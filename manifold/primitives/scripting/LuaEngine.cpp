#include "LuaEngine.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "../midi/MidiManager.h"
#include "ScriptableProcessor.h"
#include "PrimitiveGraph.h"
#include "../../core/BehaviorCoreProcessor.h"
#include "dsp/core/nodes/PrimitiveNodes.h"
#include "bindings/LuaUIBindings.h"
#include "bindings/LuaRuntimeNodeBindings.h"
#include "bindings/LuaControlBindings.h"
#include "../control/CommandParser.h"
#include "../control/ControlServer.h"
#include "../control/OSCPacketBuilder.h"
#include "../control/OSCSettingsPersistence.h"
#include "../control/OSCEndpointRegistry.h"
#include "../control/OSCQuery.h"
#include "../core/Settings.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <map>
#include <mutex>
#include <sstream>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <juce_graphics/juce_graphics.h>
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

// ============================================================================
// DSP Primitive wrappers (Phase 2)
// ============================================================================

namespace dsp_primitives {

void LoopBufferWrapper::setSize(int sizeSamples, int channels) {
  length_ = sizeSamples;
  channels_ = channels;
}

int LoopBufferWrapper::getLength() const { return length_; }
int LoopBufferWrapper::getChannels() const { return channels_; }
void LoopBufferWrapper::setCrossfade(float ms) { crossfadeMs_ = ms; }
float LoopBufferWrapper::getCrossfade() const { return crossfadeMs_; }

void PlayheadWrapper::setLoopLength(int length) { loopLength_ = length; }
int PlayheadWrapper::getLoopLength() const { return loopLength_; }
void PlayheadWrapper::setPosition(float normalized) {
  position_ = static_cast<int>(normalized * loopLength_);
}
float PlayheadWrapper::getPosition() const {
  return loopLength_ > 0 ? static_cast<float>(position_) / loopLength_ : 0.0f;
}
void PlayheadWrapper::setSpeed(float speed) { speed_ = speed; }
float PlayheadWrapper::getSpeed() const { return speed_; }
void PlayheadWrapper::setReversed(bool reversed) { reversed_ = reversed; }
bool PlayheadWrapper::isReversed() const { return reversed_; }
void PlayheadWrapper::play() { playing_ = true; }
void PlayheadWrapper::pause() { playing_ = false; }
void PlayheadWrapper::stop() { playing_ = false; position_ = 0; }

void CaptureBufferWrapper::setSize(int sizeSamples, int channels) {
  size_ = sizeSamples;
  channels_ = channels;
}
int CaptureBufferWrapper::getSize() const { return size_; }
int CaptureBufferWrapper::getChannels() const { return channels_; }
void CaptureBufferWrapper::setRecordEnabled(bool enabled) { recordEnabled_ = enabled; }
bool CaptureBufferWrapper::isRecordEnabled() const { return recordEnabled_; }
void CaptureBufferWrapper::clear() { recordEnabled_ = false; }

void QuantizerWrapper::setSampleRate(double sampleRate) { sampleRate_ = sampleRate; }
void QuantizerWrapper::setTempo(float bpm) { tempo_ = bpm; }
float QuantizerWrapper::getTempo() const { return tempo_; }

int QuantizerWrapper::getQuantizedLength(int samples) const {
  if (tempo_ <= 0.0f || sampleRate_ <= 0.0) return samples;
  float samplesPerBeat = sampleRate_ * 60.0f / tempo_;
  int beats = static_cast<int>(std::round(static_cast<float>(samples) / samplesPerBeat));
  return static_cast<int>(beats * samplesPerBeat);
}

float QuantizerWrapper::getQuantizedBars(int samples) const {
  if (tempo_ <= 0.0f || sampleRate_ <= 0.0) return 0.0f;
  float samplesPerBeat = sampleRate_ * 60.0f / tempo_;
  float samplesPerBar = samplesPerBeat * 4.0f;
  return static_cast<float>(samples) / samplesPerBar;
}

} // namespace dsp_primitives

using namespace juce::gl;

namespace {

const char *toLayerStateString(ScriptableLayerState state) {
  switch (state) {
  case ScriptableLayerState::Empty:
    return "empty";
  case ScriptableLayerState::Playing:
    return "playing";
  case ScriptableLayerState::Recording:
    return "recording";
  case ScriptableLayerState::Overdubbing:
    return "overdubbing";
  case ScriptableLayerState::Muted:
    return "muted";
  case ScriptableLayerState::Stopped:
    return "stopped";
  case ScriptableLayerState::Paused:
    return "paused";
  default:
    return "unknown";
  }
}

std::string luaEvalResultToString(const sol::object &value) {
  if (!value.valid() || value.get_type() == sol::type::nil) {
    return "";
  }

  if (value.is<std::string>()) {
    return value.as<std::string>();
  }
  if (value.is<const char *>()) {
    return std::string(value.as<const char *>());
  }
  if (value.is<bool>()) {
    return value.as<bool>() ? "true" : "false";
  }
  if (value.is<int>()) {
    return std::to_string(value.as<int>());
  }
  if (value.is<int64_t>()) {
    return std::to_string(value.as<int64_t>());
  }
  if (value.is<float>()) {
    std::ostringstream stream;
    stream << value.as<float>();
    return stream.str();
  }
  if (value.is<double>()) {
    std::ostringstream stream;
    stream << value.as<double>();
    return stream.str();
  }
  if (value.get_type() == sol::type::table) {
    return "[table]";
  }

  return "[value]";
}

bool isProjectManifestFile(const juce::File& file) {
  return file.existsAsFile() &&
         file.getFileName().equalsIgnoreCase("manifold.project.json5");
}

bool isStructuredUiFile(const juce::File& file) {
  return file.existsAsFile() &&
         file.getFileName().endsWithIgnoreCase(".ui.lua");
}

struct UiLoadTarget {
  juce::File requestedPath;
  juce::File bootstrapPath;
  juce::File projectRoot;
  juce::File manifestFile;
  juce::File structuredUiRoot;
  juce::File dspDefaultFile;
  juce::String displayName;
  bool isProject = false;
  bool isStructured = false;
  bool isSystemProject = false;  // True if project has no DSP (UI-only/system project)
  bool isOverlay = false;        // True if project should overlay on top of current (not replace)
  std::string error;
};

juce::String escapeLuaString(const juce::String& text) {
  auto s = text.replace("\\", "\\\\");
  s = s.replace("\"", "\\\"");
  s = s.replace("\n", "\\n");
  s = s.replace("\r", "\\r");
  return s;
}

juce::File resolveSystemUiDir() {
  auto& settings = Settings::getInstance();
  auto devDir = settings.getDevScriptsDir();
  if (devDir.isNotEmpty()) {
    juce::File dir(devDir);
    if (dir.isDirectory()) {
      return dir;
    }
  }

  auto defaultUiScript = settings.getDefaultUiScript();
  if (defaultUiScript.isNotEmpty()) {
    juce::File script(defaultUiScript);
    if (script.existsAsFile()) {
      return script.getParentDirectory();
    }
  }

  return {};
}

juce::File resolveProjectAssetRef(const juce::File& projectRoot,
                                  const juce::String& ref) {
  if (ref.isEmpty()) {
    return {};
  }

  juce::File absoluteCandidate(ref);
  if (juce::File::isAbsolutePath(ref)) {
    return absoluteCandidate;
  }

  auto& settings = Settings::getInstance();
  juce::File userRoot(settings.getUserScriptsDir());
  juce::File systemUiRoot = resolveSystemUiDir();
  juce::File systemDspRoot(settings.getDspScriptsDir());

  if (ref.startsWith("user:ui/")) {
    return userRoot.getChildFile("ui").getChildFile(ref.fromFirstOccurrenceOf("user:ui/", false, false));
  }
  if (ref.startsWith("user:dsp/")) {
    return userRoot.getChildFile("dsp").getChildFile(ref.fromFirstOccurrenceOf("user:dsp/", false, false));
  }
  if (ref.startsWith("system:ui/")) {
    return systemUiRoot.getChildFile(ref.fromFirstOccurrenceOf("system:ui/", false, false));
  }
  if (ref.startsWith("system:dsp/")) {
    return systemDspRoot.getChildFile(ref.fromFirstOccurrenceOf("system:dsp/", false, false));
  }

  return projectRoot.getChildFile(ref);
}

UiLoadTarget resolveUiLoadTarget(const juce::File& requestedPath) {
  UiLoadTarget target;
  target.requestedPath = requestedPath;

  if (isProjectManifestFile(requestedPath)) {
    auto json = juce::JSON::parse(requestedPath);
    if (!json.isObject()) {
      target.error = "project manifest is not valid JSON/JSON5 subset";
      return target;
    }

    auto* obj = json.getDynamicObject();
    if (obj == nullptr || !obj->hasProperty("ui")) {
      target.error = "project manifest missing ui section";
      return target;
    }

    auto uiVar = obj->getProperty("ui");
    if (!uiVar.isObject()) {
      target.error = "project manifest ui section is not an object";
      return target;
    }

    auto* uiObj = uiVar.getDynamicObject();
    if (uiObj == nullptr || !uiObj->hasProperty("root")) {
      target.error = "project manifest missing ui.root";
      return target;
    }

    auto rootRel = uiObj->getProperty("root").toString();
    if (rootRel.isEmpty()) {
      target.error = "project manifest ui.root is empty";
      return target;
    }

    const auto projectRoot = requestedPath.getParentDirectory();
    const auto uiRoot = resolveProjectAssetRef(projectRoot, rootRel);
    if (!uiRoot.existsAsFile()) {
      target.error = "project ui root does not exist: " + uiRoot.getFullPathName().toStdString();
      return target;
    }

    if (obj->hasProperty("dsp")) {
      auto dspVar = obj->getProperty("dsp");
      if (dspVar.isObject()) {
        auto* dspObj = dspVar.getDynamicObject();
        if (dspObj != nullptr && dspObj->hasProperty("default")) {
          auto dspRef = dspObj->getProperty("default").toString();
          if (dspRef.isNotEmpty()) {
            target.dspDefaultFile = resolveProjectAssetRef(projectRoot, dspRef);
          }
        }
      }
    } else {
      // No DSP section = system/UI-only project
      target.isSystemProject = true;
    }

    // Check for overlay flag in behavior section
    if (obj->hasProperty("behavior")) {
      auto behaviorVar = obj->getProperty("behavior");
      if (behaviorVar.isObject()) {
        auto* behaviorObj = behaviorVar.getDynamicObject();
        if (behaviorObj != nullptr && behaviorObj->hasProperty("isOverlay")) {
          target.isOverlay = behaviorObj->getProperty("isOverlay");
        }
      }
    }

    target.projectRoot = projectRoot;
    target.manifestFile = requestedPath;
    target.structuredUiRoot = uiRoot;
    target.bootstrapPath = uiRoot;
    target.displayName = obj->hasProperty("name")
                             ? obj->getProperty("name").toString()
                             : projectRoot.getFileName();
    if (target.displayName.isEmpty()) {
      target.displayName = projectRoot.getFileName();
    }
    target.isProject = true;
    target.isStructured = isStructuredUiFile(uiRoot);
    return target;
  }

  if (isStructuredUiFile(requestedPath)) {
    target.structuredUiRoot = requestedPath;
    target.bootstrapPath = requestedPath;
    target.projectRoot = requestedPath.getParentDirectory();
    target.displayName = requestedPath.getFileNameWithoutExtension();
    target.isStructured = true;
    return target;
  }

  target.bootstrapPath = requestedPath;
  target.displayName = requestedPath.getFileNameWithoutExtension();
  return target;
}

std::string makeStructuredUiBootstrap(const UiLoadTarget& target,
                                      const juce::File& userScriptsRoot,
                                      const juce::File& systemUiDir,
                                      const juce::File& systemDspDir,
                                      bool skipDspLoad = false) {
  std::ostringstream code;
  code << "local loader = require(\"project_loader\")\n";
  code << "loader.install({\n";
  code << "  requestedPath = \"" << escapeLuaString(target.requestedPath.getFullPathName()).toStdString() << "\",\n";
  code << "  projectRoot = \"" << escapeLuaString(target.projectRoot.getFullPathName()).toStdString() << "\",\n";
  code << "  manifestPath = \"" << escapeLuaString(target.manifestFile.getFullPathName()).toStdString() << "\",\n";
  code << "  uiRoot = \"" << escapeLuaString(target.structuredUiRoot.getFullPathName()).toStdString() << "\",\n";
  code << "  displayName = \"" << escapeLuaString(target.displayName).toStdString() << "\",\n";
  code << "  userScriptsRoot = \"" << escapeLuaString(userScriptsRoot.getFullPathName()).toStdString() << "\",\n";
  code << "  systemUiRoot = \"" << escapeLuaString(systemUiDir.getFullPathName()).toStdString() << "\",\n";
  code << "  systemDspRoot = \"" << escapeLuaString(systemDspDir.getFullPathName()).toStdString() << "\",\n";
  code << "})\n";
  if (target.dspDefaultFile.existsAsFile() && !skipDspLoad) {
    code << "if loadDspScript then loadDspScript(\""
         << escapeLuaString(target.dspDefaultFile.getFullPathName()).toStdString()
         << "\") end\n";
  }
  return code.str();
}

} // namespace

// ============================================================================
// pImpl
// ============================================================================

struct LuaEngine::Impl {
  ScriptableProcessor *processor = nullptr;
  std::shared_ptr<midi::MidiManager> midiManager;
  Canvas *rootCanvas = nullptr;
  RuntimeNode *rootRuntime = nullptr;
  RootMode rootMode = RootMode::Canvas;
  bool scriptLoaded = false;
  std::string lastError;
  juce::File currentScriptFile;

  // Hot-reload tracking
  juce::Time lastModTime;
  int hotReloadCounter = 0; // Count frames; check at ~1Hz
  static constexpr int HOT_RELOAD_CHECK_INTERVAL = 30; // frames between checks

  // Cached last window size for re-layout after hot-reload
  int lastWidth = 0;
  int lastHeight = 0;

  // Deferred script switch (to avoid use-after-free when called from Lua
  // callback)
  std::string pendingSwitchPath;

  // Shared parent shell and script content mount point
  std::string sharedUiDir;
  Canvas *scriptContentCanvasRoot = nullptr;
  RuntimeNode *scriptContentRuntimeRoot = nullptr;
  sol::table sharedShell;
  bool hasSharedShell = false;
  bool sharedShellRequireOk = false;
  bool sharedShellCreateOk = false;
  int sharedContentX = 0;
  int sharedContentY = 0;
  int sharedContentW = 0;
  int sharedContentH = 0;
  int uiScriptLoadCount = 0;
  std::string currentUiScriptPath;

  // DSP slot lifecycle policy.
  // Named slots are transient by default and are unloaded on UI switch unless
  // explicitly pinned persistent.
  std::unordered_set<std::string> managedDspSlots;
  std::unordered_set<std::string> persistentDspSlots;

  // Track if current project is a system project (no DSP)
  // to prevent unloading DSP when switching between projects
  bool currentProjectIsSystem = false;
  
  // Track the last non-system project path so we can detect when returning
  // from a system project to the same project (and skip DSP reload)
  std::string lastNonSystemProjectPath;

  // Overlay project stack - allows projects to load on top without destroying
  // the underlying project. Each entry stores the overlay's callbacks and path.
  struct OverlayEntry {
    std::string path;
    sol::function uiInit;
    sol::function uiUpdate;
    sol::function uiResized;
    sol::function uiCleanup;
    sol::function onStateChanged;
    Canvas* canvasRoot = nullptr;         // overlay's script_content_root (Canvas mode)
    RuntimeNode* runtimeRoot = nullptr;   // overlay's script_content_root (RuntimeNode mode)
    // Saved Lua globals that overlay loadScript overwrites
    sol::object savedProjectRoot;
    sol::object savedProjectManifest;
    sol::object savedStructuredUiRoot;
    sol::object savedUserScriptsRoot;
    sol::object savedSystemUiRoot;
    sol::object savedSystemDspRoot;
  };
  std::vector<OverlayEntry> overlayStack;
  
  // Base project callbacks (the underlying project when overlays are active)
  sol::function baseProjectUiUpdate;
  sol::function baseProjectUiResized;
  sol::function baseProjectOnStateChanged;
  Canvas* baseProjectCanvasRoot = nullptr;
  RuntimeNode* baseProjectRuntimeRoot = nullptr;
  bool hasBaseProjectCallbacks = false;
  bool deferredPanic = false;

  // Cache for pre-compiled overlay scripts to avoid mutex stalls during compilation
  // Key: script path, Value: compiled Lua chunk (sol::protected_function)
  std::unordered_map<std::string, sol::protected_function> overlayScriptCache;

  // UI-owned OSC custom endpoint/value bookkeeping.
  // On UI switch we remove only these paths, preserving DSP slot endpoints
  // (e.g. /core/slots/*) that must outlive a script swap.
  std::unordered_set<std::string> uiRegisteredOscEndpoints;
  std::unordered_set<std::string> uiRegisteredOscValues;

  // Primitive graph for Phase 3 wiring
  std::shared_ptr<dsp_primitives::PrimitiveGraph> primitiveGraph;

  // ============================================================================
  // OSC Callback Registry (using interface types for compatibility)
  // ============================================================================
  std::map<juce::String, std::vector<ILuaControlState::OSCCallback>> oscCallbacks;
  std::mutex oscCallbacksMutex;

  struct PendingOSCMessage {
    juce::String address;
    std::vector<juce::var> args;
  };
  std::vector<PendingOSCMessage> pendingOSCMessages;
  std::mutex pendingOSCMessagesMutex;

  std::map<juce::String, ILuaControlState::OSCQueryHandler> oscQueryHandlers;
  std::mutex oscQueryHandlersMutex;

  std::vector<std::shared_ptr<LuaEngine::EvalRequest>> pendingEvalRequests;
  std::mutex pendingEvalRequestsMutex;

  // ============================================================================
  // Looper Event Listeners (using interface types for compatibility)
  // ============================================================================
  std::vector<ILuaControlState::EventListener> tempoChangedListeners;
  std::vector<ILuaControlState::EventListener> commitListeners;
  std::vector<ILuaControlState::EventListener> recordingChangedListeners;
  std::vector<ILuaControlState::EventListener> layerStateChangedListeners;
  std::vector<ILuaControlState::EventListener> stateChangedListeners;
  std::mutex eventListenersMutex;

  // Last known state for diff detection
  float lastTempo = 0.0f;
  bool lastRecording = false;
  std::vector<int> lastLayerStates;
  int lastCommitCount = 0;
  int64_t lastFrameTimingLogCount = -1;
};

// ============================================================================
// Construction / Destruction
// ============================================================================

LuaEngine::LuaEngine() : pImpl(std::make_unique<Impl>()) {
  // CRITICAL DEBUG: This should ALWAYS print
  fprintf(stderr, "!!! LUAENGINE CONSTRUCTOR !!!\n");
  fflush(stderr);
}

LuaEngine::~LuaEngine() {
  if (pImpl && pImpl->processor) {
    pImpl->processor->getOSCServer().setLuaCallback({});
    pImpl->processor->getOSCServer().setLuaQueryCallback({});
  }
}

// ============================================================================
// Initialisation
// ============================================================================

void LuaEngine::initialise(ScriptableProcessor *processor, Canvas *rootCanvas) {
  initialiseInternal(processor,
                     rootCanvas,
                     rootCanvas != nullptr ? rootCanvas->getRuntimeNode() : nullptr,
                     RootMode::Canvas);
}

void LuaEngine::initialise(ScriptableProcessor *processor, RuntimeNode *rootRuntime) {
  initialiseInternal(processor, nullptr, rootRuntime, RootMode::RuntimeNode);
}

void LuaEngine::initialiseInternal(ScriptableProcessor *processor,
                                   Canvas *rootCanvas,
                                   RuntimeNode *rootRuntime,
                                   RootMode rootMode) {
  // CRITICAL DEBUG
  fprintf(stderr, "!!! LUAENGINE INITIALISE !!!\n");
  fflush(stderr);

  pImpl->processor = processor;
  
  // Initialize shared MidiManager if not already created
  if (!pImpl->midiManager) {
    pImpl->midiManager = std::make_shared<midi::MidiManager>();
  }
  
  // Share MidiManager with processor so it can use the same device
  if (pImpl->processor) {
    auto* bcp = dynamic_cast<BehaviorCoreProcessor*>(pImpl->processor);
    if (bcp) {
      bcp->setMidiManager(pImpl->midiManager);
    }
  }
  
  pImpl->rootCanvas = rootCanvas;
  pImpl->rootRuntime = rootRuntime;
  pImpl->rootMode = rootMode;
  pImpl->lastLayerStates.assign(
      processor ? std::max(0, processor->getNumLayers()) : 0,
      static_cast<int>(ScriptableLayerState::Unknown));

  // Initialize core engine (VM lifecycle only)
  std::fprintf(stderr, "[LuaEngine] Initializing core engine...\n");
  coreEngine_.initialize();

  // Lock Core's mutex and get reference to its Lua state
  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());

  std::fprintf(stderr, "[LuaEngine] Calling registerBindings...\n");
  registerBindings();
  std::fprintf(stderr, "[LuaEngine] registerBindings returned\n");

  // Register OSC callback to allow Lua to handle incoming OSC messages
  if (pImpl->processor) {
    pImpl->processor->getOSCServer().setLuaCallback(
        [this](const juce::String& address, const std::vector<juce::var>& args) -> bool {
          return this->invokeOSCCallback(address, args);
        });
    pImpl->processor->getOSCServer().setLuaQueryCallback(
        [this](const juce::String& path, std::vector<juce::var>& outArgs) -> bool {
          return this->invokeOSCQueryCallback(path, outArgs);
        });
  }
}

// ============================================================================
// Bindings
// ============================================================================

void LuaEngine::registerBindings() {
  std::fprintf(stderr, "[LuaEngine] registerBindings called\n");

  // Register RuntimeNode bindings before Canvas so Canvas can hand nodes to Lua.
  LuaRuntimeNodeBindings::registerBindings(coreEngine_, pImpl->rootRuntime);

  // Register Canvas, Graphics, and OpenGL bindings via LuaUIBindings module.
  // RuntimeNode-root mode still exposes Canvas bindings, but there is no root Canvas.
  LuaUIBindings::registerBindings(coreEngine_, pImpl->rootMode == RootMode::Canvas ? pImpl->rootCanvas
                                                                                    : nullptr);

  // Register control bindings (commands, OSC, events, Link, etc.)
  std::fprintf(stderr, "[LuaEngine] Calling LuaControlBindings::registerBindings...\n");
  LuaControlBindings::registerBindings(coreEngine_, *this);
  std::fprintf(stderr, "[LuaEngine] LuaControlBindings::registerBindings returned\n");

  auto &lua = coreEngine_.getLuaState();

  if (pImpl->rootMode == RootMode::Canvas) {
    lua["root"] = pImpl->rootCanvas;
  } else {
    lua["root"] = pImpl->rootRuntime;
  }
  lua["rootRuntime"] = pImpl->rootRuntime;
}

// ============================================================================
// State snapshot
// ============================================================================

void LuaEngine::pushStateToLuaFull() {
  auto *proc = pImpl->processor;
  if (!proc)
    return;

  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  proc->serializeStateToLua(coreEngine_.getLuaState());
}

void LuaEngine::pushStateToLuaIncremental(const std::vector<std::string>& changedPaths) {
  auto *proc = pImpl->processor;
  if (!proc || changedPaths.empty())
    return;

  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  proc->serializeStateToLuaIncremental(coreEngine_.getLuaState(), changedPaths);
}

// ============================================================================
// Script loading
// ============================================================================

bool LuaEngine::loadScript(const juce::File &scriptFile, bool skipDspLoad, bool isOverlay) {
  if (!scriptFile.exists()) {
    pImpl->lastError =
        "Script file not found: " + scriptFile.getFullPathName().toStdString();
    return false;
  }

  const auto target = resolveUiLoadTarget(scriptFile);
  if (!target.error.empty()) {
    pImpl->lastError = target.error;
    std::fprintf(stderr, "LuaEngine: ui target resolve error: %s\n",
                 pImpl->lastError.c_str());
    pImpl->scriptLoaded = false;
    return false;
  }

  pImpl->currentScriptFile = scriptFile;

  const auto packageDir = target.isStructured
                              ? target.structuredUiRoot.getParentDirectory()
                              : target.bootstrapPath.getParentDirectory();
  const auto systemUiDir = resolveSystemUiDir();

  coreEngine_.setPackagePath(packageDir.getFullPathName().toStdString());

  auto dir = packageDir.getFullPathName().toStdString();
  if (pImpl->sharedUiDir.empty()) {
    pImpl->sharedUiDir = systemUiDir.isDirectory()
                             ? systemUiDir.getFullPathName().toStdString()
                             : dir;
  }
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    auto packagePath = dir + "/?.lua;" + dir + "/?/init.lua";
    const auto systemUiDirPath = systemUiDir.getFullPathName().toStdString();
    if (!systemUiDirPath.empty() && systemUiDirPath != dir) {
      packagePath += ";" + systemUiDirPath + "/?.lua;" +
                     systemUiDirPath + "/?/init.lua";
    }
    if (!pImpl->sharedUiDir.empty() && pImpl->sharedUiDir != dir &&
        pImpl->sharedUiDir != systemUiDirPath) {
      packagePath += ";" + pImpl->sharedUiDir + "/?.lua;" +
                     pImpl->sharedUiDir + "/?/init.lua";
    }
    coreEngine_.getLuaState()["package"]["path"] = packagePath;
  }

  // Clear lifecycle globals so old script handlers don't leak into new scripts.
  // SKIP clearing for overlays - the underlying project keeps running.
  if (!isOverlay) {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    // Invalidate any stale base project callback refs before clearing globals.
    pImpl->baseProjectUiUpdate = sol::nil;
    pImpl->baseProjectUiResized = sol::nil;
    pImpl->baseProjectOnStateChanged = sol::nil;
    pImpl->hasBaseProjectCallbacks = false;
    
    coreEngine_.getLuaState()["ui_init"] = sol::nil;
    coreEngine_.getLuaState()["ui_update"] = sol::nil;
    coreEngine_.getLuaState()["ui_resized"] = sol::nil;
    coreEngine_.getLuaState()["ui_cleanup"] = sol::nil;
    coreEngine_.getLuaState()["shell"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldProjectRoot"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldProjectManifest"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldStructuredUiRoot"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldUserScriptsRoot"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldSystemUiRoot"] = sol::nil;
    coreEngine_.getLuaState()["__manifoldSystemDspRoot"] = sol::nil;
  }

  // For overlay loads, hide shared shell from the overlay script.
  // If shell is visible, project_loader registers performance view and hijacks
  // updates for the underlying project.
  if (isOverlay && pImpl->hasSharedShell) {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    coreEngine_.getLuaState()["shell"] = sol::nil;
  }

  bool loaded = false;
  if (target.isStructured) {
    const auto userScriptsRoot = juce::File(Settings::getInstance().getUserScriptsDir());
    const auto systemDspDir = juce::File(Settings::getInstance().getDspScriptsDir());
    const auto bootstrap = makeStructuredUiBootstrap(target, userScriptsRoot,
                                                     systemUiDir, systemDspDir,
                                                     skipDspLoad);

    // COMPILE OUTSIDE THE LOCK so MIDI callbacks don't stall during compilation.
    // load() touches lua_State internals and must be done locked, but the expensive
    // compile happens at the first protected_function call, not at load time.
    // We keep the compiled chunk on the Lua stack (as a reference) while unlocked,
    // then execute it under lock.
    sol::protected_function compiledChunk;
    {
      const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
      auto loadResult = coreEngine_.getLuaState().load(
          bootstrap, target.structuredUiRoot.getFileName().toStdString());
      if (!loadResult.valid()) {
        sol::error err = loadResult;
        pImpl->lastError = err.what();
        loaded = false;
      } else {
        compiledChunk = loadResult;
      }
    }

    if (compiledChunk.valid()) {
      // Lock only for state setup and execution (fast), not for compilation (slow).
      const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
      coreEngine_.getLuaState()["__manifoldProjectRoot"] =
          target.projectRoot.getFullPathName().toStdString();
      coreEngine_.getLuaState()["__manifoldProjectManifest"] =
          target.manifestFile.getFullPathName().toStdString();
      coreEngine_.getLuaState()["__manifoldStructuredUiRoot"] =
          target.structuredUiRoot.getFullPathName().toStdString();
      coreEngine_.getLuaState()["__manifoldUserScriptsRoot"] =
          userScriptsRoot.getFullPathName().toStdString();
      coreEngine_.getLuaState()["__manifoldSystemUiRoot"] =
          systemUiDir.getFullPathName().toStdString();
      coreEngine_.getLuaState()["__manifoldSystemDspRoot"] =
          systemDspDir.getFullPathName().toStdString();

      sol::protected_function_result result = compiledChunk();
      loaded = result.valid();
      if (!loaded) {
        sol::error err = result;
        pImpl->lastError = err.what();
      }
    }
  } else {
    loaded = coreEngine_.loadScript(target.bootstrapPath);
  }

  if (!loaded) {
    pImpl->lastError = coreEngine_.getLastError();
    std::fprintf(stderr, "LuaEngine: script load error: %s\n",
                 pImpl->lastError.c_str());
    pImpl->scriptLoaded = false;
    return false;
  }


  // Call ui_init(root) if defined
  sol::function uiInit;
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    uiInit = coreEngine_.getLuaState()["ui_init"];
  }
  if (uiInit.valid()) {
    try {
      // Build the script content mount root. Canvas mode keeps the shared shell;
      // RuntimeNode mode bypasses Canvas entirely.
      pImpl->scriptContentCanvasRoot = nullptr;
      pImpl->scriptContentRuntimeRoot = nullptr;

      if (!isOverlay) {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        pImpl->hasSharedShell = false;
        pImpl->sharedShellRequireOk = false;
        pImpl->sharedShellCreateOk = false;
        pImpl->sharedContentX = 0;
        pImpl->sharedContentY = 0;
        pImpl->sharedContentW = 0;
        pImpl->sharedContentH = 0;
      }

      if (pImpl->rootMode == RootMode::Canvas && pImpl->rootCanvas != nullptr) {
        // For overlays, don't clear existing children - add overlay UI on top
        if (!isOverlay) {
          pImpl->rootCanvas->clearChildren();
        }
        pImpl->scriptContentCanvasRoot = pImpl->rootCanvas->addChild("script_content_root");
        pImpl->scriptContentRuntimeRoot = pImpl->scriptContentCanvasRoot != nullptr
                                             ? pImpl->scriptContentCanvasRoot->getRuntimeNode()
                                             : pImpl->rootRuntime;

        if (!isOverlay) {
          const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
          sol::protected_function requireFn = coreEngine_.getLuaState()["require"];
          if (requireFn.valid()) {
            sol::protected_function_result reqRes = requireFn("ui_shell");
            if (reqRes.valid()) {
              pImpl->sharedShellRequireOk = true;
              sol::table shellModule = reqRes;
              sol::protected_function createFn = shellModule["create"];
              if (createFn.valid()) {
                sol::table opts = coreEngine_.getLuaState().create_table();
                opts["title"] = "MANIFOLD";
                sol::protected_function_result shellRes =
                    createFn(pImpl->rootCanvas, opts);
                if (shellRes.valid()) {
                  pImpl->sharedShell = shellRes.get<sol::table>();
                  pImpl->hasSharedShell = true;
                  pImpl->sharedShellCreateOk = true;
                  coreEngine_.getLuaState()["shell"] = pImpl->sharedShell;
                } else {
                  sol::error err = shellRes;
                  std::fprintf(stderr,
                               "LuaEngine: shared shell create failed: %s\n",
                               err.what());
                }
              }
            } else {
              sol::error err = reqRes;
              std::fprintf(stderr, "LuaEngine: shared shell require failed: %s\n",
                           err.what());
            }
          }
        }
      } else if (pImpl->rootRuntime != nullptr) {
        // For overlays, don't clear existing children - add overlay UI on top
        if (!isOverlay) {
          pImpl->rootRuntime->clearChildren();
        }
        pImpl->scriptContentRuntimeRoot = pImpl->rootRuntime->createChild("script_content_root");

        // Create shared shell in RuntimeNode mode (same as Canvas mode above)
        if (!isOverlay) {
          const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
          sol::protected_function requireFn = coreEngine_.getLuaState()["require"];
          if (requireFn.valid()) {
            sol::protected_function_result reqRes = requireFn("ui_shell");
            if (reqRes.valid()) {
              pImpl->sharedShellRequireOk = true;
              sol::table shellModule = reqRes;
              sol::protected_function createFn = shellModule["create"];
              if (createFn.valid()) {
                sol::table opts = coreEngine_.getLuaState().create_table();
                opts["title"] = "MANIFOLD";
                sol::protected_function_result shellRes =
                    createFn(pImpl->rootRuntime, opts);
                if (shellRes.valid()) {
                  pImpl->sharedShell = shellRes.get<sol::table>();
                  pImpl->hasSharedShell = true;
                  pImpl->sharedShellCreateOk = true;
                  coreEngine_.getLuaState()["shell"] = pImpl->sharedShell;
                } else {
                  sol::error err = shellRes;
                  std::fprintf(stderr,
                               "LuaEngine: shared shell create (RuntimeNode) failed: %s\n",
                               err.what());
                }
              }
            } else {
              sol::error err = reqRes;
              std::fprintf(stderr, "LuaEngine: shared shell require (RuntimeNode) failed: %s\n",
                           err.what());
            }
          }
        }
      }

      int contentX = 0;
      int contentY = 0;
      int contentW = pImpl->lastWidth > 0
                         ? pImpl->lastWidth
                         : (pImpl->rootMode == RootMode::Canvas && pImpl->rootCanvas != nullptr
                                ? pImpl->rootCanvas->getWidth()
                                : (pImpl->rootRuntime != nullptr ? pImpl->rootRuntime->getBounds().w : 0));
      int contentH = pImpl->lastHeight > 0
                         ? pImpl->lastHeight
                         : (pImpl->rootMode == RootMode::Canvas && pImpl->rootCanvas != nullptr
                                ? pImpl->rootCanvas->getHeight()
                                : (pImpl->rootRuntime != nullptr ? pImpl->rootRuntime->getBounds().h : 0));

      if (pImpl->hasSharedShell) {
        if (!isOverlay) {
          // Base project load: shell owns layout and content bounds.
          const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
          sol::table shell = pImpl->sharedShell;
          sol::protected_function layoutFn = shell["layout"];
          if (layoutFn.valid()) {
            layoutFn(shell, contentW, contentH);
          }
          sol::protected_function boundsFn = shell["getContentBounds"];
          if (boundsFn.valid()) {
            sol::protected_function_result boundsRes = boundsFn(shell, contentW, contentH);
            if (boundsRes.valid()) {
              auto bounds = boundsRes.get<std::tuple<int, int, int, int>>();
              contentX = std::get<0>(bounds);
              contentY = std::get<1>(bounds);
              contentW = std::get<2>(bounds);
              contentH = std::get<3>(bounds);
            }
          }

          pImpl->sharedContentX = contentX;
          pImpl->sharedContentY = contentY;
          pImpl->sharedContentW = contentW;
          pImpl->sharedContentH = contentH;
        } else {
          // Overlay load: DO NOT relayout shell (can take 100ms+ and stalls MIDI).
          // Reuse cached base content bounds.
          if (pImpl->sharedContentW > 0 && pImpl->sharedContentH > 0) {
            contentX = pImpl->sharedContentX;
            contentY = pImpl->sharedContentY;
            contentW = pImpl->sharedContentW;
            contentH = pImpl->sharedContentH;
          }
        }
      }

      // Normally shell manages content bounds. For overlays, shell manages only
      // the base project content, so overlay root must be explicitly bounded.
      if (!pImpl->hasSharedShell || isOverlay) {
        if (pImpl->scriptContentCanvasRoot != nullptr) {
          pImpl->scriptContentCanvasRoot->setBounds(contentX, contentY, contentW, contentH);
        } else if (pImpl->scriptContentRuntimeRoot != nullptr) {
          pImpl->scriptContentRuntimeRoot->setBounds(contentX, contentY, contentW, contentH);
        }
      }

      if (pImpl->processor) {
        auto& osc = pImpl->processor->getOSCServer();
        osc.setCustomValue("/ui/shell/active", { juce::var(pImpl->hasSharedShell ? 1 : 0) });
        osc.setCustomValue("/ui/shell/require_ok", { juce::var(pImpl->sharedShellRequireOk ? 1 : 0) });
        osc.setCustomValue("/ui/shell/create_ok", { juce::var(pImpl->sharedShellCreateOk ? 1 : 0) });
        osc.setCustomValue("/ui/shell/content_x", { juce::var(contentX) });
        osc.setCustomValue("/ui/shell/content_y", { juce::var(contentY) });
        osc.setCustomValue("/ui/shell/content_w", { juce::var(contentW) });
        osc.setCustomValue("/ui/shell/content_h", { juce::var(contentH) });
      }

      // Call uiInit under Lua lock for state safety.
      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        if (pImpl->rootMode == RootMode::Canvas) {
          result = uiInit(pImpl->scriptContentCanvasRoot != nullptr ? pImpl->scriptContentCanvasRoot
                                                                    : pImpl->rootCanvas);
        } else {
          result = uiInit(pImpl->scriptContentRuntimeRoot != nullptr ? pImpl->scriptContentRuntimeRoot
                                                                     : pImpl->rootRuntime);
        }
      }
      if (!result.valid()) {
        sol::error err = result;
        pImpl->lastError = err.what();
        std::fprintf(stderr, "LuaEngine: ui_init error: %s\n",
                     pImpl->lastError.c_str());
        pImpl->scriptLoaded = false;
        return false;
      }
    } catch (const std::exception &e) {
      pImpl->lastError = e.what();
      std::fprintf(stderr, "LuaEngine: ui_init exception: %s\n",
                   pImpl->lastError.c_str());
      pImpl->scriptLoaded = false;
      return false;
    }
  }

  pushStateToLuaFull();
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    if (pImpl->hasSharedShell) {
      sol::table shell = pImpl->sharedShell;
      sol::protected_function shellStateChanged = shell["onStateChanged"];
      if (shellStateChanged.valid()) {
        sol::protected_function_result shellRes = shellStateChanged(shell, sol::nil);
        if (!shellRes.valid()) {
          sol::error err = shellRes;
          std::fprintf(stderr, "LuaEngine: shell onStateChanged init error: %s\n", err.what());
        }
      }
    }
  }
  if (pImpl->processor != nullptr) {
    pImpl->processor->updateChangeCache();
  }

  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    if (pImpl->hasSharedShell) {
      sol::table shell = pImpl->sharedShell;
      sol::protected_function flushDeferredRefreshes = shell["flushDeferredRefreshes"];
      if (flushDeferredRefreshes.valid()) {
        sol::protected_function_result flushRes = flushDeferredRefreshes(shell);
        if (!flushRes.valid()) {
          sol::error err = flushRes;
          std::fprintf(stderr, "LuaEngine: shell flushDeferredRefreshes init error: %s\n", err.what());
        }
      }
    }
  }

  pImpl->scriptLoaded = true;
  pImpl->lastError.clear();
  pImpl->lastModTime = scriptFile.getLastModificationTime();
  pImpl->uiScriptLoadCount += 1;
  pImpl->currentUiScriptPath = scriptFile.getFullPathName().toStdString();

  if (pImpl->processor) {
    auto& osc = pImpl->processor->getOSCServer();
    osc.setCustomValue("/ui/shell/current_script",
                       { juce::var(pImpl->currentUiScriptPath) });
    osc.setCustomValue("/ui/shell/script_load_count",
                       { juce::var(pImpl->uiScriptLoadCount) });
    osc.setCustomValue("/ui/shell/last_error", { juce::var("") });
  }

  std::fprintf(stderr, "LuaEngine: loaded script: %s\n",
               scriptFile.getFullPathName().toRawUTF8());
  return true;
}

// ============================================================================
// Notifications
// ============================================================================

void LuaEngine::notifyResized(int width, int height) {
  pImpl->lastWidth = width;
  pImpl->lastHeight = height;

  if (pImpl->rootMode == RootMode::RuntimeNode && pImpl->rootRuntime != nullptr) {
    pImpl->rootRuntime->setBounds(0, 0, width, height);
  }

  int contentX = 0;
  int contentY = 0;
  int contentW = width;
  int contentH = height;
  const bool overlayActive = !pImpl->overlayStack.empty();

  if (pImpl->hasSharedShell) {
    if (!overlayActive) {
      // Base-only mode: shell owns layout and content bounds.
      const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
      sol::table shell = pImpl->sharedShell;
      sol::protected_function layoutFn = shell["layout"];
      if (layoutFn.valid()) {
        sol::protected_function_result layoutRes = layoutFn(shell, width, height);
        if (!layoutRes.valid()) {
          sol::error err = layoutRes;
          std::fprintf(stderr, "LuaEngine: shell layout error: %s\n", err.what());
        }
      }

      sol::protected_function boundsFn = shell["getContentBounds"];
      if (boundsFn.valid()) {
        sol::protected_function_result boundsRes = boundsFn(shell, width, height);
        if (boundsRes.valid()) {
          auto bounds = boundsRes.get<std::tuple<int, int, int, int>>();
          contentX = std::get<0>(bounds);
          contentY = std::get<1>(bounds);
          contentW = std::get<2>(bounds);
          contentH = std::get<3>(bounds);
        } else {
          sol::error err = boundsRes;
          std::fprintf(stderr, "LuaEngine: shell bounds error: %s\n", err.what());
        }
      }

      pImpl->sharedContentX = contentX;
      pImpl->sharedContentY = contentY;
      pImpl->sharedContentW = contentW;
      pImpl->sharedContentH = contentH;
    } else {
      // Overlay active: don't relayout shell on resize/switch.
      // Reuse cached base content bounds to avoid long layout stalls.
      if (pImpl->sharedContentW > 0 && pImpl->sharedContentH > 0) {
        contentX = pImpl->sharedContentX;
        contentY = pImpl->sharedContentY;
        contentW = pImpl->sharedContentW;
        contentH = pImpl->sharedContentH;
      }
    }
  }

  // Position script content when shell is absent OR overlays are active.
  // In overlay mode, shell manages base content but not overlay container bounds.
  if (!pImpl->hasSharedShell || overlayActive) {
    if (pImpl->scriptContentCanvasRoot != nullptr) {
      pImpl->scriptContentCanvasRoot->setBounds(contentX, contentY, contentW, contentH);
    } else if (pImpl->scriptContentRuntimeRoot != nullptr) {
      pImpl->scriptContentRuntimeRoot->setBounds(contentX, contentY, contentW, contentH);
    }
  }

  if (pImpl->processor) {
    auto& osc = pImpl->processor->getOSCServer();
    osc.setCustomValue("/ui/shell/active", { juce::var(pImpl->hasSharedShell ? 1 : 0) });
    osc.setCustomValue("/ui/shell/content_x", { juce::var(contentX) });
    osc.setCustomValue("/ui/shell/content_y", { juce::var(contentY) });
    osc.setCustomValue("/ui/shell/content_w", { juce::var(contentW) });
    osc.setCustomValue("/ui/shell/content_h", { juce::var(contentH) });
  }

  if (!pImpl->scriptLoaded)
    return;

  sol::function fn;
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    fn = coreEngine_.getLuaState()["ui_resized"];
  }
  if (fn.valid()) {
    try {
      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        result = fn(contentW, contentH);
      }
      if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaEngine: ui_resized error: %s\n", err.what());
      }
    } catch (const std::exception &e) {
      std::fprintf(stderr, "LuaEngine: ui_resized exception: %s\n", e.what());
    }
  }
}

void LuaEngine::notifyUpdate() {
  if (!pImpl->scriptLoaded)
    return;

  // Process deferred script switch
  if (!pImpl->pendingSwitchPath.empty()) {
    auto path = pImpl->pendingSwitchPath;
    pImpl->pendingSwitchPath.clear();

    // In BehaviorCore, graph processing is the audio engine and must remain
    // enabled across UI switches.

    auto file = juce::File(path);
    if (file.existsAsFile()) {
      switchScript(file);
    } else {
      std::fprintf(stderr, "LuaEngine: switchUiScript: file not found: %s\n",
                   path.c_str());
    }
    return; // Skip this frame's update — the new script will get updated next
            // tick
  }

  // Run deferred panic after overlay close (must happen outside closeOverlay lock)
  if (pImpl->deferredPanic) {
    pImpl->deferredPanic = false;
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    auto& lua = coreEngine_.getLuaState();
    sol::object panicObj = lua["__midiSynthPanic"];
    if (panicObj.get_type() == sol::type::function) {
      sol::protected_function panicFn = panicObj.as<sol::protected_function>();
      auto panicRes = panicFn();
      if (!panicRes.valid()) {
        sol::error err = panicRes;
        std::fprintf(stderr, "LuaEngine: deferred __midiSynthPanic error: %s\n", err.what());
      } else {
        std::fprintf(stderr, "LuaEngine: deferred __midiSynthPanic OK\n");
      }
    }
  }

  // Check for hot-reload at ~1Hz
  checkHotReload();

  // Process queued OSC callbacks on message thread
  processPendingOSCCallbacks();
  processPendingEvalRequests();

  using Clock = std::chrono::steady_clock;

  int64_t pushStateUs = 0;
  int64_t eventListenersUs = 0;
  int64_t uiUpdateUs = 0;

  std::vector<std::string> changedPaths;
  if (auto* proc = pImpl->processor) {
    const auto start = Clock::now();
    changedPaths = proc->getChangedPathsAndUpdateCache();
    if (!changedPaths.empty()) {
      pushStateToLuaIncremental(changedPaths);
    }
    pushStateUs = std::chrono::duration_cast<std::chrono::microseconds>(
                      Clock::now() - start)
                      .count();
  }

  {
    const auto start = Clock::now();
    invokeEventListeners();
    eventListenersUs = std::chrono::duration_cast<std::chrono::microseconds>(
                           Clock::now() - start)
                           .count();
  }

  frameTimings.pushState.currentUs.store(pushStateUs, std::memory_order_relaxed);
  frameTimings.eventListeners.currentUs.store(eventListenersUs,
                                              std::memory_order_relaxed);

  const auto uiUpdateStart = Clock::now();

  try {
    if (!changedPaths.empty()) {
      const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
      auto& lua = coreEngine_.getLuaState();
      sol::table pathsTable = lua.create_table();
      for (size_t i = 0; i < changedPaths.size(); ++i) {
        pathsTable[static_cast<int>(i + 1)] = changedPaths[i];
      }

      if (pImpl->hasSharedShell) {
        sol::table shell = pImpl->sharedShell;
        sol::protected_function shellStateChanged = shell["onStateChanged"];
        if (shellStateChanged.valid()) {
          sol::protected_function_result shellRes = shellStateChanged(shell, pathsTable);
          if (!shellRes.valid()) {
            sol::error err = shellRes;
            std::fprintf(stderr, "LuaEngine: shell onStateChanged error: %s\n", err.what());
          }
        }
      }

      sol::protected_function onStateChanged = lua["onStateChanged"];
      if (onStateChanged.valid()) {
        sol::protected_function_result stateChangedRes = onStateChanged(pathsTable);
        if (!stateChangedRes.valid()) {
          sol::error err = stateChangedRes;
          std::fprintf(stderr, "LuaEngine: onStateChanged error: %s\n", err.what());
        }
      }
    }

    // Call current (top) project's ui_update
    sol::protected_function fn;
    {
      const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
      fn = coreEngine_.getLuaState()["ui_update"];
    }
    if (fn.valid()) {
      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        result = fn();
      }
      if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaEngine: ui_update error: %s\n", err.what());
      }
    }
    
    // When overlays are active, explicitly tick shared shell state each frame.
    // Rationale: Main project often runs via shell performance view; if we only
    // drive shell:onStateChanged on changedPaths, Main update can starve.
    if (!pImpl->overlayStack.empty() && pImpl->hasSharedShell) {
      try {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        sol::table shell = pImpl->sharedShell;
        sol::protected_function shellStateChanged = shell["onStateChanged"];
        if (shellStateChanged.valid()) {
          sol::protected_function_result shellRes = shellStateChanged(shell, sol::nil);
          if (!shellRes.valid()) {
            sol::error err = shellRes;
            std::fprintf(stderr, "LuaEngine: shell onStateChanged overlay tick error: %s\n", err.what());
          }
        }
      } catch (const std::exception &e) {
        std::fprintf(stderr, "LuaEngine: shell overlay tick exception: %s\n", e.what());
      }
    }

    // Call overlay stack callbacks in order (base first, then overlays)
    // This ensures base project MIDI/envelopes keep running
    for (const auto& entry : pImpl->overlayStack) {
      if (entry.uiUpdate.valid()) {
        try {
          sol::protected_function_result overlayResult = entry.uiUpdate();
          if (!overlayResult.valid()) {
            sol::error err = overlayResult;
            std::fprintf(stderr, "LuaEngine: overlay ui_update error: %s\n", err.what());
          }
        } catch (const std::exception &e) {
          std::fprintf(stderr, "LuaEngine: overlay ui_update exception: %s\n", e.what());
        }
      }
    }
    
    // Legacy: also call baseProject callbacks for system-project compatibility.
    // Only safe when overlays are active (functions stay alive in same Lua state).
    // After overlay close or script reload, these refs may be stale.
    if (pImpl->hasBaseProjectCallbacks && !pImpl->overlayStack.empty()) {
      if (pImpl->baseProjectUiUpdate.valid()) {
        try {
          sol::protected_function_result baseResult = pImpl->baseProjectUiUpdate();
          if (!baseResult.valid()) {
            sol::error err = baseResult;
            std::fprintf(stderr, "LuaEngine: base project ui_update error: %s\n", err.what());
          }
        } catch (const std::exception &e) {
          std::fprintf(stderr, "LuaEngine: base project ui_update exception: %s\n", e.what());
        }
      }
    }
  } catch (const std::exception &e) {
    std::fprintf(stderr, "LuaEngine: ui_update exception: %s\n", e.what());
  }

  uiUpdateUs = std::chrono::duration_cast<std::chrono::microseconds>(
                   Clock::now() - uiUpdateStart)
                   .count();
  frameTimings.uiUpdate.currentUs.store(uiUpdateUs, std::memory_order_relaxed);

  const int64_t frameCount =
      frameTimings.frameCount.load(std::memory_order_relaxed);
  if (frameCount > 0 && (frameCount % 150) == 0 &&
      frameCount != pImpl->lastFrameTimingLogCount) {
    pImpl->lastFrameTimingLogCount = frameCount;

    const int64_t totalUs = frameTimings.total.currentUs.load(std::memory_order_relaxed);
    const int64_t paintUs = frameTimings.paint.currentUs.load(std::memory_order_relaxed);
    const int64_t peakUs = frameTimings.total.peakUs.load(std::memory_order_relaxed);
    const int64_t avgUsX100 = frameTimings.total.avgUsX100.load(std::memory_order_relaxed);

    std::fprintf(stderr,
                 "FrameTiming[%lld]: total=%lldus pushState=%lldus events=%lldus "
                 "uiUpdate=%lldus paint=%lldus peak=%lldus avg=%.1fus\n",
                 static_cast<long long>(frameCount),
                 static_cast<long long>(totalUs),
                 static_cast<long long>(pushStateUs),
                 static_cast<long long>(eventListenersUs),
                 static_cast<long long>(uiUpdateUs),
                 static_cast<long long>(paintUs),
                 static_cast<long long>(peakUs),
                 static_cast<double>(avgUsX100) / 100.0);
    std::fflush(stderr);
  }
}

bool LuaEngine::isScriptLoaded() const { return coreEngine_.isScriptLoaded(); }

bool LuaEngine::isInitialized() const { return coreEngine_.isInitialized(); }

const std::string &LuaEngine::getLastError() const { return coreEngine_.getLastError(); }

juce::File LuaEngine::getScriptDirectory() const {
  if (pImpl->currentScriptFile.existsAsFile())
    return pImpl->currentScriptFile.getParentDirectory();
  return {};
}

std::shared_ptr<LuaEngine::EvalRequest>
LuaEngine::queueEval(const std::string &code) {
  auto request = std::make_shared<EvalRequest>(code);
  std::lock_guard<std::mutex> lock(pImpl->pendingEvalRequestsMutex);
  pImpl->pendingEvalRequests.push_back(request);
  return request;
}

// ============================================================================
// Script switching / hot-reload
// ============================================================================

bool LuaEngine::switchScript(const juce::File &scriptFile) {
  // BUG: This disables the graph on every UI switch, which kills all audio
  // in BehaviorCore where the looper IS the graph. In legacy LooperProcessor
  // this was safe because loops lived in C++ ManifoldLayer objects independent
  // of the graph. Must not disable here.
  // See: agent-docs/PERSISTENT_GRAPH_ARCHITECTURE.md
  //
  // if (pImpl->processor) {
  //   pImpl->processor->setGraphProcessingEnabled(false);
  // }

  // Check if target is a system project (no DSP) - if so, don't touch DSP at all
  const auto target = resolveUiLoadTarget(scriptFile);
  const bool isSystemProject = target.isSystemProject;

  // When entering a system project from a non-system project, remember the
  // source project so we can avoid reloading its DSP on return.
  if (isSystemProject && !pImpl->currentProjectIsSystem &&
      pImpl->currentScriptFile.existsAsFile()) {
    pImpl->lastNonSystemProjectPath =
        pImpl->currentScriptFile.getFullPathName().toStdString();
  }

  // Handle overlay projects - they push onto the stack instead of replacing
  const bool isOverlay = target.isOverlay;
  const bool hasOverlays = !pImpl->overlayStack.empty();

  const std::string requestedPath = scriptFile.getFullPathName().toStdString();
  const std::string requestedManifestPath = target.manifestFile.existsAsFile()
                                                ? target.manifestFile.getFullPathName().toStdString()
                                                : requestedPath;

  std::fprintf(stderr,
               "LuaEngine: switchScript req=%s manifest=%s current=%s isOverlay=%d overlays=%zu\n",
               requestedPath.c_str(),
               requestedManifestPath.c_str(),
               pImpl->currentScriptFile.getFullPathName().toStdString().c_str(),
               isOverlay ? 1 : 0,
               pImpl->overlayStack.size());
  
  if (isOverlay) {
    // Switching TO an overlay - save current project callbacks to base or stack
    std::fprintf(stderr, "LuaEngine: entering overlay project '%s'\n", 
                 target.displayName.toRawUTF8());
    
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    auto& lua = coreEngine_.getLuaState();
    
    // Save current callbacks, UI tree root, and Lua globals the overlay will overwrite
    Impl::OverlayEntry entry;
    entry.path = pImpl->currentScriptFile.getFullPathName().toStdString();
    entry.uiUpdate = lua["ui_update"];
    entry.uiResized = lua["ui_resized"];
    entry.uiCleanup = lua["ui_cleanup"];
    entry.onStateChanged = lua["onStateChanged"];
    entry.canvasRoot = pImpl->scriptContentCanvasRoot;
    entry.runtimeRoot = pImpl->scriptContentRuntimeRoot;
    entry.savedProjectRoot = lua["__manifoldProjectRoot"];
    entry.savedProjectManifest = lua["__manifoldProjectManifest"];
    entry.savedStructuredUiRoot = lua["__manifoldStructuredUiRoot"];
    entry.savedUserScriptsRoot = lua["__manifoldUserScriptsRoot"];
    entry.savedSystemUiRoot = lua["__manifoldSystemUiRoot"];
    entry.savedSystemDspRoot = lua["__manifoldSystemDspRoot"];
    
    // Save base project roots on first overlay push
    if (pImpl->overlayStack.empty()) {
      pImpl->baseProjectCanvasRoot = pImpl->scriptContentCanvasRoot;
      pImpl->baseProjectRuntimeRoot = pImpl->scriptContentRuntimeRoot;
    }
    
    pImpl->overlayStack.push_back(std::move(entry));
    
    // Don't call ui_cleanup - underlying project keeps running
    // Don't clear UI tree - overlay will render on top
  } else if (hasOverlays && !pImpl->currentProjectIsSystem) {
    // Switching to a NON-overlay project while overlays are active
    // Pop all overlays and clean them up
    std::fprintf(stderr, "LuaEngine: popping %zu overlay(s) for non-overlay switch\n",
                 pImpl->overlayStack.size());
    
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    
    // Call cleanup on all overlays in reverse order
    for (auto it = pImpl->overlayStack.rbegin(); it != pImpl->overlayStack.rend(); ++it) {
      if (it->uiCleanup.valid()) {
        try {
          auto result = it->uiCleanup();
          if (!result.valid()) {
            sol::error err = result;
            std::fprintf(stderr, "LuaEngine: overlay ui_cleanup error: %s\n", err.what());
          }
        } catch (const std::exception &e) {
          std::fprintf(stderr, "LuaEngine: overlay ui_cleanup exception: %s\n", e.what());
        }
      }
    }
    pImpl->overlayStack.clear();
    
    // Now normal cleanup for the current (non-overlay) project
    sol::protected_function cleanup = coreEngine_.getLuaState()["ui_cleanup"];
    if (cleanup.valid()) {
      try {
        auto result = cleanup();
        if (!result.valid()) {
          sol::error err = result;
          std::fprintf(stderr, "LuaEngine: ui_cleanup error: %s\n", err.what());
        }
      } catch (const std::exception &e) {
        std::fprintf(stderr, "LuaEngine: ui_cleanup exception: %s\n", e.what());
      }
    }
  } else if (!isSystemProject) {
    // Normal switch to non-overlay, non-system project
    sol::protected_function cleanup = coreEngine_.getLuaState()["ui_cleanup"];
    if (cleanup.valid()) {
      try {
        auto result = cleanup();
        if (!result.valid()) {
          sol::error err = result;
          std::fprintf(stderr, "LuaEngine: ui_cleanup error: %s\n", err.what());
        }
      } catch (const std::exception &e) {
        std::fprintf(stderr, "LuaEngine: ui_cleanup exception: %s\n", e.what());
      }
    }
    pImpl->overlayStack.clear();
  } else {
    // Switching TO a system project (not marked as overlay) - legacy behavior
    // Save callbacks so user project keeps running
    std::fprintf(stderr, "LuaEngine: saving callbacks for system project entry\n");
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    auto& lua = coreEngine_.getLuaState();
    pImpl->baseProjectUiUpdate = lua["ui_update"];
    pImpl->baseProjectUiResized = lua["ui_resized"];
    pImpl->baseProjectOnStateChanged = lua["onStateChanged"];
    pImpl->hasBaseProjectCallbacks = pImpl->baseProjectUiUpdate.valid() || 
                                      pImpl->baseProjectUiResized.valid() ||
                                      pImpl->baseProjectOnStateChanged.valid();
  }

  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    if (pImpl->hasSharedShell) {
      sol::table shell = pImpl->sharedShell;
      sol::protected_function clearDeferredRefreshes = shell["clearDeferredRefreshes"];
      if (clearDeferredRefreshes.valid()) {
        auto clearRes = clearDeferredRefreshes(shell);
        if (!clearRes.valid()) {
          sol::error err = clearRes;
          std::fprintf(stderr, "LuaEngine: shell clearDeferredRefreshes switch error: %s\n", err.what());
        }
      }
    }
  }

  // Clear the current UI before touching transient DSP slots.
  // SKIP clearing when switching TO an overlay - it renders on top of existing UI.
  // Some UI trees keep callbacks/overlays alive long enough that unloading DSP
  // first can trip use-after-free style crashes during the same switch.
  if (!isOverlay) {
    if (pImpl->rootMode == RootMode::Canvas) {
      if (pImpl->rootCanvas != nullptr) {
        pImpl->rootCanvas->clearChildren();
      }
    } else if (pImpl->rootRuntime != nullptr) {
      pImpl->rootRuntime->clearChildren();
    }
  } else {
    std::fprintf(stderr, "LuaEngine: overlay mode - preserving base project UI\n");
    // For overlays, we create a dedicated container child for the overlay UI
    // The base project UI remains in the root's other children
    if (pImpl->rootMode == RootMode::Canvas && pImpl->rootCanvas != nullptr) {
      // Create or get the overlay container (last child if it's an overlay container)
      // We'll let the overlay script create its own root widget as a child
    }
  }

  // Enforce transient-by-default DSP-slot policy.
  // Any managed slot is unloaded on UI switch unless explicitly marked
  // persistent via setDspSlotPersistOnUiSwitch(slot, true).
  //
  // SKIP unloading when:
  // 1. Switching TO a system project (UI-only, no DSP) - don't unload existing DSP
  // 2. Switching FROM a system project - the system project doesn't own any DSP,
  //    so preserve whatever was running before
  bool shouldSkipUnload = isSystemProject || pImpl->currentProjectIsSystem;

  // Track if we're returning from a system project to the same non-system project.
  // In this case, we skip DSP loading because the DSP is already running.
  bool isReturningToSameProject = false;
  if (pImpl->currentProjectIsSystem && !isSystemProject) {
    // We're switching FROM a system project TO a non-system project
    // Check if it's the same project we were running before the system project
    juce::String targetPath = scriptFile.getFullPathName();
    juce::String lastPath(pImpl->lastNonSystemProjectPath);
    isReturningToSameProject = (targetPath == lastPath);
    if (isReturningToSameProject) {
      std::fprintf(stderr, "LuaEngine: returning to same project '%s', will skip DSP reload\n",
                   pImpl->lastNonSystemProjectPath.c_str());
    }
  }

  // If switching to a non-system project (normal case), save its path for
  // future system-project roundtrips. Do NOT overwrite when we're returning
  // from system->non-system before comparison logic above has been used.
  if (!isSystemProject && !pImpl->currentProjectIsSystem) {
    pImpl->lastNonSystemProjectPath = scriptFile.getFullPathName().toStdString();
  }

  if (!shouldSkipUnload && pImpl->processor && !pImpl->managedDspSlots.empty()) {
    std::vector<std::string> slotsToUnload;
    slotsToUnload.reserve(pImpl->managedDspSlots.size());

    for (const auto &slot : pImpl->managedDspSlots) {
      if (slot == "default") {
        continue;
      }
      if (pImpl->persistentDspSlots.find(slot) !=
          pImpl->persistentDspSlots.end()) {
        continue;
      }
      slotsToUnload.push_back(slot);
    }

    for (const auto &slot : slotsToUnload) {
      const bool unloaded = pImpl->processor->unloadDspSlot(slot);
      const bool stillLoaded = pImpl->processor->isDspSlotLoaded(slot);
      if (!unloaded && stillLoaded) {
        std::fprintf(
            stderr,
            "LuaEngine: failed to unload transient DSP slot on UI switch: %s\n",
            slot.c_str());
      }
      if (!stillLoaded) {
        pImpl->managedDspSlots.erase(slot);
        pImpl->persistentDspSlots.erase(slot);
      }
    }
  }
  
  // Update the current project type for next switch
  pImpl->currentProjectIsSystem = isSystemProject;

  // Clear non-persistent callbacks before switching scripts
  clearNonPersistentCallbacks();

  if (pImpl->processor) {
    for (const auto& endpointPath : pImpl->uiRegisteredOscEndpoints) {
      const juce::String path(endpointPath);
      pImpl->processor->getEndpointRegistry().unregisterCustomEndpoint(path);
      pImpl->processor->getOSCServer().removeCustomValue(path);
    }

    for (const auto& valuePath : pImpl->uiRegisteredOscValues) {
      pImpl->processor->getOSCServer().removeCustomValue(juce::String(valuePath));
    }

    pImpl->uiRegisteredOscEndpoints.clear();
    pImpl->uiRegisteredOscValues.clear();
    pImpl->processor->getOSCQueryServer().rebuildTree();
  }

  pImpl->scriptLoaded = false;

  // Reload into the same Lua VM (bindings are still registered)
  // Skip DSP load if we're returning to the same project (DSP already running)
  bool ok = loadScript(scriptFile, isReturningToSameProject, isOverlay);
  if (ok && pImpl->lastWidth > 0 && pImpl->lastHeight > 0) {
    notifyResized(pImpl->lastWidth, pImpl->lastHeight);
  }
  return ok;
}

bool LuaEngine::reloadCurrentScript() {
  if (!pImpl->currentScriptFile.exists()) {
    return false;
  }

  std::fprintf(stderr, "LuaEngine: hot-reloading %s\n",
               pImpl->currentScriptFile.getFullPathName().toRawUTF8());
  return switchScript(pImpl->currentScriptFile);
}

std::vector<std::pair<std::string, std::string>>
LuaEngine::getAvailableScripts(const juce::File &directory) const {
  std::vector<std::pair<std::string, std::string>> result;
  if (!directory.isDirectory())
    return result;

  for (const auto &entry :
       juce::RangedDirectoryIterator(directory, false, "*.lua")) {
    auto file = entry.getFile();
    auto name = file.getFileNameWithoutExtension().toStdString();
    // Only include files that look like UI scripts (contain ui_init)
    auto content = file.loadFileAsString();
    if (content.contains("ui_init")) {
      result.push_back({name, file.getFullPathName().toStdString()});
    }
  }

  // Sort alphabetically
  std::sort(result.begin(), result.end(),
            [](const auto &a, const auto &b) { return a.first < b.first; });
  return result;
}

void LuaEngine::checkHotReload() {
  if (++pImpl->hotReloadCounter < Impl::HOT_RELOAD_CHECK_INTERVAL)
    return;
  pImpl->hotReloadCounter = 0;

  // Structured UI projects intentionally do NOT auto-reload on file save.
  // Their contract is explicit reload/switch: navigate away and back, or hit
  // the reload action / IPC command. We still want dependency invalidation on
  // those explicit reload paths, just not eager reload while editing.
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    sol::object structuredRuntime = coreEngine_.getLuaState()["__manifoldStructuredUiRuntime"];
    if (structuredRuntime.valid() && structuredRuntime.get_type() == sol::type::table) {
      return;
    }
  }

  if (!pImpl->currentScriptFile.existsAsFile())
    return;

  auto modTime = pImpl->currentScriptFile.getLastModificationTime();
  if (modTime != pImpl->lastModTime && pImpl->lastModTime != juce::Time()) {
    pImpl->lastModTime = modTime;
    std::fprintf(stderr, "LuaEngine: hot-reloading %s\n",
                 pImpl->currentScriptFile.getFullPathName().toRawUTF8());
    pImpl->pendingSwitchPath = pImpl->currentScriptFile.getFullPathName().toStdString();
  }
}

// ============================================================================
// OSC Callback Invocation (called from OSCServer receive thread)
// ============================================================================

bool LuaEngine::invokeOSCCallback(const juce::String& address,
                                  const std::vector<juce::var>& args) {
  // OSC thread only enqueues. Lua callbacks run on message thread in
  // processPendingOSCCallbacks() to avoid cross-thread Lua/UI access.
  {
    std::lock_guard<std::mutex> lock(pImpl->oscCallbacksMutex);
    auto it = pImpl->oscCallbacks.find(address);
    if (it == pImpl->oscCallbacks.end() || it->second.empty()) {
      return false;
    }
  }

  {
    std::lock_guard<std::mutex> queueLock(pImpl->pendingOSCMessagesMutex);
    if (pImpl->pendingOSCMessages.size() >= 512) {
      pImpl->pendingOSCMessages.erase(pImpl->pendingOSCMessages.begin());
    }
    pImpl->pendingOSCMessages.push_back({address, args});
  }

  return true;
}

bool LuaEngine::invokeOSCQueryCallback(const juce::String& path,
                                       std::vector<juce::var>& outArgs) {
  ILuaControlState::OSCQueryHandler handler;
  {
    std::lock_guard<std::mutex> mapLock(pImpl->oscQueryHandlersMutex);
    auto it = pImpl->oscQueryHandlers.find(path);
    if (it == pImpl->oscQueryHandlers.end() || !it->second.func.valid()) {
      return false;
    }
    handler = it->second;
  }

  const std::lock_guard<std::recursive_mutex> luaLock(coreEngine_.getMutex());

  try {
    sol::protected_function_result result = handler.func(path.toStdString());
    if (!result.valid()) {
      sol::error err = result;
      std::fprintf(stderr, "LuaEngine: OSC query callback error for %s: %s\n",
                   path.toRawUTF8(), err.what());
      return false;
    }

    sol::object value = result.get<sol::object>();
    if (!value.valid() || value.get_type() == sol::type::nil) {
      return false;
    }

    outArgs.clear();
    if (value.is<bool>()) {
      outArgs.emplace_back(value.as<bool>() ? 1 : 0);
      return true;
    }
    if (value.is<int>()) {
      outArgs.emplace_back(value.as<int>());
      return true;
    }
    if (value.is<float>()) {
      outArgs.emplace_back(value.as<float>());
      return true;
    }
    if (value.is<double>()) {
      outArgs.emplace_back(static_cast<float>(value.as<double>()));
      return true;
    }
    if (value.is<std::string>()) {
      outArgs.emplace_back(juce::String(value.as<std::string>().c_str()));
      return true;
    }
    if (value.get_type() == sol::type::table) {
      sol::table tbl = value;
      for (int i = 1;; ++i) {
        sol::object item = tbl[i];
        if (!item.valid() || item.get_type() == sol::type::nil) {
          break;
        }
        if (item.is<bool>()) outArgs.emplace_back(item.as<bool>() ? 1 : 0);
        else if (item.is<int>()) outArgs.emplace_back(item.as<int>());
        else if (item.is<float>()) outArgs.emplace_back(item.as<float>());
        else if (item.is<double>()) outArgs.emplace_back(static_cast<float>(item.as<double>()));
        else if (item.is<std::string>()) outArgs.emplace_back(juce::String(item.as<std::string>().c_str()));
      }
      return !outArgs.empty();
    }
  } catch (const sol::error& e) {
    std::fprintf(stderr, "LuaEngine: OSC query callback exception for %s: %s\n",
                 path.toRawUTF8(), e.what());
  }

  return false;
}

void LuaEngine::processPendingOSCCallbacks() {
  std::vector<Impl::PendingOSCMessage> messages;
  {
    std::lock_guard<std::mutex> queueLock(pImpl->pendingOSCMessagesMutex);
    if (pImpl->pendingOSCMessages.empty()) {
      return;
    }
    messages.swap(pImpl->pendingOSCMessages);
  }

  const std::lock_guard<std::recursive_mutex> luaLock(coreEngine_.getMutex());
  auto &lua = coreEngine_.getLuaState();

  for (const auto& message : messages) {
    std::vector<ILuaControlState::OSCCallback> callbacksToInvoke;
    {
      std::lock_guard<std::mutex> cbLock(pImpl->oscCallbacksMutex);
      auto it = pImpl->oscCallbacks.find(message.address);
      if (it == pImpl->oscCallbacks.end() || it->second.empty()) {
        continue;
      }
      callbacksToInvoke = it->second;
    }

    auto argsTable = lua.create_table();
    for (size_t i = 0; i < message.args.size(); ++i) {
      const auto& arg = message.args[i];
      if (arg.isInt() || arg.isInt64()) {
        argsTable[i + 1] = arg.toString().getDoubleValue();
      } else if (arg.isDouble()) {
        argsTable[i + 1] = arg.operator double();
      } else if (arg.isString()) {
        argsTable[i + 1] = arg.toString().toStdString();
      } else if (arg.isBool()) {
        argsTable[i + 1] = arg.operator bool();
      } else {
        argsTable[i + 1] = sol::nil;
      }
    }

    for (const auto& cb : callbacksToInvoke) {
      if (!cb.func.valid()) {
        continue;
      }
      try {
        auto result = cb.func(argsTable);
        if (!result.valid()) {
          sol::error err = result;
          std::fprintf(stderr, "LuaEngine: OSC callback error for %s: %s\n",
                       message.address.toRawUTF8(), err.what());
        }
      } catch (const sol::error& e) {
        std::fprintf(stderr, "LuaEngine: OSC callback exception for %s: %s\n",
                     message.address.toRawUTF8(), e.what());
      }
    }
  }
}

void LuaEngine::processPendingEvalRequests() {
  std::vector<std::shared_ptr<EvalRequest>> requests;
  {
    std::lock_guard<std::mutex> queueLock(pImpl->pendingEvalRequestsMutex);
    if (pImpl->pendingEvalRequests.empty()) {
      return;
    }
    requests.swap(pImpl->pendingEvalRequests);
  }

  const std::lock_guard<std::recursive_mutex> luaLock(coreEngine_.getMutex());
  auto &lua = coreEngine_.getLuaState();

  for (const auto &request : requests) {
    bool isError = false;
    std::string result;

    try {
      sol::load_result loadResult = lua.load(request->code);
      if (!loadResult.valid()) {
        sol::error err = loadResult;
        isError = true;
        result = err.what();
      } else {
        sol::protected_function chunk = loadResult;
        sol::protected_function_result execResult = chunk();
        if (!execResult.valid()) {
          sol::error err = execResult;
          isError = true;
          result = err.what();
        } else if (execResult.return_count() > 0) {
          result = luaEvalResultToString(execResult.get<sol::object>());
        }
      }
    } catch (const std::exception &e) {
      isError = true;
      result = e.what();
    }

    {
      std::lock_guard<std::mutex> resultLock(request->resultMutex);
      request->isError = isError;
      request->result = result;
    }
    request->completed.store(true, std::memory_order_release);
  }
}

// ============================================================================
// Event Listener Invocation (called from notifyUpdate at 30Hz)
// ============================================================================

void LuaEngine::invokeEventListeners() {
  if (!pImpl->processor)
    return;

  auto* proc = pImpl->processor;
  const int numLayers = std::max(0, proc->getNumLayers());
  if (static_cast<int>(pImpl->lastLayerStates.size()) != numLayers) {
    pImpl->lastLayerStates.assign(
        numLayers, static_cast<int>(ScriptableLayerState::Unknown));
  }

  // Get current state for diff detection
  float currentTempo = proc->getTempo();
  bool currentRecording = proc->isRecording();
  int currentCommitCount = proc->getCommitCount();
  std::vector<int> currentLayerStates(static_cast<size_t>(numLayers),
                                      static_cast<int>(ScriptableLayerState::Unknown));
  for (int i = 0; i < numLayers; ++i) {
    ScriptableLayerSnapshot layer;
    if (proc->getLayerSnapshot(i, layer)) {
      currentLayerStates[static_cast<size_t>(i)] = static_cast<int>(layer.state);
    }
  }

  const bool tempoChanged = std::abs(currentTempo - pImpl->lastTempo) > 0.01f;
  const bool recordingChanged = currentRecording != pImpl->lastRecording;
  const bool commitChanged = currentCommitCount != pImpl->lastCommitCount;
  std::vector<bool> layerChanged(static_cast<size_t>(numLayers), false);
  for (int i = 0; i < numLayers; ++i) {
    layerChanged[static_cast<size_t>(i)] =
        currentLayerStates[static_cast<size_t>(i)] !=
        pImpl->lastLayerStates[static_cast<size_t>(i)];
  }

  const std::lock_guard<std::recursive_mutex> luaLock(coreEngine_.getMutex());
  std::lock_guard<std::mutex> lock(pImpl->eventListenersMutex);

  // Tempo changed
  if (tempoChanged) {
    for (const auto& listener : pImpl->tempoChangedListeners) {
      if (listener.func.valid()) {
        try {
          listener.func(currentTempo);
        } catch (const sol::error& e) {
          std::fprintf(stderr, "LuaEngine: onTempoChanged error: %s\n", e.what());
        }
      }
    }
    pImpl->lastTempo = currentTempo;
  }

  // Commit count changed
  if (commitChanged) {
    for (const auto& listener : pImpl->commitListeners) {
      if (listener.func.valid()) {
        try {
          listener.func(currentCommitCount);
        } catch (const sol::error& e) {
          std::fprintf(stderr, "LuaEngine: onCommit error: %s\n", e.what());
        }
      }
    }
    pImpl->lastCommitCount = currentCommitCount;
  }

  // Recording state changed
  if (recordingChanged) {
    for (const auto& listener : pImpl->recordingChangedListeners) {
      if (listener.func.valid()) {
        try {
          listener.func(currentRecording);
        } catch (const sol::error& e) {
          std::fprintf(stderr, "LuaEngine: onRecordingChanged error: %s\n", e.what());
        }
      }
    }
    pImpl->lastRecording = currentRecording;
  }

  // Layer state changes
  for (int i = 0; i < numLayers; ++i) {
    if (layerChanged[static_cast<size_t>(i)]) {
      const auto state =
          static_cast<ScriptableLayerState>(currentLayerStates[static_cast<size_t>(i)]);
      const char *stateStr = toLayerStateString(state);

      for (const auto& listener : pImpl->layerStateChangedListeners) {
        if (listener.func.valid()) {
          try {
            listener.func(i, stateStr);
          } catch (const sol::error& e) {
            std::fprintf(stderr, "LuaEngine: onLayerStateChanged error: %s\n", e.what());
          }
        }
      }

      pImpl->lastLayerStates[static_cast<size_t>(i)] =
          currentLayerStates[static_cast<size_t>(i)];
    }
  }

  // General state changed (30Hz polling)
  if (!pImpl->stateChangedListeners.empty()) {
    auto changedTable = coreEngine_.getLuaState().create_table();
    bool anyChanged = false;

    if (tempoChanged) {
      changedTable["tempo"] = true;
      anyChanged = true;
    }
    if (recordingChanged) {
      changedTable["recording"] = true;
      anyChanged = true;
    }
    if (commitChanged) {
      changedTable["commit"] = true;
      anyChanged = true;
    }
    for (int i = 0; i < numLayers; ++i) {
      if (layerChanged[static_cast<size_t>(i)]) {
        changedTable["layer" + std::to_string(i)] = true;
        anyChanged = true;
      }
    }

    if (anyChanged) {
      for (const auto& listener : pImpl->stateChangedListeners) {
        if (listener.func.valid()) {
          try {
            listener.func(changedTable);
          } catch (const sol::error& e) {
            std::fprintf(stderr, "LuaEngine: onStateChanged error: %s\n", e.what());
          }
        }
      }
    }
  }
}

// ============================================================================
// Clear Non-Persistent Callbacks (called on script switch)
// ============================================================================

void LuaEngine::clearNonPersistentCallbacks() {
  std::lock_guard<std::mutex> lock1(pImpl->oscCallbacksMutex);
  std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
  std::lock_guard<std::mutex> lock3(pImpl->oscQueryHandlersMutex);

  // Clear non-persistent OSC callbacks
  for (auto& [address, callbacks] : pImpl->oscCallbacks) {
    callbacks.erase(
        std::remove_if(callbacks.begin(), callbacks.end(),
                       [](const ILuaControlState::OSCCallback& cb) { return !cb.persistent; }),
        callbacks.end());
  }
  // Remove empty address entries
  for (auto it = pImpl->oscCallbacks.begin();
       it != pImpl->oscCallbacks.end();) {
    if (it->second.empty()) {
      it = pImpl->oscCallbacks.erase(it);
    } else {
      ++it;
    }
  }

  // Clear non-persistent event listeners
  auto clearNonPersistent = [](std::vector<ILuaControlState::EventListener>& listeners) {
    listeners.erase(
        std::remove_if(listeners.begin(), listeners.end(),
                       [](const ILuaControlState::EventListener& l) { return !l.persistent; }),
        listeners.end());
  };

  clearNonPersistent(pImpl->tempoChangedListeners);
  clearNonPersistent(pImpl->commitListeners);
  clearNonPersistent(pImpl->recordingChangedListeners);
  clearNonPersistent(pImpl->layerStateChangedListeners);
  clearNonPersistent(pImpl->stateChangedListeners);

  for (auto it = pImpl->oscQueryHandlers.begin();
       it != pImpl->oscQueryHandlers.end();) {
    if (!it->second.persistent) {
      it = pImpl->oscQueryHandlers.erase(it);
    } else {
      ++it;
    }
  }

}

// ============================================================================
// ILuaControlState implementation
// ============================================================================

ScriptableProcessor* LuaEngine::getProcessor() {
  return pImpl->processor;
}

const ScriptableProcessor* LuaEngine::getProcessor() const {
  return pImpl->processor;
}

midi::MidiManager* LuaEngine::getMidiManager() {
  return pImpl->midiManager.get();
}

juce::File LuaEngine::getCurrentScriptFile() const {
  return pImpl->currentScriptFile;
}

void LuaEngine::setPendingSwitchPath(const std::string& path) {
  pImpl->pendingSwitchPath = path;
}

bool LuaEngine::isOverlayActive() const {
  return !pImpl->overlayStack.empty();
}

bool LuaEngine::closeOverlay() {
  if (pImpl->overlayStack.empty()) {
    return false;
  }

  std::fprintf(stderr, "LuaEngine: closeOverlay() - popping %zu overlay(s)\n",
               pImpl->overlayStack.size());

  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  auto& lua = coreEngine_.getLuaState();

  // Call cleanup on the top overlay while state is locked.
  auto& topOverlay = pImpl->overlayStack.back();
  if (topOverlay.uiCleanup.valid()) {
    try {
      auto result = topOverlay.uiCleanup();
      if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaEngine: overlay ui_cleanup error: %s\n", err.what());
      }
    } catch (const std::exception& e) {
      std::fprintf(stderr, "LuaEngine: overlay ui_cleanup exception: %s\n", e.what());
    }
  }

  // Hide the overlay's UI tree nodes (don't remove mid-render - causes display list crash).
  if (pImpl->scriptContentCanvasRoot != nullptr) {
    pImpl->scriptContentCanvasRoot->setVisible(false);
  } else if (pImpl->scriptContentRuntimeRoot != nullptr) {
    pImpl->scriptContentRuntimeRoot->setVisible(false);
  }

  // Copy the popped entry's saved state before erasing it.
  // This entry contains the UNDERLYING project's callbacks and globals
  // (saved when the overlay was pushed on top of it).
  Impl::OverlayEntry restoredEntry = std::move(pImpl->overlayStack.back());
  pImpl->overlayStack.pop_back();

  // Restore callbacks, globals, and UI tree from the popped entry.
  if (restoredEntry.uiUpdate.valid()) lua["ui_update"] = restoredEntry.uiUpdate;
  if (restoredEntry.uiResized.valid()) lua["ui_resized"] = restoredEntry.uiResized;
  if (restoredEntry.uiCleanup.valid()) lua["ui_cleanup"] = restoredEntry.uiCleanup;
  if (restoredEntry.onStateChanged.valid()) lua["onStateChanged"] = restoredEntry.onStateChanged;
  lua["__manifoldProjectRoot"] = restoredEntry.savedProjectRoot;
  lua["__manifoldProjectManifest"] = restoredEntry.savedProjectManifest;
  lua["__manifoldStructuredUiRoot"] = restoredEntry.savedStructuredUiRoot;
  lua["__manifoldUserScriptsRoot"] = restoredEntry.savedUserScriptsRoot;
  lua["__manifoldSystemUiRoot"] = restoredEntry.savedSystemUiRoot;
  lua["__manifoldSystemDspRoot"] = restoredEntry.savedSystemDspRoot;
  pImpl->scriptContentCanvasRoot = restoredEntry.canvasRoot;
  pImpl->scriptContentRuntimeRoot = restoredEntry.runtimeRoot;
  pImpl->currentScriptFile = juce::File(juce::String(restoredEntry.path));

  // Restore shared shell (nilled during overlay load).
  if (pImpl->hasSharedShell && pImpl->sharedShell.valid()) {
    lua["shell"] = pImpl->sharedShell;
  }

  // If we've unwound all overlays, clean up base project tracking.
  if (pImpl->overlayStack.empty()) {
    pImpl->baseProjectCanvasRoot = nullptr;
    pImpl->baseProjectRuntimeRoot = nullptr;
    pImpl->hasBaseProjectCallbacks = false;
    pImpl->baseProjectUiUpdate = sol::nil;
    pImpl->baseProjectUiResized = sol::nil;
    pImpl->baseProjectOnStateChanged = sol::nil;
  }

  // Prevent immediate hot-reload after overlay close from stale counters.
  pImpl->lastModTime = pImpl->currentScriptFile.getLastModificationTime();
  pImpl->hotReloadCounter = 0;

  // Schedule a deferred panic for the next notifyUpdate() tick.
  // We can't call Lua panic here because setParam may not be safe mid-transition.
  pImpl->deferredPanic = true;

  return true;
}

std::unordered_set<std::string>& LuaEngine::getManagedDspSlots() {
  return pImpl->managedDspSlots;
}

const std::unordered_set<std::string>& LuaEngine::getManagedDspSlots() const {
  return pImpl->managedDspSlots;
}

std::unordered_set<std::string>& LuaEngine::getPersistentDspSlots() {
  return pImpl->persistentDspSlots;
}

const std::unordered_set<std::string>& LuaEngine::getPersistentDspSlots() const {
  return pImpl->persistentDspSlots;
}

std::unordered_set<std::string>& LuaEngine::getUiRegisteredOscEndpoints() {
  return pImpl->uiRegisteredOscEndpoints;
}

const std::unordered_set<std::string>& LuaEngine::getUiRegisteredOscEndpoints() const {
  return pImpl->uiRegisteredOscEndpoints;
}

std::unordered_set<std::string>& LuaEngine::getUiRegisteredOscValues() {
  return pImpl->uiRegisteredOscValues;
}

const std::unordered_set<std::string>& LuaEngine::getUiRegisteredOscValues() const {
  return pImpl->uiRegisteredOscValues;
}

std::map<juce::String, std::vector<ILuaControlState::OSCCallback>>&
LuaEngine::getOscCallbacks() {
  return pImpl->oscCallbacks;
}

std::mutex& LuaEngine::getOscCallbacksMutex() {
  return pImpl->oscCallbacksMutex;
}

std::map<juce::String, ILuaControlState::OSCQueryHandler>&
LuaEngine::getOscQueryHandlers() {
  return pImpl->oscQueryHandlers;
}

std::mutex& LuaEngine::getOscQueryHandlersMutex() {
  return pImpl->oscQueryHandlersMutex;
}

std::vector<ILuaControlState::EventListener>& LuaEngine::getTempoChangedListeners() {
  return pImpl->tempoChangedListeners;
}

std::vector<ILuaControlState::EventListener>& LuaEngine::getCommitListeners() {
  return pImpl->commitListeners;
}

std::vector<ILuaControlState::EventListener>& LuaEngine::getRecordingChangedListeners() {
  return pImpl->recordingChangedListeners;
}

std::vector<ILuaControlState::EventListener>& LuaEngine::getLayerStateChangedListeners() {
  return pImpl->layerStateChangedListeners;
}

std::vector<ILuaControlState::EventListener>& LuaEngine::getStateChangedListeners() {
  return pImpl->stateChangedListeners;
}

std::mutex& LuaEngine::getEventListenersMutex() {
  return pImpl->eventListenersMutex;
}

void LuaEngine::withLuaState(std::function<void(sol::state&)> callback) {
  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  callback(coreEngine_.getLuaState());
}

void LuaEngine::withLuaState(std::function<void(const sol::state&)> callback) const {
  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  callback(coreEngine_.getLuaState());
}

// ============================================================================
// File chooser (async directory browser)
// ============================================================================

void LuaEngine::showDirectoryChooser(const std::string& title,
                                       const std::string& initialPath,
                                       sol::function callback) {
  std::fprintf(stderr, "[FileChooser] showDirectoryChooser called: title='%s', initialPath='%s'\n",
               title.c_str(), initialPath.c_str());
  
  // Must run on message thread
  if (!juce::MessageManager::getInstance()->isThisTheMessageThread()) {
    std::fprintf(stderr, "[FileChooser] ERROR: not on message thread!\n");
    // Invoke callback with empty path to indicate error
    juce::MessageManager::callAsync([callback]() mutable {
      if (callback.valid()) {
        try { callback(""); } catch (...) {}
      }
    });
    return;
  }

  juce::File initialDir(initialPath);
  std::fprintf(stderr, "[FileChooser] initialDir exists=%d, isDirectory=%d, path='%s'\n",
               initialDir.exists() ? 1 : 0,
               initialDir.isDirectory() ? 1 : 0,
               initialDir.getFullPathName().toRawUTF8());
  
  if (!initialDir.isDirectory()) {
    initialDir = juce::File::getSpecialLocation(juce::File::userHomeDirectory);
    std::fprintf(stderr, "[FileChooser] Using home directory instead: '%s'\n",
                 initialDir.getFullPathName().toRawUTF8());
  }

  std::fprintf(stderr, "[FileChooser] Creating FileChooser...\n");
  auto chooser = std::make_unique<juce::FileChooser>(
      juce::String(title),
      initialDir,
      "*",
      true,  // useOSNativeDialog
      false  // treatFilePackagesAsDirs
  );
  std::fprintf(stderr, "[FileChooser] FileChooser created, launching async...\n");

  // Store callback in a shared_ptr to keep it alive
  auto cb = std::make_shared<sol::function>(callback);

  chooser->launchAsync(
      juce::FileBrowserComponent::canSelectDirectories
          | juce::FileBrowserComponent::openMode,
      [cb, chooserPtr = chooser.get()](const juce::FileChooser& fc) mutable {
        juce::File result = fc.getResult();
        std::string path = result.exists() ? result.getFullPathName().toStdString() : "";
        std::fprintf(stderr, "[FileChooser] User selected: '%s'\n", path.c_str());

        // Invoke Lua callback on message thread
        juce::MessageManager::callAsync([cb, path]() mutable {
          if (cb && cb->valid()) {
            try {
              std::fprintf(stderr, "[FileChooser] Invoking Lua callback with path: '%s'\n", path.c_str());
              auto result = (*cb)(path);
              if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "[FileChooser] Lua callback error: %s\n", err.what());
              } else {
                std::fprintf(stderr, "[FileChooser] Lua callback succeeded\n");
              }
            } catch (const sol::error& e) {
              std::fprintf(stderr, "[FileChooser] Lua callback exception: %s\n", e.what());
            }
          } else {
            std::fprintf(stderr, "[FileChooser] ERROR: callback invalid\n");
          }
        });

        // chooser will be auto-deleted when unique_ptr goes out of scope
      }
  );
  
  std::fprintf(stderr, "[FileChooser] launchAsync called, releasing ownership\n");
  // Release ownership - FileChooser manages its own lifetime after launchAsync
  chooser.release();
  std::fprintf(stderr, "[FileChooser] Done\n");
}

// ============================================================================
// Debug outline control (for ImGuiDirectHost in performance mode)
// These are stored as atomic values that the Editor reads/writes
// ============================================================================
static std::atomic<bool> g_debugOutlinesEnabled{false};
static std::atomic<uint64_t> g_debugHoveredStableId{0};
static std::atomic<uint64_t> g_debugSelectedStableId{0};

void LuaEngine::setDebugOutlinesEnabled(bool enabled) {
  g_debugOutlinesEnabled.store(enabled, std::memory_order_relaxed);
}

bool LuaEngine::areDebugOutlinesEnabled() const {
  return g_debugOutlinesEnabled.load(std::memory_order_relaxed);
}

std::string LuaEngine::getDebugHoveredNodeId() const {
  // This will be populated by the Editor from the DirectHost
  // For now, return empty - the Editor pushes actual values via a different mechanism
  return "";
}

std::string LuaEngine::getDebugSelectedNodeId() const {
  // This will be populated by the Editor from the DirectHost
  // For now, return empty - the Editor pushes actual values via a different mechanism
  return "";
}

// ============================================================================
// CopyID mode - when enabled, clicking widgets copies their ID to clipboard
// ============================================================================
static std::atomic<bool> g_copyIdModeEnabled{false};

bool LuaEngine::isCopyIdModeEnabled() const {
  return g_copyIdModeEnabled.load(std::memory_order_relaxed);
}

void LuaEngine::setCopyIdModeEnabled(bool enabled) {
  g_copyIdModeEnabled.store(enabled, std::memory_order_relaxed);
  // Also control debug outlines - copyid mode needs them for visual feedback
  g_debugOutlinesEnabled.store(enabled, std::memory_order_relaxed);
}

void LuaEngine::copyNodeIdToClipboard(const std::string& nodeId) {
  juce::SystemClipboard::copyTextToClipboard(juce::String(nodeId));
}

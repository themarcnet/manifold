#include "LuaEngine.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "ScriptableProcessor.h"
#include "PrimitiveGraph.h"
#include "dsp/core/nodes/PrimitiveNodes.h"
#include "bindings/LuaUIBindings.h"
#include "bindings/LuaControlBindings.h"
#include "../control/CommandParser.h"
#include "../control/ControlServer.h"
#include "../control/OSCPacketBuilder.h"
#include "../control/OSCSettingsPersistence.h"
#include "../control/OSCEndpointRegistry.h"
#include "../control/OSCQuery.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <map>
#include <mutex>
#include <tuple>
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

} // namespace

// ============================================================================
// pImpl
// ============================================================================

struct LuaEngine::Impl {
  ScriptableProcessor *processor = nullptr;
  Canvas *rootCanvas = nullptr;
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
  Canvas *scriptContentRoot = nullptr;
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
};

// ============================================================================
// Construction / Destruction
// ============================================================================

LuaEngine::LuaEngine() : pImpl(std::make_unique<Impl>()) {}

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
  pImpl->processor = processor;
  pImpl->rootCanvas = rootCanvas;
  pImpl->lastLayerStates.assign(
      processor ? std::max(0, processor->getNumLayers()) : 0,
      static_cast<int>(ScriptableLayerState::Unknown));

  // Initialize core engine (VM lifecycle only)
  coreEngine_.initialize();

  // Lock Core's mutex and get reference to its Lua state
  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());

  registerBindings();

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
  // Register Canvas, Graphics, and OpenGL bindings via LuaUIBindings module
  LuaUIBindings::registerBindings(coreEngine_, pImpl->rootCanvas);

  // Register control bindings (commands, OSC, events, Link, etc.)
  LuaControlBindings::registerBindings(coreEngine_, *this);

  auto &lua = coreEngine_.getLuaState();

  // ---- Root canvas accessor ----
  lua["root"] = pImpl->rootCanvas;

}

// ============================================================================
// State snapshot
// ============================================================================

void LuaEngine::pushStateToLua() {
  const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
  auto &lua = coreEngine_.getLuaState();
  auto *proc = pImpl->processor;
  if (!proc)
    return;

  auto state = lua.create_table();

  const float tempo = proc->getTempo();
  const float targetBPM = proc->getTargetBPM();
  const float samplesPerBar = proc->getSamplesPerBar();
  const double sampleRate = proc->getSampleRate();
  const float masterVolume = proc->getMasterVolume();
  const float inputVolume = proc->getInputVolume();
  const bool passthroughEnabled = proc->isPassthroughEnabled();
  const bool isRecording = proc->isRecording();
  const bool isOverdubEnabled = proc->isOverdubEnabled();
  const int activeLayerIndex = proc->getActiveLayerIndex();
  const bool forwardCommitArmed = proc->isForwardCommitArmed();
  const float forwardCommitBars = proc->getForwardCommitBars();
  const int recordModeIndex = proc->getRecordModeIndex();
  const int numLayers = proc->getNumLayers();
  const int captureSize = proc->getCaptureSize();
  const char *recordModeString = "firstLoop";

  // Record mode as string
  switch (recordModeIndex) {
  case 0:
    recordModeString = "firstLoop";
    break;
  case 1:
    recordModeString = "freeMode";
    break;
  case 2:
    recordModeString = "traditional";
    break;
  case 3:
    recordModeString = "retrospective";
    break;
  default:
    recordModeString = "firstLoop";
    break;
  }
  state["projectionVersion"] = 2;
  state["numVoices"] = numLayers;

  auto params = lua.create_table();
  auto setBehaviorParam = [&](const std::string &suffix, const auto &value) {
    params["/looper" + suffix] = value;
    params["/core/behavior" + suffix] = value;
    params["/dsp/looper" + suffix] = value;
  };

  setBehaviorParam("/tempo", tempo);
  setBehaviorParam("/targetbpm", targetBPM);
  setBehaviorParam("/samplesPerBar", samplesPerBar);
  setBehaviorParam("/sampleRate", sampleRate);
  setBehaviorParam("/captureSize", captureSize);
  setBehaviorParam("/volume", masterVolume);
  setBehaviorParam("/inputVolume", inputVolume);
  setBehaviorParam("/passthrough", passthroughEnabled ? 1 : 0);
  setBehaviorParam("/recording", isRecording ? 1 : 0);
  setBehaviorParam("/overdub", isOverdubEnabled ? 1 : 0);
  setBehaviorParam("/mode", recordModeString);
  setBehaviorParam("/layer", activeLayerIndex);
  setBehaviorParam("/forwardArmed", forwardCommitArmed ? 1 : 0);
  setBehaviorParam("/forwardBars", forwardCommitBars);

  auto voices = lua.create_table();
  for (int i = 0; i < numLayers; ++i) {
    ScriptableLayerSnapshot layer;
    if (!proc->getLayerSnapshot(i, layer)) {
      continue;
    }

    const char *layerStateString = toLayerStateString(layer.state);
    const float normalizedPosition =
        (layer.length > 0)
            ? static_cast<float>(layer.position) / static_cast<float>(layer.length)
            : 0.0f;
    const float bars =
        (samplesPerBar > 0.0f)
            ? static_cast<float>(layer.length) / samplesPerBar
            : 0.0f;
    const bool muted = layer.muted;

    const std::string looperLayerPrefix =
        "/looper/layer/" + std::to_string(i);
    const std::string coreLayerPrefix =
        "/core/behavior/layer/" + std::to_string(i);
    const std::string dspLayerPrefix =
        "/dsp/looper/layer/" + std::to_string(i);

    auto setLayerParam = [&](const std::string &suffix, const auto &value) {
      params[looperLayerPrefix + suffix] = value;
      params[coreLayerPrefix + suffix] = value;
      params[dspLayerPrefix + suffix] = value;
    };

    setLayerParam("/speed", layer.speed);
    setLayerParam("/volume", layer.volume);
    setLayerParam("/mute", muted ? 1 : 0);
    setLayerParam("/reverse", layer.reversed ? 1 : 0);
    setLayerParam("/length", layer.length);
    setLayerParam("/position", normalizedPosition);
    setLayerParam("/bars", bars);
    setLayerParam("/state", layerStateString);

    auto voice = lua.create_table();
    voice["id"] = i;
    voice["path"] = looperLayerPrefix;
    voice["state"] = layerStateString;
    voice["length"] = layer.length;
    voice["position"] = layer.position;
    voice["positionNorm"] = normalizedPosition;
    voice["speed"] = layer.speed;
    voice["reversed"] = layer.reversed;
    voice["volume"] = layer.volume;
    voice["bars"] = bars;

    auto voiceParams = lua.create_table();
    voiceParams["speed"] = layer.speed;
    voiceParams["volume"] = layer.volume;
    voiceParams["mute"] = muted ? 1 : 0;
    voiceParams["reverse"] = layer.reversed ? 1 : 0;
    voiceParams["length"] = layer.length;
    voiceParams["position"] = normalizedPosition;
    voiceParams["bars"] = bars;
    voiceParams["state"] = layerStateString;
    voice["params"] = voiceParams;

    voices[i + 1] = voice;
  }
  state["params"] = params;
  state["voices"] = voices;

  // Ableton Link state
  auto linkState = lua.create_table();
  linkState["enabled"] = proc->isLinkEnabled();
  linkState["tempoSync"] = proc->isLinkTempoSyncEnabled();
  linkState["startStopSync"] = proc->isLinkStartStopSyncEnabled();
  linkState["peers"] = proc->getLinkNumPeers();
  linkState["playing"] = proc->isLinkPlaying();
  linkState["beat"] = proc->getLinkBeat();
  linkState["phase"] = proc->getLinkPhase();
  state["link"] = linkState;

  // Spectrum analysis data for visualization
  auto spectrum = proc->getSpectrumData();
  sol::table spectrumTable = lua.create_table();
  for (int i = 0; i < static_cast<int>(spectrum.size()); ++i) {
    spectrumTable[i + 1] = spectrum[i];  // Lua is 1-indexed
  }
  state["spectrum"] = spectrumTable;

  lua["state"] = state;
}

// ============================================================================
// Script loading
// ============================================================================

bool LuaEngine::loadScript(const juce::File &scriptFile) {
  if (!scriptFile.existsAsFile()) {
    pImpl->lastError =
        "Script file not found: " + scriptFile.getFullPathName().toStdString();
    return false;
  }

  pImpl->currentScriptFile = scriptFile;

  // Sync with core engine
  coreEngine_.setPackagePath(scriptFile.getParentDirectory().getFullPathName().toStdString());

  // Set up package.path so require() works from the script's directory
  auto dir = scriptFile.getParentDirectory().getFullPathName().toStdString();
  if (pImpl->sharedUiDir.empty()) {
    pImpl->sharedUiDir = dir;
  }
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    auto packagePath = dir + "/?.lua;" + dir + "/?/init.lua";
    if (!pImpl->sharedUiDir.empty() && pImpl->sharedUiDir != dir) {
      packagePath += ";" + pImpl->sharedUiDir + "/?.lua;" +
                     pImpl->sharedUiDir + "/?/init.lua";
    }
    coreEngine_.getLuaState()["package"]["path"] = packagePath;
  }

  // Clear lifecycle globals so old script handlers don't leak into new scripts.
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    coreEngine_.getLuaState()["ui_init"] = sol::nil;
    coreEngine_.getLuaState()["ui_update"] = sol::nil;
    coreEngine_.getLuaState()["ui_resized"] = sol::nil;
  }

  // Delegate script execution to Core Engine
  if (!coreEngine_.loadScript(scriptFile)) {
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
      // Build persistent parent-shell frame + a dedicated content mount root.
      pImpl->rootCanvas->clearChildren();
      pImpl->scriptContentRoot = pImpl->rootCanvas->addChild("script_content_root");

      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        pImpl->hasSharedShell = false;
        pImpl->sharedShellRequireOk = false;
        pImpl->sharedShellCreateOk = false;
        pImpl->sharedContentX = 0;
        pImpl->sharedContentY = 0;
        pImpl->sharedContentW = 0;
        pImpl->sharedContentH = 0;

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

      int contentX = 0;
      int contentY = 0;
      int contentW = pImpl->lastWidth > 0 ? pImpl->lastWidth : pImpl->rootCanvas->getWidth();
      int contentH = pImpl->lastHeight > 0 ? pImpl->lastHeight : pImpl->rootCanvas->getHeight();

      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        if (pImpl->hasSharedShell) {
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
        }
      }

      pImpl->sharedContentX = contentX;
      pImpl->sharedContentY = contentY;
      pImpl->sharedContentW = contentW;
      pImpl->sharedContentH = contentH;

      pImpl->scriptContentRoot->setBounds(contentX, contentY, contentW, contentH);

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

      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        result = uiInit(pImpl->scriptContentRoot != nullptr ? pImpl->scriptContentRoot
                                                            : pImpl->rootCanvas);
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

  int contentX = 0;
  int contentY = 0;
  int contentW = width;
  int contentH = height;

  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    if (pImpl->hasSharedShell) {
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
    }
  }

  if (pImpl->scriptContentRoot != nullptr) {
    pImpl->scriptContentRoot->setBounds(contentX, contentY, contentW, contentH);
  }

  pImpl->sharedContentX = contentX;
  pImpl->sharedContentY = contentY;
  pImpl->sharedContentW = contentW;
  pImpl->sharedContentH = contentH;

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

  // Check for hot-reload at ~1Hz
  checkHotReload();

  // Process queued OSC callbacks on message thread
  processPendingOSCCallbacks();

  pushStateToLua();

  // Invoke event listeners for state changes
  invokeEventListeners();

  sol::function fn;
  {
    const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
    fn = coreEngine_.getLuaState()["ui_update"];
  }
  if (fn.valid()) {
    try {
      sol::object stateObj;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        stateObj = coreEngine_.getLuaState()["state"];

        if (pImpl->hasSharedShell) {
          sol::table shell = pImpl->sharedShell;
          sol::protected_function shellUpdate = shell["updateFromState"];
          if (shellUpdate.valid()) {
            sol::protected_function_result shellRes = shellUpdate(shell, stateObj);
            if (!shellRes.valid()) {
              sol::error err = shellRes;
              std::fprintf(stderr, "LuaEngine: shell update error: %s\n", err.what());
            }
          }
        }
      }

      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(coreEngine_.getMutex());
        result = fn(stateObj);
      }
      if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaEngine: ui_update error: %s\n", err.what());
      }
    } catch (const std::exception &e) {
      std::fprintf(stderr, "LuaEngine: ui_update exception: %s\n", e.what());
    }
  }
}

bool LuaEngine::isScriptLoaded() const { return coreEngine_.isScriptLoaded(); }

const std::string &LuaEngine::getLastError() const { return coreEngine_.getLastError(); }

juce::File LuaEngine::getScriptDirectory() const {
  if (pImpl->currentScriptFile.existsAsFile())
    return pImpl->currentScriptFile.getParentDirectory();
  return {};
}

// ============================================================================
// Script switching / hot-reload
// ============================================================================

bool LuaEngine::switchScript(const juce::File &scriptFile) {
  // BUG: This disables the graph on every UI switch, which kills all audio
  // in BehaviorCore where the looper IS the graph. In legacy LooperProcessor
  // this was safe because loops lived in C++ LooperLayer objects independent
  // of the graph. Must not disable here.
  // See: agent-docs/PERSISTENT_GRAPH_ARCHITECTURE.md
  //
  // if (pImpl->processor) {
  //   pImpl->processor->setGraphProcessingEnabled(false);
  // }

  // Give the outgoing script a chance to clean up (e.g. unload DSP slots).
  {
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
  }

  // Enforce transient-by-default DSP-slot policy.
  // Any managed slot is unloaded on UI switch unless explicitly marked
  // persistent via setDspSlotPersistOnUiSwitch(slot, true).
  if (pImpl->processor && !pImpl->managedDspSlots.empty()) {
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

  // Clear the current UI
  if (pImpl->rootCanvas) {
    pImpl->rootCanvas->clearChildren();
  }

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
  bool ok = loadScript(scriptFile);
  if (ok && pImpl->lastWidth > 0 && pImpl->lastHeight > 0) {
    notifyResized(pImpl->lastWidth, pImpl->lastHeight);
  }
  return ok;
}

bool LuaEngine::reloadCurrentScript() {
  // Delegate to core engine for hot reload check
  if (!coreEngine_.reloadCurrentScript()) {
    return false;
  }
  // If core reloaded successfully, sync our state
  if (coreEngine_.isScriptLoaded()) {
    std::fprintf(stderr, "LuaEngine: hot-reloaded %s\n",
                 coreEngine_.getCurrentScriptFile().getFileName().toRawUTF8());
    // Re-run the ui_init setup logic
    return switchScript(coreEngine_.getCurrentScriptFile());
  }
  return true; // No change needed
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

  if (!pImpl->currentScriptFile.existsAsFile())
    return;

  auto modTime = pImpl->currentScriptFile.getLastModificationTime();
  if (modTime != pImpl->lastModTime && pImpl->lastModTime != juce::Time()) {
    pImpl->lastModTime = modTime;
    reloadCurrentScript();
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

juce::File LuaEngine::getCurrentScriptFile() const {
  return pImpl->currentScriptFile;
}

void LuaEngine::setPendingSwitchPath(const std::string& path) {
  pImpl->pendingSwitchPath = path;
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

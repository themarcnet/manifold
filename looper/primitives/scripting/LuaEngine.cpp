#include "LuaEngine.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "../../engine/LooperProcessor.h"
#include "../control/ControlServer.h"

#include <algorithm>
#include <cstdio>
#include <juce_graphics/juce_graphics.h>

// ============================================================================
// pImpl
// ============================================================================

struct LuaEngine::Impl {
  sol::state lua;
  LooperProcessor *processor = nullptr;
  Canvas *rootCanvas = nullptr;
  bool scriptLoaded = false;
  std::string lastError;
  juce::File currentScriptFile;

  // Lightweight wrapper around juce::Graphics for Lua
  // We store a raw pointer that is only valid during a paint() callback.
  juce::Graphics *currentGraphics = nullptr;

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
};

// ============================================================================
// Construction / Destruction
// ============================================================================

LuaEngine::LuaEngine() : pImpl(std::make_unique<Impl>()) {}

LuaEngine::~LuaEngine() = default;

// ============================================================================
// Initialisation
// ============================================================================

void LuaEngine::initialise(LooperProcessor *processor, Canvas *rootCanvas) {
  pImpl->processor = processor;
  pImpl->rootCanvas = rootCanvas;

  auto &lua = pImpl->lua;
  lua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                     sol::lib::table, sol::lib::package);

  registerBindings();
}

// ============================================================================
// Bindings
// ============================================================================

void LuaEngine::registerBindings() {
  auto &lua = pImpl->lua;

  // ---- CanvasStyle ----
  lua.new_usertype<CanvasStyle>(
      "CanvasStyle", sol::constructors<CanvasStyle()>(), "background",
      sol::property(
          [](const CanvasStyle &s) { return (uint32_t)s.background.getARGB(); },
          [](CanvasStyle &s, uint32_t c) { s.background = juce::Colour(c); }),
      "border",
      sol::property(
          [](const CanvasStyle &s) { return (uint32_t)s.border.getARGB(); },
          [](CanvasStyle &s, uint32_t c) { s.border = juce::Colour(c); }),
      "borderWidth", &CanvasStyle::borderWidth, "cornerRadius",
      &CanvasStyle::cornerRadius, "opacity", &CanvasStyle::opacity, "padding",
      &CanvasStyle::padding);

  // ---- Canvas ----
  lua.new_usertype<Canvas>(
      "Canvas",
      // No direct construction from Lua — use addChild
      sol::no_constructor,

      "addChild",
      [](Canvas &parent, const std::string &name) -> Canvas * {
        return parent.addChild(juce::String(name));
      },

      "clearChildren", &Canvas::clearChildren, "getNumChildren",
      &Canvas::getNumChildren, "getChild", &Canvas::getChild,

      "setBounds",
      [](Canvas &c, int x, int y, int w, int h) { c.setBounds(x, y, w, h); },

      "getBounds",
      [](Canvas &c) {
        auto b = c.getBounds();
        return std::make_tuple(b.getX(), b.getY(), b.getWidth(), b.getHeight());
      },

      "getWidth", [](Canvas &c) { return c.getWidth(); }, "getHeight",
      [](Canvas &c) { return c.getHeight(); },

      "setStyle",
      [](Canvas &c, sol::table t) {
        CanvasStyle s = c.style;
        if (t["bg"].valid())
          s.background = juce::Colour((uint32_t)t["bg"]);
        if (t["border"].valid())
          s.border = juce::Colour((uint32_t)t["border"]);
        if (t["borderWidth"].valid())
          s.borderWidth = t["borderWidth"];
        if (t["radius"].valid())
          s.cornerRadius = t["radius"];
        if (t["opacity"].valid())
          s.opacity = t["opacity"];
        if (t["padding"].valid())
          s.padding = t["padding"];
        c.setStyle(s);
      },

      "getStyle", [](Canvas &c) -> CanvasStyle & { return c.style; },

      "setInterceptsMouse",
      [](Canvas &c, bool clicks, bool children) {
        c.setInterceptsMouseClicks(clicks, children);
      },

      "isMouseOver", [](Canvas &c) { return c.isMouseOverOrDragging(); },

      "repaint", [](Canvas &c) { c.repaint(); },

      "setOnClick",
      [](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          c.onClick = [fn]() mutable {
            auto result = fn();
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onClick error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onClick = nullptr;
        }
      },

      "setOnMouseDown",
      [](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          c.onMouseDown = [fn](const juce::MouseEvent &e) mutable {
            auto result = fn(e.x, e.y);
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onMouseDown error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onMouseDown = nullptr;
        }
      },

      "setOnMouseDrag",
      [](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          c.onMouseDrag = [fn](const juce::MouseEvent &e) mutable {
            auto result = fn(e.x, e.y, e.getDistanceFromDragStartX(),
                             e.getDistanceFromDragStartY());
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onMouseDrag error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onMouseDrag = nullptr;
        }
      },

      "setOnMouseUp",
      [](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          c.onMouseUp = [fn](const juce::MouseEvent &e) mutable {
            auto result = fn(e.x, e.y);
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onMouseUp error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onMouseUp = nullptr;
        }
      },

      "setOnDraw",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onDraw = [fn, impl](Canvas &self, juce::Graphics &g) mutable {
            impl->currentGraphics = &g;
            auto result = fn(std::ref(self));
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onDraw error: %s\n", err.what());
            }
            impl->currentGraphics = nullptr;
          };
        } else {
          c.onDraw = nullptr;
        }
      });

  // ---- Graphics context (gfx) ----
  // Instead of passing juce::Graphics to Lua, we expose a global 'gfx' table
  // whose methods operate on the currently-active Graphics context (set during
  // onDraw).
  auto gfx = lua.create_named_table("gfx");

  gfx["setColour"] = [this](uint32_t argb) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->setColour(juce::Colour(argb));
  };

  gfx["setFont"] = sol::overload(
      [this](float size) {
        if (pImpl->currentGraphics)
          pImpl->currentGraphics->setFont(juce::Font(size));
      },
      [this](const std::string &name, float size) {
        if (pImpl->currentGraphics)
          pImpl->currentGraphics->setFont(
              juce::Font(name, size, juce::Font::plain));
      },
      [this](const std::string &name, float size, int flags) {
        if (pImpl->currentGraphics)
          pImpl->currentGraphics->setFont(juce::Font(name, size, flags));
      });

  gfx["drawText"] = [this](const std::string &text, int x, int y, int w, int h,
                           sol::optional<int> justification) {
    if (pImpl->currentGraphics) {
      int just = justification.value_or(36); // centred = 36
      pImpl->currentGraphics->drawText(juce::String(text),
                                       juce::Rectangle<int>(x, y, w, h),
                                       juce::Justification(just));
    }
  };

  gfx["fillRect"] = [this](float x, float y, float w, float h) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->fillRect(x, y, w, h);
  };

  gfx["fillRoundedRect"] = [this](float x, float y, float w, float h,
                                  float radius) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->fillRoundedRectangle(x, y, w, h, radius);
  };

  gfx["drawRoundedRect"] = [this](float x, float y, float w, float h,
                                  float radius, float lineThickness) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->drawRoundedRectangle(x, y, w, h, radius,
                                                   lineThickness);
  };

  gfx["drawRect"] = sol::overload(
      [this](int x, int y, int w, int h) {
        if (pImpl->currentGraphics)
          pImpl->currentGraphics->drawRect(x, y, w, h);
      },
      [this](int x, int y, int w, int h, int lineThickness) {
        if (pImpl->currentGraphics)
          pImpl->currentGraphics->drawRect(x, y, w, h, lineThickness);
      });

  gfx["drawVerticalLine"] = [this](int x, float top, float bottom) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->drawVerticalLine(x, top, bottom);
  };

  gfx["drawHorizontalLine"] = [this](int y, float left, float right) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->drawHorizontalLine(y, left, right);
  };

  gfx["fillAll"] = [this]() {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->fillAll();
  };

  // ---- Justification constants ----
  lua["Justify"] = lua.create_table_with(
      "left", 1, "right", 2, "horizontallyCentred", 4, "top", 8, "bottom", 16,
      "verticallyCentred", 32, "centred", 36, "centredLeft", 33, "centredRight",
      34, "centredTop", 12, "centredBottom", 20, "topLeft", 9, "topRight", 10,
      "bottomLeft", 17, "bottomRight", 18);

  // ---- Font style constants ----
  lua["FontStyle"] = lua.create_table_with("plain", 0, "bold", 1, "italic", 2,
                                           "boldItalic", 3);

  // ---- Waveform peak data ----
  // Returns a Lua table of peak values (0..1) for a layer's waveform
  lua["getLayerPeaks"] = [this](int layerIdx, int numBuckets) -> sol::table {
    auto &lua = pImpl->lua;
    auto result = lua.create_table();
    if (!pImpl->processor || layerIdx < 0 ||
        layerIdx >= LooperProcessor::MAX_LAYERS || numBuckets <= 0)
      return result;

    auto &layer = pImpl->processor->getLayer(layerIdx);
    int length = layer.getLength();
    if (length <= 0)
      return result;

    const auto *raw = layer.getBuffer().getRawBuffer();
    if (!raw || raw->getNumSamples() <= 0)
      return result;

    int bucketSize = std::max(1, length / numBuckets);
    float highest = 0.0f;
    std::vector<float> peaks((size_t)numBuckets, 0.0f);

    for (int x = 0; x < numBuckets; ++x) {
      int start = std::min(length - 1, x * bucketSize);
      int count = std::min(bucketSize, length - start);
      float peak = 0.0f;
      for (int i = 0; i < count; ++i) {
        int idx = start + i;
        float l = std::abs(raw->getSample(0, idx));
        float r = l;
        if (raw->getNumChannels() > 1)
          r = std::abs(raw->getSample(1, idx));
        float v = std::max(l, r);
        if (v > peak)
          peak = v;
      }
      peaks[(size_t)x] = peak;
      if (peak > highest)
        highest = peak;
    }

    float rescale =
        highest > 0.0f ? std::min(8.0f, std::max(1.0f, 1.0f / highest)) : 1.0f;
    for (int x = 0; x < numBuckets; ++x) {
      result[x + 1] = std::min(1.0f, peaks[(size_t)x] * rescale);
    }
    return result;
  };

  // Returns a Lua table of peak values for a capture buffer window
  // startAgo/endAgo are in samples-ago (0 = now, larger = older)
  lua["getCapturePeaks"] = [this](int startAgo, int endAgo,
                                  int numBuckets) -> sol::table {
    auto &lua = pImpl->lua;
    auto result = lua.create_table();
    if (!pImpl->processor || numBuckets <= 0)
      return result;

    auto &capture = pImpl->processor->getCaptureBuffer();
    int captureSize = capture.getSize();
    if (captureSize <= 0)
      return result;

    int start = std::max(0, std::min(captureSize, startAgo));
    int end = std::max(0, std::min(captureSize, endAgo));
    if (end <= start)
      return result;

    int viewSamples = end - start;
    int bucketSize = std::max(1, viewSamples / numBuckets);
    float highest = 0.0f;
    std::vector<float> peaks((size_t)numBuckets, 0.0f);

    for (int x = 0; x < numBuckets; ++x) {
      // Map x position: left = older, right = now
      float t = numBuckets > 1
                    ? (float)(numBuckets - 1 - x) / (float)(numBuckets - 1)
                    : 0.0f;
      int firstAgo = start + (int)std::round(t * (float)(viewSamples - 1));
      if (firstAgo >= captureSize)
        continue;

      float peak = 0.0f;
      int bucket = std::min(bucketSize, captureSize - firstAgo);
      for (int i = 0; i < bucket; ++i) {
        float sample = std::abs(capture.getSample(firstAgo + i, 0));
        if (sample > peak)
          peak = sample;
      }
      peaks[(size_t)x] = peak;
      if (peak > highest)
        highest = peak;
    }

    float rescale =
        highest > 0.0f ? std::min(10.0f, std::max(1.0f, 1.0f / highest)) : 1.0f;
    for (int x = 0; x < numBuckets; ++x) {
      result[x + 1] = std::min(1.0f, peaks[(size_t)x] * rescale);
    }
    return result;
  };

  // ---- command() ----
  lua["command"] = [this](sol::variadic_args va) {
    if (!pImpl->processor || va.size() == 0)
      return;

    // Parse command string + args, mimicking the CLI protocol
    std::string cmdStr;
    for (size_t i = 0; i < va.size(); ++i) {
      if (i > 0)
        cmdStr += " ";
      auto arg = va[i];
      if (arg.get_type() == sol::type::number) {
        cmdStr += std::to_string(arg.get<float>());
      } else {
        cmdStr += arg.get<std::string>();
      }
    }

    // Route through the ControlServer's command posting
    // We map common commands to ControlCommand types
    // Use the text command parsing that ControlServer already has
    // For now, post the most common commands directly
    if (cmdStr.find("COMMIT") == 0) {
      float bars = 1.0f;
      if (cmdStr.size() > 7)
        bars = std::stof(cmdStr.substr(7));
      pImpl->processor->postControlCommand(ControlCommand::Type::Commit, 0,
                                           bars);
    } else if (cmdStr.find("FORWARD") == 0) {
      float bars = 1.0f;
      if (cmdStr.size() > 8)
        bars = std::stof(cmdStr.substr(8));
      pImpl->processor->postControlCommand(ControlCommand::Type::ForwardCommit,
                                           0, bars);
    } else if (cmdStr == "REC") {
      pImpl->processor->postControlCommand(
          ControlCommand::Type::StartRecording);
    } else if (cmdStr == "STOP") {
      pImpl->processor->postControlCommand(ControlCommand::Type::GlobalStop);
    } else if (cmdStr == "STOPREC") {
      pImpl->processor->postControlCommand(ControlCommand::Type::StopRecording);
    } else if (cmdStr.find("OVERDUB") == 0) {
      if (cmdStr == "OVERDUB" || cmdStr == "OVERDUB toggle") {
        pImpl->processor->postControlCommand(
            ControlCommand::Type::ToggleOverdub);
      } else {
        int val = (cmdStr.find("1") != std::string::npos) ? 1 : 0;
        pImpl->processor->postControlCommand(
            ControlCommand::Type::ToggleOverdub, val);
      }
    } else if (cmdStr.find("TEMPO") == 0 && cmdStr.size() > 6) {
      float bpm = std::stof(cmdStr.substr(6));
      pImpl->processor->postControlCommand(ControlCommand::Type::SetTempo, 0,
                                           bpm);
    } else if (cmdStr.find("MASTERVOLUME") == 0 && cmdStr.size() > 13) {
      float vol = std::stof(cmdStr.substr(13));
      pImpl->processor->postControlCommand(
          ControlCommand::Type::SetMasterVolume, 0, vol);
    } else if (cmdStr.find("LAYER") == 0) {
      // LAYER <idx> [SPEED|VOLUME|MUTE|REVERSE|CLEAR|STOP] ...
      // Parse layer index
      size_t pos = 6;
      if (pos < cmdStr.size()) {
        int layerIdx = std::stoi(cmdStr.substr(pos));
        // Find next space
        size_t nextSp = cmdStr.find(' ', pos);
        if (nextSp == std::string::npos) {
          // Just "LAYER <idx>" — set active layer
          pImpl->processor->postControlCommand(
              ControlCommand::Type::SetActiveLayer, layerIdx);
        } else {
          std::string sub = cmdStr.substr(nextSp + 1);
          if (sub.find("SPEED") == 0 && sub.size() > 6) {
            float speed = std::stof(sub.substr(6));
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerSpeed, layerIdx, speed);
          } else if (sub.find("VOLUME") == 0 && sub.size() > 7) {
            float vol = std::stof(sub.substr(7));
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerVolume, layerIdx, vol);
          } else if (sub.find("MUTE") == 0) {
            float val = (sub.size() > 5) ? std::stof(sub.substr(5)) : 1.0f;
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerMute, layerIdx, val);
          } else if (sub.find("REVERSE") == 0) {
            float val = (sub.size() > 8) ? std::stof(sub.substr(8)) : 1.0f;
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerReverse, layerIdx, val);
          } else if (sub == "CLEAR") {
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerClear, layerIdx);
          } else if (sub == "STOP") {
            pImpl->processor->postControlCommand(
                ControlCommand::Type::LayerStop, layerIdx);
          }
        }
      }
    } else if (cmdStr == "CLEARALL") {
      pImpl->processor->postControlCommand(
          ControlCommand::Type::ClearAllLayers);
    } else if (cmdStr.find("MODE") == 0 && cmdStr.size() > 5) {
      std::string mode = cmdStr.substr(5);
      int modeInt = 0;
      if (mode == "firstLoop")
        modeInt = 0;
      else if (mode == "freeMode")
        modeInt = 1;
      else if (mode == "traditional")
        modeInt = 2;
      else if (mode == "retrospective")
        modeInt = 3;
      else
        modeInt = std::stoi(mode);
      pImpl->processor->postControlCommand(ControlCommand::Type::SetRecordMode,
                                           modeInt);
    }
  };

  // ---- Root canvas accessor ----
  lua["root"] = pImpl->rootCanvas;

  // ---- Script management (exposed to Lua) ----
  lua["listUiScripts"] = [this]() -> sol::table {
    auto &lua = pImpl->lua;
    auto result = lua.create_table();
    if (!pImpl->currentScriptFile.existsAsFile())
      return result;

    auto dir = pImpl->currentScriptFile.getParentDirectory();
    auto scripts = getAvailableScripts(dir);
    for (size_t i = 0; i < scripts.size(); ++i) {
      auto entry = lua.create_table();
      entry["name"] = scripts[i].first;
      entry["path"] = scripts[i].second;
      result[i + 1] = entry;
    }
    return result;
  };

  lua["switchUiScript"] = [this](const std::string &path) {
    // Defer to next notifyUpdate() to avoid destroying Canvas nodes
    // while their callbacks are still on the stack
    pImpl->pendingSwitchPath = path;
  };

  lua["getCurrentScriptPath"] = [this]() -> std::string {
    return pImpl->currentScriptFile.getFullPathName().toStdString();
  };
}

// ============================================================================
// State snapshot
// ============================================================================

void LuaEngine::pushStateToLua() {
  auto &lua = pImpl->lua;
  auto *proc = pImpl->processor;
  if (!proc)
    return;

  auto state = lua.create_table();

  state["tempo"] = proc->getTempo();
  state["targetBPM"] = proc->getTargetBPM();
  state["samplesPerBar"] = proc->getSamplesPerBar();
  state["sampleRate"] = proc->getSampleRate();
  state["masterVolume"] = proc->getMasterVolume();
  state["isRecording"] = proc->isRecording();
  state["overdubEnabled"] = proc->isOverdubEnabled();
  state["activeLayer"] = proc->getActiveLayerIndex();
  state["forwardArmed"] = proc->isForwardCommitArmed();
  state["forwardBars"] = proc->getForwardCommitBars();

  // Record mode as string
  switch (proc->getRecordMode()) {
  case RecordMode::FirstLoop:
    state["recordMode"] = "firstLoop";
    break;
  case RecordMode::FreeMode:
    state["recordMode"] = "freeMode";
    break;
  case RecordMode::Traditional:
    state["recordMode"] = "traditional";
    break;
  case RecordMode::Retrospective:
    state["recordMode"] = "retrospective";
    break;
  }

  // Record mode as int for cycling
  state["recordModeInt"] = static_cast<int>(proc->getRecordMode());

  // Layers
  auto layers = lua.create_table();
  for (int i = 0; i < LooperProcessor::MAX_LAYERS; ++i) {
    auto &layer = proc->getLayer(i);
    auto lt = lua.create_table();
    lt["index"] = i;
    lt["length"] = layer.getLength();
    lt["position"] = layer.getPosition();
    lt["speed"] = layer.getSpeed();
    lt["reversed"] = layer.isReversed();
    lt["volume"] = layer.getVolume();

    // State as string
    switch (layer.getState()) {
    case LooperLayer::State::Empty:
      lt["state"] = "empty";
      break;
    case LooperLayer::State::Playing:
      lt["state"] = "playing";
      break;
    case LooperLayer::State::Recording:
      lt["state"] = "recording";
      break;
    case LooperLayer::State::Overdubbing:
      lt["state"] = "overdubbing";
      break;
    case LooperLayer::State::Muted:
      lt["state"] = "muted";
      break;
    case LooperLayer::State::Stopped:
      lt["state"] = "stopped";
      break;
    }

    layers[i + 1] = lt; // Lua is 1-indexed
  }
  state["layers"] = layers;

  // Capture buffer info
  auto &capture = proc->getCaptureBuffer();
  state["captureSize"] = capture.getSize();

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

  // Set up package.path so require() works from the script's directory
  auto dir = scriptFile.getParentDirectory().getFullPathName().toStdString();
  pImpl->lua["package"]["path"] = dir + "/?.lua;" + dir + "/?/init.lua";

  try {
    auto result =
        pImpl->lua.script_file(scriptFile.getFullPathName().toStdString());
    if (!result.valid()) {
      sol::error err = result;
      pImpl->lastError = err.what();
      std::fprintf(stderr, "LuaEngine: script load error: %s\n",
                   pImpl->lastError.c_str());
      pImpl->scriptLoaded = false;
      return false;
    }
  } catch (const std::exception &e) {
    pImpl->lastError = e.what();
    std::fprintf(stderr, "LuaEngine: script exception: %s\n",
                 pImpl->lastError.c_str());
    pImpl->scriptLoaded = false;
    return false;
  }

  // Call ui_init(root) if defined
  sol::function uiInit = pImpl->lua["ui_init"];
  if (uiInit.valid()) {
    try {
      // Clear existing children
      pImpl->rootCanvas->clearChildren();

      auto result = uiInit(pImpl->rootCanvas);
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

  if (!pImpl->scriptLoaded)
    return;

  sol::function fn = pImpl->lua["ui_resized"];
  if (fn.valid()) {
    try {
      auto result = fn(width, height);
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

  pushStateToLua();

  sol::function fn = pImpl->lua["ui_update"];
  if (fn.valid()) {
    try {
      auto result = fn(pImpl->lua["state"]);
      if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaEngine: ui_update error: %s\n", err.what());
      }
    } catch (const std::exception &e) {
      std::fprintf(stderr, "LuaEngine: ui_update exception: %s\n", e.what());
    }
  }
}

bool LuaEngine::isScriptLoaded() const { return pImpl->scriptLoaded; }

const std::string &LuaEngine::getLastError() const { return pImpl->lastError; }

juce::File LuaEngine::getScriptDirectory() const {
  if (pImpl->currentScriptFile.existsAsFile())
    return pImpl->currentScriptFile.getParentDirectory();
  return {};
}

// ============================================================================
// Script switching / hot-reload
// ============================================================================

bool LuaEngine::switchScript(const juce::File &scriptFile) {
  // Clear the current UI
  if (pImpl->rootCanvas)
    pImpl->rootCanvas->clearChildren();

  pImpl->scriptLoaded = false;

  // Reload into the same Lua VM (bindings are still registered)
  bool ok = loadScript(scriptFile);
  if (ok && pImpl->lastWidth > 0 && pImpl->lastHeight > 0) {
    notifyResized(pImpl->lastWidth, pImpl->lastHeight);
  }
  return ok;
}

bool LuaEngine::reloadCurrentScript() {
  if (!pImpl->currentScriptFile.existsAsFile())
    return false;
  std::fprintf(stderr, "LuaEngine: hot-reloading %s\n",
               pImpl->currentScriptFile.getFileName().toRawUTF8());
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

  if (!pImpl->currentScriptFile.existsAsFile())
    return;

  auto modTime = pImpl->currentScriptFile.getLastModificationTime();
  if (modTime != pImpl->lastModTime && pImpl->lastModTime != juce::Time()) {
    pImpl->lastModTime = modTime;
    reloadCurrentScript();
  }
}

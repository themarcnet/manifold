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
#include "../../engine/LooperProcessor.h"
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
  sol::state lua;
  ScriptableProcessor *processor = nullptr;
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
  
  // Primitive graph for Phase 3 wiring
  std::shared_ptr<dsp_primitives::PrimitiveGraph> primitiveGraph;

  // Lua VM is touched from message thread and OpenGL render thread.
  // Serialize all Lua state/function access.
  std::recursive_mutex luaMutex;

  // ============================================================================
  // OSC Callback Registry
  // ============================================================================
  struct OSCCallback {
    sol::function func;
    bool persistent;
    juce::String address;
  };

  std::map<juce::String, std::vector<OSCCallback>> oscCallbacks;
  std::mutex oscCallbacksMutex;

  struct PendingOSCMessage {
    juce::String address;
    std::vector<juce::var> args;
  };
  std::vector<PendingOSCMessage> pendingOSCMessages;
  std::mutex pendingOSCMessagesMutex;

  struct OSCQueryHandler {
    sol::function func;
    bool persistent;
  };
  std::map<juce::String, OSCQueryHandler> oscQueryHandlers;
  std::mutex oscQueryHandlersMutex;

  // ============================================================================
  // Looper Event Listeners
  // ============================================================================
  struct EventListener {
    sol::function func;
    bool persistent;
  };

  std::vector<EventListener> tempoChangedListeners;
  std::vector<EventListener> commitListeners;
  std::vector<EventListener> recordingChangedListeners;
  std::vector<EventListener> layerStateChangedListeners;
  std::vector<EventListener> stateChangedListeners;
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

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

  auto &lua = pImpl->lua;
  lua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                     sol::lib::table, sol::lib::package);

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
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onClick = [fn, impl]() mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
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

      "setOnMouseWheel",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onMouseWheel = [fn, impl](const juce::MouseEvent &e,
                                       const juce::MouseWheelDetails &wheel) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn(e.x, e.y, wheel.deltaY);
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onMouseWheel error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onMouseWheel = nullptr;
        }
      },

      "setOnDoubleClick",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onDoubleClick = [fn, impl]() mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn();
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onDoubleClick error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onDoubleClick = nullptr;
        }
      },

      "setOnMouseDown",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onMouseDown = [fn, impl](const juce::MouseEvent &e) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
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
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onMouseDrag = [fn, impl](const juce::MouseEvent &e) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
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
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onMouseUp = [fn, impl](const juce::MouseEvent &e) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
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

      "setWantsKeyboardFocus",
      [](Canvas &c, bool wantsFocus) { c.setWantsKeyboardFocus(wantsFocus); },

      "grabKeyboardFocus",
      [](Canvas &c) { c.grabKeyboardFocus(); },

      "hasKeyboardFocus",
      [](Canvas &c) { return c.hasKeyboardFocus(true); },

      "setOnKeyPress",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onKeyPress = [fn, impl](const juce::KeyPress &key) mutable -> bool {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            const auto mods = key.getModifiers();
            auto result = fn(
                key.getKeyCode(),
                static_cast<int>(key.getTextCharacter()),
                mods.isShiftDown(),
                mods.isCtrlDown() || mods.isCommandDown(),
                mods.isAltDown());
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onKeyPress error: %s\n", err.what());
              return false;
            }
            if (result.get_type() == sol::type::boolean) {
              return result.get<bool>();
            }
            return true;
          };
          c.setWantsKeyboardFocus(true);
        } else {
          c.onKeyPress = nullptr;
        }
      },

      "setOnMouseWheel",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onMouseWheel = [fn, impl](const juce::MouseEvent &e,
                                       const juce::MouseWheelDetails &wheel) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn(e.x, e.y, wheel.deltaY);
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onMouseWheel error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onMouseWheel = nullptr;
        }
      },

      "setOnDraw",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onDraw = [fn, impl](Canvas &self, juce::Graphics &g) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
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
      },

      // ---- OpenGL Support ----
      "setOpenGLEnabled",
      [](Canvas &c, bool enabled) { c.setOpenGLEnabled(enabled); },

      "isOpenGLEnabled",
      [](Canvas &c) { return c.isOpenGLEnabled(); },

      "setOnGLRender",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onGLRender = [fn, impl](Canvas &self) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn(std::ref(self));
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onGLRender error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onGLRender = nullptr;
        }
      },

      "setOnGLContextCreated",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onGLContextCreated = [fn, impl](Canvas &self) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn(std::ref(self));
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onGLContextCreated error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onGLContextCreated = nullptr;
        }
      },

      "setOnGLContextClosing",
      [this](Canvas &c, sol::function fn) {
        if (fn.valid()) {
          auto *impl = pImpl.get();
          c.onGLContextClosing = [fn, impl](Canvas &self) mutable {
            const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
            auto result = fn(std::ref(self));
            if (!result.valid()) {
              sol::error err = result;
              std::fprintf(stderr, "LuaEngine: onGLContextClosing error: %s\n",
                           err.what());
            }
          };
        } else {
          c.onGLContextClosing = nullptr;
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

  gfx["drawLine"] = [this](float x1, float y1, float x2, float y2) {
    if (pImpl->currentGraphics)
      pImpl->currentGraphics->drawLine(x1, y1, x2, y2);
  };

  // ---- OpenGL Functions (gl) ----
  using namespace juce::gl;
  auto gl = lua.create_named_table("gl");

  gl["clearColor"] = [](float r, float g, float b, float a) {
    glClearColor(r, g, b, a);
  };

  gl["clear"] = [](sol::optional<int> mask) {
    int m = mask.value_or(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glClear(m);
  };

  gl["viewport"] = [](int x, int y, int w, int h) { glViewport(x, y, w, h); };

  // Enable/disable caps
  gl["enable"] = [](int cap) { glEnable(cap); };
  gl["disable"] = [](int cap) { glDisable(cap); };

  // Blending
  gl["blendFunc"] = [](int sfactor, int dfactor) {
    glBlendFunc(sfactor, dfactor);
  };

  // Depth testing
  gl["depthFunc"] = [](int func) { glDepthFunc(func); };
  gl["depthMask"] = [](bool flag) { glDepthMask(flag ? GL_TRUE : GL_FALSE); };

  // Matrix operations (legacy style for simplicity)
  gl["matrixMode"] = [](int mode) { glMatrixMode(mode); };
  gl["loadIdentity"] = []() { glLoadIdentity(); };
  gl["pushMatrix"] = []() { glPushMatrix(); };
  gl["popMatrix"] = []() { glPopMatrix(); };
  gl["translate"] = [](float x, float y, float z) { glTranslatef(x, y, z); };
  gl["rotate"] = [](float angle, float x, float y, float z) {
    glRotatef(angle, x, y, z);
  };
  gl["scale"] = [](float x, float y, float z) { glScalef(x, y, z); };

  // Immediate mode drawing (legacy but simple)
  gl["begin"] = [](int mode) { glBegin(mode); };
  gl["end"] = []() { glEnd(); };
  gl["vertex2"] = [](float x, float y) { glVertex2f(x, y); };
  gl["vertex3"] = [](float x, float y, float z) { glVertex3f(x, y, z); };
  gl["color3"] = [](float r, float g, float b) { glColor3f(r, g, b); };
  gl["color4"] = [](float r, float g, float b, float a) { glColor4f(r, g, b, a); };
  gl["texCoord2"] = [](float s, float t) { glTexCoord2f(s, t); };
  gl["normal3"] = [](float x, float y, float z) { glNormal3f(x, y, z); };

  // Programmable pipeline support (shaders/programs/buffers)
  gl["createShader"] = [](int shaderType) -> unsigned int {
    return static_cast<unsigned int>(glCreateShader((GLenum)shaderType));
  };

  gl["deleteShader"] = [](unsigned int shaderId) {
    glDeleteShader(static_cast<GLuint>(shaderId));
  };

  gl["shaderSource"] = [](unsigned int shaderId, const std::string &source) {
    const char *src = source.c_str();
    GLint length = static_cast<GLint>(source.size());
    glShaderSource(static_cast<GLuint>(shaderId), 1, &src, &length);
  };

  gl["compileShader"] = [](unsigned int shaderId) {
    glCompileShader(static_cast<GLuint>(shaderId));
  };

  gl["getShaderCompileStatus"] = [](unsigned int shaderId) -> bool {
    GLint status = GL_FALSE;
    glGetShaderiv(static_cast<GLuint>(shaderId), GL_COMPILE_STATUS, &status);
    return status == GL_TRUE;
  };

  gl["getShaderInfoLog"] = [](unsigned int shaderId) -> std::string {
    GLint length = 0;
    glGetShaderiv(static_cast<GLuint>(shaderId), GL_INFO_LOG_LENGTH, &length);
    if (length <= 1)
      return {};

    std::string log(static_cast<size_t>(length), '\0');
    GLsizei written = 0;
    glGetShaderInfoLog(static_cast<GLuint>(shaderId), length, &written,
                       log.data());
    if (written > 0 && static_cast<size_t>(written) < log.size())
      log.resize(static_cast<size_t>(written));
    return log;
  };

  gl["createProgram"] = []() -> unsigned int {
    return static_cast<unsigned int>(glCreateProgram());
  };

  gl["deleteProgram"] = [](unsigned int programId) {
    glDeleteProgram(static_cast<GLuint>(programId));
  };

  gl["attachShader"] = [](unsigned int programId, unsigned int shaderId) {
    glAttachShader(static_cast<GLuint>(programId), static_cast<GLuint>(shaderId));
  };

  gl["detachShader"] = [](unsigned int programId, unsigned int shaderId) {
    glDetachShader(static_cast<GLuint>(programId), static_cast<GLuint>(shaderId));
  };

  gl["linkProgram"] = [](unsigned int programId) {
    glLinkProgram(static_cast<GLuint>(programId));
  };

  gl["useProgram"] = [](unsigned int programId) {
    glUseProgram(static_cast<GLuint>(programId));
  };

  gl["getProgramLinkStatus"] = [](unsigned int programId) -> bool {
    GLint status = GL_FALSE;
    glGetProgramiv(static_cast<GLuint>(programId), GL_LINK_STATUS, &status);
    return status == GL_TRUE;
  };

  gl["getProgramInfoLog"] = [](unsigned int programId) -> std::string {
    GLint length = 0;
    glGetProgramiv(static_cast<GLuint>(programId), GL_INFO_LOG_LENGTH, &length);
    if (length <= 1)
      return {};

    std::string log(static_cast<size_t>(length), '\0');
    GLsizei written = 0;
    glGetProgramInfoLog(static_cast<GLuint>(programId), length, &written,
                        log.data());
    if (written > 0 && static_cast<size_t>(written) < log.size())
      log.resize(static_cast<size_t>(written));
    return log;
  };

  gl["getAttribLocation"] = [](unsigned int programId,
                                const std::string &name) -> int {
    return glGetAttribLocation(static_cast<GLuint>(programId), name.c_str());
  };

  gl["getUniformLocation"] = [](unsigned int programId,
                                 const std::string &name) -> int {
    return glGetUniformLocation(static_cast<GLuint>(programId), name.c_str());
  };

  gl["uniform1f"] = [](int location, float v0) { glUniform1f(location, v0); };
  gl["uniform2f"] = [](int location, float v0, float v1) {
    glUniform2f(location, v0, v1);
  };
  gl["uniform3f"] = [](int location, float v0, float v1, float v2) {
    glUniform3f(location, v0, v1, v2);
  };
  gl["uniform4f"] = [](int location, float v0, float v1, float v2,
                        float v3) { glUniform4f(location, v0, v1, v2, v3); };
  gl["uniform1i"] = [](int location, int v0) { glUniform1i(location, v0); };
  gl["uniformMatrix4"] = [](int location, sol::table values,
                              sol::optional<bool> transpose) {
    const bool tx = transpose.value_or(false);
    const size_t count = values.size();
    if (count < 16)
      return;

    std::array<float, 16> matrix{};
    for (size_t i = 0; i < 16; ++i) {
      auto value = values.get<sol::optional<float>>(i + 1);
      matrix[i] = value.value_or(0.0f);
    }

    glUniformMatrix4fv(location, 1, tx ? GL_TRUE : GL_FALSE, matrix.data());
  };

  gl["createBuffer"] = []() -> unsigned int {
    GLuint id = 0;
    glGenBuffers(1, &id);
    return static_cast<unsigned int>(id);
  };

  gl["deleteBuffer"] = [](unsigned int bufferId) {
    GLuint id = static_cast<GLuint>(bufferId);
    glDeleteBuffers(1, &id);
  };

  gl["bindBuffer"] = [](int target, unsigned int bufferId) {
    glBindBuffer(static_cast<GLenum>(target), static_cast<GLuint>(bufferId));
  };

  gl["bufferDataFloat"] = [](int target, sol::table values, int usage) {
    const size_t count = values.size();
    std::vector<float> data;
    data.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
      auto value = values.get<sol::optional<float>>(i);
      data.push_back(value.value_or(0.0f));
    }

    glBufferData(static_cast<GLenum>(target),
                 static_cast<GLsizeiptr>(data.size() * sizeof(float)),
                 data.empty() ? nullptr : data.data(),
                 static_cast<GLenum>(usage));
  };

  gl["bufferSubDataFloat"] = [](int target, int offsetBytes, sol::table values) {
    const size_t count = values.size();
    std::vector<float> data;
    data.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
      auto value = values.get<sol::optional<float>>(i);
      data.push_back(value.value_or(0.0f));
    }

    glBufferSubData(static_cast<GLenum>(target),
                    static_cast<GLintptr>(offsetBytes),
                    static_cast<GLsizeiptr>(data.size() * sizeof(float)),
                    data.empty() ? nullptr : data.data());
  };

  gl["bufferDataUInt16"] = [](int target, sol::table values, int usage) {
    const size_t count = values.size();
    std::vector<uint16_t> data;
    data.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
      auto value = values.get<sol::optional<int>>(i);
      data.push_back(static_cast<uint16_t>(value.value_or(0)));
    }

    glBufferData(static_cast<GLenum>(target),
                 static_cast<GLsizeiptr>(data.size() * sizeof(uint16_t)),
                 data.empty() ? nullptr : data.data(),
                 static_cast<GLenum>(usage));
  };

  gl["createVertexArray"] = []() -> unsigned int {
    GLuint id = 0;
    glGenVertexArrays(1, &id);
    return static_cast<unsigned int>(id);
  };

  gl["bindVertexArray"] = [](unsigned int vaoId) {
    glBindVertexArray(static_cast<GLuint>(vaoId));
  };

  gl["deleteVertexArray"] = [](unsigned int vaoId) {
    GLuint id = static_cast<GLuint>(vaoId);
    glDeleteVertexArrays(1, &id);
  };

  gl["enableVertexAttribArray"] = [](unsigned int index) {
    glEnableVertexAttribArray(static_cast<GLuint>(index));
  };

  gl["disableVertexAttribArray"] = [](unsigned int index) {
    glDisableVertexAttribArray(static_cast<GLuint>(index));
  };

  gl["vertexAttribPointer"] = [](unsigned int index, int size, int type,
                                  bool normalized, int strideBytes,
                                  int offsetBytes) {
    glVertexAttribPointer(
        static_cast<GLuint>(index), size, static_cast<GLenum>(type),
        normalized ? GL_TRUE : GL_FALSE, static_cast<GLsizei>(strideBytes),
        reinterpret_cast<const void *>(static_cast<uintptr_t>(offsetBytes)));
  };

  gl["drawArrays"] = [](int mode, int first, int count) {
    glDrawArrays(static_cast<GLenum>(mode), first, count);
  };

  gl["drawElements"] = [](int mode, int count, int indexType,
                           int indexOffsetBytes) {
    glDrawElements(static_cast<GLenum>(mode), count, static_cast<GLenum>(indexType),
                   reinterpret_cast<const void *>(static_cast<uintptr_t>(indexOffsetBytes)));
  };

  gl["createTexture"] = []() -> unsigned int {
    GLuint id = 0;
    glGenTextures(1, &id);
    return static_cast<unsigned int>(id);
  };

  gl["deleteTexture"] = [](unsigned int textureId) {
    GLuint id = static_cast<GLuint>(textureId);
    glDeleteTextures(1, &id);
  };

  gl["activeTexture"] = [](int textureUnit) {
    glActiveTexture(static_cast<GLenum>(textureUnit));
  };

  gl["bindTexture"] = [](int target, unsigned int textureId) {
    glBindTexture(static_cast<GLenum>(target), static_cast<GLuint>(textureId));
  };

  gl["texParameteri"] = [](int target, int pname, int value) {
    glTexParameteri(static_cast<GLenum>(target), static_cast<GLenum>(pname), value);
  };

  gl["texImage2DRGBA"] = [](int target, int level, int width, int height,
                              sol::optional<sol::table> pixelData) {
    std::vector<uint8_t> data;
    const uint8_t *ptr = nullptr;

    if (pixelData.has_value()) {
      auto table = pixelData.value();
      const size_t count = table.size();
      data.reserve(count);
      for (size_t i = 1; i <= count; ++i) {
        auto value = table.get<sol::optional<int>>(i);
        data.push_back(
            static_cast<uint8_t>(std::clamp(value.value_or(0), 0, 255)));
      }
      ptr = data.empty() ? nullptr : data.data();
    }

    glTexImage2D(static_cast<GLenum>(target), level, GL_RGBA8, width, height, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, ptr);
  };

  gl["texSubImage2DRGBA"] = [](int target, int level, int xoffset, int yoffset,
                                 int width, int height, sol::table pixelData) {
    const size_t count = pixelData.size();
    std::vector<uint8_t> data;
    data.reserve(count);
    for (size_t i = 1; i <= count; ++i) {
      auto value = pixelData.get<sol::optional<int>>(i);
      data.push_back(
          static_cast<uint8_t>(std::clamp(value.value_or(0), 0, 255)));
    }

    glTexSubImage2D(static_cast<GLenum>(target), level, xoffset, yoffset, width,
                    height, GL_RGBA, GL_UNSIGNED_BYTE,
                    data.empty() ? nullptr : data.data());
  };

  gl["generateMipmap"] = [](int target) {
    glGenerateMipmap(static_cast<GLenum>(target));
  };

  gl["createFramebuffer"] = []() -> unsigned int {
    GLuint id = 0;
    glGenFramebuffers(1, &id);
    return static_cast<unsigned int>(id);
  };

  gl["deleteFramebuffer"] = [](unsigned int framebufferId) {
    GLuint id = static_cast<GLuint>(framebufferId);
    glDeleteFramebuffers(1, &id);
  };

  gl["bindFramebuffer"] = [](int target, unsigned int framebufferId) {
    glBindFramebuffer(static_cast<GLenum>(target), static_cast<GLuint>(framebufferId));
  };

  gl["framebufferTexture2D"] = [](int target, int attachment,
                                   int texTarget, unsigned int textureId,
                                   int level) {
    glFramebufferTexture2D(static_cast<GLenum>(target), static_cast<GLenum>(attachment),
                           static_cast<GLenum>(texTarget),
                           static_cast<GLuint>(textureId), level);
  };

  gl["checkFramebufferStatus"] = [](int target) -> int {
    return static_cast<int>(glCheckFramebufferStatus(static_cast<GLenum>(target)));
  };

  gl["drawBuffers"] = [](sol::table buffers) {
    const size_t count = buffers.size();
    std::vector<GLenum> values;
    values.reserve(count);
    for (size_t i = 1; i <= count; ++i)
      values.push_back(static_cast<GLenum>(buffers.get_or<int>(i, GL_COLOR_ATTACHMENT0)));

    if (!values.empty())
      glDrawBuffers(static_cast<GLsizei>(values.size()), values.data());
  };

  gl["createRenderbuffer"] = []() -> unsigned int {
    GLuint id = 0;
    glGenRenderbuffers(1, &id);
    return static_cast<unsigned int>(id);
  };

  gl["deleteRenderbuffer"] = [](unsigned int renderbufferId) {
    GLuint id = static_cast<GLuint>(renderbufferId);
    glDeleteRenderbuffers(1, &id);
  };

  gl["bindRenderbuffer"] = [](int target, unsigned int renderbufferId) {
    glBindRenderbuffer(static_cast<GLenum>(target), static_cast<GLuint>(renderbufferId));
  };

  gl["renderbufferStorage"] = [](int target, int internalFormat, int width,
                                  int height) {
    glRenderbufferStorage(static_cast<GLenum>(target),
                          static_cast<GLenum>(internalFormat), width, height);
  };

  gl["framebufferRenderbuffer"] = [](int target, int attachment,
                                      int renderbufferTarget,
                                      unsigned int renderbufferId) {
    glFramebufferRenderbuffer(static_cast<GLenum>(target),
                              static_cast<GLenum>(attachment),
                              static_cast<GLenum>(renderbufferTarget),
                              static_cast<GLuint>(renderbufferId));
  };

  gl["blitFramebuffer"] = [](int srcX0, int srcY0, int srcX1, int srcY1,
                              int dstX0, int dstY0, int dstX1, int dstY1,
                              int mask, int filter) {
    glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1,
                      static_cast<GLbitfield>(mask),
                      static_cast<GLenum>(filter));
  };

  gl["clearDepth"] = [](double depth) { glClearDepth(depth); };
  gl["blendEquation"] = [](int mode) {
    glBlendEquation(static_cast<GLenum>(mode));
  };
  gl["scissor"] = [](int x, int y, int width, int height) {
    glScissor(x, y, width, height);
  };
  gl["cullFace"] = [](int mode) { glCullFace(static_cast<GLenum>(mode)); };

  gl["lineWidth"] = [](float width) { glLineWidth(width); };

  gl["getError"] = []() -> int { return static_cast<int>(glGetError()); };

  // ---- OpenGL Constants ----
  lua["GL"] = lua.create_table_with(
      // Buffer bits
      "COLOR_BUFFER_BIT", GL_COLOR_BUFFER_BIT, "DEPTH_BUFFER_BIT",
      GL_DEPTH_BUFFER_BIT, "STENCIL_BUFFER_BIT", GL_STENCIL_BUFFER_BIT,
      // Primitives
      "POINTS", GL_POINTS, "LINES", GL_LINES, "LINE_STRIP", GL_LINE_STRIP,
      "LINE_LOOP", GL_LINE_LOOP, "TRIANGLES", GL_TRIANGLES, "TRIANGLE_STRIP",
      GL_TRIANGLE_STRIP, "TRIANGLE_FAN", GL_TRIANGLE_FAN, "QUADS", GL_QUADS,
      "QUAD_STRIP", GL_QUAD_STRIP, "POLYGON", GL_POLYGON,
      // Capabilities
      "BLEND", GL_BLEND, "DEPTH_TEST", GL_DEPTH_TEST, "CULL_FACE", GL_CULL_FACE,
      "LIGHTING", GL_LIGHTING, "LIGHT0", GL_LIGHT0, "LIGHT1", GL_LIGHT1,
      "TEXTURE_2D", GL_TEXTURE_2D, "SCISSOR_TEST", GL_SCISSOR_TEST,
      // Blend factors
      "ZERO", GL_ZERO, "ONE", GL_ONE, "SRC_COLOR", GL_SRC_COLOR,
      "ONE_MINUS_SRC_COLOR", GL_ONE_MINUS_SRC_COLOR, "SRC_ALPHA", GL_SRC_ALPHA,
      "ONE_MINUS_SRC_ALPHA", GL_ONE_MINUS_SRC_ALPHA,
      "DST_ALPHA", GL_DST_ALPHA, "ONE_MINUS_DST_ALPHA", GL_ONE_MINUS_DST_ALPHA,
      "FUNC_ADD", GL_FUNC_ADD,
      // Depth functions
      "NEVER", GL_NEVER, "LESS", GL_LESS, "EQUAL", GL_EQUAL, "LEQUAL", GL_LEQUAL,
      "GREATER", GL_GREATER, "NOTEQUAL", GL_NOTEQUAL, "GEQUAL", GL_GEQUAL,
      "ALWAYS", GL_ALWAYS,
      // Cull modes
      "FRONT", GL_FRONT, "BACK", GL_BACK, "FRONT_AND_BACK", GL_FRONT_AND_BACK,
      // Matrix modes
      "MODELVIEW", GL_MODELVIEW, "PROJECTION", GL_PROJECTION, "TEXTURE",
      GL_TEXTURE,
      // Shader/program pipeline
      "VERTEX_SHADER", GL_VERTEX_SHADER, "FRAGMENT_SHADER", GL_FRAGMENT_SHADER,
      "COMPILE_STATUS", GL_COMPILE_STATUS, "LINK_STATUS", GL_LINK_STATUS,
      "INFO_LOG_LENGTH", GL_INFO_LOG_LENGTH,
      // Buffer API
      "ARRAY_BUFFER", GL_ARRAY_BUFFER, "ELEMENT_ARRAY_BUFFER",
      GL_ELEMENT_ARRAY_BUFFER, "STATIC_DRAW", GL_STATIC_DRAW, "DYNAMIC_DRAW",
      GL_DYNAMIC_DRAW, "STREAM_DRAW", GL_STREAM_DRAW,
      "READ_FRAMEBUFFER", GL_READ_FRAMEBUFFER, "DRAW_FRAMEBUFFER",
      GL_DRAW_FRAMEBUFFER,
      // Framebuffer / renderbuffer
      "FRAMEBUFFER", GL_FRAMEBUFFER, "RENDERBUFFER", GL_RENDERBUFFER,
      "FRAMEBUFFER_COMPLETE", GL_FRAMEBUFFER_COMPLETE,
      "COLOR_ATTACHMENT0", GL_COLOR_ATTACHMENT0, "DEPTH_ATTACHMENT",
      GL_DEPTH_ATTACHMENT, "DEPTH_STENCIL_ATTACHMENT", GL_DEPTH_STENCIL_ATTACHMENT,
      "DEPTH24_STENCIL8", GL_DEPTH24_STENCIL8,
      // Texture API
      "TEXTURE0", GL_TEXTURE0, "TEXTURE1", GL_TEXTURE1, "TEXTURE2", GL_TEXTURE2,
      "TEXTURE_MIN_FILTER", GL_TEXTURE_MIN_FILTER, "TEXTURE_MAG_FILTER",
      GL_TEXTURE_MAG_FILTER, "TEXTURE_WRAP_S", GL_TEXTURE_WRAP_S,
      "TEXTURE_WRAP_T", GL_TEXTURE_WRAP_T, "CLAMP_TO_EDGE", GL_CLAMP_TO_EDGE,
      "REPEAT", GL_REPEAT, "LINEAR", GL_LINEAR, "NEAREST", GL_NEAREST,
      "RGBA", GL_RGBA, "RGBA8", GL_RGBA8,
      // Types
      "FLOAT", GL_FLOAT, "UNSIGNED_BYTE", GL_UNSIGNED_BYTE,
      "UNSIGNED_SHORT", GL_UNSIGNED_SHORT, "UNSIGNED_INT", GL_UNSIGNED_INT,
      // Error values
      "NO_ERROR", GL_NO_ERROR, "INVALID_ENUM", GL_INVALID_ENUM,
      "INVALID_VALUE", GL_INVALID_VALUE, "INVALID_OPERATION",
      GL_INVALID_OPERATION, "OUT_OF_MEMORY", GL_OUT_OF_MEMORY);

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
    if (!pImpl->processor || numBuckets <= 0)
      return result;

    std::vector<float> peaks;
    if (!pImpl->processor->computeLayerPeaks(layerIdx, numBuckets, peaks)) {
      return result;
    }
    for (size_t i = 0; i < peaks.size(); ++i)
      result[i + 1] = peaks[i];

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

    std::vector<float> peaks;
    if (!pImpl->processor->computeCapturePeaks(startAgo, endAgo, numBuckets,
                                               peaks)) {
      return result;
    }
    for (size_t i = 0; i < peaks.size(); ++i)
      result[i + 1] = peaks[i];

    return result;
  };

  // ---- command() ----
  // Routes through the shared CommandParser (same parser as ControlServer IPC).
  // One source of truth for command string → ControlCommand.
  lua["command"] = [this](sol::variadic_args va) {
    if (!pImpl->processor || va.size() == 0)
      return;

    // Build command string from variadic args
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

    // Parse using the shared protocol parser
    auto result = CommandParser::parse(
        cmdStr,
        pImpl->processor ? &pImpl->processor->getEndpointRegistry() : nullptr);

    if (result.usedLegacySyntax) {
      static std::atomic<int> legacySyntaxWarnings{0};
      const int count =
          legacySyntaxWarnings.fetch_add(1, std::memory_order_relaxed) + 1;
      if (count <= 5 || (count % 100) == 0) {
        fprintf(stderr,
                "[LuaEngine] deprecated legacy command syntax '%s' used "
                "(count=%d). Prefer canonical SET/GET/TRIGGER paths.\n",
                result.legacyVerb.c_str(), count);
      }
    }

    if (!result.warningCode.empty()) {
      static std::atomic<int> parserWarnings{0};
      const int count = parserWarnings.fetch_add(1, std::memory_order_relaxed) + 1;
      if (count <= 5 || (count % 100) == 0) {
        fprintf(stderr, "[LuaEngine] %s: %s (count=%d)\n",
                result.warningCode.c_str(), result.warningMessage.c_str(), count);
      }
    }

    switch (result.kind) {
    case ParseResult::Kind::Enqueue:
      pImpl->processor->postControlCommandPayload(result.command);
      break;
    case ParseResult::Kind::NoOpWarning:
      break;
    case ParseResult::Kind::Error:
      fprintf(stderr, "[LuaEngine] command error: %s (input: %s)\n",
              result.errorMessage.c_str(), cmdStr.c_str());
      break;
    default:
      // Queries (STATE/PING/DIAGNOSE), WATCH, INJECT, INJECTION_STATUS
      // are not meaningful from the UI — ignore silently
      break;
    }
  };

  // ---- Root canvas accessor ----
  lua["root"] = pImpl->rootCanvas;

  // ---- Direct seek binding (bypasses CommandParser for reliability) ----
  lua["seekLayer"] = [this](int layerIdx, float normalizedPos) {
    if (!pImpl->processor)
      return;
    if (layerIdx < 0 || layerIdx >= 4)
      return;
    ControlCommand cmd;
    cmd.operation = ControlOperation::Legacy;
    cmd.type = ControlCommand::Type::LayerSeek;
    cmd.intParam = layerIdx;
    cmd.floatParam = normalizedPos;
    pImpl->processor->postControlCommandPayload(cmd);
  };

  // ---- Generic path-based parameter access (Phase 1 DSP scripting) ----
  lua["setParam"] = [this](const std::string &path, float value) -> bool {
    if (!pImpl->processor)
      return false;
    return pImpl->processor->setParamByPath(path, value);
  };

  lua["getParam"] = [this](const std::string &path) -> float {
    if (!pImpl->processor)
      return 0.0f;
    return pImpl->processor->getParamByPath(path);
  };

  lua["hasEndpoint"] = [this](const std::string &path) -> bool {
    if (!pImpl->processor)
      return false;
    return pImpl->processor->hasEndpoint(path);
  };

  lua["reloadDspScript"] = [this]() -> bool {
    if (!pImpl->processor)
      return false;
    auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor);
    if (!lp)
      return false;
    return lp->reloadDspScript();
  };

  lua["loadDspScript"] = [this](const std::string &path) -> bool {
    if (!pImpl->processor)
      return false;
    auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor);
    if (!lp)
      return false;
    return lp->loadDspScript(juce::File(path));
  };

  lua["loadDspScriptFromString"] =
      [this](const std::string &code, const std::string &sourceName) -> bool {
    if (!pImpl->processor)
      return false;
    auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor);
    if (!lp)
      return false;
    return lp->loadDspScriptFromString(code, sourceName);
  };

  // Debug helper: write text buffers to disk (used by live DSP editor)
  lua["writeTextFile"] = [](const std::string &path,
                            const std::string &text) -> bool {
    juce::File outFile(path);
    return outFile.replaceWithText(juce::String(text), false, false, "\n");
  };

  lua["setClipboardText"] = [](const std::string &text) -> bool {
    juce::SystemClipboard::copyTextToClipboard(juce::String(text));
    return true;
  };

  lua["getClipboardText"] = []() -> std::string {
    return juce::SystemClipboard::getTextFromClipboard().toStdString();
  };

  lua["isDspScriptLoaded"] = [this]() -> bool {
    if (!pImpl->processor)
      return false;
    auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor);
    if (!lp)
      return false;
    return lp->isDspScriptLoaded();
  };

  lua["getDspScriptLastError"] = [this]() -> std::string {
    if (!pImpl->processor)
      return "";
    auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor);
    if (!lp)
      return "";
    return lp->getDspScriptLastError();
  };

  // ---- DSP Primitives factory (Phase 2) ----
  // Note: These create C++ primitives that Lua can configure.
  // The actual audio processing happens on the audio thread - Lua only configures.
  lua["Primitives"] = lua.create_table();

  // LoopBuffer factory
  lua["Primitives"]["LoopBuffer"] = lua.create_table();
  lua["Primitives"]["LoopBuffer"]["new"] = [](int sizeSamples, int channels = 2) {
    auto buf = std::make_shared<dsp_primitives::LoopBufferWrapper>();
    buf->setSize(sizeSamples, channels);
    return buf;
  };

  // Playhead factory
  lua["Primitives"]["Playhead"] = lua.create_table();
  lua["Primitives"]["Playhead"]["new"] = [](int length = 0) {
    auto ph = std::make_shared<dsp_primitives::PlayheadWrapper>();
    ph->setLoopLength(length);
    return ph;
  };

  // CaptureBuffer factory
  lua["Primitives"]["CaptureBuffer"] = lua.create_table();
  lua["Primitives"]["CaptureBuffer"]["new"] = [](int sizeSamples, int channels = 2) {
    auto cap = std::make_shared<dsp_primitives::CaptureBufferWrapper>();
    cap->setSize(sizeSamples, channels);
    return cap;
  };

  // Quantizer factory
  lua["Primitives"]["Quantizer"] = lua.create_table();
  lua["Primitives"]["Quantizer"]["new"] = [](double sampleRate) {
    auto q = std::make_shared<dsp_primitives::QuantizerWrapper>();
    q->setSampleRate(sampleRate);
    return q;
  };

  // ---- Primitive Wiring API (Phase 3) ----
  // Use the graph from LooperProcessor if available
  std::shared_ptr<dsp_primitives::PrimitiveGraph> graph;
  if (pImpl->processor) {
    auto* lp = dynamic_cast<LooperProcessor*>(pImpl->processor);
    if (lp) {
      graph = lp->getPrimitiveGraph();
    }
  }
  if (!graph) {
    graph = std::make_shared<dsp_primitives::PrimitiveGraph>();
  }
  
  // Register PlayheadNode usertype (no inheritance)
  lua.new_usertype<dsp_primitives::PlayheadNode>("PlayheadNode",
    sol::constructors<std::shared_ptr<dsp_primitives::PlayheadNode>()>(),
    "setLoopLength", &dsp_primitives::PlayheadNode::setLoopLength,
    "setSpeed", &dsp_primitives::PlayheadNode::setSpeed,
    "setReversed", &dsp_primitives::PlayheadNode::setReversed,
    "play", &dsp_primitives::PlayheadNode::play,
    "pause", &dsp_primitives::PlayheadNode::pause,
    "stop", &dsp_primitives::PlayheadNode::stop,
    "getLoopLength", &dsp_primitives::PlayheadNode::getLoopLength,
    "getSpeed", &dsp_primitives::PlayheadNode::getSpeed,
    "isReversed", &dsp_primitives::PlayheadNode::isReversed,
    "isPlaying", &dsp_primitives::PlayheadNode::isPlaying,
    "getNormalizedPosition", &dsp_primitives::PlayheadNode::getNormalizedPosition
  );
  
  // Register PassthroughNode usertype
  lua.new_usertype<dsp_primitives::PassthroughNode>("PassthroughNode",
    sol::constructors<std::shared_ptr<dsp_primitives::PassthroughNode>(int)>()
  );
  
  // Register OscillatorNode usertype
  lua.new_usertype<dsp_primitives::OscillatorNode>("OscillatorNode",
    sol::constructors<std::shared_ptr<dsp_primitives::OscillatorNode>()>(),
    "setFrequency", &dsp_primitives::OscillatorNode::setFrequency,
    "setAmplitude", &dsp_primitives::OscillatorNode::setAmplitude,
    "setEnabled", &dsp_primitives::OscillatorNode::setEnabled,
    "setWaveform", &dsp_primitives::OscillatorNode::setWaveform,
    "getFrequency", &dsp_primitives::OscillatorNode::getFrequency,
    "getAmplitude", &dsp_primitives::OscillatorNode::getAmplitude,
    "isEnabled", &dsp_primitives::OscillatorNode::isEnabled,
    "getWaveform", &dsp_primitives::OscillatorNode::getWaveform
  );
  
  // Register ReverbNode usertype
  lua.new_usertype<dsp_primitives::ReverbNode>("ReverbNode",
    sol::constructors<std::shared_ptr<dsp_primitives::ReverbNode>()>(),
    "setRoomSize", &dsp_primitives::ReverbNode::setRoomSize,
    "setDamping", &dsp_primitives::ReverbNode::setDamping,
    "setWetLevel", &dsp_primitives::ReverbNode::setWetLevel,
    "setDryLevel", &dsp_primitives::ReverbNode::setDryLevel,
    "setWidth", &dsp_primitives::ReverbNode::setWidth,
    "getRoomSize", &dsp_primitives::ReverbNode::getRoomSize,
    "getDamping", &dsp_primitives::ReverbNode::getDamping,
    "getWetLevel", &dsp_primitives::ReverbNode::getWetLevel,
    "getDryLevel", &dsp_primitives::ReverbNode::getDryLevel,
    "getWidth", &dsp_primitives::ReverbNode::getWidth
  );

  // Register FilterNode usertype
  lua.new_usertype<dsp_primitives::FilterNode>("FilterNode",
    sol::constructors<std::shared_ptr<dsp_primitives::FilterNode>()>(),
    "setCutoff", &dsp_primitives::FilterNode::setCutoff,
    "setResonance", &dsp_primitives::FilterNode::setResonance,
    "setMix", &dsp_primitives::FilterNode::setMix,
    "getCutoff", &dsp_primitives::FilterNode::getCutoff,
    "getResonance", &dsp_primitives::FilterNode::getResonance,
    "getMix", &dsp_primitives::FilterNode::getMix
  );

  // Register DistortionNode usertype
  lua.new_usertype<dsp_primitives::DistortionNode>("DistortionNode",
    sol::constructors<std::shared_ptr<dsp_primitives::DistortionNode>()>(),
    "setDrive", &dsp_primitives::DistortionNode::setDrive,
    "setMix", &dsp_primitives::DistortionNode::setMix,
    "setOutput", &dsp_primitives::DistortionNode::setOutput,
    "getDrive", &dsp_primitives::DistortionNode::getDrive,
    "getMix", &dsp_primitives::DistortionNode::getMix,
    "getOutput", &dsp_primitives::DistortionNode::getOutput
  );
  
  // Node factories
  lua["Primitives"]["PlayheadNode"] = lua.create_table();
  lua["Primitives"]["PlayheadNode"]["new"] = [graph]() {
    auto node = std::make_shared<dsp_primitives::PlayheadNode>();
    graph->registerNode(node);
    return node;
  };
  
  lua["Primitives"]["PassthroughNode"] = lua.create_table();
  lua["Primitives"]["PassthroughNode"]["new"] = [graph](int numChannels) {
    auto node = std::make_shared<dsp_primitives::PassthroughNode>(numChannels);
    graph->registerNode(node);
    return node;
  };
  
  lua["Primitives"]["OscillatorNode"] = lua.create_table();
  lua["Primitives"]["OscillatorNode"]["new"] = [graph]() {
    auto node = std::make_shared<dsp_primitives::OscillatorNode>();
    graph->registerNode(node);
    return node;
  };
  
  lua["Primitives"]["ReverbNode"] = lua.create_table();
  lua["Primitives"]["ReverbNode"]["new"] = [graph]() {
    auto node = std::make_shared<dsp_primitives::ReverbNode>();
    graph->registerNode(node);
    return node;
  };

  lua["Primitives"]["FilterNode"] = lua.create_table();
  lua["Primitives"]["FilterNode"]["new"] = [graph]() {
    auto node = std::make_shared<dsp_primitives::FilterNode>();
    graph->registerNode(node);
    return node;
  };

  lua["Primitives"]["DistortionNode"] = lua.create_table();
  lua["Primitives"]["DistortionNode"]["new"] = [graph]() {
    auto node = std::make_shared<dsp_primitives::DistortionNode>();
    graph->registerNode(node);
    return node;
  };
  
  // Generic node connection helper (supports all registered node types)
  auto toPrimitiveNode = [](const sol::object& obj) -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
    if (obj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
    }
    return nullptr;
  };

  lua["connectNodes"] = [graph, toPrimitiveNode](const sol::object& fromObj,
                                                  const sol::object& toObj) -> bool {
    auto from = toPrimitiveNode(fromObj);
    auto to = toPrimitiveNode(toObj);
    if (!from || !to) {
      return false;
    }
    return graph->connect(from, 0, to, 0);
  };
  
  lua["hasGraphCycle"] = [graph]() -> bool {
    return graph->hasCycle();
  };
  
  lua["getGraphNodeCount"] = [graph]() -> int {
    return static_cast<int>(graph->getNodeCount());
  };
  
  lua["getGraphConnectionCount"] = [graph]() -> int {
    return static_cast<int>(graph->getConnectionCount());
  };

  lua["clearGraph"] = [graph]() {
    graph->clear();
  };
  
  // Enable/disable graph processing
  lua["setGraphProcessingEnabled"] = [this](bool enabled) -> bool {
    if (!pImpl->processor) return false;
    auto* lp = dynamic_cast<LooperProcessor*>(pImpl->processor);
    if (lp) {
      lp->setGraphProcessingEnabled(enabled);
      return lp->isGraphProcessingEnabled() == enabled;
    }
    return false;
  };
  
  lua["isGraphProcessingEnabled"] = [this]() -> bool {
    if (!pImpl->processor) return false;
    auto* lp = dynamic_cast<LooperProcessor*>(pImpl->processor);
    if (lp) {
      return lp->isGraphProcessingEnabled();
    }
    return false;
  };

  // ---- Script management (exposed to Lua) ----
  lua["listUiScripts"] = [this]() -> sol::table {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
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

  // High-resolution time for animations (seconds since app start)
  lua["getTime"] = []() -> double {
    static const auto startTime = juce::Time::getHighResolutionTicks();
    return juce::Time::highResolutionTicksToSeconds(
        juce::Time::getHighResolutionTicks() - startTime);
  };

  // ---- OSC Settings API ----
  auto oscTable = lua.create_table();

  // Get current settings as Lua table
  oscTable["getSettings"] = [this]() -> sol::table {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    auto& lua = pImpl->lua;
    auto result = lua.create_table();

    if (!pImpl->processor)
      return result;

    auto& oscServer = pImpl->processor->getOSCServer();
    auto settings = oscServer.getSettings();

    result["inputPort"] = settings.inputPort;
    result["queryPort"] = settings.queryPort;
    result["oscEnabled"] = settings.oscEnabled;
    result["oscQueryEnabled"] = settings.oscQueryEnabled;

    auto targets = lua.create_table();
    for (int i = 0; i < settings.outTargets.size(); ++i) {
      targets[i + 1] = settings.outTargets[i].toStdString();
    }
    result["outTargets"] = targets;

    return result;
  };

  // Apply new settings from Lua table
  oscTable["setSettings"] = [this](sol::table settingsTable) -> bool {
    if (!pImpl->processor)
      return false;

    OSCSettings settings;

    if (settingsTable["inputPort"].valid()) {
      settings.inputPort = settingsTable["inputPort"].get<int>();
    }
    if (settingsTable["queryPort"].valid()) {
      settings.queryPort = settingsTable["queryPort"].get<int>();
    }
    if (settingsTable["oscEnabled"].valid()) {
      settings.oscEnabled = settingsTable["oscEnabled"].get<bool>();
    }
    if (settingsTable["oscQueryEnabled"].valid()) {
      settings.oscQueryEnabled = settingsTable["oscQueryEnabled"].get<bool>();
    }
    if (settingsTable["outTargets"].valid()) {
      sol::table targetsTable = settingsTable["outTargets"];
      for (int i = 1; ; ++i) {
        auto val = targetsTable.get<sol::optional<std::string>>(i);
        if (!val.has_value()) break;
        settings.outTargets.add(juce::String(val.value()));
      }
    }

    // Save to file
    if (!OSCSettingsPersistence::save(settings)) {
      return false;
    }

    // Apply to running server
    pImpl->processor->getOSCServer().setSettings(settings);
    return true;
  };

  // Get server status string
  oscTable["getStatus"] = [this]() -> std::string {
    if (!pImpl->processor)
      return "no processor";

    auto& oscServer = pImpl->processor->getOSCServer();

    if (!oscServer.isRunning()) {
      return "stopped";
    }

    return "running";
  };

  // Add a target
  oscTable["addTarget"] = [this](const std::string& ipPort) -> bool {
    if (!pImpl->processor)
      return false;

    pImpl->processor->getOSCServer().addOutTarget(juce::String(ipPort));

    // Save updated settings
    auto settings = pImpl->processor->getOSCServer().getSettings();
    OSCSettingsPersistence::save(settings);

    return true;
  };

  // Remove a target
  oscTable["removeTarget"] = [this](const std::string& ipPort) -> bool {
    if (!pImpl->processor)
      return false;

    pImpl->processor->getOSCServer().removeOutTarget(juce::String(ipPort));

    // Save updated settings
    auto settings = pImpl->processor->getOSCServer().getSettings();
    OSCSettingsPersistence::save(settings);

    return true;
  };

  // ---- OSC Send API ----

  // Broadcast an OSC message to all configured targets
  oscTable["send"] = [this](const std::string& address,
                            sol::variadic_args args) -> bool {
    if (!pImpl->processor)
      return false;

    std::vector<juce::var> vars;
    for (auto arg : args) {
      if (arg.is<int>()) {
        vars.push_back(arg.as<int>());
      } else if (arg.is<float>()) {
        vars.push_back(arg.as<float>());
      } else if (arg.is<double>()) {
        vars.push_back(static_cast<float>(arg.as<double>()));
      } else if (arg.is<std::string>()) {
        vars.push_back(juce::String(arg.as<std::string>()));
      } else if (arg.is<bool>()) {
        vars.push_back(arg.as<bool>() ? 1 : 0);
      }
    }

    juce::String path(address.c_str());
    pImpl->processor->getOSCServer().broadcast(path, vars);
    // Keep OSCQuery VALUE/LISTEN in sync for userland/custom endpoints.
    if (!path.startsWith("/looper/") && path.startsWithChar('/')) {
      pImpl->processor->getOSCServer().setCustomValue(path, vars);
    }
    return true;
  };

  // Send an OSC message to a specific target
  oscTable["sendTo"] = [this](const std::string& ip, int port,
                              const std::string& address,
                              sol::variadic_args args) -> bool {
    if (!pImpl->processor)
      return false;

    std::vector<juce::var> vars;
    for (auto arg : args) {
      if (arg.is<int>()) {
        vars.push_back(arg.as<int>());
      } else if (arg.is<float>()) {
        vars.push_back(arg.as<float>());
      } else if (arg.is<double>()) {
        vars.push_back(static_cast<float>(arg.as<double>()));
      } else if (arg.is<std::string>()) {
        vars.push_back(juce::String(arg.as<std::string>()));
      } else if (arg.is<bool>()) {
        vars.push_back(arg.as<bool>() ? 1 : 0);
      }
    }

    juce::String path(address.c_str());
    auto packet = OSCPacketBuilder::build(path, vars);
    juce::DatagramSocket socket;
    socket.bindToPort(0);  // Any available port
    socket.write(juce::String(ip.c_str()), port, packet.data(),
                 static_cast<int>(packet.size()));

    if (!path.startsWith("/looper/") && path.startsWithChar('/')) {
      pImpl->processor->getOSCServer().setCustomValue(path, vars);
    }
    return true;
  };

  // Register a Lua callback for incoming OSC messages
  oscTable["onMessage"] = [this](const std::string& address,
                                  sol::function callback,
                                  sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

    if (!callback.valid()) {
      return false;
    }

    std::lock_guard<std::mutex> cbLock(pImpl->oscCallbacksMutex);
    Impl::OSCCallback cb;
    cb.func = callback;
    cb.persistent = persistent.value_or(false);
    cb.address = juce::String(address.c_str());
    pImpl->oscCallbacks[juce::String(address.c_str())].push_back(std::move(cb));

    return true;
  };

  // Remove all Lua callbacks for an OSC address
  oscTable["removeHandler"] = [this](const std::string& address) -> bool {
    std::lock_guard<std::mutex> lock(pImpl->oscCallbacksMutex);
    auto it = pImpl->oscCallbacks.find(juce::String(address.c_str()));
    if (it != pImpl->oscCallbacks.end()) {
      pImpl->oscCallbacks.erase(it);
      return true;
    }
    return false;
  };

  // Register a custom endpoint for OSCQuery discovery
  oscTable["registerEndpoint"] = [this](const std::string& path,
                                         sol::table options) -> bool {
    if (!pImpl->processor)
      return false;

    OSCEndpoint endpoint;
    endpoint.path = juce::String(path.c_str());
    endpoint.category = "custom";

    // Extract type (e.g., "f", "i", "s")
    if (options["type"].valid()) {
      endpoint.type = juce::String(options["type"].get<std::string>().c_str());
    } else {
      endpoint.type = "f";  // Default to float
    }

    // Extract range
    if (options["range"].valid()) {
      sol::table range = options["range"];
      auto minVal = range[1];
      auto maxVal = range[2];
      endpoint.rangeMin = minVal.valid() ? minVal.get<float>() : 0.0f;
      endpoint.rangeMax = maxVal.valid() ? maxVal.get<float>() : 1.0f;
    }

    // Extract access (0=none, 1=read, 2=write, 3=read-write)
    if (options["access"].valid()) {
      endpoint.access = options["access"].get<int>();
    } else {
      endpoint.access = 3;  // Default to read-write
    }

    // Extract description
    if (options["description"].valid()) {
      endpoint.description =
          juce::String(options["description"].get<std::string>().c_str());
    }

    // Register with the endpoint registry
    pImpl->processor->getEndpointRegistry().registerCustomEndpoint(endpoint);

    // Rebuild the OSCQuery tree so it appears in /info
    pImpl->processor->getOSCQueryServer().rebuildTree();

    return true;
  };

  // Remove a custom endpoint
  oscTable["removeEndpoint"] = [this](const std::string& path) -> bool {
    if (!pImpl->processor)
      return false;

    pImpl->processor->getEndpointRegistry().unregisterCustomEndpoint(
        juce::String(path.c_str()));
    pImpl->processor->getOSCQueryServer().rebuildTree();

    return true;
  };

  // Set the current value for a custom endpoint (for OSCQuery GET/LISTEN)
  oscTable["setValue"] = [this](const std::string& path,
                                 sol::object value) -> bool {
    if (!pImpl->processor)
      return false;

    std::vector<juce::var> args;
    if (value.is<float>()) {
      args.emplace_back(value.as<float>());
    } else if (value.is<int>()) {
      args.emplace_back(value.as<int>());
    } else if (value.is<double>()) {
      args.emplace_back((float)value.as<double>());
    } else if (value.is<std::string>()) {
      args.emplace_back(juce::String(value.as<std::string>().c_str()));
    } else if (value.is<bool>()) {
      args.emplace_back(value.as<bool>() ? 1 : 0);
    } else if (value.get_type() == sol::type::table) {
      sol::table tbl = value;
      for (int i = 1;; ++i) {
        sol::object item = tbl[i];
        if (!item.valid() || item.get_type() == sol::type::nil)
          break;
        if (item.is<int>()) args.emplace_back(item.as<int>());
        else if (item.is<float>()) args.emplace_back(item.as<float>());
        else if (item.is<double>()) args.emplace_back((float)item.as<double>());
        else if (item.is<std::string>()) args.emplace_back(juce::String(item.as<std::string>().c_str()));
        else if (item.is<bool>()) args.emplace_back(item.as<bool>() ? 1 : 0);
      }
    } else {
      return false;
    }

    pImpl->processor->getOSCServer().setCustomValue(juce::String(path.c_str()), args);
    return true;
  };

  // Get the current value for a custom endpoint
  oscTable["getValue"] = [this](const std::string& path) -> sol::object {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

    if (!pImpl->processor)
      return sol::nil;

    std::vector<juce::var> vals;
    if (!pImpl->processor->getOSCServer().getCustomValue(juce::String(path.c_str()), vals) || vals.empty()) {
      return sol::nil;
    }

    if (vals.size() == 1) {
      const auto& val = vals[0];
      if (val.isInt()) {
        return sol::make_object(pImpl->lua, (int)val);
      } else if (val.isDouble()) {
        return sol::make_object(pImpl->lua, (double)val);
      } else if (val.isString()) {
        return sol::make_object(pImpl->lua, val.toString().toStdString());
      } else if (val.isBool()) {
        return sol::make_object(pImpl->lua, (bool)val);
      }
      return sol::nil;
    }

    auto t = pImpl->lua.create_table();
    for (size_t i = 0; i < vals.size(); ++i) {
      const auto& val = vals[i];
      if (val.isInt()) t[i + 1] = (int)val;
      else if (val.isDouble()) t[i + 1] = (double)val;
      else if (val.isString()) t[i + 1] = val.toString().toStdString();
      else if (val.isBool()) t[i + 1] = (bool)val;
      else t[i + 1] = sol::nil;
    }
    return sol::make_object(pImpl->lua, t);
  };

  // Register a dynamic query handler for OSCQuery VALUE requests
  oscTable["onQuery"] = [this](const std::string& path,
                                sol::function callback,
                                sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) {
      return false;
    }

    std::lock_guard<std::mutex> lock2(pImpl->oscQueryHandlersMutex);
    Impl::OSCQueryHandler handler;
    handler.func = callback;
    handler.persistent = persistent.value_or(false);
    pImpl->oscQueryHandlers[juce::String(path.c_str())] = std::move(handler);
    return true;
  };

  lua["osc"] = oscTable;

  // ---- Looper Event Listeners ----
  // Create a looper global for event callbacks (extends existing looper access)
  auto looperTable = lua.create_table();

  // Register callback for tempo changes
  looperTable["onTempoChanged"] = [this](sol::function callback,
                                          sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) return false;

    std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
    Impl::EventListener listener;
    listener.func = callback;
    listener.persistent = persistent.value_or(false);
    pImpl->tempoChangedListeners.push_back(std::move(listener));
    return true;
  };

  // Register callback for commit events
  looperTable["onCommit"] = [this](sol::function callback,
                                    sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) return false;

    std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
    Impl::EventListener listener;
    listener.func = callback;
    listener.persistent = persistent.value_or(false);
    pImpl->commitListeners.push_back(std::move(listener));
    return true;
  };

  // Register callback for recording state changes
  looperTable["onRecordingChanged"] = [this](sol::function callback,
                                              sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) return false;

    std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
    Impl::EventListener listener;
    listener.func = callback;
    listener.persistent = persistent.value_or(false);
    pImpl->recordingChangedListeners.push_back(std::move(listener));
    return true;
  };

  // Register callback for layer state changes
  looperTable["onLayerStateChanged"] = [this](sol::function callback,
                                               sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) return false;

    std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
    Impl::EventListener listener;
    listener.func = callback;
    listener.persistent = persistent.value_or(false);
    pImpl->layerStateChangedListeners.push_back(std::move(listener));
    return true;
  };

  // Register callback for general state changes (30Hz polling)
  looperTable["onStateChanged"] = [this](sol::function callback,
                                          sol::optional<bool> persistent) -> bool {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    if (!callback.valid()) return false;

    std::lock_guard<std::mutex> lock2(pImpl->eventListenersMutex);
    Impl::EventListener listener;
    listener.func = callback;
    listener.persistent = persistent.value_or(false);
    pImpl->stateChangedListeners.push_back(std::move(listener));
    return true;
  };

  // Merge with existing looper table if it exists, otherwise create it
  lua["looper"] = looperTable;
}

// ============================================================================
// State snapshot
// ============================================================================

void LuaEngine::pushStateToLua() {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  auto &lua = pImpl->lua;
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
  params["/looper/tempo"] = tempo;
  params["/looper/targetbpm"] = targetBPM;
  params["/looper/samplesPerBar"] = samplesPerBar;
  params["/looper/sampleRate"] = sampleRate;
  params["/looper/captureSize"] = captureSize;
  params["/looper/volume"] = masterVolume;
  params["/looper/inputVolume"] = inputVolume;
  params["/looper/passthrough"] = passthroughEnabled ? 1 : 0;
  params["/looper/recording"] = isRecording ? 1 : 0;
  params["/looper/overdub"] = isOverdubEnabled ? 1 : 0;
  params["/looper/mode"] = recordModeString;
  params["/looper/layer"] = activeLayerIndex;
  params["/looper/forwardArmed"] = forwardCommitArmed ? 1 : 0;
  params["/looper/forwardBars"] = forwardCommitBars;

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
    const bool muted = layer.state == ScriptableLayerState::Muted;

    const std::string layerPrefix =
        "/looper/layer/" + std::to_string(i);
    params[layerPrefix + "/speed"] = layer.speed;
    params[layerPrefix + "/volume"] = layer.volume;
    params[layerPrefix + "/mute"] = muted ? 1 : 0;
    params[layerPrefix + "/reverse"] = layer.reversed ? 1 : 0;
    params[layerPrefix + "/length"] = layer.length;
    params[layerPrefix + "/position"] = normalizedPosition;
    params[layerPrefix + "/bars"] = bars;
    params[layerPrefix + "/state"] = layerStateString;

    auto voice = lua.create_table();
    voice["id"] = i;
    voice["path"] = layerPrefix;
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

  // Set up package.path so require() works from the script's directory
  auto dir = scriptFile.getParentDirectory().getFullPathName().toStdString();
  {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    pImpl->lua["package"]["path"] = dir + "/?.lua;" + dir + "/?/init.lua";
  }

  try {
    {
      // We reuse one Lua VM across UI switches for persistent bindings.
      // Clear lifecycle globals so old script handlers don't leak into new scripts.
      const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
      pImpl->lua["ui_init"] = sol::nil;
      pImpl->lua["ui_update"] = sol::nil;
      pImpl->lua["ui_resized"] = sol::nil;
    }

    sol::protected_function_result result;
    {
      const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
      result = pImpl->lua.script_file(scriptFile.getFullPathName().toStdString());
    }
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
  sol::function uiInit;
  {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    uiInit = pImpl->lua["ui_init"];
  }
  if (uiInit.valid()) {
    try {
      // Clear existing children
      pImpl->rootCanvas->clearChildren();

      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
        result = uiInit(pImpl->rootCanvas);
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

  sol::function fn;
  {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    fn = pImpl->lua["ui_resized"];
  }
  if (fn.valid()) {
    try {
      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
        result = fn(width, height);
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
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    fn = pImpl->lua["ui_update"];
  }
  if (fn.valid()) {
    try {
      sol::object stateObj;
      {
        const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
        stateObj = pImpl->lua["state"];
      }

      sol::protected_function_result result;
      {
        const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
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
  // UI scripts should not inherit an active DSP graph implicitly.
  // If a script wants graph processing, it can re-enable explicitly.
  if (pImpl->processor) {
    if (auto *lp = dynamic_cast<LooperProcessor *>(pImpl->processor)) {
      lp->setGraphProcessingEnabled(false);
    }
  }

  // Clear the current UI
  if (pImpl->rootCanvas) {
    pImpl->rootCanvas->clearChildren();
  }

  // Clear non-persistent callbacks before switching scripts
  clearNonPersistentCallbacks();

  if (pImpl->processor) {
    pImpl->processor->getEndpointRegistry().clearCustomEndpoints();
    pImpl->processor->getOSCServer().clearCustomValues();
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
  Impl::OSCQueryHandler handler;
  {
    std::lock_guard<std::mutex> mapLock(pImpl->oscQueryHandlersMutex);
    auto it = pImpl->oscQueryHandlers.find(path);
    if (it == pImpl->oscQueryHandlers.end() || !it->second.func.valid()) {
      return false;
    }
    handler = it->second;
  }

  const std::lock_guard<std::recursive_mutex> luaLock(pImpl->luaMutex);

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

  const std::lock_guard<std::recursive_mutex> luaLock(pImpl->luaMutex);
  auto& lua = pImpl->lua;

  for (const auto& message : messages) {
    std::vector<Impl::OSCCallback> callbacksToInvoke;
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

  const std::lock_guard<std::recursive_mutex> luaLock(pImpl->luaMutex);
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
    auto changedTable = pImpl->lua.create_table();
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
                       [](const Impl::OSCCallback& cb) { return !cb.persistent; }),
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
  auto clearNonPersistent = [](std::vector<Impl::EventListener>& listeners) {
    listeners.erase(
        std::remove_if(listeners.begin(), listeners.end(),
                       [](const Impl::EventListener& l) { return !l.persistent; }),
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

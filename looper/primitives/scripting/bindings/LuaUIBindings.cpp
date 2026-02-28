#include "LuaUIBindings.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include <juce_graphics/juce_graphics.h>
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include <tuple>

using namespace juce::gl;

// ============================================================================
// Graphics context helper
// ============================================================================

namespace {
    // Current graphics context - only valid during paint callback
    thread_local juce::Graphics* currentGraphics = nullptr;
}

// ============================================================================
// Binding Registration
// ============================================================================

void LuaUIBindings::registerBindings(LuaCoreEngine& engine, Canvas* rootCanvas) {
    auto& lua = engine.getLuaState();
    
    registerCanvasBindings(engine, rootCanvas);
    registerGraphicsBindings(lua);
    registerOpenGLBindings(engine);
    registerConstants(lua);
}

void LuaUIBindings::registerCanvasBindings(LuaCoreEngine& engine, Canvas* rootCanvas) {
    auto& lua = engine.getLuaState();
    
    // ---- CanvasStyle ----
    lua.new_usertype<CanvasStyle>(
        "CanvasStyle",
        sol::constructors<CanvasStyle()>(),
        "background",
        sol::property(
            [](const CanvasStyle& s) { return (uint32_t)s.background.getARGB(); },
            [](CanvasStyle& s, uint32_t c) { s.background = juce::Colour(c); }),
        "border",
        sol::property(
            [](const CanvasStyle& s) { return (uint32_t)s.border.getARGB(); },
            [](CanvasStyle& s, uint32_t c) { s.border = juce::Colour(c); }),
        "borderWidth", &CanvasStyle::borderWidth,
        "cornerRadius", &CanvasStyle::cornerRadius,
        "opacity", &CanvasStyle::opacity,
        "padding", &CanvasStyle::padding
    );

    // ---- Canvas ----
    lua.new_usertype<Canvas>(
        "Canvas",
        sol::no_constructor,

        "addChild",
        [](Canvas& parent, const std::string& name) -> Canvas* {
            return parent.addChild(juce::String(name));
        },

        "clearChildren", &Canvas::clearChildren,
        "getNumChildren", &Canvas::getNumChildren,
        "getChild", &Canvas::getChild,

        "setBounds",
        [](Canvas& c, int x, int y, int w, int h) { c.setBounds(x, y, w, h); },

        "getBounds",
        [](Canvas& c) {
            auto b = c.getBounds();
            return std::make_tuple(b.getX(), b.getY(), b.getWidth(), b.getHeight());
        },

        "getWidth", [](Canvas& c) { return c.getWidth(); },
        "getHeight", [](Canvas& c) { return c.getHeight(); },

        "setStyle",
        [](Canvas& c, sol::table t) {
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

        "getStyle", [](Canvas& c) -> CanvasStyle& { return c.style; },

        "setInterceptsMouse",
        [](Canvas& c, bool clicks, bool children) {
            c.setInterceptsMouseClicks(clicks, children);
        },

        "isMouseOver", [](Canvas& c) { return c.isMouseOverOrDragging(); },

        "repaint", [](Canvas& c) { c.repaint(); },

        "setOnClick",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onClick = [fn, &engine]() mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onClick error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onClick = nullptr;
                });
            }
        },

        "setOnMouseDown",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseDown = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(e.x, e.y);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDown error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onMouseDown = nullptr;
                });
            }
        },

        "setOnMouseDrag",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseDrag = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(e.x, e.y, e.getDistanceFromDragStartX(),
                                   e.getDistanceFromDragStartY());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDrag error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onMouseDrag = nullptr;
                });
            }
        },

        "setOnMouseUp",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseUp = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(e.x, e.y);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseUp error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onMouseUp = nullptr;
                });
            }
        },

        "setOnDoubleClick",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onDoubleClick = [fn, &engine]() mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onDoubleClick error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onDoubleClick = nullptr;
                });
            }
        },

        "setOnMouseWheel",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseWheel = [fn, &engine](const juce::MouseEvent& e,
                                      const juce::MouseWheelDetails& wheel) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(e.x, e.y, wheel.deltaY);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseWheel error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onMouseWheel = nullptr;
                });
            }
        },

        "setWantsKeyboardFocus",
        [](Canvas& c, bool wantsFocus) { c.setWantsKeyboardFocus(wantsFocus); },

        "grabKeyboardFocus",
        [](Canvas& c) { c.grabKeyboardFocus(); },

        "hasKeyboardFocus",
        [](Canvas& c) { return c.hasKeyboardFocus(true); },

        "setOnKeyPress",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onKeyPress = [fn, &engine](const juce::KeyPress& key) mutable -> bool {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    const auto mods = key.getModifiers();
                    auto result = fn(
                        key.getKeyCode(),
                        static_cast<int>(key.getTextCharacter()),
                        mods.isShiftDown(),
                        mods.isCtrlDown() || mods.isCommandDown(),
                        mods.isAltDown());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onKeyPress error: %s\n", err.what());
                        return false;
                    }
                    if (result.get_type() == sol::type::boolean) {
                        return result.get<bool>();
                    }
                    return true;
                };
                c.setWantsKeyboardFocus(true);
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onKeyPress = nullptr;
                });
            }
        },

        "setOnDraw",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onDraw = [fn, &engine](Canvas& self, juce::Graphics& g) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    currentGraphics = &g;
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onDraw error: %s\n", err.what());
                    }
                    currentGraphics = nullptr;
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onDraw = nullptr;
                });
            }
        },

        "setOpenGLEnabled",
        [](Canvas& c, bool enabled) { c.setOpenGLEnabled(enabled); },

        "isOpenGLEnabled",
        [](Canvas& c) { return c.isOpenGLEnabled(); },

        "setOnGLRender",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLRender = [fn, &engine](Canvas& self) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLRender error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onGLRender = nullptr;
                });
            }
        },

        "setOnGLContextCreated",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLContextCreated = [fn, &engine](Canvas& self) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLContextCreated error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onGLContextCreated = nullptr;
                });
            }
        },

        "setOnGLContextClosing",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLContextClosing = [fn, &engine](Canvas& self) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLContextClosing error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                juce::MessageManager::callAsync([&c]() {
                    c.onGLContextClosing = nullptr;
                });
            }
        }
    );

    // Root canvas accessor
    lua["root"] = rootCanvas;
}

void LuaUIBindings::registerGraphicsBindings(sol::state& lua) {
    auto gfx = lua.create_named_table("gfx");

    gfx["setColour"] = [](uint32_t argb) {
        if (currentGraphics)
            currentGraphics->setColour(juce::Colour(argb));
    };

    gfx["setFont"] = sol::overload(
        [](float size) {
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(size));
        },
        [](const std::string& name, float size) {
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(name, size, juce::Font::plain));
        },
        [](const std::string& name, float size, int flags) {
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(name, size, flags));
        }
    );

    gfx["drawText"] = [](const std::string& text, int x, int y, int w, int h,
                         sol::optional<int> justification) {
        if (currentGraphics) {
            int just = justification.value_or(36);
            currentGraphics->drawText(juce::String(text),
                                      juce::Rectangle<int>(x, y, w, h),
                                      juce::Justification(just));
        }
    };

    gfx["fillRect"] = [](float x, float y, float w, float h) {
        if (currentGraphics)
            currentGraphics->fillRect(x, y, w, h);
    };

    gfx["fillRoundedRect"] = [](float x, float y, float w, float h, float radius) {
        if (currentGraphics)
            currentGraphics->fillRoundedRectangle(x, y, w, h, radius);
    };

    gfx["drawRoundedRect"] = [](float x, float y, float w, float h,
                                float radius, float lineThickness) {
        if (currentGraphics)
            currentGraphics->drawRoundedRectangle(x, y, w, h, radius, lineThickness);
    };

    gfx["drawRect"] = sol::overload(
        [](int x, int y, int w, int h) {
            if (currentGraphics)
                currentGraphics->drawRect(x, y, w, h);
        },
        [](int x, int y, int w, int h, int lineThickness) {
            if (currentGraphics)
                currentGraphics->drawRect(x, y, w, h, lineThickness);
        }
    );

    gfx["drawVerticalLine"] = [](int x, float top, float bottom) {
        if (currentGraphics)
            currentGraphics->drawVerticalLine(x, top, bottom);
    };

    gfx["drawHorizontalLine"] = [](int y, float left, float right) {
        if (currentGraphics)
            currentGraphics->drawHorizontalLine(y, left, right);
    };

    gfx["fillAll"] = []() {
        if (currentGraphics)
            currentGraphics->fillAll();
    };

    gfx["drawLine"] = [](float x1, float y1, float x2, float y2) {
        if (currentGraphics)
            currentGraphics->drawLine(x1, y1, x2, y2);
    };
}

void LuaUIBindings::registerOpenGLBindings(LuaCoreEngine& engine) {
    auto& lua = engine.getLuaState();
    auto gl = lua.create_named_table("gl");

    // Immediate mode and basic functions
    gl["clearColor"] = [](float r, float g, float b, float a) {
        glClearColor(r, g, b, a);
    };

    gl["clear"] = [](sol::optional<int> mask) {
        int m = mask.value_or(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glClear(m);
    };

    gl["viewport"] = [](int x, int y, int w, int h) { glViewport(x, y, w, h); };

    gl["enable"] = [](int cap) { glEnable(cap); };
    gl["disable"] = [](int cap) { glDisable(cap); };

    gl["blendFunc"] = [](int sfactor, int dfactor) {
        glBlendFunc(sfactor, dfactor);
    };

    gl["depthFunc"] = [](int func) { glDepthFunc(func); };
    gl["depthMask"] = [](bool flag) { glDepthMask(flag ? GL_TRUE : GL_FALSE); };

    gl["matrixMode"] = [](int mode) { glMatrixMode(mode); };
    gl["loadIdentity"] = []() { glLoadIdentity(); };
    gl["pushMatrix"] = []() { glPushMatrix(); };
    gl["popMatrix"] = []() { glPopMatrix(); };
    gl["translate"] = [](float x, float y, float z) { glTranslatef(x, y, z); };
    gl["rotate"] = [](float angle, float x, float y, float z) {
        glRotatef(angle, x, y, z);
    };
    gl["scale"] = [](float x, float y, float z) { glScalef(x, y, z); };

    gl["begin"] = [](int mode) { glBegin(mode); };
    gl["end"] = []() { glEnd(); };
    gl["vertex2"] = [](float x, float y) { glVertex2f(x, y); };
    gl["vertex3"] = [](float x, float y, float z) { glVertex3f(x, y, z); };
    gl["color3"] = [](float r, float g, float b) { glColor3f(r, g, b); };
    gl["color4"] = [](float r, float g, float b, float a) { glColor4f(r, g, b, a); };
    gl["texCoord2"] = [](float s, float t) { glTexCoord2f(s, t); };
    gl["normal3"] = [](float x, float y, float z) { glNormal3f(x, y, z); };

    // Shader functions
    gl["createShader"] = [](int shaderType) -> unsigned int {
        return static_cast<unsigned int>(glCreateShader((GLenum)shaderType));
    };

    gl["deleteShader"] = [](unsigned int shaderId) {
        glDeleteShader(static_cast<GLuint>(shaderId));
    };

    gl["shaderSource"] = [](unsigned int shaderId, const std::string& source) {
        const char* src = source.c_str();
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
        if (length <= 1) return {};
        std::string log(static_cast<size_t>(length), '\0');
        GLsizei written = 0;
        glGetShaderInfoLog(static_cast<GLuint>(shaderId), length, &written, log.data());
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
        if (length <= 1) return {};
        std::string log(static_cast<size_t>(length), '\0');
        GLsizei written = 0;
        glGetProgramInfoLog(static_cast<GLuint>(programId), length, &written, log.data());
        if (written > 0 && static_cast<size_t>(written) < log.size())
            log.resize(static_cast<size_t>(written));
        return log;
    };

    gl["getAttribLocation"] = [](unsigned int programId, const std::string& name) -> int {
        return glGetAttribLocation(static_cast<GLuint>(programId), name.c_str());
    };

    gl["getUniformLocation"] = [](unsigned int programId, const std::string& name) -> int {
        return glGetUniformLocation(static_cast<GLuint>(programId), name.c_str());
    };

    gl["uniform1f"] = [](int location, float v0) { glUniform1f(location, v0); };
    gl["uniform2f"] = [](int location, float v0, float v1) { glUniform2f(location, v0, v1); };
    gl["uniform3f"] = [](int location, float v0, float v1, float v2) { glUniform3f(location, v0, v1, v2); };
    gl["uniform4f"] = [](int location, float v0, float v1, float v2, float v3) {
        glUniform4f(location, v0, v1, v2, v3);
    };
    gl["uniform1i"] = [](int location, int v0) { glUniform1i(location, v0); };

    gl["uniformMatrix4"] = [](int location, sol::table values, sol::optional<bool> transpose) {
        const bool tx = transpose.value_or(false);
        const size_t count = values.size();
        if (count < 16) return;
        std::array<float, 16> matrix{};
        for (size_t i = 0; i < 16; ++i) {
            auto value = values.get<sol::optional<float>>(i + 1);
            matrix[i] = value.value_or(0.0f);
        }
        glUniformMatrix4fv(location, 1, tx ? GL_TRUE : GL_FALSE, matrix.data());
    };

    // Buffer functions
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

    // VAO functions
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
                                   bool normalized, int strideBytes, int offsetBytes) {
        glVertexAttribPointer(static_cast<GLuint>(index), size,
                              static_cast<GLenum>(type),
                              normalized ? GL_TRUE : GL_FALSE,
                              static_cast<GLsizei>(strideBytes),
                              reinterpret_cast<const void*>(static_cast<uintptr_t>(offsetBytes)));
    };

    // Draw functions
    gl["drawArrays"] = [](int mode, int first, int count) {
        glDrawArrays(static_cast<GLenum>(mode), first, count);
    };

    gl["drawElements"] = [](int mode, int count, int indexType, int indexOffsetBytes) {
        glDrawElements(static_cast<GLenum>(mode), count,
                       static_cast<GLenum>(indexType),
                       reinterpret_cast<const void*>(static_cast<uintptr_t>(indexOffsetBytes)));
    };

    // Texture functions
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
        const uint8_t* ptr = nullptr;
        if (pixelData.has_value()) {
            auto table = pixelData.value();
            const size_t count = table.size();
            data.reserve(count);
            for (size_t i = 1; i <= count; ++i) {
                auto value = table.get<sol::optional<int>>(i);
                data.push_back(static_cast<uint8_t>(std::clamp(value.value_or(0), 0, 255)));
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
            data.push_back(static_cast<uint8_t>(std::clamp(value.value_or(0), 0, 255)));
        }
        glTexSubImage2D(static_cast<GLenum>(target), level, xoffset, yoffset, width,
                        height, GL_RGBA, GL_UNSIGNED_BYTE,
                        data.empty() ? nullptr : data.data());
    };

    gl["generateMipmap"] = [](int target) {
        glGenerateMipmap(static_cast<GLenum>(target));
    };

    // Framebuffer functions
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

    gl["framebufferTexture2D"] = [](int target, int attachment, int texTarget,
                                     unsigned int textureId, int level) {
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

    // Renderbuffer functions
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

    gl["renderbufferStorage"] = [](int target, int internalFormat, int width, int height) {
        glRenderbufferStorage(static_cast<GLenum>(target),
                              static_cast<GLenum>(internalFormat), width, height);
    };

    gl["framebufferRenderbuffer"] = [](int target, int attachment, int renderbufferTarget,
                                        unsigned int renderbufferId) {
        glFramebufferRenderbuffer(static_cast<GLenum>(target),
                                  static_cast<GLenum>(attachment),
                                  static_cast<GLenum>(renderbufferTarget),
                                  static_cast<GLuint>(renderbufferId));
    };

    // Additional functions
    gl["blitFramebuffer"] = [](int srcX0, int srcY0, int srcX1, int srcY1,
                                int dstX0, int dstY0, int dstX1, int dstY1,
                                int mask, int filter) {
        glBlitFramebuffer(srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1,
                          static_cast<GLbitfield>(mask), static_cast<GLenum>(filter));
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
}

void LuaUIBindings::registerConstants(sol::state& lua) {
    // Justification constants
    lua["Justify"] = lua.create_table_with(
        "left", 1, "right", 2, "horizontallyCentred", 4, "top", 8, "bottom", 16,
        "verticallyCentred", 32, "centred", 36, "centredLeft", 33, "centredRight",
        34, "centredTop", 12, "centredBottom", 20, "topLeft", 9, "topRight", 10,
        "bottomLeft", 17, "bottomRight", 18
    );

    // Font style constants
    lua["FontStyle"] = lua.create_table_with(
        "plain", 0, "bold", 1, "italic", 2, "boldItalic", 3
    );

    // OpenGL constants
    lua["GL"] = lua.create_table_with(
        // Buffer bits
        "COLOR_BUFFER_BIT", GL_COLOR_BUFFER_BIT,
        "DEPTH_BUFFER_BIT", GL_DEPTH_BUFFER_BIT,
        "STENCIL_BUFFER_BIT", GL_STENCIL_BUFFER_BIT,
        // Primitives
        "POINTS", GL_POINTS,
        "LINES", GL_LINES,
        "LINE_STRIP", GL_LINE_STRIP,
        "LINE_LOOP", GL_LINE_LOOP,
        "TRIANGLES", GL_TRIANGLES,
        "TRIANGLE_STRIP", GL_TRIANGLE_STRIP,
        "TRIANGLE_FAN", GL_TRIANGLE_FAN,
        "QUADS", GL_QUADS,
        "QUAD_STRIP", GL_QUAD_STRIP,
        "POLYGON", GL_POLYGON,
        // Capabilities
        "BLEND", GL_BLEND,
        "DEPTH_TEST", GL_DEPTH_TEST,
        "CULL_FACE", GL_CULL_FACE,
        "LIGHTING", GL_LIGHTING,
        "LIGHT0", GL_LIGHT0,
        "LIGHT1", GL_LIGHT1,
        "TEXTURE_2D", GL_TEXTURE_2D,
        "SCISSOR_TEST", GL_SCISSOR_TEST,
        // Blend factors
        "ZERO", GL_ZERO,
        "ONE", GL_ONE,
        "SRC_COLOR", GL_SRC_COLOR,
        "ONE_MINUS_SRC_COLOR", GL_ONE_MINUS_SRC_COLOR,
        "SRC_ALPHA", GL_SRC_ALPHA,
        "ONE_MINUS_SRC_ALPHA", GL_ONE_MINUS_SRC_ALPHA,
        "DST_ALPHA", GL_DST_ALPHA,
        "ONE_MINUS_DST_ALPHA", GL_ONE_MINUS_DST_ALPHA,
        "FUNC_ADD", GL_FUNC_ADD,
        // Depth functions
        "NEVER", GL_NEVER,
        "LESS", GL_LESS,
        "EQUAL", GL_EQUAL,
        "LEQUAL", GL_LEQUAL,
        "GREATER", GL_GREATER,
        "NOTEQUAL", GL_NOTEQUAL,
        "GEQUAL", GL_GEQUAL,
        "ALWAYS", GL_ALWAYS,
        // Cull modes
        "FRONT", GL_FRONT,
        "BACK", GL_BACK,
        "FRONT_AND_BACK", GL_FRONT_AND_BACK,
        // Matrix modes
        "MODELVIEW", GL_MODELVIEW,
        "PROJECTION", GL_PROJECTION,
        "TEXTURE", GL_TEXTURE,
        // Shader/program pipeline
        "VERTEX_SHADER", GL_VERTEX_SHADER,
        "FRAGMENT_SHADER", GL_FRAGMENT_SHADER,
        "COMPILE_STATUS", GL_COMPILE_STATUS,
        "LINK_STATUS", GL_LINK_STATUS,
        "INFO_LOG_LENGTH", GL_INFO_LOG_LENGTH,
        // Buffer API
        "ARRAY_BUFFER", GL_ARRAY_BUFFER,
        "ELEMENT_ARRAY_BUFFER", GL_ELEMENT_ARRAY_BUFFER,
        "STATIC_DRAW", GL_STATIC_DRAW,
        "DYNAMIC_DRAW", GL_DYNAMIC_DRAW,
        "STREAM_DRAW", GL_STREAM_DRAW,
        "READ_FRAMEBUFFER", GL_READ_FRAMEBUFFER,
        "DRAW_FRAMEBUFFER", GL_DRAW_FRAMEBUFFER,
        // Framebuffer / renderbuffer
        "FRAMEBUFFER", GL_FRAMEBUFFER,
        "RENDERBUFFER", GL_RENDERBUFFER,
        "FRAMEBUFFER_COMPLETE", GL_FRAMEBUFFER_COMPLETE,
        "COLOR_ATTACHMENT0", GL_COLOR_ATTACHMENT0,
        "DEPTH_ATTACHMENT", GL_DEPTH_ATTACHMENT,
        "DEPTH_STENCIL_ATTACHMENT", GL_DEPTH_STENCIL_ATTACHMENT,
        "DEPTH24_STENCIL8", GL_DEPTH24_STENCIL8,
        // Texture API
        "TEXTURE0", GL_TEXTURE0,
        "TEXTURE1", GL_TEXTURE1,
        "TEXTURE2", GL_TEXTURE2,
        "TEXTURE_MIN_FILTER", GL_TEXTURE_MIN_FILTER,
        "TEXTURE_MAG_FILTER", GL_TEXTURE_MAG_FILTER,
        "TEXTURE_WRAP_S", GL_TEXTURE_WRAP_S,
        "TEXTURE_WRAP_T", GL_TEXTURE_WRAP_T,
        "CLAMP_TO_EDGE", GL_CLAMP_TO_EDGE,
        "REPEAT", GL_REPEAT,
        "LINEAR", GL_LINEAR,
        "NEAREST", GL_NEAREST,
        "RGBA", GL_RGBA,
        "RGBA8", GL_RGBA8,
        // Types
        "FLOAT", GL_FLOAT,
        "UNSIGNED_BYTE", GL_UNSIGNED_BYTE,
        "UNSIGNED_SHORT", GL_UNSIGNED_SHORT,
        "UNSIGNED_INT", GL_UNSIGNED_INT,
        // Error values
        "NO_ERROR", GL_NO_ERROR,
        "INVALID_ENUM", GL_INVALID_ENUM,
        "INVALID_VALUE", GL_INVALID_VALUE,
        "INVALID_OPERATION", GL_INVALID_OPERATION,
        "OUT_OF_MEMORY", GL_OUT_OF_MEMORY
    );
}

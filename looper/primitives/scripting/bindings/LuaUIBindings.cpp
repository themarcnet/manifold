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
    
    registerCanvasBindings(lua, rootCanvas);
    registerGraphicsBindings(lua);
    registerOpenGLBindings(lua);
    registerConstants(lua);
}

void LuaUIBindings::registerCanvasBindings(sol::state& lua, Canvas* rootCanvas) {
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
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onClick = [fn]() mutable {
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onClick error: %s\n", err.what());
                    }
                };
            } else {
                c.onClick = nullptr;
            }
        },

        "setOnMouseDown",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseDown = [fn](const juce::MouseEvent& e) mutable {
                    auto result = fn(e.x, e.y);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDown error: %s\n", err.what());
                    }
                };
            } else {
                c.onMouseDown = nullptr;
            }
        },

        "setOnMouseDrag",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseDrag = [fn](const juce::MouseEvent& e) mutable {
                    auto result = fn(e.x, e.y, e.getDistanceFromDragStartX(),
                                   e.getDistanceFromDragStartY());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDrag error: %s\n", err.what());
                    }
                };
            } else {
                c.onMouseDrag = nullptr;
            }
        },

        "setOnMouseUp",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseUp = [fn](const juce::MouseEvent& e) mutable {
                    auto result = fn(e.x, e.y);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseUp error: %s\n", err.what());
                    }
                };
            } else {
                c.onMouseUp = nullptr;
            }
        },

        "setOnDoubleClick",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onDoubleClick = [fn]() mutable {
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onDoubleClick error: %s\n", err.what());
                    }
                };
            } else {
                c.onDoubleClick = nullptr;
            }
        },

        "setOnMouseWheel",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onMouseWheel = [fn](const juce::MouseEvent& e,
                                      const juce::MouseWheelDetails& wheel) mutable {
                    auto result = fn(e.x, e.y, wheel.deltaY);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseWheel error: %s\n", err.what());
                    }
                };
            } else {
                c.onMouseWheel = nullptr;
            }
        },

        "setWantsKeyboardFocus",
        [](Canvas& c, bool wantsFocus) { c.setWantsKeyboardFocus(wantsFocus); },

        "grabKeyboardFocus",
        [](Canvas& c) { c.grabKeyboardFocus(); },

        "hasKeyboardFocus",
        [](Canvas& c) { return c.hasKeyboardFocus(true); },

        "setOnKeyPress",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onKeyPress = [fn](const juce::KeyPress& key) mutable -> bool {
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
                c.onKeyPress = nullptr;
            }
        },

        "setOnDraw",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onDraw = [fn](Canvas& self, juce::Graphics& g) mutable {
                    currentGraphics = &g;
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onDraw error: %s\n", err.what());
                    }
                    currentGraphics = nullptr;
                };
            } else {
                c.onDraw = nullptr;
            }
        },

        "setOpenGLEnabled",
        [](Canvas& c, bool enabled) { c.setOpenGLEnabled(enabled); },

        "isOpenGLEnabled",
        [](Canvas& c) { return c.isOpenGLEnabled(); },

        "setOnGLRender",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLRender = [fn](Canvas& self) mutable {
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLRender error: %s\n", err.what());
                    }
                };
            } else {
                c.onGLRender = nullptr;
            }
        },

        "setOnGLContextCreated",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLContextCreated = [fn](Canvas& self) mutable {
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLContextCreated error: %s\n", err.what());
                    }
                };
            } else {
                c.onGLContextCreated = nullptr;
            }
        },

        "setOnGLContextClosing",
        [](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                c.onGLContextClosing = [fn](Canvas& self) mutable {
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onGLContextClosing error: %s\n", err.what());
                    }
                };
            } else {
                c.onGLContextClosing = nullptr;
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
            int just = justification.value_or(36);  // centred = 36
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

void LuaUIBindings::registerOpenGLBindings(sol::state& lua) {
    auto gl = lua.create_named_table("gl");

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

    gl["createShader"] = [](int shaderType) -> unsigned int {
        return static_cast<unsigned int>(glCreateShader((GLenum)shaderType));
    };

    gl["shaderSource"] = [](unsigned int shaderId, const std::string& source) {
        const char* src = source.c_str();
        GLint length = static_cast<GLint>(source.size());
        glShaderSource(static_cast<GLuint>(shaderId), 1, &src, &length);
    };

    gl["compileShader"] = [](unsigned int shaderId) {
        glCompileShader(static_cast<GLuint>(shaderId));
    };

    gl["createProgram"] = []() -> unsigned int {
        return static_cast<unsigned int>(glCreateProgram());
    };

    gl["attachShader"] = [](unsigned int programId, unsigned int shaderId) {
        glAttachShader(static_cast<GLuint>(programId), static_cast<GLuint>(shaderId));
    };

    gl["linkProgram"] = [](unsigned int programId) {
        glLinkProgram(static_cast<GLuint>(programId));
    };

    gl["useProgram"] = [](unsigned int programId) {
        glUseProgram(static_cast<GLuint>(programId));
    };

    gl["uniform1f"] = [](int location, float v0) { glUniform1f(location, v0); };
    gl["uniform1i"] = [](int location, int v0) { glUniform1i(location, v0); };
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

    // OpenGL constants (subset)
    lua["GL"] = lua.create_table_with(
        "COLOR_BUFFER_BIT", GL_COLOR_BUFFER_BIT,
        "DEPTH_BUFFER_BIT", GL_DEPTH_BUFFER_BIT,
        "TRIANGLES", GL_TRIANGLES,
        "TRIANGLE_STRIP", GL_TRIANGLE_STRIP,
        "VERTEX_SHADER", GL_VERTEX_SHADER,
        "FRAGMENT_SHADER", GL_FRAGMENT_SHADER,
        "BLEND", GL_BLEND,
        "SRC_ALPHA", GL_SRC_ALPHA,
        "ONE_MINUS_SRC_ALPHA", GL_ONE_MINUS_SRC_ALPHA,
        "TEXTURE_2D", GL_TEXTURE_2D,
        "ARRAY_BUFFER", GL_ARRAY_BUFFER,
        "STATIC_DRAW", GL_STATIC_DRAW
    );
}

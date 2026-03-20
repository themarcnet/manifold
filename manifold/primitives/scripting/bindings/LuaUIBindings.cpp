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
#include <utility>
#include <vector>

using namespace juce::gl;

// ============================================================================
// Graphics context helper
// ============================================================================

namespace {
    // Current graphics context - only valid during paint callback
    thread_local juce::Graphics* currentGraphics = nullptr;

    struct RecordedDrawState {
        uint32_t color = 0xffffffffu;
        float fontSize = 13.0f;
    };

    struct RuntimeDrawRecorder {
        juce::Array<juce::var> commands;
        RecordedDrawState state;
        std::vector<RecordedDrawState> stateStack;
        RuntimeNode* node = nullptr;
    };

    thread_local RuntimeDrawRecorder* currentRuntimeDrawRecorder = nullptr;
    thread_local RuntimeNode* currentRuntimeDrawNode = nullptr;
    thread_local bool currentRuntimeDrawMutatedDisplayList = false;

    // Callback for display list broadcasting (set by BehaviorCoreEditor)
    std::function<void(const std::string&)> displayListCallback;

    std::unique_ptr<juce::DynamicObject> makeDisplayListCommand(const juce::String& cmdName) {
        auto cmd = std::make_unique<juce::DynamicObject>();
        cmd->setProperty("cmd", cmdName);
        return cmd;
    }

    void pushRecordedCommand(std::unique_ptr<juce::DynamicObject> cmd) {
        if (currentRuntimeDrawRecorder == nullptr || cmd == nullptr) {
            return;
        }
        currentRuntimeDrawRecorder->commands.add(juce::var(cmd.release()));
    }

    void applyRecordedDrawState(juce::DynamicObject& cmd) {
        if (currentRuntimeDrawRecorder == nullptr) {
            return;
        }
        cmd.setProperty("color", juce::var(static_cast<juce::int64>(currentRuntimeDrawRecorder->state.color)));
        cmd.setProperty("fontSize", currentRuntimeDrawRecorder->state.fontSize);
    }

    std::pair<std::string, std::string> justificationToAlign(int justification) {
        juce::Justification just(justification);

        std::string align = "left";
        if (just.testFlags(juce::Justification::horizontallyCentred)) {
            align = "center";
        } else if (just.testFlags(juce::Justification::right)) {
            align = "right";
        }

        std::string valign = "top";
        if (just.testFlags(juce::Justification::verticallyCentred)) {
            valign = "middle";
        } else if (just.testFlags(juce::Justification::bottom)) {
            valign = "bottom";
        }

        return {align, valign};
    }

    void clearRuntimeCallbackSlot(Canvas& c, const std::function<void(RuntimeNode::CallbackSlots&)>& clearFn) {
        if (auto* node = c.getRuntimeNode()) {
            clearFn(node->getCallbacks());
            node->markPropsDirty();
        }
    }

    void setRuntimeCallbackSlot(Canvas& c, const std::function<void(RuntimeNode::CallbackSlots&)>& setFn) {
        if (auto* node = c.getRuntimeNode()) {
            setFn(node->getCallbacks());
            node->markPropsDirty();
        }
    }

    template <typename Fn>
    void callAsyncIfCanvasAlive(Canvas& c, Fn&& fn) {
        juce::Component::SafePointer<Canvas> safeCanvas(&c);
        juce::MessageManager::callAsync(
            [safeCanvas, fn = std::forward<Fn>(fn)]() mutable {
                if (safeCanvas != nullptr) {
                    fn(*safeCanvas);
                }
            });
    }

    juce::var luaObjectToVar(const sol::object& object);

    juce::var luaTableToVar(const sol::table& table) {
        bool arrayLike = true;
        int maxIndex = 0;
        for (const auto& pair : table) {
            const sol::object& key = pair.first;
            if (!key.is<int>()) {
                arrayLike = false;
                break;
            }
            const int index = key.as<int>();
            if (index < 1) {
                arrayLike = false;
                break;
            }
            maxIndex = std::max(maxIndex, index);
        }

        if (arrayLike) {
            juce::Array<juce::var> arr;
            for (int i = 1; i <= maxIndex; ++i) {
                sol::object value = table[i];
                if (!value.valid() || value == sol::lua_nil) {
                    arrayLike = false;
                    break;
                }
                arr.add(luaObjectToVar(value));
            }
            if (arrayLike) {
                return juce::var(arr);
            }
        }

        auto obj = std::make_unique<juce::DynamicObject>();
        for (const auto& pair : table) {
            const sol::object& key = pair.first;
            const sol::object& value = pair.second;
            juce::String propName;
            if (key.is<std::string>()) {
                propName = key.as<std::string>();
            } else if (key.is<int>()) {
                propName = juce::String(key.as<int>());
            } else {
                continue;
            }
            obj->setProperty(propName, luaObjectToVar(value));
        }
        return juce::var(obj.release());
    }

    juce::var luaObjectToVar(const sol::object& object) {
        if (!object.valid() || object == sol::lua_nil) {
            return {};
        }
        if (object.is<bool>()) {
            return juce::var(object.as<bool>());
        }
        if (object.is<int>()) {
            return juce::var(object.as<int>());
        }
        if (object.is<double>()) {
            return juce::var(object.as<double>());
        }
        if (object.is<float>()) {
            return juce::var(static_cast<double>(object.as<float>()));
        }
        if (object.is<std::string>()) {
            return juce::var(juce::String(object.as<std::string>()));
        }
        if (object.is<sol::table>()) {
            return luaTableToVar(object.as<sol::table>());
        }
        return {};
    }

    sol::object varToLuaObject(sol::state& lua, const juce::var& value) {
        if (value.isVoid() || value.isUndefined()) {
            return sol::make_object(lua, sol::nil);
        }
        if (value.isBool()) {
            return sol::make_object(lua, static_cast<bool>(value));
        }
        if (value.isInt()) {
            return sol::make_object(lua, static_cast<int>(value));
        }
        if (value.isInt64()) {
            return sol::make_object(lua, value.toString().getDoubleValue());
        }
        if (value.isDouble()) {
            return sol::make_object(lua, static_cast<double>(value));
        }
        if (value.isString()) {
            return sol::make_object(lua, value.toString().toStdString());
        }
        if (auto* arr = value.getArray()) {
            sol::table out(lua, sol::create);
            for (int i = 0; i < arr->size(); ++i) {
                out[i + 1] = varToLuaObject(lua, arr->getReference(i));
            }
            return sol::make_object(lua, out);
        }
        if (auto* obj = value.getDynamicObject()) {
            sol::table out(lua, sol::create);
            for (const auto& property : obj->getProperties()) {
                out[property.name.toString().toStdString()] = varToLuaObject(lua, property.value);
            }
            return sol::make_object(lua, out);
        }
        return sol::make_object(lua, sol::nil);
    }
}

// ============================================================================
// Binding Registration
// ============================================================================

void LuaUIBindings::setDisplayListCallback(std::function<void(const std::string&)> callback) {
    displayListCallback = std::move(callback);
}

bool LuaUIBindings::invokeRuntimeNodeDrawForRetained(LuaCoreEngine& engine, RuntimeNode& node) {
    auto& fn = node.getCallbacks().onDraw;
    if (!fn.valid()) {
        return false;
    }

    if (currentRuntimeDrawNode == &node) {
        return false;
    }

    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());

    RuntimeDrawRecorder recorder;
    recorder.node = &node;

    auto* previousRecorder = currentRuntimeDrawRecorder;
    auto* previousNode = currentRuntimeDrawNode;
    const bool previousMutationFlag = currentRuntimeDrawMutatedDisplayList;
    auto* previousGraphics = currentGraphics;

    currentRuntimeDrawRecorder = &recorder;
    currentRuntimeDrawNode = &node;
    currentRuntimeDrawMutatedDisplayList = false;
    currentGraphics = nullptr;

    auto result = fn(std::ref(node));

    currentGraphics = previousGraphics;
    const bool mutatedDisplayList = currentRuntimeDrawMutatedDisplayList;
    currentRuntimeDrawMutatedDisplayList = previousMutationFlag;
    currentRuntimeDrawNode = previousNode;
    currentRuntimeDrawRecorder = previousRecorder;

    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "LuaUI: RuntimeNode invokeDrawForRetained error: %s\n", err.what());
        return false;
    }

    if (recorder.commands.size() > 0) {
        node.setDisplayList(juce::var(recorder.commands));
    } else if (!mutatedDisplayList) {
        node.clearDisplayList();
    }

    return recorder.commands.size() > 0 || mutatedDisplayList;
}

void LuaUIBindings::noteRuntimeNodeDisplayListMutation(RuntimeNode& node) {
    if (currentRuntimeDrawNode == &node) {
        currentRuntimeDrawMutatedDisplayList = true;
    }
}

void LuaUIBindings::registerBindings(LuaCoreEngine& engine, Canvas* rootCanvas) {
    auto& lua = engine.getLuaState();
    
    registerCanvasBindings(engine, rootCanvas);
    registerGraphicsBindings(lua);
    registerOpenGLBindings(engine);
    registerConstants(lua);
    
    // Display list broadcast function for WebSocket UI
    lua["sendDisplayList"] = [](const std::string& json) {
        if (displayListCallback) {
            displayListCallback(json);
        }
    };
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
        "adoptChild", &Canvas::adoptChild,

        "setBounds",
        [](Canvas& c, int x, int y, int w, int h) { c.setBounds(x, y, w, h); },

        "getBounds",
        [](Canvas& c) {
            auto b = c.getBounds();
            return std::make_tuple(b.getX(), b.getY(), b.getWidth(), b.getHeight());
        },

        "getName", [](Canvas& c) { return c.getName().toStdString(); },
        "setNodeId", [](Canvas& c, const std::string& id) { c.setNodeId(id); },
        "getNodeId", [](Canvas& c) { return c.getNodeId(); },
        "setWidgetType", [](Canvas& c, const std::string& type) { c.setWidgetType(type); },
        "getWidgetType", [](Canvas& c) { return c.getWidgetType(); },
        "getRuntimeNode", [](Canvas& c) { return c.getRuntimeNode(); },
        "getInputCapabilities",
        [&lua](Canvas& c) {
            const auto caps = c.getInputCapabilities();
            sol::table out(lua, sol::create);
            out["pointer"] = caps.pointer;
            out["wheel"] = caps.wheel;
            out["keyboard"] = caps.keyboard;
            out["focusable"] = caps.focusable;
            out["interceptsChildren"] = caps.interceptsChildren;
            return out;
        },

        "getScreenBounds",
        [](Canvas& c) {
            auto b = c.getScreenBounds();
            return std::make_tuple(b.getX(), b.getY(), b.getWidth(), b.getHeight());
        },

        "getWidth", [](Canvas& c) { return c.getWidth(); },
        "getHeight", [](Canvas& c) { return c.getHeight(); },

        "toFront", [](Canvas& c, bool shouldGrabFocus) { c.toFront(shouldGrabFocus); },
        "toBack", [](Canvas& c) { c.toBack(); },

        // Transform for zoom/pan in editor
        "setTransform", [](Canvas& c, float scaleX, float scaleY, float translateX, float translateY) {
            c.setTransform(juce::AffineTransform::scale(scaleX, scaleY)
                          .translated(translateX, translateY));
        },
        "clearTransform", [](Canvas& c) {
            c.setTransform(juce::AffineTransform());
        },



        // User data storage for editor metadata and widget properties
        "setUserData",
        [](Canvas& c, const std::string& key, sol::object value) {
            c.setUserData(key, value);
        },

        "getUserData",
        [](Canvas& c, const std::string& key) -> sol::object {
            return c.getUserData(key);
        },

        "hasUserData", &Canvas::hasUserData,

        "getUserDataKeys", &Canvas::getUserDataKeys,

        "clearUserData", &Canvas::clearUserData,

        "clearAllUserData", &Canvas::clearAllUserData,

        "setDisplayList",
        [](Canvas& c, sol::object value) {
            c.setDisplayList(luaObjectToVar(value));
        },

        "getDisplayList",
        [&lua](Canvas& c) -> sol::object {
            return varToLuaObject(lua, c.getDisplayList());
        },

        "clearDisplayList", &Canvas::clearDisplayList,

        "setCustomRenderPayload",
        [](Canvas& c, sol::object value) {
            c.setCustomRenderPayload(luaObjectToVar(value));
        },

        "getCustomRenderPayload",
        [&lua](Canvas& c) -> sol::object {
            return varToLuaObject(lua, c.getCustomRenderPayload());
        },

        "clearCustomRenderPayload", &Canvas::clearCustomRenderPayload,
        "getStructureVersion", &Canvas::getStructureVersion,
        "getPropsVersion", &Canvas::getPropsVersion,
        "getRenderVersion", &Canvas::getRenderVersion,

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
            c.syncInputCapabilities();
        },

        "getInterceptsMouse",
        [](Canvas& c) {
            bool clicks = false;
            bool children = false;
            c.getInterceptsMouseClicks(clicks, children);
            return std::make_tuple(clicks, children);
        },

        "setVisible",
        [](Canvas& c, bool visible) {
            c.setVisible(visible);
            c.markPropsDirty();
        },

        "isVisible",
        [](Canvas& c) {
            return c.isVisible();
        },

        "isMouseOver", [](Canvas& c) { return c.isMouseOverOrDragging(); },

        "repaint", [](Canvas& c) { c.repaint(); },

        "setOnClick",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onClick = fn;
                });
                c.onClick = [fn, &engine]() mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onClick error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onClick = sol::lua_nil;
                    });
                    canvas.onClick = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setOnMouseDown",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onMouseDown = fn;
                });
                c.onMouseDown = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    const auto mods = e.mods;
                    auto result = fn(e.x, e.y,
                                     mods.isShiftDown(),
                                     mods.isCtrlDown() || mods.isCommandDown(),
                                     mods.isAltDown());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDown error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onMouseDown = sol::lua_nil;
                    });
                    canvas.onMouseDown = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setOnMouseDrag",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onMouseDrag = fn;
                });
                c.onMouseDrag = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    const auto mods = e.mods;
                    auto result = fn(e.x, e.y,
                                     e.getDistanceFromDragStartX(),
                                     e.getDistanceFromDragStartY(),
                                     mods.isShiftDown(),
                                     mods.isCtrlDown() || mods.isCommandDown(),
                                     mods.isAltDown());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseDrag error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onMouseDrag = sol::lua_nil;
                    });
                    canvas.onMouseDrag = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setOnMouseUp",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onMouseUp = fn;
                });
                c.onMouseUp = [fn, &engine](const juce::MouseEvent& e) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    const auto mods = e.mods;
                    auto result = fn(e.x, e.y,
                                     mods.isShiftDown(),
                                     mods.isCtrlDown() || mods.isCommandDown(),
                                     mods.isAltDown());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseUp error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onMouseUp = sol::lua_nil;
                    });
                    canvas.onMouseUp = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setOnDoubleClick",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onDoubleClick = fn;
                });
                c.onDoubleClick = [fn, &engine]() mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    auto result = fn();
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onDoubleClick error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onDoubleClick = sol::lua_nil;
                    });
                    canvas.onDoubleClick = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setOnMouseWheel",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onMouseWheel = fn;
                });
                c.onMouseWheel = [fn, &engine](const juce::MouseEvent& e,
                                      const juce::MouseWheelDetails& wheel) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    const auto mods = e.mods;
                    auto result = fn(e.x, e.y, wheel.deltaY,
                                     mods.isShiftDown(),
                                     mods.isCtrlDown() || mods.isCommandDown(),
                                     mods.isAltDown());
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: onMouseWheel error: %s\n", err.what());
                    }
                };
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onMouseWheel = sol::lua_nil;
                    });
                    canvas.onMouseWheel = nullptr;
                    canvas.syncInputCapabilities();
                });
            }
        },

        "setWantsKeyboardFocus",
        [](Canvas& c, bool wantsFocus) {
            c.setWantsKeyboardFocus(wantsFocus);
            c.syncInputCapabilities();
        },

        "grabKeyboardFocus",
        [](Canvas& c) {
            c.grabKeyboardFocus();
            if (auto* node = c.getRuntimeNode()) {
                node->setFocused(true);
            }
        },

        "hasKeyboardFocus",
        [](Canvas& c) { return c.hasKeyboardFocus(true); },

        "setOnKeyPress",
        [&engine](Canvas& c, sol::function fn) {
            if (fn.valid()) {
                setRuntimeCallbackSlot(c, [fn](RuntimeNode::CallbackSlots& slots) mutable {
                    slots.onKeyPress = fn;
                });
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
                c.syncInputCapabilities();
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    clearRuntimeCallbackSlot(canvas, [](RuntimeNode::CallbackSlots& slots) {
                        slots.onKeyPress = sol::lua_nil;
                    });
                    canvas.onKeyPress = nullptr;
                    canvas.syncInputCapabilities();
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
                // Store a wrapper that invokes the Lua draw function without a Graphics context.
                // gfx.* calls become no-ops (currentGraphics is nullptr), but
                // node:setDisplayList() still works for retained display list refresh.
                c.invokeDrawForRetainedFn = [fn, &engine](Canvas& self) mutable {
                    const std::lock_guard<std::recursive_mutex> lock(engine.getMutex());
                    // currentGraphics is already nullptr — gfx.* calls will be no-ops
                    auto result = fn(std::ref(self));
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "LuaUI: invokeDrawForRetained error: %s\n", err.what());
                    }
                };
            } else {
                // Defer clearing to avoid destroying the callback while it's running
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    canvas.onDraw = nullptr;
                    canvas.invokeDrawForRetainedFn = nullptr;
                });
            }
        },

        // Invoke the onDraw callback without a Graphics context (for retained display list refresh).
        // gfx.* calls become no-ops, but node:setDisplayList() still works.
        "invokeDrawForRetained",
        [](Canvas& c) {
            if (c.invokeDrawForRetainedFn) {
                c.invokeDrawForRetainedFn(c);
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
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    canvas.onGLRender = nullptr;
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
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    canvas.onGLContextCreated = nullptr;
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
                callAsyncIfCanvasAlive(c, [](Canvas& canvas) {
                    canvas.onGLContextClosing = nullptr;
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
        if (currentRuntimeDrawRecorder != nullptr) {
            currentRuntimeDrawRecorder->state.color = argb;
        }
        if (currentGraphics)
            currentGraphics->setColour(juce::Colour(argb));
    };

    gfx["setFont"] = sol::overload(
        [](float size) {
            if (currentRuntimeDrawRecorder != nullptr) {
                currentRuntimeDrawRecorder->state.fontSize = size;
            }
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(size));
        },
        [](const std::string& name, float size) {
            if (currentRuntimeDrawRecorder != nullptr) {
                currentRuntimeDrawRecorder->state.fontSize = size;
            }
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(name, size, juce::Font::plain));
        },
        [](const std::string& name, float size, int flags) {
            if (currentRuntimeDrawRecorder != nullptr) {
                currentRuntimeDrawRecorder->state.fontSize = size;
            }
            if (currentGraphics)
                currentGraphics->setFont(juce::Font(name, size, flags));
        }
    );

    gfx["save"] = []() {
        if (currentRuntimeDrawRecorder != nullptr) {
            currentRuntimeDrawRecorder->stateStack.push_back(currentRuntimeDrawRecorder->state);
            pushRecordedCommand(makeDisplayListCommand("save"));
        }
        if (currentGraphics)
            currentGraphics->saveState();
    };

    gfx["restore"] = []() {
        if (currentRuntimeDrawRecorder != nullptr) {
            if (!currentRuntimeDrawRecorder->stateStack.empty()) {
                currentRuntimeDrawRecorder->state = currentRuntimeDrawRecorder->stateStack.back();
                currentRuntimeDrawRecorder->stateStack.pop_back();
            }
            pushRecordedCommand(makeDisplayListCommand("restore"));
        }
        if (currentGraphics)
            currentGraphics->restoreState();
    };

    gfx["clipRect"] = [](int x, int y, int w, int h) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("clipRect");
            cmd->setProperty("x", x);
            cmd->setProperty("y", y);
            cmd->setProperty("w", w);
            cmd->setProperty("h", h);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->reduceClipRegion(juce::Rectangle<int>(x, y, w, h));
    };

    gfx["addTransform"] = [](float a, float b, float c, float d, float tx, float ty) {
        if (currentGraphics)
            currentGraphics->addTransform(juce::AffineTransform(a, b, tx, c, d, ty));
    };

    gfx["drawText"] = [](const std::string& text, int x, int y, int w, int h,
                         sol::optional<int> justification) {
        const int just = justification.value_or(36);
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("drawText");
            cmd->setProperty("x", x);
            cmd->setProperty("y", y);
            cmd->setProperty("w", w);
            cmd->setProperty("h", h);
            cmd->setProperty("text", juce::String(text));
            const auto [align, valign] = justificationToAlign(just);
            cmd->setProperty("align", juce::String(align));
            cmd->setProperty("valign", juce::String(valign));
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics) {
            currentGraphics->drawText(juce::String(text),
                                      juce::Rectangle<int>(x, y, w, h),
                                      juce::Justification(just));
        }
    };

    gfx["fillRect"] = [](float x, float y, float w, float h) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("fillRect");
            cmd->setProperty("x", x);
            cmd->setProperty("y", y);
            cmd->setProperty("w", w);
            cmd->setProperty("h", h);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->fillRect(x, y, w, h);
    };

    gfx["fillRoundedRect"] = [](float x, float y, float w, float h, float radius) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("fillRoundedRect");
            cmd->setProperty("x", x);
            cmd->setProperty("y", y);
            cmd->setProperty("w", w);
            cmd->setProperty("h", h);
            cmd->setProperty("radius", radius);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->fillRoundedRectangle(x, y, w, h, radius);
    };

    gfx["drawRoundedRect"] = [](float x, float y, float w, float h,
                                float radius, float lineThickness) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("drawRoundedRect");
            cmd->setProperty("x", x);
            cmd->setProperty("y", y);
            cmd->setProperty("w", w);
            cmd->setProperty("h", h);
            cmd->setProperty("radius", radius);
            cmd->setProperty("thickness", lineThickness);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->drawRoundedRectangle(x, y, w, h, radius, lineThickness);
    };

    gfx["drawRect"] = sol::overload(
        [](int x, int y, int w, int h) {
            if (currentRuntimeDrawRecorder != nullptr) {
                auto cmd = makeDisplayListCommand("drawRect");
                cmd->setProperty("x", x);
                cmd->setProperty("y", y);
                cmd->setProperty("w", w);
                cmd->setProperty("h", h);
                cmd->setProperty("thickness", 1);
                applyRecordedDrawState(*cmd);
                pushRecordedCommand(std::move(cmd));
            }
            if (currentGraphics)
                currentGraphics->drawRect(x, y, w, h);
        },
        [](int x, int y, int w, int h, int lineThickness) {
            if (currentRuntimeDrawRecorder != nullptr) {
                auto cmd = makeDisplayListCommand("drawRect");
                cmd->setProperty("x", x);
                cmd->setProperty("y", y);
                cmd->setProperty("w", w);
                cmd->setProperty("h", h);
                cmd->setProperty("thickness", lineThickness);
                applyRecordedDrawState(*cmd);
                pushRecordedCommand(std::move(cmd));
            }
            if (currentGraphics)
                currentGraphics->drawRect(x, y, w, h, lineThickness);
        }
    );

    gfx["drawVerticalLine"] = [](int x, float top, float bottom) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("drawLine");
            cmd->setProperty("x1", x);
            cmd->setProperty("y1", top);
            cmd->setProperty("x2", x);
            cmd->setProperty("y2", bottom);
            cmd->setProperty("thickness", 1.0);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->drawVerticalLine(x, top, bottom);
    };

    gfx["drawHorizontalLine"] = [](int y, float left, float right) {
        if (currentRuntimeDrawRecorder != nullptr) {
            auto cmd = makeDisplayListCommand("drawLine");
            cmd->setProperty("x1", left);
            cmd->setProperty("y1", y);
            cmd->setProperty("x2", right);
            cmd->setProperty("y2", y);
            cmd->setProperty("thickness", 1.0);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->drawHorizontalLine(y, left, right);
    };

    gfx["fillAll"] = []() {
        if (currentRuntimeDrawRecorder != nullptr && currentRuntimeDrawRecorder->node != nullptr) {
            const auto& bounds = currentRuntimeDrawRecorder->node->getBounds();
            auto cmd = makeDisplayListCommand("fillRect");
            cmd->setProperty("x", 0);
            cmd->setProperty("y", 0);
            cmd->setProperty("w", bounds.w);
            cmd->setProperty("h", bounds.h);
            applyRecordedDrawState(*cmd);
            pushRecordedCommand(std::move(cmd));
        }
        if (currentGraphics)
            currentGraphics->fillAll();
    };

    gfx["drawLine"] = sol::overload(
        [](float x1, float y1, float x2, float y2) {
            if (currentRuntimeDrawRecorder != nullptr) {
                auto cmd = makeDisplayListCommand("drawLine");
                cmd->setProperty("x1", x1);
                cmd->setProperty("y1", y1);
                cmd->setProperty("x2", x2);
                cmd->setProperty("y2", y2);
                cmd->setProperty("thickness", 1.0);
                applyRecordedDrawState(*cmd);
                pushRecordedCommand(std::move(cmd));
            }
            if (currentGraphics)
                currentGraphics->drawLine(x1, y1, x2, y2);
        },
        [](float x1, float y1, float x2, float y2, float lineThickness) {
            if (currentRuntimeDrawRecorder != nullptr) {
                auto cmd = makeDisplayListCommand("drawLine");
                cmd->setProperty("x1", x1);
                cmd->setProperty("y1", y1);
                cmd->setProperty("x2", x2);
                cmd->setProperty("y2", y2);
                cmd->setProperty("thickness", lineThickness);
                applyRecordedDrawState(*cmd);
                pushRecordedCommand(std::move(cmd));
            }
            if (currentGraphics)
                currentGraphics->drawLine(x1, y1, x2, y2, lineThickness);
        }
    );
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

#ifndef __ANDROID__
    // Desktop OpenGL matrix functions (not available in OpenGL ES)
    gl["matrixMode"] = [](int mode) { glMatrixMode(mode); };
    gl["loadIdentity"] = []() { glLoadIdentity(); };
    gl["pushMatrix"] = []() { glPushMatrix(); };
    gl["popMatrix"] = []() { glPopMatrix(); };
    gl["translate"] = [](float x, float y, float z) { glTranslatef(x, y, z); };
    gl["rotate"] = [](float angle, float x, float y, float z) {
        glRotatef(angle, x, y, z);
    };
    gl["scale"] = [](float x, float y, float z) { glScalef(x, y, z); };

    // Desktop OpenGL immediate mode (not available in OpenGL ES)
    gl["begin"] = [](int mode) { glBegin(mode); };
    gl["end"] = []() { glEnd(); };
    gl["vertex2"] = [](float x, float y) { glVertex2f(x, y); };
    gl["vertex3"] = [](float x, float y, float z) { glVertex3f(x, y, z); };
    gl["color3"] = [](float r, float g, float b) { glColor3f(r, g, b); };
    gl["color4"] = [](float r, float g, float b, float a) { glColor4f(r, g, b, a); };
    gl["texCoord2"] = [](float s, float t) { glTexCoord2f(s, t); };
    gl["normal3"] = [](float x, float y, float z) { glNormal3f(x, y, z); };
#endif

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

#ifndef __ANDROID__
    gl["clearDepth"] = [](double depth) { glClearDepth(depth); };
#endif

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
#ifndef __ANDROID__
        "QUAD_STRIP", GL_QUAD_STRIP,
        "POLYGON", GL_POLYGON,
#endif
        // Capabilities
        "BLEND", GL_BLEND,
        "DEPTH_TEST", GL_DEPTH_TEST,
        "CULL_FACE", GL_CULL_FACE,
#ifndef __ANDROID__
        "LIGHTING", GL_LIGHTING,
        "LIGHT0", GL_LIGHT0,
        "LIGHT1", GL_LIGHT1,
        "MODELVIEW", GL_MODELVIEW,
        "PROJECTION", GL_PROJECTION,
#endif
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
#ifndef __ANDROID__
        "MODELVIEW", GL_MODELVIEW,
        "PROJECTION", GL_PROJECTION,
#endif
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

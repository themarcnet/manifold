#pragma once

#include "../core/LuaCoreEngine.h"
#include "../../ui/Canvas.h"

/**
 * LuaUIBindings: Registers Canvas, Graphics, and OpenGL bindings.
 * 
 * Separated from LuaCoreEngine so that non-UI plugins don't drag in
 * JUCE GUI dependencies.
 */
class LuaUIBindings {
public:
    /**
     * Register all UI-related bindings to the Lua engine.
     * Must be called after LuaCoreEngine::initialize() and before loadScript().
     * 
     * @param engine The Lua engine to register bindings to
     * @param rootCanvas The root Canvas that Lua will populate
     */
    static void registerBindings(LuaCoreEngine& engine, Canvas* rootCanvas);

private:
    // Individual binding groups - engine provides mutex access
    static void registerCanvasBindings(LuaCoreEngine& engine, Canvas* rootCanvas);
    static void registerGraphicsBindings(sol::state& lua);
    static void registerOpenGLBindings(LuaCoreEngine& engine);
    static void registerConstants(sol::state& lua);
};

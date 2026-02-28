#pragma once

#include "../core/LuaCoreEngine.h"

// Forward declarations
class ScriptableProcessor;

/**
 * LuaControlBindings: Registers commands, OSC, events, and parameter access.
 * 
 * Separated from LuaCoreEngine so that headless/control-only plugins
 * can use it without UI dependencies.
 */
class LuaControlBindings {
public:
    /**
     * Register all control-related bindings to the Lua engine.
     * Must be called after LuaCoreEngine::initialize() and before loadScript().
     * 
     * @param engine The Lua engine to register bindings to
     * @param processor The ScriptableProcessor for command posting and state access
     */
    static void registerBindings(LuaCoreEngine& engine, ScriptableProcessor* processor);

private:
    static void registerCommandBindings(sol::state& lua, ScriptableProcessor* processor);
    static void registerOSCBindings(sol::state& lua, ScriptableProcessor* processor);
    static void registerEventBindings(sol::state& lua, ScriptableProcessor* processor);
    static void registerWaveformBindings(sol::state& lua, ScriptableProcessor* processor);
    static void registerUtilityBindings(sol::state& lua, ScriptableProcessor* processor);
};

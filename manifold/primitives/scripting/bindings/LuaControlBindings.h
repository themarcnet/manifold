#pragma once

#include "../core/LuaCoreEngine.h"
#include "../ILuaControlState.h"

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
     * @param state The ILuaControlState for command posting and state access
     */
    static void registerBindings(LuaCoreEngine& engine, ILuaControlState& state);

private:
    static void registerCommandBindings(sol::state& lua, ILuaControlState& state);
    static void registerOSCBindings(sol::state& lua, ILuaControlState& state);
    static void registerEventBindings(sol::state& lua, ILuaControlState& state);
    static void registerWaveformBindings(sol::state& lua, ILuaControlState& state);
    static void registerDspBindings(sol::state& lua, ILuaControlState& state);
    static void registerGraphBindings(sol::state& lua, ILuaControlState& state);
    static void registerLinkBindings(sol::state& lua, ILuaControlState& state);
    static void registerUtilityBindings(sol::state& lua, ILuaControlState& state);
};

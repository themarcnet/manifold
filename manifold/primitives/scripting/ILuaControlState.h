#pragma once

#include <map>
#include <mutex>
#include <set>
#include <string>
#include <unordered_set>
#include <vector>

#include <juce_core/juce_core.h>
#include <sol/sol.hpp>

// Forward declarations
class ScriptableProcessor;

// ============================================================================
// ILuaControlState - Interface for control-related Lua bindings state
//
// This interface abstracts the plugin-specific state needed by control
// bindings (OSC, events, DSP slots, etc.) from the LuaEngine implementation.
// It enables LuaControlBindings to work with any implementation, facilitating
// testing and reuse across different plugin types.
// ============================================================================

class ILuaControlState {
public:
    virtual ~ILuaControlState() = default;

    // ============================================================================
    // Processor access
    // ============================================================================
    virtual ScriptableProcessor* getProcessor() = 0;
    virtual const ScriptableProcessor* getProcessor() const = 0;

    // ============================================================================
    // Script management
    // ============================================================================
    virtual juce::File getCurrentScriptFile() const = 0;
    virtual void setPendingSwitchPath(const std::string& path) = 0;

    // ============================================================================
    // DSP Slot management
    // ============================================================================
    virtual std::unordered_set<std::string>& getManagedDspSlots() = 0;
    virtual const std::unordered_set<std::string>& getManagedDspSlots() const = 0;

    virtual std::unordered_set<std::string>& getPersistentDspSlots() = 0;
    virtual const std::unordered_set<std::string>& getPersistentDspSlots() const = 0;

    // ============================================================================
    // OSC endpoint/value tracking (UI-registered)
    // ============================================================================
    virtual std::unordered_set<std::string>& getUiRegisteredOscEndpoints() = 0;
    virtual const std::unordered_set<std::string>& getUiRegisteredOscEndpoints() const = 0;

    virtual std::unordered_set<std::string>& getUiRegisteredOscValues() = 0;
    virtual const std::unordered_set<std::string>& getUiRegisteredOscValues() const = 0;

    // ============================================================================
    // OSC Callbacks
    // ============================================================================
    struct OSCCallback {
        sol::function func;
        bool persistent = false;
        juce::String address;
    };

    virtual std::map<juce::String, std::vector<OSCCallback>>& getOscCallbacks() = 0;
    virtual std::mutex& getOscCallbacksMutex() = 0;

    // ============================================================================
    // OSC Query Handlers
    // ============================================================================
    struct OSCQueryHandler {
        sol::function func;
        bool persistent = false;
    };

    virtual std::map<juce::String, OSCQueryHandler>& getOscQueryHandlers() = 0;
    virtual std::mutex& getOscQueryHandlersMutex() = 0;

    // ============================================================================
    // Event Listeners
    // ============================================================================
    struct EventListener {
        sol::function func;
        bool persistent = false;
    };

    virtual std::vector<EventListener>& getTempoChangedListeners() = 0;
    virtual std::vector<EventListener>& getCommitListeners() = 0;
    virtual std::vector<EventListener>& getRecordingChangedListeners() = 0;
    virtual std::vector<EventListener>& getLayerStateChangedListeners() = 0;
    virtual std::vector<EventListener>& getStateChangedListeners() = 0;
    virtual std::mutex& getEventListenersMutex() = 0;

    // ============================================================================
    // Lua state access (for creating tables/objects from bindings)
    // ============================================================================
    virtual void withLuaState(std::function<void(sol::state&)> callback) = 0;
    virtual void withLuaState(std::function<void(const sol::state&)> callback) const = 0;

    // ============================================================================
    // File chooser (async, calls callback with selected path or empty string)
    // ============================================================================
    virtual void showDirectoryChooser(const std::string& title, 
                                       const std::string& initialPath,
                                       sol::function callback) = 0;
};

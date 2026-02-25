#pragma once

#include <array>
#include <atomic>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <juce_core/juce_core.h>

#include "ControlServer.h"

class LooperProcessor;

struct OSCSettings {
    int inputPort = 8000;
    int queryPort = 8001;
    bool oscEnabled = false;
    bool oscQueryEnabled = false;
    juce::StringArray outTargets;
};

struct OSCMessage {
    juce::String address;
    std::vector<juce::var> args;
    juce::String sourceIP;
    int sourcePort = 0;
};

// ============================================================================
// Cached snapshot of AtomicState for diff-based broadcasting.
// Only includes values that make sense to broadcast over OSC.
// ============================================================================

struct OSCStateSnapshot {
    float tempo = 120.0f;
    bool isRecording = false;
    bool overdubEnabled = false;
    int recordMode = 0;
    int activeLayer = 0;
    float masterVolume = 1.0f;

    struct LayerSnapshot {
        int state = 0;
        float speed = 1.0f;
        float volume = 1.0f;
        bool reversed = false;
        float position = 0.0f;  // normalized 0-1
        float bars = 0.0f;
    };

    static const int MAX_LAYERS = 4;
    LayerSnapshot layers[MAX_LAYERS];
};

class OSCServer {
public:
    OSCServer();
    ~OSCServer();

    void start(LooperProcessor* processor);
    void stop();

    void setSettings(const OSCSettings& settings);
    OSCSettings getSettings() const;

    // Target management - use "host:port" format (e.g. "192.168.1.100:9000")
    void addOutTarget(const juce::String& ipPort);
    void removeOutTarget(const juce::String& ipPort);
    void clearOutTargets();
    juce::StringArray getOutTargets() const;

    // Broadcast an OSC message to all configured targets
    void broadcast(const juce::String& address, const std::vector<juce::var>& args);

    // Custom endpoint values used by Lua + OSCQuery (thread-safe)
    void setCustomValue(const juce::String& path, const std::vector<juce::var>& args);
    bool getCustomValue(const juce::String& path, std::vector<juce::var>& outArgs) const;
    void clearCustomValues();

    bool isRunning() const { return running.load(); }

    // Set broadcast rate in Hz (default 30). 0 = disabled.
    void setBroadcastRate(int hz);

    // Callback type for Lua message handlers
    // Return true if the message was handled (consumed)
    using LuaCallback = std::function<bool(const juce::String& address, const std::vector<juce::var>& args)>;
    using LuaQueryCallback = std::function<bool(const juce::String& path, std::vector<juce::var>& outArgs)>;

    // Set a callback to check for Lua handlers before built-in dispatch
    void setLuaCallback(LuaCallback callback);

    // Set/query callback for dynamic OSCQuery VALUE requests
    void setLuaQueryCallback(LuaQueryCallback callback);
    bool invokeLuaQueryCallback(const juce::String& path, std::vector<juce::var>& outArgs) const;

private:
    void receiveLoop();
    void broadcastLoop();
    void parseAndDispatch(const char* data, int size, const juce::String& sourceIP, int sourcePort);
    bool parseOSCMessage(const char* data, int size, OSCMessage& out);
    void dispatchMessage(const OSCMessage& msg);
    juce::var parseArgument(char tag, const char* data, int dataLen, int& offset);

    void sendToTargets(const juce::String& address, const std::vector<juce::var>& args);

    // State-diff broadcaster: reads AtomicState, compares to snapshot, broadcasts changes
    void broadcastStateChanges();

    LooperProcessor* owner = nullptr;
    OSCSettings settings;
    mutable std::mutex settingsMutex;

    juce::DatagramSocket* socket = nullptr;
    std::atomic<bool> running{false};
    std::thread receiveThread;
    std::thread broadcastThread;

    juce::StringArray configuredTargets;  // explicitly added targets (not ephemeral)
    mutable std::mutex targetsMutex;

    std::atomic<int> messagesReceived{0};
    std::atomic<int> messagesSent{0};
    std::atomic<int> broadcastRateHz{30};
    std::atomic<int> unknownPathMessages{0};
    std::atomic<int> invalidMessages{0};
    std::atomic<int> queueFullDrops{0};

    // Cached state for diff-based broadcasting
    OSCStateSnapshot cachedState;

    // Last seen custom endpoint values (e.g. /experimental/xy -> [0.1, 0.8])
    mutable std::mutex customValuesMutex;
    std::map<juce::String, std::vector<juce::var>> customValues;

    // Lua callback for custom message handling
    mutable std::mutex luaCallbackMutex;
    LuaCallback luaCallback;

    // Lua callback for dynamic OSCQuery value resolution
    mutable std::mutex luaQueryCallbackMutex;
    LuaQueryCallback luaQueryCallback;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(OSCServer)
};

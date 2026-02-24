#pragma once

#include <array>
#include <atomic>
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

class OSCServer {
public:
    OSCServer();
    ~OSCServer();

    void start(LooperProcessor* processor);
    void stop();

    void setSettings(const OSCSettings& settings);
    OSCSettings getSettings() const;

    // Target management
    void addOutTarget(const juce::String& ipPort);
    void removeOutTarget(const juce::String& ipPort);
    void clearOutTargets();
    juce::StringArray getOutTargets() const;

    // Broadcast an OSC message to all paired/configured targets
    void broadcast(const juce::String& address, const std::vector<juce::var>& args);

    bool isRunning() const { return running.load(); }

private:
    void receiveLoop();
    void parseAndDispatch(const char* data, int size, const juce::String& sourceIP, int sourcePort);
    bool parseOSCMessage(const char* data, int size, OSCMessage& out);
    void dispatchMessage(const OSCMessage& msg);
    juce::var parseArgument(char tag, const char* data, int dataLen, int& offset);

    void sendToTargets(const juce::String& address, const std::vector<juce::var>& args);

    LooperProcessor* owner = nullptr;
    OSCSettings settings;
    mutable std::mutex settingsMutex;

    juce::DatagramSocket* socket = nullptr;
    std::atomic<bool> running{false};
    std::thread receiveThread;

    juce::StringArray pairedTargets;
    mutable std::mutex targetsMutex;

    std::atomic<int> messagesReceived{0};
    std::atomic<int> messagesSent{0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(OSCServer)
};

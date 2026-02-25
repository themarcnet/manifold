#include "OSCServer.h"
#include "OSCPacketBuilder.h"
#include "CommandParser.h"
#include "../../engine/LooperProcessor.h"
#include <cstring>
#include <cmath>

// ============================================================================
// Byte-order helpers - OSC uses big-endian (network byte order)
// (Kept for parseArgument which needs beToHost32; sending uses OSCPacketBuilder)
// ============================================================================

static uint32_t hostToBE32(uint32_t val) {
    return ((val >> 24) & 0xFF) |
           ((val >>  8) & 0xFF00) |
           ((val <<  8) & 0xFF0000) |
           ((val << 24) & 0xFF000000);
}

static uint32_t beToHost32(uint32_t val) {
    return hostToBE32(val);  // same operation (symmetric)
}

static bool boolFromOscArg(const juce::var& arg, bool& out) {
    if (arg.isBool()) {
        out = static_cast<bool>(arg);
        return true;
    }

    if (arg.isInt() || arg.isInt64() || arg.isDouble()) {
        out = static_cast<double>(arg) != 0.0;
        return true;
    }

    if (arg.isString()) {
        const auto text = arg.toString().trim().toLowerCase();
        if (text == "1" || text == "true" || text == "on") {
            out = true;
            return true;
        }
        if (text == "0" || text == "false" || text == "off") {
            out = false;
            return true;
        }
    }

    return false;
}

static void logDispatchDiagnostic(std::atomic<int>& counter,
                                  const juce::String& label,
                                  const juce::String& address,
                                  const juce::String& detail) {
    const int count = counter.fetch_add(1, std::memory_order_relaxed) + 1;
    if (count <= 5 || (count % 100) == 0) {
        DBG("OSCServer: " << label << " '" << address << "' (" << detail
            << ", count=" << count << ")");
    }
}

// ============================================================================
// OSCServer lifecycle
// ============================================================================

OSCServer::OSCServer() = default;

OSCServer::~OSCServer() {
    stop();
}

void OSCServer::start(LooperProcessor* processor) {
    owner = processor;

    OSCSettings currentSettings;
    {
        std::lock_guard<std::mutex> lock(settingsMutex);
        currentSettings = settings;
    }

    if (!currentSettings.oscEnabled) return;

    socket = new juce::DatagramSocket(false);
    if (!socket->bindToPort(currentSettings.inputPort)) {
        delete socket;
        socket = nullptr;
        return;
    }

    running = true;
    receiveThread = std::thread(&OSCServer::receiveLoop, this);
    broadcastThread = std::thread(&OSCServer::broadcastLoop, this);
}

void OSCServer::stop() {
    running = false;

    if (socket) {
        socket->shutdown();
        delete socket;
        socket = nullptr;
    }

    if (receiveThread.joinable()) {
        receiveThread.join();
    }

    if (broadcastThread.joinable()) {
        broadcastThread.join();
    }
}

void OSCServer::setSettings(const OSCSettings& newSettings) {
    bool wasRunning = running.load();

    if (wasRunning) {
        stop();
    }

    {
        std::lock_guard<std::mutex> lock(settingsMutex);
        settings = newSettings;
    }

    if (wasRunning && settings.oscEnabled) {
        start(owner);
    }
}

OSCSettings OSCServer::getSettings() const {
    std::lock_guard<std::mutex> lock(settingsMutex);
    return settings;
}

// ============================================================================
// Target management
// ============================================================================

void OSCServer::addOutTarget(const juce::String& ipPort) {
    std::lock_guard<std::mutex> lock(targetsMutex);
    if (!configuredTargets.contains(ipPort)) {
        configuredTargets.add(ipPort);
    }
}

void OSCServer::removeOutTarget(const juce::String& ipPort) {
    std::lock_guard<std::mutex> lock(targetsMutex);
    int idx = configuredTargets.indexOf(ipPort);
    if (idx >= 0) configuredTargets.remove(idx);
}

void OSCServer::clearOutTargets() {
    std::lock_guard<std::mutex> lock(targetsMutex);
    configuredTargets.clear();
}

juce::StringArray OSCServer::getOutTargets() const {
    std::lock_guard<std::mutex> lock(targetsMutex);
    return configuredTargets;
}

void OSCServer::broadcast(const juce::String& address, const std::vector<juce::var>& args) {
    sendToTargets(address, args);
}

void OSCServer::setCustomValue(const juce::String& path,
                               const std::vector<juce::var>& args) {
    std::lock_guard<std::mutex> lock(customValuesMutex);
    customValues[path] = args;
}

bool OSCServer::getCustomValue(const juce::String& path,
                               std::vector<juce::var>& outArgs) const {
    std::lock_guard<std::mutex> lock(customValuesMutex);
    auto it = customValues.find(path);
    if (it == customValues.end()) {
        return false;
    }
    outArgs = it->second;
    return true;
}

void OSCServer::clearCustomValues() {
    std::lock_guard<std::mutex> lock(customValuesMutex);
    customValues.clear();
}

void OSCServer::setBroadcastRate(int hz) {
    broadcastRateHz.store(hz);
}

void OSCServer::setLuaCallback(LuaCallback callback) {
    std::lock_guard<std::mutex> lock(luaCallbackMutex);
    luaCallback = std::move(callback);
}

void OSCServer::setLuaQueryCallback(LuaQueryCallback callback) {
    std::lock_guard<std::mutex> lock(luaQueryCallbackMutex);
    luaQueryCallback = std::move(callback);
}

bool OSCServer::invokeLuaQueryCallback(const juce::String& path,
                                       std::vector<juce::var>& outArgs) const {
    std::lock_guard<std::mutex> lock(luaQueryCallbackMutex);
    if (!luaQueryCallback) {
        return false;
    }
    return luaQueryCallback(path, outArgs);
}

// ============================================================================
// UDP receive loop
// ============================================================================

void OSCServer::receiveLoop() {
    juce::uint8 buffer[4096];
    juce::String senderIP;
    int senderPort = 0;

    while (running.load()) {
        if (!socket) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        int bytesRead = socket->read(buffer, sizeof(buffer) - 1, false, senderIP, senderPort);

        if (bytesRead > 0) {
            parseAndDispatch((const char*)buffer, bytesRead, senderIP, senderPort);
            // Note: We do NOT auto-pair the sender's ephemeral port here.
            // Targets must be explicitly added via addOutTarget() or /api/targets.
            // The sender's ephemeral UDP port is typically not their listening port.
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
}

// ============================================================================
// State-change broadcast loop
//
// Runs at broadcastRateHz (default 30Hz). Polls AtomicState, compares to
// cached snapshot, broadcasts OSC messages for any changed values to all
// configured targets.
// ============================================================================

void OSCServer::broadcastLoop() {
    while (running.load()) {
        int hz = broadcastRateHz.load();
        if (hz <= 0 || !owner) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        broadcastStateChanges();

        int sleepMs = 1000 / hz;
        if (sleepMs < 1) sleepMs = 1;
        std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
    }
}

void OSCServer::broadcastStateChanges() {
    if (!owner) return;

    // Quick check: any targets to send to?
    {
        std::lock_guard<std::mutex> lock(targetsMutex);
        if (configuredTargets.isEmpty()) return;
    }

    auto& state = owner->getControlServer().getAtomicState();

    // --- Global state diffs ---

    float newTempo = state.tempo.load(std::memory_order_relaxed);
    if (std::abs(newTempo - cachedState.tempo) > 0.01f) {
        cachedState.tempo = newTempo;
        broadcast("/looper/tempo", { juce::var(newTempo) });
    }

    bool newRec = state.isRecording.load(std::memory_order_relaxed);
    if (newRec != cachedState.isRecording) {
        cachedState.isRecording = newRec;
        broadcast("/looper/recording", { juce::var(newRec ? 1 : 0) });
    }

    bool newOD = state.overdubEnabled.load(std::memory_order_relaxed);
    if (newOD != cachedState.overdubEnabled) {
        cachedState.overdubEnabled = newOD;
        broadcast("/looper/overdub", { juce::var(newOD ? 1 : 0) });
    }

    int newMode = state.recordMode.load(std::memory_order_relaxed);
    if (newMode != cachedState.recordMode) {
        cachedState.recordMode = newMode;
        const char* modeStr = (newMode == 0) ? "firstLoop" :
                              (newMode == 1) ? "freeMode" :
                              (newMode == 2) ? "traditional" : "retrospective";
        broadcast("/looper/mode", { juce::var(juce::String(modeStr)) });
    }

    int newActiveLayer = state.activeLayer.load(std::memory_order_relaxed);
    if (newActiveLayer != cachedState.activeLayer) {
        cachedState.activeLayer = newActiveLayer;
        broadcast("/looper/layer", { juce::var(newActiveLayer) });
    }

    float newVol = state.masterVolume.load(std::memory_order_relaxed);
    if (std::abs(newVol - cachedState.masterVolume) > 0.001f) {
        cachedState.masterVolume = newVol;
        broadcast("/looper/volume", { juce::var(newVol) });
    }

    // --- Per-layer state diffs ---

    for (int i = 0; i < OSCStateSnapshot::MAX_LAYERS && i < AtomicState::MAX_LAYERS; ++i) {
        auto& ls = state.layers[i];
        auto& cs = cachedState.layers[i];
        juce::String prefix = "/looper/layer/" + juce::String(i) + "/";

        int newState = ls.state.load(std::memory_order_relaxed);
        if (newState != cs.state) {
            cs.state = newState;
            const char* stateStr = (newState == 0) ? "empty" :
                                   (newState == 1) ? "playing" :
                                   (newState == 2) ? "recording" :
                                   (newState == 3) ? "overdubbing" :
                                   (newState == 4) ? "muted" :
                                   (newState == 5) ? "stopped" :
                                   (newState == 6) ? "paused" : "unknown";
            broadcast(prefix + "state", { juce::var(juce::String(stateStr)) });
        }

        float newSpeed = ls.speed.load(std::memory_order_relaxed);
        if (std::abs(newSpeed - cs.speed) > 0.001f) {
            cs.speed = newSpeed;
            broadcast(prefix + "speed", { juce::var(newSpeed) });
        }

        float newLayerVol = ls.volume.load(std::memory_order_relaxed);
        if (std::abs(newLayerVol - cs.volume) > 0.001f) {
            cs.volume = newLayerVol;
            broadcast(prefix + "volume", { juce::var(newLayerVol) });
        }

        bool newRev = ls.reversed.load(std::memory_order_relaxed);
        if (newRev != cs.reversed) {
            cs.reversed = newRev;
            broadcast(prefix + "reverse", { juce::var(newRev ? 1 : 0) });
        }

        // Position: normalized 0-1. Only broadcast if layer is playing and position changed meaningfully.
        int len = ls.length.load(std::memory_order_relaxed);
        float newPos = (len > 0) ? (float)ls.playheadPos.load(std::memory_order_relaxed) / (float)len : 0.0f;
        if (std::abs(newPos - cs.position) > 0.005f) {
            cs.position = newPos;
            broadcast(prefix + "position", { juce::var(newPos) });
        }

        float newBars = ls.numBars.load(std::memory_order_relaxed);
        if (std::abs(newBars - cs.bars) > 0.001f) {
            cs.bars = newBars;
            broadcast(prefix + "bars", { juce::var(newBars) });
        }
    }
}

// ============================================================================
// OSC message parsing
// ============================================================================

void OSCServer::parseAndDispatch(const char* data, int size,
                                 const juce::String& sourceIP, int sourcePort) {
    OSCMessage msg;
    msg.sourceIP = sourceIP;
    msg.sourcePort = sourcePort;

    if (parseOSCMessage(data, size, msg)) {
        messagesReceived++;
        dispatchMessage(msg);
    }
}

bool OSCServer::parseOSCMessage(const char* data, int size, OSCMessage& out) {
    if (size < 8) return false;

    int offset = 0;

    // Read address (null-terminated, padded to 4 bytes)
    juce::String address;
    while (offset < size && data[offset] != '\0') {
        address += data[offset++];
    }
    offset++;  // skip null
    while (offset % 4 != 0) offset++;

    if (offset >= size || data[offset] != ',') return false;
    offset++;

    // Read type tag string
    juce::String typeTag;
    while (offset < size && data[offset] != '\0') {
        typeTag += data[offset++];
    }
    offset++;
    while (offset % 4 != 0) offset++;

    out.address = address;

    for (int i = 0; i < typeTag.length() && offset < size; i++) {
        char tag = typeTag[i];
        juce::var arg = parseArgument(tag, data, size, offset);
        if (!arg.isVoid()) {
            out.args.push_back(arg);
        }
    }

    return true;
}

juce::var OSCServer::parseArgument(char tag, const char* data,
                                   int dataLen, int& offset) {

    if (tag == 'i' && offset + 4 <= dataLen) {
        uint32_t beVal;
        std::memcpy(&beVal, data + offset, 4);
        beVal = beToHost32(beVal);
        int32_t val = static_cast<int32_t>(beVal);
        offset += 4;
        return juce::var((int)val);
    }
    else if (tag == 'f' && offset + 4 <= dataLen) {
        uint32_t beVal;
        std::memcpy(&beVal, data + offset, 4);
        beVal = beToHost32(beVal);
        float val;
        std::memcpy(&val, &beVal, 4);
        offset += 4;
        return juce::var(val);
    }
    else if (tag == 's' || tag == 'S') {
        juce::String str;
        while (offset < dataLen && data[offset] != '\0') {
            str += data[offset++];
        }
        offset++;
        while (offset % 4 != 0) offset++;
        return juce::var(str);
    }
    else if (tag == 'h' || tag == 'd' || tag == 't') {
        offset += 8;  // skip 8-byte types
        return juce::var(0);
    }
    else if (tag == 'T' || tag == 'F' || tag == 'N' || tag == 'I') {
        return juce::var();  // no data
    }

    return juce::var();
}

// ============================================================================
// OSC message dispatch -> ControlCommand
// ============================================================================

void OSCServer::dispatchMessage(const OSCMessage& msg) {
    if (!owner) return;

    // Track custom endpoint values for OSCQuery VALUE/LISTEN.
    // Anything outside /looper/* is considered user/custom namespace.
    if (!msg.address.startsWith("/looper/") && !msg.args.empty()) {
        setCustomValue(msg.address, msg.args);
    }

    // Check for Lua callbacks first (allows Lua to override built-in behavior)
    {
        std::lock_guard<std::mutex> lock(luaCallbackMutex);
        if (luaCallback && luaCallback(msg.address, msg.args)) {
            return;  // Lua handled the message
        }
    }

    auto* endpointRegistry = &owner->getEndpointRegistry();

    juce::String path = msg.address;
    if (path == "/looper/recstop") {
        path = "/looper/stoprec";
    }

    if (path == "/looper/state") {
        return;  // read-only query endpoint
    }

    ParseResult parsed;
    bool hasCommandCandidate = false;

    if (path == "/looper/rec" && !msg.args.empty()) {
        bool shouldStart = true;
        if (!boolFromOscArg(msg.args.front(), shouldStart)) {
            logDispatchDiagnostic(this->invalidMessages,
                                  "invalid OSC argument",
                                  msg.address,
                                  "expected bool-like rec value");
            return;
        }

        parsed = CommandParser::buildResolverTriggerCommand(
            endpointRegistry,
            shouldStart ? juce::String("/looper/rec")
                        : juce::String("/looper/stoprec"));
        hasCommandCandidate = true;
    } else if (path == "/looper/overdub" && msg.args.empty()) {
        parsed = CommandParser::buildResolverTriggerCommand(
            endpointRegistry,
            path,
            true /* allow toggle */);
        hasCommandCandidate = true;
    } else if (!msg.args.empty()) {
        parsed = CommandParser::buildResolverSetCommand(
            endpointRegistry,
            path,
            msg.args.front());
        hasCommandCandidate = true;
    } else if (path.startsWith("/looper/")) {
        parsed = CommandParser::buildResolverTriggerCommand(endpointRegistry, path);
        hasCommandCandidate = true;
    } else {
        return;
    }

    if (!hasCommandCandidate) {
        return;
    }

    if (parsed.kind != ParseResult::Kind::Enqueue) {
        if (parsed.kind == ParseResult::Kind::Error) {
            const bool unknownPath =
                parsed.errorMessage.rfind("unknown path:", 0) == 0;
            logDispatchDiagnostic(
                unknownPath ? this->unknownPathMessages : this->invalidMessages,
                unknownPath ? "unknown OSC address" : "rejected OSC message",
                msg.address,
                juce::String(parsed.errorMessage));
        }
        return;
    }

    if (!owner->postControlCommandPayload(parsed.command)) {
        logDispatchDiagnostic(this->queueFullDrops,
                              "command queue full",
                              msg.address,
                              "failed to enqueue OSC command");
    }
}

// ============================================================================
// OSC message sending (with correct big-endian byte order)
// ============================================================================

void OSCServer::sendToTargets(const juce::String& address,
                              const std::vector<juce::var>& args) {
    juce::StringArray targets;
    {
        std::lock_guard<std::mutex> lock(targetsMutex);
        targets = configuredTargets;
    }

    if (targets.isEmpty()) return;

    // Build OSC packet using shared builder
    auto packet = OSCPacketBuilder::build(address, args);

    // Send to all targets
    for (int t = 0; t < targets.size(); t++) {
        const juce::String& target = targets[t];
        int colonPos = target.indexOf(":");
        if (colonPos > 0) {
            juce::String host = target.substring(0, colonPos);
            int port = target.substring(colonPos + 1).getIntValue();

            juce::DatagramSocket sock(false);
            if (sock.write(host, port, (const void*)packet.data(), (int)packet.size()) > 0) {
                messagesSent++;
            }
        }
    }
}

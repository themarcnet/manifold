#include "OSCServer.h"
#include "OSCPacketBuilder.h"
#include "CommandParser.h"
#include "../scripting/ScriptableProcessor.h"
#include <cstring>
#include <cmath>
#include <cstdlib>

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

static uint64_t hostToBE64(uint64_t val) {
    return ((val >> 56) & 0x00000000000000FFULL) |
           ((val >> 40) & 0x000000000000FF00ULL) |
           ((val >> 24) & 0x0000000000FF0000ULL) |
           ((val >>  8) & 0x00000000FF000000ULL) |
           ((val <<  8) & 0x000000FF00000000ULL) |
           ((val << 24) & 0x0000FF0000000000ULL) |
           ((val << 40) & 0x00FF000000000000ULL) |
           ((val << 56) & 0xFF00000000000000ULL);
}

static uint64_t beToHost64(uint64_t val) {
    return hostToBE64(val);  // same operation (symmetric)
}

static bool floatFromOscArg(const juce::var& arg, float& out) {
    if (arg.isBool()) {
        out = static_cast<bool>(arg) ? 1.0f : 0.0f;
        return true;
    }

    if (arg.isInt() || arg.isInt64() || arg.isDouble()) {
        out = static_cast<float>(static_cast<double>(arg));
        return true;
    }

    if (arg.isString()) {
        const juce::String text = arg.toString().trim();
        const juce::String lowered = text.toLowerCase();
        if (lowered == "true" || lowered == "on") {
            out = 1.0f;
            return true;
        }
        if (lowered == "false" || lowered == "off") {
            out = 0.0f;
            return true;
        }

        const char* begin = text.toRawUTF8();
        char* end = nullptr;
        const double parsed = std::strtod(begin, &end);
        if (end != begin && *end == '\0') {
            out = static_cast<float>(parsed);
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

void OSCServer::start(ScriptableProcessor* processor) {
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

void OSCServer::removeCustomValue(const juce::String& path) {
    std::lock_guard<std::mutex> lock(customValuesMutex);
    customValues.erase(path);
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
        broadcast("/core/behavior/tempo", { juce::var(newTempo) });
    }

    bool newRec = state.isRecording.load(std::memory_order_relaxed);
    if (newRec != cachedState.isRecording) {
        cachedState.isRecording = newRec;
        broadcast("/core/behavior/recording", { juce::var(newRec ? 1 : 0) });
    }

    bool newOD = state.overdubEnabled.load(std::memory_order_relaxed);
    if (newOD != cachedState.overdubEnabled) {
        cachedState.overdubEnabled = newOD;
        broadcast("/core/behavior/overdub", { juce::var(newOD ? 1 : 0) });
    }

    int newMode = state.recordMode.load(std::memory_order_relaxed);
    if (newMode != cachedState.recordMode) {
        cachedState.recordMode = newMode;
        const char* modeStr = (newMode == 0) ? "firstLoop" :
                              (newMode == 1) ? "freeMode" :
                              (newMode == 2) ? "traditional" : "retrospective";
        broadcast("/core/behavior/mode", { juce::var(juce::String(modeStr)) });
    }

    int newActiveLayer = state.activeLayer.load(std::memory_order_relaxed);
    if (newActiveLayer != cachedState.activeLayer) {
        cachedState.activeLayer = newActiveLayer;
        broadcast("/core/behavior/layer", { juce::var(newActiveLayer) });
    }

    float newVol = state.masterVolume.load(std::memory_order_relaxed);
    if (std::abs(newVol - cachedState.masterVolume) > 0.001f) {
        cachedState.masterVolume = newVol;
        broadcast("/core/behavior/volume", { juce::var(newVol) });
    }

    // --- Per-layer state diffs ---

    for (int i = 0; i < OSCStateSnapshot::MAX_LAYERS && i < AtomicState::MAX_LAYERS; ++i) {
        auto& ls = state.layers[i];
        auto& cs = cachedState.layers[i];
        juce::String prefix = "/core/behavior/layer/" + juce::String(i) + "/";

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

    for (int i = 0; i < typeTag.length(); i++) {
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
    else if (tag == 'h' && offset + 8 <= dataLen) {
        uint64_t beVal = 0;
        std::memcpy(&beVal, data + offset, 8);
        const int64_t val = static_cast<int64_t>(beToHost64(beVal));
        offset += 8;
        return juce::var(static_cast<double>(val));
    }
    else if (tag == 'd' && offset + 8 <= dataLen) {
        uint64_t beVal = 0;
        std::memcpy(&beVal, data + offset, 8);
        const uint64_t hostBits = beToHost64(beVal);
        double val = 0.0;
        std::memcpy(&val, &hostBits, 8);
        offset += 8;
        return juce::var(val);
    }
    else if (tag == 't' && offset + 8 <= dataLen) {
        // OSC timetag. Preserve as numeric payload.
        uint64_t beVal = 0;
        std::memcpy(&beVal, data + offset, 8);
        const int64_t val = static_cast<int64_t>(beToHost64(beVal));
        offset += 8;
        return juce::var(static_cast<double>(val));
    }
    else if (tag == 'T') {
        return juce::var(1);
    }
    else if (tag == 'F') {
        return juce::var(0);
    }
    else if (tag == 'N' || tag == 'I') {
        return juce::var();  // no payload
    }

    return juce::var();
}

// ============================================================================
// OSC message dispatch -> ControlCommand
// ============================================================================

void OSCServer::dispatchMessage(const OSCMessage& msg) {
    if (!owner) return;

    const juce::String path = msg.address;
    const bool isBehaviorPath = path.startsWith("/core/behavior/");

    // Track custom endpoint values for OSCQuery VALUE/LISTEN.
    if (!isBehaviorPath && !msg.args.empty()) {
        setCustomValue(path, msg.args);
    }

    // Check for Lua callbacks first (allows Lua to override built-in behavior).
    {
        std::lock_guard<std::mutex> lock(luaCallbackMutex);
        if (luaCallback && luaCallback(path, msg.args)) {
            return;
        }
    }

    auto* endpointRegistry = &owner->getEndpointRegistry();
    EndpointResolver resolver(endpointRegistry);
    ResolvedEndpoint endpoint;
    if (!resolver.resolve(path, endpoint)) {
        logDispatchDiagnostic(this->unknownPathMessages,
                              "unknown OSC address",
                              msg.address,
                              "not registered");
        return;
    }

    ParseResult parsed;

    if (msg.args.empty()) {
        if (endpoint.commandType == ControlCommand::Type::None) {
            logDispatchDiagnostic(this->invalidMessages,
                                  "rejected OSC message",
                                  msg.address,
                                  "missing value for direct endpoint");
            return;
        }

        parsed = CommandParser::buildResolverTriggerCommand(endpointRegistry, path,
                                                            true /* allow toggle */);
    } else {
        const auto validation = resolver.validateWrite(endpoint, msg.args.front());
        if (!validation.accepted) {
            logDispatchDiagnostic(this->invalidMessages,
                                  "rejected OSC message",
                                  msg.address,
                                  "write validation failed");
            return;
        }

        if (endpoint.commandType == ControlCommand::Type::None) {
            float value = 0.0f;
            if (!floatFromOscArg(validation.normalizedValue, value)) {
                logDispatchDiagnostic(this->invalidMessages,
                                      "rejected OSC message",
                                      msg.address,
                                      "normalized value is not numeric");
                return;
            }

            if (!owner->setParamByPath(path.toStdString(), value)) {
                logDispatchDiagnostic(this->invalidMessages,
                                      "rejected OSC message",
                                      msg.address,
                                      "direct endpoint handler rejected write");
            }
            return;
        }

        parsed = CommandParser::buildResolverSetCommand(endpointRegistry,
                                                        path,
                                                        validation.normalizedValue);
    }

    if (!parsed.warningCode.empty()) {
        static std::atomic<int> coercionWarnings{0};
        logDispatchDiagnostic(coercionWarnings,
                              parsed.warningCode,
                              msg.address,
                              parsed.warningMessage);
    }

    if (parsed.kind == ParseResult::Kind::NoOpWarning) {
        logDispatchDiagnostic(this->invalidMessages,
                              parsed.warningCode.empty() ? "rejected OSC message"
                                                         : parsed.warningCode,
                              msg.address,
                              parsed.warningMessage);
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

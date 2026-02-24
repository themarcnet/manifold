#include "OSCServer.h"
#include "../../engine/LooperProcessor.h"
#include <cstring>

// ============================================================================
// Byte-order helpers - OSC uses big-endian (network byte order)
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
    if (!pairedTargets.contains(ipPort)) {
        pairedTargets.add(ipPort);
    }
}

void OSCServer::removeOutTarget(const juce::String& ipPort) {
    std::lock_guard<std::mutex> lock(targetsMutex);
    int idx = pairedTargets.indexOf(ipPort);
    if (idx >= 0) pairedTargets.remove(idx);
}

void OSCServer::clearOutTargets() {
    std::lock_guard<std::mutex> lock(targetsMutex);
    pairedTargets.clear();
}

juce::StringArray OSCServer::getOutTargets() const {
    std::lock_guard<std::mutex> lock(targetsMutex);
    return pairedTargets;
}

void OSCServer::broadcast(const juce::String& address, const std::vector<juce::var>& args) {
    sendToTargets(address, args);
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

            // Auto-pair: add sender as a broadcast target
            juce::String ipPort = senderIP + ":" + juce::String(senderPort);
            {
                std::lock_guard<std::mutex> lock(targetsMutex);
                if (!pairedTargets.contains(ipPort)) {
                    pairedTargets.add(ipPort);
                }
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
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

    auto& cmdQueue = owner->getControlServer().getCommandQueue();
    ControlCommand cmd;

    if (msg.address == "/looper/tempo" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::SetTempo;
        cmd.floatParam = (float)msg.args[0];
    }
    else if (msg.address == "/looper/commit" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::Commit;
        cmd.floatParam = (float)msg.args[0];
    }
    else if (msg.address == "/looper/forward" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::ForwardCommit;
        cmd.floatParam = (float)msg.args[0];
    }
    else if (msg.address == "/looper/rec") {
        if (msg.args.size() >= 1 && msg.args[0].isInt()) {
            cmd.type = ((int)msg.args[0] == 0) ?
                ControlCommand::Type::StopRecording :
                ControlCommand::Type::StartRecording;
        } else {
            cmd.type = ControlCommand::Type::StartRecording;
        }
    }
    else if (msg.address == "/looper/stoprec" || msg.address == "/looper/recstop") {
        cmd.type = ControlCommand::Type::StopRecording;
    }
    else if (msg.address == "/looper/stop") {
        cmd.type = ControlCommand::Type::GlobalStop;
    }
    else if (msg.address == "/looper/play") {
        cmd.type = ControlCommand::Type::GlobalPlay;
    }
    else if (msg.address == "/looper/pause") {
        cmd.type = ControlCommand::Type::GlobalPause;
    }
    else if (msg.address == "/looper/clear") {
        cmd.type = ControlCommand::Type::ClearAllLayers;
    }
    else if (msg.address == "/looper/overdub") {
        if (msg.args.size() >= 1) {
            cmd.type = ControlCommand::Type::SetOverdubEnabled;
            cmd.intParam = ((int)msg.args[0]) ? 1 : 0;
        } else {
            cmd.type = ControlCommand::Type::ToggleOverdub;
        }
    }
    else if (msg.address == "/looper/mode" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::SetRecordMode;
        juce::String mode = msg.args[0].toString();
        if      (mode == "firstLoop")     cmd.intParam = 0;
        else if (mode == "freeMode")      cmd.intParam = 1;
        else if (mode == "traditional")   cmd.intParam = 2;
        else if (mode == "retrospective") cmd.intParam = 3;
    }
    else if (msg.address == "/looper/layer" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::SetActiveLayer;
        cmd.intParam = (int)msg.args[0];
    }
    else if (msg.address == "/looper/volume" && msg.args.size() >= 1) {
        cmd.type = ControlCommand::Type::SetMasterVolume;
        cmd.floatParam = (float)msg.args[0];
    }
    else if (msg.address == "/looper/state") {
        return;  // read-only query, no command to enqueue
    }
    else if (msg.address.startsWith("/looper/layer/")) {
        juce::String rest = msg.address.fromFirstOccurrenceOf("/looper/layer/", false, false);
        int slashPos = rest.indexOf("/");
        if (slashPos > 0) {
            int layer = rest.substring(0, slashPos).getIntValue();
            juce::String prop = rest.substring(slashPos + 1);

            if (layer >= 0 && layer < 4) {
                cmd.intParam = layer;

                if      (prop == "speed"   && msg.args.size() >= 1) { cmd.type = ControlCommand::Type::LayerSpeed;   cmd.floatParam = (float)msg.args[0]; }
                else if (prop == "volume"  && msg.args.size() >= 1) { cmd.type = ControlCommand::Type::LayerVolume;  cmd.floatParam = (float)msg.args[0]; }
                else if (prop == "mute"    && msg.args.size() >= 1) { cmd.type = ControlCommand::Type::LayerMute;    cmd.intParam = ((int)msg.args[0]) ? 1 : 0; }
                else if (prop == "reverse" && msg.args.size() >= 1) { cmd.type = ControlCommand::Type::LayerReverse; cmd.intParam = ((int)msg.args[0]) ? 1 : 0; }
                else if (prop == "play")    { cmd.type = ControlCommand::Type::LayerPlay; }
                else if (prop == "pause")   { cmd.type = ControlCommand::Type::LayerPause; }
                else if (prop == "stop")    { cmd.type = ControlCommand::Type::LayerStop; }
                else if (prop == "clear")   { cmd.type = ControlCommand::Type::LayerClear; }
                else if (prop == "seek" && msg.args.size() >= 1) { cmd.type = ControlCommand::Type::LayerSeek; cmd.floatParam = (float)msg.args[0]; }
            }
        }
    }

    if (cmd.type != ControlCommand::Type::None) {
        cmdQueue.enqueue(cmd);
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
        targets = pairedTargets;
    }

    if (targets.isEmpty()) return;

    // Build OSC packet
    std::vector<char> packet;

    // Address string (null-terminated, padded to 4 bytes)
    for (int i = 0; i < address.length(); i++) {
        packet.push_back((char)address[i]);
    }
    packet.push_back('\0');
    while (packet.size() % 4 != 0) packet.push_back('\0');

    // Type tag string
    packet.push_back(',');
    juce::String typeTag;
    for (const auto& arg : args) {
        if (arg.isInt())         typeTag += "i";
        else if (arg.isDouble()) typeTag += "f";
        else if (arg.isString()) typeTag += "s";
        else                     typeTag += "N";
    }
    for (int i = 0; i < typeTag.length(); i++) {
        packet.push_back(typeTag[i]);
    }
    packet.push_back('\0');
    while (packet.size() % 4 != 0) packet.push_back('\0');

    // Arguments (big-endian)
    for (const auto& arg : args) {
        if (arg.isInt()) {
            int32_t val = (int32_t)(int)arg;
            uint32_t beVal;
            std::memcpy(&beVal, &val, 4);
            beVal = hostToBE32(beVal);
            const char* bytes = reinterpret_cast<const char*>(&beVal);
            for (int i = 0; i < 4; i++) packet.push_back(bytes[i]);
        }
        else if (arg.isDouble()) {
            float val = (float)(double)arg;
            uint32_t beVal;
            std::memcpy(&beVal, &val, 4);
            beVal = hostToBE32(beVal);
            const char* bytes = reinterpret_cast<const char*>(&beVal);
            for (int i = 0; i < 4; i++) packet.push_back(bytes[i]);
        }
        else if (arg.isString()) {
            juce::String str = arg.toString();
            for (int i = 0; i < str.length(); i++) {
                packet.push_back((char)str[i]);
            }
            packet.push_back('\0');
            while (packet.size() % 4 != 0) packet.push_back('\0');
        }
    }

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

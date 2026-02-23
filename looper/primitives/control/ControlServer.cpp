#include "ControlServer.h"
#include "../../engine/LooperProcessor.h"
#include "../dsp/CaptureBuffer.h"

#include <juce_audio_formats/juce_audio_formats.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <cerrno>
#include <cstdio>
#include <sstream>
#include <algorithm>
#include <chrono>

// ============================================================================
// Helpers
// ============================================================================

static void setNonBlocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static std::string trim(const std::string& s) {
    auto start = s.find_first_not_of(" \t\r\n");
    auto end = s.find_last_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    return s.substr(start, end - start + 1);
}

static std::string toUpper(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::toupper);
    return s;
}

// Simple JSON helpers (no dependency)
static std::string jsonStr(const std::string& key, const std::string& val) {
    return "\"" + key + "\":\"" + val + "\"";
}

static std::string jsonNum(const std::string& key, double val) {
    char buf[64];
    if (val == (int)val)
        std::snprintf(buf, sizeof(buf), "\"%s\":%d", key.c_str(), (int)val);
    else
        std::snprintf(buf, sizeof(buf), "\"%s\":%.6g", key.c_str(), val);
    return buf;
}

static std::string jsonBool(const std::string& key, bool val) {
    return "\"" + key + "\":" + (val ? "true" : "false");
}

static const char* layerStateToString(int state) {
    switch (state) {
        case 0: return "empty";
        case 1: return "playing";
        case 2: return "recording";
        case 3: return "overdubbing";
        case 4: return "muted";
        case 5: return "stopped";
        default: return "unknown";
    }
}

static const char* recordModeToString(int mode) {
    switch (mode) {
        case 0: return "firstLoop";
        case 1: return "freeMode";
        case 2: return "traditional";
        case 3: return "retrospective";
        default: return "unknown";
    }
}

static int recordModeFromString(const std::string& s) {
    auto upper = toUpper(s);
    if (upper == "FIRSTLOOP" || upper == "FIRST" || upper == "0") return 0;
    if (upper == "FREEMODE" || upper == "FREE" || upper == "1") return 1;
    if (upper == "TRADITIONAL" || upper == "TRAD" || upper == "2") return 2;
    if (upper == "RETROSPECTIVE" || upper == "RETRO" || upper == "3") return 3;
    return -1;
}

// ============================================================================
// ControlServer
// ============================================================================

ControlServer::ControlServer() {}

ControlServer::~ControlServer() {
    stop();
}

void ControlServer::start(LooperProcessor* processor) {
    if (running.load()) return;
    owner = processor;

    // Build socket path: /tmp/looper_<pid>.sock
    socketPath = "/tmp/looper_" + std::to_string(getpid()) + ".sock";

    // Remove stale socket
    ::unlink(socketPath.c_str());

    // Create Unix domain socket
    serverFd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (serverFd < 0) {
        DBG("ControlServer: socket() failed: " << strerror(errno));
        return;
    }

    struct sockaddr_un addr;
    std::memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socketPath.c_str(), sizeof(addr.sun_path) - 1);

    if (::bind(serverFd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        DBG("ControlServer: bind() failed: " << strerror(errno));
        ::close(serverFd);
        serverFd = -1;
        return;
    }

    if (::listen(serverFd, 8) < 0) {
        DBG("ControlServer: listen() failed: " << strerror(errno));
        ::close(serverFd);
        ::unlink(socketPath.c_str());
        serverFd = -1;
        return;
    }

    setNonBlocking(serverFd);
    running.store(true);

    // Accept thread: listens for new connections
    acceptThread = std::thread([this] { acceptLoop(); });

    // Broadcast thread: drains event ring and sends to watchers
    broadcastThread = std::thread([this] {
        while (running.load()) {
            drainAndBroadcastEvents();
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    });

    DBG("ControlServer: listening on " << socketPath);
}

void ControlServer::stop() {
    if (!running.exchange(false)) return;

    // Close server socket to unblock accept
    if (serverFd >= 0) {
        ::shutdown(serverFd, SHUT_RDWR);
        ::close(serverFd);
        serverFd = -1;
    }

    // Join threads
    if (acceptThread.joinable()) acceptThread.join();
    if (broadcastThread.joinable()) broadcastThread.join();

    // Close all client connections
    {
        std::lock_guard<std::mutex> lock(clientsMutex);
        for (int fd : clientFds) ::close(fd);
        clientFds.clear();
    }
    {
        std::lock_guard<std::mutex> lock(watchersMutex);
        for (int fd : watcherFds) ::close(fd);
        watcherFds.clear();
    }

    // Remove socket file
    if (!socketPath.empty()) {
        ::unlink(socketPath.c_str());
        DBG("ControlServer: stopped, removed " << socketPath);
    }

    owner = nullptr;
}

bool ControlServer::enqueueCommand(const ControlCommand& command) {
    std::lock_guard<std::mutex> lock(commandQueueWriteMutex);
    const bool ok = commandQueue.enqueue(command);
    if (ok)
        commandsProcessed.fetch_add(1, std::memory_order_relaxed);
    return ok;
}

// ============================================================================
// Accept loop - runs in its own thread
// ============================================================================

void ControlServer::acceptLoop() {
    while (running.load()) {
        struct pollfd pfd;
        pfd.fd = serverFd;
        pfd.events = POLLIN;
        pfd.revents = 0;

        int ret = ::poll(&pfd, 1, 100); // 100ms timeout
        if (ret <= 0 || !running.load()) continue;

        int clientFd = ::accept(serverFd, nullptr, nullptr);
        if (clientFd < 0) continue;

        // Track this client
        {
            std::lock_guard<std::mutex> lock(clientsMutex);
            clientFds.push_back(clientFd);
        }

        // Spawn a thread per client (simple, fine for low client count)
        std::thread([this, clientFd] {
            clientLoop(clientFd);

            // Clean up
            {
                std::lock_guard<std::mutex> lock(clientsMutex);
                clientFds.erase(std::remove(clientFds.begin(), clientFds.end(), clientFd), clientFds.end());
            }
            removeWatcher(clientFd);
            ::close(clientFd);
        }).detach();
    }
}

// ============================================================================
// Client loop - one per connection, reads line-based commands
// ============================================================================

void ControlServer::clientLoop(int clientFd) {
    char readBuf[4096];
    std::string lineBuffer;

    while (running.load()) {
        struct pollfd pfd;
        pfd.fd = clientFd;
        pfd.events = POLLIN;
        pfd.revents = 0;

        int ret = ::poll(&pfd, 1, 200);
        if (ret < 0) break;
        if (ret == 0) continue;

        if (pfd.revents & (POLLHUP | POLLERR)) break;

        ssize_t n = ::read(clientFd, readBuf, sizeof(readBuf) - 1);
        if (n <= 0) break;
        readBuf[n] = '\0';
        lineBuffer += readBuf;

        // Process complete lines
        size_t pos;
        while ((pos = lineBuffer.find('\n')) != std::string::npos) {
            std::string line = trim(lineBuffer.substr(0, pos));
            lineBuffer = lineBuffer.substr(pos + 1);

            if (line.empty()) continue;

            std::string response = processCommand(line);
            response += "\n";

            // Send response
            ssize_t sent = ::write(clientFd, response.c_str(), response.size());
            if (sent < 0) return; // client gone

            // If this was a WATCH command, stay in watcher mode
            if (toUpper(line) == "WATCH") {
                addWatcher(clientFd);
                // Block here until connection closes - watcher stays alive
                while (running.load()) {
                    struct pollfd wpfd;
                    wpfd.fd = clientFd;
                    wpfd.events = POLLIN;
                    wpfd.revents = 0;
                    int wret = ::poll(&wpfd, 1, 500);
                    if (wret < 0) return;
                    if (wpfd.revents & (POLLHUP | POLLERR)) return;
                    if (wret > 0 && (wpfd.revents & POLLIN)) {
                        // Client sent something (maybe disconnect)
                        char tmp[64];
                        if (::read(clientFd, tmp, sizeof(tmp)) <= 0) return;
                    }
                }
                return;
            }
        }
    }
}

// ============================================================================
// Command processing - called from client thread, reads atomics
// ============================================================================

std::string ControlServer::processCommand(const std::string& cmd) {
    // Tokenize
    std::istringstream iss(cmd);
    std::vector<std::string> tokens;
    std::string tok;
    while (iss >> tok) tokens.push_back(tok);

    if (tokens.empty()) return "ERROR empty command";

    auto verb = toUpper(tokens[0]);

    auto enqueueAndOk = [this](const ControlCommand& command) -> std::string {
        if (!enqueueCommand(command))
            return "ERROR queue full";
        return "OK";
    };

    // ---- STATE ----
    if (verb == "STATE") {
        return "OK " + buildStateJson();
    }

    // ---- PING ----
    if (verb == "PING") {
        return "OK PONG";
    }

    // ---- DIAGNOSE ----
    if (verb == "DIAGNOSE") {
        return "OK " + buildDiagnoseJson();
    }

    // ---- WATCH ----
    if (verb == "WATCH") {
        return "OK watching";
    }

    // ---- COMMIT <bars> ----
    if (verb == "COMMIT") {
        if (tokens.size() < 2) return "ERROR usage: COMMIT <bars>";
        try {
            float bars = std::stof(tokens[1]);
            ControlCommand c;
            c.type = ControlCommand::Type::Commit;
            c.floatParam = bars;
            return enqueueAndOk(c);
        } catch (...) {
            return "ERROR invalid bars value";
        }
    }

    // ---- FORWARD <bars> ----
    if (verb == "FORWARD") {
        if (tokens.size() < 2) return "ERROR usage: FORWARD <bars>";
        try {
            float bars = std::stof(tokens[1]);
            ControlCommand c;
            c.type = ControlCommand::Type::ForwardCommit;
            c.floatParam = bars;
            return enqueueAndOk(c);
        } catch (...) {
            return "ERROR invalid bars value";
        }
    }

    // ---- TEMPO <bpm> ----
    if (verb == "TEMPO") {
        if (tokens.size() < 2) return "ERROR usage: TEMPO <bpm>";
        try {
            float bpm = std::stof(tokens[1]);
            ControlCommand c;
            c.type = ControlCommand::Type::SetTempo;
            c.floatParam = bpm;
            return enqueueAndOk(c);
        } catch (...) {
            return "ERROR invalid bpm value";
        }
    }

    // ---- REC ----
    if (verb == "REC") {
        ControlCommand c;
        c.type = ControlCommand::Type::StartRecording;
        return enqueueAndOk(c);
    }

    // ---- OVERDUB ----
    if (verb == "OVERDUB") {
        ControlCommand c;
        if (tokens.size() >= 2) {
            c.type = ControlCommand::Type::SetOverdubEnabled;
            c.floatParam = (tokens[1] == "1" || toUpper(tokens[1]) == "TRUE" || toUpper(tokens[1]) == "ON") ? 1.0f : 0.0f;
        } else {
            c.type = ControlCommand::Type::ToggleOverdub;
        }
        return enqueueAndOk(c);
    }

    // ---- STOP ----
    if (verb == "STOP") {
        ControlCommand c;
        c.type = ControlCommand::Type::GlobalStop;
        return enqueueAndOk(c);
    }

    // ---- STOPREC ----
    if (verb == "STOPREC") {
        ControlCommand c;
        c.type = ControlCommand::Type::StopRecording;
        return enqueueAndOk(c);
    }

    // ---- CLEAR [layer] ----
    if (verb == "CLEAR") {
        ControlCommand c;
        c.type = ControlCommand::Type::LayerClear;
        if (tokens.size() >= 2) {
            try {
                c.intParam = std::stoi(tokens[1]);
            } catch (...) {
                return "ERROR invalid layer index";
            }
        } else {
            c.intParam = -1; // active layer
        }
        return enqueueAndOk(c);
    }

    // ---- CLEARALL ----
    if (verb == "CLEARALL") {
        ControlCommand c;
        c.type = ControlCommand::Type::ClearAllLayers;
        return enqueueAndOk(c);
    }

    // ---- MODE <mode> ----
    if (verb == "MODE") {
        if (tokens.size() < 2) return "ERROR usage: MODE <firstLoop|freeMode|traditional|retrospective>";
        int mode = recordModeFromString(tokens[1]);
        if (mode < 0) return "ERROR unknown mode: " + tokens[1];
        ControlCommand c;
        c.type = ControlCommand::Type::SetRecordMode;
        c.intParam = mode;
        return enqueueAndOk(c);
    }

    // ---- VOLUME <0-1> ----
    if (verb == "VOLUME") {
        if (tokens.size() < 2) return "ERROR usage: VOLUME <0-1>";
        try {
            float vol = std::stof(tokens[1]);
            ControlCommand c;
            c.type = ControlCommand::Type::SetMasterVolume;
            c.floatParam = vol;
            return enqueueAndOk(c);
        } catch (...) {
            return "ERROR invalid volume";
        }
    }

    // ---- TARGETBPM <bpm> ----
    if (verb == "TARGETBPM") {
        if (tokens.size() < 2) return "ERROR usage: TARGETBPM <bpm>";
        try {
            float bpm = std::stof(tokens[1]);
            ControlCommand c;
            c.type = ControlCommand::Type::SetTargetBPM;
            c.floatParam = bpm;
            return enqueueAndOk(c);
        } catch (...) {
            return "ERROR invalid bpm";
        }
    }

    // ---- LAYER <index> [subcommand] ----
    if (verb == "LAYER") {
        if (tokens.size() < 2) return "ERROR usage: LAYER <index> [MUTE|SPEED|REVERSE|VOLUME|STOP|CLEAR]";

        int layerIdx = -1;
        try { layerIdx = std::stoi(tokens[1]); } catch (...) {
            return "ERROR invalid layer index";
        }
        if (layerIdx < 0 || layerIdx >= 4)
            return "ERROR layer index must be 0-3";

        // LAYER <index> with no subcommand = select active layer
        if (tokens.size() == 2) {
            ControlCommand c;
            c.type = ControlCommand::Type::SetActiveLayer;
            c.intParam = layerIdx;
            return enqueueAndOk(c);
        }

        auto sub = toUpper(tokens[2]);

        if (sub == "MUTE" && tokens.size() >= 4) {
            ControlCommand c;
            c.type = ControlCommand::Type::LayerMute;
            c.intParam = layerIdx;
            c.floatParam = (tokens[3] == "1" || toUpper(tokens[3]) == "TRUE") ? 1.0f : 0.0f;
            return enqueueAndOk(c);
        }

        if (sub == "SPEED" && tokens.size() >= 4) {
            try {
                ControlCommand c;
                c.type = ControlCommand::Type::LayerSpeed;
                c.intParam = layerIdx;
                c.floatParam = std::stof(tokens[3]);
                return enqueueAndOk(c);
            } catch (...) {
                return "ERROR invalid speed value";
            }
        }

        if (sub == "REVERSE" && tokens.size() >= 4) {
            ControlCommand c;
            c.type = ControlCommand::Type::LayerReverse;
            c.intParam = layerIdx;
            c.floatParam = (tokens[3] == "1" || toUpper(tokens[3]) == "TRUE") ? 1.0f : 0.0f;
            return enqueueAndOk(c);
        }

        if (sub == "VOLUME" && tokens.size() >= 4) {
            try {
                ControlCommand c;
                c.type = ControlCommand::Type::LayerVolume;
                c.intParam = layerIdx;
                c.floatParam = std::stof(tokens[3]);
                return enqueueAndOk(c);
            } catch (...) {
                return "ERROR invalid volume value";
            }
        }

        if (sub == "STOP") {
            ControlCommand c;
            c.type = ControlCommand::Type::LayerStop;
            c.intParam = layerIdx;
            return enqueueAndOk(c);
        }

        if (sub == "CLEAR") {
            ControlCommand c;
            c.type = ControlCommand::Type::LayerClear;
            c.intParam = layerIdx;
            return enqueueAndOk(c);
        }

        return "ERROR unknown layer command: " + tokens[2];
    }

    // ---- INJECT <filepath> ----
    if (verb == "INJECT") {
        if (tokens.size() < 2) return "ERROR usage: INJECT <filepath>";
        // Rejoin the rest in case path has spaces
        std::string filepath;
        for (size_t i = 1; i < tokens.size(); ++i) {
            if (i > 1) filepath += " ";
            filepath += tokens[i];
        }
        return loadFileForInjection(filepath);
    }

    // ---- INJECTION_STATUS ----
    if (verb == "INJECTION_STATUS") {
        bool active = injectionActive.load(std::memory_order_acquire);
        int pos = injectionReadPos.load(std::memory_order_relaxed);
        int total = 0;
        {
            std::lock_guard<std::mutex> lock(injectionMutex);
            total = injectionBuffer.totalSamples;
        }
        std::ostringstream o;
        o << "OK {";
        o << jsonBool("active", active) << ",";
        o << jsonNum("readPos", pos) << ",";
        o << jsonNum("totalSamples", total) << ",";
        o << jsonNum("progress", total > 0 ? (double)pos / total : 0.0);
        o << "}";
        return o.str();
    }

    return "ERROR unknown command: " + tokens[0];
}

// ============================================================================
// JSON builders - read from AtomicState (lock-free)
// ============================================================================

std::string ControlServer::buildStateJson() {
    auto& s = atomicState;
    std::ostringstream o;
    o << "{";
    o << jsonNum("tempo", s.tempo.load()) << ",";
    o << jsonNum("samplesPerBar", s.samplesPerBar.load()) << ",";
    o << jsonNum("captureSize", s.captureSize.load()) << ",";
    o << jsonNum("captureWritePos", s.captureWritePos.load()) << ",";
    o << jsonNum("captureLevel", s.captureLevel.load()) << ",";
    o << jsonBool("isRecording", s.isRecording.load()) << ",";
    o << jsonBool("overdubEnabled", s.overdubEnabled.load()) << ",";
    o << jsonStr("recordMode", recordModeToString(s.recordMode.load())) << ",";
    o << jsonNum("activeLayer", s.activeLayer.load()) << ",";
    o << jsonNum("masterVolume", s.masterVolume.load()) << ",";
    o << jsonNum("playTime", s.playTime.load()) << ",";
    o << jsonNum("commitCount", s.commitCount.load()) << ",";
    o << jsonNum("uptimeSeconds", s.uptimeSeconds.load()) << ",";

    o << "\"layers\":[";
    for (int i = 0; i < AtomicState::MAX_LAYERS; ++i) {
        auto& l = s.layers[i];
        if (i > 0) o << ",";
        o << "{";
        o << jsonNum("index", i) << ",";
        o << jsonStr("state", layerStateToString(l.state.load())) << ",";
        o << jsonNum("length", l.length.load()) << ",";
        o << jsonNum("playheadPos", l.playheadPos.load()) << ",";
        o << jsonNum("speed", l.speed.load()) << ",";
        o << jsonBool("reversed", l.reversed.load()) << ",";
        o << jsonNum("volume", l.volume.load()) << ",";
        o << jsonNum("numBars", l.numBars.load());
        o << "}";
    }
    o << "]}";
    return o.str();
}

std::string ControlServer::buildDiagnoseJson() {
    auto& s = atomicState;
    std::ostringstream o;
    o << "{";
    o << jsonNum("captureWritePos", s.captureWritePos.load()) << ",";
    o << jsonNum("captureSize", s.captureSize.load()) << ",";
    o << jsonNum("commandsProcessed", commandsProcessed.load()) << ",";
    o << jsonNum("eventsDropped", eventsDropped.load()) << ",";
    o << jsonStr("socketPath", socketPath) << ",";

    int numClients = 0;
    {
        std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(clientsMutex));
        numClients = (int)clientFds.size();
    }
    int numWatchers = 0;
    {
        std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(watchersMutex));
        numWatchers = (int)watcherFds.size();
    }

    o << jsonNum("connectedClients", numClients) << ",";
    o << jsonNum("connectedWatchers", numWatchers);
    o << "}";
    return o.str();
}

// ============================================================================
// Watcher management
// ============================================================================

void ControlServer::addWatcher(int fd) {
    std::lock_guard<std::mutex> lock(watchersMutex);
    watcherFds.push_back(fd);
}

void ControlServer::removeWatcher(int fd) {
    std::lock_guard<std::mutex> lock(watchersMutex);
    watcherFds.erase(std::remove(watcherFds.begin(), watcherFds.end(), fd), watcherFds.end());
}

void ControlServer::broadcastToWatchers(const std::string& msg) {
    std::lock_guard<std::mutex> lock(watchersMutex);
    auto it = watcherFds.begin();
    while (it != watcherFds.end()) {
        ssize_t n = ::write(*it, msg.c_str(), msg.size());
        if (n < 0) {
            // Dead watcher, remove
            ::close(*it);
            it = watcherFds.erase(it);
        } else {
            ++it;
        }
    }
}

void ControlServer::drainAndBroadcastEvents() {
    ControlEvent events[32];
    int count = eventRing.drain(events, 32);
    for (int i = 0; i < count; ++i) {
        std::string msg = "EVENT " + std::string(events[i].json, events[i].length) + "\n";
        broadcastToWatchers(msg);
    }
}

// ============================================================================
// Audio injection: load WAV on server thread, drain into CaptureBuffer from
// audio thread. Simulates mic input for autonomous testing.
// ============================================================================

std::string ControlServer::loadFileForInjection(const std::string& filepath) {
    // Don't allow overlapping injections
    if (injectionActive.load(std::memory_order_acquire))
        return "ERROR injection already in progress";

    juce::File file(filepath);
    if (!file.existsAsFile())
        return "ERROR file not found: " + filepath;

    // Use JUCE audio format manager to read WAV/AIFF/FLAC/etc
    juce::AudioFormatManager formatManager;
    formatManager.registerBasicFormats();

    std::unique_ptr<juce::AudioFormatReader> reader(
        formatManager.createReaderFor(file));

    if (!reader)
        return "ERROR cannot read audio file: " + filepath;

    int numSamples = (int)reader->lengthInSamples;
    int numChannels = (int)reader->numChannels;
    double fileSampleRate = reader->sampleRate;

    if (numSamples == 0)
        return "ERROR empty audio file";

    // Read the entire file into a JUCE AudioBuffer
    juce::AudioBuffer<float> fileBuffer(numChannels, numSamples);
    reader->read(&fileBuffer, 0, numSamples, 0, true, numChannels > 1);

    // Resample if needed (simple: just store at file rate, audio thread
    // will write at whatever rate it runs at — for testing this is fine,
    // the tempo inference will handle the actual duration)
    // TODO: proper resampling if file rate != plugin rate

    // Prepare injection buffer
    {
        std::lock_guard<std::mutex> lock(injectionMutex);
        injectionBuffer.samplesL.resize(numSamples);
        injectionBuffer.samplesR.resize(numSamples);
        injectionBuffer.totalSamples = numSamples;

        // Copy channel data
        const float* ch0 = fileBuffer.getReadPointer(0);
        std::memcpy(injectionBuffer.samplesL.data(), ch0, numSamples * sizeof(float));

        if (numChannels > 1) {
            const float* ch1 = fileBuffer.getReadPointer(1);
            std::memcpy(injectionBuffer.samplesR.data(), ch1, numSamples * sizeof(float));
        } else {
            // Mono: duplicate to both channels
            std::memcpy(injectionBuffer.samplesR.data(), ch0, numSamples * sizeof(float));
        }
    }

    // Activate: audio thread will start draining
    injectionReadPos.store(0, std::memory_order_relaxed);
    injectionActive.store(true, std::memory_order_release);

    char json[256];
    std::snprintf(json, sizeof(json),
        R"({"type":"injection_start","file":"%s","samples":%d,"sampleRate":%.0f,"channels":%d})",
        file.getFileName().toRawUTF8(), numSamples, fileSampleRate, numChannels);
    eventRing.push(json, (int)std::strlen(json));

    // Build response
    std::ostringstream o;
    o << "OK {";
    o << jsonNum("samples", numSamples) << ",";
    o << jsonNum("sampleRate", fileSampleRate) << ",";
    o << jsonNum("channels", numChannels) << ",";
    o << jsonNum("durationSeconds", numSamples / fileSampleRate);
    o << "}";
    return o.str();
}

int ControlServer::drainInjection(CaptureBuffer& capture, int maxSamples) {
    if (!injectionActive.load(std::memory_order_acquire))
        return 0;

    int pos = injectionReadPos.load(std::memory_order_relaxed);
    int total = injectionBuffer.totalSamples;
    int remaining = total - pos;

    if (remaining <= 0) {
        // Done injecting
        injectionActive.store(false, std::memory_order_release);

        char json[64];
        std::snprintf(json, sizeof(json), R"({"type":"injection_done"})");
        eventRing.push(json, (int)std::strlen(json));

        return 0;
    }

    int toWrite = std::min(maxSamples, remaining);

    for (int i = 0; i < toWrite; ++i) {
        capture.write(injectionBuffer.samplesL[pos + i], 0);
        capture.write(injectionBuffer.samplesR[pos + i], 1);
    }

    injectionReadPos.store(pos + toWrite, std::memory_order_relaxed);
    return toWrite;
}

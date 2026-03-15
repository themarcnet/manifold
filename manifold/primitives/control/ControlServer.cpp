#include "ControlServer.h"
#include "CommandParser.h"
#include "OSCEndpointRegistry.h"
#include "OSCQuery.h"
#include "OSCServer.h"
#include "../scripting/LuaEngine.h"
#include "../scripting/ScriptableProcessor.h"
#include "../dsp/CaptureBuffer.h"

#include <juce_audio_formats/juce_audio_formats.h>

#if !JUCE_WINDOWS
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include <signal.h>
#include <cerrno>
#include <cstdlib>
#include <cstdio>
#endif

#include <sstream>
#include <algorithm>
#include <chrono>
#include <filesystem>

#if JUCE_WINDOWS

ControlServer::ControlServer() {}

ControlServer::~ControlServer() {
    stop();
}

void ControlServer::start(ScriptableProcessor* processor) {
    owner = processor;
    running.store(true);
    socketPath.clear();
    DBG("ControlServer: Unix domain socket IPC is disabled on Windows builds.");
}

void ControlServer::stop() {
    running.store(false);
    owner = nullptr;
}

bool ControlServer::enqueueCommand(const ControlCommand& command) {
    std::lock_guard<std::mutex> lock(commandQueueWriteMutex);
    const bool ok = commandQueue.enqueue(command);
    if (ok)
        commandsProcessed.fetch_add(1, std::memory_order_relaxed);
    return ok;
}

void ControlServer::acceptLoop() {}

void ControlServer::clientLoop(int clientFd) {
    juce::ignoreUnused(clientFd);
}

std::string ControlServer::processCommand(const std::string& cmd) {
    juce::ignoreUnused(cmd);
    return "{\"ok\":false,\"error\":\"unix_socket_ipc_not_supported_on_windows\"}\n";
}

std::string ControlServer::buildStateJson() {
    return "{\"ok\":true,\"ipc\":\"disabled\",\"reason\":\"unix_socket_not_available_on_windows\"}\n";
}

std::string ControlServer::getStateJson() {
    return buildStateJson();
}

std::string ControlServer::getDiagnosticsJson() {
    return buildDiagnoseJson();
}

std::string ControlServer::buildDiagnoseJson() {
    return "{\"ok\":true,\"ipc\":\"disabled\",\"platform\":\"windows\"}\n";
}

void ControlServer::addWatcher(int fd) {
    juce::ignoreUnused(fd);
}

void ControlServer::removeWatcher(int fd) {
    juce::ignoreUnused(fd);
}

void ControlServer::broadcastToWatchers(const std::string& msg) {
    juce::ignoreUnused(msg);
}

void ControlServer::drainAndBroadcastEvents() {}

std::string ControlServer::loadFileForInjection(const std::string& filepath) {
    juce::ignoreUnused(filepath);
    return "{\"ok\":false,\"error\":\"audio_injection_not_supported_on_windows\"}\n";
}

int ControlServer::drainInjection(CaptureBuffer& capture, int maxSamples, float gain) {
    juce::ignoreUnused(capture, maxSamples, gain);
    return 0;
}

#else

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
        case 6: return "paused";
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

static void pruneStaleManifoldSockets() {
    namespace fs = std::filesystem;
    const pid_t selfPid = getpid();

    std::error_code ec;
    for (const auto& entry : fs::directory_iterator("/tmp", ec)) {
        if (ec) {
            break;
        }
        if (!entry.is_socket(ec)) {
            continue;
        }

        const std::string name = entry.path().filename().string();
        if (name.rfind("manifold_", 0) != 0) {
            continue;
        }
        if (name.size() <= 14 || name.substr(name.size() - 5) != ".sock") {
            continue;
        }

        const std::string pidStr = name.substr(9, name.size() - 14);
        char* end = nullptr;
        const long parsed = std::strtol(pidStr.c_str(), &end, 10);
        if (end == nullptr || *end != '\0' || parsed <= 0) {
            continue;
        }

        const pid_t pid = static_cast<pid_t>(parsed);
        if (pid == selfPid) {
            continue;
        }

        if (::kill(pid, 0) == 0) {
            continue;
        }
        if (errno != ESRCH) {
            continue;
        }

        std::error_code removeEc;
        fs::remove(entry.path(), removeEc);
    }
}

// ============================================================================
// ControlServer
// ============================================================================

ControlServer::ControlServer() {}

ControlServer::~ControlServer() {
    stop();
}

void ControlServer::start(ScriptableProcessor* processor) {
    if (running.load()) return;
    owner = processor;

    // Best-effort stale socket cleanup for crashed processes.
    pruneStaleManifoldSockets();

    // Build socket path: /tmp/manifold_<pid>.sock
    socketPath = "/tmp/manifold_" + std::to_string(getpid()) + ".sock";

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

            // Phase 4: dispose retired graph runtimes off the audio thread.
            // This keeps runtime swaps leak-free even in headless mode.
            if (owner != nullptr) {
                owner->drainRetiredGraphRuntimes();
            }

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
            ssize_t sent = ::send(clientFd, response.c_str(), response.size(), MSG_NOSIGNAL);
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
    const std::string trimmedCmd = trim(cmd);
    const std::string upperTrimmedCmd = toUpper(trimmedCmd);

    if (owner) {
        constexpr const char* kDspRunPrefix = "DSPRUN ";
        constexpr size_t kDspRunPrefixLen = 7;
        if (cmd.rfind(kDspRunPrefix, 0) == 0) {
            std::string script = cmd.substr(kDspRunPrefixLen);
            juce::String scriptText(script);
            scriptText = scriptText.replace("\\n", "\n");
            if (owner->loadDspScriptFromString(scriptText.toStdString(), "ipc:dsprun")) {
                return "OK";
            }
            return "ERROR " + owner->getDspScriptLastError();
        }
    }

    if (upperTrimmedCmd == "PERF RESET") {
        if (frameTimings != nullptr) {
            frameTimings->resetPeaks();
        }
        return "OK";
    }

    if (upperTrimmedCmd == "EVAL" || upperTrimmedCmd.rfind("EVAL ", 0) == 0) {
        if (luaEngine == nullptr) {
            return "ERROR no lua engine";
        }
        if (!luaEngine->isScriptLoaded()) {
            return "ERROR lua engine not ready";
        }

        const size_t separatorPos = cmd.find_first_of(" \t");
        std::string script = separatorPos == std::string::npos ? "" : cmd.substr(separatorPos + 1);
        juce::String scriptText(script);
        scriptText = scriptText.replace("\\n", "\n");

        auto request = luaEngine->queueEval(scriptText.toStdString());
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (!request->completed.load(std::memory_order_acquire)) {
            if (std::chrono::steady_clock::now() >= deadline) {
                return "ERROR eval timeout";
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }

        std::lock_guard<std::mutex> resultLock(request->resultMutex);
        if (request->isError) {
            return "ERROR " + request->result;
        }
        if (request->result.empty()) {
            return "OK";
        }
        return "OK " + request->result;
    }

    // Direct-value endpoints (commandType=None) are handled synchronously.
    // They must be declared in the endpoint registry and pass resolver
    // validation. Unknown paths are not accepted.
    if (owner && cmd.size() > 4) {
        std::istringstream iss(cmd);
        std::vector<std::string> tokens;
        std::string tok;
        while (iss >> tok) {
            tokens.push_back(tok);
        }

        if (tokens.size() >= 3 && toUpper(tokens[0]) == "SET") {
            const juce::String path(tokens[1]);

            EndpointResolver resolver(&owner->getEndpointRegistry());
            ResolvedEndpoint endpoint;
            if (resolver.resolve(path, endpoint) &&
                endpoint.commandType == ControlCommand::Type::None) {
                std::string rawValue = tokens[2];
                for (size_t i = 3; i < tokens.size(); ++i) {
                    rawValue += " ";
                    rawValue += tokens[i];
                }

                const juce::var input = CommandParser::parseCanonicalValueToken(rawValue);
                const auto validation = resolver.validateWrite(endpoint, input);
                if (!validation.accepted) {
                    return "ERROR invalid value for path: " + path.toStdString();
                }

                float normalized = 0.0f;
                const juce::var& value = validation.normalizedValue;
                if (value.isBool()) {
                    normalized = static_cast<bool>(value) ? 1.0f : 0.0f;
                } else if (value.isInt() || value.isInt64() || value.isDouble()) {
                    normalized = static_cast<float>(static_cast<double>(value));
                } else {
                    return "ERROR unsupported direct value type for path: " +
                           path.toStdString();
                }

                if (!owner->setParamByPath(path.toStdString(), normalized)) {
                    return "ERROR rejected direct endpoint write: " +
                           path.toStdString();
                }
                return "OK";
            }
        }
    }

    auto result = CommandParser::parse(
        cmd,
        owner ? &owner->getEndpointRegistry() : nullptr);

    if (!result.warningCode.empty()) {
        static std::atomic<int> parserWarnings{0};
        const int count = parserWarnings.fetch_add(1, std::memory_order_relaxed) + 1;
        if (count <= 5 || (count % 100) == 0) {
            DBG("ControlServer: " << result.warningCode << " (" << result.warningMessage
                << ", count=" << count << ")");
        }
    }

    switch (result.kind) {
        case ParseResult::Kind::Enqueue: {
            if (!enqueueCommand(result.command))
                return "ERROR queue full";
            return "OK";
        }

        case ParseResult::Kind::Query: {
            if (result.queryType == "STATE")    return "OK " + buildStateJson();
            if (result.queryType == "PING")     return "OK PONG";
            if (result.queryType == "DIAGNOSE") return "OK " + buildDiagnoseJson();
            if (result.queryType == "DIAGNOSTICS") return "OK " + buildDiagnoseJson();
            if (result.queryType == "GET") {
                if (!owner) {
                    return "ERROR no processor";
                }

                const juce::String payload =
                    owner->getOSCQueryServer().queryPathValue(
                        juce::String(result.queryPath));
                if (payload.startsWith("{\"error\"")) {
                    return "ERROR " + payload.toStdString();
                }
                return "OK " + payload.toStdString();
            }
            return "ERROR unknown query type";
        }

        case ParseResult::Kind::Watch:
            return "OK watching";

        case ParseResult::Kind::Inject:
            return loadFileForInjection(result.filepath);

        case ParseResult::Kind::InjectionStatus: {
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

        case ParseResult::Kind::UISwitch: {
            std::lock_guard<std::mutex> lock(uiSwitchRequest.mutex);
            uiSwitchRequest.path = result.filepath;
            uiSwitchRequest.pending.store(true, std::memory_order_release);
            return "OK UI switch queued";
        }

        case ParseResult::Kind::NoOpWarning:
            return "ERROR " + result.warningMessage;

        case ParseResult::Kind::Error:
            return "ERROR " + result.errorMessage;
    }

    return "ERROR internal";
}

// ============================================================================
// JSON builders - read from AtomicState (lock-free)
// ============================================================================

std::string ControlServer::buildStateJson() {
    auto& s = atomicState;
    static constexpr const char* kBehaviorBase = "/core/behavior";

    std::ostringstream o;
    o << "{";
    o << jsonNum("projectionVersion", 2) << ",";
    o << jsonNum("numVoices", AtomicState::MAX_LAYERS) << ",";
    o << jsonNum("captureWritePos", s.captureWritePos.load()) << ",";
    o << jsonNum("captureLevel", s.captureLevel.load()) << ",";
    o << jsonNum("playTime", s.playTime.load()) << ",";
    o << jsonNum("commitCount", s.commitCount.load()) << ",";
    o << jsonNum("uptimeSeconds", s.uptimeSeconds.load()) << ",";

    o << "\"params\":{";
    o << jsonNum(std::string(kBehaviorBase) + "/tempo", s.tempo.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/targetbpm", s.targetBPM.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/samplesPerBar", s.samplesPerBar.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/sampleRate", s.sampleRate.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/captureSize", s.captureSize.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/recording", s.isRecording.load() ? 1 : 0) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/overdub", s.overdubEnabled.load() ? 1 : 0) << ",";
    o << jsonStr(std::string(kBehaviorBase) + "/mode", recordModeToString(s.recordMode.load())) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/layer", s.activeLayer.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/volume", s.masterVolume.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/inputVolume", s.inputVolume.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/passthrough", s.passthroughEnabled.load() ? 1 : 0) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/forwardArmed", s.forwardArmed.load() ? 1 : 0) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/forwardBars", s.forwardBars.load()) << ",";
    o << jsonNum(std::string(kBehaviorBase) + "/graph/enabled", s.graphEnabled.load() ? 1 : 0);

    for (int i = 0; i < AtomicState::MAX_LAYERS; ++i) {
        auto& layer = s.layers[i];
        const std::string prefix = std::string(kBehaviorBase) + "/layer/" + std::to_string(i);
        const int stateValue = layer.state.load();
        const bool muted = stateValue == 4;

        o << "," << jsonNum(prefix + "/speed", layer.speed.load());
        o << "," << jsonNum(prefix + "/volume", layer.volume.load());
        o << "," << jsonNum(prefix + "/mute", muted ? 1 : 0);
        o << "," << jsonBool(prefix + "/reverse", layer.reversed.load());
        o << "," << jsonNum(prefix + "/length", layer.length.load());

        const int length = layer.length.load();
        const int position = layer.playheadPos.load();
        const float positionNorm =
            (length > 0) ? static_cast<float>(position) / static_cast<float>(length)
                         : 0.0f;
        o << "," << jsonNum(prefix + "/position", positionNorm);
        o << "," << jsonNum(prefix + "/bars", layer.numBars.load());
        o << "," << jsonStr(prefix + "/state", layerStateToString(stateValue));
    }
    o << "},";

    o << "\"voices\":[";
    for (int i = 0; i < AtomicState::MAX_LAYERS; ++i) {
        auto& layer = s.layers[i];
        if (i > 0) o << ",";

        const int length = layer.length.load();
        const int position = layer.playheadPos.load();
        const int stateValue = layer.state.load();
        const bool muted = stateValue == 4;
        const float positionNorm =
            (length > 0) ? static_cast<float>(position) / static_cast<float>(length)
                         : 0.0f;
        const float bars = layer.numBars.load();

        o << "{";
        o << jsonNum("id", i) << ",";
        o << jsonStr("path", std::string(kBehaviorBase) + "/layer/" + std::to_string(i)) << ",";
        o << jsonStr("state", layerStateToString(stateValue)) << ",";
        o << jsonNum("length", length) << ",";
        o << jsonNum("position", position) << ",";
        o << jsonNum("positionNorm", positionNorm) << ",";
        o << jsonNum("speed", layer.speed.load()) << ",";
        o << jsonBool("reversed", layer.reversed.load()) << ",";
        o << jsonNum("volume", layer.volume.load()) << ",";
        o << jsonNum("bars", bars) << ",";
        o << "\"params\":{";
        o << jsonNum("speed", layer.speed.load()) << ",";
        o << jsonNum("volume", layer.volume.load()) << ",";
        o << jsonNum("mute", muted ? 1 : 0) << ",";
        o << jsonNum("reverse", layer.reversed.load() ? 1 : 0) << ",";
        o << jsonNum("length", length) << ",";
        o << jsonNum("position", positionNorm) << ",";
        o << jsonNum("bars", bars) << ",";
        o << jsonStr("state", layerStateToString(stateValue));
        o << "}";
        o << "}";
    }
    o << "]}";
    return o.str();
}

std::string ControlServer::getStateJson() {
    return buildStateJson();
}

std::string ControlServer::getDiagnosticsJson() {
    return buildDiagnoseJson();
}

std::string ControlServer::buildDiagnoseJson() {
    auto& s = atomicState;
    const auto parserDiagnostics = CommandParser::getDiagnosticsSnapshot();
    std::ostringstream o;
    o << "{";
    o << jsonNum("captureWritePos", s.captureWritePos.load()) << ",";
    o << jsonNum("captureSize", s.captureSize.load()) << ",";
    o << jsonNum("commandsProcessed", commandsProcessed.load()) << ",";
    o << jsonNum("eventsDropped", eventsDropped.load()) << ",";
    o << jsonNum("warningsTotal", parserDiagnostics.warningsTotal) << ",";
    o << jsonNum("errorsTotal", parserDiagnostics.errorsTotal) << ",";
    o << jsonNum("warningPathUnknown", parserDiagnostics.warningPathUnknown) << ",";
    o << jsonNum("warningPathDeprecated", parserDiagnostics.warningPathDeprecated) << ",";
    o << jsonNum("warningAccessDenied", parserDiagnostics.warningAccessDenied) << ",";
    o << jsonNum("warningRangeClamped", parserDiagnostics.warningRangeClamped) << ",";
    o << jsonNum("warningCoerceLossy", parserDiagnostics.warningCoerceLossy) << ",";
    o << jsonNum("warningCoerceImpossibleNoop", parserDiagnostics.warningCoerceImpossibleNoop) << ",";
    o << jsonNum("legacySyntaxTotal", parserDiagnostics.legacySyntaxTotal) << ",";
    o << jsonNum("legacyVerbCommit", parserDiagnostics.legacyVerbCommit) << ",";
    o << jsonNum("legacyVerbForward", parserDiagnostics.legacyVerbForward) << ",";
    o << jsonNum("legacyVerbTempo", parserDiagnostics.legacyVerbTempo) << ",";
    o << jsonNum("legacyVerbRec", parserDiagnostics.legacyVerbRec) << ",";
    o << jsonNum("legacyVerbOverdub", parserDiagnostics.legacyVerbOverdub) << ",";
    o << jsonNum("legacyVerbStop", parserDiagnostics.legacyVerbStop) << ",";
    o << jsonNum("legacyVerbPlay", parserDiagnostics.legacyVerbPlay) << ",";
    o << jsonNum("legacyVerbPause", parserDiagnostics.legacyVerbPause) << ",";
    o << jsonNum("legacyVerbStopRec", parserDiagnostics.legacyVerbStopRec) << ",";
    o << jsonNum("legacyVerbClear", parserDiagnostics.legacyVerbClear) << ",";
    o << jsonNum("legacyVerbClearAll", parserDiagnostics.legacyVerbClearAll) << ",";
    o << jsonNum("legacyVerbMode", parserDiagnostics.legacyVerbMode) << ",";
    o << jsonNum("legacyVerbVolume", parserDiagnostics.legacyVerbVolume) << ",";
    o << jsonNum("legacyVerbTargetBpm", parserDiagnostics.legacyVerbTargetBpm) << ",";
    o << jsonNum("legacyVerbLayer", parserDiagnostics.legacyVerbLayer) << ",";
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

    if (frameTimings != nullptr) {
        o << ",\"frameTiming\":{";
        o << jsonNum("frameCount", frameTimings->frameCount.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("totalUs", frameTimings->total.currentUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("pushStateUs", frameTimings->pushState.currentUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("eventListenersUs", frameTimings->eventListeners.currentUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("uiUpdateUs", frameTimings->uiUpdate.currentUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("paintUs", frameTimings->paint.currentUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("peakTotalUs", frameTimings->total.peakUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("peakPushStateUs", frameTimings->pushState.peakUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("peakEventListenersUs", frameTimings->eventListeners.peakUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("peakUiUpdateUs", frameTimings->uiUpdate.peakUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("peakPaintUs", frameTimings->paint.peakUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("avgTotalUs", frameTimings->total.getAvgUs()) << ",";
        o << jsonNum("avgPushStateUs", frameTimings->pushState.getAvgUs()) << ",";
        o << jsonNum("avgEventListenersUs", frameTimings->eventListeners.getAvgUs()) << ",";
        o << jsonNum("avgUiUpdateUs", frameTimings->uiUpdate.getAvgUs()) << ",";
        o << jsonNum("avgPaintUs", frameTimings->paint.getAvgUs()) << ",";
        o << jsonNum("totalPaintAccumulatedUs", frameTimings->totalPaintAccumulatedUs.load(std::memory_order_relaxed));
        o << "}";

        o << ",\"imgui\":{";
        o << jsonBool("contextReady", frameTimings->imguiContextReady.load(std::memory_order_relaxed)) << ",";
        o << jsonBool("testWindowVisible", frameTimings->imguiTestWindowVisible.load(std::memory_order_relaxed)) << ",";
        o << jsonBool("wantCaptureMouse", frameTimings->imguiWantCaptureMouse.load(std::memory_order_relaxed)) << ",";
        o << jsonBool("wantCaptureKeyboard", frameTimings->imguiWantCaptureKeyboard.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("frameCount", frameTimings->imguiFrameCount.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("renderUs", frameTimings->imguiRenderUs.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("vertexCount", frameTimings->imguiVertexCount.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("indexCount", frameTimings->imguiIndexCount.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("buttonClicks", frameTimings->imguiButtonClicks.load(std::memory_order_relaxed)) << ",";
        o << jsonBool("documentLoaded", frameTimings->imguiDocumentLoaded.load(std::memory_order_relaxed)) << ",";
        o << jsonBool("documentDirty", frameTimings->imguiDocumentDirty.load(std::memory_order_relaxed)) << ",";
        o << jsonNum("documentLineCount", frameTimings->imguiDocumentLineCount.load(std::memory_order_relaxed));
        o << "}";
    }

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
        ssize_t n = ::send(*it, msg.c_str(), msg.size(), MSG_NOSIGNAL);
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

    char json[scripting::BufferConfig::MAX_JSON_PAYLOAD_SIZE];
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

int ControlServer::drainInjection(CaptureBuffer& capture, int maxSamples, float gain) {
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
        capture.write(injectionBuffer.samplesL[pos + i] * gain, 0);
        capture.write(injectionBuffer.samplesR[pos + i] * gain, 1);
    }

    injectionReadPos.store(pos + toWrite, std::memory_order_relaxed);
    return toWrite;
}

#endif

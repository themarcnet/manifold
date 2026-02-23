#pragma once

#include <juce_core/juce_core.h>
#include <atomic>
#include <array>
#include <string>
#include <thread>
#include <mutex>
#include <vector>
#include <functional>
#include <cstring>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <poll.h>
#include <fcntl.h>

// Forward declarations
class LooperProcessor;
class CaptureBuffer;

// ============================================================================
// Lock-free SPSC command queue: control thread -> audio thread
// ============================================================================

struct ControlCommand {
    enum class Type {
        None,
        Commit,         // commit N bars retrospectively
        ForwardCommit,  // wait N bars, then commit N bars retrospectively
        SetTempo,       // set tempo
        StartRecording, // start recording
        ToggleOverdub,  // toggle overdub mode on/off
        SetOverdubEnabled, // set overdub mode explicitly
        StopRecording,  // stop recording
        GlobalStop,     // stop all layer playback
        SetActiveLayer, // select layer
        LayerMute,      // mute/unmute layer
        LayerSpeed,     // set layer speed
        LayerReverse,   // set layer reverse
        LayerVolume,    // set layer volume
        LayerStop,      // stop playback without clearing
        LayerClear,     // clear layer
        ClearAllLayers, // clear all layers
        SetRecordMode,  // set record mode
        SetMasterVolume,// set master volume
        SetTargetBPM,   // set target BPM
    };

    Type type = Type::None;
    int intParam = 0;       // layer index, mode enum, etc.
    float floatParam = 0.0f; // bars, bpm, speed, volume, etc.
};

template <int Capacity>
class SPSCQueue {
public:
    bool enqueue(const ControlCommand& cmd) {
        int w = writeIdx.load(std::memory_order_relaxed);
        int next = (w + 1) % Capacity;
        if (next == readIdx.load(std::memory_order_acquire))
            return false; // full
        ring[w] = cmd;
        writeIdx.store(next, std::memory_order_release);
        return true;
    }

    bool dequeue(ControlCommand& cmd) {
        int r = readIdx.load(std::memory_order_relaxed);
        if (r == writeIdx.load(std::memory_order_acquire))
            return false; // empty
        cmd = ring[r];
        readIdx.store((r + 1) % Capacity, std::memory_order_release);
        return true;
    }

private:
    std::array<ControlCommand, Capacity> ring{};
    std::atomic<int> writeIdx{0};
    std::atomic<int> readIdx{0};
};

// ============================================================================
// Lock-free event ring: audio thread -> control thread (for broadcast)
// ============================================================================

struct ControlEvent {
    char json[512]; // pre-formatted JSON string
    int length = 0;
};

template <int Capacity>
class EventRing {
public:
    // Called from audio thread only
    void push(const char* jsonStr, int len) {
        int w = writeIdx.load(std::memory_order_relaxed);
        auto& slot = ring[w];
        int copyLen = (len < 511) ? len : 511;
        std::memcpy(slot.json, jsonStr, copyLen);
        slot.json[copyLen] = '\0';
        slot.length = copyLen;
        writeIdx.store((w + 1) % Capacity, std::memory_order_release);
    }

    // Called from server thread only. Returns number of events read.
    int drain(ControlEvent* out, int maxEvents) {
        int count = 0;
        while (count < maxEvents) {
            int r = readIdx.load(std::memory_order_relaxed);
            if (r == writeIdx.load(std::memory_order_acquire))
                break;
            out[count] = ring[r];
            readIdx.store((r + 1) % Capacity, std::memory_order_release);
            ++count;
        }
        return count;
    }

private:
    std::array<ControlEvent, Capacity> ring{};
    std::atomic<int> writeIdx{0};
    std::atomic<int> readIdx{0};
};

// ============================================================================
// Atomic state snapshot - updated each audio block by the processor
// ============================================================================

struct AtomicLayerState {
    std::atomic<int> state{0};        // LooperLayer::State enum as int
    std::atomic<int> length{0};       // buffer length in samples
    std::atomic<int> playheadPos{0};  // current position
    std::atomic<float> speed{1.0f};
    std::atomic<bool> reversed{false};
    std::atomic<float> volume{1.0f};
    std::atomic<float> numBars{0.0f};
};

struct AtomicState {
    static const int MAX_LAYERS = 4;

    std::atomic<float> tempo{120.0f};
    std::atomic<float> samplesPerBar{0.0f};
    std::atomic<int> captureSize{0};
    std::atomic<int> captureWritePos{0};
    std::atomic<float> captureLevel{0.0f};
    std::atomic<bool> isRecording{false};
    std::atomic<bool> overdubEnabled{false};
    std::atomic<int> recordMode{0};
    std::atomic<int> activeLayer{0};
    std::atomic<float> masterVolume{1.0f};
    std::atomic<double> playTime{0.0};
    std::atomic<int> commitCount{0};
    std::atomic<double> uptimeSeconds{0.0};

    AtomicLayerState layers[MAX_LAYERS];
};

// ============================================================================
// Audio injection buffer: server thread loads WAV, audio thread drains into
// CaptureBuffer as if it were live mic input.
// ============================================================================

struct InjectionBuffer {
    std::vector<float> samplesL;
    std::vector<float> samplesR;
    int totalSamples = 0;
};

// ============================================================================
// ControlServer - Unix socket IPC for observation and control
// ============================================================================

class ControlServer {
public:
    ControlServer();
    ~ControlServer();

    // Lifecycle - called from processor
    void start(LooperProcessor* processor);
    void stop();

    // Audio thread interface - all lock-free
    SPSCQueue<256>& getCommandQueue() { return commandQueue; }
    bool enqueueCommand(const ControlCommand& command);
    void pushEvent(const char* json, int len) { eventRing.push(json, len); }
    AtomicState& getAtomicState() { return atomicState; }

    // Audio injection: audio thread calls this each block to drain injected
    // audio into the CaptureBuffer. Returns number of samples injected.
    int drainInjection(CaptureBuffer& capture, int maxSamples);

    // Check if injection is in progress
    bool isInjecting() const { return injectionActive.load(std::memory_order_acquire); }

    // Get socket path (for logging/debugging)
    const std::string& getSocketPath() const { return socketPath; }

private:
    void acceptLoop();
    void clientLoop(int clientFd);
    std::string processCommand(const std::string& cmd);
    std::string buildStateJson();
    std::string buildDiagnoseJson();

    void addWatcher(int fd);
    void removeWatcher(int fd);
    void broadcastToWatchers(const std::string& msg);
    void drainAndBroadcastEvents();

    // Load a WAV file and prepare injection buffer (called from server thread)
    std::string loadFileForInjection(const std::string& filepath);

    LooperProcessor* owner = nullptr;
    std::string socketPath;
    int serverFd = -1;
    std::atomic<bool> running{false};

    std::thread acceptThread;
    std::thread broadcastThread;

    // Client management
    std::mutex clientsMutex;
    std::vector<int> clientFds;

    // Watcher (EVENT stream) management
    std::mutex watchersMutex;
    std::vector<int> watcherFds;

    // Lock-free queues
    std::mutex commandQueueWriteMutex;
    SPSCQueue<256> commandQueue;
    EventRing<256> eventRing;
    AtomicState atomicState;

    // Audio injection state
    // Server thread writes a new InjectionBuffer then sets injectionActive.
    // Audio thread reads from it and advances injectionReadPos.
    std::mutex injectionMutex;  // only held by server thread during load
    InjectionBuffer injectionBuffer;
    std::atomic<int> injectionReadPos{0};
    std::atomic<bool> injectionActive{false};

    // Stats
    std::atomic<int> commandsProcessed{0};
    std::atomic<int> eventsDropped{0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ControlServer)
};

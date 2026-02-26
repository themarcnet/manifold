#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>
#include <atomic>
#include <vector>
#include <mutex>
#include "../primitives/scripting/ScriptableProcessor.h"
#include "../primitives/scripting/PrimitiveGraph.h"
#include "../primitives/dsp/CaptureBuffer.h"
#include "../primitives/dsp/TempoInference.h"
#include "../primitives/dsp/Quantizer.h"
#include "../primitives/control/ControlServer.h"
#include "../primitives/control/OSCServer.h"
#include "../primitives/control/OSCEndpointRegistry.h"
#include "../primitives/control/OSCQuery.h"
#include "LooperLayer.h"

// Forward declaration - actual header provided by another agent
namespace dsp_primitives {
class GraphRuntime;
}

// Simple fixed-capacity SPSC queue for pointers (audio thread -> message thread)
// NOTE: Must not be in an anonymous namespace because this type is part of the
// LooperProcessor class layout and needs to be identical across translation units.
template <typename T, int Capacity>
class SPSCQueuePtr {
public:
  bool enqueue(T* ptr) noexcept {
    const int w = writeIdx.load(std::memory_order_relaxed);
    const int next = (w + 1) % Capacity;
    if (next == readIdx.load(std::memory_order_acquire))
      return false; // full
    ring[static_cast<size_t>(w)] = ptr;
    writeIdx.store(next, std::memory_order_release);
    return true;
  }

  bool dequeue(T*& out) noexcept {
    const int r = readIdx.load(std::memory_order_relaxed);
    if (r == writeIdx.load(std::memory_order_acquire))
      return false; // empty
    out = ring[static_cast<size_t>(r)];
    readIdx.store((r + 1) % Capacity, std::memory_order_release);
    return true;
  }

  bool isEmpty() const noexcept {
    return writeIdx.load(std::memory_order_acquire) == readIdx.load(std::memory_order_acquire);
  }

private:
  std::array<T*, static_cast<size_t>(Capacity)> ring{};
  std::atomic<int> writeIdx{0};
  std::atomic<int> readIdx{0};
};

enum class RecordMode {
    FirstLoop,
    FreeMode,
    Traditional,
    Retrospective
};

class LooperProcessor : public juce::AudioProcessor, public ScriptableProcessor {
public:
    static const int MAX_LAYERS = 4;
    static const int CAPTURE_SECONDS = 32;
    
    LooperProcessor();
    ~LooperProcessor() override;
    
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) override;
    
    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    
    const juce::String getName() const override { return "Looper"; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    
    void getStateInformation(juce::MemoryBlock&) override {}
    void setStateInformation(const void*, int) override {}
    
    CaptureBuffer& getCaptureBuffer() { return captureBuffer; }
    LooperLayer& getLayer(int index) { return layers[index]; }
    int getNumLayers() const override { return MAX_LAYERS; }
    bool getLayerSnapshot(int index, ScriptableLayerSnapshot& out) const override;
    int getCaptureSize() const override { return captureBuffer.getSize(); }
    bool computeLayerPeaks(int layerIndex, int numBuckets,
                           std::vector<float>& outPeaks) const override;
    bool computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                             std::vector<float>& outPeaks) const override;
    int getActiveLayerIndex() const override { return activeLayerIndex; }
    void setActiveLayer(int index);
    
    void startRecording();
    void startOverdub();
    void setOverdubEnabled(bool enabled);
    void stopRecording();
    void commitRetrospective(float numBars);
    void scheduleForwardCommit(float numBars);
    bool isForwardCommitArmed() const override { return forwardCommitArmed.load(std::memory_order_relaxed); }
    float getForwardCommitBars() const override { return forwardCommitBars.load(std::memory_order_relaxed); }
    
    RecordMode getRecordMode() const { return recordMode; }
    int getRecordModeIndex() const override { return static_cast<int>(recordMode); }
    void setRecordMode(RecordMode mode) { recordMode = mode; }
    
    bool isRecording() const override { return isCurrentlyRecording; }
    bool isOverdubEnabled() const override { return overdubEnabled; }
    bool isPlaying() const;
    
    float getTempo() const override { return tempo; }
    void setTempo(float bpm);
    
    float getTargetBPM() const override { return targetBPM; }
    void setTargetBPM(float bpm) { targetBPM = bpm; }
    
    bool getInferTempo() const { return inferTempo; }
    void setInferTempo(bool infer) { inferTempo = infer; }
    
    float getMasterVolume() const override { return masterVolume; }
    void setMasterVolume(float vol) { masterVolume = vol; }
    
    float getInputVolume() const { return inputVolume; }
    void setInputVolume(float vol) { inputVolume = vol; }
    
    bool isPassthroughEnabled() const { return passthroughEnabled; }
    void setPassthroughEnabled(bool enabled) { passthroughEnabled = enabled; }
    
    float getSamplesPerBar() const override;
    double getSampleRate() const override { return currentSampleRate; }
    int getCommitCount() const override { return commitCount; }
    
    // Control server access
    ControlServer& getControlServer() { return controlServer; }
    OSCServer& getOSCServer() override { return oscServer; }
    OSCEndpointRegistry& getEndpointRegistry() override { return endpointRegistry; }
    OSCQueryServer& getOSCQueryServer() override { return oscQueryServer; }
    
    // DSP primitive graph access
    std::shared_ptr<dsp_primitives::PrimitiveGraph> getPrimitiveGraph() { return primitiveGraph; }
    bool isGraphProcessingEnabled() const { return graphProcessingEnabled; }
    void setGraphProcessingEnabled(bool enabled);
    bool loadDspScript(const juce::File &scriptFile);
    bool loadDspScriptFromString(const std::string &luaCode,
                                 const std::string &sourceName = "ui_live");
    bool reloadDspScript();
    bool isDspScriptLoaded() const;
    const std::string &getDspScriptLastError() const;
    bool postControlCommandPayload(const ControlCommand &command);
    bool postControlCommand(ControlCommand::Type type, int intParam = 0, float floatParam = 0.0f) override;

    // Generic path-based parameter access
    bool setParamByPath(const std::string &path, float value) override;
    float getParamByPath(const std::string &path) const override;
    bool hasEndpoint(const std::string &path) const override;
    
    // UI switching (thread-safe) - called by editor to check for UI switch
    std::string getAndClearPendingUISwitch();
    
    // Spectrum analysis for visualization
    static constexpr int NUM_SPECTRUM_BANDS = 32;
    std::array<float, NUM_SPECTRUM_BANDS> getSpectrumData() const override;

    // ============================================================================
    // Phase 4: Graph Runtime Swap (message-thread API)
    // ============================================================================
    // Publish a new RT-safe graph runtime for the audio thread to consume.
    // This must be callable from UI/CLI threads.
    void requestGraphRuntimeSwap(std::unique_ptr<dsp_primitives::GraphRuntime> runtime);

    // Dispose of retired graph runtimes off the audio thread.
    void drainRetiredGraphRuntimes();
     
private:
    CaptureBuffer captureBuffer;
    LooperLayer layers[MAX_LAYERS];
    int activeLayerIndex = 0;
    
    TempoInference tempoInference;
    Quantizer quantizer;
    
    RecordMode recordMode = RecordMode::FirstLoop;
    bool isCurrentlyRecording = false;
    bool overdubEnabled = false;
    double recordStartTime = 0.0;
    double playTime = 0.0;

    // Forward/traditional capture: arm now, capture retrospectively after waiting numBars.
    std::atomic<bool> forwardCommitArmed{false};
    std::atomic<float> forwardCommitBars{0.0f};
    std::atomic<int> forwardCommitLayer{0};
    std::atomic<double> forwardCommitArmPlayTime{0.0};
    
    float tempo = 120.0f;
    float targetBPM = 120.0f;
    bool inferTempo = true;
    float masterVolume = 1.0f;
    float inputVolume = 1.0f;
    bool passthroughEnabled = true;
    double currentSampleRate = 44100.0;
    
    // Control server for IPC observation/control
    ControlServer controlServer;
    
    // OSC server for network control
    OSCServer oscServer;
    
    // Endpoint registry (single source of truth for all OSC endpoints)
    OSCEndpointRegistry endpointRegistry;
    
    // OSCQuery HTTP server
    OSCQueryServer oscQueryServer;
    
    int commitCount = 0;

    // Scratch buffers reused across processBlock to avoid per-block allocation.
    std::vector<float> layerMixL;
    std::vector<float> layerMixR;
    std::vector<float> tempLayerL;
    std::vector<float> tempLayerR;

    // Host transport info for sync.
    bool hostTransportPlaying = false;
    double hostTimelineSamples = 0.0;
    
    // DSP primitive graph processing
    bool graphProcessingEnabled = false;

    // Phase 4: preallocated buffers for graph processing.
    // Allocated in prepareToPlay; never reallocated on audio thread.
    int preparedMaxBlockSize = 0;
    juce::AudioBuffer<float> fadeOldBuffer;
    juce::AudioBuffer<float> fadeNewBuffer;

    void processFirstLoopStop();
    void processFreeModeStop();
    void processTraditionalStop();
    bool shouldOverdubLayer(int layerIndex) const;

    void commitRetrospectiveNow(float numBars, int layerIndex, bool overdub);
    void maybeFireForwardCommit();
    void updateTransportState();
    void syncLayersToTransportIfNeeded();
    void ensureScratchSize(int numSamples);
    
    // Process pending commands from control server (called from audio thread)
    void processControlCommands();
    
    // Update atomic state snapshot (called from audio thread each block)
    void updateAtomicState(const juce::AudioBuffer<float>& buffer);
    
    // Push an event to control server (called from audio thread)
    void pushEvent(const char* json);
    
    // FFT analysis for spectrum visualization
    static constexpr int FFT_ORDER = 10;  // 1024 samples
    static constexpr int FFT_SIZE = 1 << FFT_ORDER;
    
    std::unique_ptr<juce::dsp::FFT> fft;
    std::vector<float> fftInput;
    std::vector<float> fftOutput;
    int fftInputIndex = 0;
    
    // Lock-free spectrum data for UI
    std::array<std::atomic<float>, NUM_SPECTRUM_BANDS> spectrumBands{};
    std::atomic<float> graphInputRms{0.0f};
    std::atomic<float> graphWetRms{0.0f};
    std::atomic<float> graphMixedRms{0.0f};
    std::atomic<int> graphNodeCount{0};
    std::atomic<int> graphRouteCount{0};
    
    void processFFT(const float* inputData, int numSamples);
    void updateSpectrumBands();
    
    // DSP primitive graph for scripting
    std::shared_ptr<dsp_primitives::PrimitiveGraph> primitiveGraph;
    std::unique_ptr<class DSPPluginScriptHost> dspScriptHost;
    
    // ============================================================================
    // Phase 4: Graph Runtime Swap (RT-safe, lock-free, 30ms crossfade)
    // ============================================================================
    
    // Audio-thread state for runtime swapping
    // The pending runtime atomics are published from message thread, consumed by audio thread
    std::atomic<dsp_primitives::GraphRuntime*> pendingRuntime{nullptr};
    
    // Active runtime and fade state
    dsp_primitives::GraphRuntime* activeRuntime = nullptr;
    dsp_primitives::GraphRuntime* fadingFromRuntime = nullptr;
    dsp_primitives::GraphRuntime* fadingToRuntime = nullptr;
    
    // Fade state
    int fadePosition = 0;           // Current position in fade (samples)
    int fadeTotalSamples = 0;       // Total samples for 30ms fade
    juce::AudioBuffer<float> graphDryBuffer;
    
    // (legacy scratch vectors removed; crossfade uses fadeOldBuffer/fadeNewBuffer)
    
    // SPSC queue for retiring old runtimes (audio thread enqueues, message thread dequeues)
    static constexpr int RETIRE_QUEUE_CAPACITY = 64;
    SPSCQueuePtr<dsp_primitives::GraphRuntime, RETIRE_QUEUE_CAPACITY> retireQueue;

    // If retireQueue is full, keep one pending retire pointer and retry next block.
    // Audio thread only.
    dsp_primitives::GraphRuntime* pendingRetireRuntime = nullptr;

    // Serializes drainRetiredGraphRuntimes() across non-audio threads.
    std::mutex retiredRuntimeDrainMutex;
    
    // Helper to begin a fade from old to new runtime
    void beginFade(dsp_primitives::GraphRuntime* from, dsp_primitives::GraphRuntime* to);
    
    // Process graph with active runtime (called from processBlock when enabled)
    void processGraphRuntime(juce::AudioBuffer<float>& buffer);
    
    // Check and handle pending runtime swap (called from audio thread)
    void checkGraphRuntimeSwap();
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LooperProcessor)
};

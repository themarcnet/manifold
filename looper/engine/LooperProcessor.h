#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>
#include <atomic>
#include <vector>
#include "../primitives/scripting/ScriptableProcessor.h"
#include "../primitives/dsp/CaptureBuffer.h"
#include "../primitives/dsp/TempoInference.h"
#include "../primitives/dsp/Quantizer.h"
#include "../primitives/control/ControlServer.h"
#include "../primitives/control/OSCServer.h"
#include "../primitives/control/OSCEndpointRegistry.h"
#include "../primitives/control/OSCQuery.h"
#include "LooperLayer.h"

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
    
    float getSamplesPerBar() const override;
    double getSampleRate() const override { return currentSampleRate; }
    int getCommitCount() const override { return commitCount; }
    
    // Control server access
    ControlServer& getControlServer() { return controlServer; }
    OSCServer& getOSCServer() override { return oscServer; }
    OSCEndpointRegistry& getEndpointRegistry() override { return endpointRegistry; }
    OSCQueryServer& getOSCQueryServer() override { return oscQueryServer; }
    bool postControlCommandPayload(const ControlCommand &command);
    bool postControlCommand(ControlCommand::Type type, int intParam = 0, float floatParam = 0.0f) override;
    
    // UI switching (thread-safe) - called by editor to check for UI switch
    std::string getAndClearPendingUISwitch();
    
    // Spectrum analysis for visualization
    static constexpr int NUM_SPECTRUM_BANDS = 32;
    std::array<float, NUM_SPECTRUM_BANDS> getSpectrumData() const override;
    
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
    
    void processFFT(const float* inputData, int numSamples);
    void updateSpectrumBands();
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LooperProcessor)
};

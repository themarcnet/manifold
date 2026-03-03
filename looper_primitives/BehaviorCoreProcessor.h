#pragma once

#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_basics/juce_audio_basics.h>

#include "../looper/primitives/control/ControlServer.h"
#include "../looper/primitives/control/OSCEndpointRegistry.h"
#include "../looper/primitives/control/OSCQuery.h"
#include "../looper/primitives/control/OSCServer.h"
#include "../looper/primitives/dsp/CaptureBuffer.h"
#include "../looper/primitives/scripting/PrimitiveGraph.h"
#include "../looper/primitives/scripting/ScriptableProcessor.h"
#include "../looper/primitives/sync/LinkSync.h"

class DSPPluginScriptHost;

namespace dsp_primitives {
class GraphRuntime;
}

template <typename T, int Capacity>
class SPSCQueuePtr {
public:
    bool enqueue(T* ptr) noexcept {
        const int w = writeIdx.load(std::memory_order_relaxed);
        const int next = (w + 1) % Capacity;
        if (next == readIdx.load(std::memory_order_acquire)) {
            return false;
        }
        ring[static_cast<size_t>(w)] = ptr;
        writeIdx.store(next, std::memory_order_release);
        return true;
    }

    bool dequeue(T*& out) noexcept {
        const int r = readIdx.load(std::memory_order_relaxed);
        if (r == writeIdx.load(std::memory_order_acquire)) {
            return false;
        }
        out = ring[static_cast<size_t>(r)];
        readIdx.store((r + 1) % Capacity, std::memory_order_release);
        return true;
    }

private:
    std::array<T*, static_cast<size_t>(Capacity)> ring{};
    std::atomic<int> writeIdx{0};
    std::atomic<int> readIdx{0};
};

class BehaviorCoreProcessor : public juce::AudioProcessor,
                              public ScriptableProcessor {
public:
    static constexpr int MAX_LAYERS = 4;
    static constexpr int CAPTURE_SECONDS = 32;

    BehaviorCoreProcessor();
    ~BehaviorCoreProcessor() override;

    using juce::AudioProcessor::processBlock;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>& buffer,
                      juce::MidiBuffer& midiMessages) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return JucePlugin_Name; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}

    void getStateInformation(juce::MemoryBlock&) override;
    void setStateInformation(const void*, int) override;

    // ScriptableProcessor
    bool postControlCommandPayload(const ControlCommand& command) override;
    bool postControlCommand(ControlCommand::Type type, int intParam = 0,
                            float floatParam = 0.0f) override;

    ControlServer& getControlServer() override { return controlServer; }
    OSCServer& getOSCServer() override { return oscServer; }
    OSCEndpointRegistry& getEndpointRegistry() override {
        return endpointRegistry;
    }
    OSCQueryServer& getOSCQueryServer() override { return oscQueryServer; }

    std::shared_ptr<dsp_primitives::PrimitiveGraph> getPrimitiveGraph() override {
        return primitiveGraph;
    }
    void setGraphProcessingEnabled(bool enabled) override {
        graphProcessingEnabled.store(enabled, std::memory_order_relaxed);
        controlServer.getAtomicState().graphEnabled.store(enabled,
                                                          std::memory_order_relaxed);
    }
    bool isGraphProcessingEnabled() const override {
        return graphProcessingEnabled.load(std::memory_order_relaxed);
    }
    int getGraphBlockSize() const override {
        return currentBlockSize.load(std::memory_order_relaxed);
    }
    int getGraphOutputChannels() const override {
        return 2;
    }
    void requestGraphRuntimeSwap(
        std::unique_ptr<dsp_primitives::GraphRuntime> runtime) override;

    bool loadDspScript(const juce::File&) override;
    bool loadDspScript(const juce::File&, const std::string& slot) override;
    bool loadDspScriptFromString(const std::string&,
                                 const std::string&) override;
    bool loadDspScriptFromString(const std::string&, const std::string&,
                                 const std::string& slot) override;
    bool reloadDspScript() override;
    bool reloadDspScript(const std::string& slot) override;
    bool unloadDspSlot(const std::string& slot) override;
    bool isDspScriptLoaded() const override;
    bool isDspSlotLoaded(const std::string& slot) const override;
    const std::string& getDspScriptLastError() const override;
    void drainRetiredGraphRuntimes() override;

    bool setParamByPath(const std::string& path, float value) override;
    float getParamByPath(const std::string& path) const override;
    bool hasEndpoint(const std::string& path) const override;

    int getNumLayers() const override { return MAX_LAYERS; }
    bool getLayerSnapshot(int index,
                          ScriptableLayerSnapshot& out) const override;
    int getCaptureSize() const override;
    bool computeLayerPeaks(int layerIndex, int numBuckets,
                           std::vector<float>& outPeaks) const override;
    bool computeLayerPeaksForPath(const std::string& pathBase,
                                  int layerIndex, int numBuckets,
                                  std::vector<float>& outPeaks) const override;
    bool computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                             std::vector<float>& outPeaks) const override;

    float getTempo() const override;
    float getTargetBPM() const override;
    float getSamplesPerBar() const override;
    double getSampleRate() const override;
    double getPlayTimeSamples() const override {
        return playTimeSamples.load(std::memory_order_relaxed);
    }
    float getMasterVolume() const override;
    float getInputVolume() const override;
    bool isPassthroughEnabled() const override;
    bool isRecording() const override;
    bool isOverdubEnabled() const override;
    int getActiveLayerIndex() const override;
    bool isForwardCommitArmed() const override;
    float getForwardCommitBars() const override;
    int getRecordModeIndex() const override;
    int getCommitCount() const override;
    std::array<float, 32> getSpectrumData() const override;

    // Ableton Link integration
    bool isLinkEnabled() const override;
    void setLinkEnabled(bool enabled) override;
    bool isLinkTempoSyncEnabled() const override;
    void setLinkTempoSyncEnabled(bool enabled) override;
    bool isLinkStartStopSyncEnabled() const override;
    void setLinkStartStopSyncEnabled(bool enabled) override;
    int getLinkNumPeers() const override;
    bool isLinkPlaying() const override;
    double getLinkBeat() const override;
    double getLinkPhase() const override;
    void requestLinkTempo(double bpm) override;
    void requestLinkStart() override;
    void requestLinkStop() override;
    void processLinkPendingRequests() override;

    // ========================================================================
    // IStateSerializer implementation (Looper-specific state schema)
    // ========================================================================
    void serializeStateToLua(sol::state& lua) const override;
    std::string serializeStateToJson() const override;
    std::vector<StateField> getStateSchema() const override;
    std::string getValueAtPath(const std::string& path) const override;
    bool hasPathChanged(const std::string& path) const override;
    void updateChangeCache() override;
    void subscribeToPath(const std::string& path, StateChangeCallback callback) override;
    void unsubscribeFromPath(const std::string& path) override;
    void clearSubscriptions() override;
    void processPendingChanges() override;

    std::string getAndClearPendingUISwitch();

public:
    // Destroy deferred DSP slot hosts (safe boundary, not inside Lua call stacks)
    void drainPendingSlotDestroy();

private:
    bool applyParamPath(const std::string& path, float value);
    void applyControlCommand(const ControlCommand& cmd);
    void checkGraphRuntimeSwap();
    void processControlCommands();
    void initialiseAtomicState(double sampleRate);
    void scheduleForwardCommitIfNeeded();

    static bool extractLayerParam(const std::string& path, int& layerIndex,
                                  std::string& paramSuffix);

    std::atomic<double> currentSampleRate{44100.0};
    std::atomic<int> currentBlockSize{512};
    std::atomic<double> playTimeSamples{0.0};
    std::atomic<bool> graphProcessingEnabled{false};

    CaptureBuffer captureBuffer;
    juce::AudioBuffer<float> graphWetBuffer;

    bool forwardScheduled = false;
    double forwardFireAtSample = 0.0;
    float forwardScheduledBars = 0.0f;

    std::atomic<dsp_primitives::GraphRuntime*> pendingRuntime{nullptr};
    dsp_primitives::GraphRuntime* activeRuntime = nullptr;
    dsp_primitives::GraphRuntime* pendingRetireRuntime = nullptr;
    static constexpr int RETIRE_QUEUE_CAPACITY = 64;
    SPSCQueuePtr<dsp_primitives::GraphRuntime, RETIRE_QUEUE_CAPACITY> retireQueue;
    std::mutex retiredRuntimeDrainMutex;

    std::string dspScriptLastError =
        "DSP script host is not wired in BehaviorCore bootstrap yet";

    std::shared_ptr<dsp_primitives::PrimitiveGraph> primitiveGraph;
    std::unique_ptr<DSPPluginScriptHost> dspScriptHost; // "default" slot (legacy compat)
    std::unordered_map<std::string, std::unique_ptr<DSPPluginScriptHost>> dspSlots;
    // Hosts moved here for deferred destruction (can't destroy sol::state from Lua callback)
    std::vector<std::unique_ptr<DSPPluginScriptHost>> pendingSlotDestroy;
    DSPPluginScriptHost& getOrCreateSlot(const std::string& slot);

    ControlServer controlServer;
    OSCServer oscServer;
    OSCEndpointRegistry endpointRegistry;
    OSCQueryServer oscQueryServer;

    LinkSync linkSync;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BehaviorCoreProcessor)
};

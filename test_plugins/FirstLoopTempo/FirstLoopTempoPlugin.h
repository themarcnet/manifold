#pragma once

#include "../../looper/primitives/scripting/ScriptableProcessor.h"
#include "../../looper/primitives/control/OSCServer.h"
#include "../../looper/primitives/control/OSCEndpointRegistry.h"
#include "../../looper/primitives/control/OSCQuery.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <sol/sol.hpp>
#include <atomic>
#include <chrono>

class FirstLoopTempoPlugin : public ScriptableProcessor {
public:
    FirstLoopTempoPlugin();
    ~FirstLoopTempoPlugin() override = default;

    // =========================================================================
    // ScriptableProcessor (core functionality)
    // =========================================================================
    bool postControlCommandPayload(const ControlCommand& command) override;
    bool postControlCommand(ControlCommand::Type type, int intParam = 0,
                           float floatParam = 0.0f) override;

    ControlServer& getControlServer() override { return controlServer_; }
    OSCServer& getOSCServer() override { return oscServer_; }
    OSCEndpointRegistry& getEndpointRegistry() override { return endpointRegistry_; }
    OSCQueryServer& getOSCQueryServer() override { return oscQueryServer_; }

    // VST Parameter exposure
    bool setParamByPath(const std::string& path, float value) override;
    float getParamByPath(const std::string& path) const override;
    bool hasEndpoint(const std::string& path) const override;

    // Minimal layer support (0 layers, just tempo detection)
    int getNumLayers() const override { return 0; }
    bool getLayerSnapshot(int index, ScriptableLayerSnapshot& out) const override;
    int getCaptureSize() const override { return 0; }
    bool computeLayerPeaks(int layerIndex, int numBuckets,
                          std::vector<float>& outPeaks) const override;
    bool computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                            std::vector<float>& outPeaks) const override;

    // State accessors
    float getTempo() const override { return detectedTempo_.load(); }
    float getTargetBPM() const override { return targetBPM_.load(); }
    float getSamplesPerBar() const override;
    double getSampleRate() const override { return 44100.0; }
    double getPlayTimeSamples() const override { return 0.0; }
    float getMasterVolume() const override { return 1.0f; }
    float getInputVolume() const override { return 1.0f; }
    bool isPassthroughEnabled() const override { return false; }
    bool isRecording() const override { return isDetecting_.load(); }
    bool isOverdubEnabled() const override { return false; }
    int getActiveLayerIndex() const override { return 0; }
    bool isForwardCommitArmed() const override { return false; }
    float getForwardCommitBars() const override { return 0.0f; }
    int getRecordModeIndex() const override { return 0; } // firstLoop mode
    int getCommitCount() const override { return commitCount_.load(); }
    std::array<float, 32> getSpectrumData() const override;

    // =========================================================================
    // IStateSerializer - Custom minimal state
    // =========================================================================
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

    // =========================================================================
    // Ableton Link (enable for tempo sync)
    // =========================================================================
    bool isLinkEnabled() const override { return linkEnabled_.load(); }
    void setLinkEnabled(bool enabled) override;
    bool isLinkTempoSyncEnabled() const override { return linkTempoSync_.load(); }
    void setLinkTempoSyncEnabled(bool enabled) override { linkTempoSync_.store(enabled); }
    bool isLinkStartStopSyncEnabled() const override { return false; }
    void setLinkStartStopSyncEnabled(bool /*enabled*/) override {}
    int getLinkNumPeers() const override;
    bool isLinkPlaying() const override;
    double getLinkBeat() const override;
    double getLinkPhase() const override;
    void requestLinkTempo(double bpm) override;
    void requestLinkStart() override {}
    void requestLinkStop() override {}
    void processLinkPendingRequests() override;

    // =========================================================================
    // First Loop Detection
    // =========================================================================
    void startDetection();
    void stopDetection();
    void setTargetBPM(float bpm);

    struct DetectionResult {
        float tempo = 120.0f;
        float bars = 2.0f;
        float durationSeconds = 0.0f;
    };
    DetectionResult getLastResult() const { return lastResult_; }

private:
    DetectionResult inferTempoAndBars(float durationSeconds);

    ControlServer controlServer_;
    OSCServer oscServer_;
    OSCEndpointRegistry endpointRegistry_;
    OSCQueryServer oscQueryServer_;

    // First loop state
    std::atomic<float> detectedTempo_{120.0f};
    std::atomic<float> targetBPM_{120.0f};
    std::atomic<float> detectedBars_{2.0f};
    std::atomic<bool> isDetecting_{false};
    std::atomic<int> commitCount_{0};
    DetectionResult lastResult_;

    std::chrono::steady_clock::time_point detectionStart_;

    // Link state
    std::atomic<bool> linkEnabled_{false};
    std::atomic<bool> linkTempoSync_{true};
    std::unique_ptr<class LinkSync> linkSync_;

    static constexpr std::array<float, 9> kAllowedBars = {
        0.0625f, 0.125f, 0.25f, 0.5f, 1.0f, 2.0f, 4.0f, 8.0f, 16.0f
    };
};

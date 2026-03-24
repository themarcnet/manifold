#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "dsp/core/nodes/PartialData.h"
#include "dsp/core/nodes/PitchDetector.h"
#include "dsp/core/nodes/SampleAnalysis.h"
#include "dsp/core/nodes/TemporalPartialData.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <vector>
#include <cstdint>

namespace dsp_primitives {

class SampleRegionPlaybackNode : public IPrimitiveNode,
                                 public std::enable_shared_from_this<SampleRegionPlaybackNode> {
public:
    explicit SampleRegionPlaybackNode(int numChannels = 2);
    ~SampleRegionPlaybackNode() override;

    const char* getNodeType() const override { return "SampleRegionPlayback"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setLoopLength(int samples);
    int getLoopLength() const;
    void setSpeed(float speed);
    float getSpeed() const;
    void play();
    void pause();
    void stop();
    void trigger();
    bool isPlaying() const;
    void seekNormalized(float normalized);
    float getNormalizedPosition() const;

    void setPlayStart(float normalized);
    float getPlayStart() const;
    void setLoopStart(float normalized);
    float getLoopStart() const;
    void setLoopEnd(float normalized);
    float getLoopEnd() const;
    void setCrossfade(float normalized);
    float getCrossfade() const;

    void setUnison(int voices);
    int getUnison() const;
    void setDetune(float cents);
    float getDetune() const;
    void setSpread(float amount);
    float getSpread() const;

    bool computePeaks(int numBuckets, std::vector<float>& outPeaks) const;
    std::vector<float> getPeaks(int numBuckets) const;
    SampleAnalysis analyzeSample() const;
    SampleAnalysis getLastAnalysis() const;
    PartialData extractPartials() const;
    PartialData getLastPartials() const;
    TemporalPartialData extractTemporalPartials(int maxPartials = PartialData::kMaxPartials,
                                                 int windowSize = 2048,
                                                 int hopSize = 1024,
                                                 int maxFrames = 128) const;
    TemporalPartialData getLastTemporalPartials() const;
    void requestAsyncAnalysis(int maxPartials = PartialData::kMaxPartials,
                              int windowSize = 2048,
                              int hopSize = 1024,
                              int maxFrames = 128);
    bool isAsyncAnalysisPending() const;
    void publishAsyncAnalysisResult(std::uint64_t generation,
                                    const SampleAnalysis& analysis,
                                    const PartialData& partials,
                                    const TemporalPartialData& temporal);
    SampleAnalysisResult analyzeRootKey() const;
    void clearLoop();
    void copyFromCaptureBuffer(const juce::AudioBuffer<float>& captureBuffer,
                               int captureSize,
                               int captureStartOffset,
                               int numSamples,
                               bool overdub);

private:
    static constexpr int kMaxUnisonVoices = 8;

    struct RegionState {
        int sampleLength = 1;
        int playStart = 0;
        int loopStart = 0;
        int loopEnd = 1; // exclusive
        int loopWindow = 1;
        int crossfadeSamples = 0;
    };

    static double clampPosition(double position, int sampleLength);
    static float normalizedUnisonOffset(int voiceIndex, int voiceCount);
    RegionState computeRegionState() const;
    float readSample(const juce::AudioBuffer<float>& buffer, int channel, double position) const;
    void applyPendingControlChanges(const RegionState& region, int activeUnison);

    int numChannels_ = 2;
    double sampleRate_ = 44100.0;
    int maxLoopSamples_ = 1;
    juce::AudioBuffer<float> loopBufferA_;
    juce::AudioBuffer<float> loopBufferB_;
    std::atomic<int> activeLoopBufferIndex_{0};

    std::atomic<int> loopLength_{0};
    std::atomic<float> speed_{1.0f};
    std::atomic<bool> playing_{false};

    std::atomic<float> playStartNorm_{0.0f};
    std::atomic<float> loopStartNorm_{0.0f};
    std::atomic<float> loopEndNorm_{1.0f};
    std::atomic<float> crossfadeNorm_{0.0f};
    std::atomic<int> unisonVoices_{1};
    std::atomic<float> detuneCents_{0.0f};
    std::atomic<float> stereoSpread_{0.0f};

    std::atomic<int> seekRequest_{-1};
    std::atomic<bool> triggerRequest_{false};
    std::atomic<int> lastPosition_{0};

    float currentSpeed_ = 1.0f;
    float currentDetuneCents_ = 0.0f;
    float currentSpread_ = 0.0f;
    float speedSmoothingCoeff_ = 1.0f;
    float detuneSmoothingCoeff_ = 1.0f;
    float spreadSmoothingCoeff_ = 1.0f;
    float unisonVoiceSmoothingCoeff_ = 1.0f;

    mutable std::mutex analysisMutex_;
    mutable SampleAnalysis lastAnalysis_;
    mutable PartialData lastPartials_;
    mutable TemporalPartialData lastTemporalPartials_;
    std::atomic<std::uint64_t> analysisRequestedGeneration_{0};
    std::atomic<std::uint64_t> analysisCompletedGeneration_{0};
    std::atomic<bool> asyncAnalysisPending_{false};

    double readPositions_[kMaxUnisonVoices] = {0.0};
    bool firstPassStates_[kMaxUnisonVoices] = {true};
    float unisonVoiceGains_[kMaxUnisonVoices] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};
    int lastRequestedUnison_ = 1;
};

} // namespace dsp_primitives

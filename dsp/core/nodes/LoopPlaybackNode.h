#pragma once

#include "dsp/core/graph/PrimitiveNode.h"

#include <atomic>
#include <memory>
#include <vector>

namespace dsp_primitives {

class LoopPlaybackNode : public IPrimitiveNode, public std::enable_shared_from_this<LoopPlaybackNode> {
public:
    enum class OverdubLengthPolicy {
        LegacyRepeat = 0,
        CommitLengthWins = 1,
    };

    explicit LoopPlaybackNode(int numChannels = 2);

    const char* getNodeType() const override { return "LoopPlayback"; }
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
    void setReversed(bool reversed);
    bool isReversed() const;
    void play();
    void pause();
    void stop();
    bool isPlaying() const;
    void seekNormalized(float normalized);
    float getNormalizedPosition() const;
    bool computePeaks(int numBuckets, std::vector<float>& outPeaks) const;
    void clearLoop();
    void copyFromCaptureBuffer(const juce::AudioBuffer<float>& captureBuffer,
                               int captureSize,
                               int captureStartOffset,
                               int numSamples,
                               bool overdub,
                               OverdubLengthPolicy overdubLengthPolicy =
                                   OverdubLengthPolicy::LegacyRepeat);

private:
    int numChannels_ = 2;
    double sampleRate_ = 44100.0;
    int maxLoopSamples_ = 1;
    juce::AudioBuffer<float> loopBufferA_;
    juce::AudioBuffer<float> loopBufferB_;
    std::atomic<int> activeLoopBufferIndex_{0};
    double readPosition_ = 0.0;

    std::atomic<int> loopLength_{44100};
    std::atomic<float> speed_{1.0f};
    std::atomic<bool> reversed_{false};
    std::atomic<bool> playing_{true};
    std::atomic<int> seekRequest_{-1};
    std::atomic<int> lastPosition_{0};

    int seekCrossfadeSamples_ = 64;
    int seekCrossfadeRemaining_ = 0;
    int seekCrossfadeTotal_ = 0;
    double seekCrossfadeSourcePosition_ = 0.0;
};

} // namespace dsp_primitives

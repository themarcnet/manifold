#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class MultitapDelayNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<MultitapDelayNode> {
public:
    MultitapDelayNode();

    const char* getNodeType() const override { return "MultitapDelay"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setTapCount(int count) { targetTapCount_.store(juce::jlimit(1, 8, count), std::memory_order_release); }
    void setTapTime(int index, float ms);
    void setTapGain(int index, float gain);
    void setTapPan(int index, float pan);

    void setFeedback(float feedback) { targetFeedback_.store(juce::jlimit(0.0f, 0.95f, feedback), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    int getTapCount() const { return targetTapCount_.load(std::memory_order_acquire); }
    float getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    float readDelay(int channel, float delaySamples) const;

    static constexpr int kMaxTaps = 8;

    std::atomic<int> targetTapCount_{4};
    std::array<std::atomic<float>, kMaxTaps> targetTapTimeMs_{};
    std::array<std::atomic<float>, kMaxTaps> targetTapGain_{};
    std::array<std::atomic<float>, kMaxTaps> targetTapPan_{};

    std::atomic<float> targetFeedback_{0.3f};
    std::atomic<float> targetMix_{0.5f};

    float currentFeedback_ = 0.3f;
    float currentMix_ = 0.5f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> buffer_;
    int bufferSize_ = 0;
    int writeIndex_ = 0;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

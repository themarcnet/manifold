#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class ReverseDelayNode : public IPrimitiveNode,
                         public std::enable_shared_from_this<ReverseDelayNode> {
public:
    ReverseDelayNode();

    const char* getNodeType() const override { return "ReverseDelay"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setTime(float ms) { targetTimeMs_.store(juce::jlimit(50.0f, 2000.0f, ms), std::memory_order_release); }
    void setWindow(float ms) { targetWindowMs_.store(juce::jlimit(20.0f, 400.0f, ms), std::memory_order_release); }
    void setFeedback(float feedback) { targetFeedback_.store(juce::jlimit(0.0f, 0.95f, feedback), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getTime() const { return targetTimeMs_.load(std::memory_order_acquire); }
    float getWindow() const { return targetWindowMs_.load(std::memory_order_acquire); }
    float getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    static float triangular(float t);

    std::atomic<float> targetTimeMs_{420.0f};
    std::atomic<float> targetWindowMs_{120.0f};
    std::atomic<float> targetFeedback_{0.35f};
    std::atomic<float> targetMix_{0.5f};

    float currentTimeMs_ = 420.0f;
    float currentWindowMs_ = 120.0f;
    float currentFeedback_ = 0.35f;
    float currentMix_ = 0.5f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> delayBuffer_;
    int bufferSize_ = 0;
    int writeIndex_ = 0;

    std::array<float, 2> readPos_{{0.0f, 0.0f}};
    std::array<int, 2> segmentSamplesRemaining_{{0, 0}};

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

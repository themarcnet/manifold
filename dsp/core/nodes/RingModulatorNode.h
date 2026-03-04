#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class RingModulatorNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<RingModulatorNode> {
public:
    RingModulatorNode();

    const char* getNodeType() const override { return "RingModulator"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setFrequency(float hz) { targetFrequencyHz_.store(juce::jlimit(0.1f, 8000.0f, hz), std::memory_order_release); }
    void setDepth(float depth) { targetDepth_.store(juce::jlimit(0.0f, 1.0f, depth), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }
    void setSpread(float degrees) { targetSpreadDegrees_.store(juce::jlimit(0.0f, 180.0f, degrees), std::memory_order_release); }

    float getFrequency() const { return targetFrequencyHz_.load(std::memory_order_acquire); }
    float getDepth() const { return targetDepth_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getSpread() const { return targetSpreadDegrees_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetFrequencyHz_{180.0f};
    std::atomic<float> targetDepth_{1.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<float> targetSpreadDegrees_{0.0f};

    float currentFrequencyHz_ = 180.0f;
    float currentDepth_ = 1.0f;
    float currentMix_ = 1.0f;
    float currentSpreadDegrees_ = 0.0f;
    float smooth_ = 1.0f;

    float lfoPhase_ = 0.0f;
    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

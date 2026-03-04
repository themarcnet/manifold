#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class BitCrusherNode : public IPrimitiveNode,
                       public std::enable_shared_from_this<BitCrusherNode> {
public:
    BitCrusherNode();

    const char* getNodeType() const override { return "BitCrusher"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setBits(float bits) { targetBits_.store(juce::jlimit(2.0f, 16.0f, bits), std::memory_order_release); }
    void setRateReduction(float factor) { targetRateReduction_.store(juce::jlimit(1.0f, 64.0f, factor), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }
    void setOutput(float gain) { targetOutput_.store(juce::jlimit(0.0f, 2.0f, gain), std::memory_order_release); }

    float getBits() const { return targetBits_.load(std::memory_order_acquire); }
    float getRateReduction() const { return targetRateReduction_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getOutput() const { return targetOutput_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetBits_{8.0f};
    std::atomic<float> targetRateReduction_{4.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<float> targetOutput_{0.8f};

    float currentBits_ = 8.0f;
    float currentRateReduction_ = 4.0f;
    float currentMix_ = 1.0f;
    float currentOutput_ = 0.8f;
    float smooth_ = 1.0f;

    std::array<float, 2> heldSample_{{0.0f, 0.0f}};
    std::array<float, 2> holdCounter_{{0.0f, 0.0f}};

    bool prepared_ = false;
};

} // namespace dsp_primitives

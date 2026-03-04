#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class TransientShaperNode : public IPrimitiveNode,
                            public std::enable_shared_from_this<TransientShaperNode> {
public:
    TransientShaperNode();

    const char* getNodeType() const override { return "TransientShaper"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setAttack(float amount) { targetAttack_.store(juce::jlimit(-1.0f, 1.0f, amount), std::memory_order_release); }
    void setSustain(float amount) { targetSustain_.store(juce::jlimit(-1.0f, 1.0f, amount), std::memory_order_release); }
    void setSensitivity(float sensitivity) { targetSensitivity_.store(juce::jlimit(0.1f, 4.0f, sensitivity), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getAttack() const { return targetAttack_.load(std::memory_order_acquire); }
    float getSustain() const { return targetSustain_.load(std::memory_order_acquire); }
    float getSensitivity() const { return targetSensitivity_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getTransient() const { return transientMeter_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetAttack_{0.5f};
    std::atomic<float> targetSustain_{0.0f};
    std::atomic<float> targetSensitivity_{1.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<float> transientMeter_{0.0f};

    float currentAttack_ = 0.5f;
    float currentSustain_ = 0.0f;
    float currentSensitivity_ = 1.0f;
    float currentMix_ = 1.0f;

    float smooth_ = 1.0f;

    float fastAttackCoeff_ = 0.1f;
    float fastReleaseCoeff_ = 0.02f;
    float slowAttackCoeff_ = 0.01f;
    float slowReleaseCoeff_ = 0.002f;

    std::array<float, 2> fastEnv_{{0.0f, 0.0f}};
    std::array<float, 2> slowEnv_{{0.0f, 0.0f}};

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

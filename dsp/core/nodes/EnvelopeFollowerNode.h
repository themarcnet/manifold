#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class EnvelopeFollowerNode : public IPrimitiveNode,
                             public std::enable_shared_from_this<EnvelopeFollowerNode> {
public:
    EnvelopeFollowerNode();

    const char* getNodeType() const override { return "EnvelopeFollower"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setAttack(float ms) { targetAttackMs_.store(juce::jlimit(0.1f, 200.0f, ms), std::memory_order_release); }
    void setRelease(float ms) { targetReleaseMs_.store(juce::jlimit(1.0f, 2000.0f, ms), std::memory_order_release); }
    void setSensitivity(float scale) { targetSensitivity_.store(juce::jlimit(0.1f, 8.0f, scale), std::memory_order_release); }
    void setHighpass(float hz) { targetHighpassHz_.store(juce::jlimit(20.0f, 2000.0f, hz), std::memory_order_release); }

    float getAttack() const { return targetAttackMs_.load(std::memory_order_acquire); }
    float getRelease() const { return targetReleaseMs_.load(std::memory_order_acquire); }
    float getSensitivity() const { return targetSensitivity_.load(std::memory_order_acquire); }
    float getHighpass() const { return targetHighpassHz_.load(std::memory_order_acquire); }
    float getEnvelope() const { return envelopeOut_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetAttackMs_{10.0f};
    std::atomic<float> targetReleaseMs_{120.0f};
    std::atomic<float> targetSensitivity_{1.0f};
    std::atomic<float> targetHighpassHz_{80.0f};
    std::atomic<float> envelopeOut_{0.0f};

    float currentAttackMs_ = 10.0f;
    float currentReleaseMs_ = 120.0f;
    float currentSensitivity_ = 1.0f;
    float currentHighpassHz_ = 80.0f;
    float smooth_ = 1.0f;

    std::array<float, 2> hpState_{{0.0f, 0.0f}};
    std::array<float, 2> hpInput_{{0.0f, 0.0f}};
    float envelope_ = 0.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

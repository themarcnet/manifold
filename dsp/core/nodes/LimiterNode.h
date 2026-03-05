#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class LimiterNode : public IPrimitiveNode,
                    public std::enable_shared_from_this<LimiterNode> {
public:
    LimiterNode();

    const char* getNodeType() const override { return "Limiter"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setThreshold(float db) { targetThresholdDb_.store(juce::jlimit(-24.0f, 0.0f, db), std::memory_order_release); }
    void setRelease(float ms) { targetReleaseMs_.store(juce::jlimit(1.0f, 500.0f, ms), std::memory_order_release); }
    void setMakeup(float db) { targetMakeupDb_.store(juce::jlimit(0.0f, 18.0f, db), std::memory_order_release); }
    void setSoftClip(float amount) { targetSoftClip_.store(juce::jlimit(0.0f, 1.0f, amount), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getThreshold() const { return targetThresholdDb_.load(std::memory_order_acquire); }
    float getRelease() const { return targetReleaseMs_.load(std::memory_order_acquire); }
    float getMakeup() const { return targetMakeupDb_.load(std::memory_order_acquire); }
    float getSoftClip() const { return targetSoftClip_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getGainReduction() const { return gainReductionDb_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetThresholdDb_{-1.0f};
    std::atomic<float> targetReleaseMs_{60.0f};
    std::atomic<float> targetMakeupDb_{0.0f};
    std::atomic<float> targetSoftClip_{0.2f};
    std::atomic<float> targetMix_{1.0f};

    std::atomic<float> gainReductionDb_{0.0f};

    float thresholdDb_ = -1.0f;
    float releaseMs_ = 60.0f;
    float makeupDb_ = 0.0f;
    float softClip_ = 0.2f;
    float mix_ = 1.0f;
    float smooth_ = 1.0f;

    float gain_ = 1.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class StereoWidenerNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<StereoWidenerNode> {
public:
    StereoWidenerNode();

    const char* getNodeType() const override { return "StereoWidener"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setWidth(float width) { targetWidth_.store(juce::jlimit(0.0f, 2.0f, width), std::memory_order_release); }
    void setMonoLowFreq(float freq) { targetMonoLowFreq_.store(juce::jlimit(20.0f, 500.0f, freq), std::memory_order_release); }
    void setMonoLowEnable(bool enabled) { monoLowEnable_.store(enabled, std::memory_order_release); }

    float getWidth() const { return targetWidth_.load(std::memory_order_acquire); }
    float getMonoLowFreq() const { return targetMonoLowFreq_.load(std::memory_order_acquire); }
    bool getMonoLowEnable() const { return monoLowEnable_.load(std::memory_order_acquire); }
    float getCorrelation() const { return correlation_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetWidth_{1.0f};
    std::atomic<float> targetMonoLowFreq_{120.0f};
    std::atomic<bool> monoLowEnable_{true};
    std::atomic<float> correlation_{0.0f};

    float currentWidth_ = 1.0f;
    float currentMonoLowFreq_ = 120.0f;

    float widthSmooth_ = 1.0f;
    float freqSmooth_ = 1.0f;

    float lowL_ = 0.0f;
    float lowR_ = 0.0f;
    float corrNum_ = 0.0f;
    float corrDenL_ = 0.0f;
    float corrDenR_ = 0.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

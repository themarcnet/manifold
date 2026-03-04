#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class DistortionNode : public IPrimitiveNode, public std::enable_shared_from_this<DistortionNode> {
public:
    DistortionNode();

    const char* getNodeType() const override { return "Distortion"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setDrive(float d) { targetDrive_.store(juce::jlimit(1.0f, 30.0f, d), std::memory_order_release); }
    void setMix(float m) { targetMix_.store(juce::jlimit(0.0f, 1.0f, m), std::memory_order_release); }
    void setOutput(float g) { targetOutput_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }

    float getDrive() const { return targetDrive_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getOutput() const { return targetOutput_.load(std::memory_order_acquire); }

private:
    float smoothingCoeff_ = 1.0f;

    std::atomic<float> targetDrive_{4.0f};
    std::atomic<float> targetMix_{0.7f};
    std::atomic<float> targetOutput_{0.8f};

    float drive_ = 4.0f;
    float mix_ = 0.7f;
    float output_ = 0.8f;
};

} // namespace dsp_primitives

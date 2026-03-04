#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>
#include <vector>

namespace dsp_primitives {

class ReverbNode : public IPrimitiveNode, public std::enable_shared_from_this<ReverbNode> {
public:
    ReverbNode();

    const char* getNodeType() const override { return "Reverb"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setRoomSize(float value) { targetRoomSize_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setDamping(float value) { targetDamping_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setWetLevel(float value) { targetWetLevel_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setDryLevel(float value) { targetDryLevel_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setWidth(float value) { targetWidth_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }

    float getRoomSize() const { return targetRoomSize_.load(std::memory_order_acquire); }
    float getDamping() const { return targetDamping_.load(std::memory_order_acquire); }
    float getWetLevel() const { return targetWetLevel_.load(std::memory_order_acquire); }
    float getDryLevel() const { return targetDryLevel_.load(std::memory_order_acquire); }
    float getWidth() const { return targetWidth_.load(std::memory_order_acquire); }

private:
    juce::Reverb reverb_;
    juce::Reverb::Parameters params_;

    double sampleRate_ = 44100.0;
    float smoothingTimeSeconds_ = 0.04f;

    std::atomic<float> targetRoomSize_{0.5f};
    std::atomic<float> targetDamping_{0.5f};
    std::atomic<float> targetWetLevel_{0.33f};
    std::atomic<float> targetDryLevel_{0.4f};
    std::atomic<float> targetWidth_{1.0f};

    std::vector<float> left_;
    std::vector<float> right_;
};

} // namespace dsp_primitives

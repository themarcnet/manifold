#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class ShimmerNode : public IPrimitiveNode,
                    public std::enable_shared_from_this<ShimmerNode> {
public:
    ShimmerNode();

    const char* getNodeType() const override { return "Shimmer"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setSize(float size) { targetSize_.store(juce::jlimit(0.0f, 1.0f, size), std::memory_order_release); }
    void setPitch(float semitones) { targetPitchSemitones_.store(juce::jlimit(-12.0f, 12.0f, semitones), std::memory_order_release); }
    void setFeedback(float feedback) { targetFeedback_.store(juce::jlimit(0.0f, 0.99f, feedback), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }
    void setModulation(float modulation) { targetModulation_.store(juce::jlimit(0.0f, 1.0f, modulation), std::memory_order_release); }
    void setFilter(float cutoffHz) { targetFilterHz_.store(juce::jlimit(100.0f, 12000.0f, cutoffHz), std::memory_order_release); }

    float getSize() const { return targetSize_.load(std::memory_order_acquire); }
    float getPitch() const { return targetPitchSemitones_.load(std::memory_order_acquire); }
    float getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getModulation() const { return targetModulation_.load(std::memory_order_acquire); }
    float getFilter() const { return targetFilterHz_.load(std::memory_order_acquire); }

private:
    float readDelay(int channel, float pos) const;

    std::atomic<float> targetSize_{0.6f};
    std::atomic<float> targetPitchSemitones_{12.0f};
    std::atomic<float> targetFeedback_{0.65f};
    std::atomic<float> targetMix_{0.45f};
    std::atomic<float> targetModulation_{0.25f};
    std::atomic<float> targetFilterHz_{6000.0f};

    float currentSize_ = 0.6f;
    float currentPitchSemitones_ = 12.0f;
    float currentFeedback_ = 0.65f;
    float currentMix_ = 0.45f;
    float currentModulation_ = 0.25f;
    float currentFilterHz_ = 6000.0f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> buffer_;
    int bufferSize_ = 0;
    int writeIndex_ = 0;

    std::array<float, 2> readPos_{{0.0f, 0.0f}};
    std::array<float, 2> filterState_{{0.0f, 0.0f}};
    float lfoPhase_ = 0.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

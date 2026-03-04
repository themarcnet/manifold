#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class PhaserNode : public IPrimitiveNode,
                   public std::enable_shared_from_this<PhaserNode> {
public:
    PhaserNode();

    const char* getNodeType() const override { return "Phaser"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setRate(float hz) { targetRateHz_.store(juce::jlimit(0.1f, 10.0f, hz), std::memory_order_release); }
    void setDepth(float depth) { targetDepth_.store(juce::jlimit(0.0f, 1.0f, depth), std::memory_order_release); }
    void setStages(int stages) {
        const int s = stages >= 9 ? 12 : 6;
        targetStages_.store(s, std::memory_order_release);
    }
    void setFeedback(float feedback) { targetFeedback_.store(juce::jlimit(-0.95f, 0.95f, feedback), std::memory_order_release); }
    void setSpread(float degrees) { targetSpreadDegrees_.store(juce::jlimit(0.0f, 180.0f, degrees), std::memory_order_release); }

    float getRate() const { return targetRateHz_.load(std::memory_order_acquire); }
    float getDepth() const { return targetDepth_.load(std::memory_order_acquire); }
    int getStages() const { return targetStages_.load(std::memory_order_acquire); }
    float getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
    float getSpread() const { return targetSpreadDegrees_.load(std::memory_order_acquire); }

private:
    static constexpr int kMaxStages = 12;

    float allpassProcess(int channel, int stage, float in, float a);

    std::atomic<float> targetRateHz_{0.4f};
    std::atomic<float> targetDepth_{0.7f};
    std::atomic<int> targetStages_{6};
    std::atomic<float> targetFeedback_{0.2f};
    std::atomic<float> targetSpreadDegrees_{90.0f};

    float currentRateHz_ = 0.4f;
    float currentDepth_ = 0.7f;
    float currentFeedback_ = 0.2f;
    float currentSpreadDegrees_ = 90.0f;

    float smooth_ = 1.0f;

    std::array<std::array<float, kMaxStages>, 2> z1_{};
    std::array<float, 2> feedbackState_{{0.0f, 0.0f}};
    float lfoPhase_ = 0.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

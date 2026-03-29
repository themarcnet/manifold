#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class PitchShifterNode : public IPrimitiveNode,
                         public std::enable_shared_from_this<PitchShifterNode> {
public:
    PitchShifterNode();

    const char* getNodeType() const override { return "PitchShifter"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setPitch(float semitones) { targetPitchSemitones_.store(juce::jlimit(-24.0f, 24.0f, semitones), std::memory_order_release); }
    void setWindow(float ms) { targetWindowMs_.store(juce::jlimit(20.0f, 200.0f, ms), std::memory_order_release); }
    void setFeedback(float feedback) { targetFeedback_.store(juce::jlimit(0.0f, 0.95f, feedback), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getPitch() const { return targetPitchSemitones_.load(std::memory_order_acquire); }
    float getWindow() const { return targetWindowMs_.load(std::memory_order_acquire); }
    float getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    struct HeadState {
        float readPos = 0.0f;
        float age = 0.0f;
    };

    float readDelay(int channel, float pos) const;
    static float triangularWindow(float t);

    std::atomic<float> targetPitchSemitones_{0.0f};
    std::atomic<float> targetWindowMs_{80.0f};
    std::atomic<float> targetFeedback_{0.0f};
    std::atomic<float> targetMix_{1.0f};

    float currentPitchSemitones_ = 0.0f;
    float currentWindowMs_ = 80.0f;
    float currentFeedback_ = 0.0f;
    float currentMix_ = 1.0f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> delayBuffer_;
    int delayBufferSize_ = 0;
    int writeIndex_ = 0;

    std::array<std::array<HeadState, 2>, 2> heads_{};

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
    bool dormantBypass_ = false;
};

} // namespace dsp_primitives

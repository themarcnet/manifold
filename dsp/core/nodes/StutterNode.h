#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class StutterNode : public IPrimitiveNode,
                    public std::enable_shared_from_this<StutterNode> {
public:
    StutterNode();

    const char* getNodeType() const override { return "Stutter"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setLength(float beats) { targetLengthBeats_.store(juce::jlimit(0.125f, 8.0f, beats), std::memory_order_release); }
    void setGate(float gate) { targetGate_.store(juce::jlimit(0.0f, 1.0f, gate), std::memory_order_release); }
    void setFilterDecay(float value) { targetFilterDecay_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setPitchDecay(float value) { targetPitchDecay_.store(juce::jlimit(0.0f, 1.0f, value), std::memory_order_release); }
    void setProbability(float p) { targetProbability_.store(juce::jlimit(0.0f, 1.0f, p), std::memory_order_release); }
    void setPattern(float mask) { targetPatternMask_.store(static_cast<int>(mask), std::memory_order_release); }
    void setTempo(float bpm) { tempoBpm_.store(juce::jlimit(20.0f, 300.0f, bpm), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getLength() const { return targetLengthBeats_.load(std::memory_order_acquire); }
    float getGate() const { return targetGate_.load(std::memory_order_acquire); }
    float getFilterDecay() const { return targetFilterDecay_.load(std::memory_order_acquire); }
    float getPitchDecay() const { return targetPitchDecay_.load(std::memory_order_acquire); }
    float getProbability() const { return targetProbability_.load(std::memory_order_acquire); }
    int getPattern() const { return targetPatternMask_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetLengthBeats_{0.5f};
    std::atomic<float> targetGate_{0.8f};
    std::atomic<float> targetFilterDecay_{0.3f};
    std::atomic<float> targetPitchDecay_{0.2f};
    std::atomic<float> targetProbability_{0.5f};
    std::atomic<int> targetPatternMask_{0xFF};
    std::atomic<float> tempoBpm_{120.0f};
    std::atomic<float> targetMix_{1.0f};

    float currentLengthBeats_ = 0.5f;
    float currentGate_ = 0.8f;
    float currentFilterDecay_ = 0.3f;
    float currentPitchDecay_ = 0.2f;
    float currentProbability_ = 0.5f;
    float currentMix_ = 1.0f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> buffer_;
    int bufferSize_ = 0;
    int writeIndex_ = 0;

    bool stutterActive_ = false;
    int segmentLengthSamples_ = 1;
    int segmentAge_ = 0;
    int readStart_ = 0;
    int stepCounter_ = 0;

    float lpL_ = 0.0f;
    float lpR_ = 0.0f;

    juce::Random random_;
    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

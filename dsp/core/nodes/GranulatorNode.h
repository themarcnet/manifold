#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class GranulatorNode : public IPrimitiveNode,
                       public std::enable_shared_from_this<GranulatorNode> {
public:
    GranulatorNode();

    const char* getNodeType() const override { return "Granulator"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setGrainSize(float ms) { targetGrainSizeMs_.store(juce::jlimit(1.0f, 500.0f, ms), std::memory_order_release); }
    void setDensity(float grainsPerSecond) { targetDensity_.store(juce::jlimit(1.0f, 100.0f, grainsPerSecond), std::memory_order_release); }
    void setPosition(float position) { targetPosition_.store(juce::jlimit(0.0f, 1.0f, position), std::memory_order_release); }
    void setPitch(float semitones) { targetPitchSemitones_.store(juce::jlimit(-24.0f, 24.0f, semitones), std::memory_order_release); }
    void setSpray(float spray) { targetSpray_.store(juce::jlimit(0.0f, 1.0f, spray), std::memory_order_release); }
    void setFreeze(bool freeze) { freeze_.store(freeze, std::memory_order_release); }
    void setEnvelope(int type) { envelopeType_.store(juce::jlimit(0, 1, type), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getGrainSize() const { return targetGrainSizeMs_.load(std::memory_order_acquire); }
    float getDensity() const { return targetDensity_.load(std::memory_order_acquire); }
    float getPosition() const { return targetPosition_.load(std::memory_order_acquire); }
    float getPitch() const { return targetPitchSemitones_.load(std::memory_order_acquire); }
    float getSpray() const { return targetSpray_.load(std::memory_order_acquire); }
    bool getFreeze() const { return freeze_.load(std::memory_order_acquire); }
    int getEnvelope() const { return envelopeType_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    struct Grain {
        bool active = false;
        float readPos = 0.0f;
        float increment = 1.0f;
        int age = 0;
        int length = 1;
    };

    float readRing(int channel, float pos) const;
    float envelopeValue(const Grain& g) const;
    void spawnGrain();

    std::atomic<float> targetGrainSizeMs_{80.0f};
    std::atomic<float> targetDensity_{20.0f};
    std::atomic<float> targetPosition_{0.5f};
    std::atomic<float> targetPitchSemitones_{0.0f};
    std::atomic<float> targetSpray_{0.2f};
    std::atomic<bool> freeze_{false};
    std::atomic<int> envelopeType_{0};
    std::atomic<float> targetMix_{1.0f};

    float currentGrainSizeMs_ = 80.0f;
    float currentDensity_ = 20.0f;
    float currentPosition_ = 0.5f;
    float currentPitchSemitones_ = 0.0f;
    float currentSpray_ = 0.2f;
    float currentMix_ = 1.0f;
    float smooth_ = 1.0f;

    juce::AudioBuffer<float> captureBuffer_;
    int bufferSize_ = 0;
    int writeIndex_ = 0;

    static constexpr int kMaxGrains = 64;
    std::array<Grain, kMaxGrains> grains_{};
    int spawnCounter_ = 0;

    juce::Random random_;
    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

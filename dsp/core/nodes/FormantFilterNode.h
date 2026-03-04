#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class FormantFilterNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<FormantFilterNode> {
public:
    FormantFilterNode();

    const char* getNodeType() const override { return "FormantFilter"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setVowel(float vowel) { targetVowel_.store(juce::jlimit(0.0f, 4.0f, vowel), std::memory_order_release); }
    void setShift(float semitones) { targetShiftSemitones_.store(juce::jlimit(-12.0f, 12.0f, semitones), std::memory_order_release); }
    void setResonance(float q) { targetResonance_.store(juce::jlimit(1.0f, 20.0f, q), std::memory_order_release); }
    void setDrive(float drive) { targetDrive_.store(juce::jlimit(0.5f, 8.0f, drive), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getVowel() const { return targetVowel_.load(std::memory_order_acquire); }
    float getShift() const { return targetShiftSemitones_.load(std::memory_order_acquire); }
    float getResonance() const { return targetResonance_.load(std::memory_order_acquire); }
    float getDrive() const { return targetDrive_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    struct BiquadState {
        float x1 = 0.0f;
        float x2 = 0.0f;
        float y1 = 0.0f;
        float y2 = 0.0f;
    };

    struct Coeffs {
        float b0 = 0.0f;
        float b1 = 0.0f;
        float b2 = 0.0f;
        float a1 = 0.0f;
        float a2 = 0.0f;
    };

    static Coeffs makeBandpass(float sampleRate, float frequencyHz, float q);
    static float processBiquad(float x, BiquadState& s, const Coeffs& c);

    std::atomic<float> targetVowel_{0.0f};
    std::atomic<float> targetShiftSemitones_{0.0f};
    std::atomic<float> targetResonance_{6.0f};
    std::atomic<float> targetDrive_{1.2f};
    std::atomic<float> targetMix_{1.0f};

    float currentVowel_ = 0.0f;
    float currentShiftSemitones_ = 0.0f;
    float currentResonance_ = 6.0f;
    float currentDrive_ = 1.2f;
    float currentMix_ = 1.0f;
    float smooth_ = 1.0f;

    std::array<std::array<BiquadState, 3>, 2> states_{};
    std::array<Coeffs, 3> coeffs_{};

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

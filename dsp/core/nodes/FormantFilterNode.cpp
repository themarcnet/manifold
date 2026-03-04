#include "dsp/core/nodes/FormantFilterNode.h"

#include <cmath>

namespace dsp_primitives {

namespace {
constexpr float kFormants[5][3] = {
    {800.0f, 1150.0f, 2900.0f}, // A
    {400.0f, 1700.0f, 2600.0f}, // E
    {350.0f, 1900.0f, 2800.0f}, // I
    {450.0f, 800.0f, 2830.0f},  // O
    {325.0f, 700.0f, 2700.0f}   // U
};

constexpr float kFormantGains[3] = {1.0f, 0.8f, 0.55f};
}

FormantFilterNode::FormantFilterNode() = default;

void FormantFilterNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentVowel_ = targetVowel_.load(std::memory_order_acquire);
    currentShiftSemitones_ = targetShiftSemitones_.load(std::memory_order_acquire);
    currentResonance_ = targetResonance_.load(std::memory_order_acquire);
    currentDrive_ = targetDrive_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void FormantFilterNode::reset() {
    for (auto& ch : states_) {
        for (auto& f : ch) {
            f = BiquadState{};
        }
    }
}

FormantFilterNode::Coeffs FormantFilterNode::makeBandpass(float sampleRate,
                                                          float frequencyHz,
                                                          float q) {
    const float f = juce::jlimit(40.0f, 16000.0f, frequencyHz);
    const float Q = juce::jlimit(0.2f, 50.0f, q);

    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sampleRate;
    const float cosW0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);

    const float b0 = alpha;
    const float b1 = 0.0f;
    const float b2 = -alpha;
    const float a0 = 1.0f + alpha;
    const float a1 = -2.0f * cosW0;
    const float a2 = 1.0f - alpha;

    Coeffs c;
    c.b0 = b0 / a0;
    c.b1 = b1 / a0;
    c.b2 = b2 / a0;
    c.a1 = a1 / a0;
    c.a2 = a2 / a0;
    return c;
}

float FormantFilterNode::processBiquad(float x, BiquadState& s, const Coeffs& c) {
    const float y = c.b0 * x + c.b1 * s.x1 + c.b2 * s.x2 - c.a1 * s.y1 - c.a2 * s.y2;
    s.x2 = s.x1;
    s.x1 = x;
    s.y2 = s.y1;
    s.y1 = y;
    return y;
}

void FormantFilterNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tVowel = targetVowel_.load(std::memory_order_acquire);
    const float tShift = targetShiftSemitones_.load(std::memory_order_acquire);
    const float tResonance = targetResonance_.load(std::memory_order_acquire);
    const float tDrive = targetDrive_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentVowel_ += (tVowel - currentVowel_) * smooth_;
        currentShiftSemitones_ += (tShift - currentShiftSemitones_) * smooth_;
        currentResonance_ += (tResonance - currentResonance_) * smooth_;
        currentDrive_ += (tDrive - currentDrive_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const int idx0 = juce::jlimit(0, 4, static_cast<int>(std::floor(currentVowel_)));
        const int idx1 = juce::jlimit(0, 4, idx0 + 1);
        const float frac = juce::jlimit(0.0f, 1.0f, currentVowel_ - static_cast<float>(idx0));
        const float shiftRatio = std::pow(2.0f, currentShiftSemitones_ / 12.0f);

        for (int f = 0; f < 3; ++f) {
            const float baseHz = juce::jmap(frac, kFormants[idx0][f], kFormants[idx1][f]);
            coeffs_[static_cast<size_t>(f)] = makeBandpass(
                static_cast<float>(sampleRate_),
                baseHz * shiftRatio,
                currentResonance_);
        }

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float outL = inL;
        float outR = inR;

        for (int ch = 0; ch < 2; ++ch) {
            const float dry = ch == 0 ? inL : inR;
            const float driven = std::tanh(dry * currentDrive_);

            float wet = 0.0f;
            for (int f = 0; f < 3; ++f) {
                wet += processBiquad(
                    driven,
                    states_[static_cast<size_t>(ch)][static_cast<size_t>(f)],
                    coeffs_[static_cast<size_t>(f)]) * kFormantGains[f];
            }

            wet = std::tanh(wet);
            const float out = dry * (1.0f - currentMix_) + wet * currentMix_;

            if (ch == 0) outL = out;
            else outR = out;
        }

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }
}

} // namespace dsp_primitives

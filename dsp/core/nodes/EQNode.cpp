#include "dsp/core/nodes/EQNode.h"

#include <cmath>

namespace dsp_primitives {

namespace {
inline void copyDryToOutput(const AudioBufferView& input,
                            WritableAudioBufferView& output,
                            int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        const float inL = input.getSample(0, i);
        const float inR = input.numChannels > 1 ? input.getSample(1, i) : inL;
        output.setSample(0, i, inL);
        if (output.numChannels > 1) {
            output.setSample(1, i, inR);
        }
    }
}
}

EQNode::EQNode() = default;

void EQNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    lowGainDb_ = targetLowGainDb_.load(std::memory_order_acquire);
    lowFreqHz_ = targetLowFreqHz_.load(std::memory_order_acquire);
    midGainDb_ = targetMidGainDb_.load(std::memory_order_acquire);
    midFreqHz_ = targetMidFreqHz_.load(std::memory_order_acquire);
    midQ_ = targetMidQ_.load(std::memory_order_acquire);
    highGainDb_ = targetHighGainDb_.load(std::memory_order_acquire);
    highFreqHz_ = targetHighFreqHz_.load(std::memory_order_acquire);
    outputDb_ = targetOutputDb_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    updateCoeffsForCurrentParams(true);
    prepared_ = true;
}

void EQNode::reset() {
    for (auto& ch : state_) {
        for (auto& s : ch) {
            s = State{};
        }
    }
    coeffsValid_ = false;
}

void EQNode::updateCoeffsForCurrentParams(bool force) {
    constexpr float kGainEpsilon = 0.02f;
    constexpr float kFreqEpsilon = 0.5f;
    constexpr float kQEpsilon = 0.01f;

    if (!force
        && coeffsValid_
        && std::abs(lowGainDb_ - lastCoeffLowGainDb_) <= kGainEpsilon
        && std::abs(lowFreqHz_ - lastCoeffLowFreqHz_) <= kFreqEpsilon
        && std::abs(midGainDb_ - lastCoeffMidGainDb_) <= kGainEpsilon
        && std::abs(midFreqHz_ - lastCoeffMidFreqHz_) <= kFreqEpsilon
        && std::abs(midQ_ - lastCoeffMidQ_) <= kQEpsilon
        && std::abs(highGainDb_ - lastCoeffHighGainDb_) <= kGainEpsilon
        && std::abs(highFreqHz_ - lastCoeffHighFreqHz_) <= kFreqEpsilon) {
        return;
    }

    lowCoeffs_ = makeLowShelf(static_cast<float>(sampleRate_), lowFreqHz_, lowGainDb_);
    midCoeffs_ = makePeak(static_cast<float>(sampleRate_), midFreqHz_, midQ_, midGainDb_);
    highCoeffs_ = makeHighShelf(static_cast<float>(sampleRate_), highFreqHz_, highGainDb_);

    lastCoeffLowGainDb_ = lowGainDb_;
    lastCoeffLowFreqHz_ = lowFreqHz_;
    lastCoeffMidGainDb_ = midGainDb_;
    lastCoeffMidFreqHz_ = midFreqHz_;
    lastCoeffMidQ_ = midQ_;
    lastCoeffHighGainDb_ = highGainDb_;
    lastCoeffHighFreqHz_ = highFreqHz_;
    coeffsValid_ = true;
}

EQNode::Coeffs EQNode::makePeak(float sr, float freq, float q, float gainDb) {
    const float f = juce::jlimit(20.0f, 20000.0f, freq);
    const float Q = juce::jlimit(0.2f, 50.0f, q);
    const float A = std::pow(10.0f, gainDb / 40.0f);

    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);

    const float b0 = 1.0f + alpha * A;
    const float b1 = -2.0f * cosw0;
    const float b2 = 1.0f - alpha * A;
    const float a0 = 1.0f + alpha / A;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha / A;

    Coeffs c;
    c.b0 = b0 / a0;
    c.b1 = b1 / a0;
    c.b2 = b2 / a0;
    c.a1 = a1 / a0;
    c.a2 = a2 / a0;
    return c;
}

EQNode::Coeffs EQNode::makeLowShelf(float sr, float freq, float gainDb) {
    const float f = juce::jlimit(20.0f, 20000.0f, freq);
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;

    const float cosw0 = std::cos(w0);
    const float sinw0 = std::sin(w0);
    const float alpha = sinw0 / 2.0f * std::sqrt(A);

    const float b0 = A * ((A + 1.0f) - (A - 1.0f) * cosw0 + 2.0f * alpha);
    const float b1 = 2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw0);
    const float b2 = A * ((A + 1.0f) - (A - 1.0f) * cosw0 - 2.0f * alpha);
    const float a0 = (A + 1.0f) + (A - 1.0f) * cosw0 + 2.0f * alpha;
    const float a1 = -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw0);
    const float a2 = (A + 1.0f) + (A - 1.0f) * cosw0 - 2.0f * alpha;

    Coeffs c;
    c.b0 = b0 / a0;
    c.b1 = b1 / a0;
    c.b2 = b2 / a0;
    c.a1 = a1 / a0;
    c.a2 = a2 / a0;
    return c;
}

EQNode::Coeffs EQNode::makeHighShelf(float sr, float freq, float gainDb) {
    const float f = juce::jlimit(20.0f, 20000.0f, freq);
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;

    const float cosw0 = std::cos(w0);
    const float sinw0 = std::sin(w0);
    const float alpha = sinw0 / 2.0f * std::sqrt(A);

    const float b0 = A * ((A + 1.0f) + (A - 1.0f) * cosw0 + 2.0f * alpha);
    const float b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw0);
    const float b2 = A * ((A + 1.0f) + (A - 1.0f) * cosw0 - 2.0f * alpha);
    const float a0 = (A + 1.0f) - (A - 1.0f) * cosw0 + 2.0f * alpha;
    const float a1 = 2.0f * ((A - 1.0f) - (A + 1.0f) * cosw0);
    const float a2 = (A + 1.0f) - (A - 1.0f) * cosw0 - 2.0f * alpha;

    Coeffs c;
    c.b0 = b0 / a0;
    c.b1 = b1 / a0;
    c.b2 = b2 / a0;
    c.a1 = a1 / a0;
    c.a2 = a2 / a0;
    return c;
}

float EQNode::processBiquad(float x, State& s, const Coeffs& c) {
    const float y = c.b0 * x + c.b1 * s.x1 + c.b2 * s.x2 - c.a1 * s.y1 - c.a2 * s.y2;
    s.x2 = s.x1;
    s.x1 = x;
    s.y2 = s.y1;
    s.y1 = y;
    return y;
}

void EQNode::process(const std::vector<AudioBufferView>& inputs,
                     std::vector<WritableAudioBufferView>& outputs,
                     int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tLowG = targetLowGainDb_.load(std::memory_order_acquire);
    const float tLowF = targetLowFreqHz_.load(std::memory_order_acquire);
    const float tMidG = targetMidGainDb_.load(std::memory_order_acquire);
    const float tMidF = targetMidFreqHz_.load(std::memory_order_acquire);
    const float tMidQ = targetMidQ_.load(std::memory_order_acquire);
    const float tHighG = targetHighGainDb_.load(std::memory_order_acquire);
    const float tHighF = targetHighFreqHz_.load(std::memory_order_acquire);
    const float tOut = targetOutputDb_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    if (tMix <= 1.0e-4f && mix_ <= 1.0e-4f) {
        copyDryToOutput(inputs[0], outputs[0], numSamples);
        return;
    }

    for (int i = 0; i < numSamples; ++i) {
        lowGainDb_ += (tLowG - lowGainDb_) * smooth_;
        lowFreqHz_ += (tLowF - lowFreqHz_) * smooth_;
        midGainDb_ += (tMidG - midGainDb_) * smooth_;
        midFreqHz_ += (tMidF - midFreqHz_) * smooth_;
        midQ_ += (tMidQ - midQ_) * smooth_;
        highGainDb_ += (tHighG - highGainDb_) * smooth_;
        highFreqHz_ += (tHighF - highFreqHz_) * smooth_;
        outputDb_ += (tOut - outputDb_) * smooth_;
        mix_ += (tMix - mix_) * smooth_;

        updateCoeffsForCurrentParams();
        const float outGain = std::pow(10.0f, outputDb_ / 20.0f);

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float outL = inL;
        float outR = inR;

        for (int ch = 0; ch < 2; ++ch) {
            const float dry = ch == 0 ? inL : inR;
            float x = dry;
            x = processBiquad(x, state_[static_cast<size_t>(ch)][0], lowCoeffs_);
            x = processBiquad(x, state_[static_cast<size_t>(ch)][1], midCoeffs_);
            x = processBiquad(x, state_[static_cast<size_t>(ch)][2], highCoeffs_);
            x *= outGain;

            const float out = dry * (1.0f - mix_) + x * mix_;
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

#include "dsp/core/nodes/OscillatorNode.h"

#define _USE_MATH_DEFINES
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace dsp_primitives {

OscillatorNode::OscillatorNode() = default;

void OscillatorNode::setFrequency(float freq) {
    targetFrequency_.store(juce::jlimit(1.0f, 20000.0f, freq), std::memory_order_release);
}

void OscillatorNode::setWaveform(int shape) {
    waveform_.store(juce::jlimit(0, 4, shape), std::memory_order_release);
}

void OscillatorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double freqTimeSeconds = 0.02;
    const double ampTimeSeconds = 0.01;
    freqSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (freqTimeSeconds * sampleRate_)));
    ampSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (ampTimeSeconds * sampleRate_)));
    freqSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, freqSmoothingCoeff_);
    ampSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, ampSmoothingCoeff_);

    currentFrequency_ = targetFrequency_.load(std::memory_order_acquire);
    currentAmplitude_ = targetAmplitude_.load(std::memory_order_acquire);
}

void OscillatorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    (void)inputs;

    if (outputs.empty() || !enabled_.load(std::memory_order_acquire)) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }

    auto& out = outputs[0];
    const int wf = waveform_.load(std::memory_order_acquire);
    const float targetFreq = targetFrequency_.load(std::memory_order_acquire);
    const float targetAmp = enabled_.load(std::memory_order_acquire)
                                ? targetAmplitude_.load(std::memory_order_acquire)
                                : 0.0f;

    for (int i = 0; i < numSamples; ++i) {
        currentFrequency_ += (targetFreq - currentFrequency_) * freqSmoothingCoeff_;
        currentAmplitude_ += (targetAmp - currentAmplitude_) * ampSmoothingCoeff_;

        const double phaseIncrement = 2.0 * M_PI * currentFrequency_ / sampleRate_;

        const float sine = static_cast<float>(std::sin(phase_));
        const float phaseNorm = static_cast<float>(phase_ / (2.0 * M_PI));
        const float saw = 2.0f * phaseNorm - 1.0f;
        const float square = (phase_ < juce::MathConstants<double>::pi) ? 1.0f : -1.0f;
        const float triangle = 1.0f - 4.0f * std::abs(phaseNorm - 0.5f);

        float waveformSample = sine;
        switch (wf) {
            case 1: waveformSample = saw; break;
            case 2: waveformSample = square; break;
            case 3: waveformSample = triangle; break;
            case 4: waveformSample = 0.45f * sine + 0.55f * saw; break;
            case 0:
            default:
                waveformSample = sine;
                break;
        }

        const float sample = waveformSample * currentAmplitude_;
        for (int ch = 0; ch < out.numChannels; ++ch) {
            out.setSample(ch, i, sample);
        }

        phase_ += phaseIncrement;
        while (phase_ >= 2.0 * M_PI) {
            phase_ -= 2.0 * M_PI;
        }
        while (phase_ < 0.0) {
            phase_ += 2.0 * M_PI;
        }
    }
}

} // namespace dsp_primitives

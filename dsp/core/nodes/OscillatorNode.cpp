#include "dsp/core/nodes/OscillatorNode.h"

#define _USE_MATH_DEFINES
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace dsp_primitives {

OscillatorNode::OscillatorNode() = default;

void OscillatorNode::setFrequency(float freq) {
    frequency_ = juce::jlimit(1.0f, 20000.0f, freq);
    if (sampleRate_ > 0.0) {
        phaseIncrement_ = 2.0 * M_PI * frequency_ / sampleRate_;
    }
}

void OscillatorNode::setWaveform(int shape) {
    waveform_ = juce::jlimit(0, 4, shape);
}

void OscillatorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate;
    phaseIncrement_ = 2.0 * M_PI * frequency_ / sampleRate_;
}

void OscillatorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    (void)inputs;

    if (outputs.empty() || !enabled_) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }

    auto& out = outputs[0];
    for (int i = 0; i < numSamples; ++i) {
        const float sine = static_cast<float>(std::sin(phase_));
        const float phaseNorm = static_cast<float>(phase_ / (2.0 * M_PI));
        const float saw = 2.0f * phaseNorm - 1.0f;
        const float square = (phase_ < juce::MathConstants<double>::pi) ? 1.0f : -1.0f;
        const float triangle = 1.0f - 4.0f * std::abs(phaseNorm - 0.5f);

        float waveformSample = sine;
        switch (waveform_) {
            case 1: waveformSample = saw; break;
            case 2: waveformSample = square; break;
            case 3: waveformSample = triangle; break;
            case 4: waveformSample = 0.45f * sine + 0.55f * saw; break;
            case 0:
            default:
                waveformSample = sine;
                break;
        }

        const float sample = waveformSample * amplitude_;
        for (int ch = 0; ch < out.numChannels; ++ch) {
            out.setSample(ch, i, sample);
        }

        phase_ += phaseIncrement_;
        while (phase_ >= 2.0 * M_PI) {
            phase_ -= 2.0 * M_PI;
        }
        while (phase_ < 0) {
            phase_ += 2.0 * M_PI;
        }
    }
}

} // namespace dsp_primitives

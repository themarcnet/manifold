#include "dsp/core/nodes/FilterNode.h"

#include <cmath>

namespace dsp_primitives {

FilterNode::FilterNode() = default;

void FilterNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothingTimeSeconds = 0.02;
    smoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sampleRate_)));
    smoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, smoothingCoeff_);

    z1_[0] = 0.0f;
    z1_[1] = 0.0f;
    z2_[0] = 0.0f;
    z2_[1] = 0.0f;

    cutoffHz_ = targetCutoffHz_.load(std::memory_order_acquire);
    resonance_ = targetResonance_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);
}

void FilterNode::setCutoff(float hz) {
    targetCutoffHz_.store(juce::jlimit(20.0f, 18000.0f, hz), std::memory_order_release);
}

void FilterNode::setResonance(float q) {
    targetResonance_.store(juce::jlimit(0.0f, 1.0f, q), std::memory_order_release);
}

void FilterNode::setMix(float mix) {
    targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release);
}

float FilterNode::computeAlpha(float cutoffHz, float resonance) const {
    const float sr = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);
    const float normalized = juce::jlimit(0.0001f, 0.49f, cutoffHz / sr);
    const float shaping = 1.0f + resonance * 0.6f;
    float alpha = 1.0f - std::exp(-2.0f * juce::MathConstants<float>::pi * normalized * shaping);
    return juce::jlimit(0.0001f, 0.999f, alpha);
}

void FilterNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    const float targetCutoff = targetCutoffHz_.load(std::memory_order_acquire);
    const float targetResonance = targetResonance_.load(std::memory_order_acquire);
    const float targetMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        cutoffHz_ += (targetCutoff - cutoffHz_) * smoothingCoeff_;
        resonance_ += (targetResonance - resonance_) * smoothingCoeff_;
        mix_ += (targetMix - mix_) * smoothingCoeff_;

        const float alpha = computeAlpha(cutoffHz_, resonance_);
        const float feedback = resonance_ * 0.85f;
        const float dry = 1.0f - mix_;
        const float wet = mix_;

        for (int ch = 0; ch < 2; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            const float in = inputs[idx].getSample(ch, i);
            const float x = in - feedback * (z2_[idx] - z1_[idx]);
            z1_[idx] += alpha * (x - z1_[idx]);
            z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
            const float filtered = z2_[idx];
            outputs[idx].setSample(ch, i, in * dry + filtered * wet);
        }
    }
}

} // namespace dsp_primitives

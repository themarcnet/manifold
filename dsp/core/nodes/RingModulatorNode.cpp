#include "dsp/core/nodes/RingModulatorNode.h"

#include <cmath>

namespace dsp_primitives {

RingModulatorNode::RingModulatorNode() = default;

void RingModulatorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentFrequencyHz_ = targetFrequencyHz_.load(std::memory_order_acquire);
    currentDepth_ = targetDepth_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentSpreadDegrees_ = targetSpreadDegrees_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void RingModulatorNode::reset() {
    lfoPhase_ = 0.0f;
}

void RingModulatorNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const bool enabled = enabled_.load(std::memory_order_acquire);
    const bool hasExternalModBus = inputs.size() >= 3;

    const float tFrequency = targetFrequencyHz_.load(std::memory_order_acquire);
    const float tDepth = targetDepth_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);
    const float tSpread = targetSpreadDegrees_.load(std::memory_order_acquire);

    if (!enabled) {
        outputs[0].clear();
        currentDepth_ = 0.0f;
        currentMix_ = 0.0f;
        return;
    }

    for (int i = 0; i < numSamples; ++i) {
        currentFrequencyHz_ += (tFrequency - currentFrequencyHz_) * smooth_;
        currentDepth_ += (tDepth - currentDepth_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;
        currentSpreadDegrees_ += (tSpread - currentSpreadDegrees_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float modL = 0.0f;
        float modR = 0.0f;
        if (hasExternalModBus) {
            modL = juce::jlimit(-1.0f, 1.0f, inputs[2].getSample(0, i));
            modR = juce::jlimit(-1.0f, 1.0f,
                                inputs[2].numChannels > 1 ? inputs[2].getSample(1, i) : modL);
        } else {
            const float phaseInc = currentFrequencyHz_ / static_cast<float>(sampleRate_);
            lfoPhase_ += phaseInc;
            if (lfoPhase_ >= 1.0f) {
                lfoPhase_ -= 1.0f;
            }

            const float spreadPhase = currentSpreadDegrees_ / 360.0f;
            modL = std::sin(2.0f * juce::MathConstants<float>::pi * lfoPhase_);
            modR = std::sin(2.0f * juce::MathConstants<float>::pi * (lfoPhase_ + spreadPhase));
        }

        const float wetL = inL * ((1.0f - currentDepth_) + currentDepth_ * modL);
        const float wetR = inR * ((1.0f - currentDepth_) + currentDepth_ * modR);

        const float dry = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dry + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dry + wetR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

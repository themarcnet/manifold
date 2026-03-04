#include "dsp/core/nodes/BitCrusherNode.h"

#include <cmath>

namespace dsp_primitives {

BitCrusherNode::BitCrusherNode() = default;

void BitCrusherNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentBits_ = targetBits_.load(std::memory_order_acquire);
    currentRateReduction_ = targetRateReduction_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentOutput_ = targetOutput_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void BitCrusherNode::reset() {
    heldSample_[0] = 0.0f;
    heldSample_[1] = 0.0f;
    holdCounter_[0] = 0.0f;
    holdCounter_[1] = 0.0f;
}

void BitCrusherNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tBits = targetBits_.load(std::memory_order_acquire);
    const float tRateReduction = targetRateReduction_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);
    const float tOutput = targetOutput_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentBits_ += (tBits - currentBits_) * smooth_;
        currentRateReduction_ += (tRateReduction - currentRateReduction_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;
        currentOutput_ += (tOutput - currentOutput_) * smooth_;

        const float quantLevels = std::pow(2.0f, currentBits_ - 1.0f);
        const float holdInterval = juce::jmax(1.0f, currentRateReduction_);

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float outL = inL;
        float outR = inR;

        for (int ch = 0; ch < 2; ++ch) {
            const float in = ch == 0 ? inL : inR;
            holdCounter_[static_cast<size_t>(ch)] += 1.0f;

            if (holdCounter_[static_cast<size_t>(ch)] >= holdInterval) {
                holdCounter_[static_cast<size_t>(ch)] -= holdInterval;
                const float q = std::round(in * quantLevels) / quantLevels;
                heldSample_[static_cast<size_t>(ch)] = juce::jlimit(-1.0f, 1.0f, q);
            }

            const float wet = heldSample_[static_cast<size_t>(ch)] * currentOutput_;
            const float out = in * (1.0f - currentMix_) + wet * currentMix_;

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

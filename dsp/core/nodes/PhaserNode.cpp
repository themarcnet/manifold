#include "dsp/core/nodes/PhaserNode.h"

#include <cmath>

namespace dsp_primitives {

PhaserNode::PhaserNode() = default;

void PhaserNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    const float smooth = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth);

    currentRateHz_ = targetRateHz_.load(std::memory_order_acquire);
    currentDepth_ = targetDepth_.load(std::memory_order_acquire);
    currentFeedback_ = targetFeedback_.load(std::memory_order_acquire);
    currentSpreadDegrees_ = targetSpreadDegrees_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void PhaserNode::reset() {
    for (auto& ch : z1_) {
        ch.fill(0.0f);
    }
    feedbackState_[0] = 0.0f;
    feedbackState_[1] = 0.0f;
    lfoPhase_ = 0.0f;
}

float PhaserNode::allpassProcess(int channel, int stage, float in, float a) {
    const float z = z1_[static_cast<size_t>(channel)][static_cast<size_t>(stage)];
    const float y = -a * in + z;
    z1_[static_cast<size_t>(channel)][static_cast<size_t>(stage)] = in + (a * y);
    return y;
}

void PhaserNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float targetRate = targetRateHz_.load(std::memory_order_acquire);
    const float targetDepth = targetDepth_.load(std::memory_order_acquire);
    const float targetFeedback = targetFeedback_.load(std::memory_order_acquire);
    const float targetSpread = targetSpreadDegrees_.load(std::memory_order_acquire);
    const int stages = targetStages_.load(std::memory_order_acquire) >= 9 ? 12 : 6;

    for (int i = 0; i < numSamples; ++i) {
        currentRateHz_ += (targetRate - currentRateHz_) * smooth_;
        currentDepth_ += (targetDepth - currentDepth_) * smooth_;
        currentFeedback_ += (targetFeedback - currentFeedback_) * smooth_;
        currentSpreadDegrees_ += (targetSpread - currentSpreadDegrees_) * smooth_;

        const float phaseInc = currentRateHz_ / static_cast<float>(sampleRate_);
        lfoPhase_ += phaseInc;
        if (lfoPhase_ >= 1.0f) {
            lfoPhase_ -= 1.0f;
        }

        const float spreadPhase = currentSpreadDegrees_ / 360.0f;
        const float lfoL = std::sin(2.0f * juce::MathConstants<float>::pi * lfoPhase_);
        const float lfoR = std::sin(2.0f * juce::MathConstants<float>::pi * (lfoPhase_ + spreadPhase));

        const float centerHz = 900.0f;
        const float rangeHz = 700.0f * currentDepth_;
        const float freqL = juce::jlimit(80.0f, 4000.0f, centerHz + lfoL * rangeHz);
        const float freqR = juce::jlimit(80.0f, 4000.0f, centerHz + lfoR * rangeHz);

        const float gL = std::tan(juce::MathConstants<float>::pi * freqL / static_cast<float>(sampleRate_));
        const float gR = std::tan(juce::MathConstants<float>::pi * freqR / static_cast<float>(sampleRate_));
        const float aL = (gL - 1.0f) / (gL + 1.0f);
        const float aR = (gR - 1.0f) / (gR + 1.0f);

        float inL = inputs[0].getSample(0, i);
        float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float xL = inL + feedbackState_[0] * currentFeedback_;
        float xR = inR + feedbackState_[1] * currentFeedback_;

        for (int s = 0; s < stages; ++s) {
            xL = allpassProcess(0, s, xL, aL);
            xR = allpassProcess(1, s, xR, aR);
        }

        feedbackState_[0] = xL;
        feedbackState_[1] = xR;

        const float outL = 0.5f * inL + 0.5f * xL;
        const float outR = 0.5f * inR + 0.5f * xR;

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }
}

} // namespace dsp_primitives

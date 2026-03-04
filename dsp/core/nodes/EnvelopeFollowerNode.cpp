#include "dsp/core/nodes/EnvelopeFollowerNode.h"

#include <cmath>

namespace dsp_primitives {

EnvelopeFollowerNode::EnvelopeFollowerNode() = default;

void EnvelopeFollowerNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentAttackMs_ = targetAttackMs_.load(std::memory_order_acquire);
    currentReleaseMs_ = targetReleaseMs_.load(std::memory_order_acquire);
    currentSensitivity_ = targetSensitivity_.load(std::memory_order_acquire);
    currentHighpassHz_ = targetHighpassHz_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void EnvelopeFollowerNode::reset() {
    hpState_[0] = 0.0f;
    hpState_[1] = 0.0f;
    hpInput_[0] = 0.0f;
    hpInput_[1] = 0.0f;
    envelope_ = 0.0f;
    envelopeOut_.store(0.0f, std::memory_order_release);
}

void EnvelopeFollowerNode::process(const std::vector<AudioBufferView>& inputs,
                                   std::vector<WritableAudioBufferView>& outputs,
                                   int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tAttack = targetAttackMs_.load(std::memory_order_acquire);
    const float tRelease = targetReleaseMs_.load(std::memory_order_acquire);
    const float tSensitivity = targetSensitivity_.load(std::memory_order_acquire);
    const float tHighpass = targetHighpassHz_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentAttackMs_ += (tAttack - currentAttackMs_) * smooth_;
        currentReleaseMs_ += (tRelease - currentReleaseMs_) * smooth_;
        currentSensitivity_ += (tSensitivity - currentSensitivity_) * smooth_;
        currentHighpassHz_ += (tHighpass - currentHighpassHz_) * smooth_;

        const float hpCoeff = std::exp(-2.0f * juce::MathConstants<float>::pi *
                                       currentHighpassHz_ / static_cast<float>(sampleRate_));
        const float attackCoeff = std::exp(-1.0f / (juce::jmax(0.0001f, currentAttackMs_ * 0.001f) *
                                                    static_cast<float>(sampleRate_)));
        const float releaseCoeff = std::exp(-1.0f / (juce::jmax(0.0001f, currentReleaseMs_ * 0.001f) *
                                                     static_cast<float>(sampleRate_)));

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float sum = 0.0f;
        for (int ch = 0; ch < 2; ++ch) {
            const float x = ch == 0 ? inL : inR;
            const float hp = hpCoeff * (hpState_[static_cast<size_t>(ch)] + x - hpInput_[static_cast<size_t>(ch)]);
            hpInput_[static_cast<size_t>(ch)] = x;
            hpState_[static_cast<size_t>(ch)] = hp;
            sum += std::abs(hp);
        }

        const float detector = (sum * 0.5f) * currentSensitivity_;
        if (detector > envelope_) {
            envelope_ = attackCoeff * envelope_ + (1.0f - attackCoeff) * detector;
        } else {
            envelope_ = releaseCoeff * envelope_ + (1.0f - releaseCoeff) * detector;
        }

        outputs[0].setSample(0, i, inL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR);
        }
    }

    envelopeOut_.store(envelope_, std::memory_order_release);
}

} // namespace dsp_primitives

#include "dsp/core/nodes/TransientShaperNode.h"

#include <cmath>

namespace dsp_primitives {

TransientShaperNode::TransientShaperNode() = default;

void TransientShaperNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    auto coeffFromMs = [this](float ms) {
        const float t = juce::jmax(0.0001f, ms * 0.001f);
        return 1.0f - std::exp(-1.0f / (static_cast<float>(sampleRate_) * t));
    };

    fastAttackCoeff_ = coeffFromMs(1.0f);
    fastReleaseCoeff_ = coeffFromMs(20.0f);
    slowAttackCoeff_ = coeffFromMs(20.0f);
    slowReleaseCoeff_ = coeffFromMs(300.0f);

    currentAttack_ = targetAttack_.load(std::memory_order_acquire);
    currentSustain_ = targetSustain_.load(std::memory_order_acquire);
    currentSensitivity_ = targetSensitivity_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void TransientShaperNode::reset() {
    fastEnv_[0] = 0.0f;
    fastEnv_[1] = 0.0f;
    slowEnv_[0] = 0.0f;
    slowEnv_[1] = 0.0f;
    transientMeter_.store(0.0f, std::memory_order_release);
}

void TransientShaperNode::process(const std::vector<AudioBufferView>& inputs,
                                  std::vector<WritableAudioBufferView>& outputs,
                                  int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tAttack = targetAttack_.load(std::memory_order_acquire);
    const float tSustain = targetSustain_.load(std::memory_order_acquire);
    const float tSensitivity = targetSensitivity_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    float transientAccum = 0.0f;

    for (int i = 0; i < numSamples; ++i) {
        currentAttack_ += (tAttack - currentAttack_) * smooth_;
        currentSustain_ += (tSustain - currentSustain_) * smooth_;
        currentSensitivity_ += (tSensitivity - currentSensitivity_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float outL = inL;
        float outR = inR;

        for (int ch = 0; ch < 2; ++ch) {
            const float in = ch == 0 ? inL : inR;
            const float level = std::abs(in);

            const float fastCoeff = level > fastEnv_[static_cast<size_t>(ch)] ? fastAttackCoeff_ : fastReleaseCoeff_;
            const float slowCoeff = level > slowEnv_[static_cast<size_t>(ch)] ? slowAttackCoeff_ : slowReleaseCoeff_;

            fastEnv_[static_cast<size_t>(ch)] +=
                (level - fastEnv_[static_cast<size_t>(ch)]) * fastCoeff;
            slowEnv_[static_cast<size_t>(ch)] +=
                (level - slowEnv_[static_cast<size_t>(ch)]) * slowCoeff;

            const float transient = (fastEnv_[static_cast<size_t>(ch)] - slowEnv_[static_cast<size_t>(ch)]) * currentSensitivity_;
            const float body = (slowEnv_[static_cast<size_t>(ch)] - fastEnv_[static_cast<size_t>(ch)]) * currentSensitivity_;

            const float attackGain = juce::jlimit(0.0f, 4.0f, 1.0f + currentAttack_ * transient * 6.0f);
            const float sustainGain = juce::jlimit(0.0f, 4.0f, 1.0f + currentSustain_ * body * 4.0f);
            const float gain = juce::jlimit(0.0f, 4.0f, attackGain * sustainGain);

            const float wet = in * gain;
            const float out = in * (1.0f - currentMix_) + wet * currentMix_;

            if (ch == 0) {
                outL = out;
            } else {
                outR = out;
            }

            transientAccum += std::abs(transient);
        }

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }

    transientMeter_.store(transientAccum / static_cast<float>(juce::jmax(1, numSamples * 2)),
                          std::memory_order_release);
}

} // namespace dsp_primitives

#include "dsp/core/nodes/LimiterNode.h"

#include <cmath>

namespace dsp_primitives {

LimiterNode::LimiterNode() = default;

void LimiterNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    thresholdDb_ = targetThresholdDb_.load(std::memory_order_acquire);
    releaseMs_ = targetReleaseMs_.load(std::memory_order_acquire);
    makeupDb_ = targetMakeupDb_.load(std::memory_order_acquire);
    softClip_ = targetSoftClip_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void LimiterNode::reset() {
    gain_ = 1.0f;
    gainReductionDb_.store(0.0f, std::memory_order_release);
}

void LimiterNode::process(const std::vector<AudioBufferView>& inputs,
                          std::vector<WritableAudioBufferView>& outputs,
                          int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tThreshold = targetThresholdDb_.load(std::memory_order_acquire);
    const float tRelease = targetReleaseMs_.load(std::memory_order_acquire);
    const float tMakeup = targetMakeupDb_.load(std::memory_order_acquire);
    const float tSoft = targetSoftClip_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    float gr = 0.0f;

    for (int i = 0; i < numSamples; ++i) {
        thresholdDb_ += (tThreshold - thresholdDb_) * smooth_;
        releaseMs_ += (tRelease - releaseMs_) * smooth_;
        makeupDb_ += (tMakeup - makeupDb_) * smooth_;
        softClip_ += (tSoft - softClip_) * smooth_;
        mix_ += (tMix - mix_) * smooth_;

        const float thresholdLin = std::pow(10.0f, thresholdDb_ / 20.0f);
        const float makeupLin = std::pow(10.0f, makeupDb_ / 20.0f);

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        const float peak = std::max(std::abs(inL), std::abs(inR));
        const float targetGain = (peak > thresholdLin && peak > 0.0f)
                                     ? (thresholdLin / peak)
                                     : 1.0f;

        const float releaseCoeff = std::exp(-1.0f / (juce::jmax(0.0001f, releaseMs_ * 0.001f) *
                                                     static_cast<float>(sampleRate_)));

        if (targetGain < gain_) {
            // Attack: clamp immediately
            gain_ = targetGain;
        } else {
            // Release: smooth upwards
            gain_ = releaseCoeff * gain_ + (1.0f - releaseCoeff) * targetGain;
        }

        const float wetL0 = inL * gain_ * makeupLin;
        const float wetR0 = inR * gain_ * makeupLin;

        float wetL = wetL0;
        float wetR = wetR0;

        if (softClip_ > 0.0001f) {
            const float drive = 1.0f + softClip_ * 6.0f;
            wetL = std::tanh(wetL0 * drive) / drive;
            wetR = std::tanh(wetR0 * drive) / drive;
        }

        const float dry = 1.0f - mix_;
        outputs[0].setSample(0, i, inL * dry + wetL * mix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dry + wetR * mix_);
        }

        gr += -20.0f * std::log10(juce::jmax(0.000001f, gain_));
    }

    gainReductionDb_.store(gr / static_cast<float>(juce::jmax(1, numSamples)), std::memory_order_release);
}

} // namespace dsp_primitives

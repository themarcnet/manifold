#include "dsp/core/nodes/StereoWidenerNode.h"

#include <cmath>

namespace dsp_primitives {

StereoWidenerNode::StereoWidenerNode() = default;

void StereoWidenerNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    const float smooth = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    widthSmooth_ = juce::jlimit(0.0001f, 1.0f, smooth);
    freqSmooth_ = widthSmooth_;

    currentWidth_ = targetWidth_.load(std::memory_order_acquire);
    currentMonoLowFreq_ = targetMonoLowFreq_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void StereoWidenerNode::reset() {
    lowL_ = 0.0f;
    lowR_ = 0.0f;
    corrNum_ = 0.0f;
    corrDenL_ = 0.0f;
    corrDenR_ = 0.0f;
    correlation_.store(0.0f, std::memory_order_release);
}

void StereoWidenerNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const bool monoLow = monoLowEnable_.load(std::memory_order_acquire);
    const float targetWidth = targetWidth_.load(std::memory_order_acquire);
    const float targetFreq = targetMonoLowFreq_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentWidth_ += (targetWidth - currentWidth_) * widthSmooth_;
        currentMonoLowFreq_ += (targetFreq - currentMonoLowFreq_) * freqSmooth_;

        const float omega = 2.0f * juce::MathConstants<float>::pi * currentMonoLowFreq_ / static_cast<float>(sampleRate_);
        const float alpha = juce::jlimit(0.00001f, 0.99999f, omega / (omega + 1.0f));

        float inL = inputs[0].getSample(0, i);
        float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        lowL_ += alpha * (inL - lowL_);
        lowR_ += alpha * (inR - lowR_);

        float lowOutL = lowL_;
        float lowOutR = lowR_;
        if (monoLow) {
            const float lowMono = 0.5f * (lowL_ + lowR_);
            lowOutL = lowMono;
            lowOutR = lowMono;
        }

        const float highL = inL - lowL_;
        const float highR = inR - lowR_;

        const float mid = 0.5f * (highL + highR);
        const float side = 0.5f * (highL - highR) * currentWidth_;

        const float outL = lowOutL + (mid + side);
        const float outR = lowOutR + (mid - side);

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }

        const float corrSmooth = 0.001f;
        corrNum_ += corrSmooth * ((outL * outR) - corrNum_);
        corrDenL_ += corrSmooth * ((outL * outL) - corrDenL_);
        corrDenR_ += corrSmooth * ((outR * outR) - corrDenR_);
    }

    const float denom = std::sqrt(std::max(1.0e-9f, corrDenL_ * corrDenR_));
    const float corr = juce::jlimit(-1.0f, 1.0f, corrNum_ / denom);
    correlation_.store(corr, std::memory_order_release);
}

} // namespace dsp_primitives

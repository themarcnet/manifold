#include "dsp/core/nodes/ShimmerNode.h"

#include <cmath>

namespace dsp_primitives {

ShimmerNode::ShimmerNode() = default;

void ShimmerNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const int maxSeconds = 3;
    bufferSize_ = static_cast<int>(sampleRate_ * maxSeconds) + std::max(16, maxBlockSize);
    buffer_.setSize(2, bufferSize_, false, true, true);
    buffer_.clear();
    writeIndex_ = 0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentSize_ = targetSize_.load(std::memory_order_acquire);
    currentPitchSemitones_ = targetPitchSemitones_.load(std::memory_order_acquire);
    currentFeedback_ = targetFeedback_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentModulation_ = targetModulation_.load(std::memory_order_acquire);
    currentFilterHz_ = targetFilterHz_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void ShimmerNode::reset() {
    buffer_.clear();
    writeIndex_ = 0;
    readPos_[0] = 0.0f;
    readPos_[1] = 0.0f;
    filterState_[0] = 0.0f;
    filterState_[1] = 0.0f;
    lfoPhase_ = 0.0f;
}

float ShimmerNode::readDelay(int channel, float pos) const {
    float wrapped = pos;
    while (wrapped < 0.0f) wrapped += static_cast<float>(bufferSize_);
    while (wrapped >= static_cast<float>(bufferSize_)) wrapped -= static_cast<float>(bufferSize_);

    const int i0 = static_cast<int>(wrapped);
    const int i1 = (i0 + 1) % bufferSize_;
    const float frac = wrapped - static_cast<float>(i0);
    const float a = buffer_.getSample(channel, i0);
    const float b = buffer_.getSample(channel, i1);
    return a + (b - a) * frac;
}

void ShimmerNode::process(const std::vector<AudioBufferView>& inputs,
                          std::vector<WritableAudioBufferView>& outputs,
                          int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }

    const float tSize = targetSize_.load(std::memory_order_acquire);
    const float tPitch = targetPitchSemitones_.load(std::memory_order_acquire);
    const float tFb = targetFeedback_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);
    const float tMod = targetModulation_.load(std::memory_order_acquire);
    const float tFilter = targetFilterHz_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentSize_ += (tSize - currentSize_) * smooth_;
        currentPitchSemitones_ += (tPitch - currentPitchSemitones_) * smooth_;
        currentFeedback_ += (tFb - currentFeedback_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;
        currentModulation_ += (tMod - currentModulation_) * smooth_;
        currentFilterHz_ += (tFilter - currentFilterHz_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        const float baseDelay = (0.05f + 1.45f * currentSize_) * static_cast<float>(sampleRate_);
        lfoPhase_ += 0.19f / static_cast<float>(sampleRate_);
        if (lfoPhase_ >= 1.0f) lfoPhase_ -= 1.0f;
        const float mod = std::sin(2.0f * juce::MathConstants<float>::pi * lfoPhase_) * currentModulation_ * 0.08f * static_cast<float>(sampleRate_);

        const float pitchRatio = std::pow(2.0f, currentPitchSemitones_ / 12.0f);

        float wetL = 0.0f;
        float wetR = 0.0f;

        for (int ch = 0; ch < 2; ++ch) {
            const float in = ch == 0 ? inL : inR;
            const float delaySamples = baseDelay + (ch == 0 ? mod : -mod);

            if (readPos_[static_cast<size_t>(ch)] == 0.0f) {
                readPos_[static_cast<size_t>(ch)] = static_cast<float>(writeIndex_) - delaySamples;
            }

            float pitched = readDelay(ch, readPos_[static_cast<size_t>(ch)]);
            readPos_[static_cast<size_t>(ch)] += pitchRatio;
            if (readPos_[static_cast<size_t>(ch)] >= static_cast<float>(bufferSize_)) {
                readPos_[static_cast<size_t>(ch)] -= static_cast<float>(bufferSize_);
            }

            const float a = juce::jlimit(0.0001f, 0.9999f,
                2.0f * juce::MathConstants<float>::pi * currentFilterHz_ /
                (2.0f * juce::MathConstants<float>::pi * currentFilterHz_ + static_cast<float>(sampleRate_)));
            filterState_[static_cast<size_t>(ch)] += a * (pitched - filterState_[static_cast<size_t>(ch)]);
            const float feedbackSample = filterState_[static_cast<size_t>(ch)] * currentFeedback_;

            buffer_.setSample(ch, writeIndex_, in + feedbackSample);

            if (ch == 0) wetL = pitched;
            else wetR = pitched;
        }

        writeIndex_ = (writeIndex_ + 1) % bufferSize_;

        const float dry = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dry + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dry + wetR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

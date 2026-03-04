#include "dsp/core/nodes/MultitapDelayNode.h"

#include <cmath>

namespace dsp_primitives {

MultitapDelayNode::MultitapDelayNode() {
    for (int i = 0; i < kMaxTaps; ++i) {
        targetTapTimeMs_[static_cast<size_t>(i)].store(120.0f * (i + 1), std::memory_order_release);
        targetTapGain_[static_cast<size_t>(i)].store(0.5f / static_cast<float>(i + 1), std::memory_order_release);
        targetTapPan_[static_cast<size_t>(i)].store((i % 2 == 0) ? -0.5f : 0.5f, std::memory_order_release);
    }
}

void MultitapDelayNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const int maxSeconds = 4;
    bufferSize_ = static_cast<int>(sampleRate_ * maxSeconds) + std::max(16, maxBlockSize);
    buffer_.setSize(2, bufferSize_, false, true, true);
    buffer_.clear();
    writeIndex_ = 0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentFeedback_ = targetFeedback_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    prepared_ = true;
}

void MultitapDelayNode::reset() {
    buffer_.clear();
    writeIndex_ = 0;
}

void MultitapDelayNode::setTapTime(int index, float ms) {
    const int i = juce::jlimit(1, kMaxTaps, index) - 1;
    targetTapTimeMs_[static_cast<size_t>(i)].store(juce::jlimit(1.0f, 3000.0f, ms), std::memory_order_release);
}

void MultitapDelayNode::setTapGain(int index, float gain) {
    const int i = juce::jlimit(1, kMaxTaps, index) - 1;
    targetTapGain_[static_cast<size_t>(i)].store(juce::jlimit(0.0f, 1.0f, gain), std::memory_order_release);
}

void MultitapDelayNode::setTapPan(int index, float pan) {
    const int i = juce::jlimit(1, kMaxTaps, index) - 1;
    targetTapPan_[static_cast<size_t>(i)].store(juce::jlimit(-1.0f, 1.0f, pan), std::memory_order_release);
}

float MultitapDelayNode::readDelay(int channel, float delaySamples) const {
    float readPos = static_cast<float>(writeIndex_) - delaySamples;
    while (readPos < 0.0f) readPos += static_cast<float>(bufferSize_);
    while (readPos >= static_cast<float>(bufferSize_)) readPos -= static_cast<float>(bufferSize_);

    const int i0 = static_cast<int>(readPos);
    const int i1 = (i0 + 1) % bufferSize_;
    const float frac = readPos - static_cast<float>(i0);
    const float a = buffer_.getSample(channel, i0);
    const float b = buffer_.getSample(channel, i1);
    return a + (b - a) * frac;
}

void MultitapDelayNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }

    const int tapCount = targetTapCount_.load(std::memory_order_acquire);
    const float tFeedback = targetFeedback_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentFeedback_ += (tFeedback - currentFeedback_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float wetL = 0.0f;
        float wetR = 0.0f;

        for (int t = 0; t < tapCount; ++t) {
            const float tapMs = targetTapTimeMs_[static_cast<size_t>(t)].load(std::memory_order_acquire);
            const float tapGain = targetTapGain_[static_cast<size_t>(t)].load(std::memory_order_acquire);
            const float tapPan = targetTapPan_[static_cast<size_t>(t)].load(std::memory_order_acquire);

            const float delaySamples = tapMs * 0.001f * static_cast<float>(sampleRate_);
            const float dL = readDelay(0, delaySamples);
            const float dR = readDelay(1, delaySamples);
            const float tapMono = 0.5f * (dL + dR) * tapGain;

            const float panL = std::sqrt(0.5f * (1.0f - tapPan));
            const float panR = std::sqrt(0.5f * (1.0f + tapPan));

            wetL += tapMono * panL;
            wetR += tapMono * panR;
        }

        const float feedbackWriteL = inL + wetL * currentFeedback_;
        const float feedbackWriteR = inR + wetR * currentFeedback_;

        buffer_.setSample(0, writeIndex_, feedbackWriteL);
        buffer_.setSample(1, writeIndex_, feedbackWriteR);
        writeIndex_ = (writeIndex_ + 1) % bufferSize_;

        const float dry = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dry + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dry + wetR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

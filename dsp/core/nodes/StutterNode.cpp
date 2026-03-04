#include "dsp/core/nodes/StutterNode.h"

#include <cmath>

namespace dsp_primitives {

StutterNode::StutterNode() = default;

void StutterNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const int maxSeconds = 8;
    bufferSize_ = static_cast<int>(sampleRate_ * maxSeconds) + std::max(16, maxBlockSize);
    buffer_.setSize(2, bufferSize_, false, true, true);
    buffer_.clear();
    writeIndex_ = 0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentLengthBeats_ = targetLengthBeats_.load(std::memory_order_acquire);
    currentGate_ = targetGate_.load(std::memory_order_acquire);
    currentFilterDecay_ = targetFilterDecay_.load(std::memory_order_acquire);
    currentPitchDecay_ = targetPitchDecay_.load(std::memory_order_acquire);
    currentProbability_ = targetProbability_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void StutterNode::reset() {
    buffer_.clear();
    writeIndex_ = 0;
    stutterActive_ = false;
    segmentLengthSamples_ = 1;
    segmentAge_ = 0;
    readStart_ = 0;
    stepCounter_ = 0;
    lpL_ = 0.0f;
    lpR_ = 0.0f;
}

void StutterNode::process(const std::vector<AudioBufferView>& inputs,
                          std::vector<WritableAudioBufferView>& outputs,
                          int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tLength = targetLengthBeats_.load(std::memory_order_acquire);
    const float tGate = targetGate_.load(std::memory_order_acquire);
    const float tFilterDecay = targetFilterDecay_.load(std::memory_order_acquire);
    const float tPitchDecay = targetPitchDecay_.load(std::memory_order_acquire);
    const float tProb = targetProbability_.load(std::memory_order_acquire);
    const int pattern = targetPatternMask_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);
    const float bpm = tempoBpm_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentLengthBeats_ += (tLength - currentLengthBeats_) * smooth_;
        currentGate_ += (tGate - currentGate_) * smooth_;
        currentFilterDecay_ += (tFilterDecay - currentFilterDecay_) * smooth_;
        currentPitchDecay_ += (tPitchDecay - currentPitchDecay_) * smooth_;
        currentProbability_ += (tProb - currentProbability_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        buffer_.setSample(0, writeIndex_, inL);
        buffer_.setSample(1, writeIndex_, inR);

        segmentLengthSamples_ = std::max(8, static_cast<int>((60.0f / std::max(20.0f, bpm)) * currentLengthBeats_ * sampleRate_));

        if (segmentAge_ <= 0) {
            const bool patternOn = ((pattern >> (stepCounter_ & 7)) & 1) != 0;
            const bool randomOn = random_.nextFloat() <= currentProbability_;
            stutterActive_ = patternOn && randomOn;
            readStart_ = writeIndex_;
            segmentAge_ = segmentLengthSamples_;
            ++stepCounter_;
        }

        float wetL = inL;
        float wetR = inR;

        if (stutterActive_) {
            const int elapsed = segmentLengthSamples_ - segmentAge_;
            const int gatedLength = std::max(1, static_cast<int>(segmentLengthSamples_ * currentGate_));
            if (elapsed < gatedLength) {
                const float progress = static_cast<float>(elapsed) / static_cast<float>(segmentLengthSamples_);
                const float pitchFactor = std::max(0.5f, 1.0f - currentPitchDecay_ * progress);
                const float readOffset = static_cast<float>(elapsed) * pitchFactor;
                int idx = readStart_ - static_cast<int>(readOffset);
                while (idx < 0) {
                    idx += bufferSize_;
                }
                idx %= bufferSize_;

                wetL = buffer_.getSample(0, idx);
                wetR = buffer_.getSample(1, idx);

                const float decay = 1.0f - currentFilterDecay_ * progress;
                lpL_ += 0.2f * ((wetL * decay) - lpL_);
                lpR_ += 0.2f * ((wetR * decay) - lpR_);
                wetL = lpL_;
                wetR = lpR_;
            } else {
                wetL = 0.0f;
                wetR = 0.0f;
            }
        }

        const float dryMix = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dryMix + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dryMix + wetR * currentMix_);
        }

        writeIndex_ = (writeIndex_ + 1) % bufferSize_;
        --segmentAge_;
    }
}

} // namespace dsp_primitives

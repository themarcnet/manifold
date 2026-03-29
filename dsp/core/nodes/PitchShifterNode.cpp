#include "dsp/core/nodes/PitchShifterNode.h"

#include <cmath>

namespace dsp_primitives {

namespace {
inline void copyDryToOutput(const AudioBufferView& input,
                            WritableAudioBufferView& output,
                            int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        const float inL = input.getSample(0, i);
        const float inR = input.numChannels > 1 ? input.getSample(1, i) : inL;
        output.setSample(0, i, inL);
        if (output.numChannels > 1) {
            output.setSample(1, i, inR);
        }
    }
}
}

PitchShifterNode::PitchShifterNode() = default;

void PitchShifterNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const int maxSeconds = 2;
    delayBufferSize_ = static_cast<int>(sampleRate_ * maxSeconds) + std::max(64, maxBlockSize);
    delayBuffer_.setSize(2, delayBufferSize_, false, true, true);
    delayBuffer_.clear();

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentPitchSemitones_ = targetPitchSemitones_.load(std::memory_order_acquire);
    currentWindowMs_ = targetWindowMs_.load(std::memory_order_acquire);
    currentFeedback_ = targetFeedback_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void PitchShifterNode::reset() {
    delayBuffer_.clear();
    writeIndex_ = 0;

    const float windowSamples = juce::jlimit(32.0f,
                                             static_cast<float>(delayBufferSize_ / 4),
                                             currentWindowMs_ * 0.001f * static_cast<float>(sampleRate_));

    for (int ch = 0; ch < 2; ++ch) {
        heads_[static_cast<size_t>(ch)][0].age = 0.0f;
        heads_[static_cast<size_t>(ch)][1].age = windowSamples * 0.5f;

        heads_[static_cast<size_t>(ch)][0].readPos =
            static_cast<float>(writeIndex_) - windowSamples;
        heads_[static_cast<size_t>(ch)][1].readPos =
            static_cast<float>(writeIndex_) - windowSamples * 0.5f;
    }
}

float PitchShifterNode::readDelay(int channel, float pos) const {
    float wrapped = pos;
    while (wrapped < 0.0f) wrapped += static_cast<float>(delayBufferSize_);
    while (wrapped >= static_cast<float>(delayBufferSize_)) wrapped -= static_cast<float>(delayBufferSize_);

    const int i0 = static_cast<int>(wrapped);
    const int i1 = (i0 + 1) % delayBufferSize_;
    const float frac = wrapped - static_cast<float>(i0);

    const float a = delayBuffer_.getSample(channel, i0);
    const float b = delayBuffer_.getSample(channel, i1);
    return a + (b - a) * frac;
}

float PitchShifterNode::triangularWindow(float t) {
    const float x = juce::jlimit(0.0f, 1.0f, t);
    return 1.0f - std::abs(2.0f * x - 1.0f);
}

void PitchShifterNode::process(const std::vector<AudioBufferView>& inputs,
                               std::vector<WritableAudioBufferView>& outputs,
                               int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tPitch = targetPitchSemitones_.load(std::memory_order_acquire);
    const float tWindowMs = targetWindowMs_.load(std::memory_order_acquire);
    const float tFeedback = targetFeedback_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    const bool dormant = tMix <= 1.0e-4f
        && currentMix_ <= 1.0e-4f
        && tFeedback <= 1.0e-4f
        && currentFeedback_ <= 1.0e-4f;
    if (dormant) {
        if (!dormantBypass_) {
            reset();
            dormantBypass_ = true;
        }
        copyDryToOutput(inputs[0], outputs[0], numSamples);
        return;
    }
    if (dormantBypass_) {
        reset();
        dormantBypass_ = false;
    }

    for (int i = 0; i < numSamples; ++i) {
        currentPitchSemitones_ += (tPitch - currentPitchSemitones_) * smooth_;
        currentWindowMs_ += (tWindowMs - currentWindowMs_) * smooth_;
        currentFeedback_ += (tFeedback - currentFeedback_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float windowSamples = juce::jlimit(32.0f,
                                                 static_cast<float>(delayBufferSize_ / 4),
                                                 currentWindowMs_ * 0.001f * static_cast<float>(sampleRate_));
        const float pitchRatio = std::pow(2.0f, currentPitchSemitones_ / 12.0f);

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float wetL = 0.0f;
        float wetR = 0.0f;

        for (int ch = 0; ch < 2; ++ch) {
            const float in = ch == 0 ? inL : inR;
            float wet = 0.0f;
            float gainSum = 0.0f;

            for (int h = 0; h < 2; ++h) {
                auto& head = heads_[static_cast<size_t>(ch)][static_cast<size_t>(h)];

                if (head.age >= windowSamples) {
                    head.age -= windowSamples;
                    head.readPos = static_cast<float>(writeIndex_) - windowSamples;
                }

                const float normAge = head.age / windowSamples;
                const float env = triangularWindow(normAge);
                const float s = readDelay(ch, head.readPos);

                wet += s * env;
                gainSum += env;

                head.readPos += pitchRatio;
                while (head.readPos >= static_cast<float>(delayBufferSize_)) {
                    head.readPos -= static_cast<float>(delayBufferSize_);
                }
                while (head.readPos < 0.0f) {
                    head.readPos += static_cast<float>(delayBufferSize_);
                }

                head.age += 1.0f;
            }

            if (gainSum > 0.0001f) {
                wet /= gainSum;
            }

            delayBuffer_.setSample(ch, writeIndex_, in + wet * currentFeedback_);

            if (ch == 0) {
                wetL = wet;
            } else {
                wetR = wet;
            }
        }

        writeIndex_ = (writeIndex_ + 1) % delayBufferSize_;

        const float dry = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dry + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dry + wetR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

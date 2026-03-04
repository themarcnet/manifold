#include "dsp/core/nodes/PitchDetectorNode.h"

#include <cmath>

namespace dsp_primitives {

PitchDetectorNode::PitchDetectorNode() = default;

void PitchDetectorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    reset();
    prepared_ = true;
}

void PitchDetectorNode::reset() {
    lastSample_ = 0.0f;
    samplesSinceCross_ = 0;
    smoothedPitch_ = 0.0f;
    pitchHz_.store(0.0f, std::memory_order_release);
    confidence_.store(0.0f, std::memory_order_release);
}

void PitchDetectorNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    float minFreq = targetMinFreq_.load(std::memory_order_acquire);
    float maxFreq = targetMaxFreq_.load(std::memory_order_acquire);
    if (maxFreq < minFreq) {
        std::swap(maxFreq, minFreq);
    }

    const int minPeriod = juce::jmax(1, static_cast<int>(sampleRate_ / maxFreq));
    const int maxPeriod = juce::jmax(minPeriod + 1, static_cast<int>(sampleRate_ / minFreq));
    const float sensitivity = targetSensitivity_.load(std::memory_order_acquire);
    const float smoothing = targetSmoothing_.load(std::memory_order_acquire);

    float confidence = confidence_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;
        const float x = 0.5f * (inL + inR);

        outputs[0].setSample(0, i, inL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR);
        }

        ++samplesSinceCross_;

        const bool crossing = (lastSample_ <= 0.0f && x > 0.0f && std::abs(x - lastSample_) >= sensitivity);
        lastSample_ = x;

        if (!crossing) {
            continue;
        }

        if (samplesSinceCross_ < minPeriod || samplesSinceCross_ > maxPeriod) {
            confidence *= 0.98f;
            continue;
        }

        const float instantPitch = static_cast<float>(sampleRate_) / static_cast<float>(samplesSinceCross_);
        if (smoothedPitch_ <= 0.0f) {
            smoothedPitch_ = instantPitch;
        } else {
            smoothedPitch_ = smoothedPitch_ * smoothing + instantPitch * (1.0f - smoothing);
        }

        pitchHz_.store(smoothedPitch_, std::memory_order_release);
        confidence = juce::jlimit(0.0f, 1.0f, confidence * 0.9f + 0.1f);
        samplesSinceCross_ = 0;
    }

    confidence_.store(confidence, std::memory_order_release);
}

} // namespace dsp_primitives

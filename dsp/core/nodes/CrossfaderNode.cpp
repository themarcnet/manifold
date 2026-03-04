#include "dsp/core/nodes/CrossfaderNode.h"

#include <cmath>

namespace dsp_primitives {

CrossfaderNode::CrossfaderNode() = default;

void CrossfaderNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentPosition_ = targetPosition_.load(std::memory_order_acquire);
    currentCurve_ = targetCurve_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    prepared_ = true;
}

void CrossfaderNode::reset() {
    // no internal state
}

void CrossfaderNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (!prepared_ || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    // Expect 2 stereo busses encoded as 4 input views (bus0 duplicated for ch0/ch1, bus1 duplicated).
    // If only one bus is connected or runtime doesn't provide it, fall back to bus0 passthrough.
    const bool hasBusB = inputs.size() >= 3; // inputs[2] should exist when bus1 is available

    const float tPos = targetPosition_.load(std::memory_order_acquire);
    const float tCurve = targetCurve_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentPosition_ += (tPos - currentPosition_) * smooth_;
        currentCurve_ += (tCurve - currentCurve_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float t = juce::jlimit(0.0f, 1.0f, 0.5f * (currentPosition_ + 1.0f));

        // Linear and equal-power gains
        const float linA = 1.0f - t;
        const float linB = t;
        const float epA = std::cos(0.5f * juce::MathConstants<float>::pi * t);
        const float epB = std::sin(0.5f * juce::MathConstants<float>::pi * t);

        const float curve = juce::jlimit(0.0f, 1.0f, currentCurve_);
        const float gainA = linA * (1.0f - curve) + epA * curve;
        const float gainB = linB * (1.0f - curve) + epB * curve;

        const float inAL = !inputs.empty() ? inputs[0].getSample(0, i) : 0.0f;
        const float inAR = (!inputs.empty() && inputs[0].numChannels > 1) ? inputs[0].getSample(1, i) : inAL;

        float inBL = 0.0f;
        float inBR = 0.0f;
        if (hasBusB) {
            inBL = inputs[2].getSample(0, i);
            inBR = inputs[2].numChannels > 1 ? inputs[2].getSample(1, i) : inBL;
        }

        const float xL = inAL * gainA + inBL * gainB;
        const float xR = inAR * gainA + inBR * gainB;

        const float dry = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inAL * dry + xL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inAR * dry + xR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

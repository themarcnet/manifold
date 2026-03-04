#include "dsp/core/nodes/DistortionNode.h"

#include <cmath>

namespace dsp_primitives {

DistortionNode::DistortionNode() = default;

void DistortionNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothingTimeSeconds = 0.015;
    smoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sr)));
    smoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, smoothingCoeff_);

    drive_ = targetDrive_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);
    output_ = targetOutput_.load(std::memory_order_acquire);
}

void DistortionNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    const float targetDrive = targetDrive_.load(std::memory_order_acquire);
    const float targetMix = targetMix_.load(std::memory_order_acquire);
    const float targetOutput = targetOutput_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        drive_ += (targetDrive - drive_) * smoothingCoeff_;
        mix_ += (targetMix - mix_) * smoothingCoeff_;
        output_ += (targetOutput - output_) * smoothingCoeff_;

        const float dry = 1.0f - mix_;
        const float wet = mix_;

        for (int ch = 0; ch < 2; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            const float in = inputs[idx].getSample(ch, i);
            const float shaped = std::tanh(in * drive_);
            float out = (in * dry + shaped * wet) * output_;
            out = juce::jlimit(-1.0f, 1.0f, out);
            outputs[idx].setSample(ch, i, out);
        }
    }
}

} // namespace dsp_primitives

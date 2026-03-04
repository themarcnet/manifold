#include "dsp/core/nodes/GainNode.h"

#include <cmath>

namespace dsp_primitives {

GainNode::GainNode(int numChannels) : numChannels_(numChannels) {}

void GainNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothingTimeSeconds = 0.01;
    smoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sr)));
    smoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, smoothingCoeff_);

    currentGain_ = juce::jmax(0.0f, targetGain_.load(std::memory_order_acquire));
}

void GainNode::process(const std::vector<AudioBufferView>& inputs,
                       std::vector<WritableAudioBufferView>& outputs,
                       int numSamples) {
    const float requestedGain = juce::jmax(0.0f, targetGain_.load(std::memory_order_acquire));
    const float target = muted_.load(std::memory_order_acquire) ? 0.0f : requestedGain;

    const int channels = juce::jmin(numChannels_, static_cast<int>(inputs.size()),
                                    static_cast<int>(outputs.size()));
    for (int i = 0; i < numSamples; ++i) {
        currentGain_ += (target - currentGain_) * smoothingCoeff_;

        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            outputs[idx].setSample(ch, i, inputs[idx].getSample(ch, i) * currentGain_);
        }
    }
}

void GainNode::setGain(float gain) {
    targetGain_.store(juce::jmax(0.0f, gain), std::memory_order_release);
}

float GainNode::getGain() const {
    return targetGain_.load(std::memory_order_acquire);
}

void GainNode::setMuted(bool muted) {
    muted_.store(muted, std::memory_order_release);
}

bool GainNode::isMuted() const {
    return muted_.load(std::memory_order_acquire);
}

} // namespace dsp_primitives

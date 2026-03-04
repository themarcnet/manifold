#include "dsp/core/nodes/CompressorNode.h"

#include <cmath>

namespace dsp_primitives {

CompressorNode::CompressorNode() = default;

void CompressorNode::setMode(int mode) {
    mode_ = mode;
}

void CompressorNode::setDetectorMode(int mode) {
    detectorMode_ = mode;
}

void CompressorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    
    const float attackTime = targetAttack_.load(std::memory_order_acquire) * 0.001f;
    const float releaseTime = targetRelease_.load(std::memory_order_acquire) * 0.001f;
    
    attackCoeff_ = std::exp(-1.0f / (static_cast<float>(sampleRate_) * attackTime));
    releaseCoeff_ = std::exp(-1.0f / (static_cast<float>(sampleRate_) * releaseTime));
    
    attackCoeff_ = juce::jlimit(0.0001f, 0.9999f, attackCoeff_);
    releaseCoeff_ = juce::jlimit(0.0001f, 0.9999f, releaseCoeff_);

    currentThreshold_ = targetThreshold_.load(std::memory_order_acquire);
    currentRatio_ = targetRatio_.load(std::memory_order_acquire);
    currentKnee_ = targetKnee_.load(std::memory_order_acquire);
    currentMakeup_ = targetMakeup_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
}

void CompressorNode::reset() {
    envelope_ = 0.0f;
    gainReduction_.store(0.0f, std::memory_order_release);
}

void CompressorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    const int channels = juce::jmin(2, static_cast<int>(inputs.size()), static_cast<int>(outputs.size()));
    if (channels <= 0) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    const float threshold = targetThreshold_.load(std::memory_order_acquire);
    const float ratio = targetRatio_.load(std::memory_order_acquire);
    const float makeup = targetMakeup_.load(std::memory_order_acquire);
    const float mix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const float input = inputs[ch].getSample(ch, i);
            const float level = std::abs(input);
            
            const float overThreshold = level > 0.0f ? 20.0f * std::log10(level) - threshold : -100.0f;
            
            float targetReduction = 0.0f;
            if (overThreshold > 0.0f) {
                targetReduction = overThreshold * (1.0f - 1.0f / ratio);
            }
            
            if (targetReduction > envelope_) {
                envelope_ = attackCoeff_ * envelope_ + (1.0f - attackCoeff_) * targetReduction;
            } else {
                envelope_ = releaseCoeff_ * envelope_ + (1.0f - releaseCoeff_) * targetReduction;
            }
            
            const float gain = std::pow(10.0f, (-envelope_ + makeup) * 0.05f);
            const float output = input * (1.0f - mix) + input * gain * mix;
            
            outputs[ch].setSample(ch, i, output);
        }
    }
    
    gainReduction_.store(-envelope_, std::memory_order_release);
}

} // namespace dsp_primitives

#include "dsp/core/nodes/ReverbNode.h"

#include <cmath>

namespace dsp_primitives {

ReverbNode::ReverbNode() {
    params_ = reverb_.getParameters();

    targetRoomSize_.store(params_.roomSize, std::memory_order_release);
    targetDamping_.store(params_.damping, std::memory_order_release);
    targetWetLevel_.store(params_.wetLevel, std::memory_order_release);
    targetDryLevel_.store(params_.dryLevel, std::memory_order_release);
    targetWidth_.store(params_.width, std::memory_order_release);
}

void ReverbNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    reverb_.setSampleRate(sampleRate_);
    reverb_.reset();

    left_.resize(static_cast<size_t>(maxBlockSize));
    right_.resize(static_cast<size_t>(maxBlockSize));

    params_.roomSize = targetRoomSize_.load(std::memory_order_acquire);
    params_.damping = targetDamping_.load(std::memory_order_acquire);
    params_.wetLevel = targetWetLevel_.load(std::memory_order_acquire);
    params_.dryLevel = targetDryLevel_.load(std::memory_order_acquire);
    params_.width = targetWidth_.load(std::memory_order_acquire);
    reverb_.setParameters(params_);
}

void ReverbNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    if (numSamples > static_cast<int>(left_.size())) {
        outputs[0].clear();
        outputs[1].clear();
        return;
    }

    const float targetRoom = targetRoomSize_.load(std::memory_order_acquire);
    const float targetDamp = targetDamping_.load(std::memory_order_acquire);
    const float targetWet = targetWetLevel_.load(std::memory_order_acquire);
    const float targetDry = targetDryLevel_.load(std::memory_order_acquire);
    const float targetWidth = targetWidth_.load(std::memory_order_acquire);

    const double blockSeconds = static_cast<double>(numSamples) / juce::jmax(1.0, sampleRate_);
    const float blockCoeff = static_cast<float>(1.0 - std::exp(-blockSeconds / juce::jmax(0.001f, smoothingTimeSeconds_)));

    params_.roomSize += (targetRoom - params_.roomSize) * blockCoeff;
    params_.damping += (targetDamp - params_.damping) * blockCoeff;
    params_.wetLevel += (targetWet - params_.wetLevel) * blockCoeff;
    params_.dryLevel += (targetDry - params_.dryLevel) * blockCoeff;
    params_.width += (targetWidth - params_.width) * blockCoeff;
    reverb_.setParameters(params_);

    for (int i = 0; i < numSamples; ++i) {
        left_[static_cast<size_t>(i)] = inputs[0].getSample(0, i);
        right_[static_cast<size_t>(i)] = inputs[1].getSample(1, i);
    }

    reverb_.processStereo(left_.data(), right_.data(), numSamples);

    for (int i = 0; i < numSamples; ++i) {
        outputs[0].setSample(0, i, left_[static_cast<size_t>(i)]);
        outputs[1].setSample(1, i, right_[static_cast<size_t>(i)]);
    }
}

} // namespace dsp_primitives

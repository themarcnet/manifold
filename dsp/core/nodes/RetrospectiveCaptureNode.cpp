#include "dsp/core/nodes/RetrospectiveCaptureNode.h"

namespace dsp_primitives {

RetrospectiveCaptureNode::RetrospectiveCaptureNode(int numChannels)
    : numChannels_(numChannels) {}

void RetrospectiveCaptureNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    ensureBuffer(sampleRate_);
    writeOffset_.store(0, std::memory_order_release);
}

void RetrospectiveCaptureNode::process(const std::vector<AudioBufferView>& inputs,
                                       std::vector<WritableAudioBufferView>& outputs,
                                       int numSamples) {
    const int channels = juce::jmin(numChannels_, static_cast<int>(outputs.size()));
    if (channels <= 0 || numSamples <= 0) {
        return;
    }

    int write = writeOffset_.load(std::memory_order_acquire);
    for (int i = 0; i < numSamples; ++i) {
        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            float s = 0.0f;
            if (ch < static_cast<int>(inputs.size())) {
                s = inputs[idx].getSample(ch, i);
            }
            captureBuffer_.setSample(ch, write, s);
            outputs[idx].setSample(ch, i, s);
        }

        ++write;
        if (write >= captureSize_) {
            write = 0;
        }
    }

    writeOffset_.store(write, std::memory_order_release);
}

void RetrospectiveCaptureNode::setCaptureSeconds(float seconds) {
    captureSeconds_.store(juce::jlimit(1.0f, 120.0f, seconds), std::memory_order_release);
    ensureBuffer(sampleRate_);
}

float RetrospectiveCaptureNode::getCaptureSeconds() const {
    return captureSeconds_.load(std::memory_order_acquire);
}

int RetrospectiveCaptureNode::getCaptureSize() const {
    return captureSize_;
}

int RetrospectiveCaptureNode::getWriteOffset() const {
    return writeOffset_.load(std::memory_order_acquire);
}

void RetrospectiveCaptureNode::clear() {
    captureBuffer_.clear();
    writeOffset_.store(0, std::memory_order_release);
}

bool RetrospectiveCaptureNode::copyRecentToLoop(const std::shared_ptr<LoopPlaybackNode>& playback,
                                                int samplesBack,
                                                bool overdub) {
    return copyRecentToLoop(playback, samplesBack, overdub,
                            LoopPlaybackNode::OverdubLengthPolicy::LegacyRepeat);
}

bool RetrospectiveCaptureNode::copyRecentToLoop(const std::shared_ptr<LoopPlaybackNode>& playback,
                                                int samplesBack,
                                                bool overdub,
                                                LoopPlaybackNode::OverdubLengthPolicy overdubLengthPolicy) {
    if (!playback || samplesBack <= 0 || captureSize_ <= 0) {
        return false;
    }

    const int clamped = juce::jmin(samplesBack, captureSize_);
    int start = getWriteOffset() - clamped;
    while (start < 0) {
        start += captureSize_;
    }
    start %= captureSize_;

    playback->copyFromCaptureBuffer(captureBuffer_, captureSize_, start, clamped,
                                    overdub, overdubLengthPolicy);
    return true;
}

void RetrospectiveCaptureNode::ensureBuffer(float sampleRate) {
    const float seconds = getCaptureSeconds();
    const int target = juce::jmax(1, static_cast<int>(sampleRate * seconds));
    if (target == captureSize_ && captureBuffer_.getNumChannels() == numChannels_) {
        return;
    }

    captureSize_ = target;
    captureBuffer_.setSize(numChannels_, captureSize_, false, true, true);
    captureBuffer_.clear();
    writeOffset_.store(0, std::memory_order_release);
}

} // namespace dsp_primitives

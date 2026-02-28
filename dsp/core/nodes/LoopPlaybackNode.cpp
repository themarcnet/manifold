#include "dsp/core/nodes/LoopPlaybackNode.h"

#include <cmath>

namespace dsp_primitives {

namespace {

double wrapPosition(double position, int length) {
    if (length <= 0) {
        return 0.0;
    }
    while (position >= static_cast<double>(length)) {
        position -= static_cast<double>(length);
    }
    while (position < 0.0) {
        position += static_cast<double>(length);
    }
    return position;
}

} // namespace

LoopPlaybackNode::LoopPlaybackNode(int numChannels) : numChannels_(numChannels) {}

void LoopPlaybackNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 0.0 ? sampleRate : 44100.0;
    maxLoopSamples_ = juce::jmax(1, static_cast<int>(sampleRate_ * 30.0));
    loopBufferA_.setSize(numChannels_, maxLoopSamples_, false, true, true);
    loopBufferB_.setSize(numChannels_, maxLoopSamples_, false, true, true);
    loopBufferA_.clear();
    loopBufferB_.clear();
    activeLoopBufferIndex_.store(0, std::memory_order_release);

    int loopLength = juce::jlimit(1, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    loopLength_.store(loopLength, std::memory_order_release);
    readPosition_ = 0.0;
    seekCrossfadeRemaining_ = 0;
    seekCrossfadeTotal_ = 0;
    seekCrossfadeSourcePosition_ = 0.0;
    lastPosition_.store(0, std::memory_order_release);
}

void LoopPlaybackNode::process(const std::vector<AudioBufferView>& inputs,
                               std::vector<WritableAudioBufferView>& outputs,
                               int numSamples) {
    (void)inputs;
    const int channels = juce::jmin(numChannels_, static_cast<int>(outputs.size()));
    if (channels <= 0 || numSamples <= 0) {
        return;
    }

    const int loopLength = juce::jlimit(1, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    const int seek = seekRequest_.exchange(-1, std::memory_order_acq_rel);
    if (seek >= 0) {
        const double previousPos = readPosition_;
        const double nextPos = wrapPosition(static_cast<double>(seek), loopLength);
        const double jump = std::abs(nextPos - previousPos);

        if (jump > 1.0) {
            seekCrossfadeSourcePosition_ = previousPos;
            seekCrossfadeTotal_ = juce::jlimit(16, 128, seekCrossfadeSamples_);
            seekCrossfadeRemaining_ = seekCrossfadeTotal_;
        } else {
            seekCrossfadeRemaining_ = 0;
            seekCrossfadeTotal_ = 0;
        }

        readPosition_ = nextPos;
    }

    if (!playing_.load(std::memory_order_acquire)) {
        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            for (int i = 0; i < numSamples; ++i) {
                outputs[idx].setSample(ch, i, 0.0f);
            }
        }
        return;
    }

    float speed = speed_.load(std::memory_order_acquire);
    speed = juce::jlimit(0.0f, 8.0f, std::abs(speed));
    double increment = static_cast<double>(speed);
    if (reversed_.load(std::memory_order_acquire)) {
        increment = -increment;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    juce::AudioBuffer<float>& activeLoop = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;

    for (int i = 0; i < numSamples; ++i) {
        const int readIndex = juce::jlimit(0, loopLength - 1, static_cast<int>(readPosition_));
        const bool xfade = seekCrossfadeRemaining_ > 0 && seekCrossfadeTotal_ > 0;

        if (xfade) {
            const int sourceIndex = juce::jlimit(0, loopLength - 1,
                                                 static_cast<int>(seekCrossfadeSourcePosition_));
            const float t = 1.0f - static_cast<float>(seekCrossfadeRemaining_) /
                                       static_cast<float>(seekCrossfadeTotal_);

            for (int ch = 0; ch < channels; ++ch) {
                const size_t idx = static_cast<size_t>(ch);
                const float src = activeLoop.getSample(ch, sourceIndex);
                const float dst = activeLoop.getSample(ch, readIndex);
                outputs[idx].setSample(ch, i, src * (1.0f - t) + dst * t);
            }

            seekCrossfadeSourcePosition_ =
                wrapPosition(seekCrossfadeSourcePosition_ + increment, loopLength);
            --seekCrossfadeRemaining_;
            if (seekCrossfadeRemaining_ <= 0) {
                seekCrossfadeRemaining_ = 0;
                seekCrossfadeTotal_ = 0;
            }
        } else {
            for (int ch = 0; ch < channels; ++ch) {
                const size_t idx = static_cast<size_t>(ch);
                const float loopSample = activeLoop.getSample(ch, readIndex);
                outputs[idx].setSample(ch, i, loopSample);
            }
        }

        readPosition_ = wrapPosition(readPosition_ + increment, loopLength);
    }

    lastPosition_.store(static_cast<int>(readPosition_), std::memory_order_release);
}

void LoopPlaybackNode::setLoopLength(int samples) {
    const int clamped = juce::jmax(1, samples);
    loopLength_.store(clamped, std::memory_order_release);
}

int LoopPlaybackNode::getLoopLength() const {
    return loopLength_.load(std::memory_order_acquire);
}

void LoopPlaybackNode::setSpeed(float speed) {
    speed_.store(juce::jmax(0.0f, speed), std::memory_order_release);
}

float LoopPlaybackNode::getSpeed() const {
    return speed_.load(std::memory_order_acquire);
}

void LoopPlaybackNode::setReversed(bool reversed) {
    reversed_.store(reversed, std::memory_order_release);
}

bool LoopPlaybackNode::isReversed() const {
    return reversed_.load(std::memory_order_acquire);
}

void LoopPlaybackNode::play() {
    playing_.store(true, std::memory_order_release);
}

void LoopPlaybackNode::pause() {
    playing_.store(false, std::memory_order_release);
}

void LoopPlaybackNode::stop() {
    playing_.store(false, std::memory_order_release);
    readPosition_ = 0.0;
    lastPosition_.store(0, std::memory_order_release);
}

bool LoopPlaybackNode::isPlaying() const {
    return playing_.load(std::memory_order_acquire);
}

void LoopPlaybackNode::seekNormalized(float normalized) {
    const int loopLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
    const float clamped = juce::jlimit(0.0f, 1.0f, normalized);
    const int position = juce::jlimit(0, loopLength - 1,
                                      static_cast<int>(clamped * static_cast<float>(loopLength - 1)));
    seekRequest_.store(position, std::memory_order_release);
}

float LoopPlaybackNode::getNormalizedPosition() const {
    const int loopLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
    const int position = juce::jlimit(0, loopLength - 1, lastPosition_.load(std::memory_order_acquire));
    return static_cast<float>(position) / static_cast<float>(loopLength);
}

bool LoopPlaybackNode::computePeaks(int numBuckets, std::vector<float>& outPeaks) const {
    outPeaks.clear();
    if (numBuckets <= 0) {
        return false;
    }

    const int loopLength = juce::jmax(0, loopLength_.load(std::memory_order_acquire));
    if (loopLength <= 0) {
        return false;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const juce::AudioBuffer<float>& activeLoop = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;
    if (activeLoop.getNumSamples() <= 0 || activeLoop.getNumChannels() <= 0) {
        return false;
    }

    outPeaks.resize(static_cast<size_t>(numBuckets), 0.0f);
    const int bucketSize = juce::jmax(1, loopLength / numBuckets);
    const int channels = juce::jmin(numChannels_, activeLoop.getNumChannels());

    float highest = 0.0f;
    for (int x = 0; x < numBuckets; ++x) {
        const int start = juce::jmin(loopLength - 1, x * bucketSize);
        const int count = juce::jmin(bucketSize, loopLength - start);
        float peak = 0.0f;

        for (int i = 0; i < count; ++i) {
            const int idx = start + i;
            for (int ch = 0; ch < channels; ++ch) {
                peak = juce::jmax(peak, std::abs(activeLoop.getSample(ch, idx)));
            }
        }

        outPeaks[static_cast<size_t>(x)] = peak;
        highest = juce::jmax(highest, peak);
    }

    const float rescale = highest > 0.0f
                              ? juce::jmin(8.0f, juce::jmax(1.0f, 1.0f / highest))
                              : 1.0f;
    for (auto& peak : outPeaks) {
        peak = juce::jmin(1.0f, peak * rescale);
    }

    return true;
}

void LoopPlaybackNode::clearLoop() {
    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const int writeIndex = (activeIndex == 0) ? 1 : 0;
    juce::AudioBuffer<float>& writeBuffer = (writeIndex == 0) ? loopBufferA_ : loopBufferB_;
    writeBuffer.clear();
    activeLoopBufferIndex_.store(writeIndex, std::memory_order_release);
    readPosition_ = 0.0;
    lastPosition_.store(0, std::memory_order_release);
}

void LoopPlaybackNode::copyFromCaptureBuffer(const juce::AudioBuffer<float>& captureBuffer,
                                             int captureSize,
                                             int captureStartOffset,
                                             int numSamples,
                                             bool overdub,
                                             OverdubLengthPolicy overdubLengthPolicy) {
    if (captureSize <= 0 || numSamples <= 0 || captureBuffer.getNumChannels() <= 0) {
        return;
    }

    const int requestedLength = juce::jlimit(1, maxLoopSamples_, numSamples);

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const int writeIndex = (activeIndex == 0) ? 1 : 0;
    juce::AudioBuffer<float>& writeBuffer = (writeIndex == 0) ? loopBufferA_ : loopBufferB_;
    const juce::AudioBuffer<float>& activeBuffer = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;

    const int previousLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));

    int targetLength = requestedLength;
    if (overdub && previousLength > 0) {
        if (overdubLengthPolicy == OverdubLengthPolicy::CommitLengthWins) {
            targetLength = requestedLength;
        } else {
            targetLength = juce::jmax(previousLength, requestedLength);
        }
    }

    const int channels = juce::jmin(numChannels_, captureBuffer.getNumChannels(), writeBuffer.getNumChannels());
    int start = captureStartOffset;
    while (start < 0) {
        start += captureSize;
    }
    start %= captureSize;

    writeBuffer.clear();

    if (!overdub) {
        for (int ch = 0; ch < channels; ++ch) {
            for (int i = 0; i < targetLength; ++i) {
                const int src = (start + i) % captureSize;
                writeBuffer.setSample(ch, i, captureBuffer.getSample(ch, src));
            }
        }
    } else {
        for (int ch = 0; ch < channels; ++ch) {
            for (int i = 0; i < targetLength; ++i) {
                const float existing = previousLength > 0
                                           ? activeBuffer.getSample(ch, i % previousLength)
                                           : 0.0f;
                writeBuffer.setSample(ch, i, existing);
            }
        }

        for (int ch = 0; ch < channels; ++ch) {
            for (int i = 0; i < targetLength; ++i) {
                const int src = (start + (i % requestedLength)) % captureSize;
                const float sample = captureBuffer.getSample(ch, src);
                writeBuffer.addSample(ch, i, sample);
            }
        }
    }

    loopLength_.store(targetLength, std::memory_order_release);
    activeLoopBufferIndex_.store(writeIndex, std::memory_order_release);
}

} // namespace dsp_primitives

#include "dsp/core/nodes/GranulatorNode.h"

#include <cmath>

namespace dsp_primitives {

GranulatorNode::GranulatorNode() = default;

void GranulatorNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const int maxSeconds = 4;
    bufferSize_ = static_cast<int>(sampleRate_ * maxSeconds) + std::max(16, maxBlockSize);
    captureBuffer_.setSize(2, bufferSize_, false, true, true);
    captureBuffer_.clear();
    writeIndex_ = 0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentGrainSizeMs_ = targetGrainSizeMs_.load(std::memory_order_acquire);
    currentDensity_ = targetDensity_.load(std::memory_order_acquire);
    currentPosition_ = targetPosition_.load(std::memory_order_acquire);
    currentPitchSemitones_ = targetPitchSemitones_.load(std::memory_order_acquire);
    currentSpray_ = targetSpray_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    prepared_ = true;
}

void GranulatorNode::reset() {
    captureBuffer_.clear();
    writeIndex_ = 0;
    for (auto& g : grains_) {
        g = Grain{};
    }
    spawnCounter_ = 0;
}

float GranulatorNode::readRing(int channel, float pos) const {
    float wrapped = pos;
    while (wrapped < 0.0f) {
        wrapped += static_cast<float>(bufferSize_);
    }
    while (wrapped >= static_cast<float>(bufferSize_)) {
        wrapped -= static_cast<float>(bufferSize_);
    }

    const int i0 = static_cast<int>(wrapped);
    const int i1 = (i0 + 1) % bufferSize_;
    const float frac = wrapped - static_cast<float>(i0);
    const float a = captureBuffer_.getSample(channel, i0);
    const float b = captureBuffer_.getSample(channel, i1);
    return a + (b - a) * frac;
}

float GranulatorNode::envelopeValue(const Grain& g) const {
    const float t = static_cast<float>(g.age) / static_cast<float>(std::max(1, g.length));
    const int envType = envelopeType_.load(std::memory_order_acquire);
    if (envType == 1) {
        // triangle
        return 1.0f - std::abs(2.0f * t - 1.0f);
    }
    // hann
    return 0.5f - 0.5f * std::cos(2.0f * juce::MathConstants<float>::pi * t);
}

void GranulatorNode::spawnGrain() {
    for (auto& g : grains_) {
        if (g.active) {
            continue;
        }

        const float grainSamples = currentGrainSizeMs_ * 0.001f * static_cast<float>(sampleRate_);
        g.length = std::max(4, static_cast<int>(grainSamples));
        g.age = 0;
        g.increment = std::pow(2.0f, currentPitchSemitones_ / 12.0f);

        const float maxOffset = static_cast<float>(bufferSize_ - g.length - 1);
        const float baseOffset = juce::jlimit(0.0f, maxOffset, currentPosition_ * maxOffset);
        const float sprayRange = currentSpray_ * 0.2f * maxOffset;
        const float spray = (random_.nextFloat() * 2.0f - 1.0f) * sprayRange;
        const float startOffset = juce::jlimit(0.0f, maxOffset, baseOffset + spray);

        g.readPos = static_cast<float>(writeIndex_) - startOffset;
        g.active = true;
        break;
    }
}

void GranulatorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const bool freeze = freeze_.load(std::memory_order_acquire);

    const float tGrain = targetGrainSizeMs_.load(std::memory_order_acquire);
    const float tDensity = targetDensity_.load(std::memory_order_acquire);
    const float tPosition = targetPosition_.load(std::memory_order_acquire);
    const float tPitch = targetPitchSemitones_.load(std::memory_order_acquire);
    const float tSpray = targetSpray_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        currentGrainSizeMs_ += (tGrain - currentGrainSizeMs_) * smooth_;
        currentDensity_ += (tDensity - currentDensity_) * smooth_;
        currentPosition_ += (tPosition - currentPosition_) * smooth_;
        currentPitchSemitones_ += (tPitch - currentPitchSemitones_) * smooth_;
        currentSpray_ += (tSpray - currentSpray_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        if (!freeze) {
            captureBuffer_.setSample(0, writeIndex_, inL);
            captureBuffer_.setSample(1, writeIndex_, inR);
            writeIndex_ = (writeIndex_ + 1) % bufferSize_;
        }

        const int spawnInterval = std::max(1, static_cast<int>(sampleRate_ / std::max(1.0f, currentDensity_)));
        ++spawnCounter_;
        if (spawnCounter_ >= spawnInterval) {
            spawnCounter_ = 0;
            spawnGrain();
        }

        float wetL = 0.0f;
        float wetR = 0.0f;

        for (auto& g : grains_) {
            if (!g.active) {
                continue;
            }

            const float env = envelopeValue(g);
            wetL += readRing(0, g.readPos) * env;
            wetR += readRing(1, g.readPos) * env;

            g.readPos += g.increment;
            ++g.age;
            if (g.age >= g.length) {
                g.active = false;
            }
        }

        const float dryMix = 1.0f - currentMix_;
        outputs[0].setSample(0, i, inL * dryMix + wetL * currentMix_);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, inR * dryMix + wetR * currentMix_);
        }
    }
}

} // namespace dsp_primitives

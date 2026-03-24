#include "dsp/core/nodes/SineBankNode.h"

#include <algorithm>
#include <cmath>

namespace dsp_primitives {

namespace {
inline float foldToUnit(float x) {
    x = juce::jlimit(-32.0f, 32.0f, x);
    while (x > 1.0f || x < -1.0f) {
        if (x > 1.0f) {
            x = 2.0f - x;
        } else {
            x = -2.0f - x;
        }
    }
    return x;
}

inline float applyDriveTransfer(float sample, float drive, int shape) {
    const float drv = juce::jlimit(0.0f, 20.0f, drive);
    if (drv <= 0.0001f) {
        return juce::jlimit(-1.0f, 1.0f, sample);
    }

    switch (juce::jlimit(0, 3, shape)) {
        case 1: {
            const float gain = 1.0f + drv * 1.35f;
            const float normaliser = std::atan(gain);
            if (normaliser <= 1.0e-6f) {
                return juce::jlimit(-1.0f, 1.0f, sample);
            }
            return std::atan(sample * gain) / normaliser;
        }
        case 2: {
            const float gain = 1.0f + drv * 1.2f;
            return juce::jlimit(-1.0f, 1.0f, sample * gain);
        }
        case 3: {
            const float gain = 1.0f + drv * 1.1f;
            return foldToUnit(sample * gain);
        }
        case 0:
        default: {
            const float gain = 1.0f + drv * 0.85f;
            const float normaliser = std::tanh(gain);
            if (normaliser <= 1.0e-6f) {
                return juce::jlimit(-1.0f, 1.0f, sample);
            }
            return std::tanh(sample * gain) / normaliser;
        }
    }
}

inline float applyDriveShape(float sample, float drive, int shape, float bias, float mix) {
    const float drv = juce::jlimit(0.0f, 20.0f, drive);
    const float wetMix = juce::jlimit(0.0f, 1.0f, mix);
    if (drv <= 0.0001f || wetMix <= 0.0001f) {
        return juce::jlimit(-1.0f, 1.0f, sample);
    }

    const float biasOffset = juce::jlimit(-1.0f, 1.0f, bias) * 0.75f;
    const float center = applyDriveTransfer(biasOffset, drv, shape);
    const float pos = std::abs(applyDriveTransfer(1.0f + biasOffset, drv, shape) - center);
    const float neg = std::abs(applyDriveTransfer(-1.0f + biasOffset, drv, shape) - center);
    const float normaliser = std::max(1.0e-6f, std::max(pos, neg));
    const float shaped = (applyDriveTransfer(sample + biasOffset, drv, shape) - center) / normaliser;
    const float wet = juce::jlimit(-1.0f, 1.0f, shaped);
    return juce::jlimit(-1.0f, 1.0f, sample + (wet - sample) * wetMix);
}
}

SineBankNode::SineBankNode() = default;

void SineBankNode::setFrequency(float freq) {
    targetFrequency_.store(juce::jlimit(1.0f, 20000.0f, freq), std::memory_order_release);
}

void SineBankNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double freqTimeSeconds = 0.02;
    const double ampTimeSeconds = 0.01;
    const double detuneTimeSeconds = 0.012;
    const double spreadTimeSeconds = 0.012;
    const double unisonVoiceTimeSeconds = 0.008;
    freqSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (freqTimeSeconds * sampleRate_)));
    ampSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (ampTimeSeconds * sampleRate_)));
    detuneSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (detuneTimeSeconds * sampleRate_)));
    spreadSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (spreadTimeSeconds * sampleRate_)));
    unisonVoiceSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (unisonVoiceTimeSeconds * sampleRate_)));
    freqSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, freqSmoothingCoeff_);
    ampSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, ampSmoothingCoeff_);
    detuneSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, detuneSmoothingCoeff_);
    spreadSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, spreadSmoothingCoeff_);
    unisonVoiceSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, unisonVoiceSmoothingCoeff_);

    currentFrequency_ = targetFrequency_.load(std::memory_order_acquire);
    currentAmplitude_ = targetAmplitude_.load(std::memory_order_acquire);
    currentDetuneCents_ = detuneCents_.load(std::memory_order_acquire);
    currentSpread_ = stereoSpread_.load(std::memory_order_acquire);
    reset();
    prepared_ = true;
}

void SineBankNode::reset() {
    prevSyncSample_ = 0.0f;
    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        for (int i = 0; i < kMaxPartials; ++i) {
            runningPhases_[static_cast<size_t>(v)][static_cast<size_t>(i)] = partialPhaseOffsets_[static_cast<size_t>(i)];
        }
        unisonVoiceGains_[static_cast<size_t>(v)] = (v == 0) ? 1.0f : 0.0f;
    }
    lastRequestedUnison_ = 1;
}

void SineBankNode::clearPartials() {
    activePartials_.store(0, std::memory_order_release);
    referenceFundamental_.store(440.0f, std::memory_order_release);
    partialFrequencies_.fill(0.0f);
    partialAmplitudes_.fill(0.0f);
    partialPhaseOffsets_.fill(0.0f);
    partialDecayRates_.fill(0.0f);
    reset();
}

void SineBankNode::setPartial(int index, float frequency, float amplitude, float phase, float decayRate) {
    if (index < 0 || index >= kMaxPartials) {
        return;
    }

    const size_t idx = static_cast<size_t>(index);
    partialFrequencies_[idx] = juce::jlimit(0.0f, 24000.0f, frequency);
    partialAmplitudes_[idx] = juce::jmax(0.0f, amplitude);
    partialPhaseOffsets_[idx] = phase;
    partialDecayRates_[idx] = juce::jmax(0.0f, decayRate);
    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        runningPhases_[static_cast<size_t>(v)][idx] = phase;
    }
    activePartials_.store(juce::jmax(activePartials_.load(std::memory_order_acquire), index + 1), std::memory_order_release);
}

void SineBankNode::setPartials(const PartialData& data) {
    const int previousCount = activePartials_.load(std::memory_order_acquire);
    const int count = juce::jlimit(0, kMaxPartials, data.activeCount);
    referenceFundamental_.store(data.fundamental > 0.0f ? data.fundamental : 440.0f,
                                std::memory_order_release);

    for (int i = 0; i < count; ++i) {
        const size_t idx = static_cast<size_t>(i);
        partialFrequencies_[idx] = juce::jlimit(0.0f, 24000.0f, data.frequencies[idx]);
        partialAmplitudes_[idx] = juce::jmax(0.0f, data.amplitudes[idx]);
        partialPhaseOffsets_[idx] = data.phases[idx];
        partialDecayRates_[idx] = juce::jmax(0.0f, data.decayRates[idx]);

        if (i >= previousCount) {
            for (int v = 0; v < kMaxUnisonVoices; ++v) {
                runningPhases_[static_cast<size_t>(v)][idx] = partialPhaseOffsets_[idx];
            }
        }
    }

    for (int i = count; i < kMaxPartials; ++i) {
        const size_t idx = static_cast<size_t>(i);
        partialFrequencies_[idx] = 0.0f;
        partialAmplitudes_[idx] = 0.0f;
        partialPhaseOffsets_[idx] = 0.0f;
        partialDecayRates_[idx] = 0.0f;
    }

    activePartials_.store(count, std::memory_order_release);
}

PartialData SineBankNode::getPartials() const {
    PartialData out;
    out.activeCount = activePartials_.load(std::memory_order_acquire);
    out.fundamental = referenceFundamental_.load(std::memory_order_acquire);
    for (int i = 0; i < out.activeCount && i < kMaxPartials; ++i) {
        out.frequencies[static_cast<size_t>(i)] = partialFrequencies_[static_cast<size_t>(i)];
        out.amplitudes[static_cast<size_t>(i)] = partialAmplitudes_[static_cast<size_t>(i)];
        out.phases[static_cast<size_t>(i)] = partialPhaseOffsets_[static_cast<size_t>(i)];
        out.decayRates[static_cast<size_t>(i)] = partialDecayRates_[static_cast<size_t>(i)];
    }
    return out;
}

void SineBankNode::process(const std::vector<AudioBufferView>& inputs,
                           std::vector<WritableAudioBufferView>& outputs,
                           int numSamples) {
    if (outputs.empty() || numSamples <= 0 || !prepared_) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    auto& out = outputs[0];
    const bool enabled = enabled_.load(std::memory_order_acquire);
    const int active = activePartials_.load(std::memory_order_acquire);
    if (!enabled || active <= 0) {
        out.clear();
        return;
    }

    const bool syncOn = syncEnabled_.load(std::memory_order_acquire);
    const bool hasSyncInput = syncOn && !inputs.empty() && inputs[0].numChannels > 0;

    const float targetFreq = targetFrequency_.load(std::memory_order_acquire);
    const float targetAmp = targetAmplitude_.load(std::memory_order_acquire);
    const float targetSpread = stereoSpread_.load(std::memory_order_acquire);
    const int targetUnison = unisonVoices_.load(std::memory_order_acquire);
    const float targetDetuneCents = detuneCents_.load(std::memory_order_acquire);
    const float drive = drive_.load(std::memory_order_acquire);
    const int driveShape = driveShape_.load(std::memory_order_acquire);
    const float driveBias = driveBias_.load(std::memory_order_acquire);
    const float driveMix = driveMix_.load(std::memory_order_acquire);
    const float referenceFundamental = juce::jmax(1.0f, referenceFundamental_.load(std::memory_order_acquire));
    if (targetUnison > lastRequestedUnison_) {
        for (int v = lastRequestedUnison_; v < targetUnison; ++v) {
            for (int p = 0; p < kMaxPartials; ++p) {
                runningPhases_[static_cast<size_t>(v)][static_cast<size_t>(p)] =
                    runningPhases_[0][static_cast<size_t>(p)];
            }
            unisonVoiceGains_[static_cast<size_t>(v)] = 0.0f;
        }
    }
    lastRequestedUnison_ = targetUnison;

    float amplitudeSum = 0.0f;
    for (int i = 0; i < active; ++i) {
        amplitudeSum += juce::jmax(0.0f, partialAmplitudes_[static_cast<size_t>(i)]);
    }
    const float bankNormaliser = amplitudeSum > 1.0e-6f ? (1.0f / amplitudeSum) : 1.0f;

    for (int i = 0; i < numSamples; ++i) {
        if (hasSyncInput) {
            const float syncSample = inputs[0].getSample(0, i);
            if (prevSyncSample_ <= 0.0f && syncSample > 0.0f) {
                reset();
            }
            prevSyncSample_ = syncSample;
        }

        currentFrequency_ += (targetFreq - currentFrequency_) * freqSmoothingCoeff_;
        currentAmplitude_ += (targetAmp - currentAmplitude_) * ampSmoothingCoeff_;
        currentDetuneCents_ += (targetDetuneCents - currentDetuneCents_) * detuneSmoothingCoeff_;
        currentSpread_ += (targetSpread - currentSpread_) * spreadSmoothingCoeff_;
        const double pitchRatio = static_cast<double>(juce::jmax(1.0f, currentFrequency_))
            / static_cast<double>(referenceFundamental);

        float left = 0.0f;
        float right = 0.0f;
        int contributingVoices = 0;

        for (int v = 0; v < kMaxUnisonVoices; ++v) {
            const float targetVoiceGain = (v < targetUnison) ? 1.0f : 0.0f;
            unisonVoiceGains_[static_cast<size_t>(v)] +=
                (targetVoiceGain - unisonVoiceGains_[static_cast<size_t>(v)]) * unisonVoiceSmoothingCoeff_;
            const float voiceGain = unisonVoiceGains_[static_cast<size_t>(v)];
            if (voiceGain <= 1.0e-4f) {
                continue;
            }
            ++contributingVoices;

            const float voiceOffset = static_cast<float>(v) - (static_cast<float>(targetUnison - 1) * 0.5f);
            const float detuneSemitones = voiceOffset * currentDetuneCents_ / 100.0f;
            const double detuneRatio = std::pow(2.0, detuneSemitones / 12.0);

            float voiceSample = 0.0f;
            auto& phases = runningPhases_[static_cast<size_t>(v)];

            for (int p = 0; p < active; ++p) {
                const size_t idx = static_cast<size_t>(p);
                const float partialAmp = partialAmplitudes_[idx];
                if (partialAmp <= 1.0e-6f) {
                    continue;
                }

                const double baseFreq = static_cast<double>(partialFrequencies_[idx]);
                const double renderedFreq = baseFreq * pitchRatio * detuneRatio;
                if (renderedFreq <= 0.0 || renderedFreq >= (sampleRate_ * 0.5)) {
                    continue;
                }

                voiceSample += std::sin(phases[idx]) * partialAmp;

                const double phaseInc = juce::MathConstants<double>::twoPi * renderedFreq / sampleRate_;
                phases[idx] += phaseInc;
                while (phases[idx] >= juce::MathConstants<double>::twoPi) {
                    phases[idx] -= juce::MathConstants<double>::twoPi;
                }
                while (phases[idx] < 0.0) {
                    phases[idx] += juce::MathConstants<double>::twoPi;
                }
            }

            voiceSample *= bankNormaliser;
            voiceSample = applyDriveShape(voiceSample, drive, driveShape, driveBias, driveMix);
            voiceSample *= voiceGain;

            const float pan = (targetUnison > 1)
                ? juce::jlimit(0.0f, 1.0f, 0.5f + voiceOffset * (currentSpread_ / static_cast<float>(targetUnison - 1)))
                : 0.5f;
            const float leftPan = std::sqrt(1.0f - pan);
            const float rightPan = std::sqrt(pan);

            left += voiceSample * leftPan;
            right += voiceSample * rightPan;
        }

        const float unisonNormaliser = (contributingVoices > 0)
            ? (1.0f / std::sqrt(static_cast<float>(contributingVoices)))
            : 0.0f;
        left *= unisonNormaliser * currentAmplitude_;
        right *= unisonNormaliser * currentAmplitude_;

        if (out.numChannels >= 2) {
            out.setSample(0, i, left);
            out.setSample(1, i, right);
        } else {
            out.setSample(0, i, 0.5f * (left + right));
        }
    }
}

} // namespace dsp_primitives

#pragma once

#include "dsp/core/nodes/PitchDetector.h"
#include "dsp/core/nodes/SampleAnalysis.h"

#include <juce_dsp/juce_dsp.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace dsp_primitives {

class SampleAnalyzer {
public:
    struct MonoBuffer {
        std::vector<float> samples;
        int numChannels = 0;
    };

    static MonoBuffer foldToMono(const juce::AudioBuffer<float>& buffer,
                                 int numChannels,
                                 int numSamples) {
        MonoBuffer result;
        const int channels = juce::jmax(1, juce::jmin(numChannels, buffer.getNumChannels()));
        const int length = juce::jmax(0, juce::jmin(numSamples, buffer.getNumSamples()));
        result.numChannels = channels;
        result.samples.assign(static_cast<size_t>(length), 0.0f);
        if (length <= 0) {
            return result;
        }

        const float invChannels = 1.0f / static_cast<float>(channels);
        for (int i = 0; i < length; ++i) {
            float sum = 0.0f;
            for (int ch = 0; ch < channels; ++ch) {
                sum += buffer.getSample(ch, i);
            }
            result.samples[static_cast<size_t>(i)] = sum * invChannels;
        }
        return result;
    }

    static SampleAnalysis analyzeMonoBuffer(const float* samples,
                                            int numSamples,
                                            float sampleRate,
                                            int numChannels = 1) {
        SampleAnalysis analysis;
        analysis.numSamples = juce::jmax(0, numSamples);
        analysis.numChannels = juce::jmax(1, numChannels);
        analysis.sampleRate = sampleRate > 0.0f ? sampleRate : 44100.0f;

        if (!samples || numSamples <= 0) {
            analysis.isPercussive = true;
            analysis.algorithm = "none";
            return analysis;
        }

        PitchDetector detector(juce::jmax(8192, numSamples));
        detector.setSampleRate(analysis.sampleRate);
        detector.setThreshold(0.15f);
        detector.setMinFrequency(40.0f);
        detector.setMaxFrequency(4000.0f);

        const SampleAnalysisResult pitch = detector.analyzeSampleRootKey(samples, numSamples);
        analysis.midiNote = pitch.midiNote;
        analysis.frequency = pitch.frequency;
        analysis.confidence = pitch.confidence;
        analysis.pitchStability = pitch.pitchStability;
        analysis.isPercussive = pitch.isPercussive;
        analysis.attackEndSample = pitch.attackEndSample;
        analysis.analysisStartSample = pitch.analysisStartSample;
        analysis.analysisEndSample = pitch.analysisEndSample;
        analysis.algorithm = pitch.algorithm ? pitch.algorithm : "none";
        analysis.isReliable = analysis.frequency > 0.0f && !analysis.isPercussive && analysis.confidence >= 0.5f;
        if (!analysis.isReliable) {
            analysis.frequency = 0.0f;
        }

        analysis.rms = computeRMS(samples, numSamples);
        analysis.peak = computePeak(samples, numSamples);
        analysis.attackTimeMs = estimateAttackTimeMs(samples, numSamples, analysis.sampleRate);
        analysis.spectralCentroidHz = computeSpectralCentroidHz(samples, numSamples, analysis.sampleRate);
        const float nyquist = analysis.sampleRate * 0.5f;
        analysis.brightness = (nyquist > 0.0f)
            ? juce::jlimit(0.0f, 1.0f, analysis.spectralCentroidHz / nyquist)
            : 0.0f;
        return analysis;
    }

    static SampleAnalysis analyzeBuffer(const juce::AudioBuffer<float>& buffer,
                                        int numChannels,
                                        int numSamples,
                                        float sampleRate) {
        const MonoBuffer mono = foldToMono(buffer, numChannels, numSamples);
        return analyzeMonoBuffer(mono.samples.data(), static_cast<int>(mono.samples.size()), sampleRate, mono.numChannels);
    }

private:
    static float computeRMS(const float* samples, int numSamples) {
        if (!samples || numSamples <= 0) {
            return 0.0f;
        }
        double sum = 0.0;
        for (int i = 0; i < numSamples; ++i) {
            const double s = samples[i];
            sum += s * s;
        }
        return static_cast<float>(std::sqrt(sum / static_cast<double>(numSamples)));
    }

    static float computePeak(const float* samples, int numSamples) {
        if (!samples || numSamples <= 0) {
            return 0.0f;
        }
        float peak = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            peak = juce::jmax(peak, std::abs(samples[i]));
        }
        return peak;
    }

    static float estimateAttackTimeMs(const float* samples, int numSamples, float sampleRate) {
        if (!samples || numSamples <= 1 || sampleRate <= 0.0f) {
            return 0.0f;
        }

        float peak = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            peak = juce::jmax(peak, std::abs(samples[i]));
        }
        if (peak <= 1.0e-6f) {
            return 0.0f;
        }

        const int smoothingWindow = juce::jmax(1, static_cast<int>(sampleRate * 0.001f));
        std::vector<float> envelope(static_cast<size_t>(numSamples), 0.0f);
        float smoothed = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            const float magnitude = std::abs(samples[i]);
            smoothed += (magnitude - smoothed) / static_cast<float>(smoothingWindow);
            envelope[static_cast<size_t>(i)] = smoothed;
        }

        const float lowThreshold = peak * 0.1f;
        const float highThreshold = peak * 0.9f;
        int startIndex = -1;
        int endIndex = -1;
        for (int i = 0; i < numSamples; ++i) {
            const float value = envelope[static_cast<size_t>(i)];
            if (startIndex < 0 && value >= lowThreshold) {
                startIndex = i;
            }
            if (value >= highThreshold) {
                endIndex = i;
                break;
            }
        }

        if (startIndex < 0) {
            return 0.0f;
        }
        if (endIndex < 0 || endIndex < startIndex) {
            endIndex = startIndex;
        }
        return static_cast<float>(endIndex - startIndex) * 1000.0f / sampleRate;
    }

    static float computeSpectralCentroidHz(const float* samples, int numSamples, float sampleRate) {
        if (!samples || numSamples <= 0 || sampleRate <= 0.0f) {
            return 0.0f;
        }

        int fftOrder = 0;
        while ((1 << fftOrder) < numSamples && fftOrder < 16) {
            ++fftOrder;
        }
        const int fftSize = 1 << juce::jlimit(5, 16, fftOrder);
        if (fftSize <= 0) {
            return 0.0f;
        }

        std::vector<float> fftData(static_cast<size_t>(fftSize * 2), 0.0f);
        const int copyCount = juce::jmin(numSamples, fftSize);
        for (int i = 0; i < copyCount; ++i) {
            const float window = 0.5f * (1.0f - std::cos((2.0f * juce::MathConstants<float>::pi * i) /
                                                          static_cast<float>(juce::jmax(1, copyCount - 1))));
            fftData[static_cast<size_t>(i)] = samples[i] * window;
        }

        juce::dsp::FFT fft(juce::jlimit(5, 16, fftOrder));
        fft.performFrequencyOnlyForwardTransform(fftData.data());

        const int bins = fftSize / 2;
        double weighted = 0.0;
        double total = 0.0;
        for (int bin = 1; bin < bins; ++bin) {
            const double magnitude = fftData[static_cast<size_t>(bin)];
            const double frequency = (static_cast<double>(bin) * sampleRate) / static_cast<double>(fftSize);
            weighted += frequency * magnitude;
            total += magnitude;
        }

        if (total <= std::numeric_limits<double>::epsilon()) {
            return 0.0f;
        }
        return static_cast<float>(weighted / total);
    }
};

} // namespace dsp_primitives

#pragma once

#include "dsp/core/nodes/PartialData.h"
#include "dsp/core/nodes/SampleAnalysis.h"
#include "dsp/core/nodes/SampleAnalyzer.h"
#include "dsp/core/nodes/TemporalPartialData.h"

#include <juce_core/juce_core.h>
#include <juce_audio_basics/juce_audio_basics.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <vector>

namespace dsp_primitives {

class PartialsExtractor {
public:
    static PartialData extractBuffer(const juce::AudioBuffer<float>& buffer,
                                     int numChannels,
                                     int numSamples,
                                     float sampleRate,
                                     int maxPartials = PartialData::kMaxPartials) {
        const auto mono = SampleAnalyzer::foldToMono(buffer, numChannels, numSamples);
        const auto analysis = SampleAnalyzer::analyzeMonoBuffer(
            mono.samples.data(), static_cast<int>(mono.samples.size()), sampleRate, mono.numChannels);
        return extractMonoBuffer(mono.samples.data(),
                                 static_cast<int>(mono.samples.size()),
                                 sampleRate,
                                 analysis,
                                 mono.numChannels,
                                 maxPartials);
    }

    static PartialData extractMonoBuffer(const float* samples,
                                         int numSamples,
                                         float sampleRate,
                                         const SampleAnalysis& analysis,
                                         int numChannels = 1,
                                         int maxPartials = PartialData::kMaxPartials) {
        PartialData result;
        result.numSamples = juce::jmax(0, numSamples);
        result.numChannels = juce::jmax(1, numChannels);
        result.sampleRate = sampleRate > 0.0f ? sampleRate : 44100.0f;
        result.fundamental = analysis.frequency > 0.0f ? analysis.frequency : 0.0f;
        result.brightness = analysis.brightness;
        result.rmsLevel = analysis.rms;
        result.peakLevel = analysis.peak;
        result.attackTimeMs = analysis.attackTimeMs;
        result.spectralCentroidHz = analysis.spectralCentroidHz;
        result.analysisStartSample = analysis.analysisStartSample;
        result.analysisEndSample = analysis.analysisEndSample;
        result.isPercussive = analysis.isPercussive;
        result.isReliable = analysis.isReliable;
        result.algorithm = "harmonic-projection";

        if (!samples || numSamples <= 0 || result.sampleRate <= 0.0f) {
            result.algorithm = "none";
            return result;
        }

        if (!analysis.isReliable || analysis.frequency <= 0.0f) {
            return result;
        }

        const int partialLimit = juce::jlimit(1, PartialData::kMaxPartials, maxPartials);
        const int analysisStart = juce::jlimit(0, juce::jmax(0, numSamples - 1),
                                               analysis.analysisStartSample);
        const int analysisEnd = juce::jlimit(analysisStart + 1,
                                             numSamples,
                                             analysis.analysisEndSample > analysisStart
                                                 ? analysis.analysisEndSample
                                                 : numSamples);
        result.analysisStartSample = analysisStart;
        result.analysisEndSample = analysisEnd;

        const int available = analysisEnd - analysisStart;
        const int windowSize = chooseWindowSize(available);
        if (windowSize < 512) {
            return result;
        }

        const int headStart = juce::jlimit(0, numSamples - windowSize,
                                           analysisStart + juce::jmax(0, (available - windowSize) / 2));
        const int tailStart = juce::jlimit(0, numSamples - windowSize,
                                           juce::jmax(analysisStart, analysisEnd - windowSize));
        const float nyquist = result.sampleRate * 0.5f;

        struct HarmonicCandidate {
            float expectedFrequency = 0.0f;
            float measuredFrequency = 0.0f;
            float amplitude = 0.0f;
            float phase = 0.0f;
            float decayRate = 0.0f;
            int harmonicNumber = 0;
        };

        std::array<HarmonicCandidate, PartialData::kMaxPartials> candidates{};
        float strongestAmplitude = 0.0f;
        int candidateCount = 0;

        for (int i = 0; i < partialLimit; ++i) {
            const int harmonicNumber = i + 1;
            const float expectedFrequency = analysis.frequency * static_cast<float>(harmonicNumber);
            if (expectedFrequency <= 0.0f || expectedFrequency >= nyquist * 0.95f) {
                break;
            }

            HarmonicCandidate candidate;
            candidate.expectedFrequency = expectedFrequency;
            candidate.harmonicNumber = harmonicNumber;

            const Projection headProjection = scanDominantFrequency(samples + headStart,
                                                                    windowSize,
                                                                    result.sampleRate,
                                                                    expectedFrequency,
                                                                    harmonicNumber == 1 ? 0.05f : 0.035f);
            if (headProjection.amplitude <= 1.0e-5f || !std::isfinite(headProjection.amplitude)) {
                continue;
            }

            candidate.measuredFrequency = headProjection.frequency;
            candidate.amplitude = headProjection.amplitude;
            candidate.phase = headProjection.phase;

            if (tailStart > headStart) {
                const Projection tailProjection = measureProjection(samples + tailStart,
                                                                    windowSize,
                                                                    result.sampleRate,
                                                                    candidate.measuredFrequency);
                candidate.decayRate = estimateDecayRateSeconds(candidate.amplitude,
                                                               tailProjection.amplitude,
                                                               static_cast<float>(tailStart - headStart) / result.sampleRate);
            }

            candidates[static_cast<size_t>(candidateCount)] = candidate;
            strongestAmplitude = juce::jmax(strongestAmplitude, candidate.amplitude);
            ++candidateCount;
        }

        if (candidateCount <= 0 || strongestAmplitude <= 0.0f) {
            return result;
        }

        const float minAmplitude = strongestAmplitude * 0.02f;
        float inharmonicityWeighted = 0.0f;
        float inharmonicityWeight = 0.0f;

        for (int i = 0; i < candidateCount; ++i) {
            const auto& candidate = candidates[static_cast<size_t>(i)];
            if (candidate.amplitude < minAmplitude) {
                continue;
            }

            const int outIndex = result.activeCount;
            if (outIndex >= PartialData::kMaxPartials) {
                break;
            }

            result.frequencies[static_cast<size_t>(outIndex)] = candidate.measuredFrequency;
            result.amplitudes[static_cast<size_t>(outIndex)] = candidate.amplitude / strongestAmplitude;
            result.phases[static_cast<size_t>(outIndex)] = candidate.phase;
            result.decayRates[static_cast<size_t>(outIndex)] = candidate.decayRate;
            ++result.activeCount;

            if (candidate.expectedFrequency > 0.0f) {
                const float deviation = std::abs(candidate.measuredFrequency - candidate.expectedFrequency)
                    / candidate.expectedFrequency;
                inharmonicityWeighted += deviation * candidate.amplitude;
                inharmonicityWeight += candidate.amplitude;
            }
        }

        if (inharmonicityWeight > 0.0f) {
            result.inharmonicity = juce::jlimit(0.0f, 1.0f, inharmonicityWeighted / inharmonicityWeight);
        }

        if (result.activeCount <= 0) {
            result.algorithm = "harmonic-projection-empty";
        }

        return result;
    }

    /// Extract temporal (multi-frame) partial data by sliding a window across the sample.
    /// Uses the global fundamental from the full-sample analysis so we don't re-detect
    /// pitch per frame (faster, avoids jitter).
    /// @param windowSize  FFT/projection window in samples (default 2048)
    /// @param hopSize     hop between frames in samples (default 1024 = 50% overlap)
    /// @param maxFrames   cap on number of frames (default 128)
    static TemporalPartialData extractTemporalFrames(
        const float* samples,
        int numSamples,
        float sampleRate,
        const SampleAnalysis& analysis,
        int numChannels = 1,
        int maxPartials = PartialData::kMaxPartials,
        int windowSize = 2048,
        int hopSize = 1024,
        int maxFrames = 128)
    {
        TemporalPartialData result;
        result.sampleRate = sampleRate > 0.0f ? sampleRate : 44100.0f;
        result.windowSize = windowSize;
        result.hopSize = hopSize;
        result.globalFundamental = analysis.frequency;

        if (!samples || numSamples <= 0 || result.sampleRate <= 0.0f) {
            return result;
        }

        result.sampleLengthSeconds = static_cast<float>(numSamples) / result.sampleRate;

        if (!analysis.isReliable || analysis.frequency <= 0.0f) {
            // Can't do harmonic projection without a detected fundamental.
            // Still mark what we know.
            return result;
        }

        // Ensure window fits in buffer
        const int effectiveWindow = juce::jlimit(256, juce::jmax(256, numSamples), windowSize);
        const int effectiveHop = juce::jlimit(64, effectiveWindow, hopSize);

        // Calculate number of frames
        int totalFrames = 0;
        for (int offset = 0; offset + effectiveWindow <= numSamples; offset += effectiveHop) {
            ++totalFrames;
        }
        totalFrames = juce::jlimit(1, juce::jmin(maxFrames, TemporalPartialData::kMaxFrames), totalFrames);

        // If we have more potential frames than maxFrames, spread them evenly
        const int availablePositions = juce::jmax(1, (numSamples - effectiveWindow));

        result.frames.reserve(static_cast<size_t>(totalFrames));
        result.frameTimes.reserve(static_cast<size_t>(totalFrames));

        const int partialLimit = juce::jlimit(1, PartialData::kMaxPartials, maxPartials);
        const float nyquist = result.sampleRate * 0.5f;

        for (int frameIdx = 0; frameIdx < totalFrames; ++frameIdx) {
            // Position this frame
            int frameStart;
            if (totalFrames <= 1) {
                frameStart = juce::jmax(0, (numSamples - effectiveWindow) / 2);
            } else {
                frameStart = (availablePositions * frameIdx) / (totalFrames - 1);
                frameStart = juce::jlimit(0, numSamples - effectiveWindow, frameStart);
            }

            const float normalizedTime = (numSamples > effectiveWindow)
                ? static_cast<float>(frameStart) / static_cast<float>(numSamples - effectiveWindow)
                : 0.5f;

            // Project harmonics for this window using the global fundamental
            PartialData frame;
            frame.numSamples = effectiveWindow;
            frame.numChannels = juce::jmax(1, numChannels);
            frame.sampleRate = result.sampleRate;
            frame.fundamental = analysis.frequency;
            frame.isReliable = true;
            frame.algorithm = "temporal-harmonic-projection";

            float strongestAmplitude = 0.0f;
            struct FrameCandidate {
                float frequency = 0.0f;
                float amplitude = 0.0f;
                float phase = 0.0f;
            };
            std::array<FrameCandidate, PartialData::kMaxPartials> candidates{};
            int candidateCount = 0;

            for (int i = 0; i < partialLimit; ++i) {
                const int harmonicNumber = i + 1;
                const float expectedFreq = analysis.frequency * static_cast<float>(harmonicNumber);
                if (expectedFreq >= nyquist * 0.95f) break;

                // Use a tighter search for temporal frames — we already know the fundamental
                const Projection proj = scanDominantFrequency(
                    samples + frameStart,
                    effectiveWindow,
                    result.sampleRate,
                    expectedFreq,
                    harmonicNumber == 1 ? 0.03f : 0.025f);

                if (proj.amplitude <= 1.0e-5f || !std::isfinite(proj.amplitude)) continue;

                candidates[static_cast<size_t>(candidateCount)] = { proj.frequency, proj.amplitude, proj.phase };
                strongestAmplitude = juce::jmax(strongestAmplitude, proj.amplitude);
                ++candidateCount;
            }

            if (candidateCount > 0 && strongestAmplitude > 0.0f) {
                const float minAmp = strongestAmplitude * 0.02f;
                for (int i = 0; i < candidateCount; ++i) {
                    if (candidates[static_cast<size_t>(i)].amplitude < minAmp) continue;
                    const int idx = frame.activeCount;
                    if (idx >= PartialData::kMaxPartials) break;

                    frame.frequencies[static_cast<size_t>(idx)] = candidates[static_cast<size_t>(i)].frequency;
                    frame.amplitudes[static_cast<size_t>(idx)] = candidates[static_cast<size_t>(i)].amplitude / strongestAmplitude;
                    frame.phases[static_cast<size_t>(idx)] = candidates[static_cast<size_t>(i)].phase;
                    ++frame.activeCount;
                }
            }

            // Compute per-frame brightness (spectral centroid as quick metric)
            float weightedFreq = 0.0f, totalAmp = 0.0f;
            for (int i = 0; i < frame.activeCount; ++i) {
                const auto si = static_cast<size_t>(i);
                weightedFreq += frame.frequencies[si] * frame.amplitudes[si];
                totalAmp += frame.amplitudes[si];
            }
            frame.brightness = (totalAmp > 0.0f) ? (weightedFreq / totalAmp) / nyquist : 0.0f;

            // Compute per-frame RMS from the window
            float rmsSum = 0.0f;
            for (int i = 0; i < effectiveWindow; ++i) {
                const float s = samples[frameStart + i];
                rmsSum += s * s;
            }
            frame.rmsLevel = std::sqrt(rmsSum / static_cast<float>(effectiveWindow));

            result.frames.push_back(std::move(frame));
            result.frameTimes.push_back(normalizedTime);
        }

        result.frameCount = static_cast<int>(result.frames.size());
        result.isReliable = result.frameCount > 0;
        return result;
    }

    /// Convenience: extract temporal frames from a juce::AudioBuffer
    static TemporalPartialData extractTemporalBuffer(
        const juce::AudioBuffer<float>& buffer,
        int numChannels,
        int numSamples,
        float sampleRate,
        int maxPartials = PartialData::kMaxPartials,
        int windowSize = 2048,
        int hopSize = 1024,
        int maxFrames = 128)
    {
        const auto mono = SampleAnalyzer::foldToMono(buffer, numChannels, numSamples);
        const auto analysis = SampleAnalyzer::analyzeMonoBuffer(
            mono.samples.data(), static_cast<int>(mono.samples.size()), sampleRate, mono.numChannels);
        return extractTemporalFrames(
            mono.samples.data(),
            static_cast<int>(mono.samples.size()),
            sampleRate,
            analysis,
            mono.numChannels,
            maxPartials,
            windowSize,
            hopSize,
            maxFrames);
    }

private:
    struct Projection {
        float frequency = 0.0f;
        float amplitude = 0.0f;
        float phase = 0.0f;
    };

    static int chooseWindowSize(int availableSamples) {
        if (availableSamples < 512) {
            return 0;
        }

        int size = 512;
        while (size < 8192 && (size * 2) <= availableSamples) {
            size *= 2;
        }
        return size;
    }

    static Projection scanDominantFrequency(const float* samples,
                                            int numSamples,
                                            float sampleRate,
                                            float expectedFrequency,
                                            float relativeSearchWidth) {
        Projection best;
        if (!samples || numSamples <= 0 || sampleRate <= 0.0f || expectedFrequency <= 0.0f) {
            return best;
        }

        const float nyquist = sampleRate * 0.5f;
        const float searchWidth = juce::jmax(6.0f, expectedFrequency * relativeSearchWidth);
        constexpr int kSteps = 11;

        for (int step = 0; step < kSteps; ++step) {
            const float t = static_cast<float>(step) / static_cast<float>(kSteps - 1);
            const float offset = (t * 2.0f) - 1.0f;
            const float freq = juce::jlimit(20.0f, nyquist * 0.95f, expectedFrequency + searchWidth * offset);
            const Projection projection = measureProjection(samples, numSamples, sampleRate, freq);
            if (projection.amplitude > best.amplitude) {
                best = projection;
            }
        }

        return best;
    }

    static Projection measureProjection(const float* samples,
                                        int numSamples,
                                        float sampleRate,
                                        float frequency) {
        Projection result;
        result.frequency = frequency;

        if (!samples || numSamples <= 0 || sampleRate <= 0.0f || frequency <= 0.0f) {
            return result;
        }

        const double phaseInc = (juce::MathConstants<double>::twoPi * static_cast<double>(frequency))
            / static_cast<double>(sampleRate);
        double re = 0.0;
        double im = 0.0;
        double windowSum = 0.0;

        for (int i = 0; i < numSamples; ++i) {
            const double norm = static_cast<double>(i) / static_cast<double>(juce::jmax(1, numSamples - 1));
            const double window = 0.5 * (1.0 - std::cos(juce::MathConstants<double>::twoPi * norm));
            const double sample = static_cast<double>(samples[i]) * window;
            const double phase = phaseInc * static_cast<double>(i);
            re += sample * std::cos(phase);
            im -= sample * std::sin(phase);
            windowSum += window;
        }

        if (windowSum <= std::numeric_limits<double>::epsilon()) {
            return result;
        }

        const double magnitude = std::sqrt(re * re + im * im);
        result.amplitude = static_cast<float>((2.0 * magnitude) / windowSum);
        result.phase = static_cast<float>(std::atan2(im, re));
        return result;
    }

    static float estimateDecayRateSeconds(float startAmplitude,
                                          float endAmplitude,
                                          float deltaSeconds) {
        if (startAmplitude <= 1.0e-6f || endAmplitude <= 1.0e-6f || deltaSeconds <= 0.0f) {
            return 0.0f;
        }
        if (endAmplitude >= startAmplitude) {
            return 0.0f;
        }

        const float ratio = juce::jlimit(1.0e-6f, 0.999999f, endAmplitude / startAmplitude);
        const float dbDrop = -20.0f * std::log10(ratio);
        if (dbDrop <= 1.0e-3f || !std::isfinite(dbDrop)) {
            return 0.0f;
        }

        return juce::jlimit(0.0f, 60.0f, deltaSeconds * (60.0f / dbDrop));
    }
};

} // namespace dsp_primitives

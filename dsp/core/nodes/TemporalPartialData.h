#pragma once

#include "dsp/core/nodes/PartialData.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace dsp_primitives {

struct TemporalPartialData {
    static constexpr int kMaxFrames = 256;

    std::vector<PartialData> frames;
    std::vector<float> frameTimes;  // normalized 0..1 position within the sample

    float sampleRate = 44100.0f;
    float sampleLengthSeconds = 0.0f;
    float globalFundamental = 0.0f;  // detected once for whole sample
    int frameCount = 0;
    int windowSize = 2048;
    int hopSize = 1024;
    bool isReliable = false;

    void clear() {
        frames.clear();
        frameTimes.clear();
        frameCount = 0;
        globalFundamental = 0.0f;
        sampleLengthSeconds = 0.0f;
        isReliable = false;
    }

    /// Interpolate between two bracketing frames at normalized position t (0..1).
    /// smoothAmount matches the original Lua morphSmooth behaviour:
    ///   0.0 = nearest-frame stepping, 1.0 = fully smoothed glide with neighbour smear.
    /// contrastAmount matches the original Lua morphContrast shaping.
    PartialData interpolateAtPosition(float t, float smoothAmount = 0.0f, float contrastAmount = 0.5f) const {
        if (frameCount <= 0 || frames.empty() || frameTimes.empty()) {
            return {};
        }

        const int safeFrameCount = std::min(frameCount,
                                            static_cast<int>(std::min(frames.size(), frameTimes.size())));
        if (safeFrameCount <= 0) {
            return {};
        }
        if (safeFrameCount == 1) {
            return frames[0];
        }

        const float pos = std::clamp(t, 0.0f, 1.0f);
        const float smoothAmt = std::clamp(smoothAmount, 0.0f, 1.0f);
        const float contrastAmt = std::clamp(contrastAmount, 0.0f, 2.0f);

        // Find bracketing frames.
        int lo = 0;
        int hi = safeFrameCount - 1;
        for (int i = 0; i < safeFrameCount - 1; ++i) {
            if (frameTimes[static_cast<size_t>(i + 1)] > pos) {
                lo = i;
                hi = i + 1;
                break;
            }
            lo = i;
            hi = i;
        }
        if (lo == hi) {
            return frames[static_cast<size_t>(lo)];
        }

        const float loTime = frameTimes[static_cast<size_t>(lo)];
        const float hiTime = frameTimes[static_cast<size_t>(hi)];
        const float span = hiTime - loTime;
        const float rawFrac = (span > 1.0e-6f)
            ? std::clamp((pos - loTime) / span, 0.0f, 1.0f)
            : 0.0f;

        float frac = 0.0f;
        if (smoothAmt <= 0.001f) {
            frac = (rawFrac >= 0.5f) ? 1.0f : 0.0f;
        } else {
            const float edge0 = 0.5f - 0.5f * smoothAmt;
            const float edge1 = 0.5f + 0.5f * smoothAmt;
            if (rawFrac <= edge0) {
                frac = 0.0f;
            } else if (rawFrac >= edge1) {
                frac = 1.0f;
            } else {
                frac = (rawFrac - edge0) / std::max(1.0e-6f, edge1 - edge0);
                frac = frac * frac * (3.0f - 2.0f * frac); // smoothstep
            }
        }

        const auto& a = frames[static_cast<size_t>(lo)];
        const auto& b = frames[static_cast<size_t>(hi)];

        PartialData result;
        result.fundamental = a.fundamental + (b.fundamental - a.fundamental) * frac;
        result.brightness = a.brightness + (b.brightness - a.brightness) * frac;
        result.rmsLevel = a.rmsLevel + (b.rmsLevel - a.rmsLevel) * frac;
        result.sampleRate = a.sampleRate;
        result.isReliable = a.isReliable || b.isReliable;
        result.algorithm = "temporal-interp";

        const int maxCount = std::min(PartialData::kMaxPartials, std::max(a.activeCount, b.activeCount));
        result.activeCount = maxCount;

        for (int i = 0; i < maxCount; ++i) {
            const auto si = static_cast<size_t>(i);
            const float af = (i < a.activeCount) ? a.frequencies[si] : 0.0f;
            const float bf = (i < b.activeCount) ? b.frequencies[si] : 0.0f;
            const float aa = (i < a.activeCount) ? a.amplitudes[si] : 0.0f;
            const float ba = (i < b.activeCount) ? b.amplitudes[si] : 0.0f;
            const float ap = (i < a.activeCount) ? a.phases[si] : 0.0f;
            const float bp = (i < b.activeCount) ? b.phases[si] : 0.0f;
            const float ad = (i < a.activeCount) ? a.decayRates[si] : 0.0f;
            const float bd = (i < b.activeCount) ? b.decayRates[si] : 0.0f;

            float freq = 0.0f;
            if (af <= 0.01f && bf <= 0.01f) {
                freq = 0.0f;
            } else if (af <= 0.01f) {
                freq = bf * frac;
            } else if (bf <= 0.01f) {
                freq = af * (1.0f - frac);
            } else {
                freq = std::exp(std::log(af) + (std::log(bf) - std::log(af)) * frac);
            }

            const float rawAmp = aa + (ba - aa) * frac;
            const float contrastExponent = 1.15f - contrastAmt * 0.45f;
            const float contrastGain = 1.0f + contrastAmt * 0.85f;
            float contrastAmp = (rawAmp > 0.001f)
                ? (std::pow(rawAmp, contrastExponent) * contrastGain)
                : 0.0f;
            const float noiseFloor = 0.006f - contrastAmt * 0.002f;
            if (contrastAmp < noiseFloor) {
                contrastAmp = 0.0f;
            }

            result.frequencies[si] = freq;
            result.amplitudes[si] = contrastAmp;
            result.phases[si] = ap + (bp - ap) * frac;
            result.decayRates[si] = ad + (bd - ad) * frac;
        }

        if (smoothAmt > 0.001f) {
            const auto& prevFrame = frames[static_cast<size_t>(std::max(0, lo - 1))];
            const auto& nextFrame = frames[static_cast<size_t>(std::min(safeFrameCount - 1, hi + 1))];
            const float smearMix = 0.15f + smoothAmt * 0.85f;

            for (int i = 0; i < maxCount; ++i) {
                const auto si = static_cast<size_t>(i);
                const float baseAmp = result.amplitudes[si];
                const float baseFreq = result.frequencies[si];

                const float prevAmp = (i < prevFrame.activeCount) ? prevFrame.amplitudes[si] : 0.0f;
                const float nextAmp = (i < nextFrame.activeCount) ? nextFrame.amplitudes[si] : 0.0f;
                const float prevFreq = (i < prevFrame.activeCount) ? prevFrame.frequencies[si] : 0.0f;
                const float nextFreq = (i < nextFrame.activeCount) ? nextFrame.frequencies[si] : 0.0f;

                const float avgAmp = (prevAmp + baseAmp + nextAmp) / 3.0f;
                float avgFreq = baseFreq;
                if (baseFreq > 0.01f || prevFreq > 0.01f || nextFreq > 0.01f) {
                    float accum = 0.0f;
                    float weight = 0.0f;
                    if (prevFreq > 0.01f) { accum += std::log(prevFreq) * 0.75f; weight += 0.75f; }
                    if (baseFreq > 0.01f) { accum += std::log(baseFreq) * 1.5f; weight += 1.5f; }
                    if (nextFreq > 0.01f) { accum += std::log(nextFreq) * 0.75f; weight += 0.75f; }
                    if (weight > 0.0f) {
                        avgFreq = std::exp(accum / weight);
                    }
                }

                result.amplitudes[si] = baseAmp + (avgAmp - baseAmp) * smearMix;
                result.frequencies[si] = (avgFreq > 0.01f)
                    ? (baseFreq + (avgFreq - baseFreq) * smearMix)
                    : baseFreq;
            }
        }

        return result;
    }
};

} // namespace dsp_primitives

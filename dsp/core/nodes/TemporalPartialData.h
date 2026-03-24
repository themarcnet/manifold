#pragma once

#include "dsp/core/nodes/PartialData.h"

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
    /// Returns a new PartialData with lerped amplitudes and log-lerped frequencies.
    PartialData interpolateAtPosition(float t) const {
        if (frameCount <= 0 || frames.empty()) {
            return {};
        }
        if (frameCount == 1) {
            return frames[0];
        }

        const float pos = std::max(0.0f, std::min(1.0f, t));

        // Find bracketing frames
        int lo = 0;
        int hi = frameCount - 1;
        for (int i = 0; i < frameCount - 1; ++i) {
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
        const float frac = (span > 1.0e-6f) ? std::max(0.0f, std::min(1.0f, (pos - loTime) / span)) : 0.0f;

        const auto& a = frames[static_cast<size_t>(lo)];
        const auto& b = frames[static_cast<size_t>(hi)];

        PartialData result;
        result.fundamental = a.fundamental + (b.fundamental - a.fundamental) * frac;
        result.brightness = a.brightness + (b.brightness - a.brightness) * frac;
        result.rmsLevel = a.rmsLevel + (b.rmsLevel - a.rmsLevel) * frac;
        result.sampleRate = a.sampleRate;
        result.isReliable = a.isReliable || b.isReliable;
        result.algorithm = "temporal-interp";

        const int maxCount = std::max(a.activeCount, b.activeCount);
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

            // Log-frequency interpolation for musical blending
            float freq;
            if (af <= 0.01f && bf <= 0.01f) {
                freq = 0.0f;
            } else if (af <= 0.01f) {
                freq = bf * frac;  // fade in
            } else if (bf <= 0.01f) {
                freq = af * (1.0f - frac);  // fade out
            } else {
                freq = std::exp(std::log(af) + (std::log(bf) - std::log(af)) * frac);
            }

            result.frequencies[si] = freq;
            result.amplitudes[si] = aa + (ba - aa) * frac;
            result.phases[si] = ap + (bp - ap) * frac;
            result.decayRates[si] = ad + (bd - ad) * frac;
        }

        return result;
    }
};

} // namespace dsp_primitives

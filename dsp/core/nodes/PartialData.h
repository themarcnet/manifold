#pragma once

#include <array>
#include <string>

namespace dsp_primitives {

struct PartialData {
    static constexpr int kMaxPartials = 32;

    std::array<float, kMaxPartials> frequencies{};
    std::array<float, kMaxPartials> amplitudes{};
    std::array<float, kMaxPartials> phases{};
    std::array<float, kMaxPartials> decayRates{};

    int activeCount = 0;
    float fundamental = 0.0f;
    float inharmonicity = 0.0f;
    float brightness = 0.0f;
    float rmsLevel = 0.0f;
    float peakLevel = 0.0f;
    float attackTimeMs = 0.0f;
    float spectralCentroidHz = 0.0f;

    int analysisStartSample = 0;
    int analysisEndSample = 0;
    int numSamples = 0;
    int numChannels = 1;
    float sampleRate = 44100.0f;

    bool isPercussive = false;
    bool isReliable = false;
    std::string algorithm{"none"};
};

} // namespace dsp_primitives

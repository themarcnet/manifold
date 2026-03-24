#pragma once

#include <string>

namespace dsp_primitives {

struct SampleAnalysis {
    int midiNote = 60;
    float frequency = 261.63f;
    float confidence = 0.0f;
    float pitchStability = 0.0f;
    bool isPercussive = false;
    bool isReliable = false;

    float rms = 0.0f;
    float peak = 0.0f;
    float attackTimeMs = 0.0f;
    int attackEndSample = 0;

    float spectralCentroidHz = 0.0f;
    float brightness = 0.0f;

    int analysisStartSample = 0;
    int analysisEndSample = 0;
    int numSamples = 0;
    int numChannels = 1;
    float sampleRate = 44100.0f;

    std::string algorithm{"none"};
};

} // namespace dsp_primitives

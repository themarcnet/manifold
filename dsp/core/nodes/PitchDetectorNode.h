#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class PitchDetectorNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<PitchDetectorNode> {
public:
    PitchDetectorNode();

    const char* getNodeType() const override { return "PitchDetector"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setMinFreq(float hz) { targetMinFreq_.store(juce::jlimit(20.0f, 2000.0f, hz), std::memory_order_release); }
    void setMaxFreq(float hz) { targetMaxFreq_.store(juce::jlimit(40.0f, 8000.0f, hz), std::memory_order_release); }
    void setSensitivity(float threshold) { targetSensitivity_.store(juce::jlimit(0.001f, 1.0f, threshold), std::memory_order_release); }
    void setSmoothing(float smoothing) { targetSmoothing_.store(juce::jlimit(0.0f, 1.0f, smoothing), std::memory_order_release); }

    float getMinFreq() const { return targetMinFreq_.load(std::memory_order_acquire); }
    float getMaxFreq() const { return targetMaxFreq_.load(std::memory_order_acquire); }
    float getSensitivity() const { return targetSensitivity_.load(std::memory_order_acquire); }
    float getSmoothing() const { return targetSmoothing_.load(std::memory_order_acquire); }
    float getPitch() const { return pitchHz_.load(std::memory_order_acquire); }
    float getConfidence() const { return confidence_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetMinFreq_{60.0f};
    std::atomic<float> targetMaxFreq_{1200.0f};
    std::atomic<float> targetSensitivity_{0.02f};
    std::atomic<float> targetSmoothing_{0.85f};

    std::atomic<float> pitchHz_{0.0f};
    std::atomic<float> confidence_{0.0f};

    float lastSample_ = 0.0f;
    int samplesSinceCross_ = 0;
    float smoothedPitch_ = 0.0f;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

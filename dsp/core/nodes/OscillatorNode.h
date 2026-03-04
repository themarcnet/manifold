#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class OscillatorNode : public IPrimitiveNode, public std::enable_shared_from_this<OscillatorNode> {
public:
    OscillatorNode();

    const char* getNodeType() const override { return "Oscillator"; }
    int getNumInputs() const override { return 0; }
    int getNumOutputs() const override { return 1; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setFrequency(float freq);
    void setAmplitude(float amp) { targetAmplitude_.store(juce::jlimit(0.0f, 1.0f, amp), std::memory_order_release); }
    void setEnabled(bool en) { enabled_.store(en, std::memory_order_release); }
    void setWaveform(int shape);
    float getFrequency() const { return targetFrequency_.load(std::memory_order_acquire); }
    float getAmplitude() const { return targetAmplitude_.load(std::memory_order_acquire); }
    bool isEnabled() const { return enabled_.load(std::memory_order_acquire); }
    int getWaveform() const { return waveform_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetFrequency_{440.0f};
    std::atomic<float> targetAmplitude_{0.5f};
    std::atomic<bool> enabled_{true};
    std::atomic<int> waveform_{0};

    float currentFrequency_ = 440.0f;
    float currentAmplitude_ = 0.5f;
    float freqSmoothingCoeff_ = 1.0f;
    float ampSmoothingCoeff_ = 1.0f;

    double sampleRate_ = 44100.0;
    double phase_ = 0.0;
};

} // namespace dsp_primitives

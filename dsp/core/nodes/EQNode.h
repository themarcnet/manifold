#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class EQNode : public IPrimitiveNode,
               public std::enable_shared_from_this<EQNode> {
public:
    EQNode();

    const char* getNodeType() const override { return "EQ"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setLowGain(float db) { targetLowGainDb_.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release); }
    void setLowFreq(float hz) { targetLowFreqHz_.store(juce::jlimit(20.0f, 400.0f, hz), std::memory_order_release); }

    void setMidGain(float db) { targetMidGainDb_.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release); }
    void setMidFreq(float hz) { targetMidFreqHz_.store(juce::jlimit(120.0f, 8000.0f, hz), std::memory_order_release); }
    void setMidQ(float q) { targetMidQ_.store(juce::jlimit(0.2f, 12.0f, q), std::memory_order_release); }

    void setHighGain(float db) { targetHighGainDb_.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release); }
    void setHighFreq(float hz) { targetHighFreqHz_.store(juce::jlimit(2000.0f, 16000.0f, hz), std::memory_order_release); }

    void setOutput(float db) { targetOutputDb_.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getLowGain() const { return targetLowGainDb_.load(std::memory_order_acquire); }
    float getLowFreq() const { return targetLowFreqHz_.load(std::memory_order_acquire); }
    float getMidGain() const { return targetMidGainDb_.load(std::memory_order_acquire); }
    float getMidFreq() const { return targetMidFreqHz_.load(std::memory_order_acquire); }
    float getMidQ() const { return targetMidQ_.load(std::memory_order_acquire); }
    float getHighGain() const { return targetHighGainDb_.load(std::memory_order_acquire); }
    float getHighFreq() const { return targetHighFreqHz_.load(std::memory_order_acquire); }
    float getOutput() const { return targetOutputDb_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    struct Coeffs {
        float b0 = 1.0f;
        float b1 = 0.0f;
        float b2 = 0.0f;
        float a1 = 0.0f;
        float a2 = 0.0f;
    };

    struct State {
        float x1 = 0.0f;
        float x2 = 0.0f;
        float y1 = 0.0f;
        float y2 = 0.0f;
    };

    static Coeffs makeLowShelf(float sr, float freq, float gainDb);
    static Coeffs makeHighShelf(float sr, float freq, float gainDb);
    static Coeffs makePeak(float sr, float freq, float q, float gainDb);
    static float processBiquad(float x, State& s, const Coeffs& c);

    std::atomic<float> targetLowGainDb_{0.0f};
    std::atomic<float> targetLowFreqHz_{120.0f};
    std::atomic<float> targetMidGainDb_{0.0f};
    std::atomic<float> targetMidFreqHz_{1000.0f};
    std::atomic<float> targetMidQ_{0.7f};
    std::atomic<float> targetHighGainDb_{0.0f};
    std::atomic<float> targetHighFreqHz_{8000.0f};
    std::atomic<float> targetOutputDb_{0.0f};
    std::atomic<float> targetMix_{1.0f};

    float lowGainDb_ = 0.0f;
    float lowFreqHz_ = 120.0f;
    float midGainDb_ = 0.0f;
    float midFreqHz_ = 1000.0f;
    float midQ_ = 0.7f;
    float highGainDb_ = 0.0f;
    float highFreqHz_ = 8000.0f;
    float outputDb_ = 0.0f;
    float mix_ = 1.0f;
    float smooth_ = 1.0f;

    std::array<std::array<State, 3>, 2> state_{};

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

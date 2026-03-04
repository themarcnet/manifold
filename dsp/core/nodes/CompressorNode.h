#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>
#include <vector>

namespace dsp_primitives {

class CompressorNode : public IPrimitiveNode, public std::enable_shared_from_this<CompressorNode> {
public:
    CompressorNode();

    const char* getNodeType() const override { return "Compressor"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setThreshold(float db) { targetThreshold_.store(juce::jlimit(-60.0f, 0.0f, db), std::memory_order_release); }
    void setRatio(float ratio) { targetRatio_.store(juce::jlimit(1.0f, 100.0f, ratio), std::memory_order_release); }
    void setAttack(float ms) { targetAttack_.store(juce::jlimit(0.01f, 500.0f, ms), std::memory_order_release); }
    void setRelease(float ms) { targetRelease_.store(juce::jlimit(1.0f, 5000.0f, ms), std::memory_order_release); }
    void setKnee(float db) { targetKnee_.store(juce::jlimit(0.0f, 20.0f, db), std::memory_order_release); }
    void setMakeup(float db) { targetMakeup_.store(juce::jlimit(0.0f, 40.0f, db), std::memory_order_release); }
    void setAutoMakeup(bool enable) { targetAutoMakeup_.store(enable, std::memory_order_release); }
    void setMode(int mode);
    void setDetectorMode(int mode);
    void setSidechainHPF(float freq) { targetSidechainHPF_.store(juce::jlimit(20.0f, 1000.0f, freq), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getThreshold() const { return targetThreshold_.load(std::memory_order_acquire); }
    float getRatio() const { return targetRatio_.load(std::memory_order_acquire); }
    float getAttack() const { return targetAttack_.load(std::memory_order_acquire); }
    float getRelease() const { return targetRelease_.load(std::memory_order_acquire); }
    float getKnee() const { return targetKnee_.load(std::memory_order_acquire); }
    float getMakeup() const { return targetMakeup_.load(std::memory_order_acquire); }
    bool getAutoMakeup() const { return targetAutoMakeup_.load(std::memory_order_acquire); }
    int getMode() const { return mode_; }
    int getDetectorMode() const { return detectorMode_; }
    float getSidechainHPF() const { return targetSidechainHPF_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getGainReduction() const { return gainReduction_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetThreshold_{-12.0f};
    std::atomic<float> targetRatio_{4.0f};
    std::atomic<float> targetAttack_{10.0f};
    std::atomic<float> targetRelease_{100.0f};
    std::atomic<float> targetKnee_{6.0f};
    std::atomic<float> targetMakeup_{0.0f};
    std::atomic<bool> targetAutoMakeup_{true};
    std::atomic<float> targetSidechainHPF_{20.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<float> gainReduction_{0.0f};

    int mode_ = 0;
    int detectorMode_ = 0;
    float currentThreshold_ = -12.0f;
    float currentRatio_ = 4.0f;
    float currentKnee_ = 6.0f;
    float currentMakeup_ = 0.0f;
    float currentMix_ = 1.0f;
    float attackCoeff_ = 1.0f;
    float releaseCoeff_ = 1.0f;
    float envelope_ = 0.0f;
    double sampleRate_ = 44100.0;
};

} // namespace dsp_primitives

#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "dsp/core/nodes/PartialData.h"

#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class SineBankNode : public IPrimitiveNode,
                     public std::enable_shared_from_this<SineBankNode> {
public:
    SineBankNode();

    const char* getNodeType() const override { return "SineBank"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 1; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setFrequency(float freq);
    float getFrequency() const { return targetFrequency_.load(std::memory_order_acquire); }

    void setAmplitude(float amp) { targetAmplitude_.store(juce::jlimit(0.0f, 1.0f, amp), std::memory_order_release); }
    float getAmplitude() const { return targetAmplitude_.load(std::memory_order_acquire); }

    void setEnabled(bool enabled) { enabled_.store(enabled, std::memory_order_release); }
    bool isEnabled() const { return enabled_.load(std::memory_order_acquire); }

    void setStereoSpread(float spread) { stereoSpread_.store(juce::jlimit(0.0f, 1.0f, spread), std::memory_order_release); }
    float getStereoSpread() const { return stereoSpread_.load(std::memory_order_acquire); }

    void setUnison(int voices) { unisonVoices_.store(juce::jlimit(1, 8, voices), std::memory_order_release); }
    int getUnison() const { return unisonVoices_.load(std::memory_order_acquire); }

    void setDetune(float cents) { detuneCents_.store(juce::jlimit(0.0f, 100.0f, cents), std::memory_order_release); }
    float getDetune() const { return detuneCents_.load(std::memory_order_acquire); }

    void setDrive(float drive) { drive_.store(juce::jlimit(0.0f, 20.0f, drive), std::memory_order_release); }
    float getDrive() const { return drive_.load(std::memory_order_acquire); }

    void setDriveShape(int shape) { driveShape_.store(juce::jlimit(0, 3, shape), std::memory_order_release); }
    int getDriveShape() const { return driveShape_.load(std::memory_order_acquire); }

    void setDriveBias(float bias) { driveBias_.store(juce::jlimit(-1.0f, 1.0f, bias), std::memory_order_release); }
    float getDriveBias() const { return driveBias_.load(std::memory_order_acquire); }

    void setDriveMix(float mix) { driveMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }
    float getDriveMix() const { return driveMix_.load(std::memory_order_acquire); }

    void setSyncEnabled(bool enabled) { syncEnabled_.store(enabled, std::memory_order_release); }
    bool isSyncEnabled() const { return syncEnabled_.load(std::memory_order_acquire); }

    void clearPartials();
    void setPartial(int index, float frequency, float amplitude, float phase = 0.0f, float decayRate = 0.0f);
    void setPartials(const PartialData& data);
    PartialData getPartials() const;
    int getActivePartialCount() const { return activePartials_.load(std::memory_order_acquire); }
    float getReferenceFundamental() const { return referenceFundamental_.load(std::memory_order_acquire); }

private:
    static constexpr int kMaxPartials = PartialData::kMaxPartials;
    static constexpr int kMaxUnisonVoices = 8;

    std::atomic<float> targetFrequency_{440.0f};
    std::atomic<float> targetAmplitude_{0.0f};
    std::atomic<bool> enabled_{true};
    std::atomic<float> referenceFundamental_{440.0f};
    std::atomic<float> stereoSpread_{0.0f};
    std::atomic<int> activePartials_{0};
    std::atomic<int> unisonVoices_{1};
    std::atomic<float> detuneCents_{0.0f};
    std::atomic<float> drive_{0.0f};
    std::atomic<int> driveShape_{0};
    std::atomic<float> driveBias_{0.0f};
    std::atomic<float> driveMix_{1.0f};
    std::atomic<bool> syncEnabled_{false};

    std::array<float, kMaxPartials> partialFrequencies_{};
    std::array<float, kMaxPartials> partialAmplitudes_{};
    std::array<float, kMaxPartials> partialPhaseOffsets_{};
    std::array<float, kMaxPartials> partialDecayRates_{};
    std::array<std::array<double, kMaxPartials>, kMaxUnisonVoices> runningPhases_{};

    float currentFrequency_ = 440.0f;
    float currentAmplitude_ = 0.0f;
    float currentDetuneCents_ = 0.0f;
    float currentSpread_ = 0.0f;
    float freqSmoothingCoeff_ = 1.0f;
    float ampSmoothingCoeff_ = 1.0f;
    float detuneSmoothingCoeff_ = 1.0f;
    float spreadSmoothingCoeff_ = 1.0f;
    float unisonVoiceSmoothingCoeff_ = 1.0f;
    double sampleRate_ = 44100.0;
    bool prepared_ = false;
    float prevSyncSample_ = 0.0f;
    std::array<float, kMaxUnisonVoices> unisonVoiceGains_{{1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f}};
    int lastRequestedUnison_ = 1;
};

} // namespace dsp_primitives

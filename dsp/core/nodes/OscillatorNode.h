#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "dsp/core/nodes/PartialData.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

    namespace OscillatorNode_Highway
    {
        class IOscillatorNodeSIMDAInterface;
    }

struct WaveAddTableSet;

float lookupWaveAddSample(const WaveAddTableSet& tableSet, float phaseNorm, int bandIndex);

// Build partials from waveform recipe for morph mode
PartialData buildWavePartials(int waveform, float fundamental, int partialCount, float tilt, float drift, float pulseWidth = 0.5f);

class OscillatorNode : public IPrimitiveNode, public std::enable_shared_from_this<OscillatorNode> {
public:
    OscillatorNode(int simdtarget);

    const char* getNodeType() const override { return "Oscillator"; }
    // 1 stereo sync input. When a rising zero-crossing is
    // detected on the sync signal the oscillator hard-resets its phase.
    int getNumInputs() const override { return 1; }
    int getNumOutputs() const override { return 1; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setFrequency(float freq);
    void setAmplitude(float amp) { targetAmplitude_.store(juce::jlimit(0.0f, 1.0f, amp), std::memory_order_release); }
    void setEnabled(bool en) { enabled_.store(en, std::memory_order_release); }
    void setWaveform(int shape);
    void resetPhase();
    void setDrive(float drive) { drive_.store(juce::jlimit(0.0f, 20.0f, drive), std::memory_order_release); }
    void setDriveShape(int shape) { driveShape_.store(juce::jlimit(0, 3, shape), std::memory_order_release); }
    void setDriveBias(float bias) { driveBias_.store(juce::jlimit(-1.0f, 1.0f, bias), std::memory_order_release); }
    void setDriveMix(float mix) { driveMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }
    void setRenderMode(int mode) { renderMode_.store(juce::jlimit(0, 1, mode), std::memory_order_release); }
    int getRenderMode() const { return renderMode_.load(std::memory_order_acquire); }
    void setAdditivePartials(int count);
    int getAdditivePartials() const { return additivePartials_.load(std::memory_order_acquire); }
    void setAdditiveTilt(float tilt);
    float getAdditiveTilt() const { return additiveTilt_.load(std::memory_order_acquire); }
    void setAdditiveDrift(float drift);
    float getAdditiveDrift() const { return additiveDrift_.load(std::memory_order_acquire); }
    void setSyncEnabled(bool en) { syncEnabled_.store(en, std::memory_order_release); }
    bool isSyncEnabled() const { return syncEnabled_.load(std::memory_order_acquire); }
    float getFrequency() const { return targetFrequency_.load(std::memory_order_acquire); }
    float getAmplitude() const { return targetAmplitude_.load(std::memory_order_acquire); }
    float getDrive() const { return drive_.load(std::memory_order_acquire); }
    int getDriveShape() const { return driveShape_.load(std::memory_order_acquire); }
    float getDriveBias() const { return driveBias_.load(std::memory_order_acquire); }
    float getDriveMix() const { return driveMix_.load(std::memory_order_acquire); }
    bool isEnabled() const { return enabled_.load(std::memory_order_acquire); }
    int getWaveform() const { return waveform_.load(std::memory_order_acquire); }

    // Pulse width for pulse waveform (0.0 to 1.0, default 0.5 = square)
    void setPulseWidth(float width);
    float getPulseWidth() const { return pulseWidth_.load(std::memory_order_acquire); }

    // Unison settings for supersaw and rich tones
    void setUnison(int voices);
    void setDetune(float cents) { detuneCents_.store(juce::jlimit(0.0f, 100.0f, cents), std::memory_order_release); notifyConfigChangeSimdImplementation(false); }
    void setSpread(float amount) { stereoSpread_.store(juce::jlimit(0.0f, 1.0f, amount), std::memory_order_release); notifyConfigChangeSimdImplementation(false); }
    int getUnison() const { return unisonVoices_.load(std::memory_order_acquire); }
    float getDetune() const { return detuneCents_.load(std::memory_order_acquire); }
    float getSpread() const { return stereoSpread_.load(std::memory_order_acquire); }

    
    const char * getHighwayImplementationTargetName() const;

    int getHighwayErrorCode() const { return highwayErrCode_;}


private:
    std::atomic<float> targetFrequency_{440.0f};
    std::atomic<float> targetAmplitude_{0.5f};
    std::atomic<bool> enabled_{true};
    std::atomic<int> waveform_{0};
    std::atomic<float> drive_{0.0f};
    std::atomic<int> driveShape_{0};
    std::atomic<int> renderMode_{0};
    std::atomic<int> additivePartials_{8};
    std::atomic<float> additiveTilt_{0.0f};
    std::atomic<float> additiveDrift_{0.0f};
    std::atomic<float> driveBias_{0.0f};
    std::atomic<float> driveMix_{1.0f};

    // New parameters
    std::atomic<float> pulseWidth_{0.5f};      // For pulse waveform (0.01-0.99)
    std::atomic<int> unisonVoices_{1};          // Number of unison voices (1-8)
    std::atomic<float> detuneCents_{0.0f};      // Detune amount in cents (0-100)
    std::atomic<float> stereoSpread_{0.0f};     // Stereo spread (0-1)

    float currentFrequency_ = 440.0f;
    float currentAmplitude_ = 0.5f;
    float currentRenderMix_ = 0.0f;
    float currentDetuneCents_ = 0.0f;
    float currentSpread_ = 0.0f;
    float freqSmoothingCoeff_ = 1.0f;
    float ampSmoothingCoeff_ = 1.0f;
    float renderMixSmoothingCoeff_ = 1.0f;
    float detuneSmoothingCoeff_ = 1.0f;
    float spreadSmoothingCoeff_ = 1.0f;
    float unisonVoiceSmoothingCoeff_ = 1.0f;

    double sampleRate_ = 44100.0;
    double phase_ = 0.0;

    // Per-unison-voice phases for supersaw
    double unisonPhases_[8] = {0.0};
    float unisonVoiceGains_[8] = {1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};
    int lastRequestedUnison_ = 1;

    // Hard-sync
    std::atomic<bool> syncEnabled_{false};
    float prevSyncSample_ = 0.0f;

    int simdTarget_ = 0;
    int highwayErrCode_ = 0;

    std::shared_ptr<const WaveAddTableSet> waveAddTableSet_;

    void refreshWaveAddTableSet();

    // SIMD implementation
    std::unique_ptr<OscillatorNode_Highway::IOscillatorNodeSIMDAInterface> simd_implementation_;

private:
    void notifyConfigChangeSimdImplementation(bool refreshWaveAddTableSet);
    
};

} // namespace dsp_primitives

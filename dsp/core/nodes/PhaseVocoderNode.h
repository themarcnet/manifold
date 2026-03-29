#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <juce_dsp/juce_dsp.h>
#include <atomic>
#include <memory>
#include <vector>

namespace dsp_primitives {

/**
 * Phase Vocoder pitch shifter node with two algorithms:
 *
 * 1. BIN_MAPPING (original): Maps frequency bins directly for pitch shift.
 *    Lower latency (~46ms), but can have artifacts at high pitch ratios.
 *
 * 2. TIME_STRETCH_RESAMPLE: Uses proper time-stretch phase vocoder followed
 *    by resampling. Higher quality, especially for large pitch shifts, but
 *    adds resampler latency (~512 samples).
 *
 * Both approaches use FFT-based analysis-resynthesis with Hann windowing
 * and 75% overlap for smooth reconstruction.
 */
class PhaseVocoderNode : public IPrimitiveNode,
                         public std::enable_shared_from_this<PhaseVocoderNode> {
public:
    PhaseVocoderNode(int numChannels = 2);
    ~PhaseVocoderNode() override = default;

    const char* getNodeType() const override { return "PhaseVocoder"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    // Mode: 0 = BinMapping, 1 = TimeStretchResample
    void setMode(int mode);
    int getMode() const;

    // Pitch control in semitones (-24 to +24)
    void setPitchSemitones(float semitones);
    float getPitchSemitones() const;

    // Time stretch ratio (1.0 = normal, 0.5 = half speed, 2.0 = double speed)
    void setTimeStretch(float ratio);
    float getTimeStretch() const;

    // Mix between dry (0.0) and wet (1.0) pitch-shifted signal
    void setMix(float mix);
    float getMix() const;

    // FFT size: valid orders 9 (512), 10 (1024), 11 (2048), 12 (4096)
    void setFFTOrder(int order);
    int getFFTOrder() const;

    // Returns algorithmic latency in samples
    int getLatencySamples() const;

private:
    void processHopBinMapping(float pitchRatio, float omegaFactor, int numBins, int ringSize, int accumSize);
    void processHopTimeStretch(float pitchRatio, float omegaFactor, int numBins, int ringSize);
    
    // Simple cubic resampler for TimeStretchResample mode

    // Configuration
    int numChannels_ = 2;
    int fftOrder_ = 11;                    // 2^11 = 2048
    int fftSize_ = 2048;
    int hopSize_ = 512;                    // fftSize / 4 = 75% overlap

    // Parameters (atomic for thread safety)
    std::atomic<int> mode_{0};             // 0 = BinMapping, 1 = TimeStretchResample
    std::atomic<float> pitchSemitones_{0.0f};
    std::atomic<float> timeStretch_{1.0f};
    std::atomic<float> mix_{1.0f};
    std::atomic<int> fftOrderParam_{11};

    // Smoothed parameters
    int currentMode_ = 0;
    float currentPitchSemitones_ = 0.0f;
    float currentMix_ = 1.0f;
    float smoothingCoeff_ = 0.0f;

    // FFT engine
    std::unique_ptr<juce::dsp::FFT> fft_;

    // Input circular buffer
    juce::AudioBuffer<float> inputRing_;
    int inputWritePos_ = 0;

    // Output overlap-add accumulator (for BinMapping mode)
    juce::AudioBuffer<float> outputAccum_;
    int outputReadPos_ = 0;
    int hopWritePos_ = 0;

    // Time-stretch mode: separate accumulators
    juce::AudioBuffer<float> timeStretchAccum_;  // Phase vocoder output (time-stretched)
    int tsWritePos_ = 0;              // Write position in timeStretchAccum_
    float tsReadPos_ = 0.0f;          // Fractional read position for resampling

    // Per-channel persistent phase state
    std::vector<std::vector<float>> prevAnalysisPhase_;  // [channel][bin]
    std::vector<std::vector<float>> synthPhaseAccum_;     // [channel][bin] UNWRAPPED
    std::vector<std::vector<float>> prevSynthMag_;        // [channel][bin]

    // Hann window (precomputed)
    std::vector<float> window_;
    float overlapAddNorm_ = 1.0f;

    // Per-hop temporary work buffers
    std::vector<float> fftWorkBuffer_;
    std::vector<float> analysisMag_;
    std::vector<float> analysisPhase_;
    std::vector<float> analysisFreq_;
    std::vector<float> synthMag_;
    std::vector<float> synthFreq_;

    int samplesUntilNextHop_ = 0;
    int hopCount_ = 0;
    double sampleRate_ = 44100.0;
    bool prepared_ = false;

    // Constants
    static constexpr float kMinPitchSemitones = -24.0f;
    static constexpr float kMaxPitchSemitones = 24.0f;
    static constexpr float kMinTimeStretch = 0.25f;
    static constexpr float kMaxTimeStretch = 4.0f;
};

} // namespace dsp_primitives

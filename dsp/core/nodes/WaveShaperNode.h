#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>
#include <array>

namespace dsp_primitives {

// Wave shaper curve types
enum class WaveShaperCurve {
    Tanh = 0,      // Soft clipping, musical
    Tube = 1,      // Asymmetric tube emulation
    Tape = 2,      // Tape saturation with hysteresis
    HardClip = 3,  // Aggressive digital clipping
    Foldback = 4,  // Wave folding for harmonic complexity
    Sigmoid = 5,   // Smooth S-curve
    SoftClip = 6   // Gentle compression-style
};

class WaveShaperNode : public IPrimitiveNode,
                       public std::enable_shared_from_this<WaveShaperNode> {
public:
    WaveShaperNode();
    ~WaveShaperNode() override = default;

    const char* getNodeType() const override { return "WaveShaper"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    // Curve selection
    void setCurve(int curve);  // 0-6 maps to WaveShaperCurve enum
    int getCurve() const;

    // Drive and output
    void setDrive(float db);   // 0 to +40 dB
    float getDrive() const;
    void setOutput(float db);  // -20 to +20 dB
    float getOutput() const;

    // Tone controls (pre/post filters)
    void setPreFilter(float freq);   // 20-20000 Hz, 0 = bypass
    float getPreFilter() const;
    void setPostFilter(float freq);  // 20-20000 Hz, 0 = bypass
    float getPostFilter() const;

    // Asymmetric bias
    void setBias(float bias);  // -1.0 to +1.0
    float getBias() const;

    // Wet/dry mix
    void setMix(float mix);    // 0.0 to 1.0
    float getMix() const;

    // Oversampling (quality vs CPU tradeoff)
    void setOversample(int factor);  // 1, 2, or 4x
    int getOversample() const;

private:
    // Parameter targets (atomic for thread safety)
    std::atomic<int> targetCurve_{0};      // Tanh default
    std::atomic<float> targetDrive_{12.0f};
    std::atomic<float> targetOutput_{0.0f};
    std::atomic<float> targetPreFilter_{0.0f};
    std::atomic<float> targetPostFilter_{0.0f};
    std::atomic<float> targetBias_{0.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<int> targetOversample_{2};  // 2x default

    // Smoothed values for DSP
    float currentDrive_ = 12.0f;
    float currentOutput_ = 0.0f;
    float currentBias_ = 0.0f;
    float currentMix_ = 1.0f;
    float currentPreFilter_ = 0.0f;
    float currentPostFilter_ = 0.0f;
    int currentCurve_ = 0;
    int currentOversample_ = 2;

    // Smoothing coefficients
    float paramSmoothingCoeff_ = 0.0f;
    float filterSmoothingCoeff_ = 0.0f;

    // Sample rate and oversampling
    double sampleRate_ = 44100.0;
    int oversampleFactor_ = 2;

    // Filter states (per channel, stereo = 2)
    // Simple 1-pole filters for tone control
    float preFilterState_[2] = {0.0f, 0.0f};
    float postFilterState_[2] = {0.0f, 0.0f};
    float preFilterCoef_ = 0.0f;
    float postFilterCoef_ = 0.0f;

    // Oversampling buffers
    std::array<std::vector<float>, 2> upsampleBuffer_;
    std::array<std::vector<float>, 2> downsampleBuffer_;

    // Helper functions
    void updateFilterCoefficients();
    float processPreFilter(int channel, float input);
    float processPostFilter(int channel, float input);
    
    // Shaping functions
    float shapeSample(float x, int curveType);
    float shapeTanh(float x);
    float shapeTube(float x);
    float shapeTape(float x);
    float shapeHardClip(float x);
    float shapeFoldback(float x);
    float shapeSigmoid(float x);
    float shapeSoftClip(float x);

    // Oversampling filters (simple FIR)
    void upsample(float input, float* output, int factor);
    float downsample(float* input, int factor);
};

} // namespace dsp_primitives

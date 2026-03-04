#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class SVFNode : public IPrimitiveNode,
                public std::enable_shared_from_this<SVFNode> {
public:
    enum class Mode {
        Lowpass = 0,
        Bandpass,
        Highpass,
        Notch,
        Peak
    };

    SVFNode();

    const char* getNodeType() const override { return "SVF"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setCutoff(float freq);
    void setResonance(float q);
    void setMode(Mode mode);
    void setDrive(float drive);
    void setMix(float wet);

    float getCutoff() const;
    float getResonance() const;
    Mode getMode() const;
    float getDrive() const;
    float getMix() const;

    void reset();

private:
    void updateCoefficients();
    float processSample(float input, int channel);

    // Target parameters (atomic for thread-safe updates from UI)
    std::atomic<float> targetCutoff_{1000.0f};
    std::atomic<float> targetResonance_{0.5f};
    std::atomic<Mode> mode_{Mode::Lowpass};
    std::atomic<float> targetDrive_{0.0f};
    std::atomic<float> targetMix_{1.0f};

    // Current smoothed parameters
    float currentCutoff_ = 1000.0f;
    float currentResonance_ = 0.5f;
    float currentDrive_ = 0.0f;
    float currentMix_ = 1.0f;

    // Coefficients (updated in prepare or when params change)
    float g_ = 0.0f;      // tan(pi * fc / sr)
    float k_ = 0.0f;      // 1 / Q
    float gk_ = 0.0f;     // g + k
    float g2_ = 0.0f;     // g * g
    float driveGain_ = 1.0f;

    // Filter state (per channel)
    struct ChannelState {
        float ic1eq = 0.0f;  // Integrator 1 state
        float ic2eq = 0.0f;  // Integrator 2 state
    };
    ChannelState state_[2];

    double sampleRate_ = 44100.0;
    bool prepared_ = false;

    // Smoothing coefficients
    float cutoffSmoothingCoeff_ = 1.0f;
    float resonanceSmoothingCoeff_ = 1.0f;
    float driveSmoothingCoeff_ = 1.0f;
    float mixSmoothingCoeff_ = 1.0f;
};

} // namespace dsp_primitives

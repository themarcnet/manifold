#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>

namespace dsp_primitives {

// Simple ADSR envelope - audio goes in, shaped audio goes out
class ADSREnvelopeNode : public IPrimitiveNode {
public:
    ADSREnvelopeNode();
    
    const char* getNodeType() const override { return "ADSREnvelope"; }
    int getNumInputs() const override { return 1; }
    int getNumOutputs() const override { return 1; }
    
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    void setAttack(float seconds);
    void setDecay(float seconds);
    void setSustain(float level);
    void setRelease(float seconds);
    void setGate(bool gateOn);
    void reset();
    void disableSIMD(); //turn off SIMD implementation, for testing

    enum class Stage { Off, Attack, Decay, Sustain, Release };
    

private:
    // Parameters
    std::atomic<float> attack_{0.05f};
    std::atomic<float> decay_{0.2f};
    std::atomic<float> sustain_{0.7f};
    std::atomic<float> release_{0.4f};
    std::atomic<bool> gate_{false};
    
   
    Stage stage_ = Stage::Off; // // State (NOT atomic - only touched in audio thread)
    float envelope_ = 0.0f;
    float startLevel_ = 0.0f;
    double stageTime_ = 0.0;
    
    double sampleRate_ = 44100.0;
    bool prevGate_ = false;

    //Implementation (SIMD)
    std::unique_ptr<IPrimitiveNodeSIMDImplementation> simd_implementation_;
};

} // namespace dsp_primitives

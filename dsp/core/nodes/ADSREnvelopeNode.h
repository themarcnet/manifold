#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>

//Debug
#include <manifold/debugging/Logging.h>

namespace dsp_primitives {

// Simple ADSR envelope - audio goes in, shaped audio goes out
class ADSREnvelopeNode : public IPrimitiveNode {
public:
    ADSREnvelopeNode();
    ADSREnvelopeNode(int target); //Override automatic selection of SIMD implementation
    
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
    
    const char * getHighwayImplementationTargetName() const
    {
        if(simd_implementation_.get() == NULL)
            return NULL;

        return simd_implementation_->targetName();
    }

    int getHighwayErrorCode() const { return highwayErrCode_;}


    enum class Stage { Off, Attack, Decay, Sustain, Release };
    
    Debug::Logger & GetLog();

private:
    // Parameters
    std::atomic<float> attack_{0.05f};
    std::atomic<float> decay_{0.2f};
    std::atomic<float> sustain_{0.7f};
    std::atomic<float> release_{0.4f};
    std::atomic<bool> gate_{false};
    
    //SIMD / Google highway
    int simdTarget_ = 0; //0 = automatic
    int highwayErrCode_ = 0;
   
    Stage stage_ = Stage::Off; // // State (NOT atomic - only touched in audio thread)
    float envelope_ = 0.0f;
    float startLevel_ = 0.0f;
    double stageTime_ = 0.0;
    
    double sampleRate_ = 44100.0;
    bool prevGate_ = false;

    //Implementation (SIMD)
    std::unique_ptr<IPrimitiveNodeSIMDImplementation> simd_implementation_;

    //Logger
    Debug::Logger logger_;
    size_t totalSampleCount_ = 0;
};

} // namespace dsp_primitives

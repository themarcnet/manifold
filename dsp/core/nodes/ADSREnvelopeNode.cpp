#include "ADSREnvelopeNode.h"
#include <algorithm>

//Include SIMD implementaions - repeatedly includes itself for each SIMD implementation supported by Highway
#include "ADSREnvelopeNode_Highway.h"

namespace dsp_primitives {

ADSREnvelopeNode::ADSREnvelopeNode() = default;

void ADSREnvelopeNode::prepare(double sampleRate, int maxBlockSize)
{
    sampleRate_ = sampleRate;
    (void)maxBlockSize;

    //Create implementation
    //Note we're passing pointers of the std::atmomic values to the SIMD implementation here. This allows these values to change without
    //needing to be syncronised with the simd implementaion.
    simd_implementation_.reset(ADSREnvelopeNode_Highway::__CreateInstance(static_cast<float>(sampleRate), &attack_, &decay_, &sustain_, &release_, &gate_ ));
}

void ADSREnvelopeNode::setAttack(float seconds) 
{ 
    attack_.store(std::max(0.001f, seconds), std::memory_order_relaxed); 

    //Notify SIMD implementation that a value has changed, and recalculation of pre-calculated values may be required
    if(simd_implementation_ != NULL) 
        simd_implementation_->configChanged();  
}

void ADSREnvelopeNode::setDecay(float seconds) 
{ 
    decay_.store(std::max(0.001f, seconds), std::memory_order_relaxed); 
    
    //Notify SIMD implementation that a value has changed, and recalculation of pre-calculated values may be required
    if(simd_implementation_ != NULL) 
        simd_implementation_->configChanged();  
}

void ADSREnvelopeNode::setSustain(float level) 
{ 
    sustain_.store(std::clamp(level, 0.0f, 1.0f), std::memory_order_relaxed); 
    
    //Notify SIMD implementation that a value has changed, and recalculation of pre-calculated values may be required
    if(simd_implementation_ != NULL) 
        simd_implementation_->configChanged();
}

void ADSREnvelopeNode::setRelease(float seconds) 
{ 
    release_.store(std::max(0.001f, seconds), std::memory_order_relaxed); 
    
    //Notify SIMD implementation that a value has changed, and recalculation of pre-calculated values may be required
    if(simd_implementation_ != NULL) 
        simd_implementation_->configChanged();
}

void ADSREnvelopeNode::setGate(bool gateOn) 
{ 
    gate_.store(gateOn, std::memory_order_relaxed); 
    
    //Notify SIMD implementation that a value has changed, and recalculation of pre-calculated values may be required
    if(simd_implementation_ != NULL) 
        simd_implementation_->configChanged();
}


void ADSREnvelopeNode::disableSIMD()
{
    //Debug method, for disabling SIMD implementation and using the original implementation instead
    //(used for comparing the original (base) implementaion against the SIMD one)
    simd_implementation_.reset();
}

void ADSREnvelopeNode::reset() {
    stage_ = Stage::Off;
    envelope_ = 0.0f;
    startLevel_ = 0.0f;
    stageTime_ = 0.0;
    prevGate_ = false;

    //Reset state in SIMD implementaion as well
    if(simd_implementation_ != NULL)
        simd_implementation_->reset();
}

void ADSREnvelopeNode::process(const std::vector<AudioBufferView>& inputs,
                                std::vector<WritableAudioBufferView>& outputs,
                                int numSamples) {
    if (outputs.empty() || numSamples <= 0) return;

    
    auto& output = outputs[0];

    //Use the SIMD version if set up
    if(simd_implementation_ != NULL)
    {
        simd_implementation_->run( inputs, outputs,  numSamples);
        return;
    }

    bool hasInput = !inputs.empty() && inputs[0].numChannels > 0;
    
    float attack = attack_.load(std::memory_order_relaxed);
    float decay = decay_.load(std::memory_order_relaxed);
    float sustain = sustain_.load(std::memory_order_relaxed);
    float release = release_.load(std::memory_order_relaxed);
    bool gate = gate_.load(std::memory_order_relaxed);
    float dt = 1.0f / static_cast<float>(sampleRate_);


    // DEBUG: Print state occasionally
    static int debugCount = 0;
    if (++debugCount % 44100 == 0) {
        printf("ADSR: gate=%d stage=%d envelope=%.3f prevGate=%d\n", 
               (int)gate, (int)stage_, envelope_, (int)prevGate_);
    }
    
    //printf("ORIG: Start Stage:%d gate:%d prevgate:%u time:%f startLevel:%f Env:%f \n", stage_, gate, prevGate_,  stageTime_ / dt, startLevel_, envelope_);
    
    for (int i = 0; i < numSamples; ++i) {
        // Check for gate trigger on first sample only
        if (i == 0 && gate && !prevGate_) {
            stage_ = Stage::Attack;
            stageTime_ = 0.0;
            startLevel_ = envelope_;
        }
        if (i == 0) prevGate_ = gate;
        
        // Update envelope state machine
        switch (stage_) {
            case Stage::Off:
                envelope_ = 0.0f;
                if (gate) {
                    stage_ = Stage::Attack;
                    stageTime_ = 0.0;
                    startLevel_ = envelope_;
                }
                break;
                
            case Stage::Attack: {
                float progress = static_cast<float>(stageTime_) / attack;
                if (progress >= 1.0f) {
                    envelope_ = 1.0f;
                    stage_ = Stage::Decay;
                    stageTime_ = 0.0;
                } else {
                    envelope_ = startLevel_ + (1.0f - startLevel_) * progress;
                }
                break;
            }
            
            case Stage::Decay: {
                float progress = static_cast<float>(stageTime_) / decay;
                if (progress >= 1.0f) {
                    envelope_ = sustain;
                    stage_ = Stage::Sustain;
                } else {
                    envelope_ = 1.0f - (1.0f - sustain) * progress;
                }
                break;
            }
            
            case Stage::Sustain:
                envelope_ = sustain;
                if (!gate) {
                    stage_ = Stage::Release;
                    stageTime_ = 0.0;
                    startLevel_ = envelope_;
                }
                break;
                
            case Stage::Release: {
                float progress = static_cast<float>(stageTime_) / release;
                if (progress >= 1.0f) {
                    envelope_ = 0.0f;
                    stage_ = Stage::Off;
                } else {
                    envelope_ = startLevel_ * (1.0f - progress);
                }
                break;
            }
        }
        
        stageTime_ += dt;
        
        // Apply envelope to audio
        float inputL = hasInput ? inputs[0].getSample(0, i) : 0.0f;
        output.setSample(0, i, inputL * envelope_);
        
        if (output.numChannels > 1) {
            float inputR = hasInput && inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inputL;
            output.setSample(1, i, inputR * envelope_);
        }
    }

    //printf("ORIG: End Stage:%d gate:%d prevgate:%u time:%f startLevel:%f Env:%f\n", stage_, gate, prevGate_,  stageTime_ / dt, startLevel_, envelope_);
}

} // namespace dsp_primitives

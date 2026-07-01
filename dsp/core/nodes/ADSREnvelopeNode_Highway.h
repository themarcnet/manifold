
//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "dsp/core/nodes/ADSREnvelopeNode_Highway.h"

#include <manifold/debugging/Logging.h>

#include <manifold/highway/HighwayWrapper.h>
#include <manifold/highway/HighwayUtils.h>
#include <manifold/highway/HighwayDebug.h>

#ifndef __HIGHWAY_ADSR_LOGGER_IFACE
#define __HIGHWAY_ADSR_LOGGER_IFACE

namespace dsp_primitives
{
    namespace ADSREnvelopeNode_Highway
    {
        class ADSREnvelopeNode_Highway_Logging_IFace : public IPrimitiveNodeSIMDImplementation
        {
        public:
            virtual Debug::Logger & GetLogger()  = 0;
        };
    }
}

#endif


namespace dsp_primitives
{
    namespace ADSREnvelopeNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {
            class ADSREnvelopeNodeSIMDImplementation : public ADSREnvelopeNode_Highway_Logging_IFace
            {
            private:
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntMaskType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltMaskType;

                
            public:
                ADSREnvelopeNodeSIMDImplementation(float smprate,
                                                   const std::atomic<float> * attack, 
                                                   const std::atomic<float> *decay, 
                                                   const std::atomic<float> * sustain, 
                                                   const std::atomic<float> * release, 
                                                   const std::atomic<bool> * gate)    : configChanged_(true),
                                                                                        sampleRate_(smprate),
                                                                                        attack_(attack),
                                                                                        decay_(decay),
                                                                                        sustain_(sustain),
                                                                                        release_(release),
                                                                                        gate_(gate)
                {}

                const char * targetName() const override
                {
                    return  hwy::TargetName(HWY_TARGET);
                }

                virtual ~ADSREnvelopeNodeSIMDImplementation()
                {
                }

                virtual void configChanged() override 
                {
                    configChanged_ = true;
                }

                virtual void reset() override
                {
                    stage_ = ADSREnvelopeNode::Stage::Off;
                    envelope_ = 0.0f;
                    startLevel_ = 0.0f;
                    stageTime_ = 0.0;
                    prevGate_ = false;
                }

                virtual  Debug::Logger & GetLogger()  override
                {
                    return logger_;
                }

                HWY_ATTR virtual void run(const std::vector<AudioBufferView>& inputs,
                                 std::vector<WritableAudioBufferView>& outputs,
                                 int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    //Recalculate values if configuration changed
                    const size_t numLanes = HWY::Lanes(_flttype);
                    if(configChanged_)
                        configure();

                    bool gate = gate_->load(std::memory_order_relaxed);
                
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType timeStart = HWY::Load(_flttype, timeStartVec_);
 
                    DEBUG_LOG_LANES(logger_, totalSampleCount_, "Time Start", timeStart);
                    
                    // Check for gate trigger on first sample only
                    if (gate  && (!(prevGate_) || (stage_ == ADSREnvelopeNode::Stage::Off)))
                    {
                        stage_ = ADSREnvelopeNode::Stage::Attack;
                        stageTime_ = 0.0;
                        startLevel_ = envelope_;
                    }
                    
                    prevGate_ = gate;

                    FltType envelopeLanes = HWY::Set(_flttype, envelope_);
                    FltType startLevelLanes = HWY::Set(_flttype, startLevel_);
                    FltType stageTimeLanes = HWY::Add(HWY::Set(_flttype, static_cast<float>(stageTime_)), timeStart);

                    const float * inputPtr1 = inputs[0].channelData[0];
                    const float * inputPtr2 = (inputs[0].numChannels > 1) ? inputs[0].channelData[1] : NULL;
                    float * outputPtr1 = outputs[0].channelData[0];
                    float * outputPtr2 = (outputs[0].numChannels > 1) ? outputs[0].channelData[1] : NULL;
                    size_t offset = 0;

                    size_t samplesRemain = numsamples;
                    FltMaskType processLaneMask, progressCmpResult;
                    FltType attackRcpVal = zero;
                    FltType decayRcpVal = zero;
                    FltType sustainVal = zero;
                    FltType releaseRcpVal = zero;
                    FltType progress, newenv,data1, data2;
                    bool reprocess;
                    bool haveAttackVal = false;
                    bool haveDecayVal = false;
                    bool haveSustainVal = false;
                    bool haveReleaseVal = false;
                    
                    //Pre-fetch 
                    hwy::Prefetch(inputPtr1);
                    if(inputPtr2 != NULL)
                        hwy::Prefetch(inputPtr2);

                    while(samplesRemain > 0)
                    {
                        //Process all lanes
                        processLaneMask = HWY::Not(HWY::MaskFalse(_flttype));

                        do
                        {
                            //Don't reprocess by default
                            reprocess = false;

                            //Process current stage on the current lanes
                            switch(stage_)
                            {
                                case ADSREnvelopeNode::Stage::Off:
                                    envelopeLanes = zero;
                                    DEBUG_LOG_LANES(logger_, totalSampleCount_, "Off: Envelope", envelopeLanes);
                                    if(gate)
                                    {
                                        //Set new state 
                                        stage_ = ADSREnvelopeNode::Stage::Attack;
                                        startLevelLanes = envelopeLanes;
                                        stageTimeLanes = timeStart;

                                        //Re-process all lanes in the new state
                                        reprocess = true;
                                    }
                                    break;

                                case ADSREnvelopeNode::Stage::Attack:
                                    /*
                                        float progress = static_cast<float>(stageTime_) / attack;
                                        if (progress >= 1.0f) {
                                            envelope_ = 1.0f;
                                            stage_ = Stage::Decay;
                                            stageTime_ = 0.0;
                                        } else {
                                            envelope_ = startLevel_ + (1.0f - startLevel_) * progress;
                                        }
                                    */

                                    //progress = (1 / attack) * stageTime
                                    if(!haveAttackVal)
                                    {
                                        //This is  dt / attack
                                        attackRcpVal = HWY::Load(_flttype, attackRcpVec_);
                                        haveAttackVal = true;
                                    }
                                    
                                    progress = HWY::Mul(attackRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN envelope = startLevel_ + (1.0f - startLevel_) * progress ELSE envelope = 1
                                    progressCmpResult = HWY::Lt(progress, one);
                                    progressCmpResult = HWY::And(progressCmpResult, processLaneMask);

                                    newenv = HWY::MaskedMulAddOr(one, progressCmpResult,
                                                                 progress, HWY::Sub(one, startLevelLanes), startLevelLanes);

                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Attack: Envelope", newenv, progressCmpResult);
                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Attack: Progress", progress, progressCmpResult);

                                    //Only change the envelope for lanes we're processing
                                    envelopeLanes = HWY::IfThenElse(processLaneMask, newenv, envelopeLanes);

                                    //If any of the lanes we're processing have 'progressCmpResult' as false (meaning progress >= 1)
                                    //then change state.
                                    //We NOT the current 'progressCmpResult' value, since that was the comparison result of progress < 1.
                                    progressCmpResult = HWY::And(HWY::Not(progressCmpResult), processLaneMask);
                                    if(!HWY::AllFalse(_flttype, progressCmpResult))
                                    {
                                        stage_ = ADSREnvelopeNode::Stage::Decay;

                                        //Reset the time for the lanes being reprocessed
                                        stageTimeLanes = HWY::SlideUpLanes(_flttype, timeStart, HWY::FindKnownFirstTrue(_flttype, progressCmpResult));

                                        #ifdef ENABLE_LOGGING
                                            FltMaskType logmask = HWY::SetOnlyFirst(progressCmpResult);
                                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Attack -> Decay: Envelope", envelopeLanes, logmask);
                                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Attack -> Decay: Progress", progress, logmask);
                                        #endif 

                                        
                                        //Any remeaining lanes that need processing in the new state?
                                        //(use slide up to mask out the lane currently being processed)
                                        processLaneMask = HWY::And(processLaneMask, HWY::SlideMask1Up(_flttype, progressCmpResult));
                                        reprocess = !HWY::AllFalse(_flttype, processLaneMask);
                                    }

                                    break;

                                case ADSREnvelopeNode::Stage::Decay:
                                    /*
                                    float progress = static_cast<float>(stageTime_) / decay;
                                    if (progress >= 1.0f) {
                                        envelope_ = sustain;
                                        stage_ = Stage::Sustain;
                                    } else {
                                        envelope_ = 1.0f - (1.0f - sustain) * progress;
                                    }
                                    */

                                    //We need the sustain value later
                                    if(!haveSustainVal)
                                    {
                                        sustainVal = HWY::Load(_flttype, sustainVec_);
                                        haveSustainVal = true;
                                    }

                                    //progress = (1 / decay) * stageTime
                                    if(!haveDecayVal)
                                    {
                                        //This is  dt / decay
                                        decayRcpVal = HWY::Load(_flttype, decayRcpVec_);
                                        haveDecayVal = true;
                                    }

                                    //progress = HWY::Mul(stageTimeLanes, HWY::Set(_flttype, 1.0 / sampleRate_));
                                    progress = HWY::Mul(decayRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN envelope_ = 1.0 - (1.0f - sustain) * progress ELSE envelope = sustain 
                                    progressCmpResult = HWY::Lt(progress, one);
                                    progressCmpResult = HWY::And(progressCmpResult, processLaneMask);
                                    newenv = HWY::IfThenElse(progressCmpResult, HWY::NegMulAdd(progress, HWY::Sub(one, sustainVal), one), sustainVal);

                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Decay: Envelope", newenv, progressCmpResult);
                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Decay: Progress", progress, progressCmpResult);

                                    //Only change the envelope for lanes we're processing
                                    envelopeLanes = HWY::IfThenElse(processLaneMask, newenv, envelopeLanes);

                                    //If any of the lanes we're processing have 'progressCmpResult' as false (meaning progress >= 1)
                                    //then change state
                                    progressCmpResult = HWY::And(HWY::Not(progressCmpResult), processLaneMask);
                                    if(!HWY::AllFalse(_flttype, progressCmpResult))
                                    {
                                        stage_ = ADSREnvelopeNode::Stage::Sustain;
                                        
                                        #ifdef ENABLE_LOGGING
                                            FltMaskType logmask = HWY::SetOnlyFirst(progressCmpResult);
                                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Decay -> Sustain: Envelope", envelopeLanes, logmask);
                                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Decay -> Sustain: Progress", progress, logmask);
                                        #endif 
                                        
                                        processLaneMask = HWY::And(processLaneMask, HWY::SlideMask1Up(_flttype, progressCmpResult));
                                        reprocess = !HWY::AllFalse(_flttype, processLaneMask);
                                    }
                                    break;

                                case ADSREnvelopeNode::Stage::Sustain:
                                    /*
                                    envelope_ = sustain;
                                    if (!gate) {
                                        stage_ = Stage::Release;
                                        stageTime_ = 0.0;
                                        startLevel_ = envelope_;
                                    }
                                    */
                                    if(!haveSustainVal)
                                    {
                                        sustainVal = HWY::Load(_flttype, sustainVec_);
                                        haveSustainVal = true;
                                    }

                                    envelopeLanes = HWY::IfThenElse(processLaneMask, sustainVal, envelopeLanes);

                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Sustain: Envelope", sustainVal, processLaneMask);

                                    if(!gate)
                                    {   
                                         //Reset the time for the lanes being reprocessed
                                        stageTimeLanes = HWY::SlideUpLanes(_flttype, timeStart, HWY::FindKnownFirstTrue(_flttype, processLaneMask));

                                        //Reprocess remaining lanes
                                        reprocess = true;
                                        processLaneMask = HWY::And(processLaneMask, HWY::SlideMask1Up(_flttype, processLaneMask));

                                        stage_ = ADSREnvelopeNode::Stage::Release;
                                        startLevelLanes = envelopeLanes;
                                    }
                                    break;

                                case ADSREnvelopeNode::Stage::Release:
                                    /*
                                    float progress = static_cast<float>(stageTime_) / release;
                                    if (progress >= 1.0f) {
                                        envelope_ = 0.0f;
                                        stage_ = Stage::Off;
                                    } else {
                                        envelope_ = startLevel_ * (1.0f - progress);
                                    }
                                    */

                                    //progress = (1 / release) * stageTime
                                    if(!haveReleaseVal)
                                    {
                                        //This is  dt / release
                                        releaseRcpVal = HWY::Load(_flttype, releaseRcpVec_);
                                        haveReleaseVal = true;
                                    }

                                    progress = HWY::Mul(releaseRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN startLevel_ * (1.0f - progress) ELSE envelope = 0
                                    progressCmpResult = HWY::Lt(progress, one);
                                    progressCmpResult = HWY::And(progressCmpResult, processLaneMask);
                                    newenv = HWY::MaskedMulAddOr(zero, progressCmpResult, startLevelLanes, HWY::Sub(one, progress), zero);

                                    DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Release: Envelope", newenv, progressCmpResult);

                                    //Only change the envelope for lanes we're processing
                                    envelopeLanes = HWY::IfThenElse(processLaneMask, newenv, envelopeLanes);

                                    //If any of the lanes we're processing have 'progressCmpResult' as false (meaning progress >= 1)
                                    //then change state
                                    progressCmpResult = HWY::And(HWY::Not(progressCmpResult), processLaneMask);
                                    if(!HWY::AllFalse(_flttype, progressCmpResult))
                                    {
                                        stage_ = ADSREnvelopeNode::Stage::Off;

                                        //All the 'off' state does is zero the envelope, which we've done already,
                                        //therefore, there is no need to reprocess the remaining lanes.
                                        reprocess = false;
                                    }
                                    break;
                            }
                        }
                        while(reprocess);

                        //----------------------------------------
                        // 
                        //Process sample data
                        //
                        //--------------------------------------------
                        //This will load input values, apply envelope, then store to output
                        //      For 1 input channel to 2 output channels - the single input is duplicated to both outputs
                        //      For 2 input channels to 1 input - the two inputs are added together and the sum halved, and the res
                        //
                        //This also takes care not to buffer overrun by using LoadN/StoreN on the last block
                        if(samplesRemain >= numLanes)
                        {
                            //No need to use masked load/save, since any masked out data will be overwritten by the next iteration
                            data1 = HWY::LoadU(_flttype, inputPtr1 + offset);
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "Input L", data1);
                            
                            data1 = HWY::Mul(data1, envelopeLanes); //Apply envelope
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "Output L", data1);
                            if(inputPtr2 != NULL)
                            {
                                data2 = HWY::LoadU(_flttype, inputPtr2 + offset);
                                DEBUG_LOG_LANES(logger_, totalSampleCount_, "Input R", data2);

                                data2 = HWY::Mul(data2, envelopeLanes); //Apply envelope
                                DEBUG_LOG_LANES(logger_, totalSampleCount_, "Output R", data2);

                                //Store
                                if(outputPtr2 == NULL)
                                {
                                    //Convert to mono by averaging both inputs, and store
                                    data1 = HWY::Add(data1, data2);
                                    data1 = HWY::Mul(data1, HWY::Set(_flttype, 0.5));

                                    HWY::StoreU(data1, _flttype, outputPtr1 + offset);
                                }
                                else
                                {
                                    HWY::StoreU(data1, _flttype, outputPtr1 + offset);
                                    HWY::StoreU(data2, _flttype, outputPtr2 + offset);
                                }
                            }
                            else
                            {
                                HWY::StoreU(data1, _flttype, outputPtr1 + offset);
                                if(outputPtr2 != NULL)
                                    HWY::StoreU(data1, _flttype, outputPtr2 + offset);
                            }

                            samplesRemain -= numLanes;
                            offset += numLanes;
                            totalSampleCount_ += numLanes;

                            //Increment the stage time - use the last lane value + dt + laneTimes
                            //Use reverse to get the top most lane into lane 0 for non-fixed size vector types (ARM SVE). Slight performance impact on x86.
                            //Use BroadcastLane<N-1> for fixed size vectors where Lanes() is a constexpr (i.e: x86)
                            HWY::Utils::BroadcastLastLane(stageTimeLanes, stageTimeLanes);
                            stageTimeLanes = HWY::Add(stageTimeLanes, one); 
                            stageTimeLanes = HWY::Add(stageTimeLanes, timeStart); //time offsets for each lane
                        }
                        else
                        {
                            //Not a full lane count remains. To prevent buffer overrun, use masked loading and maks
                            //based upon the 'procCount' (lane processed count) value.
                            processLaneMask = HWY::FirstN(_flttype, samplesRemain);

                            //Load input values and apply envelope 
                            data1 = HWY::MaskedLoad(processLaneMask, _flttype, inputPtr1 + offset);
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Input L", data1, processLaneMask);

                            data1 = HWY::Mul(data1, envelopeLanes); //Apply envelope
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Output L", data1, processLaneMask);
                            if(inputPtr2 != NULL)
                            {
                                data2 = HWY::MaskedLoad(processLaneMask, _flttype, inputPtr2 + offset);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Input R", data1, processLaneMask);

                                data2 = HWY::Mul(data2, envelopeLanes); //Apply envelope
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "Output R", data1, processLaneMask);

                                //Store
                                if(outputPtr2 == NULL)
                                {
                                    //Convert to mono by averaging both inputs, and store
                                    data1 = HWY::Add(data1, data2);
                                    data1 = HWY::Mul(data1, HWY::Set(_flttype, 0.5));

                                    HWY::StoreN(data1,_flttype, outputPtr1 + offset, samplesRemain);
                                }
                                else
                                {
                                    HWY::StoreN(data1,  _flttype, outputPtr1 + offset, samplesRemain);
                                    HWY::StoreN(data2,  _flttype, outputPtr2 + offset, samplesRemain);
                                }
                            }
                            else
                            {
                                HWY::StoreN(data1,  _flttype, outputPtr1 + offset, samplesRemain);
                                if(outputPtr2 != NULL)
                                    HWY::StoreN(data1, _flttype, outputPtr2 + offset, samplesRemain);
                            }

                            //Increment the stage time - use the last *processed* lane value + dt + laneTimes
                            processLaneMask = HWY::Not(processLaneMask);
                            stageTimeLanes = HWY::BroadcastLane<0>(HWY::Compress(stageTimeLanes, processLaneMask));
                            stageTimeLanes = HWY::Add(stageTimeLanes, timeStart );
                            
                            offset = numsamples;
                            totalSampleCount_ += samplesRemain;
                            samplesRemain = 0;
                        }
                    }
                    
                    ///Update state using the last upated lane
                    if(numsamples > 0)
                    {
                        int lane = (numsamples - 1) % numLanes;
                        stageTime_ = static_cast<double>(HWY::ExtractLane(stageTimeLanes, 0)); //stageTime_ Already updated
                        envelope_ = HWY::ExtractLane(envelopeLanes, lane);
                        startLevel_ = HWY::ExtractLane(startLevelLanes, lane);
                    }

                    //printf("SIMD: End Stage:%d gate:%d prevgate:%u time:%f startLevel:%f Env:%f\n\n", stage_, gate, prevGate_,   stageTime_, startLevel_, envelope_);
                }

            private:
                HWY_ATTR void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t maxLanes = HWY::MaxLanes(_flttype);
                    const float dt = static_cast<float>(1.0 / sampleRate_);
                    
                    if(!constValues_)
                        constValues_ = hwy::AllocateAligned<float>(maxLanes * 5);

                    attackRcpVec_ = constValues_.get();
                    decayRcpVec_ = &attackRcpVec_[maxLanes];
                    releaseRcpVec_ = &decayRcpVec_[maxLanes];
                    sustainVec_ = &releaseRcpVec_[maxLanes];
                    timeStartVec_ = &sustainVec_[maxLanes];

                    float val;
                    for(size_t x=0; x < maxLanes; ++x)
                    {
                        val = static_cast<float>(static_cast<double>(1.0f) / static_cast<double>(attack_->load(std::memory_order_relaxed)));
                        attackRcpVec_[x] = val * dt;

                        val = static_cast<float>(static_cast<double>(1.0f) / static_cast<double>(decay_->load(std::memory_order_relaxed)));
                        decayRcpVec_[x] = val * dt;

                        val = static_cast<float>(static_cast<double>(1.0f) / static_cast<double>(release_->load(std::memory_order_relaxed)));
                        releaseRcpVec_[x] = val * dt;

                        val = sustain_->load(std::memory_order_relaxed);
                        sustainVec_[x] = val;

                        timeStartVec_[x] = static_cast<float>(x);;
                    }

                 
                    configChanged_ = false;
                }
                
                bool configChanged_;
                const float sampleRate_;
                const std::atomic<float> * attack_;
                const std::atomic<float> * decay_;
                const std::atomic<float> * sustain_;
                const std::atomic<float> * release_;
                const std::atomic<bool> * gate_;
                

                //Pre-calculated
                hwy::AlignedFreeUniquePtr<float[]> constValues_;
                float * attackRcpVec_;
                float * decayRcpVec_;
                float * releaseRcpVec_;
                float * sustainVec_;
                float * timeStartVec_;
                
                //State
                ADSREnvelopeNode::Stage stage_ = ADSREnvelopeNode::Stage::Off;
                float envelope_ = 0.0f;
                float startLevel_ = 0.0f;
                double stageTime_ = 0.0;
                bool prevGate_ = false;

                Debug::Logger logger_;
                size_t totalSampleCount_ = 0;
            };

            //Create CPU specific instance
            HWY_API IPrimitiveNodeSIMDImplementation *  __CreateInstanceForCPU(float samplerate,
                                                                                const std::atomic<float> * attack, const std::atomic<float> *decay, 
                                                                                const std::atomic<float> * sustain, const std::atomic<float> * release, 
                                                                                const std::atomic<bool> * gate)
            {
                return new ADSREnvelopeNodeSIMDImplementation(samplerate, attack,decay, sustain, release, gate);
            }
        }

        //========================================================================
        //Highway bootstrap

        #if HWY_ONCE || HWY_IDE

            IPrimitiveNodeSIMDImplementation *  __CreateInstance(int target, 
                                                                 float samplerate,
                                                                const std::atomic<float> * attack, const std::atomic<float> *decay, 
                                                                const std::atomic<float> * sustain, const std::atomic<float> * release, 
                                                                const std::atomic<bool> * gate,
                                                                hwy::RunHighwayErrorCode * retErrCode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                
                IPrimitiveNodeSIMDImplementation * ret = NULL;
                hwy::RunHighwayErrorCode errCode = hwy::RunHighwayFunction(target, &ret, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                           samplerate, attack, decay, sustain, release, gate);

                *retErrCode = errCode;
                return ret;
            }
        
        #endif
    }
}

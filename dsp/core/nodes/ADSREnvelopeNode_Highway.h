
//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "ADSREnvelopeNode_Highway.h"

#include "manifold/highway/HighwayWrapper.h"

namespace dsp_primitives
{
    namespace ADSREnvelopeNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {
            class ADSREnvelopeNodeSIMDImplementation : public IPrimitiveNodeSIMDImplementation
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

                virtual void run(const std::vector<AudioBufferView>& inputs,
                                 std::vector<WritableAudioBufferView>& outputs,
                                 int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    //Recalculate values if configuration changed
                    const size_t numLanes = HWY::Lanes(_flttype);
                    if(configChanged_ || (numLanes != laneCount_))
                        configure();

                    bool gate = gate_->load(std::memory_order_relaxed);
                
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType timeStart = HWY::Load(_flttype, timeStartVec_.get());
                    
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

                    //printf("SIMD: Start Stage:%d gate:%d prevgate:%u time:%f startLevel:%f Env:%f \n", stage_, gate, prevGate_, stageTime_, startLevel_, envelope_);
    

                    size_t samplesRemain = numsamples;
                    FltMaskType processLaneMask, progressCmpResult;
                    FltType progress, attackRcpVal, decayRcpVal,  sustainVal, releaseRcpVal,  newenv,data1, data2;
                    bool reprocess;
                    bool haveAttackVal = false;
                    bool haveDecayVal = false;
                    bool haveSustainVal = false;
                    bool haveReleaseVal = false;
                    while(samplesRemain > 0)
                    {
                        //Pre-fetch 
                        hwy::Prefetch(inputPtr1 + offset);
                        if(inputPtr2 != NULL)
                            hwy::Prefetch(inputPtr2 + offset);

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
                                        attackRcpVal = HWY::Load(_flttype, attackRcpVec_.get());
                                        haveAttackVal = true;
                                    }
                                    
                                    progress = HWY::Mul(attackRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN envelope = startLevel_ + (1.0f - startLevel_) * progress ELSE envelope = 1
                                    progressCmpResult = HWY::Lt(progress, one);
                                    newenv = HWY::MaskedMulAddOr(one, progressCmpResult,
                                                                 progress, HWY::Sub(one, startLevelLanes), startLevelLanes);

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
                                        sustainVal = HWY::Load(_flttype, sustainVec_.get());
                                        haveSustainVal = true;
                                    }

                                    //progress = (1 / decay) * stageTime
                                    if(!haveDecayVal)
                                    {
                                        //This is  dt / decay
                                        decayRcpVal = HWY::Load(_flttype, decayRcpVec_.get());
                                        haveDecayVal = true;
                                    }

                                    //progress = HWY::Mul(stageTimeLanes, HWY::Set(_flttype, 1.0 / sampleRate_));
                                    progress = HWY::Mul(decayRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN envelope_ = 1.0 - (1.0f - sustain) * progress ELSE envelope = sustain 
                                    progressCmpResult = HWY::Lt(progress, one);
                                    newenv = HWY::IfThenElse(progressCmpResult, HWY::NegMulAdd(progress, HWY::Sub(one, sustainVal), one), sustainVal);

                                    //Only change the envelope for lanes we're processing
                                    envelopeLanes = HWY::IfThenElse(processLaneMask, newenv, envelopeLanes);

                                    //If any of the lanes we're processing have 'progressCmpResult' as false (meaning progress >= 1)
                                    //then change state
                                    progressCmpResult = HWY::And(HWY::Not(progressCmpResult), processLaneMask);
                                    if(!HWY::AllFalse(_flttype, progressCmpResult))
                                    {
                                        stage_ = ADSREnvelopeNode::Stage::Sustain;
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
                                        sustainVal = HWY::Load(_flttype, sustainVec_.get());
                                        haveSustainVal = true;
                                    }

                                    envelopeLanes = HWY::IfThenElse(processLaneMask, sustainVal, envelopeLanes);
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
                                        releaseRcpVal = HWY::Load(_flttype, releaseRcpVec_.get());
                                        haveReleaseVal = true;
                                    }

                                    progress = HWY::Mul(releaseRcpVal, stageTimeLanes);

                                    //if progress < 1.0 THEN startLevel_ * (1.0f - progress) ELSE envelope = 0
                                    progressCmpResult = HWY::Lt(progress, one);
                                    newenv = HWY::MaskedMulAddOr(zero, progressCmpResult, startLevelLanes, HWY::Sub(one, progress), zero);

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
                            data1 = HWY::Mul(data1, envelopeLanes); //Apply envelope
                            if(inputPtr2 != NULL)
                            {
                                data2 = HWY::LoadU(_flttype, inputPtr2 + offset);
                                data2 = HWY::Mul(data2, envelopeLanes); //Apply envelope

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

                            //Increment the stage time - use the last lane value + dt + laneTimes
                            stageTimeLanes = HWY::BroadcastLane<HWY::MaxLanes(_flttype) - 1>(stageTimeLanes);
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
                            data1 = HWY::Mul(data1, envelopeLanes); //Apply envelope
                            if(inputPtr2 != NULL)
                            {
                                data2 = HWY::MaskedLoad(processLaneMask, _flttype, inputPtr2 + offset);
                                data2 = HWY::Mul(data2, envelopeLanes); //Apply envelope

                                //Store
                                if(outputPtr2 == NULL)
                                {
                                    //Convert to mono by averaging both inputs, and store
                                    data1 = HWY::Add(data1, data2);
                                    data1 = HWY::Mul(data1, HWY::Set(_flttype, 0.5));

                                    HWY::BlendedStore(data1, processLaneMask, _flttype, outputPtr1 + offset);
                                }
                                else
                                {
                                    HWY::BlendedStore(data1, processLaneMask, _flttype, outputPtr1 + offset);
                                    HWY::BlendedStore(data2, processLaneMask, _flttype, outputPtr2 + offset);
                                }
                            }
                            else
                            {
                                HWY::BlendedStore(data1, processLaneMask, _flttype, outputPtr1 + offset);
                                if(outputPtr2 != NULL)
                                    HWY::BlendedStore(data1, processLaneMask, _flttype, outputPtr2 + offset);
                            }

                            //Increment the stage time - use the last *processed* lane value + dt + laneTimes
                            processLaneMask = HWY::Not(processLaneMask);
                            stageTimeLanes = HWY::BroadcastLane<0>(HWY::Compress(stageTimeLanes, processLaneMask));
                            stageTimeLanes = HWY::Add(stageTimeLanes, timeStart );
                            
                            samplesRemain = 0;
                            offset = numsamples;
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
                void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);
                    
                    const double dt = 1.0f / static_cast<float>(sampleRate_);
                    FltType dtv = HWY::Set(_flttype, static_cast<float>(dt));
                    
                    if(!attackRcpVec_ || (laneCount_ != numLanes))
                        attackRcpVec_ = hwy::AllocateAligned<float>(numLanes);
                    FltType val = HWY::Set(_flttype,  static_cast<float>(  static_cast<double>(1.0f) / static_cast<double>(attack_->load(std::memory_order_relaxed))));
                    val = HWY::Mul(val, dtv);
                    HWY::Store(val, _flttype, attackRcpVec_.get());
                    

                    if(!decayRcpVec_ || (numLanes != laneCount_))
                        decayRcpVec_ = hwy::AllocateAligned<float>(numLanes);
                   val = HWY::Set(_flttype,  static_cast<float>(  static_cast<double>(1.0f) /static_cast<double>(decay_->load(std::memory_order_relaxed))));
                   val = HWY::Mul(val, dtv);
                   HWY::Store(val, _flttype, decayRcpVec_.get());

                    if(!releaseRcpVec_  || (numLanes != laneCount_))
                        releaseRcpVec_ = hwy::AllocateAligned<float>(numLanes);
                    val = HWY::Set(_flttype,  static_cast<float>(  static_cast<double>(1.0f) / static_cast<double>(release_->load(std::memory_order_relaxed))));
                    val = HWY::Mul(val, dtv);
                    HWY::Store(val, _flttype, releaseRcpVec_.get());

                    if(!sustainVec_ || (numLanes != laneCount_))
                        sustainVec_ = hwy::AllocateAligned<float>(numLanes);
                    val = HWY::Set(_flttype, sustain_->load(std::memory_order_relaxed));
                    HWY::Store(val, _flttype, sustainVec_.get());


                    const FltType laneNum = HWY::Iota(_flttype, 0);
                    if(!timeStartVec_  || (laneCount_ != numLanes))
                        timeStartVec_ = hwy::AllocateAligned<float>(numLanes);
                    
                    HWY::Store(laneNum, _flttype, timeStartVec_.get());

                    laneCount_ = numLanes;
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
                hwy::AlignedFreeUniquePtr<float[]> attackRcpVec_;
                hwy::AlignedFreeUniquePtr<float[]> decayRcpVec_;
                hwy::AlignedFreeUniquePtr<float[]> releaseRcpVec_;
                hwy::AlignedFreeUniquePtr<float[]> sustainVec_;
                hwy::AlignedFreeUniquePtr<float[]> timeStartVec_;
                size_t laneCount_;

                //State
                ADSREnvelopeNode::Stage stage_ = ADSREnvelopeNode::Stage::Off;
                float envelope_ = 0.0f;
                float startLevel_ = 0.0f;
                double stageTime_ = 0.0;
                bool prevGate_ = false;
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

            IPrimitiveNodeSIMDImplementation *  __CreateInstance(float samplerate,
                                                                const std::atomic<float> * attack, const std::atomic<float> *decay, 
                                                                const std::atomic<float> * sustain, const std::atomic<float> * release, 
                                                                const std::atomic<bool> * gate)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                return HWY_DYNAMIC_DISPATCH_T(_create_instance_table)(samplerate, attack,decay, sustain, release, gate);
            }
        
        #endif
    }


}
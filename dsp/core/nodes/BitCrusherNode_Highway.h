//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "BitCrusherNode_Highway.h"

#include "manifold/highway/HighwayWrapper.h"
#include "manifold/highway/HighwayMaths.h"

namespace dsp_primitives
{
    namespace BitCrusherNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {

            class BitCrusherNodeSIMDImplementation : public IPrimitiveNodeSIMDImplementation
            {
             private:
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntMaskType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltMaskType;

            public:
                BitCrusherNodeSIMDImplementation(float samplerate,
                                                 const std::atomic<float> * targetbits,
                                                const std::atomic<float> * targetratered,
                                                const std::atomic<float> * targetmix,
                                                const std::atomic<float> * targetoutput,
                                                const std::atomic<int> * targetlogicmode) :   targetBits_(targetbits),
                                                                                              targetRateReduction_(targetratered),
                                                                                              targetMix_(targetmix),
                                                                                              targetOutput_(targetoutput),
                                                                                              targetLogicMode_(targetlogicmode),
                                                                                              configChanged_(true),
                                                                                              sampleRate_(samplerate)
                {
                    configure();
                }

                virtual void prepare(float sampleRate) override
                {
                    sampleRate_ = sampleRate;

                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const int numValues = StateIndex_Count;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    const double smoothTime = 0.01;
                    
                    smooth_ = hwy::AllocateAligned<float>(numLanes);
                    float smoothval = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
                    smoothval = juce::jlimit(0.0001f, 1.0f, smoothval);
                    HWY::Store(HWY::Set(_flttype, smoothval),  _flttype, smooth_.get());

                    if(!currentState_ || (numLanes != laneCount_))
                        currentState_ = hwy::AllocateAligned<float>( (numValues < numLanes) ? numLanes : ((1+(numValues / numLanes)) * numLanes)  );
                    
                    float * stateptr = currentState_.get();
                    stateptr[StateIndex_Bits] = targetBits_->load(std::memory_order_acquire);
                    stateptr[StateIndex_RateReduction] = targetRateReduction_->load(std::memory_order_acquire);
                    stateptr[StateIndex_Mix] = targetMix_->load(std::memory_order_acquire);
                    stateptr[StateIndex_Output] = targetOutput_->load(std::memory_order_acquire);
                    currentLogicMode_ = targetLogicMode_->load(std::memory_order_acquire);
                    
                    reset();
                }

                virtual void configChanged() override 
                {
                    configChanged_ = true;
                }

                const char * targetName() const override
                {
                    return  hwy::TargetName(HWY_TARGET);
                }


                virtual void reset() override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    memset(heldSample_.get(), 0, laneCount_ * 2 * sizeof(float));
                    memset(holdCounters_.get(), 0, laneCount_ * 2 * sizeof(float));

                    const size_t numLanes = HWY::Lanes(_flttype);

                    if(numLanes != laneCount_)
                    {
                        configure();
                    }
                    else
                    {
                        const FltType laneNum = HWY::Iota(_flttype, 1);
                        HWY::Store(laneNum, _flttype, holdCounters_.get());
                        HWY::Store(laneNum, _flttype, holdCounters_.get() + numLanes);
                    }
                }

                virtual void run(const std::vector<AudioBufferView> & inputs,
                                 std::vector<WritableAudioBufferView> & outputs,
                                 int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    if(numLanes != laneCount_)
                    {
                        configure();
                        prepare(sampleRate_);
                    }
                    else if(configChanged_)
                    {
                        configure();
                    }

                    const float * inputPtr1L = inputs[0].channelData[0];
                    const float * inputPtr1R = (inputs[0].numChannels > 1) ? inputs[0].channelData[1] : NULL;
                    const bool hasBusB = inputs.size() >= 3;
                    const float * inputPtr2L = hasBusB ? inputs[2].channelData[0] : NULL;
                    const float * inputPtr2R = (hasBusB && (inputs[0].numChannels > 1)) ? inputs[2].channelData[1] : NULL;
                    const bool outputMono = outputs[0].numChannels == 1;
                    float * outputPtrL = outputs[0].channelData[0];
                    float * outputPtrR = !outputMono ? outputs[0].channelData[1] : NULL;
                    size_t offset = 0;
                    size_t samplesRemain = numsamples;
                    
                    const FltType lanecount = HWY::Set(_flttype, static_cast<float>(numLanes));
                    const FltType half = HWY::Set(_flttype, 0.5f);
                    const FltType one = HWY::Add(half,half);
                    const FltType two = HWY::Add(one,one);
                    const FltType gateLevel = HWY::Set(_flttype, 0.001f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType negone = HWY::Sub( zero,one );
                    const FltType targetStateValues = HWY::Load(_flttype, targetState_.get());
                    const FltType laneNumbers = HWY::Load(_flttype, laneNumber_.get());
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType izero = HWY::Sub(ione,ione);

                    FltType holdCounter = HWY::Load(_flttype, holdCounters_.get());
                    FltMaskType stateMask, laneMask, gate, sampleLaneMask;
                    FltType currentStateValues = HWY::Load(_flttype, currentState_.get());
                    FltType smooth = HWY::Load(_flttype, smooth_.get());
                    FltType currentOutput = HWY::Zero(_flttype);
                    FltType currentBits = HWY::Zero(_flttype);
                    FltType currentRateReduction = HWY::Zero(_flttype);
                    FltType currentMix = HWY::Zero(_flttype);
                    FltType heldSampleL = HWY::Load(_flttype, heldSample_.get() );
                    FltType heldSampleR = HWY::Load(_flttype, heldSample_.get() + numLanes);
                    FltType holdInterval, tmp, inAL,inAR, outputL, outputR, newHeldSampleL, newHeldSampleR, quantLevels;
                    FltType inBL = zero;
                    FltType inBR = zero;
                    IntType maxCode, midCode, qaL, qaR, qbL, qbR;
                    size_t sampleLaneCount;
                    while(samplesRemain > 0)
                    {
                        //Pre-fetch
                        hwy::Prefetch(inputPtr1L + offset);
                        if(inputPtr1R != NULL)
                            hwy::Prefetch(inputPtr1R + offset);
                        if(inputPtr2L != NULL)
                            hwy::Prefetch(inputPtr2L + offset);
                        if(inputPtr2R != NULL)
                            hwy::Prefetch(inputPtr2R + offset);

                        //Generate values for all lanes
                        stateMask = HWY::Not(HWY::MaskFalse(_flttype));
                        sampleLaneCount = (samplesRemain > numLanes) ? numLanes : samplesRemain;
                        for(int lane = 0; lane < sampleLaneCount; ++lane)
                        {
                            currentStateValues = HWY::MulAdd(HWY::Sub(targetStateValues, currentStateValues), smooth, currentStateValues);
                            currentOutput = HWY::IfThenElse(stateMask, HWY::BroadcastLane<StateIndex_Output>(currentStateValues), currentOutput);
                            currentBits = HWY::IfThenElse(stateMask, HWY::BroadcastLane<StateIndex_Bits>(currentStateValues), currentBits);
                            currentRateReduction = HWY::IfThenElse(stateMask, HWY::BroadcastLane<StateIndex_RateReduction>(currentStateValues), currentRateReduction);
                            currentMix = HWY::IfThenElse(stateMask, HWY::BroadcastLane<StateIndex_Mix>(currentStateValues), currentMix);
                            stateMask = HWY::SlideMaskUpLanes(_flttype, stateMask, 1);
                        }

                        holdInterval = HWY::IfThenElse(HWY::Lt(currentRateReduction, one), one, currentRateReduction);
                        sampleLaneMask = HWY::Not(stateMask); //mask out lanes we're not processing (due to incomplete block)

                        //By default, the output is the currently held sample
                        outputL = heldSampleL;
                        outputR = heldSampleR;

                        //Read input A
                        if(samplesRemain >= numLanes)
                        {
                            inAL = HWY::LoadU(_flttype, inputPtr1L + offset);
                            inAR = (inputPtr1R == NULL) ? inAL : HWY::LoadU(_flttype, inputPtr1R + offset);
                        }
                        else
                        {
                            inAL = HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtr1L + offset);
                            inAR = (inputPtr1R == NULL) ? inAL : HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtr1R + offset);
                        }

                        //if (holdCounter_[static_cast<size_t>(ch)] >= holdInterval) {
                        laneMask = HWY::MaskedGe(sampleLaneMask, holdCounter, holdInterval);
                        if(!HWY::AllFalse(_flttype, laneMask))
                        {
                            //Caclulate common values

                            //const float quantLevels = std::pow(2.0f, currentBits_ - 1.0f);
                            quantLevels = HWY::Pow(_flttype, HWY::Add(one, one), HWY::Sub(currentBits, one));

                            //const int maxCode = juce::jmax(1, static_cast<int>(quantLevels * 2.0f) - 1);
                            maxCode = HWY::ConvertTo(_inttype, HWY::Add(quantLevels, quantLevels));
                            maxCode = HWY::Sub(maxCode, ione);
                            maxCode = HWY::IfThenElse(HWY::Lt(maxCode, ione), ione, maxCode);

                            //const int midCode = juce::jmax(1, static_cast<int>(quantLevels * 2.0f) - 1) / 2;
                            midCode = HWY::ShiftRight<1>(maxCode);

                            //Read input B
                            if((currentLogicMode_ <= 2) && hasBusB)
                            {
                                if(samplesRemain >= numLanes)
                                {
                                    inBL = HWY::LoadU(_flttype, inputPtr2L + offset);
                                    inBR = (inputPtr2R == NULL) ? inBL : HWY::LoadU(_flttype, inputPtr2R + offset);
                                }
                                else
                                {
                                    inBL = HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtr2L + offset);
                                    inBR = (inputPtr2R == NULL) ? inBL : HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtr2R + offset);
                                }
                            }

                            //Generate potential new held sample values.
                            //These will get picked out and used later
                            newHeldSampleL = heldSampleL;
                            newHeldSampleR = heldSampleR;
                            if(currentLogicMode_ == 1 && hasBusB)
                            {
                                // Offset codes to center around 0, XOR, then offset back

                                /*  auto quantizeToCode = [](float x, float levels) {
                                    const float clamped = juce::jlimit(-1.0f, 1.0f, x);
                                    const int maxCode = juce::jmax(1, static_cast<int>(levels * 2.0f) - 1);
                                    const int code = static_cast<int>(std::round(((clamped + 1.0f) * 0.5f) * static_cast<float>(maxCode)));
                                    return juce::jlimit(0, maxCode, code);
                                }*/

                                // XOR: quantize both, XOR the codes, convert back.
                                // Use bipolar quantization so silence (0.0) XOR silence = 0.0.
                                //const int qa = quantizeToCode(inA, quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(inAL, one), one, inAL);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::Mul(HWY::Add(tmp, one), half);
                                tmp = HWY::Mul(tmp, HWY::ConvertTo(_flttype, maxCode));
                                qaL = HWY::ConvertTo(_inttype, HWY::Round(tmp));
                                qaL = HWY::IfThenElse(HWY::Gt(qaL, maxCode), maxCode, qaL);
                                qaL = HWY::IfThenElse(HWY::Lt(qaL, izero), izero, qaL);
                                qaL = HWY::Sub(qaL, midCode); //const int da = qa - midCode;
                                if(HWY::AllTrue(_flttype, HWY::Eq(inAL, inAR)))
                                {
                                    //Mono input
                                    qaR = qaL;
                                }
                                else
                                {
                                    tmp = HWY::IfThenElse(HWY::Gt(inAR, one), one, inAR);
                                    tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                    tmp = HWY::Mul(HWY::Add(tmp, one), half);
                                    tmp = HWY::Mul(tmp, HWY::ConvertTo(_flttype, maxCode));
                                    qaR = HWY::ConvertTo(_inttype, HWY::Round(tmp));
                                    qaR = HWY::IfThenElse(HWY::Gt(qaR, maxCode), maxCode, qaR);
                                    qaR = HWY::IfThenElse(HWY::Lt(qaR, izero), izero, qaR);
                                    qaR = HWY::Sub(qaR, midCode);//const int da = qa - midCode;
                                }

                                //const int qb = quantizeToCode(inB, quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(inBL, one), one, inBL);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::Mul(HWY::Add(tmp, one), half);
                                tmp = HWY::Mul(tmp, HWY::ConvertTo(_flttype, maxCode));
                                qbL = HWY::ConvertTo(_inttype, HWY::Round(tmp));
                                qbL = HWY::IfThenElse(HWY::Gt(qbL, maxCode), maxCode, qbL);
                                qbL = HWY::IfThenElse(HWY::Lt(qbL, izero), izero, qbL);
                                qbL = HWY::Sub(qbL, midCode); //const int db = qb - midCode;
                                if(HWY::AllTrue(_flttype, HWY::Eq(inBL, inBR)))
                                {
                                    //Mono input
                                    qbR = qbL;
                                }
                                else
                                {
                                    tmp = HWY::IfThenElse(HWY::Gt(inBR, one), one, inBR);
                                    tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                    tmp = HWY::Mul(HWY::Add(tmp, one), half);
                                    tmp = HWY::Mul(tmp, HWY::ConvertTo(_flttype, maxCode));
                                    qbR = HWY::ConvertTo(_inttype, HWY::Round(tmp));
                                    qbR = HWY::IfThenElse(HWY::Gt(qbR, maxCode), maxCode, qbR);
                                    qbR = HWY::IfThenElse(HWY::Lt(qbR, izero), izero, qbR);
                                    qbR = HWY::Sub(qbR, midCode); //const int db = qb - midCode;
                                }

                                //const int qx = (da ^ db) + midCode;
                                qaL = HWY::Add(midCode, HWY::Xor(qaL, qbL));
                                qaR = HWY::Add(midCode, HWY::Xor(qaR, qbR));

                                //wet = codeToFloat(qx, quantLevels) * currentOutput_;

                                 /*auto codeToFloat = [](int code, float levels) {
                                    const int maxCode = juce::jmax(1, static_cast<int>(levels * 2.0f) - 1);
                                    return (static_cast<float>(juce::jlimit(0, maxCode, code)) / static_cast<float>(maxCode)) * 2.0f - 1.0f;
                                };*/
                                qbL = HWY::IfThenElse(HWY::Gt(qaL, maxCode), maxCode, qaL);
                                qbL = HWY::IfThenElse(HWY::Lt(qbL, izero), izero, qbL);
                                tmp = HWY::Div(HWY::ConvertTo(_flttype, qbL), HWY::ConvertTo(_flttype, maxCode));
                                tmp = HWY::MulSub(tmp, two, one);
                                newHeldSampleL = HWY::Mul(tmp, currentOutput);
                                if(HWY::AllTrue(_inttype, HWY::Eq(qaL, qaR)))
                                {
                                    //Mono input
                                    newHeldSampleR = newHeldSampleL;
                                }
                                else
                                {
                                    qbR = HWY::IfThenElse(HWY::Gt(qaR, maxCode), maxCode, qaR);
                                    qbR = HWY::IfThenElse(HWY::Lt(qbR, izero), izero, qbR);
                                    tmp = HWY::Div(HWY::ConvertTo(_flttype, qbR), HWY::ConvertTo(_flttype, maxCode));
                                    tmp = HWY::MulSub(tmp, two, one);
                                    newHeldSampleR = HWY::Mul(tmp, currentOutput);
                                }
                            }
                            else if(currentLogicMode_ == 2 && hasBusB)
                            {
                                // Gate/compare: use bus B amplitude to gate target A.

                                //const float qa = std::round(inA * quantLevels) / quantLevels;
                                //const bool gate = std::fabs(inB) > 0.001f;
                                //wet = (gate ? qa : 0.0f) * currentOutput_;
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAL, quantLevels)), quantLevels);
                                gate = HWY::Gt(HWY::Abs(inBL), gateLevel);
                                tmp = HWY::Mul(tmp, currentOutput);
                                newHeldSampleL = HWY::IfThenElse(gate, tmp, zero);

                                //Check for mono, and avoid div and mul if the input left signals are identical to the right.
                                if(HWY::AllTrue(_flttype, HWY::Eq(inAL, inAR)) && HWY::AllTrue(_flttype, HWY::Eq(inBL, inBR)))
                                {
                                    newHeldSampleR = newHeldSampleL;
                                }
                                else
                                {
                                    tmp = HWY::Div(HWY::Round(HWY::Mul(inAR, quantLevels)), quantLevels);
                                    gate = HWY::Gt(HWY::Abs(inBR), gateLevel);
                                    tmp = HWY::Mul(tmp, currentOutput);
                                    newHeldSampleR = HWY::IfThenElse(gate, tmp, zero);
                                }
                            }
                            else
                            {
                                //const float q = std::round(inA * quantLevels) / quantLevels;
                                // wet = juce::jlimit(-1.0f, 1.0f, q) * currentOutput_;
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAL, quantLevels)), quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(tmp, one), one, tmp);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                newHeldSampleL = HWY::Mul(tmp, currentOutput);
                                if(HWY::AllTrue(_flttype, HWY::Eq(inAL, inAR)))
                                {
                                    newHeldSampleR = newHeldSampleL;
                                }
                                else
                                {
                                    tmp = HWY::Div(HWY::Round(HWY::Mul(inAR, quantLevels)), quantLevels);
                                    tmp = HWY::IfThenElse(HWY::Gt(tmp, one), one, tmp);
                                    tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                    newHeldSampleR = HWY::Mul(tmp, currentOutput);
                                }
                            }


                            //Work out which lanes the held sample should change - where holdCounter >= holdInterval
                            //(The check has already been done earlier, and the result put into 'laneMask')
                            do
                            {
                                //Here we perform the subtraction (as per  { holdCounter_[static_cast<size_t>(ch)] -= holdInterval; })
                                //But to avoid SIMD floating point errors, in comparison with the original code, 
                                //we extract the result of the subtraction from the correct lane, broadcast that result
                                //to all lanes, then re-apply the lane number increments (+0 +1, +2, etc).
                                //
                                //The alternative is to extract the holdInterval value from the correct lane, 
                                //and subtract that value from all lanes of holdCounter.
                                //Unfortunalty, this can introduce floating point rounding errors as time goes on,
                                //so we need to use the slower version as described above.
                                holdCounter = HWY::Sub(holdCounter, holdInterval);
                                holdCounter = HWY::BroadcastLane<0>(HWY::Compress(holdCounter, laneMask));
                                holdCounter = HWY::Add(holdCounter, HWY::Expand( HWY::Sub( laneNumbers, one), laneMask));

                                //Shift lanes down and set the new held sample
                                tmp = HWY::Compress(newHeldSampleL, laneMask);
                                heldSampleL = HWY::BroadcastLane<0>(tmp);
                                tmp = HWY::Compress(newHeldSampleR, laneMask);
                                heldSampleR = HWY::BroadcastLane<0>(tmp);

                                //Apply new held sample to the output
                                outputL = HWY::IfThenElse(laneMask, heldSampleL, outputL);
                                outputR = HWY::IfThenElse(laneMask, heldSampleR, outputR);

                                //Check for further lanes to process 
                                laneMask = HWY::MaskedGe(sampleLaneMask, holdCounter, holdInterval);
                            }
                            while(!HWY::AllFalse(_flttype, laneMask));
                        
                        }//end of if(!HWY::AllFalse(_flttype, laneMask))
                        
                        // const float wet = heldSample_[static_cast<size_t>(ch)];
                        //const float out = inA * (1.0f - currentMix_) + wet * currentMix_;
                        outputL = HWY::MulAdd(inAL, HWY::Sub(one, currentMix), HWY::Mul(outputL, currentMix));
                        outputR = (outputPtrR == NULL) ? HWY::Zero(_flttype) : HWY::MulAdd(inAR, HWY::Sub(one, currentMix), HWY::Mul(outputR, currentMix));

                        //Update for next round, and Write output for this round
                        if(samplesRemain >= numLanes)
                        {
                            //Use the last value of the hold counter to generate the next set of hold counters
                            holdCounter = HWY::Add(laneNumbers, HWY::BroadcastLane<MaxLanes(_flttype) - 1>(holdCounter));
                            
                            HWY::StoreU(outputL, _flttype, outputPtrL + offset);
                            if(outputPtrR != NULL)
                                HWY::StoreU(outputR, _flttype, outputPtrR + offset);

                            samplesRemain -= numLanes;
                            offset += numLanes;
                        }
                        else
                        {
                            //Use the last value of the hold counter to generate the next set of hold counters - 
                            //this is a partial block so only use the counter of the last sample
                            laneMask = HWY::Not( HWY::FirstN(_flttype, samplesRemain - 1)); 
                            holdCounter = HWY::BroadcastLane<0>(HWY::Compress(holdCounter, laneMask));
                            holdCounter = HWY::Add(laneNumbers, holdCounter);
                           
                            HWY::StoreN(outputL, _flttype, outputPtrL + offset, samplesRemain);
                            if(outputPtrR != NULL)
                                HWY::StoreN(outputR, _flttype, outputPtrR + offset, samplesRemain);

                            samplesRemain = 0;
                        }

                    } //end of while(samplesRemain > 0)

                        
                    //Save state
                    HWY::Store(currentStateValues, _flttype, currentState_.get());
                    HWY::Store(heldSampleL, _flttype, heldSample_.get());
                    HWY::Store(heldSampleR, _flttype, heldSample_.get() + numLanes);
                    HWY::Store(holdCounter, _flttype, holdCounters_.get());
                }
            private:
                void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    
                    size_t numLanes = HWY::Lanes(_flttype);
                    const int numValues = 4;
                    const FltType  one = HWY::Set(_flttype, 1.0f);
                    const FltType laneNum = HWY::Iota(_flttype, 1);

                    if(!targetState_ || (numLanes != laneCount_))
                        targetState_ = hwy::AllocateAligned<float>( (numValues < numLanes) ? numLanes : ((1+(numValues / numLanes)) * numLanes)  );

                    float * stateptr = targetState_.get();
                    stateptr[StateIndex_Bits] = targetBits_->load(std::memory_order_acquire);
                    stateptr[StateIndex_RateReduction] = targetRateReduction_->load(std::memory_order_acquire);
                    stateptr[StateIndex_Mix] = targetMix_->load(std::memory_order_acquire);
                    stateptr[StateIndex_Output] = targetOutput_->load(std::memory_order_acquire);
                    currentLogicMode_ = targetLogicMode_->load(std::memory_order_acquire);

                    if(!holdCounters_ || (numLanes != laneCount_))
                    {
                        holdCounters_ = hwy::AllocateAligned<float>(2 * numLanes);
                        HWY::Store(laneNum, _flttype, holdCounters_.get());
                        HWY::Store(laneNum, _flttype, holdCounters_.get() + numLanes);
                    }

                    if(!heldSample_ || (numLanes != laneCount_))
                    {
                        heldSample_ = hwy::AllocateAligned<float>(2 * numLanes);
                        memset(heldSample_.get(), 0, sizeof(float) * 2 * numLanes);
                    }

                    if(!laneNumber_ || (numLanes != laneCount_))
                    {
                        laneNumber_ = hwy::AllocateAligned<float>(numLanes);
                        HWY::Store(laneNum, _flttype, laneNumber_.get());
                    }

                    laneCount_ = numLanes;
                    configChanged_ = false;
                }

                const std::atomic<float> * targetBits_;
                const std::atomic<float> * targetRateReduction_;
                const std::atomic<float> * targetMix_;
                const std::atomic<float> * targetOutput_;
                const std::atomic<int> * targetLogicMode_;
                bool configChanged_;
                size_t laneCount_;
                float sampleRate_;
                
                
                
                enum StateIndex
                {
                    StateIndex_Bits = 0,
                    StateIndex_RateReduction = 1,
                    StateIndex_Mix = 2,
                    StateIndex_Output = 3,
                    StateIndex_Count = 4
                };

                hwy::AlignedFreeUniquePtr<float[]> currentState_;
                hwy::AlignedFreeUniquePtr<float[]> targetState_;
                int currentLogicMode_;
                hwy::AlignedFreeUniquePtr<float[]> smooth_;
                hwy::AlignedFreeUniquePtr<float[]> holdCounters_;
                hwy::AlignedFreeUniquePtr<float[]> heldSample_;
                hwy::AlignedFreeUniquePtr<float[]> laneNumber_;
            };



            //Create CPU specific instance
            HWY_API IPrimitiveNodeSIMDImplementation *  __CreateInstanceForCPU(float samplerate,
                                                                               const std::atomic<float> * targetbits,
                                                                               const std::atomic<float> * targetratered,
                                                                               const std::atomic<float> * targetmix,
                                                                               const std::atomic<float> * targetoutput,
                                                                               const std::atomic<int> * targetlogicmode)
            {
                return new BitCrusherNodeSIMDImplementation(samplerate, targetbits, targetratered, targetmix, targetoutput, targetlogicmode);
            }        
        }

        //========================================================================
        //Highway bootstrap

        #if HWY_ONCE || HWY_IDE

            IPrimitiveNodeSIMDImplementation *  __CreateInstance(float samplerate,
                                                                const std::atomic<float> * targetbits,
                                                                const std::atomic<float> * targetratered,
                                                                const std::atomic<float> * targetmix,
                                                                const std::atomic<float> * targetoutput,
                                                                const std::atomic<int> * targetlogicmode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                return HWY_DYNAMIC_DISPATCH_T(_create_instance_table)(samplerate, targetbits, targetratered, targetmix, targetoutput, targetlogicmode);
            }
        
        #endif
    }
}
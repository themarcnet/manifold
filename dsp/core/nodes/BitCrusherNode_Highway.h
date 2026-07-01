//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "dsp/core/nodes/BitCrusherNode_Highway.h"

#include "manifold/highway/HighwayWrapper.h"
#include "manifold/highway/HighwayMaths.h"
#include "manifold/highway/HighwaySmoother.h"
#include "manifold/highway/HighwayUtils.h"

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
                HWY_ATTR BitCrusherNodeSIMDImplementation(float samplerate,
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
                    smoother_.initialise(targetbits, targetratered, targetmix, targetoutput);
                    configure();
                }

                HWY_ATTR virtual void prepare(float sampleRate) override
                {
                    sampleRate_ = sampleRate;

                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    //const int numValues = StateIndex_Count;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    const double smoothTime = 0.01;
                    float smoothval = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
                    smoothval = juce::jlimit(0.0001f, 1.0f, smoothval);
                    smoother_.SetSmooth(smoothval);
                    smoother_.PrepareCurrentValues();

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


                HWY_ATTR virtual void reset() override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t maxLanes = hwy::HWY_NAMESPACE::MaxLanes(_flttype);

                    memset(heldSample_, 0, maxLanes * 2 * sizeof(float));
                    memset(holdCounters_, 0, maxLanes * 2 * sizeof(float));

                    const size_t numLanes = HWY::Lanes(_flttype);

                    if(configChanged_)
                    {
                        configure();
                    }
                    
                    float val;
                    for(size_t x=0; x < maxLanes; ++x)
                    {
                        val = static_cast<float>(x + 1);
                        holdCounters_[x] = val;
                        holdCounters_[x + maxLanes] = val;
                    }
                    
                    smoother_.PrepareCurrentValues();//Reset current values
                }

                HWY_ATTR virtual void run(const std::vector<AudioBufferView> & inputs,
                                        std::vector<WritableAudioBufferView> & outputs,
                                        int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t maxLanes = HWY::MaxLanes(_flttype); //for loading const values
                    const size_t numLanes = HWY::Lanes(_flttype); //actual number of lanes in use

                    if(configChanged_)
                    {
                        configure();
                    }
                    
                    const float * inputPtr1L = inputs[0].channelData[0];
                    const float * inputPtr1R = (inputs[0].numChannels > 1) ? inputs[0].channelData[1] : NULL;
                    const bool hasBusB = inputs.size() >= 2;
                    const float * inputPtr2L = hasBusB ? inputs[1].channelData[0] : NULL;
                    const float * inputPtr2R = (hasBusB && (inputs[1].numChannels > 1)) ? inputs[1].channelData[1] : NULL;
                    const bool outputMono = outputs[0].numChannels == 1;
                    float * outputPtrL = outputs[0].channelData[0];
                    float * outputPtrR = !outputMono ? outputs[0].channelData[1] : NULL;
                    size_t offset = 0;
                    size_t samplesRemain = numsamples;
                    
                    const FltType half = HWY::Set(_flttype, 0.5f);
                    const FltType one = HWY::Add(half,half);
                    const FltType two = HWY::Add(one,one);
                    const FltType gateLevel = HWY::Set(_flttype, 0.001f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType negone = HWY::Sub( zero,one );
                    const FltType laneNumbers = HWY::Load(_flttype, laneNumber_);
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType izero = HWY::Sub(ione,ione);

                    FltType holdCounter = HWY::Load(_flttype, holdCounters_);
                    FltMaskType laneMask, gate, sampleLaneMask;
                    FltType currentOutput, currentBits, currentRateReduction, currentMix;
                    FltType heldSampleL = HWY::Load(_flttype, heldSample_);
                    FltType heldSampleR = HWY::Load(_flttype, &heldSample_[maxLanes] );
                    FltType holdInterval, tmp, inAL,inAR, outputL, outputR, newHeldSampleL, newHeldSampleR, quantLevels, maxCodeFlt;
                    FltType inBL = zero;
                    FltType inBR = zero;
                    IntType maxCode, midCode, qaL, qaR, qbL, qbR;
                    size_t sampleLaneCount, laneidx;

                    Smoother::ValueType targetStateVals, currentStateVals, smoothVals;
                    smoother_.Start(targetStateVals, currentStateVals, smoothVals);

                    //Pre-fetch
                    hwy::Prefetch(inputPtr1L);
                    if(inputPtr1R != NULL)
                        hwy::Prefetch(inputPtr1R );
                    if(inputPtr2L != NULL)
                        hwy::Prefetch(inputPtr2L);
                    if(inputPtr2R != NULL)
                        hwy::Prefetch(inputPtr2R);

                    while(samplesRemain > 0)
                    {
                        sampleLaneCount = (samplesRemain > numLanes) ? numLanes : samplesRemain;

                        smoother_.Run(sampleLaneCount, smoothVals, targetStateVals, currentStateVals,
                                      currentBits, currentRateReduction, currentMix, currentOutput);

                        holdInterval = HWY::IfThenElse(HWY::Lt(currentRateReduction, one), one, currentRateReduction);
                        
                        //By default, the output is the currently. held sample
                        outputL = heldSampleL;
                        outputR = heldSampleR;

                        //Read input A
                        if(samplesRemain >= numLanes)
                        {
                            sampleLaneMask = HWY::Not( HWY::MaskFalse(_flttype));
                            inAL = HWY::LoadU(_flttype, inputPtr1L + offset);
                            inAR = (inputPtr1R == NULL) ? inAL : HWY::LoadU(_flttype, inputPtr1R + offset);
                        }
                        else
                        {
                            sampleLaneMask = HWY::FirstN(_flttype, sampleLaneCount);
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

                            //Generate potential new held sample values.
                            //These will get picked out and used later
                            newHeldSampleL = heldSampleL;
                            newHeldSampleR = heldSampleR;
                            if(hasBusB && (currentLogicMode_ == 1))
                            {
                                //Read input B
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

                                //Float version of maxCode - used several times below.
                                maxCodeFlt = HWY::ConvertTo(_flttype, maxCode);
                                
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
                                //
                                //A Note about rounding:
                                // The base version uses std::round as part of this process. In the tie-break condition (e.g: 1234.5) will round away from zero (e.g: 1234.5 -> 1235.0)
                                //HWY::Round on x86/x64 will round towards EVEN.  So 1234.5 will round DOWN to 1234.0
                                //Thus, we avoid using HWY::Round, and instead truncate the value +- 0.5 (plus if > 0, subtract if < 0) to match what std::round does.
                                //
                                tmp = HWY::IfThenElse(HWY::Gt(inAL, one), one, inAL);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::MulAdd(tmp, half, half);
                                tmp = HWY::Mul(tmp, maxCodeFlt);
                                qaL = HWY::ConvertTo(_inttype,HWY::Trunc(HWY::IfThenElse(HWY::Gt(tmp, zero), HWY::Add(tmp, half), HWY::Sub(tmp, half)))); //Rounding like std::round
                                qaL = HWY::IfThenElse(HWY::Gt(qaL, maxCode), maxCode, qaL);
                                qaL = HWY::IfThenElse(HWY::Lt(qaL, izero), izero, qaL);
                                qaL = HWY::Sub(qaL, midCode); //const int da = qa - midCode;
                                
                                tmp = HWY::IfThenElse(HWY::Gt(inAR, one), one, inAR);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::MulAdd(tmp, half, half);
                                tmp = HWY::Mul(tmp,maxCodeFlt);
                                qaR = HWY::ConvertTo(_inttype,HWY::Trunc(HWY::IfThenElse(HWY::Gt(tmp, zero), HWY::Add(tmp, half), HWY::Sub(tmp, half)))); //Rounding like std::round
                                qaR = HWY::IfThenElse(HWY::Gt(qaR, maxCode), maxCode, qaR);
                                qaR = HWY::IfThenElse(HWY::Lt(qaR, izero), izero, qaR);
                                qaR = HWY::Sub(qaR, midCode);//const int da = qa - midCode;
                                
                                //const int qb = quantizeToCode(inB, quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(inBL, one), one, inBL);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::MulAdd(tmp, half, half);
                                tmp = HWY::Mul(tmp, maxCodeFlt);
                                qbL = HWY::ConvertTo(_inttype,HWY::Trunc(HWY::IfThenElse(HWY::Gt(tmp, zero), HWY::Add(tmp, half), HWY::Sub(tmp, half)))); //Rounding like std::round
                                qbL = HWY::IfThenElse(HWY::Gt(qbL, maxCode), maxCode, qbL);
                                qbL = HWY::IfThenElse(HWY::Lt(qbL, izero), izero, qbL);
                                qbL = HWY::Sub(qbL, midCode); //const int db = qb - midCode;
                                
                                tmp = HWY::IfThenElse(HWY::Gt(inBR, one), one, inBR);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                tmp = HWY::MulAdd(tmp, half, half);
                                tmp = HWY::Mul(tmp, maxCodeFlt);
                                qbR = HWY::ConvertTo(_inttype,HWY::Trunc(HWY::IfThenElse(HWY::Gt(tmp, zero), HWY::Add(tmp, half), HWY::Sub(tmp, half)))); //Rounding like std::round
                                qbR = HWY::IfThenElse(HWY::Gt(qbR, maxCode), maxCode, qbR);
                                qbR = HWY::IfThenElse(HWY::Lt(qbR, izero), izero, qbR);
                                qbR = HWY::Sub(qbR, midCode); //const int db = qb - midCode;
                            
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
                                tmp = HWY::Div(HWY::ConvertTo(_flttype, qbL), maxCodeFlt);
                                tmp = HWY::MulSub(tmp, two, one);
                                newHeldSampleL = HWY::Mul(tmp, currentOutput);
                                
                                qbR = HWY::IfThenElse(HWY::Gt(qaR, maxCode), maxCode, qaR);
                                qbR = HWY::IfThenElse(HWY::Lt(qbR, izero), izero, qbR);
                                tmp = HWY::Div(HWY::ConvertTo(_flttype, qbR), maxCodeFlt);
                                tmp = HWY::MulSub(tmp, two, one);
                                newHeldSampleR = HWY::Mul(tmp, currentOutput);
                            }
                            else if(hasBusB && (currentLogicMode_ == 2))
                            {
                                //Read input B
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

                                // Gate/compare: use bus B amplitude to gate target A.

                                //const float qa = std::round(inA * quantLevels) / quantLevels;
                                //const bool gate = std::fabs(inB) > 0.001f;
                                //wet = (gate ? qa : 0.0f) * currentOutput_;
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAL, quantLevels)), quantLevels);
                                gate = HWY::Gt(HWY::Abs(inBL), gateLevel);
                                tmp = HWY::Mul(tmp, currentOutput);
                                newHeldSampleL = HWY::IfThenElse(gate, tmp, zero);

                                
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAR, quantLevels)), quantLevels);
                                gate = HWY::Gt(HWY::Abs(inBR), gateLevel);
                                tmp = HWY::Mul(tmp, currentOutput);
                                newHeldSampleR = HWY::IfThenElse(gate, tmp, zero);
                            }
                            else
                            {
                                //const float q = std::round(inA * quantLevels) / quantLevels;
                                // wet = juce::jlimit(-1.0f, 1.0f, q) * currentOutput_;
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAL, quantLevels)), quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(tmp, one), one, tmp);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                newHeldSampleL = HWY::Mul(tmp, currentOutput);
                           
                                tmp = HWY::Div(HWY::Round(HWY::Mul(inAR, quantLevels)), quantLevels);
                                tmp = HWY::IfThenElse(HWY::Gt(tmp, one), one, tmp);
                                tmp = HWY::IfThenElse(HWY::Lt(tmp, negone), negone, tmp);
                                newHeldSampleR = HWY::Mul(tmp, currentOutput);
                            }


                            //Work out which lanes the held sample should change - where holdCounter >= holdInterval
                            //(The check has already been done earlier, and the result put into 'laneMask')
                            do
                            {
                                laneidx = HWY::FindKnownFirstTrue(_flttype, laneMask);

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
                                holdCounter = HWY::BroadcastLane<0>(HWY::SlideDownLanes(_flttype, holdCounter, laneidx));
                                holdCounter = HWY::Add(holdCounter, HWY::SlideUpLanes(_flttype, laneNumbers, laneidx + 1));

                                //Shift lanes down and set the new held sample for current and future lanes
                                tmp = HWY::SlideDownLanes(_flttype,newHeldSampleL, laneidx);
                                heldSampleL = HWY::BroadcastLane<0>(tmp);
                                tmp = HWY::SlideDownLanes(_flttype,newHeldSampleR, laneidx);
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
                        outputR = (outputPtrR == NULL) ? outputL : HWY::MulAdd(inAR, HWY::Sub(one, currentMix), HWY::Mul(outputR, currentMix));

                        //Update for next round, and Write output for this round
                        if(samplesRemain >= numLanes)
                        {
                            HWY::Utils::BroadcastLastLane(holdCounter, tmp);
                            holdCounter = HWY::Add(laneNumbers, tmp);
                            
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
                            holdCounter = HWY::BroadcastLane<0>(HWY::SlideDownLanes(_flttype, holdCounter, samplesRemain - 1));
                            holdCounter = HWY::Add(laneNumbers, holdCounter);
                           
                            HWY::StoreN(outputL, _flttype, outputPtrL + offset, samplesRemain);
                            if(outputPtrR != NULL)
                                HWY::StoreN(outputR, _flttype, outputPtrR + offset, samplesRemain);

                            samplesRemain = 0;
                        }

                    } //end of while(samplesRemain > 0)

                        
                    //Save state
                    smoother_.End(currentStateVals);
                    HWY::Store(heldSampleL, _flttype, heldSample_);
                    HWY::Store(heldSampleR, _flttype, &heldSample_[maxLanes]);
                    HWY::Store(holdCounter, _flttype, holdCounters_);
                }
            private:
                HWY_ATTR void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    
                    const size_t maxLanes = HWY::MaxLanes(_flttype);
                    
                    smoother_.UpdateTargetValues();

                    if(!stateValues_)
                    {
                        stateValues_ = hwy::AllocateAligned<float>(6 * maxLanes);
                        holdCounters_ = stateValues_.get();
                        heldSample_ = &holdCounters_[maxLanes * 2];
                        laneNumber_ = &heldSample_[maxLanes * 2];

                        float val;
                        for(size_t x=0; x < maxLanes; ++x)
                        {
                            val = static_cast<float>(x + 1);
                            holdCounters_[x] = val;
                            holdCounters_[x + maxLanes] = val;
                        
                            heldSample_[x] = 0;
                            heldSample_[x + maxLanes] = 0;
                        
                            laneNumber_[x] = val;
                        }
                    }

                    currentLogicMode_ = targetLogicMode_->load(std::memory_order_acquire);

                    configChanged_ = false;
                }

                const std::atomic<float> * targetBits_;
                const std::atomic<float> * targetRateReduction_;
                const std::atomic<float> * targetMix_;
                const std::atomic<float> * targetOutput_;
                const std::atomic<int> * targetLogicMode_;
                bool configChanged_;
                float sampleRate_;
                
                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 4> Smoother;

                Smoother smoother_;
                int currentLogicMode_;
                hwy::AlignedFreeUniquePtr<float[]> stateValues_;
                float * holdCounters_;
                float * heldSample_;
                float * laneNumber_;
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

            IPrimitiveNodeSIMDImplementation *  __CreateInstance(int target,
                                                                float samplerate,
                                                                const std::atomic<float> * targetbits,
                                                                const std::atomic<float> * targetratered,
                                                                const std::atomic<float> * targetmix,
                                                                const std::atomic<float> * targetoutput,
                                                                const std::atomic<int> * targetlogicmode ,
                                                                hwy::RunHighwayErrorCode * retErrorCode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                IPrimitiveNodeSIMDImplementation * retiface = NULL;

                hwy::RunHighwayErrorCode res =  hwy::RunHighwayFunction(target, &retiface, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                        samplerate, targetbits, targetratered, targetmix, targetoutput, targetlogicmode);

                *retErrorCode = res;
                return retiface;
            }
        
        #endif
    }
}

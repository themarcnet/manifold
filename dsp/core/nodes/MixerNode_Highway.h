//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "dsp/core/nodes/MixerNode_Highway.h"

#include "manifold/highway/HighwayWrapper.h"
#include "manifold/highway/HighwayMaths.h"
#include "manifold/highway/HighwaySmoother.h"
#include "manifold/highway/HighwayUtils.h"

#include <cmath>

namespace dsp_primitives
{
    namespace MixerNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {
            template<int MAXBUSSES>
            class MixerNodeSIMDImplementation : public IPrimitiveNodeSIMDImplementation
            {
            private:
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntMaskType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltMaskType;

            public:
                HWY_ATTR MixerNodeSIMDImplementation(const std::atomic<int>* targetInputCount,
                                                    const std::atomic<float>* targetGains,
                                                    const std::atomic<float>* targetPans,
                                                    const std::atomic<float>* targetMaster) :    targetInputCount_(targetInputCount),  
                                                                                                laneCount_(0),
                                                                                                configChanged_(true)
                {
                    //We use the first smoother to handle the 'master' value as well
                    //We do include it in smoothers for all other inputs, but it is ignored
                    //With SIMD, calculating the smoothing for 3 values should be no more expensive than calculating smoothing for 2.
                    for(int b = 0; b < MAXBUSSES; ++b)
                    {
                        smoothers_[b].initialise(&targetGains[b], &targetPans[b], &targetMaster[0]);
                    }
                }

                HWY_ATTR virtual void prepare(float sampleRate) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const int numValues = MixerNode::kMaxBusses;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    const double smoothTime = 0.01;
                    float smoothval = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
                    smoothval = juce::jlimit(0.0001f, 1.0f, smoothval);
                    
                    if(inputCount_ == 0)
                    {
                        configure();
                    }

                    for(int b = 0; b < MAXBUSSES; ++b)
                    {
                        smoothers_[b].SetSmooth(smoothval);
                        smoothers_[b].PrepareCurrentValues();
                    }
                    

                    laneCount_ = numLanes;
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

                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one, one);

                    configure();

                    for(int x = 0; x < MAXBUSSES; ++x)
                    {
                        smoothers_[x].PrepareCurrentValues();//Reset current values
                    }
                }

                HWY_ATTR virtual void run(const std::vector<AudioBufferView> & inputs,
                                            std::vector<WritableAudioBufferView> & outputs,
                                            int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);
                    
                    if((configChanged_) || (numLanes != laneCount_))
                    {
                        configure();
                    }
                    
                    const FltType half = HWY::Set(_flttype, 0.5f);
                    const FltType one = HWY::Add(half,half);
                    const FltType zero =  HWY::Sub(one,one);
                    const FltType negone = HWY::Sub( zero,one );
                    const FltType  halfpiScalar = HWY::Set(_flttype, 3.14159265358979323846f / 2);
                    const size_t inputBufferCount = (inputCount_ > inputs.size()) ? inputs.size() : inputCount_;
                    const AudioBufferView * inputBufferViews = inputs.data();
                    
                    
                    FltType inL, inR, outL, outR, currentBusPan, currentBusGain, tmp, panL, panR, currentMaster;
                    
                    const float * const * inputPtrs;
                    const bool outputMono = outputs[0].numChannels == 1;
                    float * outputPtrL = outputs[0].channelData[0];
                    float * outputPtrR = !outputMono ? outputs[0].channelData[1] : NULL;

                    Smoother * cursmoother;
                    Smoother::ValueType targetValues;
                    Smoother::ValueType currentValues;
                    Smoother::ValueType smoothValues;
                    
                    bool haveLoaded = false;
                    size_t offset = 0;
                    size_t sampleLaneCount;
                    size_t samplesRemain = static_cast<size_t>(numsamples);
                    const AudioBufferView * curbuf;
                    while(samplesRemain > 0)
                    {
                        sampleLaneCount = (samplesRemain > numLanes) ? numLanes : samplesRemain;

                        outL = zero;
                        outR = zero;
                        currentMaster = zero;
                        for(size_t bus = 0; bus < inputBufferCount; ++bus)
                        {
                            if(bus >= inputBufferCount)
                                break;

                            //Load current bus
                            smoothers_[bus].Start(targetValues, currentValues, smoothValues);

                            cursmoother = &smoothers_[bus];
                            curbuf = &inputBufferViews[bus];
                            inputPtrs = curbuf->channelData;

                            //Load input values
                            inL = HWY::LoadU(_flttype, inputPtrs[0] + offset);
                            inR = (curbuf->numChannels > 1) ? HWY::LoadU(_flttype, inputPtrs[1] + offset) : inL;

                            //Run value smoother to obtain current gain and pan values
                            //If this is bus 0 - the first input, then the 'master' is also calculated, and is to be used later
                            //For subsequent busses, the 'master' value on those smoothers is to be ignored and thrown away - we just apply the
                            //smoothed 'master' value that was obtained from the first input.
                            cursmoother->Run(sampleLaneCount, smoothValues, targetValues, currentValues, currentBusGain, currentBusPan, (bus == 0) ? currentMaster : tmp);

                            //Apply panning
                            /*
                            * static inline void equalPowerPan(float pan, float& gainL, float& gainR) {
                                const float t = 0.5f * (juce::jlimit(-1.0f, 1.0f, pan) + 1.0f);
                                gainL = std::cos(0.5f * juce::MathConstants<float>::pi * t);
                                gainR = std::sin(0.5f * juce::MathConstants<float>::pi * t);
                            }
                            */
                            //where: pan = pans_[busIndex] (part of the smoother - output via currentBusPan), and gainL and gainR are pure outputs
                            
                            tmp = HWY::IfThenElse(HWY::Lt(currentBusPan, negone), negone, currentBusPan);
                            tmp = HWY::IfThenElse(HWY::Gt(tmp, one), one, tmp);
                            tmp = HWY::Add(one, tmp);
                            tmp = HWY::Mul(half, tmp);
                            tmp = HWY::Mul(tmp, halfpiScalar);
                            HWY::SinCos(_flttype, tmp, panR, panL); //sin to panR, cos to panL

                            // outL += inL * gains_[busIndex] * panL;
                            //outR += inR * gains_[busIndex] * panR;
                            panL = HWY::Mul(panL, currentBusGain);
                            panR = HWY::Mul(panR, currentBusGain);

                            outL = HWY::MulAdd(inL, panL, outL);
                            outR = HWY::MulAdd(inR, panR, outR);

                            //Save smoother state for this bus
                            smoothers_[bus].End(currentValues);
                        }
                        //End of for loop over busses

                        //Apply the 'master' to the output
                        outL = HWY::Mul(currentMaster, outL);
                        outR = HWY::Mul(currentMaster, outR);

                        //Store result
                        if(samplesRemain >= numLanes)
                        {
                            HWY::StoreU(outL, _flttype, outputPtrL + offset);
                            if(outputPtrR != NULL)
                                HWY::StoreU(outR, _flttype, outputPtrR + offset);
                        }
                        else
                        {
                            HWY::StoreN(outL, _flttype, outputPtrL + offset, samplesRemain);
                            if(outputPtrR != NULL)
                                HWY::StoreN(outR, _flttype, outputPtrR + offset, samplesRemain);
                        }

                        haveLoaded = true;
                        offset += sampleLaneCount;
                        samplesRemain -= sampleLaneCount;
                    }
                }

            private:
                HWY_ATTR void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    const FltType one = HWY::Set(_flttype, 1.0f); 

                    inputCount_ = juce::jlimit(1, MAXBUSSES, targetInputCount_->load(std::memory_order_acquire));
                    
                    for(size_t x = 0; x < inputCount_; ++x)
                    {
                        smoothers_[x].UpdateTargetValues();
                    }

                    laneCount_ = numLanes;
                    configChanged_ = false;
                }

                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 3> Smoother;
                
                const std::atomic<int>* targetInputCount_;
                size_t laneCount_;
                bool configChanged_;
                size_t inputCount_;
                Smoother smoothers_[MAXBUSSES];
            };

            //Create CPU specific instance
            template<int MAXBUSSES>
            HWY_API IPrimitiveNodeSIMDImplementation *  __CreateInstanceForCPU(const std::atomic<int>* targetInputCount,
                                                                               const std::atomic<float>* targetGains,
                                                                               const std::atomic<float>* targetPans,
                                                                               const std::atomic<float>* targetMaster)
            {
                return new MixerNodeSIMDImplementation<MAXBUSSES>(targetInputCount, targetGains, targetPans, targetMaster);
            }
        }

        //========================================================================
        //Highway bootstrap

        #if HWY_ONCE || HWY_IDE

            template<int MAXBUSSES>
            IPrimitiveNodeSIMDImplementation *  __CreateInstance(int target,
                                                                 const std::atomic<int>* targetInputCount,
                                                                 const std::atomic<float>* targetGains,
                                                                 const std::atomic<float>* targetPans,
                                                                 const std::atomic<float>* targetMaster,
                                                                 hwy::RunHighwayErrorCode * retErrCode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU<MAXBUSSES>);
                
                IPrimitiveNodeSIMDImplementation * ret = NULL;
                hwy::RunHighwayErrorCode errCode = hwy::RunHighwayFunction(target, &ret, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                           targetInputCount, targetGains, targetPans, targetMaster);
                *retErrCode = errCode;
                return ret;
            }

        #endif
    }
}

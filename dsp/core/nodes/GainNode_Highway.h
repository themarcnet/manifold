//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE
#define HWY_TARGET_INCLUDE "dsp/core/nodes/GainNode_Highway.h"

#include "manifold/highway/HighwayWrapper.h"
#include "manifold/highway/HighwaySmoother.h"
#include "manifold/highway/HighwayUtils.h"

#include <cmath>

namespace dsp_primitives
{
    namespace GainNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {

            class GainNodeSIMDImplementation : public IPrimitiveNodeSIMDImplementation
            {
            private:
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;

            public:
                HWY_ATTR GainNodeSIMDImplementation(int numChannels,
                                                    const std::atomic<float> * targetGain,
                                                    const std::atomic<bool> * targetMuted) : numChannels_(numChannels),
                                                                                             laneCount_(0),
                                                                                             configChanged_(true),
                                                                                             targetMuted_(targetMuted)
                {
                    smoother_.initialise(targetGain);
                }

                const char * targetName() const override
                {
                    return hwy::TargetName(HWY_TARGET);
                }

                virtual void configChanged() override
                {
                    configChanged_ = true;
                }

                HWY_ATTR virtual void reset() override
                {
                    smoother_.ZeroCurrentValues();
                }

                HWY_ATTR virtual void prepare(float sampleRate) override
                {   
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    //Configure smoother
                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    const double smoothingTimeSeconds = 0.01;
                    float smoothingCoeff = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sr)));
                    smoothingCoeff = juce::jlimit(0.0001f, 1.0f, smoothingCoeff);
                    smoother_.SetSmooth(smoothingCoeff);

                    //Set current gain
                    smoother_.PrepareCurrentValues();
                }

                HWY_ATTR virtual void run(const std::vector<AudioBufferView> & inputs,
                                 std::vector<WritableAudioBufferView> & outputs,
                                 int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    if(configChanged_)
                    {
                        const bool muted = targetMuted_->load(std::memory_order_acquire);
                        if(muted)
                        {
                            //Zero the target values
                            smoother_.ZeroTargetValues();
                        }
                        else
                        {
                            //Re-read target values
                            smoother_.UpdateTargetValues();
                        }

                        configChanged_ = false;
                    }

                  
                    const int numChannels = juce::jmin(numChannels_,
                                                       inputs[0].numChannels,
                                                       outputs[0].numChannels);
                    if (numChannels <= 0)
                        return;

                    Smoother::ValueType targetStateValues, currentStateValues, smoothVals;
                    FltType lValues = HWY::Zero(_flttype);
                    FltType rValues = lValues;
                    FltType gainValues;
                    const float * const * inputPtrs = inputs[0].channelData;
                    float * const * outputPtrs = outputs[0].channelData;

                    //Start the gain smoother
                    smoother_.Start(targetStateValues, currentStateValues, smoothVals);
                    
                    //Process samples
                    size_t offset = 0;
                    size_t sampleLaneCount;
                    size_t samplesRemain = static_cast<size_t>(numsamples);
                    while(samplesRemain > 0)
                    {
                        //How many samples to process? 
                        if(samplesRemain >= numLanes)
                        {
                            sampleLaneCount = numLanes;
                            
                            //Load input values
                            lValues = HWY::LoadU(_flttype, inputPtrs[0] + offset);
                            rValues = (numChannels > 1) ? HWY::LoadU(_flttype, inputPtrs[1] + offset) : lValues;
                        }
                        else
                        {
                            sampleLaneCount = samplesRemain;
                            
                            //Load input values
                            lValues = HWY::LoadN(_flttype, inputPtrs[0] + offset, samplesRemain);
                            rValues = (numChannels > 1) ? HWY::LoadN(_flttype, inputPtrs[1] + offset, samplesRemain) : lValues;
                        }

                        
                        //Run the gain smoother 
                        smoother_.Run(sampleLaneCount, smoothVals, targetStateValues, currentStateValues, gainValues);

                        //Apply gain -
                        lValues = HWY::Mul(lValues, gainValues);
                        rValues = (numChannels > 1) ? HWY::Mul(rValues, gainValues) : lValues;
                        
                        //Write out
                        if(sampleLaneCount == numLanes)
                        {
                            HWY::StoreU(lValues, _flttype, outputPtrs[0] + offset);
                            if(numChannels > 1)
                                HWY::StoreU(rValues, _flttype, outputPtrs[1] + offset);
                        }
                        else
                        {
                            HWY::StoreN(lValues, _flttype, outputPtrs[0] + offset, sampleLaneCount);
                            if(numChannels > 1)
                                HWY::StoreN(rValues, _flttype, outputPtrs[1] + offset, sampleLaneCount);
                        }

                        //Next
                        samplesRemain -= sampleLaneCount;
                        offset += sampleLaneCount;
                    }

                    //Update smoother state
                    smoother_.End(currentStateValues);
                }

            private:
              
                const int numChannels_;
                bool configChanged_;
                int laneCount_;

                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 1> Smoother;

                Smoother smoother_;
                const std::atomic<bool> * targetMuted_;

                float currentGain_ = 0.0f;
                float aPowLanes_ = 0.0f;
            };

            //Create CPU specific instance
            HWY_API IPrimitiveNodeSIMDImplementation * __CreateInstanceForCPU(int numChannels,
                                                                              const std::atomic<float> * targetGain,
                                                                              const std::atomic<bool> * targetMuted)
            {
                return new GainNodeSIMDImplementation(numChannels, targetGain, targetMuted);
            }
        }

        //========================================================================
        //Highway bootstrap

        #if HWY_ONCE || HWY_IDE

            IPrimitiveNodeSIMDImplementation * __CreateInstance(int target, 
                                                                int numChannels,
                                                                const std::atomic<float> * targetGain,
                                                                const std::atomic<bool> * targetMuted, 
                                                                hwy::RunHighwayErrorCode * retErrCode)
            {
                 HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                
                IPrimitiveNodeSIMDImplementation * ret = NULL;
                hwy::RunHighwayErrorCode errCode = hwy::RunHighwayFunction(target, &ret, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                           numChannels, targetGain, targetMuted);
                *retErrCode = errCode;
                return ret;
            }

        #endif
    }
}

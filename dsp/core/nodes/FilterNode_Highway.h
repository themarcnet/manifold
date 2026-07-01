//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE 
#define HWY_TARGET_INCLUDE "dsp/core/nodes/FilterNode_Highway.h"

#include <manifold/highway/HighwayWrapper.h>
#include <manifold/highway/HighwayMaths.h>
#include <manifold/highway/HighwaySmoother.h>
#include <manifold/highway/HighwayUtils.h>
#include <manifold/highway/HighwayDebug.h>

#include <manifold/debugging/Logging.h>

#include <cmath>

#ifndef __HIGHWAY_FILTER_LOGGER_IFACE
#define __HIGHWAY_FILTER_LOGGER_IFACE

namespace dsp_primitives
{
    namespace FilterNode_Highway
    {
        class FilterNode_Highway_Logging_IFace : public IPrimitiveNodeSIMDImplementation
        {
        public:
            virtual Debug::Logger & GetLogger()  = 0;
        };
    }
}

#endif


namespace dsp_primitives
{
    namespace FilterNode_Highway
    {
        //Do not change this namespace. This separates the specific SIMD implementaions from each other
        namespace HWY_NAMESPACE
        {

            class FilterNodeSIMDImplementation : public FilterNode_Highway_Logging_IFace
            {
            private:
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::BlockDFromD< hwy::HWY_NAMESPACE::DFromV<FltType>>> FltBlkType;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>> IntMaskType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltMaskType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::BlockDFromD< hwy::HWY_NAMESPACE::DFromV<FltType>>> FltBlkMaskType;

            public:
                HWY_ATTR FilterNodeSIMDImplementation(const std::atomic<float> * targetCutoffHz,
                                                      const std::atomic<float> * targetResonance,
                                                      const std::atomic<float> * targetMix)        : configChanged_(true)
                {
                    smoother_.initialise(targetCutoffHz, targetResonance, targetMix);
                }

                virtual  Debug::Logger & GetLogger()  override
                {
                    return logger_;
                }

                HWY_ATTR virtual void prepare(float sampleRate) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t maxLanes = HWY::MaxLanes(_flttype);

                    //Set up value smoother
                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    const double smoothingTimeSeconds = 0.02;
                    float smoothval = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sr)));
                    smoothval = juce::jlimit(0.0001f, 1.0f, smoothval);
                    smoother_.SetSmooth(smoothval);
                    smoother_.PrepareCurrentValues();

                    if(!stateValues_)
                    {
                        stateValues_ = hwy::AllocateAligned<float>(maxLanes * 6);
                        sampleRateRcp_ = stateValues_.get();
                        z1_ = &sampleRateRcp_[maxLanes];
                        z2_ = &z1_[maxLanes * 2];
                    }

                    float smpRateRcp = static_cast<float>(1.0 / sr);
                    for(size_t x = 0; x < maxLanes; ++x)
                    {
                        sampleRateRcp_[x] = smpRateRcp;
                    }

                    memset(z1_, 0, maxLanes * 2 * sizeof(float));
                    memset(z2_, 0, maxLanes * 2 * sizeof(float));
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
                    const size_t maxLanes = HWY::Lanes(_flttype);

                     // Initialize feedback state to zero
                    //Two channels, so x number of lanes by 2
                    memset(z1_, 0, maxLanes * 2 * sizeof(float));
                    memset(z2_, 0, maxLanes * 2 * sizeof(float));
                }

                HWY_ATTR virtual void run(const std::vector<AudioBufferView> & inputs,
                                 std::vector<WritableAudioBufferView> & outputs,
                                 int numsamples) override
                {
                    //It is assumed that the caller, the base implementation of FilterNode, has 
                    //already checked the input and output buffer counts

                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::DFromV<FltBlkType> _blktype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    constexpr size_t maxLanes = _flttype.MaxLanes(); //for use with state memory only
                    constexpr size_t lanesPerBlock = 4; //128 bits
                    const size_t numBlocks = HWY::Blocks(_flttype);
                    const size_t numLanes = HWY::Lanes(_flttype); //actual number of lanes in use

                    if(configChanged_)
                    {
                        configChanged_ = false;
                        smoother_.UpdateTargetValues();
                    }
                    
                   
                    const float * inputPtrL = inputs[0].channelData[0];
                    const float * inputPtrR = (inputs[0].numChannels > 1) ? inputs[0].channelData[1] : NULL;
                    float * outputPtrL = outputs[0].channelData[0];
                    float * outputPtrR = (outputs[0].numChannels > 1) ? outputs[0].channelData[1] : NULL;
                    
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType sampleRateRcp = HWY::Load(_flttype, sampleRateRcp_);
                    const FltType neg2xpi = HWY::Set(_flttype, -2 * 3.141592653589793238f);
                    const FltType minNormalised = HWY::Set(_flttype, 0.0001f);
                    const FltType maxNormalised = HWY::Set(_flttype, 0.49f);
                    const FltType resonanceScaler = HWY::Set(_flttype, 0.6f);
                    const FltType feedbackScaler = HWY::Set(_flttype, -0.85f);
                    const FltBlkMaskType upperBlockMask = HWY::Dup128MaskFromMaskBits(_blktype, 0xC);
                    
                    //Load current state
                    FltType z1L = HWY::Load(_flttype, z1_);
                    FltType z1R = HWY::Load(_flttype, &z1_[maxLanes]);
                    FltType z2L = HWY::Load(_flttype, z2_);
                    FltType z2R = HWY::Load(_flttype, &z2_[maxLanes]);
                    FltType currentResonance = zero;
                    FltType currentMix = currentResonance;
                    FltType currentCutoff = currentResonance;
                    FltType inL, inR, normalised, alpha, negfeedback, tmp, origL, origR, filteredL, filteredR;
                    FltType lastExpNormalised, lastExpShaping, lastExpAlpha;
                    FltType outL = zero;
                    FltType outR = zero;
                    FltMaskType  sampleLaneMask, blockMask, expcmp;
                    FltBlkType curAlpha, curNegFeedback, curIn, curZ1, curZ2, filteredLower, filteredHigher, x, z1Lower, z1Higher;
                    
                    //Start the smoother to get current state
                    Smoother::ValueType targetValues, currentValues, smoothValues;
                    smoother_.Start(targetValues, currentValues, smoothValues);

                    //Pre-fetch
                    hwy::Prefetch(inputPtrL);
                    if(inputPtrR != NULL)
                        hwy::Prefetch(inputPtrR);

                    blockMask = HWY::MaskFalse(_flttype);
                    filteredL = zero;
                    filteredR = zero;

                    bool first = true;
                    bool useCachedExpVal = false;
                    size_t sampleLaneCount;
                    size_t offset = 0;
                    size_t samplesRemain = static_cast<size_t>(numsamples);
                    while (samplesRemain > 0)
                    {
                        if(samplesRemain >= numLanes)
                        {
                            sampleLaneCount = numLanes;
                            inL =  HWY::LoadU(_flttype, inputPtrL + offset);
                            inR = (inputPtrR == NULL) ? inL : HWY::LoadU(_flttype, inputPtrR + offset);
                            sampleLaneMask = HWY::Not(HWY::MaskFalse(_flttype));

                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "input L", inL);
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "input R", inR);
                        }
                        else
                        {
                            sampleLaneCount = samplesRemain;
                            sampleLaneMask = HWY::FirstN(_flttype, sampleLaneCount);
                            
                            //Partial read - 
                            inL = HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtrL + offset);
                            inR = (inputPtrR == NULL) ? inL : HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtrR + offset);

                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "input L", inL,sampleLaneMask);
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "input R", inR, sampleLaneMask);
                        }
                        
                        //Run the smoother to get the next N values for cutoff, resonance and mix.
                        //Run it in reverse mode to return the values in reverse order (such that lane 0 contains the last value)
                        smoother_.Run(sampleLaneCount, smoothValues, targetValues, currentValues,
                                       currentCutoff, currentResonance, currentMix);

                        //const float feedback = resonance_ * 0.85f;
                        //We've set 'feedbackScaler' to a negative value, thus negfeedback = resonance_ * -0.85f
                        negfeedback = HWY::Mul(currentResonance, feedbackScaler);

                        // Compute alpha (biquad coefficient)
                        //
                        //const float normalized = juce::jlimit(0.0001f, 0.49f, currentCutoff / sr);  
                        //(1 / sr * currentCutOff)
                        normalised = HWY::Mul(sampleRateRcp, currentCutoff);
                        normalised = HWY::IfThenElse(HWY::Lt(normalised, minNormalised), minNormalised, normalised);
                        normalised = HWY::IfThenElse(HWY::Gt(normalised, maxNormalised), maxNormalised, normalised);

                        //const float shaping = 1.0f + currentResonance * 0.6f;
                        tmp = HWY::MulAdd(currentResonance, resonanceScaler, one);
                        
                        //const float alpha = 1.0f - std::exp(-2.0f * piScalar * normalized * shaping);
                        //  - shaping is 'tmp'
                        //  - normalised is 'normalised'
                        //  - -2 x pi   is 'neg2xpi'
                        //
                        //Avoid using expensive operations, and used a cached result,
                        //if both 'normalised' and 'shaping' (tmp) have not changed from last time
                        if(!first)
                        {
                            expcmp = HWY::Eq(lastExpNormalised, normalised);
                            expcmp = HWY::And(expcmp, HWY::Eq(lastExpShaping, tmp));
                            useCachedExpVal = HWY::AllTrue(_flttype, expcmp);
                        }
                        
                        if(useCachedExpVal)
                        {
                            alpha = lastExpAlpha;
                        }
                        else
                        {
                            alpha = HWY::Mul(neg2xpi, normalised);
                            alpha = HWY::Mul(alpha, tmp);
                            alpha = HWY::Exp(_flttype, alpha);
                            alpha = HWY::Sub(one, alpha);

                            lastExpAlpha = alpha;
                            lastExpShaping = tmp;
                            lastExpNormalised = normalised;
                        }
                        //z1 and z2 depend on previous values -
                        //and the next z1 and z2 depend on the X value caclulated for the 'current' sample
                        //Each lane represents 1 sample in time, thus we need to calculate the X, z1 and z2 values
                        //based on previous ones.
                        //
                        //
                        //Work on a block by block basis - where a block consists of 2 samples of 2 channels each.
                        //This prevents multiple blocks being operated on at the same time, which can decrease performance
                        //with certain operations (e.g: shifting lanes)
                        // 
                        //Each block is 4 lanes
                        //Each block will be both left and right samples for 2 samples where:
                        //  lane 0 = left sample 0
                        //  lane 1 = right sample 0
                        //  lane 2 = left sample 1
                        //  lane 3 = right sample 1
                        //
                        //First get the latest Z values into the block.
                        //This assumes that the previous call left z1L, z1R, z2L, z2R in the correct state - 
                        //such that the last calculated values have already been broadcast across the vectors
                        curZ1 = HWY::InterleaveLower(_blktype, HWY::ResizeBitCast(_blktype, z1L), HWY::ResizeBitCast(_blktype, z1R));
                        curZ2 = HWY::InterleaveLower(_blktype, HWY::ResizeBitCast(_blktype, z2L), HWY::ResizeBitCast(_blktype, z2R));

                        origL = inL;
                        origR = inR;
                        filteredLower = HWY::Zero(_blktype);
                        filteredHigher = filteredLower;
                        blockMask = HWY::Not(HWY::MaskFalse(_flttype));
                        filteredL = zero;
                        filteredR = zero;
                        for(size_t i=0; (i < numLanes) && (i < samplesRemain); i += lanesPerBlock)
                        {
                            //SlideDownBlocks<1> will fail to build if there are only 1 blocks (4 lanes) per register
                            //In that situation, there is no need to shift or cast - since a block and FltType types are the same size.
                            #if HWY_MAX_BYTES > 16
                                if(i > 0)
                                {
                                    //Next block of samples
                                    inL = HWY::SlideDownBlocks<1>(_flttype, inL);
                                    inR = HWY::SlideDownBlocks<1>(_flttype, inR);

                                    //Next block of smoothed values
                                    alpha = HWY::SlideDownBlocks<1>(_flttype, alpha);
                                    negfeedback = HWY::SlideDownBlocks<1>(_flttype, negfeedback);

                                     //Select next block for next iteration
                                    blockMask = HWY::SlideMaskUpLanes(_flttype, blockMask, lanesPerBlock);

                                    //Set up z1 and z2 from previous block values
                                    curZ1 = HWY::Per4LaneBlockShuffle<3, 2, 3, 2>(z1Higher);
                                    curZ2 = HWY::Per4LaneBlockShuffle<3, 2, 3, 2>(filteredHigher);
                                }
                            #endif

                            //Use the current bottom 4 lanes of the values to make a block of 2 samples of 2 channels (4 values, 2 values per sample)
                            //curIn = InL0 InR0 | InL1 InR1
                            curIn = HWY::InterleaveLower(_blktype, HWY::ResizeBitCast(_blktype,inL), HWY::ResizeBitCast(_blktype, inR));

                            //Alpha and feedback values are the same for both channels
                            //
                            //X1 X1 | X0 X0
                            curAlpha = HWY::Per4LaneBlockShuffle<1,1,0,0>(HWY::ResizeBitCast(_blktype, alpha));
                            curNegFeedback = HWY::Per4LaneBlockShuffle<1,1,0,0>(HWY::ResizeBitCast(_blktype, negfeedback));

                            //value 0 is from the previous iteration
                            x = HWY::Sub(curZ2, curZ1);
                            x = HWY::MulAdd(curNegFeedback, x, curIn);  //const float x = in - feedback * (z2_[idx] - z1_[idx]);
                            #ifdef ENABLE_LOGGING
                                FltBlkMaskType logmask = HWY::Dup128MaskFromMaskBits(_blktype, 1);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "z1 l", curZ1, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "z1 r", HWY::Slide1Down(_blktype, curZ1), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "z2 l", curZ2, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "z2 r", HWY::Slide1Down(_blktype, curZ2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "x l", x, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i, "x r", HWY::Slide1Down(_blktype,x), logmask);
                            #endif
                            curZ1 = HWY::MulAdd(curAlpha, HWY::Sub(x, curZ1), curZ1);    //z1_[idx] += alpha * (x - z1_[idx]);
                            curZ2 = HWY::MulAdd(curAlpha, HWY::Sub(curZ1, curZ2), curZ2);  //z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
                            filteredLower = curZ2; // const float filtered = z2_[idx];
                            z1Lower = curZ1;
                            
                            //Value 1 uses sample 1 and the previous z1 and z2 values
                            //We want to put value 1 in the upper half of the block - so duplicate the previous result into the upper half
                            curZ1 = HWY::Per4LaneBlockShuffle<1, 0, 1, 0>(curZ1);
                            curZ2 = HWY::Per4LaneBlockShuffle<1, 0, 1, 0>(curZ2);
                            x = HWY::Sub(curZ2, curZ1);
                            x = HWY::MulAdd(curNegFeedback, x, curIn);  //const float x = in - feedback * (z2_[idx] - z1_[idx]);
                            #ifdef ENABLE_LOGGING
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "z1 l", HWY::SlideDownLanes(_blktype, curZ1,2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "z1 r", HWY::SlideDownLanes(_blktype, curZ1,3), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "z2 l", HWY::SlideDownLanes(_blktype, curZ2,2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "z2 r", HWY::SlideDownLanes(_blktype, curZ2,3), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "x l",  HWY::SlideDownLanes(_blktype, x, 2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 1, "x r", HWY::SlideDownLanes(_blktype, x,3), logmask);
                            #endif
                            curZ1 = HWY::MaskedMulAddOr(z1Lower, upperBlockMask, curAlpha, HWY::Sub(x, curZ1), curZ1);    //z1_[idx] += alpha * (x - z1_[idx]);
                            curZ2 = HWY::MaskedMulAddOr(filteredLower, upperBlockMask, curAlpha, HWY::Sub(curZ1, curZ2), curZ2);  //z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
                            filteredLower = curZ2;
                            z1Lower = curZ1;

                            //Value 2 - upper block of samples 
                            //Upper half of block carries on from where the lower half of block left off above -
                            //duplicate current z1 and z2 values back to bottom half of block
                            //Also get upper half of smoothed alpha and feedback values
                            curIn = HWY::InterleaveUpper(_blktype, HWY::ResizeBitCast(_blktype, inL), HWY::ResizeBitCast(_blktype, inR)); //upper block of samples
                            curAlpha = HWY::Per4LaneBlockShuffle<3, 3, 2, 2>(HWY::ResizeBitCast(_blktype, alpha));
                            curNegFeedback = HWY::Per4LaneBlockShuffle<3, 3, 2, 2>(HWY::ResizeBitCast(_blktype, negfeedback));
                            curZ1 = HWY::Per4LaneBlockShuffle<3, 2, 3, 2>(curZ1);
                            curZ2 = HWY::Per4LaneBlockShuffle<3, 2, 3, 2>(curZ2);
                            x = HWY::Sub(curZ2, curZ1);
                            x = HWY::MulAdd(curNegFeedback, x, curIn);  //const float x = in - feedback * (z2_[idx] - z1_[idx]);
                            #ifdef ENABLE_LOGGING
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "z1 l", curZ1, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "z1 r", HWY::Slide1Down(_blktype, curZ1), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "z2 l", curZ2, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "z2 r", HWY::Slide1Down(_blktype, curZ2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "x l", x, logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 2, "x r", HWY::Slide1Down(_blktype,x), logmask);
                            #endif
                            curZ1 = HWY::MulAdd(curAlpha, HWY::Sub(x, curZ1), curZ1);    //z1_[idx] += alpha * (x - z1_[idx]);
                            curZ2 = HWY::MulAdd(curAlpha, HWY::Sub(curZ1, curZ2), curZ2);  //z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
                            filteredHigher = curZ2; //const float filtered = z2_[idx];
                            z1Higher = curZ1;

                            //Value 3 - same as value 1, but using the upper sample values
                            //Put the last result of z1 and z2 from the lower half into the upper half
                            curZ1 = HWY::Per4LaneBlockShuffle<1, 0, 1, 0>(curZ1);
                            curZ2 = HWY::Per4LaneBlockShuffle<1, 0, 1, 0>(curZ2);
                            x = HWY::Sub(curZ2, curZ1);
                            x = HWY::MulAdd(curNegFeedback, x, curIn);  //const float x = in - feedback * (z2_[idx] - z1_[idx]);
                            #ifdef ENABLE_LOGGING
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "z1 l", HWY::SlideDownLanes(_blktype, curZ1,2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "z1 r", HWY::SlideDownLanes(_blktype, curZ1,3), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "z2 l", HWY::SlideDownLanes(_blktype, curZ2,2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "z2 r", HWY::SlideDownLanes(_blktype, curZ2,3), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "x l",  HWY::SlideDownLanes(_blktype, x, 2), logmask);
                                DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_ + i + 3, "x r", HWY::SlideDownLanes(_blktype, x,3), logmask);
                            #endif
                            z1Higher = HWY::MaskedMulAddOr(z1Higher, upperBlockMask, curAlpha, HWY::Sub(x, curZ1), curZ1);    //z1_[idx] += alpha * (x - z1_[idx]);
                            filteredHigher = HWY::MaskedMulAddOr(filteredHigher, upperBlockMask, curAlpha, HWY::Sub(z1Higher, curZ2), curZ2);  //z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
                        
                            //Update the filtered value - putting the constructed block above into the full vector
                            #if HWY_MAX_BYTES  > 16
                                //We use the fact that sliding up lanes puts zeros in place in the lanes that were slid up...
                                //We can then OR the slide result with the current filterL and filterR values to 
                                //put the output block into the correct posision.
                                //Of course, this also relies on filterL and filterR initialised to zero before starting the block loop (which they are)...
                                tmp = HWY::SlideUpLanes(_flttype, HWY::ResizeBitCast(_flttype, HWY::ConcatEven(_blktype, filteredHigher, filteredLower)), i);
                                filteredL = HWY::Or(tmp, filteredL);
                                tmp = HWY::SlideUpLanes(_flttype, HWY::ResizeBitCast(_flttype, HWY::ConcatOdd(_blktype, filteredHigher, filteredLower)), i);
                                filteredR = HWY::Or(tmp, filteredR);

                                curZ1 = z1Higher;
                                curZ2 = filteredHigher;

                            #else
                                //Blocks are same size as vector - just separate left and right 
                                filteredL = HWY::ConcatEven(_blktype, filteredHigher, filteredLower);
                                filteredR = HWY::ConcatOdd(_blktype, filteredHigher, filteredLower);
                            #endif
                        }

                        //const float filtered = z2_[idx];
                        //outputs[idx].setSample(ch, i, in * dry + filtered * wet);
                        //
                        //'wet' is currentMix
                        //'dry' is 1 - currentMix
                        outL = HWY::MulAdd(filteredL, currentMix, HWY::Mul(origL, HWY::Sub(one, currentMix)));
                        outR = HWY::MulAdd(filteredR, currentMix, HWY::Mul(origR, HWY::Sub(one, currentMix)));

                        // Store output
                        if (samplesRemain >= numLanes)
                        {
                            HWY::StoreU(outL, _flttype, outputPtrL + offset);
                            if (outputPtrR != NULL)
                                HWY::StoreU(outR, _flttype, outputPtrR + offset);

                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "filtered l", filteredL);
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "filtered r", filteredR);
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "out L", outL);
                            DEBUG_LOG_LANES(logger_, totalSampleCount_, "out R", outR);

                            //Fill z1 and z2 with the last processed values
                            //We can just select from the lanes that we know hold the last processed values.
                            z2R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, filteredHigher));
                            z2L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, filteredHigher));
                            z1R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, z1Higher));
                            z1L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, z1Higher));

                            samplesRemain -= numLanes;
                            offset += numLanes;
                            totalSampleCount_ += numLanes;
                            first = false;
                        }
                        else
                        {
                            HWY::StoreN(outL,  _flttype, outputPtrL + offset, samplesRemain);
                            if (outputPtrR != NULL)
                                HWY::StoreN(outR, _flttype, outputPtrR + offset, samplesRemain);

                            switch(samplesRemain % lanesPerBlock)
                            {
                                case 0:
                                    //All lanes processed - grab the last lanes in the high position
                                    z2R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, filteredHigher));
                                    z2L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, filteredHigher));
                                    z1R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, z1Higher));
                                    z1L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, z1Higher));
                                    break;
                                case 3:
                                    //3 lanes processed - grab the first lanes in the high position
                                    z2R = HWY::BroadcastLane<1>(HWY::ResizeBitCast(_flttype, filteredHigher));
                                    z2L = HWY::BroadcastLane<0>(HWY::ResizeBitCast(_flttype, filteredHigher));
                                    z1R = HWY::BroadcastLane<1>(HWY::ResizeBitCast(_flttype, z1Higher));
                                    z1L = HWY::BroadcastLane<0>(HWY::ResizeBitCast(_flttype, z1Higher));
                                    break;
                                case 2:
                                    //2 lanes processed - grab the last lanes in the low position
                                    z2R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, filteredLower));
                                    z2L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, filteredLower));
                                    z1R = HWY::BroadcastLane<3>(HWY::ResizeBitCast(_flttype, z1Lower));
                                    z1L = HWY::BroadcastLane<2>(HWY::ResizeBitCast(_flttype, z1Lower));
                                    break;
                                case 1:
                                    //1 lane processed - grab the first lanes in the low position
                                    z2R = HWY::BroadcastLane<1>(HWY::ResizeBitCast(_flttype, filteredLower));
                                    z2L = HWY::BroadcastLane<0>(HWY::ResizeBitCast(_flttype, filteredLower));
                                    z1R = HWY::BroadcastLane<1>(HWY::ResizeBitCast(_flttype, z1Lower));
                                    z1L = HWY::BroadcastLane<0>(HWY::ResizeBitCast(_flttype, z1Lower));
                                    break;
                            }

                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "filtered l", filteredL, sampleLaneMask);
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "filtered r", filteredR, sampleLaneMask);
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "out L", outL, sampleLaneMask);
                            DEBUG_LOG_LANES_MASK(logger_, totalSampleCount_, "out R", outR, sampleLaneMask);

                            totalSampleCount_ += samplesRemain;
                            samplesRemain = 0;
                            offset += sampleLaneCount;
                        }
                    }

                    //Update state
                    smoother_.End(currentValues);
                    HWY::Store(z1L, _flttype, z1_);
                    HWY::Store(z1R, _flttype, &z1_[maxLanes]);
                    HWY::Store(z2L, _flttype, z2_);
                    HWY::Store(z2R, _flttype, &z2_[maxLanes]);
                }

            private:
                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 3> Smoother;

                Smoother smoother_;
                hwy::AlignedFreeUniquePtr<float[]> stateValues_;
                float * z1_;
                float * z2_;
                float * sampleRateRcp_;

                bool configChanged_ = true;
                size_t totalSampleCount_ = 0;
                Debug::Logger logger_;
            };

            //Create CPU specific instance
            HWY_API IPrimitiveNodeSIMDImplementation *  __CreateInstanceForCPU(const std::atomic<float> * targetCutoffHz,
                                                                                const std::atomic<float> * targetResonance,
                                                                                const std::atomic<float> * targetMix)
            {
                return new FilterNodeSIMDImplementation(targetCutoffHz, targetResonance, targetMix);
            }
        }

        //========================================================================
        //Highway bootstrap

        #if HWY_ONCE || HWY_IDE

            IPrimitiveNodeSIMDImplementation *  __CreateInstance(int target, 
                                                                 const std::atomic<float> * targetCutoffHz,
                                                                const std::atomic<float> * targetResonance,
                                                                const std::atomic<float> * targetMix,
                                                                hwy::RunHighwayErrorCode * retErrorCode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                IPrimitiveNodeSIMDImplementation * retiface = NULL;

                hwy::RunHighwayErrorCode res =  hwy::RunHighwayFunction(target, &retiface, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                        targetCutoffHz, targetResonance, targetMix);

                *retErrorCode = res;
                return retiface;
            }

        #endif
    }
}

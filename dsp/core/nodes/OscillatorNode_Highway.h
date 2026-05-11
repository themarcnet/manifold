//Do not guard against multiple inclusions - Highway works by including this file multiple times, once for each SIMD implementation

#undef HWY_TARGET_INCLUDE
#define HWY_TARGET_INCLUDE "dsp/core/nodes/OscillatorNode_Highway.h"

#include "OscillatorNode_Common.h"

#include "manifold/highway/HighwayWrapper.h"
#include "manifold/highway/HighwayMaths.h"
#include "manifold/highway/HighwaySmoother.h"
#include "manifold/highway/HighwayUtils.h"



#include <hwy/contrib/random/random-inl.h>

#include <algorithm>
#include <cmath>
#include <memory>


namespace dsp_primitives
{
    namespace OscillatorNode_Highway
    {
       
        namespace HWY_NAMESPACE
        {
            class OscillatorNodeSIMDImplementation : public dsp_primitives::OscillatorNode_Highway::IOscillatorNodeSIMDAInterface
            {
            private:
                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 5> Smoother;
                typedef hwy::HWY_NAMESPACE::HighwayValueSmoother<float, 8> VoiceSmoother;
                
                using FltType = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>>;
                using IntType = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>>;
                using FltMaskType = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>>;
                using IntMaskType = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<int32_t>>;
                using VoiceFltType = VoiceSmoother::ValueType;

                struct AdditiveControls
                {
                    int partialCount = 8;
                    float tilt = 0.0f;
                    float drift = 0.0f;
                    int waveform = 0;
                };

            public:
                OscillatorNodeSIMDImplementation(float samplerate,
                                                 const std::atomic<float>* targetFrequency,
                                                 const std::atomic<float>* targetAmplitude,
                                                 const std::atomic<int>* targetWaveform,
                                                 const std::atomic<float>* targetPulseWidth,
                                                 const std::atomic<float>* targetDrive,
                                                 const std::atomic<int>* targetDriveShape,
                                                 const std::atomic<float>* targetDriveBias,
                                                 const std::atomic<float>* targetDriveMix,
                                                 const std::atomic<int>* targetRenderMode,
                                                 const std::atomic<int>* targetAdditivePartials,
                                                 const std::atomic<float>* targetAdditiveTilt,
                                                 const std::atomic<float>* targetAdditiveDrift,
                                                 const std::shared_ptr<const WaveAddTableSet> * targetWaveAddTableSet,
                                                 const std::atomic<int>* targetUnisonVoices,
                                                 const std::atomic<float>* targetDetuneCents,
                                                 const std::atomic<float>* targetStereoSpread,
                                                 const std::atomic<bool> * syncEnabled)        : renderModeToMixConverter_(targetRenderMode),
                                                                                                 unisonVoicesToUnisonGainConverter_{targetUnisonVoices, //voice 0 
                                                                                                                                   targetUnisonVoices,  //voice 1
                                                                                                                                   targetUnisonVoices,  //voice 2
                                                                                                                                   targetUnisonVoices,  //voice 3
                                                                                                                                   targetUnisonVoices,  //voice 4
                                                                                                                                   targetUnisonVoices,  //voice 5
                                                                                                                                   targetUnisonVoices,  //voice 6
                                                                                                                                   targetUnisonVoices}, //voice 7
                                                                                                 syncEnabled_(syncEnabled),
                                                                                                 targetPulseWidth_(targetPulseWidth),
                                                                                                 waveform_(targetWaveform),
                                                                                                 waveAddTableSet_(targetWaveAddTableSet),
                                                                                                 additivePartials_(targetAdditivePartials),
                                                                                                 additiveTilt_(targetAdditiveTilt),
                                                                                                 additiveDrift_(targetAdditiveDrift),
                                                                                                 drive_(targetDrive),
                                                                                                 driveshape_(targetDriveShape),
                                                                                                 drivebias_(targetDriveBias),
                                                                                                 drivemix_(targetDriveMix),
                                                                                                 sampleRate_(samplerate)
                {
                    //Initialise the value smoother
                    //Note the use of 'renderModeToMixConverter_', which will return a 'mix' of 1.0f or 0.0f, depending on the state of the target render mode 
                    smoother_.initialise(targetFrequency, targetAmplitude, &renderModeToMixConverter_, targetDetuneCents, targetStereoSpread);

                    //Initialise the unison voice smoother
                    unisonVoiceSmoother_.initialise(&unisonVoicesToUnisonGainConverter_[0],
                                                    &unisonVoicesToUnisonGainConverter_[1],
                                                    &unisonVoicesToUnisonGainConverter_[2],
                                                    &unisonVoicesToUnisonGainConverter_[3],
                                                    &unisonVoicesToUnisonGainConverter_[4],
                                                    &unisonVoicesToUnisonGainConverter_[5],
                                                    &unisonVoicesToUnisonGainConverter_[6],
                                                    &unisonVoicesToUnisonGainConverter_[7]);
                }

                const char* targetName() const override
                {
                    return hwy::TargetName(HWY_TARGET);
                }

                void configChanged() override
                {
                    configChanged_ = true;
                }

                virtual void refreshWaveAddTableSet() override
                {
                    if((waveAddTableSet_ != NULL) && (waveAddTableSet_->get() != NULL))
                    {
                        const size_t bandcount = (*waveAddTableSet_)->bands.size();
                        const size_t tablesize = (*waveAddTableSet_)->bands[0].size();
                        if(!addWaveTableSet_ || (numBands_ != bandcount) || (bandTableSize_ != tablesize))
                        {
                            addWaveTableSet_ = hwy::AllocateAligned<float>(bandcount * tablesize );
                        }

                        for(size_t x=0; x < bandcount; ++x)
                        {
                            float * destPtr = addWaveTableSet_.get() + (tablesize * x);
                            const float * srcPtr = (*waveAddTableSet_)->bands[x].data();
                            memcpy(destPtr, srcPtr, sizeof(float) * tablesize);
                        }

                        numBands_ = bandcount;
                        bandTableSize_ = tablesize;
                    }
                }

                virtual void resetPhase() override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::DFromV<VoiceSmoother::ValueType> _voicesflttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const size_t numLanes = HWY::Lanes(_flttype);
                    const size_t numVoices = HWY::MaxLanes(_voicesflttype);
                    
                    if(phaseValues_.get() != NULL)
                        memset(phaseValues_.get(), 0, sizeof(float) * numVoices);


                    /*unisonVoiceGains_[0] = 1.0f;
                    for (int i = 1; i < 8; ++i) {
                        unisonVoiceGains_[toIndex(i)] = 0.0f;
                    }
                    */
                    const float voice0 = 1.0f;
                    unisonVoiceSmoother_.ZeroCurrentValues();
                    unisonVoiceSmoother_.SetCurrentValues(&voice0, 0, 1);

                    lastRequestedUnison_ = 1;
                }

                void reset() override
                {
                    resetPhase();
                }

                HWY_ATTR void prepare(float sampleRate) override
                {
                    const double freqTimeSeconds = 0.02;
                    const double ampTimeSeconds = 0.01;
                    const double renderTimeSeconds = 0.008;
                    const double detuneTimeSeconds = 0.012;
                    const double spreadTimeSeconds = 0.012;
                    const double unisonVoiceTimeSeconds = 0.008;

                    //Each value has it's own smooth rate
                    sampleRate_ = sampleRate;
                    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
                    float freqSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (freqTimeSeconds * sr)));
                    float ampSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (ampTimeSeconds * sr)));
                    float renderSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (renderTimeSeconds * sr)));
                    float detuneSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (detuneTimeSeconds * sr)));
                    float spreadSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (spreadTimeSeconds * sr)));

                    smoother_.SetSmooth(freqSmooth, ampSmooth, renderSmooth, detuneSmooth, spreadSmooth);
                    smoother_.PrepareCurrentValues();

                    float unisonSmooth = static_cast<float>(1.0 - std::exp(-1.0 / (unisonVoiceTimeSeconds * sr)));
                    unisonVoiceSmoother_.SetSmooth(unisonSmooth); //sets same coeff for all voices
                    unisonVoiceSmoother_.PrepareCurrentValues();

                    resetPhase();
                }

                HWY_ATTR void run(const std::vector<AudioBufferView>& inputs,
                                  std::vector<WritableAudioBufferView>& outputs,
                                  int numsamples) override
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                    bool calcVoiceOffsets = false;
                    const int requestedUnison = unisonVoicesToUnisonGainConverter_[0].GetSourceValue();
                    if(!voiceOffsets_ ||  (requestedUnison > numAllocatedVoiceOffsets_) || (numLanes != laneCount_))
                    {
                        voiceOffsets_ = hwy::AllocateAligned<float>(numLanes * requestedUnison);
                        numAllocatedVoiceOffsets_ = requestedUnison;
                        calcVoiceOffsets = true;
                    }

                    if(configChanged_ || (numLanes != laneCount_))
                    {
                        //Re-read target values
                        configure();
                    }

                    const bool syncOn = syncEnabled_->load(std::memory_order_acquire);
                    const bool hasSyncInput = syncOn && !inputs.empty() && inputs[0].numChannels > 0;
                    int layoutUnison = lastRequestedUnison_;
                    if(requestedUnison > lastRequestedUnison_)
                    {
                        //Copy the first phase value to new voices
                        float * voicePhasePtr = phaseValues_.get();
                        for(int v=lastRequestedUnison_; v < requestedUnison; ++v)
                        {
                            float * destvoicePhasePtr = &voicePhasePtr[(numLanes * v)];
                            FltType p = HWY::Load(_flttype, voicePhasePtr);
                            HWY::Store(p, _flttype, destvoicePhasePtr);
                        }

                        layoutUnison = requestedUnison;
                        calcVoiceOffsets = true;
                    }
                    else
                    {
                        layoutUnison = lastRequestedUnison_;
                    }

                    
                    const int voiceLimit = juce::jlimit(1, 8, layoutUnison);
                    const int placementCount = juce::jmax(1, layoutUnison);
                    const int wf = waveform_->load(std::memory_order_acquire);
                    const int driveshape = driveshape_->load(std::memory_order_acquire);
                    
                    const FltType half = HWY::Set(_flttype, 0.5f);
                    const FltType one = HWY::Add(half, half);
                    const FltType two = HWY::Add(one,one);
                    const FltType oneOverHundred = HWY::Set(_flttype, 0.01f);
                    const FltType oneOverTwelve = HWY::Set(_flttype, 1.0f / 12.0f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType twoPi = HWY::Set(_flttype, 2 * 3.141592653589793238f);
                    const FltType oneOverTwoPi = HWY::Set(_flttype, 1.0f / (2 * 3.141592653589793238f));
                    const FltType placementCountFlt = HWY::Set(_flttype, static_cast<float>(placementCount));
                    const FltType twoPiOverSampleRate = HWY::Div(twoPi, HWY::Set(_flttype, sampleRate_));
                    const FltType voiceThreshold = HWY::Set(_flttype, 1.0e-4f);
                    const FltType mixLowerThreshold = HWY::Set(_flttype, 0.0001f);
                    const FltType mixUpperThreshold = HWY::Set(_flttype, 0.9999f);
                    const FltType pulseWidthPhase = HWY::Load(_flttype, pulseWidthPhase_.get());
                    const FltType pulseWidthNorm = HWY::Load(_flttype, pulseWidthNorm_.get());
                    const FltType sampleRate = HWY::Set(_flttype, sampleRate_);
                    const FltType additiveTilt = HWY::Load(_flttype, additiveTiltValues_.get());
                    const FltType additiveDrift = HWY::Load(_flttype, additiveDriftValues_.get());
                    const IntType additivePartials = HWY::Load(_inttype, additivePartialValues_.get());
                    const FltType drive = HWY::Load(_flttype, driveValues_.get());
                    const FltType drivebias = HWY::Load(_flttype, driveBiasValues_.get());
                    const FltType drivemix = HWY::Load(_flttype, driveMixValues_.get());
                    
                    FltType leftSample, rightSample, currentFreq, currentAmplitude, currentRenderMix, currentDetune, currentSpread, voiceGain, contribVoices;
                    FltType waveformSamples, voicePhaseNorm;
                    FltType unisonVocieGains[c_max_voices];
                    FltType voiceOffsets[c_max_voices];
                    FltType voicePhases[c_max_voices];
                    FltType phaseIncrement, tmp, voiceFrequency, voicePhaseInc,  panL, panR;
                    FltType prevSyncSample = HWY::Load(_flttype, previousSyncSample_.get());
                    FltType laneNumbers = HWY::Load(_flttype, laneNumbers_.get());
                    FltMaskType cmp, sampleLaneMask, msk, voiceLaneMask, higherVoicesStillActive;

                    const bool isStereo = outputs[0].numChannels > 1;
                    float* outputPtrL = outputs[0].channelData[0];
                    float* outputPtrR = isStereo ? outputs[0].channelData[1] : nullptr;

                    const float * inputPtrL = hasSyncInput ?  inputs[0].channelData[0] : NULL;
                    const float * inputPtrR = (hasSyncInput &&  (inputs[0].numChannels > 1)) ? inputs[0].channelData[1] : NULL;


                    if(calcVoiceOffsets)
                    {
                        //Pre-Caclulate voice offset values
                        for(int v = 0; v < layoutUnison; ++v)
                        {
                            float * voiceOffsetPtr = voiceOffsets_.get() + (v * numLanes);
                            //const float placementCenter = (static_cast<float>(placementCount) - 1.0f) * 0.5f;   
                            tmp = HWY::Sub(laneNumbers, one); //v
                            //tmp = HWY::Sub(tmp, HWY::Mul( HWY::Sub(placementCountFlt, one), half)); //v - placementCenter
                            HWY::Store(tmp, _flttype, voiceOffsetPtr);
                            voiceOffsets[v] = tmp;
                            voicePhases[v] = HWY::Load(_flttype, phaseValues_.get() + (v * numLanes));
                        }
                    }
                    else
                    {
                        for(int v = 0; v < layoutUnison; ++v)
                        {
                            const float * voiceOffsetPtr = voiceOffsets_.get() + (v * numLanes);
                            voiceOffsets[v] = HWY::Load(_flttype, voiceOffsetPtr);
                            voicePhases[v] = HWY::Load(_flttype, phaseValues_.get() + (v * numLanes));
                        }
                    }

                    Smoother::ValueType targetStateVals, currentStateVals, smoothVals;
                    smoother_.Start(targetStateVals, currentStateVals, smoothVals);

                    
                    VoiceSmoother::ValueType targetVoiceStateVals, currentVoiceStateVals, voiceSmoothVals;
                    unisonVoiceSmoother_.Start(targetVoiceStateVals, currentVoiceStateVals, voiceSmoothVals);

                    size_t offset = 0;
                    size_t samplesRemain = numsamples;
                    size_t sampleLaneCount;
                    bool smootherFrozen = false;
                    while(samplesRemain > 0)
                    {
                        sampleLaneCount = (samplesRemain > numLanes) ? numLanes : samplesRemain;

                        //Run the smoother
                        smootherFrozen = smoother_.IsFrozen();
                        smoother_.Run(sampleLaneCount, smoothVals, targetStateVals, currentStateVals, 
                                      currentFreq, currentAmplitude, currentRenderMix, currentDetune, currentSpread);

                        //phaseIncrement = kTwoPi * static_cast<double>(currentFrequency_) / sampleRate_;
                        phaseIncrement = HWY::Mul(twoPiOverSampleRate, currentFreq);

                        if(hasSyncInput)
                        {
                            //Read input A
                            if(samplesRemain >= numLanes)
                            {
                                sampleLaneMask = HWY::Not( HWY::MaskFalse(_flttype));
                                leftSample = HWY::LoadU(_flttype, inputPtrL + offset);
                                rightSample = (inputPtrR == NULL) ? zero : HWY::LoadU(_flttype, inputPtrR + offset);
                            }
                            else
                            {
                                sampleLaneMask = HWY::FirstN(_flttype, sampleLaneCount);
                                leftSample = HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtrL + offset);
                                rightSample = (inputPtrR == NULL) ? zero : HWY::MaskedLoad(sampleLaneMask, _flttype, inputPtrR + offset);
                            }

                            //Add left and right - we're only using the inputs for syncing, so 
                            //any sound on left OR right will trigger
                            leftSample = HWY::Add(leftSample, rightSample);

                            //if (prevSyncSample_ <= 0.0f && syncSample > 0.0f) {
                            //    phase_ = 0.0;
                            //    for (auto& p : unisonPhases_) p = 0.0;
                            // }
                            cmp = HWY::Le(prevSyncSample, zero);
                            cmp = HWY::MaskedGt(cmp, leftSample, zero);
                            if(!HWY::AllFalse(_flttype, cmp))
                            {
                                //TODO: Reset phase to zero when cmp == true, 
                                //and restart phaseIncerement counter for future samples
                            }

                            prevSyncSample = leftSample;
                        }
                        else
                        {
                            //Caclulate total phase increment for each lane
                            tmp = zero;
                            msk = HWY::Not(HWY::MaskFalse(_flttype));
                            for(size_t x=0; x < numLanes; ++x)
                            {
                                tmp = HWY::MaskedAddOr(tmp, msk, tmp, HWY::BroadcastLane<0>( phaseIncrement));
                                msk = HWY::SlideMask1Up(_flttype, msk);
                                phaseIncrement = HWY::Slide1Down(_flttype, phaseIncrement);
                            }

                            phaseIncrement = tmp;
                        }
                        
                        //renderMix = juce::jlimit(0.0f, 1.0f, currentRenderMix_);
                        currentRenderMix = HWY::Limit(zero, one, currentRenderMix);
                   
                        leftSample = zero;
                        rightSample = zero;
                        
                        //Run the voice gain smoother
                        //Puts each voice gain into 'unisonVocieGains' - N samples per voice, where N is the number of lanes
                        unisonVoiceSmoother_.RunArray(sampleLaneCount, voiceSmoothVals, targetVoiceStateVals, currentVoiceStateVals, unisonVocieGains);

                        //For each voice
                        higherVoicesStillActive = HWY::MaskFalse(_flttype);
                        contribVoices = zero;
                        for(size_t v = 0; v < voiceLimit; ++v)
                        {
                            voiceGain = unisonVocieGains[v];

                            //if (v >= targetUnison && voiceGain > 1.0e-4f) {
                            //    higherVoicesStillActive = true;
                            //}
                            if(v >= requestedUnison)
                            {
                                cmp = HWY::Gt(voiceGain, voiceThreshold);
                                higherVoicesStillActive = HWY::Or(higherVoicesStillActive, cmp);
                            }


                            /*if (voiceGain <= 1.0e-4f) {
                                continue;
                            }*/
                            //We're dealing with N samples (where N is the lane count) at a time, so
                            //mask out lanes we don't want to process
                            voiceLaneMask = HWY::Ge(voiceGain, voiceThreshold);
                            if(HWY::AllFalse(_flttype, voiceLaneMask))
                            {
                                continue;
                            }

                            //++contributingVoices;
                            contribVoices = HWY::MaskedAddOr(contribVoices, voiceLaneMask, one, contribVoices);

                            /*const float voiceOffset = static_cast<float>(v) - placementCenter;
                            const float detuneAmount = voiceOffset * currentDetuneCents_ / 100.0f;
                            const double freqMult = std::pow(2.0, detuneAmount / 12.0);
                            const double voicePhaseInc = phaseIncrement * freqMult;
                            const float voiceFrequency = currentFrequency_ * static_cast<float>(freqMult); */
                            tmp = HWY::Mul(voiceOffsets[v], currentDetune);
                            tmp = HWY::Mul(tmp, oneOverHundred);
                            tmp = HWY::Pow(_flttype, two, HWY::Mul(tmp, oneOverTwelve));
                            voicePhaseInc = HWY::Mul(tmp, phaseIncrement);
                            voiceFrequency = HWY::Mul(currentFreq, tmp);

                            //ouble& voicePhase = (v == 0) ? phase_ : unisonPhases_[voiceSlot];
                            //const float phaseNorm = static_cast<float>(voicePhase / kTwoPi);
                            voicePhaseNorm = HWY::Mul(voicePhases[v], oneOverTwoPi);

                            
                            //if (renderMix <= 0.0001f) {
                            //  waveformSample = standardWaveformSample(wf, voicePhase, pulseWidthPhase);
                            //}
                            waveformSamples = zero;
                            cmp = HWY::Le(currentRenderMix, mixLowerThreshold);
                            if(!HWY::AllFalse(_flttype, cmp))
                            {
                                standardWaveformSample(wf, voicePhases[v], voicePhaseNorm,  pulseWidthPhase, cmp, waveformSamples);
                            }

                            //else if (renderMix >= 0.9999f) {
                            //  waveformSample = renderAdditiveSample();
                            //}
                            msk = HWY::Not(cmp);
                            cmp = HWY::MaskedGe(HWY::Not(cmp), currentRenderMix, mixUpperThreshold);
                            if(!HWY::AllFalse(_flttype, cmp))
                            {
                                renderAdditiveSample(cmp, voiceFrequency, voicePhaseNorm, pulseWidthNorm, wf,
                                                    additivePartials, additiveTilt, additiveDrift,
                                                    waveformSamples);
                            }

                            //else {}
                            cmp = HWY::AndNot(cmp,msk);
                            if(!HWY::AllFalse(_flttype, cmp))
                            {
                                //const float standardSample = standardWaveformSample(wf, voicePhase, pulseWidthPhase);
                                //const float additiveSample = renderAdditiveSample();
                                //waveformSample = standardSample + (additiveSample - standardSample) * renderMix;
                                standardWaveformSample(wf, voicePhases[v], voicePhaseNorm,  pulseWidthPhase, cmp, waveformSamples);
                                renderAdditiveSample(cmp, voiceFrequency, voicePhaseNorm, pulseWidthNorm, wf,
                                                    additivePartials, additiveTilt, additiveDrift,
                                                    tmp); //addiditveSample in 'tmp'

                                waveformSamples = HWY::MaskedMulAddOr(waveformSamples, cmp, HWY::Sub(tmp, waveformSamples), currentRenderMix, waveformSamples);
                            }


                            //waveformSample = applyDriveShape(waveformSample, drive, driveShape, driveBias, driveMix);
                            applyDriveShape(waveformSamples, drive, driveshape, drivebias, drivemix, waveformSamples);

                            //if (!std::isfinite(waveformSample)) {
                            //waveformSample = 0.0f;
                            //}
                            waveformSamples = HWY::IfThenElse(HWY::IsFinite(waveformSamples), zero, waveformSamples);

                            //waveformSample *= voiceGain;
                            waveformSamples = HWY::Mul(waveformSamples, voiceGain);

                            //const float pan = juce::jlimit(0.0f,
                           //                1.0f,
                           //                0.5f + voiceOffset * currentSpread_ / static_cast<float>(juce::jmax(1, placementCount)));
                            panL = HWY::Mul(voiceOffsets[v], currentSpread);
                            tmp = HWY::IfThenElse(HWY::Lt(placementCountFlt, one), one, placementCountFlt);
                            panL = HWY::Div(panL, tmp);
                            panL = HWY::Add(panL, half);
                            panL = HWY::Limit(zero, one, panL);

                            //const float leftPan = std::sqrt(1.0f - pan);
                            //const float rightPan = std::sqrt(pan);
                            panR = HWY::Sqrt(panL);
                            panL = HWY::Sqrt(HWY::Sub(one, panL));

                            //leftSample += waveformSample * leftPan;
                            //rightSample += waveformSample * rightPan;
                            leftSample = HWY::MaskedMulAddOr(leftSample, voiceLaneMask, waveformSamples, panL, leftSample);
                            rightSample = HWY::MaskedMulAddOr(rightSample, voiceLaneMask, waveformSamples, panR, rightSample);

                            /*voicePhase += voicePhaseInc;
                            while (voicePhase >= kTwoPi) {
                                voicePhase -= kTwoPi;
                            }
                            while (voicePhase < 0.0) {
                                voicePhase += kTwoPi;
                            }*/
                            tmp = HWY::Add(voicePhases[v], voicePhaseInc);
                            cmp = HWY::MaskedGe(voiceLaneMask, tmp, twoPi);
                            while(!HWY::AllFalse(_flttype, cmp))
                            {
                                tmp = HWY::MaskedSubOr(tmp, cmp, tmp, twoPi);
                                cmp = HWY::MaskedGe(voiceLaneMask, tmp, twoPi);
                            }

                            cmp = HWY::MaskedLt(voiceLaneMask, tmp, zero);
                            while(!HWY::AllFalse(_flttype, cmp))
                            {
                                tmp = HWY::MaskedAddOr(tmp, cmp, tmp, twoPi);
                                cmp = HWY::MaskedLt(voiceLaneMask, tmp, zero);
                            }

                            voicePhases[v] = tmp;
                        }

                        //After all that, better write to the output....
                        

                        //const float normGain = (contributingVoices > 0) ? (1.0f / std::sqrt(static_cast<float>(contributingVoices))) : 0.0f;
                        tmp = zero;
                        cmp = HWY::Gt(contribVoices, zero);
                        if(!HWY::AllFalse(_flttype, cmp))
                        {
                            tmp = HWY::Sqrt(contribVoices);
                            tmp = HWY::ApproximateReciprocal(tmp);
                            tmp = HWY::IfThenElse(cmp, tmp, zero);
                        }
                        
                        //leftSample *= normGain * currentAmplitude_;
                        //rightSample *= normGain * currentAmplitude_;
                        leftSample = HWY::Mul(leftSample, HWY::Mul(tmp, currentAmplitude));
                        rightSample = HWY::Mul(rightSample, HWY::Mul(tmp, currentAmplitude));

                        //if (!std::isfinite(leftSample)) {
                        //    leftSample = 0.0f;
                        // }
                        // if (!std::isfinite(rightSample)) {
                        //     rightSample = 0.0f;
                        // }
                        leftSample = HWY::IfThenElse(HWY::IsFinite(leftSample), leftSample, zero);
                        rightSample = HWY::IfThenElse(HWY::IsFinite(rightSample), rightSample, zero);

                        
                        //if (out.numChannels >= 2) {
                        //  out.setSample(0, i, leftSample);
                        //  out.setSample(1, i, rightSample);
                        //} else {
                        //  out.setSample(0, i, (leftSample + rightSample) * 0.5f);
                        //}
                        if(isStereo)
                        {
                            if(sampleLaneCount == numLanes)
                            {
                                HWY::StoreU(leftSample, _flttype, outputPtrL + offset);
                                HWY::StoreU(rightSample, _flttype, outputPtrR + offset);
                            }
                            else
                            {
                                HWY::StoreN(leftSample, _flttype, outputPtrL + offset, sampleLaneCount);
                                HWY::StoreN(rightSample, _flttype, outputPtrR + offset, sampleLaneCount);
                            }
                        }
                        else
                        {
                            leftSample = HWY::Add(leftSample, rightSample);
                            leftSample = HWY::Mul(leftSample, half);
                            
                            if(sampleLaneCount == numLanes)
                            {
                                HWY::StoreU(leftSample, _flttype, outputPtrL + offset);
                            }
                            else
                            {
                                HWY::StoreN(leftSample, _flttype, outputPtrL + offset, sampleLaneCount);
                            }
                        }

                        samplesRemain -= sampleLaneCount;
                        offset += sampleLaneCount;
                    }
                }

            private:
                static constexpr int c_wave_add_table_size = 2048;
                static constexpr int c_wave_add_band_count = 20;

                HWY_ATTR void foldToUnit(FltType & x)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    /*
                        x = juce::jlimit(-32.0f, 32.0f, x);
                        while (x > 1.0f || x < -1.0f) {
                            if (x > 1.0f) {
                                x = 2.0f - x;
                            } else {
                                x = -2.0f - x;
                            }
                        }
                    */

                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType two = HWY::Add(one,one);
                    const FltType negtwo = HWY::Neg(two);
                    const FltType negone = HWY::Neg(one);
                    const FltType maxX = HWY::Set(_flttype, 32.0f);
                    const FltType minX = HWY::Neg(maxX);
                    
                    // x = juce::jlimit(-32.0f, 32.0f, x);
                    x = HWY::Limit(minX, maxX, x);
                    
                    FltMaskType cmpnegone = HWY::Lt(x, negone);
                    FltMaskType cmpone = HWY::Gt(x, one);
                    while(!HWY::AllFalse(_flttype, HWY::Or(cmpone, cmpnegone)))
                    {
                        //if (x > 1.0f) {  x = 2.0f - x; }
                        x = HWY::MaskedSubOr(x, HWY::And(cmpnegone, cmpone), two, x);
                        x = HWY::MaskedSubOr(x,  HWY::AndNot(cmpone, cmpnegone), negtwo, x);

                        cmpnegone = HWY::Lt(x, negone);
                        cmpone = HWY::Gt(x, one);
                    }
                }
                
                HWY_ATTR void applyDriveTransfer(const FltType & sample, const FltType & drive, const int shape, FltType & retWavSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const FltType one = HWY::Set(_flttype, 1);
                    const FltType negone = HWY::Neg(one);
                    const FltType gainMul_1 = HWY::Set(_flttype, 1.35f);
                    const FltType gainMul_2 = HWY::Set(_flttype, 1.2f);
                    const FltType gainMul_3 = HWY::Set(_flttype, 1.1f);
                    const FltType gainMul_0 = HWY::Set(_flttype, 0.85f);
                    const FltType minVal = HWY::Set(_flttype, 1.0e-6f);

                    FltMaskType mask;
                    FltType temp, gain;

                    //This is already done by the caller
                     //const float drv = juce::jlimit(0.0f, 20.0f, drive);
                    //FltType drv = HWY::IfThenElse(HWY::Gt(drive, maxDrive), maxDrive, drive);
                    //drv = HWY::IfThenElse(HWY::Lt(drv, zero), zero, drv);
                    //if (drv <= 0.0001f) {
                    //    return juce::jlimit(-1.0f, 1.0f, sample);
                    //}

                    switch((shape > 3) ? 3 : shape)
                    {
                        case 1:
                            //const float gain = 1.0f + drv * 1.35f;
                            //const float normaliser = std::atan(gain);
                            //if (normaliser <= 1.0e-6f) {
                            //    return juce::jlimit(-1.0f, 1.0f, sample);
                            //}
                            //return std::atan(sample * gain) / normaliser;
                            {
                                gain = HWY::MulAdd(drive, gainMul_1, one);
                                FltType normaliser = HWY::Atan(_flttype, gain);

                                mask = HWY::Le(normaliser, minVal);
                                retWavSample = HWY::MaskedLimit(retWavSample, mask, negone, one, sample);
                                if(HWY::AllTrue(_flttype, mask))
                                {
                                    return;
                                }

                                //Mask is if value <= min, so put the result on the else of the if/else below.
                                temp = HWY::Atan(_flttype, HWY::Div(HWY::Mul(sample, gain), normaliser));
                                retWavSample = HWY::IfThenElse(mask, retWavSample, temp);
                            }
                            break;

                        case 2:
                            //const float gain = 1.0f + drv * 1.2f;
                            // return juce::jlimit(-1.0f, 1.0f, sample * gain);
                            {
                                gain = HWY::MulAdd(drive, gainMul_2, one);
                                gain = HWY::Mul(sample, gain);
                                retWavSample = HWY::Limit(negone, one, gain);
                            }
                            break;

                        case 3:
                            //const float gain = 1.0f + drv * 1.1f;
                            //return foldToUnit(sample * gain);
                            gain = HWY::MulAdd(drive, gainMul_3, one);
                            retWavSample = HWY::Mul(sample, gain);
                            foldToUnit(retWavSample);
                            break;

                        case 0:
                        default: 
                            //const float gain = 1.0f + drv * 0.85f;
                            //const float normaliser = std::tanh(gain);
                            // if (normaliser <= 1.0e-6f) {
                           //     return juce::jlimit(-1.0f, 1.0f, sample);
                           // }
                           // return std::tanh(sample * gain) / normaliser;
                            {
                                gain = HWY::MulAdd(drive, gainMul_1, one);
                                FltType normaliser = HWY::Tanh(_flttype, gain);

                                mask = HWY::Le(normaliser, minVal);
                                retWavSample = HWY::MaskedLimit(retWavSample, mask, negone, one, sample);
                                if(HWY::AllTrue(_flttype, mask))
                                {
                                    return;
                                }

                                //Mask is if value <= min, so put the result on the else of the if/else below.
                                temp = HWY::Tanh(_flttype, HWY::Div(HWY::Mul(sample, gain), normaliser));
                                retWavSample = HWY::IfThenElse(mask, retWavSample, temp);
                            }
                            break;
                    }
                }

                HWY_ATTR void applyDriveShape(const FltType & sample, const FltType & drive, const int shape, const FltType & bias, const FltType & mix,
                                                         FltType & retWavSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    // const float wetMix = juce::jlimit(0.0f, 1.0f, mix);
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType negone = HWY::Neg(one);
                    const FltType minValue = HWY::Set(_flttype, 0.0001f);
                    const FltType zero = HWY::Sub(one, one);
                    
                    const FltType wetMix = HWY::Limit(zero, one, mix);

                    //if (drv <= 0.0001f || wetMix <= 0.0001f) {
                    //    return juce::jlimit(-1.0f, 1.0f, sample);
                    //}
                    FltMaskType mask = HWY::Lt(wetMix, minValue);
                    mask = HWY::Or(mask, HWY::Lt(wetMix, minValue));

                    retWavSample = HWY::MaskedLimit(retWavSample, mask, negone, one, sample);
                    if(HWY::AllTrue(_flttype, mask))
                        return;
                    
                    const FltType maxDrive = HWY::Set(_flttype, 20.0f);
                    const FltType biasOffsetCoeff = HWY::Set(_flttype, 0.75f);
                    const FltType minNorm = HWY::Set(_flttype, 1.0e-6f);

                    //const float drv = juce::jlimit(0.0f, 20.0f, drive);
                    const FltType drv = HWY::Limit(zero, maxDrive, drive);
             
                    //const float biasOffset = juce::jlimit(-1.0f, 1.0f, bias) * 0.75f;
                    FltType biasOffset = HWY::Limit(negone, one, bias);
                    biasOffset = HWY::Mul(biasOffset, biasOffsetCoeff);

                    //const float center = applyDriveTransfer(biasOffset, drv, shape);
                    FltType center = zero;
                    applyDriveTransfer(biasOffset, drive, shape, center);

                    //const float pos = std::abs(applyDriveTransfer(1.0f + biasOffset, drv, shape) - center);
                    FltType pos = HWY::Add(one, biasOffset);
                    applyDriveTransfer(pos, drive, shape, pos);
                    pos = HWY::Abs(HWY::Sub(pos, center));

                    //const float neg = std::abs(applyDriveTransfer(-1.0f + biasOffset, drv, shape) - center);
                    FltType neg = HWY::Sub(biasOffset, one);
                    applyDriveTransfer(neg, drive, shape, neg);
                    neg = HWY::Abs(HWY::Sub(neg, center));

                    //const float normaliser = std::max(1.0e-6f, std::max(pos, neg));
                    FltType normaliser = HWY::IfThenElse(HWY::Gt(pos, neg), pos, neg);
                    normaliser = HWY::IfThenElse(HWY::Gt(normaliser, minNorm), normaliser, minNorm);

                    //const float shaped = (applyDriveTransfer(sample + biasOffset, drv, shape) - center) / normaliser;
                    FltType shaped = HWY::Add(sample, biasOffset);
                    applyDriveTransfer(shaped, drive, shape, shaped);
                    shaped = HWY::Div(HWY::Sub(shaped, center), normaliser);

                    // const float wet = juce::jlimit(-1.0f, 1.0f, shaped);
                    const FltType wet = HWY::Limit(negone, one, shaped);
              
                    //return juce::jlimit(-1.0f, 1.0f, sample + (wet - sample) * wetMix);
                    retWavSample = HWY::MaskedMulAddOr( HWY::Not(retWavSample), mask, HWY::Sub(wet, sample), wetMix, sample);
                    retWavSample = HWY::Limit(negone, one, retWavSample);
                }



                HWY_API void standardWaveformSample(int waveform, const FltType & voicePhase, const FltType & voicePhaseNorm,
                                                    const FltType & pulseWidthPhase, 
                                                    const FltMaskType & mask, FltType & outWaveformSamples)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    constexpr size_t numLanes = _flttype.MaxLanes();
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    FltType tmp, tmp2;

                    switch(waveform)
                    {
                        case 1:
                            {
                                //const float saw = 2.0f * phaseNorm - 1.0f;
                                tmp = HWY::MulAdd(HWY::Add(one, one), voicePhaseNorm, HWY::Neg(one));
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        case 2:
                            {
                                //const float square = (voicePhase < juce::MathConstants<double>::pi) ? 1.0f : -1.0f;
                                const FltType pi = HWY::Set(_flttype, 3.141592653589793238f);
                                tmp = HWY::IfThenElse(HWY::Lt(voicePhase, pi), one, HWY::Neg(one));
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        case 3:
                            {
                                //const float triangle = 1.0f - 4.0f * std::abs(phaseNorm - 0.5f);
                                const FltType half = HWY::Set(_flttype, 0.5f);
                                const FltType negfour = HWY::Set(_flttype, -4.0f);
                                tmp = HWY::MulAdd(negfour, HWY::Sub(voicePhaseNorm, half), one);
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        //
                        case 4:
                            //const float saw = 2.0f * phaseNorm - 1.0f;
                            //const float sine = static_cast<float>(std::sin(voicePhase));
                            //return 0.45f * sine + 0.55f * saw;
                            {
                                HWY::SinCos(_flttype, voicePhase, tmp, tmp2); //tmp = sin
                                tmp2 = HWY::MulAdd(HWY::Add(one, one), voicePhaseNorm, HWY::Neg(one));
                                tmp = HWY::Add(HWY::Mul(HWY::Set(_flttype, 0.45f), tmp), HWY::Mul(HWY::Set(_flttype, 0.55f), tmp2));
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        case 5:
                            //return (static_cast<float>(std::rand()) / RAND_MAX) * 2.0f - 1.0f;
                            {
                                
                                static HWY::VectorXoshiro random_(static_cast<uint64_t>(std::time(nullptr)));
                                
                                IntType rnd = HWY::BitCast(_inttype, random_.operator()());
                                IntMaskType negtst = HWY::Lt(rnd, HWY::Zero(_inttype));
                                rnd = HWY::Mod(rnd, HWY::Set(_inttype, RAND_MAX));
                                rnd = HWY::IfThenElse(negtst, HWY::Neg(rnd), rnd);
                                tmp = HWY::Div(HWY::ConvertTo(_flttype, rnd), HWY::Set(_flttype, RAND_MAX));
                                tmp = HWY::MulSub(tmp, HWY::Add(one, one), one);
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        case 6:
                            //return (voicePhase < pulseWidthPhase) ? 1.0f : -1.0f;
                            {
                                 tmp = HWY::IfThenElse(HWY::Lt(voicePhase, pulseWidthPhase), one, HWY::Neg(one));
                                 outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;

                        case 7:
                            /* //const float saw = 2.0f * phaseNorm - 1.0f;
                            
                                const float s1 = saw;
                                const float s2 = 2.0f * std::fmod(phaseNorm * 1.01f, 1.0f) - 1.0f;
                                const float s3 = 2.0f * std::fmod(phaseNorm * 0.99f, 1.0f) - 1.0f;
                                return (s1 + s2 * 0.5f + s3 * 0.5f) * 0.5f;
                                */
                            {
                                const FltType two = HWY::Add(one, one);
                                FltType s1 = HWY::MulAdd(HWY::Add(one, one), voicePhaseNorm, HWY::Neg(one));
                                tmp = HWY::Mul(voicePhaseNorm, HWY::Set(_flttype, 1.01f));
                                    FltType s2 = HWY::MulSub(two, HWY::Fmod(tmp, one), one);
                                tmp = HWY::Mul(voicePhaseNorm, HWY::Set(_flttype, 0.99f));
                                FltType s3 = HWY::MulSub(two, HWY::Fmod(tmp, one), one);
                            }

                            break;
                        default:
                            //return sine;
                            {
                                //const float sine = static_cast<float>(std::sin(voicePhase));
                                HWY::SinCos(_flttype, voicePhase, tmp, tmp2); //tmp = sin
                                outWaveformSamples = HWY::IfThenElse(mask, tmp, outWaveformSamples);
                            }
                            break;
                    }
                }

                HWY_ATTR  void waveAddBandIndexForFrequency(const FltType & frequency,  IntType & retBandIndex)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    const FltType samplerate = HWY::Set(_flttype, sampleRate_);
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType ratio = HWY::Set(_flttype, 0.475f);
                    FltType kWaveAddBandCount = HWY::Set(_flttype, c_wave_add_band_count);

                    //const float safeFrequency = std::max(1.0f, std::abs(frequency));
                    FltType safeFrequency = HWY::Abs(frequency);
                    safeFrequency = HWY::IfThenElse(HWY::Lt(safeFrequency, one), one, safeFrequency);

                    //const float maxRatio = std::max(1.0f, static_cast<float>((sampleRate * 0.475) / safeFrequency));
                    FltType maxRatio = HWY::Mul(samplerate, ratio);
                    maxRatio = HWY::Div(maxRatio, safeFrequency);
                    maxRatio = HWY::IfThenElse(HWY::Lt(maxRatio, one), one, maxRatio);

                    //return juce::jlimit(0, kWaveAddBandCount - 1, ratioBucket - 1);  
                    //Note conversion to int is done later for ease
                    //const int ratioBucket = static_cast<int>(std::floor(std::min(maxRatio, static_cast<float>(kWaveAddBandCount))));
                    FltType ratioBucket = HWY::IfThenElse(HWY::Gt(maxRatio, kWaveAddBandCount), maxRatio, kWaveAddBandCount);
                    ratioBucket = HWY::Sub(HWY::Floor( ratioBucket), one);
                    
                    // return juce::jlimit(0, kWaveAddBandCount - 1, ratioBucket - 1);
                    kWaveAddBandCount = HWY::Sub(kWaveAddBandCount, one);
                    ratioBucket = HWY::Limit(zero, kWaveAddBandCount, ratioBucket);
                    retBandIndex = HWY::ConvertTo(_inttype, ratioBucket);
                }


                HWY_ATTR void lookupWaveAddSampleInternal(const FltMaskType & mask, const FltType & phaseNorm, const IntType & bandIndex, FltType & ret)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                    constexpr size_t maxLanes = _flttype.MaxLanes();
                    
                    /*  const float wrappedPhase = [] (float phase) {
                        const float wrapped = std::fmod(phase, 1.0f);
                        return wrapped < 0.0f ? wrapped + 1.0f : wrapped;
                    }(phaseNorm);
                    const float position = wrappedPhase * static_cast<float>(kWaveAddTableSize); */

                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType zero = HWY::Sub(one, one);
                    const FltType kWaveAddTableSize =  HWY::Set(_flttype, c_wave_add_table_size);
                    FltType position = HWY::Fmod(phaseNorm, one);
                    position = HWY::IfThenElse(HWY::Lt(position, zero), HWY::Add(position, one), position); //wrappedPhase
                    position = HWY::Mul(kWaveAddTableSize, position);

                    //const int index = juce::jlimit(0, kWaveAddTableSize - 1, static_cast<int>(position));
                    const FltType index = HWY::Limit(zero, HWY::Sub(kWaveAddTableSize, one), position);
                    
                    //const float frac = position - static_cast<float>(index);
                    const FltType frac = HWY::Sub(position, index);

                    //const auto& band = tableSet.bands[static_cast<std::size_t>(juce::jlimit(0, kWaveAddBandCount - 1, bandIndex))];
                    //We have a cached version of the band table in aligned memory
                    //This allows us to use Gather to use indexes to that table and read the values for 
                    //each sample in one go
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType ikWaveAddTableSize = HWY::Sub(HWY::Set(_inttype, c_wave_add_table_size), ione);
                    const IntType izero = HWY::Sub(ione, ione);
                    const IntType tablesz = HWY::Set(_inttype, static_cast<int>(bandTableSize_));
                    IntType bi = HWY::IfThenElse(HWY::Gt(bandIndex, ikWaveAddTableSize), ikWaveAddTableSize, bandIndex);
                    bi = HWY::IfThenElse(HWY::Lt(bi, izero), izero, bi);
                    bi = HWY::Mul(bi, tablesz); //Memory organised in one big block - so band index is multiplied by table size to get offset in said block
                    bi = HWY::Add(bi, HWY::ConvertTo(_inttype, index));  //Add index into the band table
                    
                    //const float a = band[static_cast<std::size_t>(index)];
                    //const float b = band[static_cast<std::size_t>(index + 1)];
                    FltType a = HWY::GatherIndex(_flttype, addWaveTableSet_.get(), bi);
                    FltType b = HWY::GatherIndex(_flttype, addWaveTableSet_.get(), HWY::Add(bi, ione));
                    
                    //return a + (b - a) * frac;
                    ret = HWY::MaskedMulAddOr(ret, mask, HWY::Sub(b, a), frac, a);
                }


                HWY_ATTR  void addShapedPartialSample(const IntMaskType & mask,
                                                    const FltType & phaseNorm,
                                                    const FltType & ratio,
                                                    const FltType & amplitude,
                                                    const FltType & phaseOffset,
                                                    /*const IntType & ctrlPartialCount, */const FltType & ctrlTilt, const FltType & ctrlDrift,const IntType & ctrlwaveform, 
                                                    FltType & sum, FltType & amplitudeSum)
            {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType negone = HWY::Neg(one);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType minRatio = HWY::Set(_flttype, 0.1f);
                    const FltType twoPi = HWY::Set(_flttype, 2 * 3.141592653589793238f);
                    const FltType safeRatioDriftCoeff = HWY::Set(_flttype, 0.05f);
                    const FltType driftCoeff = HWY::Set(_flttype, 0.035f);
                    const FltType shapedPhaseDriftCoeff = HWY::Set(_flttype,  0.85f);
                    const FltType tiltScaleCoeff = shapedPhaseDriftCoeff;
                    const FltType ratioJitterCoeff = HWY::Set(_flttype, 2.173f);
                    const FltType ratioJitterWaveformCoeff = HWY::Set(_flttype, 0.53f);
                    const FltType phaseJitterSafeRatioCoeff = HWY::Set(_flttype, 1.618f);
                    const FltType phaseJitterCoeff = HWY::Set(_flttype, 0.37f);
                    const FltType maxTiltScale = HWY::Set(_flttype, 0.12f);
                    FltType s, c,tmp;

                    //const double safeRatio = std::max(0.1, ratio);
                    FltType safeRatio = HWY::IfThenElse(HWY::Lt(ratio, minRatio), minRatio, ratio);

                    //const double ratioJitter = std::sin(safeRatio * 2.173 + static_cast<double>(controls.waveform) * 0.53);
                    FltType ratioJitter;
                    FltType waveform = HWY::ConvertTo(_flttype, ctrlwaveform);
                    HWY::SinCos(_flttype, HWY::MulAdd(safeRatio, ratioJitterCoeff, HWY::Mul(ratioJitterWaveformCoeff, waveform)), ratioJitter, tmp);

                    // const float drift = juce::jlimit(0.0f, 1.0f, controls.drift);
                    const FltType drift = HWY::Limit(zero, one, ctrlDrift);
                        
                    //const double driftRatio = 1.0 + ratioJitter * static_cast<double>(drift) * 0.035 * (1.0 + safeRatio * 0.05);
                    FltType driftRatio = HWY::MulAdd(safeRatio, safeRatioDriftCoeff, one);
                    driftRatio = HWY::Mul(driftRatio, drift);
                    driftRatio = HWY::Mul(driftRatio, driftCoeff);
                    driftRatio = HWY::MulAdd(driftRatio, ratioJitter, one);

                    //const double shapedRatio = std::max(0.1, safeRatio * driftRatio);
                    FltType shapedRatio = HWY::Mul(safeRatio, driftRatio);
                    shapedRatio = HWY::IfThenElse(HWY::Lt(shapedRatio, minRatio), minRatio, shapedRatio);

                    //const double phaseJitter = std::sin(safeRatio * 1.618 + static_cast<double>(controls.waveform) * 0.37);
                    tmp = HWY::Mul(safeRatio, phaseJitterSafeRatioCoeff);
                    tmp = HWY::MulAdd(waveform, phaseJitterCoeff, tmp);
                    HWY::SinCos(_flttype, tmp, s, c);

                    //const double shapedPhase = phaseOffset + phaseJitter * static_cast<double>(drift) * 0.85;
                    FltType shapedPhase = HWY::MulAdd(s, HWY::Mul(drift, shapedPhaseDriftCoeff), phaseOffset);

                    //const float tilt = juce::jlimit(-1.0f, 1.0f, controls.tilt);
                    const FltType tilt = HWY::Limit(negone, one, ctrlTilt);

                    //const float tiltScale = std::max(0.12f, std::pow(static_cast<float>(safeRatio), tilt * 0.85f));
                    FltType tiltScale = HWY::Pow(_flttype, safeRatio, HWY::Mul(tilt, tiltScaleCoeff));

                    //onst float shapedAmplitude = amplitude * tiltScale;
                    FltType shapedAmplitude = HWY::Mul(amplitude, tiltScale);

                    //sum += static_cast<float>(std::sin(kTwoPi * static_cast<double>(phaseNorm) * shapedRatio + shapedPhase)) * shapedAmplitude;
                    tmp = HWY::Mul(twoPi, phaseNorm);
                    tmp = HWY::MulAdd(tmp, shapedRatio, shapedPhase);
                    HWY::SinCos(_flttype, tmp, s, c);
                    s = HWY::Mul(s, shapedAmplitude);
                    sum = HWY::MaskedAddOr(sum, HWY::RebindMask(_flttype, mask),  sum, s);
                    amplitudeSum = HWY::MaskedAddOr(amplitudeSum, HWY::RebindMask(_flttype, mask), amplitudeSum, shapedAmplitude);
                }


                HWY_ATTR void additiveSquareSample(const FltMaskType & mask,
                                                    const FltType & phaseNorm, const IntType & harmonicLimit,
                                                    const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                    FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;
                
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType itwo = HWY::Add(ione,ione);
                    const IntType izero = HWY::Sub(ione, ione);
                    const FltType zero = HWY::Zero(_flttype);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);

                    //const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
                    const IntType partialCount = HWY::Limit(ione, harmonicLimit, ctrlPartialCount);
              
                    //sample = additiveSquareSample(phaseNorm, harmonicLimit, controls);
                    //for (int harmonic = 1; harmonic <= harmonicLimit && added < partialCount; harmonic += 2, ++added) {
                    //    addShapedPartialSample(phaseNorm,
                    //                       static_cast<double>(harmonic),
                    //                       1.0f / static_cast<float>(harmonic),
                    //                       0.0,
                    //                       controls,
                    //                       sum,
                    //                       amplitudeSum);
                    // }
                    
                    FltType ratio, amplitude;
                    FltType amplitudeSum = zero;
                    FltType sum = zero;
                    IntType harmonic = ione;
                    IntType added = izero;
                    IntMaskType cmp;
                    
                    cmp = HWY::MaskedLe(HWY::RebindMask(_inttype, mask),harmonic, harmonicLimit);
                    cmp = HWY::MaskedLt(cmp, added, partialCount);
                    while(!HWY::AllFalse(_inttype, cmp))
                    {   
                        ratio = HWY::ConvertTo(_flttype, harmonic);
                        amplitude = HWY::ApproximateReciprocal(ratio);
    
                        addShapedPartialSample(cmp,
                                                phaseNorm,
                                                ratio,   //static_cast<double>(harmonic)
                                                amplitude,  //1.0f / static_cast<float>(harmonic),
                                                zero, //0.0
                                                ctrlTilt, ctrlDrift, ctrlWaveform, // controls
                                                sum, amplitudeSum);
                            
                        harmonic = HWY::Add(harmonic, itwo);
                        added = HWY::Add(added, ione);
                        cmp = HWY::MaskedLe(HWY::RebindMask(_inttype, mask), harmonic, harmonicLimit);
                        cmp = HWY::MaskedLt(cmp, added, partialCount);
                    }

                    //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }

                HWY_ATTR  void additiveSawSample(const FltMaskType & mask,
                                                const FltType & phaseNorm, const IntType & harmonicLimit,
                                                const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType izero = HWY::Sub(ione, ione);
                    const FltType zero = HWY::Zero(_flttype);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);
                    const FltType pi = HWY::Set(_flttype, 3.141592653589793238f);
                    
                    //const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
                    const IntType partialCount = HWY::Limit(ione, harmonicLimit, ctrlPartialCount);
                    
                    //float amplitudeSum = 0.0f;
                    //for (int harmonic = 1; harmonic <= partialCount; ++harmonic) {
                    //      const bool negative = (harmonic % 2) == 0;
                    //        addShapedPartialSample(phaseNorm,
                    //                                static_cast<double>(harmonic),
                    //                               1.0f / static_cast<float>(harmonic),
                    //                               negative ? M_PI : 0.0,
                    //                               controls,    
                    //                               sum,
                    //                               amplitudeSum);
                    //}
                    
                    IntType harmonic = ione;
                    FltType phaseOffset, ratio, amplitude;
                    FltType amplitudeSum = zero;
                    FltType sum = zero;
                    IntMaskType cmp;
                    cmp = HWY::MaskedLe(HWY::RebindMask(_inttype, mask), harmonic, partialCount);
                    while(!HWY::AllFalse(_inttype, cmp))
                    {
                        //const bool negative = (harmonic % 2) == 0;
                        //Odd = negative
                        //Even = positive
                        //X & 1 == 0 is even,  X & 1 == 1 is odd
                        phaseOffset = HWY::IfThenElse( HWY::RebindMask(_flttype, HWY::Eq(HWY::And(harmonic, ione), izero)), zero, pi); //negative ? M_PI : 0.0,
                        ratio = HWY::ConvertTo(_flttype, harmonic);
                        amplitude = HWY::ApproximateReciprocal(ratio);
                        addShapedPartialSample(cmp,
                                                phaseNorm,   //phaseNorm
                                                ratio, //static_cast<double>(harmonic)
                                                amplitude, //1.0f / static_cast<float>(harmonic),
                                                phaseOffset, 
                                                ctrlTilt, ctrlDrift, ctrlWaveform, // controls
                                                sum, amplitudeSum);

                        harmonic = HWY::Add(ione, harmonic);
                        cmp = HWY::MaskedLe(HWY::RebindMask(_inttype, mask), harmonic, harmonicLimit);
                    }

                    //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }

                HWY_ATTR void additiveTriangleSample(const FltMaskType & mask,
                                                    const FltType & phaseNorm, const IntType & harmonicLimit,
                                                    const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                    FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const FltType halfpi = HWY::Set(_flttype, 0.5f * 3.141592653589793238f);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);
                    const FltType zero = HWY::Zero(_flttype);
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType izero = HWY::Sub(ione, ione);
                    const IntType itwo = HWY::Add(ione, ione);

                    //const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
                    const IntType partialCount = HWY::Limit(ione, harmonicLimit, ctrlPartialCount);
                  
                    //sample = additiveTriangleSample(phaseNorm, harmonicLimit, controls);
                    //
                    //for(int harmonic = 1; harmonic <= harmonicLimit && added < partialCount; harmonic += 2, ++added)
                    //{
                    //    const bool positiveCosine = ((harmonic / 2) % 2) == 1;
                    //    addShapedPartialSample(phaseNorm,
                    //                           static_cast<double>(harmonic),
                    //                           1.0f / static_cast<float>(harmonic * harmonic),
                    //                           positiveCosine ? (M_PI * 0.5) : (-M_PI * 0.5),
                    //                           controls,
                    //                           sum,
                    //                           amplitudeSum);
                    // }

                    IntType itmp;
                    IntType added = izero;
                    IntType harmonic = ione;
                    IntMaskType cmp;
                    FltType phaseOffset, ratio, amplitude;
                    FltType amplitudeSum = zero;
                    FltType sum = zero;
                    

                    cmp = HWY::MaskedLe( HWY::RebindMask(_inttype, mask) ,harmonic, harmonicLimit);
                    cmp = HWY::MaskedLt(cmp, added, partialCount);
                    while(!HWY::AllFalse(_inttype, cmp))
                    {
                        ratio = HWY::ConvertTo(_flttype, harmonic);
                        amplitude = HWY::ApproximateReciprocal(HWY::Mul(ratio, ratio));

                        //const bool positiveCosine = ((harmonic / 2) % 2) == 1;
                        //positiveCosine ? (M_PI * 0.5) : (-M_PI * 0.5),
                        //
                        // positiveCosine is true if (n/2) is odd
                        // positiveCosine is false if (n/2) is even
                        //
                        // (n/2) & 1 == 0 - even
                        // (n/2) & 1 == 1 - odd
                        itmp = HWY::ShiftRight<1>(harmonic);
                        itmp = HWY::And(itmp, ione);
                        phaseOffset = HWY::IfThenElse(HWY::RebindMask(_flttype, HWY::Eq(itmp, ione)), halfpi, HWY::Neg(halfpi));

                        addShapedPartialSample(cmp,
                                                phaseNorm,
                                                ratio,   //static_cast<double>(harmonic)
                                                amplitude,  //1.0f / static_cast<float>(harmonic),
                                                phaseOffset, //positiveCosine ? (M_PI * 0.5) : (-M_PI * 0.5),
                                                ctrlTilt, ctrlDrift, ctrlWaveform, // controls
                                                sum, amplitudeSum);

                        harmonic = HWY::Add(harmonic, itwo);
                        added = HWY::Add(added, ione);
                        cmp = HWY::MaskedLe( HWY::RebindMask(_inttype, mask), harmonic, harmonicLimit);
                        cmp = HWY::MaskedLt(cmp, added, partialCount);
                    }

                    //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt( amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }

                HWY_ATTR void additiveNoiseSample(const FltMaskType & mask,
                                                const FltType & phaseNorm, const FltType & maxRatio,
                                                const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    //for (const auto& partial : kNoiseCloud) {
                        // if (partial.ratio > static_cast<double>(maxRatio) || added >= controls.partialCount) {
                            //continue;
                        //}
                        // addShapedPartialSample(phaseNorm,
                        //     partial.ratio,
                        //     partial.amplitude,
                        //     partial.phaseOffset,
                        //     controls,
                        //     sum,
                        //     amplitudeSum); 
                    //}

                    const IntType ione = HWY::Set(_inttype, 1);
                    const FltType zero = HWY::Zero(_flttype);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);
                    
                    FltType ratio, amplitude, phaseOffset;
                    IntType added = HWY::Zero(_inttype);
                    FltType amplitudeSum = zero;
                    FltType sum = zero;

                    IntMaskType cmp;
                    for(size_t x = 0; x < (sizeof(constants::kNoiseCloud) / sizeof(constants::kNoiseCloud[0])); ++x)
                    {
                        const InharmonicPartial & partial = constants::kNoiseCloud[x];

                        cmp = HWY::MaskedLt(  HWY::RebindMask(_inttype,mask), added, ctrlPartialCount);
                        if(HWY::AllFalse(_inttype, cmp))
                            break;

                        cmp = HWY::RebindMask(_inttype,HWY::MaskedLt( HWY::RebindMask(_flttype,cmp), HWY::Set(_flttype,static_cast<float>(partial.ratio)), maxRatio));

                        ratio = HWY::Set(_flttype, static_cast<float>( partial.ratio));
                        amplitude = HWY::Set(_flttype, partial.amplitude);
                        phaseOffset = HWY::Set(_flttype, static_cast<float>(partial.phaseOffset));

                        addShapedPartialSample(cmp, phaseNorm, ratio, amplitude, phaseOffset,
                                               ctrlTilt, ctrlDrift,ctrlWaveform,
                                               sum, amplitudeSum);
                     
                        added = HWY::Add(added, ione);
                    }

                     //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }


                HWY_ATTR void additiveBlendSample(const FltMaskType & mask,
                                                const FltType & phaseNorm, const IntType & harmonicLimit,
                                                const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const FltType twoPi = HWY::Set(_flttype, 2 * 3.141592653589793238f);
                    const FltType sawCoeff = HWY::Set(_flttype, 0.55f);
                    const FltType sinCoeff = HWY::Set(_flttype, 0.45f);
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType negone = HWY::Neg(one);

                    FltType sine, tmp, saw;

                    //const float sine = std::sin(kTwoPi * static_cast<double>(phaseNorm));
                    HWY::SinCos(_flttype, HWY::Mul(twoPi, phaseNorm), sine, tmp); 
                                
                    //const float saw = additiveSawSample(phaseNorm, harmonicLimit, controls);
                    additiveSawSample(mask,
                                      phaseNorm, harmonicLimit,
                                      ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                      saw);  

                    //return juce::jlimit(-1.0f, 1.0f, sine * 0.45f + saw * 0.55f);
                    tmp = HWY::MulAdd(saw, sawCoeff, HWY::Mul(sine, sinCoeff));
                    retWaveSample = HWY::MaskedLimit(retWaveSample, mask, negone, one, tmp);
                }
                
                HWY_ATTR  void additivePulseSample(const FltMaskType & mask,
                                                    const FltType & phaseNorm, const IntType & harmonicLimit, const FltType & pulseWidth,
                                                    const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform,
                                                    FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const IntType ione = HWY::Set(_inttype, 1);
                    const FltType pi = HWY::Set(_flttype, 3.141592653589793238f);
                    const FltType widthMax = HWY::Set(_flttype, 0.99f);
                    const FltType widthMin = HWY::Set(_flttype, 0.01f);
                    const FltType zero =  HWY::Zero(_flttype);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);

                    //const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
                    const IntType partialCount = HWY::Limit(ione, harmonicLimit, ctrlPartialCount);
                   
                    //const float width = juce::jlimit(0.01f, 0.99f, pulseWidth);
                    FltType widthPi = HWY::Limit(widthMin, widthMax, pulseWidth);
                        
                    //Multiply by PI
                    widthPi = HWY::Mul(widthPi, pi);

                    //for (int harmonic = 1; harmonic <= partialCount; ++harmonic) {
                    //    const float coeff = std::sin(static_cast<float>(M_PI) * static_cast<float>(harmonic) * width);
                    //    addShapedPartialSample(phaseNorm,
                    //                           static_cast<double>(harmonic),
                    //                           std::abs(coeff) / static_cast<float>(harmonic),
                    //                           coeff < 0.0f ? M_PI : 0.0,
                    //                           controls,
                    //                           sum,
                    //                           amplitudeSum);
                    //}

                    FltType amplitudeSum = zero;
                    FltType sum = zero;
                    IntType harmonic = ione;
                    IntMaskType cmp = HWY::MaskedLt(HWY::RebindMask(_inttype, mask) ,harmonic, partialCount);
                    FltType tmp, coeff, ratio, amplitude, phaseOffset;
                    while(!HWY::AllFalse(_inttype,cmp))
                    {
                        ratio = HWY::ConvertTo(_flttype, harmonic);
                        
                        //const float coeff = std::sin(static_cast<float>(M_PI) * static_cast<float>(harmonic) * width);
                        HWY::SinCos(_flttype, HWY::Mul(ratio, widthPi), coeff, tmp);
                    
                        amplitude = HWY::Div(coeff, ratio);
                        phaseOffset = HWY::IfThenElse(HWY::Lt(coeff, zero), pi, zero);

                        addShapedPartialSample(cmp, 
                                               phaseNorm,
                                               ratio,
                                               amplitude,
                                               phaseOffset,
                                               ctrlTilt, ctrlDrift, ctrlWaveform,
                                               sum, amplitudeSum);
                                               
                    

                        harmonic = HWY::Add(harmonic, ione);
                        cmp = HWY::MaskedLt(HWY::RebindMask(_inttype, mask), harmonic, partialCount);
                    }

                    //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }

                HWY_ATTR void additiveSuperSawSampleFromRatioLimit(const FltMaskType & mask, 
                                                                    const FltType & phaseNorm, const FltType & maxRatio,
                                                                    const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform,
                                                                    FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const size_t laysz = constants::kSuperSawLayers.size();
                    const IntType layersSize = HWY::Set(_inttype, static_cast<int>(laysz));
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType izero = HWY::Sub(ione, ione);
                    const FltType twoPiRcp = HWY::Set(_flttype, 1.0f / (2 * 3.141592653589793238f));
                    const FltType detuneCoeff = HWY::Set(_flttype, 1.0f / 1200.0f);
                    const FltType one = HWY::Set(_flttype, 1.0f);
                    const FltType two = HWY::Add(one,one);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType maxAmpSum = HWY::Set(_flttype, 1.0e-6f);
                    const IntType kMaxAdditiveHarmonics = HWY::Set(_inttype, c_max_additive_harmonics);

                    //const int layerLimit = juce::jlimit(1, static_cast<int>(kSuperSawLayers.size()), controls.partialCount);
                    const IntType layerLimit = HWY::Limit(ione, layersSize, ctrlPartialCount);
                        
                    size_t idx = 0;
                    IntType harmonicLimit;
                    IntType layerIndex = izero;
                    IntMaskType cmp = HWY::MaskedLt(HWY::RebindMask(_inttype, mask), layerIndex, layerLimit);
                    FltType layerPhase, layerRatioLimit, detuneRatio, gain, sample;
                    FltType amplitudeSum = zero;
                    FltType sum = zero;

                    while((idx < laysz) &&  !HWY::AllFalse(_inttype, cmp))
                    {   
                        const SuperSawLayer & layer = constants::kSuperSawLayers[idx];
                        
                        //const double detuneRatio = std::pow(2.0, static_cast<double>(layer.detuneCents) / 1200.0);
                        detuneRatio = HWY::Set(_flttype, layer.detuneCents);
                        detuneRatio = HWY::Pow(_flttype, two, HWY::Mul(detuneRatio, detuneCoeff));

                        //const float layerPhase = wrapPhase01(phaseNorm * static_cast<float>(detuneRatio) + static_cast<float>(layer.phaseOffset / kTwoPi));
                        layerPhase = HWY::Set(_flttype, static_cast<float>(layer.phaseOffset));
                        layerPhase = HWY::Mul(layerPhase, twoPiRcp);
                        layerPhase = HWY::MulAdd(phaseNorm, detuneRatio, layerPhase);

                        //wrapPhase01(float phase) {
                        //const float wrapped = std::fmod(phase, 1.0f);
                        //return wrapped < 0.0f ? wrapped + 1.0f : wrapped;
                        //}
                        layerPhase = HWY::Fmod(layerPhase, one);
                        layerPhase = HWY::IfThenElse(HWY::Lt(layerPhase, zero), HWY::Add(layerPhase, one), layerPhase);

                        //const float layerRatioLimit = std::max(1.0f, maxRatio / static_cast<float>(detuneRatio));
                        layerRatioLimit = HWY::Div(maxRatio, detuneRatio);
                        layerRatioLimit = HWY::IfThenElse(HWY::Lt(layerRatioLimit, one), one, layerRatioLimit);
                       
                        // const int harmonicLimit = juce::jlimit(1, kMaxAdditiveHarmonics, static_cast<int>(std::floor(layerRatioLimit)));
                        harmonicLimit = HWY::ConvertTo(_inttype, HWY::Floor(layerRatioLimit));
                        harmonicLimit = HWY::Limit(ione, kMaxAdditiveHarmonics, harmonicLimit);
                        
                        //const float sample = additiveSawSample(layerPhase, harmonicLimit, controls);
                        additiveSawSample(mask,
                                          layerPhase, harmonicLimit,
                                          ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                          sample);

                        //sum += sample * layer.gain;
                        // amplitudeSum += layer.gain;
                        gain = HWY::Set(_flttype, layer.gain);
                        sum = HWY::MaskedMulAddOr(sum, HWY::RebindMask(_flttype, cmp), sample, gain, sum);
                        amplitudeSum = HWY::MaskedAddOr(amplitudeSum, HWY::RebindMask(_flttype, cmp), amplitudeSum, gain);

                        layerIndex = HWY::Add(layerIndex, ione);
                        cmp = HWY::MaskedLt(HWY::RebindMask(_inttype, mask), layerIndex, layerLimit);
                        ++idx;
                    }

                    //return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
                    retWaveSample = HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(amplitudeSum, maxAmpSum), HWY::Div(sum, amplitudeSum), zero), retWaveSample);
                }


                HWY_ATTR void additiveRecipeSampleFromRatioLimit(const FltMaskType & mask,
                                                                int waveform, const FltType & phaseNorm, const FltType & maxRatio, const FltType & pulseWidth,
                                                                const IntType & ctrlPartialCount, const FltType & ctrlTilt, const FltType & ctrlDrift, const IntType & ctrlWaveform, 
                                                                FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const IntType maxHarmonics = HWY::Set(_inttype, c_max_additive_harmonics);
                    const IntType ione = HWY::Set(_inttype, 1);
                    const FltType one = HWY::Set(_flttype, 1);
                    const FltType twoPi = HWY::Set(_flttype, 2 * 3.141592653589793238f);
                    
                    //const int harmonicLimit = juce::jlimit(1, kMaxAdditiveHarmonics, static_cast<int>(std::floor(std::max(1.0f, maxRatio))));
                    FltType temp, temp2;
                    IntType itmp = HWY::ConvertTo(_inttype, HWY::Floor(HWY::IfThenElse(HWY::Lt(maxRatio, one), one, maxRatio)));
                    
                    const IntType harmonicLimit = HWY::Limit(ione, maxHarmonics, itmp);
                        
                    switch(waveform)
                    {  
                        case 1:
                            additiveSawSample(mask, phaseNorm, harmonicLimit,
                                              ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                              retWaveSample);
                            break;
                        case 2:
                            additiveSquareSample(mask, phaseNorm, harmonicLimit, 
                                                 ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                 retWaveSample);
                            break;

                        case 3:
                            additiveTriangleSample(mask, phaseNorm, harmonicLimit,
                                                   ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                   retWaveSample);
                            break;

                        case 4:
                            additiveBlendSample(mask, phaseNorm, harmonicLimit,
                                                ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                retWaveSample);
                            break;

                        case 5:
                            additiveNoiseSample(mask, phaseNorm, maxRatio,
                                                ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                retWaveSample);
                            break;

                        case 6:
                            additivePulseSample(mask,phaseNorm, harmonicLimit, pulseWidth, 
                                                ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                retWaveSample);
                            break;

                        case 7:
                            additiveSuperSawSampleFromRatioLimit(mask, phaseNorm, maxRatio,
                                                                 ctrlPartialCount, ctrlTilt, ctrlDrift, ctrlWaveform,
                                                                 retWaveSample);
                            break;

                        case 0:
                        default:
                            //sample = static_cast<float>(std::sin(kTwoPi * static_cast<double>(phaseNorm)));
                            HWY::SinCos(_flttype, HWY::Mul(phaseNorm, twoPi), temp, temp2); //sine value in 'temp'
                            retWaveSample = HWY::IfThenElse(mask, temp, retWaveSample);
                            break;
                    }
                }

                HWY_ATTR void additiveRecipeSample(const FltMaskType & mask,
                                                    int waveform, const FltType & phaseNorm, const FltType & baseFrequency,  const FltType & pulseWidth,
                                                    const IntType & partialCount, const FltType & tilt, const FltType & drift, 
                                                    FltType & retWaveSample)
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    namespace HWY = hwy::HWY_NAMESPACE;

                    const FltType one = HWY::Set(_flttype, 1.0f);

                    //const float maxRatio = std::max(1.0f, static_cast<float>((sampleRate * 0.475) / std::max(1.0f, std::abs(baseFrequency))));
                    const FltType maxCoeff = HWY::Set(_flttype, 0.475f);
                    const FltType samplerate = HWY::Set(_flttype, sampleRate_);
                    FltType maxRatio = HWY::Abs(baseFrequency);
                    maxRatio = HWY::IfThenElse(HWY::Lt(maxRatio, one), one, maxRatio);
                    maxRatio = HWY::Div(HWY::Mul(samplerate, maxCoeff), maxRatio);
                    maxRatio = HWY::IfThenElse(HWY::Lt(maxRatio, one), one, maxRatio);
                    
                    /*
                        const AdditiveShapeControls controls {
                        juce::jlimit(1, kMaxAdditiveHarmonics, partialCount),
                        juce::jlimit(-1.0f, 1.0f, tilt),
                        juce::jlimit(0.0f, 1.0f, drift),
                        waveform,
                    };
                    */
                    const IntType ione = HWY::Set(_inttype, 1);
                    const IntType maxHarmonics = HWY::Set(_inttype, c_max_additive_harmonics);
                    const IntType ctrlPcount = HWY::Limit(ione, maxHarmonics, partialCount);
                    const FltType negone = HWY::Neg(one);
                    const FltType ctrlTilt = HWY::Limit(negone, one, tilt);
                    const FltType zero = HWY::Sub(one,one);
                    const FltType ctrlDrift = HWY::Limit(zero, one, drift);
                        
                    //return additiveRecipeSampleFromRatioLimit(waveform, phaseNorm, maxRatio, pulseWidth, controls);
                    additiveRecipeSampleFromRatioLimit(mask, waveform, phaseNorm, maxRatio, pulseWidth, ctrlPcount, ctrlTilt, ctrlDrift,  HWY::Set(_inttype, waveform), retWaveSample);
                }

                HWY_ATTR void renderAdditiveSample(const FltMaskType & mask, const FltType & voiceFrequency, const FltType & voicePhaseNorm, const FltType & pulseWidthNorm,
                                                    int waveform, const IntType & effectiveAdditivePartials, const FltType & additiveTilt, const FltType & additiveDrift,
                                                    FltType & retWaveSample)
                {
                    if((waveAddTableSet_ != NULL) && (waveAddTableSet_->get() != NULL))
                    {
                        IntType bandIndex;
                        waveAddBandIndexForFrequency(voiceFrequency, bandIndex); //Returns bandIndex
                        lookupWaveAddSampleInternal(mask, voicePhaseNorm, bandIndex, retWaveSample);
                        return;
                    }

                    return additiveRecipeSample(mask, waveform, voicePhaseNorm, voiceFrequency, pulseWidthNorm,
                                                effectiveAdditivePartials, additiveTilt, additiveDrift, 
                                                retWaveSample);
                }
            
                HWY_ATTR void configure()
                {
                    const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                    const hwy::HWY_NAMESPACE::ScalableTag<int32_t> _inttype;
                    const hwy::HWY_NAMESPACE::DFromV<VoiceSmoother::ValueType> _voicesflttype;

                    namespace HWY = hwy::HWY_NAMESPACE;
                    const size_t numLanes = HWY::Lanes(_flttype);

                
                    if(!previousSyncSample_ || (laneCount_ != numLanes))
                    {
                        previousSyncSample_ = hwy::AllocateAligned<float>(numLanes);
                        memset(previousSyncSample_.get(), 0, numLanes * sizeof(float));
                    }

                    if(!laneNumbers_ || (laneCount_ != numLanes))
                    {
                        laneNumbers_ =  hwy::AllocateAligned<float>(numLanes);
                        FltType lane = HWY::Iota(_flttype, 1.0f);
                        HWY::Store(lane, _flttype, laneNumbers_.get());
                    }

                    if(!phaseValues_)
                    {
                        const size_t numVoices = HWY::MaxLanes(_voicesflttype);
                        phaseValues_ = hwy::AllocateAligned<float>(numLanes * numVoices);
                        memset(phaseValues_.get(), 0, numVoices * numLanes * sizeof(float));
                    }

                    if(!pulseWidthPhase_ || (laneCount_ != numLanes))
                        pulseWidthPhase_ =  hwy::AllocateAligned<float>(numLanes);

                    if(!pulseWidthNorm_ || (laneCount_ != numLanes))
                        pulseWidthNorm_ =  hwy::AllocateAligned<float>(numLanes);

                    //---------------------------
                    
                    const FltType twoPi = HWY::Set(_flttype, 2 * 3.141592653589793238f);
                    FltType val = HWY::Set(_flttype, targetPulseWidth_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, pulseWidthNorm_.get());
                    val = HWY::Mul(twoPi, val);
                    HWY::Store(val, _flttype, pulseWidthPhase_.get());

                    //---------------------------
                    
                    if(!additivePartialValues_ || (laneCount_ != numLanes))
                        additivePartialValues_ =  hwy::AllocateAligned<int32_t>(numLanes);

                    IntType ival = HWY::Set(_inttype, additivePartials_->load(std::memory_order_acquire));
                    HWY::Store(ival, _inttype, additivePartialValues_.get());

                    
                    //---------------------------

                    if(!additiveTiltValues_ || (laneCount_ != numLanes))
                        additiveTiltValues_ =  hwy::AllocateAligned<float>(numLanes);

                    val = HWY::Set(_flttype, additiveTilt_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, additiveTiltValues_.get());

                    //---------------------------

                    if(!additiveDriftValues_ || (laneCount_ != numLanes))
                        additiveDriftValues_ =  hwy::AllocateAligned<float>(numLanes);

                    val = HWY::Set(_flttype, additiveDrift_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, additiveDriftValues_.get());

                    //---------------------------

                    if(!driveValues_ || (laneCount_ != numLanes))
                        driveValues_ = hwy::AllocateAligned<float>(numLanes);

                    val = HWY::Set(_flttype, drive_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, driveValues_.get());

                    //---------------------------

                    if(!driveBiasValues_ || (laneCount_ != numLanes))
                        driveBiasValues_ = hwy::AllocateAligned<float>(numLanes);

                    val = HWY::Set(_flttype, drivebias_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, driveBiasValues_.get());

                    //---------------------------

                    if(!driveMixValues_ || (laneCount_ != numLanes))
                        driveMixValues_ = hwy::AllocateAligned<float>(numLanes);

                    val = HWY::Set(_flttype, drivemix_->load(std::memory_order_acquire));
                    HWY::Store(val, _flttype, driveMixValues_.get());

                    //------------------------------

                    
                    laneCount_ = numLanes;
                    configChanged_ = false;
                }

                //===========================================================================================

                //Used by smoother to convert from render mode atmoic into a float.
                class RenderModeToRenderMix : public Smoother::SmoothValueConverterTplt<int>
                {
                public:
                    RenderModeToRenderMix(const std::atomic<int> * mode) : Smoother::SmoothValueConverterTplt<int>(mode)
                    {}

                    virtual float Convert() const override
                    {
                        return GetSourceValue() == 1 ? 1.0f : 0.0f;
                    }
                };

                //Used by unison voice smoother to convert from 'number of voices in unison' to a gain
                class UnisonVoiceCountToUnisonGain : public   VoiceSmoother::SmoothValueConverterTplt<int>
                {
                public:
                    UnisonVoiceCountToUnisonGain(const std::atomic<int> * mode) : VoiceSmoother::SmoothValueConverterTplt<int>(mode)
                    {}

                    virtual float Convert() const override
                    {
                        int targetUnison = GetSourceValue() == 1 ? 1 : 0;
                        return (lane_ < targetUnison) ? 1.0f : 0.0f;
                    }
                };

                //=======================================================================
                
                static constexpr size_t c_max_voices = 8; //If changed, then population of unisonVoicesToUnisonGainConverter_ needs changing as well
                static constexpr int c_max_additive_harmonics = 12;

                RenderModeToRenderMix renderModeToMixConverter_;
                Smoother smoother_;

                UnisonVoiceCountToUnisonGain unisonVoicesToUnisonGainConverter_[8];
                VoiceSmoother unisonVoiceSmoother_;

                const std::atomic<bool> * syncEnabled_;
                const std::atomic<float> * targetPulseWidth_;
                const std::atomic<int> * waveform_;
                const std::shared_ptr<const WaveAddTableSet> * waveAddTableSet_; //This is a raw pointer, so that updates in the parent class are automatically accessible via this pointer.
                const std::atomic<int> * additivePartials_;
                const std::atomic<float> * additiveTilt_;
                const std::atomic<float> * additiveDrift_;
                const std::atomic<float> * drive_;
                const std::atomic<int> * driveshape_;
                const std::atomic<float> * drivebias_;
                const std::atomic<float> * drivemix_;

                float sampleRate_ ;
                bool configChanged_ = true;
                size_t laneCount_ = 0;
                int lastRequestedUnison_ = 0;
                size_t numAllocatedVoiceOffsets_ = 0;
                size_t numBands_ = 0;
                size_t bandTableSize_ = 0;

                hwy::AlignedFreeUniquePtr<float[]> previousSyncSample_;
                hwy::AlignedFreeUniquePtr<float[]> phaseValues_;
                hwy::AlignedFreeUniquePtr<float[]> laneNumbers_;
                hwy::AlignedFreeUniquePtr<float[]> voiceOffsets_;
                hwy::AlignedFreeUniquePtr<float[]> pulseWidthPhase_;
                hwy::AlignedFreeUniquePtr<float[]> pulseWidthNorm_;
                hwy::AlignedFreeUniquePtr<int32_t[]> additivePartialValues_;
                hwy::AlignedFreeUniquePtr<float[]> additiveTiltValues_;
                hwy::AlignedFreeUniquePtr<float[]> additiveDriftValues_;
                hwy::AlignedFreeUniquePtr<float[]>  addWaveTableSet_; //This is a copy of the source - but in a simgle block of memory that can be easilly indexes 
                hwy::AlignedFreeUniquePtr<float[]> driveValues_;
                hwy::AlignedFreeUniquePtr<float[]> driveBiasValues_;
                hwy::AlignedFreeUniquePtr<float[]> driveMixValues_;
            };

            HWY_API IOscillatorNodeSIMDAInterface  *  __CreateInstanceForCPU(float samplerate,
                                                                             const std::atomic<float>* targetFrequency,
                                                                             const std::atomic<float>* targetAmplitude,
                                                                             const std::atomic<int>* targetWaveform,
                                                                             const std::atomic<float>* targetPulseWidth,
                                                                             const std::atomic<float>* targetDrive,
                                                                             const std::atomic<int>* targetDriveShape,
                                                                             const std::atomic<float>* targetDriveBias,
                                                                             const std::atomic<float>* targetDriveMix,
                                                                             const std::atomic<int>* targetRenderMode,
                                                                             const std::atomic<int>* targetAdditivePartials,
                                                                             const std::atomic<float>* targetAdditiveTilt,
                                                                             const std::atomic<float>* targetAdditiveDrift,
                                                                             const std::shared_ptr<const WaveAddTableSet>* targetWaveAddTableSet,
                                                                             const std::atomic<int>* targetUnisonVoices,
                                                                             const std::atomic<float>* targetDetuneCents,
                                                                             const std::atomic<float>* targetStereoSpread,
                                                                             const std::atomic<bool> * syncEnabled)
            {
                return new OscillatorNodeSIMDImplementation(samplerate,
                                                            targetFrequency,
                                                            targetAmplitude,
                                                            targetWaveform,
                                                            targetPulseWidth,
                                                            targetDrive,
                                                            targetDriveShape,
                                                            targetDriveBias,
                                                            targetDriveMix,
                                                            targetRenderMode,
                                                            targetAdditivePartials,
                                                            targetAdditiveTilt,
                                                            targetAdditiveDrift,
                                                            targetWaveAddTableSet,
                                                            targetUnisonVoices,
                                                            targetDetuneCents,
                                                            targetStereoSpread,
                                                            syncEnabled);
            }
        }

        #if HWY_ONCE || HWY_IDE

            IOscillatorNodeSIMDAInterface  *  __CreateInstance(int target, float samplerate,
                                                               const std::atomic<float>* targetFrequency,
                                                               const std::atomic<float>* targetAmplitude,
                                                               const std::atomic<int>* targetWaveform,
                                                               const std::atomic<float>* targetPulseWidth,
                                                               const std::atomic<float>* targetDrive,
                                                               const std::atomic<int>* targetDriveShape,
                                                               const std::atomic<float>* targetDriveBias,
                                                               const std::atomic<float>* targetDriveMix,
                                                               const std::atomic<int>* targetRenderMode,
                                                               const std::atomic<int>* targetAdditivePartials,
                                                               const std::atomic<float>* targetAdditiveTilt,
                                                               const std::atomic<float>* targetAdditiveDrift,
                                                               const std::shared_ptr<const WaveAddTableSet>* targetWaveAddTableSet,
                                                               const std::atomic<int>* targetUnisonVoices,
                                                               const std::atomic<float>* targetDetuneCents,
                                                               const std::atomic<float>* targetStereoSpread,
                                                               const std::atomic<bool> * syncEnabled,
                                                               hwy::RunHighwayErrorCode * retErrorCode)
            {
                HWY_EXPORT_T(_create_instance_table, __CreateInstanceForCPU);
                IOscillatorNodeSIMDAInterface * retiface = NULL;

                hwy::RunHighwayErrorCode res =  hwy::RunHighwayFunction(target, &retiface, HWY_DISPATCH_TABLE(_create_instance_table),
                                                                        samplerate, 
                                                                        targetFrequency,
                                                                        targetAmplitude,
                                                                        targetWaveform,
                                                                        targetPulseWidth,
                                                                        targetDrive,
                                                                        targetDriveShape,
                                                                        targetDriveBias,
                                                                        targetDriveMix,
                                                                        targetRenderMode,
                                                                        targetAdditivePartials,
                                                                        targetAdditiveTilt,
                                                                        targetAdditiveDrift,
                                                                        targetWaveAddTableSet,
                                                                        targetUnisonVoices,
                                                                        targetDetuneCents,
                                                                        targetStereoSpread,
                                                                        syncEnabled);

                *retErrorCode = res;
                return retiface;

            }

        #endif
    }
}

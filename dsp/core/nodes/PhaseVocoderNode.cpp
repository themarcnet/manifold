#include "dsp/core/nodes/PhaseVocoderNode.h"

#include <cmath>
#include <algorithm>

namespace dsp_primitives {

namespace {

constexpr float kPi = juce::MathConstants<float>::pi;
constexpr float kTwoPi = 2.0f * juce::MathConstants<float>::pi;

inline float princarg(float phase) {
    return phase - kTwoPi * std::floor(phase / kTwoPi + 0.5f);
}

} // namespace

PhaseVocoderNode::PhaseVocoderNode(int numChannels)
    : numChannels_(std::max(1, numChannels)) {
}

void PhaseVocoderNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 0.0 ? sampleRate : 44100.0;

    const int newOrder = fftOrderParam_.load(std::memory_order_acquire);
    fftOrder_ = juce::jlimit(9, 12, newOrder);
    fftSize_ = 1 << fftOrder_;
    hopSize_ = fftSize_ / 4;
    fft_ = std::make_unique<juce::dsp::FFT>(fftOrder_);

    const int numBins = fftSize_ / 2 + 1;
    const int ringSize = fftSize_ * 2;
    const int accumSize = fftSize_ * 2;

    inputRing_.setSize(numChannels_, ringSize, false, true, true);
    inputRing_.clear();
    inputWritePos_ = 0;

    outputAccum_.setSize(numChannels_, accumSize, false, true, true);
    outputAccum_.clear();
    outputReadPos_ = 0;
    hopWritePos_ = 0;

    // Time-stretch mode: large accumulator for time-stretched signal
    timeStretchAccum_.setSize(numChannels_, accumSize * 4, false, true, true);
    timeStretchAccum_.clear();
    tsWritePos_ = 0;
    tsReadPos_ = 0.0;

    prevAnalysisPhase_.resize(static_cast<size_t>(numChannels_));
    synthPhaseAccum_.resize(static_cast<size_t>(numChannels_));
    prevSynthMag_.resize(static_cast<size_t>(numChannels_));
    for (int ch = 0; ch < numChannels_; ++ch) {
        prevAnalysisPhase_[static_cast<size_t>(ch)].assign(static_cast<size_t>(numBins), 0.0f);
        synthPhaseAccum_[static_cast<size_t>(ch)].assign(static_cast<size_t>(numBins), 0.0f);
        prevSynthMag_[static_cast<size_t>(ch)].assign(static_cast<size_t>(numBins), 0.0f);
    }

    window_.resize(static_cast<size_t>(fftSize_));
    for (int i = 0; i < fftSize_; ++i) {
        window_[static_cast<size_t>(i)] = 0.5f - 0.5f * std::cos(
            kTwoPi * static_cast<float>(i) / static_cast<float>(fftSize_));
    }

    overlapAddNorm_ = 2.0f / 3.0f;

    fftWorkBuffer_.resize(static_cast<size_t>(fftSize_ * 2), 0.0f);
    analysisMag_.resize(static_cast<size_t>(numBins), 0.0f);
    analysisPhase_.resize(static_cast<size_t>(numBins), 0.0f);
    analysisFreq_.resize(static_cast<size_t>(numBins), 0.0f);
    synthMag_.resize(static_cast<size_t>(numBins), 0.0f);
    synthFreq_.resize(static_cast<size_t>(numBins), 0.0f);

    const double smoothTime = 0.01;
    smoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, smoothingCoeff_);

    currentMode_ = mode_.load(std::memory_order_acquire);
    currentPitchSemitones_ = pitchSemitones_.load(std::memory_order_acquire);
    currentMix_ = mix_.load(std::memory_order_acquire);
    timeStretch_.store(1.0f, std::memory_order_release);

    samplesUntilNextHop_ = hopSize_;
    hopCount_ = 0;

    prepared_ = true;
}

void PhaseVocoderNode::reset() {
    if (inputRing_.getNumChannels() > 0)
        inputRing_.clear();
    inputWritePos_ = 0;

    if (outputAccum_.getNumChannels() > 0)
        outputAccum_.clear();
    outputReadPos_ = 0;
    hopWritePos_ = 0;

    if (timeStretchAccum_.getNumChannels() > 0)
        timeStretchAccum_.clear();
    tsWritePos_ = 0;
    tsReadPos_ = 0.0;

    for (auto& chPhase : prevAnalysisPhase_)
        std::fill(chPhase.begin(), chPhase.end(), 0.0f);
    for (auto& chAccum : synthPhaseAccum_)
        std::fill(chAccum.begin(), chAccum.end(), 0.0f);
    for (auto& chMag : prevSynthMag_)
        std::fill(chMag.begin(), chMag.end(), 0.0f);

    std::fill(fftWorkBuffer_.begin(), fftWorkBuffer_.end(), 0.0f);

    currentMode_ = mode_.load(std::memory_order_acquire);
    currentPitchSemitones_ = pitchSemitones_.load(std::memory_order_acquire);
    currentMix_ = mix_.load(std::memory_order_acquire);
    timeStretch_.store(1.0f, std::memory_order_release);
    samplesUntilNextHop_ = hopSize_ > 0 ? hopSize_ : 512;
    hopCount_ = 0;
}

void PhaseVocoderNode::setMode(int mode) {
    mode_.store(juce::jlimit(0, 1, mode), std::memory_order_release);
}

int PhaseVocoderNode::getMode() const {
    return mode_.load(std::memory_order_acquire);
}

void PhaseVocoderNode::setPitchSemitones(float semitones) {
    pitchSemitones_.store(juce::jlimit(kMinPitchSemitones, kMaxPitchSemitones, semitones),
                          std::memory_order_release);
}

float PhaseVocoderNode::getPitchSemitones() const {
    return pitchSemitones_.load(std::memory_order_acquire);
}

void PhaseVocoderNode::setTimeStretch(float ratio) {
    timeStretch_.store(juce::jlimit(kMinTimeStretch, kMaxTimeStretch, ratio),
                       std::memory_order_release);
}

float PhaseVocoderNode::getTimeStretch() const {
    return timeStretch_.load(std::memory_order_acquire);
}

void PhaseVocoderNode::setMix(float mix) {
    mix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release);
}

float PhaseVocoderNode::getMix() const {
    return mix_.load(std::memory_order_acquire);
}

void PhaseVocoderNode::setFFTOrder(int order) {
    fftOrderParam_.store(juce::jlimit(9, 12, order), std::memory_order_release);
}

int PhaseVocoderNode::getFFTOrder() const {
    return fftOrderParam_.load(std::memory_order_acquire);
}

int PhaseVocoderNode::getLatencySamples() const {
    return fftSize_;
}

void PhaseVocoderNode::process(const std::vector<AudioBufferView>& inputs,
                               std::vector<WritableAudioBufferView>& outputs,
                               int numSamples) {
    const bool outputsValid = !outputs.empty() && outputs[0].numChannels > 0;
    const bool inputsValid = !inputs.empty() && inputs[0].numChannels > 0;

    if (!outputsValid)
        return;

    const float targetMix = mix_.load(std::memory_order_acquire);
    if (targetMix < 0.001f) {
        if (inputsValid) {
            const int outCh = outputs[0].numChannels;
            const int inCh = inputs[0].numChannels;
            for (int i = 0; i < numSamples; ++i) {
                for (int ch = 0; ch < outCh; ++ch) {
                    const float s = (ch < inCh) ? inputs[0].getSample(ch, i)
                                                : inputs[0].getSample(0, i);
                    outputs[0].setSample(ch, i, s);
                }
            }
        } else {
            outputs[0].clear();
        }
        return;
    }

    if (!prepared_ || !inputsValid) {
        outputs[0].clear();
        return;
    }

    const int targetMode = mode_.load(std::memory_order_acquire);
    const float targetPitch = pitchSemitones_.load(std::memory_order_acquire);
    const int ringSize = inputRing_.getNumSamples();
    const int accumSize = outputAccum_.getNumSamples();
    const int inCh = inputs[0].numChannels;
    const int outCh = outputs[0].numChannels;

    for (int i = 0; i < numSamples; ++i) {
        currentMode_ = targetMode;
        currentPitchSemitones_ += (targetPitch - currentPitchSemitones_) * smoothingCoeff_;
        currentMix_ += (targetMix - currentMix_) * smoothingCoeff_;

        // Write input to ring buffer
        for (int ch = 0; ch < numChannels_; ++ch) {
            const float s = (ch < inCh) ? inputs[0].getSample(ch, i)
                                        : inputs[0].getSample(0, i);
            inputRing_.setSample(ch, inputWritePos_, s);
        }
        inputWritePos_ = (inputWritePos_ + 1) % ringSize;

        const float mix = currentMix_;
        const float dryGain = 1.0f - mix;

        // Output
        for (int ch = 0; ch < outCh; ++ch) {
            const int srcCh = std::min(ch, numChannels_ - 1);
            const float dry = (ch < inCh) ? inputs[0].getSample(ch, i)
                                          : inputs[0].getSample(0, i);
            
            float wet = 0.0f;
            if (currentMode_ == 0) {
                wet = outputAccum_.getSample(srcCh, outputReadPos_);
                outputAccum_.setSample(srcCh, outputReadPos_, 0.0f);
            } else {
                // HQ mode: read from time-stretch accumulator with resampling
                const int tsSize = timeStretchAccum_.getNumSamples();
                int readIdx = static_cast<int>(tsReadPos_) % tsSize;
                if (readIdx < 0) readIdx += tsSize;
                
                wet = timeStretchAccum_.getSample(srcCh, readIdx);
                timeStretchAccum_.setSample(srcCh, readIdx, 0.0f);
                
                // Advance read position by resample step
                const float pitchRatio = std::pow(2.0f, currentPitchSemitones_ / 12.0f);
                tsReadPos_ += pitchRatio;
                if (tsReadPos_ >= tsSize)
                    tsReadPos_ -= tsSize;
            }

            outputs[0].setSample(ch, i, dry * dryGain + wet * mix);
        }
        
        if (currentMode_ == 0) {
            outputReadPos_ = (outputReadPos_ + 1) % accumSize;
        }

        --samplesUntilNextHop_;
        if (samplesUntilNextHop_ <= 0) {
            const float pitchRatio = std::pow(2.0f, currentPitchSemitones_ / 12.0f);
            const float omegaFactor = kTwoPi * static_cast<float>(hopSize_) / static_cast<float>(fftSize_);
            const int numBins = fftSize_ / 2 + 1;
            
            if (currentMode_ == 0) {
                processHopBinMapping(pitchRatio, omegaFactor, numBins, ringSize, accumSize);
            } else {
                processHopTimeStretch(pitchRatio, omegaFactor, numBins, ringSize);
            }
            samplesUntilNextHop_ = hopSize_;
        }
    }
}

void PhaseVocoderNode::processHopBinMapping(float pitchRatio, float omegaFactor, 
                                            int numBins, int ringSize, int accumSize) {
    int readStart = inputWritePos_ - fftSize_;
    if (readStart < 0) readStart += ringSize;

    for (int ch = 0; ch < numChannels_; ++ch) {
        const auto uch = static_cast<size_t>(ch);

        std::fill(fftWorkBuffer_.begin(), fftWorkBuffer_.end(), 0.0f);
        for (int n = 0; n < fftSize_; ++n) {
            const int pos = (readStart + n) % ringSize;
            fftWorkBuffer_[static_cast<size_t>(n)] =
                inputRing_.getSample(ch, pos) * window_[static_cast<size_t>(n)];
        }

        fft_->performRealOnlyForwardTransform(fftWorkBuffer_.data(), false);

        for (int bin = 0; bin < numBins; ++bin) {
            const auto ubin = static_cast<size_t>(bin);
            const float re = fftWorkBuffer_[ubin * 2];
            const float im = fftWorkBuffer_[ubin * 2 + 1];

            const float mag = std::sqrt(re * re + im * im);
            const float phase = std::atan2(im, re);

            const float omega = static_cast<float>(bin) * omegaFactor;
            const float rawDiff = phase - prevAnalysisPhase_[uch][ubin];
            const float deviation = princarg(rawDiff - omega);
            const float instFreq = omega + deviation;

            prevAnalysisPhase_[uch][ubin] = phase;
            analysisMag_[ubin] = mag;
            analysisFreq_[ubin] = instFreq;
        }

        std::fill(synthMag_.begin(), synthMag_.end(), 0.0f);
        std::fill(synthFreq_.begin(), synthFreq_.end(), 0.0f);

        for (int dstBin = 0; dstBin < numBins; ++dstBin) {
            const auto udst = static_cast<size_t>(dstBin);
            const float srcBinF = static_cast<float>(dstBin) / pitchRatio;
            const int srcLo = static_cast<int>(std::floor(srcBinF));
            const int srcHi = srcLo + 1;
            const float frac = srcBinF - static_cast<float>(srcLo);

            float mag = 0.0f;
            if (srcLo >= 0 && srcLo < numBins)
                mag += analysisMag_[static_cast<size_t>(srcLo)] * (1.0f - frac);
            if (srcHi >= 0 && srcHi < numBins)
                mag += analysisMag_[static_cast<size_t>(srcHi)] * frac;
            synthMag_[udst] = mag;

            float freqLo = 0.0f, freqHi = 0.0f;
            float magLo = 0.0f, magHi = 0.0f;

            if (srcLo >= 0 && srcLo < numBins) {
                magLo = analysisMag_[static_cast<size_t>(srcLo)];
                freqLo = analysisFreq_[static_cast<size_t>(srcLo)];
            }
            if (srcHi >= 0 && srcHi < numBins) {
                magHi = analysisMag_[static_cast<size_t>(srcHi)];
                freqHi = analysisFreq_[static_cast<size_t>(srcHi)];
            }

            const float totalMag = magLo + magHi;
            if (totalMag > 1e-10f) {
                const float interpFreq = (freqLo * magLo + freqHi * magHi) / totalMag;
                const float srcOmega = srcBinF * omegaFactor;
                const float deviation = interpFreq - srcOmega;
                const float dstOmega = static_cast<float>(dstBin) * omegaFactor;
                synthFreq_[udst] = dstOmega + deviation;
            } else {
                synthFreq_[udst] = static_cast<float>(dstBin) * omegaFactor;
            }
        }

        std::fill(fftWorkBuffer_.begin(), fftWorkBuffer_.end(), 0.0f);

        for (int bin = 0; bin < numBins; ++bin) {
            const auto ubin = static_cast<size_t>(bin);
            const float mag = synthMag_[ubin];

            synthPhaseAccum_[uch][ubin] += synthFreq_[ubin];

            if (mag < 1e-6f) {
                synthPhaseAccum_[uch][ubin] = princarg(synthPhaseAccum_[uch][ubin]);
            }

            const float phase = synthPhaseAccum_[uch][ubin];
            fftWorkBuffer_[ubin * 2]     = mag * std::cos(phase);
            fftWorkBuffer_[ubin * 2 + 1] = mag * std::sin(phase);

            prevSynthMag_[uch][ubin] = mag;
        }

        fft_->performRealOnlyInverseTransform(fftWorkBuffer_.data());

        const float hopGain = overlapAddNorm_;
        for (int n = 0; n < fftSize_; ++n) {
            const int outPos = (hopWritePos_ + n) % accumSize;
            const float sample = fftWorkBuffer_[static_cast<size_t>(n)]
                               * window_[static_cast<size_t>(n)]
                               * hopGain;
            const float existing = outputAccum_.getSample(ch, outPos);
            outputAccum_.setSample(ch, outPos, existing + sample);
        }
    }

    hopWritePos_ = (hopWritePos_ + hopSize_) % accumSize;
}

void PhaseVocoderNode::processHopTimeStretch(float pitchRatio, float omegaFactor,
                                             int numBins, int ringSize) {
    // Time-stretch ratio combines pitch ratio with user time stretch
    // To shift pitch UP by P: time-stretch by P (make longer), then resample by P (make shorter/higher)
    // User time stretch allows independent speed control (0.5 = half speed, 2.0 = double speed)
    const float userTimeStretch = timeStretch_.load(std::memory_order_acquire);
    const float timeStretchRatio = pitchRatio * userTimeStretch;
    const int tsAccumSize = timeStretchAccum_.getNumSamples();
    
    int readStart = inputWritePos_ - fftSize_;
    if (readStart < 0) readStart += ringSize;

    for (int ch = 0; ch < numChannels_; ++ch) {
        const auto uch = static_cast<size_t>(ch);

        // Window and FFT
        std::fill(fftWorkBuffer_.begin(), fftWorkBuffer_.end(), 0.0f);
        for (int n = 0; n < fftSize_; ++n) {
            const int pos = (readStart + n) % ringSize;
            fftWorkBuffer_[static_cast<size_t>(n)] =
                inputRing_.getSample(ch, pos) * window_[static_cast<size_t>(n)];
        }

        fft_->performRealOnlyForwardTransform(fftWorkBuffer_.data(), false);

        // Analysis
        for (int bin = 0; bin < numBins; ++bin) {
            const auto ubin = static_cast<size_t>(bin);
            const float re = fftWorkBuffer_[ubin * 2];
            const float im = fftWorkBuffer_[ubin * 2 + 1];

            const float mag = std::sqrt(re * re + im * im);
            const float phase = std::atan2(im, re);

            const float omega = static_cast<float>(bin) * omegaFactor;
            const float rawDiff = phase - prevAnalysisPhase_[uch][ubin];
            const float deviation = princarg(rawDiff - omega);
            const float instFreq = omega + deviation;

            prevAnalysisPhase_[uch][ubin] = phase;
            analysisMag_[ubin] = mag;
            analysisFreq_[ubin] = instFreq;
        }

        // Synthesis with time-stretch: scale phase advance
        std::fill(fftWorkBuffer_.begin(), fftWorkBuffer_.end(), 0.0f);

        for (int bin = 0; bin < numBins; ++bin) {
            const auto ubin = static_cast<size_t>(bin);
            const float mag = analysisMag_[ubin];
            
            // Scale phase advance by timeStretchRatio
            const float phaseAdvance = timeStretchRatio * analysisFreq_[ubin];
            synthPhaseAccum_[uch][ubin] += phaseAdvance;

            if (mag < 1e-6f) {
                synthPhaseAccum_[uch][ubin] = princarg(synthPhaseAccum_[uch][ubin]);
            }

            const float phase = synthPhaseAccum_[uch][ubin];
            fftWorkBuffer_[ubin * 2]     = mag * std::cos(phase);
            fftWorkBuffer_[ubin * 2 + 1] = mag * std::sin(phase);
        }

        fft_->performRealOnlyInverseTransform(fftWorkBuffer_.data());

        // Overlap-add to time-stretch accumulator
        // The synthesis hop is hopSize_ * timeStretchRatio
        const float hopGain = overlapAddNorm_ / std::sqrt(timeStretchRatio);
        for (int n = 0; n < fftSize_; ++n) {
            const int outPos = (tsWritePos_ + n) % tsAccumSize;
            const float sample = fftWorkBuffer_[static_cast<size_t>(n)]
                               * window_[static_cast<size_t>(n)]
                               * hopGain;
            const float existing = timeStretchAccum_.getSample(ch, outPos);
            timeStretchAccum_.setSample(ch, outPos, existing + sample);
        }
    }

    // Advance write position by synthesis hop (time-stretched)
    tsWritePos_ = (tsWritePos_ + static_cast<int>(hopSize_ * timeStretchRatio)) % tsAccumSize;
}

} // namespace dsp_primitives

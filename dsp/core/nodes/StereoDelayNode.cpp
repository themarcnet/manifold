#include "StereoDelayNode.h"
#include <cmath>
#include <algorithm>

namespace dsp_primitives {

namespace {
    inline float clamp(float x, float min, float max) {
        return x < min ? min : (x > max ? max : x);
    }
    
    inline float lerp(float a, float b, float t) {
        return a + (b - a) * t;
    }
    
    inline float processOnePole(float input, float& z, float g) {
        float v = (input - z) * g;
        float y = v + z;
        z = y + v;
        return y;
    }
}

StereoDelayNode::StereoDelayNode() 
    : bufferSize_(0)
    , writeIndex_(0)
    , readIndexL_(0.0f)
    , readIndexR_(0.0f)
    , filterG_(0.0f)
    , filterK_(0.0f)
    , duckEnvelope_(1.0f)
    , sampleRate_(44100.0)
    , prepared_(false) {
}

void StereoDelayNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    updateBufferSize();
    
    // Calculate smoothing coefficients
    // Time params: 20ms, others: 10ms
    const double timeSmoothSeconds = 0.02;
    const double otherSmoothSeconds = 0.01;
    
    timeSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (timeSmoothSeconds * sampleRate_)));
    feedbackSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (otherSmoothSeconds * sampleRate_)));
    filterSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (otherSmoothSeconds * sampleRate_)));
    mixSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (otherSmoothSeconds * sampleRate_)));
    widthSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (otherSmoothSeconds * sampleRate_)));
    duckingSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (otherSmoothSeconds * sampleRate_)));
    
    timeSmoothingCoeff_ = clamp(timeSmoothingCoeff_, 0.0001f, 1.0f);
    feedbackSmoothingCoeff_ = clamp(feedbackSmoothingCoeff_, 0.0001f, 1.0f);
    filterSmoothingCoeff_ = clamp(filterSmoothingCoeff_, 0.0001f, 1.0f);
    mixSmoothingCoeff_ = clamp(mixSmoothingCoeff_, 0.0001f, 1.0f);
    widthSmoothingCoeff_ = clamp(widthSmoothingCoeff_, 0.0001f, 1.0f);
    duckingSmoothingCoeff_ = clamp(duckingSmoothingCoeff_, 0.0001f, 1.0f);
    
    // Initialize current values from targets
    currentTimeL_ = targetTimeL_.load(std::memory_order_acquire);
    currentTimeR_ = targetTimeR_.load(std::memory_order_acquire);
    currentFeedback_ = targetFeedback_.load(std::memory_order_acquire);
    currentFeedbackCrossfeed_ = targetFeedbackCrossfeed_.load(std::memory_order_acquire);
    currentFilterCutoff_ = targetFilterCutoff_.load(std::memory_order_acquire);
    currentFilterResonance_ = targetFilterResonance_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentWidth_ = targetWidth_.load(std::memory_order_acquire);
    currentDucking_ = targetDucking_.load(std::memory_order_acquire);
    
    // Initialize filter coefficients
    filterG_ = std::tan(3.14159265f * currentFilterCutoff_ / static_cast<float>(sampleRate_));
    filterK_ = 1.0f / std::max(0.01f, currentFilterResonance_ * 2.0f);
    
    prepared_ = true;
}

void StereoDelayNode::process(const std::vector<AudioBufferView>& inputs,
                              std::vector<WritableAudioBufferView>& outputs,
                              int numSamples) {
    if (!prepared_ || outputs.empty() || bufferSize_ <= 1) {
        if (!inputs.empty() && !outputs.empty()) {
            int inCh = inputs[0].numChannels;
            int outCh = outputs[0].numChannels;
            for (int ch = 0; ch < std::min(inCh, outCh); ++ch) {
                for (int i = 0; i < numSamples; ++i) {
                    outputs[0].setSample(ch, i, inputs[0].getSample(ch, i));
                }
            }
        }
        return;
    }

    int inChannels = inputs.empty() ? 0 : inputs[0].numChannels;
    int outChannels = outputs.empty() ? 0 : outputs[0].numChannels;
    const int channels = std::max(1, std::min(std::min(inChannels, outChannels), 2));

    const TimeMode mode = timeMode_.load(std::memory_order_acquire);
    const bool pingPong = pingPong_.load(std::memory_order_acquire);
    const bool freeze = freeze_.load(std::memory_order_acquire);
    const bool filterOn = filterEnabled_.load(std::memory_order_acquire);

    // Load target parameters
    const float targetTimeL = targetTimeL_.load(std::memory_order_acquire);
    const float targetTimeR = targetTimeR_.load(std::memory_order_acquire);
    const float targetFeedback = clamp(targetFeedback_.load(std::memory_order_acquire), 0.0f, 1.2f);
    const float targetCrossfeed = clamp(targetFeedbackCrossfeed_.load(std::memory_order_acquire), 0.0f, 1.0f);
    const float targetMix = clamp(targetMix_.load(std::memory_order_acquire), 0.0f, 1.0f);
    const float targetWidth = clamp(targetWidth_.load(std::memory_order_acquire), 0.0f, 1.0f);
    const float targetDucking = clamp(targetDucking_.load(std::memory_order_acquire), 0.0f, 1.0f);
    const float targetFilterCutoff = targetFilterCutoff_.load(std::memory_order_acquire);
    const float targetFilterResonance = targetFilterResonance_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        // Smooth parameters toward targets
        currentTimeL_ += (targetTimeL - currentTimeL_) * timeSmoothingCoeff_;
        currentTimeR_ += (targetTimeR - currentTimeR_) * timeSmoothingCoeff_;
        currentFeedback_ += (targetFeedback - currentFeedback_) * feedbackSmoothingCoeff_;
        currentFeedbackCrossfeed_ += (targetCrossfeed - currentFeedbackCrossfeed_) * feedbackSmoothingCoeff_;
        currentMix_ += (targetMix - currentMix_) * mixSmoothingCoeff_;
        currentWidth_ += (targetWidth - currentWidth_) * widthSmoothingCoeff_;
        currentDucking_ += (targetDucking - currentDucking_) * duckingSmoothingCoeff_;
        currentFilterCutoff_ += (targetFilterCutoff - currentFilterCutoff_) * filterSmoothingCoeff_;
        currentFilterResonance_ += (targetFilterResonance - currentFilterResonance_) * filterSmoothingCoeff_;
        
        // Update filter coefficients from smoothed values
        filterG_ = std::tan(3.14159265f * currentFilterCutoff_ / static_cast<float>(sampleRate_));
        filterK_ = 1.0f / std::max(0.01f, currentFilterResonance_ * 2.0f);
        
        // Calculate delay in samples from smoothed times
        float delaySamplesL, delaySamplesR;
        if (mode == TimeMode::Synced) {
            delaySamplesL = divisionToSamples(divisionL_.load(std::memory_order_acquire));
            delaySamplesR = divisionToSamples(divisionR_.load(std::memory_order_acquire));
        } else {
            delaySamplesL = currentTimeL_ * 0.001f * static_cast<float>(sampleRate_);
            delaySamplesR = currentTimeR_ * 0.001f * static_cast<float>(sampleRate_);
        }
        delaySamplesL = clamp(delaySamplesL, 1.0f, static_cast<float>(bufferSize_ - 1));
        delaySamplesR = clamp(delaySamplesR, 1.0f, static_cast<float>(bufferSize_ - 1));
        
        // Ping-pong: swap the delay times
        if (pingPong) {
            std::swap(delaySamplesL, delaySamplesR);
        }

        // Calculate read position directly from write position and delay time
        float readPosL = static_cast<float>(writeIndex_) - delaySamplesL;
        float readPosR = static_cast<float>(writeIndex_) - delaySamplesR;
        
        // Wrap to buffer
        while (readPosL < 0) readPosL += bufferSize_;
        while (readPosR < 0) readPosR += bufferSize_;
        
        // Integer and fractional parts for interpolation
        int idxL = static_cast<int>(readPosL) % bufferSize_;
        int idxR = static_cast<int>(readPosR) % bufferSize_;
        float fracL = readPosL - static_cast<float>(idxL);
        float fracR = readPosR - static_cast<float>(idxR);
        
        int nextL = (idxL + 1) % bufferSize_;
        int nextR = (idxR + 1) % bufferSize_;
        
        float s0L = delayBuffer_.getSample(0, idxL);
        float s1L = delayBuffer_.getSample(0, nextL);
        float s0R = delayBuffer_.getSample(1, idxR);
        float s1R = delayBuffer_.getSample(1, nextR);
        
        float delayL = lerp(s0L, s1L, fracL);
        float delayR = lerp(s0R, s1R, fracR);

        // Get input
        float inputL = inputs.empty() ? 0.0f : inputs[0].getSample(0, i);
        float inputR = inputs.empty() || channels < 2 ? inputL : inputs[0].getSample(1, i);

        // Ducking: detect input level and reduce delay volume
        if (currentDucking_ > 0.0f) {
            float inputLevel = (std::abs(inputL) + std::abs(inputR)) * 0.5f;
            float targetDuckEnv = inputLevel > 0.01f ? (1.0f - currentDucking_) : 1.0f;
            duckEnvelope_ = lerp(targetDuckEnv, duckEnvelope_, inputLevel > 0.01f ? kDuckAttack : kDuckRelease);
            delayL *= duckEnvelope_;
            delayR *= duckEnvelope_;
        }

        // Output mixing with width control
        float outL, outR;
        if (currentWidth_ < 1.0f) {
            float mono = (delayL + delayR) * 0.5f;
            delayL = lerp(mono, delayL, currentWidth_);
            delayR = lerp(mono, delayR, currentWidth_);
        }
        
        outL = inputL * (1.0f - currentMix_) + delayL * currentMix_;
        outR = inputR * (1.0f - currentMix_) + delayR * currentMix_;
        
        outputs[0].setSample(0, i, outL);
        if (channels > 1) outputs[0].setSample(1, i, outR);

        // Feedback path
        float fbL = delayL;
        float fbR = delayR;
        
        // Crossfeed for ping-pong or stereo width
        if (currentFeedbackCrossfeed_ > 0.0f || pingPong) {
            float newL = fbL * (1.0f - currentFeedbackCrossfeed_) + fbR * currentFeedbackCrossfeed_;
            float newR = fbR * (1.0f - currentFeedbackCrossfeed_) + fbL * currentFeedbackCrossfeed_;
            fbL = newL;
            fbR = newR;
        }
        
        // Filter in feedback path
        if (filterOn) {
            processFilter(fbL, fbR);
        }
        
        // Apply feedback
        fbL *= currentFeedback_;
        fbR *= currentFeedback_;
        
        // Write to delay buffer: feedback + dry input
        float dryL = inputL * 0.7f;
        float dryR = inputR * 0.7f;
        float writeL = freeze ? fbL : (fbL + dryL);
        float writeR = freeze ? fbR : (fbR + dryR);
        
        delayBuffer_.setSample(0, writeIndex_, writeL);
        delayBuffer_.setSample(1, writeIndex_, writeR);
        
        writeIndex_++;
        if (writeIndex_ >= bufferSize_) writeIndex_ = 0;
    }
}

void StereoDelayNode::updateBufferSize() {
    int newSize = static_cast<int>(sampleRate_ * kMaxDelaySeconds);
    if (newSize < 1024) newSize = 1024;
    if (newSize != bufferSize_) {
        bufferSize_ = newSize;
        delayBuffer_.setSize(2, bufferSize_, false, true, true);
        delayBuffer_.clear();
        writeIndex_ = 0;
        readIndexL_ = 0.0f;
        readIndexR_ = 0.0f;
        stateL_ = ChannelState{};
        stateR_ = ChannelState{};
    }
}

float StereoDelayNode::divisionToSamples(Division div) const {
    float beats = 1.0f;
    switch (div) {
        case Division::ThirtySecond: beats = 0.125f; break;
        case Division::Sixteenth: beats = 0.25f; break;
        case Division::Eighth: beats = 0.5f; break;
        case Division::Quarter: beats = 1.0f; break;
        case Division::Half: beats = 2.0f; break;
        case Division::Whole: beats = 4.0f; break;
        case Division::DottedEighth: beats = 0.75f; break;
        case Division::DottedQuarter: beats = 1.5f; break;
        case Division::TripletSixteenth: beats = 0.166666f; break;
        case Division::TripletEighth: beats = 0.333333f; break;
        case Division::TripletQuarter: beats = 0.666666f; break;
        case Division::NumDivisions: beats = 1.0f; break;
    }
    
    float tempo = tempo_.load(std::memory_order_acquire);
    if (tempo <= 0.0f) tempo = 120.0f;
    
    return beats * 60.0f / tempo * static_cast<float>(sampleRate_);
}

void StereoDelayNode::processFilter(float& sampleL, float& sampleR) {
    sampleL = processOnePole(sampleL, stateL_.filterZ1, filterG_);
    sampleR = processOnePole(sampleR, stateR_.filterZ1, filterG_);
}

// Setters - write to targets
void StereoDelayNode::setTimeMode(TimeMode mode) { timeMode_.store(mode, std::memory_order_release); }
void StereoDelayNode::setTimeL(float ms) { targetTimeL_.store(clamp(ms, 1.0f, 5000.0f), std::memory_order_release); }
void StereoDelayNode::setTimeR(float ms) { targetTimeR_.store(clamp(ms, 1.0f, 5000.0f), std::memory_order_release); }
void StereoDelayNode::setDivisionL(Division div) { divisionL_.store(div, std::memory_order_release); }
void StereoDelayNode::setDivisionR(Division div) { divisionR_.store(div, std::memory_order_release); }
void StereoDelayNode::setFeedback(float fb) { targetFeedback_.store(clamp(fb, 0.0f, 1.2f), std::memory_order_release); }
void StereoDelayNode::setFeedbackCrossfeed(float cf) { targetFeedbackCrossfeed_.store(clamp(cf, 0.0f, 1.0f), std::memory_order_release); }
void StereoDelayNode::setFilterEnabled(bool on) { filterEnabled_.store(on, std::memory_order_release); }
void StereoDelayNode::setFilterCutoff(float freq) { targetFilterCutoff_.store(clamp(freq, 20.0f, 20000.0f), std::memory_order_release); }
void StereoDelayNode::setFilterResonance(float res) { targetFilterResonance_.store(clamp(res, 0.0f, 1.0f), std::memory_order_release); }
void StereoDelayNode::setMix(float wet) { targetMix_.store(clamp(wet, 0.0f, 1.0f), std::memory_order_release); }
void StereoDelayNode::setPingPong(bool on) { pingPong_.store(on, std::memory_order_release); }
void StereoDelayNode::setWidth(float w) { targetWidth_.store(clamp(w, 0.0f, 1.0f), std::memory_order_release); }
void StereoDelayNode::setFreeze(bool on) { freeze_.store(on, std::memory_order_release); }
void StereoDelayNode::setDucking(float d) { targetDucking_.store(clamp(d, 0.0f, 1.0f), std::memory_order_release); }
void StereoDelayNode::setTempo(float bpm) { tempo_.store(clamp(bpm, 20.0f, 300.0f), std::memory_order_release); }

// Getters - read from targets
StereoDelayNode::TimeMode StereoDelayNode::getTimeMode() const { return timeMode_.load(std::memory_order_acquire); }
float StereoDelayNode::getTimeL() const { return targetTimeL_.load(std::memory_order_acquire); }
float StereoDelayNode::getTimeR() const { return targetTimeR_.load(std::memory_order_acquire); }
StereoDelayNode::Division StereoDelayNode::getDivisionL() const { return divisionL_.load(std::memory_order_acquire); }
StereoDelayNode::Division StereoDelayNode::getDivisionR() const { return divisionR_.load(std::memory_order_acquire); }
float StereoDelayNode::getFeedback() const { return targetFeedback_.load(std::memory_order_acquire); }
float StereoDelayNode::getFeedbackCrossfeed() const { return targetFeedbackCrossfeed_.load(std::memory_order_acquire); }
bool StereoDelayNode::getFilterEnabled() const { return filterEnabled_.load(std::memory_order_acquire); }
float StereoDelayNode::getFilterCutoff() const { return targetFilterCutoff_.load(std::memory_order_acquire); }
float StereoDelayNode::getFilterResonance() const { return targetFilterResonance_.load(std::memory_order_acquire); }
float StereoDelayNode::getMix() const { return targetMix_.load(std::memory_order_acquire); }
bool StereoDelayNode::getPingPong() const { return pingPong_.load(std::memory_order_acquire); }
float StereoDelayNode::getWidth() const { return targetWidth_.load(std::memory_order_acquire); }
bool StereoDelayNode::getFreeze() const { return freeze_.load(std::memory_order_acquire); }
float StereoDelayNode::getDucking() const { return targetDucking_.load(std::memory_order_acquire); }

void StereoDelayNode::reset() {
    delayBuffer_.clear();
    writeIndex_ = 0;
    readIndexL_ = 0.0f;
    readIndexR_ = 0.0f;
    stateL_ = ChannelState{};
    stateR_ = ChannelState{};
    duckEnvelope_ = 1.0f;
}

} // namespace dsp_primitives

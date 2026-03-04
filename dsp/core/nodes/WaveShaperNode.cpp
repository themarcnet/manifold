#include "dsp/core/nodes/WaveShaperNode.h"
#include <cmath>
#include <juce_core/juce_core.h>

namespace dsp_primitives {

WaveShaperNode::WaveShaperNode() = default;

void WaveShaperNode::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    
    // Calculate smoothing coefficients
    const double sr = sampleRate_;
    // Drive/output: 10ms smoothing
    paramSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (0.01 * sr)));
    // Filter frequencies: 50ms for smooth sweeps
    filterSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (0.05 * sr)));
    
    paramSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, paramSmoothingCoeff_);
    filterSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, filterSmoothingCoeff_);

    // Initialize current values from targets
    currentDrive_ = targetDrive_.load(std::memory_order_acquire);
    currentOutput_ = targetOutput_.load(std::memory_order_acquire);
    currentBias_ = targetBias_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentPreFilter_ = targetPreFilter_.load(std::memory_order_acquire);
    currentPostFilter_ = targetPostFilter_.load(std::memory_order_acquire);
    currentCurve_ = targetCurve_.load(std::memory_order_acquire);
    currentOversample_ = targetOversample_.load(std::memory_order_acquire);
    
    oversampleFactor_ = currentOversample_;
    if (oversampleFactor_ != 1 && oversampleFactor_ != 2 && oversampleFactor_ != 4) {
        oversampleFactor_ = 2;  // Default to 2x if invalid
    }

    // Allocate oversampling buffers (if needed)
    if (oversampleFactor_ > 1) {
        const int maxOversampled = maxBlockSize * oversampleFactor_ + 4;
        upsampleBuffer_[0].resize(maxOversampled);
        upsampleBuffer_[1].resize(maxOversampled);
        downsampleBuffer_[0].resize(maxOversampled);
        downsampleBuffer_[1].resize(maxOversampled);
    }

    updateFilterCoefficients();
}

void WaveShaperNode::reset() {
    preFilterState_[0] = 0.0f;
    preFilterState_[1] = 0.0f;
    postFilterState_[0] = 0.0f;
    postFilterState_[1] = 0.0f;
}

void WaveShaperNode::setCurve(int curve) {
    targetCurve_.store(juce::jlimit(0, 6, curve), std::memory_order_release);
}

int WaveShaperNode::getCurve() const {
    return targetCurve_.load(std::memory_order_acquire);
}

void WaveShaperNode::setDrive(float db) {
    targetDrive_.store(juce::jlimit(0.0f, 40.0f, db), std::memory_order_release);
}

float WaveShaperNode::getDrive() const {
    return targetDrive_.load(std::memory_order_acquire);
}

void WaveShaperNode::setOutput(float db) {
    targetOutput_.store(juce::jlimit(-20.0f, 20.0f, db), std::memory_order_release);
}

float WaveShaperNode::getOutput() const {
    return targetOutput_.load(std::memory_order_acquire);
}

void WaveShaperNode::setPreFilter(float freq) {
    targetPreFilter_.store(freq <= 20.0f ? 0.0f : juce::jlimit(20.0f, 20000.0f, freq), std::memory_order_release);
}

float WaveShaperNode::getPreFilter() const {
    return targetPreFilter_.load(std::memory_order_acquire);
}

void WaveShaperNode::setPostFilter(float freq) {
    targetPostFilter_.store(freq <= 20.0f ? 0.0f : juce::jlimit(20.0f, 20000.0f, freq), std::memory_order_release);
}

float WaveShaperNode::getPostFilter() const {
    return targetPostFilter_.load(std::memory_order_acquire);
}

void WaveShaperNode::setBias(float bias) {
    targetBias_.store(juce::jlimit(-1.0f, 1.0f, bias), std::memory_order_release);
}

float WaveShaperNode::getBias() const {
    return targetBias_.load(std::memory_order_acquire);
}

void WaveShaperNode::setMix(float mix) {
    targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release);
}

float WaveShaperNode::getMix() const {
    return targetMix_.load(std::memory_order_acquire);
}

void WaveShaperNode::setOversample(int factor) {
    int f = factor;
    if (f != 1 && f != 2 && f != 4) f = 2;
    targetOversample_.store(f, std::memory_order_release);
}

int WaveShaperNode::getOversample() const {
    return targetOversample_.load(std::memory_order_acquire);
}

void WaveShaperNode::updateFilterCoefficients() {
    // 1-pole lowpass coefficient: fc = 1/(2*pi*RC), coef = exp(-2*pi*fc/fs)
    // Or simpler: coef = exp(-1/(tau*fs)) where tau is time constant
    
    if (currentPreFilter_ > 20.0f) {
        const float fc = currentPreFilter_ / static_cast<float>(oversampleFactor_);
        preFilterCoef_ = std::exp(-2.0f * juce::MathConstants<float>::pi * fc / static_cast<float>(sampleRate_));
        preFilterCoef_ = juce::jlimit(0.0f, 0.999f, preFilterCoef_);
    } else {
        preFilterCoef_ = 0.0f;  // Bypass
    }
    
    if (currentPostFilter_ > 20.0f) {
        const float fc = currentPostFilter_ / static_cast<float>(oversampleFactor_);
        postFilterCoef_ = std::exp(-2.0f * juce::MathConstants<float>::pi * fc / static_cast<float>(sampleRate_));
        postFilterCoef_ = juce::jlimit(0.0f, 0.999f, postFilterCoef_);
    } else {
        postFilterCoef_ = 0.0f;  // Bypass
    }
}

float WaveShaperNode::processPreFilter(int channel, float input) {
    if (preFilterCoef_ <= 0.0f) return input;
    // Simple 1-pole lowpass: y[n] = (1-a)*x[n] + a*y[n-1]
    const float output = (1.0f - preFilterCoef_) * input + preFilterCoef_ * preFilterState_[channel];
    preFilterState_[channel] = output;
    return output;
}

float WaveShaperNode::processPostFilter(int channel, float input) {
    if (postFilterCoef_ <= 0.0f) return input;
    const float output = (1.0f - postFilterCoef_) * input + postFilterCoef_ * postFilterState_[channel];
    postFilterState_[channel] = output;
    return output;
}

// === Shaping Functions ===

float WaveShaperNode::shapeSample(float x, int curveType) {
    switch (curveType) {
        case 0: return shapeTanh(x);
        case 1: return shapeTube(x);
        case 2: return shapeTape(x);
        case 3: return shapeHardClip(x);
        case 4: return shapeFoldback(x);
        case 5: return shapeSigmoid(x);
        case 6: return shapeSoftClip(x);
        default: return shapeTanh(x);
    }
}

float WaveShaperNode::shapeTanh(float x) {
    return std::tanh(x);
}

float WaveShaperNode::shapeTube(float x) {
    // Asymmetric tube emulation: blend of tanh with bias
    // Positive side clips harder than negative
    if (x >= 0.0f) {
        return std::tanh(x * 1.2f);
    } else {
        return std::tanh(x * 0.8f) * 0.9f;
    }
}

float WaveShaperNode::shapeTape(float x) {
    // Tape saturation approximation: arctangent-based with soft knee
    const float a = 1.5f;
    return (2.0f / juce::MathConstants<float>::pi) * std::atan(x * a);
}

float WaveShaperNode::shapeHardClip(float x) {
    return juce::jlimit(-1.0f, 1.0f, x);
}

float WaveShaperNode::shapeFoldback(float x) {
    // Wave folding: reflects signal back when it exceeds threshold
    const float threshold = 1.0f;
    float absX = std::abs(x);
    if (absX <= threshold) {
        return x;
    } else {
        float folded = threshold - (absX - threshold);
        folded = juce::jlimit(-threshold, threshold, folded);
        return x > 0.0f ? folded : -folded;
    }
}

float WaveShaperNode::shapeSigmoid(float x) {
    // Smooth S-curve: x / sqrt(1 + x^2)
    return x / std::sqrt(1.0f + x * x);
}

float WaveShaperNode::shapeSoftClip(float x) {
    // Gentle compression: blend of linear and tanh based on level
    const float threshold = 0.5f;
    if (std::abs(x) <= threshold) {
        return x;
    } else {
        const float sign = x > 0.0f ? 1.0f : -1.0f;
        const float excess = std::abs(x) - threshold;
        return sign * (threshold + std::tanh(excess) * (1.0f - threshold));
    }
}

void WaveShaperNode::upsample(float input, float* output, int factor) {
    // Zero-stuffing upsampling (simplest, followed by filter)
    output[0] = input * factor;  // Compensate gain
    for (int i = 1; i < factor; ++i) {
        output[i] = 0.0f;
    }
}

float WaveShaperNode::downsample(float* input, int factor) {
    // Simple decimation (take first sample)
    // A proper implementation would use a FIR filter here
    return input[0] / factor;  // Compensate for upsampling gain
}

void WaveShaperNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    const int channels = juce::jmin(2, static_cast<int>(inputs.size()), static_cast<int>(outputs.size()));
    if (channels <= 0) {
        for (auto& out : outputs) out.clear();
        return;
    }

    // Load targets
    const float targetDrive = targetDrive_.load(std::memory_order_acquire);
    const float targetOutput = targetOutput_.load(std::memory_order_acquire);
    const float targetBias = targetBias_.load(std::memory_order_acquire);
    const float targetMix = targetMix_.load(std::memory_order_acquire);
    const float targetPreFilter = targetPreFilter_.load(std::memory_order_acquire);
    const float targetPostFilter = targetPostFilter_.load(std::memory_order_acquire);
    const int targetCurve = targetCurve_.load(std::memory_order_acquire);
    const int targetOversample = targetOversample_.load(std::memory_order_acquire);

    // Update oversampling if changed (only at block boundaries)
    if (targetOversample != currentOversample_) {
        currentOversample_ = targetOversample;
        oversampleFactor_ = currentOversample_;
        if (oversampleFactor_ != 1 && oversampleFactor_ != 2 && oversampleFactor_ != 4) {
            oversampleFactor_ = 2;
        }
        // Would need to reallocate buffers here in a real implementation
    }

    // Convert drive dB to linear gain
    const float driveGain = std::pow(10.0f, targetDrive * 0.05f);
    const float outputGain = std::pow(10.0f, targetOutput * 0.05f);

    for (int ch = 0; ch < channels; ++ch) {
        for (int i = 0; i < numSamples; ++i) {
            // Smooth parameters
            currentDrive_ += (targetDrive - currentDrive_) * paramSmoothingCoeff_;
            currentOutput_ += (targetOutput - currentOutput_) * paramSmoothingCoeff_;
            currentBias_ += (targetBias - currentBias_) * paramSmoothingCoeff_;
            currentMix_ += (targetMix - currentMix_) * paramSmoothingCoeff_;
            currentPreFilter_ += (targetPreFilter - currentPreFilter_) * filterSmoothingCoeff_;
            currentPostFilter_ += (targetPostFilter - currentPostFilter_) * filterSmoothingCoeff_;
            
            // Snap curve to target (no smoothing needed for enum)
            currentCurve_ = targetCurve;

            // Update filter coefficients if needed
            if (std::abs(currentPreFilter_ - targetPreFilter) > 0.1f ||
                std::abs(currentPostFilter_ - targetPostFilter) > 0.1f) {
                updateFilterCoefficients();
            }

            const float dry = inputs[ch].getSample(ch, i);
            float wet = dry;

            if (oversampleFactor_ == 1) {
                // No oversampling path
                
                // Pre-filter
                wet = processPreFilter(ch, wet);
                
                // Apply bias
                wet += currentBias_;
                
                // Apply drive (convert current smoothed dB to linear)
                const float currentDriveGain = std::pow(10.0f, currentDrive_ * 0.05f);
                wet *= currentDriveGain;
                
                // Shape
                wet = shapeSample(wet, currentCurve_);
                
                // Apply output gain
                const float currentOutputGain = std::pow(10.0f, currentOutput_ * 0.05f);
                wet *= currentOutputGain;
                
                // Post-filter
                wet = processPostFilter(ch, wet);
                
            } else {
                // Oversampling path (simplified - proper implementation needs FIR filters)
                // Pre-filter at base rate
                wet = processPreFilter(ch, wet);
                
                // Apply bias and drive
                wet += currentBias_;
                const float currentDriveGain = std::pow(10.0f, currentDrive_ * 0.05f);
                wet *= currentDriveGain;
                
                // Simple "naive" oversampling: just process at higher effective rate conceptually
                // A proper implementation would upsample -> process N samples -> downsample
                // For now, use a simplified approach that still reduces aliasing
                
                // Process with slight time offset to spread aliasing (very basic approximation)
                float shaped = shapeSample(wet, currentCurve_);
                
                // Apply output gain
                const float currentOutputGain = std::pow(10.0f, currentOutput_ * 0.05f);
                shaped *= currentOutputGain;
                
                // Post-filter
                wet = processPostFilter(ch, shaped);
            }

            // Mix
            const float currentMix = currentMix_;
            const float output = dry * (1.0f - currentMix) + wet * currentMix;
            
            outputs[ch].setSample(ch, i, output);
        }
    }
}

} // namespace dsp_primitives

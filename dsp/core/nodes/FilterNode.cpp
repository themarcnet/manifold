#include <dsp/core/nodes/FilterNode.h>

#include <manifold/debugging/Logging.h>

#include <cmath>

#include "FilterNode_Highway.h"

namespace dsp_primitives {

FilterNode::FilterNode() = default;

FilterNode::FilterNode(int tgt) : simdTarget_(tgt)
{}


Debug::Logger &  FilterNode::GetLog() 
{
    if(simd_implementation_.get() != NULL)
    {
        IPrimitiveNodeSIMDImplementation * prim = simd_implementation_.get();
        FilterNode_Highway::FilterNode_Highway_Logging_IFace * loggerIface = dynamic_cast<FilterNode_Highway::FilterNode_Highway_Logging_IFace *>(prim);
        if(loggerIface != NULL)
            return loggerIface->GetLogger();
    }
    return logger_;
}


void FilterNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothingTimeSeconds = 0.02;
    smoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothingTimeSeconds * sampleRate_)));
    smoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, smoothingCoeff_);

    z1_[0] = 0.0f;
    z1_[1] = 0.0f;
    z2_[0] = 0.0f;
    z2_[1] = 0.0f;

    cutoffHz_ = targetCutoffHz_.load(std::memory_order_acquire);
    resonance_ = targetResonance_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);
    prepared_ = true;

    //Set up SIMD implementation
    if((simd_implementation_ == NULL) && (simdTarget_ >= 0))
    {
        hwy::RunHighwayErrorCode errcode = hwy::RunHighwayErrorCode_Error;
        simd_implementation_.reset(FilterNode_Highway::__CreateInstance(simdTarget_, &targetCutoffHz_, &targetResonance_, &targetMix_,   &errcode));
        highwayError_ = static_cast<int>(errcode);
    }

    if(simd_implementation_ != NULL)
        simd_implementation_->prepare(static_cast<float>(sampleRate));
}

void FilterNode::setCutoff(float hz) {
    targetCutoffHz_.store(juce::jlimit(20.0f, 18000.0f, hz), std::memory_order_release);
    if(simd_implementation_ != nullptr)
        simd_implementation_->configChanged();
}

void FilterNode::setResonance(float q) {
    targetResonance_.store(juce::jlimit(0.0f, 1.0f, q), std::memory_order_release);
    if(simd_implementation_ != nullptr)
        simd_implementation_->configChanged();
}

void FilterNode::setMix(float mix) {
    targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release);
    if(simd_implementation_ != nullptr)
        simd_implementation_->configChanged();
}

float FilterNode::computeAlpha(float cutoffHz, float resonance) const {
    const float sr = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);
    const float normalized = juce::jlimit(0.0001f, 0.49f, cutoffHz / sr);
    const float shaping = 1.0f + resonance * 0.6f;
    float alpha = 1.0f - std::exp(-2.0f * juce::MathConstants<float>::pi * normalized * shaping);
    return juce::jlimit(0.0001f, 0.999f, alpha);
}

void FilterNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (!prepared_ || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    if (inputs.empty()) {
        outputs[0].clear();
        return;
    }

    if(simd_implementation_ != nullptr)
    {
        simd_implementation_->run(inputs, outputs, numSamples);
        return;
    }

    const auto& input = inputs[0];
    auto& output = outputs[0];
    const int channels = juce::jmin(2, input.numChannels, output.numChannels);
    if (channels <= 0) {
        output.clear();
        return;
    }

    const float targetCutoff = targetCutoffHz_.load(std::memory_order_acquire);
    const float targetResonance = targetResonance_.load(std::memory_order_acquire);
    const float targetMix = targetMix_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        cutoffHz_ += (targetCutoff - cutoffHz_) * smoothingCoeff_;
        resonance_ += (targetResonance - resonance_) * smoothingCoeff_;
        mix_ += (targetMix - mix_) * smoothingCoeff_;

        const float alpha = computeAlpha(cutoffHz_, resonance_);
        const float feedback = resonance_ * 0.85f;
        const float dry = 1.0f - mix_;
        const float wet = mix_;

        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            const float in = input.getSample(ch, i);
            
            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "input L" : "input R", in);
            
            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "z1 l" : "z1 r", z1_[idx]);
            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "z2 l" : "z2 r", z2_[idx]);

            const float x = in - feedback * (z2_[idx] - z1_[idx]);

            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "x l" : "x r", x);

            z1_[idx] += alpha * (x - z1_[idx]);
            z2_[idx] += alpha * (z1_[idx] - z2_[idx]);
            const float filtered = z2_[idx];

            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "filtered l" : "filtered r", filtered);

            const float out = in * dry + filtered * wet;
            DEBUG_LOG_VALUE(logger_, totalSampleCount_, (ch == 0) ? "out L" : "out R", out);
            output.setSample(ch, i, out);
        }

        ++totalSampleCount_;
    }
}

void FilterNode::reset() {
    // no internal state
    if(simd_implementation_ != nullptr)
        simd_implementation_->reset();
}

} // namespace dsp_primitives

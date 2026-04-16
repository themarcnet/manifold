#include "BitCrusherNode.h"

#include <cmath>

#include "BitCrusherNode_Highway.h"

namespace dsp_primitives {

BitCrusherNode::BitCrusherNode() = default;

void BitCrusherNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;
    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    currentBits_ = targetBits_.load(std::memory_order_acquire);
    currentRateReduction_ = targetRateReduction_.load(std::memory_order_acquire);
    currentMix_ = targetMix_.load(std::memory_order_acquire);
    currentOutput_ = targetOutput_.load(std::memory_order_acquire);
    currentLogicMode_ = targetLogicMode_.load(std::memory_order_acquire);

    reset();

    //Set up SIMD implementation
    if(simd_implementation_ == NULL)
        simd_implementation_.reset(BitCrusherNode_Highway::__CreateInstance(static_cast<float>(sampleRate), &targetBits_, &targetRateReduction_, &targetMix_, &targetOutput_, &targetLogicMode_));
    
    simd_implementation_->prepare(static_cast<float>(sampleRate));

    prepared_ = true;
}

void BitCrusherNode::reset() {
    heldSample_[0] = 0.0f;
    heldSample_[1] = 0.0f;
    holdCounter_[0] = 0.0f;
    holdCounter_[1] = 0.0f;

    if(simd_implementation_ != NULL)
        simd_implementation_->reset();
}

void BitCrusherNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    if(simd_implementation_ != NULL)
    {
        simd_implementation_->run(inputs, outputs, numSamples);
        return;
    }

    const bool hasBusB = inputs.size() >= 3;

    const float tBits = targetBits_.load(std::memory_order_acquire);
    const float tRateReduction = targetRateReduction_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);
    const float tOutput = targetOutput_.load(std::memory_order_acquire);
    const int tLogicMode = targetLogicMode_.load(std::memory_order_acquire);

    auto quantizeToCode = [](float x, float levels) {
        const float clamped = juce::jlimit(-1.0f, 1.0f, x);
        const int maxCode = juce::jmax(1, static_cast<int>(levels * 2.0f) - 1);
        const int code = static_cast<int>(std::round(((clamped + 1.0f) * 0.5f) * static_cast<float>(maxCode)));
        return juce::jlimit(0, maxCode, code);
    };
    auto codeToFloat = [](int code, float levels) {
        const int maxCode = juce::jmax(1, static_cast<int>(levels * 2.0f) - 1);
        return (static_cast<float>(juce::jlimit(0, maxCode, code)) / static_cast<float>(maxCode)) * 2.0f - 1.0f;
    };

    for (int i = 0; i < numSamples; ++i) {
        currentBits_ += (tBits - currentBits_) * smooth_;
        currentRateReduction_ += (tRateReduction - currentRateReduction_) * smooth_;
        currentMix_ += (tMix - currentMix_) * smooth_;
        currentOutput_ += (tOutput - currentOutput_) * smooth_;
        currentLogicMode_ = tLogicMode;

        
        const float quantLevels = std::pow(2.0f, currentBits_ - 1.0f);
        const float holdInterval = juce::jmax(1.0f, currentRateReduction_);

        const float inAL = inputs[0].getSample(0, i);
        const float inAR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inAL;
        const float inBL = hasBusB ? inputs[2].getSample(0, i) : 0.0f;
        const float inBR = hasBusB ? (inputs[2].numChannels > 1 ? inputs[2].getSample(1, i) : inBL) : 0.0f;

        float outL = inAL;
        float outR = inAR;


        //printf("DEBUG: Sample:%d, heldL=%f heldR=%f holdCountL=%f (%f) holdCountR=%f (%f)   holdInterval=%f tbits=%f currentBits_=%f   tRateRed=%f  currentRateReduction_=%f   tMix=%f currentMix_=%f   tout=%f currentOutput_=%f currentLogicMode_=%d inAL=%f inAR=%f inBL=%f inBR=%f\n",
        //       i, heldSample_[0], heldSample_[1], holdCounter_[0], holdCounter_[0] + 1.0f,  holdCounter_[1], holdCounter_[1] + 1.0f, holdInterval, tBits, currentBits_, tRateReduction,currentRateReduction_, tMix, currentMix_, tOutput, currentOutput_, currentLogicMode_, inAL, inAR, inBL, inBR);


        for (int ch = 0; ch < 2; ++ch) {
            const float inA = ch == 0 ? inAL : inAR;
            const float inB = ch == 0 ? inBL : inBR;
            holdCounter_[static_cast<size_t>(ch)] += 1.0f;

            if (holdCounter_[static_cast<size_t>(ch)] >= holdInterval) {
                holdCounter_[static_cast<size_t>(ch)] -= holdInterval;

                
                float wet = 0.0f;
                if (currentLogicMode_ == 1 && hasBusB) {
                    // XOR: quantize both, XOR the codes, convert back.
                    // Use bipolar quantization so silence (0.0) XOR silence = 0.0.
                    const int qa = quantizeToCode(inA, quantLevels);
                    const int qb = quantizeToCode(inB, quantLevels);
                    const int midCode = juce::jmax(1, static_cast<int>(quantLevels * 2.0f) - 1) / 2;
                    // Offset codes to center around 0, XOR, then offset back
                    const int da = qa - midCode;
                    const int db = qb - midCode;
                    const int qx = (da ^ db) + midCode;
                    wet = codeToFloat(qx, quantLevels) * currentOutput_;

                    //printf("   DEBUG: LOGIC 1 : Channel %d hold counter %f at sample %d quant:%f newheld=%f qa=%d qb=%d qx=%d midCode=%d \n", ch, holdCounter_[static_cast<size_t>(ch)], i,quantLevels, wet,qa,qb,qx,midCode);

                } else if (currentLogicMode_ == 2 && hasBusB) {
                    // Gate/compare: use bus B amplitude to gate target A.
                    const float qa = std::round(inA * quantLevels) / quantLevels;
                    const bool gate = std::fabs(inB) > 0.001f;
                    wet = (gate ? qa : 0.0f) * currentOutput_;
                } else {
                    const float q = std::round(inA * quantLevels) / quantLevels;
                    wet = juce::jlimit(-1.0f, 1.0f, q) * currentOutput_;

                    //printf("   DEBUG: ELSE Channel %d hold counter %f at sample %d quant:%f newheld=%f \n", ch, holdCounter_[static_cast<size_t>(ch)], i,quantLevels, wet);
                }

                heldSample_[static_cast<size_t>(ch)] = wet;

                
            }

            const float wet = heldSample_[static_cast<size_t>(ch)];
            const float out = inA * (1.0f - currentMix_) + wet * currentMix_;

            if (ch == 0) outL = out;
            else outR = out;
        }

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }

    //printf("\n\n");
}

} // namespace dsp_primitives

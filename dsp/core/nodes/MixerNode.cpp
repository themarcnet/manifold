#include "dsp/core/nodes/MixerNode.h"

#include <cmath>

namespace dsp_primitives {

MixerNode::MixerNode() = default;

void MixerNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    const double sr = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sr)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    g1_ = targetGain1_.load(std::memory_order_acquire);
    g2_ = targetGain2_.load(std::memory_order_acquire);
    g3_ = targetGain3_.load(std::memory_order_acquire);
    g4_ = targetGain4_.load(std::memory_order_acquire);

    p1_ = targetPan1_.load(std::memory_order_acquire);
    p2_ = targetPan2_.load(std::memory_order_acquire);
    p3_ = targetPan3_.load(std::memory_order_acquire);
    p4_ = targetPan4_.load(std::memory_order_acquire);

    master_ = targetMaster_.load(std::memory_order_acquire);

    prepared_ = true;
}

void MixerNode::reset() {
    // no internal state
}

static inline void equalPowerPan(float pan, float& gainL, float& gainR) {
    const float t = 0.5f * (juce::jlimit(-1.0f, 1.0f, pan) + 1.0f);
    gainL = std::cos(0.5f * juce::MathConstants<float>::pi * t);
    gainR = std::sin(0.5f * juce::MathConstants<float>::pi * t);
}

void MixerNode::process(const std::vector<AudioBufferView>& inputs,
                        std::vector<WritableAudioBufferView>& outputs,
                        int numSamples) {
    if (!prepared_ || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    const float tg1 = targetGain1_.load(std::memory_order_acquire);
    const float tg2 = targetGain2_.load(std::memory_order_acquire);
    const float tg3 = targetGain3_.load(std::memory_order_acquire);
    const float tg4 = targetGain4_.load(std::memory_order_acquire);

    const float tp1 = targetPan1_.load(std::memory_order_acquire);
    const float tp2 = targetPan2_.load(std::memory_order_acquire);
    const float tp3 = targetPan3_.load(std::memory_order_acquire);
    const float tp4 = targetPan4_.load(std::memory_order_acquire);

    const float tMaster = targetMaster_.load(std::memory_order_acquire);

    for (int i = 0; i < numSamples; ++i) {
        g1_ += (tg1 - g1_) * smooth_;
        g2_ += (tg2 - g2_) * smooth_;
        g3_ += (tg3 - g3_) * smooth_;
        g4_ += (tg4 - g4_) * smooth_;

        p1_ += (tp1 - p1_) * smooth_;
        p2_ += (tp2 - p2_) * smooth_;
        p3_ += (tp3 - p3_) * smooth_;
        p4_ += (tp4 - p4_) * smooth_;

        master_ += (tMaster - master_) * smooth_;

        float outL = 0.0f;
        float outR = 0.0f;

        auto addBus = [&](int bus, float gain, float pan) {
            const int viewIndex = bus * 2;
            if (inputs.size() <= static_cast<size_t>(viewIndex)) {
                return;
            }

            const float inL = inputs[static_cast<size_t>(viewIndex)].getSample(0, i);
            const float inR = inputs[static_cast<size_t>(viewIndex)].numChannels > 1
                                  ? inputs[static_cast<size_t>(viewIndex)].getSample(1, i)
                                  : inL;

            float panL = 1.0f;
            float panR = 1.0f;
            equalPowerPan(pan, panL, panR);

            outL += inL * gain * panL;
            outR += inR * gain * panR;
        };

        addBus(0, g1_, p1_);
        addBus(1, g2_, p2_);
        addBus(2, g3_, p3_);
        addBus(3, g4_, p4_);

        outL *= master_;
        outR *= master_;

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }
}

} // namespace dsp_primitives

#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class FilterNode : public IPrimitiveNode, public std::enable_shared_from_this<FilterNode> {
public:
    FilterNode();

    const char* getNodeType() const override { return "Filter"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setCutoff(float hz);
    void setResonance(float q);
    void setMix(float mix);

    float getCutoff() const { return targetCutoffHz_.load(std::memory_order_acquire); }
    float getResonance() const { return targetResonance_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    float computeAlpha(float cutoffHz, float resonance) const;

    double sampleRate_ = 44100.0;
    float smoothingCoeff_ = 1.0f;

    std::atomic<float> targetCutoffHz_{1400.0f};
    std::atomic<float> targetResonance_{0.1f};
    std::atomic<float> targetMix_{1.0f};

    float cutoffHz_ = 1400.0f;
    float resonance_ = 0.1f;
    float mix_ = 1.0f;
    std::array<float, 2> z1_ {0.0f, 0.0f};
    std::array<float, 2> z2_ {0.0f, 0.0f};
};

} // namespace dsp_primitives

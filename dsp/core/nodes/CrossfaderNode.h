#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class CrossfaderNode : public IPrimitiveNode,
                      public std::enable_shared_from_this<CrossfaderNode> {
public:
    CrossfaderNode();

    const char* getNodeType() const override { return "Crossfader"; }
    // 2 stereo busses encoded as 4 input views (bus0 duplicated for ch0/ch1, bus1 duplicated)
    int getNumInputs() const override { return 4; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setPosition(float pos) { targetPosition_.store(juce::jlimit(-1.0f, 1.0f, pos), std::memory_order_release); }
    void setCurve(float curve) { targetCurve_.store(juce::jlimit(0.0f, 1.0f, curve), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getPosition() const { return targetPosition_.load(std::memory_order_acquire); }
    float getCurve() const { return targetCurve_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetPosition_{0.0f};
    std::atomic<float> targetCurve_{1.0f};
    std::atomic<float> targetMix_{1.0f};

    float currentPosition_ = 0.0f;
    float currentCurve_ = 1.0f;
    float currentMix_ = 1.0f;
    float smooth_ = 1.0f;

    bool prepared_ = false;
};

} // namespace dsp_primitives

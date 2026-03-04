#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>

namespace dsp_primitives {

class MixerNode : public IPrimitiveNode,
                  public std::enable_shared_from_this<MixerNode> {
public:
    MixerNode();

    const char* getNodeType() const override { return "Mixer"; }

    // 4 stereo busses encoded as 8 input views (bus0 duplicated for ch0/ch1, etc)
    int getNumInputs() const override { return 8; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setGain1(float g) { targetGain1_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }
    void setGain2(float g) { targetGain2_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }
    void setGain3(float g) { targetGain3_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }
    void setGain4(float g) { targetGain4_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }

    void setPan1(float p) { targetPan1_.store(juce::jlimit(-1.0f, 1.0f, p), std::memory_order_release); }
    void setPan2(float p) { targetPan2_.store(juce::jlimit(-1.0f, 1.0f, p), std::memory_order_release); }
    void setPan3(float p) { targetPan3_.store(juce::jlimit(-1.0f, 1.0f, p), std::memory_order_release); }
    void setPan4(float p) { targetPan4_.store(juce::jlimit(-1.0f, 1.0f, p), std::memory_order_release); }

    void setMaster(float g) { targetMaster_.store(juce::jlimit(0.0f, 2.0f, g), std::memory_order_release); }

    float getGain1() const { return targetGain1_.load(std::memory_order_acquire); }
    float getGain2() const { return targetGain2_.load(std::memory_order_acquire); }
    float getGain3() const { return targetGain3_.load(std::memory_order_acquire); }
    float getGain4() const { return targetGain4_.load(std::memory_order_acquire); }

    float getPan1() const { return targetPan1_.load(std::memory_order_acquire); }
    float getPan2() const { return targetPan2_.load(std::memory_order_acquire); }
    float getPan3() const { return targetPan3_.load(std::memory_order_acquire); }
    float getPan4() const { return targetPan4_.load(std::memory_order_acquire); }

    float getMaster() const { return targetMaster_.load(std::memory_order_acquire); }

private:
    std::atomic<float> targetGain1_{1.0f};
    std::atomic<float> targetGain2_{1.0f};
    std::atomic<float> targetGain3_{1.0f};
    std::atomic<float> targetGain4_{1.0f};

    std::atomic<float> targetPan1_{0.0f};
    std::atomic<float> targetPan2_{0.0f};
    std::atomic<float> targetPan3_{0.0f};
    std::atomic<float> targetPan4_{0.0f};

    std::atomic<float> targetMaster_{1.0f};

    float g1_ = 1.0f;
    float g2_ = 1.0f;
    float g3_ = 1.0f;
    float g4_ = 1.0f;

    float p1_ = 0.0f;
    float p2_ = 0.0f;
    float p3_ = 0.0f;
    float p4_ = 0.0f;

    float master_ = 1.0f;
    float smooth_ = 1.0f;

    bool prepared_ = false;
};

} // namespace dsp_primitives

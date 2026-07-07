#pragma once

#include <dsp/core/graph/PrimitiveNode.h>
#include <array>
#include <atomic>
#include <memory>

#include <manifold/debugging/Logging.h>

namespace dsp_primitives {

class BitCrusherNode : public IPrimitiveNode,
                       public std::enable_shared_from_this<BitCrusherNode> {
public:
    BitCrusherNode();
    BitCrusherNode(int simdTarget);

    const char* getNodeType() const override { return "BitCrusher"; }
    // Two stereo busses encoded as 4 input views:
    // bus A = inputs[0] (target stereo), bus B = inputs[1] (logic/mod source stereo, optional)
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 1; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setBits(float bits) { targetBits_.store(juce::jlimit(2.0f, 16.0f, bits), std::memory_order_release); notifyConfigChangeSimdImplementation();}
    void setRateReduction(float factor) { targetRateReduction_.store(juce::jlimit(1.0f, 64.0f, factor), std::memory_order_release); notifyConfigChangeSimdImplementation();}
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); notifyConfigChangeSimdImplementation();}
    void setOutput(float gain) { targetOutput_.store(juce::jlimit(0.0f, 2.0f, gain), std::memory_order_release); notifyConfigChangeSimdImplementation();}
    // 0 = normal crush, 1 = XOR(crushed A, crushed B), 2 = gate/compare using B over A
    void setLogicMode(int mode) { targetLogicMode_.store(juce::jlimit(0, 2, mode), std::memory_order_release); notifyConfigChangeSimdImplementation();}

    float getBits() const { return targetBits_.load(std::memory_order_acquire); }
    float getRateReduction() const { return targetRateReduction_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }
    float getOutput() const { return targetOutput_.load(std::memory_order_acquire); }
    int getLogicMode() const { return targetLogicMode_.load(std::memory_order_acquire); }

    const char * getHighwayImplementationTargetName() const
    {
        if(simd_implementation_.get() == NULL)
            return NULL;

        return simd_implementation_->targetName();
    }

    int getHighwayErrorCode() const { return highwayErrCode_;}

    Debug::Logger & GetLog();
    
private:
    inline void notifyConfigChangeSimdImplementation()
    {
        if(simd_implementation_ != NULL)
            simd_implementation_->configChanged();
    }

    std::atomic<float> targetBits_{8.0f};
    std::atomic<float> targetRateReduction_{4.0f};
    std::atomic<float> targetMix_{1.0f};
    std::atomic<float> targetOutput_{0.8f};
    std::atomic<int> targetLogicMode_{0};

    int simdTarget_ = 0; //0 = automatic
    int highwayErrCode_ = 0;

    float currentBits_ = 8.0f;
    float currentRateReduction_ = 4.0f;
    float currentMix_ = 1.0f;
    float currentOutput_ = 0.8f;
    int currentLogicMode_ = 0;
    float smooth_ = 1.0f;

    std::array<float, 2> heldSample_{{0.0f, 0.0f}};
    std::array<float, 2> holdCounter_{{0.0f, 0.0f}};

    bool prepared_ = false;

    //SIMD implementation
    std::unique_ptr<IPrimitiveNodeSIMDImplementation> simd_implementation_;
    Debug::Logger logger_;
    size_t totalSampleCount_ = 0;
};

} // namespace dsp_primitives

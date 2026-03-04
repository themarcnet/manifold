#pragma once

#include "dsp/core/graph/PrimitiveNode.h"

#include <atomic>
#include <memory>

namespace dsp_primitives {

class GainNode : public IPrimitiveNode, public std::enable_shared_from_this<GainNode> {
public:
    explicit GainNode(int numChannels = 2);

    const char* getNodeType() const override { return "Gain"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setGain(float gain);
    float getGain() const;
    void setMuted(bool muted);
    bool isMuted() const;

private:
    int numChannels_ = 2;
    std::atomic<float> targetGain_{1.0f};
    std::atomic<bool> muted_{false};

    float currentGain_ = 1.0f;
    float smoothingCoeff_ = 1.0f;
};

} // namespace dsp_primitives

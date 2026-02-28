#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <memory>

namespace dsp_primitives {

class PassthroughNode : public IPrimitiveNode, public std::enable_shared_from_this<PassthroughNode> {
public:
    enum class HostInputMode {
        MonitorControlled = 0,
        RawCapture = 1,
    };

    explicit PassthroughNode(int numChannels = 2,
                             HostInputMode hostInputMode = HostInputMode::MonitorControlled);

    const char* getNodeType() const override { return "Passthrough"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    bool acceptsHostInputWhenUnconnected() const override { return true; }
    bool wantsRawHostInputWhenUnconnected() const override {
        return hostInputMode_ == HostInputMode::RawCapture;
    }

private:
    int numChannels_ = 2;
    HostInputMode hostInputMode_ = HostInputMode::MonitorControlled;
};

} // namespace dsp_primitives

#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "dsp/core/nodes/LoopPlaybackNode.h"

#include <atomic>
#include <memory>

namespace dsp_primitives {

class RetrospectiveCaptureNode : public IPrimitiveNode,
                                 public std::enable_shared_from_this<RetrospectiveCaptureNode> {
public:
    explicit RetrospectiveCaptureNode(int numChannels = 2);

    const char* getNodeType() const override { return "RetrospectiveCapture"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setCaptureSeconds(float seconds);
    float getCaptureSeconds() const;
    int getCaptureSize() const;
    int getWriteOffset() const;
    void clear();

    bool copyRecentToLoop(const std::shared_ptr<LoopPlaybackNode>& playback,
                          int samplesBack,
                          bool overdub);
    bool copyRecentToLoop(const std::shared_ptr<LoopPlaybackNode>& playback,
                          int samplesBack,
                          bool overdub,
                          LoopPlaybackNode::OverdubLengthPolicy overdubLengthPolicy);

private:
    void ensureBuffer(float sampleRate);

    int numChannels_ = 2;
    juce::AudioBuffer<float> captureBuffer_;
    int captureSize_ = 1;
    std::atomic<int> writeOffset_{0};
    std::atomic<float> captureSeconds_{30.0f};
    double sampleRate_ = 44100.0;
};

} // namespace dsp_primitives

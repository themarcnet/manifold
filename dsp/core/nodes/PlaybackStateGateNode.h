#pragma once

#include "dsp/core/graph/PrimitiveNode.h"

#include <atomic>
#include <memory>

namespace dsp_primitives {

class PlaybackStateGateNode : public IPrimitiveNode,
                              public std::enable_shared_from_this<PlaybackStateGateNode> {
public:
    explicit PlaybackStateGateNode(int numChannels = 2);

    const char* getNodeType() const override { return "PlaybackStateGate"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void play();
    void pause();
    void stop();
    void setPlaying(bool playing);
    bool isPlaying() const;
    void setMuted(bool muted);
    bool isMuted() const;

private:
    int numChannels_ = 2;
    std::atomic<bool> playing_{true};
    std::atomic<bool> muted_{false};

    float gateGain_ = 1.0f;
    float smoothingCoeff_ = 1.0f;
};

} // namespace dsp_primitives

#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <atomic>
#include <memory>
#include <vector>

namespace dsp_primitives {

struct AudioBufferView {
    const float* const* channelData = nullptr;
    int numChannels = 0;
    int numSamples = 0;

    AudioBufferView() = default;
    explicit AudioBufferView(const juce::AudioBuffer<float>& buffer)
        : channelData(buffer.getArrayOfReadPointers())
        , numChannels(buffer.getNumChannels())
        , numSamples(buffer.getNumSamples()) {}

    float getSample(int channel, int sample) const {
        if (channel < 0 || channel >= numChannels) return 0.0f;
        if (sample < 0 || sample >= numSamples) return 0.0f;
        return channelData[channel][sample];
    }
};

struct WritableAudioBufferView {
    float* const* channelData = nullptr;
    int numChannels = 0;
    int numSamples = 0;

    WritableAudioBufferView() = default;
    explicit WritableAudioBufferView(juce::AudioBuffer<float>& buffer)
        : channelData(buffer.getArrayOfWritePointers())
        , numChannels(buffer.getNumChannels())
        , numSamples(buffer.getNumSamples()) {}

    void setSample(int channel, int sample, float value) {
        if (channel < 0 || channel >= numChannels) return;
        if (sample < 0 || sample >= numSamples) return;
        channelData[channel][sample] = value;
    }

    void addSample(int channel, int sample, float value) {
        if (channel < 0 || channel >= numChannels) return;
        if (sample < 0 || sample >= numSamples) return;
        channelData[channel][sample] += value;
    }

    void clear() {
        for (int ch = 0; ch < numChannels; ++ch) {
            std::fill_n(channelData[ch], numSamples, 0.0f);
        }
    }
};

struct Connection {
    std::weak_ptr<void> target;
    int fromOutput = 0;
    int toInput = 0;

    Connection(std::weak_ptr<void> t, int from, int to)
        : target(t), fromOutput(from), toInput(to) {}
};

class IPrimitiveNode {
public:
    virtual ~IPrimitiveNode() = default;

    virtual const char* getNodeType() const = 0;
    virtual int getNumInputs() const = 0;
    virtual int getNumOutputs() const = 0;

    virtual void process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) = 0;

    virtual void prepare(double sampleRate, int maxBlockSize) = 0;

    // If true and no graph inputs are connected, GraphRuntime will feed this
    // node from host input.
    virtual bool acceptsHostInputWhenUnconnected() const { return false; }

    // Host-input source selection for unconnected nodes:
    //  - false: use monitor-scaled host input (global passthrough/input gain)
    //  - true:  use raw host input (capture-plane semantics)
    virtual bool wantsRawHostInputWhenUnconnected() const { return false; }

    void addOutputConnection(std::weak_ptr<IPrimitiveNode> target, int fromOutput, int toInput) {
        outputConnections_.emplace_back(target, fromOutput, toInput);
    }

    void removeAllConnections() {
        outputConnections_.clear();
    }

    const std::vector<Connection>& getOutputConnections() const { return outputConnections_; }

    bool visitInProgress() const { return visitInProgress_.load(); }
    void setVisitInProgress(bool v) { visitInProgress_.store(v); }
    bool wasVisited() const { return visited_.load(); }
    void setVisited(bool v) { visited_.store(v); }
    void resetVisitFlags() { visited_.store(false); visitInProgress_.store(false); }

protected:
    std::vector<Connection> outputConnections_;
    std::atomic<bool> visited_{false};
    std::atomic<bool> visitInProgress_{false};
};

class IPrimitiveNodeSIMDImplementation
{
public:
     virtual ~IPrimitiveNodeSIMDImplementation() = default;

    virtual const char * targetName() const = 0;

    //Called by parent to notify the SIMD implementation that configuration has changed, and
    //recalculations of values that are based upon the configuration need to occur (if any)
    virtual void configChanged() = 0;

    virtual void reset() = 0;

    virtual void prepare(float /*samplerate*/)
    {}

    virtual void run(const std::vector<AudioBufferView>& inputs,
                     std::vector<WritableAudioBufferView>& outputs,
                     int numsamples) = 0;
};

} // namespace dsp_primitives

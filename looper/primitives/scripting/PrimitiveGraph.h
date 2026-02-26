#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <memory>
#include <vector>
#include <array>
#include <unordered_map>
#include <unordered_set>
#include <functional>
#include <atomic>

namespace dsp_primitives {

// Forward declarations
class LoopBufferWrapper;
class PlayheadWrapper;
class CaptureBufferWrapper;
class QuantizerWrapper;

// ============================================================================
// AudioBufferView - lightweight non-owning view into audio data
// ============================================================================
struct AudioBufferView {
    const float* const* channelData = nullptr;
    int numChannels = 0;
    int numSamples = 0;
    
    AudioBufferView() = default;
    AudioBufferView(const juce::AudioBuffer<float>& buffer) 
        : channelData(buffer.getArrayOfReadPointers())
        , numChannels(buffer.getNumChannels())
        , numSamples(buffer.getNumSamples()) {}
    
    float getSample(int channel, int sample) const {
        if (channel < 0 || channel >= numChannels) return 0.0f;
        if (sample < 0 || sample >= numSamples) return 0.0f;
        return channelData[channel][sample];
    }
};

// ============================================================================
// WritableAudioBufferView - view with write access
// ============================================================================
struct WritableAudioBufferView {
    float* const* channelData = nullptr;
    int numChannels = 0;
    int numSamples = 0;
    
    WritableAudioBufferView() = default;
    WritableAudioBufferView(juce::AudioBuffer<float>& buffer)
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

// ============================================================================
// Connection - represents a connection from an output to a target's input
// ============================================================================
struct Connection {
    std::weak_ptr<void> target;  // Weak ptr to target node
    int fromOutput = 0;          // Which output of source
    int toInput = 0;             // Which input of target
    
    Connection(std::weak_ptr<void> t, int from, int to)
        : target(t), fromOutput(from), toInput(to) {}
};

// ============================================================================
// IPrimitiveNode - interface for all primitive nodes
// ============================================================================
class IPrimitiveNode {
public:
    virtual ~IPrimitiveNode() = default;
    
    // Node identification
    virtual const char* getNodeType() const = 0;
    virtual int getNumInputs() const = 0;
    virtual int getNumOutputs() const = 0;
    
    // Audio processing - called on audio thread
    // inputs: array of input buffers (size = numInputs)
    // outputs: array of output buffers to fill (size = numOutputs)
    // numSamples: number of samples to process
    virtual void process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) = 0;
    
    // Called before process() to prepare internal state
    virtual void prepare(double sampleRate, int maxBlockSize) = 0;
    
    // Connection management (thread-safe)
    void addOutputConnection(std::weak_ptr<IPrimitiveNode> target, int fromOutput, int toInput);
    void removeAllConnections();
    const std::vector<Connection>& getOutputConnections() const { return outputConnections_; }
    
    // For cycle detection
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

// ============================================================================
// PrimitiveGraph - manages the graph and executes it
// ============================================================================
class PrimitiveGraph {
public:
    PrimitiveGraph();
    ~PrimitiveGraph();
    
    // Node registration (thread-safe, called from message thread)
    void registerNode(std::shared_ptr<IPrimitiveNode> node);
    void unregisterNode(std::shared_ptr<IPrimitiveNode> node);
    
    // Connection management (thread-safe)
    bool connect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                 std::shared_ptr<IPrimitiveNode> to, int inputIndex);
    void disconnect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                    std::shared_ptr<IPrimitiveNode> to, int inputIndex);
    void disconnectAll(std::shared_ptr<IPrimitiveNode> node);
    void clear();
    
    // Graph validation
    bool hasCycle() const;
    bool validateConnection(std::shared_ptr<IPrimitiveNode> from,
                           std::shared_ptr<IPrimitiveNode> to,
                           std::string& errorMessage) const;
    
    // Audio processing - called on audio thread
    void prepare(double sampleRate, int maxBlockSize);
    void process(juce::AudioBuffer<float>& outputBuffer);
    
    // For testing
    size_t getNodeCount() const;
    size_t getConnectionCount() const;
    std::vector<std::shared_ptr<IPrimitiveNode>> getTopologicalOrder() const;
    
    // Compile runtime - creates RT-safe immutable runtime from this builder graph
    // Must be called off audio thread. Returns nullptr on failure.
    std::unique_ptr<class GraphRuntime> compileRuntime(double sampleRate, int maxBlockSize, int numChannels);
    
private:
    std::vector<std::shared_ptr<IPrimitiveNode>> nodes_;
    mutable std::recursive_mutex nodesMutex_;
    
    // Working buffers for graph execution
    std::vector<juce::AudioBuffer<float>> workingBuffers_;
    std::vector<std::vector<AudioBufferView>> inputViews_;
    std::vector<std::vector<WritableAudioBufferView>> outputViews_;
    
    double sampleRate_ = 44100.0;
    int maxBlockSize_ = 512;
    bool prepared_ = false;
    
    // Build execution order (topological sort)
    bool buildTopologicalOrder(std::vector<std::shared_ptr<IPrimitiveNode>>& order) const;
    bool dfsVisit(std::shared_ptr<IPrimitiveNode> node, 
                  std::vector<std::shared_ptr<IPrimitiveNode>>& order,
                  std::unordered_set<std::shared_ptr<IPrimitiveNode>>& visited) const;
};

// ============================================================================
// PlayheadNode - concrete node that wraps PlayheadWrapper
// ============================================================================
class PlayheadNode : public IPrimitiveNode, public std::enable_shared_from_this<PlayheadNode> {
public:
    PlayheadNode();
    
    // IPrimitiveNode interface
    const char* getNodeType() const override { return "Playhead"; }
    int getNumInputs() const override { return 0; }
    int getNumOutputs() const override { return 1; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    // Configuration (called from Lua/control thread)
    void setLoopLength(int length);
    void setSpeed(float speed);
    void setReversed(bool reversed);
    void play();
    void pause();
    void stop();
    
    int getLoopLength() const;
    float getSpeed() const;
    bool isReversed() const;
    bool isPlaying() const;
    float getNormalizedPosition() const;
    
private:
    // RT-safe state: atomics for cross-thread communication
    // Control thread writes, audio thread reads (no locks in process())
    std::atomic<int> loopLength_{44100};
    std::atomic<int> position_{0};
    std::atomic<float> speed_{1.0f};
    std::atomic<bool> reversed_{false};
    std::atomic<bool> playing_{false};
    
    double sampleRate_ = 44100.0;
};

// ============================================================================
// OscillatorNode - generates audio (sine wave, for testing)
// ============================================================================
class OscillatorNode : public IPrimitiveNode, public std::enable_shared_from_this<OscillatorNode> {
public:
    OscillatorNode();
    
    const char* getNodeType() const override { return "Oscillator"; }
    int getNumInputs() const override { return 0; }
    int getNumOutputs() const override { return 1; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    void setFrequency(float freq);
    void setAmplitude(float amp) { amplitude_ = amp; }
    void setEnabled(bool en) { enabled_ = en; }
    void setWaveform(int shape);
    float getFrequency() const { return frequency_; }
    float getAmplitude() const { return amplitude_; }
    bool isEnabled() const { return enabled_; }
    int getWaveform() const { return waveform_; }
    
private:
    float frequency_ = 440.0f;
    float amplitude_ = 0.5f;
    bool enabled_ = true;
    int waveform_ = 0; // 0=sine,1=saw,2=square,3=triangle,4=sine+saw
    double sampleRate_ = 44100.0;
    double phase_ = 0.0;
    double phaseIncrement_ = 0.0;
};

// ============================================================================
// FilterNode - simple stereo low-pass filter
// ============================================================================
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

    float getCutoff() const { return cutoffHz_; }
    float getResonance() const { return resonance_; }
    float getMix() const { return mix_; }

private:
    void updateAlpha();

    double sampleRate_ = 44100.0;
    float cutoffHz_ = 1400.0f;
    float resonance_ = 0.1f;
    float mix_ = 1.0f;
    float alpha_ = 0.0f;
    std::array<float, 2> z1_ {0.0f, 0.0f};
    std::array<float, 2> z2_ {0.0f, 0.0f};
};

// ============================================================================
// DistortionNode - stereo tanh saturator
// ============================================================================
class DistortionNode : public IPrimitiveNode, public std::enable_shared_from_this<DistortionNode> {
public:
    DistortionNode();

    const char* getNodeType() const override { return "Distortion"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    void setDrive(float d) { drive_ = juce::jlimit(1.0f, 30.0f, d); }
    void setMix(float m) { mix_ = juce::jlimit(0.0f, 1.0f, m); }
    void setOutput(float g) { output_ = juce::jlimit(0.0f, 2.0f, g); }

    float getDrive() const { return drive_; }
    float getMix() const { return mix_; }
    float getOutput() const { return output_; }

private:
    float drive_ = 4.0f;
    float mix_ = 0.7f;
    float output_ = 0.8f;
};

// ============================================================================
// PassthroughNode - simple node that copies input to output (for testing)
// ============================================================================
class PassthroughNode : public IPrimitiveNode, public std::enable_shared_from_this<PassthroughNode> {
public:
    PassthroughNode(int numChannels = 2);
    
    const char* getNodeType() const override { return "Passthrough"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
private:
    int numChannels_ = 2;
};

// ============================================================================
// ReverbNode - wraps JUCE Reverb for audio effects
// ============================================================================
class ReverbNode : public IPrimitiveNode, public std::enable_shared_from_this<ReverbNode> {
public:
    ReverbNode();
    
    const char* getNodeType() const override { return "Reverb"; }
    int getNumInputs() const override { return 2; } // Stereo in
    int getNumOutputs() const override { return 2; } // Stereo out
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    void setRoomSize(float value) { params_.roomSize = value; reverb_.setParameters(params_); }
    void setDamping(float value) { params_.damping = value; reverb_.setParameters(params_); }
    void setWetLevel(float value) { params_.wetLevel = value; reverb_.setParameters(params_); }
    void setDryLevel(float value) { params_.dryLevel = value; reverb_.setParameters(params_); }
    void setWidth(float value) { params_.width = value; reverb_.setParameters(params_); }
    
    float getRoomSize() const { return params_.roomSize; }
    float getDamping() const { return params_.damping; }
    float getWetLevel() const { return params_.wetLevel; }
    float getDryLevel() const { return params_.dryLevel; }
    float getWidth() const { return params_.width; }
    
private:
    juce::Reverb reverb_;
    juce::Reverb::Parameters params_;
    
    // Preallocated scratch buffers to avoid per-process allocations
    // RT-safe: allocated once in prepare(), reused every process()
    std::vector<float> left_;
    std::vector<float> right_;
};

} // namespace dsp_primitives

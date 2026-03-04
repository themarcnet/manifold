#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "ScriptingConfig.h"

#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace dsp_primitives {

// Forward declarations
class LoopBufferWrapper;
class PlayheadWrapper;
class CaptureBufferWrapper;
class QuantizerWrapper;

class PrimitiveGraph {
public:
    PrimitiveGraph();
    ~PrimitiveGraph();

    void registerNode(std::shared_ptr<IPrimitiveNode> node);
    void unregisterNode(std::shared_ptr<IPrimitiveNode> node);

    bool connect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                 std::shared_ptr<IPrimitiveNode> to, int inputIndex);
    void disconnect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                    std::shared_ptr<IPrimitiveNode> to, int inputIndex);
    void disconnectAll(std::shared_ptr<IPrimitiveNode> node);
    void clear();

    bool hasCycle() const;
    bool validateConnection(std::shared_ptr<IPrimitiveNode> from,
                           std::shared_ptr<IPrimitiveNode> to,
                           std::string& errorMessage) const;

    void prepare(double sampleRate, int maxBlockSize);
    void process(juce::AudioBuffer<float>& outputBuffer);

    size_t getNodeCount() const;
    size_t getConnectionCount() const;
    std::vector<std::shared_ptr<IPrimitiveNode>> getTopologicalOrder() const;

    std::unique_ptr<class GraphRuntime> compileRuntime(double sampleRate, int maxBlockSize, int numChannels);

private:
    std::vector<std::shared_ptr<IPrimitiveNode>> nodes_;
    mutable std::recursive_mutex nodesMutex_;

    std::vector<juce::AudioBuffer<float>> workingBuffers_;
    std::vector<std::vector<AudioBufferView>> inputViews_;
    std::vector<std::vector<WritableAudioBufferView>> outputViews_;

    double sampleRate_ = 44100.0;
    int maxBlockSize_ = scripting::BufferConfig::MAX_DSP_BLOCK_SIZE;
    bool prepared_ = false;

    bool buildTopologicalOrder(std::vector<std::shared_ptr<IPrimitiveNode>>& order) const;
    bool dfsVisit(std::shared_ptr<IPrimitiveNode> node,
                  std::vector<std::shared_ptr<IPrimitiveNode>>& order,
                  std::unordered_set<std::shared_ptr<IPrimitiveNode>>& visited) const;
};

} // namespace dsp_primitives

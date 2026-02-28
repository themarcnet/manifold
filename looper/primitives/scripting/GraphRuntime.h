#pragma once

#include "PrimitiveGraph.h"
#include <juce_audio_basics/juce_audio_basics.h>
#include <memory>
#include <vector>
#include <atomic>

namespace dsp_primitives {

// Forward declarations
class IPrimitiveNode;

/**
 * CompiledNode - immutable snapshot of a node for runtime execution.
 */
struct CompiledNode {
    std::shared_ptr<IPrimitiveNode> node;
    int inputCount = 0;
    int outputCount = 0;
};

/**
 * RouteEntry - connection routing info computed at compile time.
 */
struct RouteEntry {
    int sourceNodeIndex = -1;
    int targetNodeIndex = -1;
    int sourceOutput = 0;
    int targetInput = 0;
};

/**
 * GraphRuntime - RT-safe compiled graph executor.
 * 
 * Designed for Phase 4 lock-free audio processing:
 * - prepare() called off audio thread, allocates all scratch
 * - process() called on audio thread, no locks, no allocations
 * - Immutable after prepare() - topology is fixed
 * 
 * Assumptions (conservative first pass):
 * - 2 channels fixed
 * - maxBlockSize handled via internal chunking if needed
 * - Single output (sink) node or sum of all sink nodes
 */
class GraphRuntime {
public:
    GraphRuntime();
    ~GraphRuntime();

    /**
     * Prepare runtime for processing.
     * Called OFF audio thread. May allocate.
     * 
     * @param sampleRate Audio sample rate
     * @param maxBlockSize Maximum samples per process() call
     * @param numChannels Number of audio channels (currently ignored, assumes 2)
     */
    void prepare(double sampleRate, int maxBlockSize, int numChannels);

    /**
     * Process audio through the compiled graph.
     * Called on audio thread. MUST be lock-free and allocation-free.
     *
     * @param buffer In-place audio buffer (modified)
     * @param rawHostInput Optional raw host-input buffer for nodes that request
     *                     capture-plane semantics when unconnected.
     */
    void process(juce::AudioBuffer<float>& buffer,
                 const juce::AudioBuffer<float>* rawHostInput = nullptr);

    int getNumChannels() const noexcept { return numChannels_; }
    int getMaxBlockSize() const noexcept { return maxBlockSize_; }
    double getSampleRate() const noexcept { return sampleRate_; }
    int getCompiledNodeCount() const noexcept { return static_cast<int>(compiledNodes_.size()); }
    int getRouteCount() const noexcept { return static_cast<int>(routes_.size()); }

    /**
     * Check if runtime is valid and ready for processing.
     */
    bool isValid() const noexcept { return isValid_.load(); }

    // Friend function for compilation (defined in GraphRuntime.cpp)
    friend std::unique_ptr<GraphRuntime> compileGraphRuntime(
        PrimitiveGraph& graph, double sampleRate, int maxBlockSize, int numChannels);

private:
    double sampleRate_ = 44100.0;
    int maxBlockSize_ = 512;
    int numChannels_ = 2;

    std::atomic<bool> isValid_{false};

    // Compiled topology (immutable after prepare)
    std::vector<CompiledNode> compiledNodes_;
    std::vector<RouteEntry> routes_;

    // Preallocated scratch buffers for graph execution
    // No allocations in process() - all preallocated here
    std::vector<juce::AudioBuffer<float>> scratchBuffers_;

    // Preallocated buffers used in process() to avoid per-call heap work.
    juce::AudioBuffer<float> chunkBuffer_;
    juce::AudioBuffer<float> rawChunkBuffer_;
    juce::AudioBuffer<float> inputAccumulator_;

    // Map from node index to its scratch buffer index
    std::vector<int> nodeToScratchIndex_;

    // Input/output views reused each process() call
    std::vector<AudioBufferView> inputViews_;
    std::vector<WritableAudioBufferView> outputViews_;

    /**
     * Internal process that handles chunking for blocks larger than maxBlockSize.
     */
    void processChunked(juce::AudioBuffer<float>& buffer,
                        const juce::AudioBuffer<float>* rawHostInput);

    /**
     * Single-pass process for blocks <= maxBlockSize.
     */
    void processSingle(juce::AudioBuffer<float>& buffer,
                       const juce::AudioBuffer<float>* rawHostInput);
};

/**
 * Compile a PrimitiveGraph into a GraphRuntime.
 * 
 * This is the builder-side API that creates an immutable, RT-safe runtime
 * from the mutable builder graph.
 * 
 * Implementation notes:
 * 1. Takes snapshot of nodes + connections under builder lock
 * 2. Computes topological order
 * 3. Builds routing table from connections
 * 4. Allocates all scratch buffers
 * 5. Calls prepare() on all nodes
 * 6. Returns ready-to-use runtime
 * 
 * Note: This is a free function, but has friend access to GraphRuntime internals.
 * 
 * @param graph Source graph to compile
 * @param sampleRate Target sample rate
 * @param maxBlockSize Maximum block size
 * @param numChannels Number of channels (currently ignored, assumes 2)
 * @return Compiled runtime or nullptr on failure
 */
std::unique_ptr<GraphRuntime> compileGraphRuntime(
    class PrimitiveGraph& graph,
    double sampleRate,
    int maxBlockSize,
    int numChannels);

} // namespace dsp_primitives

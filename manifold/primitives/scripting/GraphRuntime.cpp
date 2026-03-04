#include "GraphRuntime.h"
#include <cstring>
#include <algorithm>

namespace dsp_primitives {

// ============================================================================
// GraphRuntime implementation
// ============================================================================

GraphRuntime::GraphRuntime() = default;

GraphRuntime::~GraphRuntime() = default;

void GraphRuntime::prepare(double sampleRate, int maxBlockSize, int numChannels) {
    (void)numChannels; // Conservative: always 2 channels for now
    
    sampleRate_ = sampleRate;
    maxBlockSize_ = maxBlockSize;
    numChannels_ = 2; // Conservative: hardcode stereo
    
    if (compiledNodes_.empty()) {
        isValid_.store(false);
        return;
    }

    // Allocate scratch buffers: one per node (for simplicity, avoid complex pooling)
    const size_t numNodes = compiledNodes_.size();
    scratchBuffers_.clear();
    scratchBuffers_.reserve(numNodes);
    
    for (size_t i = 0; i < numNodes; ++i) {
        // Preallocate stereo buffer at maxBlockSize
        juce::AudioBuffer<float> buf(numChannels_, maxBlockSize_);
        buf.clear();
        scratchBuffers_.push_back(std::move(buf));
    }

    // Map nodes to their scratch buffer indices
    nodeToScratchIndex_.resize(numNodes);
    for (size_t i = 0; i < numNodes; ++i) {
        nodeToScratchIndex_[i] = static_cast<int>(i);
    }

    // Preallocate input/output view vectors to max sizes seen in compiled nodes.
    // This ensures process() won't allocate when pushing views.
    int maxInputs = 0;
    int maxOutputs = 0;
    for (const auto& compiled : compiledNodes_) {
        maxInputs = std::max(maxInputs, compiled.inputCount);
        maxOutputs = std::max(maxOutputs, compiled.outputCount);
    }
    inputViews_.reserve(static_cast<size_t>(std::max(1, maxInputs)));
    outputViews_.reserve(static_cast<size_t>(std::max(1, maxOutputs)));

    // Call prepare on each compiled node
    for (auto& compiled : compiledNodes_) {
        compiled.node->prepare(sampleRate, maxBlockSize);
    }

    // Preallocate buffers used during processing (audio thread)
    chunkBuffer_.setSize(numChannels_, maxBlockSize_, false, true);
    rawChunkBuffer_.setSize(numChannels_, maxBlockSize_, false, true);

    // Allocate input accumulators for the maximum bus-count across nodes.
    int maxInputBuses = 1;
    for (const auto& compiled : compiledNodes_) {
        const int buses = std::max(0, (compiled.inputCount + numChannels_ - 1) / numChannels_);
        maxInputBuses = std::max(maxInputBuses, buses);
    }

    inputAccumulators_.clear();
    inputAccumulators_.reserve(static_cast<size_t>(maxInputBuses));
    for (int b = 0; b < maxInputBuses; ++b) {
        juce::AudioBuffer<float> buf(numChannels_, maxBlockSize_);
        buf.clear();
        inputAccumulators_.push_back(std::move(buf));
    }

    isValid_.store(true);
}

void GraphRuntime::process(juce::AudioBuffer<float>& buffer,
                           const juce::AudioBuffer<float>* rawHostInput) {
    if (!isValid_.load()) {
        buffer.clear();
        return;
    }

    const int numSamples = buffer.getNumSamples();

    // Handle blocks larger than maxBlockSize via chunking
    if (numSamples > maxBlockSize_) {
        processChunked(buffer, rawHostInput);
    } else {
        processSingle(buffer, rawHostInput);
    }
}

void GraphRuntime::processChunked(juce::AudioBuffer<float>& buffer,
                                  const juce::AudioBuffer<float>* rawHostInput) {
    const int totalSamples = buffer.getNumSamples();
    const int numChunks = (totalSamples + maxBlockSize_ - 1) / maxBlockSize_;

    // Process in chunks without allocating
    int offset = 0;
    for (int chunk = 0; chunk < numChunks; ++chunk) {
        const int chunkSize = juce::jmin(maxBlockSize_, totalSamples - offset);

        // Copy into preallocated chunk buffer then process using a view.
        // Avoid resizing chunkBuffer_ on the audio thread.
        for (int ch = 0; ch < numChannels_; ++ch) {
            const int srcCh = juce::jmin(ch, buffer.getNumChannels() - 1);
            std::memcpy(chunkBuffer_.getWritePointer(ch),
                        buffer.getReadPointer(srcCh) + offset,
                        static_cast<size_t>(chunkSize) * sizeof(float));
        }

        const juce::AudioBuffer<float>* rawChunkPtr = nullptr;
        juce::AudioBuffer<float> rawChunkView;
        if (rawHostInput != nullptr &&
            rawHostInput->getNumChannels() > 0 &&
            rawHostInput->getNumSamples() >= (offset + chunkSize)) {
            for (int ch = 0; ch < numChannels_; ++ch) {
                const int srcCh = juce::jmin(ch, rawHostInput->getNumChannels() - 1);
                std::memcpy(rawChunkBuffer_.getWritePointer(ch),
                            rawHostInput->getReadPointer(srcCh) + offset,
                            static_cast<size_t>(chunkSize) * sizeof(float));
            }
            float* rawPtrs[2] = {
                rawChunkBuffer_.getWritePointer(0),
                rawChunkBuffer_.getWritePointer(1)
            };
            rawChunkView.setDataToReferTo(rawPtrs, numChannels_, chunkSize);
            rawChunkPtr = &rawChunkView;
        }

        float* chunkPtrs[2] = {
            chunkBuffer_.getWritePointer(0),
            chunkBuffer_.getWritePointer(1)
        };
        juce::AudioBuffer<float> chunkView(chunkPtrs, numChannels_, chunkSize);
        processSingle(chunkView, rawChunkPtr);

        for (int ch = 0; ch < numChannels_; ++ch) {
            const int dstCh = juce::jmin(ch, buffer.getNumChannels() - 1);
            std::memcpy(buffer.getWritePointer(dstCh) + offset,
                        chunkBuffer_.getReadPointer(ch),
                        static_cast<size_t>(chunkSize) * sizeof(float));
        }

        offset += chunkSize;
    }
}

void GraphRuntime::processSingle(juce::AudioBuffer<float>& buffer,
                                 const juce::AudioBuffer<float>* rawHostInput) {
    const int numSamples = buffer.getNumSamples();
    const size_t numNodes = compiledNodes_.size();
    
    if (numNodes == 0) {
        buffer.clear();
        return;
    }

    // Clear all scratch buffers. They are preallocated to maxBlockSize_ in prepare().
    if (numSamples > maxBlockSize_) {
        // Should be prevented by process() chunking.
        buffer.clear();
        return;
    }

    for (auto& scratch : scratchBuffers_) {
        scratch.clear(0, numSamples);
    }

    // Execute nodes in topological order
    for (size_t nodeIdx = 0; nodeIdx < numNodes; ++nodeIdx) {
        auto& compiled = compiledNodes_[nodeIdx];
        const int scratchIdx = nodeToScratchIndex_[nodeIdx];
        auto& scratchBuf = scratchBuffers_[scratchIdx];
        
        // Build per-bus input accumulators for this node (preallocated)
        const int busCount = std::max(0, (compiled.inputCount + numChannels_ - 1) / numChannels_);
        const int activeBuses = std::max(1, busCount);

        for (int b = 0; b < activeBuses; ++b) {
            inputAccumulators_[static_cast<size_t>(b)].clear(0, numSamples);
        }

        bool hasIncoming = false;

        // Find all compiled routes that target this node.
        // IMPORTANT: use compiled route snapshot, not mutable node connections.
        for (const auto& route : routes_) {
            if (route.targetNodeIndex != static_cast<int>(nodeIdx)) {
                continue;
            }

            const int srcScratchIdx = nodeToScratchIndex_[static_cast<size_t>(route.sourceNodeIndex)];
            auto& srcBuf = scratchBuffers_[static_cast<size_t>(srcScratchIdx)];

            const int bus = juce::jlimit(0, activeBuses - 1, route.targetInput);
            auto& acc = inputAccumulators_[static_cast<size_t>(bus)];

            for (int ch = 0; ch < numChannels_; ++ch) {
                acc.addFrom(ch, 0, srcBuf, ch, 0, numSamples);
            }
            hasIncoming = true;
        }

        // If node expects input but nothing connected, only nodes that opt in
        // receive host input implicitly. Other DSP nodes stay silent unless
        // explicitly wired, which avoids stale/ghost FX when scripts change.
        if (!hasIncoming && compiled.inputCount > 0 &&
            compiled.node->acceptsHostInputWhenUnconnected()) {
            const juce::AudioBuffer<float>* hostInputSource = &buffer;
            if (compiled.node->wantsRawHostInputWhenUnconnected() &&
                rawHostInput != nullptr &&
                rawHostInput->getNumChannels() > 0 &&
                rawHostInput->getNumSamples() >= numSamples) {
                hostInputSource = rawHostInput;
            }

            auto& acc0 = inputAccumulators_[0];
            for (int ch = 0; ch < numChannels_; ++ch) {
                const int srcCh = juce::jmin(ch, hostInputSource->getNumChannels() - 1);
                acc0.copyFrom(ch, 0, *hostInputSource, srcCh, 0, numSamples);
            }
        }

        // Build input views from per-bus accumulators.
        // Legacy convention: most nodes declare inputCount==2 for stereo,
        // and index inputs by channel (inputs[0] for L, inputs[1] for R).
        // Multi-bus nodes encode busses as (busCount * 2) input views.
        inputViews_.clear();
        for (int i = 0; i < compiled.inputCount; ++i) {
            const int bus = juce::jlimit(0, activeBuses - 1, i / numChannels_);
            inputViews_.push_back(AudioBufferView(inputAccumulators_[static_cast<size_t>(bus)]));
        }

        // Build output views to scratch buffer
        outputViews_.clear();
        for (int i = 0; i < compiled.outputCount; ++i) {
            outputViews_.push_back(WritableAudioBufferView(scratchBuf));
        }

        // Process the node
        compiled.node->process(inputViews_, outputViews_, numSamples);
    }

    // Mix sink nodes (nodes with no outgoing compiled routes) to output
    buffer.clear();
    
    for (size_t nodeIdx = 0; nodeIdx < numNodes; ++nodeIdx) {
        bool hasOutgoing = false;
        for (const auto& route : routes_) {
            if (route.sourceNodeIndex == static_cast<int>(nodeIdx)) {
                hasOutgoing = true;
                break;
            }
        }

        if (hasOutgoing) {
            continue;
        }
        
        // This is a sink - add its output to buffer
        const int scratchIdx = nodeToScratchIndex_[nodeIdx];
        auto& sinkBuf = scratchBuffers_[scratchIdx];
        
        for (int ch = 0; ch < numChannels_; ++ch) {
            buffer.addFrom(ch, 0, sinkBuf, ch, 0, numSamples);
        }
    }
}

// ============================================================================
// compileGraphRuntime - factory function
// ============================================================================

std::unique_ptr<GraphRuntime> compileGraphRuntime(
    PrimitiveGraph& graph,
    double sampleRate,
    int maxBlockSize,
    int numChannels) {

    auto runtime = std::make_unique<GraphRuntime>();
    
    // Step 1: Get topological order (snapshot)
    // This requires the graph lock, but we copy the pointers
    auto topoOrder = graph.getTopologicalOrder();
    
    if (topoOrder.empty()) {
        return nullptr; // No nodes to compile
    }

    // Step 2: Build compiled node list
    runtime->compiledNodes_.clear();
    runtime->compiledNodes_.reserve(topoOrder.size());
    
    for (auto& node : topoOrder) {
        CompiledNode compiled;
        compiled.node = node;
        compiled.inputCount = node->getNumInputs();
        compiled.outputCount = node->getNumOutputs();
        runtime->compiledNodes_.push_back(std::move(compiled));
    }

    // Step 3: Build routing table (connections snapshot)
    // Routes are built implicitly by the topological processing
    runtime->routes_.clear();
    
    for (size_t srcIdx = 0; srcIdx < runtime->compiledNodes_.size(); ++srcIdx) {
        const auto& srcNode = runtime->compiledNodes_[srcIdx];
        const auto& connections = srcNode.node->getOutputConnections();
        
        for (const auto& conn : connections) {
            if (auto target = std::static_pointer_cast<IPrimitiveNode>(conn.target.lock())) {
                // Find target index in compiled nodes
                for (size_t tgtIdx = 0; tgtIdx < runtime->compiledNodes_.size(); ++tgtIdx) {
                    if (runtime->compiledNodes_[tgtIdx].node.get() == target.get()) {
                        RouteEntry route;
                        route.sourceNodeIndex = static_cast<int>(srcIdx);
                        route.targetNodeIndex = static_cast<int>(tgtIdx);
                        route.sourceOutput = conn.fromOutput;
                        route.targetInput = conn.toInput;
                        runtime->routes_.push_back(route);
                        break;
                    }
                }
            }
        }
    }

    // Step 4: Prepare the runtime (allocates scratch, calls node prepare)
    runtime->prepare(sampleRate, maxBlockSize, numChannels);
    
    if (!runtime->isValid()) {
        return nullptr;
    }

    return runtime;
}

} // namespace dsp_primitives

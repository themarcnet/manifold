#include "PrimitiveGraph.h"
#include "GraphRuntime.h"
#include <cmath>

namespace dsp_primitives {

// ============================================================================
// IPrimitiveNode implementation
// ============================================================================

void IPrimitiveNode::addOutputConnection(std::weak_ptr<IPrimitiveNode> target, int fromOutput, int toInput) {
    outputConnections_.emplace_back(target, fromOutput, toInput);
}

void IPrimitiveNode::removeAllConnections() {
    outputConnections_.clear();
}

// ============================================================================
// PrimitiveGraph implementation
// ============================================================================

PrimitiveGraph::PrimitiveGraph() = default;
PrimitiveGraph::~PrimitiveGraph() = default;

void PrimitiveGraph::registerNode(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    nodes_.push_back(node);
    prepared_ = false; // Force re-prepare
}

void PrimitiveGraph::unregisterNode(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    
    // Remove all connections to/from this node
    node->removeAllConnections();
    for (auto& otherNode : nodes_) {
        if (otherNode != node) {
            // Remove connections from other nodes to this node
            auto& connections = const_cast<std::vector<Connection>&>(otherNode->getOutputConnections());
            connections.erase(
                std::remove_if(connections.begin(), connections.end(),
                    [&node](const Connection& conn) {
                        if (auto target = conn.target.lock()) {
                            return target == node;
                        }
                        return false;
                    }),
                connections.end()
            );
        }
    }
    
    // Remove node from list
    nodes_.erase(
        std::remove(nodes_.begin(), nodes_.end(), node),
        nodes_.end()
    );
    
    prepared_ = false;
}

bool PrimitiveGraph::connect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                             std::shared_ptr<IPrimitiveNode> to, int inputIndex) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    std::string error;
    if (!validateConnection(from, to, error)) {
        return false;
    }

    // Avoid duplicate edges.
    for (const auto& conn : from->getOutputConnections()) {
        if (auto target = std::static_pointer_cast<IPrimitiveNode>(conn.target.lock())) {
            if (target == to && conn.fromOutput == outputIndex && conn.toInput == inputIndex) {
                return true;
            }
        }
    }
    
    // Add connection
    from->addOutputConnection(to, outputIndex, inputIndex);
    prepared_ = false; // Force re-prepare
    return true;
}

void PrimitiveGraph::disconnect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                                std::shared_ptr<IPrimitiveNode> to, int inputIndex) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    auto& connections = const_cast<std::vector<Connection>&>(from->getOutputConnections());
    connections.erase(
        std::remove_if(connections.begin(), connections.end(),
            [&to, outputIndex, inputIndex](const Connection& conn) {
                if (auto target = conn.target.lock()) {
                    return target == to && 
                           conn.fromOutput == outputIndex && 
                           conn.toInput == inputIndex;
                }
                return false;
            }),
        connections.end()
    );
    prepared_ = false;
}

void PrimitiveGraph::disconnectAll(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    // Remove all outgoing connections
    node->removeAllConnections();
    
    // Remove all incoming connections
    for (auto& otherNode : nodes_) {
        if (otherNode != node) {
            auto& connections = const_cast<std::vector<Connection>&>(otherNode->getOutputConnections());
            connections.erase(
                std::remove_if(connections.begin(), connections.end(),
                    [&node](const Connection& conn) {
                        if (auto target = conn.target.lock()) {
                            return target == node;
                        }
                        return false;
                    }),
                connections.end()
            );
        }
    }
    prepared_ = false;
}

void PrimitiveGraph::clear() {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    for (auto& node : nodes_) {
        node->removeAllConnections();
    }
    nodes_.clear();
    workingBuffers_.clear();
    prepared_ = false;
}

bool PrimitiveGraph::hasCycle() const {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    
    // Reset all visit flags
    for (auto& node : nodes_) {
        node->resetVisitFlags();
    }
    
    // Try to build topological order - if it fails, there's a cycle
    std::vector<std::shared_ptr<IPrimitiveNode>> order;
    return !buildTopologicalOrder(order);
}

bool PrimitiveGraph::validateConnection(std::shared_ptr<IPrimitiveNode> from,
                                       std::shared_ptr<IPrimitiveNode> to,
                                       std::string& errorMessage) const {
    // Check if nodes exist
    {
        std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
        if (std::find(nodes_.begin(), nodes_.end(), from) == nodes_.end()) {
            errorMessage = "Source node not found in graph";
            return false;
        }
        if (std::find(nodes_.begin(), nodes_.end(), to) == nodes_.end()) {
            errorMessage = "Target node not found in graph";
            return false;
        }
    }
    
    // Check for self-connection
    if (from == to) {
        errorMessage = "Cannot connect node to itself";
        return false;
    }
    
    // Check for existing connection that would create cycle
    // Temporarily add connection and check for cycle
    from->addOutputConnection(to, 0, 0);
    bool hasCycleResult = hasCycle();
    
    // Remove the temporary connection
    auto& connections = const_cast<std::vector<Connection>&>(from->getOutputConnections());
    if (!connections.empty()) {
        connections.pop_back();
    }
    
    if (hasCycleResult) {
        errorMessage = "Connection would create cycle";
        return false;
    }
    
    return true;
}

void PrimitiveGraph::prepare(double sampleRate, int maxBlockSize) {
    sampleRate_ = sampleRate;
    maxBlockSize_ = maxBlockSize;
    
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    
    // Prepare all nodes
    for (auto& node : nodes_) {
        node->prepare(sampleRate, maxBlockSize);
    }
    
    // Allocate working buffers
    // We need buffers for intermediate connections
    // For now, allocate a reasonable number
    const int maxIntermediateBuffers = 16;
    workingBuffers_.resize(maxIntermediateBuffers);
    for (auto& buffer : workingBuffers_) {
        buffer.setSize(2, maxBlockSize); // Stereo
    }
    
    prepared_ = true;
}

void PrimitiveGraph::process(juce::AudioBuffer<float>& outputBuffer) {
    const int numSamples = outputBuffer.getNumSamples();

    // Graph topology can change at runtime from Lua. Re-prepare lazily.
    if (!prepared_) {
        prepare(sampleRate_, juce::jmax(maxBlockSize_, numSamples));
        if (!prepared_) {
            return;
        }
    }
    
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    // Get topological order for execution
    std::vector<std::shared_ptr<IPrimitiveNode>> order;
    if (!buildTopologicalOrder(order)) {
        // Cycle detected - clear output
        outputBuffer.clear();
        return;
    }
    
    // Execute graph with basic routing:
    // - upstream node outputs are summed into each node input buffer
    // - nodes with no incoming connections but audio inputs receive host buffer
    // - sink nodes (no outgoing connections) are summed to final output
    std::unordered_map<IPrimitiveNode*, int> nodeToBuffer;
    int bufferIndex = 0;

    for (auto& node : order) {
        if (bufferIndex >= static_cast<int>(workingBuffers_.size())) {
            break;
        }

        juce::AudioBuffer<float> inBuffer(outputBuffer.getNumChannels(), numSamples);
        inBuffer.clear();

        bool hasIncoming = false;

        // Gather all upstream connections into this node input buffer.
        for (auto& src : order) {
            for (const auto& conn : src->getOutputConnections()) {
                if (auto target = std::static_pointer_cast<IPrimitiveNode>(conn.target.lock())) {
                    if (target.get() != node.get()) {
                        continue;
                    }

                    hasIncoming = true;
                    auto it = nodeToBuffer.find(src.get());
                    if (it == nodeToBuffer.end()) {
                        continue;
                    }

                    auto& srcBuffer = workingBuffers_[it->second];
                    const int channels = juce::jmin(inBuffer.getNumChannels(), srcBuffer.getNumChannels());
                    for (int ch = 0; ch < channels; ++ch) {
                        inBuffer.addFrom(ch, 0, srcBuffer, ch, 0, numSamples);
                    }
                }
            }
        }

        // Keep legacy path consistent with GraphRuntime: only PassthroughNode
        // receives implicit host input when it has no incoming edges.
        if (!hasIncoming && node->getNumInputs() > 0 &&
            dynamic_cast<PassthroughNode*>(node.get()) != nullptr) {
            const int channels = juce::jmin(inBuffer.getNumChannels(), outputBuffer.getNumChannels());
            for (int ch = 0; ch < channels; ++ch) {
                inBuffer.copyFrom(ch, 0, outputBuffer, ch, 0, numSamples);
            }
        }

        auto& outBuffer = workingBuffers_[bufferIndex];
        outBuffer.setSize(outputBuffer.getNumChannels(), numSamples, false, false, true);
        outBuffer.clear();

        std::vector<AudioBufferView> inputs;
        for (int i = 0; i < node->getNumInputs(); ++i) {
            inputs.emplace_back(inBuffer);
        }

        std::vector<WritableAudioBufferView> outputs;
        for (int i = 0; i < node->getNumOutputs(); ++i) {
            outputs.emplace_back(outBuffer);
        }

        node->process(inputs, outputs, numSamples);
        nodeToBuffer[node.get()] = bufferIndex;
        ++bufferIndex;
    }

    outputBuffer.clear();

    // Mix sink nodes (no outgoing edges) to graph output.
    for (auto& node : order) {
        if (!node->getOutputConnections().empty()) {
            continue;
        }

        auto it = nodeToBuffer.find(node.get());
        if (it == nodeToBuffer.end()) {
            continue;
        }

        auto& sinkBuffer = workingBuffers_[it->second];
        const int channels = juce::jmin(outputBuffer.getNumChannels(), sinkBuffer.getNumChannels());
        for (int ch = 0; ch < channels; ++ch) {
            outputBuffer.addFrom(ch, 0, sinkBuffer, ch, 0, numSamples);
        }
    }
}

bool PrimitiveGraph::buildTopologicalOrder(std::vector<std::shared_ptr<IPrimitiveNode>>& order) const {
    order.clear();
    
    // Reset visit flags
    for (auto& node : nodes_) {
        node->resetVisitFlags();
    }
    
    std::unordered_set<std::shared_ptr<IPrimitiveNode>> visited;
    
    // DFS from each unvisited node
    for (auto& node : nodes_) {
        if (!node->wasVisited()) {
            if (!dfsVisit(node, order, visited)) {
                return false; // Cycle detected
            }
        }
    }
    
    // Reverse to get correct order
    std::reverse(order.begin(), order.end());
    return true;
}

bool PrimitiveGraph::dfsVisit(std::shared_ptr<IPrimitiveNode> node, 
                              std::vector<std::shared_ptr<IPrimitiveNode>>& order,
                              std::unordered_set<std::shared_ptr<IPrimitiveNode>>& visited) const {
    if (node->visitInProgress()) {
        return false; // Cycle!
    }
    
    if (node->wasVisited()) {
        return true;
    }
    
    node->setVisitInProgress(true);
    
    // Visit all children
    for (const auto& conn : node->getOutputConnections()) {
        if (auto target = std::static_pointer_cast<IPrimitiveNode>(conn.target.lock())) {
            if (!dfsVisit(target, order, visited)) {
                return false;
            }
        }
    }
    
    node->setVisitInProgress(false);
    node->setVisited(true);
    order.push_back(node);
    return true;
}

size_t PrimitiveGraph::getNodeCount() const {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    return nodes_.size();
}

size_t PrimitiveGraph::getConnectionCount() const {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    size_t count = 0;
    for (const auto& node : nodes_) {
        count += node->getOutputConnections().size();
    }
    return count;
}

std::vector<std::shared_ptr<IPrimitiveNode>> PrimitiveGraph::getTopologicalOrder() const {
    std::vector<std::shared_ptr<IPrimitiveNode>> order;
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    buildTopologicalOrder(order);
    return order;
}

std::unique_ptr<GraphRuntime> PrimitiveGraph::compileRuntime(double sampleRate, int maxBlockSize, int numChannels) {
    return compileGraphRuntime(*this, sampleRate, maxBlockSize, numChannels);
}

// ============================================================================
// OscillatorNode implementation
// ============================================================================

OscillatorNode::OscillatorNode() = default;

void OscillatorNode::setFrequency(float freq) {
    frequency_ = juce::jlimit(1.0f, 20000.0f, freq);
    if (sampleRate_ > 0.0) {
        phaseIncrement_ = 2.0 * M_PI * frequency_ / sampleRate_;
    }
}

void OscillatorNode::setWaveform(int shape) {
    waveform_ = juce::jlimit(0, 4, shape);
}

void OscillatorNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate;
    phaseIncrement_ = 2.0 * M_PI * frequency_ / sampleRate_;
}

void OscillatorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    (void)inputs;
    
    if (outputs.empty() || !enabled_) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }
    
    auto& out = outputs[0];
    for (int i = 0; i < numSamples; ++i) {
        const float sine = static_cast<float>(std::sin(phase_));
        const float phaseNorm = static_cast<float>(phase_ / (2.0 * M_PI));
        const float saw = 2.0f * phaseNorm - 1.0f;
        const float square = (phase_ < juce::MathConstants<double>::pi) ? 1.0f : -1.0f;
        const float triangle = 1.0f - 4.0f * std::abs(phaseNorm - 0.5f);

        float waveformSample = sine;
        switch (waveform_) {
            case 1: waveformSample = saw; break;
            case 2: waveformSample = square; break;
            case 3: waveformSample = triangle; break;
            case 4: waveformSample = 0.45f * sine + 0.55f * saw; break;
            case 0:
            default:
                waveformSample = sine;
                break;
        }

        const float sample = waveformSample * amplitude_;
        for (int ch = 0; ch < out.numChannels; ++ch) {
            out.setSample(ch, i, sample);
        }
        
        phase_ += phaseIncrement_;
        while (phase_ >= 2.0 * M_PI) {
            phase_ -= 2.0 * M_PI;
        }
        while (phase_ < 0) {
            phase_ += 2.0 * M_PI;
        }
    }
}

// ============================================================================
// PlayheadNode implementation
// ============================================================================

PlayheadNode::PlayheadNode() = default;

void PlayheadNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate;
}

void PlayheadNode::process(const std::vector<AudioBufferView>& inputs,
                           std::vector<WritableAudioBufferView>& outputs,
                           int numSamples) {
    (void)inputs; // Unused - playhead has no inputs
    
    if (outputs.empty()) return;
    
    // RT-safe: atomics allow lock-free read in audio thread
    const int loopLen = loopLength_.load(std::memory_order_acquire);
    const bool isPlaying = playing_.load(std::memory_order_acquire);
    const float speedVal = speed_.load(std::memory_order_acquire);
    const bool isReversed = reversed_.load(std::memory_order_acquire);
    
    if (!isPlaying || loopLen <= 0) {
        // Not playing - clear output
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }
    
    // Update position using atomic fetch_add for thread-safe increment
    float increment = speedVal;
    if (isReversed) {
        increment = -increment;
    }
    
    // For now, just advance position (no actual audio output from playhead)
    // Full implementation would output position as CV or trigger
    for (int i = 0; i < numSamples; ++i) {
        int pos = position_.fetch_add(static_cast<int>(increment >= 0 ? 1 : -1), std::memory_order_relaxed);
        
        // Wrap around
        if (increment >= 0) {
            while (pos >= loopLen) {
                pos -= loopLen;
            }
        } else {
            while (pos < 0) {
                pos += loopLen;
            }
        }
        position_.store(pos, std::memory_order_release);
    }
    
    // Clear output (playhead doesn't generate audio, just position)
    if (!outputs.empty()) {
        outputs[0].clear();
    }
}

void PlayheadNode::setLoopLength(int length) {
    loopLength_.store(length, std::memory_order_release);
    position_.store(0, std::memory_order_release);
}

void PlayheadNode::setSpeed(float speed) {
    speed_.store(speed, std::memory_order_release);
}

void PlayheadNode::setReversed(bool reversed) {
    reversed_.store(reversed, std::memory_order_release);
}

void PlayheadNode::play() {
    playing_.store(true, std::memory_order_release);
}

void PlayheadNode::pause() {
    playing_.store(false, std::memory_order_release);
}

void PlayheadNode::stop() {
    playing_.store(false, std::memory_order_release);
    position_.store(0, std::memory_order_release);
}

int PlayheadNode::getLoopLength() const {
    return loopLength_.load(std::memory_order_acquire);
}

float PlayheadNode::getSpeed() const {
    return speed_.load(std::memory_order_acquire);
}

bool PlayheadNode::isReversed() const {
    return reversed_.load(std::memory_order_acquire);
}

bool PlayheadNode::isPlaying() const {
    return playing_.load(std::memory_order_acquire);
}

float PlayheadNode::getNormalizedPosition() const {
    const int loopLen = loopLength_.load(std::memory_order_acquire);
    if (loopLen <= 0) return 0.0f;
    const int pos = position_.load(std::memory_order_acquire);
    return static_cast<float>(pos) / loopLen;
}

// ============================================================================
// FilterNode implementation
// ============================================================================

FilterNode::FilterNode() {
    updateAlpha();
}

void FilterNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate;
    z1_[0] = 0.0f;
    z1_[1] = 0.0f;
    z2_[0] = 0.0f;
    z2_[1] = 0.0f;
    updateAlpha();
}

void FilterNode::setCutoff(float hz) {
    cutoffHz_ = juce::jlimit(20.0f, 18000.0f, hz);
    updateAlpha();
}

void FilterNode::setResonance(float q) {
    resonance_ = juce::jlimit(0.0f, 1.0f, q);
    updateAlpha();
}

void FilterNode::setMix(float mix) {
    mix_ = juce::jlimit(0.0f, 1.0f, mix);
}

void FilterNode::updateAlpha() {
    const float sr = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);
    const float normalized = juce::jlimit(0.0001f, 0.49f, cutoffHz_ / sr);
    const float shaping = 1.0f + resonance_ * 0.6f;
    alpha_ = 1.0f - std::exp(-2.0f * juce::MathConstants<float>::pi * normalized * shaping);
    alpha_ = juce::jlimit(0.0001f, 0.999f, alpha_);
}

void FilterNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    const float dry = 1.0f - mix_;
    const float wet = mix_;
    const float feedback = resonance_ * 0.85f;

    for (int i = 0; i < numSamples; ++i) {
        for (int ch = 0; ch < 2; ++ch) {
            const float in = inputs[ch].getSample(ch, i);
            const size_t idx = static_cast<size_t>(ch);
            const float x = in - feedback * (z2_[idx] - z1_[idx]);
            z1_[idx] += alpha_ * (x - z1_[idx]);
            z2_[idx] += alpha_ * (z1_[idx] - z2_[idx]);
            const float filtered = z2_[idx];
            outputs[ch].setSample(ch, i, in * dry + filtered * wet);
        }
    }
}

// ============================================================================
// DistortionNode implementation
// ============================================================================

DistortionNode::DistortionNode() = default;

void DistortionNode::prepare(double sampleRate, int maxBlockSize) {
    (void)sampleRate;
    (void)maxBlockSize;
}

void DistortionNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }

    const float dry = 1.0f - mix_;
    const float wet = mix_;

    for (int i = 0; i < numSamples; ++i) {
        for (int ch = 0; ch < 2; ++ch) {
            const float in = inputs[ch].getSample(ch, i);
            const float shaped = std::tanh(in * drive_);
            float out = (in * dry + shaped * wet) * output_;
            out = juce::jlimit(-1.0f, 1.0f, out);
            outputs[ch].setSample(ch, i, out);
        }
    }
}

// ============================================================================
// PassthroughNode implementation
// ============================================================================

PassthroughNode::PassthroughNode(int numChannels) : numChannels_(numChannels) {}

void PassthroughNode::prepare(double sampleRate, int maxBlockSize) {
    (void)sampleRate;
    (void)maxBlockSize;
}

void PassthroughNode::process(const std::vector<AudioBufferView>& inputs,
                              std::vector<WritableAudioBufferView>& outputs,
                              int numSamples) {
    // Copy input to output
    for (int ch = 0; ch < numChannels_ && ch < static_cast<int>(inputs.size()) && ch < static_cast<int>(outputs.size()); ++ch) {
        for (int i = 0; i < numSamples; ++i) {
            outputs[ch].setSample(ch, i, inputs[ch].getSample(ch, i));
        }
    }
}

// ============================================================================
// ReverbNode implementation
// ============================================================================

ReverbNode::ReverbNode() {
    params_ = reverb_.getParameters();
}

void ReverbNode::prepare(double sampleRate, int maxBlockSize) {
    reverb_.setSampleRate(sampleRate);
    reverb_.reset();
    
    // Preallocate scratch buffers to avoid per-process allocations
    // RT-safe: allocated once here, reused every process() call
    left_.resize(static_cast<size_t>(maxBlockSize));
    right_.resize(static_cast<size_t>(maxBlockSize));
}

void ReverbNode::process(const std::vector<AudioBufferView>& inputs,
                         std::vector<WritableAudioBufferView>& outputs,
                         int numSamples) {
    if (inputs.size() < 2 || outputs.size() < 2) {
        if (!outputs.empty()) outputs[0].clear();
        if (outputs.size() > 1) outputs[1].clear();
        return;
    }
    
    // RT constraint: must not allocate in process().
    // GraphRuntime guarantees chunking to <= maxBlockSize from prepare().
    if (numSamples > static_cast<int>(left_.size())) {
        // Fail safe: clear outputs rather than allocating.
        outputs[0].clear();
        outputs[1].clear();
        return;
    }

    // Copy inputs to preallocated scratch buffers
    for (int i = 0; i < numSamples; ++i) {
        left_[static_cast<size_t>(i)] = inputs[0].getSample(0, i);
        right_[static_cast<size_t>(i)] = inputs[1].getSample(1, i);
    }

    reverb_.processStereo(left_.data(), right_.data(), numSamples);

    // Copy back to outputs
    for (int i = 0; i < numSamples; ++i) {
        outputs[0].setSample(0, i, left_[static_cast<size_t>(i)]);
        outputs[1].setSample(1, i, right_[static_cast<size_t>(i)]);
    }
}

} // namespace dsp_primitives

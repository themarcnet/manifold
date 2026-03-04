#include "PrimitiveGraph.h"
#include "GraphRuntime.h"

#include <algorithm>
#include <unordered_map>

namespace dsp_primitives {

PrimitiveGraph::PrimitiveGraph() = default;
PrimitiveGraph::~PrimitiveGraph() = default;

void PrimitiveGraph::registerNode(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);
    nodes_.push_back(node);
    prepared_ = false;
}

void PrimitiveGraph::unregisterNode(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    node->removeAllConnections();
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
                connections.end());
        }
    }

    nodes_.erase(std::remove(nodes_.begin(), nodes_.end(), node), nodes_.end());
    prepared_ = false;
}

bool PrimitiveGraph::connect(std::shared_ptr<IPrimitiveNode> from, int outputIndex,
                             std::shared_ptr<IPrimitiveNode> to, int inputIndex) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    std::string error;
    if (!validateConnection(from, to, error)) {
        return false;
    }

    for (const auto& conn : from->getOutputConnections()) {
        if (auto target = std::static_pointer_cast<IPrimitiveNode>(conn.target.lock())) {
            if (target == to && conn.fromOutput == outputIndex && conn.toInput == inputIndex) {
                return true;
            }
        }
    }

    from->addOutputConnection(to, outputIndex, inputIndex);
    prepared_ = false;
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
                    return target == to && conn.fromOutput == outputIndex && conn.toInput == inputIndex;
                }
                return false;
            }),
        connections.end());

    prepared_ = false;
}

void PrimitiveGraph::disconnectAll(std::shared_ptr<IPrimitiveNode> node) {
    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    node->removeAllConnections();
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
                connections.end());
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

    for (auto& node : nodes_) {
        node->resetVisitFlags();
    }

    std::vector<std::shared_ptr<IPrimitiveNode>> order;
    return !buildTopologicalOrder(order);
}

bool PrimitiveGraph::validateConnection(std::shared_ptr<IPrimitiveNode> from,
                                        std::shared_ptr<IPrimitiveNode> to,
                                        std::string& errorMessage) const {
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

    if (from == to) {
        errorMessage = "Cannot connect node to itself";
        return false;
    }

    from->addOutputConnection(to, 0, 0);
    bool hasCycleResult = hasCycle();

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

    for (auto& node : nodes_) {
        node->prepare(sampleRate, maxBlockSize);
    }

    const int maxIntermediateBuffers = 16;
    workingBuffers_.resize(maxIntermediateBuffers);
    for (auto& buffer : workingBuffers_) {
        buffer.setSize(2, maxBlockSize);
    }

    prepared_ = true;
}

void PrimitiveGraph::process(juce::AudioBuffer<float>& outputBuffer) {
    const int numSamples = outputBuffer.getNumSamples();

    if (!prepared_) {
        prepare(sampleRate_, juce::jmax(maxBlockSize_, numSamples));
        if (!prepared_) {
            return;
        }
    }

    std::lock_guard<std::recursive_mutex> lock(nodesMutex_);

    std::vector<std::shared_ptr<IPrimitiveNode>> order;
    if (!buildTopologicalOrder(order)) {
        outputBuffer.clear();
        return;
    }

    std::unordered_map<IPrimitiveNode*, int> nodeToBuffer;
    int bufferIndex = 0;

    for (auto& node : order) {
        if (bufferIndex >= static_cast<int>(workingBuffers_.size())) {
            break;
        }

        juce::AudioBuffer<float> inBuffer(outputBuffer.getNumChannels(), numSamples);
        inBuffer.clear();

        bool hasIncoming = false;

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

        if (!hasIncoming && node->getNumInputs() > 0 && node->acceptsHostInputWhenUnconnected()) {
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

    for (auto& node : nodes_) {
        node->resetVisitFlags();
    }

    std::unordered_set<std::shared_ptr<IPrimitiveNode>> visited;

    for (auto& node : nodes_) {
        if (!node->wasVisited()) {
            if (!dfsVisit(node, order, visited)) {
                return false;
            }
        }
    }

    std::reverse(order.begin(), order.end());
    return true;
}

bool PrimitiveGraph::dfsVisit(std::shared_ptr<IPrimitiveNode> node,
                              std::vector<std::shared_ptr<IPrimitiveNode>>& order,
                              std::unordered_set<std::shared_ptr<IPrimitiveNode>>& visited) const {
    (void)visited;

    if (node->visitInProgress()) {
        return false;
    }

    if (node->wasVisited()) {
        return true;
    }

    node->setVisitInProgress(true);

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

} // namespace dsp_primitives

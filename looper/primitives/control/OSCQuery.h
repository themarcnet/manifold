#pragma once

#include "OSCEndpointRegistry.h"
#include <juce_core/juce_core.h>
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class LooperProcessor;

// ============================================================================
// OSCQueryNode - a node in the OSCQuery address tree.
//
// The tree is built dynamically from endpoint paths. For example, endpoints:
//   /looper/tempo
//   /looper/layer/0/speed
//   /looper/layer/0/volume
//
// Produce the tree:
//   / (root)
//     looper/
//       tempo  [leaf - has endpoint data]
//       layer/
//         0/
//           speed   [leaf]
//           volume  [leaf]
// ============================================================================

struct OSCQueryNode {
    juce::String name;           // segment name (e.g. "tempo", "0", "layer")
    juce::String fullPath;       // full OSC path (e.g. "/looper/tempo")

    // If this node IS an endpoint, this holds the metadata.
    // A container node may also be an endpoint (e.g. /looper/layer is both
    // a container for /looper/layer/0 and an endpoint for SetActiveLayer).
    bool isEndpoint = false;
    OSCEndpoint endpoint;

    // Children keyed by segment name
    std::map<juce::String, std::unique_ptr<OSCQueryNode>> children;

    // Insert an endpoint into this subtree, creating intermediate nodes as needed.
    void insert(const OSCEndpoint& ep, const juce::StringArray& segments, int depth);

    // Serialize this node (and all children) to OSCQuery JSON.
    juce::String toJSON(int indent = 0) const;
};

// ============================================================================
// OSCQueryServer - HTTP server for OSCQuery protocol.
//
// Builds the address tree dynamically from OSCEndpointRegistry, responds to
// HTTP GET requests with JSON, and queries AtomicState for live VALUES.
// ============================================================================

class OSCQueryServer {
public:
    OSCQueryServer();
    ~OSCQueryServer();

    void start(LooperProcessor* processor, OSCEndpointRegistry* registry, int httpPort, int oscPort);
    void stop();

    bool isRunning() const { return running.load(); }

    // Rebuild the tree from the registry. Call when endpoints change.
    void rebuildTree();

private:
    void httpLoop();
    void handleHttpRequest(juce::StreamingSocket* client, const juce::String& request);

    juce::String buildOSCQueryInfo();
    juce::String buildHostInfo();
    juce::String queryValue(const juce::String& oscPath);
    juce::String handleTargetsRequest(const juce::String& method, const juce::String& body);

    // Build the tree from the registry
    void buildTree();

    LooperProcessor* owner = nullptr;
    OSCEndpointRegistry* registry = nullptr;
    int oscUdpPort = 9000;

    juce::StreamingSocket* httpSocket = nullptr;
    int httpPort = 9001;
    std::atomic<bool> running{false};
    std::thread httpThread;

    // The address tree
    std::unique_ptr<OSCQueryNode> root;
    mutable std::mutex treeMutex;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(OSCQueryServer)
};

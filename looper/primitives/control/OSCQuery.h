#pragma once

#include "OSCEndpointRegistry.h"
#include "OSCPacketBuilder.h"
#include <juce_core/juce_core.h>
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <set>
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
// WebSocket types for OSCQuery LISTEN/IGNORE protocol (RFC 6455)
// ============================================================================

struct WebSocketClient {
    std::unique_ptr<juce::StreamingSocket> socket;
    std::set<juce::String> listenPaths;   // OSC paths this client is subscribed to
    mutable std::mutex listenMutex;
    std::atomic<bool> connected{true};
    std::thread readThread;               // reads frames from this client

    // State snapshot for diff-based streaming (per-client)
    struct StateCache {
        float tempo = 0.0f;
        bool isRecording = false;
        bool overdubEnabled = false;
        int recordMode = -1;
        int activeLayer = -1;
        float masterVolume = -1.0f;

        struct LayerCache {
            int state = -1;
            float speed = -999.0f;
            float volume = -999.0f;
            bool reversed = false;
            float position = -1.0f;
            float bars = -1.0f;
        };
        static const int MAX_LAYERS = 4;
        LayerCache layers[MAX_LAYERS];

        // Signature of last sent custom endpoint values, keyed by path.
        // Example: "/experimental/xy" -> "0.100000|0.800000"
        std::map<juce::String, juce::String> customSignatures;
    };
    StateCache cache;

    ~WebSocketClient() {
        connected.store(false);
        if (socket) socket->close();
        if (readThread.joinable()) readThread.join();
    }
};

// WebSocket frame opcodes (RFC 6455 section 5.2)
enum class WSOpcode : uint8_t {
    Continuation = 0x0,
    Text         = 0x1,
    Binary       = 0x2,
    Close        = 0x8,
    Ping         = 0x9,
    Pong         = 0xA
};

// ============================================================================
// OSCQueryServer - HTTP + WebSocket server for OSCQuery protocol.
//
// Builds the address tree dynamically from OSCEndpointRegistry, responds to
// HTTP GET requests with JSON, queries AtomicState for live VALUES, and
// maintains WebSocket connections for LISTEN/IGNORE value streaming.
// ============================================================================

class OSCQueryServer {
public:
    OSCQueryServer();
    ~OSCQueryServer();

    void start(LooperProcessor* processor, OSCEndpointRegistry* registry, int httpPort, int oscPort);
    void stop();

    bool isRunning() const { return running.load(); }

    // Query a single OSC path and return OSCQuery VALUE JSON payload.
    juce::String queryPathValue(const juce::String& oscPath);

    // Rebuild the tree from the registry. Call when endpoints change.
    void rebuildTree();

private:
    // --- HTTP ---
    void httpLoop();
    void handleHttpRequest(juce::StreamingSocket* client, const juce::String& request,
                           const juce::String& rawHeaders);

    juce::String buildOSCQueryInfo();
    juce::String buildHostInfo();
    juce::String queryValue(const juce::String& oscPath);
    juce::String handleTargetsRequest(const juce::String& method, const juce::String& body);

    // --- WebSocket ---
    // Upgrade an HTTP connection to WebSocket (RFC 6455 handshake)
    bool performWebSocketUpgrade(juce::StreamingSocket* client, const juce::String& rawHeaders);

    // Compute Sec-WebSocket-Accept from client key
    juce::String computeAcceptKey(const juce::String& clientKey);

    // Frame I/O
    bool readWebSocketFrame(juce::StreamingSocket* sock, WSOpcode& opcode,
                            std::vector<uint8_t>& payload);
    bool writeWebSocketFrame(juce::StreamingSocket* sock, WSOpcode opcode,
                             const void* data, size_t length);

    // Per-client read loop (runs on client's readThread)
    void wsClientReadLoop(WebSocketClient* client);

    // Handle parsed LISTEN/IGNORE commands
    void handleWSCommand(WebSocketClient* client, const juce::String& jsonText);

    // Broadcast loop for WebSocket value streaming
    void wsBroadcastLoop();

    // Send value update to a single client for a single path
    void sendValueToClient(WebSocketClient* client, const juce::String& oscPath,
                           const std::vector<juce::var>& args);

    // --- Tree ---
    void buildTree();

    // --- Members ---
    LooperProcessor* owner = nullptr;
    OSCEndpointRegistry* registry = nullptr;
    int oscUdpPort = 9000;

    juce::StreamingSocket* httpSocket = nullptr;
    int httpPort = 9001;
    std::atomic<bool> running{false};
    std::thread httpThread;

    // WebSocket clients
    std::vector<std::unique_ptr<WebSocketClient>> wsClients;
    mutable std::mutex wsClientsMutex;
    std::thread wsBroadcastThread;

    // The address tree
    std::unique_ptr<OSCQueryNode> root;
    mutable std::mutex treeMutex;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(OSCQueryServer)
};

#include "OSCQuery.h"
#include "../../engine/LooperProcessor.h"
#include <cstring>

// ============================================================================
// OSCQueryNode - tree building and JSON serialization
// ============================================================================

void OSCQueryNode::insert(const OSCEndpoint& ep, const juce::StringArray& segments, int depth) {
    if (depth >= segments.size()) {
        // We've consumed all segments - this node IS the endpoint.
        isEndpoint = true;
        endpoint = ep;
        return;
    }

    const juce::String& seg = segments[depth];

    auto it = children.find(seg);
    if (it == children.end()) {
        auto node = std::make_unique<OSCQueryNode>();
        node->name = seg;

        // Build full path from segments consumed so far
        juce::String path;
        for (int i = 0; i <= depth; ++i) {
            path += "/" + segments[i];
        }
        node->fullPath = path;

        it = children.emplace(seg, std::move(node)).first;
    }

    it->second->insert(ep, segments, depth + 1);
}

static juce::String indent(int level) {
    juce::String s;
    for (int i = 0; i < level; ++i) s += "  ";
    return s;
}

juce::String OSCQueryNode::toJSON(int ind) const {
    juce::String json;
    json += indent(ind) + "{\n";
    json += indent(ind + 1) + "\"FULL_PATH\": \"" + fullPath + "\"";

    if (isEndpoint) {
        if (endpoint.type.isNotEmpty()) {
            json += ",\n" + indent(ind + 1) + "\"TYPE\": \"" + endpoint.type + "\"";
        }
        json += ",\n" + indent(ind + 1) + "\"ACCESS\": " + juce::String(endpoint.access);

        if (endpoint.rangeMin != endpoint.rangeMax) {
            // Use float formatting for non-integer ranges
            bool useFloat = (endpoint.rangeMin != (int)endpoint.rangeMin) ||
                            (endpoint.rangeMax != (int)endpoint.rangeMax);
            juce::String minStr = useFloat ? juce::String(endpoint.rangeMin, 1)
                                           : juce::String((int)endpoint.rangeMin);
            juce::String maxStr = useFloat ? juce::String(endpoint.rangeMax, 1)
                                           : juce::String((int)endpoint.rangeMax);
            json += ",\n" + indent(ind + 1) + "\"RANGE\": [{\"MIN\": " + minStr +
                    ", \"MAX\": " + maxStr + "}]";
        }

        json += ",\n" + indent(ind + 1) + "\"DESCRIPTION\": \"" + endpoint.description + "\"";
    }

    if (!children.empty()) {
        json += ",\n" + indent(ind + 1) + "\"CONTENTS\": {\n";

        int count = 0;
        int total = (int)children.size();
        for (const auto& [key, child] : children) {
            json += indent(ind + 2) + "\"" + key + "\": ";
            json += child->toJSON(ind + 2).trimStart();
            if (++count < total) json += ",";
            json += "\n";
        }

        json += indent(ind + 1) + "}";
    }

    json += "\n" + indent(ind) + "}";
    return json;
}

// ============================================================================
// OSCQueryServer implementation
// ============================================================================

OSCQueryServer::OSCQueryServer() = default;

OSCQueryServer::~OSCQueryServer() {
    stop();
}

void OSCQueryServer::start(LooperProcessor* processor, OSCEndpointRegistry* reg,
                           int httpPort_, int oscPort_) {
    owner = processor;
    registry = reg;
    httpPort = httpPort_;
    oscUdpPort = oscPort_;

    // Build the address tree from registry
    buildTree();

    httpSocket = new juce::StreamingSocket();
    if (!httpSocket->createListener(httpPort)) {
        delete httpSocket;
        httpSocket = nullptr;
        return;
    }

    running = true;
    httpThread = std::thread(&OSCQueryServer::httpLoop, this);
}

void OSCQueryServer::stop() {
    running = false;

    if (httpSocket) {
        httpSocket->close();
        delete httpSocket;
        httpSocket = nullptr;
    }

    if (httpThread.joinable()) {
        httpThread.join();
    }
}

void OSCQueryServer::rebuildTree() {
    buildTree();
}

void OSCQueryServer::buildTree() {
    if (!registry) return;

    auto newRoot = std::make_unique<OSCQueryNode>();
    newRoot->name = "";
    newRoot->fullPath = "/";

    auto endpoints = registry->getAllEndpoints();

    for (const auto& ep : endpoints) {
        // Split path into segments: "/looper/tempo" -> ["looper", "tempo"]
        juce::String path = ep.path;
        if (path.startsWithChar('/')) path = path.substring(1);

        juce::StringArray segments;
        segments.addTokens(path, "/", "");

        if (segments.isEmpty()) continue;

        newRoot->insert(ep, segments, 0);
    }

    std::lock_guard<std::mutex> lock(treeMutex);
    root = std::move(newRoot);
}

void OSCQueryServer::httpLoop() {
    while (running.load()) {
        if (!httpSocket) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            continue;
        }

        auto* client = httpSocket->waitForNextConnection();
        if (client) {
            int ready = client->waitUntilReady(true, 1000);
            if (ready > 0) {
                char buffer[4096];
                int bytesRead = client->read(buffer, sizeof(buffer) - 1, false);
                if (bytesRead > 0) {
                    buffer[bytesRead] = '\0';
                    juce::String request(buffer, bytesRead);
                    handleHttpRequest(client, request);
                }
            }
            client->close();
            delete client;
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
}

void OSCQueryServer::handleHttpRequest(juce::StreamingSocket* client,
                                       const juce::String& request) {
    juce::StringArray lines;
    lines.addLines(request);
    if (lines.isEmpty()) return;

    juce::StringArray parts;
    parts.addTokens(lines[0], " ", "");
    if (parts.size() < 2) return;

    juce::String method = parts[0];
    juce::String path = parts[1].trim();

    juce::String response;
    juce::String contentType = "application/json";

    // Extract query string
    juce::String query;
    int queryPos = path.indexOf("?");
    if (queryPos > 0) {
        query = path.substring(queryPos + 1);
        path = path.substring(0, queryPos);
    }

    if (method == "GET") {
        if (query == "HOST_INFO") {
            response = buildHostInfo();
        }
        else if (path == "/info" || path == "/" || path.isEmpty()) {
            response = buildOSCQueryInfo();
        }
        else if (path.startsWith("/osc")) {
            // Value query: /osc/looper/tempo -> query /looper/tempo
            juce::String oscPath = path.substring(4);
            if (oscPath.isEmpty()) oscPath = "/";
            response = queryValue(oscPath);
        }
        else {
            response = "{\"error\":\"not found\"}";
        }
    }
    else if (method == "POST") {
        if (path == "/api/targets") {
            juce::String body = request.fromFirstOccurrenceOf("\r\n\r\n", false, false);
            if (body.isEmpty())
                body = request.fromFirstOccurrenceOf("\n\n", false, false);
            response = handleTargetsRequest(method, body);
        } else {
            response = "{\"error\":\"unknown endpoint\"}";
        }
    }
    else {
        response = "{\"error\":\"method not allowed\"}";
    }

    juce::String header = "HTTP/1.1 200 OK\r\n";
    header += "Content-Type: " + contentType + "\r\n";
    header += "Content-Length: " + juce::String(response.length()) + "\r\n";
    header += "Access-Control-Allow-Origin: *\r\n";
    header += "Connection: close\r\n";
    header += "\r\n";

    client->write(header.toRawUTF8(), (int)header.getNumBytesAsUTF8());
    client->write(response.toRawUTF8(), (int)response.getNumBytesAsUTF8());
}

juce::String OSCQueryServer::buildOSCQueryInfo() {
    std::lock_guard<std::mutex> lock(treeMutex);
    if (!root) return "{}";
    return root->toJSON(0);
}

juce::String OSCQueryServer::buildHostInfo() {
    juce::String json = "{\n";
    json += "  \"NAME\": \"Looper OSCQuery Server\",\n";
    json += "  \"EXTENSIONS\": {\n";
    json += "    \"ACCESS\": true,\n";
    json += "    \"VALUE\": true,\n";
    json += "    \"RANGE\": true,\n";
    json += "    \"DESCRIPTION\": true,\n";
    json += "    \"TAGS\": true,\n";
    json += "    \"LISTEN\": false,\n";
    json += "    \"PATH_CHANGED\": false\n";
    json += "  },\n";
    json += "  \"OSC_IP\": \"0.0.0.0\",\n";
    json += "  \"OSC_PORT\": " + juce::String(oscUdpPort) + ",\n";
    json += "  \"OSC_TRANSPORT\": \"UDP\"\n";
    json += "}\n";
    return json;
}

juce::String OSCQueryServer::queryValue(const juce::String& oscPath) {
    if (!owner) return "{\"error\":\"no processor\"}";

    auto& state = owner->getControlServer().getAtomicState();

    // Normalize: accept both /tempo and /looper/tempo
    juce::String path = oscPath;
    if (!path.startsWith("/looper/") && path.startsWith("/")) {
        path = "/looper" + path;
    }

    // --- Global values ---
    if (path == "/looper/tempo") {
        return "{\"VALUE\": " + juce::String(state.tempo.load(), 2) + "}";
    }
    if (path == "/looper/recording") {
        return "{\"VALUE\": " + juce::String(state.isRecording.load() ? 1 : 0) + "}";
    }
    if (path == "/looper/overdub") {
        return "{\"VALUE\": " + juce::String(state.overdubEnabled.load() ? 1 : 0) + "}";
    }
    if (path == "/looper/mode") {
        int mode = state.recordMode.load();
        const char* modeStr = (mode == 0) ? "firstLoop" :
                              (mode == 1) ? "freeMode" :
                              (mode == 2) ? "traditional" : "retrospective";
        return "{\"VALUE\": \"" + juce::String(modeStr) + "\"}";
    }
    if (path == "/looper/layer") {
        return "{\"VALUE\": " + juce::String(state.activeLayer.load()) + "}";
    }
    if (path == "/looper/volume") {
        return "{\"VALUE\": " + juce::String(state.masterVolume.load(), 3) + "}";
    }

    // --- Per-layer values ---
    if (path.startsWith("/looper/layer/")) {
        juce::String rest = path.fromFirstOccurrenceOf("/looper/layer/", false, false);
        int slashPos = rest.indexOf("/");
        if (slashPos > 0) {
            int layerIdx = rest.substring(0, slashPos).getIntValue();
            juce::String prop = rest.substring(slashPos + 1);

            if (layerIdx >= 0 && layerIdx < AtomicState::MAX_LAYERS) {
                auto& ls = state.layers[layerIdx];

                if (prop == "speed") {
                    return "{\"VALUE\": " + juce::String(ls.speed.load(), 3) + "}";
                }
                if (prop == "volume") {
                    return "{\"VALUE\": " + juce::String(ls.volume.load(), 3) + "}";
                }
                if (prop == "mute") {
                    int s = ls.state.load();
                    // State 4 = Muted (from LooperLayer::State enum)
                    return "{\"VALUE\": " + juce::String(s == 4 ? 1 : 0) + "}";
                }
                if (prop == "reverse") {
                    return "{\"VALUE\": " + juce::String(ls.reversed.load() ? 1 : 0) + "}";
                }
                if (prop == "length") {
                    return "{\"VALUE\": " + juce::String(ls.length.load()) + "}";
                }
                if (prop == "position") {
                    int len = ls.length.load();
                    float pos = (len > 0) ? (float)ls.playheadPos.load() / (float)len : 0.0f;
                    return "{\"VALUE\": " + juce::String(pos, 4) + "}";
                }
                if (prop == "bars") {
                    return "{\"VALUE\": " + juce::String(ls.numBars.load(), 4) + "}";
                }
                if (prop == "state") {
                    int s = ls.state.load();
                    const char* stateStr = (s == 0) ? "empty" :
                                           (s == 1) ? "playing" :
                                           (s == 2) ? "stopped" :
                                           (s == 3) ? "paused" :
                                           (s == 4) ? "muted" :
                                           (s == 5) ? "recording" : "unknown";
                    return "{\"VALUE\": \"" + juce::String(stateStr) + "\"}";
                }
            }
        }
        // Layer index with no prop = layer selector value
        else {
            int layerIdx = rest.getIntValue();
            if (layerIdx >= 0 && layerIdx < AtomicState::MAX_LAYERS) {
                auto& ls = state.layers[layerIdx];
                int s = ls.state.load();
                const char* stateStr = (s == 0) ? "empty" :
                                       (s == 1) ? "playing" :
                                       (s == 2) ? "stopped" :
                                       (s == 3) ? "paused" :
                                       (s == 4) ? "muted" : "unknown";
                return "{\"VALUE\": \"" + juce::String(stateStr) + "\"}";
            }
        }
    }

    return "{\"error\":\"not found\"}";
}

juce::String OSCQueryServer::handleTargetsRequest(const juce::String& /*method*/,
                                                  const juce::String& body) {
    if (!owner) return "{\"error\":\"no processor\"}";

    auto& oscServer = owner->getOSCServer();

    if (body.contains("add:")) {
        juce::String target = body.fromFirstOccurrenceOf("add:", false, false).trim();
        oscServer.addOutTarget(target);
        return "{\"status\":\"added\"}";
    }
    if (body.contains("remove:")) {
        juce::String target = body.fromFirstOccurrenceOf("remove:", false, false).trim();
        oscServer.removeOutTarget(target);
        return "{\"status\":\"removed\"}";
    }

    // List targets
    juce::StringArray targets = oscServer.getOutTargets();
    juce::String json = "{\"targets\":[";
    for (int i = 0; i < targets.size(); ++i) {
        if (i > 0) json += ",";
        json += "\"" + targets[i] + "\"";
    }
    json += "]}";
    return json;
}

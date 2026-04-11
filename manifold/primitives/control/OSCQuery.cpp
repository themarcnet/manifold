#include "OSCQuery.h"
#include "SHA1.h"
#include "OSCPacketBuilder.h"
#include "EndpointResolver.h"
#include "OSCServer.h"
#include "../scripting/ScriptableProcessor.h"
#include "../scripting/LuaEngine.h"
#include "../core/Settings.h"
#include <cstring>
#include <cmath>

namespace {
constexpr double kOscQueryFloatEpsilon = 1.0e-9;

bool nearlyEqual(double a, double b) {
    return std::abs(a - b) < kOscQueryFloatEpsilon;
}
}

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

static juce::String escapeJsonString(const juce::String& s) {
    juce::String out;
    for (int i = 0; i < s.length(); ++i) {
        juce::juce_wchar c = s[i];
        if (c == '\\') out += "\\\\";
        else if (c == '"') out += "\\\"";
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else out += juce::String::charToString(c);
    }
    return out;
}

static juce::String varToJsonLiteral(const juce::var& v) {
    if (v.isString()) {
        return "\"" + escapeJsonString(v.toString()) + "\"";
    }
    if (v.isBool()) {
        return (bool)v ? "true" : "false";
    }
    if (v.isInt()) {
        return juce::String((int)v);
    }
    if (v.isInt64()) {
        return juce::String((double)v, 0);
    }
    if (v.isDouble()) {
        return juce::String((double)v, 6);
    }
    return "null";
}

static juce::String argsToValueJson(const std::vector<juce::var>& args) {
    if (args.empty()) {
        return "null";
    }
    if (args.size() == 1) {
        return varToJsonLiteral(args[0]);
    }

    juce::String arr = "[";
    for (size_t i = 0; i < args.size(); ++i) {
        if (i > 0) arr += ",";
        arr += varToJsonLiteral(args[i]);
    }
    arr += "]";
    return arr;
}

static juce::String argsSignature(const std::vector<juce::var>& args) {
    juce::String sig;
    for (size_t i = 0; i < args.size(); ++i) {
        if (i > 0) sig += "|";
        if (args[i].isString()) sig += "s:" + args[i].toString();
        else if (args[i].isBool()) sig += juce::String("b:") + ((bool)args[i] ? "1" : "0");
        else if (args[i].isInt()) sig += "i:" + juce::String((int)args[i]);
        else if (args[i].isInt64()) sig += "h:" + juce::String((double)args[i], 0);
        else if (args[i].isDouble()) sig += "f:" + juce::String((double)args[i], 6);
        else sig += "n:null";
    }
    return sig;
}

static juce::String normalizeQueryPath(const juce::String& oscPath) {
    return oscPath;
}

static bool tryReadProjectedValue(const juce::var& stateBundle,
                                  const juce::String& path,
                                  juce::var& outValue) {
    auto* rootObject = stateBundle.getDynamicObject();
    if (!rootObject) {
        return false;
    }

    const juce::var paramsVar = rootObject->getProperty("params");
    if (auto* paramsObject = paramsVar.getDynamicObject()) {
        const juce::var directValue = paramsObject->getProperty(path);
        if (!directValue.isVoid()) {
            outValue = directValue;
            return true;
        }
    }
    return false;
}

static juce::File resolveManifestFromScriptPath(const juce::File& scriptFile) {
    if (!scriptFile.existsAsFile()) {
        return {};
    }
    if (scriptFile.getFileName().equalsIgnoreCase("manifold.project.json5")) {
        return scriptFile;
    }

    const auto parentManifest = scriptFile.getParentDirectory().getChildFile("manifold.project.json5");
    if (parentManifest.existsAsFile()) {
        return parentManifest;
    }

    const auto grandParent = scriptFile.getParentDirectory().getParentDirectory();
    const auto grandParentManifest = grandParent.getChildFile("manifold.project.json5");
    if (grandParentManifest.existsAsFile()) {
        return grandParentManifest;
    }

    return {};
}

static juce::File resolveCurrentProjectManifest(ScriptableProcessor* owner) {
    if (owner != nullptr) {
        if (auto* luaEngine = owner->getControlServer().getLuaEngine()) {
            const auto manifest = resolveManifestFromScriptPath(luaEngine->getCurrentScriptFile());
            if (manifest.existsAsFile()) {
                return manifest;
            }
        }
    }

    const auto defaultUiScript = Settings::getInstance().getDefaultUiScript();
    if (defaultUiScript.isNotEmpty()) {
        const auto manifest = resolveManifestFromScriptPath(juce::File(defaultUiScript));
        if (manifest.existsAsFile()) {
            return manifest;
        }
    }

    return {};
}

static juce::File resolveProjectAssetRef(const juce::File& projectRoot, const juce::String& ref) {
    if (ref.isEmpty()) {
        return {};
    }
    if (juce::File::isAbsolutePath(ref)) {
        return juce::File(ref);
    }
    return projectRoot.getChildFile(ref);
}

static juce::String buildUiMetaResponse(ScriptableProcessor* owner) {
    const auto manifestFile = resolveCurrentProjectManifest(owner);
    if (!manifestFile.existsAsFile()) {
        return "{\"error\":\"ui metadata unavailable\"}";
    }

    const auto parsed = juce::JSON::parse(manifestFile);
    if (!parsed.isObject()) {
        return "{\"error\":\"project manifest is not valid JSON/JSON5 subset\"}";
    }

    auto* source = parsed.getDynamicObject();
    if (source == nullptr) {
        return "{\"error\":\"project manifest root is invalid\"}";
    }

    juce::DynamicObject::Ptr result = new juce::DynamicObject();
    result->setProperty("name", source->getProperty("name"));
    result->setProperty("version", source->getProperty("version"));
    result->setProperty("description", source->getProperty("description"));
    result->setProperty("manifestPath", manifestFile.getFullPathName());
    result->setProperty("projectRoot", manifestFile.getParentDirectory().getFullPathName());

    if (source->hasProperty("ui")) {
        result->setProperty("ui", source->getProperty("ui"));
    }
    if (source->hasProperty("plugin")) {
        result->setProperty("plugin", source->getProperty("plugin"));
    }

    juce::DynamicObject::Ptr capabilities = new juce::DynamicObject();
    capabilities->setProperty("genericRemote", true);
    capabilities->setProperty("layoutRemote", manifestFile.getParentDirectory().getChildFile("web-remote.layout.json").existsAsFile());
    capabilities->setProperty("customSurface", true);
    result->setProperty("capabilities", juce::var(capabilities.get()));

    return juce::JSON::toString(juce::var(result.get()));
}

static juce::String buildUiLayoutResponse(ScriptableProcessor* owner) {
    const auto manifestFile = resolveCurrentProjectManifest(owner);
    if (!manifestFile.existsAsFile()) {
        return "{\"error\":\"layout unavailable\"}";
    }

    const auto projectRoot = manifestFile.getParentDirectory();
    const auto sidecar = projectRoot.getChildFile("web-remote.layout.json");
    if (sidecar.existsAsFile()) {
        const auto parsed = juce::JSON::parse(sidecar);
        if (!parsed.isVoid()) {
            return juce::JSON::toString(parsed);
        }
    }

    const auto parsedManifest = juce::JSON::parse(manifestFile);
    if (parsedManifest.isObject()) {
        auto* obj = parsedManifest.getDynamicObject();
        if (obj != nullptr && obj->hasProperty("ui")) {
            const auto uiVar = obj->getProperty("ui");
            if (uiVar.isObject()) {
                auto* uiObj = uiVar.getDynamicObject();
                if (uiObj != nullptr && uiObj->hasProperty("root")) {
                    const auto layoutCandidate = resolveProjectAssetRef(projectRoot, uiObj->getProperty("root").toString());
                    if (layoutCandidate.existsAsFile()) {
                        juce::DynamicObject::Ptr fallback = new juce::DynamicObject();
                        fallback->setProperty("error", "layout sidecar missing");
                        fallback->setProperty("uiRoot", layoutCandidate.getFullPathName());
                        fallback->setProperty("projectRoot", projectRoot.getFullPathName());
                        return juce::JSON::toString(juce::var(fallback.get()));
                    }
                }
            }
        }
    }

    return "{\"error\":\"layout unavailable\"}";
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

        if (!nearlyEqual(endpoint.rangeMin, endpoint.rangeMax)) {
            // Use float formatting for non-integer ranges
            const bool useFloat = !nearlyEqual(endpoint.rangeMin, std::trunc(endpoint.rangeMin)) ||
                                  !nearlyEqual(endpoint.rangeMax, std::trunc(endpoint.rangeMax));
            juce::String minStr = useFloat ? juce::String(endpoint.rangeMin, 1)
                                           : juce::String(static_cast<int>(std::trunc(endpoint.rangeMin)));
            juce::String maxStr = useFloat ? juce::String(endpoint.rangeMax, 1)
                                           : juce::String(static_cast<int>(std::trunc(endpoint.rangeMax)));
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
// OSCQueryServer lifecycle
// ============================================================================

OSCQueryServer::OSCQueryServer() = default;

OSCQueryServer::~OSCQueryServer() {
    stop();
}

void OSCQueryServer::setContext(ScriptableProcessor* processor,
                                OSCEndpointRegistry* reg) {
    owner = processor;
    registry = reg;
    buildTree();
}

void OSCQueryServer::start(ScriptableProcessor* processor, OSCEndpointRegistry* reg,
                           int httpPort_, int oscPort_) {
    setContext(processor, reg);
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
    wsBroadcastThread = std::thread(&OSCQueryServer::wsBroadcastLoop, this);
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

    if (wsBroadcastThread.joinable()) {
        wsBroadcastThread.join();
    }

    // Clean up client threads (after http/ws threads joined, no concurrent sends)
    {
        std::lock_guard<std::mutex> lock(wsClientsMutex);
        for (auto& client : wsClients) {
            client->connected.store(false);
            if (client->socket) client->socket->close();
        }
        wsClients.clear();  // destructors join readThreads
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
        // Split path into segments: "/core/behavior/tempo" -> ["core", "behavior", "tempo"]
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

// ============================================================================
// HTTP accept loop
// ============================================================================

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
                char buffer[8192];
                int totalRead = 0;
                int bytesRead = client->read(buffer, sizeof(buffer) - 1, false);
                if (bytesRead > 0) {
                    totalRead = bytesRead;

                    // Check if we have a Content-Length but body hasn't arrived yet.
                    // Some HTTP clients (e.g. Python http.client) send headers and body
                    // as separate TCP writes.
                    buffer[totalRead] = '\0';
                    juce::String partial(buffer, static_cast<size_t>(totalRead));
                    int headerEnd = partial.indexOf("\r\n\r\n");
                    if (headerEnd < 0) headerEnd = partial.indexOf("\n\n");

                    if (headerEnd >= 0) {
                        // Extract Content-Length from headers
                        int clPos = partial.indexOfIgnoreCase("Content-Length:");
                        if (clPos >= 0 && clPos < headerEnd) {
                            int clEnd = partial.indexOf(clPos, "\r\n");
                            if (clEnd < 0) clEnd = partial.indexOf(clPos, "\n");
                            juce::String clVal = partial.substring(clPos + 15, clEnd).trim();
                            int contentLength = clVal.getIntValue();

                            // How much body do we have so far?
                            int bodyStart = partial.indexOf("\r\n\r\n");
                            int bodyOffset = (bodyStart >= 0) ? bodyStart + 4 : partial.indexOf("\n\n") + 2;
                            int bodyReceived = totalRead - bodyOffset;

                            // Read remaining body bytes if needed
                            while (bodyReceived < contentLength && totalRead < (int)sizeof(buffer) - 1) {
                                int readyAgain = client->waitUntilReady(true, 500);
                                if (readyAgain <= 0) break;
                                int more = client->read(buffer + totalRead,
                                                        (int)sizeof(buffer) - 1 - totalRead, false);
                                if (more <= 0) break;
                                totalRead += more;
                                bodyReceived += more;
                            }
                        }
                    }

                    buffer[totalRead] = '\0';
                    juce::String request(buffer, static_cast<size_t>(totalRead));

                    // Extract raw headers for WebSocket upgrade detection
                    juce::String rawHeaders;
                    int hdrEnd = request.indexOf("\r\n\r\n");
                    if (hdrEnd >= 0)
                        rawHeaders = request.substring(0, hdrEnd);
                    else {
                        hdrEnd = request.indexOf("\n\n");
                        if (hdrEnd >= 0) rawHeaders = request.substring(0, hdrEnd);
                        else rawHeaders = request;
                    }

                    // Check for WebSocket upgrade BEFORE normal HTTP handling
                    bool hasUpgrade = rawHeaders.containsIgnoreCase("Upgrade:") &&
                                     rawHeaders.containsIgnoreCase("websocket");
                    bool hasConnection = rawHeaders.containsIgnoreCase("Connection:");

                    if (hasUpgrade && hasConnection) {
                        // This is a WebSocket upgrade request
                        if (performWebSocketUpgrade(client, rawHeaders)) {
                            // Client was successfully upgraded - don't close/delete it.
                            // It's now owned by a WebSocketClient in wsClients.
                            continue;  // skip the close/delete below
                        }
                        // Upgrade failed - fall through to close
                    } else {
                        handleHttpRequest(client, request, rawHeaders);
                    }
                }
            }
            client->close();
            delete client;
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }
}

// ============================================================================
// HTTP request handler (non-WebSocket requests)
// ============================================================================

void OSCQueryServer::handleHttpRequest(juce::StreamingSocket* client,
                                       const juce::String& request,
                                       const juce::String& /*rawHeaders*/) {
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
    int statusCode = 200;
    juce::String statusText = "OK";

    auto readRequestBody = [&request]() {
        juce::String body = request.fromFirstOccurrenceOf("\r\n\r\n", false, false);
        if (body.isEmpty()) {
            body = request.fromFirstOccurrenceOf("\n\n", false, false);
        }
        return body;
    };

    // Extract query string
    juce::String query;
    int queryPos = path.indexOf("?");
    if (queryPos > 0) {
        query = path.substring(queryPos + 1);
        path = path.substring(0, queryPos);
    }

    if (method == "OPTIONS") {
        response = "";
    }
    else if (method == "GET") {
        if (query == "HOST_INFO") {
            response = buildHostInfo();
        }
        else if (query.startsWith("LISTEN=")) {
            // OSCQuery LISTEN extension via HTTP query parameter.
            // Extract the OSC address and return the current value.
            juce::String listenAddr = query.fromFirstOccurrenceOf("LISTEN=", false, false);
            listenAddr = juce::URL::removeEscapeChars(listenAddr);
            response = queryValue(listenAddr);
        }
        else if (path == "/info" || path == "/" || path.isEmpty()) {
            response = buildOSCQueryInfo();
        }
        else if (path == "/ui/meta") {
            response = buildUiMetaResponse(owner);
            if (response.contains("\"error\"")) {
                statusCode = 404;
                statusText = "Not Found";
            }
        }
        else if (path == "/ui/layout") {
            response = buildUiLayoutResponse(owner);
            if (response.contains("\"error\"")) {
                statusCode = 404;
                statusText = "Not Found";
            }
        }
        else if (path.startsWith("/osc")) {
            // Value query: /osc/core/behavior/tempo -> query /core/behavior/tempo
            juce::String oscPath = path.substring(4);
            if (oscPath.isEmpty()) oscPath = "/";
            response = queryValue(oscPath);
        }
        else {
            // Try as an OSCQuery path lookup (some clients query endpoint paths directly)
            juce::String oscPath = path;
            juce::String val = queryValue(oscPath);
            if (!val.contains("\"error\"")) {
                response = val;
            } else {
                response = "{\"error\":\"not found\"}";
                statusCode = 404;
                statusText = "Not Found";
            }
        }
    }
    else if (method == "POST") {
        if (path == "/api/targets") {
            response = handleTargetsRequest(method, readRequestBody());
        } else if (path == "/api/command") {
            juce::String body = readRequestBody().trim();
            juce::String upper = body.toUpperCase();
            if (!(upper.startsWith("SET ") || upper.startsWith("TRIGGER "))) {
                response = "{\"error\":\"only SET and TRIGGER commands are allowed\"}";
                statusCode = 400;
                statusText = "Bad Request";
            } else if (!owner) {
                response = "{\"error\":\"no processor\"}";
                statusCode = 500;
                statusText = "Internal Server Error";
            } else {
                const std::string result = owner->getControlServer().runCommand(body.toStdString());
                if (result.rfind("OK", 0) == 0) {
                    response = "{\"ok\":true,\"result\":" + varToJsonLiteral(juce::String(result)) + "}";
                } else {
                    response = "{\"ok\":false,\"result\":" + varToJsonLiteral(juce::String(result)) + "}";
                    statusCode = 400;
                    statusText = "Bad Request";
                }
            }
        } else {
            response = "{\"error\":\"unknown endpoint\"}";
            statusCode = 404;
            statusText = "Not Found";
        }
    }
    else {
        response = "{\"error\":\"method not allowed\"}";
        statusCode = 405;
        statusText = "Method Not Allowed";
    }

    juce::String header = "HTTP/1.1 " + juce::String(statusCode) + " " + statusText + "\r\n";
    header += "Content-Type: " + contentType + "\r\n";
    header += "Content-Length: " + juce::String(response.getNumBytesAsUTF8()) + "\r\n";
    header += "Access-Control-Allow-Origin: *\r\n";
    header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    header += "Access-Control-Allow-Headers: Content-Type\r\n";
    header += "Connection: close\r\n";
    header += "\r\n";

    client->write(header.toRawUTF8(), (int)header.getNumBytesAsUTF8());
    if (response.isNotEmpty()) {
        client->write(response.toRawUTF8(), (int)response.getNumBytesAsUTF8());
    }
}

// ============================================================================
// OSCQuery tree and host info
// ============================================================================

juce::String OSCQueryServer::buildOSCQueryInfo() {
    std::lock_guard<std::mutex> lock(treeMutex);
    if (!root) return "{}";
    return root->toJSON(0);
}

juce::String OSCQueryServer::buildHostInfo() {
    juce::String json = "{\n";
    json += "  \"NAME\": \"Manifold OSCQuery Server\",\n";
    json += "  \"EXTENSIONS\": {\n";
    json += "    \"ACCESS\": true,\n";
    json += "    \"VALUE\": true,\n";
    json += "    \"RANGE\": true,\n";
    json += "    \"DESCRIPTION\": true,\n";
    json += "    \"TAGS\": true,\n";
    json += "    \"LISTEN\": true,\n";
    json += "    \"PATH_CHANGED\": true\n";
    json += "  },\n";
    json += "  \"OSC_IP\": \"0.0.0.0\",\n";
    json += "  \"OSC_PORT\": " + juce::String(oscUdpPort) + ",\n";
    json += "  \"OSC_TRANSPORT\": \"UDP\",\n";
    json += "  \"WS_PORT\": " + juce::String(httpPort) + "\n";
    json += "}\n";
    return json;
}

juce::String OSCQueryServer::queryPathValue(const juce::String& oscPath) {
    return queryValue(oscPath);
}

// ============================================================================
// Value queries
// ============================================================================

juce::String OSCQueryServer::queryValue(const juce::String& oscPath) {
    if (!owner) return "{\"error\":\"no processor\"}";

    const juce::String path = normalizeQueryPath(oscPath);

    if (path == "/core/behavior/state") {
        const std::string snapshot = owner->getControlServer().getStateJson();
        return "{\"VALUE\": " + juce::String(snapshot) + "}";
    }

    if (path == "/core/behavior/diagnostics") {
        const std::string diagnostics = owner->getControlServer().getDiagnosticsJson();
        return "{\"VALUE\": " + juce::String(diagnostics) + "}";
    }

    EndpointResolver resolver(registry);
    ResolvedEndpoint endpoint;
    const bool hasResolvedEndpoint = resolver.resolve(path, endpoint);
    if (hasResolvedEndpoint) {
        const auto readValidation = resolver.validateRead(endpoint);
        if (!readValidation.accepted) {
            return "{\"error\":\"path not readable\"}";
        }
    }

    const std::string snapshot = owner->getControlServer().getStateJson();
    const juce::var stateBundle = juce::JSON::parse(juce::String(snapshot));
    if (!stateBundle.isVoid()) {
        juce::var value;
        if (tryReadProjectedValue(stateBundle, path, value)) {
            return "{\"VALUE\": " + varToJsonLiteral(value) + "}";
        }
    }

    // --- Dynamic Lua query callback (if registered) ---
    std::vector<juce::var> queryArgs;
    if (owner->getOSCServer().invokeLuaQueryCallback(path, queryArgs)) {
        return "{\"VALUE\": " + argsToValueJson(queryArgs) + "}";
    }

    // --- Custom endpoint values (Lua/userland) ---
    std::vector<juce::var> customArgs;
    if (owner->getOSCServer().getCustomValue(path, customArgs)) {
        return "{\"VALUE\": " + argsToValueJson(customArgs) + "}";
    }

    // --- Processor endpoints (Link, etc.) ---
    if (hasResolvedEndpoint && owner->hasEndpoint(path.toStdString())) {
        const float value = owner->getParamByPath(path.toStdString());
        return "{\"VALUE\": " + juce::String(value) + "}";
    }

    if (hasResolvedEndpoint) {
        return "{\"error\":\"value unavailable\"}";
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

// ============================================================================
// WebSocket upgrade handshake (RFC 6455 section 4.2.2)
// ============================================================================

juce::String OSCQueryServer::computeAcceptKey(const juce::String& clientKey) {
    // Concatenate client key with magic GUID
    juce::String concat = clientKey.trim() + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    // SHA-1 hash
    uint8_t hash[20];
    sha1::compute(concat.toRawUTF8(), concat.getNumBytesAsUTF8(), hash);

    // Base64 encode
    return juce::Base64::toBase64(hash, 20);
}

bool OSCQueryServer::performWebSocketUpgrade(juce::StreamingSocket* client,
                                             const juce::String& rawHeaders) {
    // Extract Sec-WebSocket-Key from headers
    juce::String wsKey;
    juce::String wsVersion;
    juce::String wsProtocol;
    juce::StringArray headerLines;
    headerLines.addTokens(rawHeaders, "\r\n", "");

    for (const auto& line : headerLines) {
        if (line.startsWithIgnoreCase("Sec-WebSocket-Key:"))
            wsKey = line.fromFirstOccurrenceOf(":", false, false).trim();
        else if (line.startsWithIgnoreCase("Sec-WebSocket-Version:"))
            wsVersion = line.fromFirstOccurrenceOf(":", false, false).trim();
        else if (line.startsWithIgnoreCase("Sec-WebSocket-Protocol:"))
            wsProtocol = line.fromFirstOccurrenceOf(":", false, false).trim();
    }

    if (wsKey.isEmpty()) {
        // Missing key - send 400 Bad Request
        juce::String resp = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n";
        client->write(resp.toRawUTF8(), (int)resp.getNumBytesAsUTF8());
        return false;
    }

    // Compute accept key
    juce::String acceptKey = computeAcceptKey(wsKey);

    // Send 101 Switching Protocols
    juce::String response = "HTTP/1.1 101 Switching Protocols\r\n";
    response += "Upgrade: websocket\r\n";
    response += "Connection: Upgrade\r\n";
    response += "Sec-WebSocket-Accept: " + acceptKey + "\r\n";
    // Echo back subprotocol if client requested one
    if (wsProtocol.isNotEmpty())
        response += "Sec-WebSocket-Protocol: " + wsProtocol + "\r\n";
    response += "\r\n";

    int written = client->write(response.toRawUTF8(), (int)response.getNumBytesAsUTF8());
    if (written <= 0) return false;

    // Create WebSocketClient and transfer socket ownership
    auto wsClient = std::make_unique<WebSocketClient>();
    wsClient->socket.reset(client);  // take ownership
    wsClient->connected.store(true);

    // Start read thread for this client
    WebSocketClient* rawPtr = wsClient.get();
    wsClient->readThread = std::thread(&OSCQueryServer::wsClientReadLoop, this, rawPtr);

    {
        std::lock_guard<std::mutex> lock(wsClientsMutex);
        wsClients.push_back(std::move(wsClient));
    }

    return true;
}

// ============================================================================
// WebSocket frame I/O (RFC 6455 section 5)
// ============================================================================

bool OSCQueryServer::readWebSocketFrame(juce::StreamingSocket* sock, WSOpcode& opcode,
                                        std::vector<uint8_t>& payload) {
    payload.clear();

    // Read 2-byte header
    uint8_t header[2];
    int r = sock->read(header, 2, true);
    if (r != 2) return false;

    // bool fin = (header[0] & 0x80) != 0;  // FIN bit (unused for now)
    opcode = static_cast<WSOpcode>(header[0] & 0x0F);
    bool masked = (header[1] & 0x80) != 0;
    uint64_t payloadLen = header[1] & 0x7F;

    // Extended payload length
    if (payloadLen == 126) {
        uint8_t ext[2];
        if (sock->read(ext, 2, true) != 2) return false;
        payloadLen = ((uint64_t)ext[0] << 8) | ext[1];
    } else if (payloadLen == 127) {
        uint8_t ext[8];
        if (sock->read(ext, 8, true) != 8) return false;
        payloadLen = 0;
        for (int i = 0; i < 8; i++) {
            payloadLen = (payloadLen << 8) | ext[i];
        }
    }

    // Sanity check - don't allocate more than 1MB for a single frame
    if (payloadLen > 1048576) return false;

    // Read mask key (4 bytes, only if masked)
    uint8_t maskKey[4] = {0, 0, 0, 0};
    if (masked) {
        if (sock->read(maskKey, 4, true) != 4) return false;
    }

    // Read payload
    if (payloadLen > 0) {
        payload.resize((size_t)payloadLen);
        size_t totalRead = 0;
        while (totalRead < (size_t)payloadLen) {
            int chunk = sock->read(payload.data() + totalRead,
                                   (int)((size_t)payloadLen - totalRead), true);
            if (chunk <= 0) return false;
            totalRead += (size_t)chunk;
        }

        // Unmask
        if (masked) {
            for (size_t i = 0; i < payload.size(); i++) {
                payload[i] ^= maskKey[i % 4];
            }
        }
    }

    return true;
}

bool OSCQueryServer::writeWebSocketFrame(juce::StreamingSocket* sock, WSOpcode opcode,
                                         const void* data, size_t length) {
    // Server frames are NOT masked (RFC 6455 section 5.1)
    std::vector<uint8_t> frame;
    frame.reserve(10 + length);

    // FIN=1, opcode
    frame.push_back(0x80 | static_cast<uint8_t>(opcode));

    // Payload length (no mask bit for server->client)
    if (length < 126) {
        frame.push_back((uint8_t)length);
    } else if (length < 65536) {
        frame.push_back(126);
        frame.push_back((uint8_t)(length >> 8));
        frame.push_back((uint8_t)(length & 0xFF));
    } else {
        frame.push_back(127);
        for (int i = 7; i >= 0; i--) {
            frame.push_back((uint8_t)((length >> (i * 8)) & 0xFF));
        }
    }

    // Payload
    if (length > 0 && data) {
        const uint8_t* bytes = static_cast<const uint8_t*>(data);
        frame.insert(frame.end(), bytes, bytes + length);
    }

    int written = sock->write(frame.data(), (int)frame.size());
    return written == (int)frame.size();
}

// ============================================================================
// Per-client WebSocket read loop
// ============================================================================

void OSCQueryServer::wsClientReadLoop(WebSocketClient* client) {
    while (client->connected.load() && running.load()) {
        if (!client->socket || !client->socket->isConnected()) {
            client->connected.store(false);
            break;
        }

        // Wait for data with timeout so we can check connected/running flags
        int ready = client->socket->waitUntilReady(true, 500);
        if (ready < 0) {
            client->connected.store(false);
            break;
        }
        if (ready == 0) continue;  // timeout, check flags again

        WSOpcode opcode;
        std::vector<uint8_t> payload;

        if (!readWebSocketFrame(client->socket.get(), opcode, payload)) {
            client->connected.store(false);
            break;
        }

        switch (opcode) {
            case WSOpcode::Continuation:
                break;

            case WSOpcode::Text: {
                // JSON command (LISTEN/IGNORE)
                juce::String text(reinterpret_cast<const char*>(payload.data()),
                                  payload.size());
                handleWSCommand(client, text);
                break;
            }

            case WSOpcode::Binary: {
                // Client sending OSC over WebSocket - we could dispatch it,
                // but for now this is primarily a server->client streaming protocol.
                break;
            }

            case WSOpcode::Ping: {
                // Respond with Pong (same payload)
                writeWebSocketFrame(client->socket.get(), WSOpcode::Pong,
                                    payload.data(), payload.size());
                break;
            }

            case WSOpcode::Pong: {
                // Response to our ping - nothing to do
                break;
            }

            case WSOpcode::Close: {
                // Send close frame back and disconnect
                writeWebSocketFrame(client->socket.get(), WSOpcode::Close,
                                    payload.data(), payload.size());
                client->connected.store(false);
                break;
            }

            default:
                break;
        }
    }

    client->connected.store(false);
}

// ============================================================================
// WebSocket LISTEN/IGNORE command handling
// ============================================================================

void OSCQueryServer::handleWSCommand(WebSocketClient* client, const juce::String& jsonText) {
    // Parse simple JSON: {"COMMAND":"LISTEN","DATA":"/core/behavior/tempo"}
    // We do minimal parsing since we know the exact format.

    juce::String command;
    juce::String data;

    // Extract COMMAND
    int cmdPos = jsonText.indexOf("\"COMMAND\"");
    if (cmdPos >= 0) {
        int colonPos = jsonText.indexOf(cmdPos, ":");
        if (colonPos >= 0) {
            int firstQuote = jsonText.indexOf(colonPos, "\"");
            if (firstQuote >= 0) {
                int secondQuote = jsonText.indexOf(firstQuote + 1, "\"");
                if (secondQuote >= 0) {
                    command = jsonText.substring(firstQuote + 1, secondQuote);
                }
            }
        }
    }

    // Extract DATA
    int dataPos = jsonText.indexOf("\"DATA\"");
    if (dataPos >= 0) {
        int colonPos = jsonText.indexOf(dataPos, ":");
        if (colonPos >= 0) {
            int firstQuote = jsonText.indexOf(colonPos, "\"");
            if (firstQuote >= 0) {
                int secondQuote = jsonText.indexOf(firstQuote + 1, "\"");
                if (secondQuote >= 0) {
                    data = jsonText.substring(firstQuote + 1, secondQuote);
                }
            }
        }
    }

    if (command == "LISTEN" && data.isNotEmpty()) {
        std::lock_guard<std::mutex> pathLock(client->listenMutex);
        client->listenPaths.insert(data);
    }
    else if (command == "IGNORE" && data.isNotEmpty()) {
        std::lock_guard<std::mutex> pathLock(client->listenMutex);
        client->listenPaths.erase(data);
    }
}

// ============================================================================
// WebSocket broadcast loop - streams values to subscribed clients
// ============================================================================

void OSCQueryServer::wsBroadcastLoop() {
    while (running.load()) {
        // Run at ~30Hz
        std::this_thread::sleep_for(std::chrono::milliseconds(33));

        if (!owner) continue;

        // Clean up disconnected clients
        {
            std::lock_guard<std::mutex> lock(wsClientsMutex);
            wsClients.erase(
                std::remove_if(wsClients.begin(), wsClients.end(),
                    [](const std::unique_ptr<WebSocketClient>& c) {
                        return !c->connected.load();
                    }),
                wsClients.end()
            );

            if (wsClients.empty()) continue;
        }

        auto& state = owner->getControlServer().getAtomicState();

        // Snapshot connected clients, then send outside wsClientsMutex.
        std::vector<WebSocketClient*> clients;
        {
            std::lock_guard<std::mutex> lock(wsClientsMutex);
            clients.reserve(wsClients.size());
            for (auto& c : wsClients) {
                clients.push_back(c.get());
            }
        }

        // For each connected client, check subscriptions and send changed values
        for (auto* client : clients) {
            if (!client || !client->connected.load()) continue;

            std::set<juce::String> listenPaths;
            {
                std::lock_guard<std::mutex> pathLock(client->listenMutex);
                listenPaths = client->listenPaths;
            }
            if (listenPaths.empty()) continue;

            auto& cache = client->cache;

            const auto isBehaviorListened = [&listenPaths](const juce::String& suffix) {
                return listenPaths.count("/core/behavior" + suffix) > 0;
            };

            const auto isFastTrackedPath = [](const juce::String& fullPath) {
                static const juce::String base("/core/behavior");
                const juce::String globalPaths[] = {
                    "/tempo", "/recording", "/overdub", "/mode", "/layer", "/volume"
                };
                for (const auto& suffix : globalPaths) {
                    if (fullPath == base + suffix) {
                        return true;
                    }
                }

                const juce::String layerPrefix = base + "/layer/";
                if (!fullPath.startsWith(layerPrefix)) {
                    return false;
                }

                const juce::String rest = fullPath.substring(layerPrefix.length());
                const int slash = rest.indexOfChar('/');
                if (slash <= 0) {
                    return false;
                }

                const juce::String indexPart = rest.substring(0, slash);
                if (indexPart.isEmpty() || !indexPart.containsOnly("0123456789")) {
                    return false;
                }

                const juce::String suffix = rest.substring(slash + 1);
                return suffix == "state" || suffix == "speed" || suffix == "volume" ||
                       suffix == "reverse" || suffix == "position" || suffix == "bars";
            };

            // --- Global values ---

            if (isBehaviorListened("/tempo")) {
                float v = state.tempo.load(std::memory_order_relaxed);
                if (std::abs(v - cache.tempo) > 0.01f) {
                    cache.tempo = v;
                    sendValueToClient(client, "/core/behavior/tempo", { juce::var(v) });
                }
            }

            if (isBehaviorListened("/recording")) {
                bool v = state.isRecording.load(std::memory_order_relaxed);
                if (v != cache.isRecording) {
                    cache.isRecording = v;
                    sendValueToClient(client, "/core/behavior/recording", { juce::var(v ? 1 : 0) });
                }
            }

            if (isBehaviorListened("/overdub")) {
                bool v = state.overdubEnabled.load(std::memory_order_relaxed);
                if (v != cache.overdubEnabled) {
                    cache.overdubEnabled = v;
                    sendValueToClient(client, "/core/behavior/overdub", { juce::var(v ? 1 : 0) });
                }
            }

            if (isBehaviorListened("/mode")) {
                int v = state.recordMode.load(std::memory_order_relaxed);
                if (v != cache.recordMode) {
                    cache.recordMode = v;
                    const char* modeStr = (v == 0) ? "firstLoop" :
                                          (v == 1) ? "freeMode" :
                                          (v == 2) ? "traditional" : "retrospective";
                    sendValueToClient(client, "/core/behavior/mode",
                                      { juce::var(juce::String(modeStr)) });
                }
            }

            if (isBehaviorListened("/layer")) {
                int v = state.activeLayer.load(std::memory_order_relaxed);
                if (v != cache.activeLayer) {
                    cache.activeLayer = v;
                    sendValueToClient(client, "/core/behavior/layer", { juce::var(v) });
                }
            }

            if (isBehaviorListened("/volume")) {
                float v = state.masterVolume.load(std::memory_order_relaxed);
                if (std::abs(v - cache.masterVolume) > 0.001f) {
                    cache.masterVolume = v;
                    sendValueToClient(client, "/core/behavior/volume", { juce::var(v) });
                }
            }

            // --- Per-layer values ---
            for (int i = 0; i < WebSocketClient::StateCache::MAX_LAYERS &&
                            i < AtomicState::MAX_LAYERS; ++i) {
                auto& ls = state.layers[i];
                auto& lc = cache.layers[i];
                const juce::String layerPrefix =
                    "/core/behavior/layer/" + juce::String(i) + "/";

                if (listenPaths.count(layerPrefix + "state") > 0) {
                    int v = ls.state.load(std::memory_order_relaxed);
                    if (v != lc.state) {
                        lc.state = v;
                        const char* stateStr = (v == 0) ? "empty" :
                                               (v == 1) ? "playing" :
                                               (v == 2) ? "recording" :
                                               (v == 3) ? "overdubbing" :
                                               (v == 4) ? "muted" :
                                               (v == 5) ? "stopped" :
                                               (v == 6) ? "paused" : "unknown";
                        sendValueToClient(client, layerPrefix + "state",
                                          { juce::var(juce::String(stateStr)) });
                    }
                }

                if (listenPaths.count(layerPrefix + "speed") > 0) {
                    float v = ls.speed.load(std::memory_order_relaxed);
                    if (std::abs(v - lc.speed) > 0.001f) {
                        lc.speed = v;
                        sendValueToClient(client, layerPrefix + "speed", { juce::var(v) });
                    }
                }

                if (listenPaths.count(layerPrefix + "volume") > 0) {
                    float v = ls.volume.load(std::memory_order_relaxed);
                    if (std::abs(v - lc.volume) > 0.001f) {
                        lc.volume = v;
                        sendValueToClient(client, layerPrefix + "volume", { juce::var(v) });
                    }
                }

                if (listenPaths.count(layerPrefix + "reverse") > 0) {
                    bool v = ls.reversed.load(std::memory_order_relaxed);
                    if (v != lc.reversed) {
                        lc.reversed = v;
                        sendValueToClient(client, layerPrefix + "reverse",
                                          { juce::var(v ? 1 : 0) });
                    }
                }

                if (listenPaths.count(layerPrefix + "position") > 0) {
                    int len = ls.length.load(std::memory_order_relaxed);
                    float v = (len > 0)
                                  ? static_cast<float>(ls.playheadPos.load(std::memory_order_relaxed)) /
                                        static_cast<float>(len)
                                  : 0.0f;
                    if (std::abs(v - lc.position) > 0.005f) {
                        lc.position = v;
                        sendValueToClient(client, layerPrefix + "position", { juce::var(v) });
                    }
                }

                if (listenPaths.count(layerPrefix + "bars") > 0) {
                    float v = ls.numBars.load(std::memory_order_relaxed);
                    if (std::abs(v - lc.bars) > 0.001f) {
                        lc.bars = v;
                        sendValueToClient(client, layerPrefix + "bars", { juce::var(v) });
                    }
                }
            }

            juce::var projectedStateBundle;
            bool projectedStateLoaded = false;
            const auto tryReadProjectedPath = [&](const juce::String& path,
                                                  juce::var& outValue) {
                if (!projectedStateLoaded) {
                    const std::string snapshot = owner->getControlServer().getStateJson();
                    projectedStateBundle = juce::JSON::parse(juce::String(snapshot));
                    projectedStateLoaded = true;
                }

                if (projectedStateBundle.isVoid()) {
                    return false;
                }
                return tryReadProjectedValue(projectedStateBundle, path, outValue);
            };

            const auto isOscScalar = [](const juce::var& v) {
                return v.isInt() || v.isInt64() || v.isDouble() || v.isBool() || v.isString();
            };

            // --- Dynamic/custom values outside fast-tracked behavior paths ---
            for (const auto& listenPath : listenPaths) {
                if (isFastTrackedPath(listenPath)) {
                    continue;
                }

                std::vector<juce::var> args;
                if (!owner->getOSCServer().getCustomValue(listenPath, args)) {
                    juce::var projectedValue;
                    if (tryReadProjectedPath(listenPath, projectedValue) &&
                        isOscScalar(projectedValue)) {
                        args.push_back(projectedValue);
                    } else if (owner->hasEndpoint(listenPath.toStdString())) {
                        args.push_back(juce::var(owner->getParamByPath(listenPath.toStdString())));
                    } else {
                        continue;
                    }
                }

                juce::String newSig = argsSignature(args);
                auto it = cache.customSignatures.find(listenPath);
                if (it == cache.customSignatures.end() || it->second != newSig) {
                    cache.customSignatures[listenPath] = newSig;
                    sendValueToClient(client, listenPath, args);
                }
            }
        }
    }
}

void OSCQueryServer::sendValueToClient(WebSocketClient* client,
                                       const juce::String& oscPath,
                                       const std::vector<juce::var>& args) {
    if (!client->connected.load() || !client->socket) return;

    // Build OSC binary packet and send as WebSocket binary frame
    auto packet = OSCPacketBuilder::build(oscPath, args);

    if (!writeWebSocketFrame(client->socket.get(), WSOpcode::Binary,
                             packet.data(), packet.size())) {
        client->connected.store(false);
    }
}

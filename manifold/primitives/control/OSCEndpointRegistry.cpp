#include "OSCEndpointRegistry.h"

// ============================================================================
// Static endpoint templates - THE single source of truth.
//
// Each ControlCommand::Type that has an OSC endpoint gets a template here.
// Per-layer templates use "{L}" as placeholder for layer index.
//
// Adding a new command? Add its template here and it automatically:
//   - Appears in OSCQuery /info
//   - Gets a valid OSC address
//   - Has correct type/range/access metadata
// ============================================================================

static const EndpointTemplate kEndpointTemplates[] = {
    // --- Global commands ---
    { ControlCommand::Type::SetTempo,         "tempo",      "f",  20.0f, 300.0f, 3, "Tempo (BPM)",                   false },
    { ControlCommand::Type::SetTargetBPM,     "targetbpm",  "f",  20.0f, 300.0f, 3, "Target tempo for inference",     false },
    { ControlCommand::Type::Commit,           "commit",     "f",  0.0f,  16.0f,  2, "Commit N bars retrospectively",  false },
    { ControlCommand::Type::ForwardCommit,    "forward",    "f",  0.0f,  16.0f,  2, "Arm forward commit N bars",      false },
    { ControlCommand::Type::StartRecording,   "rec",        "N",  0.0f,  0.0f,   2, "Start recording",               false },
    { ControlCommand::Type::StopRecording,    "stoprec",    "N",  0.0f,  0.0f,   2, "Stop recording",                false },
    { ControlCommand::Type::GlobalStop,       "stop",       "N",  0.0f,  0.0f,   2, "Stop all layers",               false },
    { ControlCommand::Type::GlobalPlay,       "play",       "N",  0.0f,  0.0f,   2, "Play all layers",               false },
    { ControlCommand::Type::GlobalPause,      "pause",      "N",  0.0f,  0.0f,   2, "Pause all layers",              false },
    { ControlCommand::Type::ToggleOverdub,    "overdub",    "i",  0.0f,  1.0f,   3, "Toggle/set overdub (0/1/none)", false },
    { ControlCommand::Type::SetRecordMode,    "mode",       "s",  0.0f,  0.0f,   3, "Record mode (firstLoop/freeMode/traditional/retrospective)", false },
    { ControlCommand::Type::SetActiveLayer,   "layer",      "i",  0.0f,  3.0f,   3, "Active layer index (0-3)",      false },
    { ControlCommand::Type::SetMasterVolume,  "volume",     "f",  0.0f,  2.0f,   3, "Master volume",                 false },
    { ControlCommand::Type::SetInputVolume,   "inputVolume", "f", 0.0f,  2.0f,   3, "Input volume",                  false },
    { ControlCommand::Type::SetPassthroughEnabled, "passthrough", "i", 0.0f, 1.0f, 3, "Input passthrough (0/1)",      false },
    { ControlCommand::Type::None,             "forwardBars", "f",  0.0f, 16.0f,  3, "Forward-commit bars (0 disarms)", false },
    { ControlCommand::Type::None,             "forwardArmed", "i", 0.0f, 1.0f,   3, "Forward-commit armed (0/1)",     false },
    { ControlCommand::Type::None,             "graph/enabled", "i", 0.0f, 1.0f,  3, "Enable graph processing (0/1)",  false },
    { ControlCommand::Type::None,             "dsp/reload", "i",  0.0f,  1.0f,   2, "Reload DSP script (write 1)",    false },
    { ControlCommand::Type::ClearAllLayers,   "clear",      "N",  0.0f,  0.0f,   2, "Clear all layers",              false },

    // --- Per-layer commands ---
    { ControlCommand::Type::LayerSpeed,       "layer/{L}/speed",    "f",  0.0f, 4.0f, 3, "Layer playback speed",     true },
    { ControlCommand::Type::LayerVolume,      "layer/{L}/volume",   "f",  0.0f, 2.0f, 3, "Layer volume",             true },
    { ControlCommand::Type::LayerMute,        "layer/{L}/mute",     "i",  0.0f, 1.0f, 3, "Layer mute (0/1)",         true },
    { ControlCommand::Type::LayerReverse,     "layer/{L}/reverse",  "i",  0.0f, 1.0f, 3, "Layer reverse (0/1)",      true },
    { ControlCommand::Type::LayerPlay,        "layer/{L}/play",     "N",  0.0f, 0.0f, 2, "Play layer",               true },
    { ControlCommand::Type::LayerPause,       "layer/{L}/pause",    "N",  0.0f, 0.0f, 2, "Pause layer",              true },
    { ControlCommand::Type::LayerStop,        "layer/{L}/stop",     "N",  0.0f, 0.0f, 2, "Stop layer (keep buffer)", true },
    { ControlCommand::Type::LayerClear,       "layer/{L}/clear",    "N",  0.0f, 0.0f, 2, "Clear layer",              true },
    { ControlCommand::Type::LayerSeek,        "layer/{L}/seek",     "f",  0.0f, 1.0f, 2, "Seek layer (0-1)",         true },
};

// Read-only query endpoints (not tied to a ControlCommand)
static const EndpointTemplate kReadOnlyTemplates[] = {
    { ControlCommand::Type::None, "recording",            "i",  0.0f, 1.0f, 1, "Recording state (0/1)",           false },
    { ControlCommand::Type::None, "state",                "N",  0.0f, 0.0f, 1, "Full state query (returns bundle)", false },
    { ControlCommand::Type::None, "diagnostics",          "N",  0.0f, 0.0f, 1, "Diagnostics counters and warning telemetry", false },
    { ControlCommand::Type::None, "layer/{L}/length",     "i",  0.0f, 0.0f, 1, "Loop length in samples",          true },
    { ControlCommand::Type::None, "layer/{L}/position",   "f",  0.0f, 1.0f, 1, "Playhead position (normalized)",  true },
    { ControlCommand::Type::None, "layer/{L}/state",      "s",  0.0f, 0.0f, 1, "Layer state string",              true },
    { ControlCommand::Type::None, "layer/{L}/bars",       "f",  0.0f, 0.0f, 1, "Loop length in bars",             true },
    // Ableton Link endpoints
    { ControlCommand::Type::None, "link/enabled",         "i",  0.0f, 1.0f, 3, "Link enabled (0/1)",              false },
    { ControlCommand::Type::None, "link/tempoSync",       "i",  0.0f, 1.0f, 3, "Link tempo sync enabled (0/1)",   false },
    { ControlCommand::Type::None, "link/startStopSync",   "i",  0.0f, 1.0f, 3, "Link start/stop sync enabled (0/1)", false },
    { ControlCommand::Type::None, "link/peers",           "i",  0.0f, 0.0f, 1, "Number of Link peers connected",  false },
    { ControlCommand::Type::None, "link/playing",         "i",  0.0f, 1.0f, 1, "Link transport playing (0/1)",    false },
    { ControlCommand::Type::None, "link/beat",            "f",  0.0f, 0.0f, 1, "Current Link beat position",      false },
    { ControlCommand::Type::None, "link/phase",           "f",  0.0f, 1.0f, 1, "Current Link phase (0-1)",        false },
};

static constexpr int kNumTemplates = sizeof(kEndpointTemplates) / sizeof(kEndpointTemplates[0]);
static constexpr int kNumReadOnly = sizeof(kReadOnlyTemplates) / sizeof(kReadOnlyTemplates[0]);

// ============================================================================
// Implementation
// ============================================================================

OSCEndpointRegistry::OSCEndpointRegistry() {
    buildBackendEndpoints();
}

void OSCEndpointRegistry::setBackendEnabled(bool enabled) {
    std::lock_guard<std::mutex> lock(mutex);
    backendEnabled = enabled;
    buildBackendEndpoints();
}

void OSCEndpointRegistry::rebuild() {
    std::lock_guard<std::mutex> lock(mutex);
    buildBackendEndpoints();
}

void OSCEndpointRegistry::buildBackendEndpoints() {
    backendEndpoints.clear();
    if (!backendEnabled) {
        return;
    }

    static const juce::String canonicalPrefix("/core/behavior");

    auto expandTemplateForPrefix = [&](const EndpointTemplate& tmpl,
                                       const juce::String& prefix,
                                       const char* cat) {
        if (tmpl.perLayer) {
            for (int i = 0; i < numLayers; ++i) {
                juce::String path = prefix + "/" + tmpl.pathSuffix;
                path = path.replace("{L}", juce::String(i));

                OSCEndpoint ep;
                ep.path = path;
                ep.type = tmpl.type;
                ep.rangeMin = tmpl.rangeMin;
                ep.rangeMax = tmpl.rangeMax;
                ep.access = tmpl.access;
                ep.description = tmpl.description;
                ep.category = cat;
                ep.commandType = tmpl.commandType;
                ep.layerIndex = i;
                backendEndpoints.push_back(ep);
            }
        } else {
            OSCEndpoint ep;
            ep.path = prefix + "/" + tmpl.pathSuffix;
            ep.type = tmpl.type;
            ep.rangeMin = tmpl.rangeMin;
            ep.rangeMax = tmpl.rangeMax;
            ep.access = tmpl.access;
            ep.description = tmpl.description;
            ep.category = cat;
            ep.commandType = tmpl.commandType;
            ep.layerIndex = -1;
            backendEndpoints.push_back(ep);
        }
    };

    // Writable backend endpoints (canonical namespace only).
    for (int i = 0; i < kNumTemplates; ++i) {
        expandTemplateForPrefix(kEndpointTemplates[i], canonicalPrefix, "backend");
    }

    // Read-only query endpoints (canonical namespace only).
    for (int i = 0; i < kNumReadOnly; ++i) {
        expandTemplateForPrefix(kReadOnlyTemplates[i], canonicalPrefix, "query");
    }
}

std::vector<OSCEndpoint> OSCEndpointRegistry::getAllEndpoints() const {
    std::lock_guard<std::mutex> lock(mutex);
    std::vector<OSCEndpoint> result;
    result.reserve(backendEndpoints.size() + customEndpoints.size());
    result.insert(result.end(), backendEndpoints.begin(), backendEndpoints.end());
    result.insert(result.end(), customEndpoints.begin(), customEndpoints.end());
    return result;
}

OSCEndpointRegistry::Stats OSCEndpointRegistry::getStats() const {
    std::lock_guard<std::mutex> lock(mutex);
    Stats stats;
    stats.backendCount = static_cast<int64_t>(backendEndpoints.size());
    stats.customCount = static_cast<int64_t>(customEndpoints.size());
    stats.totalCount = stats.backendCount + stats.customCount;
    auto accumulate = [&](const std::vector<OSCEndpoint>& endpoints) {
        for (const auto& ep : endpoints) {
            stats.pathBytes += ep.path.getNumBytesAsUTF8();
            stats.descriptionBytes += ep.description.getNumBytesAsUTF8();
        }
    };
    accumulate(backendEndpoints);
    accumulate(customEndpoints);
    return stats;
}

std::vector<OSCEndpoint> OSCEndpointRegistry::getBackendEndpoints() const {
    std::lock_guard<std::mutex> lock(mutex);
    return backendEndpoints;
}

void OSCEndpointRegistry::registerCustomEndpoint(const OSCEndpoint& endpoint) {
    std::lock_guard<std::mutex> lock(mutex);
    for (auto& e : customEndpoints) {
        if (e.path == endpoint.path) {
            e = endpoint;
            return;
        }
    }
    customEndpoints.push_back(endpoint);
}

void OSCEndpointRegistry::unregisterCustomEndpoint(const juce::String& path) {
    std::lock_guard<std::mutex> lock(mutex);
    customEndpoints.erase(
        std::remove_if(customEndpoints.begin(), customEndpoints.end(),
                       [&](const OSCEndpoint& e) { return e.path == path; }),
        customEndpoints.end());
}

void OSCEndpointRegistry::clearCustomEndpoints() {
    std::lock_guard<std::mutex> lock(mutex);
    customEndpoints.clear();
}

OSCEndpoint OSCEndpointRegistry::findEndpoint(const juce::String& path) const {
    std::lock_guard<std::mutex> lock(mutex);
    for (const auto& e : backendEndpoints) {
        if (e.path == path) return e;
    }
    for (const auto& e : customEndpoints) {
        if (e.path == path) return e;
    }
    return OSCEndpoint();  // empty path = not found
}

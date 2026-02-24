#pragma once

#include "ControlServer.h"
#include <juce_core/juce_core.h>
#include <map>
#include <mutex>
#include <string>
#include <vector>

// ============================================================================
// Endpoint descriptor - metadata about a single OSC endpoint
// ============================================================================

struct OSCEndpoint {
    juce::String path;           // e.g. "/looper/tempo"
    juce::String type;           // OSC type tags: "f", "i", "s", "N", etc.
    float rangeMin = 0.0f;
    float rangeMax = 1.0f;
    int access = 2;              // 0=none, 1=read, 2=write, 3=read-write
    juce::String description;
    juce::String category;       // "backend", "layer", or "custom"

    // Map to ControlCommand (only meaningful for writable backend endpoints)
    ControlCommand::Type commandType = ControlCommand::Type::None;

    // For per-layer endpoints, which layer index (-1 = not layer-specific)
    int layerIndex = -1;
};

// ============================================================================
// EndpointTemplate - defines how a ControlCommand::Type maps to an OSC path.
// Per-layer templates use layerIndex placeholder.
// ============================================================================

struct EndpointTemplate {
    ControlCommand::Type commandType;
    const char* pathSuffix;      // e.g. "tempo" or "layer/{L}/speed"
    const char* type;            // OSC type tags
    float rangeMin;
    float rangeMax;
    int access;                  // 0=none, 1=read, 2=write, 3=rw
    const char* description;
    bool perLayer;               // if true, expanded per-layer with {L} replaced
};

// ============================================================================
// OSCEndpointRegistry - single source of truth for all OSC endpoints.
// Generates endpoint list from ControlCommand::Type enum + templates.
// ============================================================================

class OSCEndpointRegistry {
public:
    OSCEndpointRegistry();

    // Get all endpoints (backend + custom). Thread-safe.
    std::vector<OSCEndpoint> getAllEndpoints() const;

    // Get only backend endpoints (generated from ControlCommand::Type)
    std::vector<OSCEndpoint> getBackendEndpoints() const;

    // Custom endpoint management (for Lua UI scripts)
    void registerCustomEndpoint(const OSCEndpoint& endpoint);
    void unregisterCustomEndpoint(const juce::String& path);
    void clearCustomEndpoints();

    // Lookup endpoint by path. Returns nullptr-equivalent (empty path) if not found.
    OSCEndpoint findEndpoint(const juce::String& path) const;

    // Number of layers (set once, used for per-layer endpoint generation)
    void setNumLayers(int n) { numLayers = n; }
    int getNumLayers() const { return numLayers; }

    // Rebuild backend endpoints (call after changing numLayers)
    void rebuild();

private:
    void buildBackendEndpoints();

    int numLayers = 4;  // default, matches LooperProcessor::MAX_LAYERS

    std::vector<OSCEndpoint> backendEndpoints;
    std::vector<OSCEndpoint> customEndpoints;
    mutable std::mutex mutex;
};

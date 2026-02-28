#pragma once

#include <string>
#include <vector>
#include <functional>

// Forward declarations
namespace sol {
class state;
}

// ============================================================================
// IStateSerializer - Interface for plugin-specific state serialization
//
// This interface allows plugins to define their own state schema for Lua
// and OSCQuery. The Looper provides looper-specific state (voices[], layers),
// while other plugins (GrainFreeze, etc.) can provide their own schemas.
//
// The serializer creates a Lua table structure that scripts can access via
// the global 'state' variable. It also provides schema information for
// OSCQuery auto-discovery.
// ============================================================================

class IStateSerializer {
public:
    virtual ~IStateSerializer() = default;

    // ========================================================================
    // Core serialization
    // ========================================================================

    // Serialize current state to a Lua table and set it as lua["state"].
    // This replaces the old pushStateToLua() hardcoded behavior.
    // The table structure is plugin-defined:
    //   - Looper: { projectionVersion, numVoices, params{}, voices[], link{}, spectrum[] }
    //   - Others: plugin-specific structure
    virtual void serializeStateToLua(sol::state& lua) const = 0;

    // Serialize to JSON string for OSCQuery or network transmission.
    // Format matches the Lua table structure as closely as possible.
    virtual std::string serializeStateToJson() const = 0;

    // ========================================================================
    // Schema introspection (for OSCQuery auto-discovery)
    // ========================================================================

    struct StateField {
        std::string path;           // Full path: "/looper/tempo", "/looper/layer/0/speed"
        std::string type;           // OSC type tag: "f", "i", "s", "b", etc.
        std::string description;
        float rangeMin = 0.0f;
        float rangeMax = 1.0f;
        int access = 1;             // 0=none, 1=read, 2=write, 3=read-write
        bool isPerLayer = false;    // If true, path has layer index placeholder
        int layerIndex = -1;        // For per-layer fields, which layer (-1 = global)
    };

    // Get schema describing all available state fields.
    // Used by OSCQuery to build endpoint descriptions.
    virtual std::vector<StateField> getStateSchema() const = 0;

    // ========================================================================
    // Incremental updates (for efficient event broadcasting)
    // ========================================================================

    // Get value at a specific path (for on-demand queries).
    // Path format matches OSC paths: "/looper/tempo", "/looper/layer/0/speed"
    // Returns empty string if path not found.
    virtual std::string getValueAtPath(const std::string& path) const = 0;

    // Check if a path has changed since last check (for diff-based updates).
    // Returns true if value at path is different from cached value.
    virtual bool hasPathChanged(const std::string& path) const = 0;

    // Update internal cache to current values (call after checking changes).
    virtual void updateChangeCache() = 0;

    // ========================================================================
    // Subscription management (for selective event broadcasting)
    // ========================================================================

    using StateChangeCallback = std::function<void(const std::string& path, const std::string& value)>;

    // Subscribe to changes on specific paths (supports wildcards like "/looper/layer/*/speed").
    // When any subscribed path changes, callback is invoked with path and new value.
    virtual void subscribeToPath(const std::string& path, StateChangeCallback callback) = 0;

    // Unsubscribe from a path.
    virtual void unsubscribeFromPath(const std::string& path) = 0;

    // Clear all subscriptions.
    virtual void clearSubscriptions() = 0;

    // Process all pending state changes and invoke callbacks for subscribed paths.
    // Should be called regularly (e.g., from message thread timer).
    virtual void processPendingChanges() = 0;
};

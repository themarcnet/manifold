#pragma once

// ============================================================================
// ScriptingConfig - Centralized configuration constants
//
// This file provides a single source of truth for all magic numbers used
// in the scripting system. These can be adjusted compile-time for different
// hardware targets (embedded vs desktop).
//
// See ARCHITECTURAL_AUDIT.md Category B for rationale.
// ============================================================================

namespace scripting {

// ============================================================================
// Queue Configuration (Category B1)
// ============================================================================

struct QueueConfig {
    // Command queue: Lua thread -> Audio thread
    // Larger = more commands buffered, more memory
    // 256 = ~1ms burst at 44.1kHz with typical command rate
    static constexpr int COMMAND_QUEUE_SIZE = 256;

    // Event queue: Audio thread -> Lua thread
    // Events are pushed at ~30Hz, so 256 is generous
    static constexpr int EVENT_QUEUE_SIZE = 256;
};

// ============================================================================
// Buffer Configuration (Category B3, B4)
// ============================================================================

struct BufferConfig {
    // Maximum size for JSON event payloads
    // Controls ControlEvent::json buffer size
    // 512 bytes = ~256 chars which is plenty for most events
    static constexpr int MAX_JSON_PAYLOAD_SIZE = 512;

    // Maximum block size for DSP processing
    // Affects PrimitiveGraph and GraphRuntime buffer sizing
    static constexpr int MAX_DSP_BLOCK_SIZE = 512;

    // Stack buffer size for SHA1 operations
    static constexpr int SHA1_STACK_BUFFER_SIZE = 256;
};

// ============================================================================
// Layer Configuration (Category B2)
// ============================================================================

struct LayerConfig {
    // Maximum number of layers supported
    // This is a compile-time limit that affects:
    // - AtomicState memory layout
    // - OSC query responses
    // - UI state serialization
    //
    // NOTE: Changing this requires recompiling all components.
    // For runtime-configurable layers, use ScriptableProcessor::getNumLayers()
    static constexpr int MAX_LAYERS = 4;
};

// ============================================================================
// Derived constants (don't modify directly)
// ============================================================================

// Backward compatibility aliases - these will be deprecated
// Prefer using the structs above in new code
inline constexpr int SCRIPTING_COMMAND_QUEUE_SIZE = QueueConfig::COMMAND_QUEUE_SIZE;
inline constexpr int SCRIPTING_EVENT_QUEUE_SIZE = QueueConfig::EVENT_QUEUE_SIZE;
inline constexpr int SCRIPTING_MAX_JSON_SIZE = BufferConfig::MAX_JSON_PAYLOAD_SIZE;
inline constexpr int SCRIPTING_MAX_BLOCK_SIZE = BufferConfig::MAX_DSP_BLOCK_SIZE;
inline constexpr int SCRIPTING_MAX_LAYERS = LayerConfig::MAX_LAYERS;

} // namespace scripting

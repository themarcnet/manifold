#pragma once

#include <array>
#include <atomic>
#include <cstdint>

/**
 * Lock-free single-producer-single-consumer ring buffer for MIDI messages.
 * Used for passing MIDI from audio thread to control thread (and vice versa).
 * 
 * Messages are stored as packed 4-byte values:
 * - byte 0: status (message type | channel)
 * - byte 1: data1 (note number / CC number / etc)
 * - byte 2: data2 (velocity / value / etc)
 * - byte 3: timestamp delta (samples from previous message)
 */
class MidiRingBuffer {
public:
    static constexpr int CAPACITY = 256;
    static constexpr int EMPTY = -1;
    static constexpr int FULL = -2;

    MidiRingBuffer() {
        clear();
    }

    void clear() {
        writeIdx.store(0, std::memory_order_relaxed);
        readIdx.store(0, std::memory_order_relaxed);
        lastTimestamp.store(0, std::memory_order_relaxed);
    }

    // Write a MIDI message (called from single producer, e.g., audio thread)
    // Returns false if buffer is full
    bool write(uint8_t status, uint8_t data1, uint8_t data2, int32_t timestampDelta = 0) {
        int w = writeIdx.load(std::memory_order_relaxed);
        int next = (w + 1) % CAPACITY;
        if (next == readIdx.load(std::memory_order_acquire)) {
            return false; // full
        }

        // Pack: [status, data1, data2, timestampDelta]
        ring[w] = (static_cast<uint32_t>(status) << 24) |
                  (static_cast<uint32_t>(data1) << 16) |
                  (static_cast<uint32_t>(data2) << 8) |
                  (static_cast<uint32_t>(timestampDelta & 0xFF));

        writeIdx.store(next, std::memory_order_release);
        return true;
    }

    // Read a MIDI message (called from single consumer, e.g., control thread)
    // Returns false if buffer is empty
    bool read(uint8_t& status, uint8_t& data1, uint8_t& data2, int32_t& timestampDelta) {
        int r = readIdx.load(std::memory_order_relaxed);
        if (r == writeIdx.load(std::memory_order_acquire)) {
            return false; // empty
        }

        uint32_t msg = ring[r];
        status = static_cast<uint8_t>((msg >> 24) & 0xFF);
        data1 = static_cast<uint8_t>((msg >> 16) & 0xFF);
        data2 = static_cast<uint8_t>((msg >> 8) & 0xFF);
        timestampDelta = static_cast<int32_t>(msg & 0xFF);

        // Convert delta to absolute timestamp
        int32_t prev = lastTimestamp.load(std::memory_order_relaxed);
        int32_t absTimestamp = prev + timestampDelta;
        lastTimestamp.store(absTimestamp, std::memory_order_relaxed);

        readIdx.store((r + 1) % CAPACITY, std::memory_order_release);
        return true;
    }

    // Peek at a MIDI message without consuming it (for overlays/monitoring)
    // Returns false if buffer is empty
    bool peek(uint8_t& status, uint8_t& data1, uint8_t& data2, int32_t timestampOffset = 0) const {
        int r = readIdx.load(std::memory_order_relaxed);
        if (r == writeIdx.load(std::memory_order_acquire)) {
            return false; // empty
        }

        uint32_t msg = ring[r];
        status = static_cast<uint8_t>((msg >> 24) & 0xFF);
        data1 = static_cast<uint8_t>((msg >> 16) & 0xFF);
        data2 = static_cast<uint8_t>((msg >> 8) & 0xFF);
        // Don't advance readIdx - this is a non-destructive read
        (void)timestampOffset; // Unused but reserved for future absolute timestamp
        return true;
    }

    // Check if empty
    bool isEmpty() const {
        return writeIdx.load(std::memory_order_acquire) == 
               readIdx.load(std::memory_order_acquire);
    }

    // Check if full
    bool isFull() const {
        int next = (writeIdx.load(std::memory_order_relaxed) + 1) % CAPACITY;
        return next == readIdx.load(std::memory_order_acquire);
    }

    // Approximate number of messages (not exact, but good for debugging)
    int approxSize() const {
        int w = writeIdx.load(std::memory_order_relaxed);
        int r = readIdx.load(std::memory_order_relaxed);
        if (w >= r) return w - r;
        return CAPACITY - r + w;
    }

private:
    std::array<uint32_t, CAPACITY> ring{};
    std::atomic<int> writeIdx{0};
    std::atomic<int> readIdx{0};
    std::atomic<int32_t> lastTimestamp{0};
};

// ============================================================================
// MIDI Message Types (4-bit status)
// ============================================================================
namespace MidiStatus {
    constexpr uint8_t NOTE_OFF = 0x80;
    constexpr uint8_t NOTE_ON = 0x90;
    constexpr uint8_t AFTERTOUCH = 0xA0;
    constexpr uint8_t CONTROL_CHANGE = 0xB0;
    constexpr uint8_t PROGRAM_CHANGE = 0xC0;
    constexpr uint8_t CHANNEL_PRESSURE = 0xD0;
    constexpr uint8_t PITCH_BEND = 0xE0;
    constexpr uint8_t SYSEX = 0xF0;
    constexpr uint8_t MIDI_CLOCK = 0xF8;
    constexpr uint8_t MIDI_START = 0xFA;
    constexpr uint8_t MIDI_STOP = 0xFC;
    constexpr uint8_t MIDI_CONTINUE = 0xFB;
    constexpr uint8_t ACTIVE_SENSING = 0xFE;
    constexpr uint8_t RESET = 0xFF;

    // Extract channel (0-15) from status byte
    constexpr uint8_t channel(uint8_t status) { return status & 0x0F; }
    
    // Extract message type (0xF0 masked) from status byte
    constexpr uint8_t type(uint8_t status) { return status & 0xF0; }
    
    // Check if it's a channel message (not sysex/clock)
    constexpr bool isChannelMessage(uint8_t status) { return (status & 0xF0) != 0xF0; }
}

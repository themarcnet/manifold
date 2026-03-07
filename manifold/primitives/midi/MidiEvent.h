#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <cmath>

namespace midi {

// ============================================================================
// MIDI Event Types
// ============================================================================
enum class EventType : uint8_t {
    NoteOff = 0x80,
    NoteOn = 0x90,
    Aftertouch = 0xA0,
    ControlChange = 0xB0,
    ProgramChange = 0xC0,
    ChannelPressure = 0xD0,
    PitchBend = 0xE0,
    Sysex = 0xF0,
    Clock = 0xF8,
    Start = 0xFA,
    Continue = 0xFB,
    Stop = 0xFC,
    ActiveSensing = 0xFE,
    Reset = 0xFF,
    Unknown = 0x00
};

// ============================================================================
// MIDI Event Structure
// ============================================================================
struct MidiEvent {
    EventType type;
    uint8_t channel;      // 0-15 (stored as 0-based internally)
    uint8_t data1;        // Note number, CC number, program number, etc.
    uint8_t data2;        // Velocity, CC value, pressure, etc.
    int32_t timestamp;    // Sample position in buffer
    double timeStampSeconds; // Time in seconds
    
    // Constructors
    MidiEvent() : type(EventType::Unknown), channel(0), data1(0), data2(0), 
                  timestamp(0), timeStampSeconds(0.0) {}
    
    MidiEvent(uint8_t status, uint8_t d1, uint8_t d2, int32_t ts = 0) 
        : channel(status & 0x0F), data1(d1), data2(d2), timestamp(ts), timeStampSeconds(0.0) {
        type = static_cast<EventType>(status & 0xF0);
    }
    
    // Convenience accessors
    bool isNoteOn() const { return type == EventType::NoteOn && data2 > 0; }
    bool isNoteOff() const { return type == EventType::NoteOff || (type == EventType::NoteOn && data2 == 0); }
    bool isControlChange() const { return type == EventType::ControlChange; }
    bool isPitchBend() const { return type == EventType::PitchBend; }
    bool isProgramChange() const { return type == EventType::ProgramChange; }
    bool isChannelMessage() const { return static_cast<uint8_t>(type) < 0xF0; }
    
    uint8_t getNoteNumber() const { return data1; }
    uint8_t getVelocity() const { return data2; }
    uint8_t getCCNumber() const { return data1; }
    uint8_t getCCValue() const { return data2; }
    int16_t getPitchBendValue() const { 
        return static_cast<int16_t>(data1 | (data2 << 7)) - 8192; 
    }
    
    // Convert to JUCE-style status byte
    uint8_t getStatusByte() const {
        return static_cast<uint8_t>(type) | (channel & 0x0F);
    }
    
    std::string toString() const;
};

// ============================================================================
// MIDI Constants
// ============================================================================
namespace Constants {
    constexpr uint8_t ALL_NOTES_OFF = 123;
    constexpr uint8_t ALL_SOUND_OFF = 120;
    constexpr uint8_t RESET_ALL_CONTROLLERS = 121;
    constexpr uint8_t DAMPER_PEDAL = 64;
    constexpr uint8_t PORTAMENTO = 65;
    constexpr uint8_t SOSTENUTO = 66;
    constexpr uint8_t SOFT_PEDAL = 67;
    constexpr uint8_t MOD_WHEEL = 1;
    constexpr uint8_t VOLUME = 7;
    constexpr uint8_t PAN = 10;
    constexpr uint8_t EXPRESSION = 11;
    constexpr uint8_t RESONANCE = 71;
    constexpr uint8_t RELEASE_TIME = 72;
    constexpr uint8_t ATTACK_TIME = 73;
    constexpr uint8_t CUTOFF = 74;
    constexpr uint8_t DECAY_TIME = 75;
    constexpr uint8_t SUSTAIN_LEVEL = 76;
    constexpr uint8_t VIBRATO_RATE = 76;
    constexpr uint8_t VIBRATO_DEPTH = 77;
    constexpr uint8_t VIBRATO_DELAY = 78;
}

// ============================================================================
// MIDI Event Callback Types
// ============================================================================
using NoteOnCallback = std::function<void(uint8_t channel, uint8_t note, uint8_t velocity, const MidiEvent& event)>;
using NoteOffCallback = std::function<void(uint8_t channel, uint8_t note, const MidiEvent& event)>;
using ControlChangeCallback = std::function<void(uint8_t channel, uint8_t cc, uint8_t value, const MidiEvent& event)>;
using PitchBendCallback = std::function<void(uint8_t channel, int16_t value, const MidiEvent& event)>;
using ProgramChangeCallback = std::function<void(uint8_t channel, uint8_t program, const MidiEvent& event)>;
using MidiEventCallback = std::function<void(const MidiEvent& event)>;

// ============================================================================
// Utility Functions
// ============================================================================
inline float noteToFrequency(int noteNumber) {
    // A4 = 69 = 440Hz
    return 440.0f * std::pow(2.0f, (noteNumber - 69) / 12.0f);
}

inline int frequencyToNote(float frequency) {
    if (frequency <= 0.0f) return 0;
    return static_cast<int>(std::round(69.0f + 12.0f * std::log2(frequency / 440.0f)));
}

inline const char* noteName(int noteNumber) {
    static const char* names[] = {
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
    };
    return names[noteNumber % 12];
}

inline int noteOctave(int noteNumber) {
    return (noteNumber / 12) - 1;
}

inline std::string noteToString(int noteNumber) {
    return std::string(noteName(noteNumber)) + std::to_string(noteOctave(noteNumber));
}

} // namespace midi

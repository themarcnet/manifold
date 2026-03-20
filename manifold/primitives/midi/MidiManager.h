#pragma once

#include "MidiEvent.h"
#include "MidiRingBuffer.h"
#include <vector>
#include <array>
#include <functional>
#include <mutex>
#include <atomic>
#include <memory>

#include <juce_audio_devices/juce_audio_devices.h>

namespace midi {

// ============================================================================
// Voice State for Polyphonic Synthesis
// ============================================================================
struct VoiceState {
    uint8_t note = 0;
    uint8_t velocity = 0;
    uint8_t channel = 0;
    bool active = false;
    bool sustained = false;  // While sustain pedal is held
    double startTime = 0.0;
    double releaseTime = 0.0;
    float currentPitchBend = 0.0f;  // -1.0 to +1.0
    
    void reset() {
        note = 0;
        velocity = 0;
        channel = 0;
        active = false;
        sustained = false;
        startTime = 0.0;
        releaseTime = 0.0;
        currentPitchBend = 0.0f;
    }
};

// ============================================================================
// MIDI Channel State
// ============================================================================
struct ChannelState {
    std::array<uint8_t, 128> ccValues{};  // Current CC values
    std::array<bool, 128> notesHeld{};    // Currently held notes
    uint8_t program = 0;
    uint8_t pressure = 0;
    int16_t pitchBend = 0;  // -8192 to +8191
    bool sustainPedal = false;
    bool sostenutoPedal = false;
    bool softPedal = false;
    int numActiveNotes = 0;
    
    ChannelState() {
        ccValues.fill(0);
        notesHeld.fill(false);
    }
};

// ============================================================================
// MIDI Manager - Central MIDI handling with callbacks and state tracking
// ============================================================================
class MidiManager : public juce::MidiInputCallback {
public:
    static constexpr int MAX_VOICES = 32;
    static constexpr int NUM_CHANNELS = 16;
    
    MidiManager();
    
    // Process MIDI input from JUCE buffer (call from audio thread)
    void processIncomingMidi(const juce::MidiBuffer& midiBuffer, double sampleRate);
    
    // Get outgoing MIDI messages (call from audio thread)
    void fillOutgoingMidi(juce::MidiBuffer& outputBuffer);
    
    // State queries
    const ChannelState& getChannelState(int channel) const { return channels_[channel & 0x0F]; }
    const VoiceState* getVoiceStates() const { return voices_.data(); }
    int getNumActiveVoices() const { return numActiveVoices_.load(std::memory_order_acquire); }
    
    // Voice management
    int findFreeVoice() const;
    int findVoicePlayingNote(uint8_t note, uint8_t channel) const;
    void releaseVoice(int voiceIndex);
    void releaseAllVoices();
    
    // MIDI output
    void sendNoteOn(uint8_t channel, uint8_t note, uint8_t velocity);
    void sendNoteOff(uint8_t channel, uint8_t note);
    void sendCC(uint8_t channel, uint8_t cc, uint8_t value);
    void sendPitchBend(uint8_t channel, int16_t value);
    void sendProgramChange(uint8_t channel, uint8_t program);
    void sendAllNotesOff(uint8_t channel);
    void sendAllSoundOff(uint8_t channel);
    
    // Callback registration (thread-safe)
    void setNoteOnCallback(NoteOnCallback cb);
    void setNoteOffCallback(NoteOffCallback cb);
    void setControlChangeCallback(ControlChangeCallback cb);
    void setPitchBendCallback(PitchBendCallback cb);
    void setProgramChangeCallback(ProgramChangeCallback cb);
    void setMidiEventCallback(MidiEventCallback cb);
    
    // Clear all callbacks
    void clearCallbacks();

    // Temporarily suppress callbacks during script loading to avoid audio thread stalls
    void setCallbacksSuppressed(bool suppressed) { callbacksSuppressed_.store(suppressed, std::memory_order_release); }
    bool areCallbacksSuppressed() const { return callbacksSuppressed_.load(std::memory_order_acquire); }

    // Settings
    void setChannelMask(uint16_t mask);  // Bit mask of enabled channels (bit 0 = ch 1)
    bool isChannelEnabled(uint8_t channel) const;
    void setOmniMode(bool omni) { omniMode_ = omni; }
    bool isOmniMode() const { return omniMode_; }
    
    // Reset
    void reset();
    
    // Access to input ring buffer for polling (alternative to callbacks)
    MidiRingBuffer& getInputRing() { return inputRing_; }
    MidiRingBuffer& getOutputRing() { return outputRing_; }

    // Non-destructive monitor tap (latest MIDI message seen by MidiManager)
    // Returns false if no input has been seen yet.
    bool getLastInputMessage(uint8_t& status, uint8_t& data1, uint8_t& data2, uint64_t& seq) const;
    
    // Physical device management (shared across projects)
    bool openInput(int deviceIndex);
    bool openOutput(int deviceIndex);
    void closeInput();
    void closeOutput();
    bool isInputOpen() const { return midiInput_ != nullptr; }
    bool isOutputOpen() const { return midiOutput_ != nullptr; }
    int getCurrentInputDevice() const { return currentInputDevice_; }
    int getCurrentOutputDevice() const { return currentOutputDevice_; }
    
    // Static device listing
    static std::vector<std::string> getInputDevices();
    static std::vector<std::string> getOutputDevices();
    
private:
    // Handle incoming MIDI from physical device
    void handleIncomingMidiMessage(juce::MidiInput* source, const juce::MidiMessage& message) override;
    
    std::unique_ptr<juce::MidiInput> midiInput_;
    std::unique_ptr<juce::MidiOutput> midiOutput_;
    int currentInputDevice_ = -1;
    int currentOutputDevice_ = -1;
    void handleMidiEvent(const MidiEvent& event);
    void updateCC(uint8_t channel, uint8_t cc, uint8_t value);
    void handleNoteOn(uint8_t channel, uint8_t note, uint8_t velocity);
    void handleNoteOff(uint8_t channel, uint8_t note);
    void updateVoicePitchBends();
    
    std::array<ChannelState, NUM_CHANNELS> channels_;
    std::array<VoiceState, MAX_VOICES> voices_;
    std::atomic<int> numActiveVoices_{0};
    
    MidiRingBuffer inputRing_;   // Audio thread → Control/Script thread
    MidiRingBuffer outputRing_;  // Control/Script thread → Audio thread
    
    // Callbacks (protected by mutex for thread safety)
    std::mutex callbackMutex_;
    NoteOnCallback noteOnCb_;
    NoteOffCallback noteOffCb_;
    ControlChangeCallback ccCb_;
    PitchBendCallback pitchBendCb_;
    ProgramChangeCallback programChangeCb_;
    MidiEventCallback midiEventCb_;
    
    // Settings
    uint16_t channelMask_ = 0xFFFF;  // All channels enabled
    bool omniMode_ = true;
    double currentSampleRate_ = 44100.0;
    int32_t sampleCounter_ = 0;

    // Non-destructive monitor snapshot of latest input message
    std::atomic<uint64_t> lastInputSeq_{0};
    std::atomic<uint32_t> lastInputPacked_{0};

    // Temporarily suppress Lua callbacks during script loading to prevent audio thread blocking
    std::atomic<bool> callbacksSuppressed_{false};
};

} // namespace midi

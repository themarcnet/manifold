#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "manifold/primitives/midi/MidiManager.h"
#include <memory>
#include <atomic>

namespace dsp_primitives {

// Forward declaration
class MidiVoiceNode;

// ============================================================================
// MidiInputNode - Routes MIDI input to connected voice processors
// ============================================================================
class MidiInputNode : public IPrimitiveNode, public std::enable_shared_from_this<MidiInputNode> {
public:
    MidiInputNode();
    
    const char* getNodeType() const override { return "MidiInput"; }
    int getNumInputs() const override { return 0; }
    int getNumOutputs() const override { return 0; }  // MIDI is handled separately
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    // Set the MIDI manager to receive events from
    void setMidiManager(std::shared_ptr<midi::MidiManager> manager) { midiManager_ = manager; }
    
    // Connect to a voice node for automatic routing
    void connectToVoiceNode(std::shared_ptr<MidiVoiceNode> voiceNode);
    
    // Parameter setters
    void setChannelFilter(int channel) { channelFilter_ = juce::jlimit(-1, 15, channel); }  // -1 = all channels
    void setChannelMask(uint16_t mask) { channelMask_ = mask; }
    void setOmniMode(bool omni) { omniMode_ = omni; }
    void setMonophonic(bool mono) { monophonic_ = mono; }
    void setPortamento(float seconds) { portamentoTime_ = juce::jlimit(0.0f, 5.0f, seconds); }
    void setPitchBendRange(float semitones) { pitchBendRange_ = juce::jlimit(0.0f, 24.0f, semitones); }
    void setEnabled(bool en) { enabled_ = en; }
    void setEchoOutput(bool echo) { echoOutput_ = echo; }
    
    // Parameter getters
    int getChannelFilter() const { return channelFilter_; }
    bool isOmniMode() const { return omniMode_; }
    bool isMonophonic() const { return monophonic_; }
    float getPortamento() const { return portamentoTime_; }
    float getPitchBendRange() const { return pitchBendRange_; }
    bool isEnabled() const { return enabled_; }
    bool isEchoingOutput() const { return echoOutput_; }
    
    // Current state queries
    uint8_t getLastNote() const { return lastNote_; }
    uint8_t getLastVelocity() const { return lastVelocity_; }
    float getCurrentPitchBend() const { return currentPitchBend_; }
    
    // Manual trigger functions (for UI testing)
    void triggerNoteOn(uint8_t note, uint8_t velocity);
    void triggerNoteOff(uint8_t note);
    void triggerPitchBend(int16_t value);
    
private:
    void processMidiEvent(const midi::MidiEvent& event);
    void routeToVoices(uint8_t channel, uint8_t note, uint8_t velocity, bool isNoteOn);
    float noteToFreq(uint8_t note);
    
    std::shared_ptr<midi::MidiManager> midiManager_;
    std::weak_ptr<MidiVoiceNode> connectedVoiceNode_;
    
    // Settings
    int channelFilter_ = -1;      // -1 = all channels
    uint16_t channelMask_ = 0xFFFF;  // All channels enabled
    bool omniMode_ = true;
    bool monophonic_ = false;
    float portamentoTime_ = 0.0f;
    float pitchBendRange_ = 2.0f;   // +/- 2 semitones
    bool enabled_ = true;
    bool echoOutput_ = false;
    
    // Monophonic state
    uint8_t lastNote_ = 0;
    uint8_t lastVelocity_ = 0;
    float currentPitchBend_ = 0.0f;
    float currentFrequency_ = 440.0f;
    float targetFrequency_ = 440.0f;
    
    // Sample rate
    double sampleRate_ = 44100.0;
    
    // Output buffer for echo
    std::vector<midi::MidiEvent> pendingOutput_;
};

} // namespace dsp_primitives

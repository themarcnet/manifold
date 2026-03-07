#include "MidiInputNode.h"
#include "MidiVoiceNode.h"
#include <cmath>

namespace dsp_primitives {

MidiInputNode::MidiInputNode() = default;

void MidiInputNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
}

void MidiInputNode::process(const std::vector<AudioBufferView>& inputs,
                            std::vector<WritableAudioBufferView>& outputs,
                            int numSamples) {
    (void)inputs;
    (void)outputs;
    (void)numSamples;
    
    if (!enabled_) return;
    
    // Process incoming MIDI from the ring buffer
    if (midiManager_) {
        uint8_t status, data1, data2;
        int32_t timestamp;
        auto& inputRing = midiManager_->getInputRing();
        
        while (inputRing.read(status, data1, data2, timestamp)) {
            midi::MidiEvent event(status, data1, data2, timestamp);
            processMidiEvent(event);
        }
    }
    
    // Handle portamento for monophonic mode
    if (monophonic_ && portamentoTime_ > 0.0f) {
        float glideCoeff = 1.0f - std::exp(-1.0f / (portamentoTime_ * sampleRate_));
        currentFrequency_ += (targetFrequency_ - currentFrequency_) * glideCoeff;
    }
}

void MidiInputNode::processMidiEvent(const midi::MidiEvent& event) {
    // Channel filtering
    if (!omniMode_ && channelFilter_ >= 0 && event.channel != channelFilter_) {
        return;
    }
    if ((channelMask_ & (1 << event.channel)) == 0) {
        return;
    }
    
    switch (event.type) {
        case midi::EventType::NoteOn:
            if (event.data2 == 0) {
                // Zero velocity note on = note off
                processMidiEvent(midi::MidiEvent(
                    static_cast<uint8_t>(midi::EventType::NoteOff) | event.channel,
                    event.data1, 0, event.timestamp));
            } else {
                lastNote_ = event.data1;
                lastVelocity_ = event.data2;
                targetFrequency_ = noteToFreq(event.data1);
                
                if (monophonic_) {
                    if (portamentoTime_ <= 0.0f) {
                        currentFrequency_ = targetFrequency_;
                    }
                }
                
                routeToVoices(event.channel, event.data1, event.data2, true);
            }
            break;
            
        case midi::EventType::NoteOff:
            routeToVoices(event.channel, event.data1, 0, false);
            break;
            
        case midi::EventType::ControlChange:
            // Forward CC to connected voice node
            if (auto voiceNode = connectedVoiceNode_.lock()) {
                voiceNode->controlChange(event.channel, event.data1, event.data2);
            }
            break;
            
        case midi::EventType::PitchBend:
            currentPitchBend_ = static_cast<float>(event.getPitchBendValue()) / 8192.0f * pitchBendRange_;
            if (auto voiceNode = connectedVoiceNode_.lock()) {
                voiceNode->pitchBend(event.channel, event.getPitchBendValue());
            }
            break;
            
        case midi::EventType::ProgramChange:
            // Could be used to change instrument/preset
            break;
            
        default:
            break;
    }
    
    // Echo to output if enabled
    if (echoOutput_) {
        pendingOutput_.push_back(event);
    }
}

void MidiInputNode::routeToVoices(uint8_t channel, uint8_t note, uint8_t velocity, bool isNoteOn) {
    if (auto voiceNode = connectedVoiceNode_.lock()) {
        if (isNoteOn) {
            voiceNode->noteOn(channel, note, velocity);
        } else {
            voiceNode->noteOff(channel, note);
        }
    }
}

float MidiInputNode::noteToFreq(uint8_t note) {
    return midi::noteToFrequency(note);
}

void MidiInputNode::connectToVoiceNode(std::shared_ptr<MidiVoiceNode> voiceNode) {
    connectedVoiceNode_ = voiceNode;
}

void MidiInputNode::triggerNoteOn(uint8_t note, uint8_t velocity) {
    midi::MidiEvent event(
        static_cast<uint8_t>(midi::EventType::NoteOn),
        note, velocity, 0);
    processMidiEvent(event);
}

void MidiInputNode::triggerNoteOff(uint8_t note) {
    midi::MidiEvent event(
        static_cast<uint8_t>(midi::EventType::NoteOff),
        note, 0, 0);
    processMidiEvent(event);
}

void MidiInputNode::triggerPitchBend(int16_t value) {
    uint8_t lsb = (value + 8192) & 0x7F;
    uint8_t msb = ((value + 8192) >> 7) & 0x7F;
    midi::MidiEvent event(
        static_cast<uint8_t>(midi::EventType::PitchBend),
        lsb, msb, 0);
    processMidiEvent(event);
}

} // namespace dsp_primitives
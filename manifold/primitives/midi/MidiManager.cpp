#include "MidiManager.h"
#include "MidiRingBuffer.h"
#include <juce_audio_basics/juce_audio_basics.h>
#include <cmath>
#include <algorithm>

namespace midi {

MidiManager::MidiManager() {
    for (auto& voice : voices_) {
        voice.reset();
    }
}

void MidiManager::processIncomingMidi(const juce::MidiBuffer& midiBuffer, double sampleRate) {
    currentSampleRate_ = sampleRate;
    
    for (const auto metadata : midiBuffer) {
        const juce::MidiMessage& msg = metadata.getMessage();
        
        MidiEvent event;
        event.timestamp = metadata.samplePosition;
        event.timeStampSeconds = sampleCounter_ / sampleRate + metadata.samplePosition / sampleRate;
        
        if (msg.isNoteOn()) {
            event.type = EventType::NoteOn;
            event.channel = msg.getChannel() - 1;  // JUCE uses 1-16, we use 0-15
            event.data1 = msg.getNoteNumber();
            event.data2 = msg.getVelocity();
        } else if (msg.isNoteOff()) {
            event.type = EventType::NoteOff;
            event.channel = msg.getChannel() - 1;
            event.data1 = msg.getNoteNumber();
            event.data2 = msg.getVelocity();
        } else if (msg.isController()) {
            event.type = EventType::ControlChange;
            event.channel = msg.getChannel() - 1;
            event.data1 = msg.getControllerNumber();
            event.data2 = msg.getControllerValue();
        } else if (msg.isPitchWheel()) {
            event.type = EventType::PitchBend;
            event.channel = msg.getChannel() - 1;
            int value = msg.getPitchWheelValue();
            event.data1 = value & 0x7F;
            event.data2 = (value >> 7) & 0x7F;
        } else if (msg.isProgramChange()) {
            event.type = EventType::ProgramChange;
            event.channel = msg.getChannel() - 1;
            event.data1 = msg.getProgramChangeNumber();
            event.data2 = 0;
        } else if (msg.isChannelPressure()) {
            event.type = EventType::ChannelPressure;
            event.channel = msg.getChannel() - 1;
            event.data1 = msg.getChannelPressureValue();
            event.data2 = 0;
        } else if (msg.isAftertouch()) {
            event.type = EventType::Aftertouch;
            event.channel = msg.getChannel() - 1;
            event.data1 = msg.getNoteNumber();
            event.data2 = msg.getAfterTouchValue();
        } else if (msg.isMidiClock()) {
            event.type = EventType::Clock;
            event.channel = 0;
            event.data1 = event.data2 = 0;
        } else if (msg.isMidiStart()) {
            event.type = EventType::Start;
            event.channel = 0;
            event.data1 = event.data2 = 0;
        } else if (msg.isMidiStop()) {
            event.type = EventType::Stop;
            event.channel = 0;
            event.data1 = event.data2 = 0;
        } else if (msg.isMidiContinue()) {
            event.type = EventType::Continue;
            event.channel = 0;
            event.data1 = event.data2 = 0;
        } else if (msg.isActiveSense()) {
            event.type = EventType::ActiveSensing;
            event.channel = 0;
            event.data1 = event.data2 = 0;
        } else if (msg.isResetAllControllers()) {
            event.type = EventType::Reset;
            event.channel = msg.getChannel() - 1;
            event.data1 = event.data2 = 0;
        } else {
            continue;  // Unknown message type
        }
        
        // Write to ring buffer for Lua/script consumption
        inputRing_.write(event.getStatusByte(), event.data1, event.data2, event.timestamp);
        
        // Process internally
        handleMidiEvent(event);
        
        // Fire callbacks
        std::lock_guard<std::mutex> lock(callbackMutex_);
        if (midiEventCb_) midiEventCb_(event);
    }
    
    sampleCounter_ += static_cast<int32_t>(midiBuffer.getLastEventTime() + 1);
}

void MidiManager::handleMidiEvent(const MidiEvent& event) {
    if (!isChannelEnabled(event.channel) && event.isChannelMessage()) {
        return;
    }
    
    switch (event.type) {
        case EventType::NoteOn:
            if (event.data2 == 0) {
                handleNoteOff(event.channel, event.data1);
            } else {
                handleNoteOn(event.channel, event.data1, event.data2);
            }
            break;
            
        case EventType::NoteOff:
            handleNoteOff(event.channel, event.data1);
            break;
            
        case EventType::ControlChange:
            updateCC(event.channel, event.data1, event.data2);
            {
                std::lock_guard<std::mutex> lock(callbackMutex_);
                if (ccCb_) ccCb_(event.channel, event.data1, event.data2, event);
            }
            break;
            
        case EventType::PitchBend:
            channels_[event.channel].pitchBend = event.getPitchBendValue();
            updateVoicePitchBends();
            {
                std::lock_guard<std::mutex> lock(callbackMutex_);
                if (pitchBendCb_) pitchBendCb_(event.channel, event.getPitchBendValue(), event);
            }
            break;
            
        case EventType::ProgramChange:
            channels_[event.channel].program = event.data1;
            {
                std::lock_guard<std::mutex> lock(callbackMutex_);
                if (programChangeCb_) programChangeCb_(event.channel, event.data1, event);
            }
            break;
            
        case EventType::ChannelPressure:
            channels_[event.channel].pressure = event.data1;
            break;
            
        default:
            break;
    }
}

void MidiManager::handleNoteOn(uint8_t channel, uint8_t note, uint8_t velocity) {
    auto& ch = channels_[channel];
    ch.notesHeld[note] = true;
    ch.numActiveNotes++;
    
    // Find or steal voice
    int voiceIdx = findVoicePlayingNote(note, channel);
    if (voiceIdx < 0) {
        voiceIdx = findFreeVoice();
    }
    
    if (voiceIdx >= 0) {
        auto& voice = voices_[voiceIdx];
        voice.reset();
        voice.note = note;
        voice.velocity = velocity;
        voice.channel = channel;
        voice.active = true;
        voice.startTime = sampleCounter_ / currentSampleRate_;
        voice.currentPitchBend = static_cast<float>(ch.pitchBend) / 8192.0f;
        
        numActiveVoices_.store(numActiveVoices_.load(std::memory_order_relaxed) + 1,
                               std::memory_order_release);
    }
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (noteOnCb_) noteOnCb_(channel, note, velocity, MidiEvent(0x90 | channel, note, velocity));
}

void MidiManager::handleNoteOff(uint8_t channel, uint8_t note) {
    auto& ch = channels_[channel];
    ch.notesHeld[note] = false;
    if (ch.numActiveNotes > 0) ch.numActiveNotes--;
    
    int voiceIdx = findVoicePlayingNote(note, channel);
    if (voiceIdx >= 0) {
        auto& voice = voices_[voiceIdx];
        if (ch.sustainPedal) {
            voice.sustained = true;
        } else {
            voice.active = false;
            voice.releaseTime = sampleCounter_ / currentSampleRate_;
            numActiveVoices_.store(numActiveVoices_.load(std::memory_order_relaxed) - 1,
                                   std::memory_order_release);
        }
    }
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (noteOffCb_) noteOffCb_(channel, note, MidiEvent(0x80 | channel, note, 0));
}

void MidiManager::updateCC(uint8_t channel, uint8_t cc, uint8_t value) {
    auto& ch = channels_[channel];
    ch.ccValues[cc] = value;
    
    switch (cc) {
        case Constants::DAMPER_PEDAL:
            ch.sustainPedal = value >= 64;
            if (!ch.sustainPedal) {
                // Release sustained voices
                for (auto& voice : voices_) {
                    if (voice.active && voice.sustained && voice.channel == channel) {
                        voice.active = false;
                        voice.sustained = false;
                        voice.releaseTime = sampleCounter_ / currentSampleRate_;
                        numActiveVoices_.store(numActiveVoices_.load(std::memory_order_relaxed) - 1,
                                               std::memory_order_release);
                    }
                }
            }
            break;
        case Constants::SOSTENUTO:
            ch.sostenutoPedal = value >= 64;
            break;
        case Constants::SOFT_PEDAL:
            ch.softPedal = value >= 64;
            break;
    }
}

void MidiManager::updateVoicePitchBends() {
    for (auto& voice : voices_) {
        if (voice.active) {
            voice.currentPitchBend = static_cast<float>(channels_[voice.channel].pitchBend) / 8192.0f;
        }
    }
}

int MidiManager::findFreeVoice() const {
    for (int i = 0; i < MAX_VOICES; ++i) {
        if (!voices_[i].active) return i;
    }
    
    // Voice stealing: find oldest non-sustained voice
    double oldestTime = currentSampleRate_;  // Large value
    int oldestIdx = -1;
    for (int i = 0; i < MAX_VOICES; ++i) {
        if (!voices_[i].sustained && voices_[i].startTime < oldestTime) {
            oldestTime = voices_[i].startTime;
            oldestIdx = i;
        }
    }
    
    // If all sustained, steal oldest sustained
    if (oldestIdx < 0) {
        oldestTime = currentSampleRate_;
        for (int i = 0; i < MAX_VOICES; ++i) {
            if (voices_[i].startTime < oldestTime) {
                oldestTime = voices_[i].startTime;
                oldestIdx = i;
            }
        }
    }
    
    return oldestIdx;
}

int MidiManager::findVoicePlayingNote(uint8_t note, uint8_t channel) const {
    for (int i = 0; i < MAX_VOICES; ++i) {
        if (voices_[i].active && voices_[i].note == note && 
            (voices_[i].channel == channel || omniMode_)) {
            return i;
        }
    }
    return -1;
}

void MidiManager::releaseVoice(int voiceIndex) {
    if (voiceIndex >= 0 && voiceIndex < MAX_VOICES && voices_[voiceIndex].active) {
        voices_[voiceIndex].active = false;
        voices_[voiceIndex].sustained = false;
        voices_[voiceIndex].releaseTime = sampleCounter_ / currentSampleRate_;
        numActiveVoices_.store(numActiveVoices_.load(std::memory_order_relaxed) - 1,
                               std::memory_order_release);
    }
}

void MidiManager::releaseAllVoices() {
    for (int i = 0; i < MAX_VOICES; ++i) {
        if (voices_[i].active) {
            voices_[i].active = false;
            voices_[i].sustained = false;
            voices_[i].releaseTime = sampleCounter_ / currentSampleRate_;
        }
    }
    numActiveVoices_.store(0, std::memory_order_release);
}

void MidiManager::fillOutgoingMidi(juce::MidiBuffer& outputBuffer) {
    uint8_t status, data1, data2;
    int32_t timestamp;
    while (outputRing_.read(status, data1, data2, timestamp)) {
        outputBuffer.addEvent(juce::MidiMessage(status, data1, data2), timestamp);
    }
}

void MidiManager::sendNoteOn(uint8_t channel, uint8_t note, uint8_t velocity) {
    outputRing_.write(static_cast<uint8_t>(EventType::NoteOn) | (channel & 0x0F),
                      note & 0x7F, velocity & 0x7F, 0);
}

void MidiManager::sendNoteOff(uint8_t channel, uint8_t note) {
    outputRing_.write(static_cast<uint8_t>(EventType::NoteOff) | (channel & 0x0F),
                      note & 0x7F, 0, 0);
}

void MidiManager::sendCC(uint8_t channel, uint8_t cc, uint8_t value) {
    outputRing_.write(static_cast<uint8_t>(EventType::ControlChange) | (channel & 0x0F),
                      cc & 0x7F, value & 0x7F, 0);
}

void MidiManager::sendPitchBend(uint8_t channel, int16_t value) {
    int centered = value + 8192;
    outputRing_.write(static_cast<uint8_t>(EventType::PitchBend) | (channel & 0x0F),
                      centered & 0x7F, (centered >> 7) & 0x7F, 0);
}

void MidiManager::sendProgramChange(uint8_t channel, uint8_t program) {
    outputRing_.write(static_cast<uint8_t>(EventType::ProgramChange) | (channel & 0x0F),
                      program & 0x7F, 0, 0);
}

void MidiManager::sendAllNotesOff(uint8_t channel) {
    sendCC(channel, Constants::ALL_NOTES_OFF, 0);
}

void MidiManager::sendAllSoundOff(uint8_t channel) {
    sendCC(channel, Constants::ALL_SOUND_OFF, 0);
}

void MidiManager::setNoteOnCallback(NoteOnCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    noteOnCb_ = cb;
}

void MidiManager::setNoteOffCallback(NoteOffCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    noteOffCb_ = cb;
}

void MidiManager::setControlChangeCallback(ControlChangeCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    ccCb_ = cb;
}

void MidiManager::setPitchBendCallback(PitchBendCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    pitchBendCb_ = cb;
}

void MidiManager::setProgramChangeCallback(ProgramChangeCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    programChangeCb_ = cb;
}

void MidiManager::setMidiEventCallback(MidiEventCallback cb) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    midiEventCb_ = cb;
}

void MidiManager::clearCallbacks() {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    noteOnCb_ = nullptr;
    noteOffCb_ = nullptr;
    ccCb_ = nullptr;
    pitchBendCb_ = nullptr;
    programChangeCb_ = nullptr;
    midiEventCb_ = nullptr;
}

void MidiManager::setChannelMask(uint16_t mask) {
    channelMask_ = mask;
}

bool MidiManager::isChannelEnabled(uint8_t channel) const {
    return (channelMask_ & (1 << (channel & 0x0F))) != 0;
}

void MidiManager::reset() {
    releaseAllVoices();
    for (auto& ch : channels_) {
        ch = ChannelState{};
    }
    inputRing_.clear();
    outputRing_.clear();
    sampleCounter_ = 0;
}

} // namespace midi

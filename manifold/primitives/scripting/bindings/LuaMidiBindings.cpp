#include "LuaControlBindings.h"
#include "../ILuaControlState.h"
#include "../ScriptableProcessor.h"

#include "../../../core/BehaviorCoreProcessor.h"
#include "../../../primitives/midi/MidiManager.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include <cstdio>
#include <map>
#include <vector>

// Helper to cast ScriptableProcessor to BehaviorCoreProcessor
static BehaviorCoreProcessor* toBcp(ScriptableProcessor* p) {
    return static_cast<BehaviorCoreProcessor*>(p);
}

// Helper to get MidiManager
static midi::MidiManager* getMidiManager(ScriptableProcessor* p) {
    auto* bcp = toBcp(p);
    return bcp ? bcp->getMidiManager() : nullptr;
}

// ============================================================================
// MIDI Bindings
// ============================================================================

void LuaControlBindings::registerMidiBindings(sol::state& lua,
                                              ILuaControlState& state) {
    auto* processor = state.getProcessor();
    auto* bcp = toBcp(processor);
    auto* midiMgr = getMidiManager(processor);
    
    // Create MIDI namespace/table
    lua["Midi"] = lua.create_table();
    
    // ---- MIDI:sendNoteOn(channel, note, velocity) ----
    // Channel is 1-16, note is 0-127, velocity is 0-127
    lua["Midi"]["sendNoteOn"] = [bcp](int channel, int note, int velocity) {
        if (!bcp) return;
        bcp->sendMidiNoteOn(channel, note, velocity);
    };
    
    // ---- MIDI:sendNoteOff(channel, note) ----
    lua["Midi"]["sendNoteOff"] = [bcp](int channel, int note) {
        if (!bcp) return;
        bcp->sendMidiNoteOff(channel, note);
    };
    
    // ---- MIDI:sendCC(channel, cc, value) ----
    lua["Midi"]["sendCC"] = [bcp](int channel, int cc, int value) {
        if (!bcp) return;
        bcp->sendMidiCC(channel, cc, value);
    };
    
    // ---- MIDI:sendPitchBend(channel, value) ----
    // Value is -8192 to +8191
    lua["Midi"]["sendPitchBend"] = [bcp](int channel, int value) {
        if (!bcp) return;
        bcp->sendMidiPitchBend(channel, value);
    };
    
    // ---- MIDI:sendProgramChange(channel, program) ----
    lua["Midi"]["sendProgramChange"] = [bcp](int channel, int program) {
        if (!bcp) return;
        bcp->sendMidiProgramChange(channel, program);
    };
    
    // ---- MIDI:sendAllNotesOff(channel) ----
    lua["Midi"]["sendAllNotesOff"] = [bcp](int channel) {
        if (!bcp) return;
        bcp->sendMidiCC(channel, 123, 0);  // All Notes Off CC
    };
    
    // ---- MIDI:sendAllSoundOff(channel) ----
    lua["Midi"]["sendAllSoundOff"] = [bcp](int channel) {
        if (!bcp) return;
        bcp->sendMidiCC(channel, 120, 0);  // All Sound Off CC
    };
    
    // ---- MIDI Callback Registration (using MidiManager) ----
    // These are called when MIDI events are received
    
    lua["Midi"]["onNoteOn"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setNoteOnCallback([callback](uint8_t channel, uint8_t note, uint8_t velocity, const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(channel + 1, note, velocity, event.timeStampSeconds);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onNoteOn callback error: %s\n", err.what());
            }
        });
    };
    
    lua["Midi"]["onNoteOff"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setNoteOffCallback([callback](uint8_t channel, uint8_t note, const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(channel + 1, note, event.timeStampSeconds);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onNoteOff callback error: %s\n", err.what());
            }
        });
    };
    
    lua["Midi"]["onControlChange"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setControlChangeCallback([callback](uint8_t channel, uint8_t cc, uint8_t value, const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(channel + 1, cc, value, event.timeStampSeconds);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onControlChange callback error: %s\n", err.what());
            }
        });
    };
    
    lua["Midi"]["onPitchBend"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setPitchBendCallback([callback](uint8_t channel, int16_t value, const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(channel + 1, value, event.timeStampSeconds);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onPitchBend callback error: %s\n", err.what());
            }
        });
    };
    
    lua["Midi"]["onProgramChange"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setProgramChangeCallback([callback](uint8_t channel, uint8_t program, const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(channel + 1, program, event.timeStampSeconds);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onProgramChange callback error: %s\n", err.what());
            }
        });
    };
    
    lua["Midi"]["onMidiEvent"] = [midiMgr](sol::function callback) {
        if (!midiMgr || !callback.valid()) return;
        midiMgr->setMidiEventCallback([callback](const midi::MidiEvent& event) {
            sol::state_view lua(callback.lua_state());
            auto result = callback(
                static_cast<int>(event.type),
                event.channel + 1,
                event.data1,
                event.data2,
                event.timeStampSeconds
            );
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "Midi onMidiEvent callback error: %s\n", err.what());
            }
        });
    };
    
    // ---- Clear all callbacks ----
    lua["Midi"]["clearCallbacks"] = [midiMgr]() {
        if (!midiMgr) return;
        midiMgr->clearCallbacks();
    };

    // ---- Poll next input event from MidiManager ring (UI-thread safe) ----
    lua["Midi"]["pollInputEvent"] = [&lua, midiMgr]() -> sol::object {
        if (!midiMgr) {
            return sol::make_object(lua, sol::nil);
        }

        uint8_t status = 0, data1 = 0, data2 = 0;
        int32_t timestamp = 0;
        if (!midiMgr->getInputRing().read(status, data1, data2, timestamp)) {
            return sol::make_object(lua, sol::nil);
        }

        sol::table event = lua.create_table();
        event["status"] = status;
        event["type"] = MidiStatus::type(status);
        event["channel"] = MidiStatus::channel(status) + 1;
        event["data1"] = data1;
        event["data2"] = data2;
        event["timestamp"] = timestamp;
        return sol::make_object(lua, event);
    };
    
    // ---- MIDI State Queries ----
    lua["Midi"]["getNumActiveVoices"] = [midiMgr]() -> int {
        if (!midiMgr) return 0;
        return midiMgr->getNumActiveVoices();
    };
    
    lua["Midi"]["getChannelState"] = [&lua, midiMgr](int channel) -> sol::table {
        sol::table result = lua.create_table();
        if (!midiMgr) return result;
        
        const auto& state = midiMgr->getChannelState(channel - 1);
        result["program"] = state.program;
        result["pressure"] = state.pressure;
        result["pitchBend"] = state.pitchBend;
        result["sustainPedal"] = state.sustainPedal;
        result["sostenutoPedal"] = state.sostenutoPedal;
        result["softPedal"] = state.softPedal;
        result["numActiveNotes"] = state.numActiveNotes;
        
        // CC values table
        sol::table ccTable = lua.create_table();
        for (int i = 0; i < 128; ++i) {
            if (state.ccValues[i] != 0) {
                ccTable[i] = state.ccValues[i];
            }
        }
        result["cc"] = ccTable;
        
        return result;
    };
    
    // ---- MIDI Settings ----
    lua["Midi"]["setChannelMask"] = [midiMgr](int mask) {
        if (!midiMgr) return;
        midiMgr->setChannelMask(static_cast<uint16_t>(mask));
    };
    
    lua["Midi"]["getChannelMask"] = [midiMgr]() -> int {
        if (!midiMgr) return 0xFFFF;
        return 0xFFFF;  // TODO: expose channelMask getter
    };
    
    lua["Midi"]["setOmniMode"] = [midiMgr](bool omni) {
        if (!midiMgr) return;
        midiMgr->setOmniMode(omni);
    };
    
    lua["Midi"]["isOmniMode"] = [midiMgr]() -> bool {
        if (!midiMgr) return true;
        return midiMgr->isOmniMode();
    };
    
    lua["Midi"]["reset"] = [midiMgr]() {
        if (!midiMgr) return;
        midiMgr->reset();
    };
    
    // ---- MIDI Learn ----
    lua["Midi"]["learn"] = [bcp](const std::string& paramPath) {
        (void)paramPath;
        if (!bcp) return false;
        // TODO: Implement MIDI learn
        return true;
    };
    
    lua["Midi"]["unlearn"] = [bcp](const std::string& paramPath) {
        (void)paramPath;
        if (!bcp) return false;
        // TODO: Remove MIDI mapping
        return true;
    };
    
    lua["Midi"]["getMappings"] = [&lua]() -> sol::table {
        sol::table mappings = lua.create_table();
        // TODO: Populate from stored mappings
        return mappings;
    };
    
    // ---- MIDI Thru ----
    lua["Midi"]["thruEnabled"] = sol::overload(
        [bcp]() -> bool {
            if (!bcp) return false;
            return bcp->isMidiThruEnabled();
        },
        [bcp](bool enabled) {
            if (!bcp) return;
            bcp->setMidiThruEnabled(enabled);
        }
    );
    
    // ---- MIDI Device Management ----
    lua["Midi"]["inputDevices"] = [&lua, bcp]() -> sol::table {
        sol::table devices = lua.create_table();
        if (!bcp) return devices;
        auto deviceList = bcp->getMidiInputDevices();
        for (size_t i = 0; i < deviceList.size(); ++i) {
            devices[i + 1] = deviceList[i];
        }
        return devices;
    };
    
    lua["Midi"]["outputDevices"] = [&lua, bcp]() -> sol::table {
        sol::table devices = lua.create_table();
        if (!bcp) return devices;
        auto deviceList = bcp->getMidiOutputDevices();
        for (size_t i = 0; i < deviceList.size(); ++i) {
            devices[i + 1] = deviceList[i];
        }
        return devices;
    };
    
    lua["Midi"]["openInput"] = [bcp](int deviceIndex) -> bool {
        if (!bcp) return false;
        return bcp->openMidiInput(deviceIndex);
    };
    
    lua["Midi"]["openOutput"] = [bcp](int deviceIndex) -> bool {
        if (!bcp) return false;
        return bcp->openMidiOutput(deviceIndex);
    };
    
    lua["Midi"]["closeInput"] = [bcp]() {
        if (!bcp) return;
        bcp->closeMidiInput();
    };
    
    lua["Midi"]["closeOutput"] = [bcp]() {
        if (!bcp) return;
        bcp->closeMidiOutput();
    };
    
    // ---- MIDI Utility Functions ----
    lua["Midi"]["noteToFrequency"] = [](int note) -> float {
        return midi::noteToFrequency(note);
    };
    
    lua["Midi"]["frequencyToNote"] = [](float frequency) -> int {
        return midi::frequencyToNote(frequency);
    };
    
    lua["Midi"]["noteName"] = [](int note) -> std::string {
        return midi::noteToString(note);
    };
    
    // ---- MIDI Constants ----
    lua["Midi"]["NOTE_OFF"] = 0x80;
    lua["Midi"]["NOTE_ON"] = 0x90;
    lua["Midi"]["AFTERTOUCH"] = 0xA0;
    lua["Midi"]["CONTROL_CHANGE"] = 0xB0;
    lua["Midi"]["PROGRAM_CHANGE"] = 0xC0;
    lua["Midi"]["CHANNEL_PRESSURE"] = 0xD0;
    lua["Midi"]["PITCH_BEND"] = 0xE0;
    lua["Midi"]["SYSEX"] = 0xF0;
    lua["Midi"]["CLOCK"] = 0xF8;
    lua["Midi"]["START"] = 0xFA;
    lua["Midi"]["STOP"] = 0xFC;
    lua["Midi"]["CONTINUE"] = 0xFB;
    
    // Common CC numbers
    lua["Midi"]["CC_MODWHEEL"] = 1;
    lua["Midi"]["CC_VOLUME"] = 7;
    lua["Midi"]["CC_PAN"] = 10;
    lua["Midi"]["CC_EXPRESSION"] = 11;
    lua["Midi"]["CC_SUSTAIN"] = 64;
    lua["Midi"]["CC_PORTAMENTO"] = 65;
    lua["Midi"]["CC_SOSTENUTO"] = 66;
    lua["Midi"]["CC_SOFT"] = 67;
    lua["Midi"]["CC_RESONANCE"] = 71;
    lua["Midi"]["CC_RELEASE"] = 72;
    lua["Midi"]["CC_ATTACK"] = 73;
    lua["Midi"]["CC_CUTOFF"] = 74;
    lua["Midi"]["CC_DECAY"] = 75;
    lua["Midi"]["CC_SUSTAIN_LEVEL"] = 76;
    
    // Create EventType constants table
    sol::table eventTypes = lua.create_table();
    eventTypes["NoteOff"] = 0x80;
    eventTypes["NoteOn"] = 0x90;
    eventTypes["Aftertouch"] = 0xA0;
    eventTypes["ControlChange"] = 0xB0;
    eventTypes["ProgramChange"] = 0xC0;
    eventTypes["ChannelPressure"] = 0xD0;
    eventTypes["PitchBend"] = 0xE0;
    eventTypes["Sysex"] = 0xF0;
    eventTypes["Clock"] = 0xF8;
    eventTypes["Start"] = 0xFA;
    eventTypes["Stop"] = 0xFC;
    eventTypes["Continue"] = 0xFB;
    lua["Midi"]["EventType"] = eventTypes;
}

# MIDI Implementation Summary

## Overview
This document describes the comprehensive MIDI implementation across all domains of the Manifold application.

## C++ Core Implementation

### 1. MIDI Event System (`manifold/primitives/midi/`)

#### MidiEvent.h/cpp
- **MidiEvent struct**: Comprehensive MIDI message representation
  - Event types: NoteOn, NoteOff, ControlChange, PitchBend, ProgramChange, etc.
  - Channel handling (0-15 internal, 1-16 display)
  - Timestamp support for sample-accurate timing
  - Convenience accessors: `isNoteOn()`, `isNoteOff()`, `getPitchBendValue()`, etc.
  - `toString()` method for debugging/monitoring

#### Utility Functions
- `noteToFrequency(note)`: Convert MIDI note to frequency (440Hz = A4)
- `frequencyToNote(freq)`: Convert frequency back to MIDI note
- `noteName(note)`: Get note name (C, C#, D, etc.)
- `noteOctave(note)`: Get octave number
- `noteToString(note)`: Full note string (e.g., "C4")

#### MIDI Constants
Standard CC numbers defined:
- `DAMPER_PEDAL` (64), `PORTAMENTO` (65), `SOSTENUTO` (66)
- `MOD_WHEEL` (1), `VOLUME` (7), `PAN` (10), `EXPRESSION` (11)
- `CUTOFF` (74), `RESONANCE` (71), `ATTACK_TIME` (73), `RELEASE_TIME` (72)

### 2. MIDI Manager (`MidiManager.h/cpp`)

Central MIDI handling with callbacks and state tracking:

#### Features
- **Polyphonic voice management**: Up to 32 voices
- **Per-channel state tracking**: CC values, program, pitch bend, sustain pedal
- **Lock-free ring buffers**: For audio/control thread communication
- **Callback system**: NoteOn, NoteOff, CC, PitchBend, ProgramChange, general MIDI event

#### Voice State Tracking
```cpp
struct VoiceState {
    uint8_t note, velocity, channel;
    bool active, sustained;
    double startTime, releaseTime;
    float currentPitchBend;
};
```

#### Channel State
```cpp
struct ChannelState {
    std::array<uint8_t, 128> ccValues;
    std::array<bool, 128> notesHeld;
    uint8_t program, pressure;
    int16_t pitchBend;
    bool sustainPedal, sostenutoPedal, softPedal;
};
```

#### API
- `processIncomingMidi(buffer, sampleRate)`: Process MIDI from audio thread
- `fillOutgoingMidi(buffer)`: Send MIDI to audio thread output
- `set*Callback()`: Register event handlers
- `getChannelState(channel)`: Query channel state
- `getNumActiveVoices()`: Get active voice count

### 3. DSP Nodes for MIDI Synthesis (`dsp/core/nodes/`)

#### MidiVoiceNode
Full polyphonic synthesizer voice processor:

**Waveforms**: Sine, Saw, Square, Triangle, Noise, Pulse, SuperSaw

**Parameters**:
- `setWaveform(shape)`: 0-6 waveform selection
- `setAttack/Decay/Sustain/Release(seconds)`: ADSR envelope
- `setFilterCutoff(freq)`: 20Hz - 20kHz
- `setFilterResonance(q)`: 0.1 - 10.0
- `setFilterEnvAmount(amount)`: -1.0 to +1.0 (filter envelope modulation)
- `setPolyphony(voices)`: 1-16 voices
- `setUnison(voices)`: 1-8 unison voices
- `setDetune(cents)`: 0-100 cents
- `setSpread(amount)`: 0-1 stereo spread
- `setGlide(seconds)`: Portamento time

**Voice Methods**:
- `noteOn(channel, note, velocity)`: Trigger a note
- `noteOff(channel, note)`: Release a note
- `allNotesOff()`: Release all voices
- `allSoundOff()`: Immediately stop all voices
- `pitchBend(channel, value)`: Apply pitch bend (-8192 to +8191)
- `controlChange(channel, cc, value)`: Process CC messages

**Features**:
- Per-voice state-variable filter
- Polyphonic glide/portamento
- Unison detune and stereo spread
- Voice stealing (oldest voice released first)
- Sustain pedal support

#### MidiInputNode
Routes MIDI input to voice processors:

**Settings**:
- `setChannelFilter(channel)`: -1 = all channels
- `setChannelMask(mask)`: Bit mask for enabled channels
- `setOmniMode(true/false)`: Respond to all channels
- `setMonophonic(true/false)`: Single voice mode
- `setPortamento(seconds)`: Glide time
- `setPitchBendRange(semitones)`: +/- semitones

**Manual Trigger Functions**:
- `triggerNoteOn(note, velocity)`: For UI/testing
- `triggerNoteOff(note)`: For UI/testing
- `triggerPitchBend(value)`: For UI/testing

### 4. BehaviorCoreProcessor Integration

The processor now includes:
- `midiManager_`: Shared_ptr to MidiManager
- `getMidiManager()`: Access to MIDI manager for advanced scripting
- `processMidiInput()`: Uses MidiManager for event processing
- `drainMidiOutput()`: Outputs from MidiManager

## Lua Scripting API

### MIDI Namespace (`Midi.*`)

#### Sending MIDI
```lua
Midi.sendNoteOn(channel, note, velocity)      -- channel 1-16, note 0-127
Midi.sendNoteOff(channel, note)
Midi.sendCC(channel, cc, value)               -- CC 0-127, value 0-127
Midi.sendPitchBend(channel, value)            -- -8192 to +8191
Midi.sendProgramChange(channel, program)
Midi.sendAllNotesOff(channel)
Midi.sendAllSoundOff(channel)
```

#### Event Callbacks
```lua
Midi.onNoteOn(function(channel, note, velocity, timestamp)
    -- Note on received
end)

Midi.onNoteOff(function(channel, note, timestamp)
    -- Note off received
end)

Midi.onControlChange(function(channel, cc, value, timestamp)
    -- CC received
end)

Midi.onPitchBend(function(channel, value, timestamp)
    -- Pitch bend received
end)

Midi.onProgramChange(function(channel, program, timestamp)
    -- Program change received
end)

Midi.onMidiEvent(function(type, channel, data1, data2, timestamp)
    -- All MIDI events
end)
```

#### State Queries
```lua
local numVoices = Midi.getNumActiveVoices()
local channelState = Midi.getChannelState(channel)
-- channelState.cc[74] = cutoff value
-- channelState.pitchBend = current bend
-- channelState.sustainPedal = true/false
```

#### Settings
```lua
Midi.setChannelMask(0xFFFF)     -- Enable all channels
Midi.setOmniMode(true)           -- Listen to all channels
Midi.reset()                     -- Reset all state
```

#### Utility Functions
```lua
local freq = Midi.noteToFrequency(69)      -- 440.0
local note = Midi.frequencyToNote(440.0)   -- 69
local name = Midi.noteName(69)             -- "A"
local str = Midi.noteToString(69)          -- "A4"
```

#### Constants
```lua
Midi.NOTE_ON, Midi.NOTE_OFF, Midi.CONTROL_CHANGE
Midi.CC_MODWHEEL, Midi.CC_VOLUME, Midi.CC_PAN
Midi.CC_CUTOFF, Midi.CC_RESONANCE
Midi.CC_ATTACK, Midi.CC_RELEASE, Midi.CC_SUSTAIN
```

## MIDI Synth Project

### Project Structure
```
UserScripts/projects/MidiSynth_uiproject/
├── dsp/
│   └── main.lua              # DSP graph with polyphonic synthesis
├── ui/
│   ├── main.ui.lua           # Main UI layout
│   ├── behaviors/            # Lua behavior scripts
│   │   ├── main.lua          # Main behavior/coordinator
│   │   ├── oscillator.lua    # Oscillator panel logic
│   │   ├── envelope.lua      # ADSR envelope logic
│   │   ├── keyboard.lua      # Virtual piano keyboard
│   │   └── midi_monitor.lua  # MIDI event display
│   └── components/           # UI component definitions
│       ├── header.ui.lua
│       ├── oscillator.ui.lua
│       ├── envelope.ui.lua
│       ├── filter.ui.lua
│       ├── effects.ui.lua
│       ├── keyboard.ui.lua
│       ├── spectrum.ui.lua
│       ├── midi_monitor.ui.lua
│       └── presets.ui.lua
└── themes/
    └── dark.lua              # Color theme
```

### DSP Graph
```
MidiInput -> MidiVoice -> Chorus -> Delay -> Reverb -> 
            Filter -> Compressor -> Limiter -> MasterGain -> Output
                          |
                     SpectrumAnalyzer
```

### UI Features
- **Oscillator Panel**: Waveform selector, polyphony, unison, detune, glide
- **Envelope Panel**: ADSR with visual graph
- **Filter Panel**: Cutoff, resonance, envelope amount
- **Effects Panel**: Chorus, delay, reverb with individual controls
- **Virtual Keyboard**: 5-octave piano keyboard with velocity
- **Spectrum Analyzer**: Real-time frequency display
- **MIDI Monitor**: Incoming MIDI event log
- **Presets**: Save/load synth patches

### Parameter Paths (OSC/Automation)
```
/midi/synth/waveform        -- 0-6
/midi/synth/polyphony       -- 1-16
/midi/synth/attack          -- 0.001-10.0s
/midi/synth/decay           -- 0.001-10.0s
/midi/synth/sustain         -- 0-1
/midi/synth/release         -- 0.001-10.0s
/midi/synth/filterCutoff    -- 20-20000Hz
/midi/synth/filterResonance -- 0.1-10.0
/midi/synth/volume          -- 0-1
/midi/synth/reverbMix       -- 0-1
/midi/synth/delayMix        -- 0-1
/midi/synth/chorusMix       -- 0-1
```

## Monitoring Features

### Real-time MIDI Monitoring
- Event type display (Note On/Off, CC, Pitch Bend, etc.)
- Channel, note number, velocity, CC number/value
- Timestamp information
- Activity LED indicator

### Voice Activity
- Active voice count display
- Per-channel note tracking
- Sustain pedal state

### Integration with Existing Systems
- **OSC Control**: All parameters exposed via OSC endpoints
- **OSCQuery**: MIDI parameters discoverable
- **State Projection**: MIDI state available to Lua UI
- **DSP Graph**: Full integration with existing node system

## Usage Examples

### Basic MIDI Synthesis
```lua
-- In DSP script
function buildPlugin(ctx)
    local graph = ctx.graph
    
    -- Create MIDI input
    local midiIn = graph:addNode("MidiInput", "midi_in")
    
    -- Create polyphonic voice
    local voice = graph:addNode("MidiVoice", "synth")
    voice:setWaveform(1)  -- Saw
    voice:setAttack(0.01)
    voice:setRelease(0.3)
    
    -- Connect
    midiIn:connectToVoiceNode(voice)
    graph:connectToOutput(voice, 0)
end
```

### MIDI Monitoring Script
```lua
-- Monitor incoming MIDI
Midi.onNoteOn(function(ch, note, vel, time)
    print(string.format("Note On: %s%d (vel %d) on ch %d", 
        Midi.noteName(note), Midi.noteOctave(note), vel, ch))
end)

Midi.onControlChange(function(ch, cc, val, time)
    print(string.format("CC %d = %d on ch %d", cc, val, ch))
end)
```

### MIDI Learn Implementation
```lua
-- Simple MIDI learn
local learningParam = nil

Midi.onControlChange(function(ch, cc, val, time)
    if learningParam then
        -- Map this CC to the parameter
        mapCCToParam(cc, learningParam)
        learningParam = nil
    end
end)

function startLearn(paramName)
    learningParam = paramName
end
```

## Files Added/Modified

### New Files
- `manifold/primitives/midi/MidiEvent.h/cpp`
- `manifold/primitives/midi/MidiManager.h/cpp`
- `dsp/core/nodes/MidiVoiceNode.h/cpp`
- `dsp/core/nodes/MidiInputNode.h/cpp`
- `UserScripts/projects/MidiSynth_uiproject/` (complete project)

### Modified Files
- `CMakeLists.txt`: Added new source files
- `manifold/core/BehaviorCoreProcessor.h/cpp`: Integrated MidiManager
- `manifold/primitives/scripting/bindings/LuaMidiBindings.cpp`: Enhanced API

## Building

```bash
# Configure
cmake -S . -B build-dev -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo

# Build
cmake --build build-dev --target Manifold_Standalone

# Run
./build-dev/Manifold_artefacts/RelWithDebInfo/Standalone/Manifold
```

## Future Enhancements

Potential additions:
- Arpeggiator node
- MIDI sequencer
- MPE (MIDI Polyphonic Expression) support
- More filter types (Moog, TB-303 emulation)
- LFOs and modulation matrix
- Microtonal tuning support
- MIDI clock sync for delays/LFOs

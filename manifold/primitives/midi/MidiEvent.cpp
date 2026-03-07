#include "MidiEvent.h"
#include <cstdio>
#include <cmath>

namespace midi {

std::string MidiEvent::toString() const {
    char buffer[128];
    switch (type) {
        case EventType::NoteOn:
            if (data2 == 0) {
                std::snprintf(buffer, sizeof(buffer), 
                    "NoteOff ch=%d note=%s%d (%d) vel=0", 
                    channel + 1, noteName(data1), noteOctave(data1), data1);
            } else {
                std::snprintf(buffer, sizeof(buffer), 
                    "NoteOn ch=%d note=%s%d (%d) vel=%d", 
                    channel + 1, noteName(data1), noteOctave(data1), data1, data2);
            }
            break;
        case EventType::NoteOff:
            std::snprintf(buffer, sizeof(buffer), 
                "NoteOff ch=%d note=%s%d (%d) vel=%d", 
                channel + 1, noteName(data1), noteOctave(data1), data1, data2);
            break;
        case EventType::Aftertouch:
            std::snprintf(buffer, sizeof(buffer), 
                "Aftertouch ch=%d note=%s%d (%d) pressure=%d", 
                channel + 1, noteName(data1), noteOctave(data1), data1, data2);
            break;
        case EventType::ControlChange:
            std::snprintf(buffer, sizeof(buffer), 
                "CC ch=%d cc=%d value=%d", channel + 1, data1, data2);
            break;
        case EventType::ProgramChange:
            std::snprintf(buffer, sizeof(buffer), 
                "ProgramChange ch=%d program=%d", channel + 1, data1);
            break;
        case EventType::ChannelPressure:
            std::snprintf(buffer, sizeof(buffer), 
                "ChannelPressure ch=%d pressure=%d", channel + 1, data1);
            break;
        case EventType::PitchBend:
            std::snprintf(buffer, sizeof(buffer), 
                "PitchBend ch=%d value=%d", channel + 1, getPitchBendValue());
            break;
        case EventType::Clock:
            return "MIDI Clock";
        case EventType::Start:
            return "MIDI Start";
        case EventType::Stop:
            return "MIDI Stop";
        case EventType::Continue:
            return "MIDI Continue";
        case EventType::ActiveSensing:
            return "Active Sensing";
        case EventType::Reset:
            return "MIDI Reset";
        default:
            std::snprintf(buffer, sizeof(buffer), 
                "Unknown type=0x%02X ch=%d data1=%d data2=%d", 
                static_cast<int>(type), channel + 1, data1, data2);
            break;
    }
    return std::string(buffer);
}

} // namespace midi

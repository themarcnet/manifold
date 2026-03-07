-- Test MIDI functionality
print("=== MIDI Test ===")

if Midi then
    print("Midi namespace exists: YES")
    print("Midi.sendNoteOn exists:", type(Midi.sendNoteOn))
    print("Midi.onNoteOn exists:", type(Midi.onNoteOn))
    print("Midi.noteToFrequency exists:", type(Midi.noteToFrequency))
    
    -- Test utility function
    local freq = Midi.noteToFrequency(69)
    print("A4 frequency:", freq)
    
    -- Test constants
    print("NOTE_ON constant:", Midi.NOTE_ON)
    print("CC_CUTOFF constant:", Midi.CC_CUTOFF)
else
    print("ERROR: Midi namespace not found!")
end

if Primitives then
    print("\n=== DSP Nodes Test ===")
    print("Primitives.MidiVoiceNode exists:", type(Primitives.MidiVoiceNode))
    print("Primitives.MidiInputNode exists:", type(Primitives.MidiInputNode))
else
    print("ERROR: Primitives namespace not found!")
end

print("\n=== Test Complete ===")

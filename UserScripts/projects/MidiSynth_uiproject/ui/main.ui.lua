return {
  id = "root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1280,
  h = 720,
  style = { bg = 0xff0b1020 },
  behavior = "ui/behaviors/main.lua",
  children = {
    -- Header
    { id = "header", type = "Panel", x = 24, y = 16, w = 1232, h = 72, style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "title", type = "Label", x = 44, y = 28, w = 280, h = 26, props = { text = "MIDISYNTH" }, style = { colour = 0xffe2e8f0, fontSize = 22 } },
    { id = "subtitle", type = "Label", x = 44, y = 56, w = 400, h = 16, props = { text = "8-voice polysynth with ADSR envelope & swappable FX" }, style = { colour = 0xff94a3b8, fontSize = 11 } },
    { id = "voicesLabel", type = "Label", x = 460, y = 32, w = 100, h = 14, props = { text = "Voices" }, style = { colour = 0xff64748b, fontSize = 10 } },
    { id = "voicesValue", type = "Label", x = 460, y = 50, w = 100, h = 18, props = { text = "8 voice poly" }, style = { colour = 0xff4ade80, fontSize = 13 } },
    { id = "midiInputLabel", type = "Label", x = 580, y = 26, w = 200, h = 14, props = { text = "MIDI Input" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "midiInputDropdown", type = "Dropdown", x = 580, y = 44, w = 280, h = 26, props = { options = { "None (Disabled)" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8 } },
    { id = "refreshMidi", type = "Button", x = 870, y = 44, w = 70, h = 26, props = { label = "Refresh" }, style = { bg = 0xff1d4ed8, fontSize = 10 } },
    { id = "midiState", type = "Label", x = 1150, y = 28, w = 90, h = 20, props = { text = "waiting" }, style = { colour = 0xfff59e0b, fontSize = 12, justification = Justify.centredRight } },

    -- Oscillator Section
    { id = "oscPanel", type = "Panel", x = 24, y = 104, w = 220, h = 200, style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "oscTitle", type = "Label", x = 40, y = 118, w = 180, h = 16, props = { text = "OSCILLATOR" }, style = { colour = 0xff7dd3fc, fontSize = 12 } },
    { id = "waveformLabel", type = "Label", x = 40, y = 142, w = 100, h = 14, props = { text = "Waveform" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "waveformDropdown", type = "Dropdown", x = 40, y = 160, w = 188, h = 26, props = { options = { "Sine", "Saw", "Square", "Triangle", "Blend" }, selected = 2, max_visible_rows = 5 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8 } },
    { id = "drive", type = "Knob", x = 44, y = 196, w = 76, h = 90, props = { min = 0, max = 20, step = 0.1, value = 1.8, label = "Drive" }, style = { colour = 0xfff97316 } },
    { id = "output", type = "Knob", x = 140, y = 196, w = 76, h = 90, props = { min = 0, max = 1, step = 0.01, value = 0.8, label = "Output" }, style = { colour = 0xff34d399 } },

    -- Filter Section
    { id = "filterPanel", type = "Panel", x = 260, y = 104, w = 220, h = 200, style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "filterTitle", type = "Label", x = 276, y = 118, w = 180, h = 16, props = { text = "FILTER" }, style = { colour = 0xffc084fc, fontSize = 12 } },
    { id = "filterTypeLabel", type = "Label", x = 276, y = 142, w = 100, h = 14, props = { text = "Type" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "filterTypeDropdown", type = "Dropdown", x = 276, y = 158, w = 188, h = 24, props = { options = { "SVF Lowpass", "SVF Bandpass", "SVF Highpass", "SVF Notch" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff1e293b, colour = 0xffa78bfa } },
    { id = "cutoff", type = "Knob", x = 276, y = 188, w = 90, h = 100, props = { min = 80, max = 16000, step = 1, value = 3200, label = "Cutoff" }, style = { colour = 0xffa78bfa } },
    { id = "resonance", type = "Knob", x = 374, y = 188, w = 90, h = 100, props = { min = 0.1, max = 2.0, step = 0.01, value = 0.75, label = "Reso" }, style = { colour = 0xffd8b4fe } },

    -- ADSR Section
    { id = "adsrPanel", type = "Panel", x = 496, y = 104, w = 280, h = 200, style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "adsrTitle", type = "Label", x = 512, y = 118, w = 240, h = 16, props = { text = "ADSR ENVELOPE" }, style = { colour = 0xfffda4af, fontSize = 12 } },
    { id = "attack", type = "Knob", x = 512, y = 148, w = 60, h = 80, props = { min = 0.001, max = 5, step = 0.001, value = 0.05, label = "Attack" }, style = { colour = 0xfffb7185 } },
    { id = "decay", type = "Knob", x = 580, y = 148, w = 60, h = 80, props = { min = 0.001, max = 5, step = 0.001, value = 0.2, label = "Decay" }, style = { colour = 0xfff59e0b } },
    { id = "sustain", type = "Knob", x = 648, y = 148, w = 60, h = 80, props = { min = 0, max = 1, step = 0.01, value = 0.7, label = "Sustain" }, style = { colour = 0xff4ade80 } },
    { id = "release", type = "Knob", x = 716, y = 148, w = 60, h = 80, props = { min = 0.001, max = 10, step = 0.001, value = 0.4, label = "Release" }, style = { colour = 0xff22d3ee } },
    -- ADSR value labels
    { id = "attackValue", type = "Label", x = 512, y = 230, w = 60, h = 14, props = { text = "50ms" }, style = { colour = 0xffcbd5e1, fontSize = 9, justification = Justify.centred } },
    { id = "decayValue", type = "Label", x = 580, y = 230, w = 60, h = 14, props = { text = "200ms" }, style = { colour = 0xffcbd5e1, fontSize = 9, justification = Justify.centred } },
    { id = "sustainValue", type = "Label", x = 648, y = 230, w = 60, h = 14, props = { text = "70%" }, style = { colour = 0xffcbd5e1, fontSize = 9, justification = Justify.centred } },
    { id = "releaseValue", type = "Label", x = 716, y = 230, w = 60, h = 14, props = { text = "400ms" }, style = { colour = 0xffcbd5e1, fontSize = 9, justification = Justify.centred } },

    -- FX1 Section
    { id = "fx1Panel", type = "Panel", x = 792, y = 104, w = 220, h = 200, style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "fx1Title", type = "Label", x = 808, y = 118, w = 180, h = 16, props = { text = "FX SLOT 1" }, style = { colour = 0xff22d3ee, fontSize = 12 } },
    { id = "fx1TypeDropdown", type = "Dropdown", x = 808, y = 138, w = 188, h = 24, props = { options = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener", "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap", "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ", "Limiter", "Transient" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee } },
    { id = "fx1Param1", type = "Knob", x = 808, y = 168, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Param 1" }, style = { colour = 0xff22d3ee } },
    { id = "fx1Param2", type = "Knob", x = 874, y = 168, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Param 2" }, style = { colour = 0xff38bdf8 } },
    { id = "fx1Mix", type = "Knob", x = 940, y = 168, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Mix" }, style = { colour = 0xff4ade80 } },

    -- FX2 Section
    { id = "fx2Panel", type = "Panel", x = 1028, y = 104, w = 228, h = 200, style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "fx2Title", type = "Label", x = 1044, y = 118, w = 200, h = 16, props = { text = "FX SLOT 2" }, style = { colour = 0xfff59e0b, fontSize = 12 } },
    { id = "fx2TypeDropdown", type = "Dropdown", x = 1044, y = 138, w = 196, h = 24, props = { options = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener", "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap", "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ", "Limiter", "Transient" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xfff59e0b } },
    { id = "fx2Param1", type = "Knob", x = 1044, y = 168, w = 58, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Param 1" }, style = { colour = 0xfff59e0b } },
    { id = "fx2Param2", type = "Knob", x = 1114, y = 168, w = 58, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Param 2" }, style = { colour = 0xfff97316 } },
    { id = "fx2Mix", type = "Knob", x = 1184, y = 168, w = 58, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Mix" }, style = { colour = 0xfffb7185 } },

    -- Performance Section (moved below FX)
    { id = "perfPanel", type = "Panel", x = 24, y = 320, w = 400, h = 120, style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "perfTitle", type = "Label", x = 40, y = 334, w = 200, h = 16, props = { text = "PERFORMANCE" }, style = { colour = 0xff4ade80, fontSize = 12 } },
    { id = "testNote", type = "Button", x = 40, y = 360, w = 100, h = 28, props = { label = "Test C4" }, style = { bg = 0xff1d4ed8, fontSize = 11 } },
    { id = "panic", type = "Button", x = 150, y = 360, w = 100, h = 28, props = { label = "Panic" }, style = { bg = 0xff7f1d1d, fontSize = 11 } },
    { id = "currentNote", type = "Label", x = 40, y = 400, w = 180, h = 18, props = { text = "Note: --" }, style = { colour = 0xffe2e8f0, fontSize = 13 } },
    { id = "voiceStatus", type = "Label", x = 260, y = 360, w = 140, h = 60, props = { text = "Voices: idle" }, style = { colour = 0xff94a3b8, fontSize = 10 } },

    -- Delay/Reverb Section
    { id = "timefxPanel", type = "Panel", x = 440, y = 320, w = 400, h = 120, style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "timefxTitle", type = "Label", x = 456, y = 334, w = 200, h = 16, props = { text = "TIME EFFECTS" }, style = { colour = 0xfffb7185, fontSize = 12 } },
    { id = "delayMix", type = "Knob", x = 456, y = 360, w = 60, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.18, label = "Dly Mix" }, style = { colour = 0xfff59e0b } },
    { id = "delayTime", type = "Slider", x = 530, y = 360, w = 140, h = 20, props = { min = 40, max = 900, step = 1, value = 220, label = "Time", suffix = "ms" }, style = { colour = 0xfff59e0b, bg = 0xff1e293b } },
    { id = "delayFeedback", type = "Slider", x = 530, y = 388, w = 140, h = 20, props = { min = 0, max = 0.99, step = 0.01, value = 0.24, label = "FB" }, style = { colour = 0xfff97316, bg = 0xff1e293b } },
    { id = "reverbWet", type = "Knob", x = 700, y = 360, w = 60, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.16, label = "Verb" }, style = { colour = 0xfffb7185 } },

    -- Keyboard Section
    { id = "keyboardPanel", type = "Panel", x = 24, y = 456, w = 1232, h = 140, style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "keyboardTitle", type = "Label", x = 44, y = 470, w = 200, h = 16, props = { text = "KEYBOARD" }, style = { colour = 0xff94a3b8, fontSize = 12 } },
    { id = "octaveDown", type = "Button", x = 44, y = 494, w = 60, h = 28, props = { label = "Oct -" }, style = { bg = 0xff1e293b, fontSize = 10 } },
    { id = "octaveUp", type = "Button", x = 112, y = 494, w = 60, h = 28, props = { label = "Oct +" }, style = { bg = 0xff1e293b, fontSize = 10 } },
    { id = "octaveLabel", type = "Label", x = 180, y = 500, w = 80, h = 16, props = { text = "C3-C5" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
    { id = "keyboardCanvas", type = "Panel", x = 44, y = 530, w = 1192, h = 50, style = { bg = 0xff0d1420, border = 0xff1f2b4d, borderWidth = 1, radius = 6 } },

    -- Status Section
    { id = "statusPanel", type = "Panel", x = 24, y = 610, w = 1232, h = 94, style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 10 } },
    { id = "statusTitle", type = "Label", x = 44, y = 624, w = 200, h = 16, props = { text = "LIVE STATUS" }, style = { colour = 0xff94a3b8, fontSize = 12 } },
    { id = "deviceValue", type = "Label", x = 44, y = 650, w = 400, h = 16, props = { text = "Input: none" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
    { id = "freqValue", type = "Label", x = 44, y = 674, w = 200, h = 16, props = { text = "Freq: 220.00 Hz" }, style = { colour = 0xff7dd3fc, fontSize = 11 } },
    { id = "ampValue", type = "Label", x = 260, y = 674, w = 200, h = 16, props = { text = "Amp: 0.000" }, style = { colour = 0xff4ade80, fontSize = 11 } },
    { id = "filterValue", type = "Label", x = 480, y = 650, w = 300, h = 16, props = { text = "Filter: SVF Lowpass / 3200 Hz / Res 0.75" }, style = { colour = 0xffc084fc, fontSize = 11 } },
    { id = "adsrValue", type = "Label", x = 480, y = 674, w = 400, h = 16, props = { text = "ADSR: A 50ms / D 200ms / S 70% / R 400ms" }, style = { colour = 0xfffda4af, fontSize = 11 } },
    { id = "fxValue", type = "Label", x = 900, y = 650, w = 300, h = 16, props = { text = "FX1: None / FX2: None" }, style = { colour = 0xff22d3ee, fontSize = 11 } },
    { id = "midiEvent", type = "Label", x = 900, y = 674, w = 180, h = 16, props = { text = "No MIDI yet" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
    { id = "savePreset", type = "Button", x = 1100, y = 624, w = 136, h = 24, props = { label = "Save State" }, style = { bg = 0xff1d4ed8, fontSize = 10 } },
    { id = "loadPreset", type = "Button", x = 1100, y = 652, w = 136, h = 24, props = { label = "Load State" }, style = { bg = 0xff1d4ed8, fontSize = 10 } },
    { id = "resetPreset", type = "Button", x = 1100, y = 680, w = 136, h = 24, props = { label = "Reset" }, style = { bg = 0xff7f1d1d, fontSize = 10 } },
  },
  components = {},
}

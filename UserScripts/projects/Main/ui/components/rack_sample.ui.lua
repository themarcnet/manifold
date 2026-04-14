return {
  id = "sampleRoot",
  type = "Panel",
  x = 0, y = 0, w = 472, h = 208,
  ports = {
    inputs = {
      { id = "in", type = "audio", y = 0.24, label = "IN" },
      { id = "voice", type = "control", y = 0.48, label = "VOICE" },
      { id = "gate", type = "control", y = 0.68, label = "GATE" },
      { id = "v_oct", type = "control", y = 0.84, label = "V/OCT" },
    },
    outputs = {
      { id = "out", type = "audio", y = 0.36, label = "OUT" },
      { id = "analysis", type = "analysis", y = 0.74, label = "AN" },
    },
  },
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  children = {
    { id = "sample_graph", type = "Panel", x = 10, y = 10, w = 226, h = 126, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },

    { id = "sample_panel", type = "Panel", x = 242, y = 10, w = 220, h = 188, style = { bg = 0xff0b1220, border = 0xff1f2937, borderWidth = 1, radius = 6 } },
    { id = "sample_source_dropdown", type = "Dropdown", x = 246, y = 18, w = 54, h = 20, props = { options = { "Input", "Live", "L1", "L2", "L3", "L4" }, selected = 2, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 10, radius = 0 } },
    { id = "sample_pitch_map_toggle", type = "Toggle", x = 306, y = 18, w = 68, h = 20, props = { offLabel = "P-Map Off", onLabel = "P-Map On", value = false }, style = { onColour = 0xffd97706, offColour = 0xff475569, fontSize = 10 } },
    { id = "sample_capture_mode_toggle", type = "Toggle", x = 380, y = 18, w = 44, h = 20, props = { offLabel = "Retro", onLabel = "Free", value = false }, style = { onColour = 0xff0ea5e9, offColour = 0xff475569, fontSize = 10 } },
    { id = "sample_capture_button", type = "Button", x = 430, y = 18, w = 28, h = 20, props = { label = "Cap" }, style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 10 } },

    { id = "sample_pitch_mode", type = "SegmentedControl", x = 246, y = 44, w = 212, h = 20, props = { segments = { "Classic", "PVoc", "HQ" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xff8b5cf6, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },

    { id = "sample_bars_box", type = "Slider", x = 252, y = 72, w = 200, h = 20, props = { min = 0.0625, max = 16.0, step = 0.0625, value = 1.0, label = "Bars", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "sample_root_box", type = "Slider", x = 252, y = 98, w = 200, h = 20, props = { min = 12, max = 96, step = 1, value = 60, label = "Root", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
    { id = "unison_knob", type = "Slider", x = 16, y = 144, w = 66, h = 20, props = { min = 1, max = 8, step = 1, value = 1, label = "Unison", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "detune_knob", type = "Slider", x = 90, y = 144, w = 66, h = 20, props = { min = 0, max = 100, step = 1, value = 0, label = "Detune", compact = true, showValue = true }, style = { colour = 0xff4ade80, bg = 0xff102317, fontSize = 9 } },
    { id = "spread_knob", type = "Slider", x = 164, y = 144, w = 66, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0, label = "Spread", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
    { id = "sample_xfade_box", type = "Slider", x = 252, y = 124, w = 200, h = 20, props = { min = 0, max = 50, step = 1, value = 10, label = "X-Fade", compact = true, showValue = true }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },
    { id = "sample_pvoc_fft", type = "Slider", x = 252, y = 150, w = 96, h = 20, props = { min = 9, max = 12, step = 1, value = 11, label = "FFT", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
    { id = "sample_pvoc_stretch", type = "Slider", x = 356, y = 150, w = 96, h = 20, props = { min = 0.25, max = 4.0, step = 0.25, value = 1.0, label = "Stretch", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },

    { id = "output_knob", type = "Slider", x = 10, y = 174, w = 226, h = 24, props = { min = 0, max = 2, step = 0.01, value = 0.8, label = "Output", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff10231d, fontSize = 9 } },
  },
}

return {
  id = "sampleRoot",
  type = "Panel",
  x = 0, y = 0, w = 560, h = 200,
  style = { bg = 0xff121a2f, border = 0xff164e63, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = 16, y = 8, w = 200, h = 14, props = { text = "SAMPLE" }, style = { colour = 0xff22d3ee, fontSize = 12 } },
    { id = "sample_graph", type = "Panel", x = 10, y = 28, w = 270, h = 164, style = { bg = 0xff0d1420, border = 0xff134e5e, borderWidth = 1, radius = 6 } },
    { id = "sample_length_label", type = "Label", x = 210, y = 10, w = 80, h = 16, props = { text = "0ms" }, style = { colour = 0xff94a3b8, fontSize = 10 } },

    { id = "sample_source_dropdown", type = "Dropdown", x = 300, y = 30, w = 72, h = 20, props = { options = { "Input", "Live", "L1", "L2", "L3", "L4" }, selected = 2, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 10, radius = 0 } },
    { id = "sample_pitch_map_toggle", type = "Toggle", x = 378, y = 30, w = 72, h = 20, props = { offLabel = "PMap Off", onLabel = "PMap On", value = false }, style = { onColour = 0xffd97706, offColour = 0xff475569, fontSize = 9 } },
    { id = "sample_capture_mode_toggle", type = "Toggle", x = 456, y = 30, w = 50, h = 20, props = { offLabel = "Retro", onLabel = "Free", value = false }, style = { onColour = 0xff0ea5e9, offColour = 0xff475569, fontSize = 9 } },
    { id = "sample_capture_button", type = "Button", x = 512, y = 30, w = 38, h = 20, props = { label = "Cap" }, style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 10 } },

    { id = "sample_pitch_mode", type = "SegmentedControl", x = 300, y = 56, w = 250, h = 20, props = { segments = { "Classic", "PVoc", "HQ" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xff8b5cf6, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },

    { id = "sample_bars_box", type = "Slider", x = 300, y = 82, w = 250, h = 20, props = { min = 0.0625, max = 16.0, step = 0.0625, value = 1.0, label = "Bars", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "sample_root_box", type = "Slider", x = 300, y = 108, w = 250, h = 20, props = { min = 12, max = 96, step = 1, value = 60, label = "Root", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
    { id = "sample_play_start_box", type = "Slider", x = 300, y = 134, w = 120, h = 20, props = { min = 0, max = 99, step = 1, value = 0, label = "Play", compact = true, showValue = true }, style = { colour = 0xffeab308, bg = 0xff2b2808, fontSize = 9 } },
    { id = "sample_loop_start_box", type = "Slider", x = 430, y = 134, w = 120, h = 20, props = { min = 0, max = 95, step = 1, value = 0, label = "Start", compact = true, showValue = true }, style = { colour = 0xff4ade80, bg = 0xff102317, fontSize = 9 } },
    { id = "sample_loop_len_box", type = "Slider", x = 300, y = 160, w = 120, h = 20, props = { min = 5, max = 100, step = 1, value = 100, label = "Length", compact = true, showValue = true }, style = { colour = 0xfff87171, bg = 0xff2a1117, fontSize = 9 } },
    { id = "sample_xfade_box", type = "Slider", x = 430, y = 160, w = 120, h = 20, props = { min = 0, max = 50, step = 1, value = 10, label = "X-Fade", compact = true, showValue = true }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },

    { id = "sample_pvoc_fft", type = "Slider", x = 300, y = 186, w = 120, h = 20, props = { min = 9, max = 12, step = 1, value = 11, label = "FFT", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
    { id = "sample_pvoc_stretch", type = "Slider", x = 430, y = 186, w = 120, h = 20, props = { min = 0.25, max = 4.0, step = 0.25, value = 1.0, label = "Stretch", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },

    { id = "sample_retrigger_toggle", type = "Toggle", x = 300, y = 212, w = 110, h = 20, props = { offLabel = "Retrig Off", onLabel = "Retrig On", value = true }, style = { onColour = 0xff0f766e, offColour = 0xff475569, fontSize = 9 } },
    { id = "output_knob", type = "Slider", x = 430, y = 212, w = 120, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.8, label = "Output", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff10231d, fontSize = 9 } },
  },
}

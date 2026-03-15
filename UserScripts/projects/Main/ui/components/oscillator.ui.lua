return {
  id = "oscRoot",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 200,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = 16, y = 8, w = 200, h = 16, props = { text = "OSCILLATOR" }, style = { colour = 0xff7dd3fc, fontSize = 12 } },
    { id = "osc_graph", type = "Panel", x = 16, y = 30, w = 248, h = 80, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },

    { id = "waveform_label", type = "Label", x = 16, y = 116, w = 60, h = 14, props = { text = "Waveform" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "waveform_dropdown", type = "Dropdown", x = 16, y = 132, w = 120, h = 24, props = { options = { "Sine", "Saw", "Square", "Triangle", "Blend" }, selected = 2, max_visible_rows = 5 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8 } },

    { id = "sample_mode_label", type = "Label", x = 148, y = 116, w = 80, h = 14, props = { text = "Mode" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "sample_mode_dropdown", type = "Dropdown", x = 148, y = 132, w = 120, h = 24, props = { options = { "Classic", "Sample Loop" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff1e293b, colour = 0xffa78bfa } },

    { id = "sample_source_label", type = "Label", x = 16, y = 160, w = 80, h = 14, props = { text = "Source" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "sample_source_dropdown", type = "Dropdown", x = 16, y = 176, w = 120, h = 24, props = { options = { "Live", "Layer 1", "Layer 2", "Layer 3", "Layer 4" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee } },

    { id = "sample_capture_button", type = "Button", x = 148, y = 176, w = 120, h = 24, props = { label = "Capture" }, style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 11 } },

    { id = "sample_bars_box", type = "NumberBox", x = 16, y = 206, w = 58, h = 26, props = { min = 0.0625, max = 16.0, step = 0.0625, value = 1.0, label = "Bars", format = "%.3f" }, style = { colour = 0xff22d3ee } },
    { id = "sample_root_box", type = "NumberBox", x = 80, y = 206, w = 58, h = 26, props = { min = 12, max = 96, step = 1, value = 60, label = "Root", format = "%d" }, style = { colour = 0xfffbbf24 } },

    { id = "range_view_dropdown", type = "Dropdown", x = 148, y = 206, w = 120, h = 22, props = { options = { "All", "Global", "Voice 1", "Voice 2", "Voice 3", "Voice 4", "Voice 5", "Voice 6", "Voice 7", "Voice 8" }, selected = 1, max_visible_rows = 10 }, style = { bg = 0xff1e293b, colour = 0xffe2e8f0, fontSize = 10 } },

    { id = "sample_start_box", type = "NumberBox", x = 16, y = 238, w = 58, h = 26, props = { min = 0, max = 95, step = 1, value = 0, label = "Start%", format = "%d" }, style = { colour = 0xffa78bfa } },
    { id = "sample_len_box", type = "NumberBox", x = 80, y = 238, w = 58, h = 26, props = { min = 5, max = 100, step = 1, value = 100, label = "Len%", format = "%d" }, style = { colour = 0xff34d399 } },

    { id = "drive_knob", type = "Knob", x = 16, y = 236, w = 56, h = 70, props = { min = 0, max = 20, step = 0.1, value = 1.8, label = "Drive" }, style = { colour = 0xfff97316 } },
    { id = "output_knob", type = "Knob", x = 78, y = 262, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.8, label = "Output" }, style = { colour = 0xff34d399 } },
    { id = "noise_knob", type = "Knob", x = 146, y = 262, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Noise" }, style = { colour = 0xff94a3b8 } },
    { id = "noise_color_knob", type = "Knob", x = 214, y = 262, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.1, label = "Color" }, style = { colour = 0xffcbd5e1 } },
  },
}

return {
  id = "fxRoot",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 200,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  -- Port definitions for signal routing visualization
  ports = {
    inputs = {
      { id = "audio_in", type = "audio", y = 0.5, label = "IN" }
    },
    outputs = {
      { id = "audio_out", type = "audio", y = 0.5, label = "OUT" }
    }
  },
  children = {
    { id = "type_dropdown", type = "Dropdown", x = 16, y = 10, w = 200, h = 24, props = { options = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener", "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap", "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ", "Limiter", "Transient" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee } },
    -- XY pad (title drawn inside)
    { id = "xy_pad", type = "Panel", x = 16, y = 40, w = 200, h = 98, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },

    { id = "xy_x_label", type = "Label", x = 16, y = 142, w = 14, h = 16, props = { text = "X" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "xy_x_dropdown", type = "Dropdown", x = 32, y = 142, w = 78, h = 20, props = { options = { "Rate" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "xy_y_label", type = "Label", x = 114, y = 142, w = 14, h = 16, props = { text = "Y" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "xy_y_dropdown", type = "Dropdown", x = 130, y = 142, w = 78, h = 20, props = { options = { "Depth" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },

    { id = "mix_knob", type = "Slider", x = 16, y = 166, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Mix", compact = true, showValue = true }, style = { colour = 0xff4ade80, bg = 0xff102317, fontSize = 9 } },
    { id = "param1", type = "Slider", x = 16, y = 190, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P1", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "param2", type = "Slider", x = 16, y = 214, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P2", compact = true, showValue = true }, style = { colour = 0xff38bdf8, bg = 0xff0b1c2e, fontSize = 9 } },
    { id = "param3", type = "Slider", x = 16, y = 238, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P3", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
    { id = "param4", type = "Slider", x = 16, y = 262, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P4", compact = true, showValue = true }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },
    { id = "param5", type = "Slider", x = 16, y = 286, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P5", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
  },
}

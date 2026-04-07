return {
  id = "fxRoot",
  type = "Panel",
  x = 0, y = 0, w = 236, h = 208,
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
    { id = "type_dropdown", type = "Dropdown", x = 10, y = 10, w = 160, h = 20, props = { options = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener", "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap", "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ", "Limiter", "Transient", "Bitcrusher", "Shimmer", "Reverse Delay", "Stutter" }, selected = 1, max_visible_rows = 8, visible = false }, style = { bg = 0xff1e293b, colour = 0xff22d3ee } },
    -- XY pad (title drawn inside)
    { id = "xy_pad", type = "Panel", x = 10, y = 10, w = 216, h = 188, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },

    { id = "xy_x_label", type = "Label", x = 10, y = 34, w = 14, h = 16, props = { text = "X", visible = false }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "xy_x_dropdown", type = "Dropdown", x = 26, y = 34, w = 78, h = 20, props = { options = { "Rate" }, selected = 1, max_visible_rows = 6, visible = false }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "xy_y_label", type = "Label", x = 108, y = 34, w = 14, h = 16, props = { text = "Y", visible = false }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "xy_y_dropdown", type = "Dropdown", x = 124, y = 34, w = 78, h = 20, props = { options = { "Depth" }, selected = 1, max_visible_rows = 6, visible = false }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },

    { id = "mix_knob", type = "Slider", x = 10, y = 58, w = 160, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Mix", compact = true, showValue = true, visible = false }, style = { colour = 0xff4ade80, bg = 0xff102317, fontSize = 9 } },
    { id = "param1", type = "Slider", x = 10, y = 82, w = 160, h = 18, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P1", compact = true, showValue = true, visible = false }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "param2", type = "Slider", x = 10, y = 104, w = 160, h = 18, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P2", compact = true, showValue = true, visible = false }, style = { colour = 0xff38bdf8, bg = 0xff0b1c2e, fontSize = 9 } },
    { id = "param3", type = "Slider", x = 10, y = 126, w = 160, h = 18, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P3", compact = true, showValue = true, visible = false }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
    { id = "param4", type = "Slider", x = 10, y = 148, w = 160, h = 18, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P4", compact = true, showValue = true, visible = false }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },
    { id = "param5", type = "Slider", x = 10, y = 170, w = 160, h = 18, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "P5", compact = true, showValue = true, visible = false }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
  },
}

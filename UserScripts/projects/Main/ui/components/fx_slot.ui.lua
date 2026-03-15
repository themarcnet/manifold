return {
  id = "fxRoot",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 200,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = 16, y = 8, w = 200, h = 16, props = { text = "FX SLOT" }, style = { colour = 0xff22d3ee, fontSize = 12 } },
    { id = "type_dropdown", type = "Dropdown", x = 16, y = 28, w = 200, h = 24, props = { options = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener", "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap", "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ", "Limiter", "Transient" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee } },
    { id = "xy_pad", type = "Panel", x = 16, y = 58, w = 200, h = 80, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },
    { id = "xy_x_dropdown", type = "Dropdown", x = 16, y = 142, w = 90, h = 20, props = { options = { "Rate" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "xy_y_dropdown", type = "Dropdown", x = 110, y = 142, w = 90, h = 20, props = { options = { "Depth" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "knob1_dropdown", type = "Dropdown", x = 16, y = 166, w = 90, h = 20, props = { options = { "Rate" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "knob2_dropdown", type = "Dropdown", x = 110, y = 166, w = 90, h = 20, props = { options = { "Depth" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff64748b, fontSize = 9 } },
    { id = "knob1", type = "Knob", x = 16, y = 190, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Rate" }, style = { colour = 0xff22d3ee } },
    { id = "knob2", type = "Knob", x = 80, y = 190, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Depth" }, style = { colour = 0xff38bdf8 } },
    { id = "mix_knob", type = "Knob", x = 144, y = 190, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Mix" }, style = { colour = 0xff4ade80 } },
  },
}

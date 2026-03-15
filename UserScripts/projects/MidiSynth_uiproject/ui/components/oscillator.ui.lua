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
    { id = "drive_knob", type = "Knob", x = 16, y = 162, w = 56, h = 70, props = { min = 0, max = 20, step = 0.1, value = 1.8, label = "Drive" }, style = { colour = 0xfff97316 } },
    { id = "output_knob", type = "Knob", x = 78, y = 162, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.8, label = "Output" }, style = { colour = 0xff34d399 } },
    { id = "noise_knob", type = "Knob", x = 146, y = 162, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Noise" }, style = { colour = 0xff94a3b8 } },
    { id = "noise_color_knob", type = "Knob", x = 214, y = 162, w = 56, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.1, label = "Color" }, style = { colour = 0xffcbd5e1 } },
  },
}

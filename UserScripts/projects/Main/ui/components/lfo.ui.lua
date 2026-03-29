return {
  type = "Panel",
  style = { bg = 0xff0f172a, border = 0xff1e3a5f, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(96), h = math.floor(14), props = { text = "LFO" }, style = { colour = 0xff38bdf8, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Sine  •  1.00 Hz" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff08111f, border = 0xff15304f, borderWidth = 1, radius = 6 } },
    { id = "shape_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(106), w = math.floor(92), h = math.floor(18), props = { options = { "Sine", "Triangle", "Saw", "Square", "S&H", "Noise" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff111827, colour = 0xff38bdf8, fontSize = 8 } },
    { id = "retrig_toggle", type = "Slider", x = math.floor(112), y = math.floor(106), w = math.floor(112), h = math.floor(18), props = { min = 0, max = 1, step = 1, value = 1, label = "Retrig", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff111827, fontSize = 8 } },
    { id = "rate_slider", type = "Slider", x = math.floor(12), y = math.floor(130), w = math.floor(212), h = math.floor(18), props = { min = 0.01, max = 20.0, step = 0.01, value = 1.0, label = "Rate Hz", compact = true, showValue = true }, style = { colour = 0xff38bdf8, bg = 0xff111827, fontSize = 8 } },
    { id = "depth_slider", type = "Slider", x = math.floor(12), y = math.floor(152), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 1.0, step = 0.01, value = 1.0, label = "Depth", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff111827, fontSize = 8 } },
    { id = "phase_slider", type = "Slider", x = math.floor(12), y = math.floor(174), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 360, step = 1, value = 0, label = "Phase °", compact = true, showValue = true }, style = { colour = 0xff60a5fa, bg = 0xff111827, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(196), w = math.floor(212), h = math.floor(12), props = { text = "Out 0.00  •  Uni 0.50" }, style = { colour = 0xffbae6fd, fontSize = 8 } },
  },
}

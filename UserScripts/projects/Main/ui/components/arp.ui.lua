return {
  type = "Panel",
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "ARPEGGIATOR" }, style = { colour = 0xfff59e0b, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Up  •  Held 0  •  Gate Off" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "mode_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(50), w = math.floor(92), h = math.floor(18), props = { options = { "Up", "Down", "Up/Down", "Random" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff1e293b, colour = 0xfff59e0b, fontSize = 8 } },
    { id = "hold_toggle", type = "Slider", x = math.floor(112), y = math.floor(50), w = math.floor(112), h = math.floor(18), props = { min = 0, max = 1, step = 1, value = 0, label = "Hold", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff1e293b, fontSize = 8 } },
    { id = "rate_slider", type = "Slider", x = math.floor(12), y = math.floor(76), w = math.floor(212), h = math.floor(18), props = { min = 0.25, max = 20.0, step = 0.25, value = 8.0, label = "Rate Hz", compact = true, showValue = true }, style = { colour = 0xfff59e0b, bg = 0xff2b1e08, fontSize = 8 } },
    { id = "octave_slider", type = "Slider", x = math.floor(12), y = math.floor(98), w = math.floor(212), h = math.floor(18), props = { min = 1, max = 4, step = 1, value = 1, label = "Octaves", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 8 } },
    { id = "gate_slider", type = "Slider", x = math.floor(12), y = math.floor(120), w = math.floor(212), h = math.floor(18), props = { min = 5, max = 100, step = 1, value = 60, label = "Gate %", compact = true, showValue = true }, style = { colour = 0xfffb923c, bg = 0xff2a1708, fontSize = 8 } },
    { id = "note_label", type = "Label", x = math.floor(12), y = math.floor(146), w = math.floor(212), h = math.floor(12), props = { text = "Output: —" }, style = { colour = 0xfffde68a, fontSize = 8 } },
  },
}

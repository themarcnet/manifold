return {
  type = "Panel",
  style = { bg = 0xff181228, border = 0xff3b2a65, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "CV MIX" }, style = { colour = 0xffc084fc, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Levels 100 / 0 / 0 / 0" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(46), props = { interceptsMouse = false }, style = { bg = 0xff140f22, border = 0xff2b1d48, borderWidth = 1, radius = 6 } },
    { id = "level_1_slider", type = "Slider", x = math.floor(12), y = math.floor(98), w = math.floor(212), h = math.floor(16), props = { min = 0, max = 1, step = 0.01, value = 1.0, label = "In 1", compact = true, showValue = true }, style = { colour = 0xffc084fc, bg = 0xff150f22, fontSize = 8 } },
    { id = "level_2_slider", type = "Slider", x = math.floor(12), y = math.floor(118), w = math.floor(212), h = math.floor(16), props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "In 2", compact = true, showValue = true }, style = { colour = 0xffc084fc, bg = 0xff150f22, fontSize = 8 } },
    { id = "level_3_slider", type = "Slider", x = math.floor(12), y = math.floor(138), w = math.floor(212), h = math.floor(16), props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "In 3", compact = true, showValue = true }, style = { colour = 0xffc084fc, bg = 0xff150f22, fontSize = 8 } },
    { id = "level_4_slider", type = "Slider", x = math.floor(12), y = math.floor(158), w = math.floor(212), h = math.floor(16), props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "In 4", compact = true, showValue = true }, style = { colour = 0xffc084fc, bg = 0xff150f22, fontSize = 8 } },
    { id = "offset_slider", type = "Slider", x = math.floor(12), y = math.floor(178), w = math.floor(212), h = math.floor(16), props = { min = -1, max = 1, step = 0.01, value = 0.0, label = "Offset", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xffa855f7, bg = 0xff150f22, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(198), w = math.floor(212), h = math.floor(12), props = { text = "Out 0.00  •  Inv 0.00" }, style = { colour = 0xffe9d5ff, fontSize = 8 } },
  },
}

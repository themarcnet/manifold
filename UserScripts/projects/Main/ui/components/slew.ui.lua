return {
  type = "Panel",
  style = { bg = 0xff0f1f17, border = 0xff1f3b2d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "SLEW" }, style = { colour = 0xff2dd4bf, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Log  •  ↑ 0 ms  ↓ 0 ms" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff0d1812, border = 0xff1c2d23, borderWidth = 1, radius = 6 } },
    { id = "shape_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(106), w = math.floor(88), h = math.floor(18), props = { options = { "Linear", "Log", "Exp" }, selected = 2, max_visible_rows = 3 }, style = { bg = 0xff112417, colour = 0xff2dd4bf, fontSize = 8 } },
    { id = "rise_slider", type = "Slider", x = math.floor(12), y = math.floor(130), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 2000, step = 1, value = 0, label = "Rise ms", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff112417, fontSize = 8 } },
    { id = "fall_slider", type = "Slider", x = math.floor(12), y = math.floor(152), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 2000, step = 1, value = 0, label = "Fall ms", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff112417, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(176), w = math.floor(212), h = math.floor(12), props = { text = "In 0.00  •  Out 0.00" }, style = { colour = 0xffbbf7d0, fontSize = 8 } },
  },
}

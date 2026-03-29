return {
  type = "Panel",
  style = { bg = 0xff1a1f1c, border = 0xff2d3b32, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "VELOCITY" }, style = { colour = 0xff4ade80, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Linear  •  Amt 100%  •  Off 0%" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff101611, border = 0xff203127, borderWidth = 1, radius = 6 } },
    { id = "curve_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(106), w = math.floor(88), h = math.floor(18), props = { options = { "Linear", "Soft", "Hard" }, selected = 1, max_visible_rows = 3 }, style = { bg = 0xff112417, colour = 0xff4ade80, fontSize = 8 } },
    { id = "amount_slider", type = "Slider", x = math.floor(12), y = math.floor(130), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 1, step = 0.01, value = 1.0, label = "Amount", compact = true, showValue = true }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "offset_slider", type = "Slider", x = math.floor(12), y = math.floor(152), w = math.floor(212), h = math.floor(18), props = { min = -1, max = 1, step = 0.01, value = 0.0, label = "Offset", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff112417, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(176), w = math.floor(212), h = math.floor(12), props = { text = "Preview: —" }, style = { colour = 0xffbbf7d0, fontSize = 8 } },
  },
}

return {
  type = "Panel",
  style = { bg = 0xff0f1f17, border = 0xff1f3b2d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "NOTE FILTER" }, style = { colour = 0xff4ade80, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Inside  •  C2 .. C7" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(50), props = { interceptsMouse = false }, style = { bg = 0xff0d1812, border = 0xff1c2d23, borderWidth = 1, radius = 6 } },
    { id = "mode_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(102), w = math.floor(84), h = math.floor(18), props = { options = { "Inside", "Outside" }, selected = 1, max_visible_rows = 2 }, style = { bg = 0xff112417, colour = 0xff22c55e, fontSize = 8 } },
    { id = "low_slider", type = "Slider", x = math.floor(12), y = math.floor(126), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 127, step = 1, value = 36, label = "Low", compact = true, showValue = true }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "high_slider", type = "Slider", x = math.floor(12), y = math.floor(148), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 127, step = 1, value = 96, label = "High", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff112417, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(172), w = math.floor(212), h = math.floor(12), props = { text = "Preview: —" }, style = { colour = 0xffbbf7d0, fontSize = 8 } },
  },
}

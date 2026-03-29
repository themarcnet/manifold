return {
  type = "Panel",
  style = { bg = 0xff221513, border = 0xff5f261d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "COMPARE" }, style = { colour = 0xfff97316, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Rising  •  Th 0.00  •  Hy 0.05" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff1f160f, border = 0xff4d2018, borderWidth = 1, radius = 6 } },
    { id = "direction_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(106), w = math.floor(88), h = math.floor(18), props = { options = { "Rising", "Falling", "Both" }, selected = 1, max_visible_rows = 3 }, style = { bg = 0xff1f160f, colour = 0xfff97316, fontSize = 8 } },
    { id = "threshold_slider", type = "Slider", x = math.floor(12), y = math.floor(130), w = math.floor(212), h = math.floor(18), props = { min = -1, max = 1, step = 0.01, value = 0, label = "Threshold", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xfff97316, bg = 0xff1f160f, fontSize = 8 } },
    { id = "hysteresis_slider", type = "Slider", x = math.floor(12), y = math.floor(152), w = math.floor(212), h = math.floor(18), props = { min = 0, max = 0.5, step = 0.01, value = 0.05, label = "Hysteresis", compact = true, showValue = true }, style = { colour = 0xfffb923c, bg = 0xff1f160f, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(176), w = math.floor(212), h = math.floor(12), props = { text = "In 0.00  •  Gate 0  •  Trig 0" }, style = { colour = 0xfffdba74, fontSize = 8 } },
  },
}

return {
  type = "Panel",
  style = { bg = 0xff0f1f17, border = 0xff1f3b2d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(120), h = math.floor(14), props = { text = "ATV / BIAS" }, style = { colour = 0xff4ade80, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "In 0.00  •  Out 0.00" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff0d1812, border = 0xff1c2d23, borderWidth = 1, radius = 6 } },
    { id = "amount_slider", type = "Slider", x = math.floor(12), y = math.floor(106), w = math.floor(212), h = math.floor(18), props = { min = -1.0, max = 1.0, step = 0.01, value = 1.0, label = "Amount", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "bias_slider", type = "Slider", x = math.floor(12), y = math.floor(128), w = math.floor(212), h = math.floor(18), props = { min = -1.0, max = 1.0, step = 0.01, value = 0.0, label = "Bias", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xff3b82f6, bg = 0xff0f1a2e, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(152), w = math.floor(212), h = math.floor(12), props = { text = "Amt +1.00  •  Bias 0.00" }, style = { colour = 0xff86efac, fontSize = 8 } },
  },
}

return {
  type = "Panel",
  style = { bg = 0xff23170f, border = 0xff5b3412, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(140), h = math.floor(14), props = { text = "SAMPLE HOLD" }, style = { colour = 0xfff59e0b, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "Sample  •  Hold 0.00" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(54), props = { interceptsMouse = false }, style = { bg = 0xff1f160f, border = 0xff4b2a10, borderWidth = 1, radius = 6 } },
    { id = "mode_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(106), w = math.floor(96), h = math.floor(18), props = { options = { "Sample", "Track", "Step" }, selected = 1, max_visible_rows = 3 }, style = { bg = 0xff1f160f, colour = 0xfff59e0b, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(132), w = math.floor(212), h = math.floor(12), props = { text = "In 0.00  •  Hold 0.00" }, style = { colour = 0xfffde68a, fontSize = 8 } },
    { id = "inv_label", type = "Label", x = math.floor(12), y = math.floor(150), w = math.floor(212), h = math.floor(12), props = { text = "Inv 0.00" }, style = { colour = 0xfffde68a, fontSize = 8 } },
  },
}

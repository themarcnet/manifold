return {
  id = "rackBlendSimpleRoot",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 200,
  style = { bg = 0xff1a130f, border = 0xff4a2414, borderWidth = 1, radius = 10 },
  ports = {
    inputs = {
      { id = "a", type = "audio", y = 0.34, label = "A" },
      { id = "b", type = "audio", y = 0.68, label = "B" },
    },
    outputs = {
      { id = "out", type = "audio", y = 0.50, label = "OUT" },
    },
  },
  children = {
    { id = "title", type = "Label", x = 12, y = 10, w = 120, h = 14, props = { text = "BLEND" }, style = { colour = 0xffff9a62, fontSize = 10 } },
    { id = "status_label", type = "Label", x = 12, y = 28, w = 200, h = 12, props = { text = "Mix  •  A/B" }, style = { colour = 0xffb9a18f, fontSize = 8 } },
    { id = "mode_dropdown", type = "Dropdown", x = 12, y = 48, w = 92, h = 20, props = { options = { "Mix", "Ring", "FM", "Sync" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff261913, colour = 0xffff9a62, fontSize = 9 } },
    { id = "io_label", type = "Label", x = 112, y = 52, w = 92, h = 12, props = { text = "A serial  /  B aux" }, style = { colour = 0xffcbb6a5, fontSize = 8 } },
    { id = "amount_slider", type = "Slider", x = 12, y = 82, w = 248, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Amount", compact = true, showValue = true }, style = { colour = 0xffff9a62, bg = 0xff261913, fontSize = 9 } },
    { id = "mix_slider", type = "Slider", x = 12, y = 108, w = 248, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Mix", compact = true, showValue = true }, style = { colour = 0xfffb7185, bg = 0xff2d1517, fontSize = 9 } },
    { id = "output_slider", type = "Slider", x = 12, y = 134, w = 248, h = 20, props = { min = 0, max = 1, step = 0.01, value = 1.0, label = "Output", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2c210d, fontSize = 9 } },
    { id = "detail_label", type = "Label", x = 12, y = 162, w = 248, h = 22, props = { text = "Crossfade, ring, FM, or sync using A with auxiliary B.", wordWrap = true }, style = { colour = 0xffcbb6a5, fontSize = 8 } },
  },
}

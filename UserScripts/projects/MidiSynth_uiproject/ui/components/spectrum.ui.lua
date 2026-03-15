-- Spectrum Analyzer UI
-- Visual frequency display

return {
  type = "Panel",
  style = {
    bg = 0xFF16213E,
    border = 0xFF0F3460,
    borderWidth = 1,
    radius = 8,
  },
  children = {
    {
      id = "title",
      type = "Label",
      x = 10, y = 8,
      w = 200, h = 20,
      text = "SPECTRUM",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    {
      id = "spectrum_canvas",
      type = "Panel",
      x = 10, y = 30,
      w = 620, h = 60,
      style = {
        bg = 0xFF0A0A1A,
      }
    },
  }
}

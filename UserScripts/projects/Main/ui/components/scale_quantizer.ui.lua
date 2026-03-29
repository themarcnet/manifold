return {
  type = "Panel",
  style = { bg = 0xff0f1f17, border = 0xff1f3b2d, borderWidth = 1, radius = 10 },
  children = {
    { id = "title", type = "Label", x = math.floor(12), y = math.floor(10), w = math.floor(140), h = math.floor(14), props = { text = "SCALE QUANTIZER" }, style = { colour = 0xff4ade80, fontSize = 11 } },
    { id = "status_label", type = "Label", x = math.floor(12), y = math.floor(28), w = math.floor(212), h = math.floor(12), props = { text = "C Major" }, style = { colour = 0xff94a3b8, fontSize = 8 } },
    { id = "preview_graph", type = "Panel", x = math.floor(12), y = math.floor(44), w = math.floor(212), h = math.floor(50), props = { interceptsMouse = false }, style = { bg = 0xff0d1812, border = 0xff1c2d23, borderWidth = 1, radius = 6 } },
    { id = "root_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(102), w = math.floor(64), h = math.floor(18), props = { options = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }, selected = 1, max_visible_rows = 8 }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "scale_dropdown", type = "Dropdown", x = math.floor(84), y = math.floor(102), w = math.floor(140), h = math.floor(18), props = { options = { "Major", "Minor", "Dorian", "Mixolydian", "Pentatonic", "Chromatic" }, selected = 1, max_visible_rows = 6 }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "direction_dropdown", type = "Dropdown", x = math.floor(12), y = math.floor(126), w = math.floor(212), h = math.floor(18), props = { options = { "Nearest", "Up", "Down" }, selected = 1, max_visible_rows = 3 }, style = { colour = 0xff22c55e, bg = 0xff112417, fontSize = 8 } },
    { id = "preview_label", type = "Label", x = math.floor(12), y = math.floor(150), w = math.floor(212), h = math.floor(12), props = { text = "Preview: — -> —" }, style = { colour = 0xffbbf7d0, fontSize = 8 } },
  },
}

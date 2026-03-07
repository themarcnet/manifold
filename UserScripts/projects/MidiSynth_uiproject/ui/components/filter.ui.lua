-- Filter Panel UI
-- Lowpass/Highpass/Bandpass filter with cutoff and resonance

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
      w = 280, h = 24,
      text = "FILTER",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    {
      id = "type_label",
      type = "Label",
      x = 10, y = 40,
      w = 60, h = 20,
      text = "Type",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "type_dropdown",
      type = "Dropdown",
      x = 80, y = 38,
      w = 120, h = 24,
      items = {"Lowpass", "Highpass", "Bandpass"},
      selected = 0,
    },
    {
      id = "cutoff_label",
      type = "Label",
      x = 10, y = 75,
      w = 80, h = 20,
      text = "Cutoff",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "cutoff_slider",
      type = "Slider",
      x = 10, y = 95,
      w = 200, h = 24,
      min = 20, max = 20000,
      value = 20000,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "cutoff_value",
      type = "Label",
      x = 220, y = 95,
      w = 70, h = 20,
      text = "20 kHz",
      style = { textColor = 0xFFAAAAAA, fontSize = 11 }
    },
    {
      id = "resonance_label",
      type = "Label",
      x = 10, y = 130,
      w = 80, h = 20,
      text = "Resonance",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "resonance_knob",
      type = "Knob",
      x = 100, y = 125,
      w = 40, h = 40,
      min = 0.1, max = 10,
      value = 0.707,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "resonance_value",
      type = "Label",
      x = 150, y = 135,
      w = 50, h = 20,
      text = "0.7",
      style = { textColor = 0xFFAAAAAA, fontSize = 11 }
    },
    {
      id = "env_label",
      type = "Label",
      x = 10, y = 170,
      w = 80, h = 20,
      text = "Env Amt",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "env_knob",
      type = "Knob",
      x = 100, y = 165,
      w = 40, h = 40,
      min = 0, max = 1,
      value = 0,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "env_value",
      type = "Label",
      x = 150, y = 175,
      w = 50, h = 20,
      text = "0%",
      style = { textColor = 0xFFAAAAAA, fontSize = 11 }
    },
  }
}

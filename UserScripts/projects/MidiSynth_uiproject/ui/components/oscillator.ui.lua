-- Oscillator Panel UI
-- Waveform selection and unison controls

return {
  type = "Panel",
  style = {
    bg = 0xFF16213E,
    border = 0xFF0F3460,
    borderWidth = 1,
    radius = 8,
  },
  children = {
    -- Title
    {
      id = "title",
      type = "Label",
      x = 10, y = 8,
      w = 280, h = 24,
      text = "OSCILLATOR",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,  -- Bold
      }
    },
    
    -- Waveform selector
    {
      id = "waveform_label",
      type = "Label",
      x = 10, y = 40,
      w = 100, h = 20,
      text = "Waveform",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "waveform_dropdown",
      type = "Dropdown",
      x = 110, y = 38,
      w = 180, h = 24,
      items = {"Sine", "Saw", "Square", "Triangle", "Noise", "Pulse", "SuperSaw"},
      selected = 0,
    },
    
    -- Polyphony control
    {
      id = "polyphony_label",
      type = "Label",
      x = 10, y = 70,
      w = 100, h = 20,
      text = "Voices",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "polyphony_slider",
      type = "Slider",
      x = 110, y = 68,
      w = 140, h = 24,
      min = 1, max = 16,
      value = 8,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "polyphony_value",
      type = "Label",
      x = 260, y = 70,
      w = 30, h = 20,
      text = "8",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, align = "center" }
    },
    
    -- Unison voices
    {
      id = "unison_label",
      type = "Label",
      x = 10, y = 100,
      w = 100, h = 20,
      text = "Unison",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "unison_slider",
      type = "Slider",
      x = 110, y = 98,
      w = 140, h = 24,
      min = 1, max = 8,
      value = 1,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "unison_value",
      type = "Label",
      x = 260, y = 100,
      w = 30, h = 20,
      text = "1",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, align = "center" }
    },
    
    -- Detune
    {
      id = "detune_label",
      type = "Label",
      x = 10, y = 130,
      w = 100, h = 20,
      text = "Detune",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "detune_knob",
      type = "Knob",
      x = 110, y = 128,
      w = 40, h = 40,
      min = 0, max = 100,
      value = 0,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "detune_value",
      type = "Label",
      x = 160, y = 138,
      w = 50, h = 20,
      text = "0 ct",
      style = { textColor = 0xFFAAAAAA, fontSize = 11 }
    },
    
    -- Glide/Portamento
    {
      id = "glide_label",
      type = "Label",
      x = 10, y = 170,
      w = 100, h = 20,
      text = "Glide",
      style = { textColor = 0xFFFFFFFF, fontSize = 12 }
    },
    {
      id = "glide_knob",
      type = "Knob",
      x = 110, y = 168,
      w = 40, h = 40,
      min = 0, max = 5000,
      value = 0,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "glide_value",
      type = "Label",
      x = 160, y = 178,
      w = 60, h = 20,
      text = "0 ms",
      style = { textColor = 0xFFAAAAAA, fontSize = 11 }
    },
  }
}

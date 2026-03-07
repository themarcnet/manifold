-- Envelope (ADSR) Panel UI
-- Attack, Decay, Sustain, Release controls with visual representation

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
      text = "ENVELOPE (ADSR)",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    
    -- ADSR Graph visualization
    {
      id = "adsr_graph",
      type = "Canvas",
      x = 10, y = 35,
      w = 280, h = 80,
      style = {
        bg = 0xFF0A0A1A,
      }
    },
    
    -- Attack control
    {
      id = "attack_label",
      type = "Label",
      x = 10, y = 125,
      w = 60, h = 20,
      text = "Attack",
      style = { textColor = 0xFFFFFFFF, fontSize = 11 }
    },
    {
      id = "attack_knob",
      type = "Knob",
      x = 15, y = 145,
      w = 36, h = 36,
      min = 1, max = 10000,  -- 1ms to 10s
      value = 10,  -- 10ms default
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "attack_value",
      type = "Label",
      x = 10, y = 185,
      w = 60, h = 16,
      text = "10 ms",
      style = { textColor = 0xFFAAAAAA, fontSize = 10, align = "center" }
    },
    
    -- Decay control
    {
      id = "decay_label",
      type = "Label",
      x = 80, y = 125,
      w = 60, h = 20,
      text = "Decay",
      style = { textColor = 0xFFFFFFFF, fontSize = 11 }
    },
    {
      id = "decay_knob",
      type = "Knob",
      x = 85, y = 145,
      w = 36, h = 36,
      min = 1, max = 10000,
      value = 100,  -- 100ms default
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "decay_value",
      type = "Label",
      x = 80, y = 185,
      w = 60, h = 16,
      text = "100 ms",
      style = { textColor = 0xFFAAAAAA, fontSize = 10, align = "center" }
    },
    
    -- Sustain control
    {
      id = "sustain_label",
      type = "Label",
      x = 150, y = 125,
      w = 60, h = 20,
      text = "Sustain",
      style = { textColor = 0xFFFFFFFF, fontSize = 11 }
    },
    {
      id = "sustain_knob",
      type = "Knob",
      x = 155, y = 145,
      w = 36, h = 36,
      min = 0, max = 100,
      value = 70,  -- 70% default
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "sustain_value",
      type = "Label",
      x = 150, y = 185,
      w = 60, h = 16,
      text = "70%",
      style = { textColor = 0xFFAAAAAA, fontSize = 10, align = "center" }
    },
    
    -- Release control
    {
      id = "release_label",
      type = "Label",
      x = 220, y = 125,
      w = 60, h = 20,
      text = "Release",
      style = { textColor = 0xFFFFFFFF, fontSize = 11 }
    },
    {
      id = "release_knob",
      type = "Knob",
      x = 225, y = 145,
      w = 36, h = 36,
      min = 1, max = 10000,
      value = 300,  -- 300ms default
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "release_value",
      type = "Label",
      x = 220, y = 185,
      w = 60, h = 16,
      text = "300 ms",
      style = { textColor = 0xFFAAAAAA, fontSize = 10, align = "center" }
    },
  }
}

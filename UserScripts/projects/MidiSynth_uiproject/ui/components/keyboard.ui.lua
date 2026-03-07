-- Virtual Keyboard UI
-- Piano keyboard for mouse/touch input with velocity sensitivity

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
      text = "KEYBOARD",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    {
      id = "octave_label",
      type = "Label",
      x = 120, y = 8,
      w = 100, h = 20,
      text = "Octave: C3",
      style = {
        fontSize = 12,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "octave_down",
      type = "Button",
      x = 220, y = 6,
      w = 30, h = 24,
      text = "◄",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "octave_up",
      type = "Button",
      x = 255, y = 6,
      w = 30, h = 24,
      text = "►",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "velocity_label",
      type = "Label",
      x = 300, y = 8,
      w = 60, h = 20,
      text = "Vel:",
      style = {
        fontSize = 12,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "velocity_slider",
      type = "Slider",
      x = 340, y = 6,
      w = 100, h = 24,
      min = 1, max = 127,
      value = 100,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    -- Keyboard canvas
    {
      id = "keyboard_canvas",
      type = "Canvas",
      x = 10, y = 35,
      w = 920, h = 75,
      style = {
        bg = 0xFF0A0A1A,
      }
    },
  }
}

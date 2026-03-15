-- Preset Management UI
-- Save/Load synth presets

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
      w = 260, h = 20,
      text = "PRESETS",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    {
      id = "preset_dropdown",
      type = "Dropdown",
      x = 10, y = 35,
      w = 260, h = 28,
      items = {"Init", "Bass", "Lead", "Pad", "Pluck", "Brass", "Strings", "FX"},
      selected = 0,
    },
    {
      id = "load_btn",
      type = "Button",
      x = 10, y = 70,
      w = 80, h = 32,
      text = "Load",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "save_btn",
      type = "Button",
      x = 100, y = 70,
      w = 80, h = 32,
      text = "Save",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "delete_btn",
      type = "Button",
      x = 190, y = 70,
      w = 80, h = 32,
      text = "Delete",
      style = {
        bg = 0xFF662222,
        textColor = 0xFFFFFFFF,
      }
    },
  }
}

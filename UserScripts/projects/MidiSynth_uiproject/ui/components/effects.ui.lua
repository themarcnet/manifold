-- Effects Panel UI
-- Chorus, Delay, Reverb controls

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
      w = 260, h = 24,
      text = "EFFECTS",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    -- Chorus Section
    {
      id = "chorus_title",
      type = "Label",
      x = 10, y = 35,
      w = 100, h = 20,
      text = "CHORUS",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, fontFlags = 1 }
    },
    {
      id = "chorus_mix_label",
      type = "Label",
      x = 10, y = 55,
      w = 40, h = 16,
      text = "Mix",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "chorus_mix_slider",
      type = "Slider",
      x = 50, y = 53,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 0,
    },
    -- Delay Section
    {
      id = "delay_title",
      type = "Label",
      x = 10, y = 90,
      w = 100, h = 20,
      text = "DELAY",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, fontFlags = 1 }
    },
    {
      id = "delay_mix_label",
      type = "Label",
      x = 10, y = 110,
      w = 40, h = 16,
      text = "Mix",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "delay_mix_slider",
      type = "Slider",
      x = 50, y = 108,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 0,
    },
    {
      id = "delay_time_label",
      type = "Label",
      x = 10, y = 135,
      w = 40, h = 16,
      text = "Time",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "delay_time_slider",
      type = "Slider",
      x = 50, y = 133,
      w = 120, h = 20,
      min = 10, max = 2000,
      value = 250,
    },
    -- Reverb Section
    {
      id = "reverb_title",
      type = "Label",
      x = 10, y = 175,
      w = 100, h = 20,
      text = "REVERB",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, fontFlags = 1 }
    },
    {
      id = "reverb_mix_label",
      type = "Label",
      x = 10, y = 195,
      w = 40, h = 16,
      text = "Mix",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "reverb_mix_slider",
      type = "Slider",
      x = 50, y = 193,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 0,
    },
    {
      id = "reverb_size_label",
      type = "Label",
      x = 10, y = 220,
      w = 40, h = 16,
      text = "Size",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "reverb_size_slider",
      type = "Slider",
      x = 50, y = 218,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 50,
    },
    {
      id = "reverb_damp_label",
      type = "Label",
      x = 10, y = 245,
      w = 40, h = 16,
      text = "Damp",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "reverb_damp_slider",
      type = "Slider",
      x = 50, y = 243,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 50,
    },
    {
      id = "reverb_width_label",
      type = "Label",
      x = 10, y = 270,
      w = 40, h = 16,
      text = "Width",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "reverb_width_slider",
      type = "Slider",
      x = 50, y = 268,
      w = 120, h = 20,
      min = 0, max = 100,
      value = 100,
    },
    {
      id = "reverb_freeze_btn",
      type = "Toggle",
      x = 180, y = 268,
      w = 50, h = 20,
      text = "Freeze",
      value = false,
    },
    -- Master Section
    {
      id = "master_title",
      type = "Label",
      x = 10, y = 310,
      w = 100, h = 20,
      text = "MASTER",
      style = { textColor = 0xFFFFFFFF, fontSize = 12, fontFlags = 1 }
    },
    {
      id = "master_vol_label",
      type = "Label",
      x = 10, y = 330,
      w = 40, h = 16,
      text = "Vol",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
    {
      id = "master_vol_slider",
      type = "VSlider",
      x = 20, y = 350,
      w = 24, h = 40,
      min = 0, max = 100,
      value = 70,
    },
    {
      id = "master_vol_value",
      type = "Label",
      x = 50, y = 365,
      w = 50, h = 16,
      text = "70%",
      style = { textColor = 0xFFAAAAAA, fontSize = 10 }
    },
  }
}

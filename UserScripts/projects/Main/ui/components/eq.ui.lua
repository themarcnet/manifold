-- 8-Band EQ Panel UI
return {
  id = "eqRoot",
  type = "Panel",
  x = 0, y = 0, w = 236, h = 208,
  style = {
    bg = 0xff121a2f,
    border = 0xff1f2b4d,
    borderWidth = 1,
    radius = 0,
  },
  -- Port definitions for signal routing visualization
  ports = {
    inputs = {
      { id = "audio_in", type = "audio", y = 0.5, label = "IN" }  -- Center-left (audio)
    }
    -- No outputs - final stage
  },
  children = {
    -- EQ graph (title drawn inside, helper text removed)
    {
      id = "eq_graph",
      type = "Panel",
      x = 10, y = 10,
      w = 216, h = 108,
      style = { bg = 0xff0a0a1a, border = 0xff1f2b4d, borderWidth = 1, radius = 0 }
    },
    {
      id = "type_label",
      type = "Label",
      x = 10, y = 126,
      w = 38, h = 18,
      props = { text = "Curve" },
      style = { colour = 0xff94a3b8, fontSize = 9 }
    },
    {
      id = "type_selector",
      type = "Dropdown",
      x = 52, y = 124,
      w = 116, h = 22,
      props = {
        options = { "Bell", "Low Shelf", "High Shelf", "Low Pass", "High Pass", "Notch" },
        selected = 1,
        max_visible_rows = 6,
      },
      style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 9 }
    },
    {
      id = "freq_value",
      type = "NumberBox",
      x = 10, y = 156,
      w = 68, h = 24,
      props = { min = 20, max = 20000, step = 1, value = 1000, label = "Freq", suffix = "Hz", format = "%d" },
      style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 9 }
    },
    {
      id = "gain_value",
      type = "NumberBox",
      x = 84, y = 156,
      w = 68, h = 24,
      props = { min = -24, max = 24, step = 0.1, value = 0.0, label = "Gain", suffix = "dB", format = "%.1f" },
      style = { bg = 0xff1e293b, colour = 0xff38bdf8, fontSize = 9 }
    },
    {
      id = "q_value",
      type = "NumberBox",
      x = 158, y = 156,
      w = 68, h = 24,
      props = { min = 0.1, max = 24.0, step = 0.05, value = 1.0, label = "Q", format = "%.2f" },
      style = { bg = 0xff1e293b, colour = 0xffa78bfa, fontSize = 9 }
    },
  },
}

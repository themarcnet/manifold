return {
  id = "filterRoot",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 200,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  -- Port definitions for signal routing visualization
  ports = {
    inputs = {
      { id = "audio_in", type = "audio", y = 0.5, label = "IN" }  -- Center-left (audio)
    },
    outputs = {
      { id = "audio_out", type = "audio", y = 0.5, label = "OUT" }  -- Center-right (audio)
    }
  },
  children = {
    -- Filter graph (title drawn inside)
    { id = "filter_graph", type = "Panel", x = 16, y = 10, w = 248, h = 118, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },
    { id = "filter_type_label", type = "Label", x = 16, y = 136, w = 60, h = 14, props = { text = "Type" }, style = { colour = 0xff94a3b8, fontSize = 10 } },
    { id = "filter_type_dropdown", type = "Dropdown", x = 16, y = 152, w = 140, h = 24, props = { options = { "SVF Lowpass", "SVF Bandpass", "SVF Highpass", "SVF Notch" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff1e293b, colour = 0xffa78bfa } },
    { id = "cutoff_knob", type = "Slider", x = 16, y = 182, w = 160, h = 20, props = { min = 80, max = 16000, step = 1, value = 3200, label = "Cutoff", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
    { id = "resonance_knob", type = "Slider", x = 16, y = 208, w = 160, h = 20, props = { min = 0.1, max = 2.0, step = 0.01, value = 0.75, label = "Reso", compact = true, showValue = true }, style = { colour = 0xffd8b4fe, bg = 0xff241a33, fontSize = 9 } },
  },
}

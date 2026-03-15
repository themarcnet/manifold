-- Envelope (ADSR) Panel UI
return {
  type = "Panel",
  style = {
    bg = 0xff121a2f,
    border = 0xff1f2b4d,
    borderWidth = 1,
    radius = 10,
  },
  children = {
    -- Title
    {
      id = "title",
      type = "Label",
      x = 16, y = 8,
      w = 248, h = 16,
      props = { text = "ADSR ENVELOPE" },
      style = { colour = 0xfffda4af, fontSize = 12 }
    },

    -- ADSR Graph visualization
    {
      id = "adsr_graph",
      type = "Panel",
      x = 16, y = 28,
      w = 248, h = 90,
      style = { bg = 0xff0a0a1a, border = 0xff1f2b4d, borderWidth = 1, radius = 4 }
    },

    -- Knobs
    {
      id = "attack_knob",
      type = "Knob",
      x = 16, y = 124,
      w = 56, h = 70,
      props = { min = 1, max = 5000, step = 1, value = 50, label = "Attack" },
      style = { colour = 0xfffda4af }
    },
    {
      id = "decay_knob",
      type = "Knob",
      x = 80, y = 124,
      w = 56, h = 70,
      props = { min = 1, max = 5000, step = 1, value = 200, label = "Decay" },
      style = { colour = 0xfffda4af }
    },
    {
      id = "sustain_knob",
      type = "Knob",
      x = 144, y = 124,
      w = 56, h = 70,
      props = { min = 0, max = 100, step = 1, value = 70, label = "Sustain" },
      style = { colour = 0xfffda4af }
    },
    {
      id = "release_knob",
      type = "Knob",
      x = 208, y = 124,
      w = 56, h = 70,
      props = { min = 1, max = 10000, step = 1, value = 400, label = "Release" },
      style = { colour = 0xfffda4af }
    },
  }
}

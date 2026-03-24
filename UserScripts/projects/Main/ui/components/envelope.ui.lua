-- Envelope (ADSR) Panel UI
return {
  type = "Panel",
  style = {
    bg = 0xff121a2f,
    border = 0xff1f2b4d,
    borderWidth = 1,
    radius = 10,
  },
  -- Port definitions for signal routing visualization
  ports = {
    outputs = {
      { id = "cv_out", type = "cv", y = 0.5, label = "ENV" }  -- Center-right
    }
  },
  children = {
    -- ADSR Graph visualization (title drawn inside graph)
    {
      id = "adsr_graph",
      type = "Panel",
      x = 16, y = 10,
      w = 248, h = 108,
      style = { bg = 0xff0a0a1a, border = 0xff1f2b4d, borderWidth = 1, radius = 4 }
    },

    -- Compact sliders
    {
      id = "attack_knob",
      type = "Slider",
      x = 16, y = 124,
      w = 120, h = 20,
      props = { min = 1, max = 5000, step = 1, value = 50, label = "Attack", compact = true, showValue = true },
      style = { colour = 0xfffda4af, bg = 0xff2b141b, fontSize = 9 }
    },
    {
      id = "decay_knob",
      type = "Slider",
      x = 144, y = 124,
      w = 120, h = 20,
      props = { min = 1, max = 5000, step = 1, value = 200, label = "Decay", compact = true, showValue = true },
      style = { colour = 0xfffda4af, bg = 0xff2b141b, fontSize = 9 }
    },
    {
      id = "sustain_knob",
      type = "Slider",
      x = 16, y = 150,
      w = 120, h = 20,
      props = { min = 0, max = 100, step = 1, value = 70, label = "Sustain", compact = true, showValue = true },
      style = { colour = 0xfffda4af, bg = 0xff2b141b, fontSize = 9 }
    },
    {
      id = "release_knob",
      type = "Slider",
      x = 144, y = 150,
      w = 120, h = 20,
      props = { min = 1, max = 10000, step = 1, value = 400, label = "Release", compact = true, showValue = true },
      style = { colour = 0xfffda4af, bg = 0xff2b141b, fontSize = 9 }
    },
    
  }
}

-- Port overlay definitions (rendered by signal router, not as widgets)
-- CV Output Port: Center-right of component
-- Position: x = component.w - 4, y = component.h / 2 - 6

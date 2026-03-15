return {
  id = "layer_strip_root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1280,
  h = 120,
  style = {
    bg = 4279969334,
    border = 4281549141,
    borderWidth = 1,
    radius = 8,
  },
  children = {
    {
      id = "label",
      type = "Label",
      x = 6,
      y = 6,
      w = 26,
      h = 24,
      props = {
        text = "L?",
      },
      style = {
        colour = 4287931320,
        fontSize = 15,
        fontStyle = "bold",
      },
    },
    {
      id = "state",
      type = "Label",
      x = 6,
      y = 38,
      w = 50,
      h = 20,
      props = {
        text = "",
      },
      style = {
        colour = 4284773515,
        fontSize = 11,
      },
    },
    {
      id = "bars",
      type = "Label",
      x = 6,
      y = 70,
      w = 50,
      h = 16,
      props = {
        text = "",
      },
      style = {
        colour = 4287931320,
        fontSize = 10,
      },
    },
    {
      id = "waveform",
      type = "WaveformView",
      x = 56,
      y = 6,
      w = 980,
      h = 108,
      props = {
        layerIndex = 0,
        mode = "layer",
      },
      style = {
        colour = 4280472558,
      },
    },
    {
      id = "vol",
      type = "Knob",
      x = 1044,
      y = 6,
      w = 60,
      h = 108,
      props = {
        label = "Vol",
        max = 2,
        min = 0,
        step = 0.01,
        value = 1.0,
      },
      style = {
        colour = 4289170426,
      },
    },
    {
      id = "speed",
      type = "Knob",
      x = 1108,
      y = 6,
      w = 60,
      h = 108,
      props = {
        label = "Speed",
        max = 4.0,
        min = -4.0,
        step = 0.01,
        value = 1.0,
      },
      style = {
        colour = 4280472558,
      },
    },
    {
      id = "mute",
      type = "Button",
      x = 1172,
      y = 6,
      w = 44,
      h = 108,
      props = {
        label = "Mute",
      },
      style = {
        bg = 4282865001,
        fontSize = 11,
      },
    },
    {
      id = "clear",
      type = "Button",
      x = 1220,
      y = 6,
      w = 28,
      h = 48,
      props = {
        label = "✕",
      },
      style = {
        bg = 4286520605,
        fontSize = 11,
      },
    },
    {
      id = "play",
      type = "Button",
      x = 1220,
      y = 60,
      w = 28,
      h = 48,
      props = {
        label = "▶",
      },
      style = {
        bg = 4280252986,
        fontSize = 13,
      },
    },
  },
  components = {},
}

return {
  id = "transport_root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1280,
  h = 48,
  style = {
    bg = 4279507492,
    radius = 8,
  },
  children = {
    {
      id = "mode",
      type = "Dropdown",
      x = 6,
      y = 6,
      w = 130,
      h = 36,
      props = {
        options = {
          "First Loop",
          "Free Mode",
          "Traditional",
        },
        selected = 1,
      },
      style = {
        bg = 4280240762,
        colour = 4286436348,
      },
    },
    {
      id = "rec",
      type = "Button",
      x = 144,
      y = 6,
      w = 80,
      h = 36,
      props = {
        label = "● REC",
      },
      style = {
        bg = 4286520605,
        fontSize = 13,
      },
    },
    {
      id = "playpause",
      type = "Button",
      x = 230,
      y = 6,
      w = 80,
      h = 36,
      props = {
        label = "▶ PLAY",
      },
      style = {
        bg = 4280252986,
        fontSize = 13,
      },
    },
    {
      id = "stop",
      type = "Button",
      x = 316,
      y = 6,
      w = 80,
      h = 36,
      props = {
        label = "⏹ STOP",
      },
      style = {
        bg = 4281811281,
        fontSize = 13,
      },
    },
    {
      id = "overdub",
      type = "Toggle",
      x = 408,
      y = 6,
      w = 110,
      h = 36,
      props = {
        label = "Overdub",
        value = false,
      },
      style = {
        offColour = 4281811281,
        onColour = 4294286859,
      },
    },
    {
      id = "clearall",
      type = "Button",
      x = 530,
      y = 6,
      w = 70,
      h = 36,
      props = {
        label = "Clear All",
      },
      style = {
        bg = 4280232247,
        fontSize = 12,
      },
    },
    {
      id = "linkIndicator",
      type = "Label",
      x = 930,
      y = 6,
      w = 50,
      h = 36,
      props = {
        text = "link",
      },
      style = {
        colour = 4283127139,
        fontSize = 11,
      },
    },
    {
      id = "tempo",
      type = "NumberBox",
      x = 988,
      y = 6,
      w = 96,
      h = 36,
      props = {
        format = "%d",
        label = "BPM",
        max = 240,
        min = 40,
        step = 1,
        value = 120,
      },
      style = {
        colour = 4281908728,
      },
    },
    {
      id = "targetBpm",
      type = "NumberBox",
      x = 1092,
      y = 6,
      w = 96,
      h = 36,
      props = {
        format = "%d",
        label = "Target",
        max = 240,
        min = 40,
        step = 1,
        value = 120,
      },
      style = {
        colour = 4280472558,
      },
    },
  },
}

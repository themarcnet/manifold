return {
  id = "root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1280,
  h = 720,
  style = {
    bg = 0xff08111f,
  },
  behavior = "ui/behaviors/main.lua",
  children = {
    {
      id = "tabs",
      type = "TabHost",
      x = 0,
      y = 0,
      w = 1280,
      h = 720,
      layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
      props = {
        activeIndex = 1,
        tabBarHeight = 34,
        tabSizing = "fill",
      },
      style = {
        bg = 0xff08111f,
        border = 0xff1f2937,
        borderWidth = 1,
        radius = 0,
        tabBarBg = 0xff020617,
        tabBg = 0xff111827,
        activeTabBg = 0xff2563eb,
        textColour = 0xffcbd5e1,
        activeTextColour = 0xffffffff,
      },
      children = {
        {
          id = "looper_tab",
          type = "TabPage",
          x = 0,
          y = 34,
          w = 1280,
          h = 686,
          props = {
            title = "Looper",
          },
          style = {
            bg = 0xff0b1220,
          },
          components = {
            {
              id = "looper_view",
              x = 0,
              y = 0,
              w = 1280,
              h = 720,
              layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
              ref = "ui/components/looper_view.ui.lua",
            },
          },
        },
        {
          id = "donut_tab",
          type = "TabPage",
          x = 0,
          y = 34,
          w = 1280,
          h = 686,
          props = {
            title = "DonutSuper",
          },
          style = {
            bg = 0xff0b1220,
          },
          components = {
            {
              id = "donut_view",
              x = 0,
              y = 0,
              w = 1280,
              h = 720,
              layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
              ref = "ui/components/donut_view.ui.lua",
            },
          },
        },
        {
          id = "midisynth_tab",
          type = "TabPage",
          x = 0,
          y = 34,
          w = 1280,
          h = 686,
          props = {
            title = "MidiSynth",
          },
          style = {
            bg = 0xff0b1220,
          },
          components = {
            {
              id = "midisynth_view",
              x = 0,
              y = 0,
              w = 1280,
              h = 720,
              layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
              ref = "ui/components/midisynth_view.ui.lua",
            },
          },
        },
        {
          id = "sandbox_tab",
          type = "TabPage",
          x = 0,
          y = 34,
          w = 1280,
          h = 686,
          props = {
            title = "FX Sandbox",
          },
          style = {
            bg = 0xff0b1220,
          },
          components = {
            {
              id = "sandbox_view",
              x = 0,
              y = 0,
              w = 1280,
              h = 720,
              layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
              behavior = "ui/behaviors/effects_sandbox.lua",
              ref = "ui/components/effects_sandbox.ui.lua",
            },
          },
        },
      },
    },
  },
}

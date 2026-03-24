-- NOTE: The rack shell accent bars/colour strips in this file are temporary debug visuals.
-- They are only here to make shell boundaries obvious while the rack-node surface is being built.
-- They are NOT the agreed final rack card visual language and should be revisited when the
-- shell styling is properly designed/refactored.

local PaginationDots = require("components.pagination_dots")

return {
  id = "midisynth_root",
  type = "Panel",
  x = 0, y = 0, w = 1280, h = 686,
  style = { bg = 0xff0b1220 },
  behavior = "ui/behaviors/midisynth.lua",
  children = {
    {
      id = "mainStack",
      type = "Panel",
      x = 0, y = 0, w = 1280, h = 686,
      style = { bg = 0x00000000 },
      props = { interceptsMouse = false },
      layout = {
        mode = "stack-y",
        padding = { 0, 0, 0, 0 },
        gap = 0,
        align = "stretch",
      },
      children = {
        {
          id = "content_rows",
          type = "Panel",
          x = 0, y = 0, w = 1280, h = 452,
          layoutChild = { order = 1, grow = 0, shrink = 0, basisH = 452, minH = 452, maxH = 452 },
          style = {
            bg = 0xff0f1726,
            border = 0xff1f2937,
            borderWidth = 1,
            radius = 0,
          },
          props = { interceptsMouse = false },
          layout = {
            mode = "stack-y",
            gap = 12,
            align = "stretch",
          },
          children = {
            (require("components/rack_container")),
            {
              id = "patchViewToggle",
              type = "Button",
              x = 1180, y = 0, w = 60, h = 24,
              layoutChild = { position = "absolute" },
              props = { label = "PATCH" },
              style = { bg = 0xff1e293b, border = 0xff38bdf8, borderWidth = 1, radius = 0, fontSize = 10 },
            },
          },
        },
        {
          id = "keyboardPanel",
          type = "Panel",
          x = 0, y = 0, w = 1248, h = 44,
          layoutChild = { order = 2, grow = 0, shrink = 0, basisH = 44, minH = 44 },
          style = { bg = 0xff11172a, border = 0xff1f2b4d, borderWidth = 1, radius = 0 },
          props = { interceptsMouse = false },
          layout = {
            mode = "stack-y",
            padding = { 4, 16, 4, 16 },
            gap = 0,
            align = "stretch",
          },
          children = {
            {
              id = "keyboardBody",
              type = "Panel",
              x = 0, y = 0, w = 1216, h = 120,
              layoutChild = { order = 1, grow = 1, shrink = 1, basisH = 120, minH = 0 },
              style = { bg = 0x00000000 },
              props = { interceptsMouse = false },
              layout = {
                mode = "stack-y",
                padding = { 0, 0, 42, 0 },
                gap = 6,
                align = "stretch",
              },
              children = {
                {
                  id = "keyboardStatusSecondary",
                  type = "Label",
                  x = 0, y = 0, w = 1216, h = 14,
                  layoutChild = { basisH = 14, shrink = 0, alignSelf = "stretch" },
                  props = { text = "" },
                  style = { colour = 0xff94a3b8, fontSize = 10 },
                },
                {
                  id = "keyboardCanvas",
                  type = "Panel",
                  x = 0, y = 0, w = 1216, h = 100,
                  layoutChild = { grow = 1, shrink = 1, basisH = 100, minH = 72 },
                  style = { bg = 0xff0d1420, radius = 6 },
                },
              },
            },
            {
              id = "utilitySplitArea",
              type = "Panel",
              x = 0, y = 0, w = 1216, h = 120,
              layoutChild = { order = 2, grow = 1, shrink = 1, basisH = 120, minH = 0 },
              style = { bg = 0xff0d1420, border = 0xff1f2937, borderWidth = 1, radius = 0 },
              props = { interceptsMouse = false },
              children = {
                {
                  id = "utilitySplitHint",
                  type = "Label",
                  x = 0, y = 0, w = 320, h = 18,
                  layout = { mode = "hybrid", left = 12, top = 10, width = 320, height = 18 },
                  props = { text = "Utility split area" },
                  style = { colour = 0xff64748b, fontSize = 11 },
                },
              },
            },
            {
              id = "keyboardHeader",
              type = "Panel",
              x = 0, y = 0, w = 1216, h = 42,
              layoutChild = { order = 3, position = "absolute", bottom = 0, left = 0, right = 0, height = 42 },
              style = { bg = 0x00000000 },
              props = { interceptsMouse = false },
              layout = {
                mode = "stack-x",
                gap = 12,
                align = "center",
              },
              children = {
                {
                  id = "octaveCluster",
                  type = "Panel",
                  x = 0, y = 0, w = 210, h = 28,
                  layoutChild = { basisW = 210, shrink = 0, alignSelf = "center" },
                  style = { bg = 0x00000000 },
                  props = { interceptsMouse = false },
                  layout = {
                    mode = "stack-x",
                    gap = 6,
                    align = "center",
                  },
                  children = {
                    { id = "octaveDown", type = "Button", x = 0, y = 0, w = 56, h = 28, layoutChild = { basisW = 56, shrink = 0 }, props = { label = "Oct -" }, style = { bg = 0xff1e293b, fontSize = 10 } },
                    { id = "octaveUp", type = "Button", x = 0, y = 0, w = 56, h = 28, layoutChild = { basisW = 56, shrink = 0 }, props = { label = "Oct +" }, style = { bg = 0xff1e293b, fontSize = 10 } },
                    { id = "octaveLabel", type = "Label", x = 0, y = 0, w = 72, h = 16, layoutChild = { basisW = 72, shrink = 0, alignSelf = "center" }, props = { text = "C3-C5" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
                  },
                },
                {
                  id = "statusCluster",
                  type = "Panel",
                  x = 0, y = 0, w = 420, h = 28,
                  layoutChild = { grow = 1, shrink = 1, basisW = 420, minW = 260, alignSelf = "center" },
                  style = { bg = 0x00000000 },
                  props = { interceptsMouse = false },
                  layout = {
                    mode = "stack-x",
                    gap = 4,
                    align = "center",
                  },
                  children = {
                    { id = "keyboardStatusPrimary", type = "Label", x = 0, y = 0, w = 220, h = 16, layoutChild = { grow = 1, shrink = 1, basisW = 220, minW = 180, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
                    { id = "voiceNote1", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xff4ade80, fontSize = 12 } },
                    { id = "voiceNote2", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xff38bdf8, fontSize = 12 } },
                    { id = "voiceNote3", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xfffbbf24, fontSize = 12 } },
                    { id = "voiceNote4", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xfff87171, fontSize = 12 } },
                    { id = "voiceNote5", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xffa78bfa, fontSize = 12 } },
                    { id = "voiceNote6", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xff2dd4bf, fontSize = 12 } },
                    { id = "voiceNote7", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xfffb923c, fontSize = 12 } },
                    { id = "voiceNote8", type = "Label", x = 0, y = 0, w = 36, h = 18, layoutChild = { basisW = 36, shrink = 0, alignSelf = "center" }, props = { text = "" }, style = { colour = 0xfff472b6, fontSize = 12 } },
                  },
                },
                {
                  id = "midiCluster",
                  type = "Panel",
                  x = 0, y = 0, w = 372, h = 28,
                  layoutChild = { basisW = 372, shrink = 0, alignSelf = "center" },
                  style = { bg = 0x00000000 },
                  props = { interceptsMouse = false },
                  layout = {
                    mode = "stack-x",
                    gap = 8,
                    align = "center",
                  },
                  children = {
                    { id = "midiInputDropdown", type = "Dropdown", x = 0, y = 0, w = 180, h = 28, layoutChild = { grow = 1, shrink = 1, basisW = 180, minW = 140 }, props = { options = { "None (Disabled)" }, selected = 1, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8 } },
                    { id = "refreshMidi", type = "Button", x = 0, y = 0, w = 64, h = 28, layoutChild = { basisW = 64, shrink = 0 }, props = { label = "Refresh" }, style = { bg = 0xff1d4ed8, fontSize = 10 } },
                    { id = "panic", type = "Button", x = 0, y = 0, w = 64, h = 28, layoutChild = { basisW = 64, shrink = 0 }, props = { label = "Panic" }, style = { bg = 0xff7f1d1d, fontSize = 11 } },
                    { id = "keyboardCollapse", type = "Button", x = 0, y = 0, w = 28, h = 28, layoutChild = { basisW = 28, shrink = 0 }, props = { label = "▼" }, style = { bg = 0xff1e293b, fontSize = 12 } },
                  },
                },
              },
            },
            PaginationDots({
              id = "dockModeDots",
              dotIds = { "dockModeDotFull", "dockModeDotCompactSplit", "dockModeDotCompactCollapsed" },
              count = 3,
              orientation = "y",
              gap = 5,
              layoutChild = { position = "absolute" },
            }),
          },
        },
      },
      components = {},
    },
  },
}

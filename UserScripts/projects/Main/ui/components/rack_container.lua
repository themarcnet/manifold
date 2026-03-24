local RackNodeShell = require("components.rack_node_shell")
local PaginationDots = require("components.pagination_dots")

local function railSocket(id, x, y, accent, side)
  local bezel = accent or 0xff38bdf8
  local glow = side == "left" and 0x2038bdf8 or 0x20fb7185
  return {
    id = id,
    type = "Panel",
    x = x, y = y, w = 14, h = 14,
    style = {
      bg = 0xff111827,
      border = bezel,
      borderWidth = 2,
      radius = 7,
    },
    props = { interceptsMouse = true },
    children = {
      {
        id = id .. "_glow",
        type = "Panel",
        x = 1, y = 1, w = 12, h = 12,
        style = { bg = glow, radius = 6 },
        props = { interceptsMouse = false },
      },
      {
        id = id .. "_hole",
        type = "Panel",
        x = 3, y = 3, w = 8, h = 8,
        style = {
          bg = 0xff020617,
          border = 0x80ffffff,
          borderWidth = 1,
          radius = 4,
        },
        props = { interceptsMouse = false },
      },
    },
  }
end

return {
  id = "rackContainer",
  type = "Panel",
  x = 0, y = 0, w = 1248, h = 452,
  style = {
    bg = 0xff0f1726,
    border = 0xff1f2937,
    borderWidth = 1,
    radius = 0,
  },
  props = { interceptsMouse = false },
  children = {
    -- Keep dots in the same sidebar area, just tucked up near the right outputs.
    PaginationDots({
      id = "rackPaginationDots",
      dotIds = { "rackDot1", "rackDot2", "rackDot3" },
      count = 3,
      orientation = "y",
      gap = 6,
      x = 1235, y = 405,
      w = 10, h = 60,
    }),
    -- Rack edge terminals: receives on the left, sends on the right.
    -- No top-left receive socket per request.
    railSocket("rightRailSend1", 1232, 128, 0xfffb7185, "right"),
    railSocket("rightRailSend2", 1232, 348, 0xfffb7185, "right"),
    railSocket("rightRailSend3", 1232, 568, 0xfffb7185, "right"),
    railSocket("leftRailRecv2", 6, 348, 0xff38bdf8, "left"),
    railSocket("leftRailRecv3", 6, 568, 0xff38bdf8, "left"),
    {
      id = "rackRow1",
      type = "Panel",
      x = 35, y = 25, w = 1213, h = 220,
      style = { bg = 0x12000000, border = 0x221f2b4d, borderWidth = 1, radius = 0 },
      props = { interceptsMouse = false },
    },
    {
      id = "rackRow2",
      type = "Panel",
      x = 35, y = 245, w = 1213, h = 220,
      style = { bg = 0x12000000, border = 0x221f2b4d, borderWidth = 1, radius = 0 },
      props = { interceptsMouse = false },
    },
    {
      id = "rackRow3",
      type = "Panel",
      x = 35, y = 465, w = 1213, h = 220,
      style = { bg = 0x12000000, border = 0x221f2b4d, borderWidth = 1, radius = 0 },
      props = { interceptsMouse = false },
    },
    RackNodeShell({
      id = "adsrShell",
      layout = false,
      x = 0, y = 25,
      w = 236, h = 220,
      sizeKey = "1x1",
      accentColor = 0xfffda4af,
      nodeName = "ADSR",
      componentRef = "ui/components/envelope.ui.lua",
      componentId = "envelopeComponent",
      componentBehavior = "ui/behaviors/envelope.lua",
      componentOverrides = {
        envelopeComponent = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "oscillatorShell",
      layout = false,
      x = 236, y = 25,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xff7dd3fc,
      nodeName = "OSC",
      componentRef = "ui/components/oscillator.ui.lua",
      componentId = "oscillatorComponent",
      componentBehavior = "ui/behaviors/oscillator.lua",
      componentOverrides = {
        oscillatorComponent = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "filterShell",
      layout = false,
      x = 708, y = 25,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xffa78bfa,
      nodeName = "FILTER",
      componentRef = "ui/components/filter.ui.lua",
      componentId = "filterComponent",
      componentBehavior = "ui/behaviors/filter.lua",
      componentOverrides = {
        filterComponent = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "fx1Shell",
      layout = false,
      x = 0, y = 245,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xff22d3ee,
      nodeName = "FX1",
      componentRef = "ui/components/fx_slot.ui.lua",
      componentId = "fx1Component",
      componentBehavior = "ui/behaviors/fx_slot.lua",
      componentOverrides = {
        fx1Component = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "fx2Shell",
      layout = false,
      x = 472, y = 245,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xff38bdf8,
      nodeName = "FX2",
      componentRef = "ui/components/fx_slot.ui.lua",
      componentId = "fx2Component",
      componentBehavior = "ui/behaviors/fx_slot.lua",
      componentOverrides = {
        fx2Component = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "eqShell",
      layout = false,
      x = 944, y = 245,
      w = 236, h = 220,
      sizeKey = "1x1",
      accentColor = 0xff34d399,
      nodeName = "EQ",
      componentRef = "ui/components/eq.ui.lua",
      componentId = "eqComponent",
      componentBehavior = "ui/behaviors/eq.lua",
      componentOverrides = {
        eqComponent = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
          props = { interceptsMouse = false },
        },
      },
    }),
    RackNodeShell({
      id = "placeholder1Shell",
      layout = false,
      x = 30, y = 465,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xff64748b,
      nodeName = "SLOT1",
      componentRef = "ui/components/placeholder.ui.lua",
      componentId = "placeholder1Content",
    }),
    RackNodeShell({
      id = "placeholder2Shell",
      layout = false,
      x = 514, y = 465,
      w = 472, h = 220,
      sizeKey = "1x2",
      accentColor = 0xff64748b,
      nodeName = "SLOT2",
      componentRef = "ui/components/placeholder.ui.lua",
      componentId = "placeholder2Content",
    }),
    RackNodeShell({
      id = "placeholder3Shell",
      layout = false,
      x = 997, y = 440,
      w = 236, h = 220,
      sizeKey = "1x1",
      accentColor = 0xff64748b,
      nodeName = "SLOT3",
      componentRef = "ui/components/placeholder_knob.ui.lua",
      componentId = "placeholderKnobContent",
    }),
    {
      id = "wireOverlay",
      type = "Panel",
      x = 0, y = 0, w = 1248, h = 684,
      style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
      props = { interceptsMouse = false },
    },
  },
}

-- NOTE: The accent bar in this shell is temporary debug chrome.
-- It exists only to make rack-node boundaries obvious while the rack surface is
-- being refactored. It is not the agreed final rack card styling.

return {
  id = "rackNodeShell",
  type = "Panel",
  x = 0, y = 0, w = 280, h = 180,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 0 },
  props = { interceptsMouse = false },
  children = {
    {
      id = "accent",
      type = "Panel",
      x = 0, y = 0, w = 280, h = 3,
      layout = { mode = "hybrid", left = 0, top = 0, right = 0, height = 3 },
      style = { bg = 0xff7dd3fc, radius = 0 },
      props = { interceptsMouse = false },
    },
    {
      id = "sizeBadge",
      type = "Label",
      x = 0, y = 0, w = 34, h = 14,
      layout = { mode = "hybrid", right = 10, top = 8, width = 34, height = 14 },
      props = { text = "1x1" },
      style = { bg = 0x66111827, colour = 0xfff8fafc, fontSize = 9, radius = 0 },
    },
  },
  components = {
    {
      id = "contentComponent",
      x = 0, y = 0, w = 280, h = 180,
      layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
      behavior = "ui/behaviors/envelope.lua",
      ref = "ui/components/envelope.ui.lua",
      overrides = {
        contentComponent = {
          style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
        },
      },
    },
  },
}

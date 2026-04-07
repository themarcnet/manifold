-- Generic rack node shell component
-- Provides a reusable container for rack nodes with header, accent strip, and size badge
-- NOTE: Accent color strip is temporary debug visual per workplan

return function(props)
  local sizeKey = props.sizeKey or "1x1"
  local accentColor = props.accentColor or 0xff64748b
  local componentRef = props.componentRef
  local componentId = props.componentId or "content"
  local componentBehavior = props.componentBehavior
  local componentOverrides = props.componentOverrides or {}
  local headerH = tonumber(props.headerH) or 12

  -- Parse size key for layout hints (e.g., "1x1", "1x2", "2x2")
  local rows, cols = sizeKey:match("(%d+)x(%d+)")
  rows = tonumber(rows) or 1
  cols = tonumber(cols) or 1

  -- Base grow factor on column count (wider nodes grow more)
  local growFactor = cols

  local shellLayout = nil
  if props.layout ~= false then
    shellLayout = type(props.layout) == "table" and props.layout or { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 }
  end

  local w = props.w or (cols * 236)
  local h = props.h or (rows * 220)
  local contentH = h - headerH

  -- Build the shell structure
  local shell = {
    id = props.id or "nodeShell",
    type = "Panel",
    x = props.x or 0, y = props.y or 0,
    w = w, h = h,
    layoutChild = {
      order = props.order or 1,
      grow = props.grow or growFactor,
      shrink = props.shrink or 1,
      basisW = props.basisW or w,
      minW = props.minW or (cols * 180),
    },
    style = {
      bg = 0xff121a2f,
      border = 0xff1f2b4d,
      borderWidth = 1,
      radius = 0,
    },
    props = { interceptsMouse = false },
    layout = shellLayout,
    children = {
      -- Size badge (hidden by default, only for debugging)
      {
        id = "sizeBadge",
        type = "Label",
        x = 0, y = 0,
        w = 34, h = 14,
        layout = { mode = "hybrid", right = 10, top = 8, width = 34, height = 14 },
        props = { text = sizeKey },
        style = { bg = 0x00000000, colour = 0x00000000, fontSize = 9, radius = 0 },
      },
    },
    components = {},
  }

  -- Add the content component if specified
  if componentRef then
    shell.components[1] = {
      id = componentId,
      x = 0, y = headerH,
      w = w,
      h = contentH,
      layout = { mode = "hybrid", left = 0, top = headerH, right = 0, bottom = 0 },
      behavior = componentBehavior,
      ref = componentRef,
      props = type(props.componentProps) == "table" and props.componentProps or nil,
      overrides = componentOverrides,
    }
  end

  -- Node name label in header (left side, high contrast)
  local nodeName = props.nodeName or componentId:gsub("Component", ""):gsub("Content", "")
  table.insert(shell.children, {
    id = "nodeNameLabel",
    type = "Label",
    x = 30, y = 0,
    w = math.max(40, w - 60), h = headerH,
    layout = { mode = "hybrid", left = 30, top = 0, width = math.max(40, w - 60), height = headerH },
    props = { text = nodeName },
    style = { 
      colour = 0xffffffff,  -- white for max contrast
      fontSize = 9,
      bg = 0x00000000,     -- transparent
    },
  })

  -- Delete button (left side of header)
  table.insert(shell.children, {
    id = "deleteButton",
    type = "Button",
    x = 0, y = 0,
    w = 24, h = headerH,
    layout = { mode = "hybrid", left = 0, top = 0, width = 24, height = headerH },
    style = { bg = 0xff991b1b, hoverBg = 0xffb91c1c, radius = 0 },
    props = { text = "", interceptsMouse = true },
  })

  -- Resize toggle button (right side of header)
  table.insert(shell.children, {
    id = "resizeToggle",
    type = "Button",
    x = w - 24, y = 0,
    w = 24, h = headerH,
    layout = { mode = "hybrid", right = 0, top = 0, width = 24, height = headerH },
    style = { bg = 0x20ffffff, hoverBg = 0x40ffffff, radius = 0 },
    props = { text = "", interceptsMouse = true },
  })

  -- Add accent strip as last child (on top) with mouse intercept
  table.insert(shell.children, {
    id = "accent",
    type = "Panel",
    x = 0, y = 0,
    w = w, h = headerH,
    layout = { mode = "hybrid", left = 24, top = 0, right = 24, height = headerH },
    style = { bg = accentColor, radius = 0 },
    props = { interceptsMouse = true },
  })

  -- Patchbay overlay panel - fills the content area, only visible in patch view
  -- Renders directly on shell surface - NO background, NO border, NO nesting
  -- The shell's existing border and bg define the node edge
  table.insert(shell.children, {
    id = "patchbayPanel",
    type = "Panel",
    x = 0, y = headerH,
    w = w, h = contentH,
    layout = { mode = "hybrid", left = 0, top = headerH, right = 0, bottom = 0 },
    style = { bg = 0x00000000 },  -- Transparent - uses shell bg
    props = { interceptsMouse = true, visible = false },
    children = {},
  })

  return shell
end

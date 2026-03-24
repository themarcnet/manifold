local M = {}

local function round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

local function lowerString(v)
  return string.lower(tostring(v or ""))
end

local function getGlobalPrefix(ctx)
  local root = ctx and ctx.root or nil
  local node = root and root.node or nil
  local src = node and node.getUserData and node:getUserData("_structuredSource") or nil
  return type(src) == "table" and type(src.globalId) == "string" and src.globalId or ""
end

local function getParentPrefix(globalPrefix)
  if type(globalPrefix) ~= "string" or globalPrefix == "" then
    return ""
  end
  return globalPrefix:match("^(.*)%.[^.]+$") or ""
end

local function findSiblingWidget(ctx, suffix)
  local all = ctx and ctx.allWidgets or nil
  local parentPrefix = getParentPrefix(getGlobalPrefix(ctx))
  if type(all) ~= "table" or type(suffix) ~= "string" or suffix == "" or parentPrefix == "" then
    return nil
  end

  local exact = all[parentPrefix .. suffix]
  if exact ~= nil then
    return exact
  end

  for key, widget in pairs(all) do
    if type(key) == "string"
      and key:sub(1, #parentPrefix) == parentPrefix
      and key:sub(-#suffix) == suffix then
      return widget
    end
  end

  return nil
end

local function getLocalBounds(widget)
  local node = widget and widget.node or nil
  if not (node and node.getBounds) then
    return nil
  end
  local x, y, w, h = node:getBounds()
  return round(x), round(y), round(w), round(h)
end

local function getRelativeBounds(ctx, widget)
  local x, y, w, h = getLocalBounds(widget)
  if not x then
    return nil
  end

  local scopePrefix = getParentPrefix(getGlobalPrefix(ctx))
  if scopePrefix == "" then
    return x, y, w, h
  end

  local record = widget and widget._structuredRecord or nil
  if type(record) ~= "table" then
    return x, y, w, h
  end

  local current = record.parent
  while current do
    if current.globalId == scopePrefix then
      break
    end

    local parentWidget = current.widget
    local px, py = getLocalBounds(parentWidget)
    if px then
      x = x + px
      y = y + py
    end
    current = current.parent
  end

  return x, y, w, h
end

local function addPort(display, x, y, glow, colour)
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = round(x - 5), y = round(y - 5),
    w = 10, h = 10,
    radius = 5,
    color = glow,
  }
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = round(x - 3), y = round(y - 3),
    w = 6, h = 6,
    radius = 3,
    color = colour,
  }
end

local function addLine(display, x1, y1, x2, y2, shadow, glow, colour, thicknessGlow, thicknessMain)
  display[#display + 1] = {
    cmd = "drawLine",
    x1 = round(x1), y1 = round(y1),
    x2 = round(x2), y2 = round(y2),
    thickness = thicknessGlow + 2,
    color = shadow,
  }
  display[#display + 1] = {
    cmd = "drawLine",
    x1 = round(x1), y1 = round(y1),
    x2 = round(x2), y2 = round(y2),
    thickness = thicknessGlow,
    color = glow,
  }
  display[#display + 1] = {
    cmd = "drawLine",
    x1 = round(x1), y1 = round(y1),
    x2 = round(x2), y2 = round(y2),
    thickness = thicknessMain,
    color = colour,
  }
end

local function addWifiArcs(display, cx, cy, side, glow, colour)
  local radii = { 10, 16, 22 }
  local startAngle = side == "left" and (math.pi * 0.60) or (-math.pi * 0.60)
  local endAngle = side == "left" and (math.pi * 1.40) or (math.pi * 0.60)
  local segments = 10

  for _, radius in ipairs(radii) do
    local prevX = nil
    local prevY = nil
    for i = 0, segments do
      local t = i / segments
      local a = startAngle + (endAngle - startAngle) * t
      local x = cx + math.cos(a) * radius
      local y = cy + math.sin(a) * radius
      if prevX ~= nil then
        addLine(display, prevX, prevY, x, y, 0x00000000, glow, colour, 2, 1)
      end
      prevX = x
      prevY = y
    end
  end
end

local function addRecessedPort(display, socketX, socketY, dotX, dotY, side, shadow, glow, colour, borderColour)
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = round(socketX - 6), y = round(socketY - 6),
    w = 12, h = 12,
    radius = 6,
    color = 0xff0b1220,
  }
  display[#display + 1] = {
    cmd = "drawRoundedRect",
    x = round(socketX - 6), y = round(socketY - 6),
    w = 12, h = 12,
    radius = 6,
    thickness = 1,
    color = borderColour,
  }

  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = round(socketX - 5), y = round(socketY - 5),
    w = 10, h = 10,
    radius = 5,
    color = glow,
  }
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = round(socketX - 3), y = round(socketY - 3),
    w = 6, h = 6,
    radius = 3,
    color = colour,
  }

  local arcCenterX = side == "right" and (socketX + 2) or (socketX - 2)
  addWifiArcs(display, arcCenterX, socketY, side, glow, colour)
end

local function buildLineConnector(display, props, fx, fy, fw, fh, tx, ty, tw, th, shadow, glow, colour, thicknessGlow, thicknessMain)
  local fromYNorm = tonumber(props.fromY) or 0.5
  local toYNorm = tonumber(props.toY) or 0.5
  local startX = fx + fw - 4
  local startY = fy + fh * fromYNorm
  local endX = tx + 4
  local endY = ty + th * toYNorm
  local lineY = round((startY + endY) * 0.5)
  startY = lineY
  endY = lineY

  addLine(display, startX, startY, endX, endY, shadow, glow, colour, thicknessGlow, thicknessMain)
  addPort(display, startX, startY, glow, colour)
  addPort(display, endX, endY, glow, colour)

  if lowerString(props.showLabel or "") == "true" then
    display[#display + 1] = {
      cmd = "drawText",
      x = round(math.min(startX, endX) + 8), y = round(lineY - 12),
      w = 64, h = 12,
      text = tostring(props.label or ""),
      color = colour,
      fontSize = 10.0,
      align = "left",
      valign = "middle",
    }
  end
end

local function buildRelayConnector(display, props, fx, fy, fw, fh, tx, ty, tw, th, shadow, glow, colour, _thicknessGlow, _thicknessMain)
  local senderSocketX = fx + fw - 8
  local senderSocketY = fy + fh * (tonumber(props.fromY) or 0.5)
  local receiverSocketX = tx + 8
  local receiverSocketY = ty + th * (tonumber(props.toY) or 0.5)

  local senderStem = tonumber(props.senderStem) or 14
  local receiverStem = tonumber(props.receiverStem) or 14
  local borderColour = tonumber(props.socketBorderColour) or 0xff1f2b4d

  addRecessedPort(display, senderSocketX, senderSocketY, senderSocketX - senderStem, senderSocketY, "right", shadow, glow, colour, borderColour)
  addRecessedPort(display, receiverSocketX, receiverSocketY, receiverSocketX + receiverStem, receiverSocketY, "left", shadow, glow, colour, borderColour)
end

local function buildConnectorDisplay(ctx, w, h)
  local display = {}
  local props = ctx.instanceProps or {}
  local fromWidget = findSiblingWidget(ctx, tostring(props.fromSuffix or ".envelopeComponent"))
  local toWidget = findSiblingWidget(ctx, tostring(props.toSuffix or ".oscillatorComponent"))
  local fx, fy, fw, fh = getRelativeBounds(ctx, fromWidget)
  local tx, ty, tw, th = getRelativeBounds(ctx, toWidget)
  if not (fx and tx) then
    return display
  end

  local glow = tonumber(props.glowColour) or 0x4422d3ee
  local colour = tonumber(props.colour) or 0xff22d3ee
  local shadow = tonumber(props.shadowColour) or 0x220891b2
  local thicknessGlow = tonumber(props.glowThickness) or 6
  local thicknessMain = tonumber(props.thickness) or 2
  local style = lowerString(props.style or props.mode or "line")

  if style == "relay" or style == "sender-receiver" or style == "wireless" then
    buildRelayConnector(display, props, fx, fy, fw, fh, tx, ty, tw, th, shadow, glow, colour, thicknessGlow, thicknessMain)
  else
    buildLineConnector(display, props, fx, fy, fw, fh, tx, ty, tw, th, shadow, glow, colour, thicknessGlow, thicknessMain)
  end

  return display
end

local function refresh(ctx)
  local root = ctx.root
  if not (root and root.node and root.node.setDisplayList and root.node.getWidth and root.node.getHeight) then
    return
  end
  local w = math.max(1, round(root.node:getWidth()))
  local h = math.max(1, round(root.node:getHeight()))
  root.node:setDisplayList(buildConnectorDisplay(ctx, w, h))
  if root.node.repaint then
    root.node:repaint()
  end
end

function M.init(ctx)
  if ctx.root and ctx.root.node and ctx.root.node.setInterceptsMouse then
    ctx.root.node:setInterceptsMouse(false, false)
  end
  refresh(ctx)
end

function M.resized(ctx, _w, _h)
  refresh(ctx)
end

function M.update(ctx)
  refresh(ctx)
end

return M

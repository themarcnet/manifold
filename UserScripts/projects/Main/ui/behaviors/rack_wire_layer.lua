-- Rack Wire Layer
-- Renders patch-view wires from the actual instantiated patchbay port widgets.
-- Interaction lives on the real port widgets; this overlay only draws wires
-- and drag previews.

local M = {}

local COLORS = {
  audio = {
    core = 0xb8fb7185,
    inner = 0x88ff8fa3,
    glow = 0x20fb7185,
    shadow = 0x0c000000,
    tip = 0xe0ffc4cf,
  },
  control = {
    core = 0xb838bdf8,
    inner = 0x887dd3fc,
    glow = 0x2038bdf8,
    shadow = 0x0c000000,
    tip = 0xe0d0f0ff,
  },
  midi = {
    core = 0xb8c084fc,
    inner = 0x88d8b4fe,
    glow = 0x20c084fc,
    shadow = 0x0c000000,
    tip = 0xe0f0d9ff,
  },
  bus = {
    core = 0xb8fbbf24,
    inner = 0x88fde68a,
    glow = 0x20fbbf24,
    shadow = 0x0c000000,
    tip = 0xe0fff3c4,
  },
}

local function round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

local function endsWith(text, suffix)
  if type(text) ~= "string" or type(suffix) ~= "string" then
    return false
  end
  if suffix == "" then
    return true
  end
  return text:sub(-#suffix) == suffix
end

local function findScopedWidget(allWidgets, rootId, suffix)
  if type(allWidgets) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end

  local exact = nil
  if type(rootId) == "string" and rootId ~= "" then
    exact = allWidgets[rootId .. suffix]
  end
  if exact ~= nil then
    return exact
  end

  local bestKey = nil
  local bestWidget = nil
  for key, widget in pairs(allWidgets) do
    if type(key) == "string" and endsWith(key, suffix) then
      local rootMatches = type(rootId) ~= "string" or rootId == "" or key:sub(1, #rootId) == rootId
      if rootMatches then
        if bestKey == nil or #key < #bestKey then
          bestKey = key
          bestWidget = widget
        end
      end
    end
  end
  return bestWidget
end

local function getLocalBounds(widget)
  local node = widget and widget.node or nil
  if not (node and node.getBounds) then
    return nil
  end
  local x, y, w, h = node:getBounds()
  return round(x), round(y), round(w), round(h)
end

local function getRelativeBounds(widget, ancestorGlobalId)
  local x, y, w, h = getLocalBounds(widget)
  if not x then
    return nil
  end

  local record = widget and widget._structuredRecord or nil
  if type(record) ~= "table" then
    return x, y, w, h
  end

  local current = record.parent
  while current do
    if current.globalId == ancestorGlobalId then
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

local function getOverlay(ctx)
  return findScopedWidget(ctx and ctx.allWidgets or {}, ctx and ctx._globalPrefix or "root", ".rackContainer.wireOverlay")
end

local function getOverlayAncestorGlobalId(overlay)
  local record = overlay and overlay._structuredRecord or nil
  local parent = record and record.parent or nil
  return parent and parent.globalId or nil
end

local function shallowCopyPortRef(portRef)
  if type(portRef) ~= "table" then
    return nil
  end
  return {
    key = portRef.key,
    nodeId = portRef.nodeId,
    shellId = portRef.shellId,
    portId = portRef.portId,
    direction = portRef.direction,
    portType = portRef.portType,
    label = portRef.label,
    group = portRef.group,
    page = portRef.page,
    side = portRef.side,
    row = portRef.row,
  }
end

local function connectionId(fromRef, toRef)
  return string.format("wire_%s_%s__%s_%s", tostring(fromRef.nodeId), tostring(fromRef.portId), tostring(toRef.nodeId), tostring(toRef.portId))
end

local function portPalette(portType)
  return COLORS[portType or ""] or COLORS.control
end

local function connectionPalette(connection)
  local kind = connection and connection.kind or nil
  if kind == "audio" then
    return COLORS.audio
  elseif kind == "midi" then
    return COLORS.midi
  elseif kind == "bus" then
    return COLORS.bus
  end
  return COLORS.control
end

local function scaleAlpha(colour, factor)
  local value = math.floor(tonumber(colour) or 0)
  local alpha = math.floor(value / 0x1000000)
  local rgb = value % 0x1000000
  local scaled = math.max(0, math.min(255, math.floor(alpha * (tonumber(factor) or 1) + 0.5)))
  return scaled * 0x1000000 + rgb
end

local function scalePaletteAlpha(palette, factor, tipFactor)
  return {
    core = scaleAlpha(palette.core, factor),
    inner = scaleAlpha(palette.inner, factor),
    glow = scaleAlpha(palette.glow, factor),
    shadow = scaleAlpha(palette.shadow, factor),
    tip = scaleAlpha(palette.tip, tipFactor or factor),
  }
end

local function getWireVisualStyle(ctx, active)
  local mode = ctx and ctx._wireVisualMode or "soft"
  if mode == "solid" then
    return {
      alpha = 1.0,
      tipAlpha = 1.0,
      thicknessScale = 1.0,
    }
  end

  if active then
    return {
      alpha = 0.82,
      tipAlpha = 0.9,
      thicknessScale = 0.95,
    }
  end

  return {
    alpha = 0.46,
    tipAlpha = 0.58,
    thicknessScale = 0.82,
  }
end

local function distanceSquared(x1, y1, x2, y2)
  local dx = (tonumber(x2) or 0) - (tonumber(x1) or 0)
  local dy = (tonumber(y2) or 0) - (tonumber(y1) or 0)
  return dx * dx + dy * dy
end

local function getRegistry(ctx)
  local registry = ctx and ctx._patchbayPortRegistry or nil
  return type(registry) == "table" and registry or {}
end

local function getPortAnchor(ctx, portRef)
  if type(portRef) ~= "table" then
    return nil
  end

  local registry = getRegistry(ctx)
  local entry = nil
  if type(portRef.key) == "string" and registry[portRef.key] then
    entry = registry[portRef.key]
  else
    for _, candidate in pairs(registry) do
      if candidate.nodeId == portRef.nodeId
        and candidate.portId == portRef.portId
        and candidate.direction == portRef.direction then
        entry = candidate
        break
      end
    end
  end

  if type(entry) ~= "table" then
    return nil
  end

  local overlay = getOverlay(ctx)
  local ancestorId = getOverlayAncestorGlobalId(overlay)
  if not ancestorId then
    return nil
  end

  local x, y, w, h = getRelativeBounds(entry.widget, ancestorId)
  if not x then
    return nil
  end

  return {
    entry = entry,
    x = x + math.floor(w * 0.5),
    y = y + math.floor(h * 0.5),
    w = w,
    h = h,
    radius = math.max(6, math.floor(math.min(w, h) * 0.5)),
  }
end

local function portRefsCompatible(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  if a.direction == b.direction then
    return false
  end
  if a.nodeId == b.nodeId and a.portId == b.portId and a.direction == b.direction then
    return false
  end

  local aType = tostring(a.portType or "control")
  local bType = tostring(b.portType or "control")
  if aType ~= bType then
    return false
  end

  local hasOutput = (a.direction == "output") or (b.direction == "output")
  local hasInput = (a.direction == "input") or (b.direction == "input")
  return hasOutput and hasInput
end

local function findSnapTarget(ctx, sourceRef, cursorX, cursorY)
  if type(sourceRef) ~= "table" then
    return nil
  end

  local best = nil
  local bestDist2 = nil
  local snapRadius = 28
  local snapRadius2 = snapRadius * snapRadius

  for _, entry in pairs(getRegistry(ctx)) do
    if portRefsCompatible(sourceRef, entry) then
      local anchor = getPortAnchor(ctx, entry)
      if anchor then
        local dist2 = distanceSquared(cursorX, cursorY, anchor.x, anchor.y)
        if dist2 <= snapRadius2 and (bestDist2 == nil or dist2 < bestDist2) then
          best = shallowCopyPortRef(entry)
          bestDist2 = dist2
        end
      end
    end
  end

  return best
end

local function addGlowDot(commands, x, y, radius, fill, outline)
  local outer = math.max(8, round(radius + 4))
  local inner = math.max(4, round(radius))

  commands[#commands + 1] = {
    cmd = "fillRoundedRect",
    x = round(x - outer), y = round(y - outer),
    w = outer * 2, h = outer * 2,
    radius = outer,
    color = fill,
  }
  commands[#commands + 1] = {
    cmd = "drawRoundedRect",
    x = round(x - inner), y = round(y - inner),
    w = inner * 2, h = inner * 2,
    radius = inner,
    thickness = 2,
    color = outline,
  }
end

local function addWire(commands, x1, y1, x2, y2, palette, thickness)
  local dx = (x2 or 0) - (x1 or 0)
  local dy = (y2 or 0) - (y1 or 0)
  local absDx = math.abs(dx)
  local absDy = math.abs(dy)

  local cpOffset = math.max(44, math.min(180, absDx * 0.42 + absDy * 0.14))

  local cx1
  local cy1 = y1
  local cx2
  local cy2 = y2

  if dx >= 0 then
    cx1 = x1 + cpOffset
    cx2 = x2 - cpOffset
  else
    cx1 = x1 - cpOffset
    cx2 = x2 + cpOffset
  end

  commands[#commands + 1] = {
    cmd = "drawBezier",
    x1 = round(x1), y1 = round(y1),
    cx1 = round(cx1), cy1 = round(cy1),
    cx2 = round(cx2), cy2 = round(cy2),
    x2 = round(x2), y2 = round(y2),
    color = palette.shadow,
    thickness = thickness + 4.5,
    segments = 32,
  }
  commands[#commands + 1] = {
    cmd = "drawBezier",
    x1 = round(x1), y1 = round(y1),
    cx1 = round(cx1), cy1 = round(cy1),
    cx2 = round(cx2), cy2 = round(cy2),
    x2 = round(x2), y2 = round(y2),
    color = palette.glow,
    thickness = thickness + 2.4,
    segments = 32,
  }
  commands[#commands + 1] = {
    cmd = "drawBezier",
    x1 = round(x1), y1 = round(y1),
    cx1 = round(cx1), cy1 = round(cy1),
    cx2 = round(cx2), cy2 = round(cy2),
    x2 = round(x2), y2 = round(y2),
    color = palette.inner,
    thickness = thickness + 1.2,
    segments = 32,
  }
  commands[#commands + 1] = {
    cmd = "drawBezier",
    x1 = round(x1), y1 = round(y1),
    cx1 = round(cx1), cy1 = round(cy1),
    cx2 = round(cx2), cy2 = round(cy2),
    x2 = round(x2), y2 = round(y2),
    color = palette.core,
    thickness = thickness,
    segments = 32,
  }
end

local function normaliseConnectionEnds(a, b)
  if a.direction == "output" then
    return a, b
  end
  return b, a
end

local function connectionExists(ctx, fromRef, toRef)
  local connections = ctx and ctx._rackConnections or {}
  for i = 1, #connections do
    local conn = connections[i]
    local from = type(conn.from) == "table" and conn.from or nil
    local to = type(conn.to) == "table" and conn.to or nil
    if from and to
      and from.nodeId == fromRef.nodeId and from.portId == fromRef.portId
      and to.nodeId == toRef.nodeId and to.portId == toRef.portId then
      return true
    end
  end
  return false
end

local function getNodeRow(ctx, nodeId)
  local rackState = ctx and ctx._rackState or nil
  local nodes = rackState and rackState.nodes or nil
  if type(nodes) ~= "table" then
    return nil
  end
  for i = 1, #nodes do
    local node = nodes[i]
    if node and node.id == nodeId then
      return math.max(0, math.floor(tonumber(node.row) or 0))
    end
  end
  return nil
end

local function portTouchesConnection(ctx, portRef, conn)
  if type(portRef) ~= "table" or type(conn) ~= "table" then
    return false
  end

  local from = type(conn.from) == "table" and conn.from or nil
  local to = type(conn.to) == "table" and conn.to or nil
  if not (from and to) then
    return false
  end

  if portRef.nodeId == "__rackRail" then
    local route = type(conn.meta) == "table" and tostring(conn.meta.route or "") or ""
    if route ~= "relay" then
      return false
    end
    local row = tonumber(portRef.row)
    if row == nil then
      return false
    end
    if portRef.side == "right" then
      return getNodeRow(ctx, from.nodeId) == row
    elseif portRef.side == "left" then
      return getNodeRow(ctx, to.nodeId) == row
    end
    return false
  end

  if portRef.direction == "output" then
    return from.nodeId == portRef.nodeId and from.portId == portRef.portId
  elseif portRef.direction == "input" then
    return to.nodeId == portRef.nodeId and to.portId == portRef.portId
  end
  return false
end

function M.deleteConnectionsForPort(ctx, portRef)
  local connections = ctx and ctx._rackConnections or nil
  if type(connections) ~= "table" or type(portRef) ~= "table" then
    return 0
  end

  local kept = {}
  local removed = 0
  for i = 1, #connections do
    local conn = connections[i]
    if portTouchesConnection(ctx, portRef, conn) then
      removed = removed + 1
    else
      kept[#kept + 1] = conn
    end
  end

  if removed > 0 then
    ctx._rackConnections = kept
    _G.__midiSynthRackConnections = ctx._rackConnections
    M.refreshWires(ctx)
  end
  return removed
end

function M.generateWireDisplayList(ctx)
  local commands = {}
  local viewMode = (ctx._rackState and ctx._rackState.viewMode) or "perf"
  if viewMode ~= "patch" then
    return commands
  end

  local connections = ctx._rackConnections or {}
  for i = 1, #connections do
    local conn = connections[i]
    local from = type(conn.from) == "table" and conn.from or nil
    local to = type(conn.to) == "table" and conn.to or nil
    if from and to then
      local fromAnchor = getPortAnchor(ctx, {
        nodeId = from.nodeId,
        portId = from.portId,
        direction = "output",
      })
      local toAnchor = getPortAnchor(ctx, {
        nodeId = to.nodeId,
        portId = to.portId,
        direction = "input",
      })

      local basePalette = connectionPalette(conn)
      local visual = getWireVisualStyle(ctx, false)
      local palette = scalePaletteAlpha(basePalette, visual.alpha, visual.tipAlpha)
      local thickness = ((conn.kind == "audio") and 3.8 or 2.8) * visual.thicknessScale
      local route = type(conn.meta) == "table" and tostring(conn.meta.route or "") or ""

      if route == "relay" then
        local fromRow = getNodeRow(ctx, from.nodeId)
        local toRow = getNodeRow(ctx, to.nodeId)
        local sendRail = (fromRow ~= nil) and getPortAnchor(ctx, {
          key = string.format("rail:right:%d", fromRow),
          nodeId = "__rackRail",
          portId = string.format("send_row%d", fromRow + 1),
          direction = "input",
        }) or nil
        local recvRail = (toRow ~= nil) and getPortAnchor(ctx, {
          key = string.format("rail:left:%d", toRow),
          nodeId = "__rackRail",
          portId = string.format("recv_row%d", toRow + 1),
          direction = "output",
        }) or nil

        if fromAnchor and sendRail then
          addWire(commands, fromAnchor.x, fromAnchor.y, sendRail.x, sendRail.y, palette, thickness)
          addGlowDot(commands, fromAnchor.x, fromAnchor.y, fromAnchor.radius, palette.glow, palette.tip)
          addGlowDot(commands, sendRail.x, sendRail.y, sendRail.radius or 7, palette.glow, palette.tip)
        end
        if recvRail and toAnchor then
          addWire(commands, recvRail.x, recvRail.y, toAnchor.x, toAnchor.y, palette, thickness)
          addGlowDot(commands, recvRail.x, recvRail.y, recvRail.radius or 7, palette.glow, palette.tip)
          addGlowDot(commands, toAnchor.x, toAnchor.y, toAnchor.radius, palette.glow, palette.tip)
        end
      elseif fromAnchor and toAnchor then
        addWire(commands, fromAnchor.x, fromAnchor.y, toAnchor.x, toAnchor.y, palette, thickness)
        addGlowDot(commands, fromAnchor.x, fromAnchor.y, fromAnchor.radius, palette.glow, palette.tip)
        addGlowDot(commands, toAnchor.x, toAnchor.y, toAnchor.radius, palette.glow, palette.tip)
      end
    end
  end

  local drag = ctx._wireDrag
  if type(drag) == "table" and type(drag.source) == "table" then
    local sourceAnchor = getPortAnchor(ctx, drag.source)
    if sourceAnchor then
      local basePalette = portPalette(drag.source.portType)
      local visual = getWireVisualStyle(ctx, true)
      local palette = scalePaletteAlpha(basePalette, visual.alpha, visual.tipAlpha)
      local targetAnchor = drag.snapTarget and getPortAnchor(ctx, drag.snapTarget) or nil
      local x2 = targetAnchor and targetAnchor.x or round(drag.cursorX or sourceAnchor.x)
      local y2 = targetAnchor and targetAnchor.y or round(drag.cursorY or sourceAnchor.y)

      addWire(commands, sourceAnchor.x, sourceAnchor.y, x2, y2, palette, 3.2 * visual.thicknessScale)
      addGlowDot(commands, sourceAnchor.x, sourceAnchor.y, sourceAnchor.radius + 1, palette.glow, palette.tip)

      if targetAnchor then
        addGlowDot(commands, targetAnchor.x, targetAnchor.y, targetAnchor.radius + 2, palette.glow, palette.tip)
      else
        addGlowDot(commands, x2, y2, 7, palette.glow, palette.tip)
      end
    end
  end

  return commands
end

function M.updateWireOverlay(ctx)
  local overlay = getOverlay(ctx)
  if not (overlay and overlay.node and overlay.node.setDisplayList) then
    return
  end

  overlay.node:setDisplayList(M.generateWireDisplayList(ctx))
  if overlay.node.repaint then
    overlay.node:repaint()
  end
end

function M.setupWireLayer(ctx)
  M.updateWireOverlay(ctx)
end

function M.refreshWires(ctx)
  M.updateWireOverlay(ctx)
end

function M.beginWireDrag(ctx, portRef)
  if type(portRef) ~= "table" then
    return
  end
  ctx._wireDrag = {
    source = shallowCopyPortRef(portRef),
    cursorX = 0,
    cursorY = 0,
    snapTarget = nil,
  }
  M.refreshWires(ctx)
end

function M.updateWireDragPointer(ctx, widget, localX, localY)
  local drag = ctx and ctx._wireDrag or nil
  local overlay = getOverlay(ctx)
  local ancestorId = getOverlayAncestorGlobalId(overlay)
  if not (drag and widget and ancestorId) then
    return
  end

  local wx, wy = getRelativeBounds(widget, ancestorId)
  if not wx then
    return
  end

  drag.cursorX = wx + round(localX or 0)
  drag.cursorY = wy + round(localY or 0)
  drag.snapTarget = findSnapTarget(ctx, drag.source, drag.cursorX, drag.cursorY)
  M.refreshWires(ctx)
end

function M.finishWireDrag(ctx)
  local drag = ctx and ctx._wireDrag or nil
  if type(drag) ~= "table" then
    return false
  end

  local snapTarget = drag.snapTarget
  local source = drag.source
  ctx._wireDrag = nil

  if not (type(source) == "table" and type(snapTarget) == "table" and portRefsCompatible(source, snapTarget)) then
    M.refreshWires(ctx)
    return false
  end

  local fromRef, toRef = normaliseConnectionEnds(source, snapTarget)
  ctx._rackConnections = ctx._rackConnections or {}

  if not connectionExists(ctx, fromRef, toRef) then
    ctx._rackConnections[#ctx._rackConnections + 1] = {
      id = connectionId(fromRef, toRef),
      kind = tostring(fromRef.portType or "control"),
      from = { nodeId = fromRef.nodeId, portId = fromRef.portId },
      to = { nodeId = toRef.nodeId, portId = toRef.portId },
      meta = {
        pending = true,
        source = "ui-dummy-wire",
      },
    }
  end

  M.refreshWires(ctx)
  return true
end

function M.cancelWireDrag(ctx)
  if ctx then
    ctx._wireDrag = nil
    M.refreshWires(ctx)
  end
end

return M

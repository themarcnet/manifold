local M = {}

local function shallowCopyArray(values)
  local out = {}
  if type(values) ~= "table" then
    return out
  end
  for i = 1, #values do
    out[i] = values[i]
  end
  return out
end

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deepCopy(v)
  end
  return out
end

local function clampInt(value, fallback, minimum)
  local n = math.floor(tonumber(value) or fallback or 0)
  if minimum ~= nil and n < minimum then
    return minimum
  end
  return n
end

local function compareNodeOrder(a, b)
  local ac = tonumber(a.col) or 0
  local bc = tonumber(b.col) or 0
  if ac ~= bc then
    return ac < bc
  end
  return tostring(a.id or "") < tostring(b.id or "")
end

local function sanitizeUtilitySlot(slot, fallbackKind, fallbackVariant)
  local value = type(slot) == "table" and deepCopy(slot) or {}
  local kind = type(value.kind) == "string" and value.kind ~= "" and value.kind or (fallbackKind or "keyboard")
  local variant = type(value.variant) == "string" and value.variant ~= "" and value.variant or (fallbackVariant or "full")
  return {
    kind = kind,
    variant = variant,
  }
end

function M.defaultUtilityDock()
  return {
    visible = true,
    mode = "full_keyboard",
    heightMode = "full",
    layoutMode = "single",
    primary = { kind = "keyboard", variant = "full" },
    secondary = nil,
  }
end

function M.defaultRackState()
  return {
    viewMode = "perf",
    densityMode = "normal",
    utilityDock = M.defaultUtilityDock(),
    nodes = {},
  }
end

function M.sanitizeUtilityDock(dock)
  local defaults = M.defaultUtilityDock()
  local value = type(dock) == "table" and deepCopy(dock) or {}

  if value.visible == nil then value.visible = defaults.visible end
  if type(value.mode) ~= "string" or value.mode == "" then value.mode = defaults.mode end
  if type(value.heightMode) ~= "string" or value.heightMode == "" then value.heightMode = defaults.heightMode end
  if type(value.layoutMode) ~= "string" or value.layoutMode == "" then value.layoutMode = defaults.layoutMode end

  local visible = value.visible ~= false
  local mode = value.mode
  local heightMode = value.heightMode
  local layoutMode = value.layoutMode

  if heightMode ~= "collapsed" and heightMode ~= "compact" and heightMode ~= "full" then
    heightMode = defaults.heightMode
  end
  if layoutMode ~= "single" and layoutMode ~= "split" then
    layoutMode = defaults.layoutMode
  end

  local primary = value.primary
  local secondary = value.secondary

  if mode == "hidden" then
    visible = false
  elseif mode == "compact_keyboard" then
    primary = { kind = "keyboard", variant = "compact" }
    if heightMode == "full" then heightMode = "compact" end
    mode = "keyboard"
  elseif mode == "full_keyboard" then
    primary = { kind = "keyboard", variant = "full" }
    mode = "keyboard"
  elseif mode == "keyboard" then
    primary = primary or { kind = "keyboard", variant = (heightMode == "compact" and "compact" or "full") }
  end

  primary = sanitizeUtilitySlot(primary, defaults.primary.kind, (heightMode == "compact" and "compact" or defaults.primary.variant))
  if primary.kind == "keyboard" and (primary.variant ~= "compact" and primary.variant ~= "full") then
    primary.variant = heightMode == "compact" and "compact" or "full"
  end

  local normalizedSecondary = nil
  if type(secondary) == "table" then
    normalizedSecondary = sanitizeUtilitySlot(secondary, "utility", "compact")
  end

  if layoutMode == "single" then
    normalizedSecondary = nil
  end

  return {
    visible = visible,
    mode = mode,
    heightMode = heightMode,
    layoutMode = layoutMode,
    primary = primary,
    secondary = normalizedSecondary,
  }
end

function M.sanitizeRackState(state)
  local defaults = M.defaultRackState()
  local source = type(state) == "table" and state or {}
  local nodes = {}
  for i = 1, #(source.nodes or {}) do
    nodes[i] = M.makeNodeInstance(source.nodes[i])
  end
  return {
    viewMode = type(source.viewMode) == "string" and source.viewMode or defaults.viewMode,
    densityMode = type(source.densityMode) == "string" and source.densityMode or defaults.densityMode,
    utilityDock = M.sanitizeUtilityDock(source.utilityDock),
    nodes = nodes,
  }
end

function M.makeNodeSpec(spec)
  assert(type(spec) == "table", "node spec must be a table")
  assert(type(spec.id) == "string" and spec.id ~= "", "node spec id required")

  return {
    id = spec.id,
    name = type(spec.name) == "string" and spec.name or spec.id,
    validSizes = shallowCopyArray(spec.validSizes or { "1x1" }),
    ports = deepCopy(spec.ports or { inputs = {}, outputs = {}, params = {} }),
    renderers = deepCopy(spec.renderers or {}),
    accentColor = spec.accentColor,
    meta = deepCopy(spec.meta or {}),
  }
end

function M.makeNodeInstance(node)
  assert(type(node) == "table", "node instance must be a table")
  assert(type(node.id) == "string" and node.id ~= "", "node instance id required")

  return {
    id = node.id,
    row = clampInt(node.row, 0, 0),
    col = clampInt(node.col, 0, 0),
    w = clampInt(node.w, 1, 1),
    h = clampInt(node.h, 1, 1),
    sizeKey = type(node.sizeKey) == "string" and node.sizeKey or nil,
    meta = deepCopy(node.meta or {}),
  }
end

function M.makeConnectionDescriptor(connection)
  assert(type(connection) == "table", "connection descriptor must be a table")
  assert(type(connection.id) == "string" and connection.id ~= "", "connection id required")
  assert(type(connection.from) == "table", "connection.from required")
  assert(type(connection.to) == "table", "connection.to required")
  assert(type(connection.from.nodeId) == "string" and connection.from.nodeId ~= "", "connection.from.nodeId required")
  assert(type(connection.to.nodeId) == "string" and connection.to.nodeId ~= "", "connection.to.nodeId required")

  return {
    id = connection.id,
    kind = type(connection.kind) == "string" and connection.kind or "audio",
    from = {
      nodeId = connection.from.nodeId,
      portId = connection.from.portId,
    },
    to = {
      nodeId = connection.to.nodeId,
      portId = connection.to.portId,
    },
    meta = deepCopy(connection.meta or {}),
  }
end

function M.cloneNodes(nodes)
  local out = {}
  if type(nodes) ~= "table" then
    return out
  end
  for i = 1, #nodes do
    out[i] = M.makeNodeInstance(nodes[i])
  end
  return out
end

function M.findNodeIndex(nodes, nodeId)
  if type(nodes) ~= "table" then
    return nil
  end
  for i = 1, #nodes do
    if nodes[i] and nodes[i].id == nodeId then
      return i
    end
  end
  return nil
end

function M.cellsForNode(node)
  local item = M.makeNodeInstance(node)
  local cells = {}
  for row = item.row, item.row + item.h - 1 do
    for col = item.col, item.col + item.w - 1 do
      cells[#cells + 1] = {
        row = row,
        col = col,
        nodeId = item.id,
      }
    end
  end
  return cells
end

function M.buildOccupancy(nodes, ignoredNodeId)
  local occupancy = {
    cells = {},
    collisions = {},
  }

  if type(nodes) ~= "table" then
    return occupancy
  end

  for i = 1, #nodes do
    local node = nodes[i]
    if node and node.id ~= ignoredNodeId then
      local cells = M.cellsForNode(node)
      for j = 1, #cells do
        local cell = cells[j]
        local key = tostring(cell.row) .. ":" .. tostring(cell.col)
        local existing = occupancy.cells[key]
        if existing then
          occupancy.collisions[#occupancy.collisions + 1] = {
            key = key,
            row = cell.row,
            col = cell.col,
            existingNodeId = existing,
            nodeId = cell.nodeId,
          }
        else
          occupancy.cells[key] = cell.nodeId
        end
      end
    end
  end

  return occupancy
end

function M.isAreaFree(nodes, row, col, w, h, ignoredNodeId)
  local occupancy = M.buildOccupancy(nodes, ignoredNodeId)
  local rr = clampInt(row, 0, 0)
  local cc = clampInt(col, 0, 0)
  local ww = clampInt(w, 1, 1)
  local hh = clampInt(h, 1, 1)

  for r = rr, rr + hh - 1 do
    for c = cc, cc + ww - 1 do
      local key = tostring(r) .. ":" .. tostring(c)
      if occupancy.cells[key] ~= nil then
        return false
      end
    end
  end

  return true
end

function M.getRowNodes(nodes, row)
  local out = {}
  if type(nodes) ~= "table" then
    return out
  end
  local targetRow = clampInt(row, 0, 0)
  for i = 1, #nodes do
    local node = nodes[i]
    if node and clampInt(node.row, 0, 0) == targetRow then
      out[#out + 1] = M.makeNodeInstance(node)
    end
  end
  table.sort(out, compareNodeOrder)
  return out
end

local function replaceRowNodes(allNodes, row, rowNodes)
  local targetRow = clampInt(row, 0, 0)
  local out = {}
  if type(allNodes) == "table" then
    for i = 1, #allNodes do
      local node = allNodes[i]
      if node and clampInt(node.row, 0, 0) ~= targetRow then
        out[#out + 1] = M.makeNodeInstance(node)
      end
    end
  end
  for i = 1, #rowNodes do
    out[#out + 1] = M.makeNodeInstance(rowNodes[i])
  end
  return out
end

function M.packRow(nodes, row)
  local rowNodes = M.getRowNodes(nodes, row)
  local cursor = 0
  for i = 1, #rowNodes do
    rowNodes[i].col = cursor
    cursor = cursor + rowNodes[i].w
  end
  return replaceRowNodes(nodes, row, rowNodes)
end

function M.moveNodeWithinRow(nodes, nodeId, targetIndex)
  local allNodes = M.cloneNodes(nodes)
  local sourceIndex = M.findNodeIndex(allNodes, nodeId)
  assert(sourceIndex ~= nil, "node not found for same-row move: " .. tostring(nodeId))

  local node = allNodes[sourceIndex]
  local row = node.row
  local rowNodes = M.getRowNodes(allNodes, row)
  local movingIndex = nil
  for i = 1, #rowNodes do
    if rowNodes[i].id == nodeId then
      movingIndex = i
      break
    end
  end
  assert(movingIndex ~= nil, "row node not found for same-row move: " .. tostring(nodeId))

  local moving = rowNodes[movingIndex]
  table.remove(rowNodes, movingIndex)

  local clampedTarget = clampInt(targetIndex, #rowNodes + 1, 1)
  if clampedTarget > (#rowNodes + 1) then
    clampedTarget = #rowNodes + 1
  end
  table.insert(rowNodes, clampedTarget, moving)

  local cursor = 0
  for i = 1, #rowNodes do
    rowNodes[i].row = row
    rowNodes[i].col = cursor
    cursor = cursor + rowNodes[i].w
  end

  return replaceRowNodes(allNodes, row, rowNodes)
end

function M.getFlowNodes(nodes)
  local out = M.cloneNodes(nodes)
  table.sort(out, function(a, b)
    local ar = clampInt(a.row, 0, 0)
    local br = clampInt(b.row, 0, 0)
    if ar ~= br then
      return ar < br
    end
    local ac = tonumber(a.col) or 0
    local bc = tonumber(b.col) or 0
    if ac ~= bc then
      return ac < bc
    end
    return tostring(a.id or "") < tostring(b.id or "")
  end)
  return out
end

function M.wrapFlowNodes(nodes, columnsPerRow, startRow)
  local ordered = M.cloneNodes(nodes)
  local maxCols = math.max(1, clampInt(columnsPerRow, 5, 1))
  local row = clampInt(startRow, 0, 0)
  local cursor = 0

  for i = 1, #ordered do
    local node = ordered[i]
    local width = math.max(1, clampInt(node.w, 1, 1))
    if width > maxCols then
      width = maxCols
      node.w = width
    end
    if cursor > 0 and (cursor + width) > maxCols then
      row = row + 1
      cursor = 0
    end
    node.row = row
    node.col = cursor
    cursor = cursor + width
  end

  return ordered
end

function M.moveNodeInFlow(nodes, nodeId, targetIndex, columnsPerRow, startRow)
  local ordered = M.getFlowNodes(nodes)
  local movingIndex = nil
  for i = 1, #ordered do
    if ordered[i].id == nodeId then
      movingIndex = i
      break
    end
  end
  assert(movingIndex ~= nil, "flow node not found for move: " .. tostring(nodeId))

  local moving = ordered[movingIndex]
  table.remove(ordered, movingIndex)

  local clampedTarget = clampInt(targetIndex, #ordered + 1, 1)
  if clampedTarget > (#ordered + 1) then
    clampedTarget = #ordered + 1
  end
  table.insert(ordered, clampedTarget, moving)

  return M.wrapFlowNodes(ordered, columnsPerRow, startRow)
end

function M.relocateNodeToRow(nodes, nodeId, targetRow, targetIndex)
  local allNodes = M.cloneNodes(nodes)
  local sourceIndex = M.findNodeIndex(allNodes, nodeId)
  assert(sourceIndex ~= nil, "node not found for row relocation: " .. tostring(nodeId))

  local moving = allNodes[sourceIndex]
  local sourceRow = moving.row
  moving.row = clampInt(targetRow, sourceRow, 0)
  moving.col = 0
  allNodes[sourceIndex] = moving

  local sourcePacked = M.packRow(allNodes, sourceRow)
  local destinationNodes = M.getRowNodes(sourcePacked, moving.row)

  local withoutMoving = {}
  for i = 1, #destinationNodes do
    if destinationNodes[i].id ~= moving.id then
      withoutMoving[#withoutMoving + 1] = destinationNodes[i]
    end
  end

  local clampedTarget = clampInt(targetIndex, #withoutMoving + 1, 1)
  if clampedTarget > (#withoutMoving + 1) then
    clampedTarget = #withoutMoving + 1
  end
  table.insert(withoutMoving, clampedTarget, moving)

  local cursor = 0
  for i = 1, #withoutMoving do
    withoutMoving[i].row = moving.row
    withoutMoving[i].col = cursor
    cursor = cursor + withoutMoving[i].w
  end

  return replaceRowNodes(sourcePacked, moving.row, withoutMoving)
end

local function serializeLuaValue(value, indent)
  local t = type(value)
  indent = indent or ""

  if t == "nil" then
    return "nil"
  end
  if t == "number" or t == "boolean" then
    return tostring(value)
  end
  if t == "string" then
    return string.format("%q", value)
  end
  if t ~= "table" then
    error("unsupported Lua serialization type: " .. t)
  end

  local isArray = true
  local count = 0
  local maxIndex = 0
  for k, _ in pairs(value) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
      isArray = false
      break
    end
    count = count + 1
    if k > maxIndex then maxIndex = k end
  end
  if isArray and maxIndex ~= count then
    isArray = false
  end

  local nextIndent = indent .. "  "
  if isArray then
    if count == 0 then
      return "{}"
    end
    local out = { "{" }
    for i = 1, count do
      out[#out + 1] = nextIndent .. serializeLuaValue(value[i], nextIndent) .. ","
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out, "\n")
  end

  local keys = {}
  for k, _ in pairs(value) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  if #keys == 0 then
    return "{}"
  end

  local out = { "{" }
  for i = 1, #keys do
    local key = keys[i]
    local keyText
    if type(key) == "string" and key:match("^[%a_][%w_]*$") then
      keyText = key
    else
      keyText = "[" .. serializeLuaValue(key, nextIndent) .. "]"
    end
    out[#out + 1] = nextIndent .. keyText .. " = " .. serializeLuaValue(value[key], nextIndent) .. ","
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end

function M.serializeLuaLiteral(value)
  return serializeLuaValue(value, "")
end

return M

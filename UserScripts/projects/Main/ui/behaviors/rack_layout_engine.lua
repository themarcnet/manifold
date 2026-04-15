-- Rack Layout Engine Module
-- Extracted from midisynth.lua 
-- Handles rack layout, drag-drop reordering, pagination, module spawning and deletion

local M = {}

-- Dependencies (provided via init)
local deps = {}

-- Local state
local dragState = {
  active = false,
  sourceKind = nil,
  shellId = nil,
  moduleId = nil,
  row = nil,
  paletteEntryId = nil,
  unregisterOnCancel = false,
  startX = 0,
  startY = 0,
  grabOffsetX = 0,
  grabOffsetY = 0,
  startIndex = nil,
  targetIndex = nil,
  previewIndex = nil,
  startPlacement = nil,
  previewPlacement = nil,
  rowSnapshot = nil,
  baseModules = nil,
  insertMode = false,
  ghostStartX = 0,
  ghostStartY = 0,
  ghostX = 0,
  ghostY = 0,
  ghostW = 0,
  ghostH = 0,
}

function M.ensureRackPaginationState(ctx)
  if not ctx._rackPagination then
    ctx._rackPagination = {
      totalRows = 1,
      rowsPerPage = 1,
      pageCount = 1,
      visibleRows = {1},
      viewportOffset = 0,
      showAll = true,
    }
  end
  _G.__midiSynthRackPagination = ctx._rackPagination
  return ctx._rackPagination
end

function M.getRackNodeRowById(ctx, nodeId)
  local nodes = ctx and ctx._rackState and ctx._rackState.modules or nil
  if type(nodes) ~= "table" then
    return nil
  end
  for i = 1, #nodes do
    local node = nodes[i]
    if node and tostring(node.id or "") == tostring(nodeId or "") then
      return math.max(0, math.floor(tonumber(node.row) or 0))
    end
  end
  return nil
end

function M.getRackTotalRows(ctx)
  local rackState = ctx and ctx._rackState or nil
  local nodes = rackState and rackState.modules or nil
  local maxRow = -1
  if type(nodes) == "table" then
    for i = 1, #nodes do
      local node = nodes[i]
      if node and node.row then
        maxRow = math.max(maxRow, tonumber(node.row) or 0)
      end
    end
  end
  local defaultRackState = deps.MidiSynthRackSpecs and deps.MidiSynthRackSpecs.defaultRackState and deps.MidiSynthRackSpecs.defaultRackState() or {}
  local defaultModules = defaultRackState.modules or {}
  for i = 1, #defaultModules do
    local node = defaultModules[i]
    if node and node.row then
      maxRow = math.max(maxRow, tonumber(node.row) or 0)
    end
  end
  return maxRow + 1
end

function M.syncRackPaginationModel(ctx, viewportHeight)
  local ensuring = M.ensureRackPaginationState(ctx)
  local totalRows = M.getRackTotalRows(ctx)
  local rackSlotH = tonumber(deps.RackLayoutManager and deps.RackLayoutManager.RACK_SLOT_H) or 220
  local rowsPerPage = math.max(1, math.floor(viewportHeight / rackSlotH))
  local pageCount = math.max(1, math.ceil(totalRows / rowsPerPage))
  local currentPage = math.max(1, math.floor(ensuring.viewportOffset / rowsPerPage) + 1)
  
  local pagination = ctx._rackPagination
  pagination.totalRows = totalRows
  pagination.rowsPerPage = rowsPerPage
  pagination.pageCount = pageCount
  pagination.currentPage = currentPage
  pagination.showAll = (totalRows <= rowsPerPage)
  
  local visibleRows = {}
  local startRow = pagination.viewportOffset
  for i = 0, rowsPerPage - 1 do
    if startRow + i < totalRows then
      table.insert(visibleRows, startRow + i + 1)
    end
  end
  pagination.visibleRows = visibleRows
  _G.__midiSynthRackPagination = pagination
  return pagination
end

function M.updateRackPaginationDots(ctx)
  local pagination = ctx._rackPagination
  if not pagination then return end
  local dotsContainer = deps.getScopedWidget and deps.getScopedWidget(ctx, ".paginationDots")
  if not dotsContainer then return end
end

function M.setRackViewport(ctx, offset)
  local ensuring = M.ensureRackPaginationState(ctx)
  ensuring.viewportOffset = math.max(0, offset or 0)
  _G.__midiSynthRackPagination = ensuring
end

function M.onRackDotClick(ctx, dotIndex)
  local pagination = ctx._rackPagination
  if not pagination then return end
  local targetPage = dotIndex
  local viewportOffset = (targetPage - 1) * pagination.rowsPerPage
  M.setRackViewport(ctx, viewportOffset)
end

function M.resetDragState(ctx)
  dragState.active = false
  dragState.sourceKind = nil
  dragState.shellId = nil
  dragState.moduleId = nil
  dragState.row = nil
  dragState.paletteEntryId = nil
  dragState.unregisterOnCancel = false
  dragState.startX = 0
  dragState.startY = 0
  dragState.grabOffsetX = 0
  dragState.grabOffsetY = 0
  dragState.startIndex = nil
  dragState.targetIndex = nil
  dragState.previewIndex = nil
  dragState.startPlacement = nil
  dragState.previewPlacement = nil
  dragState.rowSnapshot = nil
  dragState.baseModules = nil
  dragState.insertMode = false
end

function M.getRackShellMetaByNodeId(nodeId)
  if type(RACK_MODULE_SHELL_LAYOUT) ~= "table" then
    return nil
  end
  return RACK_MODULE_SHELL_LAYOUT[nodeId]
end

function M.getRackNodeIdByShellId(shellId)
  if type(RACK_MODULE_SHELL_LAYOUT) ~= "table" then
    return nil
  end
  for nodeId, meta in pairs(RACK_MODULE_SHELL_LAYOUT) do
    if meta and meta.shellId == shellId then
      return nodeId
    end
  end
  return nil
end

function M.getWidgetBounds(widget)
  if not widget then return nil end
  local bounds = {}
  bounds.x, bounds.y, bounds.w, bounds.h = widget:getBounds()
  return bounds
end

function M.getWidgetBoundsInRoot(ctx, widget)
  local bounds = M.getWidgetBounds(widget)
  if not bounds then return nil end
  local rootX, rootY = ctx._root:getOffset()
  bounds.x = bounds.x + rootX
  bounds.y = bounds.y + rootY
  return bounds
end

function M.getShellWidget(ctx, nodeId)
  local shellMeta = M.getRackShellMetaByNodeId(nodeId)
  if not shellMeta then return nil end
  return deps.getScopedWidget and deps.getScopedWidget(ctx, "." .. shellMeta.shellId)
end

function M.setShellDragPlaceholder(ctx, nodeId, active)
  local shellWidget = M.getShellWidget(ctx, nodeId)
  if not shellWidget then return end
  if active then
    shellWidget:setOpacity(0.3)
  else
    shellWidget:setOpacity(1.0)
  end
end

function M.ensureDragGhost(ctx)
  if not ctx._dragGhost then
    local GhostWidget = deps.GhostWidget
    if GhostWidget then
      ctx._dragGhost = GhostWidget.new()
      ctx._dragGhost:setVisible(false)
      ctx._root:addChild(ctx._dragGhost)
    end
  end
  return ctx._dragGhost
end

function M.hideDragGhost(ctx)
  if ctx._dragGhost then
    ctx._dragGhost:setVisible(false)
  end
end

function M.updateDragGhost(ctx)
  local ghost = ctx._dragGhost
  if not ghost then return end
  if not dragState.active then
    M.hideDragGhost(ctx)
    return
  end
  ghost:setVisible(true)
  ghost:setBounds(dragState.ghostX, dragState.ghostY, dragState.ghostW, dragState.ghostH)
end

function M.getActiveRackNodes(ctx)
  return ctx._rackState and ctx._rackState.modules or {}
end

function M.getActiveRackNodeById(ctx, nodeId)
  local nodes = M.getActiveRackNodes(ctx)
  for i = 1, #nodes do
    if nodes[i] and tostring(nodes[i].id) == tostring(nodeId) then
      return nodes[i]
    end
  end
  return nil
end

function M.attach(midiSynth)
  deps.midiSynth = midiSynth
  -- Expose layout functions to host module
  midiSynth.ensureRackPaginationState = M.ensureRackPaginationState
  midiSynth.getRackNodeRowById = M.getRackNodeRowById
  midiSynth.getRackTotalRows = M.getRackTotalRows
  midiSynth.syncRackPaginationModel = M.syncRackPaginationModel
  midiSynth.updateRackPaginationDots = M.updateRackPaginationDots
  midiSynth.setRackViewport = M.setRackViewport
  midiSynth.onRackDotClick = M.onRackDotClick
  midiSynth.resetDragState = M.resetDragState
  midiSynth.getRackShellMetaByNodeId = M.getRackShellMetaByNodeId
  midiSynth.getRackNodeIdByShellId = M.getRackNodeIdByShellId
  midiSynth.getWidgetBounds = M.getWidgetBounds
  midiSynth.getWidgetBoundsInRoot = M.getWidgetBoundsInRoot
  midiSynth.getShellWidget = M.getShellWidget
  midiSynth.setShellDragPlaceholder = M.setShellDragPlaceholder
  midiSynth.ensureDragGhost = M.ensureDragGhost
  midiSynth.hideDragGhost = M.hideDragGhost
  midiSynth.updateDragGhost = M.updateDragGhost
  midiSynth.getActiveRackNodes = M.getActiveRackNodes
  midiSynth.getActiveRackNodeById = M.getActiveRackNodeById
end

function M.init(options)
  options = options or {}
  deps.getScopedWidget = options.getScopedWidget
  deps.GhostWidget = options.GhostWidget
  deps.RackLayoutManager = options.RackLayoutManager or require("ui.rack_layout_manager")
  deps.MidiSynthRackSpecs = options.MidiSynthRackSpecs or require("behaviors.rack_midisynth_specs")
  deps.RackModuleFactory = options.RackModuleFactory or require("ui.rack_module_factory")
  deps.setPath = options.setPath
  deps.ParameterBinder = options.ParameterBinder or require("parameter_binder")
  deps.RackLayout = options.RackLayout or require("behaviors.rack_layout")
  deps.PatchbayRuntime = options.PatchbayRuntime
  deps.RackWireLayer = options.RackWireLayer
  deps.RackModPopover = options.RackModPopover
end

return M

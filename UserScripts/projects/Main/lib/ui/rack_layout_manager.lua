-- Rack Layout Manager
-- Handles rack shell positioning, row layout, and widget bounds management

local WidgetSync = require("ui.widget_sync")
local ScopedWidget = require("ui.scoped_widget")

local M = {}

-- Constants
M.CANONICAL_RACK_HEIGHT = 452
M.RACK_SLOT_W = 236
M.RACK_SLOT_H = 220
M.RACK_ROW_GAP = 0
M.RACK_ROW_PADDING_X = 0

-- Re-export helpers
local round = WidgetSync.round
local getScopedWidget = ScopedWidget.getScopedWidget

-- Relayout a widget subtree after resize
function M.relayoutWidgetSubtree(widget, width, height)
  if widget == nil then
    return false
  end

  local runtime = widget._structuredRuntime
  local record = widget._structuredRecord
  if type(runtime) ~= "table" or type(runtime.notifyRecordHostedResized) ~= "function" or type(record) ~= "table" then
    return false
  end

  local ok = pcall(function()
    runtime:notifyRecordHostedResized(record, width, height)
  end)
  return ok == true
end

-- Update layout child values
function M.updateLayoutChild(widget, values)
  local record = widget and widget._structuredRecord or nil
  local spec = record and record.spec or nil
  if type(spec) ~= "table" then
    return false
  end

  local layoutChild = spec.layoutChild
  if type(layoutChild) ~= "table" then
    layoutChild = {}
    spec.layoutChild = layoutChild
  end

  local changed = false
  for key, value in pairs(values or {}) do
    local nextValue = value
    if type(value) == "number" then
      nextValue = round(value)
    end
    if layoutChild[key] ~= nextValue then
      layoutChild[key] = nextValue
      changed = true
    end
  end
  return changed
end

-- Update widget rect spec
function M.updateWidgetRectSpec(widget, x, y, w, h)
  local record = widget and widget._structuredRecord or nil
  local spec = record and record.spec or nil
  if type(spec) ~= "table" then
    return false
  end

  local changed = false
  local values = {
    x = round(x or 0),
    y = round(y or 0),
    w = math.max(1, round(w or 1)),
    h = math.max(1, round(h or 1)),
  }
  for key, value in pairs(values) do
    if spec[key] ~= value then
      spec[key] = value
      changed = true
    end
  end
  return changed
end

-- Compute projected row widths for nodes
function M.computeProjectedRowWidths(nodes, rowBounds)
  local count = #nodes
  if count == 0 then
    return {}
  end

  local widths = {}
  for i = 1, count do
    local widthUnits = math.max(1, tonumber(nodes[i].w) or 1)
    widths[i] = widthUnits * M.RACK_SLOT_W
  end

  return widths
end

-- Sync rack shell layout positions
function M.syncShellLayout(ctx, deps)
  deps = deps or {}
  local RackLayout = deps.RackLayout
  local MidiSynthRackSpecs = deps.MidiSynthRackSpecs
  local ensureUtilityDockState = deps.ensureUtilityDockState
  local getWidgetBounds = deps.getWidgetBounds
  local setWidgetBounds = deps.setWidgetBounds
  local syncText = deps.syncText
  local RACK_SHELL_LAYOUT = deps.RACK_SHELL_LAYOUT

  if not (RackLayout and MidiSynthRackSpecs and ensureUtilityDockState) then
    return false
  end

  local defaultRackState = MidiSynthRackSpecs.defaultRackState()
  local rackState = ctx._rackState or {
    viewMode = defaultRackState.viewMode,
    densityMode = defaultRackState.densityMode,
    utilityDock = defaultRackState.utilityDock,
    nodes = RackLayout.cloneNodes(defaultRackState.nodes),
  }
  if #(rackState.nodes or {}) == 0 then
    rackState.nodes = RackLayout.cloneNodes(defaultRackState.nodes)
  end
  ctx._rackState = rackState
  ctx._utilityDock = rackState.utilityDock or ctx._utilityDock

  local rowBoundsByRow = {}
  for row = 0, 7 do
    local rowWidget = getScopedWidget(ctx, ".rackRow" .. tostring(row + 1))
    if rowWidget then
      rowBoundsByRow[row] = getWidgetBounds and getWidgetBounds(rowWidget) or nil
    end
  end

  local layoutNodes = RackLayout.getFlowNodes(ctx._dragPreviewNodes or rackState.nodes or {})
  local rowBuckets = {}
  for i = 1, #layoutNodes do
    local node = layoutNodes[i]
    local row = math.max(0, tonumber(node.row) or 0)
    local bucket = rowBuckets[row]
    if not bucket then
      bucket = {}
      rowBuckets[row] = bucket
    end
    bucket[#bucket + 1] = node
  end

  local changed = false
  for row, bucket in pairs(rowBuckets) do
    local rowBounds = rowBoundsByRow[row]
    if rowBounds then
      local rowLeft = (tonumber(rowBounds.x) or 0) + M.RACK_ROW_PADDING_X
      local rowTop = tonumber(rowBounds.y) or 0
      for i = 1, #bucket do
        local node = bucket[i]
        local shellMeta = node and RACK_SHELL_LAYOUT and RACK_SHELL_LAYOUT[node.id] or nil
        if shellMeta then
          local shellWidget = getScopedWidget(ctx, "." .. shellMeta.shellId)
          local width = math.max(1, tonumber(node.w) or 1) * M.RACK_SLOT_W
          local height = math.max(1, tonumber(node.h) or 1) * M.RACK_SLOT_H
          local x = rowLeft + (math.max(0, tonumber(node.col) or 0) * (M.RACK_SLOT_W + M.RACK_ROW_GAP))
          local y = rowTop
          if shellWidget then
            changed = M.updateWidgetRectSpec(shellWidget, x, y, width, height) or changed
            if setWidgetBounds then
              changed = setWidgetBounds(shellWidget, x, y, width, height) or changed
            end
            M.relayoutWidgetSubtree(shellWidget, width, height)
          end
          local badge = getScopedWidget(ctx, shellMeta.badgeSuffix)
          local sizeText = type(node.sizeKey) == "string" and node.sizeKey ~= "" and node.sizeKey or string.format("%dx%d", math.max(1, tonumber(node.h) or 1), math.max(1, tonumber(node.w) or 1))
          if syncText then
            syncText(badge, sizeText)
          end
        end
      end
    end
  end

  return changed
end

return M

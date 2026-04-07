local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Layout = require("ui.canonical_layout")

local RackBlendSimpleBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/blend_simple/1"
local FALLBACK_MODULE_ID = "blend_simple_inst_1"
local MODE_NAMES = { "Mix", "Ring", "FM", "Sync" }
local MODE_DESCRIPTIONS = {
  "Crossfade between serial input A and auxiliary input B.",
  "Ring-modulate A with B, then blend dry and wet.",
  "Audio-rate FM-style delay modulation using B on A.",
  "Reset-style sync slicing driven by zero-crossings from B.",
}

local COMPACT_LAYOUT_CUTOFF_W = 300
local COMPACT_REFERENCE_SIZE = { w = 236, h = 208 }
local WIDE_REFERENCE_SIZE = { w = 472, h = 208 }

local COMPACT_RECTS = {
  title = { x = 12, y = 10, w = 120, h = 14 },
  status_label = { x = 12, y = 28, w = 212, h = 12 },
  mode_dropdown = { x = 12, y = 48, w = 100, h = 20 },
  blendAmount_slider = { x = 12, y = 82, w = 212, h = 20 },
  blendModAmount_slider = { x = 12, y = 108, w = 212, h = 20 },
  output_slider = { x = 12, y = 134, w = 212, h = 20 },
  detail_label = { x = 12, y = 162, w = 212, h = 28 },
}

local WIDE_RECTS = {
  title = { x = 12, y = 10, w = 160, h = 14 },
  status_label = { x = 12, y = 28, w = 448, h = 12 },
  mode_dropdown = { x = 12, y = 48, w = 112, h = 20 },
  io_label = { x = 136, y = 52, w = 224, h = 12 },
  blendAmount_slider = { x = 12, y = 82, w = 448, h = 20 },
  blendModAmount_slider = { x = 12, y = 108, w = 448, h = 20 },
  output_slider = { x = 12, y = 134, w = 448, h = 20 },
  detail_label = { x = 12, y = 162, w = 448, h = 28 },
}

local function anchorDropdown(dropdown, root)
  if not dropdown or not dropdown.setAbsolutePos or not dropdown.node or not root or not root.node then return end
  local ax, ay = 0, 0
  local node = dropdown.node
  local depth = 0
  while node and depth < 20 do
    local bx, by = node:getBounds()
    ax = ax + (bx or 0)
    ay = ay + (by or 0)
    local ok, parent = pcall(function() return node:getParent() end)
    if ok and parent and parent ~= node then
      node = parent
    else
      break
    end
    depth = depth + 1
  end
  dropdown:setAbsolutePos(ax, ay)
end

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function syncView(ctx)
  local modeValue = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "mode"), ctx.values.mode or 0), 0, 3) + 0.5)
  local blendAmountBase, blendAmountEffective, blendAmountState = ModWidgetSync.resolveValues(pathFor(ctx, "blendAmount"), ctx.values.blendAmount or 0.5, Ui.readParam)
  local blendModAmountBase, blendModAmountEffective, blendModAmountState = ModWidgetSync.resolveValues(pathFor(ctx, "blendModAmount"), ctx.values.blendModAmount or 0.5, Ui.readParam)
  local outputBase, outputEffective, outputState = ModWidgetSync.resolveValues(pathFor(ctx, "output"), ctx.values.output or 1.0, Ui.readParam)

  ctx.values.mode = modeValue
  ctx.values.blendAmount = Ui.clamp(blendAmountBase, 0.0, 1.0)
  ctx.values.blendModAmount = Ui.clamp(blendModAmountBase, 0.0, 1.0)
  ctx.values.output = Ui.clamp(outputBase, 0.0, 1.0)

  Ui.setOptions(ctx.widgets and ctx.widgets.mode_dropdown or nil, MODE_NAMES, modeValue + 1)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.blendAmount_slider or nil, ctx.values.blendAmount, Ui.clamp(blendAmountEffective, 0.0, 1.0), blendAmountState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.blendModAmount_slider or nil, ctx.values.blendModAmount, Ui.clamp(blendModAmountEffective, 0.0, 1.0), blendModAmountState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.output_slider or nil, ctx.values.output, Ui.clamp(outputEffective, 0.0, 1.0), outputState)

  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  %.0f%% blend / %.0f%% depth", MODE_NAMES[modeValue + 1], ctx.values.blendAmount * 100.0, ctx.values.blendModAmount * 100.0))
  Ui.setText(ctx.widgets and ctx.widgets.detail_label or nil, MODE_DESCRIPTIONS[modeValue + 1] or "")
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.mode_dropdown then
    ctx.widgets.mode_dropdown._onSelect = function(value)
      Ui.writeParam(pathFor(ctx, "mode"), math.floor(Ui.clamp((tonumber(value) or 1) - 1, 0, 3) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.blendAmount_slider then
    ctx.widgets.blendAmount_slider._onChange = function(value)
      Ui.writeParam(pathFor(ctx, "blendAmount"), Ui.clamp(value, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.blendModAmount_slider then
    ctx.widgets.blendModAmount_slider._onChange = function(value)
      Ui.writeParam(pathFor(ctx, "blendModAmount"), Ui.clamp(value, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.output_slider then
    ctx.widgets.output_slider._onChange = function(value)
      Ui.writeParam(pathFor(ctx, "output"), Ui.clamp(value, 0.0, 1.0))
      syncView(ctx)
    end
  end
end

function RackBlendSimpleBehavior.init(ctx)
  ctx.values = { mode = 0, blendAmount = 0.5, blendModAmount = 0.5, output = 1.0 }
  bindControls(ctx)
  syncView(ctx)
end

function RackBlendSimpleBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then
    return
  end

  local widgets = ctx.widgets or {}
  local queue = {}
  local mode = Layout.layoutModeForWidth(w, COMPACT_LAYOUT_CUTOFF_W)
  local reference = mode == "compact" and COMPACT_REFERENCE_SIZE or WIDE_REFERENCE_SIZE
  local rects = mode == "compact" and COMPACT_RECTS or WIDE_RECTS
  local scaleX, scaleY = Layout.scaleFactors(w, h, reference)

  Layout.applyScaledRect(queue, widgets.title, rects.title, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.status_label, rects.status_label, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.mode_dropdown, rects.mode_dropdown, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.blendAmount_slider, rects.blendAmount_slider, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.blendModAmount_slider, rects.blendModAmount_slider, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.output_slider, rects.output_slider, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.detail_label, rects.detail_label, scaleX, scaleY)

  if mode == "wide" then
    Layout.setVisibleQueued(queue, widgets.io_label, true)
    Layout.applyScaledRect(queue, widgets.io_label, rects.io_label, scaleX, scaleY)
  else
    Layout.setVisibleQueued(queue, widgets.io_label, false)
    Layout.setBoundsQueued(queue, widgets.io_label, 0, 0, 1, 1)
  end

  Layout.flushWidgetRefreshes(queue)
  anchorDropdown(widgets.mode_dropdown, ctx.root)
end

function RackBlendSimpleBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return RackBlendSimpleBehavior

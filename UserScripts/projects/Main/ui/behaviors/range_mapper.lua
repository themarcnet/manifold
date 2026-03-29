local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local RangeMapperBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/range_mapper/1"
local FALLBACK_MODULE_ID = "range_mapper_inst_1"
local MODE_NAMES = { "Clamp", "Remap" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildRangeDisplay(w, h, ctx.values or {}, viewState or {}, 0xff4ade80)
  end)
end

local function syncView(ctx)
  local minBase, minEffective, minState = ModWidgetSync.resolveValues(pathFor(ctx, "min"), ctx.values.min or 0.0, Ui.readParam)
  local maxBase, maxEffective, maxState = ModWidgetSync.resolveValues(pathFor(ctx, "max"), ctx.values.max or 1.0, Ui.readParam)
  local mode = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "mode"), ctx.values.mode or 0), 0, 1) + 0.5)

  local minValue = Ui.clamp(minBase, 0.0, 1.0)
  local maxValue = Ui.clamp(maxBase, 0.0, 1.0)
  ctx.values.min = minValue
  ctx.values.max = maxValue
  ctx.values.mode = mode

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.min_slider or nil, minValue, Ui.clamp(minEffective, 0.0, 1.0), minState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.max_slider or nil, maxValue, Ui.clamp(maxEffective, 0.0, 1.0), maxState)
  Ui.setOptions(ctx.widgets and ctx.widgets.mode_dropdown or nil, MODE_NAMES, mode + 1)

  local lo = minValue
  local hi = maxValue
  if lo > hi then lo, hi = hi, lo end
  local viewState = Ui.getViewState("__midiSynthRangeMapperViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  %.0f%% -> %.0f%%", MODE_NAMES[mode + 1] or "Clamp", lo * 100.0, hi * 100.0))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Preview: %.2f -> %.2f", tonumber(viewState.lastInput) or 0.0, tonumber(viewState.lastOutput) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.min_slider then
    ctx.widgets.min_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "min"), Ui.clamp(v, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.max_slider then
    ctx.widgets.max_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "max"), Ui.clamp(v, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.mode_dropdown then
    ctx.widgets.mode_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "mode"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 1) + 0.5))
      syncView(ctx)
    end
  end
end

function RangeMapperBehavior.init(ctx)
  ctx.values = { min = 0.0, max = 1.0, mode = 0 }
  bindControls(ctx)
  syncView(ctx)
end

function RangeMapperBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return RangeMapperBehavior

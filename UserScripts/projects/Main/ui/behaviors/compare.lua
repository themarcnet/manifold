local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local CompareBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/compare/1"
local FALLBACK_MODULE_ID = "compare_inst_1"
local DIRECTION_NAMES = { "Rising", "Falling", "Both" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildCompareDisplay(w, h, ctx.values or {}, viewState or {}, 0xfff97316)
  end)
end

local function syncView(ctx)
  local thresholdBase, thresholdEffective, thresholdState = ModWidgetSync.resolveValues(pathFor(ctx, "threshold"), ctx.values.threshold or 0.0, Ui.readParam)
  local hysteresisBase, hysteresisEffective, hysteresisState = ModWidgetSync.resolveValues(pathFor(ctx, "hysteresis"), ctx.values.hysteresis or 0.05, Ui.readParam)
  local directionBase = Ui.readParam(pathFor(ctx, "direction"), ctx.values.direction or 0)

  local threshold = Ui.clamp(thresholdBase, -1.0, 1.0)
  local hysteresis = Ui.clamp(hysteresisBase, 0.0, 0.5)
  local direction = math.floor(Ui.clamp(directionBase, 0, 2) + 0.5)

  ctx.values.threshold = threshold
  ctx.values.hysteresis = hysteresis
  ctx.values.direction = direction

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.threshold_slider or nil, threshold, Ui.clamp(thresholdEffective, -1.0, 1.0), thresholdState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.hysteresis_slider or nil, hysteresis, Ui.clamp(hysteresisEffective, 0.0, 0.5), hysteresisState)
  Ui.setOptions(ctx.widgets and ctx.widgets.direction_dropdown or nil, DIRECTION_NAMES, direction + 1)

  local viewState = Ui.getViewState("__midiSynthCompareViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  Th %+.2f  •  Hy %.2f", DIRECTION_NAMES[direction + 1] or "Rising", threshold, hysteresis))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("In %+.2f  •  Gate %.0f  •  Trig %.0f", tonumber(viewState.inputValue) or 0.0, tonumber(viewState.gateValue) or 0.0, tonumber(viewState.trigValue) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.threshold_slider then
    ctx.widgets.threshold_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "threshold"), Ui.clamp(v, -1.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.hysteresis_slider then
    ctx.widgets.hysteresis_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "hysteresis"), Ui.clamp(v, 0.0, 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.direction_dropdown then
    ctx.widgets.direction_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "direction"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 2) + 0.5))
      syncView(ctx)
    end
  end
end

function CompareBehavior.init(ctx)
  ctx.values = { threshold = 0.0, hysteresis = 0.05, direction = 0 }
  bindControls(ctx)
  syncView(ctx)
end

function CompareBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return CompareBehavior

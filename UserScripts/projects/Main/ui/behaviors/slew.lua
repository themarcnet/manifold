local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local SlewBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/slew/1"
local FALLBACK_MODULE_ID = "slew_inst_1"
local SHAPE_NAMES = { "Linear", "Log", "Exp" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildSlewDisplay(w, h, ctx.values or {}, viewState or {}, 0xff2dd4bf)
  end)
end

local function syncView(ctx)
  local riseBase, riseEffective, riseState = ModWidgetSync.resolveValues(pathFor(ctx, "rise"), ctx.values.rise or 0.0, Ui.readParam)
  local fallBase, fallEffective, fallState = ModWidgetSync.resolveValues(pathFor(ctx, "fall"), ctx.values.fall or 0.0, Ui.readParam)
  local shapeBase = Ui.readParam(pathFor(ctx, "shape"), ctx.values.shape or 1)

  local rise = Ui.clamp(riseBase, 0.0, 2000.0)
  local fall = Ui.clamp(fallBase, 0.0, 2000.0)
  local shape = math.floor(Ui.clamp(shapeBase, 0, 2) + 0.5)

  ctx.values.rise = rise
  ctx.values.fall = fall
  ctx.values.shape = shape

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.rise_slider or nil, rise, Ui.clamp(riseEffective, 0.0, 2000.0), riseState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.fall_slider or nil, fall, Ui.clamp(fallEffective, 0.0, 2000.0), fallState)
  Ui.setOptions(ctx.widgets and ctx.widgets.shape_dropdown or nil, SHAPE_NAMES, shape + 1)

  local viewState = Ui.getViewState("__midiSynthSlewViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  ↑ %.0f ms  •  ↓ %.0f ms", SHAPE_NAMES[shape + 1] or "Linear", rise, fall))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("In %+.2f  •  Out %+.2f", tonumber(viewState.inputValue) or 0.0, tonumber(viewState.outputValue) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.rise_slider then
    ctx.widgets.rise_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "rise"), Ui.clamp(v, 0.0, 2000.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.fall_slider then
    ctx.widgets.fall_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "fall"), Ui.clamp(v, 0.0, 2000.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.shape_dropdown then
    ctx.widgets.shape_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "shape"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 2) + 0.5))
      syncView(ctx)
    end
  end
end

function SlewBehavior.init(ctx)
  ctx.values = { rise = 0.0, fall = 0.0, shape = 1 }
  bindControls(ctx)
  syncView(ctx)
end

function SlewBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return SlewBehavior

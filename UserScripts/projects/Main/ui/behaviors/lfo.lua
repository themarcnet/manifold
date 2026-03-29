local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local LfoBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/lfo/1"
local FALLBACK_MODULE_ID = "lfo_inst_1"
local SHAPE_NAMES = { "Sine", "Triangle", "Saw", "Square", "S&H", "Noise" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildLfoDisplay(w, h, ctx.values or {}, viewState or {}, 0xff38bdf8)
  end)
end

local function syncView(ctx)
  local rateBase, rateEffective, rateState = ModWidgetSync.resolveValues(pathFor(ctx, "rate"), ctx.values.rate or 1.0, Ui.readParam)
  local shapeBase = Ui.readParam(pathFor(ctx, "shape"), ctx.values.shape or 0)
  local depthBase, depthEffective, depthState = ModWidgetSync.resolveValues(pathFor(ctx, "depth"), ctx.values.depth or 1.0, Ui.readParam)
  local phaseBase, phaseEffective, phaseState = ModWidgetSync.resolveValues(pathFor(ctx, "phase"), ctx.values.phase or 0.0, Ui.readParam)
  local retrigBase, retrigEffective, retrigState = ModWidgetSync.resolveValues(pathFor(ctx, "retrig"), ctx.values.retrig or 1, Ui.readParam)

  local rate = Ui.clamp(rateBase, 0.01, 20.0)
  local depth = Ui.clamp(depthBase, 0.0, 1.0)
  local phase = Ui.clamp(phaseBase, 0.0, 360.0)
  local shape = math.floor(Ui.clamp(shapeBase, 0, 5) + 0.5)
  local retrig = math.floor(Ui.clamp(retrigBase, 0, 1) + 0.5)

  ctx.values.rate = rate
  ctx.values.shape = shape
  ctx.values.depth = depth
  ctx.values.phase = phase
  ctx.values.retrig = retrig

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.rate_slider or nil, rate, Ui.clamp(rateEffective, 0.01, 20.0), rateState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.depth_slider or nil, depth, Ui.clamp(depthEffective, 0.0, 1.0), depthState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.phase_slider or nil, phase, Ui.clamp(phaseEffective, 0.0, 360.0), phaseState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.retrig_toggle or nil, retrig, math.floor(Ui.clamp(retrigEffective, 0, 1) + 0.5), retrigState)
  Ui.setOptions(ctx.widgets and ctx.widgets.shape_dropdown or nil, SHAPE_NAMES, shape + 1)

  local viewState = Ui.getViewState("__midiSynthLfoViewState", getModuleId(ctx)) or {}
  local outputs = type(viewState.outputs) == "table" and viewState.outputs or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  %.2f Hz  •  Depth %.0f%%", SHAPE_NAMES[shape + 1] or "Sine", rate, depth * 100.0))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Out %+.2f  •  Uni %.2f  •  Φ %.2f", tonumber(outputs.out) or 0.0, tonumber(outputs.uni) or 0.0, tonumber(viewState.phase) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.rate_slider then
    ctx.widgets.rate_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "rate"), Ui.clamp(v, 0.01, 20.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.depth_slider then
    ctx.widgets.depth_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "depth"), Ui.clamp(v, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.phase_slider then
    ctx.widgets.phase_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "phase"), Ui.clamp(v, 0.0, 360.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.retrig_toggle then
    ctx.widgets.retrig_toggle._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "retrig"), math.floor(Ui.clamp(v, 0, 1) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.shape_dropdown then
    ctx.widgets.shape_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "shape"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 5) + 0.5))
      syncView(ctx)
    end
  end
end

function LfoBehavior.init(ctx)
  ctx.values = { rate = 1.0, shape = 0, depth = 1.0, phase = 0.0, retrig = 1 }
  bindControls(ctx)
  syncView(ctx)
end

function LfoBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return LfoBehavior

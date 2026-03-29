local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local AttenuverterBiasBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/attenuverter_bias/1"
local FALLBACK_MODULE_ID = "attenuverter_bias_inst_1"

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildAttenuverterDisplay(w, h, ctx.values or {}, viewState or {}, 0xff22c55e)
  end)
end

local function syncView(ctx)
  local amountBase, amountEffective, amountState = ModWidgetSync.resolveValues(pathFor(ctx, "amount"), ctx.values.amount or 1.0, Ui.readParam)
  local biasBase, biasEffective, biasState = ModWidgetSync.resolveValues(pathFor(ctx, "bias"), ctx.values.bias or 0.0, Ui.readParam)

  local amount = Ui.clamp(amountBase, -1.0, 1.0)
  local bias = Ui.clamp(biasBase, -1.0, 1.0)
  ctx.values.amount = amount
  ctx.values.bias = bias

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.amount_slider or nil, amount, Ui.clamp(amountEffective, -1.0, 1.0), amountState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.bias_slider or nil, bias, Ui.clamp(biasEffective, -1.0, 1.0), biasState)

  local viewState = Ui.getViewState("__midiSynthAttenuverterBiasViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("In %+.2f  •  Out %+.2f", tonumber(viewState.inputValue) or 0.0, tonumber(viewState.outputValue) or 0.0))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Amt %+.2f  •  Bias %+.2f", amount, bias))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.amount_slider then
    ctx.widgets.amount_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "amount"), Ui.clamp(v, -1.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.bias_slider then
    ctx.widgets.bias_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "bias"), Ui.clamp(v, -1.0, 1.0))
      syncView(ctx)
    end
  end
end

function AttenuverterBiasBehavior.init(ctx)
  ctx.values = { amount = 1.0, bias = 0.0 }
  bindControls(ctx)
  syncView(ctx)
end

function AttenuverterBiasBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return AttenuverterBiasBehavior

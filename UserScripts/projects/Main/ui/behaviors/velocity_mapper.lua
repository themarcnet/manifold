local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local VelocityMapperBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/velocity_mapper/1"
local FALLBACK_MODULE_ID = "velocity_mapper_inst_1"
local CURVE_NAMES = { "Linear", "Soft", "Hard" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildVelocityDisplay(w, h, ctx.values or {}, viewState or {}, 0xff4ade80)
  end)
end

local function syncView(ctx)
  local amountBase, amountEffective, amountState = ModWidgetSync.resolveValues(pathFor(ctx, "amount"), ctx.values.amount or 1.0, Ui.readParam)
  local offsetBase, offsetEffective, offsetState = ModWidgetSync.resolveValues(pathFor(ctx, "offset"), ctx.values.offset or 0.0, Ui.readParam)
  local curve = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "curve"), ctx.values.curve or 0), 0, 2) + 0.5)

  local amount = Ui.clamp(amountBase, 0.0, 1.0)
  local offset = Ui.clamp(offsetBase, -1.0, 1.0)

  ctx.values.amount = amount
  ctx.values.offset = offset
  ctx.values.curve = curve

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.amount_slider or nil, amount, Ui.clamp(amountEffective, 0.0, 1.0), amountState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.offset_slider or nil, offset, Ui.clamp(offsetEffective, -1.0, 1.0), offsetState)
  Ui.setOptions(ctx.widgets and ctx.widgets.curve_dropdown or nil, CURVE_NAMES, curve + 1)

  local viewState = Ui.getViewState("__midiSynthVelocityMapperViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  Amt %.0f%%  •  Off %+.0f%%", CURVE_NAMES[curve + 1] or "Linear", amount * 100.0, offset * 100.0))
  if viewState.inputAmp ~= nil and viewState.outputAmp ~= nil then
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Preview: %.0f%% -> %.0f%%", viewState.inputAmp * 100.0, viewState.outputAmp * 100.0))
  else
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, "Preview: —")
  end
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.amount_slider then
    ctx.widgets.amount_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "amount"), Ui.clamp(v, 0.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.offset_slider then
    ctx.widgets.offset_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "offset"), Ui.clamp(v, -1.0, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.curve_dropdown then
    ctx.widgets.curve_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "curve"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 2) + 0.5))
      syncView(ctx)
    end
  end
end

function VelocityMapperBehavior.init(ctx)
  ctx.values = { amount = 1.0, curve = 0, offset = 0.0 }
  bindControls(ctx)
  syncView(ctx)
end

function VelocityMapperBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return VelocityMapperBehavior

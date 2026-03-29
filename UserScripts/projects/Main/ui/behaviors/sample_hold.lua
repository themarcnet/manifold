local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local SampleHoldBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/sample_hold/1"
local FALLBACK_MODULE_ID = "sample_hold_inst_1"
local MODE_NAMES = { "Sample", "Track", "Step" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildSampleHoldDisplay(w, h, ctx.values or {}, viewState or {}, 0xfff59e0b)
  end)
end

local function syncView(ctx)
  local mode = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "mode"), ctx.values.mode or 0), 0, 2) + 0.5)
  ctx.values.mode = mode
  Ui.setOptions(ctx.widgets and ctx.widgets.mode_dropdown or nil, MODE_NAMES, mode + 1)

  local viewState = Ui.getViewState("__midiSynthSampleHoldViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  Hold %+.2f", MODE_NAMES[mode + 1] or "Sample", tonumber(viewState.outputValue) or 0.0))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("In %+.2f  •  Hold %+.2f", tonumber(viewState.inputValue) or 0.0, tonumber(viewState.outputValue) or 0.0))
  Ui.setText(ctx.widgets and ctx.widgets.inv_label or nil, string.format("Inv %+.2f", tonumber(viewState.invValue) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.mode_dropdown then
    ctx.widgets.mode_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "mode"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 2) + 0.5))
      syncView(ctx)
    end
  end
end

function SampleHoldBehavior.init(ctx)
  ctx.values = { mode = 0 }
  bindControls(ctx)
  syncView(ctx)
end

function SampleHoldBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return SampleHoldBehavior

local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local CvMixBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/cv_mix/1"
local FALLBACK_MODULE_ID = "cv_mix_inst_1"

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildCvMixDisplay(w, h, ctx.values or {}, viewState or {}, 0xffc084fc)
  end)
end

local function syncView(ctx)
  for i = 1, 4 do
    local key = "level_" .. i
    local base, effective, state = ModWidgetSync.resolveValues(pathFor(ctx, key), ctx.values[key] or (i == 1 and 1.0 or 0.0), Ui.readParam)
    local value = Ui.clamp(base, 0.0, 1.0)
    ctx.values[key] = value
    ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets[key .. "_slider"] or nil, value, Ui.clamp(effective, 0.0, 1.0), state)
  end

  local offsetBase, offsetEffective, offsetState = ModWidgetSync.resolveValues(pathFor(ctx, "offset"), ctx.values.offset or 0.0, Ui.readParam)
  local offset = Ui.clamp(offsetBase, -1.0, 1.0)
  ctx.values.offset = offset
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.offset_slider or nil, offset, Ui.clamp(offsetEffective, -1.0, 1.0), offsetState)

  local viewState = Ui.getViewState("__midiSynthCvMixViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("Levels %.0f / %.0f / %.0f / %.0f", (ctx.values.level_1 or 0) * 100, (ctx.values.level_2 or 0) * 100, (ctx.values.level_3 or 0) * 100, (ctx.values.level_4 or 0) * 100))
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Out %+.2f  •  Inv %+.2f", tonumber(viewState.outputValue) or 0.0, tonumber(viewState.invertedValue) or 0.0))
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  for i = 1, 4 do
    local key = "level_" .. i
    local widget = ctx.widgets and ctx.widgets[key .. "_slider"] or nil
    if widget then
      widget._onChange = function(v)
        Ui.writeParam(pathFor(ctx, key), Ui.clamp(v, 0.0, 1.0))
        syncView(ctx)
      end
    end
  end
  if ctx.widgets and ctx.widgets.offset_slider then
    ctx.widgets.offset_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "offset"), Ui.clamp(v, -1.0, 1.0))
      syncView(ctx)
    end
  end
end

function CvMixBehavior.init(ctx)
  ctx.values = { level_1 = 1.0, level_2 = 0.0, level_3 = 0.0, level_4 = 0.0, offset = 0.0 }
  bindControls(ctx)
  syncView(ctx)
end

function CvMixBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return CvMixBehavior

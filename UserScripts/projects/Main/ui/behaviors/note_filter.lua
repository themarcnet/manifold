local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local NoteFilterBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/note_filter/1"
local FALLBACK_MODULE_ID = "note_filter_inst_1"
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local MODE_NAMES = { "Inside", "Outside" }

local function pathFor(ctx, suffix)
  return Ui.pathFor(ctx, TEMPLATE_BASE, FALLBACK_MODULE_ID, suffix)
end

local function getModuleId(ctx)
  return Ui.getInstanceModuleId(ctx, FALLBACK_MODULE_ID)
end

local function noteName(note)
  local n = math.max(0, math.min(127, math.floor((tonumber(note) or 60) + 0.5)))
  local octave = math.floor(n / 12) - 1
  return string.format("%s%d", NOTE_NAMES[(n % 12) + 1] or "C", octave)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildNoteFilterDisplay(w, h, ctx.values or {}, viewState or {}, 0xff22c55e)
  end)
end

local function syncView(ctx)
  local lowBase, lowEffective, lowState = ModWidgetSync.resolveValues(pathFor(ctx, "low"), ctx.values.low or 36, Ui.readParam)
  local highBase, highEffective, highState = ModWidgetSync.resolveValues(pathFor(ctx, "high"), ctx.values.high or 96, Ui.readParam)
  local mode = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "mode"), ctx.values.mode or 0), 0, 1) + 0.5)

  local low = math.floor(Ui.clamp(lowBase, 0, 127) + 0.5)
  local high = math.floor(Ui.clamp(highBase, 0, 127) + 0.5)

  ctx.values.low = low
  ctx.values.high = high
  ctx.values.mode = mode

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.low_slider or nil, low, math.floor(Ui.clamp(lowEffective, 0, 127) + 0.5), lowState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.high_slider or nil, high, math.floor(Ui.clamp(highEffective, 0, 127) + 0.5), highState)
  Ui.setOptions(ctx.widgets and ctx.widgets.mode_dropdown or nil, MODE_NAMES, mode + 1)

  local viewState = Ui.getViewState("__midiSynthNoteFilterViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  %s .. %s", MODE_NAMES[mode + 1] or "Inside", noteName(low), noteName(high)))
  if viewState.inputNote ~= nil then
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Preview: %s -> %s", noteName(viewState.inputNote), viewState.passes and "PASS" or "BLOCK"))
  else
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, "Preview: —")
  end
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.low_slider then
    ctx.widgets.low_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "low"), math.floor(Ui.clamp(v, 0, 127) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.high_slider then
    ctx.widgets.high_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "high"), math.floor(Ui.clamp(v, 0, 127) + 0.5))
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

function NoteFilterBehavior.init(ctx)
  ctx.values = { low = 36, high = 96, mode = 0 }
  bindControls(ctx)
  syncView(ctx)
end

function NoteFilterBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return NoteFilterBehavior

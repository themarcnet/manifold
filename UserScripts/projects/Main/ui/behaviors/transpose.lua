local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local TransposeBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/transpose/1"
local FALLBACK_MODULE_ID = "transpose_inst_1"
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

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

local function signedSemitoneText(value)
  local amount = math.floor(Ui.clamp(value, -24, 24) + (value >= 0 and 0.5 or -0.5))
  if amount > 0 then
    return string.format("+%d st", amount)
  end
  return string.format("%d st", amount)
end

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildPitchDisplay(
      w,
      h,
      tonumber(viewState and viewState.inputNote) or nil,
      tonumber(viewState and viewState.outputNote) or nil,
      0xff4ade80,
      { text = "pitch shift", viewState = viewState }
    )
  end)
end

local function syncView(ctx)
  local semitoneBase, semitoneEffective, semitoneState = ModWidgetSync.resolveValues(pathFor(ctx, "semitones"), ctx.values.semitones or 0.0, Ui.readParam)
  local semitones = math.floor(Ui.clamp(semitoneBase, -24.0, 24.0) + (semitoneBase >= 0 and 0.5 or -0.5))
  local semitonesEffective = math.floor(Ui.clamp(semitoneEffective, -24.0, 24.0) + (semitoneEffective >= 0 and 0.5 or -0.5))
  ctx.values.semitones = semitones

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.semitones_slider or nil, semitones, semitonesEffective, semitoneState)

  local viewState = Ui.getViewState("__midiSynthTransposeViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("Shift %s  •  %+.1f oct", signedSemitoneText(semitones), semitones / 12.0))
  Ui.setText(ctx.widgets and ctx.widgets.range_label or nil, "Range: -24 .. +24 st")
  Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, (viewState.inputNote ~= nil and viewState.outputNote ~= nil) and string.format("Preview: %s -> %s", noteName(viewState.inputNote), noteName(viewState.outputNote)) or "Preview: — -> —")
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.semitones_slider then
    ctx.widgets.semitones_slider._onChange = function(v)
      local value = math.floor(Ui.clamp(v, -24.0, 24.0) + (v >= 0 and 0.5 or -0.5))
      Ui.writeParam(pathFor(ctx, "semitones"), value)
      syncView(ctx)
    end
  end
end

function TransposeBehavior.init(ctx)
  ctx.values = { semitones = 0.0 }
  bindControls(ctx)
  syncView(ctx)
end

function TransposeBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return TransposeBehavior

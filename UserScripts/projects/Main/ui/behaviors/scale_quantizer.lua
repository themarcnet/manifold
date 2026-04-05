local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local ScaleQuantizerBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/scale_quantizer/1"
local FALLBACK_MODULE_ID = "scale_quantizer_inst_1"

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local SCALE_NAMES = { "Major", "Minor", "Dorian", "Mixolydian", "Pentatonic", "Chromatic" }
local DIRECTION_NAMES = { "Nearest", "Up", "Down" }

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
    return Graphs.buildScaleDisplay(
      w,
      h,
      ctx.values.root or 0,
      ctx.values.scale or 1,
      tonumber(viewState and viewState.inputNote) or nil,
      tonumber(viewState and viewState.outputNote) or nil,
      { colour = 0xff4ade80, viewState = viewState }
    )
  end)
end

local function syncView(ctx)
  local root = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "root"), ctx.values.root or 0), 0, 11) + 0.5)
  local scale = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "scale"), ctx.values.scale or 1), 1, 6) + 0.5)
  local direction = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "direction"), ctx.values.direction or 1), 1, 3) + 0.5)

  ctx.values.root = root
  ctx.values.scale = scale
  ctx.values.direction = direction

  Ui.setOptions(ctx.widgets and ctx.widgets.root_dropdown or nil, NOTE_NAMES, root + 1)
  Ui.setOptions(ctx.widgets and ctx.widgets.scale_dropdown or nil, SCALE_NAMES, scale)
  Ui.setOptions(ctx.widgets and ctx.widgets.direction_dropdown or nil, DIRECTION_NAMES, direction)

  local viewState = Ui.getViewState("__midiSynthScaleQuantizerViewState", getModuleId(ctx)) or {}
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s %s  •  %s", NOTE_NAMES[root + 1] or "C", SCALE_NAMES[scale] or "Major", DIRECTION_NAMES[direction] or "Nearest"))
  if viewState.inputNote ~= nil and viewState.outputNote ~= nil then
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, string.format("Preview: %s -> %s", noteName(viewState.inputNote), noteName(viewState.outputNote)))
  else
    Ui.setText(ctx.widgets and ctx.widgets.preview_label or nil, "Preview: — -> —")
  end
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.root_dropdown then
    ctx.widgets.root_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "root"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0, 11) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.scale_dropdown then
    ctx.widgets.scale_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "scale"), math.floor(Ui.clamp(tonumber(v) or 1, 1, 6) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.direction_dropdown then
    ctx.widgets.direction_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "direction"), math.floor(Ui.clamp(tonumber(v) or 1, 1, 3) + 0.5))
      syncView(ctx)
    end
  end
end

function ScaleQuantizerBehavior.init(ctx)
  ctx.values = { root = 0, scale = 1, direction = 1 }
  bindControls(ctx)
  syncView(ctx)
end

function ScaleQuantizerBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return ScaleQuantizerBehavior

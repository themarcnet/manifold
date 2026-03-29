local ModWidgetSync = require("ui.modulation_widget_sync")
local Ui = require("ui.dynamic_module_ui")
local Graphs = require("ui.dynamic_module_graphs")

local ArpBehavior = {}

local SYNC_INTERVAL = 0.08
local TEMPLATE_BASE = "/midi/synth/rack/arp/1"
local FALLBACK_MODULE_ID = "arp_inst_1"
local MODE_NAMES = { "Up", "Down", "Up/Down", "Random" }
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

local function refreshGraph(ctx, viewState)
  Ui.refreshDisplay(ctx.widgets and ctx.widgets.preview_graph or nil, function(w, h)
    return Graphs.buildArpDisplay(w, h, viewState or {}, 0xfff59e0b)
  end)
end

local function syncView(ctx)
  local rateBase, rateEffective, rateState = ModWidgetSync.resolveValues(pathFor(ctx, "rate"), ctx.values.rate or 8.0, Ui.readParam)
  local octaveBase, octaveEffective, octaveState = ModWidgetSync.resolveValues(pathFor(ctx, "octaves"), ctx.values.octaves or 1.0, Ui.readParam)
  local gateBase, gateEffective, gateState = ModWidgetSync.resolveValues(pathFor(ctx, "gate"), ctx.values.gate or 0.6, Ui.readParam)
  local mode = math.floor(Ui.clamp(Ui.readParam(pathFor(ctx, "mode"), ctx.values.mode or 0), 0.0, 3.0) + 0.5)
  local holdBase, holdEffective, holdState = ModWidgetSync.resolveValues(pathFor(ctx, "hold"), ctx.values.hold or 0.0, Ui.readParam)

  local rate = Ui.clamp(rateBase, 0.25, 20.0)
  local octaves = math.floor(Ui.clamp(octaveBase, 1.0, 4.0) + 0.5)
  local gate = Ui.clamp(gateBase, 0.05, 1.0)
  local hold = math.floor(Ui.clamp(holdBase, 0.0, 1.0) + 0.5)

  ctx.values.rate = rate
  ctx.values.mode = mode
  ctx.values.octaves = octaves
  ctx.values.gate = gate
  ctx.values.hold = hold

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.rate_slider or nil, rate, Ui.clamp(rateEffective, 0.25, 20.0), rateState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.octave_slider or nil, octaves, math.floor(Ui.clamp(octaveEffective, 1.0, 4.0) + 0.5), octaveState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.gate_slider or nil, gate * 100.0, Ui.clamp(gateEffective, 0.05, 1.0) * 100.0, gateState)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.hold_toggle or nil, hold, math.floor(Ui.clamp(holdEffective, 0.0, 1.0) + 0.5), holdState)
  Ui.setOptions(ctx.widgets and ctx.widgets.mode_dropdown or nil, MODE_NAMES, mode + 1)

  local viewState = Ui.getViewState("__midiSynthArpViewState", getModuleId(ctx)) or {}
  local heldCount = math.max(0, math.floor(tonumber(viewState.heldCount) or 0))
  local lanes = math.max(0, math.floor(tonumber(viewState.activeLaneCount) or 0))
  local gateOpen = (tonumber(viewState.gate) or 0.0) > 0.5
  Ui.setText(ctx.widgets and ctx.widgets.status_label or nil, string.format("%s  •  Held %d  •  Lanes %d  •  Gate %s", MODE_NAMES[mode + 1] or "Up", heldCount, lanes, gateOpen and "On" or "Off"))
  Ui.setText(ctx.widgets and ctx.widgets.note_label or nil, viewState.currentNote ~= nil and ("Output: " .. noteName(viewState.currentNote)) or "Output: —")
  refreshGraph(ctx, viewState)
end

local function bindControls(ctx)
  if ctx.widgets and ctx.widgets.rate_slider then
    ctx.widgets.rate_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "rate"), Ui.clamp(v, 0.25, 20.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.octave_slider then
    ctx.widgets.octave_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "octaves"), math.floor(Ui.clamp(v, 1.0, 4.0) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.gate_slider then
    ctx.widgets.gate_slider._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "gate"), Ui.clamp((tonumber(v) or 0.0) / 100.0, 0.05, 1.0))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.hold_toggle then
    ctx.widgets.hold_toggle._onChange = function(v)
      Ui.writeParam(pathFor(ctx, "hold"), math.floor(Ui.clamp(v, 0.0, 1.0) + 0.5))
      syncView(ctx)
    end
  end
  if ctx.widgets and ctx.widgets.mode_dropdown then
    ctx.widgets.mode_dropdown._onSelect = function(v)
      Ui.writeParam(pathFor(ctx, "mode"), math.floor(Ui.clamp((tonumber(v) or 1) - 1, 0.0, 3.0) + 0.5))
      syncView(ctx)
    end
  end
end

function ArpBehavior.init(ctx)
  ctx.values = { rate = 8.0, mode = 0, octaves = 1.0, gate = 0.6, hold = 0.0 }
  bindControls(ctx)
  syncView(ctx)
end

function ArpBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncView(ctx)
  end
end

return ArpBehavior

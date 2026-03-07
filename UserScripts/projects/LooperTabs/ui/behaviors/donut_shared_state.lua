local M = {}

M.MAX_LAYERS = 4
M.kSegmentBars = { 0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0 }
M.kSegmentLabels = { "1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16" }
M.kFxEffects = {
  { id = "bypass", label = "Bypass" },
  { id = "chorus", label = "Chorus" },
  { id = "phaser", label = "Phaser" },
  { id = "bitcrusher", label = "Bitcrusher" },
  { id = "waveshaper", label = "Waveshaper" },
  { id = "filter", label = "Filter" },
  { id = "svf", label = "SVF Filter" },
  { id = "reverb", label = "Reverb" },
  { id = "shimmer", label = "Shimmer" },
  { id = "stereodelay", label = "Stereo Delay" },
  { id = "reversedelay", label = "Reverse Delay" },
  { id = "multitap", label = "Multitap" },
  { id = "pitchshift", label = "Pitch Shift" },
  { id = "granulator", label = "Granulator" },
  { id = "ringmod", label = "Ring Mod" },
  { id = "formant", label = "Formant" },
  { id = "eq", label = "EQ" },
  { id = "compressor", label = "Compressor" },
  { id = "limiter", label = "Limiter" },
  { id = "transient", label = "Transient" },
  { id = "widener", label = "Widener" },
}
M.kFxLabels = {}
for i = 1, #M.kFxEffects do
  M.kFxLabels[i] = M.kFxEffects[i].label
end

local selections = {
  vocal = "bypass",
  layers = { "bypass", "bypass", "bypass", "bypass" },
}

function M.clamp(v, lo, hi)
  local n = tonumber(v) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.commandSet(path, value)
  if command then
    command("SET", path, tostring(value))
  end
end

function M.commandTrigger(path)
  if command then
    command("TRIGGER", path)
  end
end

function M.layerPath(layerIndex, suffix)
  return string.format("/core/behavior/layer/%d/%s", layerIndex, suffix)
end

function M.sanitizeSpeed(value)
  local speed = math.abs(tonumber(value) or 1.0)
  if speed < 0.1 then speed = 0.1 end
  if speed > 4.0 then speed = 4.0 end
  return speed
end

function M.wrap01(v)
  while v < 0.0 do v = v + 1.0 end
  while v >= 1.0 do v = v - 1.0 end
  return v
end

function M.readParam(params, path, fallback)
  if type(params) ~= "table" then
    return fallback
  end
  local value = params[path]
  if value == nil then
    return fallback
  end
  return value
end

function M.readBoolParam(params, path, fallback)
  local raw = M.readParam(params, path, fallback and 1 or 0)
  if raw == nil then
    return fallback
  end
  return raw == true or raw == 1
end

function M.normalizeState(state)
  if type(state) ~= "table" then
    return {}
  end

  local params = state.params or {}
  local voices = state.voices or {}
  local normalized = {
    params = params,
    voices = voices,
    tempo = M.readParam(params, "/core/behavior/tempo", 120),
    targetBPM = M.readParam(params, "/core/behavior/targetbpm", 120),
    samplesPerBar = M.readParam(params, "/core/behavior/samplesPerBar", 88200),
    sampleRate = M.readParam(params, "/core/behavior/sampleRate", 44100),
    captureSize = M.readParam(params, "/core/behavior/captureSize", 0),
    isRecording = M.readBoolParam(params, "/core/behavior/recording", false),
    overdubEnabled = M.readBoolParam(params, "/core/behavior/overdub", false),
    recordMode = M.readParam(params, "/core/behavior/mode", "firstLoop"),
    activeLayer = M.readParam(params, "/core/behavior/activeLayer", M.readParam(params, "/core/behavior/layer", 0)),
    forwardArmed = M.readBoolParam(params, "/core/behavior/forwardArmed", false),
    forwardBars = M.readParam(params, "/core/behavior/forwardBars", 0),
    layers = {},
  }

  normalized.activeLayer = tonumber(normalized.activeLayer) or 0

  for i, voice in ipairs(voices) do
    if type(voice) == "table" then
      normalized.layers[i] = {
        index = voice.id or (i - 1),
        length = voice.length or 0,
        position = voice.position or 0,
        speed = voice.speed or 1,
        reversed = voice.reversed or false,
        volume = voice.volume or 1,
        state = voice.state or "empty",
        muted = voice.muted or false,
        bars = voice.bars or 0,
        params = voice.params or {},
      }
    end
  end

  if #normalized.layers == 0 then
    for layerIdx = 0, M.MAX_LAYERS - 1 do
      local volume = tonumber(M.readParam(params, M.layerPath(layerIdx, "volume"), 1.0)) or 1.0
      local muted = M.readBoolParam(params, M.layerPath(layerIdx, "mute"), false)
      local bars = tonumber(M.readParam(params, M.layerPath(layerIdx, "bars"), 0)) or 0
      local length = tonumber(M.readParam(params, M.layerPath(layerIdx, "length"), 0)) or 0
      local posNorm = tonumber(M.readParam(params, M.layerPath(layerIdx, "seek"), 0)) or 0
      local stateName = M.readParam(params, M.layerPath(layerIdx, "state"), nil)
      if type(stateName) ~= "string" or stateName == "" then
        if muted then
          stateName = "muted"
        elseif normalized.isRecording and normalized.activeLayer == layerIdx then
          stateName = "recording"
        else
          stateName = "stopped"
        end
      end

      normalized.layers[layerIdx + 1] = {
        index = layerIdx,
        length = length,
        position = math.floor(posNorm * math.max(1, length)),
        speed = tonumber(M.readParam(params, M.layerPath(layerIdx, "speed"), 1.0)) or 1.0,
        reversed = M.readBoolParam(params, M.layerPath(layerIdx, "reverse"), false),
        volume = volume,
        state = stateName,
        muted = muted,
        bars = bars,
        params = { mute = muted and 1 or 0 },
      }
    end
  end

  return normalized
end

function M.layerStateColour(state)
  local colours = {
    empty = 0xff64748b,
    playing = 0xff34d399,
    recording = 0xffef4444,
    overdubbing = 0xfff59e0b,
    muted = 0xff94a3b8,
    stopped = 0xfffde047,
    paused = 0xffa78bfa,
  }
  return colours[state] or 0xffffffff
end

function M.layerStateName(state)
  local names = {
    empty = "Empty",
    playing = "Playing",
    recording = "Recording",
    overdubbing = "Overdub",
    muted = "Muted",
    stopped = "Stopped",
    paused = "Paused",
  }
  return names[state] or ""
end

function M.segmentRangeForBars(bars)
  local prev = 0
  for i, v in ipairs(M.kSegmentBars) do
    if math.abs(v - bars) < 0.0001 then
      prev = (i > 1) and M.kSegmentBars[i - 1] or 0
      return prev, v, M.kSegmentLabels[i] or tostring(v)
    end
  end
  return 0, bars, tostring(bars)
end

function M.formatBars(bars)
  if bars == nil or bars == 0 then
    return ""
  end
  if bars < 1 then
    if math.abs(bars - 0.0625) < 0.001 then return "1/16 bar" end
    if math.abs(bars - 0.125) < 0.001 then return "1/8 bar" end
    if math.abs(bars - 0.25) < 0.001 then return "1/4 bar" end
    if math.abs(bars - 0.5) < 0.001 then return "1/2 bar" end
    return string.format("%.2f bars", bars)
  end
  local rounded = math.floor(bars + 0.5)
  if rounded == 1 then
    return "1 bar"
  end
  return string.format("%d bars", rounded)
end

function M.effectIdFromIndex(idx)
  idx = math.max(1, math.min(#M.kFxEffects, tonumber(idx) or 1))
  return M.kFxEffects[idx].id
end

function M.effectIndexFromId(effectId)
  for i = 1, #M.kFxEffects do
    if M.kFxEffects[i].id == effectId then
      return i
    end
  end
  return 1
end

function M.effectLabelById(effectId)
  return M.kFxEffects[M.effectIndexFromId(effectId)].label
end

function M.getSelections()
  return selections
end

function M.setVocalEffectByIndex(idx)
  selections.vocal = M.effectIdFromIndex(idx)
  return selections.vocal
end

function M.setLayerEffectByIndex(layerIndex, idx)
  local slot = math.max(1, math.min(M.MAX_LAYERS, (tonumber(layerIndex) or 0) + 1))
  selections.layers[slot] = M.effectIdFromIndex(idx)
  return selections.layers[slot]
end

function M.mappingOptionLabels()
  return {
    "Unmapped",
    "Param X",
    "Param Y",
    "Macro 1",
    "Macro 2",
    "Mix",
  }
end

local function findById(items, id)
  if type(items) ~= "table" or type(id) ~= "string" or id == "" then
    return nil
  end
  for _, item in ipairs(items) do
    if type(item) == "table" and item.id == id then
      return item
    end
  end
  return nil
end

function M.getChildSpec(ctx, id)
  local spec = ctx and ctx.spec or nil
  if type(spec) ~= "table" then
    return nil
  end
  return findById(spec.children, id)
end

function M.getComponentSpec(ctx, id)
  local spec = ctx and ctx.spec or nil
  if type(spec) ~= "table" then
    return nil
  end
  return findById(spec.components, id)
end

function M.getDesignSize(ctx, fallbackW, fallbackH)
  local spec = ctx and ctx.spec or nil
  local designW = type(spec) == "table" and tonumber(spec.w) or nil
  local designH = type(spec) == "table" and tonumber(spec.h) or nil
  if not designW or designW <= 0 then designW = tonumber(fallbackW) or 1 end
  if not designH or designH <= 0 then designH = tonumber(fallbackH) or 1 end
  return designW, designH
end

function M.applySpecRect(widget, nodeSpec, parentW, parentH, designW, designH)
  if not widget or not nodeSpec or not widget.setBounds then
    return
  end
  designW = tonumber(designW) or tonumber(parentW) or 1
  designH = tonumber(designH) or tonumber(parentH) or 1
  parentW = tonumber(parentW) or designW
  parentH = tonumber(parentH) or designH

  local sx = parentW / math.max(1, designW)
  local sy = parentH / math.max(1, designH)
  local x = math.floor(((tonumber(nodeSpec.x) or 0) * sx) + 0.5)
  local y = math.floor(((tonumber(nodeSpec.y) or 0) * sy) + 0.5)
  local w = math.floor(((tonumber(nodeSpec.w) or 0) * sx) + 0.5)
  local h = math.floor(((tonumber(nodeSpec.h) or 0) * sy) + 0.5)
  widget:setBounds(x, y, w, h)
end

function M.setDropdownAbsolutePos(rootWidget, widget)
  if not (rootWidget and rootWidget.node and widget and widget.node and widget.setAbsolutePos and rootWidget.node.getBounds and widget.node.getBounds) then
    return
  end
  local rx, ry = rootWidget.node:getBounds()
  local wx, wy = widget.node:getBounds()
  widget:setAbsolutePos(rx + wx, ry + wy)
end

return M

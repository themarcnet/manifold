local M = {}

M.MAX_LAYERS = 4
M.kModeNames = { "First Loop", "Free Mode", "Traditional" }
M.kModeKeys = { "firstLoop", "freeMode", "traditional" }
M.kSegmentBars = { 0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0 }
M.kSegmentLabels = { "1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16" }

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

function M.sanitizeScrubSpeed(value)
  local speed = math.abs(tonumber(value) or 0.0)
  if speed < 0.0 then speed = 0.0 end
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

function M.modeIndexFromValue(mode)
  if type(mode) == "number" then
    return math.max(0, math.min(2, math.floor(mode + 0.5)))
  end
  if mode == "firstLoop" then return 0 end
  if mode == "freeMode" then return 1 end
  if mode == "traditional" then return 2 end
  return 0
end

function M.modeText(mode)
  local idx = M.modeIndexFromValue(mode)
  return M.kModeNames[idx + 1] or "Mode"
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

function M.normalizeState(state)
  if type(state) ~= "table" then
    return {}
  end

  local params = state.params or {}
  local voices = state.voices or {}
  local normalized = {
    projectionVersion = state.projectionVersion or 0,
    numVoices = state.numVoices or #voices,
    params = params,
    voices = voices,
    tempo = M.readParam(params, "/core/behavior/tempo", 120),
    targetBPM = M.readParam(params, "/core/behavior/targetbpm", 120),
    samplesPerBar = M.readParam(params, "/core/behavior/samplesPerBar", 88200),
    sampleRate = M.readParam(params, "/core/behavior/sampleRate", 44100),
    captureSize = M.readParam(params, "/core/behavior/captureSize", 0),
    masterVolume = M.readParam(params, "/core/behavior/volume", 0.8),
    inputVolume = M.readParam(params, "/core/behavior/inputVolume", 1.0),
    passthroughEnabled = M.readBoolParam(params, "/core/behavior/passthrough", true),
    isRecording = M.readBoolParam(params, "/core/behavior/recording", false),
    overdubEnabled = M.readBoolParam(params, "/core/behavior/overdub", false),
    recordMode = M.readParam(params, "/core/behavior/mode", "firstLoop"),
    link = state.link or {
      enabled = false,
      tempoSync = false,
      startStopSync = false,
      peers = 0,
      playing = false,
      beat = 0,
      phase = 0,
    },
    activeLayer = M.readParam(params, "/core/behavior/activeLayer", M.readParam(params, "/core/behavior/layer", 0)),
    forwardArmed = M.readBoolParam(params, "/core/behavior/forwardArmed", false),
    forwardBars = M.readParam(params, "/core/behavior/forwardBars", 0),
    spectrum = state.spectrum,
    layers = {},
  }

  normalized.recordModeInt = M.modeIndexFromValue(normalized.recordMode)
  if type(normalized.recordMode) == "number" then
    normalized.recordMode = M.kModeKeys[math.max(1, math.min(#M.kModeKeys, normalized.recordModeInt + 1))] or "firstLoop"
  end
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
        numBars = voice.bars or 0,
        bars = voice.bars or 0,
        params = voice.params or {},
      }
    end
  end

  if #normalized.layers == 0 then
    for layerIdx = 0, M.MAX_LAYERS - 1 do
      local speed = tonumber(M.readParam(params, M.layerPath(layerIdx, "speed"), 1.0)) or 1.0
      local reversed = M.readBoolParam(params, M.layerPath(layerIdx, "reverse"), false)
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
        speed = speed,
        reversed = reversed,
        volume = volume,
        state = stateName,
        muted = muted,
        numBars = bars,
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

function M.anyLayerPlaying(state)
  for _, layer in ipairs(state.layers or {}) do
    if layer.state == "playing" then
      return true
    end
  end
  return false
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
  local spec = ctx and ctx.spec or {}
  local designW = tonumber(spec.w) or tonumber(fallbackW) or 1
  local designH = tonumber(spec.h) or tonumber(fallbackH) or 1
  if designW <= 0 then designW = tonumber(fallbackW) or 1 end
  if designH <= 0 then designH = tonumber(fallbackH) or 1 end
  return designW, designH
end

function M.applySpecRect(widget, nodeSpec, parentW, parentH, designW, designH)
  if not widget or not nodeSpec or not widget.setBounds then
    return false
  end

  local x = tonumber(nodeSpec.x) or 0
  local y = tonumber(nodeSpec.y) or 0
  local w = tonumber(nodeSpec.w) or 0
  local h = tonumber(nodeSpec.h) or 0

  local sx = (tonumber(parentW) or designW or 1) / math.max(1, tonumber(designW) or 1)
  local sy = (tonumber(parentH) or designH or 1) / math.max(1, tonumber(designH) or 1)

  widget:setBounds(
    math.floor(x * sx + 0.5),
    math.floor(y * sy + 0.5),
    math.max(1, math.floor(w * sx + 0.5)),
    math.max(1, math.floor(h * sy + 0.5))
  )
  return true
end

return M

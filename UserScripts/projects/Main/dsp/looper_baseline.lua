-- Project-local reusable looper baseline for Main.
--
-- This keeps the core looper behavior explicit and project-visible while
-- letting the project own its base DSP without depending on a hidden system
-- script entry.

local M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local kAllowedBars = {0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0}

function M.attach(ctx)
  local state = {
    activeLayer = 0,
    tempo = 120.0,
    targetBPM = 120.0,
    mode = 0, -- 0=firstLoop, 1=freeMode, 2=traditional
    forwardBars = 0.0,
    forwardArmed = false,
    overdubLengthPolicy = 0, -- 0=legacyRepeat, 1=commitLengthWins
    transport = 0,
    recordingStartSamples = nil,
    recordingLayer = 0,
    layers = {},
  }

  local numLayers = 4
  for i = 1, numLayers do
    local layer = ctx.bundles.LoopLayer.new({ channels = 2 })
    layer:setTempo(state.tempo)
    layer:setMode(state.mode)
    layer:setCaptureSeconds(30.0)
    state.layers[i] = layer
  end

  local function hostGetSampleRate()
    if ctx.host and ctx.host.getSampleRate then
      return ctx.host.getSampleRate()
    end
    return 44100.0
  end

  local function hostGetPlayTimeSamples()
    if ctx.host and ctx.host.getPlayTimeSamples then
      return ctx.host.getPlayTimeSamples()
    end
    return 0.0
  end

  local function hostSetParam(path, value)
    if ctx.host and ctx.host.setParam then
      return ctx.host.setParam(path, value)
    end
    return false
  end

  local function currentLayer()
    local idx0 = clamp(math.floor(state.activeLayer + 0.5), 0, numLayers - 1)
    return state.layers[idx0 + 1], idx0
  end

  local function applyTempo(value)
    local bpm = clamp(value, 20.0, 300.0)
    state.tempo = bpm
    for i = 1, numLayers do
      state.layers[i]:setTempo(bpm)
    end
  end

  local function applyTargetBpm(value)
    state.targetBPM = clamp(value, 20.0, 300.0)
  end

  local function applyMode(value)
    local mode = clamp(math.floor(value + 0.5), 0, 2)
    state.mode = mode
    for i = 1, numLayers do
      state.layers[i]:setMode(mode)
    end
  end

  local function applyOverdubLengthPolicy(value)
    state.overdubLengthPolicy = clamp(math.floor(value + 0.5), 0, 1)
  end

  local function applyTransport(value)
    local mode = clamp(math.floor(value + 0.5), 0, 2)
    state.transport = mode
    for i = 1, numLayers do
      local layer = state.layers[i]
      if mode == 0 then
        layer:stop()
      elseif mode == 1 then
        layer:play()
      else
        layer:pause()
      end
    end
  end

  local function inferTempoAndBars(durationSeconds, targetBpm)
    if durationSeconds <= 0 then
      return nil, nil
    end

    local bestTempo = nil
    local bestBars = nil
    local bestDistance = nil

    local minutes = durationSeconds / 60.0
    for _, bars in ipairs(kAllowedBars) do
      local beats = bars * 4.0
      local tempo = beats / minutes
      local distance = math.abs(tempo - targetBpm)

      if bestDistance == nil or distance < bestDistance or
         (math.abs(distance - bestDistance) <= 0.0001 and bars > bestBars) then
        bestDistance = distance
        bestTempo = tempo
        bestBars = bars
      end
    end

    return bestTempo, bestBars
  end

  local function startRecordingFlow()
    local layer, idx = currentLayer()
    layer:startRecording()
    state.recordingLayer = idx
    state.recordingStartSamples = hostGetPlayTimeSamples()
  end

  local function stopRecordingFlow()
    local layer = state.layers[state.recordingLayer + 1] or currentLayer()
    layer:stopRecording()

    local startSamples = state.recordingStartSamples
    state.recordingStartSamples = nil
    if not startSamples then
      return
    end

    local nowSamples = hostGetPlayTimeSamples()
    local durationSamples = math.max(0.0, nowSamples - startSamples)
    if durationSamples <= 0.0 then
      return
    end

    local commitBars = 0.0

    if state.mode == 0 then
      local sr = math.max(1.0, hostGetSampleRate())
      local durationSeconds = durationSamples / sr
      local inferredTempo, inferredBars = inferTempoAndBars(durationSeconds, state.targetBPM)
      if inferredTempo and inferredBars and inferredTempo > 0.0 and inferredBars > 0.0 then
        hostSetParam("/core/behavior/tempo", inferredTempo)
        commitBars = inferredBars
      end
    else
      local quantized = layer:quantizeToNearestLegal(math.floor(durationSamples + 0.5))
      local spb = layer:getSamplesPerBar()
      if quantized > 0 and spb > 0 then
        commitBars = quantized / spb
      end
    end

    if commitBars > 0.0 then
      hostSetParam("/core/behavior/commit", commitBars)
    end
  end

  local function register(path, opts)
    ctx.params.register(path, opts)
  end

  local function registerBehaviorAliases(suffix, opts)
    register("/core/behavior" .. suffix, opts)
  end

  registerBehaviorAliases("/tempo", { type = "f", min = 20.0, max = 300.0, default = 120.0 })
  registerBehaviorAliases("/targetbpm", { type = "f", min = 20.0, max = 300.0, default = 120.0 })
  registerBehaviorAliases("/mode", { type = "f", min = 0.0, max = 2.0, default = 0.0 })
  registerBehaviorAliases("/layer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerBehaviorAliases("/activeLayer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerBehaviorAliases("/transport", { type = "f", min = 0.0, max = 2.0, default = 0.0 })
  registerBehaviorAliases("/recording", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/rec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/stoprec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/clear", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/overdub", { type = "f", min = 0.0, max = 1.0, default = 1.0 })
  registerBehaviorAliases("/overdubLengthPolicy", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/commit", { type = "f", min = 0.0625, max = 16.0, default = 1.0 })
  registerBehaviorAliases("/forward", { type = "f", min = 0.0625, max = 16.0, default = 1.0 })
  registerBehaviorAliases("/forwardBars", { type = "f", min = 0.0, max = 16.0, default = 0.0 })
  registerBehaviorAliases("/forwardArmed", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/forwardFire", { type = "f", min = 0.0, max = 1.0, default = 0.0 })

  for i = 0, numLayers - 1 do
    local suffix = "/layer/" .. tostring(i)
    registerBehaviorAliases(suffix .. "/volume", { type = "f", min = 0.0, max = 2.0, default = 1.0 })
    registerBehaviorAliases(suffix .. "/mute", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/speed", { type = "f", min = 0.0, max = 4.0, default = 1.0 })
    registerBehaviorAliases(suffix .. "/reverse", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/seek", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(suffix .. "/clear", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  end

  local baseline = {}

  function baseline.applyParam(path, value)
    if path == "/core/behavior/tempo" then
      applyTempo(value)
      return true
    end
    if path == "/core/behavior/targetbpm" then
      applyTargetBpm(value)
      return true
    end
    if path == "/core/behavior/mode" then
      applyMode(value)
      return true
    end
    if path == "/core/behavior/layer" or path == "/core/behavior/activeLayer" then
      state.activeLayer = clamp(math.floor(value + 0.5), 0, numLayers - 1)
      return true
    end

    if path == "/core/behavior/recording" then
      if value > 0.5 then
        startRecordingFlow()
      else
        stopRecordingFlow()
      end
      return true
    end
    if path == "/core/behavior/rec" and value > 0.5 then
      hostSetParam("/core/behavior/recording", 1.0)
      return true
    end
    if path == "/core/behavior/stoprec" and value > 0.5 then
      hostSetParam("/core/behavior/recording", 0.0)
      return true
    end

    if path == "/core/behavior/transport" then
      applyTransport(value)
      return true
    end
    if path == "/core/behavior/play" and value > 0.5 then
      applyTransport(1)
      return true
    end
    if path == "/core/behavior/pause" and value > 0.5 then
      applyTransport(2)
      return true
    end
    if path == "/core/behavior/stop" and value > 0.5 then
      applyTransport(0)
      return true
    end

    if path == "/core/behavior/clear" and value > 0.5 then
      for i = 1, numLayers do
        state.layers[i]:clearLoop()
        state.layers[i]:setMuted(false)
        state.layers[i]:setVolume(1.0)
        state.layers[i]:setSpeed(1.0)
        state.layers[i]:setReversed(false)
      end
      return true
    end

    if path == "/core/behavior/overdub" then
      for i = 1, numLayers do
        state.layers[i]:setOverdub(value > 0.5)
      end
      return true
    end

    if path == "/core/behavior/overdubLengthPolicy" then
      applyOverdubLengthPolicy(value)
      return true
    end

    if path == "/core/behavior/commit" then
      local layer = currentLayer()
      layer:commit(clamp(value, 0.0625, 16.0), state.overdubLengthPolicy)
      state.forwardArmed = false
      state.forwardBars = 0.0
      return true
    end

    if path == "/core/behavior/forward" then
      state.forwardBars = clamp(value, 0.0625, 16.0)
      state.forwardArmed = state.forwardBars > 0.0
      return true
    end

    if path == "/core/behavior/forwardArmed" then
      state.forwardArmed = value > 0.5
      return true
    end

    if path == "/core/behavior/forwardBars" then
      state.forwardBars = math.max(0.0, value)
      return true
    end

    if path == "/core/behavior/forwardFire" then
      if value > 0.5 and state.forwardArmed and state.forwardBars > 0.0 then
        hostSetParam("/core/behavior/commit", state.forwardBars)
        state.forwardArmed = false
        state.forwardBars = 0.0
      end
      return true
    end

    for i = 0, numLayers - 1 do
      local prefix = "/core/behavior/layer/" .. tostring(i)
      local layer = state.layers[i + 1]
      if path == prefix .. "/volume" then layer:setVolume(value) return true end
      if path == prefix .. "/mute" then layer:setMuted(value > 0.5) return true end
      if path == prefix .. "/speed" then layer:setSpeed(value) return true end
      if path == prefix .. "/reverse" then layer:setReversed(value > 0.5) return true end
      if path == prefix .. "/seek" then layer:seek(value) return true end
      if path == prefix .. "/play" and value > 0.5 then layer:play() return true end
      if path == prefix .. "/pause" and value > 0.5 then layer:pause() return true end
      if path == prefix .. "/stop" and value > 0.5 then layer:stop() return true end
      if path == prefix .. "/clear" and value > 0.5 then
        layer:clearLoop()
        layer:setMuted(false)
        layer:setVolume(1.0)
        layer:setSpeed(1.0)
        layer:setReversed(false)
        return true
      end
    end

    return false
  end

  baseline.state = state
  baseline.layers = state.layers
  baseline.numLayers = numLayers
  return baseline
end

return M

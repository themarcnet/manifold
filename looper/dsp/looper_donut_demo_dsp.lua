-- looper_donut_demo_dsp.lua
-- Minimal alternate looper behavior script proving runtime decoupling:
-- - Different defaults from canonical looper script
-- - Round-robin active layer after each recording commit
-- - Shared reverb effect node in the graph

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function boolToFloat(v)
  return v and 1.0 or 0.0
end

function buildPlugin(ctx)
  local numLayers = 4

  local state = {
    tempo = 96.0,
    activeLayer = 0,
    recording = false,
    recordingLayer = 0,
    recordingStartSamples = nil,
    transport = 0, -- 0=stop, 1=play, 2=pause
    defaultCommitBars = 2.0,
    layers = {},
  }

  local input = ctx.primitives.PassthroughNode.new(2)
  local inputMonitor = ctx.primitives.GainNode.new(2)
  inputMonitor:setGain(0.0) -- off by default; UI enables while donut view is active

  local reverb = ctx.primitives.ReverbNode.new()
  reverb:setRoomSize(0.65)
  reverb:setDamping(0.35)
  reverb:setWetLevel(0.35)
  reverb:setDryLevel(0.70)
  reverb:setWidth(0.85)

  -- Live input through reverb as part of this demo behavior.
  -- Routed through a dedicated gain so input-FX can be disabled on UI switch
  -- while keeping donut loop playback persistent.
  ctx.graph.connect(input, inputMonitor)
  ctx.graph.connect(inputMonitor, reverb)

  for i = 1, numLayers do
    local layer = ctx.bundles.LoopLayer.new({ channels = 2 })
    layer:setTempo(state.tempo)
    layer:setCaptureSeconds(20.0)
    layer:setVolume(0.85)

    -- Route each layer into shared reverb bus.
    ctx.graph.connect(layer, reverb)

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

  local function register(path, opts)
    ctx.params.register(path, opts)
  end

  local function registerBehaviorAliases(suffix, opts)
    -- Demo script intentionally uses canonical-only registration.
    register("/core/behavior" .. suffix, opts)
  end

  local function normalizePath(path)
    return path
  end

  local function currentLayer()
    local idx0 = clamp(math.floor(state.activeLayer + 0.5), 0, numLayers - 1)
    return state.layers[idx0 + 1], idx0
  end

  local function applyTempo(v)
    local bpm = clamp(v, 40.0, 220.0)
    state.tempo = bpm
    for i = 1, numLayers do
      state.layers[i]:setTempo(bpm)
    end
  end

  local function applyTransport(v)
    local mode = clamp(math.floor(v + 0.5), 0, 2)
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

  local function computeCommitBarsFromDuration(layer, durationSamples)
    local spb = layer:getSamplesPerBar()
    if spb > 0.0 then
      local quantized = layer:quantizeToNearestLegal(math.floor(durationSamples + 0.5))
      if quantized > 0 then
        local bars = quantized / spb
        return clamp(bars, 0.0625, 8.0)
      end
    end

    local sr = math.max(1.0, hostGetSampleRate())
    local durationSec = durationSamples / sr
    local roughBars = (durationSec * state.tempo) / 60.0 / 4.0
    return clamp(roughBars, 0.0625, 8.0)
  end

  local function startRecordingFlow()
    if state.recording then
      return
    end

    local layer, idx = currentLayer()
    state.recording = true
    state.recordingLayer = idx
    state.recordingStartSamples = hostGetPlayTimeSamples()

    layer:startRecording()
  end

  local function stopRecordingFlow()
    if not state.recording then
      return
    end

    local idx = state.recordingLayer
    local layer = state.layers[idx + 1] or state.layers[1]

    layer:stopRecording()
    state.recording = false

    local bars = state.defaultCommitBars
    if state.recordingStartSamples ~= nil then
      local duration = math.max(0.0, hostGetPlayTimeSamples() - state.recordingStartSamples)
      if duration > 0.0 then
        bars = computeCommitBarsFromDuration(layer, duration)
      end
    end
    state.recordingStartSamples = nil

    -- Different default from canonical script:
    -- stop-record auto-commits and advances active layer in round-robin.
    -- Route commit through host param path so projection/state stays coherent.
    if not hostSetParam("/core/behavior/commit", bars) then
      layer:commit(bars)
      layer:play()
    end

    local nextIdx = (idx + 1) % numLayers
    state.activeLayer = nextIdx
    hostSetParam("/core/behavior/activeLayer", nextIdx)
  end

  registerBehaviorAliases("/tempo", { type = "f", min = 40.0, max = 220.0, default = state.tempo })
  registerBehaviorAliases("/layer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerBehaviorAliases("/activeLayer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerBehaviorAliases("/recording", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/rec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/stoprec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerBehaviorAliases("/transport", { type = "f", min = 0.0, max = 2.0, default = 0.0 })
  registerBehaviorAliases("/commit", { type = "f", min = 0.0625, max = 8.0, default = state.defaultCommitBars })

  -- Input monitor routing for this slot only.
  -- 1.0 = input into donut FX chain, 0.0 = no live input into donut FX.
  registerBehaviorAliases("/input/monitor", { type = "f", min = 0.0, max = 1.0, default = 0.0 })

  registerBehaviorAliases("/fx/reverb/wet", { type = "f", min = 0.0, max = 1.0, default = 0.35 })
  registerBehaviorAliases("/fx/reverb/room", { type = "f", min = 0.0, max = 1.0, default = 0.65 })
  registerBehaviorAliases("/fx/reverb/damping", { type = "f", min = 0.0, max = 1.0, default = 0.35 })
  registerBehaviorAliases("/fx/reverb/width", { type = "f", min = 0.0, max = 1.0, default = 0.85 })
  registerBehaviorAliases("/fx/reverb/dry", { type = "f", min = 0.0, max = 1.0, default = 0.70 })

  for i = 0, numLayers - 1 do
    local prefix = "/layer/" .. tostring(i)
    registerBehaviorAliases(prefix .. "/volume", { type = "f", min = 0.0, max = 2.0, default = 0.85 })
    registerBehaviorAliases(prefix .. "/speed", { type = "f", min = 0.0, max = 4.0, default = 1.0 })
    registerBehaviorAliases(prefix .. "/reverse", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/mute", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/seek", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerBehaviorAliases(prefix .. "/clear", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  end

  return {
    onParamChange = function(path, value)
      local canonical = normalizePath(path)
      if canonical ~= path then
        hostSetParam(canonical, value)
        return
      end
      path = canonical

      if path == "/core/behavior/tempo" then
        applyTempo(value)
        return
      end

      if path == "/core/behavior/layer" or path == "/core/behavior/activeLayer" then
        state.activeLayer = clamp(math.floor(value + 0.5), 0, numLayers - 1)
        return
      end

      if path == "/core/behavior/recording" then
        if value > 0.5 then
          startRecordingFlow()
        else
          stopRecordingFlow()
        end
        return
      end

      if path == "/core/behavior/rec" and value > 0.5 then
        hostSetParam("/core/behavior/recording", 1.0)
        return
      end

      if path == "/core/behavior/stoprec" and value > 0.5 then
        hostSetParam("/core/behavior/recording", 0.0)
        return
      end

      if path == "/core/behavior/transport" then
        applyTransport(value)
        return
      end

      if path == "/core/behavior/play" and value > 0.5 then
        applyTransport(1)
        return
      end

      if path == "/core/behavior/pause" and value > 0.5 then
        applyTransport(2)
        return
      end

      if path == "/core/behavior/stop" and value > 0.5 then
        applyTransport(0)
        return
      end

      if path == "/core/behavior/commit" then
        local layer = currentLayer()
        local bars = clamp(value, 0.0625, 8.0)
        local ok = layer:commit(bars)
        if ok ~= false then
          layer:play()
        end
        return
      end

      if path == "/core/behavior/input/monitor" then
        inputMonitor:setGain(clamp(value, 0.0, 1.0))
        return
      end

      if path == "/core/behavior/fx/reverb/wet" then reverb:setWetLevel(clamp(value, 0.0, 1.0)) return end
      if path == "/core/behavior/fx/reverb/room" then reverb:setRoomSize(clamp(value, 0.0, 1.0)) return end
      if path == "/core/behavior/fx/reverb/damping" then reverb:setDamping(clamp(value, 0.0, 1.0)) return end
      if path == "/core/behavior/fx/reverb/width" then reverb:setWidth(clamp(value, 0.0, 1.0)) return end
      if path == "/core/behavior/fx/reverb/dry" then reverb:setDryLevel(clamp(value, 0.0, 1.0)) return end

      for i = 0, numLayers - 1 do
        local prefix = "/core/behavior/layer/" .. tostring(i)
        local layer = state.layers[i + 1]

        if path == prefix .. "/volume" then layer:setVolume(value) return end
        if path == prefix .. "/speed" then layer:setSpeed(clamp(value, 0.0, 4.0)) return end
        if path == prefix .. "/reverse" then layer:setReversed(value > 0.5) return end
        if path == prefix .. "/mute" then layer:setMuted(value > 0.5) return end
        if path == prefix .. "/seek" then layer:seek(clamp(value, 0.0, 1.0)) return end
        if path == prefix .. "/play" and value > 0.5 then layer:play() return end
        if path == prefix .. "/pause" and value > 0.5 then layer:pause() return end
        if path == prefix .. "/stop" and value > 0.5 then layer:stop() return end
        if path == prefix .. "/clear" and value > 0.5 then layer:clearLoop() return end
      end
    end,
  }
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function buildPlugin(ctx)
  local state = {
    activeLayer = 0,
    tempo = 120.0,
    mode = 3,
    forwardBars = 0.0,
    forwardArmed = false,
    transport = 0,
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

  local function applyMode(value)
    local mode = clamp(math.floor(value + 0.5), 0, 3)
    state.mode = mode
    for i = 1, numLayers do
      state.layers[i]:setMode(mode)
    end
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

  local function register(path, opts)
    ctx.params.register(path, opts)
  end

  local function registerPair(suffix, opts)
    register("/dsp/looper" .. suffix, opts)
    register("/looper" .. suffix, opts)
  end

  local function normalizePath(path)
    if string.sub(path, 1, 11) == "/dsp/looper" then
      return path
    end
    if string.sub(path, 1, 7) == "/looper" then
      return "/dsp/looper" .. string.sub(path, 8)
    end
    return path
  end

  registerPair("/tempo", { type = "f", min = 20.0, max = 300.0, default = 120.0 })
  registerPair("/targetbpm", { type = "f", min = 20.0, max = 300.0, default = 120.0 })
  registerPair("/mode", { type = "f", min = 0.0, max = 3.0, default = 3.0 })
  registerPair("/layer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerPair("/activeLayer", { type = "f", min = 0.0, max = numLayers - 1, default = 0.0 })
  registerPair("/transport", { type = "f", min = 0.0, max = 2.0, default = 0.0 })
  registerPair("/recording", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/rec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/stoprec", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/clear", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/overdub", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/commit", { type = "f", min = 0.25, max = 16.0, default = 1.0 })
  registerPair("/forward", { type = "f", min = 0.25, max = 16.0, default = 1.0 })
  registerPair("/forwardBars", { type = "f", min = 0.0, max = 16.0, default = 0.0 })
  registerPair("/forwardArmed", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  registerPair("/forwardFire", { type = "f", min = 0.0, max = 1.0, default = 0.0 })

  for i = 0, numLayers - 1 do
    local suffix = "/layer/" .. tostring(i)
    registerPair(suffix .. "/volume", { type = "f", min = 0.0, max = 2.0, default = 1.0 })
    registerPair(suffix .. "/mute", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/speed", { type = "f", min = 0.1, max = 4.0, default = 1.0 })
    registerPair(suffix .. "/reverse", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/seek", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/play", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/pause", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/stop", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
    registerPair(suffix .. "/clear", { type = "f", min = 0.0, max = 1.0, default = 0.0 })
  end

  return {
    onParamChange = function(path, value)
      path = normalizePath(path)
      if path == "/dsp/looper/tempo" then
        applyTempo(value)
        return
      end
      if path == "/dsp/looper/targetbpm" then
        applyTempo(value)
        return
      end
      if path == "/dsp/looper/mode" then
        applyMode(value)
        return
      end
      if path == "/dsp/looper/layer" then
        state.activeLayer = clamp(math.floor(value + 0.5), 0, numLayers - 1)
        return
      end
      if path == "/dsp/looper/activeLayer" then
        state.activeLayer = clamp(math.floor(value + 0.5), 0, numLayers - 1)
        return
      end
      if path == "/dsp/looper/rec" then
        if value > 0.5 then
          local layer = currentLayer()
          layer:startRecording()
        end
        return
      end
      if path == "/dsp/looper/stoprec" then
        if value > 0.5 then
          local layer = currentLayer()
          layer:stopRecording()
        end
        return
      end
      if path == "/dsp/looper/transport" then
        applyTransport(value)
        return
      end
      if path == "/dsp/looper/play" then
        if value > 0.5 then
          applyTransport(1)
        end
        return
      end
      if path == "/dsp/looper/pause" then
        if value > 0.5 then
          applyTransport(2)
        end
        return
      end
      if path == "/dsp/looper/stop" then
        if value > 0.5 then
          applyTransport(0)
        end
        return
      end
      if path == "/dsp/looper/recording" then
        local layer = currentLayer()
        if value > 0.5 then layer:startRecording() else layer:stopRecording() end
        return
      end
      if path == "/dsp/looper/clear" then
        if value > 0.5 then
          for i = 1, numLayers do
            state.layers[i]:clearLoop()
          end
        end
        return
      end
      if path == "/dsp/looper/overdub" then
        local layer = currentLayer()
        layer:setOverdub(value > 0.5)
        return
      end
      if path == "/dsp/looper/commit" then
        local layer = currentLayer()
        layer:commit(clamp(value, 0.25, 16.0))
        return
      end
      if path == "/dsp/looper/forward" then
        state.forwardBars = clamp(value, 0.25, 16.0)
        state.forwardArmed = true
        return
      end
      if path == "/dsp/looper/forwardFire" then
        if value > 0.5 and state.forwardArmed then
          local layer = currentLayer()
          layer:commit(state.forwardBars)
          state.forwardArmed = false
        end
        return
      end

      for i = 0, numLayers - 1 do
        local prefix = "/dsp/looper/layer/" .. tostring(i)
        local layer = state.layers[i + 1]
        if path == prefix .. "/volume" then layer:setVolume(value) return end
        if path == prefix .. "/mute" then layer:setMuted(value > 0.5) return end
        if path == prefix .. "/speed" then layer:setSpeed(value) return end
        if path == prefix .. "/reverse" then layer:setReversed(value > 0.5) return end
        if path == prefix .. "/seek" then layer:seek(value) return end
        if path == prefix .. "/play" and value > 0.5 then layer:play() return end
        if path == prefix .. "/pause" and value > 0.5 then layer:pause() return end
        if path == prefix .. "/stop" and value > 0.5 then layer:stop() return end
        if path == prefix .. "/clear" and value > 0.5 then layer:clearLoop() return end
      end
    end,
  }
end

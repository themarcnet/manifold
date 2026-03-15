local Shared = require("behaviors.looper_shared_state")

local M = {}

M.subscriptionPatterns = {
  "/core/behavior/layer",
  "/core/behavior/layer/${layerIndex}/speed",
  "/core/behavior/layer/${layerIndex}/volume",
  "/core/behavior/layer/${layerIndex}/mute",
  "/core/behavior/layer/${layerIndex}/reverse",
  "/core/behavior/layer/${layerIndex}/length",
  "/core/behavior/layer/${layerIndex}/position",
  "/core/behavior/layer/${layerIndex}/bars",
  "/core/behavior/layer/${layerIndex}/state",
}

local function selectLayer(layerIdx)
  Shared.commandSet("/core/behavior/layer", layerIdx)
end

function M.init(ctx)
  local widgets = ctx.widgets or {}
  local layerIdx = tonumber(ctx.instanceProps and ctx.instanceProps.layerIndex) or 0
  ctx._layerIndex = layerIdx
  ctx._frameCounter = 0
  ctx._scrub = {
    preScrubSpeed = 1.0,
    preScrubReversed = false,
    scrubEndFrame = 0,
  }
  ctx._subscriptions = {}

  for _, pattern in ipairs(M.subscriptionPatterns) do
    local path = pattern:gsub("${layerIndex}", tostring(layerIdx))
    ctx._subscriptions[path] = true
  end

  if widgets.label then
    widgets.label:setText("L" .. tostring(layerIdx))
  end

  if widgets.waveform and widgets.waveform.setLayerIndex then
    widgets.waveform:setLayerIndex(layerIdx)
    if widgets.waveform.node and widgets.waveform.node.setInterceptsMouse then
      widgets.waveform.node:setInterceptsMouse(true, false)
    end
    if widgets.waveform.node and widgets.waveform.node.setOnMouseDown then
      local existingScrubStart = widgets.waveform._onScrubStart
      widgets.waveform.node:setOnMouseDown(function(mx, my)
        selectLayer(layerIdx)
        if widgets.waveform._scrubbing then
          local w = widgets.waveform.node:getWidth()
          if w > 4 then
            local pos = math.max(0, math.min(1, (mx - 2) / (w - 4)))
            widgets.waveform._lastScrubPos = pos
            if widgets.waveform._onScrubSnap then
              widgets.waveform._onScrubSnap(pos, 0)
            end
          end
          return
        end

        widgets.waveform._scrubbing = true
        widgets.waveform:_syncRetained()
        widgets.waveform.node:repaint()
        if existingScrubStart then
          existingScrubStart()
        end
        local w = widgets.waveform.node:getWidth()
        if w > 4 then
          local pos = math.max(0, math.min(1, (mx - 2) / (w - 4)))
          widgets.waveform._lastScrubPos = pos
          if widgets.waveform._onScrubSnap then
            widgets.waveform._onScrubSnap(pos, 0)
          end
        end
      end)
    end
  end

  if widgets.speed then
    widgets.speed._onChange = function(v)
      selectLayer(layerIdx)
      local absSpeed = Shared.sanitizeSpeed(v)
      local rev = v < 0
      Shared.commandSet(Shared.layerPath(layerIdx, "speed"), absSpeed)
      Shared.commandSet(Shared.layerPath(layerIdx, "reverse"), rev and 1 or 0)
    end
  end

  if widgets.vol then
    widgets.vol._onChange = function(v)
      selectLayer(layerIdx)
      Shared.commandSet(Shared.layerPath(layerIdx, "volume"), v)
    end
  end

  if widgets.mute then
    widgets.mute._onClick = function()
      selectLayer(layerIdx)
      local state = ctx._state or {}
      local layerData = state.layers and state.layers[layerIdx + 1] or {}
      local isMuted = layerData.muted or (layerData.params and layerData.params.mute and layerData.params.mute > 0.5)
      Shared.commandSet(Shared.layerPath(layerIdx, "mute"), isMuted and 0 or 1)
    end
  end

  if widgets.play then
    widgets.play._onClick = function()
      selectLayer(layerIdx)
      local state = ctx._state or {}
      local layerData = state.layers and state.layers[layerIdx + 1] or {}
      if layerData.state == "playing" then
        Shared.commandTrigger(Shared.layerPath(layerIdx, "pause"))
      else
        Shared.commandTrigger(Shared.layerPath(layerIdx, "play"))
      end
    end
  end

  if widgets.clear then
    widgets.clear._onClick = function()
      selectLayer(layerIdx)
      Shared.commandTrigger(Shared.layerPath(layerIdx, "clear"))
    end
  end

  if ctx.root and ctx.root.node then
    ctx.root.node:setOnClick(function()
      selectLayer(layerIdx)
    end)
  end

  if widgets.waveform then
    widgets.waveform._onScrubStart = function()
      selectLayer(layerIdx)
      local scrub = ctx._scrub
      local framesSinceLast = (ctx._frameCounter or 0) - (scrub.scrubEndFrame or -10)
      if framesSinceLast < 3 or scrub._active then return end
      scrub._active = true

      local state = ctx._state or {}
      local layerData = state.layers and state.layers[layerIdx + 1] or {}
      local length = layerData.length or 0
      local knobValue = widgets.speed and widgets.speed:getValue() or 1.0
      scrub.preScrubSpeed = math.abs(knobValue)
      scrub.preScrubReversed = knobValue < 0
      scrub.expectedSpeed = scrub.preScrubSpeed
      scrub.expectedReversed = scrub.preScrubReversed
      scrub.cursorPos = length > 0 and Shared.wrap01((layerData.position or 0) / math.max(1, length)) or 0.0
      scrub.lastPinnedPos = nil
      scrub.lastMotionFrame = ctx._frameCounter or 0
      scrub.smoothedSignedSpeed = 0.0
      scrub.lastSpeedSent = nil
      scrub.lastReverseSent = nil

      Shared.commandSet(Shared.layerPath(layerIdx, "speed"), 0.0)
      scrub.lastSpeedSent = 0.0
    end

    widgets.waveform._onScrubSnap = function(pos, delta)
      local scrub = ctx._scrub
      local state = ctx._state or {}
      local layerData = state.layers and state.layers[layerIdx + 1] or {}
      local length = layerData.length or 0
      if length <= 0 then return end

      local p = math.max(0.0, math.min(1.0, pos))
      local prevCursor = scrub.cursorPos or p
      local deltaNorm = p - prevCursor
      scrub.cursorPos = p

      if scrub.lastPinnedPos == nil or math.abs(p - scrub.lastPinnedPos) > 0.0005 then
        Shared.commandSet(Shared.layerPath(layerIdx, "seek"), p)
        scrub.lastPinnedPos = p
      end

      if math.abs(deltaNorm) < 0.0006 then
        return
      end

      scrub.lastMotionFrame = ctx._frameCounter or 0
      local sr = state.sampleRate or 44100
      local samplesPerFrame = math.max(1.0, sr / 70.0)
      local targetSignedSpeed = (deltaNorm * length) / samplesPerFrame
      local prev = scrub.smoothedSignedSpeed or 0.0
      local signedSpeed = prev * 0.6 + targetSignedSpeed * 0.4
      scrub.smoothedSignedSpeed = signedSpeed

      local absSpeed = Shared.sanitizeScrubSpeed(signedSpeed)
      local rev = signedSpeed < 0.0

      if scrub.lastSpeedSent == nil or math.abs(absSpeed - scrub.lastSpeedSent) > 0.01 then
        Shared.commandSet(Shared.layerPath(layerIdx, "speed"), absSpeed)
        scrub.lastSpeedSent = absSpeed
      end
      if scrub.lastReverseSent == nil or rev ~= scrub.lastReverseSent then
        Shared.commandSet(Shared.layerPath(layerIdx, "reverse"), rev and 1 or 0)
        scrub.lastReverseSent = rev
      end
    end

    widgets.waveform._onScrubEnd = function()
      local scrub = ctx._scrub
      if scrub.cursorPos ~= nil then
        Shared.commandSet(Shared.layerPath(layerIdx, "seek"), scrub.cursorPos)
      end
      Shared.commandSet(Shared.layerPath(layerIdx, "speed"), scrub.preScrubSpeed)
      Shared.commandSet(Shared.layerPath(layerIdx, "reverse"), scrub.preScrubReversed and 1 or 0)

      scrub._active = false
      scrub.scrubEndFrame = ctx._frameCounter or 0
      scrub.cursorPos = nil
      scrub.lastPinnedPos = nil
      scrub.lastMotionFrame = nil
      scrub.smoothedSignedSpeed = nil
      scrub.lastSpeedSent = nil
      scrub.lastReverseSent = nil
    end
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local ids = {
    "label",
    "state",
    "bars",
    "waveform",
    "vol",
    "speed",
    "mute",
    "clear",
    "play",
  }

  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end
end

local function isLayerPositionPath(layerIdx, path)
  local suffix = "/layer/" .. tostring(layerIdx) .. "/position"
  return path == ("/core/behavior" .. suffix)
      or path == ("/manifold" .. suffix)
      or path == ("/dsp/manifold" .. suffix)
end

local function readRawLayerPosition(rawState, layerIdx)
  if type(rawState) ~= "table" then
    return 0, 0
  end

  local voices = rawState.voices
  local voice = type(voices) == "table" and voices[layerIdx + 1] or nil
  if type(voice) == "table" then
    return tonumber(voice.position) or 0, tonumber(voice.length) or 0
  end

  local params = rawState.params
  if type(params) == "table" then
    local length = tonumber(params[Shared.layerPath(layerIdx, "length")]) or 0
    local positionNorm = tonumber(params[Shared.layerPath(layerIdx, "position")]) or 0
    return positionNorm * math.max(1, length), length
  end

  return 0, 0
end

local function applyPositionOnlyUpdate(ctx, rawState)
  local widgets = ctx.widgets or {}
  local layerIdx = ctx._layerIndex or 0
  local position, length = readRawLayerPosition(rawState, layerIdx)

  if widgets.waveform then
    if length > 0 then
      widgets.waveform:setPlayheadPos(position / length)
    else
      widgets.waveform:setPlayheadPos(-1)
    end
  end

  local state = ctx._state
  if type(state) == "table" then
    state.layers = state.layers or {}
    state.layers[layerIdx + 1] = state.layers[layerIdx + 1] or {}
    state.layers[layerIdx + 1].position = position
    state.layers[layerIdx + 1].length = length
  end
end

function M.update(ctx, rawState, changedPaths)
  if type(changedPaths) == "table" then
    local subscriptions = ctx._subscriptions or {}
    local hasRelevantChange = false
    local onlyPositionChanges = true
    local layerIdx = ctx._layerIndex or 0

    for _, path in ipairs(changedPaths) do
      if subscriptions[path] then
        hasRelevantChange = true
        if not isLayerPositionPath(layerIdx, path) then
          onlyPositionChanges = false
        end
      end
    end

    if not hasRelevantChange then
      return
    end

    if onlyPositionChanges then
      ctx._frameCounter = (ctx._frameCounter or 0) + 1
      applyPositionOnlyUpdate(ctx, rawState)
      return
    end
  end

  local widgets = ctx.widgets or {}
  local layerIdx = ctx._layerIndex or 0
  local state = Shared.normalizeState(rawState)
  ctx._state = state
  ctx._frameCounter = (ctx._frameCounter or 0) + 1

  local layerData = state.layers and state.layers[layerIdx + 1] or {}
  local isActive = (state.activeLayer or 0) == layerIdx
  local stateName = layerData.state or "empty"

  if ctx.root then
    if isActive then
      ctx.root:setStyle({ bg = 0xff25405f, border = 0xff7dd3fc, borderWidth = 2 })
    else
      ctx.root:setStyle({ bg = 0xff1b2636, border = 0xff334155, borderWidth = 1 })
    end
  end

  if widgets.label then widgets.label:setColour(isActive and 0xff7dd3fc or 0xff94a3b8) end
  if widgets.state then
    widgets.state:setText(Shared.layerStateName(stateName))
    widgets.state:setColour(Shared.layerStateColour(stateName))
  end
  if widgets.bars then
    if layerData.bars and layerData.bars > 0 then
      widgets.bars:setText(Shared.formatBars(layerData.bars))
    else
      widgets.bars:setText("")
    end
  end

  if widgets.waveform then
    if layerData.length and layerData.length > 0 then
      widgets.waveform:setPlayheadPos((layerData.position or 0) / layerData.length)
      widgets.waveform:setColour(Shared.layerStateColour(stateName))
    else
      widgets.waveform:setPlayheadPos(-1)
    end
  end

  local scrub = ctx._scrub or {}
  if widgets.waveform and widgets.waveform._scrubbing and scrub then
    local pinned = scrub.cursorPos
    if pinned ~= nil then
      local lastPinned = scrub.lastPinnedPos
      if lastPinned == nil or math.abs(pinned - lastPinned) > 0.0002 then
        Shared.commandSet(Shared.layerPath(layerIdx, "seek"), pinned)
        scrub.lastPinnedPos = pinned
      end
    end

    local lastMotion = scrub.lastMotionFrame or ctx._frameCounter
    if (ctx._frameCounter - lastMotion) >= 1 then
      local lastSpeed = scrub.lastSpeedSent
      if lastSpeed == nil or math.abs(lastSpeed) > 0.0001 then
        Shared.commandSet(Shared.layerPath(layerIdx, "speed"), 0.0)
        scrub.lastSpeedSent = 0.0
      end
    end
  end

  if widgets.vol then widgets.vol:setValue(layerData.volume or 1.0) end

  local speedKnobFrozen = false
  if widgets.waveform and widgets.waveform._scrubbing then
    speedKnobFrozen = true
  elseif scrub and scrub._active == false and scrub.expectedSpeed then
    local actualSpeed = layerData.speed or 1.0
    local actualReversed = layerData.reversed or false
    local speedMatch = math.abs(actualSpeed - scrub.expectedSpeed) < 0.01
    local revMatch = (actualReversed == scrub.expectedReversed)
    if not (speedMatch and revMatch) then
      speedKnobFrozen = true
      local framesSinceEnd = (ctx._frameCounter or 0) - (scrub.scrubEndFrame or 0)
      if framesSinceEnd > 60 then
        scrub.expectedSpeed = nil
        scrub.expectedReversed = nil
        speedKnobFrozen = false
      end
    else
      scrub.expectedSpeed = nil
      scrub.expectedReversed = nil
    end
  end

  if widgets.speed and not speedKnobFrozen then
    local speed = layerData.speed or 1.0
    if layerData.reversed then speed = -speed end
    widgets.speed:setValue(speed)
  end

  local isMuted = layerData.muted or (layerData.params and layerData.params.mute and layerData.params.mute > 0.5)
  if widgets.mute then
    if isMuted then
      widgets.mute:setBg(0xffef4444)
      widgets.mute:setLabel("Muted")
    else
      widgets.mute:setBg(0xff475569)
      widgets.mute:setLabel("Mute")
    end
  end

  if widgets.waveform then
    if isMuted then
      widgets.waveform:setColour(0xff94a3b8)
    else
      widgets.waveform:setColour(Shared.layerStateColour(stateName))
    end
  end

  if widgets.play then
    if stateName == "playing" then
      widgets.play:setBg(0xfff59e0b)
      widgets.play:setLabel("⏸")
    else
      widgets.play:setBg(0xff1f7a3a)
      widgets.play:setLabel("▶")
    end
  end
end

function M.cleanup(ctx)
end

return M

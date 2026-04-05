local Shared = require("behaviors.looper_shared_state")
local DonutShared = require("behaviors.donut_shared_state")

local M = {}

local function initDonut(ctx, idx)
  local widgets = ctx.widgets or {}
  local donut = widgets["donut" .. idx]
  if not donut then return end

  donut._layerIndex = idx
  donut._onSeek = function()
    DonutShared.commandSet("/core/behavior/layer", idx)
  end

  donut.node:setOnClick(function()
    DonutShared.commandSet("/core/behavior/layer", idx)
  end)
end

local kDonutColours = { 0xff22d3ee, 0xffa78bfa, 0xfff59e0b, 0xff34d399 }

local function updateDonut(ctx, state, idx)
  local widgets = ctx.widgets or {}
  local donut = widgets["donut" .. idx]
  if not donut then return end

  local layer = state.layers and state.layers[idx + 1] or {}
  local stateName = layer.state or "empty"
  local positionNorm = 0.0
  if (layer.length or 0) > 0 then
    positionNorm = DonutShared.clamp((tonumber(layer.position) or 0) / math.max(1, tonumber(layer.length) or 1), 0.0, 1.0)
  end

  local peaks = nil
  if type(getLayerPeaks) == "function" then
    peaks = getLayerPeaks(idx, 32)
  end

  donut:setLayerData({
    length = layer.length or 0,
    positionNorm = positionNorm,
    volume = layer.volume or 1.0,
    muted = layer.muted,
    state = stateName,
  })
  donut:setPeaks(peaks)
  donut:setBounce((stateName == "playing" and not layer.muted) and 0.15 or 0.0)
end

function M.init(ctx)
  local widgets = ctx.widgets or {}
  local recBtn = widgets.rec
  local playPauseBtn = widgets.playpause
  local stopBtn = widgets.stop
  local overdub = widgets.overdub
  local clearAll = widgets.clearall
  local tempo = widgets.tempo
  local target = widgets.targetBpm
  local mode = widgets.mode

  ctx._recButtonLatched = false

  if recBtn then
    recBtn._onPress = function()
      if ctx._recButtonLatched then
        Shared.commandTrigger("/core/behavior/stoprec")
        ctx._recButtonLatched = false
      else
        Shared.commandTrigger("/core/behavior/rec")
        ctx._recButtonLatched = true
      end
    end
  end

  if playPauseBtn then
    playPauseBtn._onClick = function()
      local state = ctx._state or {}
      if Shared.anyLayerPlaying(state) then
        Shared.commandTrigger("/core/behavior/pause")
      else
        Shared.commandTrigger("/core/behavior/play")
      end
    end
  end

  if stopBtn then
    stopBtn._onClick = function()
      Shared.commandTrigger("/core/behavior/stop")
    end
  end

  if overdub then
    Shared.commandSet("/core/behavior/overdub", 1)
    overdub._onChange = function(on)
      Shared.commandSet("/core/behavior/overdub", on and 1 or 0)
    end
  end

  if clearAll then
    clearAll._onClick = function()
      Shared.commandTrigger("/core/behavior/clear")
    end
  end

  if tempo then
    tempo._onChange = function(v)
      Shared.commandSet("/core/behavior/tempo", v)
    end
  end

  if target then
    target._onChange = function(v)
      Shared.commandSet("/core/behavior/targetbpm", v)
    end
  end

  if mode then
    mode._onSelect = function(idx)
      local modeIdx = math.max(0, math.min(2, (tonumber(idx) or 1) - 1))
      Shared.commandSet("/core/behavior/mode", modeIdx)
    end
  end

  for i = 0, 3 do
    initDonut(ctx, i)
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local root = ctx.root
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local ids = {
    "mode",
    "rec",
    "playpause",
    "stop",
    "overdub",
    "clearall",
    "donut0",
    "donut1",
    "donut2",
    "donut3",
    "linkIndicator",
    "tempo",
    "targetBpm",
  }

  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end

  if widgets.mode and widgets.mode.setAbsolutePos and root and root.node and root.node.getBounds then
    local rx, ry = root.node:getBounds()
    local mx, my = widgets.mode.node:getBounds()
    widgets.mode:setAbsolutePos(rx + mx, ry + my)
  end
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local state = Shared.normalizeState(rawState)
  ctx._state = state
  ctx._recButtonLatched = state.isRecording or false

  if widgets.tempo then widgets.tempo:setValue(state.tempo or 120) end
  if widgets.targetBpm then widgets.targetBpm:setValue(state.targetBPM or 120) end

  if widgets.linkIndicator then
    local linkState = state.link
    if linkState and linkState.enabled then
      local peers = linkState.peers or 0
      if peers > 0 then
        widgets.linkIndicator:setText("● LINK " .. peers)
        widgets.linkIndicator:setColour(0xff4ade80)
      else
        widgets.linkIndicator:setText("● LINK")
        widgets.linkIndicator:setColour(0xfff59e0b)
      end
    else
      widgets.linkIndicator:setText("○ link")
      widgets.linkIndicator:setColour(0xff4b5563)
    end
  end

  if widgets.mode then
    widgets.mode:setSelected(math.max(1, math.min(3, (state.recordModeInt or 0) + 1)))
  end

  if widgets.rec then
    if state.isRecording then
      widgets.rec:setBg(0xffdc2626)
      widgets.rec:setLabel("● REC*")
    else
      widgets.rec:setBg(0xff7f1d1d)
      widgets.rec:setLabel("● REC")
    end
  end

  if widgets.playpause then
    if Shared.anyLayerPlaying(state) then
      widgets.playpause:setLabel("⏸ PAUSE")
      widgets.playpause:setBg(0xffb45309)
    else
      widgets.playpause:setLabel("▶ PLAY")
      widgets.playpause:setBg(0xff1f7a3a)
    end
  end

  if widgets.overdub then
    widgets.overdub:setValue(state.overdubEnabled or false)
  end

  for i = 0, 3 do
    updateDonut(ctx, state, i)
  end

  local activeLayer = state.activeLayer or 0
  if ctx._lastActiveLayer ~= activeLayer then
    ctx._lastActiveLayer = activeLayer
    for i = 0, 3 do
      local donut = widgets["donut" .. i]
      if donut then
        donut:setActive(i == activeLayer, kDonutColours[i + 1])
      end
    end
  end
end

function M.cleanup(ctx)
end

return M

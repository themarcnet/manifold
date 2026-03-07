local Shared = require("behaviors.donut_shared_state")

local M = {}

local function selectLayer(layerIdx)
  Shared.commandSet("/core/behavior/layer", layerIdx)
end

function M.init(ctx)
  local widgets = ctx.widgets or {}
  local layerIdx = tonumber(ctx.instanceProps and ctx.instanceProps.layerIndex) or 0
  ctx._layerIndex = layerIdx

  if widgets.donut then
    widgets.donut._layerIndex = layerIdx
    widgets.donut._onSeek = function(_, norm)
      selectLayer(layerIdx)
      Shared.commandSet(Shared.layerPath(layerIdx, "seek"), norm)
    end
  end

  if ctx.root and ctx.root.node then
    ctx.root.node:setOnClick(function()
      selectLayer(layerIdx)
    end)
  end

  if widgets.play then
    widgets.play._onClick = function()
      local state = ctx._state or {}
      local layer = state.layers and state.layers[layerIdx + 1] or {}
      selectLayer(layerIdx)
      if (layer.state or "") == "playing" then
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

  if widgets.mute then
    widgets.mute._onClick = function()
      local state = ctx._state or {}
      local layer = state.layers and state.layers[layerIdx + 1] or {}
      local muted = layer.muted or false
      selectLayer(layerIdx)
      Shared.commandSet(Shared.layerPath(layerIdx, "mute"), muted and 0 or 1)
    end
  end

  if widgets.vol then
    widgets.vol._onChange = function(v)
      selectLayer(layerIdx)
      Shared.commandSet(Shared.layerPath(layerIdx, "volume"), v)
    end
  end

  if widgets.preset then
    widgets.preset:setOptions(Shared.kFxLabels)
    widgets.preset._onSelect = function(idx)
      Shared.setLayerEffectByIndex(layerIdx, idx)
    end
  end

  local mappingLabels = Shared.mappingOptionLabels()
  for _, id in ipairs({ "xMap", "yMap", "k1Map", "k2Map", "mixMap" }) do
    if widgets[id] then
      widgets[id]:setOptions(mappingLabels)
    end
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local ids = {
    "title", "donut", "play", "clear", "mute", "vol", "preset",
    "xMap", "yMap", "xy", "k1Map", "k2Map", "mixMap", "k1", "k2", "mix",
  }
  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end

  for _, id in ipairs({ "preset", "xMap", "yMap", "k1Map", "k2Map", "mixMap" }) do
    Shared.setDropdownAbsolutePos(ctx.root, widgets[id])
  end
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local state = Shared.normalizeState(rawState)
  ctx._state = state
  local layerIdx = ctx._layerIndex or 0
  local layer = state.layers and state.layers[layerIdx + 1] or {}
  local isActive = (state.activeLayer or 0) == layerIdx
  local stateName = layer.state or "empty"
  local effectId = Shared.getSelections().layers[layerIdx + 1] or "bypass"

  if ctx.root then
    if isActive then
      ctx.root:setStyle({ bg = 0xff10243f, border = 0xff38bdf8, borderWidth = 2 })
    else
      ctx.root:setStyle({ bg = 0xff0b1220, border = 0xff1f2937, borderWidth = 1 })
    end
  end

  if widgets.title then
    widgets.title:setText(string.format("Layer %d  •  %s  •  %s", layerIdx, Shared.layerStateName(stateName), Shared.effectLabelById(effectId)))
    widgets.title:setColour(isActive and 0xffdbeafe or 0xffcbd5e1)
  end

  if widgets.play then
    if stateName == "playing" then
      widgets.play:setLabel("Pause")
      widgets.play:setBg(0xffb45309)
    else
      widgets.play:setLabel("Play")
      widgets.play:setBg(0xff14532d)
    end
  end

  if widgets.mute then
    if layer.muted then
      widgets.mute:setLabel("Muted")
      widgets.mute:setBg(0xffef4444)
    else
      widgets.mute:setLabel("Mute")
      widgets.mute:setBg(0xff475569)
    end
  end

  if widgets.vol and not widgets.vol._dragging then
    widgets.vol:setValue(layer.volume or 1.0)
  end

  if widgets.preset then
    widgets.preset:setSelected(Shared.effectIndexFromId(effectId))
  end

  if widgets.xy then
    widgets.xy:setValues(0.5, 0.5)
  end
  if widgets.k1 then widgets.k1:setValue(0.5) end
  if widgets.k2 then widgets.k2:setValue(0.5) end
  if widgets.mix then widgets.mix:setValue(0.35) end

  if widgets.donut then
    local peaks = nil
    if type(getLayerPeaks) == "function" then
      peaks = getLayerPeaks(layerIdx, 96)
    end
    local positionNorm = 0.0
    if (layer.length or 0) > 0 then
      positionNorm = Shared.clamp((tonumber(layer.position) or 0) / math.max(1, tonumber(layer.length) or 1), 0.0, 1.0)
    end
    widgets.donut:setLayerData({
      length = layer.length or 0,
      positionNorm = positionNorm,
      volume = layer.volume or 1.0,
      muted = layer.muted,
      state = stateName,
    })
    widgets.donut:setPeaks(peaks)
    widgets.donut:setBounce((stateName == "playing" and not layer.muted) and 0.2 or 0.0)
  end
end

function M.cleanup(ctx)
end

return M

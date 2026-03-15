local Shared = require("behaviors.donut_shared_state")

local M = {}

local function selectedLayer(ctx)
  return tonumber(ctx._selectedLayer or 0) or 0
end

function M.init(ctx)
  local widgets = ctx.widgets or {}

  if widgets.layerTabs then
    widgets.layerTabs._segments = { "L0", "L1", "L2", "L3" }
    widgets.layerTabs._onSelect = function(idx)
      local layerIdx = math.max(0, math.min(3, (tonumber(idx) or 1) - 1))
      ctx._selectedLayer = layerIdx
      Shared.commandSet("/core/behavior/layer", layerIdx)
    end
  end

  if widgets.vocalPreset then
    widgets.vocalPreset:setOptions(Shared.kFxLabels)
    widgets.vocalPreset._onSelect = function(idx)
      Shared.setVocalEffectByIndex(idx)
    end
  end

  if widgets.layerPreset then
    widgets.layerPreset:setOptions(Shared.kFxLabels)
    widgets.layerPreset._onSelect = function(idx)
      Shared.setLayerEffectByIndex(selectedLayer(ctx), idx)
    end
  end

  for _, id in ipairs({ "xMap", "yMap", "k1Map", "k2Map", "mixMap" }) do
    if widgets[id] then
      widgets[id]:setOptions(Shared.mappingOptionLabels())
    end
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local ids = {
    "title", "subtitle", "layerTabs", "vocalPreset", "layerPreset",
    "xMap", "yMap", "k1Map", "k2Map", "mixMap",
    "xy", "donut", "k1", "k2", "mix", "info"
  }
  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end

  for _, id in ipairs({ "vocalPreset", "layerPreset", "xMap", "yMap", "k1Map", "k2Map", "mixMap" }) do
    Shared.setDropdownAbsolutePos(ctx.root, widgets[id])
  end
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local state = Shared.normalizeState(rawState)
  local selections = Shared.getSelections()
  local activeLayer = tonumber(state.activeLayer or 0) or 0
  ctx._selectedLayer = ctx._selectedLayer or activeLayer
  local layerIdx = selectedLayer(ctx)
  local layerFxId = selections.layers[layerIdx + 1] or "bypass"
  local vocalFxId = selections.vocal or "bypass"
  local layer = state.layers and state.layers[layerIdx + 1] or {}
  local stateName = layer.state or "empty"

  if widgets.title then
    widgets.title:setText("Effects Sandbox")
  end
  if widgets.subtitle then
    widgets.subtitle:setText(string.format("Shared looper core • active layer %d • sandbox layer %d", activeLayer, layerIdx))
  end
  if widgets.layerTabs then
    widgets.layerTabs:setSelected(layerIdx + 1)
  end
  if widgets.vocalPreset then
    widgets.vocalPreset:setSelected(Shared.effectIndexFromId(vocalFxId))
  end
  if widgets.layerPreset then
    widgets.layerPreset:setSelected(Shared.effectIndexFromId(layerFxId))
  end
  if widgets.info then
    widgets.info:setText(string.format("Layer %d • %s • Vocal FX: %s • Layer FX: %s", layerIdx, Shared.layerStateName(stateName), Shared.effectLabelById(vocalFxId), Shared.effectLabelById(layerFxId)))
  end
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
  if widgets.xy then widgets.xy:setValues(0.5, 0.5) end
  if widgets.k1 then widgets.k1:setValue(0.5) end
  if widgets.k2 then widgets.k2:setValue(0.35) end
  if widgets.mix then widgets.mix:setValue(0.6) end
end

return M

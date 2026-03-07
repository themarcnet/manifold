local Shared = require("behaviors.donut_shared_state")

local M = {}

function M.init(ctx)
  local widgets = ctx.widgets or {}

  if widgets.preset then
    widgets.preset:setOptions(Shared.kFxLabels)
    widgets.preset._onSelect = function(idx)
      Shared.setVocalEffectByIndex(idx)
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
  local ids = { "title", "preset", "xMap", "yMap", "xy", "k1Map", "k2Map", "mixMap", "k1", "k2", "mix" }
  for _, id in ipairs(ids) do
    Shared.applySpecRect(widgets[id], Shared.getChildSpec(ctx, id), w, h, designW, designH)
  end

  for _, id in ipairs({ "preset", "xMap", "yMap", "k1Map", "k2Map", "mixMap" }) do
    Shared.setDropdownAbsolutePos(ctx.root, widgets[id])
  end
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local _ = Shared.normalizeState(rawState)
  local selections = Shared.getSelections()
  local effectId = selections.vocal or "bypass"
  local idx = Shared.effectIndexFromId(effectId)

  if widgets.preset then widgets.preset:setSelected(idx) end
  if widgets.title then widgets.title:setText("Vocal Input FX  •  " .. Shared.effectLabelById(effectId)) end
end

function M.cleanup(ctx)
end

return M

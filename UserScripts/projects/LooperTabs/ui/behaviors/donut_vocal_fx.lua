local Shared = require("behaviors.donut_shared_state")

local M = {}

function M.init(ctx)
  local widgets = ctx.widgets or {}
  ctx._scope = Shared.createMappingScope(Shared.vocalFxBasePath())

  if widgets.preset then
    widgets.preset:setOptions(Shared.kFxLabels)
    widgets.preset._onSelect = function(idx)
      Shared.setVocalEffectByIndex(idx)
    end
  end

  local function bindMapDropdown(id, key)
    if widgets[id] then
      widgets[id]._onSelect = function(idx)
        Shared.assignScopeMappingByIndex(ctx._scope, key, idx)
      end
    end
  end

  bindMapDropdown("xMap", "x")
  bindMapDropdown("yMap", "y")
  bindMapDropdown("k1Map", "k1")
  bindMapDropdown("k2Map", "k2")
  bindMapDropdown("mixMap", "mix")

  if widgets.xy then
    widgets.xy._onChange = function(x, y)
      Shared.applyMappedNormalized(ctx._scope.mappings.x, x)
      Shared.applyMappedNormalized(ctx._scope.mappings.y, y)
    end
  end

  if widgets.k1 then
    widgets.k1._onChange = function(v)
      Shared.applyMappedActual(ctx._scope.mappings.k1, v)
    end
  end

  if widgets.k2 then
    widgets.k2._onChange = function(v)
      Shared.applyMappedActual(ctx._scope.mappings.k2, v)
    end
  end

  if widgets.mix then
    widgets.mix._onChange = function(v)
      Shared.applyMappedActual(ctx._scope.mappings.mix, v)
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
  local scope = ctx._scope

  if scope then
    Shared.ensureScopeCatalog(scope, effectId)
  end

  if widgets.preset then widgets.preset:setSelected(idx) end
  if widgets.title then widgets.title:setText("Vocal Input FX  •  " .. Shared.effectLabelById(effectId)) end

  if scope then
    Shared.syncScopeDropdown(widgets.xMap, scope, "x")
    Shared.syncScopeDropdown(widgets.yMap, scope, "y")
    Shared.syncScopeDropdown(widgets.k1Map, scope, "k1")
    Shared.syncScopeDropdown(widgets.k2Map, scope, "k2")
    Shared.syncScopeDropdown(widgets.mixMap, scope, "mix")
    Shared.syncMappedXY(widgets.xy, scope.mappings.x, scope.mappings.y, 0.5, 0.5)
    Shared.syncMappedKnob(widgets.k1, scope.mappings.k1, "K1", 0.5)
    Shared.syncMappedKnob(widgets.k2, scope.mappings.k2, "K2", 0.5)
    Shared.syncMappedKnob(widgets.mix, scope.mappings.mix, "Mix", 0.45)
  end
end

function M.cleanup(ctx)
end

return M

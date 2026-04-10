local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local FxSlot = deps.FxSlot
  local ParameterBinder = deps.ParameterBinder
  local fxCtx = deps.fxCtx
  local fxDefs = deps.fxDefs
  local maxFxParams = deps.maxFxParams

  local function writeParam(path, value)
    local writer = type(setParam) == "function" and setParam or nil
    if writer == nil and ctx and ctx.host and type(ctx.host.setParam) == "function" then
      writer = function(paramPath, paramValue)
        return ctx.host.setParam(paramPath, paramValue)
      end
    end
    if type(writer) == "function" then
      return writer(path, value) == true
    end
    return false
  end

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end
    slots[index] = FxSlot.create(fxCtx, fxDefs, { defaultMix = 0.0, maxFxParams = maxFxParams })
    return slots[index]
  end

  local function applyPath(path, value)
    local slotIndex, suffix, paramIndex = ParameterBinder.matchDynamicFxPath(path)
    if slotIndex == nil then
      return false
    end
    local slot = slots[slotIndex]
    if not slot then
      return true
    end
    if suffix == "type" then
      slot.applySelection(value)
      for i = 1, maxFxParams do
        writeParam(ParameterBinder.dynamicFxParamPath(slotIndex, i - 1), slot.paramValues[i] or 0.5)
      end
      return true
    elseif suffix == "mix" then
      slot.applyMix(value)
      return true
    elseif suffix == "param" and paramIndex ~= nil then
      slot.applyParam(paramIndex + 1, value)
      return true
    end
    return false
  end

  return {
    createSlot = createSlot,
    applyPath = applyPath,
  }
end

return M

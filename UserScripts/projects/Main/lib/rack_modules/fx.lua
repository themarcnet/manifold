local M = {}

function M.create(deps)
  local slots = deps.slots
  local FxSlot = deps.FxSlot
  local ParameterBinder = deps.ParameterBinder
  local fxCtx = deps.fxCtx
  local fxDefs = deps.fxDefs
  local maxFxParams = deps.maxFxParams

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

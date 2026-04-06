local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local Utils = deps.Utils
  local ParameterBinder = deps.ParameterBinder
  local applyDefaults = deps.applyDefaults

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end
    local node = ctx.primitives.SVFNode.new()
    applyDefaults(node)
    slots[index] = { node = node }
    return slots[index]
  end

  local function applyPath(path, value)
    local slotIndex, suffix = ParameterBinder.matchDynamicFilterPath(path)
    if slotIndex == nil then
      return false
    end
    local slot = slots[slotIndex]
    local node = slot and slot.node or nil
    if not node then
      return true
    end
    if suffix == "type" then
      node:setMode(Utils.roundIndex(value, 3))
      return true
    elseif suffix == "cutoff" then
      node:setCutoff(tonumber(value) or 3200.0)
      return true
    elseif suffix == "resonance" then
      node:setResonance(tonumber(value) or 0.75)
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

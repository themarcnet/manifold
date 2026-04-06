local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local applyDefaults = deps.applyDefaults
  local ParameterBinder = deps.ParameterBinder

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end
    local node = ctx.primitives.EQ8Node.new()
    applyDefaults(node)
    slots[index] = { node = node }
    return slots[index]
  end

  local function setEqNodeBandEnabled(node, bandIndex, value)
    node:setBandEnabled(math.max(1, math.floor(tonumber(bandIndex) or 1)), (tonumber(value) or 0) > 0.5)
  end

  local function applyPath(path, value)
    local slotIndex, bandIndex, suffix = ParameterBinder.matchDynamicEqPath(path)
    if slotIndex == nil then
      return false
    end
    local slot = slots[slotIndex]
    local node = slot and slot.node or nil
    if not node then
      return true
    end
    if suffix == "mix" then
      node:setMix(tonumber(value) or 1.0)
      return true
    elseif suffix == "output" then
      node:setOutput(tonumber(value) or 0.0)
      return true
    elseif suffix == "enabled" and bandIndex ~= nil then
      setEqNodeBandEnabled(node, bandIndex, value)
      return true
    elseif suffix == "type" and bandIndex ~= nil then
      node:setBandType(bandIndex, math.max(0, math.floor((tonumber(value) or 0) + 0.5)))
      return true
    elseif suffix == "freq" and bandIndex ~= nil then
      node:setBandFreq(bandIndex, tonumber(value) or 1000.0)
      return true
    elseif suffix == "gain" and bandIndex ~= nil then
      node:setBandGain(bandIndex, tonumber(value) or 0.0)
      return true
    elseif suffix == "q" and bandIndex ~= nil then
      node:setBandQ(bandIndex, tonumber(value) or 1.0)
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

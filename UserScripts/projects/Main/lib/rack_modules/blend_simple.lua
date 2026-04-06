local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local Utils = deps.Utils
  local ParameterBinder = deps.ParameterBinder
  local connectMixerInput = deps.connectMixerInput

  local function applyMode(slot)
    if not slot then
      return false
    end
    local mode = math.max(0, math.min(3, math.floor(tonumber(slot.mode) or 0)))
    for busIndex = 1, 4 do
      slot.modeMixer:setGain(busIndex, busIndex == (mode + 1) and 1.0 or 0.0)
    end
    return true
  end

  local function applyParams(slot)
    if not slot then
      return false
    end
    local amount = Utils.clamp01(tonumber(slot.blendAmount) or 0.5)
    local wetAmount = Utils.clamp01(tonumber(slot.blendModAmount) or 0.5)
    local blendPos = amount * 2.0 - 1.0
    local modulationDepth = Utils.clamp01(wetAmount)

    slot.mixCrossfade:setPosition(blendPos)
    slot.mixCrossfade:setCurve(1.0)
    slot.mixCrossfade:setMix(1.0)

    slot.ringAToB:setDepth(modulationDepth)
    slot.ringAToB:setMix(1.0)
    slot.ringAToB:setSpread(0.0)
    if slot.ringAToB.setEnabled then slot.ringAToB:setEnabled(modulationDepth > 0.001) end

    slot.ringBToA:setDepth(modulationDepth)
    slot.ringBToA:setMix(1.0)
    slot.ringBToA:setSpread(0.0)
    if slot.ringBToA.setEnabled then slot.ringBToA:setEnabled(modulationDepth > 0.001) end

    slot.ringCrossfade:setPosition(blendPos)
    slot.ringCrossfade:setCurve(1.0)
    slot.ringCrossfade:setMix(1.0)

    slot.fmAToB:setAmount(modulationDepth)
    slot.fmAToB:setMix(1.0)
    slot.fmBToA:setAmount(modulationDepth)
    slot.fmBToA:setMix(1.0)
    slot.fmCrossfade:setPosition(blendPos)
    slot.fmCrossfade:setCurve(1.0)
    slot.fmCrossfade:setMix(1.0)

    slot.syncAToB:setHardness(modulationDepth)
    slot.syncAToB:setMix(1.0)
    slot.syncBToA:setHardness(modulationDepth)
    slot.syncBToA:setMix(1.0)
    slot.syncCrossfade:setPosition(blendPos)
    slot.syncCrossfade:setCurve(1.0)
    slot.syncCrossfade:setMix(1.0)

    slot.output:setGain(Utils.clamp01(tonumber(slot.outputLevel) or 1.0))
    applyMode(slot)
    return true
  end

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end

    local inputA = ctx.primitives.GainNode.new(2)
    inputA:setGain(1.0)
    local inputB = ctx.primitives.GainNode.new(2)
    inputB:setGain(1.0)

    local mixCrossfade = ctx.primitives.CrossfaderNode.new()
    mixCrossfade:setPosition(0.0)
    mixCrossfade:setCurve(1.0)
    mixCrossfade:setMix(1.0)

    local ringAToB = ctx.primitives.RingModulatorNode.new()
    ringAToB:setFrequency(120.0)
    ringAToB:setDepth(0.0)
    ringAToB:setMix(1.0)
    ringAToB:setSpread(0.0)
    if ringAToB.setEnabled then ringAToB:setEnabled(true) end

    local ringBToA = ctx.primitives.RingModulatorNode.new()
    ringBToA:setFrequency(120.0)
    ringBToA:setDepth(0.0)
    ringBToA:setMix(1.0)
    ringBToA:setSpread(0.0)
    if ringBToA.setEnabled then ringBToA:setEnabled(true) end

    local ringCrossfade = ctx.primitives.CrossfaderNode.new()
    ringCrossfade:setPosition(0.0)
    ringCrossfade:setCurve(1.0)
    ringCrossfade:setMix(1.0)

    local fmAToB = ctx.primitives.AudioFmNode.new()
    fmAToB:setAmount(0.0)
    fmAToB:setMix(1.0)

    local fmBToA = ctx.primitives.AudioFmNode.new()
    fmBToA:setAmount(0.0)
    fmBToA:setMix(1.0)

    local fmCrossfade = ctx.primitives.CrossfaderNode.new()
    fmCrossfade:setPosition(0.0)
    fmCrossfade:setCurve(1.0)
    fmCrossfade:setMix(1.0)

    local syncAToB = ctx.primitives.AudioSyncNode.new()
    syncAToB:setHardness(0.0)
    syncAToB:setMix(1.0)

    local syncBToA = ctx.primitives.AudioSyncNode.new()
    syncBToA:setHardness(0.0)
    syncBToA:setMix(1.0)

    local syncCrossfade = ctx.primitives.CrossfaderNode.new()
    syncCrossfade:setPosition(0.0)
    syncCrossfade:setCurve(1.0)
    syncCrossfade:setMix(1.0)

    local modeMixer = ctx.primitives.MixerNode.new()
    modeMixer:setInputCount(4)
    for busIndex = 1, 4 do
      modeMixer:setGain(busIndex, busIndex == 1 and 1.0 or 0.0)
      modeMixer:setPan(busIndex, 0.0)
    end

    local output = ctx.primitives.GainNode.new(2)
    output:setGain(1.0)

    ctx.graph.connect(inputA, mixCrossfade, 0, 0)
    ctx.graph.connect(inputB, mixCrossfade, 0, 2)
    ctx.graph.connect(inputA, ringAToB, 0, 0)
    ctx.graph.connect(inputB, ringAToB, 0, 2)
    ctx.graph.connect(inputB, ringBToA, 0, 0)
    ctx.graph.connect(inputA, ringBToA, 0, 2)
    ctx.graph.connect(ringAToB, ringCrossfade, 0, 0)
    ctx.graph.connect(ringBToA, ringCrossfade, 0, 2)
    ctx.graph.connect(inputA, fmAToB, 0, 0)
    ctx.graph.connect(inputB, fmAToB, 0, 2)
    ctx.graph.connect(inputB, fmBToA, 0, 0)
    ctx.graph.connect(inputA, fmBToA, 0, 2)
    ctx.graph.connect(fmAToB, fmCrossfade, 0, 0)
    ctx.graph.connect(fmBToA, fmCrossfade, 0, 2)
    ctx.graph.connect(inputA, syncAToB, 0, 0)
    ctx.graph.connect(inputB, syncAToB, 0, 2)
    ctx.graph.connect(inputB, syncBToA, 0, 0)
    ctx.graph.connect(inputA, syncBToA, 0, 2)
    ctx.graph.connect(syncAToB, syncCrossfade, 0, 0)
    ctx.graph.connect(syncBToA, syncCrossfade, 0, 2)
    connectMixerInput(modeMixer, 1, mixCrossfade)
    connectMixerInput(modeMixer, 2, ringCrossfade)
    connectMixerInput(modeMixer, 3, fmCrossfade)
    connectMixerInput(modeMixer, 4, syncCrossfade)
    ctx.graph.connect(modeMixer, output)

    slots[index] = {
      slotIndex = index,
      inputA = inputA,
      inputB = inputB,
      mixCrossfade = mixCrossfade,
      ringAToB = ringAToB,
      ringBToA = ringBToA,
      ringCrossfade = ringCrossfade,
      fmAToB = fmAToB,
      fmBToA = fmBToA,
      fmCrossfade = fmCrossfade,
      syncAToB = syncAToB,
      syncBToA = syncBToA,
      syncCrossfade = syncCrossfade,
      modeMixer = modeMixer,
      output = output,
      mode = 0,
      amount = 0.5,
      mix = 0.5,
      outputLevel = 1.0,
    }
    applyParams(slots[index])
    return slots[index]
  end

  local function applyPath(path, value)
    local slotIndex, suffix = ParameterBinder.matchDynamicBlendSimplePath(path)
    if slotIndex == nil then
      return false
    end
    local slot = slots[slotIndex]
    if not slot then
      return true
    end

    local numeric = tonumber(value) or 0.0
    if suffix == "mode" then
      slot.mode = math.max(0, math.min(3, math.floor(numeric + 0.5)))
    elseif suffix == "blendAmount" then
      slot.blendAmount = Utils.clamp01(numeric)
    elseif suffix == "blendModAmount" then
      slot.blendModAmount = Utils.clamp01(numeric)
    elseif suffix == "output" then
      slot.outputLevel = Utils.clamp01(numeric)
    else
      return false
    end

    return applyParams(slot)
  end

  return {
    createSlot = createSlot,
    applyPath = applyPath,
  }
end

return M

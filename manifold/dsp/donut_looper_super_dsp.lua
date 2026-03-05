local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function map(v, inLo, inHi, outLo, outHi)
  local t = 0.0
  if inHi ~= inLo then
    t = (v - inLo) / (inHi - inLo)
  end
  t = clamp(t, 0.0, 1.0)
  return outLo + (outHi - outLo) * t
end

local kNumLayers = 4
local kFxPresetCount = 4

function buildPlugin(ctx)
  local state = {
    super = {
      vocal = nil,
      layerFx = {},
    },
  }

  local function register(path, opts)
    ctx.params.register(path, opts)
  end

  local function normalizePath(path)
    if type(path) ~= "string" then
      return path
    end
    if string.sub(path, 1, 21) == "/core/behavior/super/" then
      return "/core/super/" .. string.sub(path, 22)
    end
    return path
  end

  local function registerFxSlotParams(basePath)
    register(basePath .. "/select", { type = "f", min = 0.0, max = kFxPresetCount - 1, default = 0.0 })
    register(basePath .. "/x", { type = "f", min = 0.0, max = 1.0, default = 0.5 })
    register(basePath .. "/y", { type = "f", min = 0.0, max = 1.0, default = 0.5 })
    register(basePath .. "/k1", { type = "f", min = 0.0, max = 1.0, default = 0.5 })
    register(basePath .. "/k2", { type = "f", min = 0.0, max = 1.0, default = 0.5 })
    register(basePath .. "/mix", { type = "f", min = 0.0, max = 1.0, default = 0.35 })
    register(basePath .. "/level", { type = "f", min = 0.0, max = 2.0, default = 1.0 })
  end

  local function createFxSlot(basePath)
    local chorus = ctx.primitives.ChorusNode.new()
    local phaser = ctx.primitives.PhaserNode.new()
    local reverseDelay = ctx.primitives.ReverseDelayNode.new()
    local crusher = ctx.primitives.BitCrusherNode.new()
    local fxMixer = ctx.primitives.MixerNode.new()
    local wetGain = ctx.primitives.GainNode.new(2)
    local outGain = ctx.primitives.GainNode.new(2)

    chorus:setRate(0.8)
    chorus:setDepth(0.55)
    chorus:setVoices(3)
    chorus:setSpread(0.7)
    chorus:setFeedback(0.18)
    chorus:setWaveform(0)
    chorus:setMix(1.0)

    phaser:setRate(0.4)
    phaser:setDepth(0.8)
    phaser:setStages(6)
    phaser:setFeedback(0.22)
    phaser:setSpread(120)

    reverseDelay:setTime(380)
    reverseDelay:setWindow(130)
    reverseDelay:setFeedback(0.45)
    reverseDelay:setMix(1.0)

    crusher:setBits(7)
    crusher:setRateReduction(8)
    crusher:setMix(1.0)
    crusher:setOutput(1.0)

    fxMixer:setGain1(1.0)
    fxMixer:setGain2(0.0)
    fxMixer:setGain3(0.0)
    fxMixer:setGain4(0.0)
    fxMixer:setPan1(0.0)
    fxMixer:setPan2(0.0)
    fxMixer:setPan3(0.0)
    fxMixer:setPan4(0.0)
    fxMixer:setMaster(1.0)

    wetGain:setGain(0.35)
    outGain:setGain(1.0)

    registerFxSlotParams(basePath)

    local slot = {
      chorus = chorus,
      phaser = phaser,
      reverseDelay = reverseDelay,
      crusher = crusher,
      fxMixer = fxMixer,
      wetGain = wetGain,
      outGain = outGain,
      select = 0,
      x = 0.5,
      y = 0.5,
      k1 = 0.5,
      k2 = 0.5,
      mix = 0.35,
      level = 1.0,
    }

    slot.connectSource = function(source)
      if not source then
        return
      end

      ctx.graph.connect(source, chorus)
      ctx.graph.connect(source, phaser)
      ctx.graph.connect(source, reverseDelay)
      ctx.graph.connect(source, crusher)

      ctx.graph.connect(chorus, fxMixer, 0, 0)
      ctx.graph.connect(phaser, fxMixer, 0, 1)
      ctx.graph.connect(reverseDelay, fxMixer, 0, 2)
      ctx.graph.connect(crusher, fxMixer, 0, 3)

      ctx.graph.connect(fxMixer, wetGain)
      ctx.graph.connect(wetGain, outGain)
    end

    slot.apply = function()
      local sel = clamp(math.floor(slot.select + 0.5), 0, kFxPresetCount - 1)
      slot.select = sel

      fxMixer:setGain1(sel == 0 and 1.0 or 0.0)
      fxMixer:setGain2(sel == 1 and 1.0 or 0.0)
      fxMixer:setGain3(sel == 2 and 1.0 or 0.0)
      fxMixer:setGain4(sel == 3 and 1.0 or 0.0)

      if sel == 0 then
        chorus:setRate(map(slot.x, 0, 1, 0.1, 6.0))
        chorus:setDepth(map(slot.y, 0, 1, 0.0, 1.0))
        chorus:setSpread(map(slot.k1, 0, 1, 0.0, 1.0))
        chorus:setFeedback(map(slot.k2, 0, 1, 0.0, 0.85))
      elseif sel == 1 then
        phaser:setRate(map(slot.x, 0, 1, 0.1, 8.0))
        phaser:setDepth(map(slot.y, 0, 1, 0.0, 1.0))
        phaser:setFeedback(map(slot.k1, 0, 1, -0.8, 0.8))
        phaser:setSpread(map(slot.k2, 0, 1, 0.0, 180.0))
      elseif sel == 2 then
        reverseDelay:setTime(map(slot.x, 0, 1, 80.0, 1600.0))
        reverseDelay:setFeedback(map(slot.y, 0, 1, 0.0, 0.92))
        reverseDelay:setWindow(map(slot.k1, 0, 1, 20.0, 420.0))
        reverseDelay:setMix(map(slot.k2, 0, 1, 0.2, 1.0))
      else
        crusher:setBits(map(slot.x, 0, 1, 2.0, 16.0))
        crusher:setRateReduction(map(slot.y, 0, 1, 1.0, 64.0))
        crusher:setOutput(map(slot.k1, 0, 1, 0.2, 1.8))
        crusher:setMix(map(slot.k2, 0, 1, 0.2, 1.0))
      end

      wetGain:setGain(clamp(slot.mix, 0.0, 1.0))
      outGain:setGain(clamp(slot.level, 0.0, 2.0))
    end

    slot.apply()
    return slot
  end

  local hostInput = ctx.primitives.PassthroughNode.new(2)
  local inputTrim = ctx.primitives.GainNode.new(2)
  inputTrim:setGain(1.0)
  ctx.graph.connect(hostInput, inputTrim)

  state.super.vocal = createFxSlot("/core/super/vocal/slot")
  state.super.vocal.mix = 0.35
  state.super.vocal.connectSource(inputTrim)
  state.super.vocal.apply()

  local layerMixer = ctx.primitives.MixerNode.new()
  layerMixer:setGain1(1.0)
  layerMixer:setGain2(1.0)
  layerMixer:setGain3(1.0)
  layerMixer:setGain4(1.0)
  layerMixer:setPan1(0.0)
  layerMixer:setPan2(0.0)
  layerMixer:setPan3(0.0)
  layerMixer:setPan4(0.0)
  layerMixer:setMaster(1.0)

  local function getHostNodeByPath(path)
    if ctx.host and ctx.host.getGraphNodeByPath then
      return ctx.host.getGraphNodeByPath(path)
    end
    return nil
  end

  for i = 0, kNumLayers - 1 do
    local slot = createFxSlot("/core/super/layer/" .. tostring(i) .. "/fx")
    slot.mix = 0.35
    slot.level = 1.0

    local layerOut = getHostNodeByPath("/core/behavior/layer/" .. tostring(i) .. "/output")

    if layerOut then
      slot.connectSource(layerOut)
      ctx.graph.connect(slot.outGain, layerMixer, 0, i)
    end

    local layerIn = getHostNodeByPath("/core/behavior/layer/" .. tostring(i) .. "/input")
    if layerIn then
      ctx.graph.connect(state.super.vocal.outGain, layerIn)
    end

    slot.apply()
    state.super.layerFx[i + 1] = slot
  end

  local mainMixer = ctx.primitives.MixerNode.new()
  mainMixer:setGain1(1.0)
  mainMixer:setGain2(1.0)
  mainMixer:setGain3(0.0)
  mainMixer:setGain4(0.0)
  mainMixer:setPan1(0.0)
  mainMixer:setPan2(0.0)
  mainMixer:setPan3(0.0)
  mainMixer:setPan4(0.0)
  mainMixer:setMaster(1.0)

  local masterGain = ctx.primitives.GainNode.new(2)
  masterGain:setGain(0.8)

  ctx.graph.connect(layerMixer, mainMixer, 0, 0)
  ctx.graph.connect(state.super.vocal.outGain, mainMixer, 0, 1)
  ctx.graph.connect(mainMixer, masterGain)

  local function applySlotParam(path, value)
    local function match(slot, base)
      if path == base .. "/select" then slot.select = value; slot.apply(); return true end
      if path == base .. "/x" then slot.x = clamp(value, 0.0, 1.0); slot.apply(); return true end
      if path == base .. "/y" then slot.y = clamp(value, 0.0, 1.0); slot.apply(); return true end
      if path == base .. "/k1" then slot.k1 = clamp(value, 0.0, 1.0); slot.apply(); return true end
      if path == base .. "/k2" then slot.k2 = clamp(value, 0.0, 1.0); slot.apply(); return true end
      if path == base .. "/mix" then slot.mix = clamp(value, 0.0, 1.0); slot.apply(); return true end
      if path == base .. "/level" then slot.level = clamp(value, 0.0, 2.0); slot.apply(); return true end
      return false
    end

    if match(state.super.vocal, "/core/super/vocal/slot") then return true end
    for i = 0, kNumLayers - 1 do
      if match(state.super.layerFx[i + 1], "/core/super/layer/" .. tostring(i) .. "/fx") then return true end
    end
    return false
  end

  return {
    onParamChange = function(path, value)
      path = normalizePath(path)
      applySlotParam(path, value)
    end,
  }
end

return buildPlugin

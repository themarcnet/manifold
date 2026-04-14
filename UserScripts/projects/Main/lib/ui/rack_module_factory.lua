local RackLayout = require("behaviors.rack_layout")
local ParameterBinder = require("parameter_binder")

local M = {}

local DEFAULT_VOICE_COUNT = 8
local EQ_DEFAULT_FREQS = { 60, 120, 250, 500, 1000, 2500, 6000, 12000 }
local EQ_DEFAULT_TYPES = { 1, 0, 0, 0, 0, 0, 0, 2 }
local EQ_DEFAULT_QS = { 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8 }

local DYNAMIC_MODULES = {}

DYNAMIC_MODULES = {
  adsr = {
    slotBucket = "adsr",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/adsr/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.adsr.buildParamBase(slotIndex)
      setPath(base .. "/attack", 0.05)
      setPath(base .. "/decay", 0.2)
      setPath(base .. "/sustain", 0.7)
      setPath(base .. "/release", 0.4)
    end,
  },
  arp = {
    slotBucket = "arp",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/arp/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.arp.buildParamBase(slotIndex)
      setPath(base .. "/rate", 8.0)
      setPath(base .. "/mode", 0)
      setPath(base .. "/octaves", 1)
      setPath(base .. "/gate", 0.6)
      setPath(base .. "/hold", 0)
    end,
  },
  transpose = {
    slotBucket = "transpose",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/transpose/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.transpose.buildParamBase(slotIndex)
      setPath(base .. "/semitones", 0)
    end,
  },
  velocity_mapper = {
    slotBucket = "velocity_mapper",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/velocity_mapper/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.velocity_mapper.buildParamBase(slotIndex)
      setPath(base .. "/amount", 1.0)
      setPath(base .. "/curve", 0)
      setPath(base .. "/offset", 0.0)
    end,
  },
  scale_quantizer = {
    slotBucket = "scale_quantizer",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/scale_quantizer/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.scale_quantizer.buildParamBase(slotIndex)
      setPath(base .. "/root", 0)
      setPath(base .. "/scale", 1)
      setPath(base .. "/direction", 1)
    end,
  },
  note_filter = {
    slotBucket = "note_filter",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/note_filter/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.note_filter.buildParamBase(slotIndex)
      setPath(base .. "/low", 36)
      setPath(base .. "/high", 96)
      setPath(base .. "/mode", 0)
    end,
  },
  attenuverter_bias = {
    slotBucket = "attenuverter_bias",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/attenuverter_bias/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.attenuverter_bias.buildParamBase(slotIndex)
      setPath(base .. "/amount", 1.0)
      setPath(base .. "/bias", 0.0)
    end,
  },
  lfo = {
    slotBucket = "lfo",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/lfo/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.lfo.buildParamBase(slotIndex)
      setPath(base .. "/rate", 1.0)
      setPath(base .. "/shape", 0)
      setPath(base .. "/depth", 1.0)
      setPath(base .. "/phase", 0)
      setPath(base .. "/retrig", 1)
    end,
  },
  slew = {
    slotBucket = "slew",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/slew/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.slew.buildParamBase(slotIndex)
      setPath(base .. "/rise", 0)
      setPath(base .. "/fall", 0)
      setPath(base .. "/shape", 1)
    end,
  },
  sample_hold = {
    slotBucket = "sample_hold",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/sample_hold/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.sample_hold.buildParamBase(slotIndex)
      setPath(base .. "/mode", 0)
    end,
  },
  compare = {
    slotBucket = "compare",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/compare/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.compare.buildParamBase(slotIndex)
      setPath(base .. "/threshold", 0.0)
      setPath(base .. "/hysteresis", 0.05)
      setPath(base .. "/direction", 0)
    end,
  },
  cv_mix = {
    slotBucket = "cv_mix",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/cv_mix/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.cv_mix.buildParamBase(slotIndex)
      setPath(base .. "/level_1", 1.0)
      setPath(base .. "/level_2", 0.0)
      setPath(base .. "/level_3", 0.0)
      setPath(base .. "/level_4", 0.0)
      setPath(base .. "/offset", 0.0)
    end,
  },
  eq = {
    slotBucket = "eq",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/eq/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.eq.buildParamBase(slotIndex)
      setPath(base .. "/mix", 1.0)
      setPath(base .. "/output", 0.0)
      for bandIndex = 1, 8 do
        setPath(string.format("%s/band/%d/enabled", base, bandIndex), 0)
        setPath(string.format("%s/band/%d/type", base, bandIndex), EQ_DEFAULT_TYPES[bandIndex] or 0)
        setPath(string.format("%s/band/%d/freq", base, bandIndex), EQ_DEFAULT_FREQS[bandIndex] or 1000)
        setPath(string.format("%s/band/%d/gain", base, bandIndex), 0.0)
        setPath(string.format("%s/band/%d/q", base, bandIndex), EQ_DEFAULT_QS[bandIndex] or 1.0)
      end
    end,
  },
  fx = {
    slotBucket = "fx",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/fx/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.fx.buildParamBase(slotIndex)
      setPath(base .. "/type", 0)
      setPath(base .. "/mix", 0.0)
      for paramIndex = 0, 4 do
        setPath(string.format("%s/p/%d", base, paramIndex), 0.5)
      end
    end,
  },
  filter = {
    slotBucket = "filter",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/filter/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.filter.buildParamBase(slotIndex)
      setPath(base .. "/type", 0)
      setPath(base .. "/cutoff", 3200)
      setPath(base .. "/resonance", 0.75)
    end,
  },
  rack_oscillator = {
    slotBucket = "rack_oscillator",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/osc/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.rack_oscillator.buildParamBase(slotIndex)
      local voiceCount = math.max(1, math.floor(tonumber(deps and deps.voiceCount or DEFAULT_VOICE_COUNT) or DEFAULT_VOICE_COUNT))
      setPath(base .. "/waveform", 1)
      setPath(base .. "/renderMode", 0)
      setPath(base .. "/additivePartials", 8)
      setPath(base .. "/additiveTilt", 0.0)
      setPath(base .. "/additiveDrift", 0.0)
      setPath(base .. "/drive", 0.0)
      setPath(base .. "/driveShape", 0)
      setPath(base .. "/driveBias", 0.0)
      setPath(base .. "/pulseWidth", 0.5)
      setPath(base .. "/unison", 1)
      setPath(base .. "/detune", 0.0)
      setPath(base .. "/spread", 0.0)
      setPath(base .. "/manualPitch", 60)
      setPath(base .. "/manualLevel", 0.0)
      setPath(base .. "/output", 0.8)
      for voiceIndex = 1, voiceCount do
        setPath(string.format("%s/voice/%d/gate", base, voiceIndex), 0)
        setPath(string.format("%s/voice/%d/vOct", base, voiceIndex), 60)
        setPath(string.format("%s/voice/%d/fm", base, voiceIndex), 0.0)
        setPath(string.format("%s/voice/%d/pwCv", base, voiceIndex), 0.5)
      end
    end,
  },
  rack_sample = {
    slotBucket = "rack_sample",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/sample/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.rack_sample.buildParamBase(slotIndex)
      local voiceCount = math.max(1, math.floor(tonumber(deps and deps.voiceCount or DEFAULT_VOICE_COUNT) or DEFAULT_VOICE_COUNT))
      setPath(base .. "/source", 1)
      setPath(base .. "/captureTrigger", 0)
      setPath(base .. "/captureBars", 1.0)
      setPath(base .. "/captureMode", 0)
      setPath(base .. "/captureStartOffset", 0)
      setPath(base .. "/capturedLengthMs", 0)
      setPath(base .. "/captureRecording", 0)
      setPath(base .. "/captureWriteOffset", 0)
      setPath(base .. "/pitchMapEnabled", 0)
      setPath(base .. "/pitchMode", 0)
      setPath(base .. "/pvoc/fftOrder", 11)
      setPath(base .. "/pvoc/timeStretch", 1.0)
      setPath(base .. "/rootNote", 60)
      setPath(base .. "/playStart", 0.0)
      setPath(base .. "/loopStart", 0.0)
      setPath(base .. "/loopLen", 1.0)
      setPath(base .. "/crossfade", 0.1)
      setPath(base .. "/retrigger", 1)
      setPath(base .. "/output", 0.8)
      for voiceIndex = 1, voiceCount do
        setPath(string.format("%s/voice/%d/gate", base, voiceIndex), 0)
        setPath(string.format("%s/voice/%d/vOct", base, voiceIndex), 60)
      end
    end,
  },
  blend_simple = {
    slotBucket = "blend_simple",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/blend_simple/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.blend_simple.buildParamBase(slotIndex)
      setPath(base .. "/mode", 0)
      setPath(base .. "/amount", 0.5)
      setPath(base .. "/mix", 0.5)
      setPath(base .. "/output", 1.0)
    end,
  },
  range_mapper = {
    slotBucket = "range_mapper",
    buildParamBase = function(slotIndex)
      return string.format("/midi/synth/rack/range_mapper/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
    end,
    resetDefaults = function(slotIndex, deps)
      local setPath = deps and deps.setPath or nil
      if type(setPath) ~= "function" then
        return
      end
      local base = DYNAMIC_MODULES.range_mapper.buildParamBase(slotIndex)
      setPath(base .. "/min", 0.0)
      setPath(base .. "/max", 1.0)
      setPath(base .. "/mode", 0)
    end,
  },
}

local function ensureDynamicNodeInfoTable()
  _G.__midiSynthDynamicModuleInfo = _G.__midiSynthDynamicModuleInfo or {}
  return _G.__midiSynthDynamicModuleInfo
end

local function interpolateTemplate(template, captures)
  local out = tostring(template or "")
  for i = 1, #captures do
    out = out:gsub("{" .. tostring(i) .. "}", tostring(captures[i] or ""))
  end
  return out
end

function M.specConfig(specId)
  return DYNAMIC_MODULES[tostring(specId or "")]
end

function M.ensureDynamicModuleSlots(ctx)
  ctx._dynamicModuleSlots = ctx._dynamicModuleSlots or {
    adsr = {},
    arp = {},
    transpose = {},
    velocity_mapper = {},
    scale_quantizer = {},
    note_filter = {},
    attenuverter_bias = {},
    lfo = {},
    slew = {},
    sample_hold = {},
    compare = {},
    cv_mix = {},
    eq = {},
    fx = {},
    filter = {},
    rack_oscillator = {},
    rack_sample = {},
    blend_simple = {},
    range_mapper = {},
  }
  ctx._dynamicModuleSlots.adsr = ctx._dynamicModuleSlots.adsr or {}
  ctx._dynamicModuleSlots.arp = ctx._dynamicModuleSlots.arp or {}
  ctx._dynamicModuleSlots.transpose = ctx._dynamicModuleSlots.transpose or {}
  ctx._dynamicModuleSlots.velocity_mapper = ctx._dynamicModuleSlots.velocity_mapper or {}
  ctx._dynamicModuleSlots.scale_quantizer = ctx._dynamicModuleSlots.scale_quantizer or {}
  ctx._dynamicModuleSlots.note_filter = ctx._dynamicModuleSlots.note_filter or {}
  ctx._dynamicModuleSlots.attenuverter_bias = ctx._dynamicModuleSlots.attenuverter_bias or {}
  ctx._dynamicModuleSlots.lfo = ctx._dynamicModuleSlots.lfo or {}
  ctx._dynamicModuleSlots.slew = ctx._dynamicModuleSlots.slew or {}
  ctx._dynamicModuleSlots.sample_hold = ctx._dynamicModuleSlots.sample_hold or {}
  ctx._dynamicModuleSlots.compare = ctx._dynamicModuleSlots.compare or {}
  ctx._dynamicModuleSlots.cv_mix = ctx._dynamicModuleSlots.cv_mix or {}
  ctx._dynamicModuleSlots.eq = ctx._dynamicModuleSlots.eq or {}
  ctx._dynamicModuleSlots.fx = ctx._dynamicModuleSlots.fx or {}
  ctx._dynamicModuleSlots.filter = ctx._dynamicModuleSlots.filter or {}
  ctx._dynamicModuleSlots.rack_oscillator = ctx._dynamicModuleSlots.rack_oscillator or {}
  ctx._dynamicModuleSlots.rack_sample = ctx._dynamicModuleSlots.rack_sample or {}
  ctx._dynamicModuleSlots.blend_simple = ctx._dynamicModuleSlots.blend_simple or {}
  ctx._dynamicModuleSlots.range_mapper = ctx._dynamicModuleSlots.range_mapper or {}
  return ctx._dynamicModuleSlots
end

function M.nextAvailableSlot(ctx, specId)
  local config = M.specConfig(specId)
  if type(config) ~= "table" then
    return nil
  end
  local capacity = math.max(0, math.floor(tonumber(ParameterBinder.dynamicSlotCapacity(specId)) or 0))
  if capacity <= 0 then
    return nil
  end
  local slots = M.ensureDynamicModuleSlots(ctx)
  local bucket = slots[config.slotBucket] or {}
  slots[config.slotBucket] = bucket

  for slotIndex = 1, capacity do
    local occupant = bucket[slotIndex]
    if occupant == nil or occupant == false then
      return slotIndex
    end
  end
  return nil
end

function M.markSlotOccupied(ctx, specId, slotIndex, nodeId)
  local config = M.specConfig(specId)
  if type(config) ~= "table" then
    return false
  end
  local slots = M.ensureDynamicModuleSlots(ctx)
  local bucket = slots[config.slotBucket] or {}
  slots[config.slotBucket] = bucket
  bucket[tonumber(slotIndex) or slotIndex] = nodeId
  return true
end

function M.freeSlot(ctx, specId, slotIndex)
  local config = M.specConfig(specId)
  if type(config) ~= "table" or slotIndex == nil then
    return false
  end
  local slots = M.ensureDynamicModuleSlots(ctx)
  local bucket = slots[config.slotBucket] or {}
  slots[config.slotBucket] = bucket
  bucket[tonumber(slotIndex) or slotIndex] = nil
  return true
end

function M.buildParamBase(specId, slotIndex)
  local config = M.specConfig(specId)
  if type(config) ~= "table" or type(config.buildParamBase) ~= "function" then
    return nil
  end
  return config.buildParamBase(slotIndex)
end

function M.resetSlotParams(specId, slotIndex, deps)
  local config = M.specConfig(specId)
  if type(config) ~= "table" or type(config.resetDefaults) ~= "function" then
    return false
  end
  config.resetDefaults(slotIndex, deps or {})
  return true
end

function M.remapParamPaths(spec, paramBase, remapFn)
  if type(spec) ~= "table" or type(paramBase) ~= "string" or paramBase == "" or type(remapFn) ~= "function" then
    return spec
  end
  local params = spec.ports and spec.ports.params or nil
  if type(params) == "table" then
    for i = 1, #params do
      local param = params[i]
      local path = param and tostring(param.path or "") or ""
      local nextPath = remapFn(path)
      if type(nextPath) == "string" and nextPath ~= "" then
        param.path = nextPath
      end
    end
  end
  spec.meta = spec.meta or {}
  spec.meta.paramBase = paramBase
  return spec
end

function M.applySpecParamRemap(spec, paramBase, rules)
  if type(rules) ~= "table" then
    return spec
  end

  local exact = type(rules.exact) == "table" and rules.exact or {}
  local patterns = type(rules.patterns) == "table" and rules.patterns or {}

  M.remapParamPaths(spec, paramBase, function(path)
    local suffix = exact[path]
    if type(suffix) == "string" and suffix ~= "" then
      return paramBase .. suffix
    end

    for i = 1, #patterns do
      local rule = patterns[i]
      if type(rule) == "table" and type(rule.match) == "string" and type(rule.toSuffixTemplate) == "string" then
        local captures = { path:match(rule.match) }
        if #captures > 0 then
          return paramBase .. interpolateTemplate(rule.toSuffixTemplate, captures)
        end
      end
    end

    return nil
  end)

  spec.meta = spec.meta or {}
  local clearMeta = type(rules.clearMeta) == "table" and rules.clearMeta or {}
  for i = 1, #clearMeta do
    local key = tostring(clearMeta[i] or "")
    if key ~= "" then
      spec.meta[key] = nil
    end
  end

  return spec
end

function M.patchSpecForInstance(specId, spec, paramBase)
  local rules = spec and spec.meta and spec.meta.paramPathRemap or nil
  if type(rules) == "table" then
    return M.applySpecParamRemap(spec, paramBase, rules)
  end
  local config = M.specConfig(specId)
  if type(config) == "table" and type(config.patchSpec) == "function" then
    return config.patchSpec(spec, paramBase)
  end
  return spec
end

function M.nextDynamicNodeId(ctx, specId)
  local serial = math.max(0, math.floor(tonumber(ctx and ctx._dynamicNodeSerial or 0))) + 1
  ctx._dynamicNodeSerial = serial
  return string.format("%s_inst_%d", tostring(specId or "node"), serial)
end

function M.createDynamicSpawnMeta(ctx, specId, deps)
  local slotIndex = M.nextAvailableSlot(ctx, specId)
  if slotIndex == nil then
    return nil
  end
  M.resetSlotParams(specId, slotIndex, deps)
  return {
    slotIndex = slotIndex,
    paramBase = M.buildParamBase(specId, slotIndex),
  }
end

function M.releaseDynamicSpawnMeta(ctx, specId, meta)
  if type(meta) == "table" and meta.slotIndex ~= nil then
    return M.freeSlot(ctx, specId, meta.slotIndex)
  end
  return false
end

function M.registerDynamicModuleSpec(ctx, specId, nodeId, meta)
  if not (ctx and ctx._rackModuleSpecs) then
    return nil
  end
  local base = ctx._rackModuleSpecs[tostring(specId or "")]
  if type(base) ~= "table" then
    return nil
  end

  local spec = RackLayout.makeRackModuleSpec(base)
  spec.id = tostring(nodeId or "")
  spec.name = tostring(base.name or specId or nodeId)
  spec.meta = spec.meta or {}
  spec.meta.specId = tostring(specId or "")
  spec.meta.componentId = tostring(spec.meta.componentId or "contentComponent")

  if type(meta) == "table" then
    for key, value in pairs(meta) do
      spec.meta[key] = value
    end
  end

  if type(spec.meta.paramBase) == "string" and spec.meta.paramBase ~= "" then
    M.patchSpecForInstance(specId, spec, spec.meta.paramBase)
  end

  ctx._rackModuleSpecs[spec.id] = spec
  _G.__midiSynthDynamicModuleSpecs = _G.__midiSynthDynamicModuleSpecs or {}
  _G.__midiSynthDynamicModuleSpecs[spec.id] = spec

  local info = ensureDynamicNodeInfoTable()
  info[spec.id] = {
    specId = tostring(specId or ""),
    slotIndex = spec.meta.slotIndex,
    paramBase = spec.meta.paramBase,
  }

  return spec
end

function M.unregisterDynamicModuleSpec(ctx, nodeId, deps)
  local id = tostring(nodeId or "")
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  if type(info) == "table" then
    local entry = info[id]
    if type(entry) == "table" then
      if entry.slotIndex ~= nil then
        M.resetSlotParams(entry.specId, entry.slotIndex, deps)
        M.freeSlot(ctx, entry.specId, entry.slotIndex)
      end
    end
    info[id] = nil
  end

  if ctx and ctx._rackModuleSpecs then
    ctx._rackModuleSpecs[id] = nil
  end
  if ctx and type(ctx._dynamicAdsrRuntime) == "table" then
    ctx._dynamicAdsrRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicArpRuntime) == "table" then
    ctx._dynamicArpRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicTransposeRuntime) == "table" then
    ctx._dynamicTransposeRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicVelocityMapperRuntime) == "table" then
    ctx._dynamicVelocityMapperRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicScaleQuantizerRuntime) == "table" then
    ctx._dynamicScaleQuantizerRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicNoteFilterRuntime) == "table" then
    ctx._dynamicNoteFilterRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicAttenuverterBiasRuntime) == "table" then
    ctx._dynamicAttenuverterBiasRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicLfoRuntime) == "table" then
    ctx._dynamicLfoRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicSlewRuntime) == "table" then
    ctx._dynamicSlewRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicSampleHoldRuntime) == "table" then
    ctx._dynamicSampleHoldRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicCompareRuntime) == "table" then
    ctx._dynamicCompareRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicCvMixRuntime) == "table" then
    ctx._dynamicCvMixRuntime[id] = nil
  end
  if ctx and type(ctx._dynamicRangeMapperRuntime) == "table" then
    ctx._dynamicRangeMapperRuntime[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthAdsrViewState) == "table" then
    _G.__midiSynthAdsrViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthArpViewState) == "table" then
    _G.__midiSynthArpViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthTransposeViewState) == "table" then
    _G.__midiSynthTransposeViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthVelocityMapperViewState) == "table" then
    _G.__midiSynthVelocityMapperViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthScaleQuantizerViewState) == "table" then
    _G.__midiSynthScaleQuantizerViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthNoteFilterViewState) == "table" then
    _G.__midiSynthNoteFilterViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthAttenuverterBiasViewState) == "table" then
    _G.__midiSynthAttenuverterBiasViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthLfoViewState) == "table" then
    _G.__midiSynthLfoViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthSlewViewState) == "table" then
    _G.__midiSynthSlewViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthSampleHoldViewState) == "table" then
    _G.__midiSynthSampleHoldViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthCompareViewState) == "table" then
    _G.__midiSynthCompareViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthCvMixViewState) == "table" then
    _G.__midiSynthCvMixViewState[id] = nil
  end
  if type(_G) == "table" and type(_G.__midiSynthRangeMapperViewState) == "table" then
    _G.__midiSynthRangeMapperViewState[id] = nil
  end
  local dynamicSpecs = type(_G) == "table" and _G.__midiSynthDynamicModuleSpecs or nil
  if type(dynamicSpecs) == "table" then
    dynamicSpecs[id] = nil
  end
end

return M

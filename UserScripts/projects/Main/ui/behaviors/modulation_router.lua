-- Modulation Router Module
-- Extracted from midisynth.lua
-- Handles modulation routing for voices and controls

local M = {}

-- Dependencies (provided via init)
local deps = {}
local VOICE_COUNT = 8

local function clamp(value, minVal, maxVal)
  return math.max(minVal or 0, math.min(maxVal or 1, tonumber(value) or 0))
end

local function noteToFreq(note)
  return 440.0 * (2.0 ^ (((tonumber(note) or 69.0) - 69.0) / 12.0))
end

local function velocityToAmp(velocity)
  local v = tonumber(velocity) or 0
  return math.max(0, math.min(0.40, 0.03 + (v / 127.0) * 0.37))
end

local function voiceFreqPath(index)
  return string.format("/midi/synth/voice/%d/freq", index)
end

local function voiceAmpPath(index)
  return string.format("/midi/synth/voice/%d/amp", index)
end

local function voiceGatePath(index)
  return string.format("/midi/synth/voice/%d/gate", index)
end

local function isLegacyOscillatorGateRouteConnected(ctx)
  local router = ctx and ctx._rackControlRouter or nil
  if not (router and router.getRoutesForTarget) then
    return false
  end

  local function hasDirectLegacyAdsrSource(targetId)
    local routes = router:getRoutesForTarget(targetId) or {}
    for i = 1, #routes do
      local route = routes[i]
      local sourceId = tostring(
        (route and route.source and route.source.id)
        or (route and route.route and route.route.source)
        or (route and route.compiled and route.compiled.sourceHandle)
        or ""
      )
      if sourceId == "adsr.voice" or sourceId == "adsr.env" or sourceId == "adsr.inv" then
        return true
      end
    end
    return false
  end

  return hasDirectLegacyAdsrSource("oscillator.gate") or hasDirectLegacyAdsrSource("oscillator.voice")
end

local function hasCanonicalOscillatorGateRoute(ctx)
  local router = ctx and ctx._rackControlRouter or nil
  if not (router and router.isTargetConnected) then
    return false
  end
  return not not (router:isTargetConnected("oscillator.gate") or router:isTargetConnected("oscillator.voice"))
end

local function hasAnyOscillatorGateRoute(ctx)
  local router = ctx and ctx._rackControlRouter or nil
  if not (router and router.isTargetConnected) then
    return false
  end
  if hasCanonicalOscillatorGateRoute(ctx) then
    return true
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  if type(info) == "table" then
    for moduleId, entry in pairs(info) do
      if type(entry) == "table" and (tostring(entry.specId or "") == "rack_oscillator" or tostring(entry.specId or "") == "rack_sample") then
        if router:isTargetConnected(tostring(moduleId) .. ".gate") or router:isTargetConnected(tostring(moduleId) .. ".voice") then
          return true
        end
      end
    end
  end
  return false
end

local function dynamicRackOscAdsrGateSlots(ctx)
  local out = {}
  local router = ctx and ctx._rackControlRouter or nil
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  if not (router and router.getRoutesForTarget and type(info) == "table") then
    return out
  end

  for moduleId, entry in pairs(info) do
    if type(entry) == "table"
      and (tostring(entry.specId or "") == "rack_oscillator" or tostring(entry.specId or "") == "rack_sample")
      and tonumber(entry.slotIndex) ~= nil then
      local routes = router:getRoutesForTarget(tostring(moduleId) .. ".gate") or {}
      for i = 1, #routes do
        local route = routes[i]
        local sourceId = tostring(route and route.source and route.source.id or route and route.route and route.route.source or "")
        if sourceId == "adsr.env" then
          out[#out + 1] = {
            moduleId = tostring(moduleId),
            slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 1)),
            specId = tostring(entry.specId or ""),
          }
          break
        end
      end
    end
  end

  return out
end

-- Write voice target value with caching
M._writeVoiceTargetValue = function(ctx, path, value, meta, cacheKey, epsilon)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local nextValue = tonumber(value) or 0.0
  local eps = tonumber(epsilon) or 0.0001
  if type(ctx) == "table" then
    ctx._voiceTargetWriteCache = ctx._voiceTargetWriteCache or {}
    local key = tostring(cacheKey or path)
    local previous = ctx._voiceTargetWriteCache[key]
    local liveValue = tonumber(deps.readParam(path, nextValue)) or nextValue
    if previous ~= nil
      and math.abs((tonumber(previous) or 0.0) - nextValue) <= eps
      and math.abs(liveValue - nextValue) <= eps then
      return false
    end
    ctx._voiceTargetWriteCache[key] = nextValue
  end
  deps.setPath(path, nextValue, meta)
  return true
end

-- Resolve dynamic voice bundle sample
local function resolveDynamicVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local clampFn = clampFn or clamp
  local resolved = require("velocity_mapper_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("scale_quantizer_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("note_filter_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("transpose_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("arp_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(resolved) == "table" then
    return resolved
  end
  return require("adsr_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
end

-- Resolve dynamic voice modulation source
local function resolveDynamicVoiceModulationSource(ctx, sourceId, source, voiceCount)
  local resolved = require("velocity_mapper_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("scale_quantizer_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("note_filter_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("transpose_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  if type(resolved) == "table" then
    return resolved
  end
  resolved = require("arp_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  if type(resolved) == "table" then
    return resolved
  end
  return require("adsr_runtime").resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
end

-- Apply control modulation target
local function applyControlModulationTarget(ctx, targetId, target, value, meta)
  local targetMeta = type(target) == "table" and type(target.meta) == "table" and target.meta or {}
  local moduleId = tostring(targetMeta.moduleId or "")
  local portId = tostring(targetMeta.portId or "")
  local dynamicInfo = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local dynamicEntry = type(dynamicInfo) == "table" and dynamicInfo[moduleId] or nil
  local specId = tostring((type(dynamicEntry) == "table" and dynamicEntry.specId) or targetMeta.specId or "")

  if specId == "attenuverter_bias" then
    return require("attenuverter_bias_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "lfo" then
    return require("lfo_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "slew" then
    return require("slew_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "sample_hold" then
    return require("sample_hold_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "compare" then
    return require("compare_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "cv_mix" then
    return require("cv_mix_runtime").applyInputScalar(ctx, moduleId, portId, value, meta) == true
  end
  if specId == "range_mapper" then
    local runtime = require("range_mapper_runtime")
    if type(runtime.applyInputScalar) == "function" then
      return runtime.applyInputScalar(ctx, moduleId, portId, value, meta) == true
    end
    if type(runtime.processInput) == "function" then
      return runtime.processInput(ctx, moduleId, portId, value, meta) == true
    end
  end

  return false
end

-- Resolve control modulation source
local function resolveControlModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.") or ""))
  local dynamicInfo = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local dynamicEntry = type(dynamicInfo) == "table" and dynamicInfo[moduleId] or nil
  local specId = tostring((type(dynamicEntry) == "table" and dynamicEntry.specId) or sourceMeta.specId or "")

  local function resolvedValue(runtime)
    if runtime and type(runtime.resolveScalarModulationSource) == "function" then
      local resolved = runtime.resolveScalarModulationSource(ctx, sourceId, source)
      if type(resolved) == "table" then
        return tonumber(resolved.rawSourceValue) or 0.0
      end
    end
    return nil
  end

  if specId == "attenuverter_bias" then
    return resolvedValue(require("attenuverter_bias_runtime"))
  end
  if specId == "lfo" then
    return resolvedValue(require("lfo_runtime"))
  end
  if specId == "slew" then
    return resolvedValue(require("slew_runtime"))
  end
  if specId == "sample_hold" then
    return resolvedValue(require("sample_hold_runtime"))
  end
  if specId == "compare" then
    return resolvedValue(require("compare_runtime"))
  end
  if specId == "cv_mix" then
    return resolvedValue(require("cv_mix_runtime"))
  end
  if specId == "range_mapper" then
    local runtime = require("range_mapper_runtime")
    local resolved = resolvedValue(runtime)
    if resolved ~= nil then
      return resolved
    end
    if type(runtime.getOutput) == "function" then
      return tonumber(runtime.getOutput(ctx, moduleId)) or 0.0
    end
  end

  return nil
end

-- Apply voice modulation target
local function applyVoiceModulationTarget(ctx, targetId, target, value, meta)
  local targetMeta = type(target) == "table" and type(target.meta) == "table" and target.meta or {}
  local moduleId = tostring(targetMeta.moduleId or "")
  local portId = tostring(targetMeta.portId or "")
  local dynamicInfo = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local dynamicEntry = type(dynamicInfo) == "table" and dynamicInfo[moduleId] or nil
  local specId = tostring((type(dynamicEntry) == "table" and dynamicEntry.specId) or targetMeta.specId or "")
  local slotIndex = tonumber((type(dynamicEntry) == "table" and dynamicEntry.slotIndex) or targetMeta.slotIndex)
  local voiceIndex = math.max(1, math.floor(tonumber(type(meta) == "table" and meta.voiceIndex or 1) or 1))
  local liveVoice = type(ctx) == "table" and type(ctx._voices) == "table" and ctx._voices[voiceIndex] or nil
  local action = type(meta) == "table" and meta.action or "apply"
  local routeActive = (tonumber(value) or 0.0) > 0.5 and action ~= "restore"
  local bundle = type(meta) == "table" and type(meta.bundleSample) == "table" and meta.bundleSample or nil

  if specId == "adsr" and (portId == "midi" or portId == "gate" or portId == "retrig") then
    return require("adsr_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "arp" and portId == "voice_in" then
    return require("arp_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "transpose" and portId == "voice_in" then
    return require("transpose_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "velocity_mapper" and portId == "voice_in" then
    return require("velocity_mapper_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "scale_quantizer" and portId == "voice_in" then
    return require("scale_quantizer_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "note_filter" and portId == "voice_in" then
    return require("note_filter_runtime").applyInputVoice(ctx, moduleId, portId, value, meta, VOICE_COUNT, clamp)
  end

  if specId == "oscillator" and portId == "voice" then
    bundle = bundle or resolveDynamicVoiceBundleSample(ctx, type(meta) == "table" and meta.bundleSourceId or nil, type(meta) == "table" and meta.bundleSource or nil, voiceIndex, clamp)
      or {
      note = clamp(tonumber(liveVoice and liveVoice.note) or 60.0, 0.0, 127.0),
      gate = ((tonumber(liveVoice and liveVoice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      amp = clamp(tonumber(liveVoice and liveVoice.currentAmp) or 0.0, 0.0, 0.40),
    }
    local liveFreq = noteToFreq(bundle.note or 60.0)
    local liveGate = ((tonumber(bundle.noteGate) or tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
    local liveAmp = clamp(tonumber(bundle.currentAmp) or tonumber(bundle.amp) or tonumber(bundle.targetAmp) or 0.0, 0.0, 0.40)
    local writeMeta = {
      source = "modulation_runtime",
      action = action,
      target = tostring(targetId or ""),
      voiceIndex = voiceIndex,
    }
    M._writeVoiceTargetValue(ctx, voiceFreqPath(voiceIndex), liveFreq, writeMeta, string.format("osc:%d:freq", voiceIndex), 0.0001)
    M._writeVoiceTargetValue(ctx, voiceGatePath(voiceIndex), routeActive and liveGate or 0.0, writeMeta, string.format("osc:%d:gate", voiceIndex), 0.0)
    M._writeVoiceTargetValue(ctx, voiceAmpPath(voiceIndex), routeActive and liveAmp or 0.0, writeMeta, string.format("osc:%d:amp", voiceIndex), 0.0001)
    return true
  end

  if slotIndex == nil then
    return false
  end

  if specId == "rack_oscillator" then
    if portId == "voice" then
      bundle = bundle or resolveDynamicVoiceBundleSample(ctx, type(meta) == "table" and meta.bundleSourceId or nil, type(meta) == "table" and meta.bundleSource or nil, voiceIndex, clamp)
        or {
        note = clamp(tonumber(liveVoice and liveVoice.note) or 60.0, 0.0, 127.0),
        gate = ((tonumber(liveVoice and liveVoice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
        amp = clamp(tonumber(liveVoice and liveVoice.currentAmp) or 0.0, 0.0, 0.40),
      }
      local liveNote = clamp(tonumber(bundle.note) or 60.0, 0.0, 127.0)
      local liveAmp = clamp(tonumber(bundle.currentAmp) or tonumber(bundle.amp) or tonumber(bundle.targetAmp) or 0.0, 0.0, 0.40)
      local writeMeta = {
        source = "modulation_runtime",
        action = action,
        target = tostring(targetId or ""),
        voiceIndex = voiceIndex,
      }
      M._writeVoiceTargetValue(ctx, deps.ParameterBinder.dynamicOscillatorVoiceVOctPath(slotIndex, voiceIndex), liveNote, writeMeta, string.format("rackosc:%d:%d:v_oct", slotIndex, voiceIndex), 0.0001)
      M._writeVoiceTargetValue(ctx, deps.ParameterBinder.dynamicOscillatorVoiceGatePath(slotIndex, voiceIndex), routeActive and liveAmp or 0.0, writeMeta, string.format("rackosc:%d:%d:gate", slotIndex, voiceIndex), 0.0001)
      return true
    end

    local path = nil
    if portId == "gate" then
      path = deps.ParameterBinder.dynamicOscillatorVoiceGatePath(slotIndex, voiceIndex)
    elseif portId == "v_oct" then
      path = deps.ParameterBinder.dynamicOscillatorVoiceVOctPath(slotIndex, voiceIndex)
    elseif portId == "fm" then
      path = deps.ParameterBinder.dynamicOscillatorVoiceFmPath(slotIndex, voiceIndex)
    elseif portId == "pw_cv" then
      path = deps.ParameterBinder.dynamicOscillatorVoicePwCvPath(slotIndex, voiceIndex)
    end

    if type(path) ~= "string" or path == "" then
      return false
    end

    M._writeVoiceTargetValue(ctx, path, tonumber(value) or 0.0, {
      source = "modulation_runtime",
      action = action,
      target = tostring(targetId or ""),
      voiceIndex = voiceIndex,
    }, string.format("voice-target:%s:%d:%s", tostring(moduleId or ""), voiceIndex, tostring(portId or "")), 0.0001)
    return true
  end

  if specId == "rack_sample" then
    if portId == "voice" then
      bundle = bundle or resolveDynamicVoiceBundleSample(ctx, type(meta) == "table" and meta.bundleSourceId or nil, type(meta) == "table" and meta.bundleSource or nil, voiceIndex, clamp)
        or {
        note = clamp(tonumber(liveVoice and liveVoice.note) or 60.0, 0.0, 127.0),
        gate = ((tonumber(liveVoice and liveVoice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
        amp = clamp(tonumber(liveVoice and liveVoice.currentAmp) or 0.0, 0.0, 1.0),
      }
      local liveNote = clamp(tonumber(bundle.note) or 60.0, 0.0, 127.0)
      local liveAmp = clamp(tonumber(bundle.currentAmp) or tonumber(bundle.amp) or tonumber(bundle.targetAmp) or 0.0, 0.0, 1.0)
      local writeMeta = {
        source = "modulation_runtime",
        action = action,
        target = tostring(targetId or ""),
        voiceIndex = voiceIndex,
      }
      M._writeVoiceTargetValue(ctx, deps.ParameterBinder.dynamicSampleVoiceVOctPath(slotIndex, voiceIndex), liveNote, writeMeta, string.format("racksample:%d:%d:v_oct", slotIndex, voiceIndex), 0.0001)
      M._writeVoiceTargetValue(ctx, deps.ParameterBinder.dynamicSampleVoiceGatePath(slotIndex, voiceIndex), routeActive and liveAmp or 0.0, writeMeta, string.format("racksample:%d:%d:gate", slotIndex, voiceIndex), 0.0001)
      return true
    end

    local path = nil
    if portId == "gate" then
      path = deps.ParameterBinder.dynamicSampleVoiceGatePath(slotIndex, voiceIndex)
    elseif portId == "v_oct" then
      path = deps.ParameterBinder.dynamicSampleVoiceVOctPath(slotIndex, voiceIndex)
    end

    if type(path) ~= "string" or path == "" then
      return false
    end

    M._writeVoiceTargetValue(ctx, path, tonumber(value) or 0.0, {
      source = "modulation_runtime",
      action = action,
      target = tostring(targetId or ""),
      voiceIndex = voiceIndex,
    }, string.format("voice-target:%s:%d:%s", tostring(moduleId or ""), voiceIndex, tostring(portId or "")), 0.0001)
    return true
  end

  return false
end

-- Apply implicit rack oscillator keyboard pitch
local function applyImplicitRackOscillatorKeyboardPitch(ctx, voiceIndex, note)
  local targetVoiceIndex = math.max(1, math.floor(tonumber(voiceIndex) or 1))
  local targetNote = clamp(tonumber(note) or 60.0, 0.0, 127.0)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local router = ctx and ctx._rackControlRouter or nil
  if type(info) ~= "table" then
    return false
  end

  local applied = false
  for moduleId, entry in pairs(info) do
    if type(entry) == "table" and tonumber(entry.slotIndex) ~= nil then
      local specId = tostring(entry.specId or "")
      local pitchTargetId = string.format("%s.v_oct", tostring(moduleId or ""))
      local voiceTargetId = string.format("%s.voice", tostring(moduleId or ""))
      local explicitlyPatched = router and router.isTargetConnected and (router:isTargetConnected(pitchTargetId) or router:isTargetConnected(voiceTargetId)) or false
      if not explicitlyPatched and specId == "rack_oscillator" then
        deps.setPath(deps.ParameterBinder.dynamicOscillatorVoiceVOctPath(entry.slotIndex, targetVoiceIndex), targetNote, {
          source = "legacy_keyboard_parity",
          action = "implicit_pitch",
          moduleId = tostring(moduleId or ""),
          voiceIndex = targetVoiceIndex,
        })
        deps.setPath(deps.ParameterBinder.dynamicOscillatorManualPitchPath(entry.slotIndex), targetNote, {
          source = "legacy_keyboard_parity",
          action = "implicit_manual_pitch",
          moduleId = tostring(moduleId or ""),
        })
        applied = true
      elseif not explicitlyPatched and specId == "rack_sample" then
        deps.setPath(deps.ParameterBinder.dynamicSampleVoiceVOctPath(entry.slotIndex, targetVoiceIndex), targetNote, {
          source = "legacy_keyboard_parity",
          action = "implicit_pitch",
          moduleId = tostring(moduleId or ""),
          voiceIndex = targetVoiceIndex,
        })
        applied = true
      end
    end
  end

  return applied
end

-- Get combined modulation target state
local function getCombinedModTargetState(ctx, path)
  local targetPath = tostring(path or "")
  if targetPath == "" then
    return nil
  end

  local runtimes = {
    ctx and ctx._rackModRuntime or nil,
    ctx and ctx._modRuntime or nil,
  }

  for i = 1, #runtimes do
    local runtime = runtimes[i]
    if runtime and runtime.getTargetState then
      local state = runtime:getTargetState(targetPath, deps.readParam)
      if state ~= nil then
        return state
      end
    end
  end

  return nil
end

-- Exported functions
M.applyVoiceModulationTarget = applyVoiceModulationTarget
M.applyControlModulationTarget = applyControlModulationTarget
M.resolveDynamicVoiceModulationSource = resolveDynamicVoiceModulationSource
M.resolveControlModulationSource = resolveControlModulationSource
M.getCombinedModTargetState = getCombinedModTargetState
M.applyImplicitRackOscillatorKeyboardPitch = applyImplicitRackOscillatorKeyboardPitch
M.resolveDynamicVoiceBundleSample = resolveDynamicVoiceBundleSample
M.noteToFreq = noteToFreq
M.velocityToAmp = velocityToAmp
M._isLegacyOscillatorGateRouteConnected = isLegacyOscillatorGateRouteConnected
M._hasCanonicalOscillatorGateRoute = hasCanonicalOscillatorGateRoute
M._hasAnyOscillatorGateRoute = hasAnyOscillatorGateRoute
M._dynamicRackOscAdsrGateSlots = dynamicRackOscAdsrGateSlots

function M.attach(midiSynth)
  deps.midiSynth = midiSynth
  midiSynth._writeVoiceTargetValue = M._writeVoiceTargetValue
  midiSynth._applyVoiceModulationTarget = applyVoiceModulationTarget
  midiSynth._applyControlModulationTarget = applyControlModulationTarget
  midiSynth._resolveControlModulationSource = resolveControlModulationSource
  midiSynth.applyImplicitRackOscillatorKeyboardPitch = applyImplicitRackOscillatorKeyboardPitch
  midiSynth.getCombinedModTargetState = getCombinedModTargetState
  midiSynth._isLegacyOscillatorGateRouteConnected = isLegacyOscillatorGateRouteConnected
  midiSynth._hasCanonicalOscillatorGateRoute = hasCanonicalOscillatorGateRoute
  midiSynth._hasAnyOscillatorGateRoute = hasAnyOscillatorGateRoute
  midiSynth._dynamicRackOscAdsrGateSlots = dynamicRackOscAdsrGateSlots
end

function M.init(options)
  options = options or {}
  deps.setPath = options.setPath
  deps.readParam = options.readParam
  deps.ParameterBinder = options.ParameterBinder or require("parameter_binder")
end

return M
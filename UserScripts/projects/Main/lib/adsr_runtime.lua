local M = {}

local function createAdsrRuntimeVoice(note, amp)
  return {
    active = false,
    note = tonumber(note) or 60.0,
    gate = 0,
    targetAmp = tonumber(amp) or 0.0,
    currentAmp = 0.0,
    envelopeStage = "idle",
    envelopeLevel = 0.0,
    envelopeTime = 0.0,
    envelopeStartLevel = 0.0,
    eoc = 0.0,
    _retrigHigh = false,
  }
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicAdsrRuntime = ctx._dynamicAdsrRuntime or {}
  _G.__midiSynthDynamicAdsrRuntime = ctx._dynamicAdsrRuntime
  _G.__midiSynthAdsrViewState = _G.__midiSynthAdsrViewState or {}
  return ctx._dynamicAdsrRuntime
end

function M.resolveModuleState(ctx, moduleId, voiceCount)
  local id = tostring(moduleId or "")
  if id == "adsr" then
    return {
      moduleId = "adsr",
      values = ctx._adsr,
      voices = ctx._voices,
    }
  end

  local store = M.ensureDynamicRuntime(ctx)
  local state = store[id]
  if state ~= nil then
    return state
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local meta = type(info) == "table" and info[id] or nil
  state = {
    moduleId = id,
    slotIndex = tonumber(type(meta) == "table" and meta.slotIndex or nil),
    paramBase = type(meta) == "table" and type(meta.paramBase) == "string" and meta.paramBase or nil,
    values = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 },
    voices = {},
  }
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 8)) do
    state.voices[i] = createAdsrRuntimeVoice(60.0, 0.0)
  end
  store[id] = state
  return state
end

function M.refreshModuleParams(ctx, state, readParam, clamp)
  if not (ctx and type(state) == "table" and type(readParam) == "function") then
    return state and state.values or nil
  end
  local paramBase = type(state.paramBase) == "string" and state.paramBase or nil
  if paramBase == nil or paramBase == "" then
    return state.values
  end
  state.values.attack = tonumber(readParam(paramBase .. "/attack", state.values.attack or 0.05)) or 0.05
  state.values.decay = tonumber(readParam(paramBase .. "/decay", state.values.decay or 0.2)) or 0.2
  local sustain = tonumber(readParam(paramBase .. "/sustain", state.values.sustain or 0.7)) or 0.7
  state.values.sustain = type(clamp) == "function" and clamp(sustain, 0.0, 1.0) or sustain
  state.values.release = tonumber(readParam(paramBase .. "/release", state.values.release or 0.4)) or 0.4
  return state.values
end

function M.advanceVoice(voice, adsr, dt)
  if not (voice and adsr) then
    return 0.0
  end

  voice.eoc = 0.0
  local gate = (tonumber(voice.gate) or 0.0) > 0.5 and 1.0 or 0.0
  local level = tonumber(voice.envelopeLevel) or 0.0
  local stage = tostring(voice.envelopeStage or "idle")

  if gate > 0.5 then
    if stage == "idle" or stage == "release" then
      stage = "attack"
      voice.envelopeStartLevel = level
    end

    if stage == "attack" then
      local attackTime = math.max(0.001, tonumber(adsr.attack) or 0.05)
      local progress = (tonumber(voice.envelopeTime) or 0.0) / attackTime
      if progress >= 1.0 then
        level = 1.0
        stage = "decay"
        voice.envelopeTime = 0.0
        voice.envelopeStartLevel = 1.0
      else
        local startLevel = tonumber(voice.envelopeStartLevel) or 0.0
        level = startLevel + (1.0 - startLevel) * progress
      end
    elseif stage == "decay" then
      local decayTime = math.max(0.001, tonumber(adsr.decay) or 0.2)
      local progress = (tonumber(voice.envelopeTime) or 0.0) / decayTime
      local sustainLevel = tonumber(adsr.sustain) or 0.7
      if progress >= 1.0 then
        level = sustainLevel
        stage = "sustain"
      else
        level = 1.0 - (1.0 - sustainLevel) * progress
      end
    elseif stage == "sustain" then
      level = tonumber(adsr.sustain) or 0.7
    end
  else
    if stage ~= "release" and stage ~= "idle" then
      stage = "release"
      voice.envelopeTime = 0.0
      voice.envelopeStartLevel = level
    end

    if stage == "release" then
      local releaseTime = math.max(0.001, tonumber(adsr.release) or 0.4)
      local progress = (tonumber(voice.envelopeTime) or 0.0) / releaseTime
      if progress >= 1.0 then
        level = 0.0
        stage = "idle"
        voice.eoc = 1.0
      else
        local startLevel = tonumber(voice.envelopeStartLevel) or 0.0
        level = startLevel * (1.0 - progress)
      end
    end
  end

  voice.envelopeStage = stage
  voice.envelopeLevel = level
  voice.envelopeTime = (tonumber(voice.envelopeTime) or 0.0) + dt
  voice.currentAmp = level * math.max(0.0, tonumber(voice.targetAmp) or 0.0)
  return voice.currentAmp
end

function M.publishViewState(ctx)
  _G.__midiSynthAdsrViewState = _G.__midiSynthAdsrViewState or {}
  _G.__midiSynthAdsrViewState["adsr"] = {
    values = {
      attack = tonumber(ctx._adsr and ctx._adsr.attack) or 0.05,
      decay = tonumber(ctx._adsr and ctx._adsr.decay) or 0.2,
      sustain = tonumber(ctx._adsr and ctx._adsr.sustain) or 0.7,
      release = tonumber(ctx._adsr and ctx._adsr.release) or 0.4,
    },
    voices = ctx._voices,
  }

  local runtime = ctx and ctx._dynamicAdsrRuntime or nil
  if type(runtime) == "table" then
    for moduleId, state in pairs(runtime) do
      if type(state) == "table" then
        _G.__midiSynthAdsrViewState[tostring(moduleId)] = {
          values = state.values,
          voices = state.voices,
        }
      end
    end
  end
end

function M.resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clamp)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local moduleId = tostring(sourceMeta.moduleId or "")
  local index = math.max(1, math.floor(tonumber(voiceIndex) or 1))

  if tostring(sourceId or "") == "midi.voice" then
    local voice = ctx and ctx._midiVoices and ctx._midiVoices[index] or nil
    local noteGate = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0
    return {
      note = type(clamp) == "function" and clamp(tonumber(voice and voice.note) or 60.0, 0.0, 127.0) or (tonumber(voice and voice.note) or 60.0),
      gate = noteGate,
      noteGate = noteGate,
      amp = math.max(0.0, tonumber(voice and voice.targetAmp) or 0.0),
      targetAmp = math.max(0.0, tonumber(voice and voice.targetAmp) or 0.0),
      currentAmp = math.max(0.0, tonumber(voice and voice.currentAmp) or tonumber(voice and voice.targetAmp) or 0.0),
      envelopeLevel = math.max(0.0, tonumber(voice and voice.envelopeLevel) or 0.0),
      envelopeStage = tostring(voice and voice.envelopeStage or (((tonumber(voice and voice.gate) or 0.0) > 0.5) and "sustain" or "idle")),
      active = type(voice) == "table" and (voice.active == true or noteGate > 0.5),
      sourceVoiceIndex = index,
    }
  end

  if tostring(sourceId or "") == "adsr.voice" or (tostring(sourceMeta.specId or "") == "adsr" and tostring(sourceMeta.portId or "") == "voice") then
    local state = M.resolveModuleState(ctx, moduleId ~= "" and moduleId or "adsr", #((ctx and ctx._voices) or {}))
    local voice = state and state.voices and state.voices[index] or nil
    local noteGate = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0
    local active = (noteGate > 0.5) or tostring(voice and voice.envelopeStage or "idle") ~= "idle"
    return {
      note = type(clamp) == "function" and clamp(tonumber(voice and voice.note) or 60.0, 0.0, 127.0) or (tonumber(voice and voice.note) or 60.0),
      gate = noteGate,
      noteGate = noteGate,
      amp = math.max(0.0, tonumber(voice and voice.currentAmp) or 0.0),
      targetAmp = math.max(0.0, tonumber(voice and voice.targetAmp) or tonumber(voice and voice.currentAmp) or 0.0),
      currentAmp = math.max(0.0, tonumber(voice and voice.currentAmp) or 0.0),
      envelopeLevel = math.max(0.0, tonumber(voice and voice.envelopeLevel) or 0.0),
      envelopeStage = tostring(voice and voice.envelopeStage or "idle"),
      active = active,
      sourceVoiceIndex = index,
    }
  end

  local transposeBundle = require("transpose_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, index, clamp)
  if type(transposeBundle) == "table" then
    return transposeBundle
  end

  local arpBundle = require("arp_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, index, clamp)
  if type(arpBundle) == "table" then
    return arpBundle
  end

  return nil
end

function M.resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or tostring(sourceId or ""):match("%.([%a_]+)$") or "")
  local moduleId = tostring(sourceMeta.moduleId or ((tostring(sourceId or ""):match("^([^.]+)%.") or "")))

  local isCanonicalAdsrSource = sourceId == "adsr.voice" or sourceId == "adsr.env" or sourceId == "adsr.inv" or sourceId == "adsr.eoc"
  if not isCanonicalAdsrSource and specId ~= "adsr" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId ~= "" and moduleId or "adsr", voiceCount)
  if not (state and type(state.voices) == "table") then
    return nil
  end

  local out = {}
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
    local voice = state.voices[i]
    local raw = 0.0
    local bundleSnapshot = nil
    if portId == "voice" then
      raw = (((tonumber(voice and voice.gate) or 0.0) > 0.5) or tostring(voice and voice.envelopeStage or "idle") ~= "idle") and 1.0 or 0.0
      if type(voice) == "table" then
        local note = tonumber(voice.note) or 60.0
        note = math.max(0.0, math.min(127.0, note))
        bundleSnapshot = {
          note = note,
          gate = ((((tonumber(voice.gate) or 0.0) > 0.5) or tostring(voice.envelopeStage or "idle") ~= "idle") and 1.0 or 0.0),
          noteGate = ((tonumber(voice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
          amp = math.max(0.0, tonumber(voice.currentAmp) or 0.0),
          targetAmp = math.max(0.0, tonumber(voice.targetAmp) or tonumber(voice.currentAmp) or 0.0),
          currentAmp = math.max(0.0, tonumber(voice.currentAmp) or 0.0),
          envelopeLevel = math.max(0.0, tonumber(voice.envelopeLevel) or 0.0),
          envelopeStage = tostring(voice.envelopeStage or "idle"),
          active = (((tonumber(voice.gate) or 0.0) > 0.5) or tostring(voice.envelopeStage or "idle") ~= "idle"),
          sourceVoiceIndex = i,
        }
      end
    elseif portId == "env" then
      raw = tonumber(voice and voice.envelopeLevel) or 0.0
    elseif portId == "inv" then
      raw = 1.0 - (tonumber(voice and voice.envelopeLevel) or 0.0)
    elseif portId == "eoc" then
      raw = tonumber(voice and voice.eoc) or 0.0
    end
    out[#out + 1] = { voiceIndex = i, rawSourceValue = raw, bundleSnapshot = bundleSnapshot }
  end
  return out
end

function M.applyInputVoice(ctx, moduleId, portId, value, meta, voiceCount, clamp)
  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  if not (state and state.voices) then
    return tostring(moduleId or "") == "adsr"
  end

  local voiceIndex = math.max(1, math.floor(tonumber(type(meta) == "table" and meta.voiceIndex or 1) or 1))
  local voice = state.voices[voiceIndex]
  if not voice then
    return false
  end

  local action = type(meta) == "table" and tostring(meta.action or "apply") or "apply"
  local bundleSource = type(meta) == "table" and meta.bundleSource or nil
  local bundleSourceId = type(meta) == "table" and meta.bundleSourceId or nil

  if portId == "midi" then
    local bundle = type(meta) == "table" and type(meta.bundleSample) == "table" and meta.bundleSample
      or M.resolveVoiceBundleSample(ctx, bundleSourceId, bundleSource, voiceIndex, clamp)
    local gate = (action ~= "restore" and type(bundle) == "table" and (tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
    if type(bundle) == "table" then
      local note = tonumber(bundle.note) or voice.note or 60.0
      voice.note = type(clamp) == "function" and clamp(note, 0.0, 127.0) or note
      voice.targetAmp = math.max(0.0, tonumber(bundle.targetAmp) or tonumber(bundle.amp) or tonumber(bundle.currentAmp) or voice.targetAmp or 0.0)
    end
    if gate > 0.5 and (tonumber(voice.gate) or 0.0) <= 0.5 then
      voice.envelopeStage = "attack"
      voice.envelopeTime = 0.0
      voice.envelopeStartLevel = tonumber(voice.envelopeLevel) or 0.0
      voice.active = true
    end
    voice.gate = gate
    if gate <= 0.5 and tostring(voice.envelopeStage or "idle") == "idle" then
      voice.active = false
    end
    return true
  elseif portId == "gate" then
    local gate = (action ~= "restore" and (tonumber(value) or 0.0) > 0.5) and 1.0 or 0.0
    if gate > 0.5 and (tonumber(voice.gate) or 0.0) <= 0.5 then
      voice.envelopeStage = "attack"
      voice.envelopeTime = 0.0
      voice.envelopeStartLevel = tonumber(voice.envelopeLevel) or 0.0
      voice.active = true
      if (tonumber(voice.targetAmp) or 0.0) <= 0.0001 then
        voice.targetAmp = 1.0
      end
    end
    voice.gate = gate
    return true
  elseif portId == "retrig" then
    local triggerHigh = action ~= "restore" and (tonumber(value) or 0.0) > 0.5
    if triggerHigh and not voice._retrigHigh then
      voice.envelopeStage = "attack"
      voice.envelopeTime = 0.0
      voice.envelopeStartLevel = tonumber(voice.envelopeLevel) or 0.0
      voice.active = true
    end
    voice._retrigHigh = triggerHigh
    return true
  end

  return false
end

function M.updateDynamicModules(ctx, dt, readParam, clamp, voiceCount)
  local runtime = ctx and ctx._dynamicAdsrRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      local values = M.refreshModuleParams(ctx, state, readParam, clamp)
      for voiceIndex = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
        local voice = state.voices and state.voices[voiceIndex] or nil
        if voice then
          M.advanceVoice(voice, values, dt)
          if ((tonumber(voice.gate) or 0.0) <= 0.5) and tostring(voice.envelopeStage or "idle") == "idle" then
            voice.active = false
          end
        end
      end
    end
  end

  M.publishViewState(ctx)
end

return M

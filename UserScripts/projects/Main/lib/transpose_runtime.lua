local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function readLiveParam(path, fallback)
  if type(path) ~= "string" or path == "" then
    return fallback
  end
  if type(_G.getParam) == "function" then
    local ok, value = pcall(_G.getParam, path)
    if ok and value ~= nil then
      return tonumber(value) or fallback
    end
  end
  return fallback
end

local function makeInputVoice()
  return {
    note = 60.0,
    gate = 0.0,
    noteGate = 0.0,
    amp = 0.0,
    targetAmp = 0.0,
    currentAmp = 0.0,
    envelopeLevel = 0.0,
    envelopeStage = "idle",
    active = false,
    sourceVoiceIndex = 1,
  }
end

local function ensureVoiceArray(store, count, factory)
  for i = 1, math.max(1, math.floor(tonumber(count) or 1)) do
    if store[i] == nil then
      store[i] = factory()
    end
  end
end

local function copyVoicePayload(target, source)
  target = target or {}
  source = type(source) == "table" and source or {}
  target.note = clamp(tonumber(source.note) or tonumber(target.note) or 60.0, 0.0, 127.0)
  target.gate = ((tonumber(source.gate) or 0.0) > 0.5) and 1.0 or 0.0
  target.noteGate = ((tonumber(source.noteGate) or tonumber(source.gate) or 0.0) > 0.5) and 1.0 or 0.0
  target.amp = math.max(0.0, tonumber(source.amp) or tonumber(source.currentAmp) or tonumber(source.targetAmp) or tonumber(target.amp) or 0.0)
  target.targetAmp = math.max(0.0, tonumber(source.targetAmp) or tonumber(source.amp) or tonumber(target.targetAmp) or 0.0)
  target.currentAmp = math.max(0.0, tonumber(source.currentAmp) or tonumber(source.amp) or tonumber(target.currentAmp) or 0.0)
  target.envelopeLevel = math.max(0.0, tonumber(source.envelopeLevel) or tonumber(target.envelopeLevel) or 0.0)
  target.envelopeStage = tostring(source.envelopeStage or target.envelopeStage or "idle")
  target.active = source.active == true or target.gate > 0.5 or target.noteGate > 0.5 or target.envelopeStage ~= "idle"
  target.sourceVoiceIndex = math.max(1, math.floor(tonumber(source.sourceVoiceIndex) or tonumber(target.sourceVoiceIndex) or 1))
  return target
end

local function voiceCountFromCtx(ctx)
  local voices = ctx and ctx._voices or nil
  if type(voices) == "table" and #voices > 0 then
    return #voices
  end
  return 8
end

local function resolveInputSnapshot(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  return require("arp_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    or require("adsr_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicTransposeRuntime = ctx._dynamicTransposeRuntime or {}
  _G.__midiSynthDynamicTransposeRuntime = ctx._dynamicTransposeRuntime
  _G.__midiSynthTransposeViewState = _G.__midiSynthTransposeViewState or {}
  return ctx._dynamicTransposeRuntime
end

function M.resolveModuleState(ctx, moduleId, voiceCount)
  local id = tostring(moduleId or "")
  local store = M.ensureDynamicRuntime(ctx)
  local state = store[id]
  if state ~= nil then
    state.voiceCount = math.max(1, math.floor(tonumber(voiceCount) or state.voiceCount or 8))
    ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
    return state
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local meta = type(info) == "table" and info[id] or nil
  state = {
    moduleId = id,
    slotIndex = tonumber(type(meta) == "table" and meta.slotIndex or nil),
    paramBase = type(meta) == "table" and type(meta.paramBase) == "string" and meta.paramBase or nil,
    values = { semitones = 0.0 },
    inputs = {},
    voiceCount = math.max(1, math.floor(tonumber(voiceCount) or 8)),
  }
  ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
  store[id] = state
  return state
end

function M.refreshModuleParams(ctx, state, readParam)
  if not (ctx and type(state) == "table" and type(readParam) == "function") then
    return state and state.values or nil
  end
  local paramBase = type(state.paramBase) == "string" and state.paramBase or nil
  if paramBase == nil or paramBase == "" then
    return state.values
  end
  state.values.semitones = math.floor(clamp(readParam(paramBase .. "/semitones", state.values.semitones or 0.0), -24.0, 24.0) + 0.5)
  return state.values
end

local function currentSemitoneOffset(state)
  if type(state) ~= "table" then
    return 0.0
  end
  local value = tonumber(state.values and state.values.semitones) or 0.0
  return math.floor(clamp(value, -24.0, 24.0) + 0.5)
end

function M.resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if portId ~= "voice" then
    return nil
  end
  if sourceKey ~= "transpose.voice" and specId ~= "transpose" then
    return nil
  end

  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.") or ""))
  local state = M.resolveModuleState(ctx, moduleId, voiceCountFromCtx(ctx))
  local index = math.max(1, math.floor(tonumber(voiceIndex) or 1))
  ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
  local input = state.inputs[index]
  if type(input) ~= "table" then
    return nil
  end

  local shifted = copyVoicePayload({}, input)
  local note = (tonumber(shifted.note) or 60.0) + currentSemitoneOffset(state)
  shifted.note = type(clampFn) == "function" and clampFn(note, 0.0, 127.0) or clamp(note, 0.0, 127.0)
  shifted.active = input.active == true or shifted.gate > 0.5 or shifted.noteGate > 0.5 or tostring(shifted.envelopeStage or "idle") ~= "idle"
  return shifted
end

function M.applyInputVoice(ctx, moduleId, portId, value, meta, voiceCount, clampFn)
  if tostring(portId or "") ~= "voice_in" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  local voiceIndex = math.max(1, math.floor(tonumber(type(meta) == "table" and meta.voiceIndex or 1) or 1))
  ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
  local input = state.inputs[voiceIndex]
  if type(input) ~= "table" then
    return false
  end

  local action = type(meta) == "table" and tostring(meta.action or "apply") or "apply"
  local bundle = type(meta) == "table" and type(meta.bundleSample) == "table" and meta.bundleSample
    or resolveInputSnapshot(ctx, type(meta) == "table" and meta.bundleSourceId or nil, type(meta) == "table" and meta.bundleSource or nil, voiceIndex, clampFn)
  if action == "restore" or type(bundle) ~= "table" then
    input.gate = 0.0
    input.noteGate = 0.0
    input.active = false
    input.envelopeStage = "idle"
    input.currentAmp = 0.0
    input.targetAmp = 0.0
    return true
  end

  copyVoicePayload(input, bundle)
  input.gate = ((tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
  input.noteGate = ((tonumber(bundle.noteGate) or tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
  input.active = bundle.active == true or input.gate > 0.5 or input.noteGate > 0.5 or tostring(input.envelopeStage or "idle") ~= "idle"
  input.sourceVoiceIndex = math.max(1, math.floor(tonumber(bundle.sourceVoiceIndex) or voiceIndex))
  return true
end

function M.resolveVoiceModulationSource(ctx, sourceId, source, voiceCount)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or tostring(sourceId or ""):match("%.([%a_]+)$") or "")
  local moduleId = tostring(sourceMeta.moduleId or ((tostring(sourceId or ""):match("^([^.]+)%.") or "")))
  if portId ~= "voice" then
    return nil
  end
  if tostring(sourceId or "") ~= "transpose.voice" and specId ~= "transpose" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  if not (state and type(state.inputs) == "table") then
    return nil
  end

  local out = {}
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
    local bundle = M.resolveVoiceBundleSample(ctx, sourceId, source, i, clamp)
    out[#out + 1] = {
      voiceIndex = i,
      rawSourceValue = ((tonumber(bundle and bundle.noteGate) or tonumber(bundle and bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      bundleSnapshot = bundle,
    }
  end
  return out
end

function M.publishViewState(ctx)
  _G.__midiSynthTransposeViewState = _G.__midiSynthTransposeViewState or {}
  local runtime = ctx and ctx._dynamicTransposeRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local activeInput = nil
      local activeVoices = {}
      local semitones = currentSemitoneOffset(state)
      for i = 1, #(state.inputs or {}) do
        local voice = state.inputs[i]
        if type(voice) == "table" and ((tonumber(voice.noteGate) or tonumber(voice.gate) or 0.0) > 0.5 or voice.active == true) then
          if activeInput == nil then
            activeInput = voice
          end
          local voiceNote = tonumber(voice.note)
          local sourceIdx = math.max(1, math.floor(tonumber(voice.sourceVoiceIndex) or i))
          if voiceNote ~= nil then
            activeVoices[#activeVoices + 1] = {
              inputNote = voiceNote,
              outputNote = clamp(voiceNote + semitones, 0.0, 127.0),
              voiceIndex = sourceIdx,
            }
          end
        end
      end
      local inputNote = tonumber(activeInput and activeInput.note) or nil
      local outputNote = inputNote ~= nil and clamp(inputNote + semitones, 0.0, 127.0) or nil
      _G.__midiSynthTransposeViewState[tostring(moduleId)] = {
        values = { semitones = semitones },
        inputNote = inputNote,
        outputNote = outputNote,
        active = activeInput ~= nil,
        activeVoices = activeVoices,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam, voiceCount)
  local runtime = ctx and ctx._dynamicTransposeRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      state.voiceCount = math.max(1, math.floor(tonumber(voiceCount) or state.voiceCount or 8))
      ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
      M.refreshModuleParams(ctx, state, readParam)
    end
  end

  M.publishViewState(ctx)
end

return M

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

local function makeInactiveVoice(source)
  local inactive = copyVoicePayload({}, source)
  inactive.gate = 0.0
  inactive.noteGate = 0.0
  inactive.amp = 0.0
  inactive.targetAmp = 0.0
  inactive.currentAmp = 0.0
  inactive.envelopeLevel = 0.0
  inactive.active = false
  return inactive
end

local function voiceCountFromCtx(ctx)
  local voices = ctx and ctx._voices or nil
  if type(voices) == "table" and #voices > 0 then
    return #voices
  end
  return 8
end

local function resolveInputSnapshot(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local customResolver = ctx and ctx._resolveDynamicVoiceBundleSample or nil
  if type(customResolver) == "function" then
    local resolved = customResolver(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    if type(resolved) == "table" then return resolved end
  end
  return require("arp_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    or require("adsr_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    or require("transpose_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicNoteFilterRuntime = ctx._dynamicNoteFilterRuntime or {}
  _G.__midiSynthDynamicNoteFilterRuntime = ctx._dynamicNoteFilterRuntime
  _G.__midiSynthNoteFilterViewState = _G.__midiSynthNoteFilterViewState or {}
  return ctx._dynamicNoteFilterRuntime
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
    values = { low = 36, high = 96, mode = 0 },
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
  state.values.low = math.floor(clamp(readParam(paramBase .. "/low", state.values.low or 36), 0.0, 127.0) + 0.5)
  state.values.high = math.floor(clamp(readParam(paramBase .. "/high", state.values.high or 96), 0.0, 127.0) + 0.5)
  state.values.mode = math.floor(clamp(readParam(paramBase .. "/mode", state.values.mode or 0), 0.0, 1.0) + 0.5)
  return state.values
end

local function currentFilterParams(state)
  if type(state) ~= "table" then
    return { low = 36, high = 96, mode = 0 }
  end
  local values = state.values or { low = 36, high = 96, mode = 0 }
  return {
    low = math.floor(clamp(values.low or 36, 0.0, 127.0) + 0.5),
    high = math.floor(clamp(values.high or 96, 0.0, 127.0) + 0.5),
    mode = math.floor(clamp(values.mode or 0, 0.0, 1.0) + 0.5),
  }
end

local function notePassesFilter(noteValue, params)
  local note = math.floor(tonumber(noteValue) or 0)
  local low = math.min(params.low, params.high)
  local high = math.max(params.low, params.high)
  local inside = note >= low and note <= high
  if params.mode == 0 then
    return inside
  else
    return not inside
  end
end

function M.resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if portId ~= "voice" then
    return nil
  end
  if sourceKey ~= "note_filter.voice" and specId ~= "note_filter" then
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

  local params = currentFilterParams(state)
  local passes = notePassesFilter(input.note, params)

  if passes then
    local output = copyVoicePayload({}, input)
    output.active = input.active == true or output.gate > 0.5 or output.noteGate > 0.5 or tostring(output.envelopeStage or "idle") ~= "idle"
    return output
  else
    local inactive = makeInactiveVoice(input)
    inactive.note = input.note
    inactive.sourceVoiceIndex = input.sourceVoiceIndex
    return inactive
  end
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
  if tostring(sourceId or "") ~= "note_filter.voice" and specId ~= "note_filter" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  if not (state and type(state.inputs) == "table") then
    return nil
  end

  local params = currentFilterParams(state)
  local out = {}
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
    local bundle = M.resolveVoiceBundleSample(ctx, sourceId, source, i, clamp)
    local passes = bundle and notePassesFilter(bundle.note, params) or false
    out[#out + 1] = {
      voiceIndex = i,
      rawSourceValue = passes and ((tonumber(bundle and bundle.noteGate) or tonumber(bundle and bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      bundleSnapshot = bundle,
    }
  end
  return out
end

function M.publishViewState(ctx)
  _G.__midiSynthNoteFilterViewState = _G.__midiSynthNoteFilterViewState or {}
  local runtime = ctx and ctx._dynamicNoteFilterRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local activeInput = nil
      local activeVoices = {}
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
              note = voiceNote,
              passes = notePassesFilter(voiceNote, currentFilterParams(state)),
              voiceIndex = sourceIdx,
            }
          end
        end
      end
      local params = currentFilterParams(state)
      local inputNote = tonumber(activeInput and activeInput.note) or nil
      local passes = inputNote ~= nil and notePassesFilter(inputNote, params) or false
      _G.__midiSynthNoteFilterViewState[tostring(moduleId)] = {
        values = { low = params.low, high = params.high, mode = params.mode },
        inputNote = inputNote,
        passes = passes,
        active = activeInput ~= nil,
        activeVoices = activeVoices,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam, voiceCount)
  local runtime = ctx and ctx._dynamicNoteFilterRuntime or nil
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

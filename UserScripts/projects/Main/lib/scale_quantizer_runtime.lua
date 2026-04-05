local M = {}

local SCALE_INTERVALS = {
  major       = { 0, 2, 4, 5, 7, 9, 11 },
  minor       = { 0, 2, 3, 5, 7, 8, 10 },
  dorian      = { 0, 2, 3, 5, 7, 9, 10 },
  mixolydian  = { 0, 2, 4, 5, 7, 9, 10 },
  pentatonic  = { 0, 2, 4, 7, 9 },
  chromatic   = nil, -- pass-through
}

local SCALE_NAMES = { "major", "minor", "dorian", "mixolydian", "pentatonic", "chromatic" }
local DIRECTION_NAMES = { "nearest", "up", "down" }
local VOICE_ACTIVE_EPSILON = 1.0e-4

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
  local customResolver = ctx and ctx._resolveDynamicVoiceBundleSample or nil
  if type(customResolver) == "function" then
    local resolved = customResolver(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    if type(resolved) == "table" then return resolved end
  end
  return require("arp_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
    or require("adsr_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
end

local function quantizeNote(note, root, scale, direction)
  local intervals = SCALE_INTERVALS[scale]
  if intervals == nil then
    -- chromatic pass-through
    return note
  end

  local normalized = note - root
  local octave = math.floor(normalized / 12)
  local pc = normalized % 12

  local closest = nil
  local closestDist = math.huge

  local lower = nil
  local higher = nil

  for _, interval in ipairs(intervals) do
    local degreeNote = octave * 12 + interval
    local dist = math.abs(pc - interval)

    if dist < closestDist then
      closestDist = dist
      closest = degreeNote
    end

    if interval <= pc then
      lower = degreeNote
    end
    if interval >= pc and higher == nil then
      higher = degreeNote
    end
  end

  -- Handle wrap-around for lower/higher
  if lower == nil then
    lower = (octave - 1) * 12 + intervals[#intervals]
  end
  if higher == nil then
    higher = (octave + 1) * 12 + intervals[1]
  end

  local resultPc = closest
  if direction == "up" then
    resultPc = higher
  elseif direction == "down" then
    resultPc = lower
  end

  return root + resultPc
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicScaleQuantizerRuntime = ctx._dynamicScaleQuantizerRuntime or {}
  _G.__midiSynthDynamicScaleQuantizerRuntime = ctx._dynamicScaleQuantizerRuntime
  _G.__midiSynthScaleQuantizerViewState = _G.__midiSynthScaleQuantizerViewState or {}
  return ctx._dynamicScaleQuantizerRuntime
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
    values = { root = 0, scale = 1, direction = 1 },
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
  state.values.root = math.floor(clamp(readParam(paramBase .. "/root", state.values.root or 0), 0, 11) + 0.5)
  state.values.scale = math.floor(clamp(readParam(paramBase .. "/scale", state.values.scale or 1), 1, 6) + 0.5)
  state.values.direction = math.floor(clamp(readParam(paramBase .. "/direction", state.values.direction or 1), 1, 3) + 0.5)
  return state.values
end

local function currentQuantizerSettings(state)
  if type(state) ~= "table" then
    return 0, "major", "nearest"
  end
  local values = state.values or {}
  local root = math.floor(clamp(tonumber(values.root) or 0, 0, 11) + 0.5)
  local scaleIdx = math.floor(clamp(tonumber(values.scale) or 1, 1, 6) + 0.5)
  local dirIdx = math.floor(clamp(tonumber(values.direction) or 1, 1, 3) + 0.5)
  return root, SCALE_NAMES[scaleIdx] or "major", DIRECTION_NAMES[dirIdx] or "nearest"
end

function M.resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if portId ~= "voice" then
    return nil
  end
  if sourceKey ~= "scale_quantizer.voice" and specId ~= "scale_quantizer" then
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

  local root, scale, direction = currentQuantizerSettings(state)
  local shifted = copyVoicePayload({}, input)
  local note = tonumber(shifted.note) or 60.0
  shifted.note = type(clampFn) == "function" and clampFn(quantizeNote(note, root, scale, direction), 0.0, 127.0) or clamp(quantizeNote(note, root, scale, direction), 0.0, 127.0)
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
  if tostring(sourceId or "") ~= "scale_quantizer.voice" and specId ~= "scale_quantizer" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  if not (state and type(state.inputs) == "table") then
    return nil
  end

  local out = {}
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
    local bundle = M.resolveVoiceBundleSample(ctx, sourceId, source, i, clamp)
    local gateOn = ((tonumber(bundle and bundle.noteGate) or tonumber(bundle and bundle.gate) or 0.0) > 0.5)
    local ampActive = math.max(
      tonumber(bundle and bundle.currentAmp) or 0.0,
      tonumber(bundle and bundle.amp) or 0.0,
      tonumber(bundle and bundle.targetAmp) or 0.0
    ) > VOICE_ACTIVE_EPSILON
    out[#out + 1] = {
      voiceIndex = i,
      rawSourceValue = (gateOn or ampActive) and 1.0 or 0.0,
      bundleSnapshot = bundle,
    }
  end
  return out
end

function M.publishViewState(ctx)
  _G.__midiSynthScaleQuantizerViewState = _G.__midiSynthScaleQuantizerViewState or {}
  local runtime = ctx and ctx._dynamicScaleQuantizerRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local activeInput = nil
      local activeVoices = {}
      local root, scale, direction = currentQuantizerSettings(state)
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
              outputNote = quantizeNote(voiceNote, root, scale, direction),
              voiceIndex = sourceIdx,
            }
          end
        end
      end
      local inputNote = tonumber(activeInput and activeInput.note) or nil
      local outputNote = nil
      if inputNote ~= nil then
        outputNote = quantizeNote(inputNote, root, scale, direction)
      end
      _G.__midiSynthScaleQuantizerViewState[tostring(moduleId)] = {
        values = { root = root, scale = scale, direction = direction },
        inputNote = inputNote,
        outputNote = outputNote,
        active = activeInput ~= nil,
        activeVoices = activeVoices,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam, voiceCount)
  local runtime = ctx and ctx._dynamicScaleQuantizerRuntime or nil
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

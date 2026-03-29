local M = {}

local START_CAPTURE_WINDOW = 0.03

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
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
    _lastProcessedGate = 0.0,
  }
end

local function makeOutputVoice()
  return {
    active = false,
    note = 60.0,
    gate = 0.0,
    noteGate = 0.0,
    amp = 0.0,
    targetAmp = 0.0,
    currentAmp = 0.0,
    envelopeLevel = 0.0,
    envelopeStage = "idle",
    sourceVoiceIndex = 1,
    lastTriggerClock = -1.0,
    gateCloseClock = -1.0,
    lastStepStamp = 0,
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
  target.active = source.active == true or target.gate > 0.5 or target.envelopeStage ~= "idle"
  target.sourceVoiceIndex = math.max(1, math.floor(tonumber(source.sourceVoiceIndex) or tonumber(target.sourceVoiceIndex) or 1))
  return target
end

local function sequenceSignature(sequence)
  local out = {}
  for i = 1, #(sequence or {}) do
    local entry = sequence[i]
    out[#out + 1] = string.format(
      "%0.3f:%d@%0.3f",
      tonumber(entry and entry.note) or 0.0,
      math.max(1, math.floor(tonumber(entry and entry.sourceVoiceIndex) or i)),
      tonumber(entry and entry.targetAmp) or tonumber(entry and entry.amp) or 0.0
    )
  end
  return table.concat(out, ",")
end

local function reverseCopy(sequence)
  local out = {}
  for i = #(sequence or {}), 1, -1 do
    out[#out + 1] = sequence[i]
  end
  return out
end

local function buildExpandedSequence(notes, octaves)
  local out = {}
  local octaveCount = math.max(1, math.floor(tonumber(octaves) or 1))
  for octave = 0, octaveCount - 1 do
    for i = 1, #(notes or {}) do
      local entry = notes[i]
      local expanded = copyVoicePayload({}, entry)
      expanded.note = clamp((tonumber(entry and entry.note) or 60.0) + octave * 12.0, 0.0, 127.0)
      out[#out + 1] = expanded
    end
  end
  return out
end

local function chooseSequenceEntry(state, sequence)
  local mode = math.max(0, math.floor(tonumber(state.values and state.values.mode) or 0))
  local count = #(sequence or {})
  if count <= 0 then
    return nil, nil
  end

  if mode == 3 then
    local index = math.max(1, math.min(count, math.floor(math.random() * count) + 1))
    state.currentIndex = index
    return sequence[index], index
  end

  local activeSequence = sequence
  if mode == 1 then
    activeSequence = reverseCopy(sequence)
  end

  local index = math.max(1, math.min(#activeSequence, math.floor(tonumber(state.currentIndex) or 1)))
  if mode == 2 then
    local direction = tonumber(state.direction) or 1
    index = math.max(1, math.min(count, index))
    local entry = sequence[index]
    if count > 1 then
      local nextIndex = index + direction
      if nextIndex > count then
        direction = -1
        nextIndex = count - 1
      elseif nextIndex < 1 then
        direction = 1
        nextIndex = 2
      end
      state.currentIndex = math.max(1, math.min(count, nextIndex))
      state.direction = direction
    end
    return entry, index
  end

  local entry = activeSequence[index]
  if #activeSequence > 1 then
    state.currentIndex = (index % #activeSequence) + 1
  end
  return entry, index
end

local function chooseOutputLane(state)
  state.nextOutputLane = math.max(1, math.floor(tonumber(state.nextOutputLane) or 1))
  local voiceCount = math.max(1, math.floor(tonumber(state.voiceCount) or 1))

  for offset = 0, voiceCount - 1 do
    local laneIndex = ((state.nextOutputLane + offset - 1) % voiceCount) + 1
    local voice = state.outputs and state.outputs[laneIndex] or nil
    if voice and (tonumber(voice.gate) or 0.0) <= 0.5 then
      state.nextOutputLane = (laneIndex % voiceCount) + 1
      return laneIndex
    end
  end

  local fallback = state.nextOutputLane
  state.nextOutputLane = (fallback % voiceCount) + 1
  return fallback
end

local function releaseOutputVoice(voice)
  if type(voice) ~= "table" then
    return
  end
  voice.gate = 0.0
  voice.noteGate = 0.0
  voice.amp = 0.0
  voice.targetAmp = 0.0
  voice.currentAmp = 0.0
  voice.envelopeLevel = 0.0
  voice.active = false
  voice.envelopeStage = "idle"
  voice.gateCloseClock = -1.0
end

local function releaseAllOutputs(state)
  ensureVoiceArray(state.outputs, state.voiceCount or 8, makeOutputVoice)
  for i = 1, #(state.outputs or {}) do
    releaseOutputVoice(state.outputs[i])
  end
end

local function refreshReleasedOutputs(state, nowClock)
  for i = 1, #(state.outputs or {}) do
    local voice = state.outputs[i]
    if type(voice) == "table" and (tonumber(voice.gate) or 0.0) > 0.5 then
      local closeClock = tonumber(voice.gateCloseClock) or -1.0
      if closeClock >= 0.0 and tonumber(nowClock) >= closeClock then
        releaseOutputVoice(voice)
      end
    end
  end
end

local function collectHeldNotes(state)
  local entries = {}
  local holdOn = (tonumber(state.values and state.values.hold) or 0.0) > 0.5
  state.latchedNotes = state.latchedNotes or {}

  if holdOn then
    for i = 1, #(state.inputs or {}) do
      local input = state.inputs[i]
      local gate = (tonumber(input and input.noteGate) or tonumber(input and input.gate) or 0.0) > 0.5 and 1.0 or 0.0
      local lastGate = (tonumber(input and input._lastProcessedGate) or 0.0) > 0.5 and 1.0 or 0.0
      if gate > 0.5 and lastGate <= 0.5 then
        local note = clamp(tonumber(input and input.note) or 60.0, 0.0, 127.0)
        state.latchedNotes[string.format("%0.3f", note)] = copyVoicePayload({}, input)
      end
      if input then
        input._lastProcessedGate = gate
      end
    end
  else
    state.latchedNotes = {}
    for i = 1, #(state.inputs or {}) do
      local input = state.inputs[i]
      local gate = (tonumber(input and input.noteGate) or tonumber(input and input.gate) or 0.0) > 0.5 and 1.0 or 0.0
      if input then
        input._lastProcessedGate = gate
      end
      if gate > 0.5 then
        local note = clamp(tonumber(input and input.note) or 60.0, 0.0, 127.0)
        state.latchedNotes[string.format("%0.3f", note)] = copyVoicePayload({}, input)
      end
    end
  end

  for _, entry in pairs(state.latchedNotes or {}) do
    entries[#entries + 1] = copyVoicePayload({}, entry)
  end
  table.sort(entries, function(a, b)
    if tonumber(a.note) ~= tonumber(b.note) then
      return tonumber(a.note) < tonumber(b.note)
    end
    return tonumber(a.sourceVoiceIndex or 0) < tonumber(b.sourceVoiceIndex or 0)
  end)
  return entries
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicArpRuntime = ctx._dynamicArpRuntime or {}
  _G.__midiSynthDynamicArpRuntime = ctx._dynamicArpRuntime
  _G.__midiSynthArpViewState = _G.__midiSynthArpViewState or {}
  return ctx._dynamicArpRuntime
end

function M.resolveModuleState(ctx, moduleId, voiceCount)
  local id = tostring(moduleId or "")
  local store = M.ensureDynamicRuntime(ctx)
  local state = store[id]
  if state ~= nil then
    state.voiceCount = math.max(1, math.floor(tonumber(voiceCount) or state.voiceCount or 8))
    ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
    ensureVoiceArray(state.outputs, state.voiceCount, makeOutputVoice)
    return state
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local meta = type(info) == "table" and info[id] or nil
  state = {
    moduleId = id,
    slotIndex = tonumber(type(meta) == "table" and meta.slotIndex or nil),
    paramBase = type(meta) == "table" and type(meta.paramBase) == "string" and meta.paramBase or nil,
    values = { rate = 8.0, mode = 0.0, octaves = 1.0, gate = 0.6, hold = 0.0 },
    inputs = {},
    outputs = {},
    latchedNotes = {},
    currentIndex = 1,
    direction = 1,
    voiceCount = math.max(1, math.floor(tonumber(voiceCount) or 8)),
    heldCount = 0,
    sequenceSignature = "",
    clock = 0.0,
    nextStepClock = 0.0,
    nextOutputLane = 1,
    stepStamp = 0,
    pendingStartUntil = nil,
  }
  ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
  ensureVoiceArray(state.outputs, state.voiceCount, makeOutputVoice)
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
  state.values.rate = clamp(readParam(paramBase .. "/rate", state.values.rate or 8.0), 0.25, 20.0)
  state.values.mode = clamp(readParam(paramBase .. "/mode", state.values.mode or 0.0), 0.0, 3.0)
  state.values.octaves = clamp(readParam(paramBase .. "/octaves", state.values.octaves or 1.0), 1.0, 4.0)
  state.values.gate = clamp(readParam(paramBase .. "/gate", state.values.gate or 0.6), 0.05, 1.0)
  state.values.hold = clamp(readParam(paramBase .. "/hold", state.values.hold or 0.0), 0.0, 1.0)
  return state.values
end

local function resolveVoiceSnapshot(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local index = math.max(1, math.floor(tonumber(voiceIndex) or 1))
  local sourceKey = tostring(sourceId or "")

  if sourceKey == "midi.voice" then
    local voice = ctx and ctx._midiVoices and ctx._midiVoices[index] or nil
    local note = tonumber(voice and voice.note) or 60.0
    if type(clampFn) == "function" then
      note = clampFn(note, 0.0, 127.0)
    else
      note = clamp(note, 0.0, 127.0)
    end
    return {
      note = note,
      gate = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      noteGate = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      amp = math.max(0.0, tonumber(voice and voice.targetAmp) or 0.0),
      targetAmp = math.max(0.0, tonumber(voice and voice.targetAmp) or 0.0),
      currentAmp = math.max(0.0, tonumber(voice and voice.currentAmp) or tonumber(voice and voice.targetAmp) or 0.0),
      envelopeLevel = math.max(0.0, tonumber(voice and voice.envelopeLevel) or 0.0),
      envelopeStage = tostring(voice and voice.envelopeStage or (((tonumber(voice and voice.gate) or 0.0) > 0.5) and "sustain" or "idle")),
      active = type(voice) == "table" and (voice.active == true or ((tonumber(voice.gate) or 0.0) > 0.5)),
      sourceVoiceIndex = index,
    }
  end

  if sourceKey == "arp.voice" or tostring(sourceMeta.specId or "") == "arp" then
    local moduleId = tostring(sourceMeta.moduleId or ((sourceKey:match("^([^.]+)%.") or "")))
    local state = M.resolveModuleState(ctx, moduleId, #((ctx and ctx._voices) or {}))
    local voice = state and state.outputs and state.outputs[index] or nil
    if type(voice) == "table" then
      return copyVoicePayload({}, voice)
    end
  end

  if sourceKey == "adsr.voice" or tostring(sourceMeta.specId or "") == "adsr" then
    local moduleId = tostring(sourceMeta.moduleId or ((sourceKey:match("^([^.]+)%.") or "adsr")))
    local state = require("adsr_runtime").resolveModuleState(ctx, moduleId ~= "" and moduleId or "adsr", #((ctx and ctx._voices) or {}))
    local voice = state and state.voices and state.voices[index] or nil
    if type(voice) == "table" then
      local note = tonumber(voice.note) or 60.0
      if type(clampFn) == "function" then
        note = clampFn(note, 0.0, 127.0)
      else
        note = clamp(note, 0.0, 127.0)
      end
      return {
        note = note,
        gate = ((((tonumber(voice.gate) or 0.0) > 0.5) or tostring(voice.envelopeStage or "idle") ~= "idle") and 1.0 or 0.0),
        noteGate = ((tonumber(voice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
        amp = math.max(0.0, tonumber(voice.currentAmp) or 0.0),
        targetAmp = math.max(0.0, tonumber(voice.targetAmp) or tonumber(voice.currentAmp) or 0.0),
        currentAmp = math.max(0.0, tonumber(voice.currentAmp) or 0.0),
        envelopeLevel = math.max(0.0, tonumber(voice.envelopeLevel) or 0.0),
        envelopeStage = tostring(voice.envelopeStage or "idle"),
        active = (((tonumber(voice.gate) or 0.0) > 0.5) or tostring(voice.envelopeStage or "idle") ~= "idle"),
        sourceVoiceIndex = index,
      }
    end
  end

  local transposeBundle = require("transpose_runtime").resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, index, clampFn)
  if type(transposeBundle) == "table" then
    return transposeBundle
  end

  return nil
end

function M.resolveVoiceBundleSample(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  local snapshot = resolveVoiceSnapshot(ctx, sourceId, sourceEndpoint, voiceIndex, clampFn)
  if type(snapshot) ~= "table" then
    return nil
  end
  return {
    note = snapshot.note,
    gate = snapshot.gate,
    noteGate = snapshot.noteGate,
    amp = snapshot.amp,
    targetAmp = snapshot.targetAmp,
    currentAmp = snapshot.currentAmp,
    envelopeLevel = snapshot.envelopeLevel,
    envelopeStage = snapshot.envelopeStage,
    active = snapshot.active,
    sourceVoiceIndex = snapshot.sourceVoiceIndex,
  }
end

function M.applyInputVoice(ctx, moduleId, portId, value, meta, voiceCount, clampFn)
  if tostring(portId or "") ~= "voice_in" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  local voiceIndex = math.max(1, math.floor(tonumber(type(meta) == "table" and meta.voiceIndex or 1) or 1))
  ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
  local input = state.inputs[voiceIndex]
  if not input then
    return false
  end

  local action = type(meta) == "table" and tostring(meta.action or "apply") or "apply"
  local bundle = type(meta) == "table" and type(meta.bundleSample) == "table" and meta.bundleSample
    or resolveVoiceSnapshot(ctx, type(meta) == "table" and meta.bundleSourceId or nil, type(meta) == "table" and meta.bundleSource or nil, voiceIndex, clampFn)
  if action == "restore" or type(bundle) ~= "table" then
    input.gate = 0.0
    input.noteGate = 0.0
    input.active = false
    return true
  end

  copyVoicePayload(input, bundle)
  input.gate = ((tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
  input.noteGate = ((tonumber(bundle.noteGate) or tonumber(bundle.gate) or 0.0) > 0.5) and 1.0 or 0.0
  input.active = bundle.active == true or input.gate > 0.5 or tostring(input.envelopeStage or "idle") ~= "idle"
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
  if tostring(sourceId or "") ~= "arp.voice" and specId ~= "arp" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId, voiceCount)
  if not (state and type(state.outputs) == "table") then
    return nil
  end

  local out = {}
  for i = 1, math.max(1, math.floor(tonumber(voiceCount) or 1)) do
    local voice = state.outputs[i]
    out[#out + 1] = {
      voiceIndex = i,
      rawSourceValue = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0,
      bundleSnapshot = type(voice) == "table" and copyVoicePayload({}, voice) or nil,
    }
  end
  return out
end

function M.publishViewState(ctx)
  _G.__midiSynthArpViewState = _G.__midiSynthArpViewState or {}
  local runtime = ctx and ctx._dynamicArpRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local activeLaneCount = 0
      local currentNote = nil
      local gate = 0.0
      for i = 1, #(state.outputs or {}) do
        local voice = state.outputs[i]
        if type(voice) == "table" and ((tonumber(voice.gate) or 0.0) > 0.5) then
          activeLaneCount = activeLaneCount + 1
          currentNote = tonumber(voice.note) or currentNote
          gate = 1.0
        end
      end
      _G.__midiSynthArpViewState[tostring(moduleId)] = {
        values = state.values,
        heldCount = tonumber(state.heldCount) or 0,
        currentNote = tonumber(currentNote),
        gate = gate,
        activeLaneCount = activeLaneCount,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam, voiceCount)
  local runtime = ctx and ctx._dynamicArpRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      state.voiceCount = math.max(1, math.floor(tonumber(voiceCount) or state.voiceCount or 8))
      ensureVoiceArray(state.inputs, state.voiceCount, makeInputVoice)
      ensureVoiceArray(state.outputs, state.voiceCount, makeOutputVoice)
      M.refreshModuleParams(ctx, state, readParam)

      state.clock = (tonumber(state.clock) or 0.0) + math.max(0.0, tonumber(dt) or 0.0)
      refreshReleasedOutputs(state, state.clock)

      local heldNotes = collectHeldNotes(state)
      local sequence = buildExpandedSequence(heldNotes, state.values.octaves)
      local signature = sequenceSignature(sequence)
      state.heldCount = #heldNotes

      if #sequence == 0 then
        releaseAllOutputs(state)
        state.sequenceSignature = ""
        state.currentIndex = 1
        state.direction = 1
        state.nextStepClock = state.clock
        state.pendingStartUntil = nil
        state.stepStamp = 0
      else
        local period = 1.0 / math.max(0.25, tonumber(state.values.rate) or 8.0)
        local gateLength = clamp(tonumber(state.values.gate) or 0.6, 0.05, 1.0)
        local gateDuration = period * gateLength

        local previousSignature = tostring(state.sequenceSignature or "")
        if signature ~= previousSignature then
          state.sequenceSignature = signature
          state.currentIndex = 1
          state.direction = 1
          if previousSignature == "" then
            local startAt = state.clock + START_CAPTURE_WINDOW
            state.pendingStartUntil = startAt
            state.nextStepClock = startAt
          elseif state.pendingStartUntil ~= nil and math.max(0, math.floor(tonumber(state.stepStamp) or 0)) == 0 then
            -- Chord is still being collected; keep the original deferred start time
            state.nextStepClock = math.max(tonumber(state.nextStepClock) or state.clock, tonumber(state.pendingStartUntil) or state.clock)
          else
            local scheduled = tonumber(state.nextStepClock) or state.clock
            state.nextStepClock = math.max(scheduled, state.clock)
          end
        end

        if state.pendingStartUntil ~= nil and tonumber(state.clock) >= tonumber(state.pendingStartUntil) then
          state.pendingStartUntil = nil
        end

        while state.pendingStartUntil == nil and tonumber(state.clock) >= (tonumber(state.nextStepClock) or 0.0) do
          local entry = chooseSequenceEntry(state, sequence)
          entry = type(entry) == "table" and entry or sequence[1]
          local laneIndex = chooseOutputLane(state)
          local voice = state.outputs[laneIndex]
          if voice then
            state.stepStamp = math.max(0, math.floor(tonumber(state.stepStamp) or 0)) + 1
            copyVoicePayload(voice, entry)
            voice.gate = 1.0
            voice.noteGate = 1.0
            voice.active = true
            voice.lastTriggerClock = state.clock
            voice.gateCloseClock = state.clock + gateDuration
            voice.lastStepStamp = state.stepStamp
          end
          state.nextStepClock = (tonumber(state.nextStepClock) or state.clock) + period
          if period <= 0.0 then
            break
          end
        end
      end
    end
  end

  M.publishViewState(ctx)
end

return M

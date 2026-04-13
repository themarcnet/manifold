local ParameterBinder = require("parameter_binder")

local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function round(value)
  return math.floor((tonumber(value) or 0.0) + 0.5)
end

local function readParam(path, fallback)
  if type(path) ~= "string" or path == "" then
    return fallback
  end
  if type(getParam) == "function" then
    local ok, value = pcall(getParam, path)
    if ok and value ~= nil then
      return tonumber(value) or fallback
    end
  end
  return fallback
end

local function registerSchema(ctx, schema)
  if type(schema) ~= "table" or not (ctx and ctx.params and ctx.params.register) then
    return
  end

  if schema.path and schema.spec then
    ctx.params.register(schema.path, schema.spec)
    return
  end

  for i = 1, #schema do
    local entry = schema[i]
    if type(entry) == "table" and entry.path and entry.spec then
      ctx.params.register(entry.path, entry.spec)
    end
  end
end

local function isScalarValue(value)
  local valueType = type(value)
  return valueType == "number" or valueType == "string" or valueType == "boolean"
end

local function publishScalarTable(base, values)
  if type(base) ~= "string" or base == "" or type(values) ~= "table" or type(setCustomValue) ~= "function" then
    return
  end
  for key, value in pairs(values) do
    if isScalarValue(value) then
      pcall(setCustomValue, base .. "/" .. tostring(key), value)
    end
  end
end

local function publishVoiceEntries(base, entries)
  if type(base) ~= "string" or base == "" or type(entries) ~= "table" or type(setCustomValue) ~= "function" then
    return
  end
  local count = math.max(0, math.floor(tonumber(#entries) or 0))
  pcall(setCustomValue, base .. "/count", count)
  for i = 1, count do
    if type(entries[i]) == "table" then
      publishScalarTable(base .. "/" .. tostring(i), entries[i])
    end
  end
end

local function paramBaseForSpec(specId, slotIndex)
  local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
  local id = tostring(specId or "")
  if id == "arp" then return ParameterBinder.dynamicArpBasePath(index) end
  if id == "scale_quantizer" then return ParameterBinder.dynamicScaleQuantizerBasePath(index) end
  if id == "transpose" then return ParameterBinder.dynamicTransposeBasePath(index) end
  if id == "velocity_mapper" then return ParameterBinder.dynamicVelocityMapperBasePath(index) end
  if id == "note_filter" then return ParameterBinder.dynamicNoteFilterBasePath(index) end
  return nil
end

local function ensureDynamicModuleInfo(moduleId, specId, slotIndex, paramBase)
  _G.__midiSynthDynamicModuleInfo = _G.__midiSynthDynamicModuleInfo or {}
  _G.__midiSynthDynamicModuleInfo[tostring(moduleId or "")] = {
    specId = tostring(specId or ""),
    slotIndex = math.max(1, math.floor(tonumber(slotIndex) or 1)),
    paramBase = tostring(paramBase or ""),
  }
end

local function cloneSlot(slot)
  if type(slot) ~= "table" then
    return nil
  end
  local out = {}
  for key, value in pairs(slot) do
    out[key] = value
  end
  return out
end

local function createNoteRouter(maxVoices)
  local slots = {}
  local byKey = {}
  local stamp = 0
  local voiceCount = math.max(1, math.floor(tonumber(maxVoices) or 8))

  local function keyFor(channel, note)
    return tostring(math.max(1, math.floor(tonumber(channel) or 1))) .. ":" .. tostring(math.max(0, math.min(127, math.floor(tonumber(note) or 0))))
  end

  for i = 1, voiceCount do
    slots[i] = {
      index = i,
      active = false,
      channel = 1,
      note = 60,
      velocity = 100,
      outputNote = nil,
      stamp = 0,
      key = nil,
    }
  end

  local router = {}

  function router.noteOn(channel, note, velocity)
    local key = keyFor(channel, note)
    local existing = byKey[key]
    if existing then
      stamp = stamp + 1
      existing.channel = math.max(1, math.floor(tonumber(channel) or 1))
      existing.note = math.max(0, math.min(127, math.floor(tonumber(note) or 0)))
      existing.velocity = math.max(0, math.min(127, math.floor(tonumber(velocity) or 0)))
      existing.stamp = stamp
      return existing, nil
    end

    local chosen = nil
    for i = 1, #slots do
      if slots[i].active ~= true then
        chosen = slots[i]
        break
      end
    end

    local evicted = nil
    if chosen == nil then
      chosen = slots[1]
      for i = 2, #slots do
        if (tonumber(slots[i].stamp) or 0) < (tonumber(chosen.stamp) or 0) then
          chosen = slots[i]
        end
      end
      evicted = cloneSlot(chosen)
      if type(chosen.key) == "string" then
        byKey[chosen.key] = nil
      end
    end

    stamp = stamp + 1
    chosen.active = true
    chosen.channel = math.max(1, math.floor(tonumber(channel) or 1))
    chosen.note = math.max(0, math.min(127, math.floor(tonumber(note) or 0)))
    chosen.velocity = math.max(0, math.min(127, math.floor(tonumber(velocity) or 0)))
    chosen.outputNote = nil
    chosen.stamp = stamp
    chosen.key = key
    byKey[key] = chosen
    return chosen, evicted
  end

  function router.noteOff(channel, note)
    local key = keyFor(channel, note)
    local slot = byKey[key]
    if slot == nil then
      return nil
    end
    byKey[key] = nil
    local released = cloneSlot(slot)
    slot.active = false
    slot.key = nil
    slot.outputNote = nil
    return released
  end

  function router.slotByIndex(index)
    return slots[math.max(1, math.floor(tonumber(index) or 1))]
  end

  function router.activeEntries()
    local out = {}
    for i = 1, #slots do
      if slots[i].active == true then
        out[#out + 1] = slots[i]
      end
    end
    table.sort(out, function(a, b)
      return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
    end)
    return out
  end

  function router.clear()
    local out = {}
    for i = 1, #slots do
      if slots[i].active == true then
        out[#out + 1] = cloneSlot(slots[i])
      end
      slots[i].active = false
      slots[i].key = nil
      slots[i].outputNote = nil
    end
    byKey = {}
    return out
  end

  return router
end

local function makeVoiceBundle(slot)
  local velocity = math.max(0, math.min(127, math.floor(tonumber(slot and slot.velocity) or 0)))
  local amp = clamp(velocity / 127.0, 0.0, 1.0)
  return {
    note = math.max(0.0, math.min(127.0, tonumber(slot and slot.note) or 60.0)),
    gate = 1.0,
    noteGate = 1.0,
    amp = amp,
    targetAmp = amp,
    currentAmp = amp,
    envelopeLevel = amp,
    envelopeStage = "sustain",
    active = true,
    sourceVoiceIndex = math.max(1, math.floor(tonumber(slot and slot.index) or 1)),
  }
end

local function buildEmitter()
  local emitter = {}

  function emitter.noteOn(channel, note, velocity)
    if Midi and Midi.sendNoteOn then
      Midi.sendNoteOn(math.max(1, round(channel)), math.max(0, math.min(127, round(note))), math.max(0, math.min(127, round(velocity))))
    end
  end

  function emitter.noteOff(channel, note)
    if Midi and Midi.sendNoteOff then
      Midi.sendNoteOff(math.max(1, round(channel)), math.max(0, math.min(127, round(note))))
    end
  end

  function emitter.cc(channel, cc, value)
    if Midi and Midi.sendCC then
      Midi.sendCC(math.max(1, round(channel)), math.max(0, math.min(127, round(cc))), math.max(0, math.min(127, round(value))))
    end
  end

  function emitter.pitchBend(channel, value)
    if Midi and Midi.sendPitchBend then
      Midi.sendPitchBend(math.max(1, round(channel)), math.max(-8192, math.min(8191, round(value))))
    end
  end

  function emitter.programChange(channel, program)
    if Midi and Midi.sendProgramChange then
      Midi.sendProgramChange(math.max(1, round(channel)), math.max(0, math.min(127, round(program))))
    end
  end

  function emitter.allNotesOff(channel)
    if Midi and Midi.sendAllNotesOff then
      Midi.sendAllNotesOff(math.max(1, round(channel)))
    elseif Midi and Midi.sendCC then
      Midi.sendCC(math.max(1, round(channel)), 123, 0)
    end
  end

  function emitter.forwardEvent(event)
    local eventType = tonumber(type(event) == "table" and event.type or 0) or 0
    local channel = tonumber(type(event) == "table" and event.channel or 1) or 1
    local data1 = tonumber(type(event) == "table" and event.data1 or 0) or 0
    local data2 = tonumber(type(event) == "table" and event.data2 or 0) or 0

    if Midi and eventType == Midi.NOTE_ON and data2 > 0 then
      emitter.noteOn(channel, data1, data2)
    elseif Midi and (eventType == Midi.NOTE_OFF or (eventType == Midi.NOTE_ON and data2 <= 0)) then
      emitter.noteOff(channel, data1)
    elseif Midi and eventType == Midi.CONTROL_CHANGE then
      emitter.cc(channel, data1, data2)
    elseif Midi and eventType == Midi.PITCH_BEND then
      local lsb = math.max(0, math.min(127, round(data1)))
      local msb = math.max(0, math.min(127, round(data2)))
      emitter.pitchBend(channel, (msb * 128 + lsb) - 8192)
    elseif Midi and eventType == Midi.PROGRAM_CHANGE then
      emitter.programChange(channel, data1)
    end
  end

  return emitter
end

function M.buildMidiEffect(ctx, options)
  options = type(options) == "table" and options or {}

  local specId = tostring(options.schemaSpecId or "")
  local adapterRequire = tostring(options.adapterRequire or "")
  local description = tostring(options.description or "Manifold MIDI Effect")
  local moduleId = tostring(options.instanceNodeId or ("standalone_" .. specId .. "_1"))
  local slotIndex = math.max(1, math.floor(tonumber(options.slotIndex) or 1))
  local voiceCount = math.max(1, math.floor(tonumber(options.voiceCount) or 8))
  local schemaOptions = type(options.schemaOptions) == "table" and options.schemaOptions or {}
  local viewStateKey = tostring(options.viewStateKey or "")

  if specId == "" then
    error("export_midi_effect_scaffold: schemaSpecId is required")
  end
  if adapterRequire == "" then
    error("export_midi_effect_scaffold: adapterRequire is required")
  end

  local paramBase = tostring(options.paramBase or paramBaseForSpec(specId, slotIndex) or "")
  if paramBase == "" then
    error("export_midi_effect_scaffold: unable to resolve param base for specId=" .. specId)
  end

  ensureDynamicModuleInfo(moduleId, specId, slotIndex, paramBase)
  registerSchema(ctx, ParameterBinder.buildDynamicSlotSchema(specId, slotIndex, schemaOptions))

  local adapter = require(adapterRequire).create {
    ctx = ctx,
    specId = specId,
    slotIndex = slotIndex,
    moduleId = moduleId,
    paramBase = paramBase,
    voiceCount = voiceCount,
    readParam = readParam,
    clamp = clamp,
    round = round,
    noteRouter = createNoteRouter(voiceCount),
    makeVoiceBundle = makeVoiceBundle,
  }

  local emit = buildEmitter()

  local function publishViewState()
    if viewStateKey == "" or type(setCustomValue) ~= "function" then
      return
    end
    local store = type(_G) == "table" and _G[viewStateKey] or nil
    local viewState = type(store) == "table" and store[tostring(moduleId)] or nil
    if type(viewState) ~= "table" then
      return
    end

    local base = "/plugin/ui/viewstate/" .. viewStateKey .. "/" .. tostring(moduleId)
    for key, value in pairs(viewState) do
      if isScalarValue(value) then
        pcall(setCustomValue, base .. "/" .. tostring(key), value)
      elseif key == "values" and type(value) == "table" then
        publishScalarTable(base .. "/values", value)
      elseif key == "activeVoices" and type(value) == "table" then
        publishVoiceEntries(base .. "/activeVoices", value)
      end
    end
  end

  return {
    description = description,
    onParamChange = function(path, value)
      if adapter and adapter.onParamChange then
        adapter.onParamChange(path, value, emit)
      end
      publishViewState()
    end,
    process = function(blockSize, sampleRate)
      if adapter and adapter.beforeProcess then
        adapter.beforeProcess(blockSize, sampleRate, emit)
      end

      if Midi and Midi.pollInputEvent and adapter and adapter.handleMidiEvent then
        while true do
          local event = Midi.pollInputEvent()
          if event == nil then
            break
          end
          adapter.handleMidiEvent(event, emit)
        end
      end

      if adapter and adapter.process then
        local sr = math.max(1.0, tonumber(sampleRate) or 44100.0)
        local dt = math.max(0.0, (tonumber(blockSize) or 0.0) / sr)
        adapter.process(dt, emit)
      end

      publishViewState()
    end,
  }
end

return M

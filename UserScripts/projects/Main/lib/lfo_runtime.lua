local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function randomBipolar()
  return (math.random() * 2.0) - 1.0
end

local function wrapPhase(value)
  local v = tonumber(value) or 0.0
  v = v - math.floor(v)
  if v < 0.0 then
    v = v + 1.0
  end
  return v
end

local function phaseFromDegrees(degrees)
  return wrapPhase((tonumber(degrees) or 0.0) / 360.0)
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicLfoRuntime = ctx._dynamicLfoRuntime or {}
  _G.__midiSynthDynamicLfoRuntime = ctx._dynamicLfoRuntime
  _G.__midiSynthLfoViewState = _G.__midiSynthLfoViewState or {}
  return ctx._dynamicLfoRuntime
end

local function initializeState(state)
  if state.phase == nil then
    state.phase = phaseFromDegrees(state.values and state.values.phase or 0.0)
  else
    state.phase = wrapPhase(state.phase)
  end
  state.syncGateHigh = state.syncGateHigh == true
  state.lastResetHigh = state.lastResetHigh == true
  state.sampleHoldValue = state.sampleHoldValue or randomBipolar()
  state.noiseCurrent = state.noiseCurrent or randomBipolar()
  state.noiseNext = state.noiseNext or randomBipolar()
  state.outputs = state.outputs or { out = 0.0, inv = 0.0, uni = 0.0, eoc = 0.0 }
end

function M.resolveModuleState(ctx, moduleId)
  local id = tostring(moduleId or "")
  local store = M.ensureDynamicRuntime(ctx)
  local state = store[id]
  if state ~= nil then
    initializeState(state)
    return state
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local meta = type(info) == "table" and info[id] or nil
  state = {
    moduleId = id,
    slotIndex = tonumber(type(meta) == "table" and meta.slotIndex or nil),
    paramBase = type(meta) == "table" and type(meta.paramBase) == "string" and meta.paramBase or nil,
    values = {
      rate = 1.0,
      shape = 0,
      depth = 1.0,
      phase = 0.0,
      retrig = 1,
    },
  }
  initializeState(state)
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
  state.values.rate = clamp(readParam(paramBase .. "/rate", state.values.rate or 1.0), 0.01, 20.0)
  state.values.shape = math.floor(clamp(readParam(paramBase .. "/shape", state.values.shape or 0), 0.0, 5.0) + 0.5)
  state.values.depth = clamp(readParam(paramBase .. "/depth", state.values.depth or 1.0), 0.0, 1.0)
  state.values.phase = clamp(readParam(paramBase .. "/phase", state.values.phase or 0.0), 0.0, 360.0)
  state.values.retrig = math.floor(clamp(readParam(paramBase .. "/retrig", state.values.retrig or 1), 0.0, 1.0) + 0.5)
  return state.values
end

local function resetPhase(state)
  state.phase = phaseFromDegrees(state.values and state.values.phase or 0.0)
  if math.floor(tonumber(state.values and state.values.shape) or 0) == 4 then
    state.sampleHoldValue = randomBipolar()
  elseif math.floor(tonumber(state.values and state.values.shape) or 0) == 5 then
    state.noiseCurrent = randomBipolar()
    state.noiseNext = randomBipolar()
  end
end

local function shapeValue(state)
  local phase = wrapPhase(state.phase)
  local shape = math.floor(tonumber(state.values and state.values.shape) or 0)

  if shape == 0 then
    return math.sin(phase * math.pi * 2.0)
  elseif shape == 1 then
    return 1.0 - math.abs((phase * 4.0) - 2.0)
  elseif shape == 2 then
    return (phase * 2.0) - 1.0
  elseif shape == 3 then
    return phase < 0.5 and 1.0 or -1.0
  elseif shape == 4 then
    return clamp(tonumber(state.sampleHoldValue) or 0.0, -1.0, 1.0)
  elseif shape == 5 then
    local a = tonumber(state.noiseCurrent) or 0.0
    local b = tonumber(state.noiseNext) or 0.0
    return clamp(a + ((b - a) * phase), -1.0, 1.0)
  end

  return 0.0
end

local function refreshOutputs(state)
  initializeState(state)
  local depth = clamp(tonumber(state.values and state.values.depth) or 1.0, 0.0, 1.0)
  local bipolar = clamp(shapeValue(state) * depth, -1.0, 1.0)
  local unipolar = clamp(((shapeValue(state) + 1.0) * 0.5) * depth, 0.0, 1.0)
  state.outputs.out = bipolar
  state.outputs.inv = -bipolar
  state.outputs.uni = unipolar
  state.outputs.eoc = (tonumber(state.eocPulseFrames) or 0) > 0 and 1.0 or 0.0
  return state.outputs
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  local id = tostring(portId or "")
  if id ~= "reset" and id ~= "sync" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId)
  local high = (tonumber(value) or 0.0) > 0.5
  local retrigEnabled = math.floor(tonumber(state.values and state.values.retrig) or 1) > 0

  if id == "reset" then
    if high and not state.lastResetHigh and retrigEnabled then
      resetPhase(state)
    end
    state.lastResetHigh = high
  elseif id == "sync" then
    if high and not state.syncGateHigh and retrigEnabled then
      resetPhase(state)
    end
    state.syncGateHigh = high
  end

  refreshOutputs(state)
  return true
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if specId ~= "lfo" and sourceKey ~= "lfo." .. portId then
    return nil
  end

  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.") or ""))
  local state = M.resolveModuleState(ctx, moduleId)
  local outputs = refreshOutputs(state)
  local value = outputs[portId]
  if value == nil then
    return nil
  end
  return {
    rawSourceValue = tonumber(value) or 0.0,
  }
end

function M.publishViewState(ctx)
  _G.__midiSynthLfoViewState = _G.__midiSynthLfoViewState or {}
  local runtime = ctx and ctx._dynamicLfoRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local outputs = refreshOutputs(state)
      _G.__midiSynthLfoViewState[tostring(moduleId)] = {
        values = {
          rate = tonumber(state.values and state.values.rate) or 1.0,
          shape = math.floor(tonumber(state.values and state.values.shape) or 0),
          depth = tonumber(state.values and state.values.depth) or 1.0,
          phase = tonumber(state.values and state.values.phase) or 0.0,
          retrig = math.floor(tonumber(state.values and state.values.retrig) or 1),
        },
        phase = wrapPhase(state.phase),
        outputs = {
          out = tonumber(outputs.out) or 0.0,
          inv = tonumber(outputs.inv) or 0.0,
          uni = tonumber(outputs.uni) or 0.0,
          eoc = tonumber(outputs.eoc) or 0.0,
        },
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicLfoRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  local delta = math.max(0.0, tonumber(dt) or 0.0)
  for _, state in pairs(runtime) do
    if type(state) == "table" then
      initializeState(state)
      M.refreshModuleParams(ctx, state, readParam)

      if (tonumber(state.eocPulseFrames) or 0) > 0 then
        state.eocPulseFrames = math.max(0, math.floor((tonumber(state.eocPulseFrames) or 0) - 1))
      end

      if not state.syncGateHigh then
        local previous = wrapPhase(state.phase)
        local nextPhase = previous + (delta * math.max(0.01, tonumber(state.values and state.values.rate) or 1.0))
        local wrapped = nextPhase >= 1.0
        state.phase = wrapPhase(nextPhase)
        if wrapped then
          if math.floor(tonumber(state.values and state.values.shape) or 0) == 4 then
            state.sampleHoldValue = randomBipolar()
          elseif math.floor(tonumber(state.values and state.values.shape) or 0) == 5 then
            state.noiseCurrent = tonumber(state.noiseNext) or randomBipolar()
            state.noiseNext = randomBipolar()
          end
          state.eocPulseFrames = 1
        end
      else
        state.phase = wrapPhase(state.phase)
      end

      refreshOutputs(state)
    end
  end

  M.publishViewState(ctx)
end

return M

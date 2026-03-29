local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicSampleHoldRuntime = ctx._dynamicSampleHoldRuntime or {}
  _G.__midiSynthDynamicSampleHoldRuntime = ctx._dynamicSampleHoldRuntime
  _G.__midiSynthSampleHoldViewState = _G.__midiSynthSampleHoldViewState or {}
  return ctx._dynamicSampleHoldRuntime
end

local function initializeState(state)
  state.inputValue = tonumber(state.inputValue) or 0.0
  state.outputValue = tonumber(state.outputValue) or 0.0
  state.trigHigh = state.trigHigh == true
  state.outputs = state.outputs or { out = state.outputValue, inv = -state.outputValue }
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
    values = { mode = 0 },
    inputValue = 0.0,
    outputValue = 0.0,
    trigHigh = false,
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
  state.values.mode = math.floor(clamp(readParam(paramBase .. "/mode", state.values.mode or 0), 0.0, 2.0) + 0.5)
  return state.values
end

local function quantizeStep(value)
  local steps = 12.0
  return clamp(math.floor(((clamp(value, -1.0, 1.0) + 1.0) * 0.5 * steps) + 0.5) / steps * 2.0 - 1.0, -1.0, 1.0)
end

local function refreshOutputs(state)
  initializeState(state)
  state.outputs.out = clamp(tonumber(state.outputValue) or 0.0, -1.0, 1.0)
  state.outputs.inv = clamp(-state.outputs.out, -1.0, 1.0)
  return state.outputs
end

local function processTrigger(state, high)
  local mode = math.floor(tonumber(state.values and state.values.mode) or 0)
  if mode == 1 then
    if high then
      state.outputValue = state.inputValue
    end
  else
    if high and not state.trigHigh then
      if mode == 2 then
        state.outputValue = quantizeStep(state.inputValue)
      else
        state.outputValue = state.inputValue
      end
    end
  end
  state.trigHigh = high
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  local state = M.resolveModuleState(ctx, moduleId)
  local id = tostring(portId or "")
  if id == "in" then
    state.inputValue = clamp(tonumber(value) or 0.0, -1.0, 1.0)
    if math.floor(tonumber(state.values and state.values.mode) or 0) == 1 and state.trigHigh then
      state.outputValue = state.inputValue
    end
    refreshOutputs(state)
    return true
  elseif id == "trig" then
    processTrigger(state, (tonumber(value) or 0.0) > 0.5)
    refreshOutputs(state)
    return true
  end
  return false
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if specId ~= "sample_hold" and not sourceKey:find("sample_hold", 1, true) then
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
  _G.__midiSynthSampleHoldViewState = _G.__midiSynthSampleHoldViewState or {}
  local runtime = ctx and ctx._dynamicSampleHoldRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local outputs = refreshOutputs(state)
      _G.__midiSynthSampleHoldViewState[tostring(moduleId)] = {
        values = {
          mode = math.floor(tonumber(state.values and state.values.mode) or 0),
        },
        inputValue = tonumber(state.inputValue) or 0.0,
        outputValue = tonumber(outputs.out) or 0.0,
        invValue = tonumber(outputs.inv) or 0.0,
        trigHigh = state.trigHigh == true,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicSampleHoldRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      initializeState(state)
      M.refreshModuleParams(ctx, state, readParam)
      if math.floor(tonumber(state.values and state.values.mode) or 0) == 1 and state.trigHigh then
        state.outputValue = state.inputValue
      end
      refreshOutputs(state)
    end
  end

  M.publishViewState(ctx)
end

return M

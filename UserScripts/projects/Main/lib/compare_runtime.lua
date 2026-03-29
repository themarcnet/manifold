local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicCompareRuntime = ctx._dynamicCompareRuntime or {}
  _G.__midiSynthDynamicCompareRuntime = ctx._dynamicCompareRuntime
  _G.__midiSynthCompareViewState = _G.__midiSynthCompareViewState or {}
  return ctx._dynamicCompareRuntime
end

local function initializeState(state)
  state.inputValue = tonumber(state.inputValue) or 0.0
  state.gateValue = ((tonumber(state.gateValue) or 0.0) > 0.5) and 1.0 or 0.0
  state.outputs = state.outputs or { gate = state.gateValue, trig = 0.0 }
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
      threshold = 0.0,
      hysteresis = 0.05,
      direction = 0,
    },
    inputValue = 0.0,
    gateValue = 0.0,
    trigPulseFrames = 0,
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
  state.values.threshold = clamp(readParam(paramBase .. "/threshold", state.values.threshold or 0.0), -1.0, 1.0)
  state.values.hysteresis = clamp(readParam(paramBase .. "/hysteresis", state.values.hysteresis or 0.05), 0.0, 0.5)
  state.values.direction = math.floor(clamp(readParam(paramBase .. "/direction", state.values.direction or 0), 0.0, 2.0) + 0.5)
  return state.values
end

local function computeGate(state)
  local threshold = clamp(tonumber(state.values and state.values.threshold) or 0.0, -1.0, 1.0)
  local hysteresis = clamp(tonumber(state.values and state.values.hysteresis) or 0.05, 0.0, 0.5)
  local direction = math.floor(tonumber(state.values and state.values.direction) or 0)
  local input = clamp(tonumber(state.inputValue) or 0.0, -1.0, 1.0)
  local currentGate = ((tonumber(state.gateValue) or 0.0) > 0.5) and 1.0 or 0.0
  local highThreshold = threshold + (hysteresis * 0.5)
  local lowThreshold = threshold - (hysteresis * 0.5)

  local nextGate = currentGate
  if direction == 1 then
    if currentGate > 0.5 then
      if input >= highThreshold then
        nextGate = 0.0
      end
    else
      if input <= lowThreshold then
        nextGate = 1.0
      end
    end
  else
    if currentGate > 0.5 then
      if input <= lowThreshold then
        nextGate = 0.0
      end
    else
      if input >= highThreshold then
        nextGate = 1.0
      end
    end
  end

  local trigger = false
  if direction == 2 then
    trigger = nextGate ~= currentGate
  else
    trigger = currentGate <= 0.5 and nextGate > 0.5
  end

  state.gateValue = nextGate
  if trigger then
    state.trigPulseFrames = 2
  end
end

local function refreshOutputs(state)
  initializeState(state)
  state.outputs.gate = ((tonumber(state.gateValue) or 0.0) > 0.5) and 1.0 or 0.0
  state.outputs.trig = (tonumber(state.trigPulseFrames) or 0) > 0 and 1.0 or 0.0
  return state.outputs
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  if tostring(portId or "") ~= "in" then
    return false
  end
  local state = M.resolveModuleState(ctx, moduleId)
  state.inputValue = clamp(tonumber(value) or 0.0, -1.0, 1.0)
  computeGate(state)
  refreshOutputs(state)
  return true
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if specId ~= "compare" and not sourceKey:find("compare", 1, true) then
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
  _G.__midiSynthCompareViewState = _G.__midiSynthCompareViewState or {}
  local runtime = ctx and ctx._dynamicCompareRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local outputs = refreshOutputs(state)
      _G.__midiSynthCompareViewState[tostring(moduleId)] = {
        values = {
          threshold = tonumber(state.values and state.values.threshold) or 0.0,
          hysteresis = tonumber(state.values and state.values.hysteresis) or 0.05,
          direction = math.floor(tonumber(state.values and state.values.direction) or 0),
        },
        inputValue = tonumber(state.inputValue) or 0.0,
        gateValue = tonumber(outputs.gate) or 0.0,
        trigValue = tonumber(outputs.trig) or 0.0,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicCompareRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      initializeState(state)
      M.refreshModuleParams(ctx, state, readParam)
      if (tonumber(state.trigPulseFrames) or 0) > 0 then
        state.trigPulseFrames = math.max(0, math.floor((tonumber(state.trigPulseFrames) or 0) - 1))
      end
      computeGate(state)
      refreshOutputs(state)
    end
  end

  M.publishViewState(ctx)
end

return M

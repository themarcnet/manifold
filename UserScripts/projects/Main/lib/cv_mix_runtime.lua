local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicCvMixRuntime = ctx._dynamicCvMixRuntime or {}
  _G.__midiSynthDynamicCvMixRuntime = ctx._dynamicCvMixRuntime
  _G.__midiSynthCvMixViewState = _G.__midiSynthCvMixViewState or {}
  return ctx._dynamicCvMixRuntime
end

local function initializeState(state)
  state.inputs = state.inputs or { 0.0, 0.0, 0.0, 0.0 }
  for i = 1, 4 do
    state.inputs[i] = tonumber(state.inputs[i]) or 0.0
  end
  state.outputs = state.outputs or { out = 0.0, inv = 0.0 }
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
      level_1 = 1.0,
      level_2 = 0.0,
      level_3 = 0.0,
      level_4 = 0.0,
      offset = 0.0,
    },
    inputs = { 0.0, 0.0, 0.0, 0.0 },
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
  state.values.level_1 = clamp(readParam(paramBase .. "/level_1", state.values.level_1 or 1.0), 0.0, 1.0)
  state.values.level_2 = clamp(readParam(paramBase .. "/level_2", state.values.level_2 or 0.0), 0.0, 1.0)
  state.values.level_3 = clamp(readParam(paramBase .. "/level_3", state.values.level_3 or 0.0), 0.0, 1.0)
  state.values.level_4 = clamp(readParam(paramBase .. "/level_4", state.values.level_4 or 0.0), 0.0, 1.0)
  state.values.offset = clamp(readParam(paramBase .. "/offset", state.values.offset or 0.0), -1.0, 1.0)
  return state.values
end

local function refreshOutputs(state)
  initializeState(state)
  local mixed = 0.0
  for i = 1, 4 do
    local level = tonumber(state.values and state.values["level_" .. i]) or 0.0
    mixed = mixed + ((tonumber(state.inputs[i]) or 0.0) * clamp(level, 0.0, 1.0))
  end
  mixed = clamp(mixed + (tonumber(state.values and state.values.offset) or 0.0), -1.0, 1.0)
  state.outputs.out = mixed
  state.outputs.inv = clamp(-mixed, -1.0, 1.0)
  return state.outputs
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  local port = tostring(portId or "")
  local index = port:match("^in_(%d+)$")
  if index == nil then
    return false
  end
  local inputIndex = math.max(1, math.min(4, math.floor(tonumber(index) or 1)))
  local state = M.resolveModuleState(ctx, moduleId)
  state.inputs[inputIndex] = clamp(tonumber(value) or 0.0, -1.0, 1.0)
  refreshOutputs(state)
  return true
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if specId ~= "cv_mix" and not sourceKey:find("cv_mix", 1, true) then
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
  _G.__midiSynthCvMixViewState = _G.__midiSynthCvMixViewState or {}
  local runtime = ctx and ctx._dynamicCvMixRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local outputs = refreshOutputs(state)
      _G.__midiSynthCvMixViewState[tostring(moduleId)] = {
        values = {
          level_1 = tonumber(state.values and state.values.level_1) or 1.0,
          level_2 = tonumber(state.values and state.values.level_2) or 0.0,
          level_3 = tonumber(state.values and state.values.level_3) or 0.0,
          level_4 = tonumber(state.values and state.values.level_4) or 0.0,
          offset = tonumber(state.values and state.values.offset) or 0.0,
        },
        inputs = { state.inputs[1], state.inputs[2], state.inputs[3], state.inputs[4] },
        outputValue = tonumber(outputs.out) or 0.0,
        invertedValue = tonumber(outputs.inv) or 0.0,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicCvMixRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      initializeState(state)
      M.refreshModuleParams(ctx, state, readParam)
      refreshOutputs(state)
    end
  end

  M.publishViewState(ctx)
end

return M

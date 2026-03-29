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

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicRangeMapperRuntime = ctx._dynamicRangeMapperRuntime or {}
  _G.__midiSynthDynamicRangeMapperRuntime = ctx._dynamicRangeMapperRuntime
  _G.__midiSynthRangeMapperViewState = _G.__midiSynthRangeMapperViewState or {}
  return ctx._dynamicRangeMapperRuntime
end

function M.resolveModuleState(ctx, moduleId)
  local id = tostring(moduleId or "")
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
    values = { min = 0.0, max = 1.0, mode = 0 },
  }
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
  state.values.min = clamp(readParam(paramBase .. "/min", state.values.min or 0.0), 0.0, 1.0)
  state.values.max = clamp(readParam(paramBase .. "/max", state.values.max or 1.0), 0.0, 1.0)
  state.values.mode = math.floor(clamp(readParam(paramBase .. "/mode", state.values.mode or 0), 0, 1) + 0.5)
  return state.values
end

local function getEffectiveMinMax(state)
  local minVal = tonumber(state.values and state.values.min) or 0.0
  local maxVal = tonumber(state.values and state.values.max) or 1.0
  if minVal > maxVal then
    minVal, maxVal = maxVal, minVal
  end
  return minVal, maxVal
end

local function currentMode(state)
  local mode = tonumber(state.values and state.values.mode) or 0
  return math.floor(clamp(mode, 0, 1) + 0.5)
end

local function processValue(input, minVal, maxVal, mode)
  local x = tonumber(input) or 0.0
  if mode == 0 then
    return clamp(x, minVal, maxVal)
  else
    local normalized = clamp(x, 0.0, 1.0)
    return minVal + normalized * (maxVal - minVal)
  end
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  if tostring(portId or "") ~= "in" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId)
  if type(state) ~= "table" then
    return false
  end

  local input = tonumber(value) or 0.0
  local minVal, maxVal = getEffectiveMinMax(state)
  local mode = currentMode(state)

  state.lastInput = input
  state.lastOutput = processValue(input, minVal, maxVal, mode)
  state.lastMin = minVal
  state.lastMax = maxVal
  state.lastMode = mode

  return true
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  
  if portId ~= "out" then
    return nil
  end
  if sourceKey ~= "range_mapper.out" and specId ~= "range_mapper" then
    return nil
  end

  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.") or ""))
  local state = M.resolveModuleState(ctx, moduleId)
  if type(state) ~= "table" then
    return nil
  end

  return {
    rawSourceValue = tonumber(state.lastOutput) or 0.0,
  }
end

function M.publishViewState(ctx)
  _G.__midiSynthRangeMapperViewState = _G.__midiSynthRangeMapperViewState or {}
  local runtime = ctx and ctx._dynamicRangeMapperRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local minVal, maxVal = getEffectiveMinMax(state)
      local mode = currentMode(state)
      _G.__midiSynthRangeMapperViewState[tostring(moduleId)] = {
        values = {
          min = state.values and state.values.min or 0.0,
          max = state.values and state.values.max or 1.0,
          mode = state.values and state.values.mode or 0,
        },
        effectiveMin = minVal,
        effectiveMax = maxVal,
        effectiveMode = mode,
        lastInput = state.lastInput,
        lastOutput = state.lastOutput,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicRangeMapperRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  for _, state in pairs(runtime) do
    if type(state) == "table" then
      M.refreshModuleParams(ctx, state, readParam)
    end
  end

  M.publishViewState(ctx)
end

return M

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
  ctx._dynamicAttenuverterBiasRuntime = ctx._dynamicAttenuverterBiasRuntime or {}
  _G.__midiSynthDynamicAttenuverterBiasRuntime = ctx._dynamicAttenuverterBiasRuntime
  _G.__midiSynthAttenuverterBiasViewState = _G.__midiSynthAttenuverterBiasViewState or {}
  return ctx._dynamicAttenuverterBiasRuntime
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
    values = { amount = 1.0, bias = 0.0 },
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
  state.values.amount = clamp(readParam(paramBase .. "/amount", state.values.amount or 1.0), -1.0, 1.0)
  state.values.bias = clamp(readParam(paramBase .. "/bias", state.values.bias or 0.0), -1.0, 1.0)
  return state.values
end

local function currentAmount(state)
  if type(state) ~= "table" then
    return 1.0
  end
  local value = tonumber(state.values and state.values.amount) or 1.0
  return clamp(value, -1.0, 1.0)
end

local function currentBias(state)
  if type(state) ~= "table" then
    return 0.0
  end
  local value = tonumber(state.values and state.values.bias) or 0.0
  return clamp(value, -1.0, 1.0)
end

function M.resolveScalarSample(ctx, sourceId, sourceEndpoint, clampFn)
  local sourceMeta = type(sourceEndpoint) == "table" and type(sourceEndpoint.meta) == "table" and sourceEndpoint.meta or {}
  local sourceKey = tostring(sourceId or "")
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or sourceKey:match("%.([%a_]+)$") or "")
  if portId ~= "out" then
    return nil
  end
  if sourceKey ~= "attenuverter_bias.out" and specId ~= "attenuverter_bias" then
    return nil
  end

  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.out$") or ""))
  local state = M.resolveModuleState(ctx, moduleId)

  local amount = currentAmount(state)
  local bias = currentBias(state)
  local inputValue = 0.0

  if type(sourceEndpoint) == "table" and type(sourceEndpoint.resolve) == "function" then
    local resolved = sourceEndpoint.resolve()
    inputValue = tonumber(resolved) or 0.0
  end

  local output = (inputValue * amount) + bias
  return type(clampFn) == "function" and clampFn(output, -1.0, 1.0) or clamp(output, -1.0, 1.0)
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  if tostring(portId or "") ~= "in" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId)
  state.lastInput = tonumber(value) or 0.0
  return true
end

function M.resolveScalarModulationSource(ctx, sourceId, source)
  local sourceMeta = type(source) == "table" and type(source.meta) == "table" and source.meta or {}
  local specId = tostring(sourceMeta.specId or "")
  local portId = tostring(sourceMeta.portId or tostring(sourceId or ""):match("%.([%a_]+)$") or "")
  local moduleId = tostring(sourceMeta.moduleId or ((tostring(sourceId or ""):match("^([^.]+)%.out$") or "")))
  if portId ~= "out" then
    return nil
  end
  if tostring(sourceId or "") ~= "attenuverter_bias.out" and specId ~= "attenuverter_bias" then
    return nil
  end

  local state = M.resolveModuleState(ctx, moduleId)
  local amount = currentAmount(state)
  local bias = currentBias(state)
  local inputValue = state.lastInput or 0.0
  local output = (inputValue * amount) + bias

  return {
    rawSourceValue = clamp(output, -1.0, 1.0),
  }
end

function M.publishViewState(ctx)
  _G.__midiSynthAttenuverterBiasViewState = _G.__midiSynthAttenuverterBiasViewState or {}
  local runtime = ctx and ctx._dynamicAttenuverterBiasRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local amount = currentAmount(state)
      local bias = currentBias(state)
      local inputValue = state.lastInput or 0.0
      local outputValue = clamp((inputValue * amount) + bias, -1.0, 1.0)
      _G.__midiSynthAttenuverterBiasViewState[tostring(moduleId)] = {
        values = { amount = amount, bias = bias },
        inputValue = inputValue,
        outputValue = outputValue,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicAttenuverterBiasRuntime or nil
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

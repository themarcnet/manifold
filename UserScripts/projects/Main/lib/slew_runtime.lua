local M = {}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.ensureDynamicRuntime(ctx)
  ctx._dynamicSlewRuntime = ctx._dynamicSlewRuntime or {}
  _G.__midiSynthDynamicSlewRuntime = ctx._dynamicSlewRuntime
  _G.__midiSynthSlewViewState = _G.__midiSynthSlewViewState or {}
  return ctx._dynamicSlewRuntime
end

local function initializeState(state)
  state.targetInput = tonumber(state.targetInput) or 0.0
  state.currentOutput = tonumber(state.currentOutput)
  if state.currentOutput == nil then
    state.currentOutput = state.targetInput
  end
  state.outputs = state.outputs or { out = state.currentOutput }
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
      rise = 0.0,
      fall = 0.0,
      shape = 1,
    },
    targetInput = 0.0,
    currentOutput = 0.0,
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
  state.values.rise = clamp(readParam(paramBase .. "/rise", state.values.rise or 0.0), 0.0, 2000.0)
  state.values.fall = clamp(readParam(paramBase .. "/fall", state.values.fall or 0.0), 0.0, 2000.0)
  state.values.shape = math.floor(clamp(readParam(paramBase .. "/shape", state.values.shape or 1), 0.0, 2.0) + 0.5)
  return state.values
end

local function curveAlpha(dt, timeMs, shape)
  local timeSeconds = math.max(0.0, tonumber(timeMs) or 0.0) / 1000.0
  if timeSeconds <= 0.0 then
    return 1.0
  end
  local linear = clamp((tonumber(dt) or 0.0) / timeSeconds, 0.0, 1.0)
  local mode = math.floor(tonumber(shape) or 1)
  if mode == 0 then
    return linear
  elseif mode == 1 then
    return 1.0 - ((1.0 - linear) * (1.0 - linear))
  end
  return linear * linear
end

local function refreshOutput(state)
  initializeState(state)
  state.outputs.out = clamp(tonumber(state.currentOutput) or 0.0, -1.0, 1.0)
  return state.outputs
end

function M.applyInputScalar(ctx, moduleId, portId, value, meta)
  if tostring(portId or "") ~= "in" then
    return false
  end

  local state = M.resolveModuleState(ctx, moduleId)
  state.targetInput = clamp(tonumber(value) or 0.0, -1.0, 1.0)
  local riseMs = tonumber(state.values and state.values.rise) or 0.0
  local fallMs = tonumber(state.values and state.values.fall) or 0.0
  if riseMs <= 0.0 and fallMs <= 0.0 then
    state.currentOutput = state.targetInput
  end
  refreshOutput(state)
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
  if specId ~= "slew" and sourceKey ~= "slew.out" then
    return nil
  end

  local moduleId = tostring(sourceMeta.moduleId or (sourceKey:match("^([^.]+)%.") or ""))
  local state = M.resolveModuleState(ctx, moduleId)
  local outputs = refreshOutput(state)
  return {
    rawSourceValue = tonumber(outputs.out) or 0.0,
  }
end

function M.publishViewState(ctx)
  _G.__midiSynthSlewViewState = _G.__midiSynthSlewViewState or {}
  local runtime = ctx and ctx._dynamicSlewRuntime or nil
  if type(runtime) ~= "table" then
    return
  end
  for moduleId, state in pairs(runtime) do
    if type(state) == "table" then
      local outputs = refreshOutput(state)
      _G.__midiSynthSlewViewState[tostring(moduleId)] = {
        values = {
          rise = tonumber(state.values and state.values.rise) or 0.0,
          fall = tonumber(state.values and state.values.fall) or 0.0,
          shape = math.floor(tonumber(state.values and state.values.shape) or 1),
        },
        inputValue = tonumber(state.targetInput) or 0.0,
        outputValue = tonumber(outputs.out) or 0.0,
      }
    end
  end
end

function M.updateDynamicModules(ctx, dt, readParam)
  local runtime = ctx and ctx._dynamicSlewRuntime or nil
  if type(runtime) ~= "table" then
    M.publishViewState(ctx)
    return
  end

  local delta = math.max(0.0, tonumber(dt) or 0.0)
  for _, state in pairs(runtime) do
    if type(state) == "table" then
      initializeState(state)
      M.refreshModuleParams(ctx, state, readParam)
      local current = tonumber(state.currentOutput) or 0.0
      local target = tonumber(state.targetInput) or 0.0
      local diff = target - current
      if math.abs(diff) <= 0.0001 then
        state.currentOutput = target
      else
        local timeMs = diff > 0.0 and (tonumber(state.values and state.values.rise) or 0.0) or (tonumber(state.values and state.values.fall) or 0.0)
        local alpha = curveAlpha(delta, timeMs, state.values and state.values.shape)
        state.currentOutput = current + (diff * alpha)
      end
      refreshOutput(state)
    end
  end

  M.publishViewState(ctx)
end

return M

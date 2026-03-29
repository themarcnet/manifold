local MidiSynthRack = require("behaviors.rack_midisynth_specs")
local RackModuleFactory = require("ui.rack_module_factory")
local ParameterBinder = require("parameter_binder")

local M = {}

local RUNTIME_GLOBAL_KEYS = {
  "__midiSynthDynamicAdsrRuntime",
  "__midiSynthDynamicArpRuntime",
  "__midiSynthDynamicTransposeRuntime",
  "__midiSynthDynamicVelocityMapperRuntime",
  "__midiSynthDynamicScaleQuantizerRuntime",
  "__midiSynthDynamicNoteFilterRuntime",
  "__midiSynthDynamicAttenuverterBiasRuntime",
  "__midiSynthDynamicLfoRuntime",
  "__midiSynthDynamicSlewRuntime",
  "__midiSynthDynamicSampleHoldRuntime",
  "__midiSynthDynamicCompareRuntime",
  "__midiSynthDynamicCvMixRuntime",
  "__midiSynthDynamicRangeMapperRuntime",
}

local VIEW_STATE_KEYS = {
  "__midiSynthAdsrViewState",
  "__midiSynthArpViewState",
  "__midiSynthTransposeViewState",
  "__midiSynthVelocityMapperViewState",
  "__midiSynthScaleQuantizerViewState",
  "__midiSynthNoteFilterViewState",
  "__midiSynthAttenuverterBiasViewState",
  "__midiSynthLfoViewState",
  "__midiSynthSlewViewState",
  "__midiSynthSampleHoldViewState",
  "__midiSynthCompareViewState",
  "__midiSynthCvMixViewState",
  "__midiSynthRangeMapperViewState",
}

function M.clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function copyTable(source)
  local out = {}
  for key, value in pairs(source or {}) do
    out[key] = value
  end
  return out
end

local function startsWith(value, prefix)
  return tostring(value or ""):sub(1, #tostring(prefix or "")) == tostring(prefix or "")
end

function M.assertTrue(value, message)
  if not value then
    error(message or "assertTrue failed", 2)
  end
end

function M.assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEqual failed") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)), 2)
  end
end

function M.assertNear(actual, expected, epsilon, message)
  local eps = tonumber(epsilon) or 1.0e-6
  local a = tonumber(actual)
  local b = tonumber(expected)
  if a == nil or b == nil or math.abs(a - b) > eps then
    error((message or "assertNear failed") .. string.format(" (expected=%s actual=%s eps=%s)", tostring(expected), tostring(actual), tostring(eps)), 2)
  end
end

function M.runTests(label, tests)
  for i = 1, #(tests or {}) do
    M.resetGlobals()
    tests[i]()
  end
  print(string.format("OK %s %d tests", tostring(label or "tests"), #(tests or {})))
end

function M.resetGlobals()
  _G.getParam = nil
  _G.__midiSynthDynamicModuleInfo = {}
  _G.__midiSynthDynamicModuleSpecs = {}
  for i = 1, #RUNTIME_GLOBAL_KEYS do
    _G[RUNTIME_GLOBAL_KEYS[i]] = nil
  end
  for i = 1, #VIEW_STATE_KEYS do
    _G[VIEW_STATE_KEYS[i]] = {}
  end
end

function M.makeVoiceBundle(overrides)
  local voice = {
    note = 60.0,
    gate = 1.0,
    noteGate = 1.0,
    amp = 0.5,
    targetAmp = 0.5,
    currentAmp = 0.5,
    envelopeLevel = 0.5,
    envelopeStage = "sustain",
    active = true,
    sourceVoiceIndex = 1,
  }
  for key, value in pairs(overrides or {}) do
    voice[key] = value
  end
  return voice
end

function M.makeEndpoint(moduleId, specId, portId, extras)
  local endpoint = {
    meta = {
      moduleId = tostring(moduleId or ""),
      specId = tostring(specId or ""),
      portId = tostring(portId or ""),
    },
  }
  for key, value in pairs(extras or {}) do
    endpoint[key] = value
  end
  if type(extras) == "table" and type(extras.meta) == "table" then
    endpoint.meta = copyTable(endpoint.meta)
    for key, value in pairs(extras.meta) do
      endpoint.meta[key] = value
    end
  end
  return endpoint
end

function M.freshCtx(extra)
  local ctx = {
    _rackModuleSpecs = MidiSynthRack.rackModuleSpecById(),
    _dynamicAdsrRuntime = {},
    _dynamicArpRuntime = {},
    _dynamicTransposeRuntime = {},
    _dynamicVelocityMapperRuntime = {},
    _dynamicScaleQuantizerRuntime = {},
    _dynamicNoteFilterRuntime = {},
    _dynamicAttenuverterBiasRuntime = {},
    _dynamicLfoRuntime = {},
    _dynamicSlewRuntime = {},
    _dynamicSampleHoldRuntime = {},
    _dynamicCompareRuntime = {},
    _dynamicCvMixRuntime = {},
    _dynamicRangeMapperRuntime = {},
    _voices = {},
  }
  for i = 1, 8 do
    ctx._voices[i] = M.makeVoiceBundle {
      gate = 0.0,
      noteGate = 0.0,
      amp = 0.0,
      targetAmp = 0.0,
      currentAmp = 0.0,
      envelopeLevel = 0.0,
      envelopeStage = "idle",
      active = false,
      sourceVoiceIndex = i,
    }
  end
  for key, value in pairs(extra or {}) do
    ctx[key] = value
  end
  return ctx
end

function M.captureWrites()
  local writes = {}
  local writer = function(path, value)
    writes[#writes + 1] = { path = tostring(path or ""), value = value }
  end
  return writes, writer
end

function M.writeValue(writes, path)
  for i = 1, #(writes or {}) do
    local entry = writes[i]
    if type(entry) == "table" and tostring(entry.path or "") == tostring(path or "") then
      return entry.value
    end
  end
  return nil
end

function M.paramPath(spec, paramId)
  local params = spec and spec.ports and spec.ports.params or {}
  for i = 1, #params do
    local param = params[i]
    if param and tostring(param.id or "") == tostring(paramId or "") then
      return tostring(param.path or "")
    end
  end
  return nil
end

function M.paramPaths(spec)
  local out = {}
  local params = spec and spec.ports and spec.ports.params or {}
  for i = 1, #params do
    local path = tostring(params[i] and params[i].path or "")
    if path ~= "" then
      out[#out + 1] = path
    end
  end
  return out
end

function M.installMockGetParam(values)
  local previous = _G.getParam
  local lookup = copyTable(values or {})
  _G.getParam = function(path)
    return lookup[tostring(path or "")]
  end
  return function()
    _G.getParam = previous
  end
end

function M.withMockGetParam(values, fn)
  local restore = M.installMockGetParam(values)
  local ok, err = xpcall(fn, debug.traceback)
  restore()
  if not ok then
    error(err, 0)
  end
end

function M.bindDynamicModuleInfo(moduleId, specId, slotIndex, paramBase)
  _G.__midiSynthDynamicModuleInfo = _G.__midiSynthDynamicModuleInfo or {}
  _G.__midiSynthDynamicModuleInfo[tostring(moduleId or "")] = {
    specId = tostring(specId or ""),
    slotIndex = tonumber(slotIndex) or slotIndex,
    paramBase = tostring(paramBase or ""),
  }
end

function M.schemaByPath(options)
  local schema = ParameterBinder.buildSchema(options or {})
  local byPath = {}
  for i = 1, #schema do
    local entry = schema[i]
    byPath[tostring(entry.path or "")] = entry
  end
  return schema, byPath
end

function M.assertDynamicModuleContract(specId, options)
  options = options or {}
  local voiceCount = math.max(1, math.floor(tonumber(options.voiceCount) or 8))
  local ctx = options.ctx or M.freshCtx()
  local writes, setPath = M.captureWrites()
  local deps = { setPath = setPath, voiceCount = voiceCount }

  local baseSpecs = MidiSynthRack.rackModuleSpecById()
  local baseSpec = baseSpecs[tostring(specId or "")]
  M.assertTrue(type(baseSpec) == "table", tostring(specId or "") .. " base spec exists")

  local meta = RackModuleFactory.createDynamicSpawnMeta(ctx, specId, deps)
  M.assertTrue(type(meta) == "table", tostring(specId or "") .. " spawn meta created")
  M.assertEqual(meta.slotIndex, 1, tostring(specId or "") .. " allocates slot 1 first")
  M.assertEqual(meta.paramBase, RackModuleFactory.buildParamBase(specId, 1), tostring(specId or "") .. " paramBase matches factory")
  M.assertTrue(#writes > 0, tostring(specId or "") .. " reset defaults wrote params")

  local nodeId = tostring(options.nodeId or (tostring(specId or "") .. "_inst_1"))
  local registered = RackModuleFactory.registerDynamicModuleSpec(ctx, specId, nodeId, meta)
  M.assertTrue(type(registered) == "table", tostring(specId or "") .. " dynamic spec registered")
  M.assertTrue(type(ctx._rackModuleSpecs[nodeId]) == "table", tostring(specId or "") .. " stored on ctx")
  M.assertTrue(type(_G.__midiSynthDynamicModuleSpecs[nodeId]) == "table", tostring(specId or "") .. " stored globally")
  M.assertTrue(type(_G.__midiSynthDynamicModuleInfo[nodeId]) == "table", tostring(specId or "") .. " dynamic info stored globally")

  local basePaths = M.paramPaths(baseSpec)
  local registeredPaths = M.paramPaths(registered)
  M.assertEqual(#registeredPaths, #basePaths, tostring(specId or "") .. " preserves param count")

  local dynamicSchema = ParameterBinder.buildDynamicSlotSchema(specId, meta.slotIndex, { voiceCount = voiceCount })
  local schemaMap = {}
  for i = 1, #dynamicSchema do
    local entry = dynamicSchema[i]
    schemaMap[tostring(entry.path or "")] = entry
  end
  for i = 1, #registeredPaths do
    local path = registeredPaths[i]
    M.assertTrue(path ~= "", tostring(specId or "") .. " registered path non-empty")
    M.assertTrue(not path:find("__template", 1, true), tostring(specId or "") .. " registered path remapped: " .. path)
    if startsWith(path, "/midi/synth/rack/") then
      M.assertTrue(startsWith(path, meta.paramBase), tostring(specId or "") .. " registered path uses live paramBase: " .. path)
    end
    M.assertTrue(schemaMap[path] ~= nil, tostring(specId or "") .. " binder schema contains path: " .. path)
  end

  RackModuleFactory.markSlotOccupied(ctx, specId, meta.slotIndex, nodeId)
  RackModuleFactory.unregisterDynamicModuleSpec(ctx, nodeId, deps)
  M.assertEqual(ctx._rackModuleSpecs[nodeId], nil, tostring(specId or "") .. " ctx spec cleaned up")
  M.assertEqual(_G.__midiSynthDynamicModuleSpecs[nodeId], nil, tostring(specId or "") .. " global spec cleaned up")
  M.assertEqual(_G.__midiSynthDynamicModuleInfo[nodeId], nil, tostring(specId or "") .. " dynamic info cleaned up")
  M.assertEqual(RackModuleFactory.nextAvailableSlot(ctx, specId), 1, tostring(specId or "") .. " slot reusable after unregister")
end

return M

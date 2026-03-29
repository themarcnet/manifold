package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local RackModuleFactory = require("ui.rack_module_factory")
local MidiSynthRack = require("behaviors.rack_midisynth_specs")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEqual failed") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(value, message)
  if not value then
    error(message or "assertTrue failed", 2)
  end
end

local function freshCtx()
  return {
    _rackModuleSpecs = MidiSynthRack.rackModuleSpecById(),
    _dynamicAdsrRuntime = {},
    _dynamicArpRuntime = {},
    _dynamicTransposeRuntime = {},
  }
end

local function captureWrites()
  local writes = {}
  local fn = function(path, value)
    writes[#writes + 1] = { path = tostring(path or ""), value = value }
  end
  return writes, fn
end

local function writeValue(writes, path)
  for i = 1, #writes do
    if writes[i].path == path then
      return writes[i].value
    end
  end
  return nil
end

local function paramPath(spec, paramId)
  local params = spec and spec.ports and spec.ports.params or {}
  for i = 1, #params do
    local param = params[i]
    if param and tostring(param.id or "") == tostring(paramId or "") then
      return param.path
    end
  end
  return nil
end

local function resetGlobals()
  _G.__midiSynthDynamicModuleInfo = {}
  _G.__midiSynthDynamicModuleSpecs = {}
  _G.__midiSynthAdsrViewState = {}
  _G.__midiSynthArpViewState = {}
  _G.__midiSynthTransposeViewState = {}
end

local function testNextDynamicNodeId()
  local ctx = freshCtx()
  local first = RackModuleFactory.nextDynamicNodeId(ctx, "arp")
  local second = RackModuleFactory.nextDynamicNodeId(ctx, "arp")
  assertEqual(first, "arp_inst_1", "first dynamic node id")
  assertEqual(second, "arp_inst_2", "second dynamic node id")
end

local function testSlotReservationAndReuse()
  resetGlobals()
  local ctx = freshCtx()
  local writes, setPath = captureWrites()

  local meta1 = RackModuleFactory.createDynamicSpawnMeta(ctx, "adsr", { setPath = setPath })
  assertEqual(meta1.slotIndex, 1, "first ADSR slot")
  assertEqual(writeValue(writes, "/midi/synth/rack/adsr/1/attack"), 0.05, "spawn meta resets ADSR defaults")

  -- createDynamicSpawnMeta() no longer pre-reserves slots. Real occupancy starts when the
  -- spawned node is registered/marked, otherwise the same free slot stays available.
  assertEqual(RackModuleFactory.nextAvailableSlot(ctx, "adsr"), 1, "spawn meta does not pre-reserve slot")
  RackModuleFactory.markSlotOccupied(ctx, "adsr", meta1.slotIndex, "adsr_inst_1")

  local meta2 = RackModuleFactory.createDynamicSpawnMeta(ctx, "adsr", { setPath = setPath })
  assertEqual(meta2.slotIndex, 2, "second ADSR slot after first is actually occupied")

  RackModuleFactory.releaseDynamicSpawnMeta(ctx, "adsr", meta1)
  assertEqual(RackModuleFactory.nextAvailableSlot(ctx, "adsr"), 1, "released ADSR slot reused")
end

local function testSlotsGrowWithoutCap()
  resetGlobals()
  local ctx = freshCtx()
  local writes, setPath = captureWrites()

  for i = 1, 10 do
    local meta = RackModuleFactory.createDynamicSpawnMeta(ctx, "lfo", { setPath = setPath })
    assertEqual(meta.slotIndex, i, "lfo slot grows without hard cap")
    RackModuleFactory.markSlotOccupied(ctx, "lfo", meta.slotIndex, "lfo_inst_" .. i)
  end

  assertEqual(RackModuleFactory.nextAvailableSlot(ctx, "lfo"), 11, "next available slot advances past prior ceiling")
end

local function testSpecMaterializationPathRemap()
  resetGlobals()
  local ctx = freshCtx()

  local adsr = RackModuleFactory.registerDynamicModuleSpec(ctx, "adsr", "adsr_inst_1", {
    slotIndex = 2,
    paramBase = RackModuleFactory.buildParamBase("adsr", 2),
  })
  assertEqual(paramPath(adsr, "attack"), "/midi/synth/rack/adsr/2/attack", "adsr attack remap")

  local arp = RackModuleFactory.registerDynamicModuleSpec(ctx, "arp", "arp_inst_1", {
    slotIndex = 3,
    paramBase = RackModuleFactory.buildParamBase("arp", 3),
  })
  assertEqual(paramPath(arp, "hold"), "/midi/synth/rack/arp/3/hold", "arp hold remap")

  local transpose = RackModuleFactory.registerDynamicModuleSpec(ctx, "transpose", "transpose_inst_1", {
    slotIndex = 2,
    paramBase = RackModuleFactory.buildParamBase("transpose", 2),
  })
  assertEqual(paramPath(transpose, "semitones"), "/midi/synth/rack/transpose/2/semitones", "transpose semitone remap")

  local eq = RackModuleFactory.registerDynamicModuleSpec(ctx, "eq", "eq_inst_1", {
    slotIndex = 1,
    paramBase = RackModuleFactory.buildParamBase("eq", 1),
  })
  assertEqual(paramPath(eq, "b3_gain"), "/midi/synth/rack/eq/1/band/3/gain", "eq band gain remap")

  local fx = RackModuleFactory.registerDynamicModuleSpec(ctx, "fx", "fx_inst_1", {
    slotIndex = 2,
    paramBase = RackModuleFactory.buildParamBase("fx", 2),
  })
  assertEqual(paramPath(fx, "p4"), "/midi/synth/rack/fx/2/p/4", "fx param remap")
  assertEqual(fx.meta.slot, nil, "fx slot cleared")

  local filter = RackModuleFactory.registerDynamicModuleSpec(ctx, "filter", "filter_inst_1", {
    slotIndex = 2,
    paramBase = RackModuleFactory.buildParamBase("filter", 2),
  })
  assertEqual(paramPath(filter, "cutoff"), "/midi/synth/rack/filter/2/cutoff", "filter cutoff remap")

  local osc = RackModuleFactory.registerDynamicModuleSpec(ctx, "rack_oscillator", "rack_oscillator_inst_1", {
    slotIndex = 1,
    paramBase = RackModuleFactory.buildParamBase("rack_oscillator", 1),
  })
  assertEqual(paramPath(osc, "manual_level"), "/midi/synth/rack/osc/1/manualLevel", "osc manual level remap")
  assertEqual(paramPath(osc, "output"), "/midi/synth/rack/osc/1/output", "osc output remap")
end

local function testResetDefaultsWrites()
  local transposeWrites, transposeSetPath = captureWrites()
  RackModuleFactory.resetSlotParams("transpose", 2, { setPath = transposeSetPath })
  assertEqual(writeValue(transposeWrites, "/midi/synth/rack/transpose/2/semitones"), 0, "transpose semitone reset")

  local writes, setPath = captureWrites()
  RackModuleFactory.resetSlotParams("eq", 2, { setPath = setPath })
  assertEqual(writeValue(writes, "/midi/synth/rack/eq/2/mix"), 1.0, "eq mix reset")
  assertEqual(writeValue(writes, "/midi/synth/rack/eq/2/band/1/type"), 1, "eq band1 type reset")
  assertEqual(writeValue(writes, "/midi/synth/rack/eq/2/band/8/type"), 2, "eq band8 type reset")

  local oscWrites, oscSetPath = captureWrites()
  RackModuleFactory.resetSlotParams("rack_oscillator", 1, { setPath = oscSetPath, voiceCount = 4 })
  assertEqual(writeValue(oscWrites, "/midi/synth/rack/osc/1/manualPitch"), 60, "osc manual pitch reset")
  assertEqual(writeValue(oscWrites, "/midi/synth/rack/osc/1/voice/4/pwCv"), 0.5, "osc voice reset writes all voices")
end

local function testRegisterAndUnregisterCleanup()
  resetGlobals()
  local ctx = freshCtx()
  local writes, setPath = captureWrites()
  local nodeId = "arp_inst_99"

  local spec = RackModuleFactory.registerDynamicModuleSpec(ctx, "arp", nodeId, {
    slotIndex = 2,
    paramBase = RackModuleFactory.buildParamBase("arp", 2),
  })
  assertTrue(type(spec) == "table", "arp dynamic spec registered")
  RackModuleFactory.markSlotOccupied(ctx, "arp", 2, nodeId)

  ctx._dynamicArpRuntime[nodeId] = { active = true }
  _G.__midiSynthArpViewState[nodeId] = { foo = true }

  assertTrue(ctx._rackModuleSpecs[nodeId] ~= nil, "dynamic spec present on ctx")
  assertTrue(_G.__midiSynthDynamicModuleSpecs[nodeId] ~= nil, "dynamic spec present globally")
  assertEqual(_G.__midiSynthDynamicModuleInfo[nodeId].paramBase, "/midi/synth/rack/arp/2", "dynamic info paramBase")

  RackModuleFactory.unregisterDynamicModuleSpec(ctx, nodeId, {
    setPath = setPath,
    voiceCount = 8,
  })

  assertEqual(ctx._rackModuleSpecs[nodeId], nil, "ctx dynamic spec removed")
  assertEqual(_G.__midiSynthDynamicModuleSpecs[nodeId], nil, "global dynamic spec removed")
  assertEqual(_G.__midiSynthDynamicModuleInfo[nodeId], nil, "global dynamic info removed")
  assertEqual(ctx._dynamicArpRuntime[nodeId], nil, "dynamic arp runtime removed")
  assertEqual(_G.__midiSynthArpViewState[nodeId], nil, "arp view state removed")
  assertEqual(RackModuleFactory.nextAvailableSlot(ctx, "arp"), 1, "arp slot freed after unregister")
  assertEqual(writeValue(writes, "/midi/synth/rack/arp/2/rate"), 8.0, "unregister reset rate")
end

local tests = {
  testNextDynamicNodeId,
  testSlotReservationAndReuse,
  testSlotsGrowWithoutCap,
  testSpecMaterializationPathRemap,
  testResetDefaultsWrites,
  testRegisterAndUnregisterCleanup,
}

for i = 1, #tests do
  tests[i]()
end

print(string.format("OK rack_module_factory %d tests", #tests))

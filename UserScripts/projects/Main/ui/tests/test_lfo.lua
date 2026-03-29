package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("lfo_runtime")

local MODULE_ID = "lfo_inst_1"
local PARAM_BASE = "/midi/synth/rack/lfo/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "lfo", 1, PARAM_BASE)
  return ctx
end

local function readMockParam(path, fallback)
  if type(_G.getParam) == "function" then
    local value = _G.getParam(path)
    if value ~= nil then
      return value
    end
  end
  return fallback
end

local function resolveOutput(ctx, portId)
  local resolved = Runtime.resolveScalarModulationSource(
    ctx,
    MODULE_ID .. "." .. tostring(portId),
    Test.makeEndpoint(MODULE_ID, "lfo", portId)
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testSineOutputsTrackPhaseAdvance()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/rate"] = 1.0,
    [PARAM_BASE .. "/shape"] = 0.0,
    [PARAM_BASE .. "/depth"] = 1.0,
    [PARAM_BASE .. "/phase"] = 0.0,
    [PARAM_BASE .. "/retrig"] = 1.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.updateDynamicModules(ctx, 0.25, readMockParam)

    Test.assertNear(resolveOutput(ctx, "out"), 1.0, 1.0e-4, "quarter-cycle sine reaches positive peak")
    Test.assertNear(resolveOutput(ctx, "inv"), -1.0, 1.0e-4, "inv output mirrors bipolar peak")
    Test.assertNear(resolveOutput(ctx, "uni"), 1.0, 1.0e-4, "uni output reaches top of range")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthLfoViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "lfo view state published")
    Test.assertNear(view.phase, 0.25, 1.0e-4, "view state stores advanced phase")
  end)
end

local function testWrapRaisesEocAndResetReturnsToStartPhase()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/rate"] = 1.0,
    [PARAM_BASE .. "/shape"] = 4.0,
    [PARAM_BASE .. "/depth"] = 1.0,
    [PARAM_BASE .. "/phase"] = 90.0,
    [PARAM_BASE .. "/retrig"] = 1.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.updateDynamicModules(ctx, 1.1, readMockParam)
    Test.assertEqual(resolveOutput(ctx, "eoc"), 1.0, "wrapping LFO raises EOC pulse")

    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "reset", 1.0, {}), "reset input accepted")
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "reset", 0.0, {}), "reset release accepted")
    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthLfoViewState[MODULE_ID]
    Test.assertNear(view.phase, 0.25, 1.0e-4, "reset returns phase to configured start offset")
  end)
end

Test.runTests("lfo", {
  testSineOutputsTrackPhaseAdvance,
  testWrapRaisesEocAndResetReturnsToStartPhase,
})

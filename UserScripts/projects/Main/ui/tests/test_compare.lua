package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("compare_runtime")

local MODULE_ID = "compare_inst_1"
local PARAM_BASE = "/midi/synth/rack/compare/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "compare", 1, PARAM_BASE)
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
    Test.makeEndpoint(MODULE_ID, "compare", portId)
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testRisingModeGeneratesGateAndTrigger()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/threshold"] = 0.0,
    [PARAM_BASE .. "/hysteresis"] = 0.05,
    [PARAM_BASE .. "/direction"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", -0.2, {})
    Test.assertEqual(resolveOutput(ctx, "gate"), 0.0, "below threshold gate stays low")
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.2, {})
    Test.assertEqual(resolveOutput(ctx, "gate"), 1.0, "crossing upward raises gate")
    Test.assertEqual(resolveOutput(ctx, "trig"), 1.0, "crossing upward emits trigger")
  end)
end

local function testBothModeTriggersOnFallingCrossing()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/threshold"] = 0.0,
    [PARAM_BASE .. "/hysteresis"] = 0.05,
    [PARAM_BASE .. "/direction"] = 2.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.2, {})
    Test.assertEqual(resolveOutput(ctx, "gate"), 1.0, "initial high input raises gate")
    Runtime.updateDynamicModules(ctx, 0.01, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", -0.2, {})
    Test.assertEqual(resolveOutput(ctx, "gate"), 0.0, "falling below threshold clears gate in both mode")
    Test.assertEqual(resolveOutput(ctx, "trig"), 1.0, "falling crossing emits trigger in both mode")
  end)
end

Test.runTests("compare", {
  testRisingModeGeneratesGateAndTrigger,
  testBothModeTriggersOnFallingCrossing,
})

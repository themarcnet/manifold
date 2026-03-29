package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("slew_runtime")

local MODULE_ID = "slew_inst_1"
local PARAM_BASE = "/midi/synth/rack/slew/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "slew", 1, PARAM_BASE)
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

local function resolveOutput(ctx)
  local resolved = Runtime.resolveScalarModulationSource(
    ctx,
    MODULE_ID .. ".out",
    Test.makeEndpoint(MODULE_ID, "slew", "out")
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testRiseMovesTowardTargetLinearly()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/rise"] = 1000.0,
    [PARAM_BASE .. "/fall"] = 1000.0,
    [PARAM_BASE .. "/shape"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 1.0, {}), "slew accepts input")
    Runtime.updateDynamicModules(ctx, 0.5, readMockParam)
    Test.assertNear(resolveOutput(ctx), 0.5, 1.0e-4, "500ms of 1000ms rise reaches midpoint")
  end)
end

local function testFallUsesIndependentTimeConstant()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/rise"] = 100.0,
    [PARAM_BASE .. "/fall"] = 1000.0,
    [PARAM_BASE .. "/shape"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 1.0, {}), "slew accepts positive input")
    Runtime.updateDynamicModules(ctx, 0.1, readMockParam)
    Test.assertNear(resolveOutput(ctx), 1.0, 1.0e-4, "fast rise reaches target immediately")
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", -1.0, {}), "slew accepts falling input")
    Runtime.updateDynamicModules(ctx, 0.25, readMockParam)
    Test.assertNear(resolveOutput(ctx), 0.5, 1.0e-4, "slower fall only moves part-way after 250ms")
  end)
end

Test.runTests("slew", {
  testRiseMovesTowardTargetLinearly,
  testFallUsesIndependentTimeConstant,
})

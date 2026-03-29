package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("cv_mix_runtime")

local MODULE_ID = "cv_mix_inst_1"
local PARAM_BASE = "/midi/synth/rack/cv_mix/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "cv_mix", 1, PARAM_BASE)
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
    Test.makeEndpoint(MODULE_ID, "cv_mix", portId)
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testDefaultLevelOnePassesFirstInput()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/level_1"] = 1.0,
    [PARAM_BASE .. "/level_2"] = 0.0,
    [PARAM_BASE .. "/level_3"] = 0.0,
    [PARAM_BASE .. "/level_4"] = 0.0,
    [PARAM_BASE .. "/offset"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in_1", 0.25, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.25, 1.0e-6, "first input passes through at unity")
    Test.assertNear(resolveOutput(ctx, "inv"), -0.25, 1.0e-6, "inv output mirrors mixed result")
  end)
end

local function testMixesMultipleInputsWithOffset()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/level_1"] = 0.5,
    [PARAM_BASE .. "/level_2"] = 0.25,
    [PARAM_BASE .. "/level_3"] = 0.0,
    [PARAM_BASE .. "/level_4"] = 0.25,
    [PARAM_BASE .. "/offset"] = 0.1,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in_1", 0.8, {})
    Runtime.applyInputScalar(ctx, MODULE_ID, "in_2", -0.4, {})
    Runtime.applyInputScalar(ctx, MODULE_ID, "in_4", 0.2, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.45, 1.0e-6, "cv mix sums weighted inputs and offset")
    Test.assertNear(resolveOutput(ctx, "inv"), -0.45, 1.0e-6, "cv mix inverted output mirrors final result")
  end)
end

Test.runTests("cv_mix", {
  testDefaultLevelOnePassesFirstInput,
  testMixesMultipleInputsWithOffset,
})

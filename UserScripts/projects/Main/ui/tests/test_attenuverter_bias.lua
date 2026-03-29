package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("attenuverter_bias_runtime")

local MODULE_ID = "attenuverter_bias_inst_1"
local PARAM_BASE = "/midi/synth/rack/attenuverter_bias/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "attenuverter_bias", 1, PARAM_BASE)
  return ctx
end

local function resolveOutput(ctx)
  local resolved = Runtime.resolveScalarModulationSource(
    ctx,
    MODULE_ID .. ".out",
    Test.makeEndpoint(MODULE_ID, "attenuverter_bias", "out")
  )
  return resolved and resolved.rawSourceValue or nil
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

local function testAppliesAmountAndBias()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/amount"] = -0.5,
    [PARAM_BASE .. "/bias"] = 0.25,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.8), "attenuverter accepts scalar input")
    Test.assertNear(resolveOutput(ctx), -0.15, 1.0e-6, "attenuverter applies amount and bias")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthAttenuverterBiasViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "attenuverter view state published")
    Test.assertNear(view.inputValue, 0.8, 1.0e-6, "view state stores input value")
    Test.assertNear(view.outputValue, -0.15, 1.0e-6, "view state stores output value")
  end)
end

local function testOutputClampsToBipolarRange()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/amount"] = 1.0,
    [PARAM_BASE .. "/bias"] = 0.75,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.8), "attenuverter accepts scalar input for clamp test")
    Test.assertNear(resolveOutput(ctx), 1.0, 1.0e-6, "attenuverter clamps output to +1")
  end)
end

Test.runTests("attenuverter_bias", {
  testAppliesAmountAndBias,
  testOutputClampsToBipolarRange,
})

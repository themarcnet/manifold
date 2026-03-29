package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("sample_hold_runtime")

local MODULE_ID = "sample_hold_inst_1"
local PARAM_BASE = "/midi/synth/rack/sample_hold/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "sample_hold", 1, PARAM_BASE)
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
    Test.makeEndpoint(MODULE_ID, "sample_hold", portId)
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testSampleModeOnlyCapturesOnTriggerEdge()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({ [PARAM_BASE .. "/mode"] = 0.0 }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.75, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.0, 1.0e-6, "sample mode holds previous value before trigger")
    Runtime.applyInputScalar(ctx, MODULE_ID, "trig", 1.0, {})
    Runtime.applyInputScalar(ctx, MODULE_ID, "trig", 0.0, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.75, 1.0e-6, "trigger captures current input")
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.25, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.75, 1.0e-6, "held value persists after input changes")
  end)
end

local function testTrackModeFollowsInputWhileGateHigh()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({ [PARAM_BASE .. "/mode"] = 1.0 }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Runtime.applyInputScalar(ctx, MODULE_ID, "trig", 1.0, {})
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.40, {})
    Test.assertNear(resolveOutput(ctx, "out"), 0.40, 1.0e-6, "track mode follows input while trigger is high")
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", -0.20, {})
    Test.assertNear(resolveOutput(ctx, "out"), -0.20, 1.0e-6, "track mode keeps following input updates")
    Runtime.applyInputScalar(ctx, MODULE_ID, "trig", 0.0, {})
    Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.60, {})
    Test.assertNear(resolveOutput(ctx, "out"), -0.20, 1.0e-6, "track mode holds last tracked value once trigger drops")
  end)
end

Test.runTests("sample_hold", {
  testSampleModeOnlyCapturesOnTriggerEdge,
  testTrackModeFollowsInputWhileGateHigh,
})

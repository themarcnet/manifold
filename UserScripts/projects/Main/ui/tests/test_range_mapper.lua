package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("range_mapper_runtime")

local MODULE_ID = "range_mapper_inst_1"
local PARAM_BASE = "/midi/synth/rack/range_mapper/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "range_mapper", 1, PARAM_BASE)
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
    Test.makeEndpoint(MODULE_ID, "range_mapper", "out")
  )
  return resolved and resolved.rawSourceValue or nil
end

local function testClampModeConstrainsInputToRange()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/min"] = 0.2,
    [PARAM_BASE .. "/max"] = 0.7,
    [PARAM_BASE .. "/mode"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.9), "range mapper accepts scalar input")
    Test.assertNear(resolveOutput(ctx), 0.7, 1.0e-6, "clamp mode limits value to max")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthRangeMapperViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "range mapper view state published")
    Test.assertNear(view.lastInput, 0.9, 1.0e-6, "view state stores input")
    Test.assertNear(view.lastOutput, 0.7, 1.0e-6, "view state stores clamped output")
    Test.assertNear(view.effectiveMin, 0.2, 1.0e-6, "view state stores effective min")
    Test.assertNear(view.effectiveMax, 0.7, 1.0e-6, "view state stores effective max")
  end)
end

local function testRemapModeProjectsNormalizedInputIntoRange()
  local ctx = withRuntimeCtx()
  Test.withMockGetParam({
    [PARAM_BASE .. "/min"] = 0.2,
    [PARAM_BASE .. "/max"] = 0.7,
    [PARAM_BASE .. "/mode"] = 1.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputScalar(ctx, MODULE_ID, "in", 0.5), "range mapper accepts scalar input for remap mode")
    Test.assertNear(resolveOutput(ctx), 0.45, 1.0e-6, "remap mode projects normalized value into target range")
  end)
end

Test.runTests("range_mapper", {
  testClampModeConstrainsInputToRange,
  testRemapModeProjectsNormalizedInputIntoRange,
})

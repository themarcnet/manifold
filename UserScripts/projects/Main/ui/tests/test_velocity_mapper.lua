package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("velocity_mapper_runtime")

local MODULE_ID = "velocity_mapper_inst_1"
local PARAM_BASE = "/midi/synth/rack/velocity_mapper/1"

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "velocity_mapper", 1, PARAM_BASE)
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

local function testMapsAmplitudeAndPublishesViewState()
  local ctx = withRuntimeCtx()
  ctx._resolveDynamicVoiceBundleSample = function()
    return Test.makeVoiceBundle {
      note = 64,
      amp = 0.5,
      targetAmp = 0.5,
      currentAmp = 0.5,
    }
  end

  Test.withMockGetParam({
    [PARAM_BASE .. "/amount"] = 1.0,
    [PARAM_BASE .. "/curve"] = 2.0,
    [PARAM_BASE .. "/offset"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "velocity mapper accepts voice input")

    local output = Runtime.resolveVoiceBundleSample(
      ctx,
      MODULE_ID .. ".voice",
      Test.makeEndpoint(MODULE_ID, "velocity_mapper", "voice"),
      1,
      Test.clamp
    )

    Test.assertNear(output.amp, 0.25, 1.0e-6, "hard curve remaps amplitude")
    Test.assertEqual(output.note, 64, "note passes through")
    Test.assertEqual(output.gate, 1.0, "gate passes through")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthVelocityMapperViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "velocity mapper view state published")
    Test.assertNear(view.inputAmp, 0.5, 1.0e-6, "view state captures input amplitude")
    Test.assertNear(view.outputAmp, 0.25, 1.0e-6, "view state captures mapped amplitude")
    Test.assertTrue(view.active == true, "view state reports active input")
  end)
end

local function testRestoreClearsVoiceState()
  local ctx = withRuntimeCtx()
  ctx._resolveDynamicVoiceBundleSample = function()
    return Test.makeVoiceBundle {
      amp = 0.8,
      targetAmp = 0.8,
      currentAmp = 0.8,
    }
  end

  Test.withMockGetParam({
    [PARAM_BASE .. "/amount"] = 1.0,
    [PARAM_BASE .. "/curve"] = 0.0,
    [PARAM_BASE .. "/offset"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "velocity mapper seeds input state")
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 0.0, { voiceIndex = 1, action = "restore" }, 8, Test.clamp), "velocity mapper accepts restore action")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthVelocityMapperViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "velocity mapper restore still publishes view state")
    Test.assertTrue(view.active == false, "restore clears active state")
    Test.assertEqual(view.inputAmp, nil, "restore removes active input amplitude")
    Test.assertEqual(view.outputAmp, nil, "restore removes mapped output amplitude")
  end)
end

Test.runTests("velocity_mapper", {
  testMapsAmplitudeAndPublishesViewState,
  testRestoreClearsVoiceState,
})

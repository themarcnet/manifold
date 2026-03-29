package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("scale_quantizer_runtime")

local MODULE_ID = "scale_quantizer_inst_1"
local PARAM_BASE = "/midi/synth/rack/scale_quantizer/1"

local function withRuntimeCtx(note)
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "scale_quantizer", 1, PARAM_BASE)
  ctx._resolveDynamicVoiceBundleSample = function()
    return Test.makeVoiceBundle {
      note = note or 61,
      sourceVoiceIndex = 1,
    }
  end
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
  return Runtime.resolveVoiceBundleSample(
    ctx,
    MODULE_ID .. ".voice",
    Test.makeEndpoint(MODULE_ID, "scale_quantizer", "voice"),
    1,
    Test.clamp
  )
end

local function testNearestMajorQuantizesToClosestPitch()
  local ctx = withRuntimeCtx(61)
  Test.withMockGetParam({
    [PARAM_BASE .. "/root"] = 0.0,
    [PARAM_BASE .. "/scale"] = 1.0,
    [PARAM_BASE .. "/direction"] = 1.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "scale quantizer accepts voice input")
    local output = resolveOutput(ctx)
    Test.assertEqual(output.note, 60, "nearest C major quantizes C# down to C")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthScaleQuantizerViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "scale quantizer view state published")
    Test.assertEqual(view.inputNote, 61, "view state stores input note")
    Test.assertEqual(view.outputNote, 60, "view state stores quantized note")
  end)
end

local function testUpDirectionAlwaysRoundsUp()
  local ctx = withRuntimeCtx(61)
  Test.withMockGetParam({
    [PARAM_BASE .. "/root"] = 0.0,
    [PARAM_BASE .. "/scale"] = 1.0,
    [PARAM_BASE .. "/direction"] = 2.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "scale quantizer accepts voice input for up mode")
    local output = resolveOutput(ctx)
    Test.assertEqual(output.note, 62, "up mode quantizes C# to D")
  end)
end

Test.runTests("scale_quantizer", {
  testNearestMajorQuantizesToClosestPitch,
  testUpDirectionAlwaysRoundsUp,
})

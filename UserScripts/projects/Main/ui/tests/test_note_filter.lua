package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("note_filter_runtime")

local MODULE_ID = "note_filter_inst_1"
local PARAM_BASE = "/midi/synth/rack/note_filter/1"

local function withRuntimeCtx(note)
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "note_filter", 1, PARAM_BASE)
  ctx._resolveDynamicVoiceBundleSample = function()
    return Test.makeVoiceBundle {
      note = note or 20,
      sourceVoiceIndex = 1,
    }
  end
  return ctx
end

local function resolveOutput(ctx)
  return Runtime.resolveVoiceBundleSample(
    ctx,
    MODULE_ID .. ".voice",
    Test.makeEndpoint(MODULE_ID, "note_filter", "voice"),
    1,
    Test.clamp
  )
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

local function testInsideModeBlocksNotesOutsideRange()
  local ctx = withRuntimeCtx(20)
  Test.withMockGetParam({
    [PARAM_BASE .. "/low"] = 36.0,
    [PARAM_BASE .. "/high"] = 96.0,
    [PARAM_BASE .. "/mode"] = 0.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "note filter accepts voice input")
    local output = resolveOutput(ctx)
    Test.assertEqual(output.note, 20, "blocked notes preserve pitch metadata")
    Test.assertEqual(output.gate, 0.0, "blocked note clears gate")
    Test.assertEqual(output.amp, 0.0, "blocked note clears amplitude")
    Test.assertTrue(output.active == false, "blocked note becomes inactive")

    Runtime.publishViewState(ctx)
    local view = _G.__midiSynthNoteFilterViewState[MODULE_ID]
    Test.assertTrue(type(view) == "table", "note filter view state published")
    Test.assertEqual(view.inputNote, 20, "view state stores input note")
    Test.assertTrue(view.passes == false, "view state reports blocked note")
  end)
end

local function testOutsideModeLetsOutsideNotesPass()
  local ctx = withRuntimeCtx(20)
  Test.withMockGetParam({
    [PARAM_BASE .. "/low"] = 36.0,
    [PARAM_BASE .. "/high"] = 96.0,
    [PARAM_BASE .. "/mode"] = 1.0,
  }, function()
    local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)
    Runtime.refreshModuleParams(ctx, state, readMockParam)
    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, { voiceIndex = 1 }, 8, Test.clamp), "note filter accepts voice input for outside mode")
    local output = resolveOutput(ctx)
    Test.assertEqual(output.note, 20, "outside mode preserves note")
    Test.assertEqual(output.gate, 1.0, "outside mode keeps gate")
    Test.assertTrue(output.active == true, "outside mode keeps voice active")
  end)
end

Test.runTests("note_filter", {
  testInsideModeBlocksNotesOutsideRange,
  testOutsideModeLetsOutsideNotesPass,
})

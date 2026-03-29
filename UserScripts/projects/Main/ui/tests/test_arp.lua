package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local Runtime = require("arp_runtime")

local MODULE_ID = "arp_inst_1"
local PARAM_BASE = "/midi/synth/rack/arp/1"

local function readMockParam(path, fallback)
  if type(_G.getParam) == "function" then
    local value = _G.getParam(path)
    if value ~= nil then
      return value
    end
  end
  return fallback
end

local function withRuntimeCtx()
  local ctx = Test.freshCtx()
  Test.bindDynamicModuleInfo(MODULE_ID, "arp", 1, PARAM_BASE)
  return ctx
end

local function firstActiveOutput(state)
  for i = 1, #(state.outputs or {}) do
    local voice = state.outputs[i]
    if type(voice) == "table" and ((tonumber(voice.gate) or 0.0) > 0.5) then
      return voice, i
    end
  end
  return nil, nil
end

local function countActiveOutputs(state)
  local count = 0
  for i = 1, #(state.outputs or {}) do
    local voice = state.outputs[i]
    if type(voice) == "table" and ((tonumber(voice.gate) or 0.0) > 0.5) then
      count = count + 1
    end
  end
  return count
end

local function seedHeldChord(ctx)
  local bundle1 = Test.makeVoiceBundle {
    note = 60,
    gate = 1.0,
    noteGate = 1.0,
    amp = 0.31,
    targetAmp = 0.31,
    currentAmp = 0.31,
    envelopeLevel = 0.31,
    envelopeStage = "sustain",
    active = true,
    sourceVoiceIndex = 1,
  }
  local bundle2 = Test.makeVoiceBundle {
    note = 64,
    gate = 1.0,
    noteGate = 1.0,
    amp = 0.28,
    targetAmp = 0.28,
    currentAmp = 0.28,
    envelopeLevel = 0.28,
    envelopeStage = "sustain",
    active = true,
    sourceVoiceIndex = 2,
  }
  Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, {
    voiceIndex = 1,
    bundleSample = bundle1,
  }, 8, Test.clamp), "arp accepts first held voice")
  Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, {
    voiceIndex = 2,
    bundleSample = bundle2,
  }, 8, Test.clamp), "arp accepts second held voice")
end

local function configureArp(ctx, state)
  Runtime.refreshModuleParams(ctx, state, readMockParam)
end

local function testChordCaptureWindowDefersFirstStep()
  local ctx = withRuntimeCtx()
  local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)

  Test.withMockGetParam({
    [PARAM_BASE .. "/rate"] = 8.0,
    [PARAM_BASE .. "/mode"] = 0.0,
    [PARAM_BASE .. "/octaves"] = 1.0,
    [PARAM_BASE .. "/gate"] = 0.6,
    [PARAM_BASE .. "/hold"] = 0.0,
  }, function()
    configureArp(ctx, state)

    local bundle1 = Test.makeVoiceBundle {
      note = 60,
      gate = 1.0,
      noteGate = 1.0,
      amp = 0.31,
      targetAmp = 0.31,
      currentAmp = 0.31,
      envelopeLevel = 0.31,
      envelopeStage = "sustain",
      active = true,
      sourceVoiceIndex = 1,
    }

    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, {
      voiceIndex = 1,
      bundleSample = bundle1,
    }, 8, Test.clamp), "arp accepts first voice of chord")
    Runtime.updateDynamicModules(ctx, 0.01, readMockParam, 8)
    Test.assertEqual(countActiveOutputs(state), 0, "first note alone does not fire before capture window closes")

    local bundle2 = Test.makeVoiceBundle {
      note = 64,
      gate = 1.0,
      noteGate = 1.0,
      amp = 0.28,
      targetAmp = 0.28,
      currentAmp = 0.28,
      envelopeLevel = 0.28,
      envelopeStage = "sustain",
      active = true,
      sourceVoiceIndex = 2,
    }

    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, {
      voiceIndex = 2,
      bundleSample = bundle2,
    }, 8, Test.clamp), "arp accepts second voice of chord")
    Runtime.updateDynamicModules(ctx, 0.01, readMockParam, 8)
    Test.assertEqual(countActiveOutputs(state), 0, "adding another note during capture window still does not emit extra immediate lanes")

    Runtime.updateDynamicModules(ctx, 0.02, readMockParam, 8)
    Test.assertEqual(countActiveOutputs(state), 1, "arp emits first step after capture window closes")
  end)
end

local function testSequenceSignatureIgnoresEnvelopeDrift()
  local ctx = withRuntimeCtx()
  local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)

  Test.withMockGetParam({
    [PARAM_BASE .. "/rate"] = 8.0,
    [PARAM_BASE .. "/mode"] = 0.0,
    [PARAM_BASE .. "/octaves"] = 1.0,
    [PARAM_BASE .. "/gate"] = 0.6,
    [PARAM_BASE .. "/hold"] = 0.0,
  }, function()
    configureArp(ctx, state)
    seedHeldChord(ctx)

    Runtime.updateDynamicModules(ctx, 0.01, readMockParam, 8)
    Runtime.updateDynamicModules(ctx, 0.03, readMockParam, 8)
    local signatureA = tostring(state.sequenceSignature or "")
    Test.assertTrue(signatureA ~= "", "arp records sequence signature for held chord")

    local input1 = state.inputs[1]
    local input2 = state.inputs[2]
    input1.currentAmp = 0.12
    input1.envelopeStage = "decay"
    input2.currentAmp = 0.07
    input2.envelopeStage = "release"

    Runtime.updateDynamicModules(ctx, 0.01, readMockParam, 8)
    local signatureB = tostring(state.sequenceSignature or "")
    Test.assertEqual(signatureB, signatureA, "arp sequence signature stays stable across envelope-only drift")
  end)
end

local function testReleaseClearsOutputAmplitudeAndActivity()
  local ctx = withRuntimeCtx()
  local state = Runtime.resolveModuleState(ctx, MODULE_ID, 8)

  Test.withMockGetParam({
    [PARAM_BASE .. "/rate"] = 8.0,
    [PARAM_BASE .. "/mode"] = 0.0,
    [PARAM_BASE .. "/octaves"] = 1.0,
    [PARAM_BASE .. "/gate"] = 0.6,
    [PARAM_BASE .. "/hold"] = 0.0,
  }, function()
    configureArp(ctx, state)

    local bundle = Test.makeVoiceBundle {
      note = 60,
      gate = 1.0,
      noteGate = 1.0,
      amp = 0.31,
      targetAmp = 0.31,
      currentAmp = 0.31,
      envelopeLevel = 0.31,
      envelopeStage = "sustain",
      active = true,
    }

    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 1.0, {
      voiceIndex = 1,
      bundleSample = bundle,
    }, 8, Test.clamp), "arp accepts seeded input bundle")

    Runtime.updateDynamicModules(ctx, 0.01, readMockParam, 8)
    Runtime.updateDynamicModules(ctx, 0.03, readMockParam, 8)
    local output = firstActiveOutput(state)
    Test.assertTrue(output ~= nil, "arp produces at least one active output voice")
    Test.assertNear(output.currentAmp, 0.31, 1.0e-6, "arp output carries source amplitude while active")

    Test.assertTrue(Runtime.applyInputVoice(ctx, MODULE_ID, "voice_in", 0.0, {
      voiceIndex = 1,
      action = "restore",
    }, 8, Test.clamp), "arp accepts restore action")

    Runtime.updateDynamicModules(ctx, 0.05, readMockParam, 8)

    for i = 1, #(state.outputs or {}) do
      local voice = state.outputs[i]
      Test.assertEqual(voice.gate, 0.0, "released arp output gate cleared for lane " .. i)
      Test.assertEqual(voice.noteGate, 0.0, "released arp output noteGate cleared for lane " .. i)
      Test.assertNear(voice.amp, 0.0, 1.0e-6, "released arp output amp cleared for lane " .. i)
      Test.assertNear(voice.currentAmp, 0.0, 1.0e-6, "released arp output currentAmp cleared for lane " .. i)
      Test.assertNear(voice.targetAmp, 0.0, 1.0e-6, "released arp output targetAmp cleared for lane " .. i)
      Test.assertTrue(voice.active == false, "released arp output inactive for lane " .. i)
      Test.assertEqual(voice.envelopeStage, "idle", "released arp output stage reset for lane " .. i)
    end
  end)
end

Test.runTests("arp", {
  testChordCaptureWindowDefersFirstStep,
  testSequenceSignatureIgnoresEnvelopeDrift,
  testReleaseClearsOutputAmplitudeAndActivity,
})

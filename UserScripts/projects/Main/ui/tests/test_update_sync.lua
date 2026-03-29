package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/tests/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local Test = require("rack_module_testlib")
local UpdateSync = require("ui.update_sync")

local PATHS = {
  waveform = "/midi/synth/waveform",
  filterType = "/midi/synth/filter/type",
  cutoff = "/midi/synth/filter/cutoff",
  resonance = "/midi/synth/filter/resonance",
  drive = "/midi/synth/drive",
  driveShape = "/midi/synth/driveShape",
  driveBias = "/midi/synth/driveBias",
  oscRenderMode = "/midi/synth/osc/renderMode",
  fx1Type = "/midi/synth/fx/1/type",
  fx1Mix = "/midi/synth/fx/1/mix",
  fx2Type = "/midi/synth/fx/2/type",
  fx2Mix = "/midi/synth/fx/2/mix",
  delayTimeL = "/midi/synth/fx/delay/timeL",
  delayFeedback = "/midi/synth/fx/delay/feedback",
  delayMix = "/midi/synth/fx/delay/mix",
  reverbWet = "/midi/synth/fx/reverb/wet",
  output = "/midi/synth/output",
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
  sampleSource = "/midi/synth/sample/source",
  sampleCaptureBars = "/midi/synth/sample/captureBars",
  samplePitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
  samplePitchMode = "/midi/synth/sample/pitchMode",
  sampleRootNote = "/midi/synth/sample/rootNote",
  sampleLoopStart = "/midi/synth/sample/loopStart",
  sampleLoopLen = "/midi/synth/sample/loopLen",
  sampleRetrigger = "/midi/synth/sample/retrigger",
  blendMode = "/midi/synth/blend/mode",
  blendAmount = "/midi/synth/blend/amount",
  blendKeyTrack = "/midi/synth/blend/keyTrack",
  blendSamplePitch = "/midi/synth/blend/samplePitch",
  blendModAmount = "/midi/synth/blend/modAmount",
  addFlavor = "/midi/synth/blend/addFlavor",
  sampleCrossfade = "/midi/synth/sample/crossfade",
  samplePvocFFTOrder = "/midi/synth/sample/pvoc/fftOrder",
  samplePvocTimeStretch = "/midi/synth/sample/pvoc/timeStretch",
  additivePartials = "/midi/synth/osc/add/partials",
  additiveTilt = "/midi/synth/osc/add/tilt",
  additiveDrift = "/midi/synth/osc/add/drift",
  pulseWidth = "/midi/synth/pulseWidth",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  morphCurve = "/midi/synth/blend/morphCurve",
  morphConvergence = "/midi/synth/blend/morphConvergence",
  morphPhase = "/midi/synth/blend/morphPhase",
  morphSpeed = "/midi/synth/blend/morphSpeed",
  morphContrast = "/midi/synth/blend/morphContrast",
  morphSmooth = "/midi/synth/blend/morphSmooth",
  samplePlayStart = "/midi/synth/sample/playStart",
  sampleCaptureTrigger = "/midi/synth/sample/captureTrigger",
}

local function makeDeps(values)
  local lookup = values or {}
  return {
    BG_TICK_INTERVAL = 0.1,
    OSC_REPAINT_INTERVAL = 999.0,
    OSC_REPAINT_INTERVAL_WHILE_INTERACTING = 999.0,
    OSC_REPAINT_INTERVAL_MULTI_VOICE = 999.0,
    ENV_REPAINT_INTERVAL = 999.0,
    ENV_REPAINT_INTERVAL_WHILE_INTERACTING = 999.0,
    VOICE_COUNT = 8,
    FILTER_OPTIONS = { "SVF" },
    FxDefs = { FX_OPTIONS = { "None" } },
    PATHS = PATHS,
    getTime = function() return 1.0 end,
    backgroundTick = function() end,
    isUiInteracting = function() return false end,
    maybeRefreshMidiDevices = function() end,
    syncPatchViewMode = function() end,
    RackWireLayer = nil,
    readParam = function(path, fallback)
      local value = lookup[tostring(path or "")]
      if value ~= nil then
        return value
      end
      return fallback
    end,
    setPath = function() end,
    sanitizeBlendMode = function(value) return value end,
    getVoiceStackingLabels = function() return "Unison", "Detune", "Spread" end,
    setWidgetInteractiveState = function() end,
    setWidgetBounds = function() end,
    isPluginMode = function() return false end,
    activeVoiceCount = function() return 0 end,
    voiceSummary = function() return "" end,
    noteName = function(note) return tostring(note or "--") end,
    formatTime = function(value) return tostring(value or 0) end,
    syncKeyboardDisplay = function() end,
    syncMidiParamRack = function() end,
    cleanupPatchbayFromRuntime = function() end,
    patchbayInstances = {},
    ensurePatchbayWidgets = function() end,
    syncPatchbayValues = function() end,
    clamp = Test.clamp,
    setWidgetValueSilently = function(widget, value)
      if widget and widget.setValue then
        widget:setValue(value)
      end
    end,
    getModTargetState = function() return nil end,
  }
end

local function makeCtx(controlRouteState, oscCtx)
  return Test.freshCtx {
    _adsr = {},
    _oscCtx = oscCtx or { activeVoices = {} },
    _controlRouteState = controlRouteState or {},
    _rackState = { viewMode = "perf" },
    _lastUpdateTime = 0.0,
    _lastUiUpdateTime = 0.0,
    _lastOscRepaintTime = 0.0,
    _lastEnvRepaintTime = 0.0,
    _selectedMidiInputIdx = 1,
    _selectedMidiInputLabel = "None (Disabled)",
    widgets = {},
    allWidgets = {},
  }
end

local function withVoiceSamplePositions(values, fn)
  local previous = _G.getVoiceSamplePositions
  _G.getVoiceSamplePositions = function()
    return values
  end
  local ok, err = xpcall(fn, debug.traceback)
  _G.getVoiceSamplePositions = previous
  if not ok then
    error(err, 0)
  end
end

local function testCanonicalOscillatorPreviewTracksVoiceRackOutput()
  local ctx = makeCtx({
    adsrToOscillatorGateConnected = true,
    adsrToCanonicalOscillatorGateConnected = true,
    adsrToLegacyOscillatorGateConnected = false,
  })

  local deps = makeDeps({
    ["/midi/synth/voice/1/amp"] = 0.22,
    ["/midi/synth/voice/1/freq"] = 440.0,
  })

  withVoiceSamplePositions({ [1] = 0.37 }, function()
    UpdateSync.update(ctx, deps)
  end)

  Test.assertEqual(#(ctx._oscCtx.activeVoices or {}), 1, "canonical oscillator preview should stay alive through voice rack modules")
  local voice = ctx._oscCtx.activeVoices[1]
  Test.assertEqual(voice.voiceIndex, 1, "preview voice keeps routed voice index")
  Test.assertNear(voice.amp, 0.22, 1.0e-6, "preview voice keeps routed amplitude")
  Test.assertNear(voice.freq, 440.0, 1.0e-6, "preview voice keeps routed frequency")
  Test.assertNear(voice.samplePos, 0.37, 1.0e-6, "preview voice keeps sample playhead position")
  Test.assertNear(ctx._oscCtx.morphSamplePos, 0.37, 1.0e-6, "morph cursor follows dominant routed sample position")
end

local function testDisconnectedCanonicalOscillatorClearsStalePreviewVoices()
  local ctx = makeCtx({
    adsrToOscillatorGateConnected = false,
    adsrToCanonicalOscillatorGateConnected = false,
    adsrToLegacyOscillatorGateConnected = false,
  }, {
    activeVoices = {
      { voiceIndex = 7, amp = 0.9, freq = 330.0, samplePos = 0.66 },
    },
    morphSamplePos = 0.66,
  })

  local deps = makeDeps({
    ["/midi/synth/voice/1/amp"] = 0.24,
    ["/midi/synth/voice/1/freq"] = 523.25,
  })

  withVoiceSamplePositions({ [1] = 0.41 }, function()
    UpdateSync.update(ctx, deps)
  end)

  Test.assertEqual(#(ctx._oscCtx.activeVoices or {}), 0, "disconnected canonical oscillator should not retain stale preview voices")
  Test.assertNear(ctx._oscCtx.morphSamplePos or 0.0, 0.0, 1.0e-6, "disconnected canonical oscillator resets morph cursor")
end

Test.runTests("update_sync", {
  testCanonicalOscillatorPreviewTracksVoiceRackOutput,
  testDisconnectedCanonicalOscillatorClearsStalePreviewVoices,
})

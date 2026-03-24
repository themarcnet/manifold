-- MidiSynth Integration Module for Main
-- Extracted from MidiSynth_uiproject/dsp/main.lua with routing support.
-- Builds an 8-voice polysynth with two serial FX slots, ADSR, filter, EQ.
-- Optionally connects output to a looper layer input for recording.

local M = {}

local VOICE_COUNT = 8

local PATHS = {
  waveform = "/midi/synth/waveform",
  cutoff = "/midi/synth/cutoff",
  resonance = "/midi/synth/resonance",
  drive = "/midi/synth/drive",
  driveShape = "/midi/synth/driveShape",
  driveBias = "/midi/synth/driveBias",
  filterType = "/midi/synth/filterType",
  fx1Type = "/midi/synth/fx1/type",
  fx1Mix = "/midi/synth/fx1/mix",
  fx2Type = "/midi/synth/fx2/type",
  fx2Mix = "/midi/synth/fx2/mix",
  -- Note: Delay and Reverb removed - use FX slots instead
  eqOutput = "/midi/synth/eq8/output",
  eqMix = "/midi/synth/eq8/mix",
  output = "/midi/synth/output",
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
  noiseLevel = "/midi/synth/noise/level",
  noiseColor = "/midi/synth/noise/color",
  -- New oscillator parameters
  pulseWidth = "/midi/synth/pulseWidth",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  oscRenderMode = "/midi/synth/osc/renderMode",
  additivePartials = "/midi/synth/osc/add/partials",
  additiveTilt = "/midi/synth/osc/add/tilt",
  additiveDrift = "/midi/synth/osc/add/drift",

  -- Sample synth mode
  oscMode = "/midi/synth/osc/mode",                  -- 0=classic osc, 1=sample loop
  sampleSource = "/midi/synth/sample/source",        -- 0=live, 1..4=layer1..4
  sampleCaptureTrigger = "/midi/synth/sample/captureTrigger",
  sampleCaptureBars = "/midi/synth/sample/captureBars",
  samplePitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
  sampleRootNote = "/midi/synth/sample/rootNote",
  samplePlayStart = "/midi/synth/sample/playStart",  -- Yellow flag: initial playback position
  sampleLoopStart = "/midi/synth/sample/loopStart",  -- Green flag: loop jump destination
  sampleLoopLen = "/midi/synth/sample/loopLen",      -- Determines red flag (loop end)
  sampleCrossfade = "/midi/synth/sample/crossfade",  -- normalized boundary crossfade window
  sampleRetrigger = "/midi/synth/sample/retrigger",  -- 0/1
  sampleAdditiveEnabled = "/midi/synth/debug/sampleAdditive/enabled",
  sampleAdditiveMix = "/midi/synth/debug/sampleAdditive/mix",

  -- Blend mode
  blendMode = "/midi/synth/blend/mode",
  blendAmount = "/midi/synth/blend/amount",
  waveToSample = "/midi/synth/blend/waveToSample",
  sampleToWave = "/midi/synth/blend/sampleToWave",
  blendKeyTrack = "/midi/synth/blend/keyTrack",
  blendSamplePitch = "/midi/synth/blend/samplePitch",
  blendModAmount = "/midi/synth/blend/modAmount",
  addFlavor = "/midi/synth/blend/addFlavor",
  xorBehavior = "/midi/synth/blend/xorBehavior",

  -- Morph mode parameters
  morphCurve = "/midi/synth/blend/morphCurve",        -- 0=linear, 1=exponential, 2=equal-power
  morphConvergence = "/midi/synth/blend/morphConvergence", -- 0=freq-interpolate, 1=spectral-blend
  morphPhase = "/midi/synth/blend/morphPhase",        -- 0=sample-phase, 1=wave-phase, 2=reset
  morphSpeed = "/midi/synth/blend/morphSpeed",        -- temporal scan speed multiplier (0.1-4x)
  morphContrast = "/midi/synth/blend/morphContrast",  -- spectral contrast boost (0-2)
  morphSmooth = "/midi/synth/blend/morphSmooth",      -- temporal frame smoothing (0=hard, 1=buttery)
}

local function voiceFreqPath(index)
  return string.format("/midi/synth/voice/%d/freq", index)
end

local function voiceAmpPath(index)
  return string.format("/midi/synth/voice/%d/amp", index)
end

local function voiceGatePath(index)
  return string.format("/midi/synth/voice/%d/gate", index)
end

local function eq8BandEnabledPath(index)
  return string.format("/midi/synth/eq8/band/%d/enabled", index)
end

local function eq8BandTypePath(index)
  return string.format("/midi/synth/eq8/band/%d/type", index)
end

local function eq8BandFreqPath(index)
  return string.format("/midi/synth/eq8/band/%d/freq", index)
end

local function eq8BandGainPath(index)
  return string.format("/midi/synth/eq8/band/%d/gain", index)
end

local function eq8BandQPath(index)
  return string.format("/midi/synth/eq8/band/%d/q", index)
end

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function clamp01(value)
  return clamp(value, 0.0, 1.0)
end

local function roundIndex(value, maxIndex)
  return math.max(0, math.min(maxIndex, math.floor((tonumber(value) or 0) + 0.5)))
end

local function lerp(lo, hi, t)
  return lo + (hi - lo) * clamp01(t)
end

local function expLerp(lo, hi, t)
  local frac = clamp01(t)
  if lo <= 0 or hi <= 0 then
    return lerp(lo, hi, frac)
  end
  return lo * ((hi / lo) ^ frac)
end

local function noteToFrequency(note)
  return 440.0 * (2.0 ^ ((tonumber(note) - 69.0) / 12.0))
end

local FX_OPTIONS = {
  "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener",
  "Filter", "SVF Filter", "Reverb", "Stereo Delay", "Multitap",
  "Pitch Shift", "Granulator", "Ring Mod", "Formant", "EQ",
  "Limiter", "Transient",
}

local MAX_FX_PARAMS = 5
local OSC_MODE_CLASSIC = 0
local OSC_MODE_SAMPLE_LOOP = 1
local OSC_MODE_BLEND = 2
local OSC_RENDER_STANDARD = 0
local OSC_RENDER_ADD = 1
local ADD_FLAVOR_SELF = 0
local ADD_FLAVOR_DRIVEN = 1
local SAMPLE_SOURCE_LIVE = 0
local SAMPLE_SOURCE_LAYER_MIN = 1
local SAMPLE_SOURCE_LAYER_MAX = 4

function M.buildSynth(ctx, options)
  options = options or {}
  local targetLayerInput = options.targetLayerInput
  local layerSourceNodes = options.layerSourceNodes or {}

  local voices = {}
  local mix = ctx.primitives.MixerNode.new()

  local filt = ctx.primitives.SVFNode.new()
  filt:setMode(0)
  filt:setCutoff(3200)
  filt:setResonance(0.75)
  filt:setDrive(1.0)
  filt:setMix(1.0)

  local dist = ctx.primitives.DistortionNode.new()
  local eq8 = ctx.primitives.EQ8Node.new()
  local spec = ctx.primitives.SpectrumAnalyzerNode.new()
  local out = ctx.primitives.GainNode.new(2)

  local function connectMixerInput(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    -- inputIndex is 1-based bus number; target input = (bus-1) * 2 for stereo buses
    ctx.graph.connect(source, mixer, 0, (inputIndex - 1) * 2)
  end

  local function buildFxDefs()
    local P = ctx.primitives
    return {
      { -- 0: Chorus
        label = "Chorus",
        create = function()
          local node = P.ChorusNode.new()
          node:setRate(0.35); node:setDepth(0.3); node:setVoices(3)
          node:setSpread(0.6); node:setFeedback(0.08); node:setWaveform(0); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setRate(lerp(0.08, 2.4, v)) end, default = 0.5 },
          { setter = function(n, v) n:setDepth(lerp(0.05, 1.0, v)) end, default = 0.5 },
          { setter = function(n, v) n:setFeedback(lerp(0.0, 0.35, v)) end, default = 0.2 },
          { setter = function(n, v) n:setSpread(lerp(0.0, 1.0, v)) end, default = 0.6 },
          { setter = function(n, v) n:setVoices(math.floor(lerp(1, 6, v) + 0.5)) end, default = 0.4 },
        },
      },
      { -- 1: Phaser
        label = "Phaser",
        create = function()
          local node = P.PhaserNode.new()
          node:setRate(0.3); node:setDepth(0.45); node:setStages(6)
          node:setFeedback(0.35); node:setSpread(0.4)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setRate(lerp(0.05, 2.8, v)) end, default = 0.5 },
          { setter = function(n, v) n:setDepth(lerp(0.05, 1.0, v)) end, default = 0.5 },
          { setter = function(n, v) n:setFeedback(lerp(0.0, 0.8, v)) end, default = 0.4 },
          { setter = function(n, v) n:setSpread(lerp(0.0, 1.0, v)) end, default = 0.5 },
          { setter = function(n, v) n:setStages(math.floor(lerp(2, 12, v) + 0.5)) end, default = 0.4 },
        },
      },
      { -- 2: WaveShaper
        label = "WaveShaper",
        create = function()
          local node = P.WaveShaperNode.new()
          node:setCurve(0); node:setDrive(2.5); node:setOutput(0.8)
          node:setPreFilter(0.0); node:setPostFilter(0.0); node:setBias(0.0)
          node:setMix(1.0); node:setOversample(2)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setDrive(lerp(0.75, 18.0, v)) end, default = 0.3 },
          { setter = function(n, v) n:setCurve(math.floor(lerp(0, 6, v) + 0.5)) end, default = 0.0 },
          { setter = function(n, v) n:setOutput(lerp(0.25, 1.0, v)) end, default = 0.7 },
          { setter = function(n, v) n:setBias(lerp(-0.5, 0.5, v)) end, default = 0.5 },
        },
      },
      { -- 3: Compressor
        label = "Compressor",
        create = function()
          local node = P.CompressorNode.new()
          node:setThreshold(-18.0); node:setRatio(4.0); node:setAttack(5.0)
          node:setRelease(100.0); node:setKnee(6.0); node:setMakeup(0.0)
          node:setAutoMakeup(true); node:setMode(0); node:setDetectorMode(0)
          node:setSidechainHPF(100.0); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setThreshold(lerp(-40, -2, v)) end, default = 0.4 },
          { setter = function(n, v) n:setRatio(lerp(1.5, 20, v)) end, default = 0.3 },
          { setter = function(n, v) n:setAttack(lerp(1, 40, v)) end, default = 0.1 },
          { setter = function(n, v) n:setRelease(lerp(20, 250, v)) end, default = 0.3 },
          { setter = function(n, v) n:setKnee(lerp(0, 12, v)) end, default = 0.5 },
        },
      },
      { -- 4: StereoWidener
        label = "StereoWidener",
        create = function()
          local node = P.StereoWidenerNode.new()
          node:setWidth(1.25); node:setMonoLowFreq(140.0); node:setMonoLowEnable(true)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setWidth(lerp(0, 2, v)) end, default = 0.6 },
          { setter = function(n, v) n:setMonoLowFreq(lerp(40, 320, v)) end, default = 0.4 },
        },
      },
      { -- 5: Filter
        label = "Filter",
        create = function()
          local node = P.FilterNode.new()
          node:setCutoff(1000.0); node:setResonance(0.2); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setCutoff(expLerp(80, 12000, v)) end, default = 0.5 },
          { setter = function(n, v) n:setResonance(lerp(0, 1, v)) end, default = 0.2 },
        },
      },
      { -- 6: SVF Filter
        label = "SVF Filter",
        create = function()
          local node = P.SVFNode.new()
          node:setCutoff(1200); node:setResonance(0.35); node:setMode(0)
          node:setDrive(0.5); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setCutoff(expLerp(60, 10000, v)) end, default = 0.5 },
          { setter = function(n, v) n:setResonance(lerp(0.08, 1, v)) end, default = 0.4 },
          { setter = function(n, v) n:setDrive(lerp(0, 6, v)) end, default = 0.1 },
        },
      },
      { -- 7: Reverb
        label = "Reverb",
        create = function()
          local node = P.ReverbNode.new()
          node:setRoomSize(0.55); node:setDamping(0.4)
          node:setWetLevel(1.0); node:setDryLevel(0.0); node:setWidth(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setRoomSize(lerp(0.15, 0.95, v)) end, default = 0.5 },
          { setter = function(n, v) n:setDamping(lerp(0, 1, v)) end, default = 0.4 },
        },
      },
      { -- 8: Stereo Delay
        label = "Stereo Delay",
        create = function()
          local node = P.StereoDelayNode.new()
          node:setTempo(120); node:setTimeMode(0); node:setTimeL(250); node:setTimeR(375)
          node:setFeedback(0.3); node:setFeedbackCrossfeed(0.12); node:setFilterEnabled(false)
          node:setFilterCutoff(4200); node:setFilterResonance(0.5); node:setMix(1.0)
          node:setPingPong(true); node:setWidth(1.0); node:setFreeze(false); node:setDucking(0.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) local t = lerp(40, 780, v); n:setTimeL(t); n:setTimeR(t * 1.5) end, default = 0.3 },
          { setter = function(n, v) n:setFeedback(lerp(0, 0.92, v)) end, default = 0.3 },
        },
      },
      { -- 9: Multitap
        label = "Multitap",
        create = function()
          local node = P.MultitapDelayNode.new()
          node:setTapCount(4)
          node:setTapTime(1, 180); node:setTapTime(2, 320); node:setTapTime(3, 470); node:setTapTime(4, 620)
          node:setTapGain(1, 0.5); node:setTapGain(2, 0.35); node:setTapGain(3, 0.28); node:setTapGain(4, 0.2)
          node:setTapPan(1, -0.8); node:setTapPan(2, -0.25); node:setTapPan(3, 0.25); node:setTapPan(4, 0.8)
          node:setFeedback(0.3); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setTapCount(math.floor(lerp(2, 8, v) + 0.5)) end, default = 0.3 },
          { setter = function(n, v) n:setFeedback(lerp(0, 0.95, v)) end, default = 0.3 },
        },
      },
      { -- 10: Pitch Shift
        label = "Pitch Shift",
        create = function()
          local node = P.PitchShifterNode.new()
          node:setPitch(7.0); node:setWindow(80.0); node:setFeedback(0.15); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setPitch(lerp(-12, 12, v)) end, default = 0.5 },
          { setter = function(n, v) n:setWindow(lerp(30, 180, v)) end, default = 0.5 },
          { setter = function(n, v) n:setFeedback(lerp(0, 0.75, v)) end, default = 0.2 },
        },
      },
      { -- 11: Granulator
        label = "Granulator",
        create = function()
          local node = P.GranulatorNode.new()
          node:setGrainSize(90); node:setDensity(24); node:setPosition(0.6)
          node:setPitch(0.0); node:setSpray(0.25); node:setFreeze(false)
          node:setEnvelope(0); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setGrainSize(lerp(12, 280, v)) end, default = 0.3 },
          { setter = function(n, v) n:setDensity(lerp(2, 64, v)) end, default = 0.4 },
          { setter = function(n, v) n:setPosition(v) end, default = 0.6 },
          { setter = function(n, v) n:setSpray(v) end, default = 0.25 },
        },
      },
      { -- 12: Ring Mod
        label = "Ring Mod",
        create = function()
          local node = P.RingModulatorNode.new()
          node:setFrequency(120); node:setDepth(1.0); node:setMix(1.0); node:setSpread(30.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setFrequency(expLerp(20, 2000, v)) end, default = 0.3 },
          { setter = function(n, v) n:setDepth(v) end, default = 1.0 },
          { setter = function(n, v) n:setSpread(lerp(0, 180, v)) end, default = 0.2 },
        },
      },
      { -- 13: Formant
        label = "Formant",
        create = function()
          local node = P.FormantFilterNode.new()
          node:setVowel(0.0); node:setShift(0.0); node:setResonance(7.0)
          node:setDrive(1.4); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setVowel(lerp(0, 4, v)) end, default = 0.0 },
          { setter = function(n, v) n:setShift(lerp(-12, 12, v)) end, default = 0.5 },
          { setter = function(n, v) n:setResonance(lerp(2, 16, v)) end, default = 0.4 },
          { setter = function(n, v) n:setDrive(lerp(0.8, 4, v)) end, default = 0.3 },
        },
      },
      { -- 14: EQ
        label = "EQ",
        create = function()
          local node = P.EQNode.new()
          node:setLowGain(0.0); node:setLowFreq(120.0); node:setMidGain(0.0)
          node:setMidFreq(900.0); node:setMidQ(0.8); node:setHighGain(0.0)
          node:setHighFreq(8000.0); node:setOutput(0.0); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setLowGain(lerp(-12, 12, v)) end, default = 0.5 },
          { setter = function(n, v) n:setHighGain(lerp(-12, 12, v)) end, default = 0.5 },
          { setter = function(n, v) n:setMidGain(lerp(-6, 6, v)) end, default = 0.5 },
        },
      },
      { -- 15: Limiter
        label = "Limiter",
        create = function()
          local pre = P.GainNode.new(2)
          local node = P.LimiterNode.new()
          pre:setGain(1.0); node:setThreshold(-6.0); node:setRelease(80.0)
          node:setMakeup(0.0); node:setSoftClip(0.4); node:setMix(1.0)
          ctx.graph.connect(pre, node)
          return { input = pre, output = node, node = node, pre = pre }
        end,
        params = {
          { setter = function(n, v) n:setThreshold(lerp(-20, -1, v)) end, default = 0.5 },
          { setter = function(n, v, e) if e.pre then e.pre:setGain(lerp(0.6, 2, v)) end end, default = 0.3 },
          { setter = function(n, v) n:setRelease(lerp(10, 200, v)) end, default = 0.4 },
          { setter = function(n, v) n:setSoftClip(v) end, default = 0.4 },
        },
      },
      { -- 16: Transient
        label = "Transient",
        create = function()
          local node = P.TransientShaperNode.new()
          node:setAttack(0.6); node:setSustain(-0.3); node:setSensitivity(1.2); node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { setter = function(n, v) n:setAttack(lerp(-1, 1, v)) end, default = 0.5 },
          { setter = function(n, v) n:setSustain(lerp(-1, 1, v)) end, default = 0.5 },
          { setter = function(n, v) n:setSensitivity(lerp(0.2, 4, v)) end, default = 0.5 },
        },
      },
    }
  end

  local fxDefs = buildFxDefs()

  local function createFxSlot(defaultMix)
    local slot = {
      select = 0,
      paramValues = {},
      mix = clamp01(defaultMix or 0.0),
      effects = {},
    }

    for i = 1, MAX_FX_PARAMS do
      slot.paramValues[i] = 0.5
    end

    slot.dry = ctx.primitives.GainNode.new(2)
    slot.wetMixer = ctx.primitives.MixerNode.new()
    slot.wetTrim = ctx.primitives.GainNode.new(2)
    slot.output = ctx.primitives.MixerNode.new()

    connectMixerInput(slot.output, 1, slot.dry)
    connectMixerInput(slot.output, 2, slot.wetTrim)

    for i, def in ipairs(fxDefs) do
      local effect = def.create()
      effect.def = def
      effect.gate = ctx.primitives.GainNode.new(2)
      effect.gate:setGain(0.0)
      ctx.graph.connect(effect.output, effect.gate)
      connectMixerInput(slot.wetMixer, i, effect.gate)
      slot.effects[i] = effect
    end

    ctx.graph.connect(slot.wetMixer, slot.wetTrim)

    function slot.connectSource(source)
      if not source then return end
      ctx.graph.connect(source, slot.dry)
      for i = 1, #slot.effects do
        ctx.graph.connect(source, slot.effects[i].input)
      end
    end

    function slot.applySelection(value)
      slot.select = roundIndex(value or slot.select, #slot.effects - 1)
      for i = 1, #slot.effects do
        slot.effects[i].gate:setGain((i - 1) == slot.select and 1.0 or 0.0)
      end
      local def = fxDefs[slot.select + 1]
      if def and def.params then
        for pi, p in ipairs(def.params) do
          slot.paramValues[pi] = p.default or 0.5
        end
      end
      slot.applyAllParams()
    end

    function slot.applyParam(paramIdx, value)
      slot.paramValues[paramIdx] = clamp01(tonumber(value) or 0.5)
      local effect = slot.effects[slot.select + 1]
      if not effect then return end
      local def = effect.def
      if def and def.params and def.params[paramIdx] then
        def.params[paramIdx].setter(effect.node, slot.paramValues[paramIdx], effect)
      end
    end

    function slot.applyAllParams()
      local effect = slot.effects[slot.select + 1]
      if not effect then return end
      local def = effect.def
      if not def or not def.params then return end
      for pi, p in ipairs(def.params) do
        p.setter(effect.node, slot.paramValues[pi] or p.default or 0.5, effect)
      end
    end

    function slot.applyMix(value)
      slot.mix = clamp01(tonumber(value) or slot.mix)
      slot.dry:setGain(1.0 - slot.mix)
      slot.wetTrim:setGain(slot.mix)
    end

    slot.applySelection(0)
    slot.applyMix(slot.mix)
    return slot
  end

  local fx1Slot = createFxSlot(0.0)
  local fx2Slot = createFxSlot(0.0)

  -- Noise generator
  local noiseGen = ctx.primitives.NoiseGeneratorNode.new()
  noiseGen:setLevel(1.0)
  noiseGen:setColor(0.1)
  local currentNoiseLevel = 0.0

  -- Sample synth mode state
  -- DSP is always on the canonical blend path; UI tabs are view-only.
  local sampleMode = OSC_MODE_BLEND
  local renderMode = OSC_RENDER_STANDARD
  local additivePartials = 8
  local additiveTilt = 0.0
  local additiveDrift = 0.0
  local sampleSource = SAMPLE_SOURCE_LIVE
  local sampleCaptureBars = 1.0
  local samplePitchMapEnabled = false
  local sampleRootNote = 60.0
  local samplePlayStart = 0.0    -- Yellow flag: where playback starts
  local sampleLoopStart = 0.0    -- Green flag: where playback jumps to after loopEnd
  local sampleLoopLen = 1.0      -- Determines red flag (loop end)
  local sampleCrossfade = 0.1    -- Boundary crossfade window (normalized of clipped domain)
  local sampleRetrigger = true

  -- Blend mode state
  local blendMode = 0           -- 0=Mix, 1=Ring, 2=FM, 3=Sync, 4=Add, 5=Morph
  local blendAmount = 0.5       -- Mix: crossfade. Other modes: bipolar direction/amount.
  local waveToSample = 0.5      -- Legacy hidden param (deprecated)
  local sampleToWave = 0.0      -- Legacy hidden param (deprecated)
  local blendKeyTrack = 2       -- 0=wave (no sample keytrack), 1=sample, 2=both
  local blendSamplePitch = 0.0  -- Sample transpose in semitones
  local blendModAmount = 0.5    -- Modulation depth budget
  local addFlavor = ADD_FLAVOR_SELF
  local unisonVoices = 1
  local detuneCents = 0.0
  local stereoSpread = 0.0
  local xorBehavior = 0         -- Legacy hidden param (deprecated)

  -- Morph mode parameters
  local morphCurve = 2          -- 0=linear, 1=S-curve, 2=equal-power (default)
  local morphConvergence = 0.0  -- Repurposed: harmonic stretch (0=normal, 1=stretched/metallic)
  local morphPhaseParam = 0     -- Repurposed: spectral tilt (0=neutral, 1=bright, 2=dark)
  local morphSpeed = 1.0        -- Temporal scan speed multiplier
  local morphContrast = 0.5     -- Spectral contrast boost
  local morphSmooth = 0.0       -- Temporal frame smoothing

  -- Morph mode cache to avoid rebuilding partials every frame
  local cachedMorphWavePartials = nil
  local cachedMorphWaveKey = nil -- string: waveform_freq_partialCount_tilt_drift

  local cachedSamplePeaks = {}
  local cachedSamplePeakBuckets = 0
  local latestSampleAnalysis = nil
  local latestSamplePartials = nil
  local latestTemporalPartials = nil  -- TemporalTemporalData: { frameCount, frames[], frameTimes[], ... }
  local temporalExtractPending = false
  local sampleAdditiveEnabled = false
  local sampleAdditiveMix = 0.25
  local sampleAnalysisPending = false   -- analysis requested but not yet queued
  local sampleAnalysisInFlight = false  -- async worker is running
  local extractCapturedSamplePartials

  -- Forward declarations for async analysis helpers (defined later)
  local ensureSampleAnalysis = nil
  local pollAsyncSampleAnalysis = nil

  -- Capture sources for sample mode.
  -- 0 = live input, 1..4 = looper layers 1..4.
  local sampleSources = {}
  local function registerSampleSource(sourceId, sourceName, sourceNode)
    if not sourceNode then
      return
    end
    -- Add input gain boost before capture to compensate for quiet input
    local inputGain = ctx.primitives.GainNode.new(2)
    inputGain:setGain(4.0) -- 12dB boost to compensate for quiet capture
    ctx.graph.connect(sourceNode, inputGain)
    local capture = ctx.primitives.RetrospectiveCaptureNode.new(2)
    capture:setCaptureSeconds(30.0)
    ctx.graph.connect(inputGain, capture)
    -- Capture node passes through input; absorb that passthrough so this
    -- recording branch does not become an audible output sink.
    local nullSink = ctx.primitives.GainNode.new(2)
    nullSink:setGain(0.0)
    ctx.graph.connect(capture, nullSink)
    sampleSources[sourceId] = {
      id = sourceId,
      name = sourceName,
      capture = capture,
      inputGain = inputGain,
    }
  end

  -- Live source for input-dsp capture path (mode 0 = MonitorControlled).
  local liveSampleInput = ctx.primitives.PassthroughNode.new(2, 0)
  registerSampleSource(SAMPLE_SOURCE_LIVE, "live", liveSampleInput)

  for i = SAMPLE_SOURCE_LAYER_MIN, SAMPLE_SOURCE_LAYER_MAX do
    registerSampleSource(i, "layer" .. tostring(i), layerSourceNodes[i])
  end

  mix:setInputCount(VOICE_COUNT)

  for i = 1, VOICE_COUNT do
    local osc = ctx.primitives.OscillatorNode.new()
    osc:setWaveform(1)
    osc:setFrequency(220.0)
    osc:setAmplitude(0.0)
    osc:setDrive(0.0)
    osc:setDriveShape(0)
    osc:setDriveBias(0.0)
    osc:setDriveMix(1.0)
    osc:setRenderMode(OSC_RENDER_STANDARD)
    -- Initialize new oscillator parameters
    osc:setPulseWidth(0.5)
    osc:setUnison(1)
    osc:setDetune(0.0)
    osc:setSpread(0.0)

    local noiseGain = ctx.primitives.GainNode.new(2)
    noiseGain:setGain(0.0)

    local samplePlayback = ctx.primitives.SampleRegionPlaybackNode.new(2)
    samplePlayback:setLoopLength(1)
    samplePlayback:setSpeed(1.0)
    samplePlayback:setUnison(1)
    samplePlayback:setDetune(0.0)
    samplePlayback:setSpread(0.0)
    samplePlayback:stop()
    if i == 1 and ctx.graph and ctx.graph.nameNode then
      ctx.graph.nameNode(samplePlayback, "/midi/synth/sample/playback")
    end

    local sampleGain = ctx.primitives.GainNode.new(2)
    sampleGain:setGain(0.0)

    local sampleBlendGain = ctx.primitives.GainNode.new(2)
    sampleBlendGain:setGain(0.0)

    local sampleAdditive = ctx.primitives.SineBankNode.new()
    sampleAdditive:setEnabled(false)
    sampleAdditive:setAmplitude(0.0)
    sampleAdditive:setUnison(1)
    sampleAdditive:setDetune(0.0)
    sampleAdditive:setSpread(0.0)
    sampleAdditive:setDrive(0.0)
    sampleAdditive:setDriveShape(0)
    sampleAdditive:setDriveBias(0.0)
    sampleAdditive:setDriveMix(1.0)
    sampleAdditive:clearPartials()

    local sampleAdditiveGain = ctx.primitives.GainNode.new(2)
    sampleAdditiveGain:setGain(0.0)

    local morphWaveAdditive = ctx.primitives.SineBankNode.new()
    morphWaveAdditive:setEnabled(false)
    morphWaveAdditive:setAmplitude(0.0)
    morphWaveAdditive:setUnison(1)
    morphWaveAdditive:setDetune(0.0)
    morphWaveAdditive:setSpread(0.0)
    morphWaveAdditive:setDrive(0.0)
    morphWaveAdditive:setDriveShape(0)
    morphWaveAdditive:setDriveBias(0.0)
    morphWaveAdditive:setDriveMix(1.0)
    morphWaveAdditive:clearPartials()

    local morphWaveAdditiveGain = ctx.primitives.GainNode.new(2)
    morphWaveAdditiveGain:setGain(0.0)

    local blendAddOsc = ctx.primitives.OscillatorNode.new()
    blendAddOsc:setWaveform(1)
    blendAddOsc:setFrequency(220.0)
    blendAddOsc:setAmplitude(0.0)
    blendAddOsc:setDrive(0.0)
    blendAddOsc:setDriveShape(0)
    blendAddOsc:setDriveBias(0.0)
    blendAddOsc:setDriveMix(1.0)
    blendAddOsc:setRenderMode(OSC_RENDER_ADD)
    blendAddOsc:setAdditivePartials(8)
    blendAddOsc:setAdditiveTilt(0.0)
    blendAddOsc:setAdditiveDrift(0.0)
    blendAddOsc:setPulseWidth(0.5)
    blendAddOsc:setUnison(1)
    blendAddOsc:setDetune(0.0)
    blendAddOsc:setSpread(0.0)

    local addCrossfade = ctx.primitives.CrossfaderNode.new()
    addCrossfade:setPosition(0.0)
    addCrossfade:setCurve(1.0)
    addCrossfade:setMix(1.0)

    local addBranchGain = ctx.primitives.GainNode.new(2)
    addBranchGain:setGain(0.0)

    -- MIX output: wave ↔ sample source crossfade
    local mixCrossfade = ctx.primitives.CrossfaderNode.new()
    mixCrossfade:setPosition(0.0)
    mixCrossfade:setCurve(1.0)
    mixCrossfade:setMix(1.0)

    -- DIRECTIONAL output: A=sample target, B=wave target
    local directionCrossfade = ctx.primitives.CrossfaderNode.new()
    directionCrossfade:setPosition(0.0)
    directionCrossfade:setCurve(1.0)
    directionCrossfade:setMix(1.0)

    -- Base selector: Mix uses source crossfade, FM/Sync use directional target crossfade
    local basePathSelect = ctx.primitives.CrossfaderNode.new()
    basePathSelect:setPosition(-1.0)
    basePathSelect:setCurve(1.0)
    basePathSelect:setMix(1.0)

    -- Ring mode: two directional operators, then blend crossfade between outputs
    local ringWaveToSample = ctx.primitives.RingModulatorNode.new()
    ringWaveToSample:setFrequency(120.0)
    ringWaveToSample:setDepth(0.0)
    ringWaveToSample:setMix(0.0)
    ringWaveToSample:setSpread(0.0)
    if ringWaveToSample.setEnabled then ringWaveToSample:setEnabled(false) end

    local ringSampleToWave = ctx.primitives.RingModulatorNode.new()
    ringSampleToWave:setFrequency(120.0)
    ringSampleToWave:setDepth(0.0)
    ringSampleToWave:setMix(0.0)
    ringSampleToWave:setSpread(0.0)
    if ringSampleToWave.setEnabled then ringSampleToWave:setEnabled(false) end

    local ringCrossfade = ctx.primitives.CrossfaderNode.new()
    ringCrossfade:setPosition(0.0)
    ringCrossfade:setCurve(1.0)
    ringCrossfade:setMix(0.0)

    -- Final branch selector mixer:
    -- bus1 = basePathSelect (Mix/FM/Sync)
    -- bus2 = ringCrossfade
    -- bus3 = addBranchGain (Add blend family)
    local branchMixer = ctx.primitives.MixerNode.new()
    branchMixer:setInputCount(3)
    branchMixer:setGain(1, 1.0); branchMixer:setPan(1, 0.0)
    branchMixer:setGain(2, 0.0); branchMixer:setPan(2, 0.0)
    branchMixer:setGain(3, 0.0); branchMixer:setPan(3, 0.0)

    local voiceMix = ctx.primitives.MixerNode.new()
    voiceMix:setInputCount(4)
    voiceMix:setGain(1, 0.0); voiceMix:setPan(1, 0.0)
    voiceMix:setGain(2, 0.0); voiceMix:setPan(2, 0.0)
    voiceMix:setGain(3, 0.0); voiceMix:setPan(3, 0.0)
    voiceMix:setGain(4, 1.0); voiceMix:setPan(4, 0.0)

    ctx.graph.connect(noiseGen, noiseGain)
    ctx.graph.connect(samplePlayback, sampleGain)
    ctx.graph.connect(samplePlayback, sampleBlendGain)
    ctx.graph.connect(sampleAdditive, sampleAdditiveGain)
    ctx.graph.connect(morphWaveAdditive, morphWaveAdditiveGain)

    -- Hard-sync: connect sample output to osc sync input (bus 0)
    -- Sync is gated by osc:setSyncEnabled() in applyBlendParamsToVoice
    ctx.graph.connect(samplePlayback, osc, 0, 0)

    -- Mix branch: wave/source sample crossfade (bus 0=wave, bus 1=sample)
    ctx.graph.connect(osc, mixCrossfade, 0, 0)
    ctx.graph.connect(sampleBlendGain, mixCrossfade, 0, 2)

    -- Directional branch: A=wave target (sample modulates wave), B=sample target (wave modulates sample)
    -- CrossfaderNode: bus 0 = Bus A (blend=0), bus 1 = Bus B (blend=1)
    -- One connection per bus (stereo handled internally by 2-ch buffer)
    ctx.graph.connect(osc, directionCrossfade, 0, 0)
    ctx.graph.connect(sampleBlendGain, directionCrossfade, 0, 2)

    -- Base selector: mix vs directional outputs (bus 0=mix, bus 1=directional)
    ctx.graph.connect(mixCrossfade, basePathSelect, 0, 0)
    ctx.graph.connect(directionCrossfade, basePathSelect, 0, 2)

    -- Ring directional operators (4 inputs: bus 0=carrier, bus 1=modulator)
    -- waveToSample: sample carrier (bus 0), wave modulator (bus 1)
    ctx.graph.connect(sampleBlendGain, ringWaveToSample, 0, 0)
    ctx.graph.connect(osc, ringWaveToSample, 0, 2)
    -- sampleToWave: wave carrier (bus 0), sample modulator (bus 1)
    ctx.graph.connect(osc, ringSampleToWave, 0, 0)
    ctx.graph.connect(sampleBlendGain, ringSampleToWave, 0, 2)
    -- ringCrossfade: bus 0 = blend 0 (wave modulated by sample), bus 1 = blend 1 (sample modulated by wave)
    ctx.graph.connect(ringSampleToWave, ringCrossfade, 0, 0)
    ctx.graph.connect(ringWaveToSample, ringCrossfade, 0, 2)

    -- Add blend family: additive resynthesis with directional crossfade.
    -- addCrossfade bus 0 (Bus A, blend=0) = wave-centric endpoint
    --   - Add mode: blendAddOsc
    --   - Morph mode: morphWaveAdditive via gain
    -- addCrossfade bus 1 (Bus B, blend=1) = sample-centric endpoint
    --   - Add mode: sample-derived additive
    --   - Morph mode: sample-centric morph additive
    ctx.graph.connect(blendAddOsc, addCrossfade, 0, 0)
    ctx.graph.connect(morphWaveAdditiveGain, addCrossfade, 0, 0)
    ctx.graph.connect(sampleAdditiveGain, addCrossfade, 0, 2)
    ctx.graph.connect(addCrossfade, addBranchGain)

    -- Branch selection to final voice output (3 stereo buses: 0,2,4)
    ctx.graph.connect(basePathSelect, branchMixer, 0, 0)
    ctx.graph.connect(ringCrossfade, branchMixer, 0, 2)
    ctx.graph.connect(addBranchGain, branchMixer, 0, 4)
    ctx.graph.connect(branchMixer, voiceMix, 0, 6)

    ctx.graph.connect(voiceMix, mix, 0, (i - 1) * 2)

    if ctx.graph and ctx.graph.nameNode then
      ctx.graph.nameNode(sampleAdditive, string.format("/midi/synth/debug/voice/%d/sampleAdditive", i))
      ctx.graph.nameNode(sampleAdditiveGain, string.format("/midi/synth/debug/voice/%d/sampleAdditiveGain", i))
      ctx.graph.nameNode(morphWaveAdditive, string.format("/midi/synth/debug/voice/%d/morphWaveAdditive", i))
      ctx.graph.nameNode(morphWaveAdditiveGain, string.format("/midi/synth/debug/voice/%d/morphWaveAdditiveGain", i))
      ctx.graph.nameNode(blendAddOsc, string.format("/midi/synth/debug/voice/%d/blendAddOsc", i))
      ctx.graph.nameNode(addCrossfade, string.format("/midi/synth/debug/voice/%d/addCrossfade", i))
      ctx.graph.nameNode(addBranchGain, string.format("/midi/synth/debug/voice/%d/addBranchGain", i))
    end

    voices[i] = {
      osc = osc,
      noiseGain = noiseGain,
      samplePlayback = samplePlayback,
      sampleGain = sampleGain,
      sampleBlendGain = sampleBlendGain,
      sampleAdditive = sampleAdditive,
      sampleAdditiveGain = sampleAdditiveGain,
      morphWaveAdditive = morphWaveAdditive,
      morphWaveAdditiveGain = morphWaveAdditiveGain,
      blendAddOsc = blendAddOsc,
      addCrossfade = addCrossfade,
      addBranchGain = addBranchGain,
      mixCrossfade = mixCrossfade,
      directionCrossfade = directionCrossfade,
      basePathSelect = basePathSelect,
      ringWaveToSample = ringWaveToSample,
      ringSampleToWave = ringSampleToWave,
      ringCrossfade = ringCrossfade,
      branchMixer = branchMixer,
      voiceMix = voiceMix,
      gate = 0.0,
      targetAmp = 0.0,
      currentAmp = 0.0,
      waveform = 1,
      pulseWidth = 0.5,
      additivePartials = 8,
      additiveTilt = 0.0,
      additiveDrift = 0.0,
      freq = 220.0,
      amp = 0.0,
      sampleCapturedLength = 0,
      playStartNorm = 0.0,
      loopStartNorm = 0.0,
      loopEndNorm = 1.0,
      crossfadeNorm = 0.1,
      blendPhase = 0.0,
      syncPhase = 0.0,
      lastSamplePos = 0.0,
      lastBlendSampleSpeed = 1.0,
      lastBlendOscFreq = 220.0,
      lastSampleAdditiveFreq = 0.0,
      lastSampleAdditiveMix = 0.0,
      morphTemporalPos = 0.0,
      lastTemporalSamplePos = nil,
    }
  end

  -- Signal chain defaults
  -- Keep the downstream distortion node around for the future dedicated drive
  -- stage, but it is no longer part of the synth voice path.
  dist:setDrive(1.8); dist:setMix(0.14); dist:setOutput(0.9)

  eq8:setMix(1.0); eq8:setOutput(0.0)
  eq8:setBandType(1, ctx.primitives.EQ8Node.BandType.LowShelf)
  eq8:setBandFreq(1, 60.0); eq8:setBandGain(1, 0.0); eq8:setBandQ(1, 0.8)
  eq8:setBandType(2, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(2, 120.0); eq8:setBandGain(2, 0.0); eq8:setBandQ(2, 1.0)
  eq8:setBandType(3, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(3, 250.0); eq8:setBandGain(3, 0.0); eq8:setBandQ(3, 1.0)
  eq8:setBandType(4, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(4, 500.0); eq8:setBandGain(4, 0.0); eq8:setBandQ(4, 1.0)
  eq8:setBandType(5, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(5, 1000.0); eq8:setBandGain(5, 0.0); eq8:setBandQ(5, 1.0)
  eq8:setBandType(6, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(6, 2500.0); eq8:setBandGain(6, 0.0); eq8:setBandQ(6, 1.0)
  eq8:setBandType(7, ctx.primitives.EQ8Node.BandType.Peak)
  eq8:setBandFreq(7, 6000.0); eq8:setBandGain(7, 0.0); eq8:setBandQ(7, 1.0)
  eq8:setBandType(8, ctx.primitives.EQ8Node.BandType.HighShelf)
  eq8:setBandFreq(8, 12000.0); eq8:setBandGain(8, 0.0); eq8:setBandQ(8, 0.8)

  spec:setSensitivity(1.2); spec:setSmoothing(0.86); spec:setFloor(-72)
  out:setGain(0.8)

  -- Signal chain: mix → filt → fx1 → fx2 → eq8 → spec → out
  -- Note: dist stays instantiated for a future dedicated drive node, but is
  -- intentionally disconnected from the synth path now that Drive lives in the oscillator.
  ctx.graph.connect(mix, filt)
  fx1Slot.connectSource(filt)
  fx2Slot.connectSource(fx1Slot.output)
  ctx.graph.connect(fx2Slot.output, eq8)
  ctx.graph.connect(eq8, spec)
  ctx.graph.connect(spec, out)
  ctx.graph.markOutput(out)

  -- Route synth output to looper layer input for recording.
  -- Use a separate send node so `out` is an explicit OutputDSP sink.
  -- The send taps the same signal into the looper capture chain.
  if targetLayerInput then
    local send = ctx.primitives.GainNode.new(2)
    send:setGain(1.0)
    ctx.graph.connect(spec, send)
    ctx.graph.connect(send, targetLayerInput)
  end

  -- Parameter registration
  local params = {}
  local adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }

  local function addParam(path, specDef)
    ctx.params.register(path, specDef)
    params[#params + 1] = path
  end

  -- Voice params
  local voiceFreqPathToIndex = {}
  local voiceAmpPathToIndex = {}
  local voiceGatePathToIndex = {}
  local voiceLastAmp = {}
  for i = 1, VOICE_COUNT do
    local freqP = voiceFreqPath(i)
    local ampP = voiceAmpPath(i)
    local gateP = voiceGatePath(i)

    addParam(freqP, { type = "f", min = 20, max = 8000, default = 220, description = "Voice frequency " .. i })
    -- Don't bind frequency directly - handle in onParamChange for keytrack logic

    addParam(ampP, { type = "f", min = 0, max = 0.5, default = 0, description = "Voice amplitude " .. i })
    -- Don't bind amplitude - handle manually in onParamChange to support mode switching

    addParam(gateP, { type = "f", min = 0, max = 1, default = 0, description = "Voice gate " .. i })

    voiceFreqPathToIndex[freqP] = i
    voiceAmpPathToIndex[ampP] = i
    voiceGatePathToIndex[gateP] = i
    voiceLastAmp[i] = 0.0
  end

  -- Main synth params
  addParam(PATHS.waveform, { type = "f", min = 0, max = 7, default = 1, description = "Oscillator waveform" })
  addParam(PATHS.oscRenderMode, { type = "f", min = 0, max = 1, default = OSC_RENDER_STANDARD, description = "Oscillator render mode (0=standard, 1=additive)" })
  addParam(PATHS.additivePartials, { type = "f", min = 1, max = 32, default = 8, description = "Additive partial count" })
  addParam(PATHS.additiveTilt, { type = "f", min = -1, max = 1, default = 0, description = "Additive spectral tilt" })
  addParam(PATHS.additiveDrift, { type = "f", min = 0, max = 1, default = 0, description = "Additive drift amount" })
  -- New oscillator parameters
  addParam(PATHS.pulseWidth, { type = "f", min = 0.01, max = 0.99, default = 0.5, description = "Pulse width" })
  addParam(PATHS.unison, { type = "f", min = 1, max = 8, default = 1, description = "Unison voices" })
  addParam(PATHS.detune, { type = "f", min = 0, max = 100, default = 0, description = "Unison detune (cents)" })
  addParam(PATHS.spread, { type = "f", min = 0, max = 1, default = 0, description = "Stereo spread" })
  addParam(PATHS.driveShape, { type = "f", min = 0, max = 3, default = 0, description = "Oscillator drive shape" })
  addParam(PATHS.driveBias, { type = "f", min = -1, max = 1, default = 0, description = "Oscillator drive bias" })
  addParam(PATHS.filterType, { type = "f", min = 0, max = 3, default = 0, description = "Filter type" })
  addParam(PATHS.cutoff, { type = "f", min = 80, max = 16000, default = 3200, description = "Filter cutoff" })
  ctx.params.bind(PATHS.cutoff, filt, "setCutoff")
  addParam(PATHS.resonance, { type = "f", min = 0.1, max = 2, default = 0.75, description = "Filter resonance" })
  ctx.params.bind(PATHS.resonance, filt, "setResonance")
  addParam(PATHS.drive, { type = "f", min = 0, max = 20, default = 0.0, description = "Oscillator drive amount" })

  -- FX slot params (type + mix + 5 individual params per slot)
  addParam(PATHS.fx1Type, { type = "f", min = 0, max = #FX_OPTIONS - 1, default = 0, description = "FX1 type" })
  addParam(PATHS.fx1Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX1 wet/dry" })
  addParam(PATHS.fx2Type, { type = "f", min = 0, max = #FX_OPTIONS - 1, default = 0, description = "FX2 type" })
  addParam(PATHS.fx2Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX2 wet/dry" })

  for i = 0, MAX_FX_PARAMS - 1 do
    addParam(string.format("/midi/synth/fx1/p/%d", i), { type = "f", min = 0, max = 1, default = 0.5, description = "FX1 param " .. i })
    addParam(string.format("/midi/synth/fx2/p/%d", i), { type = "f", min = 0, max = 1, default = 0.5, description = "FX2 param " .. i })
  end

  -- Delay / reverb / output
  -- Note: Delay and Reverb removed from chain - use FX slots instead
  addParam(PATHS.eqOutput, { type = "f", min = -24, max = 24, default = 0, description = "EQ output trim" })
  assert(ctx.params.bind(PATHS.eqOutput, eq8, "setOutput"), "EQ8 bind failed: setOutput")
  addParam(PATHS.eqMix, { type = "f", min = 0, max = 1, default = 1, description = "EQ mix" })
  assert(ctx.params.bind(PATHS.eqMix, eq8, "setMix"), "EQ8 bind failed: setMix")
  for i = 1, 8 do
    addParam(eq8BandEnabledPath(i), { type = "f", min = 0, max = 1, default = 0, description = "EQ8 band " .. i .. " enabled" })
    assert(ctx.params.bind(eq8BandEnabledPath(i), eq8, "setBandEnabled:" .. i), "EQ8 bind failed: setBandEnabled:" .. i)
    addParam(eq8BandTypePath(i), { type = "f", min = 0, max = 6, default = i == 1 and 1 or (i == 8 and 2 or 0), description = "EQ8 band " .. i .. " type" })
    assert(ctx.params.bind(eq8BandTypePath(i), eq8, "setBandType:" .. i), "EQ8 bind failed: setBandType:" .. i)
    addParam(eq8BandFreqPath(i), { type = "f", min = 20, max = 20000, default = ({60, 120, 250, 500, 1000, 2500, 6000, 12000})[i], description = "EQ8 band " .. i .. " frequency" })
    assert(ctx.params.bind(eq8BandFreqPath(i), eq8, "setBandFreq:" .. i), "EQ8 bind failed: setBandFreq:" .. i)
    addParam(eq8BandGainPath(i), { type = "f", min = -24, max = 24, default = 0, description = "EQ8 band " .. i .. " gain" })
    assert(ctx.params.bind(eq8BandGainPath(i), eq8, "setBandGain:" .. i), "EQ8 bind failed: setBandGain:" .. i)
    addParam(eq8BandQPath(i), { type = "f", min = 0.1, max = 24, default = (i == 1 or i == 8) and 0.8 or 1.0, description = "EQ8 band " .. i .. " Q" })
    assert(ctx.params.bind(eq8BandQPath(i), eq8, "setBandQ:" .. i), "EQ8 bind failed: setBandQ:" .. i)
  end
  addParam(PATHS.output, { type = "f", min = 0, max = 1, default = 0.8, description = "Output gain" })
  ctx.params.bind(PATHS.output, out, "setGain")

  -- ADSR
  addParam(PATHS.attack, { type = "f", min = 0.001, max = 5, default = 0.05, description = "ADSR attack" })
  addParam(PATHS.decay, { type = "f", min = 0.001, max = 5, default = 0.2, description = "ADSR decay" })
  addParam(PATHS.sustain, { type = "f", min = 0, max = 1, default = 0.7, description = "ADSR sustain" })
  addParam(PATHS.release, { type = "f", min = 0.001, max = 10, default = 0.4, description = "ADSR release" })

  -- Noise
  addParam(PATHS.noiseLevel, { type = "f", min = 0, max = 1, default = 0, description = "Noise level" })
  addParam(PATHS.noiseColor, { type = "f", min = 0, max = 1, default = 0.1, description = "Noise color" })
  ctx.params.bind(PATHS.noiseColor, noiseGen, "setColor")

  -- Sample mode params (first-run backend; UI can opt-in later without breaking classic controls)
  addParam(PATHS.oscMode, { type = "f", min = 0, max = 2, default = OSC_MODE_CLASSIC, description = "Osc mode (0=classic, 1=sample loop, 2=blend)" })
  addParam(PATHS.sampleSource, { type = "f", min = SAMPLE_SOURCE_LIVE, max = SAMPLE_SOURCE_LAYER_MAX, default = SAMPLE_SOURCE_LIVE, description = "Sample source (0=live, 1..4=layers)" })
  addParam(PATHS.sampleCaptureTrigger, { type = "f", min = 0, max = 1, default = 0, description = "Trigger sample capture from current source" })
  addParam(PATHS.sampleCaptureBars, { type = "f", min = 0.0625, max = 16, default = 1.0, description = "Capture length in bars" })
  addParam(PATHS.samplePitchMapEnabled, { type = "f", min = 0, max = 1, default = 0, description = "Auto-apply detected sample pitch to root note" })
  addParam(PATHS.sampleRootNote, { type = "f", min = 12, max = 96, default = 60, description = "Sample root MIDI note" })
  addParam(PATHS.samplePlayStart, { type = "f", min = 0, max = 0.95, default = 0, description = "Sample play start - yellow flag (normalized)" })
  addParam(PATHS.sampleLoopStart, { type = "f", min = 0, max = 0.95, default = 0, description = "Sample loop start - green flag (normalized)" })
  addParam(PATHS.sampleLoopLen, { type = "f", min = 0.05, max = 1.0, default = 1.0, description = "Sample loop length (normalized)" })
  addParam(PATHS.sampleCrossfade, { type = "f", min = 0.0, max = 0.5, default = 0.1, description = "Boundary crossfade window" })
  addParam(PATHS.sampleRetrigger, { type = "f", min = 0, max = 1, default = 1, description = "Retrigger sample from loop start on note-on" })
  addParam(PATHS.sampleAdditiveEnabled, { type = "f", min = 0, max = 1, default = 0, description = "Debug gate for hidden sample-derived additive layer" })
  addParam(PATHS.sampleAdditiveMix, { type = "f", min = 0, max = 1, default = 0.25, description = "Debug mix for hidden sample-derived additive layer" })

  -- Blend mode params
  addParam(PATHS.blendMode, { type = "f", min = 0, max = 5, default = 0, description = "Blend mode (0=Mix, 1=Ring, 2=FM, 3=Sync, 4=Add, 5=Morph)" })
  addParam(PATHS.blendAmount, { type = "f", min = 0, max = 1, default = 0.5, description = "Blend amount / wetness" })
  addParam(PATHS.waveToSample, { type = "f", min = 0, max = 1, default = 0.5, description = "Wave influence on sample path" })
  addParam(PATHS.sampleToWave, { type = "f", min = 0, max = 1, default = 0.0, description = "Sample influence on wave path" })
  addParam(PATHS.blendKeyTrack, { type = "f", min = 0, max = 2, default = 2, description = "Keytrack: 0=wave, 1=sample, 2=both" })
  addParam(PATHS.blendSamplePitch, { type = "f", min = -24, max = 24, default = 0, description = "Blend sample transpose (semitones)" })
  addParam(PATHS.blendModAmount, { type = "f", min = 0, max = 1, default = 0.5, description = "Blend mode modulation depth" })
  addParam(PATHS.addFlavor, { type = "f", min = 0, max = 1, default = 0, description = "Add mode flavor (0=Self, 1=Driven)" })
  addParam(PATHS.xorBehavior, { type = "f", min = 0, max = 1, default = 0, description = "XOR behavior: 0=crush/xor, 1=gate/compare" })

  -- Morph mode parameters
  addParam(PATHS.morphCurve, { type = "f", min = 0, max = 2, default = 2, description = "Morph crossfade curve: 0=linear, 1=S-curve, 2=equal-power" })
  addParam(PATHS.morphConvergence, { type = "f", min = 0, max = 1, default = 0, description = "Harmonic stretch: 0=normal, 1=metallic/bell character" })
  addParam(PATHS.morphPhase, { type = "f", min = 0, max = 2, default = 0, description = "Spectral tilt: 0=neutral, 1=bright, 2=dark" })
  addParam(PATHS.morphSpeed, { type = "f", min = 0.1, max = 4.0, default = 1.0, description = "Temporal scan speed: 0.1=slow, 4.0=fast" })
  addParam(PATHS.morphContrast, { type = "f", min = 0, max = 2, default = 0.5, description = "Spectral contrast: 0=subtle, 2=aggressive" })
  addParam(PATHS.morphSmooth, { type = "f", min = 0, max = 1, default = 0.0, description = "Frame smoothing: 0=hard cuts, 1=buttery" })

  local function hostSamplesPerBar()
    if ctx.host and ctx.host.getParam then
      local spb = tonumber(ctx.host.getParam("/core/behavior/samplesPerBar")) or 0
      if spb > 0 then
        return spb
      end
    end

    local sr = (ctx.host and ctx.host.getSampleRate and tonumber(ctx.host.getSampleRate())) or 44100.0
    local tempo = (ctx.host and ctx.host.getParam and tonumber(ctx.host.getParam("/core/behavior/tempo"))) or 120.0
    if sr <= 0 then sr = 44100.0 end
    if tempo <= 0 then tempo = 120.0 end
    return (sr * 240.0) / tempo
  end

  local function selectedSampleSourceEntry()
    local src = sampleSources[sampleSource]
    if src and src.capture and src.capture.__node then
      return src
    end
    local fallback = sampleSources[SAMPLE_SOURCE_LIVE]
    if fallback and fallback.capture and fallback.capture.__node then
      return fallback
    end
    return nil
  end

  local function selectedSampleSourceCapture()
    local entry = selectedSampleSourceEntry()
    return entry and entry.capture and entry.capture.__node or nil
  end

  local function reverseTable(tbl)
    local out = {}
    for i = #tbl, 1, -1 do
      out[#out + 1] = tbl[i]
    end
    return out
  end

  local function resamplePeaks(peaks, numBuckets)
    if type(peaks) ~= "table" or #peaks == 0 or numBuckets <= 0 then
      return {}
    end
    if #peaks == numBuckets then
      return peaks
    end
    local out = {}
    local srcCount = #peaks
    for i = 1, numBuckets do
      local t = (i - 1) / math.max(1, numBuckets - 1)
      local srcIndex = math.floor(t * math.max(0, srcCount - 1)) + 1
      out[i] = peaks[srcIndex] or 0.0
    end
    return out
  end

  local function hasUsableSampleAdditivePartials(partials)
    return type(partials) == "table"
      and (tonumber(partials.activeCount) or 0) > 0
      and (tonumber(partials.fundamental) or 0.0) > 0.0
      and partials.reliable ~= false
  end

  local function buildDrivenWaveWeight(waveform, harmonicNumber, width)
    local wf = roundIndex(waveform, 7)
    local h = math.max(1, math.floor(tonumber(harmonicNumber) or 1))
    local pulse = clamp(width or 0.5, 0.01, 0.99)

    if wf == 0 then
      return (h == 1) and 1.0 or 0.0
    elseif wf == 1 then
      return 1.0 / h
    elseif wf == 2 then
      return (h % 2 == 1) and (1.0 / h) or 0.0
    elseif wf == 3 then
      return (h % 2 == 1) and (1.0 / (h * h)) or 0.0
    elseif wf == 4 then
      return ((h == 1) and 0.45 or 0.0) + (0.55 / h)
    elseif wf == 5 then
      return 1.0 / math.sqrt(h)
    elseif wf == 6 then
      return math.abs(math.sin(math.pi * h * pulse)) / h
    elseif wf == 7 then
      return (1.0 / h) * (1.0 + 0.22 * math.cos(h * 0.73) + 0.15 * math.sin(h * 1.11))
    end

    return 1.0 / h
  end

  local function buildDrivenSampleAdditivePartials(sourcePartials, voice)
    if not hasUsableSampleAdditivePartials(sourcePartials) then
      return sourcePartials
    end

    local width = (voice and voice.pulseWidth) or pulseWidth or 0.5
    local waveform = (voice and voice.waveform) or 1
    local out = {
      activeCount = 0,
      fundamental = tonumber(sourcePartials.fundamental) or 0.0,
      inharmonicity = tonumber(sourcePartials.inharmonicity) or 0.0,
      brightness = tonumber(sourcePartials.brightness) or 0.0,
      rmsLevel = tonumber(sourcePartials.rmsLevel) or 0.0,
      peakLevel = tonumber(sourcePartials.peakLevel) or 0.0,
      attackTimeMs = tonumber(sourcePartials.attackTimeMs) or 0.0,
      spectralCentroidHz = tonumber(sourcePartials.spectralCentroidHz) or 0.0,
      analysisStartSample = tonumber(sourcePartials.analysisStartSample) or 0,
      analysisEndSample = tonumber(sourcePartials.analysisEndSample) or 0,
      numSamples = tonumber(sourcePartials.numSamples) or 0,
      numChannels = tonumber(sourcePartials.numChannels) or 1,
      sampleRate = tonumber(sourcePartials.sampleRate) or 44100.0,
      isPercussive = sourcePartials.isPercussive,
      reliable = sourcePartials.reliable,
      algorithm = "wave-driven-additive",
      partials = {}
    }

    local maxAmp = 0.0
    local sourceEntries = sourcePartials.partials or {}
    for i = 1, math.min(8, tonumber(sourcePartials.activeCount) or 0) do
      local src = sourceEntries[i]
      if type(src) == "table" then
        local srcAmp = math.max(0.0, tonumber(src.amplitude) or 0.0)
        local weight = math.max(0.0, buildDrivenWaveWeight(waveform, i, width))
        local amp = srcAmp * weight
        out.partials[#out.partials + 1] = {
          frequency = tonumber(src.frequency) or 0.0,
          amplitude = amp,
          phase = tonumber(src.phase) or 0.0,
          decayRate = tonumber(src.decayRate) or 0.0,
        }
        maxAmp = math.max(maxAmp, amp)
      end
    end

    if maxAmp <= 1.0e-6 then
      out.partials = {}
      out.activeCount = 0
      out.fundamental = 0.0
      return out
    end

    local kept = {}
    for i = 1, #out.partials do
      local part = out.partials[i]
      if part.amplitude > (maxAmp * 0.02) then
        kept[#kept + 1] = {
          frequency = part.frequency,
          amplitude = part.amplitude / maxAmp,
          phase = part.phase,
          decayRate = part.decayRate,
        }
      end
    end
    out.partials = kept
    out.activeCount = #kept
    if out.activeCount <= 0 then
      out.fundamental = 0.0
    end
    return out
  end

  --- Normalize partials to ratio space (fundamental = 1.0).
  --- Returns nil if input is unusable.
  local function normalizePartials(partials)
    if type(partials) ~= "table" then return nil end
    local count = tonumber(partials.activeCount) or 0
    if count <= 0 then return nil end
    local fund = tonumber(partials.fundamental) or 0.0
    if fund <= 1.0e-6 then
      local p1 = partials.partials and partials.partials[1]
      fund = p1 and (tonumber(p1.frequency) or 0.0) or 0.0
    end
    if fund <= 1.0e-6 then return nil end

    local out = { activeCount = count, fundamental = fund, partials = {} }
    for i = 1, count do
      local p = partials.partials and partials.partials[i]
      if p then
        out.partials[i] = {
          ratio = math.max(0.01, (tonumber(p.frequency) or 0.0) / fund),
          amplitude = tonumber(p.amplitude) or 0.0,
          phase = tonumber(p.phase) or 0.0,
          decayRate = tonumber(p.decayRate) or 0.0,
        }
      else
        out.partials[i] = { ratio = 0.0, amplitude = 0.0, phase = 0.0, decayRate = 0.0 }
      end
    end
    return out
  end

  --- Core spectral morph between two normalized partial sets.
  --- position: 0 = source A (wave), 1 = source B (sample)
  --- curve: 0=linear, 1=S-curve, 2=equal-power
  --- depth: 0=only amplitudes morph (freqs snap to dominant), 1=full freq+amp morph
  --- Returns a PartialData-compatible table with absolute frequencies.
  local function morphPartials(partialsA, partialsB, position, curve, depth)
    local a = normalizePartials(partialsA)
    local b = normalizePartials(partialsB)
    if not a and not b then return nil end
    if not a then return partialsB end
    if not b then return partialsA end

    local pos = clamp01(position or 0.0)
    local dep = clamp01(depth or 1.0)
    local aCount = a.activeCount or 0
    local bCount = b.activeCount or 0
    local maxCount = math.max(aCount, bCount)
    if maxCount <= 0 then return nil end

    -- Amplitude crossfade coefficients (affected by curve)
    local aCoeff, bCoeff
    local curveType = curve or 2
    if curveType == 0 then
      -- Linear
      aCoeff = 1.0 - pos
      bCoeff = pos
    elseif curveType == 1 then
      -- S-curve (smooth cosine interpolation)
      local t = 0.5 - 0.5 * math.cos(pos * math.pi)
      aCoeff = 1.0 - t
      bCoeff = t
    else
      -- Equal-power (default)
      aCoeff = math.cos(pos * math.pi * 0.5)
      bCoeff = math.sin(pos * math.pi * 0.5)
    end

    -- Frequency morph amount: depth scales how much frequencies slide
    -- At depth=0: freqs stay with the dominant source (snap crossfade)
    -- At depth=1: full log-frequency interpolation
    local freqMorphT = pos * dep

    local out = {
      activeCount = maxCount,
      fundamental = 1.0,
      partials = {},
    }

    for i = 1, maxCount do
      local ap = (i <= aCount) and a.partials[i] or nil
      local bp = (i <= bCount) and b.partials[i] or nil
      local aRatio = ap and (tonumber(ap.ratio) or 0.0) or 0.0
      local aAmp   = ap and (tonumber(ap.amplitude) or 0.0) or 0.0
      local aPhase  = ap and (tonumber(ap.phase) or 0.0) or 0.0
      local aDecay  = ap and (tonumber(ap.decayRate) or 0.0) or 0.0
      local bRatio = bp and (tonumber(bp.ratio) or 0.0) or 0.0
      local bAmp   = bp and (tonumber(bp.amplitude) or 0.0) or 0.0
      local bPhase  = bp and (tonumber(bp.phase) or 0.0) or 0.0
      local bDecay  = bp and (tonumber(bp.decayRate) or 0.0) or 0.0

      -- Frequency: log-space interpolation (musical pitch morph)
      local morphRatio
      if aRatio <= 0.01 and bRatio <= 0.01 then
        morphRatio = 0.0
      elseif aRatio <= 0.01 then
        morphRatio = bRatio
      elseif bRatio <= 0.01 then
        morphRatio = aRatio
      else
        -- Log-lerp: exp( (1-t)*log(a) + t*log(b) )
        local logA = math.log(aRatio)
        local logB = math.log(bRatio)
        morphRatio = math.exp(logA + (logB - logA) * freqMorphT)
      end

      -- Amplitude: crossfade with curve
      local morphAmp = aAmp * aCoeff + bAmp * bCoeff

      -- Phase: crossfade linearly
      local morphPhase = aPhase + (bPhase - aPhase) * pos

      -- Decay: crossfade
      local morphDecay = aDecay + (bDecay - aDecay) * pos

      out.partials[i] = {
        frequency = morphRatio,  -- ratio space (fundamental = 1.0)
        amplitude = morphAmp,
        phase = morphPhase,
        decayRate = morphDecay,
      }
    end

    return out
  end

  local function applySampleDerivedPartialsToVoices(partials)
    local usable = hasUsableSampleAdditivePartials(partials)
    for i = 1, VOICE_COUNT do
      local voice = voices[i]
      if voice and voice.sampleAdditive then
        if usable then
          local voicePartials = (addFlavor == ADD_FLAVOR_DRIVEN)
            and buildDrivenSampleAdditivePartials(partials, voice)
            or partials
          voice.sampleAdditive:setPartials(voicePartials)
        else
          voice.sampleAdditive:clearPartials()
        end
      end
    end
    return usable
  end

  local function refreshSampleDerivedPartialsFromPlayback(reason)
    -- Ensure analysis has run if capture just happened
    ensureSampleAnalysis()
    local partials = extractCapturedSamplePartials(false, true)
    local usable = applySampleDerivedPartialsToVoices(partials)
    return usable
  end

  -- Temporal (multi-frame) partial extraction for evolving morph.
  -- This is heavier than single-frame, so we only call it when Morph mode is active
  -- and the sample has changed.
  local function extractTemporalPartials(reason)
    local voice = voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastTemporalPartials then
      latestTemporalPartials = nil
      return nil
    end

    local ok, temporal = pcall(function()
      return playback:getLastTemporalPartials()
    end)
    if not ok or type(temporal) ~= "table" then
      return latestTemporalPartials
    end

    local fc = tonumber(temporal.frameCount) or 0
    if fc > 0 then
      latestTemporalPartials = temporal
      for i = 1, VOICE_COUNT do
        voices[i].morphTemporalPos = 0.0
      end
      return temporal
    end

    ensureSampleAnalysis()
    return latestTemporalPartials
  end

  local function mapTemporalPositionForVoice(voice, samplePos)
    local pos = math.max(0.0, math.min(1.0, tonumber(samplePos) or 0.0))
    local speed = clamp(tonumber(morphSpeed) or 1.0, 0.1, 4.0)

    -- Make Speed obvious and deterministic: scale the actual sample position.
    -- This matches the UI preview and avoids the previous barely-audible delta drift.
    local outPos = (pos * speed) % 1.0
    if outPos < 0.0 then outPos = outPos + 1.0 end

    if voice then
      voice.lastTemporalSamplePos = pos
      voice.morphTemporalPos = outPos
    end
    return outPos
  end

  -- Get the interpolated partial frame at a normalized position (0..1) in temporal data.
  -- Uses morphSmooth to go from stepped frames -> smooth interpolation,
  -- and morphContrast to exaggerate spectral differences.
  local function getTemporalFrameAtPosition(temporal, pos)
    if not temporal or not temporal.frames or not temporal.frameTimes then return nil end
    local fc = tonumber(temporal.frameCount) or 0
    if fc <= 0 then return nil end
    if fc == 1 then return temporal.frames[1] end

    local t = math.max(0.0, math.min(1.0, pos))
    local smoothAmt = clamp01(tonumber(morphSmooth) or 0.0)
    local contrastAmt = clamp(tonumber(morphContrast) or 0.5, 0.0, 2.0)

    -- Find bracketing frames
    local lo, hi = 1, fc
    for i = 1, fc - 1 do
      local ft = tonumber(temporal.frameTimes[i + 1]) or 1.0
      if ft > t then
        lo = i
        hi = i + 1
        break
      end
      lo = i
      hi = i
    end

    if lo == hi then return temporal.frames[lo] end

    local loTime = tonumber(temporal.frameTimes[lo]) or 0.0
    local hiTime = tonumber(temporal.frameTimes[hi]) or 1.0
    local span = hiTime - loTime
    local rawFrac = (span > 1e-6) and math.max(0.0, math.min(1.0, (t - loTime) / span)) or 0.0

    -- Smooth is intentionally strong:
    --   0.0 = nearest-frame stepping
    --   1.0 = full glide across the frame span
    local frac
    if smoothAmt <= 0.001 then
      frac = (rawFrac >= 0.5) and 1.0 or 0.0
    else
      local edge0 = 0.5 - 0.5 * smoothAmt
      local edge1 = 0.5 + 0.5 * smoothAmt
      if rawFrac <= edge0 then
        frac = 0.0
      elseif rawFrac >= edge1 then
        frac = 1.0
      else
        frac = (rawFrac - edge0) / math.max(1.0e-6, edge1 - edge0)
        frac = frac * frac * (3.0 - 2.0 * frac) -- smoothstep
      end
    end

    local frameA = temporal.frames[lo]
    local frameB = temporal.frames[hi]
    if not frameA or not frameB then return frameA or frameB end

    -- Interpolate partials
    local countA = tonumber(frameA.activeCount) or 0
    local countB = tonumber(frameB.activeCount) or 0
    local maxCount = math.max(countA, countB)
    if maxCount <= 0 then return frameA end

    local result = {
      activeCount = maxCount,
      fundamental = (tonumber(frameA.fundamental) or 0) + ((tonumber(frameB.fundamental) or 0) - (tonumber(frameA.fundamental) or 0)) * frac,
      brightness = (tonumber(frameA.brightness) or 0) + ((tonumber(frameB.brightness) or 0) - (tonumber(frameA.brightness) or 0)) * frac,
      rmsLevel = (tonumber(frameA.rmsLevel) or 0) + ((tonumber(frameB.rmsLevel) or 0) - (tonumber(frameA.rmsLevel) or 0)) * frac,
      partials = {},
      frequencies = {},
      amplitudes = {},
      phases = {},
    }

    local freqsA = frameA.frequencies or {}
    local freqsB = frameB.frequencies or {}
    local ampsA = frameA.amplitudes or {}
    local ampsB = frameB.amplitudes or {}
    local phsA = frameA.phases or {}
    local phsB = frameB.phases or {}

    for i = 1, maxCount do
      local af = tonumber(freqsA[i]) or 0.0
      local bf = tonumber(freqsB[i]) or 0.0
      local aa = tonumber(ampsA[i]) or 0.0
      local ba = tonumber(ampsB[i]) or 0.0
      local ap = tonumber(phsA[i]) or 0.0
      local bp = tonumber(phsB[i]) or 0.0

      -- Log-frequency interpolation
      local freq
      if af <= 0.01 and bf <= 0.01 then freq = 0.0
      elseif af <= 0.01 then freq = bf * frac
      elseif bf <= 0.01 then freq = af * (1.0 - frac)
      else freq = math.exp(math.log(af) + (math.log(bf) - math.log(af)) * frac) end

      local rawAmp = aa + (ba - aa) * frac

      -- Contrast control: 0 = flatter / gentler, 2 = more dramatic spectral peaks
      local contrastExponent = 1.15 - contrastAmt * 0.45
      local contrastGain = 1.0 + contrastAmt * 0.85
      local contrastAmp = rawAmp > 0.001 and (math.pow(rawAmp, contrastExponent) * contrastGain) or 0.0

      -- Kill truly silent partials (noise floor)
      local noiseFloor = 0.006 - contrastAmt * 0.002
      if contrastAmp < noiseFloor then contrastAmp = 0.0 end

      result.frequencies[i] = freq
      result.amplitudes[i] = contrastAmp
      result.phases[i] = ap + (bp - ap) * frac
      result.partials[i] = {
        frequency = freq,
        amplitude = contrastAmp,
        phase = ap + (bp - ap) * frac,
      }
    end

    -- Per-frame RMS scaling: louder parts of the sample should sound louder
    local rmsA = tonumber(frameA.rmsLevel) or 0.0
    local rmsB = tonumber(frameB.rmsLevel) or 0.0
    local rmsScale = 1.0 + (rmsA + (rmsB - rmsA) * frac) * 3.0
    if rmsScale > 0.5 and rmsScale < 4.0 then
      for i = 1, maxCount do
        if result.partials[i] then
          result.partials[i].amplitude = math.min(1.0, (result.partials[i].amplitude or 0) * rmsScale)
          result.amplitudes[i] = result.partials[i].amplitude
        end
      end
    end

    -- Strong temporal smoothing: smear across neighbouring frames, not just the local crossfade.
    if smoothAmt > 0.001 then
      local prevFrame = temporal.frames[math.max(1, lo - 1)]
      local nextFrame = temporal.frames[math.min(fc, hi + 1)]
      local prevAmps = prevFrame and prevFrame.amplitudes or nil
      local nextAmps = nextFrame and nextFrame.amplitudes or nil
      local prevFreqs = prevFrame and prevFrame.frequencies or nil
      local nextFreqs = nextFrame and nextFrame.frequencies or nil

      for i = 1, maxCount do
        local p = result.partials[i]
        if p then
          local baseAmp = tonumber(p.amplitude) or 0.0
          local baseFreq = tonumber(p.frequency) or 0.0

          local pa = prevAmps and (tonumber(prevAmps[i]) or 0.0) or 0.0
          local na = nextAmps and (tonumber(nextAmps[i]) or 0.0) or 0.0
          local pf = prevFreqs and (tonumber(prevFreqs[i]) or 0.0) or 0.0
          local nf = nextFreqs and (tonumber(nextFreqs[i]) or 0.0) or 0.0

          local avgAmp = (pa + baseAmp + na) / 3.0
          local avgFreq = baseFreq
          if baseFreq > 0.01 or pf > 0.01 or nf > 0.01 then
            local accum = 0.0
            local weight = 0.0
            if pf > 0.01 then accum = accum + math.log(pf) * 0.75; weight = weight + 0.75 end
            if baseFreq > 0.01 then accum = accum + math.log(baseFreq) * 1.5; weight = weight + 1.5 end
            if nf > 0.01 then accum = accum + math.log(nf) * 0.75; weight = weight + 0.75 end
            if weight > 0.0 then avgFreq = math.exp(accum / weight) end
          end

          -- Make Smooth obvious: at 1.0 it strongly favours the averaged temporal smear.
          local smearMix = 0.15 + smoothAmt * 0.85
          p.amplitude = baseAmp + (avgAmp - baseAmp) * smearMix
          p.frequency = avgFreq > 0.01 and (baseFreq + (avgFreq - baseFreq) * smearMix) or baseFreq
          result.amplitudes[i] = p.amplitude
          result.frequencies[i] = p.frequency
        end
      end
    end

    return result
  end

  local function applySampleWindowToVoice(voice)
    if not voice or not voice.samplePlayback then
      return
    end

    local capturedLength = tonumber(voice.sampleCapturedLength) or 0
    local fullLength = capturedLength > 0 and capturedLength or (voice.samplePlayback:getLoopLength() or 0)
    if fullLength <= 0 then
      return
    end

    local playStartAbs = clamp(samplePlayStart, 0.0, 0.95)
    local loopStartAbs = clamp(sampleLoopStart, 0.0, 0.95)
    local loopEndAbs = clamp(sampleLoopStart + sampleLoopLen, 0.05, 1.0)
    if loopEndAbs <= loopStartAbs then
      loopEndAbs = math.min(1.0, loopStartAbs + 0.01)
    end
    if playStartAbs > loopEndAbs then
      playStartAbs = loopStartAbs
    end

    voice.playStartNorm = playStartAbs
    voice.loopStartNorm = loopStartAbs
    voice.loopEndNorm = loopEndAbs
    voice.crossfadeNorm = clamp(sampleCrossfade, 0.0, 0.5)

    voice.samplePlayback:setLoopLength(fullLength)
    voice.samplePlayback:setPlayStart(playStartAbs)
    voice.samplePlayback:setLoopStart(loopStartAbs)
    voice.samplePlayback:setLoopEnd(loopEndAbs)
    voice.samplePlayback:setCrossfade(voice.crossfadeNorm)
  end

  local function analyzeCapturedSample()
    local voice = voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastAnalysis then
      latestSampleAnalysis = nil
      return nil
    end

    local ok, analysis = pcall(function()
      return playback:getLastAnalysis()
    end)
    if not ok or type(analysis) ~= "table" then
      ensureSampleAnalysis()
      return latestSampleAnalysis
    end

    local midiNote = tonumber(analysis.midiNote)
    if midiNote ~= nil then
      analysis.midiNote = clamp(math.floor(midiNote + 0.5), 12, 96)
    end

    latestSampleAnalysis = analysis
    return analysis
  end

  extractCapturedSamplePartials = function(forceExtract, preserveLastGood)
    local voice = voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastPartials then
      latestSamplePartials = nil
      applySampleDerivedPartialsToVoices(nil)
      return nil
    end

    local ok, partials = pcall(function()
      return playback:getLastPartials()
    end)
    if ok and type(partials) == "table" and hasUsableSampleAdditivePartials(partials) then
      latestSamplePartials = partials
      applySampleDerivedPartialsToVoices(partials)
      return partials
    end

    if forceExtract then
      ensureSampleAnalysis()
    end

    if preserveLastGood and hasUsableSampleAdditivePartials(latestSamplePartials) then
      applySampleDerivedPartialsToVoices(latestSamplePartials)
      return latestSamplePartials
    end

    if ok and type(partials) == "table" then
      latestSamplePartials = partials
      applySampleDerivedPartialsToVoices(partials)
      return partials
    end

    latestSamplePartials = nil
    applySampleDerivedPartialsToVoices(nil)
    return nil
  end

  local applyVoiceFrequency

  local function maybeApplyDetectedSampleRoot(analysis)
    if type(analysis) ~= "table" then
      print("PitchMap: no analysis result to apply")
      return false
    end
    if not samplePitchMapEnabled then
      print("PitchMap: toggle off, leaving root at " .. tostring(sampleRootNote))
      return false
    end
    if analysis.reliable ~= true then
      print("PitchMap: analysis not reliable, not applying")
      return false
    end

    local midiNote = tonumber(analysis.midiNote)
    if midiNote == nil then
      print("PitchMap: analysis missing midiNote")
      return false
    end

    local applied = clamp(math.floor(midiNote + 0.5), 12, 96)
    print("PitchMap: applying root " .. tostring(applied))

    local wrote = false
    if ctx and ctx.host and ctx.host.setParam then
      wrote = ctx.host.setParam(PATHS.sampleRootNote, applied) == true
    end

    if wrote then
      sampleRootNote = applied
      for i = 1, VOICE_COUNT do
        applyVoiceFrequency(i, voices[i].freq or 220.0)
      end
    else
      print("PitchMap: host param write failed")
    end

    return wrote
  end

  -- Queue async sample analysis if needed. Never do heavy FFT / partial extraction inline.
  ensureSampleAnalysis = function()
    if sampleAnalysisPending == false or sampleAnalysisInFlight == true then
      return
    end

    local voice = voices[1]
    local playback = voice and voice.samplePlayback or nil
    local playbackNode = playback and playback.__node or nil
    if not playbackNode or type(requestSampleRegionPlaybackAsyncAnalysis) ~= "function" then
      return
    end
    local loopLen = (playback and playback.getLoopLength and playback:getLoopLength()) or 0
    if loopLen <= 0 then
      return
    end

    local partialCount = math.min(24, math.max(12, additivePartials or 16))
    local ok, err = pcall(function()
      requestSampleRegionPlaybackAsyncAnalysis(playbackNode, partialCount, 1024, 256, 256)
    end)
    if ok then
      sampleAnalysisPending = false
      sampleAnalysisInFlight = true
      print(string.format("AsyncAnalysis: queued loopLen=%d partialCount=%d", loopLen, partialCount))
    else
      print("ensureSampleAnalysis failed to queue async analysis: " .. tostring(err))
    end
  end

  pollAsyncSampleAnalysis = function()
    if sampleAnalysisInFlight ~= true then
      return false
    end

    local voice = voices[1]
    local playback = voice and voice.samplePlayback or nil
    local playbackNode = playback and playback.__node or nil
    if not playbackNode or type(isSampleRegionPlaybackAnalysisPending) ~= "function" then
      sampleAnalysisInFlight = false
      return false
    end

    local okPending, pending = pcall(function()
      return isSampleRegionPlaybackAnalysisPending(playbackNode)
    end)
    if not okPending then
      sampleAnalysisInFlight = false
      return false
    end
    if pending == true then
      return false
    end

    sampleAnalysisInFlight = false
    print("AsyncAnalysis: worker finished, harvesting results")

    local okAnalysis, analysis = pcall(function() return getSampleRegionPlaybackLastAnalysis(playbackNode) end)
    local okPartials, partials = pcall(function() return getSampleRegionPlaybackPartials(playbackNode) end)
    local okTemporal, temporal = pcall(function() return getSampleRegionPlaybackTemporalPartials(playbackNode) end)

    if okAnalysis and type(analysis) == "table" then
      latestSampleAnalysis = analysis
      print(string.format("AsyncAnalysis: analysis freq=%.2f reliable=%s midi=%s", tonumber(analysis.frequency) or 0.0, tostring(analysis.reliable), tostring(analysis.midiNote)))
      maybeApplyDetectedSampleRoot(analysis)
    end
    if okPartials and type(partials) == "table" then
      latestSamplePartials = partials
      print(string.format("AsyncAnalysis: partials active=%s fundamental=%.2f", tostring(partials.activeCount), tonumber(partials.fundamental) or 0.0))
      applySampleDerivedPartialsToVoices(partials)
    end
    if okTemporal and type(temporal) == "table" then
      latestTemporalPartials = temporal
      print(string.format("AsyncAnalysis: temporal frames=%s fundamental=%.2f", tostring(temporal.frameCount), tonumber(temporal.globalFundamental) or 0.0))
    end

    local playbackNode = playback and playback.__node or nil
    if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
      local okPeaks, peaks = pcall(function()
        return getSampleRegionPlaybackPeaks(playbackNode, 512)
      end)
      if okPeaks and type(peaks) == "table" and #peaks > 0 then
        cachedSamplePeaks = peaks
        cachedSamplePeakBuckets = #peaks
      end
    end

    applyAllSampleDerivedAdditiveStates()
    return true
  end

  local function blendPitchRatio()
    return 2.0 ^ (clamp(tonumber(blendSamplePitch) or 0.0, -24.0, 24.0) / 12.0)
  end

  local function additiveModeDisablesVoiceStacking()
    return blendMode == 4 or blendMode == 5
  end

  local function getEffectiveVoiceStackingParams()
    if additiveModeDisablesVoiceStacking() then
      return 1, 0.0, 0.0
    end
    return unisonVoices, detuneCents, stereoSpread
  end

  local function applyVoiceStackingParams(voice)
    if not voice then
      return
    end
    local uni, det, spr = getEffectiveVoiceStackingParams()
    if voice.osc then
      voice.osc:setUnison(uni)
      voice.osc:setDetune(det)
      voice.osc:setSpread(spr)
    end
    if voice.samplePlayback then
      voice.samplePlayback:setUnison(uni)
      voice.samplePlayback:setDetune(det)
      voice.samplePlayback:setSpread(spr)
    end
    if voice.sampleAdditive then
      voice.sampleAdditive:setUnison(uni)
      voice.sampleAdditive:setDetune(det)
      voice.sampleAdditive:setSpread(spr)
    end
    if voice.morphWaveAdditive then
      voice.morphWaveAdditive:setUnison(uni)
      voice.morphWaveAdditive:setDetune(det)
      voice.morphWaveAdditive:setSpread(spr)
    end
    if voice.blendAddOsc then
      voice.blendAddOsc:setUnison(uni)
      voice.blendAddOsc:setDetune(det)
      voice.blendAddOsc:setSpread(spr)
    end
  end

  local function applyAllVoiceStackingParams()
    for i = 1, VOICE_COUNT do
      applyVoiceStackingParams(voices[i])
    end
  end

  local function getBlendSampleBaseSpeed(voice)
    if not voice then
      return 1.0
    end
    local keyRatio = 1.0
    -- blendKeyTrack: 0=wave (no keytrack), 1=sample (keytrack), 2=both (keytrack)
    if blendKeyTrack >= 1 then
      local rootFreq = noteToFrequency(sampleRootNote)
      if rootFreq > 0.0 then
        keyRatio = clamp((voice.freq or 220.0) / rootFreq, 0.05, 8.0)
      end
    end
    return clamp(keyRatio * blendPitchRatio(), 0.05, 8.0)
  end

  local function getSampleDerivedAdditiveTargetFrequency(voice)
    local rootFreq = noteToFrequency(sampleRootNote)
    if rootFreq <= 0.0 then
      rootFreq = 220.0
    end
    return clamp(rootFreq * getBlendSampleBaseSpeed(voice), 20.0, 8000.0)
  end

  local function applySampleDerivedAdditiveToVoice(voice, amp)
    if not voice or not voice.sampleAdditive or not voice.sampleAdditiveGain or not voice.blendAddOsc or not voice.morphWaveAdditive or not voice.morphWaveAdditiveGain then
      return
    end

    local addActive = blendMode == 4
    local morphActive = blendMode == 5

    -- blendAddOsc: wave-centric additive endpoint (Bus A, blend=0)
    -- Always set frequency/waveform to match the main osc; only enable+amplify in Add mode.
    if addActive and amp > 0.0005 then
      voice.blendAddOsc:setEnabled(true)
      voice.blendAddOsc:setAmplitude(amp * 2.0)
      voice.blendAddOsc:setWaveform(voice.waveform or 1)
      voice.blendAddOsc:setPulseWidth(voice.pulseWidth or 0.5)
    else
      voice.blendAddOsc:setEnabled(false)
      voice.blendAddOsc:setAmplitude(0.0)
    end

    -- Morph mode always disables the second bank (morphWaveAdditive)
    -- and the wave-additive osc (blendAddOsc) — we use ONE bank only.
    voice.morphWaveAdditive:setEnabled(false)
    voice.morphWaveAdditive:setAmplitude(0.0)
    voice.morphWaveAdditiveGain:setGain(0.0)

    if morphActive and amp <= 0.0005 then
      voice.sampleAdditive:setEnabled(false)
      voice.sampleAdditive:setAmplitude(0.0)
      voice.sampleAdditiveGain:setGain(0.0)
      voice.lastSampleAdditiveFreq = 0.0
      voice.lastSampleAdditiveMix = 0.0
      return
    end

    -- Morph mode: single bank, single morph position.
    -- blendAmount = morph position (0=wave, 1=sample)
    -- blendModAmount = depth (0=amplitude-only morph, 1=full freq+amp morph)
    -- morphCurve = crossfade curve shape
    if morphActive and amp > 0.0005 then
      -- Ensure analysis has run if capture just happened
      ensureSampleAnalysis()
      
      -- Try temporal partials first; fall back to static
      local hasTemporal = latestTemporalPartials and (tonumber(latestTemporalPartials.frameCount) or 0) > 0
      local hasSamplePartials = latestSamplePartials and (latestSamplePartials.activeCount or 0) > 0

      -- Lazy extraction: if we have neither temporal nor static, try to get them
      if not hasTemporal and not hasSamplePartials then
        refreshSampleDerivedPartialsFromPlayback("lazy-morph-refresh")
        hasSamplePartials = latestSamplePartials and (latestSamplePartials.activeCount or 0) > 0
        -- Also try temporal extraction if static succeeded
        if hasSamplePartials and not temporalExtractPending then
          temporalExtractPending = true
          extractTemporalPartials("lazy-morph-temporal")
          hasTemporal = latestTemporalPartials and (tonumber(latestTemporalPartials.frameCount) or 0) > 0
          temporalExtractPending = false
        end
      end

      -- Generate wave partials from current osc settings
      local voiceFundamental = voice.freq or 220.0
      local voiceWaveform = voice.waveform or 1
      local voicePulseWidth = voice.pulseWidth or 0.5
      local partialCount = additivePartials or 8
      local tilt = additiveTilt or 0.0
      local drift = additiveDrift or 0.0
      local waveKey = string.format("%d_%.1f_%d_%.2f_%.4f_%.3f",
        voiceWaveform, voiceFundamental, partialCount, tilt, drift, voicePulseWidth)

      local wavePartials = cachedMorphWavePartials
      if waveKey ~= cachedMorphWaveKey or not wavePartials then
        if type(buildWavePartials) == "function" then
          wavePartials = buildWavePartials(voiceWaveform, voiceFundamental, partialCount, tilt, drift, voicePulseWidth)
          cachedMorphWavePartials = wavePartials
          cachedMorphWaveKey = waveKey
        end
      end

      -- Determine sample partials for this voice:
      -- If temporal data is available, follow the ACTUAL sample playback position.
      local currentSamplePartials
      if hasTemporal then
        local samplePos = (voice.samplePlayback and voice.samplePlayback:getNormalizedPosition()) or (voice.lastSamplePos or 0.0)
        local tPos = mapTemporalPositionForVoice(voice, samplePos)
        currentSamplePartials = getTemporalFrameAtPosition(latestTemporalPartials, tPos)
      else
        currentSamplePartials = latestSamplePartials
      end

      -- morphPartials: A=wave, B=sample, position=blendAmount, depth=blendModAmount
      local morphPos = clamp01(blendAmount)
      local morphDepth = clamp01(blendModAmount)
      local morphed = morphPartials(wavePartials, currentSamplePartials, morphPos, morphCurve, morphDepth)

      -- Target frequency: respect sample key mapping when morph is sample-weighted,
      -- use voice frequency when wave-weighted, interpolate between.
      local waveFreq = clamp(voiceFundamental, 20.0, 8000.0)
      local sampleFreq = (hasSamplePartials or hasTemporal) and getSampleDerivedAdditiveTargetFrequency(voice) or waveFreq
      local targetFreq = waveFreq + (sampleFreq - waveFreq) * morphPos

      -- Apply morph shaping: harmonic stretch + spectral tilt
      if morphed and (morphed.activeCount or 0) > 0 then
        -- Harmonic stretch: controlled by morphConvergence param (repurposed: 0=normal, 1=stretched)
        local stretch = clamp01(morphConvergence or 0.0)
        -- Spectral tilt post-morph: controlled by morphPhase param (repurposed: 0=neutral, 1=bright, 2=dark)
        local tiltMode = math.floor((morphPhaseParam or 0) + 0.5)

        if stretch > 0.001 or tiltMode > 0 then
          for i = 1, morphed.activeCount do
            local p = morphed.partials[i]
            if p then
              local freq = tonumber(p.frequency) or 0.0
              local amp = tonumber(p.amplitude) or 0.0
              local partialIdx = i - 1

              -- Harmonic stretch: make it fucking obvious.
              -- At max this pushes upper partials way out toward metallic / bell territory.
              if freq > 0.01 and stretch > 0.001 then
                local stretchPow = 1.0 + stretch * 0.65
                local spreadBias = 1.0 + partialIdx * stretch * 0.035
                p.frequency = math.pow(freq, stretchPow) * spreadBias
              end

              -- Spectral tilt: also make this plainly audible.
              if amp > 0.0 and partialIdx > 0 then
                if tiltMode == 1 then
                  -- Bright: aggressively lift highs
                  p.amplitude = amp * math.pow(1.22, partialIdx)
                elseif tiltMode == 2 then
                  -- Dark: aggressively suppress highs
                  p.amplitude = amp * math.pow(0.78, partialIdx)
                end
              end
            end
          end
        end

        voice.sampleAdditive:setEnabled(true)
        voice.sampleAdditive:setAmplitude(amp * 2.0)
        voice.sampleAdditive:setFrequency(targetFreq)
        voice.sampleAdditiveGain:setGain(1.0)
        voice.lastSampleAdditiveFreq = targetFreq
        voice.sampleAdditive:setPartials(morphed)
      else
        -- Fallback: if morph produces nothing, just play wave partials raw
        if wavePartials and (wavePartials.activeCount or 0) > 0 then
          voice.sampleAdditive:setEnabled(true)
          voice.sampleAdditive:setAmplitude(amp * 2.0)
          voice.sampleAdditive:setFrequency(waveFreq)
          voice.sampleAdditiveGain:setGain(1.0)
          voice.lastSampleAdditiveFreq = waveFreq
          voice.sampleAdditive:setPartials(wavePartials)
        else
          voice.sampleAdditive:setEnabled(false)
          voice.sampleAdditive:setAmplitude(0.0)
          voice.sampleAdditiveGain:setGain(0.0)
          voice.lastSampleAdditiveFreq = 0.0
        end
      end
      voice.lastSampleAdditiveMix = 1.0
      return
    end

    -- sampleAdditive for Add mode: sample-derived additive endpoint (Bus B, blend=1)
    -- Uses partials extracted from captured sample, with temporal evolution if available.
    -- Lazy re-extraction: if we need partials but don't have them, try once.
    if addActive and amp <= 0.0005 then
      voice.sampleAdditive:setEnabled(false)
      voice.sampleAdditive:setAmplitude(0.0)
      voice.sampleAdditiveGain:setGain(0.0)
      voice.lastSampleAdditiveFreq = 0.0
      voice.lastSampleAdditiveMix = 0.0
      return
    end
    
    -- Ensure analysis has run if capture just happened
    ensureSampleAnalysis()
    
    local hasTemporal = latestTemporalPartials and (tonumber(latestTemporalPartials.frameCount) or 0) > 0
    local hasPartials = latestSamplePartials and (latestSamplePartials.activeCount or 0) > 0
    
    -- Lazy extraction
    if not hasTemporal and not hasPartials then
      refreshSampleDerivedPartialsFromPlayback("lazy-add-refresh")
      hasPartials = latestSamplePartials and (latestSamplePartials.activeCount or 0) > 0
      if hasPartials and not temporalExtractPending then
        temporalExtractPending = true
        extractTemporalPartials("lazy-add-temporal")
        hasTemporal = latestTemporalPartials and (tonumber(latestTemporalPartials.frameCount) or 0) > 0
        temporalExtractPending = false
      end
    end
    
    if addActive and amp > 0.0005 and (hasTemporal or hasPartials) then
      local targetFreq = getSampleDerivedAdditiveTargetFrequency(voice)
      local currentPartials
      
      -- Use temporal partials if available, with Speed/Contrast/Smooth applied
      if hasTemporal then
        local samplePos = (voice.samplePlayback and voice.samplePlayback:getNormalizedPosition()) or (voice.lastSamplePos or 0.0)
        local tPos = mapTemporalPositionForVoice(voice, samplePos)
        currentPartials = getTemporalFrameAtPosition(latestTemporalPartials, tPos)
        
        -- Apply spectral shaping (Tilt/Stretch) to the temporal frame
        if currentPartials and (currentPartials.activeCount or 0) > 0 then
          local stretch = clamp01(morphConvergence or 0.0)
          local tiltMode = math.floor((morphPhaseParam or 0) + 0.5)
          if stretch > 0.001 or tiltMode > 0 then
            for i = 1, currentPartials.activeCount do
              local p = currentPartials.partials[i]
              if p then
                local freq = tonumber(p.frequency) or 0.0
                local amp = tonumber(p.amplitude) or 0.0
                local partialIdx = i - 1
                if freq > 0.01 and stretch > 0.001 then
                  local stretchPow = 1.0 + stretch * 0.65
                  local spreadBias = 1.0 + partialIdx * stretch * 0.035
                  p.frequency = math.pow(freq, stretchPow) * spreadBias
                end
                if amp > 0.0 and partialIdx > 0 then
                  if tiltMode == 1 then
                    p.amplitude = amp * math.pow(1.22, partialIdx)
                  elseif tiltMode == 2 then
                    p.amplitude = amp * math.pow(0.78, partialIdx)
                  end
                end
              end
            end
          end
        end
      else
        currentPartials = latestSamplePartials
      end
      
      -- Apply flavor transformation if Driven mode
      if addFlavor == ADD_FLAVOR_DRIVEN and currentPartials then
        currentPartials = buildDrivenSampleAdditivePartials(currentPartials, voice)
      end
      
      if currentPartials and (currentPartials.activeCount or 0) > 0 then
        voice.sampleAdditive:setEnabled(true)
        voice.sampleAdditive:setAmplitude(amp * 2.0)
        voice.sampleAdditive:setFrequency(targetFreq)
        voice.sampleAdditiveGain:setGain(1.0)
        voice.sampleAdditive:setPartials(currentPartials)
        voice.lastSampleAdditiveFreq = targetFreq
      else
        voice.sampleAdditive:setEnabled(false)
        voice.sampleAdditive:setAmplitude(0.0)
        voice.sampleAdditiveGain:setGain(0.0)
        voice.lastSampleAdditiveFreq = 0.0
      end
    else
      voice.sampleAdditive:setEnabled(false)
      voice.sampleAdditive:setAmplitude(0.0)
      voice.sampleAdditiveGain:setGain(0.0)
      voice.lastSampleAdditiveFreq = 0.0
    end

    voice.lastSampleAdditiveMix = addActive and 1.0 or 0.0
  end

  local function applyAllSampleDerivedAdditiveStates()
    for i = 1, VOICE_COUNT do
      local voice = voices[i]
      applySampleDerivedAdditiveToVoice(voice, (voice and (voice.amp or voiceLastAmp[i])) or 0.0)
    end
  end

  local function applyBlendParamsToVoice(voice)
    if not voice then
      return
    end

    -- Blend chooses source/output balance; hidden directional params still feed
    -- the per-mode internals and are now derived from Blend at the UI layer.
    local blendPos = clamp01(blendAmount) * 2.0 - 1.0
    local depth = clamp01(blendModAmount)

    if voice.mixCrossfade then
      voice.mixCrossfade:setPosition(blendPos)
      voice.mixCrossfade:setMix(1.0)
      voice.mixCrossfade:setCurve(1.0)
    end

    if voice.directionCrossfade then
      -- A = wave target (blend 0), B = sample target (blend 1)
      voice.directionCrossfade:setPosition(blendPos)
      voice.directionCrossfade:setMix(1.0)
      voice.directionCrossfade:setCurve(1.0)
    end

    if voice.basePathSelect then
      -- Mix uses source-crossfade branch, FM/Sync use directional-output branch.
      local useDirectional = (blendMode == 2 or blendMode == 3)
      voice.basePathSelect:setPosition(useDirectional and 1.0 or -1.0)
      voice.basePathSelect:setMix(1.0)
      voice.basePathSelect:setCurve(1.0)
    end

    if voice.addCrossfade then
      if blendMode == 5 then
        -- Morph: single bank on bus B, force crossfade fully there
        voice.addCrossfade:setPosition(1.0)
      else
        voice.addCrossfade:setPosition(blendPos)
      end
      voice.addCrossfade:setMix(1.0)
      voice.addCrossfade:setCurve(1.0)
    end

    if voice.addBranchGain then
      -- Add family depth is handled at the branch mixer so the additive path
      -- can fade against the canonical branch instead of just changing loudness.
      voice.addBranchGain:setGain((blendMode == 4 or blendMode == 5) and 1.0 or 0.0)
    end

    if voice.branchMixer then
      -- bus1=base(Mix/FM/Sync), bus2=Ring, bus3=Add/Morph
      if blendMode == 5 then
        -- Morph: full signal through additive path, position controls morph blend
        voice.branchMixer:setGain(1, 0.0)
        voice.branchMixer:setGain(2, 0.0)
        voice.branchMixer:setGain(3, 1.0)
      elseif blendMode == 4 then
        -- Add: depth controls wet/dry mix between canonical and additive
        voice.branchMixer:setGain(1, 1.0 - depth)
        voice.branchMixer:setGain(2, 0.0)
        voice.branchMixer:setGain(3, depth)
      else
        voice.branchMixer:setGain(1, (blendMode == 0 or blendMode == 2 or blendMode == 3) and 1.0 or 0.0)
        voice.branchMixer:setGain(2, (blendMode == 1) and 1.0 or 0.0)
        voice.branchMixer:setGain(3, 0.0)
      end
    end

    -- Hard-sync: enable sample-rate sync on osc only on the sample->wave side.
    if voice.osc then
      voice.osc:setSyncEnabled(blendMode == 3 and blendPos < 0.0)
    end

    if voice.ringWaveToSample and voice.ringSampleToWave and voice.ringCrossfade then
      local ringActive = (blendMode == 1)
      local oscFreq = voice.freq or 220.0
      local sampleSpeed = getBlendSampleBaseSpeed(voice)
      local rootFreq = noteToFrequency(sampleRootNote)
      local sampleFreq = (rootFreq > 0.0) and (rootFreq * sampleSpeed) or (220.0 * sampleSpeed)

      if voice.ringWaveToSample.setEnabled then
        voice.ringWaveToSample:setEnabled(ringActive)
      end
      if voice.ringSampleToWave.setEnabled then
        voice.ringSampleToWave:setEnabled(ringActive)
      end

      -- A: sample target, wave as external modulator
      voice.ringWaveToSample:setFrequency(clamp(sampleFreq, 20.0, 8000.0))
      voice.ringWaveToSample:setDepth(ringActive and depth or 0.0)
      voice.ringWaveToSample:setSpread(lerp(0.0, 180.0, sampleToWave))
      voice.ringWaveToSample:setMix(ringActive and 1.0 or 0.0)

      -- B: wave target, sample as external modulator
      voice.ringSampleToWave:setFrequency(clamp(oscFreq, 20.0, 8000.0))
      voice.ringSampleToWave:setDepth(ringActive and depth or 0.0)
      voice.ringSampleToWave:setSpread(lerp(0.0, 180.0, waveToSample))
      voice.ringSampleToWave:setMix(ringActive and 1.0 or 0.0)

      voice.ringCrossfade:setPosition(blendPos)
      voice.ringCrossfade:setMix(ringActive and 1.0 or 0.0)
      voice.ringCrossfade:setCurve(1.0)
    end


  end

  local function applyAllBlendParams()
    for i = 1, VOICE_COUNT do
      applyBlendParamsToVoice(voices[i])
    end
  end

  local function applyVoiceModeForAmp(voice, amp)
    if not voice then
      return
    end

    -- Canonical Blend branch for all tabs/modes.
    if voice.voiceMix then
      voice.voiceMix:setGain(1, 0.0) -- osc direct off
      voice.voiceMix:setGain(2, 0.0) -- noise direct off
      voice.voiceMix:setGain(3, 0.0) -- sample direct off
      voice.voiceMix:setGain(4, 1.0) -- canonical path on
    end
    voice.osc:setEnabled(true)
    voice.osc:setAmplitude(amp)
    voice.noiseGain:setGain(0.0)
    voice.sampleGain:setGain(0.0)
    if voice.sampleBlendGain then voice.sampleBlendGain:setGain(amp * 2.0) end
    applySampleDerivedAdditiveToVoice(voice, amp)
    applyBlendParamsToVoice(voice)
    if amp <= 0.0005 and voice.gate <= 0.5 then
      voice.samplePlayback:stop()
    end
  end

  local function applyAllVoiceModes()
    for i = 1, VOICE_COUNT do
      local amp = voiceLastAmp[i] or 0.0
      applyVoiceModeForAmp(voices[i], amp)
    end
  end

  applyVoiceFrequency = function(voiceIndex, frequency)
    local voice = voices[voiceIndex]
    if not voice then
      return
    end

    local f = clamp(tonumber(frequency) or 220.0, 20.0, 8000.0)
    voice.freq = f
    
    -- blendKeyTrack: 0=wave (wave keytracks, sample doesn't), 1=sample (sample keytracks, wave doesn't), 2=both keytrack
    local waveFreq = f
    if blendKeyTrack ~= 1 then
      -- Wave keytracks in modes 0 and 2
      waveFreq = f
    else
      -- Mode 1: Wave stays at root note frequency (no keytracking)
      local rootFreq = noteToFrequency(sampleRootNote)
      if rootFreq > 0 then
        waveFreq = rootFreq
      else
        waveFreq = 220.0
      end
    end

    voice.osc:setFrequency(waveFreq)
    if voice.blendAddOsc then
      voice.blendAddOsc:setFrequency(waveFreq)
    end

    -- Always set sample speed (blend is always active)
    voice.samplePlayback:setSpeed(getBlendSampleBaseSpeed(voice))
    applySampleDerivedAdditiveToVoice(voice, voice.amp or voiceLastAmp[voiceIndex] or 0.0)
    applyBlendParamsToVoice(voice)
  end

  local function applyVoiceGate(voiceIndex, gateValue)
    local voice = voices[voiceIndex]
    if not voice then
      return
    end

    local g = (tonumber(gateValue) or 0.0) > 0.5 and 1.0 or 0.0
    voice.gate = g
    if g <= 0.5 then
      voice.syncPhase = 0.0
    end

    -- Trigger ADSR envelope
    if voice.adsr then
      voice.adsr:setGate(g > 0.5)
    end

    -- Always start sample playback (blend is always active)
    if g > 0.5 then
      if sampleRetrigger or not voice.samplePlayback:isPlaying() then
        voice.samplePlayback:trigger()
      else
        voice.samplePlayback:play()
      end
      if voice.sampleAdditive then
        voice.sampleAdditive:reset()
      end
      -- Reset temporal morph cursor on note-on
      voice.morphTemporalPos = 0.0
      voice.lastTemporalSamplePos = nil
      -- Ensure gains and blend params are set for this voice
      applyVoiceModeForAmp(voice, voice.amp or voiceLastAmp[voiceIndex] or 0.5)
      applyBlendParamsToVoice(voice)
    end
    -- Note: Don't stop immediately on gate off - let ADSR release fade it out
    -- Sample will be stopped by applyVoiceModeForAmp when amp <= 0.0005
  end

  local function captureSampleFromCurrentSource()
    local sourceEntry = selectedSampleSourceEntry()
    local captureNode = sourceEntry and sourceEntry.capture and sourceEntry.capture.__node or nil
    if not captureNode then
      print("CaptureSample: no capture node")
      return false
    end

    local samplesBack = math.max(1, math.floor(sampleCaptureBars * hostSamplesPerBar() + 0.5))
    local copiedAny = false
    print(string.format("CaptureSample: source=%s samplesBack=%d", tostring(sourceEntry and sourceEntry.name), samplesBack))

    for i = 1, VOICE_COUNT do
      local voice = voices[i]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node
      if playbackNode then
        local ok, copied = pcall(function()
          return captureNode:copyRecentToLoop(playbackNode, samplesBack, false)
        end)
        print(string.format("CaptureSample: voice=%d ok=%s copied=%s", i, tostring(ok), tostring(copied)))
        if ok and copied then
          copiedAny = true
          voice.sampleCapturedLength = voice.samplePlayback:getLoopLength() or 0
          print(string.format("CaptureSample: voice=%d loopLen=%d", i, tonumber(voice.sampleCapturedLength) or 0))
          -- C++ side already swapped buffer and reset positions to 0.
          -- Don't stop - let playback continue from start of new sample.
          -- If voice was playing, it will seamlessly pick up the new buffer.
          applySampleWindowToVoice(voice)
          applyVoiceFrequency(i, voice.freq or 220.0)
        end
      else
        print(string.format("CaptureSample: voice=%d no playback node", i))
      end
    end

    if copiedAny and type(getSampleRegionPlaybackPeaks) == "function" then
      local voice = voices[1]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
      local ok, peaks = pcall(function()
        return getSampleRegionPlaybackPeaks(playbackNode, 512)
      end)
      if ok and type(peaks) == "table" and #peaks > 0 then
        cachedSamplePeaks = peaks
        cachedSamplePeakBuckets = #cachedSamplePeaks
      end
    end

    print("CaptureSample: copiedAny=" .. tostring(copiedAny))
    if copiedAny then
      -- Keep current published analysis/partials alive until the async replacement finishes.
      -- That avoids the dead-zone where Morph/Add lose both audio and visuals.
      sampleAnalysisPending = true
      sampleAnalysisInFlight = false
      ensureSampleAnalysis()
      applyAllSampleDerivedAdditiveStates()
    end

    return copiedAny
  end

  local function applyWaveform(value)
    local wf = roundIndex(value, 7)
    for i = 1, VOICE_COUNT do
      voices[i].waveform = wf
      voices[i].osc:setWaveform(wf)
      voices[i].blendAddOsc:setWaveform(wf)
    end
  end

  local function applyFilterType(value)
    filt:setMode(roundIndex(value, 3))
  end

  applyWaveform(1)
  -- Initialize canonical blend path for all voices up front so Wave/Sample
  -- tabs behave like Blend DSP immediately, without requiring a tab switch.
  for i = 1, VOICE_COUNT do
    voices[i].osc:setDrive(0.0)
    voices[i].osc:setDriveShape(0)
    voices[i].osc:setDriveBias(0.0)
    voices[i].osc:setDriveMix(1.0)
    voices[i].osc:setRenderMode(OSC_RENDER_STANDARD)
    voices[i].osc:setAdditivePartials(8)
    voices[i].osc:setAdditiveTilt(0.0)
    voices[i].osc:setAdditiveDrift(0.0)
    voices[i].osc:setPulseWidth(0.5)
    voices[i].osc:setUnison(1)
    voices[i].osc:setDetune(0)
    voices[i].osc:setSpread(0)
    voices[i].samplePlayback:setUnison(1)
    voices[i].samplePlayback:setDetune(0)
    voices[i].samplePlayback:setSpread(0)
    voices[i].sampleAdditive:setEnabled(false)
    voices[i].sampleAdditive:setAmplitude(0.0)
    voices[i].sampleAdditive:setUnison(1)
    voices[i].sampleAdditive:setDetune(0)
    voices[i].sampleAdditive:setSpread(0)
    voices[i].sampleAdditive:setDrive(0.0)
    voices[i].sampleAdditive:setDriveShape(0)
    voices[i].sampleAdditive:setDriveBias(0.0)
    voices[i].sampleAdditive:setDriveMix(1.0)
    voices[i].sampleAdditive:clearPartials()
    voices[i].sampleAdditiveGain:setGain(0.0)
    voices[i].morphWaveAdditive:setEnabled(false)
    voices[i].morphWaveAdditive:setAmplitude(0.0)
    voices[i].morphWaveAdditive:setUnison(1)
    voices[i].morphWaveAdditive:setDetune(0)
    voices[i].morphWaveAdditive:setSpread(0)
    voices[i].morphWaveAdditive:setDrive(0.0)
    voices[i].morphWaveAdditive:setDriveShape(0)
    voices[i].morphWaveAdditive:setDriveBias(0.0)
    voices[i].morphWaveAdditive:setDriveMix(1.0)
    voices[i].morphWaveAdditive:clearPartials()
    voices[i].morphWaveAdditiveGain:setGain(0.0)
    voices[i].blendAddOsc:setWaveform(1)
    voices[i].blendAddOsc:setEnabled(false)
    voices[i].blendAddOsc:setAmplitude(0.0)
    voices[i].addBranchGain:setGain(0.0)
    voices[i].blendAddOsc:setDrive(0.0)
    voices[i].blendAddOsc:setDriveShape(0)
    voices[i].blendAddOsc:setDriveBias(0.0)
    voices[i].blendAddOsc:setDriveMix(1.0)
    voices[i].blendAddOsc:setRenderMode(OSC_RENDER_ADD)
    voices[i].blendAddOsc:setAdditivePartials(8)
    voices[i].blendAddOsc:setAdditiveTilt(0.0)
    voices[i].blendAddOsc:setAdditiveDrift(0.0)
    voices[i].blendAddOsc:setPulseWidth(0.5)
    voices[i].blendAddOsc:setUnison(1)
    voices[i].blendAddOsc:setDetune(0)
    voices[i].blendAddOsc:setSpread(0)
    if voices[i].ringWaveToSample and voices[i].ringWaveToSample.setEnabled then
      voices[i].ringWaveToSample:setEnabled(false)
      voices[i].ringWaveToSample:setMix(0.0)
      voices[i].ringWaveToSample:setDepth(0.0)
    end
    if voices[i].ringSampleToWave and voices[i].ringSampleToWave.setEnabled then
      voices[i].ringSampleToWave:setEnabled(false)
      voices[i].ringSampleToWave:setMix(0.0)
      voices[i].ringSampleToWave:setDepth(0.0)
    end
    if voices[i].ringCrossfade then
      voices[i].ringCrossfade:setMix(0.0)
    end
    -- Initialize ADSR with default values
    if voices[i].adsr then
      voices[i].adsr:setAttack(adsr.attack)
      voices[i].adsr:setDecay(adsr.decay)
      voices[i].adsr:setSustain(adsr.sustain)
      voices[i].adsr:setRelease(adsr.release)
    end
    applySampleWindowToVoice(voices[i])
    applyVoiceFrequency(i, voices[i].freq or 220.0)
    applyVoiceModeForAmp(voices[i], voiceLastAmp[i] or 0.0)
    applyBlendParamsToVoice(voices[i])
  end

  return {
    params = params,
    onParamChange = function(path, value)
      local voiceFreqIdx = voiceFreqPathToIndex[path]
      if voiceFreqIdx then
        applyVoiceFrequency(voiceFreqIdx, value)
        return
      end

      local voiceGateIdx = voiceGatePathToIndex[path]
      if voiceGateIdx then
        applyVoiceGate(voiceGateIdx, value)
        return
      end

      local voiceAmpIdx = voiceAmpPathToIndex[path]
      if voiceAmpIdx then
        local amp = clamp(tonumber(value) or 0, 0, 0.5)
        voiceLastAmp[voiceAmpIdx] = amp
        voices[voiceAmpIdx].amp = amp
        applyVoiceModeForAmp(voices[voiceAmpIdx], amp)
        return
      end

      if path == PATHS.noiseLevel then
        currentNoiseLevel = clamp01(tonumber(value) or 0.0)
        applyAllVoiceModes()
      elseif path == PATHS.oscRenderMode then
        renderMode = roundIndex(value, 1)
        for i = 1, VOICE_COUNT do
          voices[i].osc:setRenderMode(renderMode)
        end
      elseif path == PATHS.additivePartials then
        additivePartials = math.floor(clamp(tonumber(value) or 8, 1, 32) + 0.5)
        for i = 1, VOICE_COUNT do
          voices[i].additivePartials = additivePartials
          voices[i].osc:setAdditivePartials(additivePartials)
          voices[i].blendAddOsc:setAdditivePartials(additivePartials)
        end
        cachedMorphWaveKey = nil; cachedMorphWavePartials = nil
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.additiveTilt then
        additiveTilt = clamp(tonumber(value) or 0.0, -1.0, 1.0)
        for i = 1, VOICE_COUNT do
          voices[i].additiveTilt = additiveTilt
          voices[i].osc:setAdditiveTilt(additiveTilt)
          voices[i].blendAddOsc:setAdditiveTilt(additiveTilt)
        end
        cachedMorphWaveKey = nil; cachedMorphWavePartials = nil
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.additiveDrift then
        additiveDrift = clamp(tonumber(value) or 0.0, 0.0, 1.0)
        for i = 1, VOICE_COUNT do
          voices[i].additiveDrift = additiveDrift
          voices[i].osc:setAdditiveDrift(additiveDrift)
          voices[i].blendAddOsc:setAdditiveDrift(additiveDrift)
        end
        cachedMorphWaveKey = nil; cachedMorphWavePartials = nil
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.oscMode then
        -- UI tab only; DSP remains on canonical blend path.
        sampleMode = OSC_MODE_BLEND
        for i = 1, VOICE_COUNT do
          applySampleWindowToVoice(voices[i])
          applyVoiceFrequency(i, voices[i].freq or 220.0)
          if voices[i].gate > 0.5 then
            if sampleRetrigger then
              voices[i].samplePlayback:trigger()
            else
              voices[i].samplePlayback:play()
            end
          end
        end
        applyAllBlendParams()
        applyAllVoiceModes()
      elseif path == PATHS.sampleSource then
        sampleSource = roundIndex(value, SAMPLE_SOURCE_LAYER_MAX)
      elseif path == PATHS.sampleCaptureBars then
        sampleCaptureBars = clamp(tonumber(value) or 1.0, 0.0625, 16.0)
      elseif path == PATHS.samplePitchMapEnabled then
        samplePitchMapEnabled = (tonumber(value) or 0.0) > 0.5
        if samplePitchMapEnabled then
          maybeApplyDetectedSampleRoot(analyzeCapturedSample())
        end
      elseif path == PATHS.sampleRootNote then
        sampleRootNote = clamp(tonumber(value) or 60.0, 12.0, 96.0)
        for i = 1, VOICE_COUNT do
          applyVoiceFrequency(i, voices[i].freq or 220.0)
        end
      elseif path == PATHS.samplePlayStart then
        samplePlayStart = clamp01(tonumber(value) or 0.0)
        for i = 1, VOICE_COUNT do
          applySampleWindowToVoice(voices[i])
        end
      elseif path == PATHS.sampleLoopStart then
        sampleLoopStart = clamp01(tonumber(value) or 0.0)
        for i = 1, VOICE_COUNT do
          applySampleWindowToVoice(voices[i])
        end
      elseif path == PATHS.sampleLoopLen then
        sampleLoopLen = clamp(tonumber(value) or 1.0, 0.05, 1.0)
        for i = 1, VOICE_COUNT do
          applySampleWindowToVoice(voices[i])
        end
      elseif path == PATHS.sampleCrossfade then
        sampleCrossfade = clamp(tonumber(value) or 0.1, 0.0, 0.5)
        for i = 1, VOICE_COUNT do
          applySampleWindowToVoice(voices[i])
        end
      elseif path == PATHS.sampleRetrigger then
        sampleRetrigger = (tonumber(value) or 0.0) > 0.5
      elseif path == PATHS.sampleAdditiveEnabled then
        sampleAdditiveEnabled = (tonumber(value) or 0.0) > 0.5
        local ready = refreshSampleDerivedPartialsFromPlayback("param-sampleAdditiveEnabled")
        applyAllSampleDerivedAdditiveStates()
        print(string.format(
          "SampleAdditiveDebug: enabled=%s ready=%s count=%s fundamental=%.2f blendMode=%d blendAmount=%.3f",
          tostring(sampleAdditiveEnabled),
          tostring(ready),
          tostring(latestSamplePartials and latestSamplePartials.activeCount),
          tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
          blendMode,
          blendAmount
        ))
      elseif path == PATHS.sampleAdditiveMix then
        sampleAdditiveMix = clamp01(tonumber(value) or 0.25)
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.sampleCaptureTrigger then
        if (tonumber(value) or 0.0) > 0.5 then
          captureSampleFromCurrentSource()
        end
      elseif path == PATHS.blendMode then
        blendMode = roundIndex(value, 5)
        sampleAdditiveEnabled = (blendMode == 4 or blendMode == 5)
        -- Coerce voice stacking FIRST to prevent unison crash in additive modes
        applyAllVoiceStackingParams()
        if sampleAdditiveEnabled then
          refreshSampleDerivedPartialsFromPlayback("param-blendMode")
        end
        -- Keep temporal data alive for the whole additive family.
        -- Only clear it when leaving Add/Morph entirely.
        if blendMode == 4 or blendMode == 5 then
          -- Ensure we have temporal data; if not, it will be lazy-extracted when needed
        else
          latestTemporalPartials = nil
        end
        applyAllBlendParams()
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.blendAmount then
        blendAmount = clamp01(tonumber(value) or 0.5)
        applyAllBlendParams()
        if blendMode == 4 or blendMode == 5 then
          applyAllSampleDerivedAdditiveStates()
        end
      elseif path == PATHS.waveToSample then
        waveToSample = clamp01(tonumber(value) or 0.5)
      elseif path == PATHS.sampleToWave then
        sampleToWave = clamp01(tonumber(value) or 0.0)
      elseif path == PATHS.blendKeyTrack then
        blendKeyTrack = roundIndex(value, 2)  -- 0, 1, or 2
        for i = 1, VOICE_COUNT do
          applyVoiceFrequency(i, voices[i].freq or 220.0)
        end
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.blendSamplePitch then
        blendSamplePitch = clamp(tonumber(value) or 0.0, -24.0, 24.0)
        for i = 1, VOICE_COUNT do
          applyVoiceFrequency(i, voices[i].freq or 220.0)
        end
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.blendModAmount then
        blendModAmount = clamp01(tonumber(value) or 0.5)
        applyAllBlendParams()
        if blendMode == 4 or blendMode == 5 then
          applyAllSampleDerivedAdditiveStates()
        end
      elseif path == PATHS.addFlavor then
        addFlavor = roundIndex(value, 1)
        if hasUsableSampleAdditivePartials(latestSamplePartials) then
          applySampleDerivedPartialsToVoices(latestSamplePartials)
        end
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.xorBehavior then
        -- XOR removed; param kept for preset compat, no-op.
      elseif path == PATHS.morphCurve then
        morphCurve = roundIndex(value, 2)
        applyAllSampleDerivedAdditiveStates()
      elseif path == PATHS.morphConvergence then
        morphConvergence = clamp01(tonumber(value) or 0.0)
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.morphPhase then
        morphPhaseParam = roundIndex(value, 2)
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.morphSpeed then
        morphSpeed = clamp(tonumber(value) or 1.0, 0.1, 4.0)
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.morphContrast then
        morphContrast = clamp(tonumber(value) or 0.5, 0.0, 2.0)
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.morphSmooth then
        morphSmooth = clamp01(tonumber(value) or 0.0)
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
      elseif path == PATHS.waveform then
        applyWaveform(value)
        -- Invalidate morph cache so new waveform recipe is used
        cachedMorphWaveKey = nil
        cachedMorphWavePartials = nil
        if addFlavor == ADD_FLAVOR_DRIVEN and hasUsableSampleAdditivePartials(latestSamplePartials) then
          applySampleDerivedPartialsToVoices(latestSamplePartials)
        end
        if blendMode == 4 or blendMode == 5 then
          applyAllSampleDerivedAdditiveStates()
        end
      elseif path == PATHS.pulseWidth then
        local pw = clamp(tonumber(value) or 0.5, 0.01, 0.99)
        for i = 1, VOICE_COUNT do
          voices[i].pulseWidth = pw
          voices[i].osc:setPulseWidth(pw)
          voices[i].blendAddOsc:setPulseWidth(pw)
        end
        cachedMorphWaveKey = nil; cachedMorphWavePartials = nil
        if blendMode == 4 or blendMode == 5 then applyAllSampleDerivedAdditiveStates() end
        if addFlavor == ADD_FLAVOR_DRIVEN and hasUsableSampleAdditivePartials(latestSamplePartials) then
          applySampleDerivedPartialsToVoices(latestSamplePartials)
        end
      elseif path == PATHS.unison then
        unisonVoices = math.floor(clamp(tonumber(value) or 1, 1, 8) + 0.5)
        applyAllVoiceStackingParams()
      elseif path == PATHS.detune then
        detuneCents = clamp(tonumber(value) or 0, 0, 100)
        applyAllVoiceStackingParams()
      elseif path == PATHS.spread then
        stereoSpread = clamp(tonumber(value) or 0, 0, 1)
        applyAllVoiceStackingParams()
      elseif path == PATHS.driveShape then
        local shape = roundIndex(value, 3)
        for i = 1, VOICE_COUNT do
          voices[i].osc:setDriveShape(shape)
          -- Temporary safety guard: sample-derived additive gets no nonlinear drive path.
          voices[i].blendAddOsc:setDriveShape(shape)
        end
      elseif path == PATHS.driveBias then
        local bias = clamp(tonumber(value) or 0, -1, 1)
        for i = 1, VOICE_COUNT do
          voices[i].osc:setDriveBias(bias)
          -- Temporary safety guard: sample-derived additive gets no nonlinear drive path.
          voices[i].blendAddOsc:setDriveBias(bias)
        end
      elseif path == PATHS.drive then
        local drv = clamp(tonumber(value) or 0, 0, 20)
        for i = 1, VOICE_COUNT do
          voices[i].osc:setDrive(drv)
          -- Temporary safety guard: sample-derived additive gets no nonlinear drive path.
          voices[i].blendAddOsc:setDrive(drv)
        end
      elseif path == PATHS.filterType then
        applyFilterType(value)
      elseif path == PATHS.attack then
        local atk = math.max(0.001, tonumber(value) or 0.05)
        adsr.attack = atk
        for i = 1, VOICE_COUNT do
          if voices[i].adsr then voices[i].adsr:setAttack(atk) end
        end
      elseif path == PATHS.decay then
        local dec = math.max(0.001, tonumber(value) or 0.2)
        adsr.decay = dec
        for i = 1, VOICE_COUNT do
          if voices[i].adsr then voices[i].adsr:setDecay(dec) end
        end
      elseif path == PATHS.sustain then
        local sus = math.max(0.0, math.min(1.0, tonumber(value) or 0.7))
        adsr.sustain = sus
        for i = 1, VOICE_COUNT do
          if voices[i].adsr then voices[i].adsr:setSustain(sus) end
        end
      elseif path == PATHS.release then
        local rel = math.max(0.001, tonumber(value) or 0.4)
        adsr.release = rel
        for i = 1, VOICE_COUNT do
          if voices[i].adsr then voices[i].adsr:setRelease(rel) end
        end
      elseif path == PATHS.fx1Type then
        fx1Slot.applySelection(value)
      elseif path == PATHS.fx1Mix then
        fx1Slot.applyMix(value)
      elseif path == PATHS.fx2Type then
        fx2Slot.applySelection(value)
      elseif path == PATHS.fx2Mix then
        fx2Slot.applyMix(value)
      elseif path == PATHS.eqOutput or path == PATHS.eqMix or path:match("^/midi/synth/eq8/") then
        -- EQ8 params handled by binding
      else
        -- Individual FX params: /midi/synth/fx1/p/0 through /p/4
        local fx1pi = path:match("^/midi/synth/fx1/p/(%d+)$")
        local fx2pi = path:match("^/midi/synth/fx2/p/(%d+)$")
        if fx1pi then
          fx1Slot.applyParam(tonumber(fx1pi) + 1, value)
        elseif fx2pi then
          fx2Slot.applyParam(tonumber(fx2pi) + 1, value)
        end
      end
    end,

    process = function(blockSize, sampleRate)
      local sr = tonumber(sampleRate) or 44100.0
      local n = tonumber(blockSize) or 0
      if sr <= 1.0 or n <= 0 then
        return
      end

      -- Keep async sample analysis results flowing back into Lua/DSP state.
      pollAsyncSampleAnalysis()

      -- Throttle temporal morph updates: only run every other block to save CPU
      -- (at 128 samples/44.1kHz = ~2.9ms per block, every-other is still ~5.8ms = fast enough)
      morphProcessBlockCounter = (morphProcessBlockCounter or 0) + 1
      local shouldUpdateMorph = (morphProcessBlockCounter % 2 == 1)

      local depth = clamp01(blendModAmount)
      local blendPos = clamp01(blendAmount) * 2.0 - 1.0
      local modAmtWave = clamp01(sampleToWave) * depth * 0.35
      local modAmtSample = clamp01(waveToSample) * depth * 0.75

      for i = 1, VOICE_COUNT do
        local voice = voices[i]
        if voice and voice.gate > 0.5 then
          local baseFreq = clamp(voice.freq or 220.0, 20.0, 8000.0)
          local baseSpeed = getBlendSampleBaseSpeed(voice)
          local oscFreq = baseFreq
          local sampleSpeed = baseSpeed

          -- Maintain modulation sources; amount depends on blend position
          local phaseInc = (baseFreq / sr) * n
          voice.blendPhase = (voice.blendPhase or 0.0) + phaseInc
          voice.blendPhase = voice.blendPhase - math.floor(voice.blendPhase)
          local oscMod = math.sin(voice.blendPhase * 2.0 * math.pi)

          local samplePos = voice.samplePlayback:getNormalizedPosition() or 0.0
          local sampleMod = math.sin(samplePos * 2.0 * math.pi)

          if blendMode == 2 then
            -- FM: both modulations always active; crossfade picks which output
            sampleSpeed = clamp(baseSpeed * (1.0 + oscMod * modAmtSample), 0.05, 8.0)
            oscFreq = clamp(baseFreq * (1.0 + sampleMod * modAmtWave), 20.0, 8000.0)
          elseif blendMode == 3 then
            -- Sync mode:
            -- Direction A (blend 0): wave hard-synced by sample audio
            --   → handled at sample-rate by OscillatorNode sync input (C++)
            --
            -- Direction B (blend 1): sample retriggered by wave cycle (block-rate)
            voice.syncPhase = (voice.syncPhase or 0.0) + phaseInc
            if voice.syncPhase >= 1.0 then
              voice.syncPhase = voice.syncPhase - math.floor(voice.syncPhase)
              if sampleRetrigger then
                voice.samplePlayback:trigger()
              else
                voice.samplePlayback:play()
              end
            end
            voice.lastSamplePos = samplePos
          else
            voice.lastSamplePos = samplePos
          end

          voice.samplePlayback:setSpeed(sampleSpeed)

          -- Temporal additive family updates: follow the ACTUAL sample playback position (throttled)
          if shouldUpdateMorph and latestTemporalPartials and (tonumber(latestTemporalPartials.frameCount) or 0) > 1 and (blendMode == 4 or blendMode == 5) then
            local tPos = mapTemporalPositionForVoice(voice, samplePos or voice.lastSamplePos or 0.0)
            local currentSamplePartials = getTemporalFrameAtPosition(latestTemporalPartials, tPos)
            if currentSamplePartials and (tonumber(currentSamplePartials.activeCount) or 0) > 0 then
              local voiceFundamental = voice.freq or 220.0
              local stretch = clamp01(morphConvergence or 0.0)
              local tiltMode = math.floor((morphPhaseParam or 0) + 0.5)

              local function applyTemporalShaping(partials)
                if not partials or (partials.activeCount or 0) <= 0 then
                  return partials
                end
                if stretch <= 0.001 and tiltMode <= 0 then
                  return partials
                end
                local count = math.max(1, partials.activeCount or 0)
                for pi = 1, count do
                  local p = partials.partials[pi]
                  if p then
                    local freq = tonumber(p.frequency) or 0.0
                    local pamp = tonumber(p.amplitude) or 0.0
                    local partialIdx = pi - 1
                    local spectralPos = (count > 1) and (partialIdx / (count - 1)) or 0.0
                    if freq > 0.01 and stretch > 0.001 then
                      local stretchPow = 1.0 + stretch * 0.65
                      local spreadBias = 1.0 + partialIdx * stretch * 0.035
                      p.frequency = math.pow(freq, stretchPow) * spreadBias
                    end
                    if pamp > 0.0 then
                      if tiltMode == 1 then
                        -- Bright: gently trim the fundamental, strongly lift the top.
                        local tiltGain = 0.90 + spectralPos * 1.75
                        p.amplitude = pamp * tiltGain
                      elseif tiltMode == 2 then
                        -- Dark: slightly reinforce lows, heavily suppress the top.
                        local tiltGain = 1.12 - spectralPos * 0.78
                        p.amplitude = pamp * math.max(0.18, tiltGain)
                      end
                    end
                  end
                end
                return partials
              end

              if blendMode == 5 then
                local voiceWaveform = voice.waveform or 1
                local voicePulseWidth = voice.pulseWidth or 0.5
                local partialCount = additivePartials or 8
                local tiltVal = additiveTilt or 0.0
                local driftVal = additiveDrift or 0.0
                local waveKey = string.format("%d_%.1f_%d_%.2f_%.4f_%.3f",
                  voiceWaveform, voiceFundamental, partialCount, tiltVal, driftVal, voicePulseWidth)

                local wavePartials = cachedMorphWavePartials
                if waveKey ~= cachedMorphWaveKey or not wavePartials then
                  if type(buildWavePartials) == "function" then
                    wavePartials = buildWavePartials(voiceWaveform, voiceFundamental, partialCount, tiltVal, driftVal, voicePulseWidth)
                    cachedMorphWavePartials = wavePartials
                    cachedMorphWaveKey = waveKey
                  end
                end

                local morphPos = clamp01(blendAmount)
                local morphDepth = clamp01(blendModAmount)
                local morphed = morphPartials(wavePartials, currentSamplePartials, morphPos, morphCurve, morphDepth)
                morphed = applyTemporalShaping(morphed)

                if morphed and (morphed.activeCount or 0) > 0 then
                  local waveFreq = clamp(voiceFundamental, 20.0, 8000.0)
                  local sampleFreqTarget = getSampleDerivedAdditiveTargetFrequency(voice) or waveFreq
                  local targetFreq = waveFreq + (sampleFreqTarget - waveFreq) * morphPos

                  voice.sampleAdditive:setEnabled(true)
                  voice.sampleAdditive:setAmplitude((voice.amp or 0.0) * 2.0)
                  voice.sampleAdditive:setFrequency(targetFreq)
                  voice.sampleAdditiveGain:setGain(1.0)
                  voice.lastSampleAdditiveFreq = targetFreq
                  voice.sampleAdditive:setPartials(morphed)
                end
              elseif blendMode == 4 then
                local addPartials = applyTemporalShaping(currentSamplePartials)
                if addFlavor == ADD_FLAVOR_DRIVEN then
                  addPartials = buildDrivenSampleAdditivePartials(addPartials, voice)
                end
                if addPartials and (addPartials.activeCount or 0) > 0 then
                  local targetFreq = getSampleDerivedAdditiveTargetFrequency(voice)
                  voice.sampleAdditive:setEnabled(true)
                  voice.sampleAdditive:setAmplitude((voice.amp or 0.0) * 2.0)
                  voice.sampleAdditive:setFrequency(targetFreq)
                  voice.sampleAdditiveGain:setGain(1.0)
                  voice.lastSampleAdditiveFreq = targetFreq
                  voice.sampleAdditive:setPartials(addPartials)
                end
              end
            end
          end

          -- Apply keytrack logic: in mode 1 (sample only), osc stays at root freq
          local finalOscFreq = oscFreq
          if blendKeyTrack == 1 then
            local rootFreq = noteToFrequency(sampleRootNote)
            if rootFreq > 0 then
              finalOscFreq = rootFreq
            else
              finalOscFreq = 220.0
            end
          end
          voice.osc:setFrequency(finalOscFreq)
          voice.lastBlendSampleSpeed = sampleSpeed
          voice.lastBlendOscFreq = finalOscFreq
        elseif voice then
          voice.blendPhase = 0.0
          voice.syncPhase = 0.0
          voice.lastSamplePos = 0.0
        end
      end
    end,

    getSamplePeaks = function(numBuckets)
      numBuckets = numBuckets or 100
      pollAsyncSampleAnalysis()
      if type(cachedSamplePeaks) ~= "table" or #cachedSamplePeaks == 0 then
        local voice = voices[1]
        local playback = voice and voice.samplePlayback or nil
        local playbackNode = playback and playback.__node or nil
        if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
          local ok, peaks = pcall(function()
            return getSampleRegionPlaybackPeaks(playbackNode, math.max(32, numBuckets))
          end)
          if ok and type(peaks) == "table" and #peaks > 0 then
            cachedSamplePeaks = peaks
            cachedSamplePeakBuckets = #peaks
          end
        end
      end
      if type(cachedSamplePeaks) ~= "table" or #cachedSamplePeaks == 0 then
        return {}
      end
      return resamplePeaks(cachedSamplePeaks, numBuckets)
    end,

    getSampleLoopLength = function()
      local voice = voices[1]
      if voice and voice.samplePlayback then
        return voice.samplePlayback:getLoopLength()
      end
      return 0
    end,

    getLatestSampleAnalysis = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackLastAnalysis) == "function" then
        local ok, analyzed = pcall(function() return getSampleRegionPlaybackLastAnalysis(playbackNode) end)
        if ok and type(analyzed) == "table" and next(analyzed) ~= nil then
          latestSampleAnalysis = analyzed
          return analyzed
        end
      end

      if type(latestSampleAnalysis) == "table" then
        return latestSampleAnalysis
      end
      return {}
    end,

    getLatestSamplePartials = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackPartials) == "function" then
        local ok, extracted = pcall(function() return getSampleRegionPlaybackPartials(playbackNode) end)
        if ok and type(extracted) == "table" and ((tonumber(extracted.activeCount) or 0) > 0) then
          latestSamplePartials = extracted
          applySampleDerivedPartialsToVoices(extracted)
          return extracted
        end
      end

      if type(latestSamplePartials) == "table" then
        return latestSamplePartials
      end
      applySampleDerivedPartialsToVoices(nil)
      return {}
    end,

    getLatestTemporalPartials = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackTemporalPartials) == "function" then
        local ok, temporal = pcall(function() return getSampleRegionPlaybackTemporalPartials(playbackNode) end)
        if ok and type(temporal) == "table" and ((tonumber(temporal.frameCount) or 0) > 0) then
          latestTemporalPartials = temporal
          return temporal
        end
      end

      if type(latestTemporalPartials) == "table" then
        return latestTemporalPartials
      end
      return {}
    end,

    refreshSampleDerivedAdditive = function()
      local ready = refreshSampleDerivedPartialsFromPlayback()
      -- Also refresh temporal partials if in Morph mode
      if blendMode == 5 then
        extractTemporalPartials("refresh-additive-morph")
      end
      applyAllSampleDerivedAdditiveStates()
      return {
        enabled = blendMode == 4 or blendMode == 5,
        ready = ready,
        mix = blendAmount,
        activeCount = tonumber(latestSamplePartials and latestSamplePartials.activeCount) or 0,
        fundamental = tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
        temporalFrames = latestTemporalPartials and tonumber(latestTemporalPartials.frameCount) or 0,
      }
    end,

    getVoiceSamplePositions = function()
      local positions = {}
      for i = 1, VOICE_COUNT do
        local voice = voices[i]
        if voice and voice.amp > 0.0001 then
          positions[i] = (voice.samplePlayback and voice.samplePlayback:getNormalizedPosition()) or 0
        else
          positions[i] = 0
        end
      end
      return positions
    end,

    getSampleDerivedAddDebug = function(voiceIndex)
      local idx = math.max(1, math.min(VOICE_COUNT, tonumber(voiceIndex) or 1))
      local voice = voices[idx]
      if not voice then
        return {}
      end
      local sampleNode = voice.sampleAdditive and voice.sampleAdditive.__node or nil
      local blendOscNode = voice.blendAddOsc and voice.blendAddOsc.__node or nil
      return {
        enabled = blendMode == 4 or blendMode == 5,
        ready = hasUsableSampleAdditivePartials(latestSamplePartials),
        mix = blendAmount,
        voiceAmp = voice.amp or 0.0,
        gate = voice.gate or 0.0,
        targetFrequency = voice.lastSampleAdditiveFreq or 0.0,
        busMix = voice.lastSampleAdditiveMix or 0.0,
        activeCount = tonumber(latestSamplePartials and latestSamplePartials.activeCount) or 0,
        fundamental = tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
        referenceNote = sampleRootNote,
        blendSampleSpeed = voice.lastBlendSampleSpeed or 0.0,
        addCrossfadePosition = voice.addCrossfade and voice.addCrossfade:getPosition() or -9,
        addBranchGain = voice.addBranchGain and voice.addBranchGain:getGain() or 0.0,
        sampleAdditiveGain = voice.sampleAdditiveGain and voice.sampleAdditiveGain:getGain() or 0.0,
        branchGain1 = voice.branchMixer and voice.branchMixer:getGain(1) or -1,
        branchGain2 = voice.branchMixer and voice.branchMixer:getGain(2) or -1,
        branchGain3 = voice.branchMixer and voice.branchMixer:getGain(3) or -1,
        waveform = voice.waveform or -1,
        waveFrequency = voice.freq or 0.0,
        sampleNodeEnabled = sampleNode and sampleNode.isEnabled and sampleNode:isEnabled() or false,
        sampleNodeAmplitude = sampleNode and sampleNode.getAmplitude and sampleNode:getAmplitude() or 0.0,
        sampleNodeFrequency = sampleNode and sampleNode.getFrequency and sampleNode:getFrequency() or 0.0,
        sampleNodeActivePartials = sampleNode and sampleNode.getActivePartialCount and sampleNode:getActivePartialCount() or 0,
        sampleNodeReferenceFundamental = sampleNode and sampleNode.getReferenceFundamental and sampleNode:getReferenceFundamental() or 0.0,
        blendOscEnabled = blendOscNode and blendOscNode.isEnabled and blendOscNode:isEnabled() or false,
        blendOscAmplitude = blendOscNode and blendOscNode.getAmplitude and blendOscNode:getAmplitude() or 0.0,
        blendOscFrequency = blendOscNode and blendOscNode.getFrequency and blendOscNode:getFrequency() or 0.0,
        blendOscRenderMode = blendOscNode and blendOscNode.getRenderMode and blendOscNode:getRenderMode() or -1,
      }
    end,

    getBlendDebug = function(voiceIndex)
      local idx = math.max(1, math.min(VOICE_COUNT, tonumber(voiceIndex) or 1))
      local voice = voices[idx]
      if not voice then return "no voice" end
      local branchG1 = voice.branchMixer and voice.branchMixer:getGain(1) or -1
      local branchG2 = voice.branchMixer and voice.branchMixer:getGain(2) or -1
      local branchG3 = voice.branchMixer and voice.branchMixer:getGain(3) or -1
      local mixPos = voice.mixCrossfade and voice.mixCrossfade:getPosition() or -9
      local dirPos = voice.directionCrossfade and voice.directionCrossfade:getPosition() or -9
      local ringPos = voice.ringCrossfade and voice.ringCrossfade:getPosition() or -9
      local addPos = voice.addCrossfade and voice.addCrossfade:getPosition() or -9
      local addGain = voice.addBranchGain and voice.addBranchGain:getGain() or 0
      local baseSel = voice.basePathSelect and voice.basePathSelect:getPosition() or -9
      local samplePos = voice.samplePlayback and voice.samplePlayback:getNormalizedPosition() or 0
      local oscNode = voice.osc and voice.osc.__node or nil
      local oscAmp = oscNode and oscNode.getAmplitude and oscNode:getAmplitude() or 0.0
      local oscRender = oscNode and oscNode.getRenderMode and oscNode:getRenderMode() or renderMode
      return string.format(
        "render=%d mode=%d blend=%.3f depth=%.3f wg=%.3f sg=%.3f addActive=%s branch=[%.1f %.1f %.1f] xfade=[mix %.2f dir %.2f ring %.2f add %.2f base %.2f] addGain=%.2f oscFreq=%.2f oscAmp=%.3f sampleSpeed=%.3f samplePos=%.3f",
        oscRender, blendMode, blendAmount, blendModAmount, waveToSample, sampleToWave,
        tostring(blendMode == 4 or blendMode == 5),
        branchG1, branchG2, branchG3,
        mixPos, dirPos, ringPos, addPos, baseSel,
        addGain,
        voice.lastBlendOscFreq or 0.0,
        oscAmp,
        voice.lastBlendSampleSpeed or 0.0,
        samplePos)
    end,
  }
end

return M

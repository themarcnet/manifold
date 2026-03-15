-- MidiSynth_uiproject DSP entry
-- 8-voice polysynth with two serial swappable FX slots, ADSR, filter, delay, reverb.

local VOICE_COUNT = 8

local PATHS = {
  waveform = "/midi/synth/waveform",
  cutoff = "/midi/synth/cutoff",
  resonance = "/midi/synth/resonance",
  drive = "/midi/synth/drive",
  filterType = "/midi/synth/filterType",
  fx1Type = "/midi/synth/fx1/type",

  fx1Mix = "/midi/synth/fx1/mix",
  fx2Type = "/midi/synth/fx2/type",

  fx2Mix = "/midi/synth/fx2/mix",
  delayTimeL = "/midi/synth/delay/timeL",
  delayTimeR = "/midi/synth/delay/timeR",
  delayFeedback = "/midi/synth/delay/feedback",
  delayMix = "/midi/synth/delay/mix",
  reverbWet = "/midi/synth/reverb/wet",
  output = "/midi/synth/output",
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
  noiseLevel = "/midi/synth/noise/level",
  noiseColor = "/midi/synth/noise/color",
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

local FX_OPTIONS = {
  "Chorus",
  "Phaser",
  "WaveShaper",
  "Compressor",
  "StereoWidener",
  "Filter",
  "SVF Filter",
  "Reverb",
  "Stereo Delay",
  "Multitap",
  "Pitch Shift",
  "Granulator",
  "Ring Mod",
  "Formant",
  "EQ",
  "Limiter",
  "Transient",
}

function buildPlugin(ctx)
  local voices = {}
  local mix = ctx.primitives.MixerNode.new()

  local filt = ctx.primitives.SVFNode.new()
  filt:setMode(0)
  filt:setCutoff(3200)
  filt:setResonance(0.75)
  filt:setDrive(1.0)
  filt:setMix(1.0)

  local dist = ctx.primitives.DistortionNode.new()
  local delay = ctx.primitives.StereoDelayNode.new()
  local reverb = ctx.primitives.ReverbNode.new()
  local spec = ctx.primitives.SpectrumAnalyzerNode.new()
  local out = ctx.primitives.GainNode.new(2)

  local function connectMixerInput(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    ctx.graph.connect(source, mixer, 0, inputIndex - 1)
  end

  local MAX_FX_PARAMS = 5

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
      paramValues = {}, -- up to MAX_FX_PARAMS normalized 0-1 values
      mix = clamp01(defaultMix or 0.0),
      effects = {},
    }

    -- Init default param values
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
      -- Apply defaults for new effect
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

  -- Noise modulates oscillator shape per-voice
  local noiseGen = ctx.primitives.NoiseGeneratorNode.new()
  noiseGen:setLevel(1.0) -- always full level, per-voice gain controls amount
  noiseGen:setColor(0.1)
  local currentNoiseLevel = 0.0

  mix:setInputCount(VOICE_COUNT)

  for i = 1, VOICE_COUNT do
    local osc = ctx.primitives.OscillatorNode.new()
    osc:setWaveform(1)
    osc:setFrequency(220.0)
    osc:setAmplitude(0.0)

    -- Per-voice: osc + noise*gain → mixer → main mix
    local noiseGain = ctx.primitives.GainNode.new(2)
    noiseGain:setGain(0.0) -- noiseLevel * voiceAmp, updated manually

    local voiceMix = ctx.primitives.MixerNode.new()
    voiceMix:setInputCount(2)
    voiceMix:setGain(1, 1.0)
    voiceMix:setPan(1, 0.0)
    voiceMix:setGain(2, 1.0)
    voiceMix:setPan(2, 0.0)

    ctx.graph.connect(osc, voiceMix, 0, 0)
    ctx.graph.connect(noiseGen, noiseGain)
    ctx.graph.connect(noiseGain, voiceMix, 0, 1)
    ctx.graph.connect(voiceMix, mix, 0, i - 1)

    voices[i] = { osc = osc, noiseGain = noiseGain, gate = 0.0, targetAmp = 0.0, currentAmp = 0.0 }
  end

  dist:setDrive(1.8)
  dist:setMix(0.14)
  dist:setOutput(0.9)

  delay:setTempo(120)
  delay:setTimeMode(0)
  delay:setTimeL(220)
  delay:setTimeR(330)
  delay:setFeedback(0.24)
  delay:setFeedbackCrossfeed(0.12)
  delay:setFilterEnabled(true)
  delay:setFilterCutoff(4200)
  delay:setFilterResonance(0.5)
  delay:setMix(0.0)
  delay:setPingPong(true)
  delay:setWidth(0.8)
  delay:setFreeze(false)
  delay:setDucking(0.0)

  reverb:setRoomSize(0.52)
  reverb:setDamping(0.4)
  reverb:setWetLevel(0.0)
  reverb:setDryLevel(1.0)
  reverb:setWidth(1.0)

  spec:setSensitivity(1.2)
  spec:setSmoothing(0.86)
  spec:setFloor(-72)

  out:setGain(0.8)

  ctx.graph.connect(mix, filt)
  ctx.graph.connect(filt, dist)
  fx1Slot.connectSource(dist)
  fx2Slot.connectSource(fx1Slot.output)
  ctx.graph.connect(fx2Slot.output, delay)
  ctx.graph.connect(delay, reverb)
  ctx.graph.connect(reverb, spec)
  ctx.graph.connect(spec, out)

  local params = {}
  local adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }


  local function addParam(path, specDef)
    ctx.params.register(path, specDef)
    params[#params + 1] = path
  end

  for i = 1, VOICE_COUNT do
    local freqPath = voiceFreqPath(i)
    local ampPath = voiceAmpPath(i)
    local gatePath = voiceGatePath(i)

    addParam(freqPath, {
      type = "f",
      min = 20.0,
      max = 8000.0,
      default = 220.0,
      description = "Voice frequency " .. i,
    })
    ctx.params.bind(freqPath, voices[i].osc, "setFrequency")

    addParam(ampPath, {
      type = "f",
      min = 0.0,
      max = 0.5,
      default = 0.0,
      description = "Voice amplitude " .. i,
    })
    ctx.params.bind(ampPath, voices[i].osc, "setAmplitude")

    addParam(gatePath, {
      type = "f",
      min = 0.0,
      max = 1.0,
      default = 0.0,
      description = "Voice gate " .. i,
    })
  end

  -- Build voice amp path → index lookup for noise gain tracking
  local voiceAmpPathToIndex = {}
  local voiceLastAmp = {}
  for i = 1, VOICE_COUNT do
    voiceAmpPathToIndex[voiceAmpPath(i)] = i
    voiceLastAmp[i] = 0.0
  end

  addParam(PATHS.waveform, {
    type = "f",
    min = 0.0,
    max = 4.0,
    default = 1.0,
    description = "Shared oscillator waveform",
  })

  addParam(PATHS.filterType, {
    type = "f",
    min = 0.0,
    max = 3.0,
    default = 0.0,
    description = "Filter type (0=LP, 1=BP, 2=HP, 3=Notch)",
  })

  addParam(PATHS.cutoff, {
    type = "f",
    min = 80.0,
    max = 16000.0,
    default = 3200.0,
    description = "Filter cutoff",
  })
  ctx.params.bind(PATHS.cutoff, filt, "setCutoff")

  addParam(PATHS.resonance, {
    type = "f",
    min = 0.1,
    max = 2.0,
    default = 0.75,
    description = "Filter resonance",
  })
  ctx.params.bind(PATHS.resonance, filt, "setResonance")

  addParam(PATHS.drive, {
    type = "f",
    min = 0.0,
    max = 20.0,
    default = 1.8,
    description = "Drive amount",
  })
  ctx.params.bind(PATHS.drive, dist, "setDrive")

  addParam(PATHS.fx1Type, { type = "f", min = 0, max = #FX_OPTIONS - 1, default = 0, description = "FX1 type" })
  addParam(PATHS.fx1Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX1 wet/dry" })
  addParam(PATHS.fx2Type, { type = "f", min = 0, max = #FX_OPTIONS - 1, default = 0, description = "FX2 type" })
  addParam(PATHS.fx2Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX2 wet/dry" })

  -- Register individual params per FX slot (0-4)
  for i = 0, MAX_FX_PARAMS - 1 do
    local fx1Path = string.format("/midi/synth/fx1/p/%d", i)
    local fx2Path = string.format("/midi/synth/fx2/p/%d", i)
    addParam(fx1Path, { type = "f", min = 0, max = 1, default = 0.5, description = "FX1 param " .. i })
    addParam(fx2Path, { type = "f", min = 0, max = 1, default = 0.5, description = "FX2 param " .. i })
  end

  addParam(PATHS.delayTimeL, {
    type = "f",
    min = 10.0,
    max = 2000.0,
    default = 220.0,
    description = "Delay time left",
  })
  ctx.params.bind(PATHS.delayTimeL, delay, "setTimeL")

  addParam(PATHS.delayTimeR, {
    type = "f",
    min = 10.0,
    max = 2000.0,
    default = 330.0,
    description = "Delay time right",
  })
  ctx.params.bind(PATHS.delayTimeR, delay, "setTimeR")

  addParam(PATHS.delayFeedback, {
    type = "f",
    min = 0.0,
    max = 0.99,
    default = 0.24,
    description = "Delay feedback",
  })
  ctx.params.bind(PATHS.delayFeedback, delay, "setFeedback")

  addParam(PATHS.delayMix, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.0,
    description = "Delay mix",
  })
  ctx.params.bind(PATHS.delayMix, delay, "setMix")

  addParam(PATHS.reverbWet, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.0,
    description = "Reverb wet level",
  })
  ctx.params.bind(PATHS.reverbWet, reverb, "setWetLevel")

  addParam(PATHS.output, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.8,
    description = "Output gain",
  })
  ctx.params.bind(PATHS.output, out, "setGain")

  addParam(PATHS.attack, {
    type = "f",
    min = 0.001,
    max = 5.0,
    default = 0.05,
    description = "ADSR attack time (seconds)",
  })

  addParam(PATHS.decay, {
    type = "f",
    min = 0.001,
    max = 5.0,
    default = 0.2,
    description = "ADSR decay time (seconds)",
  })

  addParam(PATHS.sustain, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.7,
    description = "ADSR sustain level",
  })

  addParam(PATHS.release, {
    type = "f",
    min = 0.001,
    max = 10.0,
    default = 0.4,
    description = "ADSR release time (seconds)",
  })

  addParam(PATHS.noiseLevel, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.0,
    description = "Noise modulation of oscillator signal",
  })

  addParam(PATHS.noiseColor, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.1,
    description = "Noise color (0=pink, 1=white)",
  })
  ctx.params.bind(PATHS.noiseColor, noiseGen, "setColor")

  local function applyWaveform(value)
    local waveform = roundIndex(value, 4)
    for i = 1, VOICE_COUNT do
      voices[i].osc:setWaveform(waveform)
    end
  end

  local function applyFilterType(value)
    filt:setMode(roundIndex(value, 3))
  end

  applyWaveform(1)

  return {
    description = "Eight-voice polysynth with two serial FX slots, ADSR, filter, delay and reverb",
    params = params,
    onParamChange = function(path, value)
      -- Voice amp → update noise gain for that voice
      local voiceIdx = voiceAmpPathToIndex[path]
      if voiceIdx then
        local amp = clamp(tonumber(value) or 0, 0, 0.5)
        voiceLastAmp[voiceIdx] = amp
        voices[voiceIdx].noiseGain:setGain(currentNoiseLevel * amp)
        return
      end

      if path == PATHS.noiseLevel then
        currentNoiseLevel = clamp01(tonumber(value) or 0.0)
        -- Update all voice noise gains
        for i = 1, VOICE_COUNT do
          voices[i].noiseGain:setGain(currentNoiseLevel * voiceLastAmp[i])
        end
      elseif path == PATHS.waveform then
        applyWaveform(value)
      elseif path == PATHS.filterType then
        applyFilterType(value)
      elseif path == PATHS.attack then
        adsr.attack = math.max(0.001, tonumber(value) or 0.05)
      elseif path == PATHS.decay then
        adsr.decay = math.max(0.001, tonumber(value) or 0.2)
      elseif path == PATHS.sustain then
        adsr.sustain = math.max(0.0, math.min(1.0, tonumber(value) or 0.7))
      elseif path == PATHS.release then
        adsr.release = math.max(0.001, tonumber(value) or 0.4)
      elseif path == PATHS.fx1Type then
        fx1Slot.applySelection(value)
      elseif path == PATHS.fx1Mix then
        fx1Slot.applyMix(value)
      elseif path == PATHS.fx2Type then
        fx2Slot.applySelection(value)
      elseif path == PATHS.fx2Mix then
        fx2Slot.applyMix(value)
      else
        -- Check individual FX params: /midi/synth/fx1/p/0 through /p/4
        local fx1pi = path:match("^/midi/synth/fx1/p/(%d+)$")
        local fx2pi = path:match("^/midi/synth/fx2/p/(%d+)$")
        if fx1pi then
          fx1Slot.applyParam(tonumber(fx1pi) + 1, value)
        elseif fx2pi then
          fx2Slot.applyParam(tonumber(fx2pi) + 1, value)
        end
      end
    end,
  }
end

return buildPlugin

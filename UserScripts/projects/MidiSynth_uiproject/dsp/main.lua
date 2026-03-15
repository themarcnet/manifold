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
  fx1Param1 = "/midi/synth/fx1/param1",
  fx1Param2 = "/midi/synth/fx1/param2",
  fx1Mix = "/midi/synth/fx1/mix",
  fx2Type = "/midi/synth/fx2/type",
  fx2Param1 = "/midi/synth/fx2/param1",
  fx2Param2 = "/midi/synth/fx2/param2",
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

  local function buildFxDefs()
    local P = ctx.primitives

    return {
      {
        label = "Chorus",
        create = function()
          local node = P.ChorusNode.new()
          node:setRate(0.35)
          node:setDepth(0.3)
          node:setVoices(3)
          node:setSpread(0.6)
          node:setFeedback(0.08)
          node:setWaveform(0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setRate(lerp(0.08, 2.4, p1))
          effect.node:setDepth(lerp(0.05, 1.0, p2))
          effect.node:setFeedback(lerp(0.0, 0.35, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Phaser",
        create = function()
          local node = P.PhaserNode.new()
          node:setRate(0.3)
          node:setDepth(0.45)
          node:setStages(6)
          node:setFeedback(0.35)
          node:setSpread(0.4)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setRate(lerp(0.05, 2.8, p1))
          effect.node:setDepth(lerp(0.05, 1.0, p2))
          effect.node:setFeedback(lerp(0.0, 0.8, p2))
          effect.node:setSpread(lerp(0.0, 1.0, p1))
        end,
      },
      {
        label = "WaveShaper",
        create = function()
          local node = P.WaveShaperNode.new()
          node:setCurve(0)
          node:setDrive(2.5)
          node:setOutput(0.8)
          node:setPreFilter(0.0)
          node:setPostFilter(0.0)
          node:setBias(0.0)
          node:setMix(1.0)
          node:setOversample(2)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setCurve(math.floor(lerp(0.0, 6.0, p2) + 0.5))
          effect.node:setDrive(lerp(0.75, 18.0, p1))
          effect.node:setOutput(lerp(1.0, 0.25, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Compressor",
        create = function()
          local node = P.CompressorNode.new()
          node:setThreshold(-18.0)
          node:setRatio(4.0)
          node:setAttack(5.0)
          node:setRelease(100.0)
          node:setKnee(6.0)
          node:setMakeup(0.0)
          node:setAutoMakeup(true)
          node:setMode(0)
          node:setDetectorMode(0)
          node:setSidechainHPF(100.0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setThreshold(lerp(-40.0, -2.0, p1))
          effect.node:setRatio(lerp(1.5, 20.0, p2))
          effect.node:setAttack(lerp(1.0, 40.0, 1.0 - p1))
          effect.node:setRelease(lerp(20.0, 250.0, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "StereoWidener",
        create = function()
          local node = P.StereoWidenerNode.new()
          node:setWidth(1.25)
          node:setMonoLowFreq(140.0)
          node:setMonoLowEnable(true)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setWidth(lerp(0.0, 2.0, p1))
          effect.node:setMonoLowFreq(lerp(40.0, 320.0, p2))
          effect.node:setMonoLowEnable(true)
        end,
      },
      {
        label = "Filter",
        create = function()
          local node = P.FilterNode.new()
          node:setCutoff(1000.0)
          node:setResonance(0.2)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setCutoff(expLerp(80.0, 12000.0, p1))
          effect.node:setResonance(lerp(0.0, 1.0, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "SVF Filter",
        create = function()
          local node = P.SVFNode.new()
          node:setCutoff(1200.0)
          node:setResonance(0.35)
          node:setMode(0)
          node:setDrive(0.5)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setCutoff(expLerp(60.0, 10000.0, p1))
          effect.node:setResonance(lerp(0.08, 1.0, p2))
          effect.node:setDrive(lerp(0.0, 6.0, p2))
          effect.node:setMode(0)
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Reverb",
        create = function()
          local node = P.ReverbNode.new()
          node:setRoomSize(0.55)
          node:setDamping(0.4)
          node:setWetLevel(1.0)
          node:setDryLevel(0.0)
          node:setWidth(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setRoomSize(lerp(0.15, 0.95, p1))
          effect.node:setDamping(lerp(0.0, 1.0, p2))
          effect.node:setWetLevel(1.0)
          effect.node:setDryLevel(0.0)
          effect.node:setWidth(1.0)
        end,
      },
      {
        label = "Stereo Delay",
        create = function()
          local node = P.StereoDelayNode.new()
          node:setTempo(120)
          node:setTimeMode(0)
          node:setTimeL(250)
          node:setTimeR(375)
          node:setFeedback(0.3)
          node:setFeedbackCrossfeed(0.12)
          node:setFilterEnabled(0)
          node:setFilterCutoff(4200)
          node:setFilterResonance(0.5)
          node:setMix(1.0)
          node:setPingPong(1)
          node:setWidth(1.0)
          node:setFreeze(0)
          node:setDucking(0.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          local baseMs = lerp(40.0, 780.0, p1)
          effect.node:setTimeL(baseMs)
          effect.node:setTimeR(baseMs * 1.5)
          effect.node:setFeedback(lerp(0.0, 0.92, p2))
          effect.node:setMix(1.0)
          effect.node:setPingPong(1)
          effect.node:setWidth(1.0)
        end,
      },
      {
        label = "Multitap",
        create = function()
          local node = P.MultitapDelayNode.new()
          node:setTapCount(4)
          node:setTapTime(1, 180)
          node:setTapTime(2, 320)
          node:setTapTime(3, 470)
          node:setTapTime(4, 620)
          node:setTapGain(1, 0.5)
          node:setTapGain(2, 0.35)
          node:setTapGain(3, 0.28)
          node:setTapGain(4, 0.2)
          node:setTapPan(1, -0.8)
          node:setTapPan(2, -0.25)
          node:setTapPan(3, 0.25)
          node:setTapPan(4, 0.8)
          node:setFeedback(0.3)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setTapCount(math.floor(lerp(2.0, 8.0, p1) + 0.5))
          effect.node:setFeedback(lerp(0.0, 0.95, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Pitch Shift",
        create = function()
          local node = P.PitchShifterNode.new()
          node:setPitch(7.0)
          node:setWindow(80.0)
          node:setFeedback(0.15)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setPitch(lerp(-12.0, 12.0, p1))
          effect.node:setWindow(lerp(30.0, 180.0, p2))
          effect.node:setFeedback(lerp(0.0, 0.75, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Granulator",
        create = function()
          local node = P.GranulatorNode.new()
          node:setGrainSize(90.0)
          node:setDensity(24.0)
          node:setPosition(0.6)
          node:setPitch(0.0)
          node:setSpray(0.25)
          node:setFreeze(false)
          node:setEnvelope(0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setGrainSize(lerp(12.0, 280.0, p1))
          effect.node:setDensity(lerp(2.0, 64.0, p2))
          effect.node:setPosition(p1)
          effect.node:setSpray(lerp(0.0, 1.0, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Ring Mod",
        create = function()
          local node = P.RingModulatorNode.new()
          node:setFrequency(120.0)
          node:setDepth(1.0)
          node:setMix(1.0)
          node:setSpread(30.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setFrequency(expLerp(20.0, 2000.0, p1))
          effect.node:setDepth(lerp(0.0, 1.0, p2))
          effect.node:setSpread(lerp(0.0, 180.0, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Formant",
        create = function()
          local node = P.FormantFilterNode.new()
          node:setVowel(0.0)
          node:setShift(0.0)
          node:setResonance(7.0)
          node:setDrive(1.4)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setVowel(lerp(0.0, 4.0, p1))
          effect.node:setShift(lerp(-12.0, 12.0, p2))
          effect.node:setResonance(lerp(2.0, 16.0, p2))
          effect.node:setDrive(lerp(0.8, 4.0, p1))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "EQ",
        create = function()
          local node = P.EQNode.new()
          node:setLowGain(0.0)
          node:setLowFreq(120.0)
          node:setMidGain(0.0)
          node:setMidFreq(900.0)
          node:setMidQ(0.8)
          node:setHighGain(0.0)
          node:setHighFreq(8000.0)
          node:setOutput(0.0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setLowGain(lerp(-12.0, 12.0, p1))
          effect.node:setHighGain(lerp(-12.0, 12.0, p2))
          effect.node:setMidGain(lerp(-6.0, 6.0, 0.5 * (p1 + p2)))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Limiter",
        create = function()
          local pre = P.GainNode.new(2)
          local node = P.LimiterNode.new()
          pre:setGain(1.0)
          node:setThreshold(-6.0)
          node:setRelease(80.0)
          node:setMakeup(0.0)
          node:setSoftClip(0.4)
          node:setMix(1.0)
          ctx.graph.connect(pre, node)
          return { input = pre, output = node, node = node, pre = pre }
        end,
        apply = function(effect, p1, p2)
          effect.pre:setGain(lerp(0.6, 2.0, p2))
          effect.node:setThreshold(lerp(-20.0, -1.0, p1))
          effect.node:setRelease(lerp(10.0, 200.0, p2))
          effect.node:setSoftClip(lerp(0.0, 1.0, p2))
          effect.node:setMix(1.0)
        end,
      },
      {
        label = "Transient",
        create = function()
          local node = P.TransientShaperNode.new()
          node:setAttack(0.6)
          node:setSustain(-0.3)
          node:setSensitivity(1.2)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        apply = function(effect, p1, p2)
          effect.node:setAttack(lerp(-1.0, 1.0, p1))
          effect.node:setSustain(lerp(-1.0, 1.0, p2))
          effect.node:setSensitivity(lerp(0.2, 4.0, p2))
          effect.node:setMix(1.0)
        end,
      },
    }
  end

  local fxDefs = buildFxDefs()

  local function createFxSlot(defaultType, defaultP1, defaultP2, defaultMix)
    local slot = {
      select = roundIndex(defaultType or 0, #fxDefs - 1),
      param1 = clamp01(defaultP1 or 0.5),
      param2 = clamp01(defaultP2 or 0.5),
      mix = clamp01(defaultMix or 0.0),
      effects = {},
    }

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
      def.apply(effect, slot.param1, slot.param2)
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
    end

    function slot.applyParams(p1, p2)
      slot.param1 = clamp01(tonumber(p1) or slot.param1)
      slot.param2 = clamp01(tonumber(p2) or slot.param2)
      local effect = slot.effects[slot.select + 1]
      if effect and effect.def and effect.def.apply then
        effect.def.apply(effect, slot.param1, slot.param2)
      end
    end

    function slot.applyMix(value)
      slot.mix = clamp01(tonumber(value) or slot.mix)
      slot.dry:setGain(1.0 - slot.mix)
      slot.wetTrim:setGain(slot.mix)
    end

    function slot.refresh(typeValue, p1, p2, mixValue)
      slot.applySelection(typeValue)
      slot.applyParams(p1, p2)
      slot.applyMix(mixValue)
    end

    slot.refresh(slot.select, slot.param1, slot.param2, slot.mix)
    return slot
  end

  local fx1Slot = createFxSlot(0, 0.5, 0.5, 0.0)
  local fx2Slot = createFxSlot(0, 0.5, 0.5, 0.0)

  mix:setInputCount(VOICE_COUNT)

  for i = 1, VOICE_COUNT do
    local osc = ctx.primitives.OscillatorNode.new()
    osc:setWaveform(1)
    osc:setFrequency(220.0)
    osc:setAmplitude(0.0)
    voices[i] = { osc = osc, gate = 0.0, targetAmp = 0.0, currentAmp = 0.0 }
    ctx.graph.connect(osc, mix, 0, i - 1)
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
  delay:setFilterEnabled(1)
  delay:setFilterCutoff(4200)
  delay:setFilterResonance(0.5)
  delay:setMix(0.18)
  delay:setPingPong(1)
  delay:setWidth(0.8)
  delay:setFreeze(0)
  delay:setDucking(0.0)

  reverb:setRoomSize(0.52)
  reverb:setDamping(0.4)
  reverb:setWetLevel(0.16)
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
  local currentFx1Type = 0
  local currentFx2Type = 0
  local currentFx1Param1, currentFx1Param2, currentFx1Mix = 0.5, 0.5, 0.0
  local currentFx2Param1, currentFx2Param2, currentFx2Mix = 0.5, 0.5, 0.0

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

  addParam(PATHS.fx1Type, {
    type = "f",
    min = 0.0,
    max = #FX_OPTIONS - 1,
    default = 0.0,
    description = "FX1 type",
  })

  addParam(PATHS.fx1Param1, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.5,
    description = "FX1 param 1",
  })

  addParam(PATHS.fx1Param2, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.5,
    description = "FX1 param 2",
  })

  addParam(PATHS.fx1Mix, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.0,
    description = "FX1 wet/dry mix",
  })

  addParam(PATHS.fx2Type, {
    type = "f",
    min = 0.0,
    max = #FX_OPTIONS - 1,
    default = 0.0,
    description = "FX2 type",
  })

  addParam(PATHS.fx2Param1, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.5,
    description = "FX2 param 1",
  })

  addParam(PATHS.fx2Param2, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.5,
    description = "FX2 param 2",
  })

  addParam(PATHS.fx2Mix, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.0,
    description = "FX2 wet/dry mix",
  })

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
    default = 0.18,
    description = "Delay mix",
  })
  ctx.params.bind(PATHS.delayMix, delay, "setMix")

  addParam(PATHS.reverbWet, {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.16,
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

  local function applyWaveform(value)
    local waveform = roundIndex(value, 4)
    for i = 1, VOICE_COUNT do
      voices[i].osc:setWaveform(waveform)
    end
  end

  local function applyFilterType(value)
    filt:setMode(roundIndex(value, 3))
  end

  local function applyFx1Selection(fxType, userMix)
    currentFx1Type = roundIndex(fxType, #FX_OPTIONS - 1)
    currentFx1Mix = clamp01(tonumber(userMix) or currentFx1Mix)
    fx1Slot.refresh(currentFx1Type, currentFx1Param1, currentFx1Param2, currentFx1Mix)
  end

  local function applyFx2Selection(fxType, userMix)
    currentFx2Type = roundIndex(fxType, #FX_OPTIONS - 1)
    currentFx2Mix = clamp01(tonumber(userMix) or currentFx2Mix)
    fx2Slot.refresh(currentFx2Type, currentFx2Param1, currentFx2Param2, currentFx2Mix)
  end

  local function updateFx1Params(p1, p2, mixVal)
    currentFx1Param1 = clamp01(tonumber(p1) or currentFx1Param1)
    currentFx1Param2 = clamp01(tonumber(p2) or currentFx1Param2)
    currentFx1Mix = clamp01(tonumber(mixVal) or currentFx1Mix)
    fx1Slot.refresh(currentFx1Type, currentFx1Param1, currentFx1Param2, currentFx1Mix)
  end

  local function updateFx2Params(p1, p2, mixVal)
    currentFx2Param1 = clamp01(tonumber(p1) or currentFx2Param1)
    currentFx2Param2 = clamp01(tonumber(p2) or currentFx2Param2)
    currentFx2Mix = clamp01(tonumber(mixVal) or currentFx2Mix)
    fx2Slot.refresh(currentFx2Type, currentFx2Param1, currentFx2Param2, currentFx2Mix)
  end

  applyWaveform(1)
  applyFx1Selection(0, 0.0)
  applyFx2Selection(0, 0.0)

  return {
    description = "Eight-voice polysynth with two serial FX slots, ADSR, filter, delay and reverb",
    params = params,
    onParamChange = function(path, value)
      if path == PATHS.waveform then
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
        applyFx1Selection(value, currentFx1Mix)
      elseif path == PATHS.fx1Mix then
        updateFx1Params(nil, nil, value)
      elseif path == PATHS.fx1Param1 then
        updateFx1Params(value, nil, nil)
      elseif path == PATHS.fx1Param2 then
        updateFx1Params(nil, value, nil)
      elseif path == PATHS.fx2Type then
        applyFx2Selection(value, currentFx2Mix)
      elseif path == PATHS.fx2Mix then
        updateFx2Params(nil, nil, value)
      elseif path == PATHS.fx2Param1 then
        updateFx2Params(value, nil, nil)
      elseif path == PATHS.fx2Param2 then
        updateFx2Params(nil, value, nil)
      end
    end,
  }
end

return buildPlugin

-- Project-local Main Super FX extension.
--
-- This module owns the shared Super graph for the Main project. It is
-- reused both by the standalone SuperDonut path and by the Main shared
-- slot runtime so the effect graph lives in project DSP code instead of a
-- generated string blob.

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function attach(ctx, layers)
  local state = {
    vocal = nil,
    layerFx = {},
  }

  local function register(path, opts)
    ctx.params.register(path, opts)
  end

  local function normalizePath(path)
    if type(path) ~= "string" then
      return path
    end
    if string.sub(path, 1, 21) == "/core/behavior/super/" then
      return "/core/super/" .. string.sub(path, 22)
    end
    return path
  end

  local function connectMixerInput(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    ctx.graph.connect(source, mixer, 0, inputIndex - 1)
  end

  local function buildEffectDefs()
    local P = ctx.primitives
    return {
      {
        id = "bypass",
        label = "Bypass",
        create = function()
          local node = P.PassthroughNode.new(2)
          return { input = node, output = node, node = node }
        end,
        params = {},
      },
      {
        id = "chorus",
        label = "Chorus",
        create = function()
          local node = P.ChorusNode.new()
          node:setRate(0.7)
          node:setDepth(0.5)
          node:setVoices(3)
          node:setSpread(0.8)
          node:setFeedback(0.15)
          node:setWaveform(0)
          node:setMix(0.55)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "rate", type = "f", min = 0.1, max = 10.0, default = 0.7, apply = function(e, v) e.node:setRate(v) end },
          { name = "depth", type = "f", min = 0.0, max = 1.0, default = 0.5, apply = function(e, v) e.node:setDepth(v) end },
          { name = "voices", type = "f", min = 1.0, max = 4.0, default = 3.0, apply = function(e, v) e.node:setVoices(v) end },
          { name = "spread", type = "f", min = 0.0, max = 1.0, default = 0.8, apply = function(e, v) e.node:setSpread(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 0.9, default = 0.15, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "waveform", type = "f", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setWaveform(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 0.55, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "phaser",
        label = "Phaser",
        create = function()
          local node = P.PhaserNode.new()
          node:setRate(0.35)
          node:setDepth(0.8)
          node:setStages(6)
          node:setFeedback(0.25)
          node:setSpread(120)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "rate", type = "f", min = 0.1, max = 10.0, default = 0.35, apply = function(e, v) e.node:setRate(v) end },
          { name = "depth", type = "f", min = 0.0, max = 1.0, default = 0.8, apply = function(e, v) e.node:setDepth(v) end },
          { name = "stages", type = "f", min = 6.0, max = 12.0, default = 6.0, apply = function(e, v) e.node:setStages(v) end },
          { name = "feedback", type = "f", min = -0.9, max = 0.9, default = 0.25, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "spread", type = "f", min = 0.0, max = 180.0, default = 120.0, apply = function(e, v) e.node:setSpread(v) end },
        },
      },
      {
        id = "bitcrusher",
        label = "Bitcrusher",
        create = function()
          local node = P.BitCrusherNode.new()
          node:setBits(6)
          node:setRateReduction(8)
          node:setMix(1.0)
          node:setOutput(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "bits", type = "f", min = 2.0, max = 16.0, default = 6.0, apply = function(e, v) e.node:setBits(v) end },
          { name = "rate", type = "f", min = 1.0, max = 64.0, default = 8.0, apply = function(e, v) e.node:setRateReduction(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
          { name = "output", type = "f", min = 0.0, max = 2.0, default = 1.0, apply = function(e, v) e.node:setOutput(v) end },
        },
      },
      {
        id = "waveshaper",
        label = "Waveshaper",
        create = function()
          local node = P.WaveShaperNode.new()
          node:setCurve(0)
          node:setDrive(12.0)
          node:setOutput(-3.0)
          node:setPreFilter(0.0)
          node:setPostFilter(0.0)
          node:setBias(0.0)
          node:setMix(1.0)
          node:setOversample(2)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "curve", type = "f", min = 0.0, max = 6.0, default = 0.0, apply = function(e, v) e.node:setCurve(v) end },
          { name = "drive", type = "f", min = 0.0, max = 40.0, default = 12.0, apply = function(e, v) e.node:setDrive(v) end },
          { name = "output", type = "f", min = -20.0, max = 20.0, default = -3.0, apply = function(e, v) e.node:setOutput(v) end },
          { name = "prefilter", type = "f", min = 0.0, max = 10000.0, default = 0.0, apply = function(e, v) e.node:setPreFilter(v) end },
          { name = "postfilter", type = "f", min = 0.0, max = 10000.0, default = 0.0, apply = function(e, v) e.node:setPostFilter(v) end },
          { name = "bias", type = "f", min = -1.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setBias(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
          { name = "oversample", type = "f", min = 1.0, max = 4.0, default = 2.0, apply = function(e, v) e.node:setOversample(v) end },
        },
      },
      {
        id = "filter",
        label = "Filter",
        create = function()
          local node = P.FilterNode.new()
          node:setCutoff(900.0)
          node:setResonance(0.2)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "cutoff", type = "f", min = 80.0, max = 8000.0, default = 900.0, apply = function(e, v) e.node:setCutoff(v) end },
          { name = "resonance", type = "f", min = 0.0, max = 1.0, default = 0.2, apply = function(e, v) e.node:setResonance(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "svf",
        label = "SVF Filter",
        create = function()
          local node = P.SVFNode.new()
          node:setCutoff(1000.0)
          node:setResonance(0.5)
          node:setMode(0)
          node:setDrive(0.0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "cutoff", type = "f", min = 40.0, max = 10000.0, default = 1000.0, apply = function(e, v) e.node:setCutoff(v) end },
          { name = "resonance", type = "f", min = 0.06, max = 1.0, default = 0.5, apply = function(e, v) e.node:setResonance(v) end },
          { name = "mode", type = "i", min = 0.0, max = 4.0, default = 0.0, apply = function(e, v) e.node:setMode(v) end },
          { name = "drive", type = "f", min = 0.0, max = 10.0, default = 0.0, apply = function(e, v) e.node:setDrive(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "reverb",
        label = "Reverb",
        create = function()
          local node = P.ReverbNode.new()
          node:setRoomSize(0.65)
          node:setDamping(0.4)
          node:setWetLevel(0.35)
          node:setDryLevel(0.85)
          node:setWidth(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "room", type = "f", min = 0.0, max = 1.0, default = 0.65, apply = function(e, v) e.node:setRoomSize(v) end },
          { name = "damping", type = "f", min = 0.0, max = 1.0, default = 0.4, apply = function(e, v) e.node:setDamping(v) end },
          { name = "wet", type = "f", min = 0.0, max = 1.0, default = 0.35, apply = function(e, v) e.node:setWetLevel(v) end },
          { name = "dry", type = "f", min = 0.0, max = 1.0, default = 0.85, apply = function(e, v) e.node:setDryLevel(v) end },
          { name = "width", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setWidth(v) end },
        },
      },
      {
        id = "shimmer",
        label = "Shimmer",
        create = function()
          local node = P.ShimmerNode.new()
          node:setSize(0.65)
          node:setPitch(12)
          node:setFeedback(0.7)
          node:setMix(0.5)
          node:setModulation(0.25)
          node:setFilter(5500)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "size", type = "f", min = 0.0, max = 1.0, default = 0.65, apply = function(e, v) e.node:setSize(v) end },
          { name = "pitch", type = "f", min = -12.0, max = 12.0, default = 12.0, apply = function(e, v) e.node:setPitch(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 0.99, default = 0.7, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 0.5, apply = function(e, v) e.node:setMix(v) end },
          { name = "mod", type = "f", min = 0.0, max = 1.0, default = 0.25, apply = function(e, v) e.node:setModulation(v) end },
          { name = "filter", type = "f", min = 100.0, max = 12000.0, default = 5500.0, apply = function(e, v) e.node:setFilter(v) end },
        },
      },
      {
        id = "stereodelay",
        label = "Stereo Delay",
        create = function()
          local node = P.StereoDelayNode.new()
          node:setTempo(120)
          node:setTimeMode(0)
          node:setTimeL(250)
          node:setTimeR(375)
          node:setFeedback(0.3)
          node:setPingPong(false)
          node:setFilterEnabled(false)
          node:setFilterCutoff(4000)
          node:setMix(0.5)
          node:setFreeze(false)
          node:setWidth(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "timemode", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setTimeMode(v) end },
          { name = "timel", type = "f", min = 10.0, max = 2000.0, default = 250.0, apply = function(e, v) e.node:setTimeL(v) end },
          { name = "timer", type = "f", min = 10.0, max = 2000.0, default = 375.0, apply = function(e, v) e.node:setTimeR(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 1.2, default = 0.3, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "pingpong", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setPingPong(v > 0.5) end },
          { name = "filter", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setFilterEnabled(v > 0.5) end },
          { name = "filtercutoff", type = "f", min = 200.0, max = 10000.0, default = 4000.0, apply = function(e, v) e.node:setFilterCutoff(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 0.5, apply = function(e, v) e.node:setMix(v) end },
          { name = "freeze", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setFreeze(v > 0.5) end },
          { name = "width", type = "f", min = 0.0, max = 2.0, default = 1.0, apply = function(e, v) e.node:setWidth(v) end },
        },
      },
      {
        id = "reversedelay",
        label = "Reverse Delay",
        create = function()
          local node = P.ReverseDelayNode.new()
          node:setTime(420)
          node:setWindow(120)
          node:setFeedback(0.45)
          node:setMix(0.65)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "time", type = "f", min = 50.0, max = 2000.0, default = 420.0, apply = function(e, v) e.node:setTime(v) end },
          { name = "window", type = "f", min = 20.0, max = 400.0, default = 120.0, apply = function(e, v) e.node:setWindow(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 0.95, default = 0.45, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 0.65, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "multitap",
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
          node:setMix(0.55)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "tapcount", type = "f", min = 1.0, max = 8.0, default = 4.0, apply = function(e, v) e.node:setTapCount(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 0.95, default = 0.3, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 0.55, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "pitchshift",
        label = "Pitch Shift",
        create = function()
          local node = P.PitchShifterNode.new()
          node:setPitch(7)
          node:setWindow(80)
          node:setFeedback(0.15)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "pitch", type = "f", min = -24.0, max = 24.0, default = 7.0, apply = function(e, v) e.node:setPitch(v) end },
          { name = "window", type = "f", min = 20.0, max = 200.0, default = 80.0, apply = function(e, v) e.node:setWindow(v) end },
          { name = "feedback", type = "f", min = 0.0, max = 0.95, default = 0.15, apply = function(e, v) e.node:setFeedback(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "granulator",
        label = "Granulator",
        create = function()
          local node = P.GranulatorNode.new()
          node:setGrainSize(90)
          node:setDensity(24)
          node:setPosition(0.6)
          node:setPitch(0)
          node:setSpray(0.25)
          node:setFreeze(false)
          node:setEnvelope(0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "grainsize", type = "f", min = 1.0, max = 500.0, default = 90.0, apply = function(e, v) e.node:setGrainSize(v) end },
          { name = "density", type = "f", min = 1.0, max = 100.0, default = 24.0, apply = function(e, v) e.node:setDensity(v) end },
          { name = "position", type = "f", min = 0.0, max = 1.0, default = 0.6, apply = function(e, v) e.node:setPosition(v) end },
          { name = "pitch", type = "f", min = -24.0, max = 24.0, default = 0.0, apply = function(e, v) e.node:setPitch(v) end },
          { name = "spray", type = "f", min = 0.0, max = 1.0, default = 0.25, apply = function(e, v) e.node:setSpray(v) end },
          { name = "freeze", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setFreeze(v > 0.5) end },
          { name = "envelope", type = "f", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setEnvelope(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "ringmod",
        label = "Ring Mod",
        create = function()
          local node = P.RingModulatorNode.new()
          node:setFrequency(120)
          node:setDepth(1.0)
          node:setMix(1.0)
          node:setSpread(30)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "freq", type = "f", min = 0.1, max = 2000.0, default = 120.0, apply = function(e, v) e.node:setFrequency(v) end },
          { name = "depth", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setDepth(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
          { name = "spread", type = "f", min = 0.0, max = 180.0, default = 30.0, apply = function(e, v) e.node:setSpread(v) end },
        },
      },
      {
        id = "formant",
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
        params = {
          { name = "vowel", type = "f", min = 0.0, max = 4.0, default = 0.0, apply = function(e, v) e.node:setVowel(v) end },
          { name = "shift", type = "f", min = -12.0, max = 12.0, default = 0.0, apply = function(e, v) e.node:setShift(v) end },
          { name = "resonance", type = "f", min = 1.0, max = 20.0, default = 7.0, apply = function(e, v) e.node:setResonance(v) end },
          { name = "drive", type = "f", min = 0.5, max = 8.0, default = 1.4, apply = function(e, v) e.node:setDrive(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "eq",
        label = "EQ",
        create = function()
          local node = P.EQNode.new()
          node:setLowGain(6)
          node:setLowFreq(120)
          node:setMidGain(-4)
          node:setMidFreq(900)
          node:setMidQ(0.8)
          node:setHighGain(4)
          node:setHighFreq(8000)
          node:setOutput(0)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "low_gain", type = "f", min = -24.0, max = 24.0, default = 6.0, apply = function(e, v) e.node:setLowGain(v) end },
          { name = "low_freq", type = "f", min = 20.0, max = 400.0, default = 120.0, apply = function(e, v) e.node:setLowFreq(v) end },
          { name = "mid_gain", type = "f", min = -24.0, max = 24.0, default = -4.0, apply = function(e, v) e.node:setMidGain(v) end },
          { name = "mid_freq", type = "f", min = 120.0, max = 8000.0, default = 900.0, apply = function(e, v) e.node:setMidFreq(v) end },
          { name = "mid_q", type = "f", min = 0.2, max = 12.0, default = 0.8, apply = function(e, v) e.node:setMidQ(v) end },
          { name = "high_gain", type = "f", min = -24.0, max = 24.0, default = 4.0, apply = function(e, v) e.node:setHighGain(v) end },
          { name = "high_freq", type = "f", min = 2000.0, max = 16000.0, default = 8000.0, apply = function(e, v) e.node:setHighFreq(v) end },
          { name = "output", type = "f", min = -24.0, max = 24.0, default = 0.0, apply = function(e, v) e.node:setOutput(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "compressor",
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
        params = {
          { name = "threshold", type = "f", min = -60.0, max = 0.0, default = -18.0, apply = function(e, v) e.node:setThreshold(v) end },
          { name = "ratio", type = "f", min = 1.0, max = 20.0, default = 4.0, apply = function(e, v) e.node:setRatio(v) end },
          { name = "attack", type = "f", min = 0.1, max = 100.0, default = 5.0, apply = function(e, v) e.node:setAttack(v) end },
          { name = "release", type = "f", min = 1.0, max = 1000.0, default = 100.0, apply = function(e, v) e.node:setRelease(v) end },
          { name = "knee", type = "f", min = 0.0, max = 20.0, default = 6.0, apply = function(e, v) e.node:setKnee(v) end },
          { name = "makeup", type = "f", min = 0.0, max = 40.0, default = 0.0, apply = function(e, v) e.node:setMakeup(v) end },
          { name = "auto_makeup", type = "i", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setAutoMakeup(v > 0.5) end },
          { name = "mode", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setMode(v) end },
          { name = "detector", type = "i", min = 0.0, max = 1.0, default = 0.0, apply = function(e, v) e.node:setDetectorMode(v) end },
          { name = "sidechain_hpf", type = "f", min = 20.0, max = 1000.0, default = 100.0, apply = function(e, v) e.node:setSidechainHPF(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "limiter",
        label = "Limiter",
        create = function()
          local pre = P.GainNode.new(2)
          local node = P.LimiterNode.new()
          pre:setGain(1.0)
          node:setThreshold(-6)
          node:setRelease(80)
          node:setMakeup(0)
          node:setSoftClip(0.4)
          node:setMix(1.0)
          ctx.graph.connect(pre, node)
          return { input = pre, output = node, node = node, pre = pre }
        end,
        params = {
          { name = "threshold", type = "f", min = -24.0, max = 0.0, default = -6.0, apply = function(e, v) e.node:setThreshold(v) end },
          { name = "release", type = "f", min = 1.0, max = 500.0, default = 80.0, apply = function(e, v) e.node:setRelease(v) end },
          { name = "makeup", type = "f", min = 0.0, max = 18.0, default = 0.0, apply = function(e, v) e.node:setMakeup(v) end },
          { name = "soft", type = "f", min = 0.0, max = 1.0, default = 0.4, apply = function(e, v) e.node:setSoftClip(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
          { name = "pre_gain", type = "f", min = 0.0, max = 2.0, default = 1.0, apply = function(e, v) e.pre:setGain(v) end },
        },
      },
      {
        id = "transient",
        label = "Transient",
        create = function()
          local node = P.TransientShaperNode.new()
          node:setAttack(0.6)
          node:setSustain(-0.3)
          node:setSensitivity(1.2)
          node:setMix(1.0)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "attack", type = "f", min = -1.0, max = 1.0, default = 0.6, apply = function(e, v) e.node:setAttack(v) end },
          { name = "sustain", type = "f", min = -1.0, max = 1.0, default = -0.3, apply = function(e, v) e.node:setSustain(v) end },
          { name = "sensitivity", type = "f", min = 0.1, max = 4.0, default = 1.2, apply = function(e, v) e.node:setSensitivity(v) end },
          { name = "mix", type = "f", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMix(v) end },
        },
      },
      {
        id = "widener",
        label = "Widener",
        create = function()
          local node = P.StereoWidenerNode.new()
          node:setWidth(1.25)
          node:setMonoLowFreq(140)
          node:setMonoLowEnable(true)
          return { input = node, output = node, node = node }
        end,
        params = {
          { name = "width", type = "f", min = 0.0, max = 2.0, default = 1.25, apply = function(e, v) e.node:setWidth(v) end },
          { name = "monolowfreq", type = "f", min = 20.0, max = 500.0, default = 140.0, apply = function(e, v) e.node:setMonoLowFreq(v) end },
          { name = "monolowenable", type = "i", min = 0.0, max = 1.0, default = 1.0, apply = function(e, v) e.node:setMonoLowEnable(v > 0.5) end },
        },
      },
    }
  end

  local effectDefs = buildEffectDefs()

  local function applyEffectParam(param, effect, value)
    local ok = pcall(param.apply, effect, value)
    if ok then
      return true
    end

    if type(value) == "number" then
      local rounded = math.floor(value + 0.5)
      ok = pcall(param.apply, effect, rounded)
      if ok then
        return true
      end
      ok = pcall(param.apply, effect, rounded ~= 0)
      if ok then
        return true
      end
    end

    if type(value) == "boolean" then
      ok = pcall(param.apply, effect, value and 1 or 0)
      if ok then
        return true
      end
    end

    return false
  end

  local function createFxSlot(basePath)
    register(basePath .. "/select", { type = "f", min = 0.0, max = #effectDefs - 1, default = 0.0 })

    local slot = {
      effects = {},
      effectDefs = effectDefs,
      paramBindings = {},
      select = 0,
      output = nil,
    }

    local gatedOutputs = {}

    for idx, def in ipairs(effectDefs) do
      local effect = def.create()
      effect.id = def.id
      effect.label = def.label
      effect.def = def
      effect.gate = ctx.primitives.GainNode.new(2)
      effect.gate:setGain(idx == 1 and 1.0 or 0.0)
      ctx.graph.connect(effect.output, effect.gate)
      slot.effects[idx] = effect
      gatedOutputs[#gatedOutputs + 1] = effect.gate

      for _, param in ipairs(def.params) do
        local path = basePath .. "/" .. def.id .. "/" .. param.name
        register(path, {
          type = param.type or "f",
          min = param.min,
          max = param.max,
          default = param.default,
        })
        applyEffectParam(param, effect, param.default)
        slot.paramBindings[path] = function(value)
          return applyEffectParam(param, effect, value)
        end
      end
    end

    local effectMixer = ctx.primitives.MixerNode.new()
    effectMixer:setInputCount(#gatedOutputs)
    effectMixer:setMaster(1.0)
    for i = 1, #gatedOutputs do
      effectMixer:setGain(i, 1.0)
      effectMixer:setPan(i, 0.0)
      ctx.graph.connect(gatedOutputs[i], effectMixer, 0, i - 1)
    end
    slot.output = effectMixer

    slot.connectSource = function(source)
      if not source then return end
      for i = 1, #slot.effects do
        ctx.graph.connect(source, slot.effects[i].input)
      end
    end

    slot.applySelection = function()
      local selected = clamp(math.floor(slot.select + 0.5), 0, #slot.effects - 1)
      slot.select = selected
      for i = 1, #slot.effects do
        slot.effects[i].gate:setGain((i - 1) == selected and 1.0 or 0.0)
      end
    end

    slot.applyParam = function(path, value)
      if path == basePath .. "/select" then
        slot.select = value
        slot.applySelection()
        return true
      end
      local fn = slot.paramBindings[path]
      if fn then
        fn(value)
        return true
      end
      return false
    end

    slot.applySelection()
    return slot
  end

  -- Input-DSP source (mode 0 = MonitorControlled / always-on input-dsp feed)
  local hostInput = ctx.primitives.PassthroughNode.new(2, 0)
  local inputTrim = ctx.primitives.GainNode.new(2)
  inputTrim:setGain(1.0)
  ctx.graph.connect(hostInput, inputTrim)

  state.vocal = createFxSlot("/core/super/vocal/slot")
  state.vocal.connectSource(inputTrim)

  -- Input-DSP branch markings
  ctx.graph.markInput(hostInput)
  ctx.graph.markInput(inputTrim)
  ctx.graph.markInput(state.vocal.output)

  local layerMixer = ctx.primitives.MixerNode.new()
  layerMixer:setGain1(1.0)
  layerMixer:setGain2(1.0)
  layerMixer:setGain3(1.0)
  layerMixer:setGain4(1.0)
  layerMixer:setPan1(0.0)
  layerMixer:setPan2(0.0)
  layerMixer:setPan3(0.0)
  layerMixer:setPan4(0.0)
  layerMixer:setMaster(1.0)

  local layerCount = type(layers) == "table" and #layers or 0
  for i = 0, layerCount - 1 do
    local slot = createFxSlot("/core/super/layer/" .. tostring(i) .. "/fx")
    local layer = layers[i + 1]
    local parts = type(layer) == "table" and layer.parts or nil
    local layerOut = parts and parts.gain or layer
    local layerIn = parts and parts.input or nil

    if layerOut then
      slot.connectSource(layerOut)
      connectMixerInput(layerMixer, i + 1, slot.output)
    end

    if layerIn then
      ctx.graph.connect(state.vocal.output, layerIn)
    end

    state.layerFx[i + 1] = slot
  end

  local mainMixer = ctx.primitives.MixerNode.new()
  mainMixer:setGain1(1.0)
  mainMixer:setGain2(1.0)
  mainMixer:setGain3(0.0)
  mainMixer:setGain4(0.0)
  mainMixer:setPan1(0.0)
  mainMixer:setPan2(0.0)
  mainMixer:setPan3(0.0)
  mainMixer:setPan4(0.0)
  mainMixer:setMaster(1.0)

  -- Explicit monitor sink path for input-DSP signal
  local monitorTap = ctx.primitives.GainNode.new(2)
  monitorTap:setGain(1.0)

  local masterGain = ctx.primitives.GainNode.new(2)
  masterGain:setGain(1.0)

  ctx.graph.connect(layerMixer, mainMixer, 0, 0)
  ctx.graph.connect(state.vocal.output, monitorTap)
  ctx.graph.connect(monitorTap, mainMixer, 0, 1)
  ctx.graph.connect(mainMixer, masterGain)

  ctx.graph.markMonitor(monitorTap)
  ctx.graph.markOutput(layerMixer)
  ctx.graph.markOutput(mainMixer)
  ctx.graph.markOutput(masterGain)

  local extension = {}

  function extension.applyParam(path, value)
    path = normalizePath(path)
    if state.vocal.applyParam(path, value) then
      return true
    end
    for i = 1, #state.layerFx do
      if state.layerFx[i].applyParam(path, value) then
        return true
      end
    end
    return false
  end

  extension.state = state
  return extension
end

local M = {}

M.attach = attach

return M

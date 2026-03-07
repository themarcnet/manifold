-- MidiSynth_uiproject DSP entry
-- 8-voice polysynth with swappable FX, ADSR envelopes, filter, delay, reverb.
-- FX switching uses static parallel graph with mix-based selection (no rebuilds).

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

-- FX types: 0=Chorus, 1=Phaser, 2=WaveShaper, 3=Compressor, 4=StereoWidener
local FX_TYPES = { "Chorus", "Phaser", "WaveShaper", "Compressor", "StereoWidener" }

function buildPlugin(ctx)
  local voices = {}
  local mix = ctx.primitives.MixerNode.new()
  
  -- Filter (SVF)
  local filt = ctx.primitives.SVFNode.new()
  filt:setMode(0) -- Lowpass
  filt:setCutoff(3200)
  filt:setResonance(0.75)
  filt:setDrive(1.0)
  filt:setMix(1.0)
  
  local dist = ctx.primitives.DistortionNode.new()
  
  -- Create ALL FX nodes for both slots upfront (static graph)
  local fx1Nodes = {}
  local fx2Nodes = {}
  
  -- FX1 slot nodes
  fx1Nodes[1] = ctx.primitives.ChorusNode.new()
  fx1Nodes[1]:setRate(0.38)
  fx1Nodes[1]:setDepth(0.26)
  fx1Nodes[1]:setVoices(3)
  fx1Nodes[1]:setSpread(0.65)
  fx1Nodes[1]:setFeedback(0.08)
  fx1Nodes[1]:setWaveform(0)
  fx1Nodes[1]:setMix(0.0)
  
  fx1Nodes[2] = ctx.primitives.PhaserNode.new()
  fx1Nodes[2]:setRate(0.3)
  fx1Nodes[2]:setDepth(0.5)
  fx1Nodes[2]:setStages(4)
  fx1Nodes[2]:setFeedback(0.3)
  fx1Nodes[2]:setSpread(0.5)
  
  fx1Nodes[3] = ctx.primitives.WaveShaperNode.new()
  fx1Nodes[3]:setCurve(0)
  fx1Nodes[3]:setDrive(1.0)
  fx1Nodes[3]:setOutput(1.0)
  fx1Nodes[3]:setMix(0.0)
  
  fx1Nodes[4] = ctx.primitives.CompressorNode.new()
  fx1Nodes[4]:setThreshold(-12.0)
  fx1Nodes[4]:setRatio(4.0)
  fx1Nodes[4]:setAttack(10.0)
  fx1Nodes[4]:setRelease(100.0)
  fx1Nodes[4]:setMix(0.0)
  
  fx1Nodes[5] = ctx.primitives.StereoWidenerNode.new()
  fx1Nodes[5]:setWidth(1.5)
  fx1Nodes[5]:setMonoLowFreq(120.0)
  fx1Nodes[5]:setMonoLowEnable(true)
  
  -- FX2 slot nodes (same types, independent instances)
  fx2Nodes[1] = ctx.primitives.ChorusNode.new()
  fx2Nodes[1]:setRate(0.5)
  fx2Nodes[1]:setDepth(0.3)
  fx2Nodes[1]:setVoices(3)
  fx2Nodes[1]:setSpread(0.5)
  fx2Nodes[1]:setFeedback(0.1)
  fx2Nodes[1]:setWaveform(0)
  fx2Nodes[1]:setMix(0.0)
  
  fx2Nodes[2] = ctx.primitives.PhaserNode.new()
  fx2Nodes[2]:setRate(0.2)
  fx2Nodes[2]:setDepth(0.4)
  fx2Nodes[2]:setStages(6)
  fx2Nodes[2]:setFeedback(0.4)
  fx2Nodes[2]:setSpread(0.3)
  
  fx2Nodes[3] = ctx.primitives.WaveShaperNode.new()
  fx2Nodes[3]:setCurve(2)
  fx2Nodes[3]:setDrive(2.0)
  fx2Nodes[3]:setOutput(1.0)
  fx2Nodes[3]:setMix(0.0)
  
  fx2Nodes[4] = ctx.primitives.CompressorNode.new()
  fx2Nodes[4]:setThreshold(-20.0)
  fx2Nodes[4]:setRatio(2.0)
  fx2Nodes[4]:setAttack(5.0)
  fx2Nodes[4]:setRelease(50.0)
  fx2Nodes[4]:setMix(0.0)
  
  fx2Nodes[5] = ctx.primitives.StereoWidenerNode.new()
  fx2Nodes[5]:setWidth(2.0)
  fx2Nodes[5]:setMonoLowFreq(80.0)
  fx2Nodes[5]:setMonoLowEnable(true)
  
  local delay = ctx.primitives.StereoDelayNode.new()
  local reverb = ctx.primitives.ReverbNode.new()
  local spec = ctx.primitives.SpectrumAnalyzerNode.new()
  local out = ctx.primitives.GainNode.new(2)

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

  -- Build static parallel graph
  -- mix -> filt -> dist -> [all FX1 in parallel] -> [all FX2 in parallel] -> delay -> reverb -> spec -> out
  ctx.graph.connect(mix, filt)
  ctx.graph.connect(filt, dist)
  
  -- Connect dist to all FX1 nodes (parallel)
  for i = 1, #FX_TYPES do
    ctx.graph.connect(dist, fx1Nodes[i])
  end
  
  -- Connect each FX1 to all FX2 nodes (full mesh for flexibility)
  for i = 1, #FX_TYPES do
    for j = 1, #FX_TYPES do
      ctx.graph.connect(fx1Nodes[i], fx2Nodes[j])
    end
  end
  
  -- Connect all FX2 nodes to delay
  for j = 1, #FX_TYPES do
    ctx.graph.connect(fx2Nodes[j], delay)
  end
  
  ctx.graph.connect(delay, reverb)
  ctx.graph.connect(reverb, spec)
  ctx.graph.connect(spec, out)

  local params = {}
  local adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }
  local currentFx1Type = 0 -- Chorus default
  local currentFx2Type = 0 -- Chorus default

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

  -- FX1 params
  addParam(PATHS.fx1Type, {
    type = "f",
    min = 0.0,
    max = 4.0,
    default = 0.0,
    description = "FX1 type (0=Chorus, 1=Phaser, 2=WaveShaper, 3=Comp, 4=Widener)",
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
    description = "FX1 mix",
  })

  -- FX2 params
  addParam(PATHS.fx2Type, {
    type = "f",
    min = 0.0,
    max = 4.0,
    default = 0.0,
    description = "FX2 type (0=Chorus, 1=Phaser, 2=WaveShaper, 3=Comp, 4=Widener)",
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
    description = "FX2 mix",
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
    local waveform = math.max(0, math.min(4, math.floor((tonumber(value) or 0) + 0.5)))
    for i = 1, VOICE_COUNT do
      voices[i].osc:setWaveform(waveform)
    end
  end

  local function applyFilterType(value)
    local ftype = math.max(0, math.min(3, math.floor((tonumber(value) or 0) + 0.5)))
    filt:setMode(ftype)
  end

  -- FX selection via mix: selected FX gets user mix, others get 0
  local function applyFx1Selection(fxType, userMix)
    fxType = math.max(0, math.min(4, math.floor((tonumber(fxType) or 0) + 0.5)))
    userMix = tonumber(userMix) or 0
    currentFx1Type = fxType
    
    for i = 1, #FX_TYPES do
      local node = fx1Nodes[i]
      if i - 1 == fxType then
        -- Selected FX gets the user mix level
        if node.setMix then node:setMix(userMix) end
      else
        -- Unselected FX are muted
        if node.setMix then node:setMix(0.0) end
      end
    end
  end

  local function applyFx2Selection(fxType, userMix)
    fxType = math.max(0, math.min(4, math.floor((tonumber(fxType) or 0) + 0.5)))
    userMix = tonumber(userMix) or 0
    currentFx2Type = fxType
    
    for i = 1, #FX_TYPES do
      local node = fx2Nodes[i]
      if i - 1 == fxType then
        if node.setMix then node:setMix(userMix) end
      else
        if node.setMix then node:setMix(0.0) end
      end
    end
  end

  local function updateFx1Params(p1, p2, mixVal)
    local node = fx1Nodes[currentFx1Type + 1]
    if not node then return end
    
    local ftype = currentFx1Type
    if ftype == 0 then -- Chorus
      node:setRate(0.1 + p1 * 2.0)
      node:setDepth(p2)
      node:setMix(mixVal)
    elseif ftype == 1 then -- Phaser
      node:setRate(0.1 + p1 * 2.0)
      node:setDepth(p2)
    elseif ftype == 2 then -- WaveShaper
      node:setDrive(0.5 + p1 * 5.0)
      node:setMix(mixVal)
    elseif ftype == 3 then -- Compressor
      node:setThreshold(-30.0 + p1 * 20.0)
      node:setRatio(1.0 + p2 * 10.0)
    elseif ftype == 4 then -- StereoWidener
      node:setWidth(0.5 + p1 * 2.0)
    end
  end

  local function updateFx2Params(p1, p2, mixVal)
    local node = fx2Nodes[currentFx2Type + 1]
    if not node then return end
    
    local ftype = currentFx2Type
    if ftype == 0 then -- Chorus
      node:setRate(0.1 + p1 * 2.0)
      node:setDepth(p2)
      node:setMix(mixVal)
    elseif ftype == 1 then -- Phaser
      node:setRate(0.1 + p1 * 2.0)
      node:setDepth(p2)
    elseif ftype == 2 then -- WaveShaper
      node:setDrive(0.5 + p1 * 5.0)
      node:setMix(mixVal)
    elseif ftype == 3 then -- Compressor
      node:setThreshold(-30.0 + p1 * 20.0)
      node:setRatio(1.0 + p2 * 10.0)
    elseif ftype == 4 then -- StereoWidener
      node:setWidth(0.5 + p1 * 2.0)
    end
  end

  applyWaveform(1)
  applyFx1Selection(0, 0.0) -- Start with Chorus at 0 mix
  applyFx2Selection(0, 0.0) -- Start with Chorus at 0 mix

  return {
    description = "Eight-voice polysynth with swappable FX, ADSR, filter, delay and reverb",
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
        -- Get current mix to apply to new selection
        -- Mix is stored in the node already, just reapply selection
        applyFx1Selection(value, nil)
      elseif path == PATHS.fx1Mix then
        updateFx1Params(nil, nil, tonumber(value) or 0)
      elseif path == PATHS.fx1Param1 or path == PATHS.fx1Param2 then
        -- Params update happens in real-time, need current values
        -- The behavior will send these together
      elseif path == PATHS.fx2Type then
        applyFx2Selection(value, nil)
      elseif path == PATHS.fx2Mix then
        updateFx2Params(nil, nil, tonumber(value) or 0)
      end
    end,
  }
end

return buildPlugin

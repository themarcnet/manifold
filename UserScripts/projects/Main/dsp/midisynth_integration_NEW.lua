-- MidiSynth Integration Module for Main
-- Simplified version using LoopPlaybackNode's new loopStart/loopEnd/crossfade features

local M = {}

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

  -- Sample synth mode
  oscMode = "/midi/synth/osc/mode",
  sampleSource = "/midi/synth/sample/source",
  sampleCaptureTrigger = "/midi/synth/sample/captureTrigger",
  sampleCaptureBars = "/midi/synth/sample/captureBars",
  sampleRootNote = "/midi/synth/sample/rootNote",
  samplePlayStart = "/midi/synth/sample/playStart",
  sampleLoopStart = "/midi/synth/sample/loopStart",
  sampleLoopEnd = "/midi/synth/sample/loopEnd",
  sampleCrossfade = "/midi/synth/sample/crossfade",
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
  local delay = ctx.primitives.StereoDelayNode.new()
  local reverb = ctx.primitives.ReverbNode.new()
  local spec = ctx.primitives.SpectrumAnalyzerNode.new()
  local out = ctx.primitives.GainNode.new(2)

  -- Sample mode state
  local sampleSource = 0
  local sampleCaptureBars = 1.0
  local sampleRootNote = 60.0
  local samplePlayStart = 0.0
  local sampleLoopStart = 0.0
  local sampleLoopEnd = 1.0
  local sampleCrossfade = 0  -- 0 = no crossfade

  local function connectMixerInput(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    ctx.graph.connect(source, mixer, 0, inputIndex - 1)
  end

  -- Capture sources for sample mode.
  -- 0 = live input, 1..4 = looper layers 1..4.
  local sampleSources = {}
  local function registerSampleSource(sourceId, sourceName, sourceNode)
    if not sourceNode then
      return
    end
    local inputGain = ctx.primitives.GainNode.new(2)
    inputGain:setGain(4.0)
    ctx.graph.connect(sourceNode, inputGain)
    local capture = ctx.primitives.RetrospectiveCaptureNode.new(2)
    capture:setCaptureSeconds(30.0)
    ctx.graph.connect(inputGain, capture)
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

  -- Live source
  local liveSampleInput = ctx.primitives.PassthroughNode.new(2, 0)
  registerSampleSource(0, "live", liveSampleInput)

  for i = 1, 4 do
    registerSampleSource(i, "layer" .. tostring(i), layerSourceNodes[i])
  end

  mix:setInputCount(VOICE_COUNT)

  for i = 1, VOICE_COUNT do
    local osc = ctx.primitives.OscillatorNode.new()
    osc:setWaveform(1)
    osc:setFrequency(220.0)
    osc:setAmplitude(0.0)

    local noiseGain = ctx.primitives.GainNode.new(2)
    noiseGain:setGain(0.0)

    local samplePlayback = ctx.primitives.LoopPlaybackNode.new(2)
    samplePlayback:setLoopLength(1)
    samplePlayback:setLoopStart(0)
    samplePlayback:setLoopEnd(-1)  -- Use full length
    samplePlayback:setLoopCrossfade(0)  -- No crossfade by default
    samplePlayback:setSpeed(1.0)
    samplePlayback:stop()

    local sampleGain = ctx.primitives.GainNode.new(2)
    sampleGain:setGain(0.0)

    local voiceMix = ctx.primitives.MixerNode.new()
    voiceMix:setInputCount(3)
    voiceMix:setGain(1, 1.0); voiceMix:setPan(1, 0.0)
    voiceMix:setGain(2, 1.0); voiceMix:setPan(2, 0.0)
    voiceMix:setGain(3, 1.0); voiceMix:setPan(3, 0.0)

    ctx.graph.connect(osc, voiceMix, 0, 0)
    ctx.graph.connect(noiseGen, noiseGain)
    ctx.graph.connect(noiseGain, voiceMix, 0, 1)
    ctx.graph.connect(samplePlayback, sampleGain)
    ctx.graph.connect(sampleGain, voiceMix, 0, 2)
    ctx.graph.connect(voiceMix, mix, 0, i - 1)

    voices[i] = {
      osc = osc,
      noiseGain = noiseGain,
      samplePlayback = samplePlayback,
      sampleGain = sampleGain,
      gate = 0.0,
      targetAmp = 0.0,
      currentAmp = 0.0,
      freq = 220.0,
      amp = 0.0,
      sampleCapturedLength = 0,
      isFirstTrigger = true,
    }
  end

  -- Signal chain defaults
  dist:setDrive(1.8); dist:setMix(0.14); dist:setOutput(0.9)
  delay:setTempo(120); delay:setTimeMode(0); delay:setTimeL(220); delay:setTimeR(330)
  delay:setFeedback(0.24); delay:setFeedbackCrossfeed(0.12); delay:setFilterEnabled(true)
  delay:setFilterCutoff(4200); delay:setFilterResonance(0.5); delay:setMix(0.0)
  delay:setPingPong(true); delay:setWidth(0.8); delay:setFreeze(false); delay:setDucking(0.0)
  reverb:setRoomSize(0.52); reverb:setDamping(0.4)
  reverb:setWetLevel(0.0); reverb:setDryLevel(1.0); reverb:setWidth(1.0)
  spec:setSensitivity(1.2); spec:setSmoothing(0.86); spec:setFloor(-72)
  out:setGain(0.8)

  ctx.graph.connect(mix, filt)
  ctx.graph.connect(filt, dist)
  ctx.graph.connect(dist, delay)
  ctx.graph.connect(delay, reverb)
  ctx.graph.connect(reverb, spec)
  ctx.graph.connect(spec, out)

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

  for i = 1, VOICE_COUNT do
    addParam(voiceFreqPath(i), { type = "f", min = 20, max = 8000, default = 220, description = "Voice frequency " .. i })
    ctx.params.bind(voiceFreqPath(i), voices[i].osc, "setFrequency")
    addParam(voiceAmpPath(i), { type = "f", min = 0, max = 0.5, default = 0, description = "Voice amplitude " .. i })
    ctx.params.bind(voiceAmpPath(i), voices[i].osc, "setAmplitude")
    addParam(voiceGatePath(i), { type = "f", min = 0, max = 1, default = 0, description = "Voice gate " .. i })
  end

  addParam(PATHS.waveform, { type = "f", min = 0, max = 4, default = 1, description = "Oscillator waveform" })
  addParam(PATHS.cutoff, { type = "f", min = 80, max = 16000, default = 3200, description = "Filter cutoff" })
  ctx.params.bind(PATHS.cutoff, filt, "setCutoff")
  addParam(PATHS.resonance, { type = "f", min = 0.1, max = 2, default = 0.75, description = "Filter resonance" })
  ctx.params.bind(PATHS.resonance, filt, "setResonance")
  addParam(PATHS.drive, { type = "f", min = 0, max = 20, default = 1.8, description = "Drive amount" })
  ctx.params.bind(PATHS.drive, dist, "setDrive")
  addParam(PATHS.output, { type = "f", min = 0, max = 1, default = 0.8, description = "Output gain" })
  ctx.params.bind(PATHS.output, out, "setGain")
  addParam(PATHS.attack, { type = "f", min = 0.001, max = 5, default = 0.05, description = "ADSR attack" })
  addParam(PATHS.decay, { type = "f", min = 0.001, max = 5, default = 0.2, description = "ADSR decay" })
  addParam(PATHS.sustain, { type = "f", min = 0, max = 1, default = 0.7, description = "ADSR sustain" })
  addParam(PATHS.release, { type = "f", min = 0.001, max = 10, default = 0.4, description = "ADSR release" })
  addParam(PATHS.noiseLevel, { type = "f", min = 0, max = 1, default = 0, description = "Noise level" })
  addParam(PATHS.noiseColor, { type = "f", min = 0, max = 1, default = 0.1, description = "Noise color" })
  ctx.params.bind(PATHS.noiseColor, noiseGen, "setColor")

  -- Sample mode params
  addParam(PATHS.oscMode, { type = "f", min = 0, max = 1, default = 0, description = "Osc mode (0=classic, 1=sample)" })
  addParam(PATHS.sampleSource, { type = "f", min = 0, max = 4, default = 0, description = "Sample source (0=live, 1-4=layers)" })
  addParam(PATHS.sampleCaptureTrigger, { type = "f", min = 0, max = 1, default = 0, description = "Trigger sample capture" })
  addParam(PATHS.sampleCaptureBars, { type = "f", min = 0.0625, max = 16, default = 1.0, description = "Capture length in bars" })
  addParam(PATHS.sampleRootNote, { type = "f", min = 12, max = 96, default = 60, description = "Sample root MIDI note" })
  addParam(PATHS.samplePlayStart, { type = "f", min = 0, max = 0.99, default = 0, description = "Play start position (yellow)" })
  addParam(PATHS.sampleLoopStart, { type = "f", min = 0, max = 0.99, default = 0, description = "Loop start position (green)" })
  addParam(PATHS.sampleLoopEnd, { type = "f", min = 0.01, max = 1, default = 1, description = "Loop end position (red)" })
  addParam(PATHS.sampleCrossfade, { type = "f", min = 0, max = 44100, default = 0, description = "Loop crossfade in samples" })

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

  local function selectedSampleSourceCapture()
    local src = sampleSources[sampleSource]
    if src and src.capture and src.capture.__node then
      return src.capture.__node
    end
    local fallback = sampleSources[0]
    if fallback and fallback.capture and fallback.capture.__node then
      return fallback.capture.__node
    end
    return nil
  end

  local function applyLoopSettings(voice)
    if not voice or not voice.samplePlayback then
      return
    end
    local capturedLength = tonumber(voice.sampleCapturedLength) or voice.samplePlayback:getLoopLength() or 1
    if capturedLength <= 0 then
      return
    end
    
    -- Convert normalized positions to absolute samples
    local playStartAbs = math.floor(capturedLength * samplePlayStart)
    local loopStartAbs = math.floor(capturedLength * sampleLoopStart)
    local loopEndAbs = math.floor(capturedLength * sampleLoopEnd)
    
    -- Ensure valid ranges
    if loopEndAbs <= loopStartAbs then
      loopEndAbs = loopStartAbs + 1
    end
    if loopEndAbs > capturedLength then
      loopEndAbs = capturedLength
    end
    if playStartAbs >= capturedLength then
      playStartAbs = capturedLength - 1
    end
    
    voice.samplePlayback:setLoopLength(capturedLength)
    voice.samplePlayback:setLoopStart(loopStartAbs)
    voice.samplePlayback:setLoopEnd(loopEndAbs)
    voice.samplePlayback:setLoopCrossfade(math.floor(sampleCrossfade))
  end

  local function applyVoiceFrequency(voiceIndex, frequency)
    local voice = voices[voiceIndex]
    if not voice then
      return
    end
    local f = clamp(tonumber(frequency) or 220.0, 20.0, 8000.0)
    voice.freq = f
    if voice.osc then
      voice.osc:setFrequency(f)
    end
    -- Sample mode pitch tracking would go here if needed
  end

  local function applyVoiceGate(voiceIndex, gateValue)
    local voice = voices[voiceIndex]
    if not voice then
      return
    end

    local g = (tonumber(gateValue) or 0.0) > 0.5 and 1.0 or 0.0
    voice.gate = g

    if g > 0.5 then
      if voice.isFirstTrigger then
        -- First play: seek to playStart
        local capturedLength = voice.sampleCapturedLength or voice.samplePlayback:getLoopLength() or 1
        local playStartAbs = math.floor(capturedLength * samplePlayStart)
        voice.samplePlayback:seekAbsolute(playStartAbs)
        voice.isFirstTrigger = false
      end
      voice.samplePlayback:play()
    else
      voice.samplePlayback:stop()
      voice.isFirstTrigger = true
    end
  end

  local function captureSampleFromCurrentSource()
    local captureNode = selectedSampleSourceCapture()
    if not captureNode then
      return false
    end

    local samplesBack = math.max(1, math.floor(sampleCaptureBars * hostSamplesPerBar() + 0.5))
    local copiedAny = false

    for i = 1, VOICE_COUNT do
      local voice = voices[i]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node
      if playbackNode then
        local ok, copied = pcall(function()
          return captureNode:copyRecentToLoop(playbackNode, samplesBack, false)
        end)
        if ok and copied then
          copiedAny = true
          voice.sampleCapturedLength = voice.samplePlayback:getLoopLength() or 0
          applyLoopSettings(voice)
          voice.samplePlayback:seekAbsolute(math.floor(voice.sampleCapturedLength * samplePlayStart))
          voice.isFirstTrigger = true
          if voice.gate > 0.5 then
            voice.samplePlayback:play()
          else
            voice.samplePlayback:stop()
          end
        end
      end
    end

    return copiedAny
  end

  local function applyWaveform(value)
    local wf = math.max(0, math.min(4, math.floor((tonumber(value) or 0) + 0.5)))
    for i = 1, VOICE_COUNT do
      voices[i].osc:setWaveform(wf)
    end
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

      if path == PATHS.waveform then
        applyWaveform(value)
      elseif path == PATHS.sampleSource then
        sampleSource = math.max(0, math.min(4, math.floor((tonumber(value) or 0) + 0.5)))
      elseif path == PATHS.sampleCaptureBars then
        sampleCaptureBars = clamp(tonumber(value) or 1.0, 0.0625, 16.0)
      elseif path == PATHS.sampleRootNote then
        sampleRootNote = clamp(tonumber(value) or 60.0, 12.0, 96.0)
      elseif path == PATHS.samplePlayStart then
        samplePlayStart = clamp01(tonumber(value) or 0.0)
      elseif path == PATHS.sampleLoopStart then
        sampleLoopStart = clamp01(tonumber(value) or 0.0)
        for i = 1, VOICE_COUNT do
          applyLoopSettings(voices[i])
        end
      elseif path == PATHS.sampleLoopEnd then
        sampleLoopEnd = clamp(tonumber(value) or 1.0, 0.01, 1.0)
        for i = 1, VOICE_COUNT do
          applyLoopSettings(voices[i])
        end
      elseif path == PATHS.sampleCrossfade then
        sampleCrossfade = math.max(0, tonumber(value) or 0)
        for i = 1, VOICE_COUNT do
          applyLoopSettings(voices[i])
        end
      elseif path == PATHS.sampleCaptureTrigger then
        if (tonumber(value) or 0.0) > 0.5 then
          captureSampleFromCurrentSource()
        end
      end
    end,

    getSamplePeaks = function(numBuckets)
      numBuckets = numBuckets or 100
      local voice = voices[1]
      if not voice or not voice.samplePlayback then
        return nil
      end
      local node = voice.samplePlayback.__node
      if not node then
        return nil
      end
      if type(getLoopPlaybackPeaks) == "function" then
        return getLoopPlaybackPeaks(node, numBuckets)
      end
      return nil
    end,

    getSampleLoopLength = function()
      local voice = voices[1]
      if voice and voice.samplePlayback then
        return voice.samplePlayback:getLoopLength()
      end
      return 0
    end,

    getVoiceSamplePositions = function()
      local positions = {}
      for i = 1, VOICE_COUNT do
        local voice = voices[i]
        if voice and voice.samplePlayback and voice.amp > 0.0001 then
          positions[i] = voice.samplePlayback:getNormalizedPosition() or 0
        else
          positions[i] = 0
        end
      end
      return positions
    end,
  }
end

return M

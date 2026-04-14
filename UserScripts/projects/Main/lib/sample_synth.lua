-- SampleSynth Module
-- Sample-based instrument with blend modes and spectral analysis

local Utils = require("utils")

local M = {}

function M.create(ctx, options)
  options = options or {}

  -- Sample capture sources are project-configured and injected as generic specs.
  local sampleSources = {}
  local sampleSourceOrder = {}
  local defaultSourceId = tonumber(options.defaultSourceId)

  -- Sample state
  local sampleSource = defaultSourceId or 0
  local sampleCaptureBars = 1.0
  local sampleCaptureMode = 0
  local sampleCaptureStartOffset = 0
  local sampleCaptureRecording = false
  local sampleCaptureRecordingSourceId = nil
  local sampleCaptureRecordingStartOffset = 0
  local lastCapturedLengthMs = 0

  -- Helper to get samples per bar from host
  local function hostSamplesPerBar()
    if ctx.host and ctx.host.getParam then
      local spb = tonumber(ctx.host.getParam("/core/behavior/samplesPerBar")) or 0
      if spb > 0 then return spb end
    end
    local sr = (ctx.host and ctx.host.getSampleRate and tonumber(ctx.host.getSampleRate())) or 44100.0
    local tempo = (ctx.host and ctx.host.getParam and tonumber(ctx.host.getParam("/core/behavior/tempo"))) or 120.0
    if sr <= 0 then sr = 44100.0 end
    if tempo <= 0 then tempo = 120.0 end
    return (sr * 240.0) / tempo
  end

  -- Register a sample source
  local function registerSampleSource(sourceId, sourceName, sourceNode, sourceMeta)
    if not sourceNode then return end

    local numericId = math.floor(tonumber(sourceId) or 0)
    local inputGain = ctx.primitives.GainNode.new(2)
    inputGain:setGain(4.0)
    ctx.graph.connect(sourceNode, inputGain)

    local capture = ctx.primitives.RetrospectiveCaptureNode.new(2)
    capture:setCaptureSeconds(30.0)
    ctx.graph.connect(inputGain, capture)

    local nullSink = ctx.primitives.GainNode.new(2)
    nullSink:setGain(0.0)
    ctx.graph.connect(capture, nullSink)

    if not sampleSources[numericId] then
      sampleSourceOrder[#sampleSourceOrder + 1] = numericId
      table.sort(sampleSourceOrder)
    end

    local entry = {
      id = numericId,
      name = sourceName or ("source" .. tostring(numericId)),
      capture = capture,
      inputGain = inputGain,
    }
    if type(sourceMeta) == "table" then
      for k, v in pairs(sourceMeta) do
        entry[k] = v
      end
    end

    sampleSources[numericId] = entry
    if defaultSourceId == nil then
      defaultSourceId = numericId
    end
  end

  local function registerSampleSourceSpec(spec)
    if type(spec) ~= "table" then
      return
    end
    registerSampleSource(spec.id, spec.name, spec.node, spec)
  end

  if type(options.sourceSpecs) == "table" then
    for i = 1, #options.sourceSpecs do
      registerSampleSourceSpec(options.sourceSpecs[i])
    end
  end

  local function getDefaultSourceEntry()
    if defaultSourceId ~= nil then
      local entry = sampleSources[defaultSourceId]
      if entry and entry.capture and entry.capture.__node then
        return entry
      end
    end
    for i = 1, #sampleSourceOrder do
      local entry = sampleSources[sampleSourceOrder[i]]
      if entry and entry.capture and entry.capture.__node then
        return entry
      end
    end
    return nil
  end

  local function getSourceEntryById(sourceId)
    local numericId = math.floor(tonumber(sourceId) or -1)
    local entry = sampleSources[numericId]
    if entry and entry.capture and entry.capture.__node then
      return entry
    end
    return nil
  end

  -- Get selected source entry
  local function getSelectedSourceEntry()
    local src = sampleSources[sampleSource]
    if src and src.capture and src.capture.__node then
      return src
    end
    return getDefaultSourceEntry()
  end

  -- Get capture node from selected source
  local function getSelectedSourceCapture()
    local entry = getSelectedSourceEntry()
    return entry and entry.capture and entry.capture.__node or nil
  end

  -- Get write offset for UI
  local function getSelectedSourceWriteOffset()
    local capture = getSelectedSourceCapture()
    if capture then
      return capture:getWriteOffset()
    end
    return 0
  end

  local function normalizeWriteOffset(value)
    return math.max(0, math.floor(tonumber(value) or 0))
  end

  local function clearCaptureRecording(resetStartOffset)
    sampleCaptureRecording = false
    sampleCaptureRecordingSourceId = nil
    sampleCaptureRecordingStartOffset = 0
    if resetStartOffset ~= false then
      sampleCaptureStartOffset = 0
    end
  end

  local function buildCaptureRequest(entry, samplesBack, extra)
    local captureNode = entry and entry.capture and entry.capture.__node or nil
    if not captureNode then
      return nil
    end
    local request = {
      sourceEntry = entry,
      captureNode = captureNode,
      samplesBack = math.max(1, math.floor(tonumber(samplesBack) or 0)),
    }
    if type(extra) == "table" then
      for key, value in pairs(extra) do
        request[key] = value
      end
    end
    return request
  end

  local function buildRetroCaptureRequest()
    local entry = getSelectedSourceEntry()
    if not entry then
      return nil
    end
    local samplesBack = math.max(1, math.floor(hostSamplesPerBar() * sampleCaptureBars + 0.5))
    return buildCaptureRequest(entry, samplesBack, { mode = "retro" })
  end

  local function buildFreeCaptureRequestFromOffset(entry, startOffset)
    local captureNode = entry and entry.capture and entry.capture.__node or nil
    if not captureNode then
      return nil
    end
    local currentOffset = normalizeWriteOffset(captureNode:getWriteOffset())
    local normalizedStart = normalizeWriteOffset(startOffset)
    local duration = currentOffset - normalizedStart
    if duration < 0 then
      duration = duration + math.max(1, normalizeWriteOffset(captureNode:getCaptureSize()))
    end
    local samplesBack = math.max(1, math.floor(duration))
    return buildCaptureRequest(entry, samplesBack, {
      mode = "free",
      startOffset = normalizedStart,
      endOffset = currentOffset,
    })
  end

  local function buildManualFreeCaptureRequest()
    local entry = getSelectedSourceEntry()
    if not entry then
      return nil
    end
    local explicitStartOffset = math.floor(sampleCaptureStartOffset or 0)
    if explicitStartOffset < 0 then
      return buildCaptureRequest(entry, math.abs(explicitStartOffset), {
        mode = "free",
        startOffset = explicitStartOffset,
      })
    end
    return buildFreeCaptureRequestFromOffset(entry, explicitStartOffset)
  end

  local function beginFreeCapture()
    local entry = getSelectedSourceEntry()
    local captureNode = entry and entry.capture and entry.capture.__node or nil
    if not captureNode then
      return false
    end
    local startOffset = normalizeWriteOffset(captureNode:getWriteOffset())
    sampleCaptureRecording = true
    sampleCaptureRecordingSourceId = entry.id
    sampleCaptureRecordingStartOffset = startOffset
    sampleCaptureStartOffset = startOffset
    return true
  end

  local function finishFreeCapture()
    local entry = getSourceEntryById(sampleCaptureRecordingSourceId) or getSelectedSourceEntry()
    if not entry then
      clearCaptureRecording(true)
      return nil
    end
    local request = buildFreeCaptureRequestFromOffset(entry, sampleCaptureRecordingStartOffset)
    clearCaptureRecording(true)
    return request
  end

  local function setCaptureRecording(recording)
    local wantRecording = recording == true or (tonumber(recording) or 0) > 0.5
    if sampleCaptureMode ~= 1 then
      if not wantRecording then
        clearCaptureRecording(true)
      end
      return nil
    end
    if wantRecording then
      if not sampleCaptureRecording then
        beginFreeCapture()
      end
      return nil
    end
    if sampleCaptureRecording then
      return finishFreeCapture()
    end
    return nil
  end

  local function triggerCapture()
    if sampleCaptureMode == 1 then
      if sampleCaptureRecording then
        return finishFreeCapture()
      end
      if math.floor(sampleCaptureStartOffset or 0) ~= 0 then
        local request = buildManualFreeCaptureRequest()
        sampleCaptureStartOffset = 0
        return request
      end
      beginFreeCapture()
      return nil
    end
    return buildRetroCaptureRequest()
  end

  -- Trigger capture
  local function capture(bars, mode, startOffset)
    mode = mode or 0
    startOffset = startOffset or 0
    local src = getSelectedSourceEntry()
    if not src then
      print("DSP ERROR: No sample source available for capture")
      return false
    end
    local samplesPerBar = hostSamplesPerBar()
    local captureSamples = math.floor(samplesPerBar * (bars or sampleCaptureBars))
    if mode == 1 and startOffset > 0 then
      src.capture:setFreeCaptureStartOffset(startOffset)
    else
      src.capture:setFreeCaptureStartOffset(0)
    end
    src.capture:captureNow(captureSamples)
    return true
  end

  -- Analysis state
  local analysisPending = false
  local analysisInFlight = false
  local latestAnalysis = nil
  local latestPartials = nil
  local latestTemporal = nil

  -- Request async analysis (to be called after capture)
  local function requestAnalysis(playbackNode)
    if analysisInFlight then
      return false
    end
    if not playbackNode or type(_G.requestSampleRegionPlaybackAsyncAnalysis) ~= "function" then
      return false
    end
    local ok, err = pcall(function()
      _G.requestSampleRegionPlaybackAsyncAnalysis(playbackNode, 32, 1024, 256, 256)
    end)
    if ok then
      analysisPending = false
      analysisInFlight = true
      return true
    else
      print("SampleSynth: Failed to queue analysis: " .. tostring(err))
      return false
    end
  end

  -- Poll async analysis completion
  -- Returns: isComplete, analysisResult, partialsResult, temporalResult
  local function pollAnalysis(playbackNode)
    if not analysisInFlight then
      return false, latestAnalysis, latestPartials, latestTemporal
    end
    if not playbackNode or type(_G.isSampleRegionPlaybackAnalysisPending) ~= "function" then
      analysisInFlight = false
      return false, latestAnalysis, latestPartials, latestTemporal
    end
    local okPending, pending = pcall(function()
      return _G.isSampleRegionPlaybackAnalysisPending(playbackNode)
    end)
    if not okPending or pending == true then
      return false, latestAnalysis, latestPartials, latestTemporal
    end
    analysisInFlight = false
    local okA, analysis = pcall(function() return _G.getSampleRegionPlaybackLastAnalysis(playbackNode) end)
    local okP, partials = pcall(function() return _G.getSampleRegionPlaybackPartials(playbackNode) end)
    local okT, temporal = pcall(function() return _G.getSampleRegionPlaybackTemporalPartials(playbackNode) end)
    if okA and type(analysis) == "table" then
      latestAnalysis = analysis
    end
    if okP and type(partials) == "table" then
      latestPartials = partials
    end
    if okT and type(temporal) == "table" then
      latestTemporal = temporal
    end
    return true, latestAnalysis, latestPartials, latestTemporal
  end

  -- Get last analysis results (without polling)
  local function getLastAnalysis()
    return latestAnalysis
  end
  local function getLastPartials()
    return latestPartials
  end
  local function getLastTemporal()
    return latestTemporal
  end

  -- Check if analysis is currently in flight
  local function isAnalysisInFlight()
    return analysisInFlight
  end

  -- Reset analysis state (e.g., after new capture)
  local function resetAnalysisState()
    analysisPending = false
    analysisInFlight = false
  end

  local function createVoiceGraph(index, options)
    options = options or {}

    local mixBus = options.mixBus
    local noiseSource = options.noiseSource
    local oscRenderStandard = tonumber(options.oscRenderStandard) or 0
    local oscRenderAdd = tonumber(options.oscRenderAdd) or 1
    local addFlavorSelf = tonumber(options.addFlavorSelf) or 0

    local osc = ctx.primitives.OscillatorNode.new()
    osc:setWaveform(1)
    osc:setFrequency(220.0)
    osc:setAmplitude(0.0)
    osc:setDrive(0.0)
    osc:setDriveShape(0)
    osc:setDriveBias(0.0)
    osc:setDriveMix(1.0)
    osc:setRenderMode(oscRenderStandard)
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
    if index == 1 and ctx.graph and ctx.graph.nameNode then
      ctx.graph.nameNode(samplePlayback, "/midi/synth/sample/playback")
    end

    local samplePhaseVocoder = ctx.primitives.PhaseVocoderNode.new(2)
    samplePhaseVocoder:setPitchSemitones(0.0)
    samplePhaseVocoder:setTimeStretch(1.0)
    samplePhaseVocoder:setMix(0.0)
    samplePhaseVocoder:setFFTOrder(11)
    samplePhaseVocoder:reset()

    local sampleEnvFollower = ctx.primitives.EnvelopeFollowerNode.new()
    sampleEnvFollower:setAttack(5.0)
    sampleEnvFollower:setRelease(80.0)
    sampleEnvFollower:setSensitivity(2.0)
    sampleEnvFollower:setHighpass(40.0)
    sampleEnvFollower:setMode(0)

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
    if sampleAdditive.setSpectralMode then sampleAdditive:setSpectralMode(0) end
    if sampleAdditive.setSpectralWaveform then sampleAdditive:setSpectralWaveform(1) end
    if sampleAdditive.setSpectralPulseWidth then sampleAdditive:setSpectralPulseWidth(0.5) end
    if sampleAdditive.setSpectralAdditivePartials then sampleAdditive:setSpectralAdditivePartials(8) end
    if sampleAdditive.setSpectralAdditiveTilt then sampleAdditive:setSpectralAdditiveTilt(0.0) end
    if sampleAdditive.setSpectralAdditiveDrift then sampleAdditive:setSpectralAdditiveDrift(0.0) end
    if sampleAdditive.setSpectralMorphAmount then sampleAdditive:setSpectralMorphAmount(0.5) end
    if sampleAdditive.setSpectralMorphDepth then sampleAdditive:setSpectralMorphDepth(0.5) end
    if sampleAdditive.setSpectralMorphCurve then sampleAdditive:setSpectralMorphCurve(2) end
    if sampleAdditive.setSpectralTemporalSpeed then sampleAdditive:setSpectralTemporalSpeed(1.0) end
    if sampleAdditive.setSpectralTemporalSmooth then sampleAdditive:setSpectralTemporalSmooth(0.0) end
    if sampleAdditive.setSpectralTemporalContrast then sampleAdditive:setSpectralTemporalContrast(0.5) end
    if sampleAdditive.setSpectralStretch then sampleAdditive:setSpectralStretch(0.0) end
    if sampleAdditive.setSpectralTiltMode then sampleAdditive:setSpectralTiltMode(0) end
    if sampleAdditive.setSpectralAddFlavor then sampleAdditive:setSpectralAddFlavor(addFlavorSelf) end

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
    blendAddOsc:setRenderMode(oscRenderAdd)
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

    local addPhraseGain = ctx.primitives.GainNode.new(2)
    addPhraseGain:setGain(1.0)

    local addBranchGain = ctx.primitives.GainNode.new(2)
    addBranchGain:setGain(0.0)

    local mixCrossfade = ctx.primitives.CrossfaderNode.new()
    mixCrossfade:setPosition(0.0)
    mixCrossfade:setCurve(1.0)
    mixCrossfade:setMix(1.0)

    local directionCrossfade = ctx.primitives.CrossfaderNode.new()
    directionCrossfade:setPosition(0.0)
    directionCrossfade:setCurve(1.0)
    directionCrossfade:setMix(1.0)

    local basePathSelect = ctx.primitives.CrossfaderNode.new()
    basePathSelect:setPosition(-1.0)
    basePathSelect:setCurve(1.0)
    basePathSelect:setMix(1.0)

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

    if noiseSource then
      ctx.graph.connect(noiseSource, noiseGain)
    end
    ctx.graph.connect(samplePlayback, samplePhaseVocoder)
    ctx.graph.connect(samplePhaseVocoder, sampleGain)
    ctx.graph.connect(samplePhaseVocoder, sampleBlendGain)
    ctx.graph.connect(samplePlayback, sampleEnvFollower)
    local envFollowerSink = ctx.primitives.GainNode.new(2)
    envFollowerSink:setGain(0.0)
    ctx.graph.connect(sampleEnvFollower, envFollowerSink)
    ctx.graph.connect(sampleAdditive, sampleAdditiveGain)
    ctx.graph.connect(morphWaveAdditive, morphWaveAdditiveGain)
    ctx.graph.connect(samplePlayback, osc, 0, 0)
    ctx.graph.connect(osc, mixCrossfade, 0, 0)
    ctx.graph.connect(sampleBlendGain, mixCrossfade, 0, 2)
    ctx.graph.connect(osc, directionCrossfade, 0, 0)
    ctx.graph.connect(sampleBlendGain, directionCrossfade, 0, 2)
    ctx.graph.connect(mixCrossfade, basePathSelect, 0, 0)
    ctx.graph.connect(directionCrossfade, basePathSelect, 0, 2)
    ctx.graph.connect(sampleBlendGain, ringWaveToSample, 0, 0)
    ctx.graph.connect(osc, ringWaveToSample, 0, 2)
    ctx.graph.connect(osc, ringSampleToWave, 0, 0)
    ctx.graph.connect(sampleBlendGain, ringSampleToWave, 0, 2)
    ctx.graph.connect(ringSampleToWave, ringCrossfade, 0, 0)
    ctx.graph.connect(ringWaveToSample, ringCrossfade, 0, 2)
    ctx.graph.connect(blendAddOsc, addCrossfade, 0, 0)
    ctx.graph.connect(morphWaveAdditiveGain, addCrossfade, 0, 0)
    ctx.graph.connect(sampleAdditiveGain, addCrossfade, 0, 2)
    ctx.graph.connect(addCrossfade, addPhraseGain)
    ctx.graph.connect(addPhraseGain, addBranchGain)
    ctx.graph.connect(basePathSelect, branchMixer, 0, 0)
    ctx.graph.connect(ringCrossfade, branchMixer, 0, 2)
    ctx.graph.connect(addBranchGain, branchMixer, 0, 4)
    ctx.graph.connect(branchMixer, voiceMix, 0, 6)

    if mixBus then
      ctx.graph.connect(voiceMix, mixBus, 0, (index - 1) * 2)
    end

    if ctx.graph and ctx.graph.nameNode then
      ctx.graph.nameNode(samplePhaseVocoder, string.format("/midi/synth/debug/voice/%d/samplePhaseVocoder", index))
      ctx.graph.nameNode(sampleEnvFollower, string.format("/midi/synth/debug/voice/%d/sampleEnvFollower", index))
      ctx.graph.nameNode(sampleAdditive, string.format("/midi/synth/debug/voice/%d/sampleAdditive", index))
      ctx.graph.nameNode(sampleAdditiveGain, string.format("/midi/synth/debug/voice/%d/sampleAdditiveGain", index))
      ctx.graph.nameNode(morphWaveAdditive, string.format("/midi/synth/debug/voice/%d/morphWaveAdditive", index))
      ctx.graph.nameNode(morphWaveAdditiveGain, string.format("/midi/synth/debug/voice/%d/morphWaveAdditiveGain", index))
      ctx.graph.nameNode(blendAddOsc, string.format("/midi/synth/debug/voice/%d/blendAddOsc", index))
      ctx.graph.nameNode(addCrossfade, string.format("/midi/synth/debug/voice/%d/addCrossfade", index))
      ctx.graph.nameNode(addPhraseGain, string.format("/midi/synth/debug/voice/%d/addPhraseGain", index))
      ctx.graph.nameNode(addBranchGain, string.format("/midi/synth/debug/voice/%d/addBranchGain", index))
    end

    return {
      osc = osc,
      noiseGain = noiseGain,
      samplePlayback = samplePlayback,
      samplePhaseVocoder = samplePhaseVocoder,
      sampleEnvFollower = sampleEnvFollower,
      sampleGain = sampleGain,
      sampleBlendGain = sampleBlendGain,
      sampleAdditive = sampleAdditive,
      sampleAdditiveGain = sampleAdditiveGain,
      morphWaveAdditive = morphWaveAdditive,
      morphWaveAdditiveGain = morphWaveAdditiveGain,
      blendAddOsc = blendAddOsc,
      addCrossfade = addCrossfade,
      addPhraseGain = addPhraseGain,
      addBranchGain = addBranchGain,
      mixCrossfade = mixCrossfade,
      directionCrossfade = directionCrossfade,
      basePathSelect = basePathSelect,
      ringWaveToSample = ringWaveToSample,
      ringSampleToWave = ringSampleToWave,
      ringCrossfade = ringCrossfade,
      branchMixer = branchMixer,
      voiceMix = voiceMix,
      index = index,
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
      lastBlendSamplePitchRatio = 1.0,
      lastSamplePvocSemitones = 0.0,
      lastBlendOscFreq = 220.0,
      lastSampleAdditiveFreq = 0.0,
      lastSampleAdditiveMix = 0.0,
      morphTemporalPos = 0.0,
      lastTemporalSamplePos = nil,
    }
  end

  local function applyInitialPhaseVocoderSettings(voices, options)
    options = options or {}

    local pvocMode = tonumber(options.pvocMode)
    if pvocMode == nil then
      local samplePitchMode = tonumber(options.samplePitchMode) or 0
      local samplePitchModePhaseVocoderHQ = tonumber(options.samplePitchModePhaseVocoderHQ) or 2
      pvocMode = (samplePitchMode == samplePitchModePhaseVocoderHQ) and 1 or 0
    end
    local fftOrder = math.floor(tonumber(options.fftOrder) or 11)
    local timeStretch = tonumber(options.timeStretch) or 1.0

    for i = 1, #voices do
      local voice = voices[i]
      if voice and voice.samplePhaseVocoder then
        voice.samplePhaseVocoder:setMode(pvocMode)
        voice.samplePhaseVocoder:setFFTOrder(fftOrder)
        voice.samplePhaseVocoder:setTimeStretch(timeStretch)
      end
    end
  end

  local function initializeVoiceGraphDefaults(voices, options)
    options = options or {}

    local adsr = options.adsr or {}
    local oscRenderStandard = tonumber(options.oscRenderStandard) or 0
    local oscRenderAdd = tonumber(options.oscRenderAdd) or 1
    local addFlavorSelf = tonumber(options.addFlavorSelf) or 0
    local referencePlayback = (voices[1] and voices[1].samplePlayback) or nil

    for i = 1, #voices do
      local voice = voices[i]
      if voice then
        voice.osc:setDrive(0.0)
        voice.osc:setDriveShape(0)
        voice.osc:setDriveBias(0.0)
        voice.osc:setDriveMix(1.0)
        voice.osc:setRenderMode(oscRenderStandard)
        voice.osc:setAdditivePartials(8)
        voice.osc:setAdditiveTilt(0.0)
        voice.osc:setAdditiveDrift(0.0)
        voice.osc:setPulseWidth(0.5)
        voice.osc:setUnison(1)
        voice.osc:setDetune(0)
        voice.osc:setSpread(0)

        voice.samplePlayback:setUnison(1)
        voice.samplePlayback:setDetune(0)
        voice.samplePlayback:setSpread(0)

        voice.sampleAdditive:setEnabled(false)
        voice.sampleAdditive:setAmplitude(0.0)
        voice.sampleAdditive:setUnison(1)
        voice.sampleAdditive:setDetune(0)
        voice.sampleAdditive:setSpread(0)
        voice.sampleAdditive:setDrive(0.0)
        voice.sampleAdditive:setDriveShape(0)
        voice.sampleAdditive:setDriveBias(0.0)
        voice.sampleAdditive:setDriveMix(1.0)
        voice.sampleAdditive:clearPartials()
        if voice.sampleAdditive.setSpectralSamplePlayback then
          voice.sampleAdditive:setSpectralSamplePlayback(referencePlayback or voice.samplePlayback)
        end
        if voice.sampleAdditive.setSpectralMode then voice.sampleAdditive:setSpectralMode(0) end
        if voice.sampleAdditive.setSpectralWaveform then voice.sampleAdditive:setSpectralWaveform(voice.waveform or 1) end
        if voice.sampleAdditive.setSpectralPulseWidth then voice.sampleAdditive:setSpectralPulseWidth(0.5) end
        if voice.sampleAdditive.setSpectralAdditivePartials then voice.sampleAdditive:setSpectralAdditivePartials(8) end
        if voice.sampleAdditive.setSpectralAdditiveTilt then voice.sampleAdditive:setSpectralAdditiveTilt(0.0) end
        if voice.sampleAdditive.setSpectralAdditiveDrift then voice.sampleAdditive:setSpectralAdditiveDrift(0.0) end
        if voice.sampleAdditive.setSpectralMorphAmount then voice.sampleAdditive:setSpectralMorphAmount(0.5) end
        if voice.sampleAdditive.setSpectralMorphDepth then voice.sampleAdditive:setSpectralMorphDepth(0.5) end
        if voice.sampleAdditive.setSpectralMorphCurve then voice.sampleAdditive:setSpectralMorphCurve(2) end
        if voice.sampleAdditive.setSpectralTemporalSpeed then voice.sampleAdditive:setSpectralTemporalSpeed(1.0) end
        if voice.sampleAdditive.setSpectralTemporalSmooth then voice.sampleAdditive:setSpectralTemporalSmooth(0.0) end
        if voice.sampleAdditive.setSpectralTemporalContrast then voice.sampleAdditive:setSpectralTemporalContrast(0.5) end
        if voice.sampleAdditive.setSpectralStretch then voice.sampleAdditive:setSpectralStretch(0.0) end
        if voice.sampleAdditive.setSpectralTiltMode then voice.sampleAdditive:setSpectralTiltMode(0) end
        if voice.sampleAdditive.setSpectralAddFlavor then voice.sampleAdditive:setSpectralAddFlavor(addFlavorSelf) end
        voice.sampleAdditiveGain:setGain(0.0)

        if voice.addPhraseGain then voice.addPhraseGain:setGain(1.0) end

        voice.morphWaveAdditive:setEnabled(false)
        voice.morphWaveAdditive:setAmplitude(0.0)
        voice.morphWaveAdditive:setUnison(1)
        voice.morphWaveAdditive:setDetune(0)
        voice.morphWaveAdditive:setSpread(0)
        voice.morphWaveAdditive:setDrive(0.0)
        voice.morphWaveAdditive:setDriveShape(0)
        voice.morphWaveAdditive:setDriveBias(0.0)
        voice.morphWaveAdditive:setDriveMix(1.0)
        voice.morphWaveAdditive:clearPartials()
        voice.morphWaveAdditiveGain:setGain(0.0)

        voice.blendAddOsc:setWaveform(1)
        voice.blendAddOsc:setEnabled(false)
        voice.blendAddOsc:setAmplitude(0.0)
        voice.addBranchGain:setGain(0.0)
        voice.blendAddOsc:setDrive(0.0)
        voice.blendAddOsc:setDriveShape(0)
        voice.blendAddOsc:setDriveBias(0.0)
        voice.blendAddOsc:setDriveMix(1.0)
        voice.blendAddOsc:setRenderMode(oscRenderAdd)
        voice.blendAddOsc:setAdditivePartials(8)
        voice.blendAddOsc:setAdditiveTilt(0.0)
        voice.blendAddOsc:setAdditiveDrift(0.0)
        voice.blendAddOsc:setPulseWidth(0.5)
        voice.blendAddOsc:setUnison(1)
        voice.blendAddOsc:setDetune(0)
        voice.blendAddOsc:setSpread(0)

        if voice.ringWaveToSample and voice.ringWaveToSample.setEnabled then
          voice.ringWaveToSample:setEnabled(false)
          voice.ringWaveToSample:setMix(0.0)
          voice.ringWaveToSample:setDepth(0.0)
        end
        if voice.ringSampleToWave and voice.ringSampleToWave.setEnabled then
          voice.ringSampleToWave:setEnabled(false)
          voice.ringSampleToWave:setMix(0.0)
          voice.ringSampleToWave:setDepth(0.0)
        end
        if voice.ringCrossfade then
          voice.ringCrossfade:setMix(0.0)
        end
        if voice.adsr then
          voice.adsr:setAttack(adsr.attack or 0.05)
          voice.adsr:setDecay(adsr.decay or 0.2)
          voice.adsr:setSustain(adsr.sustain or 0.7)
          voice.adsr:setRelease(adsr.release or 0.4)
        end
      end
    end
  end

  local function isAdditiveBlendMode(blendMode)
    return tonumber(blendMode) == 4 or tonumber(blendMode) == 5
  end

  local function getEffectiveVoiceStackingParams(target, options)
    options = options or {}

    local blendMode = tonumber(options.blendMode) or 0
    local unisonVoices = math.max(1, math.min(8, tonumber(options.unisonVoices) or 1))
    local detuneCents = Utils.clamp(tonumber(options.detuneCents) or 0.0, 0.0, 100.0)
    local stereoSpread = Utils.clamp(tonumber(options.stereoSpread) or 0.0, 0.0, 1.0)

    if isAdditiveBlendMode(blendMode) and target == "samplePlayback" then
      return 1, 0.0, 0.0
    end

    if isAdditiveBlendMode(blendMode)
      and (target == "sampleAdditive" or target == "morphWaveAdditive" or target == "blendAddOsc") then
      local cappedUni = math.min(4, unisonVoices)
      local det = detuneCents
      local spr = stereoSpread
      if unisonVoices > cappedUni then
        local extra = (unisonVoices - cappedUni) / math.max(1, 8 - cappedUni)
        det = Utils.clamp(det * (1.0 + extra * 0.9), 0.0, 100.0)
        spr = Utils.clamp(spr + extra * 0.25, 0.0, 1.0)
      end
      return cappedUni, det, spr
    end

    return unisonVoices, detuneCents, stereoSpread
  end

  local function applyVoiceStackingParams(voice, options)
    if not voice then
      return
    end

    if voice.osc then
      local uni, det, spr = getEffectiveVoiceStackingParams("osc", options)
      voice.osc:setUnison(uni)
      voice.osc:setDetune(det)
      voice.osc:setSpread(spr)
    end
    if voice.samplePlayback then
      local uni, det, spr = getEffectiveVoiceStackingParams("samplePlayback", options)
      voice.samplePlayback:setUnison(uni)
      voice.samplePlayback:setDetune(det)
      voice.samplePlayback:setSpread(spr)
    end
    if voice.sampleAdditive then
      local uni, det, spr = getEffectiveVoiceStackingParams("sampleAdditive", options)
      voice.sampleAdditive:setUnison(uni)
      voice.sampleAdditive:setDetune(det)
      voice.sampleAdditive:setSpread(spr)
    end
    if voice.morphWaveAdditive then
      local uni, det, spr = getEffectiveVoiceStackingParams("morphWaveAdditive", options)
      voice.morphWaveAdditive:setUnison(uni)
      voice.morphWaveAdditive:setDetune(det)
      voice.morphWaveAdditive:setSpread(spr)
    end
    if voice.blendAddOsc then
      local uni, det, spr = getEffectiveVoiceStackingParams("blendAddOsc", options)
      voice.blendAddOsc:setUnison(uni)
      voice.blendAddOsc:setDetune(det)
      voice.blendAddOsc:setSpread(spr)
    end
  end

  local function ratioToSemitones(ratio)
    local safeRatio = math.max(1.0e-6, tonumber(ratio) or 1.0)
    return (math.log(safeRatio) / math.log(2.0)) * 12.0
  end

  local function semitonesToRatio(semitones)
    return 2.0 ^ ((tonumber(semitones) or 0.0) / 12.0)
  end

  local function blendPitchRatio(options)
    options = options or {}
    return 2.0 ^ (Utils.clamp(tonumber(options.blendSamplePitch) or 0.0, -24.0, 24.0) / 12.0)
  end

  local function getBlendSampleDesiredPitchRatio(voice, options)
    options = options or {}
    if not voice then
      return 1.0
    end

    local keyRatio = 1.0
    local blendKeyTrack = tonumber(options.blendKeyTrack) or 0
    local noteToFrequency = options.noteToFrequency

    if blendKeyTrack >= 1 and type(noteToFrequency) == "function" then
      local rootFreq = noteToFrequency(options.sampleRootNote)
      if rootFreq > 0.0 then
        keyRatio = Utils.clamp((voice.freq or 220.0) / rootFreq, 0.05, 8.0)
      end
    end

    return Utils.clamp(keyRatio * blendPitchRatio(options), 0.05, 8.0)
  end

  local function getBlendSampleDesiredPitchSemitones(voice, options)
    return ratioToSemitones(getBlendSampleDesiredPitchRatio(voice, options))
  end

  local function getBlendSamplePlaybackSpeed(voice, options)
    options = options or {}

    local samplePitchMode = tonumber(options.samplePitchMode) or 0
    local phaseVocoderMode = tonumber(options.samplePitchModePhaseVocoder) or 1
    local phaseVocoderHQMode = tonumber(options.samplePitchModePhaseVocoderHQ) or 2

    if samplePitchMode ~= phaseVocoderMode and samplePitchMode ~= phaseVocoderHQMode then
      return getBlendSampleDesiredPitchRatio(voice, options)
    end

    local desiredSemitones = getBlendSampleDesiredPitchSemitones(voice, options)
    local pvocSemitones = Utils.clamp(desiredSemitones, -24.0, 24.0)
    local coarseSemitones = desiredSemitones - pvocSemitones
    return Utils.clamp(semitonesToRatio(coarseSemitones), 0.05, 8.0)
  end

  local function getBlendSamplePhaseVocoderSemitones(voice, options)
    options = options or {}

    local samplePitchMode = tonumber(options.samplePitchMode) or 0
    local phaseVocoderMode = tonumber(options.samplePitchModePhaseVocoder) or 1
    local phaseVocoderHQMode = tonumber(options.samplePitchModePhaseVocoderHQ) or 2

    if samplePitchMode ~= phaseVocoderMode and samplePitchMode ~= phaseVocoderHQMode then
      return 0.0
    end

    return Utils.clamp(getBlendSampleDesiredPitchSemitones(voice, options), -24.0, 24.0)
  end

  local function applyPitchModeToVoice(voice, options)
    options = options or {}
    if not voice or not voice.samplePhaseVocoder then
      return
    end

    local samplePitchMode = tonumber(options.samplePitchMode) or 0
    local phaseVocoderMode = tonumber(options.samplePitchModePhaseVocoder) or 1
    local phaseVocoderHQMode = tonumber(options.samplePitchModePhaseVocoderHQ) or 2
    local pvocActive = samplePitchMode == phaseVocoderMode or samplePitchMode == phaseVocoderHQMode
    local pvocSemitones = pvocActive and getBlendSamplePhaseVocoderSemitones(voice, options) or 0.0

    voice.samplePhaseVocoder:setPitchSemitones(pvocSemitones)
    voice.samplePhaseVocoder:setMix(pvocActive and 1.0 or 0.0)
    voice.lastBlendSamplePitchRatio = getBlendSampleDesiredPitchRatio(voice, options)
    voice.lastSamplePvocSemitones = pvocSemitones
  end

  local function getSampleDerivedAdditiveTargetFrequency(voice, options)
    options = options or {}
    local noteToFrequency = options.noteToFrequency
    local rootFreq = (type(noteToFrequency) == "function") and noteToFrequency(options.sampleRootNote) or 0.0
    if rootFreq <= 0.0 then
      rootFreq = 220.0
    end
    return Utils.clamp(rootFreq * getBlendSampleDesiredPitchRatio(voice, options), 20.0, 8000.0)
  end

  local function applySpectralVoiceParams(voice, options)
    options = options or {}
    if not voice or not voice.sampleAdditive then
      return
    end

    if voice.sampleAdditive.setSpectralSamplePlayback then
      voice.sampleAdditive:setSpectralSamplePlayback(options.sampleReferencePlayback or voice.samplePlayback)
    end

    local blendMode = tonumber(options.blendMode) or 0
    local spectralMode = 0
    if blendMode == 4 then
      spectralMode = 1
    elseif blendMode == 5 then
      spectralMode = 2
    end

    if voice.sampleAdditive.setSpectralMode then voice.sampleAdditive:setSpectralMode(spectralMode) end
    if voice.sampleAdditive.setSpectralWaveform then voice.sampleAdditive:setSpectralWaveform(voice.waveform or 1) end
    if voice.sampleAdditive.setSpectralPulseWidth then voice.sampleAdditive:setSpectralPulseWidth(voice.pulseWidth or 0.5) end
    if voice.sampleAdditive.setSpectralAdditivePartials then voice.sampleAdditive:setSpectralAdditivePartials(tonumber(options.additivePartials) or 8) end
    if voice.sampleAdditive.setSpectralAdditiveTilt then voice.sampleAdditive:setSpectralAdditiveTilt(tonumber(options.additiveTilt) or 0.0) end
    if voice.sampleAdditive.setSpectralAdditiveDrift then voice.sampleAdditive:setSpectralAdditiveDrift(tonumber(options.additiveDrift) or 0.0) end
    local morphRange = Utils.clamp01(tonumber(options.blendModAmount) or 0.5)
    local effectiveMorphAmount = Utils.clamp01(tonumber(options.blendAmount) or 0.5) * morphRange
    if voice.sampleAdditive.setSpectralMorphAmount then voice.sampleAdditive:setSpectralMorphAmount(effectiveMorphAmount) end
    if voice.sampleAdditive.setSpectralMorphDepth then voice.sampleAdditive:setSpectralMorphDepth(1.0) end
    if voice.sampleAdditive.setSpectralMorphCurve then voice.sampleAdditive:setSpectralMorphCurve(tonumber(options.morphCurve) or 2) end
    if voice.sampleAdditive.setSpectralTemporalSpeed then voice.sampleAdditive:setSpectralTemporalSpeed(tonumber(options.morphSpeed) or 1.0) end
    if voice.sampleAdditive.setSpectralTemporalSmooth then voice.sampleAdditive:setSpectralTemporalSmooth(tonumber(options.morphSmooth) or 0.0) end
    if voice.sampleAdditive.setSpectralTemporalContrast then voice.sampleAdditive:setSpectralTemporalContrast(tonumber(options.morphContrast) or 0.5) end
    if voice.sampleAdditive.setSpectralEnvelopeFollow then voice.sampleAdditive:setSpectralEnvelopeFollow(tonumber(options.envFollowAmount) or 1.0) end
    if voice.sampleAdditive.setSpectralStretch then voice.sampleAdditive:setSpectralStretch(tonumber(options.morphConvergence) or 0.0) end
    if voice.sampleAdditive.setSpectralTiltMode then voice.sampleAdditive:setSpectralTiltMode(tonumber(options.morphPhaseParam) or 0) end
    if voice.sampleAdditive.setSpectralAddFlavor then
      voice.sampleAdditive:setSpectralAddFlavor(tonumber(options.addFlavor) or tonumber(options.addFlavorSelf) or 0)
    end
  end

  local function applySampleDerivedAdditiveToVoice(voice, amp, options)
    options = options or {}
    if not voice or not voice.sampleAdditive or not voice.sampleAdditiveGain or not voice.addPhraseGain or not voice.blendAddOsc or not voice.morphWaveAdditive or not voice.morphWaveAdditiveGain then
      return
    end

    local blendMode = tonumber(options.blendMode) or 0
    local addActive = blendMode == 4
    local morphActive = blendMode == 5
    local activeAmp = tonumber(amp) or 0.0

    applySpectralVoiceParams(voice, options)

    if addActive and activeAmp > 0.0005 then
      voice.blendAddOsc:setEnabled(true)
      voice.blendAddOsc:setAmplitude(activeAmp * 2.0)
      voice.blendAddOsc:setWaveform(voice.waveform or 1)
      voice.blendAddOsc:setPulseWidth(voice.pulseWidth or 0.5)
    else
      voice.blendAddOsc:setEnabled(false)
      voice.blendAddOsc:setAmplitude(0.0)
    end

    voice.morphWaveAdditive:setEnabled(false)
    voice.morphWaveAdditive:setAmplitude(0.0)
    voice.morphWaveAdditiveGain:setGain(0.0)

    if (not addActive and not morphActive) or activeAmp <= 0.0005 then
      if voice.sampleAdditive.setSpectralMode then voice.sampleAdditive:setSpectralMode((addActive and 1) or (morphActive and 2) or 0) end
      voice.sampleAdditive:setEnabled(false)
      voice.sampleAdditive:setAmplitude(0.0)
      voice.sampleAdditiveGain:setGain(0.0)
      voice.addPhraseGain:setGain(1.0)
      voice.lastSampleAdditiveFreq = 0.0
      voice.lastSampleAdditiveMix = 0.0
      return
    end

    if type(options.ensureSampleAnalysis) == "function" then
      options.ensureSampleAnalysis()
    end

    local targetFreq
    if morphActive then
      local morphPos = Utils.clamp01(tonumber(options.blendAmount) or 0.0)
      local waveFreq = Utils.clamp(voice.freq or 220.0, 20.0, 8000.0)
      local sampleFreq = getSampleDerivedAdditiveTargetFrequency(voice, options)
      targetFreq = waveFreq + (sampleFreq - waveFreq) * morphPos
    else
      targetFreq = getSampleDerivedAdditiveTargetFrequency(voice, options)
    end

    voice.sampleAdditive:setEnabled(true)
    voice.sampleAdditive:setAmplitude(activeAmp * 2.0)
    voice.sampleAdditive:setFrequency(targetFreq)
    voice.sampleAdditiveGain:setGain(1.0)
    voice.addPhraseGain:setGain(1.0)
    voice.lastSampleAdditiveFreq = targetFreq
    voice.lastSampleAdditiveMix = (addActive or morphActive) and 1.0 or 0.0
  end

  local function applyBlendParamsToVoice(voice, options)
    options = options or {}
    if not voice then
      return
    end

    local blendMode = tonumber(options.blendMode) or 0
    local blendPos = Utils.clamp01(tonumber(options.blendAmount) or 0.0) * 2.0 - 1.0
    local depth = Utils.clamp01(tonumber(options.blendModAmount) or 0.0)

    if voice.mixCrossfade then
      voice.mixCrossfade:setPosition(blendPos)
      voice.mixCrossfade:setMix(1.0)
      voice.mixCrossfade:setCurve(1.0)
    end

    if voice.directionCrossfade then
      voice.directionCrossfade:setPosition(blendPos)
      voice.directionCrossfade:setMix(1.0)
      voice.directionCrossfade:setCurve(1.0)
    end

    if voice.basePathSelect then
      local useDirectional = (blendMode == 2 or blendMode == 3)
      voice.basePathSelect:setPosition(useDirectional and 1.0 or -1.0)
      voice.basePathSelect:setMix(1.0)
      voice.basePathSelect:setCurve(1.0)
    end

    if voice.addCrossfade then
      if blendMode == 5 then
        voice.addCrossfade:setPosition(1.0)
      else
        voice.addCrossfade:setPosition(blendPos)
      end
      voice.addCrossfade:setMix(1.0)
      voice.addCrossfade:setCurve(1.0)
    end

    if voice.addBranchGain then
      voice.addBranchGain:setGain(isAdditiveBlendMode(blendMode) and 1.0 or 0.0)
    end

    if voice.branchMixer then
      if blendMode == 4 or blendMode == 5 then
        voice.branchMixer:setGain(1, 1.0 - depth)
        voice.branchMixer:setGain(2, 0.0)
        voice.branchMixer:setGain(3, depth)
      else
        voice.branchMixer:setGain(1, (blendMode == 0 or blendMode == 2 or blendMode == 3) and 1.0 or 0.0)
        voice.branchMixer:setGain(2, (blendMode == 1) and 1.0 or 0.0)
        voice.branchMixer:setGain(3, 0.0)
      end
    end

    if voice.osc then
      voice.osc:setSyncEnabled(blendMode == 3 and blendPos < 0.0)
    end

    if voice.ringWaveToSample and voice.ringSampleToWave and voice.ringCrossfade then
      local ringActive = (blendMode == 1)
      local oscFreq = voice.freq or 220.0
      local samplePitchRatio = getBlendSampleDesiredPitchRatio(voice, options)
      local noteToFrequency = options.noteToFrequency
      local rootFreq = (type(noteToFrequency) == "function") and noteToFrequency(options.sampleRootNote) or 0.0
      local sampleFreq = (rootFreq > 0.0) and (rootFreq * samplePitchRatio) or (220.0 * samplePitchRatio)

      if voice.ringWaveToSample.setEnabled then
        voice.ringWaveToSample:setEnabled(ringActive)
      end
      if voice.ringSampleToWave.setEnabled then
        voice.ringSampleToWave:setEnabled(ringActive)
      end

      voice.ringWaveToSample:setFrequency(Utils.clamp(sampleFreq, 20.0, 8000.0))
      voice.ringWaveToSample:setDepth(ringActive and depth or 0.0)
      voice.ringWaveToSample:setSpread(Utils.lerp(0.0, 180.0, Utils.clamp01(tonumber(options.sampleToWave) or 0.0)))
      voice.ringWaveToSample:setMix(ringActive and 1.0 or 0.0)

      voice.ringSampleToWave:setFrequency(Utils.clamp(oscFreq, 20.0, 8000.0))
      voice.ringSampleToWave:setDepth(ringActive and depth or 0.0)
      voice.ringSampleToWave:setSpread(Utils.lerp(0.0, 180.0, Utils.clamp01(tonumber(options.waveToSample) or 0.0)))
      voice.ringSampleToWave:setMix(ringActive and 1.0 or 0.0)

      voice.ringCrossfade:setPosition(blendPos)
      voice.ringCrossfade:setMix(ringActive and 1.0 or 0.0)
      voice.ringCrossfade:setCurve(1.0)
    end
  end

  local function updateBlendVoiceFrame(voice, options)
    options = options or {}
    if not voice or voice.gate <= 0.5 then
      return
    end

    local blendMode = tonumber(options.blendMode) or 0
    local sr = math.max(1.0, tonumber(options.sr) or 44100.0)
    local blockSamples = math.max(0.0, tonumber(options.blockSamples) or 0.0)
    local depth = Utils.clamp01(tonumber(options.blendModAmount) or 0.0)
    local baseFreq = Utils.clamp(voice.freq or 220.0, 20.0, 8000.0)
    local baseSpeed = getBlendSamplePlaybackSpeed(voice, options)
    local oscFreq = baseFreq
    local sampleSpeed = baseSpeed
    local modAmtWave = Utils.clamp01(tonumber(options.sampleToWave) or 0.0) * depth * 0.35
    local modAmtSample = Utils.clamp01(tonumber(options.waveToSample) or 0.0) * depth * 0.75

    local phaseInc = (baseFreq / sr) * blockSamples
    voice.blendPhase = (voice.blendPhase or 0.0) + phaseInc
    voice.blendPhase = voice.blendPhase - math.floor(voice.blendPhase)
    local oscMod = math.sin(voice.blendPhase * 2.0 * math.pi)

    local samplePos = (voice.samplePlayback and voice.samplePlayback:getNormalizedPosition()) or 0.0
    local sampleMod = math.sin(samplePos * 2.0 * math.pi)

    if blendMode == 2 then
      sampleSpeed = Utils.clamp(baseSpeed * (1.0 + oscMod * modAmtSample), 0.05, 8.0)
      oscFreq = Utils.clamp(baseFreq * (1.0 + sampleMod * modAmtWave), 20.0, 8000.0)
    elseif blendMode == 3 then
      voice.syncPhase = (voice.syncPhase or 0.0) + phaseInc
      if voice.syncPhase >= 1.0 then
        voice.syncPhase = voice.syncPhase - math.floor(voice.syncPhase)
        if voice.samplePlayback then
          if options.sampleRetrigger then
            voice.samplePlayback:trigger()
          else
            voice.samplePlayback:play()
          end
        end
      end
      voice.lastSamplePos = samplePos
    else
      voice.lastSamplePos = samplePos
    end

    if voice.samplePlayback then
      voice.samplePlayback:setSpeed(sampleSpeed)
    end

    if isAdditiveBlendMode(blendMode)
      and voice.sampleAdditive
      and voice.sampleAdditive.setSpectralTemporalPosition
      and type(options.mapTemporalPositionForVoice) == "function" then
      voice.sampleAdditive:setSpectralTemporalPosition(
        options.mapTemporalPositionForVoice(voice, samplePos or voice.lastSamplePos or 0.0)
      )
    end

    if options.additiveRefreshPending and isAdditiveBlendMode(blendMode) then
      applySampleDerivedAdditiveToVoice(voice, options.amp or voice.amp or 0.0, options)
    end

    if isAdditiveBlendMode(blendMode) and voice.addPhraseGain then
      local envGain = 1.0
      local envFollowAmount = tonumber(options.envFollowAmount) or 0.0
      if envFollowAmount > 0.001 and voice.sampleEnvFollower then
        local envValue = Utils.clamp01(tonumber(voice.sampleEnvFollower:getEnvelope()) or 0.0)
        local latestSampleAnalysis = options.latestSampleAnalysis
        local latestSamplePartials = options.latestSamplePartials
        local envReference = tonumber(latestSampleAnalysis and latestSampleAnalysis.rms)
          or tonumber(latestSamplePartials and latestSamplePartials.rmsLevel)
          or 0.18
        envReference = Utils.clamp(envReference, 0.05, 0.6)
        local normalizedEnv = Utils.clamp(envValue / envReference, 0.0, 3.0)
        envGain = 1.0 + (normalizedEnv - 1.0) * envFollowAmount
      end
      voice.addPhraseGain:setGain(envGain)
    end

    local finalOscFreq = oscFreq
    local blendKeyTrack = tonumber(options.blendKeyTrack) or 0
    if blendKeyTrack == 1 then
      -- Mode 1: Wave locked to root note
      local noteToFrequency = options.noteToFrequency
      local rootFreq = (type(noteToFrequency) == "function") and noteToFrequency(options.sampleRootNote) or 0.0
      if rootFreq > 0.0 then
        finalOscFreq = rootFreq
      else
        finalOscFreq = 220.0
      end
    elseif blendKeyTrack == 2 then
      -- Mode 2 (both keytrack): Apply pitch knob to wave as well as sample
      local pitchRatio = 2.0 ^ (Utils.clamp(tonumber(options.blendSamplePitch) or 0.0, -24.0, 24.0) / 12.0)
      finalOscFreq = oscFreq * pitchRatio
    end

    if voice.osc then
      voice.osc:setFrequency(finalOscFreq)
    end
    voice.lastBlendSampleSpeed = sampleSpeed
    voice.lastBlendOscFreq = finalOscFreq
  end

  local function resetBlendVoiceFrameState(voice)
    if not voice then
      return
    end
    voice.blendPhase = 0.0
    voice.syncPhase = 0.0
    voice.lastSamplePos = 0.0
  end

  -- ============================================================================
  -- Partials / Morph Functions
  -- ============================================================================

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

  local function hasUsablePartials(partials)
    return type(partials) == "table"
      and (tonumber(partials.activeCount) or 0) > 0
      and (tonumber(partials.fundamental) or 0.0) > 0.0
  end

  local function buildDrivenWaveWeight(waveform, harmonicNumber, width)
    local wf = Utils.roundIndex(waveform, 7)
    local h = math.max(1, math.floor(tonumber(harmonicNumber) or 1))
    local pulse = Utils.clamp(width or 0.5, 0.01, 0.99)

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

  local function buildDrivenPartials(sourcePartials, waveform, pulseWidth)
    if not hasUsablePartials(sourcePartials) then
      return sourcePartials
    end
    local width = pulseWidth or 0.5
    local wf = waveform or 1
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
        local weight = math.max(0.0, buildDrivenWaveWeight(wf, i, width))
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

  local function morphPartials(partialsA, partialsB, position, curve, depth)
    local a = normalizePartials(partialsA)
    local b = normalizePartials(partialsB)
    if not a and not b then return nil end
    if not a then return partialsB end
    if not b then return partialsA end
    local pos = Utils.clamp01(position or 0.0)
    local dep = Utils.clamp01(depth or 1.0)
    local aCount = a.activeCount or 0
    local bCount = b.activeCount or 0
    local maxCount = math.max(aCount, bCount)
    if maxCount <= 0 then return nil end
    local aCoeff, bCoeff
    local curveType = curve or 2
    if curveType == 0 then
      aCoeff = 1.0 - pos
      bCoeff = pos
    elseif curveType == 1 then
      local t = 0.5 - 0.5 * math.cos(pos * math.pi)
      aCoeff = 1.0 - t
      bCoeff = t
    else
      aCoeff = math.cos(pos * math.pi * 0.5)
      bCoeff = math.sin(pos * math.pi * 0.5)
    end
    local freqMorphT = pos * dep
    local out = { activeCount = maxCount, fundamental = 1.0, partials = {} }
    for i = 1, maxCount do
      local ap = (i <= aCount) and a.partials[i] or nil
      local bp = (i <= bCount) and b.partials[i] or nil
      local aRatio = ap and (tonumber(ap.ratio) or 0.0) or 0.0
      local aAmp = ap and (tonumber(ap.amplitude) or 0.0) or 0.0
      local aPhase = ap and (tonumber(ap.phase) or 0.0) or 0.0
      local aDecay = ap and (tonumber(ap.decayRate) or 0.0) or 0.0
      local bRatio = bp and (tonumber(bp.ratio) or 0.0) or 0.0
      local bAmp = bp and (tonumber(bp.amplitude) or 0.0) or 0.0
      local bPhase = bp and (tonumber(bp.phase) or 0.0) or 0.0
      local bDecay = bp and (tonumber(bp.decayRate) or 0.0) or 0.0
      local morphRatio
      if aRatio <= 0.01 and bRatio <= 0.01 then
        morphRatio = 0.0
      elseif aRatio <= 0.01 then
        morphRatio = bRatio
      elseif bRatio <= 0.01 then
        morphRatio = aRatio
      else
        local logA = math.log(aRatio)
        local logB = math.log(bRatio)
        morphRatio = math.exp(logA + (logB - logA) * freqMorphT)
      end
      local morphAmp = aAmp * aCoeff + bAmp * bCoeff
      local morphPhase = aPhase + (bPhase - aPhase) * pos
      local morphDecay = aDecay + (bDecay - aDecay) * pos
      out.partials[i] = {
        frequency = morphRatio,
        amplitude = morphAmp,
        phase = morphPhase,
        decayRate = morphDecay,
      }
    end
    return out
  end

  local function getSourceBounds()
    if #sampleSourceOrder == 0 then
      local fallbackId = defaultSourceId or 0
      return fallbackId, fallbackId
    end
    return sampleSourceOrder[1], sampleSourceOrder[#sampleSourceOrder]
  end

  -- Public interface
  return {
    -- Source registry info
    getSourceBounds = getSourceBounds,
    getRegisteredSourceIds = function()
      local out = {}
      for i = 1, #sampleSourceOrder do
        out[i] = sampleSourceOrder[i]
      end
      return out
    end,

    -- State accessors
    getSource = function() return sampleSource end,
    setSource = function(id)
      sampleSource = math.floor(tonumber(id) or defaultSourceId or 0)
    end,
    getCaptureBars = function() return sampleCaptureBars end,
    setCaptureBars = function(bars)
      sampleCaptureBars = Utils.clamp(bars or 1.0, 0.0625, 16)
    end,
    getCaptureMode = function() return sampleCaptureMode end,
    setCaptureMode = function(mode)
      sampleCaptureMode = Utils.roundIndex(mode, 1)
      if sampleCaptureMode ~= 1 then
        clearCaptureRecording(true)
      end
    end,
    getCaptureStartOffset = function() return sampleCaptureStartOffset end,
    setCaptureStartOffset = function(offset)
      sampleCaptureStartOffset = math.floor(offset or 0)
      if sampleCaptureRecording then
        sampleCaptureRecordingStartOffset = normalizeWriteOffset(offset)
      end
    end,
    getCaptureRecording = function() return sampleCaptureRecording end,
    setCaptureRecording = setCaptureRecording,
    getLastCapturedLengthMs = function() return lastCapturedLengthMs end,
    setLastCapturedLengthMs = function(ms) lastCapturedLengthMs = ms end,

    -- Source management
    registerSampleSource = registerSampleSource,
    getSelectedSourceEntry = getSelectedSourceEntry,
    getSelectedSourceCapture = getSelectedSourceCapture,
    getSelectedSourceWriteOffset = getSelectedSourceWriteOffset,

    -- Actions
    capture = capture,
    triggerCapture = triggerCapture,

    -- Analysis
    requestAnalysis = requestAnalysis,
    pollAnalysis = pollAnalysis,
    getLastAnalysis = getLastAnalysis,
    getLastPartials = getLastPartials,
    getLastTemporal = getLastTemporal,
    isAnalysisInFlight = isAnalysisInFlight,
    resetAnalysisState = resetAnalysisState,

    -- Voice graph ownership
    createVoiceGraph = createVoiceGraph,
    applyInitialPhaseVocoderSettings = applyInitialPhaseVocoderSettings,
    initializeVoiceGraphDefaults = initializeVoiceGraphDefaults,

    -- Blend / routing ownership
    isAdditiveBlendMode = isAdditiveBlendMode,
    getEffectiveVoiceStackingParams = getEffectiveVoiceStackingParams,
    applyVoiceStackingParams = applyVoiceStackingParams,
    getBlendSampleDesiredPitchRatio = getBlendSampleDesiredPitchRatio,
    getBlendSamplePlaybackSpeed = getBlendSamplePlaybackSpeed,
    applyPitchModeToVoice = applyPitchModeToVoice,
    applySpectralVoiceParams = applySpectralVoiceParams,
    applySampleDerivedAdditiveToVoice = applySampleDerivedAdditiveToVoice,
    applyBlendParamsToVoice = applyBlendParamsToVoice,
    updateBlendVoiceFrame = updateBlendVoiceFrame,
    resetBlendVoiceFrameState = resetBlendVoiceFrameState,

    -- Partials / Morph
    reverseTable = reverseTable,
    resamplePeaks = resamplePeaks,
    hasUsablePartials = hasUsablePartials,
    buildDrivenWaveWeight = buildDrivenWaveWeight,
    buildDrivenPartials = buildDrivenPartials,
    normalizePartials = normalizePartials,
    morphPartials = morphPartials,
  }
end

return M

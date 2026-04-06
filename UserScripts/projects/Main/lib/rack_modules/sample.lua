local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local Utils = deps.Utils
  local SampleSynth = deps.SampleSynth
  local ParameterBinder = deps.ParameterBinder
  local noteToFrequency = deps.noteToFrequency
  local connectMixerInput = deps.connectMixerInput
  local voiceCount = deps.voiceCount
  local outputTrim = deps.outputTrim
  local samplePitchModeClassic = deps.samplePitchModeClassic
  local samplePitchModePhaseVocoder = deps.samplePitchModePhaseVocoder
  local samplePitchModePhaseVocoderHQ = deps.samplePitchModePhaseVocoderHQ
  local buildSourceSpecs = deps.buildSourceSpecs

  local function buildRuntimeOptions(slot)
    return {
      samplePitchMode = tonumber(slot and slot.pitchMode) or samplePitchModeClassic,
      samplePitchModePhaseVocoder = samplePitchModePhaseVocoder,
      samplePitchModePhaseVocoderHQ = samplePitchModePhaseVocoderHQ,
      sampleRootNote = tonumber(slot and slot.rootNote) or 60.0,
      unisonVoices = math.floor(Utils.clamp(tonumber(slot and slot.unison) or 1, 1, 8) + 0.5),
      detuneCents = Utils.clamp(tonumber(slot and slot.detune) or 0.0, 0.0, 100.0),
      stereoSpread = Utils.clamp(tonumber(slot and slot.spread) or 0.0, 0.0, 1.0),
      blendKeyTrack = 1,
      blendSamplePitch = 0.0,
      noteToFrequency = noteToFrequency,
    }
  end

  local function applyWindowToVoice(slot, voice)
    if not (slot and voice and voice.samplePlayback) then
      return false
    end

    local capturedLength = tonumber(voice.sampleCapturedLength) or 0
    local fullLength = capturedLength > 0 and capturedLength or (voice.samplePlayback:getLoopLength() or 0)
    if fullLength <= 0 then
      return false
    end

    local playStart = Utils.clamp(tonumber(slot.playStart) or 0.0, 0.0, 0.95)
    local loopStart = Utils.clamp(tonumber(slot.loopStart) or 0.0, 0.0, 0.95)
    local loopEnd = Utils.clamp((tonumber(slot.loopStart) or 0.0) + (tonumber(slot.loopLen) or 1.0), 0.05, 1.0)
    if loopEnd <= loopStart then
      loopEnd = math.min(1.0, loopStart + 0.01)
    end
    if playStart > loopEnd then
      playStart = loopStart
    end

    voice.playStartNorm = playStart
    voice.loopStartNorm = loopStart
    voice.loopEndNorm = loopEnd
    voice.crossfadeNorm = Utils.clamp(tonumber(slot.crossfade) or 0.1, 0.0, 0.5)

    voice.samplePlayback:setLoopLength(fullLength)
    voice.samplePlayback:setPlayStart(playStart)
    voice.samplePlayback:setLoopStart(loopStart)
    voice.samplePlayback:setLoopEnd(loopEnd)
    voice.samplePlayback:setCrossfade(voice.crossfadeNorm)
    return true
  end

  local function refreshVoice(slotIndex, voiceIndex)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (slot and voice and voice.samplePlayback and voice.samplePhaseVocoder and voice.gain) then
      return false
    end

    local note = Utils.clamp(tonumber(voice.note) or 60.0, 0.0, 127.0)
    voice.freq = noteToFrequency(note)
    voice.gain:setGain(Utils.clamp01(tonumber(voice.level) or 0.0))
    local runtimeOptions = buildRuntimeOptions(slot)
    slot.sampleSynth.applyVoiceStackingParams(voice, runtimeOptions)
    voice.samplePlayback:setSpeed(slot.sampleSynth.getBlendSamplePlaybackSpeed(voice, runtimeOptions))
    slot.sampleSynth.applyPitchModeToVoice(voice, runtimeOptions)
    local pvocMode = ((tonumber(slot.pitchMode) or 0) == samplePitchModePhaseVocoderHQ) and 1 or 0
    voice.samplePhaseVocoder:setMode(pvocMode)
    voice.samplePhaseVocoder:setFFTOrder(math.floor(Utils.clamp(tonumber(slot.pvocFFTOrder) or 11, 9, 12)))
    voice.samplePhaseVocoder:setTimeStretch(Utils.clamp(tonumber(slot.pvocTimeStretch) or 1.0, 0.25, 4.0))
    applyWindowToVoice(slot, voice)
    return true
  end

  local function refreshAllVoices(slotIndex)
    local slot = slots[slotIndex]
    if not (slot and slot.voices) then
      return false
    end
    for i = 1, #slot.voices do
      refreshVoice(slotIndex, i)
    end
    return true
  end

  local function getPathWriter()
    if type(setParam) == "function" then
      return setParam
    end
    if ctx.host and ctx.host.setParam then
      return function(path, value)
        return ctx.host.setParam(path, value)
      end
    end
    return nil
  end

  local function updateReadbacks(slotIndex)
    local slot = slots[slotIndex]
    if not slot then
      return false
    end
    local writer = getPathWriter()
    if type(writer) ~= "function" then
      return false
    end

    local writeOffsetPath = ParameterBinder.dynamicSampleCaptureWriteOffsetPath(slotIndex)
    local writeOffset = slot.sampleSynth and slot.sampleSynth.getSelectedSourceWriteOffset and slot.sampleSynth.getSelectedSourceWriteOffset() or 0
    writer(writeOffsetPath, math.max(0, math.floor(tonumber(writeOffset) or 0)))

    local capturedLengthPath = ParameterBinder.dynamicSampleCapturedLengthMsPath(slotIndex)
    writer(capturedLengthPath, math.max(0, math.floor(tonumber(slot.lastCapturedLengthMs) or 0)))
    return true
  end

  local function maybeApplyDetectedRoot(slotIndex, analysis)
    local slot = slots[slotIndex]
    if not (slot and slot.pitchMapEnabled and type(analysis) == "table") then
      return false
    end
    if analysis.reliable ~= true then
      return false
    end
    local midiNote = tonumber(analysis.midiNote)
    if midiNote == nil then
      return false
    end
    local nextRoot = Utils.clamp(math.floor(midiNote + 0.5), 12.0, 96.0)
    slot.rootNote = nextRoot
    if type(setParam) == "function" then
      setParam(ParameterBinder.dynamicSampleRootNotePath(slotIndex), nextRoot)
    elseif ctx.host and ctx.host.setParam then
      ctx.host.setParam(ParameterBinder.dynamicSampleRootNotePath(slotIndex), nextRoot)
    end
    refreshAllVoices(slotIndex)
    return true
  end

  local function pollAnalysis(slotIndex)
    local slot = slots[slotIndex]
    if not (slot and slot.sampleSynth and slot.voices and slot.voices[1]) then
      return false
    end
    local voice = slot.voices[1]
    local playbackNode = voice.samplePlayback and voice.samplePlayback.__node or nil
    local complete, analysis, partials, temporal = slot.sampleSynth.pollAnalysis(playbackNode)
    if complete then
      slot.latestAnalysis = type(analysis) == "table" and analysis or slot.latestAnalysis
      slot.latestPartials = type(partials) == "table" and partials or slot.latestPartials
      slot.latestTemporal = type(temporal) == "table" and temporal or slot.latestTemporal
      if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
        local okPeaks, peaks = pcall(function()
          return getSampleRegionPlaybackPeaks(playbackNode, 512)
        end)
        if okPeaks and type(peaks) == "table" and #peaks > 0 then
          slot.cachedSamplePeaks = peaks
          slot.cachedSamplePeakBuckets = #peaks
        end
      end
      maybeApplyDetectedRoot(slotIndex, slot.latestAnalysis)
      updateReadbacks(slotIndex)
      return true
    end
    return false
  end

  local function captureFromCurrentSource(slotIndex)
    local slot = slots[slotIndex]
    if not (slot and slot.sampleSynth) then
      return false, 0
    end

    local sourceEntry = slot.sampleSynth.getSelectedSourceEntry()
    local captureNode = sourceEntry and sourceEntry.capture and sourceEntry.capture.__node or nil
    if not captureNode then
      print("DynamicSample: no capture node for slot " .. tostring(slotIndex))
      return false, 0
    end

    local function localHostSamplesPerBar()
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

    local captureMode = slot.sampleSynth.getCaptureMode()
    local captureStartOffset = slot.sampleSynth.getCaptureStartOffset()
    local captureBars = slot.sampleSynth.getCaptureBars()
    local samplesBack = 0

    if captureMode == 1 then
      local currentOffset = captureNode:getWriteOffset()
      if captureStartOffset < 0 then
        samplesBack = math.abs(captureStartOffset)
      elseif captureStartOffset == 0 then
        samplesBack = math.max(1, math.floor(captureBars * localHostSamplesPerBar() + 0.5))
      else
        local duration = currentOffset - captureStartOffset
        if duration <= 0 then
          duration = duration + captureNode:getCaptureSize()
        end
        samplesBack = math.max(1, math.floor(duration))
      end
    else
      samplesBack = math.max(1, math.floor(captureBars * localHostSamplesPerBar() + 0.5))
    end

    local copiedAny = false
    for voiceIndex = 1, #(slot.voices or {}) do
      local voice = slot.voices[voiceIndex]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
      if playbackNode then
        local ok, copied = pcall(function()
          return captureNode:copyRecentToLoop(playbackNode, samplesBack, false)
        end)
        if ok and copied then
          copiedAny = true
          voice.sampleCapturedLength = voice.samplePlayback:getLoopLength() or 0
          voice.samplePlayback:setLoopLength(voice.sampleCapturedLength)
          voice.samplePlayback:seek(0)
          voice.samplePhaseVocoder:reset()
          voice.samplePhaseVocoder:setFFTOrder(math.floor(Utils.clamp(tonumber(slot.pvocFFTOrder) or 11, 9, 12)))
          voice.samplePhaseVocoder:setTimeStretch(Utils.clamp(tonumber(slot.pvocTimeStretch) or 1.0, 0.25, 4.0))
          if (tonumber(voice.level) or 0.0) > 0.001 then
            voice.samplePlayback:play()
          end
          refreshVoice(slotIndex, voiceIndex)
        end
      end
    end

    local capturedLengthMs = 0
    if copiedAny then
      local sampleRate = (ctx.host and ctx.host.getSampleRate and tonumber(ctx.host.getSampleRate())) or 48000.0
      capturedLengthMs = math.floor((samplesBack / sampleRate) * 1000 + 0.5)
      slot.lastCapturedLengthMs = capturedLengthMs
      slot.sampleSynth.setLastCapturedLengthMs(capturedLengthMs)
      slot.sampleSynth.resetAnalysisState()
      local voice = slot.voices and slot.voices[1] or nil
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
      slot.sampleSynth.requestAnalysis(playbackNode)
      if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
        local okPeaks, peaks = pcall(function()
          return getSampleRegionPlaybackPeaks(playbackNode, 512)
        end)
        if okPeaks and type(peaks) == "table" and #peaks > 0 then
          slot.cachedSamplePeaks = peaks
          slot.cachedSamplePeakBuckets = #peaks
        end
      end
      updateReadbacks(slotIndex)
    end

    return copiedAny, capturedLengthMs
  end

  local function applyVoiceGate(slotIndex, voiceIndex, gateValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (slot and voice and voice.samplePlayback and voice.gain) then
      return true
    end

    local nextLevel = Utils.clamp01(tonumber(gateValue) or 0.0)
    local previousLevel = Utils.clamp01(tonumber(voice.level) or 0.0)
    voice.gate = nextLevel
    voice.level = nextLevel
    voice.gain:setGain(nextLevel)

    if nextLevel > 0.001 and previousLevel <= 0.001 then
      if slot.retrigger or not voice.samplePlayback:isPlaying() then
        voice.samplePlayback:trigger()
      else
        voice.samplePlayback:play()
      end
      voice.samplePhaseVocoder:reset()
      voice.samplePhaseVocoder:setFFTOrder(math.floor(Utils.clamp(tonumber(slot.pvocFFTOrder) or 11, 9, 12)))
      voice.samplePhaseVocoder:setTimeStretch(Utils.clamp(tonumber(slot.pvocTimeStretch) or 1.0, 0.25, 4.0))
    elseif nextLevel <= 0.001 and previousLevel > 0.001 then
      voice.samplePlayback:stop()
    end

    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applyVoiceVOct(slotIndex, voiceIndex, noteValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (slot and voice) then
      return true
    end
    voice.note = Utils.clamp(tonumber(noteValue) or 60.0, 0.0, 127.0)
    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applySlotParam(slotIndex, suffix, value)
    local slot = slots[slotIndex]
    if not slot then
      return true
    end
    local numeric = tonumber(value) or 0.0
    if suffix == "source" then
      slot.sampleSynth.setSource(Utils.roundIndex(value, 5))
      updateReadbacks(slotIndex)
      return true
    elseif suffix == "captureTrigger" then
      if numeric > 0.5 then
        captureFromCurrentSource(slotIndex)
      end
      return true
    elseif suffix == "captureBars" then
      slot.sampleSynth.setCaptureBars(Utils.clamp(numeric, 0.0625, 16.0))
      return true
    elseif suffix == "captureMode" then
      slot.sampleSynth.setCaptureMode(value)
      return true
    elseif suffix == "captureStartOffset" then
      slot.sampleSynth.setCaptureStartOffset(math.floor(numeric))
      return true
    elseif suffix == "capturedLengthMs" then
      slot.lastCapturedLengthMs = math.max(0, math.floor(numeric))
      return true
    elseif suffix == "captureWriteOffset" then
      return true
    elseif suffix == "pitchMapEnabled" then
      slot.pitchMapEnabled = numeric > 0.5
      if slot.pitchMapEnabled then
        maybeApplyDetectedRoot(slotIndex, slot.latestAnalysis)
      end
      return true
    elseif suffix == "pitchMode" then
      slot.pitchMode = Utils.roundIndex(value, samplePitchModePhaseVocoderHQ)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "pvocFFTOrder" then
      slot.pvocFFTOrder = Utils.clamp(numeric, 9.0, 12.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "pvocTimeStretch" then
      slot.pvocTimeStretch = Utils.clamp(numeric, 0.25, 4.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "rootNote" then
      slot.rootNote = Utils.clamp(numeric, 12.0, 96.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "unison" then
      slot.unison = math.floor(Utils.clamp(numeric, 1.0, 8.0) + 0.5)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "detune" then
      slot.detune = Utils.clamp(numeric, 0.0, 100.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "spread" then
      slot.spread = Utils.clamp(numeric, 0.0, 1.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "playStart" then
      slot.playStart = Utils.clamp01(numeric)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "loopStart" then
      slot.loopStart = Utils.clamp01(numeric)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "loopLen" then
      slot.loopLen = Utils.clamp(numeric, 0.05, 1.0)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "crossfade" then
      slot.crossfade = Utils.clamp(numeric, 0.0, 0.5)
      refreshAllVoices(slotIndex)
      return true
    elseif suffix == "retrigger" then
      slot.retrigger = numeric > 0.5
      return true
    elseif suffix == "output" then
      slot.output:setGain(Utils.clamp01(numeric) * outputTrim)
      return true
    end
    return false
  end

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end

    print(string.format("DynamicSample[%d]: create start", index))
    local slotMix = ctx.primitives.MixerNode.new()
    slotMix:setInputCount(voiceCount)
    local output = ctx.primitives.GainNode.new(2)
    output:setGain(0.8 * outputTrim)
    ctx.graph.connect(slotMix, output)
    print(string.format("DynamicSample[%d]: mix/output ready", index))

    local captureInput = ctx.primitives.PassthroughNode.new(2, 0)
    print(string.format("DynamicSample[%d]: capture input ready", index))
    local slotSampleSynth = SampleSynth.create(ctx, {
      sourceSpecs = buildSourceSpecs(captureInput),
      defaultSourceId = 1,
    })
    print(string.format("DynamicSample[%d]: sample synth ready", index))

    local voices = {}
    for voiceIndex = 1, voiceCount do
      print(string.format("DynamicSample[%d]: voice %d start", index, voiceIndex))
      local samplePlayback = ctx.primitives.SampleRegionPlaybackNode.new(2)
      samplePlayback:setLoopLength(1)
      samplePlayback:setSpeed(1.0)
      samplePlayback:setUnison(1)
      samplePlayback:setDetune(0.0)
      samplePlayback:setSpread(0.0)
      samplePlayback:stop()

      local samplePhaseVocoder = ctx.primitives.PhaseVocoderNode.new(2)
      samplePhaseVocoder:setPitchSemitones(0.0)
      samplePhaseVocoder:setTimeStretch(1.0)
      samplePhaseVocoder:setMix(0.0)
      samplePhaseVocoder:setFFTOrder(11)
      samplePhaseVocoder:reset()

      local gain = ctx.primitives.GainNode.new(2)
      gain:setGain(0.0)

      ctx.graph.connect(samplePlayback, samplePhaseVocoder)
      ctx.graph.connect(samplePhaseVocoder, gain)
      connectMixerInput(slotMix, voiceIndex, gain)
      print(string.format("DynamicSample[%d]: voice %d ready", index, voiceIndex))

      voices[voiceIndex] = {
        samplePlayback = samplePlayback,
        samplePhaseVocoder = samplePhaseVocoder,
        gain = gain,
        note = 60.0,
        freq = noteToFrequency(60.0),
        gate = 0.0,
        level = 0.0,
        sampleCapturedLength = 0,
        playStartNorm = 0.0,
        loopStartNorm = 0.0,
        loopEndNorm = 1.0,
        crossfadeNorm = 0.1,
      }
    end

    print(string.format("DynamicSample[%d]: voices ready", index))
    local dynamicSlot = {
      slotIndex = index,
      mix = slotMix,
      output = output,
      captureInput = captureInput,
      sampleSynth = slotSampleSynth,
      voices = voices,
      rootNote = 60.0,
      unison = 1,
      detune = 0.0,
      spread = 0.0,
      pitchMapEnabled = false,
      pitchMode = samplePitchModeClassic,
      pvocFFTOrder = 11,
      pvocTimeStretch = 1.0,
      playStart = 0.0,
      loopStart = 0.0,
      loopLen = 1.0,
      crossfade = 0.1,
      retrigger = true,
      lastCapturedLengthMs = 0,
      cachedSamplePeaks = {},
      cachedSamplePeakBuckets = 0,
      latestAnalysis = nil,
      latestPartials = nil,
      latestTemporal = nil,
    }
    slots[index] = dynamicSlot
    print(string.format("DynamicSample[%d]: slot table assigned", index))

    refreshAllVoices(index)
    print(string.format("DynamicSample[%d]: refresh complete", index))
    return slots[index]
  end

  local function applyPath(path, value)
    local slotIndex, voiceIndex, suffix = ParameterBinder.matchDynamicSampleVoicePath(path)
    if slotIndex ~= nil then
      if suffix == "gate" then
        return applyVoiceGate(slotIndex, voiceIndex, value)
      elseif suffix == "vOct" then
        return applyVoiceVOct(slotIndex, voiceIndex, value)
      end
      return false
    end

    slotIndex, suffix = ParameterBinder.matchDynamicSamplePath(path)
    if slotIndex == nil then
      return false
    end
    return applySlotParam(slotIndex, suffix, value)
  end

  return {
    createSlot = createSlot,
    applyPath = applyPath,
    pollAnalysis = pollAnalysis,
    updateReadbacks = updateReadbacks,
  }
end

return M

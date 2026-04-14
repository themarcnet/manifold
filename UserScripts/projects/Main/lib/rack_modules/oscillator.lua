local M = {}

function M.create(deps)
  local ctx = deps.ctx
  local slots = deps.slots
  local Utils = deps.Utils
  local ParameterBinder = deps.ParameterBinder
  local noteToFrequency = deps.noteToFrequency
  local connectMixerInput = deps.connectMixerInput
  local voiceCount = deps.voiceCount
  local outputTrim = deps.outputTrim
  local defaultOutput = deps.defaultOutput
  local maxLevel = deps.maxLevel
  local oscRenderStandard = deps.oscRenderStandard

  local function configureOscNode(osc, frequency)
    osc:setWaveform(1)
    osc:setFrequency(frequency)
    osc:setAmplitude(0.0)
    osc:setDrive(0.0)
    osc:setDriveShape(0)
    osc:setDriveBias(0.0)
    osc:setDriveMix(1.0)
    osc:setRenderMode(oscRenderStandard)
    osc:setAdditivePartials(8)
    osc:setAdditiveTilt(0.0)
    osc:setAdditiveDrift(0.0)
    osc:setPulseWidth(0.5)
    osc:setUnison(1)
    osc:setDetune(0.0)
    osc:setSpread(0.0)
  end

  local function createSlot(slotIndex)
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    if slots[index] then
      return slots[index]
    end

    local slotMix = ctx.primitives.MixerNode.new()
    slotMix:setInputCount(voiceCount + 1)
    local output = ctx.primitives.GainNode.new(2)
    output:setGain(defaultOutput * outputTrim)
    ctx.graph.connect(slotMix, output)

    local manualOsc = ctx.primitives.OscillatorNode.new()
    configureOscNode(manualOsc, 261.625565)
    connectMixerInput(slotMix, voiceCount + 1, manualOsc)

    local voices = {}
    for voiceIndex = 1, voiceCount do
      local osc = ctx.primitives.OscillatorNode.new()
      configureOscNode(osc, 220.0)
      connectMixerInput(slotMix, voiceIndex, osc)
      voices[voiceIndex] = {
        osc = osc,
        note = 60.0,
        fm = 0.0,
        pwCv = 0.5,
        basePulseWidth = 0.5,
        gate = 0.0,
        level = 0.0,
      }
    end

    slots[index] = {
      slotIndex = index,
      mix = slotMix,
      output = output,
      voices = voices,
      manualOsc = manualOsc,
      manualPitch = 60.0,
      manualLevel = 0.0,
    }
    return slots[index]
  end

  local function refreshManual(slotIndex)
    local slot = slots[slotIndex]
    if not (slot and slot.manualOsc) then
      return false
    end
    slot.manualOsc:setFrequency(Utils.clamp(noteToFrequency(tonumber(slot.manualPitch) or 60.0), 20.0, 8000.0))
    slot.manualOsc:setAmplitude(Utils.clamp01(tonumber(slot.manualLevel) or 0.0) * maxLevel)
    return true
  end

  local function refreshVoice(slotIndex, voiceIndex)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (voice and voice.osc) then
      return false
    end

    local note = Utils.clamp(tonumber(voice.note) or 60.0, 0.0, 127.0)
    local fm = Utils.clamp(tonumber(voice.fm) or 0.0, -1.0, 1.0)
    local freq = Utils.clamp(noteToFrequency(note + (fm * 12.0)), 20.0, 8000.0)
    local width = Utils.clamp((tonumber(voice.basePulseWidth) or 0.5) + ((tonumber(voice.pwCv) or 0.5) - 0.5), 0.01, 0.99)
    local level = Utils.clamp(tonumber(voice.level) or 0.0, 0.0, maxLevel)

    voice.osc:setFrequency(freq)
    voice.osc:setPulseWidth(width)
    voice.osc:setAmplitude(level)
    return true
  end

  local function applyVoiceGate(slotIndex, voiceIndex, gateValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (voice and voice.osc) then
      return true
    end
    local level = Utils.clamp01(tonumber(gateValue) or 0.0)
    local previousLevel = Utils.clamp01(tonumber(voice.level) or 0.0)
    voice.gate = level
    voice.level = level
    if level > 0.001 and previousLevel <= 0.001 then
      voice.osc:resetPhase()
    end
    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applyVoiceVOct(slotIndex, voiceIndex, noteValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (voice and voice.osc) then
      return true
    end
    voice.note = Utils.clamp(tonumber(noteValue) or 60.0, 0.0, 127.0)
    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applyVoiceFm(slotIndex, voiceIndex, fmValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (voice and voice.osc) then
      return true
    end
    voice.fm = Utils.clamp(tonumber(fmValue) or 0.0, -1.0, 1.0)
    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applyVoicePwCv(slotIndex, voiceIndex, pwCvValue)
    local slot = slots[slotIndex]
    local voice = slot and slot.voices and slot.voices[voiceIndex] or nil
    if not (voice and voice.osc) then
      return true
    end
    voice.pwCv = Utils.clamp01(tonumber(pwCvValue) or 0.5)
    return refreshVoice(slotIndex, voiceIndex)
  end

  local function applySlotParam(slotIndex, suffix, value)
    local slot = slots[slotIndex]
    if not slot then
      return true
    end
    local numeric = tonumber(value) or 0.0
    if suffix == "waveform" then
      local wf = Utils.roundIndex(value, 7)
      for i = 1, #slot.voices do slot.voices[i].osc:setWaveform(wf) end
      if slot.manualOsc then slot.manualOsc:setWaveform(wf) end
      return true
    elseif suffix == "renderMode" then
      local mode = Utils.roundIndex(value, 1)
      for i = 1, #slot.voices do slot.voices[i].osc:setRenderMode(mode) end
      if slot.manualOsc then slot.manualOsc:setRenderMode(mode) end
      return true
    elseif suffix == "additivePartials" then
      local count = math.floor(Utils.clamp(numeric, 1, 32) + 0.5)
      for i = 1, #slot.voices do slot.voices[i].osc:setAdditivePartials(count) end
      if slot.manualOsc then slot.manualOsc:setAdditivePartials(count) end
      return true
    elseif suffix == "additiveTilt" then
      local tilt = Utils.clamp(numeric, -1.0, 1.0)
      for i = 1, #slot.voices do slot.voices[i].osc:setAdditiveTilt(tilt) end
      if slot.manualOsc then slot.manualOsc:setAdditiveTilt(tilt) end
      return true
    elseif suffix == "additiveDrift" then
      local drift = Utils.clamp(numeric, 0.0, 1.0)
      for i = 1, #slot.voices do slot.voices[i].osc:setAdditiveDrift(drift) end
      if slot.manualOsc then slot.manualOsc:setAdditiveDrift(drift) end
      return true
    elseif suffix == "drive" then
      local drive = Utils.clamp(numeric, 0.0, 20.0)
      for i = 1, #slot.voices do slot.voices[i].osc:setDrive(drive) end
      if slot.manualOsc then slot.manualOsc:setDrive(drive) end
      return true
    elseif suffix == "driveShape" then
      local shape = Utils.roundIndex(value, 3)
      for i = 1, #slot.voices do slot.voices[i].osc:setDriveShape(shape) end
      if slot.manualOsc then slot.manualOsc:setDriveShape(shape) end
      return true
    elseif suffix == "driveBias" then
      local bias = Utils.clamp(numeric, -1.0, 1.0)
      for i = 1, #slot.voices do slot.voices[i].osc:setDriveBias(bias) end
      if slot.manualOsc then slot.manualOsc:setDriveBias(bias) end
      return true
    elseif suffix == "pulseWidth" then
      local width = Utils.clamp(numeric, 0.01, 0.99)
      for i = 1, #slot.voices do
        slot.voices[i].basePulseWidth = width
        refreshVoice(slotIndex, i)
      end
      if slot.manualOsc then slot.manualOsc:setPulseWidth(width) end
      return true
    elseif suffix == "unison" then
      local unison = math.floor(Utils.clamp(numeric, 1, 8) + 0.5)
      for i = 1, #slot.voices do slot.voices[i].osc:setUnison(unison) end
      if slot.manualOsc then slot.manualOsc:setUnison(unison) end
      return true
    elseif suffix == "detune" then
      local detune = Utils.clamp(numeric, 0.0, 100.0)
      for i = 1, #slot.voices do slot.voices[i].osc:setDetune(detune) end
      if slot.manualOsc then slot.manualOsc:setDetune(detune) end
      return true
    elseif suffix == "spread" then
      local spread = Utils.clamp01(numeric)
      for i = 1, #slot.voices do slot.voices[i].osc:setSpread(spread) end
      if slot.manualOsc then slot.manualOsc:setSpread(spread) end
      return true
    elseif suffix == "manualPitch" then
      slot.manualPitch = Utils.clamp(numeric, 0.0, 127.0)
      return refreshManual(slotIndex)
    elseif suffix == "manualLevel" then
      slot.manualLevel = Utils.clamp01(numeric)
      return refreshManual(slotIndex)
    elseif suffix == "output" then
      slot.output:setGain(Utils.clamp(numeric, 0.0, 2.0) * outputTrim)
      return true
    end
    return false
  end

  local function applyPath(path, value)
    local slotIndex, voiceIndex, suffix = ParameterBinder.matchDynamicOscillatorVoicePath(path)
    if slotIndex ~= nil then
      if suffix == "gate" then
        return applyVoiceGate(slotIndex, voiceIndex, value)
      elseif suffix == "vOct" then
        return applyVoiceVOct(slotIndex, voiceIndex, value)
      elseif suffix == "fm" then
        return applyVoiceFm(slotIndex, voiceIndex, value)
      elseif suffix == "pwCv" then
        return applyVoicePwCv(slotIndex, voiceIndex, value)
      end
      return false
    end
    slotIndex, suffix = ParameterBinder.matchDynamicOscillatorPath(path)
    if slotIndex == nil then
      return false
    end
    return applySlotParam(slotIndex, suffix, value)
  end

  local function refreshAll()
    for slotIndex = 1, #slots do
      refreshManual(slotIndex)
      for voiceIndex = 1, voiceCount do
        refreshVoice(slotIndex, voiceIndex)
      end
    end
  end

  return {
    createSlot = createSlot,
    applyPath = applyPath,
    refreshAll = refreshAll,
  }
end

return M

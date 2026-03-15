local M = {}

local VOICE_COUNT = 8
local WAVE_OPTIONS = { "Sine", "Saw", "Square", "Triangle", "Blend" }
local WAVE_NAMES = {
  [0] = "Sine",
  [1] = "Saw",
  [2] = "Square",
  [3] = "Triangle",
  [4] = "Blend",
}

local FILTER_OPTIONS = { "SVF Lowpass", "SVF Bandpass", "SVF Highpass", "SVF Notch" }
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
local FX_PARAM_LABELS = {
  [0] = { "Rate", "Depth" },
  [1] = { "Rate", "Depth" },
  [2] = { "Drive", "Curve" },
  [3] = { "Thresh", "Ratio" },
  [4] = { "Width", "MonoLow" },
  [5] = { "Cutoff", "Reso" },
  [6] = { "Cutoff", "Reso" },
  [7] = { "Room", "Damp" },
  [8] = { "Time", "FBack" },
  [9] = { "Taps", "FBack" },
  [10] = { "Pitch", "Window" },
  [11] = { "Grain", "Dense" },
  [12] = { "Freq", "Depth" },
  [13] = { "Vowel", "Shift" },
  [14] = { "Low", "High" },
  [15] = { "Thresh", "Drive" },
  [16] = { "Attack", "Sustain" },
}

local PATHS = {
  waveform = "/midi/synth/waveform",
  filterType = "/midi/synth/filterType",
  cutoff = "/midi/synth/cutoff",
  resonance = "/midi/synth/resonance",
  drive = "/midi/synth/drive",
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

local function clamp(v, lo, hi)
  local n = tonumber(v) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

local function repaint(widget)
  if widget and widget.node and widget.node.repaint then
    widget.node:repaint()
  end
end

local function syncValue(widget, value, epsilon)
  if not (widget and widget.setValue and value ~= nil) then
    return
  end
  local current = widget.getValue and widget:getValue() or nil
  local threshold = epsilon or 0.0001
  if current == nil or math.abs((tonumber(current) or 0) - (tonumber(value) or 0)) > threshold then
    widget:setValue(value)
    repaint(widget)
  end
end

local function syncText(widget, text)
  if not (widget and widget.setText and text ~= nil) then
    return
  end
  local current = widget.getText and widget:getText() or nil
  if current ~= text then
    widget:setText(text)
    repaint(widget)
  end
end

local function syncColour(widget, colour)
  if not (widget and widget.setColour and colour ~= nil) then
    return
  end
  widget:setColour(colour)
  repaint(widget)
end

local function syncSelected(widget, idx)
  if not (widget and widget.setSelected and idx ~= nil) then
    return
  end
  local current = widget.getSelected and widget:getSelected() or nil
  if current ~= idx then
    widget:setSelected(idx)
    repaint(widget)
  end
end

local function syncKnobLabel(widget, label)
  if not (widget and widget.setLabel and label ~= nil) then
    return
  end
  local current = widget.getLabel and widget:getLabel() or nil
  if current ~= label then
    widget:setLabel(label)
    repaint(widget)
  end
end

local function setPath(path, value)
  if type(setParam) == "function" then
    return setParam(path, tonumber(value) or 0)
  end
  if command then
    command("SET", path, tostring(value))
    return true
  end
  return false
end

local function readParam(path, fallback)
  if type(_G.getParam) == "function" then
    local ok, value = pcall(_G.getParam, path)
    if ok and value ~= nil then
      return value
    end
  end
  return fallback
end

local function noteToFreq(note)
  return 440.0 * (2.0 ^ ((note - 69) / 12.0))
end

local function updateDropdownAnchors(widgets)
  widgets = widgets or {}
  if widgets.midiInputDropdown and widgets.midiInputDropdown.setAbsolutePos then
    widgets.midiInputDropdown:setAbsolutePos(580, 44)
  end
  if widgets.waveformDropdown and widgets.waveformDropdown.setAbsolutePos then
    widgets.waveformDropdown:setAbsolutePos(40, 160)
  end
  if widgets.filterTypeDropdown and widgets.filterTypeDropdown.setAbsolutePos then
    widgets.filterTypeDropdown:setAbsolutePos(276, 158)
  end
  if widgets.fx1TypeDropdown and widgets.fx1TypeDropdown.setAbsolutePos then
    widgets.fx1TypeDropdown:setAbsolutePos(808, 138)
  end
  if widgets.fx2TypeDropdown and widgets.fx2TypeDropdown.setAbsolutePos then
    widgets.fx2TypeDropdown:setAbsolutePos(1044, 138)
  end
end

local function updateFxParamLabels(widgets, fx1Type, fx2Type)
  widgets = widgets or {}
  local fx1Labels = FX_PARAM_LABELS[round(fx1Type or 0)] or { "Param 1", "Param 2" }
  local fx2Labels = FX_PARAM_LABELS[round(fx2Type or 0)] or { "Param 1", "Param 2" }

  syncKnobLabel(widgets.fx1Param1, fx1Labels[1] or "Param 1")
  syncKnobLabel(widgets.fx1Param2, fx1Labels[2] or "Param 2")
  syncKnobLabel(widgets.fx2Param1, fx2Labels[1] or "Param 1")
  syncKnobLabel(widgets.fx2Param2, fx2Labels[2] or "Param 2")
end

local function freqToNote(freq)
  if freq <= 0 then return 0 end
  return math.floor(69 + 12 * math.log(freq / 440.0) / math.log(2) + 0.5)
end

local function noteName(note)
  if not note then return "--" end
  local names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
  local name = names[(note % 12) + 1] or "?"
  local octave = math.floor(note / 12) - 1
  return name .. octave
end

local function velocityToAmp(velocity)
  return clamp(0.02 + ((tonumber(velocity) or 0) / 127.0) * 0.23, 0.0, 0.25)
end

local function formatTime(seconds)
  if seconds >= 1 then
    return string.format("%.2fs", seconds)
  else
    return string.format("%dms", round(seconds * 1000))
  end
end

local function projectRoot()
  local path = getCurrentScriptPath and getCurrentScriptPath() or ""
  if path == "" then
    return ""
  end
  return path:gsub("/+$", ""):match("^(.*)/[^/]+$") or ""
end

local function runtimeStatePath()
  local root = projectRoot()
  if root == "" then
    return ""
  end
  return root .. "/editor/runtime_state.lua"
end

local function loadRuntimeState()
  local path = runtimeStatePath()
  if path == "" or type(readTextFile) ~= "function" then
    return {}
  end
  local text = readTextFile(path)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  local chunk, err = load(text, "midi_runtime_state", "t", {})
  if not chunk then
    return {}
  end
  local ok, state = pcall(chunk)
  if not ok or type(state) ~= "table" then
    return {}
  end
  return state
end

local function saveRuntimeState(state)
  local path = runtimeStatePath()
  if path == "" or type(writeTextFile) ~= "function" then
    return false
  end
  
  local lines = {
    "return {",
    string.format("  inputDevice = %q,", tostring(state.inputDevice or "")),
    string.format("  waveform = %d,", tonumber(state.waveform) or 1),
    string.format("  filterType = %d,", tonumber(state.filterType) or 0),
    string.format("  cutoff = %.2f,", tonumber(state.cutoff) or 3200),
    string.format("  resonance = %.3f,", tonumber(state.resonance) or 0.75),
    string.format("  drive = %.2f,", tonumber(state.drive) or 1.8),
    string.format("  output = %.3f,", tonumber(state.output) or 0.8),
    string.format("  attack = %.4f,", tonumber(state.attack) or 0.05),
    string.format("  decay = %.4f,", tonumber(state.decay) or 0.2),
    string.format("  sustain = %.3f,", tonumber(state.sustain) or 0.7),
    string.format("  release = %.4f,", tonumber(state.release) or 0.4),
    string.format("  fx1Type = %d,", tonumber(state.fx1Type) or 0),
    string.format("  fx1Param1 = %.3f,", tonumber(state.fx1Param1) or 0.5),
    string.format("  fx1Param2 = %.3f,", tonumber(state.fx1Param2) or 0.5),
    string.format("  fx1Mix = %.3f,", tonumber(state.fx1Mix) or 0.0),
    string.format("  fx2Type = %d,", tonumber(state.fx2Type) or 0),
    string.format("  fx2Param1 = %.3f,", tonumber(state.fx2Param1) or 0.5),
    string.format("  fx2Param2 = %.3f,", tonumber(state.fx2Param2) or 0.5),
    string.format("  fx2Mix = %.3f,", tonumber(state.fx2Mix) or 0.0),
    string.format("  delayMix = %.3f,", tonumber(state.delayMix) or 0.18),
    string.format("  delayTime = %d,", tonumber(state.delayTime) or 220),
    string.format("  delayFeedback = %.3f,", tonumber(state.delayFeedback) or 0.24),
    string.format("  reverbWet = %.3f,", tonumber(state.reverbWet) or 0.16),
    "}",
  }
  
  return writeTextFile(path, table.concat(lines, "\n"))
end

local function isPluginMode()
  if Audio and Audio.isPlugin then
    return Audio.isPlugin()
  end
  return false
end

local function buildMidiOptions(ctx)
  local devices = Midi and Midi.inputDevices and Midi.inputDevices() or {}
  ctx._midiDevices = devices
  local noneLabel = isPluginMode() and "Use Host MIDI" or "None (Disabled)"
  local options = { noneLabel }
  for _, name in ipairs(devices) do
    options[#options + 1] = name
  end
  return options
end

local function findOptionIndex(options, label)
  if type(label) ~= "string" or label == "" then
    return nil
  end
  for i, option in ipairs(options or {}) do
    if option == label then
      return i
    end
  end
  return nil
end

local function applyMidiSelection(ctx, idx, persist)
  local widgets = ctx.widgets or {}
  local options = ctx._midiOptions or {}
  local label = options[idx] or options[1] or "None (Disabled)"
  
  ctx._selectedMidiInputIdx = idx
  ctx._selectedMidiInputLabel = label
  
  if idx == 1 then
    if Midi and Midi.closeInput then
      Midi.closeInput()
    end
    ctx._lastEvent = isPluginMode() and "Using host MIDI" or "MIDI input disabled"
    syncText(widgets.deviceValue, "Input: " .. label)
    return true
  end
  
  local deviceIndex = idx - 2
  local success = Midi and Midi.openInput and Midi.openInput(deviceIndex) or false
  if success then
    ctx._lastEvent = "Opened: " .. label
    syncText(widgets.deviceValue, "Input: " .. label)
    return true
  end
  
  ctx._lastEvent = "Failed: " .. label
  return false
end

local function refreshMidiDevices(ctx, restoreSelection)
  local widgets = ctx.widgets or {}
  local options = buildMidiOptions(ctx)
  ctx._midiOptions = options
  
  if widgets.midiInputDropdown then
    widgets.midiInputDropdown:setOptions(options)
    repaint(widgets.midiInputDropdown)
  end
  
  local idx = 1
  local saved = restoreSelection and loadRuntimeState() or nil
  if saved and saved.inputDevice then
    local savedIdx = findOptionIndex(options, saved.inputDevice)
    if savedIdx then
      idx = savedIdx
    end
  elseif ctx._selectedMidiInputLabel then
    local currentIdx = findOptionIndex(options, ctx._selectedMidiInputLabel)
    if currentIdx then
      idx = currentIdx
    end
  end
  
  syncSelected(widgets.midiInputDropdown, idx)
  ctx._selectedMidiInputIdx = idx
  ctx._selectedMidiInputLabel = options[idx] or options[1]
  
  if restoreSelection and idx > 1 then
    applyMidiSelection(ctx, idx, false)
  else
    syncText(widgets.deviceValue, "Input: " .. (ctx._selectedMidiInputLabel or options[1] or "None"))
  end
end

-- ADSR envelope calculation
local function calculateEnvelope(ctx, voiceIndex, dt)
  local voice = ctx._voices[voiceIndex]
  if not voice then return 0 end
  
  local adsr = ctx._adsr
  local gate = voice.gate
  local level = voice.envelopeLevel or 0
  local stage = voice.envelopeStage or "idle"
  
  if gate > 0.5 then
    if stage == "idle" or stage == "release" then
      stage = "attack"
      voice.envelopeStartLevel = level
    end
    
    if stage == "attack" then
      local attackTime = math.max(0.001, adsr.attack)
      local progress = (voice.envelopeTime or 0) / attackTime
      if progress >= 1 then
        level = 1
        stage = "decay"
        voice.envelopeTime = 0
        voice.envelopeStartLevel = 1
      else
        level = voice.envelopeStartLevel + (1 - voice.envelopeStartLevel) * progress
      end
    elseif stage == "decay" then
      local decayTime = math.max(0.001, adsr.decay)
      local progress = (voice.envelopeTime or 0) / decayTime
      local sustainLevel = adsr.sustain
      if progress >= 1 then
        level = sustainLevel
        stage = "sustain"
      else
        level = 1 - (1 - sustainLevel) * progress
      end
    elseif stage == "sustain" then
      level = adsr.sustain
    end
  else
    if stage ~= "release" and stage ~= "idle" then
      stage = "release"
      voice.envelopeTime = 0
      voice.envelopeStartLevel = level
    end
    
    if stage == "release" then
      local releaseTime = math.max(0.001, adsr.release)
      local progress = (voice.envelopeTime or 0) / releaseTime
      if progress >= 1 then
        level = 0
        stage = "idle"
      else
        level = voice.envelopeStartLevel * (1 - progress)
      end
    end
  end
  
  voice.envelopeStage = stage
  voice.envelopeLevel = level
  voice.envelopeTime = (voice.envelopeTime or 0) + dt
  
  return level * voice.targetAmp
end

local function updateEnvelopes(ctx, dt)
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice then
      local amp = calculateEnvelope(ctx, i, dt)
      voice.currentAmp = amp
      setPath(voiceAmpPath(i), amp)
    end
  end
end

local function chooseVoice(ctx, note, velocity)
  -- First, try to find an inactive voice
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if not voice.active or voice.envelopeStage == "idle" then
      return i
    end
  end
  
  -- All voices active - use smart stealing
  local adsr = ctx._adsr
  
  -- Option 1: Steal voice in release stage with lowest level
  local bestReleaseIndex = nil
  local bestReleaseLevel = 999
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.envelopeStage == "release" then
      if voice.envelopeLevel < bestReleaseLevel then
        bestReleaseLevel = voice.envelopeLevel
        bestReleaseIndex = i
      end
    end
  end
  if bestReleaseIndex then
    return bestReleaseIndex
  end
  
  -- Option 2: Steal oldest voice (highest stamp)
  local oldestIndex = 1
  local oldestStamp = ctx._voices[1].stamp or 0
  for i = 2, VOICE_COUNT do
    local stamp = ctx._voices[i].stamp or 0
    if stamp < oldestStamp then
      oldestStamp = stamp
      oldestIndex = i
    end
  end
  return oldestIndex
end

local function triggerVoice(ctx, note, velocity)
  local index = chooseVoice(ctx, note, velocity)
  local voice = ctx._voices[index]
  
  ctx._voiceStamp = (ctx._voiceStamp or 0) + 1
  
  voice.active = true
  voice.note = note
  voice.stamp = ctx._voiceStamp
  voice.targetAmp = velocityToAmp(velocity)
  voice.gate = 1
  voice.envelopeStage = "attack"
  voice.envelopeTime = 0
  voice.envelopeStartLevel = 0
  
  setPath(voiceFreqPath(index), noteToFreq(note))
  setPath(voiceGatePath(index), 1)
  
  return index
end

local function releaseVoice(ctx, note)
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.active and voice.note == note then
      voice.gate = 0
      voice.envelopeStage = "release"
      voice.envelopeTime = 0
      voice.envelopeStartLevel = voice.envelopeLevel or voice.targetAmp
      setPath(voiceGatePath(i), 0)
    end
  end
end

local function panicVoices(ctx)
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    voice.active = false
    voice.note = nil
    voice.stamp = 0
    voice.gate = 0
    voice.targetAmp = 0
    voice.currentAmp = 0
    voice.envelopeStage = "idle"
    voice.envelopeLevel = 0
    setPath(voiceAmpPath(i), 0)
    setPath(voiceGatePath(i), 0)
  end
end

local function activeVoiceCount(ctx)
  local count = 0
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.active and voice.envelopeStage ~= "idle" then
      count = count + 1
    end
  end
  return count
end

local function voiceSummary(ctx)
  local notes = {}
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.active and voice.note and voice.envelopeStage ~= "idle" then
      notes[#notes + 1] = noteName(voice.note)
    end
  end
  if #notes == 0 then
    return "Voices: idle"
  end
  return "Voices: " .. table.concat(notes, "  ")
end

local function getOctaveLabel(baseOctave)
  local startNote = "C" .. baseOctave
  local endNote = "C" .. (baseOctave + 2)
  return startNote .. "-" .. endNote
end

local function saveCurrentState(ctx)
  local state = {
    inputDevice = ctx._selectedMidiInputLabel or "",
    waveform = round(readParam(PATHS.waveform, 1)),
    filterType = round(readParam(PATHS.filterType, 0)),
    cutoff = readParam(PATHS.cutoff, 3200),
    resonance = readParam(PATHS.resonance, 0.75),
    drive = readParam(PATHS.drive, 1.8),
    output = readParam(PATHS.output, 0.8),
    attack = readParam(PATHS.attack, 0.05),
    decay = readParam(PATHS.decay, 0.2),
    sustain = readParam(PATHS.sustain, 0.7),
    release = readParam(PATHS.release, 0.4),
    fx1Type = round(readParam(PATHS.fx1Type, 0)),
    fx1Param1 = readParam(PATHS.fx1Param1, 0.5),
    fx1Param2 = readParam(PATHS.fx1Param2, 0.5),
    fx1Mix = readParam(PATHS.fx1Mix, 0.0),
    fx2Type = round(readParam(PATHS.fx2Type, 0)),
    fx2Param1 = readParam(PATHS.fx2Param1, 0.5),
    fx2Param2 = readParam(PATHS.fx2Param2, 0.5),
    fx2Mix = readParam(PATHS.fx2Mix, 0.0),
    delayMix = readParam(PATHS.delayMix, 0.18),
    delayTime = round(readParam(PATHS.delayTimeL, 220)),
    delayFeedback = readParam(PATHS.delayFeedback, 0.24),
    reverbWet = readParam(PATHS.reverbWet, 0.16),
  }
  
  if saveRuntimeState(state) then
    ctx._lastEvent = "State saved"
  else
    ctx._lastEvent = "Save failed"
  end
end

local function loadSavedState(ctx)
  local state = loadRuntimeState()
  if not state or not next(state) then
    ctx._lastEvent = "No saved state"
    return
  end
  
  -- Apply all saved parameters
  if state.waveform then
    setPath(PATHS.waveform, state.waveform)
  end
  if state.cutoff then
    setPath(PATHS.cutoff, state.cutoff)
  end
  if state.resonance then
    setPath(PATHS.resonance, state.resonance)
  end
  if state.drive then
    setPath(PATHS.drive, state.drive)
  end
  if state.output then
    setPath(PATHS.output, state.output)
  end
  if state.attack then
    setPath(PATHS.attack, state.attack)
  end
  if state.decay then
    setPath(PATHS.decay, state.decay)
  end
  if state.sustain then
    setPath(PATHS.sustain, state.sustain)
  end
  if state.release then
    setPath(PATHS.release, state.release)
  end
  if state.chorusMix then
    setPath(PATHS.chorusMix, state.chorusMix)
  end
  if state.delayMix then
    setPath(PATHS.delayMix, state.delayMix)
  end
  if state.delayTime then
    setPath(PATHS.delayTimeL, state.delayTime)
    setPath(PATHS.delayTimeR, state.delayTime * 1.5)
  end
  if state.delayFeedback then
    setPath(PATHS.delayFeedback, state.delayFeedback)
  end
  if state.reverbWet then
    setPath(PATHS.reverbWet, state.reverbWet)
  end
  if state.filterType then
    setPath(PATHS.filterType, state.filterType)
  end
  if state.fx1Type then
    setPath(PATHS.fx1Type, state.fx1Type)
  end
  if state.fx1Param1 then
    setPath(PATHS.fx1Param1, state.fx1Param1)
  end
  if state.fx1Param2 then
    setPath(PATHS.fx1Param2, state.fx1Param2)
  end
  if state.fx1Mix then
    setPath(PATHS.fx1Mix, state.fx1Mix)
  end
  if state.fx2Type then
    setPath(PATHS.fx2Type, state.fx2Type)
  end
  if state.fx2Param1 then
    setPath(PATHS.fx2Param1, state.fx2Param1)
  end
  if state.fx2Param2 then
    setPath(PATHS.fx2Param2, state.fx2Param2)
  end
  if state.fx2Mix then
    setPath(PATHS.fx2Mix, state.fx2Mix)
  end
  
  -- Update ADSR cache
  ctx._adsr.attack = state.attack or 0.05
  ctx._adsr.decay = state.decay or 0.2
  ctx._adsr.sustain = state.sustain or 0.7
  ctx._adsr.release = state.release or 0.4
  
  ctx._lastEvent = "State loaded"
end

local function resetToDefaults(ctx)
  setPath(PATHS.waveform, 1)
  setPath(PATHS.filterType, 0)
  setPath(PATHS.cutoff, 3200)
  setPath(PATHS.resonance, 0.75)
  setPath(PATHS.drive, 1.8)
  setPath(PATHS.output, 0.8)
  setPath(PATHS.attack, 0.05)
  setPath(PATHS.decay, 0.2)
  setPath(PATHS.sustain, 0.7)
  setPath(PATHS.release, 0.4)
  setPath(PATHS.fx1Type, 0)
  setPath(PATHS.fx1Param1, 0.5)
  setPath(PATHS.fx1Param2, 0.5)
  setPath(PATHS.fx1Mix, 0.0)
  setPath(PATHS.fx2Type, 0)
  setPath(PATHS.fx2Param1, 0.5)
  setPath(PATHS.fx2Param2, 0.5)
  setPath(PATHS.fx2Mix, 0.0)
  setPath(PATHS.delayMix, 0.18)
  setPath(PATHS.delayTimeL, 220)
  setPath(PATHS.delayTimeR, 330)
  setPath(PATHS.delayFeedback, 0.24)
  setPath(PATHS.reverbWet, 0.16)
  
  ctx._adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }
  ctx._keyboardOctave = 3
  ctx._lastEvent = "Reset to defaults"
end

local function drawKeyboard(ctx, w, h)
  if w <= 0 or h <= 0 then return end
  
  -- gfx is global in structured UI
  
  -- Draw white keys
  local whiteKeyWidth = w / 14
  local blackKeyWidth = whiteKeyWidth * 0.6
  local baseNote = ctx._keyboardOctave * 12
  
  local whiteKeys = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23 }
  local blackKeys = { 1, 3, 6, 8, 10, 13, 15, 18, 20, 22 }
  local blackKeyPositions = { 1, 2, 3, 4, 5, 8, 9, 10, 11, 12 }
  
  -- White keys
  for i, offset in ipairs(whiteKeys) do
    local note = baseNote + offset
    local x = (i - 1) * whiteKeyWidth
    local isActive = false
    
    -- Check if note is active
    for j = 1, VOICE_COUNT do
      local voice = ctx._voices[j]
      if voice and voice.active and voice.note == note and voice.gate > 0.5 then
        isActive = true
        break
      end
    end
    
    if isActive then
      gfx.setColour(0xff4ade80)
    else
      gfx.setColour(0xfff1f5f9)
    end
    gfx.fillRoundedRect(x + 2, 2, whiteKeyWidth - 4, h - 4, 4)
    gfx.setColour(0xff64748b)
    gfx.drawRoundedRect(x + 2, 2, whiteKeyWidth - 4, h - 4, 4, 1)
  end
  
  -- Black keys
  for i, offset in ipairs(blackKeys) do
    local note = baseNote + offset
    local pos = blackKeyPositions[i]
    local x = pos * whiteKeyWidth - blackKeyWidth / 2
    local isActive = false
    
    for j = 1, VOICE_COUNT do
      local voice = ctx._voices[j]
      if voice and voice.active and voice.note == note and voice.gate > 0.5 then
        isActive = true
        break
      end
    end
    
    if isActive then
      gfx.setColour(0xff22d3ee)
    else
      gfx.setColour(0xff1e293b)
    end
    gfx.fillRoundedRect(x, 2, blackKeyWidth, h * 0.6, 3)
    gfx.setColour(0xff0f172a)
    gfx.drawRoundedRect(x, 2, blackKeyWidth, h * 0.6, 3, 1)
  end
end

local function handleKeyboardClick(ctx, x, y, isDown)
  local widgets = ctx.widgets or {}
  local canvas = widgets.keyboardCanvas
  if not canvas or not canvas.node then return end
  
  local w = canvas.node:getWidth()
  local h = canvas.node:getHeight()
  local whiteKeyWidth = w / 14
  local baseNote = ctx._keyboardOctave * 12
  
  -- Simple white key detection
  if y > h * 0.6 then
    local keyIndex = math.floor(x / whiteKeyWidth) + 1
    local whiteKeys = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23 }
    if keyIndex >= 1 and keyIndex <= #whiteKeys then
      local note = baseNote + whiteKeys[keyIndex]
      if isDown then
        triggerVoice(ctx, note, 100)
        ctx._keyboardNote = note
      else
        releaseVoice(ctx, note)
        if ctx._keyboardNote == note then
          ctx._keyboardNote = nil
        end
      end
    end
  end
end

function M.init(ctx)
  local widgets = ctx.widgets or {}
  ctx._currentNote = nil
  ctx._lastEvent = "No MIDI yet"
  ctx._voiceStamp = 0
  ctx._voices = {}
  ctx._selectedMidiInputIdx = 1
  ctx._selectedMidiInputLabel = "None (Disabled)"
  ctx._adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }
  ctx._keyboardOctave = 3
  ctx._keyboardNote = nil
  ctx._lastUpdateTime = getTime and getTime() or 0
  
  for i = 1, VOICE_COUNT do
    ctx._voices[i] = {
      active = false,
      note = nil,
      stamp = 0,
      gate = 0,
      targetAmp = 0,
      currentAmp = 0,
      envelopeStage = "idle",
      envelopeLevel = 0,
      envelopeTime = 0,
      envelopeStartLevel = 0,
    }
  end
  
  if Midi and Midi.clearCallbacks then
    Midi.clearCallbacks()
  end
  
  -- Waveform dropdown
  if widgets.waveformDropdown then
    widgets.waveformDropdown._onSelect = function(idx)
      setPath(PATHS.waveform, idx - 1)
    end
  end
  
  -- Parameter knobs
  if widgets.drive then
    widgets.drive._onChange = function(v) setPath(PATHS.drive, v) end
  end
  if widgets.output then
    widgets.output._onChange = function(v) setPath(PATHS.output, v) end
  end
  if widgets.cutoff then
    widgets.cutoff._onChange = function(v) setPath(PATHS.cutoff, v) end
  end
  if widgets.resonance then
    widgets.resonance._onChange = function(v) setPath(PATHS.resonance, v) end
  end
  
  -- ADSR knobs
  if widgets.attack then
    widgets.attack._onChange = function(v)
      setPath(PATHS.attack, v)
      ctx._adsr.attack = v
    end
  end
  if widgets.decay then
    widgets.decay._onChange = function(v)
      setPath(PATHS.decay, v)
      ctx._adsr.decay = v
    end
  end
  if widgets.sustain then
    widgets.sustain._onChange = function(v)
      setPath(PATHS.sustain, v)
      ctx._adsr.sustain = v
    end
  end
  if widgets.release then
    widgets.release._onChange = function(v)
      setPath(PATHS.release, v)
      ctx._adsr.release = v
    end
  end
  
  -- Filter dropdown
  if widgets.filterTypeDropdown then
    widgets.filterTypeDropdown._onSelect = function(idx)
      setPath(PATHS.filterType, idx - 1)
    end
  end

  -- FX1 dropdown and params
  if widgets.fx1TypeDropdown then
    widgets.fx1TypeDropdown._onSelect = function(idx)
      setPath(PATHS.fx1Type, idx - 1)
    end
  end
  if widgets.fx1Param1 then
    widgets.fx1Param1._onChange = function(v) setPath(PATHS.fx1Param1, v) end
  end
  if widgets.fx1Param2 then
    widgets.fx1Param2._onChange = function(v) setPath(PATHS.fx1Param2, v) end
  end
  if widgets.fx1Mix then
    widgets.fx1Mix._onChange = function(v) setPath(PATHS.fx1Mix, v) end
  end

  -- FX2 dropdown and params
  if widgets.fx2TypeDropdown then
    widgets.fx2TypeDropdown._onSelect = function(idx)
      setPath(PATHS.fx2Type, idx - 1)
    end
  end
  if widgets.fx2Param1 then
    widgets.fx2Param1._onChange = function(v) setPath(PATHS.fx2Param1, v) end
  end
  if widgets.fx2Param2 then
    widgets.fx2Param2._onChange = function(v) setPath(PATHS.fx2Param2, v) end
  end
  if widgets.fx2Mix then
    widgets.fx2Mix._onChange = function(v) setPath(PATHS.fx2Mix, v) end
  end

  -- Delay/Reverb
  if widgets.delayMix then
    widgets.delayMix._onChange = function(v) setPath(PATHS.delayMix, v) end
  end
  if widgets.reverbWet then
    widgets.reverbWet._onChange = function(v) setPath(PATHS.reverbWet, v) end
  end
  if widgets.delayTime then
    widgets.delayTime._onChange = function(v)
      setPath(PATHS.delayTimeL, v)
      setPath(PATHS.delayTimeR, v * 1.5)
    end
  end
  if widgets.delayFeedback then
    widgets.delayFeedback._onChange = function(v) setPath(PATHS.delayFeedback, v) end
  end
  
  -- Performance buttons
  if widgets.testNote then
    widgets.testNote._onPress = function()
      triggerVoice(ctx, 60, 100)
      ctx._lastEvent = "Test: C4"
    end
    widgets.testNote._onRelease = function()
      releaseVoice(ctx, 60)
    end
  end
  
  if widgets.panic then
    widgets.panic._onClick = function()
      panicVoices(ctx)
      ctx._lastEvent = "Panic: all off"
    end
  end
  
  -- MIDI controls
  if widgets.refreshMidi then
    widgets.refreshMidi._onClick = function()
      refreshMidiDevices(ctx, false)
      ctx._lastEvent = "MIDI refreshed"
    end
  end
  
  if widgets.midiInputDropdown then
    widgets.midiInputDropdown._onSelect = function(idx)
      applyMidiSelection(ctx, idx, true)
      syncSelected(widgets.midiInputDropdown, idx)
    end
  end
  
  -- Octave buttons
  if widgets.octaveDown then
    widgets.octaveDown._onClick = function()
      ctx._keyboardOctave = math.max(0, ctx._keyboardOctave - 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave))
    end
  end
  
  if widgets.octaveUp then
    widgets.octaveUp._onClick = function()
      ctx._keyboardOctave = math.min(6, ctx._keyboardOctave + 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave))
    end
  end
  
  -- Keyboard canvas - set up custom drawing
  if widgets.keyboardCanvas and widgets.keyboardCanvas.node then
    local canvas = widgets.keyboardCanvas
    canvas.node:setOnDraw(function(node)
      local w = node:getWidth()
      local h = node:getHeight()
      drawKeyboard(ctx, w, h)
    end)
    canvas.node:setInterceptsMouse(true, false)
    canvas.node:setOnMouseDown(function(x, y)
      handleKeyboardClick(ctx, x, y, true)
    end)
    canvas.node:setOnMouseUp(function(x, y)
      handleKeyboardClick(ctx, x, y, false)
    end)
  end
  
  -- State buttons
  if widgets.savePreset then
    widgets.savePreset._onClick = function()
      saveCurrentState(ctx)
    end
  end
  
  if widgets.loadPreset then
    widgets.loadPreset._onClick = function()
      loadSavedState(ctx)
    end
  end
  
  if widgets.resetPreset then
    widgets.resetPreset._onClick = function()
      resetToDefaults(ctx)
    end
  end
  
  updateDropdownAnchors(widgets)
  updateFxParamLabels(widgets, 0, 0)
  refreshMidiDevices(ctx, true)
  loadSavedState(ctx)
end

function M.resized(ctx, w, h)
  updateDropdownAnchors(ctx.widgets or {})
end

function M.update(ctx, rawState)
  local widgets = ctx.widgets or {}
  local now = getTime and getTime() or 0
  local dt = now - (ctx._lastUpdateTime or now)
  ctx._lastUpdateTime = now
  
  -- Update envelopes
  updateEnvelopes(ctx, dt)
  
  -- Read parameters
  local waveform = round(readParam(PATHS.waveform, 1))
  local filterType = round(readParam(PATHS.filterType, 0))
  local cutoff = readParam(PATHS.cutoff, 3200)
  local resonance = readParam(PATHS.resonance, 0.75)
  local drive = readParam(PATHS.drive, 1.8)
  local fx1Type = round(readParam(PATHS.fx1Type, 0))
  local fx1Param1 = readParam(PATHS.fx1Param1, 0.5)
  local fx1Param2 = readParam(PATHS.fx1Param2, 0.5)
  local fx1Mix = readParam(PATHS.fx1Mix, 0.0)
  local fx2Type = round(readParam(PATHS.fx2Type, 0))
  local fx2Param1 = readParam(PATHS.fx2Param1, 0.5)
  local fx2Param2 = readParam(PATHS.fx2Param2, 0.5)
  local fx2Mix = readParam(PATHS.fx2Mix, 0.0)
  local delayTime = readParam(PATHS.delayTimeL, 220)
  local delayFeedback = readParam(PATHS.delayFeedback, 0.24)
  local delayMix = readParam(PATHS.delayMix, 0.18)
  local reverbWet = readParam(PATHS.reverbWet, 0.16)
  local output = readParam(PATHS.output, 0.8)
  local attack = readParam(PATHS.attack, 0.05)
  local decay = readParam(PATHS.decay, 0.2)
  local sustain = readParam(PATHS.sustain, 0.7)
  local release = readParam(PATHS.release, 0.4)
  
  ctx._adsr.attack = attack
  ctx._adsr.decay = decay
  ctx._adsr.sustain = sustain
  ctx._adsr.release = release
  
  -- Find dominant voice for display
  local maxAmp = 0
  local dominantFreq = 220
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.currentAmp > maxAmp then
      maxAmp = voice.currentAmp
      dominantFreq = readParam(voiceFreqPath(i), dominantFreq)
    end
  end
  
  -- Sync UI
  syncSelected(widgets.waveformDropdown, waveform + 1)
  syncSelected(widgets.filterTypeDropdown, filterType + 1)
  syncValue(widgets.drive, drive)
  syncValue(widgets.output, output)
  syncValue(widgets.cutoff, cutoff)
  syncValue(widgets.resonance, resonance)
  updateFxParamLabels(widgets, fx1Type, fx2Type)
  syncSelected(widgets.fx1TypeDropdown, fx1Type + 1)
  syncValue(widgets.fx1Param1, fx1Param1)
  syncValue(widgets.fx1Param2, fx1Param2)
  syncValue(widgets.fx1Mix, fx1Mix)
  syncSelected(widgets.fx2TypeDropdown, fx2Type + 1)
  syncValue(widgets.fx2Param1, fx2Param1)
  syncValue(widgets.fx2Param2, fx2Param2)
  syncValue(widgets.fx2Mix, fx2Mix)
  syncValue(widgets.delayMix, delayMix)
  syncValue(widgets.reverbWet, reverbWet)
  syncValue(widgets.delayTime, delayTime)
  syncValue(widgets.delayFeedback, delayFeedback)
  syncValue(widgets.attack, attack)
  syncValue(widgets.decay, decay)
  syncValue(widgets.sustain, sustain)
  syncValue(widgets.release, release)
  
  -- Value labels
  syncText(widgets.attackValue, formatTime(attack))
  syncText(widgets.decayValue, formatTime(decay))
  syncText(widgets.sustainValue, string.format("%.0f%%", sustain * 100))
  syncText(widgets.releaseValue, formatTime(release))
  
  -- Process MIDI
  if Midi and Midi.pollInputEvent then
    while true do
      local event = Midi.pollInputEvent()
      if not event then break end
      
      if event.type == Midi.NOTE_ON and event.data2 > 0 then
        ctx._currentNote = event.data1
        triggerVoice(ctx, event.data1, event.data2)
        ctx._lastEvent = string.format("Note: %s vel %d", noteName(event.data1), event.data2)
      elseif event.type == Midi.NOTE_OFF or (event.type == Midi.NOTE_ON and event.data2 == 0) then
        releaseVoice(ctx, event.data1)
        if ctx._currentNote == event.data1 then
          ctx._currentNote = nil
        end
      elseif event.type == Midi.CONTROL_CHANGE then
        ctx._lastEvent = string.format("CC %d = %d", event.data1, event.data2)
      end
    end
  end
  
  -- Update status
  local activeCount = activeVoiceCount(ctx)
  if widgets.midiState then
    if activeCount > 0 then
      syncText(widgets.midiState, "active")
      syncColour(widgets.midiState, 0xff4ade80)
    elseif ctx._selectedMidiInputIdx and ctx._selectedMidiInputIdx > 1 then
      syncText(widgets.midiState, "armed")
      syncColour(widgets.midiState, 0xff38bdf8)
    else
      syncText(widgets.midiState, isPluginMode() and "host" or "waiting")
      syncColour(widgets.midiState, 0xfff59e0b)
    end
  end
  
  syncText(widgets.voicesValue, "8 voice poly")
  syncText(widgets.currentNote, "Note: " .. (ctx._currentNote and noteName(ctx._currentNote) or "--"))
  syncText(widgets.voiceStatus, voiceSummary(ctx))
  syncText(widgets.midiEvent, ctx._lastEvent)
  syncText(widgets.freqValue, string.format("Freq: %.2f Hz", dominantFreq))
  syncText(widgets.ampValue, string.format("Amp: %.3f", maxAmp))
  local filterName = FILTER_OPTIONS[filterType + 1] or "SVF"
  syncText(widgets.filterValue, string.format("Filter: %s / %d Hz / Res %.2f", filterName, round(cutoff), resonance))
  syncText(widgets.adsrValue, string.format("ADSR: A %s / D %s / S %.0f%% / R %s",
    formatTime(attack), formatTime(decay), sustain * 100, formatTime(release)))
  local fx1Name = FX_OPTIONS[fx1Type + 1] or "None"
  local fx2Name = FX_OPTIONS[fx2Type + 1] or "None"
  syncText(widgets.fxValue, string.format("FX1: %s / FX2: %s / Dly %.0f%% / Verb %.0f%%",
    fx1Name, fx2Name, delayMix * 100, reverbWet * 100))
  syncText(widgets.deviceValue, "Input: " .. (ctx._selectedMidiInputLabel or "None"))
  
  -- Keyboard is drawn via setOnDraw callback, just trigger repaint
  if widgets.keyboardCanvas then
    repaint(widgets.keyboardCanvas)
  end
end

function M.cleanup(ctx)
  if Midi and Midi.clearCallbacks then
    Midi.clearCallbacks()
  end
end

return M

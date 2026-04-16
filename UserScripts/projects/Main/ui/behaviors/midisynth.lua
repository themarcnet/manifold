local RackLayout = require("behaviors.rack_layout")
local MidiSynthRackSpecs = require("behaviors.rack_midisynth_specs")
local RackWireLayer = require("behaviors.rack_wire_layer")
local KeyboardInput = require("behaviors.keyboard_input")
local VoiceManager = require("behaviors.voice_manager")
local FxDefs = require("fx_definitions")
local ScopedWidget = require("ui.scoped_widget")
local WidgetSync = require("ui.widget_sync")
local MidiDevices = require("ui.midi_devices")
local RackLayoutManager = require("ui.rack_layout_manager")
local InitBindings = require("ui.init_bindings")
local InitControls = require("ui.init_controls")
local PatchbayRuntime = require("ui.patchbay_runtime")
local RackModPopover = require("ui.rack_mod_popover")
local ParameterBinder = require("parameter_binder")
local ModEndpointRegistry = require("modulation.endpoint_registry")
local ModRouteCompiler = require("modulation.route_compiler")
local ModRuntime = require("modulation.runtime")
local RackControlRouter = require("modulation.rack_control_router")
local MidiParamRack = require("ui.midi_param_rack")
local RackModuleFactory = require("ui.rack_module_factory")
local RackLayoutEngine = require("behaviors.rack_layout_engine")
local StateManager = require("behaviors.state_manager")
local PatchbayBinding = require("behaviors.patchbay_binding")

local M = {}
require("behaviors.palette_browser").attach(M)
require("behaviors.voice_manager").attach(M)
local ModulationRouter = require("behaviors.modulation_router")
require("behaviors.modulation_router").attach(M)
require("behaviors.dynamic_module_binding").attach(M)
require("behaviors.rack_mutation_runtime").attach(M)
require("behaviors.rack_layout_engine").attach(M)
require("behaviors.state_manager").attach(M)
require("behaviors.patchbay_binding").attach(M)

local resolveGlobalPrefix = ScopedWidget.resolveGlobalPrefix
local endsWith = ScopedWidget.endsWith
local getScopedWidget = ScopedWidget.getScopedWidget
local getScopedBehavior = ScopedWidget.getScopedBehavior
local setWidgetValueSilently = ScopedWidget.setWidgetValueSilently

local VOICE_COUNT = 8
local WAVE_OPTIONS = { "Sine", "Saw", "Square", "Triangle", "Blend", "Noise", "Pulse", "SuperSaw" }
local OSC_MODE_OPTIONS = { "Classic", "Sample Loop", "Blend" }
local BLEND_MODE_OPTIONS = { "Mix", "Ring", "FM", "Sync", "Add", "Morph" }
local DRIVE_SHAPE_OPTIONS = { "Soft", "Hard", "Clip", "Fold" }
local SAMPLE_SOURCE_OPTIONS = { "Live", "Layer 1", "Layer 2", "Layer 3", "Layer 4" }
local WAVE_NAMES = {
  [0] = "Sine",
  [1] = "Saw",
  [2] = "Square",
  [3] = "Triangle",
  [4] = "Blend",
  [5] = "Noise",
  [6] = "Pulse",
  [7] = "SuperSaw",
}

local function sanitizeBlendMode(value)
  local mode = math.floor((tonumber(value) or 0) + 0.5)
  if mode < 0 or mode >= #BLEND_MODE_OPTIONS then
    return 0
  end
  return mode
end

local FILTER_OPTIONS = { "SVF Lowpass", "SVF Bandpass", "SVF Highpass", "SVF Notch" }
local AUX_AUDIO_SOURCE_CODES = ParameterBinder.AUX_AUDIO_SOURCE_CODES or {}

local PATHS = {
  waveform = "/midi/synth/waveform",
  filterType = "/midi/synth/filterType",
  cutoff = "/midi/synth/cutoff",
  resonance = "/midi/synth/resonance",
  drive = "/midi/synth/drive",
  driveShape = "/midi/synth/driveShape",
  driveBias = "/midi/synth/driveBias",
  fx1Type = "/midi/synth/fx1/type",
  fx1Mix = "/midi/synth/fx1/mix",
  fx2Type = "/midi/synth/fx2/type",
  fx2Mix = "/midi/synth/fx2/mix",
  delayTimeL = "/midi/synth/delay/timeL",
  delayTimeR = "/midi/synth/delay/timeR",
  delayFeedback = "/midi/synth/delay/feedback",
  delayMix = "/midi/synth/delay/mix",
  reverbWet = "/midi/synth/reverb/wet",
  eqOutput = "/midi/synth/eq8/output",
  eqMix = "/midi/synth/eq8/mix",
  output = "/midi/synth/output",
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
  -- New oscillator parameters
  pulseWidth = "/midi/synth/pulseWidth",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  oscRenderMode = "/midi/synth/osc/renderMode",
  additivePartials = "/midi/synth/osc/add/partials",
  additiveTilt = "/midi/synth/osc/add/tilt",
  additiveDrift = "/midi/synth/osc/add/drift",

  oscMode = "/midi/synth/osc/mode",
  sampleSource = "/midi/synth/sample/source",
  sampleCaptureTrigger = "/midi/synth/sample/captureTrigger",
  sampleCaptureBars = "/midi/synth/sample/captureBars",
  sampleCaptureMode = "/midi/synth/sample/captureMode",
  sampleCaptureWriteOffset = "/midi/synth/sample/captureWriteOffset",
  sampleCaptureStartOffset = "/midi/synth/sample/captureStartOffset",
  sampleCapturedLengthMs = "/midi/synth/sample/capturedLengthMs",
  sampleCaptureRecording = "/midi/synth/sample/captureRecording",
  samplePitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
  samplePitchMode = "/midi/synth/sample/pitchMode",
  samplePvocFFTOrder = "/midi/synth/sample/pvoc/fftOrder",
  samplePvocTimeStretch = "/midi/synth/sample/pvoc/timeStretch",
  sampleRootNote = "/midi/synth/sample/rootNote",
  sampleLoopStart = "/midi/synth/sample/loopStart",
  sampleLoopLen = "/midi/synth/sample/loopLen",
  samplePlayStart = "/midi/synth/sample/playStart",
  sampleCrossfade = "/midi/synth/sample/crossfade",
  sampleRetrigger = "/midi/synth/sample/retrigger",

  blendMode = "/midi/synth/blend/mode",
  blendAmount = "/midi/synth/blend/amount",
  waveToSample = "/midi/synth/blend/waveToSample",
  sampleToWave = "/midi/synth/blend/sampleToWave",
  blendKeyTrack = "/midi/synth/blend/keyTrack",
  blendSamplePitch = "/midi/synth/blend/samplePitch",
  blendModAmount = "/midi/synth/blend/modAmount",
  envFollow = "/midi/synth/blend/envFollow",
  addFlavor = "/midi/synth/blend/addFlavor",
  xorBehavior = "/midi/synth/blend/xorBehavior",
  morphCurve = "/midi/synth/blend/morphCurve",
  morphConvergence = "/midi/synth/blend/morphConvergence",
  morphPhase = "/midi/synth/blend/morphPhase",
  rackAudioEdgeMask = "/midi/synth/rack/audio/edgeMask",
  rackAudioStageCount = "/midi/synth/rack/stageCount",
  rackAudioOutputEnabled = "/midi/synth/rack/outputEnabled",
  rackAudioSourceCount = "/midi/synth/rack/sourceCount",
  rackRegistryRequestKind = "/midi/synth/rack/registry/requestKind",
  rackRegistryRequestIndex = "/midi/synth/rack/registry/requestIndex",
  rackRegistryRequestNonce = "/midi/synth/rack/registry/requestNonce",
  morphSpeed = "/midi/synth/blend/morphSpeed",
  morphContrast = "/midi/synth/blend/morphContrast",
  morphSmooth = "/midi/synth/blend/morphSmooth",
}

local function auxAudioSourceCodeForEndpoint(moduleId, portId)
  local id = tostring(moduleId or "")
  local pid = tostring(portId or "")
  if id == "oscillator" then
    return AUX_AUDIO_SOURCE_CODES.OSCILLATOR or 1
  end
  if id == "filter" then
    return AUX_AUDIO_SOURCE_CODES.FILTER or 2
  end
  if id == "fx1" then
    return AUX_AUDIO_SOURCE_CODES.FX1 or 3
  end
  if id == "fx2" then
    return AUX_AUDIO_SOURCE_CODES.FX2 or 4
  end
  if id == "eq" then
    return AUX_AUDIO_SOURCE_CODES.EQ or 5
  end

  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[id] or nil
  local slotIndex = math.max(1, math.floor(tonumber(type(entry) == "table" and entry.slotIndex or 0) or 1))
  local specId = tostring(type(entry) == "table" and entry.specId or "")

  if specId == "rack_oscillator" then
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_OSC_BASE or 100) + slotIndex
  end
  if specId == "rack_sample" then
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_SAMPLE_BASE or 200) + slotIndex
  end
  if specId == "blend_simple" then
    if pid == "b" then
      return AUX_AUDIO_SOURCE_CODES.NONE or 0
    end
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_BLEND_SIMPLE_BASE or 300) + slotIndex
  end
  if specId == "filter" then
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FILTER_BASE or 400) + slotIndex
  end
  if specId == "fx" then
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FX_BASE or 500) + slotIndex
  end
  if specId == "eq" then
    return (AUX_AUDIO_SOURCE_CODES.DYNAMIC_EQ_BASE or 600) + slotIndex
  end

  return AUX_AUDIO_SOURCE_CODES.NONE or 0
end

local function syncAuxAudioRouteParams(ctx)
  return M.syncAuxAudioRouteParams(ctx)
end

local MAX_FX_PARAMS = 5
local BG_TICK_INTERVAL = 1.0 / 60.0
local BG_TICK_INTERVAL_WHILE_INTERACTING = 1.0 / 30.0
local VOICE_AMP_SEND_EPSILON = 0.0015
local VOICE_AMP_SEND_INTERVAL = 1.0 / 60.0
local OSC_REPAINT_INTERVAL = 1.0 / 60.0
local OSC_REPAINT_INTERVAL_MULTI_VOICE = 1.0 / 30.0
local OSC_REPAINT_INTERVAL_WHILE_INTERACTING = 1.0 / 20.0
local ENV_REPAINT_INTERVAL = 1.0 / 60.0
local ENV_REPAINT_INTERVAL_WHILE_INTERACTING = 1.0 / 30.0

_G.__midiSynthRackWireLayer = RackWireLayer

local activeBehaviorCtx = nil

local function fxParamPath(slot, paramIdx)
  return string.format("/midi/synth/fx%d/p/%d", slot, paramIdx - 1)
end

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



-- Widget sync functions now in WidgetSync module
local clamp = WidgetSync.clamp
local round = WidgetSync.round
local repaint = WidgetSync.repaint
local syncValue = WidgetSync.syncValue
local syncToggleValue = WidgetSync.syncToggleValue
local syncText = WidgetSync.syncText
local syncColour = WidgetSync.syncColour
local syncSelected = WidgetSync.syncSelected
local syncKnobLabel = WidgetSync.syncKnobLabel

local function getVoiceStackingLabels(activeTab, oscRenderMode, blendMode)
  if activeTab == 1 and oscRenderMode == 1 then
    return "Ensemble", "Width", "Stereo"
  end
  if activeTab == 3 and (blendMode == 4 or blendMode == 5) then
    return "Density", "Diverge", "Stereo"
  end
  return "Unison", "Detune", "Spread"
end

local function setWidgetInteractiveState(widget, enabled)
  if not widget then
    return
  end
  if widget.setEnabled then
    widget:setEnabled(enabled)
  end
  if widget.node and widget.node.setStyle then
    widget.node:setStyle({ opacity = enabled and 1.0 or 0.35 })
  end
  repaint(widget)
end

local function setPath(path, value, meta)
  local numericValue = tonumber(value) or 0
  local writeMeta = type(meta) == "table" and meta or {}
  local currentCtx = activeBehaviorCtx

  local writeSource = tostring(writeMeta.source or "")
  if currentCtx ~= nil and writeSource ~= "modulation_runtime" and writeSource ~= "legacy_keyboard_parity" and writeSource ~= "adsr_rackosc_parity" then
    if currentCtx._rackModRuntime and currentCtx._rackModRuntime.recordAuthoredValue then
      currentCtx._rackModRuntime:recordAuthoredValue(path, numericValue, writeMeta)
    end
    if currentCtx._modRuntime and currentCtx._modRuntime.recordAuthoredValue then
      currentCtx._modRuntime:recordAuthoredValue(path, numericValue, writeMeta)
    end
  end

  if type(setParam) == "function" then
    return setParam(path, numericValue)
  end
  if command then
    command("SET", path, tostring(numericValue))
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

-- Voice utility functions (needed early by applyVoiceModulationTarget)
local function noteToFreq(note)
  return 440.0 * (2.0 ^ (((tonumber(note) or 69.0) - 69.0) / 12.0))
end

local function velocityToAmp(velocity)
  local v = tonumber(velocity) or 0
  return math.max(0, math.min(0.40, 0.03 + (v / 127.0) * 0.37))
end

local SAMPLE_LOOP_MIN_LEN = 0.05
local SAMPLE_LOOP_MAX_START = 0.95

local function getSampleLoopWindow()
  local start = clamp(readParam(PATHS.sampleLoopStart, 0.0), 0.0, SAMPLE_LOOP_MAX_START)
  local len = clamp(readParam(PATHS.sampleLoopLen, 1.0), SAMPLE_LOOP_MIN_LEN, 1.0)
  len = math.min(len, math.max(SAMPLE_LOOP_MIN_LEN, 1.0 - start))
  return start, len
end

local function setSampleLoopStartLinked(start)
  local currentStart, currentLen = getSampleLoopWindow()
  local loopEnd = clamp(currentStart + currentLen, SAMPLE_LOOP_MIN_LEN, 1.0)
  local nextStart = clamp(start, 0.0, math.min(SAMPLE_LOOP_MAX_START, loopEnd - SAMPLE_LOOP_MIN_LEN))
  local nextLen = clamp(loopEnd - nextStart, SAMPLE_LOOP_MIN_LEN, 1.0)
  setPath(PATHS.sampleLoopStart, nextStart)
  setPath(PATHS.sampleLoopLen, nextLen)
  return nextStart, nextLen
end

local function setSampleLoopLenLinked(len)
  local currentStart = clamp(readParam(PATHS.sampleLoopStart, 0.0), 0.0, SAMPLE_LOOP_MAX_START)
  local maxLen = math.max(SAMPLE_LOOP_MIN_LEN, 1.0 - currentStart)
  local nextLen = clamp(len, SAMPLE_LOOP_MIN_LEN, maxLen)
  setPath(PATHS.sampleLoopLen, nextLen)
  return currentStart, nextLen
end

local function syncLegacyBlendDirectionFromBlend(blendAmount)
  local blend = clamp(blendAmount, 0.0, 1.0)
  setPath(PATHS.waveToSample, blend)
  setPath(PATHS.sampleToWave, 1.0 - blend)
  return blend, 1.0 - blend
end

local function updateDropdownAnchors(ctx)
  local _ = ctx
  -- Dropdown popup placement is now handled in the widget itself.
  -- Keep this hook as a no-op so older call sites do not explode.
end



local function noteName(note)
  if not note then return "--" end
  local names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
  local name = names[(note % 12) + 1] or "?"
  local octave = math.floor(note / 12) - 1
  return name .. octave
end

local function formatMidiNoteValue(value)
  local midi = round(clamp(value or 0, 0, 127))
  return string.format("%s (%d)", noteName(midi), midi)
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

-- MIDI device functions now in MidiDevices module
local isPluginMode = MidiDevices.isPluginMode
local buildMidiOptions = MidiDevices.buildMidiOptions
local findOptionIndex = MidiDevices.findOptionIndex
local getCurrentMidiInputLabel = MidiDevices.getCurrentMidiInputLabel
local persistMidiInputSelection = MidiDevices.persistMidiInputSelection
local applyMidiSelection = MidiDevices.applyMidiSelection
local refreshMidiDevices = MidiDevices.refreshMidiDevices
local maybeRefreshMidiDevices = MidiDevices.maybeRefreshMidiDevices

local syncKeyboardDisplay
local function syncPatchViewMode(ctx)
  return M.syncPatchViewMode(ctx)
end

local function getOctaveLabel(baseOctave, ctx)
  local keyCount = ctx and ctx._keyboardKeyCount or 14
  local whiteKeysPerOctave = 7
  local octaves = keyCount / whiteKeysPerOctave
  local startNote = "C" .. baseOctave
  local endOctave = baseOctave + math.floor(octaves)
  local endNoteIndex = ((keyCount - 1) % 7) + 1
  local noteNames = {"C", "D", "E", "F", "G", "A", "B"}
  local endNote = noteNames[endNoteIndex] .. endOctave
  return startNote .. "-" .. endNote
end

local RACK_MODULE_SHELL_LAYOUT

-- Same-row drag reorder state
local RACK_COLUMNS_PER_ROW = 5

local CANONICAL_RACK_HEIGHT = RackLayoutManager.CANONICAL_RACK_HEIGHT
local RACK_SLOT_W = RackLayoutManager.RACK_SLOT_W
local RACK_SLOT_H = RackLayoutManager.RACK_SLOT_H
local RACK_ROW_GAP = RackLayoutManager.RACK_ROW_GAP
local RACK_ROW_PADDING_X = RackLayoutManager.RACK_ROW_PADDING_X

RACK_MODULE_SHELL_LAYOUT = {
  adsr = { shellId = "adsrShell", badgeSuffix = ".adsrShell.sizeBadge", row = 0, accentColor = 0xfffda4af },
  oscillator = { shellId = "oscillatorShell", badgeSuffix = ".oscillatorShell.sizeBadge", row = 0, accentColor = 0xff7dd3fc },
  filter = { shellId = "filterShell", badgeSuffix = ".filterShell.sizeBadge", row = 0, accentColor = 0xffa78bfa },
  fx1 = { shellId = "fx1Shell", badgeSuffix = ".fx1Shell.sizeBadge", row = 1, accentColor = 0xff22d3ee },
  fx2 = { shellId = "fx2Shell", badgeSuffix = ".fx2Shell.sizeBadge", row = 1, accentColor = 0xff38bdf8 },
  eq = { shellId = "eqShell", badgeSuffix = ".eqShell.sizeBadge", row = 1, accentColor = 0xff34d399 },
  placeholder1 = { shellId = "placeholder1Shell", badgeSuffix = ".placeholder1Shell.sizeBadge", row = 2, accentColor = 0xff64748b },
  placeholder2 = { shellId = "placeholder2Shell", badgeSuffix = ".placeholder2Shell.sizeBadge", row = 2, accentColor = 0xff64748b },
  placeholder3 = { shellId = "placeholder3Shell", badgeSuffix = ".placeholder3Shell.sizeBadge", row = 2, accentColor = 0xff64748b },
}
local function setKeyboardCollapsed(ctx, collapsed)
  return KeyboardInput.setKeyboardCollapsed(ctx, collapsed)
end

local function generateKeyboardKeys(whiteKeyCount)
  whiteKeyCount = whiteKeyCount or 14
  local whiteKeys = {}
  local blackKeys = {}
  local blackPositions = {}
  
  local whitePattern = {0, 2, 4, 5, 7, 9, 11}  -- C, D, E, F, G, A, B
  local blackPattern = {1, 3, 6, 8, 10}  -- C#, D#, F#, G#, A#
  local blackPosPattern = {0.5, 1.5, 3.5, 4.5, 5.5}  -- position between white keys
  
  for i = 1, whiteKeyCount do
    local octave = math.floor((i - 1) / 7)
    local noteInOctave = ((i - 1) % 7) + 1
    whiteKeys[i] = octave * 12 + whitePattern[noteInOctave]
  end
  
  local blackIndex = 1
  for i = 1, whiteKeyCount - 1 do
    local octave = math.floor((i - 1) / 7)
    local noteInOctave = ((i - 1) % 7) + 1
    -- C#(1), D#(3) between C-D and D-E, then F#(6), G#(8), A#(10) between F-G, G-A, A-B
    if noteInOctave == 1 or noteInOctave == 2 or noteInOctave == 4 or noteInOctave == 5 or noteInOctave == 6 then
      local blackOffset = blackPattern[noteInOctave == 1 and 1 or noteInOctave == 2 and 2 or noteInOctave == 4 and 3 or noteInOctave == 5 and 4 or 5]
      blackKeys[blackIndex] = octave * 12 + blackOffset
      blackPositions[blackIndex] = i + blackPosPattern[noteInOctave == 1 and 1 or noteInOctave == 2 and 2 or noteInOctave == 4 and 3 or noteInOctave == 5 and 4 or 5]
      blackIndex = blackIndex + 1
    end
  end
  
  return whiteKeys, blackKeys, blackPositions
end

local function getKeyCountForCtx(ctx)
  return ctx._keyboardKeyCount or 14
end

local function isKeyboardNoteActive(ctx, note)
  local midiVoices = ctx._midiVoices or ctx._voices or {}
  local voiceCount = ctx._voiceCount or 8
  for j = 1, voiceCount do
    local voice = midiVoices[j]
    if voice and voice.active and voice.note == note and voice.gate > 0.5 then
      return true
    end
  end
  return false
end

local function buildKeyboardDisplayList(ctx, w, h)
  return KeyboardInput.buildKeyboardDisplayList(ctx, w, h)
end

syncKeyboardDisplay = function(ctx)
  return KeyboardInput.syncKeyboardDisplay(ctx)
end

local function handleKeyboardClick(ctx, x, y, isDown)
  return KeyboardInput.handleKeyboardClick(ctx, x, y, isDown)
end

local function isUiInteracting(ctx)
  local widgets = ctx.widgets or {}
  local all = ctx.allWidgets or {}
  local rootId = ctx._globalPrefix or "root"

  local function widgetBusy(widget)
    return widget and (widget._dragging or widget._open)
  end

  if widgetBusy(widgets.midiInputDropdown) then return true end

  local trackedSuffixes = {
    ".oscillatorComponent.waveform_dropdown",
    ".oscillatorComponent.mode_tabs.wave_tab.render_mode_tabs",
    ".oscillatorComponent.mode_tabs.wave_tab.drive_mode_dropdown",
    ".oscillatorComponent.mode_tabs.wave_tab.pulse_width_knob",
    ".oscillatorComponent.mode_tabs.sample_tab.sample_source_dropdown",
    ".oscillatorComponent.mode_tabs.sample_tab.sample_bars_box",
    ".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_map_toggle",
    ".oscillatorComponent.mode_tabs.sample_tab.sample_root_box",
    ".oscillatorComponent.mode_tabs.wave_tab.drive_knob",
    ".oscillatorComponent.mode_tabs.wave_tab.drive_bias_knob",
    ".oscillatorComponent.mode_tabs.wave_tab.add_partials_knob",
    ".oscillatorComponent.mode_tabs.wave_tab.add_tilt_knob",
    ".oscillatorComponent.mode_tabs.wave_tab.add_drift_knob",
    ".oscillatorComponent.output_knob",
    ".oscillatorComponent.blend_amount_knob",
    ".filterComponent.filter_type_dropdown",
    ".filterComponent.cutoff_knob",
    ".filterComponent.resonance_knob",
    ".envelopeComponent.attack_knob",
    ".envelopeComponent.decay_knob",
    ".envelopeComponent.sustain_knob",
    ".envelopeComponent.release_knob",
    ".fx1Component.type_dropdown",
    ".fx1Component.xy_x_dropdown",
    ".fx1Component.xy_y_dropdown",
    ".fx1Component.mix_knob",
    ".fx1Component.param1",
    ".fx1Component.param2",
    ".fx1Component.param3",
    ".fx1Component.param4",
    ".fx1Component.param5",
    ".fx2Component.type_dropdown",
    ".fx2Component.xy_x_dropdown",
    ".fx2Component.xy_y_dropdown",
    ".fx2Component.mix_knob",
    ".fx2Component.param1",
    ".fx2Component.param2",
    ".fx2Component.param3",
    ".fx2Component.param4",
    ".fx2Component.param5",
  }

  for _, suffix in ipairs(trackedSuffixes) do
    if widgetBusy(getScopedWidget(ctx, suffix)) then
      return true
    end
  end

  local runtime = _G.__manifoldStructuredUiRuntime
  if runtime and type(runtime.behaviors) == "table" then
    for i = 1, #runtime.behaviors do
      local behavior = runtime.behaviors[i]
      local path = tostring(behavior and behavior.path or "")
      local behaviorCtx = behavior and behavior.ctx or nil
      if endsWith(path, "ui/behaviors/fx_slot.lua") and type(behaviorCtx) == "table" and behaviorCtx.dragging then
        return true
      end
    end
  end

  return false
end

-- Background tick: MIDI polling + envelope processing.
-- Stored as a global so the root behavior can call it every frame,
-- even when the MidiSynth tab is not active.
local function backgroundTick(ctx)
  activeBehaviorCtx = ctx
  local now = getTime and getTime() or 0
  local minInterval = isUiInteracting(ctx) and BG_TICK_INTERVAL_WHILE_INTERACTING or BG_TICK_INTERVAL
  if now - (ctx._lastBackgroundTickTime or 0) < minInterval then
    return
  end

  local dt = now - (ctx._lastUpdateTime or now)
  if dt < 0 then dt = 0 end
  if dt > 0.05 then dt = 0.05 end

  ctx._lastUpdateTime = now
  ctx._lastBackgroundTickTime = now

  -- Process MIDI input
  if Midi and Midi.pollInputEvent then
    while true do
      local event = Midi.pollInputEvent()
      if not event then break end

      if ctx._rackModRuntime and ctx._rackModRuntime.onMidiEvent then
        ctx._rackModRuntime:onMidiEvent(event)
      end
      if ctx._modRuntime and ctx._modRuntime.onMidiEvent then
        ctx._modRuntime:onMidiEvent(event)
      end

      if event.type == Midi.NOTE_ON and event.data2 > 0 then
        ctx._currentNote = event.data1
        local voiceIndex = VoiceManager.triggerVoice(ctx, event.data1, event.data2)
        if voiceIndex ~= nil then
          ctx._lastEvent = string.format("Note: %s vel %d", noteName(event.data1), event.data2)
        else
          ctx._lastEvent = string.format("Blocked: %s", tostring(ctx._triggerBlockedReason or "missing trigger path"))
        end
      elseif event.type == Midi.NOTE_OFF or (event.type == Midi.NOTE_ON and event.data2 == 0) then
        VoiceManager.releaseVoice(ctx, event.data1)
        if ctx._currentNote == event.data1 then
          ctx._currentNote = nil
        end
      elseif event.type == Midi.CONTROL_CHANGE then
        ctx._lastEvent = string.format("CC %d = %d", event.data1, event.data2)
        MidiParamRack.onMidiCC(ctx, event.data1, event.data2)
        MidiParamRack.invalidate(ctx)
      elseif Midi and event.type == Midi.PITCH_BEND then
        local bend = event.data1 | (event.data2 << 7)
        ctx._lastEvent = string.format("Pitch Bend %d", bend)
      elseif Midi and Midi.CHANNEL_PRESSURE and event.type == Midi.CHANNEL_PRESSURE then
        ctx._lastEvent = string.format("Pressure %d", event.data1)
      end
    end
  end

  if ctx._rackModRuntime and ctx._rackModRuntime.evaluateAndApply then
    ctx._rackModRuntime:evaluateAndApply(ctx, readParam, setPath)
  end
  require("transpose_runtime").updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  require("velocity_mapper_runtime").updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  require("scale_quantizer_runtime").updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  require("note_filter_runtime").updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  require("arp_runtime").updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  if ctx._rackModRuntime and ctx._rackModRuntime.evaluateAndApply then
    ctx._rackModRuntime:evaluateAndApply(ctx, readParam, setPath)
  end

  -- Update ADSR envelopes after voice-chain transforms have landed.
  local attack = readParam(PATHS.attack, 0.05)
  local decay = readParam(PATHS.decay, 0.2)
  local sustain = readParam(PATHS.sustain, 0.7)
  local release = readParam(PATHS.release, 0.4)
  ctx._adsr.attack = attack
  ctx._adsr.decay = decay
  ctx._adsr.sustain = sustain
  ctx._adsr.release = release
  VoiceManager.updateEnvelopes(ctx, dt, now)
  require("adsr_runtime").updateDynamicModules(ctx, dt, readParam, clamp, VOICE_COUNT)
  if ctx._rackModRuntime and ctx._rackModRuntime.evaluateAndApply then
    ctx._rackModRuntime:evaluateAndApply(ctx, readParam, setPath)
  end
  if ctx._modRuntime and ctx._modRuntime.evaluateAndApply then
    ctx._modRuntime:evaluateAndApply(ctx, readParam, setPath)
  end
  require("attenuverter_bias_runtime").updateDynamicModules(ctx, dt, readParam)
  require("lfo_runtime").updateDynamicModules(ctx, dt, readParam)
  require("slew_runtime").updateDynamicModules(ctx, dt, readParam)
  require("sample_hold_runtime").updateDynamicModules(ctx, dt, readParam)
  require("compare_runtime").updateDynamicModules(ctx, dt, readParam)
  require("cv_mix_runtime").updateDynamicModules(ctx, dt, readParam)
  require("range_mapper_runtime").updateDynamicModules(ctx, dt, readParam)
  if ctx._pendingAuxAudioRouteSync == true then
    syncAuxAudioRouteParams(ctx)
  end
end

function M.init(ctx)
  activeBehaviorCtx = ctx
  local widgets = ctx.widgets or {}
  ctx._currentNote = nil
  ctx._lastEvent = "No MIDI yet"
  ctx._voiceStamp = 0
  ctx._voices = {}
  ctx._midiVoices = {}
  ctx._selectedMidiInputIdx = 1
  ctx._selectedMidiInputLabel = "None (Disabled)"
  ctx._adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }
  ctx._keyboardOctave = 3
  ctx._rackState = MidiSynthRackSpecs.defaultRackState()
  ctx._utilityViewId = "palette"
  ctx._selectedPaletteEntryId = "adsr"
  ctx._paletteScrollOffset = 0
  ctx._utilityNavScrollOffset = 0
  ctx._paletteBrowseCollapsed = { voice = false, audio = false, fx = false, mod = false }
  ctx._paletteFilterTags = {}
  ctx._paletteFilterTagAll = true
  ctx._paletteSearchText = ""
  ctx._paletteSearchFocused = false
  ctx._rackModuleSpecs = MidiSynthRackSpecs.rackModuleSpecById()
  ctx._rackConnections = MidiSynthRackSpecs.defaultConnections(ctx._rackState.modules)
  M.invalidatePatchbay(nil, ctx)
  ctx._utilityDock = ctx._rackState.utilityDock or RackLayout.defaultUtilityDock()
  ctx._keyboardCollapsed = false
  KeyboardInput.init({
    triggerVoice = VoiceManager.triggerVoice,
    releaseVoice = VoiceManager.releaseVoice,
    ensureUtilityDockState = M.ensureUtilityDockState,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
    noteName = noteName,
    repaint = repaint,
  })
  VoiceManager.init({
    setPath = setPath,
    readParam = readParam,
    ParameterBinder = ParameterBinder,
    adsr_runtime = require("adsr_runtime"),
    applyImplicitRackOscillatorKeyboardPitch = ModulationRouter.applyImplicitRackOscillatorKeyboardPitch,
  })
  ModulationRouter.init({
    setPath = setPath,
    readParam = readParam,
    ParameterBinder = ParameterBinder,
  })
  RackLayoutEngine.init({
    getScopedWidget = getScopedWidget,
    getScopedBehavior = getScopedBehavior,
    RackLayoutManager = RackLayoutManager,
    MidiSynthRackSpecs = MidiSynthRackSpecs,
    RackModuleFactory = RackModuleFactory,
    RackLayout = RackLayout,
    RackWireLayer = RackWireLayer,
    MidiParamRack = MidiParamRack,
    setPath = setPath,
    syncText = syncText,
    round = round,
    RACK_COLUMNS_PER_ROW = RACK_COLUMNS_PER_ROW,
    RACK_MODULE_SHELL_LAYOUT = RACK_MODULE_SHELL_LAYOUT,
    ensureUtilityDockState = M.ensureUtilityDockState,
    syncPatchViewMode = M.syncPatchViewMode,
    syncRackEdgeTerminals = M.syncRackEdgeTerminals,
    syncKeyboardCollapsedFromUtilityDock = KeyboardInput.syncKeyboardCollapsedFromUtilityDock,
    syncKeyboardCollapseButton = KeyboardInput.syncKeyboardCollapseButton,
    computeKeyboardPanelHeight = KeyboardInput.computeKeyboardPanelHeight,
    syncKeyboardDisplay = KeyboardInput.syncKeyboardDisplay,
  })
  StateManager.init({
    projectRoot = projectRoot,
    readTextFile = readTextFile,
    writeTextFile = writeTextFile,
    setPath = setPath,
    readParam = readParam,
    round = round,
    MidiSynthRackSpecs = MidiSynthRackSpecs,
    RackLayout = RackLayout,
    RackModuleFactory = RackModuleFactory,
    PATHS = PATHS,
    MAX_FX_PARAMS = MAX_FX_PARAMS,
    fxParamPath = fxParamPath,
    eq8BandEnabledPath = eq8BandEnabledPath,
    eq8BandTypePath = eq8BandTypePath,
    eq8BandFreqPath = eq8BandFreqPath,
    eq8BandGainPath = eq8BandGainPath,
    eq8BandQPath = eq8BandQPath,
    syncKeyboardCollapsedFromUtilityDock = syncKeyboardCollapsedFromUtilityDock,
    setKeyboardCollapsed = setKeyboardCollapsed,
    applyRackConnectionState = M.applyRackConnectionState,
    syncKeyboardCollapseButton = M.syncKeyboardCollapseButton,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
    MidiParamRack = MidiParamRack,
    persistMidiInputSelection = persistMidiInputSelection,
  })
  MidiDevices.init({
    loadRuntimeState = M.loadRuntimeState,
    saveRuntimeState = M.saveRuntimeState,
  })
  PatchbayBinding.init({
    RackWireLayer = RackWireLayer,
    RackModPopover = RackModPopover,
    getScopedWidget = getScopedWidget,
    getWidgetBoundsInRoot = M.getWidgetBoundsInRoot,
    readParam = readParam,
    setPath = setPath,
    setWidgetValueSilently = setWidgetValueSilently,
    setSampleLoopStartLinked = setSampleLoopStartLinked,
    setSampleLoopLenLinked = setSampleLoopLenLinked,
    syncLegacyBlendDirectionFromBlend = syncLegacyBlendDirectionFromBlend,
    ModulationRouter = ModulationRouter,
    ParameterBinder = ParameterBinder,
    auxAudioSourceCodeForEndpoint = auxAudioSourceCodeForEndpoint,
    RACK_MODULE_SHELL_LAYOUT = RACK_MODULE_SHELL_LAYOUT,
    RackLayout = RackLayout,
    getRackTotalRows = M.getRackTotalRows,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
    RACK_COLUMNS_PER_ROW = RACK_COLUMNS_PER_ROW,
    round = round,
  })
  require("behaviors.dynamic_module_binding").init({
    setPath = setPath,
    PATHS = PATHS,
    MidiSynthRackSpecs = MidiSynthRackSpecs,
    RackModuleFactory = RackModuleFactory,
    RACK_MODULE_SHELL_LAYOUT = RACK_MODULE_SHELL_LAYOUT,
    getScopedWidget = getScopedWidget,
    getScopedBehavior = getScopedBehavior,
    RackLayoutManager = RackLayoutManager,
    PatchbayRuntime = PatchbayRuntime,
  })
  require("behaviors.rack_mutation_runtime").init({
    RackLayout = RackLayout,
    MidiSynthRackSpecs = MidiSynthRackSpecs,
    RackModuleFactory = RackModuleFactory,
    ModEndpointRegistry = ModEndpointRegistry,
    ModRouteCompiler = ModRouteCompiler,
    RackControlRouter = RackControlRouter,
    ModRuntime = ModRuntime,
    PatchbayRuntime = PatchbayRuntime,
    RackWireLayer = RackWireLayer,
    RackModPopover = RackModPopover,
    setPath = setPath,
    readParam = readParam,
    PATHS = PATHS,
    VOICE_COUNT = VOICE_COUNT,
    RACK_COLUMNS_PER_ROW = RACK_COLUMNS_PER_ROW,
    RACK_MODULE_SHELL_LAYOUT = RACK_MODULE_SHELL_LAYOUT,
    getScopedWidget = getScopedWidget,
    getWidgetBoundsInRoot = M.getWidgetBoundsInRoot,
    autoCollapseRowForInsertion = M.autoCollapseRowForInsertion,
    getRackTotalRows = M.getRackTotalRows,
    ensureUtilityDockState = M.ensureUtilityDockState,
    hideDragGhost = M.hideDragGhost,
    resetDragState = M.resetDragState,
    dragState = M.dragState,
    getRackShellMetaByNodeId = M.getRackShellMetaByNodeId,
    invalidatePatchbay = M.invalidatePatchbay,
    cleanupPatchbayFromRuntime = M.cleanupPatchbayFromRuntime,
    syncAuxAudioRouteParams = syncAuxAudioRouteParams,
    syncPatchViewMode = M.syncPatchViewMode,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
    panicVoices = VoiceManager.panicVoices,
  })
  require("behaviors.palette_browser").init({
    setPath = setPath,
    voiceCount = VOICE_COUNT,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
    getScopedWidget = getScopedWidget,
    getWidgetBoundsInRoot = M.getWidgetBoundsInRoot,
    getWidgetBounds = M.getWidgetBounds,
    setWidgetBounds = M.setWidgetBounds,
    syncText = syncText,
    syncColour = syncColour,
    computeRackFlowTargetPlacement = M.computeRackFlowTargetPlacement,
    previewRackDragReorder = M.previewRackDragReorder,
    finalizeRackDragReorder = M.finalizeRackDragReorder,
    ensureDragGhost = M.ensureDragGhost,
    updateDragGhost = M.updateDragGhost,
    hideDragGhost = M.hideDragGhost,
    resetDragState = M.resetDragState,
    dragState = M.dragState,
    getRackShellMetaByNodeId = M.getRackShellMetaByNodeId,
    collectRackFlowSnapshot = M.collectRackFlowSnapshot,
    pointInsideRackFlowBands = M._pointInsideRackFlowBands,
    requestDynamicModuleSlot = M._requestDynamicModuleSlot,
  })
  KeyboardInput.syncKeyboardCollapsedFromUtilityDock(ctx)
  _G.__midiSynthRackState = ctx._rackState
  _G.__midiSynthRackModuleSpecs = ctx._rackModuleSpecs
  _G.__midiSynthRackConnections = ctx._rackConnections
  _G.__midiSynthUtilityDock = ctx._utilityDock
  _G.__midiSynthDynamicModuleInfo = {}
  ctx._dynamicModuleSlots = RackModuleFactory.ensureDynamicModuleSlots(ctx)
  M._rebuildDynamicRackModuleState(ctx)
  ctx._applyVoiceModulationTarget = ModulationRouter.applyVoiceModulationTarget
  ctx._resolveDynamicVoiceBundleSample = ModulationRouter.resolveDynamicVoiceBundleSample
  ctx._applyControlModulationTarget = ModulationRouter.applyControlModulationTarget
  ctx._resolveControlModulationSource = ModulationRouter.resolveControlModulationSource
  ctx._resolveVoiceModulationSource = function(innerCtx, sourceId, source, voiceCount)
    return ModulationRouter.resolveDynamicVoiceModulationSource(innerCtx, sourceId, source, voiceCount)
  end
  ctx._onRackConnectionsChanged = function(innerCtx, reason)
    M.applyRackConnectionState(innerCtx, reason)
  end
  M.applyRackConnectionState(ctx, "init")
  ctx._keyboardNote = nil
  ctx._keyboardDirty = true
  ctx._lastUpdateTime = getTime and getTime() or 0
  ctx._lastMidiDeviceScanTime = -1000
  ctx._lastKnownMidiDeviceCount = -1
  ctx._lastBackgroundTickTime = 0
  ctx._lastOscRepaintTime = 0
  ctx._lastEnvRepaintTime = 0
  ctx._midiParamRackDisplayDirty = true
  
  for i = 1, VOICE_COUNT do
    ctx._voices[i] = {
      active = false,
      note = nil,
      stamp = 0,
      gate = 0,
      targetAmp = 0,
      currentAmp = 0,
      sentAmp = 0,
      lastAmpPushTime = 0,
      freq = 220,
      envelopeStage = "idle",
      envelopeLevel = 0,
      envelopeTime = 0,
      envelopeStartLevel = 0,
      eoc = 0,
    }
    ctx._midiVoices[i] = {
      active = false,
      note = nil,
      stamp = 0,
      gate = 0,
      targetAmp = 0,
      currentAmp = 0,
      sentAmp = 0,
      lastAmpPushTime = 0,
      freq = 220,
      envelopeStage = "idle",
      envelopeLevel = 0,
      envelopeTime = 0,
      envelopeStartLevel = 0,
      eoc = 0,
    }
  end
  require("transpose_runtime").publishViewState(ctx)
  require("velocity_mapper_runtime").publishViewState(ctx)
  require("scale_quantizer_runtime").publishViewState(ctx)
  require("note_filter_runtime").publishViewState(ctx)
  require("arp_runtime").publishViewState(ctx)
  require("adsr_runtime").publishViewState(ctx)
  require("attenuverter_bias_runtime").publishViewState(ctx)
  require("lfo_runtime").publishViewState(ctx)
  require("slew_runtime").publishViewState(ctx)
  require("sample_hold_runtime").publishViewState(ctx)
  require("compare_runtime").publishViewState(ctx)
  require("cv_mix_runtime").publishViewState(ctx)
  require("range_mapper_runtime").publishViewState(ctx)
  
  if Midi and Midi.clearCallbacks then
    -- Don't clear callbacks here - we want MIDI to keep working globally
    -- Midi.clearCallbacks()
  end
  
  ctx._globalPrefix = resolveGlobalPrefix(ctx)
  InitBindings.bindComponents(ctx, {
    PATHS = PATHS,
    SAMPLE_SOURCE_OPTIONS = SAMPLE_SOURCE_OPTIONS,
    DRIVE_SHAPE_OPTIONS = DRIVE_SHAPE_OPTIONS,
    BLEND_MODE_OPTIONS = BLEND_MODE_OPTIONS,
    getScopedWidget = getScopedWidget,
    getScopedBehavior = getScopedBehavior,
    setPath = setPath,
    readParam = readParam,
    clamp = clamp,
    round = round,
    sanitizeBlendMode = sanitizeBlendMode,
    setWidgetInteractiveState = setWidgetInteractiveState,
    formatMidiNoteValue = formatMidiNoteValue,
    getTime = getTime,
  })

  InitControls.bindControls(ctx, {
    getScopedWidget = getScopedWidget,
    triggerVoice = triggerVoice,
    releaseVoice = releaseVoice,
    panicVoices = panicVoices,
    refreshMidiDevices = refreshMidiDevices,
    applyMidiSelection = applyMidiSelection,
    syncSelected = syncSelected,
    setKeyboardCollapsed = setKeyboardCollapsed,
    persistDockUiState = M.persistDockUiState,
    syncText = syncText,
    getOctaveLabel = getOctaveLabel,
    syncKeyboardDisplay = syncKeyboardDisplay,
    handleKeyboardClick = handleKeyboardClick,
    saveCurrentState = M.saveCurrentState,
    loadSavedState = M.loadSavedState,
    resetToDefaults = M.resetToDefaults,
    updateDropdownAnchors = updateDropdownAnchors,
    loadRuntimeState = M.loadRuntimeState,
    backgroundTick = backgroundTick,
    setPath = setPath,
    readParam = readParam,
    applyRackConnectionState = M.applyRackConnectionState,
    deleteRackNode = M.deleteRackNode,
    toggleRackNodeWidth = toggleRackNodeWidth,
    spawnPalettePlaceholderAt = M.spawnPalettePlaceholderAt,
    spawnPaletteNodeAt = M.spawnPaletteNodeAt,
    setUtilityDockMode = M.setUtilityDockMode,
    syncDockModeDots = M.syncDockModeDots,
    ensureUtilityDockState = M.ensureUtilityDockState,
    syncPatchViewMode = M.syncPatchViewMode,
    onRackDotClick = M.onRackDotClick,
    ensureRackPaginationState = M.ensureRackPaginationState,
    updateRackPaginationDots = M.updateRackPaginationDots,
    setRackViewport = M.setRackViewport,
    bindWirePortWidget = M.bindWirePortWidget,
    setupShellDragHandlers = M._setupShellDragHandlers,
    setupResizeToggleHandlers = M._setupResizeToggleHandlers,
    setupDeleteButtonHandlers = M._setupDeleteButtonHandlers,
    setupPaletteDragHandlers = M._setupPaletteDragHandlers,
    syncKeyboardCollapseButton = M.syncKeyboardCollapseButton,
    RackWireLayer = RackWireLayer,
    refreshManagedLayoutState = M.refreshManagedLayoutState,
  })
end

function M.resized(ctx, w, h)
  ctx._lastW = w
  ctx._lastH = h
  M.refreshManagedLayoutState(ctx, w, h)
  updateDropdownAnchors(ctx)
end
function M.update(ctx, rawState)
  activeBehaviorCtx = ctx
  local UpdateSync = require("ui.update_sync")
  UpdateSync.update(ctx, {
    BG_TICK_INTERVAL = BG_TICK_INTERVAL,
    OSC_REPAINT_INTERVAL = OSC_REPAINT_INTERVAL,
    OSC_REPAINT_INTERVAL_WHILE_INTERACTING = OSC_REPAINT_INTERVAL_WHILE_INTERACTING,
    OSC_REPAINT_INTERVAL_MULTI_VOICE = OSC_REPAINT_INTERVAL_MULTI_VOICE,
    ENV_REPAINT_INTERVAL = ENV_REPAINT_INTERVAL,
    ENV_REPAINT_INTERVAL_WHILE_INTERACTING = ENV_REPAINT_INTERVAL_WHILE_INTERACTING,
    MAX_FX_PARAMS = MAX_FX_PARAMS,
    VOICE_COUNT = VOICE_COUNT,
    FILTER_OPTIONS = FILTER_OPTIONS,
    FxDefs = FxDefs,
    PATHS = PATHS,
    getTime = getTime,
    backgroundTick = backgroundTick,
    isUiInteracting = isUiInteracting,
    maybeRefreshMidiDevices = maybeRefreshMidiDevices,
    syncPatchViewMode = syncPatchViewMode,
    RackWireLayer = RackWireLayer,
    readParam = readParam,
    setPath = setPath,
    sanitizeBlendMode = sanitizeBlendMode,
    getVoiceStackingLabels = getVoiceStackingLabels,
    setWidgetInteractiveState = setWidgetInteractiveState,
    setWidgetBounds = M.setWidgetBounds,
    isPluginMode = isPluginMode,
    activeVoiceCount = VoiceManager.activeVoiceCount,
    voiceSummary = VoiceManager.voiceSummary,
    noteName = noteName,
    formatTime = formatTime,
    syncKeyboardDisplay = syncKeyboardDisplay,
    syncMidiParamRack = function()
      MidiParamRack.sync(ctx, (ctx.widgets or {}).midiParamRack)
    end,
    cleanupPatchbayFromRuntime = cleanupPatchbayFromRuntime,
    patchbayInstances = PatchbayRuntime.getInstances(),
    ensurePatchbayWidgets = ensurePatchbayWidgets,
    syncPatchbayValues = syncPatchbayValues,
    clamp = clamp,
    setWidgetValueSilently = setWidgetValueSilently,
    getModTargetState = function(path)
      return ModulationRouter.getCombinedModTargetState(ctx, path)
    end,
  })
end

function M.cleanup(ctx)
  if activeBehaviorCtx == ctx then
    activeBehaviorCtx = nil
  end
  -- Clear exported hooks if they still point at this instance. Leaving stale
  -- ctx-capturing closures alive across project reloads is crash bait.
  if _G.__midiSynthBackgroundTick == ctx._backgroundTickHook then
    _G.__midiSynthBackgroundTick = nil
  end
  if _G.__midiSynthPanic == ctx._panicHook then
    _G.__midiSynthPanic = nil
  end
  if _G.__midiSynthTriggerNote == ctx._triggerNoteHook then
    _G.__midiSynthTriggerNote = nil
  end
  if _G.__midiSynthReleaseNote == ctx._releaseNoteHook then
    _G.__midiSynthReleaseNote = nil
  end
  if _G.__midiSynthSetAuthoredParam == ctx._setAuthoredParamHook then
    _G.__midiSynthSetAuthoredParam = nil
  end
  if _G.__midiSynthGetModTargetState == ctx._getModTargetStateHook then
    _G.__midiSynthGetModTargetState = nil
  end
  if _G.__midiSynthGetDockPresentationMode == ctx._getDockPresentationModeHook then
    _G.__midiSynthGetDockPresentationMode = nil
  end
  if _G.__midiSynthSetDockPresentationMode == ctx._setDockPresentationModeHook then
    _G.__midiSynthSetDockPresentationMode = nil
  end
  if _G.__midiSynthGetRackRouteDebug == ctx._getRackRouteDebugHook then
    _G.__midiSynthGetRackRouteDebug = nil
  end
  if _G.__midiSynthGetModEndpointRegistry == ctx._getModEndpointRegistryHook then
    _G.__midiSynthGetModEndpointRegistry = nil
  end
  if _G.__midiSynthCompileModRoute == ctx._compileModRouteHook then
    _G.__midiSynthCompileModRoute = nil
  end
  if _G.__midiSynthGetModRouteCompilerDebug == ctx._getModRouteCompilerDebugHook then
    _G.__midiSynthGetModRouteCompilerDebug = nil
  end
  if _G.__midiSynthSetGlobalModRoutes == ctx._setGlobalModRoutesHook then
    _G.__midiSynthSetGlobalModRoutes = nil
  end
  if _G.__midiSynthClearGlobalModRoutes == ctx._clearGlobalModRoutesHook then
    _G.__midiSynthClearGlobalModRoutes = nil
  end
  if _G.__midiSynthSetModSourceValue == ctx._setModSourceValueHook then
    _G.__midiSynthSetModSourceValue = nil
  end
  if _G.__midiSynthEvaluateModRuntime == ctx._evaluateModRuntimeHook then
    _G.__midiSynthEvaluateModRuntime = nil
  end
  if _G.__midiSynthGetModRuntimeDebug == ctx._getModRuntimeDebugHook then
    _G.__midiSynthGetModRuntimeDebug = nil
  end
  if _G.__midiSynthResyncRackConnections == ctx._resyncRackConnectionsHook then
    _G.__midiSynthResyncRackConnections = nil
  end
  if _G.__midiSynthDeleteRackNode == ctx._deleteRackNodeHook then
    _G.__midiSynthDeleteRackNode = nil
  end
  if _G.__midiSynthSpawnPalettePlaceholder == ctx._spawnPalettePlaceholderHook then
    _G.__midiSynthSpawnPalettePlaceholder = nil
  end
  if _G.__midiSynthSpawnPaletteNode == ctx._spawnPaletteNodeHook then
    _G.__midiSynthSpawnPaletteNode = nil
  end
  if _G.__midiSynthToggleRackNodeWidth == ctx._toggleRackNodeWidthHook then
    _G.__midiSynthToggleRackNodeWidth = nil
  end
  if _G.__midiSynthSetRackViewport == ctx._setRackViewportHook then
    _G.__midiSynthSetRackViewport = nil
  end

  if ctx._onMidiDeviceStateChanged ~= nil then
    ctx._onMidiDeviceStateChanged = nil
  end

  -- Note: Midi.clearCallbacks() is still not called here to keep MIDI alive.

  -- Clear patchbay/widget globals that can otherwise keep dead runtime nodes alive.
  M.invalidatePatchbay(nil, ctx)
  ctx._pendingPatchbayPages = nil
  ctx._patchbayPortRegistry = nil

  if _G.__midiSynthPatchbayPortRegistry == nil or _G.__midiSynthPatchbayPortRegistry == ctx._patchbayPortRegistry then
    _G.__midiSynthPatchbayPortRegistry = nil
  end
  if _G.__midiSynthRackPagination == ctx._rackPagination then
    _G.__midiSynthRackPagination = nil
  end
  if _G.__midiSynthRackWireLayer == RackWireLayer then
    _G.__midiSynthRackWireLayer = nil
  end
  if type(_G) == "table" then
    _G.__midiSynthDynamicModuleSpecs = nil
    _G.__midiSynthDynamicOscillatorAnalysis = nil
    _G.__midiSynthAdsrViewState = nil
    _G.__midiSynthArpViewState = nil
    _G.__midiSynthTransposeViewState = nil
    _G.__midiSynthVelocityMapperViewState = nil
    _G.__midiSynthScaleQuantizerViewState = nil
    _G.__midiSynthNoteFilterViewState = nil
    _G.__midiSynthAttenuverterBiasViewState = nil
    _G.__midiSynthLfoViewState = nil
    _G.__midiSynthSlewViewState = nil
    _G.__midiSynthSampleHoldViewState = nil
    _G.__midiSynthCompareViewState = nil
    _G.__midiSynthCvMixViewState = nil
    _G.__midiSynthRangeMapperViewState = nil
  end

  if _G.__midiSynthRackState == ctx._rackState then
    _G.__midiSynthRackState = nil
  end
  if _G.__midiSynthRackModuleSpecs == ctx._rackModuleSpecs then
    _G.__midiSynthRackModuleSpecs = nil
  end
  if _G.__midiSynthRackConnections == ctx._rackConnections then
    _G.__midiSynthRackConnections = nil
  end
  if _G.__midiSynthUtilityDock == ctx._utilityDock then
    _G.__midiSynthUtilityDock = nil
  end
  if type(_G) == "table" then
    _G.__midiSynthDynamicModuleInfo = nil
  end
end

return M

local Registry = require("module_host_registry")
local ParameterBinder = require("parameter_binder")
package.loaded["ui.midi_devices"] = nil
local MidiDevices = require("ui.midi_devices")
local PatchbayRuntime = require("ui.patchbay_runtime")
local ScopedWidget = require("ui.scoped_widget")

local AdsrRuntime = require("adsr_runtime")
local ArpRuntime = require("arp_runtime")
local TransposeRuntime = require("transpose_runtime")
local VelocityMapperRuntime = require("velocity_mapper_runtime")
local ScaleQuantizerRuntime = require("scale_quantizer_runtime")
local NoteFilterRuntime = require("note_filter_runtime")
local AttenuverterBiasRuntime = require("attenuverter_bias_runtime")
local LfoRuntime = require("lfo_runtime")
local SlewRuntime = require("slew_runtime")
local SampleHoldRuntime = require("sample_hold_runtime")
local CompareRuntime = require("compare_runtime")
local CvMixRuntime = require("cv_mix_runtime")
local RangeMapperRuntime = require("range_mapper_runtime")

local M = {}

local MODULES = Registry.modules()
local MODULE_INDEX_BY_ID = Registry.moduleIndexById()
local MODULE_INFO_MAP = Registry.moduleInfoMap()
local VOICE_COUNT = Registry.VOICE_COUNT
local AUDITION_OSC_BASE = Registry.auditionOscParamBase()

local HOST_PATHS = {
  moduleIndex = "/rack_host/module/index",
  viewMode = "/rack_host/view/mode",
  inputAMode = "/rack_host/input_a/mode",
  inputAPitch = "/rack_host/input_a/pitch",
  inputALevel = "/rack_host/input_a/level",
  inputBMode = "/rack_host/input_b/mode",
  inputBPitch = "/rack_host/input_b/pitch",
  inputBLevel = "/rack_host/input_b/level",
}

local SOURCE_MODE_COUNT = 7
local VIEW_MODE_COUNT = 2
local SYNC_INTERVAL = 0.05
local LAYOUT_PADDING = 18
local ADAPTIVE_MIN_H = 48
local ADAPTIVE_GAP = 16
local SHELL_HEADER_H = 12
local MAX_DISPLAY_SCALE = 2.0

local VOICE_RUNTIME_BY_ID = {
  adsr = AdsrRuntime,
  arp = ArpRuntime,
  transpose = TransposeRuntime,
  velocity_mapper = VelocityMapperRuntime,
  scale_quantizer = ScaleQuantizerRuntime,
  note_filter = NoteFilterRuntime,
}

local SCALAR_RUNTIME_BY_ID = {
  attenuverter_bias = AttenuverterBiasRuntime,
  lfo = LfoRuntime,
  slew = SlewRuntime,
  sample_hold = SampleHoldRuntime,
  compare = CompareRuntime,
  cv_mix = CvMixRuntime,
  range_mapper = RangeMapperRuntime,
}

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function clamp01(value)
  return clamp(value, 0.0, 1.0)
end

local function round(value)
  return math.floor((tonumber(value) or 0.0) + 0.5)
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

local function writeParam(path, value)
  local numeric = tonumber(value) or 0.0
  if type(_G.setParam) == "function" then
    return _G.setParam(path, numeric)
  end
  if type(command) == "function" then
    command("SET", path, tostring(numeric))
    return true
  end
  return false
end

local function setVisible(widget, visible)
  if widget and widget.setVisible then
    widget:setVisible(visible == true)
  elseif widget and widget.node and widget.node.setVisible then
    widget.node:setVisible(visible == true)
  end
end

local function setText(widget, text)
  if widget and widget.setText then
    widget:setText(tostring(text or ""))
  elseif widget and widget.setLabel then
    widget:setLabel(tostring(text or ""))
  end
end

local function setBounds(widget, x, y, w, h)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.max(1, math.floor(tonumber(w) or 1))
  h = math.max(1, math.floor(tonumber(h) or 1))
  if widget and widget.setBounds then
    widget:setBounds(x, y, w, h)
  elseif widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(x, y, w, h)
  end
end

local function syncDropdown(widget, options, selected)
  if not widget then
    return
  end
  if type(options) == "table" and widget.setOptions then
    widget:setOptions(options)
  end
  if widget.setSelected and not widget._open then
    widget:setSelected(math.max(1, round(selected)))
  end
end

local function syncSlider(widget, value)
  if widget and widget.setValue and not widget._dragging then
    widget:setValue(tonumber(value) or 0.0)
  end
end

local function getScopedWidget(ctx, suffix)
  return ScopedWidget.getScopedWidget(ctx, suffix)
end

local function getWidgetBoundsInRoot(ctx, widget)
  if not (widget and widget.node and widget.node.getBounds) then
    return nil
  end
  local x, y, w, h = widget.node:getBounds()
  local bounds = { x = tonumber(x) or 0, y = tonumber(y) or 0, w = tonumber(w) or 0, h = tonumber(h) or 0 }
  local record = widget._structuredRecord
  local current = type(record) == "table" and record.parent or nil
  while current do
    local parentWidget = current.widget
    if parentWidget and parentWidget.node and parentWidget.node.getBounds then
      local px, py = parentWidget.node:getBounds()
      bounds.x = bounds.x + (tonumber(px) or 0)
      bounds.y = bounds.y + (tonumber(py) or 0)
    end
    current = current.parent
  end
  return bounds
end

local function setWidgetValueSilently(widget, value)
  return ScopedWidget.setWidgetValueSilently(widget, value)
end

local function getScopedBehavior(ctx, suffix)
  local runtime = _G.__manifoldStructuredUiRuntime
  if not (runtime and type(runtime.behaviors) == "table") then
    return nil
  end
  local wanted = tostring(suffix or "")
  local best = nil
  for i = 1, #(runtime.behaviors or {}) do
    local behavior = runtime.behaviors[i]
    local id = tostring(behavior and behavior.id or "")
    if wanted ~= "" and id:sub(-#wanted) == wanted then
      if best == nil or #id < #(best.id or "") then
        best = behavior
      end
    end
  end
  return best
end

local function notifyModuleResized(ctx, module, width, height)
  local behavior = getScopedBehavior(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.componentId or ""))
  if behavior and behavior.ctx and behavior.module and type(behavior.module.resized) == "function" then
    behavior.module.resized(behavior.ctx, width, height)
  end
end

local function layoutShellWidgets(ctx, module, shellW, shellH)
  local shell = getScopedWidget(ctx, "." .. tostring(module.shellId or ""))
  if not shell then
    return
  end

  local contentH = math.max(1, shellH - SHELL_HEADER_H)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.deleteButtonId or "")), 0, 0, 24, SHELL_HEADER_H)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.resizeButtonId or "")), shellW - 24, 0, 24, SHELL_HEADER_H)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.nodeNameLabelId or "")), 30, 0, math.max(40, shellW - 60), SHELL_HEADER_H)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.accentId or "")), 24, 0, math.max(1, shellW - 48), SHELL_HEADER_H)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.sizeBadgeId or "")), shellW - 44, 8, 34, 14)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. ".patchbayPanel"), 0, SHELL_HEADER_H, shellW, contentH)
  setBounds(getScopedWidget(ctx, "." .. tostring(module.shellId or "") .. "." .. tostring(module.componentId or "")), 0, SHELL_HEADER_H, shellW, contentH)
end

local function categoryLabel(module)
  local category = tostring(module and module.category or "")
  if category == "audio" then return "Audio" end
  if category == "fx" then return "FX" end
  if category == "voice" then return "Voice" end
  if category == "mod" then return "Mod" end
  return category ~= "" and category or "Module"
end

local function sizeLabelList(validSizes)
  local out = {}
  if type(validSizes) ~= "table" then
    return { "1x1" }
  end
  for i = 1, #validSizes do
    out[i] = tostring(validSizes[i])
  end
  if #out == 0 then
    out[1] = "1x1"
  end
  return out
end

local function moduleByIndex(index)
  local resolved = math.max(1, math.min(#MODULES, round(index)))
  return MODULES[resolved], resolved
end

local function currentSizeFor(ctx, module)
  ctx.state = ctx.state or {}
  ctx.state.sizeByModuleId = ctx.state.sizeByModuleId or {}
  local sizeKey = tostring(ctx.state.sizeByModuleId[module.id] or module.defaultSize or "1x1")
  local valid = module.validSizes or {}
  for i = 1, #valid do
    if tostring(valid[i]) == sizeKey then
      return sizeKey
    end
  end
  return tostring(module.defaultSize or valid[1] or "1x1")
end

local function setCurrentSize(ctx, module, sizeKey)
  ctx.state = ctx.state or {}
  ctx.state.sizeByModuleId = ctx.state.sizeByModuleId or {}
  local fallback = tostring(module.defaultSize or "1x1")
  local resolved = fallback
  for i = 1, #(module.validSizes or {}) do
    if tostring(module.validSizes[i]) == tostring(sizeKey) then
      resolved = tostring(sizeKey)
      break
    end
  end
  ctx.state.sizeByModuleId[module.id] = resolved
  return resolved
end

local function cycleSize(ctx, module)
  local sizes = module.validSizes or {}
  if #sizes <= 1 then
    return currentSizeFor(ctx, module)
  end
  local current = currentSizeFor(ctx, module)
  local currentIndex = 1
  for i = 1, #sizes do
    if tostring(sizes[i]) == current then
      currentIndex = i
      break
    end
  end
  local nextIndex = currentIndex + 1
  if nextIndex > #sizes then
    nextIndex = 1
  end
  return setCurrentSize(ctx, module, tostring(sizes[nextIndex]))
end

local function moduleNoteText(module)
  local modeText = ""
  if module.kind == "source" then
    modeText = "MIDI drives the source directly."
  elseif module.kind == "audio" then
    modeText = "Audio Input A feeds the processor. Blend additionally uses Input B."
  elseif module.kind == "voice" then
    modeText = "Incoming MIDI voices are transformed by the selected module, then auditioned through a hidden rack oscillator."
  elseif module.kind == "scalar" then
    modeText = "The selected modulation runtime is driven by internal test signals and auditioned through a hidden rack oscillator."
  end
  local sizeText = table.concat(sizeLabelList(module.validSizes), ", ")
  local desc = tostring(module.description or "")
  local summary = tostring(module.portSummary or "")
  if summary ~= "" then
    summary = "Ports: " .. summary
  end
  return table.concat({
    desc,
    summary,
    "Valid sizes: " .. sizeText,
    modeText,
  }, "\n")
end

local function moduleStatusText(module, sizeKey)
  local size = Registry.sizePixels(sizeKey)
  return string.format(
    "%s • %s • %s (%d×%d canonical px)",
    categoryLabel(module),
    tostring(module.label or module.id),
    tostring(sizeKey),
    math.floor(size.w),
    math.floor(size.h)
  )
end

local function activeVoiceCount(ctx)
  local count = 0
  local voices = ctx._midiVoices or {}
  for i = 1, #voices do
    local voice = voices[i]
    if type(voice) == "table" and (voice.active == true or (tonumber(voice.gate) or 0.0) > 0.5) then
      count = count + 1
    end
  end
  return count
end

local function newVoice()
  return {
    active = false,
    note = 60.0,
    gate = 0.0,
    stamp = 0,
    targetAmp = 0.0,
    currentAmp = 0.0,
    envelopeLevel = 0.0,
    envelopeStage = "idle",
    envelopeTime = 0.0,
    envelopeStartLevel = 0.0,
  }
end

local function velocityToAmp(velocity)
  return clamp((tonumber(velocity) or 0.0) / 127.0, 0.0, 1.0)
end

local function chooseVoice(ctx)
  local voices = ctx._midiVoices or {}
  for i = 1, VOICE_COUNT do
    local voice = voices[i]
    if not voice or voice.active ~= true or (tonumber(voice.gate) or 0.0) <= 0.5 then
      return i
    end
  end
  local oldestIndex = 1
  local oldestStamp = tonumber(voices[1] and voices[1].stamp) or 0
  for i = 2, VOICE_COUNT do
    local stamp = tonumber(voices[i] and voices[i].stamp) or 0
    if stamp < oldestStamp then
      oldestIndex = i
      oldestStamp = stamp
    end
  end
  return oldestIndex
end

local function triggerVoice(ctx, note, velocity)
  local voices = ctx._midiVoices or {}
  local index = chooseVoice(ctx)
  local voice = voices[index]
  if not voice then
    return nil
  end
  ctx._voiceStamp = (ctx._voiceStamp or 0) + 1
  voice.active = true
  voice.note = clamp(note, 0, 127)
  voice.gate = 1.0
  voice.noteGate = 1.0
  voice.stamp = ctx._voiceStamp
  voice.targetAmp = velocityToAmp(velocity)
  voice.currentAmp = voice.targetAmp
  voice.envelopeLevel = voice.targetAmp
  voice.envelopeStage = "sustain"
  voice.envelopeTime = 0.0
  voice.envelopeStartLevel = 0.0
  return index
end

local function releaseVoice(ctx, note)
  local voices = ctx._midiVoices or {}
  for i = 1, VOICE_COUNT do
    local voice = voices[i]
    if type(voice) == "table" and voice.active == true and round(voice.note) == round(note) then
      voice.gate = 0.0
      voice.noteGate = 0.0
      voice.currentAmp = 0.0
      voice.envelopeLevel = 0.0
      voice.envelopeStage = "idle"
      voice.active = false
    end
  end
end

local function panicVoices(ctx)
  local voices = ctx._midiVoices or {}
  for i = 1, VOICE_COUNT do
    voices[i] = voices[i] or newVoice()
    local voice = voices[i]
    voice.active = false
    voice.note = 60.0
    voice.gate = 0.0
    voice.noteGate = 0.0
    voice.targetAmp = 0.0
    voice.currentAmp = 0.0
    voice.envelopeLevel = 0.0
    voice.envelopeStage = "idle"
    voice.envelopeTime = 0.0
    voice.envelopeStartLevel = 0.0
  end
end

local function midiBundleFromVoice(voice, voiceIndex)
  local gate = ((tonumber(voice and voice.gate) or 0.0) > 0.5) and 1.0 or 0.0
  local amp = math.max(0.0, tonumber(voice and voice.targetAmp) or 0.0)
  local current = math.max(0.0, tonumber(voice and voice.currentAmp) or amp)
  local stage = tostring(voice and voice.envelopeStage or (gate > 0.5 and "sustain" or "idle"))
  return {
    note = clamp(tonumber(voice and voice.note) or 60.0, 0.0, 127.0),
    gate = gate,
    noteGate = gate,
    amp = amp,
    targetAmp = amp,
    currentAmp = current,
    envelopeLevel = math.max(0.0, tonumber(voice and voice.envelopeLevel) or current),
    envelopeStage = stage,
    active = voice and voice.active == true or gate > 0.5,
    sourceVoiceIndex = math.max(1, math.floor(tonumber(voiceIndex) or 1)),
  }
end

local updateVisibility
local updateLayout
local syncFromParams
local syncPatchView
local currentViewMode

local function requestLayoutRefresh(ctx, reason)
  if type(ctx) ~= "table" then
    return
  end
  ctx._layoutDirty = true
  ctx._layoutRetries = math.max(tonumber(ctx._layoutRetries) or 0, 8)
  ctx._layoutDirtyReason = tostring(reason or "layout")
end

local function currentLayoutKey(ctx)
  local module = moduleByIndex(ctx and ctx.state and ctx.state.moduleIndex or 1)
  local surface = ctx and ctx.widgets and ctx.widgets.module_surface or nil
  local surfaceW = surface and surface.node and tonumber(surface.node:getWidth()) or 0
  local surfaceH = surface and surface.node and tonumber(surface.node:getHeight()) or 0
  local moduleId = module and tostring(module.id or "") or ""
  local sizeKey = module and currentSizeFor(ctx, module) or "1x1"
  local viewMode = currentViewMode(ctx)
  return table.concat({ moduleId, sizeKey, viewMode, tostring(math.floor(surfaceW + 0.5)), tostring(math.floor(surfaceH + 0.5)) }, ":")
end

local function maybeApplyPendingLayout(ctx)
  if type(ctx) ~= "table" then
    return false
  end
  local layoutKey = currentLayoutKey(ctx)
  local shouldApply = (ctx._lastAppliedLayoutKey ~= layoutKey) or (ctx._layoutDirty == true)
  if not shouldApply then
    return false
  end
  updateVisibility(ctx)
  updateLayout(ctx)
  syncPatchView(ctx)
  ctx._lastAppliedLayoutKey = layoutKey
  local retries = math.max(0, math.floor(tonumber(ctx._layoutRetries) or 0) - 1)
  ctx._layoutRetries = retries
  ctx._layoutDirty = retries > 0 and true or false
  return true
end

local function setDropdownOptionsDirect(widget, options)
  if not widget then return false end
  local record = widget._structuredRecord
  if record and record.spec and record.spec.props then
    record.spec.props.options = options
    if widget.node and widget.node.repaint then
      widget.node:repaint()
    end
    return true
  end
  return false
end

local function setDropdownSelectedDirect(widget, idx)
  if not widget then return false end
  local record = widget._structuredRecord
  if record and record.spec and record.spec.props then
    record.spec.props.selected = idx
    if widget.node and widget.node.repaint then
      widget.node:repaint()
    end
    return true
  end
  return false
end

local function refreshMidiDevices(ctx, restoreSelection)
  local runtime = _G.__manifoldStructuredUiRuntime
  local widgets = runtime and runtime.widgets or {}
  local midiDropdown = widgets["rack_host_root.sidebar.midi_input_dropdown"]
  local deviceValueLabel = widgets["rack_host_root.sidebar.midi_device_value"]

  local devices = Midi and Midi.inputDevices and Midi.inputDevices() or {}
  local options = { "None (Disabled)" }
  for _, name in ipairs(devices) do
    table.insert(options, name)
  end
  ctx._midiOptions = options

  if midiDropdown then
    setDropdownOptionsDirect(midiDropdown, options)
    setDropdownSelectedDirect(midiDropdown, 1)
  end
  if deviceValueLabel then
    local record = deviceValueLabel._structuredRecord
    if record and record.spec and record.spec.props then
      record.spec.props.text = "Input: None (Disabled)"
      if deviceValueLabel.node and deviceValueLabel.node.repaint then
        deviceValueLabel.node:repaint()
      end
    end
  end
end

local function maybeRefreshMidiDevices(ctx, now)
  MidiDevices.maybeRefreshMidiDevices(ctx, now)
end

local function installGlobals(ctx)
  _G.__midiSynthDynamicModuleInfo = MODULE_INFO_MAP
  _G.__midiSynthSetAuthoredParam = function(path, value)
    return writeParam(path, value)
  end
  for i = 1, #MODULES do
    local module = MODULES[i]
    PatchbayRuntime.registerShellMapping(module.shellId, module.instanceNodeId, module.id, module.componentId)
  end
  _G.__rackModuleHostState = ctx.state
  _G.__rackModuleHostSelectModule = function(moduleIdOrIndex)
    local index = tonumber(moduleIdOrIndex)
    if index == nil then
      index = MODULE_INDEX_BY_ID[tostring(moduleIdOrIndex or "")]
    end
    index = math.max(1, math.min(#MODULES, round(index or 1)))
    writeParam(HOST_PATHS.moduleIndex, index)
    ctx.state.moduleIndex = index
    requestLayoutRefresh(ctx, "select-module")
    maybeApplyPendingLayout(ctx)
    return true
  end
  _G.__rackModuleHostSetSize = function(moduleIdOrIndex, sizeKey)
    local index = tonumber(moduleIdOrIndex)
    if index == nil then
      index = MODULE_INDEX_BY_ID[tostring(moduleIdOrIndex or "")]
    end
    index = math.max(1, math.min(#MODULES, round(index or 1)))
    local module = MODULES[index]
    if not module then
      return false
    end
    setCurrentSize(ctx, module, tostring(sizeKey or module.defaultSize or "1x1"))
    ctx.state.moduleIndex = index
    requestLayoutRefresh(ctx, "set-size")
    maybeApplyPendingLayout(ctx)
    return true
  end
  _G.__rackModuleHostValidSizes = function(moduleIdOrIndex)
    local index = tonumber(moduleIdOrIndex)
    if index == nil then
      index = MODULE_INDEX_BY_ID[tostring(moduleIdOrIndex or "")]
    end
    index = math.max(1, math.min(#MODULES, round(index or 1)))
    local module = MODULES[index]
    local out = {}
    if module and type(module.validSizes) == "table" then
      for i = 1, #module.validSizes do
        out[i] = tostring(module.validSizes[i])
      end
    end
    return out
  end
  _G.__rackModuleHostNoteOn = function(note, velocity)
    triggerVoice(ctx, tonumber(note) or 60, tonumber(velocity) or 100)
    return true
  end
  _G.__rackModuleHostNoteOff = function(note)
    releaseVoice(ctx, tonumber(note) or 60)
    return true
  end
  _G.__rackModuleHostPanic = function()
    panicVoices(ctx)
    return true
  end
  ctx._voices = ctx._midiVoices
end

local function setAuditionVoice(voiceIndex, note, gate)
  writeParam(ParameterBinder.dynamicOscillatorVoiceVOctPath(Registry.AUDITION_OSC_SLOT_INDEX, voiceIndex), clamp(note, 0, 127))
  writeParam(ParameterBinder.dynamicOscillatorVoiceGatePath(Registry.AUDITION_OSC_SLOT_INDEX, voiceIndex), clamp01(gate))
end

local function silenceAuditionOscillator(ctx)
  writeParam(AUDITION_OSC_BASE .. "/manualLevel", 0.0)
  for i = 1, VOICE_COUNT do
    setAuditionVoice(i, 60, 0)
  end
end

local function syncPrimarySourceVoices(ctx)
  local voices = ctx._midiVoices or {}
  for i = 1, VOICE_COUNT do
    local bundle = midiBundleFromVoice(voices[i], i)
    writeParam(ParameterBinder.dynamicOscillatorVoiceVOctPath(Registry.PRIMARY_SLOT_INDEX, i), bundle.note)
    writeParam(ParameterBinder.dynamicOscillatorVoiceGatePath(Registry.PRIMARY_SLOT_INDEX, i), bundle.gate > 0.5 and bundle.amp or 0.0)
    writeParam(ParameterBinder.dynamicSampleVoiceVOctPath(Registry.PRIMARY_SLOT_INDEX, i), bundle.note)
    writeParam(ParameterBinder.dynamicSampleVoiceGatePath(Registry.PRIMARY_SLOT_INDEX, i), bundle.gate > 0.5 and bundle.amp or 0.0)
  end
end

local function pushVoiceRuntimeToAudition(ctx, module, runtime, dt)
  local sourceMeta = { meta = { specId = module.id, portId = "voice", moduleId = module.instanceNodeId } }
  local voices = ctx._midiVoices or {}
  for i = 1, VOICE_COUNT do
    local bundle = midiBundleFromVoice(voices[i], i)
    local meta = {
      voiceIndex = i,
      action = bundle.gate > 0.5 and "apply" or "restore",
      bundleSample = bundle,
      bundleSourceId = "midi.voice",
      bundleSource = { meta = { specId = "midi", portId = "voice", moduleId = "midi_host" } },
    }
    if module.id == "adsr" then
      runtime.applyInputVoice(ctx, module.instanceNodeId, "midi", bundle.gate, meta, VOICE_COUNT, clamp)
    else
      runtime.applyInputVoice(ctx, module.instanceNodeId, "voice_in", bundle.gate, meta, VOICE_COUNT, clamp)
    end
  end

  if module.id == "adsr" then
    runtime.updateDynamicModules(ctx, dt, readParam, clamp, VOICE_COUNT)
  else
    runtime.updateDynamicModules(ctx, dt, readParam, VOICE_COUNT)
  end

  writeParam(AUDITION_OSC_BASE .. "/manualLevel", 0.0)
  for i = 1, VOICE_COUNT do
    local bundle = runtime.resolveVoiceBundleSample(ctx, module.id .. ".voice", sourceMeta, i, clamp)
    if type(bundle) == "table" and (bundle.active == true or (tonumber(bundle.gate) or 0.0) > 0.5 or (tonumber(bundle.currentAmp) or 0.0) > 0.0001) then
      local gate = tonumber(bundle.currentAmp)
      if gate == nil then
        gate = tonumber(bundle.amp)
      end
      if gate == nil then
        gate = tonumber(bundle.targetAmp)
      end
      if gate == nil then
        gate = tonumber(bundle.gate)
      end
      setAuditionVoice(i, tonumber(bundle.note) or 60.0, clamp01(gate or 0.0))
    else
      setAuditionVoice(i, 60, 0.0)
    end
  end
end

local function testSignalState(ctx, now)
  local aLevel = clamp01(ctx.state.inputALevel or 0.65)
  local bLevel = clamp01(ctx.state.inputBLevel or 0.5)
  local aPitch = clamp(ctx.state.inputAPitch or 60, 24, 84)
  local bPitch = clamp(ctx.state.inputBPitch or 67, 24, 84)
  local aRate = clamp(0.125 * (2.0 ^ ((aPitch - 60.0) / 12.0)), 0.05, 20.0)
  local bRate = clamp(0.125 * (2.0 ^ ((bPitch - 60.0) / 12.0)), 0.05, 20.0)
  local aPhase = (now * aRate) % 1.0
  local bPhase = (now * bRate) % 1.0
  local sine = math.sin(aPhase * math.pi * 2.0) * aLevel
  local tri = ((bPhase < 0.5) and ((bPhase * 4.0) - 1.0) or (3.0 - (bPhase * 4.0))) * bLevel
  local saw = (((aPhase * 2.0) - 1.0) * 0.75) * aLevel
  local square = (bPhase < 0.5 and 1.0 or -1.0) * bLevel
  local midiGate = activeVoiceCount(ctx) > 0 and 1.0 or 0.0
  local clockGate = midiGate > 0.5 and 1.0 or ((aPhase < 0.1) and 1.0 or 0.0)
  return {
    a = clamp(sine, -1.0, 1.0),
    b = clamp(tri, -1.0, 1.0),
    c = clamp(saw, -1.0, 1.0),
    d = clamp(square, -1.0, 1.0),
    gate = clamp(clockGate, 0.0, 1.0),
    midiGate = clamp(midiGate, 0.0, 1.0),
  }
end

local function primaryAuditionPort(module)
  local port = tostring(module and module.auditionOutputPort or "")
  if port ~= "" then
    return port
  end
  return "out"
end

local function updateScalarRuntimeAudition(ctx, module, runtime, dt, now)
  local s = testSignalState(ctx, now)
  if module.id == "attenuverter_bias" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in", s.a)
  elseif module.id == "lfo" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "reset", s.midiGate)
    runtime.applyInputScalar(ctx, module.instanceNodeId, "sync", s.gate)
  elseif module.id == "slew" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in", s.a)
  elseif module.id == "sample_hold" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in", s.a)
    runtime.applyInputScalar(ctx, module.instanceNodeId, "trig", s.gate)
  elseif module.id == "compare" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in", s.a)
  elseif module.id == "cv_mix" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in_1", s.a)
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in_2", s.b)
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in_3", s.c)
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in_4", s.d)
  elseif module.id == "range_mapper" then
    runtime.applyInputScalar(ctx, module.instanceNodeId, "in", s.a)
  end

  runtime.updateDynamicModules(ctx, dt, readParam)

  local portId = primaryAuditionPort(module)
  local source = runtime.resolveScalarModulationSource(ctx, module.id .. "." .. portId, {
    meta = {
      specId = module.id,
      portId = portId,
      moduleId = module.instanceNodeId,
    }
  }) or { rawSourceValue = 0.0 }

  local value = clamp(tonumber(source.rawSourceValue) or 0.0, -1.0, 1.0)
  for i = 1, VOICE_COUNT do
    setAuditionVoice(i, 60, 0.0)
  end
  writeParam(AUDITION_OSC_BASE .. "/manualPitch", 60.0 + (value * 24.0))
  writeParam(AUDITION_OSC_BASE .. "/manualLevel", 0.35)
end

local function updateModuleRuntime(ctx, dt, now)
  local module = moduleByIndex(ctx.state.moduleIndex or 1)
  if not module then
    silenceAuditionOscillator(ctx)
    return
  end

  syncPrimarySourceVoices(ctx)

  if module.kind == "voice" then
    local runtime = VOICE_RUNTIME_BY_ID[module.id]
    if runtime then
      pushVoiceRuntimeToAudition(ctx, module, runtime, dt)
    else
      silenceAuditionOscillator(ctx)
    end
  elseif module.kind == "scalar" then
    local runtime = SCALAR_RUNTIME_BY_ID[module.id]
    if runtime then
      updateScalarRuntimeAudition(ctx, module, runtime, dt, now)
    else
      silenceAuditionOscillator(ctx)
    end
  else
    silenceAuditionOscillator(ctx)
  end
end

currentViewMode = function(ctx)
  local value = round(ctx and ctx.state and ctx.state.viewMode or 1)
  return (value == 2) and "patch" or "perf"
end

local function activeRackNode(module, sizeKey)
  local size = Registry.sizePixels(sizeKey)
  return {
    id = module.instanceNodeId,
    row = 0,
    col = 0,
    w = math.max(1, tonumber(size.cols) or 1),
    h = math.max(1, tonumber(size.rows) or 1),
    sizeKey = sizeKey,
    meta = { componentId = module.componentId },
  }
end

syncPatchView = function(ctx)
  local module = moduleByIndex(ctx.state.moduleIndex or 1)
  if not module then
    return
  end
  local sizeKey = currentSizeFor(ctx, module)
  ctx._rackState = {
    viewMode = currentViewMode(ctx),
    modules = { activeRackNode(module, sizeKey) },
  }
  ctx._rackConnections = {}
  ctx._rackModuleSpecs = ctx._rackModuleSpecs or {}
  if ctx._rackModuleSpecs[module.id] == nil and type(module.spec) == "table" then
    ctx._rackModuleSpecs[module.id] = module.spec
  end
  PatchbayRuntime.syncPatchViewMode(ctx, {
    getScopedWidget = getScopedWidget,
    getWidgetBoundsInRoot = getWidgetBoundsInRoot,
    round = round,
    readParam = readParam,
    setPath = writeParam,
    setWidgetValueSilently = setWidgetValueSilently,
    PATHS = {
      sampleLoopStart = ParameterBinder.dynamicSampleLoopStartPath(Registry.PRIMARY_SLOT_INDEX),
      sampleLoopLen = ParameterBinder.dynamicSampleLoopLenPath(Registry.PRIMARY_SLOT_INDEX),
      blendAmount = ParameterBinder.dynamicBlendSimpleBlendAmountPath(Registry.PRIMARY_SLOT_INDEX),
    },
  })
  PatchbayRuntime.syncValues(ctx, {
    readParam = readParam,
    setWidgetValueSilently = setWidgetValueSilently,
  })
end

updateVisibility = function(ctx)
  local widgets = ctx.widgets or {}
  local module, index = moduleByIndex(ctx.state.moduleIndex or 1)
  if not module then
    return
  end

  local sizeKey = currentSizeFor(ctx, module)
  local isPatch = currentViewMode(ctx) == "patch"
  for i = 1, #MODULES do
    local entry = MODULES[i]
    setVisible(widgets[entry.displayId], i == index)
    setVisible(widgets[entry.shellId], true)
    setVisible(widgets[entry.deleteButtonId], false)
    local showResize = i == index and #(entry.validSizes or {}) > 1 and not isPatch
    setVisible(widgets[entry.resizeButtonId], showResize)
    if widgets[entry.resizeButtonId] and widgets[entry.resizeButtonId].setLabel then
      widgets[entry.resizeButtonId]:setLabel("")
    end
    if widgets[entry.sizeBadgeId] and widgets[entry.sizeBadgeId].setText then
      widgets[entry.sizeBadgeId]:setText(i == index and sizeKey or tostring(entry.defaultSize or "1x1"))
    end
  end

  setVisible(widgets.input_b_group, module.id == "blend_simple")
  setText(widgets.module_status, moduleStatusText(module, sizeKey))
  setText(widgets.module_note, moduleNoteText(module))
  syncDropdown(widgets.module_selector, nil, index)
  syncDropdown(widgets.view_selector, { "Performance", "Patch" }, currentViewMode(ctx) == "patch" and 2 or 1)
  syncDropdown(widgets.size_selector, sizeLabelList(module.validSizes), 1)
  local validSizes = sizeLabelList(module.validSizes)
  for i = 1, #validSizes do
    if validSizes[i] == sizeKey then
      syncDropdown(widgets.size_selector, validSizes, i)
      break
    end
  end
end

updateLayout = function(ctx)
  local widgets = ctx.widgets or {}
  local module = moduleByIndex(ctx.state.moduleIndex or 1)
  if not module then
    return
  end

  local surface = widgets.module_surface
  local displayWidget = widgets[module.displayId]
  local shellWidget = widgets[module.shellId]
  if not (surface and surface.node and displayWidget and displayWidget.node and shellWidget and shellWidget.node) then
    return
  end

  local surfaceW = tonumber(surface.node:getWidth()) or 0
  local surfaceH = tonumber(surface.node:getHeight()) or 0
  if surfaceW <= 0 or surfaceH <= 0 then
    return
  end

  local sizeKey = currentSizeFor(ctx, module)
  local size = Registry.sizePixels(sizeKey)
  local canonicalW = math.max(1, math.floor(tonumber(size.w) or 1))
  local canonicalH = math.max(1, math.floor(tonumber(size.h) or 1))
  local isPatch = currentViewMode(ctx) == "patch"

  -- Calculate scale based on 2x2 canonical size so 1x1 and 2x2 use the same scale
  local size2x2 = Registry.sizePixels("2x2")
  local canonicalW2x2 = math.max(1, math.floor(tonumber(size2x2 and size2x2.w) or 472))
  local canonicalH2x2 = math.max(1, math.floor(tonumber(size2x2 and size2x2.h) or 416))

  local targetScale = MAX_DISPLAY_SCALE
  local maxDisplayW = math.max(1, surfaceW - (LAYOUT_PADDING * 2))
  local maxDisplayH = math.max(1, surfaceH - (LAYOUT_PADDING * 2) - (isPatch and 0 or (ADAPTIVE_MIN_H + ADAPTIVE_GAP)))
  targetScale = math.min(targetScale, maxDisplayW / canonicalW2x2, maxDisplayH / canonicalH2x2)
  if not (targetScale > 0.0) then
    targetScale = 1.0
  end

  local displayW = math.max(1, math.floor((canonicalW * targetScale) + 0.5))
  local displayH = math.max(1, math.floor((canonicalH * targetScale) + 0.5))
  local displayX = math.floor((surfaceW - displayW) * 0.5)
  local displayY = LAYOUT_PADDING

  setBounds(displayWidget, displayX, displayY, displayW, displayH)
  setBounds(shellWidget, 0, 0, displayW, displayH)
  if shellWidget.node.setTransform then
    shellWidget.node:setTransform(1.0, 1.0, 0, 0)
  end
  layoutShellWidgets(ctx, module, displayW, displayH)
  notifyModuleResized(ctx, module, displayW, math.max(1, displayH - SHELL_HEADER_H))

  local remaining = math.max(0, surfaceH - (displayY + displayH + LAYOUT_PADDING))
  local adaptiveVisible = (not isPatch) and remaining >= ADAPTIVE_MIN_H
  local adaptiveX = LAYOUT_PADDING
  local adaptiveY = adaptiveVisible and (displayY + displayH + ADAPTIVE_GAP) or (surfaceH - 1)
  local adaptiveW = maxDisplayW
  local adaptiveFinalH = adaptiveVisible and math.max(1, remaining - ADAPTIVE_GAP) or 1
  local adaptiveWidget = widgets.adaptive_container
  setBounds(adaptiveWidget, adaptiveX, adaptiveY, adaptiveW, adaptiveFinalH)
  setVisible(adaptiveWidget, adaptiveVisible)

  if widgets.adaptive_container_title and widgets.adaptive_container_title.setText then
    widgets.adaptive_container_title:setText("Adaptive container")
  end
  if widgets.adaptive_container_note and widgets.adaptive_container_note.setText then
    widgets.adaptive_container_note:setText(string.format("Reserved vertical space below %s. Actual size mode: %s. Canonical shell: %dx%d. View scale %.2fx.", tostring(module.label), tostring(sizeKey), canonicalW, canonicalH, targetScale))
  end

  _G.__rackModuleHostDebug = {
    selectedModuleId = module.id,
    selectedModuleLabel = module.label,
    selectedModuleKind = module.kind,
    selectedSizeKey = sizeKey,
    viewMode = currentViewMode(ctx),
    canonicalSize = { w = canonicalW, h = canonicalH },
    displayScale = targetScale,
    moduleBounds = { x = displayX, y = displayY, w = displayW, h = displayH },
    shellBounds = { x = 0, y = 0, w = displayW, h = displayH },
    adaptiveBounds = { x = adaptiveX, y = adaptiveY, w = adaptiveW, h = adaptiveFinalH, visible = adaptiveVisible },
    viewportBounds = { w = surfaceW, h = surfaceH },
    inputA = {
      mode = ctx.state.inputAMode,
      pitch = ctx.state.inputAPitch,
      level = ctx.state.inputALevel,
    },
    inputB = {
      mode = ctx.state.inputBMode,
      pitch = ctx.state.inputBPitch,
      level = ctx.state.inputBLevel,
    },
    activeVoices = activeVoiceCount(ctx),
  }
end

local function enforceCurrentModuleLayout(ctx)
  local module = moduleByIndex(ctx and ctx.state and ctx.state.moduleIndex or 1)
  if not module then
    return
  end
  local sizeKey = currentSizeFor(ctx, module)
  local size = Registry.sizePixels(sizeKey)
  notifyModuleResized(ctx, module, math.max(1, tonumber(size.w) or 1), math.max(1, tonumber(size.h) or 1) - SHELL_HEADER_H)
end

syncFromParams = function(ctx)
  ctx.state = ctx.state or {}
  local changed = false

  local function assignState(key, value)
    if ctx.state[key] ~= value then
      ctx.state[key] = value
      changed = true
    end
  end

  assignState("moduleIndex", clamp(readParam(HOST_PATHS.moduleIndex, ctx.state.moduleIndex or 1), 1, #MODULES))
  assignState("viewMode", clamp(readParam(HOST_PATHS.viewMode, ctx.state.viewMode or 1), 1, VIEW_MODE_COUNT))
  assignState("inputAMode", clamp(readParam(HOST_PATHS.inputAMode, ctx.state.inputAMode or 3), 1, SOURCE_MODE_COUNT))
  assignState("inputAPitch", clamp(readParam(HOST_PATHS.inputAPitch, ctx.state.inputAPitch or 60), 24, 84))
  assignState("inputALevel", clamp(readParam(HOST_PATHS.inputALevel, ctx.state.inputALevel or 0.65), 0, 1))
  assignState("inputBMode", clamp(readParam(HOST_PATHS.inputBMode, ctx.state.inputBMode or 4), 1, SOURCE_MODE_COUNT))
  assignState("inputBPitch", clamp(readParam(HOST_PATHS.inputBPitch, ctx.state.inputBPitch or 67), 24, 84))
  assignState("inputBLevel", clamp(readParam(HOST_PATHS.inputBLevel, ctx.state.inputBLevel or 0.5), 0, 1))

  local widgets = ctx.widgets or {}
  syncDropdown(widgets.module_selector, nil, ctx.state.moduleIndex)
  syncDropdown(widgets.view_selector, { "Performance", "Patch" }, ctx.state.viewMode)
  syncDropdown(widgets.input_a_mode, nil, ctx.state.inputAMode)
  syncSlider(widgets.input_a_pitch, ctx.state.inputAPitch)
  syncSlider(widgets.input_a_level, ctx.state.inputALevel)
  syncDropdown(widgets.input_b_mode, nil, ctx.state.inputBMode)
  syncSlider(widgets.input_b_pitch, ctx.state.inputBPitch)
  syncSlider(widgets.input_b_level, ctx.state.inputBLevel)

  if changed then
    requestLayoutRefresh(ctx, "param-sync")
  end
  maybeApplyPendingLayout(ctx)

  -- Refresh MIDI devices once widgets are available (fixes initial population)
  local midiDropdown = widgets.midi_input_dropdown or widgets["rack_host_root.sidebar.midi_input_dropdown"]
  if midiDropdown and #(ctx._midiOptions or {}) == 0 then
    refreshMidiDevices(ctx, true)
  end
end

local function bindControls(ctx)
  local widgets = ctx.widgets or {}

  -- Find MIDI widgets by full path (scoped widget storage uses full paths)
  widgets.midi_input_dropdown = widgets.midi_input_dropdown or widgets["rack_host_root.sidebar.midi_input_dropdown"]
  widgets.midi_device_value = widgets.midi_device_value or widgets["rack_host_root.sidebar.midi_device_value"]
  widgets.midiInputDropdown = widgets.midi_input_dropdown
  widgets.deviceValue = widgets.midi_device_value

  if widgets.midi_input_dropdown then
    widgets.midi_input_dropdown._onSelect = function(index)
      MidiDevices.applyMidiSelection(ctx, math.max(1, round(index)), true)
    end
  end

  if widgets.view_selector then
    widgets.view_selector._onSelect = function(index)
      local nextValue = clamp(index, 1, VIEW_MODE_COUNT)
      ctx.state.viewMode = nextValue
      writeParam(HOST_PATHS.viewMode, nextValue)
      requestLayoutRefresh(ctx, "view-select")
      maybeApplyPendingLayout(ctx)
    end
  end

  if widgets.module_selector then
    widgets.module_selector._onSelect = function(index)
      local nextValue = clamp(index, 1, #MODULES)
      ctx.state.moduleIndex = nextValue
      writeParam(HOST_PATHS.moduleIndex, nextValue)
      requestLayoutRefresh(ctx, "module-select")
      maybeApplyPendingLayout(ctx)
    end
  end

  if widgets.size_selector then
    widgets.size_selector._onSelect = function(index)
      local module = moduleByIndex(ctx.state.moduleIndex or 1)
      if not module then
        return
      end
      local sizes = sizeLabelList(module.validSizes)
      local sizeKey = tostring(sizes[math.max(1, math.min(#sizes, round(index)))] or module.defaultSize or "1x1")
      setCurrentSize(ctx, module, sizeKey)
      requestLayoutRefresh(ctx, "size-select")
      maybeApplyPendingLayout(ctx)
    end
  end

  if widgets.input_a_mode then
    widgets.input_a_mode._onSelect = function(index)
      local nextValue = clamp(index, 1, SOURCE_MODE_COUNT)
      ctx.state.inputAMode = nextValue
      writeParam(HOST_PATHS.inputAMode, nextValue)
      requestLayoutRefresh(ctx, "input-a-mode")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.input_a_pitch then
    widgets.input_a_pitch._onChange = function(value)
      writeParam(HOST_PATHS.inputAPitch, clamp(round(value), 24, 84))
    end
  end
  if widgets.input_a_level then
    widgets.input_a_level._onChange = function(value)
      writeParam(HOST_PATHS.inputALevel, clamp(value, 0, 1))
    end
  end

  if widgets.input_b_mode then
    widgets.input_b_mode._onSelect = function(index)
      local nextValue = clamp(index, 1, SOURCE_MODE_COUNT)
      ctx.state.inputBMode = nextValue
      writeParam(HOST_PATHS.inputBMode, nextValue)
      requestLayoutRefresh(ctx, "input-b-mode")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.input_b_pitch then
    widgets.input_b_pitch._onChange = function(value)
      writeParam(HOST_PATHS.inputBPitch, clamp(round(value), 24, 84))
    end
  end
  if widgets.input_b_level then
    widgets.input_b_level._onChange = function(value)
      writeParam(HOST_PATHS.inputBLevel, clamp(value, 0, 1))
    end
  end

  for i = 1, #MODULES do
    local module = MODULES[i]
    local resizeButton = widgets[module.resizeButtonId]
    if resizeButton then
      resizeButton._onClick = function()
        cycleSize(ctx, module)
        requestLayoutRefresh(ctx, "resize-button")
        maybeApplyPendingLayout(ctx)
      end
    end
    local deleteButton = widgets[module.deleteButtonId]
    if deleteButton then
      deleteButton._onClick = function()
        setCurrentSize(ctx, module, module.defaultSize)
        requestLayoutRefresh(ctx, "reset-size")
        maybeApplyPendingLayout(ctx)
      end
    end
  end
end

local function initializeAuditionOscillator()
  writeParam(AUDITION_OSC_BASE .. "/waveform", 0)
  writeParam(AUDITION_OSC_BASE .. "/renderMode", 0)
  writeParam(AUDITION_OSC_BASE .. "/pulseWidth", 0.5)
  writeParam(AUDITION_OSC_BASE .. "/output", 0.8)
  writeParam(AUDITION_OSC_BASE .. "/manualPitch", 60.0)
  writeParam(AUDITION_OSC_BASE .. "/manualLevel", 0.0)
  for i = 1, VOICE_COUNT do
    setAuditionVoice(i, 60.0, 0.0)
  end
end

local function pollMidi(ctx)
  if not (Midi and Midi.pollInputEvent) then
    return
  end
  while true do
    local event = Midi.pollInputEvent()
    if not event then break end

    if event.type == Midi.NOTE_ON and (tonumber(event.data2) or 0) > 0 then
      triggerVoice(ctx, tonumber(event.data1) or 60, tonumber(event.data2) or 0)
    elseif event.type == Midi.NOTE_OFF or (event.type == Midi.NOTE_ON and (tonumber(event.data2) or 0) <= 0) then
      releaseVoice(ctx, tonumber(event.data1) or 60)
    elseif Midi.ALL_NOTES_OFF and event.type == Midi.ALL_NOTES_OFF then
      panicVoices(ctx)
    end
  end
end

function M.init(ctx)
  ctx._globalPrefix = ScopedWidget.resolveGlobalPrefix(ctx)
  ctx.state = { sizeByModuleId = {} }
  ctx._midiOptions = { "None (Disabled)" }
  ctx._midiDevices = {}
  ctx._midiVoices = {}
  ctx._voices = ctx._midiVoices
  ctx._voiceStamp = 0
  for i = 1, VOICE_COUNT do
    ctx._midiVoices[i] = newVoice()
  end
  ctx._rackModuleSpecs = {}
  for i = 1, #MODULES do
    ctx.state.sizeByModuleId[MODULES[i].id] = MODULES[i].defaultSize
    ctx._rackModuleSpecs[MODULES[i].id] = MODULES[i].spec
  end
  installGlobals(ctx)
  bindControls(ctx)
  refreshMidiDevices(ctx, true)
  initializeAuditionOscillator()
  requestLayoutRefresh(ctx, "init")
  syncFromParams(ctx)
end

function M.update(ctx)
  installGlobals(ctx)
  local now = type(getTime) == "function" and getTime() or 0.0
  local dt = now - (ctx._lastUpdateTime or now)
  if dt < 0 then dt = 0 end
  if dt > 0.05 then dt = 0.05 end
  ctx._lastUpdateTime = now

  -- One-time MIDI setup once widgets are available
  if not ctx._midiInitialized then
    local runtime = _G.__manifoldStructuredUiRuntime
    local widgets = runtime and runtime.widgets or {}
    local midiDropdown = widgets["rack_host_root.sidebar.midi_input_dropdown"]
    if midiDropdown then
      ctx._midiInitialized = true
      -- Re-bind controls now that widgets exist
      bindControls(ctx)
      -- Populate MIDI device list
      refreshMidiDevices(ctx, true)
    end
  end

  maybeRefreshMidiDevices(ctx, now)
  pollMidi(ctx)
  updateModuleRuntime(ctx, dt, now)
  maybeApplyPendingLayout(ctx)

  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncFromParams(ctx)
  end
end

return M

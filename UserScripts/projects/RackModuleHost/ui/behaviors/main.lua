local Registry = require("module_host_registry")
local ParameterBinder = require("parameter_binder")
package.loaded["ui.midi_devices"] = nil
local MidiDevices = require("ui.midi_devices")
local PatchbayRuntime = require("ui.patchbay_runtime")
local ScopedWidget = require("ui.scoped_widget")
local RuntimeHelpers = require("shell.runtime_script_utils")

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
local WORKSPACE_MIN_H = 180
local WORKSPACE_GAP = 16
local SHELL_HEADER_H = 12
local MAX_DISPLAY_SCALE = 2.0
local FILE_POLL_INTERVAL = 0.5

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

local parseDspGraphFromCode = RuntimeHelpers.parseDspGraphFromCode

local function dirname(path)
  return (tostring(path or ""):gsub("/+$", ""):match("^(.*)/[^/]+$") or ".")
end

local function join(...)
  local parts = { ... }
  local out = ""
  for i = 1, #parts do
    local part = tostring(parts[i] or "")
    if part ~= "" then
      if out == "" then
        out = part
      else
        out = out:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
      end
    end
  end
  return out
end

local PROJECT_ROOT = tostring(_G.__manifoldProjectRoot or dirname(_G.__manifoldProjectManifest or ""))
local MAIN_ROOT = join(PROJECT_ROOT, "../Main")

local function pathStem(path)
  local p = tostring(path or "")
  local stem = p:match("([^/]+)$") or p
  return stem
end

local function readText(path)
  if type(readTextFile) ~= "function" or type(path) ~= "string" or path == "" then
    return ""
  end
  local ok, text = pcall(readTextFile, path)
  if ok and type(text) == "string" then
    return text
  end
  return ""
end

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
    behavior.ctx.instanceProps = type(behavior.ctx.instanceProps) == "table" and behavior.ctx.instanceProps or {}
    local sizeKey = tostring(ctx and ctx.state and ctx.state.sizeByModuleId and ctx.state.sizeByModuleId[module.id] or module.defaultSize or "1x1")
    behavior.ctx.instanceProps.sizeKey = sizeKey
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

local SIDEBAR_PARAM_WIDGET_IDS = {
  "input_a_title",
  "input_a_mode",
  "input_a_pitch",
  "input_a_level",
  "input_b_group",
  "routing_hint",
  "module_note",
}

local function moduleImplementationPath(module)
  local id = tostring(module and module.id or "")
  if id == "rack_oscillator" then
    return join(MAIN_ROOT, "lib/rack_modules/oscillator.lua")
  elseif id == "rack_sample" then
    return join(MAIN_ROOT, "lib/rack_modules/sample.lua")
  elseif id == "blend_simple" or id == "filter" or id == "fx" or id == "eq" then
    return join(MAIN_ROOT, "lib/rack_modules/" .. id .. ".lua")
  elseif VOICE_RUNTIME_BY_ID[id] or SCALAR_RUNTIME_BY_ID[id] then
    return join(MAIN_ROOT, "lib/" .. id .. "_runtime.lua")
  end
  return ""
end

local function appendFileSection(rows, label)
  rows[#rows + 1] = { section = true, label = label }
end

local function appendFileRow(rows, name, path, kind, role, selected)
  if type(path) ~= "string" or path == "" then
    return
  end
  rows[#rows + 1] = {
    section = false,
    nonInteractive = false,
    kind = kind or "ui",
    ownership = "",
    name = name or pathStem(path),
    label = name or pathStem(path),
    path = path,
    role = role or "file",
    active = selected == true,
    selected = selected == true,
    dirty = false,
  }
end

local function chooseDefaultModuleFileRow(rows)
  local preferredRoles = { "module-behavior", "module-component", "module-dsp", "host-dsp" }
  for r = 1, #preferredRoles do
    for i = 1, #rows do
      local row = rows[i]
      if not row.section and not row.nonInteractive and row.role == preferredRoles[r] then
        return row
      end
    end
  end
  for i = 1, #rows do
    local row = rows[i]
    if not row.section and not row.nonInteractive then
      return row
    end
  end
  return nil
end

local function buildModuleFileRows(ctx, module)
  local rows = {}
  if not module then
    return rows
  end

  local selectedPath = tostring(ctx._selectedFilePath or "")
  appendFileSection(rows, "Plugin Host")
  appendFileRow(rows, "Manifest", join(PROJECT_ROOT, "manifold.project.json5"), "ui", "host-manifest", selectedPath == join(PROJECT_ROOT, "manifold.project.json5"))
  appendFileRow(rows, "Host UI", join(PROJECT_ROOT, "ui/main.ui.lua"), "ui", "host-ui", selectedPath == join(PROJECT_ROOT, "ui/main.ui.lua"))
  appendFileRow(rows, "Host Behavior", join(PROJECT_ROOT, "ui/behaviors/main.lua"), "ui", "host-behavior", selectedPath == join(PROJECT_ROOT, "ui/behaviors/main.lua"))
  appendFileRow(rows, "Host DSP", join(PROJECT_ROOT, "dsp/main.lua"), "dsp", "host-dsp", selectedPath == join(PROJECT_ROOT, "dsp/main.lua"))
  appendFileRow(rows, "Module Registry", join(PROJECT_ROOT, "lib/module_host_registry.lua"), "ui", "host-registry", selectedPath == join(PROJECT_ROOT, "lib/module_host_registry.lua"))
  appendFileRow(rows, "Shared Rack Runtime", join(MAIN_ROOT, "lib/rack_module_host_runtime.lua"), "dsp", "host-runtime", selectedPath == join(MAIN_ROOT, "lib/rack_module_host_runtime.lua"))

  appendFileSection(rows, "Module UI")
  appendFileRow(rows, "UI Behavior", join(PROJECT_ROOT, module.behaviorPath or ""), "ui", "module-behavior", selectedPath == join(PROJECT_ROOT, module.behaviorPath or ""))
  appendFileRow(rows, "UI Component", join(PROJECT_ROOT, module.componentPath or ""), "ui", "module-component", selectedPath == join(PROJECT_ROOT, module.componentPath or ""))
  appendFileRow(rows, "Module Specs", join(MAIN_ROOT, "ui/behaviors/rack_midisynth_specs.lua"), "ui", "module-specs", selectedPath == join(MAIN_ROOT, "ui/behaviors/rack_midisynth_specs.lua"))

  local implPath = moduleImplementationPath(module)
  if implPath ~= "" then
    appendFileSection(rows, "Module DSP")
    appendFileRow(rows, "Runtime Implementation", implPath, "dsp", "module-dsp", selectedPath == implPath)
  end

  return rows
end

local function ensureProjectEditorState(_ctx)
  if type(shell) ~= "table" then
    return nil
  end
  shell.projectScriptEditor = shell.projectScriptEditor or {
    kind = "",
    ownership = "",
    name = "",
    path = "",
    text = "",
    cursorPos = 1,
    selectionAnchor = nil,
    dragAnchorPos = nil,
    scrollRow = 1,
    focused = false,
    status = "",
    lastClickTime = 0,
    lastClickLine = -1,
    clickStreak = 0,
    dirty = false,
    syncToken = 0,
    bodyRect = nil,
  }
  return shell.projectScriptEditor
end

local function loadSelectedFileIntoEditor(ctx, row)
  if type(row) ~= "table" or tostring(row.path or "") == "" then
    return
  end
  local text = readText(row.path)
  ctx._selectedFileRow = row
  ctx._selectedFilePath = row.path
  ctx._selectedFileKind = tostring(row.kind or "ui")
  ctx._selectedFileName = tostring(row.name or pathStem(row.path))
  ctx._selectedFileText = text
  ctx._selectedDiskText = text
  ctx._selectedFileExternalDirty = false
  ctx._graphModel = ctx._selectedFileKind == "dsp" and parseDspGraphFromCode(text) or { nodes = {}, edges = {} }
  ctx._workspaceStatus = "Loaded " .. tostring(ctx._selectedFileName)

  local editorState = ensureProjectEditorState(ctx)
  if editorState then
    editorState.kind = ctx._selectedFileKind
    editorState.ownership = ""
    editorState.name = ctx._selectedFileName
    editorState.path = ctx._selectedFilePath
    editorState.text = ctx._selectedFileText
    editorState.cursorPos = 1
    editorState.selectionAnchor = nil
    editorState.dragAnchorPos = nil
    editorState.scrollRow = 1
    editorState.focused = false
    editorState.status = ctx._workspaceStatus
    editorState.lastClickTime = 0
    editorState.lastClickLine = -1
    editorState.clickStreak = 0
    editorState.dirty = false
    editorState.syncToken = (tonumber(editorState.syncToken) or 0) + 1
  end
end

local function syncEditorTextFromHost(ctx)
  if type(shell) ~= "table" or type(shell.projectScriptEditor) ~= "table" then
    return
  end
  local editorState = shell.projectScriptEditor
  if tostring(editorState.path or "") ~= tostring(ctx._selectedFilePath or "") then
    return
  end
  local nextText = tostring(editorState.text or "")
  if nextText ~= tostring(ctx._selectedFileText or "") then
    ctx._selectedFileText = nextText
    ctx._graphModel = tostring(ctx._selectedFileKind or "") == "dsp" and parseDspGraphFromCode(nextText) or { nodes = {}, edges = {} }
  end
end

local function installEditorActionHandlers(ctx)
  if type(shell) ~= "table" then
    return
  end
  shell.mainScriptEditorActions = {
    save = function(shellRef)
      local ed = type(shellRef) == "table" and shellRef.projectScriptEditor or nil
      if type(ed) ~= "table" or tostring(ed.path or "") == "" or type(writeTextFile) ~= "function" then
        return
      end
      local ok = writeTextFile(ed.path, ed.text or "")
      if ok == false then
        ctx._workspaceStatus = "Save failed"
        return
      end
      ed.dirty = false
      ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
      ctx._selectedFileText = tostring(ed.text or "")
      ctx._selectedDiskText = ctx._selectedFileText
      ctx._selectedFileExternalDirty = false
      ctx._graphModel = tostring(ctx._selectedFileKind or "") == "dsp" and parseDspGraphFromCode(ctx._selectedFileText) or { nodes = {}, edges = {} }
      ctx._workspaceStatus = "Saved " .. tostring(ctx._selectedFileName or pathStem(ed.path))
    end,
    reload = function(shellRef)
      local ed = type(shellRef) == "table" and shellRef.projectScriptEditor or nil
      if type(ed) ~= "table" or tostring(ed.path or "") == "" then
        return
      end
      local text = readText(ed.path)
      ed.text = text
      ed.cursorPos = 1
      ed.selectionAnchor = nil
      ed.dragAnchorPos = nil
      ed.scrollRow = 1
      ed.dirty = false
      ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
      ctx._selectedFileText = text
      ctx._selectedDiskText = text
      ctx._selectedFileExternalDirty = false
      ctx._graphModel = tostring(ctx._selectedFileKind or "") == "dsp" and parseDspGraphFromCode(text) or { nodes = {}, edges = {} }
      ctx._workspaceStatus = "Reloaded " .. tostring(ctx._selectedFileName or pathStem(ed.path))
    end,
    close = function(_shellRef)
      ctx._workspaceTab = "graph"
      requestLayoutRefresh(ctx, "editor-close")
    end,
  }
end

local function refreshModuleFiles(ctx, module)
  local currentModuleId = tostring(module and module.id or "")
  if currentModuleId == "" then
    return
  end
  local changedModule = tostring(ctx._fileModuleId or "") ~= currentModuleId
  ctx._fileRows = buildModuleFileRows(ctx, module)
  ctx._fileModuleId = currentModuleId

  local selectedRow = nil
  local selectedPath = tostring(ctx._selectedFilePath or "")
  for i = 1, #(ctx._fileRows or {}) do
    local row = ctx._fileRows[i]
    if not row.section and not row.nonInteractive then
      local isSelected = row.path == selectedPath
      row.selected = isSelected
      row.active = isSelected
      if isSelected then
        selectedRow = row
      end
    end
  end

  if changedModule or not selectedRow then
    selectedRow = chooseDefaultModuleFileRow(ctx._fileRows or {})
    if selectedRow then
      loadSelectedFileIntoEditor(ctx, selectedRow)
      for i = 1, #(ctx._fileRows or {}) do
        local row = ctx._fileRows[i]
        if not row.section and not row.nonInteractive then
          local isSelected = row.path == selectedRow.path
          row.selected = isSelected
          row.active = isSelected
        end
      end
    end
  end
end

local function buildGraphDisplayList(ctx, w, h)
  local graph = ctx._graphModel or { nodes = {}, edges = {} }
  local nodes = graph.nodes or {}
  local edges = graph.edges or {}
  local display = {
    { cmd = "fillRoundedRect", x = 0, y = 0, w = w, h = h, radius = 6, color = 0xff0b1220 },
    { cmd = "drawRoundedRect", x = 0, y = 0, w = w, h = h, radius = 6, thickness = 1, color = 0xff334155 },
    { cmd = "drawText", x = 10, y = 8, w = math.max(0, w - 20), h = 16, color = 0xff94a3b8, text = string.format("parsed nodes=%d edges=%d", #nodes, #edges), fontSize = 10.0, align = "left", valign = "middle" },
  }
  if #nodes == 0 then
    display[#display + 1] = { cmd = "drawText", x = 10, y = 34, w = math.max(0, w - 20), h = 18, color = 0xff64748b, text = "No DSP graph available for the selected file", fontSize = 11.0, align = "left", valign = "middle" }
    return display
  end

  local left = 14
  local top = 34
  local graphW = math.max(1, w - 28)
  local graphH = math.max(1, h - 48)
  local count = #nodes
  local nodeW = math.min(160, math.max(110, math.floor(graphW / math.max(1, count)) - 16))
  local nodeH = 44
  local positions = {}

  local depth = {}
  local inDegree = {}
  for i = 1, count do
    depth[i] = 0
    inDegree[i] = 0
  end
  for _, edge in ipairs(edges) do
    inDegree[edge.to] = (inDegree[edge.to] or 0) + 1
  end
  local queue = {}
  for i = 1, count do
    if inDegree[i] == 0 then
      queue[#queue + 1] = i
    end
  end
  while #queue > 0 do
    local u = table.remove(queue, 1)
    for _, edge in ipairs(edges) do
      if edge.from == u then
        local v = edge.to
        depth[v] = math.max(depth[v] or 0, (depth[u] or 0) + 1)
        inDegree[v] = (inDegree[v] or 0) - 1
        if inDegree[v] == 0 then
          queue[#queue + 1] = v
        end
      end
    end
  end

  local levels = {}
  local maxDepth = 0
  for i = 1, count do
    local d = depth[i] or 0
    maxDepth = math.max(maxDepth, d)
    levels[d] = levels[d] or {}
    levels[d][#levels[d] + 1] = i
  end

  local levelW = math.max(nodeW + 32, math.floor(graphW / math.max(1, maxDepth + 1)))
  for d = 0, maxDepth do
    local levelNodes = levels[d] or {}
    local totalH = #levelNodes * nodeH + math.max(0, #levelNodes - 1) * 14
    local startY = top + math.max(0, math.floor((graphH - totalH) * 0.5))
    for i = 1, #levelNodes do
      local nodeIndex = levelNodes[i]
      local x = left + d * levelW + math.max(0, math.floor((levelW - nodeW) * 0.5))
      local y = startY + (i - 1) * (nodeH + 14)
      positions[nodeIndex] = { x = x, y = y, w = nodeW, h = nodeH }
    end
  end

  for _, edge in ipairs(edges) do
    local a = positions[edge.from]
    local b = positions[edge.to]
    if a and b then
      local x1 = a.x + a.w
      local y1 = a.y + math.floor(a.h * 0.5)
      local x2 = b.x
      local y2 = b.y + math.floor(b.h * 0.5)
      local elbow = x1 + math.max(18, math.floor((x2 - x1) * 0.45))
      display[#display + 1] = { cmd = "drawLine", x1 = x1, y1 = y1, x2 = elbow, y2 = y1, color = 0xff94a3b8, thickness = 2 }
      display[#display + 1] = { cmd = "drawLine", x1 = elbow, y1 = y1, x2 = elbow, y2 = y2, color = 0xff94a3b8, thickness = 2 }
      display[#display + 1] = { cmd = "drawLine", x1 = elbow, y1 = y2, x2 = x2, y2 = y2, color = 0xff94a3b8, thickness = 2 }
    end
  end

  for i = 1, #nodes do
    local node = nodes[i]
    local p = positions[i]
    if p then
      display[#display + 1] = { cmd = "fillRoundedRect", x = p.x, y = p.y, w = p.w, h = p.h, radius = 6, color = 0xff172030 }
      display[#display + 1] = { cmd = "drawRoundedRect", x = p.x, y = p.y, w = p.w, h = p.h, radius = 6, thickness = 1, color = 0xff38bdf8 }
      display[#display + 1] = { cmd = "drawText", x = p.x + 10, y = p.y + 2, w = p.w - 20, h = p.h - 4, color = 0xffe2e8f0, text = tostring(node.var or "") .. " : " .. tostring(node.prim or ""), fontSize = 10.0, align = "left", valign = "middle" }
    end
  end
  return display
end

local function syncWorkspaceGraph(ctx)
  local widgets = ctx.widgets or {}
  local graphCanvas = widgets.workspace_graph_canvas
  if not (graphCanvas and graphCanvas.node and graphCanvas.node.setDisplayList) then
    return
  end
  local w = math.max(1, round(graphCanvas.node:getWidth()))
  local h = math.max(1, round(graphCanvas.node:getHeight()))
  graphCanvas.node:setClipRect(0, 0, w, h)
  graphCanvas.node:setDisplayList(buildGraphDisplayList(ctx, w, h))
  if graphCanvas.node.repaint then
    graphCanvas.node:repaint()
  end
end

local function syncWorkspaceSurfaces(ctx, workspaceVisible)
  if type(shell) ~= "table" or type(shell.defineSurface) ~= "function" then
    return
  end

  shell.scriptRows = ctx._fileRows or {}
  shell.scriptListActions = {
    select = function(_shellRef, row, _index)
      if type(row) ~= "table" or tostring(row.path or "") == "" then
        return
      end
      loadSelectedFileIntoEditor(ctx, row)
      refreshModuleFiles(ctx, moduleByIndex(ctx.state.moduleIndex or 1))
      syncWorkspaceGraph(ctx)
      requestLayoutRefresh(ctx, "file-select")
    end,
    open = function(_shellRef, row, _index)
      if type(row) ~= "table" or tostring(row.path or "") == "" then
        return
      end
      loadSelectedFileIntoEditor(ctx, row)
      ctx._workspaceTab = "editor"
      refreshModuleFiles(ctx, moduleByIndex(ctx.state.moduleIndex or 1))
      syncWorkspaceGraph(ctx)
      requestLayoutRefresh(ctx, "file-open")
    end,
  }

  local fileTreeBounds = getWidgetBoundsInRoot(ctx, ctx.widgets and ctx.widgets.sidebar_files_tree_panel or nil) or { x = 0, y = 0, w = 0, h = 0 }
  shell:defineSurface("rackModuleFileTree", {
    id = "rackModuleFileTree",
    kind = "tool",
    backend = "imgui",
    visible = workspaceVisible and ctx._sidebarTab == "files" and fileTreeBounds.w > 0 and fileTreeBounds.h > 0,
    bounds = fileTreeBounds,
    z = 60,
    mode = "global",
    docking = "fill",
    interactive = true,
    modal = false,
    payloadKey = "scriptRows",
    title = "Plugin Files",
  })

  local editorState = ensureProjectEditorState(ctx)
  local editorBounds = getWidgetBoundsInRoot(ctx, ctx.widgets and ctx.widgets.workspace_editor_host_frame or nil) or { x = 0, y = 0, w = 0, h = 0 }
  if editorState then
    editorState.bodyRect = editorBounds
    editorState.path = ctx._selectedFilePath or ""
    editorState.name = ctx._selectedFileName or ""
    editorState.text = ctx._selectedFileText or ""
    editorState.status = ctx._workspaceStatus or ""
  end
  shell:defineSurface("projectScriptEditor", {
    id = "projectScriptEditor",
    kind = "tool",
    backend = "imgui",
    visible = workspaceVisible and ctx._workspaceTab == "editor" and tostring(ctx._selectedFilePath or "") ~= "" and editorBounds.w > 0 and editorBounds.h > 0,
    bounds = editorBounds,
    z = 61,
    mode = "global",
    docking = "fill",
    interactive = true,
    modal = false,
    payloadKey = "projectScriptEditor",
    title = "Plugin Script",
  })
end

local function syncExternalFileChanges(ctx, now)
  if tostring(ctx._selectedFilePath or "") == "" then
    return
  end
  if now ~= 0 and (now - (ctx._lastFilePollAt or 0)) < FILE_POLL_INTERVAL then
    return
  end
  ctx._lastFilePollAt = now
  local diskText = readText(ctx._selectedFilePath)
  if diskText == tostring(ctx._selectedDiskText or "") then
    return
  end
  local editorState = ensureProjectEditorState(ctx)
  if editorState and editorState.dirty == true then
    ctx._selectedDiskText = diskText
    ctx._selectedFileExternalDirty = true
    ctx._workspaceStatus = "External changes detected on disk"
    return
  end
  ctx._selectedDiskText = diskText
  ctx._selectedFileText = diskText
  ctx._selectedFileExternalDirty = false
  ctx._graphModel = tostring(ctx._selectedFileKind or "") == "dsp" and parseDspGraphFromCode(diskText) or { nodes = {}, edges = {} }
  if editorState then
    editorState.text = diskText
    editorState.dirty = false
    editorState.syncToken = (tonumber(editorState.syncToken) or 0) + 1
  end
  ctx._workspaceStatus = "Reloaded external changes"
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

  refreshModuleFiles(ctx, module)

  local sidebarFiles = ctx._sidebarTab == "files"
  for i = 1, #SIDEBAR_PARAM_WIDGET_IDS do
    local id = SIDEBAR_PARAM_WIDGET_IDS[i]
    if id == "input_b_group" then
      setVisible(widgets[id], (not sidebarFiles) and module.id == "blend_simple")
    else
      setVisible(widgets[id], not sidebarFiles)
    end
  end
  setVisible(widgets.sidebar_files_panel, sidebarFiles)
  setText(widgets.sidebar_params_tab, ctx._sidebarTab == "params" and "[Params]" or "Params")
  setText(widgets.sidebar_files_tab, ctx._sidebarTab == "files" and "[Files]" or "Files")
  setText(widgets.workspace_editor_tab, ctx._workspaceTab == "editor" and "[Editor]" or "Editor")
  setText(widgets.workspace_graph_tab, ctx._workspaceTab == "graph" and "[DSP Graph]" or "DSP Graph")
  setVisible(widgets.workspace_editor_host_frame, ctx._workspaceTab == "editor")
  setVisible(widgets.workspace_graph_canvas, ctx._workspaceTab == "graph")
  local graphAvailable = tostring(ctx._selectedFileKind or "") == "dsp"
  setVisible(widgets.workspace_graph_empty, ctx._workspaceTab == "graph" and not graphAvailable)
  setText(widgets.workspace_path, tostring(ctx._selectedFilePath or ""))
  local externalSuffix = ctx._selectedFileExternalDirty and " | disk changed" or ""
  setText(widgets.workspace_status, tostring(ctx._workspaceStatus or "No file selected") .. externalSuffix)

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
  local maxDisplayH = math.max(1, surfaceH - (LAYOUT_PADDING * 2) - (isPatch and 0 or (WORKSPACE_MIN_H + WORKSPACE_GAP)))
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
  local workspaceVisible = (not isPatch) and remaining >= WORKSPACE_MIN_H
  local workspaceX = LAYOUT_PADDING
  local workspaceY = workspaceVisible and (displayY + displayH + WORKSPACE_GAP) or (surfaceH - 1)
  local workspaceW = maxDisplayW
  local workspaceH = workspaceVisible and math.max(1, remaining - WORKSPACE_GAP) or 1
  local workspaceWidget = widgets.script_workspace
  setBounds(workspaceWidget, workspaceX, workspaceY, workspaceW, workspaceH)
  setVisible(workspaceWidget, workspaceVisible)

  local toolbarY = 8
  local innerX = 14
  local innerW = math.max(1, workspaceW - 28)
  local contentY = 58
  local contentH = math.max(1, workspaceH - 68)

  setBounds(widgets.workspace_title, innerX, toolbarY + 2, 180, 18)
  setBounds(widgets.workspace_status, innerX + 180, toolbarY + 2, math.max(120, innerW - 470), 18)
  local rightX = workspaceW - 14
  setBounds(widgets.workspace_reload_button, rightX - 60, toolbarY, 60, 22)
  setBounds(widgets.workspace_save_button, rightX - 60 - 48, toolbarY, 44, 22)
  setBounds(widgets.workspace_graph_tab, rightX - 60 - 48 - 86, toolbarY, 82, 22)
  setBounds(widgets.workspace_editor_tab, rightX - 60 - 48 - 86 - 78, toolbarY, 74, 22)
  setBounds(widgets.workspace_path, innerX, 32, innerW, 18)
  setBounds(widgets.workspace_editor_host_frame, innerX, contentY, innerW, contentH)
  setBounds(widgets.workspace_graph_canvas, innerX, contentY, innerW, contentH)
  setBounds(widgets.workspace_graph_empty, innerX + 18, contentY + math.max(20, math.floor(contentH * 0.30)), math.max(120, innerW - 36), 22)

  syncWorkspaceGraph(ctx)
  syncWorkspaceSurfaces(ctx, workspaceVisible)

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
    adaptiveBounds = { x = workspaceX, y = workspaceY, w = workspaceW, h = workspaceH, visible = workspaceVisible },
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

  if widgets.sidebar_params_tab then
    widgets.sidebar_params_tab._onClick = function()
      ctx._sidebarTab = "params"
      requestLayoutRefresh(ctx, "sidebar-params-tab")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.sidebar_files_tab then
    widgets.sidebar_files_tab._onClick = function()
      ctx._sidebarTab = "files"
      requestLayoutRefresh(ctx, "sidebar-files-tab")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.workspace_editor_tab then
    widgets.workspace_editor_tab._onClick = function()
      ctx._workspaceTab = "editor"
      requestLayoutRefresh(ctx, "workspace-editor-tab")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.workspace_graph_tab then
    widgets.workspace_graph_tab._onClick = function()
      ctx._workspaceTab = "graph"
      requestLayoutRefresh(ctx, "workspace-graph-tab")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.workspace_save_button then
    widgets.workspace_save_button._onClick = function()
      if type(shell) == "table" and type(shell.mainScriptEditorActions) == "table" and type(shell.mainScriptEditorActions.save) == "function" then
        shell.mainScriptEditorActions.save(shell)
      end
      requestLayoutRefresh(ctx, "workspace-save")
      maybeApplyPendingLayout(ctx)
    end
  end
  if widgets.workspace_reload_button then
    widgets.workspace_reload_button._onClick = function()
      if type(shell) == "table" and type(shell.mainScriptEditorActions) == "table" and type(shell.mainScriptEditorActions.reload) == "function" then
        shell.mainScriptEditorActions.reload(shell)
      end
      requestLayoutRefresh(ctx, "workspace-reload")
      maybeApplyPendingLayout(ctx)
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
  ctx._sidebarTab = "params"
  ctx._workspaceTab = "editor"
  ctx._fileRows = {}
  ctx._fileModuleId = ""
  ctx._selectedFileRow = nil
  ctx._selectedFilePath = ""
  ctx._selectedFileKind = ""
  ctx._selectedFileName = ""
  ctx._selectedFileText = ""
  ctx._selectedDiskText = ""
  ctx._selectedFileExternalDirty = false
  ctx._workspaceStatus = "No file selected"
  ctx._graphModel = { nodes = {}, edges = {} }
  for i = 1, #MODULES do
    ctx.state.sizeByModuleId[MODULES[i].id] = MODULES[i].defaultSize
    ctx._rackModuleSpecs[MODULES[i].id] = MODULES[i].spec
  end
  installGlobals(ctx)
  installEditorActionHandlers(ctx)
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
  syncEditorTextFromHost(ctx)
  syncExternalFileChanges(ctx, now)
  maybeApplyPendingLayout(ctx)

  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncFromParams(ctx)
  end
end

return M

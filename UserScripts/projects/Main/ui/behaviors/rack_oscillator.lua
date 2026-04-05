local Preview = require("ui.oscillator_preview")
local ModWidgetSync = require("ui.modulation_widget_sync")

local RackOscillatorBehavior = {}

local VOICE_COUNT = 8
local SYNC_INTERVAL = 0.08
local LEGACY_OSC_MAX_LEVEL = 0.40

local GLOBAL_PATHS = {
  waveform = "/midi/synth/waveform",
  renderMode = "/midi/synth/osc/renderMode",
  additivePartials = "/midi/synth/osc/add/partials",
  additiveTilt = "/midi/synth/osc/add/tilt",
  additiveDrift = "/midi/synth/osc/add/drift",
  drive = "/midi/synth/drive",
  driveShape = "/midi/synth/driveShape",
  driveBias = "/midi/synth/driveBias",
  pulseWidth = "/midi/synth/pulseWidth",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  manualPitch = "/midi/synth/rack/osc/manualPitch",
  manualLevel = "/midi/synth/rack/osc/manualLevel",
  output = "/midi/synth/rack/osc/output",
}

local ANALYSIS_FUNDAMENTAL = 220.0

local function buildWavePreviewPartials(ctx, fundamental)
  local waveform = tonumber(ctx.waveformType) or 1
  local partialCount = math.max(1, math.min(32, tonumber(ctx.additivePartials) or 8))
  local tilt = tonumber(ctx.additiveTilt) or 0.0
  local drift = tonumber(ctx.additiveDrift) or 0.0
  local fund = math.max(1.0, fundamental or ANALYSIS_FUNDAMENTAL)
  local out = { activeCount = 0, fundamental = fund, partials = {} }

  local function tiltScale(h)
    return math.max(0.12, h ^ (tilt * 0.85))
  end

  local function driftOffset(h)
    if drift <= 0.0 then
      return 1.0, 0.0
    end
    return 1.0 + math.sin(h * 2.173 + waveform * 0.53) * drift * 0.035 * (1.0 + h * 0.05),
      math.sin(h * 1.618 + waveform * 0.37) * drift * 0.85
  end

  local function addPartial(harmonic, amplitude, phase)
    if out.activeCount >= 32 then
      return
    end
    local freqJitter, phaseJitter = driftOffset(harmonic)
    out.activeCount = out.activeCount + 1
    out.partials[out.activeCount] = {
      frequency = fund * harmonic * freqJitter,
      amplitude = tiltScale(harmonic) * amplitude,
      phase = (phase or 0.0) + phaseJitter,
      decayRate = 0.0,
    }
  end

  if waveform == 0 then
    addPartial(1, 1.0, 0.0)
  elseif waveform == 1 then
    for h = 1, partialCount do
      addPartial(h, 1.0 / h, (h % 2 == 0) and math.pi or 0.0)
    end
  elseif waveform == 2 then
    for i = 1, partialCount do
      local h = i * 2 - 1
      addPartial(h, 1.0 / h, 0.0)
    end
  elseif waveform == 3 then
    for i = 1, partialCount do
      local h = i * 2 - 1
      addPartial(h, 1.0 / (h * h), (((i - 1) % 2) == 0) and (-math.pi * 0.5) or (math.pi * 0.5))
    end
  elseif waveform == 4 then
    addPartial(1, 0.45, 0.0)
    for h = 2, partialCount + 1 do
      addPartial(h, 0.55 / h, (h % 2 == 0) and math.pi or 0.0)
    end
  elseif waveform == 5 then
    local noiseCluster = {
      { 1.0, 0.32, 0.0 },
      { 1.73, 0.22, 1.2 },
      { 2.41, 0.16, 2.1 },
      { 3.07, 0.12, 0.8 },
      { 4.62, 0.09, 2.8 },
      { 6.11, 0.05, 1.7 },
    }
    for i = 1, math.min(#noiseCluster, partialCount) do
      local item = noiseCluster[i]
      out.activeCount = out.activeCount + 1
      out.partials[out.activeCount] = {
        frequency = fund * item[1],
        amplitude = tiltScale(i) * item[2],
        phase = item[3],
        decayRate = 0.0,
      }
    end
  elseif waveform == 6 then
    local pw = math.max(0.01, math.min(0.99, tonumber(ctx.pulseWidth) or 0.5))
    for h = 1, partialCount do
      local coeff = math.sin(math.pi * h * pw)
      addPartial(h, math.abs(coeff) / h, coeff < 0 and math.pi or 0.0)
    end
  elseif waveform == 7 then
    for h = 1, partialCount do
      addPartial(h, 0.84 / h, (h % 2 == 0) and math.pi or 0.0)
    end
  else
    addPartial(1, 1.0, 0.0)
  end

  local sum = 0.0
  for i = 1, out.activeCount do
    sum = sum + (out.partials[i].amplitude or 0.0)
  end
  if sum > 1.0e-6 then
    for i = 1, out.activeCount do
      out.partials[i].amplitude = out.partials[i].amplitude / sum
    end
  end
  return out
end

local function dynamicVoiceGatePath(slotIndex, voiceIndex)
  return string.format("/midi/synth/rack/osc/%d/voice/%d/gate", slotIndex, voiceIndex)
end

local function dynamicVoiceVOctPath(slotIndex, voiceIndex)
  return string.format("/midi/synth/rack/osc/%d/voice/%d/vOct", slotIndex, voiceIndex)
end

local function noteToFrequency(note)
  return 440.0 * (2.0 ^ (((tonumber(note) or 69.0) - 69.0) / 12.0))
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
  if type(_G.setParam) == "function" then
    return _G.setParam(path, tonumber(value) or 0)
  end
  if type(command) == "function" then
    command("SET", path, tostring(value))
    return true
  end
  return false
end

local function setBounds(widget, x, y, w, h)
  x = math.floor(x)
  y = math.floor(y)
  w = math.max(1, math.floor(w))
  h = math.max(1, math.floor(h))
  if widget and widget.setBounds then
    widget:setBounds(x, y, w, h)
  elseif widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(x, y, w, h)
  end
end

local function setWidgetVisible(widget, visible)
  if widget and widget.setVisible then
    widget:setVisible(visible == true)
  elseif widget and widget.node and widget.node.setVisible then
    widget.node:setVisible(visible == true)
  end
end

local function anchorDropdown(dropdown, root)
  if not dropdown or not dropdown.setAbsolutePos or not dropdown.node or not root or not root.node then return end
  local ax, ay = 0, 0
  local node = dropdown.node
  local depth = 0
  while node and depth < 20 do
    local bx, by = node:getBounds()
    ax = ax + (bx or 0)
    ay = ay + (by or 0)
    local ok, parent = pcall(function() return node:getParent() end)
    if ok and parent and parent ~= node then
      node = parent
    else
      break
    end
    depth = depth + 1
  end
  dropdown:setAbsolutePos(ax, ay)
end

local function isUsableInstanceNodeId(nodeId)
  local id = tostring(nodeId or "")
  if id == "" then
    return false
  end
  if id:match("Component$") or id:match("Content$") or id:match("Shell$") then
    return false
  end
  return true
end

local function nodeIdFromGlobalId(globalId)
  local gid = tostring(globalId or "")
  local shellId = gid:match("%.([^.]+Shell)%.[^.]+$")
  if shellId == nil then
    shellId = gid:match("([^.]+Shell)%.[^.]+$")
  end
  if type(shellId) == "string" and shellId ~= "" then
    local nodeId = shellId:gsub("Shell$", "")
    if isUsableInstanceNodeId(nodeId) then
      return nodeId
    end
  end
  return nil
end

local function getInstanceNodeId(ctx)
  if type(ctx) ~= "table" then
    return nil
  end
  local propsNodeId = ctx.instanceProps and ctx.instanceProps.instanceNodeId or nil
  if isUsableInstanceNodeId(propsNodeId) then
    ctx._instanceNodeId = propsNodeId
    return propsNodeId
  end
  if isUsableInstanceNodeId(ctx._instanceNodeId) then
    return ctx._instanceNodeId
  end

  local record = ctx.root and ctx.root._structuredRecord or nil
  local globalId = type(record) == "table" and tostring(record.globalId or "") or ""
  local nodeId = nodeIdFromGlobalId(globalId)
  if nodeId ~= nil then
    ctx._instanceNodeId = nodeId
    return nodeId
  end

  local root = ctx.root
  local node = root and root.node or nil
  local source = node and node.getUserData and node:getUserData("_structuredInstanceSource") or nil
  local sourceNodeId = type(source) == "table" and type(source.nodeId) == "string" and source.nodeId or nil
  if isUsableInstanceNodeId(sourceNodeId) then
    ctx._instanceNodeId = sourceNodeId
    return sourceNodeId
  end

  local sourceGlobalId = type(source) == "table" and tostring(source.globalId or "") or ""
  nodeId = nodeIdFromGlobalId(sourceGlobalId)
  if nodeId ~= nil then
    ctx._instanceNodeId = nodeId
    return nodeId
  end

  return nil
end

local function getParamBase(ctx)
  local instanceProps = type(ctx) == "table" and ctx.instanceProps or nil
  local propsParamBase = type(instanceProps) == "table" and type(instanceProps.paramBase) == "string" and instanceProps.paramBase or nil
  if type(propsParamBase) == "string" and propsParamBase ~= "" then
    return propsParamBase
  end
  local nodeId = getInstanceNodeId(ctx)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  local paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase
  end
  return nil
end

local function getSlotIndex(ctx)
  local paramBase = getParamBase(ctx)
  local slotIndex = type(paramBase) == "string" and paramBase:match("^/midi/synth/rack/osc/(%d+)$") or nil
  if slotIndex ~= nil then
    return math.max(1, math.floor(tonumber(slotIndex) or 1))
  end
  local nodeId = getInstanceNodeId(ctx)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  return math.max(1, math.floor(tonumber(type(entry) == "table" and entry.slotIndex or 1) or 1))
end

local function updateAnalysisExport(ctx)
  local slotIndex = getSlotIndex(ctx)
  if slotIndex == nil or type(_G) ~= "table" then
    return
  end
  local storage = _G.__midiSynthDynamicOscillatorAnalysis or {}
  local activeFreq = nil
  local activeAmp = 0.0
  for i = 1, #(ctx.activeVoices or {}) do
    local voice = ctx.activeVoices[i]
    local amp = tonumber(voice and voice.amp) or 0.0
    if amp > activeAmp then
      activeAmp = amp
      activeFreq = tonumber(voice.freq) or activeFreq
    end
  end
  if activeFreq == nil then
    activeFreq = noteToFrequency(tonumber(ctx.manualPitch) or 60.0)
  end
  storage[slotIndex] = buildWavePreviewPartials(ctx, activeFreq or ANALYSIS_FUNDAMENTAL)
  _G.__midiSynthDynamicOscillatorAnalysis = storage
end

local function pathFor(ctx, key)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    local suffix = {
      waveform = "/waveform",
      renderMode = "/renderMode",
      additivePartials = "/additivePartials",
      additiveTilt = "/additiveTilt",
      additiveDrift = "/additiveDrift",
      drive = "/drive",
      driveShape = "/driveShape",
      driveBias = "/driveBias",
      pulseWidth = "/pulseWidth",
      unison = "/unison",
      detune = "/detune",
      spread = "/spread",
      manualPitch = "/manualPitch",
      manualLevel = "/manualLevel",
      output = "/output",
    }
    if suffix[key] then
      return paramBase .. suffix[key]
    end
  end
  return GLOBAL_PATHS[key]
end

local function refreshGraph(ctx)
  local widgets = ctx.widgets or {}
  local graph = widgets.osc_graph
  if graph and graph.node then
    local w = graph.node:getWidth()
    local h = graph.node:getHeight()
    if w > 0 and h > 0 then
      graph.node:setDisplayList(Preview.buildWaveDisplay(ctx, w, h))
      graph.node:repaint()
    end
  end
  Preview.refreshDriveCurve(widgets.drive_curve, ctx)
end

local function syncFromParams(ctx)
  local changed = false
  local widgets = ctx.widgets or {}

  local nextWaveform = round(readParam(pathFor(ctx, "waveform"), ctx.waveformType or 1))
  if ctx.waveformType ~= nextWaveform then
    ctx.waveformType = nextWaveform
    changed = true
    local dropdown = widgets.waveform_dropdown
    if dropdown and dropdown.setSelected and not dropdown._open then
      dropdown:setSelected(nextWaveform + 1)
    end
  end

  local nextRenderMode = round(readParam(pathFor(ctx, "renderMode"), ctx.renderMode or 0))
  if ctx.renderMode ~= nextRenderMode then
    ctx.renderMode = nextRenderMode
    changed = true
    local tabs = widgets.render_mode_tabs
    if tabs and tabs.setSelected then
      tabs:setSelected(nextRenderMode + 1)
    end
  end

  local numericFields = {
    { key = "pulseWidth", pathKey = "pulseWidth", min = 0.01, max = 0.99, widget = "pulse_width_knob", eps = 0.0001 },
    { key = "additivePartials", pathKey = "additivePartials", min = 1, max = 32, widget = "add_partials_knob", round = true, eps = 0.0001 },
    { key = "additiveTilt", pathKey = "additiveTilt", min = -1, max = 1, widget = "add_tilt_knob", eps = 0.0001 },
    { key = "additiveDrift", pathKey = "additiveDrift", min = 0, max = 1, widget = "add_drift_knob", eps = 0.0001 },
    { key = "driveAmount", pathKey = "drive", min = 0, max = 20, widget = "drive_knob", eps = 0.0001 },
    { key = "driveBias", pathKey = "driveBias", min = -1, max = 1, widget = "drive_bias_knob", eps = 0.0001 },
    { key = "unison", pathKey = "unison", min = 1, max = 8, widget = "unison_knob", round = true, eps = 0.0001 },
    { key = "detune", pathKey = "detune", min = 0, max = 100, widget = "detune_knob", eps = 0.0001 },
    { key = "spread", pathKey = "spread", min = 0, max = 1, widget = "spread_knob", eps = 0.0001 },
    { key = "manualPitch", pathKey = "manualPitch", min = 0, max = 127, widget = "manual_pitch_knob", round = true, eps = 0.0001 },
    { key = "manualLevel", pathKey = "manualLevel", min = 0, max = 1, widget = "manual_level_knob", eps = 0.0001 },
    { key = "outputLevel", pathKey = "output", min = 0, max = 1, widget = "output_knob", eps = 0.0001 },
  }

  for i = 1, #numericFields do
    local spec = numericFields[i]
    local baseValue, effectiveValue, modState = ModWidgetSync.resolveValues(pathFor(ctx, spec.pathKey), ctx[spec.key] or 0, readParam)
    local nextValue = clamp(baseValue, spec.min, spec.max)
    local nextEffectiveValue = clamp(effectiveValue, spec.min, spec.max)
    if spec.round then
      nextValue = round(nextValue)
      nextEffectiveValue = round(nextEffectiveValue)
    end
    if math.abs((tonumber(ctx[spec.key]) or 0) - nextValue) > (spec.eps or 0.0001) then
      ctx[spec.key] = nextValue
      changed = true
    end
    ModWidgetSync.syncWidget(widgets[spec.widget], nextValue, nextEffectiveValue, modState, nil, spec.eps)
  end

  local nextDriveShape = round(readParam(pathFor(ctx, "driveShape"), ctx.driveShape or 0))
  if ctx.driveShape ~= nextDriveShape then
    ctx.driveShape = nextDriveShape
    changed = true
    local dropdown = widgets.drive_mode_dropdown
    if dropdown and dropdown.setSelected and not dropdown._open then
      dropdown:setSelected(nextDriveShape + 1)
    end
  end

  return changed
end

local function isAudioConnected(ctx)
  local nodeId = getInstanceNodeId(ctx)
  if type(nodeId) ~= "string" or nodeId == "" then
    return false
  end
  local connections = type(_G) == "table" and _G.__midiSynthRackConnections or nil
  if type(connections) ~= "table" then
    return false
  end
  for i = 1, #connections do
    local conn = connections[i]
    if tostring(conn and conn.kind or "") == "audio" then
      local from = type(conn.from) == "table" and conn.from or nil
      if from and tostring(from.moduleId or "") == nodeId then
        return true
      end
    end
  end
  return false
end

local function syncVoiceOverlay(ctx, dt)
  local activeVoices = ctx.activeVoices or {}
  local activeCount = 0
  local connected = isAudioConnected(ctx)
  local slotIndex = getSlotIndex(ctx)
  ctx.audioConnected = connected

  if slotIndex ~= nil then
    for i = 1, VOICE_COUNT do
      local level = tonumber(readParam(dynamicVoiceGatePath(slotIndex, i), 0.0)) or 0.0
      if level > 0.001 then
        activeCount = activeCount + 1
        local item = activeVoices[activeCount] or {}
        local note = tonumber(readParam(dynamicVoiceVOctPath(slotIndex, i), 60.0)) or 60.0
        item.voiceIndex = i
        item.freq = noteToFrequency(note)
        item.amp = math.min(level, LEGACY_OSC_MAX_LEVEL)
        activeVoices[activeCount] = item
      end
    end
    if activeCount == 0 then
      local manualLevel = tonumber(readParam(pathFor(ctx, "manualLevel"), ctx.manualLevel or 0.0)) or 0.0
      if manualLevel > 0.001 then
        activeCount = 1
        local item = activeVoices[1] or {}
        local note = tonumber(readParam(pathFor(ctx, "manualPitch"), ctx.manualPitch or 60.0)) or 60.0
        item.voiceIndex = 0
        item.freq = noteToFrequency(note)
        item.amp = manualLevel * LEGACY_OSC_MAX_LEVEL
        activeVoices[1] = item
      end
    end
  end

  for i = activeCount + 1, #activeVoices do
    activeVoices[i] = nil
  end
  ctx.activeVoices = activeVoices
  ctx.animTime = (ctx.animTime or 0) + (tonumber(dt) or 0)
  if activeCount >= 3 then
    ctx.maxPoints = 96
  elseif activeCount >= 2 then
    ctx.maxPoints = 120
  else
    ctx.maxPoints = 180
  end
end

local function bindControls(ctx)
  local widgets = ctx.widgets or {}

  if widgets.waveform_dropdown then
    widgets.waveform_dropdown._onSelect = function(idx)
      local value = math.max(0, math.min(7, round((tonumber(idx) or 1) - 1)))
      ctx.waveformType = value
      writeParam(pathFor(ctx, "waveform"), value)
      RackOscillatorBehavior.updateKnobLayout(ctx)
      refreshGraph(ctx)
    end
  end

  if widgets.render_mode_tabs then
    widgets.render_mode_tabs._onSelect = function(idx)
      local value = math.max(0, math.min(1, round((tonumber(idx) or 1) - 1)))
      ctx.renderMode = value
      writeParam(pathFor(ctx, "renderMode"), value)
      RackOscillatorBehavior.updateKnobLayout(ctx)
      refreshGraph(ctx)
    end
  end

  if widgets.drive_mode_dropdown then
    widgets.drive_mode_dropdown._onSelect = function(idx)
      local value = math.max(0, math.min(3, round((tonumber(idx) or 1) - 1)))
      ctx.driveShape = value
      writeParam(pathFor(ctx, "driveShape"), value)
      refreshGraph(ctx)
    end
  end

  local sliderBindings = {
    { widget = "pulse_width_knob", key = "pulseWidth", pathKey = "pulseWidth", min = 0.01, max = 0.99 },
    { widget = "add_partials_knob", key = "additivePartials", pathKey = "additivePartials", min = 1, max = 32, round = true },
    { widget = "add_tilt_knob", key = "additiveTilt", pathKey = "additiveTilt", min = -1, max = 1 },
    { widget = "add_drift_knob", key = "additiveDrift", pathKey = "additiveDrift", min = 0, max = 1 },
    { widget = "drive_knob", key = "driveAmount", pathKey = "drive", min = 0, max = 20 },
    { widget = "drive_bias_knob", key = "driveBias", pathKey = "driveBias", min = -1, max = 1 },
    { widget = "unison_knob", key = "unison", pathKey = "unison", min = 1, max = 8, round = true },
    { widget = "detune_knob", key = "detune", pathKey = "detune", min = 0, max = 100 },
    { widget = "spread_knob", key = "spread", pathKey = "spread", min = 0, max = 1 },
    { widget = "manual_pitch_knob", key = "manualPitch", pathKey = "manualPitch", min = 0, max = 127, round = true },
    { widget = "manual_level_knob", key = "manualLevel", pathKey = "manualLevel", min = 0, max = 1 },
    { widget = "output_knob", key = "outputLevel", pathKey = "output", min = 0, max = 1 },
  }

  for i = 1, #sliderBindings do
    local spec = sliderBindings[i]
    local widget = widgets[spec.widget]
    if widget then
      widget._onChange = function(v)
        local value = clamp(v, spec.min, spec.max)
        if spec.round then
          value = round(value)
        end
        ctx[spec.key] = value
        writeParam(pathFor(ctx, spec.pathKey), value)
        refreshGraph(ctx)
      end
    end
  end
end

function RackOscillatorBehavior.init(ctx)
  ctx.waveformType = 1
  ctx.renderMode = 0
  ctx.pulseWidth = 0.5
  ctx.unison = 1
  ctx.detune = 0.0
  ctx.spread = 0.0
  ctx.additivePartials = 8
  ctx.additiveTilt = 0.0
  ctx.additiveDrift = 0.0
  ctx.driveAmount = 0.0
  ctx.driveShape = 0
  ctx.driveBias = 0.0
  ctx.driveMix = 1.0
  ctx.manualPitch = 60
  ctx.manualLevel = 0.0
  ctx.outputLevel = 0.8
  ctx.activeVoices = {}
  ctx.animTime = 0
  ctx.maxPoints = 180
  ctx._lastDriveCurveValue = nil
  ctx._lastWaveKnobLayoutKey = nil
  ctx._lastSyncTime = 0
  ctx._lastUpdateTime = getTime and getTime() or 0

  bindControls(ctx)
  syncFromParams(ctx)
  syncVoiceOverlay(ctx, 0)
  updateAnalysisExport(ctx)
  refreshGraph(ctx)
end

function RackOscillatorBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets or {}
  local pad = 10
  local gap = 6

  local graph = widgets.osc_graph
  local tabHost = widgets.mode_tabs
  local title = widgets.title
  local pitchK = widgets.manual_pitch_knob
  local levelK = widgets.manual_level_knob
  local outputK = widgets.output_knob
  local unisonK = widgets.unison_knob
  local detuneK = widgets.detune_knob
  local spreadK = widgets.spread_knob
  local waveformDropdown = widgets.waveform_dropdown
  local driveModeDropdown = widgets.drive_mode_dropdown

  local footerGap = 6
  local footerSliderH = 22
  local footerGapInner = 8
  local controlGap = 8
  local controlSliderH = 20
  local controlRowGap = 8

  local footerSliderW = 0
  local footerY = 0

  local function placeControlRow(x, y, width)
    local rowW = math.max(96, width)
    local colW = math.max(48, math.floor((rowW - controlRowGap * 2) / 3))
    local detuneX = x + colW + controlRowGap
    local spreadX = detuneX + colW + controlRowGap
    setWidgetVisible(unisonK, true)
    setWidgetVisible(detuneK, true)
    setWidgetVisible(spreadK, true)
    setBounds(unisonK, x, y, colW, controlSliderH)
    setBounds(detuneK, detuneX, y, colW, controlSliderH)
    setBounds(spreadK, spreadX, y, colW, controlSliderH)
  end

  if w < 300 then
    local contentW = w - pad * 2
    footerSliderW = math.max(40, math.floor((contentW - footerGapInner * 2) / 3))
    footerY = h - pad - footerSliderH
    local controlY = footerY - footerGap - controlSliderH
    local graphH = math.max(48, controlY - controlGap - pad)

    setBounds(graph, pad, pad, contentW, graphH)
    setWidgetVisible(tabHost, false)
    setBounds(tabHost, 0, 0, 0, 0)
    setWidgetVisible(title, false)
    setBounds(title, 0, 0, 0, 0)
    placeControlRow(pad + 6, controlY, math.max(96, contentW - 12))
  else
    setWidgetVisible(tabHost, true)
    setWidgetVisible(title, true)

    local split = math.floor(w / 2)
    local leftW = split - pad
    local rightX = split + gap
    local rightW = w - rightX - pad

    footerSliderW = math.max(52, math.floor((leftW - footerGapInner * 2) / 3))
    footerY = h - pad - footerSliderH
    local controlY = footerY - footerGap - controlSliderH
    local graphH = math.max(60, controlY - controlGap - pad)
    local tabH = h - pad * 2

    setBounds(graph, pad, pad, leftW, graphH)
    placeControlRow(pad + 6, controlY, math.max(96, leftW - 12))
    setBounds(tabHost, rightX, pad, rightW, tabH)
  end

  local pitchX = pad
  local levelX = pitchX + footerSliderW + footerGapInner
  local outX = levelX + footerSliderW + footerGapInner
  setWidgetVisible(pitchK, true)
  setWidgetVisible(levelK, true)
  setWidgetVisible(outputK, true)
  setBounds(pitchK, pitchX, footerY, footerSliderW, footerSliderH)
  setBounds(levelK, levelX, footerY, footerSliderW, footerSliderH)
  setBounds(outputK, outX, footerY, footerSliderW, footerSliderH)

  anchorDropdown(waveformDropdown, ctx.root)
  anchorDropdown(driveModeDropdown, ctx.root)
  RackOscillatorBehavior.updateKnobLayout(ctx)
  updateAnalysisExport(ctx)
  refreshGraph(ctx)
end

function RackOscillatorBehavior.update(ctx)
  if type(ctx) ~= "table" then
    return
  end
  local now = getTime and getTime() or 0
  local lastUpdate = ctx._lastUpdateTime or now
  local dt = now - lastUpdate
  ctx._lastUpdateTime = now
  syncVoiceOverlay(ctx, dt)

  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    local changed = syncFromParams(ctx)
    if changed then
      RackOscillatorBehavior.updateKnobLayout(ctx)
    end
    updateAnalysisExport(ctx)
    refreshGraph(ctx)
  end
end

function RackOscillatorBehavior.updateKnobLayout(ctx)
  local widgets = ctx.widgets or {}
  local tabHost = widgets.mode_tabs
  local waveformDropdown = widgets.waveform_dropdown
  local renderModeTabs = widgets.render_mode_tabs
  local driveModeDropdown = widgets.drive_mode_dropdown
  local driveKnob = widgets.drive_knob
  local driveBiasKnob = widgets.drive_bias_knob
  local driveCurve = widgets.drive_curve
  local widthKnob = widgets.pulse_width_knob
  local addPartialsKnob = widgets.add_partials_knob
  local addTiltKnob = widgets.add_tilt_knob
  local addDriftKnob = widgets.add_drift_knob

  local isPulse = (ctx.waveformType == 6)
  local isAdd = (ctx.renderMode == 1)

  local widgetsNeedingRefresh = {}

  local function queueWidgetRefresh(widget, w, h)
    if not widget then return end
    widgetsNeedingRefresh[#widgetsNeedingRefresh + 1] = { widget = widget, w = w, h = h }
  end

  local function setVisible(widget, visible)
    if not widget or not widget.node then return end
    local node = widget.node
    local nextVisible = visible == true
    local changed = node.isVisible and (node:isVisible() ~= nextVisible)
    if widget.setVisible then
      widget:setVisible(nextVisible)
    elseif node.setVisible then
      node:setVisible(nextVisible)
    end
    if changed then
      queueWidgetRefresh(widget, node.getWidth and node:getWidth() or nil, node.getHeight and node:getHeight() or nil)
    end
  end

  setVisible(widthKnob, isPulse)
  setVisible(addPartialsKnob, isAdd)
  setVisible(addTiltKnob, isAdd)
  setVisible(addDriftKnob, isAdd)

  local availableW = 220
  local availableH = 156
  if tabHost and tabHost.node then
    if tabHost.node.getWidth then
      availableW = math.max(180, tabHost.node:getWidth())
    end
    if tabHost.node.getHeight then
      availableH = math.max(120, tabHost.node:getHeight() - 24)
    end
  end

  local layoutKey = string.format("%s:%s:%d:%d", tostring(isPulse), tostring(isAdd), math.floor(availableW + 0.5), math.floor(availableH + 0.5))
  if ctx._lastWaveKnobLayoutKey == layoutKey then
    return
  end
  ctx._lastWaveKnobLayoutKey = layoutKey
  ctx._lastKnobLayoutPulse = isPulse

  local function setBoundsIfDifferent(widget, x, y, w, h)
    if not widget or not widget.node or not widget.node.getBounds then return end
    local node = widget.node
    local cx, cy, cw, ch = node:getBounds()
    if cx ~= x or cy ~= y or cw ~= w or ch ~= h then
      node:setBounds(x, y, w, h)
      queueWidgetRefresh(widget, w, h)
    end
  end

  local outerPad = 10
  local colGap = 8
  local rowGap = 6
  local topY = 4
  local sliderH = 20
  local dropdownX = 4
  local renderTabsW = 84
  local renderTabsX = availableW - outerPad - renderTabsW
  local dropdownW = math.max(64, renderTabsX - dropdownX - colGap)
  local controlTopY = 30

  if waveformDropdown and waveformDropdown.node then
    setBoundsIfDifferent(waveformDropdown, dropdownX, topY, dropdownW, sliderH)
  end
  if renderModeTabs and renderModeTabs.node then
    setBoundsIfDifferent(renderModeTabs, renderTabsX, topY, renderTabsW, sliderH)
  end

  local leftAreaX = outerPad
  local fullControlW = math.max(96, availableW - outerPad * 2)
  local halfGap = 6
  local halfW = math.max(46, math.floor((fullControlW - halfGap) / 2))
  local curveY = 82

  if isAdd and not isPulse then
    local row2Y = controlTopY + sliderH + rowGap
    if addPartialsKnob and addPartialsKnob.node then
      setBoundsIfDifferent(addPartialsKnob, leftAreaX, controlTopY, fullControlW, sliderH)
    end
    if addTiltKnob and addTiltKnob.node then
      setBoundsIfDifferent(addTiltKnob, leftAreaX, row2Y, halfW, sliderH)
    end
    if addDriftKnob and addDriftKnob.node then
      setBoundsIfDifferent(addDriftKnob, leftAreaX + halfW + halfGap, row2Y, halfW, sliderH)
    end
  elseif isAdd and isPulse then
    local row1Y = controlTopY
    local row2Y = controlTopY + sliderH + rowGap
    if widthKnob and widthKnob.node then
      setBoundsIfDifferent(widthKnob, leftAreaX, row1Y, halfW, sliderH)
    end
    if addPartialsKnob and addPartialsKnob.node then
      setBoundsIfDifferent(addPartialsKnob, leftAreaX + halfW + halfGap, row1Y, halfW, sliderH)
    end
    if addTiltKnob and addTiltKnob.node then
      setBoundsIfDifferent(addTiltKnob, leftAreaX, row2Y, halfW, sliderH)
    end
    if addDriftKnob and addDriftKnob.node then
      setBoundsIfDifferent(addDriftKnob, leftAreaX + halfW + halfGap, row2Y, halfW, sliderH)
    end
  elseif isPulse and widthKnob and widthKnob.node then
    setBoundsIfDifferent(widthKnob, leftAreaX, controlTopY, fullControlW, sliderH)
  end

  local curveSize = math.max(52, math.min(56, availableH - curveY - 8))
  local curveX = leftAreaX
  local paramColW = math.max(56, math.min(62, fullControlW - curveSize - colGap))
  local rightPanelX = curveX + curveSize + colGap
  local modeY = curveY
  local driveY = modeY + sliderH + rowGap
  local biasY = driveY + sliderH + rowGap

  if driveCurve and driveCurve.node then
    setBoundsIfDifferent(driveCurve, curveX, curveY, curveSize, curveSize)
  end
  if driveModeDropdown and driveModeDropdown.node then
    setBoundsIfDifferent(driveModeDropdown, rightPanelX, modeY, paramColW, sliderH)
  end
  if driveBiasKnob and driveBiasKnob.node then
    setBoundsIfDifferent(driveBiasKnob, rightPanelX, biasY, paramColW, sliderH)
  end
  if driveKnob and driveKnob.node then
    setBoundsIfDifferent(driveKnob, rightPanelX, driveY, paramColW, sliderH)
  end

  for i = 1, #widgetsNeedingRefresh do
    local item = widgetsNeedingRefresh[i]
    local widget = item.widget
    local node = widget and widget.node or nil
    if widget and widget.refreshRetained then
      widget:refreshRetained(item.w, item.h)
    end
    if node and node.markRenderDirty then
      pcall(function() node:markRenderDirty() end)
    end
    if node and node.repaint then
      pcall(function() node:repaint() end)
    end
  end

  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.flushDeferredRefreshes) == "function" and #widgetsNeedingRefresh > 0 then
    pcall(function() shell:flushDeferredRefreshes() end)
  end
end

function RackOscillatorBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return RackOscillatorBehavior

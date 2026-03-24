local RackLayout = require("behaviors.rack_layout")
local MidiSynthRackSpecs = require("behaviors.rack_midisynth_specs")
local RackWireLayer = require("behaviors.rack_wire_layer")

local M = {}

-- Find this behavior's global ID prefix from the runtime behaviors list.
-- In the standalone MidiSynth this is always "root", but when embedded as a
-- component inside Main tabs it becomes something like
-- "root.tabs.midisynth_tab.midisynth_view".
local function resolveGlobalPrefix(ctx)
  local runtime = _G.__manifoldStructuredUiRuntime
  if runtime and runtime.behaviors then
    for _, b in ipairs(runtime.behaviors) do
      if b.ctx == ctx then
        return b.id or "root"
      end
    end
  end
  return "root"
end

local function endsWith(text, suffix)
  if type(text) ~= "string" or type(suffix) ~= "string" then
    return false
  end
  if suffix == "" then
    return true
  end
  return text:sub(-#suffix) == suffix
end

local function findScopedWidget(allWidgets, rootId, suffix)
  if type(allWidgets) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end

  local exact = nil
  if type(rootId) == "string" and rootId ~= "" then
    exact = allWidgets[rootId .. suffix]
  end
  if exact ~= nil then
    return exact
  end

  local bestKey = nil
  local bestWidget = nil
  for key, widget in pairs(allWidgets) do
    if type(key) == "string" and endsWith(key, suffix) then
      local rootMatches = type(rootId) ~= "string" or rootId == "" or key:sub(1, #rootId) == rootId
      if rootMatches then
        if bestKey == nil or #key < #bestKey then
          bestKey = key
          bestWidget = widget
        end
      end
    end
  end
  return bestWidget
end

local function findScopedBehavior(runtime, rootId, suffix)
  if not (runtime and runtime.behaviors and type(suffix) == "string" and suffix ~= "") then
    return nil
  end

  local exactId = nil
  if type(rootId) == "string" and rootId ~= "" then
    exactId = rootId .. suffix
  end
  if exactId ~= nil then
    for _, behavior in ipairs(runtime.behaviors) do
      if behavior.id == exactId then
        return behavior
      end
    end
  end

  local best = nil
  for _, behavior in ipairs(runtime.behaviors) do
    local id = behavior.id
    if type(id) == "string" and endsWith(id, suffix) then
      local rootMatches = type(rootId) ~= "string" or rootId == "" or id:sub(1, #rootId) == rootId
      if rootMatches then
        if best == nil or #id < #(best.id or "") then
          best = behavior
        end
      end
    end
  end
  return best
end

local function getScopedWidget(ctx, suffix)
  if type(ctx) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end
  local cache = ctx._scopedWidgetCache
  if type(cache) ~= "table" then
    cache = {}
    ctx._scopedWidgetCache = cache
  end
  local cached = cache[suffix]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local widget = findScopedWidget(ctx.allWidgets or {}, ctx._globalPrefix or "root", suffix)
  cache[suffix] = widget or false
  return widget
end

local function getScopedBehavior(ctx, suffix)
  if type(ctx) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end
  local cache = ctx._scopedBehaviorCache
  if type(cache) ~= "table" then
    cache = {}
    ctx._scopedBehaviorCache = cache
  end
  local cached = cache[suffix]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local runtime = _G.__manifoldStructuredUiRuntime
  local behavior = findScopedBehavior(runtime, ctx._globalPrefix or "root", suffix)
  cache[suffix] = behavior or false
  return behavior
end

local function flushDeferredRefreshesNow()
  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.flushDeferredRefreshes) == "function" then
    pcall(function() shell:flushDeferredRefreshes() end)
  end
end

local function refreshRetainedSubtree(node)
  if node == nil then
    return
  end

  if node.getUserData ~= nil then
    local meta = node:getUserData("_editorMeta")
    if type(meta) == "table" then
      local widget = meta.widget
      if type(widget) == "table" and type(widget.refreshRetained) == "function" then
        local w = 0
        local h = 0
        if node.getWidth ~= nil and node.getHeight ~= nil then
          w = tonumber(node:getWidth()) or 0
          h = tonumber(node:getHeight()) or 0
        elseif node.getBounds ~= nil then
          local _, _, bw, bh = node:getBounds()
          w = tonumber(bw) or 0
          h = tonumber(bh) or 0
        end
        pcall(function() widget:refreshRetained(w, h) end)
      end
    end
  end

  if node.getNumChildren ~= nil and node.getChild ~= nil then
    local childCount = math.max(0, math.floor(tonumber(node:getNumChildren()) or 0))
    for i = 0, childCount - 1 do
      local child = node:getChild(i)
      if child ~= nil then
        refreshRetainedSubtree(child)
      end
    end
  end
end

local function forcePatchbayRetainedRefresh(widget, patchbayPanel)
  if widget and widget.node then
    refreshRetainedSubtree(widget.node)
    if widget.node.markRenderDirty then
      pcall(function() widget.node:markRenderDirty() end)
    end
    if widget.node.repaint then
      pcall(function() widget.node:repaint() end)
    end
  end

  if patchbayPanel and patchbayPanel.node then
    refreshRetainedSubtree(patchbayPanel.node)
    if patchbayPanel.node.markRenderDirty then
      pcall(function() patchbayPanel.node:markRenderDirty() end)
    end
    if patchbayPanel.node.repaint then
      pcall(function() patchbayPanel.node:repaint() end)
    end
  end

  flushDeferredRefreshesNow()
end

local function setWidgetValueSilently(widget, value)
  if not (widget and widget.setValue) then
    return
  end
  local onChange = widget._onChange
  widget._onChange = nil
  local ok, err = pcall(function()
    widget:setValue(value)
  end)
  widget._onChange = onChange
  if not ok then
    error(err)
  end
end

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
  samplePitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
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
  addFlavor = "/midi/synth/blend/addFlavor",
  xorBehavior = "/midi/synth/blend/xorBehavior",
  morphCurve = "/midi/synth/blend/morphCurve",
  morphConvergence = "/midi/synth/blend/morphConvergence",
  morphPhase = "/midi/synth/blend/morphPhase",
  morphSpeed = "/midi/synth/blend/morphSpeed",
  morphContrast = "/midi/synth/blend/morphContrast",
  morphSmooth = "/midi/synth/blend/morphSmooth",
}

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

-- Lightweight XY pad refresh (no layout rebuild)
local function refreshFxPad(fxCtx)
  if not fxCtx then return end
  local pad = fxCtx.widgets and fxCtx.widgets.xy_pad
  if not pad or not pad.node then return end
  local w = pad.node:getWidth()
  local h = pad.node:getHeight()
  if w <= 0 or h <= 0 then return end
  -- Delegate to behavior's refreshPad if available, else just repaint
  if fxCtx._refreshPad then
    fxCtx._refreshPad()
  else
    pad.node:repaint()
  end
end

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
  -- Never fight direct manipulation (knob drag, slider drag, etc.).
  if widget._dragging then
    return
  end
  local current = widget.getValue and widget:getValue() or nil
  local threshold = epsilon or 0.0001
  if current == nil or math.abs((tonumber(current) or 0) - (tonumber(value) or 0)) > threshold then
    widget:setValue(value)
    repaint(widget)
  end
end

local function syncToggleValue(widget, value)
  if not (widget and widget.setValue and value ~= nil) then
    return
  end
  local current = widget.getValue and widget:getValue() or nil
  local nextValue = value == true
  if current ~= nextValue then
    widget:setValue(nextValue)
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
  -- Don't mutate selection while a dropdown popup is open.
  if widget._open then
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

local function noteToFreq(note)
  return 440.0 * (2.0 ^ ((note - 69) / 12.0))
end

local function updateDropdownAnchors(ctx)
  local _ = ctx
  -- Dropdown popup placement is now handled in the widget itself.
  -- Keep this hook as a no-op so older call sites do not explode.
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

local function formatMidiNoteValue(value)
  local midi = round(clamp(value or 0, 0, 127))
  return string.format("%s (%d)", noteName(midi), midi)
end

local function velocityToAmp(velocity)
  return clamp(0.03 + ((tonumber(velocity) or 0) / 127.0) * 0.37, 0.0, 0.40)
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

loadRuntimeState = function()
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

saveRuntimeState = function(state)
  local path = runtimeStatePath()
  if path == "" or type(writeTextFile) ~= "function" then
    return false
  end

  local rackState = state.rackState or {
    viewMode = state.rackViewMode,
    densityMode = state.rackDensityMode,
    utilityDock = {
      visible = state.utilityDockVisible,
      mode = state.utilityDockMode,
      heightMode = state.utilityDockHeightMode,
    },
    nodes = state.rackNodes,
  }

  -- Serialize rackNodes array
  local function serializeNodes(nodes)
    if type(nodes) ~= "table" or #nodes == 0 then
      return "{}"
    end
    local parts = {"{"}
    for i, node in ipairs(nodes) do
      local nodeParts = {
        string.format("id=%q", tostring(node.id or "")),
        string.format("row=%d", tonumber(node.row) or 0),
        string.format("col=%d", tonumber(node.col) or 0),
        string.format("w=%d", tonumber(node.w) or 1),
        string.format("h=%d", tonumber(node.h) or 1),
      }
      if node.sizeKey then
        table.insert(nodeParts, string.format("sizeKey=%q", tostring(node.sizeKey)))
      end
      table.insert(parts, "  { " .. table.concat(nodeParts, ", ") .. " },")
    end
    table.insert(parts, "}")
    return table.concat(parts, "\n")
  end

  local lines = {
    "return {",
    string.format("  inputDevice = %q,", tostring(state.inputDevice or "")),
    string.format("  keyboardCollapsed = %s,", state.keyboardCollapsed and "true" or "false"),
    string.format("  utilityDockVisible = %s,", state.utilityDockVisible == false and "false" or "true"),
    string.format("  utilityDockMode = %q,", tostring(state.utilityDockMode or "full_keyboard")),
    string.format("  utilityDockHeightMode = %q,", tostring(state.utilityDockHeightMode or (state.keyboardCollapsed and "collapsed" or "full"))),
    string.format("  rackViewMode = %q,", tostring(rackState.viewMode or "perf")),
    string.format("  rackDensityMode = %q,", tostring(rackState.densityMode or "normal")),
    "  rackNodes = " .. serializeNodes(rackState.nodes) .. ",",
    string.format("  waveform = %d,", tonumber(state.waveform) or 1),
    string.format("  filterType = %d,", tonumber(state.filterType) or 0),
    string.format("  cutoff = %.2f,", tonumber(state.cutoff) or 3200),
    string.format("  resonance = %.3f,", tonumber(state.resonance) or 0.75),
    string.format("  drive = %.2f,", tonumber(state.drive) or 0.0),
    string.format("  driveShape = %d,", tonumber(state.driveShape) or 0),
    string.format("  driveBias = %.3f,", tonumber(state.driveBias) or 0.0),
    string.format("  output = %.3f,", tonumber(state.output) or 0.8),
    string.format("  attack = %.4f,", tonumber(state.attack) or 0.05),
    string.format("  decay = %.4f,", tonumber(state.decay) or 0.2),
    string.format("  sustain = %.3f,", tonumber(state.sustain) or 0.7),
    string.format("  release = %.4f,", tonumber(state.release) or 0.4),
    string.format("  fx1Type = %d,", tonumber(state.fx1Type) or 0),
    string.format("  fx1Mix = %.3f,", tonumber(state.fx1Mix) or 0.0),
    string.format("  fx2Type = %d,", tonumber(state.fx2Type) or 0),
    string.format("  fx2Mix = %.3f,", tonumber(state.fx2Mix) or 0.0),
    string.format("  oscMode = %d,", tonumber(state.oscMode) or 0),
    string.format("  sampleSource = %d,", tonumber(state.sampleSource) or 0),
    string.format("  sampleCaptureBars = %.4f,", tonumber(state.sampleCaptureBars) or 1.0),
    string.format("  samplePitchMapEnabled = %s,", state.samplePitchMapEnabled and "true" or "false"),
    string.format("  sampleRootNote = %.2f,", tonumber(state.sampleRootNote) or 60.0),
    string.format("  samplePlayStart = %.4f,", tonumber(state.samplePlayStart) or 0.0),
    string.format("  sampleLoopStart = %.4f,", tonumber(state.sampleLoopStart) or 0.0),
    string.format("  sampleLoopLen = %.4f,", tonumber(state.sampleLoopLen) or 1.0),
    string.format("  sampleRetrigger = %d,", tonumber(state.sampleRetrigger) or 1),
    string.format("  blendMode = %d,", tonumber(state.blendMode) or 0),
    string.format("  blendAmount = %.3f,", tonumber(state.blendAmount) or 0.5),
    string.format("  waveToSample = %.3f,", tonumber(state.waveToSample) or 0.5),
    string.format("  sampleToWave = %.3f,", tonumber(state.sampleToWave) or 0.0),
    string.format("  blendKeyTrack = %d,", tonumber(state.blendKeyTrack) or 2),
    string.format("  blendSamplePitch = %.2f,", tonumber(state.blendSamplePitch) or 0.0),
    string.format("  blendModAmount = %.3f,", tonumber(state.blendModAmount) or 0.5),
    string.format("  addFlavor = %d,", tonumber(state.addFlavor) or 0),
    string.format("  xorBehavior = %d,", tonumber(state.xorBehavior) or 0),
    string.format("  delayMix = %.3f,", tonumber(state.delayMix) or 0.0),
    string.format("  delayTime = %d,", tonumber(state.delayTime) or 220),
    string.format("  delayFeedback = %.3f,", tonumber(state.delayFeedback) or 0.24),
    string.format("  reverbWet = %.3f,", tonumber(state.reverbWet) or 0.0),
    string.format("  pulseWidth = %.2f,", tonumber(state.pulseWidth) or 0.5),
    string.format("  unison = %d,", tonumber(state.unison) or 1),
    string.format("  detune = %.1f,", tonumber(state.detune) or 0.0),
    string.format("  spread = %.2f,", tonumber(state.spread) or 0.0),
    string.format("  oscRenderMode = %d,", tonumber(state.oscRenderMode) or 0),
    string.format("  additivePartials = %d,", tonumber(state.additivePartials) or 8),
    string.format("  additiveTilt = %.3f,", tonumber(state.additiveTilt) or 0.0),
    string.format("  additiveDrift = %.3f,", tonumber(state.additiveDrift) or 0.0),
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

local function getCurrentMidiInputLabel(ctx)
  if Midi and Midi.currentInputDeviceName then
    local name = Midi.currentInputDeviceName()
    if type(name) == "string" and name ~= "" then
      return name
    end
  end

  if Midi and Midi.currentInputDeviceIndex and Midi.isInputOpen and Midi.isInputOpen() then
    local deviceIndex = tonumber(Midi.currentInputDeviceIndex()) or -1
    if deviceIndex >= 0 then
      local devices = ctx and ctx._midiDevices or (Midi.inputDevices and Midi.inputDevices() or {})
      return devices[deviceIndex + 1]
    end
  end

  return nil
end

local function persistMidiInputSelection(label)
  local state = loadRuntimeState()
  state.inputDevice = tostring(label or "")
  saveRuntimeState(state)
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
    if persist then
      persistMidiInputSelection("")
    end
    return true
  end
  
  local deviceIndex = idx - 2
  local success = Midi and Midi.openInput and Midi.openInput(deviceIndex) or false
  if success then
    local activeLabel = getCurrentMidiInputLabel(ctx) or label
    local activeIdx = findOptionIndex(options, activeLabel) or idx
    ctx._selectedMidiInputIdx = activeIdx
    ctx._selectedMidiInputLabel = activeLabel
    ctx._lastEvent = "Opened: " .. activeLabel
    syncSelected(widgets.midiInputDropdown, activeIdx)
    syncText(widgets.deviceValue, "Input: " .. activeLabel)
    if persist then
      persistMidiInputSelection(activeLabel)
    end
    return true
  end
  
  ctx._lastEvent = "Failed: " .. label
  return false
end

local function refreshMidiDevices(ctx, restoreSelection)
  local widgets = ctx.widgets or {}
  local options = buildMidiOptions(ctx)
  ctx._midiOptions = options
  ctx._lastKnownMidiDeviceCount = math.max(0, #options - 1)
  
  if widgets.midiInputDropdown then
    widgets.midiInputDropdown:setOptions(options)
    repaint(widgets.midiInputDropdown)
  end

  local activeLabel = getCurrentMidiInputLabel(ctx)
  local activeIdx = findOptionIndex(options, activeLabel)
  local idx = activeIdx or 1

  local saved = restoreSelection and loadRuntimeState() or nil
  if not activeIdx and saved and saved.inputDevice then
    local savedIdx = findOptionIndex(options, saved.inputDevice)
    if savedIdx then
      idx = savedIdx
    end
  elseif not activeIdx and ctx._selectedMidiInputLabel then
    local currentIdx = findOptionIndex(options, ctx._selectedMidiInputLabel)
    if currentIdx then
      idx = currentIdx
    end
  end
  
  syncSelected(widgets.midiInputDropdown, idx)
  ctx._selectedMidiInputIdx = idx
  ctx._selectedMidiInputLabel = options[idx] or options[1]
  
  if not activeIdx and restoreSelection and idx > 1 then
    applyMidiSelection(ctx, idx, false)
  else
    if activeLabel then
      ctx._selectedMidiInputLabel = activeLabel
      ctx._selectedMidiInputIdx = activeIdx or idx
    end
    syncText(widgets.deviceValue, "Input: " .. (ctx._selectedMidiInputLabel or options[1] or "None"))
  end
end

local function maybeRefreshMidiDevices(ctx, now)
  if not (Midi and Midi.inputDevices) then
    return
  end
  if (now - (ctx._lastMidiDeviceScanTime or 0)) < 1.0 then
    return
  end
  ctx._lastMidiDeviceScanTime = now

  local devices = Midi.inputDevices() or {}
  local deviceCount = #devices
  local activeLabel = getCurrentMidiInputLabel(ctx)
  local selectedLabel = ctx._selectedMidiInputLabel or ""
  local options = ctx._midiOptions or {}
  local dropdownOpen = ctx.widgets and ctx.widgets.midiInputDropdown and ctx.widgets.midiInputDropdown._open

  local shouldRefresh = false
  if deviceCount ~= (ctx._lastKnownMidiDeviceCount or -1) then
    shouldRefresh = true
  elseif deviceCount > 0 and #options <= 1 then
    shouldRefresh = true
  elseif activeLabel and activeLabel ~= selectedLabel then
    shouldRefresh = true
  elseif deviceCount > 0 and (selectedLabel == "" or selectedLabel == "None (Disabled)" or selectedLabel == "Use Host MIDI") then
    local saved = loadRuntimeState()
    if saved and type(saved.inputDevice) == "string" and saved.inputDevice ~= "" then
      shouldRefresh = true
    end
  end

  ctx._lastKnownMidiDeviceCount = deviceCount
  if shouldRefresh and not dropdownOpen then
    refreshMidiDevices(ctx, true)
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

local function updateEnvelopes(ctx, dt, now)
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice then
      local amp = calculateEnvelope(ctx, i, dt)
      voice.currentAmp = amp

      local sentAmp = voice.sentAmp or 0
      local elapsed = now - (voice.lastAmpPushTime or 0)
      local changedEnough = math.abs(amp - sentAmp) >= VOICE_AMP_SEND_EPSILON
      local atRestEdge = (amp <= VOICE_AMP_SEND_EPSILON and sentAmp > VOICE_AMP_SEND_EPSILON)

      if changedEnough and (elapsed >= VOICE_AMP_SEND_INTERVAL or atRestEdge) then
        voice.sentAmp = amp
        voice.lastAmpPushTime = now
        setPath(voiceAmpPath(i), amp)
      end
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
  voice.currentAmp = 0  -- ADSR starts at 0
  voice.gate = 1
  voice.envelopeStage = "attack"
  voice.envelopeTime = 0
  voice.envelopeStartLevel = 0
  voice.envelopeLevel = 0
  voice.currentAmp = 0
  voice.sentAmp = -1 -- force immediate first amp push on next envelope tick
  voice.lastAmpPushTime = 0
  voice.freq = noteToFreq(note)
  
  setPath(voiceFreqPath(index), voice.freq)
  setPath(voiceGatePath(index), 1)
  ctx._keyboardDirty = true
  
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
      voice.lastAmpPushTime = 0
      setPath(voiceGatePath(i), 0)
      ctx._keyboardDirty = true
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
    voice.sentAmp = 0
    voice.lastAmpPushTime = 0
    voice.envelopeStage = "idle"
    voice.envelopeLevel = 0
    voice.freq = 220
    setPath(voiceAmpPath(i), 0)
    setPath(voiceGatePath(i), 0)
  end
  ctx._keyboardDirty = true
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

local refreshManagedLayoutState
local syncKeyboardDisplay
local syncPatchViewMode

local function getOctaveLabel(baseOctave)
  local startNote = "C" .. baseOctave
  local endNote = "C" .. (baseOctave + 2)
  return startNote .. "-" .. endNote
end

local function ensureUtilityDockState(ctx)
  local existing = ctx._utilityDock or {}
  ctx._utilityDock = {
    visible = existing.visible ~= false,
    mode = type(existing.mode) == "string" and existing.mode ~= "" and existing.mode or "keyboard",
    heightMode = type(existing.heightMode) == "string" and existing.heightMode or "full",
    layoutMode = type(existing.layoutMode) == "string" and existing.layoutMode or "single",
    primary = type(existing.primary) == "table" and existing.primary or {kind="keyboard",variant="full"},
    secondary = type(existing.secondary) == "table" and existing.secondary or nil,
  }
  _G.__midiSynthUtilityDock = ctx._utilityDock
  return ctx._utilityDock
end

-- Rack pagination state management
local function ensureRackPaginationState(ctx)
  if not ctx._rackPagination then
    ctx._rackPagination = {
      totalRows = 3,
      visibleRows = {1, 2},
      viewportOffset = 0,
      showAll = false,
    }
  end
  _G.__midiSynthRackPagination = ctx._rackPagination
  return ctx._rackPagination
end

local function updateRackPaginationDots(ctx)
  local p = ensureRackPaginationState(ctx)
  local dots = ctx._rackDots or {}
  for _, entry in ipairs(dots) do
    local dot = entry.widget
    local i = entry.index
    if dot then
      local isActive = false
      for _, r in ipairs(p.visibleRows) do
        if r == i then isActive = true; break end
      end
      local newColour = isActive and 0xffffffff or 0xff475569
      -- Runtime widgets use _colour directly, not style.colour
      if dot._colour ~= newColour then
        dot._colour = newColour
        if dot._syncRetained then dot:_syncRetained() end
        if dot.node and dot.node.repaint then dot.node:repaint() end
      end
    end
  end
end

local function setRackViewport(ctx, offset, showAll)
  local p = ensureRackPaginationState(ctx)
  local rackContainer = ctx.widgets.rackContainer
  if not rackContainer then return end
  
  p.viewportOffset = offset or 0
  p.showAll = showAll or false
  
  if p.showAll then
    p.visibleRows = {1, 2, 3}
    rackContainer.h = 684
    rackContainer.y = 0
  elseif p.viewportOffset == 0 then
    p.visibleRows = {1, 2}
    rackContainer.h = 452
    rackContainer.y = 0
  else
    p.visibleRows = {2, 3}
    rackContainer.h = 452
    rackContainer.y = -232
  end
  
  updateRackPaginationDots(ctx)
end

local function onRackDotClick(ctx, dotIndex)
  local p = ensureRackPaginationState(ctx)
  
  if dotIndex == 1 then
    setRackViewport(ctx, 0, false)
  elseif dotIndex == 3 then
    setRackViewport(ctx, 1, false)
  else
    -- Middle dot: toggle between 1-2 and 2-3
    if p.viewportOffset == 0 then
      setRackViewport(ctx, 1, false)
    else
      setRackViewport(ctx, 0, false)
    end
  end
end

local RACK_SHELL_LAYOUT

-- Same-row drag reorder state
local dragState = {
  active = false,
  shellId = nil,
  nodeId = nil,
  row = nil,
  startX = 0,
  startY = 0,
  grabOffsetX = 0,
  grabOffsetY = 0,
  startIndex = nil,
  targetIndex = nil,
  previewIndex = nil,
  rowSnapshot = nil,
  baseNodes = nil,
  ghostStartX = 0,
  ghostStartY = 0,
  ghostX = 0,
  ghostY = 0,
  ghostW = 0,
  ghostH = 0,
}

local function resetDragState(ctx)
  if ctx then
    ctx._dragPreviewNodes = nil
  end
  dragState.active = false
  dragState.shellId = nil
  dragState.nodeId = nil
  dragState.row = nil
  dragState.startX = 0
  dragState.startY = 0
  dragState.grabOffsetX = 0
  dragState.grabOffsetY = 0
  dragState.startIndex = nil
  dragState.targetIndex = nil
  dragState.previewIndex = nil
  dragState.rowSnapshot = nil
  dragState.baseNodes = nil
  dragState.ghostStartX = 0
  dragState.ghostStartY = 0
  dragState.ghostX = 0
  dragState.ghostY = 0
  dragState.ghostW = 0
  dragState.ghostH = 0
end

local function getRackShellMetaByNodeId(nodeId)
  return type(RACK_SHELL_LAYOUT) == "table" and RACK_SHELL_LAYOUT[nodeId] or nil
end

local function getRackNodeIdByShellId(shellId)
  if type(RACK_SHELL_LAYOUT) ~= "table" then
    return nil, nil
  end
  for nodeId, meta in pairs(RACK_SHELL_LAYOUT) do
    if type(meta) == "table" and meta.shellId == shellId then
      return nodeId, meta
    end
  end
  return nil, nil
end

local function getWidgetBounds(widget)
  if not (widget and widget.node and widget.node.getBounds) then
    return nil
  end
  local x, y, w, h = widget.node:getBounds()
  return {
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
    w = tonumber(w) or 0,
    h = tonumber(h) or 0,
  }
end

local function getWidgetBoundsInRoot(ctx, widget)
  if not widget then
    return nil
  end

  local bounds = getWidgetBounds(widget)
  if not bounds then
    return nil
  end

  local rootId = type(ctx) == "table" and ctx._globalPrefix or nil
  local record = widget._structuredRecord
  local current = type(record) == "table" and record.parent or nil

  while current do
    if current.globalId == rootId then
      break
    end

    local parentWidget = current.widget
    local parentBounds = getWidgetBounds(parentWidget)
    if parentBounds then
      bounds.x = bounds.x + (tonumber(parentBounds.x) or 0)
      bounds.y = bounds.y + (tonumber(parentBounds.y) or 0)
    end
    current = current.parent
  end

  return bounds
end

local function getShellWidget(ctx, nodeId)
  local meta = getRackShellMetaByNodeId(nodeId)
  if not meta then
    return nil
  end
  return getScopedWidget(ctx, "." .. meta.shellId)
end

local function setShellDragPlaceholder(ctx, nodeId, active)
  local shellWidget = getShellWidget(ctx, nodeId)
  if not shellWidget or type(shellWidget.setStyle) ~= "function" then
    return
  end
  shellWidget:setStyle({ opacity = active and 0.22 or 1.0 })
  if shellWidget.node and shellWidget.node.repaint then
    shellWidget.node:repaint()
  end
end

local function ensureDragGhost(ctx)
  if ctx._dragGhostCanvas then
    return ctx._dragGhostCanvas, ctx._dragGhostAccentCanvas
  end
  if not (ctx and ctx.root and ctx.root.node and ctx.root.node.addChild) then
    return nil, nil
  end

  local ghost = ctx.root.node:addChild("rackDragGhost")
  if not ghost then
    return nil, nil
  end
  ghost:setInterceptsMouse(false, false)
  ghost:setVisible(false)
  ghost:setStyle({ bg = 0xcc121a2f, border = 0xff94a3b8, borderWidth = 2, radius = 0, opacity = 0.92 })
  if ghost.toFront then
    ghost:toFront(false)
  end

  local accent = ghost:addChild("accent")
  if accent then
    accent:setInterceptsMouse(false, false)
    accent:setStyle({ bg = 0xffffffff, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
  end

  ctx._dragGhostCanvas = ghost
  ctx._dragGhostAccentCanvas = accent
  return ghost, accent
end

local function hideDragGhost(ctx)
  local ghost = ctx and ctx._dragGhostCanvas or nil
  if ghost then
    ghost:setVisible(false)
  end
end

local function updateDragGhost(ctx)
  local ghost, accent = ensureDragGhost(ctx)
  if not ghost then
    return
  end
  ghost:setBounds(
    math.floor((dragState.ghostX or 0) + 0.5),
    math.floor((dragState.ghostY or 0) + 0.5),
    math.max(1, math.floor((dragState.ghostW or 1) + 0.5)),
    math.max(1, math.floor((dragState.ghostH or 1) + 0.5))
  )
  ghost:setVisible(true)
  if ghost.toFront then
    ghost:toFront(false)
  end
  if accent then
    accent:setBounds(0, 0, math.max(1, math.floor((dragState.ghostW or 1) + 0.5)), 12)
  end
end

local RACK_COLUMNS_PER_ROW = 5

local function getActiveRackNodes(ctx)
  return (ctx and (ctx._dragPreviewNodes or (ctx._rackState and ctx._rackState.nodes))) or {}
end

local function getActiveRackNodeById(ctx, nodeId)
  local nodes = getActiveRackNodes(ctx)
  for i = 1, #nodes do
    if nodes[i] and nodes[i].id == nodeId then
      return nodes[i]
    end
  end
  return nil
end

local function collectRackFlowSnapshot(ctx)
  local snapshot = {}
  local orderedNodes = RackLayout.getFlowNodes(getActiveRackNodes(ctx))
  for i = 1, #orderedNodes do
    local node = orderedNodes[i]
    local meta = getRackShellMetaByNodeId(node.id)
    if meta then
      local shellWidget = getScopedWidget(ctx, "." .. meta.shellId)
      local bounds = getWidgetBoundsInRoot(ctx, shellWidget)
      if bounds and bounds.w > 0 then
        snapshot[#snapshot + 1] = {
          id = node.id,
          row = tonumber(node.row) or 0,
          col = tonumber(node.col) or 0,
          bounds = bounds,
          index = i,
        }
      end
    end
  end
  return snapshot
end

local function collectRackRowBands(ctx, snapshot)
  local rowBands = {}
  for row = 0, 2 do
    local rowWidget = getScopedWidget(ctx, ".rackRow" .. tostring(row + 1))
    local visible = rowWidget and rowWidget.isVisible and rowWidget:isVisible()
    if visible ~= false then
      local rowBounds = getWidgetBoundsInRoot(ctx, rowWidget)
      if rowBounds and rowBounds.h > 0 then
        rowBands[#rowBands + 1] = {
          row = row,
          top = tonumber(rowBounds.y) or 0,
          bottom = (tonumber(rowBounds.y) or 0) + (tonumber(rowBounds.h) or 0),
        }
      end
    end
  end

  if #rowBands == 0 and type(snapshot) == "table" then
    local byRow = {}
    for i = 1, #snapshot do
      local entry = snapshot[i]
      local row = tonumber(entry.row) or 0
      local band = byRow[row]
      local top = tonumber(entry.bounds.y) or 0
      local bottom = top + (tonumber(entry.bounds.h) or 0)
      if not band then
        byRow[row] = { row = row, top = top, bottom = bottom }
      else
        if top < band.top then band.top = top end
        if bottom > band.bottom then band.bottom = bottom end
      end
    end
    for _, band in pairs(byRow) do
      rowBands[#rowBands + 1] = band
    end
  end

  table.sort(rowBands, function(a, b)
    if a.top ~= b.top then
      return a.top < b.top
    end
    return (a.row or 0) < (b.row or 0)
  end)
  return rowBands
end

local function computeRackFlowTargetIndex(ctx, snapshot, movingNodeId, centerX, centerY)
  if type(snapshot) ~= "table" or #snapshot == 0 then
    return nil
  end

  local rowBands = collectRackRowBands(ctx, snapshot)
  if #rowBands == 0 then
    return nil
  end

  local selectedRow = rowBands[1].row
  local y = tonumber(centerY) or 0
  for i = 1, #rowBands do
    local band = rowBands[i]
    local nextBand = rowBands[i + 1]
    selectedRow = band.row
    if not nextBand then
      break
    end
    local boundary = ((tonumber(band.bottom) or 0) + (tonumber(nextBand.top) or 0)) * 0.5
    if y < boundary then
      break
    end
  end

  local entriesByRow = {}
  local flowCount = 0
  local hasMoving = false
  for i = 1, #snapshot do
    local entry = snapshot[i]
    if entry.id == movingNodeId then
      hasMoving = true
    else
      flowCount = flowCount + 1
      local row = tonumber(entry.row) or 0
      local bucket = entriesByRow[row]
      if not bucket then
        bucket = {}
        entriesByRow[row] = bucket
      end
      bucket[#bucket + 1] = entry
    end
  end
  if not hasMoving then
    return nil
  end

  local rowEntries = entriesByRow[selectedRow] or {}
  table.sort(rowEntries, function(a, b)
    local ac = tonumber(a.col) or 0
    local bc = tonumber(b.col) or 0
    if ac ~= bc then
      return ac < bc
    end
    return tostring(a.id or "") < tostring(b.id or "")
  end)

  local rowTargetIndex = 1
  for i = 1, #rowEntries do
    local midpoint = (tonumber(rowEntries[i].bounds.x) or 0) + ((tonumber(rowEntries[i].bounds.w) or 0) * 0.5)
    if (tonumber(centerX) or 0) > midpoint then
      rowTargetIndex = rowTargetIndex + 1
    end
  end

  local targetIndex = rowTargetIndex
  for _, band in ipairs(rowBands) do
    if (tonumber(band.row) or 0) < selectedRow then
      targetIndex = targetIndex + #(entriesByRow[band.row] or {})
    end
  end

  if targetIndex < 1 then
    targetIndex = 1
  end
  if targetIndex > (flowCount + 1) then
    targetIndex = flowCount + 1
  end
  return targetIndex
end

local function previewRackDragReorder(ctx, targetIndex)
  if not dragState.active or not dragState.nodeId then
    return false
  end
  if type(dragState.baseNodes) ~= "table" then
    return false
  end

  local nextIndex = tonumber(targetIndex) or dragState.startIndex
  if not nextIndex then
    return false
  end
  if dragState.previewIndex == nextIndex then
    return false
  end

  local ok, nextNodes = pcall(RackLayout.moveNodeInFlow, dragState.baseNodes, dragState.nodeId, nextIndex, RACK_COLUMNS_PER_ROW, 0)
  if not ok or type(nextNodes) ~= "table" then
    print("[Drag] Preview reorder failed for " .. tostring(dragState.nodeId) .. ": " .. tostring(nextNodes))
    return false
  end

  ctx._dragPreviewNodes = nextNodes
  dragState.previewIndex = nextIndex
  dragState.targetIndex = nextIndex
  refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
  return true
end

local function finalizeRackDragReorder(ctx)
  if not dragState.active or not dragState.nodeId then
    return false
  end

  local finalNodes = ctx._dragPreviewNodes or dragState.baseNodes
  local finalIndex = dragState.previewIndex or dragState.startIndex
  if type(finalNodes) ~= "table" or not finalIndex then
    return false
  end

  ctx._rackState.nodes = RackLayout.cloneNodes(finalNodes)
  ctx._rackState.utilityDock = ensureUtilityDockState(ctx)
  _G.__midiSynthRackState = ctx._rackState
  ctx._dragPreviewNodes = nil
  if finalIndex ~= dragState.startIndex then
    ctx._lastEvent = string.format("Rack moved: %s → slot %d", tostring(dragState.nodeId), tonumber(finalIndex) or -1)
  end
  refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
  return finalIndex ~= dragState.startIndex
end

local function setupShellDragHandlers(ctx)
  if type(RACK_SHELL_LAYOUT) ~= "table" then
    return
  end

  for _, meta in pairs(RACK_SHELL_LAYOUT) do
    local shellId = meta.shellId
    local nodeId = getRackNodeIdByShellId(shellId)
    local accent = getScopedWidget(ctx, "." .. shellId .. ".accent")

    if accent and accent.node and nodeId then
      accent.node:setInterceptsMouse(true, true)

      local isDragging = false

      accent.node:setOnMouseDown(function(x, y)
        local currentNode = getActiveRackNodeById(ctx, nodeId)
        local snapshot = collectRackFlowSnapshot(ctx)
        local shellWidget = getShellWidget(ctx, nodeId)
        local rootBounds = getWidgetBoundsInRoot(ctx, shellWidget)
        local startCenterX = rootBounds and ((rootBounds.x or 0) + ((rootBounds.w or 0) * 0.5)) or 0
        local startCenterY = rootBounds and ((rootBounds.y or 0) + ((rootBounds.h or 0) * 0.5)) or 0
        local startIndex = computeRackFlowTargetIndex(ctx, snapshot, nodeId, startCenterX, startCenterY)
        if not startIndex or not rootBounds then
          return
        end

        isDragging = true
        dragState.active = true
        dragState.shellId = shellId
        dragState.nodeId = nodeId
        dragState.row = currentNode and currentNode.row or tonumber(meta.row) or 0
        dragState.startX = x
        dragState.startY = y
        dragState.grabOffsetX = x
        dragState.grabOffsetY = y
        dragState.startIndex = startIndex
        dragState.targetIndex = startIndex
        dragState.previewIndex = startIndex
        dragState.rowSnapshot = snapshot
        dragState.baseNodes = RackLayout.cloneNodes((ctx._rackState and ctx._rackState.nodes) or {})
        dragState.ghostStartX = rootBounds.x or 0
        dragState.ghostStartY = rootBounds.y or 0
        dragState.ghostX = rootBounds.x or 0
        dragState.ghostY = rootBounds.y or 0
        dragState.ghostW = rootBounds.w or 1
        dragState.ghostH = rootBounds.h or 1

        local ghost, ghostAccent = ensureDragGhost(ctx)
        local spec = ctx._rackNodeSpecs and ctx._rackNodeSpecs[nodeId] or nil
        local ghostAccentColor = (spec and spec.accentColor) or meta.accentColor or 0xff64748b
        if ghostAccent then
          ghostAccent:setStyle({ bg = ghostAccentColor, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
        end
        setShellDragPlaceholder(ctx, nodeId, true)
        updateDragGhost(ctx)
      end)

      accent.node:setOnMouseDrag(function(x, y, dx, dy)
        if not isDragging then return end

        dragState.ghostX = (dragState.ghostStartX or 0) + (tonumber(dx) or 0)
        dragState.ghostY = (dragState.ghostStartY or 0) + (tonumber(dy) or 0)
        updateDragGhost(ctx)

        local snapshot = collectRackFlowSnapshot(ctx)
        dragState.rowSnapshot = snapshot
        local ghostCenterX = (dragState.ghostX or 0) + ((dragState.ghostW or 0) * 0.5)
        local ghostCenterY = (dragState.ghostY or 0) + ((dragState.ghostH or 0) * 0.5)
        local targetIndex = computeRackFlowTargetIndex(ctx, snapshot, nodeId, ghostCenterX, ghostCenterY) or dragState.startIndex
        previewRackDragReorder(ctx, targetIndex)
        setShellDragPlaceholder(ctx, nodeId, true)
      end)

      accent.node:setOnMouseUp(function(x, y)
        if not isDragging then return end
        isDragging = false
        finalizeRackDragReorder(ctx)
        setShellDragPlaceholder(ctx, nodeId, false)
        hideDragGhost(ctx)
        resetDragState(ctx)
      end)
    end
  end
end

local function getUtilityDockState(ctx)
  return ensureUtilityDockState(ctx)
end

local function utilityDockHasKeyboard(ctx)
  local dock = ensureUtilityDockState(ctx)
  local primary = dock.primary or {}
  local secondary = dock.secondary or nil
  return primary.kind == "keyboard" or (secondary and secondary.kind == "keyboard")
end

-- Patchbay widget generation
-- Uses the patchbay_panel module to generate real interactive widget trees
-- from node specs, with sliders bound to DSP paths.
local PatchbayPanel = require("components.patchbay_panel")

-- Cache of instantiated patchbay widget trees per shell, keyed by shellId.
-- Prevents re-instantiation on every perf/patch toggle.
local patchbayInstances = {}
local patchbayPortRegistry = {}
local onPatchbayPageClick -- forward declare for pagination closures

local function clearPatchbayPortRegistryForShell(shellId, ctx)
  for key, entry in pairs(patchbayPortRegistry) do
    if type(entry) == "table" and entry.shellId == shellId then
      patchbayPortRegistry[key] = nil
    end
  end
  if ctx then
    ctx._patchbayPortRegistry = patchbayPortRegistry
  end
  _G.__midiSynthPatchbayPortRegistry = patchbayPortRegistry
end

local function registerPatchbayPort(entry, ctx)
  if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
    return
  end
  patchbayPortRegistry[entry.key] = entry
  if ctx then
    ctx._patchbayPortRegistry = patchbayPortRegistry
  end
  _G.__midiSynthPatchbayPortRegistry = patchbayPortRegistry
end

local function bindWirePortWidget(ctx, portWidget, entry)
  if not (portWidget and portWidget.node and type(entry) == "table") then
    return
  end

  entry.widget = portWidget
  registerPatchbayPort(entry, ctx)
  portWidget.node:setInterceptsMouse(true, true)

  if portWidget.node.setOnMouseDown then
    portWidget.node:setOnMouseDown(function(mx, my, shift, ctrl, alt)
      if (ctrl or alt) and RackWireLayer and RackWireLayer.deleteConnectionsForPort then
        local removed = RackWireLayer.deleteConnectionsForPort(ctx, entry)
        if removed > 0 then
          return
        end
      end
      if RackWireLayer and RackWireLayer.beginWireDrag then
        RackWireLayer.beginWireDrag(ctx, entry)
        if RackWireLayer.updateWireDragPointer then
          RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
        end
      end
    end)
  end

  if portWidget.node.setOnMouseDrag then
    portWidget.node:setOnMouseDrag(function(mx, my)
      if RackWireLayer and RackWireLayer.updateWireDragPointer then
        RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
      end
    end)
  end

  if portWidget.node.setOnMouseUp then
    portWidget.node:setOnMouseUp(function(mx, my)
      if RackWireLayer and RackWireLayer.updateWireDragPointer then
        RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
      end
      if RackWireLayer and RackWireLayer.finishWireDrag then
        RackWireLayer.finishWireDrag(ctx)
      end
    end)
  end
end

-- Invalidate patchbay cache for a specific node (or all if nodeId is nil).
-- Called when nodes resize so the patchbay regenerates for the new dimensions.
-- ctx is optional — if provided, clears the patchbayPanel's children via getScopedWidget.
local function cleanupPatchbayFromRuntime(shellId, ctx)
  clearPatchbayPortRegistryForShell(shellId, ctx)

  local runtime = _G.__manifoldStructuredUiRuntime
  if not runtime then return end

  -- Invalidate any deferred retained refreshes before tearing down widgets.
  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.clearDeferredRefreshes) == "function" then
    pcall(function() shell:clearDeferredRefreshes() end)
  end

  if RackWireLayer and RackWireLayer.cancelWireDrag then
    RackWireLayer.cancelWireDrag(ctx)
  end

  -- Remove stale widget entries from runtime.widgets for this shell's patchbay
  if runtime.widgets then
    local toRemove = {}
    for k, _ in pairs(runtime.widgets) do
      if type(k) == "string" and k:find(shellId .. "%.patchbayPanel%.patchbayContent", 1, false) then
        toRemove[#toRemove + 1] = k
      end
    end
    for _, k in ipairs(toRemove) do
      runtime.widgets[k] = nil
    end
  end

  if ctx then
    local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
    if panel and panel._structuredRecord then
      panel._structuredRecord.children = {}
    end
    if panel and panel.node and panel.node.clearChildren then
      pcall(function() panel.node:clearChildren() end)
    end
  end
end

local function invalidatePatchbay(nodeId, ctx)
  if nodeId == nil then
    -- Clear all
    for shellId, instance in pairs(patchbayInstances) do
      cleanupPatchbayFromRuntime(shellId, ctx)
      if ctx then
        local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
        if panel and panel.node and panel.node.clearChildren then
          pcall(function() panel.node:clearChildren() end)
        end
      end
    end
    patchbayInstances = {}
    return
  end
  -- Find the shellId for this nodeId
  if type(RACK_SHELL_LAYOUT) == "table" then
    local meta = RACK_SHELL_LAYOUT[nodeId]
    if meta then
      local shellId = meta.shellId
      if patchbayInstances[shellId] then
        cleanupPatchbayFromRuntime(shellId, ctx)
        if ctx then
          local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
          if panel and panel.node and panel.node.clearChildren then
            pcall(function() panel.node:clearChildren() end)
          end
        end
        patchbayInstances[shellId] = nil
      end
    end
  end
end

local function setupResizeToggleHandlers(ctx)
  if type(RACK_SHELL_LAYOUT) ~= "table" then
    return
  end
  for nodeId, meta in pairs(RACK_SHELL_LAYOUT) do
    local shellId = meta.shellId
    local toggle = getScopedWidget(ctx, "." .. shellId .. ".resizeToggle")
    if toggle and toggle.node then
      toggle.node:setInterceptsMouse(true, true)
      toggle.node:setOnMouseDown(function(x, y)
        local rackState = ctx._rackState
        local nodes = rackState and rackState.nodes or nil
        if not nodes then return end
        for i = 1, #nodes do
          local node = nodes[i]
          if node and node.id == nodeId then
            local currentW = tonumber(node.w) or 1
            local newW = (currentW == 1) and 2 or 1
            
            -- If expanding, check for overflow and auto-collapse a neighbor
            if newW == 2 then
              local targetRow = tonumber(node.row) or 0
              local rowTotal = 0
              local expandableNeighbor = nil
              
              -- Calculate current row total and find a collapsible neighbor
              for j = 1, #nodes do
                local other = nodes[j]
                if other and tonumber(other.row) == targetRow then
                  rowTotal = rowTotal + math.max(1, tonumber(other.w) or 1)
                  -- Find a 1x2 neighbor that can collapse (not the one we're expanding)
                  if other.id ~= nodeId and (tonumber(other.w) or 1) == 2 then
                    expandableNeighbor = other
                  end
                end
              end
              
              -- If row would overflow (5 slots is max: 1+2+2 or 2+1+2 etc), collapse neighbor
              if rowTotal >= 5 and expandableNeighbor then
                expandableNeighbor.w = 1
                expandableNeighbor.sizeKey = string.format("%dx%d", math.max(1, tonumber(expandableNeighbor.h) or 1), 1)
                invalidatePatchbay(expandableNeighbor.id, ctx)
              end
            end
            
            node.w = newW
            node.sizeKey = string.format("%dx%d", math.max(1, tonumber(node.h) or 1), newW)
            -- Invalidate patchbay cache so it regenerates for new size
            invalidatePatchbay(nodeId, ctx)
            -- Trigger layout reprojection
            if ctx._lastW and ctx._lastH then
              refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
            end
            -- If in patch view, immediately regenerate patchbay
            local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
            if viewMode == "patch" then
              syncPatchViewMode(ctx)
            end
            break
          end
        end
      end)
    end
  end
end

local function ensurePatchbayWidgets(ctx, shellId, specId, currentPage)
  currentPage = currentPage or 0
  
  -- Check if we already have an instance with the same page
  if patchbayInstances[shellId] and patchbayInstances[shellId].currentPage == currentPage then
    return patchbayInstances[shellId]
  end
  
  -- If page changed, we need to regenerate
  if patchbayInstances[shellId] and patchbayInstances[shellId].currentPage ~= currentPage then
    cleanupPatchbayFromRuntime(shellId, ctx)
    patchbayInstances[shellId] = nil
  end

  -- Check again after potential clear
  if patchbayInstances[shellId] then
    return patchbayInstances[shellId]
  end

  local spec = ctx._rackNodeSpecs and ctx._rackNodeSpecs[specId]
  if not spec then return nil end

  local patchbayPanel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
  if not patchbayPanel or not patchbayPanel.node then return nil end

  local runtime = _G.__manifoldStructuredUiRuntime
  if not runtime or not runtime.instantiateSpec then return nil end

  -- Get the shell bounds first to derive correct patchbay dimensions
  local shellWidget = getScopedWidget(ctx, "." .. shellId)
  local shellX, shellY, shellW, shellH = 0, 0, 236, 220
  if shellWidget and shellWidget.node and shellWidget.node.getBounds then
    shellX, shellY, shellW, shellH = shellWidget.node:getBounds()
  end
  local headerH = 12
  local pw = math.max(100, math.floor(tonumber(shellW) or 236))
  local ph = math.max(80, math.floor((tonumber(shellH) or 220) - headerH))

  -- Update patchbayPanel bounds to match shell
  patchbayPanel.node:setBounds(0, headerH, pw, ph)

  -- Determine node size from shell width (1x1 = 236px, 1x2 = 472px)
  local nodeSize = (pw >= 400) and "1x2" or "1x1"

  -- Generate the patchbay widget spec from the node spec with pagination
  local patchbaySpec = PatchbayPanel.generate(spec, pw, ph, nodeSize, currentPage)
  if not patchbaySpec then return nil end

  -- Build the global ID prefix for scoping
  local globalPrefix = ctx._globalPrefix or "root"
  local patchbayPrefix = globalPrefix .. "." .. shellId .. ".patchbayPanel"

  -- Clear any existing display list (from old implementation)
  patchbayPanel.node:setDisplayList({})

  -- Instantiate the widget tree into the patchbay panel
  local ok, widget, globalId, record = pcall(function()
    return runtime:instantiateSpec(patchbayPanel.node, patchbaySpec, {
      idPrefix = patchbayPrefix,
      localWidgets = ctx.allWidgets or {},
      extraProps = nil,
      isRoot = false,
      parentRecord = patchbayPanel._structuredRecord,
      sourceDocumentPath = "patchbay_dynamic",
      sourceKind = "node",
    })
  end)

  if not ok then
    print("[Patchbay] Failed to instantiate for " .. shellId .. ": " .. tostring(widget))
    return nil
  end

  -- Add the new record to the patchbayPanel's structured record children
  -- so the layout engine can walk and relayout the subtree on resize
  if record and patchbayPanel._structuredRecord then
    local parentChildren = patchbayPanel._structuredRecord.children
    if type(parentChildren) ~= "table" then
      parentChildren = {}
      patchbayPanel._structuredRecord.children = parentChildren
    end
    parentChildren[#parentChildren + 1] = record
  end

  -- Ensure the patchbay content widget fills its parent panel
  if widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(0, 0, math.floor(pw), math.floor(ph))
  end
  -- Trigger layout of the newly instantiated tree — notify both the content
  -- widget and the patchbayPanel parent so the full subtree gets laid out
  if widget and widget._structuredRuntime and widget._structuredRecord then
    pcall(function()
      widget._structuredRuntime:notifyRecordHostedResized(widget._structuredRecord, pw, ph)
    end)
  end
  if patchbayPanel._structuredRuntime and patchbayPanel._structuredRecord then
    pcall(function()
      patchbayPanel._structuredRuntime:notifyRecordHostedResized(patchbayPanel._structuredRecord, pw, ph)
    end)
  end

  forcePatchbayRetainedRefresh(widget, patchbayPanel)

  -- Wire up param sliders to DSP paths for the CURRENT page only.
  -- Use runtime.widgets for lookup since dynamically instantiated widgets
  -- are registered there, not necessarily in the behavior's ctx.allWidgets.
  local runtimeWidgets = runtime.widgets or {}

  local function findFirstWidget(searchPaths)
    for _, searchPath in ipairs(searchPaths or {}) do
      local candidate = runtimeWidgets[searchPath]
      if candidate then
        return candidate, searchPath
      end
    end
    return nil, nil
  end


  local allParams = (spec.ports or {}).params or {}
  local perPage = (nodeSize == "1x2") and (PatchbayPanel.PARAMS_PER_PAGE_1X2 or 16) or (PatchbayPanel.PARAMS_PER_PAGE_1X1 or 6)
  local startIdx = currentPage * perPage + 1
  local endIdx = math.min(#allParams, startIdx + perPage - 1)
  local currentParams = {}
  for idx = startIdx, endIdx do
    currentParams[#currentParams + 1] = allParams[idx]
  end

  local sliderWidgets = {}
  local boundCount = 0

  local inputs = (spec.ports or {}).inputs or {}
  for _, port in ipairs(inputs) do
    if port.edge == nil then
      local rowId = "input_" .. tostring(port.id)
      local widget = runtimeWidgets[patchbayPrefix .. ".patchbayContent.inputsColumn." .. rowId .. "." .. rowId .. "_port"]
      bindWirePortWidget(ctx, widget, {
        key = table.concat({ specId, shellId, "input", tostring(port.id) }, ":"),
        nodeId = specId,
        shellId = shellId,
        portId = tostring(port.id),
        direction = "input",
        portType = tostring(port.type or "control"),
        label = port.label or port.id,
        group = "io",
      })
    end
  end

  local outputs = (spec.ports or {}).outputs or {}
  for _, port in ipairs(outputs) do
    if port.edge == nil then
      local rowId = "output_" .. tostring(port.id)
      local widget = runtimeWidgets[patchbayPrefix .. ".patchbayContent.outputsColumn." .. rowId .. "." .. rowId .. "_port"]
      bindWirePortWidget(ctx, widget, {
        key = table.concat({ specId, shellId, "output", tostring(port.id) }, ":"),
        nodeId = specId,
        shellId = shellId,
        portId = tostring(port.id),
        direction = "output",
        portType = tostring(port.type or "audio"),
        label = port.label or port.id,
        group = "io",
      })
    end
  end

  for i, param in ipairs(currentParams) do
    if param then
      local paramId = tostring(param.id or i)
      local paramKey = "param_" .. paramId .. "_p" .. currentPage

      local sliderSearchPaths = {
        -- Single-column layout
        patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_val",
        -- Multi-column layout (left)
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_val",
        -- Multi-column layout (right)
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_val",
      }

      local sliderWidget = findFirstWidget(sliderSearchPaths)

      local inputPortWidget = nil
      if param.input ~= false then
        inputPortWidget = findFirstWidget({
          patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_in",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_in",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_in",
        })
      end

      local outputPortWidget = nil
      if param.output ~= false then
        outputPortWidget = findFirstWidget({
          patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_out",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_out",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_out",
        })
      end

      bindWirePortWidget(ctx, inputPortWidget, {
        key = table.concat({ specId, shellId, "input", paramId }, ":"),
        nodeId = specId,
        shellId = shellId,
        portId = paramId,
        direction = "input",
        portType = "control",
        label = param.label or paramId,
        group = "param",
        page = currentPage,
      })

      bindWirePortWidget(ctx, outputPortWidget, {
        key = table.concat({ specId, shellId, "output", paramId }, ":"),
        nodeId = specId,
        shellId = shellId,
        portId = paramId,
        direction = "output",
        portType = "control",
        label = param.label or paramId,
        group = "param",
        page = currentPage,
      })

      if sliderWidget and param.path then
        local dspPath = param.path
        local scale = param.scale
        local pmin = param.min or 0
        local pmax = param.max or 1
        local displayRange = pmax - pmin

        sliderWidget._onChange = function(v)
          local dspVal = v
          if scale and displayRange > 0 then
            local dspMin = scale.dspMin or 0
            local dspMax = scale.dspMax or 1
            local dspRange = dspMax - dspMin
            dspVal = ((v - pmin) / displayRange) * dspRange + dspMin
          end

          if dspPath == PATHS.sampleLoopStart then
            setSampleLoopStartLinked(dspVal)
          elseif dspPath == PATHS.sampleLoopLen then
            setSampleLoopLenLinked(dspVal)
          elseif dspPath == PATHS.blendAmount then
            setPath(dspPath, dspVal)
            syncLegacyBlendDirectionFromBlend(dspVal)
          else
            setPath(dspPath, dspVal)
          end
        end

        local dspVal = readParam(dspPath, param.default or 0)
        local displayVal = dspVal
        if scale and displayRange > 0 then
          local dspMin = scale.dspMin or 0
          local dspMax = scale.dspMax or 1
          local dspRange = dspMax - dspMin
          if dspRange > 0 then
            displayVal = ((dspVal - dspMin) / dspRange) * displayRange + pmin
          end
        end

        if sliderWidget.setValue then
          setWidgetValueSilently(sliderWidget, tonumber(displayVal) or param.default or 0)
        end
        sliderWidgets[param.id] = { widget = sliderWidget, path = dspPath, param = param }
        boundCount = boundCount + 1
      end
    end
  end

  -- Wire up pagination dot click handlers (same pattern as keyboard dots)
  local numPages = patchbaySpec.props and patchbaySpec.props._numPages or 1
  if numPages > 1 then
    for pageIdx = 0, numPages - 1 do
      local dotPath = patchbayPrefix .. ".patchbayContent.paramsColumn.paramsHeaderRow.pageDots.pageDots_dot" .. (pageIdx + 1)
      local dotWidget = runtimeWidgets[dotPath]
      if dotWidget and dotWidget.node and dotWidget.node.setOnClick then
        dotWidget.node:setInterceptsMouse(true, true)
        local targetPage = pageIdx
        local targetShell = shellId
        dotWidget.node:setOnClick(function()
          onPatchbayPageClick(ctx, targetShell, targetPage)
        end)
      end
    end
  end

  local instance = {
    widget = widget,
    record = record,
    sliders = sliderWidgets,
    specId = specId,
    currentPage = currentPage,
    nodeSize = nodeSize,
    numPages = numPages,
  }
  patchbayInstances[shellId] = instance
  if RackWireLayer and RackWireLayer.refreshWires then
    RackWireLayer.refreshWires(ctx)
  end
  return instance
end

-- Handle pagination dot click in patchbay
-- Called when user clicks a page indicator dot
onPatchbayPageClick = function(ctx, shellId, pageIndex)
  if not shellId then return end

  local instance = patchbayInstances[shellId]
  if instance and instance.numPages and instance.numPages > 1 then
    ctx._pendingPatchbayPages = ctx._pendingPatchbayPages or {}
    ctx._pendingPatchbayPages[shellId] = pageIndex
  end
end

-- Sync patchbay slider values from live DSP state (called in update loop)
-- Converts DSP values to display values using param.scale if present
local function syncPatchbayValues(ctx)
  for shellId, instance in pairs(patchbayInstances) do
    if instance and instance.sliders then
      for paramId, entry in pairs(instance.sliders) do
        local widget = entry.widget
        local path = entry.path
        local param = entry.param
        if widget and path and widget.setValue and not widget._dragging then
          local dspVal = readParam(path, param.default or 0)
          
          -- Convert DSP value to display value if scaling is defined
          local displayVal = dspVal
          local scale = param.scale
          if scale then
            local pmin = param.min or 0
            local pmax = param.max or 1
            local displayRange = pmax - pmin
            local dspMin = scale.dspMin or 0
            local dspMax = scale.dspMax or 1
            local dspRange = dspMax - dspMin
            if displayRange > 0 and dspRange > 0 then
              displayVal = ((dspVal - dspMin) / dspRange) * displayRange + pmin
            end
          end
          
          local current = widget.getValue and widget:getValue() or nil
          local threshold = 0.0001
          if current == nil or math.abs((tonumber(current) or 0) - (tonumber(displayVal) or 0)) > threshold then
            setWidgetValueSilently(widget, displayVal)
            if widget.node and widget.node.repaint then widget.node:repaint() end
          end
        end
      end
    end
  end
end

syncPatchViewMode = function(ctx)
  local rackState = ctx._rackState
  if not rackState then return end

  -- Do NOT clear the shell's global deferred refresh queue here.
  -- That was a fucking stupid hammer: it fixes patchbay bootstrap, but it also
  -- cancels unrelated retained updates (header/top-bar buttons, labels, etc.)
  -- during project load. Patchbay teardown already clears deferred refreshes in
  -- the targeted cleanup path where it's actually needed.
  local isPatch = (rackState.viewMode or "perf") == "patch"
  local shellIds = { "adsrShell", "oscillatorShell", "filterShell", "fx1Shell", "fx2Shell", "eqShell", "placeholder1Shell", "placeholder2Shell", "placeholder3Shell" }

  -- Map shell IDs to node specs
  local shellToSpecId = {
    adsrShell = "adsr",
    oscillatorShell = "oscillator",
    filterShell = "filter",
    fx1Shell = "fx1",
    fx2Shell = "fx2",
    eqShell = "eq",
  }

  for _, shellId in ipairs(shellIds) do
    local shell = getScopedWidget(ctx, "." .. shellId)
    if shell then
      -- Hide content components in patch view
      local content = getScopedWidget(ctx, "." .. shellId .. "Content")
      if content and content.setVisible then
        content:setVisible(not isPatch)
      end
      local compId = shellId:gsub("Shell", "Component")
      local comp = getScopedWidget(ctx, "." .. shellId .. "." .. compId)
      if comp and comp.setVisible then
        comp:setVisible(not isPatch)
      end
      local contentPanels = { "envelopeComponent", "oscillatorComponent", "filterComponent", "fx1Component", "fx2Component", "eqComponent", "placeholder1Content", "placeholder2Content", "placeholder3Content" }
      for _, panelId in ipairs(contentPanels) do
        local panel = getScopedWidget(ctx, "." .. shellId .. "." .. panelId)
        if panel and panel.setVisible then
          panel:setVisible(not isPatch)
          break
        end
      end

      -- Show patchbay panel in patch view, hide in perf view
      local patchbayPanel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
      if patchbayPanel and patchbayPanel.node then
        patchbayPanel.node:setVisible(isPatch)
      end

      -- Ensure patchbay widgets are instantiated on first switch to patch mode
      if isPatch then
        local specId = shellToSpecId[shellId]
        if specId then
          ensurePatchbayWidgets(ctx, shellId, specId)
        end
      end
    end
  end

  syncRackEdgeTerminals(ctx)

  -- Refresh wire layer
  if RackWireLayer then
    RackWireLayer.refreshWires(ctx)
  end
end

local function findRegisteredPatchbayPort(ctx, nodeId, portId, direction)
  local registry = ctx and ctx._patchbayPortRegistry or nil
  if type(registry) ~= "table" then
    return nil
  end
  for _, entry in pairs(registry) do
    if type(entry) == "table"
      and entry.nodeId == nodeId
      and entry.portId == portId
      and entry.direction == direction
      and entry.widget ~= nil then
      return entry
    end
  end
  return nil
end

local function setWidgetVisibleState(widget, visible)
  if widget == nil then
    return
  end
  if widget.setVisible then
    widget:setVisible(visible)
  elseif widget.node and widget.node.setVisible then
    widget.node:setVisible(visible)
  end
end

syncRackEdgeTerminals = function(ctx)
  local isPatch = (ctx and ctx._rackState and ctx._rackState.viewMode or "perf") == "patch"
  local rackContainer = getScopedWidget(ctx, ".rackContainer")
  local rackBounds = getWidgetBoundsInRoot(ctx, rackContainer)

  local rails = {
    { suffix = ".rackContainer.rightRailSend1", nodeId = "filter", portId = "out", direction = "output", side = "right", x = 1232 },
    { suffix = ".rackContainer.leftRailRecv2", nodeId = "fx1", portId = "in", direction = "input", side = "left", x = 6 },
    { suffix = ".rackContainer.rightRailSend2", nodeId = "eq", portId = "out", direction = "output", side = "right", x = 1232 },
    { suffix = ".rackContainer.leftRailRecv3", nodeId = "placeholder1", portId = "in", direction = "input", side = "left", x = 6 },
    { suffix = ".rackContainer.rightRailSend3", nodeId = "placeholder3", portId = "out", direction = "output", side = "right", x = 1232 },
  }

  for _, rail in ipairs(rails) do
    local railWidget = getScopedWidget(ctx, rail.suffix)
    local anchor = isPatch and findRegisteredPatchbayPort(ctx, rail.nodeId, rail.portId, rail.direction) or nil
    local anchorBounds = anchor and getWidgetBoundsInRoot(ctx, anchor.widget) or nil
    local visible = isPatch and rackBounds ~= nil and anchorBounds ~= nil
    setWidgetVisibleState(railWidget, visible)

    if visible and railWidget and railWidget.node and railWidget.node.setBounds then
      local localX = tonumber(rail.x) or 6
      local localY = (anchorBounds.y - rackBounds.y) + math.floor((anchorBounds.h - 14) * 0.5)
      railWidget.node:setBounds(round(localX), round(localY), 14, 14)
    end
  end
end

local function isUtilityDockVisible(ctx)
  local dock = ensureUtilityDockState(ctx)
  return dock.visible ~= false and dock.mode ~= "hidden"
end

local function syncKeyboardCollapsedFromUtilityDock(ctx)
  local dock = ensureUtilityDockState(ctx)
  ctx._keyboardCollapsed = dock.heightMode == "collapsed"
end

local function syncUtilityDockFromKeyboardCollapsed(ctx)
  local dock = ensureUtilityDockState(ctx)
  dock.visible = true
  if dock.mode == "hidden" then
    dock.mode = "keyboard"
  end
  -- When uncollapsing, restore previous mode instead of defaulting to full
  if ctx._keyboardCollapsed then
    dock.heightMode = "collapsed"
  else
    local mode = ctx._dockMode or "compact_collapsed"
    if mode == "compact_split" then
      dock.heightMode = "full"
      dock.layoutMode = "split"
    elseif mode == "compact_collapsed" then
      dock.heightMode = "compact"
      dock.layoutMode = "single"
    else
      dock.heightMode = "full"
      dock.layoutMode = "single"
    end
  end
  dock.primary = dock.primary or { kind = "keyboard", variant = "full" }
  dock.primary.kind = "keyboard"
  dock.primary.variant = (dock.heightMode == "compact" or dock.layoutMode == "split") and "compact" or "full"
end

local function utilityDockPresentationMode(ctx)
  return ctx._dockMode or "compact_collapsed"
end

local function syncDockModeDots(ctx)
  local mode = ctx._dockMode or "compact_collapsed"
  local dots = ctx._dockDots
  if not dots then return end
  for _, entry in ipairs(dots) do
    local color = (entry.mode == mode) and 0xffffffff or 0xff475569
    if entry.widget and entry.widget._colour ~= color then
      entry.widget._colour = color
      if entry.widget._syncRetained then entry.widget:_syncRetained() end
      if entry.widget.node and entry.widget.node.repaint then entry.widget.node:repaint() end
    end
  end
end

local function syncKeyboardCollapseButton(ctx)
  local widgets = ctx.widgets or {}
  if widgets.keyboardCollapse and widgets.keyboardCollapse.setLabel then
    widgets.keyboardCollapse:setLabel(ctx._keyboardCollapsed and "▶" or "▼")
    repaint(widgets.keyboardCollapse)
  end
  syncDockModeDots(ctx)
end

local function setUtilityDockMode(ctx, modeKey)
  local dock = ensureUtilityDockState(ctx)
  dock.visible = true
  dock.mode = "keyboard"
  dock.primary = dock.primary or { kind = "keyboard", variant = "full" }
  dock.primary.kind = "keyboard"

  if modeKey == "compact_split" then
    dock.heightMode = "full"
    dock.layoutMode = "split"
    dock.primary.variant = "compact"
    dock.secondary = dock.secondary or { kind = "utility", variant = "compact" }
  elseif modeKey == "compact_collapsed" or modeKey == "compact" then
    dock.heightMode = "compact"
    dock.layoutMode = "single"
    dock.primary.variant = "compact"
    dock.secondary = nil
  else
    dock.heightMode = "full"
    dock.layoutMode = "single"
    dock.primary.variant = "full"
    dock.secondary = nil
  end

  if ctx._rackState then
    ctx._rackState.utilityDock = dock
  end
  ctx._keyboardCollapsed = false
  ctx._dockMode = modeKey == "compact" and "compact_collapsed" or modeKey
  syncKeyboardCollapseButton(ctx)
  if ctx._lastW and ctx._lastH then
    refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
  end
end

local function computeKeyboardPanelHeight(ctx, totalH)
  local dock = ensureUtilityDockState(ctx)
  if not isUtilityDockVisible(ctx) then
    return 0
  end

  local h = math.max(0, tonumber(totalH) or 0)
  local topPad = 0
  local bottomPad = 0
  local gap = 0
  local captureH = 0
  local captureGap = 0
  local contentTop = topPad + captureH + captureGap
  local availableBelow = math.max(220, h - contentTop - bottomPad)
  local keyboardHeaderH = 44
  local keyboardExpandedH = math.max(148, availableBelow - math.max(180, math.floor(availableBelow * 0.45)) - gap - 6)
  local compactH = math.max(220, math.min(420, math.floor(keyboardExpandedH * 0.5)))

  if dock.heightMode == "collapsed" then
    return keyboardHeaderH
  end
  if dock.heightMode == "compact" or dock.mode == "compact_keyboard" then
    return compactH
  end
  return keyboardExpandedH
end

local function setMeasuredWidgetBounds(widget, width, height)
  if widget == nil then
    return false
  end

  local node = widget.node
  local currentX = 0
  local currentY = 0
  local currentW = 0
  local currentH = 0
  if node and node.getBounds then
    local bx, by, bw, bh = node:getBounds()
    currentX = tonumber(bx) or 0
    currentY = tonumber(by) or 0
    currentW = tonumber(bw) or 0
    currentH = tonumber(bh) or 0
  else
    if node and node.getWidth then
      currentW = tonumber(node:getWidth()) or 0
    end
    if node and node.getHeight then
      currentH = tonumber(node:getHeight()) or 0
    end
  end

  local nextW = math.max(1, round(width or currentW or 1))
  local nextH = math.max(1, round(height or currentH or 1))
  if currentW == nextW and currentH == nextH then
    return false
  end

  if widget.setBounds then
    widget:setBounds(currentX, currentY, nextW, nextH)
  elseif node and node.setBounds then
    node:setBounds(currentX, currentY, nextW, nextH)
  end
  return true
end

local function setWidgetBounds(widget, x, y, w, h)
  if widget == nil then
    return false
  end

  local nextX = round(x or 0)
  local nextY = round(y or 0)
  local nextW = math.max(1, round(w or 1))
  local nextH = math.max(1, round(h or 1))
  local currentX = 0
  local currentY = 0
  local currentW = 0
  local currentH = 0

  local node = widget.node
  if node and node.getBounds then
    local bx, by, bw, bh = node:getBounds()
    currentX = round(bx or 0)
    currentY = round(by or 0)
    currentW = round(bw or 0)
    currentH = round(bh or 0)
  end

  if currentX == nextX and currentY == nextY and currentW == nextW and currentH == nextH then
    return false
  end

  if widget.setBounds then
    widget:setBounds(nextX, nextY, nextW, nextH)
  elseif node and node.setBounds then
    node:setBounds(nextX, nextY, nextW, nextH)
  end
  return true
end

local function relayoutWidgetSubtree(widget, width, height)
  if widget == nil then
    return false
  end

  local runtime = widget._structuredRuntime
  local record = widget._structuredRecord
  if type(runtime) ~= "table" or type(runtime.notifyRecordHostedResized) ~= "function" or type(record) ~= "table" then
    return false
  end

  local ok = pcall(function()
    runtime:notifyRecordHostedResized(record, width, height)
  end)
  return ok == true
end

local function updateLayoutChild(widget, values)
  local record = widget and widget._structuredRecord or nil
  local spec = record and record.spec or nil
  if type(spec) ~= "table" then
    return false
  end

  local layoutChild = spec.layoutChild
  if type(layoutChild) ~= "table" then
    layoutChild = {}
    spec.layoutChild = layoutChild
  end

  local changed = false
  for key, value in pairs(values or {}) do
    local nextValue = value
    if type(value) == "number" then
      nextValue = round(value)
    end
    if layoutChild[key] ~= nextValue then
      layoutChild[key] = nextValue
      changed = true
    end
  end
  return changed
end

local function updateWidgetRectSpec(widget, x, y, w, h)
  local record = widget and widget._structuredRecord or nil
  local spec = record and record.spec or nil
  if type(spec) ~= "table" then
    return false
  end

  local changed = false
  local values = {
    x = round(x or 0),
    y = round(y or 0),
    w = math.max(1, round(w or 1)),
    h = math.max(1, round(h or 1)),
  }
  for key, value in pairs(values) do
    if spec[key] ~= value then
      spec[key] = value
      changed = true
    end
  end
  return changed
end

local CANONICAL_RACK_HEIGHT = 452
local RACK_SLOT_W = 236  -- 220 + 16px internal padding
local RACK_SLOT_H = 220
local RACK_ROW_GAP = 0
local RACK_ROW_PADDING_X = 0

RACK_SHELL_LAYOUT = {
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

local function computeProjectedRowWidths(nodes, rowBounds)
  local count = #nodes
  if count == 0 then
    return {}
  end

  -- Fixed sizes only: node.w * RACK_SLOT_W, no stretching
  local widths = {}
  for i = 1, count do
    local widthUnits = math.max(1, tonumber(nodes[i].w) or 1)
    widths[i] = widthUnits * RACK_SLOT_W
  end

  return widths
end

local function shouldShowRackRow3(ctx)
  local dock = ensureUtilityDockState(ctx)
  local heightMode = type(dock.heightMode) == "string" and dock.heightMode or "full"
  return heightMode == "collapsed" or heightMode == "compact"
end

local function syncRackShellLayout(ctx)
  local defaultRackState = MidiSynthRackSpecs.defaultRackState()
  local rackState = ctx._rackState or {
    viewMode = defaultRackState.viewMode,
    densityMode = defaultRackState.densityMode,
    utilityDock = defaultRackState.utilityDock,
    nodes = RackLayout.cloneNodes(defaultRackState.nodes),
  }
  if #(rackState.nodes or {}) == 0 then
    rackState.nodes = RackLayout.cloneNodes(defaultRackState.nodes)
  end
  ctx._rackState = rackState
  ctx._utilityDock = rackState.utilityDock or ctx._utilityDock

  local rowBoundsByRow = {}
  for row = 0, 2 do
    local rowWidget = getScopedWidget(ctx, ".rackRow" .. tostring(row + 1))
    rowBoundsByRow[row] = getWidgetBounds(rowWidget)
  end

  local layoutNodes = RackLayout.getFlowNodes(ctx._dragPreviewNodes or rackState.nodes or {})
  local rowBuckets = {}
  for i = 1, #layoutNodes do
    local node = layoutNodes[i]
    local row = math.max(0, tonumber(node.row) or 0)
    local bucket = rowBuckets[row]
    if not bucket then
      bucket = {}
      rowBuckets[row] = bucket
    end
    bucket[#bucket + 1] = node
  end

  local changed = false
  for row, bucket in pairs(rowBuckets) do
    local rowBounds = rowBoundsByRow[row]
    if rowBounds then
      local widths = computeProjectedRowWidths(bucket, rowBounds)
      local nextX = (tonumber(rowBounds.x) or 0) + RACK_ROW_PADDING_X
      local nextY = tonumber(rowBounds.y) or 0
      for i = 1, #bucket do
        local node = bucket[i]
        local shellMeta = node and RACK_SHELL_LAYOUT[node.id] or nil
        if shellMeta then
          local shellWidget = getScopedWidget(ctx, "." .. shellMeta.shellId)
          local width = widths[i] or (math.max(1, tonumber(node.w) or 1) * RACK_SLOT_W)
          local height = math.max(1, tonumber(node.h) or 1) * RACK_SLOT_H
          if shellWidget then
            changed = updateWidgetRectSpec(shellWidget, nextX, nextY, width, height) or changed
            changed = setWidgetBounds(shellWidget, nextX, nextY, width, height) or changed
            relayoutWidgetSubtree(shellWidget, width, height)
          end
          nextX = nextX + width + RACK_ROW_GAP
          local badge = getScopedWidget(ctx, shellMeta.badgeSuffix)
          local sizeText = type(node.sizeKey) == "string" and node.sizeKey ~= "" and node.sizeKey or string.format("%dx%d", math.max(1, tonumber(node.h) or 1), math.max(1, tonumber(node.w) or 1))
          syncText(badge, sizeText)
        end
      end
    end
  end

  return changed
end

refreshManagedLayoutState = function(ctx, w, h)
  local widgets = ctx.widgets or {}
  local mainStack = widgets.mainStack
  local contentRows = widgets.content_rows
  local topRow = widgets.top_row
  local bottomRow = widgets.bottom_row
  local keyboardPanel = widgets.keyboardPanel
  local keyboardBody = widgets.keyboardBody
  local utilitySplitArea = widgets.utilitySplitArea
  local keyboardHeader = widgets.keyboardHeader
  local keyboardCanvas = widgets.keyboardCanvas
  local dockModeDots = widgets.dockModeDots

  local totalW = tonumber(w) or tonumber(ctx._lastW)
  local totalH = tonumber(h) or tonumber(ctx._lastH)
  if (totalW == nil or totalH == nil) and ctx.root and ctx.root.node and ctx.root.node.getBounds then
    local _, _, bw, bh = ctx.root.node:getBounds()
    if totalW == nil then totalW = tonumber(bw) end
    if totalH == nil then totalH = tonumber(bh) end
  end
  if (totalW == nil or totalH == nil) and mainStack and mainStack.node and mainStack.node.getBounds then
    local _, _, bw, bh = mainStack.node:getBounds()
    if totalW == nil then totalW = tonumber(bw) end
    if totalH == nil then totalH = tonumber(bh) end
  end
  totalW = math.max(1, round(totalW or 0))
  totalH = math.max(1, round(totalH or 0))

  syncKeyboardCollapsedFromUtilityDock(ctx)
  syncKeyboardCollapseButton(ctx)

  local stackChanged = setWidgetBounds(mainStack, 0, 0, totalW, totalH)

  local dockVisible = isUtilityDockVisible(ctx)
  local dock = ensureUtilityDockState(ctx)
  local isCompactSplit = dock.layoutMode == "split" and dock.primary and dock.primary.kind == "keyboard" and dock.primary.variant == "compact"
  local bodyVisible = dockVisible and ctx._keyboardCollapsed ~= true
  local splitVisible = dockVisible and bodyVisible and isCompactSplit
  local bodyVisibilityChanged = false

  -- Row 3 backplate visibility follows dock state for visual clarity
  local rackRow3 = getScopedWidget(ctx, ".rackRow3")
  if rackRow3 and rackRow3.setVisible then
    local showRow3 = shouldShowRackRow3(ctx)
    local currentVisible = rackRow3.isVisible and rackRow3:isVisible() or false
    if currentVisible ~= showRow3 then
      rackRow3:setVisible(showRow3)
    end
  end

  -- Sync rack pagination to actual row visibility
  local rackRow1 = getScopedWidget(ctx, ".rackRow1")
  local rackRow2 = getScopedWidget(ctx, ".rackRow2") 
  local rackRow3 = getScopedWidget(ctx, ".rackRow3")
  
  local row1Visible = rackRow1 and rackRow1.isVisible and rackRow1:isVisible()
  local row2Visible = rackRow2 and rackRow2.isVisible and rackRow2:isVisible()
  local row3Visible = rackRow3 and rackRow3.isVisible and rackRow3:isVisible()
  
  local p = ensureRackPaginationState(ctx)
  if row3Visible then
    p.visibleRows = {1, 2, 3}
  elseif row1Visible and not row3Visible then
    p.visibleRows = {1, 2}
  elseif row2Visible and row3Visible then
    p.visibleRows = {2, 3}
  end
  updateRackPaginationDots(ctx)
  if keyboardPanel and keyboardPanel.setVisible then
    local currentVisible = true
    if keyboardPanel.isVisible then
      currentVisible = keyboardPanel:isVisible()
    end
    if currentVisible ~= dockVisible then
      keyboardPanel:setVisible(dockVisible)
      bodyVisibilityChanged = true
    end
  end
  if keyboardBody and keyboardBody.setVisible then
    local currentVisible = true
    if keyboardBody.isVisible then
      currentVisible = keyboardBody:isVisible()
    end
    if currentVisible ~= bodyVisible then
      keyboardBody:setVisible(bodyVisible)
      bodyVisibilityChanged = true
    end
  end
  if keyboardCanvas and keyboardCanvas.setVisible then
    local currentVisible = true
    if keyboardCanvas.isVisible then
      currentVisible = keyboardCanvas:isVisible()
    end
    if currentVisible ~= bodyVisible then
      keyboardCanvas:setVisible(bodyVisible)
      bodyVisibilityChanged = true
    end
  end
  if utilitySplitArea and utilitySplitArea.setVisible then
    local currentVisible = true
    if utilitySplitArea.isVisible then
      currentVisible = utilitySplitArea:isVisible()
    end
    if currentVisible ~= splitVisible then
      utilitySplitArea:setVisible(splitVisible)
      bodyVisibilityChanged = true
    end
  end

  local topPad = 0
  local bottomPad = 0
  local gap = 0
  local captureH = 0
  local captureGap = 0
  local contentTop = topPad + captureH + captureGap
  local availableBelow = math.max(220, totalH - contentTop - bottomPad)
  local keyboardH = computeKeyboardPanelHeight(ctx, totalH)
  local contentH = math.max(CANONICAL_RACK_HEIGHT, availableBelow - keyboardH - gap)

  local rackChanged = syncRackShellLayout(ctx)
  syncRackEdgeTerminals(ctx)
  if rackChanged and RackWireLayer and RackWireLayer.refreshWires then
    local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
    if viewMode == "patch" then
      RackWireLayer.refreshWires(ctx)
    end
  end
  local sizingChanged = false
  sizingChanged = updateLayoutChild(topRow, {
    order = 1,
    grow = 0,
    shrink = 0,
    basisH = 220,
    minH = 220,
    maxH = 220,
  }) or sizingChanged
  sizingChanged = updateLayoutChild(bottomRow, {
    order = 2,
    grow = 0,
    shrink = 0,
    basisH = 220,
    minH = 220,
    maxH = 220,
  }) or sizingChanged
  -- Compute compact body height to match compact_collapsed mode sizing
  -- This mirrors the compactH calculation in computeKeyboardPanelHeight
  local keyboardHeaderH = 44
  local keyboardExpandedH = math.max(148, availableBelow - math.max(180, math.floor(availableBelow * 0.45)) - gap - 6)
  local compactPanelH = math.max(220, math.min(420, math.floor(keyboardExpandedH * 0.5)))
  local compactBodyH = compactPanelH - keyboardHeaderH
  sizingChanged = updateLayoutChild(utilitySplitArea, {
    order = splitVisible and 1 or 2,
    grow = 0,
    shrink = 1,
    basisH = splitVisible and 273 or 0,
    minH = splitVisible and 273 or 0,
    maxH = splitVisible and 273 or 0,
  }) or sizingChanged
  sizingChanged = updateLayoutChild(keyboardBody, {
    order = splitVisible and 2 or 1,
    grow = 1,
    shrink = 1,
    basisH = splitVisible and 0 or 120,
    minH = splitVisible and 0 or 80,
    maxH = nil,
  }) or sizingChanged
  sizingChanged = updateLayoutChild(keyboardHeader, {
    order = 3,
    grow = 0,
    shrink = 0,
    basisH = 42,
    minH = 42,
    maxH = 42,
  }) or sizingChanged
  sizingChanged = updateLayoutChild(contentRows, {
    order = 1,
    basisH = contentH,
    minH = contentH,
    maxH = contentH,
  }) or sizingChanged

  -- Rack container always has full height for all rows; viewport controls visibility
  local rackContainer = widgets.rackContainer or getScopedWidget(ctx, ".rackContainer")
  if rackContainer then
    local fullRackH = 684
    sizingChanged = updateLayoutChild(rackContainer, {
      basisH = fullRackH,
      minH = fullRackH,
      maxH = fullRackH,
    }) or sizingChanged
  end
  sizingChanged = updateLayoutChild(keyboardPanel, {
    order = 2,
    grow = 0,
    shrink = 0,
    basisH = keyboardH,
    minH = keyboardH,
    maxH = keyboardH,
  }) or sizingChanged

  if stackChanged or bodyVisibilityChanged or sizingChanged or rackChanged then
    relayoutWidgetSubtree(mainStack, totalW, totalH)
  end

  if dockModeDots and keyboardPanel and keyboardPanel.node and keyboardPanel.node.getBounds
      and keyboardBody and keyboardBody.node and keyboardBody.node.getBounds then
    local _, _, panelW, _ = keyboardPanel.node:getBounds()
    local bx, by, bw, bh = keyboardBody.node:getBounds()
    local dotsH = 46
    local dotsW = 12
    local bodyRight = (tonumber(bx) or 0) + (tonumber(bw) or 0)
    local rightPad = math.max(0, (tonumber(panelW) or 0) - bodyRight)
    local dotX = round(bodyRight + math.max(0, (rightPad - dotsW) * 0.5))
    local dotY = round(((tonumber(by) or 0) + (tonumber(bh) or 0)) - dotsH - 48)
    setWidgetBounds(dockModeDots, dotX, dotY, dotsW, dotsH)
  end

  syncDockModeDots(ctx)
  syncKeyboardDisplay(ctx)

  -- Position patchViewToggle flush right within content_rows
  if widgets.patchViewToggle and contentRows and contentRows.node then
    local _, _, rowsW, _ = contentRows.node:getBounds()
    local btnW = 60
    local btnH = 24
    local btnX = math.max(0, round((tonumber(rowsW) or 1280) - btnW - 1))-- 1px for border
    setWidgetBounds(widgets.patchViewToggle, btnX, 0, btnW, btnH)
  end
end

local function setKeyboardCollapsed(ctx, collapsed)
  ctx._keyboardCollapsed = collapsed == true
  syncUtilityDockFromKeyboardCollapsed(ctx)
  if ctx._rackState then
    ctx._rackState.utilityDock = ensureUtilityDockState(ctx)
  end
  syncKeyboardCollapseButton(ctx)
  if ctx._lastW and ctx._lastH then
    refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
  end
end

local function persistDockUiState(ctx)
  persistMidiInputSelection(ctx._selectedMidiInputIdx and ctx._selectedMidiInputIdx > 1 and ctx._selectedMidiInputLabel or "")
  local state = loadRuntimeState()
  local dock = ensureUtilityDockState(ctx)
  state.keyboardCollapsed = ctx._keyboardCollapsed == true
  state.utilityDockVisible = dock.visible ~= false
  state.utilityDockMode = dock.mode or "keyboard"
  state.utilityDockHeightMode = dock.heightMode or (ctx._keyboardCollapsed and "collapsed" or "full")
  saveRuntimeState(state)
end

local function saveCurrentState(ctx)
  local dock = ensureUtilityDockState(ctx)
  local defaultRackState = MidiSynthRackSpecs.defaultRackState()
  local rackState = ctx._rackState or {
    viewMode = defaultRackState.viewMode,
    densityMode = defaultRackState.densityMode,
    utilityDock = dock,
    nodes = RackLayout.cloneNodes(defaultRackState.nodes),
  }
  if #(rackState.nodes or {}) == 0 then
    rackState.nodes = RackLayout.cloneNodes(defaultRackState.nodes)
  end
  rackState.utilityDock = {visible=true,mode="keyboard",heightMode="full",layoutMode="single",primary={kind="keyboard",variant="full"}}
  local state = {
    inputDevice = ctx._selectedMidiInputLabel or "",
    keyboardCollapsed = ctx._keyboardCollapsed == true,
    utilityDockVisible = dock.visible ~= false,
    utilityDockMode = dock.mode or "full_keyboard",
    utilityDockHeightMode = dock.heightMode or (ctx._keyboardCollapsed and "collapsed" or "full"),
    rackViewMode = rackState.viewMode,
    rackDensityMode = rackState.densityMode,
    rackNodes = RackLayout.cloneNodes(rackState.nodes),
    rackState = rackState,
    waveform = round(readParam(PATHS.waveform, 1)),
    filterType = round(readParam(PATHS.filterType, 0)),
    cutoff = readParam(PATHS.cutoff, 3200),
    resonance = readParam(PATHS.resonance, 0.75),
    drive = readParam(PATHS.drive, 0.0),
    driveShape = round(readParam(PATHS.driveShape, 0)),
    driveBias = readParam(PATHS.driveBias, 0.0),
    output = readParam(PATHS.output, 0.8),
    attack = readParam(PATHS.attack, 0.05),
    decay = readParam(PATHS.decay, 0.2),
    sustain = readParam(PATHS.sustain, 0.7),
    release = readParam(PATHS.release, 0.4),
    fx1Type = round(readParam(PATHS.fx1Type, 0)),
    fx1Mix = readParam(PATHS.fx1Mix, 0.0),
    fx2Type = round(readParam(PATHS.fx2Type, 0)),
    fx2Mix = readParam(PATHS.fx2Mix, 0.0),
    oscMode = round(readParam(PATHS.oscMode, 0)),
    sampleSource = round(readParam(PATHS.sampleSource, 0)),
    sampleCaptureBars = readParam(PATHS.sampleCaptureBars, 1.0),
    samplePitchMapEnabled = (readParam(PATHS.samplePitchMapEnabled, 0.0) or 0.0) > 0.5,
    sampleRootNote = readParam(PATHS.sampleRootNote, 60.0),
    samplePlayStart = readParam(PATHS.samplePlayStart, 0.0),
    sampleLoopStart = readParam(PATHS.sampleLoopStart, 0.0),
    sampleLoopLen = readParam(PATHS.sampleLoopLen, 1.0),
    sampleRetrigger = round(readParam(PATHS.sampleRetrigger, 1)),
    blendMode = round(readParam(PATHS.blendMode, 0)),
    blendAmount = readParam(PATHS.blendAmount, 0.5),
    waveToSample = readParam(PATHS.waveToSample, 0.5),
    sampleToWave = readParam(PATHS.sampleToWave, 0.0),
    blendKeyTrack = round(readParam(PATHS.blendKeyTrack, 2)),
    blendSamplePitch = readParam(PATHS.blendSamplePitch, 0.0),
    blendModAmount = readParam(PATHS.blendModAmount, 0.5),
    addFlavor = round(readParam(PATHS.addFlavor, 0)),
    xorBehavior = round(readParam(PATHS.xorBehavior, 0)),
    delayMix = readParam(PATHS.delayMix, 0.0),
    delayTime = round(readParam(PATHS.delayTimeL, 220)),
    delayFeedback = readParam(PATHS.delayFeedback, 0.24),
    reverbWet = readParam(PATHS.reverbWet, 0.0),
    eqOutput = readParam(PATHS.eqOutput, 0.0),
    eqMix = readParam(PATHS.eqMix, 1.0),
    -- New oscillator parameters
    pulseWidth = readParam(PATHS.pulseWidth, 0.5),
    unison = round(readParam(PATHS.unison, 1)),
    detune = readParam(PATHS.detune, 0.0),
    spread = readParam(PATHS.spread, 0.0),
    oscRenderMode = round(readParam(PATHS.oscRenderMode, 0)),
    additivePartials = round(readParam(PATHS.additivePartials, 8)),
    additiveTilt = readParam(PATHS.additiveTilt, 0.0),
    additiveDrift = readParam(PATHS.additiveDrift, 0.0),
  }
  for i = 1, 8 do
    state["eqBandEnabled" .. i] = round(readParam(eq8BandEnabledPath(i), 0))
    state["eqBandType" .. i] = round(readParam(eq8BandTypePath(i), i == 1 and 1 or (i == 8 and 2 or 0)))
    state["eqBandFreq" .. i] = readParam(eq8BandFreqPath(i), ({60, 120, 250, 500, 1000, 2500, 6000, 12000})[i])
    state["eqBandGain" .. i] = readParam(eq8BandGainPath(i), 0.0)
    state["eqBandQ" .. i] = readParam(eq8BandQPath(i), (i == 1 or i == 8) and 0.8 or 1.0)
  end
  
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

  local defaultRackState = MidiSynthRackSpecs.defaultRackState()
  local restoredRackState = nil
  
  -- First try to use rackState.nodes if it exists and has content
  if state.rackState and type(state.rackState) == "table" then
    local rs = state.rackState
    if rs.nodes and #rs.nodes > 0 then
      restoredRackState = {
        viewMode = rs.viewMode or state.rackViewMode or defaultRackState.viewMode,
        densityMode = rs.densityMode or state.rackDensityMode or defaultRackState.densityMode,
        utilityDock = rs.utilityDock or {
          visible = state.utilityDockVisible,
          mode = state.utilityDockMode,
          heightMode = state.utilityDockHeightMode,
        },
        nodes = RackLayout.cloneNodes(rs.nodes),
      }
    end
  end
  
  -- Fall back to rackNodes if no valid rackState.nodes
  if not restoredRackState then
    local rackNodes = state.rackNodes
    if rackNodes and #rackNodes > 0 then
      restoredRackState = {
        viewMode = state.rackViewMode or defaultRackState.viewMode,
        densityMode = state.rackDensityMode or defaultRackState.densityMode,
        utilityDock = {
          visible = state.utilityDockVisible,
          mode = state.utilityDockMode,
          heightMode = state.utilityDockHeightMode,
        },
        nodes = RackLayout.cloneNodes(rackNodes),
      }
    end
  end
  
  -- Final fallback to defaults
  if not restoredRackState then
    restoredRackState = {
      viewMode = state.rackViewMode or defaultRackState.viewMode,
      densityMode = state.rackDensityMode or defaultRackState.densityMode,
      utilityDock = {
        visible = state.utilityDockVisible,
        mode = state.utilityDockMode,
        heightMode = state.utilityDockHeightMode,
      },
      nodes = RackLayout.cloneNodes(defaultRackState.nodes),
    }
  end
  ctx._rackState = restoredRackState
  ctx._rackNodeSpecs = ctx._rackNodeSpecs or MidiSynthRackSpecs.nodeSpecById()
  ctx._rackConnections = ctx._rackConnections or MidiSynthRackSpecs.defaultConnections()
  ctx._utilityDock = restoredRackState.utilityDock
  _G.__midiSynthRackState = ctx._rackState
  _G.__midiSynthRackNodeSpecs = ctx._rackNodeSpecs
  _G.__midiSynthRackConnections = ctx._rackConnections
  _G.__midiSynthUtilityDock = ctx._utilityDock

  local dock = ensureUtilityDockState(ctx)
  local hasExplicitDockState = false
  if state.utilityDockVisible ~= nil then
    dock.visible = state.utilityDockVisible == true
    hasExplicitDockState = true
  end
  if type(state.utilityDockMode) == "string" and state.utilityDockMode ~= "" then
    dock.mode = state.utilityDockMode
    hasExplicitDockState = true
  end
  if type(state.utilityDockHeightMode) == "string" and state.utilityDockHeightMode ~= "" then
    dock.heightMode = state.utilityDockHeightMode
    hasExplicitDockState = true
  elseif state.keyboardCollapsed ~= nil then
    dock.heightMode = state.keyboardCollapsed == true and "collapsed" or "full"
  end
  syncKeyboardCollapsedFromUtilityDock(ctx)

  -- If the current UI does not expose an explicit dock-mode selector yet,
  -- do not leave the user stranded in a persisted compact mode from a prior
  -- experimental build. Preserve collapsed/full via the visible toggle.
  if not ((ctx.widgets or {}).dockModeTabs or (ctx.widgets or {}).dockModeDots) then
    if dock.heightMode == "compact" then
      dock.heightMode = "full"
      if dock.primary and dock.primary.kind == "keyboard" then
        dock.primary.variant = "full"
      end
      ctx._utilityDock = {visible=true,mode="keyboard",heightMode="full",layoutMode="single",primary={kind="keyboard",variant="full"}}
      if ctx._rackState then
        ctx._rackState.utilityDock = ctx._utilityDock
      end
      _G.__midiSynthUtilityDock = ctx._utilityDock
      _G.__midiSynthRackState = ctx._rackState
    end
  end

  if state.keyboardCollapsed ~= nil and not hasExplicitDockState then
    setKeyboardCollapsed(ctx, state.keyboardCollapsed == true)
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
  if state.eqOutput ~= nil then
    setPath(PATHS.eqOutput, state.eqOutput)
  end
  if state.eqMix ~= nil then
    setPath(PATHS.eqMix, state.eqMix)
  end
  for i = 1, 8 do
    if state["eqBandEnabled" .. i] ~= nil then setPath(eq8BandEnabledPath(i), state["eqBandEnabled" .. i]) end
    if state["eqBandType" .. i] ~= nil then setPath(eq8BandTypePath(i), state["eqBandType" .. i]) end
    if state["eqBandFreq" .. i] ~= nil then setPath(eq8BandFreqPath(i), state["eqBandFreq" .. i]) end
    if state["eqBandGain" .. i] ~= nil then setPath(eq8BandGainPath(i), state["eqBandGain" .. i]) end
    if state["eqBandQ" .. i] ~= nil then setPath(eq8BandQPath(i), state["eqBandQ" .. i]) end
  end
  if state.filterType then
    setPath(PATHS.filterType, state.filterType)
  end
  if state.fx1Type then setPath(PATHS.fx1Type, state.fx1Type) end
  if state.fx1Mix then setPath(PATHS.fx1Mix, state.fx1Mix) end
  if state.fx2Type then setPath(PATHS.fx2Type, state.fx2Type) end
  if state.fx2Mix then setPath(PATHS.fx2Mix, state.fx2Mix) end
  if state.oscMode ~= nil then setPath(PATHS.oscMode, state.oscMode) end
  if state.sampleSource ~= nil then setPath(PATHS.sampleSource, state.sampleSource) end
  if state.sampleCaptureBars ~= nil then setPath(PATHS.sampleCaptureBars, state.sampleCaptureBars) end
  if state.samplePitchMapEnabled ~= nil then setPath(PATHS.samplePitchMapEnabled, state.samplePitchMapEnabled and 1 or 0) end
  if state.sampleRootNote ~= nil then setPath(PATHS.sampleRootNote, state.sampleRootNote) end
  if state.samplePlayStart ~= nil then setPath(PATHS.samplePlayStart, state.samplePlayStart) end
  if state.sampleLoopStart ~= nil then setPath(PATHS.sampleLoopStart, state.sampleLoopStart) end
  if state.sampleLoopLen ~= nil then setPath(PATHS.sampleLoopLen, state.sampleLoopLen) end
  if state.sampleRetrigger ~= nil then setPath(PATHS.sampleRetrigger, state.sampleRetrigger) end
  if state.blendMode ~= nil then setPath(PATHS.blendMode, state.blendMode) end
  if state.blendAmount ~= nil then setPath(PATHS.blendAmount, state.blendAmount) end
  if state.waveToSample ~= nil then setPath(PATHS.waveToSample, state.waveToSample) end
  if state.sampleToWave ~= nil then setPath(PATHS.sampleToWave, state.sampleToWave) end
  if state.blendKeyTrack ~= nil then setPath(PATHS.blendKeyTrack, state.blendKeyTrack) end
  if state.blendSamplePitch ~= nil then setPath(PATHS.blendSamplePitch, state.blendSamplePitch) end
  if state.blendModAmount ~= nil then setPath(PATHS.blendModAmount, state.blendModAmount) end
  if state.addFlavor ~= nil then setPath(PATHS.addFlavor, state.addFlavor) end
  if state.xorBehavior ~= nil then setPath(PATHS.xorBehavior, state.xorBehavior) end
  -- New oscillator parameters
  if state.pulseWidth ~= nil then setPath(PATHS.pulseWidth, state.pulseWidth) end
  if state.unison ~= nil then setPath(PATHS.unison, state.unison) end
  if state.detune ~= nil then setPath(PATHS.detune, state.detune) end
  if state.spread ~= nil then setPath(PATHS.spread, state.spread) end
  if state.oscRenderMode ~= nil then setPath(PATHS.oscRenderMode, state.oscRenderMode) end
  if state.additivePartials ~= nil then setPath(PATHS.additivePartials, state.additivePartials) end
  if state.additiveTilt ~= nil then setPath(PATHS.additiveTilt, state.additiveTilt) end
  if state.additiveDrift ~= nil then setPath(PATHS.additiveDrift, state.additiveDrift) end
  if state.driveShape ~= nil then setPath(PATHS.driveShape, state.driveShape) end
  if state.driveBias ~= nil then setPath(PATHS.driveBias, state.driveBias) end

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
  setPath(PATHS.drive, 0.0)
  setPath(PATHS.output, 0.8)
  setPath(PATHS.attack, 0.05)
  setPath(PATHS.decay, 0.2)
  setPath(PATHS.sustain, 0.7)
  setPath(PATHS.release, 0.4)
  setPath(PATHS.fx1Type, 0)
  setPath(PATHS.fx1Mix, 0.0)
  setPath(PATHS.fx2Type, 0)
  setPath(PATHS.fx2Mix, 0.0)
  setPath(PATHS.oscMode, 0)
  setPath(PATHS.sampleSource, 0)
  setPath(PATHS.sampleCaptureBars, 1.0)
  setPath(PATHS.samplePitchMapEnabled, 0.0)
  setPath(PATHS.sampleRootNote, 60.0)
  setPath(PATHS.samplePlayStart, 0.0)
  setPath(PATHS.sampleLoopStart, 0.0)
  setPath(PATHS.sampleLoopLen, 1.0)
  setPath(PATHS.sampleRetrigger, 1.0)
  setPath(PATHS.blendMode, 0)
  setPath(PATHS.blendAmount, 0.5)
  setPath(PATHS.waveToSample, 0.5)
  setPath(PATHS.sampleToWave, 0.0)
  setPath(PATHS.blendKeyTrack, 2.0)
  setPath(PATHS.blendSamplePitch, 0.0)
  setPath(PATHS.blendModAmount, 0.5)
  setPath(PATHS.addFlavor, 0.0)
  setPath(PATHS.xorBehavior, 0.0)
  for i = 0, MAX_FX_PARAMS - 1 do
    setPath(fxParamPath(1, i + 1), 0.5)
    setPath(fxParamPath(2, i + 1), 0.5)
  end
  setPath(PATHS.delayMix, 0.0)
  setPath(PATHS.delayTimeL, 220)
  setPath(PATHS.delayTimeR, 330)
  setPath(PATHS.delayFeedback, 0.24)
  setPath(PATHS.reverbWet, 0.0)
  setPath(PATHS.eqOutput, 0.0)
  setPath(PATHS.eqMix, 1.0)
  -- New oscillator parameters
  setPath(PATHS.pulseWidth, 0.5)
  setPath(PATHS.unison, 1)
  setPath(PATHS.detune, 0.0)
  setPath(PATHS.spread, 0.0)
  setPath(PATHS.oscRenderMode, 0)
  setPath(PATHS.additivePartials, 8)
  setPath(PATHS.additiveTilt, 0.0)
  setPath(PATHS.additiveDrift, 0.0)
  setPath(PATHS.driveShape, 0)
  setPath(PATHS.driveBias, 0.0)
  for i = 1, 8 do
    setPath(eq8BandEnabledPath(i), 0)
    setPath(eq8BandTypePath(i), i == 1 and 1 or (i == 8 and 2 or 0))
    setPath(eq8BandFreqPath(i), ({60, 120, 250, 500, 1000, 2500, 6000, 12000})[i])
    setPath(eq8BandGainPath(i), 0.0)
    setPath(eq8BandQPath(i), (i == 1 or i == 8) and 0.8 or 1.0)
  end
  
  ctx._adsr = { attack = 0.05, decay = 0.2, sustain = 0.7, release = 0.4 }
  ctx._keyboardOctave = 3
  setKeyboardCollapsed(ctx, false)
  ctx._lastEvent = "Reset to defaults"
end

local KEYBOARD_WHITE_KEYS = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23 }
local KEYBOARD_BLACK_KEYS = { 1, 3, 6, 8, 10, 13, 15, 18, 20, 22 }
local KEYBOARD_BLACK_KEY_POSITIONS = { 1, 2, 4, 5, 6, 8, 9, 11, 12, 13 }

local function isKeyboardNoteActive(ctx, note)
  for j = 1, VOICE_COUNT do
    local voice = ctx._voices[j]
    if voice and voice.active and voice.note == note and voice.gate > 0.5 then
      return true
    end
  end
  return false
end

local function buildKeyboardDisplayList(ctx, w, h)
  local display = {}
  if w <= 0 or h <= 0 then
    return display
  end

  local whiteKeyWidth = w / 14
  local blackKeyWidth = whiteKeyWidth * 0.6
  local baseNote = ctx._keyboardOctave * 12

  for i, offset in ipairs(KEYBOARD_WHITE_KEYS) do
    local note = baseNote + offset
    local x = (i - 1) * whiteKeyWidth
    local isActive = isKeyboardNoteActive(ctx, note)
    local keyX = math.floor(x + 2)
    local keyY = 2
    local keyW = math.max(1, math.floor(whiteKeyWidth - 4))
    local keyH = math.max(1, math.floor(h - 4))

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = keyX,
      y = keyY,
      w = keyW,
      h = keyH,
      radius = 4,
      color = isActive and 0xff4ade80 or 0xfff1f5f9,
    }
    display[#display + 1] = {
      cmd = "drawRoundedRect",
      x = keyX,
      y = keyY,
      w = keyW,
      h = keyH,
      radius = 4,
      thickness = 1,
      color = 0xff64748b,
    }
  end

  for i, offset in ipairs(KEYBOARD_BLACK_KEYS) do
    local note = baseNote + offset
    local pos = KEYBOARD_BLACK_KEY_POSITIONS[i]
    local x = pos * whiteKeyWidth - blackKeyWidth / 2
    local isActive = isKeyboardNoteActive(ctx, note)
    local keyX = math.floor(x)
    local keyY = 2
    local keyW = math.max(1, math.floor(blackKeyWidth))
    local keyH = math.max(1, math.floor(h * 0.6))

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = keyX,
      y = keyY,
      w = keyW,
      h = keyH,
      radius = 3,
      color = isActive and 0xff22d3ee or 0xff1e293b,
    }
    display[#display + 1] = {
      cmd = "drawRoundedRect",
      x = keyX,
      y = keyY,
      w = keyW,
      h = keyH,
      radius = 3,
      thickness = 1,
      color = 0xff0f172a,
    }
  end

  return display
end

syncKeyboardDisplay = function(ctx)
  local widgets = ctx.widgets or {}
  local canvas = widgets.keyboardCanvas
  if not (canvas and canvas.node and canvas.node.setDisplayList) then
    return
  end

  local w = canvas.node:getWidth()
  local h = canvas.node:getHeight()
  canvas.node:setDisplayList(buildKeyboardDisplayList(ctx, w, h))
  repaint(canvas)
end

local function handleKeyboardClick(ctx, x, y, isDown)
  local widgets = ctx.widgets or {}
  local canvas = widgets.keyboardCanvas
  if not canvas or not canvas.node then return end
  
  local w = canvas.node:getWidth()
  local h = canvas.node:getHeight()
  local whiteKeyWidth = w / 14
  local baseNote = ctx._keyboardOctave * 12
  
  local blackKeyWidth = whiteKeyWidth * 0.6
  local blackKeyHeight = h * 0.6
  local hitNote = nil

  -- Check black keys first (they're on top)
  if y <= blackKeyHeight then
    for i, offset in ipairs(KEYBOARD_BLACK_KEYS) do
      local pos = KEYBOARD_BLACK_KEY_POSITIONS[i]
      local kx = pos * whiteKeyWidth - blackKeyWidth / 2
      if x >= kx and x <= kx + blackKeyWidth then
        hitNote = baseNote + offset
        break
      end
    end
  end

  -- Fall through to white keys if no black key hit
  if not hitNote then
    local keyIndex = math.floor(x / whiteKeyWidth) + 1
    if keyIndex >= 1 and keyIndex <= #KEYBOARD_WHITE_KEYS then
      hitNote = baseNote + KEYBOARD_WHITE_KEYS[keyIndex]
    end
  end

  if hitNote then
    if isDown then
      triggerVoice(ctx, hitNote, 100)
      ctx._keyboardNote = hitNote
      ctx._currentNote = hitNote
      ctx._lastEvent = string.format("Note: %s vel 100", noteName(hitNote))
    else
      releaseVoice(ctx, hitNote)
      if ctx._keyboardNote == hitNote then
        ctx._keyboardNote = nil
      end
      if ctx._currentNote == hitNote then
        ctx._currentNote = nil
      end
    end
  end
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

  if (ctx._fx1Ctx and ctx._fx1Ctx.dragging) or (ctx._fx2Ctx and ctx._fx2Ctx.dragging) then
    return true
  end

  return false
end

-- Background tick: MIDI polling + envelope processing.
-- Stored as a global so the root behavior can call it every frame,
-- even when the MidiSynth tab is not active.
local function backgroundTick(ctx)
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

  -- Update ADSR envelopes (drives voice amplitude via setParam)
  local attack = readParam(PATHS.attack, 0.05)
  local decay = readParam(PATHS.decay, 0.2)
  local sustain = readParam(PATHS.sustain, 0.7)
  local release = readParam(PATHS.release, 0.4)
  ctx._adsr.attack = attack
  ctx._adsr.decay = decay
  ctx._adsr.sustain = sustain
  ctx._adsr.release = release
  updateEnvelopes(ctx, dt, now)
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
  ctx._rackState = MidiSynthRackSpecs.defaultRackState()
  ctx._rackNodeSpecs = MidiSynthRackSpecs.nodeSpecById()
  ctx._rackConnections = MidiSynthRackSpecs.defaultConnections()
  ctx._utilityDock = ctx._rackState.utilityDock or RackLayout.defaultUtilityDock()
  ctx._keyboardCollapsed = false
  syncKeyboardCollapsedFromUtilityDock(ctx)
  _G.__midiSynthRackState = ctx._rackState
  _G.__midiSynthRackNodeSpecs = ctx._rackNodeSpecs
  _G.__midiSynthRackConnections = ctx._rackConnections
  _G.__midiSynthUtilityDock = ctx._utilityDock
  ctx._keyboardNote = nil
  ctx._keyboardDirty = true
  ctx._lastUpdateTime = getTime and getTime() or 0
  ctx._lastMidiDeviceScanTime = -1000
  ctx._lastKnownMidiDeviceCount = -1
  ctx._lastBackgroundTickTime = 0
  ctx._lastOscRepaintTime = 0
  ctx._lastEnvRepaintTime = 0
  
  -- Port specifications for signal routing visualization
  -- Loaded from component UI files
  ctx._portSpecs = {
    envelopeComponent = { outputs = {{ id = "cv_out", type = "cv", y = 0.5 }} },
    oscillatorComponent = { 
      inputs = {{ id = "cv_in", type = "cv", y = 0.35 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.65 }}
    },
    filterComponent = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    fx1Component = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    fx2Component = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    eqComponent = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }}
    },
  }
  
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
    }
  end
  
  if Midi and Midi.clearCallbacks then
    -- Don't clear callbacks here - we want MIDI to keep working globally
    -- Midi.clearCallbacks()
  end
  
  -- Wire up component behaviors via allWidgets + runtime.behaviors
  local all = ctx.allWidgets or {}
  ctx._globalPrefix = resolveGlobalPrefix(ctx)
  local rootId = ctx._globalPrefix
  local function scopedBehavior(suffix)
    return getScopedBehavior(ctx, suffix)
  end
  local function scopedWidget(suffix)
    return getScopedWidget(ctx, suffix)
  end

  -- Oscillator component → DSP
  local oscBehavior = scopedBehavior(".oscillatorComponent")
  local oscCtx = oscBehavior and oscBehavior.ctx or nil
  local oscModule = oscBehavior and oscBehavior.module or nil
  ctx._oscCtx = oscCtx
  ctx._oscModule = oscModule

  local oscWfDrop = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.waveform_dropdown")
  local oscRenderModeTabs = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.render_mode_tabs")
  local oscSampleSourceDrop = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_source_dropdown")
  local oscSamplePitchMapToggle = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_map_toggle")
  local oscSampleCaptureBtn = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_capture_button")
  local oscSampleBarsBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_bars_box")
  local oscSampleRootBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_root_box")
  local oscSampleXfadeBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_xfade_box")
  -- NOTE: range_view_dropdown disabled - only global view supported
  -- local oscRangeViewDrop = all[rootId .. ".oscillatorComponent.mode_tabs.sample_tab.range_view_dropdown"]

  -- Wire up range bar callbacks to DSP (after NumberBoxes are defined)
  if oscCtx then
    oscCtx._onRangeChange = function(which, value)
      if which == "start" then
        setPath(PATHS.sampleLoopStart, clamp(value, 0.0, 0.95))
      elseif which == "len" then
        setPath(PATHS.sampleLoopLen, clamp(value, 0.05, 1.0))
      end
    end
    oscCtx._onPlayStartChange = function(value)
      setPath(PATHS.samplePlayStart, clamp(value, 0.0, 0.99))
    end
    -- NOTE: _onVoiceRangeChange disabled - only global view supported
    -- oscCtx._onVoiceRangeChange = function(voiceIdx, which, value) ... end
  end

  local oscDriveModeDrop = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_mode_dropdown")
  local oscDrive = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_knob")
  local oscDriveBias = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_bias_knob")
  local oscAddPartials = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_partials_knob")
  local oscAddTilt = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_tilt_knob")
  local oscAddDrift = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_drift_knob")
  local oscOutput = scopedWidget(".oscillatorComponent.output_knob")
  -- New oscillator parameter knobs
  local oscPulseWidth = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.pulse_width_knob")
  local oscUnison = scopedWidget(".oscillatorComponent.unison_knob")
  local oscDetune = scopedWidget(".oscillatorComponent.detune_knob")
  local oscSpread = scopedWidget(".oscillatorComponent.spread_knob")
  local oscBlendModeDrop = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mode_dropdown")
  local oscBlendKeyTrackRadio = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_key_track_radio")
  local oscBlendAmount = scopedWidget(".oscillatorComponent.blend_amount_knob")
  local oscBlendSamplePitch = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob")
  local oscBlendModAmount = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob")
  local oscAddFlavorToggle = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle")
  local oscMorphCurve = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve")
  local oscMorphConvergence = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence")
  local oscMorphPhase = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase")
  local oscMorphSpeed = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed")
  local oscMorphContrast = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast")
  local oscMorphSmooth = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth")

  local function refreshOscGraph()
    if oscCtx and oscModule then oscModule.resized(oscCtx) end
  end

  if oscSampleSourceDrop and oscSampleSourceDrop.setOptions then
    oscSampleSourceDrop:setOptions(SAMPLE_SOURCE_OPTIONS)
  end
  if oscSampleRootBox and oscSampleRootBox.setValueFormatter then
    oscSampleRootBox:setValueFormatter(function(v)
      return formatMidiNoteValue(v)
    end)
  end
  if oscDriveModeDrop and oscDriveModeDrop.setOptions then
    oscDriveModeDrop:setOptions(DRIVE_SHAPE_OPTIONS)
  end
  if oscBlendModeDrop and oscBlendModeDrop.setOptions then
    oscBlendModeDrop:setOptions(BLEND_MODE_OPTIONS)
  end

  if oscWfDrop then oscWfDrop._onSelect = function(idx)
    setPath(PATHS.waveform, idx - 1)
    if oscCtx then
      oscCtx.waveformType = idx - 1
      refreshOscGraph()
      -- Update knob layout (show/hide Width knob for Pulse)
      if oscModule and oscModule.updateKnobLayout then
        oscModule.updateKnobLayout(oscCtx)
      end
    end
  end end
  if oscRenderModeTabs then oscRenderModeTabs._onSelect = function(idx)
    local mode = math.max(0, math.min(1, idx - 1))
    setPath(PATHS.oscRenderMode, mode)
    if oscCtx then
      oscCtx.renderMode = mode
      refreshOscGraph()
      if oscModule and oscModule.updateKnobLayout then
        oscModule.updateKnobLayout(oscCtx)
      end
    end
  end end
  if oscSampleSourceDrop then oscSampleSourceDrop._onSelect = function(idx)
    setPath(PATHS.sampleSource, idx - 1)
  end end
  if oscSamplePitchMapToggle then oscSamplePitchMapToggle._onChange = function(v)
    setPath(PATHS.samplePitchMapEnabled, v and 1 or 0)
  end end
  if oscSampleCaptureBtn then oscSampleCaptureBtn._onClick = function()
    print("Capture button clicked!")
    setPath(PATHS.sampleCaptureTrigger, 1)
    ctx._lastEvent = "Sample captured"
    if oscCtx then oscCtx._cachedPeaks = nil end
  end end
  if oscSampleBarsBox then oscSampleBarsBox._onChange = function(v)
    setPath(PATHS.sampleCaptureBars, v)
  end end
  if oscSampleRootBox then oscSampleRootBox._onChange = function(v)
    setPath(PATHS.sampleRootNote, round(v))
  end end
  if oscSampleXfadeBox then oscSampleXfadeBox._onChange = function(v)
    setPath(PATHS.sampleCrossfade, clamp(v / 100.0, 0.0, 0.5))
    if oscCtx then oscCtx.sampleCrossfade = clamp(v / 100.0, 0.0, 0.5); refreshOscGraph() end
  end end

  -- NOTE: Range view dropdown disabled - only global view supported
  --[[
  if oscRangeViewDrop then oscRangeViewDrop._onSelect = function(idx)
    ...
  end end
  --]]

  if oscDriveModeDrop then oscDriveModeDrop._onSelect = function(idx)
    local shape = math.max(0, math.min(#DRIVE_SHAPE_OPTIONS - 1, idx - 1))
    setPath(PATHS.driveShape, shape)
    if oscCtx then oscCtx.driveShape = shape; refreshOscGraph() end
  end end
  if oscDrive then oscDrive._onChange = function(v)
    setPath(PATHS.drive, v)
    if oscCtx then oscCtx.driveAmount = v; refreshOscGraph() end
  end end
  if oscDriveBias then oscDriveBias._onChange = function(v)
    setPath(PATHS.driveBias, v)
    if oscCtx then oscCtx.driveBias = v; refreshOscGraph() end
  end end
  if oscAddPartials then oscAddPartials._onChange = function(v)
    local partials = round(v)
    setPath(PATHS.additivePartials, partials)
    if oscCtx then oscCtx.additivePartials = partials; refreshOscGraph() end
  end end
  if oscAddTilt then oscAddTilt._onChange = function(v)
    setPath(PATHS.additiveTilt, v)
    if oscCtx then oscCtx.additiveTilt = v; refreshOscGraph() end
  end end
  if oscAddDrift then oscAddDrift._onChange = function(v)
    setPath(PATHS.additiveDrift, v)
    if oscCtx then oscCtx.additiveDrift = v; refreshOscGraph() end
  end end
  if oscOutput then oscOutput._onChange = function(v)
    setPath(PATHS.output, v)
    if oscCtx then oscCtx.outputLevel = v; refreshOscGraph() end
  end end
  -- New oscillator parameter handlers
  if oscPulseWidth then oscPulseWidth._onChange = function(v)
    setPath(PATHS.pulseWidth, v)
    if oscCtx then oscCtx.pulseWidth = v; refreshOscGraph() end
  end end
  if oscUnison then oscUnison._onChange = function(v)
    setPath(PATHS.unison, v)
    if oscCtx then oscCtx.unison = v; refreshOscGraph() end
  end end
  if oscDetune then oscDetune._onChange = function(v)
    setPath(PATHS.detune, v)
    if oscCtx then oscCtx.detune = v; refreshOscGraph() end
  end end
  if oscSpread then oscSpread._onChange = function(v)
    setPath(PATHS.spread, v)
    if oscCtx then oscCtx.spread = v; refreshOscGraph() end
  end end
  if oscBlendModeDrop then oscBlendModeDrop._onSelect = function(idx)
    local mode = sanitizeBlendMode(idx - 1)
    setPath(PATHS.blendMode, mode)
    local stackingEnabled = mode ~= 4 and mode ~= 5
    setWidgetInteractiveState(oscUnison, stackingEnabled)
    setWidgetInteractiveState(oscDetune, stackingEnabled)
    setWidgetInteractiveState(oscSpread, stackingEnabled)
    if oscCtx then oscCtx.blendMode = mode; refreshOscGraph() end
  end end
  if oscBlendKeyTrackRadio then oscBlendKeyTrackRadio._onChange = function(idx)
    -- idx: 1=Wave, 2=Sample, 3=Both
    local val = (idx == 1) and 0 or (idx == 2) and 1 or 2
    setPath(PATHS.blendKeyTrack, val)
    if oscCtx then
      oscCtx.blendKeyTrackMode = val  -- 0=wave, 1=sample, 2=both
      refreshOscGraph()
    end
  end end
  if oscBlendAmount then oscBlendAmount._onChange = function(v)
    setPath(PATHS.blendAmount, v)
    if oscCtx then oscCtx.blendAmount = v; refreshOscGraph() end
  end end
  if oscBlendSamplePitch then oscBlendSamplePitch._onChange = function(v)
    setPath(PATHS.blendSamplePitch, v)
    if oscCtx then oscCtx.blendSamplePitch = v; refreshOscGraph() end
  end end
  if oscBlendModAmount then oscBlendModAmount._onChange = function(v)
    setPath(PATHS.blendModAmount, v)
    if oscCtx then oscCtx.blendModAmount = v; refreshOscGraph() end
  end end
  if oscAddFlavorToggle then oscAddFlavorToggle._onSelect = function(idx)
    local flavor = (idx == 2) and 1 or 0
    setPath(PATHS.addFlavor, flavor)
    if oscCtx then oscCtx.addFlavor = flavor; refreshOscGraph() end
  end end
  if oscMorphCurve then oscMorphCurve._onSelect = function(idx)
    local curve = math.max(0, math.min(2, idx - 1))
    setPath(PATHS.morphCurve, curve)
    if oscCtx then oscCtx.morphCurve = curve; refreshOscGraph() end
  end end
  if oscMorphConvergence then oscMorphConvergence._onChange = function(v)
    local convergence = math.max(0, math.min(1, tonumber(v) or 0))
    setPath(PATHS.morphConvergence, convergence)
    if oscCtx then oscCtx.morphStretch = convergence; refreshOscGraph() end
  end end
  if oscMorphPhase then oscMorphPhase._onSelect = function(idx)
    local phase = math.max(0, math.min(2, idx - 1))
    setPath(PATHS.morphPhase, phase)
    if oscCtx then oscCtx.morphPhase = phase; refreshOscGraph() end
  end end
  if oscMorphSpeed then oscMorphSpeed._onChange = function(v)
    local speed = math.max(0.1, math.min(4.0, tonumber(v) or 1.0))
    if PATHS.morphSpeed then setPath(PATHS.morphSpeed, speed) end
    if oscCtx then oscCtx.morphSpeed = speed; refreshOscGraph() end
  end end
  if oscMorphContrast then oscMorphContrast._onChange = function(v)
    local contrast = math.max(0.0, math.min(2.0, tonumber(v) or 0.5))
    if PATHS.morphContrast then setPath(PATHS.morphContrast, contrast) end
    if oscCtx then oscCtx.morphContrast = contrast; refreshOscGraph() end
  end end
  if oscMorphSmooth then oscMorphSmooth._onChange = function(v)
    local smooth = math.max(0.0, math.min(1.0, tonumber(v) or 0.0))
    if PATHS.morphSmooth then setPath(PATHS.morphSmooth, smooth) end
    if oscCtx then oscCtx.morphSmooth = smooth; refreshOscGraph() end
  end end

  -- Filter component → DSP
  local filterBehavior = scopedBehavior(".filterComponent")
  local filterCtx = filterBehavior and filterBehavior.ctx or nil
  local filterModule = filterBehavior and filterBehavior.module or nil
  ctx._filterCtx = filterCtx
  ctx._filterModule = filterModule

  local filterTypeDrop = scopedWidget(".filterComponent.filter_type_dropdown")
  local filterCutoff = scopedWidget(".filterComponent.cutoff_knob")
  local filterReso = scopedWidget(".filterComponent.resonance_knob")

  local function refreshFilterGraph()
    if filterCtx and filterModule then filterModule.resized(filterCtx) end
  end

  if filterTypeDrop then filterTypeDrop._onSelect = function(idx)
    setPath(PATHS.filterType, idx - 1)
    if filterCtx then filterCtx.filterType = idx - 1; refreshFilterGraph() end
  end end
  if filterCutoff then filterCutoff._onChange = function(v)
    setPath(PATHS.cutoff, v)
    if filterCtx then filterCtx.cutoffHz = v; refreshFilterGraph() end
  end end
  if filterReso then filterReso._onChange = function(v)
    setPath(PATHS.resonance, v)
    if filterCtx then filterCtx.resonance = v; refreshFilterGraph() end
  end end

  -- Envelope ADSR component → DSP + graph refresh
  local envBehavior = scopedBehavior(".envelopeComponent")
  local envCtx = envBehavior and envBehavior.ctx or nil
  local envModule = envBehavior and envBehavior.module or nil
  ctx._envCtx = envCtx
  ctx._envModule = envModule

  local envAttack = scopedWidget(".envelopeComponent.attack_knob")
  local envDecay = scopedWidget(".envelopeComponent.decay_knob")
  local envSustain = scopedWidget(".envelopeComponent.sustain_knob")
  local envRelease = scopedWidget(".envelopeComponent.release_knob")
  if envAttack then envAttack._onChange = function(v)
    local s = v / 1000.0; setPath(PATHS.attack, s)
    if envCtx then envCtx.values.attack = s; envModule.resized(envCtx) end
  end end
  if envDecay then envDecay._onChange = function(v)
    local s = v / 1000.0; setPath(PATHS.decay, s)
    if envCtx then envCtx.values.decay = s; envModule.resized(envCtx) end
  end end
  if envSustain then envSustain._onChange = function(v)
    local s = v / 100.0; setPath(PATHS.sustain, s)
    if envCtx then envCtx.values.sustain = s; envModule.resized(envCtx) end
  end end
  if envRelease then envRelease._onChange = function(v)
    local s = v / 1000.0; setPath(PATHS.release, s)
    if envCtx then envCtx.values.release = s; envModule.resized(envCtx) end
  end end
  
  -- Filter dropdown
  if widgets.filterTypeDropdown then
    widgets.filterTypeDropdown._onSelect = function(idx)
      setPath(PATHS.filterType, idx - 1)
    end
  end

  -- Wire up FX components → DSP with individually addressable params
  local function wireFxComponent(slotNum, prefix)
    local behavior = scopedBehavior(prefix)
    local fxCtx = behavior and behavior.ctx or nil
    local fxModule = behavior and behavior.module or nil
    ctx["_fx" .. slotNum .. "Ctx"] = fxCtx
    ctx["_fx" .. slotNum .. "Module"] = fxModule

    local typeDrop = scopedWidget(prefix .. ".type_dropdown")
    local mixKnob = scopedWidget(prefix .. ".mix_knob")
    local paramWidgets = {
      scopedWidget(prefix .. ".param1"),
      scopedWidget(prefix .. ".param2"),
      scopedWidget(prefix .. ".param3"),
      scopedWidget(prefix .. ".param4"),
      scopedWidget(prefix .. ".param5"),
    }
    local typePath = slotNum == 1 and PATHS.fx1Type or PATHS.fx2Type
    local mixPath = slotNum == 1 and PATHS.fx1Mix or PATHS.fx2Mix

    if typeDrop then typeDrop._onSelect = function(idx)
      setPath(typePath, idx - 1)
      if fxCtx then
        fxCtx.fxType = idx - 1
        if fxModule and fxModule.onTypeChanged then fxModule.onTypeChanged(fxCtx) end
      end
    end end

    if mixKnob then mixKnob._onChange = function(v) setPath(mixPath, v) end end

    for pi = 1, #paramWidgets do
      local widget = paramWidgets[pi]
      if widget then
        widget._onChange = function(v)
          setPath(fxParamPath(slotNum, pi), v)
        end
      end
    end

    if fxCtx then
      fxCtx._onXYChanged = function(xVal, yVal)
        setPath(fxParamPath(slotNum, fxCtx.xyXIdx or 1), xVal)
        setPath(fxParamPath(slotNum, fxCtx.xyYIdx or 2), yVal)
      end
    end
  end

  wireFxComponent(1, ".fx1Component")
  wireFxComponent(2, ".fx2Component")

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
      syncSelected(widgets.midiInputDropdown, ctx._selectedMidiInputIdx or idx)
    end
  end

  -- Cache dot widgets once; simple click handler
  ctx._dockDots = {}
  local dotMap = {
    { suffix = ".dockModeDots.dockModeDotFull", mode = "full" },
    { suffix = ".dockModeDots.dockModeDotCompactSplit", mode = "compact_split" },
    { suffix = ".dockModeDots.dockModeDotCompactCollapsed", mode = "compact_collapsed" },
  }
  for _, entry in ipairs(dotMap) do
    local w = widgets[entry.suffix:match("[^.]+$")] or getScopedWidget(ctx, entry.suffix)
    if w then
      ctx._dockDots[#ctx._dockDots + 1] = { widget = w, mode = entry.mode }
      if w.node and w.node.setOnClick then
        w.node:setInterceptsMouse(true, true)
        local mode = entry.mode
        w.node:setOnClick(function()
          setUtilityDockMode(ctx, mode)
          syncDockModeDots(ctx)
        end)
      end
    end
  end
  -- Set initial mode from dock state
  local initDock = ensureUtilityDockState(ctx)
  if initDock.layoutMode == "split" then
    ctx._dockMode = "compact_split"
  elseif initDock.heightMode == "compact" then
    ctx._dockMode = "compact_collapsed"
  else
    ctx._dockMode = "full"
  end
  syncDockModeDots(ctx)

  if widgets.keyboardCollapse then
    widgets.keyboardCollapse._onClick = function()
      setKeyboardCollapsed(ctx, not ctx._keyboardCollapsed)
      persistDockUiState(ctx)
    end
  end

  -- Patch view toggle button
  if widgets.patchViewToggle then
    widgets.patchViewToggle._onClick = function()
      local currentMode = ctx._rackState and ctx._rackState.viewMode or "perf"
      local newMode = (currentMode == "perf") and "patch" or "perf"
      if ctx._rackState then
        ctx._rackState.viewMode = newMode
      end
      -- Update button visual state (show opposite of current mode)
      local isPatch = newMode == "patch"
      widgets.patchViewToggle:setLabel(isPatch and "PERF" or "PATCH")
      -- Apply view mode change (hide/show module content)
      syncPatchViewMode(ctx)
      print("[PatchView] Switched to " .. newMode .. " mode")
    end
    -- Set initial label based on current mode
    local isPatch = (ctx._rackState and ctx._rackState.viewMode) == "patch"
    widgets.patchViewToggle:setLabel(isPatch and "PERF" or "PATCH")
  end

  -- Octave buttons
  if widgets.octaveDown then
    widgets.octaveDown._onClick = function()
      ctx._keyboardOctave = math.max(0, ctx._keyboardOctave - 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave))
      syncKeyboardDisplay(ctx)
    end
  end
  
  if widgets.octaveUp then
    widgets.octaveUp._onClick = function()
      ctx._keyboardOctave = math.min(6, ctx._keyboardOctave + 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave))
      syncKeyboardDisplay(ctx)
    end
  end
  
  -- Keyboard canvas - retained display list + input callbacks
  if widgets.keyboardCanvas and widgets.keyboardCanvas.node then
    local canvas = widgets.keyboardCanvas
    canvas.node:setInterceptsMouse(true, false)
    canvas.node:setOnMouseDown(function(x, y)
      handleKeyboardClick(ctx, x, y, true)
      syncKeyboardDisplay(ctx)
    end)
    canvas.node:setOnMouseUp(function(x, y)
      handleKeyboardClick(ctx, x, y, false)
      syncKeyboardDisplay(ctx)
    end)
    syncKeyboardDisplay(ctx)
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

  -- Rack pagination dots - use same pattern as dock dots
  ctx._rackDots = {}
  for i = 1, 3 do
    -- Try scoped path first, then direct lookup
    local dotId = ".rackContainer.rackPaginationDots.rackDot" .. i
    local w = getScopedWidget(ctx, dotId)
    if not w then
      -- Fallback: try flat lookup
      w = widgets["rackDot" .. i]
    end
    if not w then
      -- Another fallback: lookup via nested container
      local container = widgets.rackPaginationDots
      if container and container.children then
        w = container.children["rackDot" .. i]
      end
    end
    if w and w.node then
      ctx._rackDots[i] = { widget = w, index = i }
      w.node:setInterceptsMouse(true, true)
      local idx = i
      w.node:setOnClick(function()
        onRackDotClick(ctx, idx)
      end)
    end
  end
  ensureRackPaginationState(ctx)
  updateRackPaginationDots(ctx)

  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend1"), {
    key = "rail:right:0",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row1",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 0,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend2"), {
    key = "rail:right:1",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row2",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 1,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend3"), {
    key = "rail:right:2",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row3",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 2,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.leftRailRecv2"), {
    key = "rail:left:1",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "recv_row2",
    direction = "output",
    portType = "audio",
    label = "RECV",
    group = "rail",
    side = "left",
    row = 1,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.leftRailRecv3"), {
    key = "rail:left:2",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "recv_row3",
    direction = "output",
    portType = "audio",
    label = "RECV",
    group = "rail",
    side = "left",
    row = 2,
  })

  -- Wire up shell drag handles for same-row reorder
  setupShellDragHandlers(ctx)
  setupResizeToggleHandlers(ctx)
  print("[Drag] Shell drag handlers setup complete")

  syncKeyboardCollapseButton(ctx)
  updateDropdownAnchors(ctx)
  refreshMidiDevices(ctx, true)
  loadSavedState(ctx)
  local additiveState = loadRuntimeState() or {}
  ctx._pendingAdditiveParamSync = {
    partials = tonumber(additiveState.additivePartials) or 8,
    tilt = tonumber(additiveState.additiveTilt) or 0.0,
    drift = tonumber(additiveState.additiveDrift) or 0.0,
    attempts = 0,
  }
  -- Apply initial view mode (patch or perf)
  syncPatchViewMode(ctx)
  -- Setup wire layer for patch view
  if RackWireLayer then
    RackWireLayer.setupWireLayer(ctx)
  end
  -- Sync _dockMode from loaded dock state
  local loadedDock = ensureUtilityDockState(ctx)
  if loadedDock.layoutMode == "split" then
    ctx._dockMode = "compact_split"
  elseif loadedDock.heightMode == "compact" then
    ctx._dockMode = "compact_collapsed"
  elseif loadedDock.heightMode == "collapsed" then
    ctx._dockMode = "compact_collapsed"
  else
    ctx._dockMode = "full"
  end
  syncDockModeDots(ctx)
  refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)

  -- Patch view can race structured layout during init; give it a few update
  -- passes to fully bootstrap labels/params/ports before declaring success.
  ctx._patchViewBootstrapFrames = 8

  -- Expose background tick so root behavior can drive MIDI + envelopes
  -- even when the MidiSynth tab is hidden.
  ctx._backgroundTickHook = function()
    backgroundTick(ctx)
  end
  _G.__midiSynthBackgroundTick = ctx._backgroundTickHook

  -- Expose panic hook so overlays/system views can force note release
  -- on project transitions to avoid stuck-note edge cases.
  ctx._panicHook = function()
    panicVoices(ctx)
  end
  _G.__midiSynthPanic = ctx._panicHook

  ctx._getDockPresentationModeHook = function()
    return ctx._dockMode or "compact_collapsed"
  end
  _G.__midiSynthGetDockPresentationMode = ctx._getDockPresentationModeHook

  ctx._setDockPresentationModeHook = function(mode)
    if mode == "full" or mode == "compact_split" or mode == "compact_collapsed" then
      setUtilityDockMode(ctx, mode)
      syncDockModeDots(ctx)
      return true
    end
    return false
  end
  _G.__midiSynthSetDockPresentationMode = ctx._setDockPresentationModeHook
end

function M.resized(ctx, w, h)
  ctx._lastW = w
  ctx._lastH = h
  refreshManagedLayoutState(ctx, w, h)
  updateDropdownAnchors(ctx)
end
function M.update(ctx, rawState)
  -- backgroundTick is driven by root behavior at ~60Hz.
  -- Only call here if root hasn't ticked recently (tab was just activated).
  local now = getTime and getTime() or 0
  if now - (ctx._lastUpdateTime or 0) > BG_TICK_INTERVAL then
    backgroundTick(ctx)
  end
  
  -- (debug removed)

  local widgets = ctx.widgets or {}
  local all = ctx.allWidgets or {}
  local rootId = ctx._globalPrefix or "root"
  local uiInteracting = isUiInteracting(ctx)

  -- Compute dt for UI animation
  local dt = now - (ctx._lastUiUpdateTime or now)
  ctx._lastUiUpdateTime = now

  maybeRefreshMidiDevices(ctx, now)

  if (ctx._patchViewBootstrapFrames or 0) > 0 then
    local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
    if viewMode == "patch" then
      syncPatchViewMode(ctx)
      if RackWireLayer and RackWireLayer.refreshWires then
        RackWireLayer.refreshWires(ctx)
      end
      local registry = ctx._patchbayPortRegistry or {}
      local registryCount = 0
      for _ in pairs(registry) do
        registryCount = registryCount + 1
      end
      if registryCount > 0 then
        ctx._patchViewBootstrapFrames = ctx._patchViewBootstrapFrames - 1
      end
    else
      ctx._patchViewBootstrapFrames = 0
    end
  end

  if ctx._pendingAdditiveParamSync then
    local pending = ctx._pendingAdditiveParamSync
    pending.attempts = (pending.attempts or 0) + 1
    local currentPartials = readParam(PATHS.additivePartials, pending.partials)
    local currentTilt = readParam(PATHS.additiveTilt, pending.tilt)
    local currentDrift = readParam(PATHS.additiveDrift, pending.drift)
    if math.abs((tonumber(currentPartials) or 0) - (tonumber(pending.partials) or 8)) > 0.0001 then
      setPath(PATHS.additivePartials, pending.partials)
    end
    if math.abs((tonumber(currentTilt) or 0) - (tonumber(pending.tilt) or 0.0)) > 0.0001 then
      setPath(PATHS.additiveTilt, pending.tilt)
    end
    if math.abs((tonumber(currentDrift) or 0) - (tonumber(pending.drift) or 0.0)) > 0.0001 then
      setPath(PATHS.additiveDrift, pending.drift)
    end
    if pending.attempts >= 4 then
      ctx._pendingAdditiveParamSync = nil
    end
  end

  -- Read parameters
  local waveform = round(readParam(PATHS.waveform, 1))
  local filterType = round(readParam(PATHS.filterType, 0))
  local cutoff = readParam(PATHS.cutoff, 3200)
  local resonance = readParam(PATHS.resonance, 0.75)
  local drive = readParam(PATHS.drive, 0.0)
  local driveShape = round(readParam(PATHS.driveShape, 0))
  local driveBias = readParam(PATHS.driveBias, 0.0)
  local oscRenderMode = round(readParam(PATHS.oscRenderMode, 0))
  local fx1Type = round(readParam(PATHS.fx1Type, 0))
  local fx1Mix = readParam(PATHS.fx1Mix, 0.0)
  local fx2Type = round(readParam(PATHS.fx2Type, 0))
  local fx2Mix = readParam(PATHS.fx2Mix, 0.0)
  local delayTime = readParam(PATHS.delayTimeL, 220)
  local delayFeedback = readParam(PATHS.delayFeedback, 0.24)
  local delayMix = readParam(PATHS.delayMix, 0.0)
  local reverbWet = readParam(PATHS.reverbWet, 0.0)
  local output = readParam(PATHS.output, 0.8)
  local attack = readParam(PATHS.attack, 0.05)
  local decay = readParam(PATHS.decay, 0.2)
  local sustain = readParam(PATHS.sustain, 0.7)
  local release = readParam(PATHS.release, 0.4)

  local sampleSource = round(readParam(PATHS.sampleSource, 0))
  local sampleCaptureBars = readParam(PATHS.sampleCaptureBars, 1.0)
  local samplePitchMapEnabled = (readParam(PATHS.samplePitchMapEnabled, 0.0) or 0.0) > 0.5
  local sampleRootNote = readParam(PATHS.sampleRootNote, 60.0)
  local sampleLoopStartPct = readParam(PATHS.sampleLoopStart, 0.0) * 100.0
  local sampleLoopLenPct = readParam(PATHS.sampleLoopLen, 1.0) * 100.0
  local sampleRetrigger = readParam(PATHS.sampleRetrigger, 1.0) > 0.5
  local rawBlendMode = round(readParam(PATHS.blendMode, 0))
  local blendMode = sanitizeBlendMode(rawBlendMode)
  if blendMode ~= rawBlendMode then
    setPath(PATHS.blendMode, blendMode)
  end
  local blendAmount = readParam(PATHS.blendAmount, 0.5)
  local blendKeyTrackMode = round(readParam(PATHS.blendKeyTrack, 2))  -- 0=wave, 1=sample, 2=both
  local blendSamplePitch = readParam(PATHS.blendSamplePitch, 0.0)
  local blendModAmount = readParam(PATHS.blendModAmount, 0.5)
  local addFlavor = round(readParam(PATHS.addFlavor, 0))
  
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
      dominantFreq = voice.freq or dominantFreq
    end
  end
  
  -- Sync oscillator component
  local function liveWidget(suffix)
    return getScopedWidget(ctx, suffix)
  end

  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.waveform_dropdown"), waveform + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.render_mode_tabs"), oscRenderMode + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_mode_dropdown"), driveShape + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mode_dropdown"), blendMode + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_source_dropdown"), sampleSource + 1)
  local samplePitchMapToggle = liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_map_toggle")
  if samplePitchMapToggle and samplePitchMapToggle.getValue and samplePitchMapToggle.setValue then
    if samplePitchMapToggle:getValue() ~= samplePitchMapEnabled then
      samplePitchMapToggle:setValue(samplePitchMapEnabled)
    end
  end
  
  local tabHost = liveWidget(".oscillatorComponent.mode_tabs")
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_bars_box"), sampleCaptureBars)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_root_box"), sampleRootNote)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_xfade_box"), math.floor((readParam(PATHS.sampleCrossfade, 0.1) or 0.1) * 100))

  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_knob"), drive)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_bias_knob"), driveBias)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_partials_knob"), round(readParam(PATHS.additivePartials, 8)))
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_tilt_knob"), readParam(PATHS.additiveTilt, 0.0))
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_drift_knob"), readParam(PATHS.additiveDrift, 0.0))
  syncValue(liveWidget(".oscillatorComponent.output_knob"), output)
  -- New oscillator parameters
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.pulse_width_knob"), readParam(PATHS.pulseWidth, 0.5))
  syncValue(liveWidget(".oscillatorComponent.unison_knob"), readParam(PATHS.unison, 1))
  syncValue(liveWidget(".oscillatorComponent.detune_knob"), readParam(PATHS.detune, 0))
  syncValue(liveWidget(".oscillatorComponent.spread_knob"), readParam(PATHS.spread, 0))
  -- Map DSP value (0=wave, 1=sample, 2=both) to UI index (1, 2, 3)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_key_track_radio"), blendKeyTrackMode + 1)
  syncValue(liveWidget(".oscillatorComponent.blend_amount_knob"), blendAmount)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob"), blendSamplePitch)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob"), blendModAmount)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle"), addFlavor + 1)

  -- Flavor toggle: Add only
  local addFlavorToggle = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle")
  if addFlavorToggle then
    local visible = blendMode == 4
    if addFlavorToggle.setVisible then
      addFlavorToggle:setVisible(visible)
    elseif addFlavorToggle.node and addFlavorToggle.node.setVisible then
      addFlavorToggle.node:setVisible(visible)
    end
  end

  local blendSamplePitchWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob")
  if blendSamplePitchWidget then
    if blendSamplePitchWidget.setVisible then
      blendSamplePitchWidget:setVisible(true)
    elseif blendSamplePitchWidget.node and blendSamplePitchWidget.node.setVisible then
      blendSamplePitchWidget.node:setVisible(true)
    end
  end

  local blendModAmountWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob")
  if blendModAmountWidget then
    if blendModAmountWidget.setVisible then
      blendModAmountWidget:setVisible(true)
    elseif blendModAmountWidget.node and blendModAmountWidget.node.setVisible then
      blendModAmountWidget.node:setVisible(true)
    end
  end

  -- Temporal controls visible for Add and Morph
  local addActive = blendMode == 4
  local morphActive = blendMode == 5
  local temporalActive = addActive or morphActive
  
  local phaseWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase")
  local speedWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed")
  local contrastWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast")
  local smoothWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth")
  local stretchWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence")
  local curveWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve")

  -- Temporal controls: visible for Add and Morph
  for _, w in ipairs({ phaseWidget, speedWidget, contrastWidget, smoothWidget, stretchWidget }) do
    if w then
      if w.setVisible then w:setVisible(temporalActive)
      elseif w.node and w.node.setVisible then w.node:setVisible(temporalActive) end
    end
  end

  -- Curve: Morph only
  if curveWidget then
    if curveWidget.setVisible then curveWidget:setVisible(morphActive)
    elseif curveWidget.node and curveWidget.node.setVisible then curveWidget.node:setVisible(morphActive) end
  end

  -- Responsive layout inside the existing tab area. No fake height inflation.
  local rowX = 10
  local rowW = 200
  local rowH = 20
  local gap = 8
  local halfW = 96
  if blendSamplePitchWidget then setWidgetBounds(blendSamplePitchWidget, rowX, 34, rowW, rowH) end
  if blendModAmountWidget then setWidgetBounds(blendModAmountWidget, rowX, 60, rowW, rowH) end

  if morphActive then
    if curveWidget then setWidgetBounds(curveWidget, rowX, 86, 74, rowH) end
    if phaseWidget then setWidgetBounds(phaseWidget, 92, 86, 118, rowH) end
    if speedWidget then setWidgetBounds(speedWidget, rowX, 112, halfW, rowH) end
    if contrastWidget then setWidgetBounds(contrastWidget, 114, 112, halfW, rowH) end
    if smoothWidget then setWidgetBounds(smoothWidget, rowX, 138, halfW, rowH) end
    if stretchWidget then setWidgetBounds(stretchWidget, 114, 138, halfW, rowH) end
  elseif addActive then
    if addFlavorToggle then setWidgetBounds(addFlavorToggle, rowX, 86, 86, rowH) end
    if phaseWidget then setWidgetBounds(phaseWidget, 104, 86, 106, rowH) end
    if speedWidget then setWidgetBounds(speedWidget, rowX, 112, halfW, rowH) end
    if contrastWidget then setWidgetBounds(contrastWidget, 114, 112, halfW, rowH) end
    if smoothWidget then setWidgetBounds(smoothWidget, rowX, 138, halfW, rowH) end
    if stretchWidget then setWidgetBounds(stretchWidget, 114, 138, halfW, rowH) end
  end
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve"), round(readParam(PATHS.morphCurve, 2)) + 1)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence"), readParam(PATHS.morphConvergence, 0))
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase"), round(readParam(PATHS.morphPhase, 0)) + 1)
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed"), readParam(PATHS.morphSpeed, 1.0))
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast"), readParam(PATHS.morphContrast, 0.5))
  syncValue(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth"), readParam(PATHS.morphSmooth, 0.0))

  local stackingEnabled = blendMode ~= 4 and blendMode ~= 5
  setWidgetInteractiveState(liveWidget(".oscillatorComponent.unison_knob"), stackingEnabled)
  setWidgetInteractiveState(liveWidget(".oscillatorComponent.detune_knob"), stackingEnabled)
  setWidgetInteractiveState(liveWidget(".oscillatorComponent.spread_knob"), stackingEnabled)

  -- Sync oscillator graph state + voice playthrough
  local oscCtx = ctx._oscCtx
  if oscCtx then
    oscCtx.waveformType = waveform
    oscCtx.renderMode = oscRenderMode
    oscCtx.pulseWidth = readParam(PATHS.pulseWidth, 0.5)
    oscCtx.unison = readParam(PATHS.unison, 1)
    oscCtx.detune = readParam(PATHS.detune, 0)
    oscCtx.spread = readParam(PATHS.spread, 0)
    oscCtx.additivePartials = round(readParam(PATHS.additivePartials, 8))
    oscCtx.additiveTilt = readParam(PATHS.additiveTilt, 0.0)
    oscCtx.additiveDrift = readParam(PATHS.additiveDrift, 0.0)
    oscCtx.driveAmount = drive
    oscCtx.driveShape = driveShape
    oscCtx.driveBias = driveBias
    oscCtx.driveMix = 1.0
    oscCtx.outputLevel = output
    -- Update knob layout based on initial waveform
    local oscModule = ctx._oscModule
    if oscModule and oscModule.updateKnobLayout then
      oscModule.updateKnobLayout(oscCtx)
    end
    -- TabHost owns oscMode as UI-only view state now.
    local currentTab = tabHost and tabHost.getActiveIndex and tabHost:getActiveIndex() or 1
    oscCtx.oscMode = (currentTab == 2) and 1 or ((currentTab == 3) and 2 or 0)
    oscCtx.sampleLoopStart = sampleLoopStartPct / 100.0
    oscCtx.sampleLoopLen = sampleLoopLenPct / 100.0
    oscCtx.samplePlayStart = (readParam(PATHS.samplePlayStart, 0.0) or 0.0)
    oscCtx.sampleCrossfade = (readParam(PATHS.sampleCrossfade, 0.1) or 0.1)
    oscCtx.blendMode = blendMode
    oscCtx.blendAmount = blendAmount
    oscCtx.blendKeyTrackMode = blendKeyTrackMode
    oscCtx.blendSamplePitch = blendSamplePitch
    oscCtx.blendModAmount = blendModAmount
    oscCtx.addFlavor = addFlavor
    oscCtx.morphCurve = round(readParam(PATHS.morphCurve, 2))
    oscCtx.morphStretch = readParam(PATHS.morphConvergence, 0)
    oscCtx.morphTilt = round(readParam(PATHS.morphPhase, 0))
    oscCtx.morphSpeed = readParam(PATHS.morphSpeed, 1.0)
    oscCtx.morphContrast = readParam(PATHS.morphContrast, 0.5)
    oscCtx.morphSmooth = readParam(PATHS.morphSmooth, 0.0)

    -- Push active voice data for animated waveform display (reuse tables to
    -- avoid per-frame GC churn while voices are active).
    local activeVoices = oscCtx.activeVoices or {}
    local activeCount = 0
    local dominantSamplePos = 0
    local dominantAmpForPos = 0
    for i = 1, VOICE_COUNT do
      local voice = ctx._voices[i]
      if voice and voice.currentAmp > 0.001 then
        activeCount = activeCount + 1
        local item = activeVoices[activeCount] or {}
        item.voiceIndex = i  -- Preserve voice index for consistent coloring
        item.freq = voice.freq or 220
        item.amp = voice.currentAmp
        item.samplePos = voice.samplePos or 0  -- Actual sample playback position
        activeVoices[activeCount] = item
        if (voice.currentAmp or 0) > dominantAmpForPos then
          dominantAmpForPos = voice.currentAmp or 0
          dominantSamplePos = voice.samplePos or 0
        end
      end
    end
    for i = activeCount + 1, #activeVoices do
      activeVoices[i] = nil
    end
    oscCtx.activeVoices = activeVoices
    oscCtx.morphSamplePos = dominantSamplePos

    -- Hint drawing quality to oscillator renderer.
    if uiInteracting then
      oscCtx.maxPoints = 72
    elseif activeCount >= 3 then
      oscCtx.maxPoints = 96
    elseif activeCount >= 2 then
      oscCtx.maxPoints = 120
    else
      oscCtx.maxPoints = 180
    end

    -- Advance animation time
    oscCtx.animTime = (oscCtx.animTime or 0) + dt

    local oscRepaintInterval = OSC_REPAINT_INTERVAL
    if uiInteracting then
      oscRepaintInterval = OSC_REPAINT_INTERVAL_WHILE_INTERACTING
    elseif activeCount >= 2 then
      oscRepaintInterval = OSC_REPAINT_INTERVAL_MULTI_VOICE
    end

    if ctx._oscModule and ctx._oscModule.repaint and now - (ctx._lastOscRepaintTime or 0) >= oscRepaintInterval then
      ctx._lastOscRepaintTime = now
      ctx._oscModule.repaint(oscCtx)
    end
  end

  -- Sync filter component
  syncSelected(liveWidget(".filterComponent.filter_type_dropdown"), filterType + 1)
  syncValue(liveWidget(".filterComponent.cutoff_knob"), cutoff)
  syncValue(liveWidget(".filterComponent.resonance_knob"), resonance)

  -- Sync filter graph state
  local filterCtx = ctx._filterCtx
  if filterCtx then
    filterCtx.filterType = filterType
    filterCtx.cutoffHz = cutoff
    filterCtx.resonance = resonance
    if ctx._filterModule and ctx._filterModule.repaint then ctx._filterModule.repaint(filterCtx) end
  end

  -- Sync FX components: read individual DSP params, sync controls (lightweight per-frame)
  local function syncFxSlot(slotNum, prefix, fxType, fxMix)
    local fxCtx = ctx["_fx" .. slotNum .. "Ctx"]
    if not fxCtx then return end

    local typeDrop = liveWidget(prefix .. ".type_dropdown")
    local xyXDrop = liveWidget(prefix .. ".xy_x_dropdown")
    local xyYDrop = liveWidget(prefix .. ".xy_y_dropdown")
    local mixKnob = liveWidget(prefix .. ".mix_knob")
    local paramWidgets = {
      liveWidget(prefix .. ".param1"),
      liveWidget(prefix .. ".param2"),
      liveWidget(prefix .. ".param3"),
      liveWidget(prefix .. ".param4"),
      liveWidget(prefix .. ".param5"),
    }

    local anyDropdownOpen = (typeDrop and typeDrop._open)
      or (xyXDrop and xyXDrop._open)
      or (xyYDrop and xyYDrop._open)

    syncSelected(typeDrop, fxType + 1)
    if not (mixKnob and mixKnob._dragging) then
      syncValue(mixKnob, fxMix)
    end

    if fxCtx.fxType ~= fxType and not anyDropdownOpen then
      fxCtx.fxType = fxType
      local fxModule = ctx["_fx" .. slotNum .. "Module"]
      if fxModule and fxModule.onTypeChanged then fxModule.onTypeChanged(fxCtx) end
    end

    local pvals = {}
    for pi = 1, MAX_FX_PARAMS do
      pvals[pi] = readParam(fxParamPath(slotNum, pi), 0.5)
    end

    if not fxCtx.dragging then
      local newX = pvals[fxCtx.xyXIdx or 1] or 0.5
      local newY = pvals[fxCtx.xyYIdx or 2] or 0.5
      if newX ~= fxCtx.xyX or newY ~= fxCtx.xyY then
        fxCtx.xyX = newX
        fxCtx.xyY = newY
        refreshFxPad(fxCtx)
      end
    end

    for pi = 1, #paramWidgets do
      local widget = paramWidgets[pi]
      if widget and not widget._dragging then
        syncValue(widget, pvals[pi] or 0.5)
      end
    end
  end

  syncFxSlot(1, ".fx1Component", fx1Type, fx1Mix)
  syncFxSlot(2, ".fx2Component", fx2Type, fx2Mix)

  
  -- Sync envelope graph: push ADSR values + voice positions each frame
  local envCtx = ctx._envCtx
  if envCtx then
    envCtx.values.attack = attack
    envCtx.values.decay = decay
    envCtx.values.sustain = sustain
    envCtx.values.release = release

    -- Build voice position data for the graph (reuse tables to reduce GC).
    local voicePositions = envCtx.voicePositions or {}
    local vpCount = 0
    for i = 1, VOICE_COUNT do
      local voice = ctx._voices[i]
      if voice and voice.envelopeStage and voice.envelopeStage ~= "idle" then
        vpCount = vpCount + 1
        local item = voicePositions[vpCount] or {}
        item.stage = voice.envelopeStage
        item.level = voice.envelopeLevel or 0
        item.time = voice.envelopeTime or 0
        voicePositions[vpCount] = item
      end
    end
    for i = vpCount + 1, #voicePositions do
      voicePositions[i] = nil
    end
    envCtx.voicePositions = voicePositions

    local envRepaintInterval = uiInteracting and ENV_REPAINT_INTERVAL_WHILE_INTERACTING or ENV_REPAINT_INTERVAL
    if ctx._envModule and ctx._envModule.repaint and now - (ctx._lastEnvRepaintTime or 0) >= envRepaintInterval then
      ctx._lastEnvRepaintTime = now
      ctx._envModule.repaint(envCtx)
    end
  end
  
  -- Sync main ADSR status label
  syncText(widgets.adsrValue, string.format("ADSR: A %s / D %s / S %.0f%% / R %s",
    formatTime(attack), formatTime(decay), sustain * 100, formatTime(release)))
  
  -- (MIDI polling + envelope updates now run in backgroundTick)
  
  -- Update status
  local activeCount = activeVoiceCount(ctx)
  local midiStatusText = isPluginMode() and "host" or "waiting"
  local midiStatusColour = 0xfff59e0b
  if activeCount > 0 then
    midiStatusText = "active"
    midiStatusColour = 0xff4ade80
  elseif ctx._selectedMidiInputIdx and ctx._selectedMidiInputIdx > 1 then
    midiStatusText = "armed"
    midiStatusColour = 0xff38bdf8
  end

  if widgets.midiState then
    syncText(widgets.midiState, midiStatusText)
    syncColour(widgets.midiState, midiStatusColour)
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

  

  -- Update voice note labels (color-coded per voice)
  for i = 1, 8 do
    local voiceLabel = widgets["voiceNote" .. i]
    if voiceLabel then
      local voice = ctx._voices[i]
      if voice and voice.active and voice.note and voice.envelopeStage ~= "idle" then
        syncText(voiceLabel, noteName(voice.note))
      else
        syncText(voiceLabel, "--")
      end
    end
  end

  

  if ctx._keyboardDirty then
    syncKeyboardDisplay(ctx)
    ctx._keyboardDirty = false
  end

  -- Apply deferred patchbay page switches safely in update, not inside click callback.
  if ctx._pendingPatchbayPages and next(ctx._pendingPatchbayPages) ~= nil then
    for shellId, pageIndex in pairs(ctx._pendingPatchbayPages) do
      local instance = patchbayInstances[shellId]
      local specId = instance and instance.specId or nil
      if specId then
        cleanupPatchbayFromRuntime(shellId, ctx)
        patchbayInstances[shellId] = nil
        ensurePatchbayWidgets(ctx, shellId, specId, pageIndex)
      end
      ctx._pendingPatchbayPages[shellId] = nil
    end
    if RackWireLayer and RackWireLayer.refreshWires then
      RackWireLayer.refreshWires(ctx)
    end
  end

  -- Sync patchbay slider values from live DSP state (only in patch view)
  local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
  if viewMode == "patch" then
    syncPatchbayValues(ctx)
  end

end

function M.cleanup(ctx)
  -- Clear exported hooks if they still point at this instance. Leaving stale
  -- ctx-capturing closures alive across project reloads is crash bait.
  if _G.__midiSynthBackgroundTick == ctx._backgroundTickHook then
    _G.__midiSynthBackgroundTick = nil
  end
  if _G.__midiSynthPanic == ctx._panicHook then
    _G.__midiSynthPanic = nil
  end
  if _G.__midiSynthGetDockPresentationMode == ctx._getDockPresentationModeHook then
    _G.__midiSynthGetDockPresentationMode = nil
  end
  if _G.__midiSynthSetDockPresentationMode == ctx._setDockPresentationModeHook then
    _G.__midiSynthSetDockPresentationMode = nil
  end

  -- Note: Midi.clearCallbacks() is still not called here to keep MIDI alive.

  -- Clear patchbay widget cache
  invalidatePatchbay(nil, ctx)
  ctx._pendingPatchbayPages = nil

  if _G.__midiSynthRackState == ctx._rackState then
    _G.__midiSynthRackState = nil
  end
  if _G.__midiSynthRackNodeSpecs == ctx._rackNodeSpecs then
    _G.__midiSynthRackNodeSpecs = nil
  end
  if _G.__midiSynthRackConnections == ctx._rackConnections then
    _G.__midiSynthRackConnections = nil
  end
  if _G.__midiSynthUtilityDock == ctx._utilityDock then
    _G.__midiSynthUtilityDock = nil
  end
end

return M

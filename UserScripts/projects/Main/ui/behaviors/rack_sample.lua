local Layout = require("ui.canonical_layout")

local RackSampleBehavior = {}

local SYNC_INTERVAL = 0.08
local COMPACT_LAYOUT_CUTOFF_W = 320
local COMPACT_REFERENCE_SIZE = { w = 236, h = 208 }
local WIDE_REFERENCE_SIZE = { w = 472, h = 208 }
local SAMPLE_COLOR = 0xff22d3ee
local VOICE_COLORS = {
  0xfffb7185,
  0xfff59e0b,
  0xff10b981,
  0xff38bdf8,
  0xffa78bfa,
  0xfff472b6,
  0xfffacc15,
  0xff34d399,
}

local GLOBAL_PATHS = {
  source = "/midi/synth/sample/source",
  captureTrigger = "/midi/synth/sample/captureTrigger",
  captureBars = "/midi/synth/sample/captureBars",
  captureMode = "/midi/synth/sample/captureMode",
  captureStartOffset = "/midi/synth/sample/captureStartOffset",
  capturedLengthMs = "/midi/synth/sample/capturedLengthMs",
  captureRecording = "/midi/synth/sample/captureRecording",
  captureWriteOffset = "/midi/synth/sample/captureWriteOffset",
  pitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
  pitchMode = "/midi/synth/sample/pitchMode",
  pvocFFTOrder = "/midi/synth/sample/pvoc/fftOrder",
  pvocTimeStretch = "/midi/synth/sample/pvoc/timeStretch",
  rootNote = "/midi/synth/sample/rootNote",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  playStart = "/midi/synth/sample/playStart",
  loopStart = "/midi/synth/sample/loopStart",
  loopLen = "/midi/synth/sample/loopLen",
  crossfade = "/midi/synth/sample/crossfade",
  retrigger = "/midi/synth/sample/retrigger",
  output = "/midi/synth/output",
}

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
  local numeric = tonumber(value) or 0
  local authoredWriter = type(_G) == "table" and _G.__midiSynthSetAuthoredParam or nil
  if type(authoredWriter) == "function" then
    return authoredWriter(path, numeric)
  end
  if type(_G.setParam) == "function" then
    return _G.setParam(path, numeric)
  end
  if type(command) == "function" then
    command("SET", path, tostring(numeric))
    return true
  end
  return false
end

local function setBounds(widget, x, y, w, h)
  Layout.setBounds(widget, x, y, w, h)
end

local function setWidgetVisible(widget, visible)
  Layout.setVisible(widget, visible)
end

local function layoutModeForContext(ctx, width)
  local sizeKey = type(ctx) == "table" and type(ctx.instanceProps) == "table" and tostring(ctx.instanceProps.sizeKey or "") or ""
  local _, cols = sizeKey:match("^(%d+)x(%d+)$")
  cols = tonumber(cols)
  if cols ~= nil then
    return cols >= 2 and "wide" or "compact"
  end
  return Layout.layoutModeForWidth(width, COMPACT_LAYOUT_CUTOFF_W)
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
  local slotIndex = type(paramBase) == "string" and paramBase:match("^/midi/synth/rack/sample/(%d+)$") or nil
  if slotIndex ~= nil then
    return math.max(1, math.floor(tonumber(slotIndex) or 1))
  end
  local nodeId = getInstanceNodeId(ctx)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  return math.max(1, math.floor(tonumber(type(entry) == "table" and entry.slotIndex or 1) or 1))
end

local function pathFor(ctx, key)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    local suffix = {
      source = "/source",
      captureTrigger = "/captureTrigger",
      captureBars = "/captureBars",
      captureMode = "/captureMode",
      captureStartOffset = "/captureStartOffset",
      capturedLengthMs = "/capturedLengthMs",
      captureRecording = "/captureRecording",
      captureWriteOffset = "/captureWriteOffset",
      pitchMapEnabled = "/pitchMapEnabled",
      pitchMode = "/pitchMode",
      pvocFFTOrder = "/pvoc/fftOrder",
      pvocTimeStretch = "/pvoc/timeStretch",
      rootNote = "/rootNote",
      unison = "/unison",
      detune = "/detune",
      spread = "/spread",
      playStart = "/playStart",
      loopStart = "/loopStart",
      loopLen = "/loopLen",
      crossfade = "/crossfade",
      retrigger = "/retrigger",
      output = "/output",
    }
    if suffix[key] then
      return paramBase .. suffix[key]
    end
  end
  return GLOBAL_PATHS[key]
end

local function dynamicSamplePeaks(ctx, numBuckets)
  local slotIndex = getSlotIndex(ctx)
  local fn = type(getDynamicSampleSlotPeaks) == "function" and getDynamicSampleSlotPeaks
    or (type(_G) == "table" and _G.__midiSynthGetDynamicSampleSlotPeaks or nil)
  if type(fn) ~= "function" or slotIndex == nil then
    return {}
  end
  local ok, peaks = pcall(fn, slotIndex, math.max(32, math.floor(tonumber(numBuckets) or 128)))
  if ok and type(peaks) == "table" then
    return peaks
  end
  return {}
end

local function dynamicVoicePositions(ctx)
  local slotIndex = getSlotIndex(ctx)
  local fn = type(getDynamicSampleSlotVoicePositions) == "function" and getDynamicSampleSlotVoicePositions
    or (type(_G) == "table" and _G.__midiSynthGetDynamicSampleSlotVoicePositions or nil)
  if type(fn) ~= "function" or slotIndex == nil then
    return {}
  end
  local ok, positions = pcall(fn, slotIndex)
  if ok and type(positions) == "table" then
    return positions
  end
  return {}
end

local function buildSampleDisplay(ctx, w, h)
  local display = {}
  local barH = 16
  local barGap = 4
  local barsHeight = barH * 2 + barGap
  local waveH = h - barsHeight - 4
  local centerY = waveH / 2
  local maxAmp = (waveH / 2) * 0.75
  local numPoints = math.max(48, math.min(w, 200))
  local loopStart = ctx.sampleLoopStart or 0.0
  local loopLen = ctx.sampleLoopLen or 1.0
  local peaks = dynamicSamplePeaks(ctx, numPoints)
  local positions = dynamicVoicePositions(ctx)

  display[#display + 1] = { cmd = "fillRect", x = 0, y = 0, w = w, h = waveH, color = 0x20ffffff }

  if peaks and #peaks > 0 then
    local prevX, prevY
    for i = 0, numPoints do
      local t = i / numPoints
      local peakIdx = math.floor(t * (#peaks - 1)) + 1
      local peak = peaks[peakIdx] or 0.5
      local s = peak * 2 - 1
      local x = math.floor(t * w)
      local y = math.floor(centerY - s * maxAmp)
      if prevX then
        display[#display + 1] = {
          cmd = "drawLine",
          x1 = prevX, y1 = prevY, x2 = x, y2 = y,
          thickness = 1, color = SAMPLE_COLOR,
        }
      end
      prevX, prevY = x, y
    end

    for voiceIndex = 1, 8 do
      local pos = tonumber(positions[voiceIndex]) or 0.0
      if pos > 0.0 then
        local peakIdx = math.floor(clamp(pos, 0.0, 1.0) * math.max(1, #peaks - 1)) + 1
        local peak = peaks[peakIdx] or 0.5
        local s = peak * 2 - 1
        local waveY = math.floor(centerY - s * maxAmp)
        local playheadX = math.floor(clamp(pos, 0.0, 1.0) * w) - 4
        display[#display + 1] = {
          cmd = "drawLine",
          x1 = playheadX, y1 = waveH - 2, x2 = playheadX, y2 = waveY,
          thickness = 3, color = VOICE_COLORS[voiceIndex],
        }
      end
    end
  end

  local handleW = 8
  local handleH = barH - 4
  local playStart = ctx.samplePlayStart or 0.0
  local loopStartPos = loopStart
  local loopEndPos = loopStart + loopLen
  local xfadeNorm = math.max(0.0, math.min(0.5, ctx.sampleCrossfade or 0.1))

  local function drawBarBackground(y)
    display[#display + 1] = { cmd = "fillRect", x = 0, y = y, w = w, h = barH, color = 0xff0d1420 }
    display[#display + 1] = { cmd = "drawLine", x1 = 0, y1 = y + barH, x2 = w, y2 = y + barH, thickness = 1, color = 0xff334155 }
  end

  local function drawHandle(y, pos, color)
    local hx = math.floor(pos * w) - math.floor(handleW / 2)
    local hy = y + 2
    display[#display + 1] = { cmd = "fillRect", x = hx, y = hy, w = handleW, h = handleH, color = color }
    display[#display + 1] = { cmd = "drawRect", x = hx, y = hy, w = handleW, h = handleH, thickness = 1, color = 0xffffffff }
  end

  local bar1Y = waveH + 2
  drawBarBackground(bar1Y)
  drawHandle(bar1Y, playStart, 0xffe5e509)

  local bar2Y = bar1Y + barH + barGap
  drawBarBackground(bar2Y)
  display[#display + 1] = {
    cmd = "drawLine",
    x1 = math.floor(loopStartPos * w), y1 = bar2Y + math.floor(barH / 2),
    x2 = math.floor(loopEndPos * w), y2 = bar2Y + math.floor(barH / 2),
    thickness = 2, color = 0x80cbd5e1,
  }

  local xfadeLen = xfadeNorm * loopLen
  local xfadeStart = math.max(loopStartPos, loopEndPos - xfadeLen)
  local headXfadeEnd = math.min(loopEndPos, loopStartPos + xfadeLen)
  if xfadeLen > 0.0001 then
    display[#display + 1] = {
      cmd = "fillRect",
      x = math.floor(loopStartPos * w), y = bar2Y + 2,
      w = math.max(1, math.floor(headXfadeEnd * w) - math.floor(loopStartPos * w)),
      h = barH - 4, color = 0x504ade80,
    }
    display[#display + 1] = {
      cmd = "fillRect",
      x = math.floor(xfadeStart * w), y = bar2Y + 2,
      w = math.max(1, math.floor(loopEndPos * w) - math.floor(xfadeStart * w)),
      h = barH - 4, color = 0x50f87171,
    }
  end

  drawHandle(bar2Y, loopStartPos, 0xff4ade80)
  drawHandle(bar2Y, loopEndPos, 0xfff87171)

  if not peaks or #peaks == 0 then
    display[#display + 1] = {
      cmd = "drawText", x = 0, y = math.floor(waveH / 2) - 8, w = w, h = 16,
      text = "No sample captured", color = 0xff94a3b8, fontSize = 11, align = "center", valign = "middle",
    }
  end

  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "SAMPLE MODE", color = 0xffa78bfa, fontSize = 10, align = "left", valign = "top",
  }
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = string.format("%dms", tonumber(ctx.sampleCapturedLengthMs) or 0), color = 0xff94a3b8, fontSize = 10, align = "right", valign = "top",
  }

  return display
end

local function refreshGraph(ctx)
  local graph = ctx.widgets and ctx.widgets.sample_graph or nil
  if not (graph and graph.node) then
    return
  end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then
    return
  end
  graph.node:setDisplayList(buildSampleDisplay(ctx, w, h))
  graph.node:repaint()
end

local function syncSlider(widget, value)
  if widget and widget.setValue and not widget._dragging then
    widget:setValue(value)
  end
end

local function setCaptureButtonAppearance(ctx)
  local button = ctx and ctx.widgets and ctx.widgets.sample_capture_button or nil
  if not button then
    return
  end
  local recording = (ctx.sampleCaptureMode == 1) and (ctx.sampleCaptureRecording == true)
  if button.setLabel then button:setLabel(recording and "STOP" or "Cap") end
  if button.setBg then button:setBg(recording and 0xffdc2626 or 0xff334155) end
end

local function pulseCaptureTrigger(ctx)
  local triggerPath = pathFor(ctx, "captureTrigger")
  writeParam(triggerPath, 1)
  writeParam(triggerPath, 0)
end

local function updatePvocVisibility(ctx)
  local widgets = ctx.widgets or {}
  local compact = ctx._layoutMode == "compact"
  setWidgetVisible(widgets.sample_pvoc_fft, not compact)
  setWidgetVisible(widgets.sample_pvoc_stretch, (not compact) and (ctx.samplePitchMode or 0) == 2)
end

local function syncFromParams(ctx)
  local widgets = ctx.widgets or {}

  ctx.sampleSource = round(readParam(pathFor(ctx, "source"), ctx.sampleSource or 1))
  ctx.sampleCaptureBars = clamp(readParam(pathFor(ctx, "captureBars"), ctx.sampleCaptureBars or 1.0), 0.0625, 16.0)
  ctx.sampleCaptureMode = round(readParam(pathFor(ctx, "captureMode"), ctx.sampleCaptureMode or 0))
  ctx.sampleCapturedLengthMs = math.max(0, round(readParam(pathFor(ctx, "capturedLengthMs"), ctx.sampleCapturedLengthMs or 0)))
  ctx.sampleCaptureRecording = (readParam(pathFor(ctx, "captureRecording"), ctx.sampleCaptureRecording and 1 or 0) or 0) > 0.5
  ctx.samplePitchMapEnabled = (readParam(pathFor(ctx, "pitchMapEnabled"), ctx.samplePitchMapEnabled and 1 or 0) or 0) > 0.5
  ctx.samplePitchMode = round(readParam(pathFor(ctx, "pitchMode"), ctx.samplePitchMode or 0))
  ctx.samplePvocFFTOrder = clamp(readParam(pathFor(ctx, "pvocFFTOrder"), ctx.samplePvocFFTOrder or 11), 9, 12)
  ctx.samplePvocTimeStretch = clamp(readParam(pathFor(ctx, "pvocTimeStretch"), ctx.samplePvocTimeStretch or 1.0), 0.25, 4.0)
  ctx.sampleRootNote = clamp(readParam(pathFor(ctx, "rootNote"), ctx.sampleRootNote or 60.0), 12, 96)
  ctx.unison = round(clamp(readParam(pathFor(ctx, "unison"), ctx.unison or 1), 1, 8))
  ctx.detune = clamp(readParam(pathFor(ctx, "detune"), ctx.detune or 0.0), 0.0, 100.0)
  ctx.spread = clamp(readParam(pathFor(ctx, "spread"), ctx.spread or 0.0), 0.0, 1.0)
  ctx.samplePlayStart = clamp(readParam(pathFor(ctx, "playStart"), ctx.samplePlayStart or 0.0), 0.0, 0.99)
  ctx.sampleLoopStart = clamp(readParam(pathFor(ctx, "loopStart"), ctx.sampleLoopStart or 0.0), 0.0, 0.95)
  ctx.sampleLoopLen = clamp(readParam(pathFor(ctx, "loopLen"), ctx.sampleLoopLen or 1.0), 0.05, 1.0)
  ctx.sampleCrossfade = clamp(readParam(pathFor(ctx, "crossfade"), ctx.sampleCrossfade or 0.1), 0.0, 0.5)
  ctx.sampleRetrigger = (readParam(pathFor(ctx, "retrigger"), ctx.sampleRetrigger and 1 or 0) or 0) > 0.5
  ctx.outputLevel = clamp(readParam(pathFor(ctx, "output"), ctx.outputLevel or 0.8), 0.0, 2.0)

  if widgets.sample_source_dropdown and widgets.sample_source_dropdown.setSelected and not widgets.sample_source_dropdown._open then
    widgets.sample_source_dropdown:setSelected(ctx.sampleSource + 1)
  end
  if widgets.sample_pitch_map_toggle and widgets.sample_pitch_map_toggle.setValue then
    widgets.sample_pitch_map_toggle:setValue(ctx.samplePitchMapEnabled)
  end
  if widgets.sample_capture_mode_toggle and widgets.sample_capture_mode_toggle.setValue then
    widgets.sample_capture_mode_toggle:setValue(ctx.sampleCaptureMode == 1)
  end
  if widgets.sample_pitch_mode and widgets.sample_pitch_mode.setSelected then
    widgets.sample_pitch_mode:setSelected(ctx.samplePitchMode + 1)
  end
  syncSlider(widgets.sample_bars_box, ctx.sampleCaptureBars)
  syncSlider(widgets.sample_root_box, ctx.sampleRootNote)
  syncSlider(widgets.unison_knob, ctx.unison)
  syncSlider(widgets.detune_knob, ctx.detune)
  syncSlider(widgets.spread_knob, ctx.spread)
  syncSlider(widgets.sample_loop_start_box, ctx.sampleLoopStart * 100.0)
  syncSlider(widgets.sample_loop_len_box, ctx.sampleLoopLen * 100.0)
  syncSlider(widgets.sample_xfade_box, ctx.sampleCrossfade * 100.0)
  syncSlider(widgets.sample_pvoc_fft, ctx.samplePvocFFTOrder)
  syncSlider(widgets.sample_pvoc_stretch, ctx.samplePvocTimeStretch)
  if widgets.sample_retrigger_toggle and widgets.sample_retrigger_toggle.setValue then widgets.sample_retrigger_toggle:setValue(ctx.sampleRetrigger) end
  syncSlider(widgets.output_knob, ctx.outputLevel)
  setCaptureButtonAppearance(ctx)
  updatePvocVisibility(ctx)
end

local function bindControls(ctx)
  local widgets = ctx.widgets or {}
  if widgets.sample_source_dropdown then
    widgets.sample_source_dropdown._onSelect = function(idx)
      local value = math.max(0, math.min(5, round((tonumber(idx) or 1) - 1)))
      ctx.sampleSource = value
      writeParam(pathFor(ctx, "source"), value)
    end
  end
  if widgets.sample_pitch_map_toggle then
    widgets.sample_pitch_map_toggle._onChange = function(v)
      ctx.samplePitchMapEnabled = v == true
      writeParam(pathFor(ctx, "pitchMapEnabled"), v and 1 or 0)
    end
  end
  if widgets.sample_capture_mode_toggle then
    widgets.sample_capture_mode_toggle._onChange = function(v)
      local mode = v and 1 or 0
      ctx.sampleCaptureMode = mode
      writeParam(pathFor(ctx, "captureMode"), mode)
      if mode ~= 1 then
        ctx.sampleCaptureRecording = false
        setCaptureButtonAppearance(ctx)
      end
    end
  end
  if widgets.sample_pitch_mode then
    widgets.sample_pitch_mode._onSelect = function(idx)
      local mode = math.max(0, math.min(2, round((tonumber(idx) or 1) - 1)))
      ctx.samplePitchMode = mode
      writeParam(pathFor(ctx, "pitchMode"), mode)
      updatePvocVisibility(ctx)
      refreshGraph(ctx)
    end
  end
  if widgets.sample_capture_button then
    widgets.sample_capture_button._onClick = nil
    widgets.sample_capture_button._onPress = function()
      if ctx.sampleCaptureMode == 1 then
        ctx.sampleCaptureRecording = not (ctx.sampleCaptureRecording == true)
        setCaptureButtonAppearance(ctx)
      end
      pulseCaptureTrigger(ctx)
    end
  end
  if widgets.sample_bars_box then
    widgets.sample_bars_box._onChange = function(v) writeParam(pathFor(ctx, "captureBars"), clamp(v, 0.0625, 16.0)) end
  end
  if widgets.sample_root_box then
    widgets.sample_root_box._onChange = function(v) writeParam(pathFor(ctx, "rootNote"), round(clamp(v, 12, 96))) end
  end
  if widgets.unison_knob then
    widgets.unison_knob._onChange = function(v) writeParam(pathFor(ctx, "unison"), round(clamp(v, 1, 8))) end
  end
  if widgets.detune_knob then
    widgets.detune_knob._onChange = function(v) writeParam(pathFor(ctx, "detune"), clamp(v, 0.0, 100.0)) end
  end
  if widgets.spread_knob then
    widgets.spread_knob._onChange = function(v) writeParam(pathFor(ctx, "spread"), clamp(v, 0.0, 1.0)) end
  end
  if widgets.sample_loop_start_box then
    widgets.sample_loop_start_box._onChange = function(v)
      writeParam(pathFor(ctx, "loopStart"), clamp(v / 100.0, 0.0, 0.95))
      refreshGraph(ctx)
    end
  end
  if widgets.sample_loop_len_box then
    widgets.sample_loop_len_box._onChange = function(v)
      writeParam(pathFor(ctx, "loopLen"), clamp(v / 100.0, 0.05, 1.0))
      refreshGraph(ctx)
    end
  end
  if widgets.sample_xfade_box then
    widgets.sample_xfade_box._onChange = function(v)
      writeParam(pathFor(ctx, "crossfade"), clamp(v / 100.0, 0.0, 0.5))
      refreshGraph(ctx)
    end
  end
  if widgets.sample_pvoc_fft then
    widgets.sample_pvoc_fft._onChange = function(v) writeParam(pathFor(ctx, "pvocFFTOrder"), round(clamp(v, 9, 12))) end
  end
  if widgets.sample_pvoc_stretch then
    widgets.sample_pvoc_stretch._onChange = function(v) writeParam(pathFor(ctx, "pvocTimeStretch"), clamp(v, 0.25, 4.0)) end
  end
  if widgets.sample_retrigger_toggle then
    widgets.sample_retrigger_toggle._onChange = function(v) writeParam(pathFor(ctx, "retrigger"), v and 1 or 0) end
  end
  if widgets.output_knob then
    widgets.output_knob._onChange = function(v) writeParam(pathFor(ctx, "output"), clamp(v, 0.0, 2.0)) end
  end
end

local function setupGraphInteraction(ctx)
  local graph = ctx.widgets and ctx.widgets.sample_graph or nil
  if not (graph and graph.node) or ctx._rangeMouseSetup then
    return
  end
  ctx._rangeMouseSetup = true
  graph.node:setInterceptsMouse(true, false)

  graph.node:setOnMouseDown(function(mx, my, shift)
    local gw = graph.node:getWidth()
    local gh = graph.node:getHeight()
    if gw <= 0 or gh <= 0 then return end

    local barH = 16
    local barGap = 4
    local barsHeight = barH * 2 + barGap
    local waveH = gh - barsHeight - 4
    local handleW = 8
    local minLoopLen = 0.05

    local loopStart = ctx.sampleLoopStart or 0.0
    local loopLen = ctx.sampleLoopLen or 1.0
    local playStart = ctx.samplePlayStart or 0.0
    local loopEnd = loopStart + loopLen

    local bar1Y = waveH + 2
    if my >= bar1Y and my <= bar1Y + barH then
      local playHandleX = math.floor(playStart * gw) - math.floor(handleW / 2)
      if mx >= playHandleX - 2 and mx <= playHandleX + handleW + 2 then
        ctx._flagDrag = { active = true, which = "play", grabOffset = mx - (playHandleX + handleW / 2) }
        return
      end
    end

    local bar2Y = bar1Y + barH + barGap
    if my >= bar2Y and my <= bar2Y + barH then
      local loopHandleX = math.floor(loopStart * gw) - math.floor(handleW / 2)
      local endHandleX = math.floor(loopEnd * gw) - math.floor(handleW / 2)
      local spanStartX = math.floor(loopStart * gw)
      local spanEndX = math.floor(loopEnd * gw)

      if shift and mx >= spanStartX and mx <= spanEndX then
        ctx._flagDrag = { active = true, which = "window", grabOffset = mx - spanStartX, windowLen = math.max(minLoopLen, loopLen) }
        return
      end
      if mx >= loopHandleX - 2 and mx <= loopHandleX + handleW + 2 then
        ctx._flagDrag = { active = true, which = "loop", grabOffset = mx - (loopHandleX + handleW / 2) }
        return
      end
      if mx >= endHandleX - 2 and mx <= endHandleX + handleW + 2 then
        ctx._flagDrag = { active = true, which = "end", grabOffset = mx - (endHandleX + handleW / 2) }
        return
      end
    end
  end)

  graph.node:setOnMouseDrag(function(mx, my)
    local drag = ctx._flagDrag
    if not (drag and drag.active) then return end
    local gw = graph.node:getWidth()
    if gw <= 4 then return end

    local minLoopLen = 0.05
    local adjustedMx = mx - (drag.grabOffset or 0)
    local pos = math.max(0, math.min(1, adjustedMx / gw))
    local loopStart = ctx.sampleLoopStart or 0.0
    local loopLen = ctx.sampleLoopLen or 1.0
    local loopEnd = loopStart + loopLen

    if drag.which == "play" then
      ctx.samplePlayStart = pos
      writeParam(pathFor(ctx, "playStart"), clamp(pos, 0.0, 0.99))
    elseif drag.which == "window" then
      local windowLen = math.max(minLoopLen, drag.windowLen or loopLen)
      local newStart = math.max(0.0, math.min(1.0 - windowLen, adjustedMx / gw))
      ctx.sampleLoopStart = newStart
      ctx.sampleLoopLen = windowLen
      writeParam(pathFor(ctx, "loopStart"), newStart)
      writeParam(pathFor(ctx, "loopLen"), windowLen)
    elseif drag.which == "loop" then
      pos = math.min(pos, loopEnd - minLoopLen)
      local newLen = loopEnd - pos
      ctx.sampleLoopStart = pos
      ctx.sampleLoopLen = newLen
      writeParam(pathFor(ctx, "loopStart"), pos)
      writeParam(pathFor(ctx, "loopLen"), newLen)
    elseif drag.which == "end" then
      pos = math.max(pos, loopStart + minLoopLen)
      local newLen = pos - loopStart
      ctx.sampleLoopLen = newLen
      writeParam(pathFor(ctx, "loopLen"), newLen)
    end
    refreshGraph(ctx)
  end)

  graph.node:setOnMouseUp(function()
    if ctx._flagDrag then
      ctx._flagDrag.active = false
      ctx._flagDrag.which = nil
      ctx._flagDrag.grabOffset = nil
    end
  end)
end

function RackSampleBehavior.init(ctx)
  ctx.sampleSource = 1
  ctx.sampleCaptureBars = 1.0
  ctx.sampleCaptureMode = 0
  ctx.sampleCapturedLengthMs = 0
  ctx.sampleCaptureRecording = false
  ctx.samplePitchMapEnabled = false
  ctx.samplePitchMode = 0
  ctx.samplePvocFFTOrder = 11
  ctx.samplePvocTimeStretch = 1.0
  ctx.sampleRootNote = 60
  ctx.unison = 1
  ctx.detune = 0.0
  ctx.spread = 0.0
  ctx.samplePlayStart = 0.0
  ctx.sampleLoopStart = 0.0
  ctx.sampleLoopLen = 1.0
  ctx.sampleCrossfade = 0.1
  ctx.sampleRetrigger = true
  ctx.outputLevel = 0.8
  ctx._lastSyncTime = 0
  ctx._lastUpdateTime = getTime and getTime() or 0
  ctx._flagDrag = { active = false, which = nil, grabOffset = 0 }

  bindControls(ctx)
  syncFromParams(ctx)
  refreshGraph(ctx)
end

function RackSampleBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets or {}
  local queue = {}
  local mode = layoutModeForContext(ctx, w)
  local reference = mode == "compact" and COMPACT_REFERENCE_SIZE or WIDE_REFERENCE_SIZE
  local scaleX, scaleY = Layout.scaleFactors(w, h, reference)
  ctx._layoutMode = mode
  local padX = math.max(6, math.floor(10 * scaleX + 0.5))
  local padY = math.max(6, math.floor(10 * scaleY + 0.5))
  local gapX = math.max(4, math.floor(6 * scaleX + 0.5))
  local gapY = math.max(4, math.floor(6 * scaleY + 0.5))
  local rowH = math.max(18, math.floor(20 * scaleY + 0.5))
  local rowGapY = math.max(2, math.floor(2 * scaleY + 0.5))
  local controlSliderH = math.max(18, math.floor(20 * scaleY + 0.5))
  local controlRowGapX = math.max(6, math.floor(8 * scaleX + 0.5))
  local controlGapY = math.max(6, math.floor(8 * scaleY + 0.5))
  local footerGapY = math.max(4, math.floor(6 * scaleY + 0.5))
  local footerSliderH = math.max(20, math.floor(22 * scaleY + 0.5))

  local function qset(widget, x, y, ww, hh)
    Layout.setBoundsQueued(queue, widget, x, y, ww, hh)
  end

  local function placeControlRow(x, y, width)
    local rowW = math.max(math.floor(96 * scaleX + 0.5), width)
    local colW = math.max(math.floor(48 * scaleX + 0.5), math.floor((rowW - controlRowGapX * 2) / 3))
    local detuneX = x + colW + controlRowGapX
    local spreadX = detuneX + colW + controlRowGapX
    qset(widgets.unison_knob, x, y, colW, controlSliderH)
    qset(widgets.detune_knob, detuneX, y, colW, controlSliderH)
    qset(widgets.spread_knob, spreadX, y, colW, controlSliderH)
  end

  local function placePanel(panelX, panelY, panelW, panelH)
    local insetX = math.max(4, math.floor(4 * scaleX + 0.5))
    local insetY = math.max(4, math.floor(4 * scaleY + 0.5))
    local innerX = panelX + insetX
    local innerY = panelY + insetY
    local innerW = math.max(math.floor(120 * scaleX + 0.5), panelW - insetX * 2)
    local colGap = math.max(4, math.floor(4 * scaleX + 0.5))
    local buttonW = math.max(math.floor(38 * scaleX + 0.5), 38)
    local sourceW = math.max(math.floor(52 * scaleX + 0.5), math.floor((innerW - colGap * 3 - buttonW) * 0.30))
    local toggleW = math.max(math.floor(52 * scaleX + 0.5), math.floor((innerW - sourceW - colGap * 3 - buttonW) * 0.5))
    local captureModeW = math.max(math.floor(48 * scaleX + 0.5), innerW - sourceW - toggleW - colGap * 3 - buttonW)

    qset(widgets.sample_panel, panelX, panelY, panelW, panelH)
    qset(widgets.sample_source_dropdown, innerX, innerY, sourceW, rowH)
    qset(widgets.sample_pitch_map_toggle, innerX + sourceW + colGap, innerY, toggleW, rowH)
    qset(widgets.sample_capture_mode_toggle, innerX + sourceW + toggleW + colGap * 2, innerY, captureModeW, rowH)
    qset(widgets.sample_capture_button, panelX + panelW - insetX - buttonW, innerY, buttonW, rowH)

    local contentX = innerX + math.max(4, math.floor(6 * scaleX + 0.5))
    local contentW = math.max(math.floor(96 * scaleX + 0.5), innerW - math.max(8, math.floor(12 * scaleX + 0.5)))
    local y = innerY + rowH + rowGapY
    qset(widgets.sample_pitch_mode, innerX, y, innerW, rowH)
    y = y + rowH + rowGapY
    qset(widgets.sample_bars_box, contentX, y, contentW, rowH)
    y = y + rowH + rowGapY
    qset(widgets.sample_root_box, contentX, y, contentW, rowH)
    y = y + rowH + rowGapY
    qset(widgets.sample_xfade_box, contentX, y, contentW, rowH)
    y = y + rowH + rowGapY
    local pvGap = math.max(8, math.floor(8 * scaleX + 0.5))
    local halfW = math.max(math.floor(56 * scaleX + 0.5), math.floor((contentW - pvGap) / 2))
    qset(widgets.sample_pvoc_fft, contentX, y, halfW, rowH)
    qset(widgets.sample_pvoc_stretch, contentX + halfW + pvGap, y, math.max(math.floor(56 * scaleX + 0.5), contentW - halfW - pvGap), rowH)
  end

  if mode == "compact" then
    local graphX = math.floor(10 * scaleX + 0.5)
    local graphY = math.floor(10 * scaleY + 0.5)
    local graphW = math.max(math.floor(216 * scaleX + 0.5), w - padX * 2)
    local graphH = math.max(math.floor(88 * scaleY + 0.5), math.floor(h * 0.40))
    local sourceY = math.floor(106 * scaleY + 0.5)
    local sourceW = math.max(math.floor(72 * scaleX + 0.5), math.floor(graphW * 0.28))
    local pitchX = graphX + sourceW + gapX
    local pitchW = math.max(math.floor(96 * scaleX + 0.5), graphX + graphW - pitchX)
    local controlY = math.floor(136 * scaleY + 0.5)
    local outputY = math.floor(166 * scaleY + 0.5)

    Layout.setVisibleQueued(queue, widgets.sample_panel, false)
    Layout.setVisibleQueued(queue, widgets.sample_pitch_map_toggle, false)
    Layout.setVisibleQueued(queue, widgets.sample_capture_mode_toggle, false)
    Layout.setVisibleQueued(queue, widgets.sample_capture_button, false)
    Layout.setVisibleQueued(queue, widgets.sample_bars_box, false)
    Layout.setVisibleQueued(queue, widgets.sample_root_box, false)
    Layout.setVisibleQueued(queue, widgets.sample_xfade_box, false)
    Layout.setVisibleQueued(queue, widgets.sample_pvoc_fft, false)
    Layout.setVisibleQueued(queue, widgets.sample_pvoc_stretch, false)
    Layout.setBoundsQueued(queue, widgets.sample_panel, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_pitch_map_toggle, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_capture_mode_toggle, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_capture_button, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_bars_box, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_root_box, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_xfade_box, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_pvoc_fft, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.sample_pvoc_stretch, 0, 0, 1, 1)
    Layout.setVisibleQueued(queue, widgets.sample_source_dropdown, true)
    Layout.setVisibleQueued(queue, widgets.sample_pitch_mode, true)

    qset(widgets.sample_graph, graphX, graphY, graphW, graphH)
    qset(widgets.sample_source_dropdown, graphX, sourceY, sourceW, rowH)
    qset(widgets.sample_pitch_mode, pitchX, sourceY, pitchW, rowH)
    placeControlRow(math.floor(16 * scaleX + 0.5), controlY, math.floor(202 * scaleX + 0.5))
    qset(widgets.output_knob, graphX, outputY, graphW, footerSliderH)
  else
    local graphX = math.floor(10 * scaleX + 0.5)
    local graphY = math.floor(10 * scaleY + 0.5)
    local graphW = math.max(math.floor(226 * scaleX + 0.5), math.floor((w - gapX - padX * 2) * 0.5))
    local graphH = math.max(math.floor(126 * scaleY + 0.5), rowH * 4)
    local controlY = math.floor(144 * scaleY + 0.5)
    local outputY = math.floor(174 * scaleY + 0.5)
    local outputH = math.max(math.floor(24 * scaleY + 0.5), footerSliderH)
    local panelX = math.floor(242 * scaleX + 0.5)
    local panelY = math.floor(10 * scaleY + 0.5)
    local panelW = math.max(math.floor(220 * scaleX + 0.5), w - panelX - padX)
    local panelH = math.max(math.floor(188 * scaleY + 0.5), h - panelY - padY)

    Layout.setVisibleQueued(queue, widgets.sample_panel, true)
    Layout.setVisibleQueued(queue, widgets.sample_source_dropdown, true)
    Layout.setVisibleQueued(queue, widgets.sample_pitch_map_toggle, true)
    Layout.setVisibleQueued(queue, widgets.sample_capture_mode_toggle, true)
    Layout.setVisibleQueued(queue, widgets.sample_capture_button, true)
    Layout.setVisibleQueued(queue, widgets.sample_pitch_mode, true)
    Layout.setVisibleQueued(queue, widgets.sample_bars_box, true)
    Layout.setVisibleQueued(queue, widgets.sample_root_box, true)
    Layout.setVisibleQueued(queue, widgets.sample_xfade_box, true)
    Layout.setVisibleQueued(queue, widgets.sample_pvoc_fft, true)

    qset(widgets.sample_graph, graphX, graphY, graphW, graphH)
    placeControlRow(math.floor(16 * scaleX + 0.5), controlY, math.floor(214 * scaleX + 0.5))
    qset(widgets.output_knob, math.floor(10 * scaleX + 0.5), outputY, math.floor(226 * scaleX + 0.5), outputH)
    placePanel(panelX, panelY, panelW, panelH)
  end

  Layout.flushWidgetRefreshes(queue)
  anchorDropdown(widgets.sample_source_dropdown, ctx.root)
  updatePvocVisibility(ctx)
  setupGraphInteraction(ctx)
  refreshGraph(ctx)
end

function RackSampleBehavior.update(ctx)
  local now = getTime and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncFromParams(ctx)
    refreshGraph(ctx)
  end
end

function RackSampleBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return RackSampleBehavior

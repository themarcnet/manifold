local ModWidgetSync = require("ui.modulation_widget_sync")
local Layout = require("ui.canonical_layout")

local EqBehavior = {}

local MIN_FREQ = 20.0
local MAX_FREQ = 20000.0
local MIN_GAIN = -24.0
local MAX_GAIN = 24.0
local MIN_Q = 0.1
local MAX_Q = 24.0
local LOG_MIN = math.log(MIN_FREQ)
local LOG_MAX = math.log(MAX_FREQ)
local NUM_BANDS = 8

-- Get actual sample rate from the engine, fallback to 48000
local function getSR()
  if type(_G.sampleRate) == "number" and _G.sampleRate > 0 then return _G.sampleRate end
  if type(_G.getParam) == "function" then
    local ok, sr = pcall(_G.getParam, "/core/sampleRate")
    if ok and type(sr) == "number" and sr > 0 then return sr end
  end
  return 48000.0
end
local POINT_RADIUS = 5
local HIT_RADIUS = 12

local BAND_TYPE = {
  Peak = 0,
  LowShelf = 1,
  HighShelf = 2,
  LowPass = 3,
  HighPass = 4,
  Notch = 5,
  BandPass = 6,
}

local TYPE_NAMES = {
  [BAND_TYPE.Peak] = "Bell",
  [BAND_TYPE.LowShelf] = "Low Shelf",
  [BAND_TYPE.HighShelf] = "High Shelf",
  [BAND_TYPE.LowPass] = "Low Pass",
  [BAND_TYPE.HighPass] = "High Pass",
  [BAND_TYPE.Notch] = "Notch",
  [BAND_TYPE.BandPass] = "Band Pass",
}

local DEFAULT_FREQS = { 60, 120, 250, 500, 1000, 2500, 6000, 12000 }
local DEFAULT_TYPES = {
  BAND_TYPE.LowShelf,
  BAND_TYPE.Peak,
  BAND_TYPE.Peak,
  BAND_TYPE.Peak,
  BAND_TYPE.Peak,
  BAND_TYPE.Peak,
  BAND_TYPE.Peak,
  BAND_TYPE.HighShelf,
}
local DEFAULT_QS = { 0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.8 }

local BAND_COLORS = {
  0xfff87171,
  0xfffb923c,
  0xfffbbf24,
  0xff4ade80,
  0xff2dd4bf,
  0xff38bdf8,
  0xffa78bfa,
  0xfff472b6,
}

local GRID_COLOR = 0xff1a1a3a
local AXIS_COLOR = 0xff334155
local CURVE_COLOR = 0xff22d3ee
local CURVE_GLOW = 0x4422d3ee
local LABEL_COLOR = 0xff64748b

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
  if command then
    command("SET", path, tostring(numeric))
    return true
  end
  return false
end

local COMPACT_LAYOUT_CUTOFF_W = 300
local COMPACT_REFERENCE_SIZE = { w = 236, h = 208 }
local WIDE_REFERENCE_SIZE = { w = 472, h = 208 }
local COMPACT_RECTS = {
  eq_graph = { x = 10, y = 10, w = 216, h = 108 },
  type_label = { x = 10, y = 126, w = 38, h = 18 },
  type_selector = { x = 52, y = 124, w = 116, h = 22 },
  freq_value = { x = 10, y = 156, w = 68, h = 24 },
  gain_value = { x = 84, y = 156, w = 68, h = 24 },
  q_value = { x = 158, y = 156, w = 68, h = 24 },
}
local WIDE_RECTS = {
  eq_graph = { x = 10, y = 10, w = 452, h = 108 },
  type_label = { x = 10, y = 126, w = 46, h = 18 },
  type_selector = { x = 60, y = 124, w = 140, h = 22 },
  freq_value = { x = 10, y = 156, w = 144, h = 24 },
  gain_value = { x = 164, y = 156, w = 144, h = 24 },
  q_value = { x = 318, y = 156, w = 144, h = 24 },
}

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
    return "eq"
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

  return "eq"
end

local function getParamBase(ctx)
  local instanceProps = type(ctx) == "table" and ctx.instanceProps or nil
  local propsParamBase = type(instanceProps) == "table" and type(instanceProps.paramBase) == "string" and instanceProps.paramBase or nil
  if type(propsParamBase) == "string" and propsParamBase ~= "" then
    return propsParamBase
  end
  local nodeId = getInstanceNodeId(ctx)
  if nodeId == "eq" then
    return "/midi/synth/eq8"
  end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  local paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase
  end
  return "/midi/synth/eq8"
end

local function bandEnabledPath(ctx, index)
  return string.format("%s/band/%d/enabled", getParamBase(ctx), index)
end

local function bandTypePath(ctx, index)
  return string.format("%s/band/%d/type", getParamBase(ctx), index)
end

local function bandFreqPath(ctx, index)
  return string.format("%s/band/%d/freq", getParamBase(ctx), index)
end

local function bandGainPath(ctx, index)
  return string.format("%s/band/%d/gain", getParamBase(ctx), index)
end

local function bandQPath(ctx, index)
  return string.format("%s/band/%d/q", getParamBase(ctx), index)
end

local function outputPath(ctx)
  return getParamBase(ctx) .. "/output"
end

local function mixPath(ctx)
  return getParamBase(ctx) .. "/mix"
end

local function freqToX(freq, w)
  local f = clamp(freq, MIN_FREQ, MAX_FREQ)
  return math.floor((math.log(f) - LOG_MIN) / (LOG_MAX - LOG_MIN) * w)
end

local function xToFreq(x, w)
  local norm = clamp(x / math.max(1, w), 0, 1)
  return math.exp(LOG_MIN + norm * (LOG_MAX - LOG_MIN))
end

local function gainToY(gain, h)
  local norm = (clamp(gain, MIN_GAIN, MAX_GAIN) - MIN_GAIN) / (MAX_GAIN - MIN_GAIN)
  return math.floor((1.0 - norm) * h)
end

local function yToGain(y, h)
  local norm = 1.0 - clamp(y / math.max(1, h), 0, 1)
  return MIN_GAIN + norm * (MAX_GAIN - MIN_GAIN)
end

local function qToY(q, h)
  local lmin = math.log(MIN_Q)
  local lmax = math.log(MAX_Q)
  local norm = (math.log(clamp(q, MIN_Q, MAX_Q)) - lmin) / (lmax - lmin)
  return math.floor((1.0 - norm) * h)
end

local function yToQ(y, h)
  local lmin = math.log(MIN_Q)
  local lmax = math.log(MAX_Q)
  local norm = 1.0 - clamp(y / math.max(1, h), 0, 1)
  return math.exp(lmin + norm * (lmax - lmin))
end

local function bandUsesGain(bandType)
  return bandType == BAND_TYPE.Peak or bandType == BAND_TYPE.LowShelf or bandType == BAND_TYPE.HighShelf
end

local function bandUsesQ(bandType)
  return bandType == BAND_TYPE.Peak or bandType == BAND_TYPE.Notch or bandType == BAND_TYPE.LowPass or bandType == BAND_TYPE.HighPass or bandType == BAND_TYPE.BandPass
end

local function makePeak(freq, q, gainDb)
  local A = 10 ^ (gainDb / 40.0)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local alpha = math.sin(w0) / (2.0 * q)
  local b0 = 1.0 + alpha * A
  local b1 = -2.0 * cosw0
  local b2 = 1.0 - alpha * A
  local a0 = 1.0 + alpha / A
  local a1 = -2.0 * cosw0
  local a2 = 1.0 - alpha / A
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeLowShelf(freq, gainDb)
  local A = 10 ^ (gainDb / 40.0)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / 2.0 * math.sqrt(A)
  local b0 = A * ((A + 1.0) - (A - 1.0) * cosw0 + 2.0 * alpha)
  local b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)
  local b2 = A * ((A + 1.0) - (A - 1.0) * cosw0 - 2.0 * alpha)
  local a0 = (A + 1.0) + (A - 1.0) * cosw0 + 2.0 * alpha
  local a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw0)
  local a2 = (A + 1.0) + (A - 1.0) * cosw0 - 2.0 * alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeHighShelf(freq, gainDb)
  local A = 10 ^ (gainDb / 40.0)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local sinw0 = math.sin(w0)
  local alpha = sinw0 / 2.0 * math.sqrt(A)
  local b0 = A * ((A + 1.0) + (A - 1.0) * cosw0 + 2.0 * alpha)
  local b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)
  local b2 = A * ((A + 1.0) + (A - 1.0) * cosw0 - 2.0 * alpha)
  local a0 = (A + 1.0) - (A - 1.0) * cosw0 + 2.0 * alpha
  local a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw0)
  local a2 = (A + 1.0) - (A - 1.0) * cosw0 - 2.0 * alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeLowPass(freq, q)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local alpha = math.sin(w0) / (2.0 * q)
  local b0 = (1.0 - cosw0) * 0.5
  local b1 = 1.0 - cosw0
  local b2 = (1.0 - cosw0) * 0.5
  local a0 = 1.0 + alpha
  local a1 = -2.0 * cosw0
  local a2 = 1.0 - alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeHighPass(freq, q)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local alpha = math.sin(w0) / (2.0 * q)
  local b0 = (1.0 + cosw0) * 0.5
  local b1 = -(1.0 + cosw0)
  local b2 = (1.0 + cosw0) * 0.5
  local a0 = 1.0 + alpha
  local a1 = -2.0 * cosw0
  local a2 = 1.0 - alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeNotch(freq, q)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local alpha = math.sin(w0) / (2.0 * q)
  local b0 = 1.0
  local b1 = -2.0 * cosw0
  local b2 = 1.0
  local a0 = 1.0 + alpha
  local a1 = -2.0 * cosw0
  local a2 = 1.0 - alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeBandPass(freq, q)
  local w0 = 2.0 * math.pi * freq / getSR()
  local cosw0 = math.cos(w0)
  local alpha = math.sin(w0) / (2.0 * q)
  local b0 = alpha
  local b1 = 0.0
  local b2 = -alpha
  local a0 = 1.0 + alpha
  local a1 = -2.0 * cosw0
  local a2 = 1.0 - alpha
  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

local function makeCoeffs(band)
  local freq = clamp(band.freq, MIN_FREQ, MAX_FREQ)
  local q = clamp(band.q, MIN_Q, MAX_Q)
  if band.type == BAND_TYPE.LowShelf then return makeLowShelf(freq, band.gain) end
  if band.type == BAND_TYPE.HighShelf then return makeHighShelf(freq, band.gain) end
  if band.type == BAND_TYPE.LowPass then return makeLowPass(freq, q) end
  if band.type == BAND_TYPE.HighPass then return makeHighPass(freq, q) end
  if band.type == BAND_TYPE.Notch then return makeNotch(freq, q) end
  if band.type == BAND_TYPE.BandPass then return makeBandPass(freq, q) end
  return makePeak(freq, q, band.gain)
end

local function renderBandState(band)
  band = type(band) == "table" and band or {}
  return {
    type = band.type,
    freq = tonumber(band.displayFreq) or tonumber(band.freq) or DEFAULT_FREQS[1],
    gain = tonumber(band.displayGain) or tonumber(band.gain) or 0.0,
    q = tonumber(band.displayQ) or tonumber(band.q) or DEFAULT_QS[1],
  }
end

local function magnitudeForCoeffs(coeffs, freq)
  local w = 2.0 * math.pi * freq / getSR()
  local cos1 = math.cos(w)
  local sin1 = math.sin(w)
  local cos2 = math.cos(2.0 * w)
  local sin2 = math.sin(2.0 * w)

  local nr = coeffs.b0 + coeffs.b1 * cos1 + coeffs.b2 * cos2
  local ni = -(coeffs.b1 * sin1 + coeffs.b2 * sin2)
  local dr = 1.0 + coeffs.a1 * cos1 + coeffs.a2 * cos2
  local di = -(coeffs.a1 * sin1 + coeffs.a2 * sin2)

  local num = math.sqrt(nr * nr + ni * ni)
  local den = math.sqrt(dr * dr + di * di)
  if den <= 1.0e-9 then return 1.0 end
  return num / den
end

local function syncBandInfo(ctx)
  local label = ctx.widgets and ctx.widgets.band_info
  if not label then return end

  if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
    local band = ctx.bands[ctx.selectedBand]
    local renderBand = renderBandState(band)
    local typeName = TYPE_NAMES[band.type] or "Bell"
    local parts = { string.format("Band %d", ctx.selectedBand), typeName, string.format("%d Hz", round(renderBand.freq)) }
    if bandUsesGain(band.type) then
      local gainText = renderBand.gain >= 0 and string.format("+%.1f dB", renderBand.gain) or string.format("%.1f dB", renderBand.gain)
      parts[#parts + 1] = gainText
    end
    if bandUsesQ(band.type) then
      parts[#parts + 1] = string.format("Q %.2f", renderBand.q)
    end
    if label.setText then
      label:setText(table.concat(parts, " · "))
    end
    if label.setColour then
      label:setColour(BAND_COLORS[ctx.selectedBand])
    end
  else
    if label.setText then
      label:setText("Click graph to add · drag point to edit · wheel adjusts Q · double-click removes")
    end
    if label.setColour then
      label:setColour(LABEL_COLOR)
    end
  end
end

local function activeBandCount(ctx)
  local count = 0
  for i = 1, NUM_BANDS do
    if ctx.bands[i].enabled then count = count + 1 end
  end
  return count
end

local function buildDisplay(ctx, w, h)
  local display = {}

  -- Title inside graph (top-left)
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "EQ", color = CURVE_COLOR, fontSize = 11, align = "left", valign = "top",
  }

  local freqMarks = { 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 }
  for _, f in ipairs(freqMarks) do
    local x = freqToX(f, w)
    display[#display + 1] = { cmd = "drawLine", x1 = x, y1 = 0, x2 = x, y2 = h, thickness = 1, color = GRID_COLOR }
  end

  for _, db in ipairs({ -18, -12, -6, 0, 6, 12, 18 }) do
    local y = gainToY(db, h)
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = 0, y1 = y, x2 = w, y2 = y,
      thickness = db == 0 and 1 or 1,
      color = db == 0 and AXIS_COLOR or GRID_COLOR,
    }
  end

  local outGainDb = tonumber(ctx.displayOutputGainDb)
  if outGainDb == nil then
    outGainDb = tonumber(ctx.outputGainDb)
  end
  if outGainDb == nil then
    local _, outputEffective = ModWidgetSync.resolveValues(outputPath(ctx), 0.0, readParam)
    outGainDb = tonumber(outputEffective) or 0.0
  end
  local lastX, lastY = nil, nil
  for x = 0, w - 1 do
    local freq = xToFreq(x, w)
    local mag = 1.0
    for i = 1, NUM_BANDS do
      local band = ctx.bands[i]
      if band.enabled then
        mag = mag * magnitudeForCoeffs(makeCoeffs(renderBandState(band)), freq)
      end
    end
    local db = 20.0 * math.log(math.max(mag, 1.0e-9), 10) + outGainDb
    local y = gainToY(db, h)
    if lastX then
      display[#display + 1] = { cmd = "drawLine", x1 = lastX, y1 = lastY, x2 = x, y2 = y, thickness = 4, color = CURVE_GLOW }
      display[#display + 1] = { cmd = "drawLine", x1 = lastX, y1 = lastY, x2 = x, y2 = y, thickness = 2, color = CURVE_COLOR }
    end
    lastX, lastY = x, y
  end

  for i = 1, NUM_BANDS do
    local band = ctx.bands[i]
    if band.enabled then
      local renderBand = renderBandState(band)
      local x = freqToX(renderBand.freq, w)
      local y = bandUsesGain(renderBand.type) and gainToY(renderBand.gain, h) or qToY(renderBand.q, h)
      local selected = ctx.selectedBand == i
      local hover = ctx.hoverBand == i
      local pointR = selected and (POINT_RADIUS + 2) or POINT_RADIUS
      if selected or hover then
        local glowR = pointR + 5
        display[#display + 1] = {
          cmd = "fillRoundedRect",
          x = x - glowR,
          y = y - glowR,
          w = glowR * 2,
          h = glowR * 2,
          radius = glowR,
          color = selected and 0x44ffffff or 0x22ffffff,
        }
      end
      display[#display + 1] = {
        cmd = "fillRoundedRect",
        x = x - pointR,
        y = y - pointR,
        w = pointR * 2,
        h = pointR * 2,
        radius = pointR,
        color = BAND_COLORS[i],
      }
      display[#display + 1] = {
        cmd = "drawRoundedRect",
        x = x - pointR,
        y = y - pointR,
        w = pointR * 2,
        h = pointR * 2,
        radius = pointR,
        thickness = selected and 2 or 1,
        color = selected and 0xffffffff or 0xff0f172a,
      }
      display[#display + 1] = {
        cmd = "drawText",
        x = x - pointR,
        y = y - pointR,
        w = pointR * 2,
        h = pointR * 2,
        text = tostring(i),
        color = 0xffffffff,
        fontSize = selected and 10 or 9,
        align = "center",
        valign = "middle",
      }
    end
  end

  return display
end

local function refreshGraph(ctx)
  local graph = ctx.widgets and ctx.widgets.eq_graph
  if not graph or not graph.node then return end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return end
  graph.node:setDisplayList(buildDisplay(ctx, w, h))
  graph.node:repaint()
end

local DROPDOWN_TYPES = { "Bell", "Low Shelf", "High Shelf", "Low Pass", "High Pass", "Notch" }

local function typeIndexFromBandType(bandType)
  if bandType == BAND_TYPE.Peak then return 1 end
  if bandType == BAND_TYPE.LowShelf then return 2 end
  if bandType == BAND_TYPE.HighShelf then return 3 end
  if bandType == BAND_TYPE.LowPass then return 4 end
  if bandType == BAND_TYPE.HighPass then return 5 end
  if bandType == BAND_TYPE.Notch then return 6 end
  return 1
end

local function bandTypeFromTypeIndex(index)
  if index == 1 then return BAND_TYPE.Peak end
  if index == 2 then return BAND_TYPE.LowShelf end
  if index == 3 then return BAND_TYPE.HighShelf end
  if index == 4 then return BAND_TYPE.LowPass end
  if index == 5 then return BAND_TYPE.HighPass end
  if index == 6 then return BAND_TYPE.Notch end
  return BAND_TYPE.Peak
end

local syncControlsToBand
local commitBand

local function updateControlsVisibility(ctx)
  local hasSelection = not not (ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled)
  local band = hasSelection and ctx.bands[ctx.selectedBand] or nil
  local showGain = band and bandUsesGain(band.type)
  local showQ = band and bandUsesQ(band.type)

  local controls = {
    ctx.widgets.type_label,
    ctx.widgets.type_selector,
    ctx.widgets.freq_value,
  }

  for _, widget in ipairs(controls) do
    if widget and widget.node and widget.node.setVisible then
      widget.node:setVisible(hasSelection)
    end
  end

  if ctx.widgets.gain_value and ctx.widgets.gain_value.node and ctx.widgets.gain_value.node.setVisible then
    ctx.widgets.gain_value.node:setVisible(hasSelection and showGain)
  end
  if ctx.widgets.q_value and ctx.widgets.q_value.node and ctx.widgets.q_value.node.setVisible then
    ctx.widgets.q_value.node:setVisible(hasSelection and showQ)
  end

  if hasSelection then
    syncControlsToBand(ctx)
  end
end

local function setupTypeSelector(ctx)
  local selector = ctx.widgets and ctx.widgets.type_selector
  if not selector then return end
  selector._onSelect = function(idx)
    ctx.insertType = bandTypeFromTypeIndex(idx)
    if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
      ctx.bands[ctx.selectedBand].type = ctx.insertType
      commitBand(ctx, ctx.selectedBand)
      syncControlsToBand(ctx)
      updateControlsVisibility(ctx)
      syncBandInfo(ctx)
      refreshGraph(ctx)
    end
  end
end

local function setupNumberBoxes(ctx)
  local freqBox = ctx.widgets and ctx.widgets.freq_value
  local gainBox = ctx.widgets and ctx.widgets.gain_value
  local qBox = ctx.widgets and ctx.widgets.q_value

  if freqBox then
    freqBox._onChange = function(value)
      if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
        ctx.bands[ctx.selectedBand].freq = clamp(value, MIN_FREQ, MAX_FREQ)
        commitBand(ctx, ctx.selectedBand)
        syncControlsToBand(ctx)
        syncBandInfo(ctx)
        refreshGraph(ctx)
      end
    end
  end

  if gainBox then
    gainBox._onChange = function(value)
      if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
        ctx.bands[ctx.selectedBand].gain = clamp(value, MIN_GAIN, MAX_GAIN)
        commitBand(ctx, ctx.selectedBand)
        syncControlsToBand(ctx)
        syncBandInfo(ctx)
        refreshGraph(ctx)
      end
    end
  end

  if qBox then
    qBox._onChange = function(value)
      if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
        ctx.bands[ctx.selectedBand].q = clamp(value, MIN_Q, MAX_Q)
        commitBand(ctx, ctx.selectedBand)
        syncControlsToBand(ctx)
        syncBandInfo(ctx)
        refreshGraph(ctx)
      end
    end
  end
end

syncControlsToBand = function(ctx)
  if not ctx.selectedBand or not ctx.bands[ctx.selectedBand] or not ctx.bands[ctx.selectedBand].enabled then
    return
  end
  local bandIndex = ctx.selectedBand
  local band = ctx.bands[bandIndex]
  ctx.insertType = band.type

  local selector = ctx.widgets and ctx.widgets.type_selector
  if selector and selector.setSelected then
    selector:setSelected(typeIndexFromBandType(band.type))
  end

  local freqBox = ctx.widgets and ctx.widgets.freq_value
  local gainBox = ctx.widgets and ctx.widgets.gain_value
  local qBox = ctx.widgets and ctx.widgets.q_value

  local freqBase, freqEffective, freqState = ModWidgetSync.resolveValues(bandFreqPath(ctx, bandIndex), band.freq, readParam)
  local gainBase, gainEffective, gainState = ModWidgetSync.resolveValues(bandGainPath(ctx, bandIndex), band.gain, readParam)
  local qBase, qEffective, qState = ModWidgetSync.resolveValues(bandQPath(ctx, bandIndex), band.q, readParam)

  band.freq = clamp(freqBase, MIN_FREQ, MAX_FREQ)
  band.gain = clamp(gainBase, MIN_GAIN, MAX_GAIN)
  band.q = clamp(qBase, MIN_Q, MAX_Q)
  band.displayFreq = clamp(freqEffective, MIN_FREQ, MAX_FREQ)
  band.displayGain = clamp(gainEffective, MIN_GAIN, MAX_GAIN)
  band.displayQ = clamp(qEffective, MIN_Q, MAX_Q)

  ModWidgetSync.syncWidget(freqBox, band.freq, band.displayFreq, freqState)
  ModWidgetSync.syncWidget(gainBox, band.gain, band.displayGain, gainState)
  ModWidgetSync.syncWidget(qBox, band.q, band.displayQ, qState)
end

local function syncFromParams(ctx)
  if type(ctx) ~= "table" or type(ctx.bands) ~= "table" then
    return false
  end
  local changed = false
  local outputBase, outputEffective = ModWidgetSync.resolveValues(outputPath(ctx), ctx.outputGainDb or 0.0, readParam)
  outputBase = tonumber(outputBase) or 0.0
  outputEffective = tonumber(outputEffective) or outputBase
  if math.abs((ctx.outputGainDb or 0.0) - outputBase) > 0.001 then
    ctx.outputGainDb = outputBase
    changed = true
  end
  if math.abs((ctx.displayOutputGainDb or 0.0) - outputEffective) > 0.001 then
    ctx.displayOutputGainDb = outputEffective
    changed = true
  end
  for i = 1, NUM_BANDS do
    local band = ctx.bands[i]
    local enabledRaw = readParam(bandEnabledPath(ctx, i), 0)
    local typeRaw = readParam(bandTypePath(ctx, i), DEFAULT_TYPES[i])
    local freqBase, freqEffective = ModWidgetSync.resolveValues(bandFreqPath(ctx, i), DEFAULT_FREQS[i], readParam)
    local gainBase, gainEffective = ModWidgetSync.resolveValues(bandGainPath(ctx, i), 0.0, readParam)
    local qBase, qEffective = ModWidgetSync.resolveValues(bandQPath(ctx, i), DEFAULT_QS[i], readParam)
    local enabled = (enabledRaw or 0) > 0.5
    local bandType = round(typeRaw)
    local freq = clamp(freqBase, MIN_FREQ, MAX_FREQ)
    local gain = clamp(gainBase, MIN_GAIN, MAX_GAIN)
    local q = clamp(qBase, MIN_Q, MAX_Q)
    local displayFreq = clamp(freqEffective, MIN_FREQ, MAX_FREQ)
    local displayGain = clamp(gainEffective, MIN_GAIN, MAX_GAIN)
    local displayQ = clamp(qEffective, MIN_Q, MAX_Q)
    if band.enabled ~= enabled or band.type ~= bandType or math.abs(band.freq - freq) > 0.01 or math.abs(band.gain - gain) > 0.01 or math.abs(band.q - q) > 0.001 or math.abs((band.displayFreq or band.freq) - displayFreq) > 0.01 or math.abs((band.displayGain or band.gain) - displayGain) > 0.01 or math.abs((band.displayQ or band.q) - displayQ) > 0.001 then
      band.enabled = enabled
      band.type = bandType
      band.freq = freq
      band.gain = gain
      band.q = q
      band.displayFreq = displayFreq
      band.displayGain = displayGain
      band.displayQ = displayQ
      changed = true
    end
  end
  return changed
end

commitBand = function(ctx, index)
  local band = ctx.bands[index]
  writeParam(bandEnabledPath(ctx, index), band.enabled and 1 or 0)
  writeParam(bandTypePath(ctx, index), band.type)
  writeParam(bandFreqPath(ctx, index), band.freq)
  writeParam(bandGainPath(ctx, index), band.gain)
  writeParam(bandQPath(ctx, index), band.q)
end

local function graphPointForBand(band, w, h)
  local renderBand = renderBandState(band)
  local y = bandUsesGain(renderBand.type) and gainToY(renderBand.gain, h) or qToY(renderBand.q, h)
  return freqToX(renderBand.freq, w), y
end

local function hitTestBand(ctx, mx, my)
  local graph = ctx.widgets and ctx.widgets.eq_graph
  if not graph or not graph.node then return nil end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return nil end

  local bestIdx = nil
  local bestDist = HIT_RADIUS * HIT_RADIUS
  for i = 1, NUM_BANDS do
    local band = ctx.bands[i]
    if band.enabled then
      local px, py = graphPointForBand(band, w, h)
      local dx = mx - px
      local dy = my - py
      local d2 = dx * dx + dy * dy
      if d2 <= bestDist then
        bestDist = d2
        bestIdx = i
      end
    end
  end
  return bestIdx
end

local function firstFreeBand(ctx)
  for i = 1, NUM_BANDS do
    if not ctx.bands[i].enabled then return i end
  end
  return nil
end

local function updateBandFromPosition(ctx, index, mx, my)
  local graph = ctx.widgets and ctx.widgets.eq_graph
  if not graph or not graph.node then return end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return end
  local band = ctx.bands[index]
  band.freq = clamp(xToFreq(mx, w), MIN_FREQ, MAX_FREQ)
  if bandUsesGain(band.type) then
    band.gain = clamp(yToGain(my, h), MIN_GAIN, MAX_GAIN)
  elseif bandUsesQ(band.type) then
    band.q = clamp(yToQ(my, h), MIN_Q, MAX_Q)
  end
  band.displayFreq = band.freq
  band.displayGain = band.gain
  band.displayQ = band.q
  commitBand(ctx, index)
  syncControlsToBand(ctx)
  updateControlsVisibility(ctx)
  syncBandInfo(ctx)
  refreshGraph(ctx)
end

local function setupGraphInteraction(ctx)
  local graph = ctx.widgets and ctx.widgets.eq_graph
  if not graph or not graph.node then return end

  if graph.node.setInterceptsMouse then
    graph.node:setInterceptsMouse(true, true)
  end

  if graph.node.setOnMouseDown then
    graph.node:setOnMouseDown(function(mx, my)
      local hit = hitTestBand(ctx, mx, my)
      if hit then
        ctx.selectedBand = hit
        ctx.insertType = ctx.bands[hit].type
        ctx.dragging = true
        updateControlsVisibility(ctx)
        updateBandFromPosition(ctx, hit, mx, my)
      else
        local free = firstFreeBand(ctx)
        if free then
          local band = ctx.bands[free]
          band.enabled = true
          band.type = ctx.insertType or BAND_TYPE.Peak
          band.q = 1.0
          ctx.selectedBand = free
          ctx.dragging = true
          updateControlsVisibility(ctx)
          updateBandFromPosition(ctx, free, mx, my)
        else
          ctx.selectedBand = nil
          updateControlsVisibility(ctx)
          syncBandInfo(ctx)
          refreshGraph(ctx)
        end
      end
    end)
  end

  if graph.node.setOnMouseDrag then
    graph.node:setOnMouseDrag(function(mx, my)
      if ctx.dragging and ctx.selectedBand then
        updateBandFromPosition(ctx, ctx.selectedBand, mx, my)
      end
    end)
  end

  if graph.node.setOnMouseUp then
    graph.node:setOnMouseUp(function()
      ctx.dragging = false
    end)
  end

  if graph.node.setOnMouseWheel then
    graph.node:setOnMouseWheel(function(mx, my, deltaY)
      local hit = hitTestBand(ctx, mx, my) or ctx.selectedBand
      if not hit then return end
      local band = ctx.bands[hit]
      if not band or not band.enabled then return end
      ctx.selectedBand = hit
      local step = deltaY > 0 and 0.1 or -0.1
      band.q = clamp(band.q + step, MIN_Q, MAX_Q)
      band.displayQ = band.q
      commitBand(ctx, hit)
      syncControlsToBand(ctx)
      syncBandInfo(ctx)
      refreshGraph(ctx)
    end)
  end

  if graph.node.setOnDoubleClick then
    graph.node:setOnDoubleClick(function()
      if ctx.selectedBand and ctx.bands[ctx.selectedBand] and ctx.bands[ctx.selectedBand].enabled then
        ctx.bands[ctx.selectedBand].enabled = false
        commitBand(ctx, ctx.selectedBand)
        ctx.selectedBand = nil
        updateControlsVisibility(ctx)
        syncBandInfo(ctx)
        refreshGraph(ctx)
      end
    end)
  end
end

function EqBehavior.init(ctx)
  ctx.bands = {}
  for i = 1, NUM_BANDS do
    ctx.bands[i] = {
      enabled = false,
      type = DEFAULT_TYPES[i],
      freq = DEFAULT_FREQS[i],
      gain = 0.0,
      q = DEFAULT_QS[i],
      displayFreq = DEFAULT_FREQS[i],
      displayGain = 0.0,
      displayQ = DEFAULT_QS[i],
    }
  end
  ctx.outputGainDb = 0.0
  ctx.displayOutputGainDb = 0.0
  ctx.selectedBand = nil
  ctx.hoverBand = nil
  ctx.dragging = false
  ctx.insertType = BAND_TYPE.Peak
  ctx._lastSyncTime = 0

  syncFromParams(ctx)
  setupGraphInteraction(ctx)
  setupTypeSelector(ctx)
  setupNumberBoxes(ctx)
  updateControlsVisibility(ctx)
  syncBandInfo(ctx)
  refreshGraph(ctx)
end

function EqBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets or {}
  local queue = {}
  local mode = Layout.layoutModeForWidth(w, COMPACT_LAYOUT_CUTOFF_W)
  local reference = mode == "compact" and COMPACT_REFERENCE_SIZE or WIDE_REFERENCE_SIZE
  local rects = mode == "compact" and COMPACT_RECTS or WIDE_RECTS
  local scaleX, scaleY = Layout.scaleFactors(w, h, reference)

  Layout.applyScaledRect(queue, widgets.eq_graph, rects.eq_graph, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.type_label, rects.type_label, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.type_selector, rects.type_selector, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.freq_value, rects.freq_value, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.gain_value, rects.gain_value, scaleX, scaleY)
  Layout.applyScaledRect(queue, widgets.q_value, rects.q_value, scaleX, scaleY)

  Layout.flushWidgetRefreshes(queue)
  anchorDropdown(widgets.type_selector, ctx.root)
  updateControlsVisibility(ctx)
  syncBandInfo(ctx)
  refreshGraph(ctx)
end

function EqBehavior.update(ctx)
  if type(ctx) ~= "table" then
    return
  end
  if type(ctx.bands) ~= "table" then
    EqBehavior.init(ctx)
    return
  end
  local now = getTime and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= 0.12 then
    ctx._lastSyncTime = now
    if syncFromParams(ctx) then
      if ctx.selectedBand and not ctx.bands[ctx.selectedBand].enabled then
        ctx.selectedBand = nil
      end
      updateControlsVisibility(ctx)
      syncBandInfo(ctx)
      refreshGraph(ctx)
    end
  end
end

function EqBehavior.repaint(ctx)
  syncBandInfo(ctx)
  refreshGraph(ctx)
end

return EqBehavior

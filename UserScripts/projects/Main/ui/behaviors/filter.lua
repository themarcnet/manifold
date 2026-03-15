-- Filter component behavior - interactive frequency response curve
local FilterBehavior = {}

local FILTER_COLORS = {
  [0] = 0xffa78bfa,  -- lowpass - purple
  [1] = 0xff38bdf8,  -- bandpass - blue
  [2] = 0xfffb7185,  -- highpass - pink
  [3] = 0xff4ade80,  -- notch - green
}

local MIN_FREQ = 20
local MAX_FREQ = 20000
local LOG_MIN = math.log(MIN_FREQ)
local LOG_MAX = math.log(MAX_FREQ)
local MIN_RESO = 0.1
local MAX_RESO = 2.0
local DB_RANGE = 36

local function freqToX(freq, w)
  return math.floor((math.log(math.max(MIN_FREQ, math.min(MAX_FREQ, freq))) - LOG_MIN) / (LOG_MAX - LOG_MIN) * w)
end

local function xToFreq(x, w)
  local t = math.max(0, math.min(1, x / w))
  return math.exp(LOG_MIN + t * (LOG_MAX - LOG_MIN))
end

local function resoToY(resonance, h)
  -- Higher resonance = taller peak = higher on screen (lower Y)
  local t = (resonance - MIN_RESO) / (MAX_RESO - MIN_RESO)
  return math.floor(h * (1 - t) * 0.8 + h * 0.1)
end

local function yToReso(y, h)
  local t = 1 - (y - h * 0.1) / (h * 0.8)
  return MIN_RESO + math.max(0, math.min(1, t)) * (MAX_RESO - MIN_RESO)
end

local function svfMagnitude(freq, cutoff, resonance, filterType)
  local w = freq / cutoff
  local w2 = w * w
  local Q = math.max(0.5, resonance * 2)
  local denom = (1 - w2) * (1 - w2) + (w / Q) * (w / Q)
  if denom < 1e-10 then denom = 1e-10 end

  if filterType == 0 then
    return 1.0 / math.sqrt(denom)
  elseif filterType == 1 then
    return (w / Q) / math.sqrt(denom)
  elseif filterType == 2 then
    return w2 / math.sqrt(denom)
  elseif filterType == 3 then
    local num = (1 - w2) * (1 - w2)
    return math.sqrt(num / denom)
  end
  return 1.0
end

local function buildFilterDisplay(ctx, w, h)
  local display = {}
  local cutoff = ctx.cutoffHz or 3200
  local resonance = ctx.resonance or 0.75
  local filterType = ctx.filterType or 0
  local dragging = ctx.dragging
  local col = FILTER_COLORS[filterType] or 0xffa78bfa
  local colDim = (0x20 << 24) | (col & 0x00ffffff)
  local colMid = (0x60 << 24) | (col & 0x00ffffff)

  -- Frequency grid
  local freqMarks = { 100, 500, 1000, 5000, 10000 }
  for _, f in ipairs(freqMarks) do
    local x = freqToX(f, w)
    display[#display + 1] = {
      cmd = "drawLine", x1 = x, y1 = 0, x2 = x, y2 = h,
      thickness = 1, color = 0xff1a1a3a,
    }
  end

  -- dB grid
  local dbMarks = { -24, -12, 0, 12, 24 }
  for _, db in ipairs(dbMarks) do
    local y = math.floor(h * 0.5 - (db / DB_RANGE) * h * 0.45)
    display[#display + 1] = {
      cmd = "drawLine", x1 = 0, y1 = y, x2 = w, y2 = y,
      thickness = 1, color = (db == 0) and 0xff1f2b4d or 0xff1a1a3a,
    }
  end

  -- Cutoff indicator line
  local cutoffX = freqToX(cutoff, w)
  display[#display + 1] = {
    cmd = "drawLine", x1 = cutoffX, y1 = 0, x2 = cutoffX, y2 = h,
    thickness = 1, color = colMid,
  }

  -- Frequency response curve
  local numPoints = math.max(60, math.min(w, 200))
  local prevX, prevY
  local zeroY = math.floor(h * 0.5)

  for i = 0, numPoints do
    local t = i / numPoints
    local freq = math.exp(LOG_MIN + t * (LOG_MAX - LOG_MIN))
    local mag = svfMagnitude(freq, cutoff, resonance, filterType)
    local db = 20 * math.log(mag + 1e-10) / math.log(10)
    db = math.max(-DB_RANGE, math.min(DB_RANGE, db))

    local x = math.floor(t * w)
    local y = math.floor(h * 0.5 - (db / DB_RANGE) * h * 0.45)
    y = math.max(1, math.min(h - 1, y))

    if i > 0 then
      display[#display + 1] = {
        cmd = "drawLine", x1 = x, y1 = y, x2 = x, y2 = zeroY,
        thickness = math.max(1, math.ceil(w / numPoints)), color = colDim,
      }
    end

    if prevX then
      display[#display + 1] = {
        cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y,
        thickness = 2, color = col,
      }
    end
    prevX, prevY = x, y
  end

  -- Control point at cutoff/resonance peak
  local peakMag = svfMagnitude(cutoff, cutoff, resonance, filterType)
  local peakDb = 20 * math.log(peakMag + 1e-10) / math.log(10)
  peakDb = math.max(-DB_RANGE, math.min(DB_RANGE, peakDb))
  local peakY = math.floor(h * 0.5 - (peakDb / DB_RANGE) * h * 0.45)

  local ptR = dragging and 7 or 5

  -- Glow when dragging
  if dragging then
    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = cutoffX - ptR - 3, y = peakY - ptR - 3,
      w = (ptR + 3) * 2, h = (ptR + 3) * 2,
      radius = ptR + 3,
      color = (0x44 << 24) | (col & 0x00ffffff),
    }
  end

  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = cutoffX - ptR, y = peakY - ptR,
    w = ptR * 2, h = ptR * 2,
    radius = ptR,
    color = dragging and col or 0xFFFFFFFF,
  }

  return display
end

local function refreshGraph(ctx)
  local graph = ctx.widgets.filter_graph
  if not graph or not graph.node then return end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return end
  graph.node:setDisplayList(buildFilterDisplay(ctx, w, h))
  graph.node:repaint()
end

local function setupGraphInteraction(ctx)
  local graph = ctx.widgets.filter_graph
  if not graph or not graph.node then return end

  if graph.node.setInterceptsMouse then
    graph.node:setInterceptsMouse(true, true)
  end

  if graph.node.setOnMouseDown then
    graph.node:setOnMouseDown(function(mx, my)
      ctx.dragging = true
      local w = graph.node:getWidth()
      local h = graph.node:getHeight()
      ctx.cutoffHz = xToFreq(mx, w)
      ctx.resonance = yToReso(my, h)
      -- Sync knobs
      local ck = ctx.widgets.cutoff_knob
      local rk = ctx.widgets.resonance_knob
      if ck then ck:setValue(ctx.cutoffHz) end
      if rk then rk:setValue(ctx.resonance) end
      refreshGraph(ctx)
    end)
  end

  if graph.node.setOnMouseDrag then
    graph.node:setOnMouseDrag(function(mx, my)
      if not ctx.dragging then return end
      local w = graph.node:getWidth()
      local h = graph.node:getHeight()
      ctx.cutoffHz = xToFreq(mx, w)
      ctx.resonance = yToReso(my, h)
      local ck = ctx.widgets.cutoff_knob
      local rk = ctx.widgets.resonance_knob
      if ck then ck:setValue(ctx.cutoffHz) end
      if rk then rk:setValue(ctx.resonance) end
      refreshGraph(ctx)
    end)
  end

  if graph.node.setOnMouseUp then
    graph.node:setOnMouseUp(function(mx, my)
      ctx.dragging = false
      refreshGraph(ctx)
    end)
  end
end

function FilterBehavior.init(ctx)
  ctx.filterType = 0
  ctx.cutoffHz = 3200
  ctx.resonance = 0.75
  ctx.dragging = false
  setupGraphInteraction(ctx)
  refreshGraph(ctx)
end

function FilterBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets
  local pad = 16

  local title = widgets.title
  if title then
    if title.setBounds then title:setBounds(pad, 8, w - pad * 2, 16)
    elseif title.node then title.node:setBounds(pad, 8, w - pad * 2, 16) end
  end

  local graphY = 30
  local knobH = math.min(90, math.floor(h * 0.36))
  local dropdownH = 24
  local labelH = 14
  local graphH = math.max(30, h - graphY - labelH - 4 - dropdownH - 4 - knobH - 8)
  local graph = widgets.filter_graph
  if graph then
    if graph.setBounds then graph:setBounds(pad, graphY, w - pad * 2, graphH)
    elseif graph.node then graph.node:setBounds(pad, graphY, w - pad * 2, graphH) end
  end

  local ddY = graphY + graphH + 4
  local ftLabel = widgets.filter_type_label
  if ftLabel then
    if ftLabel.setBounds then ftLabel:setBounds(pad, ddY, 60, labelH)
    elseif ftLabel.node then ftLabel.node:setBounds(pad, ddY, 60, labelH) end
  end
  ddY = ddY + labelH + 2
  local ftDrop = widgets.filter_type_dropdown
  if ftDrop then
    if ftDrop.setBounds then ftDrop:setBounds(pad, ddY, math.floor((w - pad * 2) * 0.55), dropdownH)
    elseif ftDrop.node then ftDrop.node:setBounds(pad, ddY, math.floor((w - pad * 2) * 0.55), dropdownH) end
  end

  local knobY = ddY + dropdownH + 6
  local knobW = math.min(76, math.floor((w - pad * 2 - 8) / 2))

  local ck = widgets.cutoff_knob
  if ck then
    if ck.setBounds then ck:setBounds(pad, knobY, knobW, knobH)
    elseif ck.node then ck.node:setBounds(pad, knobY, knobW, knobH) end
  end
  local rk = widgets.resonance_knob
  if rk then
    if rk.setBounds then rk:setBounds(pad + knobW + 8, knobY, knobW, knobH)
    elseif rk.node then rk.node:setBounds(pad + knobW + 8, knobY, knobW, knobH) end
  end

  refreshGraph(ctx)
end

function FilterBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return FilterBehavior

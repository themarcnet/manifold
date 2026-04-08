-- Filter component behavior - interactive frequency response curve
local ModWidgetSync = require("ui.modulation_widget_sync")
local Layout = require("ui.canonical_layout")

local FilterBehavior = {}

local FILTER_COLORS = {
  [0] = 0xffa78bfa, -- lowpass - purple
  [1] = 0xff38bdf8, -- bandpass - blue
  [2] = 0xfffb7185, -- highpass - pink
  [3] = 0xff4ade80, -- notch - green
}

local MIN_FREQ = 80
local MAX_FREQ = 16000
local LOG_MIN = math.log(MIN_FREQ)
local LOG_MAX = math.log(MAX_FREQ)
local MIN_RESO = 0.1
local MAX_RESO = 2.0
local DB_RANGE = 14
local SYNC_INTERVAL = 0.12
local COMPACT_LAYOUT_CUTOFF_W = 300

local COMPACT_REFERENCE_SIZE = { w = 236, h = 208 }
local WIDE_REFERENCE_SIZE = { w = 472, h = 208 }
local COMPACT_RECTS = {
  filter_graph = { x = 10, y = 10, w = 216, h = 188 },
}
local WIDE_RECTS = {
  filter_graph = { x = 10, y = 10, w = 226, h = 188 },
  filter_type_dropdown = { x = 242, y = 10, w = 220, h = 22 },
  cutoff_knob = { x = 242, y = 42, w = 220, h = 20 },
  resonance_knob = { x = 242, y = 68, w = 220, h = 20 },
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
    return "filter"
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

  return "filter"
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

local function typePath(ctx)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/type"
  end
  local nodeId = getInstanceNodeId(ctx)
  if nodeId == "filter" then
    return "/midi/synth/filterType"
  end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  local paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/type"
  end
  return "/midi/synth/filterType"
end

local function cutoffPath(ctx)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/cutoff"
  end
  local nodeId = getInstanceNodeId(ctx)
  if nodeId == "filter" then
    return "/midi/synth/cutoff"
  end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/cutoff"
  end
  return "/midi/synth/cutoff"
end

local function resonancePath(ctx)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/resonance"
  end
  local nodeId = getInstanceNodeId(ctx)
  if nodeId == "filter" then
    return "/midi/synth/resonance"
  end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[nodeId] or nil
  paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/resonance"
  end
  return "/midi/synth/resonance"
end

local function freqToX(freq, w)
  return math.floor((math.log(math.max(MIN_FREQ, math.min(MAX_FREQ, freq))) - LOG_MIN) / (LOG_MAX - LOG_MIN) * w)
end

local function xToFreq(x, w)
  local t = math.max(0, math.min(1, x / math.max(1, w)))
  return math.exp(LOG_MIN + t * (LOG_MAX - LOG_MIN))
end

local function yToReso(y, h)
  local t = 1 - math.max(0, math.min(1, y / math.max(1, h)))
  return MIN_RESO + t * (MAX_RESO - MIN_RESO)
end

local function svfMagnitude(freq, cutoff, resonance, filterType)
  local safeCutoff = math.max(MIN_FREQ, tonumber(cutoff) or 3200)
  local w = freq / safeCutoff
  if w < 0.1 then
    if filterType == 0 then return 1.0 end
    if filterType == 1 then return 0.0 end
    if filterType == 2 then return 0.0 end
    if filterType == 3 then return 1.0 end
  end
  if w > 10 then
    if filterType == 0 then return 0.0 end
    if filterType == 1 then return 0.0 end
    if filterType == 2 then return 1.0 end
    if filterType == 3 then return 1.0 end
  end
  local w2 = w * w
  local q = math.max(0.5, (tonumber(resonance) or 0.75) * 2)
  local denom = (1 - w2) * (1 - w2) + (w / q) * (w / q)
  if denom < 1e-10 then denom = 1e-10 end

  if filterType == 0 then
    return 1.0 / math.sqrt(denom)
  elseif filterType == 1 then
    return (w / q) / math.sqrt(denom)
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
  local cutoff = clamp(ctx.displayCutoffHz or ctx.cutoffHz or 3200, MIN_FREQ, MAX_FREQ)
  local resonance = clamp(ctx.displayResonance or ctx.resonance or 0.75, MIN_RESO, MAX_RESO)
  local filterType = round(ctx.displayFilterType or ctx.filterType or 0)
  local dragging = ctx.dragging
  local col = FILTER_COLORS[filterType] or 0xffa78bfa
  local colDim = (0x20 << 24) | (col & 0x00ffffff)
  local colMid = (0x60 << 24) | (col & 0x00ffffff)

  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "FILTER", color = col, fontSize = 11, align = "left", valign = "top",
  }

  local freqMarks = { 100, 500, 1000, 5000, 10000 }
  for _, f in ipairs(freqMarks) do
    local x = freqToX(f, w)
    display[#display + 1] = {
      cmd = "drawLine", x1 = x, y1 = 0, x2 = x, y2 = h,
      thickness = 1, color = 0xff1a1a3a,
    }
  end

  local dbMarks = { -24, -12, 0, 12, 24 }
  for _, db in ipairs(dbMarks) do
    local y = math.floor(h * 0.5 - (db / DB_RANGE) * h * 0.45)
    if y >= 0 and y <= h then
      display[#display + 1] = {
        cmd = "drawLine", x1 = 0, y1 = y, x2 = w, y2 = y,
        thickness = 1, color = (db == 0) and 0xff1f2b4d or 0xff1a1a3a,
      }
    end
  end

  local cutoffX = freqToX(cutoff, w)
  display[#display + 1] = {
    cmd = "drawLine", x1 = cutoffX, y1 = 0, x2 = cutoffX, y2 = h,
    thickness = 1, color = colMid,
  }

  local numPoints = math.max(60, math.min(w, 200))
  local prevX, prevY
  local zeroY = math.floor(h * 0.5)

  for i = 0, numPoints do
    local t = i / numPoints
    local freq = math.exp(LOG_MIN + t * (LOG_MAX - LOG_MIN))
    freq = math.max(cutoff * 0.25, math.min(cutoff * 4, freq))
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

  local peakMag = svfMagnitude(cutoff, cutoff, resonance, filterType)
  local peakDb = 20 * math.log(peakMag + 1e-10) / math.log(10)
  peakDb = math.max(-DB_RANGE, math.min(DB_RANGE, peakDb))
  local peakY = math.floor(h * 0.5 - (peakDb / DB_RANGE) * h * 0.45)

  local ptR = dragging and 7 or 5
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
  local graph = ctx.widgets and ctx.widgets.filter_graph
  if not graph or not graph.node then return end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return end
  graph.node:setDisplayList(buildFilterDisplay(ctx, w, h))
  graph.node:repaint()
end

local function commitFilterValues(ctx)
  writeParam(cutoffPath(ctx), clamp(ctx.cutoffHz or 3200, MIN_FREQ, MAX_FREQ))
  writeParam(resonancePath(ctx), clamp(ctx.resonance or 0.75, MIN_RESO, MAX_RESO))
end

local function syncFromParams(ctx)
  local changed = false
  local filterTypeBase, filterTypeEffective = ModWidgetSync.resolveValues(typePath(ctx), ctx.filterType or 0, readParam)
  local filterType = round(filterTypeBase)
  local filterTypeDisplay = round(filterTypeEffective)
  local cutoffBase, cutoffEffective, cutoffState = ModWidgetSync.resolveValues(cutoffPath(ctx), ctx.cutoffHz or 3200, readParam)
  local resonanceBase, resonanceEffective, resonanceState = ModWidgetSync.resolveValues(resonancePath(ctx), ctx.resonance or 0.75, readParam)
  local cutoff = clamp(cutoffBase, MIN_FREQ, MAX_FREQ)
  local resonance = clamp(resonanceBase, MIN_RESO, MAX_RESO)
  cutoffEffective = clamp(cutoffEffective, MIN_FREQ, MAX_FREQ)
  resonanceEffective = clamp(resonanceEffective, MIN_RESO, MAX_RESO)

  local dropdown = ctx.widgets and ctx.widgets.filter_type_dropdown or nil
  local anyDropdownOpen = dropdown and dropdown._open

  if ctx.filterType ~= filterType then
    ctx.filterType = filterType
    changed = true
    if dropdown and dropdown.setSelected and not anyDropdownOpen then
      dropdown:setSelected(filterType + 1)
    end
  end
  if (ctx.displayFilterType or ctx.filterType or 0) ~= filterTypeDisplay then
    ctx.displayFilterType = filterTypeDisplay
    changed = true
  end

  if math.abs((ctx.cutoffHz or 0) - cutoff) > 0.001 then
    ctx.cutoffHz = cutoff
    changed = true
  end
  if math.abs((ctx.displayCutoffHz or 0) - cutoffEffective) > 0.001 then
    ctx.displayCutoffHz = cutoffEffective
    changed = true
  end
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.cutoff_knob or nil, cutoff, cutoffEffective, cutoffState)

  if math.abs((ctx.resonance or 0) - resonance) > 0.0001 then
    ctx.resonance = resonance
    changed = true
  end
  if math.abs((ctx.displayResonance or 0) - resonanceEffective) > 0.0001 then
    ctx.displayResonance = resonanceEffective
    changed = true
  end
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.resonance_knob or nil, resonance, resonanceEffective, resonanceState)

  return changed
end

local function bindControls(ctx)
  local dropdown = ctx.widgets and ctx.widgets.filter_type_dropdown or nil
  if dropdown then
    dropdown._onSelect = function(idx)
      local nextType = math.max(0, math.min(3, round((tonumber(idx) or 1) - 1)))
      writeParam(typePath(ctx), nextType)
      ctx.filterType = nextType
      ctx.displayFilterType = nextType
      refreshGraph(ctx)
    end
  end

  local cutoffKnob = ctx.widgets and ctx.widgets.cutoff_knob or nil
  if cutoffKnob then
    cutoffKnob._onChange = function(v)
      local cutoff = clamp(v, MIN_FREQ, MAX_FREQ)
      ctx.cutoffHz = cutoff
      writeParam(cutoffPath(ctx), cutoff)
      syncFromParams(ctx)
      refreshGraph(ctx)
    end
  end

  local resonanceKnob = ctx.widgets and ctx.widgets.resonance_knob or nil
  if resonanceKnob then
    resonanceKnob._onChange = function(v)
      local resonance = clamp(v, MIN_RESO, MAX_RESO)
      ctx.resonance = resonance
      writeParam(resonancePath(ctx), resonance)
      syncFromParams(ctx)
      refreshGraph(ctx)
    end
  end
end

local function setupGraphInteraction(ctx)
  local graph = ctx.widgets and ctx.widgets.filter_graph
  if not graph or not graph.node then return end

  if graph.node.setInterceptsMouse then
    graph.node:setInterceptsMouse(true, true)
  end

  local function applyGraphPoint(mx, my)
    local w = graph.node:getWidth()
    local h = graph.node:getHeight()
    ctx.cutoffHz = clamp(xToFreq(mx, w), MIN_FREQ, MAX_FREQ)
    ctx.resonance = clamp(yToReso(my, h), MIN_RESO, MAX_RESO)
    commitFilterValues(ctx)
    syncFromParams(ctx)
    refreshGraph(ctx)
  end

  if graph.node.setOnMouseDown then
    graph.node:setOnMouseDown(function(mx, my)
      ctx.dragging = true
      applyGraphPoint(mx, my)
    end)
  end

  if graph.node.setOnMouseDrag then
    graph.node:setOnMouseDrag(function(mx, my)
      if not ctx.dragging then return end
      applyGraphPoint(mx, my)
    end)
  end

  if graph.node.setOnMouseUp then
    graph.node:setOnMouseUp(function()
      ctx.dragging = false
      refreshGraph(ctx)
    end)
  end
end

function FilterBehavior.init(ctx)
  ctx.filterType = 0
  ctx.displayFilterType = 0
  ctx.cutoffHz = 3200
  ctx.displayCutoffHz = 3200
  ctx.resonance = 0.75
  ctx.displayResonance = 0.75
  ctx.dragging = false
  ctx._lastSyncTime = 0
  bindControls(ctx)
  setupGraphInteraction(ctx)
  syncFromParams(ctx)
  refreshGraph(ctx)
end

function FilterBehavior.resized(ctx, w, h)
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

  Layout.setVisibleQueued(queue, widgets.filter_type_label, false)
  Layout.setBoundsQueued(queue, widgets.filter_type_label, 0, 0, 1, 1)

  Layout.applyScaledRect(queue, widgets.filter_graph, rects.filter_graph, scaleX, scaleY)

  if mode == "wide" then
    Layout.setVisibleQueued(queue, widgets.filter_type_dropdown, true)
    Layout.setVisibleQueued(queue, widgets.cutoff_knob, true)
    Layout.setVisibleQueued(queue, widgets.resonance_knob, true)
    Layout.applyScaledRect(queue, widgets.filter_type_dropdown, rects.filter_type_dropdown, scaleX, scaleY)
    Layout.applyScaledRect(queue, widgets.cutoff_knob, rects.cutoff_knob, scaleX, scaleY)
    Layout.applyScaledRect(queue, widgets.resonance_knob, rects.resonance_knob, scaleX, scaleY)
  else
    Layout.setVisibleQueued(queue, widgets.filter_type_dropdown, false)
    Layout.setVisibleQueued(queue, widgets.cutoff_knob, false)
    Layout.setVisibleQueued(queue, widgets.resonance_knob, false)
    Layout.setBoundsQueued(queue, widgets.filter_type_dropdown, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.cutoff_knob, 0, 0, 1, 1)
    Layout.setBoundsQueued(queue, widgets.resonance_knob, 0, 0, 1, 1)
  end

  Layout.flushWidgetRefreshes(queue)
  anchorDropdown(widgets.filter_type_dropdown, ctx.root)
  refreshGraph(ctx)
end

function FilterBehavior.update(ctx)
  if type(ctx) ~= "table" then
    return
  end
  local now = getTime and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    if syncFromParams(ctx) then
      refreshGraph(ctx)
    end
  end
end

function FilterBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return FilterBehavior

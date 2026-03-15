-- FX Slot component behavior
-- XY pad + 2 knobs, each independently assignable to any effect parameter via dropdowns
local FxSlotBehavior = {}

local FX_PARAMS = {
  [0]  = { "Rate", "Depth", "Feedback", "Spread", "Voices" },
  [1]  = { "Rate", "Depth", "Feedback", "Spread", "Stages" },
  [2]  = { "Drive", "Curve", "Output", "Bias" },
  [3]  = { "Threshold", "Ratio", "Attack", "Release", "Knee" },
  [4]  = { "Width", "MonoLow" },
  [5]  = { "Cutoff", "Reso" },
  [6]  = { "Cutoff", "Reso", "Drive" },
  [7]  = { "Room", "Damp" },
  [8]  = { "Time", "Feedback" },
  [9]  = { "Taps", "Feedback" },
  [10] = { "Pitch", "Window", "Feedback" },
  [11] = { "Grain", "Density", "Position", "Spray" },
  [12] = { "Freq", "Depth", "Spread" },
  [13] = { "Vowel", "Shift", "Reso", "Drive" },
  [14] = { "Low", "High", "Mid" },
  [15] = { "Threshold", "Drive", "Release", "SoftClip" },
  [16] = { "Attack", "Sustain", "Sensitivity" },
}

local function getParamNames(fxType)
  return FX_PARAMS[fxType or 0] or { "Param 1", "Param 2" }
end

local function buildXYDisplay(ctx, w, h)
  local display = {}
  local xVal = ctx.xyX or 0.5
  local yVal = ctx.xyY or 0.5
  local dragging = ctx.dragging
  local col = ctx.accentColor or 0xff22d3ee
  local colDim = (0x18 << 24) | (col & 0x00ffffff)
  local colMid = (0x44 << 24) | (col & 0x00ffffff)

  -- Grid
  for i = 1, 3 do
    display[#display + 1] = {
      cmd = "drawLine", x1 = math.floor(w * i / 4), y1 = 0,
      x2 = math.floor(w * i / 4), y2 = h, thickness = 1, color = 0xff1a1a3a,
    }
    display[#display + 1] = {
      cmd = "drawLine", x1 = 0, y1 = math.floor(h * i / 4),
      x2 = w, y2 = math.floor(h * i / 4), thickness = 1, color = 0xff1a1a3a,
    }
  end

  local cx = math.floor(xVal * w)
  local cy = math.floor((1 - yVal) * h)

  display[#display + 1] = { cmd = "drawLine", x1 = cx, y1 = 0, x2 = cx, y2 = h, thickness = 1, color = colMid }
  display[#display + 1] = { cmd = "drawLine", x1 = 0, y1 = cy, x2 = w, y2 = cy, thickness = 1, color = colMid }
  display[#display + 1] = { cmd = "fillRect", x = 0, y = cy, w = cx, h = h - cy, color = colDim }

  local ptR = dragging and 8 or 6
  if dragging then
    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = cx - ptR - 3, y = cy - ptR - 3, w = (ptR + 3) * 2, h = (ptR + 3) * 2,
      radius = ptR + 3, color = (0x33 << 24) | (col & 0x00ffffff),
    }
  end
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = cx - ptR, y = cy - ptR, w = ptR * 2, h = ptR * 2,
    radius = ptR, color = dragging and col or 0xFFFFFFFF,
  }

  local xName = ctx.xyXName or "X"
  local yName = ctx.xyYName or "Y"
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = h - 14, w = math.floor(w * 0.5), h = 12,
    text = string.format("%s: %.0f%%", xName, xVal * 100),
    color = (0x88 << 24) | (col & 0x00ffffff), fontSize = 9,
  }
  display[#display + 1] = {
    cmd = "drawText", x = math.floor(w * 0.5), y = 2,
    w = math.floor(w * 0.5) - 4, h = 12,
    text = string.format("%s: %.0f%%", yName, yVal * 100),
    color = (0x88 << 24) | (col & 0x00ffffff), fontSize = 9,
    justification = 2,
  }

  return display
end

local function refreshPad(ctx)
  local pad = ctx.widgets.xy_pad
  if not pad or not pad.node then return end
  local w = pad.node:getWidth()
  local h = pad.node:getHeight()
  if w <= 0 or h <= 0 then return end
  pad.node:setDisplayList(buildXYDisplay(ctx, w, h))
  pad.node:repaint()
end

local function populateDropdown(dropdown, names, selectedIdx)
  if not dropdown then return end
  if dropdown.setOptions then dropdown:setOptions(names) end
  local sel = math.min(selectedIdx or 1, #names)
  if sel < 1 then sel = 1 end
  if dropdown.setSelected then dropdown:setSelected(sel) end
  return sel
end

local function syncAllDropdowns(ctx)
  local names = getParamNames(ctx.fxType)

  ctx.xyXIdx = populateDropdown(ctx.widgets.xy_x_dropdown, names, ctx.xyXIdx or 1)
  ctx.xyYIdx = populateDropdown(ctx.widgets.xy_y_dropdown, names, ctx.xyYIdx or 2)
  ctx.knob1Idx = populateDropdown(ctx.widgets.knob1_dropdown, names, ctx.knob1Idx or 1)
  ctx.knob2Idx = populateDropdown(ctx.widgets.knob2_dropdown, names, ctx.knob2Idx or 2)

  ctx.xyXName = names[ctx.xyXIdx] or "X"
  ctx.xyYName = names[ctx.xyYIdx] or "Y"

  -- Update knob labels (must rebuild retained display list)
  local function setKnobLabel(knob, label)
    if not knob then return end
    knob._label = label
    if knob._syncRetained then knob:_syncRetained() end
  end
  setKnobLabel(ctx.widgets.knob1, names[ctx.knob1Idx] or "P1")
  setKnobLabel(ctx.widgets.knob2, names[ctx.knob2Idx] or "P2")
end

local function setupInteraction(ctx)
  local pad = ctx.widgets.xy_pad
  if pad and pad.node then
    if pad.node.setInterceptsMouse then pad.node:setInterceptsMouse(true, true) end

    local function applyXY(mx, my)
      local w = pad.node:getWidth()
      local h = pad.node:getHeight()
      if w <= 0 or h <= 0 then return end
      ctx.xyX = math.max(0, math.min(1, mx / w))
      ctx.xyY = math.max(0, math.min(1, 1 - my / h))
      if ctx._onXYChanged then ctx._onXYChanged(ctx.xyX, ctx.xyY) end
      refreshPad(ctx)
    end

    if pad.node.setOnMouseDown then
      pad.node:setOnMouseDown(function(mx, my) ctx.dragging = true; applyXY(mx, my) end)
    end
    if pad.node.setOnMouseDrag then
      pad.node:setOnMouseDrag(function(mx, my) if ctx.dragging then applyXY(mx, my) end end)
    end
    if pad.node.setOnMouseUp then
      pad.node:setOnMouseUp(function(mx, my) ctx.dragging = false; refreshPad(ctx) end)
    end
  end

  -- XY axis assignment dropdowns
  local xyXDrop = ctx.widgets.xy_x_dropdown
  if xyXDrop then
    xyXDrop._onSelect = function(idx)
      ctx.xyXIdx = idx
      local names = getParamNames(ctx.fxType)
      ctx.xyXName = names[idx] or "X"
      refreshPad(ctx)
    end
  end
  local xyYDrop = ctx.widgets.xy_y_dropdown
  if xyYDrop then
    xyYDrop._onSelect = function(idx)
      ctx.xyYIdx = idx
      local names = getParamNames(ctx.fxType)
      ctx.xyYName = names[idx] or "Y"
      refreshPad(ctx)
    end
  end

  -- Knob assignment dropdowns
  local k1Drop = ctx.widgets.knob1_dropdown
  if k1Drop then
    k1Drop._onSelect = function(idx)
      ctx.knob1Idx = idx
      local names = getParamNames(ctx.fxType)
      local k1 = ctx.widgets.knob1
      if k1 then k1._label = names[idx] or "P1"; if k1._syncRetained then k1:_syncRetained() end end
    end
  end
  local k2Drop = ctx.widgets.knob2_dropdown
  if k2Drop then
    k2Drop._onSelect = function(idx)
      ctx.knob2Idx = idx
      local names = getParamNames(ctx.fxType)
      local k2 = ctx.widgets.knob2
      if k2 then k2._label = names[idx] or "P2"; if k2._syncRetained then k2:_syncRetained() end end
    end
  end
end

function FxSlotBehavior.init(ctx)
  ctx.fxType = 0
  ctx.xyX = 0.5
  ctx.xyY = 0.5
  ctx.xyXIdx = 1
  ctx.xyYIdx = 2
  ctx.xyXName = "Rate"
  ctx.xyYName = "Depth"
  ctx.knob1Idx = 1
  ctx.knob2Idx = 2
  ctx.dragging = false
  ctx.accentColor = 0xff22d3ee
  setupInteraction(ctx)
  syncAllDropdowns(ctx)
  -- Expose lightweight refresh for per-frame updates from main behavior
  ctx._refreshPad = function() refreshPad(ctx) end
  refreshPad(ctx)
end

-- Called when effect type changes — repopulate dropdowns + labels
function FxSlotBehavior.onTypeChanged(ctx)
  syncAllDropdowns(ctx)
  refreshPad(ctx)
end

function FxSlotBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets
  local p = 16
  local ddH = 20
  local knobH = math.min(70, math.floor(h * 0.22))
  local innerW = w - p * 2

  -- Title
  local title = widgets.title
  if title then
    if title.setBounds then title:setBounds(p, 8, innerW, 16)
    elseif title.node then title.node:setBounds(p, 8, innerW, 16) end
  end

  -- Type dropdown
  local dd = widgets.type_dropdown
  if dd then
    if dd.setBounds then dd:setBounds(p, 28, innerW, 24)
    elseif dd.node then dd.node:setBounds(p, 28, innerW, 24) end
  end

  -- XY pad
  local padY = 56
  -- Reserve: xy_dd row + knob_dd row + knobs row + gaps
  local reserveBelow = ddH + 4 + ddH + 4 + knobH + 4
  local padH = math.max(40, h - padY - reserveBelow - p)
  local xyPad = widgets.xy_pad
  if xyPad then
    if xyPad.setBounds then xyPad:setBounds(p, padY, innerW, padH)
    elseif xyPad.node then xyPad.node:setBounds(p, padY, innerW, padH) end
  end

  -- XY param dropdowns
  local xyDdY = padY + padH + 4
  local halfW = math.floor((innerW - 8) / 2)
  local xyXDrop = widgets.xy_x_dropdown
  if xyXDrop then
    if xyXDrop.setBounds then xyXDrop:setBounds(p, xyDdY, halfW, ddH)
    elseif xyXDrop.node then xyXDrop.node:setBounds(p, xyDdY, halfW, ddH) end
  end
  local xyYDrop = widgets.xy_y_dropdown
  if xyYDrop then
    if xyYDrop.setBounds then xyYDrop:setBounds(p + halfW + 8, xyDdY, halfW, ddH)
    elseif xyYDrop.node then xyYDrop.node:setBounds(p + halfW + 8, xyDdY, halfW, ddH) end
  end

  -- Knob param dropdowns
  local knobDdY = xyDdY + ddH + 4
  local thirdW = math.floor((innerW - 16) / 3)
  local k1Drop = widgets.knob1_dropdown
  if k1Drop then
    if k1Drop.setBounds then k1Drop:setBounds(p, knobDdY, thirdW, ddH)
    elseif k1Drop.node then k1Drop.node:setBounds(p, knobDdY, thirdW, ddH) end
  end
  local k2Drop = widgets.knob2_dropdown
  if k2Drop then
    if k2Drop.setBounds then k2Drop:setBounds(p + thirdW + 8, knobDdY, thirdW, ddH)
    elseif k2Drop.node then k2Drop.node:setBounds(p + thirdW + 8, knobDdY, thirdW, ddH) end
  end

  -- Knobs row
  local knobY = knobDdY + ddH + 4
  local knobW = thirdW
  local k1 = widgets.knob1
  if k1 then
    if k1.setBounds then k1:setBounds(p, knobY, knobW, knobH)
    elseif k1.node then k1.node:setBounds(p, knobY, knobW, knobH) end
  end
  local k2 = widgets.knob2
  if k2 then
    if k2.setBounds then k2:setBounds(p + knobW + 8, knobY, knobW, knobH)
    elseif k2.node then k2.node:setBounds(p + knobW + 8, knobY, knobW, knobH) end
  end
  local mk = widgets.mix_knob
  if mk then
    if mk.setBounds then mk:setBounds(p + (knobW + 8) * 2, knobY, knobW, knobH)
    elseif mk.node then mk.node:setBounds(p + (knobW + 8) * 2, knobY, knobW, knobH) end
  end

  refreshPad(ctx)
end

return FxSlotBehavior

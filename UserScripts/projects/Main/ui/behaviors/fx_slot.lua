-- FX Slot component behavior
-- XY pad + all real effect params for the selected FX type.
local FxSlotBehavior = {}

local FX_TYPE_NAMES = {
  [0] = "CHORUS",
  [1] = "PHASER",
  [2] = "WAVESHAPER",
  [3] = "COMPRESSOR",
  [4] = "STEREO WIDENER",
  [5] = "FILTER",
  [6] = "SVF FILTER",
  [7] = "REVERB",
  [8] = "STEREO DELAY",
  [9] = "MULTITAP",
  [10] = "PITCH SHIFT",
  [11] = "GRANULATOR",
  [12] = "RING MOD",
  [13] = "FORMANT",
  [14] = "EQ",
  [15] = "LIMITER",
  [16] = "TRANSIENT",
}

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

local MAX_VISIBLE_PARAMS = 5

local function getParamNames(fxType)
  return FX_PARAMS[fxType or 0] or { "Param 1", "Param 2" }
end

local function getParamWidgets(ctx)
  return {
    ctx.widgets.param1,
    ctx.widgets.param2,
    ctx.widgets.param3,
    ctx.widgets.param4,
    ctx.widgets.param5,
  }
end

local function setWidgetVisible(widget, visible)
  if widget and widget.setVisible then
    widget:setVisible(visible)
  end
end

local function buildXYDisplay(ctx, w, h)
  local display = {}
  local xVal = ctx.xyX or 0.5
  local yVal = ctx.xyY or 0.5
  local dragging = ctx.dragging
  local col = ctx.accentColor or 0xff22d3ee
  local colDim = (0x18 << 24) | (col & 0x00ffffff)
  local colMid = (0x44 << 24) | (col & 0x00ffffff)

  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = ctx.fxName or "FX", color = col, fontSize = 11, align = "left", valign = "top",
  }

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

local function updateParamControls(ctx)
  local names = getParamNames(ctx.fxType)
  ctx.paramNames = names

  local paramWidgets = getParamWidgets(ctx)
  for i = 1, #paramWidgets do
    local widget = paramWidgets[i]
    local name = names[i]
    if widget then
      widget._label = name or ("P" .. tostring(i))
      if widget._syncRetained then widget:_syncRetained() end
      setWidgetVisible(widget, name ~= nil)
    end
  end
end

local function syncAllDropdowns(ctx)
  local names = getParamNames(ctx.fxType)
  ctx.xyXIdx = populateDropdown(ctx.widgets.xy_x_dropdown, names, ctx.xyXIdx or 1)
  ctx.xyYIdx = populateDropdown(ctx.widgets.xy_y_dropdown, names, ctx.xyYIdx or math.min(2, #names))
  ctx.xyXName = names[ctx.xyXIdx] or "X"
  ctx.xyYName = names[ctx.xyYIdx] or "Y"
  updateParamControls(ctx)
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
end

function FxSlotBehavior.init(ctx)
  ctx.fxType = 0
  ctx.fxName = FX_TYPE_NAMES[0] or "FX"
  ctx.xyX = 0.5
  ctx.xyY = 0.5
  ctx.xyXIdx = 1
  ctx.xyYIdx = 2
  ctx.xyXName = "Rate"
  ctx.xyYName = "Depth"
  ctx.dragging = false
  ctx.accentColor = 0xff22d3ee
  ctx.paramNames = getParamNames(ctx.fxType)
  setupInteraction(ctx)
  syncAllDropdowns(ctx)
  ctx._refreshPad = function() refreshPad(ctx) end
  refreshPad(ctx)
end

function FxSlotBehavior.onTypeChanged(ctx)
  local names = getParamNames(ctx.fxType)
  ctx.fxName = FX_TYPE_NAMES[ctx.fxType] or "FX"
  if ctx.xyXIdx > #names then ctx.xyXIdx = 1 end
  if ctx.xyYIdx > #names then ctx.xyYIdx = math.min(2, #names) end
  if ctx.xyYIdx < 1 then ctx.xyYIdx = 1 end
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
  local pad = 10
  local gap = 6

  local xyPad = widgets.xy_pad
  local dd = widgets.type_dropdown
  local xyXLabel = widgets.xy_x_label
  local xyX = widgets.xy_x_dropdown
  local xyYLabel = widgets.xy_y_label
  local xyY = widgets.xy_y_dropdown
  local mix = widgets.mix_knob
  local paramWidgets = getParamWidgets(ctx)

  if w < 300 then
    if xyPad then
      if xyPad.setBounds then xyPad:setBounds(pad, pad, w - pad * 2, h - pad * 2)
      elseif xyPad.node then xyPad.node:setBounds(pad, pad, w - pad * 2, h - pad * 2) end
    end
    setWidgetVisible(dd, false)
    setWidgetVisible(xyXLabel, false)
    setWidgetVisible(xyX, false)
    setWidgetVisible(xyYLabel, false)
    setWidgetVisible(xyY, false)
    setWidgetVisible(mix, false)
    for i = 1, #paramWidgets do
      setWidgetVisible(paramWidgets[i], false)
    end
  else
    setWidgetVisible(dd, true)
    setWidgetVisible(xyXLabel, true)
    setWidgetVisible(xyX, true)
    setWidgetVisible(xyYLabel, true)
    setWidgetVisible(xyY, true)
    setWidgetVisible(mix, true)

    local split = math.floor(w / 2)
    local leftW = split - pad
    local rightX = split + gap
    local rightW = w - rightX - pad

    if xyPad then
      if xyPad.setBounds then xyPad:setBounds(pad, pad, leftW, h - pad * 2)
      elseif xyPad.node then xyPad.node:setBounds(pad, pad, leftW, h - pad * 2) end
    end

    local topRowH = 18
    local sectionGap = 4
    local labelW = 10
    local typeW = math.max(72, math.floor(rightW * 0.48))
    local remainingW = math.max(40, rightW - typeW - sectionGap * 2)
    local xSectionW = math.floor(remainingW / 2)
    local ySectionW = remainingW - xSectionW
    local rowY = pad

    if dd then
      if dd.setBounds then dd:setBounds(rightX, rowY, typeW, topRowH)
      elseif dd.node then dd.node:setBounds(rightX, rowY, typeW, topRowH) end
    end

    local xSectionX = rightX + typeW + sectionGap
    local ySectionX = xSectionX + xSectionW + sectionGap

    if xyXLabel then
      if xyXLabel.setBounds then xyXLabel:setBounds(xSectionX, rowY + 2, labelW, 14)
      elseif xyXLabel.node then xyXLabel.node:setBounds(xSectionX, rowY + 2, labelW, 14) end
    end
    if xyX then
      if xyX.setBounds then xyX:setBounds(xSectionX + labelW, rowY, math.max(16, xSectionW - labelW), topRowH)
      elseif xyX.node then xyX.node:setBounds(xSectionX + labelW, rowY, math.max(16, xSectionW - labelW), topRowH) end
    end
    if xyYLabel then
      if xyYLabel.setBounds then xyYLabel:setBounds(ySectionX, rowY + 2, labelW, 14)
      elseif xyYLabel.node then xyYLabel.node:setBounds(ySectionX, rowY + 2, labelW, 14) end
    end
    if xyY then
      if xyY.setBounds then xyY:setBounds(ySectionX + labelW, rowY, math.max(16, ySectionW - labelW), topRowH)
      elseif xyY.node then xyY.node:setBounds(ySectionX + labelW, rowY, math.max(16, ySectionW - labelW), topRowH) end
    end

    local sliderY = rowY + topRowH + gap
    local sliderH = 20
    local sliderGap = 4

    if mix then
      if mix.setBounds then mix:setBounds(rightX, sliderY, rightW, sliderH)
      elseif mix.node then mix.node:setBounds(rightX, sliderY, rightW, sliderH) end
    end

    local names = getParamNames(ctx.fxType)
    for i = 1, MAX_VISIBLE_PARAMS do
      local widget = paramWidgets[i]
      local visible = names[i] ~= nil
      setWidgetVisible(widget, visible)
      if visible and widget then
        local y = sliderY + (sliderH + sliderGap) * i
        if widget.setBounds then widget:setBounds(rightX, y, rightW, sliderH)
        elseif widget.node then widget.node:setBounds(rightX, y, rightW, sliderH) end
      end
    end
  end

  refreshPad(ctx)
end

return FxSlotBehavior

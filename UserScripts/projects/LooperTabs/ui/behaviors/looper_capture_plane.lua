local Shared = require("behaviors.looper_shared_state")

local M = {}

local function makeStripDraw(ctx, bars, label)
  local rangeStartBars, rangeEndBars = Shared.segmentRangeForBars(bars)

  return function(node)
    local state = ctx._state or {}
    local w = node:getWidth()
    local h = node:getHeight()

    gfx.setColour(0xff0f1b2d)
    gfx.fillRect(0, 0, w, h)
    gfx.setColour(0x22ffffff)
    gfx.drawHorizontalLine(math.floor(h / 2), 0, w)

    local spb = state.samplesPerBar or 88200
    local sampleStart = math.floor(rangeStartBars * spb)
    local sampleEnd = math.floor(rangeEndBars * spb)
    local captureSize = state.captureSize or 0
    local clippedStart = math.max(0, math.min(captureSize, sampleStart))
    local clippedEnd = math.max(0, math.min(captureSize, sampleEnd))

    if clippedEnd > clippedStart and w > 4 then
      local numBuckets = math.min(w - 4, 128)
      local peaks = getCapturePeaks(clippedStart, clippedEnd, numBuckets)
      if peaks and #peaks > 0 then
        local centerY = h / 2
        local gain = h * 0.45
        gfx.setColour(0xff22d3ee)
        for x = 1, #peaks do
          local peak = peaks[x]
          local ph = peak * gain
          local px = 2 + (x - 1) * ((w - 4) / #peaks)
          gfx.drawVerticalLine(math.floor(px), centerY - ph, centerY + ph)
        end
      end
    end

    gfx.setColour(0x40475569)
    gfx.drawRect(0, 0, w, h)
    gfx.setColour(0xffcbd5e1)
    gfx.setFont(10.0)
    gfx.drawText(label, 4, h - 16, w - 8, 14, Justify.bottomLeft)
  end
end

local function makeOverlayDraw(ctx, bars, label)
  return function(node)
    local state = ctx._state or {}
    local w = node:getWidth()
    local h = node:getHeight()
    local hovered = node:isMouseOver()
    local armed = state.forwardArmed and math.abs((state.forwardBars or 0) - bars) < 0.001

    if hovered then
      gfx.setColour(0x2a60a5fa)
      gfx.fillRect(0, 0, w, h)
      gfx.setColour(0xff60a5fa)
      gfx.drawRect(0, 0, w, h, 1)
    end

    if armed then
      gfx.setColour(0x3384cc16)
      gfx.fillRect(0, 0, w, h)
      gfx.setColour(0xff84cc16)
      gfx.drawRect(0, 0, w, h, 2)
    end

    if hovered or armed then
      local tc = armed and 0xffd9f99d or 0xffbfdbfe
      gfx.setColour(tc)
      gfx.setFont(12.0)
      gfx.drawText(label .. " bars", 6, 0, w - 12, 20, Justify.topRight)
    end
  end
end

function M.init(ctx)
  local widgets = ctx.widgets or {}
  ctx._strips = {}
  ctx._segments = {}
  ctx._state = {}

  if widgets.captureTitle then
    widgets.captureTitle:setText("")
  end

  for slot = 1, #Shared.kSegmentBars do
    local barsIndex = #Shared.kSegmentBars + 1 - slot
    local bars = Shared.kSegmentBars[barsIndex]
    local label = Shared.kSegmentLabels[barsIndex]

    local strip = widgets["strip_" .. tostring(slot)]
    if strip and strip.node then
      strip.node:setOnDraw(makeStripDraw(ctx, bars, label))
      ctx._strips[#ctx._strips + 1] = {
        widget = strip,
        slot = slot,
        barsIndex = barsIndex,
        bars = bars,
        label = label,
      }
    end
  end

  for i = #Shared.kSegmentBars, 1, -1 do
    local widget = widgets["segment_hit_" .. tostring(i)]
    if widget and widget.node then
      local bars = Shared.kSegmentBars[i]
      local label = Shared.kSegmentLabels[i]
      widget.node:setOnClick(function()
        local state = ctx._state or {}
        if state.recordMode == "traditional" then
          Shared.commandSet("/core/behavior/forward", bars)
        else
          Shared.commandSet("/core/behavior/commit", bars)
        end
      end)
      widget.node:setOnDraw(makeOverlayDraw(ctx, bars, label))
      ctx._segments[#ctx._segments + 1] = { widget = widget, bars = bars, label = label, index = i }
    end
  end
end

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)

  if widgets.captureTitle then
    Shared.applySpecRect(widgets.captureTitle, Shared.getChildSpec(ctx, "captureTitle"), w, h, designW, designH)
  end

  for slot = 1, #Shared.kSegmentBars do
    local stripId = "strip_" .. tostring(slot)
    Shared.applySpecRect(widgets[stripId], Shared.getChildSpec(ctx, stripId), w, h, designW, designH)
  end

  for i = 1, #Shared.kSegmentBars do
    local segId = "segment_hit_" .. tostring(i)
    Shared.applySpecRect(widgets[segId], Shared.getChildSpec(ctx, segId), w, h, designW, designH)
  end
end

function M.update(ctx, rawState)
  ctx._state = Shared.normalizeState(rawState)
end

function M.cleanup(ctx)
end

return M

local Shared = require("behaviors.looper_shared_state")

local M = {}

local function setTransparentStyle(node)
  if node and node.setStyle then
    node:setStyle({ bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
  end
end

local function attachRetainedDraw(node, drawFn)
  if node == nil or drawFn == nil then
    return
  end
  if node.setOnDraw ~= nil then
    node:setOnDraw(drawFn)
  end
  drawFn(node)
end

local function refreshDrawEntries(entries)
  for i = 1, #(entries or {}) do
    local entry = entries[i]
    if entry and entry.node and entry.draw then
      entry.draw(entry.node)
    end
  end
end

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

    local display = {
      {
        cmd = "fillRect",
        x = 0,
        y = 0,
        w = w,
        h = h,
        color = 0xff0f1b2d,
      },
      {
        cmd = "drawLine",
        x1 = 0,
        y1 = math.floor(h / 2),
        x2 = w,
        y2 = math.floor(h / 2),
        thickness = 1,
        color = 0x22ffffff,
      }
    }

    local spb = state.samplesPerBar or 88200
    local sampleStart = math.floor(rangeStartBars * spb)
    local sampleEnd = math.floor(rangeEndBars * spb)
    local captureSize = state.captureSize or 0
    local clippedStart = math.max(0, math.min(captureSize, sampleStart))
    local clippedEnd = math.max(0, math.min(captureSize, sampleEnd))

    if clippedEnd > clippedStart and w > 4 and type(getCapturePeaksAtPath) == "function" then
      local numBuckets = math.min(w - 4, 128)
      local activeLayer = state.activeLayer or 0
      local capturePath = string.format("/core/behavior/layer/%d/parts/capture", activeLayer)
      local peaks = getCapturePeaksAtPath(capturePath, clippedStart, clippedEnd, numBuckets)
      if peaks and #peaks > 0 then
        local centerY = h / 2
        local gain = h * 0.45
        gfx.setColour(0xff22d3ee)
        for x = 1, #peaks do
          local peak = peaks[x]
          local ph = peak * gain
          local px = 2 + (x - 1) * ((w - 4) / #peaks)
          local ix = math.floor(px)
          gfx.drawVerticalLine(ix, centerY - ph, centerY + ph)
          display[#display + 1] = {
            cmd = "drawLine",
            x1 = ix,
            y1 = centerY - ph,
            x2 = ix,
            y2 = centerY + ph,
            thickness = 1,
            color = 0xff22d3ee,
          }
        end
      end
    end

    gfx.setColour(0x40475569)
    gfx.drawRect(0, 0, w, h)
    gfx.setColour(0xffcbd5e1)
    gfx.setFont(10.0)
    gfx.drawText(label, 4, h - 16, w - 8, 14, Justify.bottomLeft)

    display[#display + 1] = {
      cmd = "drawRect",
      x = 0,
      y = 0,
      w = w,
      h = h,
      thickness = 1,
      color = 0x40475569,
    }
    display[#display + 1] = {
      cmd = "drawText",
      x = 4,
      y = h - 16,
      w = math.max(0, w - 8),
      h = 14,
      color = 0xffcbd5e1,
      text = label,
      fontSize = 10.0,
      align = "left",
      valign = "bottom",
    }

    if node.setDisplayList then
      setTransparentStyle(node)
      node:setDisplayList(display)
    end
  end
end

local function makeOverlayDraw(ctx, bars, label)
  return function(node)
    local state = ctx._state or {}
    local w = node:getWidth()
    local h = node:getHeight()
    local hovered = node:isMouseOver()
    local armed = state.forwardArmed and math.abs((state.forwardBars or 0) - bars) < 0.001
    local display = {}

    if hovered then
      gfx.setColour(0x2a60a5fa)
      gfx.fillRect(0, 0, w, h)
      gfx.setColour(0xff60a5fa)
      gfx.drawRect(0, 0, w, h, 1)
      display[#display + 1] = {
        cmd = "fillRect",
        x = 0,
        y = 0,
        w = w,
        h = h,
        color = 0x2a60a5fa,
      }
      display[#display + 1] = {
        cmd = "drawRect",
        x = 0,
        y = 0,
        w = w,
        h = h,
        thickness = 1,
        color = 0xff60a5fa,
      }
    end

    if armed then
      gfx.setColour(0x3384cc16)
      gfx.fillRect(0, 0, w, h)
      gfx.setColour(0xff84cc16)
      gfx.drawRect(0, 0, w, h, 2)
      display[#display + 1] = {
        cmd = "fillRect",
        x = 0,
        y = 0,
        w = w,
        h = h,
        color = 0x3384cc16,
      }
      display[#display + 1] = {
        cmd = "drawRect",
        x = 0,
        y = 0,
        w = w,
        h = h,
        thickness = 2,
        color = 0xff84cc16,
      }
    end

    if hovered or armed then
      local tc = armed and 0xffd9f99d or 0xffbfdbfe
      gfx.setColour(tc)
      gfx.setFont(12.0)
      gfx.drawText(label .. " bars", 6, 0, w - 12, 20, Justify.topRight)
      display[#display + 1] = {
        cmd = "drawText",
        x = 6,
        y = 0,
        w = math.max(0, w - 12),
        h = 20,
        color = tc,
        text = label .. " bars",
        fontSize = 12.0,
        align = "right",
        valign = "top",
      }
    end

    if node.setDisplayList then
      setTransparentStyle(node)
      if #display > 0 then
        node:setDisplayList(display)
      else
        node:clearDisplayList()
      end
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
      local draw = makeStripDraw(ctx, bars, label)
      attachRetainedDraw(strip.node, draw)
      ctx._strips[#ctx._strips + 1] = {
        widget = strip,
        node = strip.node,
        draw = draw,
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
      local draw = makeOverlayDraw(ctx, bars, label)
      widget.node:setOnClick(function()
        local state = ctx._state or {}
        if state.recordMode == "traditional" then
          Shared.commandSet("/core/behavior/forward", bars)
        else
          Shared.commandSet("/core/behavior/commit", bars)
        end
      end)
      attachRetainedDraw(widget.node, draw)
      ctx._segments[#ctx._segments + 1] = { widget = widget, node = widget.node, draw = draw, bars = bars, label = label, index = i }
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

  refreshDrawEntries(ctx._strips)
  refreshDrawEntries(ctx._segments)
end

function M.update(ctx, rawState)
  ctx._state = Shared.normalizeState(rawState)
  refreshDrawEntries(ctx._strips)
  refreshDrawEntries(ctx._segments)
end

function M.cleanup(ctx)
end

return M

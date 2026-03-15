-- Oscillator component behavior - waveform preview + voice playthrough
local OscBehavior = {}

local WAVEFORM_COLORS = {
  [0] = 0xff7dd3fc,  -- sine
  [1] = 0xff38bdf8,  -- saw
  [2] = 0xff22d3ee,  -- square
  [3] = 0xff2dd4bf,  -- triangle
  [4] = 0xffa78bfa,  -- blend
}

local VOICE_COLORS = {
  0xff4ade80, 0xff38bdf8, 0xfffbbf24, 0xfff87171,
  0xffa78bfa, 0xff2dd4bf, 0xfffb923c, 0xfff472b6,
}

local function waveformSample(waveType, phase)
  local p = phase % 1.0
  if waveType == 0 then
    return math.sin(p * 2 * math.pi)
  elseif waveType == 1 then
    return 2 * p - 1
  elseif waveType == 2 then
    return p < 0.5 and 1 or -1
  elseif waveType == 3 then
    return p < 0.5 and (4 * p - 1) or (3 - 4 * p)
  elseif waveType == 4 then
    return ((2 * p - 1) + math.sin(p * 2 * math.pi)) * 0.5
  end
  return 0
end

local function softClip(s, drive)
  s = s * drive
  if s > 1 then return 1 - 1 / (1 + s)
  elseif s < -1 then return -1 + 1 / (1 - s) end
  return s
end

local SAMPLE_COLOR = 0xff22d3ee
local SAMPLE_DIM = 0x6022d3ee

local function buildSampleWaveform(ctx, w, h, display)
  local centerY = h / 2
  local maxAmp = (h / 2) * 0.75
  local numPoints = math.max(48, math.min(w, 200))
  local loopStart = ctx.sampleLoopStart or 0.0
  local loopLen = ctx.sampleLoopLen or 1.0

  -- Get sample peaks from the DSP (cache to avoid re-fetch on range changes)
  local peaks = ctx._cachedPeaks
  if not peaks and type(getSynthSamplePeaks) == "function" then
    peaks = getSynthSamplePeaks(numPoints)
    if peaks and #peaks > 0 then
      ctx._cachedPeaks = peaks
    end
  end



  -- Sample mode background (full width, static)
  display[#display + 1] = {
    cmd = "fillRect", x = 0, y = 0, w = w, h = h,
    color = 0x20ffffff,
  }

  -- Draw actual sample waveform from peaks
  if peaks and #peaks > 0 then
    local prevX, prevY
    for i = 0, numPoints do
      local t = i / numPoints
      local peakIdx = math.floor(t * (#peaks - 1)) + 1
      local peak = peaks[peakIdx] or 0
      local s = peak * 2 - 1 -- Convert 0..1 to -1..1

      local x = math.floor(t * w)
      local y = math.floor(centerY - s * maxAmp)
      if prevX then
        display[#display + 1] = {
          cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y,
          thickness = 1, color = SAMPLE_COLOR,
        }
      end
      prevX, prevY = x, y
    end

    -- Draw per-voice playheads - line tracks actual waveform height at position
    local samplePositions = {}
    if type(getVoiceSamplePositions) == "function" then
      samplePositions = getVoiceSamplePositions() or {}
    end
    
    -- Get voice loop data for mapping positions
    local voiceLoops = ctx.voiceLoops or {}
    
    -- Draw per-voice playheads - iterate in fixed voice order (1-8) to match ADSR
    local activeVoices = ctx.activeVoices or {}
    local voiceLookup = {}
    for _, v in ipairs(activeVoices) do
      local idx = v.voiceIndex
      if idx then voiceLookup[idx] = v end
    end
    
    for voiceIndex = 1, 8 do
      local voice = voiceLookup[voiceIndex]
      if not voice then goto continue end

      local vcol = VOICE_COLORS[voiceIndex]
      local pos = samplePositions[voiceIndex] or 0

      -- Map playhead to the voice's loop range area
      local loop = voiceLoops[voiceIndex]
      local vLoopStart = (loop and loop.start) or loopStart
      local vLoopLen = (loop and loop.len) or loopLen
      local playheadX = math.floor((vLoopStart + pos * vLoopLen) * w)

      -- Get waveform amplitude at this position from peaks
      local waveY = centerY
      if peaks and #peaks > 0 then
        local absPos = vLoopStart + pos * vLoopLen
        local peakIdx = math.floor(absPos * (#peaks - 1)) + 1
        local peak = peaks[peakIdx] or 0.5
        local s = peak * 2 - 1  -- Convert 0..1 to -1..1
        waveY = math.floor(centerY - s * maxAmp)
      end

      -- Draw line from bottom up to waveform at this position
      display[#display + 1] = {
        cmd = "drawLine", x1 = playheadX, y1 = h - 2, x2 = playheadX, y2 = waveY,
        thickness = 3, color = vcol,
      }
      ::continue::
    end

    -- Draw interactive range bar at bottom
    local rangeView = ctx.rangeView or "all"
    local voiceLoops = ctx.voiceLoops or {}
    local barH = 20
    local barY = h - barH
    local handleW = 8
    local handleH = barH - 4
    
    -- Thin divider line between waveform and bar
    display[#display + 1] = {
      cmd = "drawLine", x1 = 0, y1 = math.floor(barY), x2 = w, y2 = math.floor(barY),
      thickness = 1, color = 0xff334155,
    }
    
    -- Bar background (neutral, matches sample viewer)
    display[#display + 1] = {
      cmd = "fillRect", x = 0, y = math.floor(barY) + 1, w = w, h = barH - 1,
      color = 0xff0d1420,
    }
    
    -- Global loop values for fallback
    local gStart = loopStart
    local gEnd = loopStart + loopLen
    
    local function drawHandle(x, y, hW, hH, fillColor, borderColor)
      -- Fill
      display[#display + 1] = {
        cmd = "fillRect", x = x, y = y, w = hW, h = hH,
        color = fillColor,
      }
      -- Border
      display[#display + 1] = {
        cmd = "drawRect", x = x, y = y, w = hW, h = hH,
        thickness = 1, color = borderColor,
      }
    end
    
    if rangeView == "all" then
      -- Draw all 8 voice handles overlaid
      for voiceIndex = 1, 8 do
        local loop = voiceLoops[voiceIndex]
        local vStart = (loop and loop.start) or gStart
        local vLen = (loop and loop.len) or (gEnd - gStart)
        local vEnd = vStart + vLen
        local startX = math.max(0, math.floor(vStart * w) - math.floor(handleW / 2))
        local endX = math.min(w - handleW, math.floor(vEnd * w) - math.floor(handleW / 2))
        local vcol = VOICE_COLORS[voiceIndex]
        local handleY = math.floor(barY) + 2
        -- Start handle: voice color with white border
        drawHandle(startX, handleY, handleW, handleH, vcol, 0xffffffff)
        -- End handle: voice color with black border
        drawHandle(endX, handleY, handleW, handleH, vcol, 0xff000000)
      end
    elseif rangeView == "global" then
      -- Draw global handles (gray fill)
      local startX = math.max(0, math.floor(gStart * w) - math.floor(handleW / 2))
      local endX = math.min(w - handleW, math.floor(gEnd * w) - math.floor(handleW / 2))
      local handleY = math.floor(barY) + 2
      -- Start handle: gray with white border
      drawHandle(startX, handleY, handleW, handleH, 0xff888888, 0xffffffff)
      -- End handle: gray with black border
      drawHandle(endX, handleY, handleW, handleH, 0xff888888, 0xff000000)
    elseif rangeView:match("^voice%d$") then
      -- Draw specific voice handles
      local voiceIndex = tonumber(rangeView:match("%d"))
      local loop = voiceLoops[voiceIndex]
      local vStart = (loop and loop.start) or gStart
      local vEnd = vStart + ((loop and loop.len) or (gEnd - gStart))
      local startX = math.max(0, math.floor(vStart * w) - math.floor(handleW / 2))
      local endX = math.min(w - handleW, math.floor(vEnd * w) - math.floor(handleW / 2))
      local vcol = VOICE_COLORS[voiceIndex]
      local handleY = math.floor(barY) + 2
      -- Start handle: voice color with white border
      drawHandle(startX, handleY, handleW, handleH, vcol, 0xffffffff)
      -- End handle: voice color with black border
      drawHandle(endX, handleY, handleW, handleH, vcol, 0xff000000)
    end
  else
    -- No sample captured yet - show placeholder
    display[#display + 1] = {
      cmd = "drawText", x = 0, y = math.floor(h / 2) - 8, w = w, h = 16,
      text = "No sample captured", color = 0xff94a3b8, fontSize = 11, align = "center", valign = "middle",
    }
  end

  -- Draw "SAMPLE" label
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "SAMPLE MODE", color = 0xffa78bfa, fontSize = 10, align = "left", valign = "top",
  }

  return display
end

local function buildOscDisplay(ctx, w, h)
  local display = {}
  local waveType = ctx.waveformType or 1
  local noiseLevel = ctx.noiseLevel or 0
  local noiseColor = ctx.noiseColor or 0.1
  local drive = math.max(0.1, ctx.driveAmount or 1.8)
  local voices = ctx.activeVoices or {}
  local time = ctx.animTime or 0
  local oscMode = ctx.oscMode or 0

  -- Grid
  for i = 1, 3 do
    display[#display + 1] = {
      cmd = "drawLine", x1 = 0, y1 = math.floor(h * i / 4), x2 = w, y2 = math.floor(h * i / 4),
      thickness = 1, color = 0xff1a1a3a,
    }
  end
  display[#display + 1] = {
    cmd = "drawLine", x1 = 0, y1 = math.floor(h / 2), x2 = w, y2 = math.floor(h / 2),
    thickness = 1, color = 0xff1f2b4d,
  }

  -- Sample mode: render sample-style waveform with loop markers
  if oscMode == 1 then
    return buildSampleWaveform(ctx, w, h, display)
  end

  local col = WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local centerY = h / 2
  local maxAmp = (h / 2) * 0.85
  local pointCap = math.max(48, tonumber(ctx.maxPoints) or 200)
  local numPoints = math.max(48, math.min(w, pointCap))

  -- Static waveform shape (dim reference)
  local colStatic = (0x40 << 24) | (col & 0x00ffffff)
  local prevX, prevY
  for i = 0, numPoints do
    local t = i / numPoints
    local s = waveformSample(waveType, t)
    s = softClip(s, drive)

    -- Add noise to static shape
    if noiseLevel > 0.01 then
      local hash = math.sin(i * 127.1 + noiseColor * 311.7) * 43758.5453
      hash = hash - math.floor(hash)
      local smoothN = math.sin(i * 0.15 + noiseColor * 5) * 0.5
      local whiteN = (hash - 0.5) * 2
      s = s + (smoothN * (1 - noiseColor) + whiteN * noiseColor) * noiseLevel * 0.4
    end

    local x = math.floor(t * w)
    local y = math.floor(centerY - s * maxAmp)
    if prevX then
      display[#display + 1] = {
        cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y,
        thickness = 1, color = colStatic,
      }
    end
    prevX, prevY = x, y
  end

  -- Per-voice animated waveforms
  if #voices > 0 then
    local drawFill = (#voices <= 1)
    for vi, voice in ipairs(voices) do
      local vcol = VOICE_COLORS[((vi - 1) % #VOICE_COLORS) + 1]
      local vcolDim = (0x20 << 24) | (vcol & 0x00ffffff)
      local freq = voice.freq or 220
      local amp = voice.amp or 0
      if amp < 0.001 then goto continue end

      -- Phase offset based on time and frequency — show ~2 cycles in the view
      local cyclesInView = 2
      local phaseOffset = time * freq
      local vPrevX, vPrevY

      for i = 0, numPoints do
        local t = i / numPoints
        local phase = phaseOffset + t * cyclesInView
        local s = waveformSample(waveType, phase)
        s = softClip(s, drive)

        -- Add animated noise
        if noiseLevel > 0.01 then
          local noisePhase = phase * 17.3 + time * 3.7
          local hash = math.sin(noisePhase * 127.1 + noiseColor * 311.7) * 43758.5453
          hash = hash - math.floor(hash)
          local smoothN = math.sin(noisePhase * 0.8) * 0.5
          local whiteN = (hash - 0.5) * 2
          s = s + (smoothN * (1 - noiseColor) + whiteN * noiseColor) * noiseLevel * 0.4
        end

        s = s * (amp / 0.5) -- scale by voice amplitude (max 0.5)
        local x = math.floor(t * w)
        local y = math.floor(centerY - s * maxAmp)

        -- Fill to center (only for single-voice display to keep multi-voice
        -- interactions responsive)
        if drawFill and i > 0 then
          display[#display + 1] = {
            cmd = "drawLine", x1 = x, y1 = y, x2 = x, y2 = math.floor(centerY),
            thickness = math.max(1, math.ceil(w / numPoints)), color = vcolDim,
          }
        end

        if vPrevX then
          display[#display + 1] = {
            cmd = "drawLine", x1 = vPrevX, y1 = vPrevY, x2 = x, y2 = y,
            thickness = 2, color = vcol,
          }
        end
        vPrevX, vPrevY = x, y
      end

      ::continue::
    end
  end

  -- Noise indicator bar
  if noiseLevel > 0.01 then
    display[#display + 1] = {
      cmd = "fillRect", x = 0, y = h - 3, w = math.floor(w * noiseLevel), h = 3,
      color = 0x6694a3b8,
    }
  end

  return display
end

local function refreshGraph(ctx)
  local graph = ctx.widgets.osc_graph
  if not graph or not graph.node then return end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then return end
  -- Fetch voice loop data from DSP
  if type(getVoiceLoopData) == "function" then
    ctx.voiceLoops = getVoiceLoopData()
  end
  graph.node:setDisplayList(buildOscDisplay(ctx, w, h))
  graph.node:repaint()
end

function OscBehavior.init(ctx)
  ctx.waveformType = 1
  ctx.driveAmount = 1.8
  ctx.outputLevel = 0.8
  ctx.noiseLevel = 0.0
  ctx.noiseColor = 0.1
  ctx.activeVoices = {}
  ctx.animTime = 0
  ctx.oscMode = 0
  ctx.sampleLoopStart = 0.0
  ctx.sampleLoopLen = 1.0
  ctx.rangeView = "all"
  ctx.rangeViewIndex = 1
  ctx.voiceLoops = {}

  -- Range bar mouse interaction state
  ctx._rangeDrag = {
    active = false,
    dragging = nil,
    voiceIndex = nil,
  }

  refreshGraph(ctx)
end

function OscBehavior.resized(ctx, w, h)
  if (not w or w <= 0) and ctx.root and ctx.root.node then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if not w or w <= 0 then return end

  local widgets = ctx.widgets
  local pad = 12
  local gap = 4
  local contentW = math.max(1, w - pad * 2)

  local title = widgets.title
  if title then
    if title.setBounds then title:setBounds(pad, 8, contentW, 16)
    elseif title.node then title.node:setBounds(pad, 8, contentW, 16) end
  end

  local graphY = 28
  local dropdownH = 22
  local labelH = 12
  local numberH = 26
  local toggleH = 22
  local knobH = math.max(44, math.min(58, math.floor(h * 0.22)))

  local row1H = labelH + 2 + dropdownH
  local row2H = dropdownH
  local row3H = numberH
  local row4H = numberH  -- Start%/Len% boxes
  local row5H = knobH
  local controlsH = row1H + gap + row2H + gap + row3H + gap + row4H + gap + row5H

  local graphH = math.max(24, h - graphY - controlsH - 8)
  local graph = widgets.osc_graph
  if graph then
    if graph.setBounds then graph:setBounds(pad, graphY, contentW, graphH)
    elseif graph.node then graph.node:setBounds(pad, graphY, contentW, graphH) end
    
    -- Set up mouse handlers for range bar (once)
    if graph.node and not ctx._rangeMouseSetup then
      ctx._rangeMouseSetup = true
      graph.node:setInterceptsMouse(true, false)
      
      graph.node:setOnMouseDown(function(mx, my)
        if ctx.oscMode ~= 1 then return end
        local gw = graph.node:getWidth()
        local gh = graph.node:getHeight()
        if gw <= 0 or gh <= 0 then return end
        
        local barH = 20
        local barY = gh - barH
        local handleW = 8
        
        if my < barY or my > barY + barH then return end
        
        local rangeView = ctx.rangeView or "all"
        if rangeView == "all" then return end
        
        local voiceLoops = ctx.voiceLoops or {}
        local loopStart = ctx.sampleLoopStart or 0.0
        local loopLen = ctx.sampleLoopLen or 1.0
        local gStart = loopStart
        local gEnd = loopStart + loopLen
        
        local vStart, vEnd
        if rangeView == "global" then
          vStart = gStart
          vEnd = gEnd
        elseif rangeView:match("^voice%d$") then
          local voiceIndex = tonumber(rangeView:match("%d"))
          local loop = voiceLoops[voiceIndex]
          vStart = (loop and loop.start) or gStart
          vEnd = vStart + ((loop and loop.len) or (gEnd - gStart))
        else
          return
        end
        
        -- Handles are centered on position
        local startX = math.floor(vStart * gw) - math.floor(handleW / 2)
        local endX = math.floor(vEnd * gw) - math.floor(handleW / 2)
        
        if mx >= startX - 2 and mx <= startX + handleW + 2 then
          ctx._rangeDrag.active = true
          ctx._rangeDrag.dragging = "start"
        elseif mx >= endX - 2 and mx <= endX + handleW + 2 then
          ctx._rangeDrag.active = true
          ctx._rangeDrag.dragging = "end"
        end
      end)
      
      graph.node:setOnMouseDrag(function(mx, my)
        if not ctx._rangeDrag.active then return end
        local gw = graph.node:getWidth()
        if gw <= 4 then return end
        
        local pos = math.max(0, math.min(1, mx / gw))
        local rangeView = ctx.rangeView or "all"
        local handleW = 8
        
        local loopStart = ctx.sampleLoopStart or 0.0
        local loopLen = ctx.sampleLoopLen or 1.0
        local voiceLoops = ctx.voiceLoops or {}
        
        if ctx._rangeDrag.dragging == "start" then
          local currentEnd
          if rangeView == "global" then
            currentEnd = loopStart + loopLen
          else
            local voiceIndex = tonumber(rangeView:match("%d"))
            local loop = voiceLoops[voiceIndex]
            currentEnd = (loop and loop.start or loopStart) + (loop and loop.len or loopLen)
          end
          pos = math.min(pos, currentEnd - 0.05)
          local newLen = currentEnd - pos
          
          if rangeView == "global" then
            if ctx._onRangeChange then
              ctx._onRangeChange("start", pos)
              ctx._onRangeChange("len", newLen)
            end
          else
            local voiceIndex = tonumber(rangeView:match("%d"))
            if ctx._onVoiceRangeChange then
              ctx._onVoiceRangeChange(voiceIndex, "start", pos)
              ctx._onVoiceRangeChange(voiceIndex, "len", newLen)
            end
          end
        elseif ctx._rangeDrag.dragging == "end" then
          local currentStart
          if rangeView == "global" then
            currentStart = loopStart
          else
            local voiceIndex = tonumber(rangeView:match("%d"))
            local loop = voiceLoops[voiceIndex]
            currentStart = loop and loop.start or loopStart
          end
          pos = math.max(pos, currentStart + 0.05)
          
          if rangeView == "global" then
            if ctx._onRangeChange then ctx._onRangeChange("len", pos - currentStart) end
          else
            local voiceIndex = tonumber(rangeView:match("%d"))
            if ctx._onVoiceRangeChange then ctx._onVoiceRangeChange(voiceIndex, "len", pos - currentStart) end
          end
        end
        
      end)
      
      graph.node:setOnMouseUp(function()
        ctx._rangeDrag.active = false
        ctx._rangeDrag.dragging = nil
      end)
    end
  end

  local y = graphY + graphH + gap
  local colGap = 8
  local colW = math.max(60, math.floor((contentW - colGap) * 0.5))
  local col2X = pad + colW + colGap

  -- Row 1: waveform + mode
  local wfLabel = widgets.waveform_label
  if wfLabel then
    if wfLabel.setBounds then wfLabel:setBounds(pad, y, colW, labelH)
    elseif wfLabel.node then wfLabel.node:setBounds(pad, y, colW, labelH) end
  end
  local modeLabel = widgets.sample_mode_label
  if modeLabel then
    if modeLabel.setBounds then modeLabel:setBounds(col2X, y, colW, labelH)
    elseif modeLabel.node then modeLabel.node:setBounds(col2X, y, colW, labelH) end
  end

  local row1ControlY = y + labelH + 2
  local wfDrop = widgets.waveform_dropdown
  if wfDrop then
    if wfDrop.setBounds then wfDrop:setBounds(pad, row1ControlY, colW, dropdownH)
    elseif wfDrop.node then wfDrop.node:setBounds(pad, row1ControlY, colW, dropdownH) end
  end
  local modeDrop = widgets.sample_mode_dropdown
  if modeDrop then
    if modeDrop.setBounds then modeDrop:setBounds(col2X, row1ControlY, colW, dropdownH)
    elseif modeDrop.node then modeDrop.node:setBounds(col2X, row1ControlY, colW, dropdownH) end
  end

  -- Row 2: source + capture
  y = row1ControlY + dropdownH + gap
  local sourceLabel = widgets.sample_source_label
  if sourceLabel then
    if sourceLabel.setBounds then sourceLabel:setBounds(pad, y + 4, 42, labelH)
    elseif sourceLabel.node then sourceLabel.node:setBounds(pad, y + 4, 42, labelH) end
  end

  local sourceDrop = widgets.sample_source_dropdown
  if sourceDrop then
    local sourceX = pad + 44
    local sourceW = math.max(44, colW - 44)
    if sourceDrop.setBounds then sourceDrop:setBounds(sourceX, y, sourceW, dropdownH)
    elseif sourceDrop.node then sourceDrop.node:setBounds(sourceX, y, sourceW, dropdownH) end
  end

  local captureBtn = widgets.sample_capture_button
  if captureBtn then
    if captureBtn.setBounds then captureBtn:setBounds(col2X, y, colW, dropdownH)
    elseif captureBtn.node then captureBtn.node:setBounds(col2X, y, colW, dropdownH) end
  end

  -- Row 3: Bars, Root on left; Range dropdown on right
  y = y + dropdownH + gap
  local boxGap = 6
  local boxW = math.max(42, math.floor((contentW - boxGap * 3) / 4))
  
  -- Bars and Root on left
  local barsBox = widgets.sample_bars_box
  if barsBox then
    if barsBox.setBounds then barsBox:setBounds(pad, y, boxW, numberH)
    elseif barsBox.node then barsBox.node:setBounds(pad, y, boxW, numberH) end
  end
  local rootBox = widgets.sample_root_box
  if rootBox then
    if rootBox.setBounds then rootBox:setBounds(pad + boxW + boxGap, y, boxW, numberH)
    elseif rootBox.node then rootBox.node:setBounds(pad + boxW + boxGap, y, boxW, numberH) end
  end
  
  -- Range view dropdown on right (spans 2 box widths)
  local rangeDrop = widgets.range_view_dropdown
  if rangeDrop then
    local dropX = pad + (boxW + boxGap) * 2
    local dropW = (boxW + boxGap) * 2 - boxGap
    if rangeDrop.setBounds then rangeDrop:setBounds(dropX, y + 2, dropW, dropdownH)
    elseif rangeDrop.node then rangeDrop.node:setBounds(dropX, y + 2, dropW, dropdownH) end
  end

  -- Row 4: Start% and Len% boxes (editable range params)
  y = y + numberH + gap
  local startBox = widgets.sample_start_box
  if startBox then
    if startBox.setBounds then startBox:setBounds(pad, y, boxW, numberH)
    elseif startBox.node then startBox.node:setBounds(pad, y, boxW, numberH) end
  end
  local lenBox = widgets.sample_len_box
  if lenBox then
    if lenBox.setBounds then lenBox:setBounds(pad + boxW + boxGap, y, boxW, numberH)
    elseif lenBox.node then lenBox.node:setBounds(pad + boxW + boxGap, y, boxW, numberH) end
  end

  -- Row 5: classic tone knobs
  y = y + numberH + gap
  local knobW = math.max(44, math.floor((contentW - 18) / 4))
  local knobGap = math.max(4, math.floor((contentW - knobW * 4) / 3))
  local knobs = { "drive_knob", "output_knob", "noise_knob", "noise_color_knob" }
  for i, id in ipairs(knobs) do
    local knob = widgets[id]
    local kx = pad + (i - 1) * (knobW + knobGap)
    if knob then
      if knob.setBounds then knob:setBounds(kx, y, knobW, knobH)
      elseif knob.node then knob.node:setBounds(kx, y, knobW, knobH) end
    end
  end

  refreshGraph(ctx)
end

function OscBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return OscBehavior

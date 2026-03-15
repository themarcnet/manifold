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

local function buildOscDisplay(ctx, w, h)
  local display = {}
  local waveType = ctx.waveformType or 1
  local noiseLevel = ctx.noiseLevel or 0
  local noiseColor = ctx.noiseColor or 0.1
  local drive = math.max(0.1, ctx.driveAmount or 1.8)
  local voices = ctx.activeVoices or {}
  local time = ctx.animTime or 0

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

  local col = WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local centerY = h / 2
  local maxAmp = (h / 2) * 0.85
  local numPoints = math.max(60, math.min(w, 200))

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

        -- Fill to center
        if i > 0 then
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
  refreshGraph(ctx)
end

function OscBehavior.resized(ctx, w, h)
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
  local knobH = math.min(70, math.floor(h * 0.30))
  local dropdownH = 24
  local labelH = 14
  local graphH = math.max(30, h - graphY - labelH - 4 - dropdownH - 4 - knobH - 8)
  local graph = widgets.osc_graph
  if graph then
    if graph.setBounds then graph:setBounds(pad, graphY, w - pad * 2, graphH)
    elseif graph.node then graph.node:setBounds(pad, graphY, w - pad * 2, graphH) end
  end

  local ddY = graphY + graphH + 4
  local wfLabel = widgets.waveform_label
  if wfLabel then
    if wfLabel.setBounds then wfLabel:setBounds(pad, ddY, 60, labelH)
    elseif wfLabel.node then wfLabel.node:setBounds(pad, ddY, 60, labelH) end
  end
  ddY = ddY + labelH + 2
  local wfDrop = widgets.waveform_dropdown
  if wfDrop then
    if wfDrop.setBounds then wfDrop:setBounds(pad, ddY, math.floor((w - pad * 2) * 0.5), dropdownH)
    elseif wfDrop.node then wfDrop.node:setBounds(pad, ddY, math.floor((w - pad * 2) * 0.5), dropdownH) end
  end

  local knobY = ddY + dropdownH + 6
  local knobW = math.min(56, math.floor((w - pad * 2 - 18) / 4))
  local knobGap = math.floor((w - pad * 2 - knobW * 4) / 3)
  local knobs = { "drive_knob", "output_knob", "noise_knob", "noise_color_knob" }
  for i, id in ipairs(knobs) do
    local knob = widgets[id]
    local kx = pad + (i - 1) * (knobW + knobGap)
    if knob then
      if knob.setBounds then knob:setBounds(kx, knobY, knobW, knobH)
      elseif knob.node then knob.node:setBounds(kx, knobY, knobW, knobH) end
    end
  end

  refreshGraph(ctx)
end

function OscBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return OscBehavior

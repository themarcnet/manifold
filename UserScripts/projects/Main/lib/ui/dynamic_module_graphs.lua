local M = {}

local function floor(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function lerp(a, b, t)
  return a + ((b - a) * clamp(t, 0.0, 1.0))
end

local function copyArray(values)
  local out = {}
  for i = 1, #(values or {}) do
    out[i] = values[i]
  end
  return out
end

local function withAlpha(colour, alpha)
  local rgb = (tonumber(colour) or 0xffffffff) & 0x00ffffff
  local a = math.max(0, math.min(255, floor(alpha or 255)))
  return (a << 24) | rgb
end

local function addGrid(display, w, h, colour)
  local grid = colour or 0x1fffffff
  for i = 1, 3 do
    local x = floor(lerp(0, w, i / 4))
    local y = floor(lerp(0, h, i / 4))
    display[#display + 1] = { cmd = "drawLine", x1 = x, y1 = 0, x2 = x, y2 = h, thickness = 1, color = grid }
    display[#display + 1] = { cmd = "drawLine", x1 = 0, y1 = y, x2 = w, y2 = y, thickness = 1, color = grid }
  end
  display[#display + 1] = { cmd = "drawLine", x1 = 0, y1 = floor(h * 0.5), x2 = w, y2 = floor(h * 0.5), thickness = 1, color = withAlpha(0xffffffff, 42) }
end

local function addPolyline(display, points, colour, thickness)
  local prev = nil
  for i = 1, #(points or {}) do
    local point = points[i]
    if prev ~= nil and point ~= nil then
      display[#display + 1] = {
        cmd = "drawLine",
        x1 = floor(prev.x),
        y1 = floor(prev.y),
        x2 = floor(point.x),
        y2 = floor(point.y),
        thickness = thickness or 2,
        color = colour or 0xffffffff,
      }
    end
    prev = point
  end
end

local function addMarker(display, x, y, colour, size)
  local s = math.max(2, floor(size or 3))
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = floor(x - s), y = floor(y - s), w = s * 2, h = s * 2,
    radius = s, color = colour or 0xffffffff,
  }
end

local VOICE_COLORS = {
  0xff4ade80, 0xff38bdf8, 0xfffbbf24, 0xfff87171,
  0xffa78bfa, 0xff2dd4bf, 0xfffb923c, 0xfff472b6,
}

local function voiceColor(index)
  local i = math.max(1, math.floor(tonumber(index) or 1))
  return VOICE_COLORS[((i - 1) % #VOICE_COLORS) + 1] or 0xffffffff
end

local function copyVoiceEntries(view)
  local source = type(view) == "table" and view.activeVoices or nil
  local out = {}
  for i = 1, #(source or {}) do
    local voice = source[i]
    if type(voice) == "table" then
      out[#out + 1] = voice
    end
  end
  return out
end

local function mapBipolarY(value, top, bottom)
  return lerp(bottom, top, (clamp(value, -1.0, 1.0) + 1.0) * 0.5)
end

local function mapUnipolarY(value, top, bottom)
  return lerp(bottom, top, clamp(value, 0.0, 1.0))
end

local function mapMidiX(note, left, right)
  return lerp(left, right, clamp((tonumber(note) or 0.0) / 127.0, 0.0, 1.0))
end

local function seededStepValue(index)
  local seed = math.sin((tonumber(index) or 0) * 12.9898) * 43758.5453
  local frac = seed - math.floor(seed)
  return clamp((frac * 2.0) - 1.0, -1.0, 1.0)
end

local function lfoShapeValue(shape, phase)
  local p = clamp(phase, 0.0, 1.0)
  if shape == 0 then
    return math.sin(p * math.pi * 2.0)
  elseif shape == 1 then
    return 1.0 - math.abs((p * 4.0) - 2.0)
  elseif shape == 2 then
    return (p * 2.0) - 1.0
  elseif shape == 3 then
    return p < 0.5 and 1.0 or -1.0
  elseif shape == 4 then
    return seededStepValue(math.floor(p * 8) + 1)
  elseif shape == 5 then
    local a = seededStepValue(math.floor(p * 6) + 1)
    local b = seededStepValue(math.floor(p * 6) + 2)
    local localT = (p * 6.0) % 1.0
    return lerp(a, b, localT)
  end
  return 0.0
end

local function responseAlpha(shape, t)
  local n = clamp(t, 0.0, 1.0)
  if shape == 0 then
    return n
  elseif shape == 1 then
    return 1.0 - ((1.0 - n) * (1.0 - n))
  end
  return n * n
end

local SCALE_INTERVALS = {
  [1] = { 0, 2, 4, 5, 7, 9, 11 },
  [2] = { 0, 2, 3, 5, 7, 8, 10 },
  [3] = { 0, 2, 3, 5, 7, 9, 10 },
  [4] = { 0, 2, 4, 5, 7, 9, 10 },
  [5] = { 0, 2, 4, 7, 9 },
  [6] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
}

local function velocityCurve(value, amount, curve, offset)
  local x = clamp(value, 0.0, 1.0)
  local amt = clamp(amount, 0.0, 1.0)
  local off = clamp(offset, -1.0, 1.0)
  local shaped = x
  if curve == 1 then
    shaped = math.sqrt(x)
  elseif curve == 2 then
    shaped = x * x
  end
  local blended = x * (1.0 - amt) + shaped * amt
  return clamp(blended + (off * amt), 0.0, 1.0)
end

local function addTitle(display, text, w, h, colour)
  display[#display + 1] = {
    cmd = "drawText",
    x = 4, y = 2, w = w - 8, h = 14,
    text = tostring(text or ""),
    color = colour or 0xffffffff,
    fontSize = 9,
    align = "left",
    valign = "top",
  }
end

function M.buildLfoDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff38bdf8
  addGrid(display, w, h, withAlpha(col, 28))
  local depth = clamp(values and values.depth or 1.0, 0.0, 1.0)
  local shape = math.floor(clamp(values and values.shape or 0, 0, 5) + 0.5)
  local phase = clamp(view and view.phase or 0.0, 0.0, 1.0)
  local top = 10
  local bottom = h - 10
  local left = 6
  local right = w - 6
  local points = {}
  local segments = math.max(24, w - 12)
  for i = 0, segments do
    local t = i / math.max(1, segments)
    local x = lerp(left, right, t)
    local y = mapBipolarY(lfoShapeValue(shape, t) * depth, top, bottom)
    points[#points + 1] = { x = x, y = y }
  end
  addPolyline(display, points, col, 2)
  local cursorX = lerp(left, right, phase)
  display[#display + 1] = { cmd = "drawLine", x1 = floor(cursorX), y1 = top, x2 = floor(cursorX), y2 = bottom, thickness = 1, color = withAlpha(col, 120) }
  local currentOut = tonumber(view and view.outputs and view.outputs.out) or 0.0
  addMarker(display, cursorX, mapBipolarY(currentOut, top, bottom), 0xffffffff, 3)
  addTitle(display, string.format("shape %d  out %+.2f", shape, currentOut), w, h, col)
  return display
end

function M.buildSlewDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff22d3ee
  addGrid(display, w, h, withAlpha(col, 26))
  local shape = math.floor(clamp(values and values.shape or 1, 0, 2) + 0.5)
  local inputValue = tonumber(view and view.inputValue) or 0.0
  local outputValue = tonumber(view and view.outputValue) or 0.0
  local top = 10
  local bottom = h - 10
  local left = 6
  local right = w - 6
  local points = {}
  local segments = math.max(16, w - 12)
  local startValue = 0.0
  for i = 0, segments do
    local t = i / math.max(1, segments)
    local x = lerp(left, right, t)
    local y = mapBipolarY(lerp(startValue, inputValue, responseAlpha(shape, t)), top, bottom)
    points[#points + 1] = { x = x, y = y }
  end
  addPolyline(display, points, col, 2)
  local inputY = mapBipolarY(inputValue, top, bottom)
  local outputY = mapBipolarY(outputValue, top, bottom)
  display[#display + 1] = { cmd = "drawLine", x1 = left, y1 = floor(inputY), x2 = right, y2 = floor(inputY), thickness = 1, color = withAlpha(col, 72) }
  addMarker(display, right, outputY, 0xffffffff, 3)
  addTitle(display, string.format("in %+.2f  out %+.2f", inputValue, outputValue), w, h, col)
  return display
end

function M.buildSampleHoldDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xfff59e0b
  addGrid(display, w, h, withAlpha(col, 26))
  local inputValue = tonumber(view and view.inputValue) or 0.0
  local outputValue = tonumber(view and view.outputValue) or 0.0
  local mode = math.floor(clamp(values and values.mode or 0, 0, 2) + 0.5)
  local top = 10
  local bottom = h - 10
  local left = 6
  local right = w - 6
  local mid1 = lerp(left, right, 0.33)
  local mid2 = lerp(left, right, 0.66)
  local outY = mapBipolarY(outputValue, top, bottom)
  local inY = mapBipolarY(inputValue, top, bottom)
  display[#display + 1] = { cmd = "drawLine", x1 = left, y1 = floor(outY), x2 = mid1, y2 = floor(outY), thickness = 2, color = col }
  display[#display + 1] = { cmd = "drawLine", x1 = floor(mid1), y1 = floor(outY), x2 = floor(mid1), y2 = floor(inY), thickness = 2, color = col }
  display[#display + 1] = { cmd = "drawLine", x1 = floor(mid1), y1 = floor(inY), x2 = floor(mid2), y2 = floor(inY), thickness = 2, color = withAlpha(col, 180) }
  display[#display + 1] = { cmd = "drawLine", x1 = floor(mid2), y1 = floor(inY), x2 = floor(mid2), y2 = floor(outY), thickness = 2, color = col }
  display[#display + 1] = { cmd = "drawLine", x1 = floor(mid2), y1 = floor(outY), x2 = right, y2 = floor(outY), thickness = 2, color = col }
  addMarker(display, right, outY, 0xffffffff, 3)
  addTitle(display, string.format("mode %d  hold %+.2f", mode, outputValue), w, h, col)
  return display
end

function M.buildCompareDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xfff97316
  addGrid(display, w, h, withAlpha(col, 26))
  local threshold = tonumber(values and values.threshold) or 0.0
  local hysteresis = tonumber(values and values.hysteresis) or 0.05
  local inputValue = tonumber(view and view.inputValue) or 0.0
  local gateValue = tonumber(view and view.gateValue) or 0.0
  local trigValue = tonumber(view and view.trigValue) or 0.0
  local top = 10
  local bottom = h - 10
  local left = 6
  local right = w - 6
  local lowY = mapBipolarY(threshold - (hysteresis * 0.5), top, bottom)
  local highY = mapBipolarY(threshold + (hysteresis * 0.5), top, bottom)
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = left,
    y = floor(math.min(lowY, highY)),
    w = math.max(1, right - left),
    h = math.max(2, floor(math.abs(highY - lowY))),
    radius = 3,
    color = withAlpha(col, 34),
  }
  local transfer = {
    { x = left, y = gateValue > 0.5 and top or bottom },
    { x = lerp(left, right, 0.5), y = gateValue > 0.5 and top or bottom },
    { x = right, y = gateValue > 0.5 and top or bottom },
  }
  addPolyline(display, transfer, col, 2)
  local inputX = mapMidiX((inputValue + 1.0) * 63.5, left, right)
  addMarker(display, inputX, mapBipolarY(inputValue, top, bottom), trigValue > 0.5 and 0xffffffff or withAlpha(0xffffffff, 180), 4)
  addTitle(display, string.format("thr %+.2f  gate %.0f trig %.0f", threshold, gateValue, trigValue), w, h, col)
  return display
end

function M.buildCvMixDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xffc084fc
  addGrid(display, w, h, withAlpha(col, 22))
  local inputs = type(view and view.inputs) == "table" and view.inputs or { 0.0, 0.0, 0.0, 0.0 }
  local levels = {
    clamp(values and values.level_1 or 1.0, 0.0, 1.0),
    clamp(values and values.level_2 or 0.0, 0.0, 1.0),
    clamp(values and values.level_3 or 0.0, 0.0, 1.0),
    clamp(values and values.level_4 or 0.0, 0.0, 1.0),
  }
  local left = 8
  local right = w - 8
  local top = 12
  local bottom = h - 10
  local gap = 6
  local barCount = 5
  local barW = math.max(8, floor((right - left - (gap * (barCount - 1))) / barCount))
  for i = 1, 4 do
    local x = left + ((i - 1) * (barW + gap))
    local height = math.max(2, floor((bottom - top) * clamp(((tonumber(inputs[i]) or 0.0) * levels[i] + 1.0) * 0.5, 0.0, 1.0)))
    display[#display + 1] = { cmd = "fillRoundedRect", x = x, y = bottom - height, w = barW, h = height, radius = 3, color = withAlpha(col, 180) }
  end
  local outX = left + (4 * (barW + gap))
  local outHeight = math.max(2, floor((bottom - top) * clamp(((tonumber(view and view.outputValue) or 0.0) + 1.0) * 0.5, 0.0, 1.0)))
  display[#display + 1] = { cmd = "fillRoundedRect", x = outX, y = bottom - outHeight, w = barW, h = outHeight, radius = 3, color = 0xffffffff }
  addTitle(display, string.format("out %+.2f", tonumber(view and view.outputValue) or 0.0), w, h, col)
  return display
end

function M.buildVelocityDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff4ade80
  addGrid(display, w, h, withAlpha(col, 24))
  local amount = tonumber(values and values.amount) or 1.0
  local curve = math.floor(clamp(values and values.curve or 0, 0, 2) + 0.5)
  local offset = tonumber(values and values.offset) or 0.0
  local left = 6
  local right = w - 6
  local top = 10
  local bottom = h - 10
  local points = {}
  local segments = math.max(16, w - 12)
  for i = 0, segments do
    local t = i / math.max(1, segments)
    local x = lerp(left, right, t)
    local y = mapUnipolarY(velocityCurve(t, amount, curve, offset), top, bottom)
    points[#points + 1] = { x = x, y = y }
  end
  addPolyline(display, points, col, 2)
  local inputAmp = clamp(tonumber(view and view.inputAmp) or 0.0, 0.0, 1.0)
  local outputAmp = clamp(tonumber(view and view.outputAmp) or 0.0, 0.0, 1.0)
  local voiceEntries = copyVoiceEntries(view)
  if #voiceEntries > 0 then
    for i = 1, #voiceEntries do
      local voice = voiceEntries[i]
      local vin = clamp(tonumber(voice.inputAmp) or 0.0, 0.0, 1.0)
      local vout = clamp(tonumber(voice.outputAmp) or vin, 0.0, 1.0)
      addMarker(display, lerp(left, right, vin), mapUnipolarY(vout, top, bottom), voiceColor(voice.voiceIndex), 3)
    end
  else
    addMarker(display, lerp(left, right, inputAmp), mapUnipolarY(outputAmp, top, bottom), 0xffffffff, 3)
  end
  addTitle(display, string.format("in %.0f%%  out %.0f%%", inputAmp * 100.0, outputAmp * 100.0), w, h, col)
  return display
end

function M.buildAttenuverterDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff22c55e
  addGrid(display, w, h, withAlpha(col, 24))
  local amount = tonumber(values and values.amount) or 1.0
  local bias = tonumber(values and values.bias) or 0.0
  local left = 6
  local right = w - 6
  local top = 10
  local bottom = h - 10
  local points = {}
  local segments = math.max(16, w - 12)
  for i = 0, segments do
    local t = i / math.max(1, segments)
    local xIn = (t * 2.0) - 1.0
    local yOut = clamp((xIn * amount) + bias, -1.0, 1.0)
    points[#points + 1] = { x = lerp(left, right, t), y = mapBipolarY(yOut, top, bottom) }
  end
  addPolyline(display, points, col, 2)
  local inputValue = clamp(tonumber(view and view.inputValue) or 0.0, -1.0, 1.0)
  local outputValue = clamp(tonumber(view and view.outputValue) or 0.0, -1.0, 1.0)
  addMarker(display, lerp(left, right, (inputValue + 1.0) * 0.5), mapBipolarY(outputValue, top, bottom), 0xffffffff, 3)
  addTitle(display, string.format("amt %+.2f  bias %+.2f", amount, bias), w, h, col)
  return display
end

function M.buildRangeDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff4ade80
  addGrid(display, w, h, withAlpha(col, 22))
  local minValue = clamp(values and values.min or 0.0, 0.0, 1.0)
  local maxValue = clamp(values and values.max or 1.0, 0.0, 1.0)
  if minValue > maxValue then minValue, maxValue = maxValue, minValue end
  local mode = math.floor(clamp(values and values.mode or 0, 0, 1) + 0.5)
  local left = 6
  local right = w - 6
  local top = 10
  local bottom = h - 10
  local points = {}
  local segments = math.max(16, w - 12)
  for i = 0, segments do
    local t = i / math.max(1, segments)
    local outValue = mode == 0 and clamp(t, minValue, maxValue) or lerp(minValue, maxValue, t)
    points[#points + 1] = { x = lerp(left, right, t), y = mapUnipolarY(outValue, top, bottom) }
  end
  addPolyline(display, points, col, 2)
  local inputValue = clamp(tonumber(view and view.lastInput) or 0.0, 0.0, 1.0)
  local outputValue = clamp(tonumber(view and view.lastOutput) or 0.0, 0.0, 1.0)
  addMarker(display, lerp(left, right, inputValue), mapUnipolarY(outputValue, top, bottom), 0xffffffff, 3)
  addTitle(display, string.format("%s %.0f→%.0f%%", mode == 0 and "clamp" or "remap", minValue * 100.0, maxValue * 100.0), w, h, col)
  return display
end

function M.buildPitchDisplay(w, h, inputNote, outputNote, accent, title)
  local display = {}
  local col = accent or 0xff4ade80
  addGrid(display, w, h, withAlpha(col, 18))
  local left = 6
  local right = w - 6
  local centerY = floor(h * 0.55)
  display[#display + 1] = { cmd = "drawLine", x1 = left, y1 = centerY, x2 = right, y2 = centerY, thickness = 2, color = withAlpha(col, 110) }
  local titleText = type(title) == "table" and title.text or title
  local voiceEntries = type(title) == "table" and copyVoiceEntries(title.viewState) or {}
  if #voiceEntries > 0 then
    for i = 1, #voiceEntries do
      local voice = voiceEntries[i]
      local vin = tonumber(voice.inputNote)
      local vout = tonumber(voice.outputNote)
      if vin ~= nil then
        local inputX = mapMidiX(vin, left, right)
        display[#display + 1] = { cmd = "drawLine", x1 = floor(inputX), y1 = centerY - 12, x2 = floor(inputX), y2 = centerY + 12, thickness = 1, color = withAlpha(voiceColor(voice.voiceIndex), 180) }
      end
      if vout ~= nil then
        addMarker(display, mapMidiX(vout, left, right), centerY, voiceColor(voice.voiceIndex), 4)
      end
    end
  elseif inputNote ~= nil then
    local inputX = mapMidiX(inputNote, left, right)
    display[#display + 1] = { cmd = "drawLine", x1 = floor(inputX), y1 = centerY - 12, x2 = floor(inputX), y2 = centerY + 12, thickness = 2, color = withAlpha(col, 190) }
    if outputNote ~= nil then
      local outputX = mapMidiX(outputNote, left, right)
      addMarker(display, outputX, centerY, 0xffffffff, 4)
    end
  end
  addTitle(display, titleText or "pitch map", w, h, col)
  return display
end

function M.buildScaleDisplay(w, h, root, scaleIndex, inputNote, outputNote, accent)
  local display = {}
  local col = type(accent) == "table" and (accent.colour or accent.color) or accent or 0xff4ade80
  addGrid(display, w, h, withAlpha(col, 18))
  local intervals = copyArray(SCALE_INTERVALS[math.max(1, math.min(6, math.floor(tonumber(scaleIndex) or 1)))] or SCALE_INTERVALS[6])
  local left = 8
  local right = w - 8
  local top = 14
  local bottom = h - 14
  local rowY = floor((top + bottom) * 0.5)
  for i = 0, 11 do
    local x = lerp(left, right, i / 11)
    local inScale = false
    for j = 1, #intervals do
      if ((root + intervals[j]) % 12) == i then
        inScale = true
        break
      end
    end
    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = floor(x - 4), y = rowY - (inScale and 10 or 4), w = 8, h = inScale and 20 or 8,
      radius = 3, color = inScale and withAlpha(col, 180) or withAlpha(0xffffffff, 42),
    }
  end
  local voiceEntries = type(accent) == "table" and copyVoiceEntries(accent.viewState) or {}
  if #voiceEntries > 0 then
    for i = 1, #voiceEntries do
      local voice = voiceEntries[i]
      local vin = tonumber(voice.inputNote)
      local vout = tonumber(voice.outputNote)
      local vcol = voiceColor(voice.voiceIndex)
      if vin ~= nil then
        addMarker(display, lerp(left, right, (math.floor(vin) % 12) / 11), rowY - 14, vcol, 3)
      end
      if vout ~= nil then
        addMarker(display, lerp(left, right, (math.floor(vout) % 12) / 11), rowY + 14, vcol, 3)
      end
    end
  else
    if inputNote ~= nil then
      addMarker(display, lerp(left, right, (math.floor(inputNote) % 12) / 11), rowY - 14, withAlpha(col, 220), 3)
    end
    if outputNote ~= nil then
      addMarker(display, lerp(left, right, (math.floor(outputNote) % 12) / 11), rowY + 14, 0xffffffff, 3)
    end
  end
  addTitle(display, "scale map", w, h, col)
  return display
end

function M.buildNoteFilterDisplay(w, h, values, view, accent)
  local display = {}
  local col = accent or 0xff22c55e
  addGrid(display, w, h, withAlpha(col, 18))
  local low = clamp(values and values.low or 36, 0.0, 127.0)
  local high = clamp(values and values.high or 96, 0.0, 127.0)
  if low > high then low, high = high, low end
  local left = 6
  local right = w - 6
  local midY = floor(h * 0.55)
  display[#display + 1] = { cmd = "drawLine", x1 = left, y1 = midY, x2 = right, y2 = midY, thickness = 2, color = withAlpha(col, 90) }
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = floor(mapMidiX(low, left, right)),
    y = midY - 8,
    w = math.max(4, floor(mapMidiX(high, left, right) - mapMidiX(low, left, right))),
    h = 16,
    radius = 4,
    color = withAlpha(col, 140),
  }
  local voiceEntries = copyVoiceEntries(view)
  if #voiceEntries > 0 then
    for i = 1, #voiceEntries do
      local voice = voiceEntries[i]
      local note = tonumber(voice.note)
      if note ~= nil then
        local markerColor = voice.passes == false and withAlpha(0xffff4444, 255) or voiceColor(voice.voiceIndex)
        addMarker(display, mapMidiX(note, left, right), midY, markerColor, 4)
      end
    end
  else
    local inputNote = tonumber(view and view.inputNote) or nil
    if inputNote ~= nil then
      addMarker(display, mapMidiX(inputNote, left, right), midY, (view and view.passes) and 0xffffffff or withAlpha(0xffff4444, 255), 4)
    end
  end
  addTitle(display, (view and view.passes) and "pass window" or "filter window", w, h, col)
  return display
end

function M.buildArpDisplay(w, h, view, accent)
  local display = {}
  local col = accent or 0xfff59e0b
  addGrid(display, w, h, withAlpha(col, 18))
  local held = math.max(0, math.floor(tonumber(view and view.heldCount) or 0))
  local activeLanes = math.max(0, math.floor(tonumber(view and view.activeLaneCount) or 0))
  local gate = (tonumber(view and view.gate) or 0.0) > 0.5
  local left = 10
  local right = w - 10
  local top = 18
  local bottom = h - 12
  local gap = 6
  local barW = math.max(8, floor((right - left - (gap * 3)) / 4))
  local litCount = math.max(0, math.min(4, math.max(held, activeLanes)))
  for i = 1, 4 do
    local x = left + ((i - 1) * (barW + gap))
    local active = i <= litCount
    local height = active and (bottom - top) or math.max(12, floor((bottom - top) * 0.3))
    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = x,
      y = bottom - height,
      w = barW,
      h = height,
      radius = 4,
      color = active and withAlpha(col, gate and 220 or 150) or withAlpha(0xffffffff, 30),
    }
  end
  addTitle(display, string.format("held %d  lanes %d", held, activeLanes), w, h, col)
  return display
end

return M

-- Oscillator component behavior - waveform preview + voice playthrough
local OscBehavior = {}

local WAVEFORM_COLORS = {
  [0] = 0xff7dd3fc,  -- sine
  [1] = 0xff38bdf8,  -- saw
  [2] = 0xff22d3ee,  -- square
  [3] = 0xff2dd4bf,  -- triangle
  [4] = 0xffa78bfa,  -- blend
  [5] = 0xff94a3b8,  -- noise (gray)
  [6] = 0xfff472b6,  -- pulse (pink)
  [7] = 0xfffbbf24,  -- supersaw (amber)
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
  elseif waveType == 5 then
    -- Noise: return random-ish value based on phase (deterministic for preview)
    local pseudoRandom = math.sin(p * 43758.5453) % 1.0
    return (pseudoRandom * 2 - 1) * 0.5
  elseif waveType == 6 then
    -- Pulse: default 25% width (narrow pulse)
    return p < 0.25 and 1 or -1
  elseif waveType == 7 then
    -- SuperSaw: 3 detuned saws
    local s1 = 2 * p - 1
    local s2 = 2 * ((p * 1.01) % 1.0) - 1
    local s3 = 2 * ((p * 0.99) % 1.0) - 1
    return (s1 + s2 * 0.5 + s3 * 0.5) * 0.5
  end
  return 0
end

local function additiveOutputTrim(waveType)
  if waveType == 1 then return 0.96 end
  if waveType == 2 then return 0.98 end
  if waveType == 3 then return 1.06 end
  if waveType == 4 then return 0.94 end
  if waveType == 5 then return 0.78 end
  if waveType == 6 then return 1.00 end
  if waveType == 7 then return 0.84 end
  return 1.0
end

local function buildAdditiveRecipe(waveType, pulseWidth)
  local width = math.max(0.01, math.min(0.99, tonumber(pulseWidth) or 0.5))
  local partials = {}

  local function add(ratio, amplitude, phase)
    local amp = tonumber(amplitude) or 0.0
    if amp <= 1.0e-6 or #partials >= 12 then
      return
    end
    partials[#partials + 1] = {
      ratio = tonumber(ratio) or 1.0,
      amplitude = amp,
      phase = tonumber(phase) or 0.0,
    }
  end

  if waveType == 0 then
    add(1.0, 1.0, 0.0)
  elseif waveType == 1 then
    for harmonic = 1, 12 do
      add(harmonic, 1.0 / harmonic, 0.0)
    end
  elseif waveType == 2 then
    local harmonic = 1
    while #partials < 12 do
      add(harmonic, 1.0 / harmonic, 0.0)
      harmonic = harmonic + 2
    end
  elseif waveType == 3 then
    local harmonic = 1
    local positiveCosine = false
    while #partials < 12 do
      add(harmonic, 1.0 / (harmonic * harmonic), positiveCosine and (math.pi * 0.5) or (-math.pi * 0.5))
      harmonic = harmonic + 2
      positiveCosine = not positiveCosine
    end
  elseif waveType == 4 then
    for harmonic = 1, 12 do
      local sineComponent = (harmonic == 1) and 0.45 or 0.0
      local sawComponent = 0.55 / harmonic
      add(harmonic, sineComponent + sawComponent, 0.0)
    end
  elseif waveType == 5 then
    local ratios = { 1.0, 1.37, 1.93, 2.58, 3.11, 3.93, 5.17, 6.44, 8.13, 10.37, 13.11, 16.51 }
    local amps = { 1.0, 0.91, 0.82, 0.74, 0.67, 0.60, 0.52, 0.45, 0.38, 0.31, 0.25, 0.20 }
    local phases = { 0.0, 0.63, 1.42, 2.17, 0.88, 2.74, 1.11, 2.49, 0.37, 1.96, 2.81, 0.94 }
    for i = 1, #ratios do
      add(ratios[i], amps[i], phases[i])
    end
  elseif waveType == 6 then
    for harmonic = 1, 12 do
      local coeff = math.sin(math.pi * harmonic * width)
      add(harmonic, math.abs(coeff) / harmonic, coeff < 0 and math.pi or 0.0)
    end
  elseif waveType == 7 then
    local detunes = { -18.0, -7.0, 0.0, 8.0, 19.0 }
    local gains = { 0.55, 0.82, 1.0, 0.79, 0.50 }
    local phases = { 0.17, 0.51, 0.0, 0.33, 0.74 }
    for i = 1, #detunes do
      local ratio = 2.0 ^ (detunes[i] / 1200.0)
      add(ratio, gains[i], phases[i])
    end
  else
    add(1.0, 1.0, 0.0)
  end

  return partials
end

local function getCachedAdditiveRecipe(ctx, waveType, pulseWidth)
  local width = math.max(0.01, math.min(0.99, tonumber(pulseWidth) or 0.5))
  local partialCount = math.max(1, math.min(32, math.floor((tonumber(ctx.additivePartials) or 8) + 0.5)))
  local tilt = math.max(-1.0, math.min(1.0, tonumber(ctx.additiveTilt) or 0.0))
  local drift = math.max(0.0, math.min(1.0, tonumber(ctx.additiveDrift) or 0.0))
  local key = string.format("%d:%.4f:%d:%.4f:%.4f", tonumber(waveType) or 0, width, partialCount, tilt, drift)
  if ctx._cachedAdditiveRecipeKey ~= key then
    local base = buildAdditiveRecipe(waveType, width)
    local shaped = {}
    for i = 1, math.min(partialCount, #base) do
      local part = base[i]
      local ratio = math.max(0.1, tonumber(part.ratio) or 1.0)
      local ratioJitter = math.sin(ratio * 2.173 + (tonumber(waveType) or 0) * 0.53)
      local phaseJitter = math.sin(ratio * 1.618 + (tonumber(waveType) or 0) * 0.37)
      local driftRatio = 1.0 + ratioJitter * drift * 0.035 * (1.0 + ratio * 0.05)
      local tiltScale = math.max(0.12, ratio ^ (tilt * 0.85))
      shaped[#shaped + 1] = {
        ratio = math.max(0.1, ratio * driftRatio),
        amplitude = (tonumber(part.amplitude) or 0.0) * tiltScale,
        phase = (tonumber(part.phase) or 0.0) + phaseJitter * drift * 0.85,
      }
    end
    ctx._cachedAdditiveRecipeKey = key
    ctx._cachedAdditiveRecipe = shaped
  end
  return ctx._cachedAdditiveRecipe or {}
end

local function getCachedDetuneRatios(ctx)
  local unison = math.max(1, math.min(8, math.floor((tonumber(ctx.unison) or 1) + 0.5)))
  local detune = math.max(0.0, math.min(100.0, tonumber(ctx.detune) or 0.0))
  local key = string.format("%d:%.4f", unison, detune)
  if ctx._cachedAdditiveDetuneKey ~= key then
    local ratios = {}
    for v = 1, unison do
      local voiceOffset = (v - 1) - ((unison - 1) * 0.5)
      local detuneSemitones = voiceOffset * detune / 100.0
      ratios[#ratios + 1] = 2.0 ^ (detuneSemitones / 12.0)
    end
    ctx._cachedAdditiveDetuneKey = key
    ctx._cachedAdditiveDetuneRatios = ratios
  end
  return ctx._cachedAdditiveDetuneRatios or { 1.0 }
end

local function additiveRecipeSample(partials, phase)
  local sum = 0.0
  local ampSum = 0.0
  for i = 1, #partials do
    local part = partials[i]
    sum = sum + math.sin((phase * part.ratio) * 2 * math.pi + part.phase) * part.amplitude
    ampSum = ampSum + part.amplitude
  end
  if ampSum <= 1.0e-6 then
    return 0.0
  end
  return math.max(-1.0, math.min(1.0, sum / ampSum))
end

local function additiveSuperSawPreview(ctx, phase)
  local detunes = { -18.0, -7.0, 0.0, 8.0, 19.0 }
  local gains = { 0.55, 0.82, 1.0, 0.79, 0.50 }
  local phases = { 0.17, 0.51, 0.0, 0.33, 0.74 }
  local layerCount = math.max(1, math.min(#detunes, math.floor((tonumber(ctx.additivePartials) or 8) + 0.5)))
  local sum = 0.0
  local ampSum = 0.0
  for i = 1, layerCount do
    local ratio = 2.0 ^ (detunes[i] / 1200.0)
    local layerPhase = (phase * ratio + phases[i] / (2.0 * math.pi)) % 1.0
    sum = sum + waveformSample(1, layerPhase) * gains[i]
    ampSum = ampSum + gains[i]
  end
  if ampSum <= 1.0e-6 then
    return 0.0
  end
  return math.max(-1.0, math.min(1.0, sum / ampSum))
end

local function buildDrivenWaveWeight(waveType, harmonicNumber, pulseWidth)
  local h = math.max(1, math.floor(tonumber(harmonicNumber) or 1))
  local width = math.max(0.01, math.min(0.99, tonumber(pulseWidth) or 0.5))
  if waveType == 0 then
    return (h == 1) and 1.0 or 0.0
  elseif waveType == 1 then
    return 1.0 / h
  elseif waveType == 2 then
    return (h % 2 == 1) and (1.0 / h) or 0.0
  elseif waveType == 3 then
    return (h % 2 == 1) and (1.0 / (h * h)) or 0.0
  elseif waveType == 4 then
    return ((h == 1) and 0.45 or 0.0) + (0.55 / h)
  elseif waveType == 5 then
    return 1.0 / math.sqrt(h)
  elseif waveType == 6 then
    return math.abs(math.sin(math.pi * h * width)) / h
  elseif waveType == 7 then
    return (1.0 / h) * (1.0 + 0.22 * math.cos(h * 0.73) + 0.15 * math.sin(h * 1.11))
  end
  return 1.0 / h
end

local function drivenSamplePreview(ctx, sample, phase)
  local waveType = tonumber(ctx.waveformType) or 1
  local pulseWidth = tonumber(ctx.pulseWidth) or 0.5
  local partialCount = math.max(1, math.min(32, math.floor((tonumber(ctx.additivePartials) or 8) + 0.5)))
  local sum = 0.0
  local ampSum = 0.0
  for h = 1, partialCount do
    local weight = math.max(0.0, buildDrivenWaveWeight(waveType, h, pulseWidth))
    if weight > 1.0e-6 then
      sum = sum + math.sin((phase * h) * 2 * math.pi) * (sample * weight)
      ampSum = ampSum + weight
    end
  end
  if ampSum <= 1.0e-6 then
    return 0.0
  end
  return math.max(-1.0, math.min(1.0, sum / ampSum))
end

local function renderWaveSample(ctx, waveType, phase)
  local renderMode = ctx.renderMode or 0
  if renderMode ~= 1 then
    return waveformSample(waveType, phase)
  end

  local pulseWidth = ctx.pulseWidth or 0.5
  local partials = getCachedAdditiveRecipe(ctx, waveType, pulseWidth)
  local detuneRatios = getCachedDetuneRatios(ctx)
  local sum = 0.0
  for i = 1, #detuneRatios do
    local detunedPhase = phase * detuneRatios[i]
    if waveType == 7 then
      sum = sum + additiveSuperSawPreview(ctx, detunedPhase)
    else
      sum = sum + additiveRecipeSample(partials, detunedPhase)
    end
  end
  local sample = math.max(-1.0, math.min(1.0, sum / math.sqrt(#detuneRatios)))
  local tilt = math.max(-1.0, math.min(1.0, tonumber(ctx.additiveTilt) or 0.0))
  local drift = math.max(0.0, math.min(1.0, tonumber(ctx.additiveDrift) or 0.0))
  local tiltComp = 1.0 + math.max(-0.12, math.min(0.10, tilt * -0.10))
  local driftComp = 1.0 - drift * 0.08
  return math.max(-1.0, math.min(1.0, sample * additiveOutputTrim(waveType) * tiltComp * driftComp))
end

local function tanh(x)
  if math.tanh then return math.tanh(x) end
  local ex = math.exp(x)
  local enx = math.exp(-x)
  return (ex - enx) / (ex + enx)
end

local function foldToUnit(x)
  x = math.max(-32.0, math.min(32.0, tonumber(x) or 0.0))
  while x > 1.0 or x < -1.0 do
    if x > 1.0 then
      x = 2.0 - x
    else
      x = -2.0 - x
    end
  end
  return x
end

local function applyDriveTransfer(s, drive, shape)
  local drv = math.max(0.0, tonumber(drive) or 0.0)
  local shp = math.max(0, math.min(3, math.floor((tonumber(shape) or 0) + 0.5)))
  if drv <= 0.0001 then
    return math.max(-1.0, math.min(1.0, s))
  end

  if shp == 1 then
    local gain = 1.0 + drv * 1.35
    local normaliser = math.atan(gain)
    if math.abs(normaliser) <= 1.0e-6 then
      return math.max(-1.0, math.min(1.0, s))
    end
    return math.atan(s * gain) / normaliser
  elseif shp == 2 then
    local gain = 1.0 + drv * 1.2
    return math.max(-1.0, math.min(1.0, s * gain))
  elseif shp == 3 then
    local gain = 1.0 + drv * 1.1
    return foldToUnit(s * gain)
  end

  local gain = 1.0 + drv * 0.85
  local normaliser = tanh(gain)
  if math.abs(normaliser) <= 1.0e-6 then
    return math.max(-1.0, math.min(1.0, s))
  end
  return tanh(s * gain) / normaliser
end

local function applyDriveShape(s, drive, shape, bias, mix)
  local drv = math.max(0.0, tonumber(drive) or 0.0)
  local wetMix = math.max(0.0, math.min(1.0, tonumber(mix) or 1.0))
  if drv <= 0.0001 or wetMix <= 0.0001 then
    return math.max(-1.0, math.min(1.0, s))
  end

  local biasOffset = math.max(-1.0, math.min(1.0, tonumber(bias) or 0.0)) * 0.75
  local center = applyDriveTransfer(biasOffset, drv, shape)
  local pos = math.abs(applyDriveTransfer(1.0 + biasOffset, drv, shape) - center)
  local neg = math.abs(applyDriveTransfer(-1.0 + biasOffset, drv, shape) - center)
  local normaliser = math.max(1.0e-6, math.max(pos, neg))
  local shaped = (applyDriveTransfer(s + biasOffset, drv, shape) - center) / normaliser
  local wet = math.max(-1.0, math.min(1.0, shaped))
  return math.max(-1.0, math.min(1.0, s + (wet - s) * wetMix))
end

local SAMPLE_COLOR = 0xff22d3ee
local SAMPLE_DIM = 0x6022d3ee

local function buildSampleWaveform(ctx, w, h, display)
  -- Reserve bottom space for 2 bars:
  -- 1) play start
  -- 2) loop start + loop end + crossfade visualization
  local barH = 16
  local barGap = 4
  local barsHeight = barH * 2 + barGap
  local waveH = h - barsHeight - 4  -- waveform area above bars

  local centerY = waveH / 2
  local maxAmp = (waveH / 2) * 0.75
  local numPoints = math.max(48, math.min(w, 200))
  local loopStart = ctx.sampleLoopStart or 0.0
  local loopLen = ctx.sampleLoopLen or 1.0

  local peaks = ctx._cachedPeaks
  if not peaks and type(getSynthSamplePeaks) == "function" then
    peaks = getSynthSamplePeaks(numPoints)
    if peaks and #peaks > 0 then
      ctx._cachedPeaks = peaks
    end
  end

  -- Waveform background (only in wave area)
  display[#display + 1] = {
    cmd = "fillRect", x = 0, y = 0, w = w, h = waveH,
    color = 0x20ffffff,
  }

  if peaks and #peaks > 0 then
    local prevX, prevY
    for i = 0, numPoints do
      local t = i / numPoints
      local peakIdx = math.floor(t * (#peaks - 1)) + 1
      local peak = peaks[peakIdx] or 0
      local s = peak * 2 - 1

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

    local samplePositions = {}
    if type(getVoiceSamplePositions) == "function" then
      samplePositions = getVoiceSamplePositions() or {}
    end

    local voiceLoops = ctx.voiceLoops or {}
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

      -- NOTE: pos from getVoiceSamplePositions() is ALREADY ABSOLUTE (0-1 across full sample).
      local handleCenterOffset = math.floor(8 / 2)
      local playheadX = math.floor(pos * w) - handleCenterOffset

      local waveY = centerY
      if peaks and #peaks > 0 then
        local peakIdx = math.floor(pos * (#peaks - 1)) + 1
        local peak = peaks[peakIdx] or 0.5
        local s = peak * 2 - 1
        waveY = math.floor(centerY - s * maxAmp)
      end

      -- Playhead line stops at waveform bottom
      display[#display + 1] = {
        cmd = "drawLine", x1 = playheadX, y1 = waveH - 2, x2 = playheadX, y2 = waveY,
        thickness = 3, color = vcol,
      }
      ::continue::
    end
  end

  -- 2 HANDLE BARS - simple square handles, no labels
  local handleW = 8
  local handleH = barH - 4
  local playStart = ctx.samplePlayStart or 0.0
  local loopStartPos = loopStart
  local loopEndPos = loopStart + loopLen
  local xfadeNorm = math.max(0.0, math.min(0.5, ctx.sampleCrossfade or 0.1))

  local function drawBarBackground(y)
    display[#display + 1] = {
      cmd = "fillRect", x = 0, y = y, w = w, h = barH,
      color = 0xff0d1420,
    }
    display[#display + 1] = {
      cmd = "drawLine", x1 = 0, y1 = y + barH, x2 = w, y2 = y + barH,
      thickness = 1, color = 0xff334155,
    }
  end

  local function drawHandle(y, pos, color)
    local hx = math.floor(pos * w) - math.floor(handleW / 2)
    local hy = y + 2
    display[#display + 1] = {
      cmd = "fillRect", x = hx, y = hy, w = handleW, h = handleH,
      color = color,
    }
    display[#display + 1] = {
      cmd = "drawRect", x = hx, y = hy, w = handleW, h = handleH,
      thickness = 1, color = 0xffffffff,
    }
  end

  -- Bar 1: Play Start (yellow)
  local bar1Y = waveH + 2
  drawBarBackground(bar1Y)
  drawHandle(bar1Y, playStart, 0xffe5e509)

  -- Bar 2: Loop Start + Loop End + explicit crossfade mapping
  local bar2Y = bar1Y + barH + barGap
  drawBarBackground(bar2Y)

  -- Main loop span guide
  display[#display + 1] = {
    cmd = "drawLine",
    x1 = math.floor(loopStartPos * w), y1 = bar2Y + math.floor(barH / 2),
    x2 = math.floor(loopEndPos * w), y2 = bar2Y + math.floor(barH / 2),
    thickness = 2, color = 0x80cbd5e1,
  }

  local xfadeLen = xfadeNorm * loopLen
  local xfadeStart = math.max(loopStartPos, loopEndPos - xfadeLen)
  local headXfadeEnd = math.min(loopEndPos, loopStartPos + xfadeLen)
  if xfadeLen > 0.0001 then
    -- Head fade-in window near loop start
    display[#display + 1] = {
      cmd = "fillRect",
      x = math.floor(loopStartPos * w),
      y = bar2Y + 2,
      w = math.max(1, math.floor(headXfadeEnd * w) - math.floor(loopStartPos * w)),
      h = barH - 4,
      color = 0x504ade80,
    }

    -- Tail fade-out window near loop end
    display[#display + 1] = {
      cmd = "fillRect",
      x = math.floor(xfadeStart * w),
      y = bar2Y + 2,
      w = math.max(1, math.floor(loopEndPos * w) - math.floor(xfadeStart * w)),
      h = barH - 4,
      color = 0x50f87171,
    }

    -- Explicit seam mapping: head window crossfades into tail window
    local seamLines = 6
    for i = 0, seamLines do
      local t = i / seamLines
      local srcX = math.floor((loopStartPos + xfadeLen * t) * w)
      local dstX = math.floor((xfadeStart + xfadeLen * t) * w)
      display[#display + 1] = {
        cmd = "drawLine",
        x1 = srcX, y1 = bar2Y + 3,
        x2 = dstX, y2 = bar2Y + barH - 3,
        thickness = 1, color = 0xa0f472b6,
      }
    end
  end

  drawHandle(bar2Y, loopStartPos, 0xff4ade80)
  drawHandle(bar2Y, loopEndPos, 0xfff87171)

  -- "No sample" message if no peaks
  if not peaks or #peaks == 0 then
    display[#display + 1] = {
      cmd = "drawText", x = 0, y = math.floor(waveH / 2) - 8, w = w, h = 16,
      text = "No sample captured", color = 0xff94a3b8, fontSize = 11, align = "center", valign = "middle",
    }
  end

  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "SAMPLE MODE", color = 0xffa78bfa, fontSize = 10, align = "left", valign = "top",
  }

  return display
end

local function sampleAtPeaks(peaks, t)
  if type(peaks) ~= "table" or #peaks == 0 then
    return 0.0
  end
  local idx = math.floor(math.max(0, math.min(1, t)) * (#peaks - 1)) + 1
  local peak = peaks[idx] or 0.5
  return peak * 2.0 - 1.0
end

-- Normalize partial data to ratio space for preview rendering
local function normalizePreviewPartials(partials)
  if type(partials) ~= "table" then return nil end
  local count = tonumber(partials.activeCount) or 0
  if count <= 0 then return nil end
  local fund = tonumber(partials.fundamental) or 0.0
  if fund <= 1.0e-6 then
    local p1 = partials.partials and partials.partials[1]
    fund = p1 and (tonumber(p1.frequency) or 0.0) or 0.0
  end
  if fund <= 1.0e-6 then return nil end
  local out = { activeCount = count, fundamental = fund, partials = {} }
  for i = 1, count do
    local p = partials.partials and partials.partials[i]
    if p then
      out.partials[i] = {
        ratio = math.max(0.01, (tonumber(p.frequency) or 0.0) / fund),
        amplitude = tonumber(p.amplitude) or 0.0,
        phase = tonumber(p.phase) or 0.0,
      }
    else
      out.partials[i] = { ratio = 0.0, amplitude = 0.0, phase = 0.0 }
    end
  end
  return out
end

-- Generate wave preview partials using the same recipe as the DSP
local function buildWavePreviewPartials(ctx, fundamental)
  local waveform = tonumber(ctx.waveformType) or 1
  local partialCount = math.max(1, math.min(32, tonumber(ctx.additivePartials) or 8))
  local tilt = tonumber(ctx.additiveTilt) or 0.0
  local drift = tonumber(ctx.additiveDrift) or 0.0
  local fund = math.max(1.0, fundamental or 220.0)
  local out = { activeCount = 0, fundamental = fund, partials = {} }

  local function tiltScale(h) return math.max(0.12, h ^ (tilt * 0.85)) end
  local function driftOffset(h)
    if drift <= 0.0 then return 1.0, 0.0 end
    return 1.0 + math.sin(h * 2.173 + waveform * 0.53) * drift * 0.035 * (1.0 + h * 0.05),
           math.sin(h * 1.618 + waveform * 0.37) * drift * 0.85
  end
  local function addP(h, amp, phase)
    if out.activeCount >= 32 then return end
    local fj, pj = driftOffset(h)
    out.activeCount = out.activeCount + 1
    out.partials[out.activeCount] = {
      frequency = fund * h * fj, amplitude = tiltScale(h) * amp,
      phase = (phase or 0.0) + pj, decayRate = 0.0,
    }
  end

  if waveform == 0 then addP(1, 1.0, 0.0)
  elseif waveform == 1 then for h = 1, partialCount do addP(h, 1.0 / h, (h % 2 == 0) and math.pi or 0.0) end
  elseif waveform == 2 then for i = 1, partialCount do local h = i * 2 - 1; addP(h, 1.0 / h, 0.0) end
  elseif waveform == 3 then for i = 1, partialCount do local h = i * 2 - 1; addP(h, 1.0 / (h * h), (((i - 1) % 2) == 0) and (-math.pi * 0.5) or (math.pi * 0.5)) end
  elseif waveform == 4 then addP(1, 0.45, 0.0); for h = 2, partialCount + 1 do addP(h, 0.55 / h, (h % 2 == 0) and math.pi or 0.0) end
  elseif waveform == 5 then
    local nc = { {1.0,0.32,0.0}, {1.73,0.22,1.2}, {2.41,0.16,2.1}, {3.07,0.12,0.8}, {4.62,0.09,2.8}, {6.11,0.05,1.7} }
    for i = 1, math.min(#nc, partialCount) do
      out.activeCount = out.activeCount + 1
      out.partials[out.activeCount] = { frequency = fund * nc[i][1], amplitude = tiltScale(i) * nc[i][2], phase = nc[i][3], decayRate = 0.0 }
    end
  elseif waveform == 6 then
    local pw = math.max(0.01, math.min(0.99, tonumber(ctx.pulseWidth) or 0.5))
    for h = 1, partialCount do local c = math.sin(math.pi * h * pw); addP(h, math.abs(c) / h, c < 0 and math.pi or 0.0) end
  elseif waveform == 7 then for h = 1, partialCount do addP(h, 0.84 / h, (h % 2 == 0) and math.pi or 0.0) end
  else addP(1, 1.0, 0.0)
  end

  local sum = 0.0
  for i = 1, out.activeCount do sum = sum + (out.partials[i].amplitude or 0.0) end
  if sum > 1.0e-6 then for i = 1, out.activeCount do out.partials[i].amplitude = out.partials[i].amplitude / sum end end
  return out
end

-- Preview morph: same math as DSP (log-freq, curve, depth)
local function morphPreviewPartials(partialsA, partialsB, position, curve, depth)
  local a = normalizePreviewPartials(partialsA)
  local b = normalizePreviewPartials(partialsB)
  if not a and not b then return nil end
  if not a then return normalizePreviewPartials(partialsB) end
  if not b then return normalizePreviewPartials(partialsA) end

  local pos = math.max(0.0, math.min(1.0, position or 0.0))
  local dep = math.max(0.0, math.min(1.0, depth or 1.0))
  local maxCount = math.max(a.activeCount or 0, b.activeCount or 0)
  if maxCount <= 0 then return nil end

  local aCoeff, bCoeff
  if curve == 0 then aCoeff = 1.0 - pos; bCoeff = pos
  elseif curve == 1 then local t = 0.5 - 0.5 * math.cos(pos * math.pi); aCoeff = 1.0 - t; bCoeff = t
  else aCoeff = math.cos(pos * math.pi * 0.5); bCoeff = math.sin(pos * math.pi * 0.5) end

  local freqT = pos * dep
  local out = { activeCount = maxCount, partials = {} }
  for i = 1, maxCount do
    local ap = (i <= (a.activeCount or 0)) and a.partials[i] or nil
    local bp = (i <= (b.activeCount or 0)) and b.partials[i] or nil
    local ar = ap and (tonumber(ap.ratio) or 0.0) or 0.0
    local aa = ap and (tonumber(ap.amplitude) or 0.0) or 0.0
    local aph = ap and (tonumber(ap.phase) or 0.0) or 0.0
    local br = bp and (tonumber(bp.ratio) or 0.0) or 0.0
    local ba = bp and (tonumber(bp.amplitude) or 0.0) or 0.0
    local bph = bp and (tonumber(bp.phase) or 0.0) or 0.0

    local ratio
    if ar <= 0.01 and br <= 0.01 then ratio = 0.0
    elseif ar <= 0.01 then ratio = br
    elseif br <= 0.01 then ratio = ar
    else ratio = math.exp(math.log(ar) + (math.log(br) - math.log(ar)) * freqT) end

    out.partials[i] = {
      ratio = ratio,
      amplitude = aa * aCoeff + ba * bCoeff,
      phase = aph + (bph - aph) * pos,
    }
  end
  return out
end

local function applyMorphPreviewShaping(partials, stretch, tiltMode)
  if not partials or not partials.partials then return partials end
  local s = math.max(0.0, math.min(1.0, tonumber(stretch) or 0.0))
  local tilt = math.max(0, math.min(2, math.floor((tonumber(tiltMode) or 0) + 0.5)))
  if s <= 0.001 and tilt == 0 then return partials end

  local out = { activeCount = partials.activeCount or 0, partials = {} }
  local count = math.max(1, out.activeCount)
  for i = 1, out.activeCount do
    local p = partials.partials[i]
    if p then
      local ratio = tonumber(p.ratio) or tonumber(p.frequency) or 0.0
      local amp = tonumber(p.amplitude) or 0.0
      local partialIdx = i - 1
      local spectralPos = (count > 1) and (partialIdx / (count - 1)) or 0.0
      if ratio > 0.01 and s > 0.001 then
        ratio = math.pow(ratio, 1.0 + s * 0.65) * (1.0 + partialIdx * s * 0.035)
      end
      if amp > 0.0 then
        if tilt == 1 then
          amp = amp * (0.90 + spectralPos * 1.75)
        elseif tilt == 2 then
          amp = amp * math.max(0.18, 1.12 - spectralPos * 0.78)
        end
      end
      out.partials[i] = { ratio = ratio, frequency = ratio, amplitude = amp, phase = tonumber(p.phase) or 0.0 }
    end
  end
  return out
end

local function temporalFramePreviewAtPosition(temporal, pos)
  if type(temporal) ~= "table" or type(temporal.frames) ~= "table" or type(temporal.frameTimes) ~= "table" then
    return nil
  end
  local fc = math.max(0, math.floor(tonumber(temporal.frameCount) or 0))
  if fc <= 0 then return nil end
  if fc == 1 then return normalizePreviewPartials(temporal.frames[1]) end

  local t = math.max(0.0, math.min(1.0, tonumber(pos) or 0.0))
  local lo, hi = 1, fc
  for i = 1, fc - 1 do
    local nextTime = tonumber(temporal.frameTimes[i + 1]) or 1.0
    if nextTime > t then
      lo = i
      hi = i + 1
      break
    end
    lo = i
    hi = i
  end
  if lo == hi then return normalizePreviewPartials(temporal.frames[lo]) end

  local frameA = normalizePreviewPartials(temporal.frames[lo])
  local frameB = normalizePreviewPartials(temporal.frames[hi])
  if not frameA then return frameB end
  if not frameB then return frameA end

  local loTime = tonumber(temporal.frameTimes[lo]) or 0.0
  local hiTime = tonumber(temporal.frameTimes[hi]) or 1.0
  local span = hiTime - loTime
  local frac = (span > 1.0e-6) and math.max(0.0, math.min(1.0, (t - loTime) / span)) or 0.0

  local out = { activeCount = math.max(frameA.activeCount or 0, frameB.activeCount or 0), partials = {} }
  for i = 1, out.activeCount do
    local ap = frameA.partials[i]
    local bp = frameB.partials[i]
    local ar = ap and (tonumber(ap.ratio) or 0.0) or 0.0
    local br = bp and (tonumber(bp.ratio) or 0.0) or 0.0
    local aa = ap and (tonumber(ap.amplitude) or 0.0) or 0.0
    local ba = bp and (tonumber(bp.amplitude) or 0.0) or 0.0
    local aph = ap and (tonumber(ap.phase) or 0.0) or 0.0
    local bph = bp and (tonumber(bp.phase) or 0.0) or 0.0

    local ratio
    if ar <= 0.01 and br <= 0.01 then ratio = 0.0
    elseif ar <= 0.01 then ratio = br * frac
    elseif br <= 0.01 then ratio = ar * (1.0 - frac)
    else ratio = math.exp(math.log(ar) + (math.log(br) - math.log(ar)) * frac) end

    out.partials[i] = {
      ratio = ratio,
      amplitude = aa + (ba - aa) * frac,
      phase = aph + (bph - aph) * frac,
    }
  end
  return out
end

-- Synthesize one cycle of a waveform from partial ratios + amplitudes
-- Caps at 16 partials for UI performance (beyond that is inaudible in a tiny graph)
local function synthFromPartials(partials, phase)
  if not partials or not partials.partials then return 0.0 end
  local sum = 0.0
  local ampSum = 0.0
  local count = math.min(partials.activeCount or 0, 16)
  local twoPi = 6.283185307179586
  for i = 1, count do
    local p = partials.partials[i]
    if p then
      local r = tonumber(p.ratio) or tonumber(p.frequency) or 0.0
      local a = tonumber(p.amplitude) or 0.0
      if a > 1.0e-6 and r > 0.01 then
        sum = sum + math.sin(phase * r * twoPi + (tonumber(p.phase) or 0.0)) * a
        ampSum = ampSum + a
      end
    end
  end
  return (ampSum > 1.0e-6) and math.max(-1.0, math.min(1.0, sum / ampSum)) or 0.0
end

local function buildMorphDisplay(ctx, w, h, display)
  local morphPos = math.max(0.0, math.min(1.0, ctx.blendAmount or 0.5))
  local morphDepth = math.max(0.0, math.min(1.0, ctx.blendModAmount or 0.5))
  local morphCurve = tonumber(ctx.morphCurve) or 2
  local morphStretch = math.max(0.0, math.min(1.0, tonumber(ctx.morphStretch) or tonumber(ctx.morphConvergence) or 0.0))
  local morphTilt = math.max(0, math.min(2, math.floor((tonumber(ctx.morphTilt) or tonumber(ctx.morphPhase) or 0) + 0.5)))
  local waveType = ctx.waveformType or 1
  local waveCol = WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local sampleCol = 0xff22d3ee
  local morphCol = 0xfff97316
  local time = ctx.animTime or 0
  local voices = ctx.activeVoices or {}
  local dominantFreq = 220.0
  local dominantAmp = 0.0
  local dominantSamplePos = math.max(0.0, math.min(1.0, tonumber(ctx.morphSamplePos) or 0.0))
  local samplePositions = (type(getVoiceSamplePositions) == "function") and (getVoiceSamplePositions() or {}) or {}
  local dominantVoiceIndex = nil
  for _, v in ipairs(voices) do
    if (v.amp or 0) > dominantAmp then
      dominantFreq = v.freq or 220.0
      dominantAmp = v.amp or 0
      dominantVoiceIndex = v.voiceIndex
    end
  end
  if dominantVoiceIndex then
    dominantSamplePos = math.max(0.0, math.min(1.0, tonumber(samplePositions[dominantVoiceIndex]) or dominantSamplePos or 0.0))
  end

  -- Get real data. In Morph mode, prefer the TEMPORAL frame at the current sample playback position.
  local temporalPartials = (type(getLatestTemporalPartials) == "function") and getLatestTemporalPartials() or nil
  local samplePartials = nil
  if type(temporalPartials) == "table" and (tonumber(temporalPartials.frameCount) or 0) > 0 then
    samplePartials = temporalFramePreviewAtPosition(temporalPartials, dominantSamplePos)
  end
  if not samplePartials then
    samplePartials = (type(getLatestSamplePartials) == "function") and getLatestSamplePartials() or nil
  end

  local wavePartials = buildWavePreviewPartials(ctx, dominantFreq)
  local waveNorm = normalizePreviewPartials(wavePartials)
  local sampleNorm = normalizePreviewPartials(samplePartials)
  local morphed = applyMorphPreviewShaping(
    morphPreviewPartials(wavePartials, samplePartials, morphPos, morphCurve, morphDepth),
    morphStretch,
    morphTilt
  )
  local hasSample = sampleNorm ~= nil
  local hasWave = waveNorm ~= nil
  local hasLiveVoice = dominantAmp > 0.001
  local canShowLiveMorph = hasSample and hasLiveVoice and morphed ~= nil

  -- Layout: ridge-only Morph view.
  -- Make it smaller, lower, and keep the full depth stack inside the graph area.
  local ridgeTop = 46
  local ridgeBottom = h - 16
  local waveTop = ridgeTop
  local waveH = math.max(34, ridgeBottom - ridgeTop)
  local centerY = ridgeTop + waveH * 0.72
  local maxAmp = (waveH / 2) * 0.56
  local visualSpeed = math.max(0.1, math.min(4.0, tonumber(ctx.morphSpeed) or 1.0))
  local visualContrast = math.max(0.0, math.min(2.0, tonumber(ctx.morphContrast) or 0.5))
  local visualTemporalPos = (dominantSamplePos * visualSpeed) % 1.0

  local hasTemporalData = type(temporalPartials) == "table" and (tonumber(temporalPartials.frameCount) or 0) > 1
  if hasTemporalData and canShowLiveMorph then
    local cursorX = math.floor(12 + (w - 44) * visualTemporalPos)
    display[#display + 1] = { cmd = "drawLine", x1 = cursorX, y1 = ridgeTop - 8, x2 = cursorX, y2 = ridgeBottom, thickness = 1, color = 0x55f97316 }
    display[#display + 1] = { cmd = "fillRect", x = math.floor(cursorX - 1), y = ridgeTop - 10, w = 3, h = 3, color = 0xfff97316 }
  end

  -- === TEMPORAL RIDGE PANEL (wireframe mesh) ===
  do
    local ridgePoints = math.max(16, math.min(w, 24))
    local ridgeDy = 8
    local ridgeDx = 6
    local ridgeScale = maxAmp * (0.90 + visualContrast * 0.20)
    local ridgeLeft = 12
    local ridgeRightPad = 12
    local maxDepthDx = 7 * ridgeDx
    local ridgeWidth = math.max(80, w - ridgeLeft - ridgeRightPad - maxDepthDx)
    local ridgePalette = {
      0xff60a5fa, -- blue
      0xff38bdf8, -- sky
      0xff22d3ee, -- cyan
      0xff2dd4bf, -- teal
      0xff4ade80, -- green
      0xfffbbf24, -- amber
      0xfffb923c, -- orange
      0xfff97316, -- hot orange
    }
    local history = ctx._morphRidgeHistory or {}
    local lastPos = tonumber(ctx._lastMorphRidgePos)
    local lastPushTime = tonumber(ctx._lastMorphRidgeTime) or 0.0

    local function buildRidgePoints(phaseOffset)
      local pts = {}
      for i = 0, ridgePoints do
        local t = i / ridgePoints
        local sig = synthFromPartials(morphed, phaseOffset + t * 2.0)
        local x = math.floor(ridgeLeft + t * ridgeWidth)
        local y = math.floor(centerY - sig * ridgeScale)
        pts[i + 1] = { x = x, y = y }
      end
      return pts
    end

    local phaseRate = math.max(0.15, dominantFreq / 220.0)
    local livePhase = time * phaseRate

    -- Push a new ridge slice when temporal position moves or enough time has passed.
    if canShowLiveMorph then
      local posDelta = (lastPos ~= nil) and math.abs(visualTemporalPos - lastPos) or 1.0
      if posDelta > (0.012 / math.max(0.35, visualSpeed)) or math.abs(time - lastPushTime) > (0.06 / math.max(0.35, visualSpeed)) or #history == 0 then
        history[#history + 1] = {
          points = buildRidgePoints(livePhase),
          pos = visualTemporalPos,
        }
        while #history > 8 do table.remove(history, 1) end
        ctx._lastMorphRidgePos = visualTemporalPos
        ctx._lastMorphRidgeTime = time
      end
      ctx._morphRidgeHistory = history
    else
      ctx._morphRidgeHistory = {}
      ctx._lastMorphRidgePos = nil
      ctx._lastMorphRidgeTime = nil
      history = {}
    end

    if #history > 0 then
      display[#display + 1] = { cmd = "drawText", x = ridgeLeft, y = ridgeTop - 14, w = 72, h = 12, text = "PAST", color = 0xff64748b, fontSize = 8, align = "left", valign = "top" }
      display[#display + 1] = { cmd = "drawText", x = ridgeLeft + ridgeWidth + maxDepthDx - 48, y = ridgeTop - 14, w = 48, h = 12, text = "NOW", color = 0xfff97316, fontSize = 8, align = "right", valign = "top" }

      local livePoints = buildRidgePoints(livePhase)

      -- Draw history oldest -> newest, with live slice in front.
      for si = 1, #history do
        local depth = (#history - si) + 1
        local slice = history[si]
        local dx = depth * ridgeDx
        local dy = depth * ridgeDy
        local alpha = math.max(0x40, 0xd0 - depth * 14)
        local thick = (depth <= 2) and 2 or 1
        local baseColor = ridgePalette[math.min(#ridgePalette, si)] or morphCol
        local color = (baseColor & 0x00ffffff) | (alpha << 24)
        local pts = slice.points
        for i = 2, #pts do
          display[#display + 1] = {
            cmd = "drawLine",
            x1 = pts[i - 1].x + dx, y1 = pts[i - 1].y - dy,
            x2 = pts[i].x + dx, y2 = pts[i].y - dy,
            thickness = thick,
            color = color,
          }
        end
      end

      -- Live front slice.
      for i = 2, #livePoints do
        local c1 = ridgePalette[math.min(#ridgePalette, i - 1)] or morphCol
        display[#display + 1] = {
          cmd = "drawLine",
          x1 = livePoints[i - 1].x, y1 = livePoints[i - 1].y,
          x2 = livePoints[i].x, y2 = livePoints[i].y,
          thickness = 3,
          color = c1,
        }
      end

      -- Mesh connectors between history slices and current live slice.
      local connectorPrev = nil
      local connectorPrevDepth = 0
      for si = 1, #history do
        connectorPrev = history[si].points
        connectorPrevDepth = (#history - si) + 1
      end
      if connectorPrev then
        for i = 1, math.min(#connectorPrev, #livePoints), 2 do
          local a = connectorPrev[i]
          local b = livePoints[i]
          if a and b then
            display[#display + 1] = {
              cmd = "drawLine",
              x1 = a.x + connectorPrevDepth * ridgeDx, y1 = a.y - connectorPrevDepth * ridgeDy,
              x2 = b.x, y2 = b.y,
              thickness = 1,
              color = 0x44f97316,
            }
          end
        end
      end
    end
  end

  -- === WAVEFORM from morphed partials ===
  -- In temporal mode, the ridge panel IS the main lower visualization.
  -- Only draw the large foreground waveform when temporal data is absent.
  local numPoints = math.max(48, math.min(w, 96))

  local ridgeHistoryCount = (ctx._morphRidgeHistory and #ctx._morphRidgeHistory) or 0
  if ridgeHistoryCount <= 1 and not hasTemporalData and #voices > 0 and morphed then
    local bestVoice = nil
    local bestAmp = 0
    for _, voice in ipairs(voices) do
      if (voice.amp or 0) > bestAmp then bestVoice = voice; bestAmp = voice.amp or 0 end
    end
    if bestVoice and bestAmp > 0.001 then
      local vcol = VOICE_COLORS[1]
      local freq = bestVoice.freq or 220
      local phaseOffset = time * freq
      local prevX, prevY
      for i = 0, numPoints do
        local t = i / numPoints
        local phase = phaseOffset + t * 2.0
        local s = synthFromPartials(morphed, phase) * (bestAmp / 0.5)
        local x = math.floor(t * w)
        local y = math.floor(centerY - s * maxAmp)
        if prevX then
          display[#display + 1] = { cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y, thickness = 2, color = vcol }
        end
        prevX, prevY = x, y
      end
    end
  elseif morphed and not hasTemporalData and ridgeHistoryCount <= 1 then
    -- Static preview
    local prevX, prevY
    for i = 0, numPoints do
      local t = i / numPoints
      local s = synthFromPartials(morphed, t * 2.0)
      local x = math.floor(t * w)
      local y = math.floor(centerY - s * maxAmp)
      if prevX then
        display[#display + 1] = { cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y, thickness = 2, color = morphCol }
      end
      prevX, prevY = x, y
    end
  end


  -- === LABEL ===
  local label = "MORPH"
  local hasTemporalData = type(temporalPartials) == "table" and (tonumber(temporalPartials.frameCount) or 0) > 1
  if hasTemporalData then
    label = "MORPH · TEMPORAL " .. (tonumber(temporalPartials.frameCount) or 0) .. " frames"
  end
  display[#display + 1] = { cmd = "drawText", x = 4, y = 2, w = w - 8, h = 14, text = label, color = morphCol, fontSize = 11, align = "left", valign = "top" }

  -- Depth indicator text
  local depthPct = math.floor(morphDepth * 100 + 0.5)
  display[#display + 1] = { cmd = "drawText", x = 4, y = 2, w = w - 8, h = 14, text = "depth " .. depthPct .. "%", color = 0xff64748b, fontSize = 9, align = "right", valign = "top" }

  if not hasSample then
    display[#display + 1] = { cmd = "drawText", x = 0, y = h - 22, w = w, h = 16, text = "No sample - capture in Sample tab", color = 0xff64748b, fontSize = 9, align = "center", valign = "middle" }
  elseif not hasLiveVoice then
    display[#display + 1] = { cmd = "drawText", x = 0, y = h - 22, w = w, h = 16, text = "Play a note to animate Morph", color = 0xff64748b, fontSize = 9, align = "center", valign = "middle" }
  end

  return display
end

local function buildAddDisplay(ctx, w, h, display)
  -- Add mode temporal display
  local blendAmount = math.max(0.0, math.min(1.0, ctx.blendAmount or 0.5))
  local addCol = 0xffc084fc  -- purple for Add mode
  local time = ctx.animTime or 0
  local voices = ctx.activeVoices or {}
  local dominantFreq = 220.0
  local dominantAmp = 0.0
  local dominantSamplePos = 0.0
  local samplePositions = (type(getVoiceSamplePositions) == "function") and (getVoiceSamplePositions() or {}) or {}
  local dominantVoiceIndex = nil
  for _, v in ipairs(voices) do
    if (v.amp or 0) > dominantAmp then
      dominantFreq = v.freq or 220.0
      dominantAmp = v.amp or 0
      dominantVoiceIndex = v.voiceIndex
    end
  end
  if dominantVoiceIndex then
    dominantSamplePos = math.max(0.0, math.min(1.0, tonumber(samplePositions[dominantVoiceIndex]) or 0.0))
  end

  -- Temporal shaping params (same as DSP uses)
  local morphStretch = math.max(0.0, math.min(1.0, tonumber(ctx.morphStretch) or tonumber(ctx.morphConvergence) or 0.0))
  local morphTilt = math.max(0, math.min(2, math.floor((tonumber(ctx.morphTilt) or tonumber(ctx.morphPhase) or 0) + 0.5)))
  local visualSpeed = math.max(0.1, math.min(4.0, tonumber(ctx.morphSpeed) or 1.0))
  local visualContrast = math.max(0.0, math.min(2.0, tonumber(ctx.morphContrast) or 0.5))

  -- Ensure temporal analysis has run
  if type(ensureSampleAnalysis) == "function" then
    ensureSampleAnalysis()
  end

  -- Get temporal partials
  local temporalPartials = (type(getLatestTemporalPartials) == "function") and getLatestTemporalPartials() or nil
  
  -- Apply temporal shaping: get frame at the mapped position
  local samplePartials = nil
  local hasTemporal = type(temporalPartials) == "table" and (tonumber(temporalPartials.frameCount) or 0) > 1
  if hasTemporal then
    samplePartials = temporalFramePreviewAtPosition(temporalPartials, (dominantSamplePos * visualSpeed) % 1.0)
  end
  if not samplePartials then
    samplePartials = (type(getLatestSamplePartials) == "function") and getLatestSamplePartials() or nil
  end

  local wavePartials = buildWavePreviewPartials(ctx, dominantFreq)
  local addFlavor = tonumber(ctx.addFlavor) or 0
  local hasSample = samplePartials and (samplePartials.activeCount or 0) > 0
  local hasWave = wavePartials and (wavePartials.activeCount or 0) > 0
  local hasLiveVoice = dominantAmp > 0.001

  -- Apply spectral shaping to sample partials (Tilt/Stretch) - same as DSP
  local shapedPartials = samplePartials
  if hasSample and (morphStretch > 0.001 or morphTilt > 0) then
    shapedPartials = applyMorphPreviewShaping(samplePartials, morphStretch, morphTilt)
  end

  -- Layout
  local ridgeTop = 46
  local ridgeBottom = h - 16
  local waveH = math.max(34, ridgeBottom - ridgeTop)
  local centerY = ridgeTop + waveH * 0.72
  local maxAmp = (waveH / 2) * 0.56

  -- Temporal cursor
  if hasTemporal and hasLiveVoice and hasSample then
    local cursorX = math.floor(12 + (w - 44) * ((dominantSamplePos * visualSpeed) % 1.0))
    display[#display + 1] = { cmd = "drawLine", x1 = cursorX, y1 = ridgeTop - 8, x2 = cursorX, y2 = ridgeBottom, thickness = 1, color = 0x55c084fc }
    display[#display + 1] = { cmd = "fillRect", x = math.floor(cursorX - 1), y = ridgeTop - 10, w = 3, h = 3, color = addCol }
  end

  -- Temporal ridge panel
  do
    local ridgePoints = math.max(16, math.min(w, 24))
    local ridgeDy = 8
    local ridgeDx = 6
    local ridgeScale = maxAmp * (0.90 + visualContrast * 0.20)
    local ridgeLeft = 12
    local ridgeRightPad = 12
    local maxDepthDx = 7 * ridgeDx
    local ridgeWidth = math.max(80, w - ridgeLeft - ridgeRightPad - maxDepthDx)
    local ridgePalette = {
      0xffa78bfa, 0xffc4b5fd, 0xffa78bfa, 0xff8b5cf6,
      0xffc084fc, 0xffe879f9, 0xfff0abfc, 0xffc084fc,
    }
    local history = ctx._addRidgeHistory or {}
    local lastPos = tonumber(ctx._lastAddRidgePos)
    local lastPushTime = tonumber(ctx._lastAddRidgeTime) or 0.0

    local function buildRidgePoints(phaseOffset)
      local pts = {}
      for i = 0, ridgePoints do
        local t = i / ridgePoints
        local phase = phaseOffset + t * 2.0
        local waveSig = hasWave and synthFromPartials(wavePartials, phase) or 0.0
        local sampleSig = shapedPartials and synthFromPartials(shapedPartials, phase) or 0.0
        if addFlavor == 1 then
          sampleSig = drivenSamplePreview(ctx, sampleSig, phase)
        end
        local sig = waveSig * (1.0 - blendAmount) + sampleSig * blendAmount
        local x = math.floor(ridgeLeft + t * ridgeWidth)
        local y = math.floor(centerY - sig * ridgeScale)
        pts[i + 1] = { x = x, y = y }
      end
      return pts
    end

    local phaseRate = math.max(0.15, dominantFreq / 220.0)
    local livePhase = time * phaseRate

    if (hasSample or hasWave) and hasLiveVoice then
      local posDelta = (lastPos ~= nil) and math.abs((dominantSamplePos * visualSpeed) % 1.0 - lastPos) or 1.0
      if posDelta > (0.012 / math.max(0.35, visualSpeed)) or math.abs(time - lastPushTime) > (0.06 / math.max(0.35, visualSpeed)) or #history == 0 then
        history[#history + 1] = {
          points = buildRidgePoints(livePhase),
          pos = (dominantSamplePos * visualSpeed) % 1.0,
        }
        while #history > 8 do table.remove(history, 1) end
        ctx._lastAddRidgePos = (dominantSamplePos * visualSpeed) % 1.0
        ctx._lastAddRidgeTime = time
      end
      ctx._addRidgeHistory = history
    else
      ctx._addRidgeHistory = {}
      ctx._lastAddRidgePos = nil
      ctx._lastAddRidgeTime = nil
      history = {}
    end

    if #history > 0 then
      display[#display + 1] = { cmd = "drawText", x = ridgeLeft, y = ridgeTop - 14, w = 72, h = 12, text = "PAST", color = 0xff64748b, fontSize = 8, align = "left", valign = "top" }
      display[#display + 1] = { cmd = "drawText", x = ridgeLeft + ridgeWidth + maxDepthDx - 48, y = ridgeTop - 14, w = 48, h = 12, text = "NOW", color = addCol, fontSize = 8, align = "right", valign = "top" }

      local livePoints = (hasSample or hasWave) and buildRidgePoints(livePhase) or {}

      for si = 1, #history do
        local depth = (#history - si) + 1
        local slice = history[si]
        local dx = depth * ridgeDx
        local dy = depth * ridgeDy
        local alpha = math.max(0x40, 0xd0 - depth * 14)
        local thick = (depth <= 2) and 2 or 1
        local baseColor = ridgePalette[math.min(#ridgePalette, si)] or addCol
        local color = (baseColor & 0x00ffffff) | (alpha << 24)
        local pts = slice.points
        for i = 2, #pts do
          display[#display + 1] = {
            cmd = "drawLine",
            x1 = pts[i - 1].x + dx, y1 = pts[i - 1].y - dy,
            x2 = pts[i].x + dx, y2 = pts[i].y - dy,
            thickness = thick,
            color = color,
          }
        end
      end

      -- Live front slice
      if #livePoints > 0 then
        for i = 2, #livePoints do
          local c1 = ridgePalette[math.min(#ridgePalette, i - 1)] or addCol
          display[#display + 1] = {
            cmd = "drawLine",
            x1 = livePoints[i - 1].x, y1 = livePoints[i - 1].y,
            x2 = livePoints[i].x, y2 = livePoints[i].y,
            thickness = 3,
            color = c1,
          }
        end
      end
    end
  end

  -- Labels
  local label = "ADD"
  if hasTemporal then
    label = "ADD · TEMPORAL " .. (tonumber(temporalPartials.frameCount) or 0) .. " frames"
  end
  display[#display + 1] = { cmd = "drawText", x = 4, y = 2, w = w - 8, h = 14, text = label, color = addCol, fontSize = 11, align = "left", valign = "top" }
  display[#display + 1] = { cmd = "drawText", x = 4, y = 2, w = w - 8, h = 14, text = "blend " .. math.floor(blendAmount * 100 + 0.5) .. "%", color = 0xff64748b, fontSize = 9, align = "right", valign = "top" }

  if not hasSample then
    display[#display + 1] = { cmd = "drawText", x = 0, y = h - 22, w = w, h = 16, text = "No sample temporal data - capture in Sample tab", color = 0xff64748b, fontSize = 9, align = "center", valign = "middle" }
  elseif not hasLiveVoice then
    display[#display + 1] = { cmd = "drawText", x = 0, y = h - 22, w = w, h = 16, text = "Play a note to animate Add", color = 0xff64748b, fontSize = 9, align = "center", valign = "middle" }
  end

  return display
end

local function buildBlendDisplay(ctx, w, h, display)
  local waveType = ctx.waveformType or 1
  local drive = math.max(0.0, ctx.driveAmount or 0.0)
  local driveShape = ctx.driveShape or 0
  local driveBias = ctx.driveBias or 0.0
  local driveMix = ctx.driveMix or 1.0
  local blendMode = ctx.blendMode or 0
  local blendAmount = math.max(0.0, math.min(1.0, ctx.blendAmount or 0.5))
  local blendModAmount = math.max(0.0, math.min(1.0, ctx.blendModAmount or 0.5))
  local waveToSample = blendAmount
  local sampleToWave = 1.0 - blendAmount
  local samplePitch = ctx.blendSamplePitch or 0.0
  local voices = ctx.activeVoices or {}
  local time = ctx.animTime or 0
  local peaks = ctx._cachedPeaks
  local pointCap = tonumber(ctx.maxPoints) or 200
  if (ctx.renderMode or 0) == 1 then
    pointCap = math.min(pointCap, 96)
  end
  local numPoints = math.max(64, math.min(w, pointCap))
  local centerY = h / 2
  local maxAmp = (h / 2) * 0.82
  local modeNames = { [0] = "MIX", [1] = "RING", [2] = "FM", [3] = "SYNC", [4] = "ADD", [5] = "MORPH" }
  local modeColors = { [0] = 0xffa78bfa, [1] = 0xff22d3ee, [2] = 0xfff472b6, [3] = 0xff4ade80, [4] = 0xffc084fc, [5] = 0xfff97316 }

  if blendMode == 5 then
    return buildMorphDisplay(ctx, w, h, display)
  end

  -- Add mode: show temporal display similar to Morph but with Add-specific visuals
  if blendMode == 4 then
    return buildAddDisplay(ctx, w, h, display)
  end

  -- Background grid (like Wave mode)
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

  if not peaks and type(getSynthSamplePeaks) == "function" then
    peaks = getSynthSamplePeaks(numPoints)
    if peaks and #peaks > 0 then
      ctx._cachedPeaks = peaks
    end
  end

  local hasSample = peaks and #peaks > 0
  local waveCol = WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local sampleCol = 0xff22d3ee
  local resultCol = modeColors[blendMode] or 0xffa78bfa

  -- Draw source waveforms dimmed in background
  local prevWaveX, prevWaveY
  local prevSampleX, prevSampleY

  for i = 0, numPoints do
    local t = i / numPoints
    local wave = applyDriveShape(renderWaveSample(ctx, waveType, t * 2.0), drive, driveShape, driveBias, driveMix)
    local sampleT = t * (2.0 ^ (samplePitch / 12.0))
    local sample = hasSample and sampleAtPeaks(peaks, sampleT % 1.0) or 0

    local x = math.floor(t * w)
    local waveY = math.floor(centerY - wave * maxAmp * 0.5)
    local sampleY = math.floor(centerY - sample * maxAmp * 0.5)

    if prevWaveX then
      -- Dimmed wave and sample in background
      display[#display + 1] = {
        cmd = "drawLine", x1 = prevWaveX, y1 = prevWaveY, x2 = x, y2 = waveY,
        thickness = 1, color = (waveCol & 0x00ffffff) | 0x30000000,
      }
      if hasSample then
        display[#display + 1] = {
          cmd = "drawLine", x1 = prevSampleX, y1 = prevSampleY, x2 = x, y2 = sampleY,
          thickness = 1, color = (sampleCol & 0x00ffffff) | 0x30000000,
        }
      end
    end

    prevWaveX, prevWaveY = x, waveY
    prevSampleX, prevSampleY = x, sampleY
  end

  -- Animated result waveform (main focus)
  if #voices > 0 then
    for vi, voice in ipairs(voices) do
      local vcol = VOICE_COLORS[((vi - 1) % #VOICE_COLORS) + 1]
      local freq = voice.freq or 220
      local amp = voice.amp or 0
      if amp < 0.001 then goto continue end

      local cyclesInView = 2
      local phaseOffset = time * freq
      local vPrevX, vPrevY

      for i = 0, numPoints do
        local t = i / numPoints
        local phase = phaseOffset + t * cyclesInView
        local wave = applyDriveShape(renderWaveSample(ctx, waveType, phase), drive, driveShape, driveBias, driveMix)
        local sampleT = t * (2.0 ^ (samplePitch / 12.0))
        local sample = hasSample and sampleAtPeaks(peaks, sampleT % 1.0) or 0

        local result = 0.0
        if blendMode == 0 then
          result = wave * (1.0 - blendAmount) + sample * blendAmount
        elseif blendMode == 1 then
          local ring = wave * sample
          result = (wave * (1.0 - blendAmount)) + (ring * blendAmount * math.max(0.2, blendModAmount))
        elseif blendMode == 2 then
          local fmSample = hasSample and sampleAtPeaks(peaks, (sampleT + wave * waveToSample * blendModAmount * 0.12) % 1.0) or 0
          result = wave * (1.0 - blendAmount) + fmSample * blendAmount + sample * sampleToWave * 0.15
        elseif blendMode == 3 then
          local syncT = ((t * (1.0 + waveToSample * 3.0)) % 1.0)
          local syncSample = hasSample and sampleAtPeaks(peaks, syncT) or 0
          result = wave * (1.0 - blendAmount) + syncSample * blendAmount
        elseif blendMode == 4 then
          local addFlavor = tonumber(ctx.addFlavor) or 0
          local sampleAdd = (addFlavor == 1) and drivenSamplePreview(ctx, sample, phase) or sample
          result = wave * (1.0 - blendAmount) + sampleAdd * blendAmount
        elseif blendMode == 5 then
          -- Morph mode: smooth interpolation between wave and sample
          -- Use equal-power crossfade for smoother sound
          local sqrtAmount = math.sqrt(blendAmount)
          local sqrtOneMinus = math.sqrt(1.0 - blendAmount)
          result = wave * sqrtOneMinus + sample * sqrtAmount
        else
          result = wave * (1.0 - blendAmount) + sample * blendAmount
        end

        result = result * (amp / 0.5)
        local x = math.floor(t * w)
        local y = math.floor(centerY - result * maxAmp)

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
  else
    -- Static result preview when no voices active
    local prevResultX, prevResultY
    for i = 0, numPoints do
      local t = i / numPoints
      local wave = applyDriveShape(renderWaveSample(ctx, waveType, t * 2.0), drive, driveShape, driveBias, driveMix)
      local sampleT = t * (2.0 ^ (samplePitch / 12.0))
      local sample = hasSample and sampleAtPeaks(peaks, sampleT % 1.0) or 0

      local result = 0.0
      if blendMode == 0 then
        result = wave * (1.0 - blendAmount) + sample * blendAmount
      elseif blendMode == 1 then
        local ring = wave * sample
        result = (wave * (1.0 - blendAmount)) + (ring * blendAmount * math.max(0.2, blendModAmount))
      elseif blendMode == 2 then
        local fmSample = hasSample and sampleAtPeaks(peaks, (sampleT + wave * waveToSample * blendModAmount * 0.12) % 1.0) or 0
        result = wave * (1.0 - blendAmount) + fmSample * blendAmount
      elseif blendMode == 3 then
        local syncT = ((t * (1.0 + waveToSample * 3.0)) % 1.0)
        local syncSample = hasSample and sampleAtPeaks(peaks, syncT) or 0
        result = wave * (1.0 - blendAmount) + syncSample * blendAmount
      elseif blendMode == 4 then
        local addFlavor = tonumber(ctx.addFlavor) or 0
        local sampleAdd = (addFlavor == 1) and drivenSamplePreview(ctx, sample, t * 2.0) or sample
        result = wave * (1.0 - blendAmount) + sampleAdd * blendAmount
      elseif blendMode == 5 then
        -- Morph mode: smooth interpolation between wave and sample
        local sqrtAmount = math.sqrt(blendAmount)
        local sqrtOneMinus = math.sqrt(1.0 - blendAmount)
        result = wave * sqrtOneMinus + sample * sqrtAmount
      else
        result = wave * (1.0 - blendAmount) + sample * blendAmount
      end

      local x = math.floor(t * w)
      local y = math.floor(centerY - result * maxAmp)

      if prevResultX then
        display[#display + 1] = {
          cmd = "drawLine", x1 = prevResultX, y1 = prevResultY, x2 = x, y2 = y,
          thickness = 2, color = resultCol,
        }
      end
      prevResultX, prevResultY = x, y
    end
  end

  -- Mode indicator bar at bottom
  local modeName = modeNames[blendMode] or "MIX"
  local barWidth = math.floor(w * blendAmount)
  display[#display + 1] = {
    cmd = "fillRect", x = 0, y = h - 4, w = barWidth, h = 4,
    color = resultCol,
  }
  display[#display + 1] = {
    cmd = "drawRect", x = 0, y = h - 4, w = w, h = 4,
    thickness = 1, color = 0xff334155,
  }

  -- Clean mode label
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = modeName .. " MODE",
    color = resultCol, fontSize = 11, align = "left", valign = "top",
  }

  -- Sample status
  if not hasSample then
    display[#display + 1] = {
      cmd = "drawText", x = 0, y = h - 22, w = w, h = 16,
      text = "No sample - capture in Sample tab", color = 0xff64748b, fontSize = 9, align = "center", valign = "middle",
    }
  end

  return display
end

local function buildOscDisplay(ctx, w, h)
  local display = {}
  local waveType = ctx.waveformType or 1
  local drive = math.max(0.0, ctx.driveAmount or 0.0)
  local driveShape = ctx.driveShape or 0
  local driveBias = ctx.driveBias or 0.0
  local driveMix = ctx.driveMix or 1.0
  local voices = ctx.activeVoices or {}
  local time = ctx.animTime or 0
  local oscMode = ctx.oscMode or 0

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

  if oscMode == 1 then
    return buildSampleWaveform(ctx, w, h, display)
  elseif oscMode == 2 then
    return buildBlendDisplay(ctx, w, h, display)
  end

  -- Wave mode title (top-left like Sample/Blend)
  local waveNames = { [0] = "SINE", [1] = "SAW", [2] = "SQUARE", [3] = "TRIANGLE", [4] = "BLEND", [5] = "NOISE", [6] = "PULSE", [7] = "SUPERSAW" }
  local waveName = waveNames[waveType] or "WAVE"
  local col = WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local renderLabel = (ctx.renderMode == 1) and " ADD" or ""
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = waveName .. renderLabel .. " MODE", color = col, fontSize = 11, align = "left", valign = "top",
  }
  local colDim = (0x40 << 24) | (col & 0x00ffffff)
  local centerY = h / 2
  local maxAmp = (h / 2) * 0.85
  local pointCap = math.max(48, tonumber(ctx.maxPoints) or 200)
  if (ctx.renderMode or 0) == 1 then
    pointCap = math.min(pointCap, 96)
  end
  local numPoints = math.max(48, math.min(w, pointCap))

  local colStatic = (0x40 << 24) | (col & 0x00ffffff)
  local prevX, prevY
  for i = 0, numPoints do
    local t = i / numPoints
    local s = renderWaveSample(ctx, waveType, t)
    s = applyDriveShape(s, drive, driveShape, driveBias, driveMix)

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

  if #voices > 0 then
    local drawFill = (#voices <= 1)
    for vi, voice in ipairs(voices) do
      local vcol = VOICE_COLORS[((vi - 1) % #VOICE_COLORS) + 1]
      local vcolDim = (0x20 << 24) | (vcol & 0x00ffffff)
      local freq = voice.freq or 220
      local amp = voice.amp or 0
      if amp < 0.001 then goto continue end

      local cyclesInView = 2
      local phaseOffset = time * freq
      local vPrevX, vPrevY

      for i = 0, numPoints do
        local t = i / numPoints
        local phase = phaseOffset + t * cyclesInView
        local s = renderWaveSample(ctx, waveType, phase)
        s = applyDriveShape(s, drive, driveShape, driveBias, driveMix)

        s = s * (amp / 0.5)
        local x = math.floor(t * w)
        local y = math.floor(centerY - s * maxAmp)

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

  return display
end

local function refreshDriveCurve(ctx)
  local curve = ctx.widgets and ctx.widgets.drive_curve
  if not curve or not curve.node then
    return
  end

  local drive = math.max(0.0, tonumber(ctx.driveAmount) or 0.0)
  local driveShape = ctx.driveShape or 0
  local driveBias = ctx.driveBias or 0.0
  local driveMix = ctx.driveMix or 1.0
  local probeX = 0.6
  local probeY = applyDriveShape(probeX, drive, driveShape, driveBias, driveMix)
  local pointY = 1.0 - ((probeY + 1.0) * 0.5)
  local curveKey = string.format("%d:%.4f:%.4f:%.4f", tonumber(driveShape) or 0, drive, driveBias, driveMix)

  if ctx._lastDriveCurveValue ~= curveKey then
    if curve.setCurveSampler then
      curve:setCurveSampler(function(x)
        return applyDriveShape(x, drive, driveShape, driveBias, driveMix)
      end)
    end
    if curve.setControlPoints then
      curve:setControlPoints({
        { x = (probeX + 1.0) * 0.5, y = pointY, mirrored = true },
      })
    end
    ctx._lastDriveCurveValue = curveKey
  else
    curve:refreshRetained()
    curve.node:repaint()
  end
end

local function refreshGraph(ctx)
  local graph = ctx.widgets.osc_graph
  if not graph or not graph.node then
    refreshDriveCurve(ctx)
    return
  end
  local w = graph.node:getWidth()
  local h = graph.node:getHeight()
  if w <= 0 or h <= 0 then
    refreshDriveCurve(ctx)
    return
  end
  if type(getVoiceLoopData) == "function" then
    ctx.voiceLoops = getVoiceLoopData()
  end
  graph.node:setDisplayList(buildOscDisplay(ctx, w, h))
  graph.node:repaint()
  refreshDriveCurve(ctx)
end

function OscBehavior.init(ctx)
  ctx.waveformType = 1
  ctx.renderMode = 0
  ctx.pulseWidth = 0.5
  ctx.unison = 1
  ctx.detune = 0.0
  ctx.spread = 0.0
  ctx.additivePartials = 8
  ctx.additiveTilt = 0.0
  ctx.additiveDrift = 0.0
  ctx.driveAmount = 0.0
  ctx.driveShape = 0
  ctx.driveBias = 0.0
  ctx.driveMix = 1.0
  ctx.outputLevel = 0.8
  ctx.activeVoices = {}
  ctx.animTime = 0
  ctx.oscMode = 0
  ctx.sampleLoopStart = 0.0
  ctx.sampleLoopLen = 1.0
  ctx.samplePlayStart = 0.0  -- Yellow flag: where playback starts
  ctx.sampleCrossfade = 0.1  -- 0-0.5 crossfade amount
  ctx.blendMode = 0
  ctx.blendAmount = 0.5
  ctx.waveToSample = 0.5
  ctx.sampleToWave = 0.0
  ctx.blendKeyTrack = true
  ctx.blendSamplePitch = 0.0
  ctx.blendModAmount = 0.5
  ctx.rangeView = "global"  -- FORCED: only global windowing works
  ctx.rangeViewIndex = 2    -- "global" is index 2 in the views table
  ctx.voiceLoops = {}
  -- Initialize knob layout state to match initial waveform (saw = not pulse)
  ctx._lastKnobLayoutPulse = false
  ctx._lastDriveCurveValue = nil

  ctx._rangeDrag = {
    active = false,
    dragging = nil,
    voiceIndex = nil,
    grabOffset = 0,
  }
  ctx._flagDrag = {
    active = false,
    which = nil,
    grabOffset = 0,
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
  local pad = 10
  local gap = 6

  local graph = widgets.osc_graph
  local tabHost = widgets.mode_tabs
  local title = widgets.title
  local blendK = widgets.blend_amount_knob
  local outK = widgets.output_knob
  local unisonK = widgets.unison_knob
  local detuneK = widgets.detune_knob
  local spreadK = widgets.spread_knob

  local footerGap = 6
  local footerSliderH = 22
  local footerGapInner = 8
  local controlGap = 8
  local controlSliderH = 20
  local controlRowGap = 8

  local footerSliderW = 0
  local footerY = 0

  local function placeControlRow(x, y, width)
    local rowW = math.max(96, width)
    local colW = math.max(48, math.floor((rowW - controlRowGap * 2) / 3))
    local detuneX = x + colW + controlRowGap
    local spreadX = detuneX + colW + controlRowGap
    if unisonK then
      if unisonK.setVisible then unisonK:setVisible(true) end
      if unisonK.setBounds then unisonK:setBounds(x, y, colW, controlSliderH)
      elseif unisonK.node then unisonK.node:setBounds(x, y, colW, controlSliderH) end
    end
    if detuneK then
      if detuneK.setVisible then detuneK:setVisible(true) end
      if detuneK.setBounds then detuneK:setBounds(detuneX, y, colW, controlSliderH)
      elseif detuneK.node then detuneK.node:setBounds(detuneX, y, colW, controlSliderH) end
    end
    if spreadK then
      if spreadK.setVisible then spreadK:setVisible(true) end
      if spreadK.setBounds then spreadK:setBounds(spreadX, y, colW, controlSliderH)
      elseif spreadK.node then spreadK.node:setBounds(spreadX, y, colW, controlSliderH) end
    end
  end

  if w < 300 then
    local contentW = w - pad * 2
    footerSliderW = math.max(48, math.floor((contentW - footerGapInner) / 2))
    footerY = h - pad - footerSliderH
    local controlY = footerY - footerGap - controlSliderH
    local graphH = math.max(48, controlY - controlGap - pad)

    if graph then
      if graph.setBounds then graph:setBounds(pad, pad, contentW, graphH)
      elseif graph.node then graph.node:setBounds(pad, pad, contentW, graphH) end
    end
    if tabHost then
      if tabHost.setVisible then tabHost:setVisible(false) end
      if tabHost.setBounds then tabHost:setBounds(0, 0, 0, 0)
      elseif tabHost.node then tabHost.node:setBounds(0, 0, 0, 0) end
    end
    if title then
      if title.setVisible then title:setVisible(false) end
      if title.setBounds then title:setBounds(0, 0, 0, 0)
      elseif title.node then title.node:setBounds(0, 0, 0, 0) end
    end

    placeControlRow(pad + 6, controlY, math.max(96, contentW - 12))
  else
    if tabHost then
      if tabHost.setVisible then tabHost:setVisible(true) end
    end
    if title then
      if title.setVisible then title:setVisible(true) end
    end

    local split = math.floor(w / 2)
    local leftW = split - pad
    local rightX = split + gap
    local rightW = w - rightX - pad

    footerSliderW = math.max(56, math.floor((leftW - footerGapInner) / 2))
    footerY = h - pad - footerSliderH
    local controlY = footerY - footerGap - controlSliderH
    local graphH = math.max(60, controlY - controlGap - pad)
    local tabH = h - pad * 2

    if graph then
      if graph.setBounds then graph:setBounds(pad, pad, leftW, graphH)
      elseif graph.node then graph.node:setBounds(pad, pad, leftW, graphH) end
    end

    placeControlRow(pad + 6, controlY, math.max(96, leftW - 12))

    if tabHost then
      if tabHost.setBounds then tabHost:setBounds(rightX, pad, rightW, tabH)
      elseif tabHost.node then tabHost.node:setBounds(rightX, pad, rightW, tabH) end

      if not ctx._tabHandlerSet then
        ctx._tabHandlerSet = true
        tabHost:setOnSelect(function(idx, id, title)
          local newMode = 0
          if idx == 2 then
            newMode = 1
          elseif idx == 3 then
            newMode = 2
          end
          ctx.oscMode = newMode
          refreshGraph(ctx)
        end)
      end
    end
  end

  if graph and graph.node and not ctx._rangeMouseSetup then
    ctx._rangeMouseSetup = true
    graph.node:setInterceptsMouse(true, false)

    graph.node:setOnMouseDown(function(mx, my, shift)
      if ctx.oscMode ~= 1 then return end
      local gw = graph.node:getWidth()
      local gh = graph.node:getHeight()
      if gw <= 0 or gh <= 0 then return end

      local barH = 16
      local barGap = 4
      local barsHeight = barH * 2 + barGap
      local waveH = gh - barsHeight - 4
      local handleW = 8
      local minLoopLen = 0.05

      local loopStart = ctx.sampleLoopStart or 0.0
      local loopLen = ctx.sampleLoopLen or 1.0
      local playStart = ctx.samplePlayStart or 0.0
      local loopEnd = loopStart + loopLen

      local bar1Y = waveH + 2
      if my >= bar1Y and my <= bar1Y + barH then
        local playHandleX = math.floor(playStart * gw) - math.floor(handleW / 2)
        if mx >= playHandleX - 2 and mx <= playHandleX + handleW + 2 then
          ctx._flagDrag = { active = true, which = "play", grabOffset = mx - (playHandleX + handleW / 2) }
          return
        end
      end

      local bar2Y = bar1Y + barH + barGap
      if my >= bar2Y and my <= bar2Y + barH then
        local loopHandleX = math.floor(loopStart * gw) - math.floor(handleW / 2)
        local endHandleX = math.floor(loopEnd * gw) - math.floor(handleW / 2)
        local spanStartX = math.floor(loopStart * gw)
        local spanEndX = math.floor(loopEnd * gw)

        if shift and mx >= spanStartX and mx <= spanEndX then
          ctx._flagDrag = {
            active = true,
            which = "window",
            grabOffset = mx - spanStartX,
            windowLen = math.max(minLoopLen, loopLen),
          }
          return
        end

        if mx >= loopHandleX - 2 and mx <= loopHandleX + handleW + 2 then
          ctx._flagDrag = { active = true, which = "loop", grabOffset = mx - (loopHandleX + handleW / 2) }
          return
        end
        if mx >= endHandleX - 2 and mx <= endHandleX + handleW + 2 then
          ctx._flagDrag = { active = true, which = "end", grabOffset = mx - (endHandleX + handleW / 2) }
          return
        end
      end
    end)

    graph.node:setOnMouseDrag(function(mx, my)
      if not ctx._flagDrag or not ctx._flagDrag.active then return end
      local gw = graph.node:getWidth()
      if gw <= 4 then return end

      local minLoopLen = 0.05
      local grabOffset = ctx._flagDrag.grabOffset or 0
      local adjustedMx = mx - grabOffset
      local pos = math.max(0, math.min(1, adjustedMx / gw))

      local loopStart = ctx.sampleLoopStart or 0.0
      local loopLen = ctx.sampleLoopLen or 1.0
      local loopEnd = loopStart + loopLen

      if ctx._flagDrag.which == "play" then
        ctx.samplePlayStart = pos
        if ctx._onPlayStartChange then ctx._onPlayStartChange(pos) end
      elseif ctx._flagDrag.which == "window" then
        local windowLen = math.max(minLoopLen, ctx._flagDrag.windowLen or loopLen)
        local newStart = math.max(0.0, math.min(1.0 - windowLen, adjustedMx / gw))
        ctx.sampleLoopStart = newStart
        ctx.sampleLoopLen = windowLen
        if ctx._onRangeChange then
          ctx._onRangeChange("start", newStart)
          ctx._onRangeChange("len", windowLen)
        end
      elseif ctx._flagDrag.which == "loop" then
        pos = math.min(pos, loopEnd - minLoopLen)
        local newLen = loopEnd - pos
        ctx.sampleLoopStart = pos
        ctx.sampleLoopLen = newLen
        if ctx._onRangeChange then
          ctx._onRangeChange("start", pos)
          ctx._onRangeChange("len", newLen)
        end
      elseif ctx._flagDrag.which == "end" then
        pos = math.max(pos, loopStart + minLoopLen)
        local newLen = pos - loopStart
        ctx.sampleLoopLen = newLen
        if ctx._onRangeChange then ctx._onRangeChange("len", newLen) end
      end
      refreshGraph(ctx)
    end)

    graph.node:setOnMouseUp(function()
      if ctx._flagDrag then
        ctx._flagDrag.active = false
        ctx._flagDrag.which = nil
        ctx._flagDrag.grabOffset = nil
      end
    end)
  end

  local footerX = pad
  if blendK then
    if blendK.setVisible then blendK:setVisible(true) end
    if blendK.setBounds then blendK:setBounds(footerX, footerY, footerSliderW, footerSliderH)
    elseif blendK.node then blendK.node:setBounds(footerX, footerY, footerSliderW, footerSliderH) end
  end

  if outK then
    local outX = footerX + footerSliderW + footerGapInner
    if outK.setVisible then outK:setVisible(true) end
    if outK.setBounds then outK:setBounds(outX, footerY, footerSliderW, footerSliderH)
    elseif outK.node then outK.node:setBounds(outX, footerY, footerSliderW, footerSliderH) end
  end

  refreshGraph(ctx)
end

function OscBehavior.repaint(ctx)
  refreshGraph(ctx)
end

OscBehavior.refreshDriveCurve = refreshDriveCurve

-- Update wave-tab compact slider visibility/layout based on waveform + render mode.
-- Add mode gets three dedicated controls; pulse add uses a 2x2 grid with Width.
function OscBehavior.updateKnobLayout(ctx)
  local widgets = ctx.widgets
  if not widgets then return end

  local tabHost = widgets.mode_tabs
  local waveformDropdown = widgets.waveform_dropdown
  local renderModeTabs = widgets.render_mode_tabs
  local driveModeDropdown = widgets.drive_mode_dropdown
  local driveKnob = widgets.drive_knob
  local driveBiasKnob = widgets.drive_bias_knob
  local driveCurve = widgets.drive_curve
  local widthKnob = widgets.pulse_width_knob
  local addPartialsKnob = widgets.add_partials_knob
  local addTiltKnob = widgets.add_tilt_knob
  local addDriftKnob = widgets.add_drift_knob

  local isPulse = (ctx.waveformType == 6)
  local isAdd = (ctx.renderMode == 1)

  local widgetsNeedingRefresh = {}

  local function queueWidgetRefresh(widget, w, h)
    if not widget then return end
    widgetsNeedingRefresh[#widgetsNeedingRefresh + 1] = { widget = widget, w = w, h = h }
  end

  local function setVisible(widget, visible)
    if not widget or not widget.node then return end
    local node = widget.node
    local nextVisible = visible == true
    local changed = node.isVisible and (node:isVisible() ~= nextVisible)
    if widget.setVisible then
      widget:setVisible(nextVisible)
    elseif node.setVisible then
      node:setVisible(nextVisible)
    end
    if changed then
      queueWidgetRefresh(widget, node.getWidth and node:getWidth() or nil, node.getHeight and node:getHeight() or nil)
    end
  end

  setVisible(widthKnob, isPulse)
  setVisible(addPartialsKnob, isAdd)
  setVisible(addTiltKnob, isAdd)
  setVisible(addDriftKnob, isAdd)

  local availableW = 220
  local availableH = 156
  if tabHost and tabHost.node then
    if tabHost.node.getWidth then
      availableW = math.max(180, tabHost.node:getWidth())
    end
    if tabHost.node.getHeight then
      availableH = math.max(120, tabHost.node:getHeight() - 24)
    end
  end

  local layoutKey = string.format("%s:%s:%d:%d", tostring(isPulse), tostring(isAdd), math.floor(availableW + 0.5), math.floor(availableH + 0.5))
  if ctx._lastWaveKnobLayoutKey == layoutKey then
    return
  end
  ctx._lastWaveKnobLayoutKey = layoutKey
  ctx._lastKnobLayoutPulse = isPulse

  local function setBoundsIfDifferent(widget, x, y, w, h)
    if not widget or not widget.node or not widget.node.getBounds then return end
    local node = widget.node
    local cx, cy, cw, ch = node:getBounds()
    if cx ~= x or cy ~= y or cw ~= w or ch ~= h then
      node:setBounds(x, y, w, h)
      queueWidgetRefresh(widget, w, h)
    end
  end

  local outerPad = 10
  local colGap = 8
  local rowGap = 6
  local topY = 4
  local sliderH = 20
  local dropdownX = 4
  local renderTabsW = 84
  local renderTabsX = availableW - outerPad - renderTabsW
  local dropdownW = math.max(64, renderTabsX - dropdownX - colGap)
  local controlTopY = 30

  if waveformDropdown and waveformDropdown.node then
    setBoundsIfDifferent(waveformDropdown, dropdownX, topY, dropdownW, sliderH)
  end
  if renderModeTabs and renderModeTabs.node then
    setBoundsIfDifferent(renderModeTabs, renderTabsX, topY, renderTabsW, sliderH)
  end

  local leftAreaX = outerPad
  local fullControlW = math.max(96, availableW - outerPad * 2)
  local halfGap = 6
  local halfW = math.max(46, math.floor((fullControlW - halfGap) / 2))
  local curveY = 82

  if isAdd and not isPulse then
    local row2Y = controlTopY + sliderH + rowGap
    if addPartialsKnob and addPartialsKnob.node then
      setBoundsIfDifferent(addPartialsKnob, leftAreaX, controlTopY, fullControlW, sliderH)
    end
    if addTiltKnob and addTiltKnob.node then
      setBoundsIfDifferent(addTiltKnob, leftAreaX, row2Y, halfW, sliderH)
    end
    if addDriftKnob and addDriftKnob.node then
      setBoundsIfDifferent(addDriftKnob, leftAreaX + halfW + halfGap, row2Y, halfW, sliderH)
    end
  elseif isAdd and isPulse then
    local row1Y = controlTopY
    local row2Y = controlTopY + sliderH + rowGap
    if widthKnob and widthKnob.node then
      setBoundsIfDifferent(widthKnob, leftAreaX, row1Y, halfW, sliderH)
    end
    if addPartialsKnob and addPartialsKnob.node then
      setBoundsIfDifferent(addPartialsKnob, leftAreaX + halfW + halfGap, row1Y, halfW, sliderH)
    end
    if addTiltKnob and addTiltKnob.node then
      setBoundsIfDifferent(addTiltKnob, leftAreaX, row2Y, halfW, sliderH)
    end
    if addDriftKnob and addDriftKnob.node then
      setBoundsIfDifferent(addDriftKnob, leftAreaX + halfW + halfGap, row2Y, halfW, sliderH)
    end
  elseif isPulse and widthKnob and widthKnob.node then
    setBoundsIfDifferent(widthKnob, leftAreaX, controlTopY, fullControlW, sliderH)
  end

  local curveSize = math.max(52, math.min(56, availableH - curveY - 8))
  local curveX = leftAreaX
  local paramColW = math.max(56, math.min(62, fullControlW - curveSize - colGap))
  local rightPanelX = curveX + curveSize + colGap
  local modeY = curveY
  local driveY = modeY + sliderH + rowGap
  local biasY = driveY + sliderH + rowGap

  if driveCurve and driveCurve.node then
    setBoundsIfDifferent(driveCurve, curveX, curveY, curveSize, curveSize)
  end
  if driveModeDropdown and driveModeDropdown.node then
    setBoundsIfDifferent(driveModeDropdown, rightPanelX, modeY, paramColW, sliderH)
  end
  if driveBiasKnob and driveBiasKnob.node then
    setBoundsIfDifferent(driveBiasKnob, rightPanelX, biasY, paramColW, sliderH)
  end
  if driveKnob and driveKnob.node then
    setBoundsIfDifferent(driveKnob, rightPanelX, driveY, paramColW, sliderH)
  end

  for i = 1, #widgetsNeedingRefresh do
    local item = widgetsNeedingRefresh[i]
    local widget = item.widget
    local node = widget and widget.node or nil
    if widget and widget.refreshRetained then
      widget:refreshRetained(item.w, item.h)
    end
    if node and node.markRenderDirty then
      pcall(function() node:markRenderDirty() end)
    end
    if node and node.repaint then
      pcall(function() node:repaint() end)
    end
  end

  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.flushDeferredRefreshes) == "function" and #widgetsNeedingRefresh > 0 then
    pcall(function() shell:flushDeferredRefreshes() end)
  end
end

return OscBehavior

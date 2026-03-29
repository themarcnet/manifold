local M = {}

M.WAVEFORM_COLORS = {
  [0] = 0xff7dd3fc,
  [1] = 0xff38bdf8,
  [2] = 0xff22d3ee,
  [3] = 0xff2dd4bf,
  [4] = 0xffa78bfa,
  [5] = 0xff94a3b8,
  [6] = 0xfff472b6,
  [7] = 0xfffbbf24,
}

local VOICE_COLORS = {
  0xff4ade80, 0xff38bdf8, 0xfffbbf24, 0xfff87171,
  0xffa78bfa, 0xff2dd4bf, 0xfffb923c, 0xfff472b6,
}

local function clamp(v, lo, hi)
  local n = tonumber(v) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function waveformSample(waveType, phase, pulseWidth)
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
    local pseudoRandom = math.sin(p * 43758.5453) % 1.0
    return (pseudoRandom * 2 - 1) * 0.5
  elseif waveType == 6 then
    local width = clamp(pulseWidth or 0.25, 0.01, 0.99)
    return p < width and 1 or -1
  elseif waveType == 7 then
    local s1 = 2 * p - 1
    local s2 = 2 * ((p * 1.01) % 1.0) - 1
    local s3 = 2 * ((p * 0.99) % 1.0) - 1
    return (s1 + s2 * 0.5 + s3 * 0.5) * 0.5
  end
  return 0
end

local function buildAdditiveRecipe(waveType, pulseWidth)
  local width = clamp(pulseWidth, 0.01, 0.99)
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

local function renderAdditiveSample(state, waveType, phase)
  local recipe = buildAdditiveRecipe(waveType, state.pulseWidth or 0.5)
  local partialCount = math.max(1, math.min(#recipe, math.floor((tonumber(state.additivePartials) or 8) + 0.5)))
  local tilt = clamp(state.additiveTilt or 0.0, -1.0, 1.0)
  local drift = clamp(state.additiveDrift or 0.0, 0.0, 1.0)
  local sum = 0.0
  local ampSum = 0.0

  for i = 1, partialCount do
    local partial = recipe[i]
    local ratio = partial.ratio
    local amp = partial.amplitude
    local phaseOffset = partial.phase
    local tiltScale = math.max(0.12, ratio ^ (tilt * 0.85))
    local ratioJitter = math.sin(ratio * 2.173 + waveType * 0.53)
    local phaseJitter = math.sin(ratio * 1.618 + waveType * 0.37)
    local shapedRatio = math.max(0.1, ratio * (1.0 + ratioJitter * drift * 0.035 * (1.0 + ratio * 0.05)))
    local shapedPhase = phaseOffset + phaseJitter * drift * 0.85
    local shapedAmp = amp * tiltScale
    sum = sum + math.sin(2.0 * math.pi * phase * shapedRatio + shapedPhase) * shapedAmp
    ampSum = ampSum + shapedAmp
  end

  if ampSum <= 1.0e-6 then
    return 0.0
  end

  return (sum / ampSum) * additiveOutputTrim(waveType)
end

local function renderWaveSample(state, waveType, phase)
  local pulseWidth = clamp(state.pulseWidth or 0.5, 0.01, 0.99)
  if tonumber(state.renderMode or 0) == 1 then
    return renderAdditiveSample(state, waveType, phase)
  end
  return waveformSample(waveType, phase, pulseWidth)
end

local function foldToUnit(x)
  local v = clamp(x, -32.0, 32.0)
  while v > 1.0 or v < -1.0 do
    if v > 1.0 then
      v = 2.0 - v
    else
      v = -2.0 - v
    end
  end
  return v
end

local function applyDriveTransfer(sample, drive, shape)
  local drv = clamp(drive, 0.0, 20.0)
  if drv <= 0.0001 then
    return clamp(sample, -1.0, 1.0)
  end

  local clippedShape = math.max(0, math.min(3, math.floor((tonumber(shape) or 0) + 0.5)))
  if clippedShape == 1 then
    local gain = 1.0 + drv * 1.35
    local normaliser = math.atan(gain)
    if normaliser <= 1.0e-6 then
      return clamp(sample, -1.0, 1.0)
    end
    return math.atan(sample * gain) / normaliser
  elseif clippedShape == 2 then
    local gain = 1.0 + drv * 1.2
    return clamp(sample * gain, -1.0, 1.0)
  elseif clippedShape == 3 then
    local gain = 1.0 + drv * 1.1
    return foldToUnit(sample * gain)
  end

  local gain = 1.0 + drv * 0.85
  local normaliser = math.tanh(gain)
  if normaliser <= 1.0e-6 then
    return clamp(sample, -1.0, 1.0)
  end
  return math.tanh(sample * gain) / normaliser
end

function M.applyDriveShape(sample, drive, shape, bias, mix)
  local drv = clamp(drive, 0.0, 20.0)
  local wetMix = clamp(mix, 0.0, 1.0)
  if drv <= 0.0001 or wetMix <= 0.0001 then
    return clamp(sample, -1.0, 1.0)
  end

  local biasOffset = clamp(bias, -1.0, 1.0) * 0.75
  local center = applyDriveTransfer(biasOffset, drv, shape)
  local pos = math.abs(applyDriveTransfer(1.0 + biasOffset, drv, shape) - center)
  local neg = math.abs(applyDriveTransfer(-1.0 + biasOffset, drv, shape) - center)
  local normaliser = math.max(1.0e-6, math.max(pos, neg))
  local shaped = (applyDriveTransfer(sample + biasOffset, drv, shape) - center) / normaliser
  local wet = clamp(shaped, -1.0, 1.0)
  return clamp(sample + (wet - sample) * wetMix, -1.0, 1.0)
end

function M.buildWaveDisplay(state, w, h)
  local display = {}
  local waveType = math.max(0, math.min(7, math.floor((tonumber(state.waveformType) or 1) + 0.5)))
  local drive = tonumber(state.driveAmount) or 0.0
  local driveShape = tonumber(state.driveShape) or 0
  local driveBias = tonumber(state.driveBias) or 0.0
  local driveMix = tonumber(state.driveMix) or 1.0
  local col = M.WAVEFORM_COLORS[waveType] or 0xff7dd3fc
  local voices = state.activeVoices or {}
  local time = tonumber(state.animTime) or 0.0

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

  local waveNames = { [0] = "SINE", [1] = "SAW", [2] = "SQUARE", [3] = "TRIANGLE", [4] = "BLEND", [5] = "NOISE", [6] = "PULSE", [7] = "SUPERSAW" }
  local renderLabel = (tonumber(state.renderMode or 0) == 1) and " ADD" or ""
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = (waveNames[waveType] or "WAVE") .. renderLabel .. " MODE",
    color = col, fontSize = 11, align = "left", valign = "top",
  }

  local centerY = h / 2
  local maxAmp = (h / 2) * 0.85
  local pointCap = math.max(48, tonumber(state.maxPoints) or 200)
  if tonumber(state.renderMode or 0) == 1 then
    pointCap = math.min(pointCap, 96)
  end
  local numPoints = math.max(48, math.min(w, pointCap))
  local staticCol = (0x40 << 24) | (col & 0x00ffffff)

  local prevX, prevY
  for i = 0, numPoints do
    local t = i / numPoints
    local sample = renderWaveSample(state, waveType, t)
    sample = M.applyDriveShape(sample, drive, driveShape, driveBias, driveMix)
    local x = math.floor(t * w)
    local y = math.floor(centerY - sample * maxAmp)
    if prevX then
      display[#display + 1] = {
        cmd = "drawLine", x1 = prevX, y1 = prevY, x2 = x, y2 = y,
        thickness = 1, color = staticCol,
      }
    end
    prevX, prevY = x, y
  end

  if #voices > 0 then
    local drawFill = (#voices <= 1)
    for vi, voice in ipairs(voices) do
      local amp = tonumber(voice.amp) or 0.0
      if amp < 0.001 then goto continue end

      local freq = tonumber(voice.freq) or 220.0
      local vcol = VOICE_COLORS[((vi - 1) % #VOICE_COLORS) + 1]
      local vcolDim = (0x20 << 24) | (vcol & 0x00ffffff)
      local cyclesInView = 2.0
      local phaseOffset = time * freq
      local vPrevX, vPrevY

      for i = 0, numPoints do
        local t = i / numPoints
        local phase = phaseOffset + t * cyclesInView
        local sample = renderWaveSample(state, waveType, phase)
        sample = M.applyDriveShape(sample, drive, driveShape, driveBias, driveMix)
        sample = sample * (amp / 0.5)
        local x = math.floor(t * w)
        local y = math.floor(centerY - sample * maxAmp)

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

function M.refreshDriveCurve(curveWidget, state)
  if not (curveWidget and curveWidget.node) then
    return nil
  end

  local drive = clamp(state.driveAmount or 0.0, 0.0, 20.0)
  local driveShape = state.driveShape or 0
  local driveBias = state.driveBias or 0.0
  local driveMix = state.driveMix or 1.0
  local probeX = 0.6
  local probeY = M.applyDriveShape(probeX, drive, driveShape, driveBias, driveMix)
  local pointY = 1.0 - ((probeY + 1.0) * 0.5)
  local curveKey = string.format("%d:%.4f:%.4f:%.4f", tonumber(driveShape) or 0, drive, driveBias, driveMix)

  if state._lastDriveCurveValue ~= curveKey then
    if curveWidget.setCurveSampler then
      curveWidget:setCurveSampler(function(x)
        return M.applyDriveShape(x, drive, driveShape, driveBias, driveMix)
      end)
    end
    if curveWidget.setControlPoints then
      curveWidget:setControlPoints({
        { x = (probeX + 1.0) * 0.5, y = pointY, mirrored = true },
      })
    end
    state._lastDriveCurveValue = curveKey
  else
    if curveWidget.refreshRetained then
      curveWidget:refreshRetained()
    end
    if curveWidget.node.repaint then
      curveWidget.node:repaint()
    end
  end

  return curveKey
end

return M

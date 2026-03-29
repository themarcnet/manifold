-- Utils Module
-- Simple math utilities used across DSP modules

local M = {}

function M.clamp(value, lo, hi)
  local n = tonumber(value) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.clamp01(value)
  return M.clamp(value, 0.0, 1.0)
end

function M.roundIndex(value, maxIndex)
  return math.max(0, math.min(maxIndex, math.floor((tonumber(value) or 0) + 0.5)))
end

function M.lerp(lo, hi, t)
  return lo + (hi - lo) * M.clamp01(t)
end

function M.expLerp(lo, hi, t)
  local frac = M.clamp01(t)
  if lo <= 0 or hi <= 0 then
    return M.lerp(lo, hi, frac)
  end
  return lo * ((hi / lo) ^ frac)
end

return M

-- test_pitch_detector.lua
-- Pitch detector test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local detector = ctx.primitives.PitchDetectorNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(220)
  osc:setAmplitude(0.35)

  detector:setMinFreq(60)
  detector:setMaxFreq(1200)
  detector:setSensitivity(0.02)
  detector:setSmoothing(0.85)

  gain:setGain(0.22)

  ctx.graph.connect(osc, detector)
  ctx.graph.connect(detector, gain)

  ctx.params.register("/test/pitchdet/min", { type = "f", min = 20, max = 2000, default = 60 })
  ctx.params.bind("/test/pitchdet/min", detector, "setMinFreq")

  ctx.params.register("/test/pitchdet/max", { type = "f", min = 40, max = 8000, default = 1200 })
  ctx.params.bind("/test/pitchdet/max", detector, "setMaxFreq")

  ctx.params.register("/test/pitchdet/sensitivity", { type = "f", min = 0.001, max = 1.0, default = 0.02 })
  ctx.params.bind("/test/pitchdet/sensitivity", detector, "setSensitivity")

  ctx.params.register("/test/pitchdet/smoothing", { type = "f", min = 0, max = 1, default = 0.85 })
  ctx.params.bind("/test/pitchdet/smoothing", detector, "setSmoothing")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.22 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Pitch detector test",
    params = {
      "/test/pitchdet/min",
      "/test/pitchdet/max",
      "/test/pitchdet/sensitivity",
      "/test/pitchdet/smoothing",
      "/test/output/gain"
    }
  }
end

return buildPlugin

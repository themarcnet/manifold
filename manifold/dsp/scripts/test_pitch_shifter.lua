-- test_pitch_shifter.lua
-- Pitch shifter validation

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local shifter = ctx.primitives.PitchShifterNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.35)

  shifter:setPitch(7)
  shifter:setWindow(80)
  shifter:setFeedback(0.15)
  shifter:setMix(1.0)

  gain:setGain(0.25)

  ctx.graph.connect(osc, shifter)
  ctx.graph.connect(shifter, gain)

  ctx.params.register("/test/pitchshift/pitch", { type = "f", min = -24, max = 24, default = 7 })
  ctx.params.bind("/test/pitchshift/pitch", shifter, "setPitch")

  ctx.params.register("/test/pitchshift/window", { type = "f", min = 20, max = 200, default = 80 })
  ctx.params.bind("/test/pitchshift/window", shifter, "setWindow")

  ctx.params.register("/test/pitchshift/feedback", { type = "f", min = 0, max = 0.95, default = 0.15 })
  ctx.params.bind("/test/pitchshift/feedback", shifter, "setFeedback")

  ctx.params.register("/test/pitchshift/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/pitchshift/mix", shifter, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Pitch shifter test",
    params = {
      "/test/pitchshift/pitch",
      "/test/pitchshift/window",
      "/test/pitchshift/feedback",
      "/test/pitchshift/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

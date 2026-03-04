-- test_reverse_delay.lua
-- Reverse delay test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local rev = ctx.primitives.ReverseDelayNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(165)
  osc:setAmplitude(0.35)

  rev:setTime(420)
  rev:setWindow(120)
  rev:setFeedback(0.45)
  rev:setMix(0.65)

  gain:setGain(0.2)

  ctx.graph.connect(osc, rev)
  ctx.graph.connect(rev, gain)

  ctx.params.register("/test/reverse/time", { type = "f", min = 50, max = 2000, default = 420 })
  ctx.params.bind("/test/reverse/time", rev, "setTime")

  ctx.params.register("/test/reverse/window", { type = "f", min = 20, max = 400, default = 120 })
  ctx.params.bind("/test/reverse/window", rev, "setWindow")

  ctx.params.register("/test/reverse/feedback", { type = "f", min = 0, max = 0.95, default = 0.45 })
  ctx.params.bind("/test/reverse/feedback", rev, "setFeedback")

  ctx.params.register("/test/reverse/mix", { type = "f", min = 0, max = 1, default = 0.65 })
  ctx.params.bind("/test/reverse/mix", rev, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Reverse delay test",
    params = {
      "/test/reverse/time",
      "/test/reverse/window",
      "/test/reverse/feedback",
      "/test/reverse/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

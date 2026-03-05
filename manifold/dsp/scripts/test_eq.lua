-- test_eq.lua
-- EQ test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local eq = ctx.primitives.EQNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.35)

  eq:setLowGain(6)
  eq:setLowFreq(120)
  eq:setMidGain(-4)
  eq:setMidFreq(900)
  eq:setMidQ(0.8)
  eq:setHighGain(4)
  eq:setHighFreq(8000)
  eq:setOutput(0)
  eq:setMix(1.0)

  gain:setGain(0.22)

  ctx.graph.connect(osc, eq)
  ctx.graph.connect(eq, gain)

  ctx.params.register("/test/eq/low_gain", { type = "f", min = -24, max = 24, default = 6 })
  ctx.params.bind("/test/eq/low_gain", eq, "setLowGain")
  ctx.params.register("/test/eq/low_freq", { type = "f", min = 20, max = 400, default = 120 })
  ctx.params.bind("/test/eq/low_freq", eq, "setLowFreq")

  ctx.params.register("/test/eq/mid_gain", { type = "f", min = -24, max = 24, default = -4 })
  ctx.params.bind("/test/eq/mid_gain", eq, "setMidGain")
  ctx.params.register("/test/eq/mid_freq", { type = "f", min = 120, max = 8000, default = 900 })
  ctx.params.bind("/test/eq/mid_freq", eq, "setMidFreq")
  ctx.params.register("/test/eq/mid_q", { type = "f", min = 0.2, max = 12.0, default = 0.8 })
  ctx.params.bind("/test/eq/mid_q", eq, "setMidQ")

  ctx.params.register("/test/eq/high_gain", { type = "f", min = -24, max = 24, default = 4 })
  ctx.params.bind("/test/eq/high_gain", eq, "setHighGain")
  ctx.params.register("/test/eq/high_freq", { type = "f", min = 2000, max = 16000, default = 8000 })
  ctx.params.bind("/test/eq/high_freq", eq, "setHighFreq")

  ctx.params.register("/test/eq/output", { type = "f", min = -24, max = 24, default = 0 })
  ctx.params.bind("/test/eq/output", eq, "setOutput")

  ctx.params.register("/test/eq/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/eq/mix", eq, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.22 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "EQ test",
    params = {
      "/test/eq/low_gain", "/test/eq/low_freq",
      "/test/eq/mid_gain", "/test/eq/mid_freq", "/test/eq/mid_q",
      "/test/eq/high_gain", "/test/eq/high_freq",
      "/test/eq/output",
      "/test/eq/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

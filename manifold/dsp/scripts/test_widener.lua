-- test_widener.lua
-- Stereo widener utility test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local widener = ctx.primitives.StereoWidenerNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.45)

  widener:setWidth(1.25)
  widener:setMonoLowFreq(140)
  widener:setMonoLowEnable(true)

  ctx.graph.connect(osc, widener)
  ctx.graph.connect(widener, gain)

  ctx.params.register("/test/widener/width", {
    type = "f", min = 0.0, max = 2.0, default = 1.25,
    description = "Stereo width 0-200%"
  })
  ctx.params.bind("/test/widener/width", widener, "setWidth")

  ctx.params.register("/test/widener/monolowfreq", {
    type = "f", min = 20.0, max = 500.0, default = 140.0,
    description = "Mono low crossover frequency"
  })
  ctx.params.bind("/test/widener/monolowfreq", widener, "setMonoLowFreq")

  ctx.params.register("/test/widener/monolowenable", {
    type = "f", min = 0.0, max = 1.0, default = 1.0,
    description = "Force lows to mono"
  })
  ctx.params.bind("/test/widener/monolowenable", widener, "setMonoLowEnable")

  ctx.params.register("/test/output/gain", {
    type = "f", min = 0.0, max = 1.0, default = 0.22,
    description = "Master output gain"
  })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Stereo widener test",
    params = {
      "/test/widener/width",
      "/test/widener/monolowfreq",
      "/test/widener/monolowenable",
      "/test/output/gain"
    }
  }
end

return buildPlugin

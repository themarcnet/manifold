-- test_shimmer.lua
-- Shimmer reverb style test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local shimmer = ctx.primitives.ShimmerNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(165)
  osc:setAmplitude(0.35)

  shimmer:setSize(0.65)
  shimmer:setPitch(12)
  shimmer:setFeedback(0.7)
  shimmer:setMix(0.5)
  shimmer:setModulation(0.25)
  shimmer:setFilter(5500)

  ctx.graph.connect(osc, shimmer)
  ctx.graph.connect(shimmer, gain)

  ctx.params.register("/test/shimmer/size", { type = "f", min = 0, max = 1, default = 0.65 })
  ctx.params.bind("/test/shimmer/size", shimmer, "setSize")

  ctx.params.register("/test/shimmer/pitch", { type = "f", min = -12, max = 12, default = 12 })
  ctx.params.bind("/test/shimmer/pitch", shimmer, "setPitch")

  ctx.params.register("/test/shimmer/feedback", { type = "f", min = 0, max = 0.99, default = 0.7 })
  ctx.params.bind("/test/shimmer/feedback", shimmer, "setFeedback")

  ctx.params.register("/test/shimmer/mix", { type = "f", min = 0, max = 1, default = 0.5 })
  ctx.params.bind("/test/shimmer/mix", shimmer, "setMix")

  ctx.params.register("/test/shimmer/mod", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/shimmer/mod", shimmer, "setModulation")

  ctx.params.register("/test/shimmer/filter", { type = "f", min = 100, max = 12000, default = 5500 })
  ctx.params.bind("/test/shimmer/filter", shimmer, "setFilter")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Shimmer test",
    params = {
      "/test/shimmer/size",
      "/test/shimmer/pitch",
      "/test/shimmer/feedback",
      "/test/shimmer/mix",
      "/test/shimmer/mod",
      "/test/shimmer/filter",
      "/test/output/gain"
    }
  }
end

return buildPlugin

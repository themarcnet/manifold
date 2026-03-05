-- test_limiter.lua
-- Limiter test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local pre = ctx.primitives.GainNode.new(2)
  local lim = ctx.primitives.LimiterNode.new()
  local out = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.6)

  pre:setGain(1.6)

  lim:setThreshold(-6)
  lim:setRelease(80)
  lim:setMakeup(0)
  lim:setSoftClip(0.4)
  lim:setMix(1.0)

  out:setGain(0.25)

  ctx.graph.connect(osc, pre)
  ctx.graph.connect(pre, lim)
  ctx.graph.connect(lim, out)

  ctx.params.register("/test/lim/threshold", { type = "f", min = -24, max = 0, default = -6 })
  ctx.params.bind("/test/lim/threshold", lim, "setThreshold")

  ctx.params.register("/test/lim/release", { type = "f", min = 1, max = 500, default = 80 })
  ctx.params.bind("/test/lim/release", lim, "setRelease")

  ctx.params.register("/test/lim/makeup", { type = "f", min = 0, max = 18, default = 0 })
  ctx.params.bind("/test/lim/makeup", lim, "setMakeup")

  ctx.params.register("/test/lim/soft", { type = "f", min = 0, max = 1, default = 0.4 })
  ctx.params.bind("/test/lim/soft", lim, "setSoftClip")

  ctx.params.register("/test/lim/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/lim/mix", lim, "setMix")

  ctx.params.register("/test/pre/gain", { type = "f", min = 0, max = 2, default = 1.6 })
  ctx.params.bind("/test/pre/gain", pre, "setGain")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/output/gain", out, "setGain")

  return {
    description = "Limiter test",
    params = {
      "/test/lim/threshold",
      "/test/lim/release",
      "/test/lim/makeup",
      "/test/lim/soft",
      "/test/lim/mix",
      "/test/pre/gain",
      "/test/output/gain"
    }
  }
end

return buildPlugin

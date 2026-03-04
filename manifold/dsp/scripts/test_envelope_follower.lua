-- test_envelope_follower.lua
-- Envelope follower test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local env = ctx.primitives.EnvelopeFollowerNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.45)

  env:setAttack(8)
  env:setRelease(180)
  env:setSensitivity(1.2)
  env:setHighpass(90)

  gain:setGain(0.25)

  ctx.graph.connect(osc, env)
  ctx.graph.connect(env, gain)

  ctx.params.register("/test/env/attack", { type = "f", min = 0.1, max = 200, default = 8 })
  ctx.params.bind("/test/env/attack", env, "setAttack")

  ctx.params.register("/test/env/release", { type = "f", min = 1, max = 2000, default = 180 })
  ctx.params.bind("/test/env/release", env, "setRelease")

  ctx.params.register("/test/env/sensitivity", { type = "f", min = 0.1, max = 8, default = 1.2 })
  ctx.params.bind("/test/env/sensitivity", env, "setSensitivity")

  ctx.params.register("/test/env/highpass", { type = "f", min = 20, max = 2000, default = 90 })
  ctx.params.bind("/test/env/highpass", env, "setHighpass")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Envelope follower test",
    params = {
      "/test/env/attack",
      "/test/env/release",
      "/test/env/sensitivity",
      "/test/env/highpass",
      "/test/output/gain"
    }
  }
end

return buildPlugin

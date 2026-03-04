-- test_stutter.lua
-- Stutter repeat/pattern test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local st = ctx.primitives.StutterNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(220)
  osc:setAmplitude(0.35)

  st:setLength(0.5)       -- half beat
  st:setGate(0.8)
  st:setFilterDecay(0.25)
  st:setPitchDecay(0.2)
  st:setProbability(0.8)
  st:setPattern(255)      -- 8-step all on
  st:setTempo(120)
  st:setMix(1.0)

  ctx.graph.connect(osc, st)
  ctx.graph.connect(st, gain)

  ctx.params.register("/test/stutter/length", { type = "f", min = 0.125, max = 8.0, default = 0.5 })
  ctx.params.bind("/test/stutter/length", st, "setLength")

  ctx.params.register("/test/stutter/gate", { type = "f", min = 0, max = 1, default = 0.8 })
  ctx.params.bind("/test/stutter/gate", st, "setGate")

  ctx.params.register("/test/stutter/filterdecay", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/stutter/filterdecay", st, "setFilterDecay")

  ctx.params.register("/test/stutter/pitchdecay", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/stutter/pitchdecay", st, "setPitchDecay")

  ctx.params.register("/test/stutter/probability", { type = "f", min = 0, max = 1, default = 0.8 })
  ctx.params.bind("/test/stutter/probability", st, "setProbability")

  ctx.params.register("/test/stutter/pattern", { type = "f", min = 0, max = 255, default = 255 })
  ctx.params.bind("/test/stutter/pattern", st, "setPattern")

  ctx.params.register("/test/stutter/tempo", { type = "f", min = 20, max = 300, default = 120 })
  ctx.params.bind("/test/stutter/tempo", st, "setTempo")

  ctx.params.register("/test/stutter/mix", { type = "f", min = 0, max = 1, default = 1 })
  ctx.params.bind("/test/stutter/mix", st, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Stutter test",
    params = {
      "/test/stutter/length",
      "/test/stutter/gate",
      "/test/stutter/filterdecay",
      "/test/stutter/pitchdecay",
      "/test/stutter/probability",
      "/test/stutter/pattern",
      "/test/stutter/tempo",
      "/test/stutter/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

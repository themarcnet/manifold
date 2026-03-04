-- test_ringmod.lua
-- Ring modulator test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local ring = ctx.primitives.RingModulatorNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(220)
  osc:setAmplitude(0.4)

  ring:setFrequency(120)
  ring:setDepth(1.0)
  ring:setMix(1.0)
  ring:setSpread(30)

  gain:setGain(0.2)

  ctx.graph.connect(osc, ring)
  ctx.graph.connect(ring, gain)

  ctx.params.register("/test/ringmod/freq", { type = "f", min = 0.1, max = 2000, default = 120 })
  ctx.params.bind("/test/ringmod/freq", ring, "setFrequency")

  ctx.params.register("/test/ringmod/depth", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/ringmod/depth", ring, "setDepth")

  ctx.params.register("/test/ringmod/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/ringmod/mix", ring, "setMix")

  ctx.params.register("/test/ringmod/spread", { type = "f", min = 0, max = 180, default = 30 })
  ctx.params.bind("/test/ringmod/spread", ring, "setSpread")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Ring modulator test",
    params = {
      "/test/ringmod/freq",
      "/test/ringmod/depth",
      "/test/ringmod/mix",
      "/test/ringmod/spread",
      "/test/output/gain"
    }
  }
end

return buildPlugin

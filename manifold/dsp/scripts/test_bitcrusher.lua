-- test_bitcrusher.lua
-- Bit crusher test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local crush = ctx.primitives.BitCrusherNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(3)
  osc:setFrequency(140)
  osc:setAmplitude(0.4)

  crush:setBits(6)
  crush:setRateReduction(8)
  crush:setMix(1.0)
  crush:setOutput(0.8)

  gain:setGain(0.22)

  ctx.graph.connect(osc, crush)
  ctx.graph.connect(crush, gain)

  ctx.params.register("/test/bitcrusher/bits", { type = "f", min = 2, max = 16, default = 6 })
  ctx.params.bind("/test/bitcrusher/bits", crush, "setBits")

  ctx.params.register("/test/bitcrusher/rate", { type = "f", min = 1, max = 64, default = 8 })
  ctx.params.bind("/test/bitcrusher/rate", crush, "setRateReduction")

  ctx.params.register("/test/bitcrusher/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/bitcrusher/mix", crush, "setMix")

  ctx.params.register("/test/bitcrusher/output", { type = "f", min = 0, max = 2, default = 0.8 })
  ctx.params.bind("/test/bitcrusher/output", crush, "setOutput")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.22 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Bit crusher test",
    params = {
      "/test/bitcrusher/bits",
      "/test/bitcrusher/rate",
      "/test/bitcrusher/mix",
      "/test/bitcrusher/output",
      "/test/output/gain"
    }
  }
end

return buildPlugin

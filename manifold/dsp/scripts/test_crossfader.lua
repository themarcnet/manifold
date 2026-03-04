-- test_crossfader.lua
-- Crossfader test (2 busses)

function buildPlugin(ctx)
  local oscA = ctx.primitives.OscillatorNode.new()
  local oscB = ctx.primitives.OscillatorNode.new()
  local cross = ctx.primitives.CrossfaderNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  oscA:setWaveform(2)
  oscA:setFrequency(110)
  oscA:setAmplitude(0.35)

  oscB:setWaveform(2)
  oscB:setFrequency(220)
  oscB:setAmplitude(0.35)

  cross:setPosition(0.0)
  cross:setCurve(1.0)
  cross:setMix(1.0)

  gain:setGain(0.2)

  -- Bus A -> toInput 0, Bus B -> toInput 1
  ctx.graph.connect(oscA, cross, 0, 0)
  ctx.graph.connect(oscB, cross, 0, 1)
  ctx.graph.connect(cross, gain)

  ctx.params.register("/test/cross/pos", { type = "f", min = -1, max = 1, default = 0.0 })
  ctx.params.bind("/test/cross/pos", cross, "setPosition")

  ctx.params.register("/test/cross/curve", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/cross/curve", cross, "setCurve")

  ctx.params.register("/test/cross/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/cross/mix", cross, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Crossfader test",
    params = {
      "/test/cross/pos",
      "/test/cross/curve",
      "/test/cross/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

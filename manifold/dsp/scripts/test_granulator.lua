-- test_granulator.lua
-- Granulator freeze/spray test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local gran = ctx.primitives.GranulatorNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(110)
  osc:setAmplitude(0.4)

  gran:setGrainSize(90)
  gran:setDensity(24)
  gran:setPosition(0.6)
  gran:setPitch(0)
  gran:setSpray(0.25)
  gran:setFreeze(false)
  gran:setEnvelope(0)
  gran:setMix(1.0)

  ctx.graph.connect(osc, gran)
  ctx.graph.connect(gran, gain)

  ctx.params.register("/test/gran/grainsize", { type = "f", min = 1, max = 500, default = 90 })
  ctx.params.bind("/test/gran/grainsize", gran, "setGrainSize")

  ctx.params.register("/test/gran/density", { type = "f", min = 1, max = 100, default = 24 })
  ctx.params.bind("/test/gran/density", gran, "setDensity")

  ctx.params.register("/test/gran/position", { type = "f", min = 0, max = 1, default = 0.6 })
  ctx.params.bind("/test/gran/position", gran, "setPosition")

  ctx.params.register("/test/gran/pitch", { type = "f", min = -24, max = 24, default = 0 })
  ctx.params.bind("/test/gran/pitch", gran, "setPitch")

  ctx.params.register("/test/gran/spray", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.bind("/test/gran/spray", gran, "setSpray")

  ctx.params.register("/test/gran/freeze", { type = "f", min = 0, max = 1, default = 0 })
  ctx.params.bind("/test/gran/freeze", gran, "setFreeze")

  ctx.params.register("/test/gran/envelope", { type = "f", min = 0, max = 1, default = 0 })
  ctx.params.bind("/test/gran/envelope", gran, "setEnvelope")

  ctx.params.register("/test/gran/mix", { type = "f", min = 0, max = 1, default = 1 })
  ctx.params.bind("/test/gran/mix", gran, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.22 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Granulator test",
    params = {
      "/test/gran/grainsize",
      "/test/gran/density",
      "/test/gran/position",
      "/test/gran/pitch",
      "/test/gran/spray",
      "/test/gran/freeze",
      "/test/gran/envelope",
      "/test/gran/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

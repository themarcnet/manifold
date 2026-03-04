-- test_phaser.lua
-- Phaser sweep texture test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local phaser = ctx.primitives.PhaserNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(220)
  osc:setAmplitude(0.4)

  phaser:setRate(0.35)
  phaser:setDepth(0.8)
  phaser:setStages(6)
  phaser:setFeedback(0.25)
  phaser:setSpread(120)

  ctx.graph.connect(osc, phaser)
  ctx.graph.connect(phaser, gain)

  ctx.params.register("/test/phaser/rate", {
    type = "f", min = 0.1, max = 10.0, default = 0.35,
    description = "LFO rate"
  })
  ctx.params.bind("/test/phaser/rate", phaser, "setRate")

  ctx.params.register("/test/phaser/depth", {
    type = "f", min = 0.0, max = 1.0, default = 0.8,
    description = "Sweep depth"
  })
  ctx.params.bind("/test/phaser/depth", phaser, "setDepth")

  ctx.params.register("/test/phaser/stages", {
    type = "f", min = 6.0, max = 12.0, default = 6.0,
    description = "Phaser stages (6 or 12)"
  })
  ctx.params.bind("/test/phaser/stages", phaser, "setStages")

  ctx.params.register("/test/phaser/feedback", {
    type = "f", min = -0.9, max = 0.9, default = 0.25,
    description = "Feedback amount"
  })
  ctx.params.bind("/test/phaser/feedback", phaser, "setFeedback")

  ctx.params.register("/test/phaser/spread", {
    type = "f", min = 0.0, max = 180.0, default = 120.0,
    description = "Stereo phase offset in degrees"
  })
  ctx.params.bind("/test/phaser/spread", phaser, "setSpread")

  ctx.params.register("/test/output/gain", {
    type = "f", min = 0.0, max = 1.0, default = 0.24,
    description = "Master output gain"
  })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Phaser test",
    params = {
      "/test/phaser/rate",
      "/test/phaser/depth",
      "/test/phaser/stages",
      "/test/phaser/feedback",
      "/test/phaser/spread",
      "/test/output/gain"
    }
  }
end

return buildPlugin

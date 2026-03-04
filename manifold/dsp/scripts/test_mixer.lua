-- test_mixer.lua
-- Mixer test (4 busses)

function buildPlugin(ctx)
  local o1 = ctx.primitives.OscillatorNode.new()
  local o2 = ctx.primitives.OscillatorNode.new()
  local o3 = ctx.primitives.OscillatorNode.new()
  local o4 = ctx.primitives.OscillatorNode.new()

  local mix = ctx.primitives.MixerNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  o1:setWaveform(2)
  o1:setFrequency(110)
  o1:setAmplitude(0.18)

  o2:setWaveform(2)
  o2:setFrequency(165)
  o2:setAmplitude(0.18)

  o3:setWaveform(2)
  o3:setFrequency(220)
  o3:setAmplitude(0.18)

  o4:setWaveform(2)
  o4:setFrequency(330)
  o4:setAmplitude(0.18)

  mix:setGain1(1.0)
  mix:setGain2(1.0)
  mix:setGain3(1.0)
  mix:setGain4(1.0)
  mix:setPan1(-0.7)
  mix:setPan2(-0.2)
  mix:setPan3(0.2)
  mix:setPan4(0.7)
  mix:setMaster(1.0)

  gain:setGain(0.3)

  -- bus indices map to toInput 0..3
  ctx.graph.connect(o1, mix, 0, 0)
  ctx.graph.connect(o2, mix, 0, 1)
  ctx.graph.connect(o3, mix, 0, 2)
  ctx.graph.connect(o4, mix, 0, 3)
  ctx.graph.connect(mix, gain)

  ctx.params.register("/test/mix/g1", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/mix/g1", mix, "setGain1")
  ctx.params.register("/test/mix/g2", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/mix/g2", mix, "setGain2")
  ctx.params.register("/test/mix/g3", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/mix/g3", mix, "setGain3")
  ctx.params.register("/test/mix/g4", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/mix/g4", mix, "setGain4")

  ctx.params.register("/test/mix/p1", { type = "f", min = -1, max = 1, default = -0.7 })
  ctx.params.bind("/test/mix/p1", mix, "setPan1")
  ctx.params.register("/test/mix/p2", { type = "f", min = -1, max = 1, default = -0.2 })
  ctx.params.bind("/test/mix/p2", mix, "setPan2")
  ctx.params.register("/test/mix/p3", { type = "f", min = -1, max = 1, default = 0.2 })
  ctx.params.bind("/test/mix/p3", mix, "setPan3")
  ctx.params.register("/test/mix/p4", { type = "f", min = -1, max = 1, default = 0.7 })
  ctx.params.bind("/test/mix/p4", mix, "setPan4")

  ctx.params.register("/test/mix/master", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/mix/master", mix, "setMaster")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.3 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Mixer test",
    params = {
      "/test/mix/g1", "/test/mix/g2", "/test/mix/g3", "/test/mix/g4",
      "/test/mix/p1", "/test/mix/p2", "/test/mix/p3", "/test/mix/p4",
      "/test/mix/master",
      "/test/output/gain"
    }
  }
end

return buildPlugin

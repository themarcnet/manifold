-- test_multitap.lua
-- Multitap delay test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local delay = ctx.primitives.MultitapDelayNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(220)
  osc:setAmplitude(0.35)

  delay:setTapCount(4)
  delay:setTapTime(1, 180)
  delay:setTapTime(2, 320)
  delay:setTapTime(3, 470)
  delay:setTapTime(4, 620)
  delay:setTapGain(1, 0.5)
  delay:setTapGain(2, 0.35)
  delay:setTapGain(3, 0.28)
  delay:setTapGain(4, 0.2)
  delay:setTapPan(1, -0.8)
  delay:setTapPan(2, -0.25)
  delay:setTapPan(3, 0.25)
  delay:setTapPan(4, 0.8)
  delay:setFeedback(0.3)
  delay:setMix(0.55)

  ctx.graph.connect(osc, delay)
  ctx.graph.connect(delay, gain)

  ctx.params.register("/test/multitap/tapcount", { type = "f", min = 1, max = 8, default = 4 })
  ctx.params.bind("/test/multitap/tapcount", delay, "setTapCount")

  ctx.params.register("/test/multitap/feedback", { type = "f", min = 0, max = 0.95, default = 0.3 })
  ctx.params.bind("/test/multitap/feedback", delay, "setFeedback")

  ctx.params.register("/test/multitap/mix", { type = "f", min = 0, max = 1, default = 0.55 })
  ctx.params.bind("/test/multitap/mix", delay, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.2 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Multitap delay test",
    params = {
      "/test/multitap/tapcount",
      "/test/multitap/feedback",
      "/test/multitap/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

-- test_transient_shaper.lua
-- Transient shaper validation

function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  local shaper = ctx.primitives.TransientShaperNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  shaper:setAttack(0.6)
  shaper:setSustain(-0.3)
  shaper:setSensitivity(1.2)
  shaper:setMix(1.0)

  gain:setGain(1.0)

  ctx.graph.connect(input, shaper)
  ctx.graph.connect(shaper, gain)

  ctx.params.register("/test/transient/attack", { type = "f", min = -1, max = 1, default = 0.6 })
  ctx.params.bind("/test/transient/attack", shaper, "setAttack")

  ctx.params.register("/test/transient/sustain", { type = "f", min = -1, max = 1, default = -0.3 })
  ctx.params.bind("/test/transient/sustain", shaper, "setSustain")

  ctx.params.register("/test/transient/sensitivity", { type = "f", min = 0.1, max = 4, default = 1.2 })
  ctx.params.bind("/test/transient/sensitivity", shaper, "setSensitivity")

  ctx.params.register("/test/transient/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/transient/mix", shaper, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 2, default = 1.0 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Transient shaper test",
    params = {
      "/test/transient/attack",
      "/test/transient/sustain",
      "/test/transient/sensitivity",
      "/test/transient/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

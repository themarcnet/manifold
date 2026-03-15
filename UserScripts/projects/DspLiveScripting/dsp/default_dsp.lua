function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  local gain = ctx.primitives.GainNode.new(2)
  local width = ctx.primitives.StereoWidenerNode.new(2)
  local output = ctx.primitives.PassthroughNode.new(2)

  ctx.graph.connect(input, gain)
  ctx.graph.connect(gain, width)
  ctx.graph.connect(width, output)

  ctx.graph.markInput(input)
  ctx.graph.markInput(gain)
  ctx.graph.markInput(width)
  ctx.graph.markMonitor(output)

  ctx.params.register("/dsp/live/input_gain", { type = "f", min = 0.0, max = 2.0, default = 1.0 })
  ctx.params.register("/dsp/live/width", { type = "f", min = 0.0, max = 1.0, default = 0.25 })

  ctx.params.bind("/dsp/live/input_gain", gain, "setGain")
  ctx.params.bind("/dsp/live/width", width, "setWidth")

  return {
    input = input,
    output = output,
  }
end

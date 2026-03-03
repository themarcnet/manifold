-- Input Filter
-- DSP script: Simple input filter

function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  local filt = ctx.primitives.FilterNode.new()

  ctx.graph.connect(input, filt)

  ctx.params.register("/dsp/filter/cutoff", { type="f", min=80, max=8000, default=900 })
  ctx.params.register("/dsp/filter/mix", { type="f", min=0, max=1, default=1.0 })

  ctx.params.bind("/dsp/filter/cutoff", filt, "setCutoff")
  ctx.params.bind("/dsp/filter/mix", filt, "setMix")

  return {}
end

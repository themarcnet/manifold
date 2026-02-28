-- Tone + Input Chain
-- DSP script: Oscillator + Filter + Distortion with input passthrough

function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  local osc = ctx.primitives.OscillatorNode.new()
  local filt = ctx.primitives.FilterNode.new()
  local dist = ctx.primitives.DistortionNode.new()

  ctx.graph.connect(input, filt)
  ctx.graph.connect(osc, filt)
  ctx.graph.connect(filt, dist)

  ctx.params.register("/dsp/osc/freq", { type="f", min=40, max=2000, default=220 })
  ctx.params.register("/dsp/osc/amp", { type="f", min=0, max=1, default=0.2 })
  ctx.params.register("/dsp/filter/cutoff", { type="f", min=80, max=8000, default=1200 })
  ctx.params.register("/dsp/filter/mix", { type="f", min=0, max=1, default=1.0 })
  ctx.params.register("/dsp/dist/drive", { type="f", min=1, max=20, default=4 })
  ctx.params.register("/dsp/dist/mix", { type="f", min=0, max=1, default=0.5 })

  ctx.params.bind("/dsp/osc/freq", osc, "setFrequency")
  ctx.params.bind("/dsp/osc/amp", osc, "setAmplitude")
  ctx.params.bind("/dsp/filter/cutoff", filt, "setCutoff")
  ctx.params.bind("/dsp/filter/mix", filt, "setMix")
  ctx.params.bind("/dsp/dist/drive", dist, "setDrive")
  ctx.params.bind("/dsp/dist/mix", dist, "setMix")

  return {}
end

-- Input + Reverb + Tone
-- DSP script: Input + Oscillator through Reverb

function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  local osc = ctx.primitives.OscillatorNode.new()
  local rev = ctx.primitives.ReverbNode.new()

  ctx.graph.connect(input, rev)
  ctx.graph.connect(osc, rev)

  ctx.params.register("/dsp/osc/freq", { type="f", min=40, max=2000, default=110 })
  ctx.params.register("/dsp/osc/amp", { type="f", min=0, max=1, default=0.16 })
  ctx.params.register("/dsp/reverb/wet", { type="f", min=0, max=1, default=0.55 })

  ctx.params.bind("/dsp/osc/freq", osc, "setFrequency")
  ctx.params.bind("/dsp/osc/amp", osc, "setAmplitude")
  ctx.params.bind("/dsp/reverb/wet", rev, "setWetLevel")

  return {}
end

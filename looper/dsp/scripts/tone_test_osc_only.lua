-- Tone Test (Osc Only)
-- DSP script: Simple oscillator for testing

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()

  ctx.params.register("/dsp/osc/freq", { type="f", min=40, max=2000, default=220 })
  ctx.params.register("/dsp/osc/amp", { type="f", min=0, max=1, default=0.4 })

  ctx.params.bind("/dsp/osc/freq", osc, "setFrequency")
  ctx.params.bind("/dsp/osc/amp", osc, "setAmplitude")

  return {}
end

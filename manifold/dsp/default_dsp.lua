function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local filt = ctx.primitives.FilterNode.new()
  local dist = ctx.primitives.DistortionNode.new()
  -- local function shape(node)
  --   node:setWaveform(3) -- 0=sine, 1=saw, 2=square, 3=triangle, 4=blend
  -- end
  -- shape(osc)

  ctx.graph.connect(osc, filt)
  ctx.graph.connect(osc, filt, 0, 1)
  ctx.graph.connect(filt, dist)
  ctx.graph.connect(filt, dist, 1, 1)

  ctx.params.register("/dsp/osc/freq", {
    type = "f",
    min = 40.0,
    max = 2000.0,
    default = 220.0,
    description = "Oscillator frequency",
  })

  ctx.params.register("/dsp/osc/amp", {
    type = "f",
    min = 0.0,
    max = 0.8,
    default = 0.25,
    description = "Oscillator amplitude",
  })

  ctx.params.register("/dsp/filter/cutoff", {
    type = "f",
    min = 80.0,
    max = 12000.0,
    default = 1200.0,
    description = "Filter cutoff",
  })

  ctx.params.register("/dsp/filter/mix", {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 1.0,
    description = "Filter wet mix",
  })

  ctx.params.register("/dsp/dist/drive", {
    type = "f",
    min = 1.0,
    max = 20.0,
    default = 4.0,
    description = "Distortion drive",
  })

  ctx.params.register("/dsp/dist/mix", {
    type = "f",
    min = 0.0,
    max = 1.0,
    default = 0.4,
    description = "Distortion mix",
  })

  ctx.params.bind("/dsp/osc/freq", osc, "setFrequency")
  ctx.params.bind("/dsp/osc/amp", osc, "setAmplitude")
  -- ctx.params.register("/dsp/osc/shape", { type="f", min=0, max=4, default=0 })
  -- ctx.params.bind("/dsp/osc/shape", osc, "setWaveform")
  ctx.params.bind("/dsp/filter/cutoff", filt, "setCutoff")
  ctx.params.bind("/dsp/filter/mix", filt, "setMix")
  ctx.params.bind("/dsp/dist/drive", dist, "setDrive")
  ctx.params.bind("/dsp/dist/mix", dist, "setMix")

  return {}
end

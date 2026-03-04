-- Test script for CompressorNode
-- Demonstrates drum transient control with adjustable parameters

function buildPlugin(ctx)
  -- Create nodes
  local osc = ctx.primitives.OscillatorNode.new()
  local comp = ctx.primitives.CompressorNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  -- Connect: oscillator -> compressor -> gain
  ctx.graph.connect(osc, comp)
  ctx.graph.connect(comp, gain)

  -- Set up oscillator for testing (drum-like pulses)
  osc:setFrequency(60)  -- Low kick-like frequency
  osc:setWaveform(2)    -- Square wave for punchy transients
  osc:setAmplitude(0.8)

  -- Set up compressor with drum-friendly defaults
  comp:setThreshold(-18.0)
  comp:setRatio(4.0)
  comp:setAttack(5.0)      -- Fast attack to catch transients
  comp:setRelease(100.0)   -- Medium release
  comp:setKnee(6.0)
  comp:setAutoMakeup(true)
  comp:setMode(0)          -- Compressor mode (0=compressor, 1=limiter)
  comp:setDetectorMode(0)  -- Peak detection (0=peak, 1=rms)
  comp:setSidechainHPF(100.0)  -- High-pass filter on sidechain
  comp:setMix(1.0)         -- Fully wet

  -- Register parameters for UI control
  ctx.params.register("/compressor/threshold", {type="f", min=-60.0, max=0.0, default=-18.0})
  ctx.params.register("/compressor/ratio", {type="f", min=1.0, max=20.0, default=4.0})
  ctx.params.register("/compressor/attack", {type="f", min=0.1, max=100.0, default=5.0})
  ctx.params.register("/compressor/release", {type="f", min=1.0, max=1000.0, default=100.0})
  ctx.params.register("/compressor/knee", {type="f", min=0.0, max=20.0, default=6.0})
  ctx.params.register("/compressor/makeup", {type="f", min=0.0, max=40.0, default=0.0})
  ctx.params.register("/compressor/auto_makeup", {type="f", min=0.0, max=1.0, default=1.0})
  ctx.params.register("/compressor/mode", {type="f", min=0.0, max=1.0, default=0.0})
  ctx.params.register("/compressor/detector", {type="f", min=0.0, max=1.0, default=0.0})
  ctx.params.register("/compressor/sidechain_hpf", {type="f", min=20.0, max=1000.0, default=100.0})
  ctx.params.register("/compressor/mix", {type="f", min=0.0, max=1.0, default=1.0})

  -- Bind parameters to compressor
  ctx.params.bind("/compressor/threshold", comp, "setThreshold")
  ctx.params.bind("/compressor/ratio", comp, "setRatio")
  ctx.params.bind("/compressor/attack", comp, "setAttack")
  ctx.params.bind("/compressor/release", comp, "setRelease")
  ctx.params.bind("/compressor/knee", comp, "setKnee")
  ctx.params.bind("/compressor/makeup", comp, "setMakeup")
  ctx.params.bind("/compressor/auto_makeup", comp, "setAutoMakeup")
  ctx.params.bind("/compressor/mode", comp, "setMode")
  ctx.params.bind("/compressor/detector", comp, "setDetectorMode")
  ctx.params.bind("/compressor/sidechain_hpf", comp, "setSidechainHPF")
  ctx.params.bind("/compressor/mix", comp, "setMix")

  return {
    description = "Compressor test - Drum transient control",
    params = {
        "/compressor/threshold",
        "/compressor/ratio", 
        "/compressor/attack",
        "/compressor/release",
        "/compressor/knee",
        "/compressor/makeup",
        "/compressor/auto_makeup",
        "/compressor/mode",
        "/compressor/detector",
        "/compressor/sidechain_hpf",
        "/compressor/mix"
    }
  }
end

return buildPlugin

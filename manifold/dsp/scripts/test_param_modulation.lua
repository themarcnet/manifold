-- test_param_modulation.lua
-- Parameter modulation demonstration
--
-- LFO modulation runs in the UI behavior update loop (like the arpeggiator).
-- The UI computes LFO values using getTime() and calls setParam() which both:
--   1. Updates the DSP node parameters
--   2. Moves the sliders visually in the runtime params panel
--
-- Modulation targets: filter cutoff, chorus rate, oscillator frequency
-- (NOT delay time - rapid delay time changes cause buffer tearing)

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local filt = ctx.primitives.SVFNode.new()
  local chorus = ctx.primitives.ChorusNode.new()
  local delay = ctx.primitives.StereoDelayNode.new()
  local output = ctx.primitives.GainNode.new(2)

  osc:setWaveform(1)  -- Saw
  osc:setFrequency(220)
  osc:setAmplitude(0.3)

  filt:setMode(0)  -- LP
  filt:setCutoff(1500)
  filt:setResonance(0.6)
  filt:setDrive(0.8)
  filt:setMix(1.0)

  chorus:setRate(0.5)
  chorus:setDepth(0.3)
  chorus:setMix(0.3)

  delay:setTempo(120)
  delay:setTimeL(375)
  delay:setTimeR(500)
  delay:setFeedback(0.4)
  delay:setMix(0.3)
  delay:setPingPong(true)

  output:setGain(0.4)

  ctx.graph.connect(osc, filt)
  ctx.graph.connect(filt, chorus)
  ctx.graph.connect(chorus, delay)
  ctx.graph.connect(delay, output)

  -- LFO 1: modulates filter cutoff
  ctx.params.register("/mod/lfo1/rate", { type = "f", min = 0.05, max = 10, default = 0.5 })
  ctx.params.register("/mod/lfo1/depth", { type = "f", min = 0, max = 1, default = 0.5 })

  -- LFO 2: modulates chorus rate
  ctx.params.register("/mod/lfo2/rate", { type = "f", min = 0.05, max = 5, default = 0.2 })
  ctx.params.register("/mod/lfo2/depth", { type = "f", min = 0, max = 1, default = 0.4 })

  -- LFO 3: modulates oscillator frequency (vibrato)
  ctx.params.register("/mod/lfo3/rate", { type = "f", min = 0.1, max = 12, default = 4 })
  ctx.params.register("/mod/lfo3/depth", { type = "f", min = 0, max = 1, default = 0.1 })

  -- Modulation targets (base values - LFOs modulate around these)
  ctx.params.register("/mod/filter/cutoff", { type = "f", min = 100, max = 8000, default = 1500 })
  ctx.params.register("/mod/filter/res", { type = "f", min = 0.1, max = 1, default = 0.6 })
  ctx.params.register("/mod/chorus/rate", { type = "f", min = 0.1, max = 5, default = 0.5 })
  ctx.params.register("/mod/osc/freq", { type = "f", min = 40, max = 880, default = 220 })
  ctx.params.register("/mod/osc/waveform", { type = "f", min = 0, max = 4, default = 1 })

  -- Static params (not modulated)
  ctx.params.register("/mod/delay/feedback", { type = "f", min = 0, max = 0.9, default = 0.4 })
  ctx.params.register("/mod/delay/mix", { type = "f", min = 0, max = 1, default = 0.3 })
  ctx.params.register("/mod/output", { type = "f", min = 0, max = 1, default = 0.4 })

  -- Bind static params directly
  ctx.params.bind("/mod/filter/res", filt, "setResonance")
  ctx.params.bind("/mod/delay/feedback", delay, "setFeedback")
  ctx.params.bind("/mod/delay/mix", delay, "setMix")
  ctx.params.bind("/mod/output", output, "setGain")

  return {
    description = "LFO parameter modulation demo - sliders animate to show modulation",
    params = {
      "/mod/lfo1/rate",
      "/mod/lfo1/depth",
      "/mod/lfo2/rate",
      "/mod/lfo2/depth",
      "/mod/lfo3/rate",
      "/mod/lfo3/depth",
      "/mod/filter/cutoff",
      "/mod/filter/res",
      "/mod/chorus/rate",
      "/mod/osc/freq",
      "/mod/osc/waveform",
      "/mod/delay/feedback",
      "/mod/delay/mix",
      "/mod/output",
    },
    onParamChange = function(path, value)
      if path == "/mod/filter/cutoff" then
        filt:setCutoff(value)
      elseif path == "/mod/chorus/rate" then
        chorus:setRate(value)
      elseif path == "/mod/osc/freq" then
        osc:setFrequency(value)
      elseif path == "/mod/osc/waveform" then
        osc:setWaveform(math.floor(value + 0.5))
      end
    end,
  }
end

return buildPlugin

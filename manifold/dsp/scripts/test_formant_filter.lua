-- test_formant_filter.lua
-- Formant filter test

function buildPlugin(ctx)
  local osc = ctx.primitives.OscillatorNode.new()
  local formant = ctx.primitives.FormantFilterNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(2)
  osc:setFrequency(140)
  osc:setAmplitude(0.4)

  formant:setVowel(0.0)
  formant:setShift(0.0)
  formant:setResonance(7.0)
  formant:setDrive(1.4)
  formant:setMix(1.0)

  gain:setGain(0.22)

  ctx.graph.connect(osc, formant)
  ctx.graph.connect(formant, gain)

  ctx.params.register("/test/formant/vowel", { type = "f", min = 0, max = 4, default = 0 })
  ctx.params.bind("/test/formant/vowel", formant, "setVowel")

  ctx.params.register("/test/formant/shift", { type = "f", min = -12, max = 12, default = 0 })
  ctx.params.bind("/test/formant/shift", formant, "setShift")

  ctx.params.register("/test/formant/resonance", { type = "f", min = 1, max = 20, default = 7 })
  ctx.params.bind("/test/formant/resonance", formant, "setResonance")

  ctx.params.register("/test/formant/drive", { type = "f", min = 0.5, max = 8, default = 1.4 })
  ctx.params.bind("/test/formant/drive", formant, "setDrive")

  ctx.params.register("/test/formant/mix", { type = "f", min = 0, max = 1, default = 1.0 })
  ctx.params.bind("/test/formant/mix", formant, "setMix")

  ctx.params.register("/test/output/gain", { type = "f", min = 0, max = 1, default = 0.22 })
  ctx.params.bind("/test/output/gain", gain, "setGain")

  return {
    description = "Formant filter test",
    params = {
      "/test/formant/vowel",
      "/test/formant/shift",
      "/test/formant/resonance",
      "/test/formant/drive",
      "/test/formant/mix",
      "/test/output/gain"
    }
  }
end

return buildPlugin

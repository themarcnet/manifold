-- test_midi_synth.lua
-- Basic MIDI monophonic synth
--
-- MIDI device selection via /midi/device/input (UI behavior creates dropdown).
-- MIDI notes routed by UI behavior via /midi/synth/note, /velocity, /gate params.

function buildPlugin(ctx)
  -- Voice chain: Osc → SVF → Gain
  local osc = ctx.primitives.OscillatorNode.new()
  local filt = ctx.primitives.SVFNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(1)  -- Saw
  osc:setFrequency(261.63)
  osc:setAmplitude(0)

  filt:setMode(0)  -- LP
  filt:setCutoff(2500)
  filt:setResonance(0.5)
  filt:setDrive(0.5)
  filt:setMix(1.0)

  gain:setGain(0.5)

  ctx.graph.connect(osc, filt)
  ctx.graph.connect(filt, gain)

  -- MIDI device selection (UI behavior creates dropdown for this)
  ctx.params.register("/midi/device/input", { type = "f", min = -1, max = 32, default = -1 })

  -- Voice control (set by UI behavior from MIDI callbacks)
  ctx.params.register("/midi/synth/note", { type = "f", min = 0, max = 127, default = 60 })
  ctx.params.register("/midi/synth/velocity", { type = "f", min = 0, max = 127, default = 100 })
  ctx.params.register("/midi/synth/gate", { type = "f", min = 0, max = 1, default = 0 })

  -- Sound shaping
  ctx.params.register("/midi/synth/waveform", { type = "f", min = 0, max = 4, default = 1 })
  ctx.params.register("/midi/synth/cutoff", { type = "f", min = 80, max = 12000, default = 2500 })
  ctx.params.register("/midi/synth/resonance", { type = "f", min = 0.1, max = 1.0, default = 0.5 })
  ctx.params.register("/midi/synth/drive", { type = "f", min = 0, max = 6, default = 0.5 })
  ctx.params.register("/midi/synth/output", { type = "f", min = 0, max = 1, default = 0.5 })

  -- Bind sound params
  ctx.params.bind("/midi/synth/cutoff", filt, "setCutoff")
  ctx.params.bind("/midi/synth/resonance", filt, "setResonance")
  ctx.params.bind("/midi/synth/drive", filt, "setDrive")
  ctx.params.bind("/midi/synth/output", gain, "setGain")

  local function noteToFreq(note)
    return 440.0 * math.pow(2, (note - 69) / 12)
  end

  local currentVelocity = 0

  return {
    description = "Basic MIDI mono synth - select MIDI device, play notes",
    params = {
      "/midi/device/input",
      "/midi/synth/note",
      "/midi/synth/velocity",
      "/midi/synth/gate",
      "/midi/synth/waveform",
      "/midi/synth/cutoff",
      "/midi/synth/resonance",
      "/midi/synth/drive",
      "/midi/synth/output",
    },
    onParamChange = function(path, value)
      if path == "/midi/synth/note" then
        osc:setFrequency(noteToFreq(value))
      elseif path == "/midi/synth/velocity" then
        currentVelocity = value
        -- Don't update amplitude here, gate handles it
      elseif path == "/midi/synth/gate" then
        if value > 0.5 then
          osc:setAmplitude((currentVelocity / 127) * 0.4)
        else
          osc:setAmplitude(0)
        end
      elseif path == "/midi/synth/waveform" then
        osc:setWaveform(math.floor(value + 0.5))
      end
    end,
  }
end

return buildPlugin

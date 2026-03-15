-- test_midi_arp.lua
-- MIDI Arpeggiator synth
--
-- The DSP side is just a synth voice. The arpeggiator logic runs in the
-- UI behavior (DspLiveScripting/main.lua update loop) which:
--   1. Opens the selected MIDI device
--   2. Receives MIDI notes and tracks held notes
--   3. Steps through held notes on a timer
--   4. Sends /arp/note, /arp/gate, /arp/velocity params each step
--
-- Arp config params (/arp/tempo, /arp/rate, etc.) are read by the UI behavior
-- to control stepping. They don't do anything in DSP onParamChange.

function buildPlugin(ctx)
  -- Voice chain: Osc → SVF → Delay → Gain
  local osc = ctx.primitives.OscillatorNode.new()
  local filt = ctx.primitives.SVFNode.new()
  local delay = ctx.primitives.StereoDelayNode.new()
  local gain = ctx.primitives.GainNode.new(2)

  osc:setWaveform(1)  -- Saw
  osc:setFrequency(220)
  osc:setAmplitude(0)

  filt:setMode(0)  -- LP
  filt:setCutoff(3000)
  filt:setResonance(0.5)
  filt:setDrive(0.8)
  filt:setMix(1.0)

  delay:setTempo(120)
  delay:setTimeMode(0)
  delay:setTimeL(375)
  delay:setTimeR(500)
  delay:setFeedback(0.35)
  delay:setMix(0.25)
  delay:setPingPong(true)

  gain:setGain(0.5)

  ctx.graph.connect(osc, filt)
  ctx.graph.connect(filt, delay)
  ctx.graph.connect(delay, gain)

  -- MIDI device selection (UI behavior creates dropdown for this)
  ctx.params.register("/midi/device/input", { type = "f", min = -1, max = 32, default = -1 })

  -- Voice control (set by UI behavior's arp engine)
  ctx.params.register("/arp/note", { type = "f", min = 0, max = 127, default = 60 })
  ctx.params.register("/arp/velocity", { type = "f", min = 0, max = 127, default = 100 })
  ctx.params.register("/arp/gate", { type = "f", min = 0, max = 1, default = 0 })

  -- Arp config (read by UI behavior to control stepping)
  ctx.params.register("/arp/tempo", { type = "f", min = 40, max = 300, default = 120 })
  ctx.params.register("/arp/rate", { type = "f", min = 0, max = 4, default = 2 })      -- 0=1/4, 1=1/8, 2=1/16, 3=1/32, 4=1/64
  ctx.params.register("/arp/pattern", { type = "f", min = 0, max = 3, default = 0 })    -- 0=up, 1=down, 2=updown, 3=random
  ctx.params.register("/arp/octaves", { type = "f", min = 1, max = 4, default = 1 })
  ctx.params.register("/arp/gate_len", { type = "f", min = 0.1, max = 1, default = 0.8 })
  ctx.params.register("/arp/swing", { type = "f", min = 0, max = 0.9, default = 0 })

  -- Sound shaping
  ctx.params.register("/arp/waveform", { type = "f", min = 0, max = 4, default = 1 })
  ctx.params.register("/arp/filter/cutoff", { type = "f", min = 80, max = 12000, default = 3000 })
  ctx.params.register("/arp/filter/res", { type = "f", min = 0.1, max = 1.0, default = 0.5 })
  ctx.params.register("/arp/filter/drive", { type = "f", min = 0, max = 6, default = 0.8 })
  ctx.params.register("/arp/delay/mix", { type = "f", min = 0, max = 1, default = 0.25 })
  ctx.params.register("/arp/delay/feedback", { type = "f", min = 0, max = 0.95, default = 0.35 })
  ctx.params.register("/arp/output", { type = "f", min = 0, max = 1, default = 0.5 })

  -- Bind sound params directly
  ctx.params.bind("/arp/filter/cutoff", filt, "setCutoff")
  ctx.params.bind("/arp/filter/res", filt, "setResonance")
  ctx.params.bind("/arp/filter/drive", filt, "setDrive")
  ctx.params.bind("/arp/delay/mix", delay, "setMix")
  ctx.params.bind("/arp/delay/feedback", delay, "setFeedback")
  ctx.params.bind("/arp/output", gain, "setGain")

  local function noteToFreq(note)
    return 440.0 * math.pow(2, (note - 69) / 12)
  end

  return {
    description = "MIDI arpeggiator synth - select MIDI device, hold notes, arp steps through them",
    params = {
      "/midi/device/input",
      "/arp/note",
      "/arp/velocity",
      "/arp/gate",
      "/arp/tempo",
      "/arp/rate",
      "/arp/pattern",
      "/arp/octaves",
      "/arp/gate_len",
      "/arp/swing",
      "/arp/waveform",
      "/arp/filter/cutoff",
      "/arp/filter/res",
      "/arp/filter/drive",
      "/arp/delay/mix",
      "/arp/delay/feedback",
      "/arp/output",
    },
    onParamChange = function(path, value)
      if path == "/arp/note" then
        osc:setFrequency(noteToFreq(value))
      elseif path == "/arp/velocity" then
        -- Velocity scales amplitude when gate is on
      elseif path == "/arp/gate" then
        if value > 0.5 then
          osc:setAmplitude(0.4)
        else
          osc:setAmplitude(0)
        end
      elseif path == "/arp/waveform" then
        osc:setWaveform(math.floor(value + 0.5))
      elseif path == "/arp/tempo" then
        delay:setTempo(value)
      end
    end,
  }
end

return buildPlugin

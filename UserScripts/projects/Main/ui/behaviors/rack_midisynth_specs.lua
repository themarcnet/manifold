local RackLayout = require("behaviors.rack_layout")

local M = {}

local function copyPorts(ports)
  local out = { inputs = {}, outputs = {}, params = {} }
  if type(ports) ~= "table" then
    return out
  end
  for _, key in ipairs({ "inputs", "outputs", "params" }) do
    local source = type(ports[key]) == "table" and ports[key] or {}
    for i = 1, #source do
      out[key][i] = source[i]
    end
  end
  return out
end

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deepCopy(v)
  end
  return out
end

local MODULE_META_DEFAULTS = {
  adsr = {
    category = "voice",
    description = "Canonical voice control module. Converts MIDI/voice bundles into articulated voice output.",
    instancePolicy = "singleton_or_dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "ADSR",
      portSummary = "MIDI/VOICE -> VOICE, ENV, INV, EOC",
      order = 20,
    },
  },
  arp = {
    category = "voice",
    description = "Rotates held notes across voice lanes while preserving bundle state for downstream modules.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "template_token",
    palette = {
      displayName = "Arpeggiator",
      portSummary = "VOICE -> VOICE",
      order = 30,
    },
  },
  transpose = {
    category = "voice",
    description = "Shifts incoming voice bundles by semitone offsets before passing them downstream.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Transpose",
      portSummary = "VOICE -> VOICE",
      order = 25,
    },
  },
  velocity_mapper = {
    category = "voice",
    description = "Remaps incoming voice bundle velocity/amplitude response before downstream modules.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Velocity",
      portSummary = "VOICE -> VOICE",
      order = 26,
    },
  },
  scale_quantizer = {
    category = "voice",
    description = "Quantizes incoming note values to a selected root and scale.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Scale Quantizer",
      portSummary = "VOICE -> VOICE",
      order = 26,
    },
  },
  note_filter = {
    category = "voice",
    description = "Passes or blocks incoming voice bundles according to note range rules.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Note Filter",
      portSummary = "VOICE -> VOICE",
      order = 26,
    },
  },
  attenuverter_bias = {
    category = "mod",
    description = "Scale, invert, and bias a scalar modulation signal. Out = clamp((in * amount) + bias, -1, 1).",
    instancePolicy = "dynamic",
    runtimeKind = "stateless_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "ATV / Bias",
      portSummary = "IN -> OUT",
      order = 26,
    },
  },
  lfo = {
    category = "mod",
    description = "Generates cyclic scalar modulation with bipolar, unipolar, inverted, and end-of-cycle outputs.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "LFO",
      portSummary = "RESET/SYNC -> OUT, INV, UNI, EOC",
      order = 28,
    },
  },
  slew = {
    category = "mod",
    description = "Smooths incoming scalar modulation with independent rise and fall times.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Slew",
      portSummary = "IN -> OUT",
      order = 29,
    },
  },
  sample_hold = {
    category = "mod",
    description = "Samples and holds incoming scalar modulation on trigger, with tracking and stepped modes.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Sample & Hold",
      portSummary = "IN/TRIG -> OUT, INV",
      order = 30,
    },
  },
  compare = {
    category = "mod",
    description = "Generates gate and trigger events when a scalar signal crosses a threshold with hysteresis.",
    instancePolicy = "dynamic",
    runtimeKind = "stateful_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Compare",
      portSummary = "IN -> GATE, TRIG",
      order = 31,
    },
  },
  cv_mix = {
    category = "mod",
    description = "Combines up to four scalar modulation inputs with per-channel levels and an offset control.",
    instancePolicy = "dynamic",
    runtimeKind = "stateless_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "CV Mix",
      portSummary = "IN1..4 -> OUT, INV",
      order = 32,
    },
  },
  oscillator = {
    category = "audio",
    description = "Primary synth oscillator/source panel feeding the canonical rack audio path.",
    instancePolicy = "singleton",
    runtimeKind = "source",
    paramTemplateMode = "absolute",
    palette = {
      displayName = "Oscillator",
      portSummary = "VOICE -> OUT",
      order = 40,
    },
  },
  rack_oscillator = {
    category = "audio",
    description = "Standalone rack oscillator voice target with direct rack routing and legacy loudness parity.",
    instancePolicy = "dynamic",
    runtimeKind = "source",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Oscillator",
      portSummary = "VOICE -> OUT, ANALYSIS",
      order = 50,
    },
  },
  rack_sample = {
    category = "audio",
    description = "Standalone sample source with capture controls, classic/PVoc/HQ pitch handling, and exported analysis data.",
    instancePolicy = "dynamic",
    runtimeKind = "source",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Sample",
      portSummary = "IN/VOICE -> OUT, ANALYSIS",
      order = 52,
    },
  },
  blend_simple = {
    category = "audio",
    description = "Simple dual-input blend stage with mix, ring, FM, and sync modes using serial A plus auxiliary B.",
    instancePolicy = "dynamic",
    runtimeKind = "processor",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Blend",
      portSummary = "A/B -> OUT",
      order = 54,
    },
  },
  filter = {
    category = "audio",
    description = "Tone-shaping audio stage. Canonical slot can be restored, dynamic slots can be added when available.",
    instancePolicy = "canonical_or_dynamic",
    runtimeKind = "processor",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Filter",
      portSummary = "IN -> OUT",
      order = 60,
    },
  },
  fx1 = {
    category = "fx",
    description = "Canonical first insert FX stage in the default rack chain.",
    instancePolicy = "canonical_slot",
    runtimeKind = "processor",
    paramTemplateMode = "slot_absolute",
    palette = {
      displayName = "FX1",
      portSummary = "IN -> OUT",
      order = 70,
    },
  },
  fx2 = {
    category = "fx",
    description = "Canonical second insert FX stage in the default rack chain.",
    instancePolicy = "canonical_slot",
    runtimeKind = "processor",
    paramTemplateMode = "slot_absolute",
    palette = {
      displayName = "FX2",
      portSummary = "IN -> OUT",
      order = 80,
    },
  },
  fx = {
    category = "fx",
    description = "General insert effect slot. Restores canonical FX slots first, then uses dynamic slots.",
    instancePolicy = "canonical_or_dynamic",
    runtimeKind = "processor",
    paramTemplateMode = "dynamic_slot_remap",
    palette = {
      displayName = "FX",
      portSummary = "IN -> OUT",
      order = 90,
    },
  },
  eq = {
    category = "fx",
    description = "Equalizer stage for spectral shaping inside the rack chain.",
    instancePolicy = "canonical_or_dynamic",
    runtimeKind = "processor",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "EQ",
      portSummary = "IN -> OUT",
      order = 100,
    },
  },
  range_mapper = {
    category = "mod",
    description = "Clamp or remap a scalar modulation signal into a controlled output range.",
    instancePolicy = "dynamic",
    runtimeKind = "stateless_transform",
    paramTemplateMode = "dynamic_param_base",
    palette = {
      displayName = "Range",
      portSummary = "SCALAR -> SCALAR",
      order = 35,
    },
  },
  placeholder1 = {
    category = "audio",
    description = "Empty insert/split point for future routing and module insertion.",
    instancePolicy = "placeholder",
    runtimeKind = "passthrough",
    paramTemplateMode = "none",
    palette = {
      displayName = "Slot",
      portSummary = "AUDIO IN -> AUDIO OUT",
      order = 10,
    },
  },
  placeholder2 = {
    category = "audio",
    description = "Empty insert/split point for future routing and module insertion.",
    instancePolicy = "placeholder",
    runtimeKind = "passthrough",
    paramTemplateMode = "none",
    palette = {
      displayName = "Slot",
      portSummary = "AUDIO IN -> AUDIO OUT",
      order = 11,
    },
  },
  placeholder3 = {
    category = "audio",
    description = "Empty insert/split point for future routing and module insertion.",
    instancePolicy = "placeholder",
    runtimeKind = "passthrough",
    paramTemplateMode = "none",
    palette = {
      displayName = "Slot",
      portSummary = "AUDIO IN -> AUDIO OUT",
      order = 12,
    },
  },
  placeholder = {
    category = "audio",
    description = "Empty insert/split point for future routing and module insertion.",
    instancePolicy = "placeholder",
    runtimeKind = "passthrough",
    paramTemplateMode = "none",
    palette = {
      displayName = "Slot",
      portSummary = "AUDIO IN -> AUDIO OUT",
      order = 10,
    },
  },
}

local MODULE_PARAM_REMAP_DEFAULTS = {
  adsr = {
    exact = {
      ["/midi/synth/adsr/attack"] = "/attack",
      ["/midi/synth/adsr/decay"] = "/decay",
      ["/midi/synth/adsr/sustain"] = "/sustain",
      ["/midi/synth/adsr/release"] = "/release",
    },
  },
  arp = {
    exact = {
      ["/midi/synth/rack/arp/__template/rate"] = "/rate",
      ["/midi/synth/rack/arp/__template/mode"] = "/mode",
      ["/midi/synth/rack/arp/__template/octaves"] = "/octaves",
      ["/midi/synth/rack/arp/__template/gate"] = "/gate",
      ["/midi/synth/rack/arp/__template/hold"] = "/hold",
    },
  },
  transpose = {
    exact = {
      ["/midi/synth/rack/transpose/__template/semitones"] = "/semitones",
    },
  },
  velocity_mapper = {
    exact = {
      ["/midi/synth/rack/velocity_mapper/__template/amount"] = "/amount",
      ["/midi/synth/rack/velocity_mapper/__template/curve"] = "/curve",
      ["/midi/synth/rack/velocity_mapper/__template/offset"] = "/offset",
    },
  },
  scale_quantizer = {
    exact = {
      ["/midi/synth/rack/scale_quantizer/__template/root"] = "/root",
      ["/midi/synth/rack/scale_quantizer/__template/scale"] = "/scale",
      ["/midi/synth/rack/scale_quantizer/__template/direction"] = "/direction",
    },
  },
  note_filter = {
    exact = {
      ["/midi/synth/rack/note_filter/__template/low"] = "/low",
      ["/midi/synth/rack/note_filter/__template/high"] = "/high",
      ["/midi/synth/rack/note_filter/__template/mode"] = "/mode",
    },
  },
  attenuverter_bias = {
    exact = {
      ["/midi/synth/rack/attenuverter_bias/__template/amount"] = "/amount",
      ["/midi/synth/rack/attenuverter_bias/__template/bias"] = "/bias",
    },
  },
  range_mapper = {
    exact = {
      ["/midi/synth/rack/range_mapper/__template/min"] = "/min",
      ["/midi/synth/rack/range_mapper/__template/max"] = "/max",
      ["/midi/synth/rack/range_mapper/__template/mode"] = "/mode",
    },
  },
  lfo = {
    exact = {
      ["/midi/synth/rack/lfo/__template/rate"] = "/rate",
      ["/midi/synth/rack/lfo/__template/shape"] = "/shape",
      ["/midi/synth/rack/lfo/__template/depth"] = "/depth",
      ["/midi/synth/rack/lfo/__template/phase"] = "/phase",
      ["/midi/synth/rack/lfo/__template/retrig"] = "/retrig",
    },
  },
  slew = {
    exact = {
      ["/midi/synth/rack/slew/__template/rise"] = "/rise",
      ["/midi/synth/rack/slew/__template/fall"] = "/fall",
      ["/midi/synth/rack/slew/__template/shape"] = "/shape",
    },
  },
  sample_hold = {
    exact = {
      ["/midi/synth/rack/sample_hold/__template/mode"] = "/mode",
    },
  },
  compare = {
    exact = {
      ["/midi/synth/rack/compare/__template/threshold"] = "/threshold",
      ["/midi/synth/rack/compare/__template/hysteresis"] = "/hysteresis",
      ["/midi/synth/rack/compare/__template/direction"] = "/direction",
    },
  },
  cv_mix = {
    exact = {
      ["/midi/synth/rack/cv_mix/__template/level_1"] = "/level_1",
      ["/midi/synth/rack/cv_mix/__template/level_2"] = "/level_2",
      ["/midi/synth/rack/cv_mix/__template/level_3"] = "/level_3",
      ["/midi/synth/rack/cv_mix/__template/level_4"] = "/level_4",
      ["/midi/synth/rack/cv_mix/__template/offset"] = "/offset",
    },
  },

  eq = {
    exact = {
      ["/midi/synth/eq8/output"] = "/output",
      ["/midi/synth/eq8/mix"] = "/mix",
    },
    patterns = {
      { match = "^/midi/synth/eq8/band/(%d+)/(.+)$", toSuffixTemplate = "/band/{1}/{2}" },
    },
  },
  fx = {
    exact = {
      ["/midi/synth/fx1/type"] = "/type",
      ["/midi/synth/fx2/type"] = "/type",
      ["/midi/synth/fx1/mix"] = "/mix",
      ["/midi/synth/fx2/mix"] = "/mix",
    },
    patterns = {
      { match = "^/midi/synth/fx[12]/p/(%d+)$", toSuffixTemplate = "/p/{1}" },
    },
    clearMeta = { "slot" },
  },
  filter = {
    exact = {
      ["/midi/synth/filterType"] = "/type",
      ["/midi/synth/cutoff"] = "/cutoff",
      ["/midi/synth/resonance"] = "/resonance",
    },
  },
  rack_oscillator = {
    exact = {
      ["/midi/synth/waveform"] = "/waveform",
      ["/midi/synth/osc/renderMode"] = "/renderMode",
      ["/midi/synth/osc/add/partials"] = "/additivePartials",
      ["/midi/synth/osc/add/tilt"] = "/additiveTilt",
      ["/midi/synth/osc/add/drift"] = "/additiveDrift",
      ["/midi/synth/drive"] = "/drive",
      ["/midi/synth/driveShape"] = "/driveShape",
      ["/midi/synth/driveBias"] = "/driveBias",
      ["/midi/synth/pulseWidth"] = "/pulseWidth",
      ["/midi/synth/unison"] = "/unison",
      ["/midi/synth/detune"] = "/detune",
      ["/midi/synth/spread"] = "/spread",
      ["/midi/synth/rack/osc/manualPitch"] = "/manualPitch",
      ["/midi/synth/rack/osc/manualLevel"] = "/manualLevel",
      ["/midi/synth/rack/osc/output"] = "/output",
      ["/midi/synth/output"] = "/output",
    },
  },
  rack_sample = {
    exact = {
      ["/midi/synth/sample/source"] = "/source",
      ["/midi/synth/sample/captureTrigger"] = "/captureTrigger",
      ["/midi/synth/sample/captureBars"] = "/captureBars",
      ["/midi/synth/sample/captureMode"] = "/captureMode",
      ["/midi/synth/sample/captureStartOffset"] = "/captureStartOffset",
      ["/midi/synth/sample/capturedLengthMs"] = "/capturedLengthMs",
      ["/midi/synth/sample/captureRecording"] = "/captureRecording",
      ["/midi/synth/sample/pitchMapEnabled"] = "/pitchMapEnabled",
      ["/midi/synth/sample/pitchMode"] = "/pitchMode",
      ["/midi/synth/sample/pvoc/fftOrder"] = "/pvoc/fftOrder",
      ["/midi/synth/sample/pvoc/timeStretch"] = "/pvoc/timeStretch",
      ["/midi/synth/sample/rootNote"] = "/rootNote",
      ["/midi/synth/unison"] = "/unison",
      ["/midi/synth/detune"] = "/detune",
      ["/midi/synth/spread"] = "/spread",
      ["/midi/synth/sample/playStart"] = "/playStart",
      ["/midi/synth/sample/loopStart"] = "/loopStart",
      ["/midi/synth/sample/loopLen"] = "/loopLen",
      ["/midi/synth/sample/crossfade"] = "/crossfade",
      ["/midi/synth/sample/retrigger"] = "/retrigger",
      ["/midi/synth/output"] = "/output",
    },
  },
  blend_simple = {
    exact = {
      ["/midi/synth/rack/blend_simple/__template/mode"] = "/mode",
      ["/midi/synth/rack/blend_simple/__template/blendAmount"] = "/blendAmount",
      ["/midi/synth/rack/blend_simple/__template/blendModAmount"] = "/blendModAmount",
      ["/midi/synth/rack/blend_simple/__template/output"] = "/output",
    },
  },
}

local MODULE_CONTROL_PORT_DEFAULTS = {
  adsr = {
    midi = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "ADSR MIDI In" },
    gate = { scope = "voice", signalKind = "gate", domain = "event", min = 0, max = 1, default = 0, displayName = "ADSR Gate" },
    retrig = { scope = "voice", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "ADSR Retrig" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "ADSR Voice" },
    env = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0, displayName = "ADSR Env" },
    inv = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 1, displayName = "ADSR Inverted Env" },
    eoc = { scope = "voice", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "ADSR End Of Cycle" },
  },
  arp = {
    voice_in = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Arp Voice In" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Arp Voice Out" },
  },
  transpose = {
    voice_in = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Transpose Voice In" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Transpose Voice Out" },
  },
  velocity_mapper = {
    voice_in = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Velocity Mapper Voice In" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Velocity Mapper Voice Out" },
  },
  scale_quantizer = {
    voice_in = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Scale Quantizer Voice In" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Scale Quantizer Voice Out" },
  },
  note_filter = {
    voice_in = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Note Filter Voice In" },
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Note Filter Voice Out" },
  },
  attenuverter_bias = {
    ["in"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "ATV/Bias In" },
    ["out"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "ATV/Bias Out" },
  },
  lfo = {
    reset = { scope = "global", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "LFO Reset" },
    sync = { scope = "global", signalKind = "gate", domain = "event", min = 0, max = 1, default = 0, displayName = "LFO Sync" },
    out = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "LFO Out" },
    inv = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "LFO Inverted" },
    uni = { scope = "global", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0, displayName = "LFO Unipolar" },
    eoc = { scope = "global", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "LFO End Of Cycle" },
  },
  slew = {
    ["in"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Slew In" },
    ["out"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Slew Out" },
  },
  sample_hold = {
    ["in"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Sample Hold In" },
    trig = { scope = "global", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "Sample Hold Trigger" },
    ["out"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Sample Hold Out" },
    inv = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Sample Hold Inverted" },
  },
  compare = {
    ["in"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Compare In" },
    gate = { scope = "global", signalKind = "gate", domain = "event", min = 0, max = 1, default = 0, displayName = "Compare Gate" },
    trig = { scope = "global", signalKind = "trigger", domain = "event", min = 0, max = 1, default = 0, displayName = "Compare Trigger" },
  },
  cv_mix = {
    in_1 = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix In 1" },
    in_2 = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix In 2" },
    in_3 = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix In 3" },
    in_4 = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix In 4" },
    ["out"] = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix Out" },
    inv = { scope = "global", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "CV Mix Inverted" },
  },
  oscillator = {
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Oscillator Voice" },
    gate = { scope = "voice", signalKind = "gate", domain = "event", min = 0, max = 1, default = 0, displayName = "Oscillator Gate" },
    v_oct = { scope = "voice", signalKind = "scalar", domain = "midi_note", min = 0, max = 127, default = 60, displayName = "Oscillator V/Oct" },
    fm = { scope = "voice", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Oscillator FM" },
    pw_cv = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0.5, displayName = "Oscillator Pulse Width CV" },
    blend_cv = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0.5, displayName = "Oscillator Blend CV" },
  },
  rack_oscillator = {
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Rack Oscillator Voice" },
    gate = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 0.4, default = 0, displayName = "Rack Oscillator Gate" },
    v_oct = { scope = "voice", signalKind = "scalar", domain = "midi_note", min = 0, max = 127, default = 60, displayName = "Rack Oscillator V/Oct" },
    fm = { scope = "voice", signalKind = "scalar_bipolar", domain = "normalized", min = -1, max = 1, default = 0, displayName = "Rack Oscillator FM" },
    pw_cv = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0.5, displayName = "Rack Oscillator Pulse Width CV" },
  },
  rack_sample = {
    voice = { scope = "voice", signalKind = "voice_bundle", domain = "voice", min = 0, max = 1, default = 0, displayName = "Rack Sample Voice" },
    gate = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0, displayName = "Rack Sample Gate" },
    v_oct = { scope = "voice", signalKind = "scalar", domain = "midi_note", min = 0, max = 127, default = 60, displayName = "Rack Sample V/Oct" },
  },
  blend_simple = {
    a = { scope = "global", signalKind = "audio", domain = "audio", default = 0, displayName = "Blend A" },
    b = { scope = "global", signalKind = "audio", domain = "audio", default = 0, displayName = "Blend B" },
    out = { scope = "global", signalKind = "audio", domain = "audio", default = 0, displayName = "Blend Out" },
  },
  filter = {
    env = { scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", min = 0, max = 1, default = 0, displayName = "Filter Env" },
  },
}

local function inferParamScope(param)
  if type(param) == "table" and type(param.scope) == "string" and param.scope ~= "" then
    return param.scope
  end
  local path = type(param) == "table" and tostring(param.path or "") or ""
  if path:match("^/midi/synth/voice/") or path:match("/voice/%d+/") then
    return "voice"
  end
  return "global"
end

local function inferParamSignalKind(param)
  if type(param) == "table" and type(param.signalKind) == "string" and param.signalKind ~= "" then
    return param.signalKind
  end
  if type(param) == "table" then
    if type(param.options) == "table" and #param.options > 0 then
      return "stepped"
    end
    if tostring(param.format or "") == "enum" then
      return "stepped"
    end
    local minValue = tonumber(param.min)
    local maxValue = tonumber(param.max)
    if minValue ~= nil and maxValue ~= nil and minValue < 0.0 and maxValue > 0.0 then
      return "scalar_bipolar"
    end
    if minValue ~= nil and maxValue ~= nil and minValue >= 0.0 and maxValue <= 1.0 then
      return "scalar_unipolar"
    end
  end
  return "scalar"
end

local function inferParamDomain(param)
  if type(param) == "table" and type(param.domain) == "string" and param.domain ~= "" then
    return param.domain
  end
  if type(param) ~= "table" then
    return "normalized"
  end
  local format = tostring(param.format or "")
  local path = tostring(param.path or "")
  if format == "freq" or path:match("/cutoff$") or path:match("/freq$") then
    return "freq"
  end
  if format == "time" then
    return "time"
  end
  if format == "enum" then
    return "enum_index"
  end
  if path:match("/manualPitch$") or path:match("/vOct$") then
    return "midi_note"
  end
  if path:match("/output$") and tonumber(param.min) ~= nil and tonumber(param.min) < 0 then
    return "gain_db"
  end
  if path:match("/q$") then
    return "q"
  end
  return "normalized"
end

local function normalizeControlPort(specKey, direction, port)
  if type(port) ~= "table" then
    return port
  end
  local defaults = MODULE_CONTROL_PORT_DEFAULTS[tostring(specKey or "")] or {}
  local portDefaults = defaults[tostring(port.id or "")] or {}
  port.direction = tostring(port.direction or (direction == "inputs" and "target" or "source"))
  port.scope = tostring(port.scope or portDefaults.scope or (tostring(port.type or "") == "audio" and "global" or "global"))
  port.signalKind = tostring(port.signalKind or portDefaults.signalKind or (tostring(port.type or "") == "audio" and "audio" or "scalar"))
  port.domain = tostring(port.domain or portDefaults.domain or (tostring(port.type or "") == "audio" and "audio" or "normalized"))
  port.displayName = tostring(port.displayName or portDefaults.displayName or port.label or port.id or "")
  if port.min == nil then port.min = portDefaults.min end
  if port.max == nil then port.max = portDefaults.max end
  if port.default == nil then port.default = portDefaults.default end
  return port
end

local function normalizeParamDescriptor(param)
  if type(param) ~= "table" then
    return param
  end
  param.scope = inferParamScope(param)
  param.signalKind = inferParamSignalKind(param)
  param.domain = inferParamDomain(param)
  param.displayName = tostring(param.displayName or param.label or param.id or param.path or "")
  return param
end

local function normalizeModuleSpec(spec)
  if type(spec) ~= "table" then
    return spec
  end
  local specKey = tostring(type(spec.meta) == "table" and spec.meta.specId or spec.id or "")
  local defaults = MODULE_META_DEFAULTS[specKey] or {}
  spec.meta = deepCopy(spec.meta or {})
  spec.meta.factoryVersion = tonumber(spec.meta.factoryVersion) or 1
  spec.meta.category = tostring(spec.meta.category or defaults.category or "utility")
  spec.meta.description = tostring(spec.meta.description or defaults.description or "")
  spec.meta.instancePolicy = tostring(spec.meta.instancePolicy or defaults.instancePolicy or "manual")
  spec.meta.runtimeKind = tostring(spec.meta.runtimeKind or defaults.runtimeKind or "processor")
  spec.meta.paramTemplateMode = tostring(spec.meta.paramTemplateMode or defaults.paramTemplateMode or "absolute")
  spec.meta.paramPathRemap = deepCopy(spec.meta.paramPathRemap or MODULE_PARAM_REMAP_DEFAULTS[specKey] or nil)
  spec.meta.palette = deepCopy(spec.meta.palette or {})
  spec.meta.palette.displayName = tostring(spec.meta.palette.displayName or defaults.palette and defaults.palette.displayName or spec.name or spec.id)
  spec.meta.palette.description = tostring(spec.meta.palette.description or defaults.palette and defaults.palette.description or spec.meta.description or "")
  spec.meta.palette.portSummary = tostring(spec.meta.palette.portSummary or defaults.palette and defaults.palette.portSummary or "")
  spec.meta.palette.order = math.max(0, math.floor(tonumber(spec.meta.palette.order or defaults.palette and defaults.palette.order or 999) or 999))

  spec.ports = deepCopy(spec.ports or {})
  for _, key in ipairs({ "inputs", "outputs" }) do
    local ports = type(spec.ports[key]) == "table" and spec.ports[key] or {}
    spec.ports[key] = ports
    for i = 1, #ports do
      ports[i] = normalizeControlPort(specKey, key, deepCopy(ports[i]))
    end
  end
  local params = type(spec.ports.params) == "table" and spec.ports.params or {}
  spec.ports.params = params
  for i = 1, #params do
    params[i] = normalizeParamDescriptor(deepCopy(params[i]))
  end

  return spec
end

local RACK_MODULE_SPECS = {
  RackLayout.makeRackModuleSpec {
    id = "adsr",
    name = "ADSR",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xfffda4af,
    ports = copyPorts {
      inputs = {
        { id = "midi", type = "control", label = "MIDI" },
        { id = "gate", type = "control", label = "GATE" },
        { id = "retrig", type = "control", label = "RETRIG" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
        { id = "env", type = "control", label = "ENV" },
        { id = "inv", type = "control", label = "INV" },
        { id = "eoc", type = "control", label = "EOC" },
      },
      params = {
        { id = "attack", label = "Attack", path = "/midi/synth/adsr/attack",
          min = 0.001, max = 2.0, step = 0.001, default = 0.05,
          format = "time", input = true, output = true },
        { id = "decay", label = "Decay", path = "/midi/synth/adsr/decay",
          min = 0.001, max = 2.0, step = 0.001, default = 0.2,
          format = "time", input = true, output = true },
        { id = "sustain", label = "Sustain", path = "/midi/synth/adsr/sustain",
          min = 0.0, max = 1.0, step = 0.01, default = 0.7,
          format = "percent", input = true, output = true },
        { id = "release", label = "Release", path = "/midi/synth/adsr/release",
          min = 0.001, max = 5.0, step = 0.001, default = 0.4,
          format = "time", input = true, output = true },
      },
    },
    meta = {
      componentId = "envelopeComponent",
      behavior = "ui/behaviors/envelope.lua",
      componentRef = "ui/components/envelope.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "arp",
    name = "Arpeggiator",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xfff59e0b,
    ports = copyPorts {
      inputs = {
        { id = "voice_in", type = "control", label = "VOICE" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
      },
      params = {
        { id = "rate", label = "Rate", path = "/midi/synth/rack/arp/__template/rate",
          min = 0.25, max = 20.0, step = 0.25, default = 8.0,
          format = "float", input = true, output = true },
        { id = "mode", label = "Mode", path = "/midi/synth/rack/arp/__template/mode",
          min = 0, max = 3, step = 1, default = 0,
          format = "enum",
          options = { "Up", "Down", "Up/Down", "Random" },
          input = true, output = true },
        { id = "octaves", label = "Octaves", path = "/midi/synth/rack/arp/__template/octaves",
          min = 1, max = 4, step = 1, default = 1,
          format = "int", input = true, output = true },
        { id = "gate", label = "Gate", path = "/midi/synth/rack/arp/__template/gate",
          min = 0.05, max = 1.0, step = 0.01, default = 0.6,
          format = "percent", input = true, output = true },
        { id = "hold", label = "Hold", path = "/midi/synth/rack/arp/__template/hold",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Off", "On" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "arpComponent",
      behavior = "ui/behaviors/arp.lua",
      componentRef = "ui/components/arp.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "transpose",
    name = "Transpose",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff22c55e,
    ports = copyPorts {
      inputs = {
        { id = "voice_in", type = "control", label = "VOICE" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
      },
      params = {
        { id = "semitones", label = "Semitones", path = "/midi/synth/rack/transpose/__template/semitones",
          min = -24, max = 24, step = 1, default = 0,
          format = "int", signalKind = "scalar_bipolar", domain = "midi_note_delta",
          input = true, output = true },
      },
    },
    meta = {
      componentId = "transposeComponent",
      behavior = "ui/behaviors/transpose.lua",
      componentRef = "ui/components/transpose.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "velocity_mapper",
    name = "Velocity Mapper",
    validSizes = { "1x1" },
    accentColor = 0xff4ade80,
    ports = copyPorts {
      inputs = {
        { id = "voice_in", type = "control", label = "VOICE" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
      },
      params = {
        { id = "amount", label = "Amount", path = "/midi/synth/rack/velocity_mapper/__template/amount",
          min = 0, max = 1, step = 0.01, default = 1.0,
          format = "percent", input = true, output = true },
        { id = "curve", label = "Curve", path = "/midi/synth/rack/velocity_mapper/__template/curve",
          min = 0, max = 2, step = 1, default = 0,
          format = "enum", options = { "Linear", "Soft", "Hard" },
          input = true, output = true },
        { id = "offset", label = "Offset", path = "/midi/synth/rack/velocity_mapper/__template/offset",
          min = -1, max = 1, step = 0.01, default = 0.0,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "velocityMapperComponent",
      behavior = "ui/behaviors/velocity_mapper.lua",
      componentRef = "ui/components/velocity_mapper.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "scale_quantizer",
    name = "Scale Quantizer",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff22c55e,
    ports = copyPorts {
      inputs = {
        { id = "voice_in", type = "control", label = "VOICE" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
      },
      params = {
        { id = "root", label = "Root", path = "/midi/synth/rack/scale_quantizer/__template/root",
          min = 0, max = 11, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "scale", label = "Scale", path = "/midi/synth/rack/scale_quantizer/__template/scale",
          min = 1, max = 6, step = 1, default = 1,
          format = "enum",
          options = { "Major", "Minor", "Dorian", "Mixolydian", "Pentatonic", "Chromatic" },
          input = true, output = true },
        { id = "direction", label = "Direction", path = "/midi/synth/rack/scale_quantizer/__template/direction",
          min = 1, max = 3, step = 1, default = 1,
          format = "enum",
          options = { "Nearest", "Up", "Down" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "scaleQuantizerComponent",
      behavior = "ui/behaviors/scale_quantizer.lua",
      componentRef = "ui/components/scale_quantizer.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "note_filter",
    name = "Note Filter",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff22c55e,
    ports = copyPorts {
      inputs = {
        { id = "voice_in", type = "control", label = "VOICE" },
      },
      outputs = {
        { id = "voice", type = "control", label = "VOICE" },
      },
      params = {
        { id = "low", label = "Low", path = "/midi/synth/rack/note_filter/__template/low",
          min = 0, max = 127, step = 1, default = 36,
          format = "int", signalKind = "scalar", domain = "midi_note",
          input = true, output = true },
        { id = "high", label = "High", path = "/midi/synth/rack/note_filter/__template/high",
          min = 0, max = 127, step = 1, default = 96,
          format = "int", signalKind = "scalar", domain = "midi_note",
          input = true, output = true },
        { id = "mode", label = "Mode", path = "/midi/synth/rack/note_filter/__template/mode",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum", signalKind = "stepped", domain = "enum_index",
          options = { "Inside", "Outside" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "noteFilterComponent",
      behavior = "ui/behaviors/note_filter.lua",
      componentRef = "ui/components/note_filter.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "attenuverter_bias",
    name = "ATV / Bias",
    validSizes = { "1x1" },
    accentColor = 0xff22d3ee,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "control", label = "CTRL" },
      },
      outputs = {
        { id = "out", type = "control", label = "CTRL" },
      },
      params = {
        { id = "amount", label = "Amount", path = "/midi/synth/rack/attenuverter_bias/__template/amount",
          min = -1.0, max = 1.0, step = 0.01, default = 1.0,
          format = "float", signalKind = "scalar_bipolar", domain = "normalized",
          input = true, output = true },
        { id = "bias", label = "Bias", path = "/midi/synth/rack/attenuverter_bias/__template/bias",
          min = -1.0, max = 1.0, step = 0.01, default = 0.0,
          format = "float", signalKind = "scalar_bipolar", domain = "normalized",
          input = true, output = true },
      },
    },
    meta = {
      componentId = "attenuverterBiasComponent",
      behavior = "ui/behaviors/attenuverter_bias.lua",
      componentRef = "ui/components/attenuverter_bias.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "lfo",
    name = "LFO",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff38bdf8,
    ports = copyPorts {
      inputs = {
        { id = "reset", type = "control", label = "RESET" },
        { id = "sync", type = "control", label = "SYNC" },
      },
      outputs = {
        { id = "out", type = "control", label = "OUT" },
        { id = "inv", type = "control", label = "INV" },
        { id = "uni", type = "control", label = "UNI" },
        { id = "eoc", type = "control", label = "EOC" },
      },
      params = {
        { id = "rate", label = "Rate", path = "/midi/synth/rack/lfo/__template/rate",
          min = 0.01, max = 20, step = 0.01, default = 1.0,
          format = "hz", input = true, output = true },
        { id = "shape", label = "Shape", path = "/midi/synth/rack/lfo/__template/shape",
          min = 0, max = 5, step = 1, default = 0,
          format = "enum",
          options = { "Sine", "Triangle", "Saw", "Square", "S&H", "Noise" },
          input = true, output = true },
        { id = "depth", label = "Depth", path = "/midi/synth/rack/lfo/__template/depth",
          min = 0, max = 1, step = 0.01, default = 1.0,
          format = "percent", input = true, output = true },
        { id = "phase", label = "Phase", path = "/midi/synth/rack/lfo/__template/phase",
          min = 0, max = 360, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "retrig", label = "Retrig", path = "/midi/synth/rack/lfo/__template/retrig",
          min = 0, max = 1, step = 1, default = 1,
          format = "enum", options = { "Off", "On" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "lfoComponent",
      behavior = "ui/behaviors/lfo.lua",
      componentRef = "ui/components/lfo.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "slew",
    name = "Slew",
    validSizes = { "1x1" },
    accentColor = 0xff22d3ee,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "control", label = "CTRL" },
      },
      outputs = {
        { id = "out", type = "control", label = "CTRL" },
      },
      params = {
        { id = "rise", label = "Rise", path = "/midi/synth/rack/slew/__template/rise",
          min = 0, max = 2000, step = 1, default = 0,
          format = "time_ms", input = true, output = true },
        { id = "fall", label = "Fall", path = "/midi/synth/rack/slew/__template/fall",
          min = 0, max = 2000, step = 1, default = 0,
          format = "time_ms", input = true, output = true },
        { id = "shape", label = "Shape", path = "/midi/synth/rack/slew/__template/shape",
          min = 0, max = 2, step = 1, default = 1,
          format = "enum", options = { "Linear", "Log", "Exp" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "slewComponent",
      behavior = "ui/behaviors/slew.lua",
      componentRef = "ui/components/slew.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "sample_hold",
    name = "Sample Hold",
    validSizes = { "1x1" },
    accentColor = 0xfff59e0b,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "control", label = "CTRL" },
        { id = "trig", type = "control", label = "TRIG" },
      },
      outputs = {
        { id = "out", type = "control", label = "CTRL" },
        { id = "inv", type = "control", label = "INV" },
      },
      params = {
        { id = "mode", label = "Mode", path = "/midi/synth/rack/sample_hold/__template/mode",
          min = 0, max = 2, step = 1, default = 0,
          format = "enum", options = { "Sample", "Track", "Step" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "sampleHoldComponent",
      behavior = "ui/behaviors/sample_hold.lua",
      componentRef = "ui/components/sample_hold.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "compare",
    name = "Compare",
    validSizes = { "1x1" },
    accentColor = 0xfff97316,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "control", label = "CTRL" },
      },
      outputs = {
        { id = "gate", type = "control", label = "GATE" },
        { id = "trig", type = "control", label = "TRIG" },
      },
      params = {
        { id = "threshold", label = "Thresh", path = "/midi/synth/rack/compare/__template/threshold",
          min = -1, max = 1, step = 0.01, default = 0,
          format = "float", signalKind = "scalar_bipolar", domain = "normalized",
          input = true, output = true },
        { id = "hysteresis", label = "Hyst", path = "/midi/synth/rack/compare/__template/hysteresis",
          min = 0, max = 0.5, step = 0.01, default = 0.05,
          format = "float", input = true, output = true },
        { id = "direction", label = "Dir", path = "/midi/synth/rack/compare/__template/direction",
          min = 0, max = 2, step = 1, default = 0,
          format = "enum", options = { "Rising", "Falling", "Both" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "compareComponent",
      behavior = "ui/behaviors/compare.lua",
      componentRef = "ui/components/compare.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "cv_mix",
    name = "CV Mix",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xffa855f7,
    ports = copyPorts {
      inputs = {
        { id = "in_1", type = "control", label = "IN1" },
        { id = "in_2", type = "control", label = "IN2" },
        { id = "in_3", type = "control", label = "IN3" },
        { id = "in_4", type = "control", label = "IN4" },
      },
      outputs = {
        { id = "out", type = "control", label = "OUT" },
        { id = "inv", type = "control", label = "INV" },
      },
      params = {
        { id = "level_1", label = "Lvl1", path = "/midi/synth/rack/cv_mix/__template/level_1",
          min = 0, max = 1, step = 0.01, default = 1.0,
          format = "percent", input = true, output = true },
        { id = "level_2", label = "Lvl2", path = "/midi/synth/rack/cv_mix/__template/level_2",
          min = 0, max = 1, step = 0.01, default = 0.0,
          format = "percent", input = true, output = true },
        { id = "level_3", label = "Lvl3", path = "/midi/synth/rack/cv_mix/__template/level_3",
          min = 0, max = 1, step = 0.01, default = 0.0,
          format = "percent", input = true, output = true },
        { id = "level_4", label = "Lvl4", path = "/midi/synth/rack/cv_mix/__template/level_4",
          min = 0, max = 1, step = 0.01, default = 0.0,
          format = "percent", input = true, output = true },
        { id = "offset", label = "Offset", path = "/midi/synth/rack/cv_mix/__template/offset",
          min = -1, max = 1, step = 0.01, default = 0.0,
          format = "float", signalKind = "scalar_bipolar", domain = "normalized",
          input = true, output = true },
      },
    },
    meta = {
      componentId = "cvMixComponent",
      behavior = "ui/behaviors/cv_mix.lua",
      componentRef = "ui/components/cv_mix.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "oscillator",
    name = "Oscillator",
    validSizes = { "1x2", "2x1", "2x2" },
    accentColor = 0xff7dd3fc,
    ports = copyPorts {
      inputs = {
        { id = "voice", type = "control", label = "VOICE" },
        { id = "gate", type = "control", label = "GATE" },
        { id = "v_oct", type = "control", label = "V/OCT" },
        { id = "fm", type = "control", label = "FM" },
        { id = "pw_cv", type = "control", label = "PW" },
        { id = "blend_cv", type = "control", label = "BLEND" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
        { id = "sub", type = "audio", label = "SUB" },
        { id = "analysis", type = "analysis", label = "AN" },
      },
      params = {
        { id = "waveform", label = "Wave", path = "/midi/synth/waveform",
          min = 0, max = 7, step = 1, default = 1,
          format = "enum",
          options = { "Sine", "Saw", "Sqr", "Tri", "Blend", "Noise", "Pulse", "SSaw" },
          input = true, output = true },
        { id = "render_mode", label = "Render", path = "/midi/synth/osc/renderMode",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Std", "Add" },
          input = true, output = true },
        { id = "add_partials", label = "Parts", path = "/midi/synth/osc/add/partials",
          min = 1, max = 32, step = 1, default = 8,
          format = "int", input = true, output = true },
        { id = "add_tilt", label = "Tilt", path = "/midi/synth/osc/add/tilt",
          min = -1, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "add_drift", label = "Drift", path = "/midi/synth/osc/add/drift",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "drive", label = "Drive", path = "/midi/synth/drive",
          min = 0, max = 20, step = 0.1, default = 0.0,
          input = true, output = true },
        { id = "drive_shape", label = "Shape", path = "/midi/synth/driveShape",
          min = 0, max = 3, step = 1, default = 0,
          format = "enum",
          options = { "Soft", "Hard", "Clip", "Fold" },
          input = true, output = true },
        { id = "drive_bias", label = "Bias", path = "/midi/synth/driveBias",
          min = -1, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "pulse_width", label = "Width", path = "/midi/synth/pulseWidth",
          min = 0.01, max = 0.99, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "unison", label = "Unison", path = "/midi/synth/unison",
          min = 1, max = 8, step = 1, default = 1,
          format = "int", input = true, output = true },
        { id = "detune", label = "Detune", path = "/midi/synth/detune",
          min = 0, max = 100, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "spread", label = "Spread", path = "/midi/synth/spread",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "blend_amount", label = "Blend", path = "/midi/synth/blend/amount",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "output", label = "Output", path = "/midi/synth/output",
          min = 0, max = 2, step = 0.01, default = 0.8,
          input = true, output = true },
        -- Sample tab params
        { id = "sample_source", label = "Source", path = "/midi/synth/sample/source",
          min = 0, max = 4, step = 1, default = 0,
          format = "enum",
          options = { "Live", "Layer 1", "Layer 2", "Layer 3", "Layer 4" },
          input = true, output = true },
        { id = "sample_bars", label = "Bars", path = "/midi/synth/sample/captureBars",
          min = 0.0625, max = 16, step = 0.0625, default = 1,
          input = true, output = true },
        { id = "sample_root", label = "Root", path = "/midi/synth/sample/rootNote",
          min = 12, max = 96, step = 1, default = 60,
          format = "int", input = true, output = true },
        { id = "sample_pitch_map", label = "PMap", path = "/midi/synth/sample/pitchMapEnabled",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Off", "On" },
          input = true, output = true },
        { id = "sample_start", label = "Start", path = "/midi/synth/sample/loopStart",
          min = 0, max = 95, step = 1, default = 0,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.95 } },
        { id = "sample_play_start", label = "Play", path = "/midi/synth/sample/playStart",
          min = 0, max = 99, step = 1, default = 0,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.99 } },
        { id = "sample_len", label = "Length", path = "/midi/synth/sample/loopLen",
          min = 5, max = 100, step = 1, default = 100,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.05, dspMax = 1.0 } },
        { id = "sample_xfade", label = "X-Fade", path = "/midi/synth/sample/crossfade",
          min = 0, max = 50, step = 1, default = 10,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.5 } },
        { id = "sample_retrigger", label = "Retrig", path = "/midi/synth/sample/retrigger",
          min = 0, max = 1, step = 1, default = 1,
          format = "enum",
          options = { "Off", "On" },
          input = true, output = true },
        { id = "sample_capture", label = "Capture", path = "/midi/synth/sample/captureTrigger",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Idle", "Trig" },
          input = true, output = false },
        -- Blend tab params
        { id = "blend_mode", label = "Mode", path = "/midi/synth/blend/mode",
          min = 0, max = 5, step = 1, default = 0,
          format = "enum",
          options = { "Mix", "Ring", "FM", "Sync", "Add", "Morph" },
          input = true, output = true },
        { id = "blend_key_track", label = "KeyTrk", path = "/midi/synth/blend/keyTrack",
          min = 0, max = 2, step = 1, default = 2,
          format = "enum",
          options = { "Wave", "Sample", "Both" },
          input = true, output = true },
        { id = "blend_sample_pitch", label = "Pitch", path = "/midi/synth/blend/samplePitch",
          min = -24, max = 24, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "blend_mod_amount", label = "Depth", path = "/midi/synth/blend/modAmount",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "blend_env_follow", label = "EnvF", path = "/midi/synth/blend/envFollow",
          min = 0, max = 1, step = 0.01, default = 1.0,
          format = "percent",
          input = true, output = true },
        { id = "blend_add_flavor", label = "AddSrc", path = "/midi/synth/blend/addFlavor",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Self", "Driven" },
          input = true, output = true },
        { id = "morph_curve", label = "Curve", path = "/midi/synth/blend/morphCurve",
          min = 0, max = 2, step = 1, default = 2,
          format = "enum",
          options = { "Linear", "S-Curve", "EqPwr" },
          input = true, output = true },
        { id = "morph_convergence", label = "Stretch", path = "/midi/synth/blend/morphConvergence",
          min = 0, max = 1, step = 0.01, default = 0,
          format = "percent",
          input = true, output = true },
        { id = "morph_phase", label = "Tilt", path = "/midi/synth/blend/morphPhase",
          min = 0, max = 2, step = 1, default = 0,
          format = "enum",
          options = { "Neutral", "Bright", "Dark" },
          input = true, output = true },
        { id = "morph_speed", label = "Speed", path = "/midi/synth/blend/morphSpeed",
          min = 0.1, max = 4.0, step = 0.1, default = 1.0,
          format = "float",
          input = true, output = true },
        { id = "morph_contrast", label = "Contrast", path = "/midi/synth/blend/morphContrast",
          min = 0, max = 2, step = 0.01, default = 0.5,
          format = "float",
          input = true, output = true },
        { id = "morph_smooth", label = "Smooth", path = "/midi/synth/blend/morphSmooth",
          min = 0, max = 1, step = 0.01, default = 0.0,
          format = "percent",
          input = true, output = true },
      },
    },
    meta = {
      componentId = "oscillatorComponent",
      behavior = "ui/behaviors/source_panel.lua",
      componentRef = "ui/components/source_panel.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "rack_oscillator",
    name = "Rack Oscillator",
    validSizes = { "1x2", "2x1", "2x2" },
    accentColor = 0xff7dd3fc,
    ports = copyPorts {
      inputs = {
        { id = "voice", type = "control", label = "VOICE" },
        { id = "gate", type = "control", label = "GATE" },
        { id = "v_oct", type = "control", label = "V/OCT" },
        { id = "fm", type = "control", label = "FM" },
        { id = "pw_cv", type = "control", label = "PW" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
        { id = "sub", type = "audio", label = "SUB" },
        { id = "analysis", type = "analysis", label = "AN" },
      },
      params = {
        { id = "waveform", label = "Wave", path = "/midi/synth/waveform",
          min = 0, max = 7, step = 1, default = 1,
          format = "enum",
          options = { "Sine", "Saw", "Sqr", "Tri", "Blend", "Noise", "Pulse", "SSaw" },
          input = true, output = true },
        { id = "render_mode", label = "Render", path = "/midi/synth/osc/renderMode",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Std", "Add" },
          input = true, output = true },
        { id = "add_partials", label = "Parts", path = "/midi/synth/osc/add/partials",
          min = 1, max = 32, step = 1, default = 8,
          format = "int", input = true, output = true },
        { id = "add_tilt", label = "Tilt", path = "/midi/synth/osc/add/tilt",
          min = -1, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "add_drift", label = "Drift", path = "/midi/synth/osc/add/drift",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "drive", label = "Drive", path = "/midi/synth/drive",
          min = 0, max = 20, step = 0.1, default = 0.0,
          input = true, output = true },
        { id = "drive_shape", label = "Shape", path = "/midi/synth/driveShape",
          min = 0, max = 3, step = 1, default = 0,
          format = "enum",
          options = { "Soft", "Hard", "Clip", "Fold" },
          input = true, output = true },
        { id = "drive_bias", label = "Bias", path = "/midi/synth/driveBias",
          min = -1, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "pulse_width", label = "Width", path = "/midi/synth/pulseWidth",
          min = 0.01, max = 0.99, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "unison", label = "Unison", path = "/midi/synth/unison",
          min = 1, max = 8, step = 1, default = 1,
          format = "int", input = true, output = true },
        { id = "detune", label = "Detune", path = "/midi/synth/detune",
          min = 0, max = 100, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "spread", label = "Spread", path = "/midi/synth/spread",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "manual_pitch", label = "Pitch", path = "/midi/synth/rack/osc/manualPitch",
          min = 0, max = 127, step = 1, default = 60,
          format = "int", input = true, output = true },
        { id = "manual_level", label = "Level", path = "/midi/synth/rack/osc/manualLevel",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "output", label = "Output", path = "/midi/synth/rack/osc/output",
          min = 0, max = 2, step = 0.01, default = 0.8,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "rackOscillatorComponent",
      behavior = "ui/behaviors/rack_oscillator.lua",
      componentRef = "ui/components/rack_oscillator.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "rack_sample",
    name = "Rack Sample",
    validSizes = { "1x2", "2x1", "2x2" },
    accentColor = 0xff22d3ee,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN", auxiliary = true, audioRole = "capture" },
        { id = "voice", type = "control", label = "VOICE" },
        { id = "gate", type = "control", label = "GATE" },
        { id = "v_oct", type = "control", label = "V/OCT" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
        { id = "analysis", type = "analysis", label = "AN" },
      },
      params = {
        { id = "source", label = "Source", path = "/midi/synth/sample/source",
          min = 0, max = 5, step = 1, default = 1,
          format = "enum",
          options = { "Input", "Live", "Layer 1", "Layer 2", "Layer 3", "Layer 4" },
          input = true, output = true },
        { id = "capture_mode", label = "Capture", path = "/midi/synth/sample/captureMode",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Retro", "Free" },
          input = true, output = true },
        { id = "capture", label = "Capture", path = "/midi/synth/sample/captureTrigger",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Idle", "Trig" },
          input = true, output = false },
        { id = "bars", label = "Bars", path = "/midi/synth/sample/captureBars",
          min = 0.0625, max = 16, step = 0.0625, default = 1.0,
          input = true, output = true },
        { id = "pitch_map", label = "PMap", path = "/midi/synth/sample/pitchMapEnabled",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Off", "On" },
          input = true, output = true },
        { id = "pitch_mode", label = "Pitch", path = "/midi/synth/sample/pitchMode",
          min = 0, max = 2, step = 1, default = 0,
          format = "enum",
          options = { "Classic", "PVoc", "HQ" },
          input = true, output = true },
        { id = "root", label = "Root", path = "/midi/synth/sample/rootNote",
          min = 12, max = 96, step = 1, default = 60,
          format = "int", input = true, output = true },
        { id = "unison", label = "Unison", path = "/midi/synth/unison",
          min = 1, max = 8, step = 1, default = 1,
          format = "int", input = true, output = true },
        { id = "detune", label = "Detune", path = "/midi/synth/detune",
          min = 0, max = 100, step = 1, default = 0,
          format = "int", input = true, output = true },
        { id = "spread", label = "Spread", path = "/midi/synth/spread",
          min = 0, max = 1, step = 0.01, default = 0,
          format = "float", input = true, output = true },
        { id = "play_start", label = "Play", path = "/midi/synth/sample/playStart",
          min = 0, max = 99, step = 1, default = 0,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.99 } },
        { id = "loop_start", label = "Start", path = "/midi/synth/sample/loopStart",
          min = 0, max = 95, step = 1, default = 0,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.95 } },
        { id = "loop_len", label = "Length", path = "/midi/synth/sample/loopLen",
          min = 5, max = 100, step = 1, default = 100,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.05, dspMax = 1.0 } },
        { id = "crossfade", label = "X-Fade", path = "/midi/synth/sample/crossfade",
          min = 0, max = 50, step = 1, default = 10,
          format = "int", input = true, output = true,
          scale = { dspMin = 0.0, dspMax = 0.5 } },
        { id = "retrigger", label = "Retrig", path = "/midi/synth/sample/retrigger",
          min = 0, max = 1, step = 1, default = 1,
          format = "enum",
          options = { "Off", "On" },
          input = true, output = true },
        { id = "pvoc_fft", label = "FFT", path = "/midi/synth/sample/pvoc/fftOrder",
          min = 9, max = 12, step = 1, default = 11,
          format = "int", input = true, output = true },
        { id = "pvoc_stretch", label = "Stretch", path = "/midi/synth/sample/pvoc/timeStretch",
          min = 0.25, max = 4.0, step = 0.25, default = 1.0,
          format = "float", input = true, output = true },
        { id = "output", label = "Output", path = "/midi/synth/output",
          min = 0, max = 2, step = 0.01, default = 0.8,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "rackSampleComponent",
      behavior = "ui/behaviors/rack_sample.lua",
      componentRef = "ui/components/rack_sample.ui.lua",
      audioSource = true,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "blend_simple",
    name = "Blend",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xfff97316,
    ports = copyPorts {
      inputs = {
        { id = "a", type = "audio", label = "A" },
        { id = "b", type = "audio", label = "B", auxiliary = true, audioRole = "blend_b" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
      params = {
        { id = "mode", label = "Mode", path = "/midi/synth/rack/blend_simple/__template/mode",
          min = 0, max = 3, step = 1, default = 0,
          format = "enum",
          options = { "Mix", "Ring", "FM", "Sync" },
          input = true, output = true },
        { id = "blendAmount", label = "Blend", path = "/midi/synth/rack/blend_simple/__template/blendAmount",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "blendModAmount", label = "Depth", path = "/midi/synth/rack/blend_simple/__template/blendModAmount",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "output", label = "Output", path = "/midi/synth/rack/blend_simple/__template/output",
          min = 0, max = 1, step = 0.01, default = 1.0,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "rackBlendSimpleComponent",
      behavior = "ui/behaviors/rack_blend_simple.lua",
      componentRef = "ui/components/rack_blend_simple.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "filter",
    name = "Filter",
    validSizes = { "1x1", "1x2", "2x1", "2x2" },
    accentColor = 0xffa78bfa,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
        { id = "env", type = "control", label = "ENV" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
        { id = "send", type = "audio", label = "SEND", edge = "right" },
      },
      params = {
        { id = "type", label = "Type", path = "/midi/synth/filterType",
          min = 0, max = 3, step = 1, default = 0,
          format = "enum",
          options = { "SVF LP", "SVF BP", "SVF HP", "SVF Notch" },
          input = true, output = true },
        { id = "cutoff", label = "Cutoff", path = "/midi/synth/cutoff",
          min = 80, max = 16000, step = 1, default = 3200,
          format = "freq", input = true, output = true },
        { id = "resonance", label = "Reso", path = "/midi/synth/resonance",
          min = 0.1, max = 2.0, step = 0.01, default = 0.75,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "filterComponent",
      behavior = "ui/behaviors/filter.lua",
      componentRef = "ui/components/filter.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "fx1",
    name = "FX1",
    validSizes = { "1x1", "1x2", "2x1", "2x2" },
    accentColor = 0xffa855f7,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
        { id = "recv", type = "audio", label = "RECV", edge = "left" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
      params = {
        { id = "type", label = "Type", path = "/midi/synth/fx1/type",
          min = 0, max = 20, step = 1, default = 0,
          format = "enum",
          options = { "Chorus", "Phaser", "WvShp", "Comp", "Widen", "Filt", "SVF", "Verb", "SDly", "MTap", "Pitch", "Gran", "Ring", "Fmnt", "EQ", "Limit", "Trans", "BitCr", "Shim", "RevDly", "Stut" },
          input = true, output = true },
        { id = "mix", label = "Mix", path = "/midi/synth/fx1/mix",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "p0", label = "P1", path = "/midi/synth/fx1/p/0",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p1", label = "P2", path = "/midi/synth/fx1/p/1",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p2", label = "P3", path = "/midi/synth/fx1/p/2",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p3", label = "P4", path = "/midi/synth/fx1/p/3",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p4", label = "P5", path = "/midi/synth/fx1/p/4",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "fx1Component",
      behavior = "ui/behaviors/fx_slot.lua",
      componentRef = "ui/components/fx_slot.ui.lua",
      slot = 1,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "fx2",
    name = "FX2",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff3b82f6,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
      params = {
        { id = "type", label = "Type", path = "/midi/synth/fx2/type",
          min = 0, max = 20, step = 1, default = 0,
          format = "enum",
          options = { "Chorus", "Phaser", "WvShp", "Comp", "Widen", "Filt", "SVF", "Verb", "SDly", "MTap", "Pitch", "Gran", "Ring", "Fmnt", "EQ", "Limit", "Trans", "BitCr", "Shim", "RevDly", "Stut" },
          input = true, output = true },
        { id = "mix", label = "Mix", path = "/midi/synth/fx2/mix",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "p0", label = "P1", path = "/midi/synth/fx2/p/0",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p1", label = "P2", path = "/midi/synth/fx2/p/1",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p2", label = "P3", path = "/midi/synth/fx2/p/2",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p3", label = "P4", path = "/midi/synth/fx2/p/3",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
        { id = "p4", label = "P5", path = "/midi/synth/fx2/p/4",
          min = 0, max = 1, step = 0.01, default = 0.5,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "fx2Component",
      behavior = "ui/behaviors/fx_slot.lua",
      componentRef = "ui/components/fx_slot.ui.lua",
      slot = 2,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "eq",
    name = "EQ8",
    validSizes = { "1x1", "1x2", "2x1" },
    accentColor = 0xff22d3ee,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
      params = {
        { id = "output", label = "Output", path = "/midi/synth/eq8/output",
          min = -12, max = 12, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "mix", label = "Mix", path = "/midi/synth/eq8/mix",
          min = 0, max = 1, step = 0.01, default = 1.0,
          input = true, output = true },
        { id = "b1_freq", label = "B1 Freq", path = "/midi/synth/eq8/band/1/freq",
          min = 20, max = 20000, step = 1, default = 60,
          format = "freq", input = true, output = true },
        { id = "b1_gain", label = "B1 Gain", path = "/midi/synth/eq8/band/1/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b1_q", label = "B1 Q", path = "/midi/synth/eq8/band/1/q",
          min = 0.1, max = 10, step = 0.1, default = 0.8,
          input = true, output = true },
        { id = "b2_freq", label = "B2 Freq", path = "/midi/synth/eq8/band/2/freq",
          min = 20, max = 20000, step = 1, default = 120,
          format = "freq", input = true, output = true },
        { id = "b2_gain", label = "B2 Gain", path = "/midi/synth/eq8/band/2/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b2_q", label = "B2 Q", path = "/midi/synth/eq8/band/2/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b3_freq", label = "B3 Freq", path = "/midi/synth/eq8/band/3/freq",
          min = 20, max = 20000, step = 1, default = 250,
          format = "freq", input = true, output = true },
        { id = "b3_gain", label = "B3 Gain", path = "/midi/synth/eq8/band/3/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b3_q", label = "B3 Q", path = "/midi/synth/eq8/band/3/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b4_freq", label = "B4 Freq", path = "/midi/synth/eq8/band/4/freq",
          min = 20, max = 20000, step = 1, default = 500,
          format = "freq", input = true, output = true },
        { id = "b4_gain", label = "B4 Gain", path = "/midi/synth/eq8/band/4/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b4_q", label = "B4 Q", path = "/midi/synth/eq8/band/4/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b5_freq", label = "B5 Freq", path = "/midi/synth/eq8/band/5/freq",
          min = 20, max = 20000, step = 1, default = 1000,
          format = "freq", input = true, output = true },
        { id = "b5_gain", label = "B5 Gain", path = "/midi/synth/eq8/band/5/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b5_q", label = "B5 Q", path = "/midi/synth/eq8/band/5/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b6_freq", label = "B6 Freq", path = "/midi/synth/eq8/band/6/freq",
          min = 20, max = 20000, step = 1, default = 2500,
          format = "freq", input = true, output = true },
        { id = "b6_gain", label = "B6 Gain", path = "/midi/synth/eq8/band/6/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b6_q", label = "B6 Q", path = "/midi/synth/eq8/band/6/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b7_freq", label = "B7 Freq", path = "/midi/synth/eq8/band/7/freq",
          min = 20, max = 20000, step = 1, default = 6000,
          format = "freq", input = true, output = true },
        { id = "b7_gain", label = "B7 Gain", path = "/midi/synth/eq8/band/7/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b7_q", label = "B7 Q", path = "/midi/synth/eq8/band/7/q",
          min = 0.1, max = 10, step = 0.1, default = 1.0,
          input = true, output = true },
        { id = "b8_freq", label = "B8 Freq", path = "/midi/synth/eq8/band/8/freq",
          min = 20, max = 20000, step = 1, default = 12000,
          format = "freq", input = true, output = true },
        { id = "b8_gain", label = "B8 Gain", path = "/midi/synth/eq8/band/8/gain",
          min = -18, max = 18, step = 0.1, default = 0,
          format = "db", input = true, output = true },
        { id = "b8_q", label = "B8 Q", path = "/midi/synth/eq8/band/8/q",
          min = 0.1, max = 10, step = 0.1, default = 0.8,
          input = true, output = true },
      },
    },
    meta = {
      componentId = "eqComponent",
      behavior = "ui/behaviors/eq.lua",
      componentRef = "ui/components/eq.ui.lua",
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "placeholder1",
    name = "Placeholder 1",
    validSizes = { "1x1", "1x2" },
    accentColor = 0xff64748b,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
    },
    meta = {
      componentId = "placeholder1Content",
      componentRef = "ui/components/placeholder.ui.lua",
      audioPassthrough = true,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "placeholder2",
    name = "Placeholder 2",
    validSizes = { "1x1", "1x2" },
    accentColor = 0xff64748b,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
    },
    meta = {
      componentId = "placeholder2Content",
      componentRef = "ui/components/placeholder.ui.lua",
      audioPassthrough = true,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "placeholder3",
    name = "Placeholder 3",
    validSizes = { "1x1", "1x2" },
    accentColor = 0xff64748b,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "audio", label = "IN" },
      },
      outputs = {
        { id = "out", type = "audio", label = "OUT" },
      },
    },
    meta = {
      componentId = "placeholder3Content",
      componentRef = "ui/components/placeholder.ui.lua",
      audioPassthrough = true,
    },
  },
  RackLayout.makeRackModuleSpec {
    id = "range_mapper",
    name = "Range",
    validSizes = { "1x1" },
    accentColor = 0xffa855f7,
    ports = copyPorts {
      inputs = {
        { id = "in", type = "control", label = "CTRL", signalKind = "scalar_unipolar", domain = "normalized" },
      },
      outputs = {
        { id = "out", type = "control", label = "CTRL", signalKind = "scalar_unipolar", domain = "normalized" },
      },
      params = {
        { id = "min", label = "Min", path = "/midi/synth/rack/range_mapper/__template/min",
          min = 0, max = 1, step = 0.01, default = 0,
          input = true, output = true },
        { id = "max", label = "Max", path = "/midi/synth/rack/range_mapper/__template/max",
          min = 0, max = 1, step = 0.01, default = 1,
          input = true, output = true },
        { id = "mode", label = "Mode", path = "/midi/synth/rack/range_mapper/__template/mode",
          min = 0, max = 1, step = 1, default = 0,
          format = "enum",
          options = { "Clamp", "Remap" },
          input = true, output = true },
      },
    },
    meta = {
      componentId = "rangeMapperComponent",
      behavior = "ui/behaviors/range_mapper.lua",
      componentRef = "ui/components/range_mapper.ui.lua",
    },
  },
}

function M.rackModuleSpecs()
  local out = {}
  for i = 1, #RACK_MODULE_SPECS do
    out[i] = normalizeModuleSpec(RackLayout.makeRackModuleSpec(RACK_MODULE_SPECS[i]))
  end
  return out
end

function M.rackModuleSpecById()
  local out = {}
  local specs = M.rackModuleSpecs()
  for i = 1, #specs do
    out[specs[i].id] = specs[i]
  end
  if out.placeholder1 then
    local placeholder = normalizeModuleSpec(RackLayout.makeRackModuleSpec(out.placeholder1))
    placeholder.id = "placeholder"
    placeholder.name = "Placeholder"
    placeholder.meta = placeholder.meta or {}
    placeholder.meta.componentId = "contentComponent"
    placeholder.meta.palette = deepCopy(placeholder.meta.palette or {})
    placeholder.meta.palette.displayName = "Slot"
    out.placeholder = normalizeModuleSpec(placeholder)
  end
  if out.fx1 then
    local fx = normalizeModuleSpec(RackLayout.makeRackModuleSpec(out.fx1))
    fx.id = "fx"
    fx.name = "FX"
    fx.meta = fx.meta or {}
    fx.meta.slot = nil
    fx.meta.componentId = tostring(fx.meta.componentId or "fx1Component")
    fx.meta.instancePolicy = "canonical_or_dynamic"
    fx.meta.paramTemplateMode = "dynamic_slot_remap"
    fx.meta.description = MODULE_META_DEFAULTS.fx.description
    fx.meta.palette = deepCopy(fx.meta.palette or {})
    fx.meta.palette.displayName = "FX"
    fx.meta.palette.portSummary = MODULE_META_DEFAULTS.fx.palette.portSummary
    out.fx = normalizeModuleSpec(fx)
  end
  local dynamicSpecs = type(_G) == "table" and _G.__midiSynthDynamicModuleSpecs or nil
  if type(dynamicSpecs) == "table" then
    for moduleId, spec in pairs(dynamicSpecs) do
      if type(spec) == "table" then
        out[tostring(moduleId)] = normalizeModuleSpec(RackLayout.makeRackModuleSpec(spec))
      end
    end
  end
  return out
end

local DELETABLE_NODE_IDS = {
  adsr = true,
  filter = true,
  fx1 = true,
  fx2 = true,
  eq = true,
  placeholder1 = true,
  placeholder2 = true,
  placeholder3 = true,
  range_mapper = true,
}

function M.isRackModuleDeletable(moduleId)
  local id = tostring(moduleId or "")
  if DELETABLE_NODE_IDS[id] == true then
    return true
  end
  local dynamicSpecs = type(_G) == "table" and _G.__midiSynthDynamicModuleSpecs or nil
  return type(dynamicSpecs) == "table" and dynamicSpecs[id] ~= nil
end

function M.paletteEntryTemplateById()
  local out = {}
  local specs = M.rackModuleSpecById()
  for specId, spec in pairs(specs) do
    local meta = type(spec) == "table" and spec.meta or {}
    local palette = type(meta) == "table" and meta.palette or {}
    out[tostring(specId)] = {
      specId = tostring(specId),
      category = tostring(meta and meta.category or "utility"),
      accentColor = spec and spec.accentColor or nil,
      displayName = tostring(palette and palette.displayName or spec and spec.name or specId),
      description = tostring(palette and palette.description or meta and meta.description or ""),
      portSummary = tostring(palette and palette.portSummary or ""),
      order = math.max(0, math.floor(tonumber(palette and palette.order or 999) or 999)),
      componentId = tostring(meta and meta.componentId or "contentComponent"),
      instancePolicy = tostring(meta and meta.instancePolicy or "manual"),
      runtimeKind = tostring(meta and meta.runtimeKind or "processor"),
      paramTemplateMode = tostring(meta and meta.paramTemplateMode or "absolute"),
    }
  end
  return out
end

M.EQ_ROUTE_BROKEN = 0
M.EQ_ROUTE_INSERTED = 1
M.EQ_ROUTE_BYPASSED = 2
M.MIDI_INPUT_NODE_ID = "__midiInput"
M.OUTPUT_NODE_ID = "__rackOutput"
M.OUTPUT_PORT_ID = "main"

local AUDIO_ROUTE_EDGE_ORDER = {
  { fromModuleId = "oscillator", fromPortId = "out", toModuleId = "filter", toPortId = "in" },
  { fromModuleId = "oscillator", fromPortId = "out", toModuleId = "fx1", toPortId = "in" },
  { fromModuleId = "oscillator", fromPortId = "out", toModuleId = "fx2", toPortId = "in" },
  { fromModuleId = "oscillator", fromPortId = "out", toModuleId = "eq", toPortId = "in" },
  { fromModuleId = "oscillator", fromPortId = "out", toModuleId = M.OUTPUT_NODE_ID, toPortId = M.OUTPUT_PORT_ID },
  { fromModuleId = "filter", fromPortId = "out", toModuleId = "fx1", toPortId = "in" },
  { fromModuleId = "filter", fromPortId = "out", toModuleId = "fx2", toPortId = "in" },
  { fromModuleId = "filter", fromPortId = "out", toModuleId = "eq", toPortId = "in" },
  { fromModuleId = "filter", fromPortId = "out", toModuleId = M.OUTPUT_NODE_ID, toPortId = M.OUTPUT_PORT_ID },
  { fromModuleId = "fx1", fromPortId = "out", toModuleId = "filter", toPortId = "in" },
  { fromModuleId = "fx1", fromPortId = "out", toModuleId = "fx2", toPortId = "in" },
  { fromModuleId = "fx1", fromPortId = "out", toModuleId = "eq", toPortId = "in" },
  { fromModuleId = "fx1", fromPortId = "out", toModuleId = M.OUTPUT_NODE_ID, toPortId = M.OUTPUT_PORT_ID },
  { fromModuleId = "fx2", fromPortId = "out", toModuleId = "filter", toPortId = "in" },
  { fromModuleId = "fx2", fromPortId = "out", toModuleId = "fx1", toPortId = "in" },
  { fromModuleId = "fx2", fromPortId = "out", toModuleId = "eq", toPortId = "in" },
  { fromModuleId = "fx2", fromPortId = "out", toModuleId = M.OUTPUT_NODE_ID, toPortId = M.OUTPUT_PORT_ID },
  { fromModuleId = "eq", fromPortId = "out", toModuleId = "filter", toPortId = "in" },
  { fromModuleId = "eq", fromPortId = "out", toModuleId = "fx1", toPortId = "in" },
  { fromModuleId = "eq", fromPortId = "out", toModuleId = "fx2", toPortId = "in" },
  { fromModuleId = "eq", fromPortId = "out", toModuleId = M.OUTPUT_NODE_ID, toPortId = M.OUTPUT_PORT_ID },
}

local AUDIO_ROUTE_EDGE_INDEX = {}
for i = 1, #AUDIO_ROUTE_EDGE_ORDER do
  local edge = AUDIO_ROUTE_EDGE_ORDER[i]
  local key = table.concat({ edge.fromModuleId, edge.fromPortId, edge.toModuleId, edge.toPortId }, ":")
  AUDIO_ROUTE_EDGE_INDEX[key] = i - 1
end

M.AUDIO_ROUTE_EDGE_ORDER = AUDIO_ROUTE_EDGE_ORDER

local function makeConnection(id, kind, fromModuleId, fromPortId, toModuleId, toPortId, meta)
  return RackLayout.makeRackConnection {
    id = id,
    kind = kind,
    from = { moduleId = fromModuleId, portId = fromPortId },
    to = { moduleId = toModuleId, portId = toPortId },
    meta = meta or {},
  }
end

local function moduleRow(modules, moduleId)
  if type(nodes) ~= "table" then
    return nil
  end
  for i = 1, #nodes do
    local node = nodes[i]
    if node and node.id == nodeId then
      return math.max(0, math.floor(tonumber(node.row) or 0))
    end
  end
  return nil
end

local function isRowWrapNeighbor(modules, fromModuleId, toModuleId)
  local ordered = RackLayout.getFlowModules(type(modules) == "table" and modules or {})
  local filtered = {}
  for i = 1, #ordered do
    local module = ordered[i]
    if module and module.id ~= "adsr" then
      filtered[#filtered + 1] = module
    end
  end

  for i = 1, #filtered - 1 do
    local a = filtered[i]
    local b = filtered[i + 1]
    if a and b and a.id == fromModuleId and b.id == toModuleId then
      local fromRow = math.max(0, math.floor(tonumber(a.row) or 0))
      local toRow = math.max(0, math.floor(tonumber(b.row) or 0))
      return fromRow ~= toRow
    end
  end

  return false
end

local function decorateAudioMeta(modules, fromModuleId, toModuleId, extraMeta)
  local meta = type(extraMeta) == "table" and deepCopy(extraMeta) or {}

  if toModuleId == M.OUTPUT_NODE_ID then
    meta.route = "output"
  elseif isRowWrapNeighbor(modules, fromModuleId, toModuleId) then
    meta.route = "relay"
  else
    meta.route = nil
  end

  return meta
end

local function canonicalAudioConnection(modules, id)
  if id == "oscillator_to_filter" then
    return makeConnection(id, "audio", "oscillator", "out", "filter", "in", decorateAudioMeta(nodes, "oscillator", "filter", {
      source = "fixed-dsp-chain",
    }))
  elseif id == "filter_to_fx1" then
    return makeConnection(id, "audio", "filter", "out", "fx1", "in", decorateAudioMeta(nodes, "filter", "fx1", {
      source = "fixed-dsp-chain",
    }))
  elseif id == "fx1_to_fx2" then
    return makeConnection(id, "audio", "fx1", "out", "fx2", "in", decorateAudioMeta(nodes, "fx1", "fx2", {
      source = "fixed-dsp-chain",
    }))
  elseif id == "fx2_to_eq" then
    return makeConnection(id, "audio", "fx2", "out", "eq", "in", decorateAudioMeta(nodes, "fx2", "eq", {
      source = "fixed-dsp-chain",
    }))
  elseif id == "eq_to_output" then
    return makeConnection(id, "audio", "eq", "out", M.OUTPUT_NODE_ID, M.OUTPUT_PORT_ID, decorateAudioMeta(nodes, "eq", M.OUTPUT_NODE_ID, {
      source = "fixed-dsp-chain",
    }))
  elseif id == "fx2_to_output" then
    return makeConnection(id, "audio", "fx2", "out", M.OUTPUT_NODE_ID, M.OUTPUT_PORT_ID, decorateAudioMeta(nodes, "fx2", M.OUTPUT_NODE_ID, {
      source = "fixed-dsp-chain",
    }))
  end
  return nil
end

local function isAllowedNonAudioConnection(conn)
  return type(conn) == "table" and tostring(conn.kind or "") ~= "audio"
end

local function buildModuleIdSet(modules)
  local out = {}
  if type(modules) ~= "table" then
    return out
  end
  for i = 1, #modules do
    local module = modules[i]
    local moduleId = module and tostring(module.id or "") or ""
    if moduleId ~= "" then
      out[moduleId] = true
    end
  end
  return out
end

local function endpointModuleExists(moduleIdSet, moduleId)
  local id = tostring(moduleId or "")
  return id == "__rackRail" or id == M.MIDI_INPUT_NODE_ID or id == M.OUTPUT_NODE_ID or moduleIdSet[id] == true
end

local function connectionEndpointsExist(moduleIdSet, conn)
  local from = type(conn) == "table" and conn.from or nil
  local to = type(conn) == "table" and conn.to or nil
  return type(from) == "table"
    and type(to) == "table"
    and endpointModuleExists(moduleIdSet, from.moduleId)
    and endpointModuleExists(moduleIdSet, to.moduleId)
end

local function isRailOutputTarget(conn)
  local to = type(conn) == "table" and conn.to or nil
  return type(to) == "table"
    and tostring(to.moduleId or "") == "__rackRail"
    and tostring(to.portId or ""):match("^send_row%d+$") ~= nil
end

local function hasConnectionId(connections, id)
  if type(connections) ~= "table" then
    return false
  end
  for i = 1, #connections do
    local conn = connections[i]
    if conn and conn.id == id then
      return true
    end
  end
  return false
end

local firstAudioPortId

local function isGenericAudioEndpoint(moduleId, portId, direction)
  local id = tostring(moduleId or "")
  local pid = tostring(portId or "")
  if id == M.OUTPUT_NODE_ID then
    return direction == "input" and pid == M.OUTPUT_PORT_ID
  end
  if id == "__rackRail" then
    if direction == "input" then
      return pid:match("^recv_row%d+$") ~= nil
    end
    return pid:match("^send_row%d+$") ~= nil
  end
  local expected = firstAudioPortId(id, direction)
  return expected ~= nil and pid == expected
end

local function hasConnectionEndpoints(connections, kind, fromModuleId, fromPortId, toModuleId, toPortId)
  if type(connections) ~= "table" then
    return false
  end
  for i = 1, #connections do
    local conn = connections[i]
    local from = type(conn) == "table" and conn.from or nil
    local to = type(conn) == "table" and conn.to or nil
    if tostring(conn and conn.kind or "") == tostring(kind or "")
      and type(from) == "table"
      and type(to) == "table"
      and tostring(from.moduleId or "") == tostring(fromModuleId or "")
      and tostring(from.portId or "") == tostring(fromPortId or "")
      and tostring(to.moduleId or "") == tostring(toModuleId or "")
      and tostring(to.portId or "") == tostring(toPortId or "") then
      return true
    end
  end
  return false
end

local function buildFlowOrder(modules)
  local ordered = RackLayout.getFlowModules(type(modules) == "table" and modules or {})
  local order = {}
  local index = 0
  for i = 1, #ordered do
    local module = ordered[i]
    if module and module.id ~= "adsr" then
      index = index + 1
      order[module.id] = index
    end
  end
  return order, index
end

local function canonicalizeAudioEndpoint(conn, isTarget)
  local endpoint = isTarget and conn.to or conn.from
  if type(endpoint) ~= "table" then
    return nil
  end
  local moduleId = tostring(endpoint.moduleId or "")
  local portId = tostring(endpoint.portId or "")
  if isTarget and (moduleId == M.OUTPUT_NODE_ID or isRailOutputTarget(conn)) then
    return {
      moduleId = M.OUTPUT_NODE_ID,
      portId = M.OUTPUT_PORT_ID,
    }
  end
  if moduleId == "__rackRail" then
    return nil
  end
  return {
    moduleId = moduleId,
    portId = portId,
  }
end

local function rawAudioEndpoint(conn, isTarget)
  local endpoint = isTarget and conn.to or conn.from
  if type(endpoint) ~= "table" then
    return nil
  end

  local moduleId = tostring(endpoint.moduleId or "")
  local portId = tostring(endpoint.portId or "")
  if moduleId == "" or portId == "" then
    return nil
  end

  return {
    moduleId = moduleId,
    portId = portId,
  }
end

local function makeAudioConnectionFromEndpoints(modules, fromEndpoint, toEndpoint, preferredId, extraMeta)
  if type(fromEndpoint) ~= "table" or type(toEndpoint) ~= "table" then
    return nil
  end
  return makeConnection(
    preferredId or (tostring(fromEndpoint.moduleId) .. "_to_" .. tostring(toEndpoint.moduleId)),
    "audio",
    fromEndpoint.moduleId,
    fromEndpoint.portId,
    toEndpoint.moduleId,
    toEndpoint.portId,
    decorateAudioMeta(modules, fromEndpoint.moduleId, toEndpoint.moduleId, extraMeta)
  )
end

local function makeControlConnectionFromEndpoints(fromEndpoint, toEndpoint, preferredId, extraMeta)
  if type(fromEndpoint) ~= "table" or type(toEndpoint) ~= "table" then
    return nil
  end
  local meta = type(extraMeta) == "table" and deepCopy(extraMeta) or {}
  return makeConnection(
    preferredId or (tostring(fromEndpoint.moduleId) .. "_" .. tostring(fromEndpoint.portId) .. "_to_" .. tostring(toEndpoint.moduleId) .. "_" .. tostring(toEndpoint.portId)),
    "control",
    fromEndpoint.moduleId,
    fromEndpoint.portId,
    toEndpoint.moduleId,
    toEndpoint.portId,
    meta
  )
end

local function findModuleSpec(moduleId)
  local id = tostring(moduleId or "")
  local dynamicSpecs = type(_G) == "table" and _G.__midiSynthDynamicModuleSpecs or nil
  if type(dynamicSpecs) == "table" and dynamicSpecs[id] ~= nil then
    return dynamicSpecs[id]
  end
  for i = 1, #RACK_MODULE_SPECS do
    local spec = RACK_MODULE_SPECS[i]
    if spec and spec.id == id then
      return spec
    end
  end
  return nil
end

local function findPortSpec(moduleId, direction, portId)
  local spec = findModuleSpec(moduleId)
  local ports = spec and spec.ports or nil
  local list = nil
  if direction == "input" then
    list = ports and ports.inputs or nil
  else
    list = ports and ports.outputs or nil
  end
  if type(list) ~= "table" then
    return nil
  end
  local targetPortId = tostring(portId or "")
  for i = 1, #list do
    local port = list[i]
    if port and tostring(port.id or "") == targetPortId then
      return port
    end
  end
  return nil
end

local function isAuxiliaryAudioPort(moduleId, direction, portId)
  local port = findPortSpec(moduleId, direction, portId)
  return type(port) == "table"
    and tostring(port.type or "") == "audio"
    and (port.auxiliary == true or tostring(port.audioRole or "") ~= "")
end

local function isAudioPort(moduleId, direction, portId)
  local port = findPortSpec(moduleId, direction, portId)
  return type(port) == "table" and tostring(port.type or "") == "audio"
end

firstAudioPortId = function(moduleId, direction)
  local spec = findModuleSpec(moduleId)
  local ports = spec and spec.ports or nil
  local list = nil
  if direction == "input" then
    list = ports and ports.inputs or nil
  else
    list = ports and ports.outputs or nil
  end
  if type(list) ~= "table" then
    return nil
  end
  for i = 1, #list do
    local port = list[i]
    if port and tostring(port.type or "") == "audio" then
      return tostring(port.id or "")
    end
  end
  return nil
end

local firstControlPortId
firstControlPortId = function(moduleId, direction)
  local spec = findModuleSpec(moduleId)
  local ports = spec and spec.ports or nil
  local list = nil
  if direction == "input" then
    list = ports and ports.inputs or nil
  else
    list = ports and ports.outputs or nil
  end
  if type(list) ~= "table" then
    return nil
  end
  for i = 1, #list do
    local port = list[i]
    if port and tostring(port.type or "") == "control" then
      return tostring(port.id or "")
    end
  end
  return nil
end

local function isTransparentAudioModule(moduleId)
  local spec = findModuleSpec(moduleId)
  local meta = spec and spec.meta or nil
  return type(meta) == "table" and meta.audioPassthrough == true
end

local function isAudioSourceModule(moduleId)
  local id = tostring(moduleId or "")
  if id == "" or id == "adsr" or id == M.OUTPUT_NODE_ID or id == "__rackRail" then
    return false
  end
  if isTransparentAudioModule(id) then
    return false
  end
  local spec = findModuleSpec(id)
  local meta = spec and spec.meta or nil
  if type(meta) == "table" and meta.audioSource == true then
    return firstAudioPortId(id, "output") ~= nil
  end
  return firstAudioPortId(id, "output") ~= nil and firstAudioPortId(id, "input") == nil
end

local function isRealAudioStageModule(moduleId)
  local id = tostring(moduleId or "")
  if id == "" or id == "adsr" or id == M.OUTPUT_NODE_ID or id == "__rackRail" then
    return false
  end
  if isTransparentAudioModule(id) then
    return false
  end
  return firstAudioPortId(id, "input") ~= nil or firstAudioPortId(id, "output") ~= nil
end

local function orderedAudioFlowModules(modules)
  local ordered = RackLayout.getFlowModules(type(modules) == "table" and modules or {})
  local out = {}
  for i = 1, #ordered do
    local module = ordered[i]
    if module and module.id ~= "adsr" then
      local hasInput = firstAudioPortId(module.id, "input") ~= nil
      local hasOutput = firstAudioPortId(module.id, "output") ~= nil
      if hasInput or hasOutput then
        out[#out + 1] = module
      end
    end
  end
  return out
end

local function removeAudioConnectionsMatching(connections, predicate)
  local kept = {}
  for i = 1, #(connections or {}) do
    local conn = connections[i]
    local isAudio = tostring(conn and conn.kind or "") == "audio"
    local remove = isAudio and predicate(conn) or false
    if not remove then
      kept[#kept + 1] = RackLayout.makeRackConnection(conn)
    end
  end
  return kept
end

local function removeConnectionsMatching(connections, kind, predicate)
  local kept = {}
  local kindStr = tostring(kind or "")
  for i = 1, #(connections or {}) do
    local conn = connections[i]
    local connKind = tostring(conn and conn.kind or "")
    local remove = (kindStr == "" or connKind == kindStr) and predicate(conn) or false
    if not remove then
      kept[#kept + 1] = RackLayout.makeRackConnection(conn)
    end
  end
  return kept
end

function M.defaultRackState()
  local state = RackLayout.defaultRackState()
  state.modules = {
    RackLayout.makeRackModuleInstance { id = "adsr", row = 0, col = 0, w = 1, h = 1, sizeKey = "1x1", meta = { componentId = "envelopeComponent" } },
    RackLayout.makeRackModuleInstance { id = "oscillator", row = 0, col = 1, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "oscillatorComponent" } },
    RackLayout.makeRackModuleInstance { id = "filter", row = 0, col = 3, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "filterComponent" } },
    RackLayout.makeRackModuleInstance { id = "fx1", row = 1, col = 0, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "fx1Component" } },
    RackLayout.makeRackModuleInstance { id = "fx2", row = 1, col = 2, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "fx2Component" } },
    RackLayout.makeRackModuleInstance { id = "eq", row = 1, col = 4, w = 1, h = 1, sizeKey = "1x1", meta = { componentId = "eqComponent" } },
    RackLayout.makeRackModuleInstance { id = "placeholder1", row = 2, col = 0, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "placeholder1Content" } },
    RackLayout.makeRackModuleInstance { id = "placeholder2", row = 2, col = 2, w = 2, h = 1, sizeKey = "1x2", meta = { componentId = "placeholder2Content" } },
    RackLayout.makeRackModuleInstance { id = "placeholder3", row = 2, col = 4, w = 1, h = 1, sizeKey = "1x1", meta = { componentId = "placeholder3Content" } },
  }
  return state
end

function M.normalizeConnections(connections, modules)
  local normalized = {}
  local rackModules = type(modules) == "table" and RackLayout.cloneRackModules(modules) or M.defaultRackState().modules
  local moduleIdSet = buildModuleIdSet(rackModules)
  local source = type(connections) == "table" and connections or {}
  local seenAudio = {}

  for i = 1, #source do
    local conn = source[i]
    if isAllowedNonAudioConnection(conn) and connectionEndpointsExist(moduleIdSet, conn) then
      normalized[#normalized + 1] = RackLayout.makeRackConnection(conn)
    end
  end

  for i = 1, #source do
    local conn = source[i]
    if tostring(conn and conn.kind or "") == "audio" and connectionEndpointsExist(moduleIdSet, conn) then
      local rawFrom = type(conn.from) == "table" and conn.from or nil
      local rawTo = type(conn.to) == "table" and conn.to or nil
      if rawFrom and rawTo then
        local fromModuleId = tostring(rawFrom.moduleId or "")
        local fromPortId = tostring(rawFrom.portId or "")
        local toModuleId = tostring(rawTo.moduleId or "")
        local toPortId = tostring(rawTo.portId or "")
        local touchesRail = fromModuleId == "__rackRail" or toModuleId == "__rackRail"
        local keep = false

        if touchesRail then
          keep = true
        else
          local supportedKey = table.concat({ fromModuleId, fromPortId, toModuleId, toPortId }, ":")
          keep = AUDIO_ROUTE_EDGE_INDEX[supportedKey] ~= nil
            or (isGenericAudioEndpoint(fromModuleId, fromPortId, "output") and isGenericAudioEndpoint(toModuleId, toPortId, "input"))
            or (isAudioPort(fromModuleId, "output", fromPortId) and isAuxiliaryAudioPort(toModuleId, "input", toPortId))
        end

        if keep then
          local dedupeKey = table.concat({ fromModuleId, fromPortId, toModuleId, toPortId }, ":")
          if not seenAudio[dedupeKey] then
            local preferredId = type(conn.id) == "string" and conn.id ~= "" and conn.id or nil
            local metaSource = type(conn.meta) == "table" and tostring(conn.meta.source or "") ~= "" and tostring(conn.meta.source) or "current-ui"
            normalized[#normalized + 1] = makeConnection(
              preferredId or (fromModuleId .. "_to_" .. toModuleId),
              "audio",
              fromModuleId,
              fromPortId,
              toModuleId,
              toPortId,
              decorateAudioMeta(rackModules, fromModuleId, toModuleId, {
                source = metaSource,
              })
            )
            seenAudio[dedupeKey] = true
          end
        end
      end
    end
  end

  return normalized
end

function M.defaultConnections(modules)
  local rackModules = type(modules) == "table" and RackLayout.cloneRackModules(modules) or M.defaultRackState().modules
  return M.normalizeConnections({
    makeConnection("midi_in_to_adsr", "control", M.MIDI_INPUT_NODE_ID, "voice", "adsr", "midi", {
      source = "current-ui",
    }),
    makeConnection("adsr_to_oscillator", "control", "adsr", "voice", "oscillator", "voice", {
      source = "current-ui",
    }),
    canonicalAudioConnection(rackModules, "oscillator_to_filter"),
    canonicalAudioConnection(rackModules, "filter_to_fx1"),
    canonicalAudioConnection(rackModules, "fx1_to_fx2"),
    canonicalAudioConnection(rackModules, "fx2_to_eq"),
    canonicalAudioConnection(rackModules, "eq_to_output"),
  }, rackModules)
end

function M.hasConnection(connections, kind, fromModuleId, fromPortId, toModuleId, toPortId)
  return hasConnectionEndpoints(connections, kind, fromModuleId, fromPortId, toModuleId, toPortId)
end

function M.audioRouteEdgeMask(connections)
  local source = type(connections) == "table" and connections or {}
  local mask = 0
  local outgoing = {}
  local function isTransparentNode(moduleId)
    local spec = findModuleSpec(moduleId)
    local meta = spec and spec.meta or nil
    return type(meta) == "table" and meta.audioPassthrough == true
  end
  local realSources = {
    oscillator = true,
    filter = true,
    fx1 = true,
    fx2 = true,
    eq = true,
  }
  local realTargets = {
    filter = true,
    fx1 = true,
    fx2 = true,
    eq = true,
    [M.OUTPUT_NODE_ID] = true,
  }

  local function addOutgoing(fromModuleId, fromPortId, toModuleId, toPortId)
    local fromKey = tostring(fromModuleId or "") .. ":" .. tostring(fromPortId or "")
    local bucket = outgoing[fromKey]
    if bucket == nil then
      bucket = {}
      outgoing[fromKey] = bucket
    end
    bucket[#bucket + 1] = {
      moduleId = tostring(toModuleId or ""),
      portId = tostring(toPortId or ""),
    }
  end

  for i = 1, #source do
    local conn = source[i]
    if tostring(conn and conn.kind or "") == "audio" then
      local fromEndpoint = type(conn.from) == "table" and conn.from or nil
      local toEndpoint = type(conn.to) == "table" and conn.to or nil
      if fromEndpoint and toEndpoint then
        addOutgoing(fromEndpoint.moduleId, fromEndpoint.portId, toEndpoint.moduleId, toEndpoint.portId)
      end
    end
  end

  local function railGlueTarget(endpoint)
    local moduleId = tostring(endpoint and endpoint.moduleId or "")
    local portId = tostring(endpoint and endpoint.portId or "")
    if moduleId ~= "__rackRail" then
      return nil
    end

    local row = tonumber(portId:match("send_row(%d+)"))
    if row ~= nil then
      if row >= 3 then
        return {
          moduleId = M.OUTPUT_NODE_ID,
          portId = M.OUTPUT_PORT_ID,
        }
      end

      local nextRecvPortId = string.format("recv_row%d", row + 1)
      local nextRecvKey = "__rackRail:" .. nextRecvPortId
      local nextRecvHasOutgoing = type(outgoing[nextRecvKey]) == "table" and #outgoing[nextRecvKey] > 0
      if nextRecvHasOutgoing then
        return {
          moduleId = "__rackRail",
          portId = nextRecvPortId,
        }
      end

      return {
        moduleId = M.OUTPUT_NODE_ID,
        portId = M.OUTPUT_PORT_ID,
      }
    end

    return nil
  end

  local function collectResolvedTargets(endpoint, visited, out)
    if type(endpoint) ~= "table" then
      return
    end

    local visitKey = tostring(endpoint.moduleId or "") .. ":" .. tostring(endpoint.portId or "")
    if visited[visitKey] then
      return
    end
    visited[visitKey] = true

    local glueTarget = railGlueTarget(endpoint)
    if glueTarget then
      collectResolvedTargets(glueTarget, visited, out)
      return
    end

    if realTargets[endpoint.moduleId] and not isTransparentNode(endpoint.moduleId) then
      out[#out + 1] = {
        moduleId = tostring(endpoint.moduleId or ""),
        portId = tostring(endpoint.portId or ""),
      }
      return
    end

    if isTransparentNode(endpoint.moduleId) then
      local nextKey = tostring(endpoint.moduleId or "") .. ":out"
      local nextEndpoints = outgoing[nextKey] or {}
      for j = 1, #nextEndpoints do
        collectResolvedTargets(nextEndpoints[j], visited, out)
      end
      return
    end

    if tostring(endpoint.moduleId or "") == "__rackRail" then
      local nextKey = tostring(endpoint.moduleId or "") .. ":" .. tostring(endpoint.portId or "")
      local nextEndpoints = outgoing[nextKey] or {}
      for j = 1, #nextEndpoints do
        collectResolvedTargets(nextEndpoints[j], visited, out)
      end
    end
  end

  for sourceModuleId, _ in pairs(realSources) do
    local fromKey = sourceModuleId .. ":out"
    local initialTargets = outgoing[fromKey] or {}
    local resolvedTargets = {}
    local seenTargets = {}

    for i = 1, #initialTargets do
      collectResolvedTargets(initialTargets[i], {}, resolvedTargets)
    end

    for i = 1, #resolvedTargets do
      local target = resolvedTargets[i]
      local dedupeKey = tostring(target.moduleId or "") .. ":" .. tostring(target.portId or "")
      if not seenTargets[dedupeKey] then
        seenTargets[dedupeKey] = true
        local key = table.concat({
          sourceModuleId,
          "out",
          tostring(target.moduleId or ""),
          tostring(target.portId or ""),
        }, ":")
        local bitIndex = AUDIO_ROUTE_EDGE_INDEX[key]
        if bitIndex ~= nil then
          mask = mask + (2 ^ bitIndex)
        end
      end
    end
  end

  return mask
end

function M.describeAudioStageSequence(connections, nodes)
  local normalized = M.normalizeConnections(connections, nodes)
  local rackModules = type(nodes) == "table" and RackLayout.cloneRackModules(nodes) or M.defaultRackState().modules
  local outgoing = {}

  local function addOutgoing(fromModuleId, fromPortId, toModuleId, toPortId)
    local key = tostring(fromModuleId or "") .. ":" .. tostring(fromPortId or "")
    local bucket = outgoing[key]
    if bucket == nil then
      bucket = {}
      outgoing[key] = bucket
    end
    bucket[#bucket + 1] = {
      moduleId = tostring(toModuleId or ""),
      portId = tostring(toPortId or ""),
    }
  end

  for i = 1, #normalized do
    local conn = normalized[i]
    if tostring(conn and conn.kind or "") == "audio" then
      local fromEndpoint = type(conn.from) == "table" and conn.from or nil
      local toEndpoint = type(conn.to) == "table" and conn.to or nil
      if fromEndpoint and toEndpoint then
        addOutgoing(fromEndpoint.moduleId, fromEndpoint.portId, toEndpoint.moduleId, toEndpoint.portId)
      end
    end
  end

  local function primaryAudioTargets(endpoints)
    local out = {}
    local source = type(endpoints) == "table" and endpoints or {}
    for i = 1, #source do
      local endpoint = source[i]
      if type(endpoint) == "table" and not isAuxiliaryAudioPort(endpoint.moduleId, "input", endpoint.portId) then
        out[#out + 1] = endpoint
      end
    end
    return out
  end

  local sourceNodeIds = {}
  local orderedModules = orderedAudioFlowModules(rackModules)
  for i = 1, #orderedModules do
    local module = orderedModules[i]
    if module and isAudioSourceModule(module.id) then
      local outputPortId = firstAudioPortId(module.id, "output") or "out"
      local bucket = primaryAudioTargets(outgoing[tostring(module.id) .. ":" .. tostring(outputPortId)])
      if #bucket > 0 then
        sourceNodeIds[#sourceNodeIds + 1] = tostring(module.id)
      end
    end
  end
  if #sourceNodeIds == 0 then
    sourceNodeIds[1] = "oscillator"
  end

  local orderedStages = {}
  local visited = {}
  local currentModuleId = nil
  local currentPortId = nil
  local reachesOutput = false

  local function firstSerialSource()
    for i = 1, #orderedModules do
      local module = orderedModules[i]
      if module and isAudioSourceModule(module.id) then
        local outputPortId = firstAudioPortId(module.id, "output") or "out"
        local bucket = primaryAudioTargets(outgoing[tostring(module.id) .. ":" .. tostring(outputPortId)])
        if #bucket > 0 then
          for j = 1, #bucket do
            local target = bucket[j]
            if type(target) == "table" then
              local targetModuleId = tostring(target.moduleId or "")
              if targetModuleId == M.OUTPUT_NODE_ID or targetModuleId == "__rackRail" or isRealAudioStageModule(targetModuleId) then
                return tostring(module.id), outputPortId
              end
            end
          end
        end
      end
    end
    local fallbackSource = sourceNodeIds[1]
    if fallbackSource ~= nil then
      return fallbackSource, firstAudioPortId(fallbackSource, "output") or "out"
    end
    return nil, nil
  end

  currentModuleId, currentPortId = firstSerialSource()

  while currentModuleId ~= nil and currentPortId ~= nil do
    local key = tostring(currentModuleId) .. ":" .. tostring(currentPortId)
    if visited[key] then
      break
    end
    visited[key] = true

    local nextEndpoints = primaryAudioTargets(outgoing[key])
    local nextEndpoint = nextEndpoints[1]
    if type(nextEndpoint) ~= "table" then
      break
    end

    local nextModuleId = tostring(nextEndpoint.moduleId or "")
    local nextPortId = tostring(nextEndpoint.portId or "")

    if nextModuleId == M.OUTPUT_NODE_ID then
      reachesOutput = true
      break
    end

    if nextModuleId == "__rackRail" then
      local sendRow = tonumber(nextPortId:match("send_row(%d+)"))
      if sendRow ~= nil then
        if sendRow >= 3 then
          reachesOutput = true
          break
        end

        local nextRecvPortId = string.format("recv_row%d", sendRow + 1)
        local nextRecvKey = "__rackRail:" .. nextRecvPortId
        local nextRecvHasOutgoing = type(outgoing[nextRecvKey]) == "table" and #outgoing[nextRecvKey] > 0
        if not nextRecvHasOutgoing then
          reachesOutput = true
          break
        end
        currentModuleId = "__rackRail"
        currentPortId = nextRecvPortId
      else
        currentModuleId = nextModuleId
        currentPortId = nextPortId
      end
    elseif isTransparentAudioModule(nextModuleId) then
      currentModuleId = nextModuleId
      currentPortId = firstAudioPortId(nextModuleId, "output") or "out"
    elseif isAudioSourceModule(nextModuleId) then
      currentModuleId = nextModuleId
      currentPortId = firstAudioPortId(nextModuleId, "output") or nextPortId
    elseif isRealAudioStageModule(nextModuleId) then
      orderedStages[#orderedStages + 1] = nextModuleId
      currentModuleId = nextModuleId
      currentPortId = firstAudioPortId(nextModuleId, "output") or nextPortId
    else
      break
    end
  end

  return {
    normalizedConnections = normalized,
    sourceNodeIds = sourceNodeIds,
    stageModuleIds = orderedStages,
    stageNodeIds = orderedStages,
    stageCount = #orderedStages,
    reachesOutput = reachesOutput,
  }
end

function M.describeAudioRoute(connections, nodes)
  local normalized = M.normalizeConnections(connections, nodes)
  local mask = M.audioRouteEdgeMask(normalized)
  local activeEdges = {}
  local activeEdgeIds = {}

  for i = 1, #AUDIO_ROUTE_EDGE_ORDER do
    local edge = AUDIO_ROUTE_EDGE_ORDER[i]
    local bitIndex = i - 1
    if math.floor(mask / (2 ^ bitIndex)) % 2 >= 1 then
      activeEdges[#activeEdges + 1] = {
        id = table.concat({ edge.fromModuleId, edge.toModuleId }, "_to_"),
        fromModuleId = edge.fromModuleId,
        fromPortId = edge.fromPortId,
        toModuleId = edge.toModuleId,
        toPortId = edge.toPortId,
      }
      activeEdgeIds[#activeEdgeIds + 1] = activeEdges[#activeEdges].id
    end
  end

  return {
    edgeMask = mask,
    activeEdges = activeEdges,
    activeEdgeIds = activeEdgeIds,
    normalizedConnectionCount = #normalized,
    normalizedConnections = normalized,
  }
end

function M.inferEqRouteMode(connections)
  local source = type(connections) == "table" and connections or {}
  local hasFx2ToEq = false
  local hasEqToOutput = false
  local hasFx2ToOutput = false

  for i = 1, #source do
    local conn = source[i]
    local from = conn and conn.from or nil
    local to = conn and conn.to or nil
    if tostring(conn and conn.kind or "") == "audio" and type(from) == "table" and type(to) == "table" then
      if from.moduleId == "fx2" and from.portId == "out" and to.moduleId == "eq" and to.portId == "in" then
        hasFx2ToEq = true
      elseif from.moduleId == "eq" and from.portId == "out" and ((to.moduleId == M.OUTPUT_NODE_ID and to.portId == M.OUTPUT_PORT_ID) or isRailOutputTarget(conn)) then
        hasEqToOutput = true
      elseif from.moduleId == "fx2" and from.portId == "out" and ((to.moduleId == M.OUTPUT_NODE_ID and to.portId == M.OUTPUT_PORT_ID) or isRailOutputTarget(conn)) then
        hasFx2ToOutput = true
      end
    end
  end

  if hasFx2ToOutput then
    return M.EQ_ROUTE_BYPASSED
  end
  if hasFx2ToEq and hasEqToOutput then
    return M.EQ_ROUTE_INSERTED
  end
  return M.EQ_ROUTE_BROKEN
end

function M.setEqRouteMode(connections, modules, mode)
  local rackModules = type(modules) == "table" and RackLayout.cloneRackModules(modules) or M.defaultRackState().modules
  local nextConnections = M.normalizeConnections(connections, rackModules)
  local kept = {}

  for i = 1, #nextConnections do
    local conn = nextConnections[i]
    if conn and conn.id ~= "fx2_to_eq" and conn.id ~= "eq_to_output" and conn.id ~= "fx2_to_output" then
      kept[#kept + 1] = RackLayout.makeRackConnection(conn)
    end
  end

  local routeMode = math.floor(tonumber(mode) or M.EQ_ROUTE_INSERTED)
  if routeMode == M.EQ_ROUTE_INSERTED then
    kept[#kept + 1] = canonicalAudioConnection(rackModules, "fx2_to_eq")
    kept[#kept + 1] = canonicalAudioConnection(rackModules, "eq_to_output")
  elseif routeMode == M.EQ_ROUTE_BYPASSED then
    kept[#kept + 1] = canonicalAudioConnection(rackModules, "fx2_to_output")
  end

  return M.normalizeConnections(kept, rackModules)
end

function M.spliceRackModule(connections, modules, moduleId)
  local rackModules = type(modules) == "table" and RackLayout.cloneRackModules(modules) or M.defaultRackState().modules
  local nextConnections = M.normalizeConnections(connections, rackModules)
  local kept = {}
  local audioIncoming = {}
  local audioOutgoing = {}
  local controlIncoming = {}
  local controlOutgoing = {}

  for i = 1, #nextConnections do
    local conn = nextConnections[i]
    local from = conn and conn.from or nil
    local to = conn and conn.to or nil
    local connKind = tostring(conn and conn.kind or "")
    local touchesModule = (type(from) == "table" and from.moduleId == moduleId) or (type(to) == "table" and to.moduleId == moduleId)

    if touchesModule then
      if connKind == "audio" then
        if type(to) == "table" and to.moduleId == moduleId then
          audioIncoming[#audioIncoming + 1] = RackLayout.makeRackConnection(conn)
        end
        if type(from) == "table" and from.moduleId == moduleId then
          audioOutgoing[#audioOutgoing + 1] = RackLayout.makeRackConnection(conn)
        end
      else
        if type(to) == "table" and to.moduleId == moduleId then
          controlIncoming[#controlIncoming + 1] = RackLayout.makeRackConnection(conn)
        end
        if type(from) == "table" and from.moduleId == moduleId then
          controlOutgoing[#controlOutgoing + 1] = RackLayout.makeRackConnection(conn)
        end
      end
    else
      kept[#kept + 1] = RackLayout.makeRackConnection(conn)
    end
  end

  for i = 1, #audioIncoming do
    local inc = audioIncoming[i]
    for j = 1, #audioOutgoing do
      local out = audioOutgoing[j]
      local fromEndpoint = rawAudioEndpoint(inc, false)
      local toEndpoint = rawAudioEndpoint(out, true)
      local sameEndpoint = fromEndpoint and toEndpoint
        and fromEndpoint.moduleId == toEndpoint.moduleId
        and fromEndpoint.portId == toEndpoint.portId
      if fromEndpoint and toEndpoint and not sameEndpoint then
        kept[#kept + 1] = makeAudioConnectionFromEndpoints(
          rackModules,
          fromEndpoint,
          toEndpoint,
          tostring(fromEndpoint.moduleId) .. "_to_" .. tostring(toEndpoint.moduleId),
          { source = "splice" }
        )
      end
    end
  end

  for i = 1, #controlIncoming do
    local inc = controlIncoming[i]
    for j = 1, #controlOutgoing do
      local out = controlOutgoing[j]
      local fromEndpoint = rawAudioEndpoint(inc, false)
      local toEndpoint = rawAudioEndpoint(out, true)
      local sameEndpoint = fromEndpoint and toEndpoint
        and fromEndpoint.moduleId == toEndpoint.moduleId
        and fromEndpoint.portId == toEndpoint.portId
      if fromEndpoint and toEndpoint and not sameEndpoint then
        kept[#kept + 1] = makeControlConnectionFromEndpoints(
          fromEndpoint,
          toEndpoint,
          tostring(fromEndpoint.moduleId) .. "_" .. tostring(fromEndpoint.portId) .. "_to_" .. tostring(toEndpoint.moduleId) .. "_" .. tostring(toEndpoint.portId),
          { source = "splice" }
        )
      end
    end
  end

  return M.normalizeConnections(kept, rackModules)
end

function M.insertRackModuleAtVisualSlot(connections, modules, moduleId, sourceModules)
  local rackModules = type(modules) == "table" and RackLayout.cloneRackModules(modules) or M.defaultRackState().modules
  local spliceModules = type(sourceModules) == "table" and RackLayout.cloneRackModules(sourceModules) or rackModules
  local working = M.spliceRackModule(connections, spliceModules, moduleId)

  local moduleAudioInputPortId = firstAudioPortId(moduleId, "input")
  local moduleAudioOutputPortId = firstAudioPortId(moduleId, "output")
  local moduleControlInputPortId = firstControlPortId(moduleId, "input")
  local moduleControlOutputPortId = firstControlPortId(moduleId, "output")

  if moduleAudioInputPortId ~= nil and moduleAudioOutputPortId ~= nil then
    local ordered = orderedAudioFlowModules(rackModules)
    local moduleIndex = nil
    for i = 1, #ordered do
      local module = ordered[i]
      if module and module.id == moduleId then
        moduleIndex = i
        break
      end
    end

    if moduleIndex ~= nil then
      local prevModule = nil
      for i = moduleIndex - 1, 1, -1 do
        local candidate = ordered[i]
        if candidate
          and firstAudioPortId(candidate.id, "output") ~= nil
          and not isTransparentAudioModule(candidate.id) then
          prevModule = candidate
          break
        end
      end

      local nextModule = nil
      for i = moduleIndex + 1, #ordered do
        local candidate = ordered[i]
        if candidate
          and firstAudioPortId(candidate.id, "input") ~= nil
          and not isTransparentAudioModule(candidate.id) then
          nextModule = candidate
          break
        end
      end

      local prevOutputPortId = prevModule and firstAudioPortId(prevModule.id, "output") or nil
      local nextInputPortId = nextModule and firstAudioPortId(nextModule.id, "input") or nil

      if prevModule ~= nil and prevOutputPortId ~= nil then
        if nextModule and nextInputPortId then
          working = removeAudioConnectionsMatching(working, function(conn)
            local toEndpoint = rawAudioEndpoint(conn, true)
            return toEndpoint
              and toEndpoint.moduleId == nextModule.id
              and toEndpoint.portId == nextInputPortId
          end)
        else
          working = removeAudioConnectionsMatching(working, function(conn)
            local fromEndpoint = rawAudioEndpoint(conn, false)
            local toEndpoint = rawAudioEndpoint(conn, true)
            return fromEndpoint and toEndpoint
              and fromEndpoint.moduleId == prevModule.id
              and fromEndpoint.portId == prevOutputPortId
              and toEndpoint.moduleId == M.OUTPUT_NODE_ID
              and toEndpoint.portId == M.OUTPUT_PORT_ID
          end)
        end

        working[#working + 1] = makeAudioConnectionFromEndpoints(
          rackModules,
          { moduleId = prevModule.id, portId = prevOutputPortId },
          { moduleId = moduleId, portId = moduleAudioInputPortId },
          tostring(prevModule.id) .. "_to_" .. tostring(moduleId),
          { source = "shift-insert" }
        )

        if nextModule and nextInputPortId then
          working[#working + 1] = makeAudioConnectionFromEndpoints(
            rackModules,
            { moduleId = moduleId, portId = moduleAudioOutputPortId },
            { moduleId = nextModule.id, portId = nextInputPortId },
            tostring(moduleId) .. "_to_" .. tostring(nextModule.id),
            { source = "shift-insert" }
          )
        else
          working[#working + 1] = makeAudioConnectionFromEndpoints(
            rackModules,
            { moduleId = moduleId, portId = moduleAudioOutputPortId },
            { moduleId = M.OUTPUT_NODE_ID, portId = M.OUTPUT_PORT_ID },
            tostring(moduleId) .. "_to_output",
            { source = "shift-insert" }
          )
        end
      end
    end
  end

  if moduleControlInputPortId ~= nil and moduleControlOutputPortId ~= nil then
    local orderedAll = RackLayout.getFlowModules(rackModules)
    local modulePos = nil
    for i = 1, #orderedAll do
      local mod = orderedAll[i]
      if mod and mod.id == moduleId then
        modulePos = i
        break
      end
    end

    if modulePos ~= nil then
      local function modulePosition(mid)
        for k = 1, #orderedAll do
          if orderedAll[k] and orderedAll[k].id == mid then
            return k
          end
        end
        return nil
      end

      local interceptedControl = {}
      local remaining = {}
      for i = 1, #working do
        local conn = working[i]
        local connKind = tostring(conn and conn.kind or "")
        if connKind ~= "audio" then
          local from = type(conn) == "table" and conn.from or nil
          local to = type(conn) == "table" and conn.to or nil
          if type(from) == "table" and type(to) == "table" then
            local fromPos = modulePosition(tostring(from.moduleId or ""))
            local toPos = modulePosition(tostring(to.moduleId or ""))
            local fromIsRail = tostring(from.moduleId) == "__rackRail"
            local toIsRail = tostring(to.moduleId) == "__rackRail"
            if not fromIsRail and not toIsRail
              and fromPos ~= nil and toPos ~= nil
              and fromPos < modulePos and toPos > modulePos then
              interceptedControl[#interceptedControl + 1] = conn
            else
              remaining[#remaining + 1] = conn
            end
          else
            remaining[#remaining + 1] = conn
          end
        else
          remaining[#remaining + 1] = conn
        end
      end

      working = remaining

      for i = 1, #interceptedControl do
        local conn = interceptedControl[i]
        local from = conn.from
        local to = conn.to
        local existingMeta = type(conn.meta) == "table" and conn.meta or {}
        local bridgeMeta = {}
        for k, v in pairs(existingMeta) do
          bridgeMeta[k] = v
        end
        bridgeMeta.source = "shift-insert"

        working[#working + 1] = makeControlConnectionFromEndpoints(
          { moduleId = from.moduleId, portId = from.portId },
          { moduleId = moduleId, portId = moduleControlInputPortId },
          tostring(from.moduleId) .. "_" .. tostring(from.portId) .. "_to_" .. tostring(moduleId) .. "_" .. tostring(moduleControlInputPortId),
          bridgeMeta
        )

        working[#working + 1] = makeControlConnectionFromEndpoints(
          { moduleId = moduleId, portId = moduleControlOutputPortId },
          { moduleId = to.moduleId, portId = to.portId },
          tostring(moduleId) .. "_" .. tostring(moduleControlOutputPortId) .. "_to_" .. tostring(to.moduleId) .. "_" .. tostring(to.portId),
          bridgeMeta
        )
      end
    end
  end

  return M.normalizeConnections(working, rackModules)
end

return M

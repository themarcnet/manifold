local M = {}

local DSP_SLOT = "super"

local FX_SCRIPT_DEFS = {
  bypass = {
    create = 'local fx = ctx.primitives.PassthroughNode.new(2)',
    params = {},
  },
  chorus = {
    create = [[local fx = ctx.primitives.ChorusNode.new()
  fx:setRate(0.7) fx:setDepth(0.5) fx:setVoices(3) fx:setSpread(0.8)
  fx:setFeedback(0.15) fx:setWaveform(0) fx:setMix(0.55)]],
    params = {
      {"rate",      'type="f",min=0.1,max=10.0,default=0.7',   "setRate"},
      {"depth",     'type="f",min=0.0,max=1.0,default=0.5',    "setDepth"},
      {"voices",    'type="f",min=1.0,max=4.0,default=3.0',    "setVoices"},
      {"spread",    'type="f",min=0.0,max=1.0,default=0.8',    "setSpread"},
      {"feedback",  'type="f",min=0.0,max=0.9,default=0.15',   "setFeedback"},
      {"waveform",  'type="f",min=0.0,max=1.0,default=0.0',    "setWaveform"},
      {"mix",       'type="f",min=0.0,max=1.0,default=0.55',   "setMix"},
    },
  },
  phaser = {
    create = [[local fx = ctx.primitives.PhaserNode.new()
  fx:setRate(0.35) fx:setDepth(0.8) fx:setStages(6) fx:setFeedback(0.25) fx:setSpread(120)]],
    params = {
      {"rate",     'type="f",min=0.1,max=10.0,default=0.35',  "setRate"},
      {"depth",    'type="f",min=0.0,max=1.0,default=0.8',    "setDepth"},
      {"stages",   'type="f",min=6.0,max=12.0,default=6.0',   "setStages"},
      {"feedback", 'type="f",min=-0.9,max=0.9,default=0.25',  "setFeedback"},
      {"spread",   'type="f",min=0.0,max=180.0,default=120.0',"setSpread"},
    },
  },
  bitcrusher = {
    create = [[local fx = ctx.primitives.BitCrusherNode.new()
  fx:setBits(6) fx:setRateReduction(8) fx:setMix(1.0) fx:setOutput(0.8)]],
    params = {
      {"bits",   'type="f",min=2,max=16,default=6',     "setBits"},
      {"rate",   'type="f",min=1,max=64,default=8',     "setRateReduction"},
      {"mix",    'type="f",min=0,max=1,default=1.0',    "setMix"},
      {"output", 'type="f",min=0,max=2,default=0.8',    "setOutput"},
    },
  },
  waveshaper = {
    create = [[local fx = ctx.primitives.WaveShaperNode.new()
  fx:setCurve(0) fx:setDrive(12.0) fx:setOutput(-3.0) fx:setPreFilter(0)
  fx:setPostFilter(0) fx:setBias(0.0) fx:setMix(1.0) fx:setOversample(2)]],
    params = {
      {"curve",      'type="f",min=0,max=6,default=0',          "setCurve"},
      {"drive",      'type="f",min=0,max=40,default=12',        "setDrive"},
      {"output",     'type="f",min=-20,max=20,default=-3',      "setOutput"},
      {"prefilter",  'type="f",min=0,max=10000,default=0',      "setPreFilter"},
      {"postfilter", 'type="f",min=0,max=10000,default=0',      "setPostFilter"},
      {"bias",       'type="f",min=-1,max=1,default=0',         "setBias"},
      {"mix",        'type="f",min=0,max=1,default=1',          "setMix"},
      {"oversample", 'type="f",min=1,max=4,default=2',          "setOversample"},
    },
  },
  filter = {
    create = [[local fx = ctx.primitives.FilterNode.new()
  fx:setCutoff(900.0) fx:setResonance(0.2) fx:setMix(1.0)]],
    params = {
      {"cutoff",    'type="f",min=80,max=8000,default=900',  "setCutoff"},
      {"resonance", 'type="f",min=0,max=1,default=0.2',      "setResonance"},
      {"mix",       'type="f",min=0,max=1,default=1.0',      "setMix"},
    },
  },
  svf = {
    create = [[local fx = ctx.primitives.SVFNode.new()
  fx:setCutoff(1000) fx:setResonance(0.5) fx:setMode(0) fx:setDrive(0) fx:setMix(1.0)]],
    params = {
      {"cutoff",    'type="f",min=40,max=10000,default=1000',  "setCutoff"},
      {"resonance", 'type="f",min=0.06,max=1,default=0.5',    "setResonance"},
      {"mode",      'type="i",min=0,max=4,default=0',         "setMode"},
      {"drive",     'type="f",min=0,max=10,default=0',        "setDrive"},
      {"mix",       'type="f",min=0,max=1,default=1.0',       "setMix"},
    },
  },
  reverb = {
    create = [[local fx = ctx.primitives.ReverbNode.new()
  fx:setRoomSize(0.65) fx:setDamping(0.4) fx:setWetLevel(0.35) fx:setDryLevel(0.85) fx:setWidth(1.0)]],
    params = {
      {"room",    'type="f",min=0,max=1,default=0.65',  "setRoomSize"},
      {"damping", 'type="f",min=0,max=1,default=0.4',   "setDamping"},
      {"wet",     'type="f",min=0,max=1,default=0.35',  "setWetLevel"},
      {"dry",     'type="f",min=0,max=1,default=0.85',  "setDryLevel"},
      {"width",   'type="f",min=0,max=1,default=1.0',   "setWidth"},
    },
  },
  shimmer = {
    create = [[local fx = ctx.primitives.ShimmerNode.new()
  fx:setSize(0.65) fx:setPitch(12) fx:setFeedback(0.7) fx:setMix(0.5) fx:setModulation(0.25) fx:setFilter(5500)]],
    params = {
      {"size",     'type="f",min=0,max=1,default=0.65',       "setSize"},
      {"pitch",    'type="f",min=-12,max=12,default=12',      "setPitch"},
      {"feedback", 'type="f",min=0,max=0.99,default=0.7',     "setFeedback"},
      {"mix",      'type="f",min=0,max=1,default=0.5',        "setMix"},
      {"mod",      'type="f",min=0,max=1,default=0.25',       "setModulation"},
      {"filter",   'type="f",min=100,max=12000,default=5500', "setFilter"},
    },
  },
  stereodelay = {
    create = [[local fx = ctx.primitives.StereoDelayNode.new()
  fx:setTempo(120) fx:setTimeMode(0) fx:setTimeL(250) fx:setTimeR(375)
  fx:setFeedback(0.3) fx:setPingPong(0) fx:setFilterEnabled(0)
  fx:setFilterCutoff(4000) fx:setMix(0.5) fx:setFreeze(0) fx:setWidth(1.0)]],
    params = {
      {"timemode",    'type="i",min=0,max=1,default=0',          "setTimeMode"},
      {"timel",       'type="f",min=10,max=2000,default=250',    "setTimeL"},
      {"timer",       'type="f",min=10,max=2000,default=375',    "setTimeR"},
      {"feedback",    'type="f",min=0,max=1.2,default=0.3',      "setFeedback"},
      {"pingpong",    'type="i",min=0,max=1,default=0',          "setPingPong"},
      {"filter",      'type="i",min=0,max=1,default=0',          "setFilterEnabled"},
      {"filtercutoff",'type="f",min=200,max=10000,default=4000', "setFilterCutoff"},
      {"mix",         'type="f",min=0,max=1,default=0.5',        "setMix"},
      {"freeze",      'type="i",min=0,max=1,default=0',          "setFreeze"},
      {"width",       'type="f",min=0,max=2,default=1.0',        "setWidth"},
    },
  },
  reversedelay = {
    create = [[local fx = ctx.primitives.ReverseDelayNode.new()
  fx:setTime(420) fx:setWindow(120) fx:setFeedback(0.45) fx:setMix(0.65)]],
    params = {
      {"time",     'type="f",min=50,max=2000,default=420',  "setTime"},
      {"window",   'type="f",min=20,max=400,default=120',   "setWindow"},
      {"feedback", 'type="f",min=0,max=0.95,default=0.45',  "setFeedback"},
      {"mix",      'type="f",min=0,max=1,default=0.65',     "setMix"},
    },
  },
  multitap = {
    create = [[local fx = ctx.primitives.MultitapDelayNode.new()
  fx:setTapCount(4)
  fx:setTapTime(1,180) fx:setTapTime(2,320) fx:setTapTime(3,470) fx:setTapTime(4,620)
  fx:setTapGain(1,0.5) fx:setTapGain(2,0.35) fx:setTapGain(3,0.28) fx:setTapGain(4,0.2)
  fx:setTapPan(1,-0.8) fx:setTapPan(2,-0.25) fx:setTapPan(3,0.25) fx:setTapPan(4,0.8)
  fx:setFeedback(0.3) fx:setMix(0.55)]],
    params = {
      {"tapcount", 'type="f",min=1,max=8,default=4',      "setTapCount"},
      {"feedback", 'type="f",min=0,max=0.95,default=0.3', "setFeedback"},
      {"mix",      'type="f",min=0,max=1,default=0.55',   "setMix"},
    },
  },
  pitchshift = {
    create = [[local fx = ctx.primitives.PitchShifterNode.new()
  fx:setPitch(7) fx:setWindow(80) fx:setFeedback(0.15) fx:setMix(1.0)]],
    params = {
      {"pitch",    'type="f",min=-24,max=24,default=7',    "setPitch"},
      {"window",   'type="f",min=20,max=200,default=80',   "setWindow"},
      {"feedback", 'type="f",min=0,max=0.95,default=0.15', "setFeedback"},
      {"mix",      'type="f",min=0,max=1,default=1.0',     "setMix"},
    },
  },
  granulator = {
    create = [[local fx = ctx.primitives.GranulatorNode.new()
  fx:setGrainSize(90) fx:setDensity(24) fx:setPosition(0.6) fx:setPitch(0)
  fx:setSpray(0.25) fx:setFreeze(false) fx:setEnvelope(0) fx:setMix(1.0)]],
    params = {
      {"grainsize", 'type="f",min=1,max=500,default=90',   "setGrainSize"},
      {"density",   'type="f",min=1,max=100,default=24',   "setDensity"},
      {"position",  'type="f",min=0,max=1,default=0.6',    "setPosition"},
      {"pitch",     'type="f",min=-24,max=24,default=0',   "setPitch"},
      {"spray",     'type="f",min=0,max=1,default=0.25',   "setSpray"},
      {"freeze",    'type="f",min=0,max=1,default=0',      "setFreeze"},
      {"envelope",  'type="f",min=0,max=1,default=0',      "setEnvelope"},
      {"mix",       'type="f",min=0,max=1,default=1',      "setMix"},
    },
  },
  ringmod = {
    create = [[local fx = ctx.primitives.RingModulatorNode.new()
  fx:setFrequency(120) fx:setDepth(1.0) fx:setMix(1.0) fx:setSpread(30)]],
    params = {
      {"freq",   'type="f",min=0.1,max=2000,default=120', "setFrequency"},
      {"depth",  'type="f",min=0,max=1,default=1.0',      "setDepth"},
      {"mix",    'type="f",min=0,max=1,default=1.0',      "setMix"},
      {"spread", 'type="f",min=0,max=180,default=30',     "setSpread"},
    },
  },
  formant = {
    create = [[local fx = ctx.primitives.FormantFilterNode.new()
  fx:setVowel(0) fx:setShift(0) fx:setResonance(7) fx:setDrive(1.4) fx:setMix(1.0)]],
    params = {
      {"vowel",     'type="f",min=0,max=4,default=0',     "setVowel"},
      {"shift",     'type="f",min=-12,max=12,default=0',  "setShift"},
      {"resonance", 'type="f",min=1,max=20,default=7',    "setResonance"},
      {"drive",     'type="f",min=0.5,max=8,default=1.4', "setDrive"},
      {"mix",       'type="f",min=0,max=1,default=1.0',   "setMix"},
    },
  },
  eq = {
    create = [[local fx = ctx.primitives.EQNode.new()
  fx:setLowGain(6) fx:setLowFreq(120) fx:setMidGain(-4) fx:setMidFreq(900)
  fx:setMidQ(0.8) fx:setHighGain(4) fx:setHighFreq(8000) fx:setOutput(0) fx:setMix(1.0)]],
    params = {
      {"low_gain",  'type="f",min=-24,max=24,default=6',      "setLowGain"},
      {"low_freq",  'type="f",min=20,max=400,default=120',    "setLowFreq"},
      {"mid_gain",  'type="f",min=-24,max=24,default=-4',     "setMidGain"},
      {"mid_freq",  'type="f",min=120,max=8000,default=900',  "setMidFreq"},
      {"mid_q",     'type="f",min=0.2,max=12,default=0.8',    "setMidQ"},
      {"high_gain", 'type="f",min=-24,max=24,default=4',      "setHighGain"},
      {"high_freq", 'type="f",min=2000,max=16000,default=8000',"setHighFreq"},
      {"output",    'type="f",min=-24,max=24,default=0',      "setOutput"},
      {"mix",       'type="f",min=0,max=1,default=1.0',       "setMix"},
    },
  },
  compressor = {
    create = [[local fx = ctx.primitives.CompressorNode.new()
  fx:setThreshold(-18) fx:setRatio(4) fx:setAttack(5) fx:setRelease(100)
  fx:setKnee(6) fx:setMakeup(0) fx:setAutoMakeup(true) fx:setMode(0)
  fx:setDetectorMode(0) fx:setSidechainHPF(100) fx:setMix(1.0)]],
    params = {
      {"threshold",    'type="f",min=-60,max=0,default=-18',    "setThreshold"},
      {"ratio",        'type="f",min=1,max=20,default=4',       "setRatio"},
      {"attack",       'type="f",min=0.1,max=100,default=5',    "setAttack"},
      {"release",      'type="f",min=1,max=1000,default=100',   "setRelease"},
      {"knee",         'type="f",min=0,max=20,default=6',       "setKnee"},
      {"makeup",       'type="f",min=0,max=40,default=0',       "setMakeup"},
      {"auto_makeup",  'type="f",min=0,max=1,default=1',        "setAutoMakeup"},
      {"mode",         'type="f",min=0,max=1,default=0',        "setMode"},
      {"detector",     'type="f",min=0,max=1,default=0',        "setDetectorMode"},
      {"sidechain_hpf",'type="f",min=20,max=1000,default=100',  "setSidechainHPF"},
      {"mix",          'type="f",min=0,max=1,default=1.0',      "setMix"},
    },
  },
  limiter = {
    create = [[local fx = ctx.primitives.LimiterNode.new()
  fx:setThreshold(-6) fx:setRelease(80) fx:setMakeup(0) fx:setSoftClip(0.4) fx:setMix(1.0)]],
    params = {
      {"threshold", 'type="f",min=-24,max=0,default=-6',   "setThreshold"},
      {"release",   'type="f",min=1,max=500,default=80',   "setRelease"},
      {"makeup",    'type="f",min=0,max=18,default=0',     "setMakeup"},
      {"soft",      'type="f",min=0,max=1,default=0.4',    "setSoftClip"},
      {"mix",       'type="f",min=0,max=1,default=1.0',    "setMix"},
    },
  },
  transient = {
    create = [[local fx = ctx.primitives.TransientShaperNode.new()
  fx:setAttack(0.6) fx:setSustain(-0.3) fx:setSensitivity(1.2) fx:setMix(1.0)]],
    params = {
      {"attack",      'type="f",min=-1,max=1,default=0.6',  "setAttack"},
      {"sustain",     'type="f",min=-1,max=1,default=-0.3', "setSustain"},
      {"sensitivity", 'type="f",min=0.1,max=4,default=1.2', "setSensitivity"},
      {"mix",         'type="f",min=0,max=1,default=1.0',   "setMix"},
    },
  },
  widener = {
    create = [[local fx = ctx.primitives.StereoWidenerNode.new()
  fx:setWidth(1.25) fx:setMonoLowFreq(140) fx:setMonoLowEnable(true)]],
    params = {
      {"width",         'type="f",min=0,max=2,default=1.25',   "setWidth"},
      {"monolowfreq",   'type="f",min=20,max=500,default=140', "setMonoLowFreq"},
      {"monolowenable", 'type="f",min=0,max=1,default=1',      "setMonoLowEnable"},
    },
  },
}

local function generateFxBlock(varName, basePath, effectId)
  local def = FX_SCRIPT_DEFS[effectId] or FX_SCRIPT_DEFS.bypass
  effectId = FX_SCRIPT_DEFS[effectId] and effectId or "bypass"
  local lines = {}
  lines[#lines + 1] = "  do"
  lines[#lines + 1] = "  " .. def.create
  lines[#lines + 1] = string.format("  ctx.graph.connect(%s_in, fx)", varName)
  lines[#lines + 1] = string.format("  ctx.graph.connect(fx, %s_out)", varName)
  for _, p in ipairs(def.params) do
    local path = basePath .. "/" .. effectId .. "/" .. p[1]
    lines[#lines + 1] = string.format('  ctx.params.register("%s", {%s})', path, p[2])
    lines[#lines + 1] = string.format('  ctx.params.bind("%s", fx, "%s")', path, p[3])
  end
  lines[#lines + 1] = "  end"
  return table.concat(lines, "\n")
end

local function generateSuperDspCode(vocalId, layerIds)
  local lines = {}
  lines[#lines + 1] = "function buildPlugin(ctx)"
  lines[#lines + 1] = "  local hostInput = ctx.primitives.PassthroughNode.new(2)"
  lines[#lines + 1] = "  local inputTrim = ctx.primitives.GainNode.new(2)"
  lines[#lines + 1] = "  inputTrim:setGain(1.0)"
  lines[#lines + 1] = "  ctx.graph.connect(hostInput, inputTrim)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  local vocal_in = ctx.primitives.PassthroughNode.new(2)"
  lines[#lines + 1] = "  local vocal_out = ctx.primitives.GainNode.new(2)"
  lines[#lines + 1] = "  vocal_out:setGain(1.0)"
  lines[#lines + 1] = "  ctx.graph.connect(inputTrim, vocal_in)"
  lines[#lines + 1] = generateFxBlock("vocal", "/core/super/vocal/slot", vocalId)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  local layerMixer = ctx.primitives.MixerNode.new()"
  lines[#lines + 1] = "  layerMixer:setInputCount(4)"
  lines[#lines + 1] = "  layerMixer:setMaster(1.0)"
  for i = 1, 4 do
    lines[#lines + 1] = string.format("  layerMixer:setGain(%d, 1.0)", i)
    lines[#lines + 1] = string.format("  layerMixer:setPan(%d, 0.0)", i)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  local function hostNode(path)"
  lines[#lines + 1] = "    if ctx.host and ctx.host.getGraphNodeByPath then"
  lines[#lines + 1] = "      return ctx.host.getGraphNodeByPath(path)"
  lines[#lines + 1] = "    end"
  lines[#lines + 1] = "    return nil"
  lines[#lines + 1] = "  end"
  lines[#lines + 1] = ""
  for i = 0, 3 do
    local effectId = (layerIds and layerIds[i + 1]) or "bypass"
    local lvar = "layer" .. tostring(i)
    local lbase = "/core/super/layer/" .. tostring(i) .. "/fx"
    lines[#lines + 1] = string.format("  local %s_in = ctx.primitives.PassthroughNode.new(2)", lvar)
    lines[#lines + 1] = string.format("  local %s_out = ctx.primitives.GainNode.new(2)", lvar)
    lines[#lines + 1] = string.format("  %s_out:setGain(1.0)", lvar)
    lines[#lines + 1] = generateFxBlock(lvar, lbase, effectId)
    lines[#lines + 1] = string.format('  local layerOut%d = hostNode("/core/behavior/layer/%d/output")', i, i)
    lines[#lines + 1] = string.format('  if layerOut%d then ctx.graph.connect(layerOut%d, %s_in) end', i, i, lvar)
    lines[#lines + 1] = string.format('  ctx.graph.connect(%s_out, layerMixer, 0, %d)', lvar, i)
    lines[#lines + 1] = string.format('  local layerIn%d = hostNode("/core/behavior/layer/%d/input")', i, i)
    lines[#lines + 1] = string.format('  if layerIn%d then ctx.graph.connect(vocal_out, layerIn%d) end', i, i)
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "  local mainMixer = ctx.primitives.MixerNode.new()"
  lines[#lines + 1] = "  mainMixer:setInputCount(2)"
  lines[#lines + 1] = "  mainMixer:setGain(1, 1.0) mainMixer:setPan(1, 0.0)"
  lines[#lines + 1] = "  mainMixer:setGain(2, 1.0) mainMixer:setPan(2, 0.0)"
  lines[#lines + 1] = "  mainMixer:setMaster(1.0)"
  lines[#lines + 1] = "  local masterGain = ctx.primitives.GainNode.new(2)"
  lines[#lines + 1] = "  masterGain:setGain(1.0)"
  lines[#lines + 1] = "  ctx.graph.connect(layerMixer, mainMixer, 0, 0)"
  lines[#lines + 1] = "  ctx.graph.connect(vocal_out, mainMixer, 0, 1)"
  lines[#lines + 1] = "  ctx.graph.connect(mainMixer, masterGain)"
  lines[#lines + 1] = "  return {}"
  lines[#lines + 1] = "end"
  lines[#lines + 1] = "return buildPlugin"
  return table.concat(lines, "\n")
end

local function selectionKey(selections)
  local layers = selections.layers or {}
  return table.concat({
    selections.vocal or "bypass",
    layers[1] or "bypass",
    layers[2] or "bypass",
    layers[3] or "bypass",
    layers[4] or "bypass",
  }, "|")
end

function M.ensureLoaded(project, selections, force)
  if type(loadDspScriptFromStringInSlot) ~= "function" then
    return false, "loadDspScriptFromStringInSlot unavailable"
  end
  local key = selectionKey(selections or {})
  if not force and M._loadedKey == key then
    return true
  end
  if type(setDspSlotPersistOnUiSwitch) == "function" then
    pcall(setDspSlotPersistOnUiSwitch, DSP_SLOT, false)
  end
  local code = generateSuperDspCode((selections and selections.vocal) or "bypass", (selections and selections.layers) or {})
  local sourceName = (project and project.root or "LooperTabs") .. "/dsp/super_slot.generated.lua"
  local ok, result = pcall(loadDspScriptFromStringInSlot, code, sourceName, DSP_SLOT)
  if ok and result then
    M._loadedKey = key
    return true
  end
  return false, (not ok and tostring(result)) or "slot load failed"
end

return M

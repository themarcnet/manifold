package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. package.path

local MidiSynthRack = require("behaviors.rack_midisynth_specs")

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEqual failed") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(value, message)
  if not value then
    error(message or "assertTrue failed", 2)
  end
end

local function findPort(ports, portId)
  for i = 1, #(ports or {}) do
    local port = ports[i]
    if type(port) == "table" and tostring(port.id or "") == tostring(portId or "") then
      return port
    end
  end
  return nil
end

local function testSpecMetadataNormalization()
  local specs = MidiSynthRack.rackModuleSpecById()

  assertEqual(specs.adsr.meta.category, "voice", "adsr category normalized")
  assertEqual(specs.adsr.meta.instancePolicy, "singleton_or_dynamic", "adsr instance policy")
  assertEqual(specs.adsr.meta.runtimeKind, "stateful_transform", "adsr runtime kind")
  assertEqual(specs.adsr.meta.paramTemplateMode, "dynamic_param_base", "adsr param template mode")
  assertEqual(specs.adsr.meta.palette.displayName, "ADSR", "adsr palette display name")
  assertEqual(specs.adsr.meta.palette.portSummary, "MIDI/VOICE -> VOICE, ENV, INV, EOC", "adsr palette port summary")
  assertEqual(specs.adsr.meta.factoryVersion, 1, "factory version stamped")
  assertEqual(specs.adsr.meta.paramPathRemap.exact["/midi/synth/adsr/attack"], "/attack", "adsr remap metadata")

  assertEqual(specs.arp.meta.paramTemplateMode, "template_token", "arp template mode")
  assertEqual(specs.transpose.meta.instancePolicy, "dynamic", "transpose instance policy")
  assertEqual(specs.transpose.meta.palette.portSummary, "VOICE -> VOICE", "transpose palette summary")
  assertEqual(specs.lfo.meta.runtimeKind, "stateful_transform", "lfo runtime kind")
  assertEqual(specs.lfo.ports.outputs[3].signalKind, "scalar_unipolar", "lfo uni signal kind normalized")
  assertEqual(specs.slew.meta.category, "mod", "slew category normalized")
  assertEqual(specs.sample_hold.ports.inputs[2].signalKind, "trigger", "sample hold trigger signal kind")
  assertEqual(specs.compare.ports.outputs[1].signalKind, "gate", "compare gate signal kind")
  assertEqual(specs.cv_mix.ports.inputs[1].signalKind, "scalar_bipolar", "cv mix input signal kind")
  assertEqual(specs.eq.meta.paramPathRemap.patterns[1].toSuffixTemplate, "/band/{1}/{2}", "eq remap pattern metadata")
  assertEqual(specs.rack_oscillator.meta.instancePolicy, "dynamic", "rack oscillator instance policy")
  assertEqual(findPort(specs.rack_oscillator.ports.outputs, "analysis").type, "analysis", "rack oscillator analysis output present")
  assertEqual(specs.rack_sample.meta.instancePolicy, "dynamic", "rack sample instance policy")
  assertEqual(specs.rack_sample.meta.runtimeKind, "source", "rack sample runtime kind")
  assertEqual(specs.rack_sample.ports.inputs[1].auxiliary, true, "rack sample audio input marked auxiliary")
  assertEqual(specs.blend_simple.meta.instancePolicy, "dynamic", "blend simple instance policy")
  assertEqual(specs.blend_simple.ports.inputs[2].auxiliary, true, "blend simple B input marked auxiliary")
  assertEqual(specs.filter.meta.instancePolicy, "canonical_or_dynamic", "filter instance policy")
  assertEqual(specs.fx.meta.palette.displayName, "FX", "fx alias palette display name")
  assertEqual(specs.placeholder.meta.palette.displayName, "Slot", "placeholder alias palette display name")
  assertEqual(specs.transpose.ports.inputs[1].signalKind, "voice_bundle", "transpose input signal kind normalized")
  assertEqual(specs.transpose.ports.outputs[1].domain, "voice", "transpose output domain normalized")
  assertEqual(specs.transpose.ports.params[1].signalKind, "scalar_bipolar", "transpose param signal kind normalized")
end

local function testPaletteTemplateCatalog()
  local templates = MidiSynthRack.paletteEntryTemplateById()
  assertEqual(templates.adsr.displayName, "ADSR", "adsr palette template display")
  assertEqual(templates.arp.category, "voice", "arp palette category")
  assertEqual(templates.transpose.displayName, "Transpose", "transpose palette display")
  assertEqual(templates.rack_oscillator.portSummary, "VOICE -> OUT, ANALYSIS", "oscillator port summary")
  assertEqual(templates.rack_sample.displayName, "Sample", "sample palette display")
  assertEqual(templates.rack_sample.portSummary, "IN/VOICE -> OUT, ANALYSIS", "sample palette summary")
  assertEqual(templates.blend_simple.displayName, "Blend", "blend simple palette display")
  assertEqual(templates.blend_simple.portSummary, "A/B -> OUT", "blend simple palette summary")
  assertEqual(templates.filter.instancePolicy, "canonical_or_dynamic", "filter palette policy")
  assertEqual(templates.lfo.displayName, "LFO", "lfo palette display")
  assertEqual(templates.cv_mix.portSummary, "IN1..4 -> OUT, INV", "cv mix palette summary")
  assertEqual(templates.fx.paramTemplateMode, "dynamic_slot_remap", "fx palette template mode")
  assertEqual(templates.fx.displayName, "FX", "fx alias palette display")
  assertEqual(templates.placeholder.componentId, "contentComponent", "placeholder alias component id")
  assertTrue(templates.eq.order > templates.filter.order, "eq palette order after filter")
end

local function testAuxiliaryAudioConnectionsSurviveNormalization()
  local modules = {
    { id = "rack_sample", row = 0, col = 0, w = 2, h = 1, sizeKey = "1x2" },
    { id = "blend_simple", row = 0, col = 2, w = 1, h = 1, sizeKey = "1x1" },
  }
  local connections = {
    {
      id = "sample_to_blend_b",
      kind = "audio",
      from = { moduleId = "rack_sample", portId = "out" },
      to = { moduleId = "blend_simple", portId = "b" },
      meta = { source = "test" },
    },
  }

  local normalized = MidiSynthRack.normalizeConnections(connections, modules)
  assertEqual(#normalized, 1, "auxiliary audio connection retained")
  assertEqual(normalized[1].to.portId, "b", "auxiliary audio target port preserved")
end

local function testDynamicSourceDrivesSerialStageSelection()
  local modules = {
    { id = "oscillator", row = 0, col = 0, w = 1, h = 1, sizeKey = "1x1" },
    { id = "rack_sample_inst_1", row = 0, col = 1, w = 2, h = 1, sizeKey = "1x2", meta = { specId = "rack_sample", slotIndex = 1 } },
    { id = "blend_simple_inst_1", row = 0, col = 3, w = 1, h = 1, sizeKey = "1x1", meta = { specId = "blend_simple", slotIndex = 1 } },
  }

  _G.__midiSynthDynamicModuleSpecs = _G.__midiSynthDynamicModuleSpecs or {}
  _G.__midiSynthDynamicModuleSpecs["rack_sample_inst_1"] = {
    id = "rack_sample_inst_1",
    ports = {
      inputs = {
        { id = "in", type = "audio", auxiliary = true, audioRole = "capture" },
        { id = "voice", type = "control" },
      },
      outputs = {
        { id = "out", type = "audio" },
        { id = "analysis", type = "analysis" },
      },
    },
    meta = { audioSource = true, specId = "rack_sample", slotIndex = 1 },
  }
  _G.__midiSynthDynamicModuleSpecs["blend_simple_inst_1"] = {
    id = "blend_simple_inst_1",
    ports = {
      inputs = {
        { id = "a", type = "audio" },
        { id = "b", type = "audio", auxiliary = true, audioRole = "blend_b" },
      },
      outputs = {
        { id = "out", type = "audio" },
      },
    },
    meta = { specId = "blend_simple", slotIndex = 1 },
  }

  local connections = {
    {
      id = "sample_to_blend_a",
      kind = "audio",
      from = { moduleId = "rack_sample_inst_1", portId = "out" },
      to = { moduleId = "blend_simple_inst_1", portId = "a" },
      meta = { source = "test" },
    },
    {
      id = "blend_to_output",
      kind = "audio",
      from = { moduleId = "blend_simple_inst_1", portId = "out" },
      to = { moduleId = MidiSynthRack.OUTPUT_NODE_ID, portId = MidiSynthRack.OUTPUT_PORT_ID },
      meta = { source = "test" },
    },
  }

  local description = MidiSynthRack.describeAudioStageSequence(connections, modules)
  assertEqual(description.sourceNodeIds[1], "rack_sample_inst_1", "dynamic sample chosen as primary serial source")
  assertEqual(description.stageNodeIds[1], "blend_simple_inst_1", "blend stage follows dynamic sample source")
end

local tests = {
  testSpecMetadataNormalization,
  testPaletteTemplateCatalog,
  testAuxiliaryAudioConnectionsSurviveNormalization,
  testDynamicSourceDrivesSerialStageSelection,
}

for i = 1, #tests do
  tests[i]()
end

print(string.format("OK rack_midisynth_specs %d tests", #tests))

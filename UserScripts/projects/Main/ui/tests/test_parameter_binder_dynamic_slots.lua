package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local ParameterBinder = require("parameter_binder")

local function assertTrue(value, message)
  if not value then
    error(message or "assertTrue failed", 2)
  end
end

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEqual failed") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)), 2)
  end
end

local function hasPath(schema, target)
  for i = 1, #(schema or {}) do
    local entry = schema[i]
    if tostring(entry and entry.path or "") == tostring(target or "") then
      return true
    end
  end
  return false
end

local function testBaseSchemaPrewarmsExpandedSlotPools()
  local schema = ParameterBinder.buildSchema({
    fxOptionCount = 21,
    maxFxParams = 5,
    oscRenderStandard = 0,
    oscModeClassic = 0,
    sampleSourceLive = 0,
    sampleSourceLayerMax = 4,
    samplePitchModeClassic = 0,
    samplePitchModeMax = 2,
  })

  assertTrue(hasPath(schema, "/midi/synth/output"), "base schema still registers core params")
  assertTrue(hasPath(schema, "/midi/synth/rack/lfo/1/rate"), "base schema prewarms first lfo slot")
  assertTrue(hasPath(schema, "/midi/synth/rack/lfo/128/rate"), "base schema prewarms expanded lfo pool")
  assertTrue(hasPath(schema, "/midi/synth/rack/osc/32/output"), "base schema prewarms expanded oscillator pool")
end

local function testBuildDynamicSlotSchemaForArbitrarySlot()
  local lfoSchema = ParameterBinder.buildDynamicSlotSchema("lfo", 12, { voiceCount = 8 })
  assertTrue(hasPath(lfoSchema, "/midi/synth/rack/lfo/12/rate"), "lfo dynamic slot schema uses requested slot")
  assertTrue(hasPath(lfoSchema, "/midi/synth/rack/lfo/12/retrig"), "lfo retrig path present")

  local oscSchema = ParameterBinder.buildDynamicSlotSchema("rack_oscillator", 5, { voiceCount = 8, oscRenderStandard = 0 })
  assertTrue(hasPath(oscSchema, "/midi/synth/rack/osc/5/output"), "osc output path present")
  assertTrue(hasPath(oscSchema, "/midi/synth/rack/osc/5/voice/8/pwCv"), "osc voice path scales to requested slot")

  local sampleSchema = ParameterBinder.buildDynamicSlotSchema("rack_sample", 7, { voiceCount = 8 })
  assertTrue(hasPath(sampleSchema, "/midi/synth/rack/sample/7/output"), "sample output path present")
  assertTrue(hasPath(sampleSchema, "/midi/synth/rack/sample/7/voice/8/vOct"), "sample voice path scales to requested slot")
  assertTrue(hasPath(sampleSchema, "/midi/synth/rack/sample/7/captureWriteOffset"), "sample write-offset readback path present")
end

local function testMatchDynamicModulePath()
  local specId, slotIndex = ParameterBinder.matchDynamicModulePath("/midi/synth/rack/eq/14/band/3/gain")
  assertEqual(specId, "eq", "eq band path resolves spec id")
  assertEqual(slotIndex, 14, "eq band path resolves slot index")

  specId, slotIndex = ParameterBinder.matchDynamicModulePath("/midi/synth/rack/osc/27/voice/3/gate")
  assertEqual(specId, "rack_oscillator", "osc voice path resolves spec id")
  assertEqual(slotIndex, 27, "osc voice path resolves slot index")

  specId, slotIndex = ParameterBinder.matchDynamicModulePath("/midi/synth/rack/sample_hold/9/mode")
  assertEqual(specId, "sample_hold", "sample hold path resolves spec id")
  assertEqual(slotIndex, 9, "sample hold path resolves slot index")

  specId, slotIndex = ParameterBinder.matchDynamicModulePath("/midi/synth/rack/sample/3/rootNote")
  assertEqual(specId, "rack_sample", "rack sample path resolves spec id")
  assertEqual(slotIndex, 3, "rack sample path resolves slot index")
end

local tests = {
  testBaseSchemaPrewarmsExpandedSlotPools,
  testBuildDynamicSlotSchemaForArbitrarySlot,
  testMatchDynamicModulePath,
}

for i = 1, #tests do
  tests[i]()
end

print(string.format("OK parameter_binder_dynamic_slots %d tests", #tests))

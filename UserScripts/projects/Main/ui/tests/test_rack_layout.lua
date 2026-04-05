package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. package.path

local Rack = require("behaviors.rack_layout")
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

local function moduleById(modules, id)
  for i = 1, #modules do
    if modules[i].id == id then
      return modules[i]
    end
  end
  error("module not found: " .. tostring(id), 2)
end

local function testDefaultRackState()
  local state = Rack.defaultRackState()
  assertEqual(state.viewMode, "perf", "default view mode")
  assertEqual(state.densityMode, "normal", "default density mode")
  assertTrue(type(state.utilityDock) == "table", "utility dock exists")
  assertEqual(state.utilityDock.mode, "full_keyboard", "default utility dock mode")
  assertEqual(state.utilityDock.heightMode, "full", "default utility dock height")
end

local function testCellLevelOccupancyForTallModule()
  local modules = {
    { id = "adsr", row = 0, col = 0, w = 1, h = 1 },
    { id = "osc", row = 0, col = 1, w = 1, h = 2 },
  }
  local occupancy = Rack.buildOccupancy(modules)
  assertEqual(occupancy.cells["0:1"], "osc", "top cell occupied by tall module")
  assertEqual(occupancy.cells["1:1"], "osc", "bottom cell occupied by tall module")
  assertTrue(not Rack.isAreaFree(modules, 1, 1, 1, 1), "occupied lower tall-module cell should block placement")
  assertTrue(Rack.isAreaFree(modules, 1, 2, 1, 1), "adjacent free cell should be available")
end

local function testSameRowReorderPreservesSizes()
  local modules = {
    { id = "adsr", row = 0, col = 0, w = 1, h = 1 },
    { id = "osc", row = 0, col = 1, w = 2, h = 1 },
    { id = "filter", row = 0, col = 3, w = 1, h = 1 },
  }
  local moved = Rack.moveModuleWithinRow(modules, "filter", 2)
  local adsr = moduleById(moved, "adsr")
  local filter = moduleById(moved, "filter")
  local osc = moduleById(moved, "osc")

  assertEqual(adsr.col, 0, "adsr stays first")
  assertEqual(filter.col, 1, "filter inserted second")
  assertEqual(osc.col, 2, "wide osc shifted right")
  assertEqual(adsr.w, 1, "adsr width preserved")
  assertEqual(filter.w, 1, "filter width preserved")
  assertEqual(osc.w, 2, "osc width preserved")
end

local function testWideNodeReorderPreservesPackedStrip()
  local modules = {
    { id = "adsr", row = 0, col = 0, w = 1, h = 1 },
    { id = "osc", row = 0, col = 1, w = 2, h = 1 },
    { id = "filter", row = 0, col = 3, w = 1, h = 1 },
  }
  local moved = Rack.moveModuleWithinRow(modules, "osc", 1)
  local osc = moduleById(moved, "osc")
  local adsr = moduleById(moved, "adsr")
  local filter = moduleById(moved, "filter")

  assertEqual(osc.col, 0, "wide node repacks to row start")
  assertEqual(adsr.col, 2, "narrow node shifted after wide node")
  assertEqual(filter.col, 3, "tail node remains packed after reorder")
  assertEqual(osc.w, 2, "wide node width preserved")
end

local function testFlowReorderWrapsAcrossRows()
  local modules = {
    { id = "adsr", row = 0, col = 0, w = 1, h = 1 },
    { id = "osc", row = 0, col = 1, w = 2, h = 1 },
    { id = "filter", row = 0, col = 3, w = 2, h = 1 },
    { id = "fx1", row = 1, col = 0, w = 2, h = 1 },
    { id = "fx2", row = 1, col = 2, w = 2, h = 1 },
    { id = "eq", row = 1, col = 4, w = 1, h = 1 },
  }
  local moved = Rack.moveModuleInFlow(modules, "eq", 2, 5, 0)
  local adsr = moduleById(moved, "adsr")
  local eq = moduleById(moved, "eq")
  local osc = moduleById(moved, "osc")
  local filter = moduleById(moved, "filter")

  assertEqual(adsr.row, 0, "adsr remains in first row")
  assertEqual(eq.row, 0, "eq wraps into first row after insert")
  assertEqual(eq.col, 1, "eq placed after adsr in flow")
  assertEqual(osc.row, 0, "osc stays in first row")
  assertEqual(osc.col, 2, "osc shifted right after eq insert")
  assertEqual(filter.row, 1, "filter wraps to second row after overflow")
  assertEqual(filter.col, 0, "filter becomes first item in wrapped second row")
end

local function testRackConnectionShape()
  local connection = Rack.makeRackConnection {
    id = "filter_to_fx1",
    kind = "audio",
    from = { moduleId = "filter", portId = "audio_out" },
    to = { moduleId = "fx1", portId = "audio_in" },
  }
  assertEqual(connection.id, "filter_to_fx1", "connection id")
  assertEqual(connection.kind, "audio", "connection kind")
  assertEqual(connection.from.moduleId, "filter", "from module")
  assertEqual(connection.to.moduleId, "fx1", "to module")
end
local function testMidiSynthRackSeedData()
  local state = MidiSynthRack.defaultRackState()
  local specs = MidiSynthRack.rackModuleSpecById()
  local connections = MidiSynthRack.defaultConnections()
  assertEqual(#state.modules, 9, "default MidiSynth rack module count")
  assertTrue(specs.adsr ~= nil, "ADSR module spec exists")
  assertTrue(specs.oscillator ~= nil, "Oscillator module spec exists")
  assertEqual(moduleById(state.modules, "oscillator").w, 2, "oscillator default width")
  assertEqual(moduleById(state.modules, "eq").col, 4, "eq seeded at row tail")
  assertEqual(#connections, 7, "default connection count")
  assertEqual(connections[4].meta.route, "relay", "cross-row relay preserved in seed data")
end

local function testRackStateSanitizeAndSerialize()
  local state = Rack.sanitizeRackState {
    viewMode = "patch",
    densityMode = "compact",
    utilityDock = { visible = false, mode = "hidden", heightMode = "collapsed" },
    modules = {
      { id = "adsr", row = 0, col = 0, w = 1, h = 1 },
      { id = "oscillator", row = 0, col = 1, w = 2, h = 1 },
    },
  }
  local text = Rack.serializeLuaLiteral(state)
  assertEqual(state.viewMode, "patch", "view mode preserved")
  assertEqual(state.utilityDock.mode, "hidden", "dock mode preserved")
  assertTrue(text:match("viewMode"), "serialized rack state contains view mode")
  assertTrue(text:match("oscillator"), "serialized rack state contains module ids")
end

local tests = {
  testDefaultRackState,
  testCellLevelOccupancyForTallModule,
  testSameRowReorderPreservesSizes,
  testWideNodeReorderPreservesPackedStrip,
  testFlowReorderWrapsAcrossRows,
  testRackConnectionShape,
  testMidiSynthRackSeedData,
  testRackStateSanitizeAndSerialize,
}

for i = 1, #tests do
  tests[i]()
end

print(string.format("OK rack_layout %d tests", #tests))

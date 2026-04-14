package.path = "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/ui/?/init.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?.lua;"
  .. "/home/shamanic/dev/my-plugin/UserScripts/projects/Main/lib/?/init.lua;"
  .. package.path

local SampleSynth = require("sample_synth")

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

local function makeGainNode()
  local node = { gain = 1.0 }
  function node:setGain(value) self.gain = value end
  node.__node = node
  return node
end

local function makeCaptureNode(captureSize)
  local node = {
    writeOffset = 0,
    captureSize = captureSize or 100,
    captureSeconds = 0,
    freeCaptureStartOffset = 0,
    captureNowSamples = 0,
  }
  function node:setCaptureSeconds(value) self.captureSeconds = value end
  function node:getWriteOffset() return self.writeOffset end
  function node:getCaptureSize() return self.captureSize end
  function node:setFreeCaptureStartOffset(value) self.freeCaptureStartOffset = value end
  function node:captureNow(value) self.captureNowSamples = value end
  node.__node = node
  return node
end

local function buildCtx()
  return {
    host = {
      getParam = function(path)
        if path == "/core/behavior/samplesPerBar" then
          return 48000
        end
        if path == "/core/behavior/tempo" then
          return 120
        end
        return 0
      end,
      getSampleRate = function()
        return 48000
      end,
    },
    graph = {
      connect = function() end,
    },
    primitives = {
      GainNode = { new = function() return makeGainNode() end },
      RetrospectiveCaptureNode = { new = function() return makeCaptureNode(100) end },
    },
  }
end

local function createSynth()
  local capture = makeCaptureNode(100)
  local synth = SampleSynth.create(buildCtx(), {
    defaultSourceId = 1,
    sourceSpecs = {
      { id = 1, name = "Live", node = makeGainNode(), capture = capture },
    },
  })
  local entry = synth.getSelectedSourceEntry()
  entry.capture = capture
  return synth, capture
end

local function testFreeTriggerStartsAndStopsUsingSharedRuntimeOffsets()
  local synth, capture = createSynth()
  synth.setCaptureMode(1)

  capture.writeOffset = 12
  local request = synth.triggerCapture()
  assertEqual(request, nil, "first free trigger should arm, not capture immediately")
  assertTrue(synth.getCaptureRecording(), "free trigger should enter recording state")
  assertEqual(synth.getCaptureStartOffset(), 12, "shared runtime should store capture start offset")

  capture.writeOffset = 37
  request = synth.triggerCapture()
  assertTrue(type(request) == "table", "second free trigger should produce a capture request")
  assertEqual(request.samplesBack, 25, "capture request should use exact start->end span")
  assertEqual(request.startOffset, 12, "capture request should expose start offset")
  assertEqual(request.endOffset, 37, "capture request should expose end offset")
  assertEqual(synth.getCaptureRecording(), false, "stop should leave recording state")
end

local function testFreeTriggerImmediateStopDoesNotWrapWholeBuffer()
  local synth, capture = createSynth()
  synth.setCaptureMode(1)

  capture.writeOffset = 50
  synth.triggerCapture()
  capture.writeOffset = 50
  local request = synth.triggerCapture()

  assertTrue(type(request) == "table", "immediate stop should still produce a capture request")
  assertEqual(request.samplesBack, 1, "same-offset stop should clamp to a tiny capture, not wrap the whole buffer")
end

local function testFreeTriggerWrapsAcrossCircularBuffer()
  local synth, capture = createSynth()
  synth.setCaptureMode(1)

  capture.writeOffset = 98
  synth.triggerCapture()
  capture.writeOffset = 5
  local request = synth.triggerCapture()

  assertTrue(type(request) == "table", "wrapped stop should produce a capture request")
  assertEqual(request.samplesBack, 7, "wrapped free capture should measure across circular buffer")
end

local tests = {
  testFreeTriggerStartsAndStopsUsingSharedRuntimeOffsets,
  testFreeTriggerImmediateStopDoesNotWrapWholeBuffer,
  testFreeTriggerWrapsAcrossCircularBuffer,
}

for i = 1, #tests do
  tests[i]()
end

print(string.format("OK sample_synth_capture %d tests", #tests))

#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/scripting/ScriptableProcessor.h"
#include "../primitives/control/OSCEndpointRegistry.h"
#include "../primitives/control/OSCQuery.h"
#include "../primitives/control/OSCServer.h"
#include "../primitives/control/EndpointResolver.h"
#include "../primitives/control/CommandParser.h"
#include "../primitives/dsp/CaptureBuffer.h"
#include "../engine/ManifoldLayer.h"

#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

class MockScriptableProcessor : public ScriptableProcessor {
public:
  MockScriptableProcessor() {
    capture.setSize(512);
    capture.setNumChannels(2);
    for (int i = 0; i < capture.getSize(); ++i) {
      float sample = std::sin(2.0f * 3.14159265f * (float)i / 32.0f) * 0.25f;
      capture.write(sample, 0);
      capture.write(sample, 1);
    }

    for (int i = 0; i < getNumLayers(); ++i) {
      layers[(size_t)i].copyFromCapture(capture, 0, 128, false);
      layers[(size_t)i].setVolume(1.0f);
      layers[(size_t)i].setSpeed(1.0f);
      layers[(size_t)i].setReversed(false);
    }
  }

  bool postControlCommandPayload(const ControlCommand &command) override {
    commands.push_back(command);

    if (command.type == ControlCommand::Type::SetTempo) {
      tempo = command.floatParam;
    }
    return true;
  }

  bool postControlCommand(ControlCommand::Type type, int intParam,
                          float floatParam) override {
    ControlCommand cmd;
    cmd.operation = ControlOperation::Legacy;
    cmd.type = type;
    cmd.intParam = intParam;
    cmd.floatParam = floatParam;
    return postControlCommandPayload(cmd);
  }

  ControlServer &getControlServer() override { return controlServer; }
  OSCServer &getOSCServer() override { return oscServer; }
  OSCEndpointRegistry &getEndpointRegistry() override { return endpointRegistry; }
  OSCQueryServer &getOSCQueryServer() override { return oscQueryServer; }

  // Generic path-based parameter access
  bool setParamByPath(const std::string &path, float value) override {
    ParseResult result = CommandParser::buildResolverSetCommand(
        &endpointRegistry, juce::String(path), juce::var(value));
    if (result.kind != ParseResult::Kind::Enqueue) {
      return false;
    }
    return postControlCommandPayload(result.command);
  }

  float getParamByPath(const std::string &path) const override {
    if (path == "/looper/tempo") return tempo;
    if (path == "/looper/targetbpm") return targetBPM;
    if (path == "/looper/volume") return masterVolume;
    if (path == "/looper/inputVolume") return inputVolume;
    if (path == "/looper/passthrough") return passthroughEnabled ? 1.0f : 0.0f;
    if (path == "/looper/recording") return isRecordingFlag ? 1.0f : 0.0f;
    if (path == "/looper/overdub") return overdubEnabled ? 1.0f : 0.0f;
    if (path == "/looper/layer") return static_cast<float>(activeLayer);
    if (path == "/looper/forwardArmed") return forwardArmed ? 1.0f : 0.0f;
    if (path == "/looper/forwardBars") return forwardBars;
    if (path == "/looper/samplesPerBar") return samplesPerBar;
    if (path == "/looper/sampleRate") return static_cast<float>(sampleRate);
    if (path == "/looper/captureSize") return static_cast<float>(capture.getSize());
    if (path == "/looper/mode") return static_cast<float>(recordModeIndex);
    if (path == "/looper/commitCount") return static_cast<float>(commitCount);

    // Layer paths
    if (path.find("/looper/layer/") == 0) {
      int layerIdx = -1;
      if (sscanf(path.c_str(), "/looper/layer/%d/", &layerIdx) == 1 &&
          layerIdx >= 0 && layerIdx < getNumLayers()) {
        size_t slashPos = path.find('/', 14);
        if (slashPos != std::string::npos) {
          std::string rest = path.substr(slashPos + 1);
          const auto &layer = layers[(size_t)layerIdx];
          if (rest == "speed") return layer.getSpeed();
          if (rest == "volume") return layer.getVolume();
          if (rest == "reverse") return layer.isReversed() ? 1.0f : 0.0f;
          if (rest == "length") return static_cast<float>(layer.getLength());
          if (rest == "position") {
            int len = layer.getLength();
            return (len > 0) ? static_cast<float>(layer.getPosition()) / static_cast<float>(len) : 0.0f;
          }
        }
      }
    }

    return 0.0f;
  }

  bool hasEndpoint(const std::string &path) const override {
    OSCEndpoint endpoint = endpointRegistry.findEndpoint(juce::String(path));
    return endpoint.path.isNotEmpty();
  }

  int getNumLayers() const override { return 4; }
  bool getLayerSnapshot(int index, ScriptableLayerSnapshot &out) const override {
    if (index < 0 || index >= getNumLayers()) {
      return false;
    }

    const auto &layer = layers[(size_t)index];
    out.index = index;
    out.length = layer.getLength();
    out.position = layer.getPosition();
    out.speed = layer.getSpeed();
    out.reversed = layer.isReversed();
    out.volume = layer.getVolume();
    out.state = static_cast<ScriptableLayerState>(layer.getState());
    return true;
  }
  int getCaptureSize() const override { return capture.getSize(); }

  bool computeLayerPeaks(int layerIndex, int numBuckets,
                         std::vector<float> &outPeaks) const override {
    outPeaks.clear();
    if (layerIndex < 0 || layerIndex >= getNumLayers() || numBuckets <= 0) {
      return false;
    }

    outPeaks.assign((size_t)numBuckets, 0.5f);
    return true;
  }

  bool computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                           std::vector<float> &outPeaks) const override {
    outPeaks.clear();
    if (numBuckets <= 0 || endAgo <= startAgo) {
      return false;
    }

    outPeaks.assign((size_t)numBuckets, 0.25f);
    return true;
  }

  float getTempo() const override { return tempo; }
  float getTargetBPM() const override { return targetBPM; }
  float getSamplesPerBar() const override { return samplesPerBar; }
  double getSampleRate() const override { return sampleRate; }
  double getPlayTimeSamples() const override { return 0.0; }
  float getMasterVolume() const override { return masterVolume; }
  float getInputVolume() const override { return inputVolume; }
  bool isPassthroughEnabled() const override { return passthroughEnabled; }
  bool isRecording() const override { return isRecordingFlag; }
  bool isOverdubEnabled() const override { return overdubEnabled; }
  int getActiveLayerIndex() const override { return activeLayer; }
  bool isForwardCommitArmed() const override { return forwardArmed; }
  float getForwardCommitBars() const override { return forwardBars; }
  int getRecordModeIndex() const override { return recordModeIndex; }
  int getCommitCount() const override { return commitCount; }
  std::array<float, 32> getSpectrumData() const override { return spectrum; }

  const std::vector<ControlCommand> &getCommands() const { return commands; }

private:
  OSCServer oscServer;
  ControlServer controlServer;
  OSCEndpointRegistry endpointRegistry;
  OSCQueryServer oscQueryServer;

  CaptureBuffer capture;
  std::array<ManifoldLayer, 4> layers;

  float tempo = 120.0f;
  float targetBPM = 120.0f;
  float samplesPerBar = 88200.0f;
  double sampleRate = 44100.0;
  float masterVolume = 1.0f;
  float inputVolume = 1.0f;
  bool passthroughEnabled = true;
  bool isRecordingFlag = false;
  bool overdubEnabled = false;
  int activeLayer = 0;
  bool forwardArmed = false;
  float forwardBars = 0.0f;
  int recordModeIndex = 0;
  std::array<float, 32> spectrum{};
  int commitCount = 0;

  std::vector<ControlCommand> commands;
};

int main() {
  juce::ScopedJuceInitialiser_GUI juceInit;

  MockScriptableProcessor mock;
  Canvas root("root");
  LuaEngine engine;
  engine.initialise(&mock, &root);

  juce::File script = juce::File::getSpecialLocation(juce::File::tempDirectory)
                          .getChildFile("lua_engine_mock_harness.lua");

  const juce::String scriptSource = juce::String(R"(
sent = false

local function nearly(a, b)
  if a == nil or b == nil then
    return false
  end
  return math.abs(a - b) < 0.0001
end

local function bool01(v)
  if v then
    return 1
  end
  return 0
end

function ui_init(root)
end

function ui_update(state)
  if sent then
    return
  end

  if not (state and state.params and state.voices and state.numVoices == 4) then
    return
  end

  if #state.voices ~= state.numVoices then
    return
  end

  local params = state.params
  local ok = true
  ok = ok and nearly(params["/looper/tempo"], 120)
  ok = ok and nearly(params["/looper/targetbpm"], 120)
  ok = ok and nearly(params["/looper/samplesPerBar"], 88200)
  ok = ok and nearly(params["/looper/sampleRate"], 44100)
  ok = ok and nearly(params["/looper/captureSize"], 512)
  ok = ok and nearly(params["/looper/volume"], 1.0)
  ok = ok and params["/looper/recording"] == 0
  ok = ok and params["/looper/overdub"] == 0
  ok = ok and params["/looper/mode"] == "firstLoop"
  ok = ok and params["/looper/layer"] == 0
  ok = ok and params["/looper/forwardArmed"] == 0
  ok = ok and nearly(params["/looper/forwardBars"], 0)

  -- Test hasEndpoint
  ok = ok and hasEndpoint("/looper/tempo") == true
  ok = ok and hasEndpoint("/looper/layer/0/speed") == true
  ok = ok and hasEndpoint("/nonexistent/path") == false

  -- Test getParam
  ok = ok and nearly(getParam("/looper/tempo"), 120)
  ok = ok and nearly(getParam("/looper/volume"), 1.0)
  ok = ok and nearly(getParam("/looper/layer/0/speed"), 1.0)
  ok = ok and nearly(getParam("/nonexistent/path"), 0.0)

  for i = 1, state.numVoices do
    local voice = state.voices[i]
    if not voice then
      ok = false
      break
    end

    local layerIndex = i - 1
    local layerPrefix = string.format("/looper/layer/%d", layerIndex)
    local positionNorm = 0
    if voice.length and voice.length > 0 then
      positionNorm = (voice.position or 0) / voice.length
    end

    ok = ok and voice.id == layerIndex
    ok = ok and voice.path == layerPrefix
    ok = ok and voice.state ~= nil
    ok = ok and nearly(voice.positionNorm, positionNorm)

    local voiceParams = voice.params
    ok = ok and voiceParams ~= nil
    ok = ok and nearly(voiceParams.speed, voice.speed)
    ok = ok and nearly(voiceParams.volume, voice.volume)
    ok = ok and voiceParams.mute == params[layerPrefix .. "/mute"]
    ok = ok and voiceParams.reverse == bool01(voice.reversed)
    ok = ok and nearly(voiceParams.length, voice.length)
    ok = ok and nearly(voiceParams.position, positionNorm)
    ok = ok and nearly(voiceParams.bars, params[layerPrefix .. "/bars"])
    ok = ok and voiceParams.state == voice.state

    ok = ok and nearly(params[layerPrefix .. "/speed"], voice.speed)
    ok = ok and nearly(params[layerPrefix .. "/volume"], voice.volume)
    ok = ok and params[layerPrefix .. "/mute"] == bool01(voice.state == "muted")
    ok = ok and params[layerPrefix .. "/reverse"] == bool01(voice.reversed)
    ok = ok and nearly(params[layerPrefix .. "/length"], voice.length)
    ok = ok and nearly(params[layerPrefix .. "/position"], positionNorm)
    ok = ok and nearly(params[layerPrefix .. "/bars"], voice.bars)
    ok = ok and params[layerPrefix .. "/state"] == voice.state
    ok = ok and nearly(voice.bars, params[layerPrefix .. "/bars"])
    ok = ok and nearly(voice.positionNorm, positionNorm)
  end

  if ok then
    -- Test setParam
    local setOk = setParam("/looper/tempo", 135.5)
    ok = ok and setOk == true

    -- Test setParam with invalid path
    local setFail = setParam("/nonexistent/path", 1.0)
    ok = ok and setFail == false

    -- Test Primitives factories exist (Phase 2)
    -- Note: Methods require full usertype registration - just verify factories work
    local LoopBuffer = Primitives.LoopBuffer
    local buf = LoopBuffer.new(44100, 2)
    ok = ok and buf ~= nil

    local Playhead = Primitives.Playhead
    local ph = Playhead.new(44100)
    ok = ok and ph ~= nil

    local CaptureBuffer = Primitives.CaptureBuffer
    local cap = CaptureBuffer.new(88200, 2)
    ok = ok and cap ~= nil

    local Quantizer = Primitives.Quantizer
    local q = Quantizer.new(48000)
    ok = ok and q ~= nil

    -- Test Primitive Wiring (Phase 3)
    local PlayheadNode = Primitives.PlayheadNode
    local PassthroughNode = Primitives.PassthroughNode
    
    local phNode = PlayheadNode.new()
    ok = ok and phNode ~= nil
    phNode:setLoopLength(44100)
    ok = ok and phNode:getLoopLength() == 44100
    
    local passNode = PassthroughNode.new(2)
    ok = ok and passNode ~= nil
    
    -- Test graph state functions before connection
    local nodeCount = getGraphNodeCount()
    ok = ok and nodeCount >= 2
    
    local connCount = getGraphConnectionCount()
    ok = ok and connCount == 0
    
    -- Connect nodes
    local connected = connectNodes(phNode, passNode)
    ok = ok and connected == true
    
    connCount = getGraphConnectionCount()
    ok = ok and connCount == 1
    
    -- Test cycle detection (should not have cycle)
    local hasCycle = hasGraphCycle()
    ok = ok and hasCycle == false

    sent = true
  end
end
)" )
                                      .trimStart();

  if (!script.replaceWithText(scriptSource)) {
    std::fprintf(stderr, "LuaEngineMockHarness: failed to write temp script\n");
    return 2;
  }

  bool loaded = engine.loadScript(script);
  if (!loaded) {
    std::fprintf(stderr, "LuaEngineMockHarness: loadScript failed: %s\n",
                 engine.getLastError().c_str());
    return 3;
  }

  engine.notifyUpdate();
  engine.notifyUpdate();

  const auto &commands = mock.getCommands();
  if (commands.empty()) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: expected at least one command from Lua\n");
    return 4;
  }

  const auto &first = commands.front();
  if (first.type != ControlCommand::Type::SetTempo) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: expected first command SetTempo\n");
    return 5;
  }

  // setParam was called with 135.5
  if (std::abs(first.floatParam - 135.5f) > 0.1f) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: expected tempo 135.5, got %.3f\n",
                 first.floatParam);
    return 6;
  }

  juce::File endpointScript =
      juce::File::getSpecialLocation(juce::File::tempDirectory)
          .getChildFile("lua_engine_endpoint_harness.lua");
  juce::File plainScript =
      juce::File::getSpecialLocation(juce::File::tempDirectory)
          .getChildFile("lua_engine_plain_harness.lua");

  const juce::String endpointScriptSource = juce::String(R"(
function ui_init(root)
  osc.registerEndpoint("/experimental/temp", {
    type = "f",
    access = 3,
    description = "temporary endpoint"
  })
end

function ui_update(state)
end
)" )
                                            .trimStart();

  const juce::String plainScriptSource = juce::String(R"(
function ui_init(root)
end

function ui_update(state)
end
)" )
                                        .trimStart();

  if (!endpointScript.replaceWithText(endpointScriptSource) ||
      !plainScript.replaceWithText(plainScriptSource)) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: failed to write endpoint lifecycle scripts\n");
    return 7;
  }

  if (!engine.loadScript(endpointScript)) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: failed to load endpoint script: %s\n",
                 engine.getLastError().c_str());
    return 8;
  }

  auto registered =
      mock.getEndpointRegistry().findEndpoint("/experimental/temp");
  if (registered.path.isEmpty()) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: expected custom endpoint to be registered\n");
    return 9;
  }

  if (!engine.switchScript(plainScript)) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: failed to switch to plain script: %s\n",
                 engine.getLastError().c_str());
    return 10;
  }

  auto afterSwitch =
      mock.getEndpointRegistry().findEndpoint("/experimental/temp");
  if (!afterSwitch.path.isEmpty()) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: stale custom endpoint remained after switch\n");
    return 11;
  }

  std::fprintf(stdout,
               "LuaEngineMockHarness: PASS (commands=%zu, first=SetTempo %.1f via setParam)\n",
               commands.size(), first.floatParam);

  return 0;
}

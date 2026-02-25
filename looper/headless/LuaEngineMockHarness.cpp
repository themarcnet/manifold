#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/scripting/ScriptableProcessor.h"
#include "../primitives/control/OSCEndpointRegistry.h"
#include "../primitives/control/OSCQuery.h"
#include "../primitives/control/OSCServer.h"
#include "../primitives/dsp/CaptureBuffer.h"
#include "../engine/LooperLayer.h"

#include <array>
#include <cmath>
#include <cstdio>
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

  OSCServer &getOSCServer() override { return oscServer; }
  OSCEndpointRegistry &getEndpointRegistry() override { return endpointRegistry; }
  OSCQueryServer &getOSCQueryServer() override { return oscQueryServer; }

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
  float getMasterVolume() const override { return masterVolume; }
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
  std::array<LooperLayer, 4> layers;

  float tempo = 120.0f;
  float targetBPM = 120.0f;
  float samplesPerBar = 88200.0f;
  double sampleRate = 44100.0;
  float masterVolume = 1.0f;
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

  if not (state and state.params and state.layers and state.voices and state.numVoices == 4) then
    return
  end

  if #state.layers ~= state.numVoices or #state.voices ~= state.numVoices then
    return
  end

  local ok = true
  ok = ok and nearly(state.params["/looper/tempo"], state.tempo)
  ok = ok and nearly(state.params["/looper/targetbpm"], state.targetBPM)
  ok = ok and nearly(state.params["/looper/samplesPerBar"], state.samplesPerBar)
  ok = ok and nearly(state.params["/looper/sampleRate"], state.sampleRate)
  ok = ok and nearly(state.params["/looper/captureSize"], state.captureSize)
  ok = ok and nearly(state.params["/looper/volume"], state.masterVolume)
  ok = ok and state.params["/looper/recording"] == bool01(state.isRecording)
  ok = ok and state.params["/looper/overdub"] == bool01(state.overdubEnabled)
  ok = ok and state.params["/looper/mode"] == state.recordMode
  ok = ok and state.params["/looper/layer"] == state.activeLayer
  ok = ok and state.params["/looper/forwardArmed"] == bool01(state.forwardArmed)
  ok = ok and nearly(state.params["/looper/forwardBars"], state.forwardBars)

  for i = 1, state.numVoices do
    local layer = state.layers[i]
    local voice = state.voices[i]
    if not (layer and voice) then
      ok = false
      break
    end

    local layerIndex = i - 1
    local layerPrefix = string.format("/looper/layer/%d", layerIndex)
    local positionNorm = 0
    if layer.length and layer.length > 0 then
      positionNorm = (layer.position or 0) / layer.length
    end

    ok = ok and layer.index == layerIndex
    ok = ok and voice.id == layerIndex
    ok = ok and voice.path == layerPrefix
    ok = ok and voice.state == layer.state
    ok = ok and nearly(voice.length, layer.length)
    ok = ok and nearly(voice.position, layer.position)
    ok = ok and nearly(voice.positionNorm, positionNorm)
    ok = ok and nearly(voice.speed, layer.speed)
    ok = ok and voice.reversed == layer.reversed
    ok = ok and nearly(voice.volume, layer.volume)
    ok = ok and nearly(voice.bars, state.params[layerPrefix .. "/bars"])

    local voiceParams = voice.params
    ok = ok and voiceParams ~= nil
    ok = ok and nearly(voiceParams.speed, layer.speed)
    ok = ok and nearly(voiceParams.volume, layer.volume)
    ok = ok and voiceParams.reverse == bool01(layer.reversed)
    ok = ok and nearly(voiceParams.length, layer.length)
    ok = ok and nearly(voiceParams.position, positionNorm)
    ok = ok and nearly(voiceParams.bars, state.params[layerPrefix .. "/bars"])
    ok = ok and voiceParams.state == layer.state

    ok = ok and nearly(state.params[layerPrefix .. "/speed"], layer.speed)
    ok = ok and nearly(state.params[layerPrefix .. "/volume"], layer.volume)
    ok = ok and state.params[layerPrefix .. "/reverse"] == bool01(layer.reversed)
    ok = ok and nearly(state.params[layerPrefix .. "/length"], layer.length)
    ok = ok and nearly(state.params[layerPrefix .. "/position"], positionNorm)
    ok = ok and state.params[layerPrefix .. "/state"] == layer.state
  end

  if ok then
    command("SET", "/looper/tempo", 130)
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

  if (std::abs(first.floatParam - 130.0f) > 0.1f) {
    std::fprintf(stderr,
                 "LuaEngineMockHarness: expected tempo 130, got %.3f\n",
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
               "LuaEngineMockHarness: PASS (commands=%zu, first=SetTempo %.1f)\n",
               commands.size(), first.floatParam);

  return 0;
}

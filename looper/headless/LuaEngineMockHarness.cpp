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

function ui_init(root)
end

function ui_update(state)
  if sent then
    return
  end

  if state and state.tempo and state.tempo > 119 and state.tempo < 121 and
     state.layers and state.layers[1] and state.layers[1].index == 0 then
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

  std::fprintf(stdout,
               "LuaEngineMockHarness: PASS (commands=%zu, first=SetTempo %.1f)\n",
               commands.size(), first.floatParam);

  return 0;
}

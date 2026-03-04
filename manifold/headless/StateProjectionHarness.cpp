#include "../primitives/control/ControlServer.h"

#include <cmath>
#include <cstdio>

namespace {

bool nearlyEqual(double left, double right, double epsilon = 0.0001) {
  return std::abs(left - right) <= epsilon;
}

double getNumberProperty(const juce::var &objectVar, const juce::Identifier &key,
                         double fallback = 0.0) {
  if (auto *object = objectVar.getDynamicObject()) {
    const juce::var value = object->getProperty(key);
    if (value.isInt() || value.isInt64() || value.isDouble() || value.isBool()) {
      return static_cast<double>(value);
    }
  }

  return fallback;
}

juce::String getStringProperty(const juce::var &objectVar,
                               const juce::Identifier &key,
                               const juce::String &fallback = {}) {
  if (auto *object = objectVar.getDynamicObject()) {
    const juce::var value = object->getProperty(key);
    if (value.isString()) {
      return value.toString();
    }
  }

  return fallback;
}

} // namespace

int main() {
  ControlServer server;
  auto &state = server.getAtomicState();

  state.tempo.store(133.5f);
  state.targetBPM.store(128.25f);
  state.samplesPerBar.store(88200.0f);
  state.sampleRate.store(48000.0);
  state.captureSize.store(2048);
  state.masterVolume.store(0.73f);
  state.activeLayer.store(2);
  state.recordMode.store(1);
  state.isRecording.store(true);
  state.overdubEnabled.store(false);
  state.forwardArmed.store(true);
  state.forwardBars.store(1.5f);

  for (int index = 0; index < AtomicState::MAX_LAYERS; ++index) {
    auto &layer = state.layers[index];
    layer.length.store(1000 * (index + 1));
    layer.playheadPos.store(100 * (index + 1));
    layer.speed.store(0.5f + static_cast<float>(index));
    layer.volume.store(0.25f + static_cast<float>(index) * 0.1f);
    layer.reversed.store((index % 2) == 1);
    layer.numBars.store(0.5f * static_cast<float>(index + 1));
    layer.state.store(index % 7);
  }

  const juce::String stateJson(server.getStateJson());
  const juce::var parsed = juce::JSON::parse(stateJson);
  if (parsed.isVoid()) {
    std::fprintf(stderr, "StateProjectionHarness: FAIL: state JSON did not parse\n");
    return 2;
  }

  int checks = 0;
  auto check = [&](bool condition, const char *message) {
    ++checks;
    if (!condition) {
      std::fprintf(stderr, "StateProjectionHarness: FAIL: %s\n", message);
      std::exit(3);
    }
  };

  check(getNumberProperty(parsed, "projectionVersion") == 2.0,
        "projectionVersion is 2");
  check(getNumberProperty(parsed, "numVoices") == AtomicState::MAX_LAYERS,
        "numVoices matches layer count");

  const auto *rootObject = parsed.getDynamicObject();
  check(rootObject != nullptr, "root object exists");

  check(rootObject->getProperty("tempo").isVoid(),
        "legacy top-level tempo removed");
  check(rootObject->getProperty("masterVolume").isVoid(),
        "legacy top-level masterVolume removed");
  check(rootObject->getProperty("activeLayer").isVoid(),
        "legacy top-level activeLayer removed");
  check(rootObject->getProperty("recordMode").isVoid(),
        "legacy top-level recordMode removed");
  check(rootObject->getProperty("layers").isVoid(),
        "legacy layers array removed");

  const juce::var paramsVar = rootObject->getProperty("params");
  const juce::var voicesVar = rootObject->getProperty("voices");
  const auto *paramsObject = paramsVar.getDynamicObject();
  auto *voicesArray = voicesVar.getArray();

  check(paramsObject != nullptr, "params object exists");
  check(voicesArray != nullptr, "voices array exists");
  check(static_cast<int>(voicesArray->size()) == AtomicState::MAX_LAYERS,
        "voices array has expected entries");

  check(nearlyEqual(static_cast<double>(paramsObject->getProperty("/core/behavior/tempo")),
                    133.5),
        "params tempo matches atomic tempo");
  check(nearlyEqual(static_cast<double>(paramsObject->getProperty("/core/behavior/targetbpm")),
                    128.25),
        "params targetbpm matches atomic targetBPM");
  check(nearlyEqual(
            static_cast<double>(paramsObject->getProperty("/core/behavior/samplesPerBar")),
            88200.0),
        "params samplesPerBar matches atomic samplesPerBar");
  check(nearlyEqual(static_cast<double>(paramsObject->getProperty("/core/behavior/sampleRate")),
                    48000.0),
        "params sampleRate matches atomic sampleRate");
  check(static_cast<int>(paramsObject->getProperty("/core/behavior/captureSize")) == 2048,
        "params captureSize matches atomic captureSize");
  check(static_cast<int>(paramsObject->getProperty("/core/behavior/recording")) == 1,
        "params recording matches atomic recording");
  check(static_cast<int>(paramsObject->getProperty("/core/behavior/overdub")) == 0,
        "params overdub matches atomic overdub");
  check(paramsObject->getProperty("/core/behavior/mode").toString() == "freeMode",
        "params mode matches atomic record mode");
  check(static_cast<int>(paramsObject->getProperty("/core/behavior/layer")) == 2,
        "params layer matches atomic activeLayer");
  check(nearlyEqual(static_cast<double>(paramsObject->getProperty("/core/behavior/volume")),
                    0.73),
        "params volume matches atomic masterVolume");
  check(static_cast<int>(paramsObject->getProperty("/core/behavior/forwardArmed")) == 1,
        "params forwardArmed matches atomic forwardArmed");
  check(nearlyEqual(static_cast<double>(paramsObject->getProperty("/core/behavior/forwardBars")),
                    1.5),
        "params forwardBars matches atomic forwardBars");

  for (int index = 0; index < AtomicState::MAX_LAYERS; ++index) {
    const juce::var &voiceVar = (*voicesArray)[index];

    const juce::String prefix = "/core/behavior/layer/" + juce::String(index);
    const juce::Identifier muteKey(prefix + "/mute");
    const juce::Identifier volumeKey(prefix + "/volume");
    const juce::Identifier reverseKey(prefix + "/reverse");
    const juce::Identifier lengthKey(prefix + "/length");
    const juce::Identifier positionKey(prefix + "/position");
    const juce::Identifier barsKey(prefix + "/bars");
    const juce::Identifier speedKey(prefix + "/speed");
    const juce::Identifier stateKey(prefix + "/state");

    const double voiceLength = getNumberProperty(voiceVar, "length");
    const double voicePosition = getNumberProperty(voiceVar, "position");
    const double expectedPositionNorm =
        (voiceLength > 0.0) ? (voicePosition / voiceLength) : 0.0;
    const auto *voiceObject = voiceVar.getDynamicObject();
    check(voiceObject != nullptr, "voice object exists");
    const juce::var voiceParamsVar = voiceObject->getProperty("params");

    check(getNumberProperty(voiceVar, "id") == index,
          "voice id matches slot");
    check(getStringProperty(voiceVar, "path") == prefix,
          "voice path matches layer prefix");
    check(nearlyEqual(getNumberProperty(voiceVar, "positionNorm"),
                      expectedPositionNorm),
          "voice positionNorm matches normalized voice position");

    check(nearlyEqual(getNumberProperty(voiceVar, "speed"),
                      static_cast<double>(paramsObject->getProperty(speedKey))),
          "params speed matches voice speed");
    check(nearlyEqual(getNumberProperty(voiceVar, "volume"),
                      static_cast<double>(paramsObject->getProperty(volumeKey))),
          "params volume matches voice volume");
    check(getNumberProperty(voiceVar, "reversed") ==
              static_cast<double>(paramsObject->getProperty(reverseKey)),
          "params reverse matches voice reversed");
    check(nearlyEqual(voiceLength,
                      static_cast<double>(paramsObject->getProperty(lengthKey))),
          "params length matches voice length");
    check(nearlyEqual(expectedPositionNorm,
                      static_cast<double>(paramsObject->getProperty(positionKey))),
          "params position matches voice positionNorm");
    check(nearlyEqual(getNumberProperty(voiceVar, "bars"),
                      static_cast<double>(paramsObject->getProperty(barsKey))),
          "params bars matches voice bars");
    check(getStringProperty(voiceVar, "state") ==
              paramsObject->getProperty(stateKey).toString(),
          "params state matches voice state");

    const int expectedMute = getStringProperty(voiceVar, "state") == "muted" ? 1 : 0;
    check(static_cast<int>(paramsObject->getProperty(muteKey)) == expectedMute,
          "params mute matches voice state");

    const auto *voiceParamsObject = voiceParamsVar.getDynamicObject();
    check(voiceParamsObject != nullptr, "voice.params exists");
    check(nearlyEqual(static_cast<double>(voiceParamsObject->getProperty("speed")),
                      getNumberProperty(voiceVar, "speed")),
          "voice.params speed matches voice speed");
    check(nearlyEqual(static_cast<double>(voiceParamsObject->getProperty("volume")),
                      getNumberProperty(voiceVar, "volume")),
          "voice.params volume matches voice volume");
    check(static_cast<int>(voiceParamsObject->getProperty("mute")) == expectedMute,
          "voice.params mute matches voice state");
    check(static_cast<int>(voiceParamsObject->getProperty("reverse")) ==
              static_cast<int>(getNumberProperty(voiceVar, "reversed")),
          "voice.params reverse matches voice reversed");
    check(nearlyEqual(static_cast<double>(voiceParamsObject->getProperty("length")),
                      voiceLength),
          "voice.params length matches voice length");
    check(nearlyEqual(static_cast<double>(voiceParamsObject->getProperty("position")),
                      expectedPositionNorm),
          "voice.params position matches voice positionNorm");
    check(nearlyEqual(static_cast<double>(voiceParamsObject->getProperty("bars")),
                      getNumberProperty(voiceVar, "bars")),
          "voice.params bars matches voice bars");
    check(voiceParamsObject->getProperty("state").toString() ==
              getStringProperty(voiceVar, "state"),
          "voice.params state matches voice state");
  }

  std::fprintf(stdout, "StateProjectionHarness: PASS (%d checks)\n", checks);
  return 0;
}

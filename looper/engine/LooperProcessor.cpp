#include "LooperProcessor.h"
#include "../ui/LooperEditor.h"
#include "../primitives/control/OSCServer.h"
#include "../primitives/control/OSCSettingsPersistence.h"
#include "../primitives/control/CommandParser.h"
#include "../primitives/control/EndpointResolver.h"
#include "../primitives/scripting/GraphRuntime.h"
#include "../primitives/scripting/DSPPluginScriptHost.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace {

float computeBufferRms(const juce::AudioBuffer<float>& buffer, int numSamples) {
  const int channels = juce::jmin(2, buffer.getNumChannels());
  if (channels <= 0 || numSamples <= 0) {
    return 0.0f;
  }

  double sumSq = 0.0;
  int sampleCount = 0;
  for (int ch = 0; ch < channels; ++ch) {
    const float* read = buffer.getReadPointer(ch);
    for (int i = 0; i < numSamples; ++i) {
      const float s = read[i];
      sumSq += static_cast<double>(s) * static_cast<double>(s);
    }
    sampleCount += numSamples;
  }

  if (sampleCount <= 0) {
    return 0.0f;
  }

  return static_cast<float>(std::sqrt(sumSq / static_cast<double>(sampleCount)));
}

} // namespace

LooperProcessor::LooperProcessor()
    : juce::AudioProcessor(
          juce::AudioProcessor::BusesProperties()
              .withInput("Input", juce::AudioChannelSet::stereo(), true)
              .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      primitiveGraph(std::make_shared<dsp_primitives::PrimitiveGraph>()),
      dspScriptHost(std::make_unique<DSPPluginScriptHost>()) {
  dspScriptHost->initialise(this);
}

LooperProcessor::~LooperProcessor() {
    oscQueryServer.stop();
    oscServer.stop();
    controlServer.stop();
}

void LooperProcessor::prepareToPlay(double sampleRate, int samplesPerBlock) {
  currentSampleRate = sampleRate;
  int captureSamples = static_cast<int>(CAPTURE_SECONDS * sampleRate);
  captureBuffer.setSize(captureSamples);
  captureBuffer.setNumChannels(2);
  quantizer.setSampleRate(sampleRate);
  quantizer.setTempo(tempo);
  
  // Prepare DSP primitive graph
  primitiveGraph->prepare(sampleRate, samplesPerBlock);
  
  playTime = 0.0;
  hostTransportPlaying = false;
  hostTimelineSamples = 0.0;

  ensureScratchSize(samplesPerBlock);

  preparedMaxBlockSize = samplesPerBlock;

  // Start control server
  controlServer.start(this);
  
  // Initialize endpoint registry with correct layer count
  endpointRegistry.setNumLayers(MAX_LAYERS);
  endpointRegistry.rebuild();

  if (dspScriptHost && !dspScriptHost->isLoaded()) {
    juce::File defaultDspScript("/home/shamanic/dev/my-plugin/looper/dsp/default_dsp.lua");
    if (defaultDspScript.existsAsFile()) {
      if (!loadDspScript(defaultDspScript)) {
        std::fprintf(stderr, "LooperProcessor: failed to load default DSP script: %s\n",
                     getDspScriptLastError().c_str());
      }
    }
  }

  // Load OSC settings from file (or create defaults)
  OSCSettings oscSettings = OSCSettingsPersistence::load();
  
  // If no settings file existed, save defaults for next time
  auto settingsFile = OSCSettingsPersistence::getSettingsFile();
  if (!settingsFile.existsAsFile()) {
      // Set up reasonable defaults
      oscSettings.oscEnabled = true;
      oscSettings.oscQueryEnabled = true;
      oscSettings.inputPort = 9000;
      oscSettings.queryPort = 9001;
      OSCSettingsPersistence::save(oscSettings);
  }
  
  oscServer.setSettings(oscSettings);
  oscServer.start(this);

  // Start OSCQuery server (HTTP) - uses endpoint registry for dynamic tree
  if (oscSettings.oscQueryEnabled) {
      oscQueryServer.start(this, &endpointRegistry, oscSettings.queryPort, oscSettings.inputPort);
  }

  // Initialize atomic state with static values
  auto &state = controlServer.getAtomicState();
  state.captureSize.store(captureSamples);
  state.tempo.store(tempo);
  state.targetBPM.store(targetBPM);
  state.samplesPerBar.store(getSamplesPerBar());
  state.sampleRate.store(sampleRate);
  state.forwardArmed.store(forwardCommitArmed.load(std::memory_order_relaxed));
  state.forwardBars.store(forwardCommitBars.load(std::memory_order_relaxed));

  // Initialize FFT for spectrum analysis
  fft = std::make_unique<juce::dsp::FFT>(FFT_ORDER);
  fftInput.resize(FFT_SIZE);
  fftOutput.resize(FFT_SIZE * 2);
  std::fill(fftInput.begin(), fftInput.end(), 0.0f);
  fftInputIndex = 0;
  
  // Phase 4: Initialize graph runtime crossfade buffers for 30ms crossfade.
  // Must not allocate in audio thread.
  fadeTotalSamples = static_cast<int>(sampleRate * 0.03); // 30ms
  fadeOldBuffer.setSize(2, samplesPerBlock, false, true);
  fadeNewBuffer.setSize(2, samplesPerBlock, false, true);
  graphDryBuffer.setSize(2, samplesPerBlock, false, true);
}

void LooperProcessor::releaseResources() {
    oscQueryServer.stop();
    oscServer.stop();
    controlServer.stop();
}

void LooperProcessor::processBlock(juce::AudioBuffer<float> &buffer,
                                   juce::MidiBuffer &) {
  auto *inputL = buffer.getWritePointer(0);
  auto *inputR =
      buffer.getNumChannels() > 1 ? buffer.getWritePointer(1) : inputL;
  int numSamples = buffer.getNumSamples();

  ensureScratchSize(numSamples);

  // Pull host transport timing if available.
  updateTransportState();

  // Process pending commands from control server (lock-free)
  processControlCommands();

  // Write to capture buffer: injected audio takes priority over real input.
  // During injection, suppress real input so injected data isn't overwritten
  // by silence/noise from the audio device.
  if (controlServer.isInjecting()) {
    controlServer.drainInjection(captureBuffer, numSamples);
  } else {
    for (int i = 0; i < numSamples; ++i) {
      captureBuffer.write(inputL[i], 0);
      captureBuffer.write(inputR[i], 1);
    }
  }

  // Process FFT for spectrum visualization (use mixed input)
  for (int i = 0; i < numSamples; ++i) {
    float mixedSample = (inputL[i] + inputR[i]) * 0.5f;
    fftInput[fftInputIndex] = mixedSample;
    fftInputIndex = (fftInputIndex + 1) % FFT_SIZE;
  }
  
  // Perform FFT every block (can be optimized to every N blocks)
  if (fft) {
    std::copy(fftInput.begin(), fftInput.end(), fftOutput.begin());
    fft->performRealOnlyForwardTransform(fftOutput.data());
    updateSpectrumBands();
  }

  maybeFireForwardCommit();

  syncLayersToTransportIfNeeded();

  // Mix all layers together using pre-allocated buffers.
  std::fill(layerMixL.begin(), layerMixL.begin() + numSamples, 0.0f);
  std::fill(layerMixR.begin(), layerMixR.begin() + numSamples, 0.0f);

  for (auto &layer : layers) {
    layer.process(tempLayerL.data(), tempLayerR.data(), numSamples);

    for (int i = 0; i < numSamples; ++i) {
      layerMixL[i] += tempLayerL[i];
      layerMixR[i] += tempLayerR[i];
    }
  }

  // Output: dry input (with passthrough toggle and input volume) + wet layers
  float dryGain = passthroughEnabled ? inputVolume * 0.7f : 0.0f;
  for (int i = 0; i < numSamples; ++i) {
    inputL[i] = inputL[i] * dryGain + layerMixL[i] * masterVolume;
    inputR[i] = inputR[i] * dryGain + layerMixR[i] * masterVolume;
  }
  
  // Phase 4: DSP graph processing uses compiled GraphRuntime only.
  // IMPORTANT: Do not call PrimitiveGraph::process() from the audio thread.
  if (graphProcessingEnabled) {
    processGraphRuntime(buffer);
  } else {
    graphInputRms.store(0.0f, std::memory_order_relaxed);
    graphWetRms.store(0.0f, std::memory_order_relaxed);
    graphMixedRms.store(0.0f, std::memory_order_relaxed);
    graphNodeCount.store(0, std::memory_order_relaxed);
    graphRouteCount.store(0, std::memory_order_relaxed);
  }

  if (hostTransportPlaying) {
    playTime = hostTimelineSamples + numSamples;
  } else {
    playTime += numSamples;
  }

  // Update atomic state snapshot for observers
  updateAtomicState(buffer);
}

juce::AudioProcessorEditor *LooperProcessor::createEditor() {
  return new LooperEditor(*this);
}

void LooperProcessor::setActiveLayer(int index) {
  if (index >= 0 && index < MAX_LAYERS)
    activeLayerIndex = index;
}

void LooperProcessor::startRecording() {
  if (isCurrentlyRecording)
    return;
  isCurrentlyRecording = true;
  recordStartTime = playTime;

  // Broadcast event
  char json[256];
  std::snprintf(json, sizeof(json), R"({"type":"record_start","mode":"%s"})",
                recordMode == RecordMode::FirstLoop     ? "firstLoop"
                : recordMode == RecordMode::FreeMode    ? "freeMode"
                : recordMode == RecordMode::Traditional ? "traditional"
                                                        : "retrospective");
  pushEvent(json);
}

void LooperProcessor::startOverdub() { setOverdubEnabled(!overdubEnabled); }

void LooperProcessor::setOverdubEnabled(bool enabled) {
  overdubEnabled = enabled;

  char json[256];
  std::snprintf(json, sizeof(json), R"({"type":"overdub","enabled":%s})",
                overdubEnabled ? "true" : "false");
  pushEvent(json);
}

void LooperProcessor::stopRecording() {
  if (!isCurrentlyRecording)
    return;
  isCurrentlyRecording = false;

  double duration = playTime - recordStartTime;

  switch (recordMode) {
  case RecordMode::FirstLoop:
    processFirstLoopStop();
    break;
  case RecordMode::FreeMode:
    processFreeModeStop();
    break;
  case RecordMode::Traditional:
    processTraditionalStop();
    break;
  case RecordMode::Retrospective:
    break;
  }

  // Broadcast event
  char json[256];
  std::snprintf(json, sizeof(json), R"({"type":"record_stop","duration":%.4f})",
                duration / currentSampleRate);
  pushEvent(json);
}

void LooperProcessor::commitRetrospective(float numBars) {
  if (recordMode == RecordMode::Traditional && !isCurrentlyRecording) {
    scheduleForwardCommit(numBars);
    return;
  }

  commitRetrospectiveNow(numBars, activeLayerIndex,
                         shouldOverdubLayer(activeLayerIndex));
}

void LooperProcessor::scheduleForwardCommit(float numBars) {
  if (numBars <= 0.0f)
    return;

  forwardCommitArmed.store(true, std::memory_order_relaxed);
  forwardCommitBars.store(numBars, std::memory_order_relaxed);
  forwardCommitLayer.store(activeLayerIndex, std::memory_order_relaxed);
  forwardCommitArmPlayTime.store(playTime, std::memory_order_relaxed);

  const int armedLayer = forwardCommitLayer.load(std::memory_order_relaxed);
  const float armedBars = forwardCommitBars.load(std::memory_order_relaxed);

  char json[256];
  std::snprintf(json, sizeof(json),
                R"({"type":"forward_armed","layer":%d,"bars":%.4f})",
                armedLayer, armedBars);
  pushEvent(json);
}

void LooperProcessor::processFirstLoopStop() {
  double duration = playTime - recordStartTime;
  double durationSeconds = duration / currentSampleRate;

  auto result = tempoInference.findBestMatch(durationSeconds, targetBPM, 4);

  if (result.valid) {
    tempo = result.tempo;
    quantizer.setTempo(tempo);

    int samples = static_cast<int>(result.numBars * getSamplesPerBar());
    int startOffset =
        captureBuffer.getOffsetToNow() - static_cast<int>(duration);
    while (startOffset < 0)
      startOffset += captureBuffer.getSize();

    const bool overdub = shouldOverdubLayer(activeLayerIndex);
    layers[activeLayerIndex].copyFromCapture(captureBuffer, startOffset,
                                             samples, overdub);
    ++commitCount;

    // Broadcast events
    char json[256];
    std::snprintf(json, sizeof(json), R"({"type":"tempo","bpm":%.2f})", tempo);
    pushEvent(json);

    std::snprintf(json, sizeof(json),
                  R"({"type":"commit","layer":%d,"bars":%.4f,"tempo":%.2f})",
                  activeLayerIndex, result.numBars, tempo);
    pushEvent(json);
  }
}

void LooperProcessor::processFreeModeStop() {
  double duration = playTime - recordStartTime;
  int quantizedLength = quantizer.quantizeToNearestLegal(duration);

  int startOffset = captureBuffer.getOffsetToNow() - static_cast<int>(duration);
  while (startOffset < 0)
    startOffset += captureBuffer.getSize();

  const bool overdub = shouldOverdubLayer(activeLayerIndex);
  layers[activeLayerIndex].copyFromCapture(captureBuffer, startOffset,
                                           quantizedLength, overdub);
  ++commitCount;

  float numBars = quantizedLength / getSamplesPerBar();

  char json[256];
  std::snprintf(json, sizeof(json),
                R"({"type":"commit","layer":%d,"bars":%.4f,"tempo":%.2f})",
                activeLayerIndex, numBars, tempo);
  pushEvent(json);
}

void LooperProcessor::processTraditionalStop() {
  const double duration = playTime - recordStartTime;
  if (duration <= 0.0)
    return;

  const int quantizedLength = quantizer.quantizeToNearestLegal(duration);
  if (quantizedLength <= 0)
    return;

  const float numBars = quantizedLength / getSamplesPerBar();
  commitRetrospectiveNow(numBars, activeLayerIndex,
                         shouldOverdubLayer(activeLayerIndex));
}

void LooperProcessor::commitRetrospectiveNow(float numBars, int layerIndex,
                                             bool overdub) {
  if (numBars <= 0.0f)
    return;
  if (layerIndex < 0 || layerIndex >= MAX_LAYERS)
    return;

  int samplesBack = static_cast<int>(numBars * getSamplesPerBar());
  if (samplesBack <= 0)
    return;

  int startOffset = captureBuffer.getOffsetToNow() - samplesBack;
  while (startOffset < 0)
    startOffset += captureBuffer.getSize();

  if (overdub)
    layers[layerIndex].overdubFromCapture(captureBuffer, startOffset,
                                          samplesBack);
  else
    layers[layerIndex].copyFromCapture(captureBuffer, startOffset, samplesBack);

  ++commitCount;

  char json[256];
  std::snprintf(json, sizeof(json),
                R"({"type":"commit","layer":%d,"bars":%.4f,"tempo":%.2f})",
                layerIndex, numBars, tempo);
  pushEvent(json);
}

void LooperProcessor::maybeFireForwardCommit() {
  if (!forwardCommitArmed.load(std::memory_order_relaxed))
    return;

  const float bars = forwardCommitBars.load(std::memory_order_relaxed);
  const double armPlayTime =
      forwardCommitArmPlayTime.load(std::memory_order_relaxed);
  const double waitSamples = bars * getSamplesPerBar();
  if ((playTime - armPlayTime) < waitSamples)
    return;

  forwardCommitArmed.store(false, std::memory_order_relaxed);
  const int layer = forwardCommitLayer.load(std::memory_order_relaxed);
  commitRetrospectiveNow(bars, layer, shouldOverdubLayer(layer));

  char json[256];
  std::snprintf(json, sizeof(json),
                R"({"type":"forward_fired","layer":%d,"bars":%.4f})", layer,
                bars);
  pushEvent(json);
}

bool LooperProcessor::shouldOverdubLayer(int layerIndex) const {
  if (!overdubEnabled)
    return false;
  if (layerIndex < 0 || layerIndex >= MAX_LAYERS)
    return false;
  return layers[layerIndex].getLength() > 0;
}

void LooperProcessor::setTempo(float bpm) {
  tempo = bpm;
  quantizer.setTempo(bpm);

  char json[128];
  std::snprintf(json, sizeof(json), R"({"type":"tempo","bpm":%.2f})", bpm);
  pushEvent(json);
}

bool LooperProcessor::isPlaying() const {
  for (const auto &layer : layers) {
    if (layer.getState() == LooperLayer::State::Playing)
      return true;
  }
  return false;
}

float LooperProcessor::getSamplesPerBar() const {
  float beatsPerSecond = tempo / 60.0f;
  float samplesPerBeat = static_cast<float>(currentSampleRate / beatsPerSecond);
  return samplesPerBeat * 4.0f;
}

void LooperProcessor::updateTransportState() {
  hostTransportPlaying = false;

  if (auto *playHead = getPlayHead()) {
    if (auto position = playHead->getPosition()) {
      if (auto timeInSamples = position->getTimeInSamples()) {
        hostTimelineSamples = static_cast<double>(*timeInSamples);
        hostTransportPlaying = position->getIsPlaying();

        if (auto bpm = position->getBpm()) {
          const float hostBpm = static_cast<float>(*bpm);
          if (hostBpm > 1.0f && std::abs(hostBpm - tempo) > 0.05f) {
            tempo = hostBpm;
            quantizer.setTempo(hostBpm);
          }
        }
      }
    }
  }
}

void LooperProcessor::syncLayersToTransportIfNeeded() {
  if (!hostTransportPlaying)
    return;

  for (auto &layer : layers) {
    if (layer.getState() != LooperLayer::State::Playing)
      continue;

    if (layer.getLength() <= 0)
      continue;

    if (std::abs(layer.getSpeed() - 1.0f) > 0.0001f)
      continue;

    const double length = static_cast<double>(layer.getLength());
    double phase = std::fmod(hostTimelineSamples, length);
    if (phase < 0.0)
      phase += length;

    if (layer.isReversed())
      phase = (length - 1.0) - phase;

    layer.getPlayhead().setPosition(static_cast<float>(phase));
  }
}

void LooperProcessor::ensureScratchSize(int numSamples) {
  if ((int)layerMixL.size() >= numSamples)
    return;

  layerMixL.assign(numSamples, 0.0f);
  layerMixR.assign(numSamples, 0.0f);
  tempLayerL.assign(numSamples, 0.0f);
  tempLayerR.assign(numSamples, 0.0f);
}

// ============================================================================
// Control server integration
// ============================================================================

bool LooperProcessor::postControlCommandPayload(const ControlCommand &command) {
  return controlServer.enqueueCommand(command);
}

bool LooperProcessor::postControlCommand(ControlCommand::Type type,
                                         int intParam, float floatParam) {
  ControlCommand cmd;
  cmd.operation = ControlOperation::Legacy;
  cmd.endpointId = -1;
  cmd.value.kind = ControlValueKind::None;
  cmd.type = type;
  cmd.intParam = intParam;
  cmd.floatParam = floatParam;
  return postControlCommandPayload(cmd);
}

void LooperProcessor::setGraphProcessingEnabled(bool enabled) {
  std::fprintf(stderr,
               "LooperProcessor: setGraphProcessingEnabled(%d) "
               "[active=%p pending=%p fadingFrom=%p fadingTo=%p]\n",
               enabled ? 1 : 0, static_cast<void*>(activeRuntime),
               static_cast<void*>(pendingRuntime.load(std::memory_order_acquire)),
               static_cast<void*>(fadingFromRuntime),
               static_cast<void*>(fadingToRuntime));

  if (!enabled) {
    graphProcessingEnabled = false;
    std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=0\n");
    return;
  }

  // If runtime state already exists (pending, active, or fading), just enable.
  if (activeRuntime != nullptr || fadingToRuntime != nullptr ||
      fadingFromRuntime != nullptr) {
    graphProcessingEnabled = true;
    std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=1 (existing runtime state)\n");
    return;
  }

  // If a prepared runtime is pending, just enable processing.
  if (pendingRuntime.load(std::memory_order_acquire) != nullptr) {
    graphProcessingEnabled = true;
    std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=1 (pending runtime exists)\n");
    return;
  }

  if (!primitiveGraph || preparedMaxBlockSize <= 0 || currentSampleRate <= 0.0) {
    graphProcessingEnabled = false;
    std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=0 (primitiveGraph/prepared invalid)\n");
    return;
  }

  const int numChannels = std::max(1, getTotalNumOutputChannels());
  auto runtime =
      primitiveGraph->compileRuntime(currentSampleRate, preparedMaxBlockSize, numChannels);

  if (!runtime) {
    graphProcessingEnabled = false;
    std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=0 (legacy compile failed)\n");
    return;
  }

  requestGraphRuntimeSwap(std::move(runtime));
  graphProcessingEnabled = true;
  std::fprintf(stderr, "LooperProcessor: graphProcessingEnabled=1 (legacy compile succeeded)\n");
}

bool LooperProcessor::setParamByPath(const std::string &path, float value) {
  if (path == "/looper/dsp/reload") {
    if (value > 0.5f) {
      return reloadDspScript();
    }
    return true;
  }

  if (dspScriptHost && dspScriptHost->hasParam(path)) {
    return dspScriptHost->setParam(path, value);
  }

  if (path == "/looper/graph/enabled") {
    setGraphProcessingEnabled(value > 0.5f);
    return true;
  }

  ParseResult result = CommandParser::buildResolverSetCommand(
      &endpointRegistry, juce::String(path), juce::var(value));

  if (result.kind != ParseResult::Kind::Enqueue) {
    return false;
  }

  return postControlCommandPayload(result.command);
}

float LooperProcessor::getParamByPath(const std::string &path) const {
  if (path == "/looper/dsp/reload") {
    return 0.0f;
  }

  // Direct paths handled outside the endpoint registry.
  if (path == "/looper/graph/enabled") return graphProcessingEnabled ? 1.0f : 0.0f;
  if (path == "/looper/debug/graphInputRms") return graphInputRms.load(std::memory_order_relaxed);
  if (path == "/looper/debug/graphWetRms") return graphWetRms.load(std::memory_order_relaxed);
  if (path == "/looper/debug/graphMixedRms") return graphMixedRms.load(std::memory_order_relaxed);
  if (path == "/looper/debug/graphNodeCount") return static_cast<float>(graphNodeCount.load(std::memory_order_relaxed));
  if (path == "/looper/debug/graphRouteCount") return static_cast<float>(graphRouteCount.load(std::memory_order_relaxed));

  if (dspScriptHost && dspScriptHost->hasParam(path)) {
    return dspScriptHost->getParam(path);
  }

  EndpointResolver resolver(const_cast<OSCEndpointRegistry *>(&endpointRegistry));
  ResolvedEndpoint endpoint;
  if (!resolver.resolve(juce::String(path), endpoint)) {
    return 0.0f;
  }

  auto validation = resolver.validateRead(endpoint);
  if (!validation.accepted) {
    return 0.0f;
  }

  // Map paths to direct accessor reads
  if (path == "/looper/tempo") return getTempo();
  if (path == "/looper/targetbpm") return getTargetBPM();
  if (path == "/looper/volume") return getMasterVolume();
  if (path == "/looper/inputVolume") return getInputVolume();
  if (path == "/looper/passthrough") return isPassthroughEnabled() ? 1.0f : 0.0f;
  if (path == "/looper/recording") return isRecording() ? 1.0f : 0.0f;
  if (path == "/looper/overdub") return isOverdubEnabled() ? 1.0f : 0.0f;
  if (path == "/looper/layer") return static_cast<float>(getActiveLayerIndex());
  if (path == "/looper/forwardArmed") return isForwardCommitArmed() ? 1.0f : 0.0f;
  if (path == "/looper/forwardBars") return getForwardCommitBars();
  if (path == "/looper/samplesPerBar") return getSamplesPerBar();
  if (path == "/looper/sampleRate") return static_cast<float>(getSampleRate());
  if (path == "/looper/captureSize") return static_cast<float>(getCaptureSize());
  if (path == "/looper/mode") return static_cast<float>(getRecordModeIndex());
  if (path == "/looper/commitCount") return static_cast<float>(getCommitCount());

  // Layer paths
  if (path.find("/looper/layer/") == 0) {
    int layerIdx = -1;
    std::string rest;
    if (sscanf(path.c_str(), "/looper/layer/%d/", &layerIdx) == 1 && layerIdx >= 0 && layerIdx < MAX_LAYERS) {
      size_t slashPos = path.find('/', 14);
      if (slashPos != std::string::npos) {
        rest = path.substr(slashPos + 1);
        ScriptableLayerSnapshot snap;
        if (getLayerSnapshot(layerIdx, snap)) {
          if (rest == "speed") return snap.speed;
          if (rest == "volume") return snap.volume;
          if (rest == "mute") return (snap.state == ScriptableLayerState::Muted) ? 1.0f : 0.0f;
          if (rest == "reverse") return snap.reversed ? 1.0f : 0.0f;
          if (rest == "length") return static_cast<float>(snap.length);
          if (rest == "position") {
            return (snap.length > 0) ? static_cast<float>(snap.position) / static_cast<float>(snap.length) : 0.0f;
          }
          if (rest == "bars") {
            float spb = getSamplesPerBar();
            return (spb > 0.0f) ? static_cast<float>(snap.length) / spb : 0.0f;
          }
        }
      }
    }
  }

  return 0.0f;
}

bool LooperProcessor::hasEndpoint(const std::string &path) const {
  if (path == "/looper/dsp/reload") {
    return true;
  }

  if (dspScriptHost && dspScriptHost->hasParam(path)) {
    return true;
  }

  if (path == "/looper/graph/enabled") {
    return true;
  }
  if (path == "/looper/debug/graphInputRms" ||
      path == "/looper/debug/graphWetRms" ||
      path == "/looper/debug/graphMixedRms" ||
      path == "/looper/debug/graphNodeCount" ||
      path == "/looper/debug/graphRouteCount") {
    return true;
  }
  OSCEndpoint endpoint = endpointRegistry.findEndpoint(juce::String(path));
  return endpoint.path.isNotEmpty();
}

bool LooperProcessor::loadDspScript(const juce::File &scriptFile) {
  if (!dspScriptHost) {
    return false;
  }
  return dspScriptHost->loadScript(scriptFile);
}

bool LooperProcessor::loadDspScriptFromString(const std::string &luaCode,
                                              const std::string &sourceName) {
  if (!dspScriptHost) {
    return false;
  }
  return dspScriptHost->loadScriptFromString(luaCode, sourceName);
}

bool LooperProcessor::reloadDspScript() {
  if (!dspScriptHost) {
    return false;
  }
  return dspScriptHost->reloadCurrentScript();
}

bool LooperProcessor::isDspScriptLoaded() const {
  return dspScriptHost && dspScriptHost->isLoaded();
}

const std::string &LooperProcessor::getDspScriptLastError() const {
  static const std::string empty;
  if (!dspScriptHost) {
    return empty;
  }
  return dspScriptHost->getLastError();
}

namespace {

bool isLayerAddressedCommand(ControlCommand::Type type) {
  return type == ControlCommand::Type::LayerMute ||
         type == ControlCommand::Type::LayerSpeed ||
         type == ControlCommand::Type::LayerReverse ||
         type == ControlCommand::Type::LayerVolume ||
         type == ControlCommand::Type::LayerStop ||
         type == ControlCommand::Type::LayerPlay ||
         type == ControlCommand::Type::LayerPause ||
         type == ControlCommand::Type::LayerClear ||
         type == ControlCommand::Type::LayerSeek;
}

void materializeResolvedValue(ControlCommand &command) {
  switch (command.value.kind) {
  case ControlValueKind::Float:
    command.floatParam = command.value.floatValue;
    break;
  case ControlValueKind::Int:
    if (!isLayerAddressedCommand(command.type)) {
      command.intParam = command.value.intValue;
    }
    command.floatParam = static_cast<float>(command.value.intValue);
    break;
  case ControlValueKind::Bool:
    command.floatParam = command.value.boolValue ? 1.0f : 0.0f;
    if (!isLayerAddressedCommand(command.type)) {
      command.intParam = command.value.boolValue ? 1 : 0;
    }
    break;
  case ControlValueKind::Trigger:
  case ControlValueKind::None:
    break;
  }
}

} // namespace

void LooperProcessor::processControlCommands() {
  ControlCommand cmd;
  auto &queue = controlServer.getCommandQueue();

  while (queue.dequeue(cmd)) {
    if (cmd.operation != ControlOperation::Legacy) {
      materializeResolvedValue(cmd);
    }

    switch (cmd.type) {
    case ControlCommand::Type::Commit:
      commitRetrospective(cmd.floatParam);
      break;

    case ControlCommand::Type::ForwardCommit:
      scheduleForwardCommit(cmd.floatParam);
      break;

    case ControlCommand::Type::SetTempo:
      setTempo(cmd.floatParam);
      break;

    case ControlCommand::Type::StartRecording:
      startRecording();
      break;

    case ControlCommand::Type::ToggleOverdub:
      startOverdub();
      break;

    case ControlCommand::Type::SetOverdubEnabled:
      setOverdubEnabled(cmd.floatParam > 0.5f);
      break;

    case ControlCommand::Type::StopRecording:
      stopRecording();
      break;

    case ControlCommand::Type::GlobalStop:
      for (auto &layer : layers)
        layer.stop();
      break;

    case ControlCommand::Type::GlobalPlay:
      for (auto &layer : layers)
        layer.play();
      break;

    case ControlCommand::Type::GlobalPause:
      for (auto &layer : layers)
        layer.pause();
      break;

    case ControlCommand::Type::SetActiveLayer:
      setActiveLayer(cmd.intParam);
      break;

    case ControlCommand::Type::LayerMute:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS) {
        if (cmd.floatParam > 0.5f)
          layers[cmd.intParam].mute();
        else
          layers[cmd.intParam].unmute();
      }
      break;

    case ControlCommand::Type::LayerSpeed:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].setSpeed(cmd.floatParam);
      break;

    case ControlCommand::Type::LayerReverse:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].setReversed(cmd.floatParam > 0.5f);
      break;

    case ControlCommand::Type::LayerVolume:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].setVolume(cmd.floatParam);
      break;

    case ControlCommand::Type::LayerStop:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].stop();
      break;

    case ControlCommand::Type::LayerPlay:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].play();
      break;

    case ControlCommand::Type::LayerPause:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS)
        layers[cmd.intParam].pause();
      break;

    case ControlCommand::Type::LayerClear: {
      int idx = (cmd.intParam < 0) ? activeLayerIndex : cmd.intParam;
      if (idx >= 0 && idx < MAX_LAYERS)
        layers[idx].clear();
      break;
    }

    case ControlCommand::Type::LayerSeek:
      if (cmd.intParam >= 0 && cmd.intParam < MAX_LAYERS) {
        auto &layer = layers[cmd.intParam];
        if (layer.getLength() > 0) {
          float pos = juce::jlimit(0.0f, 1.0f, cmd.floatParam);
          layer.getPlayhead().setPosition(pos * layer.getLength());
        }
      }
      break;

    case ControlCommand::Type::ClearAllLayers:
      for (auto &layer : layers)
        layer.clear();
      break;

    case ControlCommand::Type::SetRecordMode:
      recordMode = static_cast<RecordMode>(cmd.intParam);
      break;

    case ControlCommand::Type::SetMasterVolume:
      masterVolume = juce::jlimit(0.0f, 2.0f, cmd.floatParam);
      break;

    case ControlCommand::Type::SetInputVolume:
      inputVolume = juce::jlimit(0.0f, 2.0f, cmd.floatParam);
      break;

    case ControlCommand::Type::SetPassthroughEnabled:
      passthroughEnabled = cmd.floatParam > 0.5f;
      break;

    case ControlCommand::Type::SetTargetBPM:
      targetBPM = cmd.floatParam;
      break;

    case ControlCommand::Type::None:
      break;
    }
  }
}

std::string LooperProcessor::getAndClearPendingUISwitch() {
  auto &req = controlServer.getUISwitchRequest();
  if (!req.pending.load(std::memory_order_acquire))
    return "";

  std::lock_guard<std::mutex> lock(req.mutex);
  std::string path = req.path;
  req.path.clear();
  req.pending.store(false, std::memory_order_release);
  return path;
}

void LooperProcessor::updateAtomicState(
    const juce::AudioBuffer<float> &buffer) {
  auto &state = controlServer.getAtomicState();

  state.tempo.store(tempo, std::memory_order_relaxed);
  state.targetBPM.store(targetBPM, std::memory_order_relaxed);
  state.samplesPerBar.store(getSamplesPerBar(), std::memory_order_relaxed);
  state.sampleRate.store(currentSampleRate, std::memory_order_relaxed);
  state.captureWritePos.store(captureBuffer.getOffsetToNow(),
                              std::memory_order_relaxed);
  state.isRecording.store(isCurrentlyRecording, std::memory_order_relaxed);
  state.overdubEnabled.store(overdubEnabled, std::memory_order_relaxed);
  state.forwardArmed.store(forwardCommitArmed.load(std::memory_order_relaxed),
                           std::memory_order_relaxed);
  state.forwardBars.store(forwardCommitBars.load(std::memory_order_relaxed),
                          std::memory_order_relaxed);
  state.recordMode.store(static_cast<int>(recordMode),
                         std::memory_order_relaxed);
  state.activeLayer.store(activeLayerIndex, std::memory_order_relaxed);
  state.masterVolume.store(masterVolume, std::memory_order_relaxed);
  state.inputVolume.store(inputVolume, std::memory_order_relaxed);
  state.passthroughEnabled.store(passthroughEnabled, std::memory_order_relaxed);
  state.playTime.store(playTime, std::memory_order_relaxed);
  state.commitCount.store(commitCount, std::memory_order_relaxed);
  state.uptimeSeconds.store(playTime / currentSampleRate,
                            std::memory_order_relaxed);

  // Capture input level (RMS of first channel)
  float rms = 0.0f;
  const float *data = buffer.getReadPointer(0);
  int n = buffer.getNumSamples();
  for (int i = 0; i < n; ++i)
    rms += data[i] * data[i];
  rms = (n > 0) ? std::sqrt(rms / n) : 0.0f;
  state.captureLevel.store(rms, std::memory_order_relaxed);

  // Layer states
  for (int i = 0; i < MAX_LAYERS; ++i) {
    auto &ls = state.layers[i];
    auto &layer = layers[i];
    ls.state.store(static_cast<int>(layer.getState()),
                   std::memory_order_relaxed);
    ls.length.store(layer.getLength(), std::memory_order_relaxed);
    ls.playheadPos.store(layer.getPosition(), std::memory_order_relaxed);
    ls.speed.store(layer.getSpeed(), std::memory_order_relaxed);
    ls.reversed.store(layer.isReversed(), std::memory_order_relaxed);
    ls.volume.store(layer.getVolume(), std::memory_order_relaxed);

    // Calculate numBars from length
    float spb = getSamplesPerBar();
    float bars =
        (spb > 0 && layer.getLength() > 0) ? layer.getLength() / spb : 0.0f;
    ls.numBars.store(bars, std::memory_order_relaxed);
  }
}

void LooperProcessor::pushEvent(const char *json) {
  controlServer.pushEvent(json, (int)std::strlen(json));
}

// ============================================================================
// FFT Spectrum Analysis
// ============================================================================

void LooperProcessor::updateSpectrumBands() {
  // Map FFT bins to log-spaced frequency bands
  const float sampleRate = static_cast<float>(currentSampleRate);
  const float binWidth = sampleRate / FFT_SIZE;
  
  // Frequency range: 20Hz to 20kHz
  const float minFreq = 20.0f;
  const float maxFreq = 20000.0f;
  
  for (int band = 0; band < NUM_SPECTRUM_BANDS; ++band) {
    // Calculate frequency range for this band (log scale)
    float bandFreqLow = minFreq * std::pow(maxFreq / minFreq, static_cast<float>(band) / NUM_SPECTRUM_BANDS);
    float bandFreqHigh = minFreq * std::pow(maxFreq / minFreq, static_cast<float>(band + 1) / NUM_SPECTRUM_BANDS);
    
    // Convert to bin indices
    int binLow = static_cast<int>(bandFreqLow / binWidth);
    int binHigh = static_cast<int>(bandFreqHigh / binWidth);
    binLow = std::max(1, std::min(binLow, FFT_SIZE / 2));
    binHigh = std::max(1, std::min(binHigh, FFT_SIZE / 2));
    
    // Calculate average magnitude in this band
    float magnitude = 0.0f;
    for (int bin = binLow; bin < binHigh; ++bin) {
      float real = fftOutput[bin * 2];
      float imag = fftOutput[bin * 2 + 1];
      magnitude += std::sqrt(real * real + imag * imag);
    }
    
    if (binHigh > binLow) {
      magnitude /= (binHigh - binLow);
    }
    
    // Convert to dB and normalize
    float db = 20.0f * std::log10(magnitude + 1e-10f);
    float normalized = (db + 60.0f) / 60.0f;  // -60dB to 0dB range
    normalized = std::max(0.0f, std::min(1.0f, normalized));
    
    // Smooth with existing value
    float current = spectrumBands[band].load(std::memory_order_relaxed);
    float smoothed = current * 0.7f + normalized * 0.3f;
    spectrumBands[band].store(smoothed, std::memory_order_relaxed);
  }
}

bool LooperProcessor::getLayerSnapshot(int index,
                                       ScriptableLayerSnapshot &out) const {
  if (index < 0 || index >= MAX_LAYERS) {
    return false;
  }

  const auto &layer = layers[index];
  out.index = index;
  out.length = layer.getLength();
  out.position = layer.getPosition();
  out.speed = layer.getSpeed();
  out.reversed = layer.isReversed();
  out.volume = layer.getVolume();
  out.state = static_cast<ScriptableLayerState>(layer.getState());
  return true;
}

bool LooperProcessor::computeLayerPeaks(int layerIndex, int numBuckets,
                                        std::vector<float> &outPeaks) const {
  outPeaks.clear();
  if (layerIndex < 0 || layerIndex >= MAX_LAYERS || numBuckets <= 0) {
    return false;
  }

  const auto &layer = layers[layerIndex];
  const int length = layer.getLength();
  if (length <= 0) {
    return false;
  }

  const auto *raw = layer.getBuffer().getRawBuffer();
  if (raw == nullptr || raw->getNumSamples() <= 0) {
    return false;
  }

  outPeaks.resize(static_cast<size_t>(numBuckets), 0.0f);
  const int bucketSize = std::max(1, length / numBuckets);
  float highest = 0.0f;

  for (int x = 0; x < numBuckets; ++x) {
    const int start = std::min(length - 1, x * bucketSize);
    const int count = std::min(bucketSize, length - start);
    float peak = 0.0f;
    for (int i = 0; i < count; ++i) {
      const int idx = start + i;
      const float left = std::abs(raw->getSample(0, idx));
      float right = left;
      if (raw->getNumChannels() > 1) {
        right = std::abs(raw->getSample(1, idx));
      }
      peak = std::max(peak, std::max(left, right));
    }
    outPeaks[static_cast<size_t>(x)] = peak;
    highest = std::max(highest, peak);
  }

  const float rescale =
      highest > 0.0f ? std::min(8.0f, std::max(1.0f, 1.0f / highest)) : 1.0f;
  for (auto &peak : outPeaks) {
    peak = std::min(1.0f, peak * rescale);
  }
  return true;
}

bool LooperProcessor::computeCapturePeaks(int startAgo, int endAgo,
                                          int numBuckets,
                                          std::vector<float> &outPeaks) const {
  outPeaks.clear();
  if (numBuckets <= 0) {
    return false;
  }

  const int captureSize = captureBuffer.getSize();
  if (captureSize <= 0) {
    return false;
  }

  const int start = std::max(0, std::min(captureSize, startAgo));
  const int end = std::max(0, std::min(captureSize, endAgo));
  if (end <= start) {
    return false;
  }

  const int viewSamples = end - start;
  const int bucketSize = std::max(1, viewSamples / numBuckets);
  outPeaks.resize(static_cast<size_t>(numBuckets), 0.0f);

  float highest = 0.0f;
  for (int x = 0; x < numBuckets; ++x) {
    const float t = numBuckets > 1
                        ? static_cast<float>(numBuckets - 1 - x) /
                              static_cast<float>(numBuckets - 1)
                        : 0.0f;
    const int firstAgo =
        start + static_cast<int>(std::round(t * static_cast<float>(viewSamples - 1)));
    if (firstAgo >= captureSize) {
      continue;
    }

    float peak = 0.0f;
    const int bucket = std::min(bucketSize, captureSize - firstAgo);
    for (int i = 0; i < bucket; ++i) {
      peak = std::max(peak, std::abs(captureBuffer.getSample(firstAgo + i, 0)));
    }
    outPeaks[static_cast<size_t>(x)] = peak;
    highest = std::max(highest, peak);
  }

  const float rescale =
      highest > 0.0f ? std::min(10.0f, std::max(1.0f, 1.0f / highest)) : 1.0f;
  for (auto &peak : outPeaks) {
    peak = std::min(1.0f, peak * rescale);
  }
  return true;
}

std::array<float, LooperProcessor::NUM_SPECTRUM_BANDS> LooperProcessor::getSpectrumData() const {
  std::array<float, NUM_SPECTRUM_BANDS> result;
  for (int i = 0; i < NUM_SPECTRUM_BANDS; ++i) {
    result[i] = spectrumBands[i].load(std::memory_order_relaxed);
  }
  return result;
}

// ============================================================================
// Phase 4: Graph Runtime Swap (RT-safe, lock-free, 30ms crossfade)
// ============================================================================

void LooperProcessor::requestGraphRuntimeSwap(std::unique_ptr<dsp_primitives::GraphRuntime> runtime) {
  if (!runtime) return;
  
  // Atomically publish the new runtime
  // If there's already a pending one, it will be replaced (the old pending gets deleted here)
  dsp_primitives::GraphRuntime* oldPending = pendingRuntime.exchange(runtime.release(), std::memory_order_release);
  
  // Delete the old pending runtime if it was replaced (off audio thread, safe)
  if (oldPending != nullptr) {
    delete oldPending;
  }
}

void LooperProcessor::drainRetiredGraphRuntimes() {
  std::lock_guard<std::mutex> lock(this->retiredRuntimeDrainMutex);
  dsp_primitives::GraphRuntime* runtime = nullptr;
  while (retireQueue.dequeue(runtime)) {
    delete runtime;
  }
}

void LooperProcessor::beginFade(dsp_primitives::GraphRuntime* from, dsp_primitives::GraphRuntime* to) {
  fadingFromRuntime = from;
  fadingToRuntime = to;
  fadePosition = 0;
}

void LooperProcessor::checkGraphRuntimeSwap() {
  // If we're not fading and there's a pending runtime, begin fade
  if (fadingToRuntime == nullptr) {
    dsp_primitives::GraphRuntime* newRuntime = pendingRuntime.exchange(nullptr, std::memory_order_acq_rel);
    if (newRuntime != nullptr) {
      std::fprintf(stderr, "LooperProcessor: consumed pending runtime %p (active=%p)\n",
                   static_cast<void*>(newRuntime), static_cast<void*>(activeRuntime));
      if (activeRuntime == nullptr) {
        // First runtime: activate immediately, no fade needed.
        activeRuntime = newRuntime;
        fadingFromRuntime = nullptr;
        fadingToRuntime = nullptr;
        fadePosition = 0;
        std::fprintf(stderr, "LooperProcessor: activated first graph runtime %p\n",
                     static_cast<void*>(activeRuntime));
      } else {
        // Begin fade from current active to new runtime.
        beginFade(activeRuntime, newRuntime);
        activeRuntime = newRuntime;
        std::fprintf(stderr,
                     "LooperProcessor: begin graph runtime fade old=%p new=%p\n",
                     static_cast<void*>(fadingFromRuntime),
                     static_cast<void*>(activeRuntime));
      }
    }
  }
  // If we're already fading and there's a pending runtime, it will be handled
  // after current fade completes (keep only latest pending - the atomic exchange already did that)
}

void LooperProcessor::processGraphRuntime(juce::AudioBuffer<float>& buffer) {
  int numSamples = buffer.getNumSamples();
  int numChannels = buffer.getNumChannels();

  // Hard RT constraint: never allocate on audio thread.
  // If host provides larger blocks than we prepared for, drop processing.
  if (preparedMaxBlockSize <= 0 || numSamples > preparedMaxBlockSize) {
    return;
  }

  // Preserve current looper mix so DSP graph can run alongside it.
  graphDryBuffer.copyFrom(0, 0, buffer, 0, 0, numSamples);
  if (numChannels > 1) {
    graphDryBuffer.copyFrom(1, 0, buffer, 1, 0, numSamples);
  } else {
    graphDryBuffer.copyFrom(1, 0, buffer, 0, 0, numSamples);
  }
  graphInputRms.store(computeBufferRms(graphDryBuffer, numSamples),
                      std::memory_order_relaxed);

  // Drain any pending retire pointer into retireQueue (must not delete on audio thread).
  if (this->pendingRetireRuntime != nullptr) {
    if (retireQueue.enqueue(this->pendingRetireRuntime)) {
      this->pendingRetireRuntime = nullptr;
    }
  }
  
  // Case 1: No active runtime
  if (activeRuntime == nullptr) {
    // Check if a new runtime arrived
    checkGraphRuntimeSwap();
    graphWetRms.store(0.0f, std::memory_order_relaxed);
    graphMixedRms.store(graphInputRms.load(std::memory_order_relaxed),
                        std::memory_order_relaxed);
    graphNodeCount.store(0, std::memory_order_relaxed);
    graphRouteCount.store(0, std::memory_order_relaxed);
    return;
  }
  
  // Case 2: Currently fading
  if (fadingFromRuntime != nullptr && fadingToRuntime != nullptr) {
    // Get pointer copies for clarity
    dsp_primitives::GraphRuntime* oldRuntime = fadingFromRuntime;
    dsp_primitives::GraphRuntime* newRuntime = fadingToRuntime;
    graphNodeCount.store(newRuntime->getCompiledNodeCount(), std::memory_order_relaxed);
    graphRouteCount.store(newRuntime->getRouteCount(), std::memory_order_relaxed);
    
    // Process both runtimes into preallocated buffers.
    // Avoid makeCopyOf/setSize here to keep audio thread allocation-free.
    // Copy host buffer into both fade inputs (mono-safe: duplicate ch0 into ch1)
    fadeOldBuffer.copyFrom(0, 0, buffer, 0, 0, numSamples);
    fadeNewBuffer.copyFrom(0, 0, buffer, 0, 0, numSamples);
    if (numChannels > 1) {
      fadeOldBuffer.copyFrom(1, 0, buffer, 1, 0, numSamples);
      fadeNewBuffer.copyFrom(1, 0, buffer, 1, 0, numSamples);
    } else {
      fadeOldBuffer.copyFrom(1, 0, buffer, 0, 0, numSamples);
      fadeNewBuffer.copyFrom(1, 0, buffer, 0, 0, numSamples);
    }

    // Process only the active range (numSamples) without resizing member buffers.
    float* oldCh[2] = { fadeOldBuffer.getWritePointer(0), fadeOldBuffer.getWritePointer(1) };
    float* newCh[2] = { fadeNewBuffer.getWritePointer(0), fadeNewBuffer.getWritePointer(1) };
    juce::AudioBuffer<float> oldView(oldCh, 2, numSamples);
    juce::AudioBuffer<float> newView(newCh, 2, numSamples);

    oldRuntime->process(oldView);
    newRuntime->process(newView);
    
    // Apply equal-power crossfade
    // gOld = cos(t*pi/2), gNew = sin(t*pi/2) where t = fadePosition / fadeTotalSamples
    for (int i = 0; i < numSamples; ++i) {
      float t = static_cast<float>(fadePosition + i) / static_cast<float>(fadeTotalSamples);
      t = juce::jlimit(0.0f, 1.0f, t);
      
      float gOld = std::cos(t * float(juce::MathConstants<float>::pi) * 0.5f);
      float gNew = std::sin(t * float(juce::MathConstants<float>::pi) * 0.5f);
      
      const float oldL = fadeOldBuffer.getSample(0, i);
      const float oldR = fadeOldBuffer.getSample(numChannels > 1 ? 1 : 0, i);
      const float newL = fadeNewBuffer.getSample(0, i);
      const float newR = fadeNewBuffer.getSample(numChannels > 1 ? 1 : 0, i);

      float mixedL = oldL * gOld + newL * gNew;
      float mixedR = oldR * gOld + newR * gNew;
      
      buffer.setSample(0, i, mixedL);
      if (numChannels > 1) {
        buffer.setSample(1, i, mixedR);
      }
    }
    
    // Advance fade position
    fadePosition += numSamples;
    
    // Check if fade is complete
    if (fadePosition >= fadeTotalSamples) {
      // Enqueue old runtime to retire queue for deletion off audio thread.
      // If queue is full, stash it and retry later.
      if (!retireQueue.enqueue(oldRuntime)) {
        // If we already have a stashed runtime, keep the older one in pendingRetireRuntime
        // and drop the newer oldRuntime into it only if empty.
        if (this->pendingRetireRuntime == nullptr) {
          this->pendingRetireRuntime = oldRuntime;
        } else {
          // Worst-case overflow: keep the oldest pending; leak avoidance requires
          // larger queue capacity. This branch should never happen with sane capacity.
          // Intentionally do not delete here.
        }
      }
      
      // Clear fading state
      fadingFromRuntime = nullptr;
      fadingToRuntime = nullptr;
      fadePosition = 0;
      
      // Check if another pending runtime arrived during the fade
      checkGraphRuntimeSwap();
    }
  }
  // Case 3: No fade in progress, process active runtime in-place
  else {
    graphNodeCount.store(activeRuntime->getCompiledNodeCount(), std::memory_order_relaxed);
    graphRouteCount.store(activeRuntime->getRouteCount(), std::memory_order_relaxed);
    activeRuntime->process(buffer);
    
    // Check for pending runtime swap
    checkGraphRuntimeSwap();
  }

  // Blend processed graph output with original looper signal.
  graphWetRms.store(computeBufferRms(buffer, numSamples), std::memory_order_relaxed);
  buffer.addFrom(0, 0, graphDryBuffer, 0, 0, numSamples, 1.0f);
  if (numChannels > 1) {
    buffer.addFrom(1, 0, graphDryBuffer, 1, 0, numSamples, 1.0f);
  }
  graphMixedRms.store(computeBufferRms(buffer, numSamples), std::memory_order_relaxed);
}

juce::AudioProcessor *JUCE_CALLTYPE createPluginFilter() {
  return new LooperProcessor();
}

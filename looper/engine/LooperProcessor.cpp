#include "LooperProcessor.h"
#include "../ui/LooperEditor.h"
#include "../primitives/control/OSCServer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

LooperProcessor::LooperProcessor()
    : juce::AudioProcessor(
          juce::AudioProcessor::BusesProperties()
              .withInput("Input", juce::AudioChannelSet::stereo(), true)
              .withOutput("Output", juce::AudioChannelSet::stereo(), true)) {}

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
  playTime = 0.0;
  hostTransportPlaying = false;
  hostTimelineSamples = 0.0;

  ensureScratchSize(samplesPerBlock);

  // Start control server
  controlServer.start(this);
  
  // Initialize endpoint registry with correct layer count
  endpointRegistry.setNumLayers(MAX_LAYERS);
  endpointRegistry.rebuild();

  // Start OSC server (UDP)
  OSCSettings oscSettings;
  oscSettings.oscEnabled = true;
  oscSettings.oscQueryEnabled = true;
  oscSettings.inputPort = 9000;
  oscSettings.queryPort = 9001;
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
  state.samplesPerBar.store(getSamplesPerBar());

  // Initialize FFT for spectrum analysis
  fft = std::make_unique<juce::dsp::FFT>(FFT_ORDER);
  fftInput.resize(FFT_SIZE);
  fftOutput.resize(FFT_SIZE * 2);
  std::fill(fftInput.begin(), fftInput.end(), 0.0f);
  fftInputIndex = 0;
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

  // Output: dry input + wet layers
  for (int i = 0; i < numSamples; ++i) {
    inputL[i] = inputL[i] * 0.7f + layerMixL[i] * masterVolume;
    inputR[i] = inputR[i] * 0.7f + layerMixR[i] * masterVolume;
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

bool LooperProcessor::postControlCommand(ControlCommand::Type type,
                                         int intParam, float floatParam) {
  ControlCommand cmd;
  cmd.type = type;
  cmd.intParam = intParam;
  cmd.floatParam = floatParam;
  return controlServer.enqueueCommand(cmd);
}

void LooperProcessor::processControlCommands() {
  ControlCommand cmd;
  auto &queue = controlServer.getCommandQueue();

  while (queue.dequeue(cmd)) {
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
  state.samplesPerBar.store(getSamplesPerBar(), std::memory_order_relaxed);
  state.captureWritePos.store(captureBuffer.getOffsetToNow(),
                              std::memory_order_relaxed);
  state.isRecording.store(isCurrentlyRecording, std::memory_order_relaxed);
  state.overdubEnabled.store(overdubEnabled, std::memory_order_relaxed);
  state.recordMode.store(static_cast<int>(recordMode),
                         std::memory_order_relaxed);
  state.activeLayer.store(activeLayerIndex, std::memory_order_relaxed);
  state.masterVolume.store(masterVolume, std::memory_order_relaxed);
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

std::array<float, LooperProcessor::NUM_SPECTRUM_BANDS> LooperProcessor::getSpectrumData() const {
  std::array<float, NUM_SPECTRUM_BANDS> result;
  for (int i = 0; i < NUM_SPECTRUM_BANDS; ++i) {
    result[i] = spectrumBands[i].load(std::memory_order_relaxed);
  }
  return result;
}

juce::AudioProcessor *JUCE_CALLTYPE createPluginFilter() {
  return new LooperProcessor();
}

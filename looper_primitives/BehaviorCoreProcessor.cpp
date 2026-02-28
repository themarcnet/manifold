#include "BehaviorCoreProcessor.h"

#include "BehaviorCoreEditor.h"
#include "../looper/primitives/control/OSCSettingsPersistence.h"
#include "../looper/primitives/scripting/DSPPluginScriptHost.h"
#include "../looper/primitives/scripting/GraphRuntime.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace {

constexpr float kDefaultTempo = 120.0f;
constexpr float kDefaultTargetBpm = 120.0f;
constexpr float kDefaultMasterVolume = 1.0f;
constexpr float kDefaultInputVolume = 1.0f;

float computeSamplesPerBar(float tempo, double sampleRate) {
    if (tempo <= 0.0f || sampleRate <= 0.0) {
        return 0.0f;
    }
    return static_cast<float>((sampleRate * 240.0) / tempo);
}


ScriptableLayerState toLayerState(int raw) {
    switch (raw) {
        case 0:
            return ScriptableLayerState::Empty;
        case 1:
            return ScriptableLayerState::Playing;
        case 2:
            return ScriptableLayerState::Recording;
        case 3:
            return ScriptableLayerState::Overdubbing;
        case 4:
            return ScriptableLayerState::Muted;
        case 5:
            return ScriptableLayerState::Stopped;
        case 6:
            return ScriptableLayerState::Paused;
        default:
            return ScriptableLayerState::Unknown;
    }
}

float computeBufferRms(const juce::AudioBuffer<float>& buffer) {
    const int numChannels = buffer.getNumChannels();
    const int numSamples = buffer.getNumSamples();
    if (numChannels <= 0 || numSamples <= 0) {
        return 0.0f;
    }

    double sumSq = 0.0;
    int sampleCount = 0;
    for (int ch = 0; ch < numChannels; ++ch) {
        const float* data = buffer.getReadPointer(ch);
        for (int i = 0; i < numSamples; ++i) {
            const float s = data[i];
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

BehaviorCoreProcessor::BehaviorCoreProcessor()
    : juce::AudioProcessor(BusesProperties()
                               .withInput("Input", juce::AudioChannelSet::stereo(), true)
                               .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      primitiveGraph(std::make_shared<dsp_primitives::PrimitiveGraph>()),
      dspScriptHost(std::make_unique<DSPPluginScriptHost>()) {
    if (dspScriptHost) {
        dspScriptHost->initialise(this, "/core/behavior");
    }
    endpointRegistry.setNumLayers(MAX_LAYERS);
    endpointRegistry.rebuild();
    initialiseAtomicState(currentSampleRate.load(std::memory_order_relaxed));
}

BehaviorCoreProcessor::~BehaviorCoreProcessor() {
    releaseResources();
}

void BehaviorCoreProcessor::prepareToPlay(double sampleRate, int samplesPerBlock) {
    currentSampleRate.store(sampleRate > 0.0 ? sampleRate : 44100.0,
                            std::memory_order_relaxed);
    currentBlockSize.store(samplesPerBlock > 0 ? samplesPerBlock : 512,
                           std::memory_order_relaxed);
    playTimeSamples.store(0.0, std::memory_order_relaxed);

    const int captureSamples = static_cast<int>(CAPTURE_SECONDS * currentSampleRate.load(std::memory_order_relaxed));
    captureBuffer.setSize(captureSamples);
    captureBuffer.setNumChannels(2);

    graphWetBuffer.setSize(2, currentBlockSize.load(std::memory_order_relaxed), false, true, true);
    forwardScheduled = false;
    forwardFireAtSample = 0.0;
    forwardScheduledBars = 0.0f;

    endpointRegistry.setNumLayers(MAX_LAYERS);
    endpointRegistry.rebuild();

    controlServer.start(this);

    if (dspScriptHost && !dspScriptHost->isLoaded()) {
        juce::File defaultDspScript(
            "/home/shamanic/dev/my-plugin/looper/dsp/looper_primitives_dsp.lua");
        if (defaultDspScript.existsAsFile()) {
            if (!loadDspScript(defaultDspScript)) {
                std::fprintf(stderr,
                             "BehaviorCoreProcessor: failed to load default DSP script: %s\n",
                             getDspScriptLastError().c_str());
            }
        }
    }

    // Primitives behavior runtime is graph-driven; keep graph active by default.
    graphProcessingEnabled.store(true, std::memory_order_relaxed);

    OSCSettings oscSettings = OSCSettingsPersistence::load();
    auto settingsFile = OSCSettingsPersistence::getSettingsFile();
    if (!settingsFile.existsAsFile()) {
        oscSettings.oscEnabled = true;
        oscSettings.oscQueryEnabled = true;
        oscSettings.inputPort = 9000;
        oscSettings.queryPort = 9001;
        OSCSettingsPersistence::save(oscSettings);
    }

    oscServer.setSettings(oscSettings);
    oscServer.start(this);

    if (oscSettings.oscQueryEnabled) {
        oscQueryServer.start(this, &endpointRegistry, oscSettings.queryPort,
                             oscSettings.inputPort);
    }

    initialiseAtomicState(currentSampleRate.load(std::memory_order_relaxed));

    // Initialize Ableton Link
    linkSync.initialise(currentSampleRate.load(std::memory_order_relaxed));
}

void BehaviorCoreProcessor::releaseResources() {
    // Shutdown Ableton Link first
    linkSync.shutdown();
    oscQueryServer.stop();
    oscServer.stop();
    controlServer.stop();

    drainRetiredGraphRuntimes();

    if (auto* pending = pendingRuntime.exchange(nullptr, std::memory_order_acq_rel)) {
        delete pending;
    }

    if (pendingRetireRuntime != nullptr) {
        delete pendingRetireRuntime;
        pendingRetireRuntime = nullptr;
    }

    if (activeRuntime != nullptr) {
        delete activeRuntime;
        activeRuntime = nullptr;
    }
}

void BehaviorCoreProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                         juce::MidiBuffer& midiMessages) {
    juce::ignoreUnused(midiMessages);

    processControlCommands();
    checkGraphRuntimeSwap();

    // Process Ableton Link - updates tempo from network if sync enabled
    const int numSamples = buffer.getNumSamples();
    if (linkSync.processAudio(numSamples)) {
        // Tempo was updated from Link, update atomic state
        auto& state = controlServer.getAtomicState();
        const double linkTempo = linkSync.getTempo();
        state.tempo.store(static_cast<float>(linkTempo), std::memory_order_relaxed);
        state.samplesPerBar.store(computeSamplesPerBar(
                                    static_cast<float>(linkTempo),
                                    currentSampleRate.load(std::memory_order_relaxed)),
                                std::memory_order_relaxed);
    }

    auto& state = controlServer.getAtomicState();
    const int numChannels = buffer.getNumChannels();
    float* outL = numChannels > 0 ? buffer.getWritePointer(0) : nullptr;
    float* outR = numChannels > 1 ? buffer.getWritePointer(1) : outL;

    // Capture-plane source comes from incoming block before any output scaling.
    // Use the same write pointers legacy uses for in-place host buffers.
    const float* captureL = outL;
    const float* captureR = outR;

    // Capture-plane source buffer is always fed from incoming input stream
    // (or injected stream when INJECT is active), before any wet/dry mixing.
    if (controlServer.isInjecting()) {
        controlServer.drainInjection(captureBuffer, numSamples);
    } else if (captureL != nullptr) {
        captureBuffer.writeBlock(captureL, numSamples, 0);
        if (captureR != nullptr) {
            captureBuffer.writeBlock(captureR, numSamples, 1);
        }
    }

    state.captureSize.store(captureBuffer.getSize(), std::memory_order_relaxed);
    state.captureWritePos.store(captureBuffer.getOffsetToNow(), std::memory_order_relaxed);

    const float dryGain =
        state.passthroughEnabled.load(std::memory_order_relaxed)
            ? state.inputVolume.load(std::memory_order_relaxed) * 0.7f
            : 0.0f;
    const float wetGain = state.masterVolume.load(std::memory_order_relaxed);

    const bool graphEnabled = graphProcessingEnabled.load(std::memory_order_relaxed);
    state.graphEnabled.store(graphEnabled, std::memory_order_relaxed);

    const bool canProcessGraph =
        graphEnabled &&
        activeRuntime != nullptr &&
        graphWetBuffer.getNumChannels() >= numChannels &&
        graphWetBuffer.getNumSamples() >= numSamples;

    if (canProcessGraph) {
        // Build graph input from host input using the same monitor gain contract
        // as dry passthrough so all UIs/scripts share one input volume + toggle.
        const float graphInputGain = dryGain;
        for (int ch = 0; ch < numChannels; ++ch) {
            graphWetBuffer.copyFrom(ch, 0, buffer, ch, 0, numSamples);
            graphWetBuffer.applyGain(ch, 0, numSamples, graphInputGain);
        }

        float* wetPtrs[2] = {
            graphWetBuffer.getWritePointer(0),
            graphWetBuffer.getNumChannels() > 1 ? graphWetBuffer.getWritePointer(1)
                                                : graphWetBuffer.getWritePointer(0)};
        juce::AudioBuffer<float> wetView(wetPtrs, juce::jmax(1, numChannels), numSamples);

        // Provide raw host input for capture-plane nodes that explicitly request it.
        activeRuntime->process(wetView, &buffer);

        if (outL == nullptr) {
            buffer.clear();
        } else {
            const float* wetL = graphWetBuffer.getReadPointer(0);
            const float* wetR = graphWetBuffer.getNumChannels() > 1
                                    ? graphWetBuffer.getReadPointer(1)
                                    : wetL;

            for (int i = 0; i < numSamples; ++i) {
                const float dryL = captureL != nullptr ? captureL[i] : 0.0f;
                const float dryR = captureR != nullptr ? captureR[i] : dryL;
                outL[i] = dryL * dryGain + wetL[i] * wetGain;
                if (outR != nullptr && outR != outL) {
                    outR[i] = dryR * dryGain + wetR[i] * wetGain;
                }
            }
        }
    } else {
        if (outL == nullptr) {
            buffer.clear();
        } else {
            for (int i = 0; i < numSamples; ++i) {
                outL[i] *= dryGain;
                if (outR != nullptr && outR != outL) {
                    outR[i] *= dryGain;
                }
            }
        }
    }

    state.captureLevel.store(captureL != nullptr ? computeBufferRms(buffer)
                                                 : 0.0f,
                             std::memory_order_relaxed);

    for (int i = 0; i < MAX_LAYERS; ++i) {
        auto& ls = state.layers[i];
        const auto layerState = static_cast<ScriptableLayerState>(
            ls.state.load(std::memory_order_relaxed));
        if (layerState != ScriptableLayerState::Playing &&
            layerState != ScriptableLayerState::Overdubbing) {
            continue;
        }

        const int length = ls.length.load(std::memory_order_relaxed);
        if (length <= 0) {
            continue;
        }

        const float speed = std::abs(ls.speed.load(std::memory_order_relaxed));
        if (speed <= 0.0001f) {
            continue;
        }
        const int delta = std::max(1, static_cast<int>(std::round(speed * numSamples)));

        int pos = ls.playheadPos.load(std::memory_order_relaxed);
        if (ls.reversed.load(std::memory_order_relaxed)) {
            pos -= delta;
            while (pos < 0) {
                pos += length;
            }
        } else {
            pos += delta;
            while (pos >= length) {
                pos -= length;
            }
        }

        ls.playheadPos.store(pos, std::memory_order_relaxed);
    }

    const double nextPlayTime =
        playTimeSamples.load(std::memory_order_relaxed) + numSamples;
    playTimeSamples.store(nextPlayTime, std::memory_order_relaxed);

    state.playTime.store(nextPlayTime, std::memory_order_relaxed);

    scheduleForwardCommitIfNeeded();
    if (forwardScheduled && nextPlayTime >= forwardFireAtSample) {
        (void)setParamByPath("/core/behavior/forwardFire", 1.0f);
        forwardScheduled = false;
        forwardFireAtSample = 0.0;
        forwardScheduledBars = 0.0f;
    }

    const double sr = currentSampleRate.load(std::memory_order_relaxed);
    state.uptimeSeconds.store(sr > 0.0 ? nextPlayTime / sr : 0.0,
                              std::memory_order_relaxed);
}

juce::AudioProcessorEditor* BehaviorCoreProcessor::createEditor() {
    return new BehaviorCoreEditor(*this);
}

bool BehaviorCoreProcessor::postControlCommandPayload(
    const ControlCommand& command) {
    return controlServer.enqueueCommand(command);
}

bool BehaviorCoreProcessor::postControlCommand(ControlCommand::Type type,
                                               int intParam,
                                               float floatParam) {
    ControlCommand cmd;
    cmd.operation = ControlOperation::Legacy;
    cmd.type = type;
    cmd.intParam = intParam;
    cmd.floatParam = floatParam;
    return postControlCommandPayload(cmd);
}

void BehaviorCoreProcessor::requestGraphRuntimeSwap(
    std::unique_ptr<dsp_primitives::GraphRuntime> runtime) {
    if (!runtime) {
        return;
    }

    dsp_primitives::GraphRuntime* oldPending = pendingRuntime.exchange(
        runtime.release(), std::memory_order_release);
    if (oldPending != nullptr) {
        delete oldPending;
    }
}

DSPPluginScriptHost& BehaviorCoreProcessor::getOrCreateSlot(const std::string& slot) {
    // "default" slot uses the legacy dspScriptHost pointer so all existing
    // param routing, layer peaks, etc. keep working without changes.
    if (slot == "default") {
        return *dspScriptHost;
    }
    auto it = dspSlots.find(slot);
    if (it != dspSlots.end()) {
        return *it->second;
    }
    auto host = std::make_unique<DSPPluginScriptHost>();
    host->initialise(this, "/core/slots/" + slot);
    auto& ref = *host;
    dspSlots[slot] = std::move(host);
    return ref;
}

// --- Default slot (legacy compat) ---

bool BehaviorCoreProcessor::loadDspScript(const juce::File& scriptFile) {
    if (!dspScriptHost) {
        dspScriptLastError = "DSP script host unavailable";
        return false;
    }
    const bool ok = dspScriptHost->loadScript(scriptFile);
    if (!ok) {
        dspScriptLastError = dspScriptHost->getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::loadDspScriptFromString(const std::string& luaCode,
                                                    const std::string& sourceName) {
    if (!dspScriptHost) {
        dspScriptLastError = "DSP script host unavailable";
        return false;
    }
    const bool ok = dspScriptHost->loadScriptFromString(luaCode, sourceName);
    if (!ok) {
        dspScriptLastError = dspScriptHost->getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::reloadDspScript() {
    if (!dspScriptHost) {
        dspScriptLastError = "DSP script host unavailable";
        return false;
    }
    const bool ok = dspScriptHost->reloadCurrentScript();
    if (!ok) {
        dspScriptLastError = dspScriptHost->getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::isDspScriptLoaded() const {
    return dspScriptHost && dspScriptHost->isLoaded();
}

// --- Named slot API ---

bool BehaviorCoreProcessor::loadDspScript(const juce::File& scriptFile,
                                          const std::string& slot) {
    if (slot == "default") return loadDspScript(scriptFile);
    auto& host = getOrCreateSlot(slot);
    const bool ok = host.loadScript(scriptFile);
    if (!ok) {
        dspScriptLastError = host.getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::loadDspScriptFromString(const std::string& luaCode,
                                                    const std::string& sourceName,
                                                    const std::string& slot) {
    if (slot == "default") return loadDspScriptFromString(luaCode, sourceName);
    auto& host = getOrCreateSlot(slot);
    const bool ok = host.loadScriptFromString(luaCode, sourceName);
    if (!ok) {
        dspScriptLastError = host.getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::reloadDspScript(const std::string& slot) {
    if (slot == "default") return reloadDspScript();
    auto it = dspSlots.find(slot);
    if (it == dspSlots.end()) {
        dspScriptLastError = "no script loaded in slot: " + slot;
        return false;
    }
    const bool ok = it->second->reloadCurrentScript();
    if (!ok) {
        dspScriptLastError = it->second->getLastError();
    }
    return ok;
}

bool BehaviorCoreProcessor::unloadDspSlot(const std::string& slot) {
    if (slot == "default") {
        return false;
    }
    auto it = dspSlots.find(slot);
    if (it == dspSlots.end()) {
        return false;
    }

    // Do not destroy slot hosts during runtime UI/DSP transitions.
    // Tearing down Lua VMs has repeatedly caused crashes. Keep the host alive
    // and unload only its nodes by loading an empty script.
    return it->second->loadScriptFromString(
        "function buildPlugin(ctx) return {} end", "unload:" + slot);
}

void BehaviorCoreProcessor::drainPendingSlotDestroy() {
    // Intentionally no-op for now; slot hosts are kept alive for stability.
}

bool BehaviorCoreProcessor::isDspSlotLoaded(const std::string& slot) const {
    if (slot == "default") return isDspScriptLoaded();
    auto it = dspSlots.find(slot);
    return it != dspSlots.end() && it->second->isLoaded();
}

const std::string& BehaviorCoreProcessor::getDspScriptLastError() const {
    if (dspScriptHost) {
        return dspScriptHost->getLastError();
    }
    return dspScriptLastError;
}

void BehaviorCoreProcessor::drainRetiredGraphRuntimes() {
    std::lock_guard<std::mutex> lock(retiredRuntimeDrainMutex);
    dsp_primitives::GraphRuntime* runtime = nullptr;
    while (retireQueue.dequeue(runtime)) {
        delete runtime;
    }
}

bool BehaviorCoreProcessor::extractLayerParam(const std::string& path,
                                              int& layerIndex,
                                              std::string& paramSuffix) {
    static const std::array<std::string, 1> prefixes = {
        "/core/behavior/layer/",
    };

    for (const auto& prefix : prefixes) {
        if (path.rfind(prefix, 0) != 0) {
            continue;
        }

        const std::string rest = path.substr(prefix.size());
        const auto slash = rest.find('/');
        if (slash == std::string::npos) {
            return false;
        }

        const std::string idxStr = rest.substr(0, slash);
        const int idx = std::atoi(idxStr.c_str());
        if (idx < 0 || idx >= MAX_LAYERS) {
            return false;
        }

        layerIndex = idx;
        paramSuffix = rest.substr(slash + 1);
        return true;
    }

    return false;
}

bool BehaviorCoreProcessor::applyParamPath(const std::string& path, float value) {
    auto& state = controlServer.getAtomicState();

    if (path == "/core/behavior/tempo") {
        const float tempo = juce::jlimit(20.0f, 300.0f, value);
        state.tempo.store(tempo, std::memory_order_relaxed);
        state.samplesPerBar.store(computeSamplesPerBar(
                                    tempo,
                                    currentSampleRate.load(std::memory_order_relaxed)),
                                std::memory_order_relaxed);
        // Push tempo change to Ableton Link (if Link is enabled)
        if (linkSync.isEnabled()) {
            linkSync.requestTempo(static_cast<double>(tempo));
        }
        return true;
    }

    if (path == "/core/behavior/targetbpm") {
        state.targetBPM.store(value, std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/volume") {
        state.masterVolume.store(juce::jlimit(0.0f, 2.0f, value),
                                 std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/inputVolume") {
        state.inputVolume.store(juce::jlimit(0.0f, 2.0f, value),
                                std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/passthrough") {
        state.passthroughEnabled.store(value > 0.5f, std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/recording") {
        const bool recording = value > 0.5f;
        const int activeLayer = juce::jlimit(0, MAX_LAYERS - 1,
                                             state.activeLayer.load(std::memory_order_relaxed));

        state.isRecording.store(recording, std::memory_order_relaxed);

        if (recording) {
            state.layers[activeLayer].state.store(
                static_cast<int>(ScriptableLayerState::Recording),
                std::memory_order_relaxed);
            scheduleForwardCommitIfNeeded();
            return true;
        }

        // stop recording: clear forward-arm bookkeeping only.
        state.forwardArmed.store(false, std::memory_order_relaxed);
        state.forwardBars.store(0.0f, std::memory_order_relaxed);
        forwardScheduled = false;
        forwardFireAtSample = 0.0;
        forwardScheduledBars = 0.0f;
        return true;
    }

    if (path == "/core/behavior/overdub") {
        state.overdubEnabled.store(value > 0.5f, std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/layer") {
        const int layer = juce::jlimit(0, MAX_LAYERS - 1, static_cast<int>(value));
        state.activeLayer.store(layer, std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/mode") {
        const int mode = juce::jlimit(0, 2, static_cast<int>(value));
        state.recordMode.store(mode, std::memory_order_relaxed);
        return true;
    }

    if (path == "/core/behavior/forwardArmed") {
        const bool armed = value > 0.5f;
        state.forwardArmed.store(armed, std::memory_order_relaxed);
        if (!armed) {
            forwardScheduled = false;
            forwardFireAtSample = 0.0;
            forwardScheduledBars = 0.0f;
        } else {
            scheduleForwardCommitIfNeeded();
        }
        return true;
    }

    if (path == "/core/behavior/forwardBars") {
        const float bars = juce::jmax(0.0f, value);
        state.forwardBars.store(bars, std::memory_order_relaxed);
        if (bars <= 0.0f) {
            state.forwardArmed.store(false, std::memory_order_relaxed);
            forwardScheduled = false;
            forwardFireAtSample = 0.0;
            forwardScheduledBars = 0.0f;
        } else {
            forwardScheduled = false;
            scheduleForwardCommitIfNeeded();
        }
        return true;
    }

    if (path == "/core/behavior/forward") {
        const float bars = juce::jmax(0.0f, value);
        state.forwardBars.store(bars, std::memory_order_relaxed);
        state.forwardArmed.store(bars > 0.0f, std::memory_order_relaxed);
        if (bars <= 0.0f) {
            forwardScheduled = false;
            forwardFireAtSample = 0.0;
            forwardScheduledBars = 0.0f;
        } else {
            forwardScheduled = false;
            scheduleForwardCommitIfNeeded();
        }
        return true;
    }

    if (path == "/core/behavior/commit") {
        state.commitCount.fetch_add(1, std::memory_order_relaxed);
        const int activeLayer = state.activeLayer.load(std::memory_order_relaxed);
        if (activeLayer >= 0 && activeLayer < MAX_LAYERS) {
            auto& ls = state.layers[activeLayer];
            const float requestedBars = juce::jmax(0.0625f, value);
            const int requestedSamples = std::max(1, static_cast<int>(
                requestedBars * getSamplesPerBar()));

            int effectiveSamples = requestedSamples;
            if (dspScriptHost) {
                const int actualLoopLength = dspScriptHost->getLayerLoopLength(activeLayer);
                if (actualLoopLength > 0) {
                    effectiveSamples = actualLoopLength;
                }
            }

            ls.length.store(effectiveSamples, std::memory_order_relaxed);
            ls.playheadPos.store(0, std::memory_order_relaxed);
            const float spb = getSamplesPerBar();
            ls.numBars.store(spb > 0.0f ? static_cast<float>(effectiveSamples) / spb : 0.0f,
                             std::memory_order_relaxed);
            ls.state.store(static_cast<int>(ScriptableLayerState::Playing),
                           std::memory_order_relaxed);

        }
        state.forwardArmed.store(false, std::memory_order_relaxed);
        state.forwardBars.store(0.0f, std::memory_order_relaxed);
        forwardScheduled = false;
        forwardFireAtSample = 0.0;
        forwardScheduledBars = 0.0f;
        return true;
    }

    if (path == "/core/behavior/forwardFire") {
        if (value > 0.5f) {
            // Lua/script policy handles the actual forward-fire commit behavior.
            // Core only clears arm/scheduler bookkeeping.
            state.forwardArmed.store(false, std::memory_order_relaxed);
            state.forwardBars.store(0.0f, std::memory_order_relaxed);
            forwardScheduled = false;
            forwardFireAtSample = 0.0;
            forwardScheduledBars = 0.0f;
        }
        return true;
    }

    if (path == "/core/behavior/transport") {
        const int transport = static_cast<int>(value);
        for (int i = 0; i < MAX_LAYERS; ++i) {
            auto& ls = state.layers[i];
            const int currentState = ls.state.load(std::memory_order_relaxed);
            // Don't change empty layers - they stay empty
            if (currentState == static_cast<int>(ScriptableLayerState::Empty)) {
                continue;
            }
            if (transport == 0) {
                ls.state.store(static_cast<int>(ScriptableLayerState::Stopped),
                               std::memory_order_relaxed);
            } else if (transport == 1) {
                ls.state.store(static_cast<int>(ScriptableLayerState::Playing),
                               std::memory_order_relaxed);
            } else if (transport == 2) {
                ls.state.store(static_cast<int>(ScriptableLayerState::Paused),
                               std::memory_order_relaxed);
            }
        }
        return true;
    }

    if (path == "/core/behavior/graph/enabled") {
        const bool enabled = value > 0.5f;
        graphProcessingEnabled.store(enabled, std::memory_order_relaxed);
        state.graphEnabled.store(enabled, std::memory_order_relaxed);
        return true;
    }

    // Ableton Link parameters
    if (path == "/core/behavior/link/enabled") {
        linkSync.setEnabled(value > 0.5f);
        return true;
    }
    if (path == "/core/behavior/link/tempoSync") {
        linkSync.setTempoSyncEnabled(value > 0.5f);
        return true;
    }
    if (path == "/core/behavior/link/startStopSync") {
        linkSync.setStartStopSyncEnabled(value > 0.5f);
        return true;
    }

    int layerIndex = -1;
    std::string suffix;
    if (extractLayerParam(path, layerIndex, suffix)) {
        auto& ls = state.layers[layerIndex];

        if (suffix == "volume") {
            ls.volume.store(juce::jlimit(0.0f, 2.0f, value), std::memory_order_relaxed);
            return true;
        }
        if (suffix == "speed") {
            ls.speed.store(juce::jlimit(-4.0f, 4.0f, value), std::memory_order_relaxed);
            return true;
        }
        if (suffix == "reverse") {
            ls.reversed.store(value > 0.5f, std::memory_order_relaxed);
            return true;
        }
        if (suffix == "mute") {
            ls.muted.store(value > 0.5f, std::memory_order_relaxed);
            return true;
        }
        if (suffix == "play") {
            ls.state.store(static_cast<int>(ScriptableLayerState::Playing),
                           std::memory_order_relaxed);
            return true;
        }
        if (suffix == "pause") {
            ls.state.store(static_cast<int>(ScriptableLayerState::Paused),
                           std::memory_order_relaxed);
            return true;
        }
        if (suffix == "stop") {
            ls.state.store(static_cast<int>(ScriptableLayerState::Stopped),
                           std::memory_order_relaxed);
            return true;
        }
        if (suffix == "clear") {
            ls.length.store(0, std::memory_order_relaxed);
            ls.playheadPos.store(0, std::memory_order_relaxed);
            ls.state.store(static_cast<int>(ScriptableLayerState::Empty),
                           std::memory_order_relaxed);
            return true;
        }
        if (suffix == "seek") {
            const int length = std::max(1, ls.length.load(std::memory_order_relaxed));
            const int pos = static_cast<int>(juce::jlimit(0.0f, 1.0f, value) * length);
            ls.playheadPos.store(pos, std::memory_order_relaxed);
            return true;
        }
    }

    return false;
}

bool BehaviorCoreProcessor::setParamByPath(const std::string& path, float value) {
    if (path == "/core/behavior/dsp/reload") {
        if (value > 0.5f) {
            return reloadDspScript();
        }
        return true;
    }

    bool handled = false;

    if (dspScriptHost && dspScriptHost->hasParam(path)) {
        handled = dspScriptHost->setParam(path, value) || handled;
    }

    for (auto& entry : dspSlots) {
        auto* host = entry.second.get();
        if (host != nullptr && host->hasParam(path)) {
            handled = host->setParam(path, value) || handled;
        }
    }

    if (applyParamPath(path, value)) {
        handled = true;
    }

    if (handled) {
        return true;
    }

    const auto endpoint = endpointRegistry.findEndpoint(juce::String(path));
    return endpoint.path.isNotEmpty();
}

float BehaviorCoreProcessor::getParamByPath(const std::string& path) const {
    if (path == "/core/behavior/dsp/reload") {
        return 0.0f;
    }

    const auto& state = controlServer.getAtomicState();

    if (path == "/core/behavior/tempo") {
        return state.tempo.load(std::memory_order_relaxed);
    }
    if (path == "/core/behavior/targetbpm") {
        return state.targetBPM.load(std::memory_order_relaxed);
    }
    if (path == "/core/behavior/volume") {
        return state.masterVolume.load(std::memory_order_relaxed);
    }
    if (path == "/core/behavior/inputVolume") {
        return state.inputVolume.load(std::memory_order_relaxed);
    }
    if (path == "/core/behavior/passthrough") {
        return state.passthroughEnabled.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/recording") {
        return state.isRecording.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/overdub") {
        return state.overdubEnabled.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/layer") {
        return static_cast<float>(state.activeLayer.load(std::memory_order_relaxed));
    }
    if (path == "/core/behavior/forwardArmed") {
        return state.forwardArmed.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/forwardBars") {
        return state.forwardBars.load(std::memory_order_relaxed);
    }
    if (path == "/core/behavior/mode") {
        return static_cast<float>(state.recordMode.load(std::memory_order_relaxed));
    }
    if (path == "/core/behavior/graph/enabled") {
        return graphProcessingEnabled.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }

    // Ableton Link parameters
    if (path == "/core/behavior/link/enabled") {
        return linkSync.isEnabled() ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/link/tempoSync") {
        return linkSync.getState().isTempoSyncEnabled.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/link/startStopSync") {
        return linkSync.getState().isStartStopSyncEnabled.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/link/peers") {
        return static_cast<float>(linkSync.getNumPeers());
    }
    if (path == "/core/behavior/link/playing") {
        return linkSync.getIsPlaying() ? 1.0f : 0.0f;
    }
    if (path == "/core/behavior/link/beat") {
        return static_cast<float>(linkSync.getBeat());
    }
    if (path == "/core/behavior/link/phase") {
        return static_cast<float>(linkSync.getPhase());
    }

    int layerIndex = -1;
    std::string suffix;
    if (extractLayerParam(path, layerIndex, suffix)) {
        const auto& ls = state.layers[layerIndex];
        if (suffix == "volume") {
            return ls.volume.load(std::memory_order_relaxed);
        }
        if (suffix == "speed") {
            return ls.speed.load(std::memory_order_relaxed);
        }
        if (suffix == "reverse") {
            return ls.reversed.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
        }
        if (suffix == "mute") {
            return ls.state.load(std::memory_order_relaxed) ==
                           static_cast<int>(ScriptableLayerState::Muted)
                       ? 1.0f
                       : 0.0f;
        }
        if (suffix == "length") {
            return static_cast<float>(ls.length.load(std::memory_order_relaxed));
        }
        if (suffix == "position") {
            const int length = std::max(1, ls.length.load(std::memory_order_relaxed));
            return static_cast<float>(ls.playheadPos.load(std::memory_order_relaxed)) /
                   static_cast<float>(length);
        }
    }

    if (dspScriptHost && dspScriptHost->hasParam(path)) {
        return dspScriptHost->getParam(path);
    }

    for (const auto& entry : dspSlots) {
        const auto* host = entry.second.get();
        if (host != nullptr && host->hasParam(path)) {
            return host->getParam(path);
        }
    }

    return 0.0f;
}

bool BehaviorCoreProcessor::hasEndpoint(const std::string& path) const {
    if (path == "/core/behavior/dsp/reload") {
        return true;
    }

    if (path == "/core/behavior/graph/enabled") {
        return true;
    }

    // Ableton Link endpoints
    if (path.rfind("/core/behavior/link/", 0) == 0) {
        return true;
    }

    if (dspScriptHost && dspScriptHost->hasParam(path)) {
        return true;
    }

    for (const auto& entry : dspSlots) {
        const auto* host = entry.second.get();
        if (host != nullptr && host->hasParam(path)) {
            return true;
        }
    }

    const auto endpoint = endpointRegistry.findEndpoint(juce::String(path));
    return endpoint.path.isNotEmpty();
}

bool BehaviorCoreProcessor::getLayerSnapshot(int index,
                                             ScriptableLayerSnapshot& out) const {
    if (index < 0 || index >= MAX_LAYERS) {
        return false;
    }

    const auto& ls = controlServer.getAtomicState().layers[index];
    out.index = index;
    out.length = ls.length.load(std::memory_order_relaxed);
    out.position = ls.playheadPos.load(std::memory_order_relaxed);
    out.speed = ls.speed.load(std::memory_order_relaxed);
    out.reversed = ls.reversed.load(std::memory_order_relaxed);
    out.volume = ls.volume.load(std::memory_order_relaxed);
    out.state = toLayerState(ls.state.load(std::memory_order_relaxed));
    out.muted = ls.muted.load(std::memory_order_relaxed);
    // Also check DSP script gate node muted state (source of truth)
    if (dspScriptHost && index >= 0 && index < MAX_LAYERS) {
        out.muted = dspScriptHost->isLayerMuted(index);
    }
    return true;
}

int BehaviorCoreProcessor::getCaptureSize() const {
    return captureBuffer.getSize();
}

bool BehaviorCoreProcessor::computeLayerPeaks(int layerIndex, int numBuckets,
                                              std::vector<float>& outPeaks) const {
    outPeaks.clear();
    if (layerIndex < 0 || layerIndex >= MAX_LAYERS || numBuckets <= 0) {
        return false;
    }

    if (dspScriptHost && dspScriptHost->computeLayerPeaks(layerIndex, numBuckets, outPeaks)) {
        return true;
    }

    return false;
}

bool BehaviorCoreProcessor::computeLayerPeaksForPath(const std::string& pathBase,
                                                     int layerIndex,
                                                     int numBuckets,
                                                     std::vector<float>& outPeaks) const {
    outPeaks.clear();
    if (layerIndex < 0 || layerIndex >= MAX_LAYERS || numBuckets <= 0) {
        return false;
    }

    const juce::String base(pathBase);
    if (base.isEmpty() ||
        base == "/core/behavior" ||
        base.startsWith("/core/behavior/")) {
        return computeLayerPeaks(layerIndex, numBuckets, outPeaks);
    }

    if (base.startsWith("/core/slots/")) {
        juce::String rest = base.substring(12); // after "/core/slots/"
        if (rest.isEmpty()) {
            return false;
        }

        const int slash = rest.indexOfChar('/');
        const juce::String slot = (slash >= 0) ? rest.substring(0, slash) : rest;
        if (slot.isEmpty()) {
            return false;
        }

        const auto it = dspSlots.find(slot.toStdString());
        if (it == dspSlots.end() || it->second == nullptr) {
            return false;
        }

        return it->second->computeLayerPeaks(layerIndex, numBuckets, outPeaks);
    }

    // Unknown base: preserve legacy behavior.
    return computeLayerPeaks(layerIndex, numBuckets, outPeaks);
}

bool BehaviorCoreProcessor::computeCapturePeaks(int startAgo, int endAgo,
                                                int numBuckets,
                                                std::vector<float>& outPeaks) const {
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
            const float left = std::abs(captureBuffer.getSample(firstAgo + i, 0));
            float right = left;
            if (captureBuffer.getNumChannels() > 1) {
                right = std::abs(captureBuffer.getSample(firstAgo + i, 1));
            }
            peak = std::max(peak, std::max(left, right));
        }
        outPeaks[static_cast<size_t>(x)] = peak;
        highest = std::max(highest, peak);
    }

    const float rescale =
        highest > 0.0f ? std::min(10.0f, std::max(1.0f, 1.0f / highest)) : 1.0f;
    for (auto& peak : outPeaks) {
        peak = std::min(1.0f, peak * rescale);
    }
    return true;
}

float BehaviorCoreProcessor::getTempo() const {
    return controlServer.getAtomicState().tempo.load(std::memory_order_relaxed);
}

float BehaviorCoreProcessor::getTargetBPM() const {
    return controlServer.getAtomicState().targetBPM.load(std::memory_order_relaxed);
}

float BehaviorCoreProcessor::getSamplesPerBar() const {
    const auto& state = controlServer.getAtomicState();
    const float cached = state.samplesPerBar.load(std::memory_order_relaxed);
    if (cached > 0.0f) {
        return cached;
    }
    return computeSamplesPerBar(getTempo(), getSampleRate());
}

double BehaviorCoreProcessor::getSampleRate() const {
    return currentSampleRate.load(std::memory_order_relaxed);
}

float BehaviorCoreProcessor::getMasterVolume() const {
    return controlServer.getAtomicState().masterVolume.load(std::memory_order_relaxed);
}

float BehaviorCoreProcessor::getInputVolume() const {
    return controlServer.getAtomicState().inputVolume.load(std::memory_order_relaxed);
}

bool BehaviorCoreProcessor::isPassthroughEnabled() const {
    return controlServer.getAtomicState().passthroughEnabled.load(std::memory_order_relaxed);
}

bool BehaviorCoreProcessor::isRecording() const {
    return controlServer.getAtomicState().isRecording.load(std::memory_order_relaxed);
}

bool BehaviorCoreProcessor::isOverdubEnabled() const {
    return controlServer.getAtomicState().overdubEnabled.load(std::memory_order_relaxed);
}

int BehaviorCoreProcessor::getActiveLayerIndex() const {
    return controlServer.getAtomicState().activeLayer.load(std::memory_order_relaxed);
}

bool BehaviorCoreProcessor::isForwardCommitArmed() const {
    return controlServer.getAtomicState().forwardArmed.load(std::memory_order_relaxed);
}

float BehaviorCoreProcessor::getForwardCommitBars() const {
    return controlServer.getAtomicState().forwardBars.load(std::memory_order_relaxed);
}

int BehaviorCoreProcessor::getRecordModeIndex() const {
    return controlServer.getAtomicState().recordMode.load(std::memory_order_relaxed);
}

int BehaviorCoreProcessor::getCommitCount() const {
    return controlServer.getAtomicState().commitCount.load(std::memory_order_relaxed);
}

std::array<float, 32> BehaviorCoreProcessor::getSpectrumData() const {
    return {};
}

std::string BehaviorCoreProcessor::getAndClearPendingUISwitch() {
    auto& req = controlServer.getUISwitchRequest();
    if (!req.pending.load(std::memory_order_acquire)) {
        return {};
    }

    std::lock_guard<std::mutex> lock(req.mutex);
    std::string path = req.path;
    req.path.clear();
    req.pending.store(false, std::memory_order_release);
    return path;
}

void BehaviorCoreProcessor::applyControlCommand(const ControlCommand& cmd) {
    auto& state = controlServer.getAtomicState();
    static constexpr const char* kBehaviorBase = "/core/behavior";

    switch (cmd.type) {
        case ControlCommand::Type::SetTempo:
            (void)setParamByPath(std::string(kBehaviorBase) + "/tempo", cmd.floatParam);
            break;
        case ControlCommand::Type::SetTargetBPM:
            (void)setParamByPath(std::string(kBehaviorBase) + "/targetbpm", cmd.floatParam);
            break;
        case ControlCommand::Type::SetMasterVolume:
            (void)setParamByPath(std::string(kBehaviorBase) + "/volume", cmd.floatParam);
            break;
        case ControlCommand::Type::SetInputVolume:
            (void)setParamByPath(std::string(kBehaviorBase) + "/inputVolume", cmd.floatParam);
            break;
        case ControlCommand::Type::SetPassthroughEnabled:
            (void)setParamByPath(std::string(kBehaviorBase) + "/passthrough", cmd.floatParam);
            break;
        case ControlCommand::Type::SetActiveLayer:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer", static_cast<float>(cmd.intParam));
            break;
        case ControlCommand::Type::SetRecordMode:
            (void)setParamByPath(std::string(kBehaviorBase) + "/mode", static_cast<float>(cmd.intParam));
            break;
        case ControlCommand::Type::StartRecording:
            (void)setParamByPath(std::string(kBehaviorBase) + "/recording", 1.0f);
            break;
        case ControlCommand::Type::StopRecording:
            (void)setParamByPath(std::string(kBehaviorBase) + "/recording", 0.0f);
            break;
        case ControlCommand::Type::ToggleOverdub:
            state.overdubEnabled.store(!state.overdubEnabled.load(std::memory_order_relaxed),
                                       std::memory_order_relaxed);
            break;
        case ControlCommand::Type::SetOverdubEnabled:
            (void)setParamByPath(std::string(kBehaviorBase) + "/overdub", cmd.floatParam);
            break;
        case ControlCommand::Type::Commit:
            (void)setParamByPath(std::string(kBehaviorBase) + "/commit", cmd.floatParam);
            break;
        case ControlCommand::Type::ForwardCommit:
            (void)setParamByPath(std::string(kBehaviorBase) + "/forward", cmd.floatParam);
            break;
        case ControlCommand::Type::GlobalStop:
            (void)setParamByPath(std::string(kBehaviorBase) + "/transport", 0.0f);
            break;
        case ControlCommand::Type::GlobalPlay:
            (void)setParamByPath(std::string(kBehaviorBase) + "/transport", 1.0f);
            break;
        case ControlCommand::Type::GlobalPause:
            (void)setParamByPath(std::string(kBehaviorBase) + "/transport", 2.0f);
            break;
        case ControlCommand::Type::LayerVolume:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/volume",
                                 cmd.floatParam);
            break;
        case ControlCommand::Type::LayerSpeed:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/speed",
                                 cmd.floatParam);
            break;
        case ControlCommand::Type::LayerReverse:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/reverse",
                                 cmd.floatParam);
            break;
        case ControlCommand::Type::LayerMute:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/mute",
                                 cmd.floatParam);
            break;
        case ControlCommand::Type::LayerPlay:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/play",
                                 1.0f);
            break;
        case ControlCommand::Type::LayerPause:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/pause",
                                 1.0f);
            break;
        case ControlCommand::Type::LayerStop:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/stop",
                                 1.0f);
            break;
        case ControlCommand::Type::LayerClear:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/clear",
                                 1.0f);
            break;
        case ControlCommand::Type::LayerSeek:
            (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(cmd.intParam) +
                                     "/seek",
                                 cmd.floatParam);
            break;
        case ControlCommand::Type::ClearAllLayers:
            for (int i = 0; i < MAX_LAYERS; ++i) {
                (void)setParamByPath(std::string(kBehaviorBase) + "/layer/" + std::to_string(i) + "/clear", 1.0f);
            }
            break;
        case ControlCommand::Type::UISwitch:
            break;
        case ControlCommand::Type::None:
            break;
    }
}

void BehaviorCoreProcessor::processControlCommands() {
    ControlCommand cmd;
    auto& queue = controlServer.getCommandQueue();
    while (queue.dequeue(cmd)) {
        applyControlCommand(cmd);
    }
}

void BehaviorCoreProcessor::checkGraphRuntimeSwap() {
    if (pendingRetireRuntime != nullptr) {
        if (retireQueue.enqueue(pendingRetireRuntime)) {
            pendingRetireRuntime = nullptr;
        }
    }

    dsp_primitives::GraphRuntime* newRuntime =
        pendingRuntime.exchange(nullptr, std::memory_order_acq_rel);
    if (newRuntime == nullptr) {
        return;
    }

    dsp_primitives::GraphRuntime* oldRuntime = activeRuntime;
    activeRuntime = newRuntime;

    if (oldRuntime != nullptr) {
        if (!retireQueue.enqueue(oldRuntime)) {
            if (pendingRetireRuntime == nullptr) {
                pendingRetireRuntime = oldRuntime;
            }
        }
    }
}

void BehaviorCoreProcessor::scheduleForwardCommitIfNeeded() {
    auto& state = controlServer.getAtomicState();

    const bool armed = state.forwardArmed.load(std::memory_order_relaxed);
    const float bars = state.forwardBars.load(std::memory_order_relaxed);

    if (!armed || bars <= 0.0f) {
        forwardScheduled = false;
        forwardFireAtSample = 0.0;
        forwardScheduledBars = 0.0f;
        return;
    }

    if (forwardScheduled) {
        return;
    }

    const float samplesPerBar = state.samplesPerBar.load(std::memory_order_relaxed);
    if (samplesPerBar <= 0.0f) {
        return;
    }

    forwardScheduledBars = bars;
    forwardFireAtSample = playTimeSamples.load(std::memory_order_relaxed) +
                          static_cast<double>(bars) * static_cast<double>(samplesPerBar);
    forwardScheduled = true;
}

void BehaviorCoreProcessor::initialiseAtomicState(double sampleRate) {
    auto& state = controlServer.getAtomicState();

    state.sampleRate.store(sampleRate, std::memory_order_relaxed);
    state.tempo.store(kDefaultTempo, std::memory_order_relaxed);
    state.targetBPM.store(kDefaultTargetBpm, std::memory_order_relaxed);
    state.samplesPerBar.store(computeSamplesPerBar(kDefaultTempo, sampleRate),
                              std::memory_order_relaxed);
    state.captureSize.store(captureBuffer.getSize(), std::memory_order_relaxed);
    state.captureWritePos.store(captureBuffer.getOffsetToNow(), std::memory_order_relaxed);
    state.captureLevel.store(0.0f, std::memory_order_relaxed);
    state.isRecording.store(false, std::memory_order_relaxed);
    state.overdubEnabled.store(false, std::memory_order_relaxed);
    state.forwardArmed.store(false, std::memory_order_relaxed);
    state.forwardBars.store(0.0f, std::memory_order_relaxed);
    state.graphEnabled.store(graphProcessingEnabled.load(std::memory_order_relaxed),
                             std::memory_order_relaxed);
    state.recordMode.store(0, std::memory_order_relaxed);
    state.activeLayer.store(0, std::memory_order_relaxed);
    state.masterVolume.store(kDefaultMasterVolume, std::memory_order_relaxed);
    state.inputVolume.store(kDefaultInputVolume, std::memory_order_relaxed);
    state.passthroughEnabled.store(true, std::memory_order_relaxed);
    state.playTime.store(0.0, std::memory_order_relaxed);
    state.commitCount.store(0, std::memory_order_relaxed);
    state.uptimeSeconds.store(0.0, std::memory_order_relaxed);

    for (int i = 0; i < MAX_LAYERS; ++i) {
        auto& ls = state.layers[i];
        ls.state.store(static_cast<int>(ScriptableLayerState::Empty),
                       std::memory_order_relaxed);
        ls.length.store(0, std::memory_order_relaxed);
        ls.playheadPos.store(0, std::memory_order_relaxed);
        ls.speed.store(1.0f, std::memory_order_relaxed);
        ls.reversed.store(false, std::memory_order_relaxed);
        ls.volume.store(1.0f, std::memory_order_relaxed);
        ls.numBars.store(0.0f, std::memory_order_relaxed);
    }
}

// ============================================================================
// Ableton Link Integration
// ============================================================================

bool BehaviorCoreProcessor::isLinkEnabled() const {
    return linkSync.isEnabled();
}

void BehaviorCoreProcessor::setLinkEnabled(bool enabled) {
    linkSync.setEnabled(enabled);
}

bool BehaviorCoreProcessor::isLinkTempoSyncEnabled() const {
    return linkSync.getState().isTempoSyncEnabled.load(std::memory_order_relaxed);
}

void BehaviorCoreProcessor::setLinkTempoSyncEnabled(bool enabled) {
    linkSync.setTempoSyncEnabled(enabled);
}

bool BehaviorCoreProcessor::isLinkStartStopSyncEnabled() const {
    return linkSync.getState().isStartStopSyncEnabled.load(std::memory_order_relaxed);
}

void BehaviorCoreProcessor::setLinkStartStopSyncEnabled(bool enabled) {
    linkSync.setStartStopSyncEnabled(enabled);
}

int BehaviorCoreProcessor::getLinkNumPeers() const {
    return linkSync.getNumPeers();
}

bool BehaviorCoreProcessor::isLinkPlaying() const {
    return linkSync.getIsPlaying();
}

double BehaviorCoreProcessor::getLinkBeat() const {
    return linkSync.getBeat();
}

double BehaviorCoreProcessor::getLinkPhase() const {
    return linkSync.getPhase();
}

void BehaviorCoreProcessor::requestLinkTempo(double bpm) {
    linkSync.requestTempo(bpm);
}

void BehaviorCoreProcessor::requestLinkStart() {
    linkSync.requestPlay();
}

void BehaviorCoreProcessor::requestLinkStop() {
    linkSync.requestStop();
}

void BehaviorCoreProcessor::processLinkPendingRequests() {
    linkSync.processPendingRequests();
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new BehaviorCoreProcessor();
}

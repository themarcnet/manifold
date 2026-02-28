#include "TempusPlugin.h"

#include "../../looper/primitives/sync/LinkSync.h"
#include "../../looper/primitives/control/CommandParser.h"

#include <cmath>
#include <algorithm>

TempusPlugin::TempusPlugin() {
    // Initialize Link with default sample rate
    linkSync_ = std::make_unique<LinkSync>();
    linkSync_->initialise(44100.0);
    
    // Enable Link by default
    linkEnabled_.store(true);
    if (linkSync_) {
        linkSync_->setEnabled(true);
    }
    
    // Register endpoints
    endpointRegistry_.setNumLayers(0);
    
    // Register our custom endpoints with proper command types
    auto registerEndpoint = [&](const char* path, const char* type, float min, float max, 
                               ControlCommand::Type cmdType = ControlCommand::Type::None) {
        OSCEndpoint ep;
        ep.path = path;
        ep.type = type;
        ep.rangeMin = min;
        ep.rangeMax = max;
        ep.access = (cmdType != ControlCommand::Type::None) ? 2 : 1; // write if has command, else read
        ep.description = "First Loop parameter";
        ep.category = "custom";
        ep.commandType = cmdType;
        endpointRegistry_.registerCustomEndpoint(ep);
    };
    
    // Register endpoints - note: we use custom handling in setParamByPath, so commandType is None
    // But we need access = 2 (write) for SET commands to work
    auto registerWritable = [&](const char* path, const char* type, float min, float max) {
        OSCEndpoint ep;
        ep.path = path;
        ep.type = type;
        ep.rangeMin = min;
        ep.rangeMax = max;
        ep.access = 2; // write-only (we handle the actual logic in setParamByPath)
        ep.description = "First Loop parameter";
        ep.category = "custom";
        ep.commandType = ControlCommand::Type::None; // We handle these manually
        endpointRegistry_.registerCustomEndpoint(ep);
    };
    
    registerWritable("/firstloop/tempo", "f", 20.0f, 300.0f);
    registerWritable("/firstloop/targetbpm", "f", 20.0f, 300.0f);
    registerWritable("/firstloop/detectedbars", "f", 0.0625f, 16.0f);
    registerWritable("/firstloop/detecting", "i", 0.0f, 1.0f);
    registerWritable("/firstloop/linkenabled", "i", 0.0f, 1.0f);
    
    // Read-only
    OSCEndpoint peersEp;
    peersEp.path = "/firstloop/linkpeers";
    peersEp.type = "i";
    peersEp.access = 1; // read-only
    peersEp.description = "Number of Link peers";
    peersEp.category = "custom";
    endpointRegistry_.registerCustomEndpoint(peersEp);
    
    // Trigger endpoints (no value, just trigger)
    auto registerTrigger = [&](const char* path) {
        OSCEndpoint ep;
        ep.path = path;
        ep.type = "N"; // nil/empty (trigger)
        ep.access = 2; // write (trigger is a write operation)
        ep.description = "Trigger";
        ep.category = "custom";
        ep.commandType = ControlCommand::Type::None;
        endpointRegistry_.registerCustomEndpoint(ep);
    };
    
    registerTrigger("/firstloop/rec");
    registerTrigger("/firstloop/stoprec");
    
    endpointRegistry_.rebuild();
}

bool TempusPlugin::postControlCommandPayload(const ControlCommand& command) {
    // Handle commands directly (no audio thread needed)
    switch (command.type) {
        case ControlCommand::Type::SetTempo:
            detectedTempo_.store(command.floatParam);
            if (linkEnabled_.load() && linkSync_) {
                linkSync_->requestTempo(command.floatParam);
            }
            return true;
            
        case ControlCommand::Type::StartRecording:
            startDetection();
            return true;
            
        case ControlCommand::Type::StopRecording:
            stopDetection();
            return true;
            
        case ControlCommand::Type::SetTargetBPM:
            setTargetBPM(command.floatParam);
            return true;
            
        default:
            return false;
    }
}

bool TempusPlugin::postControlCommand(ControlCommand::Type type, 
                                               int intParam, float floatParam) {
    ControlCommand cmd;
    cmd.operation = ControlOperation::Legacy;
    cmd.type = type;
    cmd.intParam = intParam;
    cmd.floatParam = floatParam;
    return postControlCommandPayload(cmd);
}

bool TempusPlugin::setParamByPath(const std::string& path, float value) {
    // Handle trigger-style paths (e.g., /firstloop/rec)
    if (path == "/firstloop/rec") {
        startDetection();
        return true;
    }
    if (path == "/firstloop/stoprec") {
        stopDetection();
        return true;
    }
    
    // Handle SET paths
    if (path == "/firstloop/tempo") {
        detectedTempo_.store(value);
        return true;
    }
    if (path == "/firstloop/targetbpm") {
        setTargetBPM(value);
        return true;
    }
    if (path == "/firstloop/detecting") {
        if (value > 0.5f) startDetection();
        else stopDetection();
        return true;
    }
    if (path == "/firstloop/linkenabled") {
        setLinkEnabled(value > 0.5f);
        return true;
    }
    return false;
}

float TempusPlugin::getParamByPath(const std::string& path) const {
    if (path == "/firstloop/tempo") return detectedTempo_.load();
    if (path == "/firstloop/targetbpm") return targetBPM_.load();
    if (path == "/firstloop/detectedbars") return detectedBars_.load();
    if (path == "/firstloop/detecting") return isDetecting_.load() ? 1.0f : 0.0f;
    if (path == "/firstloop/linkenabled") return linkEnabled_.load() ? 1.0f : 0.0f;
    if (path == "/firstloop/linkpeers") return static_cast<float>(getLinkNumPeers());
    return 0.0f;
}

bool TempusPlugin::hasEndpoint(const std::string& path) const {
    static const std::vector<std::string> endpoints = {
        "/firstloop/tempo",
        "/firstloop/targetbpm",
        "/firstloop/detectedbars",
        "/firstloop/detecting",
        "/firstloop/linkenabled",
        "/firstloop/linkpeers",
        "/firstloop/rec",
        "/firstloop/stoprec"
    };
    return std::find(endpoints.begin(), endpoints.end(), path) != endpoints.end();
}

bool TempusPlugin::getLayerSnapshot(int index, ScriptableLayerSnapshot& out) const {
    (void)index;
    (void)out;
    return false; // No layers
}

bool TempusPlugin::computeLayerPeaks(int layerIndex, int numBuckets,
                                             std::vector<float>& outPeaks) const {
    (void)layerIndex;
    (void)numBuckets;
    (void)outPeaks;
    return false;
}

bool TempusPlugin::computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                                               std::vector<float>& outPeaks) const {
    (void)startAgo;
    (void)endAgo;
    (void)numBuckets;
    (void)outPeaks;
    return false;
}

float TempusPlugin::getSamplesPerBar() const {
    float tempo = detectedTempo_.load();
    if (tempo <= 0.0f) return 0.0f;
    return static_cast<float>((44100.0 * 240.0) / tempo);
}

std::array<float, 32> TempusPlugin::getSpectrumData() const {
    return {}; // No audio
}

// ============================================================================
// IStateSerializer
// ============================================================================

void TempusPlugin::serializeStateToLua(sol::state& lua) const {
    auto state = lua.create_table();
    
    state["projectionVersion"] = 1;
    state["type"] = "firstloop";
    state["numVoices"] = 0;
    
    auto params = lua.create_table();
    params["/firstloop/tempo"] = detectedTempo_.load();
    params["/firstloop/targetbpm"] = targetBPM_.load();
    params["/firstloop/detectedbars"] = detectedBars_.load();
    params["/firstloop/detecting"] = isDetecting_.load() ? 1 : 0;
    params["/firstloop/linkenabled"] = linkEnabled_.load() ? 1 : 0;
    params["/firstloop/linkpeers"] = getLinkNumPeers();
    
    state["params"] = params;
    state["voices"] = lua.create_table();
    
    // Link state
    auto linkState = lua.create_table();
    linkState["enabled"] = linkEnabled_.load();
    linkState["tempoSync"] = linkTempoSync_.load();
    linkState["startStopSync"] = false;
    linkState["peers"] = getLinkNumPeers();
    linkState["playing"] = false;
    linkState["beat"] = getLinkBeat();
    linkState["phase"] = getLinkPhase();
    state["link"] = linkState;
    
    // Detection result
    auto result = lua.create_table();
    result["tempo"] = lastResult_.tempo;
    result["bars"] = lastResult_.bars;
    result["duration"] = lastResult_.durationSeconds;
    state["detection"] = result;
    
    lua["state"] = state;
}

std::string TempusPlugin::serializeStateToJson() const {
    // Minimal JSON
    return "{}";
}

std::vector<IStateSerializer::StateField> TempusPlugin::getStateSchema() const {
    return {
        {"/firstloop/tempo", "f", "Detected tempo", 20.0f, 300.0f, 3, false, -1},
        {"/firstloop/targetbpm", "f", "Target BPM for detection", 20.0f, 300.0f, 3, false, -1},
        {"/firstloop/detectedbars", "f", "Detected bar length", 0.0625f, 16.0f, 1, false, -1},
        {"/firstloop/detecting", "i", "Currently detecting", 0.0f, 1.0f, 3, false, -1},
        {"/firstloop/linkenabled", "i", "Link enabled", 0.0f, 1.0f, 3, false, -1},
    };
}

std::string TempusPlugin::getValueAtPath(const std::string& path) const {
    float val = getParamByPath(path);
    return std::to_string(val);
}

bool TempusPlugin::hasPathChanged(const std::string& /*path*/) const {
    return false; // TODO: implement change tracking
}

void TempusPlugin::updateChangeCache() {}
void TempusPlugin::subscribeToPath(const std::string& /*path*/, StateChangeCallback /*callback*/) {}
void TempusPlugin::unsubscribeFromPath(const std::string& /*path*/) {}
void TempusPlugin::clearSubscriptions() {}
void TempusPlugin::processPendingChanges() {
    // Poll Link to update peer count and other state
    // Since we don't have an audio thread, we poll with 0 samples
    if (linkSync_ && linkEnabled_.load()) {
        linkSync_->processAudio(0);
    }
}

// ============================================================================
// Link
// ============================================================================

void TempusPlugin::setLinkEnabled(bool enabled) {
    linkEnabled_.store(enabled);
    if (linkSync_) {
        linkSync_->setEnabled(enabled);
    }
}

int TempusPlugin::getLinkNumPeers() const {
    return linkSync_ ? linkSync_->getNumPeers() : 0;
}

bool TempusPlugin::isLinkPlaying() const {
    return linkSync_ ? linkSync_->getIsPlaying() : false;
}

double TempusPlugin::getLinkBeat() const {
    return linkSync_ ? linkSync_->getBeat() : 0.0;
}

double TempusPlugin::getLinkPhase() const {
    return linkSync_ ? linkSync_->getPhase() : 0.0;
}

void TempusPlugin::requestLinkTempo(double bpm) {
    if (linkSync_) {
        linkSync_->requestTempo(bpm);
    }
}

void TempusPlugin::processLinkPendingRequests() {
    if (linkSync_) {
        linkSync_->processPendingRequests();
    }
}

// JUCE plugin entry point
#include "TempusEditor.h"
#include <juce_audio_processors/juce_audio_processors.h>

class TempusProcessorWrapper : public juce::AudioProcessor {
public:
    TempusProcessorWrapper()
        : juce::AudioProcessor(BusesProperties()
                               .withInput("Input", juce::AudioChannelSet::stereo(), true)
                               .withOutput("Output", juce::AudioChannelSet::stereo(), true)) {
    }

    void prepareToPlay(double sampleRate, int samplesPerBlock) override {
        (void)sampleRate;
        (void)samplesPerBlock;
    }
    
    void releaseResources() override {}
    
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) override {
        // Poll Link for updates
        plugin.processPendingChanges();
        
        // No audio processing - just clear output
        buffer.clear();
    }
    
    juce::AudioProcessorEditor* createEditor() override {
        return new TempusEditor(this, plugin);
    }
    
    bool hasEditor() const override { return true; }
    
    const juce::String getName() const override { return JucePlugin_Name; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    
    void getStateInformation(juce::MemoryBlock&) override {}
    void setStateInformation(const void*, int) override {}

private:
    TempusPlugin plugin;
};

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new TempusProcessorWrapper();
}

// ============================================================================
// First Loop Detection
// ============================================================================

void TempusPlugin::startDetection() {
    isDetecting_.store(true);
    detectionStart_ = std::chrono::steady_clock::now();
}

void TempusPlugin::stopDetection() {
    if (!isDetecting_.load()) return;
    
    auto end = std::chrono::steady_clock::now();
    float durationSeconds = std::chrono::duration<float>(end - detectionStart_).count();
    
    lastResult_ = inferTempoAndBars(durationSeconds);
    
    detectedTempo_.store(lastResult_.tempo);
    detectedBars_.store(lastResult_.bars);
    isDetecting_.store(false);
    commitCount_++;
    
    // Sync to Link if enabled
    if (linkEnabled_.load() && linkSync_) {
        linkSync_->requestTempo(lastResult_.tempo);
    }
}

void TempusPlugin::setTargetBPM(float bpm) {
    targetBPM_.store(std::clamp(bpm, 20.0f, 300.0f));
}

TempusPlugin::DetectionResult TempusPlugin::inferTempoAndBars(float durationSeconds) {
    DetectionResult result;
    result.durationSeconds = durationSeconds;
    
    if (durationSeconds <= 0.0f) {
        result.tempo = 120.0f;
        result.bars = 2.0f;
        return result;
    }
    
    float targetBpm = targetBPM_.load();
    float bestTempo = 120.0f;
    float bestBars = 2.0f;
    float bestDistance = 9999.0f;
    
    float minutes = durationSeconds / 60.0f;
    
    for (float bars : kAllowedBars) {
        float beats = bars * 4.0f;
        float tempo = beats / minutes;
        float distance = std::abs(tempo - targetBpm);
        
        if (distance < bestDistance) {
            bestDistance = distance;
            bestTempo = tempo;
            bestBars = bars;
        }
    }
    
    result.tempo = bestTempo;
    result.bars = bestBars;
    return result;
}

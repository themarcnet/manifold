#include "BehaviorCoreProcessor.h"

#include "BehaviorCoreEditor.h"
#include "../primitives/control/OSCSettingsPersistence.h"
#include "../primitives/core/Settings.h"
#include "../primitives/scripting/DSPPluginScriptHost.h"
#include "../primitives/scripting/GraphRuntime.h"

#include <sol/sol.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#if defined(__GLIBC__)
#include <malloc.h>
#endif

namespace {

struct ProcessorMemorySnapshot {
    int64_t pssBytes = 0;
    int64_t privateDirtyBytes = 0;
    int64_t heapUsedBytes = 0;
    int64_t arenaBytes = 0;
};

ProcessorMemorySnapshot readProcessorMemorySnapshot() {
    ProcessorMemorySnapshot snapshot;
    std::ifstream smaps("/proc/self/smaps_rollup");
    std::string line;
    while (std::getline(smaps, line)) {
        if (line.rfind("Pss:", 0) == 0) {
            std::istringstream iss(line);
            std::string label, unit;
            int64_t kb = 0;
            iss >> label >> kb >> unit;
            snapshot.pssBytes = kb * 1024;
        } else if (line.rfind("Private_Dirty:", 0) == 0) {
            std::istringstream iss(line);
            std::string label, unit;
            int64_t kb = 0;
            iss >> label >> kb >> unit;
            snapshot.privateDirtyBytes = kb * 1024;
        }
    }
#if defined(__GLIBC__)
    const auto mi = mallinfo2();
    snapshot.heapUsedBytes = static_cast<int64_t>(mi.uordblks);
    snapshot.arenaBytes = static_cast<int64_t>(mi.arena);
#endif
    return snapshot;
}

void updateTimingStage(FrameTimingStage& stage, int64_t durationUs) {
    stage.currentUs.store(durationUs, std::memory_order_relaxed);
    const int64_t previousPeak = stage.peakUs.load(std::memory_order_relaxed);
    if (durationUs > previousPeak) {
        stage.peakUs.store(durationUs, std::memory_order_relaxed);
    }
    constexpr int64_t alphaNum = 5;
    constexpr int64_t alphaDen = 100;
    const int64_t previousAvgX100 = stage.avgUsX100.load(std::memory_order_relaxed);
    const int64_t durationX100 = durationUs * 100;
    const int64_t nextAvgX100 =
        (previousAvgX100 == 0)
            ? durationX100
            : ((previousAvgX100 * (alphaDen - alphaNum)) + (durationX100 * alphaNum)) / alphaDen;
    stage.avgUsX100.store(nextAvgX100, std::memory_order_relaxed);
}

constexpr float kDefaultTempo = 120.0f;
constexpr float kDefaultTargetBpm = 120.0f;
constexpr float kDefaultMasterVolume = 1.0f;
constexpr float kDefaultInputVolume = 1.0f;

std::string normalizeRendererModeToken(std::string mode) {
    std::transform(mode.begin(), mode.end(), mode.begin(), [](unsigned char c) {
        if (c >= 'A' && c <= 'Z') {
            return static_cast<char>(c - 'A' + 'a');
        }
        return c == '_' ? '-' : static_cast<char>(c);
    });

    if (mode == "0" || mode == "off" || mode == "false") {
        return "canvas";
    }
    if (mode == "1" || mode == "on" || mode == "true" || mode == "imgui" || mode == "overlay") {
        return "imgui-overlay";
    }
    if (mode == "full" || mode == "replace" || mode == "imgui-full") {
        return "imgui-replace";
    }
    if (mode == "direct") {
        return "imgui-direct";
    }
    return mode;
}

BehaviorCoreEditor::RootMode rootModeFromEnvironmentOrState(const ControlServer& controlServer) {
    if (const char* envRenderer = std::getenv("MANIFOLD_RENDERER")) {
        const auto normalized = normalizeRendererModeToken(envRenderer);
        if (normalized == "canvas" || normalized == "imgui-overlay" || normalized == "imgui-replace") {
            return BehaviorCoreEditor::RootMode::Canvas;
        }
        return BehaviorCoreEditor::RootMode::RuntimeNode;
    }

    switch (controlServer.getCurrentUIRendererMode()) {
        case 0:
        case 1:
        case 2:
            return BehaviorCoreEditor::RootMode::Canvas;
        case 3:
        default:
            return BehaviorCoreEditor::RootMode::RuntimeNode;
    }
}

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

bool isProjectManifestFile(const juce::File& file) {
    return file.existsAsFile() && file.getFileName().equalsIgnoreCase("manifold.project.json5");
}

juce::File resolveProjectAssetRef(const juce::File& projectRoot, const juce::String& ref) {
    if (ref.isEmpty()) {
        return {};
    }

    if (juce::File::isAbsolutePath(ref)) {
        return juce::File(ref);
    }

    return projectRoot.getChildFile(ref);
}

juce::File resolveDefaultDspScriptFromProject(const juce::File& requestedPath) {
    if (!isProjectManifestFile(requestedPath)) {
        return {};
    }

    const auto json = juce::JSON::parse(requestedPath);
    if (!json.isObject()) {
        return {};
    }

    auto* obj = json.getDynamicObject();
    if (obj == nullptr || !obj->hasProperty("dsp")) {
        return {};
    }

    auto dspVar = obj->getProperty("dsp");
    if (!dspVar.isObject()) {
        return {};
    }

    auto* dspObj = dspVar.getDynamicObject();
    if (dspObj == nullptr || !dspObj->hasProperty("default")) {
        return {};
    }

    const auto dspRef = dspObj->getProperty("default").toString();
    if (dspRef.isEmpty()) {
        return {};
    }

    return resolveProjectAssetRef(requestedPath.getParentDirectory(), dspRef);
}

int readIntProperty(juce::DynamicObject* obj, const char* name, int fallback) {
    if (obj == nullptr || !obj->hasProperty(name)) {
        return fallback;
    }
    return static_cast<int>(obj->getProperty(name));
}

bool readBoolProperty(juce::DynamicObject* obj, const char* name, bool fallback) {
    if (obj == nullptr || !obj->hasProperty(name)) {
        return fallback;
    }
    return static_cast<bool>(obj->getProperty(name));
}

BehaviorCoreProcessor::ExportPluginConfig resolveExportPluginConfig(const juce::File& requestedPath) {
    BehaviorCoreProcessor::ExportPluginConfig config;
    if (!isProjectManifestFile(requestedPath)) {
        return config;
    }

    const auto json = juce::JSON::parse(requestedPath);
    if (!json.isObject()) {
        return config;
    }

    auto* obj = json.getDynamicObject();
    if (obj == nullptr || !obj->hasProperty("plugin")) {
        return config;
    }

    auto pluginVar = obj->getProperty("plugin");
    if (!pluginVar.isObject()) {
        return config;
    }

    auto* pluginObj = pluginVar.getDynamicObject();
    if (pluginObj == nullptr) {
        return config;
    }

    config.enabled = true;
    if (obj->hasProperty("name")) {
        config.headerTitle = obj->getProperty("name").toString();
    }

    if (pluginObj->hasProperty("headerTitle")) {
        config.headerTitle = pluginObj->getProperty("headerTitle").toString();
    }

    auto viewVar = pluginObj->getProperty("view");
    if (viewVar.isObject()) {
        auto* viewObj = viewVar.getDynamicObject();
        if (viewObj != nullptr) {
            if (viewObj->hasProperty("defaultMode")) {
                const auto defaultMode = viewObj->getProperty("defaultMode").toString().trim().toLowerCase();
                config.defaultViewMode = defaultMode == "compact" ? 0 : 1;
            }

            auto compactVar = viewObj->getProperty("compact");
            if (compactVar.isObject()) {
                auto* compactObj = compactVar.getDynamicObject();
                config.compactWidth = readIntProperty(compactObj, "w", config.compactWidth);
                config.compactHeight = readIntProperty(compactObj, "h", config.compactHeight);
            }

            auto splitVar = viewObj->getProperty("split");
            if (splitVar.isObject()) {
                auto* splitObj = splitVar.getDynamicObject();
                config.splitWidth = readIntProperty(splitObj, "w", config.splitWidth);
                config.splitHeight = readIntProperty(splitObj, "h", config.splitHeight);
            }
        }
    }

    auto oscVar = pluginObj->getProperty("osc");
    if (oscVar.isObject()) {
        auto* oscObj = oscVar.getDynamicObject();
        if (oscObj != nullptr) {
            config.oscDefaultEnabled = readBoolProperty(oscObj, "enabled", config.oscDefaultEnabled);
            config.oscQueryDefaultEnabled = readBoolProperty(oscObj, "queryEnabled", config.oscQueryDefaultEnabled);
            config.oscBasePort = readIntProperty(oscObj, "basePort", config.oscBasePort);
        }
    }

    auto paramsVar = pluginObj->getProperty("params");
    if (paramsVar.isArray()) {
        for (const auto& item : *paramsVar.getArray()) {
            auto* paramObj = item.getDynamicObject();
            if (paramObj == nullptr || !paramObj->hasProperty("path") || !paramObj->hasProperty("internalPath")) {
                continue;
            }

            BehaviorCoreProcessor::ExportParamAlias alias;
            alias.path = paramObj->getProperty("path").toString();
            alias.internalPath = paramObj->getProperty("internalPath").toString();
            alias.type = paramObj->hasProperty("type") ? paramObj->getProperty("type").toString() : juce::String("f");
            alias.rangeMin = static_cast<float>(paramObj->hasProperty("min") ? static_cast<double>(paramObj->getProperty("min")) : 0.0);
            alias.rangeMax = static_cast<float>(paramObj->hasProperty("max") ? static_cast<double>(paramObj->getProperty("max")) : 1.0);
            alias.defaultValue = static_cast<float>(paramObj->hasProperty("default")
                ? static_cast<double>(paramObj->getProperty("default"))
                : static_cast<double>(alias.rangeMin));
            alias.skew = static_cast<float>(paramObj->hasProperty("skew")
                ? static_cast<double>(paramObj->getProperty("skew"))
                : 1.0);
            alias.hostParamId = paramObj->hasProperty("hostParamId")
                ? paramObj->getProperty("hostParamId").toString()
                : juce::String();
            alias.hostParamName = paramObj->hasProperty("hostParamName")
                ? paramObj->getProperty("hostParamName").toString()
                : alias.hostParamId;
            alias.hostParamKind = paramObj->hasProperty("hostParamKind")
                ? paramObj->getProperty("hostParamKind").toString()
                : juce::String("float");
            if (paramObj->hasProperty("choices")) {
                auto choicesVar = paramObj->getProperty("choices");
                if (choicesVar.isArray()) {
                    for (const auto& choice : *choicesVar.getArray()) {
                        alias.choices.add(choice.toString());
                    }
                }
            }
            alias.description = paramObj->hasProperty("description")
                ? paramObj->getProperty("description").toString()
                : alias.path;
            if (alias.path.isNotEmpty() && alias.internalPath.isNotEmpty()) {
                config.paramAliases.push_back(alias);
            }
        }
    }

    return config;
}

bool isUdpPortAvailable(int port) {
    if (port <= 0) {
        return false;
    }
    juce::DatagramSocket socket(false);
    const bool ok = socket.bindToPort(port);
    if (ok) {
        socket.shutdown();
    }
    return ok;
}

bool isTcpPortAvailable(int port) {
    if (port <= 0) {
        return false;
    }
    juce::StreamingSocket socket;
    const bool ok = socket.createListener(port, "127.0.0.1");
    if (ok) {
        socket.close();
    }
    return ok;
}

void findAvailableOscPortPair(int preferredBasePort, int& oscPort, int& queryPort) {
    const int base = preferredBasePort > 0 ? preferredBasePort : 9010;
    for (int offset = 0; offset < 200; offset += 2) {
        const int candidateOsc = base + offset;
        const int candidateQuery = candidateOsc + 1;
        if (isUdpPortAvailable(candidateOsc) && isTcpPortAvailable(candidateQuery)) {
            oscPort = candidateOsc;
            queryPort = candidateQuery;
            return;
        }
    }

    oscPort = base;
    queryPort = base + 1;
}

} // namespace

BehaviorCoreProcessor::BehaviorCoreProcessor()
    : juce::AudioProcessor(BusesProperties()
                               .withInput("Input", juce::AudioChannelSet::stereo(), true)
                               .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      primitiveGraph(std::make_shared<dsp_primitives::PrimitiveGraph>()),
      dspScriptHost(std::make_unique<DSPPluginScriptHost>()),
      midiManager_(std::make_shared<midi::MidiManager>()) {
    capturePluginConstructionBaseline();
    if (dspScriptHost) {
        dspScriptHost->initialise(this, "/core/behavior");
    }
    endpointRegistry.setNumLayers(MAX_LAYERS);
    initialiseExportPluginConfig();
    endpointRegistry.setBackendEnabled(!exportPluginConfig_.enabled);
    endpointRegistry.rebuild();
    initialiseHostParameters();
    registerExportPluginEndpoints();
    initialiseAtomicState(currentSampleRate.load(std::memory_order_relaxed));
}

BehaviorCoreProcessor::~BehaviorCoreProcessor() {
    if (hostParams_) {
        for (const auto& alias : exportPluginConfig_.paramAliases) {
            if (!alias.hostParamId.isEmpty()) {
                hostParams_->removeParameterListener(alias.hostParamId, this);
            }
        }
    }
    releaseResources();
}

void BehaviorCoreProcessor::initialiseExportPluginConfig() {
    auto& settings = Settings::getInstance();
    const juce::File uiTarget(settings.getDefaultUiScript());
    exportPluginConfig_ = resolveExportPluginConfig(uiTarget);
    if (!exportPluginConfig_.enabled) {
        return;
    }

    exportViewMode_.store(exportPluginConfig_.defaultViewMode, std::memory_order_relaxed);
    exportEditorWidth_.store(exportPluginConfig_.defaultViewMode == 0
                                 ? exportPluginConfig_.compactWidth
                                 : exportPluginConfig_.splitWidth,
                             std::memory_order_relaxed);
    exportEditorHeight_.store(exportPluginConfig_.defaultViewMode == 0
                                  ? exportPluginConfig_.compactHeight
                                  : exportPluginConfig_.splitHeight,
                              std::memory_order_relaxed);
    exportSettingsVisible_.store(false, std::memory_order_relaxed);
    exportDevVisible_.store(false, std::memory_order_relaxed);
    exportOscEnabled_.store(exportPluginConfig_.oscDefaultEnabled, std::memory_order_relaxed);
    exportOscQueryEnabled_.store(exportPluginConfig_.oscQueryDefaultEnabled,
                                 std::memory_order_relaxed);
    exportOscInputPort_.store(exportPluginConfig_.oscBasePort, std::memory_order_relaxed);
    exportOscQueryPort_.store(exportPluginConfig_.oscBasePort + 1, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::initialiseHostParameters() {
    if (!exportPluginConfig_.enabled) {
        hostParams_.reset();
        return;
    }

    std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
    params.reserve(exportPluginConfig_.paramAliases.size());

    for (auto& alias : exportPluginConfig_.paramAliases) {
        alias.rawHostValue = nullptr;
        if (alias.hostParamId.isEmpty()) {
            continue;
        }

        const auto kind = alias.hostParamKind.trim().toLowerCase();
        if (kind == "choice" && alias.choices.size() > 0) {
            params.push_back(std::make_unique<juce::AudioParameterChoice>(
                juce::ParameterID(alias.hostParamId, 1),
                alias.hostParamName.isNotEmpty() ? alias.hostParamName : alias.hostParamId,
                alias.choices,
                juce::jlimit(0, alias.choices.size() - 1,
                             static_cast<int>(std::round(alias.defaultValue)))));
        } else {
            juce::NormalisableRange<float> range(alias.rangeMin, alias.rangeMax);
            if (alias.skew > 0.0f && std::abs(alias.skew - 1.0f) > 1.0e-4f) {
                range.skew = alias.skew;
            }
            params.push_back(std::make_unique<juce::AudioParameterFloat>(
                juce::ParameterID(alias.hostParamId, 1),
                alias.hostParamName.isNotEmpty() ? alias.hostParamName : alias.hostParamId,
                range,
                juce::jlimit(alias.rangeMin, alias.rangeMax, alias.defaultValue)));
        }
    }

    hostParams_ = std::make_unique<juce::AudioProcessorValueTreeState>(
        *this,
        nullptr,
        "HostParameters",
        juce::AudioProcessorValueTreeState::ParameterLayout{params.begin(), params.end()});

    for (auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.hostParamId.isEmpty()) {
            continue;
        }
        alias.rawHostValue = hostParams_->getRawParameterValue(alias.hostParamId);
        hostParams_->addParameterListener(alias.hostParamId, this);
    }
}

void BehaviorCoreProcessor::registerExportPluginEndpoints() {
    if (!exportPluginConfig_.enabled) {
        return;
    }

    const juce::StringArray uiPaths{
        "/plugin/ui/viewMode",
        "/plugin/ui/settingsVisible",
        "/plugin/ui/devVisible",
        "/plugin/ui/oscEnabled",
        "/plugin/ui/oscQueryEnabled",
        "/plugin/ui/oscInputPort",
        "/plugin/ui/oscQueryPort",
        "/plugin/ui/perf/frameCurrentUs",
        "/plugin/ui/perf/frameAvgUs",
        "/plugin/ui/perf/framePeakUs",
        "/plugin/ui/perf/dspCurrentUs",
        "/plugin/ui/perf/dspAvgUs",
        "/plugin/ui/perf/dspPeakUs",
        "/plugin/ui/perf/uiUpdateUs",
        "/plugin/ui/perf/renderUs",
        "/plugin/ui/perf/paintUs",
        "/plugin/ui/perf/cpuPercent",
        "/plugin/ui/perf/pssMB",
        "/plugin/ui/perf/privateDirtyMB",
        "/plugin/ui/perf/pluginDeltaPssMB",
        "/plugin/ui/perf/pluginDeltaPrivateDirtyMB",
        "/plugin/ui/perf/pluginDeltaHeapMB",
        "/plugin/ui/perf/uiDeltaPssMB",
        "/plugin/ui/perf/uiDeltaPrivateDirtyMB",
        "/plugin/ui/perf/uiDeltaHeapMB",
        "/plugin/ui/perf/afterLuaInitDeltaPssMB",
        "/plugin/ui/perf/afterLuaInitDeltaPrivateDirtyMB",
        "/plugin/ui/perf/afterBindingsDeltaPssMB",
        "/plugin/ui/perf/afterBindingsDeltaPrivateDirtyMB",
        "/plugin/ui/perf/afterScriptLoadDeltaPssMB",
        "/plugin/ui/perf/afterScriptLoadDeltaPrivateDirtyMB",
        "/plugin/ui/perf/afterDspDeltaPssMB",
        "/plugin/ui/perf/afterDspDeltaPrivateDirtyMB",
        "/plugin/ui/perf/afterUiOpenDeltaPssMB",
        "/plugin/ui/perf/afterUiOpenDeltaPrivateDirtyMB",
        "/plugin/ui/perf/afterUiIdleDeltaPssMB",
        "/plugin/ui/perf/afterUiIdleDeltaPrivateDirtyMB",
        "/plugin/ui/perf/luaHeapMB",
        "/plugin/ui/perf/glibcHeapMB",
        "/plugin/ui/perf/glibcArenaMB",
        "/plugin/ui/perf/glibcMmapMB",
        "/plugin/ui/perf/glibcFreeHeldMB",
        "/plugin/ui/perf/glibcReleasableMB",
        "/plugin/ui/perf/glibcArenaCount",
        "/plugin/ui/perf/gpuFontAtlasMB",
        "/plugin/ui/perf/gpuSurfaceColorMB",
        "/plugin/ui/perf/gpuSurfaceDepthMB",
        "/plugin/ui/perf/gpuTotalMB",
        "/plugin/ui/perf/runtimeNodeCount",
        "/plugin/ui/perf/runtimeNodeMB",
        "/plugin/ui/perf/runtimeCallbackCount",
        "/plugin/ui/perf/runtimeUserDataEntries",
        "/plugin/ui/perf/runtimeUserDataMB",
        "/plugin/ui/perf/runtimePayloadMB",
        "/plugin/ui/perf/displayListCount",
        "/plugin/ui/perf/displayListCommands",
        "/plugin/ui/perf/displayListMB",
        "/plugin/ui/perf/renderSnapshotNodes",
        "/plugin/ui/perf/renderSnapshotMB",
        "/plugin/ui/perf/customSurfaceStateMB",
        "/plugin/ui/perf/scriptSourceKB",
        "/plugin/ui/perf/luaGlobalCount",
        "/plugin/ui/perf/luaRegistryEntryCount",
        "/plugin/ui/perf/luaPackageLoadedCount",
        "/plugin/ui/perf/luaOscPathCount",
        "/plugin/ui/perf/luaOscCallbackCount",
        "/plugin/ui/perf/luaOscQueryHandlerCount",
        "/plugin/ui/perf/luaEventListenerCount",
        "/plugin/ui/perf/luaManagedDspSlotCount",
        "/plugin/ui/perf/luaOverlayCacheCount",
        "/plugin/ui/perf/endpointTotalCount",
        "/plugin/ui/perf/endpointCustomCount",
        "/plugin/ui/perf/endpointPathKB",
        "/plugin/ui/perf/endpointDescriptionKB",
        "/plugin/ui/perf/dspHostCount",
        "/plugin/ui/perf/dspScriptSourceKB",
        "/plugin/ui/perf/imguiWindowCount",
        "/plugin/ui/perf/imguiTableCount",
        "/plugin/ui/perf/imguiTabBarCount",
        "/plugin/ui/perf/imguiViewportCount",
        "/plugin/ui/perf/imguiFontCount",
        "/plugin/ui/perf/imguiWindowStateMB",
        "/plugin/ui/perf/imguiDrawBufferMB",
        "/plugin/ui/perf/imguiInternalStateMB",
        "/plugin/ui/perf/shellScriptListRows",
        "/plugin/ui/perf/shellScriptListMB",
        "/plugin/ui/perf/shellHierarchyRows",
        "/plugin/ui/perf/shellHierarchyMB",
        "/plugin/ui/perf/shellInspectorRows",
        "/plugin/ui/perf/shellInspectorMB",
        "/plugin/ui/perf/shellScriptInspectorMB",
        "/plugin/ui/perf/shellMainEditorTextKB"
    };

    for (const auto& path : uiPaths) {
        endpointRegistry.unregisterCustomEndpoint(path);
    }
    for (const auto& alias : exportPluginConfig_.paramAliases) {
        endpointRegistry.unregisterCustomEndpoint(alias.path);
    }

    auto registerUiEndpoint = [this](const juce::String& path,
                                     float minValue,
                                     float maxValue,
                                     int access,
                                     const juce::String& description) {
        OSCEndpoint endpoint;
        endpoint.path = path;
        endpoint.type = "f";
        endpoint.rangeMin = minValue;
        endpoint.rangeMax = maxValue;
        endpoint.access = access;
        endpoint.description = description;
        endpoint.category = "plugin-ui";
        endpoint.commandType = ControlCommand::Type::None;
        endpoint.layerIndex = -1;
        endpointRegistry.registerCustomEndpoint(endpoint);
    };

    registerUiEndpoint("/plugin/ui/viewMode", 0.0f, 1.0f, 3,
                       "Plugin export view mode (0=compact, 1=split)");
    registerUiEndpoint("/plugin/ui/settingsVisible", 0.0f, 1.0f, 3,
                       "Plugin export settings/dev panel visible (0/1)");
    registerUiEndpoint("/plugin/ui/devVisible", 0.0f, 1.0f, 3,
                       "Plugin export dev/perf detail visible (0/1)");
    registerUiEndpoint("/plugin/ui/oscEnabled", 0.0f, 1.0f, 3,
                       "Plugin OSC enable (0/1)");
    registerUiEndpoint("/plugin/ui/oscQueryEnabled", 0.0f, 1.0f, 3,
                       "Plugin OSCQuery enable (0/1)");
    registerUiEndpoint("/plugin/ui/oscInputPort", 0.0f, 65535.0f, 1,
                       "Active OSC UDP input port");
    registerUiEndpoint("/plugin/ui/oscQueryPort", 0.0f, 65535.0f, 1,
                       "Active OSCQuery HTTP port");
    registerUiEndpoint("/plugin/ui/perf/frameCurrentUs", 0.0f, 1000000.0f, 1,
                       "Current editor frame time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/frameAvgUs", 0.0f, 1000000.0f, 1,
                       "Average editor frame time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/framePeakUs", 0.0f, 1000000.0f, 1,
                       "Peak editor frame time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/dspCurrentUs", 0.0f, 1000000.0f, 1,
                       "Current DSP block time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/dspAvgUs", 0.0f, 1000000.0f, 1,
                       "Average DSP block time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/dspPeakUs", 0.0f, 1000000.0f, 1,
                       "Peak DSP block time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/uiUpdateUs", 0.0f, 1000000.0f, 1,
                       "Structured UI update time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/renderUs", 0.0f, 1000000.0f, 1,
                       "ImGui/direct render time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/paintUs", 0.0f, 1000000.0f, 1,
                       "Canvas paint time in microseconds");
    registerUiEndpoint("/plugin/ui/perf/cpuPercent", 0.0f, 100.0f, 1,
                       "CPU utilization percent (0-100)");
    registerUiEndpoint("/plugin/ui/perf/pssMB", 0.0f, 8192.0f, 1,
                       "Process proportional set size in megabytes");
    registerUiEndpoint("/plugin/ui/perf/privateDirtyMB", 0.0f, 8192.0f, 1,
                       "Process private dirty memory in megabytes");
    registerUiEndpoint("/plugin/ui/perf/pluginDeltaPssMB", 0.0f, 8192.0f, 1,
                       "Plugin-attributable PSS delta from processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/pluginDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Plugin-attributable private dirty delta from processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/pluginDeltaHeapMB", 0.0f, 8192.0f, 1,
                       "Plugin-attributable heap delta from processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/uiDeltaPssMB", -8192.0f, 8192.0f, 1,
                       "UI-attributable PSS delta since editor opened");
    registerUiEndpoint("/plugin/ui/perf/uiDeltaPrivateDirtyMB", -8192.0f, 8192.0f, 1,
                       "UI-attributable private dirty delta since editor opened");
    registerUiEndpoint("/plugin/ui/perf/uiDeltaHeapMB", -8192.0f, 8192.0f, 1,
                       "UI-attributable heap delta since editor opened");
    registerUiEndpoint("/plugin/ui/perf/afterLuaInitDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after Lua VM init relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterLuaInitDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after Lua VM init relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterBindingsDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after binding registration relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterBindingsDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after binding registration relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterScriptLoadDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after script load relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterScriptLoadDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after script load relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterDspDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after DSP boot relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterDspDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after DSP boot relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterUiOpenDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after UI open relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterUiOpenDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after UI open relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterUiIdleDeltaPssMB", 0.0f, 8192.0f, 1,
                       "PSS delta after UI idle settle relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/afterUiIdleDeltaPrivateDirtyMB", 0.0f, 8192.0f, 1,
                       "Private dirty delta after UI idle settle relative to processor construction baseline");
    registerUiEndpoint("/plugin/ui/perf/luaHeapMB", 0.0f, 512.0f, 1,
                       "Lua VM heap in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcHeapMB", 0.0f, 8192.0f, 1,
                       "glibc heap allocated in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcArenaMB", 0.0f, 8192.0f, 1,
                       "glibc arena bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcMmapMB", 0.0f, 8192.0f, 1,
                       "glibc mmap bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcFreeHeldMB", 0.0f, 8192.0f, 1,
                       "glibc free-but-held bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcReleasableMB", 0.0f, 8192.0f, 1,
                       "glibc releasable top bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/glibcArenaCount", 0.0f, 2048.0f, 1,
                       "glibc arena count");
    registerUiEndpoint("/plugin/ui/perf/gpuFontAtlasMB", 0.0f, 8192.0f, 1,
                       "Plugin-owned ImGui font atlas bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/gpuSurfaceColorMB", 0.0f, 8192.0f, 1,
                       "Plugin-owned offscreen color surface bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/gpuSurfaceDepthMB", 0.0f, 8192.0f, 1,
                       "Plugin-owned offscreen depth surface bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/gpuTotalMB", 0.0f, 8192.0f, 1,
                       "Total plugin-owned GPU bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/runtimeNodeCount", 0.0f, 1000000.0f, 1,
                       "RuntimeNode count");
    registerUiEndpoint("/plugin/ui/perf/runtimeNodeMB", 0.0f, 8192.0f, 1,
                       "RuntimeNode tree object/string/vector bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/runtimeCallbackCount", 0.0f, 1000000.0f, 1,
                       "Bound RuntimeNode callback count");
    registerUiEndpoint("/plugin/ui/perf/runtimeUserDataEntries", 0.0f, 1000000.0f, 1,
                       "RuntimeNode userdata entry count");
    registerUiEndpoint("/plugin/ui/perf/runtimeUserDataMB", 0.0f, 8192.0f, 1,
                       "RuntimeNode userdata bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/runtimePayloadMB", 0.0f, 8192.0f, 1,
                       "RuntimeNode display/custom payload bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/displayListCount", 0.0f, 1000000.0f, 1,
                       "Compiled display list count");
    registerUiEndpoint("/plugin/ui/perf/displayListCommands", 0.0f, 10000000.0f, 1,
                       "Compiled display list command count");
    registerUiEndpoint("/plugin/ui/perf/displayListMB", 0.0f, 8192.0f, 1,
                       "Compiled display list bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/renderSnapshotNodes", 0.0f, 1000000.0f, 1,
                       "Render snapshot node count across pending/active/gl snapshots");
    registerUiEndpoint("/plugin/ui/perf/renderSnapshotMB", 0.0f, 8192.0f, 1,
                       "Render snapshot bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/customSurfaceStateMB", 0.0f, 8192.0f, 1,
                       "Custom shader surface CPU-side state bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/scriptSourceKB", 0.0f, 1048576.0f, 1,
                       "Current loaded script file size in kilobytes");
    registerUiEndpoint("/plugin/ui/perf/luaGlobalCount", 0.0f, 1000000.0f, 1,
                       "Lua global table entry count");
    registerUiEndpoint("/plugin/ui/perf/luaRegistryEntryCount", 0.0f, 10000000.0f, 1,
                       "Lua registry entry count");
    registerUiEndpoint("/plugin/ui/perf/luaPackageLoadedCount", 0.0f, 1000000.0f, 1,
                       "Lua package.loaded entry count");
    registerUiEndpoint("/plugin/ui/perf/luaOscPathCount", 0.0f, 1000000.0f, 1,
                       "Lua OSC path count");
    registerUiEndpoint("/plugin/ui/perf/luaOscCallbackCount", 0.0f, 1000000.0f, 1,
                       "Lua OSC callback count");
    registerUiEndpoint("/plugin/ui/perf/luaOscQueryHandlerCount", 0.0f, 1000000.0f, 1,
                       "Lua OSCQuery handler count");
    registerUiEndpoint("/plugin/ui/perf/luaEventListenerCount", 0.0f, 1000000.0f, 1,
                       "Lua event listener count");
    registerUiEndpoint("/plugin/ui/perf/luaManagedDspSlotCount", 0.0f, 1000000.0f, 1,
                       "Lua managed DSP slot count");
    registerUiEndpoint("/plugin/ui/perf/luaOverlayCacheCount", 0.0f, 1000000.0f, 1,
                       "Lua overlay cache entry count");
    registerUiEndpoint("/plugin/ui/perf/endpointTotalCount", 0.0f, 1000000.0f, 1,
                       "Total endpoint count");
    registerUiEndpoint("/plugin/ui/perf/endpointCustomCount", 0.0f, 1000000.0f, 1,
                       "Custom endpoint count");
    registerUiEndpoint("/plugin/ui/perf/endpointPathKB", 0.0f, 1048576.0f, 1,
                       "Endpoint path bytes in kilobytes");
    registerUiEndpoint("/plugin/ui/perf/endpointDescriptionKB", 0.0f, 1048576.0f, 1,
                       "Endpoint description bytes in kilobytes");
    registerUiEndpoint("/plugin/ui/perf/dspHostCount", 0.0f, 1000000.0f, 1,
                       "DSP host count (default + slots)");
    registerUiEndpoint("/plugin/ui/perf/dspScriptSourceKB", 0.0f, 1048576.0f, 1,
                       "Primary DSP script source file size in kilobytes");
    registerUiEndpoint("/plugin/ui/perf/imguiWindowCount", 0.0f, 1000000.0f, 1,
                       "ImGui window count");
    registerUiEndpoint("/plugin/ui/perf/imguiTableCount", 0.0f, 1000000.0f, 1,
                       "ImGui table count");
    registerUiEndpoint("/plugin/ui/perf/imguiTabBarCount", 0.0f, 1000000.0f, 1,
                       "ImGui tab bar count");
    registerUiEndpoint("/plugin/ui/perf/imguiViewportCount", 0.0f, 1000000.0f, 1,
                       "ImGui viewport count");
    registerUiEndpoint("/plugin/ui/perf/imguiFontCount", 0.0f, 1000000.0f, 1,
                       "ImGui font count");
    registerUiEndpoint("/plugin/ui/perf/imguiWindowStateMB", 0.0f, 8192.0f, 1,
                       "ImGui CPU-side window/state bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/imguiDrawBufferMB", 0.0f, 8192.0f, 1,
                       "ImGui CPU-side draw buffer bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/imguiInternalStateMB", 0.0f, 8192.0f, 1,
                       "ImGui total CPU-side internal bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/shellScriptListRows", 0.0f, 1000000.0f, 1,
                       "Script list row count");
    registerUiEndpoint("/plugin/ui/perf/shellScriptListMB", 0.0f, 8192.0f, 1,
                       "Script list retained bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/shellHierarchyRows", 0.0f, 1000000.0f, 1,
                       "Hierarchy row count");
    registerUiEndpoint("/plugin/ui/perf/shellHierarchyMB", 0.0f, 8192.0f, 1,
                       "Hierarchy retained bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/shellInspectorRows", 0.0f, 1000000.0f, 1,
                       "Inspector row count");
    registerUiEndpoint("/plugin/ui/perf/shellInspectorMB", 0.0f, 8192.0f, 1,
                       "Inspector retained bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/shellScriptInspectorMB", 0.0f, 8192.0f, 1,
                       "Script inspector retained bytes in megabytes");
    registerUiEndpoint("/plugin/ui/perf/shellMainEditorTextKB", 0.0f, 1048576.0f, 1,
                       "Main editor text size in kilobytes");

    for (const auto& alias : exportPluginConfig_.paramAliases) {
        OSCEndpoint endpoint;
        endpoint.path = alias.path;
        endpoint.type = alias.type;
        endpoint.rangeMin = alias.rangeMin;
        endpoint.rangeMax = alias.rangeMax;
        endpoint.access = 3;
        endpoint.description = alias.description;
        endpoint.category = "plugin-param";
        endpoint.commandType = ControlCommand::Type::None;
        endpoint.layerIndex = -1;
        endpointRegistry.registerCustomEndpoint(endpoint);
    }

    oscQueryServer.rebuildTree();
}

juce::String BehaviorCoreProcessor::resolveExportInternalPath(const juce::String& path) const {
    for (const auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.path == path) {
            return alias.internalPath;
        }
    }
    return {};
}

BehaviorCoreProcessor::ExportParamAlias* BehaviorCoreProcessor::findExportAliasByPublicPath(const juce::String& path) {
    for (auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.path == path) {
            return &alias;
        }
    }
    return nullptr;
}

const BehaviorCoreProcessor::ExportParamAlias* BehaviorCoreProcessor::findExportAliasByPublicPath(const juce::String& path) const {
    for (const auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.path == path) {
            return &alias;
        }
    }
    return nullptr;
}

BehaviorCoreProcessor::ExportParamAlias* BehaviorCoreProcessor::findExportAliasByHostParamId(const juce::String& hostParamId) {
    for (auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.hostParamId == hostParamId) {
            return &alias;
        }
    }
    return nullptr;
}

const BehaviorCoreProcessor::ExportParamAlias* BehaviorCoreProcessor::findExportAliasByHostParamId(const juce::String& hostParamId) const {
    for (const auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.hostParamId == hostParamId) {
            return &alias;
        }
    }
    return nullptr;
}

bool BehaviorCoreProcessor::syncPublicPathToHostParameter(const juce::String& publicPath, float value) {
    if (!hostParams_) {
        return false;
    }

    auto* alias = findExportAliasByPublicPath(publicPath);
    if (alias == nullptr || alias->hostParamId.isEmpty()) {
        return false;
    }

    auto* parameter = hostParams_->getParameter(alias->hostParamId);
    auto* ranged = dynamic_cast<juce::RangedAudioParameter*>(parameter);
    if (ranged == nullptr) {
        return false;
    }

    const float clamped = juce::jlimit(alias->rangeMin, alias->rangeMax, value);
    const float current = alias->rawHostValue != nullptr ? alias->rawHostValue->load() : clamped;
    if (std::abs(current - clamped) <= 1.0e-6f) {
        return true;
    }

    ranged->setValueNotifyingHost(ranged->convertTo0to1(clamped));
    return true;
}

void BehaviorCoreProcessor::applyHostParameterSnapshotToProcessor() {
    if (!hostParams_) {
        return;
    }

    for (const auto& alias : exportPluginConfig_.paramAliases) {
        if (alias.internalPath.isEmpty() || alias.hostParamId.isEmpty()) {
            continue;
        }
        const float value = alias.rawHostValue != nullptr ? alias.rawHostValue->load() : alias.defaultValue;
        setParamByPath(alias.internalPath.toStdString(), value);
    }
}

void BehaviorCoreProcessor::parameterChanged(const juce::String& parameterID, float newValue) {
    if (suppressHostParameterCallbacks_.load(std::memory_order_relaxed)) {
        return;
    }

    auto* alias = findExportAliasByHostParamId(parameterID);
    if (alias == nullptr || alias->internalPath.isEmpty()) {
        return;
    }

    setParamByPath(alias->internalPath.toStdString(), newValue);
}

bool BehaviorCoreProcessor::applyExportPluginPath(const std::string& path, float value) {
    if (!exportPluginConfig_.enabled) {
        return false;
    }

    if (path == "/plugin/ui/viewMode") {
        const int nextMode = value >= 0.5f ? 1 : 0;
        exportViewMode_.store(nextMode, std::memory_order_relaxed);
        return true;
    }

    if (path == "/plugin/ui/settingsVisible") {
        exportSettingsVisible_.store(value > 0.5f, std::memory_order_relaxed);
        return true;
    }

    if (path == "/plugin/ui/devVisible") {
        exportDevVisible_.store(value > 0.5f, std::memory_order_relaxed);
        return true;
    }

    if (path == "/plugin/ui/oscEnabled") {
        const bool enabled = value > 0.5f;
        exportOscEnabled_.store(enabled, std::memory_order_relaxed);
        if (!enabled) {
            exportOscQueryEnabled_.store(false, std::memory_order_relaxed);
        }
        applyExportOscSettings();
        return true;
    }

    if (path == "/plugin/ui/oscQueryEnabled") {
        const bool enabled = value > 0.5f;
        exportOscQueryEnabled_.store(enabled, std::memory_order_relaxed);
        if (enabled) {
            exportOscEnabled_.store(true, std::memory_order_relaxed);
        }
        applyExportOscSettings();
        return true;
    }

    const juce::String publicPath(path);
    const auto internalPath = resolveExportInternalPath(publicPath);
    if (internalPath.isNotEmpty()) {
        if (syncPublicPathToHostParameter(publicPath, value)) {
            return true;
        }
        return setParamByPath(internalPath.toStdString(), value);
    }

    return false;
}

float BehaviorCoreProcessor::readExportPluginPath(const std::string& path) const {
    if (!exportPluginConfig_.enabled) {
        return 0.0f;
    }

    if (path == "/plugin/ui/viewMode") {
        return static_cast<float>(exportViewMode_.load(std::memory_order_relaxed));
    }
    if (path == "/plugin/ui/settingsVisible") {
        return exportSettingsVisible_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/plugin/ui/devVisible") {
        return exportDevVisible_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/plugin/ui/oscEnabled") {
        return exportOscEnabled_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/plugin/ui/oscQueryEnabled") {
        return exportOscQueryEnabled_.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
    }
    if (path == "/plugin/ui/oscInputPort") {
        return static_cast<float>(exportOscInputPort_.load(std::memory_order_relaxed));
    }
    if (path == "/plugin/ui/oscQueryPort") {
        return static_cast<float>(exportOscQueryPort_.load(std::memory_order_relaxed));
    }

    if (auto* timings = controlServer.getFrameTimings()) {
        if (path == "/plugin/ui/perf/frameCurrentUs") {
            return static_cast<float>(timings->total.currentUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/frameAvgUs") {
            return static_cast<float>(timings->total.getAvgUs());
        }
        if (path == "/plugin/ui/perf/framePeakUs") {
            return static_cast<float>(timings->total.peakUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/dspCurrentUs") {
            return static_cast<float>(timings->dsp.currentUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/dspAvgUs") {
            return static_cast<float>(timings->dsp.getAvgUs());
        }
        if (path == "/plugin/ui/perf/dspPeakUs") {
            return static_cast<float>(timings->dsp.peakUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/uiUpdateUs") {
            return static_cast<float>(timings->uiUpdate.currentUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/renderUs") {
            return static_cast<float>(timings->imguiRenderUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/paintUs") {
            return static_cast<float>(timings->paint.currentUs.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/cpuPercent") {
            return timings->cpuPercent.load(std::memory_order_relaxed);
        }
        if (path == "/plugin/ui/perf/pssMB") {
            const int64_t bytes = timings->processPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/privateDirtyMB") {
            const int64_t bytes = timings->privateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/pluginDeltaPssMB") {
            const int64_t bytes = timings->pluginDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/pluginDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->pluginDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/pluginDeltaHeapMB") {
            const int64_t bytes = timings->pluginDeltaHeapBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/uiDeltaPssMB") {
            const int64_t bytes = timings->uiDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/uiDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->uiDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/uiDeltaHeapMB") {
            const int64_t bytes = timings->uiDeltaHeapBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterLuaInitDeltaPssMB") {
            const int64_t bytes = timings->afterLuaInitDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterLuaInitDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterLuaInitDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterBindingsDeltaPssMB") {
            const int64_t bytes = timings->afterBindingsDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterBindingsDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterBindingsDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterScriptLoadDeltaPssMB") {
            const int64_t bytes = timings->afterScriptLoadDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterScriptLoadDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterScriptLoadDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterDspDeltaPssMB") {
            const int64_t bytes = timings->afterDspDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterDspDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterDspDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterUiOpenDeltaPssMB") {
            const int64_t bytes = timings->afterUiOpenDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterUiOpenDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterUiOpenDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterUiIdleDeltaPssMB") {
            const int64_t bytes = timings->afterUiIdleDeltaPssBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/afterUiIdleDeltaPrivateDirtyMB") {
            const int64_t bytes = timings->afterUiIdleDeltaPrivateDirtyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/luaHeapMB") {
            const int64_t bytes = timings->luaHeapBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcHeapMB") {
            const int64_t bytes = timings->glibcHeapUsedBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcArenaMB") {
            const int64_t bytes = timings->glibcArenaBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcMmapMB") {
            const int64_t bytes = timings->glibcMmapBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcFreeHeldMB") {
            const int64_t bytes = timings->glibcFreeHeldBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcReleasableMB") {
            const int64_t bytes = timings->glibcReleasableBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/glibcArenaCount") {
            return static_cast<float>(timings->glibcArenaCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/gpuFontAtlasMB") {
            const int64_t bytes = timings->gpuFontAtlasBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/gpuSurfaceColorMB") {
            const int64_t bytes = timings->gpuSurfaceColorBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/gpuSurfaceDepthMB") {
            const int64_t bytes = timings->gpuSurfaceDepthBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/gpuTotalMB") {
            const int64_t bytes = timings->gpuTotalBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/runtimeNodeCount") {
            return static_cast<float>(timings->runtimeNodeCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/runtimeNodeMB") {
            const int64_t bytes = timings->runtimeNodeBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/runtimeCallbackCount") {
            return static_cast<float>(timings->runtimeCallbackCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/runtimeUserDataEntries") {
            return static_cast<float>(timings->runtimeUserDataEntries.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/runtimeUserDataMB") {
            const int64_t bytes = timings->runtimeUserDataBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/runtimePayloadMB") {
            const int64_t bytes = timings->runtimeCustomPayloadBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/displayListCount") {
            return static_cast<float>(timings->displayListCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/displayListCommands") {
            return static_cast<float>(timings->displayListCommandCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/displayListMB") {
            const int64_t bytes = timings->displayListBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/renderSnapshotNodes") {
            return static_cast<float>(timings->renderSnapshotNodeCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/renderSnapshotMB") {
            const int64_t bytes = timings->renderSnapshotBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/customSurfaceStateMB") {
            const int64_t bytes = timings->customSurfaceStateBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/scriptSourceKB") {
            const int64_t bytes = timings->scriptSourceBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / 1024.0);
        }
        if (path == "/plugin/ui/perf/luaGlobalCount") {
            return static_cast<float>(timings->luaGlobalCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaRegistryEntryCount") {
            return static_cast<float>(timings->luaRegistryEntryCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaPackageLoadedCount") {
            return static_cast<float>(timings->luaPackageLoadedCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaOscPathCount") {
            return static_cast<float>(timings->luaOscPathCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaOscCallbackCount") {
            return static_cast<float>(timings->luaOscCallbackCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaOscQueryHandlerCount") {
            return static_cast<float>(timings->luaOscQueryHandlerCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaEventListenerCount") {
            return static_cast<float>(timings->luaEventListenerCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaManagedDspSlotCount") {
            return static_cast<float>(timings->luaManagedDspSlotCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/luaOverlayCacheCount") {
            return static_cast<float>(timings->luaOverlayCacheCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/endpointTotalCount") {
            return static_cast<float>(timings->endpointTotalCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/endpointCustomCount") {
            return static_cast<float>(timings->endpointCustomCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/endpointPathKB") {
            const int64_t bytes = timings->endpointPathBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / 1024.0);
        }
        if (path == "/plugin/ui/perf/endpointDescriptionKB") {
            const int64_t bytes = timings->endpointDescriptionBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / 1024.0);
        }
        if (path == "/plugin/ui/perf/dspHostCount") {
            return static_cast<float>(timings->dspHostCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/dspScriptSourceKB") {
            const int64_t bytes = timings->dspScriptSourceBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / 1024.0);
        }
        if (path == "/plugin/ui/perf/imguiWindowCount") {
            return static_cast<float>(timings->imguiWindowCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/imguiTableCount") {
            return static_cast<float>(timings->imguiTableCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/imguiTabBarCount") {
            return static_cast<float>(timings->imguiTabBarCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/imguiViewportCount") {
            return static_cast<float>(timings->imguiViewportCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/imguiFontCount") {
            return static_cast<float>(timings->imguiFontCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/imguiWindowStateMB") {
            const int64_t bytes = timings->imguiWindowStateBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/imguiDrawBufferMB") {
            const int64_t bytes = timings->imguiDrawBufferBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/imguiInternalStateMB") {
            const int64_t bytes = timings->imguiInternalStateBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/shellScriptListRows") {
            return static_cast<float>(timings->shellScriptListRowCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/shellScriptListMB") {
            const int64_t bytes = timings->shellScriptListBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/shellHierarchyRows") {
            return static_cast<float>(timings->shellHierarchyRowCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/shellHierarchyMB") {
            const int64_t bytes = timings->shellHierarchyBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/shellInspectorRows") {
            return static_cast<float>(timings->shellInspectorRowCount.load(std::memory_order_relaxed));
        }
        if (path == "/plugin/ui/perf/shellInspectorMB") {
            const int64_t bytes = timings->shellInspectorBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/shellScriptInspectorMB") {
            const int64_t bytes = timings->shellScriptInspectorBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / (1024.0 * 1024.0));
        }
        if (path == "/plugin/ui/perf/shellMainEditorTextKB") {
            const int64_t bytes = timings->shellMainEditorTextBytes.load(std::memory_order_relaxed);
            return static_cast<float>(bytes / 1024.0);
        }
    }

    const auto* alias = findExportAliasByPublicPath(juce::String(path));
    if (alias != nullptr) {
        if (alias->rawHostValue != nullptr) {
            return alias->rawHostValue->load();
        }
        if (alias->internalPath.isNotEmpty()) {
            return getParamByPath(alias->internalPath.toStdString());
        }
    }

    return 0.0f;
}

void BehaviorCoreProcessor::applyExportOscSettings() {
    if (!exportPluginConfig_.enabled) {
        return;
    }

    const bool oscEnabled = exportOscEnabled_.load(std::memory_order_relaxed);
    const bool oscQueryEnabled = exportOscQueryEnabled_.load(std::memory_order_relaxed) && oscEnabled;
    int oscPort = exportOscInputPort_.load(std::memory_order_relaxed);
    int queryPort = exportOscQueryPort_.load(std::memory_order_relaxed);

    if (oscEnabled || oscQueryEnabled) {
        findAvailableOscPortPair(oscPort > 0 ? oscPort : exportPluginConfig_.oscBasePort,
                                 oscPort,
                                 queryPort);
    } else {
        oscPort = exportPluginConfig_.oscBasePort;
        queryPort = exportPluginConfig_.oscBasePort + 1;
    }

    exportOscInputPort_.store(oscPort, std::memory_order_relaxed);
    exportOscQueryPort_.store(queryPort, std::memory_order_relaxed);

    oscQueryServer.stop();
    oscServer.stop();

    OSCSettings settings;
    settings.inputPort = oscPort;
    settings.queryPort = queryPort;
    settings.oscEnabled = oscEnabled;
    settings.oscQueryEnabled = oscQueryEnabled;
    oscServer.setSettings(settings);
    oscServer.start(this);
    oscQueryServer.setContext(this, &endpointRegistry);
    if (oscQueryEnabled) {
        oscQueryServer.start(this, &endpointRegistry, queryPort, oscPort);
    }
}

void BehaviorCoreProcessor::capturePluginConstructionBaseline() {
    const auto snapshot = readProcessorMemorySnapshot();
    pluginBaselinePssBytes_.store(snapshot.pssBytes, std::memory_order_relaxed);
    pluginBaselinePrivateDirtyBytes_.store(snapshot.privateDirtyBytes, std::memory_order_relaxed);
    pluginBaselineHeapBytes_.store(snapshot.heapUsedBytes, std::memory_order_relaxed);
    pluginBaselineArenaBytes_.store(snapshot.arenaBytes, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureLuaInitSnapshot() {
    if (luaInitSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    afterLuaInitDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterLuaInitDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureBindingsSnapshot() {
    if (bindingsSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    afterBindingsDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterBindingsDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureScriptLoadSnapshot() {
    if (scriptLoadSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    afterScriptLoadDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterScriptLoadDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureDspLoadedSnapshot() {
    if (dspLoadedSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    afterDspDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterDspDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureEditorOpenSnapshot() {
    if (editorOpenSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    editorOpenPssBytes_.store(snapshot.pssBytes, std::memory_order_relaxed);
    editorOpenPrivateDirtyBytes_.store(snapshot.privateDirtyBytes, std::memory_order_relaxed);
    editorOpenHeapBytes_.store(snapshot.heapUsedBytes, std::memory_order_relaxed);
    afterUiOpenDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterUiOpenDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

void BehaviorCoreProcessor::captureUiIdleSnapshot() {
    if (uiIdleSnapshotCaptured_.exchange(true, std::memory_order_relaxed)) {
        return;
    }
    const auto baselinePss = pluginBaselinePssBytes_.load(std::memory_order_relaxed);
    const auto baselinePriv = pluginBaselinePrivateDirtyBytes_.load(std::memory_order_relaxed);
    const auto snapshot = readProcessorMemorySnapshot();
    afterUiIdleDeltaPssBytes_.store(snapshot.pssBytes - baselinePss, std::memory_order_relaxed);
    afterUiIdleDeltaPrivateDirtyBytes_.store(snapshot.privateDirtyBytes - baselinePriv, std::memory_order_relaxed);
}

bool BehaviorCoreProcessor::hasExportPluginConfig() const {
    return exportPluginConfig_.enabled;
}

int BehaviorCoreProcessor::getExportViewMode() const {
    return exportViewMode_.load(std::memory_order_relaxed);
}

int BehaviorCoreProcessor::getExportCompactWidth() const {
    return exportPluginConfig_.compactWidth;
}

int BehaviorCoreProcessor::getExportCompactHeight() const {
    return exportPluginConfig_.compactHeight;
}

int BehaviorCoreProcessor::getExportSplitWidth() const {
    return exportPluginConfig_.splitWidth;
}

int BehaviorCoreProcessor::getExportSplitHeight() const {
    return exportPluginConfig_.splitHeight;
}

int BehaviorCoreProcessor::getExportEditorWidth() const {
    return exportEditorWidth_.load(std::memory_order_relaxed);
}

int BehaviorCoreProcessor::getExportEditorHeight() const {
    return exportEditorHeight_.load(std::memory_order_relaxed);
}

int64_t BehaviorCoreProcessor::getPrimaryDspScriptSizeBytes() const {
    return (dspScriptHost && dspScriptHost->getCurrentScriptFile().existsAsFile())
               ? static_cast<int64_t>(dspScriptHost->getCurrentScriptFile().getSize())
               : 0;
}

juce::AudioProcessorValueTreeState* BehaviorCoreProcessor::getHostParameterState() const {
    return hostParams_.get();
}

bool BehaviorCoreProcessor::isExportSettingsVisible() const {
    return exportSettingsVisible_.load(std::memory_order_relaxed);
}

void BehaviorCoreProcessor::setExportEditorSize(int width, int height) {
    if (!exportPluginConfig_.enabled) {
        return;
    }
    exportEditorWidth_.store(std::max(1, width), std::memory_order_relaxed);
    exportEditorHeight_.store(std::max(1, height), std::memory_order_relaxed);
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
    monitorInputBuffer.setSize(2, currentBlockSize.load(std::memory_order_relaxed), false, true, true);
    forwardScheduled = false;
    forwardFireAtSample = 0.0;
    forwardScheduledBars = 0.0f;

    endpointRegistry.setNumLayers(MAX_LAYERS);
    endpointRegistry.rebuild();

    controlServer.start(this);

    auto& coreSettings = Settings::getInstance();

    if (dspScriptHost && !dspScriptHost->isLoaded()) {
        const juce::File defaultUiTarget(coreSettings.getDefaultUiScript());
        const juce::File projectDspScript = resolveDefaultDspScriptFromProject(defaultUiTarget);

        if (projectDspScript.existsAsFile()) {
            if (!loadDspScript(projectDspScript)) {
                std::fprintf(stderr,
                             "BehaviorCoreProcessor: failed to load project DSP script '%s': %s\n",
                             projectDspScript.getFullPathName().toRawUTF8(),
                             getDspScriptLastError().c_str());
            }
        } else {
            const auto dspScriptsDir = coreSettings.getDspScriptsDir();
            if (dspScriptsDir.isEmpty()) {
                std::fprintf(stderr,
                             "BehaviorCoreProcessor: settings.dspScriptsDir is empty; default DSP script not loaded\n");
            } else {
                const juce::File defaultDspScript =
                    juce::File(dspScriptsDir).getChildFile("looper_primitives_dsp.lua");
                if (!defaultDspScript.existsAsFile()) {
                    std::fprintf(stderr,
                                 "BehaviorCoreProcessor: configured default DSP script missing: %s\n"
                                 "  -> Configure dspScriptsDir in .manifold.settings.json in the repo root.\n",
                                 defaultDspScript.getFullPathName().toRawUTF8());
                } else if (!loadDspScript(defaultDspScript)) {
                    std::fprintf(stderr,
                                 "BehaviorCoreProcessor: failed to load default DSP script: %s\n",
                                 getDspScriptLastError().c_str());
                }
            }
        }
    }

    applyHostParameterSnapshotToProcessor();

    // Primitives behavior runtime is graph-driven; keep graph active by default.
    graphProcessingEnabled.store(true, std::memory_order_relaxed);

    if (exportPluginConfig_.enabled) {
        applyExportOscSettings();
    } else {
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
        oscQueryServer.setContext(this, &endpointRegistry);

        if (oscSettings.oscQueryEnabled) {
            oscQueryServer.start(this, &endpointRegistry, oscSettings.queryPort,
                                 oscSettings.inputPort);
        }
    }

    initialiseAtomicState(currentSampleRate.load(std::memory_order_relaxed));

    // Initialize Ableton Link (enabled by default)
    linkSync.initialise(currentSampleRate.load(std::memory_order_relaxed));
    linkSync.setEnabled(true);
    linkSync.setTempoSyncEnabled(true);

    captureDspLoadedSnapshot();
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
    juce::ScopedNoDenormals noDenormals;
    const auto dspStart = std::chrono::steady_clock::now();

    // Process incoming MIDI from host/plugin
    processMidiInput(midiMessages);
    
    // Also process MIDI from hardware device (written to ring buffer by handleIncomingMidiMessage)
    juce::MidiBuffer hardwareMidi;
    uint8_t status, data1, data2;
    int32_t timestamp;
    while (midiInputRing.read(status, data1, data2, timestamp)) {
        hardwareMidi.addEvent(juce::MidiMessage(status, data1, data2), 0);
    }
    if (!hardwareMidi.isEmpty()) {
        processMidiInput(hardwareMidi, false);
    }

    // MIDI thru: forward incoming MIDI to output if enabled
    juce::MidiBuffer midiThruBuffer;
    if (midiThruEnabled) {
        midiThruBuffer = midiMessages;
    }

    processControlCommands();
    checkGraphRuntimeSwap();

    // Process Ableton Link - updates tempo from network if sync enabled
    const int numSamples = buffer.getNumSamples();
    if (linkSync.processAudio(numSamples)) {
        // Tempo was updated from Link, update atomic state and forward to DSP
        auto& state = controlServer.getAtomicState();
        const double linkTempo = linkSync.getTempo();
        state.tempo.store(static_cast<float>(linkTempo), std::memory_order_relaxed);
        state.samplesPerBar.store(computeSamplesPerBar(
                                    static_cast<float>(linkTempo),
                                    currentSampleRate.load(std::memory_order_relaxed)),
                                std::memory_order_relaxed);
        // Forward tempo change to DSP script
        if (dspScriptHost) {
            (void)dspScriptHost->setParam("/core/behavior/tempo", static_cast<float>(linkTempo));
        }
        for (auto& entry : dspSlots) {
            auto* host = entry.second.get();
            if (host != nullptr) {
                (void)host->setParam("/core/behavior/tempo", static_cast<float>(linkTempo));
            }
        }
    }

    const int numChannels = buffer.getNumChannels();
    float* outL = numChannels > 0 ? buffer.getWritePointer(0) : nullptr;
    float* outR = numChannels > 1 ? buffer.getWritePointer(1) : outL;

    auto& state = controlServer.getAtomicState();

    // Input volume controls level going into looper (capture + graph)
    const float inputVolume = state.inputVolume.load(std::memory_order_relaxed);

    // Capture-plane source comes from incoming block before any output scaling.
    // Use the same write pointers legacy uses for in-place host buffers.
    const float* captureL = outL;
    const float* captureR = outR;

    // Capture-plane source buffer is always fed from incoming input stream
    // (or injected stream when INJECT is active), before any wet/dry mixing.
    // Apply inputVolume to capture so input knob controls what goes into looper.
    if (controlServer.isInjecting()) {
        controlServer.drainInjection(captureBuffer, numSamples, inputVolume);
    } else if (captureL != nullptr) {
        captureBuffer.writeBlock(captureL, numSamples, 0, inputVolume);
        if (captureR != nullptr) {
            captureBuffer.writeBlock(captureR, numSamples, 1, inputVolume);
        }
    }

    state.captureSize.store(captureBuffer.getSize(), std::memory_order_relaxed);
    state.captureWritePos.store(captureBuffer.getOffsetToNow(), std::memory_order_relaxed);
    const float wetGain = state.masterVolume.load(std::memory_order_relaxed);

    const bool graphEnabled = graphProcessingEnabled.load(std::memory_order_relaxed);
    state.graphEnabled.store(graphEnabled, std::memory_order_relaxed);

    const bool canProcessGraph =
        graphEnabled &&
        activeRuntime != nullptr &&
        graphWetBuffer.getNumChannels() >= numChannels &&
        graphWetBuffer.getNumSamples() >= numSamples &&
        monitorInputBuffer.getNumChannels() >= numChannels &&
        monitorInputBuffer.getNumSamples() >= numSamples;
    const bool mutationPauseRequested =
        graphMutationPauseRequested.load(std::memory_order_acquire);

    if (canProcessGraph && !mutationPauseRequested) {
        graphProcessDepth.fetch_add(1, std::memory_order_acq_rel);
        // INPUT -> INPUT-DSP: always active at inputVolume.
        for (int ch = 0; ch < numChannels; ++ch) {
            graphWetBuffer.copyFrom(ch, 0, buffer, ch, 0, numSamples);
            graphWetBuffer.applyGain(ch, 0, numSamples, inputVolume);
        }

        // INPUT-DSP -> Monitor branch: monitor-toggle-controlled source.
        const bool passthroughEnabled = state.passthroughEnabled.load(std::memory_order_relaxed);
        const float monitorInputGain = passthroughEnabled ? inputVolume : 0.0f;
        for (int ch = 0; ch < numChannels; ++ch) {
            monitorInputBuffer.copyFrom(ch, 0, buffer, ch, 0, numSamples);
            monitorInputBuffer.applyGain(ch, 0, numSamples, monitorInputGain);
        }

        float* wetPtrs[2] = {
            graphWetBuffer.getWritePointer(0),
            graphWetBuffer.getNumChannels() > 1 ? graphWetBuffer.getWritePointer(1)
                                                : graphWetBuffer.getWritePointer(0)};
        juce::AudioBuffer<float> wetView(wetPtrs, juce::jmax(1, numChannels), numSamples);

        activeRuntime->setMonitorEnabled(passthroughEnabled);
        activeRuntime->process(wetView, &monitorInputBuffer);

        // Call script process callbacks if available
        if (dspScriptHost && dspScriptHost->isLoaded()) {
            dspScriptHost->process(numSamples, currentSampleRate.load());
        }
        for (auto& entry : dspSlots) {
            auto* host = entry.second.get();
            if (host && host->isLoaded()) {
                host->process(numSamples, currentSampleRate.load());
            }
        }

        if (outL == nullptr) {
            buffer.clear();
        } else {
            const float* wetL = graphWetBuffer.getReadPointer(0);
            const float* wetR = graphWetBuffer.getNumChannels() > 1
                                    ? graphWetBuffer.getReadPointer(1)
                                    : wetL;

            for (int i = 0; i < numSamples; ++i) {
                outL[i] = wetL[i] * wetGain;
                if (outR != nullptr && outR != outL) {
                    outR[i] = wetR[i] * wetGain;
                }
            }
        }

        if (graphProcessDepth.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            std::lock_guard<std::mutex> lock(graphMutationMutex);
            graphMutationCv.notify_all();
        }
    } else {
        // No graph enabled - passthrough toggle controls direct input monitoring.
        // When ON: hear input at inputVolume level. When OFF: silence.
        const bool passthroughEnabled = state.passthroughEnabled.load(std::memory_order_relaxed);
        const float passthroughGain = passthroughEnabled ? inputVolume : 0.0f;
        if (outL == nullptr) {
            buffer.clear();
        } else {
            for (int i = 0; i < numSamples; ++i) {
                outL[i] *= passthroughGain;
                if (outR != nullptr && outR != outL) {
                    outR[i] *= passthroughGain;
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

    // Drain MIDI output messages to host MIDI buffer
    drainMidiOutput(midiMessages);

    const auto dspEnd = std::chrono::steady_clock::now();
    const auto dspUs = std::chrono::duration_cast<std::chrono::microseconds>(dspEnd - dspStart).count();
    if (auto* timings = controlServer.getFrameTimings()) {
        updateTimingStage(timings->dsp, dspUs);
    }
}

juce::AudioProcessorEditor* BehaviorCoreProcessor::createEditor() {
    return new BehaviorCoreEditor(*this, rootModeFromEnvironmentOrState(controlServer));
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

void BehaviorCoreProcessor::beginGraphMutation() {
    std::unique_lock<std::mutex> lock(graphMutationMutex);
    graphMutationPauseRequested.store(true, std::memory_order_release);
    graphMutationRestoreEnabled = graphProcessingEnabled.exchange(false, std::memory_order_acq_rel);
    controlServer.getAtomicState().graphEnabled.store(false, std::memory_order_relaxed);
    graphMutationCv.wait(lock, [this]() {
        return graphProcessDepth.load(std::memory_order_acquire) == 0;
    });
}

void BehaviorCoreProcessor::endGraphMutation() {
    {
        std::lock_guard<std::mutex> lock(graphMutationMutex);
        graphMutationPauseRequested.store(false, std::memory_order_release);
        graphProcessingEnabled.store(graphMutationRestoreEnabled, std::memory_order_release);
        controlServer.getAtomicState().graphEnabled.store(graphMutationRestoreEnabled,
                                                          std::memory_order_relaxed);
        graphMutationRestoreEnabled = false;
    }
    graphMutationCv.notify_all();
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
    // TODO(shamanic): replace this empty-script unload + markUnloaded() split
    // with a proper slot lifecycle model. Right now we preserve the VM/runtime
    // for stability but lie about loaded-state so UI/project switches will
    // force a clean reload. That is the right tactical fix, but the long-term
    // architecture should make slot residency, script identity, and endpoint
    // lifetime explicit instead of inferred from this shim.
    const bool ok = it->second->loadScriptFromString(
        "function buildPlugin(ctx) return {} end", "unload:" + slot);
    if (ok) {
        it->second->markUnloaded();
    }
    return ok;
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

std::shared_ptr<dsp_primitives::IPrimitiveNode>
BehaviorCoreProcessor::getGraphNodeByPath(const std::string& path) {
    if (dspScriptHost) {
        auto node = dspScriptHost->getGraphNodeByPath(path);
        if (node) {
            return node;
        }
    }

    for (auto& entry : dspSlots) {
        auto* host = entry.second.get();
        if (host == nullptr) {
            continue;
        }
        auto node = host->getGraphNodeByPath(path);
        if (node) {
            return node;
        }
    }

    return {};
}

bool BehaviorCoreProcessor::extractLayerParam(const std::string& path,
                                              int& layerIndex,
                                              std::string& paramSuffix) {
    static const std::array<std::string, 3> prefixes = {
        "/core/behavior/layer/",
        "/manifold/layer/",
        "/dsp/manifold/layer/",
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
    if (applyExportPluginPath(path, value)) {
        return true;
    }

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
    if (exportPluginConfig_.enabled) {
        const float exportValue = readExportPluginPath(path);
        if (path.rfind("/plugin/", 0) == 0 || resolveExportInternalPath(juce::String(path)).isNotEmpty()) {
            return exportValue;
        }
    }

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

    if (exportPluginConfig_.enabled) {
        if (path.rfind("/plugin/", 0) == 0 || resolveExportInternalPath(juce::String(path)).isNotEmpty()) {
            const auto endpoint = endpointRegistry.findEndpoint(juce::String(path));
            if (endpoint.path.isNotEmpty()) {
                return true;
            }
        }
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

bool BehaviorCoreProcessor::computeSynthSamplePeaks(int numBuckets,
                                                    std::vector<float>& outPeaks) const {
    if (dspScriptHost) {
        return dspScriptHost->computeSynthSamplePeaks(numBuckets, outPeaks);
    }
    return false;
}

bool BehaviorCoreProcessor::computeDynamicSamplePeaks(int slotIndex,
                                                      int numBuckets,
                                                      std::vector<float>& outPeaks) const {
    if (dspScriptHost) {
        return dspScriptHost->computeDynamicSamplePeaks(slotIndex, numBuckets, outPeaks);
    }
    return false;
}

std::vector<float> BehaviorCoreProcessor::getVoiceSamplePositions() const {
    if (dspScriptHost) {
        return dspScriptHost->getVoiceSamplePositions();
    }
    return {};
}

std::vector<float> BehaviorCoreProcessor::getDynamicSampleVoicePositions(int slotIndex) const {
    if (dspScriptHost) {
        return dspScriptHost->getDynamicSampleVoicePositions(slotIndex);
    }
    return {};
}

bool BehaviorCoreProcessor::getLatestSampleAnalysis(dsp_primitives::SampleAnalysis& outAnalysis) const {
    if (dspScriptHost) {
        return dspScriptHost->getLatestSampleAnalysis(outAnalysis);
    }
    return false;
}

bool BehaviorCoreProcessor::getLatestSamplePartials(dsp_primitives::PartialData& outPartials) const {
    if (dspScriptHost) {
        return dspScriptHost->getLatestSamplePartials(outPartials);
    }
    return false;
}

bool BehaviorCoreProcessor::getSampleDerivedAdditiveDebug(int voiceIndex,
                                                          SampleDerivedAdditiveDebugState& outState) const {
    if (dspScriptHost) {
        return dspScriptHost->getSampleDerivedAdditiveDebug(voiceIndex, outState);
    }
    return false;
}

bool BehaviorCoreProcessor::refreshSampleDerivedAdditiveDebug(SampleDerivedAdditiveDebugState& outState) {
    if (dspScriptHost) {
        return dspScriptHost->refreshSampleDerivedAdditiveDebug(outState);
    }
    return false;
}

bool BehaviorCoreProcessor::ensureDynamicModuleSlot(const std::string& specId, int slotIndex) {
    if (dspScriptHost) {
        return dspScriptHost->ensureDynamicModuleSlot(specId, slotIndex);
    }
    return false;
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
    std::array<float, 32> out{};
    std::array<float, 8> bands{};

    auto accumulateHost = [&bands](const DSPPluginScriptHost* host) {
        if (host == nullptr || !host->isLoaded()) {
            return;
        }
        const auto current = host->getSpectrumBands();
        for (size_t i = 0; i < bands.size(); ++i) {
            bands[i] = std::max(bands[i], current[i]);
        }
    };

    accumulateHost(dspScriptHost.get());
    for (const auto& entry : dspSlots) {
        accumulateHost(entry.second.get());
    }

    for (size_t i = 0; i < out.size(); ++i) {
        const float pos = (static_cast<float>(i) / static_cast<float>(out.size() - 1)) * static_cast<float>(bands.size() - 1);
        const int i0 = static_cast<int>(std::floor(pos));
        const int i1 = std::min(static_cast<int>(bands.size() - 1), i0 + 1);
        const float t = pos - static_cast<float>(i0);
        out[i] = bands[static_cast<size_t>(i0)] * (1.0f - t) + bands[static_cast<size_t>(i1)] * t;
    }

    return out;
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

std::string BehaviorCoreProcessor::getAndClearPendingUIRendererMode() {
    auto& req = controlServer.getUIRendererRequest();
    if (!req.pending.load(std::memory_order_acquire)) {
        return {};
    }

    std::lock_guard<std::mutex> lock(req.mutex);
    std::string mode = req.mode;
    req.mode.clear();
    req.pending.store(false, std::memory_order_release);
    return mode;
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

// ============================================================================
// IStateSerializer Implementation (Looper-specific state schema)
// ============================================================================

namespace {

using SerializedStateEntries = std::vector<std::pair<std::string, std::string>>;
using SerializedStateMap = std::unordered_map<std::string, std::string>;

const char* toLayerStateString(ScriptableLayerState state) {
    switch (state) {
        case ScriptableLayerState::Empty: return "empty";
        case ScriptableLayerState::Playing: return "playing";
        case ScriptableLayerState::Recording: return "recording";
        case ScriptableLayerState::Overdubbing: return "overdubbing";
        case ScriptableLayerState::Muted: return "muted";
        case ScriptableLayerState::Stopped: return "stopped";
        case ScriptableLayerState::Paused: return "paused";
        case ScriptableLayerState::Unknown: return "unknown";
    }

    return "unknown";
}

const char* toRecordModeString(int mode) {
    switch (mode) {
        case 0: return "firstLoop";
        case 1: return "freeMode";
        case 2: return "traditional";
        case 3: return "retrospective";
        default: return "firstLoop";
    }
}

std::string stringifyStateValue(bool value) {
    return value ? "1" : "0";
}

std::string stringifyStateValue(const char* value) {
    return value != nullptr ? std::string(value) : std::string{};
}

[[maybe_unused]] std::string stringifyStateValue(const std::string& value) {
    return value;
}

std::string stringifyStateValue(float value) {
    return std::to_string(value);
}

std::string stringifyStateValue(double value) {
    return std::to_string(value);
}

std::string stringifyStateValue(int value) {
    return std::to_string(value);
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           const std::string& value) {
    entries.emplace_back("/manifold" + suffix, value);
    entries.emplace_back("/core/behavior" + suffix, value);
    entries.emplace_back("/dsp/manifold" + suffix, value);
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           bool value) {
    pushAliasedStateValue(entries, suffix, stringifyStateValue(value));
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           const char* value) {
    pushAliasedStateValue(entries, suffix, stringifyStateValue(value));
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           float value) {
    pushAliasedStateValue(entries, suffix, stringifyStateValue(value));
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           double value) {
    pushAliasedStateValue(entries, suffix, stringifyStateValue(value));
}

void pushAliasedStateValue(SerializedStateEntries& entries,
                           const std::string& suffix,
                           int value) {
    pushAliasedStateValue(entries, suffix, stringifyStateValue(value));
}

std::string serializeSpectrum(const std::array<float, 32>& spectrum) {
    std::string out;
    out.reserve(spectrum.size() * 12);
    for (size_t i = 0; i < spectrum.size(); ++i) {
        if (i != 0) {
            out.push_back(',');
        }
        out += std::to_string(spectrum[i]);
    }
    return out;
}

SerializedStateEntries buildSerializedStateEntries(const BehaviorCoreProcessor& processor) {
    SerializedStateEntries entries;
    entries.reserve(192);

    const float tempo = processor.getTempo();
    const float targetBPM = processor.getTargetBPM();
    const float samplesPerBar = processor.getSamplesPerBar();
    const double sampleRate = processor.getSampleRate();
    const int captureSize = processor.getCaptureSize();
    const float masterVolume = processor.getMasterVolume();
    const float inputVolume = processor.getInputVolume();
    const bool passthroughEnabled = processor.isPassthroughEnabled();
    const bool recording = processor.isRecording();
    const bool overdubEnabled = processor.isOverdubEnabled();
    const int activeLayerIndex = processor.getActiveLayerIndex();
    const bool forwardCommitArmed = processor.isForwardCommitArmed();
    const float forwardCommitBars = processor.getForwardCommitBars();
    const char* recordModeString = toRecordModeString(processor.getRecordModeIndex());

    pushAliasedStateValue(entries, "/tempo", tempo);
    pushAliasedStateValue(entries, "/targetbpm", targetBPM);
    pushAliasedStateValue(entries, "/samplesPerBar", samplesPerBar);
    pushAliasedStateValue(entries, "/sampleRate", sampleRate);
    pushAliasedStateValue(entries, "/captureSize", captureSize);
    pushAliasedStateValue(entries, "/volume", masterVolume);
    pushAliasedStateValue(entries, "/inputVolume", inputVolume);
    pushAliasedStateValue(entries, "/passthrough", passthroughEnabled);
    pushAliasedStateValue(entries, "/recording", recording);
    pushAliasedStateValue(entries, "/overdub", overdubEnabled);
    pushAliasedStateValue(entries, "/mode", recordModeString);
    pushAliasedStateValue(entries, "/layer", activeLayerIndex);
    pushAliasedStateValue(entries, "/forwardArmed", forwardCommitArmed);
    pushAliasedStateValue(entries, "/forwardBars", forwardCommitBars);

    pushAliasedStateValue(entries, "/link/enabled", processor.isLinkEnabled());
    pushAliasedStateValue(entries, "/link/tempoSync", processor.isLinkTempoSyncEnabled());
    pushAliasedStateValue(entries, "/link/startStopSync", processor.isLinkStartStopSyncEnabled());
    pushAliasedStateValue(entries, "/link/peers", processor.getLinkNumPeers());
    pushAliasedStateValue(entries, "/link/playing", processor.isLinkPlaying());
    pushAliasedStateValue(entries, "/link/beat", processor.getLinkBeat());
    pushAliasedStateValue(entries, "/link/phase", processor.getLinkPhase());

    for (int i = 0; i < processor.getNumLayers(); ++i) {
        ScriptableLayerSnapshot layer;
        if (!processor.getLayerSnapshot(i, layer)) {
            continue;
        }

        const float normalizedPosition = layer.length > 0
                                             ? static_cast<float>(layer.position) / static_cast<float>(layer.length)
                                             : 0.0f;
        const float bars = samplesPerBar > 0.0f
                               ? static_cast<float>(layer.length) / samplesPerBar
                               : 0.0f;
        const std::string layerPrefix = "/layer/" + std::to_string(i);

        pushAliasedStateValue(entries, layerPrefix + "/speed", layer.speed);
        pushAliasedStateValue(entries, layerPrefix + "/volume", layer.volume);
        pushAliasedStateValue(entries, layerPrefix + "/mute", layer.muted);
        pushAliasedStateValue(entries, layerPrefix + "/reverse", layer.reversed);
        pushAliasedStateValue(entries, layerPrefix + "/length", layer.length);
        pushAliasedStateValue(entries, layerPrefix + "/position", normalizedPosition);
        pushAliasedStateValue(entries, layerPrefix + "/bars", bars);
        pushAliasedStateValue(entries, layerPrefix + "/state", toLayerStateString(layer.state));
    }

    const auto spectrum = processor.getSpectrumData();
    pushAliasedStateValue(entries, "/spectrum", serializeSpectrum(spectrum));

    return entries;
}

SerializedStateMap buildSerializedStateMap(const BehaviorCoreProcessor& processor) {
    auto entries = buildSerializedStateEntries(processor);
    SerializedStateMap values;
    values.reserve(entries.size());
    for (auto& entry : entries) {
        values.emplace(std::move(entry.first), std::move(entry.second));
    }
    return values;
}

bool extractBehaviorSuffix(const std::string& path, std::string& outSuffix) {
    static const std::array<std::string, 3> prefixes = {
        "/manifold",
        "/core/behavior",
        "/dsp/manifold",
    };

    for (const auto& prefix : prefixes) {
        if (path.rfind(prefix, 0) == 0) {
            outSuffix = path.substr(prefix.size());
            if (outSuffix.empty()) {
                outSuffix = "/";
            }
            return true;
        }
    }

    return false;
}

sol::table ensureLuaTable(sol::state& lua, sol::table parent, const char* key) {
    sol::object value = parent[key];
    if (value.valid() && value.is<sol::table>()) {
        return value.as<sol::table>();
    }

    sol::table table = lua.create_table();
    parent[key] = table;
    return table;
}

sol::table ensureLuaIndexedTable(sol::state& lua, sol::table parent, int index) {
    sol::object value = parent[index];
    if (value.valid() && value.is<sol::table>()) {
        return value.as<sol::table>();
    }

    sol::table table = lua.create_table();
    parent[index] = table;
    return table;
}

void updateLuaVoiceFromSnapshot(sol::state& lua,
                                sol::table voices,
                                int layerIndex,
                                const ScriptableLayerSnapshot& layer,
                                float samplesPerBar) {
    const int luaIndex = layerIndex + 1;
    const float normalizedPosition = layer.length > 0
                                         ? static_cast<float>(layer.position) / static_cast<float>(layer.length)
                                         : 0.0f;
    const float bars = samplesPerBar > 0.0f
                           ? static_cast<float>(layer.length) / samplesPerBar
                           : 0.0f;
    const char* layerStateString = toLayerStateString(layer.state);

    sol::table voice = ensureLuaIndexedTable(lua, voices, luaIndex);
    voice["id"] = layerIndex;
    voice["path"] = "/manifold/layer/" + std::to_string(layerIndex);
    voice["state"] = layerStateString;
    voice["length"] = layer.length;
    voice["position"] = layer.position;
    voice["positionNorm"] = normalizedPosition;
    voice["speed"] = layer.speed;
    voice["reversed"] = layer.reversed;
    voice["volume"] = layer.volume;
    voice["muted"] = layer.muted;
    voice["bars"] = bars;

    sol::table voiceParams = ensureLuaTable(lua, voice, "params");
    voiceParams["speed"] = layer.speed;
    voiceParams["volume"] = layer.volume;
    voiceParams["mute"] = layer.muted ? 1 : 0;
    voiceParams["reverse"] = layer.reversed ? 1 : 0;
    voiceParams["length"] = layer.length;
    voiceParams["position"] = normalizedPosition;
    voiceParams["bars"] = bars;
    voiceParams["state"] = layerStateString;
}

void updateLuaLinkFromProcessor(sol::table linkState,
                                const BehaviorCoreProcessor& processor) {
    linkState["enabled"] = processor.isLinkEnabled();
    linkState["tempoSync"] = processor.isLinkTempoSyncEnabled();
    linkState["startStopSync"] = processor.isLinkStartStopSyncEnabled();
    linkState["peers"] = processor.getLinkNumPeers();
    linkState["playing"] = processor.isLinkPlaying();
    linkState["beat"] = processor.getLinkBeat();
    linkState["phase"] = processor.getLinkPhase();
}

void updateLuaSpectrumFromProcessor(sol::state& lua,
                                    sol::table state,
                                    const BehaviorCoreProcessor& processor) {
    sol::table spectrumTable = lua.create_table();
    const auto spectrum = processor.getSpectrumData();
    for (int i = 0; i < static_cast<int>(spectrum.size()); ++i) {
        spectrumTable[i + 1] = spectrum[static_cast<size_t>(i)];
    }
    state["spectrum"] = spectrumTable;
}

bool extractLayerParamForStatePath(const std::string& path,
                                  int& layerIndex,
                                  std::string& paramSuffix) {
    static const std::array<std::string, 3> prefixes = {
        "/core/behavior/layer/",
        "/manifold/layer/",
        "/dsp/manifold/layer/",
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

        const int idx = std::atoi(rest.substr(0, slash).c_str());
        if (idx < 0 || idx >= BehaviorCoreProcessor::MAX_LAYERS) {
            return false;
        }

        layerIndex = idx;
        paramSuffix = rest.substr(slash + 1);
        return true;
    }

    return false;
}

bool applyIncrementalStatePath(sol::state& lua,
                               sol::table state,
                               sol::table params,
                               sol::table voices,
                               sol::table linkState,
                               const BehaviorCoreProcessor& processor,
                               const std::string& path) {
    std::string suffix;
    if (!extractBehaviorSuffix(path, suffix)) {
        return false;
    }

    const float samplesPerBar = processor.getSamplesPerBar();

    if (suffix == "/tempo") {
        params[path] = processor.getTempo();
        return true;
    }
    if (suffix == "/targetbpm") {
        params[path] = processor.getTargetBPM();
        return true;
    }
    if (suffix == "/samplesPerBar") {
        params[path] = samplesPerBar;
        return true;
    }
    if (suffix == "/sampleRate") {
        params[path] = processor.getSampleRate();
        return true;
    }
    if (suffix == "/captureSize") {
        params[path] = processor.getCaptureSize();
        return true;
    }
    if (suffix == "/volume") {
        params[path] = processor.getMasterVolume();
        return true;
    }
    if (suffix == "/inputVolume") {
        params[path] = processor.getInputVolume();
        return true;
    }
    if (suffix == "/passthrough") {
        params[path] = processor.isPassthroughEnabled() ? 1 : 0;
        return true;
    }
    if (suffix == "/recording") {
        params[path] = processor.isRecording() ? 1 : 0;
        return true;
    }
    if (suffix == "/overdub") {
        params[path] = processor.isOverdubEnabled() ? 1 : 0;
        return true;
    }
    if (suffix == "/mode") {
        params[path] = toRecordModeString(processor.getRecordModeIndex());
        return true;
    }
    if (suffix == "/layer") {
        params[path] = processor.getActiveLayerIndex();
        return true;
    }
    if (suffix == "/forwardArmed") {
        params[path] = processor.isForwardCommitArmed() ? 1 : 0;
        return true;
    }
    if (suffix == "/forwardBars") {
        params[path] = processor.getForwardCommitBars();
        return true;
    }
    if (suffix == "/link/enabled") {
        params[path] = processor.isLinkEnabled() ? 1 : 0;
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/tempoSync") {
        params[path] = processor.isLinkTempoSyncEnabled() ? 1 : 0;
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/startStopSync") {
        params[path] = processor.isLinkStartStopSyncEnabled() ? 1 : 0;
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/peers") {
        params[path] = processor.getLinkNumPeers();
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/playing") {
        params[path] = processor.isLinkPlaying() ? 1 : 0;
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/beat") {
        params[path] = processor.getLinkBeat();
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/link/phase") {
        params[path] = processor.getLinkPhase();
        updateLuaLinkFromProcessor(linkState, processor);
        return true;
    }
    if (suffix == "/spectrum") {
        updateLuaSpectrumFromProcessor(lua, state, processor);
        return true;
    }

    int layerIndex = -1;
    std::string layerParamSuffix;
    if (!extractLayerParamForStatePath(path, layerIndex, layerParamSuffix)) {
        return false;
    }

    ScriptableLayerSnapshot layer;
    if (!processor.getLayerSnapshot(layerIndex, layer)) {
        return false;
    }

    const float normalizedPosition = layer.length > 0
                                         ? static_cast<float>(layer.position) / static_cast<float>(layer.length)
                                         : 0.0f;
    const float bars = samplesPerBar > 0.0f
                           ? static_cast<float>(layer.length) / samplesPerBar
                           : 0.0f;

    if (layerParamSuffix == "speed") {
        params[path] = layer.speed;
    } else if (layerParamSuffix == "volume") {
        params[path] = layer.volume;
    } else if (layerParamSuffix == "mute") {
        params[path] = layer.muted ? 1 : 0;
    } else if (layerParamSuffix == "reverse") {
        params[path] = layer.reversed ? 1 : 0;
    } else if (layerParamSuffix == "length") {
        params[path] = layer.length;
    } else if (layerParamSuffix == "position") {
        params[path] = normalizedPosition;
    } else if (layerParamSuffix == "bars") {
        params[path] = bars;
    } else if (layerParamSuffix == "state") {
        params[path] = toLayerStateString(layer.state);
    } else {
        return false;
    }

    updateLuaVoiceFromSnapshot(lua, voices, layerIndex, layer, samplesPerBar);
    return true;
}

} // namespace

void BehaviorCoreProcessor::serializeStateToLua(sol::state& lua) const {
    auto state = lua.create_table();

    const float tempo = getTempo();
    const float targetBPM = getTargetBPM();
    const float samplesPerBar = getSamplesPerBar();
    const double sampleRate = getSampleRate();
    const float masterVolume = getMasterVolume();
    const float inputVolume = getInputVolume();
    const bool passthroughEnabled = isPassthroughEnabled();
    const bool recording = this->isRecording();
    const bool overdubEnabled = this->isOverdubEnabled();
    const int activeLayerIndex = getActiveLayerIndex();
    const bool forwardCommitArmed = isForwardCommitArmed();
    const float forwardCommitBars = getForwardCommitBars();
    const int recordModeIndex = getRecordModeIndex();
    const int numLayers = getNumLayers();
    const int captureSize = getCaptureSize();
    const char* recordModeString = toRecordModeString(recordModeIndex);

    state["projectionVersion"] = 2;
    state["numVoices"] = numLayers;

    auto params = lua.create_table();
    auto setBehaviorParam = [&](const std::string& suffix, const auto& value) {
        params["/manifold" + suffix] = value;
        params["/core/behavior" + suffix] = value;
        params["/dsp/manifold" + suffix] = value;
    };

    setBehaviorParam("/tempo", tempo);
    setBehaviorParam("/targetbpm", targetBPM);
    setBehaviorParam("/samplesPerBar", samplesPerBar);
    setBehaviorParam("/sampleRate", sampleRate);
    setBehaviorParam("/captureSize", captureSize);
    setBehaviorParam("/volume", masterVolume);
    setBehaviorParam("/inputVolume", inputVolume);
    setBehaviorParam("/passthrough", passthroughEnabled ? 1 : 0);
    setBehaviorParam("/recording", recording ? 1 : 0);
    setBehaviorParam("/overdub", overdubEnabled ? 1 : 0);
    setBehaviorParam("/mode", recordModeString);
    setBehaviorParam("/layer", activeLayerIndex);
    setBehaviorParam("/forwardArmed", forwardCommitArmed ? 1 : 0);
    setBehaviorParam("/forwardBars", forwardCommitBars);

    auto voices = lua.create_table();
    for (int i = 0; i < numLayers; ++i) {
        ScriptableLayerSnapshot layer;
        if (!getLayerSnapshot(i, layer)) {
            continue;
        }

        const char* layerStateString = toLayerStateString(layer.state);
        const float normalizedPosition = (layer.length > 0)
            ? static_cast<float>(layer.position) / static_cast<float>(layer.length)
            : 0.0f;
        const float bars = (samplesPerBar > 0.0f)
            ? static_cast<float>(layer.length) / samplesPerBar
            : 0.0f;
        const bool muted = layer.muted;

        const std::string manifoldLayerPrefix = "/manifold/layer/" + std::to_string(i);
        const std::string coreLayerPrefix = "/core/behavior/layer/" + std::to_string(i);
        const std::string dspLayerPrefix = "/dsp/manifold/layer/" + std::to_string(i);

        auto setLayerParam = [&](const std::string& suffix, const auto& value) {
            params[manifoldLayerPrefix + suffix] = value;
            params[coreLayerPrefix + suffix] = value;
            params[dspLayerPrefix + suffix] = value;
        };

        setLayerParam("/speed", layer.speed);
        setLayerParam("/volume", layer.volume);
        setLayerParam("/mute", muted ? 1 : 0);
        setLayerParam("/reverse", layer.reversed ? 1 : 0);
        setLayerParam("/length", layer.length);
        setLayerParam("/position", normalizedPosition);
        setLayerParam("/bars", bars);
        setLayerParam("/state", layerStateString);

        auto voice = lua.create_table();
        voice["id"] = i;
        voice["path"] = manifoldLayerPrefix;
        voice["state"] = layerStateString;
        voice["length"] = layer.length;
        voice["position"] = layer.position;
        voice["positionNorm"] = normalizedPosition;
        voice["speed"] = layer.speed;
        voice["reversed"] = layer.reversed;
        voice["volume"] = layer.volume;
        voice["muted"] = muted;
        voice["bars"] = bars;

        auto voiceParams = lua.create_table();
        voiceParams["speed"] = layer.speed;
        voiceParams["volume"] = layer.volume;
        voiceParams["mute"] = muted ? 1 : 0;
        voiceParams["reverse"] = layer.reversed ? 1 : 0;
        voiceParams["length"] = layer.length;
        voiceParams["position"] = normalizedPosition;
        voiceParams["bars"] = bars;
        voiceParams["state"] = layerStateString;
        voice["params"] = voiceParams;

        voices[i + 1] = voice;
    }

    state["params"] = params;
    state["voices"] = voices;

    // Ableton Link state
    auto linkState = lua.create_table();
    linkState["enabled"] = isLinkEnabled();
    linkState["tempoSync"] = isLinkTempoSyncEnabled();
    linkState["startStopSync"] = isLinkStartStopSyncEnabled();
    linkState["peers"] = getLinkNumPeers();
    linkState["playing"] = isLinkPlaying();
    linkState["beat"] = getLinkBeat();
    linkState["phase"] = getLinkPhase();
    state["link"] = linkState;

    // Spectrum analysis data for visualization
    auto spectrum = getSpectrumData();
    sol::table spectrumTable = lua.create_table();
    for (int i = 0; i < static_cast<int>(spectrum.size()); ++i) {
        spectrumTable[i + 1] = spectrum[static_cast<std::size_t>(i)];
    }
    state["spectrum"] = spectrumTable;

    lua["state"] = state;
}

void BehaviorCoreProcessor::serializeStateToLuaIncremental(
    sol::state& lua,
    const std::vector<std::string>& changedPaths) const {
    if (changedPaths.empty()) {
        return;
    }

    sol::object stateObj = lua["state"];
    if (!stateObj.valid() || !stateObj.is<sol::table>()) {
        serializeStateToLua(lua);
        return;
    }

    sol::table state = stateObj.as<sol::table>();
    sol::table params = ensureLuaTable(lua, state, "params");
    sol::table voices = ensureLuaTable(lua, state, "voices");
    sol::table linkState = ensureLuaTable(lua, state, "link");

    for (const auto& path : changedPaths) {
        applyIncrementalStatePath(lua, state, params, voices, linkState, *this, path);
    }
}

std::string BehaviorCoreProcessor::serializeStateToJson() const {
    // TODO: Implement JSON serialization matching Lua structure
    // For now, return minimal JSON (implement when needed for OSCQuery)
    return "{}";
}

std::vector<IStateSerializer::StateField> BehaviorCoreProcessor::getStateSchema() const {
    // TODO: Implement schema describing all manifold state paths
    // For now, return empty (implement when needed for OSCQuery)
    return {};
}

std::string BehaviorCoreProcessor::getValueAtPath(const std::string& path) const {
    const auto values = buildSerializedStateMap(*this);
    const auto it = values.find(path);
    if (it == values.end()) {
        return {};
    }
    return it->second;
}

bool BehaviorCoreProcessor::hasPathChanged(const std::string& path) const {
    const auto currentValue = getValueAtPath(path);
    std::lock_guard<std::mutex> lock(stateChangeCacheMutex_);
    const auto it = lastSerializedStateValues_.find(path);
    return it == lastSerializedStateValues_.end() || it->second != currentValue;
}

std::vector<std::string> BehaviorCoreProcessor::getChangedPathsAndUpdateCache() {
    const auto entries = buildSerializedStateEntries(*this);

    std::vector<std::string> changedPaths;
    changedPaths.reserve(entries.size());

    SerializedStateMap nextValues;
    nextValues.reserve(entries.size());

    std::lock_guard<std::mutex> lock(stateChangeCacheMutex_);
    for (const auto& entry : entries) {
        const auto& path = entry.first;
        const auto& value = entry.second;
        const auto it = lastSerializedStateValues_.find(path);
        if (it == lastSerializedStateValues_.end() || it->second != value) {
            changedPaths.push_back(path);
        }
        nextValues.emplace(path, value);
    }

    lastSerializedStateValues_ = std::move(nextValues);
    return changedPaths;
}

void BehaviorCoreProcessor::updateChangeCache() {
    auto nextValues = buildSerializedStateMap(*this);
    std::lock_guard<std::mutex> lock(stateChangeCacheMutex_);
    lastSerializedStateValues_ = std::move(nextValues);
}

void BehaviorCoreProcessor::subscribeToPath(const std::string& path, StateChangeCallback callback) {
    // TODO: Implement subscription management
    (void)path;
    (void)callback;
}

void BehaviorCoreProcessor::unsubscribeFromPath(const std::string& path) {
    // TODO: Implement unsubscription
    (void)path;
}

void BehaviorCoreProcessor::clearSubscriptions() {
    // TODO: Implement subscription clearing
}

void BehaviorCoreProcessor::processPendingChanges() {
    // TODO: Implement pending change processing
}

void BehaviorCoreProcessor::getStateInformation(juce::MemoryBlock& destData) {
    juce::DynamicObject::Ptr root = new juce::DynamicObject();

    if (exportPluginConfig_.enabled) {
        juce::DynamicObject::Ptr pluginUi = new juce::DynamicObject();
        pluginUi->setProperty("viewMode", exportViewMode_.load(std::memory_order_relaxed));
        pluginUi->setProperty("editorWidth", exportEditorWidth_.load(std::memory_order_relaxed));
        pluginUi->setProperty("editorHeight", exportEditorHeight_.load(std::memory_order_relaxed));
        pluginUi->setProperty("devVisible", exportDevVisible_.load(std::memory_order_relaxed));
        root->setProperty("pluginUi", juce::var(pluginUi.get()));
    }

    if (hostParams_) {
        auto state = hostParams_->copyState();
        if (auto xml = std::unique_ptr<juce::XmlElement>(state.createXml())) {
            root->setProperty("hostParamsXml", xml->toString());
        }
    }

    destData.reset();
    juce::MemoryOutputStream out(destData, false);
    out.writeString(juce::JSON::toString(juce::var(root.get())));
}

void BehaviorCoreProcessor::setStateInformation(const void* data, int sizeInBytes) {
    if (data == nullptr || sizeInBytes <= 0) {
        return;
    }

    const juce::String jsonText = juce::String::fromUTF8(static_cast<const char*>(data), sizeInBytes);
    const auto json = juce::JSON::parse(jsonText);
    if (!json.isObject()) {
        return;
    }

    auto* obj = json.getDynamicObject();
    if (obj == nullptr) {
        return;
    }

    if (obj->hasProperty("pluginUi") && exportPluginConfig_.enabled) {
        auto pluginUiVar = obj->getProperty("pluginUi");
        auto* pluginUi = pluginUiVar.getDynamicObject();
        if (pluginUi != nullptr) {
            exportViewMode_.store(readIntProperty(pluginUi, "viewMode", exportPluginConfig_.defaultViewMode) == 0 ? 0 : 1,
                                  std::memory_order_relaxed);
            exportEditorWidth_.store(std::max(1, readIntProperty(pluginUi, "editorWidth", exportEditorWidth_.load(std::memory_order_relaxed))),
                                     std::memory_order_relaxed);
            exportEditorHeight_.store(std::max(1, readIntProperty(pluginUi, "editorHeight", exportEditorHeight_.load(std::memory_order_relaxed))),
                                      std::memory_order_relaxed);
            exportSettingsVisible_.store(false, std::memory_order_relaxed);
            exportDevVisible_.store(readBoolProperty(pluginUi, "devVisible", exportDevVisible_.load(std::memory_order_relaxed)),
                                    std::memory_order_relaxed);
            exportOscEnabled_.store(exportPluginConfig_.oscDefaultEnabled, std::memory_order_relaxed);
            exportOscQueryEnabled_.store(exportPluginConfig_.oscQueryDefaultEnabled, std::memory_order_relaxed);
            exportOscInputPort_.store(exportPluginConfig_.oscBasePort, std::memory_order_relaxed);
            exportOscQueryPort_.store(exportPluginConfig_.oscBasePort + 1, std::memory_order_relaxed);
            applyExportOscSettings();
        }
    }

    if (obj->hasProperty("hostParamsXml") && hostParams_) {
        const auto xmlText = obj->getProperty("hostParamsXml").toString();
        if (xmlText.isNotEmpty()) {
            if (auto xml = juce::parseXML(xmlText)) {
                if (xml->hasTagName(hostParams_->state.getType())) {
                    suppressHostParameterCallbacks_.store(true, std::memory_order_relaxed);
                    hostParams_->replaceState(juce::ValueTree::fromXml(*xml));
                    suppressHostParameterCallbacks_.store(false, std::memory_order_relaxed);
                    applyHostParameterSnapshotToProcessor();
                }
            }
        }
    }
}

// ============================================================================
// MIDI Implementation
// ============================================================================

std::vector<std::string> BehaviorCoreProcessor::getMidiInputDevices() {
    std::vector<std::string> devices;
    auto deviceInfos = juce::MidiInput::getAvailableDevices();
    for (const auto& info : deviceInfos) {
        devices.push_back(info.name.toStdString());
    }
    return devices;
}

std::vector<std::string> BehaviorCoreProcessor::getMidiOutputDevices() {
    std::vector<std::string> devices;
    auto deviceInfos = juce::MidiOutput::getAvailableDevices();
    for (const auto& info : deviceInfos) {
        devices.push_back(info.name.toStdString());
    }
    return devices;
}

bool BehaviorCoreProcessor::openMidiInput(int deviceIndex) {
    auto deviceInfos = juce::MidiInput::getAvailableDevices();
    if (deviceIndex < 0 || deviceIndex >= deviceInfos.size()) {
        return false;
    }
    
    // Close existing if open
    if (midiInputDevice != nullptr) {
        midiInputDevice->stop();
        midiInputDevice.reset();
    }
    
    // Open new device
    auto device = juce::MidiInput::openDevice(deviceInfos[deviceIndex].identifier, this);
    if (device != nullptr) {
        midiInputDevice = std::move(device);
        midiInputDevice->start();
        return true;
    }
    return false;
}

bool BehaviorCoreProcessor::openMidiOutput(int deviceIndex) {
    auto deviceInfos = juce::MidiOutput::getAvailableDevices();
    if (deviceIndex < 0 || deviceIndex >= deviceInfos.size()) {
        return false;
    }
    
    // Close existing if open
    if (midiOutputDevice != nullptr) {
        midiOutputDevice.reset();
    }
    
    // Open new device
    auto device = juce::MidiOutput::openDevice(deviceInfos[deviceIndex].identifier);
    if (device != nullptr) {
        midiOutputDevice = std::move(device);
        return true;
    }
    return false;
}

void BehaviorCoreProcessor::closeMidiInput() {
    if (midiInputDevice != nullptr) {
        midiInputDevice->stop();
        midiInputDevice.reset();
    }
}

void BehaviorCoreProcessor::closeMidiOutput() {
    if (midiOutputDevice != nullptr) {
        midiOutputDevice.reset();
    }
}

void BehaviorCoreProcessor::handleIncomingMidiMessage(juce::MidiInput* /*source*/, 
                                                      const juce::MidiMessage& msg) {
    // Route incoming MIDI from hardware device to the MidiManager via ring buffer
    // The MidiManager will pick this up on the next process call
    if (msg.isNoteOn()) {
        midiInputRing.write(0x90 | (msg.getChannel() & 0x0F),
                           static_cast<uint8_t>(msg.getNoteNumber()),
                           static_cast<uint8_t>(msg.getVelocity()), 0);
    } else if (msg.isNoteOff()) {
        midiInputRing.write(0x80 | (msg.getChannel() & 0x0F),
                           static_cast<uint8_t>(msg.getNoteNumber()),
                           static_cast<uint8_t>(msg.getVelocity()), 0);
    } else if (msg.isController()) {
        midiInputRing.write(0xB0 | (msg.getChannel() & 0x0F),
                           static_cast<uint8_t>(msg.getControllerNumber()),
                           static_cast<uint8_t>(msg.getControllerValue()), 0);
    } else if (msg.isPitchWheel()) {
        int value = msg.getPitchWheelValue();
        midiInputRing.write(0xE0 | (msg.getChannel() & 0x0F),
                           static_cast<uint8_t>(value & 0x7F),
                           static_cast<uint8_t>((value >> 7) & 0x7F), 0);
    } else if (msg.isProgramChange()) {
        midiInputRing.write(0xC0 | (msg.getChannel() & 0x0F),
                           static_cast<uint8_t>(msg.getProgramChangeNumber()), 0, 0);
    }
}

void BehaviorCoreProcessor::sendMidiMessage(uint8_t status, uint8_t data1, uint8_t data2) {
    if (midiOutputDevice != nullptr) {
        midiOutputDevice->sendMessageNow(juce::MidiMessage(status, data1, data2, {}));
    }
}

void BehaviorCoreProcessor::sendMidiNoteOn(int channel, int note, int velocity) {
    if (midiManager_) {
        midiManager_->sendNoteOn(static_cast<uint8_t>(channel - 1), static_cast<uint8_t>(note), static_cast<uint8_t>(velocity));
    }
    sendMidiMessage(MidiStatus::NOTE_ON | ((channel - 1) & 0x0F), note & 0x7F, velocity & 0x7F);
}

void BehaviorCoreProcessor::sendMidiNoteOff(int channel, int note) {
    if (midiManager_) {
        midiManager_->sendNoteOff(static_cast<uint8_t>(channel - 1), static_cast<uint8_t>(note));
    }
    sendMidiMessage(MidiStatus::NOTE_OFF | ((channel - 1) & 0x0F), note & 0x7F, 0);
}

void BehaviorCoreProcessor::sendMidiCC(int channel, int cc, int value) {
    if (midiManager_) {
        midiManager_->sendCC(static_cast<uint8_t>(channel - 1), static_cast<uint8_t>(cc), static_cast<uint8_t>(value));
    }
    sendMidiMessage(MidiStatus::CONTROL_CHANGE | ((channel - 1) & 0x0F), cc & 0x7F, value & 0x7F);
}

void BehaviorCoreProcessor::sendMidiPitchBend(int channel, int value) {
    if (midiManager_) {
        midiManager_->sendPitchBend(static_cast<uint8_t>(channel - 1), static_cast<int16_t>(value));
    }
    sendMidiMessage(MidiStatus::PITCH_BEND | ((channel - 1) & 0x0F), value & 0x7F, (value >> 7) & 0x7F);
}

void BehaviorCoreProcessor::sendMidiProgramChange(int channel, int program) {
    if (midiManager_) {
        midiManager_->sendProgramChange(static_cast<uint8_t>(channel - 1), static_cast<uint8_t>(program));
    }
    sendMidiMessage(MidiStatus::PROGRAM_CHANGE | ((channel - 1) & 0x0F), program & 0x7F, 0);
}

void BehaviorCoreProcessor::processMidiInput(const juce::MidiBuffer& midiMessages,
                                             bool writeLegacyRing) {
    // Process incoming MIDI through the new MidiManager
    if (midiManager_) {
        midiManager_->processIncomingMidi(midiMessages,
            currentSampleRate.load(std::memory_order_relaxed));
    }

    if (!writeLegacyRing) {
        return;
    }
    
    // Keep legacy behavior: write to ring buffer for Lua consumption
    for (const auto metadata : midiMessages) {
        const juce::MidiMessage& msg = metadata.getMessage();
        if (msg.isNoteOn()) {
            midiInputRing.write(MidiStatus::NOTE_ON | msg.getChannel(),
                              msg.getNoteNumber(), msg.getVelocity(), metadata.samplePosition);
        } else if (msg.isNoteOff()) {
            midiInputRing.write(MidiStatus::NOTE_OFF | msg.getChannel(),
                               msg.getNoteNumber(), msg.getVelocity(), metadata.samplePosition);
        } else if (msg.isController()) {
            midiInputRing.write(MidiStatus::CONTROL_CHANGE | msg.getChannel(),
                               msg.getControllerNumber(), msg.getControllerValue(), metadata.samplePosition);
        } else if (msg.isPitchWheel()) {
            midiInputRing.write(MidiStatus::PITCH_BEND | msg.getChannel(),
                               msg.getPitchWheelValue() & 0x7F,
                               (msg.getPitchWheelValue() >> 7) & 0x7F, metadata.samplePosition);
        } else if (msg.isProgramChange()) {
            midiInputRing.write(MidiStatus::PROGRAM_CHANGE | msg.getChannel(),
                               msg.getProgramChangeNumber(), 0, metadata.samplePosition);
        }
    }
}

void BehaviorCoreProcessor::drainMidiOutput(juce::MidiBuffer& outMidi) {
    // Drain MIDI messages from new MidiManager
    if (midiManager_) {
        midiManager_->fillOutgoingMidi(outMidi);
    }
    
    // Also drain legacy output ring
    uint8_t status, data1, data2;
    int32_t timestamp;
    while (midiOutputRing.read(status, data1, data2, timestamp)) {
        outMidi.addEvent(juce::MidiMessage(status, data1, data2), timestamp);
    }
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new BehaviorCoreProcessor();
}

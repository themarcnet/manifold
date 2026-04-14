#include "DSPPluginScriptHost.h"

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include "dsp_host/DSPHostInternal.h"

#include "GraphRuntime.h"
#include "PrimitiveGraph.h"

#include <algorithm>
#include <cstdio>
#include <map>
#include <mutex>

using dsp_host::DspParamSpec;
using dsp_host::LoadSession;
using dsp_host::isRegistryOwnedCategory;
using dsp_host::sanitizePath;

namespace {

bool useMinimalMidiEffectBindings(const juce::File* scriptFile) {
  if (scriptFile == nullptr) {
    return false;
  }

  const auto projectRoot = scriptFile->getParentDirectory().getParentDirectory();
  const auto manifestFile = projectRoot.getChildFile("manifold.project.json5");
  if (!manifestFile.existsAsFile()) {
    return false;
  }

  const auto json = juce::JSON::parse(manifestFile);
  if (!json.isObject()) {
    return false;
  }

  auto* root = json.getDynamicObject();
  if (root == nullptr || !root->hasProperty("plugin")) {
    return false;
  }

  auto pluginVar = root->getProperty("plugin");
  if (!pluginVar.isObject()) {
    return false;
  }

  auto* plugin = pluginVar.getDynamicObject();
  if (plugin == nullptr) {
    return false;
  }

  if (plugin->hasProperty("midiEffect") && static_cast<bool>(plugin->getProperty("midiEffect"))) {
    return true;
  }

  if (plugin->hasProperty("runtimeFamily")) {
    return plugin->getProperty("runtimeFamily").toString().trim().toLowerCase() == "midi_effect";
  }

  return false;
}

} // namespace

bool DSPPluginScriptHost::loadScriptImpl(const std::string &sourceName,
                                         const juce::File *scriptFile,
                                         const std::string *scriptCode) {
  auto *impl = pImpl.get();
  stopDeferredWorker();
  if (!impl->processor) {
    impl->lastError = "DSP host not initialised";
    return false;
  }

  auto graph = impl->processor->getPrimitiveGraph();
  if (!graph) {
    impl->lastError = "processor has no primitive graph";
    return false;
  }

  // Remove nodes previously owned by this script slot before loading replacement.
  for (auto &node : impl->ownedNodes) {
    graph->unregisterNode(node);
  }
  impl->ownedNodes.clear();

  // Retire old Lua state BEFORE creating new one, but DON'T destroy it yet.
  // Destroying Lua states with active shared_ptr references causes crashes.
  if (impl->lua.lua_state() != nullptr) {
    impl->retiredLuaStates.push_back(std::move(impl->lua));
  }
  // Limit retired states but destroy them safely
  while (impl->retiredLuaStates.size() > 4) {
    sol::state& oldState = impl->retiredLuaStates.front();
    if (oldState.lua_state() != nullptr) {
      lua_gc(oldState.lua_state(), LUA_GCCOLLECT, 0);
    }
    impl->retiredLuaStates.erase(impl->retiredLuaStates.begin());
  }

  LoadSession session;
  dsp_host::initialiseLoadSession(session);

  auto &newLua = session.lua;
  lua_State *newLuaState = session.luaState;
  auto &newParamSpecs = session.paramSpecs;
  auto &newParamValues = session.paramValues;
  auto &newParamBindings = session.paramBindings;
  auto &newExternalToInternalPath = session.externalToInternalPath;
  auto &newInternalToExternalPath = session.internalToExternalPath;
  auto &newLayerPlaybackNodes = session.layerPlaybackNodes;
  auto &newLayerGateNodes = session.layerGateNodes;
  auto &newLayerOutputNodes = session.layerOutputNodes;
  auto &newNamedNodes = session.namedNodes;
  auto newOwnedNodes = session.ownedNodes;
  auto &newOnParamChange = session.onParamChange;
  auto &newProcess = session.process;
  auto &pluginTable = session.pluginTable;

  auto mapInternalToExternal = [impl](const std::string &rawPath) {
    juce::String internal = sanitizePath(rawPath);

    if (impl->namespaceBase == "/core/behavior") {
      return internal.toStdString();
    }

    juce::String base(impl->namespaceBase);
    if (internal == "/core/behavior") {
      return base.toStdString();
    }
    if (internal.startsWith("/core/behavior/")) {
      return (base + internal.substring(14)).toStdString();
    }

    return internal.toStdString();
  };

  auto mapExternalToInternal = [impl](const std::string &rawPath) {
    juce::String external = sanitizePath(rawPath);
    juce::String base(impl->namespaceBase);

    if (impl->namespaceBase != "/core/behavior") {
      if (external == base) {
        return std::string("/core/behavior");
      }
      if (external.startsWith(base + "/")) {
        return (juce::String("/core/behavior") + external.substring(base.length())).toStdString();
      }
    }

    return external.toStdString();
  };

  auto trackNode = [graph, newOwnedNodes](std::shared_ptr<dsp_primitives::IPrimitiveNode> node) {
    graph->registerNode(node);
    newOwnedNodes->push_back(node);
  };

  dsp_host::TrackNodeFn trackNodeFn = trackNode;
  dsp_host::PathMapperFn mapInternalToExternalFn = mapInternalToExternal;
  dsp_host::PathMapperFn mapExternalToInternalFn = mapExternalToInternal;
  dsp_host::PrimitiveNodeResolverFn toPrimitiveNodeFn = dsp_host::toPrimitiveNode;

  auto ctx = sol::state_view(newLuaState).create_table();
  const bool minimalMidiEffectBindings = useMinimalMidiEffectBindings(scriptFile);
  if (!minimalMidiEffectBindings) {
    dsp_host::registerCoreBindings(session, graph, ctx, trackNodeFn,
                                   mapInternalToExternalFn);
    dsp_host::registerSynthBindings(session, graph, ctx, trackNodeFn);
    dsp_host::registerFxBindings(session, graph, ctx, trackNodeFn);
    dsp_host::registerLoopLayerBundle(session, graph, ctx, trackNodeFn,
                                      mapInternalToExternalFn);
  }
  dsp_host::registerParamsApi(session, ctx, mapInternalToExternalFn,
                              mapExternalToInternalFn);

  if (minimalMidiEffectBindings) {
    dsp_host::registerMidiApi(session, impl->processor, ctx, true);
  } else {
    dsp_host::registerHostApiAndGlobals(session, impl->processor, graph, ctx,
                                        mapInternalToExternalFn,
                                        toPrimitiveNodeFn);
  }

  if (!dsp_host::configureModuleLoading(session, scriptFile, ctx,
                                        impl->lastError)) {
    return false;
  }

  if (!dsp_host::executeBuildPlugin(session, scriptFile, scriptCode, ctx,
                                    impl->lastError)) {
    return false;
  }

  const double sampleRate =
      impl->processor->getSampleRate() > 0.0 ? impl->processor->getSampleRate()
                                             : 44100.0;
  const int blockSize = std::max(1, impl->processor->getGraphBlockSize());
  const int numChannels = std::max(1, impl->processor->getGraphOutputChannels());

  std::unique_ptr<dsp_primitives::GraphRuntime> runtime;
  if (!minimalMidiEffectBindings) {
    runtime = graph->compileRuntime(sampleRate, blockSize, numChannels);
    if (!runtime) {
      impl->lastError = "failed to compile runtime from buildPlugin graph";
      return false;
    }
  }

  {
    auto topo = graph->getTopologicalOrder();
    std::fprintf(stderr,
                 "DSPPluginScriptHost: compile summary source=%s nodes=%zu connections=%zu\n",
                 sourceName.c_str(),
                 graph->getNodeCount(),
                 graph->getConnectionCount());
    for (size_t i = 0; i < topo.size(); ++i) {
      std::fprintf(stderr, "DSPPluginScriptHost:   node[%zu]=%s\n",
                   i, topo[i] ? topo[i]->getNodeType() : "(null)");
    }
  }

  if (runtime) {
    impl->processor->requestGraphRuntimeSwap(std::move(runtime));
  }

  std::map<std::string, DspParamSpec> orderedSpecs(newParamSpecs.begin(),
                                                   newParamSpecs.end());
  dsp_host::syncEndpoints(session, impl->processor, impl->registeredEndpoints,
                          orderedSpecs);

  {
    const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);

    impl->onParamChange = std::move(newOnParamChange);
    impl->process = std::move(newProcess);
    impl->pluginTable = std::move(pluginTable);
    impl->lua = std::move(newLua);
    impl->paramSpecs = std::move(newParamSpecs);
    impl->paramValues = std::move(newParamValues);
    impl->paramBindings = std::move(newParamBindings);
    impl->externalToInternalPath = std::move(newExternalToInternalPath);
    impl->internalToExternalPath = std::move(newInternalToExternalPath);
    impl->layerPlaybackNodes = std::move(newLayerPlaybackNodes);
    impl->layerGateNodes = std::move(newLayerGateNodes);
    impl->layerOutputNodes = std::move(newLayerOutputNodes);
    impl->namedNodes = std::move(newNamedNodes);
    impl->ownedNodes = std::move(*newOwnedNodes);
    impl->currentScriptFile = scriptFile != nullptr ? *scriptFile : juce::File();
    impl->currentScriptSourceName = sourceName;
    impl->currentScriptCode = scriptCode != nullptr ? *scriptCode : std::string();
    impl->currentScriptIsInMemory = (scriptCode != nullptr);
    impl->loaded = true;
    impl->lastError.clear();
  }

  std::fprintf(stderr, "DSPPluginScriptHost: loaded script source: %s\n",
               sourceName.c_str());
  return true;
}

bool DSPPluginScriptHost::loadScript(const juce::File &scriptFile) {
  if (!scriptFile.existsAsFile()) {
    pImpl->lastError =
        "DSP script file not found: " + scriptFile.getFullPathName().toStdString();
    return false;
  }

  return loadScriptImpl(scriptFile.getFullPathName().toStdString(), &scriptFile,
                        nullptr);
}

bool DSPPluginScriptHost::loadScriptFromString(const std::string &luaCode,
                                               const std::string &sourceName) {
  if (luaCode.empty()) {
    pImpl->lastError = "DSP script source is empty";
    return false;
  }

  return loadScriptImpl(sourceName.empty() ? std::string("in_memory") : sourceName,
                        nullptr, &luaCode);
}

bool DSPPluginScriptHost::reloadCurrentScript() {
  if (pImpl->currentScriptIsInMemory) {
    if (pImpl->currentScriptCode.empty()) {
      pImpl->lastError = "no current DSP script to reload";
      return false;
    }
    return loadScriptFromString(pImpl->currentScriptCode,
                                pImpl->currentScriptSourceName);
  }

  if (!pImpl->currentScriptFile.existsAsFile()) {
    pImpl->lastError = "no current DSP script to reload";
    return false;
  }
  return loadScript(pImpl->currentScriptFile);
}

bool DSPPluginScriptHost::isLoaded() const { return pImpl->loaded; }

void DSPPluginScriptHost::markUnloaded() {
  pImpl->loaded = false;
  pImpl->currentScriptFile = juce::File();
  pImpl->currentScriptSourceName.clear();
  pImpl->currentScriptCode.clear();
  pImpl->currentScriptIsInMemory = false;
}

const std::string &DSPPluginScriptHost::getLastError() const {
  return pImpl->lastError;
}

juce::File DSPPluginScriptHost::getCurrentScriptFile() const {
  return pImpl->currentScriptFile;
}

void DSPPluginScriptHost::process(int blockSize, double sampleRate) {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (!pImpl->process.valid()) {
    return;
  }
  sol::protected_function_result result = pImpl->process(blockSize, sampleRate);
  if (!result.valid()) {
    sol::error err = result;
    pImpl->lastError = "process failed: " + std::string(err.what());
  }
}

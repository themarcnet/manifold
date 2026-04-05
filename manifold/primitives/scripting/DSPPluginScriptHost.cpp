#include "DSPPluginScriptHost.h"

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include "dsp_host/DSPHostInternal.h"

#include "GraphRuntime.h"
#include "PrimitiveGraph.h"
#include "../control/OSCQuery.h"
#include "../control/OSCServer.h"
#include "../control/OSCEndpointRegistry.h"

#include <algorithm>
#include <cstdio>
#include <map>
#include <mutex>

using dsp_host::DspParamSpec;
using dsp_host::LoadSession;
using dsp_host::isRegistryOwnedCategory;
using dsp_host::sanitizePath;

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
    // Collect the oldest state with explicit GC to ensure proper cleanup order
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
  dsp_host::registerCoreBindings(session, graph, ctx, trackNodeFn,
                                 mapInternalToExternalFn);
  dsp_host::registerSynthBindings(session, graph, ctx, trackNodeFn);
  dsp_host::registerFxBindings(session, graph, ctx, trackNodeFn);
  dsp_host::registerParamsApi(session, ctx, mapInternalToExternalFn,
                              mapExternalToInternalFn);
  dsp_host::registerLoopLayerBundle(session, graph, ctx, trackNodeFn,
                                    mapInternalToExternalFn);

  dsp_host::registerHostApiAndGlobals(session, impl->processor, graph, ctx,
                                      mapInternalToExternalFn,
                                      toPrimitiveNodeFn);

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

  auto runtime = graph->compileRuntime(sampleRate, blockSize, numChannels);
  if (!runtime) {
    impl->lastError = "failed to compile runtime from buildPlugin graph";
    return false;
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

  impl->processor->requestGraphRuntimeSwap(std::move(runtime));

  for (const auto &path : impl->registeredEndpoints) {
    impl->processor->getEndpointRegistry().unregisterCustomEndpoint(path);
    impl->processor->getOSCServer().removeCustomValue(path);
  }
  impl->registeredEndpoints.clear();

  std::map<std::string, DspParamSpec> orderedSpecs(newParamSpecs.begin(),
                                                   newParamSpecs.end());
  for (const auto &entry : orderedSpecs) {
    const auto &path = entry.first;
    const auto &spec = entry.second;

    OSCEndpoint endpoint;
    endpoint.path = juce::String(path);
    endpoint.type = spec.typeTag;
    endpoint.rangeMin = spec.rangeMin;
    endpoint.rangeMax = spec.rangeMax;
    endpoint.access = spec.access;
    endpoint.description = spec.description;
    endpoint.category = "dsp";
    endpoint.commandType = ControlCommand::Type::None;
    endpoint.layerIndex = -1;

    const OSCEndpoint existingEndpoint =
        impl->processor->getEndpointRegistry().findEndpoint(endpoint.path);
    const bool backendOwned = existingEndpoint.path.isNotEmpty() &&
                              isRegistryOwnedCategory(existingEndpoint.category);

    // Register script parameters as custom OSCQuery endpoints unless a backend
    // endpoint already owns this exact path. This lets behavior scripts expose
    // newly added parameters (e.g. forwardBars/forwardArmed) without having to
    // wait for static template updates.
    if (!backendOwned) {
      impl->processor->getEndpointRegistry().registerCustomEndpoint(endpoint);
      impl->registeredEndpoints.push_back(endpoint.path);

      const auto valIt = newParamValues.find(path);
      if (valIt != newParamValues.end()) {
        impl->processor->getOSCServer().setCustomValue(endpoint.path,
                                                       {juce::var(valIt->second)});
      }
    }
  }

  impl->processor->getOSCQueryServer().rebuildTree();

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


#include "DSPHostInternal.h"

#include "../GraphRuntime.h"
#include "../PrimitiveGraph.h"

#include <algorithm>

using dsp_host::sanitizePath;

DSPPluginScriptHost::DSPPluginScriptHost() : pImpl(std::make_unique<Impl>()) {}

bool DSPPluginScriptHost::compileRuntimeAndRequestSwap(const std::string &reason) {
  auto *impl = pImpl.get();
  if (!impl || !impl->processor) {
    return false;
  }

  auto graph = impl->processor->getPrimitiveGraph();
  if (!graph) {
    const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
    impl->lastError = reason + ": missing primitive graph";
    return false;
  }

  const double sampleRate =
      impl->processor->getSampleRate() > 0.0 ? impl->processor->getSampleRate()
                                             : 44100.0;
  const int blockSize = std::max(1, impl->processor->getGraphBlockSize());
  const int numChannels = std::max(1, impl->processor->getGraphOutputChannels());

  auto runtime = graph->compileRuntime(sampleRate, blockSize, numChannels);
  if (!runtime) {
    const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
    impl->lastError = reason + ": failed to compile runtime";
    return false;
  }

  impl->processor->requestGraphRuntimeSwap(std::move(runtime));
  return true;
}

bool DSPPluginScriptHost::applyDeferredGraphMutation(const std::string &path,
                                                     float normalized) {
  auto *impl = pImpl.get();
  if (!impl) {
    return false;
  }

  if (impl->processor) {
    impl->processor->beginGraphMutation();
  }

  bool ok = true;
  {
    const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
    const auto specIt = impl->paramSpecs.find(path);
    if (specIt == impl->paramSpecs.end()) {
      ok = false;
    } else {
      const auto bindIt = impl->paramBindings.find(path);
      if (bindIt != impl->paramBindings.end()) {
        bindIt->second(normalized);
      }

      if (ok && impl->onParamChange.valid()) {
        std::string internalPath = path;
        const auto mapIt = impl->externalToInternalPath.find(path);
        if (mapIt != impl->externalToInternalPath.end()) {
          internalPath = mapIt->second;
        }

        sol::protected_function_result result =
            impl->onParamChange(internalPath, normalized);
        if (!result.valid()) {
          sol::error err = result;
          impl->lastError =
              "deferred onParamChange failed: " + std::string(err.what());
          ok = false;
        }
      }
    }
  }

  if (ok) {
    ok = compileRuntimeAndRequestSwap("deferred graph mutation");
  }

  if (impl->processor) {
    impl->processor->endGraphMutation();
  }
  return ok;
}

void DSPPluginScriptHost::ensureDeferredWorkerStarted() {
  auto *impl = pImpl.get();
  if (!impl) {
    return;
  }

  std::lock_guard<std::mutex> lock(impl->deferredMutex);
  if (impl->deferredWorkerRunning) {
    return;
  }

  impl->deferredWorkerStop = false;
  impl->deferredWorkerRunning = true;
  impl->deferredWorker = std::thread([this, impl]() {
    for (;;) {
      Impl::DeferredParamMutation mutation;
      {
        std::unique_lock<std::mutex> lock(impl->deferredMutex);
        impl->deferredCv.wait(lock, [impl]() {
          return impl->deferredWorkerStop || !impl->deferredMutations.empty();
        });

        if (impl->deferredWorkerStop && impl->deferredMutations.empty()) {
          break;
        }

        mutation = impl->deferredMutations.front();
        impl->deferredMutations.pop_front();
      }

      (void)applyDeferredGraphMutation(mutation.path, mutation.value);
    }
  });
}

bool DSPPluginScriptHost::enqueueDeferredGraphMutation(const std::string &path,
                                                       float normalized) {
  auto *impl = pImpl.get();
  if (!impl) {
    return false;
  }

  ensureDeferredWorkerStarted();
  {
    std::lock_guard<std::mutex> lock(impl->deferredMutex);
    impl->deferredMutations.push_back({path, normalized});
  }
  impl->deferredCv.notify_one();
  return true;
}

void DSPPluginScriptHost::stopDeferredWorker() {
  auto *impl = pImpl.get();
  if (!impl) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(impl->deferredMutex);
    impl->deferredWorkerStop = true;
    impl->deferredMutations.clear();
  }
  impl->deferredCv.notify_all();

  if (impl->deferredWorker.joinable()) {
    impl->deferredWorker.join();
  }

  {
    std::lock_guard<std::mutex> lock(impl->deferredMutex);
    impl->deferredWorkerRunning = false;
    impl->deferredWorkerStop = false;
  }
}

DSPPluginScriptHost::~DSPPluginScriptHost() {
  stopDeferredWorker();
  if (pImpl->processor) {
    if (auto graph = pImpl->processor->getPrimitiveGraph()) {
      for (auto &node : pImpl->ownedNodes) {
        graph->unregisterNode(node);
      }
    }
  }
  pImpl->ownedNodes.clear();
  pImpl->retiredLuaStates.clear();
}

void DSPPluginScriptHost::initialise(ScriptableProcessor *processor,
                                     const std::string &namespaceBase) {
  pImpl->processor = processor;
  if (!namespaceBase.empty()) {
    pImpl->namespaceBase = sanitizePath(namespaceBase).toStdString();
  }
}

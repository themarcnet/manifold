#include "DSPPluginScriptHost.h"

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "GraphRuntime.h"
#include "PrimitiveGraph.h"
#include "../../engine/LooperProcessor.h"
#include "../control/OSCEndpointRegistry.h"

#include <map>
#include <mutex>
#include <functional>
#include <unordered_map>
#include <vector>

namespace {

struct DspParamSpec {
  juce::String typeTag{"f"};
  float rangeMin = 0.0f;
  float rangeMax = 1.0f;
  float defaultValue = 0.0f;
  int access = 3;
  juce::String description;
};

float clampParamValue(const DspParamSpec &spec, float value) {
  if (spec.rangeMax > spec.rangeMin) {
    return juce::jlimit(spec.rangeMin, spec.rangeMax, value);
  }
  return value;
}

juce::String sanitizePath(const std::string &path) {
  juce::String p(path);
  if (!p.startsWithChar('/')) {
    p = "/" + p;
  }
  return p;
}

template <typename NodeT>
std::shared_ptr<NodeT> tableNode(const sol::table &self) {
  sol::object obj = self["__node"];
  if (!obj.valid() || !obj.is<std::shared_ptr<NodeT>>()) {
    return nullptr;
  }
  return obj.as<std::shared_ptr<NodeT>>();
}

} // namespace

struct DSPPluginScriptHost::Impl {
  LooperProcessor *processor = nullptr;

  mutable std::recursive_mutex luaMutex;
  sol::state lua;
  sol::function onParamChange;

  std::unordered_map<std::string, DspParamSpec> paramSpecs;
  std::unordered_map<std::string, float> paramValues;
  std::unordered_map<std::string, std::function<void(float)>> paramBindings;
  std::vector<juce::String> registeredEndpoints;

  bool loaded = false;
  std::string lastError;
  juce::File currentScriptFile;
  std::string currentScriptSourceName;
  std::string currentScriptCode;
  bool currentScriptIsInMemory = false;
};

DSPPluginScriptHost::DSPPluginScriptHost() : pImpl(std::make_unique<Impl>()) {}

DSPPluginScriptHost::~DSPPluginScriptHost() = default;

void DSPPluginScriptHost::initialise(LooperProcessor *processor) {
  pImpl->processor = processor;
}

bool DSPPluginScriptHost::loadScriptImpl(const std::string &sourceName,
                                         const juce::File *scriptFile,
                                         const std::string *scriptCode) {
  auto *impl = pImpl.get();
  if (!impl->processor) {
    impl->lastError = "DSP host not initialised";
    return false;
  }

  auto graph = std::make_shared<dsp_primitives::PrimitiveGraph>();

  sol::state newLua;
  newLua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                        sol::lib::table, sol::lib::package);

  std::unordered_map<std::string, DspParamSpec> newParamSpecs;
  std::unordered_map<std::string, float> newParamValues;
  std::unordered_map<std::string, std::function<void(float)>> newParamBindings;
  sol::function newOnParamChange;

  newLua.new_usertype<dsp_primitives::PlayheadNode>(
      "PlayheadNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PlayheadNode>()>(),
      "setLoopLength", &dsp_primitives::PlayheadNode::setLoopLength,
      "setSpeed", &dsp_primitives::PlayheadNode::setSpeed, "setReversed",
      &dsp_primitives::PlayheadNode::setReversed, "play",
      &dsp_primitives::PlayheadNode::play, "pause",
      &dsp_primitives::PlayheadNode::pause, "stop",
      &dsp_primitives::PlayheadNode::stop, "getLoopLength",
      &dsp_primitives::PlayheadNode::getLoopLength, "getSpeed",
      &dsp_primitives::PlayheadNode::getSpeed, "isReversed",
      &dsp_primitives::PlayheadNode::isReversed, "isPlaying",
      &dsp_primitives::PlayheadNode::isPlaying, "getNormalizedPosition",
      &dsp_primitives::PlayheadNode::getNormalizedPosition);

  newLua.new_usertype<dsp_primitives::PassthroughNode>(
      "PassthroughNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PassthroughNode>(int)>());

  newLua.new_usertype<dsp_primitives::OscillatorNode>(
      "OscillatorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::OscillatorNode>()>(),
      "setFrequency", &dsp_primitives::OscillatorNode::setFrequency,
      "setAmplitude", &dsp_primitives::OscillatorNode::setAmplitude,
      "setEnabled", &dsp_primitives::OscillatorNode::setEnabled,
      "setWaveform", &dsp_primitives::OscillatorNode::setWaveform,
      "getFrequency", &dsp_primitives::OscillatorNode::getFrequency,
      "getAmplitude", &dsp_primitives::OscillatorNode::getAmplitude,
      "isEnabled", &dsp_primitives::OscillatorNode::isEnabled,
      "getWaveform", &dsp_primitives::OscillatorNode::getWaveform);

  newLua.new_usertype<dsp_primitives::ReverbNode>(
      "ReverbNode",
      sol::constructors<std::shared_ptr<dsp_primitives::ReverbNode>()>(),
      "setRoomSize", &dsp_primitives::ReverbNode::setRoomSize, "setDamping",
      &dsp_primitives::ReverbNode::setDamping, "setWetLevel",
      &dsp_primitives::ReverbNode::setWetLevel, "setDryLevel",
      &dsp_primitives::ReverbNode::setDryLevel, "setWidth",
      &dsp_primitives::ReverbNode::setWidth, "getRoomSize",
      &dsp_primitives::ReverbNode::getRoomSize, "getDamping",
      &dsp_primitives::ReverbNode::getDamping, "getWetLevel",
      &dsp_primitives::ReverbNode::getWetLevel, "getDryLevel",
      &dsp_primitives::ReverbNode::getDryLevel, "getWidth",
      &dsp_primitives::ReverbNode::getWidth);

  newLua.new_usertype<dsp_primitives::FilterNode>(
      "FilterNode",
      sol::constructors<std::shared_ptr<dsp_primitives::FilterNode>()>(),
      "setCutoff", &dsp_primitives::FilterNode::setCutoff, "setResonance",
      &dsp_primitives::FilterNode::setResonance, "setMix",
      &dsp_primitives::FilterNode::setMix, "getCutoff",
      &dsp_primitives::FilterNode::getCutoff, "getResonance",
      &dsp_primitives::FilterNode::getResonance, "getMix",
      &dsp_primitives::FilterNode::getMix);

  newLua.new_usertype<dsp_primitives::DistortionNode>(
      "DistortionNode",
      sol::constructors<std::shared_ptr<dsp_primitives::DistortionNode>()>(),
      "setDrive", &dsp_primitives::DistortionNode::setDrive, "setMix",
      &dsp_primitives::DistortionNode::setMix, "setOutput",
      &dsp_primitives::DistortionNode::setOutput, "getDrive",
      &dsp_primitives::DistortionNode::getDrive, "getMix",
      &dsp_primitives::DistortionNode::getMix, "getOutput",
      &dsp_primitives::DistortionNode::getOutput);

  auto toPrimitiveNode = [](const sol::object &obj)
      -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
    if (obj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
    }
    if (obj.is<sol::table>()) {
      sol::table table = obj.as<sol::table>();
      sol::object nodeObj = table["__node"];
      if (nodeObj.valid()) {
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
        }
      }
    }
    return nullptr;
  };

  auto primitives = newLua.create_table();
  {
    auto playheadApi = newLua.create_table();
    playheadApi["new"] = [graph, &newLua]() {
        auto node = std::make_shared<dsp_primitives::PlayheadNode>();
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setLoopLength"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->setLoopLength(v);
          }
        };
        t["setSpeed"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->setSpeed(v);
          }
        };
        t["setReversed"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->setReversed(v);
          }
        };
        t["play"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->play();
          }
        };
        t["pause"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->pause();
          }
        };
        t["stop"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            n->stop();
          }
        };
        t["getLoopLength"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            return n->getLoopLength();
          }
          return 0;
        };
        t["getSpeed"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            return n->getSpeed();
          }
          return 0.0f;
        };
        t["isReversed"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            return n->isReversed();
          }
          return false;
        };
        t["isPlaying"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            return n->isPlaying();
          }
          return false;
        };
        t["getNormalizedPosition"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlayheadNode>(self)) {
            return n->getNormalizedPosition();
          }
          return 0.0f;
        };
        return t;
      };
    primitives["PlayheadNode"] = playheadApi;
  }
  {
    auto passthroughApi = newLua.create_table();
    passthroughApi["new"] = [graph, &newLua](int numChannels) {
        auto node = std::make_shared<dsp_primitives::PassthroughNode>(numChannels);
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        return t;
      };
    primitives["PassthroughNode"] = passthroughApi;
  }
  {
    auto oscApi = newLua.create_table();
    oscApi["new"] = [graph, &newLua]() {
        auto node = std::make_shared<dsp_primitives::OscillatorNode>();
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setFrequency"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setFrequency(v);
          }
        };
        t["setAmplitude"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setAmplitude(v);
          }
        };
        t["setEnabled"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setEnabled(v);
          }
        };
        t["setWaveform"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setWaveform(v);
          }
        };
        return t;
      };
    primitives["OscillatorNode"] = oscApi;
  }
  {
    auto reverbApi = newLua.create_table();
    reverbApi["new"] = [graph, &newLua]() {
        auto node = std::make_shared<dsp_primitives::ReverbNode>();
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setRoomSize"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ReverbNode>(self)) {
            n->setRoomSize(v);
          }
        };
        t["setDamping"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ReverbNode>(self)) {
            n->setDamping(v);
          }
        };
        t["setWetLevel"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ReverbNode>(self)) {
            n->setWetLevel(v);
          }
        };
        t["setDryLevel"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ReverbNode>(self)) {
            n->setDryLevel(v);
          }
        };
        t["setWidth"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ReverbNode>(self)) {
            n->setWidth(v);
          }
        };
        return t;
      };
    primitives["ReverbNode"] = reverbApi;
  }
  {
    auto filterApi = newLua.create_table();
    filterApi["new"] = [graph, &newLua]() {
        auto node = std::make_shared<dsp_primitives::FilterNode>();
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setCutoff"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::FilterNode>(self)) {
            n->setCutoff(v);
          }
        };
        t["setResonance"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::FilterNode>(self)) {
            n->setResonance(v);
          }
        };
        t["setMix"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::FilterNode>(self)) {
            n->setMix(v);
          }
        };
        return t;
      };
    primitives["FilterNode"] = filterApi;
  }
  {
    auto distApi = newLua.create_table();
    distApi["new"] = [graph, &newLua]() {
        auto node = std::make_shared<dsp_primitives::DistortionNode>();
        graph->registerNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setDrive"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::DistortionNode>(self)) {
            n->setDrive(v);
          }
        };
        t["setMix"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::DistortionNode>(self)) {
            n->setMix(v);
          }
        };
        t["setOutput"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::DistortionNode>(self)) {
            n->setOutput(v);
          }
        };
        return t;
      };
    primitives["DistortionNode"] = distApi;
  }

  auto graphTable = newLua.create_table();
  graphTable["connect"] = sol::overload(
      [graph, toPrimitiveNode](const sol::object &fromObj,
                               const sol::object &toObj) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        return graph->connect(from, 0, to, 0);
      },
      [graph, toPrimitiveNode](const sol::object &fromObj,
                               const sol::object &toObj, int fromOutput,
                               int toInput) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        return graph->connect(from, fromOutput, to, toInput);
      });
  graphTable["clear"] = [graph]() { graph->clear(); };
  graphTable["hasCycle"] = [graph]() { return graph->hasCycle(); };
  graphTable["nodeCount"] =
      [graph]() { return static_cast<int>(graph->getNodeCount()); };
  graphTable["connectionCount"] =
      [graph]() { return static_cast<int>(graph->getConnectionCount()); };

  auto paramsTable = newLua.create_table();
  paramsTable["register"] =
      [&newParamSpecs, &newParamValues](const std::string &rawPath,
                                        sol::table options) {
        const juce::String path = sanitizePath(rawPath);
        DspParamSpec spec;

        if (options.valid()) {
          if (options["type"].valid()) {
            spec.typeTag = juce::String(options["type"].get<std::string>());
          }
          if (options["min"].valid()) {
            spec.rangeMin = options["min"].get<float>();
          }
          if (options["max"].valid()) {
            spec.rangeMax = options["max"].get<float>();
          }
          if (options["default"].valid()) {
            spec.defaultValue = options["default"].get<float>();
          }
          if (options["access"].valid()) {
            spec.access = options["access"].get<int>();
          }
          if (options["description"].valid()) {
            spec.description =
                juce::String(options["description"].get<std::string>());
          }
        }

        spec.defaultValue = clampParamValue(spec, spec.defaultValue);
        newParamSpecs[path.toStdString()] = spec;
        newParamValues[path.toStdString()] = spec.defaultValue;
      };

  paramsTable["bind"] =
      [&newParamBindings, toPrimitiveNode](const std::string &rawPath,
                                           const sol::object &nodeObj,
                                           const std::string &method) {
        const std::string path = sanitizePath(rawPath).toStdString();
        auto node = toPrimitiveNode(nodeObj);
        if (!node) {
          return false;
        }

        if (auto playhead = std::dynamic_pointer_cast<dsp_primitives::PlayheadNode>(node)) {
          if (method == "setLoopLength") {
            newParamBindings[path] = [playhead](float v) {
              playhead->setLoopLength(static_cast<int>(v));
            };
            return true;
          }
          if (method == "setSpeed") {
            newParamBindings[path] = [playhead](float v) { playhead->setSpeed(v); };
            return true;
          }
          if (method == "setReversed") {
            newParamBindings[path] = [playhead](float v) {
              playhead->setReversed(v > 0.5f);
            };
            return true;
          }
        }

        if (auto osc = std::dynamic_pointer_cast<dsp_primitives::OscillatorNode>(node)) {
          if (method == "setFrequency") {
            newParamBindings[path] = [osc](float v) { osc->setFrequency(v); };
            return true;
          }
          if (method == "setAmplitude") {
            newParamBindings[path] = [osc](float v) { osc->setAmplitude(v); };
            return true;
          }
          if (method == "setEnabled") {
            newParamBindings[path] = [osc](float v) { osc->setEnabled(v > 0.5f); };
            return true;
          }
          if (method == "setWaveform") {
            newParamBindings[path] = [osc](float v) {
              osc->setWaveform(static_cast<int>(v));
            };
            return true;
          }
        }

        if (auto filt = std::dynamic_pointer_cast<dsp_primitives::FilterNode>(node)) {
          if (method == "setCutoff") {
            newParamBindings[path] = [filt](float v) { filt->setCutoff(v); };
            return true;
          }
          if (method == "setResonance") {
            newParamBindings[path] = [filt](float v) { filt->setResonance(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [filt](float v) { filt->setMix(v); };
            return true;
          }
        }

        if (auto dist = std::dynamic_pointer_cast<dsp_primitives::DistortionNode>(node)) {
          if (method == "setDrive") {
            newParamBindings[path] = [dist](float v) { dist->setDrive(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [dist](float v) { dist->setMix(v); };
            return true;
          }
          if (method == "setOutput") {
            newParamBindings[path] = [dist](float v) { dist->setOutput(v); };
            return true;
          }
        }

        if (auto rev = std::dynamic_pointer_cast<dsp_primitives::ReverbNode>(node)) {
          if (method == "setRoomSize") {
            newParamBindings[path] = [rev](float v) { rev->setRoomSize(v); };
            return true;
          }
          if (method == "setDamping") {
            newParamBindings[path] = [rev](float v) { rev->setDamping(v); };
            return true;
          }
          if (method == "setWetLevel") {
            newParamBindings[path] = [rev](float v) { rev->setWetLevel(v); };
            return true;
          }
          if (method == "setDryLevel") {
            newParamBindings[path] = [rev](float v) { rev->setDryLevel(v); };
            return true;
          }
          if (method == "setWidth") {
            newParamBindings[path] = [rev](float v) { rev->setWidth(v); };
            return true;
          }
        }

        return false;
      };

  auto ctx = newLua.create_table();
  ctx["primitives"] = primitives;
  ctx["graph"] = graphTable;
  ctx["params"] = paramsTable;

  newLua["connectNodes"] = [graph, toPrimitiveNode](const sol::object &fromObj,
                                                      const sol::object &toObj) {
    auto from = toPrimitiveNode(fromObj);
    auto to = toPrimitiveNode(toObj);
    if (!from || !to) {
      return false;
    }
    return graph->connect(from, 0, to, 0);
  };

  if (scriptFile != nullptr) {
    const auto scriptDir =
        scriptFile->getParentDirectory().getFullPathName().toStdString();
    newLua["package"]["path"] = scriptDir + "/?.lua;" + scriptDir + "/?/init.lua";
  }

  if (scriptFile == nullptr && scriptCode == nullptr) {
    impl->lastError = "no DSP script source provided";
    return false;
  }

  sol::protected_function_result loadResult = (scriptFile != nullptr)
                                                  ? newLua.script_file(
                                                        scriptFile->getFullPathName()
                                                            .toStdString())
                                                  : newLua.script(*scriptCode);
  if (!loadResult.valid()) {
    sol::error err = loadResult;
    impl->lastError = err.what();
    return false;
  }

  sol::object buildFnObj = newLua["buildPlugin"];
  if (!buildFnObj.valid() || buildFnObj.get_type() != sol::type::function) {
    impl->lastError = "DSP script must define buildPlugin(ctx)";
    return false;
  }

  sol::protected_function buildFn = buildFnObj;
  sol::protected_function_result buildResult = buildFn(ctx);
  if (!buildResult.valid()) {
    sol::error err = buildResult;
    impl->lastError = err.what();
    return false;
  }

  if (!buildResult.get<sol::object>().is<sol::table>()) {
    impl->lastError = "buildPlugin(ctx) must return a table";
    return false;
  }

  sol::table pluginTable = buildResult.get<sol::table>();
  if (pluginTable["onParamChange"].valid() &&
      pluginTable["onParamChange"].get_type() == sol::type::function) {
    newOnParamChange = pluginTable["onParamChange"];
  }

  for (const auto &entry : newParamValues) {
    const auto bindingIt = newParamBindings.find(entry.first);
    if (bindingIt != newParamBindings.end()) {
      bindingIt->second(entry.second);
    }

    if (newOnParamChange.valid()) {
      sol::protected_function_result applyResult =
          newOnParamChange(entry.first, entry.second);
      if (!applyResult.valid()) {
        sol::error err = applyResult;
        impl->lastError = "onParamChange default apply failed: " +
                           std::string(err.what());
        return false;
      }
    }
  }

  const double sampleRate =
      impl->processor->getSampleRate() > 0.0 ? impl->processor->getSampleRate()
                                             : 44100.0;
  const int blockSize =
      std::max(1, impl->processor->getBlockSize() > 0
                      ? impl->processor->getBlockSize()
                      : 512);
  const int numChannels = std::max(1, impl->processor->getTotalNumOutputChannels());

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
    impl->processor->getEndpointRegistry().registerCustomEndpoint(endpoint);
    impl->registeredEndpoints.push_back(endpoint.path);

    const auto valIt = newParamValues.find(path);
    if (valIt != newParamValues.end()) {
      impl->processor->getOSCServer().setCustomValue(endpoint.path,
                                                     {juce::var(valIt->second)});
    }
  }

  impl->processor->getOSCQueryServer().rebuildTree();

  {
    const std::lock_guard<std::recursive_mutex> lock(impl->luaMutex);
    impl->lua = std::move(newLua);
    impl->onParamChange = std::move(newOnParamChange);
    impl->paramSpecs = std::move(newParamSpecs);
    impl->paramValues = std::move(newParamValues);
    impl->paramBindings = std::move(newParamBindings);
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

const std::string &DSPPluginScriptHost::getLastError() const {
  return pImpl->lastError;
}

juce::File DSPPluginScriptHost::getCurrentScriptFile() const {
  return pImpl->currentScriptFile;
}

bool DSPPluginScriptHost::hasParam(const std::string &path) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  return pImpl->paramSpecs.find(path) != pImpl->paramSpecs.end();
}

bool DSPPluginScriptHost::setParam(const std::string &path, float value) {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  const auto specIt = pImpl->paramSpecs.find(path);
  if (specIt == pImpl->paramSpecs.end()) {
    return false;
  }

  const float normalized = clampParamValue(specIt->second, value);
  pImpl->paramValues[path] = normalized;

  const auto bindIt = pImpl->paramBindings.find(path);
  if (bindIt != pImpl->paramBindings.end()) {
    bindIt->second(normalized);
  }

  if (pImpl->onParamChange.valid()) {
    sol::protected_function_result result = pImpl->onParamChange(path, normalized);
    if (!result.valid()) {
      sol::error err = result;
      pImpl->lastError = "onParamChange failed: " + std::string(err.what());
      return false;
    }
  }

  if (pImpl->processor) {
    pImpl->processor->getOSCServer().setCustomValue(juce::String(path),
                                                    {juce::var(normalized)});
  }

  return true;
}

float DSPPluginScriptHost::getParam(const std::string &path) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  const auto it = pImpl->paramValues.find(path);
  if (it == pImpl->paramValues.end()) {
    return 0.0f;
  }
  return it->second;
}

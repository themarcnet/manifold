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
#include "ScriptableProcessor.h"
#include "dsp/core/nodes/PrimitiveNodes.h"
#include "dsp/core/nodes/MidiVoiceNode.h"
#include "dsp/core/nodes/MidiInputNode.h"
#include "../control/OSCQuery.h"
#include "../control/OSCServer.h"
#include "../control/OSCEndpointRegistry.h"
#include "../core/Settings.h"
#include "../../core/BehaviorCoreProcessor.h"

#include <algorithm>
#include <map>
#include <mutex>
#include <cmath>
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

bool isRegistryOwnedCategory(const juce::String &category) {
  return category == "backend" || category == "query";
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
  ScriptableProcessor *processor = nullptr;

  mutable std::recursive_mutex luaMutex;
  sol::state lua;
  sol::function onParamChange;
  sol::function process;
  sol::table pluginTable;

  std::unordered_map<std::string, DspParamSpec> paramSpecs;
  std::unordered_map<std::string, float> paramValues;
  std::unordered_map<std::string, std::function<void(float)>> paramBindings;
  std::unordered_map<std::string, std::string> externalToInternalPath;
  std::unordered_map<std::string, std::string> internalToExternalPath;
  std::vector<juce::String> registeredEndpoints;
  std::vector<std::weak_ptr<dsp_primitives::LoopPlaybackNode>> layerPlaybackNodes;
  std::vector<std::weak_ptr<dsp_primitives::PlaybackStateGateNode>> layerGateNodes;
  std::vector<std::weak_ptr<dsp_primitives::GainNode>> layerOutputNodes;
  std::unordered_map<std::string, std::weak_ptr<dsp_primitives::IPrimitiveNode>>
      namedNodes;
  std::vector<std::shared_ptr<dsp_primitives::IPrimitiveNode>> ownedNodes;

  // Keep old Lua VMs alive to avoid tearing down a VM during nested Lua call stacks.
  std::vector<sol::state> retiredLuaStates;

  std::string namespaceBase{"/core/behavior"};

  bool loaded = false;
  std::string lastError;
  juce::File currentScriptFile;
  std::string currentScriptSourceName;
  std::string currentScriptCode;
  bool currentScriptIsInMemory = false;
};

DSPPluginScriptHost::DSPPluginScriptHost() : pImpl(std::make_unique<Impl>()) {}

DSPPluginScriptHost::~DSPPluginScriptHost() {
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

bool DSPPluginScriptHost::loadScriptImpl(const std::string &sourceName,
                                         const juce::File *scriptFile,
                                         const std::string *scriptCode) {
  auto *impl = pImpl.get();
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

  sol::state newLua;
  newLua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                        sol::lib::table, sol::lib::package);

  std::unordered_map<std::string, DspParamSpec> newParamSpecs;
  std::unordered_map<std::string, float> newParamValues;
  std::unordered_map<std::string, std::function<void(float)>> newParamBindings;
  std::unordered_map<std::string, std::string> newExternalToInternalPath;
  std::unordered_map<std::string, std::string> newInternalToExternalPath;
  std::vector<std::weak_ptr<dsp_primitives::LoopPlaybackNode>> newLayerPlaybackNodes;
  std::vector<std::weak_ptr<dsp_primitives::PlaybackStateGateNode>> newLayerGateNodes;
  std::vector<std::weak_ptr<dsp_primitives::GainNode>> newLayerOutputNodes;
  std::unordered_map<std::string, std::weak_ptr<dsp_primitives::IPrimitiveNode>>
      newNamedNodes;
  auto newOwnedNodes = std::make_shared<std::vector<std::shared_ptr<dsp_primitives::IPrimitiveNode>>>();
  sol::function newOnParamChange;
  sol::function newProcess;

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

  newLua.new_usertype<dsp_primitives::GainNode>(
      "GainNode",
      sol::constructors<std::shared_ptr<dsp_primitives::GainNode>(int)>(),
      "setGain", &dsp_primitives::GainNode::setGain,
      "getGain", &dsp_primitives::GainNode::getGain,
      "setMuted", &dsp_primitives::GainNode::setMuted,
      "isMuted", &dsp_primitives::GainNode::isMuted);

  newLua.new_usertype<dsp_primitives::LoopPlaybackNode>(
      "LoopPlaybackNode",
      sol::constructors<std::shared_ptr<dsp_primitives::LoopPlaybackNode>(int)>(),
      "setLoopLength", &dsp_primitives::LoopPlaybackNode::setLoopLength,
      "getLoopLength", &dsp_primitives::LoopPlaybackNode::getLoopLength,
      "setSpeed", &dsp_primitives::LoopPlaybackNode::setSpeed,
      "getSpeed", &dsp_primitives::LoopPlaybackNode::getSpeed,
      "setReversed", &dsp_primitives::LoopPlaybackNode::setReversed,
      "isReversed", &dsp_primitives::LoopPlaybackNode::isReversed,
      "play", &dsp_primitives::LoopPlaybackNode::play,
      "pause", &dsp_primitives::LoopPlaybackNode::pause,
      "stop", &dsp_primitives::LoopPlaybackNode::stop,
      "isPlaying", &dsp_primitives::LoopPlaybackNode::isPlaying,
      "seek", &dsp_primitives::LoopPlaybackNode::seekNormalized,
      "getNormalizedPosition", &dsp_primitives::LoopPlaybackNode::getNormalizedPosition,
      "getPeaks", [](std::shared_ptr<dsp_primitives::LoopPlaybackNode>& self, int numBuckets) -> std::vector<float> {
        std::vector<float> peaks;
        if (self) self->computePeaks(numBuckets, peaks);
        return peaks;
      });

  newLua.new_usertype<dsp_primitives::PlaybackStateGateNode>(
      "PlaybackStateGateNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>(int)>(),
      "play", &dsp_primitives::PlaybackStateGateNode::play,
      "pause", &dsp_primitives::PlaybackStateGateNode::pause,
      "stop", &dsp_primitives::PlaybackStateGateNode::stop,
      "setPlaying", &dsp_primitives::PlaybackStateGateNode::setPlaying,
      "isPlaying", &dsp_primitives::PlaybackStateGateNode::isPlaying,
      "setMuted", &dsp_primitives::PlaybackStateGateNode::setMuted,
      "isMuted", &dsp_primitives::PlaybackStateGateNode::isMuted);

  newLua.new_usertype<dsp_primitives::RetrospectiveCaptureNode>(
      "RetrospectiveCaptureNode",
      sol::constructors<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>(int)>(),
      "setCaptureSeconds", &dsp_primitives::RetrospectiveCaptureNode::setCaptureSeconds,
      "getCaptureSeconds", &dsp_primitives::RetrospectiveCaptureNode::getCaptureSeconds,
      "getCaptureSize", &dsp_primitives::RetrospectiveCaptureNode::getCaptureSize,
      "getWriteOffset", &dsp_primitives::RetrospectiveCaptureNode::getWriteOffset,
      "clear", &dsp_primitives::RetrospectiveCaptureNode::clear,
      "copyRecentToLoop",
      static_cast<bool (dsp_primitives::RetrospectiveCaptureNode::*)(
          const std::shared_ptr<dsp_primitives::LoopPlaybackNode>&, int, bool)>(
          &dsp_primitives::RetrospectiveCaptureNode::copyRecentToLoop));

  newLua.new_usertype<dsp_primitives::RecordStateNode>(
      "RecordStateNode",
      sol::constructors<std::shared_ptr<dsp_primitives::RecordStateNode>()>(),
      "startRecording", &dsp_primitives::RecordStateNode::startRecording,
      "stopRecording", &dsp_primitives::RecordStateNode::stopRecording,
      "isRecording", &dsp_primitives::RecordStateNode::isRecording,
      "setOverdub", &dsp_primitives::RecordStateNode::setOverdub,
      "isOverdub", &dsp_primitives::RecordStateNode::isOverdub);

  newLua.new_usertype<dsp_primitives::QuantizerNode>(
      "QuantizerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::QuantizerNode>()>(),
      "setTempo", &dsp_primitives::QuantizerNode::setTempo,
      "getTempo", &dsp_primitives::QuantizerNode::getTempo,
      "setBeatsPerBar", &dsp_primitives::QuantizerNode::setBeatsPerBar,
      "getBeatsPerBar", &dsp_primitives::QuantizerNode::getBeatsPerBar,
      "getSamplesPerBar", &dsp_primitives::QuantizerNode::getSamplesPerBar,
      "quantizeToNearestLegal", &dsp_primitives::QuantizerNode::quantizeToNearestLegal);

  newLua.new_usertype<dsp_primitives::RecordModePolicyNode>(
      "RecordModePolicyNode",
      sol::constructors<std::shared_ptr<dsp_primitives::RecordModePolicyNode>()>(),
      "setMode", &dsp_primitives::RecordModePolicyNode::setMode,
      "getMode", &dsp_primitives::RecordModePolicyNode::getMode,
      "usesRetrospectiveCommit", &dsp_primitives::RecordModePolicyNode::usesRetrospectiveCommit,
      "schedulesForwardCommitWhenIdle", &dsp_primitives::RecordModePolicyNode::schedulesForwardCommitWhenIdle);

  newLua.new_usertype<dsp_primitives::ForwardCommitSchedulerNode>(
      "ForwardCommitSchedulerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>()>(),
      "arm", &dsp_primitives::ForwardCommitSchedulerNode::arm,
      "clear", &dsp_primitives::ForwardCommitSchedulerNode::clear,
      "isArmed", &dsp_primitives::ForwardCommitSchedulerNode::isArmed,
      "getBars", &dsp_primitives::ForwardCommitSchedulerNode::getBars,
      "getLayerIndex", &dsp_primitives::ForwardCommitSchedulerNode::getLayerIndex,
      "shouldFire", &dsp_primitives::ForwardCommitSchedulerNode::shouldFire);

  newLua.new_usertype<dsp_primitives::TransportStateNode>(
      "TransportStateNode",
      sol::constructors<std::shared_ptr<dsp_primitives::TransportStateNode>()>(),
      "play", &dsp_primitives::TransportStateNode::play,
      "pause", &dsp_primitives::TransportStateNode::pause,
      "stop", &dsp_primitives::TransportStateNode::stop,
      "setState", &dsp_primitives::TransportStateNode::setState,
      "getState", &dsp_primitives::TransportStateNode::getState,
      "isPlaying", &dsp_primitives::TransportStateNode::isPlaying);

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

  newLua.new_usertype<dsp_primitives::SVFNode>(
      "SVFNode",
      sol::constructors<std::shared_ptr<dsp_primitives::SVFNode>()>(),
      "setCutoff", &dsp_primitives::SVFNode::setCutoff,
      "setResonance", &dsp_primitives::SVFNode::setResonance,
      "setMode", &dsp_primitives::SVFNode::setMode,
      "setDrive", &dsp_primitives::SVFNode::setDrive,
      "setMix", &dsp_primitives::SVFNode::setMix,
      "getCutoff", &dsp_primitives::SVFNode::getCutoff,
      "getResonance", &dsp_primitives::SVFNode::getResonance,
      "getMode", &dsp_primitives::SVFNode::getMode,
      "getDrive", &dsp_primitives::SVFNode::getDrive,
      "getMix", &dsp_primitives::SVFNode::getMix,
      "reset", &dsp_primitives::SVFNode::reset);

  newLua.new_usertype<dsp_primitives::StereoDelayNode>(
      "StereoDelayNode",
      sol::constructors<std::shared_ptr<dsp_primitives::StereoDelayNode>()>(),
      "setTimeMode", &dsp_primitives::StereoDelayNode::setTimeMode,
      "setTimeL", &dsp_primitives::StereoDelayNode::setTimeL,
      "setTimeR", &dsp_primitives::StereoDelayNode::setTimeR,
      "setDivisionL", &dsp_primitives::StereoDelayNode::setDivisionL,
      "setDivisionR", &dsp_primitives::StereoDelayNode::setDivisionR,
      "setFeedback", &dsp_primitives::StereoDelayNode::setFeedback,
      "setFeedbackCrossfeed", &dsp_primitives::StereoDelayNode::setFeedbackCrossfeed,
      "setFilterEnabled", &dsp_primitives::StereoDelayNode::setFilterEnabled,
      "setFilterCutoff", &dsp_primitives::StereoDelayNode::setFilterCutoff,
      "setFilterResonance", &dsp_primitives::StereoDelayNode::setFilterResonance,
      "setMix", &dsp_primitives::StereoDelayNode::setMix,
      "setPingPong", &dsp_primitives::StereoDelayNode::setPingPong,
      "setWidth", &dsp_primitives::StereoDelayNode::setWidth,
      "setFreeze", &dsp_primitives::StereoDelayNode::setFreeze,
      "setDucking", &dsp_primitives::StereoDelayNode::setDucking,
      "setTempo", &dsp_primitives::StereoDelayNode::setTempo,
      "getTimeMode", &dsp_primitives::StereoDelayNode::getTimeMode,
      "getTimeL", &dsp_primitives::StereoDelayNode::getTimeL,
      "getTimeR", &dsp_primitives::StereoDelayNode::getTimeR,
      "getMix", &dsp_primitives::StereoDelayNode::getMix,
      "getFeedback", &dsp_primitives::StereoDelayNode::getFeedback,
      "getPingPong", &dsp_primitives::StereoDelayNode::getPingPong,
      "getFreeze", &dsp_primitives::StereoDelayNode::getFreeze,
      "reset", &dsp_primitives::StereoDelayNode::reset);

  newLua.new_usertype<dsp_primitives::CompressorNode>(
      "CompressorNode",
      "setThreshold", &dsp_primitives::CompressorNode::setThreshold,
      "setRatio", &dsp_primitives::CompressorNode::setRatio,
      "setAttack", &dsp_primitives::CompressorNode::setAttack,
      "setRelease", &dsp_primitives::CompressorNode::setRelease,
      "setKnee", &dsp_primitives::CompressorNode::setKnee,
      "setMakeup", &dsp_primitives::CompressorNode::setMakeup,
      "setAutoMakeup", &dsp_primitives::CompressorNode::setAutoMakeup,
      "setMode", &dsp_primitives::CompressorNode::setMode,
      "setDetectorMode", &dsp_primitives::CompressorNode::setDetectorMode,
      "setSidechainHPF", &dsp_primitives::CompressorNode::setSidechainHPF,
      "setMix", &dsp_primitives::CompressorNode::setMix,
      "getThreshold", &dsp_primitives::CompressorNode::getThreshold,
      "getRatio", &dsp_primitives::CompressorNode::getRatio,
      "getAttack", &dsp_primitives::CompressorNode::getAttack,
      "getRelease", &dsp_primitives::CompressorNode::getRelease,
      "getKnee", &dsp_primitives::CompressorNode::getKnee,
      "getMakeup", &dsp_primitives::CompressorNode::getMakeup,
      "getAutoMakeup", &dsp_primitives::CompressorNode::getAutoMakeup,
      "getMode", &dsp_primitives::CompressorNode::getMode,
      "getDetectorMode", &dsp_primitives::CompressorNode::getDetectorMode,
      "getSidechainHPF", &dsp_primitives::CompressorNode::getSidechainHPF,
      "getMix", &dsp_primitives::CompressorNode::getMix,
      "getGainReduction", &dsp_primitives::CompressorNode::getGainReduction,
      "reset", &dsp_primitives::CompressorNode::reset);

  newLua.new_usertype<dsp_primitives::WaveShaperNode>(
      "WaveShaperNode",
      sol::constructors<std::shared_ptr<dsp_primitives::WaveShaperNode>()>(),
      "setCurve", &dsp_primitives::WaveShaperNode::setCurve,
      "getCurve", &dsp_primitives::WaveShaperNode::getCurve,
      "setDrive", &dsp_primitives::WaveShaperNode::setDrive,
      "getDrive", &dsp_primitives::WaveShaperNode::getDrive,
      "setOutput", &dsp_primitives::WaveShaperNode::setOutput,
      "getOutput", &dsp_primitives::WaveShaperNode::getOutput,
      "setPreFilter", &dsp_primitives::WaveShaperNode::setPreFilter,
      "getPreFilter", &dsp_primitives::WaveShaperNode::getPreFilter,
      "setPostFilter", &dsp_primitives::WaveShaperNode::setPostFilter,
      "getPostFilter", &dsp_primitives::WaveShaperNode::getPostFilter,
      "setBias", &dsp_primitives::WaveShaperNode::setBias,
      "getBias", &dsp_primitives::WaveShaperNode::getBias,
      "setMix", &dsp_primitives::WaveShaperNode::setMix,
      "getMix", &dsp_primitives::WaveShaperNode::getMix,
      "setOversample", &dsp_primitives::WaveShaperNode::setOversample,
      "getOversample", &dsp_primitives::WaveShaperNode::getOversample,
      "reset", &dsp_primitives::WaveShaperNode::reset);

  newLua.new_usertype<dsp_primitives::ChorusNode>(
      "ChorusNode",
      sol::constructors<std::shared_ptr<dsp_primitives::ChorusNode>()>(),
      "setRate", &dsp_primitives::ChorusNode::setRate,
      "setDepth", &dsp_primitives::ChorusNode::setDepth,
      "setVoices", &dsp_primitives::ChorusNode::setVoices,
      "setSpread", &dsp_primitives::ChorusNode::setSpread,
      "setFeedback", &dsp_primitives::ChorusNode::setFeedback,
      "setWaveform", &dsp_primitives::ChorusNode::setWaveform,
      "setMix", &dsp_primitives::ChorusNode::setMix,
      "getRate", &dsp_primitives::ChorusNode::getRate,
      "getDepth", &dsp_primitives::ChorusNode::getDepth,
      "getVoices", &dsp_primitives::ChorusNode::getVoices,
      "getSpread", &dsp_primitives::ChorusNode::getSpread,
      "getFeedback", &dsp_primitives::ChorusNode::getFeedback,
      "getWaveform", &dsp_primitives::ChorusNode::getWaveform,
      "getMix", &dsp_primitives::ChorusNode::getMix,
      "reset", &dsp_primitives::ChorusNode::reset);

  newLua.new_usertype<dsp_primitives::StereoWidenerNode>(
      "StereoWidenerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::StereoWidenerNode>()>(),
      "setWidth", &dsp_primitives::StereoWidenerNode::setWidth,
      "setMonoLowFreq", &dsp_primitives::StereoWidenerNode::setMonoLowFreq,
      "setMonoLowEnable", &dsp_primitives::StereoWidenerNode::setMonoLowEnable,
      "getWidth", &dsp_primitives::StereoWidenerNode::getWidth,
      "getMonoLowFreq", &dsp_primitives::StereoWidenerNode::getMonoLowFreq,
      "getMonoLowEnable", &dsp_primitives::StereoWidenerNode::getMonoLowEnable,
      "getCorrelation", &dsp_primitives::StereoWidenerNode::getCorrelation,
      "reset", &dsp_primitives::StereoWidenerNode::reset);

  newLua.new_usertype<dsp_primitives::PhaserNode>(
      "PhaserNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PhaserNode>()>(),
      "setRate", &dsp_primitives::PhaserNode::setRate,
      "setDepth", &dsp_primitives::PhaserNode::setDepth,
      "setStages", &dsp_primitives::PhaserNode::setStages,
      "setFeedback", &dsp_primitives::PhaserNode::setFeedback,
      "setSpread", &dsp_primitives::PhaserNode::setSpread,
      "getRate", &dsp_primitives::PhaserNode::getRate,
      "getDepth", &dsp_primitives::PhaserNode::getDepth,
      "getStages", &dsp_primitives::PhaserNode::getStages,
      "getFeedback", &dsp_primitives::PhaserNode::getFeedback,
      "getSpread", &dsp_primitives::PhaserNode::getSpread,
      "reset", &dsp_primitives::PhaserNode::reset);

  newLua.new_usertype<dsp_primitives::GranulatorNode>(
      "GranulatorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::GranulatorNode>()>(),
      "setGrainSize", &dsp_primitives::GranulatorNode::setGrainSize,
      "setDensity", &dsp_primitives::GranulatorNode::setDensity,
      "setPosition", &dsp_primitives::GranulatorNode::setPosition,
      "setPitch", &dsp_primitives::GranulatorNode::setPitch,
      "setSpray", &dsp_primitives::GranulatorNode::setSpray,
      "setFreeze", &dsp_primitives::GranulatorNode::setFreeze,
      "setEnvelope", &dsp_primitives::GranulatorNode::setEnvelope,
      "setMix", &dsp_primitives::GranulatorNode::setMix,
      "getGrainSize", &dsp_primitives::GranulatorNode::getGrainSize,
      "getDensity", &dsp_primitives::GranulatorNode::getDensity,
      "getPosition", &dsp_primitives::GranulatorNode::getPosition,
      "getPitch", &dsp_primitives::GranulatorNode::getPitch,
      "getSpray", &dsp_primitives::GranulatorNode::getSpray,
      "getFreeze", &dsp_primitives::GranulatorNode::getFreeze,
      "getEnvelope", &dsp_primitives::GranulatorNode::getEnvelope,
      "getMix", &dsp_primitives::GranulatorNode::getMix,
      "reset", &dsp_primitives::GranulatorNode::reset);

  newLua.new_usertype<dsp_primitives::StutterNode>(
      "StutterNode",
      sol::constructors<std::shared_ptr<dsp_primitives::StutterNode>()>(),
      "setLength", &dsp_primitives::StutterNode::setLength,
      "setGate", &dsp_primitives::StutterNode::setGate,
      "setFilterDecay", &dsp_primitives::StutterNode::setFilterDecay,
      "setPitchDecay", &dsp_primitives::StutterNode::setPitchDecay,
      "setProbability", &dsp_primitives::StutterNode::setProbability,
      "setPattern", &dsp_primitives::StutterNode::setPattern,
      "setTempo", &dsp_primitives::StutterNode::setTempo,
      "setMix", &dsp_primitives::StutterNode::setMix,
      "getLength", &dsp_primitives::StutterNode::getLength,
      "getGate", &dsp_primitives::StutterNode::getGate,
      "getFilterDecay", &dsp_primitives::StutterNode::getFilterDecay,
      "getPitchDecay", &dsp_primitives::StutterNode::getPitchDecay,
      "getProbability", &dsp_primitives::StutterNode::getProbability,
      "getPattern", &dsp_primitives::StutterNode::getPattern,
      "getMix", &dsp_primitives::StutterNode::getMix,
      "reset", &dsp_primitives::StutterNode::reset);



  newLua.new_usertype<dsp_primitives::ShimmerNode>(
      "ShimmerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::ShimmerNode>()>(),
      "setSize", &dsp_primitives::ShimmerNode::setSize,
      "setPitch", &dsp_primitives::ShimmerNode::setPitch,
      "setFeedback", &dsp_primitives::ShimmerNode::setFeedback,
      "setMix", &dsp_primitives::ShimmerNode::setMix,
      "setModulation", &dsp_primitives::ShimmerNode::setModulation,
      "setFilter", &dsp_primitives::ShimmerNode::setFilter,
      "getSize", &dsp_primitives::ShimmerNode::getSize,
      "getPitch", &dsp_primitives::ShimmerNode::getPitch,
      "getFeedback", &dsp_primitives::ShimmerNode::getFeedback,
      "getMix", &dsp_primitives::ShimmerNode::getMix,
      "getModulation", &dsp_primitives::ShimmerNode::getModulation,
      "getFilter", &dsp_primitives::ShimmerNode::getFilter,
      "reset", &dsp_primitives::ShimmerNode::reset);

  newLua.new_usertype<dsp_primitives::MultitapDelayNode>(
      "MultitapDelayNode",
      sol::constructors<std::shared_ptr<dsp_primitives::MultitapDelayNode>()>(),
      "setTapCount", &dsp_primitives::MultitapDelayNode::setTapCount,
      "setTapTime", &dsp_primitives::MultitapDelayNode::setTapTime,
      "setTapGain", &dsp_primitives::MultitapDelayNode::setTapGain,
      "setTapPan", &dsp_primitives::MultitapDelayNode::setTapPan,
      "setFeedback", &dsp_primitives::MultitapDelayNode::setFeedback,
      "setMix", &dsp_primitives::MultitapDelayNode::setMix,
      "getTapCount", &dsp_primitives::MultitapDelayNode::getTapCount,
      "getFeedback", &dsp_primitives::MultitapDelayNode::getFeedback,
      "getMix", &dsp_primitives::MultitapDelayNode::getMix,
      "reset", &dsp_primitives::MultitapDelayNode::reset);

  newLua.new_usertype<dsp_primitives::PitchShifterNode>(
      "PitchShifterNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PitchShifterNode>()>(),
      "setPitch", &dsp_primitives::PitchShifterNode::setPitch,
      "setWindow", &dsp_primitives::PitchShifterNode::setWindow,
      "setFeedback", &dsp_primitives::PitchShifterNode::setFeedback,
      "setMix", &dsp_primitives::PitchShifterNode::setMix,
      "getPitch", &dsp_primitives::PitchShifterNode::getPitch,
      "getWindow", &dsp_primitives::PitchShifterNode::getWindow,
      "getFeedback", &dsp_primitives::PitchShifterNode::getFeedback,
      "getMix", &dsp_primitives::PitchShifterNode::getMix,
      "reset", &dsp_primitives::PitchShifterNode::reset);

  newLua.new_usertype<dsp_primitives::TransientShaperNode>(
      "TransientShaperNode",
      sol::constructors<std::shared_ptr<dsp_primitives::TransientShaperNode>()>(),
      "setAttack", &dsp_primitives::TransientShaperNode::setAttack,
      "setSustain", &dsp_primitives::TransientShaperNode::setSustain,
      "setSensitivity", &dsp_primitives::TransientShaperNode::setSensitivity,
      "setMix", &dsp_primitives::TransientShaperNode::setMix,
      "getAttack", &dsp_primitives::TransientShaperNode::getAttack,
      "getSustain", &dsp_primitives::TransientShaperNode::getSustain,
      "getSensitivity", &dsp_primitives::TransientShaperNode::getSensitivity,
      "getMix", &dsp_primitives::TransientShaperNode::getMix,
      "getTransient", &dsp_primitives::TransientShaperNode::getTransient,
      "reset", &dsp_primitives::TransientShaperNode::reset);

  newLua.new_usertype<dsp_primitives::RingModulatorNode>(
      "RingModulatorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::RingModulatorNode>()>(),
      "setFrequency", &dsp_primitives::RingModulatorNode::setFrequency,
      "setDepth", &dsp_primitives::RingModulatorNode::setDepth,
      "setMix", &dsp_primitives::RingModulatorNode::setMix,
      "setSpread", &dsp_primitives::RingModulatorNode::setSpread,
      "getFrequency", &dsp_primitives::RingModulatorNode::getFrequency,
      "getDepth", &dsp_primitives::RingModulatorNode::getDepth,
      "getMix", &dsp_primitives::RingModulatorNode::getMix,
      "getSpread", &dsp_primitives::RingModulatorNode::getSpread,
      "reset", &dsp_primitives::RingModulatorNode::reset);

  newLua.new_usertype<dsp_primitives::BitCrusherNode>(
      "BitCrusherNode",
      sol::constructors<std::shared_ptr<dsp_primitives::BitCrusherNode>()>(),
      "setBits", &dsp_primitives::BitCrusherNode::setBits,
      "setRateReduction", &dsp_primitives::BitCrusherNode::setRateReduction,
      "setMix", &dsp_primitives::BitCrusherNode::setMix,
      "setOutput", &dsp_primitives::BitCrusherNode::setOutput,
      "getBits", &dsp_primitives::BitCrusherNode::getBits,
      "getRateReduction", &dsp_primitives::BitCrusherNode::getRateReduction,
      "getMix", &dsp_primitives::BitCrusherNode::getMix,
      "getOutput", &dsp_primitives::BitCrusherNode::getOutput,
      "reset", &dsp_primitives::BitCrusherNode::reset);

  newLua.new_usertype<dsp_primitives::FormantFilterNode>(
      "FormantFilterNode",
      sol::constructors<std::shared_ptr<dsp_primitives::FormantFilterNode>()>(),
      "setVowel", &dsp_primitives::FormantFilterNode::setVowel,
      "setShift", &dsp_primitives::FormantFilterNode::setShift,
      "setResonance", &dsp_primitives::FormantFilterNode::setResonance,
      "setDrive", &dsp_primitives::FormantFilterNode::setDrive,
      "setMix", &dsp_primitives::FormantFilterNode::setMix,
      "getVowel", &dsp_primitives::FormantFilterNode::getVowel,
      "getShift", &dsp_primitives::FormantFilterNode::getShift,
      "getResonance", &dsp_primitives::FormantFilterNode::getResonance,
      "getDrive", &dsp_primitives::FormantFilterNode::getDrive,
      "getMix", &dsp_primitives::FormantFilterNode::getMix,
      "reset", &dsp_primitives::FormantFilterNode::reset);

  newLua.new_usertype<dsp_primitives::ReverseDelayNode>(
      "ReverseDelayNode",
      sol::constructors<std::shared_ptr<dsp_primitives::ReverseDelayNode>()>(),
      "setTime", &dsp_primitives::ReverseDelayNode::setTime,
      "setWindow", &dsp_primitives::ReverseDelayNode::setWindow,
      "setFeedback", &dsp_primitives::ReverseDelayNode::setFeedback,
      "setMix", &dsp_primitives::ReverseDelayNode::setMix,
      "getTime", &dsp_primitives::ReverseDelayNode::getTime,
      "getWindow", &dsp_primitives::ReverseDelayNode::getWindow,
      "getFeedback", &dsp_primitives::ReverseDelayNode::getFeedback,
      "getMix", &dsp_primitives::ReverseDelayNode::getMix,
      "reset", &dsp_primitives::ReverseDelayNode::reset);

  newLua.new_usertype<dsp_primitives::EnvelopeFollowerNode>(
      "EnvelopeFollowerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>()>(),
      "setAttack", &dsp_primitives::EnvelopeFollowerNode::setAttack,
      "setRelease", &dsp_primitives::EnvelopeFollowerNode::setRelease,
      "setSensitivity", &dsp_primitives::EnvelopeFollowerNode::setSensitivity,
      "setHighpass", &dsp_primitives::EnvelopeFollowerNode::setHighpass,
      "getAttack", &dsp_primitives::EnvelopeFollowerNode::getAttack,
      "getRelease", &dsp_primitives::EnvelopeFollowerNode::getRelease,
      "getSensitivity", &dsp_primitives::EnvelopeFollowerNode::getSensitivity,
      "getHighpass", &dsp_primitives::EnvelopeFollowerNode::getHighpass,
      "getEnvelope", &dsp_primitives::EnvelopeFollowerNode::getEnvelope,
      "reset", &dsp_primitives::EnvelopeFollowerNode::reset);

  newLua.new_usertype<dsp_primitives::PitchDetectorNode>(
      "PitchDetectorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PitchDetectorNode>()>(),
      "setMinFreq", &dsp_primitives::PitchDetectorNode::setMinFreq,
      "setMaxFreq", &dsp_primitives::PitchDetectorNode::setMaxFreq,
      "setSensitivity", &dsp_primitives::PitchDetectorNode::setSensitivity,
      "setSmoothing", &dsp_primitives::PitchDetectorNode::setSmoothing,
      "getMinFreq", &dsp_primitives::PitchDetectorNode::getMinFreq,
      "getMaxFreq", &dsp_primitives::PitchDetectorNode::getMaxFreq,
      "getSensitivity", &dsp_primitives::PitchDetectorNode::getSensitivity,
      "getSmoothing", &dsp_primitives::PitchDetectorNode::getSmoothing,
      "getPitch", &dsp_primitives::PitchDetectorNode::getPitch,
      "getConfidence", &dsp_primitives::PitchDetectorNode::getConfidence,
      "reset", &dsp_primitives::PitchDetectorNode::reset);

  newLua.new_usertype<dsp_primitives::CrossfaderNode>(
      "CrossfaderNode",
      sol::constructors<std::shared_ptr<dsp_primitives::CrossfaderNode>()>(),
      "setPosition", &dsp_primitives::CrossfaderNode::setPosition,
      "setCurve", &dsp_primitives::CrossfaderNode::setCurve,
      "setMix", &dsp_primitives::CrossfaderNode::setMix,
      "getPosition", &dsp_primitives::CrossfaderNode::getPosition,
      "getCurve", &dsp_primitives::CrossfaderNode::getCurve,
      "getMix", &dsp_primitives::CrossfaderNode::getMix,
      "reset", &dsp_primitives::CrossfaderNode::reset);

  newLua.new_usertype<dsp_primitives::MixerNode>(
      "MixerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::MixerNode>()>(),
      "setInputCount", &dsp_primitives::MixerNode::setInputCount,
      "getInputCount", &dsp_primitives::MixerNode::getInputCount,
      "setGain", [](dsp_primitives::MixerNode& mixer, int busIndex, float gain) {
        mixer.setGain(busIndex, gain);
      },
      "setPan", [](dsp_primitives::MixerNode& mixer, int busIndex, float pan) {
        mixer.setPan(busIndex, pan);
      },
      "getGain", [](const dsp_primitives::MixerNode& mixer, int busIndex) {
        return mixer.getGain(busIndex);
      },
      "getPan", [](const dsp_primitives::MixerNode& mixer, int busIndex) {
        return mixer.getPan(busIndex);
      },
      "setGain1", &dsp_primitives::MixerNode::setGain1,
      "setGain2", &dsp_primitives::MixerNode::setGain2,
      "setGain3", &dsp_primitives::MixerNode::setGain3,
      "setGain4", &dsp_primitives::MixerNode::setGain4,
      "setPan1", &dsp_primitives::MixerNode::setPan1,
      "setPan2", &dsp_primitives::MixerNode::setPan2,
      "setPan3", &dsp_primitives::MixerNode::setPan3,
      "setPan4", &dsp_primitives::MixerNode::setPan4,
      "setMaster", &dsp_primitives::MixerNode::setMaster,
      "getGain1", &dsp_primitives::MixerNode::getGain1,
      "getGain2", &dsp_primitives::MixerNode::getGain2,
      "getGain3", &dsp_primitives::MixerNode::getGain3,
      "getGain4", &dsp_primitives::MixerNode::getGain4,
      "getPan1", &dsp_primitives::MixerNode::getPan1,
      "getPan2", &dsp_primitives::MixerNode::getPan2,
      "getPan3", &dsp_primitives::MixerNode::getPan3,
      "getPan4", &dsp_primitives::MixerNode::getPan4,
      "getMaster", &dsp_primitives::MixerNode::getMaster,
      "reset", &dsp_primitives::MixerNode::reset);

  newLua.new_usertype<dsp_primitives::NoiseGeneratorNode>(
      "NoiseGeneratorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>()>(),
      "setLevel", &dsp_primitives::NoiseGeneratorNode::setLevel,
      "setColor", &dsp_primitives::NoiseGeneratorNode::setColor,
      "getLevel", &dsp_primitives::NoiseGeneratorNode::getLevel,
      "getColor", &dsp_primitives::NoiseGeneratorNode::getColor,
      "reset", &dsp_primitives::NoiseGeneratorNode::reset);

  newLua.new_usertype<dsp_primitives::MSEncoderNode>(
      "MSEncoderNode",
      sol::constructors<std::shared_ptr<dsp_primitives::MSEncoderNode>()>(),
      "setWidth", &dsp_primitives::MSEncoderNode::setWidth,
      "getWidth", &dsp_primitives::MSEncoderNode::getWidth,
      "reset", &dsp_primitives::MSEncoderNode::reset);

  newLua.new_usertype<dsp_primitives::MSDecoderNode>(
      "MSDecoderNode",
      sol::constructors<std::shared_ptr<dsp_primitives::MSDecoderNode>()>(),
      "reset", &dsp_primitives::MSDecoderNode::reset);



  newLua.new_usertype<dsp_primitives::EQNode>(
      "EQNode",
      sol::constructors<std::shared_ptr<dsp_primitives::EQNode>()>(),
      "setLowGain", &dsp_primitives::EQNode::setLowGain,
      "setLowFreq", &dsp_primitives::EQNode::setLowFreq,
      "setMidGain", &dsp_primitives::EQNode::setMidGain,
      "setMidFreq", &dsp_primitives::EQNode::setMidFreq,
      "setMidQ", &dsp_primitives::EQNode::setMidQ,
      "setHighGain", &dsp_primitives::EQNode::setHighGain,
      "setHighFreq", &dsp_primitives::EQNode::setHighFreq,
      "setOutput", &dsp_primitives::EQNode::setOutput,
      "setMix", &dsp_primitives::EQNode::setMix,
      "getLowGain", &dsp_primitives::EQNode::getLowGain,
      "getLowFreq", &dsp_primitives::EQNode::getLowFreq,
      "getMidGain", &dsp_primitives::EQNode::getMidGain,
      "getMidFreq", &dsp_primitives::EQNode::getMidFreq,
      "getMidQ", &dsp_primitives::EQNode::getMidQ,
      "getHighGain", &dsp_primitives::EQNode::getHighGain,
      "getHighFreq", &dsp_primitives::EQNode::getHighFreq,
      "getOutput", &dsp_primitives::EQNode::getOutput,
      "getMix", &dsp_primitives::EQNode::getMix,
      "reset", &dsp_primitives::EQNode::reset);

  newLua.new_usertype<dsp_primitives::LimiterNode>(
      "LimiterNode",
      sol::constructors<std::shared_ptr<dsp_primitives::LimiterNode>()>(),
      "setThreshold", &dsp_primitives::LimiterNode::setThreshold,
      "setRelease", &dsp_primitives::LimiterNode::setRelease,
      "setMakeup", &dsp_primitives::LimiterNode::setMakeup,
      "setSoftClip", &dsp_primitives::LimiterNode::setSoftClip,
      "setMix", &dsp_primitives::LimiterNode::setMix,
      "getThreshold", &dsp_primitives::LimiterNode::getThreshold,
      "getRelease", &dsp_primitives::LimiterNode::getRelease,
      "getMakeup", &dsp_primitives::LimiterNode::getMakeup,
      "getSoftClip", &dsp_primitives::LimiterNode::getSoftClip,
      "getMix", &dsp_primitives::LimiterNode::getMix,
      "getGainReduction", &dsp_primitives::LimiterNode::getGainReduction,
      "reset", &dsp_primitives::LimiterNode::reset);

  newLua.new_usertype<dsp_primitives::SpectrumAnalyzerNode>(
      "SpectrumAnalyzerNode",
      sol::constructors<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>()>(),
      "setSensitivity", &dsp_primitives::SpectrumAnalyzerNode::setSensitivity,
      "setSmoothing", &dsp_primitives::SpectrumAnalyzerNode::setSmoothing,
      "setFloor", &dsp_primitives::SpectrumAnalyzerNode::setFloor,
      "getSensitivity", &dsp_primitives::SpectrumAnalyzerNode::getSensitivity,
      "getSmoothing", &dsp_primitives::SpectrumAnalyzerNode::getSmoothing,
      "getFloor", &dsp_primitives::SpectrumAnalyzerNode::getFloor,
      "getBand1", &dsp_primitives::SpectrumAnalyzerNode::getBand1,
      "getBand2", &dsp_primitives::SpectrumAnalyzerNode::getBand2,
      "getBand3", &dsp_primitives::SpectrumAnalyzerNode::getBand3,
      "getBand4", &dsp_primitives::SpectrumAnalyzerNode::getBand4,
      "getBand5", &dsp_primitives::SpectrumAnalyzerNode::getBand5,
      "getBand6", &dsp_primitives::SpectrumAnalyzerNode::getBand6,
      "getBand7", &dsp_primitives::SpectrumAnalyzerNode::getBand7,
      "getBand8", &dsp_primitives::SpectrumAnalyzerNode::getBand8,
      "reset", &dsp_primitives::SpectrumAnalyzerNode::reset);

  auto toPrimitiveNode = [](const sol::object &obj)
      -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
    if (obj.is<std::shared_ptr<dsp_primitives::IPrimitiveNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::IPrimitiveNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::GainNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::GainNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RecordStateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RecordStateNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::QuantizerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::QuantizerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::TransportStateNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::TransportStateNode>>();
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
    if (obj.is<std::shared_ptr<dsp_primitives::SVFNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SVFNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StereoDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StereoDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::CompressorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::CompressorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::WaveShaperNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::WaveShaperNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ChorusNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ChorusNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StereoWidenerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StereoWidenerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PhaserNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PhaserNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::GranulatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::GranulatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::StutterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::StutterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ShimmerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ShimmerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MultitapDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MultitapDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PitchShifterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PitchShifterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::TransientShaperNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::TransientShaperNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::RingModulatorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::RingModulatorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::BitCrusherNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::BitCrusherNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::FormantFilterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::FormantFilterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::ReverseDelayNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::ReverseDelayNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::PitchDetectorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::PitchDetectorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::CrossfaderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::CrossfaderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MixerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MixerNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MSEncoderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MSEncoderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MSDecoderNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MSDecoderNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MidiVoiceNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MidiVoiceNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::MidiInputNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::MidiInputNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::EQNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::EQNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::LimiterNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::LimiterNode>>();
    }
    if (obj.is<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>()) {
      return obj.as<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>();
    }
    if (obj.is<sol::table>()) {
      sol::table table = obj.as<sol::table>();
      sol::object nodeObj = table["__outputNode"];
      if (!nodeObj.valid()) {
        nodeObj = table["__node"];
      }
      if (nodeObj.valid()) {
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::GainNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::GainNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::LoopPlaybackNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PlaybackStateGateNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RetrospectiveCaptureNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RecordStateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RecordStateNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::QuantizerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::QuantizerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RecordModePolicyNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ForwardCommitSchedulerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::TransportStateNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::TransportStateNode>>();
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
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SVFNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SVFNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StereoDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StereoDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::CompressorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::CompressorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::WaveShaperNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::WaveShaperNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ChorusNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ChorusNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StereoWidenerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StereoWidenerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PhaserNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PhaserNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::GranulatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::GranulatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::StutterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::StutterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ShimmerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ShimmerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MultitapDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MultitapDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PitchShifterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PitchShifterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::TransientShaperNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::TransientShaperNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::RingModulatorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::RingModulatorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::BitCrusherNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::BitCrusherNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::FormantFilterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::FormantFilterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::ReverseDelayNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::ReverseDelayNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::EnvelopeFollowerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::PitchDetectorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::PitchDetectorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::CrossfaderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::CrossfaderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MixerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MixerNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::NoiseGeneratorNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MSEncoderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MSEncoderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MSDecoderNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MSDecoderNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MidiVoiceNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MidiVoiceNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::MidiInputNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::MidiInputNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::EQNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::EQNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::LimiterNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::LimiterNode>>();
        }
        if (nodeObj.is<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>()) {
          return nodeObj.as<std::shared_ptr<dsp_primitives::SpectrumAnalyzerNode>>();
        }
      }
    }
    return nullptr;
  };

  auto primitives = newLua.create_table();
  {
    auto playheadApi = newLua.create_table();
    playheadApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::PlayheadNode>();
        trackNode(node);
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
    // PassthroughNode.new(numChannels [, mode])
    // mode: 0 = MonitorControlled (default, always-on input-dsp source)
    //       1 = RawCapture (monitor-toggle source)
    passthroughApi["new"] = [graph, &newLua, &trackNode](int numChannels, sol::optional<int> mode) {
        using Mode = dsp_primitives::PassthroughNode::HostInputMode;
        const Mode hostMode = (mode.has_value() && mode.value() == 1)
                                  ? Mode::RawCapture
                                  : Mode::MonitorControlled;
        auto node = std::make_shared<dsp_primitives::PassthroughNode>(numChannels, hostMode);
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        return t;
      };
    primitives["PassthroughNode"] = passthroughApi;
  }
  {
    auto gainApi = newLua.create_table();
    gainApi["new"] = [graph, &newLua, &trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::GainNode>(numChannels);
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setGain"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
            n->setGain(v);
          }
        };
        t["getGain"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
            return n->getGain();
          }
          return 0.0f;
        };
        t["setMuted"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
            n->setMuted(v);
          }
        };
        t["isMuted"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
            return n->isMuted();
          }
          return false;
        };
        return t;
      };
    primitives["GainNode"] = gainApi;
  }
  {
    auto loopPlaybackApi = newLua.create_table();
    loopPlaybackApi["new"] = [graph, &newLua, &trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::LoopPlaybackNode>(numChannels);
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setLoopLength"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->setLoopLength(v);
          }
        };
        t["getLoopLength"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            return n->getLoopLength();
          }
          return 0;
        };
        t["setSpeed"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->setSpeed(v);
          }
        };
        t["setReversed"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->setReversed(v);
          }
        };
        t["play"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->play();
          }
        };
        t["pause"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->pause();
          }
        };
        t["stop"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->stop();
          }
        };
        t["seek"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            n->seekNormalized(v);
          }
        };
        t["getNormalizedPosition"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self)) {
            return n->getNormalizedPosition();
          }
          return 0.0f;
        };
        return t;
      };
    primitives["LoopPlaybackNode"] = loopPlaybackApi;
  }
  {
    auto gateApi = newLua.create_table();
    gateApi["new"] = [graph, &newLua, &trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::PlaybackStateGateNode>(numChannels);
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["play"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            n->play();
          }
        };
        t["pause"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            n->pause();
          }
        };
        t["stop"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            n->stop();
          }
        };
        t["setPlaying"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            n->setPlaying(v);
          }
        };
        t["isPlaying"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            return n->isPlaying();
          }
          return false;
        };
        t["setMuted"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            n->setMuted(v);
          }
        };
        t["isMuted"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self)) {
            return n->isMuted();
          }
          return false;
        };
        return t;
      };
    primitives["PlaybackStateGateNode"] = gateApi;
  }
  {
    auto captureApi = newLua.create_table();
    captureApi["new"] = [graph, &newLua, &trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::RetrospectiveCaptureNode>(numChannels);
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setCaptureSeconds"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self)) {
            n->setCaptureSeconds(v);
          }
        };
        t["getCaptureSeconds"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self)) {
            return n->getCaptureSeconds();
          }
          return 0.0f;
        };
        t["getCaptureSize"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self)) {
            return n->getCaptureSize();
          }
          return 0;
        };
        t["clear"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self)) {
            n->clear();
          }
        };
        return t;
      };
    primitives["RetrospectiveCaptureNode"] = captureApi;
  }
  {
    auto recordStateApi = newLua.create_table();
    recordStateApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::RecordStateNode>();
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["startRecording"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordStateNode>(self)) {
            n->startRecording();
          }
        };
        t["stopRecording"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordStateNode>(self)) {
            n->stopRecording();
          }
        };
        t["isRecording"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordStateNode>(self)) {
            return n->isRecording();
          }
          return false;
        };
        t["setOverdub"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::RecordStateNode>(self)) {
            n->setOverdub(v);
          }
        };
        t["isOverdub"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordStateNode>(self)) {
            return n->isOverdub();
          }
          return false;
        };
        return t;
      };
    primitives["RecordStateNode"] = recordStateApi;
  }
  {
    auto quantizerApi = newLua.create_table();
    quantizerApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::QuantizerNode>();
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setTempo"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::QuantizerNode>(self)) {
            n->setTempo(v);
          }
        };
        t["getTempo"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::QuantizerNode>(self)) {
            return n->getTempo();
          }
          return 120.0f;
        };
        t["setBeatsPerBar"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::QuantizerNode>(self)) {
            n->setBeatsPerBar(v);
          }
        };
        t["getSamplesPerBar"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::QuantizerNode>(self)) {
            return n->getSamplesPerBar();
          }
          return 0.0f;
        };
        t["quantizeToNearestLegal"] = [](sol::table self, int samples) {
          if (auto n = tableNode<dsp_primitives::QuantizerNode>(self)) {
            return n->quantizeToNearestLegal(samples);
          }
          return samples;
        };
        return t;
      };
    primitives["QuantizerNode"] = quantizerApi;
  }
  {
    auto modeApi = newLua.create_table();
    modeApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::RecordModePolicyNode>();
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["setMode"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self)) {
            n->setMode(v);
          }
        };
        t["getMode"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self)) {
            return n->getMode();
          }
          return 0;
        };
        t["usesRetrospectiveCommit"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self)) {
            return n->usesRetrospectiveCommit();
          }
          return false;
        };
        t["schedulesForwardCommitWhenIdle"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self)) {
            return n->schedulesForwardCommitWhenIdle();
          }
          return false;
        };
        return t;
      };
    primitives["RecordModePolicyNode"] = modeApi;
  }
  {
    auto forwardApi = newLua.create_table();
    forwardApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::ForwardCommitSchedulerNode>();
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["arm"] = [](sol::table self, float bars, int layerIndex, double currentSamples, float samplesPerBar) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            n->arm(bars, layerIndex, currentSamples, samplesPerBar);
          }
        };
        t["clear"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            n->clear();
          }
        };
        t["isArmed"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            return n->isArmed();
          }
          return false;
        };
        t["shouldFire"] = [](sol::table self, double currentSamples) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            return n->shouldFire(currentSamples);
          }
          return false;
        };
        t["getBars"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            return n->getBars();
          }
          return 0.0f;
        };
        t["getLayerIndex"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self)) {
            return n->getLayerIndex();
          }
          return 0;
        };
        return t;
      };
    primitives["ForwardCommitSchedulerNode"] = forwardApi;
  }
  {
    auto transportApi = newLua.create_table();
    transportApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::TransportStateNode>();
        trackNode(node);
        auto t = newLua.create_table();
        t["__node"] = node;
        t["play"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            n->play();
          }
        };
        t["pause"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            n->pause();
          }
        };
        t["stop"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            n->stop();
          }
        };
        t["setState"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            n->setState(v);
          }
        };
        t["getState"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            return n->getState();
          }
          return 0;
        };
        t["isPlaying"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::TransportStateNode>(self)) {
            return n->isPlaying();
          }
          return false;
        };
        return t;
      };
    primitives["TransportStateNode"] = transportApi;
  }
  {
    auto oscApi = newLua.create_table();
    oscApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::OscillatorNode>();
        trackNode(node);
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
    reverbApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::ReverbNode>();
        trackNode(node);
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
    filterApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::FilterNode>();
        trackNode(node);
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
    distApi["new"] = [graph, &newLua, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::DistortionNode>();
        trackNode(node);
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
  {
    auto svfApi = newLua.create_table();
    svfApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::SVFNode>();
        trackNode(node);
        return node;
      };
    primitives["SVFNode"] = svfApi;
  }
  {
    auto delayApi = newLua.create_table();
    delayApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::StereoDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["StereoDelayNode"] = delayApi;
  }

  {
    auto compressorApi = newLua.create_table();
    compressorApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::CompressorNode>();
        trackNode(node);
        return node;
      };
    primitives["CompressorNode"] = compressorApi;
  }

  {
    auto waveShaperApi = newLua.create_table();
    waveShaperApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::WaveShaperNode>();
        trackNode(node);
        return node;
      };
    primitives["WaveShaperNode"] = waveShaperApi;
  }

  {
    auto chorusApi = newLua.create_table();
    chorusApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::ChorusNode>();
        trackNode(node);
        return node;
      };
    primitives["ChorusNode"] = chorusApi;
  }

  {
    auto widenerApi = newLua.create_table();
    widenerApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::StereoWidenerNode>();
        trackNode(node);
        return node;
      };
    primitives["StereoWidenerNode"] = widenerApi;
  }

  {
    auto phaserApi = newLua.create_table();
    phaserApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::PhaserNode>();
        trackNode(node);
        return node;
      };
    primitives["PhaserNode"] = phaserApi;
  }

  {
    auto granulatorApi = newLua.create_table();
    granulatorApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::GranulatorNode>();
        trackNode(node);
        return node;
      };
    primitives["GranulatorNode"] = granulatorApi;
  }

  {
    auto stutterApi = newLua.create_table();
    stutterApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::StutterNode>();
        trackNode(node);
        return node;
      };
    primitives["StutterNode"] = stutterApi;
  }

  {
    auto shimmerApi = newLua.create_table();
    shimmerApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::ShimmerNode>();
        trackNode(node);
        return node;
      };
    primitives["ShimmerNode"] = shimmerApi;
  }

  {
    auto multitapApi = newLua.create_table();
    multitapApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::MultitapDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["MultitapDelayNode"] = multitapApi;
  }

  {
    auto pitchShifterApi = newLua.create_table();
    pitchShifterApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::PitchShifterNode>();
        trackNode(node);
        return node;
      };
    primitives["PitchShifterNode"] = pitchShifterApi;
  }

  {
    auto transientShaperApi = newLua.create_table();
    transientShaperApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::TransientShaperNode>();
        trackNode(node);
        return node;
      };
    primitives["TransientShaperNode"] = transientShaperApi;
  }

  {
    auto ringModApi = newLua.create_table();
    ringModApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::RingModulatorNode>();
        trackNode(node);
        return node;
      };
    primitives["RingModulatorNode"] = ringModApi;
  }

  {
    auto bitCrusherApi = newLua.create_table();
    bitCrusherApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::BitCrusherNode>();
        trackNode(node);
        return node;
      };
    primitives["BitCrusherNode"] = bitCrusherApi;
  }

  {
    auto formantApi = newLua.create_table();
    formantApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::FormantFilterNode>();
        trackNode(node);
        return node;
      };
    primitives["FormantFilterNode"] = formantApi;
  }

  {
    auto reverseDelayApi = newLua.create_table();
    reverseDelayApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::ReverseDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["ReverseDelayNode"] = reverseDelayApi;
  }

  {
    auto envelopeApi = newLua.create_table();
    envelopeApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::EnvelopeFollowerNode>();
        trackNode(node);
        return node;
      };
    primitives["EnvelopeFollowerNode"] = envelopeApi;
  }

  {
    auto pitchDetectorApi = newLua.create_table();
    pitchDetectorApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::PitchDetectorNode>();
        trackNode(node);
        return node;
      };
    primitives["PitchDetectorNode"] = pitchDetectorApi;
  }

  {
    auto crossfaderApi = newLua.create_table();
    crossfaderApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::CrossfaderNode>();
        trackNode(node);
        return node;
      };
    primitives["CrossfaderNode"] = crossfaderApi;
  }

  {
    auto mixerApi = newLua.create_table();
    mixerApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::MixerNode>();
        trackNode(node);
        return node;
      };
    primitives["MixerNode"] = mixerApi;
  }

  {
    auto noiseApi = newLua.create_table();
    noiseApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::NoiseGeneratorNode>();
        trackNode(node);
        return node;
      };
    primitives["NoiseGeneratorNode"] = noiseApi;
  }

  {
    auto msEncApi = newLua.create_table();
    msEncApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::MSEncoderNode>();
        trackNode(node);
        return node;
      };
    primitives["MSEncoderNode"] = msEncApi;
  }

  {
    auto msDecApi = newLua.create_table();
    msDecApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::MSDecoderNode>();
        trackNode(node);
        return node;
      };
    primitives["MSDecoderNode"] = msDecApi;
  }

  {
    auto eqApi = newLua.create_table();
    eqApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::EQNode>();
        trackNode(node);
        return node;
      };
    primitives["EQNode"] = eqApi;
  }

  {
    auto limiterApi = newLua.create_table();
    limiterApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::LimiterNode>();
        trackNode(node);
        return node;
      };
    primitives["LimiterNode"] = limiterApi;
  }

  {
    auto spectrumApi = newLua.create_table();
    spectrumApi["new"] = [graph, &trackNode]() {
        auto node = std::make_shared<dsp_primitives::SpectrumAnalyzerNode>();
        trackNode(node);
        return node;
      };
    primitives["SpectrumAnalyzerNode"] = spectrumApi;
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

  graphTable["markInput"] = [graph, toPrimitiveNode](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::InputDSP);
      return true;
    };
  graphTable["markMonitor"] = [graph, toPrimitiveNode](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::Monitor);
      return true;
    };
  graphTable["markOutput"] = [graph, toPrimitiveNode](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::OutputDSP);
      return true;
    };

  auto paramsTable = newLua.create_table();
  paramsTable["register"] =
      [&newParamSpecs, &newParamValues, &newExternalToInternalPath,
       &newInternalToExternalPath, &mapInternalToExternal,
       &mapExternalToInternal](const std::string &rawPath,
                               sol::table options) {
        const std::string externalPath = mapInternalToExternal(rawPath);
        const std::string internalPath = mapExternalToInternal(externalPath);
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
        newParamSpecs[externalPath] = spec;
        newParamValues[externalPath] = spec.defaultValue;
        newExternalToInternalPath[externalPath] = internalPath;
        newInternalToExternalPath[internalPath] = externalPath;
      };

  paramsTable["bind"] =
      [&newParamBindings, toPrimitiveNode, &mapInternalToExternal](
          const std::string &rawPath, const sol::object &nodeObj,
          const std::string &method) {
        const std::string path = mapInternalToExternal(rawPath);
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

        if (auto gain = std::dynamic_pointer_cast<dsp_primitives::GainNode>(node)) {
          if (method == "setGain") {
            newParamBindings[path] = [gain](float v) { gain->setGain(v); };
            return true;
          }
          if (method == "setMuted") {
            newParamBindings[path] = [gain](float v) { gain->setMuted(v > 0.5f); };
            return true;
          }
        }

        if (auto playback = std::dynamic_pointer_cast<dsp_primitives::LoopPlaybackNode>(node)) {
          if (method == "setLoopLength") {
            newParamBindings[path] = [playback](float v) {
              playback->setLoopLength(static_cast<int>(v));
            };
            return true;
          }
          if (method == "setSpeed") {
            newParamBindings[path] = [playback](float v) { playback->setSpeed(v); };
            return true;
          }
          if (method == "setReversed") {
            newParamBindings[path] = [playback](float v) { playback->setReversed(v > 0.5f); };
            return true;
          }
          if (method == "seek") {
            newParamBindings[path] = [playback](float v) { playback->seekNormalized(v); };
            return true;
          }
        }

        if (auto gate = std::dynamic_pointer_cast<dsp_primitives::PlaybackStateGateNode>(node)) {
          if (method == "setMuted") {
            newParamBindings[path] = [gate](float v) { gate->setMuted(v > 0.5f); };
            return true;
          }
          if (method == "setPlaying") {
            newParamBindings[path] = [gate](float v) { gate->setPlaying(v > 0.5f); };
            return true;
          }
        }

        if (auto capture = std::dynamic_pointer_cast<dsp_primitives::RetrospectiveCaptureNode>(node)) {
          if (method == "setCaptureSeconds") {
            newParamBindings[path] = [capture](float v) { capture->setCaptureSeconds(v); };
            return true;
          }
        }

        if (auto record = std::dynamic_pointer_cast<dsp_primitives::RecordStateNode>(node)) {
          if (method == "setOverdub") {
            newParamBindings[path] = [record](float v) { record->setOverdub(v > 0.5f); };
            return true;
          }
          if (method == "setRecording") {
            newParamBindings[path] = [record](float v) {
              if (v > 0.5f) {
                record->startRecording();
              } else {
                record->stopRecording();
              }
            };
            return true;
          }
        }

        if (auto quantizer = std::dynamic_pointer_cast<dsp_primitives::QuantizerNode>(node)) {
          if (method == "setTempo") {
            newParamBindings[path] = [quantizer](float v) { quantizer->setTempo(v); };
            return true;
          }
          if (method == "setBeatsPerBar") {
            newParamBindings[path] = [quantizer](float v) { quantizer->setBeatsPerBar(v); };
            return true;
          }
        }

        if (auto mode = std::dynamic_pointer_cast<dsp_primitives::RecordModePolicyNode>(node)) {
          if (method == "setMode") {
            newParamBindings[path] = [mode](float v) {
              mode->setMode(static_cast<int>(v));
            };
            return true;
          }
        }

        if (auto transport = std::dynamic_pointer_cast<dsp_primitives::TransportStateNode>(node)) {
          if (method == "setState") {
            newParamBindings[path] = [transport](float v) {
              transport->setState(static_cast<int>(v));
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

        if (auto svf = std::dynamic_pointer_cast<dsp_primitives::SVFNode>(node)) {
          if (method == "setCutoff") {
            newParamBindings[path] = [svf](float v) { svf->setCutoff(v); };
            return true;
          }
          if (method == "setResonance") {
            newParamBindings[path] = [svf](float v) { svf->setResonance(v); };
            return true;
          }
          if (method == "setMode") {
            newParamBindings[path] = [svf](float v) { svf->setMode(static_cast<dsp_primitives::SVFNode::Mode>(static_cast<int>(v))); };
            return true;
          }
          if (method == "setDrive") {
            newParamBindings[path] = [svf](float v) { svf->setDrive(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [svf](float v) { svf->setMix(v); };
            return true;
          }
        }

        if (auto delay = std::dynamic_pointer_cast<dsp_primitives::StereoDelayNode>(node)) {
          if (method == "setTimeMode") {
            newParamBindings[path] = [delay](float v) { delay->setTimeMode(static_cast<dsp_primitives::StereoDelayNode::TimeMode>(static_cast<int>(v))); };
            return true;
          }
          if (method == "setTimeL") {
            newParamBindings[path] = [delay](float v) { delay->setTimeL(v); };
            return true;
          }
          if (method == "setTimeR") {
            newParamBindings[path] = [delay](float v) { delay->setTimeR(v); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [delay](float v) { delay->setFeedback(v); };
            return true;
          }
          if (method == "setPingPong") {
            newParamBindings[path] = [delay](float v) { delay->setPingPong(v > 0.5f); };
            return true;
          }
          if (method == "setFilterEnabled") {
            newParamBindings[path] = [delay](float v) { delay->setFilterEnabled(v > 0.5f); };
            return true;
          }
          if (method == "setFilterCutoff") {
            newParamBindings[path] = [delay](float v) { delay->setFilterCutoff(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [delay](float v) { delay->setMix(v); };
            return true;
          }
          if (method == "setFreeze") {
            newParamBindings[path] = [delay](float v) { delay->setFreeze(v > 0.5f); };
            return true;
          }
        }

        if (auto comp = std::dynamic_pointer_cast<dsp_primitives::CompressorNode>(node)) {
          if (method == "setThreshold") {
            newParamBindings[path] = [comp](float v) { comp->setThreshold(v); };
            return true;
          }
          if (method == "setRatio") {
            newParamBindings[path] = [comp](float v) { comp->setRatio(v); };
            return true;
          }
          if (method == "setAttack") {
            newParamBindings[path] = [comp](float v) { comp->setAttack(v); };
            return true;
          }
          if (method == "setRelease") {
            newParamBindings[path] = [comp](float v) { comp->setRelease(v); };
            return true;
          }
          if (method == "setKnee") {
            newParamBindings[path] = [comp](float v) { comp->setKnee(v); };
            return true;
          }
          if (method == "setMakeup") {
            newParamBindings[path] = [comp](float v) { comp->setMakeup(v); };
            return true;
          }
          if (method == "setAutoMakeup") {
            newParamBindings[path] = [comp](float v) { comp->setAutoMakeup(v > 0.5f); };
            return true;
          }
          if (method == "setMode") {
            newParamBindings[path] = [comp](float v) { comp->setMode(static_cast<int>(v)); };
            return true;
          }
          if (method == "setDetectorMode") {
            newParamBindings[path] = [comp](float v) { comp->setDetectorMode(static_cast<int>(v)); };
            return true;
          }
          if (method == "setSidechainHPF") {
            newParamBindings[path] = [comp](float v) { comp->setSidechainHPF(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [comp](float v) { comp->setMix(v); };
            return true;
          }
        }

        if (auto ws = std::dynamic_pointer_cast<dsp_primitives::WaveShaperNode>(node)) {
          if (method == "setCurve") {
            newParamBindings[path] = [ws](float v) { ws->setCurve(static_cast<int>(v)); };
            return true;
          }
          if (method == "setDrive") {
            newParamBindings[path] = [ws](float v) { ws->setDrive(v); };
            return true;
          }
          if (method == "setOutput") {
            newParamBindings[path] = [ws](float v) { ws->setOutput(v); };
            return true;
          }
          if (method == "setPreFilter") {
            newParamBindings[path] = [ws](float v) { ws->setPreFilter(v); };
            return true;
          }
          if (method == "setPostFilter") {
            newParamBindings[path] = [ws](float v) { ws->setPostFilter(v); };
            return true;
          }
          if (method == "setBias") {
            newParamBindings[path] = [ws](float v) { ws->setBias(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [ws](float v) { ws->setMix(v); };
            return true;
          }
          if (method == "setOversample") {
            newParamBindings[path] = [ws](float v) { ws->setOversample(static_cast<int>(v)); };
            return true;
          }
        }

        if (auto chorus = std::dynamic_pointer_cast<dsp_primitives::ChorusNode>(node)) {
          if (method == "setRate") {
            newParamBindings[path] = [chorus](float v) { chorus->setRate(v); };
            return true;
          }
          if (method == "setDepth") {
            newParamBindings[path] = [chorus](float v) { chorus->setDepth(v); };
            return true;
          }
          if (method == "setVoices") {
            newParamBindings[path] = [chorus](float v) { chorus->setVoices(static_cast<int>(v)); };
            return true;
          }
          if (method == "setSpread") {
            newParamBindings[path] = [chorus](float v) { chorus->setSpread(v); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [chorus](float v) { chorus->setFeedback(v); };
            return true;
          }
          if (method == "setWaveform") {
            newParamBindings[path] = [chorus](float v) { chorus->setWaveform(static_cast<int>(v)); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [chorus](float v) { chorus->setMix(v); };
            return true;
          }
        }

        if (auto widener = std::dynamic_pointer_cast<dsp_primitives::StereoWidenerNode>(node)) {
          if (method == "setWidth") {
            newParamBindings[path] = [widener](float v) { widener->setWidth(v); };
            return true;
          }
          if (method == "setMonoLowFreq") {
            newParamBindings[path] = [widener](float v) { widener->setMonoLowFreq(v); };
            return true;
          }
          if (method == "setMonoLowEnable") {
            newParamBindings[path] = [widener](float v) { widener->setMonoLowEnable(v > 0.5f); };
            return true;
          }
        }

        if (auto phaser = std::dynamic_pointer_cast<dsp_primitives::PhaserNode>(node)) {
          if (method == "setRate") {
            newParamBindings[path] = [phaser](float v) { phaser->setRate(v); };
            return true;
          }
          if (method == "setDepth") {
            newParamBindings[path] = [phaser](float v) { phaser->setDepth(v); };
            return true;
          }
          if (method == "setStages") {
            newParamBindings[path] = [phaser](float v) { phaser->setStages(static_cast<int>(v)); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [phaser](float v) { phaser->setFeedback(v); };
            return true;
          }
          if (method == "setSpread") {
            newParamBindings[path] = [phaser](float v) { phaser->setSpread(v); };
            return true;
          }
        }

        if (auto gran = std::dynamic_pointer_cast<dsp_primitives::GranulatorNode>(node)) {
          if (method == "setGrainSize") {
            newParamBindings[path] = [gran](float v) { gran->setGrainSize(v); };
            return true;
          }
          if (method == "setDensity") {
            newParamBindings[path] = [gran](float v) { gran->setDensity(v); };
            return true;
          }
          if (method == "setPosition") {
            newParamBindings[path] = [gran](float v) { gran->setPosition(v); };
            return true;
          }
          if (method == "setPitch") {
            newParamBindings[path] = [gran](float v) { gran->setPitch(v); };
            return true;
          }
          if (method == "setSpray") {
            newParamBindings[path] = [gran](float v) { gran->setSpray(v); };
            return true;
          }
          if (method == "setFreeze") {
            newParamBindings[path] = [gran](float v) { gran->setFreeze(v > 0.5f); };
            return true;
          }
          if (method == "setEnvelope") {
            newParamBindings[path] = [gran](float v) { gran->setEnvelope(static_cast<int>(v)); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [gran](float v) { gran->setMix(v); };
            return true;
          }
        }

        if (auto stutter = std::dynamic_pointer_cast<dsp_primitives::StutterNode>(node)) {
          if (method == "setLength") {
            newParamBindings[path] = [stutter](float v) { stutter->setLength(v); };
            return true;
          }
          if (method == "setGate") {
            newParamBindings[path] = [stutter](float v) { stutter->setGate(v); };
            return true;
          }
          if (method == "setFilterDecay") {
            newParamBindings[path] = [stutter](float v) { stutter->setFilterDecay(v); };
            return true;
          }
          if (method == "setPitchDecay") {
            newParamBindings[path] = [stutter](float v) { stutter->setPitchDecay(v); };
            return true;
          }
          if (method == "setProbability") {
            newParamBindings[path] = [stutter](float v) { stutter->setProbability(v); };
            return true;
          }
          if (method == "setPattern") {
            newParamBindings[path] = [stutter](float v) { stutter->setPattern(v); };
            return true;
          }
          if (method == "setTempo") {
            newParamBindings[path] = [stutter](float v) { stutter->setTempo(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [stutter](float v) { stutter->setMix(v); };
            return true;
          }
        }

        if (auto shimmer = std::dynamic_pointer_cast<dsp_primitives::ShimmerNode>(node)) {
          if (method == "setSize") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setSize(v); };
            return true;
          }
          if (method == "setPitch") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setPitch(v); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setFeedback(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setMix(v); };
            return true;
          }
          if (method == "setModulation") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setModulation(v); };
            return true;
          }
          if (method == "setFilter") {
            newParamBindings[path] = [shimmer](float v) { shimmer->setFilter(v); };
            return true;
          }
        }

        if (auto multitap = std::dynamic_pointer_cast<dsp_primitives::MultitapDelayNode>(node)) {
          if (method == "setTapCount") {
            newParamBindings[path] = [multitap](float v) { multitap->setTapCount(static_cast<int>(v)); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [multitap](float v) { multitap->setFeedback(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [multitap](float v) { multitap->setMix(v); };
            return true;
          }
        }

        if (auto pitchShifter = std::dynamic_pointer_cast<dsp_primitives::PitchShifterNode>(node)) {
          if (method == "setPitch") {
            newParamBindings[path] = [pitchShifter](float v) { pitchShifter->setPitch(v); };
            return true;
          }
          if (method == "setWindow") {
            newParamBindings[path] = [pitchShifter](float v) { pitchShifter->setWindow(v); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [pitchShifter](float v) { pitchShifter->setFeedback(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [pitchShifter](float v) { pitchShifter->setMix(v); };
            return true;
          }
        }

        if (auto transient = std::dynamic_pointer_cast<dsp_primitives::TransientShaperNode>(node)) {
          if (method == "setAttack") {
            newParamBindings[path] = [transient](float v) { transient->setAttack(v); };
            return true;
          }
          if (method == "setSustain") {
            newParamBindings[path] = [transient](float v) { transient->setSustain(v); };
            return true;
          }
          if (method == "setSensitivity") {
            newParamBindings[path] = [transient](float v) { transient->setSensitivity(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [transient](float v) { transient->setMix(v); };
            return true;
          }
        }

        if (auto ringMod = std::dynamic_pointer_cast<dsp_primitives::RingModulatorNode>(node)) {
          if (method == "setFrequency") {
            newParamBindings[path] = [ringMod](float v) { ringMod->setFrequency(v); };
            return true;
          }
          if (method == "setDepth") {
            newParamBindings[path] = [ringMod](float v) { ringMod->setDepth(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [ringMod](float v) { ringMod->setMix(v); };
            return true;
          }
          if (method == "setSpread") {
            newParamBindings[path] = [ringMod](float v) { ringMod->setSpread(v); };
            return true;
          }
        }

        if (auto crusher = std::dynamic_pointer_cast<dsp_primitives::BitCrusherNode>(node)) {
          if (method == "setBits") {
            newParamBindings[path] = [crusher](float v) { crusher->setBits(v); };
            return true;
          }
          if (method == "setRateReduction") {
            newParamBindings[path] = [crusher](float v) { crusher->setRateReduction(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [crusher](float v) { crusher->setMix(v); };
            return true;
          }
          if (method == "setOutput") {
            newParamBindings[path] = [crusher](float v) { crusher->setOutput(v); };
            return true;
          }
        }

        if (auto formant = std::dynamic_pointer_cast<dsp_primitives::FormantFilterNode>(node)) {
          if (method == "setVowel") {
            newParamBindings[path] = [formant](float v) { formant->setVowel(v); };
            return true;
          }
          if (method == "setShift") {
            newParamBindings[path] = [formant](float v) { formant->setShift(v); };
            return true;
          }
          if (method == "setResonance") {
            newParamBindings[path] = [formant](float v) { formant->setResonance(v); };
            return true;
          }
          if (method == "setDrive") {
            newParamBindings[path] = [formant](float v) { formant->setDrive(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [formant](float v) { formant->setMix(v); };
            return true;
          }
        }

        if (auto reverseDelay = std::dynamic_pointer_cast<dsp_primitives::ReverseDelayNode>(node)) {
          if (method == "setTime") {
            newParamBindings[path] = [reverseDelay](float v) { reverseDelay->setTime(v); };
            return true;
          }
          if (method == "setWindow") {
            newParamBindings[path] = [reverseDelay](float v) { reverseDelay->setWindow(v); };
            return true;
          }
          if (method == "setFeedback") {
            newParamBindings[path] = [reverseDelay](float v) { reverseDelay->setFeedback(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [reverseDelay](float v) { reverseDelay->setMix(v); };
            return true;
          }
        }

        if (auto env = std::dynamic_pointer_cast<dsp_primitives::EnvelopeFollowerNode>(node)) {
          if (method == "setAttack") {
            newParamBindings[path] = [env](float v) { env->setAttack(v); };
            return true;
          }
          if (method == "setRelease") {
            newParamBindings[path] = [env](float v) { env->setRelease(v); };
            return true;
          }
          if (method == "setSensitivity") {
            newParamBindings[path] = [env](float v) { env->setSensitivity(v); };
            return true;
          }
          if (method == "setHighpass") {
            newParamBindings[path] = [env](float v) { env->setHighpass(v); };
            return true;
          }
        }

        if (auto detector = std::dynamic_pointer_cast<dsp_primitives::PitchDetectorNode>(node)) {
          if (method == "setMinFreq") {
            newParamBindings[path] = [detector](float v) { detector->setMinFreq(v); };
            return true;
          }
          if (method == "setMaxFreq") {
            newParamBindings[path] = [detector](float v) { detector->setMaxFreq(v); };
            return true;
          }
          if (method == "setSensitivity") {
            newParamBindings[path] = [detector](float v) { detector->setSensitivity(v); };
            return true;
          }
          if (method == "setSmoothing") {
            newParamBindings[path] = [detector](float v) { detector->setSmoothing(v); };
            return true;
          }
        }

        if (auto cross = std::dynamic_pointer_cast<dsp_primitives::CrossfaderNode>(node)) {
          if (method == "setPosition") {
            newParamBindings[path] = [cross](float v) { cross->setPosition(v); };
            return true;
          }
          if (method == "setCurve") {
            newParamBindings[path] = [cross](float v) { cross->setCurve(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [cross](float v) { cross->setMix(v); };
            return true;
          }
        }

        if (auto mixer = std::dynamic_pointer_cast<dsp_primitives::MixerNode>(node)) {
          if (method == "setGain1") {
            newParamBindings[path] = [mixer](float v) { mixer->setGain1(v); };
            return true;
          }
          if (method == "setGain2") {
            newParamBindings[path] = [mixer](float v) { mixer->setGain2(v); };
            return true;
          }
          if (method == "setGain3") {
            newParamBindings[path] = [mixer](float v) { mixer->setGain3(v); };
            return true;
          }
          if (method == "setGain4") {
            newParamBindings[path] = [mixer](float v) { mixer->setGain4(v); };
            return true;
          }
          if (method == "setPan1") {
            newParamBindings[path] = [mixer](float v) { mixer->setPan1(v); };
            return true;
          }
          if (method == "setPan2") {
            newParamBindings[path] = [mixer](float v) { mixer->setPan2(v); };
            return true;
          }
          if (method == "setPan3") {
            newParamBindings[path] = [mixer](float v) { mixer->setPan3(v); };
            return true;
          }
          if (method == "setPan4") {
            newParamBindings[path] = [mixer](float v) { mixer->setPan4(v); };
            return true;
          }
          if (method == "setMaster") {
            newParamBindings[path] = [mixer](float v) { mixer->setMaster(v); };
            return true;
          }
        }

        if (auto noise = std::dynamic_pointer_cast<dsp_primitives::NoiseGeneratorNode>(node)) {
          if (method == "setLevel") {
            newParamBindings[path] = [noise](float v) { noise->setLevel(v); };
            return true;
          }
          if (method == "setColor") {
            newParamBindings[path] = [noise](float v) { noise->setColor(v); };
            return true;
          }
        }

        if (auto msEnc = std::dynamic_pointer_cast<dsp_primitives::MSEncoderNode>(node)) {
          if (method == "setWidth") {
            newParamBindings[path] = [msEnc](float v) { msEnc->setWidth(v); };
            return true;
          }
        }

        if (auto eq = std::dynamic_pointer_cast<dsp_primitives::EQNode>(node)) {
          if (method == "setLowGain") {
            newParamBindings[path] = [eq](float v) { eq->setLowGain(v); };
            return true;
          }
          if (method == "setLowFreq") {
            newParamBindings[path] = [eq](float v) { eq->setLowFreq(v); };
            return true;
          }
          if (method == "setMidGain") {
            newParamBindings[path] = [eq](float v) { eq->setMidGain(v); };
            return true;
          }
          if (method == "setMidFreq") {
            newParamBindings[path] = [eq](float v) { eq->setMidFreq(v); };
            return true;
          }
          if (method == "setMidQ") {
            newParamBindings[path] = [eq](float v) { eq->setMidQ(v); };
            return true;
          }
          if (method == "setHighGain") {
            newParamBindings[path] = [eq](float v) { eq->setHighGain(v); };
            return true;
          }
          if (method == "setHighFreq") {
            newParamBindings[path] = [eq](float v) { eq->setHighFreq(v); };
            return true;
          }
          if (method == "setOutput") {
            newParamBindings[path] = [eq](float v) { eq->setOutput(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [eq](float v) { eq->setMix(v); };
            return true;
          }
        }

        if (auto limiter = std::dynamic_pointer_cast<dsp_primitives::LimiterNode>(node)) {
          if (method == "setThreshold") {
            newParamBindings[path] = [limiter](float v) { limiter->setThreshold(v); };
            return true;
          }
          if (method == "setRelease") {
            newParamBindings[path] = [limiter](float v) { limiter->setRelease(v); };
            return true;
          }
          if (method == "setMakeup") {
            newParamBindings[path] = [limiter](float v) { limiter->setMakeup(v); };
            return true;
          }
          if (method == "setSoftClip") {
            newParamBindings[path] = [limiter](float v) { limiter->setSoftClip(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [limiter](float v) { limiter->setMix(v); };
            return true;
          }
        }

        if (auto spectrum = std::dynamic_pointer_cast<dsp_primitives::SpectrumAnalyzerNode>(node)) {
          if (method == "setSensitivity") {
            newParamBindings[path] = [spectrum](float v) { spectrum->setSensitivity(v); };
            return true;
          }
          if (method == "setSmoothing") {
            newParamBindings[path] = [spectrum](float v) { spectrum->setSmoothing(v); };
            return true;
          }
          if (method == "setFloor") {
            newParamBindings[path] = [spectrum](float v) { spectrum->setFloor(v); };
            return true;
          }
        }

        if (nodeObj.is<sol::table>()) {
          sol::table target = nodeObj.as<sol::table>();
          sol::object methodObj = target[method];
          if (methodObj.valid() && methodObj.get_type() == sol::type::function) {
            sol::protected_function fn = methodObj;
            newParamBindings[path] = [fn, target](float v) mutable {
              sol::protected_function_result result = fn(target, v);
              (void)result;
            };
            return true;
          }
        }

        return false;
      };

  auto bundles = newLua.create_table();
  {
    auto loopLayerApi = newLua.create_table();
    loopLayerApi["new"] = [graph, &newLua, &newLayerPlaybackNodes, &newLayerGateNodes, &newLayerOutputNodes, &newNamedNodes, &mapInternalToExternal, &trackNode](sol::optional<sol::table> options) {
      int numChannels = 2;
      if (options.has_value()) {
        sol::table opts = options.value();
        if (opts["channels"].valid()) {
          numChannels = juce::jlimit(1, 8, opts["channels"].get<int>());
        }
      }

      auto input = std::make_shared<dsp_primitives::PassthroughNode>(
          numChannels,
          dsp_primitives::PassthroughNode::HostInputMode::MonitorControlled);
      auto capture = std::make_shared<dsp_primitives::RetrospectiveCaptureNode>(numChannels);
      auto playback = std::make_shared<dsp_primitives::LoopPlaybackNode>(numChannels);
      auto gate = std::make_shared<dsp_primitives::PlaybackStateGateNode>(numChannels);
      auto gain = std::make_shared<dsp_primitives::GainNode>(numChannels);
      auto recordState = std::make_shared<dsp_primitives::RecordStateNode>();
      auto quantizer = std::make_shared<dsp_primitives::QuantizerNode>();
      auto mode = std::make_shared<dsp_primitives::RecordModePolicyNode>();
      auto forward = std::make_shared<dsp_primitives::ForwardCommitSchedulerNode>();
      auto transport = std::make_shared<dsp_primitives::TransportStateNode>();

      newLayerPlaybackNodes.push_back(playback);
      newLayerGateNodes.push_back(gate);
      newLayerOutputNodes.push_back(gain);

      const int layerIndex = static_cast<int>(newLayerOutputNodes.size()) - 1;
      const std::string layerBase =
          "/core/behavior/layer/" + std::to_string(layerIndex);
      auto registerNamedNode = [&newNamedNodes, &mapInternalToExternal](
                                   const std::string &internalPath,
                                   const std::shared_ptr<dsp_primitives::IPrimitiveNode> &node) {
        if (!node) {
          return;
        }
        newNamedNodes[mapInternalToExternal(internalPath)] = node;
      };
      registerNamedNode(layerBase + "/input", input);
      registerNamedNode(layerBase + "/output", gain);
      registerNamedNode(layerBase + "/parts/input", input);
      registerNamedNode(layerBase + "/parts/output", gain);
      registerNamedNode(layerBase + "/parts/capture", capture);
      registerNamedNode(layerBase + "/parts/playback", playback);
      registerNamedNode(layerBase + "/parts/gate", gate);
      registerNamedNode(layerBase + "/parts/gain", gain);

      // Default to silent/idle loop layer until explicitly played/committed.
      playback->stop();
      gate->stop();
      transport->stop();

      trackNode(input);
      trackNode(capture);
      trackNode(playback);
      trackNode(gate);
      trackNode(gain);
      trackNode(recordState);
      trackNode(quantizer);
      trackNode(mode);
      trackNode(forward);
      trackNode(transport);

      graph->setNodeRole(input, dsp_primitives::PrimitiveGraph::NodeRole::InputDSP);
      graph->setNodeRole(capture, dsp_primitives::PrimitiveGraph::NodeRole::InputDSP);
      graph->setNodeRole(playback, dsp_primitives::PrimitiveGraph::NodeRole::OutputDSP);
      graph->setNodeRole(gate, dsp_primitives::PrimitiveGraph::NodeRole::OutputDSP);
      graph->setNodeRole(gain, dsp_primitives::PrimitiveGraph::NodeRole::OutputDSP);

      graph->connect(input, 0, capture, 0);
      graph->connect(capture, 0, playback, 0);
      graph->connect(playback, 0, gate, 0);
      graph->connect(gate, 0, gain, 0);

      auto layer = newLua.create_table();
      layer["__node"] = gain;
      layer["__inputNode"] = input;
      layer["__outputNode"] = gain;
      layer["__capture"] = newLua.create_table_with("__node", capture);
      layer["__playback"] = newLua.create_table_with("__node", playback);
      layer["__gate"] = newLua.create_table_with("__node", gate);
      layer["__gain"] = newLua.create_table_with("__node", gain);
      layer["__record"] = newLua.create_table_with("__node", recordState);
      layer["__quantizer"] = newLua.create_table_with("__node", quantizer);
      layer["__mode"] = newLua.create_table_with("__node", mode);
      layer["__forward"] = newLua.create_table_with("__node", forward);
      layer["__transport"] = newLua.create_table_with("__node", transport);
      layer["__overdubLengthPolicy"] = 0;

      layer["setVolume"] = [](sol::table self, float v) {
        if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
          n->setGain(v);
        }
      };
      layer["getVolume"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::GainNode>(self)) {
          return n->getGain();
        }
        return 0.0f;
      };
      layer["setMuted"] = [](sol::table self, bool v) {
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->setMuted(v);
        }
      };
      layer["isMuted"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          return n->isMuted();
        }
        return false;
      };
      layer["setPlaying"] = [](sol::table self, bool v) {
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->setPlaying(v);
        }
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          if (v) {
            n->play();
          } else {
            n->pause();
          }
        }
        if (auto n = tableNode<dsp_primitives::TransportStateNode>(self["__transport"])) {
          if (v) {
            n->play();
          } else {
            n->pause();
          }
        }
      };
      layer["isPlaying"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          return n->isPlaying();
        }
        return false;
      };
      layer["setSpeed"] = [](sol::table self, float v) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->setSpeed(v);
        }
      };
      layer["setReversed"] = [](sol::table self, bool v) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->setReversed(v);
        }
      };
      layer["play"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->play();
        }
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->play();
        }
        if (auto n = tableNode<dsp_primitives::TransportStateNode>(self["__transport"])) {
          n->play();
        }
      };
      layer["pause"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->pause();
        }
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->pause();
        }
        if (auto n = tableNode<dsp_primitives::TransportStateNode>(self["__transport"])) {
          n->pause();
        }
      };
      layer["stop"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->stop();
        }
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->stop();
        }
        if (auto n = tableNode<dsp_primitives::TransportStateNode>(self["__transport"])) {
          n->stop();
        }
      };
      layer["setLoopLength"] = [](sol::table self, int v) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->setLoopLength(v);
        }
      };
      layer["seek"] = [](sol::table self, float v) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->seekNormalized(v);
        }
      };
      layer["getNormalizedPosition"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          return n->getNormalizedPosition();
        }
        return 0.0f;
      };
      layer["clearLoop"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"])) {
          n->clearLoop();
        }
      };
      layer["setTempo"] = [](sol::table self, float v) {
        if (auto n = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"])) {
          n->setTempo(v);
        }
      };
      layer["getTempo"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"])) {
          return n->getTempo();
        }
        return 120.0f;
      };
      layer["getSamplesPerBar"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"])) {
          return n->getSamplesPerBar();
        }
        return 0.0f;
      };
      layer["quantizeToNearestLegal"] = [](sol::table self, int samples) {
        if (auto n = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"])) {
          return n->quantizeToNearestLegal(samples);
        }
        return samples;
      };
      layer["setMode"] = [](sol::table self, int v) {
        if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self["__mode"])) {
          n->setMode(v);
        }
      };
      layer["getMode"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::RecordModePolicyNode>(self["__mode"])) {
          return n->getMode();
        }
        return 0;
      };
      layer["setOverdub"] = [](sol::table self, bool v) {
        if (auto n = tableNode<dsp_primitives::RecordStateNode>(self["__record"])) {
          n->setOverdub(v);
        }
      };
      layer["isOverdub"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::RecordStateNode>(self["__record"])) {
          return n->isOverdub();
        }
        return false;
      };
      layer["startRecording"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::RecordStateNode>(self["__record"])) {
          n->startRecording();
        }
      };
      layer["stopRecording"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::RecordStateNode>(self["__record"])) {
          n->stopRecording();
        }
      };
      layer["isRecording"] = [](sol::table self) {
        if (auto n = tableNode<dsp_primitives::RecordStateNode>(self["__record"])) {
          return n->isRecording();
        }
        return false;
      };
      layer["setCaptureSeconds"] = [](sol::table self, float v) {
        if (auto n = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self["__capture"])) {
          n->setCaptureSeconds(v);
        }
      };
      layer["setOverdubLengthPolicy"] = [](sol::table self, int v) {
        self["__overdubLengthPolicy"] = juce::jlimit(0, 1, v);
      };
      layer["getOverdubLengthPolicy"] = [](sol::table self) {
        sol::object policyObj = self["__overdubLengthPolicy"];
        if (policyObj.valid() && policyObj.is<int>()) {
          return juce::jlimit(0, 1, policyObj.as<int>());
        }
        return 0;
      };
      layer["commit"] = [](sol::table self, sol::optional<float> barsOpt,
                              sol::optional<int> overdubLengthPolicyOpt) {
        auto captureNode = tableNode<dsp_primitives::RetrospectiveCaptureNode>(self["__capture"]);
        auto playbackNode = tableNode<dsp_primitives::LoopPlaybackNode>(self["__playback"]);
        auto quantNode = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"]);
        auto recordNode = tableNode<dsp_primitives::RecordStateNode>(self["__record"]);
        if (!captureNode || !playbackNode || !quantNode) {
          return false;
        }

        float bars = barsOpt.value_or(1.0f);
        bars = juce::jmax(0.001f, bars);
        const float samplesPerBar = quantNode->getSamplesPerBar();
        if (samplesPerBar <= 0.0f) {
          return false;
        }

        int samplesBack = static_cast<int>(std::round(bars * samplesPerBar));
        if (samplesBack <= 0) {
          return false;
        }

        int policyValue = 0;
        if (overdubLengthPolicyOpt.has_value()) {
          policyValue = juce::jlimit(0, 1, overdubLengthPolicyOpt.value());
        } else {
          sol::object policyObj = self["__overdubLengthPolicy"];
          if (policyObj.valid() && policyObj.is<int>()) {
            policyValue = juce::jlimit(0, 1, policyObj.as<int>());
          }
        }

        const auto overdubLengthPolicy =
            policyValue == 1
                ? dsp_primitives::LoopPlaybackNode::OverdubLengthPolicy::CommitLengthWins
                : dsp_primitives::LoopPlaybackNode::OverdubLengthPolicy::LegacyRepeat;

        const bool overdub = recordNode ? recordNode->isOverdub() : false;
        const bool copied = captureNode->copyRecentToLoop(playbackNode, samplesBack, overdub,
                                                          overdubLengthPolicy);
        if (!copied) {
          return false;
        }

        playbackNode->play();
        if (auto n = tableNode<dsp_primitives::PlaybackStateGateNode>(self["__gate"])) {
          n->play();
        }
        return true;
      };
      layer["forwardCommit"] = [](sol::table self, float bars, double currentSamples) {
        auto forwardNode = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self["__forward"]);
        auto quantNode = tableNode<dsp_primitives::QuantizerNode>(self["__quantizer"]);
        if (!forwardNode || !quantNode) {
          return false;
        }
        const float spb = quantNode->getSamplesPerBar();
        if (spb <= 0.0f) {
          return false;
        }
        forwardNode->arm(bars, 0, currentSamples, spb);
        return true;
      };
      layer["tickForwardCommit"] = [](sol::table self, double currentSamples) {
        auto forwardNode = tableNode<dsp_primitives::ForwardCommitSchedulerNode>(self["__forward"]);
        if (!forwardNode) {
          return false;
        }
        if (!forwardNode->shouldFire(currentSamples)) {
          return false;
        }
        const float bars = forwardNode->getBars();
        sol::object commitObj = self["commit"];
        if (!commitObj.valid() || commitObj.get_type() != sol::type::function) {
          return false;
        }
        sol::protected_function commitFn = commitObj;
        sol::protected_function_result result = commitFn(self, bars);
        if (!result.valid()) {
          return false;
        }
        if (!result.get<sol::object>().is<bool>()) {
          return false;
        }
        return result.get<bool>();
      };
      layer["parts"] = newLua.create_table_with(
          "input", newLua.create_table_with("__node", input),
          "capture", newLua.create_table_with("__node", capture),
          "record", newLua.create_table_with("__node", recordState),
          "quantizer", newLua.create_table_with("__node", quantizer),
          "mode", newLua.create_table_with("__node", mode),
          "forward", newLua.create_table_with("__node", forward),
          "transport", newLua.create_table_with("__node", transport),
          "gain", newLua.create_table_with("__node", gain),
          "gate", newLua.create_table_with("__node", gate),
          "playback", newLua.create_table_with("__node", playback));

      return layer;
    };
    bundles["LoopLayer"] = loopLayerApi;
  }

  auto hostApi = newLua.create_table();
  hostApi["getSampleRate"] = [impl]() {
    return impl->processor ? impl->processor->getSampleRate() : 44100.0;
  };
  hostApi["getPlayTimeSamples"] = [impl]() {
    return impl->processor ? impl->processor->getPlayTimeSamples() : 0.0;
  };
  hostApi["setParam"] = [impl, mapInternalToExternal](const std::string &path,
                                                        float value) {
    if (!impl->processor) {
      return false;
    }
    const std::string externalPath = mapInternalToExternal(path);
    return impl->processor->setParamByPath(externalPath, value);
  };
  hostApi["getParam"] = [impl, mapInternalToExternal](const std::string &path) {
    if (!impl->processor) {
      return 0.0f;
    }
    const std::string externalPath = mapInternalToExternal(path);
    return impl->processor->getParamByPath(externalPath);
  };
  hostApi["getGraphNodeByPath"] = [impl](const std::string &path)
      -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
    if (!impl->processor) {
      return {};
    }
    return impl->processor->getGraphNodeByPath(path);
  };

  auto ctx = newLua.create_table();
  ctx["primitives"] = primitives;
  ctx["bundles"] = bundles;
  ctx["graph"] = graphTable;
  ctx["params"] = paramsTable;
  ctx["host"] = hostApi;

  newLua["getLoopPlaybackPeaks"] = [](sol::this_state ts, std::shared_ptr<dsp_primitives::LoopPlaybackNode> node, int numBuckets) -> sol::table {
    sol::state_view lua(ts);
    sol::table result(lua, sol::create);
    if (!node || numBuckets <= 0) return result;
    std::vector<float> peaks;
    if (node->computePeaks(numBuckets, peaks)) {
      for (size_t i = 0; i < peaks.size(); ++i) {
        result[i + 1] = peaks[i];
      }
    }
    return result;
  };

  newLua["connectNodes"] = [graph, toPrimitiveNode](const sol::object &fromObj,
                                                      const sol::object &toObj) {
    auto from = toPrimitiveNode(fromObj);
    auto to = toPrimitiveNode(toObj);
    if (!from || !to) {
      return false;
    }
    return graph->connect(from, 0, to, 0);
  };

  {
    const auto scriptDir = scriptFile != nullptr
                               ? scriptFile->getParentDirectory()
                               : juce::File();
    auto& settings = Settings::getInstance();
    juce::File userDspRoot(settings.getUserScriptsDir());
    if (userDspRoot.isDirectory()) {
      userDspRoot = userDspRoot.getChildFile("dsp");
    }
    juce::File systemDspRoot(settings.getDspScriptsDir());

    std::string packagePath;
    auto appendPackageRoot = [&packagePath](const juce::File& root) {
      if (!root.isDirectory()) {
        return;
      }
      const auto base = root.getFullPathName().toStdString();
      if (!packagePath.empty()) {
        packagePath += ";";
      }
      packagePath += base + "/?.lua;" + base + "/?/init.lua";
    };

    appendPackageRoot(scriptDir);
    appendPackageRoot(userDspRoot);
    appendPackageRoot(systemDspRoot);
    newLua["package"]["path"] = packagePath;

    newLua["__manifoldDspScriptDir"] = scriptDir.getFullPathName().toStdString();
    newLua["__manifoldUserDspRoot"] = userDspRoot.getFullPathName().toStdString();
    newLua["__manifoldSystemDspRoot"] = systemDspRoot.getFullPathName().toStdString();

    sol::protected_function_result helperInit = newLua.script(R"lua(
__manifoldDspModuleCache = __manifoldDspModuleCache or {}

local function __dirname(path)
  return (tostring(path or ""):gsub("/+$", ""):match("^(.*)/[^/]+$") or ".")
end

local function __join(...)
  local parts = { ... }
  local out = ""
  for i = 1, #parts do
    local part = tostring(parts[i] or "")
    if part ~= "" then
      if out == "" then
        out = part
      else
        out = out:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
      end
    end
  end
  return out
end

local function __isAbsolutePath(path)
  path = tostring(path or "")
  return path:match("^/") ~= nil or path:match("^[A-Za-z]:[/\\]") ~= nil
end

local function __resolveDspPath(ref, baseDir)
  if type(ref) ~= "string" or ref == "" then
    error("DSP module ref must be a non-empty string")
  end

  if __isAbsolutePath(ref) then
    return ref
  end

  if ref:sub(1, 7) == "system:" then
    return __join(__manifoldSystemDspRoot or "", ref:sub(8))
  end
  if ref:sub(1, 5) == "user:" then
    return __join(__manifoldUserDspRoot or "", ref:sub(6))
  end
  if ref:sub(1, 8) == "project:" then
    return __join(baseDir or __manifoldDspScriptDir or "", ref:sub(9))
  end
  return __join(baseDir or __manifoldDspScriptDir or "", ref)
end

function resolveDspPath(ref)
  return __resolveDspPath(ref, __manifoldDspScriptDir)
end

function __manifoldLoadDspModule(ref, baseDir)
  local path = __resolveDspPath(ref, baseDir or __manifoldDspScriptDir)
  local cached = __manifoldDspModuleCache[path]
  if cached ~= nil then
    return cached
  end

  local env = {
    __dspModulePath = path,
    __dspModuleDir = __dirname(path),
  }
  env.resolveDspPath = function(childRef)
    return __resolveDspPath(childRef, env.__dspModuleDir)
  end
  env.loadDspModule = function(childRef)
    return __manifoldLoadDspModule(childRef, env.__dspModuleDir)
  end
  setmetatable(env, { __index = _G })

  local chunk, err = loadfile(path, "t", env)
  if not chunk then
    error("failed to load DSP module '" .. tostring(ref) .. "' (" .. tostring(path) .. "): " .. tostring(err))
  end

  local result = chunk()
  local module = result
  if module == nil then
    module = rawget(env, "M")
    if module == nil then
      module = env
    end
  end

  __manifoldDspModuleCache[path] = module
  return module
end

function loadDspModule(ref)
  return __manifoldLoadDspModule(ref, __manifoldDspScriptDir)
end
)lua");
    if (!helperInit.valid()) {
      sol::error err = helperInit;
      impl->lastError = err.what();
      return false;
    }

    auto pathsTable = newLua.create_table();
    pathsTable["scriptDir"] = scriptDir.getFullPathName().toStdString();
    pathsTable["userDspRoot"] = userDspRoot.getFullPathName().toStdString();
    pathsTable["systemDspRoot"] = systemDspRoot.getFullPathName().toStdString();
    ctx["paths"] = pathsTable;
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
  if (pluginTable["process"].valid() &&
      pluginTable["process"].get_type() == sol::type::function) {
    newProcess = pluginTable["process"];
  }

  for (const auto &entry : newParamValues) {
    const auto bindingIt = newParamBindings.find(entry.first);
    if (bindingIt != newParamBindings.end()) {
      bindingIt->second(entry.second);
    }

    if (newOnParamChange.valid()) {
      std::string internalPath = entry.first;
      const auto mapIt = newExternalToInternalPath.find(entry.first);
      if (mapIt != newExternalToInternalPath.end()) {
        internalPath = mapIt->second;
      }

      sol::protected_function_result applyResult =
          newOnParamChange(internalPath, entry.second);
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

bool DSPPluginScriptHost::hasParam(const std::string &path) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (pImpl->paramSpecs.find(path) != pImpl->paramSpecs.end()) {
    return true;
  }

  // Synthetic per-slot layer telemetry endpoints.
  if (pImpl->namespaceBase != "/core/behavior") {
    const juce::String p = sanitizePath(path);
    const juce::String prefix = juce::String(pImpl->namespaceBase) + "/layer/";
    if (p.startsWith(prefix)) {
      const juce::String rest = p.substring(prefix.length());
      const int slash = rest.indexOfChar('/');
      if (slash > 0) {
        const juce::String suffix = rest.substring(slash + 1);
        if (suffix == "length" || suffix == "position" || suffix == "state") {
          return true;
        }
      }
    }
  }

  return false;
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
    std::string internalPath = path;
    const auto mapIt = pImpl->externalToInternalPath.find(path);
    if (mapIt != pImpl->externalToInternalPath.end()) {
      internalPath = mapIt->second;
    }

    sol::protected_function_result result = pImpl->onParamChange(internalPath, normalized);
    if (!result.valid()) {
      sol::error err = result;
      pImpl->lastError = "onParamChange failed: " + std::string(err.what());
      return false;
    }
  }

  if (pImpl->processor) {
    const juce::String paramPath(path);
    const bool isRegisteredCustom =
        std::find(pImpl->registeredEndpoints.begin(),
                  pImpl->registeredEndpoints.end(),
                  paramPath) != pImpl->registeredEndpoints.end();
    if (isRegisteredCustom) {
      pImpl->processor->getOSCServer().setCustomValue(paramPath,
                                                      {juce::var(normalized)});
    }
  }

  return true;
}

float DSPPluginScriptHost::getParam(const std::string &path) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  const auto it = pImpl->paramValues.find(path);
  if (it != pImpl->paramValues.end()) {
    return it->second;
  }

  // Synthetic per-slot layer telemetry endpoints.
  if (pImpl->namespaceBase != "/core/behavior") {
    const juce::String p = sanitizePath(path);
    const juce::String prefix = juce::String(pImpl->namespaceBase) + "/layer/";
    if (p.startsWith(prefix)) {
      const juce::String rest = p.substring(prefix.length());
      const int slash = rest.indexOfChar('/');
      if (slash > 0) {
        const int idx = rest.substring(0, slash).getIntValue();
        const juce::String suffix = rest.substring(slash + 1);
        if (idx >= 0 && idx < static_cast<int>(pImpl->layerPlaybackNodes.size())) {
          auto playback = pImpl->layerPlaybackNodes[static_cast<size_t>(idx)].lock();
          if (playback) {
            if (suffix == "length") {
              return static_cast<float>(juce::jmax(0, playback->getLoopLength()));
            }
            if (suffix == "position") {
              return playback->getNormalizedPosition();
            }
            if (suffix == "state") {
              return playback->isPlaying() ? 1.0f : 0.0f;
            }
          }
        }
      }
    }
  }

  return 0.0f;
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

int DSPPluginScriptHost::getLayerLoopLength(int layerIndex) const {
  if (layerIndex < 0) {
    return 0;
  }

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (layerIndex >= static_cast<int>(pImpl->layerPlaybackNodes.size())) {
    return 0;
  }

  auto playback = pImpl->layerPlaybackNodes[static_cast<size_t>(layerIndex)].lock();
  if (!playback) {
    return 0;
  }

  return juce::jmax(0, playback->getLoopLength());
}

bool DSPPluginScriptHost::isLayerMuted(int layerIndex) const {
  if (layerIndex < 0) {
    return false;
  }

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (layerIndex >= static_cast<int>(pImpl->layerGateNodes.size())) {
    return false;
  }

  auto gate = pImpl->layerGateNodes[static_cast<size_t>(layerIndex)].lock();
  if (!gate) {
    return false;
  }

  return gate->isMuted();
}

bool DSPPluginScriptHost::computeLayerPeaks(int layerIndex, int numBuckets,
                                            std::vector<float> &outPeaks) const {
  outPeaks.clear();
  if (layerIndex < 0 || numBuckets <= 0) {
    return false;
  }

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (layerIndex >= static_cast<int>(pImpl->layerPlaybackNodes.size())) {
    return false;
  }

  auto playback = pImpl->layerPlaybackNodes[static_cast<size_t>(layerIndex)].lock();
  if (!playback) {
    return false;
  }

  return playback->computePeaks(numBuckets, outPeaks);
}

bool DSPPluginScriptHost::computeSynthSamplePeaks(int numBuckets,
                                                  std::vector<float> &outPeaks) const {
  outPeaks.clear();
  if (numBuckets <= 0) {
    return false;
  }

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object getPeaksFn = pImpl->pluginTable["getSamplePeaks"];
  if (!getPeaksFn.valid() || getPeaksFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result = getPeaksFn.as<sol::function>()(numBuckets);
  if (!result.valid()) {
    return false;
  }

  sol::object peaksObj = result.get<sol::object>();
  if (!peaksObj.valid() || peaksObj.get_type() != sol::type::table) {
    return false;
  }

  sol::table peaksTable = peaksObj.as<sol::table>();
  for (int i = 1; i <= numBuckets; ++i) {
    sol::object val = peaksTable[i];
    if (val.valid() && val.is<float>()) {
      outPeaks.push_back(val.as<float>());
    } else if (val.valid() && val.is<double>()) {
      outPeaks.push_back(static_cast<float>(val.as<double>()));
    } else if (val.valid() && val.is<int>()) {
      outPeaks.push_back(static_cast<float>(val.as<int>()));
    } else {
      outPeaks.push_back(0.0f);
    }
  }

  return true;
}

std::vector<float>
DSPPluginScriptHost::getVoiceSamplePositions() const {
  std::vector<float> positions;

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (!pImpl->pluginTable.valid()) {
    return positions;
  }

  sol::object getPosFn = pImpl->pluginTable["getVoiceSamplePositions"];
  if (!getPosFn.valid() || getPosFn.get_type() != sol::type::function) {
    return positions;
  }

  sol::protected_function_result result = getPosFn.as<sol::function>()();
  if (!result.valid()) {
    return positions;
  }

  sol::object posObj = result.get<sol::object>();
  if (!posObj.valid() || posObj.get_type() != sol::type::table) {
    return positions;
  }

  sol::table posTable = posObj.as<sol::table>();
  for (size_t i = 1; i <= posTable.size(); ++i) {
    positions.push_back(posTable[i].get_or(0.0f));
  }

  return positions;
}

std::shared_ptr<dsp_primitives::IPrimitiveNode>
DSPPluginScriptHost::getGraphNodeByPath(const std::string &path) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  const auto it = pImpl->namedNodes.find(sanitizePath(path).toStdString());
  if (it == pImpl->namedNodes.end()) {
    return {};
  }

  auto node = it->second.lock();
  if (!node) {
    return {};
  }

  return node;
}

std::shared_ptr<dsp_primitives::IPrimitiveNode>
DSPPluginScriptHost::getLayerOutputNode(int layerIndex) const {
  if (layerIndex < 0) {
    return {};
  }
  return getGraphNodeByPath("/core/behavior/layer/" +
                            std::to_string(layerIndex) + "/output");
}

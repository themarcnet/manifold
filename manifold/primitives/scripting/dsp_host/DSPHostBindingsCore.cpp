#include "DSPHostInternal.h"

#include "../PrimitiveGraph.h"
#include "dsp/core/nodes/PrimitiveNodes.h"

namespace {

sol::table getOrCreateContextTable(sol::table &ctx,
                                   const char *key,
                                   lua_State *luaState) {
  sol::object obj = ctx[key];
  if (obj.valid() && obj.get_type() == sol::type::table) {
    return obj.as<sol::table>();
  }

  sol::table table = sol::state_view(luaState).create_table();
  ctx[key] = table;
  return table;
}

} // namespace

namespace dsp_host {

void registerCoreBindings(LoadSession &session,
                          PrimitiveGraphPtr graph,
                          sol::table &ctx,
                          const TrackNodeFn &trackNode,
                          const PathMapperFn &mapInternalToExternal) {
  auto &newLua = session.lua;
  lua_State *newLuaState = session.luaState;
  auto &newNamedNodes = session.namedNodes;
  sol::table primitives = getOrCreateContextTable(ctx, "primitives", newLuaState);

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
      "getPeaks", [newLuaState](std::shared_ptr<dsp_primitives::LoopPlaybackNode>& self, int numBuckets) -> sol::table {
        sol::table result = sol::state_view(newLuaState).create_table();
        if (self) {
          std::vector<float> peaks;
          bool ok = self->computePeaks(numBuckets, peaks);
          if (ok && !peaks.empty()) {
            for (size_t i = 0; i < peaks.size(); ++i) {
              result[i + 1] = peaks[i];  // Lua is 1-indexed
            }
          }
        }
        return result;
      });

  newLua.new_usertype<dsp_primitives::SampleRegionPlaybackNode>(
      "SampleRegionPlaybackNode",
      sol::constructors<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>(int)>(),
      "setLoopLength", &dsp_primitives::SampleRegionPlaybackNode::setLoopLength,
      "getLoopLength", &dsp_primitives::SampleRegionPlaybackNode::getLoopLength,
      "setSpeed", &dsp_primitives::SampleRegionPlaybackNode::setSpeed,
      "getSpeed", &dsp_primitives::SampleRegionPlaybackNode::getSpeed,
      "play", &dsp_primitives::SampleRegionPlaybackNode::play,
      "pause", &dsp_primitives::SampleRegionPlaybackNode::pause,
      "stop", &dsp_primitives::SampleRegionPlaybackNode::stop,
      "trigger", &dsp_primitives::SampleRegionPlaybackNode::trigger,
      "isPlaying", &dsp_primitives::SampleRegionPlaybackNode::isPlaying,
      "seek", &dsp_primitives::SampleRegionPlaybackNode::seekNormalized,
      "getNormalizedPosition", &dsp_primitives::SampleRegionPlaybackNode::getNormalizedPosition,
      "setPlayStart", &dsp_primitives::SampleRegionPlaybackNode::setPlayStart,
      "getPlayStart", &dsp_primitives::SampleRegionPlaybackNode::getPlayStart,
      "setLoopStart", &dsp_primitives::SampleRegionPlaybackNode::setLoopStart,
      "getLoopStart", &dsp_primitives::SampleRegionPlaybackNode::getLoopStart,
      "setLoopEnd", &dsp_primitives::SampleRegionPlaybackNode::setLoopEnd,
      "getLoopEnd", &dsp_primitives::SampleRegionPlaybackNode::getLoopEnd,
      "setCrossfade", &dsp_primitives::SampleRegionPlaybackNode::setCrossfade,
      "getCrossfade", &dsp_primitives::SampleRegionPlaybackNode::getCrossfade,
      "setUnison", &dsp_primitives::SampleRegionPlaybackNode::setUnison,
      "getUnison", &dsp_primitives::SampleRegionPlaybackNode::getUnison,
      "setDetune", &dsp_primitives::SampleRegionPlaybackNode::setDetune,
      "getDetune", &dsp_primitives::SampleRegionPlaybackNode::getDetune,
      "setSpread", &dsp_primitives::SampleRegionPlaybackNode::setSpread,
      "getSpread", &dsp_primitives::SampleRegionPlaybackNode::getSpread,
      "analyzeRootKey", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return sampleAnalysisToLua(ts, self->analyzeSample());
      },
      "analyzeSample", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return sampleAnalysisToLua(ts, self->analyzeSample());
      },
      "getLastAnalysis", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return sampleAnalysisToLua(ts, self->getLastAnalysis());
      },
      "extractPartials", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return partialDataToLua(ts, self->extractPartials());
      },
      "getLastPartials", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return partialDataToLua(ts, self->getLastPartials());
      },
      "getLastTemporalPartials", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return temporalPartialDataToLua(ts, self->getLastTemporalPartials());
      },
      "hasTemporalPartials", [](std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> bool {
        return self ? self->hasTemporalPartials() : false;
      },
      "getTemporalFrameCount", [](std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self) -> int {
        return self ? self->getTemporalFrameCount() : 0;
      },
      "getTemporalFrameAtPosition", [](sol::this_state ts,
                                         std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self,
                                         float pos,
                                         sol::optional<float> smoothAmount,
                                         sol::optional<float> contrastAmount) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return partialDataToLua(ts,
                                self->getTemporalFrameAtPosition(pos,
                                                                 smoothAmount.value_or(0.0f),
                                                                 contrastAmount.value_or(0.5f)));
      },
      "requestAsyncAnalysis", [](std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self,
                                   sol::optional<int> maxPartials,
                                   sol::optional<int> windowSize,
                                   sol::optional<int> hopSize,
                                   sol::optional<int> maxFrames) {
        if (self) {
          self->requestAsyncAnalysis(maxPartials.value_or(dsp_primitives::PartialData::kMaxPartials),
                                     windowSize.value_or(2048),
                                     hopSize.value_or(1024),
                                     maxFrames.value_or(128));
        }
      },
      "isAsyncAnalysisPending", &dsp_primitives::SampleRegionPlaybackNode::isAsyncAnalysisPending,
      "getPeaks", [newLuaState](std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& self, int numBuckets) -> sol::table {
        sol::table result = sol::state_view(newLuaState).create_table();
        if (self) {
          std::vector<float> peaks;
          bool ok = self->computePeaks(numBuckets, peaks);
          if (ok && !peaks.empty()) {
            for (size_t i = 0; i < peaks.size(); ++i) {
              result[i + 1] = peaks[i];
            }
          }
        }
        return result;
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
      sol::overload(
          static_cast<bool (dsp_primitives::RetrospectiveCaptureNode::*)(
              const std::shared_ptr<dsp_primitives::LoopPlaybackNode>&, int, bool)>(
              &dsp_primitives::RetrospectiveCaptureNode::copyRecentToLoop),
          static_cast<bool (dsp_primitives::RetrospectiveCaptureNode::*)(
              const std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>&, int, bool)>(
              &dsp_primitives::RetrospectiveCaptureNode::copyRecentToLoop)));

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

  {
    auto playheadApi = sol::state_view(newLuaState).create_table();
    playheadApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::PlayheadNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto passthroughApi = sol::state_view(newLuaState).create_table();
    // PassthroughNode.new(numChannels [, mode])
    // mode: 0 = MonitorControlled (default, always-on input-dsp source)
    //       1 = RawCapture (monitor-toggle source)
    passthroughApi["new"] = [graph, newLuaState, trackNode](int numChannels, sol::optional<int> mode) {
        using Mode = dsp_primitives::PassthroughNode::HostInputMode;
        const Mode hostMode = (mode.has_value() && mode.value() == 1)
                                  ? Mode::RawCapture
                                  : Mode::MonitorControlled;
        auto node = std::make_shared<dsp_primitives::PassthroughNode>(numChannels, hostMode);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        return t;
      };
    primitives["PassthroughNode"] = passthroughApi;
  }
  {
    auto gainApi = sol::state_view(newLuaState).create_table();
    gainApi["new"] = [graph, newLuaState, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::GainNode>(numChannels);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto loopPlaybackApi = sol::state_view(newLuaState).create_table();
    loopPlaybackApi["new"] = [graph, newLuaState, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::LoopPlaybackNode>(numChannels);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto sampleRegionApi = sol::state_view(newLuaState).create_table();
    sampleRegionApi["new"] = [graph, newLuaState, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::SampleRegionPlaybackNode>(numChannels);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        t["setLoopLength"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setLoopLength(v);
          }
        };
        t["getLoopLength"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getLoopLength();
          }
          return 0;
        };
        t["setSpeed"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setSpeed(v);
          }
        };
        t["getSpeed"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getSpeed();
          }
          return 0.0f;
        };
        t["play"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->play();
          }
        };
        t["pause"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->pause();
          }
        };
        t["stop"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->stop();
          }
        };
        t["trigger"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->trigger();
          }
        };
        t["isPlaying"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->isPlaying();
          }
          return false;
        };
        t["seek"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->seekNormalized(v);
          }
        };
        t["getNormalizedPosition"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getNormalizedPosition();
          }
          return 0.0f;
        };
        t["setPlayStart"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setPlayStart(v);
          }
        };
        t["setLoopStart"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setLoopStart(v);
          }
        };
        t["setLoopEnd"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setLoopEnd(v);
          }
        };
        t["setCrossfade"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setCrossfade(v);
          }
        };
        t["setUnison"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setUnison(v);
          }
        };
        t["getUnison"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getUnison();
          }
          return 1;
        };
        t["setDetune"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setDetune(v);
          }
        };
        t["getDetune"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getDetune();
          }
          return 0.0f;
        };
        t["setSpread"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            n->setSpread(v);
          }
        };
        t["getSpread"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            return n->getSpread();
          }
          return 0.0f;
        };
        t["getPeaks"] = [newLuaState](sol::table self, int numBuckets) {
          sol::table result = sol::state_view(newLuaState).create_table();
          if (auto n = tableNode<dsp_primitives::SampleRegionPlaybackNode>(self)) {
            std::vector<float> peaks;
            bool ok = n->computePeaks(numBuckets, peaks);
            if (ok && !peaks.empty()) {
              for (size_t i = 0; i < peaks.size(); ++i) {
                result[i + 1] = peaks[i];
              }
            }
          }
          return result;
        };
        return t;
      };
    primitives["SampleRegionPlaybackNode"] = sampleRegionApi;
  }
  {
    auto gateApi = sol::state_view(newLuaState).create_table();
    gateApi["new"] = [graph, newLuaState, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::PlaybackStateGateNode>(numChannels);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto captureApi = sol::state_view(newLuaState).create_table();
    captureApi["new"] = [graph, newLuaState, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::RetrospectiveCaptureNode>(numChannels);
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto recordStateApi = sol::state_view(newLuaState).create_table();
    recordStateApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::RecordStateNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto quantizerApi = sol::state_view(newLuaState).create_table();
    quantizerApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::QuantizerNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto modeApi = sol::state_view(newLuaState).create_table();
    modeApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::RecordModePolicyNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto forwardApi = sol::state_view(newLuaState).create_table();
    forwardApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ForwardCommitSchedulerNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto transportApi = sol::state_view(newLuaState).create_table();
    transportApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::TransportStateNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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

  auto graphTable = sol::state_view(newLuaState).create_table();
  graphTable["connect"] = sol::overload(
      [graph](const sol::object &fromObj,
                               const sol::object &toObj) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        return graph->connect(from, 0, to, 0);
      },
      [graph](const sol::object &fromObj,
                               const sol::object &toObj, int fromOutput,
                               int toInput) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        return graph->connect(from, fromOutput, to, toInput);
      });
  graphTable["disconnect"] = sol::overload(
      [graph](const sol::object &fromObj,
                               const sol::object &toObj) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        graph->disconnect(from, 0, to, 0);
        return true;
      },
      [graph](const sol::object &fromObj,
                               const sol::object &toObj, int fromOutput,
                               int toInput) {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) {
          return false;
        }
        graph->disconnect(from, fromOutput, to, toInput);
        return true;
      });
  graphTable["disconnectAll"] = [graph](const sol::object &nodeObj) {
    auto node = toPrimitiveNode(nodeObj);
    if (!node) {
      return false;
    }
    graph->disconnectAll(node);
    return true;
  };
  graphTable["clear"] = [graph]() { graph->clear(); };
  graphTable["hasCycle"] = [graph]() { return graph->hasCycle(); };
  graphTable["nodeCount"] =
      [graph]() { return static_cast<int>(graph->getNodeCount()); };
  graphTable["connectionCount"] =
      [graph]() { return static_cast<int>(graph->getConnectionCount()); };

  graphTable["markInput"] = [graph](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::InputDSP);
      return true;
    };
  graphTable["markMonitor"] = [graph](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::Monitor);
      return true;
    };
  graphTable["markOutput"] = [graph](const sol::object& nodeObj) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      graph->setNodeRole(node, dsp_primitives::PrimitiveGraph::NodeRole::OutputDSP);
      return true;
    };
  graphTable["nameNode"] = [&newNamedNodes, &mapInternalToExternal](
      const sol::object& nodeObj, const std::string& rawPath) {
      auto node = toPrimitiveNode(nodeObj);
      if (!node) {
        return false;
      }
      newNamedNodes[mapInternalToExternal(rawPath)] = node;
      return true;
    };

  ctx["graph"] = graphTable;
}

} // namespace dsp_host

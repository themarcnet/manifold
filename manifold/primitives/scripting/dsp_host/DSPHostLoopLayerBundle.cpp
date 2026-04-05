#include "DSPHostInternal.h"

#include "../PrimitiveGraph.h"
#include "dsp/core/nodes/PrimitiveNodes.h"

namespace dsp_host {

void registerLoopLayerBundle(LoadSession &session,
                             PrimitiveGraphPtr graph,
                             sol::table &ctx,
                             const TrackNodeFn &trackNode,
                             const PathMapperFn &mapInternalToExternal) {
  auto &newLayerPlaybackNodes = session.layerPlaybackNodes;
  auto &newLayerGateNodes = session.layerGateNodes;
  auto &newLayerOutputNodes = session.layerOutputNodes;
  auto &newNamedNodes = session.namedNodes;
  lua_State *newLuaState = session.luaState;

  auto bundles = sol::state_view(newLuaState).create_table();
  {
    auto loopLayerApi = sol::state_view(newLuaState).create_table();
    loopLayerApi["new"] = [graph, newLuaState, &newLayerPlaybackNodes, &newLayerGateNodes, &newLayerOutputNodes, &newNamedNodes, &mapInternalToExternal, trackNode](sol::optional<sol::table> options) {
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

      auto layer = sol::state_view(newLuaState).create_table();
      layer["__node"] = gain;
      layer["__inputNode"] = input;
      layer["__outputNode"] = gain;
      layer["__capture"] = sol::state_view(newLuaState).create_table_with("__node", capture);
      layer["__playback"] = sol::state_view(newLuaState).create_table_with("__node", playback);
      layer["__gate"] = sol::state_view(newLuaState).create_table_with("__node", gate);
      layer["__gain"] = sol::state_view(newLuaState).create_table_with("__node", gain);
      layer["__record"] = sol::state_view(newLuaState).create_table_with("__node", recordState);
      layer["__quantizer"] = sol::state_view(newLuaState).create_table_with("__node", quantizer);
      layer["__mode"] = sol::state_view(newLuaState).create_table_with("__node", mode);
      layer["__forward"] = sol::state_view(newLuaState).create_table_with("__node", forward);
      layer["__transport"] = sol::state_view(newLuaState).create_table_with("__node", transport);
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
      layer["parts"] = sol::state_view(newLuaState).create_table_with(
          "input", sol::state_view(newLuaState).create_table_with("__node", input),
          "capture", sol::state_view(newLuaState).create_table_with("__node", capture),
          "record", sol::state_view(newLuaState).create_table_with("__node", recordState),
          "quantizer", sol::state_view(newLuaState).create_table_with("__node", quantizer),
          "mode", sol::state_view(newLuaState).create_table_with("__node", mode),
          "forward", sol::state_view(newLuaState).create_table_with("__node", forward),
          "transport", sol::state_view(newLuaState).create_table_with("__node", transport),
          "gain", sol::state_view(newLuaState).create_table_with("__node", gain),
          "gate", sol::state_view(newLuaState).create_table_with("__node", gate),
          "playback", sol::state_view(newLuaState).create_table_with("__node", playback));

      return layer;
    };
    bundles["LoopLayer"] = loopLayerApi;
  }

  ctx["bundles"] = bundles;
}

} // namespace dsp_host

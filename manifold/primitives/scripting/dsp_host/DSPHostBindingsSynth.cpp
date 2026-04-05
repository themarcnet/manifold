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

void registerSynthBindings(LoadSession &session,
                           PrimitiveGraphPtr graph,
                           sol::table &ctx,
                           const TrackNodeFn &trackNode) {
  auto &newLua = session.lua;
  lua_State *newLuaState = session.luaState;
  sol::table primitives = getOrCreateContextTable(ctx, "primitives", newLuaState);

  newLua.new_usertype<dsp_primitives::OscillatorNode>(
      "OscillatorNode",
      sol::constructors<std::shared_ptr<dsp_primitives::OscillatorNode>()>(),
      "setFrequency", &dsp_primitives::OscillatorNode::setFrequency,
      "setAmplitude", &dsp_primitives::OscillatorNode::setAmplitude,
      "setEnabled", &dsp_primitives::OscillatorNode::setEnabled,
      "setWaveform", &dsp_primitives::OscillatorNode::setWaveform,
      "resetPhase", &dsp_primitives::OscillatorNode::resetPhase,
      "setDrive", &dsp_primitives::OscillatorNode::setDrive,
      "setDriveShape", &dsp_primitives::OscillatorNode::setDriveShape,
      "setDriveBias", &dsp_primitives::OscillatorNode::setDriveBias,
      "setDriveMix", &dsp_primitives::OscillatorNode::setDriveMix,
      "setRenderMode", &dsp_primitives::OscillatorNode::setRenderMode,
      "getRenderMode", &dsp_primitives::OscillatorNode::getRenderMode,
      "setAdditivePartials", &dsp_primitives::OscillatorNode::setAdditivePartials,
      "getAdditivePartials", &dsp_primitives::OscillatorNode::getAdditivePartials,
      "setAdditiveTilt", &dsp_primitives::OscillatorNode::setAdditiveTilt,
      "getAdditiveTilt", &dsp_primitives::OscillatorNode::getAdditiveTilt,
      "setAdditiveDrift", &dsp_primitives::OscillatorNode::setAdditiveDrift,
      "getAdditiveDrift", &dsp_primitives::OscillatorNode::getAdditiveDrift,
      "setSyncEnabled", &dsp_primitives::OscillatorNode::setSyncEnabled,
      "isSyncEnabled", &dsp_primitives::OscillatorNode::isSyncEnabled,
      "getFrequency", &dsp_primitives::OscillatorNode::getFrequency,
      "getAmplitude", &dsp_primitives::OscillatorNode::getAmplitude,
      "getDrive", &dsp_primitives::OscillatorNode::getDrive,
      "getDriveShape", &dsp_primitives::OscillatorNode::getDriveShape,
      "getDriveBias", &dsp_primitives::OscillatorNode::getDriveBias,
      "getDriveMix", &dsp_primitives::OscillatorNode::getDriveMix,
      "isEnabled", &dsp_primitives::OscillatorNode::isEnabled,
      "getWaveform", &dsp_primitives::OscillatorNode::getWaveform);

  newLua.new_usertype<dsp_primitives::SineBankNode>(
      "SineBankNode",
      sol::constructors<std::shared_ptr<dsp_primitives::SineBankNode>()>(),
      "setFrequency", &dsp_primitives::SineBankNode::setFrequency,
      "getFrequency", &dsp_primitives::SineBankNode::getFrequency,
      "setAmplitude", &dsp_primitives::SineBankNode::setAmplitude,
      "getAmplitude", &dsp_primitives::SineBankNode::getAmplitude,
      "setEnabled", &dsp_primitives::SineBankNode::setEnabled,
      "isEnabled", &dsp_primitives::SineBankNode::isEnabled,
      "setStereoSpread", &dsp_primitives::SineBankNode::setStereoSpread,
      "getStereoSpread", &dsp_primitives::SineBankNode::getStereoSpread,
      "setUnison", &dsp_primitives::SineBankNode::setUnison,
      "getUnison", &dsp_primitives::SineBankNode::getUnison,
      "setDetune", &dsp_primitives::SineBankNode::setDetune,
      "getDetune", &dsp_primitives::SineBankNode::getDetune,
      "setDrive", &dsp_primitives::SineBankNode::setDrive,
      "getDrive", &dsp_primitives::SineBankNode::getDrive,
      "setDriveShape", &dsp_primitives::SineBankNode::setDriveShape,
      "getDriveShape", &dsp_primitives::SineBankNode::getDriveShape,
      "setDriveBias", &dsp_primitives::SineBankNode::setDriveBias,
      "getDriveBias", &dsp_primitives::SineBankNode::getDriveBias,
      "setDriveMix", &dsp_primitives::SineBankNode::setDriveMix,
      "getDriveMix", &dsp_primitives::SineBankNode::getDriveMix,
      "setSyncEnabled", &dsp_primitives::SineBankNode::setSyncEnabled,
      "isSyncEnabled", &dsp_primitives::SineBankNode::isSyncEnabled,
      "reset", &dsp_primitives::SineBankNode::reset,
      "clearPartials", &dsp_primitives::SineBankNode::clearPartials,
      "setPartial", &dsp_primitives::SineBankNode::setPartial,
      "getActivePartialCount", &dsp_primitives::SineBankNode::getActivePartialCount,
      "getReferenceFundamental", &dsp_primitives::SineBankNode::getReferenceFundamental,
      "setSpectralMode", &dsp_primitives::SineBankNode::setSpectralMode,
      "getSpectralMode", &dsp_primitives::SineBankNode::getSpectralMode,
      "setSpectralSamplePlayback", [](std::shared_ptr<dsp_primitives::SineBankNode>& self,
                                      const std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>& playback) {
        if (self) {
          self->setSpectralSamplePlayback(playback);
        }
      },
      "clearSpectralSamplePlayback", &dsp_primitives::SineBankNode::clearSpectralSamplePlayback,
      "hasSpectralSamplePlayback", &dsp_primitives::SineBankNode::hasSpectralSamplePlayback,
      "setSpectralWaveform", &dsp_primitives::SineBankNode::setSpectralWaveform,
      "getSpectralWaveform", &dsp_primitives::SineBankNode::getSpectralWaveform,
      "setSpectralPulseWidth", &dsp_primitives::SineBankNode::setSpectralPulseWidth,
      "getSpectralPulseWidth", &dsp_primitives::SineBankNode::getSpectralPulseWidth,
      "setSpectralAdditivePartials", &dsp_primitives::SineBankNode::setSpectralAdditivePartials,
      "getSpectralAdditivePartials", &dsp_primitives::SineBankNode::getSpectralAdditivePartials,
      "setSpectralAdditiveTilt", &dsp_primitives::SineBankNode::setSpectralAdditiveTilt,
      "getSpectralAdditiveTilt", &dsp_primitives::SineBankNode::getSpectralAdditiveTilt,
      "setSpectralAdditiveDrift", &dsp_primitives::SineBankNode::setSpectralAdditiveDrift,
      "getSpectralAdditiveDrift", &dsp_primitives::SineBankNode::getSpectralAdditiveDrift,
      "setSpectralMorphAmount", &dsp_primitives::SineBankNode::setSpectralMorphAmount,
      "getSpectralMorphAmount", &dsp_primitives::SineBankNode::getSpectralMorphAmount,
      "setSpectralMorphDepth", &dsp_primitives::SineBankNode::setSpectralMorphDepth,
      "getSpectralMorphDepth", &dsp_primitives::SineBankNode::getSpectralMorphDepth,
      "setSpectralMorphCurve", &dsp_primitives::SineBankNode::setSpectralMorphCurve,
      "getSpectralMorphCurve", &dsp_primitives::SineBankNode::getSpectralMorphCurve,
      "setSpectralTemporalPosition", &dsp_primitives::SineBankNode::setSpectralTemporalPosition,
      "getSpectralTemporalPosition", &dsp_primitives::SineBankNode::getSpectralTemporalPosition,
      "setSpectralTemporalSpeed", &dsp_primitives::SineBankNode::setSpectralTemporalSpeed,
      "getSpectralTemporalSpeed", &dsp_primitives::SineBankNode::getSpectralTemporalSpeed,
      "setSpectralTemporalSmooth", &dsp_primitives::SineBankNode::setSpectralTemporalSmooth,
      "getSpectralTemporalSmooth", &dsp_primitives::SineBankNode::getSpectralTemporalSmooth,
      "setSpectralTemporalContrast", &dsp_primitives::SineBankNode::setSpectralTemporalContrast,
      "getSpectralTemporalContrast", &dsp_primitives::SineBankNode::getSpectralTemporalContrast,
      "setSpectralEnvelopeFollow", &dsp_primitives::SineBankNode::setSpectralEnvelopeFollow,
      "getSpectralEnvelopeFollow", &dsp_primitives::SineBankNode::getSpectralEnvelopeFollow,
      "setSpectralStretch", &dsp_primitives::SineBankNode::setSpectralStretch,
      "getSpectralStretch", &dsp_primitives::SineBankNode::getSpectralStretch,
      "setSpectralTiltMode", &dsp_primitives::SineBankNode::setSpectralTiltMode,
      "getSpectralTiltMode", &dsp_primitives::SineBankNode::getSpectralTiltMode,
      "setSpectralAddFlavor", &dsp_primitives::SineBankNode::setSpectralAddFlavor,
      "getSpectralAddFlavor", &dsp_primitives::SineBankNode::getSpectralAddFlavor,
      "getPartials", [](sol::this_state ts, std::shared_ptr<dsp_primitives::SineBankNode>& self) -> sol::table {
        if (!self) {
          sol::state_view lua(ts);
          return sol::table(lua, sol::create);
        }
        return partialDataToLua(ts, self->getPartials());
      },
      "setPartials", [](std::shared_ptr<dsp_primitives::SineBankNode>& self, sol::table partialsTable) {
        if (!self) {
          return;
        }
        dsp_primitives::PartialData data;
        data.activeCount = partialsTable["activeCount"].get_or(0);
        data.fundamental = partialsTable["fundamental"].get_or(0.0f);
        sol::object entriesObj = partialsTable["partials"];
        if (entriesObj.valid() && entriesObj.get_type() == sol::type::table) {
          sol::table entries = entriesObj.as<sol::table>();
          for (int i = 0; i < dsp_primitives::PartialData::kMaxPartials; ++i) {
            sol::object entryObj = entries[i + 1];
            if (!entryObj.valid() || entryObj.get_type() != sol::type::table) {
              continue;
            }
            sol::table entry = entryObj.as<sol::table>();
            data.frequencies[static_cast<size_t>(i)] = entry["frequency"].get_or(0.0f);
            data.amplitudes[static_cast<size_t>(i)] = entry["amplitude"].get_or(0.0f);
            data.phases[static_cast<size_t>(i)] = entry["phase"].get_or(0.0f);
            data.decayRates[static_cast<size_t>(i)] = entry["decayRate"].get_or(0.0f);
          }
        }
        self->setPartials(data);
      });

  {
    auto oscApi = sol::state_view(newLuaState).create_table();
    oscApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::OscillatorNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
        t["resetPhase"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->resetPhase();
          }
        };
        t["setDrive"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setDrive(v);
          }
        };
        t["setDriveShape"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setDriveShape(v);
          }
        };
        t["setDriveBias"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setDriveBias(v);
          }
        };
        t["setDriveMix"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setDriveMix(v);
          }
        };
        t["setRenderMode"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setRenderMode(v);
          }
        };
        t["setAdditivePartials"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setAdditivePartials(v);
          }
        };
        t["setAdditiveTilt"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setAdditiveTilt(v);
          }
        };
        t["setAdditiveDrift"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setAdditiveDrift(v);
          }
        };
        t["setSyncEnabled"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setSyncEnabled(v);
          }
        };
        t["isSyncEnabled"] = [](sol::table self) -> bool {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            return n->isSyncEnabled();
          }
          return false;
        };
        t["setPulseWidth"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setPulseWidth(v);
          }
        };
        t["setUnison"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setUnison(v);
          }
        };
        t["setDetune"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setDetune(v);
          }
        };
        t["setSpread"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::OscillatorNode>(self)) {
            n->setSpread(v);
          }
        };
        return t;
      };
    primitives["OscillatorNode"] = oscApi;
  }
  {
    auto sineBankApi = sol::state_view(newLuaState).create_table();
    sineBankApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::SineBankNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        t["setFrequency"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setFrequency(v);
          }
        };
        t["setAmplitude"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setAmplitude(v);
          }
        };
        t["setEnabled"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setEnabled(v);
          }
        };
        t["setStereoSpread"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setStereoSpread(v);
          }
        };
        t["setSpread"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setStereoSpread(v);
          }
        };
        t["setUnison"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setUnison(v);
          }
        };
        t["setDetune"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setDetune(v);
          }
        };
        t["setDrive"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setDrive(v);
          }
        };
        t["setDriveShape"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setDriveShape(v);
          }
        };
        t["setDriveBias"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setDriveBias(v);
          }
        };
        t["setDriveMix"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setDriveMix(v);
          }
        };
        t["setSyncEnabled"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSyncEnabled(v);
          }
        };
        t["setSpectralMode"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralMode(v);
          }
        };
        t["getSpectralMode"] = [](sol::table self) -> int {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            return n->getSpectralMode();
          }
          return 0;
        };
        t["setSpectralSamplePlayback"] = [](sol::table self, sol::object playbackObj) {
          auto n = tableNode<dsp_primitives::SineBankNode>(self);
          if (!n) {
            return;
          }
          std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> playback;
          if (playbackObj.is<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>()) {
            playback = playbackObj.as<std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode>>();
          } else if (playbackObj.get_type() == sol::type::table) {
            playback = tableNode<dsp_primitives::SampleRegionPlaybackNode>(playbackObj.as<sol::table>());
          }
          n->setSpectralSamplePlayback(playback);
        };
        t["clearSpectralSamplePlayback"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->clearSpectralSamplePlayback();
          }
        };
        t["setSpectralWaveform"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralWaveform(v);
          }
        };
        t["setSpectralPulseWidth"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralPulseWidth(v);
          }
        };
        t["setSpectralAdditivePartials"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralAdditivePartials(v);
          }
        };
        t["setSpectralAdditiveTilt"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralAdditiveTilt(v);
          }
        };
        t["setSpectralAdditiveDrift"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralAdditiveDrift(v);
          }
        };
        t["setSpectralMorphAmount"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralMorphAmount(v);
          }
        };
        t["setSpectralMorphDepth"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralMorphDepth(v);
          }
        };
        t["setSpectralMorphCurve"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralMorphCurve(v);
          }
        };
        t["setSpectralTemporalPosition"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralTemporalPosition(v);
          }
        };
        t["setSpectralTemporalSpeed"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralTemporalSpeed(v);
          }
        };
        t["setSpectralTemporalSmooth"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralTemporalSmooth(v);
          }
        };
        t["setSpectralTemporalContrast"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralTemporalContrast(v);
          }
        };
        t["setSpectralStretch"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralStretch(v);
          }
        };
        t["setSpectralTiltMode"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralTiltMode(v);
          }
        };
        t["setSpectralAddFlavor"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setSpectralAddFlavor(v);
          }
        };
        t["reset"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->reset();
          }
        };
        t["clearPartials"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->clearPartials();
          }
        };
        t["setPartial"] = [](sol::table self, int index, float frequency, float amplitude, sol::optional<float> phase, sol::optional<float> decayRate) {
          if (auto n = tableNode<dsp_primitives::SineBankNode>(self)) {
            n->setPartial(index - 1, frequency, amplitude, phase.value_or(0.0f), decayRate.value_or(0.0f));
          }
        };
        t["setPartials"] = [](sol::table self, sol::table partialsTable) {
          auto n = tableNode<dsp_primitives::SineBankNode>(self);
          if (!n) {
            return;
          }
          dsp_primitives::PartialData data;
          data.activeCount = partialsTable["activeCount"].get_or(0);
          data.fundamental = partialsTable["fundamental"].get_or(0.0f);
          sol::object entriesObj = partialsTable["partials"];
          if (entriesObj.valid() && entriesObj.get_type() == sol::type::table) {
            sol::table entries = entriesObj.as<sol::table>();
            for (int i = 0; i < dsp_primitives::PartialData::kMaxPartials; ++i) {
              sol::object entryObj = entries[i + 1];
              if (!entryObj.valid() || entryObj.get_type() != sol::type::table) {
                continue;
              }
              sol::table entry = entryObj.as<sol::table>();
              data.frequencies[static_cast<size_t>(i)] = entry["frequency"].get_or(0.0f);
              data.amplitudes[static_cast<size_t>(i)] = entry["amplitude"].get_or(0.0f);
              data.phases[static_cast<size_t>(i)] = entry["phase"].get_or(0.0f);
              data.decayRates[static_cast<size_t>(i)] = entry["decayRate"].get_or(0.0f);
            }
          }
          n->setPartials(data);
        };
        t["getPartials"] = [graph, newLuaState](sol::table self) -> sol::table {
          auto n = tableNode<dsp_primitives::SineBankNode>(self);
          if (!n) {
            return sol::state_view(newLuaState).create_table();
          }
          return partialDataToLua(newLuaState, n->getPartials());
        };
        return t;
      };
    primitives["SineBankNode"] = sineBankApi;
  }
  {
    auto midiVoiceApi = sol::state_view(newLuaState).create_table();
    midiVoiceApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MidiVoiceNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        t["setWaveform"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setWaveform(v);
          }
        };
        t["setAttack"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setAttack(v);
          }
        };
        t["setDecay"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setDecay(v);
          }
        };
        t["setSustain"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setSustain(v);
          }
        };
        t["setRelease"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setRelease(v);
          }
        };
        t["setFilterCutoff"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setFilterCutoff(v);
          }
        };
        t["setFilterResonance"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setFilterResonance(v);
          }
        };
        t["setFilterEnvAmount"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setFilterEnvAmount(v);
          }
        };
        t["setPolyphony"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setPolyphony(v);
          }
        };
        t["setGlide"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setGlide(v);
          }
        };
        t["setDetune"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setDetune(v);
          }
        };
        t["setSpread"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setSpread(v);
          }
        };
        t["setUnison"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->setUnison(v);
          }
        };
        t["noteOn"] = [](sol::table self, int channel, int note, int velocity) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->noteOn(static_cast<uint8_t>(channel), static_cast<uint8_t>(note), static_cast<uint8_t>(velocity));
          }
        };
        t["noteOff"] = [](sol::table self, int channel, int note) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->noteOff(static_cast<uint8_t>(channel), static_cast<uint8_t>(note));
          }
        };
        t["allNotesOff"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->allNotesOff();
          }
        };
        t["pitchBend"] = [](sol::table self, int channel, int value) {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            n->pitchBend(static_cast<uint8_t>(channel), static_cast<int16_t>(value));
          }
        };
        t["getNumActiveVoices"] = [](sol::table self) -> int {
          if (auto n = tableNode<dsp_primitives::MidiVoiceNode>(self)) {
            return n->getNumActiveVoices();
          }
          return 0;
        };
        return t;
      };
    primitives["MidiVoiceNode"] = midiVoiceApi;
  }
  {
    auto midiInputApi = sol::state_view(newLuaState).create_table();
    midiInputApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MidiInputNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        t["setChannelFilter"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setChannelFilter(v);
          }
        };
        t["setChannelMask"] = [](sol::table self, int v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setChannelMask(static_cast<uint16_t>(v));
          }
        };
        t["setOmniMode"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setOmniMode(v);
          }
        };
        t["setMonophonic"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setMonophonic(v);
          }
        };
        t["setPortamento"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setPortamento(v);
          }
        };
        t["setPitchBendRange"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setPitchBendRange(v);
          }
        };
        t["setEnabled"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->setEnabled(v);
          }
        };
        t["triggerNoteOn"] = [](sol::table self, int note, int velocity) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->triggerNoteOn(static_cast<uint8_t>(note), static_cast<uint8_t>(velocity));
          }
        };
        t["triggerNoteOff"] = [](sol::table self, int note) {
          if (auto n = tableNode<dsp_primitives::MidiInputNode>(self)) {
            n->triggerNoteOff(static_cast<uint8_t>(note));
          }
        };
        t["connectToVoiceNode"] = [newLuaState](sol::table self, sol::table voiceTable) {
          auto voiceNode = tableNode<dsp_primitives::MidiVoiceNode>(voiceTable);
          auto inputNode = tableNode<dsp_primitives::MidiInputNode>(self);
          if (voiceNode && inputNode) {
            inputNode->connectToVoiceNode(voiceNode);
          }
        };
        return t;
      };
    primitives["MidiInputNode"] = midiInputApi;
  }
  {
    auto adsrApi = sol::state_view(newLuaState).create_table();
    adsrApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ADSREnvelopeNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
        t["__node"] = node;
        t["setAttack"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->setAttack(v);
          }
        };
        t["setDecay"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->setDecay(v);
          }
        };
        t["setSustain"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->setSustain(v);
          }
        };
        t["setRelease"] = [](sol::table self, float v) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->setRelease(v);
          }
        };
        t["setGate"] = [](sol::table self, bool v) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->setGate(v);
          }
        };
        t["reset"] = [](sol::table self) {
          if (auto n = tableNode<dsp_primitives::ADSREnvelopeNode>(self)) {
            n->reset();
          }
        };
        return t;
      };
    primitives["ADSREnvelopeNode"] = adsrApi;
  }

}

} // namespace dsp_host

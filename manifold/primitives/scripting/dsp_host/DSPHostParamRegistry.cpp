#include "DSPHostInternal.h"

#include "../../control/OSCServer.h"
#include "dsp/core/nodes/PrimitiveNodes.h"

#include <algorithm>

namespace dsp_host {

void registerParamsApi(LoadSession &session,
                       sol::table &ctx,
                       const PathMapperFn &mapInternalToExternal,
                       const PathMapperFn &mapExternalToInternal) {
  auto &newParamSpecs = session.paramSpecs;
  auto &newParamValues = session.paramValues;
  auto &newParamBindings = session.paramBindings;
  auto &newExternalToInternalPath = session.externalToInternalPath;
  auto &newInternalToExternalPath = session.internalToExternalPath;
  lua_State *newLuaState = session.luaState;

  auto paramsTable = sol::state_view(newLuaState).create_table();
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
          if (options["deferGraphMutation"].valid()) {
            spec.deferGraphMutation = options["deferGraphMutation"].get<bool>();
          }
        }

        spec.defaultValue = clampParamValue(spec, spec.defaultValue);
        newParamSpecs[externalPath] = spec;
        newParamValues[externalPath] = spec.defaultValue;
        newExternalToInternalPath[externalPath] = internalPath;
        newInternalToExternalPath[internalPath] = externalPath;
      };

  paramsTable["bind"] =
      [&newParamBindings, &mapInternalToExternal](
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
          if (method == "setDrive") {
            newParamBindings[path] = [osc](float v) { osc->setDrive(v); };
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

        if (auto phaseVocoder = std::dynamic_pointer_cast<dsp_primitives::PhaseVocoderNode>(node)) {
          if (method == "setPitchSemitones") {
            newParamBindings[path] = [phaseVocoder](float v) { phaseVocoder->setPitchSemitones(v); };
            return true;
          }
          if (method == "setTimeStretch") {
            newParamBindings[path] = [phaseVocoder](float v) { phaseVocoder->setTimeStretch(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [phaseVocoder](float v) { phaseVocoder->setMix(v); };
            return true;
          }
          if (method == "setFFTOrder") {
            newParamBindings[path] = [phaseVocoder](float v) { phaseVocoder->setFFTOrder(static_cast<int>(v)); };
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
          if (method == "setLogicMode") {
            newParamBindings[path] = [crusher](float v) { crusher->setLogicMode(static_cast<int>(std::round(v))); };
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

        // ⚠️ UNSOLICITED: PitchDetectorNode parameter bindings - NOT REQUESTED
        // if (auto detector = std::dynamic_pointer_cast<dsp_primitives::PitchDetectorNode>(node)) {
        //   if (method == "setMinFreq" || method == "setFrequencyRange") {
        //     // Store both min/max for setFrequencyRange, but also support individual calls
        //     newParamBindings[path] = [detector](float v) { 
        //       // When called as setMinFreq, we set just the min (max stays at default/stored)
        //       // For full range control, use setFrequencyRange in Lua
        //       detector->setFrequencyRange(v, 2000.0f);
        //     };
        //     return true;
        //   }
        //   if (method == "setMaxFreq") {
        //     newParamBindings[path] = [detector](float v) { 
        //       detector->setFrequencyRange(50.0f, v);
        //     };
        //     return true;
        //   }
        //   if (method == "setThreshold") {
        //     newParamBindings[path] = [detector](float v) { detector->setThreshold(v); };
        //     return true;
        //   }
        //   if (method == "setEnabled") {
        //     newParamBindings[path] = [detector](float v) { detector->setEnabled(v > 0.5f); };
        //     return true;
        //   }
        //   if (method == "setWindowSize") {
        //     newParamBindings[path] = [detector](float v) { detector->setWindowSize(static_cast<int>(v)); };
        //     return true;
        //   }
        // }

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

        if (auto eq8 = std::dynamic_pointer_cast<dsp_primitives::EQ8Node>(node)) {
          std::string indexedMethod = method;
          int bandIndex = -1;
          if (auto pos = method.find(':'); pos != std::string::npos) {
            indexedMethod = method.substr(0, pos);
            try {
              bandIndex = std::stoi(method.substr(pos + 1));
            } catch (...) {
              bandIndex = -1;
            }
          }

          if (indexedMethod == "setBandEnabled" && bandIndex >= 1 && bandIndex <= dsp_primitives::EQ8Node::kNumBands) {
            newParamBindings[path] = [eq8, bandIndex](float v) { eq8->setBandEnabled(bandIndex, v > 0.5f); };
            return true;
          }
          if (indexedMethod == "setBandType" && bandIndex >= 1 && bandIndex <= dsp_primitives::EQ8Node::kNumBands) {
            newParamBindings[path] = [eq8, bandIndex](float v) { eq8->setBandType(bandIndex, static_cast<int>(v)); };
            return true;
          }
          if (indexedMethod == "setBandFreq" && bandIndex >= 1 && bandIndex <= dsp_primitives::EQ8Node::kNumBands) {
            newParamBindings[path] = [eq8, bandIndex](float v) { eq8->setBandFreq(bandIndex, v); };
            return true;
          }
          if (indexedMethod == "setBandGain" && bandIndex >= 1 && bandIndex <= dsp_primitives::EQ8Node::kNumBands) {
            newParamBindings[path] = [eq8, bandIndex](float v) { eq8->setBandGain(bandIndex, v); };
            return true;
          }
          if (indexedMethod == "setBandQ" && bandIndex >= 1 && bandIndex <= dsp_primitives::EQ8Node::kNumBands) {
            newParamBindings[path] = [eq8, bandIndex](float v) { eq8->setBandQ(bandIndex, v); };
            return true;
          }
          if (method == "setOutput") {
            newParamBindings[path] = [eq8](float v) { eq8->setOutput(v); };
            return true;
          }
          if (method == "setMix") {
            newParamBindings[path] = [eq8](float v) { eq8->setMix(v); };
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

  ctx["params"] = paramsTable;
}

} // namespace dsp_host

using dsp_host::DspParamSpec;
using dsp_host::clampParamValue;
using dsp_host::sanitizePath;

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
  DspParamSpec spec;
  float normalized = 0.0f;
  bool shouldDeferGraphMutation = false;

  {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    const auto specIt = pImpl->paramSpecs.find(path);
    if (specIt == pImpl->paramSpecs.end()) {
      return false;
    }

    spec = specIt->second;
    normalized = clampParamValue(spec, value);
    pImpl->paramValues[path] = normalized;
    shouldDeferGraphMutation = spec.deferGraphMutation;
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

  if (shouldDeferGraphMutation) {
    return enqueueDeferredGraphMutation(path, normalized);
  }

  {
    const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
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
  }

  if (pImpl->processor) {
    const juce::String paramPath(path);
    if (paramPath.startsWith("/midi/synth/rack/audio/")) {
      return compileRuntimeAndRequestSwap("rack audio route change");
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

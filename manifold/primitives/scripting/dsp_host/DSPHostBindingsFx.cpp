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

void registerFxBindings(LoadSession &session,
                        PrimitiveGraphPtr graph,
                        sol::table &ctx,
                        const TrackNodeFn &trackNode) {
  auto &newLua = session.lua;
  lua_State *newLuaState = session.luaState;
  sol::table primitives = getOrCreateContextTable(ctx, "primitives", newLuaState);

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

  newLua.new_usertype<dsp_primitives::PhaseVocoderNode>(
      "PhaseVocoderNode",
      sol::constructors<std::shared_ptr<dsp_primitives::PhaseVocoderNode>(int)>(),
      "setMode", &dsp_primitives::PhaseVocoderNode::setMode,
      "getMode", &dsp_primitives::PhaseVocoderNode::getMode,
      "setPitchSemitones", &dsp_primitives::PhaseVocoderNode::setPitchSemitones,
      "getPitchSemitones", &dsp_primitives::PhaseVocoderNode::getPitchSemitones,
      "setTimeStretch", &dsp_primitives::PhaseVocoderNode::setTimeStretch,
      "getTimeStretch", &dsp_primitives::PhaseVocoderNode::getTimeStretch,
      "setMix", &dsp_primitives::PhaseVocoderNode::setMix,
      "getMix", &dsp_primitives::PhaseVocoderNode::getMix,
      "setFFTOrder", &dsp_primitives::PhaseVocoderNode::setFFTOrder,
      "getFFTOrder", &dsp_primitives::PhaseVocoderNode::getFFTOrder,
      "getLatencySamples", &dsp_primitives::PhaseVocoderNode::getLatencySamples,
      "reset", &dsp_primitives::PhaseVocoderNode::reset,
      "prepare", &dsp_primitives::PhaseVocoderNode::prepare);

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
      "setEnabled", &dsp_primitives::RingModulatorNode::setEnabled,
      "getFrequency", &dsp_primitives::RingModulatorNode::getFrequency,
      "getDepth", &dsp_primitives::RingModulatorNode::getDepth,
      "getMix", &dsp_primitives::RingModulatorNode::getMix,
      "getSpread", &dsp_primitives::RingModulatorNode::getSpread,
      "isEnabled", &dsp_primitives::RingModulatorNode::isEnabled,
      "reset", &dsp_primitives::RingModulatorNode::reset);

  newLua.new_usertype<dsp_primitives::BitCrusherNode>(
      "BitCrusherNode",
      sol::constructors<std::shared_ptr<dsp_primitives::BitCrusherNode>()>(),
      "setBits", &dsp_primitives::BitCrusherNode::setBits,
      "setRateReduction", &dsp_primitives::BitCrusherNode::setRateReduction,
      "setMix", &dsp_primitives::BitCrusherNode::setMix,
      "setOutput", &dsp_primitives::BitCrusherNode::setOutput,
      "setLogicMode", &dsp_primitives::BitCrusherNode::setLogicMode,
      "getBits", &dsp_primitives::BitCrusherNode::getBits,
      "getRateReduction", &dsp_primitives::BitCrusherNode::getRateReduction,
      "getMix", &dsp_primitives::BitCrusherNode::getMix,
      "getOutput", &dsp_primitives::BitCrusherNode::getOutput,
      "getLogicMode", &dsp_primitives::BitCrusherNode::getLogicMode,
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
      "setMode", &dsp_primitives::EnvelopeFollowerNode::setMode,
      "getAttack", &dsp_primitives::EnvelopeFollowerNode::getAttack,
      "getRelease", &dsp_primitives::EnvelopeFollowerNode::getRelease,
      "getSensitivity", &dsp_primitives::EnvelopeFollowerNode::getSensitivity,
      "getHighpass", &dsp_primitives::EnvelopeFollowerNode::getHighpass,
      "getMode", &dsp_primitives::EnvelopeFollowerNode::getMode,
      "getEnvelope", &dsp_primitives::EnvelopeFollowerNode::getEnvelope,
      "reset", &dsp_primitives::EnvelopeFollowerNode::reset);


  // newLua.new_usertype<dsp_primitives::PitchDetectorNode>(
  //     "PitchDetectorNode",
  //     sol::constructors<std::shared_ptr<dsp_primitives::PitchDetectorNode>(int)>(),
  //     "setWindowSize", &dsp_primitives::PitchDetectorNode::setWindowSize,
  //     "getWindowSize", &dsp_primitives::PitchDetectorNode::getWindowSize,
  //     "setFrequencyRange", &dsp_primitives::PitchDetectorNode::setFrequencyRange,
  //     "setThreshold", &dsp_primitives::PitchDetectorNode::setThreshold,
  //     "setEnabled", &dsp_primitives::PitchDetectorNode::setEnabled,
  //     "isEnabled", &dsp_primitives::PitchDetectorNode::isEnabled,
      // "getFrequency", &dsp_primitives::PitchDetectorNode::getFrequency,
      // "getMidiNote", &dsp_primitives::PitchDetectorNode::getMidiNote,
      // "getNoteName", &dsp_primitives::PitchDetectorNode::getNoteName,
      // "getClarity", &dsp_primitives::PitchDetectorNode::getClarity,
      // "isReliable", &dsp_primitives::PitchDetectorNode::isReliable,
      // "getLastResult", [](const dsp_primitives::PitchDetectorNode& node) {
      //   auto result = node.getLastResult();
      //   return std::make_tuple(result.frequency, result.midiNote, 
      //                          result.centsDeviation, result.clarity, 
      //                          result.isReliable);
      // },
      // "reset", &dsp_primitives::PitchDetectorNode::reset);

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

  newLua.new_usertype<dsp_primitives::EQ8Node>(
      "EQ8Node",
      sol::constructors<std::shared_ptr<dsp_primitives::EQ8Node>()>(),
      "setBandEnabled", &dsp_primitives::EQ8Node::setBandEnabled,
      "setBandType", &dsp_primitives::EQ8Node::setBandType,
      "setBandFreq", &dsp_primitives::EQ8Node::setBandFreq,
      "setBandGain", &dsp_primitives::EQ8Node::setBandGain,
      "setBandQ", &dsp_primitives::EQ8Node::setBandQ,
      "getBandEnabled", &dsp_primitives::EQ8Node::getBandEnabled,
      "getBandType", &dsp_primitives::EQ8Node::getBandType,
      "getBandFreq", &dsp_primitives::EQ8Node::getBandFreq,
      "getBandGain", &dsp_primitives::EQ8Node::getBandGain,
      "getBandQ", &dsp_primitives::EQ8Node::getBandQ,
      "setOutput", &dsp_primitives::EQ8Node::setOutput,
      "setMix", &dsp_primitives::EQ8Node::setMix,
      "getOutput", &dsp_primitives::EQ8Node::getOutput,
      "getMix", &dsp_primitives::EQ8Node::getMix,
      "reset", &dsp_primitives::EQ8Node::reset);

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

  {
    auto reverbApi = sol::state_view(newLuaState).create_table();
    reverbApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ReverbNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto filterApi = sol::state_view(newLuaState).create_table();
    filterApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::FilterNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto distApi = sol::state_view(newLuaState).create_table();
    distApi["new"] = [graph, newLuaState, trackNode]() {
        auto node = std::make_shared<dsp_primitives::DistortionNode>();
        trackNode(node);
        auto t = sol::state_view(newLuaState).create_table();
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
    auto svfApi = sol::state_view(newLuaState).create_table();
    svfApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::SVFNode>();
        trackNode(node);
        return node;
      };
    primitives["SVFNode"] = svfApi;
  }
  {
    auto delayApi = sol::state_view(newLuaState).create_table();
    delayApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::StereoDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["StereoDelayNode"] = delayApi;
  }

  {
    auto compressorApi = sol::state_view(newLuaState).create_table();
    compressorApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::CompressorNode>();
        trackNode(node);
        return node;
      };
    primitives["CompressorNode"] = compressorApi;
  }

  {
    auto waveShaperApi = sol::state_view(newLuaState).create_table();
    waveShaperApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::WaveShaperNode>();
        trackNode(node);
        return node;
      };
    primitives["WaveShaperNode"] = waveShaperApi;
  }

  {
    auto chorusApi = sol::state_view(newLuaState).create_table();
    chorusApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ChorusNode>();
        trackNode(node);
        return node;
      };
    primitives["ChorusNode"] = chorusApi;
  }

  {
    auto widenerApi = sol::state_view(newLuaState).create_table();
    widenerApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::StereoWidenerNode>();
        trackNode(node);
        return node;
      };
    primitives["StereoWidenerNode"] = widenerApi;
  }

  {
    auto phaserApi = sol::state_view(newLuaState).create_table();
    phaserApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::PhaserNode>();
        trackNode(node);
        return node;
      };
    primitives["PhaserNode"] = phaserApi;
  }

  {
    auto granulatorApi = sol::state_view(newLuaState).create_table();
    granulatorApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::GranulatorNode>();
        trackNode(node);
        return node;
      };
    primitives["GranulatorNode"] = granulatorApi;
  }

  {
    auto phaseVocoderApi = sol::state_view(newLuaState).create_table();
    phaseVocoderApi["new"] = [graph, trackNode](int numChannels) {
        auto node = std::make_shared<dsp_primitives::PhaseVocoderNode>(numChannels);
        trackNode(node);
        return node;
      };
    primitives["PhaseVocoderNode"] = phaseVocoderApi;
  }

  {
    auto stutterApi = sol::state_view(newLuaState).create_table();
    stutterApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::StutterNode>();
        trackNode(node);
        return node;
      };
    primitives["StutterNode"] = stutterApi;
  }

  {
    auto shimmerApi = sol::state_view(newLuaState).create_table();
    shimmerApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ShimmerNode>();
        trackNode(node);
        return node;
      };
    primitives["ShimmerNode"] = shimmerApi;
  }

  {
    auto multitapApi = sol::state_view(newLuaState).create_table();
    multitapApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MultitapDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["MultitapDelayNode"] = multitapApi;
  }

  {
    auto pitchShifterApi = sol::state_view(newLuaState).create_table();
    pitchShifterApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::PitchShifterNode>();
        trackNode(node);
        return node;
      };
    primitives["PitchShifterNode"] = pitchShifterApi;
  }

  {
    auto transientShaperApi = sol::state_view(newLuaState).create_table();
    transientShaperApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::TransientShaperNode>();
        trackNode(node);
        return node;
      };
    primitives["TransientShaperNode"] = transientShaperApi;
  }

  {
    auto ringModApi = sol::state_view(newLuaState).create_table();
    ringModApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::RingModulatorNode>();
        trackNode(node);
        return node;
      };
    primitives["RingModulatorNode"] = ringModApi;
  }

  {
    auto bitCrusherApi = sol::state_view(newLuaState).create_table();
    bitCrusherApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::BitCrusherNode>();
        trackNode(node);
        return node;
      };
    primitives["BitCrusherNode"] = bitCrusherApi;
  }

  {
    auto formantApi = sol::state_view(newLuaState).create_table();
    formantApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::FormantFilterNode>();
        trackNode(node);
        return node;
      };
    primitives["FormantFilterNode"] = formantApi;
  }

  {
    auto reverseDelayApi = sol::state_view(newLuaState).create_table();
    reverseDelayApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::ReverseDelayNode>();
        trackNode(node);
        return node;
      };
    primitives["ReverseDelayNode"] = reverseDelayApi;
  }

  {
    auto envelopeApi = sol::state_view(newLuaState).create_table();
    envelopeApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::EnvelopeFollowerNode>();
        trackNode(node);
        return node;
      };
    primitives["EnvelopeFollowerNode"] = envelopeApi;
  }

  {
    auto pitchDetectorApi = sol::state_view(newLuaState).create_table();
    pitchDetectorApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::PitchDetectorNode>();
        trackNode(node);
        return node;
      };
    primitives["PitchDetectorNode"] = pitchDetectorApi;
  }

  {
    auto crossfaderApi = sol::state_view(newLuaState).create_table();
    crossfaderApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::CrossfaderNode>();
        trackNode(node);
        return node;
      };
    primitives["CrossfaderNode"] = crossfaderApi;
  }

  {
    auto mixerApi = sol::state_view(newLuaState).create_table();
    mixerApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MixerNode>();
        trackNode(node);
        return node;
      };
    primitives["MixerNode"] = mixerApi;
  }

  {
    auto noiseApi = sol::state_view(newLuaState).create_table();
    noiseApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::NoiseGeneratorNode>();
        trackNode(node);
        return node;
      };
    primitives["NoiseGeneratorNode"] = noiseApi;
  }

  {
    auto msEncApi = sol::state_view(newLuaState).create_table();
    msEncApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MSEncoderNode>();
        trackNode(node);
        return node;
      };
    primitives["MSEncoderNode"] = msEncApi;
  }

  {
    auto msDecApi = sol::state_view(newLuaState).create_table();
    msDecApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::MSDecoderNode>();
        trackNode(node);
        return node;
      };
    primitives["MSDecoderNode"] = msDecApi;
  }

  {
    auto eqApi = sol::state_view(newLuaState).create_table();
    eqApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::EQNode>();
        trackNode(node);
        return node;
      };
    primitives["EQNode"] = eqApi;
  }

  {
    auto eq8Api = sol::state_view(newLuaState).create_table();
    eq8Api["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::EQ8Node>();
        trackNode(node);
        return node;
      };
    eq8Api["BandType"] = sol::state_view(newLuaState).create_table_with(
        "Peak", static_cast<int>(dsp_primitives::EQ8Node::BandType::Peak),
        "LowShelf", static_cast<int>(dsp_primitives::EQ8Node::BandType::LowShelf),
        "HighShelf", static_cast<int>(dsp_primitives::EQ8Node::BandType::HighShelf),
        "LowPass", static_cast<int>(dsp_primitives::EQ8Node::BandType::LowPass),
        "HighPass", static_cast<int>(dsp_primitives::EQ8Node::BandType::HighPass),
        "Notch", static_cast<int>(dsp_primitives::EQ8Node::BandType::Notch),
        "BandPass", static_cast<int>(dsp_primitives::EQ8Node::BandType::BandPass));
    primitives["EQ8Node"] = eq8Api;
  }

  {
    auto limiterApi = sol::state_view(newLuaState).create_table();
    limiterApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::LimiterNode>();
        trackNode(node);
        return node;
      };
    primitives["LimiterNode"] = limiterApi;
  }

  {
    auto spectrumApi = sol::state_view(newLuaState).create_table();
    spectrumApi["new"] = [graph, trackNode]() {
        auto node = std::make_shared<dsp_primitives::SpectrumAnalyzerNode>();
        trackNode(node);
        return node;
      };
    primitives["SpectrumAnalyzerNode"] = spectrumApi;
  }

}

} // namespace dsp_host

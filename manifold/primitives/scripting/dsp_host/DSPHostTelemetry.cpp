#include "DSPHostInternal.h"

#include "dsp/core/nodes/PrimitiveNodes.h"

#include <algorithm>
#include <iostream>

using dsp_host::sampleDerivedAdditiveDebugFromLua;
using dsp_host::sanitizePath;

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

std::vector<float> DSPPluginScriptHost::getVoiceSamplePositions() const {
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

bool DSPPluginScriptHost::getLatestSampleAnalysis(
    dsp_primitives::SampleAnalysis &outAnalysis) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

  auto node = getGraphNodeByPath("/midi/synth/sample/playback");
  auto playback =
      std::dynamic_pointer_cast<dsp_primitives::SampleRegionPlaybackNode>(node);
  if (playback) {
    auto analysis = playback->getLastAnalysis();
    if (analysis.numSamples <= 0) {
      analysis = playback->analyzeSample();
    }
    if (analysis.numSamples > 0) {
      outAnalysis = std::move(analysis);
      return true;
    }
  }

  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object getAnalysisFn = pImpl->pluginTable["getLatestSampleAnalysis"];
  if (!getAnalysisFn.valid() || getAnalysisFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result = getAnalysisFn.as<sol::function>()();
  if (!result.valid()) {
    return false;
  }

  sol::object analysisObj = result.get<sol::object>();
  if (!analysisObj.valid() || analysisObj.get_type() != sol::type::table) {
    return false;
  }

  sol::table t = analysisObj.as<sol::table>();
  outAnalysis.midiNote = t["midiNote"].get_or(outAnalysis.midiNote);
  outAnalysis.frequency = t["frequency"].get_or(outAnalysis.frequency);
  outAnalysis.confidence = t["confidence"].get_or(outAnalysis.confidence);
  outAnalysis.pitchStability =
      t["pitchStability"].get_or(outAnalysis.pitchStability);
  outAnalysis.isPercussive = t["isPercussive"].get_or(outAnalysis.isPercussive);
  outAnalysis.isReliable = t["reliable"].get_or(outAnalysis.isReliable);
  outAnalysis.rms = t["rms"].get_or(outAnalysis.rms);
  outAnalysis.peak = t["peak"].get_or(outAnalysis.peak);
  outAnalysis.attackTimeMs = t["attackTimeMs"].get_or(outAnalysis.attackTimeMs);
  outAnalysis.attackEndSample =
      t["attackEndSample"].get_or(outAnalysis.attackEndSample);
  outAnalysis.spectralCentroidHz =
      t["spectralCentroidHz"].get_or(outAnalysis.spectralCentroidHz);
  outAnalysis.brightness = t["brightness"].get_or(outAnalysis.brightness);
  outAnalysis.analysisStartSample =
      t["analysisStartSample"].get_or(outAnalysis.analysisStartSample);
  outAnalysis.analysisEndSample =
      t["analysisEndSample"].get_or(outAnalysis.analysisEndSample);
  outAnalysis.numSamples = t["numSamples"].get_or(outAnalysis.numSamples);
  outAnalysis.numChannels = t["numChannels"].get_or(outAnalysis.numChannels);
  outAnalysis.sampleRate = t["sampleRate"].get_or(outAnalysis.sampleRate);
  outAnalysis.algorithm = t["algorithm"].get_or(std::string(outAnalysis.algorithm));
  return outAnalysis.numSamples > 0;
}

bool DSPPluginScriptHost::getLatestSamplePartials(
    dsp_primitives::PartialData &outPartials) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

  auto node = getGraphNodeByPath("/midi/synth/sample/playback");
  auto playback =
      std::dynamic_pointer_cast<dsp_primitives::SampleRegionPlaybackNode>(node);
  if (playback) {
    auto partials = playback->getLastPartials();
    if (partials.numSamples <= 0) {
      partials = playback->extractPartials();
    }
    if (partials.numSamples > 0) {
      outPartials = std::move(partials);
      return true;
    }
  }

  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object getPartialsFn = pImpl->pluginTable["getLatestSamplePartials"];
  if (!getPartialsFn.valid() || getPartialsFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result = getPartialsFn.as<sol::function>()();
  if (!result.valid()) {
    return false;
  }

  sol::object partialsObj = result.get<sol::object>();
  if (!partialsObj.valid() || partialsObj.get_type() != sol::type::table) {
    return false;
  }

  sol::table t = partialsObj.as<sol::table>();
  outPartials.activeCount = t["activeCount"].get_or(outPartials.activeCount);
  outPartials.fundamental = t["fundamental"].get_or(outPartials.fundamental);
  outPartials.inharmonicity = t["inharmonicity"].get_or(outPartials.inharmonicity);
  outPartials.brightness = t["brightness"].get_or(outPartials.brightness);
  outPartials.rmsLevel = t["rmsLevel"].get_or(outPartials.rmsLevel);
  outPartials.peakLevel = t["peakLevel"].get_or(outPartials.peakLevel);
  outPartials.attackTimeMs = t["attackTimeMs"].get_or(outPartials.attackTimeMs);
  outPartials.spectralCentroidHz =
      t["spectralCentroidHz"].get_or(outPartials.spectralCentroidHz);
  outPartials.analysisStartSample =
      t["analysisStartSample"].get_or(outPartials.analysisStartSample);
  outPartials.analysisEndSample =
      t["analysisEndSample"].get_or(outPartials.analysisEndSample);
  outPartials.numSamples = t["numSamples"].get_or(outPartials.numSamples);
  outPartials.numChannels = t["numChannels"].get_or(outPartials.numChannels);
  outPartials.sampleRate = t["sampleRate"].get_or(outPartials.sampleRate);
  outPartials.isPercussive = t["isPercussive"].get_or(outPartials.isPercussive);
  outPartials.isReliable = t["reliable"].get_or(outPartials.isReliable);
  outPartials.algorithm = t["algorithm"].get_or(std::string(outPartials.algorithm));

  sol::object partialEntries = t["partials"];
  if (partialEntries.valid() && partialEntries.get_type() == sol::type::table) {
    sol::table partialTable = partialEntries.as<sol::table>();
    for (int i = 0; i < dsp_primitives::PartialData::kMaxPartials; ++i) {
      sol::object entryObj = partialTable[i + 1];
      if (!entryObj.valid() || entryObj.get_type() != sol::type::table) {
        continue;
      }
      sol::table entry = entryObj.as<sol::table>();
      outPartials.frequencies[static_cast<size_t>(i)] =
          entry["frequency"].get_or(0.0f);
      outPartials.amplitudes[static_cast<size_t>(i)] =
          entry["amplitude"].get_or(0.0f);
      outPartials.phases[static_cast<size_t>(i)] = entry["phase"].get_or(0.0f);
      outPartials.decayRates[static_cast<size_t>(i)] =
          entry["decayRate"].get_or(0.0f);
    }
  }

  return outPartials.numSamples > 0;
}

bool DSPPluginScriptHost::getSampleDerivedAdditiveDebug(
    int voiceIndex,
    SampleDerivedAdditiveDebugState &outState) const {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object getDebugFn = pImpl->pluginTable["getSampleDerivedAddDebug"];
  if (!getDebugFn.valid() || getDebugFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result =
      getDebugFn.as<sol::function>()(voiceIndex);
  if (!result.valid()) {
    return false;
  }

  sol::object stateObj = result.get<sol::object>();
  if (!stateObj.valid() || stateObj.get_type() != sol::type::table) {
    return false;
  }

  return sampleDerivedAdditiveDebugFromLua(stateObj.as<sol::table>(), outState);
}

bool DSPPluginScriptHost::refreshSampleDerivedAdditiveDebug(
    SampleDerivedAdditiveDebugState &outState) {
  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);

  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object refreshFn = pImpl->pluginTable["refreshSampleDerivedAdditive"];
  if (!refreshFn.valid() || refreshFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result = refreshFn.as<sol::function>()();
  if (!result.valid()) {
    return false;
  }

  sol::object stateObj = result.get<sol::object>();
  if (!stateObj.valid() || stateObj.get_type() != sol::type::table) {
    return false;
  }

  return sampleDerivedAdditiveDebugFromLua(stateObj.as<sol::table>(), outState);
}

bool DSPPluginScriptHost::ensureDynamicModuleSlot(const std::string &specId,
                                                  int slotIndex) {
  if (specId.empty() || slotIndex <= 0) {
    return false;
  }

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  if (!pImpl->pluginTable.valid()) {
    return false;
  }

  sol::object ensureFn = pImpl->pluginTable["ensureDynamicModuleSlot"];
  if (!ensureFn.valid() || ensureFn.get_type() != sol::type::function) {
    return false;
  }

  sol::protected_function_result result =
      ensureFn.as<sol::function>()(specId, slotIndex);
  if (!result.valid()) {
    sol::error err = result;
    juce::Logger::writeToLog("DSPPluginScriptHost::ensureDynamicModuleSlot failed: " + juce::String(err.what()));
    std::cerr << "DSPPluginScriptHost::ensureDynamicModuleSlot failed: " << err.what() << std::endl;
    return false;
  }

  if (result.return_count() <= 0) {
    return true;
  }

  sol::object out = result.get<sol::object>();
  if (!out.valid()) {
    return false;
  }
  if (out.is<bool>()) {
    return out.as<bool>();
  }
  if (out.is<int>()) {
    return out.as<int>() != 0;
  }
  if (out.is<double>()) {
    return out.as<double>() != 0.0;
  }
  return true;
}

std::array<float, 8> DSPPluginScriptHost::getSpectrumBands() const {
  std::array<float, 8> bands{};

  const std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
  for (const auto &node : pImpl->ownedNodes) {
    auto spectrum =
        std::dynamic_pointer_cast<dsp_primitives::SpectrumAnalyzerNode>(node);
    if (!spectrum) {
      continue;
    }

    const std::array<float, 8> current = {
        spectrum->getBand1(), spectrum->getBand2(), spectrum->getBand3(),
        spectrum->getBand4(), spectrum->getBand5(), spectrum->getBand6(),
        spectrum->getBand7(), spectrum->getBand8(),
    };

    for (size_t i = 0; i < bands.size(); ++i) {
      bands[i] = std::max(bands[i], current[i]);
    }
  }

  return bands;
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

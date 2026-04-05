#include "DSPHostInternal.h"

#include "dsp/core/nodes/PitchDetector.h"
#include "dsp/core/nodes/TemporalPartialData.h"

namespace dsp_host {

sol::table sampleAnalysisToLua(sol::this_state ts,
                               const dsp_primitives::SampleAnalysis &analysis) {
  sol::state_view lua(ts);
  sol::table result(lua, sol::create);
  result["midiNote"] = analysis.midiNote;
  result["frequency"] = analysis.frequency;
  result["confidence"] = analysis.confidence;
  result["pitchStability"] = analysis.pitchStability;
  result["attackEndSample"] = analysis.attackEndSample;
  result["analysisStartSample"] = analysis.analysisStartSample;
  result["analysisEndSample"] = analysis.analysisEndSample;
  result["isPercussive"] = analysis.isPercussive;
  result["reliable"] = analysis.isReliable;
  result["rms"] = analysis.rms;
  result["peak"] = analysis.peak;
  result["attackTimeMs"] = analysis.attackTimeMs;
  result["spectralCentroidHz"] = analysis.spectralCentroidHz;
  result["brightness"] = analysis.brightness;
  result["numSamples"] = analysis.numSamples;
  result["numChannels"] = analysis.numChannels;
  result["sampleRate"] = analysis.sampleRate;
  result["algorithm"] = analysis.algorithm;
  result["noteName"] =
      (analysis.frequency > 0.0f)
          ? dsp_primitives::PitchDetector::frequencyToNoteName(analysis.frequency)
          : std::string("--");
  return result;
}

sol::table partialDataToLua(sol::this_state ts,
                            const dsp_primitives::PartialData &partials) {
  sol::state_view lua(ts);
  sol::table result(lua, sol::create);
  result["activeCount"] = partials.activeCount;
  result["fundamental"] = partials.fundamental;
  result["inharmonicity"] = partials.inharmonicity;
  result["brightness"] = partials.brightness;
  result["rmsLevel"] = partials.rmsLevel;
  result["peakLevel"] = partials.peakLevel;
  result["attackTimeMs"] = partials.attackTimeMs;
  result["spectralCentroidHz"] = partials.spectralCentroidHz;
  result["analysisStartSample"] = partials.analysisStartSample;
  result["analysisEndSample"] = partials.analysisEndSample;
  result["numSamples"] = partials.numSamples;
  result["numChannels"] = partials.numChannels;
  result["sampleRate"] = partials.sampleRate;
  result["isPercussive"] = partials.isPercussive;
  result["reliable"] = partials.isReliable;
  result["algorithm"] = partials.algorithm;

  sol::table frequencyTable(lua, sol::create);
  sol::table amplitudeTable(lua, sol::create);
  sol::table phaseTable(lua, sol::create);
  sol::table decayTable(lua, sol::create);
  sol::table partialTable(lua, sol::create);

  for (int i = 0;
       i < partials.activeCount && i < dsp_primitives::PartialData::kMaxPartials;
       ++i) {
    const int luaIndex = i + 1;
    frequencyTable[luaIndex] = partials.frequencies[static_cast<size_t>(i)];
    amplitudeTable[luaIndex] = partials.amplitudes[static_cast<size_t>(i)];
    phaseTable[luaIndex] = partials.phases[static_cast<size_t>(i)];
    decayTable[luaIndex] = partials.decayRates[static_cast<size_t>(i)];

    sol::table entry(lua, sol::create);
    entry["index"] = luaIndex;
    entry["harmonic"] = luaIndex;
    entry["frequency"] = partials.frequencies[static_cast<size_t>(i)];
    entry["amplitude"] = partials.amplitudes[static_cast<size_t>(i)];
    entry["phase"] = partials.phases[static_cast<size_t>(i)];
    entry["decayRate"] = partials.decayRates[static_cast<size_t>(i)];
    partialTable[luaIndex] = entry;
  }

  result["frequencies"] = frequencyTable;
  result["amplitudes"] = amplitudeTable;
  result["phases"] = phaseTable;
  result["decayRates"] = decayTable;
  result["partials"] = partialTable;
  return result;
}

sol::table temporalPartialDataToLua(
    sol::this_state ts,
    const dsp_primitives::TemporalPartialData &temporal) {
  sol::state_view lua(ts);
  sol::table result(lua, sol::create);
  result["frameCount"] = temporal.frameCount;
  result["sampleRate"] = temporal.sampleRate;
  result["sampleLengthSeconds"] = temporal.sampleLengthSeconds;
  result["globalFundamental"] = temporal.globalFundamental;
  result["windowSize"] = temporal.windowSize;
  result["hopSize"] = temporal.hopSize;
  result["reliable"] = temporal.isReliable;

  sol::table framesTable(lua, sol::create);
  sol::table frameTimesTable(lua, sol::create);
  for (int i = 0; i < temporal.frameCount &&
                  i < static_cast<int>(temporal.frames.size());
       ++i) {
    const int luaIndex = i + 1;
    framesTable[luaIndex] =
        partialDataToLua(ts, temporal.frames[static_cast<size_t>(i)]);
    if (i < static_cast<int>(temporal.frameTimes.size())) {
      frameTimesTable[luaIndex] = temporal.frameTimes[static_cast<size_t>(i)];
    }
  }
  result["frames"] = framesTable;
  result["frameTimes"] = frameTimesTable;
  return result;
}

sol::table sampleDerivedAdditiveDebugToLua(
    sol::this_state ts,
    const SampleDerivedAdditiveDebugState &state) {
  sol::state_view lua(ts);
  sol::table result(lua, sol::create);
  result["enabled"] = state.enabled;
  result["ready"] = state.ready;
  result["mix"] = state.mix;
  result["voiceAmp"] = state.voiceAmp;
  result["gate"] = state.gate;
  result["targetFrequency"] = state.targetFrequency;
  result["busMix"] = state.busMix;
  result["activeCount"] = state.activeCount;
  result["fundamental"] = state.fundamental;
  result["referenceNote"] = state.referenceNote;
  result["blendSampleSpeed"] = state.blendSampleSpeed;
  result["addCrossfadePosition"] = state.addCrossfadePosition;
  result["addBranchGain"] = state.addBranchGain;
  result["sampleAdditiveGain"] = state.sampleAdditiveGain;
  result["branchGain1"] = state.branchGain1;
  result["branchGain2"] = state.branchGain2;
  result["branchGain3"] = state.branchGain3;
  result["waveform"] = state.waveform;
  result["waveFrequency"] = state.waveFrequency;
  return result;
}

bool sampleDerivedAdditiveDebugFromLua(const sol::table &t,
                                       SampleDerivedAdditiveDebugState &outState) {
  outState.enabled = t["enabled"].get_or(outState.enabled);
  outState.ready = t["ready"].get_or(outState.ready);
  outState.mix = t["mix"].get_or(outState.mix);
  outState.voiceAmp = t["voiceAmp"].get_or(outState.voiceAmp);
  outState.gate = t["gate"].get_or(outState.gate);
  outState.targetFrequency = t["targetFrequency"].get_or(outState.targetFrequency);
  outState.busMix = t["busMix"].get_or(outState.busMix);
  outState.activeCount = t["activeCount"].get_or(outState.activeCount);
  outState.fundamental = t["fundamental"].get_or(outState.fundamental);
  outState.referenceNote = t["referenceNote"].get_or(outState.referenceNote);
  outState.blendSampleSpeed =
      t["blendSampleSpeed"].get_or(outState.blendSampleSpeed);
  outState.addCrossfadePosition =
      t["addCrossfadePosition"].get_or(outState.addCrossfadePosition);
  outState.addBranchGain = t["addBranchGain"].get_or(outState.addBranchGain);
  outState.sampleAdditiveGain =
      t["sampleAdditiveGain"].get_or(outState.sampleAdditiveGain);
  outState.branchGain1 = t["branchGain1"].get_or(outState.branchGain1);
  outState.branchGain2 = t["branchGain2"].get_or(outState.branchGain2);
  outState.branchGain3 = t["branchGain3"].get_or(outState.branchGain3);
  outState.waveform = t["waveform"].get_or(outState.waveform);
  outState.waveFrequency = t["waveFrequency"].get_or(outState.waveFrequency);
  return true;
}

} // namespace dsp_host

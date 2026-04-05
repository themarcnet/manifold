#pragma once

#include <juce_core/juce_core.h>

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "ScriptableProcessor.h"
#include "dsp/core/nodes/PartialData.h"
#include "dsp/core/nodes/SampleAnalysis.h"

namespace dsp_primitives {
class GainNode;
class IPrimitiveNode;
}

class DSPPluginScriptHost {
public:
  DSPPluginScriptHost();
  ~DSPPluginScriptHost();

  void initialise(ScriptableProcessor *processor,
                  const std::string &namespaceBase = "/core/behavior");

  bool loadScript(const juce::File &scriptFile);
  bool loadScriptFromString(const std::string &luaCode,
                            const std::string &sourceName = "in_memory");
  bool reloadCurrentScript();

  bool isLoaded() const;
  void markUnloaded();
  const std::string &getLastError() const;
  juce::File getCurrentScriptFile() const;

  bool hasParam(const std::string &path) const;
  bool setParam(const std::string &path, float value);
  float getParam(const std::string &path) const;
  int getLayerLoopLength(int layerIndex) const;
  bool isLayerMuted(int layerIndex) const;
  bool computeLayerPeaks(int layerIndex, int numBuckets,
                         std::vector<float> &outPeaks) const;
  bool computeSynthSamplePeaks(int numBuckets,
                               std::vector<float> &outPeaks) const;
  std::vector<float> getVoiceSamplePositions() const;
  bool getLatestSampleAnalysis(dsp_primitives::SampleAnalysis &outAnalysis) const;
  bool getLatestSamplePartials(dsp_primitives::PartialData &outPartials) const;
  bool getSampleDerivedAdditiveDebug(int voiceIndex,
                                     SampleDerivedAdditiveDebugState &outState) const;
  bool refreshSampleDerivedAdditiveDebug(SampleDerivedAdditiveDebugState &outState);
  bool ensureDynamicModuleSlot(const std::string &specId, int slotIndex);
  std::array<float, 8> getSpectrumBands() const;

  std::shared_ptr<dsp_primitives::IPrimitiveNode>
  getGraphNodeByPath(const std::string &path) const;
  std::shared_ptr<dsp_primitives::IPrimitiveNode>
  getLayerOutputNode(int layerIndex) const;

  // Call the script's process callback (if any) - called from audio thread
  void process(int blockSize, double sampleRate);

private:
  bool loadScriptImpl(const std::string &sourceName, const juce::File *scriptFile,
                      const std::string *scriptCode);
  bool compileRuntimeAndRequestSwap(const std::string &reason);
  bool applyDeferredGraphMutation(const std::string &path, float normalized);
  bool enqueueDeferredGraphMutation(const std::string &path, float normalized);
  void ensureDeferredWorkerStarted();
  void stopDeferredWorker();

  struct Impl;
  std::unique_ptr<Impl> pImpl;
};

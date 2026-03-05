#pragma once

#include <juce_core/juce_core.h>

#include <memory>
#include <string>
#include <vector>

class ScriptableProcessor;

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
  const std::string &getLastError() const;
  juce::File getCurrentScriptFile() const;

  bool hasParam(const std::string &path) const;
  bool setParam(const std::string &path, float value);
  float getParam(const std::string &path) const;
  int getLayerLoopLength(int layerIndex) const;
  bool isLayerMuted(int layerIndex) const;
  bool computeLayerPeaks(int layerIndex, int numBuckets,
                         std::vector<float> &outPeaks) const;
  std::shared_ptr<dsp_primitives::IPrimitiveNode>
  getGraphNodeByPath(const std::string &path) const;
  std::shared_ptr<dsp_primitives::IPrimitiveNode>
  getLayerOutputNode(int layerIndex) const;

private:
  bool loadScriptImpl(const std::string &sourceName, const juce::File *scriptFile,
                      const std::string *scriptCode);

  struct Impl;
  std::unique_ptr<Impl> pImpl;
};

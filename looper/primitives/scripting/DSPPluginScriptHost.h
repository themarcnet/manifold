#pragma once

#include <juce_core/juce_core.h>

#include <memory>
#include <string>

class LooperProcessor;

class DSPPluginScriptHost {
public:
  DSPPluginScriptHost();
  ~DSPPluginScriptHost();

  void initialise(LooperProcessor *processor);

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

private:
  bool loadScriptImpl(const std::string &sourceName, const juce::File *scriptFile,
                      const std::string *scriptCode);

  struct Impl;
  std::unique_ptr<Impl> pImpl;
};

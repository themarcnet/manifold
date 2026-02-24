#pragma once

#include "../engine/LooperProcessor.h"
#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/ui/Canvas.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

class LooperEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
  LooperEditor(LooperProcessor &p);
  ~LooperEditor() override = default;

  void paint(juce::Graphics &g) override;
  void resized() override;

private:
  void timerCallback() override;
  void showError(const std::string &message);

  LooperProcessor &processor;
  LuaEngine luaEngine;
  bool usingLuaUi = false;

  Canvas rootCanvas{"root"};
  Canvas *errorNode = nullptr;
  std::string errorMessage;

  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LooperEditor)
};

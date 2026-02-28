#pragma once

#include "../../looper/primitives/scripting/LuaEngine.h"
#include "../../looper/primitives/ui/Canvas.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

// Forward declaration
class TempusPlugin;

class TempusEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
    TempusEditor(juce::AudioProcessor* ownerProcessor, TempusPlugin& plugin);
    ~TempusEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;
    void timerCallback() override;

private:
    TempusPlugin& processorRef;
    Canvas rootCanvas{"root"};
    LuaEngine luaEngine;
    
    bool usingLuaUi = false;
    std::string errorMessage;
    Canvas* errorNode = nullptr;
    
    void showError(const std::string& message);
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TempusEditor)
};

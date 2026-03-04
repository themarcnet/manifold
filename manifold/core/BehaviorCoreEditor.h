#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/ui/Canvas.h"

class BehaviorCoreProcessor;

class BehaviorCoreEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
    explicit BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor);
    ~BehaviorCoreEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;

private:
    void timerCallback() override;
    void showError(const std::string& message);

    BehaviorCoreProcessor& processorRef;
    LuaEngine luaEngine;
    bool usingLuaUi = false;

    Canvas rootCanvas{"root"};
    Canvas* errorNode = nullptr;
    std::string errorMessage;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BehaviorCoreEditor)
};

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/ui/Canvas.h"
#include "../ui/imgui/ImGuiHost.h"
#include "../ui/imgui/ImGuiScriptListHost.h"
#include "../ui/imgui/ImGuiHierarchyHost.h"
#include "../ui/imgui/ImGuiInspectorHost.h"
#include "../ui/imgui/ImGuiPerfOverlayHost.h"

class BehaviorCoreProcessor;

class BehaviorCoreEditor : public juce::AudioProcessorEditor, private juce::Timer {
public:
    explicit BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor);
    ~BehaviorCoreEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;

private:
    void timerCallback() override;
    void syncImGuiHostsFromLuaShell();
    void showError(const std::string& message);

    // Deferred visibility changes to avoid blocking GUI thread during OpenGL context creation
    struct DeferredVisibility {
        juce::Component* host;
        bool visible;
        juce::Rectangle<int> bounds;
    };
    std::vector<DeferredVisibility> deferredVisibilityChanges;
    void applyDeferredVisibilityChanges();
    void queueHostVisibilityChange(juce::Component& host, bool visible, const juce::Rectangle<int>& bounds);

    BehaviorCoreProcessor& processorRef;
    LuaEngine luaEngine;
    bool usingLuaUi = false;

    Canvas rootCanvas{"root"};
    ImGuiHost mainScriptEditorHost;
    ImGuiScriptListHost scriptListHost;
    ImGuiHierarchyHost hierarchyHost;
    ImGuiInspectorHost inspectorHost;
    ImGuiInspectorHost scriptInspectorHost;
    ImGuiPerfOverlayHost perfOverlayHost;
    Canvas* errorNode = nullptr;
    std::string errorMessage;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BehaviorCoreEditor)
};
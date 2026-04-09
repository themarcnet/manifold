#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "../primitives/scripting/LuaEngine.h"
#include "../primitives/ui/Canvas.h"
#include "../primitives/ui/RuntimeNode.h"
#include "../ui/imgui/ImGuiHost.h"
#include "../ui/imgui/ImGuiScriptListHost.h"
#include "../ui/imgui/ImGuiHierarchyHost.h"
#include "../ui/imgui/ImGuiInspectorHost.h"
#include "../ui/imgui/ImGuiPerfOverlayHost.h"
#include "../ui/imgui/ImGuiRuntimeNodeHost.h"
#include "../ui/imgui/ImGuiDirectHost.h"

#include <memory>

class BehaviorCoreProcessor;

class BehaviorCoreEditor : public juce::AudioProcessorEditor,
                           private juce::Timer {
public:
    enum class RootMode {
        Canvas = 0,
        RuntimeNode = 1,
    };

    explicit BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor,
                                RootMode rootMode = RootMode::RuntimeNode);
    ~BehaviorCoreEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;
    bool keyPressed(const juce::KeyPress& key) override;

private:
    enum class RuntimeRendererMode {
        Canvas = 0,
        ImGuiOverlay = 1,
        ImGuiReplace = 2,
        ImGuiDirect = 3,
    };

    void timerCallback() override;
    void syncImGuiHostsFromLuaShell();
    void showError(const std::string& message);
    RuntimeNode* getActiveRootRuntimeNode();
    void setRuntimeRendererMode(RuntimeRendererMode mode, bool logChange = true);
    void updateRuntimeRendererPresentation();
    static RuntimeRendererMode runtimeRendererModeFromString(const std::string& value,
                                                            RuntimeRendererMode fallback);
    static const char* runtimeRendererModeToString(RuntimeRendererMode mode);
    
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
    RootMode rootMode_ = RootMode::RuntimeNode;

    Canvas rootCanvas{"root"};
    std::unique_ptr<RuntimeNode> rootRuntime_;
    ImGuiHost mainScriptEditorHost;
    ImGuiScriptListHost scriptListHost;
    ImGuiHierarchyHost hierarchyHost;
    ImGuiInspectorHost inspectorHost;
    ImGuiInspectorHost scriptInspectorHost;
    ImGuiPerfOverlayHost perfOverlayHost;
    ImGuiRuntimeNodeHost runtimeNodeDebugHost;
    ImGuiDirectHost directHost_;
    bool directHostNeedsInitialFocus_ = false;
    RuntimeRendererMode runtimeRendererMode_ = RuntimeRendererMode::ImGuiDirect;
    bool exportPluginUi_ = false;
    Canvas* errorNode = nullptr;
    std::string errorMessage;

    // CPU tracking
    std::chrono::steady_clock::time_point lastCpuCheck_{};
    std::chrono::microseconds lastCpuTime_{0};
    bool uiIdleSnapshotCaptured_ = false;
    int uiIdleSnapshotCountdown_ = 40;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(BehaviorCoreEditor)
};

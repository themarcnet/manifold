#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include "RuntimeNodeRenderer.h"
#include "../../primitives/ui/RuntimeNode.h"

#include <functional>
#include <memory>
#include <mutex>
#include <string>

class ImGuiRuntimeNodeHost : public juce::Component,
                             private juce::OpenGLRenderer,
                             private juce::AsyncUpdater {
public:
    using PreviewTransform = manifold::ui::imgui::RuntimeNodeRenderer::PreviewTransform;
    using Snapshot = manifold::ui::imgui::RuntimeNodeRenderer::Snapshot;
    using HitTestResult = manifold::ui::imgui::RuntimeNodeRenderer::HitTestResult;

    enum class PresentationMode {
        DebugPreview,
        Replace
    };

    ImGuiRuntimeNodeHost();
    ~ImGuiRuntimeNodeHost() override;

    void setRootNode(const RuntimeNode* root);
    void setPresentationMode(PresentationMode mode);
    void setUseLiveTree(bool useLiveTree);
    bool isUsingLiveTree() const;
    void setOnExitRequested(std::function<void()> fn);
    const RuntimeNode* getRootNode() const;
    void refreshSnapshotNow();

    std::string getSelectedNodeId() const;
    std::string getHoveredNodeId() const;

    void paint(juce::Graphics& g) override;
    void resized() override;
    void visibilityChanged() override;
    void parentHierarchyChanged() override;

    void mouseMove(const juce::MouseEvent& e) override;
    void mouseDrag(const juce::MouseEvent& e) override;
    void mouseDown(const juce::MouseEvent& e) override;
    void mouseUp(const juce::MouseEvent& e) override;
    void mouseExit(const juce::MouseEvent& e) override;
    void mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) override;
    bool keyPressed(const juce::KeyPress& key) override;

private:
    void newOpenGLContextCreated() override;
    void renderOpenGL() override;
    void openGLContextClosing() override;
    void handleAsyncUpdate() override;

    void attachContextIfNeeded();
    void refreshSnapshotIfNeeded();
    void updateHover(juce::Point<float> position, const juce::ModifierKeys* mods = nullptr);

    HitTestResult hitTestNode(juce::Point<float> position,
                              manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode mode = manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer) const;
    juce::Point<float> scenePositionFromPreview(juce::Point<float> position) const;
    RuntimeNode* findLiveNodeByStableId(uint64_t stableId) const;
    RuntimeNode* findLiveWheelTarget(uint64_t stableId) const;
    void setLiveFocus(uint64_t stableId);
    void invokeLiveMouseDown(uint64_t stableId, juce::Point<float> localPosition, const juce::ModifierKeys& mods);
    void invokeLiveMouseDrag(uint64_t stableId, juce::Point<float> localPosition, juce::Point<float> dragDelta, const juce::ModifierKeys& mods);
    void invokeLiveMouseUp(uint64_t stableId, juce::Point<float> localPosition, bool triggerClick, bool triggerDoubleClick, const juce::ModifierKeys& mods);
    void invokeLiveMouseMove(uint64_t stableId, juce::Point<float> localPosition, const juce::ModifierKeys& mods);
    void invokeLiveMouseEnter(uint64_t stableId);
    void invokeLiveMouseExit(uint64_t stableId);
    void invokeLiveMouseWheel(uint64_t stableId, juce::Point<float> scenePosition, float deltaY, const juce::ModifierKeys& mods);

    juce::OpenGLContext openGLContext;
    void* imguiContext = nullptr;
    manifold::ui::imgui::RuntimeNodeRenderer renderer_;

    mutable std::mutex dataMutex_;
    const RuntimeNode* liveRoot_ = nullptr;
    std::shared_ptr<const Snapshot> snapshot_;
    PreviewTransform previewTransform_;
    uint64_t selectedNodeStableId_ = 0;
    uint64_t hoveredNodeStableId_ = 0;
    uint64_t pressedNodeStableId_ = 0;
    std::string selectedNodeId_;
    std::string hoveredNodeId_;
    PresentationMode presentationMode_ = PresentationMode::DebugPreview;
    std::function<void()> onExitRequested_;
    bool useLiveTree_ = false;
    uint64_t snapshotStructureVersion_ = 0;
    uint64_t snapshotPropsVersion_ = 0;
    uint64_t snapshotRenderVersion_ = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiRuntimeNodeHost)
};

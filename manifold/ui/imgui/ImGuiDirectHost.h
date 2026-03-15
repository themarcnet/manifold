#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_opengl/juce_opengl.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <juce_core/juce_core.h>

#include "RuntimeNodeRenderer.h"
#include "../../primitives/ui/RuntimeNode.h"

class ImGuiDirectHost : public juce::Component,
                        private juce::OpenGLRenderer {
public:
    using PreviewTransform = manifold::ui::imgui::RuntimeNodeRenderer::PreviewTransform;

    struct StatsSnapshot {
        bool contextReady = false;
        bool testWindowVisible = false;
        bool wantCaptureMouse = false;
        bool wantCaptureKeyboard = false;
        bool documentLoaded = false;
        bool documentDirty = false;
        int64_t frameCount = 0;
        int64_t lastRenderUs = 0;
        int64_t lastVertexCount = 0;
        int64_t lastIndexCount = 0;
        int64_t buttonClicks = 0;
        int64_t documentLineCount = 0;
    };

    using GlobalKeyHandler = std::function<bool(const juce::KeyPress&)>;

    struct PendingDragEvent {
        bool valid = false;
        uint64_t stableId = 0;
        juce::Point<float> localPosition;
        juce::Point<float> dragDelta;
        juce::ModifierKeys mods;
    };

    struct RenderNodeData {
        juce::Rectangle<int> sceneBounds;
        RuntimeNode::StyleState style;
        bool visible = true;
        bool hasClipRect = false;
        juce::Rectangle<int> clipRect;
        int zOrder = 0;
        uint64_t stableId = 0;
        std::shared_ptr<const manifold::ui::imgui::CompiledDisplayList> compiledDisplayList;
        std::string customSurfaceType;
        juce::var customRenderPayload;
        std::vector<int> childIndices;
    };

    struct RenderSnapshot {
        PreviewTransform transform;
        std::vector<RenderNodeData> nodes;
        int rootIndex = -1;
    };

    ImGuiDirectHost();
    ~ImGuiDirectHost() override;

    StatsSnapshot getStatsSnapshot() const;
    void setGlobalKeyHandler(GlobalKeyHandler handler);
    void setRootNode(RuntimeNode* root);
    void buildRenderSnapshot();
    void renderNow();
    void shutdown();
    std::uintptr_t prepareCustomSurfaceTexture(const RuntimeNode& node,
                                              int width,
                                              int height,
                                              double timeSeconds);

public:
    struct ShaderSurfaceState;

private:
    void resized() override;
    void visibilityChanged() override;
    void parentHierarchyChanged() override;

public:
    void setVisible(bool shouldBeVisible) override;

    void mouseDown(const juce::MouseEvent&) override;
    void mouseDrag(const juce::MouseEvent&) override;
    void mouseUp(const juce::MouseEvent&) override;
    void mouseMove(const juce::MouseEvent&) override;
    void mouseExit(const juce::MouseEvent&) override;
    void mouseWheelMove(const juce::MouseEvent&, const juce::MouseWheelDetails&) override;
    bool keyPressed(const juce::KeyPress&) override;

    void newOpenGLContextCreated() override;
    void renderOpenGL() override;
    void openGLContextClosing() override;

    void attachContextIfNeeded();
    void updateHover(juce::Point<float> position, const juce::ModifierKeys* mods = nullptr);
    void flushPendingDrag();

    manifold::ui::imgui::RuntimeNodeRenderer::HitTestResult hitTestLiveTree(juce::Point<float> position,
                                                                            manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode mode = manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    juce::Point<float> scenePositionFromLocal(juce::Point<float> local);
    RuntimeNode* findLiveNodeByStableId(uint64_t stableId) const;
    RuntimeNode* findLiveWheelTarget(RuntimeNode* node) const;
    void setLiveFocus(uint64_t stableId);
    void invokeLiveMouseDown(RuntimeNode& node, juce::Point<float> localPosition, const juce::ModifierKeys& mods);
    void invokeLiveMouseDrag(RuntimeNode& node, juce::Point<float> localPosition, juce::Point<float> dragDelta, const juce::ModifierKeys& mods);
    void invokeLiveMouseUp(RuntimeNode& node, juce::Point<float> localPosition, bool triggerClick, bool triggerDoubleClick, const juce::ModifierKeys& mods);
    void invokeLiveMouseMove(RuntimeNode& node, juce::Point<float> localPosition, const juce::ModifierKeys& mods);
    void invokeLiveMouseEnter(uint64_t stableId);
    void invokeLiveMouseExit(uint64_t stableId);
    void invokeLiveMouseWheel(RuntimeNode& node, juce::Point<float> scenePosition, float deltaY, const juce::ModifierKeys& mods);

    RuntimeNode* liveRoot_ = nullptr;
    uint64_t pressedNodeStableId_ = 0;
    uint64_t hoveredNodeStableId_ = 0;
    uint64_t focusedNodeStableId_ = 0;

    juce::OpenGLContext openGLContext_;
    void* imguiContext_ = nullptr;
    bool contextReady_ = false;
    GlobalKeyHandler globalKeyHandler_;

    std::atomic<bool> wantCaptureMouse_{false};
    std::atomic<bool> wantCaptureKeyboard_{false};
    std::atomic<int64_t> frameCount_{0};
    std::atomic<int64_t> lastRenderUs_{0};
    std::atomic<int64_t> lastVertexCount_{0};
    std::atomic<int64_t> lastIndexCount_{0};

    manifold::ui::imgui::RuntimeNodeRenderer renderer_;
    manifold::ui::imgui::RuntimeNodeRenderer::PreviewTransform previewTransform_;
    PendingDragEvent pendingDragEvent_;
    double lastContinuousInputDispatchMs_ = 0.0;
    RenderSnapshot pendingSnapshot_;
    RenderSnapshot activeSnapshot_;
    RenderSnapshot glSnapshot_;
    std::mutex snapshotMutex_;
    std::atomic<bool> snapshotReady_{false};

    std::unordered_map<uint64_t, std::unique_ptr<ShaderSurfaceState>> shaderSurfaceStates_;
    unsigned int surfaceQuadVao_ = 0;
    unsigned int surfaceQuadVbo_ = 0;
    unsigned int surfaceQuadIbo_ = 0;

    bool ensureSurfaceQuadGeometry();
    void releaseSurfaceQuadGeometry();
    void releaseShaderSurfaces();
    void pruneShaderSurfaces(const std::unordered_set<uint64_t>& touchedStableIds);

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ImGuiDirectHost)
};

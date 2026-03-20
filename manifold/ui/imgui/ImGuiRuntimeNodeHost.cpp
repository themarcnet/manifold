#include "ImGuiRuntimeNodeHost.h"

#include "Theme.h"
#include "backends/imgui_impl_opengl3.h"
#include "imgui.h"

#include <algorithm>
#include <cstdio>

using namespace juce::gl;

namespace {

bool isCtrlLikeDown(const juce::ModifierKeys& mods) {
    return mods.isCtrlDown() || mods.isCommandDown();
}

template <typename... Args>
void invokeLuaCallback(sol::function& fn, const char* label, const std::string& nodeId, Args&&... args) {
    if (!fn.valid()) {
        return;
    }

    sol::protected_function protectedFn = fn;
    auto result = protectedFn(std::forward<Args>(args)...);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "[RuntimeNodeHost] %s error for %s: %s\n",
                     label,
                     nodeId.c_str(),
                     err.what());
    }
}

const RuntimeNode* findNodeRecursive(const RuntimeNode& node, const std::string& nodeId) {
    if (node.getNodeId() == nodeId) {
        return &node;
    }
    for (auto* child : node.getChildren()) {
        if (child == nullptr) {
            continue;
        }
        if (const auto* match = findNodeRecursive(*child, nodeId)) {
            return match;
        }
    }
    return nullptr;
}

const RuntimeNode* findNodeByStableIdRecursive(const RuntimeNode& node, uint64_t stableId) {
    if (node.getStableId() == stableId) {
        return &node;
    }
    for (auto* child : node.getChildren()) {
        if (child == nullptr) {
            continue;
        }
        if (const auto* match = findNodeByStableIdRecursive(*child, stableId)) {
            return match;
        }
    }
    return nullptr;
}

void clearFocusRecursive(RuntimeNode& node) {
    node.setFocused(false);
    for (auto* child : node.getChildren()) {
        if (child != nullptr) {
            clearFocusRecursive(*child);
        }
    }
}

manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions makeRenderOptions(ImGuiRuntimeNodeHost::PresentationMode mode) {
    manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions options;
    if (mode == ImGuiRuntimeNodeHost::PresentationMode::Replace) {
        options.leftPad = 0.0f;
        options.rightPad = 0.0f;
        options.topPad = 0.0f;
        options.bottomPad = 0.0f;
        options.fitToView = false;
        options.showFallbackBoxes = false;
        options.showNodeLabels = false;
        options.showSurfaceLabels = false;
        options.showHoveredOutline = false;
        options.showSelectedOutline = false;
    }
    return options;
}

juce::Rectangle<int> findSceneBoundsRecursive(const RuntimeNode& node,
                                              const std::string& nodeId,
                                              juce::Point<int> parentOffset,
                                              bool& found) {
    const auto& b = node.getBounds();
    const juce::Rectangle<int> bounds(parentOffset.x + b.x, parentOffset.y + b.y, b.w, b.h);
    if (node.getNodeId() == nodeId) {
        found = true;
        return bounds;
    }

    for (auto* child : node.getChildren()) {
        if (child == nullptr) {
            continue;
        }
        auto childBounds = findSceneBoundsRecursive(*child,
                                                    nodeId,
                                                    juce::Point<int>(bounds.getX(), bounds.getY()),
                                                    found);
        if (found) {
            return childBounds;
        }
    }

    return {};
}

juce::Rectangle<int> findSceneBoundsByStableIdRecursive(const RuntimeNode& node,
                                                        uint64_t stableId,
                                                        juce::Point<int> parentOffset,
                                                        bool& found) {
    const auto& b = node.getBounds();
    const juce::Rectangle<int> bounds(parentOffset.x + b.x, parentOffset.y + b.y, b.w, b.h);
    if (node.getStableId() == stableId) {
        found = true;
        return bounds;
    }

    for (auto* child : node.getChildren()) {
        if (child == nullptr) {
            continue;
        }
        auto childBounds = findSceneBoundsByStableIdRecursive(*child,
                                                              stableId,
                                                              juce::Point<int>(bounds.getX(), bounds.getY()),
                                                              found);
        if (found) {
            return childBounds;
        }
    }

    return {};
}

} // namespace

ImGuiRuntimeNodeHost::ImGuiRuntimeNodeHost() {
    setOpaque(true);
    setWantsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);

    openGLContext.setRenderer(this);
    openGLContext.setComponentPaintingEnabled(false);
#ifndef __ANDROID__
    openGLContext.setPersistentAttachment(true);
#endif
    openGLContext.setContinuousRepainting(true);
    openGLContext.setSwapInterval(1);
}

ImGuiRuntimeNodeHost::~ImGuiRuntimeNodeHost() {
    openGLContext.detach();
}

void ImGuiRuntimeNodeHost::setRootNode(const RuntimeNode* root) {
    std::shared_ptr<const Snapshot> snapshot = renderer_.makeSnapshot(root);
    PreviewTransform transform;
    PresentationMode presentationMode = PresentationMode::DebugPreview;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        presentationMode = presentationMode_;
    }

    if (snapshot && snapshot->root != nullptr && getWidth() > 0 && getHeight() > 0) {
        transform = renderer_.buildPreviewTransform(*snapshot->root,
                                                    getWidth(),
                                                    getHeight(),
                                                    makeRenderOptions(presentationMode));
    }

    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        liveRoot_ = root;
        snapshot_ = std::move(snapshot);
        previewTransform_ = transform;
        snapshotStructureVersion_ = root != nullptr ? root->getStructureVersion() : 0;
        snapshotPropsVersion_ = root != nullptr ? root->getPropsVersion() : 0;
        snapshotRenderVersion_ = root != nullptr ? root->getRenderVersion() : 0;
    }
    repaint();
}

void ImGuiRuntimeNodeHost::setPresentationMode(PresentationMode mode) {
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        presentationMode_ = mode;
        previewTransform_ = {};
    }
    repaint();
}

void ImGuiRuntimeNodeHost::setUseLiveTree(bool useLiveTree) {
    const RuntimeNode* root = nullptr;
    PresentationMode presentationMode = PresentationMode::DebugPreview;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        useLiveTree_ = useLiveTree;
        root = liveRoot_;
        presentationMode = presentationMode_;
        previewTransform_ = {};
    }

    if (root != nullptr && getWidth() > 0 && getHeight() > 0) {
        PreviewTransform transform = renderer_.buildPreviewTransform(*root,
                                                                    getWidth(),
                                                                    getHeight(),
                                                                    makeRenderOptions(presentationMode));
        std::lock_guard<std::mutex> lock(dataMutex_);
        previewTransform_ = transform;
        snapshotStructureVersion_ = root->getStructureVersion();
        snapshotPropsVersion_ = root->getPropsVersion();
        snapshotRenderVersion_ = root->getRenderVersion();
    }
    repaint();
}

bool ImGuiRuntimeNodeHost::isUsingLiveTree() const {
    std::lock_guard<std::mutex> lock(dataMutex_);
    return useLiveTree_;
}

void ImGuiRuntimeNodeHost::setOnExitRequested(std::function<void()> fn) {
    std::lock_guard<std::mutex> lock(dataMutex_);
    onExitRequested_ = std::move(fn);
}

const RuntimeNode* ImGuiRuntimeNodeHost::getRootNode() const {
    std::lock_guard<std::mutex> lock(dataMutex_);
    return liveRoot_;
}

void ImGuiRuntimeNodeHost::refreshSnapshotNow() {
    refreshSnapshotIfNeeded();
}

std::string ImGuiRuntimeNodeHost::getSelectedNodeId() const {
    std::lock_guard<std::mutex> lock(dataMutex_);
    return selectedNodeId_;
}

std::string ImGuiRuntimeNodeHost::getHoveredNodeId() const {
    std::lock_guard<std::mutex> lock(dataMutex_);
    return hoveredNodeId_;
}

void ImGuiRuntimeNodeHost::paint(juce::Graphics& g) {
    juce::ignoreUnused(g);
}

void ImGuiRuntimeNodeHost::resized() {
    attachContextIfNeeded();
}

void ImGuiRuntimeNodeHost::visibilityChanged() {
    attachContextIfNeeded();
}

void ImGuiRuntimeNodeHost::parentHierarchyChanged() {
    attachContextIfNeeded();
}

void ImGuiRuntimeNodeHost::mouseMove(const juce::MouseEvent& e) {
    updateHover(e.position, &e.mods);
}

void ImGuiRuntimeNodeHost::mouseDrag(const juce::MouseEvent& e) {
    updateHover(e.position, &e.mods);

    uint64_t pressedNodeStableId = 0;
    PreviewTransform transform;
    std::shared_ptr<const Snapshot> snapshot;
    const RuntimeNode* liveRoot = nullptr;
    bool useLiveTree = false;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        pressedNodeStableId = pressedNodeStableId_;
        transform = previewTransform_;
        snapshot = snapshot_;
        liveRoot = liveRoot_;
        useLiveTree = useLiveTree_;
    }

    const RuntimeNode* interactionRoot = useLiveTree
        ? liveRoot
        : (snapshot ? static_cast<const RuntimeNode*>(snapshot->root) : nullptr);
    if (pressedNodeStableId == 0 || interactionRoot == nullptr || !transform.valid || transform.scale <= 0.0f) {
        return;
    }

    const auto* pressedSnapshotNode = findNodeByStableIdRecursive(*interactionRoot, pressedNodeStableId);
    if (pressedSnapshotNode == nullptr) {
        return;
    }

    bool found = false;
    const auto bounds = findSceneBoundsByStableIdRecursive(*interactionRoot, pressedNodeStableId, juce::Point<int>(0, 0), found);
    if (!found) {
        return;
    }

    const auto scenePosition = scenePositionFromPreview(e.position);
    const auto localPosition = juce::Point<float>(scenePosition.x - static_cast<float>(bounds.getX()),
                                                  scenePosition.y - static_cast<float>(bounds.getY()));
    const auto dragDelta = juce::Point<float>(e.getDistanceFromDragStartX() / transform.scale,
                                              e.getDistanceFromDragStartY() / transform.scale);
    invokeLiveMouseDrag(pressedNodeStableId, localPosition, dragDelta, e.mods);
    refreshSnapshotIfNeeded();
    repaint();
}

RuntimeNode* ImGuiRuntimeNodeHost::findLiveNodeByStableId(uint64_t stableId) const {
    const RuntimeNode* liveRoot = nullptr;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        liveRoot = liveRoot_;
    }

    if (liveRoot == nullptr || stableId == 0) {
        return nullptr;
    }

    return const_cast<RuntimeNode*>(liveRoot)->findByStableId(stableId);
}

RuntimeNode* ImGuiRuntimeNodeHost::findLiveWheelTarget(uint64_t stableId) const {
    auto* node = findLiveNodeByStableId(stableId);
    while (node != nullptr) {
        if (node->getCallbacks().onMouseWheel.valid()) {
            return node;
        }
        node = node->getParent();
    }
    return nullptr;
}

void ImGuiRuntimeNodeHost::setLiveFocus(uint64_t stableId) {
    const RuntimeNode* liveRoot = nullptr;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        liveRoot = liveRoot_;
    }

    if (liveRoot == nullptr) {
        return;
    }

    auto* mutableRoot = const_cast<RuntimeNode*>(liveRoot);
    clearFocusRecursive(*mutableRoot);
    if (auto* current = mutableRoot->findByStableId(stableId)) {
        current->setFocused(true);
    }
}

void ImGuiRuntimeNodeHost::invokeLiveMouseDown(uint64_t stableId,
                                               juce::Point<float> localPosition,
                                               const juce::ModifierKeys& mods) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setPressed(true);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseDown,
                      "onMouseDown",
                      node->getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseDrag(uint64_t stableId,
                                               juce::Point<float> localPosition,
                                               juce::Point<float> dragDelta,
                                               const juce::ModifierKeys& mods) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseDrag,
                      "onMouseDrag",
                      node->getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      dragDelta.x,
                      dragDelta.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseUp(uint64_t stableId,
                                             juce::Point<float> localPosition,
                                             bool triggerClick,
                                             bool triggerDoubleClick,
                                             const juce::ModifierKeys& mods) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setPressed(false);
    auto& callbacks = node->getCallbacks();
    if (triggerDoubleClick) {
        invokeLuaCallback(callbacks.onDoubleClick, "onDoubleClick", node->getNodeId());
    } else if (triggerClick) {
        invokeLuaCallback(callbacks.onClick, "onClick", node->getNodeId());
    }
    invokeLuaCallback(callbacks.onMouseUp,
                      "onMouseUp",
                      node->getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseMove(uint64_t stableId,
                                               juce::Point<float> localPosition,
                                               const juce::ModifierKeys& mods) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseMove,
                      "onMouseMove",
                      node->getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseEnter(uint64_t stableId) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setHovered(true);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseEnter, "onMouseEnter", node->getNodeId());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseExit(uint64_t stableId) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setHovered(false);
    node->setPressed(false);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseExit, "onMouseExit", node->getNodeId());
}

void ImGuiRuntimeNodeHost::invokeLiveMouseWheel(uint64_t stableId,
                                                juce::Point<float> scenePosition,
                                                float deltaY,
                                                const juce::ModifierKeys& mods) {
    auto* node = findLiveWheelTarget(stableId);
    if (node == nullptr) {
        return;
    }

    float localX = scenePosition.x;
    float localY = scenePosition.y;
    std::shared_ptr<const Snapshot> snapshot;
    const RuntimeNode* liveRoot = nullptr;
    bool useLiveTree = false;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        snapshot = snapshot_;
        liveRoot = liveRoot_;
        useLiveTree = useLiveTree_;
    }
    const RuntimeNode* interactionRoot = useLiveTree
        ? liveRoot
        : (snapshot ? static_cast<const RuntimeNode*>(snapshot->root) : nullptr);
    if (interactionRoot != nullptr) {
        bool found = false;
        const auto bounds = findSceneBoundsByStableIdRecursive(*interactionRoot, node->getStableId(), juce::Point<int>(0, 0), found);
        if (found) {
            localX -= static_cast<float>(bounds.getX());
            localY -= static_cast<float>(bounds.getY());
        }
    }

    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseWheel,
                      "onMouseWheel",
                      node->getNodeId(),
                      localX,
                      localY,
                      deltaY,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiRuntimeNodeHost::mouseDown(const juce::MouseEvent& e) {
    updateHover(e.position, &e.mods);
    auto hit = hitTestNode(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    if (hit.node != nullptr) {
        uint64_t previousSelectedStableId = 0;
        const std::string nodeId = hit.node->getNodeId();
        const auto localPosition = juce::Point<float>(hit.scenePosition.x - static_cast<float>(hit.sceneBounds.getX()),
                                                      hit.scenePosition.y - static_cast<float>(hit.sceneBounds.getY()));
        {
            std::lock_guard<std::mutex> lock(dataMutex_);
            previousSelectedStableId = selectedNodeStableId_;
            selectedNodeStableId_ = hit.stableId;
            pressedNodeStableId_ = hit.stableId;
            selectedNodeId_ = nodeId;
            std::fprintf(stderr, "[RuntimeNodeHost] selected node=%s type=%s stable=%llu\n",
                         hit.node->getNodeId().c_str(),
                         hit.node->getWidgetType().c_str(),
                         static_cast<unsigned long long>(hit.stableId));
        }
        grabKeyboardFocus();
        if (previousSelectedStableId != hit.stableId) {
            setLiveFocus(hit.stableId);
        }
        invokeLiveMouseDown(hit.stableId, localPosition, e.mods);
    } else {
        uint64_t previousSelectedStableId = 0;
        {
            std::lock_guard<std::mutex> lock(dataMutex_);
            previousSelectedStableId = selectedNodeStableId_;
            selectedNodeStableId_ = 0;
            pressedNodeStableId_ = 0;
            selectedNodeId_.clear();
        }
        if (previousSelectedStableId != 0) {
            setLiveFocus(0);
        }
    }
    refreshSnapshotIfNeeded();
    repaint();
}

void ImGuiRuntimeNodeHost::mouseUp(const juce::MouseEvent& e) {
    refreshSnapshotIfNeeded();
    auto hit = hitTestNode(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    uint64_t pressedNodeStableId = 0;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        pressedNodeStableId = pressedNodeStableId_;
        pressedNodeStableId_ = 0;
    }

    if (pressedNodeStableId != 0) {
        juce::Point<float> localPosition;
        bool triggerClick = false;
        bool triggerDoubleClick = false;
        if (hit.node != nullptr && hit.stableId == pressedNodeStableId) {
            localPosition = juce::Point<float>(hit.scenePosition.x - static_cast<float>(hit.sceneBounds.getX()),
                                               hit.scenePosition.y - static_cast<float>(hit.sceneBounds.getY()));
            triggerDoubleClick = e.getNumberOfClicks() >= 2;
            triggerClick = !triggerDoubleClick && !e.mouseWasDraggedSinceMouseDown();
        }
        invokeLiveMouseUp(pressedNodeStableId, localPosition, triggerClick, triggerDoubleClick, e.mods);
    }
    refreshSnapshotIfNeeded();
    repaint();
}

void ImGuiRuntimeNodeHost::mouseExit(const juce::MouseEvent& e) {
    juce::ignoreUnused(e);
    uint64_t previousHoveredStableId = 0;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        previousHoveredStableId = hoveredNodeStableId_;
        hoveredNodeStableId_ = 0;
        hoveredNodeId_.clear();
    }
    if (previousHoveredStableId != 0) {
        invokeLiveMouseExit(previousHoveredStableId);
    }
    refreshSnapshotIfNeeded();
    repaint();
}

void ImGuiRuntimeNodeHost::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) {
    updateHover(e.position, &e.mods);
    auto hit = hitTestNode(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Wheel);
    if (hit.node == nullptr || hit.stableId == 0) {
        return;
    }

    invokeLiveMouseWheel(hit.stableId, hit.scenePosition, wheel.deltaY, e.mods);
    refreshSnapshotIfNeeded();
    repaint();
}

bool ImGuiRuntimeNodeHost::keyPressed(const juce::KeyPress& key) {
    uint64_t selectedNodeStableId = 0;
    std::string selectedNodeId;
    std::function<void()> exitRequested;
    PresentationMode presentationMode = PresentationMode::DebugPreview;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        selectedNodeStableId = selectedNodeStableId_;
        selectedNodeId = selectedNodeId_;
        exitRequested = onExitRequested_;
        presentationMode = presentationMode_;
    }

    if (presentationMode == PresentationMode::Replace && key.getKeyCode() == juce::KeyPress::escapeKey) {
        if (exitRequested) {
            exitRequested();
            return true;
        }
    }

    auto* node = findLiveNodeByStableId(selectedNodeStableId);
    if (node == nullptr) {
        return juce::Component::keyPressed(key);
    }

    node->setFocused(true);
    auto& callbacks = node->getCallbacks();
    if (!callbacks.onKeyPress.valid()) {
        return juce::Component::keyPressed(key);
    }

    sol::protected_function fn = callbacks.onKeyPress;
    auto mods = key.getModifiers();
    auto result = fn(key.getKeyCode(),
                     static_cast<int>(key.getTextCharacter()),
                     mods.isShiftDown(),
                     isCtrlLikeDown(mods),
                     mods.isAltDown());
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "[RuntimeNodeHost] onKeyPress error for %s: %s\n",
                     selectedNodeId.c_str(),
                     err.what());
        return false;
    }
    refreshSnapshotIfNeeded();
    repaint();
    if (result.get_type() == sol::type::boolean) {
        return result.get<bool>();
    }
    return true;
}

void ImGuiRuntimeNodeHost::newOpenGLContextCreated() {
    IMGUI_CHECKVERSION();
    auto* context = ImGui::CreateContext();
    imguiContext = context;
    ImGui::SetCurrentContext(context);

    auto& io = ImGui::GetIO();
    io.BackendPlatformName = "manifold_juce_runtime_node";

    manifold::ui::imgui::applyToolTheme();
    ImGui_ImplOpenGL3_Init("#version 150");
}

void ImGuiRuntimeNodeHost::renderOpenGL() {
    if (getWidth() <= 0 || getHeight() <= 0 || !isShowing()) {
        return;
    }

    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext);
    if (context == nullptr) {
        return;
    }

    refreshSnapshotIfNeeded();
    ImGui::SetCurrentContext(context);

    const auto width = std::max(1, getWidth());
    const auto height = std::max(1, getHeight());
    const auto scale = static_cast<float>(openGLContext.getRenderingScale());
    const auto framebufferWidth = std::max(1, juce::roundToInt(scale * static_cast<float>(width)));
    const auto framebufferHeight = std::max(1, juce::roundToInt(scale * static_cast<float>(height)));

    auto& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(static_cast<float>(width), static_cast<float>(height));
    io.DisplayFramebufferScale = ImVec2(scale, scale);

    const auto& theme = manifold::ui::imgui::toolTheme();
    glViewport(0, 0, framebufferWidth, framebufferHeight);
    glDisable(GL_SCISSOR_TEST);
    glClearColor(theme.panelBg.x, theme.panelBg.y, theme.panelBg.z, theme.panelBg.w);
    glClear(GL_COLOR_BUFFER_BIT);

    ImGui_ImplOpenGL3_NewFrame();
    ImGui::NewFrame();

    std::shared_ptr<const Snapshot> snapshot;
    const RuntimeNode* root = nullptr;
    PreviewTransform transform;
    uint64_t selectedNodeStableId = 0;
    uint64_t hoveredNodeStableId = 0;
    std::string selectedNodeId;
    std::string hoveredNodeId;
    PresentationMode presentationMode = PresentationMode::DebugPreview;
    manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions renderOptions;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        snapshot = snapshot_;
        root = snapshot ? snapshot->root : nullptr;
        selectedNodeStableId = selectedNodeStableId_;
        hoveredNodeStableId = hoveredNodeStableId_;
        selectedNodeId = selectedNodeId_;
        hoveredNodeId = hoveredNodeId_;
        presentationMode = presentationMode_;
        renderOptions = makeRenderOptions(presentationMode_);
        if (root != nullptr) {
            previewTransform_ = renderer_.buildPreviewTransform(*root, width, height, renderOptions);
        } else {
            previewTransform_ = {};
        }
        transform = previewTransform_;
    }

    auto* drawList = ImGui::GetForegroundDrawList();
    if (presentationMode == PresentationMode::DebugPreview) {
        drawList->AddRectFilled(ImVec2(0.0f, 0.0f),
                                ImVec2(static_cast<float>(width), static_cast<float>(height)),
                                IM_COL32(8, 12, 20, 245),
                                10.0f);
        drawList->AddRect(ImVec2(0.5f, 0.5f),
                          ImVec2(static_cast<float>(width) - 0.5f, static_cast<float>(height) - 0.5f),
                          IM_COL32(56, 189, 248, 255),
                          10.0f,
                          0,
                          2.0f);

        const std::string selectedLabel = selectedNodeId.empty()
            ? std::string("selected: <none>")
            : std::string("selected: ") + selectedNodeId;
        const std::string hoveredLabel = hoveredNodeId.empty()
            ? std::string("hovered: <none>")
            : std::string("hovered: ") + hoveredNodeId;

        drawList->AddText(ImVec2(12.0f, 10.0f), IM_COL32(255, 255, 255, 255), "RuntimeNode preview");
        drawList->AddText(ImVec2(12.0f, 30.0f), IM_COL32(203, 213, 225, 255), selectedLabel.c_str());
        drawList->AddText(ImVec2(12.0f, 48.0f), IM_COL32(148, 163, 184, 255), hoveredLabel.c_str());
    }

    if (root == nullptr) {
        drawList->AddText(ImVec2(12.0f, 76.0f), IM_COL32(248, 113, 113, 255), "RuntimeNode host: no root configured");
    } else {
        renderer_.render(*root, drawList, transform, selectedNodeStableId, hoveredNodeStableId, renderOptions);
    }

    ImGui::Render();
    if (auto* drawData = ImGui::GetDrawData()) {
        ImGui_ImplOpenGL3_RenderDrawData(drawData);
    }
}

void ImGuiRuntimeNodeHost::openGLContextClosing() {
    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext);
    if (context != nullptr) {
        ImGui::SetCurrentContext(context);
        ImGui_ImplOpenGL3_Shutdown();
        ImGui::DestroyContext(context);
        imguiContext = nullptr;
    }
}

void ImGuiRuntimeNodeHost::attachContextIfNeeded() {
    if (!isShowing()) {
        return;
    }

    if (!openGLContext.isAttached()) {
        std::fprintf(stderr, "[RuntimeNodeHost] attachContextIfNeeded: ATTACHING w=%d h=%d\n", getWidth(), getHeight());
        openGLContext.attachTo(*this);
    }
}

void ImGuiRuntimeNodeHost::refreshSnapshotIfNeeded() {
    const RuntimeNode* liveRoot = nullptr;
    uint64_t currentStructureVersion = 0;
    uint64_t currentPropsVersion = 0;
    uint64_t currentRenderVersion = 0;
    bool needsRefresh = false;
    PresentationMode presentationMode = PresentationMode::DebugPreview;

    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        liveRoot = liveRoot_;
        presentationMode = presentationMode_;
        if (liveRoot != nullptr) {
            currentStructureVersion = liveRoot->getStructureVersion();
            currentPropsVersion = liveRoot->getPropsVersion();
            currentRenderVersion = liveRoot->getRenderVersion();
            needsRefresh = snapshot_ == nullptr
                || snapshotStructureVersion_ != currentStructureVersion
                || snapshotPropsVersion_ != currentPropsVersion
                || snapshotRenderVersion_ != currentRenderVersion
                || !previewTransform_.valid;
        } else {
            needsRefresh = snapshot_ != nullptr || previewTransform_.valid;
        }
    }

    if (!needsRefresh) {
        return;
    }

    auto* messageManager = juce::MessageManager::getInstanceWithoutCreating();
    if (messageManager == nullptr || !messageManager->isThisTheMessageThread()) {
        triggerAsyncUpdate();
        return;
    }

    auto snapshot = renderer_.makeSnapshot(liveRoot);
    PreviewTransform transform;
    if (snapshot && snapshot->root != nullptr && getWidth() > 0 && getHeight() > 0) {
        transform = renderer_.buildPreviewTransform(*snapshot->root,
                                                    getWidth(),
                                                    getHeight(),
                                                    makeRenderOptions(presentationMode));
    }
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        snapshot_ = std::move(snapshot);
        previewTransform_ = transform;
        snapshotStructureVersion_ = currentStructureVersion;
        snapshotPropsVersion_ = currentPropsVersion;
        snapshotRenderVersion_ = currentRenderVersion;
    }
}

void ImGuiRuntimeNodeHost::handleAsyncUpdate() {
    refreshSnapshotIfNeeded();
    repaint();
}

juce::Point<float> ImGuiRuntimeNodeHost::scenePositionFromPreview(juce::Point<float> position) const {
    PreviewTransform transform;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        transform = previewTransform_;
    }

    if (!transform.valid || transform.scale <= 0.0f) {
        return {};
    }

    return juce::Point<float>((position.x - transform.offsetX) / transform.scale,
                              (position.y - transform.offsetY) / transform.scale);
}

void ImGuiRuntimeNodeHost::updateHover(juce::Point<float> position, const juce::ModifierKeys* mods) {
    refreshSnapshotIfNeeded();
    auto hit = hitTestNode(position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    const uint64_t nextHoveredStableId = hit.node != nullptr ? hit.stableId : 0;
    const std::string nextHovered = hit.node != nullptr ? hit.node->getNodeId() : std::string{};

    uint64_t previousHoveredStableId = 0;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        previousHoveredStableId = hoveredNodeStableId_;
        hoveredNodeStableId_ = nextHoveredStableId;
        hoveredNodeId_ = nextHovered;
    }

    if (previousHoveredStableId != nextHoveredStableId) {
        if (previousHoveredStableId != 0) {
            invokeLiveMouseExit(previousHoveredStableId);
        }
        if (nextHoveredStableId != 0) {
            invokeLiveMouseEnter(nextHoveredStableId);
        }
    }

    if (mods != nullptr && hit.node != nullptr && nextHoveredStableId != 0) {
        const auto localPosition = juce::Point<float>(hit.scenePosition.x - static_cast<float>(hit.sceneBounds.getX()),
                                                      hit.scenePosition.y - static_cast<float>(hit.sceneBounds.getY()));
        invokeLiveMouseMove(nextHoveredStableId, localPosition, *mods);
    }

    refreshSnapshotIfNeeded();
    repaint();
}

ImGuiRuntimeNodeHost::HitTestResult ImGuiRuntimeNodeHost::hitTestNode(
    juce::Point<float> position,
    manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode mode) const {
    std::shared_ptr<const Snapshot> snapshot;
    const RuntimeNode* liveRoot = nullptr;
    PreviewTransform transform;
    PresentationMode presentationMode = PresentationMode::DebugPreview;
    bool useLiveTree = false;
    {
        std::lock_guard<std::mutex> lock(dataMutex_);
        snapshot = snapshot_;
        liveRoot = liveRoot_;
        transform = previewTransform_;
        presentationMode = presentationMode_;
        useLiveTree = useLiveTree_;
    }

    const RuntimeNode* root = useLiveTree
        ? liveRoot
        : (snapshot ? static_cast<const RuntimeNode*>(snapshot->root) : nullptr);
    if (root == nullptr) {
        return {};
    }

    if ((!transform.valid || transform.scale <= 0.0f) && getWidth() > 0 && getHeight() > 0) {
        transform = renderer_.buildPreviewTransform(*root,
                                                    getWidth(),
                                                    getHeight(),
                                                    makeRenderOptions(presentationMode));
    }

    if (useLiveTree) {
        Snapshot liveSnapshot;
        liveSnapshot.root = const_cast<RuntimeNode*>(root);
        return renderer_.hitTest(liveSnapshot, position, transform, mode);
    }

    if (!snapshot) {
        return {};
    }
    return renderer_.hitTest(*snapshot, position, transform, mode);
}

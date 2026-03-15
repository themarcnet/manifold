#include "ImGuiDirectHost.h"

#include "Theme.h"
#include "backends/imgui_impl_opengl3.h"
#include "imgui.h"

#include <algorithm>
#include <cfloat>
#include <chrono>
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
        std::fprintf(stderr, "[ImGuiDirectHost] %s error for %s: %s\n",
                     label,
                     nodeId.c_str(),
                     err.what());
    }
}

void clearFocusRecursive(RuntimeNode& node) {
    node.setFocused(false);
    for (auto* child : node.getChildren()) {
        if (child != nullptr) {
            clearFocusRecursive(*child);
        }
    }
}

manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions makeDirectRenderOptions() {
    manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions options;
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
    return options;
}

manifold::ui::imgui::RuntimeNodeRenderer::HitTestResult hitTestLiveTreeDetailed(
    manifold::ui::imgui::RuntimeNodeRenderer& renderer,
    RuntimeNode* root,
    juce::Point<float> position,
    const manifold::ui::imgui::RuntimeNodeRenderer::PreviewTransform& transform,
    manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode mode) {
    if (root == nullptr || !transform.valid || transform.scale <= 0.0f) {
        return {};
    }

    manifold::ui::imgui::RuntimeNodeRenderer::Snapshot liveSnapshot;
    liveSnapshot.root = root;
    return renderer.hitTest(liveSnapshot, position, transform, mode);
}

juce::Rectangle<float> sceneBoundsForNode(RuntimeNode* node) {
    if (node == nullptr) {
        return {};
    }

    struct NodeSceneTransform {
        float scaleX = 1.0f;
        float scaleY = 1.0f;
        float offsetX = 0.0f;
        float offsetY = 0.0f;
    } transform;

    std::vector<RuntimeNode*> lineage;
    for (RuntimeNode* current = node; current != nullptr; current = current->getParent()) {
        lineage.push_back(current);
    }
    std::reverse(lineage.begin(), lineage.end());

    for (auto* current : lineage) {
        const auto& bounds = current->getBounds();
        const auto& nodeTransform = current->getTransform();
        transform.offsetX += transform.scaleX * (static_cast<float>(bounds.x) + nodeTransform.translateX);
        transform.offsetY += transform.scaleY * (static_cast<float>(bounds.y) + nodeTransform.translateY);
        transform.scaleX *= nodeTransform.scaleX;
        transform.scaleY *= nodeTransform.scaleY;
    }

    const auto& bounds = node->getBounds();
    const float x1 = transform.offsetX;
    const float y1 = transform.offsetY;
    const float x2 = transform.offsetX + transform.scaleX * static_cast<float>(bounds.w);
    const float y2 = transform.offsetY + transform.scaleY * static_cast<float>(bounds.h);
    const float left = std::min(x1, x2);
    const float top = std::min(y1, y2);
    const float right = std::max(x1, x2);
    const float bottom = std::max(y1, y2);
    return juce::Rectangle<float>(left, top, std::max(1.0f, right - left), std::max(1.0f, bottom - top));
}

juce::Point<float> localPositionForNode(RuntimeNode* node,
                                        juce::Point<float> scenePosition) {
    if (node == nullptr) {
        return scenePosition;
    }

    const auto sceneBounds = sceneBoundsForNode(node);
    const auto& bounds = node->getBounds();
    const float scaleX = bounds.w > 0 ? (sceneBounds.getWidth() / static_cast<float>(bounds.w)) : 1.0f;
    const float scaleY = bounds.h > 0 ? (sceneBounds.getHeight() / static_cast<float>(bounds.h)) : 1.0f;
    return juce::Point<float>((scenePosition.x - sceneBounds.getX()) / std::max(0.0001f, scaleX),
                              (scenePosition.y - sceneBounds.getY()) / std::max(0.0001f, scaleY));
}

ImU32 toImColor(uint32_t argb) {
    const auto a = static_cast<ImU32>((argb >> 24) & 0xffu);
    const auto r = static_cast<ImU32>((argb >> 16) & 0xffu);
    const auto g = static_cast<ImU32>((argb >> 8) & 0xffu);
    const auto b = static_cast<ImU32>(argb & 0xffu);
    return IM_COL32(r, g, b, a);
}

juce::Rectangle<float> previewRect(const juce::Rectangle<int>& sceneRect,
                                   const ImGuiDirectHost::PreviewTransform& transform) {
    const float x1 = transform.offsetX + static_cast<float>(sceneRect.getX()) * transform.scale;
    const float y1 = transform.offsetY + static_cast<float>(sceneRect.getY()) * transform.scale;
    const float x2 = transform.offsetX + static_cast<float>(sceneRect.getRight()) * transform.scale;
    const float y2 = transform.offsetY + static_cast<float>(sceneRect.getBottom()) * transform.scale;
    return juce::Rectangle<float>(x1, y1, std::max(1.0f, x2 - x1), std::max(1.0f, y2 - y1));
}

ImVec2 toImVec2(const juce::Rectangle<float>& rect) {
    return ImVec2(rect.getX(), rect.getY());
}

ImVec2 toImVec2BottomRight(const juce::Rectangle<float>& rect) {
    return ImVec2(rect.getRight(), rect.getBottom());
}

struct DrawState {
    ImU32 color = IM_COL32_WHITE;
    float fontSize = 13.0f;
    std::vector<juce::Rectangle<int>> clipStack;
};

void popClipStackTo(ImDrawList* drawList,
                    std::vector<juce::Rectangle<int>>& clipStack,
                    std::size_t targetSize) {
    while (clipStack.size() > targetSize) {
        drawList->PopClipRect();
        clipStack.pop_back();
    }
}

void renderCompiledDisplayList(const manifold::ui::imgui::CompiledDisplayList& compiled,
                               const juce::Rectangle<int>& sceneBounds,
                               ImDrawList* drawList,
                               DrawState& state,
                               const ImGuiDirectHost::PreviewTransform& transform) {
    std::vector<DrawState> stateStack;

    for (const auto& cmd : compiled.commands) {
        if (cmd.type == manifold::ui::imgui::CompiledDrawCmd::Type::Save) {
            stateStack.push_back(state);
            continue;
        }
        if (cmd.type == manifold::ui::imgui::CompiledDrawCmd::Type::Restore) {
            if (!stateStack.empty()) {
                const auto saved = stateStack.back();
                stateStack.pop_back();
                popClipStackTo(drawList, state.clipStack, saved.clipStack.size());
                state = saved;
            }
            continue;
        }

        if (cmd.hasColor) {
            state.color = cmd.color;
        }
        if (cmd.hasFontSize) {
            state.fontSize = cmd.fontSize;
        }

        const juce::Rectangle<int> sceneRect(sceneBounds.getX() + juce::roundToInt(cmd.x),
                                             sceneBounds.getY() + juce::roundToInt(cmd.y),
                                             juce::roundToInt(cmd.w),
                                             juce::roundToInt(cmd.h));
        const auto rect = previewRect(sceneRect, transform);
        const float scaledRadius = cmd.radius * transform.scale;
        const float scaledThickness = std::max(1.0f, cmd.thickness * transform.scale);

        switch (cmd.type) {
            case manifold::ui::imgui::CompiledDrawCmd::Type::FillRect:
                drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color);
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::DrawRect:
                drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::FillRoundedRect:
                drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius);
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::DrawRoundedRect:
                drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::DrawLine: {
                const ImVec2 p1(transform.offsetX + (static_cast<float>(sceneBounds.getX()) + cmd.x1) * transform.scale,
                                transform.offsetY + (static_cast<float>(sceneBounds.getY()) + cmd.y1) * transform.scale);
                const ImVec2 p2(transform.offsetX + (static_cast<float>(sceneBounds.getX()) + cmd.x2) * transform.scale,
                                transform.offsetY + (static_cast<float>(sceneBounds.getY()) + cmd.y2) * transform.scale);
                drawList->AddLine(p1, p2, state.color, scaledThickness);
                break;
            }
            case manifold::ui::imgui::CompiledDrawCmd::Type::DrawText: {
                const float fontSize = std::max(1.0f, state.fontSize * transform.scale);
                auto* font = ImGui::GetFont();
                if (font == nullptr) {
                    break;
                }
                const ImVec2 textSize = font->CalcTextSizeA(fontSize, FLT_MAX, 0.0f, cmd.text.c_str());
                float textX = rect.getX();
                float textY = rect.getY();

                if (cmd.align == "center") {
                    textX += std::max(0.0f, (rect.getWidth() - textSize.x) * 0.5f);
                } else if (cmd.align == "right") {
                    textX += std::max(0.0f, rect.getWidth() - textSize.x - 4.0f);
                } else {
                    textX += 4.0f;
                }

                if (cmd.valign == "middle") {
                    textY += std::max(0.0f, (rect.getHeight() - textSize.y) * 0.5f);
                } else if (cmd.valign == "bottom") {
                    textY += std::max(0.0f, rect.getHeight() - textSize.y - 2.0f);
                } else {
                    textY += 2.0f;
                }

                drawList->AddText(font, fontSize, ImVec2(textX, textY), state.color, cmd.text.c_str());
                break;
            }
            case manifold::ui::imgui::CompiledDrawCmd::Type::DrawImage:
                if (cmd.textureId != 0) {
                    drawList->AddImage(static_cast<ImTextureID>(cmd.textureId),
                                       toImVec2(rect),
                                       toImVec2BottomRight(rect),
                                       ImVec2(cmd.u0, cmd.v0),
                                       ImVec2(cmd.u1, cmd.v1),
                                       state.color);
                }
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::ClipRect: {
                const auto clipMin = toImVec2(rect);
                const auto clipMax = toImVec2BottomRight(rect);
                const bool validClip = clipMin.x < clipMax.x && clipMin.y < clipMax.y;
                if (validClip) {
                    drawList->PushClipRect(clipMin, clipMax, true);
                    state.clipStack.push_back(sceneRect);
                }
                break;
            }
            case manifold::ui::imgui::CompiledDrawCmd::Type::PopClipRect:
                if (!state.clipStack.empty()) {
                    drawList->PopClipRect();
                    state.clipStack.pop_back();
                }
                break;
            case manifold::ui::imgui::CompiledDrawCmd::Type::SetColor:
            case manifold::ui::imgui::CompiledDrawCmd::Type::SetFontSize:
            case manifold::ui::imgui::CompiledDrawCmd::Type::Save:
            case manifold::ui::imgui::CompiledDrawCmd::Type::Restore:
                break;
        }
    }

    while (!stateStack.empty()) {
        const auto saved = stateStack.back();
        stateStack.pop_back();
        popClipStackTo(drawList, state.clipStack, saved.clipStack.size());
        state = saved;
    }

    popClipStackTo(drawList, state.clipStack, 0);
}

std::vector<RuntimeNode*> sortedLiveChildren(const RuntimeNode& node) {
    std::vector<RuntimeNode*> children;
    children.reserve(node.getChildren().size());
    for (auto* child : node.getChildren()) {
        if (child != nullptr) {
            children.push_back(child);
        }
    }

    std::stable_sort(children.begin(), children.end(), [](const RuntimeNode* a, const RuntimeNode* b) {
        return a->getZOrder() < b->getZOrder();
    });
    return children;
}

int buildRenderSnapshotRecursive(const RuntimeNode& node,
                                 juce::Point<int> parentOffset,
                                 ImGuiDirectHost::RenderSnapshot& snapshot) {
    const auto& bounds = node.getBounds();
    const int index = static_cast<int>(snapshot.nodes.size());
    snapshot.nodes.emplace_back();
    snapshot.nodes[static_cast<std::size_t>(index)].sceneBounds = juce::Rectangle<int>(parentOffset.x + bounds.x,
                                                                                        parentOffset.y + bounds.y,
                                                                                        bounds.w,
                                                                                        bounds.h);
    snapshot.nodes[static_cast<std::size_t>(index)].style = node.getStyle();
    snapshot.nodes[static_cast<std::size_t>(index)].visible = node.isVisible();
    snapshot.nodes[static_cast<std::size_t>(index)].hasClipRect = node.hasClipRect();
    if (snapshot.nodes[static_cast<std::size_t>(index)].hasClipRect) {
        const auto& clip = node.getClipRect();
        snapshot.nodes[static_cast<std::size_t>(index)].clipRect = juce::Rectangle<int>(clip.x, clip.y, clip.w, clip.h);
    }
    snapshot.nodes[static_cast<std::size_t>(index)].zOrder = node.getZOrder();
    snapshot.nodes[static_cast<std::size_t>(index)].compiledDisplayList = node.getCompiledDisplayList();

    if (!snapshot.nodes[static_cast<std::size_t>(index)].visible) {
        return index;
    }

    const auto sceneBounds = snapshot.nodes[static_cast<std::size_t>(index)].sceneBounds;
    for (auto* child : sortedLiveChildren(node)) {
        const int childIndex = buildRenderSnapshotRecursive(*child,
                                                            juce::Point<int>(sceneBounds.getX(), sceneBounds.getY()),
                                                            snapshot);
        snapshot.nodes[static_cast<std::size_t>(index)].childIndices.push_back(childIndex);
    }

    return index;
}

void renderSnapshotNodeRecursive(const ImGuiDirectHost::RenderSnapshot& snapshot,
                                 int nodeIndex,
                                 ImDrawList* drawList,
                                 const manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions& options,
                                 int depth) {
    if (nodeIndex < 0 || nodeIndex >= static_cast<int>(snapshot.nodes.size())) {
        return;
    }

    const auto& node = snapshot.nodes[static_cast<std::size_t>(nodeIndex)];
    if (!node.visible) {
        return;
    }

    const auto bounds = previewRect(node.sceneBounds, snapshot.transform);
    const auto& style = node.style;

    bool pushedNodeClip = false;
    if (node.hasClipRect) {
        const juce::Rectangle<int> sceneClip(node.sceneBounds.getX() + node.clipRect.getX(),
                                             node.sceneBounds.getY() + node.clipRect.getY(),
                                             node.clipRect.getWidth(),
                                             node.clipRect.getHeight());
        const auto clipRect = previewRect(sceneClip, snapshot.transform);
        drawList->PushClipRect(toImVec2(clipRect), toImVec2BottomRight(clipRect), true);
        pushedNodeClip = true;
    }

    const bool hasBackground = ((style.background >> 24) & 0xffu) != 0u;
    const bool hasBorder = ((style.border >> 24) & 0xffu) != 0u && style.borderWidth > 0.0f;
    const float cornerRadius = std::max(0.0f, style.cornerRadius * snapshot.transform.scale);
    const float borderWidth = std::max(1.0f, style.borderWidth * snapshot.transform.scale);

    if (hasBackground) {
        drawList->AddRectFilled(toImVec2(bounds), toImVec2BottomRight(bounds), toImColor(style.background), cornerRadius);
    } else if (options.showFallbackBoxes && depth > 0) {
        drawList->AddRectFilled(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(255, 255, 255, 12), cornerRadius);
    }

    if (hasBorder) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), toImColor(style.border), cornerRadius, 0, borderWidth);
    } else if (options.showFallbackBoxes) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(148, 163, 184, depth == 0 ? 140 : 90), cornerRadius, 0, 1.0f);
    }

    if (node.compiledDisplayList && !node.compiledDisplayList->commands.empty()) {
        DrawState state;
        renderCompiledDisplayList(*node.compiledDisplayList, node.sceneBounds, drawList, state, snapshot.transform);
    }

    for (int childIndex : node.childIndices) {
        renderSnapshotNodeRecursive(snapshot, childIndex, drawList, options, depth + 1);
    }

    if (pushedNodeClip) {
        drawList->PopClipRect();
    }
}

void renderSnapshot(const ImGuiDirectHost::RenderSnapshot& snapshot,
                    ImDrawList* drawList,
                    const manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions& options) {
    if (drawList == nullptr || !snapshot.transform.valid || snapshot.rootIndex < 0) {
        return;
    }

    renderSnapshotNodeRecursive(snapshot, snapshot.rootIndex, drawList, options, 0);
}

} // namespace

ImGuiDirectHost::ImGuiDirectHost() {
    setOpaque(true);
    setWantsKeyboardFocus(true);
    setMouseClickGrabsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);

    openGLContext_.setRenderer(this);
    openGLContext_.setComponentPaintingEnabled(false);
    openGLContext_.setPersistentAttachment(true);
    openGLContext_.setContinuousRepainting(false);
    openGLContext_.setSwapInterval(1);
}

ImGuiDirectHost::~ImGuiDirectHost() {
    shutdown();
}

ImGuiDirectHost::StatsSnapshot ImGuiDirectHost::getStatsSnapshot() const {
    StatsSnapshot snapshot;
    snapshot.contextReady = contextReady_;
    snapshot.testWindowVisible = isVisible();
    snapshot.wantCaptureMouse = wantCaptureMouse_.load(std::memory_order_relaxed);
    snapshot.wantCaptureKeyboard = wantCaptureKeyboard_.load(std::memory_order_relaxed);
    snapshot.frameCount = frameCount_.load(std::memory_order_relaxed);
    snapshot.lastRenderUs = lastRenderUs_.load(std::memory_order_relaxed);
    snapshot.lastVertexCount = lastVertexCount_.load(std::memory_order_relaxed);
    snapshot.lastIndexCount = lastIndexCount_.load(std::memory_order_relaxed);
    return snapshot;
}

void ImGuiDirectHost::setGlobalKeyHandler(GlobalKeyHandler handler) {
    globalKeyHandler_ = std::move(handler);
}

void ImGuiDirectHost::setRootNode(RuntimeNode* root) {
    if (liveRoot_ == root) {
        return;
    }

    liveRoot_ = root;
    pressedNodeStableId_ = 0;
    hoveredNodeStableId_ = 0;
    focusedNodeStableId_ = 0;
    pendingDragEvent_ = {};
    lastContinuousInputDispatchMs_ = 0.0;
    previewTransform_ = {};

    {
        std::lock_guard<std::mutex> lock(snapshotMutex_);
        pendingSnapshot_ = {};
        activeSnapshot_ = {};
    }
    snapshotReady_.store(true, std::memory_order_release);
}

void ImGuiDirectHost::buildRenderSnapshot() {
    const auto renderOptions = makeDirectRenderOptions();
    if (liveRoot_ != nullptr && getWidth() > 0 && getHeight() > 0) {
        previewTransform_ = renderer_.buildPreviewTransform(*liveRoot_, getWidth(), getHeight(), renderOptions);
    } else {
        previewTransform_ = {};
    }
}

void ImGuiDirectHost::flushPendingDrag() {
    if (!pendingDragEvent_.valid || pendingDragEvent_.stableId == 0) {
        return;
    }

    auto* node = findLiveNodeByStableId(pendingDragEvent_.stableId);
    if (node != nullptr) {
        invokeLiveMouseDrag(*node,
                            pendingDragEvent_.localPosition,
                            pendingDragEvent_.dragDelta,
                            pendingDragEvent_.mods);
    }

    pendingDragEvent_ = {};
    lastContinuousInputDispatchMs_ = juce::Time::getMillisecondCounterHiRes();
}

void ImGuiDirectHost::renderNow() {
    attachContextIfNeeded();

    if (getWidth() <= 0 || getHeight() <= 0 || !isShowing()) {
        wantCaptureMouse_.store(false, std::memory_order_relaxed);
        wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
        lastVertexCount_.store(0, std::memory_order_relaxed);
        lastIndexCount_.store(0, std::memory_order_relaxed);
        return;
    }

    if (!openGLContext_.isAttached() || !contextReady_) {
        wantCaptureMouse_.store(false, std::memory_order_relaxed);
        wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
        lastVertexCount_.store(0, std::memory_order_relaxed);
        lastIndexCount_.store(0, std::memory_order_relaxed);
        return;
    }

    flushPendingDrag();

    if (!openGLContext_.makeActive()) {
        return;
    }

    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext_);
    if (context == nullptr) {
        juce::OpenGLContext::deactivateCurrentContext();
        return;
    }

    ImGui::SetCurrentContext(context);

    const auto width = std::max(1, getWidth());
    const auto height = std::max(1, getHeight());
    const auto scale = static_cast<float>(openGLContext_.getRenderingScale());
    const auto framebufferWidth = std::max(1, juce::roundToInt(scale * static_cast<float>(width)));
    const auto framebufferHeight = std::max(1, juce::roundToInt(scale * static_cast<float>(height)));

    auto& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(static_cast<float>(width), static_cast<float>(height));
    io.DisplayFramebufferScale = ImVec2(scale, scale);

    using Clock = std::chrono::steady_clock;
    const auto t0 = Clock::now();

    const auto renderOptions = makeDirectRenderOptions();
    if (liveRoot_ != nullptr) {
        previewTransform_ = renderer_.buildPreviewTransform(*liveRoot_, width, height, renderOptions);
    } else {
        previewTransform_ = {};
    }

    const auto t1 = Clock::now();

    const auto& theme = manifold::ui::imgui::toolTheme();
    glViewport(0, 0, framebufferWidth, framebufferHeight);
    glDisable(GL_SCISSOR_TEST);
    glClearColor(theme.panelBg.x, theme.panelBg.y, theme.panelBg.z, theme.panelBg.w);
    glClear(GL_COLOR_BUFFER_BIT);

    ImGui_ImplOpenGL3_NewFrame();
    ImGui::NewFrame();

    const auto t2 = Clock::now();

    if (liveRoot_ != nullptr) {
        renderer_.render(*liveRoot_,
                         ImGui::GetForegroundDrawList(),
                         previewTransform_,
                         0,
                         0,
                         renderOptions);
    }

    const auto t3 = Clock::now();

    ImGui::Render();
    int64_t vertexCount = 0;
    int64_t indexCount = 0;
    if (auto* drawData = ImGui::GetDrawData()) {
        vertexCount = static_cast<int64_t>(drawData->TotalVtxCount);
        indexCount = static_cast<int64_t>(drawData->TotalIdxCount);
        ImGui_ImplOpenGL3_RenderDrawData(drawData);
    }

    const auto t4 = Clock::now();

    openGLContext_.swapBuffers();

    const auto t5 = Clock::now();

    wantCaptureMouse_.store(io.WantCaptureMouse, std::memory_order_relaxed);
    wantCaptureKeyboard_.store(io.WantCaptureKeyboard, std::memory_order_relaxed);
    frameCount_.fetch_add(1, std::memory_order_relaxed);
    lastRenderUs_.store(std::chrono::duration_cast<std::chrono::microseconds>(t5 - t0).count(),
                        std::memory_order_relaxed);
    lastVertexCount_.store(vertexCount, std::memory_order_relaxed);
    lastIndexCount_.store(indexCount, std::memory_order_relaxed);

    juce::OpenGLContext::deactivateCurrentContext();

    static int frameCounter = 0;
    if (++frameCounter % 60 == 0) {
        auto us = [](auto a, auto b) { return std::chrono::duration_cast<std::chrono::microseconds>(b - a).count(); };
        std::fprintf(stderr, "[DirectHost] transform=%lldus setup=%lldus render=%lldus submit=%lldus swap=%lldus TOTAL=%lldus\n",
                     (long long)us(t0, t1), (long long)us(t1, t2), (long long)us(t2, t3),
                     (long long)us(t3, t4), (long long)us(t4, t5), (long long)us(t0, t5));
    }
}

void ImGuiDirectHost::shutdown() {
    liveRoot_ = nullptr;
    pressedNodeStableId_ = 0;
    hoveredNodeStableId_ = 0;
    focusedNodeStableId_ = 0;
    pendingDragEvent_ = {};
    lastContinuousInputDispatchMs_ = 0.0;
    previewTransform_ = {};
    wantCaptureMouse_.store(false, std::memory_order_relaxed);
    wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
    lastVertexCount_.store(0, std::memory_order_relaxed);
    lastIndexCount_.store(0, std::memory_order_relaxed);

    if (openGLContext_.isAttached()) {
        openGLContext_.detach();
    }

    imguiContext_ = nullptr;
    contextReady_ = false;
}

void ImGuiDirectHost::resized() {
    attachContextIfNeeded();
    previewTransform_ = {};
}

void ImGuiDirectHost::visibilityChanged() {
    attachContextIfNeeded();
}

void ImGuiDirectHost::setVisible(bool shouldBeVisible) {
    Component::setVisible(shouldBeVisible);
    if (shouldBeVisible) {
        attachContextIfNeeded();
    }
}

void ImGuiDirectHost::parentHierarchyChanged() {
    attachContextIfNeeded();
}

void ImGuiDirectHost::mouseDown(const juce::MouseEvent& e) {
    updateHover(e.position, &e.mods);
    auto hit = hitTestLiveTree(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    if (hit.node != nullptr) {
        pressedNodeStableId_ = hit.stableId;
        const auto localPosition = juce::Point<float>(hit.scenePosition.x - static_cast<float>(hit.sceneBounds.getX()),
                                                      hit.scenePosition.y - static_cast<float>(hit.sceneBounds.getY()));
        grabKeyboardFocus();
        setLiveFocus(hit.stableId);
        if (auto* node = findLiveNodeByStableId(hit.stableId)) {
            invokeLiveMouseDown(*node, localPosition, e.mods);
        }
        renderNow();
    } else {
        pressedNodeStableId_ = 0;
        setLiveFocus(0);
        renderNow();
    }
}

void ImGuiDirectHost::mouseDrag(const juce::MouseEvent& e) {
    // Don't update hover during drag — we know what's pressed, and the hit test
    // + Lua callbacks at 60Hz+ floods the message thread, starving the timer.

    if (pressedNodeStableId_ == 0 || liveRoot_ == nullptr) {
        return;
    }

    auto* pressedNode = findLiveNodeByStableId(pressedNodeStableId_);
    if (pressedNode == nullptr) {
        pressedNodeStableId_ = 0;
        return;
    }

    auto scenePosition = scenePositionFromLocal(e.position);
    auto localPosition = localPositionForNode(pressedNode, scenePosition);
    juce::Point<float> dragDelta(e.getDistanceFromDragStartX() / std::max(1.0f, previewTransform_.scale),
                                 e.getDistanceFromDragStartY() / std::max(1.0f, previewTransform_.scale));

    pendingDragEvent_.valid = true;
    pendingDragEvent_.stableId = pressedNodeStableId_;
    pendingDragEvent_.localPosition = localPosition;
    pendingDragEvent_.dragDelta = dragDelta;
    pendingDragEvent_.mods = e.mods;

    const double nowMs = juce::Time::getMillisecondCounterHiRes();
    if (nowMs - lastContinuousInputDispatchMs_ >= (1000.0 / 60.0)) {
        flushPendingDrag();
    }
}

void ImGuiDirectHost::mouseUp(const juce::MouseEvent& e) {
    flushPendingDrag();
    auto hit = hitTestLiveTree(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    const uint64_t pressedStableId = pressedNodeStableId_;
    pressedNodeStableId_ = 0;

    if (pressedStableId == 0 || liveRoot_ == nullptr) {
        return;
    }

    auto* pressedNode = findLiveNodeByStableId(pressedStableId);
    if (pressedNode == nullptr) {
        return;
    }

    auto scenePosition = scenePositionFromLocal(e.position);
    auto localPosition = localPositionForNode(pressedNode, scenePosition);
    const bool triggerDoubleClick = hit.node != nullptr && hit.stableId == pressedStableId && e.getNumberOfClicks() >= 2;
    const bool triggerClick = hit.node != nullptr && hit.stableId == pressedStableId && !triggerDoubleClick && !e.mouseWasDraggedSinceMouseDown();
    invokeLiveMouseUp(*pressedNode, localPosition, triggerClick, triggerDoubleClick, e.mods);
    renderNow();
}

void ImGuiDirectHost::mouseMove(const juce::MouseEvent& e) {
    updateHover(e.position, &e.mods);
}

void ImGuiDirectHost::mouseExit(const juce::MouseEvent& e) {
    juce::ignoreUnused(e);
    const uint64_t previousHoveredStableId = hoveredNodeStableId_;
    hoveredNodeStableId_ = 0;
    if (previousHoveredStableId != 0) {
        invokeLiveMouseExit(previousHoveredStableId);
        renderNow();
    }
}

void ImGuiDirectHost::mouseWheelMove(const juce::MouseEvent& e, const juce::MouseWheelDetails& wheel) {
    updateHover(e.position, &e.mods);
    auto hit = hitTestLiveTree(e.position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Wheel);
    if (hit.node == nullptr || hit.stableId == 0) {
        return;
    }

    if (auto* node = findLiveNodeByStableId(hit.stableId)) {
        invokeLiveMouseWheel(*node, hit.scenePosition, wheel.deltaY, e.mods);
        renderNow();
    }
}

bool ImGuiDirectHost::keyPressed(const juce::KeyPress& key) {
    if (globalKeyHandler_ && globalKeyHandler_(key)) {
        renderNow();
        return true;
    }

    auto* node = findLiveNodeByStableId(focusedNodeStableId_);
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
        std::fprintf(stderr, "[ImGuiDirectHost] onKeyPress error for %s: %s\n",
                     node->getNodeId().c_str(),
                     err.what());
        return false;
    }

    renderNow();
    if (result.get_type() == sol::type::boolean) {
        return result.get<bool>();
    }
    return true;
}

void ImGuiDirectHost::newOpenGLContextCreated() {
    IMGUI_CHECKVERSION();
    auto* context = ImGui::CreateContext();
    imguiContext_ = context;
    ImGui::SetCurrentContext(context);

    auto& io = ImGui::GetIO();
    io.BackendPlatformName = "manifold_juce_imgui_direct";

    manifold::ui::imgui::configureToolFonts(io);
    manifold::ui::imgui::applyToolTheme();
    ImGui_ImplOpenGL3_Init("#version 150");
    contextReady_ = true;
}

void ImGuiDirectHost::renderOpenGL() {
}

void ImGuiDirectHost::openGLContextClosing() {
    wantCaptureMouse_.store(false, std::memory_order_relaxed);
    wantCaptureKeyboard_.store(false, std::memory_order_relaxed);
    lastVertexCount_.store(0, std::memory_order_relaxed);
    lastIndexCount_.store(0, std::memory_order_relaxed);

    auto* context = reinterpret_cast<ImGuiContext*>(imguiContext_);
    if (context != nullptr) {
        ImGui::SetCurrentContext(context);
        ImGui_ImplOpenGL3_Shutdown();
        ImGui::DestroyContext(context);
        imguiContext_ = nullptr;
    }
    contextReady_ = false;
}

void ImGuiDirectHost::attachContextIfNeeded() {
    if (!isShowing()) {
        return;
    }

    if (!openGLContext_.isAttached()) {
        openGLContext_.attachTo(*this);
    }
}

void ImGuiDirectHost::updateHover(juce::Point<float> position, const juce::ModifierKeys* mods) {
    auto hit = hitTestLiveTree(position, manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode::Pointer);
    const uint64_t nextHoveredStableId = hit.node != nullptr ? hit.stableId : 0;
    const uint64_t previousHoveredStableId = hoveredNodeStableId_;
    hoveredNodeStableId_ = nextHoveredStableId;

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
        if (auto* node = findLiveNodeByStableId(nextHoveredStableId)) {
            invokeLiveMouseMove(*node, localPosition, *mods);
        }
    }
}

manifold::ui::imgui::RuntimeNodeRenderer::HitTestResult ImGuiDirectHost::hitTestLiveTree(
    juce::Point<float> position,
    manifold::ui::imgui::RuntimeNodeRenderer::HitTestMode mode) {
    if (liveRoot_ == nullptr) {
        return {};
    }

    if ((!previewTransform_.valid || previewTransform_.scale <= 0.0f) && getWidth() > 0 && getHeight() > 0) {
        previewTransform_ = renderer_.buildPreviewTransform(*liveRoot_, getWidth(), getHeight(), makeDirectRenderOptions());
    }

    return hitTestLiveTreeDetailed(renderer_, liveRoot_, position, previewTransform_, mode);
}

RuntimeNode* ImGuiDirectHost::findLiveNodeByStableId(uint64_t stableId) const {
    if (liveRoot_ == nullptr || stableId == 0) {
        return nullptr;
    }
    return liveRoot_->findByStableId(stableId);
}

RuntimeNode* ImGuiDirectHost::findLiveWheelTarget(RuntimeNode* node) const {
    while (node != nullptr) {
        if (node->getCallbacks().onMouseWheel.valid()) {
            return node;
        }
        node = node->getParent();
    }
    return nullptr;
}

void ImGuiDirectHost::setLiveFocus(uint64_t stableId) {
    if (liveRoot_ == nullptr) {
        focusedNodeStableId_ = 0;
        return;
    }

    clearFocusRecursive(*liveRoot_);
    focusedNodeStableId_ = stableId;
    if (auto* node = liveRoot_->findByStableId(stableId)) {
        node->setFocused(true);
    }
}

void ImGuiDirectHost::invokeLiveMouseDown(RuntimeNode& node,
                                          juce::Point<float> localPosition,
                                          const juce::ModifierKeys& mods) {
    node.setPressed(true);
    auto& callbacks = node.getCallbacks();
    invokeLuaCallback(callbacks.onMouseDown,
                      "onMouseDown",
                      node.getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiDirectHost::invokeLiveMouseDrag(RuntimeNode& node,
                                          juce::Point<float> localPosition,
                                          juce::Point<float> dragDelta,
                                          const juce::ModifierKeys& mods) {
    auto& callbacks = node.getCallbacks();
    invokeLuaCallback(callbacks.onMouseDrag,
                      "onMouseDrag",
                      node.getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      dragDelta.x,
                      dragDelta.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiDirectHost::invokeLiveMouseUp(RuntimeNode& node,
                                        juce::Point<float> localPosition,
                                        bool triggerClick,
                                        bool triggerDoubleClick,
                                        const juce::ModifierKeys& mods) {
    node.setPressed(false);
    auto& callbacks = node.getCallbacks();
    if (triggerDoubleClick) {
        invokeLuaCallback(callbacks.onDoubleClick, "onDoubleClick", node.getNodeId());
    } else if (triggerClick) {
        invokeLuaCallback(callbacks.onClick, "onClick", node.getNodeId());
    }
    invokeLuaCallback(callbacks.onMouseUp,
                      "onMouseUp",
                      node.getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiDirectHost::invokeLiveMouseMove(RuntimeNode& node,
                                          juce::Point<float> localPosition,
                                          const juce::ModifierKeys& mods) {
    auto& callbacks = node.getCallbacks();
    invokeLuaCallback(callbacks.onMouseMove,
                      "onMouseMove",
                      node.getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

void ImGuiDirectHost::invokeLiveMouseEnter(uint64_t stableId) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setHovered(true);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseEnter, "onMouseEnter", node->getNodeId());
}

void ImGuiDirectHost::invokeLiveMouseExit(uint64_t stableId) {
    auto* node = findLiveNodeByStableId(stableId);
    if (node == nullptr) {
        return;
    }

    node->setHovered(false);
    node->setPressed(false);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseExit, "onMouseExit", node->getNodeId());
}

void ImGuiDirectHost::invokeLiveMouseWheel(RuntimeNode& hitNode,
                                           juce::Point<float> scenePosition,
                                           float deltaY,
                                           const juce::ModifierKeys& mods) {
    auto* node = findLiveWheelTarget(&hitNode);
    if (node == nullptr) {
        return;
    }

    auto localPosition = localPositionForNode(node, scenePosition);
    auto& callbacks = node->getCallbacks();
    invokeLuaCallback(callbacks.onMouseWheel,
                      "onMouseWheel",
                      node->getNodeId(),
                      localPosition.x,
                      localPosition.y,
                      deltaY,
                      mods.isShiftDown(),
                      isCtrlLikeDown(mods),
                      mods.isAltDown());
}

juce::Point<float> ImGuiDirectHost::scenePositionFromLocal(juce::Point<float> local) {
    if ((!previewTransform_.valid || previewTransform_.scale <= 0.0f) && liveRoot_ != nullptr && getWidth() > 0 && getHeight() > 0) {
        previewTransform_ = renderer_.buildPreviewTransform(*liveRoot_, getWidth(), getHeight(), makeDirectRenderOptions());
    }

    if (!previewTransform_.valid || previewTransform_.scale <= 0.0f) {
        return local;
    }

    return juce::Point<float>((local.x - previewTransform_.offsetX) / previewTransform_.scale,
                              (local.y - previewTransform_.offsetY) / previewTransform_.scale);
}

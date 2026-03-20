#include "ImGuiDirectHost.h"

#include "Theme.h"
#include "backends/imgui_impl_opengl3.h"
#include "imgui.h"

#include <algorithm>
#include <array>
#include <cfloat>
#include <chrono>
#include <cstdio>
#include <unordered_set>

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

bool varIsNumber(const juce::var& value) {
    return value.isInt() || value.isInt64() || value.isDouble() || value.isBool();
}

double varToDoubleValue(const juce::var& value, double fallback = 0.0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    if (value.isBool()) {
        return static_cast<bool>(value) ? 1.0 : 0.0;
    }
    return static_cast<double>(value);
}

std::array<float, 4> readColorVec4(const juce::var& value,
                                   std::array<float, 4> fallback = { 0.0f, 0.0f, 0.0f, 0.0f }) {
    if (auto* arr = value.getArray(); arr != nullptr) {
        if (!arr->isEmpty()) fallback[0] = static_cast<float>(varToDoubleValue(arr->getReference(0), fallback[0]));
        if (arr->size() > 1) fallback[1] = static_cast<float>(varToDoubleValue(arr->getReference(1), fallback[1]));
        if (arr->size() > 2) fallback[2] = static_cast<float>(varToDoubleValue(arr->getReference(2), fallback[2]));
        if (arr->size() > 3) fallback[3] = static_cast<float>(varToDoubleValue(arr->getReference(3), fallback[3]));
        return fallback;
    }
    if (auto* obj = value.getDynamicObject(); obj != nullptr) {
        fallback[0] = static_cast<float>(varToDoubleValue(obj->getProperty("r"), fallback[0]));
        fallback[1] = static_cast<float>(varToDoubleValue(obj->getProperty("g"), fallback[1]));
        fallback[2] = static_cast<float>(varToDoubleValue(obj->getProperty("b"), fallback[2]));
        fallback[3] = static_cast<float>(varToDoubleValue(obj->getProperty("a"), fallback[3]));
    }
    return fallback;
}

juce::Rectangle<float> previewRect(const juce::Rectangle<int>& sceneRect,
                                   const ImGuiDirectHost::PreviewTransform& transform) {
    const float x1 = transform.offsetX + static_cast<float>(sceneRect.getX()) * transform.scale;
    const float y1 = transform.offsetY + static_cast<float>(sceneRect.getY()) * transform.scale;
    const float x2 = transform.offsetX + static_cast<float>(sceneRect.getRight()) * transform.scale;
    const float y2 = transform.offsetY + static_cast<float>(sceneRect.getBottom()) * transform.scale;
    return juce::Rectangle<float>(x1, y1, std::max(1.0f, x2 - x1), std::max(1.0f, y2 - y1));
}

juce::Rectangle<float> previewRect(const juce::Rectangle<float>& sceneRect,
                                   const ImGuiDirectHost::PreviewTransform& transform) {
    const float x1 = transform.offsetX + sceneRect.getX() * transform.scale;
    const float y1 = transform.offsetY + sceneRect.getY() * transform.scale;
    const float x2 = transform.offsetX + sceneRect.getRight() * transform.scale;
    const float y2 = transform.offsetY + sceneRect.getBottom() * transform.scale;
    const float left = std::min(x1, x2);
    const float top = std::min(y1, y2);
    const float right = std::max(x1, x2);
    const float bottom = std::max(y1, y2);
    return juce::Rectangle<float>(left, top, std::max(1.0f, right - left), std::max(1.0f, bottom - top));
}

struct SceneTransform {
    float scaleX = 1.0f;
    float scaleY = 1.0f;
    float offsetX = 0.0f;
    float offsetY = 0.0f;
};

SceneTransform composeSceneTransform(const RuntimeNode& node, const SceneTransform& parent) {
    const auto& bounds = node.getBounds();
    const auto& transform = node.getTransform();

    SceneTransform out;
    out.scaleX = parent.scaleX * transform.scaleX;
    out.scaleY = parent.scaleY * transform.scaleY;
    out.offsetX = parent.offsetX + parent.scaleX * (static_cast<float>(bounds.x) + transform.translateX);
    out.offsetY = parent.offsetY + parent.scaleY * (static_cast<float>(bounds.y) + transform.translateY);
    return out;
}

juce::Rectangle<float> sceneRectFromLocalRect(const juce::Rectangle<float>& localRect,
                                              const SceneTransform& transform) {
    const float x1 = transform.offsetX + localRect.getX() * transform.scaleX;
    const float y1 = transform.offsetY + localRect.getY() * transform.scaleY;
    const float x2 = transform.offsetX + localRect.getRight() * transform.scaleX;
    const float y2 = transform.offsetY + localRect.getBottom() * transform.scaleY;
    const float left = std::min(x1, x2);
    const float top = std::min(y1, y2);
    const float right = std::max(x1, x2);
    const float bottom = std::max(y1, y2);
    return juce::Rectangle<float>(left, top, std::max(0.0f, right - left), std::max(0.0f, bottom - top));
}

juce::Rectangle<int> enclosingIntRect(const juce::Rectangle<float>& rect) {
    const int x = juce::roundToInt(std::floor(rect.getX()));
    const int y = juce::roundToInt(std::floor(rect.getY()));
    const int r = juce::roundToInt(std::ceil(rect.getRight()));
    const int b = juce::roundToInt(std::ceil(rect.getBottom()));
    return juce::Rectangle<int>(x, y, std::max(0, r - x), std::max(0, b - y));
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
    snapshot.nodes[static_cast<std::size_t>(index)].stableId = node.getStableId();
    snapshot.nodes[static_cast<std::size_t>(index)].compiledDisplayList = node.getCompiledDisplayList();
    snapshot.nodes[static_cast<std::size_t>(index)].customSurfaceType = node.getCustomSurfaceType();
    snapshot.nodes[static_cast<std::size_t>(index)].customRenderPayload = node.getCustomRenderPayload().clone();

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

struct ImGuiDirectHost::ShaderSurfaceState {
    struct PassResources {
        unsigned int program = 0;
        unsigned int fbo = 0;
        unsigned int colorTex = 0;
        unsigned int depthRbo = 0;
        std::string vertexSource;
        std::string fragmentSource;
        std::string inputTextureUniform = "uInputTex";
        juce::var uniforms;
        std::array<float, 4> clearColor { 0.0f, 0.0f, 0.0f, 0.0f };
        bool enableDepth = false;
    };

    std::string surfaceType;
    std::string payloadSignature;
    std::vector<PassResources> passes;
    int width = 0;
    int height = 0;
    std::string lastError;
};

namespace {

void releaseShaderSurfacePass(ImGuiDirectHost::ShaderSurfaceState::PassResources& pass) {
    if (pass.program != 0) {
        glDeleteProgram(pass.program);
        pass.program = 0;
    }
    if (pass.depthRbo != 0) {
        glDeleteRenderbuffers(1, &pass.depthRbo);
        pass.depthRbo = 0;
    }
    if (pass.colorTex != 0) {
        glDeleteTextures(1, &pass.colorTex);
        pass.colorTex = 0;
    }
    if (pass.fbo != 0) {
        glDeleteFramebuffers(1, &pass.fbo);
        pass.fbo = 0;
    }
}

bool compileSurfaceShader(unsigned int& shaderOut,
                          GLenum type,
                          const std::string& source,
                          std::string& errorOut) {
    shaderOut = glCreateShader(type);
    if (shaderOut == 0) {
        errorOut = "glCreateShader failed";
        return false;
    }

    const GLchar* src = source.c_str();
    glShaderSource(shaderOut, 1, &src, nullptr);
    glCompileShader(shaderOut);

    GLint status = GL_FALSE;
    glGetShaderiv(shaderOut, GL_COMPILE_STATUS, &status);
    if (status == GL_TRUE) {
        return true;
    }

    GLint logLength = 0;
    glGetShaderiv(shaderOut, GL_INFO_LOG_LENGTH, &logLength);
    std::string log;
    if (logLength > 1) {
        log.resize(static_cast<std::size_t>(logLength));
        glGetShaderInfoLog(shaderOut, logLength, nullptr, log.data());
    }
    glDeleteShader(shaderOut);
    shaderOut = 0;
    errorOut = log.empty() ? "shader compile failed" : log;
    return false;
}

bool buildSurfaceProgram(ImGuiDirectHost::ShaderSurfaceState::PassResources& pass,
                         std::string& errorOut) {
    unsigned int vertexShader = 0;
    unsigned int fragmentShader = 0;
    if (!compileSurfaceShader(vertexShader, GL_VERTEX_SHADER, pass.vertexSource, errorOut)) {
        return false;
    }
    if (!compileSurfaceShader(fragmentShader, GL_FRAGMENT_SHADER, pass.fragmentSource, errorOut)) {
        glDeleteShader(vertexShader);
        return false;
    }

    pass.program = glCreateProgram();
    if (pass.program == 0) {
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        errorOut = "glCreateProgram failed";
        return false;
    }

    glAttachShader(pass.program, vertexShader);
    glAttachShader(pass.program, fragmentShader);
    glBindAttribLocation(pass.program, 0, "aPos");
    glBindAttribLocation(pass.program, 1, "aUv");
    glLinkProgram(pass.program);

    GLint linkStatus = GL_FALSE;
    glGetProgramiv(pass.program, GL_LINK_STATUS, &linkStatus);
    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);
    if (linkStatus == GL_TRUE) {
        return true;
    }

    GLint logLength = 0;
    glGetProgramiv(pass.program, GL_INFO_LOG_LENGTH, &logLength);
    std::string log;
    if (logLength > 1) {
        log.resize(static_cast<std::size_t>(logLength));
        glGetProgramInfoLog(pass.program, logLength, nullptr, log.data());
    }
    glDeleteProgram(pass.program);
    pass.program = 0;
    errorOut = log.empty() ? "program link failed" : log;
    return false;
}

bool createSurfaceTarget(ImGuiDirectHost::ShaderSurfaceState::PassResources& pass,
                         int width,
                         int height,
                         std::string& errorOut) {
    glGenTextures(1, &pass.colorTex);
    if (pass.colorTex == 0) {
        errorOut = "glGenTextures failed";
        return false;
    }
    glBindTexture(GL_TEXTURE_2D, pass.colorTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA8,
                 width,
                 height,
                 0,
                 GL_RGBA,
                 GL_UNSIGNED_BYTE,
                 nullptr);

    glGenFramebuffers(1, &pass.fbo);
    if (pass.fbo == 0) {
        errorOut = "glGenFramebuffers failed";
        return false;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, pass.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pass.colorTex, 0);

    if (pass.enableDepth) {
        glGenRenderbuffers(1, &pass.depthRbo);
        if (pass.depthRbo == 0) {
            errorOut = "glGenRenderbuffers failed";
            return false;
        }
        glBindRenderbuffer(GL_RENDERBUFFER, pass.depthRbo);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, pass.depthRbo);
    }

    const auto status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (status == GL_FRAMEBUFFER_COMPLETE) {
        return true;
    }

    errorOut = "framebuffer incomplete";
    return false;
}

void applySurfaceUniformValue(int location, const juce::var& value) {
    if (location < 0) {
        return;
    }

    if (varIsNumber(value)) {
        glUniform1f(location, static_cast<float>(varToDoubleValue(value)));
        return;
    }

    if (auto* arr = value.getArray(); arr != nullptr) {
        if (arr->size() == 2) {
            glUniform2f(location,
                        static_cast<float>(varToDoubleValue(arr->getReference(0))),
                        static_cast<float>(varToDoubleValue(arr->getReference(1))));
        } else if (arr->size() == 3) {
            glUniform3f(location,
                        static_cast<float>(varToDoubleValue(arr->getReference(0))),
                        static_cast<float>(varToDoubleValue(arr->getReference(1))),
                        static_cast<float>(varToDoubleValue(arr->getReference(2))));
        } else if (arr->size() >= 4) {
            glUniform4f(location,
                        static_cast<float>(varToDoubleValue(arr->getReference(0))),
                        static_cast<float>(varToDoubleValue(arr->getReference(1))),
                        static_cast<float>(varToDoubleValue(arr->getReference(2))),
                        static_cast<float>(varToDoubleValue(arr->getReference(3))));
        }
    }
}

void applySurfaceUniformBlock(unsigned int program, const juce::var& uniforms) {
    if (auto* obj = uniforms.getDynamicObject(); obj != nullptr) {
        for (const auto& property : obj->getProperties()) {
            const auto location = glGetUniformLocation(program, property.name.toString().toRawUTF8());
            applySurfaceUniformValue(location, property.value);
        }
    }
}

} // namespace

namespace {

void renderLiveNodeRecursive(ImGuiDirectHost& host,
                             const RuntimeNode& node,
                             const SceneTransform& parentTransform,
                             ImDrawList* drawList,
                             const manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions& options,
                             const ImGuiDirectHost::PreviewTransform& transform,
                             std::unordered_set<uint64_t>& touchedSurfaceIds,
                             double timeSeconds,
                             int depth) {
    if (!node.isVisible()) {
        return;
    }

    const auto& nodeBounds = node.getBounds();
    if (nodeBounds.w <= 0 || nodeBounds.h <= 0) {
        return;
    }

    const auto nodeTransform = composeSceneTransform(node, parentTransform);
    const auto sceneBounds = sceneRectFromLocalRect(juce::Rectangle<float>(0.0f,
                                                                           0.0f,
                                                                           static_cast<float>(nodeBounds.w),
                                                                           static_cast<float>(nodeBounds.h)),
                                                    nodeTransform);
    const auto bounds = previewRect(sceneBounds, transform);
    const auto& style = node.getStyle();
    const float nodeScale = transform.scale * std::min(std::abs(nodeTransform.scaleX), std::abs(nodeTransform.scaleY));

    bool pushedNodeClip = false;
    if (node.hasClipRect()) {
        const auto& clip = node.getClipRect();
        const auto sceneClip = sceneRectFromLocalRect(juce::Rectangle<float>(static_cast<float>(clip.x),
                                                                             static_cast<float>(clip.y),
                                                                             static_cast<float>(clip.w),
                                                                             static_cast<float>(clip.h)),
                                                      nodeTransform);
        const auto clipRect = previewRect(sceneClip, transform);
        drawList->PushClipRect(toImVec2(clipRect), toImVec2BottomRight(clipRect), true);
        pushedNodeClip = true;
    }

    const bool hasBackground = ((style.background >> 24) & 0xffu) != 0u;
    const bool hasBorder = ((style.border >> 24) & 0xffu) != 0u && style.borderWidth > 0.0f;
    const float cornerRadius = std::max(0.0f, style.cornerRadius * nodeScale);
    const float borderWidth = std::max(1.0f, style.borderWidth * nodeScale);

    if (hasBackground) {
        drawList->AddRectFilled(toImVec2(bounds), toImVec2BottomRight(bounds), toImColor(style.background), cornerRadius);
    } else if (options.showFallbackBoxes && depth > 0) {
        drawList->AddRectFilled(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(255, 255, 255, 12), cornerRadius);
    }

    if (!node.getCustomSurfaceType().empty()) {
        touchedSurfaceIds.insert(node.getStableId());
        const auto textureHandle = host.prepareCustomSurfaceTexture(node,
                                                                    std::max(1, juce::roundToInt(sceneBounds.getWidth())),
                                                                    std::max(1, juce::roundToInt(sceneBounds.getHeight())),
                                                                    timeSeconds);
        if (textureHandle != 0) {
            drawList->AddImage(static_cast<ImTextureID>(textureHandle),
                               toImVec2(bounds),
                               toImVec2BottomRight(bounds),
                               ImVec2(0, 0),
                               ImVec2(1, 1),
                               IM_COL32_WHITE);
        }
    }

    if (hasBorder) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), toImColor(style.border), cornerRadius, 0, borderWidth);
    } else if (options.showFallbackBoxes) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(148, 163, 184, depth == 0 ? 140 : 90), cornerRadius, 0, 1.0f);
    }

    DrawState state;
    if (auto compiled = node.getCompiledDisplayList(); compiled && !compiled->commands.empty()) {
        renderCompiledDisplayList(*compiled, enclosingIntRect(sceneBounds), drawList, state, transform);
    }

    auto children = sortedLiveChildren(node);
    for (auto* child : children) {
        renderLiveNodeRecursive(host,
                                *child,
                                nodeTransform,
                                drawList,
                                options,
                                transform,
                                touchedSurfaceIds,
                                timeSeconds,
                                depth + 1);
    }

    if (pushedNodeClip) {
        drawList->PopClipRect();
    }
}

void renderLiveTree(ImGuiDirectHost& host,
                    const RuntimeNode& root,
                    ImDrawList* drawList,
                    const manifold::ui::imgui::RuntimeNodeRenderer::RenderOptions& options,
                    const ImGuiDirectHost::PreviewTransform& transform,
                    std::unordered_set<uint64_t>& touchedSurfaceIds,
                    double timeSeconds) {
    renderLiveNodeRecursive(host,
                            root,
                            SceneTransform{},
                            drawList,
                            options,
                            transform,
                            touchedSurfaceIds,
                            timeSeconds,
                            0);
}

} // namespace

ImGuiDirectHost::ImGuiDirectHost() {
    setOpaque(true);
    setWantsKeyboardFocus(true);
    setMouseClickGrabsKeyboardFocus(true);
    setInterceptsMouseClicks(true, true);

    openGLContext_.setRenderer(this);
    openGLContext_.setComponentPaintingEnabled(false);
#ifndef __ANDROID__
    openGLContext_.setPersistentAttachment(true);
#endif
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

bool ImGuiDirectHost::ensureSurfaceQuadGeometry() {
    if (surfaceQuadVao_ != 0 && surfaceQuadVbo_ != 0 && surfaceQuadIbo_ != 0) {
        return true;
    }

    const float vertices[] = {
        -1.0f, -1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 1.0f,
    };
    const unsigned short indices[] = { 0, 1, 2, 0, 2, 3 };

    glGenBuffers(1, &surfaceQuadVbo_);
    glBindBuffer(GL_ARRAY_BUFFER, surfaceQuadVbo_);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    glGenBuffers(1, &surfaceQuadIbo_);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, surfaceQuadIbo_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    glGenVertexArrays(1, &surfaceQuadVao_);
    glBindVertexArray(surfaceQuadVao_);
    glBindBuffer(GL_ARRAY_BUFFER, surfaceQuadVbo_);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, surfaceQuadIbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 4, nullptr);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(float) * 4, reinterpret_cast<const void*>(sizeof(float) * 2));
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    return surfaceQuadVao_ != 0;
}

void ImGuiDirectHost::releaseSurfaceQuadGeometry() {
    if (surfaceQuadVao_ != 0) {
        glDeleteVertexArrays(1, &surfaceQuadVao_);
        surfaceQuadVao_ = 0;
    }
    if (surfaceQuadVbo_ != 0) {
        glDeleteBuffers(1, &surfaceQuadVbo_);
        surfaceQuadVbo_ = 0;
    }
    if (surfaceQuadIbo_ != 0) {
        glDeleteBuffers(1, &surfaceQuadIbo_);
        surfaceQuadIbo_ = 0;
    }
}

void ImGuiDirectHost::releaseShaderSurfaces() {
    for (auto& [_, state] : shaderSurfaceStates_) {
        if (!state) {
            continue;
        }
        for (auto& pass : state->passes) {
            releaseShaderSurfacePass(pass);
        }
        state->passes.clear();
    }
    shaderSurfaceStates_.clear();
}

void ImGuiDirectHost::pruneShaderSurfaces(const std::unordered_set<uint64_t>& touchedStableIds) {
    for (auto it = shaderSurfaceStates_.begin(); it != shaderSurfaceStates_.end();) {
        if (touchedStableIds.find(it->first) != touchedStableIds.end()) {
            ++it;
            continue;
        }

        if (it->second) {
            for (auto& pass : it->second->passes) {
                releaseShaderSurfacePass(pass);
            }
        }
        it = shaderSurfaceStates_.erase(it);
    }
}

std::uintptr_t ImGuiDirectHost::prepareCustomSurfaceTexture(const RuntimeNode& node,
                                                            int width,
                                                            int height,
                                                            double timeSeconds) {
    if (node.getStableId() == 0 || width <= 0 || height <= 0) {
        return 0;
    }

    const auto surfaceType = node.getCustomSurfaceType();
    if (surfaceType != "gpu_shader" && surfaceType != "opengl") {
        return 0;
    }

    const auto payload = node.getCustomRenderPayload();
    if (payload.isVoid() || payload.isUndefined()) {
        return 0;
    }

    auto* payloadObj = payload.getDynamicObject();
    if (payloadObj == nullptr) {
        return 0;
    }

    const auto kind = payloadObj->getProperty("kind").toString().toStdString();
    const auto shaderLanguage = payloadObj->getProperty("shaderLanguage").toString().toStdString();
    if (!kind.empty() && kind != "shaderQuad") {
        return 0;
    }
    if (!shaderLanguage.empty() && shaderLanguage != "glsl") {
        return 0;
    }

    const auto payloadSignature = juce::JSON::toString(payload, false).toStdString();
    auto& state = shaderSurfaceStates_[node.getStableId()];
    if (!state) {
        state = std::make_unique<ShaderSurfaceState>();
    }

    const bool descriptorChanged = state->surfaceType != surfaceType || state->payloadSignature != payloadSignature;
    if (descriptorChanged) {
        for (auto& pass : state->passes) {
            releaseShaderSurfacePass(pass);
        }
        state->passes.clear();
        state->surfaceType = surfaceType;
        state->payloadSignature = payloadSignature;
        state->lastError.clear();

        auto configurePass = [&](const juce::var& passVar) {
            auto* passObj = passVar.getDynamicObject();
            if (passObj == nullptr) {
                return false;
            }

            ShaderSurfaceState::PassResources pass;
            pass.vertexSource = passObj->getProperty("vertexShader").toString().toStdString();
            pass.fragmentSource = passObj->getProperty("fragmentShader").toString().toStdString();
            pass.inputTextureUniform = passObj->getProperty("inputTextureUniform").toString().toStdString();
            if (pass.inputTextureUniform.empty()) {
                pass.inputTextureUniform = "uInputTex";
            }
            pass.uniforms = passObj->getProperty("uniforms").clone();
            pass.clearColor = readColorVec4(passObj->getProperty("clearColor"), { 0.0f, 0.0f, 0.0f, 0.0f });
            pass.enableDepth = static_cast<bool>(passObj->getProperty("depth"));
            if (pass.vertexSource.empty() || pass.fragmentSource.empty()) {
                state->lastError = "shader pass missing source";
                return false;
            }
            if (!buildSurfaceProgram(pass, state->lastError)) {
                return false;
            }
            state->passes.push_back(std::move(pass));
            return true;
        };

        if (auto* passes = payloadObj->getProperty("passes").getArray(); passes != nullptr && !passes->isEmpty()) {
            for (const auto& passVar : *passes) {
                if (!configurePass(passVar)) {
                    break;
                }
            }
        } else {
            configurePass(payload);
        }

        if (state->passes.empty() || !state->lastError.empty()) {
            return 0;
        }
        state->width = 0;
        state->height = 0;
    }

    if (state->passes.empty() || !state->lastError.empty()) {
        return 0;
    }

    if (state->width != width || state->height != height) {
        state->lastError.clear();
        for (auto& pass : state->passes) {
            if (pass.depthRbo != 0) {
                glDeleteRenderbuffers(1, &pass.depthRbo);
                pass.depthRbo = 0;
            }
            if (pass.colorTex != 0) {
                glDeleteTextures(1, &pass.colorTex);
                pass.colorTex = 0;
            }
            if (pass.fbo != 0) {
                glDeleteFramebuffers(1, &pass.fbo);
                pass.fbo = 0;
            }
            if (!createSurfaceTarget(pass, width, height, state->lastError)) {
                return 0;
            }
        }
        state->width = width;
        state->height = height;
    }

    if (!ensureSurfaceQuadGeometry()) {
        return 0;
    }

    glDisable(GL_SCISSOR_TEST);
    glBindVertexArray(surfaceQuadVao_);

    unsigned int inputTexture = 0;
    for (std::size_t i = 0; i < state->passes.size(); ++i) {
        auto& pass = state->passes[i];
        glBindFramebuffer(GL_FRAMEBUFFER, pass.fbo);
        glViewport(0, 0, width, height);
        if (pass.enableDepth) {
            glEnable(GL_DEPTH_TEST);
            glClear(GL_DEPTH_BUFFER_BIT);
        } else {
            glDisable(GL_DEPTH_TEST);
        }
        glClearColor(pass.clearColor[0], pass.clearColor[1], pass.clearColor[2], pass.clearColor[3]);
        GLbitfield clearMask = GL_COLOR_BUFFER_BIT;
        if (pass.enableDepth) {
            clearMask |= GL_DEPTH_BUFFER_BIT;
        }
        glClear(clearMask);

        glUseProgram(pass.program);
        applySurfaceUniformBlock(pass.program, pass.uniforms);

        const auto timeLoc = glGetUniformLocation(pass.program, "uTime");
        if (timeLoc >= 0) {
            glUniform1f(timeLoc, static_cast<float>(timeSeconds));
        }
        const auto resolutionLoc = glGetUniformLocation(pass.program, "uResolution");
        if (resolutionLoc >= 0) {
            glUniform2f(resolutionLoc, static_cast<float>(width), static_cast<float>(height));
        }

        if (i > 0 && inputTexture != 0) {
            const auto inputLoc = glGetUniformLocation(pass.program, pass.inputTextureUniform.c_str());
            if (inputLoc >= 0) {
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, inputTexture);
                glUniform1i(inputLoc, 0);
            }
        }

        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, nullptr);
        if (i > 0 && inputTexture != 0) {
            glBindTexture(GL_TEXTURE_2D, 0);
        }
        inputTexture = pass.colorTex;
    }

    glBindVertexArray(0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glUseProgram(0);
    glDisable(GL_DEPTH_TEST);

    return state->passes.empty() ? 0 : static_cast<std::uintptr_t>(state->passes.back().colorTex);
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

    std::unordered_set<uint64_t> touchedSurfaceIds;
    if (liveRoot_ != nullptr) {
        renderLiveTree(*this,
                       *liveRoot_,
                       ImGui::GetForegroundDrawList(),
                       renderOptions,
                       previewTransform_,
                       touchedSurfaceIds,
                       juce::Time::getMillisecondCounterHiRes() * 0.001);
    }
    pruneShaderSurfaces(touchedSurfaceIds);

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

    if (contextReady_ && openGLContext_.makeActive()) {
        releaseShaderSurfaces();
        releaseSurfaceQuadGeometry();
        juce::OpenGLContext::deactivateCurrentContext();
    }

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

    releaseShaderSurfaces();
    releaseSurfaceQuadGeometry();

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

#include "RuntimeNodeRenderer.h"

#include "imgui.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <vector>

namespace manifold::ui::imgui {
namespace {

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

ImU32 toImColor(uint32_t argb) {
    const auto a = static_cast<ImU32>((argb >> 24) & 0xffu);
    const auto r = static_cast<ImU32>((argb >> 16) & 0xffu);
    const auto g = static_cast<ImU32>((argb >> 8) & 0xffu);
    const auto b = static_cast<ImU32>(argb & 0xffu);
    return IM_COL32(r, g, b, a);
}

int varToInt(const juce::var& value, int fallback = 0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    return static_cast<int>(value);
}

double varToDouble(const juce::var& value, double fallback = 0.0) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    return static_cast<double>(value);
}

uint32_t varToColor(const juce::var& value, uint32_t fallback = 0xffffffffu) {
    if (value.isVoid() || value.isUndefined()) {
        return fallback;
    }
    if (value.isInt() || value.isInt64() || value.isDouble()) {
        return static_cast<uint32_t>(value.toString().getLargeIntValue());
    }
    return fallback;
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

juce::Rectangle<float> sceneRectForNode(const RuntimeNode& node, const SceneTransform& parent) {
    const auto nodeTransform = composeSceneTransform(node, parent);
    const auto& bounds = node.getBounds();
    return sceneRectFromLocalRect(juce::Rectangle<float>(0.0f,
                                                         0.0f,
                                                         static_cast<float>(bounds.w),
                                                         static_cast<float>(bounds.h)),
                                  nodeTransform);
}

juce::Rectangle<int> enclosingIntRect(const juce::Rectangle<float>& rect) {
    const float left = rect.getX();
    const float top = rect.getY();
    const float right = rect.getRight();
    const float bottom = rect.getBottom();
    
    // Handle negative/zero dimensions by ensuring proper ordering
    const float minX = std::min(left, right);
    const float minY = std::min(top, bottom);
    const float maxX = std::max(left, right);
    const float maxY = std::max(top, bottom);
    
    const int x = juce::roundToInt(std::floor(minX));
    const int y = juce::roundToInt(std::floor(minY));
    const int r = juce::roundToInt(std::ceil(maxX));
    const int b = juce::roundToInt(std::ceil(maxY));
    return juce::Rectangle<int>(x, y, std::max(0, r - x), std::max(0, b - y));
}

void unionRect(juce::Rectangle<float>& bounds, const juce::Rectangle<float>& other, bool& hasBounds) {
    if (!hasBounds) {
        bounds = other;
        hasBounds = true;
        return;
    }

    const float left = std::min(bounds.getX(), other.getX());
    const float top = std::min(bounds.getY(), other.getY());
    const float right = std::max(bounds.getRight(), other.getRight());
    const float bottom = std::max(bounds.getBottom(), other.getBottom());
    bounds = juce::Rectangle<float>(left, top, std::max(0.0f, right - left), std::max(0.0f, bottom - top));
}

void collectVisibleBounds(const RuntimeNode& node,
                          const SceneTransform& parentTransform,
                          juce::Rectangle<float>& bounds,
                          bool& hasBounds) {
    if (!node.isVisible()) {
        return;
    }

    const auto nodeTransform = composeSceneTransform(node, parentTransform);
    const auto absolute = sceneRectFromLocalRect(juce::Rectangle<float>(0.0f,
                                                                        0.0f,
                                                                        static_cast<float>(node.getBounds().w),
                                                                        static_cast<float>(node.getBounds().h)),
                                                 nodeTransform);
    if (absolute.getWidth() > 0.0f && absolute.getHeight() > 0.0f) {
        unionRect(bounds, absolute, hasBounds);
    }

    for (auto* child : node.getChildren()) {
        if (child != nullptr) {
            collectVisibleBounds(*child, nodeTransform, bounds, hasBounds);
        }
    }
}

juce::Rectangle<float> previewRect(const juce::Rectangle<float>& sceneRect,
                                   const RuntimeNodeRenderer::PreviewTransform& transform) {
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

juce::Rectangle<float> previewRect(const juce::Rectangle<int>& sceneRect,
                                   const RuntimeNodeRenderer::PreviewTransform& transform) {
    return previewRect(juce::Rectangle<float>(static_cast<float>(sceneRect.getX()),
                                              static_cast<float>(sceneRect.getY()),
                                              static_cast<float>(sceneRect.getWidth()),
                                              static_cast<float>(sceneRect.getHeight())),
                       transform);
}

ImVec2 toImVec2(const juce::Rectangle<float>& rect) {
    return ImVec2(rect.getX(), rect.getY());
}

ImVec2 toImVec2BottomRight(const juce::Rectangle<float>& rect) {
    return ImVec2(rect.getRight(), rect.getBottom());
}

void renderDisplayList(const RuntimeNode& node,
                       const juce::Rectangle<float>& sceneBounds,
                       ImDrawList* drawList,
                       DrawState& state,
                       const RuntimeNodeRenderer::PreviewTransform& transform) {
    if (!node.hasDisplayList()) {
        return;
    }

    auto* arr = node.getDisplayList().getArray();
    if (arr == nullptr) {
        return;
    }

    const auto& bounds = node.getBounds();
    const float localScaleX = bounds.w > 0 ? (sceneBounds.getWidth() / static_cast<float>(bounds.w)) : 1.0f;
    const float localScaleY = bounds.h > 0 ? (sceneBounds.getHeight() / static_cast<float>(bounds.h)) : 1.0f;
    const float renderScale = transform.scale * std::min(std::abs(localScaleX), std::abs(localScaleY));

    auto localRectToPreview = [&](float rx, float ry, float rw, float rh) {
        return previewRect(juce::Rectangle<float>(sceneBounds.getX() + rx * localScaleX,
                                                  sceneBounds.getY() + ry * localScaleY,
                                                  std::max(1.0f, rw * localScaleX),
                                                  std::max(1.0f, rh * localScaleY)),
                           transform);
    };
    auto localPointToPreview = [&](float px, float py) {
        return ImVec2(transform.offsetX + (sceneBounds.getX() + px * localScaleX) * transform.scale,
                      transform.offsetY + (sceneBounds.getY() + py * localScaleY) * transform.scale);
    };

    std::vector<DrawState> stateStack;

    for (const auto& item : *arr) {
        auto* obj = item.getDynamicObject();
        if (obj == nullptr) {
            continue;
        }

        const auto cmd = obj->getProperty("cmd").toString().toStdString();
        const int x = varToInt(obj->getProperty("x"));
        const int y = varToInt(obj->getProperty("y"));
        const int w = varToInt(obj->getProperty("w"));
        const int h = varToInt(obj->getProperty("h"));
        const float radius = static_cast<float>(varToDouble(obj->getProperty("radius"), 0.0));
        const float thickness = static_cast<float>(varToDouble(obj->getProperty("thickness"), 1.0));

        if (cmd == "save") {
            stateStack.push_back(state);
            continue;
        }
        if (cmd == "restore") {
            if (!stateStack.empty()) {
                const auto saved = stateStack.back();
                stateStack.pop_back();
                popClipStackTo(drawList, state.clipStack, saved.clipStack.size());
                state = saved;
            }
            continue;
        }

        if (obj->hasProperty("color")) {
            state.color = toImColor(varToColor(obj->getProperty("color")));
        }
        if (obj->hasProperty("fontSize")) {
            state.fontSize = static_cast<float>(varToDouble(obj->getProperty("fontSize"), 13.0));
        }

        const auto sceneRect = juce::Rectangle<float>(sceneBounds.getX() + static_cast<float>(x) * localScaleX,
                                                      sceneBounds.getY() + static_cast<float>(y) * localScaleY,
                                                      std::max(1.0f, static_cast<float>(w) * localScaleX),
                                                      std::max(1.0f, static_cast<float>(h) * localScaleY));
        const auto rect = previewRect(sceneRect, transform);
        const float scaledRadius = radius * renderScale;
        const float scaledThickness = std::max(1.0f, thickness * renderScale);

        if (cmd == "fillRect") {
            drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color);
        } else if (cmd == "drawRect") {
            drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
        } else if (cmd == "fillRoundedRect") {
            drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius);
        } else if (cmd == "drawRoundedRect") {
            drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
        } else if (cmd == "drawLine") {
            const float x1 = static_cast<float>(varToDouble(obj->getProperty("x1"), x));
            const float y1 = static_cast<float>(varToDouble(obj->getProperty("y1"), y));
            const float x2 = static_cast<float>(varToDouble(obj->getProperty("x2"), x + w));
            const float y2 = static_cast<float>(varToDouble(obj->getProperty("y2"), y + h));
            drawList->AddLine(localPointToPreview(x1, y1), localPointToPreview(x2, y2), state.color, scaledThickness);
        } else if (cmd == "drawBezier") {
            // Cubic bezier: p1 -> cp1 -> cp2 -> p4
            const float x1 = static_cast<float>(varToDouble(obj->getProperty("x1"), x));
            const float y1 = static_cast<float>(varToDouble(obj->getProperty("y1"), y));
            const float cx1 = static_cast<float>(varToDouble(obj->getProperty("cx1"), x));
            const float cy1 = static_cast<float>(varToDouble(obj->getProperty("cy1"), y));
            const float cx2 = static_cast<float>(varToDouble(obj->getProperty("cx2"), x + w));
            const float cy2 = static_cast<float>(varToDouble(obj->getProperty("cy2"), y + h));
            const float x2 = static_cast<float>(varToDouble(obj->getProperty("x2"), x + w));
            const float y2 = static_cast<float>(varToDouble(obj->getProperty("y2"), y + h));
            const int numSegments = varToInt(obj->getProperty("segments"), 0); // 0 = auto
            drawList->AddBezierCubic(
                localPointToPreview(x1, y1),
                localPointToPreview(cx1, cy1),
                localPointToPreview(cx2, cy2),
                localPointToPreview(x2, y2),
                state.color,
                scaledThickness,
                numSegments);
        } else if (cmd == "drawText") {
            const auto text = obj->getProperty("text").toString().toStdString();
            const auto align = obj->getProperty("align").toString().toStdString();
            const auto valign = obj->getProperty("valign").toString().toStdString();
            const float fontSize = std::max(1.0f, state.fontSize * renderScale);
            auto* font = ImGui::GetFont();
            if (font == nullptr) {
                continue;
            }
            const ImVec2 textSize = font->CalcTextSizeA(fontSize, FLT_MAX, 0.0f, text.c_str());
            float textX = rect.getX();
            float textY = rect.getY();

            if (align == "center") {
                textX += std::max(0.0f, (rect.getWidth() - textSize.x) * 0.5f);
            } else if (align == "right") {
                textX += std::max(0.0f, rect.getWidth() - textSize.x - 4.0f * renderScale);
            } else {
                textX += 4.0f * renderScale;
            }

            if (valign == "middle") {
                textY += std::max(0.0f, (rect.getHeight() - textSize.y) * 0.5f);
            } else if (valign == "bottom") {
                textY += std::max(0.0f, rect.getHeight() - textSize.y - 2.0f * renderScale);
            } else {
                textY += 2.0f * renderScale;
            }

            drawList->PushClipRect(toImVec2(rect), toImVec2BottomRight(rect), true);
            drawList->AddText(font, fontSize, ImVec2(textX, textY), state.color, text.c_str());
            drawList->PopClipRect();
        } else if (cmd == "drawImage") {
            const auto textureHandle = static_cast<uintptr_t>(varToInt(obj->getProperty("textureId"), varToInt(obj->getProperty("texture"))));
            const auto textureId = static_cast<ImTextureID>(textureHandle);
            const float u0 = static_cast<float>(varToDouble(obj->getProperty("u0"), 0.0));
            const float v0 = static_cast<float>(varToDouble(obj->getProperty("v0"), 0.0));
            const float u1 = static_cast<float>(varToDouble(obj->getProperty("u1"), 1.0));
            const float v1 = static_cast<float>(varToDouble(obj->getProperty("v1"), 1.0));
            if (textureHandle != 0) {
                drawList->AddImage(textureId,
                                   toImVec2(rect),
                                   toImVec2BottomRight(rect),
                                   ImVec2(u0, v0),
                                   ImVec2(u1, v1),
                                   state.color);
            }
        } else if (cmd == "clipRect") {
            const auto clipMin = toImVec2(rect);
            const auto clipMax = toImVec2BottomRight(rect);
            const bool validClip = clipMin.x < clipMax.x && clipMin.y < clipMax.y;
            if (validClip) {
                drawList->PushClipRect(clipMin, clipMax, true);
                state.clipStack.push_back(enclosingIntRect(sceneRect));
            }
        } else if (cmd == "popClipRect") {
            if (!state.clipStack.empty()) {
                drawList->PopClipRect();
                state.clipStack.pop_back();
            }
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

void renderCompiledDisplayList(const CompiledDisplayList& compiled,
                               const RuntimeNode& node,
                               const juce::Rectangle<float>& sceneBounds,
                               ImDrawList* drawList,
                               DrawState& state,
                               const RuntimeNodeRenderer::PreviewTransform& transform) {
    const auto& bounds = node.getBounds();
    const float localScaleX = bounds.w > 0 ? (sceneBounds.getWidth() / static_cast<float>(bounds.w)) : 1.0f;
    const float localScaleY = bounds.h > 0 ? (sceneBounds.getHeight() / static_cast<float>(bounds.h)) : 1.0f;
    const float renderScale = transform.scale * std::min(std::abs(localScaleX), std::abs(localScaleY));

    auto localRectToPreview = [&](float rx, float ry, float rw, float rh) {
        return previewRect(juce::Rectangle<float>(sceneBounds.getX() + rx * localScaleX,
                                                  sceneBounds.getY() + ry * localScaleY,
                                                  std::max(1.0f, rw * localScaleX),
                                                  std::max(1.0f, rh * localScaleY)),
                           transform);
    };
    auto localPointToPreview = [&](float px, float py) {
        return ImVec2(transform.offsetX + (sceneBounds.getX() + px * localScaleX) * transform.scale,
                      transform.offsetY + (sceneBounds.getY() + py * localScaleY) * transform.scale);
    };

    std::vector<DrawState> stateStack;

    for (const auto& cmd : compiled.commands) {
        if (cmd.type == CompiledDrawCmd::Type::Save) {
            stateStack.push_back(state);
            continue;
        }
        if (cmd.type == CompiledDrawCmd::Type::Restore) {
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

        const auto sceneRect = juce::Rectangle<float>(sceneBounds.getX() + cmd.x * localScaleX,
                                                      sceneBounds.getY() + cmd.y * localScaleY,
                                                      std::max(1.0f, cmd.w * localScaleX),
                                                      std::max(1.0f, cmd.h * localScaleY));
        const auto rect = previewRect(sceneRect, transform);
        const float scaledRadius = cmd.radius * renderScale;
        const float scaledThickness = std::max(1.0f, cmd.thickness * renderScale);

        switch (cmd.type) {
            case CompiledDrawCmd::Type::FillRect:
                drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color);
                break;
            case CompiledDrawCmd::Type::DrawRect:
                drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
                break;
            case CompiledDrawCmd::Type::FillRoundedRect:
                drawList->AddRectFilled(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius);
                break;
            case CompiledDrawCmd::Type::DrawRoundedRect:
                drawList->AddRect(toImVec2(rect), toImVec2BottomRight(rect), state.color, scaledRadius, 0, scaledThickness);
                break;
            case CompiledDrawCmd::Type::DrawLine:
                drawList->AddLine(localPointToPreview(cmd.x1, cmd.y1),
                                  localPointToPreview(cmd.x2, cmd.y2),
                                  state.color,
                                  scaledThickness);
                break;
            case CompiledDrawCmd::Type::DrawBezier:
                drawList->AddBezierCubic(localPointToPreview(cmd.x1, cmd.y1),
                                         localPointToPreview(cmd.cx1, cmd.cy1),
                                         localPointToPreview(cmd.cx2, cmd.cy2),
                                         localPointToPreview(cmd.x2, cmd.y2),
                                         state.color,
                                         scaledThickness,
                                         cmd.segments);
                break;
            case CompiledDrawCmd::Type::DrawText: {
                const float fontSize = std::max(1.0f, state.fontSize * renderScale);
                const ImVec2 textSize = ImGui::GetFont()->CalcTextSizeA(fontSize, FLT_MAX, 0.0f, cmd.text.c_str());
                float textX = rect.getX();
                float textY = rect.getY();

                if (cmd.align == "center") {
                    textX += std::max(0.0f, (rect.getWidth() - textSize.x) * 0.5f);
                } else if (cmd.align == "right") {
                    textX += std::max(0.0f, rect.getWidth() - textSize.x - 4.0f * renderScale);
                } else {
                    textX += 4.0f * renderScale;
                }

                if (cmd.valign == "middle") {
                    textY += std::max(0.0f, (rect.getHeight() - textSize.y) * 0.5f);
                } else if (cmd.valign == "bottom") {
                    textY += std::max(0.0f, rect.getHeight() - textSize.y - 2.0f * renderScale);
                } else {
                    textY += 2.0f * renderScale;
                }

                drawList->PushClipRect(toImVec2(rect), toImVec2BottomRight(rect), true);
                drawList->AddText(ImGui::GetFont(), fontSize, ImVec2(textX, textY), state.color, cmd.text.c_str());
                drawList->PopClipRect();
                break;
            }
            case CompiledDrawCmd::Type::DrawImage:
                if (cmd.textureId != 0) {
                    drawList->AddImage(static_cast<ImTextureID>(cmd.textureId),
                                       toImVec2(rect),
                                       toImVec2BottomRight(rect),
                                       ImVec2(cmd.u0, cmd.v0),
                                       ImVec2(cmd.u1, cmd.v1),
                                       state.color);
                }
                break;
            case CompiledDrawCmd::Type::ClipRect: {
                const auto clipMin = toImVec2(rect);
                const auto clipMax = toImVec2BottomRight(rect);
                const bool validClip = clipMin.x < clipMax.x && clipMin.y < clipMax.y;
                if (validClip) {
                    drawList->PushClipRect(clipMin, clipMax, true);
                    state.clipStack.push_back(enclosingIntRect(sceneRect));
                }
                break;
            }
            case CompiledDrawCmd::Type::PopClipRect:
                if (!state.clipStack.empty()) {
                    drawList->PopClipRect();
                    state.clipStack.pop_back();
                }
                break;
            case CompiledDrawCmd::Type::SetColor:
            case CompiledDrawCmd::Type::SetFontSize:
            case CompiledDrawCmd::Type::Save:
            case CompiledDrawCmd::Type::Restore:
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

std::vector<RuntimeNode*> sortedChildren(const RuntimeNode& node) {
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

void renderNodeRecursive(const RuntimeNode& node,
                         const SceneTransform& parentTransform,
                         ImDrawList* drawList,
                         uint64_t selectedStableId,
                         uint64_t hoveredStableId,
                         const RuntimeNodeRenderer::PreviewTransform& transform,
                         const RuntimeNodeRenderer::RenderOptions& options,
                         int depth) {
    if (!node.isVisible()) {
        return;
    }

    const auto nodeTransform = composeSceneTransform(node, parentTransform);
    const auto sceneBounds = sceneRectFromLocalRect(juce::Rectangle<float>(0.0f,
                                                                           0.0f,
                                                                           static_cast<float>(node.getBounds().w),
                                                                           static_cast<float>(node.getBounds().h)),
                                                    nodeTransform);
    if (sceneBounds.getWidth() <= 0.0f || sceneBounds.getHeight() <= 0.0f) {
        return;
    }

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

    if (hasBorder) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), toImColor(style.border), cornerRadius, 0, borderWidth);
    } else if (options.showFallbackBoxes) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(148, 163, 184, depth == 0 ? 140 : 90), cornerRadius, 0, 1.0f);
    }

    DrawState state;
    if (auto compiled = node.getCompiledDisplayList(); compiled && !compiled->commands.empty()) {
        renderCompiledDisplayList(*compiled, node, sceneBounds, drawList, state, transform);
    } else if (node.hasDisplayList()) {
        renderDisplayList(node, sceneBounds, drawList, state, transform);
    }

    const bool largeEnoughForLabel = bounds.getWidth() >= 60.0f && bounds.getHeight() >= 18.0f;
    if (options.showNodeLabels && largeEnoughForLabel) {
        const std::string label = !node.getNodeId().empty()
            ? node.getNodeId()
            : (!node.getWidgetType().empty() ? node.getWidgetType() : std::string("<node>"));
        drawList->AddText(ImVec2(bounds.getX() + 4.0f, bounds.getY() + 3.0f),
                          IM_COL32(226, 232, 240, 220),
                          label.c_str());
    }

    if (options.showSurfaceLabels && !node.getCustomSurfaceType().empty()
        && bounds.getWidth() >= 80.0f && bounds.getHeight() >= 30.0f) {
        const std::string surfaceLabel = std::string("surface: ") + node.getCustomSurfaceType();
        drawList->AddText(ImVec2(bounds.getX() + 4.0f, bounds.getBottom() - 16.0f),
                          IM_COL32(216, 180, 254, 220),
                          surfaceLabel.c_str());
    }

    if (options.showHoveredOutline && node.getStableId() == hoveredStableId) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(255, 255, 255, 180), cornerRadius, 0, 2.0f);
    }
    if (options.showSelectedOutline && node.getStableId() == selectedStableId) {
        drawList->AddRect(toImVec2(bounds), toImVec2BottomRight(bounds), IM_COL32(56, 189, 248, 255), cornerRadius, 0, 3.0f);
    }

    for (auto* child : sortedChildren(node)) {
        renderNodeRecursive(*child,
                            nodeTransform,
                            drawList,
                            selectedStableId,
                            hoveredStableId,
                            transform,
                            options,
                            depth + 1);
    }

    if (pushedNodeClip) {
        drawList->PopClipRect();
    }
}

bool nodeMatchesHitMode(const RuntimeNode& node, RuntimeNodeRenderer::HitTestMode mode) {
    const auto& caps = node.getInputCapabilities();
    switch (mode) {
        case RuntimeNodeRenderer::HitTestMode::Pointer:
            return caps.pointer;
        case RuntimeNodeRenderer::HitTestMode::Wheel:
            return caps.pointer || caps.wheel;
        case RuntimeNodeRenderer::HitTestMode::AnyVisible:
            return true;
    }
    return false;
}

RuntimeNodeRenderer::HitTestResult hitTestRecursive(const RuntimeNode& node,
                                                    juce::Point<float> position,
                                                    const SceneTransform& parentTransform,
                                                    RuntimeNodeRenderer::HitTestMode mode) {
    if (!node.isVisible()) {
        return {};
    }

    const auto nodeTransform = composeSceneTransform(node, parentTransform);
    const auto bounds = sceneRectFromLocalRect(juce::Rectangle<float>(0.0f,
                                                                      0.0f,
                                                                      static_cast<float>(node.getBounds().w),
                                                                      static_cast<float>(node.getBounds().h)),
                                               nodeTransform);
    if (!bounds.contains(position)) {
        return {};
    }

    if (node.hasClipRect()) {
        const auto& clip = node.getClipRect();
        const auto sceneClip = sceneRectFromLocalRect(juce::Rectangle<float>(static_cast<float>(clip.x),
                                                                             static_cast<float>(clip.y),
                                                                             static_cast<float>(clip.w),
                                                                             static_cast<float>(clip.h)),
                                                      nodeTransform);
        if (!sceneClip.contains(position)) {
            return {};
        }
    }

    auto children = sortedChildren(node);
    for (auto it = children.rbegin(); it != children.rend(); ++it) {
        auto hit = hitTestRecursive(**it,
                                    position,
                                    nodeTransform,
                                    mode);
        if (hit.node != nullptr) {
            return hit;
        }
    }

    if (!nodeMatchesHitMode(node, mode)) {
        return {};
    }

    RuntimeNodeRenderer::HitTestResult result;
    result.node = &node;
    result.stableId = node.getStableId();
    result.sceneBounds = enclosingIntRect(bounds);
    result.scenePosition = position;
    return result;
}

} // namespace

std::shared_ptr<const RuntimeNodeRenderer::Snapshot> RuntimeNodeRenderer::makeSnapshot(const RuntimeNode* root) const {
    auto snapshot = std::make_shared<Snapshot>();
    if (root != nullptr) {
        snapshot->root = cloneTree(*root, snapshot->nodes);
    }
    return snapshot;
}

RuntimeNodeRenderer::PreviewTransform RuntimeNodeRenderer::buildPreviewTransform(const RuntimeNode& root,
                                                                                int width,
                                                                                int height,
                                                                                const RenderOptions& options) const {
    PreviewTransform transform;

    juce::Rectangle<float> sceneBounds;
    bool hasBounds = false;
    collectVisibleBounds(root, SceneTransform{}, sceneBounds, hasBounds);
    if (!hasBounds) {
        sceneBounds = sceneRectForNode(root, SceneTransform{});
    }

    transform.valid = true;
    transform.sceneBounds = enclosingIntRect(sceneBounds);

    if (!options.fitToView) {
        transform.scale = 1.0f;
        transform.offsetX = 0.0f;
        transform.offsetY = 0.0f;
        return transform;
    }

    const float leftPad = options.leftPad;
    const float rightPad = options.rightPad;
    const float topPad = options.topPad;
    const float bottomPad = options.bottomPad;
    const float availableW = std::max(1.0f, static_cast<float>(width) - leftPad - rightPad);
    const float availableH = std::max(1.0f, static_cast<float>(height) - topPad - bottomPad);
    const float sceneW = std::max(1.0f, static_cast<float>(sceneBounds.getWidth()));
    const float sceneH = std::max(1.0f, static_cast<float>(sceneBounds.getHeight()));
    const float scale = std::min(availableW / sceneW, availableH / sceneH);

    transform.scale = std::max(0.01f, scale);
    transform.offsetX = leftPad + (availableW - sceneW * transform.scale) * 0.5f
        - static_cast<float>(sceneBounds.getX()) * transform.scale;
    transform.offsetY = topPad + (availableH - sceneH * transform.scale) * 0.5f
        - static_cast<float>(sceneBounds.getY()) * transform.scale;
    return transform;
}

void RuntimeNodeRenderer::render(const RuntimeNode& root,
                                 ImDrawList* drawList,
                                 const PreviewTransform& transform,
                                 uint64_t selectedStableId,
                                 uint64_t hoveredStableId,
                                 const RenderOptions& options) const {
    if (drawList == nullptr || !transform.valid) {
        return;
    }

    renderNodeRecursive(root,
                        SceneTransform{},
                        drawList,
                        selectedStableId,
                        hoveredStableId,
                        transform,
                        options,
                        0);
}

RuntimeNodeRenderer::HitTestResult RuntimeNodeRenderer::hitTest(const Snapshot& snapshot,
                                                                juce::Point<float> position,
                                                                const PreviewTransform& transform,
                                                                HitTestMode mode) const {
    if (snapshot.root == nullptr || !transform.valid || transform.scale <= 0.0f) {
        return {};
    }

    const float sceneX = (position.x - transform.offsetX) / transform.scale;
    const float sceneY = (position.y - transform.offsetY) / transform.scale;
    return hitTestRecursive(*snapshot.root,
                            juce::Point<float>(sceneX, sceneY),
                            SceneTransform{},
                            mode);
}

RuntimeNode* RuntimeNodeRenderer::cloneTree(const RuntimeNode& root,
                                            std::vector<std::unique_ptr<RuntimeNode>>& ownedNodes) const {
    auto node = std::make_unique<RuntimeNode>(root.getNodeId());
    auto* out = node.get();
    ownedNodes.push_back(std::move(node));

    out->setStableIdForClone(root.getStableId());
    out->setNodeId(root.getNodeId());
    out->setWidgetType(root.getWidgetType());

    const auto& bounds = root.getBounds();
    out->setBounds(bounds.x, bounds.y, bounds.w, bounds.h);

    if (root.hasClipRect()) {
        const auto& clip = root.getClipRect();
        out->setClipRect(clip.x, clip.y, clip.w, clip.h);
    } else {
        out->clearClipRect();
    }

    out->setVisible(root.isVisible());
    out->setZOrder(root.getZOrder());
    out->setStyle(root.getStyle());
    out->setInputCapabilities(root.getInputCapabilities());

    const auto& transform = root.getTransform();
    if (!transform.isIdentity()) {
        out->setTransform(transform.scaleX, transform.scaleY, transform.translateX, transform.translateY);
    }

    out->setHovered(root.isHovered());
    out->setPressed(root.isPressed());
    out->setFocused(root.isFocused());

    if (root.hasDisplayList()) {
        out->setDisplayList(root.getDisplayList().clone());
    } else {
        out->clearDisplayList();
    }

    if (!root.getCustomSurfaceType().empty() || root.hasCustomRenderPayload()) {
        out->setCustomSurfaceType(root.getCustomSurfaceType());
        out->setCustomRenderPayload(root.getCustomRenderPayload().clone());
    } else {
        out->clearCustomRenderPayload();
    }

    for (auto* child : root.getChildren()) {
        if (child == nullptr) {
            continue;
        }
        if (auto* childClone = cloneTree(*child, ownedNodes)) {
            out->addChild(childClone);
        }
    }

    return out;
}

} // namespace manifold::ui::imgui

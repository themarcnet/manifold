#pragma once

#include "../../primitives/ui/RuntimeNode.h"

#include <juce_gui_basics/juce_gui_basics.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

struct ImDrawList;

namespace manifold::ui::imgui {

struct CompiledDrawCmd {
    enum class Type : uint8_t {
        FillRect,
        DrawRect,
        FillRoundedRect,
        DrawRoundedRect,
        DrawLine,
        DrawText,
        DrawImage,
        ClipRect,
        PopClipRect,
        Save,
        Restore,
        SetColor,
        SetFontSize
    };

    Type type = Type::FillRect;
    float x = 0.0f;
    float y = 0.0f;
    float w = 0.0f;
    float h = 0.0f;
    float radius = 0.0f;
    float thickness = 1.0f;
    uint32_t color = 0xffffffffu;
    bool hasColor = false;
    float fontSize = 13.0f;
    bool hasFontSize = false;
    float x1 = 0.0f;
    float y1 = 0.0f;
    float x2 = 0.0f;
    float y2 = 0.0f;
    std::string text;
    std::string align;
    std::string valign;
    uintptr_t textureId = 0;
    float u0 = 0.0f;
    float v0 = 0.0f;
    float u1 = 1.0f;
    float v1 = 1.0f;
};

struct CompiledDisplayList {
    std::vector<CompiledDrawCmd> commands;
};

class RuntimeNodeRenderer {
public:
    struct PreviewTransform {
        bool valid = false;
        float scale = 1.0f;
        float offsetX = 0.0f;
        float offsetY = 0.0f;
        juce::Rectangle<int> sceneBounds;
    };

    struct RenderOptions {
        float leftPad = 12.0f;
        float rightPad = 12.0f;
        float topPad = 84.0f;
        float bottomPad = 12.0f;
        bool fitToView = true;
        bool showFallbackBoxes = true;
        bool showNodeLabels = true;
        bool showSurfaceLabels = true;
        bool showHoveredOutline = true;
        bool showSelectedOutline = true;
    };

    struct Snapshot {
        RuntimeNode* root = nullptr;
        std::vector<std::unique_ptr<RuntimeNode>> nodes;
    };

    struct HitTestResult {
        const RuntimeNode* node = nullptr;
        uint64_t stableId = 0;
        juce::Rectangle<int> sceneBounds;
        juce::Point<float> scenePosition;
    };

    enum class HitTestMode {
        Pointer,
        Wheel,
        AnyVisible
    };

    std::shared_ptr<const Snapshot> makeSnapshot(const RuntimeNode* root) const;
    PreviewTransform buildPreviewTransform(const RuntimeNode& root,
                                           int width,
                                           int height,
                                           const RenderOptions& options) const;
    void render(const RuntimeNode& root,
                ImDrawList* drawList,
                const PreviewTransform& transform,
                uint64_t selectedStableId,
                uint64_t hoveredStableId,
                const RenderOptions& options) const;
    HitTestResult hitTest(const Snapshot& snapshot,
                          juce::Point<float> position,
                          const PreviewTransform& transform,
                          HitTestMode mode = HitTestMode::Pointer) const;

private:
    RuntimeNode* cloneTree(const RuntimeNode& root,
                           std::vector<std::unique_ptr<RuntimeNode>>& ownedNodes) const;
};

} // namespace manifold::ui::imgui

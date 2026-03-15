#pragma once

#include "imgui.h"

namespace manifold {
namespace ui {
namespace imgui {

struct ThemeTokens {
    ImVec4 panelBg { 0.06f, 0.09f, 0.13f, 0.98f };
    ImVec4 panelBgAlt { 0.08f, 0.10f, 0.14f, 1.00f };
    ImVec4 panelBorder { 0.20f, 0.26f, 0.34f, 1.00f };
    ImVec4 text { 0.90f, 0.93f, 0.97f, 1.00f };
    ImVec4 textMuted { 0.57f, 0.64f, 0.72f, 1.00f };
    ImVec4 accent { 0.22f, 0.52f, 0.86f, 1.00f };
    ImVec4 hoverBg { 0.11f, 0.17f, 0.25f, 1.00f };
    ImVec4 rowActiveBg { 0.14f, 0.22f, 0.32f, 1.00f };
    ImVec4 selectionBg { 0.16f, 0.33f, 0.55f, 0.95f };
    ImVec4 selectionText { 0.98f, 0.99f, 1.00f, 1.00f };
    ImVec4 buttonBg { 0.12f, 0.16f, 0.23f, 1.00f };
    ImVec4 buttonHoveredBg { 0.16f, 0.24f, 0.35f, 1.00f };
    ImVec4 buttonActiveBg { 0.20f, 0.31f, 0.46f, 1.00f };
    ImVec4 frameBg { 0.08f, 0.12f, 0.18f, 1.00f };
    ImVec4 frameHoveredBg { 0.11f, 0.17f, 0.25f, 1.00f };
    ImVec4 frameActiveBg { 0.14f, 0.21f, 0.32f, 1.00f };
    float windowPaddingX = 8.0f;
    float windowPaddingY = 8.0f;
    float rowPaddingX = 10.0f;
    float rowPaddingY = 5.0f;
    float rowHeight = 26.0f;
    float itemGap = 8.0f;
    float sectionPaddingY = 7.0f;
    float rowRounding = 6.0f;
    float frameRounding = 6.0f;
    float childRounding = 6.0f;
    float indentWidth = 12.0f;
};

const ThemeTokens& toolTheme();
ImU32 toU32(const ImVec4& color);
void applyToolTheme();
void beginFullWindow(const char* windowId, int width, int height);

} // namespace imgui
} // namespace ui
} // namespace manifold

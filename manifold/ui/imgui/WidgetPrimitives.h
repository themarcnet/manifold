#pragma once

#include "Theme.h"

namespace manifold {
namespace ui {
namespace imgui {

struct RowOptions {
    const char* label = "";
    const char* detail = nullptr;
    bool selected = false;
    bool muted = false;
    float indent = 0.0f;
};

void drawSectionHeader(const char* label);
bool beginPanel(const char* id, const ImVec2& size = ImVec2(0.0f, 0.0f), ImGuiWindowFlags flags = 0);
void endPanel();
void drawEmptyState(const char* title, const char* detail = nullptr);
void drawTextRow(const RowOptions& options);
bool drawSelectableRow(const RowOptions& options);

} // namespace imgui
} // namespace ui
} // namespace manifold

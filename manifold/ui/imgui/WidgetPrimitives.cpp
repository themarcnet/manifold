#include "WidgetPrimitives.h"

#include <algorithm>

namespace manifold {
namespace ui {
namespace imgui {
namespace {

float resolveRowHeight(const ThemeTokens& theme) {
    return std::max(theme.rowHeight, ImGui::GetTextLineHeight() + theme.rowPaddingY * 2.0f);
}

void drawRow(const RowOptions& options, bool hovered, bool active) {
    const auto& theme = toolTheme();
    auto* drawList = ImGui::GetWindowDrawList();
    const auto min = ImGui::GetItemRectMin();
    const auto max = ImGui::GetItemRectMax();
    const auto textLineHeight = ImGui::GetTextLineHeight();
    const auto rectHeight = max.y - min.y;

    ImU32 background = 0;
    if (options.selected) {
        background = toU32(theme.selectionBg);
    } else if (active) {
        background = toU32(theme.rowActiveBg);
    } else if (hovered) {
        background = toU32(theme.hoverBg);
    }

    if (background != 0) {
        drawList->AddRectFilled(min, max, background, theme.rowRounding);
    }

    drawList->AddLine(ImVec2(min.x, max.y - 1.0f), ImVec2(max.x, max.y - 1.0f), toU32(theme.panelBorder));

    float left = min.x + theme.rowPaddingX + options.indent;
    float right = max.x - theme.rowPaddingX;
    const float textY = min.y + (rectHeight - textLineHeight) * 0.5f;

    ImVec4 labelColor = options.selected ? theme.selectionText
                                         : (options.muted ? theme.textMuted : theme.text);
    ImVec4 detailColor = options.selected ? theme.selectionText : theme.textMuted;

    if (options.detail != nullptr && options.detail[0] != '\0') {
        const auto detailSize = ImGui::CalcTextSize(options.detail);
        const float detailX = std::max(left, right - detailSize.x);
        drawList->AddText(ImVec2(detailX, textY), toU32(detailColor), options.detail);
        right = detailX - theme.itemGap;
    }

    const float clipMaxX = std::max(left, right);
    drawList->PushClipRect(ImVec2(left, min.y), ImVec2(clipMaxX, max.y), true);
    drawList->AddText(ImVec2(left, textY), toU32(labelColor), options.label != nullptr ? options.label : "");
    drawList->PopClipRect();
}

void advanceRowCursor() {
    const auto& theme = toolTheme();
    const auto height = resolveRowHeight(theme);
    const auto width = std::max(1.0f, ImGui::GetContentRegionAvail().x);
    ImGui::Dummy(ImVec2(width, height));
}

} // namespace

void drawSectionHeader(const char* label) {
    const auto& theme = toolTheme();
    const auto width = std::max(1.0f, ImGui::GetContentRegionAvail().x);
    const auto pos = ImGui::GetCursorScreenPos();
    const auto textLineHeight = ImGui::GetTextLineHeight();
    const auto height = textLineHeight + theme.sectionPaddingY * 2.0f;

    ImGui::Dummy(ImVec2(width, height));

    auto* drawList = ImGui::GetWindowDrawList();
    const float textX = pos.x + theme.rowPaddingX;
    const float textY = pos.y + theme.sectionPaddingY;
    const auto labelSize = ImGui::CalcTextSize(label != nullptr ? label : "");
    const float lineY = pos.y + height - 1.0f;
    const float lineStart = std::min(pos.x + width - theme.rowPaddingX,
                                     textX + labelSize.x + theme.itemGap);

    drawList->AddText(ImVec2(textX, textY), toU32(theme.textMuted), label != nullptr ? label : "");
    if (lineStart < pos.x + width - theme.rowPaddingX) {
        drawList->AddLine(ImVec2(lineStart, lineY),
                          ImVec2(pos.x + width - theme.rowPaddingX, lineY),
                          toU32(theme.panelBorder));
    }
}

bool beginPanel(const char* id, const ImVec2& size, ImGuiWindowFlags flags) {
    return ImGui::BeginChild(id, size, true, flags);
}

void endPanel() {
    ImGui::EndChild();
}

void drawEmptyState(const char* title, const char* detail) {
    drawSectionHeader(title != nullptr ? title : "Empty");
    if (detail == nullptr || detail[0] == '\0') {
        return;
    }

    advanceRowCursor();
    drawRow(RowOptions { detail, nullptr, false, true, 0.0f }, false, false);
}

void drawTextRow(const RowOptions& options) {
    advanceRowCursor();
    drawRow(options, false, false);
}

bool drawSelectableRow(const RowOptions& options) {
    const auto& theme = toolTheme();
    const auto height = resolveRowHeight(theme);
    const auto width = std::max(1.0f, ImGui::GetContentRegionAvail().x);

    const bool pressed = ImGui::InvisibleButton("##row", ImVec2(width, height));
    drawRow(options, ImGui::IsItemHovered(), ImGui::IsItemActive());
    return pressed;
}

} // namespace imgui
} // namespace ui
} // namespace manifold

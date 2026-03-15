#include "Theme.h"

namespace manifold {
namespace ui {
namespace imgui {

const ThemeTokens& toolTheme() {
    static const ThemeTokens theme;
    return theme;
}

ImU32 toU32(const ImVec4& color) {
    return ImGui::ColorConvertFloat4ToU32(color);
}

void applyToolTheme() {
    const auto& theme = toolTheme();

    ImGui::StyleColorsDark();
    auto& style = ImGui::GetStyle();
    style.WindowRounding = 0.0f;
    style.ChildRounding = theme.childRounding;
    style.FrameRounding = theme.frameRounding;
    style.PopupRounding = theme.frameRounding;
    style.GrabRounding = theme.frameRounding;
    style.TabRounding = theme.frameRounding;
    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;
    style.WindowPadding = ImVec2(theme.windowPaddingX, theme.windowPaddingY);
    style.FramePadding = ImVec2(theme.rowPaddingX - 2.0f, theme.rowPaddingY);
    style.ItemSpacing = ImVec2(theme.itemGap, 6.0f);
    style.ItemInnerSpacing = ImVec2(6.0f, 4.0f);
    style.CellPadding = ImVec2(8.0f, 4.0f);
    style.IndentSpacing = theme.indentWidth;
    style.ScrollbarSize = 12.0f;

    style.Colors[ImGuiCol_WindowBg] = theme.panelBg;
    style.Colors[ImGuiCol_ChildBg] = theme.panelBgAlt;
    style.Colors[ImGuiCol_Border] = theme.panelBorder;
    style.Colors[ImGuiCol_Separator] = theme.panelBorder;
    style.Colors[ImGuiCol_SeparatorHovered] = theme.accent;
    style.Colors[ImGuiCol_SeparatorActive] = theme.accent;
    style.Colors[ImGuiCol_Text] = theme.text;
    style.Colors[ImGuiCol_TextDisabled] = theme.textMuted;
    style.Colors[ImGuiCol_Header] = theme.selectionBg;
    style.Colors[ImGuiCol_HeaderHovered] = theme.accent;
    style.Colors[ImGuiCol_HeaderActive] = theme.accent;
    style.Colors[ImGuiCol_Button] = theme.buttonBg;
    style.Colors[ImGuiCol_ButtonHovered] = theme.buttonHoveredBg;
    style.Colors[ImGuiCol_ButtonActive] = theme.buttonActiveBg;
    style.Colors[ImGuiCol_FrameBg] = theme.frameBg;
    style.Colors[ImGuiCol_FrameBgHovered] = theme.frameHoveredBg;
    style.Colors[ImGuiCol_FrameBgActive] = theme.frameActiveBg;
    style.Colors[ImGuiCol_TitleBg] = theme.panelBg;
    style.Colors[ImGuiCol_TitleBgActive] = theme.panelBg;
    style.Colors[ImGuiCol_ScrollbarBg] = theme.panelBgAlt;
    style.Colors[ImGuiCol_ScrollbarGrab] = theme.hoverBg;
    style.Colors[ImGuiCol_ScrollbarGrabHovered] = theme.rowActiveBg;
    style.Colors[ImGuiCol_ScrollbarGrabActive] = theme.accent;
    style.Colors[ImGuiCol_CheckMark] = theme.selectionText;
    style.Colors[ImGuiCol_SliderGrab] = theme.accent;
    style.Colors[ImGuiCol_SliderGrabActive] = theme.selectionText;
    style.Colors[ImGuiCol_ResizeGrip] = theme.hoverBg;
    style.Colors[ImGuiCol_ResizeGripHovered] = theme.accent;
    style.Colors[ImGuiCol_ResizeGripActive] = theme.selectionText;
    style.Colors[ImGuiCol_Tab] = theme.buttonBg;
    style.Colors[ImGuiCol_TabHovered] = theme.buttonHoveredBg;
    style.Colors[ImGuiCol_TabActive] = theme.buttonActiveBg;
    style.Colors[ImGuiCol_NavHighlight] = theme.accent;
}

void beginFullWindow(const char* windowId, int width, int height) {
    ImGui::SetNextWindowPos(ImVec2(0.0f, 0.0f), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(static_cast<float>(width), static_cast<float>(height)), ImGuiCond_Always);

    constexpr ImGuiWindowFlags windowFlags = ImGuiWindowFlags_NoDecoration
                                           | ImGuiWindowFlags_NoMove
                                           | ImGuiWindowFlags_NoResize
                                           | ImGuiWindowFlags_NoSavedSettings
                                           | ImGuiWindowFlags_NoBringToFrontOnFocus;

    ImGui::Begin(windowId, nullptr, windowFlags);
}

} // namespace imgui
} // namespace ui
} // namespace manifold

#pragma once

#include "ImGuiInspectorHost.h"

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace manifold {
namespace ui {
namespace imgui {

struct PropertyEditorCallbacks {
    std::function<void(double)> onApplyNumber;
    std::function<void(bool)> onApplyBool;
    std::function<void(const std::string&)> onApplyText;
    std::function<void(std::uint32_t)> onApplyColor;
    std::function<void(int)> onApplyEnumIndex;
};

struct ScriptInspectorCallbacks {
    std::function<void()> onRunPreview;
    std::function<void()> onStopPreview;
    std::function<void(bool collapsed)> onSetEditorCollapsed;
    std::function<void(bool collapsed)> onSetGraphCollapsed;
    std::function<void(int panX, int panY)> onSetGraphPan;
    std::function<void(const ImGuiInspectorHost::RuntimeParam&, double)> onApplyRuntimeParam;
};

void drawPropertyEditor(const ImGuiInspectorHost::ActiveProperty& activeProperty,
                        const std::string& textBuffer,
                        const PropertyEditorCallbacks& callbacks);

void drawInspectorRowsPanel(const std::vector<ImGuiInspectorHost::InspectorRow>& rows,
                            const std::function<void(int rowIndex)>& onSelectRow);

void drawScriptInspectorInfo(const ImGuiInspectorHost::ScriptInspectorData& scriptData);
void drawScriptInspectorDspControls(const ImGuiInspectorHost::ScriptInspectorData& scriptData,
                                    const ScriptInspectorCallbacks& callbacks);
void drawDspGraphPanel(const ImGuiInspectorHost::ScriptInspectorData& scriptData,
                       const ScriptInspectorCallbacks& callbacks);

} // namespace imgui
} // namespace ui
} // namespace manifold

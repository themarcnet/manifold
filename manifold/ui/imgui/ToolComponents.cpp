#include "ToolComponents.h"

#include "Theme.h"
#include "WidgetPrimitives.h"
#include "imgui.h"
#include "misc/cpp/imgui_stdlib.h"

#include <algorithm>
#include <cmath>

namespace manifold {
namespace ui {
namespace imgui {
namespace {

ImVec4 argbToImVec4(std::uint32_t argb) {
    const float a = static_cast<float>((argb >> 24) & 0xffu) / 255.0f;
    const float r = static_cast<float>((argb >> 16) & 0xffu) / 255.0f;
    const float g = static_cast<float>((argb >> 8) & 0xffu) / 255.0f;
    const float b = static_cast<float>(argb & 0xffu) / 255.0f;
    return ImVec4(r, g, b, a);
}

std::uint32_t imVec4ToArgb(const ImVec4& rgba) {
    const auto clampByte = [](float v) {
        return static_cast<std::uint32_t>(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f);
    };
    const std::uint32_t r = clampByte(rgba.x);
    const std::uint32_t g = clampByte(rgba.y);
    const std::uint32_t b = clampByte(rgba.z);
    const std::uint32_t a = clampByte(rgba.w);
    return (a << 24) | (r << 16) | (g << 8) | b;
}

double resolveRuntimeStep(const ImGuiInspectorHost::RuntimeParam& param) {
    if (param.stepValue > 0.0) {
        return param.stepValue;
    }

    if (param.hasMin && param.hasMax) {
        const auto span = std::abs(param.maxValue - param.minValue);
        if (span <= 2.0) {
            return 0.01;
        }
        if (span <= 20.0) {
            return 0.1;
        }
        return std::max(0.01, span / 100.0);
    }

    return std::max(0.01, std::abs(param.value) * 0.05);
}

juce::Rectangle<int> toLocalRect(const ImVec2& min, const ImVec2& size) {
    return {
        juce::roundToInt(min.x),
        juce::roundToInt(min.y),
        std::max(1, juce::roundToInt(size.x)),
        std::max(1, juce::roundToInt(size.y)),
    };
}

void drawInfoRow(const char* label, const std::string& value) {
    ImGui::TableNextRow();
    ImGui::TableSetColumnIndex(0);
    ImGui::TextDisabled("%s", label);
    ImGui::TableSetColumnIndex(1);
    ImGui::TextWrapped("%s", value.c_str());
}

} // namespace

void drawPropertyEditor(const ImGuiInspectorHost::ActiveProperty& activeProperty,
                        const std::string& textBuffer,
                        const PropertyEditorCallbacks& callbacks) {
    if (!activeProperty.valid) {
        ImGui::TextDisabled("Select a property to edit.");
        return;
    }

    if (activeProperty.mixed) {
        ImGui::TextDisabled("Mixed values");
    }
    ImGui::TextUnformatted(activeProperty.key.c_str());

    if (activeProperty.editorType == "number") {
        double value = activeProperty.numberValue;
        const char* format = (activeProperty.displayValue.find('.') != std::string::npos) ? "%.3f" : "%.0f";
        if (ImGui::InputDouble("##number", &value,
                               activeProperty.stepValue > 0.0 ? activeProperty.stepValue : 1.0,
                               0.0, format)) {
            if (activeProperty.hasMin) value = std::max(value, activeProperty.minValue);
            if (activeProperty.hasMax) value = std::min(value, activeProperty.maxValue);
            if (callbacks.onApplyNumber) {
                callbacks.onApplyNumber(value);
            }
        }
        return;
    }

    if (activeProperty.editorType == "bool") {
        bool value = activeProperty.boolValue;
        if (ImGui::Checkbox("##bool", &value) && callbacks.onApplyBool) {
            callbacks.onApplyBool(value);
        }
        return;
    }

    if (activeProperty.editorType == "text") {
        std::string localText = textBuffer;
        if (ImGui::InputText("##text", &localText) && callbacks.onApplyText) {
            callbacks.onApplyText(localText);
        }
        return;
    }

    if (activeProperty.editorType == "enum") {
        if (!activeProperty.enumLabels.empty()) {
            int selectedIndex = std::clamp(activeProperty.enumSelectedIndex - 1, 0,
                                           static_cast<int>(activeProperty.enumLabels.size()) - 1);
            const char* comboLabel = activeProperty.enumLabels[static_cast<std::size_t>(selectedIndex)].c_str();
            if (ImGui::BeginCombo("##enum", comboLabel)) {
                for (int i = 0; i < static_cast<int>(activeProperty.enumLabels.size()); ++i) {
                    const bool selected = (i == selectedIndex);
                    if (ImGui::Selectable(activeProperty.enumLabels[static_cast<std::size_t>(i)].c_str(), selected)
                        && callbacks.onApplyEnumIndex) {
                        callbacks.onApplyEnumIndex(i + 1);
                    }
                    if (selected) {
                        ImGui::SetItemDefaultFocus();
                    }
                }
                ImGui::EndCombo();
            }
        }
        return;
    }

    if (activeProperty.editorType == "color") {
        ImVec4 rgba = argbToImVec4(activeProperty.colorValue);
        if (ImGui::ColorEdit4("##color", &rgba.x, ImGuiColorEditFlags_NoInputs) && callbacks.onApplyColor) {
            callbacks.onApplyColor(imVec4ToArgb(rgba));
        }
        ImGui::SameLine();
        ImGui::TextDisabled("%s", activeProperty.displayValue.c_str());
        return;
    }

    ImGui::TextDisabled("No editor for this property.");
}

void drawInspectorRowsPanel(const std::vector<ImGuiInspectorHost::InspectorRow>& rows,
                            const std::function<void(int rowIndex)>& onSelectRow) {
    const float rowsHeight = std::max(120.0f, ImGui::GetContentRegionAvail().y);
    if (!beginPanel("##InspectorRows", ImVec2(0.0f, rowsHeight))) {
        return;
    }

    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0.0f, 0.0f));
    for (std::size_t rowIdx = 0; rowIdx < rows.size(); ++rowIdx) {
        const auto& row = rows[rowIdx];
        ImGui::PushID(static_cast<int>(rowIdx));
        if (row.section) {
            drawSectionHeader(row.key.c_str());
        } else if (row.interactive) {
            if (drawSelectableRow({ row.key.c_str(),
                                    row.value.empty() ? nullptr : row.value.c_str(),
                                    row.selected,
                                    false,
                                    0.0f })
                && row.rowIndex > 0 && onSelectRow) {
                onSelectRow(row.rowIndex);
            }
        } else {
            drawTextRow({ row.key.c_str(),
                          row.value.empty() ? nullptr : row.value.c_str(),
                          false,
                          true,
                          0.0f });
        }
        ImGui::PopID();
    }
    ImGui::PopStyleVar();
    endPanel();
}

void drawScriptInspectorInfo(const ImGuiInspectorHost::ScriptInspectorData& scriptData) {
    if (ImGui::BeginTable("##ScriptInspectorInfo", 2,
                          ImGuiTableFlags_BordersInnerV | ImGuiTableFlags_SizingStretchProp,
                          ImVec2(0.0f, 0.0f))) {
        ImGui::TableSetupColumn("Label", ImGuiTableColumnFlags_WidthFixed, 74.0f);
        ImGui::TableSetupColumn("Value", ImGuiTableColumnFlags_WidthStretch);
        drawInfoRow("Script", scriptData.name);
        drawInfoRow("Kind", scriptData.kind);
        if (!scriptData.ownership.empty()) {
            drawInfoRow("Ownership", scriptData.ownership);
            if (scriptData.hasStructuredStatus) {
                drawInfoRow("Dirty", scriptData.structuredDirty ? std::string{"yes"} : std::string{"no"});
            }
            if (!scriptData.projectLastError.empty()) {
                drawInfoRow("Last Error", scriptData.projectLastError);
            }
        }
        drawInfoRow("Path", scriptData.path);
        if (scriptData.kind == "dsp") {
            int activeRuntimeCount = 0;
            for (const auto& runtimeParam : scriptData.runtimeParams) {
                if (runtimeParam.active) {
                    ++activeRuntimeCount;
                }
            }
            drawInfoRow("Declared", std::to_string(scriptData.declaredParams.size()));
            drawInfoRow("Runtime", std::to_string(activeRuntimeCount) + "/" + std::to_string(scriptData.runtimeParams.size()) + " active");
            drawInfoRow("Graph", std::to_string(scriptData.graphNodes.size()) + " nodes / " + std::to_string(scriptData.graphEdges.size()) + " edges");
        }
        ImGui::EndTable();
    }
}

void drawScriptInspectorDspControls(const ImGuiInspectorHost::ScriptInspectorData& scriptData,
                                    const ScriptInspectorCallbacks& callbacks) {
    if (scriptData.kind != "dsp") {
        return;
    }

    const float buttonWidth = (ImGui::GetContentRegionAvail().x - 8.0f) * 0.5f;
    if (ImGui::Button("Run in Preview Slot", ImVec2(buttonWidth, 0.0f)) && callbacks.onRunPreview) {
        callbacks.onRunPreview();
    }
    ImGui::SameLine();
    if (ImGui::Button("Stop Preview Slot", ImVec2(buttonWidth, 0.0f)) && callbacks.onStopPreview) {
        callbacks.onStopPreview();
    }

    if (!scriptData.runtimeStatus.empty()) {
        ImGui::TextColored(ImVec4(0.49f, 0.83f, 0.99f, 1.0f), "%s", scriptData.runtimeStatus.c_str());
    }

    drawSectionHeader("Declared Params");
    if (scriptData.declaredParams.empty()) {
        ImGui::TextDisabled("No ctx.params.register(...) found.");
    } else {
        const float declaredHeight = std::min(140.0f,
            std::max(58.0f, 26.0f + static_cast<float>(scriptData.declaredParams.size()) * 18.0f));
        if (beginPanel("##DeclaredParams", ImVec2(0.0f, declaredHeight))) {
            ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0.0f, 0.0f));
            ImGuiListClipper clipper;
            clipper.Begin(static_cast<int>(scriptData.declaredParams.size()));
            while (clipper.Step()) {
                for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; ++i) {
                    const auto& param = scriptData.declaredParams[static_cast<std::size_t>(i)];
                    ImGui::PushID(i);
                    drawTextRow({ param.path.c_str(),
                                  param.defaultValue.empty() ? nullptr : param.defaultValue.c_str(),
                                  false,
                                  true,
                                  0.0f });
                    ImGui::PopID();
                }
            }
            ImGui::PopStyleVar();
            endPanel();
        }
    }

    drawSectionHeader("Runtime Params");
    if (scriptData.runtimeParams.empty()) {
        ImGui::TextDisabled("No runtime params. Run the script first.");
        return;
    }

    const float runtimeHeight = std::min(220.0f,
        std::max(84.0f, 28.0f + static_cast<float>(scriptData.runtimeParams.size()) * 28.0f));
    if (!beginPanel("##RuntimeParams", ImVec2(0.0f, runtimeHeight))) {
        return;
    }

    ImGui::TextDisabled("Buttons nudge. Drag the control to update the live runtime param.");
    ImGui::Separator();
    ImGuiListClipper clipper;
    clipper.Begin(static_cast<int>(scriptData.runtimeParams.size()));
    while (clipper.Step()) {
        for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; ++i) {
            const auto& param = scriptData.runtimeParams[static_cast<std::size_t>(i)];
            const auto step = resolveRuntimeStep(param);
            double value = param.value;
            ImGui::PushID(i);
            ImGui::BeginDisabled(!param.active || param.endpointPath.empty());
            ImGui::TextDisabled("%s", param.path.c_str());
            if (!param.active) {
                ImGui::SameLine();
                ImGui::TextDisabled("inactive");
            }
            if (ImGui::Button("-", ImVec2(20.0f, 0.0f)) && callbacks.onApplyRuntimeParam) {
                double nextValue = value - step;
                if (param.hasMin) nextValue = std::max(nextValue, param.minValue);
                if (param.hasMax) nextValue = std::min(nextValue, param.maxValue);
                callbacks.onApplyRuntimeParam(param, nextValue);
            }
            ImGui::SameLine();
            ImGui::SetNextItemWidth(std::max(72.0f, ImGui::GetContentRegionAvail().x - 88.0f));
            bool changed = false;
            if (param.hasMin && param.hasMax) {
                double sliderMin = param.minValue;
                double sliderMax = param.maxValue;
                changed = ImGui::SliderScalar("##runtimeValue", ImGuiDataType_Double,
                                              &value, &sliderMin, &sliderMax,
                                              "%.4f");
            } else {
                changed = ImGui::DragScalar("##runtimeValue", ImGuiDataType_Double,
                                            &value, static_cast<float>(step), nullptr, nullptr,
                                            "%.4f");
            }
            if (changed && callbacks.onApplyRuntimeParam) {
                if (param.hasMin) value = std::max(value, param.minValue);
                if (param.hasMax) value = std::min(value, param.maxValue);
                callbacks.onApplyRuntimeParam(param, value);
            }
            ImGui::SameLine();
            if (ImGui::Button("+", ImVec2(20.0f, 0.0f)) && callbacks.onApplyRuntimeParam) {
                double nextValue = value + step;
                if (param.hasMin) nextValue = std::max(nextValue, param.minValue);
                if (param.hasMax) nextValue = std::min(nextValue, param.maxValue);
                callbacks.onApplyRuntimeParam(param, nextValue);
            }
            ImGui::SameLine();
            ImGui::TextDisabled("%s", param.displayValue.c_str());
            ImGui::EndDisabled();
            ImGui::Spacing();
            ImGui::PopID();
        }
    }
    endPanel();
}

void drawDspGraphPanel(const ImGuiInspectorHost::ScriptInspectorData& scriptData,
                       const ScriptInspectorCallbacks& callbacks) {
    if (scriptData.kind != "dsp") {
        return;
    }

    ImGui::SetNextItemOpen(!scriptData.graphCollapsed, ImGuiCond_Always);
    const bool graphOpen = ImGui::CollapsingHeader("DSP Graph", ImGuiTreeNodeFlags_DefaultOpen);
    if (graphOpen != !scriptData.graphCollapsed && callbacks.onSetGraphCollapsed) {
        callbacks.onSetGraphCollapsed(!graphOpen);
    }
    if (!graphOpen) {
        return;
    }

    const auto& theme = toolTheme();
    const float graphHeight = std::max(120.0f, ImGui::GetContentRegionAvail().y - 4.0f);
    ImGui::BeginChild("##DspGraph", ImVec2(0.0f, graphHeight), true,
                      ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    const ImVec2 canvasSize = ImGui::GetContentRegionAvail();
    ImGui::InvisibleButton("##graphCanvas", canvasSize,
                           ImGuiButtonFlags_MouseButtonLeft | ImGuiButtonFlags_MouseButtonRight);
    const ImVec2 canvasMin = ImGui::GetItemRectMin();
    const ImVec2 canvasMax = ImGui::GetItemRectMax();
    auto* drawList = ImGui::GetWindowDrawList();
    drawList->AddRectFilled(canvasMin, canvasMax, IM_COL32(11, 18, 32, 255), theme.childRounding);
    drawList->AddRect(canvasMin, canvasMax, toU32(theme.panelBorder), theme.childRounding);
    drawList->PushClipRect(canvasMin, canvasMax, true);

    if (ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
        const auto delta = ImGui::GetIO().MouseDelta;
        if ((std::abs(delta.x) > 0.001f || std::abs(delta.y) > 0.001f) && callbacks.onSetGraphPan) {
            callbacks.onSetGraphPan(scriptData.graphPanX + juce::roundToInt(delta.x),
                                    scriptData.graphPanY + juce::roundToInt(delta.y));
        }
    }

    drawList->AddText(ImVec2(canvasMin.x + 8.0f, canvasMin.y + 6.0f),
                      toU32(theme.textMuted), "Drag to pan");

    if (scriptData.graphNodes.empty()) {
        drawList->AddText(ImVec2(canvasMin.x + 8.0f, canvasMin.y + 28.0f),
                          toU32(theme.textMuted), "No graph parsed");
    } else {
        const int cols = std::max(1, static_cast<int>(std::ceil(std::sqrt(static_cast<double>(scriptData.graphNodes.size())))));
        const float cellW = 110.0f;
        const float cellH = 48.0f;
        const float nodeW = 96.0f;
        const float nodeH = 24.0f;
        const float originX = canvasMin.x + 12.0f + static_cast<float>(scriptData.graphPanX);
        const float originY = canvasMin.y + 24.0f + static_cast<float>(scriptData.graphPanY);
        std::vector<ImVec2> centers(scriptData.graphNodes.size());
        std::vector<ImVec2> corners(scriptData.graphNodes.size());

        for (std::size_t i = 0; i < scriptData.graphNodes.size(); ++i) {
            const int col = static_cast<int>(i) % cols;
            const int row = static_cast<int>(i) / cols;
            const float x = originX + static_cast<float>(col) * cellW;
            const float y = originY + static_cast<float>(row) * cellH;
            corners[i] = ImVec2(x, y);
            centers[i] = ImVec2(x + nodeW * 0.5f, y + nodeH * 0.5f);
        }

        for (const auto& edge : scriptData.graphEdges) {
            if (edge.fromIndex < 1 || edge.toIndex < 1) {
                continue;
            }
            const auto fromIndex = static_cast<std::size_t>(edge.fromIndex - 1);
            const auto toIndex = static_cast<std::size_t>(edge.toIndex - 1);
            if (fromIndex >= centers.size() || toIndex >= centers.size()) {
                continue;
            }
            drawList->AddLine(centers[fromIndex], centers[toIndex], toU32(theme.panelBorder), 1.0f);
        }

        for (std::size_t i = 0; i < scriptData.graphNodes.size(); ++i) {
            const auto& node = scriptData.graphNodes[i];
            const auto& corner = corners[i];
            const ImVec2 nodeMax(corner.x + nodeW, corner.y + nodeH);
            drawList->AddRectFilled(corner, nodeMax, toU32(theme.buttonBg), theme.frameRounding);
            drawList->AddRect(corner, nodeMax, toU32(theme.accent), theme.frameRounding);
            const auto label = node.var + ":" + node.prim;
            drawList->AddText(ImVec2(corner.x + 4.0f, corner.y + 5.0f), toU32(theme.text), label.c_str());
        }
    }

    drawList->PopClipRect();
    ImGui::EndChild();
}

} // namespace imgui
} // namespace ui
} // namespace manifold

#include "BehaviorCoreEditor.h"
#include "BehaviorCoreProcessor.h"
#include "../primitives/core/Settings.h"
#include "../primitives/scripting/bindings/LuaRuntimeNodeBindings.h"
#include "../primitives/ui/Canvas.h"

#include <sol/sol.hpp>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#if defined(__GLIBC__)
#include <malloc.h>
#endif

namespace {
using PerfClock = std::chrono::steady_clock;

struct HostLayoutTraceState {
    bool initialised = false;
    bool visible = false;
    juce::Rectangle<int> bounds;
};

struct HostConfig {
    bool visible = false;
    juce::Rectangle<int> bounds;
    juce::File file;
    std::string text;
    int64_t syncToken = 0;
    bool readOnly = false;
};

struct ScriptListHostConfig {
    bool visible = false;
    juce::Rectangle<int> bounds;
    std::vector<ImGuiScriptListHost::ScriptRow> rows;
};

struct HierarchyHostConfig {
    bool visible = false;
    juce::Rectangle<int> bounds;
    std::vector<ImGuiHierarchyHost::TreeRow> rows;
};

struct InspectorHostConfig {
    bool visible = false;
    bool scriptMode = false;
    juce::Rectangle<int> bounds;
    ImGuiInspectorHost::BoundsInfo selectionBounds;
    std::vector<ImGuiInspectorHost::InspectorRow> rows;
    ImGuiInspectorHost::ActiveProperty activeProperty;
    ImGuiInspectorHost::ScriptInspectorData scriptData;
};

struct PerfOverlayHostConfig {
    bool visible = false;
    juce::Rectangle<int> bounds;
    ImGuiPerfOverlayHost::Snapshot snapshot;
};


[[maybe_unused]] double perfElapsedMs(PerfClock::time_point start) {
    return std::chrono::duration<double, std::milli>(PerfClock::now() - start).count();
}

void logEditorPerf(const char* label, PerfClock::time_point start, const char* extra = nullptr) {
    juce::ignoreUnused(label, start, extra);
}

struct ProcessMemorySnapshot {
    int64_t pssBytes = 0;
    int64_t privateDirtyBytes = 0;
};

struct GlibcAllocatorSnapshot {
    int64_t heapUsedBytes = 0;
    int64_t arenaBytes = 0;
    int64_t mmapBytes = 0;
    int64_t freeHeldBytes = 0;
    int64_t releasableBytes = 0;
    int64_t arenaCount = 0;
};

ProcessMemorySnapshot readProcessMemorySnapshot() {
    ProcessMemorySnapshot snapshot;
    std::ifstream smaps("/proc/self/smaps_rollup");
    std::string line;
    while (std::getline(smaps, line)) {
        if (line.rfind("Pss:", 0) == 0) {
            std::istringstream iss(line);
            std::string label, unit;
            int64_t kb = 0;
            iss >> label >> kb >> unit;
            snapshot.pssBytes = kb * 1024;
        } else if (line.rfind("Private_Dirty:", 0) == 0) {
            std::istringstream iss(line);
            std::string label, unit;
            int64_t kb = 0;
            iss >> label >> kb >> unit;
            snapshot.privateDirtyBytes = kb * 1024;
        }
    }
    return snapshot;
}

GlibcAllocatorSnapshot readGlibcAllocatorSnapshot() {
    GlibcAllocatorSnapshot snapshot;
#if defined(__GLIBC__)
    struct mallinfo2 mi;
    memset(&mi, 0, sizeof(mi));
    mi = mallinfo2();
    
    snapshot.heapUsedBytes = static_cast<int64_t>(mi.uordblks);
    snapshot.arenaBytes = static_cast<int64_t>(mi.arena);
    // hblkhd is unreliable in glibc 2.43 (returns garbage or GPU memory values)
    // Skipping mmap metric - it conflates CPU and GPU memory
    snapshot.mmapBytes = 0;
    snapshot.freeHeldBytes = static_cast<int64_t>(mi.fordblks);
    snapshot.releasableBytes = static_cast<int64_t>(mi.keepcost);
    snapshot.arenaCount = static_cast<int64_t>(mi.ordblks);
#endif
    return snapshot;
}

int64_t estimateScriptListRowsBytes(const std::vector<ImGuiScriptListHost::ScriptRow>& rows) {
    int64_t total = static_cast<int64_t>(rows.capacity()) * static_cast<int64_t>(sizeof(ImGuiScriptListHost::ScriptRow));
    for (const auto& row : rows) {
        total += static_cast<int64_t>(row.kind.capacity() + row.ownership.capacity() + row.name.capacity() + row.label.capacity() + row.path.capacity());
    }
    return total;
}

int64_t estimateHierarchyRowsBytes(const std::vector<ImGuiHierarchyHost::TreeRow>& rows) {
    int64_t total = static_cast<int64_t>(rows.capacity()) * static_cast<int64_t>(sizeof(ImGuiHierarchyHost::TreeRow));
    for (const auto& row : rows) {
        total += static_cast<int64_t>(row.type.capacity() + row.name.capacity() + row.path.capacity());
    }
    return total;
}

int64_t estimateInspectorRowsBytes(const std::vector<ImGuiInspectorHost::InspectorRow>& rows,
                                   const ImGuiInspectorHost::ActiveProperty& activeProperty) {
    int64_t total = static_cast<int64_t>(rows.capacity()) * static_cast<int64_t>(sizeof(ImGuiInspectorHost::InspectorRow));
    for (const auto& row : rows) {
        total += static_cast<int64_t>(row.key.capacity() + row.value.capacity());
    }
    total += static_cast<int64_t>(activeProperty.key.capacity() + activeProperty.path.capacity() + activeProperty.editorType.capacity()
                                + activeProperty.displayValue.capacity() + activeProperty.textValue.capacity());
    total += static_cast<int64_t>(activeProperty.enumLabels.capacity()) * static_cast<int64_t>(sizeof(std::string));
    for (const auto& label : activeProperty.enumLabels) {
        total += static_cast<int64_t>(label.capacity());
    }
    return total;
}

int64_t estimateScriptInspectorBytes(const ImGuiInspectorHost::ScriptInspectorData& data) {
    int64_t total = sizeof(ImGuiInspectorHost::ScriptInspectorData);
    total += static_cast<int64_t>(data.name.capacity() + data.kind.capacity() + data.ownership.capacity() + data.path.capacity() +
                                  data.text.capacity() + data.runtimeStatus.capacity() + data.projectLastError.capacity());
    total += static_cast<int64_t>(data.declaredParams.capacity()) * static_cast<int64_t>(sizeof(ImGuiInspectorHost::DeclaredParam));
    for (const auto& p : data.declaredParams) {
        total += static_cast<int64_t>(p.path.capacity() + p.defaultValue.capacity());
    }
    total += static_cast<int64_t>(data.runtimeParams.capacity()) * static_cast<int64_t>(sizeof(ImGuiInspectorHost::RuntimeParam));
    for (const auto& p : data.runtimeParams) {
        total += static_cast<int64_t>(p.endpointPath.capacity() + p.path.capacity() + p.displayValue.capacity());
    }
    total += static_cast<int64_t>(data.graphNodes.capacity()) * static_cast<int64_t>(sizeof(ImGuiInspectorHost::GraphNode));
    for (const auto& n : data.graphNodes) {
        total += static_cast<int64_t>(n.var.capacity() + n.prim.capacity());
    }
    total += static_cast<int64_t>(data.graphEdges.capacity()) * static_cast<int64_t>(sizeof(ImGuiInspectorHost::GraphEdge));
    return total;
}

void logEditorHostLayout(const char* name, HostLayoutTraceState& state, bool visible,
                         const juce::Rectangle<int>& bounds) {
    juce::ignoreUnused(name, visible, bounds);
    state.initialised = true;
    state.visible = visible;
    state.bounds = bounds;
}

void readSurfaceDescriptor(sol::object surfacesObj, const char* surfaceId,
                           bool& visibleOut, juce::Rectangle<int>& boundsOut,
                           std::string* titleOut = nullptr) {
    visibleOut = false;
    boundsOut = juce::Rectangle<int>();
    if (titleOut != nullptr) {
        titleOut->clear();
    }
    if (!surfacesObj.valid() || !surfacesObj.is<sol::table>()) {
        return;
    }
    sol::table surfaces = surfacesObj.as<sol::table>();
    sol::object surfaceObj = surfaces[surfaceId];
    if (!surfaceObj.valid() || !surfaceObj.is<sol::table>()) {
        return;
    }
    sol::table surface = surfaceObj.as<sol::table>();
    visibleOut = surface["visible"].get_or(false);
    if (titleOut != nullptr) {
        *titleOut = surface["title"].get_or(std::string{});
    }
    sol::object boundsObj = surface["bounds"];
    if (!boundsObj.valid() || !boundsObj.is<sol::table>()) {
        return;
    }
    sol::table bounds = boundsObj.as<sol::table>();
    boundsOut = juce::Rectangle<int>(
        bounds["x"].get_or(0),
        bounds["y"].get_or(0),
        std::max(0, bounds["w"].get_or(0)),
        std::max(0, bounds["h"].get_or(0)));
}

void invokeShellMethod(sol::table& shell, const char* name) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

bool parseProfileWindowSizeEnv(int& widthOut, int& heightOut) {
    const char* envValue = std::getenv("MANIFOLD_PROFILE_WINDOW_SIZE");
    if (envValue == nullptr || *envValue == '\0') {
        return false;
    }

    int width = 0;
    int height = 0;
    if (std::sscanf(envValue, "%dx%d", &width, &height) != 2
        && std::sscanf(envValue, "%dX%d", &width, &height) != 2) {
        return false;
    }

    if (width <= 0 || height <= 0) {
        return false;
    }

    widthOut = width;
    heightOut = height;
    return true;
}

void invokeShellMethodWithBool(sol::table& shell, const char* name, bool value) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

void invokeShellMethodWithNumber(sol::table& shell, const char* name, double value) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

void invokeShellMethodWithInts(sol::table& shell, const char* name, int a, int b) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, a, b);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

void invokeShellMethodWithStringAndNumber(sol::table& shell, const char* name,
                                          const std::string& text, double value) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, text, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

void invokeShellMethodWithStringAndInt(sol::table& shell, const char* name,
                                       const char* text, int value) {
    sol::protected_function fn = shell[name];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, text, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.%s failed: %s\n", name, err.what());
    }
}

void applyActiveConfigValue(sol::table& shell, double value, const char* valueKind) {
    sol::protected_function fn = shell["applyActiveConfigValue"];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.applyActiveConfigValue(%s) failed: %s\n",
                     valueKind, err.what());
    }
}

void applyActiveConfigValue(sol::table& shell, bool value, const char* valueKind) {
    sol::protected_function fn = shell["applyActiveConfigValue"];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.applyActiveConfigValue(%s) failed: %s\n",
                     valueKind, err.what());
    }
}

void applyActiveConfigValue(sol::table& shell, const std::string& value, const char* valueKind) {
    sol::protected_function fn = shell["applyActiveConfigValue"];
    if (!fn.valid()) {
        return;
    }
    sol::protected_function_result result = fn(shell, value);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.applyActiveConfigValue(%s) failed: %s\n",
                     valueKind, err.what());
    }
}

void syncEditorDocumentBackToShellTable(sol::table& shell,
                                        const char* tableKey,
                                        const ImGuiHost::StatsSnapshot& stats,
                                        const ImGuiHost::DocumentIdentity& identity,
                                        const std::string& text) {
    sol::object editorObj = shell[tableKey];
    if (!editorObj.valid() || !editorObj.is<sol::table>()) {
        return;
    }

    sol::table editorState = editorObj.as<sol::table>();
    const std::string shellPath = editorState["path"].get_or(std::string{});
    const int64_t shellSyncToken = editorState["syncToken"].get_or(int64_t{-1});
    if (identity.loaded
        && identity.path == shellPath
        && identity.syncToken == shellSyncToken) {
        editorState["text"] = text;
        editorState["dirty"] = stats.documentDirty;
    }
}

void syncMainEditorBackToShell(sol::table& shell,
                               const ImGuiHost::StatsSnapshot& stats,
                               const ImGuiHost::DocumentIdentity& identity,
                               const std::string& text) {
    if (!stats.testWindowVisible) {
        return;
    }

    syncEditorDocumentBackToShellTable(shell, "scriptEditor", stats, identity, text);
    syncEditorDocumentBackToShellTable(shell, "projectScriptEditor", stats, identity, text);
}

bool invokeMainEditorActionHandler(sol::table& shell, const char* actionName) {
    sol::object handlersObj = shell["mainScriptEditorActions"];
    if (!handlersObj.valid() || !handlersObj.is<sol::table>()) {
        return false;
    }

    sol::table handlers = handlersObj.as<sol::table>();
    sol::protected_function fn = handlers[actionName];
    if (!fn.valid()) {
        return false;
    }

    sol::protected_function_result result = fn(shell);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr,
                     "BehaviorCoreEditor: shell.mainScriptEditorActions.%s failed: %s\n",
                     actionName,
                     err.what());
    }
    return true;
}

void applyMainEditorActions(sol::table& shell, const ImGuiHost::ActionRequests& actions) {
    if (actions.save) {
        if (!invokeMainEditorActionHandler(shell, "save")) {
            invokeShellMethod(shell, "saveScriptEditor");
        }
    }
    if (actions.reload) {
        if (!invokeMainEditorActionHandler(shell, "reload")) {
            invokeShellMethod(shell, "reloadScriptEditor");
        }
    }
    if (actions.close) {
        if (!invokeMainEditorActionHandler(shell, "close")) {
            invokeShellMethod(shell, "closeScriptEditor");
        }
    }
}

void applyScriptInspectorActions(sol::table& shell,
                                 const ImGuiInspectorHost::ActionRequests& actions) {
    if (actions.runPreview) {
        invokeShellMethod(shell, "runSelectedDspScriptForInspector");
    }
    if (actions.stopPreview) {
        invokeShellMethod(shell, "stopSelectedDspScriptForInspector");
    }
    if (actions.setEditorCollapsed) {
        invokeShellMethodWithBool(shell, "setScriptInspectorEditorCollapsed", actions.editorCollapsed);
    }
    if (actions.setGraphCollapsed) {
        invokeShellMethodWithBool(shell, "setScriptInspectorGraphCollapsed", actions.graphCollapsed);
    }
    if (actions.setGraphPan) {
        invokeShellMethodWithInts(shell, "setScriptInspectorGraphPan",
                                  actions.graphPanX,
                                  actions.graphPanY);
    }
    if (actions.applyRuntimeParam && !actions.runtimeParamEndpointPath.empty()) {
        invokeShellMethodWithStringAndNumber(shell, "applyScriptInspectorRuntimeParam",
                                             actions.runtimeParamEndpointPath,
                                             actions.runtimeParamValue);
    }
}

void applyScriptListActions(sol::table& shell,
                            const ImGuiScriptListHost::ActionRequests& actions) {
    if (actions.selectIndex <= 0 && actions.openIndex <= 0) {
        return;
    }

    sol::object rowsObj = shell["scriptRows"];
    if (!rowsObj.valid() || !rowsObj.is<sol::table>()) {
        return;
    }

    sol::table scriptRows = rowsObj.as<sol::table>();
    const int targetIndex = actions.openIndex > 0 ? actions.openIndex : actions.selectIndex;
    sol::object rowObj = scriptRows[targetIndex];
    if (!rowObj.valid() || !rowObj.is<sol::table>()) {
        return;
    }

    sol::table row = rowObj.as<sol::table>();

    sol::object customActionsObj = shell["scriptListActions"];
    if (customActionsObj.valid() && customActionsObj.is<sol::table>()) {
        sol::table customActions = customActionsObj.as<sol::table>();
        const char* actionName = actions.openIndex > 0 ? "open" : "select";
        sol::protected_function customHandler = customActions[actionName];
        if (customHandler.valid()) {
            sol::protected_function_result result = customHandler(shell, row, targetIndex);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr,
                             "BehaviorCoreEditor: shell.scriptListActions.%s failed: %s\n",
                             actionName,
                             err.what());
            }
            return;
        }
    }

    sol::protected_function handleSelection = shell["handleLeftListSelection"];
    if (handleSelection.valid()) {
        sol::protected_function_result result = handleSelection(shell, "script", row, sol::lua_nil);
        if (!result.valid()) {
            sol::error err = result;
            std::fprintf(stderr, "BehaviorCoreEditor: shell.handleLeftListSelection failed: %s\n",
                         err.what());
        }
    }

    if (actions.openIndex > 0) {
        sol::protected_function openEditor = shell["openScriptEditor"];
        if (openEditor.valid()) {
            sol::protected_function_result result = openEditor(shell, row);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "BehaviorCoreEditor: shell.openScriptEditor failed: %s\n",
                             err.what());
            }
        }
    }
}

void applyHierarchyActions(sol::table& shell,
                           const ImGuiHierarchyHost::ActionRequests& actions) {
    if (actions.selectIndex <= 0) {
        return;
    }

    sol::object rowsObj = shell["treeRows"];
    if (!rowsObj.valid() || !rowsObj.is<sol::table>()) {
        return;
    }

    sol::table treeRows = rowsObj.as<sol::table>();
    sol::object rowObj = treeRows[actions.selectIndex];
    if (!rowObj.valid() || !rowObj.is<sol::table>()) {
        return;
    }

    sol::table row = rowObj.as<sol::table>();
    sol::object canvasObj = row["canvas"];
    sol::object selectedCanvasObj = shell["selectedWidget"];
    if (!canvasObj.valid() || canvasObj == selectedCanvasObj) {
        return;
    }

    sol::protected_function selectWidget = shell["selectWidget"];
    if (!selectWidget.valid()) {
        return;
    }

    sol::protected_function_result result = selectWidget(shell, canvasObj, true);
    if (!result.valid()) {
        sol::error err = result;
        std::fprintf(stderr, "BehaviorCoreEditor: shell.selectWidget failed: %s\n",
                     err.what());
    }
}

void applyInspectorActions(sol::table& shell,
                           const ImGuiInspectorHost::ActionRequests& actions) {
    if (actions.selectRowIndex > 0) {
        sol::object rowsObj = shell["inspectorRows"];
        if (rowsObj.valid() && rowsObj.is<sol::table>()) {
            sol::table inspectorRows = rowsObj.as<sol::table>();
            sol::object rowObj = inspectorRows[actions.selectRowIndex];
            if (rowObj.valid() && rowObj.is<sol::table>()) {
                sol::table row = rowObj.as<sol::table>();
                sol::protected_function showEditor = shell["_showActivePropertyEditor"];
                if (showEditor.valid()) {
                    sol::protected_function_result result = showEditor(shell, row);
                    if (!result.valid()) {
                        sol::error err = result;
                        std::fprintf(stderr, "BehaviorCoreEditor: shell._showActivePropertyEditor failed: %s\n",
                                     err.what());
                    }
                }
            }
        }
    }

    if (actions.setBoundsX) {
        invokeShellMethodWithStringAndInt(shell, "applyBoundsEditor", "x", actions.boundsX);
    }
    if (actions.setBoundsY) {
        invokeShellMethodWithStringAndInt(shell, "applyBoundsEditor", "y", actions.boundsY);
    }
    if (actions.setBoundsW) {
        invokeShellMethodWithStringAndInt(shell, "applyBoundsEditor", "w", actions.boundsW);
    }
    if (actions.setBoundsH) {
        invokeShellMethodWithStringAndInt(shell, "applyBoundsEditor", "h", actions.boundsH);
    }

    if (actions.applyNumber) {
        applyActiveConfigValue(shell, actions.numberValue, "number");
    }
    if (actions.applyBool) {
        applyActiveConfigValue(shell, actions.boolValue, "bool");
    }
    if (actions.applyText) {
        applyActiveConfigValue(shell, actions.textValue, "text");
    }
    if (actions.applyColor) {
        applyActiveConfigValue(shell, static_cast<double>(actions.colorValue), "color");
    }
    if (actions.applyEnumIndex > 0) {
        sol::protected_function fn = shell["applyActiveConfigEnumChoice"];
        if (fn.valid()) {
            sol::protected_function_result result = fn(shell, actions.applyEnumIndex);
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr, "BehaviorCoreEditor: shell.applyActiveConfigEnumChoice failed: %s\n",
                             err.what());
            }
        }
    }
}

bool populateMainEditorConfigFromShellTable(sol::table& shell,
                                          sol::object surfacesObj,
                                          const char* surfaceId,
                                          const char* tableKey,
                                          HostConfig& mainConfig) {
    HostConfig candidate;
    readSurfaceDescriptor(surfacesObj, surfaceId, candidate.visible, candidate.bounds);
    if (!candidate.visible || candidate.bounds.getWidth() <= 0 || candidate.bounds.getHeight() <= 0) {
        return false;
    }

    sol::object editorObj = shell[tableKey];
    if (!editorObj.valid() || !editorObj.is<sol::table>()) {
        return false;
    }

    sol::table editorState = editorObj.as<sol::table>();
    const std::string path = editorState["path"].get_or(std::string{});
    if (path.empty()) {
        return false;
    }

    candidate.file = juce::File(path);
    candidate.text = editorState["text"].get_or(std::string{});
    candidate.syncToken = editorState["syncToken"].get_or(int64_t{0});
    candidate.readOnly = false;
    mainConfig = std::move(candidate);
    return true;
}

void buildMainEditorConfig(sol::table& shell,
                           sol::object surfacesObj,
                           HostConfig& mainConfig) {
    if (populateMainEditorConfigFromShellTable(shell, surfacesObj,
                                               "projectScriptEditor",
                                               "projectScriptEditor",
                                               mainConfig)) {
        return;
    }

    populateMainEditorConfigFromShellTable(shell, surfacesObj,
                                           "mainScriptEditor",
                                           "scriptEditor",
                                           mainConfig);
}

void buildHierarchyAndInspectorConfig(sol::state& lua,
                                      sol::table& shell,
                                      sol::object surfacesObj,
                                      HierarchyHostConfig& hierarchyConfig,
                                      InspectorHostConfig& inspectorConfig) {
    readSurfaceDescriptor(surfacesObj, "hierarchyTool", hierarchyConfig.visible, hierarchyConfig.bounds);
    if (!hierarchyConfig.visible || hierarchyConfig.bounds.getWidth() <= 0 || hierarchyConfig.bounds.getHeight() <= 0) {
        return;
    }

    sol::object rowsObj = shell["treeRows"];
    if (rowsObj.valid() && rowsObj.is<sol::table>()) {
        sol::table treeRows = rowsObj.as<sol::table>();
        sol::object selectedCanvasObj = shell["selectedWidget"];
        const auto rowCount = treeRows.size();
        hierarchyConfig.rows.reserve(rowCount);
        for (std::size_t i = 1; i <= rowCount; ++i) {
            sol::object rowObj = treeRows[i];
            if (!rowObj.valid() || !rowObj.is<sol::table>()) {
                continue;
            }
            sol::table row = rowObj.as<sol::table>();
            ImGuiHierarchyHost::TreeRow hostRow;
            hostRow.depth = row["depth"].get_or(0);
            hostRow.type = row["type"].get_or(std::string{});
            hostRow.name = row["name"].get_or(std::string{});
            hostRow.path = row["path"].get_or(std::string{});
            sol::object rowCanvasObj = row["canvas"];
            hostRow.selected = selectedCanvasObj.valid() && rowCanvasObj.valid()
                && selectedCanvasObj == rowCanvasObj;
            hierarchyConfig.rows.push_back(std::move(hostRow));
        }
    }

    readSurfaceDescriptor(surfacesObj, "inspectorTool", inspectorConfig.visible, inspectorConfig.bounds);
    if (inspectorConfig.visible && inspectorConfig.bounds.getWidth() > 0 && inspectorConfig.bounds.getHeight() > 0) {
        sol::protected_function getSelectionBounds = shell["getSelectionBounds"];
        if (getSelectionBounds.valid()) {
            sol::protected_function_result result = getSelectionBounds(shell);
            if (result.valid()) {
                sol::object boundsObj = result;
                if (boundsObj.valid() && boundsObj.is<sol::table>()) {
                    sol::table selectionBounds = boundsObj.as<sol::table>();
                    inspectorConfig.selectionBounds.enabled = true;
                    inspectorConfig.selectionBounds.x = selectionBounds["x"].get_or(0);
                    inspectorConfig.selectionBounds.y = selectionBounds["y"].get_or(0);
                    inspectorConfig.selectionBounds.w = selectionBounds["w"].get_or(1);
                    inspectorConfig.selectionBounds.h = selectionBounds["h"].get_or(1);
                }
            }
        }

        sol::object inspectorRowsObj = shell["inspectorRows"];
        sol::object activePropertyObj = shell["activeConfigProperty"];
        std::string activePath;
        if (activePropertyObj.valid() && activePropertyObj.is<sol::table>()) {
            sol::table activeProperty = activePropertyObj.as<sol::table>();
            inspectorConfig.activeProperty.valid = true;
            inspectorConfig.activeProperty.key = activeProperty["key"].get_or(std::string{});
            inspectorConfig.activeProperty.path = activeProperty["path"].get_or(std::string{});
            inspectorConfig.activeProperty.editorType = activeProperty["editorType"].get_or(std::string{});
            inspectorConfig.activeProperty.displayValue = activeProperty["value"].get_or(std::string{});
            inspectorConfig.activeProperty.mixed = activeProperty["mixed"].get_or(false);
            activePath = inspectorConfig.activeProperty.path;

            sol::object rawValueObj = activeProperty["rawValue"];
            if (rawValueObj.is<double>()) {
                inspectorConfig.activeProperty.numberValue = rawValueObj.as<double>();
                inspectorConfig.activeProperty.colorValue = static_cast<std::uint32_t>(rawValueObj.as<double>());
            } else if (rawValueObj.is<bool>()) {
                inspectorConfig.activeProperty.boolValue = rawValueObj.as<bool>();
            } else if (rawValueObj.is<std::string>()) {
                inspectorConfig.activeProperty.textValue = rawValueObj.as<std::string>();
            }
            if (inspectorConfig.activeProperty.editorType == "text") {
                inspectorConfig.activeProperty.textValue = rawValueObj.is<std::string>()
                    ? rawValueObj.as<std::string>()
                    : std::string{};
            }
            sol::object minObj = activeProperty["min"];
            sol::object maxObj = activeProperty["max"];
            sol::object stepObj = activeProperty["step"];
            inspectorConfig.activeProperty.hasMin = minObj.valid() && minObj.is<double>();
            inspectorConfig.activeProperty.hasMax = maxObj.valid() && maxObj.is<double>();
            if (inspectorConfig.activeProperty.hasMin) {
                inspectorConfig.activeProperty.minValue = minObj.as<double>();
            }
            if (inspectorConfig.activeProperty.hasMax) {
                inspectorConfig.activeProperty.maxValue = maxObj.as<double>();
            }
            inspectorConfig.activeProperty.stepValue = stepObj.valid() && stepObj.is<double>()
                ? stepObj.as<double>()
                : 0.0;

            sol::object enumOptionsObj = activeProperty["enumOptions"];
            if (enumOptionsObj.valid() && enumOptionsObj.is<sol::table>()) {
                sol::table enumOptions = enumOptionsObj.as<sol::table>();
                sol::object rawValue = activeProperty["rawValue"];
                const auto optionCount = enumOptions.size();
                for (std::size_t optionIndex = 1; optionIndex <= optionCount; ++optionIndex) {
                    sol::object optionObj = enumOptions[optionIndex];
                    if (!optionObj.valid() || !optionObj.is<sol::table>()) {
                        continue;
                    }
                    sol::table option = optionObj.as<sol::table>();
                    inspectorConfig.activeProperty.enumLabels.push_back(option["label"].get_or(std::string{}));
                    sol::object optionValue = option["value"];
                    bool matches = false;
                    if (rawValue.get_type() == optionValue.get_type()) {
                        if (rawValue.is<bool>()) {
                            matches = rawValue.as<bool>() == optionValue.as<bool>();
                        } else if (rawValue.is<double>()) {
                            matches = std::abs(rawValue.as<double>() - optionValue.as<double>()) < 1.0e-9;
                        } else if (rawValue.is<std::string>()) {
                            matches = rawValue.as<std::string>() == optionValue.as<std::string>();
                        }
                    }
                    if (matches) {
                        inspectorConfig.activeProperty.enumSelectedIndex = static_cast<int>(optionIndex);
                    }
                }
            }
        }

        if (inspectorRowsObj.valid() && inspectorRowsObj.is<sol::table>()) {
            sol::table inspectorRows = inspectorRowsObj.as<sol::table>();
            const auto inspectorRowCount = inspectorRows.size();
            inspectorConfig.rows.reserve(inspectorRowCount);
            for (std::size_t i = 1; i <= inspectorRowCount; ++i) {
                sol::object rowObj = inspectorRows[i];
                if (!rowObj.valid() || !rowObj.is<sol::table>()) {
                    continue;
                }
                sol::table row = rowObj.as<sol::table>();
                ImGuiInspectorHost::InspectorRow hostRow;
                hostRow.rowIndex = static_cast<int>(i);
                hostRow.section = !row["isConfig"].get_or(false) && row["value"].get_or(std::string{}).empty();
                hostRow.interactive = row["isConfig"].get_or(false);
                hostRow.key = row["key"].get_or(std::string{});
                hostRow.value = row["value"].get_or(std::string{});
                hostRow.selected = hostRow.interactive && !activePath.empty()
                    && row["path"].get_or(std::string{}) == activePath;
                inspectorConfig.rows.push_back(std::move(hostRow));
            }
        }

        lua["__manifoldImguiInspectorActive"] = true;
    }

    lua["__manifoldImguiHierarchyActive"] = true;
}

void buildScriptListConfig(sol::state& lua,
                           sol::table& shell,
                           sol::object surfacesObj,
                           ScriptListHostConfig& scriptListConfig) {
    readSurfaceDescriptor(surfacesObj, "scriptList", scriptListConfig.visible, scriptListConfig.bounds);
    if (!scriptListConfig.visible || scriptListConfig.bounds.getWidth() <= 0 || scriptListConfig.bounds.getHeight() <= 0) {
        return;
    }

    sol::object rowsObj = shell["scriptRows"];
    if (rowsObj.valid() && rowsObj.is<sol::table>()) {
        sol::table scriptRows = rowsObj.as<sol::table>();
        const std::string selectedPath = [&]() {
            sol::object selectedObj = shell["selectedScriptRow"];
            if (!selectedObj.valid() || !selectedObj.is<sol::table>()) {
                return std::string{};
            }
            sol::table selectedRow = selectedObj.as<sol::table>();
            return selectedRow["path"].get_or(std::string{});
        }();
        const std::string selectedKind = [&]() {
            sol::object selectedObj = shell["selectedScriptRow"];
            if (!selectedObj.valid() || !selectedObj.is<sol::table>()) {
                return std::string{};
            }
            sol::table selectedRow = selectedObj.as<sol::table>();
            return selectedRow["kind"].get_or(std::string{});
        }();

        const auto rowCount = scriptRows.size();
        scriptListConfig.rows.reserve(rowCount);
        for (std::size_t i = 1; i <= rowCount; ++i) {
            sol::object rowObj = scriptRows[i];
            if (!rowObj.valid() || !rowObj.is<sol::table>()) {
                continue;
            }
            sol::table row = rowObj.as<sol::table>();
            ImGuiScriptListHost::ScriptRow hostRow;
            hostRow.section = row["section"].get_or(false);
            hostRow.nonInteractive = row["nonInteractive"].get_or(false);
            hostRow.active = row["active"].get_or(false);
            hostRow.dirty = row["dirty"].get_or(false);
            hostRow.kind = row["kind"].get_or(std::string{});
            hostRow.ownership = row["ownership"].get_or(std::string{});
            hostRow.path = row["path"].get_or(std::string{});
            hostRow.name = row["name"].get_or(std::string{});
            hostRow.label = row["label"].get_or(std::string{});
            hostRow.selected = (!selectedPath.empty()
                && hostRow.path == selectedPath
                && hostRow.kind == selectedKind);
            scriptListConfig.rows.push_back(std::move(hostRow));
        }
    }

    lua["__manifoldImguiScriptListActive"] = true;
}

void buildScriptInspectorConfig(sol::state& lua,
                                sol::table& shell,
                                sol::object surfacesObj,
                                const std::string& shellMode,
                                const std::string& leftPanelMode,
                                InspectorHostConfig& scriptInspectorConfig) {
    if (shellMode != "edit" || leftPanelMode != "scripts") {
        return;
    }

    readSurfaceDescriptor(surfacesObj, "scriptInspectorTool", scriptInspectorConfig.visible, scriptInspectorConfig.bounds);
    sol::object scriptInspectorObj = shell["scriptInspector"];
    if (!scriptInspectorConfig.visible
        || scriptInspectorConfig.bounds.getWidth() <= 0
        || scriptInspectorConfig.bounds.getHeight() <= 0
        || !scriptInspectorObj.valid()
        || !scriptInspectorObj.is<sol::table>()) {
        return;
    }

    sol::table scriptInspector = scriptInspectorObj.as<sol::table>();
    scriptInspectorConfig.scriptMode = true;

    const std::string path = scriptInspector["path"].get_or(std::string{});
    scriptInspectorConfig.scriptData.hasSelection = !path.empty();
    scriptInspectorConfig.scriptData.name = scriptInspector["name"].get_or(std::string{});
    scriptInspectorConfig.scriptData.kind = scriptInspector["kind"].get_or(std::string{});
    scriptInspectorConfig.scriptData.ownership = scriptInspector["ownership"].get_or(std::string{});
    scriptInspectorConfig.scriptData.path = path;
    scriptInspectorConfig.scriptData.text = scriptInspector["text"].get_or(std::string{});
    scriptInspectorConfig.scriptData.syncToken = scriptInspector["syncToken"].get_or(int64_t{0});
    scriptInspectorConfig.scriptData.inlineReadOnly = true;
    scriptInspectorConfig.scriptData.runtimeStatus = scriptInspector["runtimeStatus"].get_or(std::string{});
    scriptInspectorConfig.scriptData.editorCollapsed = scriptInspector["editorCollapsed"].get_or(false);
    scriptInspectorConfig.scriptData.graphCollapsed = scriptInspector["graphCollapsed"].get_or(false);
    scriptInspectorConfig.scriptData.graphPanX = scriptInspector["graphPanX"].get_or(0);
    scriptInspectorConfig.scriptData.graphPanY = scriptInspector["graphPanY"].get_or(0);

    if (!path.empty()) {
        sol::protected_function getDocumentStatus = shell["getStructuredDocumentStatus"];
        if (getDocumentStatus.valid()) {
            sol::protected_function_result result = getDocumentStatus(shell, path);
            if (result.valid()) {
                sol::object statusObj = result;
                if (statusObj.valid() && statusObj.is<sol::table>()) {
                    sol::table status = statusObj.as<sol::table>();
                    scriptInspectorConfig.scriptData.hasStructuredStatus = true;
                    scriptInspectorConfig.scriptData.structuredDirty = status["dirty"].get_or(false);
                }
            }
        }
    }

    sol::protected_function getProjectStatus = shell["getStructuredProjectStatus"];
    if (getProjectStatus.valid()) {
        sol::protected_function_result result = getProjectStatus(shell);
        if (result.valid()) {
            sol::object statusObj = result;
            if (statusObj.valid() && statusObj.is<sol::table>()) {
                sol::table status = statusObj.as<sol::table>();
                scriptInspectorConfig.scriptData.projectLastError = status["lastError"].get_or(std::string{});
            }
        }
    }

    sol::object paramsObj = scriptInspector["params"];
    if (paramsObj.valid() && paramsObj.is<sol::table>()) {
        sol::table params = paramsObj.as<sol::table>();
        const auto count = params.size();
        scriptInspectorConfig.scriptData.declaredParams.reserve(count);
        for (std::size_t i = 1; i <= count; ++i) {
            sol::object paramObj = params[i];
            if (!paramObj.valid() || !paramObj.is<sol::table>()) {
                continue;
            }
            sol::table param = paramObj.as<sol::table>();
            ImGuiInspectorHost::DeclaredParam hostParam;
            hostParam.path = param["path"].get_or(std::string{});
            sol::object defaultObj = param["default"];
            if (defaultObj.valid()) {
                if (defaultObj.is<double>()) {
                    hostParam.defaultValue = juce::String(defaultObj.as<double>()).toStdString();
                } else if (defaultObj.is<bool>()) {
                    hostParam.defaultValue = defaultObj.as<bool>() ? "true" : "false";
                } else if (defaultObj.is<std::string>()) {
                    hostParam.defaultValue = defaultObj.as<std::string>();
                }
            }
            scriptInspectorConfig.scriptData.declaredParams.push_back(std::move(hostParam));
        }
    }

    sol::object runtimeParamsObj = scriptInspector["runtimeParams"];
    if (runtimeParamsObj.valid() && runtimeParamsObj.is<sol::table>()) {
        sol::table runtimeParams = runtimeParamsObj.as<sol::table>();
        const auto count = runtimeParams.size();
        scriptInspectorConfig.scriptData.runtimeParams.reserve(count);
        for (std::size_t i = 1; i <= count; ++i) {
            sol::object paramObj = runtimeParams[i];
            if (!paramObj.valid() || !paramObj.is<sol::table>()) {
                continue;
            }
            sol::table param = paramObj.as<sol::table>();
            ImGuiInspectorHost::RuntimeParam hostParam;
            hostParam.endpointPath = param["endpointPath"].get_or(param["path"].get_or(std::string{}));
            hostParam.path = param["path"].get_or(std::string{});
            hostParam.displayValue = param["value"].get_or(std::string{});
            hostParam.active = param["active"].get_or(false);
            sol::object numericValueObj = param["numericValue"];
            if (numericValueObj.valid() && numericValueObj.is<double>()) {
                hostParam.hasValue = true;
                hostParam.value = numericValueObj.as<double>();
            } else {
                sol::object textValueObj = param["value"];
                if (textValueObj.valid() && textValueObj.is<std::string>()) {
                    const auto parsed = juce::String(textValueObj.as<std::string>()).getDoubleValue();
                    hostParam.value = parsed;
                }
            }
            sol::object minObj = param["min"];
            sol::object maxObj = param["max"];
            sol::object stepObj = param["step"];
            hostParam.hasMin = minObj.valid() && minObj.is<double>();
            hostParam.hasMax = maxObj.valid() && maxObj.is<double>();
            if (hostParam.hasMin) {
                hostParam.minValue = minObj.as<double>();
            }
            if (hostParam.hasMax) {
                hostParam.maxValue = maxObj.as<double>();
            }
            if (stepObj.valid() && stepObj.is<double>()) {
                hostParam.stepValue = stepObj.as<double>();
            }
            scriptInspectorConfig.scriptData.runtimeParams.push_back(std::move(hostParam));
        }
    }

    sol::object graphObj = scriptInspector["graph"];
    if (graphObj.valid() && graphObj.is<sol::table>()) {
        sol::table graph = graphObj.as<sol::table>();
        sol::object nodesObj = graph["nodes"];
        sol::object edgesObj = graph["edges"];
        if (nodesObj.valid() && nodesObj.is<sol::table>()) {
            sol::table nodes = nodesObj.as<sol::table>();
            const auto count = nodes.size();
            scriptInspectorConfig.scriptData.graphNodes.reserve(count);
            for (std::size_t i = 1; i <= count; ++i) {
                sol::object nodeObj = nodes[i];
                if (!nodeObj.valid() || !nodeObj.is<sol::table>()) {
                    continue;
                }
                sol::table node = nodeObj.as<sol::table>();
                ImGuiInspectorHost::GraphNode hostNode;
                hostNode.var = node["var"].get_or(std::string{"n"});
                hostNode.prim = node["prim"].get_or(std::string{"node"});
                scriptInspectorConfig.scriptData.graphNodes.push_back(std::move(hostNode));
            }
        }
        if (edgesObj.valid() && edgesObj.is<sol::table>()) {
            sol::table edges = edgesObj.as<sol::table>();
            const auto count = edges.size();
            scriptInspectorConfig.scriptData.graphEdges.reserve(count);
            for (std::size_t i = 1; i <= count; ++i) {
                sol::object edgeObj = edges[i];
                if (!edgeObj.valid() || !edgeObj.is<sol::table>()) {
                    continue;
                }
                sol::table edge = edgeObj.as<sol::table>();
                ImGuiInspectorHost::GraphEdge hostEdge;
                hostEdge.fromIndex = edge["from"].get_or(0);
                hostEdge.toIndex = edge["to"].get_or(0);
                scriptInspectorConfig.scriptData.graphEdges.push_back(std::move(hostEdge));
            }
        }
    }

    lua["__manifoldImguiInspectorActive"] = true;
}

void buildPerfOverlayConfig(LuaEngine& luaEngine,
                            sol::state& lua,
                            sol::table& shell,
                            HostConfig const& mainConfig,
                            ScriptListHostConfig const& scriptListConfig,
                            HierarchyHostConfig const& hierarchyConfig,
                            InspectorHostConfig const& inspectorConfig,
                            const std::string& rendererModeLabel,
                            PerfOverlayHostConfig& perfOverlayConfig) {
    sol::object perfOverlayObj = shell["perfOverlay"];
    if (!perfOverlayObj.valid() || !perfOverlayObj.is<sol::table>()) {
        return;
    }

    sol::table perfOverlay = perfOverlayObj.as<sol::table>();
    perfOverlayConfig.snapshot.activeTab = perfOverlay["activeTab"].get_or(std::string{"frame"});

    sol::object perfSurfacesObj = shell["surfaces"];
    if (perfSurfacesObj.valid() && perfSurfacesObj.is<sol::table>()) {
        sol::table surfaces = perfSurfacesObj.as<sol::table>();
        sol::object perfSurfaceObj = surfaces["perfOverlay"];
        if (perfSurfaceObj.valid() && perfSurfaceObj.is<sol::table>()) {
            sol::table perfSurface = perfSurfaceObj.as<sol::table>();
            perfOverlayConfig.visible = perfSurface["visible"].get_or(false);
            perfOverlayConfig.snapshot.title = perfSurface["title"].get_or(std::string{"Performance"});

            sol::object boundsObj = perfSurface["bounds"];
            if (boundsObj.valid() && boundsObj.is<sol::table>()) {
                sol::table bounds = boundsObj.as<sol::table>();
                perfOverlayConfig.bounds = juce::Rectangle<int>(
                    bounds["x"].get_or(0),
                    bounds["y"].get_or(0),
                    std::max(0, bounds["w"].get_or(0)),
                    std::max(0, bounds["h"].get_or(0)));
            }
        }
    }

    auto addTab = [&](const std::string& id, const std::string& label) -> ImGuiPerfOverlayHost::TabData& {
        perfOverlayConfig.snapshot.tabs.push_back(ImGuiPerfOverlayHost::TabData{});
        auto& tab = perfOverlayConfig.snapshot.tabs.back();
        tab.id = id;
        tab.label = label;
        return tab;
    };
    auto addRow = [](ImGuiPerfOverlayHost::TabData& tab, const std::string& label, const std::string& value) {
        tab.rows.push_back(ImGuiPerfOverlayHost::MetricRow{label, value});
    };
    auto boolText = [](bool v) { return v ? std::string{"yes"} : std::string{"no"}; };
    auto usText = [](int64_t v) { return std::to_string(static_cast<long long>(v)) + " us"; };
    auto msText = [](double v) {
        char buf[64];
        std::snprintf(buf, sizeof(buf), "%.3f ms", v);
        return std::string(buf);
    };

    auto& frameTab = addTab("frame", "Frame");
    addRow(frameTab, "Frame count", std::to_string(static_cast<long long>(luaEngine.frameTimings.frameCount.load(std::memory_order_relaxed))));
    addRow(frameTab, "Total current", usText(luaEngine.frameTimings.total.currentUs.load(std::memory_order_relaxed)));
    addRow(frameTab, "Total avg", usText(luaEngine.frameTimings.total.getAvgUs()));
    addRow(frameTab, "Total peak", usText(luaEngine.frameTimings.total.peakUs.load(std::memory_order_relaxed)));
    addRow(frameTab, "Push state", usText(luaEngine.frameTimings.pushState.currentUs.load(std::memory_order_relaxed)));
    addRow(frameTab, "Event listeners", usText(luaEngine.frameTimings.eventListeners.currentUs.load(std::memory_order_relaxed)));
    addRow(frameTab, "UI update", usText(luaEngine.frameTimings.uiUpdate.currentUs.load(std::memory_order_relaxed)));
    addRow(frameTab, "Paint", usText(luaEngine.frameTimings.paint.currentUs.load(std::memory_order_relaxed)));

    auto& imguiTab = addTab("imgui", "ImGui");
    addRow(imguiTab, "Context ready", boolText(luaEngine.frameTimings.imguiContextReady.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Capture mouse", boolText(luaEngine.frameTimings.imguiWantCaptureMouse.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Capture keyboard", boolText(luaEngine.frameTimings.imguiWantCaptureKeyboard.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Render", usText(luaEngine.frameTimings.imguiRenderUs.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Vertices", std::to_string(static_cast<long long>(luaEngine.frameTimings.imguiVertexCount.load(std::memory_order_relaxed))));
    addRow(imguiTab, "Indices", std::to_string(static_cast<long long>(luaEngine.frameTimings.imguiIndexCount.load(std::memory_order_relaxed))));
    addRow(imguiTab, "Document loaded", boolText(luaEngine.frameTimings.imguiDocumentLoaded.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Document dirty", boolText(luaEngine.frameTimings.imguiDocumentDirty.load(std::memory_order_relaxed)));
    addRow(imguiTab, "Document lines", std::to_string(static_cast<long long>(luaEngine.frameTimings.imguiDocumentLineCount.load(std::memory_order_relaxed))));

    auto& editorTab = addTab("editor", "Editor");
    sol::object editorPerfObj = lua["__manifoldEditorPerf"];
    if (editorPerfObj.valid() && editorPerfObj.is<sol::table>()) {
        sol::table editorPerf = editorPerfObj.as<sol::table>();
        addRow(editorTab, "Last event", editorPerf["lastEvent"].get_or(std::string{""}));
        addRow(editorTab, "Draw", msText(editorPerf["lastDrawMs"].get_or(0.0)));
        addRow(editorTab, "Draw peak", msText(editorPerf["peakDrawMs"].get_or(0.0)));
        addRow(editorTab, "Line build", msText(editorPerf["lastLineBuildMs"].get_or(0.0)));
        addRow(editorTab, "Cursor lookup", msText(editorPerf["lastCursorLookupMs"].get_or(0.0)));
        addRow(editorTab, "Post cursor", msText(editorPerf["lastPostCursorMs"].get_or(0.0)));
        addRow(editorTab, "Wheel", msText(editorPerf["lastWheelMs"].get_or(0.0)));
        addRow(editorTab, "Wheel peak", msText(editorPerf["peakWheelMs"].get_or(0.0)));
        addRow(editorTab, "Keypress", msText(editorPerf["lastKeypressMs"].get_or(0.0)));
        addRow(editorTab, "Keypress peak", msText(editorPerf["peakKeypressMs"].get_or(0.0)));
        addRow(editorTab, "Ensure visible", msText(editorPerf["lastEnsureVisibleMs"].get_or(0.0)));
        addRow(editorTab, "Ensure visible peak", msText(editorPerf["peakEnsureVisibleMs"].get_or(0.0)));
        addRow(editorTab, "Pos from point", msText(editorPerf["lastPosFromPointMs"].get_or(0.0)));
        addRow(editorTab, "Pos from point peak", msText(editorPerf["peakPosFromPointMs"].get_or(0.0)));
        addRow(editorTab, "Visible lines", std::to_string(editorPerf["lastVisibleLines"].get_or(0)));
        addRow(editorTab, "Syntax spans", std::to_string(editorPerf["lastSyntaxSpanCount"].get_or(0)));
        addRow(editorTab, "Syntax draw calls", std::to_string(editorPerf["lastSyntaxDrawCalls"].get_or(0)));
        addRow(editorTab, "Gutter draw calls", std::to_string(editorPerf["lastGutterDrawCalls"].get_or(0)));
        addRow(editorTab, "Text length", std::to_string(editorPerf["lastTextLen"].get_or(0)));
        addRow(editorTab, "Cursor", std::to_string(editorPerf["lastCursorLine"].get_or(0)) + ":" + std::to_string(editorPerf["lastCursorCol"].get_or(0)));
    } else {
        addRow(editorTab, "Status", "No editor metrics available");
    }

    auto& uiTab = addTab("ui", "UI");
    addRow(uiTab, "Renderer", rendererModeLabel);
    addRow(uiTab, "Mode", shell["mode"].get_or(std::string{}));
    addRow(uiTab, "Left panel", shell["leftPanelMode"].get_or(std::string{}));
    addRow(uiTab, "Edit content", shell["editContentMode"].get_or(std::string{}));
    addRow(uiTab, "Total paint accumulated", usText(luaEngine.frameTimings.totalPaintAccumulatedUs.load(std::memory_order_relaxed)));
    addRow(uiTab, "Main editor visible", boolText(mainConfig.visible));
    addRow(uiTab, "Script list visible", boolText(scriptListConfig.visible));
    addRow(uiTab, "Hierarchy visible", boolText(hierarchyConfig.visible));
    addRow(uiTab, "Inspector visible", boolText(inspectorConfig.visible));

    auto& paintTab = addTab("paint", "Paint");
    const auto paintProfile = Canvas::getLastFramePaintProfile(8);
    addRow(paintTab, "Accumulated canvas paint", usText(Canvas::getLastFrameAccumulatedPaintUs()));
    addRow(paintTab, "Tracked canvases", std::to_string(static_cast<long long>(paintProfile.size())));
    if (paintProfile.empty()) {
        addRow(paintTab, "Status", "No canvas paint samples yet");
    } else {
        for (std::size_t i = 0; i < paintProfile.size(); ++i) {
            const auto& sample = paintProfile[i];
            std::string label = "Hot canvas " + std::to_string(static_cast<long long>(i + 1));
            std::string value = sample.name;
            if (!sample.widgetType.empty()) {
                value += " [" + sample.widgetType + "]";
            }
            value += " | total=" + usText(sample.totalUs);
            value += " last=" + usText(sample.lastUs);
            value += " paints=" + std::to_string(sample.paintCount);
            value += " size=" + std::to_string(sample.width) + "x" + std::to_string(sample.height);
            value += sample.openGL ? " | gl" : " | cpu";
            addRow(paintTab, label, value);
        }
    }

    constexpr int kPerfOverlayMinWidth = 560;
    constexpr int kPerfOverlayMinHeight = 520;
    constexpr int kPerfTabWidth = 92;
    constexpr int kPerfTabGap = 6;
    constexpr int kPerfOuterPadding = 10;
    const int tabCount = static_cast<int>(perfOverlayConfig.snapshot.tabs.size());
    const int tabStripWidth = kPerfOuterPadding * 2
        + std::max(0, tabCount) * kPerfTabWidth
        + std::max(0, tabCount - 1) * kPerfTabGap;
    const int minWidth = std::max(kPerfOverlayMinWidth, tabStripWidth + 16);
    perfOverlayConfig.bounds.setWidth(std::max(perfOverlayConfig.bounds.getWidth(), minWidth));
    perfOverlayConfig.bounds.setHeight(std::max(perfOverlayConfig.bounds.getHeight(), kPerfOverlayMinHeight));
}

void applyMainEditorHostConfig(HostLayoutTraceState& trace,
                               ImGuiHost& host,
                               const HostConfig& config) {
    logEditorHostLayout("mainScriptEditorHost", trace, config.visible,
                        config.visible ? config.bounds : juce::Rectangle<int>());
    if (config.visible) {
        host.configureDocument(config.file, config.text, config.syncToken, config.readOnly);
    }
}

void applyHierarchyHostConfig(HostLayoutTraceState& trace,
                              ImGuiHierarchyHost& host,
                              const HierarchyHostConfig& config) {
    logEditorHostLayout("hierarchyHost", trace, config.visible,
                        config.visible ? config.bounds : juce::Rectangle<int>());
    if (config.visible) {
        host.configureRows(config.rows);
    }
}

void applyScriptListHostConfig(HostLayoutTraceState& trace,
                               ImGuiScriptListHost& host,
                               const ScriptListHostConfig& config) {
    logEditorHostLayout("scriptListHost", trace, config.visible,
                        config.visible ? config.bounds : juce::Rectangle<int>());
    if (config.visible) {
        host.configureRows(config.rows);
    }
}

void applyInspectorHostConfig(HostLayoutTraceState& trace,
                              ImGuiInspectorHost& host,
                              const InspectorHostConfig& config) {
    logEditorHostLayout("inspectorHost", trace, config.visible,
                        config.visible ? config.bounds : juce::Rectangle<int>());
    if (config.visible) {
        host.configureData(config.selectionBounds, config.rows, config.activeProperty);
    }
}

void applyScriptInspectorHostConfig(HostLayoutTraceState& trace,
                                    ImGuiInspectorHost& host,
                                    const InspectorHostConfig& config) {
    logEditorHostLayout("scriptInspectorHost", trace, config.visible,
                        config.visible ? config.bounds : juce::Rectangle<int>());
    if (config.visible) {
        host.configureScriptData(config.scriptData);
    }
}

void applyPerfOverlayHostConfig(ImGuiPerfOverlayHost& host,
                                const PerfOverlayHostConfig& config) {
    if (config.visible) {
        host.configureSnapshot(config.snapshot);
    }
}

}

RuntimeNode* BehaviorCoreEditor::getActiveRootRuntimeNode() {
    if (rootMode_ == RootMode::RuntimeNode) {
        return rootRuntime_.get();
    }
    return rootCanvas.getRuntimeNode();
}

const char* BehaviorCoreEditor::runtimeRendererModeToString(RuntimeRendererMode mode) {
    switch (mode) {
        case RuntimeRendererMode::Canvas:
            return "canvas";
        case RuntimeRendererMode::ImGuiOverlay:
            return "imgui-overlay";
        case RuntimeRendererMode::ImGuiReplace:
            return "imgui-replace";
        case RuntimeRendererMode::ImGuiDirect:
            return "imgui-direct";
    }

    return "canvas";
}

BehaviorCoreEditor::RuntimeRendererMode BehaviorCoreEditor::runtimeRendererModeFromString(
    const std::string& value,
    RuntimeRendererMode fallback) {
    std::string normalized;
    normalized.reserve(value.size());
    for (char ch : value) {
        if (ch >= 'A' && ch <= 'Z') {
            normalized.push_back(static_cast<char>(ch - 'A' + 'a'));
        } else {
            normalized.push_back(ch == '_' ? '-' : ch);
        }
    }

    if (normalized.empty()) {
        return fallback;
    }
    if (normalized == "0" || normalized == "off" || normalized == "false" || normalized == "canvas") {
        return RuntimeRendererMode::Canvas;
    }
    if (normalized == "1" || normalized == "on" || normalized == "true" || normalized == "imgui"
        || normalized == "overlay" || normalized == "imgui-overlay") {
        return RuntimeRendererMode::ImGuiOverlay;
    }
    if (normalized == "replace" || normalized == "full" || normalized == "imgui-replace"
        || normalized == "imgui-full") {
        return RuntimeRendererMode::ImGuiReplace;
    }
    if (normalized == "direct" || normalized == "imgui-direct") {
        return RuntimeRendererMode::ImGuiDirect;
    }
    return fallback;
}

void BehaviorCoreEditor::setRuntimeRendererMode(RuntimeRendererMode mode, bool logChange) {
    if (rootMode_ == RootMode::RuntimeNode
        && (mode == RuntimeRendererMode::Canvas || mode == RuntimeRendererMode::ImGuiOverlay)) {
        mode = RuntimeRendererMode::ImGuiDirect;
    }

    if (runtimeRendererMode_ == mode) {
        updateRuntimeRendererPresentation();
        processorRef.getControlServer().setCurrentUIRendererMode(static_cast<int>(runtimeRendererMode_));
        return;
    }

    runtimeRendererMode_ = mode;
    directHostNeedsInitialFocus_ = (runtimeRendererMode_ == RuntimeRendererMode::ImGuiDirect);
    LuaRuntimeNodeBindings::setAllowAutomaticLegacyRetainedReplay(runtimeRendererMode_ != RuntimeRendererMode::ImGuiDirect);
    processorRef.getControlServer().setCurrentUIRendererMode(static_cast<int>(runtimeRendererMode_));

    if (runtimeRendererMode_ != RuntimeRendererMode::Canvas) {
        luaEngine.withLuaState([](sol::state& L) {
            sol::object shellObj = L["_G"]["shell"];
            if (!shellObj.valid() || !shellObj.is<sol::table>()) {
                return;
            }
            auto shellTable = shellObj.as<sol::table>();
            invokeShellMethod(shellTable, "flushDeferredRefreshes");
        });
    }

    runtimeNodeDebugHost.setRootNode(getActiveRootRuntimeNode());
    updateRuntimeRendererPresentation();

    if (logChange) {
        std::fprintf(stderr,
                     "BehaviorCoreEditor: UI renderer mode -> %s\n",
                     runtimeRendererModeToString(runtimeRendererMode_));
    }
}

void BehaviorCoreEditor::updateRuntimeRendererPresentation() {
    // ImGuiDirect uses the new direct host; other modes use the old debug host
    const bool useDirect = (runtimeRendererMode_ == RuntimeRendererMode::ImGuiDirect);

    if (!useDirect) {
        // Hide direct host by zeroing bounds only; keep GL context alive.
        directHost_.setBounds(0, 0, 0, 0);
        directHost_.setRootNode(nullptr);

        // Configure old debug host
        runtimeNodeDebugHost.setRootNode(getActiveRootRuntimeNode());
        runtimeNodeDebugHost.setUseLiveTree(false);
        runtimeNodeDebugHost.setPresentationMode(
            runtimeRendererMode_ == RuntimeRendererMode::ImGuiReplace
                ? ImGuiRuntimeNodeHost::PresentationMode::Replace
                : ImGuiRuntimeNodeHost::PresentationMode::DebugPreview);
    } else {
        // Hide old debug host by zeroing bounds only; keep GL context alive.
        runtimeNodeDebugHost.setRootNode(nullptr);
        runtimeNodeDebugHost.setBounds(0, 0, 0, 0);
    }

    switch (runtimeRendererMode_) {
        case RuntimeRendererMode::Canvas: {
            runtimeNodeDebugHost.setBounds(0, 0, 0, 0);
            directHost_.setBounds(0, 0, 0, 0);
            return;
        }
        case RuntimeRendererMode::ImGuiOverlay: {
            const int debugW = std::min(420, std::max(240, getWidth() / 2));
            const int debugH = std::min(280, std::max(180, getHeight() / 2));
            runtimeNodeDebugHost.setBounds(getWidth() - debugW - 12, 12, debugW, debugH);
            runtimeNodeDebugHost.setVisible(true);
            runtimeNodeDebugHost.toFront(false);
            return;
        }
        case RuntimeRendererMode::ImGuiReplace: {
            runtimeNodeDebugHost.setBounds(getLocalBounds());
            runtimeNodeDebugHost.setVisible(true);
            runtimeNodeDebugHost.toFront(false);
            return;
        }
        case RuntimeRendererMode::ImGuiDirect: {
            directHost_.setRootNode(rootRuntime_.get());
            directHost_.setBounds(getLocalBounds());
            directHost_.setVisible(true);
            directHost_.toBack();
            if (perfOverlayHost.isVisible()) {
                perfOverlayHost.toFront(false);
            } else if (directHostNeedsInitialFocus_) {
                directHost_.grabKeyboardFocus();
                directHostNeedsInitialFocus_ = false;
            }
            return;
        }
    }
}

BehaviorCoreEditor::BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor,
                                       RootMode rootMode)
    : juce::AudioProcessorEditor(&ownerProcessor),
      processorRef(ownerProcessor),
      rootMode_(rootMode) {
    if (const char* envRenderer = std::getenv("MANIFOLD_RENDERER")) {
        const auto envMode = runtimeRendererModeFromString(envRenderer, RuntimeRendererMode::ImGuiDirect);
        if (envMode == RuntimeRendererMode::Canvas || envMode == RuntimeRendererMode::ImGuiOverlay || envMode == RuntimeRendererMode::ImGuiReplace) {
            rootMode_ = RootMode::Canvas;
        } else {
            rootMode_ = RootMode::RuntimeNode;
        }
    } else {
        switch (processorRef.getControlServer().getCurrentUIRendererMode()) {
            case 0:
            case 1:
            case 2:
                rootMode_ = RootMode::Canvas;
                break;
            case 3:
            default:
                rootMode_ = RootMode::RuntimeNode;
                break;
        }
    }

    exportPluginUi_ = processorRef.hasExportPluginConfig();

    int initialWidth = exportPluginUi_ ? processorRef.getExportEditorWidth() : 1000;
    int initialHeight = exportPluginUi_ ? processorRef.getExportEditorHeight() : 640;
    if (parseProfileWindowSizeEnv(initialWidth, initialHeight)) {
        std::fprintf(stderr,
                     "BehaviorCoreEditor: using MANIFOLD_PROFILE_WINDOW_SIZE=%dx%d\n",
                     initialWidth,
                     initialHeight);
    }

    setWantsKeyboardFocus(true);
    setSize(initialWidth, initialHeight);

    if (rootMode_ == RootMode::RuntimeNode) {
        rootRuntime_ = std::make_unique<RuntimeNode>("root");
        rootRuntime_->setBounds(0, 0, getWidth(), getHeight());
        addChildComponent(rootCanvas);
        rootCanvas.setVisible(false);
        runtimeRendererMode_ = RuntimeRendererMode::ImGuiDirect;
    } else {
        addAndMakeVisible(rootCanvas);
    }
    if (!exportPluginUi_) {
        addAndMakeVisible(mainScriptEditorHost);
        addAndMakeVisible(scriptListHost);
        addAndMakeVisible(hierarchyHost);
        addAndMakeVisible(inspectorHost);
        addAndMakeVisible(scriptInspectorHost);
        addAndMakeVisible(perfOverlayHost);
        addAndMakeVisible(runtimeNodeDebugHost);
    }
    addChildComponent(directHost_);
    runtimeNodeDebugHost.setOnExitRequested([this]() {
        setRuntimeRendererMode(RuntimeRendererMode::Canvas);
    });

    perfOverlayHost.onTabChanged = [this](const std::string& tabId) {
        luaEngine.withLuaState([tabId](sol::state& L) {
            auto shell = L["_G"]["shell"];
            if (!shell.valid()) {
                return;
            }
            sol::protected_function fn = shell["setPerfOverlayActiveTab"];
            if (fn.valid()) {
                fn(shell, tabId);
            }
        });
    };
    perfOverlayHost.onClosed = [this]() {
        luaEngine.withLuaState([](sol::state& L) {
            auto shell = L["_G"]["shell"];
            if (!shell.valid()) {
                return;
            }
            sol::protected_function fn = shell["setPerfOverlayVisible"];
            if (fn.valid()) {
                fn(shell, false);
            }
        });
    };
    directHost_.setCopyIdCallback([this](const std::string& nodeId) {
        // Copy to clipboard via JUCE
        juce::SystemClipboard::copyTextToClipboard(juce::String(nodeId));
        std::fprintf(stderr, "[CopyID DEBUG] Callback fired for: %s\n", nodeId.c_str());
        
        // Also print to Lua console
        luaEngine.withLuaState([&](sol::state& L) {
            sol::object shellObj = L["_G"]["shell"];
            if (!shellObj.valid() || !shellObj.is<sol::table>()) {
                std::fprintf(stderr, "[CopyID DEBUG] shell not found in Lua\n");
                return;
            }
            sol::table shell = shellObj.as<sol::table>();
            sol::protected_function fn = shell["appendConsoleLine"];
            if (fn.valid()) {
                std::fprintf(stderr, "[CopyID DEBUG] Calling appendConsoleLine\n");
                auto result = fn(shell, "[CopyID] copied: " + nodeId, 0xff86efac);
                if (!result.valid()) {
                    sol::error err = result;
                    std::fprintf(stderr, "[CopyID DEBUG] Lua error: %s\n", err.what());
                }
            } else {
                std::fprintf(stderr, "[CopyID DEBUG] appendConsoleLine not found\n");
            }
        });
    });

    directHost_.setGlobalKeyHandler([this](const juce::KeyPress& key) {
        bool handled = false;
        luaEngine.withLuaState([&](sol::state& L) {
            sol::object shellObj = L["_G"]["shell"];
            if (!shellObj.valid() || !shellObj.is<sol::table>()) {
                return;
            }

            sol::table shell = shellObj.as<sol::table>();
            sol::protected_function fn = shell["handleGlobalDevHotkeys"];
            if (!fn.valid()) {
                return;
            }

            const auto mods = key.getModifiers();
            auto result = fn(shell,
                             key.getKeyCode(),
                             static_cast<int>(key.getTextCharacter()),
                             mods.isShiftDown(),
                             mods.isCtrlDown() || mods.isCommandDown(),
                             mods.isAltDown());
            if (!result.valid()) {
                sol::error err = result;
                std::fprintf(stderr,
                             "BehaviorCoreEditor: shell.handleGlobalDevHotkeys failed: %s\n",
                             err.what());
                return;
            }

            if (result.get_type() == sol::type::boolean) {
                handled = result.get<bool>();
            } else {
                handled = true;
            }
        });

        if (!handled && exportPluginUi_) {
            const auto ch = static_cast<int>(key.getTextCharacter());
            if (ch == '`' || ch == '~') {
                const float current = processorRef.getParamByPath("/plugin/ui/devVisible");
                processorRef.setParamByPath("/plugin/ui/devVisible", current > 0.5f ? 0.0f : 1.0f);
                handled = true;
            }
        }

        return handled;
    });
    perfOverlayHost.onBoundsChanged = [this](const juce::Rectangle<int>& bounds) {
        luaEngine.withLuaState([bounds](sol::state& L) {
            auto shell = L["_G"]["shell"];
            if (!shell.valid()) {
                return;
            }
            sol::protected_function fn = shell["setPerfOverlayBounds"];
            if (fn.valid()) {
                fn(shell, bounds.getX(), bounds.getY(), bounds.getWidth(), bounds.getHeight());
            }
        });
    };
    if (!exportPluginUi_) {
        mainScriptEditorHost.setVisible(false);
        scriptListHost.setVisible(false);
        hierarchyHost.setVisible(false);
        inspectorHost.setVisible(false);
        scriptInspectorHost.setVisible(false);
        perfOverlayHost.setVisible(false);
        runtimeNodeDebugHost.setVisible(false);
        mainScriptEditorHost.toFront(false);
        scriptListHost.toFront(false);
        hierarchyHost.toFront(false);
        inspectorHost.toFront(false);
        scriptInspectorHost.toFront(false);
        perfOverlayHost.toFront(false);
        runtimeNodeDebugHost.toFront(false);
    }
    directHostNeedsInitialFocus_ = (runtimeRendererMode_ == RuntimeRendererMode::ImGuiDirect);

    LuaRuntimeNodeBindings::setAllowAutomaticLegacyRetainedReplay(rootMode_ != RootMode::RuntimeNode);
    if (rootMode_ == RootMode::RuntimeNode) {
        luaEngine.initialise(&processorRef, rootRuntime_.get());
    } else {
        luaEngine.initialise(&processorRef, &rootCanvas);
    }
    runtimeNodeDebugHost.setRootNode(getActiveRootRuntimeNode());
    processorRef.getControlServer().setFrameTimings(&luaEngine.frameTimings);
    processorRef.getControlServer().setLuaEngine(&luaEngine);

    if (const char* envRenderer = std::getenv("MANIFOLD_RENDERER")) {
        runtimeRendererMode_ = runtimeRendererModeFromString(envRenderer,
                                                             rootMode_ == RootMode::RuntimeNode
                                                                 ? RuntimeRendererMode::ImGuiDirect
                                                                 : RuntimeRendererMode::Canvas);
        if (runtimeRendererMode_ != RuntimeRendererMode::Canvas) {
            std::fprintf(stderr,
                         "BehaviorCoreEditor: renderer enabled via MANIFOLD_RENDERER=%s (%s)\n",
                         envRenderer,
                         runtimeRendererModeToString(runtimeRendererMode_));
        }
    } else if (const char* envMode = std::getenv("MANIFOLD_RUNTIME_NODE_DEBUG")) {
        runtimeRendererMode_ = runtimeRendererModeFromString(envMode, RuntimeRendererMode::ImGuiOverlay);
        if (runtimeRendererMode_ != RuntimeRendererMode::Canvas) {
            std::fprintf(stderr,
                         "BehaviorCoreEditor: RuntimeNode renderer enabled via MANIFOLD_RUNTIME_NODE_DEBUG=%s (%s)\n",
                         envMode,
                         runtimeRendererModeToString(runtimeRendererMode_));
        }
    }
    if (rootMode_ == RootMode::RuntimeNode
        && (runtimeRendererMode_ == RuntimeRendererMode::Canvas
            || runtimeRendererMode_ == RuntimeRendererMode::ImGuiOverlay)) {
        runtimeRendererMode_ = RuntimeRendererMode::ImGuiDirect;
    }
    processorRef.getControlServer().setCurrentUIRendererMode(static_cast<int>(runtimeRendererMode_));

    auto& settings = Settings::getInstance();
    const auto settingsScript = settings.getDefaultUiScript();
    if (settingsScript.isEmpty()) {
        std::fprintf(stderr,
                     "BehaviorCoreEditor: settings.defaultUiScript is empty; refusing to fall back\n");
        showError("Settings error:\ndefaultUiScript is empty.\n"
                  "Configure it in: " + settings.getConfigPath().toStdString());
    } else {
        const juce::File scriptFile(settingsScript);
        if (!scriptFile.existsAsFile()) {
            std::fprintf(stderr,
                         "BehaviorCoreEditor: configured UI script does not exist: %s\n"
                         "  -> Configure defaultUiScript in .manifold.settings.json in the repo root.\n",
                         settingsScript.toRawUTF8());
            showError("Settings error:\nconfigured defaultUiScript does not exist:\n" +
                      settingsScript.toStdString() +
                      "\n\nConfigure in .manifold.settings.json in the repo root.");
        } else {
            usingLuaUi = luaEngine.loadScript(scriptFile);
            if (usingLuaUi) {
                std::fprintf(stderr, "BehaviorCoreEditor: Using Lua UI from %s\n",
                             scriptFile.getFullPathName().toRawUTF8());
            } else {
                std::fprintf(stderr, "BehaviorCoreEditor: Lua script failed: %s\n",
                             luaEngine.getLastError().c_str());
                showError("Lua UI failed to load:\n" + luaEngine.getLastError());
            }
        }
    }

    processorRef.captureEditorOpenSnapshot();
    startTimerHz(exportPluginUi_ ? 20 : 30);
    resized();
}

BehaviorCoreEditor::~BehaviorCoreEditor() {
    stopTimer();
    // Shut down the direct host first (detaches GL context, clears live tree pointer)
    directHost_.shutdown();
    // Then the old debug host
    runtimeNodeDebugHost.setRootNode(nullptr);
    runtimeNodeDebugHost.setVisible(false);
    removeChildComponent(&runtimeNodeDebugHost);
    removeChildComponent(&directHost_);
    processorRef.getControlServer().setLuaEngine(nullptr);
    processorRef.getControlServer().setFrameTimings(nullptr);
}

void BehaviorCoreEditor::applyDeferredVisibilityChanges() {
    if (deferredVisibilityChanges.empty()) return;

    const auto applyStart = PerfClock::now();
    for (const auto& change : deferredVisibilityChanges) {
        if (change.host == nullptr) {
            continue;
        }

        if (change.visible) {
            if (change.host->getBounds() != change.bounds) {
                change.host->setBounds(change.bounds);
            }
            if (!change.host->isVisible()) {
                change.host->setVisible(true);
            }
            change.host->toFront(false);
            if (change.host == &perfOverlayHost) {
                perfOverlayHost.grabKeyboardFocus();
            }
        } else {
            const bool keepGlHostVisible = change.host == &perfOverlayHost
                || change.host == &mainScriptEditorHost
                || change.host == &scriptListHost
                || change.host == &hierarchyHost
                || change.host == &inspectorHost
                || change.host == &scriptInspectorHost;

            if (keepGlHostVisible) {
                if (!change.host->isVisible()) {
                    change.host->setVisible(true);
                }
                if (change.host->getBounds() != change.bounds) {
                    change.host->setBounds(change.bounds);
                }
            } else {
                if (change.host->isVisible()) {
                    change.host->setVisible(false);
                }
                if (change.host->getBounds() != change.bounds) {
                    change.host->setBounds(change.bounds);
                }
            }
        }
    }
    if (directHost_.isVisible()) {
        directHost_.toBack();
    }
    if (mainScriptEditorHost.isVisible()) {
        mainScriptEditorHost.toFront(false);
    }
    if (scriptListHost.isVisible()) {
        scriptListHost.toFront(false);
    }
    if (hierarchyHost.isVisible()) {
        hierarchyHost.toFront(false);
    }
    if (inspectorHost.isVisible()) {
        inspectorHost.toFront(false);
    }
    if (scriptInspectorHost.isVisible()) {
        scriptInspectorHost.toFront(false);
    }
    if (runtimeNodeDebugHost.isVisible()) {
        runtimeNodeDebugHost.toFront(false);
    }
    if (perfOverlayHost.isVisible()) {
        perfOverlayHost.toFront(false);
        perfOverlayHost.grabKeyboardFocus();
    }

    auto count = deferredVisibilityChanges.size();
    deferredVisibilityChanges.clear();
    std::string extra = std::to_string(count) + " hosts";
    logEditorPerf("applyDeferredVisibilityChanges", applyStart, extra.c_str());
}

void BehaviorCoreEditor::queueHostVisibilityChange(juce::Component& host, bool visible,
                                                 const juce::Rectangle<int>& bounds) {
    const auto targetBounds = visible ? bounds : juce::Rectangle<int>(0, 0, 0, 0);
    if (host.isVisible() != visible || host.getBounds() != targetBounds) {
        deferredVisibilityChanges.push_back({&host, visible, targetBounds});
    }
}

void BehaviorCoreEditor::timerCallback() {
    // Prevent back-to-back timer fires when callback overruns the period.
    // Without this, mouse events starve because the message thread never idles.
    stopTimer();

    using Clock = std::chrono::steady_clock;
    static auto lastCall = Clock::now();
    const auto now = Clock::now();
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - lastCall).count();
    lastCall = now;

    static int logCount = 0;
    const auto timerStart = Clock::now();
    
    // Apply any deferred visibility changes first (outside of GUI event handling)
    applyDeferredVisibilityChanges();
    Canvas::finishPaintProfilingFrame();

    auto pendingPath = processorRef.getAndClearPendingUISwitch();
    if (!pendingPath.empty()) {
        juce::File newScript(pendingPath);
        if (newScript.existsAsFile()) {
            std::fprintf(stderr, "BehaviorCoreEditor: Switching UI to %s\n",
                         pendingPath.c_str());
            luaEngine.switchScript(newScript);
        } else {
            std::fprintf(stderr,
                         "BehaviorCoreEditor: UI switch failed - file not found: %s\n",
                         pendingPath.c_str());
        }
    }

    auto pendingRendererMode = processorRef.getAndClearPendingUIRendererMode();
    if (!pendingRendererMode.empty()) {
        setRuntimeRendererMode(runtimeRendererModeFromString(pendingRendererMode, runtimeRendererMode_), true);
    }

    processorRef.processLinkPendingRequests();
    processorRef.drainPendingSlotDestroy();

    if (usingLuaUi) {
        luaEngine.notifyUpdate();
        int64_t animUs = 0;
        int64_t renderDispatchUs = 0;
        if (runtimeRendererMode_ != RuntimeRendererMode::Canvas) {
            const auto tAnimStart = Clock::now();
            const double deltaSeconds = static_cast<double>(elapsed) / 1000000.0;
            luaEngine.withLuaState([deltaSeconds](sol::state& L) {
                sol::object shellObj = L["_G"]["shell"];
                if (!shellObj.valid() || !shellObj.is<sol::table>()) {
                    return;
                }
                auto shellTable = shellObj.as<sol::table>();
                invokeShellMethodWithNumber(shellTable, "tickRetainedAnimations", deltaSeconds);
                invokeShellMethod(shellTable, "flushDeferredRefreshes");
            });
            const auto tAnimEnd = Clock::now();
            if (runtimeRendererMode_ == RuntimeRendererMode::ImGuiDirect) {
                // Sync debug outline and copyid mode state from Lua to DirectHost
                directHost_.setDebugOutlinesEnabled(luaEngine.areDebugOutlinesEnabled());
                directHost_.setCopyIdModeEnabled(luaEngine.isCopyIdModeEnabled());
                directHost_.renderNow();
            } else {
                runtimeNodeDebugHost.refreshSnapshotNow();
                runtimeNodeDebugHost.repaint();
            }
            const auto tRenderEnd = Clock::now();
            animUs = std::chrono::duration_cast<std::chrono::microseconds>(tAnimEnd - tAnimStart).count();
            renderDispatchUs = std::chrono::duration_cast<std::chrono::microseconds>(tRenderEnd - tAnimEnd).count();
            static int timerLogCount = 0;
            if (++timerLogCount % 60 == 0) {
                std::fprintf(stderr, "[TimerBreak] anim=%lldus render=%lldus\n",
                             (long long)animUs,
                             (long long)renderDispatchUs);
            }
        }
        const auto tSyncStart = Clock::now();
        if (!exportPluginUi_) {
            syncImGuiHostsFromLuaShell();
        }
        const auto tSyncEnd = Clock::now();
        if (rootMode_ == RootMode::Canvas) {
            rootCanvas.requestTrackedRepaint();
        }
        updateRuntimeRendererPresentation();
        const auto tPresentEnd = Clock::now();
        {
            static int timerLogCount2 = 0;
            if (++timerLogCount2 % 60 == 0) {
                auto us = [](auto a, auto b) { return std::chrono::duration_cast<std::chrono::microseconds>(b - a).count(); };
                std::fprintf(stderr, "[TimerBreak2] sync=%lldus present=%lldus\n",
                             (long long)us(tSyncStart, tSyncEnd),
                             (long long)us(tSyncEnd, tPresentEnd));
            }
        }

        const int64_t totalUs = std::chrono::duration_cast<std::chrono::microseconds>(
            Clock::now() - timerStart).count();
        const int64_t pushStateUs =
            luaEngine.frameTimings.pushState.currentUs.load(std::memory_order_relaxed);
        const int64_t eventListenersUs =
            luaEngine.frameTimings.eventListeners.currentUs.load(std::memory_order_relaxed);
        const int64_t uiUpdateUs =
            luaEngine.frameTimings.uiUpdate.currentUs.load(std::memory_order_relaxed);
        const int64_t paintUs = Canvas::getLastFrameAccumulatedPaintUs();
        const int64_t syncHostsUs = std::chrono::duration_cast<std::chrono::microseconds>(tSyncEnd - tSyncStart).count();
        const int64_t presentUs = std::chrono::duration_cast<std::chrono::microseconds>(tPresentEnd - tSyncEnd).count();
        const int64_t overBudgetUs = std::max<int64_t>(0, totalUs - 33333);
        const int64_t canvasRepaintLeadUs = (rootMode_ == RootMode::Canvas)
            ? rootCanvas.getLastTrackedRepaintLeadUs()
            : 0;

        const auto imguiStats = [&]() {
            if (runtimeRendererMode_ == RuntimeRendererMode::ImGuiDirect || exportPluginUi_) {
                return directHost_.getStatsSnapshot();
            }
            const auto mainImguiStats = mainScriptEditorHost.getStatsSnapshot();
            return ImGuiDirectHost::StatsSnapshot{
                mainImguiStats.contextReady,
                mainImguiStats.testWindowVisible,
                mainImguiStats.wantCaptureMouse,
                mainImguiStats.wantCaptureKeyboard,
                mainImguiStats.documentLoaded,
                mainImguiStats.documentDirty,
                mainImguiStats.frameCount,
                mainImguiStats.lastRenderUs,
                mainImguiStats.lastVertexCount,
                mainImguiStats.lastIndexCount,
                mainImguiStats.buttonClicks,
                mainImguiStats.documentLineCount,
                0,
                0,
                0,
                0,
            };
        }();

        luaEngine.frameTimings.imguiContextReady.store(imguiStats.contextReady,
                                                       std::memory_order_relaxed);
        luaEngine.frameTimings.imguiTestWindowVisible.store(imguiStats.testWindowVisible,
                                                            std::memory_order_relaxed);
        luaEngine.frameTimings.imguiWantCaptureMouse.store(imguiStats.wantCaptureMouse,
                                                           std::memory_order_relaxed);
        luaEngine.frameTimings.imguiWantCaptureKeyboard.store(imguiStats.wantCaptureKeyboard,
                                                              std::memory_order_relaxed);
        luaEngine.frameTimings.imguiFrameCount.store(imguiStats.frameCount,
                                                     std::memory_order_relaxed);
        luaEngine.frameTimings.imguiRenderUs.store(imguiStats.lastRenderUs,
                                                   std::memory_order_relaxed);
        luaEngine.frameTimings.imguiVertexCount.store(imguiStats.lastVertexCount,
                                                      std::memory_order_relaxed);
        luaEngine.frameTimings.imguiIndexCount.store(imguiStats.lastIndexCount,
                                                     std::memory_order_relaxed);
        luaEngine.frameTimings.imguiButtonClicks.store(imguiStats.buttonClicks,
                                                       std::memory_order_relaxed);
        luaEngine.frameTimings.gpuFontAtlasBytes.store(imguiStats.fontAtlasBytes,
                                                       std::memory_order_relaxed);
        luaEngine.frameTimings.gpuSurfaceColorBytes.store(imguiStats.surfaceColorBytes,
                                                          std::memory_order_relaxed);
        luaEngine.frameTimings.gpuSurfaceDepthBytes.store(imguiStats.surfaceDepthBytes,
                                                          std::memory_order_relaxed);
        luaEngine.frameTimings.gpuTotalBytes.store(imguiStats.totalGpuBytes,
                                                   std::memory_order_relaxed);
        luaEngine.frameTimings.renderSnapshotBytes.store(imguiStats.renderSnapshotBytes,
                                                         std::memory_order_relaxed);
        luaEngine.frameTimings.renderSnapshotNodeCount.store(imguiStats.renderSnapshotNodeCount,
                                                             std::memory_order_relaxed);
        luaEngine.frameTimings.customSurfaceStateBytes.store(imguiStats.customSurfaceStateBytes,
                                                             std::memory_order_relaxed);
        luaEngine.frameTimings.imguiWindowCount.store(imguiStats.imguiWindowCount,
                                                      std::memory_order_relaxed);
        luaEngine.frameTimings.imguiTableCount.store(imguiStats.imguiTableCount,
                                                     std::memory_order_relaxed);
        luaEngine.frameTimings.imguiTabBarCount.store(imguiStats.imguiTabBarCount,
                                                      std::memory_order_relaxed);
        luaEngine.frameTimings.imguiViewportCount.store(imguiStats.imguiViewportCount,
                                                        std::memory_order_relaxed);
        luaEngine.frameTimings.imguiFontCount.store(imguiStats.imguiFontCount,
                                                    std::memory_order_relaxed);
        luaEngine.frameTimings.imguiWindowStateBytes.store(imguiStats.imguiWindowStateBytes,
                                                           std::memory_order_relaxed);
        luaEngine.frameTimings.imguiDrawBufferBytes.store(imguiStats.imguiDrawBufferBytes,
                                                          std::memory_order_relaxed);
        luaEngine.frameTimings.imguiInternalStateBytes.store(imguiStats.imguiInternalStateBytes,
                                                             std::memory_order_relaxed);
        luaEngine.frameTimings.imguiDocumentLoaded.store(imguiStats.documentLoaded,
                                                         std::memory_order_relaxed);
        luaEngine.frameTimings.imguiDocumentDirty.store(imguiStats.documentDirty,
                                                        std::memory_order_relaxed);
        luaEngine.frameTimings.imguiDocumentLineCount.store(imguiStats.documentLineCount,
                                                            std::memory_order_relaxed);
        luaEngine.frameTimings.totalPaintAccumulatedUs.store(paintUs,
                                                             std::memory_order_relaxed);

        // CPU and memory tracking
        {
            const auto cpuNow = Clock::now();
            if (lastCpuCheck_.time_since_epoch().count() == 0) {
                lastCpuCheck_ = cpuNow;
                lastCpuTime_ = std::chrono::microseconds(totalUs);
            } else {
                const auto wallTime = std::chrono::duration_cast<std::chrono::microseconds>(cpuNow - lastCpuCheck_).count();
                const auto cpuTime = totalUs;
                if (wallTime > 0) {
                    float cpuPercent = static_cast<float>(cpuTime) / static_cast<float>(wallTime) * 100.0f;
                    cpuPercent = std::min(100.0f, std::max(0.0f, cpuPercent));
                    luaEngine.frameTimings.cpuPercent.store(cpuPercent, std::memory_order_relaxed);
                }
                lastCpuCheck_ = cpuNow;
            }

            if (perfOverlayHost.isVisible() || runtimeNodeDebugHost.isVisible()) {
                const auto mem = readProcessMemorySnapshot();
                luaEngine.frameTimings.processPssBytes.store(mem.pssBytes, std::memory_order_relaxed);
                luaEngine.frameTimings.privateDirtyBytes.store(mem.privateDirtyBytes, std::memory_order_relaxed);

            if (auto* root = getActiveRootRuntimeNode()) {
                const auto runtimeStats = root->estimateMemoryUsage();
                luaEngine.frameTimings.runtimeNodeCount.store(static_cast<int64_t>(runtimeStats.nodeCount), std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeNodeBytes.store(runtimeStats.nodeBytes + runtimeStats.stringBytes + runtimeStats.vectorBytes,
                                                              std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeCallbackCount.store(static_cast<int64_t>(runtimeStats.callbackCount), std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeUserDataEntries.store(static_cast<int64_t>(runtimeStats.userDataEntries), std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeUserDataBytes.store(runtimeStats.userDataBytes, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeCustomPayloadBytes.store(runtimeStats.customPayloadBytes, std::memory_order_relaxed);
                luaEngine.frameTimings.displayListCount.store(static_cast<int64_t>(runtimeStats.compiledDisplayListCount), std::memory_order_relaxed);
                luaEngine.frameTimings.displayListCommandCount.store(static_cast<int64_t>(runtimeStats.compiledDisplayListCommands), std::memory_order_relaxed);
                luaEngine.frameTimings.displayListBytes.store(runtimeStats.compiledDisplayListBytes, std::memory_order_relaxed);
            } else {
                luaEngine.frameTimings.runtimeNodeCount.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeNodeBytes.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeCallbackCount.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeUserDataEntries.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeUserDataBytes.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.runtimeCustomPayloadBytes.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.displayListCount.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.displayListCommandCount.store(0, std::memory_order_relaxed);
                luaEngine.frameTimings.displayListBytes.store(0, std::memory_order_relaxed);
            }

            const auto currentScriptFile = luaEngine.getCurrentScriptFile();
            luaEngine.frameTimings.scriptSourceBytes.store(currentScriptFile.existsAsFile()
                                                               ? static_cast<int64_t>(currentScriptFile.getSize())
                                                               : 0,
                                                           std::memory_order_relaxed);

            const auto luaStats = luaEngine.getMemoryStats();
            luaEngine.frameTimings.luaGlobalCount.store(luaStats.globalCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaRegistryEntryCount.store(luaStats.registryEntryCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaPackageLoadedCount.store(luaStats.packageLoadedCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaOscPathCount.store(luaStats.oscPathCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaOscCallbackCount.store(luaStats.oscCallbackCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaOscQueryHandlerCount.store(luaStats.oscQueryHandlerCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaEventListenerCount.store(luaStats.eventListenerCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaManagedDspSlotCount.store(luaStats.managedDspSlotCount, std::memory_order_relaxed);
            luaEngine.frameTimings.luaOverlayCacheCount.store(luaStats.overlayCacheCount, std::memory_order_relaxed);

            const auto endpointStats = processorRef.getEndpointRegistry().getStats();
            luaEngine.frameTimings.endpointTotalCount.store(endpointStats.totalCount, std::memory_order_relaxed);
            luaEngine.frameTimings.endpointCustomCount.store(endpointStats.customCount, std::memory_order_relaxed);
            luaEngine.frameTimings.endpointPathBytes.store(endpointStats.pathBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.endpointDescriptionBytes.store(endpointStats.descriptionBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.dspHostCount.store(1 + static_cast<int64_t>(processorRef.getManagedDspHostCount()), std::memory_order_relaxed);
            luaEngine.frameTimings.dspScriptSourceBytes.store(static_cast<int64_t>(processorRef.getPrimaryDspScriptSizeBytes()), std::memory_order_relaxed);

            const auto alloc = readGlibcAllocatorSnapshot();
            luaEngine.frameTimings.glibcHeapUsedBytes.store(alloc.heapUsedBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.glibcArenaBytes.store(alloc.arenaBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.glibcMmapBytes.store(alloc.mmapBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.glibcFreeHeldBytes.store(alloc.freeHeldBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.glibcReleasableBytes.store(alloc.releasableBytes, std::memory_order_relaxed);
            luaEngine.frameTimings.glibcArenaCount.store(alloc.arenaCount, std::memory_order_relaxed);

            int64_t luaHeapBytes = 0;
            luaEngine.withLuaState([&luaHeapBytes](sol::state& lua) {
                sol::protected_function collectgarbage = lua["collectgarbage"];
                if (!collectgarbage.valid()) {
                    return;
                }
                auto result = collectgarbage("count");
                if (result.valid() && result.get_type() == sol::type::number) {
                    const double kb = result.get<double>();
                    luaHeapBytes = static_cast<int64_t>(kb * 1024.0);
                }
            });
            luaEngine.frameTimings.luaHeapBytes.store(luaHeapBytes, std::memory_order_relaxed);

            const auto pluginBaselinePss = processorRef.getPluginBaselinePssBytes();
            const auto pluginBaselinePriv = processorRef.getPluginBaselinePrivateDirtyBytes();
            const auto pluginBaselineHeap = processorRef.getPluginBaselineHeapBytes();
            const auto pluginBaselineArena = processorRef.getPluginBaselineArenaBytes();
            luaEngine.frameTimings.pluginDeltaPssBytes.store(mem.pssBytes - pluginBaselinePss, std::memory_order_relaxed);
            luaEngine.frameTimings.pluginDeltaPrivateDirtyBytes.store(mem.privateDirtyBytes - pluginBaselinePriv, std::memory_order_relaxed);
            luaEngine.frameTimings.pluginDeltaHeapBytes.store(alloc.heapUsedBytes - pluginBaselineHeap, std::memory_order_relaxed);
            luaEngine.frameTimings.pluginDeltaArenaBytes.store(alloc.arenaBytes - pluginBaselineArena, std::memory_order_relaxed);

            const auto editorOpenPss = processorRef.getEditorOpenPssBytes();
            const auto editorOpenPriv = processorRef.getEditorOpenPrivateDirtyBytes();
            const auto editorOpenHeap = processorRef.getEditorOpenHeapBytes();
            luaEngine.frameTimings.uiDeltaPssBytes.store(editorOpenPss > 0 ? (mem.pssBytes - editorOpenPss) : 0,
                                                         std::memory_order_relaxed);
            luaEngine.frameTimings.uiDeltaPrivateDirtyBytes.store(editorOpenPriv > 0 ? (mem.privateDirtyBytes - editorOpenPriv) : 0,
                                                                  std::memory_order_relaxed);
            luaEngine.frameTimings.uiDeltaHeapBytes.store(editorOpenHeap > 0 ? (alloc.heapUsedBytes - editorOpenHeap) : 0,
                                                          std::memory_order_relaxed);
            luaEngine.frameTimings.afterLuaInitDeltaPssBytes.store(processorRef.getAfterLuaInitDeltaPssBytes(),
                                                                   std::memory_order_relaxed);
            luaEngine.frameTimings.afterLuaInitDeltaPrivateDirtyBytes.store(processorRef.getAfterLuaInitDeltaPrivateDirtyBytes(),
                                                                            std::memory_order_relaxed);
            luaEngine.frameTimings.afterBindingsDeltaPssBytes.store(processorRef.getAfterBindingsDeltaPssBytes(),
                                                                    std::memory_order_relaxed);
            luaEngine.frameTimings.afterBindingsDeltaPrivateDirtyBytes.store(processorRef.getAfterBindingsDeltaPrivateDirtyBytes(),
                                                                             std::memory_order_relaxed);
            luaEngine.frameTimings.afterScriptLoadDeltaPssBytes.store(processorRef.getAfterScriptLoadDeltaPssBytes(),
                                                                      std::memory_order_relaxed);
            luaEngine.frameTimings.afterScriptLoadDeltaPrivateDirtyBytes.store(processorRef.getAfterScriptLoadDeltaPrivateDirtyBytes(),
                                                                               std::memory_order_relaxed);
            luaEngine.frameTimings.afterDspDeltaPssBytes.store(processorRef.getAfterDspDeltaPssBytes(),
                                                               std::memory_order_relaxed);
            luaEngine.frameTimings.afterDspDeltaPrivateDirtyBytes.store(processorRef.getAfterDspDeltaPrivateDirtyBytes(),
                                                                       std::memory_order_relaxed);
            luaEngine.frameTimings.afterUiOpenDeltaPssBytes.store(processorRef.getAfterUiOpenDeltaPssBytes(),
                                                                  std::memory_order_relaxed);
            luaEngine.frameTimings.afterUiOpenDeltaPrivateDirtyBytes.store(processorRef.getAfterUiOpenDeltaPrivateDirtyBytes(),
                                                                          std::memory_order_relaxed);
                luaEngine.frameTimings.afterUiIdleDeltaPssBytes.store(processorRef.getAfterUiIdleDeltaPssBytes(),
                                                                      std::memory_order_relaxed);
                luaEngine.frameTimings.afterUiIdleDeltaPrivateDirtyBytes.store(processorRef.getAfterUiIdleDeltaPrivateDirtyBytes(),
                                                                              std::memory_order_relaxed);
            }

            if (!uiIdleSnapshotCaptured_ && exportPluginUi_ && uiIdleSnapshotCountdown_ > 0) {
                --uiIdleSnapshotCountdown_;
                if (uiIdleSnapshotCountdown_ == 0) {
                    processorRef.captureUiIdleSnapshot();
                    uiIdleSnapshotCaptured_ = true;
                }
            }
        }

        luaEngine.frameTimings.update(totalUs, pushStateUs, eventListenersUs,
                                      uiUpdateUs, paintUs,
                                      animUs, renderDispatchUs,
                                      syncHostsUs, presentUs,
                                      overBudgetUs, canvasRepaintLeadUs);

        juce::ignoreUnused(logCount, elapsed);
    } else if (errorNode == nullptr) {
        updateRuntimeRendererPresentation();
    } else {
        runtimeNodeDebugHost.setVisible(false);
    }

    // Reschedule from now so mouse events get processed between callbacks
    startTimerHz(exportPluginUi_ ? 20 : 30);
}

void BehaviorCoreEditor::paint(juce::Graphics& g) {
    juce::ignoreUnused(processorRef);

    juce::ColourGradient bg(juce::Colour(0xff161b26), 0.0f, 0.0f,
                            juce::Colour(0xff0c1019), 0.0f, (float)getHeight(), false);
    bg.addColour(0.35, juce::Colour(0xff1e2533));
    g.setGradientFill(bg);
    g.fillAll();
}

void BehaviorCoreEditor::syncImGuiHostsFromLuaShell() {
    const auto totalStart = PerfClock::now();
    static HostLayoutTraceState mainScriptHostTrace;
    static HostLayoutTraceState scriptListHostTrace;
    static HostLayoutTraceState hierarchyHostTrace;
    static HostLayoutTraceState inspectorHostTrace;
    static HostLayoutTraceState scriptInspectorHostTrace;

    const auto mainStatsBefore = mainScriptEditorHost.getStatsSnapshot();
    const std::string rendererModeLabel = runtimeRendererModeToString(runtimeRendererMode_);
    const auto mainIdentityBefore = mainScriptEditorHost.getDocumentIdentity();
    const auto mainTextBefore = mainScriptEditorHost.getCurrentText();
    const auto mainActions = mainScriptEditorHost.consumeActionRequests();
    const auto scriptListActions = scriptListHost.consumeActionRequests();
    const auto hierarchyActions = hierarchyHost.consumeActionRequests();
    const auto inspectorActions = inspectorHost.consumeActionRequests();
    const auto scriptInspectorActions = scriptInspectorHost.consumeActionRequests();

    HostConfig mainConfig;
    ScriptListHostConfig scriptListConfig;
    HierarchyHostConfig hierarchyConfig;
    InspectorHostConfig inspectorConfig;
    InspectorHostConfig scriptInspectorConfig;
    PerfOverlayHostConfig perfOverlayConfig;

    const auto luaStateStart = PerfClock::now();
    luaEngine.withLuaState([&](sol::state& lua) {
        lua["__manifoldImguiScriptListActive"] = false;
        lua["__manifoldImguiHierarchyActive"] = false;
        lua["__manifoldImguiInspectorActive"] = false;

        sol::object shellObj = lua["shell"];
        if (!shellObj.valid() || !shellObj.is<sol::table>()) {
            return;
        }

        sol::table shell = shellObj.as<sol::table>();

        syncMainEditorBackToShell(shell, mainStatsBefore, mainIdentityBefore, mainTextBefore);
        applyMainEditorActions(shell, mainActions);

        applyScriptListActions(shell, scriptListActions);
        applyHierarchyActions(shell, hierarchyActions);

        applyInspectorActions(shell, inspectorActions);
        applyScriptInspectorActions(shell, scriptInspectorActions);

        const std::string shellMode = shell["mode"].get_or(std::string{});
        sol::object surfacesObj = shell["surfaces"];
        buildMainEditorConfig(shell, surfacesObj, mainConfig);

        const std::string leftPanelMode = shell["leftPanelMode"].get_or(std::string{});

        buildHierarchyAndInspectorConfig(lua, shell, surfacesObj, hierarchyConfig, inspectorConfig);
        buildScriptListConfig(lua, shell, surfacesObj, scriptListConfig);
        buildScriptInspectorConfig(lua, shell, surfacesObj, shellMode, leftPanelMode,
                                   scriptInspectorConfig);
        buildPerfOverlayConfig(luaEngine, lua, shell,
                               mainConfig, scriptListConfig, hierarchyConfig, inspectorConfig,
                               rendererModeLabel,
                               perfOverlayConfig);
    });
    logEditorPerf("syncImGuiHostsFromLuaShell.luaState", luaStateStart);

    const auto hostApplyStart = PerfClock::now();
    applyMainEditorHostConfig(mainScriptHostTrace, mainScriptEditorHost, mainConfig);
    queueHostVisibilityChange(mainScriptEditorHost, mainConfig.visible, mainConfig.bounds);

    applyHierarchyHostConfig(hierarchyHostTrace, hierarchyHost, hierarchyConfig);
    queueHostVisibilityChange(hierarchyHost, hierarchyConfig.visible, hierarchyConfig.bounds);

    applyScriptListHostConfig(scriptListHostTrace, scriptListHost, scriptListConfig);
    queueHostVisibilityChange(scriptListHost, scriptListConfig.visible, scriptListConfig.bounds);

    applyInspectorHostConfig(inspectorHostTrace, inspectorHost, inspectorConfig);
    queueHostVisibilityChange(inspectorHost, inspectorConfig.visible, inspectorConfig.bounds);

    applyScriptInspectorHostConfig(scriptInspectorHostTrace, scriptInspectorHost, scriptInspectorConfig);
    queueHostVisibilityChange(scriptInspectorHost, scriptInspectorConfig.visible, scriptInspectorConfig.bounds);

    applyPerfOverlayHostConfig(perfOverlayHost, perfOverlayConfig);
    queueHostVisibilityChange(perfOverlayHost, perfOverlayConfig.visible, perfOverlayConfig.bounds);

    luaEngine.frameTimings.shellMainEditorTextBytes.store(static_cast<int64_t>(mainConfig.text.size()), std::memory_order_relaxed);
    luaEngine.frameTimings.shellScriptListRowCount.store(static_cast<int64_t>(scriptListConfig.rows.size()), std::memory_order_relaxed);
    luaEngine.frameTimings.shellScriptListBytes.store(estimateScriptListRowsBytes(scriptListConfig.rows), std::memory_order_relaxed);
    luaEngine.frameTimings.shellHierarchyRowCount.store(static_cast<int64_t>(hierarchyConfig.rows.size()), std::memory_order_relaxed);
    luaEngine.frameTimings.shellHierarchyBytes.store(estimateHierarchyRowsBytes(hierarchyConfig.rows), std::memory_order_relaxed);
    luaEngine.frameTimings.shellInspectorRowCount.store(static_cast<int64_t>(inspectorConfig.rows.size()), std::memory_order_relaxed);
    luaEngine.frameTimings.shellInspectorBytes.store(estimateInspectorRowsBytes(inspectorConfig.rows, inspectorConfig.activeProperty), std::memory_order_relaxed);
    luaEngine.frameTimings.shellScriptInspectorBytes.store(estimateScriptInspectorBytes(scriptInspectorConfig.scriptData), std::memory_order_relaxed);

    logEditorPerf("syncImGuiHostsFromLuaShell.applyHosts", hostApplyStart);
    logEditorPerf("syncImGuiHostsFromLuaShell.total", totalStart);
}

void BehaviorCoreEditor::resized() {
    luaEngine.frameTimings.editorWidth.store(getWidth(), std::memory_order_relaxed);
    luaEngine.frameTimings.editorHeight.store(getHeight(), std::memory_order_relaxed);
    if (exportPluginUi_) {
        processorRef.setExportEditorSize(getWidth(), getHeight());
    }
    const auto localBounds = getBounds();
    const auto screenBounds = getScreenBounds();
    const auto scale = juce::Component::getApproximateScaleFactorForComponent(this);
    const auto* display = juce::Desktop::getInstance().getDisplays().getDisplayForRect(screenBounds);
    if (display != nullptr) {
        std::fprintf(stderr,
                     "[BehaviorCoreEditor] resized editorBounds=%d,%d %dx%d screenBounds=%d,%d %dx%d scale=%.3f displayScale=%.3f displayTotal=%d,%d %dx%d displayUser=%d,%d %dx%d\n",
                     localBounds.getX(), localBounds.getY(), localBounds.getWidth(), localBounds.getHeight(),
                     screenBounds.getX(), screenBounds.getY(), screenBounds.getWidth(), screenBounds.getHeight(),
                     static_cast<double>(scale),
                     static_cast<double>(display->scale),
                     display->totalArea.getX(), display->totalArea.getY(), display->totalArea.getWidth(), display->totalArea.getHeight(),
                     display->userArea.getX(), display->userArea.getY(), display->userArea.getWidth(), display->userArea.getHeight());
    } else {
        std::fprintf(stderr,
                     "[BehaviorCoreEditor] resized editorBounds=%d,%d %dx%d screenBounds=%d,%d %dx%d scale=%.3f displayScale=none\n",
                     localBounds.getX(), localBounds.getY(), localBounds.getWidth(), localBounds.getHeight(),
                     screenBounds.getX(), screenBounds.getY(), screenBounds.getWidth(), screenBounds.getHeight(),
                     static_cast<double>(scale));
    }
    rootCanvas.setBounds(getLocalBounds());
    if (rootRuntime_ != nullptr) {
        rootRuntime_->setBounds(0, 0, getWidth(), getHeight());
    }
    updateRuntimeRendererPresentation();

    if (usingLuaUi) {
        luaEngine.notifyResized(getWidth(), getHeight());
        if (runtimeRendererMode_ != RuntimeRendererMode::Canvas) {
            luaEngine.withLuaState([](sol::state& L) {
                sol::object shellObj = L["_G"]["shell"];
                if (!shellObj.valid() || !shellObj.is<sol::table>()) {
                    return;
                }
                auto shellTable = shellObj.as<sol::table>();
                invokeShellMethod(shellTable, "flushDeferredRefreshes");
            });
            runtimeNodeDebugHost.setRootNode(getActiveRootRuntimeNode());
        }
        if (!exportPluginUi_) {
            syncImGuiHostsFromLuaShell();
        }
    } else if (errorNode != nullptr) {
        errorNode->setBounds(rootCanvas.getLocalBounds());
        mainScriptEditorHost.setBounds(0, 0, 0, 0);
        scriptListHost.setBounds(0, 0, 0, 0);
        hierarchyHost.setBounds(0, 0, 0, 0);
        inspectorHost.setBounds(0, 0, 0, 0);
        scriptInspectorHost.setBounds(0, 0, 0, 0);
        runtimeNodeDebugHost.setBounds(0, 0, 0, 0);
    }
}

bool BehaviorCoreEditor::keyPressed(const juce::KeyPress& key) {
    if (exportPluginUi_) {
        const auto ch = static_cast<int>(key.getTextCharacter());
        if (ch == '`' || ch == '~') {
            const float current = processorRef.getParamByPath("/plugin/ui/devVisible");
            processorRef.setParamByPath("/plugin/ui/devVisible", current > 0.5f ? 0.0f : 1.0f);
            return true;
        }
    }
    return juce::AudioProcessorEditor::keyPressed(key);
}

void BehaviorCoreEditor::showError(const std::string& message) {
    errorMessage = message;
    if (rootRuntime_ != nullptr) {
        rootRuntime_->clearChildren();
    }
    rootCanvas.clearChildren();
    rootCanvas.setBounds(getLocalBounds());
    rootCanvas.setVisible(true);
    rootCanvas.toFront(false);

    errorNode = rootCanvas.addChild("error");
    errorNode->onDraw = [this](Canvas& c, juce::Graphics& g) {
        auto b = c.getLocalBounds().reduced(40);

        g.setColour(juce::Colour(0xff1a0000));
        g.fillRoundedRectangle(b.toFloat(), 12.0f);
        g.setColour(juce::Colour(0xff6b2020));
        g.drawRoundedRectangle(b.toFloat(), 12.0f, 1.5f);

        auto inner = b.reduced(24);

        g.setColour(juce::Colour(0xffef4444));
        g.setFont(20.0f);
        g.drawText("Lua UI Error", inner.removeFromTop(32), juce::Justification::centredLeft);

        inner.removeFromTop(12);
        g.setColour(juce::Colour(0xffcbd5e1));
        g.setFont(13.0f);
        g.drawMultiLineText(juce::String(errorMessage), inner.getX(), inner.getY() + 14,
                            inner.getWidth());
    };
}

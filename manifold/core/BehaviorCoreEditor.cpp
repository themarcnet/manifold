#include "BehaviorCoreEditor.h"
#include "BehaviorCoreProcessor.h"
#include "../primitives/core/Settings.h"
#include "../primitives/ui/Canvas.h"

#include <sol/sol.hpp>

#include <chrono>
#include <cstdio>

namespace {

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

void buildMainScriptEditorConfig(sol::state& lua, sol::table& shell,
                               sol::object surfacesObj,
                               HostConfig& mainConfig) {
    readSurfaceDescriptor(surfacesObj, "mainScriptEditor", mainConfig.visible, mainConfig.bounds);
    if (!mainConfig.visible || mainConfig.bounds.getWidth() <= 0 || mainConfig.bounds.getHeight() <= 0) {
        return;
    }

    sol::object scriptEditorObj = shell["scriptEditor"];
    if (!scriptEditorObj.valid() || !scriptEditorObj.is<sol::table>()) {
        return;
    }

    sol::table scriptEditor = scriptEditorObj.as<sol::table>();
    const std::string path = scriptEditor["path"].get_or(std::string{});
    if (path.empty()) {
        return;
    }

    mainConfig.file = juce::File(path);
    mainConfig.text = scriptEditor["text"].get_or(std::string{});
    mainConfig.syncToken = scriptEditor["syncToken"].get_or(int64_t{0});
    mainConfig.readOnly = false;
}

void buildHierarchyAndInspectorConfig(sol::state& lua, sol::table& shell,
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
        if (inspectorRowsObj.valid() && inspectorRowsObj.is<sol::table>()) {
            sol::table inspectorRows = inspectorRowsObj.as<sol::table>();
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
            }

            const auto rowCount = inspectorRows.size();
            inspectorConfig.rows.reserve(rowCount);
            for (std::size_t i = 1; i <= rowCount; ++i) {
                sol::object rowObj = inspectorRows[i];
                if (!rowObj.valid() || !rowObj.is<sol::table>()) {
                    continue;
                }
                sol::table row = rowObj.as<sol::table>();
                ImGuiInspectorHost::InspectorRow hostRow;
                hostRow.rowIndex = static_cast<int>(i - 1);
                hostRow.key = row["key"].get_or(std::string{});
                hostRow.value = row["value"].get_or(std::string{});
                hostRow.section = row["section"].get_or(false);
                hostRow.interactive = row["interactive"].get_or(false);
                hostRow.selected = (activePath == hostRow.key);
                inspectorConfig.rows.push_back(std::move(hostRow));
            }
        }
    }
}

void buildScriptListConfig(sol::state& lua, sol::table& shell,
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
            hostRow.path = row["path"].get_or(std::string{});
            hostRow.kind = row["kind"].get_or(std::string{});
            hostRow.name = row["name"].get_or(std::string{});
            hostRow. ownership = row["ownership"].get_or(std::string{});
            hostRow.selected = (hostRow.path == selectedPath);
            scriptListConfig.rows.push_back(std::move(hostRow));
        }
    }
}

void buildScriptInspectorConfig(sol::state& lua, sol::table& shell,
                               sol::object surfacesObj,
                               InspectorHostConfig& scriptInspectorConfig) {
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
}

void buildPerfOverlayConfig(sol::state& lua, sol::table& shell,
                           PerfOverlayHostConfig& perfOverlayConfig) {
    sol::object perfSurfacesObj = shell["surfaces"];
    if (!perfSurfacesObj.valid() || !perfSurfacesObj.is<sol::table>()) {
        return;
    }
    sol::table surfaces = perfSurfacesObj.as<sol::table>();
    sol::object perfSurfaceObj = surfaces["perfOverlay"];
    if (!perfSurfaceObj.valid() || !perfSurfaceObj.is<sol::table>()) {
        return;
    }
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

    sol::object perfOverlayObj = shell["perfOverlay"];
    if (perfOverlayObj.valid() && perfOverlayObj.is<sol::table>()) {
        sol::table perfOverlay = perfOverlayObj.as<sol::table>();
        perfOverlayConfig.snapshot.activeTab = perfOverlay["activeTab"].get_or(std::string{"frame"});
    }
}

} // namespace

BehaviorCoreEditor::BehaviorCoreEditor(BehaviorCoreProcessor& ownerProcessor)
    : juce::AudioProcessorEditor(&ownerProcessor), processorRef(ownerProcessor) {
    setSize(1000, 640);

    addAndMakeVisible(rootCanvas);
    luaEngine.initialise(&processorRef, &rootCanvas);
    processorRef.getControlServer().setFrameTimings(&luaEngine.frameTimings);
    processorRef.getControlServer().setLuaEngine(&luaEngine);

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

    startTimerHz(30);
    resized();
}

BehaviorCoreEditor::~BehaviorCoreEditor() {
    stopTimer();
    processorRef.getControlServer().setLuaEngine(nullptr);
    processorRef.getControlServer().setFrameTimings(nullptr);
}

void BehaviorCoreEditor::timerCallback() {
    using Clock = std::chrono::steady_clock;
    static auto lastCall = Clock::now();
    const auto now = Clock::now();
    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(now - lastCall).count();
    lastCall = now;

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

    processorRef.processLinkPendingRequests();
    processorRef.drainPendingSlotDestroy();

    if (usingLuaUi) {
        luaEngine.notifyUpdate();
        rootCanvas.repaint();
        syncImGuiHostsFromLuaShell();
    }
}

void BehaviorCoreEditor::syncImGuiHostsFromLuaShell() {
    luaEngine.withLuaState([this](sol::state& lua) {
        sol::table shell = lua["shell"].get_or(sol::lua_nil);
        if (!shell.valid()) {
            return;
        }

        sol::object surfacesObj = shell["surfaces"];
        if (!surfacesObj.valid() || !surfacesObj.is<sol::table>()) {
            return;
        }

    // Main script editor
    HostConfig mainConfig;
    buildMainScriptEditorConfig(lua, shell, surfacesObj, mainConfig);
    if (mainConfig.visible && mainConfig.bounds.getWidth() > 0 && mainConfig.bounds.getHeight() > 0) {
        mainScriptEditorHost.setVisible(true);
        mainScriptEditorHost.setBounds(mainConfig.bounds);
        mainScriptEditorHost.configureDocument(mainConfig.file, mainConfig.text, mainConfig.syncToken, mainConfig.readOnly);
    } else {
        mainScriptEditorHost.setVisible(false);
    }

    // Hierarchy and Inspector
    HierarchyHostConfig hierarchyConfig;
    InspectorHostConfig inspectorConfig;
    buildHierarchyAndInspectorConfig(lua, shell, surfacesObj, hierarchyConfig, inspectorConfig);

    if (hierarchyConfig.visible && hierarchyConfig.bounds.getWidth() > 0 && hierarchyConfig.bounds.getHeight() > 0) {
        hierarchyHost.setVisible(true);
        hierarchyHost.setBounds(hierarchyConfig.bounds);
        hierarchyHost.configureRows(hierarchyConfig.rows);
    } else {
        hierarchyHost.setVisible(false);
    }

    if (inspectorConfig.visible && inspectorConfig.bounds.getWidth() > 0 && inspectorConfig.bounds.getHeight() > 0) {
        inspectorHost.setVisible(true);
        inspectorHost.setBounds(inspectorConfig.bounds);
        inspectorHost.configureData(inspectorConfig.selectionBounds, inspectorConfig.rows, inspectorConfig.activeProperty);
    } else {
        inspectorHost.setVisible(false);
    }

    // Script list
    ScriptListHostConfig scriptListConfig;
    buildScriptListConfig(lua, shell, surfacesObj, scriptListConfig);
    if (scriptListConfig.visible && scriptListConfig.bounds.getWidth() > 0 && scriptListConfig.bounds.getHeight() > 0) {
        scriptListHost.setVisible(true);
        scriptListHost.setBounds(scriptListConfig.bounds);
        scriptListHost.configureRows(scriptListConfig.rows);
    } else {
        scriptListHost.setVisible(false);
    }

    // Script inspector
    InspectorHostConfig scriptInspectorConfig;
    buildScriptInspectorConfig(lua, shell, surfacesObj, scriptInspectorConfig);
    if (scriptInspectorConfig.visible && scriptInspectorConfig.bounds.getWidth() > 0 && scriptInspectorConfig.bounds.getHeight() > 0) {
        scriptInspectorHost.setVisible(true);
        scriptInspectorHost.setBounds(scriptInspectorConfig.bounds);
        scriptInspectorHost.configureScriptData(scriptInspectorConfig.scriptData);
    } else {
        scriptInspectorHost.setVisible(false);
    }

    // Performance overlay
    PerfOverlayHostConfig perfOverlayConfig;
    buildPerfOverlayConfig(lua, shell, perfOverlayConfig);
    if (perfOverlayConfig.visible && perfOverlayConfig.bounds.getWidth() > 0 && perfOverlayConfig.bounds.getHeight() > 0) {
        perfOverlayHost.setVisible(true);
        perfOverlayHost.setBounds(perfOverlayConfig.bounds);
        perfOverlayHost.configureSnapshot(perfOverlayConfig.snapshot);
    } else {
        perfOverlayHost.setVisible(false);
    }

    // Apply deferred visibility changes
    applyDeferredVisibilityChanges();
    });
}

void BehaviorCoreEditor::applyDeferredVisibilityChanges() {
    for (auto& deferred : deferredVisibilityChanges) {
        if (deferred.host != nullptr) {
            deferred.host->setVisible(deferred.visible);
            if (deferred.visible && deferred.bounds.getWidth() > 0 && deferred.bounds.getHeight() > 0) {
                deferred.host->setBounds(deferred.bounds);
            }
        }
    }
    deferredVisibilityChanges.clear();
}

void BehaviorCoreEditor::queueHostVisibilityChange(juce::Component& host, bool visible, const juce::Rectangle<int>& bounds) {
    deferredVisibilityChanges.push_back({&host, visible, bounds});
}

void BehaviorCoreEditor::paint(juce::Graphics& g) {
    juce::ColourGradient bg(juce::Colour(0xff161b26), 0.0f, 0.0f,
                            juce::Colour(0xff0c1019), 0.0f, (float)getHeight(), false);
    bg.addColour(0.35, juce::Colour(0xff1e2533));
    g.setGradientFill(bg);
    g.fillAll();
}

void BehaviorCoreEditor::resized() {
    rootCanvas.setBounds(getLocalBounds());
    if (usingLuaUi) {
        luaEngine.notifyResized(rootCanvas.getWidth(), rootCanvas.getHeight());
    } else if (errorNode != nullptr) {
        errorNode->setBounds(rootCanvas.getLocalBounds());
    }
}

void BehaviorCoreEditor::showError(const std::string& message) {
    errorMessage = message;
    rootCanvas.clearChildren();

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
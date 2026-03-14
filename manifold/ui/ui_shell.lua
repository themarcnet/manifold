-- ui_shell.lua
-- Shared parent shell/header for Lua UI scripts.
-- Refactored into composable helper modules. Original preserved as tools/baselines/ui_shell_monolithic.lua.

local W = require("ui_widgets")

local Base = require("shell.base_utils")
local ScriptEditor = require("shell.script_editor_utils")
local Runtime = require("shell.runtime_script_utils")
local Inspector = require("shell.inspector_utils")
local ShellMethodsCore = require("shell.methods_core")
local ShellBindings = require("shell.bindings")
local ShellMethodsLayout = require("shell.methods_layout")

local Shell = {}

local readParam = Base.readParam
local readBoolParam = Base.readBoolParam
local getVisibleUiScripts = Base.getVisibleUiScripts
local clamp = Base.clamp
local nowSeconds = Base.nowSeconds
local deriveNodeName = Base.deriveNodeName
local fileStem = Base.fileStem

local SCRIPT_EDITOR_STYLE = ScriptEditor.SCRIPT_EDITOR_STYLE
local SCRIPT_SYNTAX_COLOUR = ScriptEditor.SCRIPT_SYNTAX_COLOUR
local seBuildLines = ScriptEditor.seBuildLines
local seLineColFromPos = ScriptEditor.seLineColFromPos
local sePosFromLineCol = ScriptEditor.sePosFromLineCol
local seGetSelectionRange = ScriptEditor.seGetSelectionRange
local seClearSelection = ScriptEditor.seClearSelection
local seDeleteSelection = ScriptEditor.seDeleteSelection
local seReplaceSelection = ScriptEditor.seReplaceSelection
local seMoveCursor = ScriptEditor.seMoveCursor
local seVisibleLineCount = ScriptEditor.seVisibleLineCount
local seMaxCols = ScriptEditor.seMaxCols
local seIsLetterShortcut = ScriptEditor.seIsLetterShortcut
local isBacktickOrTildeKey = ScriptEditor.isBacktickOrTildeKey
local splitConsoleWords = ScriptEditor.splitConsoleWords
local parseConsoleScalar = ScriptEditor.parseConsoleScalar
local seTokenizeLuaLineCached = ScriptEditor.seTokenizeLuaLineCached

local RuntimeParamSlider = Runtime.RuntimeParamSlider
local scriptLooksSettings = Runtime.scriptLooksSettings
local scriptLooksGlobal = Runtime.scriptLooksGlobal
local scriptLooksDemo = Runtime.scriptLooksDemo
local collectActiveSlotHints = Runtime.collectActiveSlotHints
local scriptMatchesActiveSlot = Runtime.scriptMatchesActiveSlot
local collectUiContextHints = Runtime.collectUiContextHints
local scriptMatchesUiContext = Runtime.scriptMatchesUiContext
local parseDspParamDefsFromCode = Runtime.parseDspParamDefsFromCode
local parseDspGraphFromCode = Runtime.parseDspGraphFromCode
local pointInRect = Runtime.pointInRect
local formatRuntimeValue = Runtime.formatRuntimeValue
local mapBehaviorPathToSlotPath = Runtime.mapBehaviorPathToSlotPath
local collectRuntimeParamsForScript = Runtime.collectRuntimeParamsForScript

local walkHierarchy = Inspector.walkHierarchy
local valueToText = Inspector.valueToText
local upperFirst = Inspector.upperFirst
local splitPath = Inspector.splitPath
local normalizeConfigPath = Inspector.normalizeConfigPath
local getPathTail = Inspector.getPathTail
local getConfigValueByPath = Inspector.getConfigValueByPath
local setConfigValueByPath = Inspector.setConfigValueByPath
local isPathExposed = Inspector.isPathExposed
local getInspectorValue = Inspector.getInspectorValue
local guessEnumOptions = Inspector.guessEnumOptions
local inferEditorType = Inspector.inferEditorType
local appendConfigRows = Inspector.appendConfigRows
local appendSchemaRows = Inspector.appendSchemaRows
local rectsIntersect = Inspector.rectsIntersect
local rectContainsRect = Inspector.rectContainsRect
local computeGridStep = Inspector.computeGridStep
local normalizeArgbNumber = Inspector.normalizeArgbNumber
local argbToRgba = Inspector.argbToRgba
local rgbaToArgb = Inspector.rgbaToArgb
local shouldSkipFallbackConfigKey = Inspector.shouldSkipFallbackConfigKey
local deepCopyTable = Inspector.deepCopyTable
local deepEqual = Inspector.deepEqual
local collectConfigLeaves = Inspector.collectConfigLeaves

function Shell.create(parentNode, options)
    local opts = options or {}

    local restore = (type(_G) == "table") and _G.__manifoldShellRestore or nil
    local initialMode = "performance"
    local initialLeftPanelMode = "hierarchy"
    local pendingRestoreMode = nil
    local pendingRestoreLeftPanelMode = nil

    if type(restore) == "table" then
        if restore.mode == "edit" or restore.mode == "performance" then
            pendingRestoreMode = restore.mode
        end
        if restore.leftPanelMode == "hierarchy" or restore.leftPanelMode == "scripts" then
            pendingRestoreLeftPanelMode = restore.leftPanelMode
        end
        _G.__manifoldShellRestore = nil
    end

    local shell = {
        parentNode = parentNode,
        pad = opts.pad or 0,
        height = opts.height or 44,
        gapAfter = opts.gapAfter or 6,
        onBeforeSwitch = opts.onBeforeSwitch,
        title = opts.title or "PLUGIN",
        selectedWidget = nil,
        selectedWidgets = {},
        treeRoot = nil,
        treeRows = {},
        treeRowHeight = 22,
        treeIndent = 12,
        treeScrollY = 0,
        treeViewportH = 0,
        leftPanelMode = initialLeftPanelMode,
        pendingRestoreMode = pendingRestoreMode,
        pendingRestoreLeftPanelMode = pendingRestoreLeftPanelMode,
        pendingRestoreApplied = false,
        dspRows = {},
        dspRowHeight = 20,
        dspScrollY = 0,
        dspViewportH = 0,
        scriptRows = {},
        scriptRowHeight = 20,
        scriptScrollY = 0,
        scriptViewportH = 0,
        scriptRowsLastRefreshAt = -1,
        scriptRowsRefreshInterval = 0.25,
        runtimeParamsLastRefreshAt = -1,
        runtimeParamsRefreshInterval = 0.1,
        uiRepaintLastAt = -1,
        uiRepaintInterval = 0.033,
        stateParamsCache = {},
        mainTabs = {},
        activeMainTabId = "",
        mainTabRects = {},
        mainTabBarH = 22,
        activeTabContentText = "",
        activeTabContentPath = "",
        editContentMode = "preview",
        scriptEditor = {
            kind = "",
            ownership = "",
            name = "",
            path = "",
            text = "",
            cursorPos = 1,
            selectionAnchor = nil,
            dragAnchorPos = nil,
            scrollRow = 1,
            focused = false,
            status = "Select a script and double-click to edit",
            lastClickTime = 0,
            lastClickLine = -1,
            clickStreak = 0,
        },
        scriptEditorButtonRects = {},
        scriptInspector = {
            kind = "",
            ownership = "",
            name = "",
            path = "",
            text = "",
            params = {},
            runtimeParams = {},
            graph = { nodes = {}, edges = {} },
            runtimeStatus = "",
            runButtonRect = nil,
            stopButtonRect = nil,
            runtimeParamRows = {},
            runtimeParamControls = {},
            runtimeInputActive = false,
            runtimeInputEndpointPath = "",
            runtimeInputText = "",
            runtimeInputMin = nil,
            runtimeInputMax = nil,
            runtimeSliderDragActive = false,
            runtimeSliderDragEndpointPath = "",
            runtimeSliderDragRect = nil,
            runtimeSliderDragMin = nil,
            runtimeSliderDragMax = nil,
            runtimeSliderDragStep = nil,
            runtimeSliderDragLastValue = nil,
            runtimeSliderDragLastApplyAt = -1,
            runtimeSliderDragLastUiRepaintAt = -1,
            editorCollapsed = false,
            graphCollapsed = false,
            editorScrollRow = 1,
            editorHeaderRect = nil,
            editorBodyRect = nil,
            graphHeaderRect = nil,
            graphBodyRect = nil,
            graphPanX = 0,
            graphPanY = 0,
            graphDragging = false,
            graphDragStartX = 0,
            graphDragStartY = 0,
            graphDragPanX = 0,
            graphDragPanY = 0,
        },
        dspPreviewSlotName = "editor_preview",
        selectedDspRow = nil,
        selectedScriptRow = nil,
        leftListLastClickAt = -1,
        leftListLastClickKey = "",
        doubleClickWindow = 0.35,
        treeRefreshPending = false,
        treeLastRefreshAt = -1,
        contentScale = 1.0,
        contentTx = 0,
        contentTy = 0,
        viewOriginX = 0,
        viewOriginY = 0,
        autoFit = true,
        minZoom = 0.15,
        maxZoom = 5.0,
        panX = 0,
        panY = 0,
        navMode = "select",
        dragState = nil,
        workspacePad = 512,
        cameraPanMargin = 120,
        previewX = 0,
        previewY = 0,
        previewW = 0,
        previewH = 0,
        designW = 0,
        designH = 0,
        viewportDesignX = 0,
        viewportDesignY = 0,
        viewportDesignW = 0,
        viewportDesignH = 0,
        handleSize = 8,
        minWidgetSize = 8,
        inspectorRows = {},
        inspectorScrollY = 0,
        inspectorRowHeight = 18,
        inspectorViewportH = 0,
        inspectorUpdating = false,
        activeConfigProperty = nil,
        activeEnumValues = nil,
        undoStack = {},
        redoStack = {},
        maxHistoryEntries = 96,
        historyApplying = false,
        performanceView = nil,
        performanceViewInitialized = false,
        performanceViewLayoutInfo = nil,
        devModeEnabled = opts.devMode ~= false,
        listWheelRows = 2,
        debugLastIdentifier = "",
        console = {
            visible = false,
            lines = {
                { text = "Dev console ready. Type 'help'.", colour = 0xff93c5fd },
            },
            input = "",
            history = {},
            historyIndex = 0,
            scrollOffset = 0,
            maxLines = 240,
            rect = { x = 0, y = 0, w = 0, h = 0 },
        },
        perfOverlay = {
            visible = false,
            activeTab = "frame",
        },
        surfaces = {},
    }

    shell.panel = W.Panel.new(parentNode, "sharedShell", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })

    shell.titleLabel = W.Label.new(shell.panel.node, "sharedShellTitle", {
        text = shell.title,
        colour = 0xff7dd3fc,
        fontSize = 18.0,
        fontStyle = FontStyle.bold,
    })

    shell.masterKnob = W.Knob.new(shell.panel.node, "sharedMaster", {
        min = 0, max = 1, step = 0.01, value = 0.8,
        label = "Master", suffix = "",
        colour = 0xffa78bfa,
        on_change = function(v)
            command("SET", "/core/behavior/volume", tostring(v))
        end,
    })

    shell.inputKnob = W.Knob.new(shell.panel.node, "sharedInput", {
        min = 0, max = 2, step = 0.01, value = 1.0,
        label = "Input", suffix = "",
        colour = 0xfff59e0b,
        on_change = function(v)
            command("SET", "/core/behavior/inputVolume", tostring(v))
        end,
    })

    shell.passthroughToggle = W.Toggle.new(shell.panel.node, "sharedPassthrough", {
        label = "Input",
        onColour = 0xff34d399,
        offColour = 0xff475569,
        value = true,
        on_change = function(on)
            command("SET", "/core/behavior/passthrough", on and "1" or "0")
        end,
    })

    shell.settingsOpen = false
    shell.scriptOverlay = nil

    shell.settingsButton = W.Button.new(shell.panel.node, "sharedSettings", {
        label = "Settings",
        bg = 0xff1e293b,
        fontSize = 13.0,
        on_click = function()
            shell.settingsOpen = not shell.settingsOpen
            if not shell.settingsOpen then
                if shell.scriptOverlay then
                    shell.scriptOverlay:setBounds(0, 0, 0, 0)
                end
                return
            end

            local currentPath = getCurrentScriptPath()
            local scripts = getVisibleUiScripts(currentPath)
            if shell.scriptOverlay == nil then
                shell.scriptOverlay = shell.parentNode:addChild("sharedScriptOverlay")
            end

            local itemH = 28
            local headerH = 26
            local overlayH = math.min(320, headerH + #scripts * itemH + 8)
            local overlayW = 240
            local btnX, btnY = shell.settingsButton.node:getBounds()
            local panelX, panelY = shell.panel.node:getBounds()

            shell.scriptOverlay:setBounds(panelX + btnX - overlayW + 84, panelY + btnY + 32, overlayW, overlayH)
            shell.scriptOverlay:setInterceptsMouse(true, true)
            shell.scriptOverlay:toFront(false)

            shell.scriptOverlay:setOnDraw(function(self)
                local w = self:getWidth()
                local h = self:getHeight()
                gfx.setColour(0x50000000)
                gfx.fillRoundedRect(2, 2, w, h, 6)
                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(0, 0, w - 2, h - 2, 6)
                gfx.setColour(0xff475569)
                gfx.drawRoundedRect(0, 0, w - 2, h - 2, 6, 1)

                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                gfx.drawText("Settings", 10, 4, w - 20, headerH - 4, Justify.centredLeft)

                if #scripts == 0 then
                    gfx.setColour(0xff64748b)
                    gfx.setFont(10.0)
                    gfx.drawText("No settings script", 12, headerH + 4, w - 24, 18, Justify.centredLeft)
                else
                    for i = 1, #scripts do
                        local s = scripts[i]
                        local y = headerH + (i - 1) * itemH
                        local isCurrent = (s.path == currentPath)
                        if isCurrent then
                            gfx.setColour(0xff334155)
                            gfx.fillRoundedRect(4, y, w - 10, itemH - 2, 4)
                        end
                        gfx.setColour(isCurrent and 0xff38bdf8 or 0xffe2e8f0)
                        gfx.setFont(11.0)
                        gfx.drawText(s.name, 12, y, w - 24, itemH - 2, Justify.centredLeft)
                    end
                end
            end)

            shell.scriptOverlay:setOnMouseDown(function(mx, my)
                if my < headerH then
                    shell.settingsOpen = false
                    shell.scriptOverlay:setBounds(0, 0, 0, 0)
                    return
                end

                local idx = math.floor((my - headerH) / itemH) + 1
                if idx >= 1 and idx <= #scripts then
                    local target = scripts[idx].path
                    shell.settingsOpen = false
                    shell.scriptOverlay:setBounds(0, 0, 0, 0)

                    if target ~= currentPath then
                        if type(shell.onBeforeSwitch) == "function" then
                            shell.onBeforeSwitch(target, currentPath)
                        end
                        shell:stashRestoreStateForScriptSwitch()
                        switchUiScript(target)
                    end
                else
                    shell.settingsOpen = false
                    shell.scriptOverlay:setBounds(0, 0, 0, 0)
                end
            end)
        end,
    })

    -- ==========================================================================
    -- MODE TOGGLE (Performance | Edit)
    -- ==========================================================================
    shell.mode = initialMode
    shell.currentZoom = 1.0
    
    -- Adopt the script content root (created by C++ as child 0)
    shell.content = parentNode:getChild(0)
    
    -- Create tree panel (for hierarchy view in edit mode)
    shell.treePanel = W.Panel.new(parentNode, "treePanel", {
        bg = 0xff141a24,
        border = 0xff334155,
        borderWidth = 1,
        radius = 6,
    })
    shell.treeLabel = W.Label.new(shell.treePanel.node, "treeLabel", {
        text = "Hierarchy",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    shell.treeTabHierarchy = W.Button.new(shell.treePanel.node, "treeTabHierarchy", {
        label = "Hierarchy",
        bg = 0xff334155,
        fontSize = 10.0,
        on_click = function()
            shell:setLeftPanelMode("hierarchy")
        end,
    })

    -- Legacy placeholder (hidden in layout); DSP scripts now live under Scripts panel.
    shell.treeTabDsp = W.Button.new(shell.treePanel.node, "treeTabDsp", {
        label = "",
        bg = 0xff1e293b,
        fontSize = 10.0,
        on_click = function()
        end,
    })

    shell.treeTabScripts = W.Button.new(shell.treePanel.node, "treeTabScripts", {
        label = "Scripts",
        bg = 0xff1e293b,
        fontSize = 10.0,
        on_click = function()
            shell:setLeftPanelMode("scripts")
        end,
    })

    shell.treeCanvas = shell.treePanel.node:addChild("treeCanvas")
    shell.treeCanvas:setInterceptsMouse(true, true)
    shell.treeCanvas:setWantsKeyboardFocus(true)

    shell.dspCanvas = shell.treePanel.node:addChild("dspCanvas")
    shell.dspCanvas:setInterceptsMouse(true, true)
    shell.dspCanvas:setWantsKeyboardFocus(true)

    shell.scriptCanvas = shell.treePanel.node:addChild("scriptCanvas")
    shell.scriptCanvas:setInterceptsMouse(true, true)
    shell.scriptCanvas:setWantsKeyboardFocus(true)

    shell.treePanel.node:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my

        if shell.leftPanelMode == "hierarchy" then
            local nextScroll, changed = shell:applyWheelListScroll(
                shell.treeScrollY,
                deltaY,
                shell.treeRowHeight,
                #shell.treeRows,
                shell.treeViewportH,
                2
            )
            if changed then
                shell.treeScrollY = nextScroll
                shell.treeCanvas:repaint()
            end
        else
            local nextScroll, changed = shell:applyWheelListScroll(
                shell.scriptScrollY,
                deltaY,
                shell.scriptRowHeight,
                #shell.scriptRows,
                shell.scriptViewportH,
                2
            )
            if changed then
                shell.scriptScrollY = nextScroll
                shell.scriptCanvas:repaint()
            end
        end
    end)

    shell.mainTabBar = parentNode:addChild("mainTabBar")
    shell.mainTabBar:setInterceptsMouse(true, true)

    shell.mainTabContent = parentNode:addChild("mainTabContent")
    shell.mainTabContent:setInterceptsMouse(true, true)
    shell.mainTabContent:setWantsKeyboardFocus(true)

    shell.previewOverlay = parentNode:addChild("editorPreviewOverlay")
    shell.previewOverlay:setInterceptsMouse(true, true)

    shell.consoleOverlay = parentNode:addChild("devConsoleOverlay")
    shell.consoleOverlay:setInterceptsMouse(false, false)
    shell.consoleOverlay:setWantsKeyboardFocus(true)

    -- Create inspector panel (for properties in edit mode)
    shell.inspectorPanel = W.Panel.new(parentNode, "inspectorPanel", {
        bg = 0xff141a24,
        border = 0xff334155,
        borderWidth = 1,
        radius = 6,
    })
    shell.inspectorLabel = W.Label.new(shell.inspectorPanel.node, "inspectorLabel", {
        text = "Inspector",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    shell.inspectorX = W.NumberBox.new(shell.inspectorPanel.node, "inspectorX", {
        min = -4096, max = 4096, step = 1, value = 0,
        label = "X", format = "%d",
        on_change = function(v)
            shell:applyBoundsEditor("x", v)
        end,
    })
    shell.inspectorY = W.NumberBox.new(shell.inspectorPanel.node, "inspectorY", {
        min = -4096, max = 4096, step = 1, value = 0,
        label = "Y", format = "%d",
        on_change = function(v)
            shell:applyBoundsEditor("y", v)
        end,
    })
    shell.inspectorW = W.NumberBox.new(shell.inspectorPanel.node, "inspectorW", {
        min = 1, max = 8192, step = 1, value = 1,
        label = "W", format = "%d",
        on_change = function(v)
            shell:applyBoundsEditor("w", v)
        end,
    })
    shell.inspectorH = W.NumberBox.new(shell.inspectorPanel.node, "inspectorH", {
        min = 1, max = 8192, step = 1, value = 1,
        label = "H", format = "%d",
        on_change = function(v)
            shell:applyBoundsEditor("h", v)
        end,
    })

    shell.inspectorPropLabel = W.Label.new(shell.inspectorPanel.node, "inspectorPropLabel", {
        text = "",
        colour = 0xff94a3b8,
        fontSize = 10.0,
        justification = Justify.centredLeft,
    })

    shell.inspectorPropNumber = W.NumberBox.new(shell.inspectorPanel.node, "inspectorPropNumber", {
        min = -2147483647, max = 2147483647, step = 1, value = 0,
        label = "Value", format = "%d",
        on_change = function(v)
            shell:applyActiveConfigValue(v)
        end,
    })

    shell.inspectorColorPreview = W.Panel.new(shell.inspectorPanel.node, "inspectorColorPreview", {
        bg = 0xff000000,
        border = 0xff334155,
        borderWidth = 1,
        radius = 3,
    })

    shell.inspectorColorHex = W.Label.new(shell.inspectorPanel.node, "inspectorColorHex", {
        text = "#000000FF",
        colour = 0xffcbd5e1,
        fontSize = 10.0,
        justification = Justify.centred,
    })

    local function makeColorSlider(name, label, onChange)
        return W.Slider.new(shell.inspectorPanel.node, name, {
            label = label,
            min = 0,
            max = 255,
            step = 1,
            value = 0,
            showValue = true,
            on_change = onChange,
        })
    end

    shell.inspectorColorR = makeColorSlider("inspectorColorR", "R", function(v)
        shell:applyActiveColorComponent("r", v)
    end)
    shell.inspectorColorG = makeColorSlider("inspectorColorG", "G", function(v)
        shell:applyActiveColorComponent("g", v)
    end)
    shell.inspectorColorB = makeColorSlider("inspectorColorB", "B", function(v)
        shell:applyActiveColorComponent("b", v)
    end)
    shell.inspectorColorA = makeColorSlider("inspectorColorA", "A", function(v)
        shell:applyActiveColorComponent("a", v)
    end)

    shell.inspectorPropBool = W.Toggle.new(shell.inspectorPanel.node, "inspectorPropBool", {
        label = "",
        value = false,
        on_change = function(on)
            shell:applyActiveConfigValue(on)
        end,
    })

    shell.inspectorPropEnum = W.Dropdown.new(shell.inspectorPanel.node, "inspectorPropEnum", {
        options = { "-" },
        selected = 1,
        rootNode = parentNode,
        on_select = function(idx, label)
            shell:applyActiveConfigEnumChoice(idx)
        end,
    })

    shell.inspectorPropText = W.Label.new(shell.inspectorPanel.node, "inspectorPropText", {
        text = "",
        colour = 0xffcbd5e1,
        fontSize = 10.0,
        justification = Justify.centredLeft,
    })

    shell.inspectorPropCopy = W.Button.new(shell.inspectorPanel.node, "inspectorPropCopy", {
        label = "Copy",
        fontSize = 10.0,
        on_click = function()
            shell:copyActiveConfigText()
        end,
    })

    shell.inspectorPropPaste = W.Button.new(shell.inspectorPanel.node, "inspectorPropPaste", {
        label = "Paste",
        fontSize = 10.0,
        on_click = function()
            shell:pasteActiveConfigText()
        end,
    })

    shell.inspectorCanvas = shell.inspectorPanel.node:addChild("inspectorCanvas")
    shell.inspectorCanvas:setInterceptsMouse(true, true)
    shell.inspectorCanvas:setWantsKeyboardFocus(true)

    shell.inspectorPanel.node:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my
        if shell.leftPanelMode == "scripts" then
            return
        end
        local nextScroll, changed = shell:applyWheelListScroll(
            shell.inspectorScrollY,
            deltaY,
            shell.inspectorRowHeight,
            #shell.inspectorRows,
            shell.inspectorViewportH,
            2
        )
        if changed then
            shell.inspectorScrollY = nextScroll
            shell.inspectorCanvas:repaint()
        end
    end)

    shell.perfButton = W.Button.new(shell.panel.node, "perfMode", {
        label = "Performance",
        bg = (shell.mode == "performance") and 0xff38bdf8 or 0xff1e293b,
        fontSize = 11.0,
        on_click = function()
            if shell.mode ~= "performance" then
                shell:setMode("performance")
            end
        end,
    })

    shell.editButton = W.Button.new(shell.panel.node, "editMode", {
        label = "Edit",
        bg = (shell.mode == "edit") and 0xff38bdf8 or 0xff1e293b,
        fontSize = 11.0,
        on_click = function()
            if shell.mode ~= "edit" then
                shell:setMode("edit")
            end
        end,
    })

    shell.zoomOutButton = W.Button.new(shell.panel.node, "zoomOut", {
        label = "-",
        bg = 0xff1e293b,
        fontSize = 12.0,
        on_click = function()
            shell.autoFit = false
            shell.currentZoom = clamp(shell.currentZoom * 0.9, shell.minZoom, shell.maxZoom)
            local w = shell.parentNode:getWidth()
            local h = shell.parentNode:getHeight()
            shell:layout(w, h)
        end,
    })

    shell.zoomInButton = W.Button.new(shell.panel.node, "zoomIn", {
        label = "+",
        bg = 0xff1e293b,
        fontSize = 12.0,
        on_click = function()
            shell.autoFit = false
            shell.currentZoom = clamp(shell.currentZoom * 1.1, shell.minZoom, shell.maxZoom)
            local w = shell.parentNode:getWidth()
            local h = shell.parentNode:getHeight()
            shell:layout(w, h)
        end,
    })

    shell.zoomFitButton = W.Button.new(shell.panel.node, "zoomFit", {
        label = "Fit",
        bg = 0xff1e293b,
        fontSize = 10.0,
        on_click = function()
            shell.autoFit = true
            shell.panX = 0
            shell.panY = 0
            local w = shell.parentNode:getWidth()
            local h = shell.parentNode:getHeight()
            shell:layout(w, h)
        end,
    })

    shell.panModeButton = W.Button.new(shell.panel.node, "panMode", {
        label = "Pan",
        bg = 0xff1e293b,
        fontSize = 10.0,
        on_click = function()
            if shell.navMode == "pan" then
                shell.navMode = "select"
            else
                shell.navMode = "pan"
            end
            local w = shell.parentNode:getWidth()
            local h = shell.parentNode:getHeight()
            shell:layout(w, h)
        end,
    })

    shell.saveProjectButton = W.Button.new(shell.panel.node, "saveProject", {
        label = "Save UI",
        bg = 0xff14532d,
        fontSize = 10.0,
        on_click = function()
            shell:saveStructuredProjectUi()
        end,
    })

    shell.reloadProjectButton = W.Button.new(shell.panel.node, "reloadProject", {
        label = "Reload UI",
        bg = 0xff1e293b,
        fontSize = 10.0,
        on_click = function()
            shell:reloadStructuredProjectUi()
        end,
    })

    shell.zoomLabel = W.Label.new(shell.panel.node, "zoomLabel", {
        text = "100%",
        colour = 0xff94a3b8,
        fontSize = 10.0,
        justification = Justify.centred,
    })

    ShellMethodsCore.attach(shell)
    ShellBindings.attach(shell)
    ShellMethodsLayout.attach(shell)

    shell:syncToolSurfaces()
    shell:syncPerfOverlaySurface(parentNode:getWidth(), parentNode:getHeight())

    return shell
end

return Shell

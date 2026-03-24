-- Auto-extracted from ui_shell.lua to keep shell composable.

local W = require("ui_widgets")

local Base = require("shell.base_utils")
local ScriptEditor = require("shell.script_editor_utils")
local Runtime = require("shell.runtime_script_utils")
local Inspector = require("shell.inspector_utils")

local readParam = Base.readParam
local readBoolParam = Base.readBoolParam
local getVisibleUiScripts = Base.getVisibleUiScripts
local clamp = Base.clamp
local nowSeconds = Base.nowSeconds
local deriveNodeName = Base.deriveNodeName
local fileStem = Base.fileStem
local safeToFront = Base.safeToFront
local safeGrabKeyboardFocus = Base.safeGrabKeyboardFocus

local SCRIPT_EDITOR_STYLE = ScriptEditor.SCRIPT_EDITOR_STYLE
local SCRIPT_SYNTAX_COLOUR = ScriptEditor.SCRIPT_SYNTAX_COLOUR
local seBuildLines = ScriptEditor.seBuildLines
local seBuildLinesCached = ScriptEditor.seBuildLinesCached
local seLineColFromPos = ScriptEditor.seLineColFromPos
local seLineColCached = ScriptEditor.seLineColCached
local sePosFromLineCol = ScriptEditor.sePosFromLineCol
local sePosFromLineColCached = ScriptEditor.sePosFromLineColCached
local seGetSelectionRange = ScriptEditor.seGetSelectionRange
local seClearSelection = ScriptEditor.seClearSelection
local seDeleteSelection = ScriptEditor.seDeleteSelection
local seReplaceSelection = ScriptEditor.seReplaceSelection
local seInvalidateCache = ScriptEditor.seInvalidateCache
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
local walkStructuredRecords = Inspector.walkStructuredRecords
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

local M = {}

local function shellPerfNowMs()
    return nowSeconds() * 1000.0
end

local function shellPerfTrace(label, startMs, extra)
    local elapsedMs = shellPerfNowMs() - startMs
    if elapsedMs < 8.0 and extra == nil then
        return elapsedMs
    end
    if extra ~= nil and extra ~= "" then
        print(string.format("[ShellPerf] %s %.3fms %s", label, elapsedMs, extra))
    else
        print(string.format("[ShellPerf] %s %.3fms", label, elapsedMs))
    end
    return elapsedMs
end

function M.attach(shell)
    local function cloneRect(bounds)
        if type(bounds) ~= "table" then
            return { x = 0, y = 0, w = 0, h = 0 }
        end
        return {
            x = math.floor(tonumber(bounds.x) or 0),
            y = math.floor(tonumber(bounds.y) or 0),
            w = math.max(0, math.floor(tonumber(bounds.w) or 0)),
            h = math.max(0, math.floor(tonumber(bounds.h) or 0)),
        }
    end

    local function currentRendererMode()
        if type(getUIRendererMode) ~= "function" then
            return "canvas"
        end
        return tostring(getUIRendererMode() or "canvas")
    end

    local function rendererModeIsCanvas()
        return currentRendererMode() == "canvas"
    end

    local function rendererModeIsDirect()
        return currentRendererMode() == "imgui-direct"
    end

    local function setWidgetBounds(widget, x, y, w, h)
        if widget == nil then
            return
        end
        if type(widget.setBounds) == "function" then
            widget:setBounds(x, y, w, h)
        elseif widget.node and type(widget.node.setBounds) == "function" then
            widget.node:setBounds(x, y, w, h)
        end
    end

    shell._animatedWidgets = shell._animatedWidgets or {}
    shell._deferredRefreshes = shell._deferredRefreshes or {}
    shell._deferredRefreshGeneration = shell._deferredRefreshGeneration or 0

    function shell:registerAnimatedWidget(widget)
        if type(widget) == "table" then
            self._animatedWidgets[widget] = true
        end
    end

    function shell:unregisterAnimatedWidget(widget)
        if type(widget) == "table" then
            self._animatedWidgets[widget] = nil
        end
    end

    function shell:tickRetainedAnimations(deltaSeconds)
        for widget in pairs(self._animatedWidgets) do
            if type(widget) == "table" and type(widget.tickRetained) == "function" then
                widget:tickRetained(deltaSeconds)
            end
        end
    end

    function shell:deferRetainedRefresh(fn)
        if type(fn) == "function" then
            table.insert(self._deferredRefreshes, fn)
        end
    end

    function shell:flushDeferredRefreshes()
        while #self._deferredRefreshes > 0 do
            local pending = self._deferredRefreshes
            self._deferredRefreshes = {}
            for i = 1, #pending do
                pending[i]()
            end
        end
    end

    function shell:clearDeferredRefreshes()
        self._deferredRefreshes = {}
        self._deferredRefreshGeneration = (tonumber(self._deferredRefreshGeneration) or 0) + 1
    end

    local function refreshRetainedRecursive(node)
        if node == nil then
            return
        end

        if node.getUserData ~= nil then
            local meta = node:getUserData("_editorMeta")
            if type(meta) == "table" then
                local widget = meta.widget
                if type(widget) == "table" and type(widget.refreshRetained) == "function" then
                    local w = 0
                    local h = 0
                    if node.getWidth ~= nil and node.getHeight ~= nil then
                        w = tonumber(node:getWidth()) or 0
                        h = tonumber(node:getHeight()) or 0
                    elseif node.getBounds ~= nil then
                        local _, _, bw, bh = node:getBounds()
                        w = tonumber(bw) or 0
                        h = tonumber(bh) or 0
                    end
                    widget:refreshRetained(w, h)
                end
            end
        end

        -- imgui-direct must not depend on Canvas-style draw callback replay.
        -- Standard runtime widgets build retained display lists directly via
        -- refreshRetained(); only legacy replace/overlay paths should use the
        -- invokeDrawForRetained compatibility hook.
        if (not rendererModeIsDirect()) and node.invokeDrawForRetained ~= nil then
            local ok, err = pcall(function() node:invokeDrawForRetained() end)
            if not ok and err then
                -- Silently ignore — some nodes may not support this
            end
        end

        if node.getNumChildren ~= nil and node.getChild ~= nil then
            local childCount = math.max(0, math.floor(tonumber(node:getNumChildren()) or 0))
            for i = 0, childCount - 1 do
                local child = node:getChild(i)
                if child ~= nil then
                    refreshRetainedRecursive(child)
                end
            end
        end
    end

    local function tickRetainedRecursive(node, deltaSeconds)
        if node == nil then
            return
        end

        if node.getUserData ~= nil then
            local meta = node:getUserData("_editorMeta")
            if type(meta) == "table" then
                local widget = meta.widget
                if type(widget) == "table" and type(widget.tickRetained) == "function" then
                    widget:tickRetained(deltaSeconds)
                end
            end
        end

        -- imgui-direct does not use draw-callback replay in the hot path.
        -- Dynamic runtime content must update its retained display lists from
        -- explicit retained sync/tick code instead of Canvas-style onDraw hooks.
        if (not rendererModeIsDirect()) and node.invokeDrawForRetained ~= nil then
            local ok, err = pcall(function() node:invokeDrawForRetained() end)
            if not ok and err then
                -- silently ignore
            end
        end

        if node.getNumChildren ~= nil and node.getChild ~= nil then
            local childCount = math.max(0, math.floor(tonumber(node:getNumChildren()) or 0))
            for i = 0, childCount - 1 do
                local child = node:getChild(i)
                if child ~= nil then
                    tickRetainedRecursive(child, deltaSeconds)
                end
            end
        end
    end

    local function normalizeSurfaceDescriptor(id, descriptor)
        local d = type(descriptor) == "table" and descriptor or {}
        return {
            id = tostring(d.id or id or ""),
            kind = tostring(d.kind or "panel"),
            backend = tostring(d.backend or "lua-canvas"),
            visible = d.visible == true,
            bounds = cloneRect(d.bounds),
            z = math.floor(tonumber(d.z) or 0),
            mode = tostring(d.mode or "global"),
            docking = tostring(d.docking or "floating"),
            interactive = d.interactive ~= false,
            modal = d.modal == true,
            payloadKey = tostring(d.payloadKey or id or ""),
            title = tostring(d.title or id or ""),
        }
    end

    function shell:ensureSurfaceRegistry()
        if type(self.surfaces) ~= "table" then
            self.surfaces = {}
        end
        return self.surfaces
    end

    function shell:defineSurface(id, descriptor)
        local key = tostring(id or "")
        if key == "" then
            return nil
        end
        local surfaces = self:ensureSurfaceRegistry()
        surfaces[key] = normalizeSurfaceDescriptor(key, descriptor)
        return surfaces[key]
    end

    function shell:updateSurface(id, patch)
        local key = tostring(id or "")
        if key == "" then
            return nil
        end
        local surfaces = self:ensureSurfaceRegistry()
        local current = normalizeSurfaceDescriptor(key, surfaces[key] or { id = key })
        if type(patch) == "table" then
            for k, v in pairs(patch) do
                if k == "bounds" then
                    current.bounds = cloneRect(v)
                else
                    current[k] = v
                end
            end
        end
        surfaces[key] = normalizeSurfaceDescriptor(key, current)
        return surfaces[key]
    end

    function shell:getSurface(id)
        local surfaces = self:ensureSurfaceRegistry()
        return surfaces[tostring(id or "")]
    end

    function shell:getSurfaceDescriptors()
        return self:ensureSurfaceRegistry()
    end

    function shell:getDefaultPerfOverlayBounds(totalW, totalH)
        local w = math.max(1, math.floor(tonumber(totalW) or self.parentNode:getWidth() or 0))
        local h = math.max(1, math.floor(tonumber(totalH) or self.parentNode:getHeight() or 0))
        local panelW = math.min(700, math.max(560, math.floor(w * 0.48)))
        local panelH = math.min(620, math.max(520, math.floor(h * 0.68)))
        return {
            x = math.max(0, w - panelW - 16),
            y = 16,
            w = panelW,
            h = panelH,
        }
    end

    function shell:syncPerfOverlaySurface(totalW, totalH)
        self.perfOverlay = self.perfOverlay or { visible = false, activeTab = "frame" }

        local bounds = self.perfOverlay.bounds
        if type(bounds) ~= "table"
            or (tonumber(bounds.w) or 0) <= 0
            or (tonumber(bounds.h) or 0) <= 0 then
            bounds = self:getDefaultPerfOverlayBounds(totalW, totalH)
            self.perfOverlay.bounds = cloneRect(bounds)
        else
            bounds = cloneRect(bounds)
            bounds.w = math.max(560, math.floor(tonumber(bounds.w) or 0))
            bounds.h = math.max(520, math.floor(tonumber(bounds.h) or 0))
            self.perfOverlay.bounds = bounds
        end

        return self:defineSurface("perfOverlay", {
            id = "perfOverlay",
            kind = "overlay",
            backend = "imgui",
            visible = self.perfOverlay.visible == true,
            bounds = bounds,
            z = 100,
            mode = "global",
            docking = "floating",
            interactive = true,
            modal = false,
            payloadKey = "perfOverlay",
            title = "Performance",
        })
    end

    function shell:setPerfOverlayVisible(visible)
        self.perfOverlay = self.perfOverlay or { visible = false, activeTab = "frame" }
        self.perfOverlay.visible = visible == true
        self:syncPerfOverlaySurface(self.parentNode:getWidth(), self.parentNode:getHeight())
    end

    function shell:setPerfOverlayActiveTab(tabId)
        self.perfOverlay = self.perfOverlay or { visible = false, activeTab = "frame" }
        if type(tabId) == "string" and tabId ~= "" then
            self.perfOverlay.activeTab = string.lower(tabId)
        end
        self:syncPerfOverlaySurface(self.parentNode:getWidth(), self.parentNode:getHeight())
    end

    function shell:setPerfOverlayBounds(x, y, w, h)
        self.perfOverlay = self.perfOverlay or { visible = false, activeTab = "frame" }
        self.perfOverlay.bounds = {
            x = math.floor(tonumber(x) or 0),
            y = math.floor(tonumber(y) or 0),
            w = math.max(0, math.floor(tonumber(w) or 0)),
            h = math.max(0, math.floor(tonumber(h) or 0)),
        }
        self:syncPerfOverlaySurface(self.parentNode:getWidth(), self.parentNode:getHeight())
    end

    local function defineHostSurface(shellRef, id, d, visible, bounds)
        return shellRef:defineSurface(id, {
            id = id,
            kind = d.kind or "tool",
            backend = d.backend or "imgui",
            visible = visible == true,
            bounds = bounds,
            z = math.floor(tonumber(d.z) or 40),
            mode = d.mode or "edit",
            docking = d.docking or "docked-left",
            interactive = d.interactive ~= false,
            modal = d.modal == true,
            payloadKey = d.payloadKey or id,
            title = d.title or id,
        })
    end

    function shell:syncHostSurfaceFromCanvas(id, descriptor)
        local d = type(descriptor) == "table" and descriptor or {}
        local panelNode = d.panelNode
        local contentNode = d.contentNode
        local visible = d.visible == true

        local bounds = { x = 0, y = 0, w = 0, h = 0 }
        if visible and panelNode ~= nil and contentNode ~= nil and panelNode.getBounds and contentNode.getBounds then
            local px, py, pw, ph = panelNode:getBounds()
            local cx, cy, cw, ch = contentNode:getBounds()
            local _ = pw
            _ = ph
            if (tonumber(cw) or 0) > 0 and (tonumber(ch) or 0) > 0 then
                bounds = {
                    x = math.floor((tonumber(px) or 0) + (tonumber(cx) or 0)),
                    y = math.floor((tonumber(py) or 0) + (tonumber(cy) or 0)),
                    w = math.max(0, math.floor(tonumber(cw) or 0)),
                    h = math.max(0, math.floor(tonumber(ch) or 0)),
                }
            else
                visible = false
            end
        else
            visible = false
        end

        return defineHostSurface(self, id, d, visible, bounds)
    end

    function shell:syncHostSurfaceFromPanelInsets(id, descriptor)
        local d = type(descriptor) == "table" and descriptor or {}
        local panelNode = d.panelNode
        local visible = d.visible == true
        local bounds = { x = 0, y = 0, w = 0, h = 0 }

        if visible and panelNode ~= nil and panelNode.getBounds then
            local px, py, pw, ph = panelNode:getBounds()
            local insetX = math.floor(tonumber(d.insetX) or 0)
            local insetY = math.floor(tonumber(d.insetY) or 0)
            local insetW = math.floor(tonumber(d.insetW) or 0)
            local insetH = math.floor(tonumber(d.insetH) or 0)
            local bw = math.max(0, math.floor(tonumber(pw) or 0) + insetW)
            local bh = math.max(0, math.floor(tonumber(ph) or 0) + insetH)
            if bw > 0 and bh > 0 then
                bounds = {
                    x = math.floor((tonumber(px) or 0) + insetX),
                    y = math.floor((tonumber(py) or 0) + insetY),
                    w = bw,
                    h = bh,
                }
            else
                visible = false
            end
        else
            visible = false
        end

        return defineHostSurface(self, id, d, visible, bounds)
    end

    function shell:computeMainScriptEditorGeometry()
        local ed = self.scriptEditor
        if type(ed) ~= "table" then
            return
        end

        ed.bodyRect = nil

        local viewW = 0
        local viewH = 0
        if self.mainTabContent and self.mainTabContent.getWidth and self.mainTabContent.getHeight then
            viewW = math.floor(tonumber(self.mainTabContent:getWidth()) or 0)
            viewH = math.floor(tonumber(self.mainTabContent:getHeight()) or 0)
        end

        if self.editContentMode ~= "script"
            or (ed.path or "") == ""
            or viewW <= 0
            or viewH <= 0 then
            if type(self.syncToolSurfaces) == "function" then
                self:syncToolSurfaces()
            end
            return
        end

        ed.bodyRect = {
            x = 0,
            y = SCRIPT_EDITOR_STYLE.headerH,
            w = viewW,
            h = math.max(0, viewH - SCRIPT_EDITOR_STYLE.headerH),
        }

        if type(self.syncToolSurfaces) == "function" then
            self:syncToolSurfaces()
        end
    end

    function shell:computeScriptInspectorGeometry()
        local si = self.scriptInspector
        if type(si) ~= "table" then
            return
        end

        si.editorHeaderRect = nil
        si.editorBodyRect = nil
        si.graphHeaderRect = nil
        si.graphBodyRect = nil
        si.runButtonRect = nil
        si.stopButtonRect = nil

        local viewW = 0
        local viewH = 0
        if self.inspectorCanvas and self.inspectorCanvas.getWidth and self.inspectorCanvas.getHeight then
            viewW = math.floor(tonumber(self.inspectorCanvas:getWidth()) or 0)
            viewH = math.floor(tonumber(self.inspectorCanvas:getHeight()) or 0)
        end

        if self.leftPanelMode ~= "scripts"
            or (si.path or "") == ""
            or viewW <= 0
            or viewH <= 0 then
            if type(self.syncToolSurfaces) == "function" then
                self:syncToolSurfaces()
            end
            return
        end

        local y = 6
        local function advanceInfoRow()
            y = y + 16
        end

        advanceInfoRow() -- Script
        advanceInfoRow() -- Kind
        if si.ownership and si.ownership ~= "" then
            advanceInfoRow() -- Ownership
            local docStatus = self:getStructuredDocumentStatus(si.path)
            if type(docStatus) == "table" then
                advanceInfoRow() -- Dirty
            end
            local projectStatus = self:getStructuredProjectStatus()
            if type(projectStatus) == "table" and tostring(projectStatus.lastError or "") ~= "" then
                advanceInfoRow() -- Last Error
            end
        end
        advanceInfoRow() -- Path

        if si.kind == "dsp" then
            local declared = si.params or {}
            local runtimeParams = si.runtimeParams or {}

            advanceInfoRow() -- Params (declared)
            advanceInfoRow() -- Params (runtime)
            advanceInfoRow() -- Graph

            local btnW = math.floor((viewW - 24) * 0.5)
            local btnH = 18
            si.runButtonRect = { x = 8, y = y, w = btnW, h = btnH }
            si.stopButtonRect = { x = 12 + btnW, y = y, w = btnW, h = btnH }
            y = y + btnH + 4

            if si.runtimeStatus and si.runtimeStatus ~= "" then
                y = y + 14
            end

            y = y + 14 -- Declared Params header
            if #declared == 0 then
                y = y + 14
            else
                local maxRows = math.min(6, #declared)
                y = y + (maxRows * 14)
                if #declared > maxRows then
                    y = y + 12
                end
            end

            y = y + 14 -- Runtime Params header
            y = y + 12 -- Runtime params hint text
            if #runtimeParams == 0 then
                y = y + 14
            else
                local maxRows = math.min(6, #runtimeParams)
                y = y + (maxRows * 20)
                if #runtimeParams > maxRows then
                    y = y + 12
                end
            end
        end

        y = y + 4

        local headerH = 20
        si.editorHeaderRect = { x = 6, y = y, w = viewW - 12, h = headerH }
        y = y + headerH + 4

        if si.editorCollapsed ~= true then
            local bodyH = math.max(80, math.min(180, viewH - y - ((si.kind == "dsp") and 150 or 40)))
            si.editorBodyRect = { x = 6, y = y, w = viewW - 12, h = bodyH }
            y = y + bodyH + 6
        end

        if si.kind == "dsp" then
            si.graphHeaderRect = { x = 6, y = y, w = viewW - 12, h = headerH }
            y = y + headerH + 4

            if si.graphCollapsed ~= true then
                local bodyH = math.max(90, viewH - y - 8)
                si.graphBodyRect = { x = 6, y = y, w = viewW - 12, h = bodyH }
            end
        end

        if type(self.syncToolSurfaces) == "function" then
            self:syncToolSurfaces()
        end
    end

    function shell:syncToolSurfaces()
        self:syncHostSurfaceFromCanvas("hierarchyTool", {
            kind = "tool",
            backend = "imgui",
            visible = self.mode == "edit" and self.leftPanelMode == "hierarchy",
            panelNode = self.treePanel and self.treePanel.node or nil,
            contentNode = self.treeCanvas,
            z = 40,
            mode = "edit",
            docking = "docked-left",
            payloadKey = "treeRows",
            title = "Hierarchy",
        })

        self:syncHostSurfaceFromCanvas("scriptList", {
            kind = "tool",
            backend = "imgui",
            visible = self.mode == "edit" and self.leftPanelMode == "scripts",
            panelNode = self.treePanel and self.treePanel.node or nil,
            contentNode = self.scriptCanvas,
            z = 40,
            mode = "edit",
            docking = "docked-left",
            payloadKey = "scriptRows",
            title = "Scripts",
        })

        self:syncHostSurfaceFromPanelInsets("inspectorTool", {
            kind = "tool",
            backend = "imgui",
            visible = self.mode == "edit" and self.leftPanelMode == "hierarchy",
            panelNode = self.inspectorPanel and self.inspectorPanel.node or nil,
            insetX = 6,
            insetY = 30,
            insetW = -12,
            insetH = -36,
            z = 40,
            mode = "edit",
            docking = "docked-right",
            payloadKey = "inspectorRows",
            title = "Inspector",
        })

        self:syncHostSurfaceFromCanvas("scriptInspectorTool", {
            kind = "tool",
            backend = "imgui",
            visible = self.mode == "edit" and self.leftPanelMode == "scripts",
            panelNode = self.inspectorPanel and self.inspectorPanel.node or nil,
            contentNode = self.inspectorCanvas,
            z = 40,
            mode = "edit",
            docking = "docked-right",
            payloadKey = "scriptInspector",
            title = "Script Inspector",
        })

        local mainEditorVisible = self.mode == "edit"
            and self.editContentMode == "script"
            and type(self.scriptEditor) == "table"
            and type(self.scriptEditor.path) == "string"
            and self.scriptEditor.path ~= ""
            and type(self.scriptEditor.bodyRect) == "table"
            and (tonumber(self.scriptEditor.bodyRect.w) or 0) > 0
            and (tonumber(self.scriptEditor.bodyRect.h) or 0) > 0

        local mainEditorBounds = { x = 0, y = 0, w = 0, h = 0 }
        if mainEditorVisible and self.mainTabContent ~= nil and self.mainTabContent.getBounds then
            local px, py, _, _ = self.mainTabContent:getBounds()
            local body = self.scriptEditor.bodyRect
            mainEditorBounds = {
                x = math.floor((tonumber(px) or 0) + (tonumber(body.x) or 0)),
                y = math.floor((tonumber(py) or 0) + (tonumber(body.y) or 0)),
                w = math.max(0, math.floor(tonumber(body.w) or 0)),
                h = math.max(0, math.floor(tonumber(body.h) or 0)),
            }
        end
        defineHostSurface(self, "mainScriptEditor", {
            kind = "tool",
            backend = "imgui",
            z = 45,
            mode = "edit",
            docking = "fill",
            payloadKey = "scriptEditor",
            title = "Script Editor",
        }, mainEditorVisible, mainEditorBounds)

        local si = self.scriptInspector or {}
        local inlineVisible = self.mode == "edit"
            and self.leftPanelMode == "scripts"
            and si.editorCollapsed ~= true
            and type(si.path) == "string"
            and si.path ~= ""
            and type(si.editorBodyRect) == "table"
            and (tonumber(si.editorBodyRect.w) or 0) > 0
            and (tonumber(si.editorBodyRect.h) or 0) > 0
            and self.inspectorPanel ~= nil
            and self.inspectorPanel.node ~= nil
            and self.inspectorPanel.node.getBounds ~= nil

        local inlineBounds = { x = 0, y = 0, w = 0, h = 0 }
        if inlineVisible then
            local px, py, _, _ = self.inspectorPanel.node:getBounds()
            local cx, cy, _, _ = self.inspectorCanvas:getBounds()
            local body = si.editorBodyRect
            inlineBounds = {
                x = math.floor((tonumber(px) or 0) + (tonumber(cx) or 0) + (tonumber(body.x) or 0)),
                y = math.floor((tonumber(py) or 0) + (tonumber(cy) or 0) + (tonumber(body.y) or 0)),
                w = math.max(0, math.floor(tonumber(body.w) or 0)),
                h = math.max(0, math.floor(tonumber(body.h) or 0)),
            }
        end
        defineHostSurface(self, "inlineScriptEditor", {
            kind = "tool",
            backend = "imgui",
            z = 46,
            mode = "edit",
            docking = "fill",
            payloadKey = "scriptInspector",
            title = "Inline Script",
        }, inlineVisible, inlineBounds)
    end

    function shell:_isWidgetInTree(canvas)
        if not canvas then
            return false
        end
        for i = 1, #self.treeRows do
            if self.treeRows[i].canvas == canvas then
                return true
            end
        end
        return false
    end

    function shell:_findTreeRowByCanvas(canvas)
        if not canvas then
            return nil
        end
        for i = 1, #self.treeRows do
            if self.treeRows[i].canvas == canvas then
                return self.treeRows[i]
            end
        end
        return nil
    end

    function shell:hitTestWidget(designX, designY)
        for i = #self.treeRows, 1, -1 do
            local row = self.treeRows[i]
            if row.depth > 0 and row.w > 0 and row.h > 0 then
                if designX >= row.x and designX <= (row.x + row.w)
                    and designY >= row.y and designY <= (row.y + row.h) then
                    return row.canvas
                end
            end
        end
        return nil
    end

    function shell:isCanvasSelected(canvas)
        if canvas == nil then
            return false
        end
        for i = 1, #self.selectedWidgets do
            if self.selectedWidgets[i] == canvas then
                return true
            end
        end
        return false
    end

    function shell:setSelection(canvases, primary, recordHistory)
        local beforeSelection = nil
        if recordHistory ~= false and not self.historyApplying then
            beforeSelection = self:_captureSelectionState()
        end

        self.selectedWidgets = {}

        if type(canvases) == "table" then
            for i = 1, #canvases do
                local canvas = canvases[i]
                if canvas ~= nil and self:_isWidgetInTree(canvas) and not self:isCanvasSelected(canvas) then
                    self.selectedWidgets[#self.selectedWidgets + 1] = canvas
                end
            end
        end

        if #self.selectedWidgets == 0 then
            self.selectedWidget = nil
        else
            if primary ~= nil and self:isCanvasSelected(primary) then
                self.selectedWidget = primary
            else
                self.selectedWidget = self.selectedWidgets[#self.selectedWidgets]
            end
        end

        self:_syncInspectorEditors()
        self:_rebuildInspectorRows()
        self.treeCanvas:repaint()
        self.previewOverlay:repaint()
        self.debugLastIdentifier = self:deriveActiveDebugIdentifier()

        if beforeSelection ~= nil then
            local afterSelection = self:_captureSelectionState()
            self:recordHistory("selection", nil, beforeSelection, nil, afterSelection)
        end
    end

    function shell:toggleCanvasSelection(canvas)
        if canvas == nil or not self:_isWidgetInTree(canvas) then
            return
        end

        local nextSelection = {}
        local found = false
        for i = 1, #self.selectedWidgets do
            local c = self.selectedWidgets[i]
            if c == canvas then
                found = true
            else
                nextSelection[#nextSelection + 1] = c
            end
        end

        if found then
            local primary = self.selectedWidget
            if primary == canvas then
                primary = nil
            end
            self:setSelection(nextSelection, primary)
        else
            for i = 1, #self.selectedWidgets do
                nextSelection[#nextSelection + 1] = self.selectedWidgets[i]
            end
            nextSelection[#nextSelection + 1] = canvas
            self:setSelection(nextSelection, canvas)
        end
    end

    function shell:appendConsoleLine(text, colour)
        local c = self.console
        c.lines[#c.lines + 1] = {
            text = tostring(text or ""),
            colour = colour or 0xffcbd5e1,
        }
        while #c.lines > (c.maxLines or 240) do
            table.remove(c.lines, 1)
        end
        c.scrollOffset = 0
        self.consoleOverlay:repaint()
        if c.visible and type(self._syncConsoleOverlayRetained) == "function" then
            self:_syncConsoleOverlayRetained()
        end
    end

    function shell:setConsoleVisible(visible)
        local c = self.console
        local nextVisible = visible == true

        c.visible = nextVisible
        if c.visible then
            local w = self.parentNode:getWidth()
            local h = self.parentNode:getHeight()
            self:layout(w, h)
            self.consoleOverlay:setInterceptsMouse(true, true)
            safeToFront(self.consoleOverlay)
            safeGrabKeyboardFocus(self.consoleOverlay)
            if type(self._syncConsoleOverlayRetained) == "function" then
                self:_syncConsoleOverlayRetained()
            end
            self.consoleOverlay:repaint()
        else
            self.consoleOverlay:setInterceptsMouse(false, false)
            self.consoleOverlay:setBounds(0, 0, 0, 0)
            self.consoleOverlay:clearDisplayList()
        end
    end

    function shell:setDevModeEnabled(enabled)
        local nextEnabled = enabled == true
        if self.devModeEnabled == nextEnabled then
            return
        end

        self.devModeEnabled = nextEnabled

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)

        if self.devModeEnabled then
            self:appendConsoleLine("Dev mode enabled", 0xff86efac)
        else
            self:appendConsoleLine("Dev mode disabled", 0xfffca5a5)
        end
    end

    function shell:toggleConsole()
        self:setConsoleVisible(not (self.console.visible == true))
    end

    function shell:updateConsoleBounds(totalW, totalH)
        local c = self.console
        if c.visible ~= true then
            self.consoleOverlay:setBounds(0, 0, 0, 0)
            return
        end

        local ch = math.max(120, math.floor(totalH * 0.28))
        local cx = self.pad + 8
        local cw = totalW - self.pad * 2 - 16
        local cy = totalH - ch - self.pad - 6

        c.rect = { x = cx, y = cy, w = cw, h = ch }
        self.consoleOverlay:setBounds(cx, cy, cw, ch)
        safeToFront(self.consoleOverlay)
    end

    function shell:deriveActiveDebugIdentifier()
        local out = {}

        if self.leftPanelMode == "scripts" then
            local si = self.scriptInspector or {}
            if si.runtimeInputActive and type(si.runtimeInputEndpointPath) == "string" and si.runtimeInputEndpointPath ~= "" then
                out[#out + 1] = "param:" .. si.runtimeInputEndpointPath
            end
            if type(self.selectedScriptRow) == "table" then
                out[#out + 1] = "script:" .. tostring(self.selectedScriptRow.path or self.selectedScriptRow.name or "")
            end
            if type(self.selectedDspRow) == "table" then
                out[#out + 1] = "dsp:" .. tostring(self.selectedDspRow.path or "")
            end
        end

        local row = self.activeConfigProperty
        if type(row) == "table" and type(row.path) == "string" then
            out[#out + 1] = "property:" .. row.path
        end

        local sel = self.selectedWidget
        if sel ~= nil then
            local meta = sel:getUserData("_editorMeta")
            local nodeType = (type(meta) == "table" and type(meta.type) == "string" and meta.type ~= "") and meta.type or "Canvas"
            local nodeName = deriveNodeName(meta, nodeType)
            out[#out + 1] = "widget:" .. tostring(nodeName)
            out[#out + 1] = "type:" .. tostring(nodeType)
            out[#out + 1] = "canvas:" .. tostring(sel)

            local row = self:_findTreeRowByCanvas(sel)
            if row and type(row.path) == "string" then
                out[#out + 1] = "tree:" .. row.path
            end

            local cfg = (type(meta) == "table") and meta.config or nil
            if type(cfg) == "table" and type(cfg.id) == "string" and cfg.id ~= "" then
                out[#out + 1] = "id:" .. cfg.id
            end

            if type(meta) == "table" and type(meta.callbacks) == "table" then
                local cbKeys = {}
                for k, v in pairs(meta.callbacks) do
                    if type(v) == "function" then
                        cbKeys[#cbKeys + 1] = tostring(k)
                    end
                end
                table.sort(cbKeys)
                if #cbKeys > 0 then
                    out[#out + 1] = "callbacks:" .. table.concat(cbKeys, ",")
                end
            end
        end

        -- Check ImGui direct host (performance mode) if no Canvas selection
        if #out == 0 and getDebugSelectedNodeId then
            local directSelected = getDebugSelectedNodeId()
            if directSelected and directSelected ~= "" then
                out[#out + 1] = "widget:" .. directSelected
                out[#out + 1] = "type:RuntimeNode"
            end
        end

        -- Check ImGui direct host hovered node
        if #out == 0 and getDebugHoveredNodeId then
            local directHovered = getDebugHoveredNodeId()
            if directHovered and directHovered ~= "" then
                out[#out + 1] = "widget:" .. directHovered
                out[#out + 1] = "type:RuntimeNode"
                out[#out + 1] = "(hovered)"
            end
        end

        if #out == 0 then
            return ""
        end

        return table.concat(out, " | ")
    end

    function shell:copyActiveDebugIdentifier()
        if not self.devModeEnabled then
            return false
        end

        local ident = self:deriveActiveDebugIdentifier()
        if ident == "" then
            self:appendConsoleLine("No active identifier to copy.", 0xfffca5a5)
            return false
        end

        self.debugLastIdentifier = ident
        if setClipboardText then
            setClipboardText(ident)
        end
        self:appendConsoleLine("copied: " .. ident, 0xff86efac)
        return true
    end

    function shell:pasteClipboardIntoConsole()
        if not self.devModeEnabled then
            return false
        end
        if getClipboardText == nil then
            return false
        end

        local text = tostring(getClipboardText() or "")
        if text == "" then
            return false
        end

        self:setConsoleVisible(true)
        self.console.input = text
        self.console.historyIndex = 0
        if type(self._syncConsoleOverlayRetained) == "function" then
            self:_syncConsoleOverlayRetained()
        end
        self.consoleOverlay:repaint()
        return true
    end

    function shell:applyWheelListScroll(currentScroll, deltaY, rowHeight, itemCount, viewportH, rowsPerTick)
        local contentHeight = (itemCount or 0) * (rowHeight or 1)
        local maxScroll = math.max(0, contentHeight - (viewportH or 0))
        if maxScroll <= 0 then
            return currentScroll, false
        end

        local sign = deltaY > 0 and -1 or 1
        local ticks = math.max(1, math.floor(math.abs(deltaY) + 0.5))
        local rows = rowsPerTick or self.listWheelRows or 1
        local amount = sign * ticks * (rowHeight or 1) * rows
        local nextScroll = clamp((currentScroll or 0) + amount, 0, maxScroll)
        return nextScroll, nextScroll ~= currentScroll
    end

    function shell:executeConsoleCommand(line)
        local src = tostring(line or "")
        local trimmed = src:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            return
        end

        self.console.history[#self.console.history + 1] = trimmed
        self.console.historyIndex = 0
        self:appendConsoleLine("> " .. trimmed, 0xff93c5fd)

        local words = splitConsoleWords(trimmed)
        local cmd = string.lower(words[1] or "")

        if cmd == "help" then
            self:appendConsoleLine("help | clear | get <path> | set <path> <value> | trigger <path>")
            self:appendConsoleLine("undo | redo | sel | copyid [on|off|toggle] | dev [on|off|toggle]")
            self:appendConsoleLine("renderer [toggle|imgui-direct|imgui-overlay|imgui-replace] | perf [on|off|toggle|tab|reset]")
            self:appendConsoleLine("ui <scriptPath> | lua <expr>")
            return
        elseif cmd == "clear" then
            self.console.lines = {}
            self.console.scrollOffset = 0
            if self.console.visible and type(self._syncConsoleOverlayRetained) == "function" then
                self:_syncConsoleOverlayRetained()
            end
            self.consoleOverlay:repaint()
            return
        elseif cmd == "get" then
            local path = words[2]
            if type(path) ~= "string" or path == "" then
                self:appendConsoleLine("ERR: get requires path", 0xfffca5a5)
                return
            end
            if type(getParam) == "function" then
                local value = getParam(path)
                self:appendConsoleLine(path .. " = " .. valueToText(value), 0xffc4b5fd)
            else
                self:appendConsoleLine("ERR: getParam unavailable", 0xfffca5a5)
            end
            return
        elseif cmd == "set" then
            local path = words[2]
            local rawValue = words[3]
            if type(path) ~= "string" or path == "" or rawValue == nil then
                self:appendConsoleLine("ERR: set <path> <value>", 0xfffca5a5)
                return
            end
            local value = parseConsoleScalar(rawValue)
            local ok = false
            if type(setParam) == "function" then
                ok = setParam(path, value)
            end
            if ok then
                self:appendConsoleLine("ok: " .. path .. " = " .. valueToText(value), 0xff86efac)
            else
                self:appendConsoleLine("ERR: set failed for " .. path, 0xfffca5a5)
            end
            return
        elseif cmd == "trigger" then
            local path = words[2]
            if type(path) ~= "string" or path == "" then
                self:appendConsoleLine("ERR: trigger requires path", 0xfffca5a5)
                return
            end
            local ok = false
            if type(triggerParam) == "function" then
                ok = triggerParam(path)
            elseif type(command) == "function" then
                command("TRIGGER", path)
                ok = true
            end
            if ok then
                self:appendConsoleLine("ok: trigger " .. path, 0xff86efac)
            else
                self:appendConsoleLine("ERR: trigger failed for " .. path, 0xfffca5a5)
            end
            return
        elseif cmd == "undo" then
            self:undo()
            self:appendConsoleLine("undo")
            return
        elseif cmd == "redo" then
            self:redo()
            self:appendConsoleLine("redo")
            return
        elseif cmd == "sel" or cmd == "id" then
            local ident = self:deriveActiveDebugIdentifier()
            if ident == "" then
                ident = "(none)"
            end
            self:appendConsoleLine(ident, 0xffc4b5fd)
            return
        elseif cmd == "copyid" then
            local argRaw = words[2]
            local arg = string.lower(argRaw or "")

            if arg == "" or arg == "status" then
                local enabled = isCopyIdModeEnabled and isCopyIdModeEnabled() or false
                self:appendConsoleLine("copyid mode: " .. (enabled and "on" or "off"), 0xff86efac)
                self:appendConsoleLine("usage: copyid on | copyid off | copyid toggle")
                self:appendConsoleLine("When on: click any widget to copy its ID to clipboard")
                return
            elseif arg == "on" then
                if setCopyIdModeEnabled then setCopyIdModeEnabled(true) end
                self:appendConsoleLine("copyid mode ON - click any widget to copy its ID", 0xff86efac)
            elseif arg == "off" then
                if setCopyIdModeEnabled then setCopyIdModeEnabled(false) end
                self:appendConsoleLine("copyid mode OFF", 0xfffca5a5)
            elseif arg == "toggle" then
                local current = isCopyIdModeEnabled and isCopyIdModeEnabled() or false
                if setCopyIdModeEnabled then setCopyIdModeEnabled(not current) end
                local enabled = isCopyIdModeEnabled and isCopyIdModeEnabled() or false
                self:appendConsoleLine("copyid mode: " .. (enabled and "on" or "off"), enabled and 0xff86efac or 0xfffca5a5)
            else
                -- Legacy: just copy current selection
                self:copyActiveDebugIdentifier()
            end
            return
        elseif cmd == "dev" then
            local argRaw = words[2]
            local arg = string.lower(argRaw or "")

            if arg == "" or arg == "status" then
                self:appendConsoleLine("dev mode: " .. (self.devModeEnabled and "on" or "off"), 0xff86efac)
                self:appendConsoleLine("usage: dev on | dev off | dev toggle")
                return
            elseif arg == "on" then
                self:setDevModeEnabled(true)
            elseif arg == "off" then
                self:setDevModeEnabled(false)
            elseif arg == "toggle" then
                self:setDevModeEnabled(not self.devModeEnabled)
            else
                self:appendConsoleLine("ERR: usage dev on|off|toggle", 0xfffca5a5)
                return
            end

            self:appendConsoleLine("dev mode: " .. (self.devModeEnabled and "on" or "off"), 0xff86efac)
            return
        elseif cmd == "renderer" or cmd == "render" or cmd == "imgui" then
            local argRaw = words[2]
            local arg = string.lower(argRaw or "")
            local currentMode = "imgui-direct"
            if type(getUIRendererMode) == "function" then
                currentMode = tostring(getUIRendererMode() or "imgui-direct")
            end

            if arg == "" or arg == "status" then
                self:appendConsoleLine("renderer: " .. currentMode, 0xff86efac)
                self:appendConsoleLine("usage: renderer toggle | renderer imgui-direct | renderer imgui-overlay | renderer imgui-replace")
                self:appendConsoleLine("note: canvas is legacy and slated for removal", 0xfffbbf24)
                return
            end

            local targetMode = arg
            if arg == "toggle" then
                if currentMode == "imgui-direct" then
                    targetMode = "imgui-replace"
                else
                    targetMode = "imgui-direct"
                end
            elseif arg == "direct" then
                targetMode = "imgui-direct"
            elseif arg == "overlay" or arg == "imgui" then
                targetMode = "imgui-overlay"
            elseif arg == "replace" or arg == "full" then
                targetMode = "imgui-replace"
            elseif arg == "canvas" then
                self:appendConsoleLine("ERR: canvas renderer is deprecated and not a supported shell target", 0xfffca5a5)
                return
            end

            if type(setUIRendererMode) ~= "function" then
                self:appendConsoleLine("ERR: setUIRendererMode unavailable", 0xfffca5a5)
                return
            end

            local ok = setUIRendererMode(targetMode)
            if not ok then
                self:appendConsoleLine("ERR: renderer [toggle|imgui-direct|imgui-overlay|imgui-replace]", 0xfffca5a5)
                return
            end

            self:appendConsoleLine("renderer queued: " .. targetMode, 0xff86efac)
            return
        elseif cmd == "perf" then
            local arg = string.lower(words[2] or "toggle")
            local activeTab = string.lower(words[3] or "")
            self.perfOverlay = self.perfOverlay or { visible = false, activeTab = "frame" }

            if arg == "" or arg == "toggle" then
                self:setPerfOverlayVisible(not (self.perfOverlay.visible == true))
            elseif arg == "on" then
                self:setPerfOverlayVisible(true)
            elseif arg == "off" then
                self:setPerfOverlayVisible(false)
            elseif arg == "tab" then
                if activeTab == "frame" or activeTab == "imgui" or activeTab == "editor" or activeTab == "ui" then
                    self:setPerfOverlayActiveTab(activeTab)
                    self:setPerfOverlayVisible(true)
                else
                    self:appendConsoleLine("ERR: perf tab <frame|imgui|editor|ui>", 0xfffca5a5)
                    return
                end
            elseif arg == "reset" then
                self:setPerfOverlayVisible(true)
                if type(command) == "function" then
                    command("RESET_PEAKS")
                end
                if type(_G) == "table" then
                    local perf = _G.__manifoldEditorPerf or {}
                    perf.peakDrawMs = 0
                    perf.peakWheelMs = 0
                    perf.peakKeypressMs = 0
                    perf.peakEnsureVisibleMs = 0
                    perf.peakPosFromPointMs = 0
                    _G.__manifoldEditorPerf = perf
                end
                self:appendConsoleLine("perf peaks reset", 0xff86efac)
            else
                self:appendConsoleLine("ERR: perf [on|off|toggle|tab <name>|reset]", 0xfffca5a5)
                return
            end

            self.consoleOverlay:repaint()
            self:appendConsoleLine("perf overlay: " .. (self.perfOverlay.visible and "on" or "off") .. " tab=" .. tostring(self.perfOverlay.activeTab or "frame"), 0xff86efac)
            return
        elseif cmd == "ui" then
            local target = words[2]
            if type(target) == "string" and target ~= "" and type(switchUiScript) == "function" then
                self:stashRestoreStateForScriptSwitch()
                switchUiScript(target)
                self:appendConsoleLine("switching ui: " .. target, 0xff86efac)
            else
                self:appendConsoleLine("ERR: ui <scriptPath>", 0xfffca5a5)
            end
            return
        elseif cmd == "lua" then
            local expr = trimmed:match("^%s*lua%s+(.+)$")
            if type(expr) ~= "string" or expr == "" then
                self:appendConsoleLine("ERR: lua <expr>", 0xfffca5a5)
                return
            end
            local chunk, loadErr = load("return " .. expr, "console", "t", _ENV)
            if chunk == nil then
                chunk, loadErr = load(expr, "console", "t", _ENV)
            end
            if chunk == nil then
                self:appendConsoleLine("ERR: " .. tostring(loadErr), 0xfffca5a5)
                return
            end
            local ok, result = pcall(chunk)
            if ok then
                self:appendConsoleLine(valueToText(result), 0xff86efac)
            else
                self:appendConsoleLine("ERR: " .. tostring(result), 0xfffca5a5)
            end
            return
        end

        self:appendConsoleLine("ERR: unknown command '" .. cmd .. "'", 0xfffca5a5)
    end

    function shell:handleConsoleKeyPress(keyCode, charCode, shift, ctrl, alt)
        local _ = shift
        _ = alt

        if self.console.visible ~= true then
            return false
        end

        local c = self.console
        local k = keyCode or 0
        local ch = charCode or 0

        local function refreshConsole()
            self.consoleOverlay:repaint()
            if type(self._syncConsoleOverlayRetained) == "function" then
                self:_syncConsoleOverlayRetained()
            end
        end

        if k == 27 then
            self:setConsoleVisible(false)
            return true
        end

        if ctrl and seIsLetterShortcut(k, ch, "v") and getClipboardText then
            c.input = c.input .. tostring(getClipboardText() or "")
            refreshConsole()
            return true
        end

        if k == 13 or k == 10 then
            local line = c.input
            c.input = ""
            self:executeConsoleCommand(line)
            refreshConsole()
            return true
        end

        if k == 8 then
            c.input = string.sub(c.input or "", 1, math.max(0, #(c.input or "") - 1))
            refreshConsole()
            return true
        end

        local isUp = (k == 63232 or k == 30 or k == 38)
        local isDown = (k == 63233 or k == 31 or k == 40)
        local isPageUp = (k == 63276 or k == 33)
        local isPageDown = (k == 63277 or k == 34)

        if isUp then
            local count = #c.history
            if count > 0 then
                if c.historyIndex == 0 then
                    c.historyIndex = count
                else
                    c.historyIndex = math.max(1, c.historyIndex - 1)
                end
                c.input = c.history[c.historyIndex] or ""
                refreshConsole()
            end
            return true
        elseif isDown then
            local count = #c.history
            if count > 0 and c.historyIndex > 0 then
                c.historyIndex = math.min(count, c.historyIndex + 1)
                c.input = c.history[c.historyIndex] or ""
                refreshConsole()
            end
            return true
        elseif isPageUp then
            c.scrollOffset = math.min(#c.lines, (c.scrollOffset or 0) + 6)
            refreshConsole()
            return true
        elseif isPageDown then
            c.scrollOffset = math.max(0, (c.scrollOffset or 0) - 6)
            refreshConsole()
            return true
        end

        if ch >= 32 and ch <= 126 then
            c.input = (c.input or "") .. string.char(ch)
            refreshConsole()
            return true
        elseif k >= 32 and k <= 126 then
            c.input = (c.input or "") .. string.char(k)
            refreshConsole()
            return true
        end

        return false
    end

    function shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt)
        if (not ctrl) and (not alt) and isBacktickOrTildeKey(keyCode or 0, charCode or 0) then
            self:toggleConsole()
            return true
        end

        if self.console.visible then
            return self:handleConsoleKeyPress(keyCode, charCode, shift, ctrl, alt)
        end

        if not self.devModeEnabled then
            return false
        end

        if ctrl and shift and seIsLetterShortcut(keyCode or 0, charCode or 0, "c") then
            self:copyActiveDebugIdentifier()
            return true
        end

        if ctrl and shift and seIsLetterShortcut(keyCode or 0, charCode or 0, "v") then
            self:pasteClipboardIntoConsole()
            return true
        end

        return false
    end

    function shell:refreshDspRows(params)
        self.dspRows = {}

        local p = params
        if type(p) ~= "table" then
            return
        end

        local keys = {}
        for k, _ in pairs(p) do
            if type(k) == "string" then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys)

        for i = 1, #keys do
            local key = keys[i]
            local value = p[key]
            local t = type(value)
            if t == "number" or t == "boolean" or t == "string" then
                self.dspRows[#self.dspRows + 1] = {
                    path = key,
                    value = valueToText(value),
                }
            end
        end

        local maxScroll = math.max(0, #self.dspRows * self.dspRowHeight - self.dspViewportH)
        self.dspScrollY = clamp(self.dspScrollY, 0, maxScroll)
    end

    function shell:refreshScriptRows()
        local perfStartMs = shellPerfNowMs()
        self.scriptRows = {}

        local currentUi = getCurrentScriptPath and getCurrentScriptPath() or ""
        local editingPath = self.scriptEditor and self.scriptEditor.path or ""

        local projectFiles = nil
        if type(getStructuredUiProjectFiles) == "function" then
            local ok, result = pcall(getStructuredUiProjectFiles)
            if ok and type(result) == "table" and #result > 0 then
                projectFiles = result
            end
        end

        if projectFiles ~= nil then
            local lastGroup = nil
            for i = 1, #projectFiles do
                local row = projectFiles[i]
                if type(row) == "table" then
                    local group = row.group or "Project Files"
                    if group ~= lastGroup then
                        self.scriptRows[#self.scriptRows + 1] = { section = true, label = group }
                        lastGroup = group
                    end

                    local path = row.path or ""
                    local kind = row.kind or "ui"
                    local name = row.name or fileStem(path) or "(unnamed)"
                    self.scriptRows[#self.scriptRows + 1] = {
                        kind = kind,
                        sourceKind = "project-file",
                        sourceScope = "project",
                        ownership = (kind == "ui" and string.match(path, "%.ui%.lua$")) and "editor-owned" or "",
                        name = name,
                        path = path,
                        dirty = row.dirty == true,
                        active = (path == currentUi) or (path == editingPath),
                    }
                end
            end

            if #self.scriptRows == 0 then
                self.scriptRows[#self.scriptRows + 1] = {
                    section = false,
                    nonInteractive = true,
                    kind = "hint",
                    name = "No project files",
                    path = "",
                    active = false,
                }
            end
        else
            self.scriptRows[#self.scriptRows + 1] = { section = true, label = "UI Scripts" }
            local uiScripts = listUiScripts and listUiScripts() or {}
            local uiCount = 0

            for i = 1, #uiScripts do
                local s = uiScripts[i]
                if type(s) == "table" then
                    local path = s.path or ""
                    local name = s.name or fileStem(path) or "(unnamed)"
                    local include = false
                    local sourceKind = s.kind or "script"
                    local sourceScope = s.scope or ""

                    -- Include projects (including Settings), active scripts, and system/user scripts
                    if sourceKind == "project" then
                        include = true
                    elseif path ~= "" and (path == currentUi or path == editingPath) then
                        include = true
                    elseif sourceScope == "user" or sourceScope == "system" then
                        include = true
                    elseif not scriptLooksSettings(name, path) and scriptLooksGlobal(name, path) then
                        include = true
                    end

                    if include then
                        self.scriptRows[#self.scriptRows + 1] = {
                            kind = "ui",
                            sourceKind = sourceKind,
                            sourceScope = sourceScope,
                            name = name,
                            path = path,
                            active = (path == currentUi),
                        }
                        uiCount = uiCount + 1
                    end
                end
            end

            if uiCount == 0 then
                self.scriptRows[#self.scriptRows + 1] = {
                    section = false,
                    nonInteractive = true,
                    kind = "hint",
                    name = "No loaded/global UI scripts",
                    path = "",
                    active = false,
                }
            end

            self.scriptRows[#self.scriptRows + 1] = { section = true, label = "DSP Scripts" }
            local dspScripts = listDspScripts and listDspScripts() or {}
            local activeSlots = collectActiveSlotHints(self.stateParamsCache)
            local uiContextHints = collectUiContextHints(currentUi)
            local dspCount = 0

            for i = 1, #dspScripts do
                local s = dspScripts[i]
                if type(s) == "table" then
                    local path = s.path or ""
                    local name = s.name or fileStem(path) or "(unnamed)"
                    local include = false
                    local slotMatch = scriptMatchesActiveSlot(name, activeSlots)
                    local contextMatch = scriptMatchesUiContext(name, path, uiContextHints)

                    if not scriptLooksSettings(name, path) then
                        if path ~= "" and path == editingPath then
                            include = true
                        elseif scriptLooksGlobal(name, path) then
                            include = true
                        elseif contextMatch and slotMatch then
                            include = true
                        elseif currentUi ~= "" and contextMatch then
                            include = true
                        elseif currentUi == "" and slotMatch then
                            include = true
                        end
                    end

                    if include then
                        self.scriptRows[#self.scriptRows + 1] = {
                            kind = "dsp",
                            name = name,
                            path = path,
                            active = (self.scriptEditor.kind == "dsp" and path == editingPath),
                        }
                        dspCount = dspCount + 1
                    end
                end
            end

            if dspCount == 0 then
                self.scriptRows[#self.scriptRows + 1] = {
                    section = false,
                    nonInteractive = true,
                    kind = "hint",
                    name = "No loaded/global DSP scripts",
                    path = "",
                    active = false,
                }
            end
        end

        local hasSelected = false
        if type(self.selectedScriptRow) == "table" then
            for i = 1, #self.scriptRows do
                local row = self.scriptRows[i]
                if not row.section and not row.nonInteractive and row.path == self.selectedScriptRow.path and row.kind == self.selectedScriptRow.kind then
                    hasSelected = true
                    break
                end
            end
        end
        if not hasSelected then
            self.selectedScriptRow = nil
            self:refreshScriptInspectorData(nil)
        end

        local maxScroll = math.max(0, #self.scriptRows * self.scriptRowHeight - self.scriptViewportH)
        self.scriptScrollY = clamp(self.scriptScrollY, 0, maxScroll)
        self.scriptRowsLastRefreshAt = nowSeconds()
        -- Logging removed to reduce console spam
    end

    function shell:refreshScriptInspectorData(row)
        local perfStartMs = shellPerfNowMs()
        local si = self.scriptInspector
        if type(row) ~= "table" or row.section or row.nonInteractive then
            si.kind = ""
            si.name = ""
            si.path = ""
            si.ownership = ""
            si.text = ""
            si.dirty = false
            si.syncToken = (tonumber(si.syncToken) or 0) + 1
            seInvalidateCache(si)
            si.params = {}
            si.runtimeParams = {}
            si.graph = { nodes = {}, edges = {} }
            si.runtimeStatus = ""
            si.runButtonRect = nil
            si.stopButtonRect = nil
            si.runtimeParamRows = {}
            si.runtimeInputActive = false
            si.runtimeInputEndpointPath = ""
            si.runtimeInputText = ""
            si.runtimeInputMin = nil
            si.runtimeInputMax = nil
            si.runtimeSliderDragActive = false
            si.runtimeSliderDragEndpointPath = ""
            si.runtimeSliderDragRect = nil
            si.runtimeSliderDragMin = nil
            si.runtimeSliderDragMax = nil
            si.runtimeSliderDragStep = nil
            si.runtimeSliderDragLastValue = nil
            si.runtimeSliderDragLastApplyAt = -1
            si.runtimeSliderDragLastUiRepaintAt = -1
            si.editorScrollRow = 1
            si.editorHeaderRect = nil
            si.editorBodyRect = nil
            si.graphHeaderRect = nil
            si.graphBodyRect = nil
            si.graphDragging = false
            self.runtimeParamsLastRefreshAt = -1
            self:hideRuntimeParamControls(1)
            self:computeScriptInspectorGeometry()
            return
        end

        local text = ""
        if readTextFile and type(row.path) == "string" and row.path ~= "" then
            text = readTextFile(row.path) or ""
        end

        si.kind = row.kind or ""
        si.name = row.name or fileStem(row.path or "")
        si.path = row.path or ""
        si.ownership = row.ownership or ""
        si.text = text
        si.dirty = false
        si.syncToken = (tonumber(si.syncToken) or 0) + 1
        seInvalidateCache(si)
        si.params = {}
        si.runtimeParams = {}
        si.graph = { nodes = {}, edges = {} }
        si.runtimeStatus = ""
        si.runButtonRect = nil
        si.stopButtonRect = nil
        si.runtimeParamRows = {}
        si.runtimeInputActive = false
        si.runtimeInputEndpointPath = ""
        si.runtimeInputText = ""
        si.runtimeInputMin = nil
        si.runtimeInputMax = nil
        si.runtimeSliderDragActive = false
        si.runtimeSliderDragEndpointPath = ""
        si.runtimeSliderDragRect = nil
        si.runtimeSliderDragMin = nil
        si.runtimeSliderDragMax = nil
        si.runtimeSliderDragStep = nil
        si.runtimeSliderDragLastValue = nil
        si.runtimeSliderDragLastApplyAt = -1
        si.runtimeSliderDragLastUiRepaintAt = -1
        si.editorScrollRow = 1
        self.runtimeParamsLastRefreshAt = -1
        self:hideRuntimeParamControls(1)

        if si.kind == "dsp" then
            si.params = parseDspParamDefsFromCode(text)
            si.runtimeParams = collectRuntimeParamsForScript(row, self.stateParamsCache, si.params, self.dspPreviewSlotName)
            si.graph = parseDspGraphFromCode(text)
        end

        self:computeScriptInspectorGeometry()
    end

    function shell:refreshScriptInspectorRuntimeParams()
        local si = self.scriptInspector
        if type(si) ~= "table" or si.kind ~= "dsp" then
            return
        end
        if type(self.selectedScriptRow) ~= "table" then
            si.runtimeParams = {}
            self.runtimeParamsLastRefreshAt = nowSeconds()
            self:computeScriptInspectorGeometry()
            return
        end
        si.runtimeParams = collectRuntimeParamsForScript(self.selectedScriptRow, self.stateParamsCache, si.params, self.dspPreviewSlotName)
        self.runtimeParamsLastRefreshAt = nowSeconds()
        self:computeScriptInspectorGeometry()
    end

    function shell:hideRuntimeParamControls(fromIndex)
        local si = self.scriptInspector
        local controls = si.runtimeParamControls or {}
        local first = math.max(1, tonumber(fromIndex) or 1)
        for i = first, #controls do
            local c = controls[i]
            if c then
                c.row = nil
                if c.minus and c.minus.node then
                    c.minus:setEnabled(false)
                    setWidgetBounds(c.minus, 0, 0, 0, 0)
                end
                if c.slider and c.slider.node then
                    c.slider:setEnabled(false)
                    setWidgetBounds(c.slider, 0, 0, 0, 0)
                end
                if c.plus and c.plus.node then
                    c.plus:setEnabled(false)
                    setWidgetBounds(c.plus, 0, 0, 0, 0)
                end
            end
        end
    end

    function shell:ensureRuntimeParamControlPool(count)
        local needed = math.max(0, tonumber(count) or 0)
        local si = self.scriptInspector
        si.runtimeParamControls = si.runtimeParamControls or {}

        while #si.runtimeParamControls < needed do
            local idx = #si.runtimeParamControls + 1
            local control = { row = nil }

            control.minus = W.Button.new(self.inspectorCanvas, "insRtMinus" .. tostring(idx), {
                label = "-",
                bg = 0xff1e293b,
                textColour = 0xffcbd5e1,
                fontSize = 9.0,
                radius = 3,
                on_click = function()
                    local row = control.row
                    if row and row.active then
                        self:nudgeRuntimeParam(row.endpointPath, -1, row.min, row.max, row.step)
                    end
                end,
            })

            control.slider = RuntimeParamSlider.new(self.inspectorCanvas, "insRtSlider" .. tostring(idx), {
                min = 0,
                max = 1,
                value = 0,
                step = 0,
                on_change = function(v)
                    local row = control.row
                    if not row or not row.active then
                        return
                    end
                    self:setRuntimeParamAbsolute(row.endpointPath, v, row.min, row.max, {
                        step = row.step,
                        fast = true,
                        noRepaint = true,
                        suppressStatus = true,
                    })
                    self.inspectorCanvas:repaint()
                end,
                on_ctrl_click = function(v)
                    local row = control.row
                    if not row or not row.active then
                        return
                    end
                    si.runtimeInputActive = true
                    si.runtimeInputEndpointPath = row.endpointPath or ""
                    si.runtimeInputText = tostring(v or row.value or 0)
                    si.runtimeInputMin = row.min
                    si.runtimeInputMax = row.max
                    self.inspectorCanvas:grabKeyboardFocus()
                    self.inspectorCanvas:repaint()
                end,
                on_drag_state = function(active)
                    si.runtimeSliderDragActive = active == true
                    if not si.runtimeSliderDragActive then
                        self:refreshScriptInspectorRuntimeParams()
                        self.inspectorCanvas:repaint()
                    end
                end,
            })

            control.plus = W.Button.new(self.inspectorCanvas, "insRtPlus" .. tostring(idx), {
                label = "+",
                bg = 0xff1e293b,
                textColour = 0xffcbd5e1,
                fontSize = 9.0,
                radius = 3,
                on_click = function()
                    local row = control.row
                    if row and row.active then
                        self:nudgeRuntimeParam(row.endpointPath, 1, row.min, row.max, row.step)
                    end
                end,
            })

            control.minus:setEnabled(false)
            control.slider:setEnabled(false)
            control.plus:setEnabled(false)

            si.runtimeParamControls[#si.runtimeParamControls + 1] = control
        end
    end

    function shell:runSelectedDspScriptForInspector()
        local row = self.selectedScriptRow
        local si = self.scriptInspector
        if type(row) ~= "table" or row.kind ~= "dsp" or (row.path or "") == "" then
            return
        end

        local slot = self.dspPreviewSlotName or "editor_preview"
        local ok = false

        if setDspSlotPersistOnUiSwitch then
            pcall(setDspSlotPersistOnUiSwitch, slot, false)
        end

        if loadDspScriptInSlot then
            ok = loadDspScriptInSlot(row.path, slot)
        elseif loadDspScript then
            ok = loadDspScript(row.path)
        end

        if ok then
            si.runtimeStatus = "DSP loaded: " .. (row.name or fileStem(row.path))
        else
            local err = getDspScriptLastError and getDspScriptLastError() or ""
            si.runtimeStatus = "DSP load failed" .. ((err ~= "") and (": " .. err) or "")
        end

        self:refreshScriptInspectorRuntimeParams()
        self:computeScriptInspectorGeometry()
        self.inspectorCanvas:repaint()
    end

    function shell:stopSelectedDspScriptForInspector()
        local si = self.scriptInspector
        local slot = self.dspPreviewSlotName or "editor_preview"
        local ok = false

        if unloadDspSlot then
            ok = unloadDspSlot(slot)
        end

        if ok then
            si.runtimeStatus = "DSP preview slot unloaded"
        else
            si.runtimeStatus = "No preview slot to unload"
        end

        self:refreshScriptInspectorRuntimeParams()
        self:computeScriptInspectorGeometry()
        self.inspectorCanvas:repaint()
    end

    function shell:setScriptInspectorEditorCollapsed(collapsed)
        local si = self.scriptInspector
        if type(si) ~= "table" then
            return
        end
        si.editorCollapsed = collapsed == true
        self:computeScriptInspectorGeometry()
        self.inspectorCanvas:repaint()
    end

    function shell:setScriptInspectorGraphCollapsed(collapsed)
        local si = self.scriptInspector
        if type(si) ~= "table" then
            return
        end
        si.graphCollapsed = collapsed == true
        if si.graphCollapsed then
            si.graphDragging = false
        end
        self:computeScriptInspectorGeometry()
        self.inspectorCanvas:repaint()
    end

    function shell:setScriptInspectorGraphPan(x, y)
        local si = self.scriptInspector
        if type(si) ~= "table" then
            return
        end
        si.graphPanX = math.floor(tonumber(x) or 0)
        si.graphPanY = math.floor(tonumber(y) or 0)
        self.inspectorCanvas:repaint()
    end

    function shell:applyScriptInspectorRuntimeParam(endpointPath, value)
        local si = self.scriptInspector
        if type(si) ~= "table" or type(endpointPath) ~= "string" or endpointPath == "" then
            return false
        end

        local runtimeParams = si.runtimeParams or {}
        for i = 1, #runtimeParams do
            local rp = runtimeParams[i]
            local candidate = rp.endpointPath or rp.path
            if candidate == endpointPath then
                return self:setRuntimeParamAbsolute(endpointPath, value, rp.min, rp.max, {
                    step = rp.step,
                    fast = true,
                })
            end
        end

        return self:setRuntimeParamAbsolute(endpointPath, value, nil, nil, { fast = true })
    end

    function shell:updateRuntimeParamCache(endpointPath, value)
        local si = self.scriptInspector
        if type(si) ~= "table" then
            return
        end

        for i = 1, #(si.runtimeParams or {}) do
            local rp = si.runtimeParams[i]
            if (rp.endpointPath or rp.path) == endpointPath then
                rp.numericValue = value
                rp.value = formatRuntimeValue(value)
                rp.active = true
            end
        end

        for i = 1, #(si.runtimeParamRows or {}) do
            local rr = si.runtimeParamRows[i]
            if rr.endpointPath == endpointPath then
                rr.value = value
                rr.active = true
            end
        end
    end

    function shell:setRuntimeParamAbsolute(endpointPath, value, minV, maxV, opts)
        if type(endpointPath) ~= "string" or endpointPath == "" then
            return false
        end
        if type(setParam) ~= "function" then
            return false
        end

        opts = opts or {}

        local lo = tonumber(minV)
        local hi = tonumber(maxV)
        local step = tonumber(opts.step)
        local nextValue = tonumber(value)
        if nextValue == nil then
            self.scriptInspector.runtimeStatus = "Invalid value"
            self:computeScriptInspectorGeometry()
            return false
        end

        if step ~= nil and step > 0 then
            if lo ~= nil then
                nextValue = lo + math.floor(((nextValue - lo) / step) + 0.5) * step
            else
                nextValue = math.floor((nextValue / step) + 0.5) * step
            end
        end

        if lo ~= nil and hi ~= nil then
            nextValue = clamp(nextValue, lo, hi)
        end

        local ok = setParam(endpointPath, nextValue)
        if not ok then
            self.scriptInspector.runtimeStatus = "setParam failed: " .. endpointPath
            self:computeScriptInspectorGeometry()
            return false
        end

        if not opts.suppressStatus then
            self.scriptInspector.runtimeStatus = string.format("set %s = %.4f", endpointPath, nextValue)
        end

        if opts.fast then
            self:updateRuntimeParamCache(endpointPath, nextValue)
        else
            self:refreshScriptInspectorRuntimeParams()
        end

        self:computeScriptInspectorGeometry()

        if not opts.noRepaint then
            self.inspectorCanvas:repaint()
        end

        return true
    end

    function shell:nudgeRuntimeParam(endpointPath, delta, minV, maxV, stepV)
        if type(endpointPath) ~= "string" or endpointPath == "" then
            return
        end

        local current = 0.0
        if type(getParam) == "function" then
            current = getParam(endpointPath) or 0.0
        end

        local lo = tonumber(minV)
        local hi = tonumber(maxV)
        local step = tonumber(stepV)

        if step == nil or step <= 0 then
            local span = nil
            if lo ~= nil and hi ~= nil then
                span = math.abs(hi - lo)
            end

            if span ~= nil then
                if span <= 2.0 then
                    step = 0.01
                elseif span <= 20.0 then
                    step = 0.1
                else
                    step = span / 100.0
                end
            else
                step = math.max(0.01, math.abs(current) * 0.05)
            end
        end

        local nextValue = current + (delta * step)
        self:setRuntimeParamAbsolute(endpointPath, nextValue, lo, hi, {
            step = step,
            fast = true,
        })
    end

    function shell:handleLeftListSelection(kind, row, openFn)
        if type(row) ~= "table" then
            return
        end

        local key = kind .. ":" .. tostring(row.path or row.name or "")
        local t = nowSeconds()
        local isDouble = (self.leftListLastClickKey == key) and ((t - self.leftListLastClickAt) <= self.doubleClickWindow)
        self.leftListLastClickKey = key
        self.leftListLastClickAt = t

        if kind == "dsp" then
            self.selectedDspRow = row
            self.selectedScriptRow = nil
            self.dspCanvas:repaint()
            self.scriptCanvas:repaint()
        elseif kind == "script" then
            self.selectedScriptRow = row
            self.selectedDspRow = nil
            self:refreshScriptInspectorData(row)
            self.scriptCanvas:repaint()
            self.dspCanvas:repaint()
        end

        self:_rebuildInspectorRows()
        self.debugLastIdentifier = self:deriveActiveDebugIdentifier()

        if isDouble and type(openFn) == "function" then
            openFn()
        end
    end

    function shell:publishUiStateToGlobals()
        if type(_G) ~= "table" then
            return
        end
        _G.__manifoldShellMode = self.mode
        _G.__manifoldShellLeftPanelMode = self.leftPanelMode
        _G.__manifoldShellGetMode = function()
            return self.mode, self.leftPanelMode
        end
    end

    function shell:setLeftPanelMode(mode)
        if mode ~= "hierarchy" and mode ~= "scripts" then
            return
        end

        if self.leftPanelMode == mode then
            return
        end

        self.leftPanelMode = mode
        self:publishUiStateToGlobals()

        if mode == "hierarchy" then
            self.treeLabel:setText("Hierarchy")
            self:refreshTree(true)
            self.editContentMode = "preview"
            self.scriptEditor.focused = false
        else
            self.treeLabel:setText("Scripts")
            self:refreshScriptRows()
            self:refreshScriptInspectorData(self.selectedScriptRow)
        end

        self:_rebuildInspectorRows()

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)

        self.treeCanvas:repaint()
        self.scriptCanvas:repaint()
    end

    function shell:_findMainTabById(tabId)
        for i = 1, #self.mainTabs do
            local t = self.mainTabs[i]
            if t.id == tabId then
                return t, i
            end
        end
        return nil, nil
    end

    function shell:stashRestoreStateForScriptSwitch()
        if type(_G) ~= "table" then
            return
        end
        _G.__manifoldShellRestore = {
            mode = self.mode,
            leftPanelMode = self.leftPanelMode,
        }
    end

    function shell:applyPendingRestoreState()
        if self.pendingRestoreApplied or self.pendingRestoreMode == nil then
            return
        end

        local restoreMode = self.pendingRestoreMode
        local restorePanel = self.pendingRestoreLeftPanelMode

        self.pendingRestoreApplied = true
        self.pendingRestoreMode = nil
        self.pendingRestoreLeftPanelMode = nil

        if restoreMode == "edit" then
            if self.mode ~= "edit" then
                self:setMode("edit")
            end

            if restorePanel == "scripts" then
                self:setLeftPanelMode("scripts")
            else
                self:setLeftPanelMode("hierarchy")
            end
        else
            if self.mode ~= "performance" then
                self:setMode("performance")
            end
        end
    end

    function shell:refreshMainUiTabs()
        local currentUiPath = getCurrentScriptPath and getCurrentScriptPath() or ""
        local uiScripts = listUiScripts and listUiScripts() or {}

        -- Build project tab list for ProjectTabHost
        local projectTabs = {}
        local seenUiIds = {}

        for i = 1, #uiScripts do
            local s = uiScripts[i]
            if type(s) == "table" and type(s.path) == "string" and s.path ~= "" then
                local name = (s.name and s.name ~= "") and s.name or fileStem(s.path)
                -- Skip system overlay projects (Settings etc) - they don't belong in the tab bar
                if not scriptLooksSettings(name, s.path) then
                    local tabId = "ui:" .. s.path
                    if not seenUiIds[tabId] then
                        seenUiIds[tabId] = true
                        projectTabs[#projectTabs + 1] = {
                            id = tabId,
                            title = name,
                            kind = "ui-script",
                            path = s.path,
                            isSystem = false,
                        }
                    end
                end
            end
        end

        if #projectTabs == 0 and currentUiPath ~= "" then
            projectTabs[#projectTabs + 1] = {
                id = "ui:" .. currentUiPath,
                title = fileStem(currentUiPath),
                kind = "ui-script",
                path = currentUiPath,
                isSystem = false,
            }
        end

        -- Update ProjectTabHost
        if self.projectTabHost then
            self.projectTabHost:setProjectTabs(projectTabs)
            -- Sync active tab by path
            if currentUiPath ~= "" then
                self.projectTabHost:setActiveByPath(currentUiPath)
            end
        end

        -- Legacy compatibility: maintain mainTabs and activeMainTabId
        self.mainTabs = projectTabs
        self.activeMainTabId = self.projectTabHost and self.projectTabHost:getActiveTabId() or ""
        if self.activeMainTabId == "" and #projectTabs > 0 then
            self.activeMainTabId = projectTabs[1].id
        end
    end

    function shell:activateMainTab(tabId)
        -- Use ProjectTabHost if available
        if self.projectTabHost then
            self.projectTabHost:setActiveTab(tabId)
            -- Note: setActiveTab triggers switchUiScript which reloads the project
            -- The activeMainTabId will be synced on the next refreshMainUiTabs() call
            return
        end

        -- Legacy fallback (should not be reached)
        local tab = self:_findMainTabById(tabId)
        if not tab then
            return
        end

        self.activeMainTabId = tabId

        if tab.kind == "ui-script" then
            self.activeTabContentText = ""
            self.activeTabContentPath = ""
            local currentUiPath = getCurrentScriptPath and getCurrentScriptPath() or ""
            if tab.path and tab.path ~= "" and tab.path ~= currentUiPath and switchUiScript then
                self:stashRestoreStateForScriptSwitch()
                switchUiScript(tab.path)
            end
        else
            self.activeTabContentText = ""
            self.activeTabContentPath = ""
        end

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
        if type(self.flushDeferredRefreshes) == "function" then
            self:flushDeferredRefreshes()
        end
    end

    function shell:ensureScriptEditorCursorVisible()
        local perfStart = nowSeconds()
        local ed = self.scriptEditor
        local h = math.floor(self.mainTabContent:getHeight())
        local lines = seBuildLinesCached(ed)
        local visible = seVisibleLineCount(h)
        local line = seLineColCached(ed)
        local maxScroll = math.max(1, #lines - visible + 1)

        if line < ed.scrollRow then
            ed.scrollRow = line
        elseif line >= ed.scrollRow + visible then
            ed.scrollRow = line - visible + 1
        end

        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)
        if type(_G) == "table" then
            local perf = _G.__manifoldEditorPerf or {}
            perf.lastEnsureVisibleMs = (nowSeconds() - perfStart) * 1000.0
            perf.peakEnsureVisibleMs = math.max(perf.peakEnsureVisibleMs or 0, perf.lastEnsureVisibleMs or 0)
            _G.__manifoldEditorPerf = perf
        end
    end

    function shell:scriptEditorPosFromPoint(mx, my)
        local perfStart = nowSeconds()
        local ed = self.scriptEditor
        local w = math.floor(self.mainTabContent:getWidth())
        local h = math.floor(self.mainTabContent:getHeight())
        local lines = seBuildLinesCached(ed)
        local visible = seVisibleLineCount(h)
        local maxScroll = math.max(1, #lines - visible + 1)
        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)

        local textTop = SCRIPT_EDITOR_STYLE.headerH + SCRIPT_EDITOR_STYLE.pad
        local lineIdx = ed.scrollRow + math.floor((my - textTop) / SCRIPT_EDITOR_STYLE.lineH)
        lineIdx = clamp(lineIdx, 1, #lines)

        local textX = SCRIPT_EDITOR_STYLE.gutterW + SCRIPT_EDITOR_STYLE.pad + 4
        local relativeX = math.max(0, mx - textX)
        local col = 1 + math.floor((relativeX / SCRIPT_EDITOR_STYLE.charW) + 0.5)
        local maxCol = #lines[lineIdx] + 1
        col = clamp(col, 1, maxCol)

        local _ = w
        local pos = sePosFromLineColCached(ed, lineIdx, col)
        if type(_G) == "table" then
            local perf = _G.__manifoldEditorPerf or {}
            perf.lastPosFromPointMs = (nowSeconds() - perfStart) * 1000.0
            perf.peakPosFromPointMs = math.max(perf.peakPosFromPointMs or 0, perf.lastPosFromPointMs or 0)
            perf.lastPointLine = lineIdx
            perf.lastPointCol = col
            _G.__manifoldEditorPerf = perf
        end
        return pos
    end

    function shell:openScriptEditor(row)
        local path = row and row.path or ""
        if path == "" then
            return
        end

        local text = ""
        if readTextFile then
            text = readTextFile(path) or ""
        end

        self.scriptEditor.kind = row.kind or ""
        self.scriptEditor.ownership = row.ownership or ""
        self.scriptEditor.name = row.name or fileStem(path)
        self:refreshScriptInspectorData(row)
        self.scriptEditor.path = path
        self.scriptEditor.text = text
        self.scriptEditor.syncToken = (tonumber(self.scriptEditor.syncToken) or 0) + 1
        self.scriptEditor.bodyRect = nil
        seInvalidateCache(self.scriptEditor)
        self.scriptEditor.cursorPos = 1
        self.scriptEditor.selectionAnchor = nil
        self.scriptEditor.dragAnchorPos = nil
        self.scriptEditor.scrollRow = 1
        self.scriptEditor.focused = false
        if self.scriptEditor.ownership == "editor-owned" then
            local docStatus = self:getStructuredDocumentStatus(path)
            local dirtySuffix = (type(docStatus) == "table" and docStatus.dirty == true) and " | runtime dirty" or ""
            self.scriptEditor.status = "Loaded editor-owned source" .. dirtySuffix
        else
            self.scriptEditor.status = "Loaded " .. (self.scriptEditor.name or fileStem(path))
        end
        self.scriptEditor.lastClickTime = 0
        self.scriptEditor.lastClickLine = -1
        self.scriptEditor.clickStreak = 0
        self.scriptEditor.dirty = false

        self.editContentMode = "script"

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
        self:computeMainScriptEditorGeometry()
        self.mainTabContent:grabKeyboardFocus()
        self.scriptEditor.focused = true
        self.mainTabContent:repaint()
    end

    function shell:saveScriptEditor()
        local ed = self.scriptEditor
        if not ed or ed.path == "" then
            return
        end

        if ed.ownership == "editor-owned" and ed.dirty ~= true and type(saveStructuredUiDocument) == "function" then
            local ok, err = pcall(saveStructuredUiDocument, ed.path)
            if not ok then
                ed.status = "Structured save failed: " .. tostring(err)
                return
            end
            if readTextFile then
                ed.text = readTextFile(ed.path) or ed.text or ""
                seInvalidateCache(ed)
            end
            ed.dirty = false
            ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
            ed.status = "Saved structured document"
            self:appendConsoleLine("Saved structured document: " .. tostring(ed.path), 0xff86efac)
            self:refreshProjectScriptRowsIfNeeded()
            if self.selectedScriptRow and self.selectedScriptRow.path == ed.path then
                self:refreshScriptInspectorData(self.selectedScriptRow)
                self.inspectorCanvas:repaint()
            end
            self.scriptCanvas:repaint()
            return
        end

        if writeTextFile then
            local ok = writeTextFile(ed.path, ed.text)
            if ok == false then
                ed.status = "Save failed"
                return
            end
            ed.dirty = false
            ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
            if ed.ownership == "editor-owned" then
                ed.status = "Saved source; reload/apply project to use changes"
                self:appendConsoleLine("Saved editor-owned source file: " .. tostring(ed.path), 0xff86efac)
            else
                ed.status = "Saved " .. (ed.name or fileStem(ed.path))
            end
            self:refreshScriptRows()
            if self.selectedScriptRow and self.selectedScriptRow.path == ed.path then
                self:refreshScriptInspectorData(self.selectedScriptRow)
                self.inspectorCanvas:repaint()
            end
            self.scriptCanvas:repaint()
        else
            ed.status = "writeTextFile unavailable"
        end
    end

    function shell:reloadScriptEditor()
        local ed = self.scriptEditor
        if not ed or ed.path == "" then
            return
        end

        if readTextFile then
            ed.text = readTextFile(ed.path) or ""
            seInvalidateCache(ed)
            ed.cursorPos = 1
            ed.selectionAnchor = nil
            ed.dragAnchorPos = nil
            ed.scrollRow = 1
            ed.dirty = false
            ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
            if ed.ownership == "editor-owned" then
                local docStatus = self:getStructuredDocumentStatus(ed.path)
                local dirtySuffix = (type(docStatus) == "table" and docStatus.dirty == true) and " | runtime still dirty" or ""
                ed.status = "Reloaded source from disk" .. dirtySuffix
            else
                ed.status = "Reloaded from disk"
            end
            if self.selectedScriptRow and self.selectedScriptRow.path == ed.path then
                self:refreshScriptInspectorData(self.selectedScriptRow)
                self.inspectorCanvas:repaint()
            end
        else
            ed.status = "readTextFile unavailable"
        end
    end

    function shell:closeScriptEditor()
        self.editContentMode = "preview"
        self.scriptEditor.focused = false
        self.scriptEditor.selectionAnchor = nil
        self.scriptEditor.dragAnchorPos = nil
        self.scriptEditor.bodyRect = nil
        self.mainTabContent:repaint()

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
        self:computeMainScriptEditorGeometry()
    end

    -- Back-compat wrappers for call-sites that still use tab naming.
    function shell:openScriptTab(kind, name, path)
        self:openScriptEditor({ kind = kind, name = name, path = path })
    end

    function shell:openDspParamTab(path, value)
        local _ = path
        _ = value
        -- DSP path/value popup removed; DSP script editing lives under Scripts panel.
        self.editContentMode = "preview"
    end

    function shell:getPerformanceViewLayoutInfo(contentW, contentH)
        local fallbackW = math.max(1, math.floor(tonumber(contentW) or 0))
        local fallbackH = math.max(1, math.floor(tonumber(contentH) or 0))
        local raw = nil

        if type(self.performanceView) == "table" then
            if type(self.performanceView.getLayoutInfo) == "function" then
                raw = self.performanceView.getLayoutInfo(fallbackW, fallbackH)
            elseif type(self.performanceView.layoutInfo) == "table" then
                raw = self.performanceView.layoutInfo
            end
        end

        local mode = "fill"
        local designW = fallbackW
        local designH = fallbackH
        local scaleMode = "stretch"
        local alignX = 0.5
        local alignY = 0.5

        if type(raw) == "table" then
            local rawMode = string.lower(tostring(raw.mode or raw.sizing or raw.viewportMode or raw.layoutMode or "fill"))
            if rawMode == "relative" or rawMode == "responsive" or rawMode == "fill-parent" or rawMode == "fill" or rawMode == "dynamic" then
                mode = "fill"
            elseif rawMode == "absolute" or rawMode == "fixed" or rawMode == "fixed-design" or rawMode == "design" then
                mode = "fixed"
            else
                mode = "fill"
            end

            if mode == "fixed" then
                designW = math.max(1, math.floor(tonumber(raw.designW or raw.w or raw.width) or designW))
                designH = math.max(1, math.floor(tonumber(raw.designH or raw.h or raw.height) or designH))
            else
                designW = fallbackW
                designH = fallbackH
            end

            local rawScaleMode = string.lower(tostring(raw.scaleMode or raw.presentation or raw.scale or ((mode == "fixed") and "fit" or "stretch")))
            if rawScaleMode == "none" or rawScaleMode == "fit" then
                scaleMode = rawScaleMode
            else
                scaleMode = (mode == "fixed") and "fit" or "stretch"
            end

            alignX = clamp(tonumber(raw.alignX or raw.anchorX or raw.pivotX) or alignX, 0.0, 1.0)
            alignY = clamp(tonumber(raw.alignY or raw.anchorY or raw.pivotY) or alignY, 0.0, 1.0)
        end

        local info = {
            mode = mode,
            designW = designW,
            designH = designH,
            scaleMode = scaleMode,
            alignX = alignX,
            alignY = alignY,
        }
        self.performanceViewLayoutInfo = info
        return info
    end

    function shell:registerPerformanceView(view)
        self.performanceView = view
        self.performanceViewLayoutInfo = nil

        if type(view) == "table" and not self.performanceViewInitialized then
            if type(view.init) == "function" and self.content ~= nil then
                view.init(self.content)
            end
            self.performanceViewInitialized = true
        end

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
    end

    function shell:isStructuredProjectActive()
        return type(getStructuredUiDocuments) == "function"
            and type(saveStructuredUiAll) == "function"
            and type(reloadStructuredUiProject) == "function"
    end

    function shell:getStructuredProjectStatus()
        if type(getStructuredUiProjectStatus) ~= "function" then
            return nil
        end
        local ok, status = pcall(getStructuredUiProjectStatus)
        if not ok or type(status) ~= "table" then
            return nil
        end
        return status
    end

    function shell:getStructuredDocumentStatus(path)
        if type(path) ~= "string" or path == "" then
            return nil
        end
        local status = self:getStructuredProjectStatus()
        local docs = status and status.documents or nil
        if type(docs) ~= "table" then
            return nil
        end
        for i = 1, #docs do
            local doc = docs[i]
            if type(doc) == "table" and doc.path == path then
                return doc
            end
        end
        return nil
    end

    function shell:getStructuredSourceForCanvas(canvas, purpose)
        if canvas == nil or type(canvas.getUserData) ~= "function" then
            return nil
        end

        if purpose == "bounds" then
            local instanceMeta = canvas:getUserData("_structuredInstanceSource")
            if type(instanceMeta) == "table"
                and type(instanceMeta.documentPath) == "string"
                and type(instanceMeta.nodeId) == "string" then
                if type(instanceMeta.childNodeId) == "string"
                    and instanceMeta.childNodeId ~= ""
                    and instanceMeta.childNodeId ~= instanceMeta.nodeId then
                    return {
                        documentPath = instanceMeta.documentPath,
                        nodeId = instanceMeta.nodeId,
                        pathPrefix = "overrides." .. instanceMeta.childNodeId .. ".",
                        childNodeId = instanceMeta.childNodeId,
                        globalId = instanceMeta.globalId,
                        kind = instanceMeta.kind,
                    }
                end
                return instanceMeta
            end
        end

        local sourceMeta = canvas:getUserData("_structuredSource")
        if type(sourceMeta) == "table"
            and type(sourceMeta.documentPath) == "string"
            and type(sourceMeta.nodeId) == "string" then
            return sourceMeta
        end

        return nil
    end

    function shell:isManagedContainerLayoutMode(mode)
        local normalized = string.lower(tostring(mode or ""))
        return normalized == "stack-x"
            or normalized == "stack-y"
            or normalized == "grid"
            or normalized == "overlay"
    end

    function shell:getStructuredRecordForCanvas(canvas, purpose)
        local source = self:getStructuredSourceForCanvas(canvas, purpose)
        if type(source) ~= "table" then
            return nil, source
        end

        local runtime = (type(_G) == "table") and _G.__manifoldStructuredUiRuntime or nil
        local row = self:_findTreeRowByCanvas(canvas)
        local record = row and row.record or nil
        if record == nil and type(runtime) == "table" and type(runtime.getRecordBySource) == "function" then
            record = runtime:getRecordBySource(source.documentPath, source.nodeId)
        end
        return record, source
    end

    function shell:canPersistStructuredBoundsForCanvas(canvas)
        local source = self:getStructuredSourceForCanvas(canvas, "bounds")
        if type(source) ~= "table" then
            return true
        end

        local docPath = source.documentPath
        local nodeId = source.nodeId
        local hasLayout = false
        local layoutMode = ""
        if type(getStructuredUiNodeValue) == "function" then
            local okLayout, layout = pcall(getStructuredUiNodeValue, docPath, nodeId, "layout")
            if okLayout and type(layout) == "table" then
                hasLayout = true
                layoutMode = string.lower(tostring(layout.mode or layout.sizing or layout.kind or "absolute"))
            end
        end

        if hasLayout and layoutMode ~= "" and layoutMode ~= "absolute" and layoutMode ~= "fixed" and layoutMode ~= "design" then
            return false
        end

        local record = self:getStructuredRecordForCanvas(canvas, "bounds")
        if type(record) == "table" and type(record.parent) == "table" then
            local parentLayout = type(record.parent.spec) == "table" and record.parent.spec.layout or nil
            local parentMode = type(parentLayout) == "table"
                and string.lower(tostring(parentLayout.mode or parentLayout.sizing or parentLayout.kind or ""))
                or ""
            if self:isManagedContainerLayoutMode(parentMode) then
                return false
            end
        end

        return true
    end

    function shell:persistStructuredBoundsForCanvas(canvas)
        if type(setStructuredUiNodeValue) ~= "function" then
            return false
        end

        if not self:canPersistStructuredBoundsForCanvas(canvas) then
            return false
        end

        local source = self:getStructuredSourceForCanvas(canvas, "bounds")
        if type(source) ~= "table" then
            return false
        end

        local bx, by, bw, bh = canvas:getBounds()
        local docPath = source.documentPath
        local nodeId = source.nodeId

        local runtime = (type(_G) == "table") and _G.__manifoldStructuredUiRuntime or nil
        local row = self:_findTreeRowByCanvas(canvas)
        local record = row and row.record or nil
        if record == nil and type(runtime) == "table" and type(runtime.getRecordBySource) == "function" then
            record = runtime:getRecordBySource(docPath, nodeId)
        end

        if type(record) == "table" and type(record.parent) == "table" then
            local parentRecord = record.parent
            local parentWidget = parentRecord.widget
            local parentCanvas = parentWidget and parentWidget.node or nil
            local parentSpec = type(parentRecord.spec) == "table" and parentRecord.spec or nil
            if parentCanvas and parentSpec then
                local _, _, parentW, parentH = parentCanvas:getBounds()
                local designW = tonumber(parentSpec.w) or tonumber(parentW) or 0
                local designH = tonumber(parentSpec.h) or tonumber(parentH) or 0
                parentW = tonumber(parentW) or 0
                parentH = tonumber(parentH) or 0
                if parentW > 0 and designW > 0 then
                    bx = bx * designW / parentW
                    bw = bw * designW / parentW
                end
                if parentH > 0 and designH > 0 then
                    by = by * designH / parentH
                    bh = bh * designH / parentH
                end
                bx = math.floor(bx + 0.5)
                by = math.floor(by + 0.5)
                bw = math.max(1, math.floor(bw + 0.5))
                bh = math.max(1, math.floor(bh + 0.5))
            end
        end

        local basePrefix = source.pathPrefix or ""
        local prefix = basePrefix .. (hasLayout and "layout." or "")
        local okX = pcall(setStructuredUiNodeValue, docPath, nodeId, prefix .. "x", bx)
        local okY = pcall(setStructuredUiNodeValue, docPath, nodeId, prefix .. "y", by)
        local okW = pcall(setStructuredUiNodeValue, docPath, nodeId, prefix .. "w", bw)
        local okH = pcall(setStructuredUiNodeValue, docPath, nodeId, prefix .. "h", bh)
        local ok = okX and okY and okW and okH

        if type(_G) == "table" then
            _G.__manifoldLastStructuredPersist = {
                documentPath = docPath,
                nodeId = nodeId,
                x = bx,
                y = by,
                w = bw,
                h = bh,
                ok = ok,
            }
            _G.__manifoldStructuredPersistCount = (_G.__manifoldStructuredPersistCount or 0) + 1
        end

        if ok and type(runtime) == "table" and type(runtime.notifyRecordHostedResized) == "function" and type(record) == "table" then
            local refreshRecord = record.parent or record
            pcall(function()
                runtime:notifyRecordHostedResized(refreshRecord)
            end)
        end

        return ok
    end

    function shell:resolveStructuredConfigDestination(documentPath, nodeId, configPath)
        local normalized = normalizeConfigPath(configPath)
        if normalized == "" then
            return nil
        end

        local candidates = {
            "props." .. normalized,
            "style." .. normalized,
            normalized,
        }

        if type(getStructuredUiNodeValue) == "function" then
            for i = 1, #candidates do
                local candidate = candidates[i]
                local ok, value = pcall(getStructuredUiNodeValue, documentPath, nodeId, candidate)
                if ok and value ~= nil then
                    return candidate
                end
            end
        end

        return "props." .. normalized
    end

    function shell:persistStructuredConfigForCanvas(canvas, configPath, value)
        if type(setStructuredUiNodeValue) ~= "function" then
            return false
        end

        local source = self:getStructuredSourceForCanvas(canvas, "config")
        if type(source) ~= "table" then
            return false
        end

        local destination = self:resolveStructuredConfigDestination(source.documentPath, source.nodeId, configPath)
        if type(destination) ~= "string" or destination == "" then
            return false
        end

        local ok = pcall(setStructuredUiNodeValue, source.documentPath, source.nodeId, destination, value)
        return ok
    end

    function shell:refreshProjectScriptRowsIfNeeded()
        if self:isStructuredProjectActive() then
            self:refreshScriptRows()
            if self.leftPanelMode == "scripts" then
                self.scriptCanvas:repaint()
            end
        end
    end

    function shell:saveStructuredProjectUi()
        if not self:isStructuredProjectActive() then
            return false
        end

        local before = self:getStructuredProjectStatus()
        local dirtyBefore = before and tonumber(before.dirtyCount) or 0
        local ok, err = pcall(saveStructuredUiAll)
        if ok then
            local after = self:getStructuredProjectStatus()
            local dirtyAfter = after and tonumber(after.dirtyCount) or 0
            local manifestPath = (after and after.manifestPath) or (before and before.manifestPath) or ""
            self:appendConsoleLine(string.format("Saved structured UI project (%d -> %d dirty)%s",
                dirtyBefore,
                dirtyAfter,
                manifestPath ~= "" and (": " .. manifestPath) or ""), 0xff86efac)
            self:refreshProjectScriptRowsIfNeeded()
            return true
        end
        local status = self:getStructuredProjectStatus()
        local op = status and status.lastOperation or ""
        self:appendConsoleLine("ERR: structured save failed" .. (op ~= "" and (" [" .. tostring(op) .. "]") or "") .. ": " .. tostring(err), 0xfffca5a5)
        return false
    end

    function shell:reloadStructuredProjectUi()
        if not self:isStructuredProjectActive() then
            return false
        end
        local before = self:getStructuredProjectStatus()
        local manifestPath = (before and before.manifestPath) or ""
        local ok, err = pcall(reloadStructuredUiProject)
        if ok then
            self:appendConsoleLine("Reloaded structured UI project" .. (manifestPath ~= "" and (": " .. manifestPath) or ""), 0xff93c5fd)
            return true
        end
        local status = self:getStructuredProjectStatus()
        local op = status and status.lastOperation or ""
        self:appendConsoleLine("ERR: structured reload failed" .. (op ~= "" and (" [" .. tostring(op) .. "]") or "") .. ": " .. tostring(err), 0xfffca5a5)
        return false
    end

    function shell:getCanvasAbsoluteBounds(canvas)
        if canvas == nil then
            return nil
        end

        local row = self:_findTreeRowByCanvas(canvas)
        if row then
            return row.x, row.y, row.w, row.h
        end

        local bx, by, bw, bh = canvas:getBounds()
        local dx, dy = self:localToDesign(bx, by)
        return dx, dy, bw, bh
    end

    function shell:getCanvasParentDesignOrigin(canvas)
        if canvas == nil then
            return self.viewportDesignX or 0, self.viewportDesignY or 0
        end

        local row = self:_findTreeRowByCanvas(canvas)
        if row then
            local bx, by = canvas:getBounds()
            return (row.x or 0) - (bx or 0), (row.y or 0) - (by or 0)
        end

        return self.viewportDesignX or 0, self.viewportDesignY or 0
    end

    function shell:getSelectionBounds()
        if #self.selectedWidgets == 0 then
            return nil
        end

        local minX, minY, maxX, maxY = nil, nil, nil, nil
        for i = 1, #self.selectedWidgets do
            local x, y, w, h = self:getCanvasAbsoluteBounds(self.selectedWidgets[i])
            if x ~= nil then
                minX = (minX == nil) and x or math.min(minX, x)
                minY = (minY == nil) and y or math.min(minY, y)
                maxX = (maxX == nil) and (x + w) or math.max(maxX, x + w)
                maxY = (maxY == nil) and (y + h) or math.max(maxY, y + h)
            end
        end

        if minX == nil then
            return nil
        end

        return {
            x = minX,
            y = minY,
            w = math.max(1, maxX - minX),
            h = math.max(1, maxY - minY),
        }
    end

    function shell:getHandleTargetRect()
        if #self.selectedWidgets > 1 then
            return self:getSelectionBounds()
        end
        if self.selectedWidget ~= nil then
            return self:_findTreeRowByCanvas(self.selectedWidget)
        end
        return nil
    end

    function shell:previewToDesign(px, py)
        if self.contentScale <= 0 then
            return 0, 0
        end
        local dx = (px - self.viewOriginX) / self.contentScale
        local dy = (py - self.viewOriginY) / self.contentScale
        return dx, dy
    end

    function shell:designToPreview(dx, dy)
        local px = self.viewOriginX + dx * self.contentScale
        local py = self.viewOriginY + dy * self.contentScale
        return px, py
    end

    function shell:getSelectionHandleRects(row)
        if row == nil then
            return {}
        end

        local x, y = self:designToPreview(row.x, row.y)
        local x2, y2 = self:designToPreview(row.x + row.w, row.y + row.h)
        local w = x2 - x
        local h = y2 - y

        local hs = self.handleSize
        local half = hs * 0.5
        local cx = x + w * 0.5
        local cy = y + h * 0.5

        return {
            { id = "nw", x = x - half, y = y - half, w = hs, h = hs },
            { id = "n", x = cx - half, y = y - half, w = hs, h = hs },
            { id = "ne", x = x + w - half, y = y - half, w = hs, h = hs },
            { id = "e", x = x + w - half, y = cy - half, w = hs, h = hs },
            { id = "se", x = x + w - half, y = y + h - half, w = hs, h = hs },
            { id = "s", x = cx - half, y = y + h - half, w = hs, h = hs },
            { id = "sw", x = x - half, y = y + h - half, w = hs, h = hs },
            { id = "w", x = x - half, y = cy - half, w = hs, h = hs },
        }
    end

    function shell:hitTestSelectionHandle(px, py)
        local row = self:getHandleTargetRect()
        if not row then
            return nil
        end

        local handles = self:getSelectionHandleRects(row)
        for i = 1, #handles do
            local h = handles[i]
            if px >= h.x and px <= (h.x + h.w) and py >= h.y and py <= (h.y + h.h) then
                return h.id
            end
        end
        return nil
    end

    local function refreshRowBoundsSubtree(row, parentAbsX, parentAbsY)
        if type(row) ~= "table" or row.canvas == nil then
            return
        end

        local bx, by, bw, bh = row.canvas:getBounds()
        local absX = (parentAbsX or 0) + (bx or 0)
        local absY = (parentAbsY or 0) + (by or 0)

        row.x = absX
        row.y = absY
        row.w = bw or 0
        row.h = bh or 0

        for i = 1, #(row.children or {}) do
            refreshRowBoundsSubtree(row.children[i], absX, absY)
        end
    end

    function shell:updateSelectedRowBoundsCache()
        if self.treeRoot == nil then
            self:refreshTree(true)
            return
        end

        refreshRowBoundsSubtree(self.treeRoot, 0, 0)
        self.treeCanvas:repaint()
        self.previewOverlay:repaint()
    end

    function shell:getWorkspaceDesignRect()
        return 0, 0, self.designW, self.designH
    end

    function shell:getViewportDesignRect()
        return self.viewportDesignX, self.viewportDesignY, self.viewportDesignW, self.viewportDesignH
    end

    function shell:localToDesign(lx, ly)
        return (lx or 0) + self.viewportDesignX, (ly or 0) + self.viewportDesignY
    end

    function shell:designToLocal(dx, dy)
        return (dx or 0) - self.viewportDesignX, (dy or 0) - self.viewportDesignY
    end

    function shell:_captureSelectionState()
        local widgets = {}
        for i = 1, #self.selectedWidgets do
            widgets[i] = self.selectedWidgets[i]
        end
        return {
            widgets = widgets,
            primary = self.selectedWidget,
        }
    end

    function shell:_selectionStatesEqual(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return false
        end

        local aw = a.widgets or {}
        local bw = b.widgets or {}
        if #aw ~= #bw then
            return false
        end
        for i = 1, #aw do
            if aw[i] ~= bw[i] then
                return false
            end
        end
        return a.primary == b.primary
    end

    function shell:_captureSceneState()
        local entries = {}
        for i = 1, #self.treeRows do
            local row = self.treeRows[i]
            if row.depth > 0 and row.canvas ~= nil then
                local bx, by, bw, bh = row.canvas:getBounds()
                local meta = row.canvas:getUserData("_editorMeta")
                local cfg = nil
                if type(meta) == "table" and type(meta.config) == "table" then
                    cfg = deepCopyTable(meta.config)
                end
                entries[#entries + 1] = {
                    canvas = row.canvas,
                    x = bx,
                    y = by,
                    w = bw,
                    h = bh,
                    config = cfg,
                }
            end
        end
        return entries
    end

    function shell:_sceneStatesEqual(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return false
        end
        if #a ~= #b then
            return false
        end

        local bMap = {}
        for i = 1, #b do
            local e = b[i]
            if e and e.canvas then
                bMap[e.canvas] = e
            end
        end

        for i = 1, #a do
            local ea = a[i]
            local eb = ea and bMap[ea.canvas] or nil
            if eb == nil then
                return false
            end
            if ea.x ~= eb.x or ea.y ~= eb.y or ea.w ~= eb.w or ea.h ~= eb.h then
                return false
            end
            if not deepEqual(ea.config, eb.config) then
                return false
            end
        end

        return true
    end

    function shell:_applySceneState(scene)
        if type(scene) ~= "table" then
            return
        end

        for i = 1, #scene do
            local entry = scene[i]
            if type(entry) == "table" and entry.canvas ~= nil then
                entry.canvas:setBounds(entry.x or 0, entry.y or 0, math.max(1, entry.w or 1), math.max(1, entry.h or 1))

                local meta = entry.canvas:getUserData("_editorMeta")
                if type(meta) == "table" and type(entry.config) == "table" then
                    meta.config = deepCopyTable(entry.config)
                    entry.canvas:setUserData("_editorMeta", meta)

                    local leaves = {}
                    collectConfigLeaves(meta.config, "", leaves, {})
                    for j = 1, #leaves do
                        local leaf = leaves[j]
                        self:_applyWidgetConfigProperty(meta, "config." .. leaf.path, leaf.value)
                    end
                end
            end
        end

        self:refreshTree(true)
    end

    function shell:recordHistory(label, beforeScene, beforeSelection, afterScene, afterSelection)
        if self.historyApplying then
            return
        end

        local sceneChanged = false
        local selectionChanged = false

        if type(beforeScene) == "table" and type(afterScene) == "table" then
            sceneChanged = not self:_sceneStatesEqual(beforeScene, afterScene)
        end
        if type(beforeSelection) == "table" and type(afterSelection) == "table" then
            selectionChanged = not self:_selectionStatesEqual(beforeSelection, afterSelection)
        end

        if not sceneChanged and not selectionChanged then
            return
        end

        self.undoStack[#self.undoStack + 1] = {
            label = label or "edit",
            beforeScene = beforeScene,
            afterScene = afterScene,
            beforeSelection = beforeSelection,
            afterSelection = afterSelection,
        }

        if #self.undoStack > self.maxHistoryEntries then
            table.remove(self.undoStack, 1)
        end

        self.redoStack = {}
    end

    function shell:undo()
        if #self.undoStack == 0 then
            return
        end

        local entry = table.remove(self.undoStack)
        self.historyApplying = true

        if type(entry.beforeScene) == "table" then
            self:_applySceneState(entry.beforeScene)
        end
        if type(entry.beforeSelection) == "table" then
            self:setSelection(entry.beforeSelection.widgets or {}, entry.beforeSelection.primary, false)
        end

        self.historyApplying = false
        self.redoStack[#self.redoStack + 1] = entry
    end

    function shell:redo()
        if #self.redoStack == 0 then
            return
        end

        local entry = table.remove(self.redoStack)
        self.historyApplying = true

        if type(entry.afterScene) == "table" then
            self:_applySceneState(entry.afterScene)
        end
        if type(entry.afterSelection) == "table" then
            self:setSelection(entry.afterSelection.widgets or {}, entry.afterSelection.primary, false)
        end

        self.historyApplying = false
        self.undoStack[#self.undoStack + 1] = entry
    end

    function shell:clampPanToWorkspace()
        if self.mode ~= "edit" then
            return
        end
        if self.previewW <= 0 or self.previewH <= 0 or self.designW <= 0 or self.designH <= 0 then
            return
        end

        local scale = self.contentScale > 0 and self.contentScale or clamp(self.currentZoom, self.minZoom, self.maxZoom)
        local scaledW = self.designW * scale
        local scaledH = self.designH * scale
        local margin = self.cameraPanMargin or 0

        local minOriginX = self.previewW - scaledW - margin
        local maxOriginX = margin
        local minOriginY = self.previewH - scaledH - margin
        local maxOriginY = margin

        if scaledW + margin * 2 <= self.previewW then
            local centered = (self.previewW - scaledW) * 0.5
            minOriginX = centered
            maxOriginX = centered
        end

        if scaledH + margin * 2 <= self.previewH then
            local centered = (self.previewH - scaledH) * 0.5
            minOriginY = centered
            maxOriginY = centered
        end

        local panMinX = minOriginX + scaledW * 0.5 - self.previewW * 0.5
        local panMaxX = maxOriginX + scaledW * 0.5 - self.previewW * 0.5
        local panMinY = minOriginY + scaledH * 0.5 - self.previewH * 0.5
        local panMaxY = maxOriginY + scaledH * 0.5 - self.previewH * 0.5

        self.panX = clamp(self.panX, panMinX, panMaxX)
        self.panY = clamp(self.panY, panMinY, panMaxY)
    end

    function shell:zoomAtPreviewPoint(factor, px, py)
        if self.mode ~= "edit" then
            return
        end
        if self.designW <= 0 or self.designH <= 0 then
            return
        end

        self.autoFit = false

        local currentScale = self.contentScale > 0 and self.contentScale or self.currentZoom
        local newScale = clamp(currentScale * factor, self.minZoom, self.maxZoom)
        if math.abs(newScale - currentScale) < 0.0001 then
            return
        end

        local designX, designY = self:previewToDesign(px, py)

        self.currentZoom = newScale
        self.panX = px - (self.previewW * 0.5) + (self.designW * 0.5 - designX) * newScale
        self.panY = py - (self.previewH * 0.5) + (self.designH * 0.5 - designY) * newScale

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
    end

    function shell:updateInspectorColorControls(argbValue)
        local packed = normalizeArgbNumber(argbValue)
        local r, g, b, a = argbToRgba(packed)

        self.inspectorColorR:setValue(r)
        self.inspectorColorG:setValue(g)
        self.inspectorColorB:setValue(b)
        self.inspectorColorA:setValue(a)

        if self.inspectorColorPreview and self.inspectorColorPreview.setStyle then
            self.inspectorColorPreview:setStyle({ bg = packed, border = 0xff334155, borderWidth = 1, radius = 3 })
        end

        if self.inspectorColorHex and self.inspectorColorHex.setText then
            self.inspectorColorHex:setText(string.format("#%02X%02X%02X%02X", r, g, b, a))
        end
    end

    function shell:applyActiveColorComponent(component, value)
        if self.inspectorUpdating then
            return
        end

        local row = self.activeConfigProperty
        if row == nil or row.editorType ~= "color" then
            return
        end

        local packed = normalizeArgbNumber(row.rawValue)
        local r, g, b, a = argbToRgba(packed)
        local v = clamp(math.floor((tonumber(value) or 0) + 0.5), 0, 255)

        if component == "r" then
            r = v
        elseif component == "g" then
            g = v
        elseif component == "b" then
            b = v
        elseif component == "a" then
            a = v
        else
            return
        end

        local nextColour = rgbaToArgb(r, g, b, a)
        self:applyActiveConfigValue(nextColour)
    end

    function shell:_showActivePropertyEditor(row)
        self.activeConfigProperty = row
        self.activeEnumValues = nil

        if row == nil or row.isConfig ~= true or row.editorType == nil then
            self.inspectorPropLabel:setText("")
            self.inspectorPropText:setText("")
            if self.mode == "edit" then
                local w = self.parentNode:getWidth()
                local h = self.parentNode:getHeight()
                self:layout(w, h)
            end
            self.inspectorCanvas:repaint()
            return
        end

        local labelText = row.key
        if row.mixed == true then
            labelText = labelText .. " (mixed)"
        end
        self.inspectorPropLabel:setText(labelText)

        if row.editorType == "number" then
            self.inspectorPropNumber._label = "Value"
            local rawNum = tonumber(row.rawValue) or 0
            if math.floor(rawNum) == rawNum then
                self.inspectorPropNumber._step = row.step or 1
                self.inspectorPropNumber._format = row.format or "%d"
            else
                self.inspectorPropNumber._step = row.step or 0.01
                self.inspectorPropNumber._format = row.format or "%.3f"
            end
            self.inspectorPropNumber._min = row.min ~= nil and row.min or -2147483647
            self.inspectorPropNumber._max = row.max ~= nil and row.max or 2147483647

            self.inspectorUpdating = true
            self.inspectorPropNumber:setValue(tonumber(row.rawValue) or 0)
            self.inspectorUpdating = false
        elseif row.editorType == "color" then
            self.inspectorUpdating = true
            self:updateInspectorColorControls(row.rawValue)
            self.inspectorUpdating = false
        elseif row.editorType == "bool" then
            local boolLabel = getPathTail(row.path)
            if row.mixed == true then
                boolLabel = boolLabel .. " (mixed)"
            end
            self.inspectorPropBool._label = boolLabel
            self.inspectorUpdating = true
            self.inspectorPropBool:setValue(row.rawValue == true)
            self.inspectorUpdating = false
        elseif row.editorType == "enum" and type(row.enumOptions) == "table" then
            local labels = {}
            local selected = 1
            self.activeEnumValues = {}

            if row.mixed == true then
                labels[#labels + 1] = "<mixed>"
                self.activeEnumValues[#self.activeEnumValues + 1] = nil
                selected = 1
            end

            for i = 1, #row.enumOptions do
                local option = row.enumOptions[i]
                labels[#labels + 1] = option.label
                self.activeEnumValues[#self.activeEnumValues + 1] = option.value
                if row.mixed ~= true and option.value == row.rawValue then
                    selected = #labels
                end
            end
            if #labels == 0 then
                labels = { "-" }
                self.activeEnumValues = { row.rawValue }
                selected = 1
            end
            self.inspectorPropEnum:setOptions(labels)
            self.inspectorPropEnum:setSelected(selected)
        elseif row.editorType == "text" then
            if row.mixed == true then
                self.inspectorPropText:setText("<mixed>")
            else
                self.inspectorPropText:setText(valueToText(row.rawValue))
            end
        end

        if self.mode == "edit" then
            local w = self.parentNode:getWidth()
            local h = self.parentNode:getHeight()
            self:layout(w, h)
        end

        self.debugLastIdentifier = self:deriveActiveDebugIdentifier()
        self.inspectorCanvas:repaint()
    end

    function shell:_applyWidgetConfigProperty(meta, path, value)
        if type(meta) ~= "table" then
            return
        end

        local widget = meta.widget
        if type(widget) ~= "table" then
            return
        end

        local key = getPathTail(path)

        -- Check if this is an exposed param - use _setExposed if available
        if isPathExposed(widget, key) and type(widget._setExposed) == "function" then
            widget:_setExposed(key, value)
            return
        end

        if key == "label" and type(widget.setLabel) == "function" then
            widget:setLabel(value)
        elseif key == "text" and type(widget.setText) == "function" then
            widget:setText(value)
        elseif key == "value" and type(widget.setValue) == "function" then
            widget:setValue(value)
        elseif key == "selected" and type(widget.setSelected) == "function" then
            widget:setSelected(value)
        elseif key == "bg" and type(widget.setBg) == "function" then
            widget:setBg(value)
        elseif key == "textColour" and type(widget.setTextColour) == "function" then
            widget:setTextColour(value)
        elseif key == "colour" and type(widget.setColour) == "function" then
            widget:setColour(value)
        elseif (key == "border" or key == "borderWidth" or key == "radius" or key == "opacity") and type(widget.setStyle) == "function" then
            widget:setStyle({ [key] = value })
        elseif key == "enabled" and type(widget.setEnabled) == "function" then
            widget:setEnabled(value == true)
        else
            local privateField = "_" .. key
            if widget[privateField] ~= nil then
                widget[privateField] = value
            end

            local setterName = "set" .. upperFirst(key)
            if type(widget[setterName]) == "function" then
                widget[setterName](widget, value)
            end
        end

        if widget.node then
            widget.node:repaint()
        end
    end

    function shell:applyActiveConfigValue(value)
        if self.inspectorUpdating then
            return
        end

        if #self.selectedWidgets == 0 or self.activeConfigProperty == nil then
            return
        end

        local row = self.activeConfigProperty
        if row.isConfig ~= true or type(row.path) ~= "string" then
            return
        end

        local beforeScene = self:_captureSceneState()
        local beforeSelection = self:_captureSelectionState()

        local baseValue = row.rawValue
        local typedValue = value

        if row.editorType == "number" then
            typedValue = tonumber(value) or tonumber(baseValue) or 0
        elseif row.editorType == "color" then
            typedValue = normalizeArgbNumber(tonumber(value) or tonumber(baseValue) or 0)
        elseif row.editorType == "bool" then
            typedValue = value == true
        elseif row.editorType == "text" then
            typedValue = tostring(value or "")
        end

        local changed = false
        local selectionCopy = {}
        for i = 1, #self.selectedWidgets do
            selectionCopy[i] = self.selectedWidgets[i]
        end
        local primary = self.selectedWidget

        for i = 1, #selectionCopy do
            local canvas = selectionCopy[i]
            local meta = canvas and canvas:getUserData("_editorMeta") or nil
            if type(meta) == "table" then
                -- For exposed params, get value from widget; otherwise from config
                local widget = meta.widget
                local pathTail = getPathTail(row.path)
                local currentValue = nil
                
                if isPathExposed(widget, pathTail) then
                    currentValue = getInspectorValue(widget, meta, pathTail)
                else
                    currentValue = getConfigValueByPath(meta.config, row.path)
                end
                
                if currentValue ~= nil and currentValue ~= typedValue then
                    -- Update config if it exists there
                    if type(meta.config) == "table" and setConfigValueByPath(meta.config, row.path, typedValue) then
                        canvas:setUserData("_editorMeta", meta)
                    end
                    -- Always apply to widget (handles exposed params)
                    self:_applyWidgetConfigProperty(meta, row.path, typedValue)
                    self:persistStructuredConfigForCanvas(canvas, row.path, typedValue)
                    changed = true
                end
            end
        end

        if not changed then
            return
        end

        self:refreshTree(true)
        self:setSelection(selectionCopy, primary)
        self:refreshProjectScriptRowsIfNeeded()

        for i = 1, #self.inspectorRows do
            local r = self.inspectorRows[i]
            if r.isConfig and r.path == row.path then
                self:_showActivePropertyEditor(r)
                break
            end
        end

        local afterScene = self:_captureSceneState()
        local afterSelection = self:_captureSelectionState()
        self:recordHistory("config", beforeScene, beforeSelection, afterScene, afterSelection)
    end

    function shell:applyActiveConfigEnumChoice(index)
        if self.activeConfigProperty == nil then
            return
        end
        if type(self.activeEnumValues) ~= "table" then
            return
        end
        local value = self.activeEnumValues[index]
        if value == nil then
            return
        end
        self:applyActiveConfigValue(value)
    end

    function shell:copyActiveConfigText()
        local row = self.activeConfigProperty
        if row == nil or row.editorType ~= "text" then
            return
        end
        if setClipboardText then
            setClipboardText(tostring(row.rawValue or ""))
        end
    end

    function shell:pasteActiveConfigText()
        local row = self.activeConfigProperty
        if row == nil or row.editorType ~= "text" then
            return
        end
        if getClipboardText then
            local text = getClipboardText()
            self:applyActiveConfigValue(text)
        end
    end

    function shell:_rebuildInspectorRows()
        local perfStartMs = shellPerfNowMs()
        local previousPath = self.activeConfigProperty and self.activeConfigProperty.path or nil

        self.inspectorRows = {}

        if self.leftPanelMode == "scripts" then
            if type(self.selectedScriptRow) == "table" then
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Script", value = self.selectedScriptRow.name or "" }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Kind", value = self.selectedScriptRow.kind or "" }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Path", value = self.selectedScriptRow.path or "" }

                local si = self.scriptInspector or {}
                if self.selectedScriptRow.kind == "dsp" then
                    local params = si.params or {}
                    local runtimeParams = si.runtimeParams or {}
                    local graph = si.graph or { nodes = {}, edges = {} }
                    self.inspectorRows[#self.inspectorRows + 1] = { key = "Params (static)", value = tostring(#params) }
                    self.inspectorRows[#self.inspectorRows + 1] = { key = "Params (runtime)", value = tostring(#runtimeParams) }
                    self.inspectorRows[#self.inspectorRows + 1] = { key = "Graph", value = string.format("%d nodes / %d edges", #(graph.nodes or {}), #(graph.edges or {})) }
                end

                self.inspectorRows[#self.inspectorRows + 1] = { key = "Action", value = "Double-click to open editor" }
            else
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Scripts", value = "Select a script" }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Action", value = "Double-click to open editor" }
            end
            self.inspectorScrollY = 0
            self:_showActivePropertyEditor(nil)
            self.inspectorCanvas:repaint()
            shellPerfTrace("_rebuildInspectorRows", perfStartMs,
                string.format("mode=scripts rows=%d selected=%s", #self.inspectorRows,
                    tostring(self.selectedScriptRow and self.selectedScriptRow.path or nil)))
            return
        end

        local selCount = #self.selectedWidgets
        if selCount == 0 then
            self.inspectorRows[#self.inspectorRows + 1] = {
                key = "Selection",
                value = "None",
            }
            self.inspectorScrollY = 0
            self:_showActivePropertyEditor(nil)
            self.inspectorCanvas:repaint()
            shellPerfTrace("_rebuildInspectorRows", perfStartMs, "mode=hierarchy rows=1 selection=none")
            return
        end

        if selCount == 1 then
            local canvas = self.selectedWidgets[1]
            local meta = canvas:getUserData("_editorMeta")
            local nodeType = (type(meta) == "table" and type(meta.type) == "string") and meta.type or "Canvas"
            local nodeName = deriveNodeName(meta, nodeType)

            self.inspectorRows[#self.inspectorRows + 1] = { key = "Type", value = nodeType }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Name", value = nodeName }

            local dx, dy, bw, bh = self:getCanvasAbsoluteBounds(canvas)
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.x", value = valueToText(dx or 0) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.y", value = valueToText(dy or 0) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.w", value = valueToText(bw or 0) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.h", value = valueToText(bh or 0) }

            if type(meta) == "table" and type(meta.config) == "table" then
                local widget = meta.widget
                local usedSchema = appendSchemaRows(meta.schema, meta.config, self.inspectorRows, widget, meta)
                if not usedSchema then
                    self.inspectorRows[#self.inspectorRows + 1] = { key = "Config", value = "" }
                    appendConfigRows(meta.config, self.inspectorRows, "config", 0, {})
                end
            end
        else
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Type", value = "Multiple (" .. selCount .. ")" }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Name", value = selCount .. " widgets selected" }

            local bounds = self:getSelectionBounds()
            if bounds then
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.x", value = valueToText(bounds.x) }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.y", value = valueToText(bounds.y) }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.w", value = valueToText(bounds.w) }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.h", value = valueToText(bounds.h) }
            end

            local firstMeta = self.selectedWidgets[1] and self.selectedWidgets[1]:getUserData("_editorMeta") or nil
            local schema = type(firstMeta) == "table" and firstMeta.schema or nil
            local addedSharedConfig = false

            if type(schema) == "table" and #schema > 0 then
                local currentGroup = nil
                for i = 1, #schema do
                    local item = schema[i]
                    if type(item) == "table" and type(item.path) == "string" then
                        local path = item.path
                        local allHave = true
                        local shared = true
                        local firstValue = nil

                        for s = 1, selCount do
                            local c = self.selectedWidgets[s]
                            local m = c and c:getUserData("_editorMeta") or nil
                            if type(m) ~= "table" or type(m.config) ~= "table" then
                                allHave = false
                                break
                            end
                            local widget = m.widget
                            local v = getInspectorValue(widget, m, path)
                            if v == nil then
                                v = getConfigValueByPath(m.config, path)
                            end
                            if v == nil then
                                allHave = false
                                break
                            end
                            if firstValue == nil then
                                firstValue = v
                            elseif firstValue ~= v then
                                shared = false
                            end
                        end

                        if allHave then
                            local group = item.group or "Config"
                            if group ~= currentGroup then
                                currentGroup = group
                                self.inspectorRows[#self.inspectorRows + 1] = {
                                    key = group,
                                    value = "",
                                    isConfig = false,
                                    editorType = nil,
                                }
                            end

                            local editorType = item.type
                            local enumOptions = item.options
                            if editorType == nil then
                                editorType, enumOptions = inferEditorType(path, firstValue)
                            end

                            self.inspectorRows[#self.inspectorRows + 1] = {
                                key = item.label or path,
                                value = shared and valueToText(firstValue) or "<mixed>",
                                rawValue = firstValue,
                                mixed = not shared,
                                path = "config." .. path,
                                isConfig = true,
                                editorType = editorType,
                                enumOptions = enumOptions,
                                min = item.min,
                                max = item.max,
                                step = item.step,
                                format = item.format,
                            }
                            addedSharedConfig = true
                        end
                    end
                end
            end

            if not addedSharedConfig then
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Config", value = "" }
                self.inspectorRows[#self.inspectorRows + 1] = { key = "Shared Properties", value = "None" }
            end
        end

        local maxScroll = math.max(0, #self.inspectorRows * self.inspectorRowHeight - self.inspectorViewportH)
        self.inspectorScrollY = clamp(self.inspectorScrollY, 0, maxScroll)

        local restored = false
        if previousPath then
            for i = 1, #self.inspectorRows do
                local row = self.inspectorRows[i]
                if row.isConfig and row.path == previousPath then
                    self:_showActivePropertyEditor(row)
                    restored = true
                    break
                end
            end
        end

        if not restored then
            self:_showActivePropertyEditor(nil)
        end

        self.inspectorCanvas:repaint()
        shellPerfTrace("_rebuildInspectorRows", perfStartMs,
            string.format("mode=hierarchy rows=%d selection=%d restored=%s",
                #self.inspectorRows,
                selCount,
                tostring(restored)))
    end

    function shell:_syncInspectorEditors()
        self.inspectorUpdating = true

        if self.leftPanelMode ~= "hierarchy" then
            self.inspectorX:setValue(0)
            self.inspectorY:setValue(0)
            self.inspectorW:setValue(1)
            self.inspectorH:setValue(1)
            self.inspectorUpdating = false
            return
        end

        local selCount = #self.selectedWidgets
        if selCount == 0 then
            self.inspectorX:setValue(0)
            self.inspectorY:setValue(0)
            self.inspectorW:setValue(1)
            self.inspectorH:setValue(1)
        elseif selCount == 1 then
            local dx, dy, bw, bh = self:getCanvasAbsoluteBounds(self.selectedWidgets[1])
            self.inspectorX:setValue(dx or 0)
            self.inspectorY:setValue(dy or 0)
            self.inspectorW:setValue(math.max(1, bw or 1))
            self.inspectorH:setValue(math.max(1, bh or 1))
        else
            local b = self:getSelectionBounds()
            if b then
                self.inspectorX:setValue(b.x)
                self.inspectorY:setValue(b.y)
                self.inspectorW:setValue(math.max(1, b.w))
                self.inspectorH:setValue(math.max(1, b.h))
            end
        end

        self.inspectorUpdating = false
    end

    function shell:applyBoundsEditor(axis, value)
        if self.inspectorUpdating then
            return
        end

        if self.leftPanelMode ~= "hierarchy" then
            return
        end

        local selCount = #self.selectedWidgets
        if selCount == 0 then
            return
        end

        for i = 1, selCount do
            local canvas = self.selectedWidgets[i]
            if canvas ~= nil and not self:canPersistStructuredBoundsForCanvas(canvas) then
                return
            end
        end

        local beforeScene = self:_captureSceneState()
        local beforeSelection = self:_captureSelectionState()

        local iv = math.floor((value or 0) + 0.5)

        if selCount == 1 then
            local target = self.selectedWidgets[1]
            local bx, by, bw, bh = target:getBounds()
            local parentDesignX, parentDesignY = self:getCanvasParentDesignOrigin(target)

            if axis == "x" then
                bx = iv - parentDesignX
            elseif axis == "y" then
                by = iv - parentDesignY
            elseif axis == "w" then
                bw = math.max(1, iv)
            elseif axis == "h" then
                bh = math.max(1, iv)
            end

            target:setBounds(bx, by, bw, bh)
            self:persistStructuredBoundsForCanvas(target)
            self.treeRefreshPending = true
            self:updateSelectedRowBoundsCache()
            self:_syncInspectorEditors()
            self:_rebuildInspectorRows()
            self:refreshProjectScriptRowsIfNeeded()

            local afterScene = self:_captureSceneState()
            local afterSelection = self:_captureSelectionState()
            self:recordHistory("bounds", beforeScene, beforeSelection, afterScene, afterSelection)
            return
        end

        local bounds = self:getSelectionBounds()
        if not bounds then
            return
        end

        if axis == "x" or axis == "y" then
            local delta = (axis == "x") and (iv - bounds.x) or (iv - bounds.y)
            for i = 1, selCount do
                local c = self.selectedWidgets[i]
                local bx, by, bw, bh = c:getBounds()
                if axis == "x" then
                    c:setBounds(bx + delta, by, bw, bh)
                else
                    c:setBounds(bx, by + delta, bw, bh)
                end
            end
        else
            local oldSize = (axis == "w") and math.max(1, bounds.w) or math.max(1, bounds.h)
            local newSize = math.max(self.minWidgetSize, iv)
            local scale = newSize / oldSize

            for i = 1, selCount do
                local c = self.selectedWidgets[i]
                local row = self:_findTreeRowByCanvas(c)
                if row then
                    local bx, by, bw, bh = c:getBounds()
                    if axis == "w" then
                        local relX = row.x - bounds.x
                        local nx = bounds.x + relX * scale
                        local parentDesignX = row.x - bx
                        local localNX = nx - parentDesignX
                        local nw = math.max(self.minWidgetSize, bw * scale)
                        c:setBounds(math.floor(localNX + 0.5), by, math.floor(nw + 0.5), bh)
                    else
                        local relY = row.y - bounds.y
                        local ny = bounds.y + relY * scale
                        local parentDesignY = row.y - by
                        local localNY = ny - parentDesignY
                        local nh = math.max(self.minWidgetSize, bh * scale)
                        c:setBounds(bx, math.floor(localNY + 0.5), bw, math.floor(nh + 0.5))
                    end
                end
            end
        end

        for i = 1, selCount do
            self:persistStructuredBoundsForCanvas(self.selectedWidgets[i])
        end
        self.treeRefreshPending = true
        self:updateSelectedRowBoundsCache()
        self:_syncInspectorEditors()
        self:_rebuildInspectorRows()
        self:refreshProjectScriptRowsIfNeeded()

        local afterScene = self:_captureSceneState()
        local afterSelection = self:_captureSelectionState()
        self:recordHistory("bounds", beforeScene, beforeSelection, afterScene, afterSelection)
    end

    function shell:selectWidget(canvas, recordHistory)
        if canvas ~= nil and not self:_isWidgetInTree(canvas) then
            return
        end

        if canvas == nil then
            if #self.selectedWidgets == 0 and self.selectedWidget == nil then
                return
            end
            self:setSelection({}, nil, recordHistory)
            return
        end

        if self.selectedWidget == canvas and #self.selectedWidgets == 1 and self.selectedWidgets[1] == canvas then
            return
        end

        self:setSelection({ canvas }, canvas, recordHistory)
    end

    function shell:refreshTree(force)
        local perfStartMs = shellPerfNowMs()
        if self.mode ~= "edit" and not force then
            return
        end

        local now = 0
        if getTime then
            now = getTime()
        elseif os and os.clock then
            now = os.clock()
        end
        if not force and self.treeLastRefreshAt >= 0 and (now - self.treeLastRefreshAt) < 0.12 then
            self.treeRefreshPending = true
            shellPerfTrace("refreshTree", perfStartMs,
                string.format("deferred=true rows=%d force=%s", #self.treeRows, tostring(force)))
            return
        end

        self.treeLastRefreshAt = now
        self.treeRefreshPending = false

        self.treeRows = {}
        if self.content ~= nil then
            local rootOffsetX = (self.mode == "edit") and self.viewportDesignX or 0
            local rootOffsetY = (self.mode == "edit") and self.viewportDesignY or 0
            local structuredRuntime = (type(_G) == "table") and _G.__manifoldStructuredUiRuntime or nil
            if self:isStructuredProjectActive()
                and type(structuredRuntime) == "table"
                and type(structuredRuntime.layoutTree) == "table" then
                self.treeRoot = walkStructuredRecords(structuredRuntime.layoutTree, 0, self.treeRows, rootOffsetX, rootOffsetY, "", 0, structuredRuntime)
            else
                self.treeRoot = walkHierarchy(self.content, 0, self.treeRows, rootOffsetX, rootOffsetY, "", 0, {
                    structuredOnly = false,
                    structuredDocumentPath = "",
                })
            end
        else
            self.treeRoot = nil
        end

        local validSelection = {}
        for i = 1, #self.selectedWidgets do
            local canvas = self.selectedWidgets[i]
            if canvas ~= nil and self:_isWidgetInTree(canvas) then
                validSelection[#validSelection + 1] = canvas
            end
        end

        if #validSelection ~= #self.selectedWidgets then
            local primary = self.selectedWidget
            if primary ~= nil and not self:_isWidgetInTree(primary) then
                primary = nil
            end
            self:setSelection(validSelection, primary, false)
        elseif self.selectedWidget ~= nil and not self:_isWidgetInTree(self.selectedWidget) then
            self:selectWidget(nil, false)
        elseif self.selectedWidget == nil and #self.treeRows > 0 then
            local initial = self.treeRows[1].canvas
            for i = 1, #self.treeRows do
                if self.treeRows[i].depth > 0 then
                    initial = self.treeRows[i].canvas
                    break
                end
            end
            self:selectWidget(initial, false)
        else
            self:_syncInspectorEditors()
            self:_rebuildInspectorRows()
        end

        local contentHeight = #self.treeRows * self.treeRowHeight
        local maxScroll = math.max(0, contentHeight - self.treeViewportH)
        self.treeScrollY = clamp(self.treeScrollY, 0, maxScroll)
        self.treeCanvas:repaint()
        self.previewOverlay:repaint()
        shellPerfTrace("refreshTree", perfStartMs,
            string.format("rows=%d selection=%d force=%s scroll=%.1f",
                #self.treeRows,
                #self.selectedWidgets,
                tostring(force),
                tonumber(self.treeScrollY) or 0))
    end


end

return M

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

local M = {}

local function shellLayoutPerfNowMs()
    return nowSeconds() * 1000.0
end

local function shellLayoutPerfTrace(label, startMs, extra)
    local elapsedMs = shellLayoutPerfNowMs() - startMs
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
    function shell:setMode(newMode)
        if self.mode == newMode then return end
        self.mode = newMode
        self:publishUiStateToGlobals()

        if newMode == "performance" then
            self.scriptEditor.focused = false
        end

        -- Update button colors
        if newMode == "performance" then
            self.perfButton:setBg(0xff38bdf8)
            self.editButton:setBg(0xff1e293b)
        else
            self.perfButton:setBg(0xff1e293b)
            self.editButton:setBg(0xff38bdf8)
        end

        -- Hide settings overlay if open
        shell.settingsOpen = false
        if shell.scriptOverlay then
            shell.scriptOverlay:setBounds(0, 0, 0, 0)
        end

        -- Trigger layout refresh
        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)

        if newMode == "edit" then
            self.treeRefreshPending = true
            self:refreshTree(true)
        end
    end

    function shell:setTitle(text)
        self.titleLabel:setText(text)
    end

    function shell:layout(totalW, totalH)
        local perfStartMs = shellLayoutPerfNowMs()
        -- Shell header
        self.panel:setBounds(self.pad, self.pad, totalW - self.pad * 2, self.height)
        self.titleLabel:setBounds(10, 0, 130, self.height)

        local right = totalW - self.pad * 2 - 10
        local hGap = 8
        local knobW = self.height - 4

        -- Settings button (rightmost)
        self.settingsButton:setBounds(right - 80, 6, 78, self.height - 12)
        right = right - 80 - hGap

        -- Master/Input knobs
        self.masterKnob:setBounds(right - knobW, 2, knobW, self.height - 4)
        right = right - knobW - hGap
        self.inputKnob:setBounds(right - knobW, 2, knobW, self.height - 4)
        right = right - knobW - hGap

        -- Input toggle
        self.passthroughToggle:setBounds(right - 80, 6, 80, self.height - 12)
        right = right - 80 - hGap - 8

        -- Mode toggle buttons (left of Input toggle)
        self.perfButton:setBounds(right - 90, 6, 88, self.height - 12)
        right = right - 90 - 4
        self.editButton:setBounds(right - 48, 6, 46, self.height - 12)
        right = right - 48 - hGap

        if self.mode == "performance" then
            self.perfButton:setBg(0xff38bdf8)
            self.editButton:setBg(0xff1e293b)
        else
            self.perfButton:setBg(0xff1e293b)
            self.editButton:setBg(0xff38bdf8)
        end

        local showStructuredControls = self.mode == "edit" and self:isStructuredProjectActive()
        if showStructuredControls then
            self.reloadProjectButton:setBounds(right - 68, 8, 66, self.height - 16)
            right = right - 68 - 4
            self.saveProjectButton:setBounds(right - 58, 8, 56, self.height - 16)
            right = right - 58 - 8
        else
            self.saveProjectButton:setBounds(0, 0, 0, 0)
            self.reloadProjectButton:setBounds(0, 0, 0, 0)
        end

        -- Edit navigation controls
        self.zoomInButton:setBounds(right - 24, 8, 22, self.height - 16)
        right = right - 24 - 2
        self.zoomOutButton:setBounds(right - 24, 8, 22, self.height - 16)
        right = right - 24 - 4
        self.zoomLabel:setBounds(right - 48, 8, 46, self.height - 16)
        right = right - 48 - 4
        self.zoomFitButton:setBounds(right - 42, 8, 40, self.height - 16)
        right = right - 42 - 4
        self.panModeButton:setBounds(right - 44, 8, 42, self.height - 16)

        if self.navMode == "pan" then
            self.panModeButton:setBg(0xff38bdf8)
        else
            self.panModeButton:setBg(0xff1e293b)
        end

        local zoomPercent = math.floor((self.contentScale > 0 and self.contentScale or self.currentZoom) * 100 + 0.5)
        if self.autoFit then
            self.zoomLabel:setText("Fit")
        else
            self.zoomLabel:setText(zoomPercent .. "%")
        end

        self:refreshMainUiTabs()

        -- Content area (below header)
        local contentY = self.height + self.gapAfter
        local contentH = totalH - contentY - self.pad
        local contentW = totalW - self.pad * 2
        local activeTab = self:_findMainTabById(self.activeMainTabId)
        local isUiTab = activeTab ~= nil and activeTab.kind == "ui-script"
        local tabH = self.mainTabBarH

        -- Runtime viewport/layout contract comes from the shell-hosted performance view.
        -- Default is dynamic fill-parent; fixed-design views can opt in via getLayoutInfo().
        local perfLayout = self:getPerformanceViewLayoutInfo(contentW, contentH)
        local viewportDesignW = perfLayout.designW
        local viewportDesignH = perfLayout.designH

        -- Edit workspace extends beyond runtime viewport
        local workspacePad = math.max(0, self.workspacePad or 0)
        local workspaceDesignW = viewportDesignW + workspacePad
        local workspaceDesignH = viewportDesignH + workspacePad

        if self.mode == "performance" then
            -- Hide tree and inspector
            self.treePanel:setBounds(0, 0, 0, 0)
            self.inspectorPanel:setBounds(0, 0, 0, 0)
            self.treeLabel:setBounds(0, 0, 0, 0)
            self.treeTabHierarchy:setBounds(0, 0, 0, 0)
            self.treeTabDsp:setBounds(0, 0, 0, 0)
            self.treeTabScripts:setBounds(0, 0, 0, 0)
            self.treeCanvas:setBounds(0, 0, 0, 0)
            self.dspCanvas:setBounds(0, 0, 0, 0)
            self.scriptCanvas:setBounds(0, 0, 0, 0)
            self.inspectorX:setBounds(0, 0, 0, 0)
            self.inspectorY:setBounds(0, 0, 0, 0)
            self.inspectorW:setBounds(0, 0, 0, 0)
            self.inspectorH:setBounds(0, 0, 0, 0)
            self.inspectorPropLabel:setBounds(0, 0, 0, 0)
            self.inspectorPropNumber:setBounds(0, 0, 0, 0)
            self.inspectorPropBool:setBounds(0, 0, 0, 0)
            self.inspectorPropEnum:setBounds(0, 0, 0, 0)
            if self.inspectorPropEnum.close then
                self.inspectorPropEnum:close()
            end
            self.inspectorPropText:setBounds(0, 0, 0, 0)
            self.inspectorPropCopy:setBounds(0, 0, 0, 0)
            self.inspectorPropPaste:setBounds(0, 0, 0, 0)
            self.inspectorCanvas:setBounds(0, 0, 0, 0)
            self.previewOverlay:setBounds(0, 0, 0, 0)

            self.mainTabBar:setBounds(0, math.floor(contentY), math.floor(contentW), math.floor(tabH))
            local perfBodyY = contentY + tabH
            local perfBodyH = math.max(0, contentH - tabH)
            if isUiTab then
                self.mainTabContent:setBounds(0, 0, 0, 0)
            else
                self.mainTabContent:setBounds(0, math.floor(perfBodyY), math.floor(contentW), math.floor(perfBodyH))
            end

            self.zoomOutButton:setBounds(0, 0, 0, 0)
            self.zoomInButton:setBounds(0, 0, 0, 0)
            self.zoomFitButton:setBounds(0, 0, 0, 0)
            self.panModeButton:setBounds(0, 0, 0, 0)
            self.saveProjectButton:setBounds(0, 0, 0, 0)
            self.reloadProjectButton:setBounds(0, 0, 0, 0)
            self.zoomLabel:setBounds(0, 0, 0, 0)

            local activeViewportW = math.max(1, contentW)
            local activeViewportH = math.max(1, perfBodyH)

            self.contentScale = 1.0
            self.contentTx = 0
            self.contentTy = perfBodyY
            self.viewOriginX = 0
            self.viewOriginY = 0
            self.previewX = 0
            self.previewY = 0
            self.previewW = 0
            self.previewH = 0
            self.designW = viewportDesignW
            self.designH = viewportDesignH
            self.viewportDesignX = 0
            self.viewportDesignY = 0
            self.viewportDesignW = viewportDesignW
            self.viewportDesignH = viewportDesignH
            self.dragState = nil

            self.panel.node:setInterceptsMouse(true, true)
            self.mainTabBar:setInterceptsMouse(true, true)
            self.mainTabContent:setInterceptsMouse(true, true)

            if self.content then
                self.content:setInterceptsMouse(true, true)
                if perfLayout.mode == "fixed" then
                    local scale = 1.0
                    if perfLayout.scaleMode == "fit" then
                        scale = math.min(
                            activeViewportW / math.max(1, viewportDesignW),
                            activeViewportH / math.max(1, viewportDesignH)
                        )
                    end

                    local drawW = viewportDesignW * scale
                    local drawH = viewportDesignH * scale
                    local tx = (activeViewportW - drawW) * perfLayout.alignX
                    local ty = perfBodyY + (activeViewportH - drawH) * perfLayout.alignY

                    self.contentScale = scale
                    self.contentTx = tx
                    self.contentTy = ty
                    self.content:setBounds(0, 0, math.floor(viewportDesignW), math.floor(viewportDesignH))
                    self.content:setTransform(scale, scale, tx, ty)
                else
                    self.content:setBounds(0, math.floor(perfBodyY), math.floor(activeViewportW), math.floor(activeViewportH))
                    self.content:clearTransform()
                end
            end

            if self.performanceView and type(self.performanceView.resized) == "function" then
                self.performanceView.resized(0, 0, math.floor(viewportDesignW), math.floor(viewportDesignH))
            end
        else
            -- Edit mode: tree | content (scaled) | inspector
            local treeW = 180
            local inspectorW = 220
            local gap = 6
            local previewW = contentW - treeW - inspectorW - gap * 2
            local previewX = treeW + gap
            local previewHeaderH = (self.editContentMode == "preview") and tabH or 0
            local previewY = contentY + previewHeaderH
            local previewH = math.max(0, contentH - previewHeaderH)

            if self.editContentMode == "preview" then
                self.mainTabBar:setBounds(math.floor(previewX), math.floor(contentY), math.floor(previewW), math.floor(tabH))
                self.mainTabContent:setBounds(0, 0, 0, 0)
            else
                self.mainTabBar:setBounds(0, 0, 0, 0)
                self.mainTabContent:setBounds(math.floor(previewX), math.floor(contentY), math.floor(previewW), math.floor(contentH))
            end
            if type(self.computeMainScriptEditorGeometry) == "function" then
                self:computeMainScriptEditorGeometry()
            end

            -- Calculate preview transform (fit/manual zoom + pan)
            local fitScale = math.min(previewW / viewportDesignW, previewH / viewportDesignH)
            if self.autoFit then
                self.currentZoom = fitScale
            end

            local scale = clamp(self.currentZoom, self.minZoom, self.maxZoom)
            self.contentScale = scale

            local viewportOffsetX = 0
            local viewportOffsetY = 0

            self.previewX = previewX
            self.previewY = previewY
            self.previewW = previewW
            self.previewH = previewH
            self.designW = workspaceDesignW
            self.designH = workspaceDesignH
            self.viewportDesignX = viewportOffsetX
            self.viewportDesignY = viewportOffsetY
            self.viewportDesignW = viewportDesignW
            self.viewportDesignH = viewportDesignH

            if self.autoFit then
                local runtimeCenterX = self.viewportDesignX + self.viewportDesignW * 0.5
                local runtimeCenterY = self.viewportDesignY + self.viewportDesignH * 0.5
                local workspaceCenterX = self.designW * 0.5
                local workspaceCenterY = self.designH * 0.5
                self.panX = (workspaceCenterX - runtimeCenterX) * scale
                self.panY = (workspaceCenterY - runtimeCenterY) * scale
            end

            self:clampPanToWorkspace()

            local centerX = previewW * 0.5 + self.panX
            local centerY = previewH * 0.5 + self.panY
            local originXInPreview = centerX - self.designW * scale * 0.5
            local originYInPreview = centerY - self.designH * scale * 0.5

            self.viewOriginX = originXInPreview
            self.viewOriginY = originYInPreview
            self.contentTx = previewX + originXInPreview + self.viewportDesignX * scale
            self.contentTy = previewY + originYInPreview + self.viewportDesignY * scale

            -- Left panel on left: Hierarchy | DSP | Scripts
            self.treePanel:setBounds(0, math.floor(contentY), treeW, math.floor(contentH))
            self.treeLabel:setBounds(8, 4, treeW - 16, 16)

            local tabY = 20
            local tabGap = 4
            local tabW = math.floor((treeW - 8 - tabGap) / 2)
            self.treeTabHierarchy:setBounds(4, tabY, tabW, 18)
            self.treeTabScripts:setBounds(4 + tabW + tabGap, tabY, tabW, 18)
            self.treeTabDsp:setBounds(0, 0, 0, 0)

            if self.leftPanelMode == "hierarchy" then
                self.treeTabHierarchy:setBg(0xff334155)
                self.treeTabScripts:setBg(0xff1e293b)
            else
                self.treeTabHierarchy:setBg(0xff1e293b)
                self.treeTabScripts:setBg(0xff334155)
            end

            local treeContentY = 42
            local treeContentH = math.max(0, math.floor(contentH - treeContentY - 6))
            local treeContentW = math.floor(treeW - 8)

            if self.leftPanelMode == "hierarchy" then
                self.treeCanvas:setBounds(4, treeContentY, treeContentW, treeContentH)
                self.dspCanvas:setBounds(0, 0, 0, 0)
                self.scriptCanvas:setBounds(0, 0, 0, 0)
            else
                self.treeCanvas:setBounds(0, 0, 0, 0)
                self.dspCanvas:setBounds(0, 0, 0, 0)
                self.scriptCanvas:setBounds(4, treeContentY, treeContentW, treeContentH)
            end

            self.treeViewportH = treeContentH
            self.dspViewportH = treeContentH
            self.scriptViewportH = treeContentH

            -- Inspector panel on right
            self.inspectorPanel:setBounds(math.floor(previewX + previewW + gap), math.floor(contentY), inspectorW, math.floor(contentH))
            self.inspectorLabel:setBounds(8, 4, inspectorW - 16, 24)

            local inspectorInnerW = inspectorW - 16
            local boxGap = 6
            local boxW = math.floor((inspectorInnerW - boxGap) * 0.5)
            local boxH = 26
            local boxY1 = 30
            local boxY2 = 30 + boxH + 4

            local inspectorContentY = 30

            if self.leftPanelMode == "hierarchy" and self.selectedWidget ~= nil then
                self.inspectorX:setBounds(8, boxY1, boxW, boxH)
                self.inspectorY:setBounds(8 + boxW + boxGap, boxY1, boxW, boxH)
                self.inspectorW:setBounds(8, boxY2, boxW, boxH)
                self.inspectorH:setBounds(8 + boxW + boxGap, boxY2, boxW, boxH)

                local propY = boxY2 + boxH + 4
                local propLabelH = 16
                local propControlH = 26
                local row = self.activeConfigProperty
                local editorType = row and row.editorType or nil

                if editorType ~= "enum" and self.inspectorPropEnum.close then
                    self.inspectorPropEnum:close()
                end

                if editorType ~= nil then
                    self.inspectorPropLabel:setBounds(8, propY, inspectorInnerW, propLabelH)

                    if editorType == "number" then
                        self.inspectorPropNumber:setBounds(8, propY + propLabelH + 2, inspectorInnerW, propControlH)
                        self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                        self.inspectorColorHex:setBounds(0, 0, 0, 0)
                        self.inspectorColorR:setBounds(0, 0, 0, 0)
                        self.inspectorColorG:setBounds(0, 0, 0, 0)
                        self.inspectorColorB:setBounds(0, 0, 0, 0)
                        self.inspectorColorA:setBounds(0, 0, 0, 0)
                        self.inspectorPropBool:setBounds(0, 0, 0, 0)
                        self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                        self.inspectorPropText:setBounds(0, 0, 0, 0)
                        self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                        self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                        inspectorContentY = propY + propLabelH + propControlH + 8
                    elseif editorType == "color" then
                        local previewH = 20
                        local sliderH = 24
                        local gap = 4
                        local rowY = propY + propLabelH + 2

                        self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                        self.inspectorColorPreview:setBounds(8, rowY, 34, previewH)
                        self.inspectorColorHex:setBounds(8 + 38, rowY, inspectorInnerW - 38, previewH)

                        rowY = rowY + previewH + gap
                        self.inspectorColorR:setBounds(8, rowY, inspectorInnerW, sliderH)
                        rowY = rowY + sliderH + gap
                        self.inspectorColorG:setBounds(8, rowY, inspectorInnerW, sliderH)
                        rowY = rowY + sliderH + gap
                        self.inspectorColorB:setBounds(8, rowY, inspectorInnerW, sliderH)
                        rowY = rowY + sliderH + gap
                        self.inspectorColorA:setBounds(8, rowY, inspectorInnerW, sliderH)

                        self.inspectorPropBool:setBounds(0, 0, 0, 0)
                        self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                        self.inspectorPropText:setBounds(0, 0, 0, 0)
                        self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                        self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                        inspectorContentY = rowY + sliderH + 8
                    elseif editorType == "bool" then
                        self.inspectorPropBool:setBounds(8, propY + propLabelH + 2, inspectorInnerW, propControlH)
                        self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                        self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                        self.inspectorColorHex:setBounds(0, 0, 0, 0)
                        self.inspectorColorR:setBounds(0, 0, 0, 0)
                        self.inspectorColorG:setBounds(0, 0, 0, 0)
                        self.inspectorColorB:setBounds(0, 0, 0, 0)
                        self.inspectorColorA:setBounds(0, 0, 0, 0)
                        self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                        self.inspectorPropText:setBounds(0, 0, 0, 0)
                        self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                        self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                        inspectorContentY = propY + propLabelH + propControlH + 8
                    elseif editorType == "enum" then
                        self.inspectorPropEnum:setBounds(8, propY + propLabelH + 2, inspectorInnerW, propControlH)
                        local panelX, panelY = self.inspectorPanel.node:getBounds()
                        self.inspectorPropEnum:setAbsolutePos(panelX + 8, panelY + propY + propLabelH + 2)
                        self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                        self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                        self.inspectorColorHex:setBounds(0, 0, 0, 0)
                        self.inspectorColorR:setBounds(0, 0, 0, 0)
                        self.inspectorColorG:setBounds(0, 0, 0, 0)
                        self.inspectorColorB:setBounds(0, 0, 0, 0)
                        self.inspectorColorA:setBounds(0, 0, 0, 0)
                        self.inspectorPropBool:setBounds(0, 0, 0, 0)
                        self.inspectorPropText:setBounds(0, 0, 0, 0)
                        self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                        self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                        inspectorContentY = propY + propLabelH + propControlH + 8
                    elseif editorType == "text" then
                        self.inspectorPropText:setBounds(8, propY + propLabelH + 2, inspectorInnerW, 22)
                        local btnW = math.floor((inspectorInnerW - boxGap) * 0.5)
                        local btnY = propY + propLabelH + 24
                        self.inspectorPropCopy:setBounds(8, btnY, btnW, 22)
                        self.inspectorPropPaste:setBounds(8 + btnW + boxGap, btnY, btnW, 22)
                        self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                        self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                        self.inspectorColorHex:setBounds(0, 0, 0, 0)
                        self.inspectorColorR:setBounds(0, 0, 0, 0)
                        self.inspectorColorG:setBounds(0, 0, 0, 0)
                        self.inspectorColorB:setBounds(0, 0, 0, 0)
                        self.inspectorColorA:setBounds(0, 0, 0, 0)
                        self.inspectorPropBool:setBounds(0, 0, 0, 0)
                        self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                        inspectorContentY = btnY + 26
                    else
                        self.inspectorPropLabel:setBounds(0, 0, 0, 0)
                        self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                        self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                        self.inspectorColorHex:setBounds(0, 0, 0, 0)
                        self.inspectorColorR:setBounds(0, 0, 0, 0)
                        self.inspectorColorG:setBounds(0, 0, 0, 0)
                        self.inspectorColorB:setBounds(0, 0, 0, 0)
                        self.inspectorColorA:setBounds(0, 0, 0, 0)
                        self.inspectorPropBool:setBounds(0, 0, 0, 0)
                        self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                        self.inspectorPropText:setBounds(0, 0, 0, 0)
                        self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                        self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                        inspectorContentY = boxY2 + boxH + 6
                    end
                else
                    self.inspectorPropLabel:setBounds(0, 0, 0, 0)
                    self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                    self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                    self.inspectorColorHex:setBounds(0, 0, 0, 0)
                    self.inspectorColorR:setBounds(0, 0, 0, 0)
                    self.inspectorColorG:setBounds(0, 0, 0, 0)
                    self.inspectorColorB:setBounds(0, 0, 0, 0)
                    self.inspectorColorA:setBounds(0, 0, 0, 0)
                    self.inspectorPropBool:setBounds(0, 0, 0, 0)
                    self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                    self.inspectorPropText:setBounds(0, 0, 0, 0)
                    self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                    self.inspectorPropPaste:setBounds(0, 0, 0, 0)
                    inspectorContentY = boxY2 + boxH + 6
                end
            else
                self.inspectorX:setBounds(0, 0, 0, 0)
                self.inspectorY:setBounds(0, 0, 0, 0)
                self.inspectorW:setBounds(0, 0, 0, 0)
                self.inspectorH:setBounds(0, 0, 0, 0)
                self.inspectorPropLabel:setBounds(0, 0, 0, 0)
                self.inspectorPropNumber:setBounds(0, 0, 0, 0)
                self.inspectorColorPreview:setBounds(0, 0, 0, 0)
                self.inspectorColorHex:setBounds(0, 0, 0, 0)
                self.inspectorColorR:setBounds(0, 0, 0, 0)
                self.inspectorColorG:setBounds(0, 0, 0, 0)
                self.inspectorColorB:setBounds(0, 0, 0, 0)
                self.inspectorColorA:setBounds(0, 0, 0, 0)
                self.inspectorPropBool:setBounds(0, 0, 0, 0)
                self.inspectorPropEnum:setBounds(0, 0, 0, 0)
                if self.inspectorPropEnum.close then
                    self.inspectorPropEnum:close()
                end
                self.inspectorPropText:setBounds(0, 0, 0, 0)
                self.inspectorPropCopy:setBounds(0, 0, 0, 0)
                self.inspectorPropPaste:setBounds(0, 0, 0, 0)
            end

            local inspectorContentH = math.max(0, math.floor(contentH - inspectorContentY - 6))
            self.inspectorCanvas:setBounds(6, inspectorContentY, inspectorW - 12, inspectorContentH)
            self.inspectorViewportH = inspectorContentH
            if type(self.computeScriptInspectorGeometry) == "function" then
                self:computeScriptInspectorGeometry()
            end

            self.panel.node:setInterceptsMouse(true, true)
            self.mainTabBar:setInterceptsMouse(true, true)
            self.mainTabContent:setInterceptsMouse(true, true)

            -- Content: show live preview only when edit center is in preview mode.
            if self.content then
                self.content:setInterceptsMouse(false, false)
                local contentInterceptsSelf, contentInterceptsChildren = self.content:getInterceptsMouse()
                shellLayoutPerfTrace("contentIntercepts",
                    nowSeconds() * 1000.0,
                    string.format("mode=%s self=%s children=%s bounds=%dx%d panel=%s",
                        tostring(self.mode),
                        tostring(contentInterceptsSelf),
                        tostring(contentInterceptsChildren),
                        math.floor(self.designW or 0),
                        math.floor(self.designH or 0),
                        tostring(self.leftPanelMode)))
                if self.editContentMode == "preview" then
                    self.content:setBounds(0, 0, math.floor(self.designW), math.floor(self.designH))
                    self.content:setTransform(scale, scale, self.contentTx, self.contentTy)
                    self.content:toFront(false)
                else
                    self.content:setBounds(0, 0, 0, 0)
                    self.content:clearTransform()
                end
            end

            if self.performanceView and type(self.performanceView.resized) == "function" then
                self.performanceView.resized(
                    math.floor(self.viewportDesignX),
                    math.floor(self.viewportDesignY),
                    math.floor(self.viewportDesignW),
                    math.floor(self.viewportDesignH)
                )
            end

            if self.editContentMode == "preview" then
                self.previewOverlay:setBounds(math.floor(previewX), math.floor(previewY), math.floor(previewW), math.floor(previewH))
            else
                self.previewOverlay:setBounds(0, 0, 0, 0)
            end

            -- Keep preview chrome above content, but keep side panels above any accidental overlap.
            -- Putting mainTabBar/mainTabContent above treePanel was a stupid move because any transient
            -- oversized bounds there can steal left-panel clicks before they ever hit the actual tabs.
            self.mainTabContent:toFront(false)
            self.mainTabBar:toFront(false)
            self.previewOverlay:toFront(false)
            self.treePanel.node:toFront(false)
            self.inspectorPanel.node:toFront(false)
            if shell.settingsOpen and shell.scriptOverlay then
                shell.scriptOverlay:toFront(false)
            end

            if self.treeRefreshPending then
                self:refreshTree(false)
            else
                local contentHeight = #self.treeRows * self.treeRowHeight
                local maxScroll = math.max(0, contentHeight - self.treeViewportH)
                self.treeScrollY = clamp(self.treeScrollY, 0, maxScroll)
            end
            self.previewOverlay:repaint()
        end

        self.mainTabContent:toFront(false)
        self.mainTabBar:toFront(false)

        self:updateConsoleBounds(totalW, totalH)

        -- Keep shell header above any transformed content.
        self.panel.node:toFront(false)
        if self.console.visible then
            self.consoleOverlay:toFront(false)
        end
        if shell.settingsOpen and shell.scriptOverlay then
            shell.scriptOverlay:toFront(false)
        end

        if type(self.syncToolSurfaces) == "function" then
            self:syncToolSurfaces()
        end
        if type(self.syncPerfOverlaySurface) == "function" then
            self:syncPerfOverlaySurface(totalW, totalH)
        end

        shellLayoutPerfTrace("layout", perfStartMs,
            string.format("mode=%s panel=%s size=%dx%d tree=%d scripts=%d tabs=%d",
                tostring(self.mode),
                tostring(self.leftPanelMode),
                totalW,
                totalH,
                #self.treeRows,
                #self.scriptRows,
                #self.mainTabs))
    end

    function shell:getContentBounds(totalW, totalH)
        local contentY = self.pad + self.height + self.gapAfter
        local contentH = totalH - contentY - self.pad
        local contentW = totalW - self.pad * 2
        
        if self.mode == "edit" then
            -- Edit mode preview area (between tree and inspector).
            local treeW = 180
            local inspectorW = 220
            local gap = 6
            local previewX = treeW + gap
            local previewW = contentW - treeW - inspectorW - gap * 2
            local previewY = contentY
            local previewH = contentH
            if self.editContentMode == "preview" then
                previewY = contentY + self.mainTabBarH
                previewH = math.max(0, contentH - self.mainTabBarH)
            end
            return previewX, previewY, previewW, previewH
        end

        -- Performance mode: account for top tab bar so ui_resized matches live content canvas.
        local tabH = self.mainTabBarH or 0
        local perfY = contentY + tabH
        local perfH = math.max(0, contentH - tabH)
        return self.pad, perfY, contentW, perfH
    end

    shell:publishUiStateToGlobals()

    function shell:updateFromState(state)
        -- Handle deferred mode switch to avoid blocking GUI thread during OpenGL context creation
        if self.deferredModeSwitch and self.deferredModeSwitch ~= self.mode then
            local modeToSwitch = self.deferredModeSwitch
            self.deferredModeSwitch = nil
            self:setMode(modeToSwitch)
        end
        
        local params = state and state.params or state or {}
        local now = nowSeconds()
        self.stateParamsCache = params

        self:applyPendingRestoreState()
        self:refreshMainUiTabs()

        self.masterKnob:setValue(readParam(params, "/core/behavior/volume", 0.8))
        self.inputKnob:setValue(readParam(params, "/core/behavior/inputVolume", 1.0))
        self.passthroughToggle:setValue(readBoolParam(params, "/core/behavior/passthrough", true))

        local allowLiveViewUpdates = true
        if self.mode == "edit" and self.leftPanelMode == "hierarchy" then
            allowLiveViewUpdates = false
        end

        if allowLiveViewUpdates and self.performanceView and type(self.performanceView.update) == "function" then
            self.performanceView.update(state)
        end

        if shell.settingsOpen and shell.scriptOverlay then
            shell.scriptOverlay:toFront(false)
        end

        if self.mode == "edit" then
            if self.treeRefreshPending then
                self:refreshTree(false)
            end
            if self.leftPanelMode == "scripts" then
                local refreshRows = (self.scriptRowsLastRefreshAt < 0) or
                    ((now - self.scriptRowsLastRefreshAt) >= (self.scriptRowsRefreshInterval or 0.25))
                if refreshRows then
                    self:refreshScriptRows()
                    self.scriptCanvas:repaint()
                end

                local si = self.scriptInspector or {}
                local runtimeInteracting = (si.runtimeSliderDragActive == true) or
                    (si.runtimeInputActive == true) or
                    (si.graphDragging == true)

                local refreshRuntime = (not runtimeInteracting) and (
                    (self.runtimeParamsLastRefreshAt < 0) or
                    ((now - self.runtimeParamsLastRefreshAt) >= (self.runtimeParamsRefreshInterval or 0.1))
                )

                if refreshRuntime then
                    self:refreshScriptInspectorRuntimeParams()
                    self.inspectorCanvas:repaint()
                end
            end
        end

        local shouldRepaintMain = true
        if self.mode == "edit" and self.leftPanelMode == "scripts" and self.editContentMode == "preview" then
            shouldRepaintMain = false
        end

        if shouldRepaintMain then
            local repaintInterval = self.uiRepaintInterval or 0.033
            if (self.uiRepaintLastAt or -1) < 0 or (now - (self.uiRepaintLastAt or -1)) >= repaintInterval then
                self.mainTabBar:repaint()
                self.mainTabContent:repaint()
                self.uiRepaintLastAt = now
            end
        end

        -- Content updates handled by C++ calling ui_update directly
    end


end

return M

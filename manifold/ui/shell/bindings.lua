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

function M.attach(shell)
    shell.treeCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        local imguiHierarchyActive = (type(_G) == "table" and _G.__manifoldImguiHierarchyActive == true)

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

        if imguiHierarchyActive then
            return
        end

        if #shell.treeRows == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No widgets", 8, 6, w - 16, 20, Justify.centredLeft)
            return
        end

        local rowH = shell.treeRowHeight
        local startRow = math.floor(shell.treeScrollY / rowH) + 1
        local rowOffset = -(shell.treeScrollY % rowH)

        for i = startRow, #shell.treeRows do
            local rowY = math.floor(rowOffset + (i - startRow) * rowH)
            if rowY > h then
                break
            end

            if rowY + rowH >= 0 then
                local row = shell.treeRows[i]
                local isSelected = shell:isCanvasSelected(row.canvas)
                if isSelected then
                    gfx.setColour(0xff1e3a5f)
                    gfx.fillRoundedRect(3, rowY + 1, w - 6, rowH - 2, 4)
                end

                local indent = math.floor(8 + row.depth * shell.treeIndent)
                local text = row.type .. "  " .. row.name
                gfx.setColour(isSelected and 0xff7dd3fc or 0xffcbd5e1)
                gfx.setFont(11.0)
                gfx.drawText(text, indent, rowY, w - indent - 6, rowH, Justify.centredLeft)
            end
        end
    end)

    shell.treeCanvas:setOnMouseDown(function(mx, my)
        if type(_G) == "table" and _G.__manifoldImguiHierarchyActive == true then
            return
        end
        shell.treeCanvas:grabKeyboardFocus()
        local row = math.floor((my + shell.treeScrollY) / shell.treeRowHeight) + 1
        if row >= 1 and row <= #shell.treeRows then
            shell:selectWidget(shell.treeRows[row].canvas)
        end
    end)

    shell.treeCanvas:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if type(_G) == "table" and _G.__manifoldImguiHierarchyActive == true then
            return false
        end
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.treeCanvas:setOnMouseWheel(function(mx, my, deltaY)
        if type(_G) == "table" and _G.__manifoldImguiHierarchyActive == true then
            return
        end
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
    end)

    shell.dspCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

        if #shell.dspRows == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No DSP params yet", 8, 6, w - 16, 20, Justify.centredLeft)
            return
        end

        local rowH = shell.dspRowHeight
        local startRow = math.floor(shell.dspScrollY / rowH) + 1
        local rowOffset = -(shell.dspScrollY % rowH)

        for i = startRow, #shell.dspRows do
            local rowY = math.floor(rowOffset + (i - startRow) * rowH)
            if rowY > h then
                break
            end
            if rowY + rowH >= 0 then
                local row = shell.dspRows[i]
                local selected = shell.selectedDspRow and shell.selectedDspRow.path == row.path
                if selected then
                    gfx.setColour(0xff1e3a5f)
                    gfx.fillRoundedRect(4, rowY + 1, w - 8, rowH - 2, 4)
                end

                gfx.setColour(selected and 0xff7dd3fc or 0xff8fa6bf)
                gfx.setFont(10.0)
                gfx.drawText(row.path or "", 8, rowY, math.floor(w * 0.66), rowH, Justify.centredLeft)

                gfx.setColour(selected and 0xfff8fafc or 0xffcbd5e1)
                gfx.setFont(10.0)
                gfx.drawText(row.value or "", math.floor(w * 0.66), rowY, math.floor(w * 0.34) - 8, rowH, Justify.centredRight)
            end
        end
    end)

    shell.dspCanvas:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.dspCanvas:setOnMouseWheel(function(mx, my, deltaY)
        local nextScroll, changed = shell:applyWheelListScroll(
            shell.dspScrollY,
            deltaY,
            shell.dspRowHeight,
            #shell.dspRows,
            shell.dspViewportH,
            2
        )
        if changed then
            shell.dspScrollY = nextScroll
            shell.dspCanvas:repaint()
        end
    end)

    shell.dspCanvas:setOnMouseDown(function(mx, my)
        shell.dspCanvas:grabKeyboardFocus()
        local row = math.floor((my + shell.dspScrollY) / shell.dspRowHeight) + 1
        if row >= 1 and row <= #shell.dspRows then
            local r = shell.dspRows[row]
            if r then
                shell:handleLeftListSelection("dsp", r, nil)
            end
        end
    end)

    shell.scriptCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        local imguiScriptListActive = (type(_G) == "table" and _G.__manifoldImguiScriptListActive == true)

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

        if imguiScriptListActive then
            return
        end

        if #shell.scriptRows == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No scripts", 8, 6, w - 16, 20, Justify.centredLeft)
            return
        end

        local rowH = shell.scriptRowHeight
        local startRow = math.floor(shell.scriptScrollY / rowH) + 1
        local rowOffset = -(shell.scriptScrollY % rowH)

        for i = startRow, #shell.scriptRows do
            local rowY = math.floor(rowOffset + (i - startRow) * rowH)
            if rowY > h then
                break
            end
            if rowY + rowH >= 0 then
                local row = shell.scriptRows[i]
                if row.section then
                    gfx.setColour(0xff94a3b8)
                    gfx.setFont(10.0)
                    gfx.drawText(row.label or "", 8, rowY, w - 16, rowH, Justify.centredLeft)
                elseif row.nonInteractive then
                    gfx.setColour(0xff64748b)
                    gfx.setFont(10.0)
                    gfx.drawText(row.name or "", 12, rowY, w - 24, rowH, Justify.centredLeft)
                else
                    local selected = shell.selectedScriptRow and shell.selectedScriptRow.path == row.path and shell.selectedScriptRow.kind == row.kind
                    if row.active or selected then
                        gfx.setColour(selected and 0xff274669 or 0xff1e3a5f)
                        gfx.fillRoundedRect(4, rowY + 1, w - 8, rowH - 2, 4)
                    end
                    gfx.setColour((row.active or selected) and 0xff7dd3fc or 0xffcbd5e1)
                    gfx.setFont(10.0)
                    local label = row.name or ""
                    if row.ownership == "editor-owned" then
                        label = label .. " [editor]"
                    end
                    if row.dirty then
                        label = "* " .. label
                    end
                    gfx.drawText(label, 12, rowY, w - 24, rowH, Justify.centredLeft)
                end
            end
        end
    end)

    shell.scriptCanvas:setOnMouseDown(function(mx, my)
        if type(_G) == "table" and _G.__manifoldImguiScriptListActive == true then
            return
        end
        shell.scriptCanvas:grabKeyboardFocus()
        local row = math.floor((my + shell.scriptScrollY) / shell.scriptRowHeight) + 1
        if row < 1 or row > #shell.scriptRows then
            return
        end
        local r = shell.scriptRows[row]
        if not r or r.section or r.nonInteractive then
            return
        end

        shell:handleLeftListSelection("script", r, function()
            shell:openScriptEditor(r)
            shell.mainTabContent:repaint()
        end)
    end)

    shell.scriptCanvas:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if type(_G) == "table" and _G.__manifoldImguiScriptListActive == true then
            return false
        end
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.scriptCanvas:setOnMouseWheel(function(mx, my, deltaY)
        if type(_G) == "table" and _G.__manifoldImguiScriptListActive == true then
            return
        end
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
    end)

    shell.mainTabBar:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)
        gfx.setColour(0xff1e293b)
        gfx.drawRect(0, 0, w, h, 1)

        shell.mainTabRects = {}

        local x = 6
        local gap = 4
        for i = 1, #shell.mainTabs do
            local tab = shell.mainTabs[i]
            local title = tab.title or "Tab"
            local tw = math.max(64, math.min(180, 18 + #title * 7))
            if x + tw > w - 6 then
                tw = math.max(40, w - 6 - x)
            end
            if tw <= 0 then
                break
            end

            local active = (tab.id == shell.activeMainTabId)
            gfx.setColour(active and 0xff334155 or 0xff1e293b)
            gfx.fillRoundedRect(x, 3, tw, h - 6, 4)
            gfx.setColour(active and 0xff7dd3fc or 0xff94a3b8)
            gfx.setFont(10.0)
            gfx.drawText(title, x + 8, 3, tw - 16, h - 6, Justify.centredLeft)

            shell.mainTabRects[#shell.mainTabRects + 1] = { x = x, y = 3, w = tw, h = h - 6, id = tab.id }
            x = x + tw + gap
            if x >= w - 4 then
                break
            end
        end
    end)

    shell.mainTabBar:setOnMouseDown(function(mx, my)
        for i = 1, #shell.mainTabRects do
            local r = shell.mainTabRects[i]
            if mx >= r.x and mx <= (r.x + r.w) and my >= r.y and my <= (r.y + r.h) then
                shell:activateMainTab(r.id)
                shell.mainTabBar:repaint()
                shell.mainTabContent:repaint()
                shell.previewOverlay:repaint()
                return
            end
        end
    end)

    shell.mainTabContent:setOnDraw(function(node)
        local w = math.floor(node:getWidth())
        local h = math.floor(node:getHeight())

        gfx.setColour(0xff0b1220)
        gfx.fillRect(0, 0, w, h)

        if shell.mode ~= "edit" then
            local tab = shell:_findMainTabById(shell.activeMainTabId)
            if tab then
                gfx.setColour(0xff94a3b8)
                gfx.setFont(11.0)
                gfx.drawText(tab.title or "Tab", 10, 8, w - 20, 18, Justify.centredLeft)
            end
            return
        end

        if shell.editContentMode ~= "script" then
            local projectStatus = shell:getStructuredProjectStatus()
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("Preview mode", 10, 8, w - 20, 18, Justify.centredLeft)

            if type(projectStatus) == "table" then
                local dirtyCount = tonumber(projectStatus.dirtyCount) or 0
                local documentCount = tonumber(projectStatus.documentCount) or 0
                local summary = string.format("Structured project | %d dirty / %d docs | Ctrl+S Save Project | Ctrl+R Reload Project", dirtyCount, documentCount)
                gfx.setColour(dirtyCount > 0 and 0xfffbbf24 or 0xff93c5fd)
                gfx.setFont(10.0)
                gfx.drawText(summary, 10, 28, w - 20, 16, Justify.centredLeft)

                gfx.setColour(0xff475569)
                gfx.setFont(9.0)
                local manifestPath = projectStatus.manifestPath or ""
                local uiRoot = projectStatus.uiRoot or ""
                gfx.drawText("Manifest: " .. manifestPath, 10, 46, w - 20, 14, Justify.centredLeft)
                gfx.drawText("Active UI root: " .. uiRoot, 10, 60, w - 20, 14, Justify.centredLeft)

                local lastError = tostring(projectStatus.lastError or "")
                local lastOperation = tostring(projectStatus.lastOperation or "")
                if lastError ~= "" then
                    gfx.setColour(0xfffca5a5)
                    gfx.setFont(9.0)
                    gfx.drawText("Last structured error" .. (lastOperation ~= "" and (" [" .. lastOperation .. "]") or "") .. ": " .. lastError,
                        10, 76, w - 20, 28, Justify.centredLeft)
                end
            end
            return
        end

        local ed = shell.scriptEditor
        shell.scriptEditorButtonRects = {}
        local mainEditorSurface = type(shell.surfaces) == "table" and shell.surfaces.mainScriptEditor or nil
        local imguiMainActive = shell.mode == "edit"
            and shell.editContentMode == "script"
            and type(ed.path) == "string"
            and ed.path ~= ""
            and type(mainEditorSurface) == "table"
            and mainEditorSurface.visible == true

        gfx.setColour(0xff101827)
        gfx.fillRect(0, 0, w, SCRIPT_EDITOR_STYLE.headerH)
        gfx.setColour(0xff25354d)
        gfx.drawHorizontalLine(SCRIPT_EDITOR_STYLE.headerH - 1, 0, w)

        local title = (ed.name ~= "" and ed.name or "Script") .. ((ed.dirty and " *") or "")
        gfx.setColour(0xffe2e8f0)
        gfx.setFont(11.0)
        gfx.drawText(title, 10, 6, math.max(40, w - 230), 18, Justify.centredLeft)

        gfx.setColour(0xff64748b)
        gfx.setFont(10.0)
        local pathLine = ed.path or ""
        if ed.ownership == "editor-owned" then
            pathLine = pathLine .. "   [editor-owned structured source]"
        end
        gfx.drawText(pathLine, 10, 18, math.max(40, w - 230), 12, Justify.centredLeft)

        local function drawEditorButton(name, label, x, y, bw, bh)
            gfx.setColour(0xff1e293b)
            gfx.fillRoundedRect(x, y, bw, bh, 4)
            gfx.setColour(0xff334155)
            gfx.drawRoundedRect(x, y, bw, bh, 4, 1)
            gfx.setColour(0xffcbd5e1)
            gfx.setFont(10.0)
            gfx.drawText(label, x + 6, y, bw - 12, bh, Justify.centred)
            shell.scriptEditorButtonRects[#shell.scriptEditorButtonRects + 1] = {
                name = name,
                x = x,
                y = y,
                w = bw,
                h = bh,
            }
        end

        local btnW = 56
        local btnH = 20
        local btnGap = 6
        local bx = w - 10 - btnW
        drawEditorButton("close", "Close", bx, 6, btnW, btnH)
        bx = bx - btnGap - btnW
        drawEditorButton("reload", "Reload", bx, 6, btnW, btnH)
        bx = bx - btnGap - btnW
        drawEditorButton("save", "Save", bx, 6, btnW, btnH)

        local pad = SCRIPT_EDITOR_STYLE.pad
        local lineH = SCRIPT_EDITOR_STYLE.lineH
        local gutterW = SCRIPT_EDITOR_STYLE.gutterW
        local statusH = SCRIPT_EDITOR_STYLE.statusH
        local textTop = SCRIPT_EDITOR_STYLE.headerH + pad
        local textX = gutterW + pad + 4
        local perfStart = nowSeconds()

        gfx.setColour(0xff0b1220)
        gfx.fillRect(0, SCRIPT_EDITOR_STYLE.headerH, w, h - SCRIPT_EDITOR_STYLE.headerH)

        if not imguiMainActive then
            gfx.setColour(0xff101a2e)
            gfx.fillRect(0, SCRIPT_EDITOR_STYLE.headerH, gutterW + pad, h - SCRIPT_EDITOR_STYLE.headerH - statusH)
            gfx.setColour(0xff25354d)
            gfx.drawVerticalLine(gutterW + pad, SCRIPT_EDITOR_STYLE.headerH + pad, h - statusH - pad)
        end

        local lines, starts = seBuildLinesCached(ed)
        local lineBuildDone = nowSeconds()
        local visible = seVisibleLineCount(h)
        local maxScroll = math.max(1, #lines - visible + 1)
        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)

        local cursorLine, cursorCol = seLineColCached(ed)
        local cursorDone = nowSeconds()
        local selStart, selEnd = seGetSelectionRange(ed)
        local maxCols = seMaxCols(w)
        local syntaxDrawCalls = 0
        local gutterDrawCalls = 0
        local syntaxSpanCount = 0

        if not imguiMainActive then
            gfx.setColour(0xff7f1d1d)
            gfx.fillRoundedRect(12, SCRIPT_EDITOR_STYLE.headerH + 12, math.max(0, w - 24), math.max(0, h - SCRIPT_EDITOR_STYLE.headerH - statusH - 24), 6)
            gfx.setColour(0xfffecaca)
            gfx.setFont(12.0)
            gfx.drawText("ImGui script editor unavailable", 24, SCRIPT_EDITOR_STYLE.headerH + 28, math.max(0, w - 48), 20, Justify.centredLeft)
            gfx.setColour(0xfffca5a5)
            gfx.setFont(10.0)
            gfx.drawText("This path must not silently fall back to the legacy editor.", 24, SCRIPT_EDITOR_STYLE.headerH + 52, math.max(0, w - 48), 16, Justify.centredLeft)
            gfx.drawText("Fix the ImGui host instead of rendering backup editor UI.", 24, SCRIPT_EDITOR_STYLE.headerH + 68, math.max(0, w - 48), 16, Justify.centredLeft)
        end

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, h - statusH, w, statusH)
        gfx.setColour(0xff22324b)
        gfx.drawHorizontalLine(h - statusH, 0, w)
        gfx.setColour(0xff94a3b8)
        gfx.setFont(SCRIPT_EDITOR_STYLE.fontName, 10.0, FontStyle.plain)
        local statusText = imguiMainActive
            and string.format("%s | Ctrl+S Save | Ctrl+R Reload | Ctrl+W Close", ed.status or "")
            or string.format("ImGui editor unavailable | %s | Ctrl+S Save | Ctrl+R Reload | Ctrl+W Close", ed.status or "")
        if ed.ownership == "editor-owned" then
            statusText = statusText .. " | visual edits save from Preview mode"
        end
        gfx.drawText(statusText, 8, h - statusH, w - 16, statusH, Justify.centredLeft)

        if type(_G) == "table" then
            local perf = _G.__manifoldEditorPerf or {}
            local drawDone = nowSeconds()
            perf.drawCount = (perf.drawCount or 0) + 1
            perf.lastDrawMs = (drawDone - perfStart) * 1000.0
            perf.peakDrawMs = math.max(perf.peakDrawMs or 0, perf.lastDrawMs or 0)
            perf.lastLineBuildMs = (lineBuildDone - perfStart) * 1000.0
            perf.lastCursorLookupMs = (cursorDone - lineBuildDone) * 1000.0
            perf.lastPostCursorMs = (drawDone - cursorDone) * 1000.0
            perf.lastVisibleLines = visible
            perf.lastSyntaxDrawCalls = syntaxDrawCalls
            perf.lastGutterDrawCalls = gutterDrawCalls
            perf.lastSyntaxSpanCount = syntaxSpanCount
            perf.lastTextLen = #(ed.text or "")
            perf.lastScrollRow = ed.scrollRow or 1
            perf.lastCursorLine = cursorLine or 1
            perf.lastCursorCol = cursorCol or 1
            perf.lastEvent = perf.lastEvent or "draw"
            _G.__manifoldEditorPerf = perf
        end
    end)

    shell.mainTabContent:setOnMouseDown(function(mx, my)
        if shell.mode ~= "edit" then
            return
        end

        if shell.editContentMode ~= "script" then
            return
        end

        for i = 1, #shell.scriptEditorButtonRects do
            local r = shell.scriptEditorButtonRects[i]
            if mx >= r.x and mx <= (r.x + r.w) and my >= r.y and my <= (r.y + r.h) then
                if r.name == "save" then
                    shell:saveScriptEditor()
                elseif r.name == "reload" then
                    shell:reloadScriptEditor()
                elseif r.name == "close" then
                    shell:closeScriptEditor()
                end
                shell.mainTabContent:repaint()
                return
            end
        end

        local mainEditorSurface = type(shell.surfaces) == "table" and shell.surfaces.mainScriptEditor or nil
        local imguiMainActive = shell.mode == "edit"
            and shell.editContentMode == "script"
            and type(shell.scriptEditor.path) == "string"
            and shell.scriptEditor.path ~= ""
            and type(mainEditorSurface) == "table"
            and mainEditorSurface.visible == true
        if imguiMainActive then
            return
        end

        local ed = shell.scriptEditor
        ed.focused = true
        shell.mainTabContent:grabKeyboardFocus()

        local pos = shell:scriptEditorPosFromPoint(mx, my)
        ed.cursorPos = pos
        ed.selectionAnchor = pos
        ed.dragAnchorPos = pos
        shell:ensureScriptEditorCursorVisible()
        shell.mainTabContent:repaint()
    end)

    shell.mainTabContent:setOnMouseDrag(function(mx, my, dx, dy)
        local _ = dx
        _ = dy
        if shell.mode ~= "edit" or shell.editContentMode ~= "script" then
            return
        end

        local mainEditorSurface = type(shell.surfaces) == "table" and shell.surfaces.mainScriptEditor or nil
        local imguiMainActive = shell.mode == "edit"
            and shell.editContentMode == "script"
            and type(shell.scriptEditor.path) == "string"
            and shell.scriptEditor.path ~= ""
            and type(mainEditorSurface) == "table"
            and mainEditorSurface.visible == true
        if imguiMainActive then
            return
        end

        local ed = shell.scriptEditor
        if ed.dragAnchorPos == nil then
            ed.dragAnchorPos = ed.cursorPos
        end
        ed.selectionAnchor = ed.dragAnchorPos
        ed.cursorPos = shell:scriptEditorPosFromPoint(mx, my)
        if ed.selectionAnchor == ed.cursorPos then
            seClearSelection(ed)
        end
        shell:ensureScriptEditorCursorVisible()
        shell.mainTabContent:repaint()
    end)

    shell.mainTabContent:setOnMouseUp(function(mx, my)
        local _ = mx
        _ = my
        if shell.mode ~= "edit" or shell.editContentMode ~= "script" then
            return
        end
        local mainEditorSurface = type(shell.surfaces) == "table" and shell.surfaces.mainScriptEditor or nil
        local imguiMainActive = shell.mode == "edit"
            and shell.editContentMode == "script"
            and type(shell.scriptEditor.path) == "string"
            and shell.scriptEditor.path ~= ""
            and type(mainEditorSurface) == "table"
            and mainEditorSurface.visible == true
        if imguiMainActive then
            return
        end
        shell.scriptEditor.dragAnchorPos = nil
    end)

    shell.mainTabContent:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my
        if shell.mode ~= "edit" or shell.editContentMode ~= "script" then
            return
        end

        local mainEditorSurface = type(shell.surfaces) == "table" and shell.surfaces.mainScriptEditor or nil
        local imguiMainActive = shell.mode == "edit"
            and shell.editContentMode == "script"
            and type(shell.scriptEditor.path) == "string"
            and shell.scriptEditor.path ~= ""
            and type(mainEditorSurface) == "table"
            and mainEditorSurface.visible == true
        if imguiMainActive then
            return
        end

        local ed = shell.scriptEditor
        local wheelPerfStart = nowSeconds()
        local lines = seBuildLinesCached(ed)
        local visible = seVisibleLineCount(math.floor(shell.mainTabContent:getHeight()))
        local maxScroll = math.max(1, #lines - visible + 1)
        if deltaY > 0 then
            ed.scrollRow = ed.scrollRow - 2
        elseif deltaY < 0 then
            ed.scrollRow = ed.scrollRow + 2
        end
        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)
        shell.mainTabContent:repaint()
        if type(_G) == "table" then
            local perf = _G.__manifoldEditorPerf or {}
            perf.lastWheelMs = (nowSeconds() - wheelPerfStart) * 1000.0
            perf.peakWheelMs = math.max(perf.peakWheelMs or 0, perf.lastWheelMs or 0)
            perf.lastWheelDelta = deltaY
            perf.lastEvent = "wheel"
            _G.__manifoldEditorPerf = perf
        end
    end)

    shell.mainTabContent:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        local _ = alt
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        if shell.mode ~= "edit" then
            return false
        end

        local k = keyCode or 0
        local c = charCode or 0

        if k == 27 and shell.editContentMode ~= "preview" then
            shell.editContentMode = "preview"
            shell.scriptEditor.focused = false
            shell.scriptEditor.dragAnchorPos = nil
            local w = shell.parentNode:getWidth()
            local h = shell.parentNode:getHeight()
            shell:layout(w, h)
            shell.mainTabContent:repaint()
            return true
        end

        if shell.editContentMode ~= "script" then
            if ctrl and seIsLetterShortcut(k, c, "s") and shell:isStructuredProjectActive() then
                return shell:saveStructuredProjectUi()
            elseif ctrl and seIsLetterShortcut(k, c, "r") and shell:isStructuredProjectActive() then
                return shell:reloadStructuredProjectUi()
            end
            return false
        end

        local ed = shell.scriptEditor
        local handled = false
        local mutated = false
        local keyPerfStart = nowSeconds()

        if ctrl and seIsLetterShortcut(k, c, "s") then
            shell:saveScriptEditor()
            handled = true
        elseif ctrl and seIsLetterShortcut(k, c, "r") then
            shell:reloadScriptEditor()
            handled = true
        elseif ctrl and seIsLetterShortcut(k, c, "w") then
            shell:closeScriptEditor()
            handled = true
        elseif ctrl and seIsLetterShortcut(k, c, "a") then
            ed.selectionAnchor = 1
            ed.cursorPos = #(ed.text or "") + 1
            handled = true
        else
            local lowByte = k % 256
            local isExtended = k >= 0x10000000

            local isBackspace = (k == 8)
            local isDelete = (k == 127 or (isExtended and lowByte == 0xff))
            local isReturn = (k == 13 or k == 10)
            local isTab = (k == 9)
            local isLeft = (k == 63234 or k == 28 or k == 37 or (isExtended and lowByte == 0x51))
            local isRight = (k == 63235 or k == 29 or k == 39 or (isExtended and lowByte == 0x53))
            local isUp = (k == 63232 or k == 30 or k == 38 or (isExtended and lowByte == 0x52))
            local isDown = (k == 63233 or k == 31 or k == 40 or (isExtended and lowByte == 0x54))

            if isBackspace then
                if not seDeleteSelection(ed) and ed.cursorPos > 1 then
                    local src = ed.text or ""
                    ed.text = string.sub(src, 1, ed.cursorPos - 2) .. string.sub(src, ed.cursorPos)
                    ed.cursorPos = ed.cursorPos - 1
                    seClearSelection(ed)
                    seInvalidateCache(ed)
                end
                handled = true
                mutated = true
            elseif isDelete then
                if not seDeleteSelection(ed) and ed.cursorPos <= #(ed.text or "") then
                    local src = ed.text or ""
                    ed.text = string.sub(src, 1, ed.cursorPos - 1) .. string.sub(src, ed.cursorPos + 1)
                    seClearSelection(ed)
                    seInvalidateCache(ed)
                end
                handled = true
                mutated = true
            elseif isReturn then
                seReplaceSelection(ed, "\n")
                handled = true
                mutated = true
            elseif isTab then
                seReplaceSelection(ed, "  ")
                handled = true
                mutated = true
            elseif isLeft then
                seMoveCursor(ed, ed.cursorPos - 1, shift)
                handled = true
            elseif isRight then
                seMoveCursor(ed, ed.cursorPos + 1, shift)
                handled = true
            elseif isUp then
                local line, col = seLineColCached(ed)
                seMoveCursor(ed, sePosFromLineColCached(ed, line - 1, col), shift)
                handled = true
            elseif isDown then
                local line, col = seLineColCached(ed)
                seMoveCursor(ed, sePosFromLineColCached(ed, line + 1, col), shift)
                handled = true
            elseif c >= 32 and c <= 126 then
                seReplaceSelection(ed, string.char(c))
                handled = true
                mutated = true
            elseif k >= 32 and k <= 126 then
                seReplaceSelection(ed, string.char(k))
                handled = true
                mutated = true
            end
        end

        if mutated then
            ed.dirty = true
            ed.status = "Edited (unsaved)"
        end

        if handled then
            shell:ensureScriptEditorCursorVisible()
            shell.mainTabContent:repaint()
            if type(_G) == "table" then
                local perf = _G.__manifoldEditorPerf or {}
                perf.lastKeypressMs = (nowSeconds() - keyPerfStart) * 1000.0
                perf.peakKeypressMs = math.max(perf.peakKeypressMs or 0, perf.lastKeypressMs or 0)
                perf.lastMutated = mutated == true
                perf.lastKeyCode = k
                perf.lastCharCode = c
                perf.lastEvent = "keypress"
                _G.__manifoldEditorPerf = perf
            end
            return true
        end

        return false
    end)

    shell.inspectorCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        local imguiInspectorActive = (type(_G) == "table" and _G.__manifoldImguiInspectorActive == true)

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

        if imguiInspectorActive then
            if shell.leftPanelMode == "scripts" then
                shell:hideRuntimeParamControls(1)
            elseif shell.leftPanelMode ~= "scripts" then
                shell:hideRuntimeParamControls(1)
            end
            return
        end

        if shell.leftPanelMode ~= "scripts" then
            shell:hideRuntimeParamControls(1)
        end

        if shell.leftPanelMode == "scripts" then
            local si = shell.scriptInspector
            local y = 6

            si.runtimeParamRows = {}

            if not si or si.path == "" then
                shell:hideRuntimeParamControls(1)
                gfx.setColour(0xff64748b)
                gfx.setFont(11.0)
                gfx.drawText("Select a script to inspect", 8, 8, w - 16, 20, Justify.centredLeft)
                gfx.setColour(0xff475569)
                gfx.setFont(10.0)
                gfx.drawText("Single-click: inspect | Double-click: open editor", 8, 28, w - 16, 18, Justify.centredLeft)
                return
            end

            local function infoRow(label, value)
                gfx.setColour(0xff64748b)
                gfx.setFont(10.0)
                gfx.drawText(label, 8, y, math.floor(w * 0.34), 16, Justify.centredLeft)
                gfx.setColour(0xffcbd5e1)
                gfx.drawText(value or "", math.floor(w * 0.34), y, math.floor(w * 0.66) - 10, 16, Justify.centredLeft)
                y = y + 16
            end

            infoRow("Script", si.name or "")
            infoRow("Kind", si.kind or "")
            if si.ownership and si.ownership ~= "" then
                infoRow("Ownership", si.ownership)
                local docStatus = shell:getStructuredDocumentStatus(si.path)
                if type(docStatus) == "table" then
                    infoRow("Dirty", docStatus.dirty == true and "yes" or "no")
                end
                local projectStatus = shell:getStructuredProjectStatus()
                if type(projectStatus) == "table" and tostring(projectStatus.lastError or "") ~= "" then
                    infoRow("Last Error", tostring(projectStatus.lastError or ""))
                end
            end
            infoRow("Path", si.path or "")
            if si.kind == "dsp" then
                local declared = si.params or {}
                local runtimeParams = si.runtimeParams or {}
                local activeRuntime = 0
                for i = 1, #runtimeParams do
                    if runtimeParams[i].active then
                        activeRuntime = activeRuntime + 1
                    end
                end

                infoRow("Params (declared)", tostring(#declared))
                infoRow("Params (runtime)", string.format("%d/%d active", activeRuntime, #runtimeParams))
                local graph = si.graph or { nodes = {}, edges = {} }
                infoRow("Graph", string.format("%d nodes / %d edges", #(graph.nodes or {}), #(graph.edges or {})))

                local btnH = 18
                if type(si.runButtonRect) == "table" then
                    gfx.setColour(0xff1e293b)
                    gfx.fillRoundedRect(si.runButtonRect.x, si.runButtonRect.y, si.runButtonRect.w, si.runButtonRect.h, 4)
                    gfx.setColour(0xff334155)
                    gfx.drawRoundedRect(si.runButtonRect.x, si.runButtonRect.y, si.runButtonRect.w, si.runButtonRect.h, 4, 1)
                    gfx.setColour(0xffcbd5e1)
                    gfx.setFont(9.0)
                    gfx.drawText("Run in Preview Slot", si.runButtonRect.x + 4, si.runButtonRect.y, si.runButtonRect.w - 8, si.runButtonRect.h, Justify.centred)
                end

                if type(si.stopButtonRect) == "table" then
                    gfx.setColour(0xff1e293b)
                    gfx.fillRoundedRect(si.stopButtonRect.x, si.stopButtonRect.y, si.stopButtonRect.w, si.stopButtonRect.h, 4)
                    gfx.setColour(0xff334155)
                    gfx.drawRoundedRect(si.stopButtonRect.x, si.stopButtonRect.y, si.stopButtonRect.w, si.stopButtonRect.h, 4, 1)
                    gfx.setColour(0xffcbd5e1)
                    gfx.drawText("Stop Preview Slot", si.stopButtonRect.x + 4, si.stopButtonRect.y, si.stopButtonRect.w - 8, si.stopButtonRect.h, Justify.centred)
                end

                y = y + btnH + 4

                if si.runtimeStatus and si.runtimeStatus ~= "" then
                    gfx.setColour(0xff7dd3fc)
                    gfx.setFont(9.0)
                    gfx.drawText(si.runtimeStatus, 8, y, w - 16, 14, Justify.centredLeft)
                    y = y + 14
                end

                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                gfx.drawText("Declared Params", 8, y, w - 16, 14, Justify.centredLeft)
                y = y + 14

                if #declared == 0 then
                    gfx.setColour(0xff64748b)
                    gfx.setFont(9.0)
                    gfx.drawText("No ctx.params.register(...) found", 10, y, w - 20, 14, Justify.centredLeft)
                    y = y + 14
                else
                    local maxRows = math.min(6, #declared)
                    for i = 1, maxRows do
                        local p = declared[i]
                        gfx.setColour(0xff64748b)
                        gfx.setFont(8.5)
                        gfx.drawText(p.path or "", 10, y, math.floor(w * 0.68), 14, Justify.centredLeft)
                        local rhs = ""
                        if p.default ~= nil then
                            rhs = "d=" .. tostring(p.default)
                        end
                        gfx.setColour(0xffcbd5e1)
                        gfx.drawText(rhs, math.floor(w * 0.68), y, math.floor(w * 0.32) - 12, 14, Justify.centredRight)
                        y = y + 14
                    end
                    if #declared > maxRows then
                        gfx.setColour(0xff475569)
                        gfx.setFont(8.5)
                        gfx.drawText("..." .. tostring(#declared - maxRows) .. " more", 10, y, w - 20, 12, Justify.centredLeft)
                        y = y + 12
                    end
                end

                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                gfx.drawText("Runtime Params", 8, y, w - 16, 14, Justify.centredLeft)
                y = y + 14
                gfx.setColour(0xff475569)
                gfx.setFont(8.0)
                gfx.drawText("- [ value ] + | drag [value] continuously | Ctrl+click [value] to type", 10, y, w - 20, 12, Justify.centredLeft)
                y = y + 12

                si.runtimeParamRows = {}
                if #runtimeParams == 0 then
                    shell:hideRuntimeParamControls(1)
                    gfx.setColour(0xff64748b)
                    gfx.setFont(9.0)
                    gfx.drawText("No runtime params (run script first)", 10, y, w - 20, 14, Justify.centredLeft)
                    y = y + 14
                else
                    local maxRows = math.min(6, #runtimeParams)
                    shell:ensureRuntimeParamControlPool(maxRows)

                    for i = 1, maxRows do
                        local rp = runtimeParams[i]
                        local rowH = 20
                        local btnW = 16
                        local ctrlGap = 4
                        local sliderW = math.max(58, math.floor(w * 0.24))
                        local clusterW = btnW + ctrlGap + sliderW + ctrlGap + btnW
                        local clusterX = math.floor(w - 10 - clusterW)

                        local pathRect = { x = 10, y = y + 1, w = math.max(40, clusterX - 16), h = 18 }
                        local minusRect = { x = clusterX, y = y + 3, w = btnW, h = 14 }
                        local sliderRect = { x = clusterX + btnW + ctrlGap, y = y + 2, w = sliderW, h = 16 }
                        local plusRect = { x = sliderRect.x + sliderRect.w + ctrlGap, y = y + 3, w = btnW, h = 14 }

                        gfx.setColour(rp.active and 0xff64748b or 0xff475569)
                        gfx.setFont(8.5)
                        gfx.drawText(rp.path or "", pathRect.x, pathRect.y, pathRect.w, pathRect.h, Justify.centredLeft)

                        local rowValue = (rp.numericValue ~= nil) and rp.numericValue or tonumber(rp.value)
                        local row = {
                            endpointPath = rp.endpointPath or rp.path,
                            min = rp.min,
                            max = rp.max,
                            step = rp.step,
                            active = rp.active,
                            value = rowValue,
                        }

                        local control = si.runtimeParamControls[i]
                        if control then
                            control.row = row
                            control.minus.node:setBounds(minusRect.x, minusRect.y, minusRect.w, minusRect.h)
                            control.slider.node:setBounds(sliderRect.x, sliderRect.y, sliderRect.w, sliderRect.h)
                            control.plus.node:setBounds(plusRect.x, plusRect.y, plusRect.w, plusRect.h)

                            control.minus:setEnabled(rp.active)
                            control.slider:setEnabled(rp.active)
                            control.plus:setEnabled(rp.active)

                            local lo = tonumber(rp.min)
                            local hi = tonumber(rp.max)
                            local step = tonumber(rp.step) or 0
                            if lo == nil then lo = 0 end
                            if hi == nil or hi <= lo then hi = lo + 1 end

                            control.slider:setVisualRange(lo, hi, step)
                            control.slider:setValue(tonumber(rowValue) or lo)

                            local editingThis = si.runtimeInputActive and si.runtimeInputEndpointPath == row.endpointPath
                            control.slider:setEditing(editingThis)
                            control.slider:setDisplayText(editingThis and (si.runtimeInputText or "") or (rp.value or ""))
                        end

                        y = y + rowH
                    end

                    shell:hideRuntimeParamControls(maxRows + 1)

                    if #runtimeParams > maxRows then
                        gfx.setColour(0xff475569)
                        gfx.setFont(8.5)
                        gfx.drawText("..." .. tostring(#runtimeParams - maxRows) .. " more", 10, y, w - 20, 12, Justify.centredLeft)
                        y = y + 12
                    end
                end
            else
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
                shell:hideRuntimeParamControls(1)
            end

            y = y + 4

            local function drawSectionHeader(text, collapsed, rect)
                if type(rect) ~= "table" then
                    return
                end
                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(rect.x, rect.y, rect.w, rect.h, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(rect.x, rect.y, rect.w, rect.h, 4, 1)
                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                local marker = collapsed and "[+] " or "[-] "
                gfx.drawText(marker .. text, rect.x + 6, rect.y, rect.w - 12, rect.h, Justify.centredLeft)
            end

            drawSectionHeader("Inline Script", si.editorCollapsed, si.editorHeaderRect)

            if type(si.editorBodyRect) == "table" then
                gfx.setColour(0xff0b1220)
                gfx.fillRoundedRect(si.editorBodyRect.x, si.editorBodyRect.y, si.editorBodyRect.w, si.editorBodyRect.h, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(si.editorBodyRect.x, si.editorBodyRect.y, si.editorBodyRect.w, si.editorBodyRect.h, 4, 1)

                local imguiInlineActive = type(_G) == "table"
                    and _G.__manifoldImguiInspectorActive == true
                    and si.editorCollapsed ~= true
                    and type(si.path) == "string"
                    and si.path ~= ""
                if not imguiInlineActive then
                    gfx.setColour(0xff7f1d1d)
                    gfx.fillRoundedRect(si.editorBodyRect.x + 6, si.editorBodyRect.y + 6, math.max(0, si.editorBodyRect.w - 12), math.max(0, si.editorBodyRect.h - 12), 4)
                    gfx.setColour(0xfffecaca)
                    gfx.setFont(11.0)
                    gfx.drawText("ImGui inline editor unavailable", si.editorBodyRect.x + 14, si.editorBodyRect.y + 14, math.max(0, si.editorBodyRect.w - 28), 18, Justify.centredLeft)
                    gfx.setColour(0xfffca5a5)
                    gfx.setFont(9.0)
                    gfx.drawText("Legacy inline fallback is disabled.", si.editorBodyRect.x + 14, si.editorBodyRect.y + 34, math.max(0, si.editorBodyRect.w - 28), 14, Justify.centredLeft)
                    gfx.drawText("Fix the ImGui host instead.", si.editorBodyRect.x + 14, si.editorBodyRect.y + 48, math.max(0, si.editorBodyRect.w - 28), 14, Justify.centredLeft)
                end
            end

            if si.kind == "dsp" then
                drawSectionHeader("DSP Graph (drag to pan)", si.graphCollapsed, si.graphHeaderRect)

                if type(si.graphBodyRect) == "table" then
                    gfx.setColour(0xff0b1220)
                    gfx.fillRoundedRect(si.graphBodyRect.x, si.graphBodyRect.y, si.graphBodyRect.w, si.graphBodyRect.h, 4)
                    gfx.setColour(0xff334155)
                    gfx.drawRoundedRect(si.graphBodyRect.x, si.graphBodyRect.y, si.graphBodyRect.w, si.graphBodyRect.h, 4, 1)

                    local graph = si.graph or { nodes = {}, edges = {} }
                    local nodes = graph.nodes or {}
                    local edges = graph.edges or {}

                    if #nodes == 0 then
                        gfx.setColour(0xff64748b)
                        gfx.setFont(10.0)
                        gfx.drawText("No graph parsed", si.graphBodyRect.x + 8, si.graphBodyRect.y + 8, si.graphBodyRect.w - 16, 16, Justify.centredLeft)
                    else
                        local positions = {}
                        local cols = math.max(1, math.ceil(math.sqrt(#nodes)))
                        local cellW = 110
                        local cellH = 48
                        local originX = si.graphBodyRect.x + 12 + (si.graphPanX or 0)
                        local originY = si.graphBodyRect.y + 12 + (si.graphPanY or 0)
                        local nodeW = 96
                        local nodeH = 24

                        for i = 1, #nodes do
                            local col = (i - 1) % cols
                            local row = math.floor((i - 1) / cols)
                            local x = originX + col * cellW
                            local yNode = originY + row * cellH
                            positions[i] = { x = x, y = yNode, cx = x + math.floor(nodeW * 0.5), cy = yNode + math.floor(nodeH * 0.5) }
                        end

                        gfx.setColour(0xff475569)
                        for i = 1, #edges do
                            local e = edges[i]
                            local a = positions[e.from]
                            local b = positions[e.to]
                            if a and b then
                                gfx.drawLine(a.cx, a.cy, b.cx, b.cy)
                            end
                        end

                        for i = 1, #nodes do
                            local n = nodes[i]
                            local p = positions[i]
                            gfx.setColour(0xff1e293b)
                            gfx.fillRoundedRect(p.x, p.y, nodeW, nodeH, 4)
                            gfx.setColour(0xff38bdf8)
                            gfx.drawRoundedRect(p.x, p.y, nodeW, nodeH, 4, 1)
                            gfx.setColour(0xffe2e8f0)
                            gfx.setFont(9.0)
                            local label = (n.var or "n") .. ":" .. (n.prim or "node")
                            gfx.drawText(label, p.x + 4, p.y + 3, nodeW - 8, nodeH - 6, Justify.centredLeft)
                        end
                    end
                end
            end

            return
        end

        if #shell.inspectorRows == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No selection", 6, 6, w - 12, 20, Justify.centredLeft)
            return
        end

        local rowH = shell.inspectorRowHeight
        local startRow = math.floor(shell.inspectorScrollY / rowH) + 1
        local rowOffset = -(shell.inspectorScrollY % rowH)

        for i = startRow, #shell.inspectorRows do
            local y = math.floor(rowOffset + (i - startRow) * rowH)
            if y > h then
                break
            end
            if y + rowH >= 0 then
                local row = shell.inspectorRows[i]
                local isSection = row.value == ""
                local isActive = shell.activeConfigProperty ~= nil and row.path ~= nil and shell.activeConfigProperty.path == row.path

                if isActive then
                    gfx.setColour(0xff1e3a5f)
                    gfx.fillRoundedRect(2, y + 1, w - 4, rowH - 2, 3)
                end

                if isSection then
                    gfx.setColour(0xff94a3b8)
                    gfx.setFont(11.0)
                    gfx.drawText(row.key, 6, y, w - 12, rowH, Justify.centredLeft)
                else
                    gfx.setColour(isActive and 0xff7dd3fc or 0xff64748b)
                    gfx.setFont(10.0)
                    gfx.drawText(row.key, 6, y, math.floor(w * 0.45), rowH, Justify.centredLeft)

                    gfx.setColour(isActive and 0xfff8fafc or 0xffcbd5e1)
                    gfx.setFont(10.0)
                    gfx.drawText(row.value, math.floor(w * 0.45), y, math.floor(w * 0.55) - 6, rowH, Justify.centredRight)
                end
            end
        end
    end)

    shell.inspectorCanvas:setOnMouseDown(function(mx, my, shift, ctrl, alt)
        local _ = shift
        _ = alt
        if type(_G) == "table" and _G.__manifoldImguiInspectorActive == true then
            return
        end
        shell.inspectorCanvas:grabKeyboardFocus()

        if shell.leftPanelMode == "scripts" then
            local si = shell.scriptInspector
            if pointInRect(mx, my, si.runButtonRect) then
                shell:runSelectedDspScriptForInspector()
                return
            end
            if pointInRect(mx, my, si.stopButtonRect) then
                shell:stopSelectedDspScriptForInspector()
                return
            end
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

            if pointInRect(mx, my, si.editorHeaderRect) then
                shell:setScriptInspectorEditorCollapsed(not si.editorCollapsed)
                return
            end
            if pointInRect(mx, my, si.graphHeaderRect) then
                shell:setScriptInspectorGraphCollapsed(not si.graphCollapsed)
                return
            end
            if pointInRect(mx, my, si.graphBodyRect) then
                si.graphDragging = true
                si.graphDragStartX = mx
                si.graphDragStartY = my
                si.graphDragPanX = si.graphPanX or 0
                si.graphDragPanY = si.graphPanY or 0
                return
            end
            return
        end

        local rowIndex = math.floor((my + shell.inspectorScrollY) / shell.inspectorRowHeight) + 1
        if rowIndex < 1 or rowIndex > #shell.inspectorRows then
            shell:_showActivePropertyEditor(nil)
            return
        end

        local row = shell.inspectorRows[rowIndex]
        if row and row.isConfig and row.editorType ~= nil then
            shell:_showActivePropertyEditor(row)
        else
            shell:_showActivePropertyEditor(nil)
        end
    end)

    shell.inspectorCanvas:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        local _ = shift
        _ = ctrl
        _ = alt

        if type(_G) == "table" and _G.__manifoldImguiInspectorActive == true then
            return false
        end

        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end

        if shell.leftPanelMode ~= "scripts" then
            local k = keyCode or 0
            local isUp = (k == 63232 or k == 30 or k == 38)
            local isDown = (k == 63233 or k == 31 or k == 40)
            local isPageUp = (k == 63276 or k == 33)
            local isPageDown = (k == 63277 or k == 34)

            if isUp or isDown or isPageUp or isPageDown then
                local rows = (isPageUp or isPageDown) and 8 or 1
                local sign = (isUp or isPageUp) and -1 or 1
                local contentHeight = #shell.inspectorRows * shell.inspectorRowHeight
                local maxScroll = math.max(0, contentHeight - shell.inspectorViewportH)
                local nextScroll = clamp(shell.inspectorScrollY + sign * rows * shell.inspectorRowHeight, 0, maxScroll)
                if nextScroll ~= shell.inspectorScrollY then
                    shell.inspectorScrollY = nextScroll
                    shell.inspectorCanvas:repaint()
                end
                return true
            end

            return false
        end

        local si = shell.scriptInspector
        if not si.runtimeInputActive then
            return false
        end

        local k = keyCode or 0
        local c = charCode or 0

        if k == 27 then
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
            shell.inspectorCanvas:repaint()
            return true
        end

        if k == 13 or k == 10 then
            local ok = shell:setRuntimeParamAbsolute(
                si.runtimeInputEndpointPath,
                tonumber(si.runtimeInputText),
                si.runtimeInputMin,
                si.runtimeInputMax
            )
            if ok then
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
            end
            shell.inspectorCanvas:repaint()
            return true
        end

        if k == 8 then
            si.runtimeInputText = string.sub(si.runtimeInputText or "", 1, math.max(0, #(si.runtimeInputText or "") - 1))
            shell.inspectorCanvas:repaint()
            return true
        end

        local ch = nil
        if c >= 32 and c <= 126 then
            ch = string.char(c)
        elseif k >= 32 and k <= 126 then
            ch = string.char(k)
        end

        if ch ~= nil then
            if string.match(ch, "[0-9%+%-%./eE]") then
                si.runtimeInputText = (si.runtimeInputText or "") .. ch
                shell.inspectorCanvas:repaint()
                return true
            end
        end

        return false
    end)

    shell.inspectorCanvas:setOnMouseDrag(function(mx, my, dx, dy)
        local _ = dx
        _ = dy
        if type(_G) == "table" and _G.__manifoldImguiInspectorActive == true then
            return
        end
        if shell.leftPanelMode ~= "scripts" then
            return
        end

        local si = shell.scriptInspector
        if si.graphDragging then
            si.graphPanX = (si.graphDragPanX or 0) + (mx - (si.graphDragStartX or mx))
            si.graphPanY = (si.graphDragPanY or 0) + (my - (si.graphDragStartY or my))
            shell.inspectorCanvas:repaint()
        end
    end)

    shell.inspectorCanvas:setOnMouseUp(function(mx, my)
        local _ = mx
        _ = my
        if type(_G) == "table" and _G.__manifoldImguiInspectorActive == true then
            return
        end
        if shell.leftPanelMode ~= "scripts" then
            return
        end

        local si = shell.scriptInspector
        si.graphDragging = false
    end)

    shell.inspectorCanvas:setOnMouseWheel(function(mx, my, deltaY)
        if type(_G) == "table" and _G.__manifoldImguiInspectorActive == true then
            return
        end
        if shell.leftPanelMode == "scripts" then
            local si = shell.scriptInspector
            if pointInRect(mx, my, si.editorBodyRect) then
                local imguiInlineActive = type(_G) == "table"
                    and _G.__manifoldImguiInspectorActive == true
                    and si.editorCollapsed ~= true
                    and type(si.path) == "string"
                    and si.path ~= ""
                if imguiInlineActive then
                    return
                end
                local lines = seBuildLinesCached(si)
                local visible = math.max(1, math.floor(((si.editorBodyRect and si.editorBodyRect.h or 80) - 8) / 14))
                local maxScroll = math.max(1, #lines - visible + 1)
                local nextRow = clamp((si.editorScrollRow or 1) - deltaY * 2, 1, maxScroll)
                if nextRow ~= si.editorScrollRow then
                    si.editorScrollRow = nextRow
                    shell.inspectorCanvas:repaint()
                end
                return
            end
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

    shell.consoleOverlay:setOnDraw(function(node)
        if shell.console.visible ~= true then
            return
        end

        local w = node:getWidth()
        local h = node:getHeight()
        local c = shell.console

        gfx.setColour(0xdd020617)
        gfx.fillRoundedRect(0, 0, w, h, 6)
        gfx.setColour(0xff334155)
        gfx.drawRoundedRect(0, 0, w, h, 6, 1)

        gfx.setColour(0xff93c5fd)
        gfx.setFont(11.0)
        gfx.drawText("Dev Console (~)  |  Ctrl+Shift+C copy id  Ctrl+Shift+V paste", 8, 4, w - 16, 16, Justify.centredLeft)

        local inputH = 24
        local bodyY = 22
        local bodyH = math.max(10, h - bodyY - inputH - 6)
        local lineH = 14
        local visibleLines = math.max(1, math.floor(bodyH / lineH))

        local lines = c.lines or {}
        local scroll = clamp(c.scrollOffset or 0, 0, math.max(0, #lines - 1))
        c.scrollOffset = scroll
        local endIndex = math.max(0, #lines - scroll)
        local startIndex = math.max(1, endIndex - visibleLines + 1)

        gfx.setColour(0x660f172a)
        gfx.fillRect(6, bodyY, w - 12, bodyH)

        local y = bodyY
        for i = startIndex, endIndex do
            local ln = lines[i]
            if ln then
                gfx.setColour(ln.colour or 0xffcbd5e1)
                gfx.setFont(11.0)
                gfx.drawText(tostring(ln.text or ""), 10, y, w - 20, lineH, Justify.centredLeft)
            end
            y = y + lineH
        end

        local inputY = h - inputH - 4
        gfx.setColour(0xff0f172a)
        gfx.fillRoundedRect(6, inputY, w - 12, inputH, 4)
        gfx.setColour(0xff334155)
        gfx.drawRoundedRect(6, inputY, w - 12, inputH, 4, 1)
        gfx.setColour(0xffe2e8f0)
        gfx.setFont(11.0)
        local inputText = "> " .. tostring(c.input or "")
        gfx.drawText(inputText, 12, inputY + 3, w - 24, inputH - 4, Justify.centredLeft)
    end)

    shell.consoleOverlay:setOnMouseDown(function(mx, my, shift, ctrl, alt)
        local _ = mx
        _ = my
        _ = shift
        _ = ctrl
        _ = alt
        if shell.console.visible ~= true then
            return
        end
        shell.consoleOverlay:grabKeyboardFocus()
    end)

    shell.consoleOverlay:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my
        if shell.console.visible ~= true then
            return
        end

        local c = shell.console
        local step = math.max(1, math.floor(math.abs(deltaY) + 0.5))
        if deltaY > 0 then
            c.scrollOffset = math.min(#c.lines, (c.scrollOffset or 0) + step)
        else
            c.scrollOffset = math.max(0, (c.scrollOffset or 0) - step)
        end
        shell.consoleOverlay:repaint()
    end)

    shell.consoleOverlay:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.previewOverlay:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        local step = computeGridStep(shell.contentScale)
        local d1x, d1y = shell:previewToDesign(0, 0)
        local d2x, d2y = shell:previewToDesign(w, h)
        local minDx = math.min(d1x, d2x)
        local maxDx = math.max(d1x, d2x)
        local minDy = math.min(d1y, d2y)
        local maxDy = math.max(d1y, d2y)

        local dotCountEstimate = ((maxDx - minDx) / step + 1) * ((maxDy - minDy) / step + 1)
        while dotCountEstimate > 6000 do
            step = step * 2
            dotCountEstimate = ((maxDx - minDx) / step + 1) * ((maxDy - minDy) / step + 1)
        end

        local startX = math.floor(minDx / step) * step
        local endX = math.ceil(maxDx / step) * step
        local startY = math.floor(minDy / step) * step
        local endY = math.ceil(maxDy / step) * step

        gfx.setColour(0x14475b73)
        for gx = startX, endX, step do
            for gy = startY, endY, step do
                local px, py = shell:designToPreview(gx, gy)
                gfx.fillRect(math.floor(px), math.floor(py), 1, 1)
            end
        end

        local majorStep = step * 4
        local majorStartX = math.floor(minDx / majorStep) * majorStep
        local majorEndX = math.ceil(maxDx / majorStep) * majorStep
        local majorStartY = math.floor(minDy / majorStep) * majorStep
        local majorEndY = math.ceil(maxDy / majorStep) * majorStep

        gfx.setColour(0x2870849c)
        for gx = majorStartX, majorEndX, majorStep do
            for gy = majorStartY, majorEndY, majorStep do
                local px, py = shell:designToPreview(gx, gy)
                gfx.fillRect(math.floor(px), math.floor(py), 2, 2)
            end
        end

        gfx.setColour(0x18ffffff)
        gfx.drawRect(0, 0, w, h, 1)

        local workspaceX, workspaceY, workspaceWDesign, workspaceHDesign = shell:getWorkspaceDesignRect()
        local wx1, wy1 = shell:designToPreview(workspaceX, workspaceY)
        local wx2, wy2 = shell:designToPreview(workspaceX + workspaceWDesign, workspaceY + workspaceHDesign)
        gfx.setColour(0x35e2e8f0)
        gfx.drawRect(math.floor(wx1), math.floor(wy1), math.floor(wx2 - wx1), math.floor(wy2 - wy1), 1)

        local viewportDX, viewportDY, viewportDW, viewportDH = shell:getViewportDesignRect()
        local vx1, vy1 = shell:designToPreview(viewportDX, viewportDY)
        local vx2, vy2 = shell:designToPreview(viewportDX + viewportDW, viewportDY + viewportDH)
        gfx.setColour(0x70ffffff)
        gfx.drawRect(math.floor(vx1), math.floor(vy1), math.floor(vx2 - vx1), math.floor(vy2 - vy1), 1)

        local selectedRows = {}
        local minX, minY = nil, nil
        local maxX, maxY = nil, nil

        for i = 1, #shell.selectedWidgets do
            local row = shell:_findTreeRowByCanvas(shell.selectedWidgets[i])
            if row then
                selectedRows[#selectedRows + 1] = row

                local sx, sy = shell:designToPreview(row.x, row.y)
                local ex, ey = shell:designToPreview(row.x + row.w, row.y + row.h)
                local sw = ex - sx
                local sh = ey - sy
                if sw > 0 and sh > 0 then
                    local isPrimary = (shell.selectedWidget == row.canvas)
                    gfx.setColour(isPrimary and 0xb0f59e0b or 0xd060a5fa)
                    gfx.drawRoundedRect(sx, sy, sw, sh, 4, isPrimary and 2 or 2)

                    minX = (minX == nil) and sx or math.min(minX, sx)
                    minY = (minY == nil) and sy or math.min(minY, sy)
                    maxX = (maxX == nil) and (sx + sw) or math.max(maxX, sx + sw)
                    maxY = (maxY == nil) and (sy + sh) or math.max(maxY, sy + sh)
                end
            end
        end

        if #selectedRows > 1 and minX ~= nil then
            gfx.setColour(0x8060a5fa)
            gfx.drawRoundedRect(minX, minY, maxX - minX, maxY - minY, 6, 2)
        end

        local handleRow = shell:getHandleTargetRect()
        if handleRow then
            local handles = shell:getSelectionHandleRects(handleRow)
            gfx.setColour(0xfff59e0b)
            for i = 1, #handles do
                local hh = handles[i]
                gfx.fillRoundedRect(hh.x, hh.y, hh.w, hh.h, 2)
            end
        end

        if shell.dragState and shell.dragState.mode == "marquee" then
            local x1 = math.min(shell.dragState.startMx, shell.dragState.currentMx or shell.dragState.startMx)
            local y1 = math.min(shell.dragState.startMy, shell.dragState.currentMy or shell.dragState.startMy)
            local x2 = math.max(shell.dragState.startMx, shell.dragState.currentMx or shell.dragState.startMx)
            local y2 = math.max(shell.dragState.startMy, shell.dragState.currentMy or shell.dragState.startMy)
            gfx.setColour(0x3360a5fa)
            gfx.fillRect(x1, y1, x2 - x1, y2 - y1)
            gfx.setColour(0xff60a5fa)
            gfx.drawRect(x1, y1, x2 - x1, y2 - y1, 1)
        end
    end)

    shell.previewOverlay:setWantsKeyboardFocus(true)
    shell.previewOverlay:setOnKeyPress(function(keyCode, textChar, shift, ctrl, alt)
        if shell:handleGlobalDevHotkeys(keyCode, textChar, shift, ctrl, alt) then
            return true
        end

        if shell.mode ~= "edit" then
            return false
        end

        if ctrl and (textChar == 122 or textChar == 90 or keyCode == 122 or keyCode == 90) then -- z / Z
            if shift then
                shell:redo()
            else
                shell:undo()
            end
            return true
        end

        if textChar == 43 or textChar == 61 then -- + or =
            shell:zoomAtPreviewPoint(1.1, shell.previewW * 0.5, shell.previewH * 0.5)
            return true
        end
        if textChar == 45 or textChar == 95 then -- - or _
            shell:zoomAtPreviewPoint(0.9, shell.previewW * 0.5, shell.previewH * 0.5)
            return true
        end
        if textChar == 48 then -- 0
            shell.autoFit = true
            shell.panX = 0
            shell.panY = 0
            local ww = shell.parentNode:getWidth()
            local hh = shell.parentNode:getHeight()
            shell:layout(ww, hh)
            return true
        end
        return false
    end)

    shell.previewOverlay:setOnMouseWheel(function(mx, my, deltaY, shift, ctrl, alt)
        if shell.mode ~= "edit" then
            return
        end

        if alt then
            local factor = deltaY > 0 and 1.1 or 0.9
            shell:zoomAtPreviewPoint(factor, mx, my)
        end
    end)

    shell.previewOverlay:setOnMouseDown(function(mx, my, shift, ctrl, alt)
        if shell.mode ~= "edit" then
            return
        end

        if type(_G) == "table" then
            _G.__manifoldPreviewDragDebug = _G.__manifoldPreviewDragDebug or { down = 0, drag = 0, up = 0, lastMode = "", lastHit = "" }
            local dbg = _G.__manifoldPreviewDragDebug
            dbg.down = (dbg.down or 0) + 1
            dbg.lastDown = { mx = mx, my = my, shift = shift, ctrl = ctrl, alt = alt }
        end

        shell.previewOverlay:grabKeyboardFocus()

        if shell.navMode == "pan" and not shift and not ctrl then
            shell.dragState = {
                mode = "pan",
                startPanX = shell.panX,
                startPanY = shell.panY,
            }
            return
        end

        local designX, designY = shell:previewToDesign(mx, my)

        if ctrl then
            local pendingHit = shell:hitTestWidget(designX, designY)
            shell.dragState = {
                mode = "marqueePending",
                startMx = mx,
                startMy = my,
                currentMx = mx,
                currentMy = my,
                pendingHit = pendingHit,
            }
            return
        end

        local handle = shell:hitTestSelectionHandle(mx, my)
        if handle and #shell.selectedWidgets > 0 then
            local bounds = shell:getSelectionBounds()
            if bounds then
                local sdx, sdy = shell:previewToDesign(mx, my)
                local targets = {}
                for i = 1, #shell.selectedWidgets do
                    local c = shell.selectedWidgets[i]
                    local bx, by, bw, bh = c:getBounds()
                    local row = shell:_findTreeRowByCanvas(c)
                    targets[#targets + 1] = {
                        canvas = c,
                        x = bx,
                        y = by,
                        w = bw,
                        h = bh,
                        rowX = row and row.x or bx,
                        rowY = row and row.y or by,
                        parentDesignX = (row and row.x or bx) - bx,
                        parentDesignY = (row and row.y or by) - by,
                    }
                end

                shell.dragState = {
                    mode = "resize",
                    handle = handle,
                    startDesignX = sdx,
                    startDesignY = sdy,
                    groupX = bounds.x,
                    groupY = bounds.y,
                    groupW = bounds.w,
                    groupH = bounds.h,
                    targets = targets,
                    historyBeforeScene = shell:_captureSceneState(),
                    historyBeforeSelection = shell:_captureSelectionState(),
                }
                return
            end
        end

        local hit = shell:hitTestWidget(designX, designY)

        if type(_G) == "table" then
            local dbg = _G.__manifoldPreviewDragDebug or {}
            local row = hit and shell:_findTreeRowByCanvas(hit) or nil
            dbg.lastHit = row and row.path or ""
            _G.__manifoldPreviewDragDebug = dbg
        end

        if shift and hit ~= nil then
            local targets = {}
            if shell:isCanvasSelected(hit) and #shell.selectedWidgets > 1 then
                for i = 1, #shell.selectedWidgets do
                    targets[#targets + 1] = shell.selectedWidgets[i]
                end
            else
                targets[1] = hit
                shell:setSelection(targets, hit)
            end

            local startBounds = {}
            for i = 1, #targets do
                local c = targets[i]
                local bx, by, bw, bh = c:getBounds()
                startBounds[i] = { canvas = c, x = bx, y = by, w = bw, h = bh }
            end

            shell.dragState = {
                mode = "move",
                startDesignX = designX,
                startDesignY = designY,
                targets = startBounds,
                historyBeforeScene = shell:_captureSceneState(),
                historyBeforeSelection = shell:_captureSelectionState(),
            }
            if type(_G) == "table" then
                local dbg = _G.__manifoldPreviewDragDebug or {}
                dbg.lastMode = "move"
                dbg.targets = #targets
                _G.__manifoldPreviewDragDebug = dbg
            end
            return
        end

        shell:selectWidget(hit)
    end)

    shell.previewOverlay:setOnMouseDrag(function(mx, my, dx, dy, shift, ctrl, alt)
        if shell.mode ~= "edit" or shell.dragState == nil then
            return
        end

        if type(_G) == "table" then
            local dbg = _G.__manifoldPreviewDragDebug or {}
            dbg.drag = (dbg.drag or 0) + 1
            dbg.lastDrag = { mx = mx, my = my, dx = dx, dy = dy, shift = shift, ctrl = ctrl, alt = alt }
            _G.__manifoldPreviewDragDebug = dbg
        end

        local ds = shell.dragState
        local runtime = (type(_G) == "table") and _G.__manifoldStructuredUiRuntime or nil
        if type(runtime) == "table" and (ds.mode == "move" or ds.mode == "resize") then
            runtime.suspendLayoutPass = true
        end

        if ds.mode == "pan" then
            shell.autoFit = false
            shell.panX = ds.startPanX + dx
            shell.panY = ds.startPanY + dy
            local ww = shell.parentNode:getWidth()
            local hh = shell.parentNode:getHeight()
            shell:layout(ww, hh)
            return
        end

        if ds.mode == "marqueePending" then
            ds.currentMx = mx
            ds.currentMy = my
            if math.abs(mx - ds.startMx) >= 3 or math.abs(my - ds.startMy) >= 3 then
                ds.mode = "marquee"
                shell.previewOverlay:repaint()
            end
            return
        end

        if ds.mode == "marquee" then
            ds.currentMx = mx
            ds.currentMy = my
            shell.previewOverlay:repaint()
            return
        end

        if shell.selectedWidget == nil then
            return
        end

        local designX, designY = shell:previewToDesign(mx, my)
        local ddx = designX - ds.startDesignX
        local ddy = designY - ds.startDesignY

        if ds.mode == "move" then
            if type(ds.targets) == "table" then
                for i = 1, #ds.targets do
                    local t = ds.targets[i]
                    if t.canvas ~= nil then
                        local nx = math.floor(t.x + ddx + 0.5)
                        local ny = math.floor(t.y + ddy + 0.5)
                        t.lastX = nx
                        t.lastY = ny
                        t.lastW = t.w
                        t.lastH = t.h
                        t.canvas:setBounds(nx, ny, t.w, t.h)
                    end
                end
            end
            shell:updateSelectedRowBoundsCache()
            shell:_syncInspectorEditors()
            shell.previewOverlay:repaint()
            return
        end

        if ds.mode == "resize" then
            local left = ds.groupX
            local right = ds.groupX + ds.groupW
            local top = ds.groupY
            local bottom = ds.groupY + ds.groupH

            if ds.handle == "nw" or ds.handle == "w" or ds.handle == "sw" then
                left = ds.groupX + ddx
            end
            if ds.handle == "ne" or ds.handle == "e" or ds.handle == "se" then
                right = ds.groupX + ds.groupW + ddx
            end
            if ds.handle == "nw" or ds.handle == "n" or ds.handle == "ne" then
                top = ds.groupY + ddy
            end
            if ds.handle == "sw" or ds.handle == "s" or ds.handle == "se" then
                bottom = ds.groupY + ds.groupH + ddy
            end

            local w = right - left
            local h = bottom - top

            if w < shell.minWidgetSize then
                if ds.handle == "nw" or ds.handle == "w" or ds.handle == "sw" then
                    left = right - shell.minWidgetSize
                else
                    right = left + shell.minWidgetSize
                end
                w = shell.minWidgetSize
            end

            if h < shell.minWidgetSize then
                if ds.handle == "nw" or ds.handle == "n" or ds.handle == "ne" then
                    top = bottom - shell.minWidgetSize
                else
                    bottom = top + shell.minWidgetSize
                end
                h = shell.minWidgetSize
            end

            local scaleX = w / math.max(1, ds.groupW)
            local scaleY = h / math.max(1, ds.groupH)

            if type(ds.targets) == "table" then
                for i = 1, #ds.targets do
                    local t = ds.targets[i]
                    if t.canvas ~= nil then
                        local relX = t.rowX - ds.groupX
                        local relY = t.rowY - ds.groupY
                        local nx = left + relX * scaleX
                        local ny = top + relY * scaleY
                        local localNX = nx - (t.parentDesignX or 0)
                        local localNY = ny - (t.parentDesignY or 0)
                        local nw = math.max(shell.minWidgetSize, t.w * scaleX)
                        local nh = math.max(shell.minWidgetSize, t.h * scaleY)
                        t.lastX = math.floor(localNX + 0.5)
                        t.lastY = math.floor(localNY + 0.5)
                        t.lastW = math.floor(nw + 0.5)
                        t.lastH = math.floor(nh + 0.5)
                        t.canvas:setBounds(t.lastX, t.lastY, t.lastW, t.lastH)
                    end
                end
            end

            shell:updateSelectedRowBoundsCache()
            shell:_syncInspectorEditors()
            shell.previewOverlay:repaint()
        end
    end)

    shell.previewOverlay:setOnMouseUp(function(mx, my, shift, ctrl, alt)
        if shell.mode ~= "edit" or shell.dragState == nil then
            return
        end

        if type(_G) == "table" then
            local dbg = _G.__manifoldPreviewDragDebug or {}
            dbg.up = (dbg.up or 0) + 1
            dbg.lastUp = { mx = mx, my = my, shift = shift, ctrl = ctrl, alt = alt, mode = shell.dragState and shell.dragState.mode or "" }
            _G.__manifoldPreviewDragDebug = dbg
        end

        local ds = shell.dragState
        shell.dragState = nil
        local runtime = (type(_G) == "table") and _G.__manifoldStructuredUiRuntime or nil

        if ds.mode == "marqueePending" then
            if ds.pendingHit ~= nil then
                shell:toggleCanvasSelection(ds.pendingHit)
            end
            shell.previewOverlay:repaint()
            return
        end

        if ds.mode == "marquee" then
            local x1 = math.min(ds.startMx, ds.currentMx or ds.startMx)
            local y1 = math.min(ds.startMy, ds.currentMy or ds.startMy)
            local x2 = math.max(ds.startMx, ds.currentMx or ds.startMx)
            local y2 = math.max(ds.startMy, ds.currentMy or ds.startMy)

            if math.abs(x2 - x1) < 3 and math.abs(y2 - y1) < 3 then
                local dx, dy = shell:previewToDesign(mx, my)
                local hit = shell:hitTestWidget(dx, dy)
                if hit ~= nil then
                    shell:setSelection({ hit }, hit)
                else
                    shell:selectWidget(nil)
                end
            else
                local d1x, d1y = shell:previewToDesign(x1, y1)
                local d2x, d2y = shell:previewToDesign(x2, y2)
                local rx = math.min(d1x, d2x)
                local ry = math.min(d1y, d2y)
                local rw = math.abs(d2x - d1x)
                local rh = math.abs(d2y - d1y)

                local hits = {}
                local primary = nil
                for i = 1, #shell.treeRows do
                    local row = shell.treeRows[i]
                    if row.depth > 0 and rectContainsRect(rx, ry, rw, rh, row.x, row.y, row.w, row.h) then
                        hits[#hits + 1] = row.canvas
                        primary = row.canvas
                    end
                end

                if #hits > 0 then
                    shell:setSelection(hits, primary)
                else
                    shell:selectWidget(nil)
                end
            end
            shell.previewOverlay:repaint()
            return
        end

        if ds.mode == "move" or ds.mode == "resize" then
            if type(runtime) == "table" then
                runtime.suspendLayoutPass = false
            end
            if type(ds.targets) == "table" then
                for i = 1, #ds.targets do
                    local t = ds.targets[i]
                    if t.canvas ~= nil then
                        if t.lastX ~= nil and t.lastY ~= nil and t.lastW ~= nil and t.lastH ~= nil then
                            t.canvas:setBounds(t.lastX, t.lastY, t.lastW, t.lastH)
                        end
                        shell:persistStructuredBoundsForCanvas(t.canvas)
                    end
                end
            end
            shell:updateSelectedRowBoundsCache()
            shell:_syncInspectorEditors()
            shell:_rebuildInspectorRows()
            shell:refreshProjectScriptRowsIfNeeded()
            local afterScene = shell:_captureSceneState()
            local afterSelection = shell:_captureSelectionState()
            shell:recordHistory(ds.mode, ds.historyBeforeScene, ds.historyBeforeSelection, afterScene, afterSelection)
            return
        end

        if type(runtime) == "table" then
            runtime.suspendLayoutPass = false
        end

        shell.previewOverlay:repaint()
    end)


end

return M

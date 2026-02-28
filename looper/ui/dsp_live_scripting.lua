-- dsp_live_scripting.lua
-- Live DSP scripting test UI:
-- - Left: preset selector + editable script text area
-- - Right top: graph diagram from script
-- - Right bottom: dynamic parameter controls generated from script
-- VERSION: 2025-03-03-fixed-layout

local W = require("looper_widgets")

local ui = {}
local root = nil
local EDITOR_FONT_NAME = "Monospace"
local EDITOR_FONT_SIZE = 12.0
local EDITOR_CHAR_W = 7.4
local EDITOR_LINE_H = 16
local EDITOR_GUTTER_W = 44
local EDITOR_PAD = 8
local EDITOR_STATUS_H = 20
local PARAM_HEADER_H = 98
local PARAM_SCROLLBAR_W = 12
local PARAM_SCROLLBAR_GAP = 4
local PARAM_SCROLL_STEP = 28
local LIVE_SLOT = "live_editor"

local LUA_KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["goto"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local LUA_BUILTINS = {
    ["buildPlugin"] = true,
    ["ctx"] = true,
    ["math"] = true,
    ["string"] = true,
    ["table"] = true,
}

local SYNTAX_COLOUR = {
    text = 0xffe2e8f0,
    keyword = 0xfff59e0b,
    builtin = 0xff67e8f9,
    number = 0xffc4b5fd,
    string = 0xff86efac,
    comment = 0xff34d399,
    operator = 0xfff9a8d4,
    lineNumber = 0xff64748b,
}

local state = {
    selectedPreset = 1,
    status = "idle",
    lastError = "none",
    scriptText = "",
    cursorPos = 1,
    selectionAnchor = nil,
    dragAnchorPos = nil,
    clickStreak = 0,
    lastClickTime = 0.0,
    lastClickLine = -1,
    internalClipboard = "",
    scrollRow = 1,
    editorFocused = false,
    graphNodeCount = 0,
    graphRouteCount = 0,
    graphInputRms = 0.0,
    graphWetRms = 0.0,
    graphMixedRms = 0.0,
    graphModel = { nodes = {}, edges = {} },
    paramDefs = {},
    paramControls = {},
    paramScroll = 0,
    paramContentHeight = 0,
    lastW = -1,
    lastH = -1,
}

-- Load presets dynamically from DSP scripts folders
local presets = {}

local function loadPresets()
    presets = {}
    
    -- Load from listDspScripts if available
    if listDspScripts then
        local scripts = listDspScripts()
        for i, script in ipairs(scripts) do
            table.insert(presets, {
                name = script.name,
                code = script.code,
                path = script.path
            })
        end
    end
    
    -- Fallback: if no scripts found, add a basic default
    if #presets == 0 then
        table.insert(presets, {
            name = "Default (no scripts found)",
            code = [[
function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2)
  ctx.params.register("/dsp/input/gain", { type="f", min=0, max=2, default=1.0 })
  ctx.params.bind("/dsp/input/gain", input, "setGain")
  return {}
end
]],
            path = ""
        })
    end
end

-- Load presets at startup
loadPresets()

local parseGraph

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function parseNumber(s, fallback)
    local n = tonumber(s)
    if n == nil then return fallback end
    return n
end

local function textHash32(text)
    local h = 2166136261
    for i = 1, #text do
        h = (h ~ string.byte(text, i)) & 0xffffffff
        h = (h * 16777619) & 0xffffffff
    end
    return h
end

local function splitLines(text)
    local lines = {}
    local starts = {}
    local i = 1
    local n = #text
    while i <= n do
        starts[#starts + 1] = i
        local j = string.find(text, "\n", i, true)
        if j == nil then
            lines[#lines + 1] = string.sub(text, i)
            i = n + 1
        else
            lines[#lines + 1] = string.sub(text, i, j - 1)
            i = j + 1
        end
    end
    if #lines == 0 then
        lines[1] = ""
        starts[1] = 1
    end
    return lines, starts
end

local function lineColFromPos(text, pos)
    local lines, starts = splitLines(text)
    for i = 1, #lines do
        local startPos = starts[i]
        local endPos = startPos + #lines[i]
        if pos >= startPos and pos <= endPos + 1 then
            return i, pos - startPos + 1
        end
    end
    return #lines, #lines[#lines] + 1
end

local function getEditorVisibleLineCount(h)
    local contentH = math.max(EDITOR_LINE_H, h - (EDITOR_PAD * 2) - EDITOR_STATUS_H)
    return math.max(1, math.floor(contentH / EDITOR_LINE_H))
end

local function getEditorMaxCols(w)
    local textX = EDITOR_GUTTER_W + EDITOR_PAD + 4
    return math.max(1, math.floor((w - textX - EDITOR_PAD) / EDITOR_CHAR_W))
end

local function buildWrappedRows(text, maxCols)
    local lines, starts = splitLines(text)
    local rows = {}

    local function isWrapBoundaryChar(ch)
        if ch == nil or ch == "" then
            return false
        end
        if ch == " " or ch == "\t" then
            return true
        end
        return string.match(ch, "[%(%)%[%]%{%},%.;:%+%-%*/=<>!%?&|%^%%]") ~= nil
    end

    for lineIdx = 1, #lines do
        local line = lines[lineIdx]
        local lineLen = #line
        local startPos = starts[lineIdx]

        if lineLen == 0 then
            rows[#rows + 1] = {
                lineIdx = lineIdx,
                lineText = line,
                segStartCol = 1,
                segEndColExclusive = 1,
                rowStartPos = startPos,
                rowEndPosExclusive = startPos,
                text = "",
            }
        else
            local segStartCol = 1
            while segStartCol <= lineLen do
                local segEndCol

                if (lineLen - segStartCol + 1) <= maxCols then
                    segEndCol = lineLen
                else
                    local hardEnd = segStartCol + maxCols - 1
                    local softEnd = nil
                    local minSoftCol = segStartCol + math.floor(maxCols * 0.35)

                    for col = hardEnd, segStartCol + 1, -1 do
                        local ch = string.sub(line, col, col)
                        if isWrapBoundaryChar(ch) then
                            softEnd = col
                            break
                        end
                    end

                    if softEnd ~= nil and softEnd >= minSoftCol then
                        segEndCol = softEnd
                    else
                        segEndCol = hardEnd
                    end
                end

                local segEndColExclusive = segEndCol + 1
                rows[#rows + 1] = {
                    lineIdx = lineIdx,
                    lineText = line,
                    segStartCol = segStartCol,
                    segEndColExclusive = segEndColExclusive,
                    rowStartPos = startPos + segStartCol - 1,
                    rowEndPosExclusive = startPos + segEndColExclusive - 1,
                    text = string.sub(line, segStartCol, segEndCol),
                }
                segStartCol = segEndCol + 1
            end
        end
    end

    if #rows == 0 then
        rows[1] = {
            lineIdx = 1,
            lineText = "",
            segStartCol = 1,
            segEndColExclusive = 1,
            rowStartPos = 1,
            rowEndPosExclusive = 1,
            text = "",
        }
    end

    return rows, lines, starts
end

local function findWrappedRowForPos(rows, pos)
    local p = clamp(pos, 1, #state.scriptText + 1)
    for i = 1, #rows do
        local row = rows[i]
        if p >= row.rowStartPos and p <= row.rowEndPosExclusive then
            return i
        end
    end
    return #rows
end

local function ensureCursorVisible()
    if not ui.editor then
        return
    end

    local maxCols = getEditorMaxCols(math.floor(ui.editor:getWidth()))
    local rows, lines = buildWrappedRows(state.scriptText, maxCols)
    local row = findWrappedRowForPos(rows, state.cursorPos)
    local h = math.floor(ui.editor:getHeight())
    local visible = getEditorVisibleLineCount(h)
    local maxScroll = math.max(1, #rows - visible + 1)

    if row < state.scrollRow then
        state.scrollRow = row
    elseif row >= state.scrollRow + visible then
        state.scrollRow = row - visible + 1
    end

    state.scrollRow = clamp(state.scrollRow, 1, maxScroll)
end

local function posFromLineCol(text, targetLine, targetCol)
    local lines, starts = splitLines(text)
    targetLine = clamp(targetLine, 1, #lines)
    local line = lines[targetLine]
    targetCol = clamp(targetCol, 1, #line + 1)
    return starts[targetLine] + targetCol - 1
end

local function isLetterShortcut(keyCode, charCode, letter)
    local upper = string.byte(string.upper(letter))
    local lower = string.byte(string.lower(letter))
    return keyCode == upper or keyCode == lower or charCode == upper or charCode == lower
end

local function getSelectionRange()
    if state.selectionAnchor == nil then
        return nil
    end
    local a = clamp(state.selectionAnchor, 1, #state.scriptText + 1)
    local b = clamp(state.cursorPos, 1, #state.scriptText + 1)
    if a == b then
        return nil
    end
    if a < b then
        return a, b
    end
    return b, a
end

local function hasSelection()
    return getSelectionRange() ~= nil
end

local function clearSelection()
    state.selectionAnchor = nil
end

local function getSelectedText()
    local a, b = getSelectionRange()
    if a == nil then
        return ""
    end
    return string.sub(state.scriptText, a, b - 1)
end

local function deleteSelection()
    local a, b = getSelectionRange()
    if a == nil then
        return false
    end
    local before = string.sub(state.scriptText, 1, a - 1)
    local after = string.sub(state.scriptText, b)
    state.scriptText = before .. after
    state.cursorPos = a
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
    return true
end

local function replaceSelection(text)
    deleteSelection()
    local before = string.sub(state.scriptText, 1, state.cursorPos - 1)
    local after = string.sub(state.scriptText, state.cursorPos)
    state.scriptText = before .. text .. after
    state.cursorPos = state.cursorPos + #text
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
end

local function moveCursor(newPos, keepSelection)
    local oldPos = state.cursorPos
    state.cursorPos = clamp(newPos, 1, #state.scriptText + 1)
    if keepSelection then
        if state.selectionAnchor == nil then
            state.selectionAnchor = oldPos
        end
        if state.selectionAnchor == state.cursorPos then
            clearSelection()
        end
    else
        clearSelection()
    end
end

local function setClipboardTextSafe(text)
    state.internalClipboard = text or ""
    if type(setClipboardText) == "function" then
        return setClipboardText(state.internalClipboard)
    end
    return true
end

local function getClipboardTextSafe()
    if type(getClipboardText) == "function" then
        local text = getClipboardText()
        if type(text) == "string" then
            state.internalClipboard = text
            return text
        end
    end
    return state.internalClipboard or ""
end

local function copySelectionToClipboard()
    local selected = getSelectedText()
    if selected == "" then
        return false
    end
    return setClipboardTextSafe(selected)
end

local function cutSelectionToClipboard()
    local selected = getSelectedText()
    if selected == "" then
        return false
    end
    setClipboardTextSafe(selected)
    deleteSelection()
    return true
end

local function pasteClipboardAtCursor()
    local clip = getClipboardTextSafe()
    if clip == "" then
        return false
    end
    replaceSelection(clip)
    return true
end

local function cursorPosFromEditorPoint(mx, my)
    if not ui.editor then
        return state.cursorPos
    end

    local maxCols = getEditorMaxCols(math.floor(ui.editor:getWidth()))
    local rows, lines = buildWrappedRows(state.scriptText, maxCols)
    local rowIdx = state.scrollRow + math.floor((my - EDITOR_PAD) / EDITOR_LINE_H)
    rowIdx = clamp(rowIdx, 1, #rows)
    local row = rows[rowIdx]

    local relativeX = math.max(0, mx - (EDITOR_GUTTER_W + EDITOR_PAD + 4))
    local colInRow = 1 + math.floor((relativeX / EDITOR_CHAR_W) + 0.5)
    local targetCol = clamp(
        row.segStartCol + colInRow - 1,
        row.segStartCol,
        row.segEndColExclusive
    )

    return posFromLineCol(state.scriptText, row.lineIdx, targetCol)
end

local function isWordChar(ch)
    if ch == nil or ch == "" then
        return false
    end
    return ch == "_" or string.match(ch, "[%w]") ~= nil
end

local function selectWordAtPos(pos)
    local text = state.scriptText
    local n = #text
    if n <= 0 then
        clearSelection()
        return
    end

    local p = clamp(pos, 1, n)
    local ch = string.sub(text, p, p)
    if not isWordChar(ch) and p > 1 then
        local leftCh = string.sub(text, p - 1, p - 1)
        if isWordChar(leftCh) then
            p = p - 1
            ch = leftCh
        end
    end

    if isWordChar(ch) then
        local s = p
        while s > 1 and isWordChar(string.sub(text, s - 1, s - 1)) do
            s = s - 1
        end
        local e = p + 1
        while e <= n and isWordChar(string.sub(text, e, e)) do
            e = e + 1
        end
        state.selectionAnchor = s
        state.cursorPos = e
        return
    end

    state.selectionAnchor = p
    state.cursorPos = p + 1
end

local function selectLineAtPos(pos)
    local line, _ = lineColFromPos(state.scriptText, clamp(pos, 1, #state.scriptText + 1))
    local lines, starts = splitLines(state.scriptText)
    line = clamp(line, 1, #lines)
    local startPos = starts[line]
    local nextStart = starts[line + 1]
    local endPosExclusive = nextStart or (#state.scriptText + 1)
    state.selectionAnchor = startPos
    state.cursorPos = endPosExclusive
end

local function pushSpan(spans, text, colour)
    if text == nil or text == "" then
        return
    end
    spans[#spans + 1] = {
        text = text,
        colour = colour,
    }
end

local function tokenizeLuaLine(line)
    local spans = {}
    local i = 1
    local n = #line

    while i <= n do
        local ch = string.sub(line, i, i)
        local nextTwo = string.sub(line, i, i + 1)

        if nextTwo == "--" then
            pushSpan(spans, string.sub(line, i), SYNTAX_COLOUR.comment)
            break
        end

        if ch == "\"" or ch == "'" then
            local quote = ch
            local j = i + 1
            local escaped = false
            while j <= n do
                local cj = string.sub(line, j, j)
                if escaped then
                    escaped = false
                elseif cj == "\\" then
                    escaped = true
                elseif cj == quote then
                    j = j + 1
                    break
                end
                j = j + 1
            end
            pushSpan(spans, string.sub(line, i, j - 1), SYNTAX_COLOUR.string)
            i = j
        elseif string.match(ch, "[%a_]") then
            local j = i + 1
            while j <= n and string.match(string.sub(line, j, j), "[%w_]") do
                j = j + 1
            end
            local ident = string.sub(line, i, j - 1)
            local colour = SYNTAX_COLOUR.text
            if LUA_KEYWORDS[ident] then
                colour = SYNTAX_COLOUR.keyword
            elseif LUA_BUILTINS[ident] then
                colour = SYNTAX_COLOUR.builtin
            end
            pushSpan(spans, ident, colour)
            i = j
        elseif string.match(ch, "[%d]") then
            local j = i + 1
            while j <= n and string.match(string.sub(line, j, j), "[%d_]") do
                j = j + 1
            end
            if string.sub(line, j, j) == "." and string.match(string.sub(line, j + 1, j + 1), "[%d]") then
                j = j + 1
                while j <= n and string.match(string.sub(line, j, j), "[%d_]") do
                    j = j + 1
                end
            end
            local expCh = string.sub(line, j, j)
            if expCh == "e" or expCh == "E" then
                local k = j + 1
                local sign = string.sub(line, k, k)
                if sign == "+" or sign == "-" then
                    k = k + 1
                end
                local hasExpDigits = false
                while k <= n and string.match(string.sub(line, k, k), "[%d]") do
                    hasExpDigits = true
                    k = k + 1
                end
                if hasExpDigits then
                    j = k
                end
            end
            pushSpan(spans, string.sub(line, i, j - 1), SYNTAX_COLOUR.number)
            i = j
        elseif ch == " " or ch == "\t" then
            local j = i + 1
            while j <= n do
                local cj = string.sub(line, j, j)
                if cj ~= " " and cj ~= "\t" then
                    break
                end
                j = j + 1
            end
            pushSpan(spans, string.sub(line, i, j - 1), SYNTAX_COLOUR.text)
            i = j
        else
            local j = i
            while j <= n do
                local cj = string.sub(line, j, j)
                local c2 = string.sub(line, j, j + 1)
                if c2 == "--" or cj == " " or cj == "\t" or cj == "\"" or cj == "'" or string.match(cj, "[%w_]") then
                    break
                end
                j = j + 1
            end
            if j == i then
                j = i + 1
            end
            pushSpan(spans, string.sub(line, i, j - 1), SYNTAX_COLOUR.operator)
            i = j
        end
    end

    return spans
end

local function findLineCommentStartCol(line)
    local i = 1
    local n = #line
    local quote = nil
    local escaped = false

    while i <= n do
        local ch = string.sub(line, i, i)
        local nextTwo = string.sub(line, i, i + 1)

        if quote ~= nil then
            if escaped then
                escaped = false
            elseif ch == "\\" then
                escaped = true
            elseif ch == quote then
                quote = nil
            end
            i = i + 1
        else
            if nextTwo == "--" then
                return i
            elseif ch == "\"" or ch == "'" then
                quote = ch
                i = i + 1
            else
                i = i + 1
            end
        end
    end

    return nil
end

parseGraph = function(code)
    local nodes = {}
    local edges = {}
    local varToIndex = {}

    for varName, primType in code:gmatch("local%s+([%w_]+)%s*=%s*ctx%.primitives%.([%w_]+)%.new") do
        if varToIndex[varName] == nil then
            local idx = #nodes + 1
            varToIndex[varName] = idx
            nodes[idx] = { var = varName, prim = primType }
        end
    end

    for fromVar, toVar in code:gmatch("ctx%.graph%.connect%s*%(%s*([%w_]+)%s*,%s*([%w_]+)") do
        local fromIdx = varToIndex[fromVar]
        local toIdx = varToIndex[toVar]
        if fromIdx ~= nil and toIdx ~= nil then
            edges[#edges + 1] = { from = fromIdx, to = toIdx }
        end
    end

    return { nodes = nodes, edges = edges }
end

local function parseParamDefs(code)
    local defs = {}
    local stripped = {}
    for line in code:gmatch("([^\n]*)\n?") do
        if not line:match("^%s*%-%-") then
            stripped[#stripped + 1] = line
        end
    end
    local parseText = table.concat(stripped, "\n")

    for path, body in parseText:gmatch('ctx%.params%.register%s*%(%s*"([^"]+)"%s*,%s*%{(.-)%}%s*%)') do
        local minV = parseNumber(body:match("min%s*=%s*([%-%d%.]+)"), 0.0)
        local maxV = parseNumber(body:match("max%s*=%s*([%-%d%.]+)"), 1.0)
        local defV = parseNumber(body:match("default%s*=%s*([%-%d%.]+)"), minV)
        defs[#defs + 1] = {
            path = path,
            min = minV,
            max = maxV,
            default = clamp(defV, minV, maxV),
        }
    end
    table.sort(defs, function(a, b) return a.path < b.path end)
    return defs
end

local function endpointAvailable(path)
    if type(hasEndpoint) == "function" then
        return hasEndpoint(path)
    end
    return true
end

local function setLiveSlotPersistOnSwitch(persist)
    if type(setDspSlotPersistOnUiSwitch) == "function" then
        pcall(setDspSlotPersistOnUiSwitch, LIVE_SLOT, persist and true or false)
    end
end

local function setStatus(text)
    state.status = text or ""
    local err = getDspScriptLastError() or ""
    state.lastError = (err ~= "") and err or "none"
    if ui.status then
        ui.status:setText("Status: " .. state.status)
    end
    if ui.error then
        ui.error:setText("Error: " .. state.lastError)
    end
end

local function refreshMetrics()
    state.graphInputRms = getParam("/looper/debug/graphInputRms") or 0.0
    state.graphWetRms = getParam("/looper/debug/graphWetRms") or 0.0
    state.graphMixedRms = getParam("/looper/debug/graphMixedRms") or 0.0
    state.graphNodeCount = math.floor((getParam("/looper/debug/graphNodeCount") or 0.0) + 0.5)
    state.graphRouteCount = math.floor((getParam("/looper/debug/graphRouteCount") or 0.0) + 0.5)

    if ui.graphMetrics then
        ui.graphMetrics:setText(string.format(
            "runtime nodes=%d routes=%d | RMS in=%.4f wet=%.4f mix=%.4f",
            state.graphNodeCount, state.graphRouteCount,
            state.graphInputRms, state.graphWetRms, state.graphMixedRms))
    end
end

local function refreshParamControlState()
    local missing = {}
    for i = 1, #state.paramControls do
        local c = state.paramControls[i]
        local active = endpointAvailable(c.path)
        c.widget:setEnabled(active)
        c.widget._label = active and c.path or (c.path .. " (inactive)")
        if active then
            local v = getParam(c.path)
            if v ~= nil then
                c.widget:setValue(v)
            end
        else
            missing[#missing + 1] = c.path
        end
    end

    if ui.paramState then
        if #missing == 0 then
            ui.paramState:setText("Params: all active")
        else
            ui.paramState:setText("Params inactive: " .. table.concat(missing, ", "))
        end
    end
end

local function setParamSafe(path, value)
    if not endpointAvailable(path) then
        setStatus("param inactive in current runtime: " .. path)
        return
    end
    if not setParam(path, value) then
        setStatus("setParam failed: " .. path)
    end
end

local function getParamContentHeight()
    if #state.paramControls <= 0 then
        return 0
    end
    -- top padding + rows + bottom padding
    return 8 + (#state.paramControls - 1) * 36 + 30 + 8
end

local function getParamViewHeight()
    if not ui.paramsBody then
        return 0
    end
    return math.max(0, math.floor(ui.paramsBody:getHeight()))
end

local function getParamMaxScroll()
    return math.max(0, state.paramContentHeight - getParamViewHeight())
end

local function clampParamScroll()
    state.paramScroll = clamp(state.paramScroll, 0, getParamMaxScroll())
end

local function rebuildParamControls()
    if not ui.paramsBody then
        return
    end

    ui.paramsBody:clearChildren()
    state.paramControls = {}
    state.paramScroll = 0
    state.paramDefs = parseParamDefs(state.scriptText)

    if #state.paramDefs == 0 then
        state.paramContentHeight = 0
        local emptyLabel = W.Label.new(ui.paramsBody, "empty", {
            text = "No ctx.params.register(...) found in script",
            colour = 0xff94a3b8,
            fontSize = 12.0,
            justification = Justify.centredLeft,
        })
        emptyLabel:setBounds(8, 8, math.max(0, ui.paramsBody:getWidth() - 16), 22)
        return
    end

    for i = 1, #state.paramDefs do
        local d = state.paramDefs[i]
        local slider = W.Slider.new(ui.paramsBody, "p" .. tostring(i), {
            label = d.path,
            min = d.min,
            max = d.max,
            value = d.default,
            step = (d.max - d.min) > 2 and 1 or 0.01,
            on_change = function(v)
                setParamSafe(d.path, v)
            end,
        })
        state.paramControls[#state.paramControls + 1] = {
            path = d.path,
            widget = slider,
        }
    end

    state.paramContentHeight = getParamContentHeight()
    clampParamScroll()
end

local function relayoutParams()
    if not ui.paramsBody then
        return
    end

    state.paramContentHeight = getParamContentHeight()
    clampParamScroll()

    local w = math.floor(ui.paramsBody:getWidth())
    local y = 8 - math.floor(state.paramScroll + 0.5)
    for i = 1, #state.paramControls do
        state.paramControls[i].widget:setBounds(8, y, math.max(0, w - 16), 30)
        y = y + 36
    end

    local maxScroll = getParamMaxScroll()
    if ui.paramScrollInfo then
        if maxScroll > 0 then
            ui.paramScrollInfo:setText(string.format(
                "Scroll: %d/%d (wheel or drag bar)",
                math.floor(state.paramScroll + 0.5),
                math.floor(maxScroll + 0.5)
            ))
        else
            ui.paramScrollInfo:setText("Scroll: none")
        end
    end

    if ui.paramScrollSlider then
        if maxScroll > 0 then
            ui.paramScrollSlider:setEnabled(true)
            ui.paramScrollSlider:setValue(1.0 - (state.paramScroll / maxScroll))
        else
            ui.paramScrollSlider:setEnabled(false)
            ui.paramScrollSlider:setValue(1.0)
        end
    end
end

local function handleParamScrollWheel(dy)
    if getParamMaxScroll() <= 0 then
        return
    end
    if dy > 0 then
        state.paramScroll = state.paramScroll - PARAM_SCROLL_STEP
    elseif dy < 0 then
        state.paramScroll = state.paramScroll + PARAM_SCROLL_STEP
    end
    clampParamScroll()
    relayoutParams()
end

local function applyPresetToEditor(idx)
    local preset = presets[idx]
    if not preset then
        return
    end
    state.scriptText = preset.code
    state.cursorPos = #state.scriptText + 1
    clearSelection()
    state.scrollRow = 1
    state.graphModel = parseGraph(state.scriptText)
    ensureCursorVisible()
    rebuildParamControls()
    relayoutParams()
    if ui.editor then
        ui.editor:repaint()
    end
    if ui.graphCanvas then
        ui.graphCanvas:repaint()
    end
    setStatus("loaded preset text: " .. preset.name)
end

local function runEditorScript()
    local dumpPath = "/tmp/dsp_live_last_run.lua"
    if type(writeTextFile) == "function" then
        writeTextFile(dumpPath, state.scriptText)
    end

    local sourceName = string.format(
        "ui:dsp_live:editor:len%d:h%08x",
        #state.scriptText,
        textHash32(state.scriptText)
    )

    -- Live editor input/effect routes are transient by default: they should
    -- not bleed into other UIs unless a script explicitly opts in.
    setLiveSlotPersistOnSwitch(false)

    local ok = false
    if type(loadDspScriptFromStringInSlot) == "function" then
        ok = loadDspScriptFromStringInSlot(state.scriptText, sourceName, LIVE_SLOT)
    else
        ok = loadDspScriptFromString(state.scriptText, sourceName)
    end
    if not ok then
        local err = ""
        if type(getDspScriptLastError) == "function" then
            local eok, eval = pcall(getDspScriptLastError)
            if eok and type(eval) == "string" then
                err = eval
            end
        end
        if #err > 0 then
            setStatus("load failed: " .. err)
        else
            setStatus("load failed")
        end
        return
    end

    -- Graph is always enabled in persistent graph architecture.
    state.graphModel = parseGraph(state.scriptText)
    rebuildParamControls()
    relayoutParams()
    refreshParamControlState()

    setStatus("script loaded in slot '" .. LIVE_SLOT .. "' (" .. sourceName .. ") -> " .. dumpPath)
end

local function stopEditorScript()
    -- Unload the live editor slot to remove its nodes from the graph.
    -- The default looper slot's nodes are untouched.
    setLiveSlotPersistOnSwitch(false)
    if type(unloadDspSlot) == "function" then
        unloadDspSlot(LIVE_SLOT)
        setStatus("live editor slot unloaded")
    else
        setStatus("unloadDspSlot not available")
    end
end

local function insertTextAtCursor(textToInsert)
    replaceSelection(textToInsert)
end

local function backspaceAtCursor()
    if deleteSelection() then
        return
    end
    if state.cursorPos <= 1 then
        return
    end
    local before = string.sub(state.scriptText, 1, state.cursorPos - 2)
    local after = string.sub(state.scriptText, state.cursorPos)
    state.scriptText = before .. after
    state.cursorPos = state.cursorPos - 1
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
end

local function deleteAtCursor()
    if deleteSelection() then
        return
    end
    if state.cursorPos > #state.scriptText then
        return
    end
    local before = string.sub(state.scriptText, 1, state.cursorPos - 1)
    local after = string.sub(state.scriptText, state.cursorPos + 1)
    state.scriptText = before .. after
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
end

local function editorMoveVertical(dir, keepSelection)
    if not ui.editor then
        local line, col = lineColFromPos(state.scriptText, state.cursorPos)
        moveCursor(posFromLineCol(state.scriptText, line + dir, col), keepSelection)
        return
    end

    local maxCols = getEditorMaxCols(math.floor(ui.editor:getWidth()))
    local rows = buildWrappedRows(state.scriptText, maxCols)
    local rowIdx = findWrappedRowForPos(rows, state.cursorPos)
    local row = rows[rowIdx]
    local colInRow = state.cursorPos - row.rowStartPos + 1

    local targetRowIdx = clamp(rowIdx + dir, 1, #rows)
    local targetRow = rows[targetRowIdx]
    local targetPos = clamp(
        targetRow.rowStartPos + colInRow - 1,
        targetRow.rowStartPos,
        targetRow.rowEndPosExclusive
    )
    moveCursor(targetPos, keepSelection)
end

local function getCurrentLineInfo()
    local lines, starts = splitLines(state.scriptText)
    local line, col = lineColFromPos(state.scriptText, state.cursorPos)
    line = clamp(line, 1, #lines)
    local startPos = starts[line]
    local nextStart = starts[line + 1]
    local endPosExclusive = nextStart or (#state.scriptText + 1)
    return {
        line = line,
        col = col,
        text = lines[line] or "",
        startPos = startPos,
        endPosExclusive = endPosExclusive,
    }
end

local function replaceCurrentLine(newLine)
    local info = getCurrentLineInfo()
    local before = string.sub(state.scriptText, 1, info.startPos - 1)
    local after = string.sub(state.scriptText, info.endPosExclusive)
    local hadNewline = (info.endPosExclusive <= #state.scriptText)
    state.scriptText = before .. newLine .. (hadNewline and "\n" or "") .. after
    state.cursorPos = clamp(info.startPos, 1, #state.scriptText + 1)
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
end

local function toggleCommentOnCurrentLine()
    local info = getCurrentLineInfo()
    local indent, body = info.text:match("^([ \t]*)(.*)$")
    if not indent then
        indent = ""
        body = info.text
    end

    if body:match("^%-%- ?") then
        local uncommented = body:gsub("^%-%- ?", "", 1)
        replaceCurrentLine(indent .. uncommented)
    else
        replaceCurrentLine(indent .. "-- " .. body)
    end
end

local function deleteCurrentLine()
    local info = getCurrentLineInfo()
    local text = state.scriptText
    local before = string.sub(text, 1, info.startPos - 1)
    local after = string.sub(text, info.endPosExclusive)

    -- If deleting the last line, also trim the preceding newline.
    if info.endPosExclusive > #text and info.startPos > 1 then
        if string.sub(text, info.startPos - 1, info.startPos - 1) == "\n" then
            before = string.sub(text, 1, info.startPos - 2)
        end
    end

    state.scriptText = before .. after
    state.cursorPos = clamp(info.startPos, 1, #state.scriptText + 1)
    clearSelection()
    state.graphModel = parseGraph(state.scriptText)
end

local function handleEditorKey(keyCode, charCode, shift, ctrl, alt)
    local _ = alt

    if ctrl and shift and (keyCode == 13 or charCode == 10 or charCode == 13) then
        stopEditorScript()
        return true
    end

    if ctrl and (keyCode == 13 or charCode == 10 or charCode == 13) then
        runEditorScript()
        return true
    end

    if ctrl and isLetterShortcut(keyCode, charCode, "a") then
        state.selectionAnchor = 1
        state.cursorPos = #state.scriptText + 1
        return true
    end

    if ctrl and isLetterShortcut(keyCode, charCode, "c") then
        if copySelectionToClipboard() then
            setStatus("selection copied")
        else
            setStatus("no selection to copy")
        end
        return true
    end

    if ctrl and isLetterShortcut(keyCode, charCode, "x") then
        if cutSelectionToClipboard() then
            setStatus("selection cut")
        else
            setStatus("no selection to cut")
        end
        return true
    end

    if ctrl and isLetterShortcut(keyCode, charCode, "v") then
        if pasteClipboardAtCursor() then
            setStatus("pasted")
        else
            setStatus("clipboard empty")
        end
        return true
    end

    local isSlash = (keyCode == 47 or charCode == 47)
    if ctrl and isSlash then
        toggleCommentOnCurrentLine()
        return true
    end

    local isD = (keyCode == 68 or keyCode == 100 or charCode == 68 or charCode == 100)
    if ctrl and isD then
        deleteCurrentLine()
        return true
    end

    local lowByte = keyCode % 256
    local isExtended = keyCode >= 0x10000000

    local isBackspace = (keyCode == 8)
    local isDelete = (keyCode == 127 or (isExtended and lowByte == 0xff))
    local isReturn = (keyCode == 13 or keyCode == 10)
    local isTab = (keyCode == 9)

    local isLeft = (keyCode == 63234 or keyCode == 28 or keyCode == 37 or (isExtended and lowByte == 0x51))
    local isRight = (keyCode == 63235 or keyCode == 29 or keyCode == 39 or (isExtended and lowByte == 0x53))
    local isUp = (keyCode == 63232 or keyCode == 30 or keyCode == 38 or (isExtended and lowByte == 0x52))
    local isDown = (keyCode == 63233 or keyCode == 31 or keyCode == 40 or (isExtended and lowByte == 0x54))

    if isBackspace then
        backspaceAtCursor()
        return true
    end
    if isDelete then
        deleteAtCursor()
        return true
    end
    if isReturn then
        insertTextAtCursor("\n")
        return true
    end
    if isTab then
        insertTextAtCursor("  ")
        return true
    end

    if isLeft then
        moveCursor(state.cursorPos - 1, shift)
        return true
    end
    if isRight then
        moveCursor(state.cursorPos + 1, shift)
        return true
    end
    if isUp then
        editorMoveVertical(-1, shift)
        return true
    end
    if isDown then
        editorMoveVertical(1, shift)
        return true
    end

    if charCode >= 32 and charCode <= 126 then
        insertTextAtCursor(string.char(charCode))
        return true
    end
    if keyCode >= 32 and keyCode <= 126 then
        insertTextAtCursor(string.char(keyCode))
        return true
    end

    return false
end

local function relayout()
    if not ui.rootPanel then
        return
    end

    local w = math.floor(root:getWidth())
    local h = math.floor(root:getHeight())
    local pad = 12
    local headerH = 34

    ui.rootPanel:setBounds(0, 0, w, h)

    local contentX, contentY, contentW, contentH = 0, 0, w, h

    local leftW = math.floor(contentW * 0.56)
    local leftX = contentX
    local rightX = leftX + leftW + pad
    local rightW = contentX + contentW - rightX
    local topY = contentY

    local controlsX = leftX + pad
    -- Back to 4 buttons in top row, Refresh moved to params panel
    local buttonW = 84
    local buttonGap = 6
    local buttonCount = 4
    local buttonsTotalW = buttonW * buttonCount + buttonGap * (buttonCount - 1)
    local buttonRowX = leftX + leftW - pad - buttonsTotalW

    ui.presetDropdown:setBounds(
        controlsX,
        topY,
        math.max(80, buttonRowX - controlsX - 8),
        headerH
    )
    ui.loadPresetButton:setBounds(buttonRowX, topY, buttonW, headerH)
    ui.runButton:setBounds(buttonRowX + (buttonW + buttonGap), topY, buttonW, headerH)
    ui.stopButton:setBounds(buttonRowX + (buttonW + buttonGap) * 2, topY, buttonW, headerH)
    ui.reloadButton:setBounds(buttonRowX + (buttonW + buttonGap) * 3, topY, buttonW, headerH)

    ui.editor:setBounds(leftX + pad, topY + headerH + 8, leftW - pad * 2, contentH - (headerH + 8))

    ui.graphTitle:setBounds(rightX, topY, rightW, 20)
    local graphY = topY + 24
    local rightAvailH = contentY + contentH - graphY
    local graphH = math.floor(rightAvailH * 0.46)
    ui.graphCanvas:setBounds(rightX, graphY, rightW, graphH)

    local paramsY = graphY + graphH + 8
    local paramsH = contentY + contentH - paramsY
    ui.paramsTitle:setBounds(rightX, paramsY, rightW - 100, 20)
    ui.refreshButton:setBounds(rightX + rightW - 95, paramsY, 90, 20)
    ui.paramsPanel:setBounds(rightX, paramsY + 22, rightW, paramsH - 22)

    local pw = math.floor(ui.paramsPanel.node:getWidth())
    local ph = math.floor(ui.paramsPanel.node:getHeight())
    ui.paramState:setBounds(8, 6, math.max(0, pw - 16), 18)
    ui.graphMetrics:setBounds(8, 24, math.max(0, pw - 16), 18)
    ui.status:setBounds(8, 42, math.max(0, pw - 16), 18)
    ui.error:setBounds(8, 60, math.max(0, pw - 16), 18)
    ui.paramScrollInfo:setBounds(8, 78, math.max(0, pw - 16), 16)
    local bodyH = math.max(0, ph - PARAM_HEADER_H)
    local hasOverflow = state.paramContentHeight > bodyH
    local bodyW = pw
    if hasOverflow then
        bodyW = math.max(0, pw - PARAM_SCROLLBAR_W - PARAM_SCROLLBAR_GAP)
        ui.paramScrollSlider:setBounds(bodyW + PARAM_SCROLLBAR_GAP, PARAM_HEADER_H, PARAM_SCROLLBAR_W, bodyH)
    else
        state.paramScroll = 0
        ui.paramScrollSlider:setBounds(0, 0, 0, 0)
    end
    ui.paramsBody:setBounds(0, PARAM_HEADER_H, bodyW, bodyH)

    relayoutParams()
end

local function drawEditor(node)
    local w = math.floor(node:getWidth())
    local h = math.floor(node:getHeight())
    local pad = EDITOR_PAD
    local lineH = EDITOR_LINE_H
    local numberW = EDITOR_GUTTER_W
    local statusH = EDITOR_STATUS_H
    local contentH = math.max(lineH, h - (pad * 2) - statusH)
    local textX = numberW + pad + 4

    gfx.setColour(0xff0b1220)
    gfx.fillRoundedRect(0, 0, w, h, 6)

    local border = state.editorFocused and 0xff38bdf8 or 0xff334155
    gfx.setColour(border)
    gfx.drawRoundedRect(0, 0, w, h, 6, 1)

    gfx.setColour(0xff101a2e)
    gfx.fillRoundedRect(1, 1, numberW + pad, h - statusH - 2, 5)
    gfx.setColour(0xff25354d)
    gfx.drawVerticalLine(numberW + pad, pad, h - statusH - pad)

    local maxCols = getEditorMaxCols(w)
    local rows = buildWrappedRows(state.scriptText, maxCols)
    local visible = getEditorVisibleLineCount(h)
    local maxScroll = math.max(1, #rows - visible + 1)
    state.scrollRow = clamp(state.scrollRow, 1, maxScroll)

    local y = pad
    local cursorLine, cursorCol = lineColFromPos(state.scriptText, state.cursorPos)
    local cursorRowIdx = findWrappedRowForPos(rows, state.cursorPos)
    local selStart, selEnd = getSelectionRange()

    for i = 0, visible - 1 do
        local rowIdx = state.scrollRow + i
        local row = rows[rowIdx]
        if row == nil then
            break
        end

        if rowIdx == cursorRowIdx then
            gfx.setColour(0x2040a8ff)
            gfx.fillRect(textX - 2, y, w - textX - pad + 2, lineH)
        end

        if selStart ~= nil and selEnd ~= nil then
            local overlapStart = math.max(selStart, row.rowStartPos)
            local overlapEnd = math.min(selEnd, row.rowEndPosExclusive)
            if overlapEnd > overlapStart then
                local selColStart = overlapStart - row.rowStartPos + 1
                local selColEnd = overlapEnd - row.rowStartPos + 1
                local sx = math.floor(textX + (selColStart - 1) * EDITOR_CHAR_W + 0.5)
                local sw = math.max(1, math.floor((selColEnd - selColStart) * EDITOR_CHAR_W + 0.5))
                gfx.setColour(0x705892f0)
                gfx.fillRect(sx, y, sw, lineH)
            end
        end

        gfx.setColour(SYNTAX_COLOUR.lineNumber)
        gfx.setFont(EDITOR_FONT_NAME, 11.0, FontStyle.plain)
        local gutterLabel = (row.segStartCol == 1) and tostring(row.lineIdx) or "·"
        gfx.drawText(gutterLabel, 4, y, numberW - 6, lineH, Justify.centredRight)

        local sourceLine = row.lineText or row.text or ""
        local commentStartCol = findLineCommentStartCol(sourceLine)
        local spans
        if commentStartCol ~= nil and row.segStartCol >= commentStartCol then
            spans = {
                {
                    text = row.text,
                    colour = SYNTAX_COLOUR.comment,
                }
            }
        else
            spans = tokenizeLuaLine(row.text)
        end
        local glyphCol = 1
        for j = 1, #spans do
            local span = spans[j]
            local spanChars = #span.text
            if spanChars > 0 then
                if not string.match(span.text, "^[ \t]+$") then
                    for k = 1, spanChars do
                        local ch = string.sub(span.text, k, k)
                        if ch ~= " " and ch ~= "\t" then
                            local visualCol = glyphCol + k - 1
                            local cx = math.floor(textX + (visualCol - 1) * EDITOR_CHAR_W + 0.5)
                            gfx.setColour(span.colour)
                            gfx.setFont(EDITOR_FONT_NAME, EDITOR_FONT_SIZE, FontStyle.plain)
                            gfx.drawText(ch, cx, y, math.floor(EDITOR_CHAR_W + 2), lineH, Justify.centredLeft)
                        end
                    end
                end
                glyphCol = glyphCol + spanChars
            end
        end

        y = y + lineH
    end

    if state.editorFocused then
        local blinkOn = (math.floor(getTime() * 2) % 2) == 0
        if blinkOn then
            if cursorRowIdx >= state.scrollRow and cursorRowIdx < state.scrollRow + visible then
                local row = rows[cursorRowIdx]
                local maxCaretCol = row.segEndColExclusive - row.segStartCol + 1
                local caretCol = clamp(state.cursorPos - row.rowStartPos + 1, 1, maxCaretCol)
                local cx = math.floor(textX + (caretCol - 1) * EDITOR_CHAR_W + 0.5)
                local cy = pad + (cursorRowIdx - state.scrollRow) * lineH
                gfx.setColour(0xff7dd3fc)
                gfx.drawLine(cx, cy + 2, cx, cy + lineH - 2)
            end
        end
    end

    gfx.setColour(0xff0f172a)
    gfx.fillRect(1, h - statusH - 1, w - 2, statusH)
    gfx.setColour(0xff22324b)
    gfx.drawHorizontalLine(h - statusH - 1, 1, w - 1)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(EDITOR_FONT_NAME, 10.0, FontStyle.plain)
    local statusText = string.format(
        "Ln %d, Col %d | Sel %d | Wrap ON | Ctrl+C/X/V | Dbl=word Triple=line | Ctrl+Enter Run | Ctrl+Shift+Enter Stop",
        cursorLine,
        cursorCol,
        (selStart ~= nil and selEnd ~= nil) and (selEnd - selStart) or 0
    )
    gfx.drawText(statusText, pad, h - statusH, w - pad * 2, statusH, Justify.centredLeft)
end

local function drawGraph()
    local w = math.floor(ui.graphCanvas:getWidth())
    local h = math.floor(ui.graphCanvas:getHeight())

    gfx.setColour(0xff0b1220)
    gfx.fillRoundedRect(0, 0, w, h, 6)
    gfx.setColour(0xff334155)
    gfx.drawRoundedRect(0, 0, w, h, 6, 1)

    local nodes = state.graphModel.nodes
    local edges = state.graphModel.edges

    if #nodes == 0 then
        gfx.setColour(0xff94a3b8)
        gfx.setFont(12.0)
        gfx.drawText("No nodes parsed from script", 12, 8, w - 24, 22, Justify.centredLeft)
        return
    end

    local positions = {}
    local graphLeft = 10
    local graphTop = 30
    local graphW = math.max(1, w - 20)
    local graphH = math.max(1, h - 40)
    local count = #nodes

    local aspect = graphW / math.max(1, graphH)
    local cols = math.max(1, math.ceil(math.sqrt(count * aspect)))
    local rows = math.max(1, math.ceil(count / cols))
    local cellW = graphW / cols
    local cellH = graphH / rows

    local maxNodeW = math.max(8, math.floor(cellW) - 4)
    local maxNodeH = math.max(8, math.floor(cellH) - 4)
    local nodeW = clamp(math.floor(cellW * 0.82), 8, maxNodeW)
    local nodeH = clamp(math.floor(cellH * 0.58), 8, maxNodeH)

    for i = 1, count do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local cellX = graphLeft + col * cellW
        local cellY = graphTop + row * cellH
        local x = math.floor(cellX + (cellW - nodeW) * 0.5 + 0.5)
        local y = math.floor(cellY + (cellH - nodeH) * 0.5 + 0.5)
        positions[i] = {
            x = x,
            y = y,
            cx = x + math.floor(nodeW * 0.5),
            cy = y + math.floor(nodeH * 0.5),
        }
    end

    gfx.setColour(0xff64748b)
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
        gfx.fillRoundedRect(p.x, p.y, nodeW, nodeH, 5)
        gfx.setColour(0xff38bdf8)
        gfx.drawRoundedRect(p.x, p.y, nodeW, nodeH, 5, 1)

        gfx.setColour(0xffe2e8f0)
        gfx.setFont(11.0)
        local label = n.var .. " : " .. n.prim
        gfx.drawText(label, p.x + 6, p.y + 4, math.floor(nodeW - 12), math.floor(nodeH - 8), Justify.centredLeft)
    end

    gfx.setColour(0xff94a3b8)
    gfx.setFont(11.0)
    gfx.drawText("parsed nodes=" .. tostring(#nodes) .. " edges=" .. tostring(#edges), 10, 8, w - 20, 18, Justify.centredLeft)
end

function ui_init(rootNode)
    root = rootNode
    ui = {}

    ui.rootPanel = W.Panel.new(root, "root", { bg = 0xff0f172a })

    -- Build options list dynamically from presets
    local presetOptions = {}
    for i, preset in ipairs(presets) do
        table.insert(presetOptions, preset.name)
    end
    
    ui.presetDropdown = W.Dropdown.new(ui.rootPanel.node, "preset", {
        options = presetOptions,
        selected = state.selectedPreset,
        bg = 0xff1e293b,
        colour = 0xff38bdf8,
        rootNode = root,
        on_select = function(idx)
            state.selectedPreset = idx
            setStatus("selected preset: " .. (presets[idx] and presets[idx].name or "unknown"))
        end,
    })

    ui.loadPresetButton = W.Button.new(ui.rootPanel.node, "loadPreset", {
        label = "Load Preset",
        bg = 0xff334155,
        on_click = function()
            applyPresetToEditor(state.selectedPreset)
        end,
    })

    ui.runButton = W.Button.new(ui.rootPanel.node, "run", {
        label = "Run Script",
        bg = 0xff0369a1,
        on_click = runEditorScript,
    })

    ui.stopButton = W.Button.new(ui.rootPanel.node, "stop", {
        label = "Stop",
        bg = 0xff9f1239,
        on_click = stopEditorScript,
    })

    ui.reloadButton = W.Button.new(ui.rootPanel.node, "reload", {
        label = "Reload",
        bg = 0xff334155,
        on_click = function()
            -- Reload the live-editor slot by re-running current editor code.
            runEditorScript()
        end,
    })

    ui.refreshButton = W.Button.new(ui.rootPanel.node, "refresh", {
        label = "Refresh List",
        bg = 0xff334155,
        on_click = function()
            -- Reload presets from disk
            loadPresets()
            -- Rebuild dropdown options
            local presetOptions = {}
            for i, preset in ipairs(presets) do
                table.insert(presetOptions, preset.name)
            end
            ui.presetDropdown:setOptions(presetOptions)
            setStatus("Reloaded " .. #presets .. " DSP scripts")
        end,
    })

    ui.editor = ui.rootPanel.node:addChild("scriptEditor")
    ui.editor:setInterceptsMouse(true, false)
    ui.editor:setWantsKeyboardFocus(true)
    ui.editor:setOnMouseDown(function(mx, my)
        state.editorFocused = true
        ui.editor:grabKeyboardFocus()

        local pos = cursorPosFromEditorPoint(mx, my)
        local clickedLine, _ = lineColFromPos(state.scriptText, pos)
        local now = getTime()
        local isRapid = (now - state.lastClickTime) <= 0.36
        local sameLine = clickedLine == state.lastClickLine

        if isRapid and sameLine then
            state.clickStreak = state.clickStreak + 1
        else
            state.clickStreak = 1
        end

        state.lastClickTime = now
        state.lastClickLine = clickedLine

        if state.clickStreak >= 3 then
            selectLineAtPos(pos)
            state.clickStreak = 0
            state.dragAnchorPos = nil
        elseif state.clickStreak == 2 then
            selectWordAtPos(pos)
            state.dragAnchorPos = nil
        else
            state.cursorPos = pos
            state.selectionAnchor = pos
            state.dragAnchorPos = pos
        end

        ensureCursorVisible()
        ui.editor:repaint()
    end)
    ui.editor:setOnMouseDrag(function(mx, my, dx, dy)
        local _ = dx
        _ = dy
        if state.dragAnchorPos == nil then
            state.dragAnchorPos = state.cursorPos
        end
        state.selectionAnchor = state.dragAnchorPos
        state.cursorPos = cursorPosFromEditorPoint(mx, my)
        if state.selectionAnchor == state.cursorPos then
            clearSelection()
        end
        ensureCursorVisible()
        ui.editor:repaint()
    end)
    ui.editor:setOnMouseUp(function(mx, my)
        local _ = mx
        _ = my
        state.dragAnchorPos = nil
        if state.selectionAnchor == state.cursorPos then
            clearSelection()
        end
        ui.editor:repaint()
    end)
    ui.editor:setOnMouseWheel(function(mx, my, dy)
        local _ = mx
        _ = my
        if dy > 0 then
            state.scrollRow = state.scrollRow - 2
        elseif dy < 0 then
            state.scrollRow = state.scrollRow + 2
        end
        local maxCols = getEditorMaxCols(math.floor(ui.editor:getWidth()))
        local rows = buildWrappedRows(state.scriptText, maxCols)
        local visible = getEditorVisibleLineCount(math.floor(ui.editor:getHeight()))
        local maxScroll = math.max(1, #rows - visible + 1)
        state.scrollRow = clamp(state.scrollRow, 1, maxScroll)
        ui.editor:repaint()
    end)
    ui.editor:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        local handled = handleEditorKey(keyCode, charCode, shift, ctrl, alt)
        if handled then
            ensureCursorVisible()
            ui.editor:repaint()
            if ui.graphCanvas then
                ui.graphCanvas:repaint()
            end
        end
        return handled
    end)
    ui.editor:setOnDraw(function(node)
        drawEditor(node)
    end)

    ui.graphTitle = W.Label.new(ui.rootPanel.node, "graphTitle", {
        text = "Computed Graph",
        colour = 0xffe2e8f0,
        fontSize = 13.0,
        justification = Justify.centredLeft,
    })

    ui.graphCanvas = ui.rootPanel.node:addChild("graphCanvas")
    ui.graphCanvas:setInterceptsMouse(false, false)
    ui.graphCanvas:setOnDraw(function(node)
        local _ = node
        drawGraph()
    end)

    ui.paramsTitle = W.Label.new(ui.rootPanel.node, "paramsTitle", {
        text = "Generated Parameters",
        colour = 0xffe2e8f0,
        fontSize = 13.0,
        justification = Justify.centredLeft,
    })

    ui.paramsPanel = W.Panel.new(ui.rootPanel.node, "paramsPanel", {
        bg = 0xff0b1220,
        border = 0xff334155,
        borderWidth = 1.0,
        radius = 6.0,
        on_wheel = function(x, y, deltaY)
            local _ = x
            _ = y
            handleParamScrollWheel(deltaY)
        end,
    })

    ui.paramState = W.Label.new(ui.paramsPanel.node, "paramState", {
        text = "Params: loading...",
        colour = 0xffc4b5fd,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    ui.graphMetrics = W.Label.new(ui.paramsPanel.node, "graphMetrics", {
        text = "runtime nodes=0 routes=0 | RMS in=0 wet=0 mix=0",
        colour = 0xff93c5fd,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    ui.status = W.Label.new(ui.paramsPanel.node, "status", {
        text = "Status: idle",
        colour = 0xff7dd3fc,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    ui.error = W.Label.new(ui.paramsPanel.node, "error", {
        text = "Error: none",
        colour = 0xfffca5a5,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    ui.paramScrollInfo = W.Label.new(ui.paramsPanel.node, "paramScrollInfo", {
        text = "Scroll: 0/0",
        colour = 0xff94a3b8,
        fontSize = 10.5,
        justification = Justify.centredLeft,
    })

    ui.paramScrollSlider = W.VSlider.new(ui.paramsPanel.node, "paramScrollSlider", {
        min = 0.0,
        max = 1.0,
        step = 0.0,
        value = 1.0,
        colour = 0xff64748b,
        bg = 0xff1f2937,
        showValue = false,
        on_change = function(v)
            local maxScroll = getParamMaxScroll()
            if maxScroll <= 0 then
                state.paramScroll = 0
            else
                state.paramScroll = (1.0 - v) * maxScroll
                clampParamScroll()
            end
            relayoutParams()
        end,
    })

    ui.paramsBody = ui.paramsPanel.node:addChild("paramsBody")
    ui.paramsBody:setInterceptsMouse(true, true)
    ui.paramsBody:setOnMouseWheel(function(mx, my, dy)
        local _ = mx
        _ = my
        handleParamScrollWheel(dy)
    end)

    -- Live editor slot should be transient unless explicitly pinned by script.
    setLiveSlotPersistOnSwitch(false)

    applyPresetToEditor(state.selectedPreset)
    relayout()
    state.lastW = math.floor(root:getWidth())
    state.lastH = math.floor(root:getHeight())
    setStatus("ready")
    refreshMetrics()
    refreshParamControlState()
end

function ui_update(engineState)
    if ui.rootPanel and root then
        local w = math.floor(root:getWidth())
        local h = math.floor(root:getHeight())
        if w ~= state.lastW or h ~= state.lastH then
            state.lastW = w
            state.lastH = h
            relayout()
        end
    end

    refreshMetrics()
    refreshParamControlState()
end

function ui_cleanup()
    -- Ensure live-editor input/effect chains do not persist across UI switches
    -- unless explicitly requested by a script.
    setLiveSlotPersistOnSwitch(false)
    if type(unloadDspSlot) == "function" then
        unloadDspSlot(LIVE_SLOT)
    end
end

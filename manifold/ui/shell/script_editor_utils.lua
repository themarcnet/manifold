-- shell/script_editor_utils.lua
-- Script editor helpers, tokenization, and console parsing.

local Base = require("shell.base_utils")
local clamp = Base.clamp

local M = {}

function M.seInvalidateCache(editor)
    if not editor then
        return
    end
    editor._textVersion = (editor._textVersion or 0) + 1
    editor._cachedLines = nil
    editor._cachedStarts = nil
    editor._cachedLinesVersion = nil
    editor._cachedCursorLine = nil
    editor._cachedCursorCol = nil
    editor._cachedCursorVersion = nil
    editor._cachedCursorPos = nil
end

function M.seBuildLinesCached(editor)
    if not editor then
        return M.seBuildLines("")
    end
    local version = editor._textVersion or 0
    if editor._cachedLines ~= nil and editor._cachedStarts ~= nil and editor._cachedLinesVersion == version then
        return editor._cachedLines, editor._cachedStarts
    end
    local lines, starts = M.seBuildLines(editor.text)
    editor._cachedLines = lines
    editor._cachedStarts = starts
    editor._cachedLinesVersion = version
    return lines, starts
end

function M.seLineColCached(editor)
    if not editor then
        return 1, 1
    end
    local version = editor._textVersion or 0
    local pos = editor.cursorPos or 1
    if editor._cachedCursorLine ~= nil
        and editor._cachedCursorCol ~= nil
        and editor._cachedCursorVersion == version
        and editor._cachedCursorPos == pos then
        return editor._cachedCursorLine, editor._cachedCursorCol
    end

    local src = editor.text or ""
    local p = clamp(pos, 1, #src + 1)
    local lines, starts = M.seBuildLinesCached(editor)

    for i = 1, #lines do
        local lineStart = starts[i]
        local nextStart = starts[i + 1] or (#src + 1)
        if p < nextStart then
            local line = i
            local col = clamp(p - lineStart + 1, 1, #lines[i] + 1)
            editor._cachedCursorLine = line
            editor._cachedCursorCol = col
            editor._cachedCursorVersion = version
            editor._cachedCursorPos = pos
            return line, col
        end
    end

    local line = #lines
    local col = #lines[#lines] + 1
    editor._cachedCursorLine = line
    editor._cachedCursorCol = col
    editor._cachedCursorVersion = version
    editor._cachedCursorPos = pos
    return line, col
end

function M.sePosFromLineColCached(editor, line, col)
    local lines, starts = M.seBuildLinesCached(editor)
    local li = clamp(line or 1, 1, #lines)
    local lc = clamp(col or 1, 1, #lines[li] + 1)
    return starts[li] + lc - 1
end

M.SCRIPT_EDITOR_STYLE = {
    fontName = "Monospace",
    fontSize = 12.0,
    charW = 7.4,
    lineH = 16,
    gutterW = 44,
    pad = 8,
    statusH = 20,
    headerH = 32,
}

function M.seBuildLines(text)
    local src = text or ""
    local lines = {}
    local starts = {}
    local i = 1
    local n = #src

    while i <= n do
        starts[#starts + 1] = i
        local j = string.find(src, "\n", i, true)
        if j == nil then
            lines[#lines + 1] = string.sub(src, i)
            i = n + 1
        else
            lines[#lines + 1] = string.sub(src, i, j - 1)
            i = j + 1
        end
    end

    if #lines == 0 then
        lines[1] = ""
        starts[1] = 1
    end

    return lines, starts
end

function M.seLineColFromPos(text, pos)
    local src = text or ""
    local p = clamp(pos or 1, 1, #src + 1)
    local lines, starts = M.seBuildLines(src)

    for i = 1, #lines do
        local lineStart = starts[i]
        local nextStart = starts[i + 1] or (#src + 1)
        if p < nextStart then
            return i, clamp(p - lineStart + 1, 1, #lines[i] + 1)
        end
    end

    return #lines, #lines[#lines] + 1
end

function M.sePosFromLineCol(text, line, col)
    local src = text or ""
    local lines, starts = M.seBuildLines(src)
    local li = clamp(line or 1, 1, #lines)
    local lc = clamp(col or 1, 1, #lines[li] + 1)
    return starts[li] + lc - 1
end

function M.seGetSelectionRange(editor)
    if not editor or editor.selectionAnchor == nil then
        return nil, nil
    end

    local a = clamp(editor.selectionAnchor, 1, #(editor.text or "") + 1)
    local b = clamp(editor.cursorPos or 1, 1, #(editor.text or "") + 1)
    if a == b then
        return nil, nil
    end
    if a < b then
        return a, b
    end
    return b, a
end

function M.seClearSelection(editor)
    if editor then
        editor.selectionAnchor = nil
    end
end

function M.seDeleteSelection(editor)
    local a, b = M.seGetSelectionRange(editor)
    if a == nil or b == nil then
        return false
    end

    local src = editor.text or ""
    editor.text = string.sub(src, 1, a - 1) .. string.sub(src, b)
    editor.cursorPos = a
    M.seClearSelection(editor)
    M.seInvalidateCache(editor)
    return true
end

function M.seReplaceSelection(editor, text)
    M.seDeleteSelection(editor)
    local src = editor.text or ""
    local ins = text or ""
    local p = clamp(editor.cursorPos or 1, 1, #src + 1)
    editor.text = string.sub(src, 1, p - 1) .. ins .. string.sub(src, p)
    editor.cursorPos = p + #ins
    M.seClearSelection(editor)
    M.seInvalidateCache(editor)
end

function M.seMoveCursor(editor, newPos, keepSelection)
    local src = editor.text or ""
    local oldPos = clamp(editor.cursorPos or 1, 1, #src + 1)
    editor.cursorPos = clamp(newPos or oldPos, 1, #src + 1)

    if keepSelection then
        if editor.selectionAnchor == nil then
            editor.selectionAnchor = oldPos
        end
        if editor.selectionAnchor == editor.cursorPos then
            M.seClearSelection(editor)
        end
    else
        M.seClearSelection(editor)
    end
end

function M.seVisibleLineCount(viewH)
    local style = M.SCRIPT_EDITOR_STYLE
    local contentH = math.max(style.lineH, viewH - style.headerH - style.statusH - style.pad * 2)
    return math.max(1, math.floor(contentH / style.lineH))
end

function M.seMaxCols(viewW)
    local style = M.SCRIPT_EDITOR_STYLE
    local textX = style.gutterW + style.pad + 4
    return math.max(1, math.floor((viewW - textX - style.pad) / style.charW))
end

function M.seIsLetterShortcut(keyCode, charCode, letter)
    local upper = string.byte(string.upper(letter))
    local lower = string.byte(string.lower(letter))
    return keyCode == upper or keyCode == lower or charCode == upper or charCode == lower
end

function M.isBacktickOrTildeKey(keyCode, charCode)
    return keyCode == 96 or keyCode == 126 or charCode == 96 or charCode == 126
end

function M.splitConsoleWords(text)
    local out = {}
    local src = tostring(text or "")
    local i = 1
    local n = #src

    while i <= n do
        while i <= n and string.match(string.sub(src, i, i), "%s") do
            i = i + 1
        end
        if i > n then
            break
        end

        local ch = string.sub(src, i, i)
        if ch == '"' then
            local j = i + 1
            while j <= n and string.sub(src, j, j) ~= '"' do
                j = j + 1
            end
            out[#out + 1] = string.sub(src, i + 1, j - 1)
            i = j + 1
        else
            local j = i
            while j <= n and not string.match(string.sub(src, j, j), "%s") do
                j = j + 1
            end
            out[#out + 1] = string.sub(src, i, j - 1)
            i = j
        end
    end

    return out
end

function M.parseConsoleScalar(text)
    local raw = tostring(text or "")
    local lower = string.lower(raw)
    if lower == "true" then
        return true
    end
    if lower == "false" then
        return false
    end
    local n = tonumber(raw)
    if n ~= nil then
        return n
    end
    return raw
end

local SCRIPT_LUA_KEYWORDS = {
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

local SCRIPT_LUA_BUILTINS = {
    ["buildPlugin"] = true,
    ["ctx"] = true,
    ["math"] = true,
    ["string"] = true,
    ["table"] = true,
}

local SCRIPT_SYNTAX_COLOUR = {
    text = 0xffe2e8f0,
    keyword = 0xfff59e0b,
    builtin = 0xff67e8f9,
    number = 0xffc4b5fd,
    string = 0xff86efac,
    comment = 0xff34d399,
    operator = 0xfff9a8d4,
}

M.SCRIPT_SYNTAX_COLOUR = SCRIPT_SYNTAX_COLOUR

local function sePushSpan(spans, text, colour)
    if text == nil or text == "" then
        return
    end
    spans[#spans + 1] = {
        text = text,
        colour = colour,
    }
end

local function seTokenizeLuaLine(line)
    local spans = {}
    local i = 1
    local n = #line

    while i <= n do
        local ch = string.sub(line, i, i)
        local nextTwo = string.sub(line, i, i + 1)

        if nextTwo == "--" then
            sePushSpan(spans, string.sub(line, i), SCRIPT_SYNTAX_COLOUR.comment)
            break
        end

        if ch == '"' or ch == "'" then
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
            sePushSpan(spans, string.sub(line, i, j - 1), SCRIPT_SYNTAX_COLOUR.string)
            i = j
        elseif string.match(ch, "[%a_]") then
            local j = i + 1
            while j <= n and string.match(string.sub(line, j, j), "[%w_]") do
                j = j + 1
            end
            local ident = string.sub(line, i, j - 1)
            local colour = SCRIPT_SYNTAX_COLOUR.text
            if SCRIPT_LUA_KEYWORDS[ident] then
                colour = SCRIPT_SYNTAX_COLOUR.keyword
            elseif SCRIPT_LUA_BUILTINS[ident] then
                colour = SCRIPT_SYNTAX_COLOUR.builtin
            end
            sePushSpan(spans, ident, colour)
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
            sePushSpan(spans, string.sub(line, i, j - 1), SCRIPT_SYNTAX_COLOUR.number)
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
            sePushSpan(spans, string.sub(line, i, j - 1), SCRIPT_SYNTAX_COLOUR.text)
            i = j
        else
            local j = i
            while j <= n do
                local cj = string.sub(line, j, j)
                local c2 = string.sub(line, j, j + 1)
                if c2 == "--" or cj == " " or cj == "\t" or cj == '"' or cj == "'" or string.match(cj, "[%w_]") then
                    break
                end
                j = j + 1
            end
            if j == i then
                j = i + 1
            end
            sePushSpan(spans, string.sub(line, i, j - 1), SCRIPT_SYNTAX_COLOUR.operator)
            i = j
        end
    end

    return spans
end

local SE_LINE_TOKEN_CACHE_MAX = 512
local seLineTokenCache = {}
local seLineTokenCacheOrder = {}

function M.seTokenizeLuaLineCached(line)
    local key = line or ""
    local cached = seLineTokenCache[key]
    if cached ~= nil then
        return cached
    end

    local spans = seTokenizeLuaLine(key)
    seLineTokenCache[key] = spans
    seLineTokenCacheOrder[#seLineTokenCacheOrder + 1] = key

    if #seLineTokenCacheOrder > SE_LINE_TOKEN_CACHE_MAX then
        local drop = table.remove(seLineTokenCacheOrder, 1)
        seLineTokenCache[drop] = nil
    end

    return spans
end

return M

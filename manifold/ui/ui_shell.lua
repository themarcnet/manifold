-- ui_shell.lua
-- Shared parent shell/header for Lua UI scripts.

local W = require("ui_widgets")

local Shell = {}

local function readParam(params, path, fallback)
    if type(params) ~= "table" then
        return fallback
    end
    local v = params[path]
    if v == nil then
        return fallback
    end
    return v
end

local function readBoolParam(params, path, fallback)
    local raw = readParam(params, path, fallback and 1 or 0)
    if raw == nil then
        return fallback
    end
    return raw == true or raw == 1
end

local function getVisibleUiScripts(currentPath)
    local listed = listUiScripts() or {}
    local visible = {}
    for i = 1, #listed do
        local s = listed[i]
        if type(s) == "table" and type(s.path) == "string" then
            local name = string.lower(s.name or "")
            local path = string.lower(s.path or "")
            if name:find("settings", 1, true) or path:find("settings", 1, true) then
                visible[#visible + 1] = s
            end
        end
    end
    return visible
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function nowSeconds()
    if getTime then
        return getTime()
    end
    if os and os.clock then
        return os.clock()
    end
    return 0
end

local function deriveNodeName(meta, fallback)
    if type(meta) ~= "table" then
        return fallback
    end

    if type(meta.name) == "string" and #meta.name > 0 then
        return meta.name
    end

    local cfg = meta.config
    if type(cfg) == "table" then
        if type(cfg.id) == "string" and #cfg.id > 0 then
            return cfg.id
        end
        if type(cfg.label) == "string" and #cfg.label > 0 then
            return cfg.label
        end
        if type(cfg.text) == "string" and #cfg.text > 0 then
            return cfg.text
        end
    end

    return fallback
end

local function fileStem(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    local name = path:match("([^/\\]+)$") or path
    return name:gsub("%.lua$", "")
end

local SCRIPT_EDITOR_STYLE = {
    fontName = "Monospace",
    fontSize = 12.0,
    charW = 7.4,
    lineH = 16,
    gutterW = 44,
    pad = 8,
    statusH = 20,
    headerH = 32,
}

local function seBuildLines(text)
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

local function seLineColFromPos(text, pos)
    local src = text or ""
    local p = clamp(pos or 1, 1, #src + 1)
    local lines, starts = seBuildLines(src)

    for i = 1, #lines do
        local lineStart = starts[i]
        local nextStart = starts[i + 1] or (#src + 1)
        if p < nextStart then
            return i, clamp(p - lineStart + 1, 1, #lines[i] + 1)
        end
    end

    return #lines, #lines[#lines] + 1
end

local function sePosFromLineCol(text, line, col)
    local src = text or ""
    local lines, starts = seBuildLines(src)
    local li = clamp(line or 1, 1, #lines)
    local lc = clamp(col or 1, 1, #lines[li] + 1)
    return starts[li] + lc - 1
end

local function seGetSelectionRange(editor)
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

local function seClearSelection(editor)
    if editor then
        editor.selectionAnchor = nil
    end
end

local function seDeleteSelection(editor)
    local a, b = seGetSelectionRange(editor)
    if a == nil or b == nil then
        return false
    end

    local src = editor.text or ""
    editor.text = string.sub(src, 1, a - 1) .. string.sub(src, b)
    editor.cursorPos = a
    seClearSelection(editor)
    return true
end

local function seReplaceSelection(editor, text)
    seDeleteSelection(editor)
    local src = editor.text or ""
    local ins = text or ""
    local p = clamp(editor.cursorPos or 1, 1, #src + 1)
    editor.text = string.sub(src, 1, p - 1) .. ins .. string.sub(src, p)
    editor.cursorPos = p + #ins
    seClearSelection(editor)
end

local function seMoveCursor(editor, newPos, keepSelection)
    local src = editor.text or ""
    local oldPos = clamp(editor.cursorPos or 1, 1, #src + 1)
    editor.cursorPos = clamp(newPos or oldPos, 1, #src + 1)

    if keepSelection then
        if editor.selectionAnchor == nil then
            editor.selectionAnchor = oldPos
        end
        if editor.selectionAnchor == editor.cursorPos then
            seClearSelection(editor)
        end
    else
        seClearSelection(editor)
    end
end

local function seVisibleLineCount(viewH)
    local contentH = math.max(SCRIPT_EDITOR_STYLE.lineH, viewH - SCRIPT_EDITOR_STYLE.headerH - SCRIPT_EDITOR_STYLE.statusH - SCRIPT_EDITOR_STYLE.pad * 2)
    return math.max(1, math.floor(contentH / SCRIPT_EDITOR_STYLE.lineH))
end

local function seMaxCols(viewW)
    local textX = SCRIPT_EDITOR_STYLE.gutterW + SCRIPT_EDITOR_STYLE.pad + 4
    return math.max(1, math.floor((viewW - textX - SCRIPT_EDITOR_STYLE.pad) / SCRIPT_EDITOR_STYLE.charW))
end

local function seIsLetterShortcut(keyCode, charCode, letter)
    local upper = string.byte(string.upper(letter))
    local lower = string.byte(string.lower(letter))
    return keyCode == upper or keyCode == lower or charCode == upper or charCode == lower
end

local function isBacktickOrTildeKey(keyCode, charCode)
    return keyCode == 96 or keyCode == 126 or charCode == 96 or charCode == 126
end

local function splitConsoleWords(text)
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

local function parseConsoleScalar(text)
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
                if c2 == "--" or cj == " " or cj == "\t" or cj == "\"" or cj == "'" or string.match(cj, "[%w_]") then
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

local function seTokenizeLuaLineCached(line)
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

local RuntimeParamSlider = W.Slider:extend()

function RuntimeParamSlider.new(parent, name, config)
    local self = setmetatable(W.Slider.new(parent, name, config), RuntimeParamSlider)
    self._showValue = false
    self._displayText = config.displayText or ""
    self._editing = false
    self._onCtrlClick = config.on_ctrl_click or config.onCtrlClick
    self._onDragState = config.on_drag_state or config.onDragState
    return self
end

function RuntimeParamSlider:setDisplayText(text)
    self._displayText = text or ""
end

function RuntimeParamSlider:setEditing(editing)
    self._editing = editing == true
end

function RuntimeParamSlider:setVisualRange(minV, maxV, stepV)
    self._min = tonumber(minV) or 0
    self._max = tonumber(maxV) or 1
    if self._max <= self._min then
        self._max = self._min + 1
    end
    self._step = tonumber(stepV) or 0
    self._value = clamp(self._value or self._min, self._min, self._max)
end

function RuntimeParamSlider:onMouseDown(mx, my, shift, ctrl, alt)
    local _ = shift
    _ = alt
    if ctrl and self._onCtrlClick then
        self._onCtrlClick(self._value)
        return
    end
    self._dragging = true
    if self._onDragState then
        self._onDragState(true)
    end
    self:valueFromMouse(mx)
end

function RuntimeParamSlider:onMouseUp(mx, my, shift, ctrl, alt)
    local _ = mx
    _ = my
    _ = shift
    _ = ctrl
    _ = alt
    self._dragging = false
    if self._onDragState then
        self._onDragState(false)
    end
end

function RuntimeParamSlider:onDraw(w, h)
    local t = (self._value - self._min) / math.max(0.0001, self._max - self._min)
    t = clamp(t, 0, 1)

    local bg = self:isEnabled() and 0xff0b1220 or 0xff111827
    local border = self._editing and 0xff38bdf8 or (self:isEnabled() and 0xff334155 or 0xff1f2937)

    gfx.setColour(bg)
    gfx.fillRoundedRect(0, 0, w, h, 3)
    gfx.setColour(border)
    gfx.drawRoundedRect(0, 0, w, h, 3, 1)

    local fillW = math.floor((w - 2) * t)
    if fillW > 0 then
        gfx.setColour(self:isEnabled() and 0xff38bdf8 or 0xff334155)
        gfx.fillRoundedRect(1, 1, fillW, h - 2, 2)
    end

    gfx.setColour(self:isEnabled() and 0xffe2e8f0 or 0xff64748b)
    gfx.setFont(8.5)
    gfx.drawText(self._displayText or "", 2, 0, w - 4, h, Justify.centred)
end

local function scriptLooksSettings(name, path)
    local n = string.lower(name or "")
    local p = string.lower(path or "")
    return n:find("settings", 1, true) ~= nil or p:find("settings", 1, true) ~= nil
end

local function scriptLooksGlobal(name, path)
    local n = string.lower(name or "")
    local p = string.lower(path or "")
    if n:find("global", 1, true) or p:find("global", 1, true) then
        return true
    end
    if n:find("shared", 1, true) or p:find("shared", 1, true) then
        return true
    end
    if n:find("system", 1, true) or p:find("system", 1, true) then
        return true
    end
    return false
end

local function scriptLooksDemo(name, path)
    local n = string.lower(name or "")
    local p = string.lower(path or "")
    if n:find("demo", 1, true) or p:find("demo", 1, true) then
        return true
    end
    if n:find("example", 1, true) or p:find("example", 1, true) then
        return true
    end
    if n:find("test", 1, true) or p:find("test", 1, true) then
        return true
    end
    return false
end

local function collectActiveSlotHints(params)
    local hints = {}
    if type(params) ~= "table" then
        return hints
    end

    for key, _ in pairs(params) do
        if type(key) == "string" then
            local slot = key:match("^/core/slots/([^/]+)/")
            if type(slot) == "string" and slot ~= "" then
                hints[string.lower(slot)] = true
            end

            local dspNs = key:match("^/dsp/([^/]+)/")
            if type(dspNs) == "string" and dspNs ~= "" then
                hints[string.lower(dspNs)] = true
            end
        end
    end

    if params["/core/behavior/volume"] ~= nil then
        hints["behavior"] = true
        hints["looper"] = true
    end

    return hints
end

local function scriptMatchesActiveSlot(scriptName, slotHints)
    if type(scriptName) ~= "string" then
        return false
    end

    local s = string.lower(scriptName)
    for slot, _ in pairs(slotHints or {}) do
        if slot == s then
            return true
        end
        if s:find(slot, 1, true) or slot:find(s, 1, true) then
            return true
        end
    end

    return false
end

local function collectUiContextHints(currentUiPath)
    local hints = {}
    local stem = string.lower(fileStem(currentUiPath or ""))
    if stem == "" then
        return hints
    end

    stem = stem:gsub("_ui$", "")
    for token in stem:gmatch("[a-z0-9]+") do
        if #token >= 3 then
            hints[token] = true
        end
    end

    if next(hints) == nil and #stem >= 3 then
        hints[stem] = true
    end

    return hints
end

local function scriptMatchesUiContext(name, path, uiContextHints)
    if type(uiContextHints) ~= "table" or next(uiContextHints) == nil then
        return false
    end

    local n = string.lower(name or "")
    local p = string.lower(path or "")
    for token, _ in pairs(uiContextHints) do
        if n == token or n:find(token, 1, true) or p:find(token, 1, true) then
            return true
        end
    end

    return false
end

local function parseNumberOr(text, fallback)
    local n = tonumber(text)
    if n == nil then
        return fallback
    end
    return n
end

local function parseDspParamDefsFromCode(code)
    local defs = {}
    local src = code or ""
    local byPath = {}

    -- Pass 1: robust path extraction (works with single/double quotes and multiline bodies)
    for path in src:gmatch("ctx%.params%.register%s*%(%s*['\"]([^'\"]+)['\"]") do
        if byPath[path] == nil then
            local d = {
                path = path,
                min = nil,
                max = nil,
                default = nil,
            }
            byPath[path] = d
            defs[#defs + 1] = d
        end
    end

    -- Pass 2: enrich with numeric metadata where easy to parse inline
    for path, body in src:gmatch('ctx%.params%.register%s*%(%s*["\']([^"\']+)["\']%s*,%s*%{(.-)%}%s*%)') do
        local d = byPath[path]
        if d then
            d.min = parseNumberOr(body:match("min%s*=%s*([%-%d%.]+)"), d.min)
            d.max = parseNumberOr(body:match("max%s*=%s*([%-%d%.]+)"), d.max)
            d.default = parseNumberOr(body:match("default%s*=%s*([%-%d%.]+)"), d.default)
        end
    end

    table.sort(defs, function(a, b)
        return (a.path or "") < (b.path or "")
    end)

    return defs
end

local function parseDspGraphFromCode(code)
    local graph = { nodes = {}, edges = {} }
    local varToIndex = {}
    local src = code or ""

    for varName, primType in src:gmatch("local%s+([%w_]+)%s*=%s*ctx%.primitives%.([%w_]+)%.new") do
        if varToIndex[varName] == nil then
            local idx = #graph.nodes + 1
            varToIndex[varName] = idx
            graph.nodes[idx] = {
                var = varName,
                prim = primType,
            }
        end
    end

    for fromVar, toVar in src:gmatch("ctx%.graph%.connect%s*%(%s*([%w_]+)%s*,%s*([%w_]+)") do
        local fromIdx = varToIndex[fromVar]
        local toIdx = varToIndex[toVar]
        if fromIdx ~= nil and toIdx ~= nil then
            graph.edges[#graph.edges + 1] = {
                from = fromIdx,
                to = toIdx,
            }
        end
    end

    return graph
end

local function pointInRect(mx, my, rect)
    if type(rect) ~= "table" then
        return false
    end
    return mx >= rect.x and mx <= (rect.x + rect.w) and my >= rect.y and my <= (rect.y + rect.h)
end

local function formatRuntimeValue(v)
    local t = type(v)
    if t == "number" then
        if math.floor(v) == v then
            return tostring(math.floor(v))
        end
        return string.format("%.4f", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "string" then
        return v
    end
    return ""
end

local function mapBehaviorPathToSlotPath(path, slotName)
    local p = path or ""
    local slot = slotName or ""
    if slot == "" then
        return p
    end
    if p:sub(1, 15) == "/core/behavior/" then
        return "/core/slots/" .. slot .. p:sub(15)
    end
    return p
end

local function collectRuntimeParamsForScript(row, params, declaredParams, slotName)
    local out = {}
    if type(row) ~= "table" then
        return out
    end

    local hasEndpointFn = (type(hasEndpoint) == "function") and hasEndpoint or nil
    local getParamFn = (type(getParam) == "function") and getParam or nil

    -- Prefer exact declared paths so scripts loaded by the editor still show
    -- intended params even when context heuristics are imperfect.
    if type(declaredParams) == "table" and #declaredParams > 0 then
        for i = 1, #declaredParams do
            local d = declaredParams[i]
            local p = d and d.path or ""
            if p ~= "" then
                local endpoint = p
                local active = false
                local raw = nil

                if hasEndpointFn then
                    active = hasEndpointFn(endpoint)
                elseif type(params) == "table" then
                    local t = type(params[endpoint])
                    active = (t == "number" or t == "boolean" or t == "string")
                end

                if (not active) and slotName and slotName ~= "" then
                    local mapped = mapBehaviorPathToSlotPath(endpoint, slotName)
                    if mapped ~= endpoint then
                        if hasEndpointFn then
                            active = hasEndpointFn(mapped)
                        elseif type(params) == "table" then
                            local t2 = type(params[mapped])
                            active = (t2 == "number" or t2 == "boolean" or t2 == "string")
                        end
                        if active then
                            endpoint = mapped
                        end
                    end
                end

                local numericValue = nil
                if active then
                    if getParamFn then
                        raw = getParamFn(endpoint)
                    elseif type(params) == "table" then
                        raw = params[endpoint]
                    end
                    if type(raw) == "number" then
                        numericValue = raw
                    end
                end

                out[#out + 1] = {
                    path = p,
                    endpointPath = endpoint,
                    value = active and formatRuntimeValue(raw) or "<inactive>",
                    active = active,
                    numericValue = numericValue,
                    min = d.min,
                    max = d.max,
                    step = d.step,
                }
            end
        end
        return out
    end

    if type(params) ~= "table" then
        return out
    end

    local name = string.lower(row.name or fileStem(row.path or "") or "")
    local tokens = {}
    for t in name:gmatch("[a-z0-9]+") do
        if #t >= 3 and t ~= "dsp" and t ~= "script" and t ~= "primitives" then
            tokens[t] = true
        end
    end

    local prefixes = {}
    local function addPrefix(p)
        if type(p) == "string" and p ~= "" then
            prefixes[#prefixes + 1] = p
        end
    end

    if tokens["looper"] then
        addPrefix("/core/behavior/")
        addPrefix("/dsp/looper/")
    end

    for token, _ in pairs(tokens) do
        addPrefix("/core/slots/" .. token .. "/")
        addPrefix("/dsp/" .. token .. "/")
    end

    if #prefixes == 0 then
        addPrefix("/dsp/")
    end

    local seen = {}
    local keys = {}
    for k, _ in pairs(params) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)

    for i = 1, #keys do
        local key = keys[i]
        local raw = params[key]
        local t = type(raw)
        if t == "number" or t == "boolean" or t == "string" then
            local include = false
            for p = 1, #prefixes do
                local pref = prefixes[p]
                if key:sub(1, #pref) == pref then
                    include = true
                    break
                end
            end
            if include and not seen[key] then
                seen[key] = true
                out[#out + 1] = {
                    path = key,
                    endpointPath = key,
                    value = formatRuntimeValue(raw),
                    active = true,
                    numericValue = (type(raw) == "number") and raw or nil,
                }
            end
        end
    end

    return out
end

local function walkHierarchy(canvas, depth, flatOut, parentAbsX, parentAbsY, parentPath, childIndex)
    if not canvas then
        return nil
    end

    local bx, by, bw, bh = canvas:getBounds()
    local absX = (parentAbsX or 0) + (bx or 0)
    local absY = (parentAbsY or 0) + (by or 0)

    local meta = canvas:getUserData("_editorMeta")
    local nodeType = "Canvas"
    if type(meta) == "table" and type(meta.type) == "string" and #meta.type > 0 then
        nodeType = meta.type
    end

    local fallbackName = depth == 0 and "ContentRoot" or nodeType
    local nodeName = deriveNodeName(meta, fallbackName)

    local basePath = parentPath or ""
    local indexPart = tostring(childIndex or 0)
    local thisPath = basePath == "" and (indexPart .. ":" .. nodeName) or (basePath .. "/" .. indexPart .. ":" .. nodeName)

    local node = {
        name = nodeName,
        type = nodeType,
        children = {},
        canvas = canvas,
        depth = depth,
        x = absX,
        y = absY,
        w = bw or 0,
        h = bh or 0,
        path = thisPath,
    }

    flatOut[#flatOut + 1] = node

    local numChildren = canvas:getNumChildren() or 0
    for i = 0, numChildren - 1 do
        local child = canvas:getChild(i)
        if child ~= nil then
            local childNode = walkHierarchy(child, depth + 1, flatOut, absX, absY, thisPath, i)
            if childNode ~= nil then
                node.children[#node.children + 1] = childNode
            end
        end
    end

    return node
end

local function valueToText(v)
    local tv = type(v)
    if tv == "number" then
        if math.floor(v) == v then
            return string.format("%d", v)
        end
        return string.format("%.4f", v)
    end
    if tv == "boolean" then
        return v and "true" or "false"
    end
    if tv == "string" then
        return v
    end
    if tv == "function" then
        return "<function>"
    end
    if tv == "table" then
        return "<table>"
    end
    return "<" .. tv .. ">"
end

local function upperFirst(text)
    if type(text) ~= "string" or #text == 0 then
        return text
    end
    return text:sub(1, 1):upper() .. text:sub(2)
end

local function splitPath(path)
    local parts = {}
    if type(path) ~= "string" then
        return parts
    end
    for part in string.gmatch(path, "[^%.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function normalizeConfigPath(path)
    if type(path) ~= "string" then
        return ""
    end
    if path:sub(1, 7) == "config." then
        return path:sub(8)
    end
    if path == "config" then
        return ""
    end
    return path
end

local function getPathTail(path)
    local parts = splitPath(path)
    if #parts == 0 then
        return ""
    end
    return parts[#parts]
end

local function getConfigValueByPath(root, path)
    if type(root) ~= "table" then
        return nil
    end

    local normalized = normalizeConfigPath(path)
    if normalized == "" then
        return root
    end

    local parts = splitPath(normalized)
    local current = root
    for i = 1, #parts do
        if type(current) ~= "table" then
            return nil
        end
        current = current[parts[i]]
    end
    return current
end

local function setConfigValueByPath(root, path, value)
    if type(root) ~= "table" then
        return false
    end

    local normalized = normalizeConfigPath(path)
    if normalized == "" then
        return false
    end

    local parts = splitPath(normalized)
    if #parts == 0 then
        return false
    end

    local current = root
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(current[part]) ~= "table" then
            return false
        end
        current = current[part]
    end

    current[parts[#parts]] = value
    return true
end

local function isPathExposed(widget, path)
    if type(widget) ~= "table" or type(widget.getExposedParams) ~= "function" then
        return false
    end
    local exposed = widget:getExposedParams()
    if type(exposed) ~= "table" then
        return false
    end
    for i = 1, #exposed do
        local item = exposed[i]
        if type(item) == "table" and item.path == path then
            return true
        end
    end
    return false
end

local function getInspectorValue(widget, meta, path)
    -- First check if this is an exposed param on the widget
    if isPathExposed(widget, path) then
        if type(widget._getExposed) == "function" then
            local v = widget:_getExposed(path)
            if v ~= nil then
                return v
            end
        end
    end

    -- Fallback to config table
    if type(meta) == "table" and type(meta.config) == "table" then
        return getConfigValueByPath(meta.config, path)
    end

    return nil
end

local function guessEnumOptions(path, value)
    local key = string.lower(getPathTail(path) or "")

    if key == "justification" and Justify then
        return {
            { label = "centred", value = Justify.centred },
            { label = "centredLeft", value = Justify.centredLeft },
            { label = "centredRight", value = Justify.centredRight },
            { label = "topLeft", value = Justify.topLeft },
            { label = "topRight", value = Justify.topRight },
            { label = "bottomLeft", value = Justify.bottomLeft },
            { label = "bottomRight", value = Justify.bottomRight },
        }
    end

    if key == "fontstyle" and FontStyle then
        return {
            { label = "plain", value = FontStyle.plain },
            { label = "bold", value = FontStyle.bold },
            { label = "italic", value = FontStyle.italic },
            { label = "boldItalic", value = FontStyle.boldItalic },
        }
    end

    if key == "orientation" then
        return {
            { label = "vertical", value = "vertical" },
            { label = "horizontal", value = "horizontal" },
        }
    end

    if key == "mode" then
        return {
            { label = "layer", value = "layer" },
            { label = "capture", value = "capture" },
            { label = "firstLoop", value = "firstLoop" },
            { label = "freeMode", value = "freeMode" },
            { label = "traditional", value = "traditional" },
        }
    end

    if type(value) == "string" and (value == "left" or value == "right" or value == "center" or value == "centre") then
        return {
            { label = "left", value = "left" },
            { label = "center", value = "center" },
            { label = "right", value = "right" },
        }
    end

    return nil
end

local function inferEditorType(path, value)
    local t = type(value)
    local key = string.lower(path or "")
    local enumOptions = guessEnumOptions(path, value)

    if enumOptions then
        return "enum", enumOptions
    end

    if t == "boolean" then
        return "bool", nil
    end

    if t == "number" then
        if key:find("colour", 1, true) or key:find("color", 1, true) or key:find("bg", 1, true) then
            return "color", nil
        end
        return "number", nil
    end

    if t == "string" then
        return "text", nil
    end

    return nil, nil
end

local CONFIG_KEY_PRIORITY = {
    id = 1,
    name = 2,
    label = 3,
    text = 4,
    value = 5,
    min = 6,
    max = 7,
    step = 8,
    x = 10,
    y = 11,
    w = 12,
    h = 13,
    bg = 20,
    colour = 21,
    color = 21,
    textcolour = 22,
    fontsize = 23,
    fontstyle = 24,
    radius = 25,
    border = 26,
    borderwidth = 27,
    enabled = 30,
}

local function appendConfigRows(tbl, outRows, prefix, depth, visited)
    if type(tbl) ~= "table" then
        return
    end
    if visited[tbl] then
        return
    end
    visited[tbl] = true

    local keys = {}
    for k, _ in pairs(tbl) do
        keys[#keys + 1] = k
    end

    table.sort(keys, function(a, b)
        local sa = string.lower(tostring(a))
        local sb = string.lower(tostring(b))
        local pa = CONFIG_KEY_PRIORITY[sa] or 999
        local pb = CONFIG_KEY_PRIORITY[sb] or 999
        if pa ~= pb then
            return pa < pb
        end
        return sa < sb
    end)

    for i = 1, #keys do
        local key = keys[i]
        local value = tbl[key]
        local valueType = type(value)
        local keyName = tostring(key)
        local keyText = prefix ~= "" and (prefix .. "." .. keyName) or keyName

        if shouldSkipFallbackConfigKey(keyName) then
            goto continue
        end

        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            local editorType, enumOptions = inferEditorType(keyText, value)
            outRows[#outRows + 1] = {
                key = keyText,
                value = valueToText(value),
                rawValue = value,
                path = keyText,
                isConfig = true,
                editorType = editorType,
                enumOptions = enumOptions,
            }
        elseif valueType == "table" and depth < 1 then
            outRows[#outRows + 1] = {
                key = keyText,
                value = "",
                isConfig = false,
                editorType = nil,
            }
            appendConfigRows(value, outRows, keyText, depth + 1, visited)
        elseif valueType ~= "function" then
            outRows[#outRows + 1] = {
                key = keyText,
                value = valueToText(value),
                rawValue = value,
                path = keyText,
                isConfig = true,
                editorType = nil,
            }
        end

        ::continue::
    end
end

local function appendSchemaRows(schema, config, outRows, widget, meta)
    if type(schema) ~= "table" then
        return false
    end

    local hasRows = false
    local currentGroup = nil

    for i = 1, #schema do
        local item = schema[i]
        if type(item) == "table" and type(item.path) == "string" then
            local path = item.path
            local value = getInspectorValue(widget, meta, path)
            if value == nil then
                value = getConfigValueByPath(config, path)
            end
            if value ~= nil then
                local group = item.group or "Config"
                if group ~= currentGroup then
                    currentGroup = group
                    outRows[#outRows + 1] = {
                        key = group,
                        value = "",
                        isConfig = false,
                        editorType = nil,
                    }
                end

                local editorType = item.type
                local enumOptions = item.options
                if editorType == nil then
                    editorType, enumOptions = inferEditorType(path, value)
                end

                outRows[#outRows + 1] = {
                    key = item.label or path,
                    value = valueToText(value),
                    rawValue = value,
                    path = "config." .. path,
                    isConfig = true,
                    editorType = editorType,
                    enumOptions = enumOptions,
                    min = item.min,
                    max = item.max,
                    step = item.step,
                    format = item.format,
                }
                hasRows = true
            end
        end
    end

    return hasRows
end

local function rectsIntersect(ax, ay, aw, ah, bx, by, bw, bh)
    return ax <= bx + bw and ax + aw >= bx and ay <= by + bh and ay + ah >= by
end

local function rectContainsRect(outerX, outerY, outerW, outerH, innerX, innerY, innerW, innerH)
    return innerX >= outerX and innerY >= outerY
        and (innerX + innerW) <= (outerX + outerW)
        and (innerY + innerH) <= (outerY + outerH)
end

local function computeGridStep(scale)
    local safeScale = math.max(0.0001, scale or 1.0)
    local targetDesignStep = 18.0 / safeScale
    local step = 1
    while step < targetDesignStep do
        step = step * 2
    end
    return step
end

local function normalizeArgbNumber(v)
    local n = math.floor((tonumber(v) or 0) + 0.5)
    if n < 0 then
        n = n + 4294967296
    end
    if n < 0 then
        n = 0
    end
    if n > 4294967295 then
        n = 4294967295
    end
    return n
end

local function argbToRgba(v)
    local n = normalizeArgbNumber(v)
    local a = math.floor(n / 16777216) % 256
    local r = math.floor(n / 65536) % 256
    local g = math.floor(n / 256) % 256
    local b = n % 256
    return r, g, b, a
end

local function rgbaToArgb(r, g, b, a)
    local rr = clamp(math.floor((tonumber(r) or 0) + 0.5), 0, 255)
    local gg = clamp(math.floor((tonumber(g) or 0) + 0.5), 0, 255)
    local bb = clamp(math.floor((tonumber(b) or 0) + 0.5), 0, 255)
    local aa = clamp(math.floor((tonumber(a) or 255) + 0.5), 0, 255)
    return aa * 16777216 + rr * 65536 + gg * 256 + bb
end

local function shouldSkipFallbackConfigKey(keyText)
    local k = string.lower(keyText or "")
    if k == "" then
        return true
    end
    if string.sub(k, 1, 1) == "_" then
        return true
    end
    if string.sub(k, 1, 3) == "on_" then
        return true
    end
    if k == "rootnode" or k == "callbacks" or k == "schema" then
        return true
    end
    return false
end

local function deepCopyTable(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[deepCopyTable(k, seen)] = deepCopyTable(v, seen)
    end
    return out
end

local function deepEqual(a, b, visited)
    if a == b then
        return true
    end
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return false
    end

    visited = visited or {}
    local mapA = visited[a]
    if mapA and mapA[b] then
        return true
    end
    if mapA == nil then
        mapA = {}
        visited[a] = mapA
    end
    mapA[b] = true

    for k, v in pairs(a) do
        if not deepEqual(v, b[k], visited) then
            return false
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function collectConfigLeaves(tbl, prefix, out, visited)
    if type(tbl) ~= "table" then
        return
    end
    visited = visited or {}
    if visited[tbl] then
        return
    end
    visited[tbl] = true

    local keys = {}
    for k, _ in pairs(tbl) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for i = 1, #keys do
        local k = keys[i]
        local v = tbl[k]
        local t = type(v)
        local keyText = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
        if t == "table" then
            collectConfigLeaves(v, keyText, out, visited)
        elseif t == "number" or t == "string" or t == "boolean" then
            out[#out + 1] = { path = keyText, value = v }
        end
    end
end

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

    local settingsOpen = false
    local scriptOverlay = nil

    shell.settingsButton = W.Button.new(shell.panel.node, "sharedSettings", {
        label = "Settings",
        bg = 0xff1e293b,
        fontSize = 13.0,
        on_click = function()
            settingsOpen = not settingsOpen
            if not settingsOpen then
                if scriptOverlay then
                    scriptOverlay:setBounds(0, 0, 0, 0)
                end
                return
            end

            local currentPath = getCurrentScriptPath()
            local scripts = getVisibleUiScripts(currentPath)
            if scriptOverlay == nil then
                scriptOverlay = shell.parentNode:addChild("sharedScriptOverlay")
            end

            local itemH = 28
            local headerH = 26
            local overlayH = math.min(320, headerH + #scripts * itemH + 8)
            local overlayW = 240
            local btnX, btnY = shell.settingsButton.node:getBounds()
            local panelX, panelY = shell.panel.node:getBounds()

            scriptOverlay:setBounds(panelX + btnX - overlayW + 84, panelY + btnY + 32, overlayW, overlayH)
            scriptOverlay:setInterceptsMouse(true, true)
            scriptOverlay:toFront(false)

            scriptOverlay:setOnDraw(function(self)
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

            scriptOverlay:setOnMouseDown(function(mx, my)
                if my < headerH then
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)
                    return
                end

                local idx = math.floor((my - headerH) / itemH) + 1
                if idx >= 1 and idx <= #scripts then
                    local target = scripts[idx].path
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)

                    if target ~= currentPath then
                        if type(shell.onBeforeSwitch) == "function" then
                            shell.onBeforeSwitch(target, currentPath)
                        end
                        shell:stashRestoreStateForScriptSwitch()
                        switchUiScript(target)
                    end
                else
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)
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

    shell.zoomLabel = W.Label.new(shell.panel.node, "zoomLabel", {
        text = "100%",
        colour = 0xff94a3b8,
        fontSize = 10.0,
        justification = Justify.centred,
    })

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
    end

    function shell:setConsoleVisible(visible)
        local c = self.console
        local nextVisible = visible == true
        if c.visible == nextVisible then
            return
        end

        c.visible = nextVisible
        if c.visible then
            local w = self.parentNode:getWidth()
            local h = self.parentNode:getHeight()
            self:layout(w, h)
            self.consoleOverlay:setInterceptsMouse(true, true)
            self.consoleOverlay:toFront(false)
            self.consoleOverlay:grabKeyboardFocus()
            self.consoleOverlay:repaint()
        else
            self.consoleOverlay:setInterceptsMouse(false, false)
            self.consoleOverlay:setBounds(0, 0, 0, 0)
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
        self.consoleOverlay:toFront(false)
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
            self:appendConsoleLine("undo | redo | sel | copyid | dev [status|on|off|toggle] | ui <scriptPath> | lua <expr>")
            return
        elseif cmd == "clear" then
            self.console.lines = {}
            self.console.scrollOffset = 0
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
            self:copyActiveDebugIdentifier()
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

        if k == 27 then
            self:setConsoleVisible(false)
            return true
        end

        if ctrl and seIsLetterShortcut(k, ch, "v") and getClipboardText then
            c.input = c.input .. tostring(getClipboardText() or "")
            self.consoleOverlay:repaint()
            return true
        end

        if k == 13 or k == 10 then
            local line = c.input
            c.input = ""
            self:executeConsoleCommand(line)
            self.consoleOverlay:repaint()
            return true
        end

        if k == 8 then
            c.input = string.sub(c.input or "", 1, math.max(0, #(c.input or "") - 1))
            self.consoleOverlay:repaint()
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
                self.consoleOverlay:repaint()
            end
            return true
        elseif isDown then
            local count = #c.history
            if count > 0 and c.historyIndex > 0 then
                c.historyIndex = math.min(count, c.historyIndex + 1)
                c.input = c.history[c.historyIndex] or ""
                self.consoleOverlay:repaint()
            end
            return true
        elseif isPageUp then
            c.scrollOffset = math.min(#c.lines, (c.scrollOffset or 0) + 6)
            self.consoleOverlay:repaint()
            return true
        elseif isPageDown then
            c.scrollOffset = math.max(0, (c.scrollOffset or 0) - 6)
            self.consoleOverlay:repaint()
            return true
        end

        if ch >= 32 and ch <= 126 then
            c.input = (c.input or "") .. string.char(ch)
            self.consoleOverlay:repaint()
            return true
        elseif k >= 32 and k <= 126 then
            c.input = (c.input or "") .. string.char(k)
            self.consoleOverlay:repaint()
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
        self.scriptRows = {}

        local currentUi = getCurrentScriptPath and getCurrentScriptPath() or ""
        local editingPath = self.scriptEditor and self.scriptEditor.path or ""

        self.scriptRows[#self.scriptRows + 1] = { section = true, label = "UI Scripts" }
        local uiScripts = listUiScripts and listUiScripts() or {}
        local uiCount = 0

        for i = 1, #uiScripts do
            local s = uiScripts[i]
            if type(s) == "table" then
                local path = s.path or ""
                local name = s.name or fileStem(path) or "(unnamed)"
                local include = false

                if not scriptLooksSettings(name, path) then
                    if path ~= "" and (path == currentUi or path == editingPath) then
                        include = true
                    elseif scriptLooksGlobal(name, path) then
                        include = true
                    end
                end

                if include then
                    self.scriptRows[#self.scriptRows + 1] = {
                        kind = "ui",
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
                    local isDemo = scriptLooksDemo(name, path)
                    if path ~= "" and path == editingPath then
                        include = true
                    elseif (not isDemo) and scriptLooksGlobal(name, path) then
                        include = true
                    elseif (not isDemo) and contextMatch and slotMatch then
                        include = true
                    elseif (not isDemo) and currentUi ~= "" and contextMatch then
                        include = true
                    elseif (not isDemo) and currentUi == "" and slotMatch then
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
    end

    function shell:refreshScriptInspectorData(row)
        local si = self.scriptInspector
        if type(row) ~= "table" or row.section or row.nonInteractive then
            si.kind = ""
            si.name = ""
            si.path = ""
            si.text = ""
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
            return
        end

        local text = ""
        if readTextFile and type(row.path) == "string" and row.path ~= "" then
            text = readTextFile(row.path) or ""
        end

        si.kind = row.kind or ""
        si.name = row.name or fileStem(row.path or "")
        si.path = row.path or ""
        si.text = text
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
    end

    function shell:refreshScriptInspectorRuntimeParams()
        local si = self.scriptInspector
        if type(si) ~= "table" or si.kind ~= "dsp" then
            return
        end
        if type(self.selectedScriptRow) ~= "table" then
            si.runtimeParams = {}
            self.runtimeParamsLastRefreshAt = nowSeconds()
            return
        end
        si.runtimeParams = collectRuntimeParamsForScript(self.selectedScriptRow, self.stateParamsCache, si.params, self.dspPreviewSlotName)
        self.runtimeParamsLastRefreshAt = nowSeconds()
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
                    c.minus.node:setBounds(0, 0, 0, 0)
                end
                if c.slider and c.slider.node then
                    c.slider:setEnabled(false)
                    c.slider.node:setBounds(0, 0, 0, 0)
                end
                if c.plus and c.plus.node then
                    c.plus:setEnabled(false)
                    c.plus.node:setBounds(0, 0, 0, 0)
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
        self.inspectorCanvas:repaint()
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
        local previousActive = self.activeMainTabId
        local currentUiPath = getCurrentScriptPath and getCurrentScriptPath() or ""
        local uiScripts = listUiScripts and listUiScripts() or {}

        local nextTabs = {}
        local seenUiIds = {}

        for i = 1, #uiScripts do
            local s = uiScripts[i]
            if type(s) == "table" and type(s.path) == "string" and s.path ~= "" then
                local tabId = "ui:" .. s.path
                if not seenUiIds[tabId] then
                    seenUiIds[tabId] = true
                    nextTabs[#nextTabs + 1] = {
                        id = tabId,
                        title = (s.name and s.name ~= "") and s.name or fileStem(s.path),
                        kind = "ui-script",
                        path = s.path,
                    }
                end
            end
        end

        if #nextTabs == 0 and currentUiPath ~= "" then
            nextTabs[#nextTabs + 1] = {
                id = "ui:" .. currentUiPath,
                title = fileStem(currentUiPath),
                kind = "ui-script",
                path = currentUiPath,
            }
        end

        self.mainTabs = nextTabs

        local foundPrev = false
        for i = 1, #self.mainTabs do
            if self.mainTabs[i].id == previousActive then
                foundPrev = true
                break
            end
        end

        if foundPrev then
            self.activeMainTabId = previousActive
            return
        end

        local currentId = "ui:" .. currentUiPath
        for i = 1, #self.mainTabs do
            if self.mainTabs[i].id == currentId then
                self.activeMainTabId = currentId
                return
            end
        end

        self.activeMainTabId = (#self.mainTabs > 0) and self.mainTabs[1].id or ""
    end

    function shell:activateMainTab(tabId)
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
    end

    function shell:ensureScriptEditorCursorVisible()
        local ed = self.scriptEditor
        local h = math.floor(self.mainTabContent:getHeight())
        local lines = seBuildLines(ed.text)
        local visible = seVisibleLineCount(h)
        local line = seLineColFromPos(ed.text, ed.cursorPos)
        local maxScroll = math.max(1, #lines - visible + 1)

        if line < ed.scrollRow then
            ed.scrollRow = line
        elseif line >= ed.scrollRow + visible then
            ed.scrollRow = line - visible + 1
        end

        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)
    end

    function shell:scriptEditorPosFromPoint(mx, my)
        local ed = self.scriptEditor
        local w = math.floor(self.mainTabContent:getWidth())
        local h = math.floor(self.mainTabContent:getHeight())
        local lines = seBuildLines(ed.text)
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
        return sePosFromLineCol(ed.text, lineIdx, col)
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
        self.scriptEditor.name = row.name or fileStem(path)
        self:refreshScriptInspectorData(row)
        self.scriptEditor.path = path
        self.scriptEditor.text = text
        self.scriptEditor.cursorPos = 1
        self.scriptEditor.selectionAnchor = nil
        self.scriptEditor.dragAnchorPos = nil
        self.scriptEditor.scrollRow = 1
        self.scriptEditor.focused = false
        self.scriptEditor.status = "Loaded " .. (self.scriptEditor.name or fileStem(path))
        self.scriptEditor.lastClickTime = 0
        self.scriptEditor.lastClickLine = -1
        self.scriptEditor.clickStreak = 0
        self.scriptEditor.dirty = false

        self.editContentMode = "script"

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
        self.mainTabContent:grabKeyboardFocus()
        self.scriptEditor.focused = true
        self.mainTabContent:repaint()
    end

    function shell:saveScriptEditor()
        local ed = self.scriptEditor
        if not ed or ed.path == "" then
            return
        end

        if writeTextFile then
            local ok = writeTextFile(ed.path, ed.text)
            if ok == false then
                ed.status = "Save failed"
                return
            end
            ed.dirty = false
            ed.status = "Saved " .. (ed.name or fileStem(ed.path))
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
            ed.cursorPos = 1
            ed.selectionAnchor = nil
            ed.dragAnchorPos = nil
            ed.scrollRow = 1
            ed.dirty = false
            ed.status = "Reloaded from disk"
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
        self.mainTabContent:repaint()

        local w = self.parentNode:getWidth()
        local h = self.parentNode:getHeight()
        self:layout(w, h)
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

    function shell:registerPerformanceView(view)
        self.performanceView = view

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

    function shell:getSelectionBounds()
        if #self.selectedWidgets == 0 then
            return nil
        end

        local minX, minY, maxX, maxY = nil, nil, nil, nil
        for i = 1, #self.selectedWidgets do
            local row = self:_findTreeRowByCanvas(self.selectedWidgets[i])
            if row then
                minX = (minX == nil) and row.x or math.min(minX, row.x)
                minY = (minY == nil) and row.y or math.min(minY, row.y)
                maxX = (maxX == nil) and (row.x + row.w) or math.max(maxX, row.x + row.w)
                maxY = (maxY == nil) and (row.y + row.h) or math.max(maxY, row.y + row.h)
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

    function shell:updateSelectedRowBoundsCache()
        -- For nested widgets, absolute coordinates depend on parent chain.
        -- Rebuild tree so selection overlay stays correct.
        self:refreshTree(true)
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
                    changed = true
                end
            end
        end

        if not changed then
            return
        end

        self:refreshTree(true)
        self:setSelection(selectionCopy, primary)

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
            return
        end

        if selCount == 1 then
            local canvas = self.selectedWidgets[1]
            local meta = canvas:getUserData("_editorMeta")
            local nodeType = (type(meta) == "table" and type(meta.type) == "string") and meta.type or "Canvas"
            local nodeName = deriveNodeName(meta, nodeType)

            self.inspectorRows[#self.inspectorRows + 1] = { key = "Type", value = nodeType }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Name", value = nodeName }

            local bx, by, bw, bh = canvas:getBounds()
            local dx, dy = self:localToDesign(bx, by)
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.x", value = valueToText(dx) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.y", value = valueToText(dy) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.w", value = valueToText(bw) }
            self.inspectorRows[#self.inspectorRows + 1] = { key = "Bounds.h", value = valueToText(bh) }

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
            local bx, by, bw, bh = self.selectedWidgets[1]:getBounds()
            local dx, dy = self:localToDesign(bx, by)
            self.inspectorX:setValue(dx)
            self.inspectorY:setValue(dy)
            self.inspectorW:setValue(math.max(1, bw))
            self.inspectorH:setValue(math.max(1, bh))
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

        local beforeScene = self:_captureSceneState()
        local beforeSelection = self:_captureSelectionState()

        local iv = math.floor((value or 0) + 0.5)

        if selCount == 1 then
            local target = self.selectedWidgets[1]
            local bx, by, bw, bh = target:getBounds()

            if axis == "x" then
                bx = iv - self.viewportDesignX
            elseif axis == "y" then
                by = iv - self.viewportDesignY
            elseif axis == "w" then
                bw = math.max(1, iv)
            elseif axis == "h" then
                bh = math.max(1, iv)
            end

            target:setBounds(bx, by, bw, bh)
            self.treeRefreshPending = true
            self:refreshTree(true)

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
                        local localNX = nx - self.viewportDesignX
                        local nw = math.max(self.minWidgetSize, bw * scale)
                        c:setBounds(math.floor(localNX + 0.5), by, math.floor(nw + 0.5), bh)
                    else
                        local relY = row.y - bounds.y
                        local ny = bounds.y + relY * scale
                        local localNY = ny - self.viewportDesignY
                        local nh = math.max(self.minWidgetSize, bh * scale)
                        c:setBounds(bx, math.floor(localNY + 0.5), bw, math.floor(nh + 0.5))
                    end
                end
            end
        end

        self.treeRefreshPending = true
        self:refreshTree(true)

        local afterScene = self:_captureSceneState()
        local afterSelection = self:_captureSelectionState()
        self:recordHistory("bounds", beforeScene, beforeSelection, afterScene, afterSelection)
    end

    function shell:selectWidget(canvas, recordHistory)
        if canvas ~= nil and not self:_isWidgetInTree(canvas) then
            return
        end

        if canvas == nil then
            self:setSelection({}, nil, recordHistory)
        else
            self:setSelection({ canvas }, canvas, recordHistory)
        end
    end

    function shell:refreshTree(force)
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
            return
        end

        self.treeLastRefreshAt = now
        self.treeRefreshPending = false

        self.treeRows = {}
        if self.content ~= nil then
            local rootOffsetX = (self.mode == "edit") and self.viewportDesignX or 0
            local rootOffsetY = (self.mode == "edit") and self.viewportDesignY or 0
            self.treeRoot = walkHierarchy(self.content, 0, self.treeRows, rootOffsetX, rootOffsetY, "", 0)
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
    end

    shell.treeCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

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
        shell.treeCanvas:grabKeyboardFocus()
        local row = math.floor((my + shell.treeScrollY) / shell.treeRowHeight) + 1
        if row >= 1 and row <= #shell.treeRows then
            shell:selectWidget(shell.treeRows[row].canvas)
        end
    end)

    shell.treeCanvas:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.treeCanvas:setOnMouseWheel(function(mx, my, deltaY)
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

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

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
                    gfx.drawText(row.name or "", 12, rowY, w - 24, rowH, Justify.centredLeft)
                end
            end
        end
    end)

    shell.scriptCanvas:setOnMouseDown(function(mx, my)
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
        if shell:handleGlobalDevHotkeys(keyCode, charCode, shift, ctrl, alt) then
            return true
        end
        return false
    end)

    shell.scriptCanvas:setOnMouseWheel(function(mx, my, deltaY)
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
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("Preview mode", 10, 8, w - 20, 18, Justify.centredLeft)
            return
        end

        local ed = shell.scriptEditor
        shell.scriptEditorButtonRects = {}

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
        gfx.drawText(ed.path or "", 10, 18, math.max(40, w - 230), 12, Justify.centredLeft)

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

        gfx.setColour(0xff0b1220)
        gfx.fillRect(0, SCRIPT_EDITOR_STYLE.headerH, w, h - SCRIPT_EDITOR_STYLE.headerH)

        gfx.setColour(0xff101a2e)
        gfx.fillRect(0, SCRIPT_EDITOR_STYLE.headerH, gutterW + pad, h - SCRIPT_EDITOR_STYLE.headerH - statusH)
        gfx.setColour(0xff25354d)
        gfx.drawVerticalLine(gutterW + pad, SCRIPT_EDITOR_STYLE.headerH + pad, h - statusH - pad)

        local lines, starts = seBuildLines(ed.text)
        local visible = seVisibleLineCount(h)
        local maxScroll = math.max(1, #lines - visible + 1)
        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)

        local cursorLine, cursorCol = seLineColFromPos(ed.text, ed.cursorPos)
        local selStart, selEnd = seGetSelectionRange(ed)
        local maxCols = seMaxCols(w)

        for i = 0, visible - 1 do
            local lineIdx = ed.scrollRow + i
            local lineText = lines[lineIdx]
            local lineStart = starts[lineIdx]
            if lineText == nil or lineStart == nil then
                break
            end

            local y = textTop + i * lineH
            if y + lineH > h - statusH then
                break
            end

            if lineIdx == cursorLine then
                gfx.setColour(0x203b82f6)
                gfx.fillRect(textX - 2, y, w - textX - pad + 2, lineH)
            end

            if selStart ~= nil and selEnd ~= nil then
                local lineEndExclusive = lineStart + #lineText
                local overlapStart = math.max(selStart, lineStart)
                local overlapEnd = math.min(selEnd, lineEndExclusive)
                if overlapEnd > overlapStart then
                    local selColStart = overlapStart - lineStart + 1
                    local selColEnd = overlapEnd - lineStart + 1
                    local sx = math.floor(textX + (selColStart - 1) * SCRIPT_EDITOR_STYLE.charW + 0.5)
                    local sw = math.max(1, math.floor((selColEnd - selColStart) * SCRIPT_EDITOR_STYLE.charW + 0.5))
                    gfx.setColour(0x705892f0)
                    gfx.fillRect(sx, y, sw, lineH)
                end
            end

            gfx.setColour(0xff64748b)
            gfx.setFont(SCRIPT_EDITOR_STYLE.fontName, 11.0, FontStyle.plain)
            gfx.drawText(tostring(lineIdx), 4, y, gutterW - 6, lineH, Justify.centredRight)

            local display = lineText
            if #display > maxCols then
                display = string.sub(display, 1, maxCols)
            end

            local spans = seTokenizeLuaLineCached(display)
            local cx = textX
            gfx.setFont(SCRIPT_EDITOR_STYLE.fontName, SCRIPT_EDITOR_STYLE.fontSize, FontStyle.plain)
            for s = 1, #spans do
                local span = spans[s]
                local text = span.text or ""
                local spanLen = #text
                if spanLen > 0 then
                    local drawTextValue = string.gsub(text, "\t", " ")
                    local drawW = math.max(1, math.floor(spanLen * SCRIPT_EDITOR_STYLE.charW + 2))
                    gfx.setColour(span.colour or SCRIPT_SYNTAX_COLOUR.text)
                    gfx.drawText(drawTextValue, math.floor(cx + 0.5), y, drawW, lineH, Justify.centredLeft)
                    cx = cx + spanLen * SCRIPT_EDITOR_STYLE.charW
                end
            end
        end

        if ed.focused then
            local blinkOn = (math.floor(nowSeconds() * 2) % 2) == 0
            if blinkOn and cursorLine >= ed.scrollRow and cursorLine < ed.scrollRow + visible then
                local caretCol = clamp(cursorCol, 1, maxCols + 1)
                local cx = math.floor(textX + (caretCol - 1) * SCRIPT_EDITOR_STYLE.charW + 0.5)
                local cy = textTop + (cursorLine - ed.scrollRow) * lineH
                gfx.setColour(0xff7dd3fc)
                gfx.drawLine(cx, cy + 2, cx, cy + lineH - 2)
            end
        end

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, h - statusH, w, statusH)
        gfx.setColour(0xff22324b)
        gfx.drawHorizontalLine(h - statusH, 0, w)
        gfx.setColour(0xff94a3b8)
        gfx.setFont(SCRIPT_EDITOR_STYLE.fontName, 10.0, FontStyle.plain)
        local statusText = string.format("Ln %d Col %d | %s | Ctrl+S Save | Ctrl+R Reload | Ctrl+W Close", cursorLine, cursorCol, ed.status or "")
        gfx.drawText(statusText, 8, h - statusH, w - 16, statusH, Justify.centredLeft)
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
        shell.scriptEditor.dragAnchorPos = nil
    end)

    shell.mainTabContent:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my
        if shell.mode ~= "edit" or shell.editContentMode ~= "script" then
            return
        end

        local ed = shell.scriptEditor
        local lines = seBuildLines(ed.text)
        local visible = seVisibleLineCount(math.floor(shell.mainTabContent:getHeight()))
        local maxScroll = math.max(1, #lines - visible + 1)
        if deltaY > 0 then
            ed.scrollRow = ed.scrollRow - 2
        elseif deltaY < 0 then
            ed.scrollRow = ed.scrollRow + 2
        end
        ed.scrollRow = clamp(ed.scrollRow, 1, maxScroll)
        shell.mainTabContent:repaint()
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
            return false
        end

        local ed = shell.scriptEditor
        local handled = false
        local mutated = false

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
                end
                handled = true
                mutated = true
            elseif isDelete then
                if not seDeleteSelection(ed) and ed.cursorPos <= #(ed.text or "") then
                    local src = ed.text or ""
                    ed.text = string.sub(src, 1, ed.cursorPos - 1) .. string.sub(src, ed.cursorPos + 1)
                    seClearSelection(ed)
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
                local line, col = seLineColFromPos(ed.text, ed.cursorPos)
                seMoveCursor(ed, sePosFromLineCol(ed.text, line - 1, col), shift)
                handled = true
            elseif isDown then
                local line, col = seLineColFromPos(ed.text, ed.cursorPos)
                seMoveCursor(ed, sePosFromLineCol(ed.text, line + 1, col), shift)
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
            return true
        end

        return false
    end)

    shell.inspectorCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        gfx.setColour(0xff0f172a)
        gfx.fillRect(0, 0, w, h)

        if shell.leftPanelMode ~= "scripts" then
            shell:hideRuntimeParamControls(1)
        end

        if shell.leftPanelMode == "scripts" then
            local si = shell.scriptInspector
            local y = 6

            si.editorHeaderRect = nil
            si.editorBodyRect = nil
            si.graphHeaderRect = nil
            si.graphBodyRect = nil
            si.runButtonRect = nil
            si.stopButtonRect = nil
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

                local btnY = y
                local btnW = math.floor((w - 24) * 0.5)
                local btnH = 18
                si.runButtonRect = { x = 8, y = btnY, w = btnW, h = btnH }
                si.stopButtonRect = { x = 12 + btnW, y = btnY, w = btnW, h = btnH }

                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(si.runButtonRect.x, si.runButtonRect.y, si.runButtonRect.w, si.runButtonRect.h, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(si.runButtonRect.x, si.runButtonRect.y, si.runButtonRect.w, si.runButtonRect.h, 4, 1)
                gfx.setColour(0xffcbd5e1)
                gfx.setFont(9.0)
                gfx.drawText("Run in Preview Slot", si.runButtonRect.x + 4, si.runButtonRect.y, si.runButtonRect.w - 8, si.runButtonRect.h, Justify.centred)

                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(si.stopButtonRect.x, si.stopButtonRect.y, si.stopButtonRect.w, si.stopButtonRect.h, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(si.stopButtonRect.x, si.stopButtonRect.y, si.stopButtonRect.w, si.stopButtonRect.h, 4, 1)
                gfx.setColour(0xffcbd5e1)
                gfx.drawText("Stop Preview Slot", si.stopButtonRect.x + 4, si.stopButtonRect.y, si.stopButtonRect.w - 8, si.stopButtonRect.h, Justify.centred)

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

            local headerH = 20
            local function drawSectionHeader(text, collapsed, yy)
                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(6, yy, w - 12, headerH, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(6, yy, w - 12, headerH, 4, 1)
                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                local marker = collapsed and "[+] " or "[-] "
                gfx.drawText(marker .. text, 12, yy, w - 24, headerH, Justify.centredLeft)
                return { x = 6, y = yy, w = w - 12, h = headerH }
            end

            si.editorHeaderRect = drawSectionHeader("Inline Script", si.editorCollapsed, y)
            y = y + headerH + 4

            if not si.editorCollapsed then
                local bodyH = math.max(80, math.min(180, h - y - ((si.kind == "dsp") and 150 or 40)))
                si.editorBodyRect = { x = 6, y = y, w = w - 12, h = bodyH }

                gfx.setColour(0xff0b1220)
                gfx.fillRoundedRect(si.editorBodyRect.x, si.editorBodyRect.y, si.editorBodyRect.w, si.editorBodyRect.h, 4)
                gfx.setColour(0xff334155)
                gfx.drawRoundedRect(si.editorBodyRect.x, si.editorBodyRect.y, si.editorBodyRect.w, si.editorBodyRect.h, 4, 1)

                local lines = seBuildLines(si.text)
                local lineH = 14
                local visible = math.max(1, math.floor((bodyH - 8) / lineH))
                local maxScroll = math.max(1, #lines - visible + 1)
                si.editorScrollRow = clamp(si.editorScrollRow or 1, 1, maxScroll)

                for i = 0, visible - 1 do
                    local idx = si.editorScrollRow + i
                    local line = lines[idx]
                    if line == nil then
                        break
                    end
                    local ly = y + 4 + i * lineH
                    gfx.setColour(0xff475569)
                    gfx.setFont(9.0)
                    gfx.drawText(tostring(idx), 10, ly, 26, lineH, Justify.centredRight)

                    local text = line
                    if #text > 200 then
                        text = text:sub(1, 200)
                    end

                    local spans = seTokenizeLuaLineCached(text)
                    local tx = 40
                    gfx.setFont(SCRIPT_EDITOR_STYLE.fontName, 10.0, FontStyle.plain)
                    for s = 1, #spans do
                        local span = spans[s]
                        local st = span.text or ""
                        local sl = #st
                        if sl > 0 then
                            local remaining = (w - 16) - tx
                            if remaining <= 0 then
                                break
                            end

                            local maxChars = math.max(0, math.floor(remaining / 7))
                            if maxChars <= 0 then
                                break
                            end

                            local drawTextValue = st
                            if sl > maxChars then
                                drawTextValue = string.sub(st, 1, maxChars)
                                sl = #drawTextValue
                            end

                            drawTextValue = string.gsub(drawTextValue, "\t", " ")
                            gfx.setColour(span.colour or SCRIPT_SYNTAX_COLOUR.text)
                            gfx.drawText(drawTextValue, tx, ly, math.max(1, sl * 7 + 2), lineH, Justify.centredLeft)
                            tx = tx + sl * 7

                            if sl < #st then
                                break
                            end
                        end
                    end
                end

                y = y + bodyH + 6
            end

            if si.kind == "dsp" then
                si.graphHeaderRect = drawSectionHeader("DSP Graph (drag to pan)", si.graphCollapsed, y)
                y = y + headerH + 4

                if not si.graphCollapsed then
                    local bodyH = math.max(90, h - y - 8)
                    si.graphBodyRect = { x = 6, y = y, w = w - 12, h = bodyH }

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
                si.editorCollapsed = not si.editorCollapsed
                shell.inspectorCanvas:repaint()
                return
            end
            if pointInRect(mx, my, si.graphHeaderRect) then
                si.graphCollapsed = not si.graphCollapsed
                shell.inspectorCanvas:repaint()
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
        if shell.leftPanelMode ~= "scripts" then
            return
        end

        local si = shell.scriptInspector
        si.graphDragging = false
    end)

    shell.inspectorCanvas:setOnMouseWheel(function(mx, my, deltaY)
        if shell.leftPanelMode == "scripts" then
            local si = shell.scriptInspector
            if pointInRect(mx, my, si.editorBodyRect) then
                local lines = seBuildLines(si.text)
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
            return
        end

        shell:selectWidget(hit)
    end)

    shell.previewOverlay:setOnMouseDrag(function(mx, my, dx, dy, shift, ctrl, alt)
        if shell.mode ~= "edit" or shell.dragState == nil then
            return
        end

        local ds = shell.dragState

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
                        local localNX = nx - shell.viewportDesignX
                        local localNY = ny - shell.viewportDesignY
                        local nw = math.max(shell.minWidgetSize, t.w * scaleX)
                        local nh = math.max(shell.minWidgetSize, t.h * scaleY)
                        t.canvas:setBounds(math.floor(localNX + 0.5), math.floor(localNY + 0.5), math.floor(nw + 0.5), math.floor(nh + 0.5))
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

        local ds = shell.dragState
        shell.dragState = nil

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
            shell:refreshTree(true)
            local afterScene = shell:_captureSceneState()
            local afterSelection = shell:_captureSelectionState()
            shell:recordHistory(ds.mode, ds.historyBeforeScene, ds.historyBeforeSelection, afterScene, afterSelection)
            return
        end

        shell.previewOverlay:repaint()
    end)

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
        settingsOpen = false
        if scriptOverlay then
            scriptOverlay:setBounds(0, 0, 0, 0)
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

        -- Runtime viewport (performance dimensions)
        local viewportDesignW = contentW
        local viewportDesignH = contentH

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
            self.zoomLabel:setBounds(0, 0, 0, 0)

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
            self.designH = activeViewportH
            self.viewportDesignX = 0
            self.viewportDesignY = 0
            self.viewportDesignW = viewportDesignW
            self.viewportDesignH = activeViewportH
            self.dragState = nil

            -- Content fills the area at full size
            if self.content then
                self.content:setBounds(0, math.floor(perfBodyY), math.floor(viewportDesignW), math.floor(activeViewportH))
                self.content:clearTransform()
            end

            if self.performanceView and type(self.performanceView.resized) == "function" then
                self.performanceView.resized(0, 0, math.floor(viewportDesignW), math.floor(activeViewportH))
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

            -- Content: show live preview only when edit center is in preview mode.
            if self.content then
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

            -- Bring panels to front so they're above the (oversized) content bounds
            self.treePanel.node:toFront(false)
            self.inspectorPanel.node:toFront(false)
            self.mainTabContent:toFront(false)
            self.mainTabBar:toFront(false)
            self.previewOverlay:toFront(false)
            if settingsOpen and scriptOverlay then
                scriptOverlay:toFront(false)
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
        if settingsOpen and scriptOverlay then
            scriptOverlay:toFront(false)
        end
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

        -- Performance mode: full content area
        return self.pad, contentY, contentW, contentH
    end

    shell:publishUiStateToGlobals()

    function shell:updateFromState(state)
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

        if settingsOpen and scriptOverlay then
            scriptOverlay:toFront(false)
        end

        if self.mode == "edit" then
            self.treeRefreshPending = true
            self:refreshTree(false)
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

    return shell
end

return Shell

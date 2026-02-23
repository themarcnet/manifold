-- looper_ui.lua
-- Looper plugin UI, built entirely with Lua Canvas widgets.
-- Mirrors the existing C++ LooperEditor layout and controls.

local W = require("looper_widgets")

-- ============================================================================
-- Shared state
-- ============================================================================
local current_state = {}
local MAX_LAYERS = 4

-- All widgets stored here for update access
local ui = {}

-- Stepped value helpers (mirror C++ logic)
local kSpeeds = {0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0}
local kVolumes = {0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0}

local function steppedValue(current, steps, direction)
    local nearest = 1
    local nearestDist = math.abs(current - steps[1])
    for i = 2, #steps do
        local d = math.abs(current - steps[i])
        if d < nearestDist then
            nearest = i
            nearestDist = d
        end
    end
    local next = math.max(1, math.min(#steps, nearest + direction))
    return steps[next]
end

local function steppedTempo(current, direction)
    return math.max(40, math.min(240, current + 2 * direction))
end

local function steppedMasterVol(current, direction)
    return math.max(0, math.min(1, current + 0.05 * direction))
end

-- Record mode cycling
local kModeNames = {"First Loop", "Free Mode", "Traditional", "Retrospective"}
local kModeKeys  = {"firstLoop", "freeMode", "traditional", "retrospective"}

local function recordModeText(modeStr)
    for i, k in ipairs(kModeKeys) do
        if k == modeStr then return kModeNames[i] end
    end
    return "Mode"
end

local function layerStateText(layerState, lengthSamples, sampleRate)
    if layerState == "empty" then return "Empty" end
    if layerState == "recording" then return "Recording" end
    if layerState == "overdubbing" then return "Overdubbing" end
    if layerState == "muted" then return "Muted" end
    if layerState == "stopped" then return "Stopped" end
    if layerState == "playing" then
        local secs = lengthSamples / math.max(1, sampleRate)
        return string.format("Playing %.2f s", secs)
    end
    return "Unknown"
end

local function layerStateColour(layerState)
    if layerState == "empty"      then return 0xff64748b end
    if layerState == "playing"    then return 0xff34d399 end
    if layerState == "recording"  then return 0xffef4444 end
    if layerState == "overdubbing" then return 0xfff59e0b end
    if layerState == "muted"      then return 0xff94a3b8 end
    if layerState == "stopped"    then return 0xfffde047 end
    return 0xffffffff
end

-- Segment bar sizes
local kSegmentBars = {0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0}
local kSegmentLabels = {"1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16"}

-- ============================================================================
-- ui_init: Build the entire UI tree
-- ============================================================================

function ui_init(root)
    -- Title row
    ui.title = W.Label(root, "title", {
        text = "LOOPER [Lua]",
        colour = 0xff7dd3fc,
        fontSize = 29.0,
        fontName = "Avenir Next",
        fontStyle = FontStyle.bold,
        justification = Justify.centredLeft,
    })

    -- Settings / UI switcher button (⚙)
    local _settingsOpen = false
    local _scriptOverlay = nil

    ui.settingsBtn = W.Button(root, "settings_btn", {
        label = "⚙", bg = 0xff1e293b, fontSize = 18.0,
        on_click = function()
            _settingsOpen = not _settingsOpen
            if _settingsOpen then
                -- Populate overlay with available scripts
                local scripts = listUiScripts()
                local currentPath = getCurrentScriptPath()
                if _scriptOverlay then
                    _scriptOverlay:setOnDraw(nil)
                    _scriptOverlay:setOnMouseDown(nil)
                end
                if not _scriptOverlay then
                    _scriptOverlay = root:addChild("script_overlay")
                end

                local itemH = 30
                local overlayH = (#scripts + 1) * itemH + 8  -- +1 for header
                local overlayW = 260
                local btnX, btnY = ui.settingsBtn.node:getBounds()
                _scriptOverlay:setBounds(btnX + 44 - overlayW, btnY + 40, overlayW, overlayH)

                _scriptOverlay:setOnDraw(function(self)
                    local w = self:getWidth()
                    local h = self:getHeight()
                    -- Drop shadow
                    gfx.setColour(0x40000000)
                    gfx.fillRoundedRect(2, 2, w, h, 8)
                    -- Background
                    gfx.setColour(0xff1e293b)
                    gfx.fillRoundedRect(0, 0, w - 2, h - 2, 8)
                    gfx.setColour(0xff475569)
                    gfx.drawRoundedRect(0, 0, w - 2, h - 2, 8, 1)

                    -- Header
                    gfx.setColour(0xff94a3b8)
                    gfx.setFont("Avenir Next", 11.0, FontStyle.bold)
                    gfx.drawText("Switch UI Script", 12, 4, w - 24, itemH - 4, Justify.centredLeft)

                    -- Items
                    for i, s in ipairs(scripts) do
                        local y = itemH + (i - 1) * itemH
                        local isCurrent = (s.path == currentPath)
                        if isCurrent then
                            gfx.setColour(0xff334155)
                            gfx.fillRect(4, y, w - 10, itemH)
                        end
                        gfx.setColour(isCurrent and 0xff38bdf8 or 0xffe2e8f0)
                        gfx.setFont("Avenir Next", 12.0, FontStyle.plain)
                        gfx.drawText(s.name, 14, y, w - 28, itemH, Justify.centredLeft)
                        if isCurrent then
                            gfx.setColour(0xff38bdf8)
                            gfx.setFont(10.0)
                            gfx.drawText("●", w - 24, y, 12, itemH, Justify.centred)
                        end
                    end
                end)

                _scriptOverlay:setOnMouseDown(function(mx, my)
                    local scripts2 = listUiScripts()
                    local idx = math.floor((my - itemH) / itemH) + 1
                    if idx >= 1 and idx <= #scripts2 then
                        _settingsOpen = false
                        switchUiScript(scripts2[idx].path)
                    else
                        _settingsOpen = false
                        _scriptOverlay:setBounds(0, 0, 0, 0)
                    end
                end)
            else
                if _scriptOverlay then
                    _scriptOverlay:setBounds(0, 0, 0, 0)
                end
            end
        end,
    })

    -- Controls panel
    ui.controlsPanel = W.Panel(root, "controls", {
        bg = 0xff141a24, radius = 10,
    })

    local cp = ui.controlsPanel.node

    -- REC button
    ui.recBtn = W.Button(cp, "rec", {
        label = "REC", bg = 0xff7f1d1d,
        on_click = function()
            if current_state.isRecording then
                command("STOPREC")
            else
                command("REC")
            end
        end,
    })

    -- OVERDUB button
    ui.overdubBtn = W.Button(cp, "overdub", {
        label = "OVERDUB", bg = 0xff7c4a03,
        on_click = function()
            command("OVERDUB")
        end,
    })

    -- STOP button
    ui.stopBtn = W.Button(cp, "stop", {
        label = "STOP", bg = 0xff374151,
        on_click = function() command("STOP") end,
    })

    -- MODE button
    ui.modeBtn = W.Button(cp, "mode", {
        label = "Mode", bg = 0xff1f4a7a,
        on_click = function()
            local next = ((current_state.recordModeInt or 0) + 1) % 4
            command("MODE", tostring(next))
        end,
    })

    -- CLEAR button
    ui.clearBtn = W.Button(cp, "clear", {
        label = "CLEAR", bg = 0xff4b5563,
        on_click = function()
            command("LAYER", tostring(current_state.activeLayer or 0), "CLEAR")
        end,
    })

    -- CLEAR ALL button
    ui.clearAllBtn = W.Button(cp, "clearall", {
        label = "CLEAR ALL", bg = 0xff111827,
        on_click = function() command("CLEARALL") end,
    })

    -- TMP- button
    ui.tempoDownBtn = W.Button(cp, "tempo_down", {
        label = "TMP-", bg = 0xff2f3f56,
        on_click = function()
            command("TEMPO", tostring(steppedTempo(current_state.tempo or 120, -1)))
        end,
    })

    -- TMP+ button
    ui.tempoUpBtn = W.Button(cp, "tempo_up", {
        label = "TMP+", bg = 0xff2f3f56,
        on_click = function()
            command("TEMPO", tostring(steppedTempo(current_state.tempo or 120, 1)))
        end,
    })

    -- VOL- button
    ui.volDownBtn = W.Button(cp, "vol_down", {
        label = "VOL-", bg = 0xff423046,
        on_click = function()
            command("MASTERVOLUME", tostring(steppedMasterVol(current_state.masterVolume or 0.8, -1)))
        end,
    })

    -- VOL+ button
    ui.volUpBtn = W.Button(cp, "vol_up", {
        label = "VOL+", bg = 0xff423046,
        on_click = function()
            command("MASTERVOLUME", tostring(steppedMasterVol(current_state.masterVolume or 0.8, 1)))
        end,
    })

    ui.controlButtons = {
        ui.recBtn, ui.overdubBtn, ui.stopBtn, ui.modeBtn,
        ui.clearBtn, ui.clearAllBtn,
        ui.tempoDownBtn, ui.tempoUpBtn, ui.volDownBtn, ui.volUpBtn,
    }

    -- Capture plane
    ui.capturePanel = W.Panel(root, "capture", {
        bg = 0xff101723, radius = 10,
    })

    -- Capture plane title draws via custom onDraw on the panel node
    ui.capturePanel.node:setOnDraw(function(self)
        local w = self:getWidth()
        gfx.setColour(0xff9ca3af)
        gfx.setFont("Avenir Next", 13.0, FontStyle.plain)

        local caption = "Capture Plane (right = now, left = older)"
        if current_state.forwardArmed then
            caption = caption .. "  |  FORWARD ARMED " .. string.format("%.3f", current_state.forwardBars or 0) .. " bars"
        elseif current_state.recordMode == "traditional" then
            caption = caption .. "  |  Traditional mode: click segment to arm FORWARD"
        else
            caption = caption .. "  |  Click a segment to COMMIT"
        end
        gfx.drawText(caption, 10, 2, w - 20, 22, Justify.centredLeft)
    end)

    -- Segment strips (visual waveform placeholders)
    ui.captureStrips = {}
    for slot = 1, #kSegmentBars do
        local barsIndex = #kSegmentBars + 1 - slot
        local stripBars = kSegmentBars[barsIndex]
        local stripLabel = kSegmentLabels[barsIndex]

        local strip = ui.capturePanel.node:addChild("strip_" .. slot)
        strip:setInterceptsMouse(false, false)

        -- Closure-captured values
        local prevBars = (barsIndex > 1) and kSegmentBars[barsIndex - 1] or 0

        strip:setOnDraw(function(self)
            local w = self:getWidth()
            local h = self:getHeight()

            -- Background
            gfx.setColour(0xff0f1b2d)
            gfx.fillRect(0, 0, w, h)

            -- Center line
            gfx.setColour(0x22ffffff)
            gfx.drawHorizontalLine(math.floor(h / 2), 0, w)

            -- Waveform
            local spb = current_state.samplesPerBar or 88200
            local rangeStart = math.floor(prevBars * spb)
            local rangeEnd = math.floor(stripBars * spb)
            local captureSize = current_state.captureSize or 0
            local clippedStart = math.max(0, math.min(captureSize, rangeStart))
            local clippedEnd = math.max(0, math.min(captureSize, rangeEnd))

            if clippedEnd > clippedStart and w > 4 then
                local numBuckets = math.min(w - 4, 128)
                local peaks = getCapturePeaks(clippedStart, clippedEnd, numBuckets)
                if peaks and #peaks > 0 then
                    local centerY = h / 2
                    local gain = h * 0.45
                    gfx.setColour(0xff22d3ee)
                    for x = 1, #peaks do
                        local peak = peaks[x]
                        local ph = peak * gain
                        local px = 2 + (x - 1) * ((w - 4) / #peaks)
                        gfx.drawVerticalLine(math.floor(px), centerY - ph, centerY + ph)
                    end
                end
            end

            -- Cell border
            gfx.setColour(0x40475569)
            gfx.drawRect(0, 0, w, h)

            -- Label
            gfx.setColour(0xffcbd5e1)
            gfx.setFont("Avenir Next", 10.0, FontStyle.bold)
            gfx.drawText(stripLabel, 4, h - 16, w - 8, 14, Justify.bottomLeft)
        end)

        table.insert(ui.captureStrips, {node = strip})
    end

    -- Segment hit regions (click-to-commit, ordered shortest-first for z-order)
    ui.captureSegments = {}
    for i = #kSegmentBars, 1, -1 do
        local bars = kSegmentBars[i]
        local label = kSegmentLabels[i]
        local seg = ui.capturePanel.node:addChild("segment_hit_" .. i)

        seg:setOnClick(function()
            if current_state.recordMode == "traditional" then
                command("FORWARD", tostring(bars))
            else
                command("COMMIT", tostring(bars))
            end
        end)

        seg:setOnDraw(function(self)
            local w = self:getWidth()
            local h = self:getHeight()
            local hovered = self:isMouseOver()
            local armed = current_state.forwardArmed and
                          math.abs((current_state.forwardBars or 0) - bars) < 0.001

            if hovered then
                gfx.setColour(0x2a60a5fa)
                gfx.fillRect(0, 0, w, h)
                gfx.setColour(0xff60a5fa)
                gfx.drawRect(0, 0, w, h, 1)
            end

            if armed then
                gfx.setColour(0x3384cc16)
                gfx.fillRect(0, 0, w, h)
                gfx.setColour(0xff84cc16)
                gfx.drawRect(0, 0, w, h, 2)
            end

            if hovered or armed then
                local tc = armed and 0xffd9f99d or 0xffbfdbfe
                gfx.setColour(tc)
                gfx.setFont("Avenir Next", 12.0, FontStyle.bold)
                gfx.drawText(label .. " bars", 6, 0, w - 12, 20, Justify.topRight)
            end
        end)

        table.insert(ui.captureSegments, {node = seg, bars = bars, index = i})
    end

    -- Now indicator
    ui.nowIndicator = ui.capturePanel.node:addChild("now_indicator")
    ui.nowIndicator:setInterceptsMouse(false, false)
    ui.nowIndicator:setOnDraw(function(self)
        gfx.setColour(0xb3e2e8f0)
        gfx.drawVerticalLine(self:getWidth() - 1, 1, self:getHeight() - 1)
    end)

    -- Layers panel
    ui.layersPanel = W.Panel(root, "layers", {
        bg = 0xff0f1622, radius = 10,
    })

    ui.layerRows = {}
    for i = 0, MAX_LAYERS - 1 do
        local row = ui.layersPanel.node:addChild("layer_row_" .. i)
        local layerIdx = i  -- capture for closures

        -- Click row to select layer
        row:setOnClick(function()
            command("LAYER", tostring(layerIdx))
        end)

        -- Row draw: background, meta text, waveform placeholder
        row:setOnDraw(function(self)
            local w = self:getWidth()
            local h = self:getHeight()
            local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
            local active = (current_state.activeLayer or 0) == layerIdx

            -- Background
            local baseBg = active and 0xff25405f or 0xff1b2636
            if self:isMouseOver() then
                -- Brighten
                local a = (baseBg >> 24) & 0xff
                local r = math.min(255, ((baseBg >> 16) & 0xff) + 15)
                local g = math.min(255, ((baseBg >> 8) & 0xff) + 15)
                local b = math.min(255, (baseBg & 0xff) + 15)
                baseBg = (a << 24) | (r << 16) | (g << 8) | b
            end
            gfx.setColour(baseBg)
            gfx.fillRoundedRect(1, 1, w - 2, h - 2, 8)

            -- Border
            local borderCol = active and 0xff7dd3fc or 0xff334155
            gfx.setColour(borderCol)
            gfx.drawRoundedRect(1, 1, w - 2, h - 2, 8, 1)

            -- Layer label
            local textCol = active and 0xffe2e8f0 or 0xff94a3b8
            gfx.setColour(textCol)
            gfx.setFont("Avenir Next", 14.0, FontStyle.bold)
            gfx.drawText("L" .. layerIdx, 10, 6, 28, 18, Justify.centredLeft)

            -- State text
            local sr = current_state.sampleRate or 44100
            local stateText = layerStateText(layer.state or "empty", layer.length or 0, sr)
            gfx.setColour(layerStateColour(layer.state or "empty"))
            gfx.setFont("Avenir Next", 13.0, FontStyle.plain)
            gfx.drawText(stateText, 40, 6, 180, 18, Justify.centredLeft)

            -- Details text
            gfx.setColour(0xffcbd5e1)
            local details = string.format("speed %.2f%s | vol %.2f",
                layer.speed or 1.0,
                (layer.reversed and " | rev" or ""),
                layer.volume or 1.0)
            gfx.drawText(details, 220, 6, w - 560, 18, Justify.centredRight)

            -- Waveform area
            local wfX = 10
            local wfY = 26
            local wfW = w - 360
            local wfH = h - 34
            if wfW > 10 and wfH > 4 then
                -- Waveform background
                gfx.setColour(0xff0b1220)
                gfx.fillRoundedRect(wfX, wfY, wfW, wfH, 4)
                gfx.setColour(0x30475569)
                gfx.drawRoundedRect(wfX, wfY, wfW, wfH, 4, 1)

                -- Draw waveform peaks
                local length = layer.length or 0
                if length > 0 then
                    local numBuckets = math.min(wfW - 4, 200)
                    local peaks = getLayerPeaks(layerIdx, numBuckets)
                    if peaks and #peaks > 0 then
                        local wfCol = active and 0xff22d3ee or 0xff38bdf8
                        gfx.setColour(wfCol)
                        local centerY = wfY + wfH / 2
                        local gain = wfH * 0.43
                        for x = 1, #peaks do
                            local peak = peaks[x]
                            local ph = peak * gain
                            local px = wfX + 2 + (x - 1) * ((wfW - 4) / #peaks)
                            gfx.drawVerticalLine(math.floor(px), centerY - ph, centerY + ph)
                        end
                    end

                    -- Playhead
                    local lstate = layer.state or "empty"
                    if lstate == "playing" or lstate == "muted" or lstate == "overdubbing" then
                        local pos = (layer.position or 0) / length
                        local phX = wfX + math.floor(pos * wfW)
                        gfx.setColour(0xffff4d4d)
                        gfx.drawVerticalLine(phX, wfY + 1, wfY + wfH - 1)
                    end
                end
            end
        end)

        -- Per-layer action buttons
        local actions = {}

        actions.speedDown = W.Button(row, "speed_down_" .. i, {
            label = "-", bg = 0xff334155,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local sp = steppedValue(layer.speed or 1.0, kSpeeds, -1)
                command("LAYER", tostring(layerIdx), "SPEED", tostring(sp))
            end,
        })

        actions.speedUp = W.Button(row, "speed_up_" .. i, {
            label = "+", bg = 0xff334155,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local sp = steppedValue(layer.speed or 1.0, kSpeeds, 1)
                command("LAYER", tostring(layerIdx), "SPEED", tostring(sp))
            end,
        })

        actions.mute = W.Button(row, "mute_" .. i, {
            label = "M", bg = 0xff475569,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local val = (layer.state == "muted") and "0" or "1"
                command("LAYER", tostring(layerIdx), "MUTE", val)
            end,
        })

        actions.reverse = W.Button(row, "rev_" .. i, {
            label = "R", bg = 0xff475569,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local val = layer.reversed and "0" or "1"
                command("LAYER", tostring(layerIdx), "REVERSE", val)
            end,
        })

        actions.volDown = W.Button(row, "vol_down_" .. i, {
            label = "V-", bg = 0xff3f3f46,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local v = steppedValue(layer.volume or 1.0, kVolumes, -1)
                command("LAYER", tostring(layerIdx), "VOLUME", tostring(v))
            end,
        })

        actions.volUp = W.Button(row, "vol_up_" .. i, {
            label = "V+", bg = 0xff3f3f46,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local v = steppedValue(layer.volume or 1.0, kVolumes, 1)
                command("LAYER", tostring(layerIdx), "VOLUME", tostring(v))
            end,
        })

        actions.stop = W.Button(row, "stop_" .. i, {
            label = "S", bg = 0xff334155,
            on_click = function()
                command("LAYER", tostring(layerIdx), "STOP")
            end,
        })

        actions.clear = W.Button(row, "clear_" .. i, {
            label = "C", bg = 0xff1f2937,
            on_click = function()
                command("LAYER", tostring(layerIdx), "CLEAR")
            end,
        })

        table.insert(ui.layerRows, {
            node = row,
            actions = actions,
            layerIdx = layerIdx,
        })
    end

    -- Status bar
    ui.statusPanel = W.Panel(root, "status", {
        bg = 0xff0b1220, radius = 8,
    })
    ui.statusPanel.node:setInterceptsMouse(false, false)
    ui.statusPanel.node:setOnDraw(function(self)
        local w = self:getWidth()
        local h = self:getHeight()
        gfx.setFont("Avenir Next", 12.0, FontStyle.plain)
        gfx.setColour(0xff94a3b8)

        local spb = current_state.samplesPerBar or 88200
        local sr = math.max(1, current_state.sampleRate or 44100)
        local barSecs = spb / sr
        local overdubText = current_state.overdubEnabled and "overdub ON" or "overdub OFF"

        local left = string.format("Tempo %.2f BPM  |  1 bar %.3f s  |  target %.1f  |  master %.2f  |  %s",
            current_state.tempo or 120,
            barSecs,
            current_state.targetBPM or 120,
            current_state.masterVolume or 1.0,
            overdubText)

        gfx.drawText(left, 10, 0, w - 200, h, Justify.centredLeft)

        local right = string.format("capture %d smp", current_state.captureSize or 0)
        gfx.drawText(right, w - 190, 0, 180, h, Justify.centredRight)
    end)
end

-- ============================================================================
-- ui_resized: Layout all nodes
-- ============================================================================

function ui_resized(w, h)
    if not ui.title then return end

    -- Title
    ui.title.node:setBounds(0, 0, w - 52, 44)
    if ui.settingsBtn then
        ui.settingsBtn.node:setBounds(w - 44, 4, 40, 36)
    end

    -- Controls panel
    local ctlY = 52
    ui.controlsPanel.node:setBounds(0, ctlY, w, 56)

    -- Layout control buttons evenly
    local ctlPad = 8
    local ctlCount = #ui.controlButtons
    local ctlGap = 6
    local totalCtlW = w - ctlPad * 2
    local btnW = math.floor((totalCtlW - ctlGap * (ctlCount - 1)) / ctlCount)
    local cx = ctlPad
    for _, btn in ipairs(ui.controlButtons) do
        btn.node:setBounds(cx, ctlPad, btnW, 56 - ctlPad * 2)
        cx = cx + btnW + ctlGap
    end

    -- Capture plane
    local capY = ctlY + 56 + 8
    local capH = 212
    ui.capturePanel.node:setBounds(0, capY, w, capH)

    -- Layout strips and segments within capture area
    local captureArea = {x = 12, y = 30, w = w - 24, h = capH - 42}
    local slotCount = #kSegmentBars
    local slotWidth = math.max(1, math.floor(captureArea.w / slotCount))
    local totalStripW = slotWidth * slotCount
    local x0 = captureArea.x + captureArea.w - totalStripW

    for slot, strip in ipairs(ui.captureStrips) do
        strip.node:setBounds(x0 + (slot - 1) * slotWidth, captureArea.y, slotWidth, captureArea.h)
    end

    -- Segment hit regions (reverse order so shortest is on top)
    for _, seg in ipairs(ui.captureSegments) do
        local i = seg.index
        local sx = x0 + (slotCount - i) * slotWidth
        local sw = i * slotWidth
        seg.node:setBounds(sx, captureArea.y, sw, captureArea.h)
    end

    -- Now indicator
    if ui.nowIndicator then
        ui.nowIndicator:setBounds(x0 + totalStripW - 2, captureArea.y, 2, captureArea.h)
    end

    -- Status bar
    local statusH = 36
    local statusY = h - statusH
    ui.statusPanel.node:setBounds(0, statusY, w, statusH)

    -- Layers panel fills remaining space
    local layerY = capY + capH + 8
    local layerH = statusY - layerY - 8
    ui.layersPanel.node:setBounds(0, layerY, w, layerH)

    -- Layout layer rows
    local layerPad = 8
    local rowGap = 8
    local innerH = layerH - layerPad * 2
    local rowH = math.floor((innerH - rowGap * (MAX_LAYERS - 1)) / MAX_LAYERS)
    local ry = layerPad

    for _, lr in ipairs(ui.layerRows) do
        lr.node:setBounds(layerPad, ry, w - layerPad * 2, rowH)

        -- Action buttons on the right side of each row
        local actionW = 36
        local actionGap = 6
        local ax = lr.node:getWidth() - layerPad - 8 * (actionW + actionGap) + actionGap
        local ay = 7
        local ah = rowH - 14

        local actionOrder = {"speedDown", "speedUp", "mute", "reverse", "volDown", "volUp", "stop", "clear"}
        for _, key in ipairs(actionOrder) do
            local btn = lr.actions[key]
            if btn then
                btn.node:setBounds(ax, ay, actionW, ah)
                ax = ax + actionW + actionGap
            end
        end

        ry = ry + rowH + rowGap
    end
end

-- ============================================================================
-- ui_update: refresh dynamic state
-- ============================================================================

function ui_update(s)
    current_state = s

    -- Update button labels/colours based on state
    if ui.recBtn then
        if s.isRecording then
            ui.recBtn.setLabel("REC*")
            ui.recBtn.setBg(0xffdc2626)
        else
            ui.recBtn.setLabel("REC")
            ui.recBtn.setBg(0xff7f1d1d)
        end
    end

    if ui.overdubBtn then
        if s.overdubEnabled then
            ui.overdubBtn.setLabel("OVERDUB*")
            ui.overdubBtn.setBg(0xfff59e0b)
        else
            ui.overdubBtn.setLabel("OVERDUB")
            ui.overdubBtn.setBg(0xff7c4a03)
        end
    end

    if ui.modeBtn then
        ui.modeBtn.setLabel(recordModeText(s.recordMode or "firstLoop"))
    end

    -- Update layer action button colours
    for _, lr in ipairs(ui.layerRows) do
        local layer = s.layers and s.layers[lr.layerIdx + 1] or {}

        -- Mute button colour
        if lr.actions.mute then
            local isMuted = layer.state == "muted"
            lr.actions.mute.setBg(isMuted and 0xffef4444 or 0xff475569)
        end

        -- Reverse button colour
        if lr.actions.reverse then
            local isRev = layer.reversed
            lr.actions.reverse.setBg(isRev and 0xff16a34a or 0xff475569)
        end
    end
end

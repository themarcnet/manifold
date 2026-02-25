-- looper_ui.lua
-- Clean, functional Looper UI built with the widget system.
-- Features: scrubable waveforms, negative speed = reverse, compact header controls.

local W = require("looper_widgets")

-- ============================================================================
-- State
-- ============================================================================
local current_state = {}
local MAX_LAYERS = 4
local ui = {}
local recButtonLatched = false

-- ============================================================================
-- Helpers
-- ============================================================================

-- Only 3 modes: Retrospective is the default commit behavior (no dedicated mode needed)
local kModeNames = {"First Loop", "Free Mode", "Traditional"}
local kModeKeys = {"firstLoop", "freeMode", "traditional"}

local kSegmentBars = {0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0}
local kSegmentLabels = {"1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16"}

local function commandSet(path, value)
    command("SET", path, tostring(value))
end

local function commandTrigger(path)
    command("TRIGGER", path)
end

local function layerPath(layerIndex, suffix)
    return string.format("/looper/layer/%d/%s", layerIndex, suffix)
end

local function modeText(mode)
    for i, k in ipairs(kModeKeys) do
        if k == mode then return kModeNames[i] end
    end
    return "Mode"
end

local function layerStateColour(state)
    local colours = {
        empty = 0xff64748b,
        playing = 0xff34d399,
        recording = 0xffef4444,
        overdubbing = 0xfff59e0b,
        muted = 0xff94a3b8,
        stopped = 0xfffde047,
        paused = 0xffa78bfa,
    }
    return colours[state] or 0xffffffff
end

local function layerStateName(state)
    local names = {
        empty = "Empty", playing = "Playing", recording = "Recording",
        overdubbing = "Overdub", muted = "Muted", stopped = "Stopped",
        paused = "Paused",
    }
    return names[state] or ""
end

-- ============================================================================
-- UI Initialization
-- ============================================================================

function ui_init(root)
    -- Root panel with dark background
    ui.rootPanel = W.Panel.new(root, "rootPanel", {
        bg = 0xff0a0f1a,
    })
    
    -- ==========================================================================
    -- Header Bar: Title | Tempo | Target BPM | Master Vol | Settings
    -- ==========================================================================
    ui.headerPanel = W.Panel.new(ui.rootPanel.node, "header", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })
    
    ui.titleLabel = W.Label.new(ui.headerPanel.node, "title", {
        text = "LOOPER",
        colour = 0xff7dd3fc,
        fontSize = 22.0,
        fontStyle = FontStyle.bold,
    })
    
    -- Tempo number box
    ui.tempoBox = W.NumberBox.new(ui.headerPanel.node, "tempo", {
        min = 40, max = 240, step = 1, value = 120,
        label = "BPM", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) commandSet("/looper/tempo", v) end,
    })
    
    -- Target BPM number box
    ui.targetBpmBox = W.NumberBox.new(ui.headerPanel.node, "targetBpm", {
        min = 40, max = 240, step = 1, value = 120,
        label = "Target", suffix = "",
        colour = 0xff22d3ee,
        format = "%d",
        on_change = function(v) commandSet("/looper/targetbpm", v) end,
    })
    
    -- Master volume knob
    ui.masterVolKnob = W.Knob.new(ui.headerPanel.node, "masterVol", {
        min = 0, max = 1, step = 0.01, value = 0.8,
        label = "Master", suffix = "",
        colour = 0xffa78bfa,
        on_change = function(v) commandSet("/looper/volume", v) end,
    })
    
    -- Settings button with dropdown menu
    local _settingsOpen = false
    local _scriptOverlay = nil
    
    ui.settingsBtn = W.Button.new(ui.headerPanel.node, "settings", {
        label = "⚙",
        bg = 0xff1e293b,
        fontSize = 16.0,
        on_click = function()
            _settingsOpen = not _settingsOpen
            if _settingsOpen then
                local scripts = listUiScripts()
                local currentPath = getCurrentScriptPath()
                
                if _scriptOverlay then
                    _scriptOverlay:setOnDraw(nil)
                    _scriptOverlay:setOnMouseDown(nil)
                end
                if not _scriptOverlay then
                    _scriptOverlay = root:addChild("script_overlay")
                end
                
                local itemH = 28
                local headerH = 26
                local overlayH = math.min(300, headerH + #scripts * itemH + 8)
                local overlayW = 220
                local btnX, btnY = ui.settingsBtn.node:getBounds()
                _scriptOverlay:setBounds(btnX - overlayW + 36, btnY + 32, overlayW, overlayH)
                
                _scriptOverlay:setOnDraw(function(self)
                    local w = self:getWidth()
                    local h = self:getHeight()
                    -- Drop shadow
                    gfx.setColour(0x40000000)
                    gfx.fillRoundedRect(2, 2, w, h, 6)
                    -- Background
                    gfx.setColour(0xff1e293b)
                    gfx.fillRoundedRect(0, 0, w - 2, h - 2, 6)
                    gfx.setColour(0xff475569)
                    gfx.drawRoundedRect(0, 0, w - 2, h - 2, 6, 1)
                    
                    -- Header
                    gfx.setColour(0xff94a3b8)
                    gfx.setFont(10.0)
                    gfx.drawText("UI Scripts", 10, 4, w - 20, headerH - 4, Justify.centredLeft)
                    
                    -- Items
                    for i, s in ipairs(scripts) do
                        local y = headerH + (i - 1) * itemH
                        local isCurrent = (s.path == currentPath)
                        if isCurrent then
                            gfx.setColour(0xff334155)
                            gfx.fillRoundedRect(4, y, w - 10, itemH - 2, 4)
                        end
                        gfx.setColour(isCurrent and 0xff38bdf8 or 0xffe2e8f0)
                        gfx.setFont(11.0)
                        gfx.drawText(s.name, 12, y, w - 28, itemH - 2, Justify.centredLeft)
                    end
                end)
                
                _scriptOverlay:setOnMouseDown(function(mx, my)
                    if my < headerH then
                        _settingsOpen = false
                        _scriptOverlay:setBounds(0, 0, 0, 0)
                        return
                    end
                    local idx = math.floor((my - headerH) / itemH) + 1
                    if idx >= 1 and idx <= #scripts then
                        _settingsOpen = false
                        if scripts[idx].path ~= currentPath then
                            switchUiScript(scripts[idx].path)
                        end
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
    
    -- ==========================================================================
    -- Transport Controls
    -- ==========================================================================
    ui.transportPanel = W.Panel.new(ui.rootPanel.node, "transport", {
        bg = 0xff141a24,
        radius = 8,
    })
    
    -- Mode dropdown (3 modes only, overlay on root)
    ui.modeDropdown = W.Dropdown.new(ui.transportPanel.node, "mode", {
        options = kModeNames,
        selected = 1,
        bg = 0xff1f4a7a,
        colour = 0xff7dd3fc,
        rootNode = root,
        on_select = function(idx)
            commandSet("/looper/mode", kModeKeys[idx] or "firstLoop")
        end,
    })
    
    -- REC button
    ui.recBtn = W.Button.new(ui.transportPanel.node, "rec", {
        label = "● REC",
        bg = 0xff7f1d1d,
        fontSize = 13.0,
        on_press = function()
            if recButtonLatched then
                commandTrigger("/looper/stoprec")
                recButtonLatched = false
            else
                commandTrigger("/looper/rec")
                recButtonLatched = true
            end
        end,
    })
    
    -- PLAY/PAUSE toggle (single button)
    ui.playPauseBtn = W.Button.new(ui.transportPanel.node, "playpause", {
        label = "▶ PLAY",
        bg = 0xff1f7a3a,
        fontSize = 13.0,
        on_click = function()
            local anyPlaying = false
            if current_state.layers then
                for _, layer in ipairs(current_state.layers) do
                    if layer.state == "playing" then anyPlaying = true end
                end
            end
            if anyPlaying then
                commandTrigger("/looper/pause")
            else
                commandTrigger("/looper/play")
            end
        end,
    })
    
    -- STOP button
    ui.stopBtn = W.Button.new(ui.transportPanel.node, "stop", {
        label = "⏹ STOP",
        bg = 0xff374151,
        fontSize = 13.0,
        on_click = function() commandTrigger("/looper/stop") end,
    })
    
    -- Overdub toggle
    ui.overdubToggle = W.Toggle.new(ui.transportPanel.node, "overdub", {
        label = "Overdub",
        onColour = 0xfff59e0b,
        offColour = 0xff374151,
        on_change = function(on) commandSet("/looper/overdub", on and 1 or 0) end,
    })
    
    -- Clear All button
    ui.clearAllBtn = W.Button.new(ui.transportPanel.node, "clearall", {
        label = "Clear All",
        bg = 0xff1f2937,
        fontSize = 12.0,
        on_click = function() commandTrigger("/looper/clear") end,
    })
    
    -- ==========================================================================
    -- Capture Plane
    -- ==========================================================================
    ui.capturePanel = W.Panel.new(ui.rootPanel.node, "capture", {
        bg = 0xff101723,
        radius = 8,
    })
    
    ui.captureTitle = W.Label.new(ui.capturePanel.node, "captureTitle", {
        text = "Capture Plane",
        colour = 0xff9ca3af,
        fontSize = 12.0,
    })
    
    -- Segment strips
    ui.captureStrips = {}
    for slot = 1, #kSegmentBars do
        local barsIndex = #kSegmentBars + 1 - slot
        local stripBars = kSegmentBars[barsIndex]
        local stripLabel = kSegmentLabels[barsIndex]
        
        local strip = W.Panel.new(ui.capturePanel.node, "strip_" .. slot, {
            bg = 0xff0f1b2d,
            interceptsMouse = false,
        })
        
        local prevBars = (barsIndex > 1) and kSegmentBars[barsIndex - 1] or 0
        
        strip.node:setOnDraw(function(self)
            local w = self:getWidth()
            local h = self:getHeight()
            
            gfx.setColour(0xff0f1b2d)
            gfx.fillRect(0, 0, w, h)
            gfx.setColour(0x22ffffff)
            gfx.drawHorizontalLine(math.floor(h / 2), 0, w)
            
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
            
            gfx.setColour(0x40475569)
            gfx.drawRect(0, 0, w, h)
            gfx.setColour(0xffcbd5e1)
            gfx.setFont(10.0)
            gfx.drawText(stripLabel, 4, h - 16, w - 8, 14, Justify.bottomLeft)
        end)
        
        table.insert(ui.captureStrips, {node = strip.node, barsIndex = barsIndex})
    end
    
    -- Segment hit regions
    ui.captureSegments = {}
    for i = #kSegmentBars, 1, -1 do
        local bars = kSegmentBars[i]
        local label = kSegmentLabels[i]
        
        local seg = W.Panel.new(ui.capturePanel.node, "segment_hit_" .. i, {
            bg = 0x00000000,
            interceptsMouse = true,
        })
        
        seg.node:setOnClick(function()
            if current_state.recordMode == "traditional" then
                commandSet("/looper/forward", bars)
            else
                commandSet("/looper/commit", bars)
            end
        end)
        
        seg.node:setOnDraw(function(self)
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
                gfx.setFont(12.0)
                gfx.drawText(label .. " bars", 6, 0, w - 12, 20, Justify.topRight)
            end
        end)
        
        table.insert(ui.captureSegments, {node = seg.node, bars = bars, index = i})
    end
    
    -- Now indicator
    ui.nowIndicator = W.Panel.new(ui.capturePanel.node, "now_indicator", {
        bg = 0x00000000,
        interceptsMouse = false,
    })
    ui.nowIndicator.node:setOnDraw(function(self)
        gfx.setColour(0xb3e2e8f0)
        gfx.drawVerticalLine(self:getWidth() - 1, 1, self:getHeight() - 1)
    end)
    
    -- ==========================================================================
    -- Layer Panels
    -- ==========================================================================
    ui.layerPanels = {}
    
    for i = 0, MAX_LAYERS - 1 do
        local layerIdx = i
        
        local panel = W.Panel.new(ui.rootPanel.node, "layer" .. i, {
            bg = 0xff1b2636,
            radius = 8,
            border = 0xff334155,
            borderWidth = 1,
        })
        
        -- Layer number label
        local label = W.Label.new(panel.node, "label" .. i, {
            text = "L" .. i,
            colour = 0xff94a3b8,
            fontSize = 15.0,
            fontStyle = FontStyle.bold,
        })
        
        -- State text
        local stateLabel = W.Label.new(panel.node, "state" .. i, {
            text = "",
            colour = 0xff64748b,
            fontSize = 11.0,
        })
        
        -- Waveform view (vinyl-style scrub: drag velocity controls speed/direction)
        local preScrubSpeed = 1.0
        local preScrubReversed = false
        local waveform = W.WaveformView.new(panel.node, "wf" .. i, {
            mode = "layer",
            layerIndex = i,
            colour = 0xff22d3ee,
            -- Grab: save current speed, ensure playing
            on_scrub_start = function()
                local layerData = current_state.layers and current_state.layers[layerIdx + 1] or {}
                preScrubSpeed = layerData.speed or 1.0
                preScrubReversed = layerData.reversed or false
                commandTrigger(layerPath(layerIdx, "play"))
            end,
            -- Click + drag: seek to position AND set speed from delta for smooth audio
            on_scrub_snap = function(pos, delta)
                commandSet(layerPath(layerIdx, "seek"), pos)
                -- Derive speed from position delta for smooth interpolation
                local layerData = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local length = layerData.length or 0
                if length > 0 then
                    local sr = current_state.sampleRate or 44100
                    local samplesPerFrame = sr / 60
                    local speed = (delta * length) / samplesPerFrame
                    local absSpeed = math.abs(speed)
                    commandSet(layerPath(layerIdx, "speed"), absSpeed)
                    commandSet(layerPath(layerIdx, "reverse"), speed < 0 and 1 or 0)
                end
            end,
            -- Release: restore pre-scrub speed and direction
            on_scrub_end = function()
                commandSet(layerPath(layerIdx, "speed"), preScrubSpeed)
                commandSet(layerPath(layerIdx, "reverse"), preScrubReversed and 1 or 0)
                commandTrigger(layerPath(layerIdx, "play"))
            end,
        })
        
        -- Volume knob (replaces slider)
        local volKnob = W.Knob.new(panel.node, "vol" .. i, {
            min = 0, max = 2, step = 0.01, value = 1.0,
            label = "Vol", suffix = "",
            colour = 0xffa78bfa,
            on_change = function(v)
                commandSet(layerPath(layerIdx, "volume"), v)
            end,
        })
        
        -- Speed knob: -4 to +4, negative = reverse
        local speedKnob = W.Knob.new(panel.node, "speed" .. i, {
            min = -4.0, max = 4.0, step = 0.01, value = 1.0,
            label = "Speed", colour = 0xff22d3ee,
            on_change = function(v)
                local absSpeed = math.abs(v)
                local rev = v < 0
                commandSet(layerPath(layerIdx, "speed"), absSpeed)
                commandSet(layerPath(layerIdx, "reverse"), rev and 1 or 0)
            end,
        })
        
        -- Mute button (labeled, toggles color)
        local muteBtn = W.Button.new(panel.node, "mute" .. i, {
            label = "Mute",
            bg = 0xff475569,
            fontSize = 11.0,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local val = (layer.state == "muted") and "0" or "1"
                commandSet(layerPath(layerIdx, "mute"), tonumber(val) or 0)
            end,
        })
        
        -- Play/Pause per layer
        local playBtn = W.Button.new(panel.node, "play" .. i, {
            label = "▶",
            bg = 0xff1f7a3a,
            fontSize = 13.0,
            on_click = function()
                local layer = current_state.layers and current_state.layers[layerIdx + 1] or {}
                if layer.state == "playing" then
                    commandTrigger(layerPath(layerIdx, "pause"))
                else
                    commandTrigger(layerPath(layerIdx, "play"))
                end
            end,
        })
        
        -- Clear button
        local clearBtn = W.Button.new(panel.node, "clear" .. i, {
            label = "✕",
            bg = 0xff7f1d1d,
            fontSize = 11.0,
            on_click = function()
                commandTrigger(layerPath(layerIdx, "clear"))
            end,
        })
        
        -- Select layer on panel click
        panel.node:setOnClick(function()
            commandSet("/looper/layer", layerIdx)
        end)
        
        table.insert(ui.layerPanels, {
            panel = panel, label = label, stateLabel = stateLabel,
            waveform = waveform, volKnob = volKnob, speedKnob = speedKnob,
            muteBtn = muteBtn,
            playBtn = playBtn, clearBtn = clearBtn,
            layerIdx = layerIdx,
        })
    end
    
    -- ==========================================================================
    -- Status Bar
    -- ==========================================================================
    ui.statusPanel = W.Panel.new(ui.rootPanel.node, "status", {
        bg = 0xff0b1220,
    })
    
    ui.statusLabel = W.Label.new(ui.statusPanel.node, "statusText", {
        text = "Ready",
        colour = 0xff64748b,
        fontSize = 11.0,
    })
end

-- ============================================================================
-- Layout
-- ============================================================================

function ui_resized(w, h)
    if not ui.rootPanel then return end
    
    ui.rootPanel:setBounds(0, 0, w, h)
    
    local pad = 10
    local gap = 6
    local headerH = 44
    local transportH = 48
    local captureH = 130
    local statusH = 26
    
    -- Header bar
    ui.headerPanel:setBounds(pad, pad, w - pad * 2, headerH)
    ui.titleLabel:setBounds(10, 0, 100, headerH)
    
    local hRight = w - pad * 2 - 10
    local boxW = 100
    local knobW = headerH - 4
    local hGap = 8
    
    ui.settingsBtn:setBounds(hRight - 34, 6, 32, headerH - 12)
    hRight = hRight - 34 - hGap
    
    ui.masterVolKnob:setBounds(hRight - knobW, 2, knobW, headerH - 4)
    hRight = hRight - knobW - hGap
    
    ui.targetBpmBox:setBounds(hRight - boxW, 6, boxW, headerH - 12)
    hRight = hRight - boxW - hGap
    
    ui.tempoBox:setBounds(hRight - boxW, 6, boxW, headerH - 12)
    
    -- Transport bar
    local ty = pad + headerH + gap
    ui.transportPanel:setBounds(pad, ty, w - pad * 2, transportH)
    
    local tPad = 6
    local tH = transportH - tPad * 2
    local tx = tPad
    
    ui.modeDropdown:setBounds(tx, tPad, 130, tH)
    ui.modeDropdown:setAbsolutePos(pad + tx, ty + tPad)
    tx = tx + 130 + 8
    
    local btnW = 80
    ui.recBtn:setBounds(tx, tPad, btnW, tH)
    tx = tx + btnW + 6
    ui.playPauseBtn:setBounds(tx, tPad, btnW, tH)
    tx = tx + btnW + 6
    ui.stopBtn:setBounds(tx, tPad, btnW, tH)
    tx = tx + btnW + 12
    
    ui.overdubToggle:setBounds(tx, tPad, 110, tH)
    tx = tx + 110 + 12
    
    ui.clearAllBtn:setBounds(tx, tPad, 70, tH)
    
    -- Capture plane
    local cy = ty + transportH + gap
    ui.capturePanel:setBounds(pad, cy, w - pad * 2, captureH)
    
    local caption = "Click segment to COMMIT"
    if current_state.forwardArmed then
        caption = "FORWARD ARMED " .. string.format("%.3f", current_state.forwardBars or 0) .. " bars"
    elseif current_state.recordMode == "traditional" then
        caption = "Click segment to arm FORWARD"
    end
    ui.captureTitle:setText(caption)
    ui.captureTitle:setBounds(10, 4, w - pad * 2 - 20, 18)
    
    local captureArea = {x = 10, y = 24, w = w - pad * 2 - 20, h = captureH - 34}
    local slotCount = #kSegmentBars
    local slotWidth = math.max(1, math.floor(captureArea.w / slotCount))
    local totalStripW = slotWidth * slotCount
    local x0 = captureArea.x + captureArea.w - totalStripW
    
    for slot, strip in ipairs(ui.captureStrips) do
        strip.node:setBounds(x0 + (slot - 1) * slotWidth, captureArea.y, slotWidth, captureArea.h)
    end
    
    for _, seg in ipairs(ui.captureSegments) do
        local i = seg.index
        local sx = x0 + (slotCount - i) * slotWidth
        local sw = i * slotWidth
        seg.node:setBounds(sx, captureArea.y, sw, captureArea.h)
    end
    
    if ui.nowIndicator then
        ui.nowIndicator:setBounds(x0 + totalStripW - 2, captureArea.y, 2, captureArea.h)
    end
    
    -- Layers
    local layerY = cy + captureH + gap
    local layerH = h - layerY - statusH - gap
    local rowH = math.floor((layerH - gap * (MAX_LAYERS - 1)) / MAX_LAYERS)
    
    for i, layer in ipairs(ui.layerPanels) do
        local y = layerY + (i - 1) * (rowH + gap)
        layer.panel:setBounds(pad, y, w - pad * 2, rowH)
        
        local lPad = 6
        local lh = rowH - lPad * 2
        local knobSize = math.min(lh, 60)
        
        -- Labels on the left
        layer.label:setBounds(lPad, lPad, 26, math.floor(lh * 0.5))
        layer.stateLabel:setBounds(lPad, lPad + math.floor(lh * 0.45), 50, math.floor(lh * 0.5))
        
        -- Knobs on the right
        local rightEdge = w - pad * 2 - lPad
        local kGap = 4
        
        -- Clear button (far right)
        layer.clearBtn:setBounds(rightEdge - 30, lPad, 28, math.floor(lh * 0.45))
        -- Play button
        layer.playBtn:setBounds(rightEdge - 30, lPad + math.floor(lh * 0.5), 28, math.floor(lh * 0.45))
        -- Mute button
        layer.muteBtn:setBounds(rightEdge - 30 - 44 - kGap, lPad, 44, lh)
        
        -- Speed knob
        local speedX = rightEdge - 30 - 44 - kGap - knobSize - kGap
        layer.speedKnob:setBounds(speedX, lPad, knobSize, lh)
        
        -- Vol knob
        local volX = speedX - knobSize - kGap
        layer.volKnob:setBounds(volX, lPad, knobSize, lh)
        
        -- Waveform fills remaining space (scrubable)
        local wfX = 56
        local wfW = volX - wfX - kGap
        layer.waveform:setBounds(wfX, lPad, math.max(40, wfW), lh)
    end
    
    -- Status bar
    ui.statusPanel:setBounds(0, h - statusH, w, statusH)
    ui.statusLabel:setBounds(pad, 0, w - pad * 2, statusH)
end

-- ============================================================================
-- Update
-- ============================================================================

function ui_update(s)
    current_state = s
    recButtonLatched = s.isRecording or false
    
    -- Header
    if ui.tempoBox then ui.tempoBox:setValue(s.tempo or 120) end
    if ui.targetBpmBox then ui.targetBpmBox:setValue(s.targetBPM or 120) end
    if ui.masterVolKnob then ui.masterVolKnob:setValue(s.masterVolume or 0.8) end
    
    -- Transport
    if ui.modeDropdown then
        -- Map mode index: 0=FirstLoop, 1=Free, 2=Traditional (skip 3=Retrospective)
        local modeInt = s.recordModeInt or 0
        if modeInt <= 2 then
            ui.modeDropdown:setSelected(modeInt + 1)
        else
            -- If retrospective is set from the backend, show as first loop
            ui.modeDropdown:setSelected(1)
        end
    end
    
    if ui.recBtn then
        if s.isRecording then
            ui.recBtn:setBg(0xffdc2626)
            ui.recBtn:setLabel("● REC*")
        else
            ui.recBtn:setBg(0xff7f1d1d)
            ui.recBtn:setLabel("● REC")
        end
    end
    
    if ui.playPauseBtn then
        local anyPlaying = false
        if s.layers then
            for _, layer in ipairs(s.layers) do
                if layer.state == "playing" then anyPlaying = true end
            end
        end
        if anyPlaying then
            ui.playPauseBtn:setLabel("⏸ PAUSE")
            ui.playPauseBtn:setBg(0xffb45309)
        else
            ui.playPauseBtn:setLabel("▶ PLAY")
            ui.playPauseBtn:setBg(0xff1f7a3a)
        end
    end
    
    if ui.overdubToggle then
        ui.overdubToggle:setValue(s.overdubEnabled or false)
    end
    
    -- Layers
    for i, layer in ipairs(ui.layerPanels) do
        local layerData = s.layers and s.layers[i] or {}
        local isActive = (s.activeLayer or 0) == layer.layerIdx
        local state = layerData.state or "empty"
        
        -- Panel style
        if isActive then
            layer.panel:setStyle({bg = 0xff25405f, border = 0xff7dd3fc, borderWidth = 2})
        else
            layer.panel:setStyle({bg = 0xff1b2636, border = 0xff334155, borderWidth = 1})
        end
        
        layer.label:setColour(isActive and 0xff7dd3fc or 0xff94a3b8)
        layer.stateLabel:setText(layerStateName(state))
        layer.stateLabel:setColour(layerStateColour(state))
        
        -- Waveform + playhead
        if layerData.length and layerData.length > 0 then
            layer.waveform:setPlayheadPos((layerData.position or 0) / layerData.length)
            layer.waveform:setColour(layerStateColour(state))
        else
            layer.waveform:setPlayheadPos(-1)
        end
        
        -- Vol knob
        layer.volKnob:setValue(layerData.volume or 1.0)
        
        -- Speed knob: negative when reversed (suppress during scrub to prevent fighting)
        if not layer.waveform._scrubbing then
            local speed = layerData.speed or 1.0
            if layerData.reversed then speed = -speed end
            layer.speedKnob:setValue(speed)
        end
        
        -- Mute button
        if state == "muted" then
            layer.muteBtn:setBg(0xffef4444)
            layer.muteBtn:setLabel("Muted")
        else
            layer.muteBtn:setBg(0xff475569)
            layer.muteBtn:setLabel("Mute")
        end
        
        -- Play/Pause button
        if state == "playing" then
            layer.playBtn:setBg(0xfff59e0b)
            layer.playBtn:setLabel("⏸")
        else
            layer.playBtn:setBg(0xff1f7a3a)
            layer.playBtn:setLabel("▶")
        end
    end
    
    -- Status bar
    if ui.statusLabel then
        local sr = math.max(1, s.sampleRate or 44100)
        local spb = s.samplesPerBar or 88200
        local barSecs = spb / sr
        ui.statusLabel:setText(string.format(
            "%.1f BPM  |  %.2fs/bar  |  Master: %.0f%%  |  Mode: %s",
            s.tempo or 120,
            barSecs,
            (s.masterVolume or 1) * 100,
            modeText(s.recordMode or "firstLoop")
        ))
    end
end

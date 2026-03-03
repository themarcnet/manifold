-- looper_primitives_ui.lua
-- Visual clone of looper_ui.lua wired to canonical behavior paths.

local W = require("ui_widgets")

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
    return string.format("/core/behavior/layer/%d/%s", layerIndex, suffix)
end

local function sanitizeSpeed(value)
    local speed = math.abs(tonumber(value) or 1.0)
    if speed < 0.1 then speed = 0.1 end
    if speed > 4.0 then speed = 4.0 end
    return speed
end

local function sanitizeScrubSpeed(value)
    local speed = math.abs(tonumber(value) or 0.0)
    if speed < 0.0 then speed = 0.0 end
    if speed > 4.0 then speed = 4.0 end
    return speed
end

local function wrap01(v)
    while v < 0.0 do v = v + 1.0 end
    while v >= 1.0 do v = v - 1.0 end
    return v
end

local function shortestNormDiff(target, current)
    local d = target - current
    if d > 0.5 then d = d - 1.0 end
    if d < -0.5 then d = d + 1.0 end
    return d
end

local function modeText(mode)
    if type(mode) == "number" then
        local idx = math.max(0, math.min(2, math.floor(mode + 0.5)))
        return kModeNames[idx + 1]
    end
    for i, k in ipairs(kModeKeys) do
        if k == mode then return kModeNames[i] end
    end
    return "Mode"
end

local function readParam(params, path, fallback)
    if type(params) ~= "table" then
        return fallback
    end
    local value = params[path]
    if value == nil then
        return fallback
    end
    return value
end

local function readBoolParam(params, path, fallback)
    local raw = readParam(params, path, fallback and 1 or 0)
    if raw == nil then
        return fallback
    end
    return raw == true or raw == 1
end

local function modeIndexFromString(mode)
    if type(mode) == "number" then
        return math.max(0, math.min(2, math.floor(mode + 0.5)))
    end
    if mode == "firstLoop" then return 0 end
    if mode == "freeMode" then return 1 end
    if mode == "traditional" then return 2 end
    return 0
end

local function formatBars(bars)
    if bars == nil or bars == 0 then
        return ""
    end
    -- Format fractional bars as fractions
    if bars < 1 then
        if math.abs(bars - 0.0625) < 0.001 then return "1/16 bar" end
        if math.abs(bars - 0.125) < 0.001 then return "1/8 bar" end
        if math.abs(bars - 0.25) < 0.001 then return "1/4 bar" end
        if math.abs(bars - 0.5) < 0.001 then return "1/2 bar" end
        return string.format("%.2f bars", bars)
    end
    -- Whole bars (round to nearest to handle floating-point errors like 3.999)
    local rounded = math.floor(bars + 0.5)
    if rounded == 1 then
        return "1 bar"
    else
        return string.format("%d bars", rounded)
    end
end

local function normalizeState(state)
    if type(state) ~= "table" then
        return {}
    end

    local params = state.params or {}
    local voices = state.voices or {}
    local normalized = {
        projectionVersion = state.projectionVersion or 0,
        numVoices = state.numVoices or #voices,
        params = params,
        voices = voices,
        tempo = readParam(params, "/core/behavior/tempo", 120),
        targetBPM = readParam(params, "/core/behavior/targetbpm", 120),
        samplesPerBar = readParam(params, "/core/behavior/samplesPerBar", 88200),
        sampleRate = readParam(params, "/core/behavior/sampleRate", 44100),
        captureSize = readParam(params, "/core/behavior/captureSize", 0),
        masterVolume = readParam(params, "/core/behavior/volume", 0.8),
        inputVolume = readParam(params, "/core/behavior/inputVolume", 1.0),
        passthroughEnabled = readBoolParam(params, "/core/behavior/passthrough", true),
        isRecording = readBoolParam(params, "/core/behavior/recording", false),
        overdubEnabled = readBoolParam(params, "/core/behavior/overdub", false),
        recordMode = readParam(params, "/core/behavior/mode", "firstLoop"),
        link = state.link or {
            enabled = false,
            tempoSync = false,
            startStopSync = false,
            peers = 0,
            playing = false,
            beat = 0,
            phase = 0,
        },
        activeLayer = readParam(params, "/core/behavior/activeLayer", readParam(params, "/core/behavior/layer", 0)),
        forwardArmed = readBoolParam(params, "/core/behavior/forwardArmed", false),
        forwardBars = readParam(params, "/core/behavior/forwardBars", 0),
        spectrum = state.spectrum,
        layers = {},
    }
    normalized.recordModeInt = modeIndexFromString(normalized.recordMode)
    if type(normalized.recordMode) == "number" then
        normalized.recordMode = kModeKeys[math.max(1, math.min(#kModeKeys, normalized.recordModeInt + 1))] or "firstLoop"
    end
    normalized.activeLayer = tonumber(normalized.activeLayer) or 0

    for i, voice in ipairs(voices) do
        if type(voice) == "table" then
            normalized.layers[i] = {
                index = voice.id or (i - 1),
                length = voice.length or 0,
                position = voice.position or 0,
                speed = voice.speed or 1,
                reversed = voice.reversed or false,
                volume = voice.volume or 1,
                state = voice.state or "empty",
                numBars = voice.bars or 0,
                bars = voice.bars or 0,
                params = voice.params or {},
            }
        end
    end

    if #normalized.layers == 0 then
        for layerIdx = 0, MAX_LAYERS - 1 do
            local speed = tonumber(readParam(params, layerPath(layerIdx, "speed"), 1.0)) or 1.0
            local reversed = readBoolParam(params, layerPath(layerIdx, "reverse"), false)
            local volume = tonumber(readParam(params, layerPath(layerIdx, "volume"), 1.0)) or 1.0
            local muted = readBoolParam(params, layerPath(layerIdx, "mute"), false)
            local bars = tonumber(readParam(params, layerPath(layerIdx, "bars"), 0)) or 0
            local length = tonumber(readParam(params, layerPath(layerIdx, "length"), 0)) or 0
            local posNorm = tonumber(readParam(params, layerPath(layerIdx, "seek"), 0)) or 0
            local stateName = readParam(params, layerPath(layerIdx, "state"), nil)
            if type(stateName) ~= "string" or stateName == "" then
                if muted then
                    stateName = "muted"
                elseif normalized.isRecording and normalized.activeLayer == layerIdx then
                    stateName = "recording"
                else
                    stateName = "stopped"
                end
            end

            normalized.layers[layerIdx + 1] = {
                index = layerIdx,
                length = length,
                position = math.floor(posNorm * math.max(1, length)),
                speed = speed,
                reversed = reversed,
                volume = volume,
                state = stateName,
                muted = muted,
                numBars = bars,
                bars = bars,
            }
        end
    end

    return normalized
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
    -- The looper's DSP lives in the "default" slot, loaded once at startup.
    -- Other UIs (donut demo, live scripting) use named slots so the looper's
    -- nodes are never removed. No reload needed here.

    -- Root panel with dark background
    ui.rootPanel = W.Panel.new(root, "rootPanel", {
        bg = 0xff0a0f1a,
    })

    -- ==========================================================================
    -- Transport Controls
    -- ==========================================================================
    ui.transportPanel = W.Panel.new(ui.rootPanel.node, "transport", {
        bg = 0xff141a24,
        radius = 8,
    })

    -- Tempo number box (moved to transport row)
    ui.tempoBox = W.NumberBox.new(ui.transportPanel.node, "tempo", {
        min = 40, max = 240, step = 1, value = 120,
        label = "BPM", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) commandSet("/core/behavior/tempo", v) end,
    })
    
    -- Target BPM number box (moved to transport row)
    ui.targetBpmBox = W.NumberBox.new(ui.transportPanel.node, "targetBpm", {
        min = 40, max = 240, step = 1, value = 120,
        label = "Target", suffix = "",
        colour = 0xff22d3ee,
        format = "%d",
        on_change = function(v) commandSet("/core/behavior/targetbpm", v) end,
    })

    -- Link status indicator (shows LINK when enabled, link when disabled)
    ui.linkIndicator = W.Label.new(ui.transportPanel.node, "linkIndicator", {
        text = "link",
        fontSize = 11,
        colour = 0xff4b5563,
    })

    -- Mode dropdown (3 modes only, overlay on root)
    ui.modeDropdown = W.Dropdown.new(ui.transportPanel.node, "mode", {
        options = kModeNames,
        selected = 1,
        bg = 0xff1f4a7a,
        colour = 0xff7dd3fc,
        rootNode = root,
        on_select = function(idx)
            commandSet("/core/behavior/mode", kModeKeys[idx] or "firstLoop")
        end,
    })
    
    -- REC button
    ui.recBtn = W.Button.new(ui.transportPanel.node, "rec", {
        label = "● REC",
        bg = 0xff7f1d1d,
        fontSize = 13.0,
        on_press = function()
            if recButtonLatched then
                commandTrigger("/core/behavior/stoprec")
                recButtonLatched = false
            else
                commandTrigger("/core/behavior/rec")
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
                commandTrigger("/core/behavior/pause")
            else
                commandTrigger("/core/behavior/play")
            end
        end,
    })
    
    -- STOP button
    ui.stopBtn = W.Button.new(ui.transportPanel.node, "stop", {
        label = "⏹ STOP",
        bg = 0xff374151,
        fontSize = 13.0,
        on_click = function() commandTrigger("/core/behavior/stop") end,
    })
    
    -- Overdub toggle
    ui.overdubToggle = W.Toggle.new(ui.transportPanel.node, "overdub", {
        label = "Overdub",
        onColour = 0xfff59e0b,
        offColour = 0xff374151,
        on_change = function(on) commandSet("/core/behavior/overdub", on and 1 or 0) end,
    })
    
    -- Clear All button
    ui.clearAllBtn = W.Button.new(ui.transportPanel.node, "clearall", {
        label = "Clear All",
        bg = 0xff1f2937,
        fontSize = 12.0,
        on_click = function() commandTrigger("/core/behavior/clear") end,
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
                commandSet("/core/behavior/forward", bars)
            else
                commandSet("/core/behavior/commit", bars)
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
    
    -- ==========================================================================
    -- Layer Panels
    -- ==========================================================================
    ui.layerPanels = {}
    ui.scrubStateByLayer = {}
    
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

        -- Bars/length display
        local barsLabel = W.Label.new(panel.node, "bars" .. i, {
            text = "",
            colour = 0xff94a3b8,
            fontSize = 10.0,
        })

        -- Speed knob: MUST be created BEFORE waveform so scrub callbacks can capture it
        local speedKnob = W.Knob.new(panel.node, "speed" .. i, {
            min = -4.0, max = 4.0, step = 0.01, value = 1.0,
            label = "Speed", colour = 0xff22d3ee,
            on_change = function(v)
                local absSpeed = sanitizeSpeed(v)
                local rev = v < 0
                commandSet(layerPath(layerIdx, "speed"), absSpeed)
                commandSet(layerPath(layerIdx, "reverse"), rev and 1 or 0)
            end,
        })

        -- Waveform view (vinyl scrub + strict 1:1 mouse->playhead pinning)
        local scrub = {}
        ui.scrubStateByLayer[layerIdx + 1] = scrub
        -- Store pre-scrub values on scrub table to survive rapid click races
        scrub.preScrubSpeed = 1.0
        scrub.preScrubReversed = false
        -- Track when scrub ended (in frames) to protect speed knob during restoration
        scrub.scrubEndFrame = 0

        local waveform = W.WaveformView.new(panel.node, "wf" .. i, {
            mode = "layer",
            layerIndex = i,
            colour = 0xff22d3ee,
            on_scrub_start = function()
                -- DEBOUNCE: Don't allow new scrub until 3 frames after previous ended
                -- This ensures state has propagated and prevents race conditions
                local framesSinceLast = (ui.frameCounter or 0) - (scrub.scrubEndFrame or -10)
                if framesSinceLast < 3 then return end
                
                -- Guard against re-entrant scrub starts (already active)
                if scrub._active then return end
                
                scrub._active = true

                local layerData = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local length = layerData.length or 0

                -- CRITICAL: Capture pre-scrub speed from the KNOB, not from layerData.
                -- layerData.speed may be stale or mid-transition during rapid clicks.
                -- The knob value is what the user actually set and expects to restore to.
                local knobValue = speedKnob:getValue()
                scrub.preScrubSpeed = math.abs(knobValue)
                scrub.preScrubReversed = knobValue < 0
                -- Store expected restored value so we can detect when DSP has applied it
                scrub.expectedSpeed = scrub.preScrubSpeed
                scrub.expectedReversed = scrub.preScrubReversed

                scrub.cursorPos = length > 0 and wrap01((layerData.position or 0) / math.max(1, length)) or 0.0
                scrub.lastPinnedPos = nil
                scrub.lastMotionFrame = ui.frameCounter or 0
                scrub.smoothedSignedSpeed = 0.0
                scrub.lastSpeedSent = nil
                scrub.lastReverseSent = nil

                -- No free-run while held still.
                commandSet(layerPath(layerIdx, "speed"), 0.0)
                scrub.lastSpeedSent = 0.0
            end,
            on_scrub_snap = function(pos, delta)
                local layerData = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local length = layerData.length or 0
                if length <= 0 then
                    return
                end

                local p = math.max(0.0, math.min(1.0, pos))
                local prevCursor = scrub.cursorPos or p
                local deltaNorm = p - prevCursor
                scrub.cursorPos = p

                -- Pin playhead to cursor (strict 1:1 mapping).
                if scrub.lastPinnedPos == nil or math.abs(p - scrub.lastPinnedPos) > 0.0005 then
                    commandSet(layerPath(layerIdx, "seek"), p)
                    scrub.lastPinnedPos = p
                end

                local motion = math.abs(deltaNorm) >= 0.0006
                if not motion then
                    return
                end

                scrub.lastMotionFrame = ui.frameCounter or 0

                -- Vinyl-like movement while dragging (smoothed), but cursor remains authoritative.
                local sr = current_state.sampleRate or 44100
                local samplesPerFrame = math.max(1.0, sr / 70.0)
                local targetSignedSpeed = (deltaNorm * length) / samplesPerFrame
                local prev = scrub.smoothedSignedSpeed or 0.0
                local signedSpeed = prev * 0.6 + targetSignedSpeed * 0.4
                scrub.smoothedSignedSpeed = signedSpeed

                local absSpeed = sanitizeScrubSpeed(signedSpeed)
                local rev = signedSpeed < 0.0

                if scrub.lastSpeedSent == nil or math.abs(absSpeed - scrub.lastSpeedSent) > 0.01 then
                    commandSet(layerPath(layerIdx, "speed"), absSpeed)
                    scrub.lastSpeedSent = absSpeed
                end
                if scrub.lastReverseSent == nil or rev ~= scrub.lastReverseSent then
                    commandSet(layerPath(layerIdx, "reverse"), rev and 1 or 0)
                    scrub.lastReverseSent = rev
                end
            end,
            on_scrub_end = function()
                if scrub.cursorPos ~= nil then
                    commandSet(layerPath(layerIdx, "seek"), scrub.cursorPos)
                end
                -- Restore to the values captured at scrub start (stored on scrub table)
                commandSet(layerPath(layerIdx, "speed"), scrub.preScrubSpeed)
                commandSet(layerPath(layerIdx, "reverse"), scrub.preScrubReversed and 1 or 0)

                -- Mark scrub as ended and record frame
                -- Speed knob will be protected until restoration propagates
                scrub._active = false
                scrub.scrubEndFrame = ui.frameCounter or 0

                scrub.cursorPos = nil
                scrub.lastPinnedPos = nil
                scrub.lastMotionFrame = nil
                scrub.smoothedSignedSpeed = nil
                scrub.lastSpeedSent = nil
                scrub.lastReverseSent = nil
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
        
        -- Mute button (labeled, toggles color)
        local muteBtn = W.Button.new(panel.node, "mute" .. i, {
            label = "Mute",
            bg = 0xff475569,
            fontSize = 11.0,
            on_click = function()
                local layerData = current_state.layers and current_state.layers[layerIdx + 1] or {}
                local isMuted = layerData.muted or (layerData.params and layerData.params.mute and layerData.params.mute > 0.5)
                local val = isMuted and 0 or 1
                commandSet(layerPath(layerIdx, "mute"), val)
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
            commandSet("/core/behavior/layer", layerIdx)
        end)
        
        table.insert(ui.layerPanels, {
            panel = panel, label = label, stateLabel = stateLabel, barsLabel = barsLabel,
            waveform = waveform, volKnob = volKnob, speedKnob = speedKnob,
            muteBtn = muteBtn,
            playBtn = playBtn, clearBtn = clearBtn,
            layerIdx = layerIdx,
        })
    end
end

-- ============================================================================
-- Layout
-- ============================================================================

function ui_resized(w, h)
    if not ui.rootPanel then return end
    
    ui.rootPanel:setBounds(0, 0, w, h)
    local contentX, contentY, contentW, contentH = 0, 0, w, h
    
    local pad = contentX
    local gap = 6
    local transportH = 48
    local captureH = 130

    -- Transport bar
    local ty = contentY
    ui.transportPanel:setBounds(contentX, ty, contentW, transportH)
    
    local tPad = 6
    local tH = transportH - tPad * 2
    local tx = tPad
    
    ui.modeDropdown:setBounds(tx, tPad, 130, tH)
    ui.modeDropdown:setAbsolutePos(contentX + tx, ty + tPad)
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

    local tRight = contentW - tPad
    local boxW = 96
    local boxGap = 8
    ui.targetBpmBox:setBounds(tRight - boxW, tPad, boxW, tH)
    tRight = tRight - boxW - boxGap
    ui.tempoBox:setBounds(tRight - boxW, tPad, boxW, tH)
    tRight = tRight - boxW - boxGap - 4
    ui.linkIndicator.node:setBounds(tRight - 50, tPad, 50, tH)

    -- Capture plane
    local cy = ty + transportH + gap
    ui.capturePanel:setBounds(contentX, cy, contentW, captureH)
    
    -- Caption removed - UI is cleaner without it
    ui.captureTitle:setText("")
    ui.captureTitle:setBounds(0, 0, 0, 0)
    
    local captureArea = {x = 0, y = 4, w = contentW, h = captureH - 8}
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
    
    -- Position loop end indicator based on detected loop length
    if ui.loopEndIndicator and ui.loopEndIndicator.setBounds then
        local detectedBars = (current_state and current_state.forwardBars) or 0
        local recordMode = (current_state and current_state.recordMode) or "firstLoop"
        if detectedBars > 0 and recordMode == "traditional" and x0 and totalStripW and slotWidth then
            local rightEdge = x0 + totalStripW
            local loopEndX = rightEdge
            
            for i = #kSegmentBars, 1, -1 do
                local stripMaxBars = kSegmentBars[i]
                if detectedBars <= stripMaxBars then
                    local stripMinBars = (i > 1) and kSegmentBars[i-1] or 0
                    local stripIndexFromRight = #kSegmentBars - i + 1
                    local stripRightEdge = rightEdge - (stripIndexFromRight - 1) * slotWidth
                    local stripLeftEdge = stripRightEdge - slotWidth
                    local barRange = stripMaxBars - stripMinBars
                    if barRange > 0 then
                        local progressInStrip = (detectedBars - stripMinBars) / barRange
                        loopEndX = stripLeftEdge + (1 - progressInStrip) * slotWidth
                    end
                    break
                end
            end
            ui.loopEndIndicator:setBounds(loopEndX - 2, captureArea.y, 4, captureArea.h)
        else
            ui.loopEndIndicator:setBounds(0, 0, 0, 0)
        end
    end
    
    -- Layers
    local layerY = cy + captureH + gap
    local layerH = h - layerY - gap
    local rowH = math.floor((layerH - gap * (MAX_LAYERS - 1)) / MAX_LAYERS)
    
    for i, layer in ipairs(ui.layerPanels) do
        local y = layerY + (i - 1) * (rowH + gap)
        layer.panel:setBounds(contentX, y, contentW, rowH)
        
        local lPad = 6
        local lh = rowH - lPad * 2
        local knobSize = math.min(lh, 60)
        
        -- Labels on the left
        layer.label:setBounds(lPad, lPad, 26, math.floor(lh * 0.4))
        layer.stateLabel:setBounds(lPad, lPad + math.floor(lh * 0.35), 50, math.floor(lh * 0.35))
        layer.barsLabel:setBounds(lPad, lPad + math.floor(lh * 0.7), 50, math.floor(lh * 0.25))
        
        -- Knobs on the right
        local rightEdge = contentW - lPad
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
end

-- ============================================================================
-- Update
-- ============================================================================

function ui_update(s)
    ui.frameCounter = (ui.frameCounter or 0) + 1
    current_state = normalizeState(s)
    local state = current_state
    recButtonLatched = state.isRecording or false
    
    -- Header
    if ui.tempoBox then ui.tempoBox:setValue(state.tempo or 120) end
    if ui.targetBpmBox then ui.targetBpmBox:setValue(state.targetBPM or 120) end

    -- Link indicator with circle (● = enabled, ○ = disabled)
    if ui.linkIndicator then
        local linkState = state.link
        if linkState and linkState.enabled then
            local peers = linkState.peers or 0
            if peers > 0 then
                ui.linkIndicator:setText("● LINK " .. peers)
                ui.linkIndicator:setColour(0xff4ade80)  -- Green with peers
            else
                ui.linkIndicator:setText("● LINK")
                ui.linkIndicator:setColour(0xfff59e0b)  -- Amber enabled, no peers
            end
        else
            ui.linkIndicator:setText("○ link")
            ui.linkIndicator:setColour(0xff4b5563)  -- Gray disabled
        end
    end

    -- Transport
    if ui.modeDropdown then
        local modeInt = state.recordModeInt or 0
        ui.modeDropdown:setSelected(math.max(1, math.min(3, modeInt + 1)))
    end
    
    if ui.recBtn then
        if state.isRecording then
            ui.recBtn:setBg(0xffdc2626)
            ui.recBtn:setLabel("● REC*")
        else
            ui.recBtn:setBg(0xff7f1d1d)
            ui.recBtn:setLabel("● REC")
        end
    end
    
    if ui.playPauseBtn then
        local anyPlaying = false
        if state.layers then
            for _, layer in ipairs(state.layers) do
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
        ui.overdubToggle:setValue(state.overdubEnabled or false)
    end
    
    -- Layers
    for i, layer in ipairs(ui.layerPanels) do
        local layerData = state.layers and state.layers[i] or {}
        local isActive = (state.activeLayer or 0) == layer.layerIdx
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

        -- Bars/length display (only when layer has content)
        if layerData.bars and layerData.bars > 0 then
            local barsText = formatBars(layerData.bars)
            layer.barsLabel:setText(barsText)
        else
            layer.barsLabel:setText("")
        end

        -- Waveform + playhead
        if layerData.length and layerData.length > 0 then
            layer.waveform:setPlayheadPos((layerData.position or 0) / layerData.length)
            layer.waveform:setColour(layerStateColour(state))
        else
            layer.waveform:setPlayheadPos(-1)
        end
        
        -- Get scrub state once for this layer
        local scrub = ui.scrubStateByLayer and ui.scrubStateByLayer[i]
        
        if layer.waveform._scrubbing and scrub then
            local pinned = scrub.cursorPos
            if pinned ~= nil then
                local lastPinned = scrub.lastPinnedPos
                if lastPinned == nil or math.abs(pinned - lastPinned) > 0.0002 then
                    commandSet(layerPath(layer.layerIdx, "seek"), pinned)
                    scrub.lastPinnedPos = pinned
                end
            end

            local lastMotion = scrub.lastMotionFrame or ui.frameCounter
            if (ui.frameCounter - lastMotion) >= 1 then
                local lastSpeed = scrub.lastSpeedSent
                if lastSpeed == nil or math.abs(lastSpeed) > 0.0001 then
                    commandSet(layerPath(layer.layerIdx, "speed"), 0.0)
                    scrub.lastSpeedSent = 0.0
                end
            end
        end

        -- Vol knob
        layer.volKnob:setValue(layerData.volume or 1.0)
        
        -- Speed knob: negative when reversed (do not fight while scrubbing)
        -- Protect until scrub ends AND DSP reports the expected restored speed
        local speedKnobFrozen = false
        if layer.waveform._scrubbing then
            speedKnobFrozen = true
        elseif scrub and scrub._active == false and scrub.expectedSpeed then
            -- Scrub ended, check if DSP has restored the expected speed
            local actualSpeed = layerData.speed or 1.0
            local actualReversed = layerData.reversed or false
            local speedMatch = math.abs(actualSpeed - scrub.expectedSpeed) < 0.01
            local revMatch = (actualReversed == scrub.expectedReversed)
            if not (speedMatch and revMatch) then
                speedKnobFrozen = true
                -- SAFETY: Force clear after 60 frames (~1s) to prevent permanent freeze
                local framesSinceEnd = (ui.frameCounter or 0) - (scrub.scrubEndFrame or 0)
                if framesSinceEnd > 60 then
                    scrub.expectedSpeed = nil
                    scrub.expectedReversed = nil
                    speedKnobFrozen = false
                end
            else
                -- Restoration confirmed, clear expectations
                scrub.expectedSpeed = nil
                scrub.expectedReversed = nil
            end
        end
        if not speedKnobFrozen then
            local speed = layerData.speed or 1.0
            if layerData.reversed then speed = -speed end
            layer.speedKnob:setValue(speed)
        end
        
        -- Mute button
        local isMuted = layerData.muted or (layerData.params and layerData.params.mute and layerData.params.mute > 0.5)
        if isMuted then
            layer.muteBtn:setBg(0xffef4444)
            layer.muteBtn:setLabel("Muted")
        else
            layer.muteBtn:setBg(0xff475569)
            layer.muteBtn:setLabel("Mute")
        end
        
        -- Waveform color shows mute state too
        if isMuted then
            layer.waveform:setColour(0xff94a3b8)
        else
            layer.waveform:setColour(layerStateColour(state))
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
end

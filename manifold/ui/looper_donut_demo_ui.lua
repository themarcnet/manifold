-- looper_donut_demo_ui.lua
-- Alternate visual style: circular/donut loop display.
-- Loads looper_donut_demo_dsp.lua and enables graph processing on init.

local W = require("ui_widgets")

local ui = {}
local current_state = {}
local MAX_LAYERS = 4
local recLatched = false

local function buildDonutDspPathCandidates()
    local out = {}

    if settings and settings.getDspScriptsDir then
        local dir = settings.getDspScriptsDir() or ""
        if dir ~= "" then
            if dir:sub(-1) == "/" then
                table.insert(out, dir .. "looper_donut_demo_dsp.lua")
            else
                table.insert(out, dir .. "/looper_donut_demo_dsp.lua")
            end
        end
    end

    table.insert(out, "manifold/dsp/looper_donut_demo_dsp.lua")
    table.insert(out, "./looper_donut_demo_dsp.lua")
    return out
end

local DONUT_DSP_PATH_CANDIDATES = buildDonutDspPathCandidates()

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function endpointExists(path)
    if type(hasEndpoint) ~= "function" then
        return false
    end
    local ok, result = pcall(hasEndpoint, path)
    return ok and result == true
end

local function setBehaviorParam(path, value)
    if type(setParam) ~= "function" then
        return false
    end
    local ok, handled = pcall(setParam, path, value)
    return ok and handled == true
end

local DONUT_SLOT = "donut"

local function setDonutSlotPersistOnSwitch(persist)
    if type(setDspSlotPersistOnUiSwitch) == "function" then
        pcall(setDspSlotPersistOnUiSwitch, DONUT_SLOT, persist and true or false)
    end
end

local function setDonutInputMonitorEnabled(enabled)
    setBehaviorParam("/core/slots/donut/input/monitor", enabled and 1.0 or 0.0)
end

local function ensureDonutDemoGraphLoaded()
    local loaded = false

    -- Do not reload if this slot is already alive; reloading would wipe donut
    -- loop content and break cross-UI persistence.
    if type(isDspSlotLoaded) == "function" then
        local ok, alive = pcall(isDspSlotLoaded, DONUT_SLOT)
        if ok and alive == true then
            setDonutSlotPersistOnSwitch(true)
            setDonutInputMonitorEnabled(true)
            ui.dspLoaded = true
            ui.graphEnabled = true
            return true
        end
    end

    -- Use slotted API so the donut DSP coexists alongside the default looper
    -- DSP in the same persistent graph. Both produce audio simultaneously.
    if type(loadDspScriptInSlot) == "function" then
        for _, p in ipairs(DONUT_DSP_PATH_CANDIDATES) do
            local ok, result = pcall(loadDspScriptInSlot, p, DONUT_SLOT)
            if ok and result then
                loaded = true
                ui.loadedDspPath = p
                break
            end
        end
    elseif type(loadDspScript) == "function" then
        -- Fallback for legacy hosts without slot support
        for _, p in ipairs(DONUT_DSP_PATH_CANDIDATES) do
            local ok, result = pcall(loadDspScript, p)
            if ok and result then
                loaded = true
                ui.loadedDspPath = p
                break
            end
        end
    end

    if not loaded and type(getDspScriptLastError) == "function" then
        local ok, err = pcall(getDspScriptLastError)
        if ok then ui.dspLoadError = err end
    end

    -- Graph should already be enabled in the persistent graph architecture.
    -- No need to toggle setGraphProcessingEnabled.
    if loaded then
        setDonutSlotPersistOnSwitch(true)
        setDonutInputMonitorEnabled(true)
    end
    ui.dspLoaded = loaded
    ui.graphEnabled = loaded
    return loaded
end

local function readParam(params, path, fallback)
    if type(params) ~= "table" then return fallback end
    local v = params[path]
    if v == nil then return fallback end
    return v
end

local function readLiveParam(path, fallback)
    if type(getParam) == "function" then
        local ok, value = pcall(getParam, path)
        if ok and value ~= nil then
            return value
        end
    end
    return fallback
end

local function readBool(params, path, fallback)
    local v = readParam(params, path, fallback and 1 or 0)
    if v == nil then return fallback end
    return v == true or v == 1
end

local function layerPath(i, suffix)
    return string.format("/core/slots/donut/layer/%d/%s", i, suffix)
end

local function toPositionNorm(position, length)
    local p = tonumber(position) or 0.0
    local len = tonumber(length) or 0.0

    -- New slot endpoints expose normalized position already; keep backwards
    -- compatibility in case an implementation returns absolute samples.
    if len > 1.0 and p > 1.0 then
        p = p / len
    end

    return clamp(p, 0.0, 1.0)
end

local function normalizeState(s)
    local st = s or {}
    local params = st.params or {}

    local out = {
        tempo = tonumber(readLiveParam("/core/slots/donut/tempo", readParam(params, "/core/slots/donut/tempo", 96))) or 96,
        recording = (readLiveParam("/core/slots/donut/recording", readParam(params, "/core/slots/donut/recording", 0)) or 0) > 0.5,
        activeLayer = tonumber(readLiveParam("/core/slots/donut/activeLayer", readParam(params, "/core/slots/donut/activeLayer", readParam(params, "/core/slots/donut/layer", 0)))) or 0,
        wet = 0.35,
        room = 0.65,
        layers = {},
    }

    for i = 0, MAX_LAYERS - 1 do
        local length = tonumber(readLiveParam(layerPath(i, "length"), readParam(params, layerPath(i, "length"), 0))) or 0
        local rawPosition = tonumber(readLiveParam(layerPath(i, "position"), readParam(params, layerPath(i, "position"), 0))) or 0
        local positionNorm = toPositionNorm(rawPosition, length)
        local volume = tonumber(readLiveParam(layerPath(i, "volume"), readParam(params, layerPath(i, "volume"), 0.85))) or 0.85

        local stateName = readParam(params, layerPath(i, "state"), "stopped")
        local stateLive = readLiveParam(layerPath(i, "state"), nil)
        if type(stateLive) == "string" then
            stateName = stateLive
        elseif type(stateLive) == "number" then
            if stateLive > 0.5 then
                stateName = "playing"
            elseif length > 0 then
                stateName = "stopped"
            else
                stateName = "empty"
            end
        elseif length <= 0 then
            stateName = "empty"
        end
        local muted = (readLiveParam(layerPath(i, "mute"), readParam(params, layerPath(i, "mute"), 0)) or 0) > 0.5

        out.layers[i + 1] = {
            index = i,
            length = length,
            position = rawPosition,
            positionNorm = positionNorm,
            volume = volume,
            state = stateName,
            muted = muted,
        }
    end

    return out
end

local function layerColor(state)
    if state == "recording" then return 0xffef4444 end
    if state == "playing" then return 0xff22c55e end
    if state == "overdubbing" then return 0xfff59e0b end
    if state == "paused" then return 0xffa78bfa end
    if state == "muted" then return 0xff64748b end
    return 0xff38bdf8
end

local function drawCircle(cx, cy, r, colour, segs)
    segs = segs or 64
    gfx.setColour(colour)
    local px = cx + r
    local py = cy
    for i = 1, segs do
        local t = (i / segs) * math.pi * 2.0
        local x = cx + math.cos(t) * r
        local y = cy + math.sin(t) * r
        gfx.drawLine(px, py, x, y)
        px, py = x, y
    end
end

local function easedLayerBounce(layerIdx, target)
    if type(ui.layerBounce) ~= "table" then
        ui.layerBounce = {}
    end

    local key = layerIdx + 1
    local prev = ui.layerBounce[key] or 0.0
    local nextV = prev * 0.84 + target * 0.16
    ui.layerBounce[key] = nextV
    return nextV
end

local function drawDonutWave(layerIdx, layerData, w, h)
    local cx, cy = w * 0.5, h * 0.5
    local baseRadius = math.max(20, math.min(w, h) * 0.34)
    local baseInner = baseRadius * 0.60
    local posNorm = clamp(tonumber(layerData.positionNorm) or 0.0, 0.0, 1.0)

    local peaks = nil
    if type(getLayerPeaksForPath) == "function" then
        peaks = getLayerPeaksForPath("/core/slots/donut", layerIdx, 96)
    else
        peaks = getLayerPeaks(layerIdx, 96)
    end

    local playheadIdx = 1

    -- Keep the original subtle donut radius bounce.
    local bounceTarget = 0.0
    if peaks and #peaks > 0 then
        playheadIdx = math.floor(posNorm * #peaks) + 1
        if playheadIdx < 1 then playheadIdx = 1 end
        if playheadIdx > #peaks then playheadIdx = #peaks end

        local sum = 0.0
        local count = 0
        for k = -1, 1 do
            local j = playheadIdx + k
            if j >= 1 and j <= #peaks then
                sum = sum + clamp(peaks[j] or 0.0, 0.0, 1.0)
                count = count + 1
            end
        end
        local localLevel = count > 0 and (sum / count) or 0.0

        local vol = clamp(tonumber(layerData.volume) or 1.0, 0.0, 1.5)
        local active = (layerData.state == "playing" or layerData.state == "recording" or layerData.state == "overdubbing")
        if active and not layerData.muted then
            bounceTarget = localLevel * vol
        end
    end

    local bounce = easedLayerBounce(layerIdx, bounceTarget)
    local radius = baseRadius + bounce * 2.4
    local inner = baseInner + bounce * 1.2

    drawCircle(cx, cy, radius, 0x22475a75, 72)
    drawCircle(cx, cy, inner, 0x22475a75, 72)

    if peaks and #peaks > 0 then
        gfx.setColour(layerColor(layerData.state))

        -- Grow/shrink waveform lines around the moving playhead.
        local window = 10
        local emphasisAmount = 2.6 * bounce

        for i = 1, #peaks do
            local p = clamp(peaks[i] or 0.0, 0.0, 1.0)

            local d = math.abs(i - playheadIdx)
            d = math.min(d, #peaks - d)

            local influence = 0.0
            if d <= window then
                influence = 1.0 - (d / window)
                influence = influence * influence
            end

            local shaped = clamp(
                p * (1.0 + emphasisAmount * influence) +
                    (0.14 * bounce * influence),
                0.0,
                1.0
            )

            local a = ((i - 1) / #peaks) * math.pi * 2.0 - math.pi * 0.5
            local r1 = inner
            local r2 = inner + shaped * (radius - inner)
            local x1 = cx + math.cos(a) * r1
            local y1 = cy + math.sin(a) * r1
            local x2 = cx + math.cos(a) * r2
            local y2 = cy + math.sin(a) * r2
            gfx.drawLine(x1, y1, x2, y2)
        end
    end

    if (layerData.length or 0) > 0 then
        local a = posNorm * math.pi * 2.0 - math.pi * 0.5
        local x1 = cx + math.cos(a) * (inner - 3)
        local y1 = cy + math.sin(a) * (inner - 3)
        local x2 = cx + math.cos(a) * (radius + 3)
        local y2 = cy + math.sin(a) * (radius + 3)
        gfx.setColour(0xfff8fafc)
        gfx.drawLine(x1, y1, x2, y2)
    end
end

local function seekFromMouse(layerIdx, node, mx, my)
    local w = node:getWidth()
    local h = node:getHeight()
    local cx, cy = w * 0.5, h * 0.5
    local ang = math.atan(my - cy, mx - cx)
    local norm = (ang + math.pi * 0.5) / (math.pi * 2.0)
    if norm < 0.0 then norm = norm + 1.0 end
    if norm >= 1.0 then norm = norm - 1.0 end

    setBehaviorParam("/core/slots/donut/activeLayer", layerIdx)
    setBehaviorParam(layerPath(layerIdx, "seek"), norm)
end

function ui_init(root)
    ui.root = W.Panel.new(root, "donutRoot", { bg = 0xff060b16 })
    ui.header = W.Panel.new(ui.root.node, "header", { bg = 0xff111827, radius = 8 })
    ui.layerBounce = {}

    ui.title = W.Label.new(ui.header.node, "title", {
        text = "Donut Looper Demo",
        colour = 0xff7dd3fc,
        fontSize = 15.0,
        fontStyle = FontStyle.bold,
    })

    ui.reloadBtn = W.Button.new(ui.header.node, "reload", {
        label = "Reload DSP",
        bg = 0xff334155,
        on_click = function() ensureDonutDemoGraphLoaded() end,
    })

    ui.recBtn = W.Button.new(ui.header.node, "rec", {
        label = "● REC",
        bg = 0xff7f1d1d,
        on_click = function()
            setBehaviorParam("/core/slots/donut/recording", recLatched and 0.0 or 1.0)
        end,
    })

    ui.playBtn = W.Button.new(ui.header.node, "play", {
        label = "▶", bg = 0xff14532d,
        on_click = function() setBehaviorParam("/core/slots/donut/transport", 1.0) end,
    })

    ui.pauseBtn = W.Button.new(ui.header.node, "pause", {
        label = "⏸", bg = 0xff78350f,
        on_click = function() setBehaviorParam("/core/slots/donut/transport", 2.0) end,
    })

    ui.stopBtn = W.Button.new(ui.header.node, "stop", {
        label = "⏹", bg = 0xff334155,
        on_click = function() setBehaviorParam("/core/slots/donut/transport", 0.0) end,
    })

    ui.commitBtn = W.Button.new(ui.header.node, "commit", {
        label = "Commit 1", bg = 0xff1d4ed8,
        on_click = function() setBehaviorParam("/core/slots/donut/commit", 1.0) end,
    })

    ui.nextLayerBtn = W.Button.new(ui.header.node, "next", {
        label = "Next Layer", bg = 0xff374151,
        on_click = function()
            local nextIdx = (math.floor(current_state.activeLayer or 0) + 1) % MAX_LAYERS
            setBehaviorParam("/core/slots/donut/activeLayer", nextIdx)
        end,
    })

    ui.tempo = W.NumberBox.new(ui.header.node, "tempo", {
        min = 40, max = 220, step = 1, value = 96,
        label = "BPM", colour = 0xff0ea5e9, format = "%d",
        on_change = function(v) setBehaviorParam("/core/slots/donut/tempo", v) end,
    })

    ui.wet = W.Knob.new(ui.header.node, "wet", {
        min = 0.0, max = 1.0, step = 0.01, value = 0.35,
        label = "Rev Wet", colour = 0xff22d3ee,
        on_change = function(v) setBehaviorParam("/core/slots/donut/fx/reverb/wet", v) end,
    })

    ui.room = W.Knob.new(ui.header.node, "room", {
        min = 0.0, max = 1.0, step = 0.01, value = 0.65,
        label = "Room", colour = 0xffa78bfa,
        on_change = function(v) setBehaviorParam("/core/slots/donut/fx/reverb/room", v) end,
    })

    ui.layers = {}
    for i = 0, MAX_LAYERS - 1 do
        local panel = W.Panel.new(ui.root.node, "layerCard" .. i, {
            bg = 0xff0f172a, border = 0xff1f2937, borderWidth = 1, radius = 8,
        })
        panel.node:setOnClick(function()
            setBehaviorParam("/core/slots/donut/activeLayer", i)
        end)

        local title = W.Label.new(panel.node, "title" .. i, {
            text = "Layer " .. tostring(i), colour = 0xffcbd5e1, fontSize = 12.0,
        })

        local donut = W.Panel.new(panel.node, "donut" .. i, {
            bg = 0x00000000, interceptsMouse = true,
        })

        donut.node:setOnDraw(function(node)
            local layerData = current_state.layers and current_state.layers[i + 1] or {}
            drawDonutWave(i, layerData, node:getWidth(), node:getHeight())
        end)
        donut.node:setOnMouseDown(function(mx, my) seekFromMouse(i, donut.node, mx, my) end)
        donut.node:setOnMouseDrag(function(mx, my, dx, dy) seekFromMouse(i, donut.node, mx, my) end)

        local play = W.Button.new(panel.node, "play" .. i, {
            label = "Play", bg = 0xff14532d,
            on_click = function()
                setBehaviorParam("/core/slots/donut/activeLayer", i)
                setBehaviorParam(layerPath(i, "play"), 1.0)
            end,
        })

        local clear = W.Button.new(panel.node, "clear" .. i, {
            label = "Clear", bg = 0xff7f1d1d,
            on_click = function()
                setBehaviorParam("/core/slots/donut/activeLayer", i)
                setBehaviorParam(layerPath(i, "clear"), 1.0)
            end,
        })

        local mute = W.Button.new(panel.node, "mute" .. i, {
            label = "Mute", bg = 0xff475569,
            on_click = function()
                local layer = current_state.layers and current_state.layers[i + 1] or {}
                setBehaviorParam("/core/slots/donut/activeLayer", i)
                setBehaviorParam(layerPath(i, "mute"), layer.muted and 0.0 or 1.0)
            end,
        })

        table.insert(ui.layers, {
            panel = panel,
            title = title,
            donut = donut,
            play = play,
            clear = clear,
            mute = mute,
            index = i,
        })
    end

    ui.status = W.Label.new(ui.root.node, "status", {
        text = "Ready", colour = 0xff94a3b8, fontSize = 11.0,
    })

    ensureDonutDemoGraphLoaded()
end

function ui_resized(w, h)
    if not ui.root then return end

    ui.root:setBounds(0, 0, w, h)

    local pad = 10
    local headerH = 84
    ui.header:setBounds(pad, pad, w - pad * 2, headerH)

    ui.title:setBounds(10, 6, 220, 24)
    ui.reloadBtn:setBounds(236, 6, 96, 24)
    ui.recBtn:setBounds(10, 34, 80, 40)
    ui.playBtn:setBounds(96, 34, 48, 40)
    ui.pauseBtn:setBounds(148, 34, 48, 40)
    ui.stopBtn:setBounds(200, 34, 48, 40)
    ui.commitBtn:setBounds(254, 34, 94, 40)
    ui.nextLayerBtn:setBounds(352, 34, 110, 40)

    ui.tempo:setBounds(470, 34, 82, 40)
    ui.wet:setBounds(w - 170, 6, 72, 72)
    ui.room:setBounds(w - 90, 6, 72, 72)

    local top = pad + headerH + 8
    local availH = h - top - 28
    local cardGap = 8
    local cardW = math.floor((w - pad * 2 - cardGap) / 2)
    local cardH = math.floor((availH - cardGap) / 2)

    for idx, layer in ipairs(ui.layers) do
        local i = idx - 1
        local col = i % 2
        local row = math.floor(i / 2)
        local x = pad + col * (cardW + cardGap)
        local y = top + row * (cardH + cardGap)

        layer.panel:setBounds(x, y, cardW, cardH)
        layer.title:setBounds(8, 6, 180, 20)
        layer.donut:setBounds(10, 26, cardW - 20, cardH - 64)

        local btnY = cardH - 30
        layer.play:setBounds(10, btnY, 58, 22)
        layer.clear:setBounds(74, btnY, 58, 22)
        layer.mute:setBounds(138, btnY, 58, 22)
    end

    ui.status:setBounds(pad, h - 20, w - pad * 2, 16)
end

function ui_update(s)
    current_state = normalizeState(s)
    recLatched = current_state.recording

    local wetLive = readLiveParam("/core/slots/donut/fx/reverb/wet", current_state.wet or 0.35)
    local roomLive = readLiveParam("/core/slots/donut/fx/reverb/room", current_state.room or 0.65)
    current_state.wet = wetLive
    current_state.room = roomLive

    if ui.recBtn then
        if current_state.recording then
            ui.recBtn:setLabel("● REC*")
            ui.recBtn:setBg(0xffdc2626)
        else
            ui.recBtn:setLabel("● REC")
            ui.recBtn:setBg(0xff7f1d1d)
        end
    end

    if ui.tempo then ui.tempo:setValue(current_state.tempo or 96) end
    if ui.wet and not ui.wet._dragging then ui.wet:setValue(wetLive) end
    if ui.room and not ui.room._dragging then ui.room:setValue(roomLive) end

    for _, layer in ipairs(ui.layers) do
        local data = current_state.layers and current_state.layers[layer.index + 1] or {}
        local active = (current_state.activeLayer or 0) == layer.index

        layer.panel:setStyle({
            bg = active and 0xff14243a or 0xff0f172a,
            border = active and 0xff38bdf8 or 0xff1f2937,
            borderWidth = active and 2 or 1,
        })

        local stateText = tostring(data.state or "stopped")
        layer.title:setText(string.format("Layer %d  •  %s", layer.index, stateText))
        layer.title:setColour(active and 0xffe0f2fe or 0xffcbd5e1)

        if data.state == "playing" then
            layer.play:setLabel("Pause")
            layer.play:setBg(0xffb45309)
            layer.play._onClick = function()
                setBehaviorParam("/core/slots/donut/activeLayer", layer.index)
                setBehaviorParam(layerPath(layer.index, "pause"), 1.0)
            end
        else
            layer.play:setLabel("Play")
            layer.play:setBg(0xff14532d)
            layer.play._onClick = function()
                setBehaviorParam("/core/slots/donut/activeLayer", layer.index)
                setBehaviorParam(layerPath(layer.index, "play"), 1.0)
            end
        end

        if data.muted then
            layer.mute:setLabel("Muted")
            layer.mute:setBg(0xffdc2626)
        else
            layer.mute:setLabel("Mute")
            layer.mute:setBg(0xff475569)
        end
    end

    if ui.status then
        local dspReady = endpointExists("/core/slots/donut/fx/reverb/wet")
        local loadState = (ui.dspLoaded and ui.graphEnabled and dspReady) and "DSP ready" or "DSP not ready"
        local err = ui.dspLoadError
        if type(err) == "string" and #err > 0 then
            if #err > 80 then err = string.sub(err, 1, 80) .. "..." end
            loadState = loadState .. " | " .. err
        end

        ui.status:setText(string.format(
            "Donut demo  |  BPM %.1f  |  Active L%d  |  Reverb wet %.2f room %.2f  |  %s",
            current_state.tempo or 96,
            math.floor(current_state.activeLayer or 0),
            current_state.wet or 0.35,
            current_state.room or 0.65,
            loadState
        ))
    end
end

function ui_cleanup()
    -- Keep donut looper slot alive across UI switches.
    setDonutSlotPersistOnSwitch(true)

    -- But disable live-input FX routing when this UI is not active so input
    -- processing does not persist unintentionally across UIs.
    setDonutInputMonitorEnabled(false)
end

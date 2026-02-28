-- firstloop_ui.lua
-- First Loop Tempo Detector - Minimal UI

local W = require("looper_widgets")

local ui = {}
local isDetecting = false
local showSettings = false

function ui_init(root)
    -- Root panel
    ui.rootPanel = W.Panel.new(root, "rootPanel", {
        bg = 0xff0a0f1a,
    })

    -- ==========================================================================
    -- Top Ribbon (all status info)
    -- ==========================================================================
    ui.ribbonPanel = W.Panel.new(ui.rootPanel.node, "ribbon", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })

    -- Tempo display (large, prominent)
    ui.tempoValue = W.Label.new(ui.ribbonPanel.node, "tempoValue", {
        text = "120.0",
        colour = 0xff34d399,
        fontSize = 36.0,
        fontStyle = FontStyle.bold,
    })

    ui.tempoUnit = W.Label.new(ui.ribbonPanel.node, "tempoUnit", {
        text = "BPM",
        colour = 0xff64748b,
        fontSize = 11.0,
    })

    -- Bars display
    ui.barsValue = W.Label.new(ui.ribbonPanel.node, "barsValue", {
        text = "2",
        colour = 0xff38bdf8,
        fontSize = 36.0,
        fontStyle = FontStyle.bold,
    })

    ui.barsUnit = W.Label.new(ui.ribbonPanel.node, "barsUnit", {
        text = "bars",
        colour = 0xff64748b,
        fontSize = 11.0,
    })

    -- Link indicator (styled like Manifold - circle + text)
    ui.linkIndicator = W.Label.new(ui.ribbonPanel.node, "linkIndicator", {
        text = "○ link",
        colour = 0xff4b5563, -- gray when disabled
        fontSize = 16.0,
        fontStyle = FontStyle.bold,
    })

    -- Settings button (small, top-right of ribbon)
    ui.settingsBtn = W.Button.new(ui.ribbonPanel.node, "settings", {
        label = "⚙",
        bg = 0xff1e293b,
        fontSize = 14.0,
        on_click = function()
            showSettings = not showSettings
            updateVisibility()
        end,
    })

    -- ==========================================================================
    -- Main Content (big detect button)
    -- ==========================================================================
    ui.contentPanel = W.Panel.new(ui.rootPanel.node, "content", {
        bg = 0x00000000, -- transparent
    })

    -- Big DETECT button
    ui.detectBtn = W.Button.new(ui.contentPanel.node, "detect", {
        label = "● DETECT",
        bg = 0xff7f1d1d,
        fontSize = 24.0,
        on_press = function()
            if isDetecting then
                setParam("/firstloop/detecting", 0)
                isDetecting = false
            else
                setParam("/firstloop/detecting", 1)
                isDetecting = true
            end
            updateDetectButton()
        end,
    })

    -- Duration label (shows during detection)
    ui.durationLabel = W.Label.new(ui.contentPanel.node, "duration", {
        text = "",
        colour = 0xff94a3b8,
        fontSize = 14.0,
    })

    -- ==========================================================================
    -- Settings Panel (overlay, initially hidden)
    -- ==========================================================================
    ui.settingsPanel = W.Panel.new(ui.rootPanel.node, "settingsPanel", {
        bg = 0xff141a24,
        border = 0xff334155,
        borderWidth = 2,
        radius = 8,
    })

    -- Settings title
    ui.settingsTitle = W.Label.new(ui.settingsPanel.node, "settingsTitle", {
        text = "SETTINGS",
        colour = 0xff7dd3fc,
        fontSize = 14.0,
        fontStyle = FontStyle.bold,
    })

    -- Close button
    ui.closeSettingsBtn = W.Button.new(ui.settingsPanel.node, "closeSettings", {
        label = "✕",
        bg = 0xff374151,
        fontSize = 12.0,
        on_click = function()
            showSettings = false
            updateVisibility()
        end,
    })

    -- Target BPM
    ui.targetBox = W.NumberBox.new(ui.settingsPanel.node, "targetBpm", {
        min = 40, max = 240, step = 1, value = 120,
        label = "Target BPM", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v)
            setParam("/firstloop/targetbpm", v)
        end,
    })

    -- Link enabled toggle
    ui.linkToggle = W.Toggle.new(ui.settingsPanel.node, "linkToggle", {
        label = "Link Enabled",
        value = true,
        onColour = 0xfff59e0b,
        offColour = 0xff475569,
        on_change = function(on)
            setParam("/firstloop/linkenabled", on and 1 or 0)
        end,
    })

    -- Link status in settings
    ui.linkStatusLabel = W.Label.new(ui.settingsPanel.node, "linkStatus", {
        text = "Link: disabled",
        colour = 0xff64748b,
        fontSize = 11.0,
    })

    ui_resized(root:getWidth(), root:getHeight())
    updateVisibility()
end

function updateVisibility()
    -- Toggle settings panel by moving it off-screen or setting size to 0
    if showSettings then
        -- Settings will be sized normally in ui_resized
        ui_resized(ui.rootPanel.node:getWidth(), ui.rootPanel.node:getHeight())
    else
        -- Hide settings by setting size to 0
        ui.settingsPanel:setBounds(0, 0, 0, 0)
    end
end

function updateDetectButton()
    if isDetecting then
        ui.detectBtn:setBg(0xffdc2626) -- bright red when recording
        ui.detectBtn:setLabel("■ STOP")
        ui.durationLabel:setText("Recording...")
        ui.durationLabel:setColour(0xffef4444)
    else
        ui.detectBtn:setBg(0xff7f1d1d) -- dark red when idle
        ui.detectBtn:setLabel("● DETECT")
        ui.durationLabel:setText("")
        ui.durationLabel:setColour(0xff94a3b8)
    end
end

function ui_resized(w, h)
    if not ui.rootPanel then return end

    ui.rootPanel:setBounds(0, 0, w, h)

    -- Ribbon at top (edge to edge, no padding)
    local ribbonH = 72
    ui.ribbonPanel:setBounds(0, 0, w, ribbonH)

    -- Layout ribbon contents with proper spacing (full width)
    -- Tempo column (left side)
    ui.tempoValue:setBounds(16, 8, 100, 42)
    ui.tempoUnit:setBounds(16, 50, 100, 16)

    -- Bars column (middle-left)
    ui.barsValue:setBounds(130, 8, 80, 42)
    ui.barsUnit:setBounds(130, 50, 80, 16)

    -- Link indicator (middle-right, centered vertically)
    ui.linkIndicator:setBounds(220, 20, 120, 32)

    -- Settings button (far right)
    ui.settingsBtn:setBounds(w - 48, 16, 40, 40)

    -- Content panel (below ribbon, edge to edge horizontally, small margin vertically)
    local contentMargin = 16
    local contentY = ribbonH + 8
    local contentH = h - contentY - contentMargin
    ui.contentPanel:setBounds(contentMargin, contentY, w - contentMargin * 2, contentH)

    -- Big detect button (centered in content)
    local contentW = w - contentMargin * 2
    local btnW = math.min(240, contentW - 40)
    local btnH = 72
    local btnX = (contentW - btnW) / 2
    local btnY = (contentH - btnH) / 2 - 10
    ui.detectBtn:setBounds(btnX, btnY, btnW, btnH)

    -- Duration label below button
    ui.durationLabel:setBounds(0, btnY + btnH + 12, contentW, 24)

    -- Settings panel (same bounds as content, or hidden)
    if showSettings then
        ui.settingsPanel:setBounds(contentMargin, contentY, contentW, contentH)

        -- Settings layout
        local sMargin = 20
        local sY = 16

        ui.settingsTitle:setBounds(sMargin, sY, 150, 24)
        ui.closeSettingsBtn:setBounds(contentW - 48, sY, 32, 32)
        sY = sY + 48

        ui.targetBox:setBounds(sMargin, sY, contentW - sMargin * 2, 50)
        sY = sY + 64

        ui.linkToggle:setBounds(sMargin, sY, 160, 36)
        sY = sY + 48

        ui.linkStatusLabel:setBounds(sMargin, sY, contentW - sMargin * 2, 20)
    else
        ui.settingsPanel:setBounds(0, 0, 0, 0)
    end
end

function ui_update(s)
    local params = s.params or {}

    -- Update tempo display
    local tempo = params["/firstloop/tempo"] or 120
    ui.tempoValue:setText(string.format("%.1f", tempo))

    -- Update bars display
    local bars = params["/firstloop/detectedbars"] or 2
    if bars == math.floor(bars) then
        ui.barsValue:setText(string.format("%d", math.floor(bars)))
    else
        ui.barsValue:setText(string.format("%.2f", bars))
    end

    -- Update detecting state
    local detecting = params["/firstloop/detecting"] or 0
    isDetecting = (detecting > 0.5)
    updateDetectButton()

    -- Update Link indicator (styled like Manifold)
    local linkEnabled = params["/firstloop/linkenabled"] or 0
    local peers = params["/firstloop/linkpeers"] or 0

    if linkEnabled > 0.5 then
        if peers > 0 then
            -- Enabled with peers - green
            ui.linkIndicator:setText("● LINK " .. math.floor(peers))
            ui.linkIndicator:setColour(0xff4ade80)
        else
            -- Enabled no peers - amber
            ui.linkIndicator:setText("● LINK")
            ui.linkIndicator:setColour(0xfff59e0b)
        end
    else
        -- Disabled - gray
        ui.linkIndicator:setText("○ link")
        ui.linkIndicator:setColour(0xff4b5563)
    end

    -- Update settings panel values
    local target = params["/firstloop/targetbpm"] or 120
    ui.targetBox:setValue(target)
    ui.linkToggle:setValue(linkEnabled > 0.5)

    if linkEnabled > 0.5 then
        if peers > 0 then
            ui.linkStatusLabel:setText("Link: enabled, " .. math.floor(peers) .. " peer(s)")
            ui.linkStatusLabel:setColour(0xff4ade80)
        else
            ui.linkStatusLabel:setText("Link: enabled, no peers")
            ui.linkStatusLabel:setColour(0xfff59e0b)
        end
    else
        ui.linkStatusLabel:setText("Link: disabled")
        ui.linkStatusLabel:setColour(0xff64748b)
    end
end

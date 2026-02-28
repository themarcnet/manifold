-- looper_settings_ui.lua
-- OSC Settings UI with Casio-style status display at top

local W = require("looper_widgets")

-- ============================================================================
-- State
-- ============================================================================
local ui = {}
local settings = {}
local statusMessage = "Ready"
local statusTime = 0

-- ============================================================================
-- Helpers
-- ============================================================================

local function showStatus(msg)
    statusMessage = msg
    statusTime = getTime()
end

local function isValidPort(port)
    return port and port >= 1024 and port <= 65535
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
    -- Header: Title
    -- ==========================================================================
    ui.headerPanel = W.Panel.new(ui.rootPanel.node, "header", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })

    ui.titleLabel = W.Label.new(ui.headerPanel.node, "title", {
        text = "OSC SETTINGS",
        colour = 0xff7dd3fc,
        fontSize = 20.0,
        fontStyle = FontStyle.bold,
    })

    -- ==========================================================================
    -- Status Display (Casio-style LCD at top)
    -- ==========================================================================
    ui.statusPanel = W.Panel.new(ui.rootPanel.node, "statusPanel", {
        bg = 0xff1a2b1a,  -- Dark green LCD background
        border = 0xff2d4a2d,
        borderWidth = 2,
    })

    ui.statusDisplay = W.Label.new(ui.statusPanel.node, "statusDisplay", {
        text = "Ready",
        colour = 0xff4ade80,  -- LCD green text
        fontSize = 14.0,
        fontStyle = FontStyle.bold,
    })

    -- ==========================================================================
    -- OSC Settings Section
    -- ==========================================================================
    ui.oscPanel = W.Panel.new(ui.rootPanel.node, "oscPanel", {
        bg = 0xff141a24,
        radius = 8,
    })

    ui.oscLabel = W.Label.new(ui.oscPanel.node, "oscLabel", {
        text = "OSC (UDP)",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    -- OSC Port input
    ui.oscPortBox = W.NumberBox.new(ui.oscPanel.node, "oscPort", {
        min = 1024, max = 65535, step = 1, value = 9000,
        label = "Port", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) end,  -- Just update local state
    })

    -- OSC Enable toggle
    ui.oscToggle = W.Toggle.new(ui.oscPanel.node, "oscToggle", {
        label = "Enabled",
        value = true,
        colour = 0xff34d399,
        bg = 0xff1e293b,
        on_change = function(v) end,
    })

    -- ==========================================================================
    -- OSCQuery Settings Section
    -- ==========================================================================
    ui.queryPanel = W.Panel.new(ui.rootPanel.node, "queryPanel", {
        bg = 0xff141a24,
        radius = 8,
    })

    ui.queryLabel = W.Label.new(ui.queryPanel.node, "queryLabel", {
        text = "OSCQuery (HTTP)",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    -- OSCQuery Port input
    ui.queryPortBox = W.NumberBox.new(ui.queryPanel.node, "queryPort", {
        min = 1024, max = 65535, step = 1, value = 9001,
        label = "Port", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) end,
    })

    -- OSCQuery Enable toggle
    ui.queryToggle = W.Toggle.new(ui.queryPanel.node, "queryToggle", {
        label = "Enabled",
        value = true,
        colour = 0xff34d399,
        bg = 0xff1e293b,
        on_change = function(v) end,
    })

    -- ==========================================================================
    -- Ableton Link Section
    -- ==========================================================================
    ui.linkPanel = W.Panel.new(ui.rootPanel.node, "linkPanel", {
        bg = 0xff141a24,
        radius = 8,
    })

    ui.linkLabel = W.Label.new(ui.linkPanel.node, "linkLabel", {
        text = "Ableton Link",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    -- Link enabled toggle
    ui.linkToggle = W.Toggle.new(ui.linkPanel.node, "linkToggle", {
        label = "Enabled",
        value = false,
        colour = 0xfff59e0b,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setEnabled(v) end
        end,
    })

    -- Tempo sync toggle
    ui.linkTempoToggle = W.Toggle.new(ui.linkPanel.node, "linkTempo", {
        label = "Tempo Sync",
        value = true,
        colour = 0xff38bdf8,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setTempoSyncEnabled(v) end
        end,
    })

    -- Start/stop sync toggle
    ui.linkStartStopToggle = W.Toggle.new(ui.linkPanel.node, "linkStartStop", {
        label = "Start/Stop Sync",
        value = true,
        colour = 0xffa78bfa,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setStartStopSyncEnabled(v) end
        end,
    })

    -- Peers indicator
    ui.linkPeersLabel = W.Label.new(ui.linkPanel.node, "linkPeers", {
        text = "0 peers",
        colour = 0xff64748b,
        fontSize = 10.0,
    })

    -- ==========================================================================
    -- Targets Section
    -- ==========================================================================
    ui.targetsPanel = W.Panel.new(ui.rootPanel.node, "targetsPanel", {
        bg = 0xff141a24,
        radius = 8,
    })

    ui.targetsLabel = W.Label.new(ui.targetsPanel.node, "targetsLabel", {
        text = "Broadcast Targets",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    -- Target list will be drawn manually (dynamic list)
    ui.targetListOverlay = ui.targetsPanel.node:addChild("targetList")
    ui.targetAddOverlay = ui.targetsPanel.node:addChild("targetAdd")

    -- New target input (ip:port)
    ui.newTargetLabel = W.Label.new(ui.targetsPanel.node, "newTargetLabel", {
        text = "Add target (ip:port):",
        colour = 0xff64748b,
        fontSize = 10.0,
    })

    -- We'll use a simple text input simulation with NumberBox for port part
    -- Actually let's just have an "Add" button that prompts
    ui.addTargetBtn = W.Button.new(ui.targetsPanel.node, "addTarget", {
        label = "+ Add Target",
        bg = 0xff1e7a3a,
        fontSize = 11.0,
        on_click = function()
            -- For now, just add a hardcoded test target
            -- In full UI, this would open an input dialog
            showStatus("Add: use osc.addTarget()")
        end,
    })

    -- ==========================================================================
    -- Apply Button
    -- ==========================================================================
    ui.applyBtn = W.Button.new(ui.rootPanel.node, "apply", {
        label = "APPLY SETTINGS",
        bg = 0xff2563eb,  -- Blue
        fontSize = 14.0,
        on_click = function()
            local newSettings = {
                inputPort = math.floor(ui.oscPortBox:getValue()),
                queryPort = math.floor(ui.queryPortBox:getValue()),
                oscEnabled = ui.oscToggle:getValue(),
                oscQueryEnabled = ui.queryToggle:getValue(),
                outTargets = {}  -- We'll keep existing targets for now
            }

            -- Validate ports
            if not isValidPort(newSettings.inputPort) then
                showStatus("ERR: OSC port must be 1024-65535")
                return
            end
            if not isValidPort(newSettings.queryPort) then
                showStatus("ERR: OSCQuery port must be 1024-65535")
                return
            end
            if newSettings.inputPort == newSettings.queryPort then
                showStatus("ERR: Ports must be different")
                return
            end

            -- Apply settings
            if osc.setSettings(newSettings) then
                showStatus("Settings saved & applied")
            else
                showStatus("ERR: Failed to save settings")
            end
        end,
    })

    -- ==========================================================================
    -- Load current settings
    -- ==========================================================================
    local current = osc.getSettings()
    if current then
        ui.oscPortBox:setValue(current.inputPort or 9000)
        ui.queryPortBox:setValue(current.queryPort or 9001)
        ui.oscToggle:setValue(current.oscEnabled ~= false)
        ui.queryToggle:setValue(current.oscQueryEnabled ~= false)
    end

    -- Load Link settings
    if link then
        ui.linkToggle:setValue(link.isEnabled())
        ui.linkTempoToggle:setValue(link.isTempoSyncEnabled())
        ui.linkStartStopToggle:setValue(link.isStartStopSyncEnabled())
    end

    ui_resized(root:getWidth(), root:getHeight())
end

-- ============================================================================
-- Layout
-- ============================================================================

function ui_resized(w, h)
    local margin = 12
    local panelW = w - margin * 2
    local rowH = 36
    local sectionSpacing = 16

    -- Root fills entire area
    ui.rootPanel.node:setBounds(0, 0, w, h)

    -- Header
    ui.headerPanel.node:setBounds(margin, margin, panelW, 44)
    ui.titleLabel.node:setBounds(12, 10, panelW - 24, 24)

    local y = margin + 44 + sectionSpacing

    -- Status display (Casio LCD style)
    ui.statusPanel.node:setBounds(margin, y, panelW, 48)
    ui.statusDisplay.node:setBounds(12, 14, panelW - 24, 20)
    y = y + 48 + sectionSpacing

    -- OSC Settings
    ui.oscPanel.node:setBounds(margin, y, panelW, 80)
    ui.oscLabel.node:setBounds(12, 8, 150, 18)
    ui.oscPortBox.node:setBounds(12, 36, 120, 32)
    ui.oscToggle.node:setBounds(panelW - 100, 36, 88, 32)
    y = y + 80 + sectionSpacing

    -- OSCQuery Settings
    ui.queryPanel.node:setBounds(margin, y, panelW, 80)
    ui.queryLabel.node:setBounds(12, 8, 150, 18)
    ui.queryPortBox.node:setBounds(12, 36, 120, 32)
    ui.queryToggle.node:setBounds(panelW - 100, 36, 88, 32)
    y = y + 80 + sectionSpacing

    -- Ableton Link Section
    ui.linkPanel.node:setBounds(margin, y, panelW, 100)
    ui.linkLabel.node:setBounds(12, 8, 120, 18)
    ui.linkToggle.node:setBounds(panelW - 100, 8, 88, 28)
    ui.linkTempoToggle.node:setBounds(12, 44, 130, 28)
    ui.linkStartStopToggle.node:setBounds(150, 44, 150, 28)
    ui.linkPeersLabel.node:setBounds(12, 76, 100, 16)
    y = y + 100 + sectionSpacing

    -- Targets Section
    ui.targetsPanel.node:setBounds(margin, y, panelW, 100)
    ui.targetsLabel.node:setBounds(12, 8, 150, 18)
    ui.addTargetBtn.node:setBounds(12, 40, 100, 28)
    
    -- Apply button at bottom
    ui.applyBtn.node:setBounds(margin, h - 60, panelW, 48)
    
    -- Setup target list drawing
    setupTargetList(panelW, 100)
end

-- ============================================================================
-- Target List Drawing
-- ============================================================================

function setupTargetList(panelW, height)
    local targets = {}
    local current = osc.getSettings()
    if current and current.outTargets then
        for i, t in ipairs(current.outTargets) do
            targets[i] = t
        end
    end

    ui.targetListOverlay:setBounds(12, 76, panelW - 24, height)
    ui.targetListOverlay:setOnDraw(function(self)
        local w = self:getWidth()
        local h = self:getHeight()
        local itemH = 28

        -- Draw targets
        for i, target in ipairs(targets) do
            local y = (i - 1) * itemH

            -- Target text
            gfx.setColour(0xffe2e8f0)
            gfx.setFont(11.0)
            gfx.drawText(target, 8, y, w - 50, itemH - 4, Justify.centredLeft)

            -- Remove button
            gfx.setColour(0xff7f1d1d)
            gfx.fillRoundedRect(w - 40, y + 2, 36, itemH - 4, 4)
            gfx.setColour(0xffffffff)
            gfx.setFont(10.0)
            gfx.drawText("×", w - 36, y + 4, 28, itemH - 8, Justify.centred)
        end

        -- Empty message
        if #targets == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No targets configured", 8, 20, w - 16, 20, Justify.centred)
        end
    end)

    ui.targetListOverlay:setOnMouseDown(function(mx, my)
        local w = ui.targetListOverlay:getWidth()
        local itemH = 28
        local idx = math.floor(my / itemH) + 1

        -- Check if remove button clicked (last 40 pixels)
        if mx > w - 40 and idx <= #targets then
            local target = targets[idx]
            if target then
                osc.removeTarget(target)
                showStatus("Removed: " .. target)
                -- Refresh
                setupTargetList(panelW, height)
            end
        end
    end)
end

-- ============================================================================
-- Update Loop
-- ============================================================================

function ui_update(state)
    -- Update status display
    if getTime() - statusTime < 3 then
        ui.statusDisplay:setText(statusMessage)
    else
        -- Show server status
        local srvStatus = osc.getStatus()
        if srvStatus == "running" then
            ui.statusDisplay:setText("OSC: Running | Ports: " .. ui.oscPortBox:getValue() .. "/" .. ui.queryPortBox:getValue())
        else
            ui.statusDisplay:setText("OSC: " .. srvStatus)
        end
    end

    -- Update Link peers indicator
    if link then
        local peers = link.getNumPeers()
        if peers == 0 then
            ui.linkPeersLabel:setText("No peers")
        elseif peers == 1 then
            ui.linkPeersLabel:setText("1 peer")
        else
            ui.linkPeersLabel:setText(peers .. " peers")
        end
    end
end

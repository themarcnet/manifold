-- manifold_settings_ui.lua
-- Multi-tab settings UI with scrollable content and user directory config

local W = require("ui_widgets")

-- ============================================================================
-- State
-- ============================================================================
local ui = {}
local uiState = {}
local statusMessage = "Ready"
local statusTime = 0
local currentTab = "osc"  -- osc, link, paths, midi
local scrollOffsets = { osc = 0, link = 0, paths = 0, midi = 0 }
local contentHeights = { osc = 0, link = 0, paths = 0, midi = 0 }

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

local function getSettingsDir()
    -- Get the settings directory from the Settings class
    local home = os.getenv("HOME") or "/tmp"
    return home .. "/.config/Manifold"
end

-- ============================================================================
-- Tab Button Creation
-- ============================================================================

local function createTabButton(parent, id, label, x, y, w, h, onClick)
    local btn = W.Button.new(parent, id, {
        label = label,
        bg = (currentTab == id) and 0xff2563eb or 0xff1e293b,
        fontSize = 12.0,
        on_click = onClick,
    })
    btn.node:setBounds(x, y, w, h)
    return btn
end

-- ============================================================================
-- Scrollable Panel Setup
-- ============================================================================

local function setupScrollableContent(contentNode, contentContainer, contentH)
    contentHeights[currentTab] = contentH
    
    -- Scrollbar overlay
    local scrollBar = contentNode:addChild("scrollBar")
    scrollBar:setBounds(contentNode:getWidth() - 12, 0, 8, contentNode:getHeight())
    
    local function updateScroll()
        local h = contentNode:getHeight()
        local ch = contentHeights[currentTab] or h
        local maxScroll = math.max(0, ch - h)
        -- Apply scroll offset to content container (negative to move up)
        contentContainer:setBounds(0, -math.floor(scrollOffsets[currentTab]), contentNode:getWidth(), math.max(ch, h))
    end
    
    scrollBar:setOnDraw(function(self)
        local h = self:getHeight()
        local ch = contentHeights[currentTab] or h
        if ch <= h then return end
        
        -- Track
        gfx.setColour(0xff1e293b)
        gfx.fillRoundedRect(0, 0, 8, h, 4)
        
        -- Thumb
        local thumbH = math.max(30, h * (h / ch))
        local maxScroll = ch - h
        local thumbY = 0
        if maxScroll > 0 then
            thumbY = (scrollOffsets[currentTab] / maxScroll) * (h - thumbH)
        end
        thumbY = math.max(0, math.min(h - thumbH, thumbY))
        
        gfx.setColour(0xff475569)
        gfx.fillRoundedRect(0, thumbY, 8, thumbH, 4)
    end)
    
    scrollBar:setOnMouseDown(function(mx, my)
        local h = scrollBar:getHeight()
        local ch = contentHeights[currentTab] or h
        if ch <= h then return end
        
        local maxScroll = ch - h
        scrollOffsets[currentTab] = (my / h) * maxScroll
        scrollOffsets[currentTab] = math.max(0, math.min(maxScroll, scrollOffsets[currentTab]))
        updateScroll()
    end)
    
    -- Mouse wheel on scrollbar too (in case it's over the scrollbar area)
    scrollBar:setOnMouseWheel(function(mx, my, dy)
        local _ = mx
        _ = my
        local h = contentNode:getHeight()
        local ch = contentHeights[currentTab] or h
        if ch <= h then return end
        
        local maxScroll = ch - h
        if dy > 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] - 30
        elseif dy < 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] + 30
        end
        scrollOffsets[currentTab] = math.max(0, math.min(maxScroll, scrollOffsets[currentTab]))
        updateScroll()
    end)
    
    -- Mouse wheel support on content node
    contentNode:setOnMouseWheel(function(mx, my, dy)
        local _ = mx
        _ = my
        local h = contentNode:getHeight()
        local ch = contentHeights[currentTab] or h
        if ch <= h then return end
        
        local maxScroll = ch - h
        if dy > 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] - 30
        elseif dy < 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] + 30
        end
        scrollOffsets[currentTab] = math.max(0, math.min(maxScroll, scrollOffsets[currentTab]))
        updateScroll()
    end)
    
    -- Mouse wheel support on content container (the actual content)
    contentContainer:setOnMouseWheel(function(mx, my, dy)
        local _ = mx
        _ = my
        local h = contentNode:getHeight()
        local ch = contentHeights[currentTab] or h
        if ch <= h then return end
        
        local maxScroll = ch - h
        if dy > 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] - 30
        elseif dy < 0 then
            scrollOffsets[currentTab] = scrollOffsets[currentTab] + 30
        end
        scrollOffsets[currentTab] = math.max(0, math.min(maxScroll, scrollOffsets[currentTab]))
        updateScroll()
    end)
    
    -- Initial scroll position
    updateScroll()
end

-- ============================================================================
-- OSC Tab Content
-- ============================================================================

local function buildOscTab(parent, w, h)
    local y = 0
    local margin = 12
    local panelW = w - margin * 2 - 16  -- Account for scrollbar
    local rowH = 36
    local sectionSpacing = 16
    
    -- Status display (Casio LCD style)
    ui.statusPanel = W.Panel.new(parent, "statusPanel", {
        bg = 0xff1a2b1a,
        border = 0xff2d4a2d,
        borderWidth = 2,
    })
    ui.statusPanel.node:setBounds(margin, y, panelW, 48)
    
    ui.statusDisplay = W.Label.new(ui.statusPanel.node, "statusDisplay", {
        text = "Ready",
        colour = 0xff4ade80,
        fontSize = 14.0,
        fontStyle = FontStyle.bold,
    })
    ui.statusDisplay.node:setBounds(12, 14, panelW - 24, 20)
    y = y + 48 + sectionSpacing
    
    -- OSC Settings
    ui.oscPanel = W.Panel.new(parent, "oscPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.oscPanel.node:setBounds(margin, y, panelW, 80)
    
    ui.oscLabel = W.Label.new(ui.oscPanel.node, "oscLabel", {
        text = "OSC (UDP)",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.oscLabel.node:setBounds(12, 8, 150, 18)
    
    ui.oscPortBox = W.NumberBox.new(ui.oscPanel.node, "oscPort", {
        min = 1024, max = 65535, step = 1, value = 9000,
        label = "Port", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) end,
    })
    ui.oscPortBox.node:setBounds(12, 36, 120, 32)
    
    ui.oscToggle = W.Toggle.new(ui.oscPanel.node, "oscToggle", {
        label = "Enabled",
        value = true,
        colour = 0xff34d399,
        bg = 0xff1e293b,
        on_change = function(v) end,
    })
    ui.oscToggle.node:setBounds(panelW - 100, 36, 88, 32)
    y = y + 80 + sectionSpacing
    
    -- OSCQuery Settings
    ui.queryPanel = W.Panel.new(parent, "queryPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.queryPanel.node:setBounds(margin, y, panelW, 80)
    
    ui.queryLabel = W.Label.new(ui.queryPanel.node, "queryLabel", {
        text = "OSCQuery (HTTP)",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.queryLabel.node:setBounds(12, 8, 150, 18)
    
    ui.queryPortBox = W.NumberBox.new(ui.queryPanel.node, "queryPort", {
        min = 1024, max = 65535, step = 1, value = 9001,
        label = "Port", suffix = "",
        colour = 0xff38bdf8,
        format = "%d",
        on_change = function(v) end,
    })
    ui.queryPortBox.node:setBounds(12, 36, 120, 32)
    
    ui.queryToggle = W.Toggle.new(ui.queryPanel.node, "queryToggle", {
        label = "Enabled",
        value = true,
        colour = 0xff34d399,
        bg = 0xff1e293b,
        on_change = function(v) end,
    })
    ui.queryToggle.node:setBounds(panelW - 100, 36, 88, 32)
    y = y + 80 + sectionSpacing
    
    -- Broadcast Targets
    ui.targetsPanel = W.Panel.new(parent, "targetsPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.targetsPanel.node:setBounds(margin, y, panelW, 140)
    
    ui.targetsLabel = W.Label.new(ui.targetsPanel.node, "targetsLabel", {
        text = "Broadcast Targets",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.targetsLabel.node:setBounds(12, 8, 150, 18)
    
    ui.addTargetBtn = W.Button.new(ui.targetsPanel.node, "addTarget", {
        label = "+ Add Target",
        bg = 0xff1e7a3a,
        fontSize = 11.0,
        on_click = function()
            showStatus("Use osc.addTarget() in console")
        end,
    })
    ui.addTargetBtn.node:setBounds(12, 36, 100, 28)
    
    ui.targetListOverlay = ui.targetsPanel.node:addChild("targetList")
    setupTargetList(panelW, 140)
    y = y + 140 + sectionSpacing
    
    -- Apply button
    ui.applyBtn = W.Button.new(parent, "apply", {
        label = "APPLY SETTINGS",
        bg = 0xff2563eb,
        fontSize = 14.0,
        on_click = function()
            local newSettings = {
                inputPort = math.floor(ui.oscPortBox:getValue()),
                queryPort = math.floor(ui.queryPortBox:getValue()),
                oscEnabled = ui.oscToggle:getValue(),
                oscQueryEnabled = ui.queryToggle:getValue(),
                outTargets = {}
            }
            
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
            
            if osc.setSettings(newSettings) then
                showStatus("Settings saved & applied")
            else
                showStatus("ERR: Failed to save settings")
            end
        end,
    })
    ui.applyBtn.node:setBounds(margin, y, panelW, 48)
    y = y + 48 + sectionSpacing
    
    return y
end

-- ============================================================================
-- Link Tab Content
-- ============================================================================

local function buildLinkTab(parent, w, h)
    local y = 0
    local margin = 12
    local panelW = w - margin * 2 - 16
    local sectionSpacing = 16
    
    -- Link Status Panel
    ui.linkStatusPanel = W.Panel.new(parent, "linkStatusPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.linkStatusPanel.node:setBounds(margin, y, panelW, 60)
    
    ui.linkStatusLabel = W.Label.new(ui.linkStatusPanel.node, "linkStatus", {
        text = "Ableton Link",
        colour = 0xff94a3b8,
        fontSize = 14.0,
        fontStyle = FontStyle.bold,
    })
    ui.linkStatusLabel.node:setBounds(12, 8, 150, 20)
    
    ui.linkPeersLabel = W.Label.new(ui.linkStatusPanel.node, "linkPeers", {
        text = "0 peers",
        colour = 0xff64748b,
        fontSize = 12.0,
    })
    ui.linkPeersLabel.node:setBounds(12, 32, 150, 20)
    y = y + 60 + sectionSpacing
    
    -- Link Settings
    ui.linkPanel = W.Panel.new(parent, "linkPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.linkPanel.node:setBounds(margin, y, panelW, 140)
    
    ui.linkLabel = W.Label.new(ui.linkPanel.node, "linkLabel", {
        text = "Link Settings",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.linkLabel.node:setBounds(12, 8, 120, 18)
    
    ui.linkToggle = W.Toggle.new(ui.linkPanel.node, "linkToggle", {
        label = "Link Enabled",
        value = true,
        colour = 0xfff59e0b,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setEnabled(v) end
        end,
    })
    ui.linkToggle.node:setBounds(12, 36, 140, 28)
    
    ui.linkTempoToggle = W.Toggle.new(ui.linkPanel.node, "linkTempo", {
        label = "Tempo Sync",
        value = true,
        colour = 0xff38bdf8,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setTempoSyncEnabled(v) end
        end,
    })
    ui.linkTempoToggle.node:setBounds(12, 72, 140, 28)
    
    ui.linkStartStopToggle = W.Toggle.new(ui.linkPanel.node, "linkStartStop", {
        label = "Start/Stop Sync",
        value = true,
        colour = 0xffa78bfa,
        bg = 0xff1e293b,
        on_change = function(v)
            if link then link.setStartStopSyncEnabled(v) end
        end,
    })
    ui.linkStartStopToggle.node:setBounds(160, 72, 150, 28)
    y = y + 140 + sectionSpacing
    
    -- Tempo Display
    ui.tempoPanel = W.Panel.new(parent, "tempoPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.tempoPanel.node:setBounds(margin, y, panelW, 80)
    
    ui.tempoLabel = W.Label.new(ui.tempoPanel.node, "tempoLabel", {
        text = "Current Tempo",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.tempoLabel.node:setBounds(12, 8, 120, 18)
    
    ui.tempoDisplay = W.Label.new(ui.tempoPanel.node, "tempoDisplay", {
        text = "120.0 BPM",
        colour = 0xff38bdf8,
        fontSize = 24.0,
        fontStyle = FontStyle.bold,
    })
    ui.tempoDisplay.node:setBounds(12, 36, 200, 30)
    y = y + 80 + sectionSpacing
    
    return y
end

-- ============================================================================
-- Paths Tab Content
-- ============================================================================

local function buildPathsTab(parent, w, h)
    local y = 0
    local margin = 12
    local panelW = w - margin * 2 - 16
    local sectionSpacing = 16
    
    -- Get current settings values
    local userDir = ""
    local devDir = ""
    if settings then
        userDir = settings.getUserScriptsDir and settings.getUserScriptsDir() or ""
        devDir = settings.getDevScriptsDir and settings.getDevScriptsDir() or ""
    end
    
    -- User Scripts Directory
    ui.userDirPanel = W.Panel.new(parent, "userDirPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.userDirPanel.node:setBounds(margin, y, panelW, 140)
    
    ui.userDirLabel = W.Label.new(ui.userDirPanel.node, "userDirLabel", {
        text = "User Scripts Directory",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.userDirLabel.node:setBounds(12, 8, 200, 18)
    
    -- Display current path (or "Not set")
    local userDirDisplay = userDir ~= "" and userDir or "Not set (click Browse to configure)"
    ui.userDirPathLabel = W.Label.new(ui.userDirPanel.node, "userDirPath", {
        text = userDirDisplay,
        colour = userDir ~= "" and 0xff64748b or 0xff94a3b8,
        fontSize = 10.0,
    })
    ui.userDirPathLabel.node:setBounds(12, 32, panelW - 24, 40)
    
    -- Browse button (opens native file chooser)
    ui.browseUserDirBtn = W.Button.new(ui.userDirPanel.node, "browseUserDir", {
        label = "Browse...",
        bg = 0xff2563eb,
        fontSize = 11.0,
        on_click = function()
            print("[SettingsUI] Browse button clicked")
            print("[SettingsUI] settings = " .. tostring(settings))
            print("[SettingsUI] type(settings) = " .. type(settings))
            if settings then
                print("[SettingsUI] settings table exists")
                -- Print all keys in settings
                local keys = {}
                for k, v in pairs(settings) do
                    table.insert(keys, k)
                end
                print("[SettingsUI] settings keys: " .. table.concat(keys, ", "))
                if settings.browseForUserScriptsDir then
                    print("[SettingsUI] browseForUserScriptsDir exists, calling...")
                    showStatus("Opening file chooser...")
                    settings.browseForUserScriptsDir(function(selectedPath)
                        print("[SettingsUI] Callback fired with path: " .. tostring(selectedPath))
                        if selectedPath and selectedPath ~= "" then
                            settings.setUserScriptsDir(selectedPath)
                            showStatus("User dir set to: " .. selectedPath)
                            -- Refresh display
                            ui.userDirPathLabel:setText(selectedPath)
                            ui.userDirPathLabel:setColour(0xff64748b)
                        else
                            showStatus("No directory selected")
                        end
                    end)
                    print("[SettingsUI] browseForUserScriptsDir returned")
                else
                    print("[SettingsUI] ERROR: browseForUserScriptsDir is nil")
                    showStatus("File chooser not available")
                end
            else
                print("[SettingsUI] ERROR: settings table is nil")
                showStatus("File chooser not available")
            end
        end,
    })
    ui.browseUserDirBtn.node:setBounds(12, 95, 100, 28)
    
    ui.clearUserDirBtn = W.Button.new(ui.userDirPanel.node, "clearUserDir", {
        label = "Clear",
        bg = 0xff7f1d1d,
        fontSize = 11.0,
        on_click = function()
            if settings and settings.setUserScriptsDir then
                settings.setUserScriptsDir("")
                showStatus("User dir cleared - restart to apply")
                -- Refresh the display
                ui.userDirPathLabel:setText("Not set (click Browse to configure)")
                ui.userDirPathLabel:setColour(0xff94a3b8)
            end
        end,
    })
    ui.clearUserDirBtn.node:setBounds(panelW - 92, 95, 80, 28)
    y = y + 140 + sectionSpacing
    
    -- Dev Scripts Directory (read-only display)
    ui.devDirPanel = W.Panel.new(parent, "devDirPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.devDirPanel.node:setBounds(margin, y, panelW, 80)
    
    ui.devDirLabel = W.Label.new(ui.devDirPanel.node, "devDirLabel", {
        text = "Development Scripts Directory",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.devDirLabel.node:setBounds(12, 8, 250, 18)
    
    ui.devDirPathLabel = W.Label.new(ui.devDirPanel.node, "devDirPath", {
        text = devDir ~= "" and devDir or "Not configured",
        colour = 0xff64748b,
        fontSize = 10.0,
    })
    ui.devDirPathLabel.node:setBounds(12, 32, panelW - 24, 40)
    y = y + 80 + sectionSpacing
    
    -- DSP Scripts Directory
    local dspDir = ""
    if settings and settings.getDspScriptsDir then
        dspDir = settings.getDspScriptsDir() or ""
    end
    
    ui.dspDirPanel = W.Panel.new(parent, "dspDirPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.dspDirPanel.node:setBounds(margin, y, panelW, 140)
    
    ui.dspDirLabel = W.Label.new(ui.dspDirPanel.node, "dspDirLabel", {
        text = "DSP Scripts Directory",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.dspDirLabel.node:setBounds(12, 8, 200, 18)
    
    local dspDirDisplay = dspDir ~= "" and dspDir or "Not set (click Browse to configure)"
    ui.dspDirPathLabel = W.Label.new(ui.dspDirPanel.node, "dspDirPath", {
        text = dspDirDisplay,
        colour = dspDir ~= "" and 0xff64748b or 0xff94a3b8,
        fontSize = 10.0,
    })
    ui.dspDirPathLabel.node:setBounds(12, 32, panelW - 24, 40)
    
    ui.browseDspDirBtn = W.Button.new(ui.dspDirPanel.node, "browseDspDir", {
        label = "Browse...",
        bg = 0xff2563eb,
        fontSize = 11.0,
        on_click = function()
            if settings and settings.browseForDspScriptsDir then
                showStatus("Opening file chooser...")
                settings.browseForDspScriptsDir(function(selectedPath)
                    if selectedPath and selectedPath ~= "" then
                        settings.setDspScriptsDir(selectedPath)
                        showStatus("DSP dir set to: " .. selectedPath)
                        ui.dspDirPathLabel:setText(selectedPath)
                        ui.dspDirPathLabel:setColour(0xff64748b)
                    else
                        showStatus("No directory selected")
                    end
                end)
            else
                showStatus("File chooser not available")
            end
        end,
    })
    ui.browseDspDirBtn.node:setBounds(12, 95, 100, 28)
    
    ui.clearDspDirBtn = W.Button.new(ui.dspDirPanel.node, "clearDspDir", {
        label = "Clear",
        bg = 0xff7f1d1d,
        fontSize = 11.0,
        on_click = function()
            if settings and settings.setDspScriptsDir then
                settings.setDspScriptsDir("")
                showStatus("DSP dir cleared - restart to apply")
                ui.dspDirPathLabel:setText("Not set (click Browse to configure)")
                ui.dspDirPathLabel:setColour(0xff94a3b8)
            end
        end,
    })
    ui.clearDspDirBtn.node:setBounds(panelW - 92, 95, 80, 28)
    y = y + 140 + sectionSpacing
    
    -- Available Scripts (taller for scrolling)
    ui.availablePanel = W.Panel.new(parent, "availablePanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.availablePanel.node:setBounds(margin, y, panelW, 280)
    
    ui.availableLabel = W.Label.new(ui.availablePanel.node, "availableLabel", {
        text = "Available UI Scripts (click to switch)",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.availableLabel.node:setBounds(12, 8, panelW - 24, 18)
    
    -- List will be drawn dynamically with its own scroll
    ui.scriptListOverlay = ui.availablePanel.node:addChild("scriptList")
    setupScriptList(panelW, 280)
    y = y + 280 + sectionSpacing
    
    return y
end

-- ============================================================================
-- MIDI Tab Content
-- ============================================================================

-- Load the proper MIDI tab module
local MidiTab = require("midi_tab")

local function buildMidiTab(parent, w, h)
    return MidiTab.build(parent, w, h, showStatus, ui.rootPanel.node)
end

-- ============================================================================
-- Setup Functions for Dynamic Lists
-- ============================================================================

function setupTargetList(panelW, height)
    local targets = {}
    local current = osc.getSettings()
    if current and current.outTargets then
        for i, t in ipairs(current.outTargets) do
            targets[i] = t
        end
    end

    ui.targetListOverlay:setBounds(12, 76, panelW - 24, height - 80)
    ui.targetListOverlay:setOnDraw(function(self)
        local w = self:getWidth()
        local h = self:getHeight()
        local itemH = 28
        
        for i, target in ipairs(targets) do
            local y = (i - 1) * itemH
            if y >= -itemH and y < h then
                -- Target text
                gfx.setColour(0xffe2e8f0)
                gfx.setFont(11.0)
                gfx.drawText(target, 8, math.floor(y), w - 50, itemH - 4, Justify.centredLeft)
                
                -- Remove button
                gfx.setColour(0xff7f1d1d)
                gfx.fillRoundedRect(math.floor(w - 40), math.floor(y + 2), 36, itemH - 4, 4)
                gfx.setColour(0xffffffff)
                gfx.setFont(10.0)
                gfx.drawText("×", math.floor(w - 36), math.floor(y + 4), 28, itemH - 8, Justify.centred)
            end
        end
        
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
        
        if mx > w - 40 and idx <= #targets then
            local target = targets[idx]
            if target then
                osc.removeTarget(target)
                showStatus("Removed: " .. target)
                setupTargetList(panelW, height)
            end
        end
    end)
end

function setupScriptList(panelW, height)
    local scripts = listUiScripts and listUiScripts() or {}
    
    ui.scriptListOverlay:setBounds(12, 32, panelW - 24, height - 40)
    ui.scriptListOverlay:setOnDraw(function(self)
        local w = self:getWidth()
        local h = self:getHeight()
        local itemH = 28
        local currentPath = getCurrentScriptPath and getCurrentScriptPath() or ""
        
        for i, script in ipairs(scripts) do
            local y = (i - 1) * itemH
            if y >= -itemH and y < h then
                local isCurrent = (script.path == currentPath)
                
                -- Background for current
                if isCurrent then
                    gfx.setColour(0xff334155)
                    gfx.fillRoundedRect(4, math.floor(y), w - 8, itemH - 2, 4)
                end
                
                -- Name
                gfx.setColour(isCurrent and 0xff38bdf8 or 0xffe2e8f0)
                gfx.setFont(11.0)
                gfx.drawText(script.name, 12, math.floor(y), w - 60, math.floor(itemH - 2), Justify.centredLeft)
                
                -- Source indicator (dev/bundled/user)
                local sourceColor = 0xff64748b
                local sourceText = "B"
                if script.path:find("/dev/") or script.path:find("dev%-my%-plugin") then
                    sourceColor = 0xfff59e0b
                    sourceText = "D"
                elseif script.path:find("/.vst3/") or script.path:find("/VST3/") then
                    sourceColor = 0xff34d399
                    sourceText = "B"
                elseif script.path:find("/config/") or script.path:find("user") then
                    sourceColor = 0xffa78bfa
                    sourceText = "U"
                end
                
                gfx.setColour(sourceColor)
                gfx.setFont(9.0)
                gfx.drawText(sourceText, math.floor(w - 40), math.floor(y), 30, math.floor(itemH - 2), Justify.centred)
            end
        end
        
        if #scripts == 0 then
            gfx.setColour(0xff64748b)
            gfx.setFont(11.0)
            gfx.drawText("No UI scripts found", 8, 20, w - 16, 20, Justify.centred)
        end
    end)
    
    ui.scriptListOverlay:setOnMouseDown(function(mx, my)
        local itemH = 28
        local idx = math.floor(my / itemH) + 1
        
        if idx >= 1 and idx <= #scripts then
            local script = scripts[idx]
            if script and switchUiScript then
                switchUiScript(script.path)
                showStatus("Switching to: " .. script.name)
            end
        end
    end)
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
    -- Header
    -- ==========================================================================
    ui.headerPanel = W.Panel.new(ui.rootPanel.node, "header", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })

    ui.titleLabel = W.Label.new(ui.headerPanel.node, "title", {
        text = "SETTINGS",
        colour = 0xff7dd3fc,
        fontSize = 20.0,
        fontStyle = FontStyle.bold,
    })

    -- ==========================================================================
    -- Tab Bar
    -- ==========================================================================
    ui.tabPanel = W.Panel.new(ui.rootPanel.node, "tabPanel", {
        bg = 0xff0f172a,
    })
    
    -- ==========================================================================
    -- Content Panel (scrollable)
    -- ==========================================================================
    ui.contentPanel = W.Panel.new(ui.rootPanel.node, "contentPanel", {
        bg = 0xff0a0f1a,
    })
    ui.contentNode = ui.contentPanel.node
    
    -- Build initial tab content
    rebuildTabContent()
    
    -- Load current settings
    local current = osc.getSettings()
    if current then
        if ui.oscPortBox then ui.oscPortBox:setValue(current.inputPort or 9000) end
        if ui.queryPortBox then ui.queryPortBox:setValue(current.queryPort or 9001) end
        if ui.oscToggle then ui.oscToggle:setValue(current.oscEnabled ~= false) end
        if ui.queryToggle then ui.queryToggle:setValue(current.oscQueryEnabled ~= false) end
    end
    
    -- Load Link settings
    if link and ui.linkToggle then
        ui.linkToggle:setValue(link.isEnabled())
        ui.linkTempoToggle:setValue(link.isTempoSyncEnabled())
        ui.linkStartStopToggle:setValue(link.isStartStopSyncEnabled())
    end
    
    ui_resized(root:getWidth(), root:getHeight())
end

-- ============================================================================
-- Tab Switching and Content Rebuilding
-- ============================================================================

function rebuildTabContent()
    -- Clear existing content
    ui.contentNode:clearChildren()
    
    local w = ui.contentNode:getWidth()
    local h = ui.contentNode:getHeight()
    
    -- Reset scroll
    scrollOffsets[currentTab] = 0
    
    -- Create a content container that will be scrolled
    local contentContainer = ui.contentNode:addChild("contentContainer")
    contentContainer:setBounds(0, 0, w, h)
    
    -- Build appropriate tab content inside the container
    local contentH = 0
    if currentTab == "osc" then
        contentH = buildOscTab(contentContainer, w, h)
    elseif currentTab == "link" then
        contentH = buildLinkTab(contentContainer, w, h)
    elseif currentTab == "paths" then
        contentH = buildPathsTab(contentContainer, w, h)
    elseif currentTab == "midi" then
        contentH = buildMidiTab(contentContainer, w, h)
    end
    
    -- Setup scrolling with content container
    setupScrollableContent(ui.contentNode, contentContainer, contentH)
end

function switchTab(tabId)
    if currentTab == tabId then return end
    currentTab = tabId
    rebuildTabContent()
    -- Force resize to update layouts
    ui_resized(ui.rootPanel.node:getWidth(), ui.rootPanel.node:getHeight())
end

-- ============================================================================
-- Layout
-- ============================================================================

function ui_resized(w, h)
    local margin = 0
    local headerH = 44
    local tabH = 40
    
    -- Root fills entire area
    ui.rootPanel.node:setBounds(0, 0, w, h)
    
    -- Header
    ui.headerPanel.node:setBounds(margin, margin, w - margin * 2, headerH)
    ui.titleLabel.node:setBounds(12, 10, w - 24, 24)
    
    -- Tab bar
    local tabY = margin + headerH
    ui.tabPanel.node:setBounds(margin, tabY, w - margin * 2, tabH)
    
    -- Tab buttons
    local tabW = math.floor((w - margin * 2 - 12) / 4)
    createTabButton(ui.tabPanel.node, "osc", "OSC", 4, 4, tabW, tabH - 8, function() switchTab("osc") end)
    createTabButton(ui.tabPanel.node, "link", "Link", 8 + tabW, 4, tabW, tabH - 8, function() switchTab("link") end)
    createTabButton(ui.tabPanel.node, "midi", "MIDI", 12 + tabW * 2, 4, tabW, tabH - 8, function() switchTab("midi") end)
    createTabButton(ui.tabPanel.node, "paths", "Paths", 16 + tabW * 3, 4, tabW, tabH - 8, function() switchTab("paths") end)
    
    -- Update tab button colors
    local children = {}
    if ui.tabPanel.node.getChildren then
        children = ui.tabPanel.node:getChildren() or {}
    end
    for _, child in ipairs(children) do
        if child and child.setBackgroundColor then
            local name = ""
            if child.getName then
                name = child:getName() or ""
            end
            if name:find("osc") then
                child:setBackgroundColor((currentTab == "osc") and 0xff2563eb or 0xff1e293b)
            elseif name:find("link") then
                child:setBackgroundColor((currentTab == "link") and 0xff2563eb or 0xff1e293b)
            elseif name:find("midi") then
                child:setBackgroundColor((currentTab == "midi") and 0xff2563eb or 0xff1e293b)
            elseif name:find("paths") then
                child:setBackgroundColor((currentTab == "paths") and 0xff2563eb or 0xff1e293b)
            end
        end
    end
    
    -- Content area (scrollable)
    local contentY = tabY + tabH + 4
    local contentH = h - contentY - margin
    ui.contentPanel.node:setBounds(margin, contentY, w - margin * 2, contentH)
    
    -- Rebuild content with new size
    rebuildTabContent()
end

-- ============================================================================
-- Update Loop
-- ============================================================================

function ui_update(state)
    -- Update status display (OSC tab)
    if ui.statusDisplay then
        if getTime() - statusTime < 3 then
            ui.statusDisplay:setText(statusMessage)
        else
            local srvStatus = osc.getStatus()
            if srvStatus == "running" and ui.oscPortBox then
                ui.statusDisplay:setText("OSC: Running | Ports: " .. ui.oscPortBox:getValue() .. "/" .. ui.queryPortBox:getValue())
            elseif ui.statusDisplay then
                ui.statusDisplay:setText("OSC: " .. srvStatus)
            end
        end
    end
    
    -- Update Link peers indicator (Link tab)
    if ui.linkPeersLabel and link then
        local peers = link.getNumPeers()
        if peers == 0 then
            ui.linkPeersLabel:setText("No peers")
        elseif peers == 1 then
            ui.linkPeersLabel:setText("1 peer")
        else
            ui.linkPeersLabel:setText(peers .. " peers")
        end
    end
    
    -- Update tempo display (Link tab)
    if ui.tempoDisplay and state and state.params then
        local tempo = state.params["/core/behavior/tempo"]
        if tempo then
            ui.tempoDisplay:setText(string.format("%.1f BPM", tempo))
        end
    end
    
    -- Refresh script list periodically (Paths tab)
    if ui.scriptListOverlay and getTime() % 2 < 0.03 then  -- Every ~2 seconds
        setupScriptList(ui.availablePanel.node:getWidth() - 36, 200)
    end
    
    -- Update MIDI voices display (MIDI tab)
    if ui.midiVoicesDisplay and Midi then
        local voices = Midi.getNumActiveVoices and Midi.getNumActiveVoices() or 0
        ui.midiVoicesDisplay:setText(tostring(voices))
    end

    if currentTab == "midi" and MidiTab and MidiTab.update then
        MidiTab.update()
    end
end

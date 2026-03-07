-- midi_tab.lua
-- MIDI device selection and monitoring for Settings UI

local W = require("ui_widgets")

local MidiTab = {}

-- State
local ui = {}
local midiInputDevices = {}
local midiOutputDevices = {}
local selectedInputIdx = 1
local selectedOutputIdx = 1
local pendingEventText = nil

-- Check if running as plugin (host MIDI available) or standalone
local function isPluginMode()
    -- In plugin mode, the host provides MIDI via processBlock
    -- In standalone, we need to open hardware devices directly
    -- Check if we can detect the runtime mode
    if Audio and Audio.isPlugin then
        return Audio.isPlugin()
    end
    -- Fallback: if we have no MIDI input devices available, assume plugin mode
    if Midi and Midi.inputDevices then
        local devices = Midi.inputDevices()
        return #devices == 0
    end
    return false
end

-- Refresh device lists from system
function MidiTab.refreshDevices()
    if not Midi then
        return
    end
    
    -- Get actual device lists from C++
    local inputs = Midi.inputDevices and Midi.inputDevices() or {}
    local outputs = Midi.outputDevices and Midi.outputDevices() or {}
    
    -- Determine appropriate "None" label based on runtime mode
    local noneInputLabel = isPluginMode() and "None (Use Host MIDI)" or "None (Disabled)"
    local noneOutputLabel = "None (Disabled)"
    
    -- Rebuild lists with "None" at start
    midiInputDevices = {noneInputLabel}
    midiOutputDevices = {noneOutputLabel}
    
    for _, name in ipairs(inputs) do
        table.insert(midiInputDevices, name)
    end
    
    for _, name in ipairs(outputs) do
        table.insert(midiOutputDevices, name)
    end
    
    -- Update dropdown options if they exist
    if ui.inputDropdown then
        ui.inputDropdown:setOptions(midiInputDevices)
        ui.inputDropdown:setSelected(selectedInputIdx)
    end
    
    if ui.outputDropdown then
        ui.outputDropdown:setOptions(midiOutputDevices)
        ui.outputDropdown:setSelected(selectedOutputIdx)
    end
end

-- Build the MIDI tab content
function MidiTab.build(parent, w, h, showStatusFn, rootNode)
    local y = 0
    local margin = 12
    local panelW = w - margin * 2 - 16
    local sectionSpacing = 16
    
    -- Get fresh device list
    MidiTab.refreshDevices()
    
    -- ============================================================================
    -- MIDI Input Device Section
    -- ============================================================================
    ui.inputPanel = W.Panel.new(parent, "midiInputPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.inputPanel.node:setBounds(margin, y, panelW, 100)
    
    ui.inputLabel = W.Label.new(ui.inputPanel.node, "midiInputLabel", {
        text = "MIDI Input Device",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.inputLabel.node:setBounds(12, 8, 200, 18)
    
    -- Device dropdown
    ui.inputDropdown = W.Dropdown.new(ui.inputPanel.node, "midiInputDropdown", {
        options = midiInputDevices,
        selected = selectedInputIdx,
        bg = 0xff1e293b,
        colour = 0xff38bdf8,
        rootNode = rootNode,
        on_select = function(idx, label)
            selectedInputIdx = idx
            if Midi then
                if idx == 1 then
                    if Midi.closeInput then Midi.closeInput() end
                    local statusMsg = isPluginMode() and "MIDI Input: Using Host" or "MIDI Input: Disabled"
                    showStatusFn(statusMsg)
                else
                    local deviceIdx = idx - 2  -- 0-based index for C++
                    local success = false
                    if Midi.openInput then
                        success = Midi.openInput(deviceIdx)
                    end
                    if success then
                        showStatusFn("MIDI Input: " .. label)
                    else
                        showStatusFn("Failed to open: " .. label)
                    end
                end
            end
        end,
    })
    ui.inputDropdown.node:setBounds(12, 36, panelW - 100, 36)
    
    -- Refresh button
    ui.refreshInputBtn = W.Button.new(ui.inputPanel.node, "refreshInput", {
        label = "Refresh",
        bg = 0xff0f3460,
        fontSize = 10.0,
        on_click = function()
            MidiTab.refreshDevices()
            showStatusFn("MIDI devices refreshed")
        end,
    })
    ui.refreshInputBtn.node:setBounds(panelW - 80, 36, 68, 36)
    y = y + 100 + sectionSpacing
    
    -- ============================================================================
    -- MIDI Output Device Section
    -- ============================================================================
    ui.outputPanel = W.Panel.new(parent, "midiOutputPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.outputPanel.node:setBounds(margin, y, panelW, 100)
    
    ui.outputLabel = W.Label.new(ui.outputPanel.node, "midiOutputLabel", {
        text = "MIDI Output Device",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.outputLabel.node:setBounds(12, 8, 200, 18)
    
    -- Output device dropdown
    ui.outputDropdown = W.Dropdown.new(ui.outputPanel.node, "midiOutputDropdown", {
        options = midiOutputDevices,
        selected = selectedOutputIdx,
        bg = 0xff1e293b,
        colour = 0xff38bdf8,
        rootNode = rootNode,
        on_select = function(idx, label)
            selectedOutputIdx = idx
            if Midi then
                if idx == 1 then
                    if Midi.closeOutput then Midi.closeOutput() end
                    showStatusFn("MIDI Output: Disabled")
                else
                    local deviceIdx = idx - 2
                    local success = false
                    if Midi.openOutput then
                        success = Midi.openOutput(deviceIdx)
                    end
                    if success then
                        showStatusFn("MIDI Output: " .. label)
                    else
                        showStatusFn("Failed to open: " .. label)
                    end
                end
            end
        end,
    })
    ui.outputDropdown.node:setBounds(12, 36, panelW - 24, 36)
    y = y + 100 + sectionSpacing
    
    -- ============================================================================
    -- MIDI Settings Section
    -- ============================================================================
    ui.settingsPanel = W.Panel.new(parent, "midiSettingsPanel", {
        bg = 0xff141a24,
        radius = 8,
    })
    ui.settingsPanel.node:setBounds(margin, y, panelW, 140)
    
    ui.settingsLabel = W.Label.new(ui.settingsPanel.node, "midiSettingsLabel", {
        text = "MIDI Settings",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.settingsLabel.node:setBounds(12, 8, 120, 18)
    
    -- Omni Mode Toggle
    ui.omniToggle = W.Toggle.new(ui.settingsPanel.node, "midiOmni", {
        label = "Omni Mode",
        value = true,
        colour = 0xfff59e0b,
        bg = 0xff1e293b,
        on_change = function(v)
            if Midi and Midi.setOmniMode then
                Midi.setOmniMode(v)
            end
        end,
    })
    ui.omniToggle.node:setBounds(12, 36, 140, 28)
    
    -- MIDI Thru Toggle
    ui.thruToggle = W.Toggle.new(ui.settingsPanel.node, "midiThru", {
        label = "MIDI Thru",
        value = false,
        colour = 0xff34d399,
        bg = 0xff1e293b,
        on_change = function(v)
            if Midi and Midi.thruEnabled then
                Midi.thruEnabled(v)
            end
        end,
    })
    ui.thruToggle.node:setBounds(160, 36, 140, 28)
    
    -- Test Note Button
    ui.testBtn = W.Button.new(ui.settingsPanel.node, "midiTest", {
        label = "Send Test Note",
        bg = 0xff2563eb,
        fontSize = 11.0,
        on_click = function()
            if Midi and Midi.sendNoteOn then
                Midi.sendNoteOn(1, 60, 100)
                showStatusFn("Sent C4 Note On")
                -- Note off after short delay would require Timer, skip for now
            end
        end,
    })
    ui.testBtn.node:setBounds(12, 80, 120, 36)
    
    -- Panic Button
    ui.panicBtn = W.Button.new(ui.settingsPanel.node, "midiPanic", {
        label = "All Notes Off",
        bg = 0xff7f1d1d,
        fontSize = 11.0,
        on_click = function()
            if Midi and Midi.sendAllNotesOff then
                for ch = 1, 16 do
                    Midi.sendAllNotesOff(ch)
                end
                showStatusFn("All Notes Off sent")
            end
        end,
    })
    ui.panicBtn.node:setBounds(140, 80, 120, 36)
    y = y + 140 + sectionSpacing
    
    -- ============================================================================
    -- MIDI Monitor Section
    -- ============================================================================
    ui.monitorPanel = W.Panel.new(parent, "midiMonitorPanel", {
        bg = 0xff1a2b1a,
        border = 0xff2d4a2d,
        borderWidth = 2,
        radius = 4,
    })
    ui.monitorPanel.node:setBounds(margin, y, panelW, 80)
    
    ui.monitorLabel = W.Label.new(ui.monitorPanel.node, "midiMonitorLabel", {
        text = "MIDI Monitor",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })
    ui.monitorLabel.node:setBounds(12, 8, 120, 18)
    
    ui.activityLed = W.Panel.new(ui.monitorPanel.node, "midiActivityLed", {
        bg = 0xff333333,
        radius = 8,
    })
    ui.activityLed.node:setBounds(panelW - 40, 12, 16, 16)
    
    ui.eventDisplay = W.Label.new(ui.monitorPanel.node, "midiEventDisplay", {
        text = "Waiting for MIDI...",
        colour = 0xff4ade80,
        fontSize = 13.0,
        fontStyle = FontStyle.bold,
    })
    ui.eventDisplay.node:setBounds(12, 40, panelW - 24, 24)
    y = y + 80 + sectionSpacing
    
    if Midi and Midi.clearCallbacks then
        Midi.clearCallbacks()
    end

    return y
end

-- Update function called each frame (UI thread)
function MidiTab.update()
    if not Midi or not Midi.pollInputEvent then
        return
    end

    local latestText = nil
    while true do
        local event = Midi.pollInputEvent()
        if not event then
            break
        end

        local eventType = event.type
        if eventType == Midi.NOTE_ON and event.data2 > 0 then
            local name = Midi.noteName and Midi.noteName(event.data1) or tostring(event.data1)
            latestText = string.format("Note On: %s (vel %d) ch%d", name, event.data2, event.channel)
        elseif eventType == Midi.NOTE_OFF or (eventType == Midi.NOTE_ON and event.data2 == 0) then
            local name = Midi.noteName and Midi.noteName(event.data1) or tostring(event.data1)
            latestText = string.format("Note Off: %s ch%d", name, event.channel)
        elseif eventType == Midi.CONTROL_CHANGE then
            latestText = string.format("CC %d = %d ch%d", event.data1, event.data2, event.channel)
        elseif eventType == Midi.PITCH_BEND then
            local bend = event.data1 | (event.data2 << 7)
            latestText = string.format("Pitch Bend %d ch%d", bend, event.channel)
        elseif eventType == Midi.PROGRAM_CHANGE then
            latestText = string.format("Program %d ch%d", event.data1, event.channel)
        end
    end

    if latestText and ui.eventDisplay then
        ui.eventDisplay:setText(latestText)
    end
end

return MidiTab

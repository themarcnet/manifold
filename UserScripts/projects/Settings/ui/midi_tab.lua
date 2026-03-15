-- MIDI Tab for Settings Project
-- Renderer-agnostic MIDI device selection and monitoring

local W = require("ui_widgets")

local MidiTab = {}

-- State
local midiInputDevices = {}
local midiOutputDevices = {}
local selectedInputIdx = 1
local selectedOutputIdx = 1

-- Colors
local C = {
  panelBg = 0xff141a24,
  text = 0xff94a3b8,
  accent = 0xff38bdf8,
  warning = 0xfff59e0b,
  success = 0xff34d399,
  danger = 0xff7f1d1d,
  monitorBg = 0xff1a2b1a,
  monitorBorder = 0xff2d4a2d,
}

-- ============================================================================
-- Helpers
-- ============================================================================

local function isPluginMode()
  if Audio and Audio.isPlugin then
    return Audio.isPlugin()
  end
  if Midi and Midi.inputDevices then
    local devices = Midi.inputDevices()
    return #devices == 0
  end
  return false
end

function MidiTab.refreshDevices(ui)
  if not Midi then return end
  
  local inputs = Midi.inputDevices and Midi.inputDevices() or {}
  local outputs = Midi.outputDevices and Midi.outputDevices() or {}
  
  local noneInputLabel = isPluginMode() and "None (Use Host MIDI)" or "None (Disabled)"
  local noneOutputLabel = "None (Disabled)"
  
  midiInputDevices = {noneInputLabel}
  midiOutputDevices = {noneOutputLabel}
  
  for _, name in ipairs(inputs) do
    table.insert(midiInputDevices, name)
  end
  
  for _, name in ipairs(outputs) do
    table.insert(midiOutputDevices, name)
  end
  
  if ui.inputDropdown then
    ui.inputDropdown:setOptions(midiInputDevices)
    ui.inputDropdown:setSelected(selectedInputIdx)
  end
  
  if ui.outputDropdown then
    ui.outputDropdown:setOptions(midiOutputDevices)
    ui.outputDropdown:setSelected(selectedOutputIdx)
  end
end

-- ============================================================================
-- Widget Creation
-- ============================================================================

function MidiTab.createWidgets(parentNode)
  local ui = {}
  local margin = 12
  
  -- Input Panel
  ui.inputPanel = W.Panel.new(parentNode, "midiInputPanel", {
    bg = C.panelBg,
    radius = 8,
  })
  
  ui.inputLabel = W.Label.new(ui.inputPanel.node, "midiInputLabel", {
    text = "MIDI Input Device",
    colour = C.text,
    fontSize = 12.0,
    fontStyle = FontStyle.bold,
  })
  
  ui.refreshInputBtn = W.Button.new(ui.inputPanel.node, "refreshInput", {
    label = "Refresh",
    bg = 0xff0f3460,
    fontSize = 10.0,
  })
  
  -- Output Panel
  ui.outputPanel = W.Panel.new(parentNode, "midiOutputPanel", {
    bg = C.panelBg,
    radius = 8,
  })
  
  ui.outputLabel = W.Label.new(ui.outputPanel.node, "midiOutputLabel", {
    text = "MIDI Output Device",
    colour = C.text,
    fontSize = 12.0,
    fontStyle = FontStyle.bold,
  })
  
  -- Settings Panel
  ui.settingsPanel = W.Panel.new(parentNode, "midiSettingsPanel", {
    bg = C.panelBg,
    radius = 8,
  })
  
  ui.settingsLabel = W.Label.new(ui.settingsPanel.node, "midiSettingsLabel", {
    text = "MIDI Settings",
    colour = C.text,
    fontSize = 12.0,
    fontStyle = FontStyle.bold,
  })
  
  ui.omniToggle = W.Toggle.new(ui.settingsPanel.node, "midiOmni", {
    label = "Omni Mode",
    value = true,
    colour = C.warning,
    bg = 0xff1e293b,
  })
  
  ui.thruToggle = W.Toggle.new(ui.settingsPanel.node, "midiThru", {
    label = "MIDI Thru",
    value = false,
    colour = C.success,
    bg = 0xff1e293b,
  })
  
  ui.testBtn = W.Button.new(ui.settingsPanel.node, "midiTest", {
    label = "Send Test Note",
    bg = 0xff2563eb,
    fontSize = 11.0,
  })
  
  ui.panicBtn = W.Button.new(ui.settingsPanel.node, "midiPanic", {
    label = "All Notes Off",
    bg = C.danger,
    fontSize = 11.0,
  })
  
  -- Monitor Panel
  ui.monitorPanel = W.Panel.new(parentNode, "midiMonitorPanel", {
    bg = C.monitorBg,
    border = C.monitorBorder,
    borderWidth = 2,
    radius = 4,
  })
  
  ui.monitorLabel = W.Label.new(ui.monitorPanel.node, "midiMonitorLabel", {
    text = "MIDI Monitor",
    colour = C.text,
    fontSize = 12.0,
    fontStyle = FontStyle.bold,
  })
  
  ui.activityLed = W.Panel.new(ui.monitorPanel.node, "midiActivityLed", {
    bg = 0xff333333,
    radius = 8,
  })
  
  ui.eventDisplay = W.Label.new(ui.monitorPanel.node, "midiEventDisplay", {
    text = "Waiting for MIDI...",
    colour = 0xff4ade80,
    fontSize = 13.0,
    fontStyle = FontStyle.bold,
  })
  
  MidiTab.refreshDevices(ui)
  
  -- Create dropdowns after refresh so we have device lists
  ui.inputDropdown = W.Dropdown.new(ui.inputPanel.node, "midiInputDropdown", {
    options = midiInputDevices,
    selected = selectedInputIdx,
    bg = 0xff1e293b,
    colour = C.accent,
  })
  
  ui.outputDropdown = W.Dropdown.new(ui.outputPanel.node, "midiOutputDropdown", {
    options = midiOutputDevices,
    selected = selectedOutputIdx,
    bg = 0xff1e293b,
    colour = C.accent,
  })
  
  if Midi and Midi.clearCallbacks then
    Midi.clearCallbacks()
  end
  
  return ui
end

-- ============================================================================
-- Wiring
-- ============================================================================

function MidiTab.wire(ui, showStatusFn)
  if not showStatusFn then
    showStatusFn = function(msg) print("[MIDI] " .. msg) end
  end
  
  ui.inputDropdown:setOnSelect(function(idx, label)
    selectedInputIdx = idx
    if Midi then
      if idx == 1 then
        if Midi.closeInput then Midi.closeInput() end
        local statusMsg = isPluginMode() and "MIDI Input: Using Host" or "MIDI Input: Disabled"
        showStatusFn(statusMsg)
      else
        local deviceIdx = idx - 2
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
  end)
  
  ui.outputDropdown:setOnSelect(function(idx, label)
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
  end)
  
  ui.refreshInputBtn:setOnClick(function()
    MidiTab.refreshDevices(ui)
    showStatusFn("MIDI devices refreshed")
  end)
  
  ui.omniToggle:setOnChange(function(v)
    if Midi and Midi.setOmniMode then
      Midi.setOmniMode(v)
    end
  end)
  
  ui.thruToggle:setOnChange(function(v)
    if Midi and Midi.thruEnabled then
      Midi.thruEnabled(v)
    end
  end)
  
  ui.testBtn:setOnClick(function()
    if Midi and Midi.sendNoteOn then
      Midi.sendNoteOn(1, 60, 100)
      showStatusFn("Sent C4 Note On")
    end
  end)
  
  ui.panicBtn:setOnClick(function()
    if Midi and Midi.sendAllNotesOff then
      for ch = 1, 16 do
        Midi.sendAllNotesOff(ch)
      end
      showStatusFn("All Notes Off sent")
    end
  end)
end

-- ============================================================================
-- Layout
-- ============================================================================

function MidiTab.layout(ui, w, h)
  local margin = 12
  local panelW = w - margin * 2
  local y = 0
  local sectionSpacing = 16
  
  -- Input Panel
  ui.inputPanel:setBounds(margin, y, panelW, 100)
  ui.inputLabel:setBounds(12, 8, 200, 18)
  ui.inputDropdown:setBounds(12, 36, panelW - 100, 36)
  ui.refreshInputBtn:setBounds(panelW - 80, 36, 68, 36)
  y = y + 100 + sectionSpacing
  
  -- Output Panel
  ui.outputPanel:setBounds(margin, y, panelW, 100)
  ui.outputLabel:setBounds(12, 8, 200, 18)
  ui.outputDropdown:setBounds(12, 36, panelW - 24, 36)
  y = y + 100 + sectionSpacing
  
  -- Settings Panel
  ui.settingsPanel:setBounds(margin, y, panelW, 140)
  ui.settingsLabel:setBounds(12, 8, 120, 18)
  ui.omniToggle:setBounds(12, 36, 140, 28)
  ui.thruToggle:setBounds(160, 36, 140, 28)
  ui.testBtn:setBounds(12, 80, 120, 36)
  ui.panicBtn:setBounds(140, 80, 120, 36)
  y = y + 140 + sectionSpacing
  
  -- Monitor Panel
  ui.monitorPanel:setBounds(margin, y, panelW, 80)
  ui.monitorLabel:setBounds(12, 8, 120, 18)
  ui.activityLed:setBounds(panelW - 40, 12, 16, 16)
  ui.eventDisplay:setBounds(12, 40, panelW - 24, 24)
end

-- ============================================================================
-- Update
-- ============================================================================

function MidiTab.update(ui)
  if not Midi or not Midi.pollInputEvent then return end
  if not ui or not ui.eventDisplay then return end
  
  local latestText = nil
  while true do
    local event = Midi.pollInputEvent()
    if not event then break end
    
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
  
  if latestText then
    ui.eventDisplay:setText(latestText)
  end
end

return MidiTab

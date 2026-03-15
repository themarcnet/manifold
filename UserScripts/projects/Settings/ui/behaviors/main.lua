-- Settings UI - Behavior
-- Pure logic, no widget creation. All widgets are declarative.

local M = {}

M.currentTab = "osc"
M.statusMessage = "Ready"
M.statusTime = 0

-- Colors
local C = {
  tabActive = 0xff2563eb,
  tabInactive = 0xff1e293b,
  textMuted = 0xff64748b,
  text = 0xff94a3b8,
}

-- ============================================================================
-- Helpers
-- ============================================================================

local function showStatus(ctx, msg)
  M.statusMessage = msg
  M.statusTime = getTime and getTime() or 0
  local statusDisplay = ctx.widgets.oscStatusDisplay
  if statusDisplay then
    statusDisplay:setText(msg)
  end
end

local function isValidPort(port)
  return port and port >= 1024 and port <= 65535
end

-- ============================================================================
-- Tab Switching
-- ============================================================================

function M.switchTab(ctx, tabId)
  if M.currentTab == tabId then return end
  M.currentTab = tabId
  M.syncTabStyles(ctx)
  M.syncTabVisibility(ctx)
end

function M.syncTabStyles(ctx)
  local w = ctx.widgets
  if w.oscTabBtn then
    w.oscTabBtn:setBg((M.currentTab == "osc") and C.tabActive or C.tabInactive)
  end
  if w.linkTabBtn then
    w.linkTabBtn:setBg((M.currentTab == "link") and C.tabActive or C.tabInactive)
  end
  if w.midiTabBtn then
    w.midiTabBtn:setBg((M.currentTab == "midi") and C.tabActive or C.tabInactive)
  end
  if w.pathsTabBtn then
    w.pathsTabBtn:setBg((M.currentTab == "paths") and C.tabActive or C.tabInactive)
  end
end

function M.syncTabVisibility(ctx)
  local w = ctx.widgets
  
  -- Hide all tab content panels
  if w.oscContent then w.oscContent:setVisible(M.currentTab == "osc") end
  if w.linkContent then w.linkContent:setVisible(M.currentTab == "link") end
  if w.pathsContent then w.pathsContent:setVisible(M.currentTab == "paths") end
  if w.midiContent then w.midiContent:setVisible(M.currentTab == "midi") end
end

-- ============================================================================
-- OSC Settings
-- ============================================================================

function M.applyOscSettings(ctx)
  local w = ctx.widgets
  if not w.oscPort then return end
  
  local newSettings = {
    inputPort = math.floor(w.oscPort:getValue()),
    queryPort = math.floor(w.queryPort:getValue()),
    oscEnabled = w.oscToggle:getValue(),
    oscQueryEnabled = w.queryToggle:getValue(),
    outTargets = {}
  }
  
  if not isValidPort(newSettings.inputPort) then
    showStatus(ctx, "ERR: OSC port must be 1024-65535")
    return
  end
  if not isValidPort(newSettings.queryPort) then
    showStatus(ctx, "ERR: OSCQuery port must be 1024-65535")
    return
  end
  if newSettings.inputPort == newSettings.queryPort then
    showStatus(ctx, "ERR: Ports must be different")
    return
  end
  
  if osc and osc.setSettings and osc.setSettings(newSettings) then
    showStatus(ctx, "Settings saved & applied")
  else
    showStatus(ctx, "ERR: Failed to save settings")
  end
end

function M.loadOscSettings(ctx)
  if not osc or not osc.getSettings then return end
  local current = osc.getSettings()
  if not current then return end
  
  local w = ctx.widgets
  if w.oscPort then w.oscPort:setValue(current.inputPort or 9000) end
  if w.queryPort then w.queryPort:setValue(current.queryPort or 9001) end
  if w.oscToggle then w.oscToggle:setValue(current.oscEnabled ~= false) end
  if w.queryToggle then w.queryToggle:setValue(current.oscQueryEnabled ~= false) end
end

-- ============================================================================
-- Link Settings
-- ============================================================================

function M.loadLinkSettings(ctx)
  if not link then return end
  local w = ctx.widgets
  
  if w.linkToggle and link.isEnabled then
    w.linkToggle:setValue(link.isEnabled())
  end
  if w.linkTempoToggle and link.isTempoSyncEnabled then
    w.linkTempoToggle:setValue(link.isTempoSyncEnabled())
  end
  if w.linkStartStopToggle and link.isStartStopSyncEnabled then
    w.linkStartStopToggle:setValue(link.isStartStopSyncEnabled())
  end
end

-- ============================================================================
-- Paths Settings
-- ============================================================================

function M.loadPathsSettings(ctx)
  if not settings then return end
  local w = ctx.widgets
  
  -- User dir
  if settings.getUserScriptsDir and w.userDirPathLabel then
    local userDir = settings.getUserScriptsDir() or ""
    if userDir ~= "" then
      w.userDirPathLabel:setText(userDir)
      w.userDirPathLabel:setColour(C.textMuted)
    else
      w.userDirPathLabel:setText("Not set (click Browse to configure)")
      w.userDirPathLabel:setColour(C.text)
    end
  end
  
  -- Dev dir
  if settings.getDevScriptsDir and w.devDirPathLabel then
    local devDir = settings.getDevScriptsDir() or ""
    w.devDirPathLabel:setText(devDir ~= "" and devDir or "Not configured")
  end
  
  -- DSP dir
  if settings.getDspScriptsDir and w.dspDirPathLabel then
    local dspDir = settings.getDspScriptsDir() or ""
    if dspDir ~= "" then
      w.dspDirPathLabel:setText(dspDir)
      w.dspDirPathLabel:setColour(C.textMuted)
    else
      w.dspDirPathLabel:setText("Not set (click Browse to configure)")
      w.dspDirPathLabel:setColour(C.text)
    end
  end
end

function M.browseForDir(ctx, which)
  local browseFn = (which == "user") and settings.browseForUserScriptsDir or settings.browseForDspScriptsDir
  local setFn = (which == "user") and settings.setUserScriptsDir or settings.setDspScriptsDir
  local label = (which == "user") and ctx.widgets.userDirPathLabel or ctx.widgets.dspDirPathLabel
  
  if not browseFn then
    showStatus(ctx, "File chooser not available")
    return
  end
  
  showStatus(ctx, "Opening file chooser...")
  browseFn(function(selectedPath)
    if selectedPath and selectedPath ~= "" then
      setFn(selectedPath)
      showStatus(ctx, (which == "user" and "User" or "DSP") .. " dir set")
      label:setText(selectedPath)
      label:setColour(C.textMuted)
    else
      showStatus(ctx, "No directory selected")
    end
  end)
end

function M.clearDir(ctx, which)
  local setFn = (which == "user") and settings.setUserScriptsDir or settings.setDspScriptsDir
  local label = (which == "user") and ctx.widgets.userDirPathLabel or ctx.widgets.dspDirPathLabel
  local name = (which == "user") and "User" or "DSP"
  
  if not setFn then return end
  
  setFn("")
  showStatus(ctx, name .. " dir cleared - restart to apply")
  label:setText("Not set (click Browse to configure)")
  label:setColour(C.text)
end

-- ============================================================================
-- MIDI
-- ============================================================================

function M.refreshMidiDevices(ctx)
  if not Midi then return end
  local w = ctx.widgets
  
  local inputs = Midi.inputDevices and Midi.inputDevices() or {}
  local outputs = Midi.outputDevices and Midi.outputDevices() or {}
  
  local inputOptions = { "None (Use Host MIDI)" }
  for _, name in ipairs(inputs) do
    table.insert(inputOptions, name)
  end
  
  local outputOptions = { "None (Disabled)" }
  for _, name in ipairs(outputs) do
    table.insert(outputOptions, name)
  end
  
  if w.midiInputDropdown then
    w.midiInputDropdown:setOptions(inputOptions)
  end
  if w.midiOutputDropdown then
    w.midiOutputDropdown:setOptions(outputOptions)
  end
end

function M.updateMidiMonitor(ctx)
  if not Midi or not Midi.pollInputEvent then return end
  if M.currentTab ~= "midi" then return end
  
  local w = ctx.widgets
  if not w.midiEventDisplay then return end
  
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
    end
  end
  
  if latestText then
    w.midiEventDisplay:setText(latestText)
    -- Flash activity LED (Panel uses setStyle)
    if w.midiActivityLed and w.midiActivityLed.setStyle then
      w.midiActivityLed:setStyle({ bg = 0xff4ade80 })
    end
  else
    -- Dim activity LED
    if w.midiActivityLed and w.midiActivityLed.setStyle then
      w.midiActivityLed:setStyle({ bg = 0xff333333 })
    end
  end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function M.init(ctx)
  local w = ctx.widgets
  
  -- Wire tab buttons (use _onClick for declarative widgets)
  if w.oscTabBtn then
    w.oscTabBtn._onClick = function() M.switchTab(ctx, "osc") end
  end
  if w.linkTabBtn then
    w.linkTabBtn._onClick = function() M.switchTab(ctx, "link") end
  end
  if w.midiTabBtn then
    w.midiTabBtn._onClick = function() M.switchTab(ctx, "midi") end
  end
  if w.pathsTabBtn then
    w.pathsTabBtn._onClick = function() M.switchTab(ctx, "paths") end
  end
  
  -- Wire OSC apply button
  if w.oscApplyBtn then
    w.oscApplyBtn._onClick = function() M.applyOscSettings(ctx) end
  end
  
  -- Wire Paths buttons
  if w.browseUserDirBtn then
    w.browseUserDirBtn._onClick = function() M.browseForDir(ctx, "user") end
  end
  if w.clearUserDirBtn then
    w.clearUserDirBtn._onClick = function() M.clearDir(ctx, "user") end
  end
  if w.browseDspDirBtn then
    w.browseDspDirBtn._onClick = function() M.browseForDir(ctx, "dsp") end
  end
  if w.clearDspDirBtn then
    w.clearDspDirBtn._onClick = function() M.clearDir(ctx, "dsp") end
  end
  
  -- Wire Link toggles (use _onChange for declarative widgets)
  if w.linkToggle then
    w.linkToggle._onChange = function(v)
      if link and link.setEnabled then link.setEnabled(v) end
    end
  end
  if w.linkTempoToggle then
    w.linkTempoToggle._onChange = function(v)
      if link and link.setTempoSyncEnabled then link.setTempoSyncEnabled(v) end
    end
  end
  if w.linkStartStopToggle then
    w.linkStartStopToggle._onChange = function(v)
      if link and link.setStartStopSyncEnabled then link.setStartStopSyncEnabled(v) end
    end
  end
  
  -- Wire MIDI
  if w.midiRefreshInputBtn then
    w.midiRefreshInputBtn._onClick = function()
      M.refreshMidiDevices(ctx)
      showStatus(ctx, "MIDI devices refreshed")
    end
  end
  if w.midiInputDropdown then
    w.midiInputDropdown._onSelect = function(idx)
      if Midi and Midi.openInput and idx > 1 then
        Midi.openInput(idx - 2)
      elseif Midi and Midi.closeInput and idx == 1 then
        Midi.closeInput()
      end
    end
  end
  if w.midiOutputDropdown then
    w.midiOutputDropdown._onSelect = function(idx)
      if Midi and Midi.openOutput and idx > 1 then
        Midi.openOutput(idx - 2)
      elseif Midi and Midi.closeOutput and idx == 1 then
        Midi.closeOutput()
      end
    end
  end
  if w.midiOmniToggle then
    w.midiOmniToggle._onChange = function(v)
      if Midi and Midi.setOmniMode then Midi.setOmniMode(v) end
    end
  end
  if w.midiThruToggle then
    w.midiThruToggle._onChange = function(v)
      if Midi and Midi.thruEnabled then Midi.thruEnabled(v) end
    end
  end
  if w.midiTestBtn then
    w.midiTestBtn._onClick = function()
      if Midi and Midi.sendNoteOn then
        Midi.sendNoteOn(1, 60, 100)
        showStatus(ctx, "Sent C4 Note On")
      end
    end
  end
  if w.midiPanicBtn then
    w.midiPanicBtn._onClick = function()
      if Midi and Midi.sendAllNotesOff then
        for ch = 1, 16 do
          Midi.sendAllNotesOff(ch)
        end
        showStatus(ctx, "All Notes Off sent")
      end
    end
  end
  
  -- Initial state
  M.syncTabStyles(ctx)
  M.syncTabVisibility(ctx)
  M.loadOscSettings(ctx)
  M.loadLinkSettings(ctx)
  M.loadPathsSettings(ctx)
  M.refreshMidiDevices(ctx)
  
  -- Set dropdown absolute positions for correct popup placement
  M.updateDropdownAnchors(ctx)
end

function M.updateDropdownAnchors(ctx)
  local w = ctx.widgets
  if w.midiInputDropdown and w.midiInputDropdown.setAbsolutePos then
    local x, y, _, h = w.midiInputDropdown.node:getBounds()
    w.midiInputDropdown:setAbsolutePos(x, y + h)
  end
  if w.midiOutputDropdown and w.midiOutputDropdown.setAbsolutePos then
    local x, y, _, h = w.midiOutputDropdown.node:getBounds()
    w.midiOutputDropdown:setAbsolutePos(x, y + h)
  end
end

function M.resized(ctx, w, h)
  -- Update dropdown positions after resize
  M.updateDropdownAnchors(ctx)
end

function M.update(ctx, state)
  local now = getTime and getTime() or 0
  
  -- Update OSC status
  if M.currentTab == "osc" and ctx.widgets.oscStatusDisplay then
    if now - M.statusTime >= 3 then
      if osc and osc.getStatus then
        local srvStatus = osc.getStatus()
        if srvStatus == "running" then
          local port = ctx.widgets.oscPort and ctx.widgets.oscPort:getValue() or 9000
          local qport = ctx.widgets.queryPort and ctx.widgets.queryPort:getValue() or 9001
          ctx.widgets.oscStatusDisplay:setText("OSC: Running | Ports: " .. port .. "/" .. qport)
        else
          ctx.widgets.oscStatusDisplay:setText("OSC: " .. srvStatus)
        end
      end
    end
  end
  
  -- Update Link status
  if M.currentTab == "link" and link then
    local w = ctx.widgets
    if w.linkPeersLabel and link.getNumPeers then
      local peers = link.getNumPeers()
      if peers == 0 then
        w.linkPeersLabel:setText("No peers")
      elseif peers == 1 then
        w.linkPeersLabel:setText("1 peer")
      else
        w.linkPeersLabel:setText(peers .. " peers")
      end
    end
    if w.linkTempoDisplay and link.getTempo then
      w.linkTempoDisplay:setText(string.format("%.1f BPM", link.getTempo()))
    end
  end
  
  -- Update MIDI monitor
  M.updateMidiMonitor(ctx)
end

return M

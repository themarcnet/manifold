-- MIDI Device Management
-- MIDI input enumeration, selection, and persistence

local M = {}
local deps = {}

local function loadRuntimeState()
  if type(deps.loadRuntimeState) == "function" then
    local state = deps.loadRuntimeState()
    if type(state) == "table" then
      return state
    end
  end
  return {}
end

local function saveRuntimeState(state)
  if type(deps.saveRuntimeState) == "function" then
    return deps.saveRuntimeState(state)
  end
  return false
end

local function notifyMidiDeviceStateChanged(ctx, reason)
  local callback = ctx and ctx._onMidiDeviceStateChanged
  if type(callback) == "function" then
    callback({ reason = reason })
  end
end

-- Check if running as plugin
function M.isPluginMode()
  if Audio and Audio.isPlugin then
    return Audio.isPlugin()
  end
  return false
end

-- Build list of MIDI input options
function M.buildMidiOptions(ctx)
  local devices = Midi and Midi.inputDevices and Midi.inputDevices() or {}
  ctx._midiDevices = devices
  local noneLabel = M.isPluginMode() and "Use Host MIDI" or "None (Disabled)"
  local options = { noneLabel }
  for _, name in ipairs(devices) do
    options[#options + 1] = name
  end
  return options
end

-- Find index of option by label
function M.findOptionIndex(options, label)
  if type(label) ~= "string" or label == "" then
    return nil
  end
  for i, option in ipairs(options or {}) do
    if option == label then
      return i
    end
  end
  return nil
end

-- Get current MIDI input label
function M.getCurrentMidiInputLabel(ctx)
  if Midi and Midi.currentInputDeviceName then
    local name = Midi.currentInputDeviceName()
    if type(name) == "string" and name ~= "" then
      return name
    end
  end

  if Midi and Midi.currentInputDeviceIndex and Midi.isInputOpen and Midi.isInputOpen() then
    local deviceIndex = tonumber(Midi.currentInputDeviceIndex()) or -1
    if deviceIndex >= 0 then
      local devices = ctx and ctx._midiDevices or (Midi.inputDevices and Midi.inputDevices() or {})
      return devices[deviceIndex + 1]
    end
  end

  return nil
end

function M.normalizeDeviceKey(label)
  local raw = tostring(label or "")
  if raw == "" then
    return nil
  end

  local normalized = raw:lower():gsub("[^%w]+", "_"):gsub("_+", "_")
  normalized = normalized:gsub("^_+", ""):gsub("_+$", "")
  if normalized == "" then
    return nil
  end
  return normalized
end

-- Persist MIDI selection to runtime state
function M.persistMidiInputSelection(label)
  local state = loadRuntimeState()
  state.inputDevice = tostring(label or "")
  saveRuntimeState(state)
end

-- Apply MIDI selection
function M.applyMidiSelection(ctx, idx, persist)
  local widgets = ctx.widgets or {}
  local options = ctx._midiOptions or {}
  local label = options[idx] or options[1] or "None (Disabled)"
  
  ctx._selectedMidiInputIdx = idx
  ctx._selectedMidiInputLabel = label
  
  if idx == 1 then
    if Midi and Midi.closeInput then
      Midi.closeInput()
    end
    ctx._lastEvent = M.isPluginMode() and "Using host MIDI" or "MIDI input disabled"
    if widgets.deviceValue and widgets.deviceValue.setText then
      widgets.deviceValue:setText("Input: " .. label)
    end
    if persist then
      M.persistMidiInputSelection("")
    end
    notifyMidiDeviceStateChanged(ctx, "selection-cleared")
    return true
  end
  
  local deviceIndex = idx - 2
  local success = Midi and Midi.openInput and Midi.openInput(deviceIndex) or false
  if success then
    local activeLabel = M.getCurrentMidiInputLabel(ctx) or label
    local activeIdx = M.findOptionIndex(options, activeLabel) or idx
    ctx._selectedMidiInputIdx = activeIdx
    ctx._selectedMidiInputLabel = activeLabel
    ctx._lastEvent = "Opened: " .. activeLabel
    if widgets.midiInputDropdown and widgets.midiInputDropdown.setSelected then
      widgets.midiInputDropdown:setSelected(activeIdx)
    end
    if widgets.deviceValue and widgets.deviceValue.setText then
      widgets.deviceValue:setText("Input: " .. activeLabel)
    end
    if persist then
      M.persistMidiInputSelection(activeLabel)
    end
    notifyMidiDeviceStateChanged(ctx, "selection-opened")
    return true
  end
  
  ctx._lastEvent = "Failed: " .. label
  notifyMidiDeviceStateChanged(ctx, "selection-failed")
  return false
end

-- Refresh MIDI device list
function M.refreshMidiDevices(ctx, restoreSelection)
  local widgets = ctx.widgets or {}
  local options = M.buildMidiOptions(ctx)
  ctx._midiOptions = options
  ctx._lastKnownMidiDeviceCount = math.max(0, #options - 1)
  
  if widgets.midiInputDropdown and widgets.midiInputDropdown.setOptions then
    widgets.midiInputDropdown:setOptions(options)
    if widgets.midiInputDropdown.repaint then
      widgets.midiInputDropdown:repaint()
    end
  end

  local activeLabel = M.getCurrentMidiInputLabel(ctx)
  local activeIdx = M.findOptionIndex(options, activeLabel)
  local idx = activeIdx or 1

  local saved = restoreSelection and loadRuntimeState() or nil
  if not activeIdx and saved and saved.inputDevice then
    local savedIdx = M.findOptionIndex(options, saved.inputDevice)
    if savedIdx then
      idx = savedIdx
    end
  elseif not activeIdx and ctx._selectedMidiInputLabel then
    local currentIdx = M.findOptionIndex(options, ctx._selectedMidiInputLabel)
    if currentIdx then
      idx = currentIdx
    end
  end
  
  if widgets.midiInputDropdown and widgets.midiInputDropdown.setSelected then
    widgets.midiInputDropdown:setSelected(idx)
  end
  ctx._selectedMidiInputIdx = idx
  ctx._selectedMidiInputLabel = options[idx] or options[1]
  
  if not activeIdx and restoreSelection and idx > 1 then
    M.applyMidiSelection(ctx, idx, false)
  else
    if activeLabel then
      ctx._selectedMidiInputLabel = activeLabel
      ctx._selectedMidiInputIdx = activeIdx or idx
    end
    if widgets.deviceValue and widgets.deviceValue.setText then
      widgets.deviceValue:setText("Input: " .. (ctx._selectedMidiInputLabel or options[1] or "None"))
    end
  end

  notifyMidiDeviceStateChanged(ctx, "refresh")
end

-- Check if MIDI refresh is needed (throttled)
function M.maybeRefreshMidiDevices(ctx, now)
  if not (Midi and Midi.inputDevices) then
    return
  end
  if (now - (ctx._lastMidiDeviceScanTime or 0)) < 1.0 then
    return
  end
  ctx._lastMidiDeviceScanTime = now
  
  local devices = Midi.inputDevices()
  local count = #devices
  local options = ctx._midiOptions or {}
  local optionCount = #options
  
  local needsRefresh = count ~= (ctx._lastKnownMidiDeviceCount or -1)
  if not needsRefresh then
    local activeLabel = M.getCurrentMidiInputLabel(ctx)
    if activeLabel and activeLabel ~= (ctx._selectedMidiInputLabel or "") then
      needsRefresh = true
    end
  end
  
  if needsRefresh then
    M.refreshMidiDevices(ctx, true)
  end
end

function M.init(options)
  options = options or {}
  deps.loadRuntimeState = options.loadRuntimeState
  deps.saveRuntimeState = options.saveRuntimeState
end

return M

local MidiDevices = require("ui.midi_devices")

local M = {}

local DISPLAY_COUNT = 32
local SLOT_GAP = 4
local HEADER_H = 14
local FOOTER_H = 12
local PADDING_X = 8
local PADDING_Y = 6

local function ensureState(ctx)
  ctx._midiParamRackState = ctx._midiParamRackState or {
    ccValues = {},
    ccTouchedAt = {},
    deviceKey = nil,
    visibleCcs = nil,
  }
  return ctx._midiParamRackState
end

local function currentDeviceLabel(ctx)
  local label = MidiDevices.getCurrentMidiInputLabel(ctx)
  if type(label) ~= "string" or label == "" or label == "None (Disabled)" then
    return nil
  end
  return label
end

local function currentDeviceKey(ctx)
  local label = currentDeviceLabel(ctx)
  if not label then
    return nil
  end
  return MidiDevices.normalizeDeviceKey(label)
end

local function resetVisibleCcs(state, deviceKey)
  state.deviceKey = deviceKey
  state.visibleCcs = {}
  for cc = 0, DISPLAY_COUNT - 1 do
    state.visibleCcs[#state.visibleCcs + 1] = cc
  end
end

local function ensureVisibleCcs(state, deviceKey)
  if not deviceKey then
    state.deviceKey = nil
    state.visibleCcs = nil
    return {}
  end
  if state.deviceKey ~= deviceKey or type(state.visibleCcs) ~= "table" then
    resetVisibleCcs(state, deviceKey)
  end
  return state.visibleCcs
end

local function displayCcs(ctx)
  local deviceKey = currentDeviceKey(ctx)
  if not deviceKey then
    return {}
  end
  local state = ensureState(ctx)
  local visible = ensureVisibleCcs(state, deviceKey)
  local out = {}
  for i = 1, math.min(DISPLAY_COUNT, #(visible or {})) do
    out[i] = visible[i]
  end
  table.sort(out)
  return out
end

function M.onMidiCC(ctx, cc, value)
  local state = ensureState(ctx)
  local ccIndex = math.max(0, math.min(127, math.floor(tonumber(cc) or 0)))
  local normalized = math.max(0.0, math.min(1.0, (tonumber(value) or 0) / 127.0))
  state.ccValues[ccIndex] = normalized
  state.ccTouchedAt[ccIndex] = (type(getTime) == "function" and getTime() or os.clock())

  local deviceKey = currentDeviceKey(ctx)
  if deviceKey then
    local visible = ensureVisibleCcs(state, deviceKey)
    local existingIndex = nil
    for i = 1, #(visible or {}) do
      if visible[i] == ccIndex then
        existingIndex = i
        break
      end
    end
    if existingIndex ~= nil then
      table.remove(visible, existingIndex)
    end
    table.insert(visible, 1, ccIndex)
    while #visible > DISPLAY_COUNT do
      table.remove(visible)
    end
  end
end

function M.invalidate(ctx)
  if type(ctx) ~= "table" then
    return
  end
  ctx._midiParamRackDisplayDirty = true
end

local function addText(display, x, y, w, h, text, color, fontSize, align)
  display[#display + 1] = {
    cmd = "drawText",
    x = math.floor(x),
    y = math.floor(y),
    w = math.floor(w),
    h = math.floor(h),
    text = tostring(text or ""),
    color = color,
    fontSize = fontSize,
    align = align or "center",
    valign = "middle",
  }
end

local function addRect(display, x, y, w, h, color, radius)
  display[#display + 1] = {
    cmd = "fillRoundedRect",
    x = math.floor(x),
    y = math.floor(y),
    w = math.max(1, math.floor(w)),
    h = math.max(1, math.floor(h)),
    radius = radius or 2,
    color = color,
  }
end

local function buildDisplayList(ctx, w, h)
  local display = {}
  local deviceKey = currentDeviceKey(ctx)
  local deviceLabel = currentDeviceLabel(ctx)
  if not deviceKey then
    addText(display, 0, 0, w, h, "No MIDI device selected", 0xff64748b, 11, "center")
    return display
  end

  local ccs = displayCcs(ctx)
  if #ccs == 0 then
    addText(display, 0, 0, w, h, "No MIDI CC endpoints for selected device", 0xff64748b, 11, "center")
    return display
  end

  local state = ensureState(ctx)
  local innerX = PADDING_X
  local innerY = PADDING_Y
  local innerW = math.max(1, w - (PADDING_X * 2))
  local innerH = math.max(1, h - (PADDING_Y * 2))
  local slotW = math.max(18, math.floor((innerW - ((#ccs - 1) * SLOT_GAP)) / #ccs))
  local meterTop = innerY + HEADER_H
  local meterBottom = innerY + innerH - FOOTER_H
  local meterH = math.max(8, meterBottom - meterTop)

  addText(display, innerX, innerY - 1, innerW, HEADER_H, tostring(deviceLabel or "MIDI CC"), 0xff94a3b8, 10, "left")

  local x = innerX
  for i = 1, #ccs do
    local cc = ccs[i]
    local value = tonumber(state.ccValues[cc]) or 0.0
    local fillH = math.floor(meterH * value + 0.5)

    addRect(display, x, meterTop, slotW, meterH, 0xff1e293b, 2)
    if fillH > 0 then
      addRect(display, x, meterTop + meterH - fillH, slotW, fillH, 0xff38bdf8, 2)
    end

    addText(display, x, meterBottom, slotW, FOOTER_H, tostring(cc), 0xffcbd5e1, 9, "center")
    x = x + slotW + SLOT_GAP
  end

  return display
end

function M.sync(ctx, widget)
  if not (ctx and widget and widget.node and widget.node.setDisplayList) then
    return
  end

  if ctx._midiParamRackDisplayDirty ~= true and ctx._midiParamRackLastW ~= nil and ctx._midiParamRackLastH ~= nil then
    local currentW = widget.node:getWidth()
    local currentH = widget.node:getHeight()
    if currentW == ctx._midiParamRackLastW and currentH == ctx._midiParamRackLastH then
      return
    end
  end

  local w = widget.node:getWidth()
  local h = widget.node:getHeight()
  widget.node:setDisplayList(buildDisplayList(ctx, w, h))
  if widget.node.repaint then
    widget.node:repaint()
  end
  ctx._midiParamRackLastW = w
  ctx._midiParamRackLastH = h
  ctx._midiParamRackDisplayDirty = false
end

return M

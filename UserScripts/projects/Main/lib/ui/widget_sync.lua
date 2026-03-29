-- Widget Sync Utilities
-- Helper functions for synchronizing widget state with DSP values

local M = {}

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.round(v)
  return math.floor(v + 0.5)
end

function M.repaint(widget)
  if widget and widget.repaint then
    widget:repaint()
  end
end

function M.syncValue(widget, value, epsilon)
  if not widget or not widget.getValue then return false end
  epsilon = epsilon or 0.0001
  local current = widget:getValue()
  if math.abs(current - value) > epsilon then
    widget:setValue(value)
    return true
  end
  return false
end

function M.syncToggleValue(widget, value)
  if not widget or not widget.getToggleState then return false end
  local current = widget:getToggleState() and 1 or 0
  local target = value and 1 or 0
  if current ~= target then
    widget:setToggleState(target > 0.5)
    return true
  end
  return false
end

function M.syncText(widget, text)
  if not widget or not widget.setText then return false end
  widget:setText(tostring(text))
  return true
end

function M.syncColour(widget, colour)
  if not widget or not widget.setColour then return false end
  widget:setColour(colour)
  return true
end

function M.syncSelected(widget, idx)
  if not widget or not widget.getSelected then return false end
  local current = widget:getSelected()
  if current ~= idx then
    widget:setSelected(idx)
    return true
  end
  return false
end

function M.syncKnobLabel(widget, label)
  if not widget or not widget.setLabel then return false end
  local getLabel = widget.getLabel
  local current = ""
  if getLabel then
    current = getLabel(widget) or ""
  end
  if current ~= label then
    widget:setLabel(label)
    return true
  end
  return false
end

return M

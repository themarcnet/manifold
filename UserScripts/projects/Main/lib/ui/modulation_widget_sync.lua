local M = {}

local function numbersClose(a, b, epsilon)
  local aa = tonumber(a) or 0.0
  local bb = tonumber(b) or 0.0
  return math.abs(aa - bb) <= (tonumber(epsilon) or 0.0001)
end

local function setWidgetValueSilently(widget, value)
  if not (widget and widget.setValue) then
    return
  end

  local onChange = widget._onChange
  widget._onChange = nil
  local ok, err = pcall(function()
    widget:setValue(value)
  end)
  widget._onChange = onChange
  if not ok then
    error(err)
  end
end

function M.getModTargetState(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local hook = type(_G) == "table" and _G.__midiSynthGetModTargetState or nil
  if type(hook) ~= "function" then
    return nil
  end
  local ok, state = pcall(hook, path)
  if ok then
    return state
  end
  return nil
end

function M.resolveValues(path, fallbackValue, readParam)
  local rawValue = fallbackValue
  if type(readParam) == "function" then
    rawValue = readParam(path, fallbackValue)
  end
  if rawValue == nil then
    rawValue = fallbackValue
  end

  local modState = M.getModTargetState(path)
  local baseValue = modState and tonumber(modState.baseValue) or rawValue
  local effectiveValue = modState and tonumber(modState.effectiveValue) or rawValue
  local modulationValue = modState and tonumber(modState.modulationValue) or nil
  if baseValue ~= nil and modulationValue ~= nil then
    effectiveValue = baseValue + modulationValue
  end
  return baseValue, effectiveValue, modState, rawValue
end

function M.projectEffectiveValue(path, baseValue, fallbackValue)
  local authoredBase = tonumber(baseValue)
  if authoredBase == nil then
    return fallbackValue
  end

  local modState = M.getModTargetState(path)
  if modState ~= nil then
    local modulationValue = tonumber(modState.modulationValue)
    if modulationValue ~= nil then
      return authoredBase + modulationValue
    end

    local stateBase = tonumber(modState.baseValue)
    local stateEffective = tonumber(modState.effectiveValue)
    if stateBase ~= nil and stateEffective ~= nil then
      return authoredBase + (stateEffective - stateBase)
    end
  end

  return authoredBase
end

function M.syncWidget(widget, baseValue, effectiveValue, modState, mapDisplayValue, epsilon)
  if not widget then
    return baseValue, effectiveValue, modState
  end

  local displayBaseValue = baseValue
  local displayEffectiveValue = effectiveValue
  if type(mapDisplayValue) == "function" then
    displayBaseValue = mapDisplayValue(displayBaseValue)
    displayEffectiveValue = mapDisplayValue(displayEffectiveValue)
  end

  if widget.setValue and not widget._dragging then
    local current = widget.getValue and widget:getValue() or nil
    if current == nil or not numbersClose(current, displayBaseValue, epsilon) then
      setWidgetValueSilently(widget, displayBaseValue)
    end
  end

  if widget.setModulationState then
    widget:setModulationState(displayBaseValue, displayEffectiveValue, {
      enabled = modState ~= nil and not numbersClose(displayBaseValue, displayEffectiveValue, epsilon),
    })
  end

  return displayBaseValue, displayEffectiveValue, modState
end

return M

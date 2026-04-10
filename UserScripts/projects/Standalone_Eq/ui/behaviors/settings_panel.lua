local M = {}

local SYNC_INTERVAL = 0.15

local function safeGetParam(path, fallback)
  if type(getParam) == "function" then
    local ok, value = pcall(getParam, path)
    if ok and value ~= nil then
      return value
    end
  end
  return fallback
end

local function safeSetParam(path, value)
  if type(setParam) == "function" then
    pcall(setParam, path, tonumber(value) or 0)
  elseif type(command) == "function" then
    pcall(command, "SET", path, tostring(tonumber(value) or 0))
  end
end

local function setLabelText(widget, text)
  if widget and widget.setText then
    widget:setText(text)
  elseif widget and widget.setLabel then
    widget:setLabel(text)
  end
end

local function formatPort(value)
  local n = math.floor((tonumber(value) or 0) + 0.5)
  if n <= 0 then
    return "-"
  end
  return tostring(n)
end

local function syncState(ctx)
  local widgets = ctx.widgets or {}
  local oscEnabled = safeGetParam('/plugin/ui/oscEnabled', 1) > 0.5
  local queryEnabled = safeGetParam('/plugin/ui/oscQueryEnabled', 1) > 0.5
  
  if queryEnabled and not oscEnabled then
    safeSetParam('/plugin/ui/oscEnabled', 1)
    oscEnabled = true
  end

  if widgets.osc_enabled_toggle and widgets.osc_enabled_toggle.setValue then
    widgets.osc_enabled_toggle:setValue(oscEnabled)
  end
  if widgets.osc_query_toggle then
    if widgets.osc_query_toggle.setEnabled then
      widgets.osc_query_toggle:setEnabled(oscEnabled)
    end
    if widgets.osc_query_toggle.setValue then
      widgets.osc_query_toggle:setValue(oscEnabled and queryEnabled)
    end
  end

  setLabelText(widgets.osc_port_value, formatPort(safeGetParam('/plugin/ui/oscInputPort', 0)))
  setLabelText(widgets.query_port_value, formatPort(safeGetParam('/plugin/ui/oscQueryPort', 0)))
end

local function bindControls(ctx)
  local widgets = ctx.widgets or {}
  if widgets.close_button then
    widgets.close_button._onClick = function()
      safeSetParam('/plugin/ui/settingsVisible', 0)
    end
  end

  if widgets.osc_enabled_toggle then
    widgets.osc_enabled_toggle._onChange = function(value)
      safeSetParam('/plugin/ui/oscEnabled', value and 1 or 0)
      if not value then
        safeSetParam('/plugin/ui/oscQueryEnabled', 0)
      end
      syncState(ctx)
    end
  end

  if widgets.osc_query_toggle then
    widgets.osc_query_toggle._onChange = function(value)
      if value then
        safeSetParam('/plugin/ui/oscEnabled', 1)
      end
      safeSetParam('/plugin/ui/oscQueryEnabled', value and 1 or 0)
      syncState(ctx)
    end
  end
end

function M.init(ctx)
  ctx._lastSyncTime = 0
  bindControls(ctx)
  syncState(ctx)
end

function M.resized(ctx)
  syncState(ctx)
end

function M.update(ctx)
  local now = type(getTime) == 'function' and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncState(ctx)
  end
end

return M

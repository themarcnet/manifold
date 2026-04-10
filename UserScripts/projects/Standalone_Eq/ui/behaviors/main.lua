local M = {}

local HEADER_H = 12
local SYNC_INTERVAL = 0.15
local CONTENT_W = 472
local CONTENT_H = 208

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

local function settingsVisible()
  return safeGetParam('/plugin/ui/settingsVisible', 0) > 0.5
end

local function perfVisible()
  return safeGetParam('/plugin/ui/devVisible', 0) > 0.5
end

local function getRuntimeWidget(ctx, suffix)
  local root = ctx.root
  local record = root and root._structuredRecord or nil
  local globalId = type(record) == 'table' and tostring(record.globalId or '') or ''
  local runtime = type(_G) == 'table' and rawget(_G, '__manifoldStructuredUiRuntime') or nil
  local runtimeWidgets = type(runtime) == 'table' and runtime.widgets or nil
  if globalId ~= '' and type(runtimeWidgets) == 'table' then
    return runtimeWidgets[globalId .. '.' .. suffix]
  end
  return nil
end

local function setVisible(widget, visible)
  if widget and widget.node then
    if widget.node.setVisible then
      widget.node:setVisible(visible)
    end
    if visible and widget.node.toFront then
      pcall(function() widget.node:toFront() end)
    end
    if widget.node.markRenderDirty then
      pcall(function() widget.node:markRenderDirty() end)
    end
    if widget.node.repaint then
      pcall(function() widget.node:repaint() end)
    end
  end
end

local function syncWidgetState(ctx)
  local widgets = ctx.widgets or {}
  local settings = settingsVisible()

  if widgets.dev_button then
    if widgets.dev_button.setValue then
      widgets.dev_button:setValue(settings)
    end
    if widgets.dev_button.setOnColour then
      widgets.dev_button:setOnColour(0xff475569)
    end
    if widgets.dev_button.setOffColour then
      widgets.dev_button:setOffColour(0x20ffffff)
    end
  end
end

local function layout(ctx)
  local root = ctx.root
  local widgets = ctx.widgets or {}
  if not (root and root.node) then
    return
  end

  local rootW = root.node:getWidth()
  local rootH = root.node:getHeight()
  if not rootW or rootW <= 0 or not rootH or rootH <= 0 then
    return
  end

  if widgets.header_bg and widgets.header_bg.node and widgets.header_bg.node.setBounds then
    widgets.header_bg.node:setBounds(0, 0, rootW, HEADER_H)
  end
  if widgets.header_accent and widgets.header_accent.node and widgets.header_accent.node.setBounds then
    widgets.header_accent.node:setBounds(0, 0, 18, HEADER_H)
  end
  if widgets.title and widgets.title.node and widgets.title.node.setBounds then
    widgets.title.node:setBounds(24, 0, math.max(80, rootW - 88), HEADER_H)
  end
  if widgets.dev_button and widgets.dev_button.node and widgets.dev_button.node.setBounds then
    widgets.dev_button.node:setBounds(math.max(0, rootW - 60), 0, 60, HEADER_H)
  end
  if widgets.content_bg and widgets.content_bg.node and widgets.content_bg.node.setBounds then
    widgets.content_bg.node:setBounds(0, HEADER_H, rootW, math.max(1, rootH - HEADER_H))
  end

  local contentW = math.max(1, rootW)
  local contentH = math.max(1, rootH - HEADER_H)

  local showSettings = settingsVisible()
  local showPerf = perfVisible()

  local eqComponent = getRuntimeWidget(ctx, 'eq_component')
  local settingsOverlay = getRuntimeWidget(ctx, 'settings_overlay')
  local perfOverlay = getRuntimeWidget(ctx, 'perf_overlay')

  if eqComponent and eqComponent.node then
    local scale = math.min(contentW / CONTENT_W, contentH / CONTENT_H)
    if not scale or scale <= 0 then
      scale = 1
    end
    local moduleW = math.max(1, math.floor(CONTENT_W * scale + 0.5))
    local moduleH = math.max(1, math.floor(CONTENT_H * scale + 0.5))
    local moduleX = math.floor((contentW - moduleW) * 0.5 + 0.5)
    local moduleY = HEADER_H + math.floor((contentH - moduleH) * 0.5 + 0.5)
    if eqComponent.node.setBounds then
      eqComponent.node:setBounds(moduleX, moduleY, moduleW, moduleH)
    end
    setVisible(eqComponent, not showSettings)
  end

  if settingsOverlay and settingsOverlay.node then
    if settingsOverlay.node.setBounds then
      settingsOverlay.node:setBounds(0, HEADER_H, rootW, contentH)
    end
    setVisible(settingsOverlay, showSettings)
  end

  if perfOverlay and perfOverlay.node then
    if perfOverlay.node.setBounds then
      perfOverlay.node:setBounds(0, HEADER_H, rootW, contentH)
    end
    setVisible(perfOverlay, showPerf and not showSettings)
  end

  syncWidgetState(ctx)
end

local function bindControls(ctx)
  local widgets = ctx.widgets or {}
  if widgets.dev_button then
    widgets.dev_button._onChange = function(value)
      safeSetParam('/plugin/ui/settingsVisible', value and 1 or 0)
      syncWidgetState(ctx)
      layout(ctx)
    end
  end
end

function M.init(ctx)
  ctx._lastSyncTime = 0
  bindControls(ctx)
  syncWidgetState(ctx)
  layout(ctx)
end

function M.resized(ctx)
  layout(ctx)
  syncWidgetState(ctx)
end

function M.update(ctx)
  local now = type(getTime) == 'function' and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    syncWidgetState(ctx)
    layout(ctx)
  end
end

return M

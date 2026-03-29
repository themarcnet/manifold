-- Scoped Widget Helpers
-- Utilities for finding widgets and behaviors by ID suffix within a scope

local M = {}

--- Check if text ends with suffix
function M.endsWith(text, suffix)
  if type(text) ~= "string" or type(suffix) ~= "string" then
    return false
  end
  if suffix == "" then
    return true
  end
  return text:sub(-#suffix) == suffix
end

--- Find this behavior's global ID prefix from the runtime behaviors list
function M.resolveGlobalPrefix(ctx)
  local runtime = _G.__manifoldStructuredUiRuntime
  if runtime and runtime.behaviors then
    for _, b in ipairs(runtime.behaviors) do
      if b.ctx == ctx then
        return b.id or "root"
      end
    end
  end
  return "root"
end

--- Find a widget by suffix within a root scope
function M.findScopedWidget(allWidgets, rootId, suffix)
  if type(allWidgets) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end

  local exact = nil
  if type(rootId) == "string" and rootId ~= "" then
    exact = allWidgets[rootId .. suffix]
  end
  if exact ~= nil then
    return exact
  end

  local bestKey = nil
  local bestWidget = nil
  for key, widget in pairs(allWidgets) do
    if type(key) == "string" and M.endsWith(key, suffix) then
      local rootMatches = type(rootId) ~= "string" or rootId == "" or key:sub(1, #rootId) == rootId
      if rootMatches then
        if bestKey == nil or #key < #bestKey then
          bestKey = key
          bestWidget = widget
        end
      end
    end
  end
  return bestWidget
end

--- Find a behavior by suffix within a root scope
function M.findScopedBehavior(runtime, rootId, suffix)
  if not (runtime and runtime.behaviors and type(suffix) == "string" and suffix ~= "") then
    return nil
  end

  local exactId = nil
  if type(rootId) == "string" and rootId ~= "" then
    exactId = rootId .. suffix
  end
  if exactId ~= nil then
    for _, behavior in ipairs(runtime.behaviors) do
      if behavior.id == exactId then
        return behavior
      end
    end
  end

  local best = nil
  for _, behavior in ipairs(runtime.behaviors) do
    local id = behavior.id
    if type(id) == "string" and M.endsWith(id, suffix) then
      local rootMatches = type(rootId) ~= "string" or rootId == "" or id:sub(1, #rootId) == rootId
      if rootMatches then
        if best == nil or #id < #(best.id or "") then
          best = behavior
        end
      end
    end
  end
  return best
end

--- Get a scoped widget with caching
function M.getScopedWidget(ctx, suffix)
  if type(ctx) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end
  local cache = ctx._scopedWidgetCache
  if type(cache) ~= "table" then
    cache = {}
    ctx._scopedWidgetCache = cache
  end
  local cached = cache[suffix]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local widget = M.findScopedWidget(ctx.allWidgets or {}, ctx._globalPrefix or "root", suffix)
  cache[suffix] = widget or false
  return widget
end

--- Get a scoped behavior with caching
function M.getScopedBehavior(ctx, suffix)
  if type(ctx) ~= "table" or type(suffix) ~= "string" or suffix == "" then
    return nil
  end
  local cache = ctx._scopedBehaviorCache
  if type(cache) ~= "table" then
    cache = {}
    ctx._scopedBehaviorCache = cache
  end
  local cached = cache[suffix]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local runtime = _G.__manifoldStructuredUiRuntime
  local behavior = M.findScopedBehavior(runtime, ctx._globalPrefix or "root", suffix)
  cache[suffix] = behavior or false
  return behavior
end

--- Flush deferred UI refreshes immediately
function M.flushDeferredRefreshesNow()
  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.flushDeferredRefreshes) == "function" then
    pcall(function() shell:flushDeferredRefreshes() end)
  end
end

--- Recursively refresh retained subtree
function M.refreshRetainedSubtree(node)
  if node == nil then
    return
  end

  if node.getUserData ~= nil then
    local meta = node:getUserData("_editorMeta")
    if type(meta) == "table" then
      local widget = meta.widget
      if type(widget) == "table" and type(widget.refreshRetained) == "function" then
        local w = 0
        local h = 0
        if node.getWidth ~= nil and node.getHeight ~= nil then
          w = tonumber(node:getWidth()) or 0
          h = tonumber(node:getHeight()) or 0
        elseif node.getBounds ~= nil then
          local _, _, bw, bh = node:getBounds()
          w = tonumber(bw) or 0
          h = tonumber(bh) or 0
        end
        pcall(function() widget:refreshRetained(w, h) end)
      end
    end
  end

  if node.getNumChildren ~= nil and node.getChild ~= nil then
    local childCount = math.max(0, math.floor(tonumber(node:getNumChildren()) or 0))
    for i = 0, childCount - 1 do
      local child = node:getChild(i)
      if child ~= nil then
        M.refreshRetainedSubtree(child)
      end
    end
  end
end

--- Force refresh of patchbay retained widgets
function M.forcePatchbayRetainedRefresh(widget, patchbayPanel)
  if widget and widget.node then
    M.refreshRetainedSubtree(widget.node)
    if widget.node.markRenderDirty then
      pcall(function() widget.node:markRenderDirty() end)
    end
    if widget.node.repaint then
      pcall(function() widget.node:repaint() end)
    end
  end

  if patchbayPanel and patchbayPanel.node then
    M.refreshRetainedSubtree(patchbayPanel.node)
    if patchbayPanel.node.markRenderDirty then
      pcall(function() patchbayPanel.node:markRenderDirty() end)
    end
    if patchbayPanel.node.repaint then
      pcall(function() patchbayPanel.node:repaint() end)
    end
  end

  M.flushDeferredRefreshesNow()
end

--- Set widget value without triggering onChange
function M.setWidgetValueSilently(widget, value)
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

return M

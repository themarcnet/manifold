local M = {}

function M.setBounds(widget, x, y, w, h)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.max(1, math.floor(tonumber(w) or 1))
  h = math.max(1, math.floor(tonumber(h) or 1))
  if widget and widget.setBounds then
    widget:setBounds(x, y, w, h)
  elseif widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(x, y, w, h)
  end
end

function M.setVisible(widget, visible)
  if widget and widget.setVisible then
    widget:setVisible(visible == true)
  elseif widget and widget.node and widget.node.setVisible then
    widget.node:setVisible(visible == true)
  end
end

function M.currentBounds(widget)
  if not (widget and widget.node and widget.node.getBounds) then
    return nil
  end
  local x, y, w, h = widget.node:getBounds()
  return math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(w) or 0), math.floor(tonumber(h) or 0)
end

function M.queueWidgetRefresh(queue, widget, w, h)
  if not widget then
    return
  end
  queue[#queue + 1] = { widget = widget, w = w, h = h }
end

function M.flushWidgetRefreshes(queue)
  for i = 1, #(queue or {}) do
    local item = queue[i]
    local widget = item.widget
    local node = widget and widget.node or nil
    if widget and widget.refreshRetained then
      widget:refreshRetained(item.w, item.h)
    end
    if node and node.markRenderDirty then
      pcall(function() node:markRenderDirty() end)
    end
    if node and node.repaint then
      pcall(function() node:repaint() end)
    end
  end

  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.flushDeferredRefreshes) == "function" and #(queue or {}) > 0 then
    pcall(function() shell:flushDeferredRefreshes() end)
  end
end

function M.setVisibleQueued(queue, widget, visible)
  if not (widget and widget.node) then
    return
  end
  local node = widget.node
  local nextVisible = visible == true
  local changed = node.isVisible and (node:isVisible() ~= nextVisible)
  M.setVisible(widget, nextVisible)
  if changed then
    local _, _, bw, bh = M.currentBounds(widget)
    M.queueWidgetRefresh(queue, widget, bw, bh)
  end
end

function M.setBoundsQueued(queue, widget, x, y, w, h)
  if not (widget and widget.node) then
    return
  end
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.max(1, math.floor(tonumber(w) or 1))
  h = math.max(1, math.floor(tonumber(h) or 1))
  local cx, cy, cw, ch = M.currentBounds(widget)
  if cx ~= x or cy ~= y or cw ~= w or ch ~= h then
    M.setBounds(widget, x, y, w, h)
    M.queueWidgetRefresh(queue, widget, w, h)
  end
end

function M.scaledRect(rect, scaleX, scaleY)
  local x = math.floor((tonumber(rect and rect.x) or 0) * scaleX + 0.5)
  local y = math.floor((tonumber(rect and rect.y) or 0) * scaleY + 0.5)
  local w = math.max(1, math.floor((tonumber(rect and rect.w) or 1) * scaleX + 0.5))
  local h = math.max(1, math.floor((tonumber(rect and rect.h) or 1) * scaleY + 0.5))
  return x, y, w, h
end

function M.applyScaledRect(queue, widget, rect, scaleX, scaleY)
  if type(rect) ~= "table" then
    return
  end
  local x, y, w, h = M.scaledRect(rect, scaleX, scaleY)
  M.setBoundsQueued(queue, widget, x, y, w, h)
end

function M.applyScaledSquareRect(queue, widget, rect, scaleX, scaleY)
  if type(rect) ~= "table" then
    return
  end
  local x, y, w, h = M.scaledRect(rect, scaleX, scaleY)
  local side = math.max(1, math.min(w, h))
  M.setBoundsQueued(queue, widget, x, y, side, side)
end

function M.layoutModeForWidth(width, cutoff)
  return (tonumber(width) or 0) < (tonumber(cutoff) or 300) and "compact" or "wide"
end

function M.scaleFactors(width, height, reference)
  local refW = math.max(1, tonumber(reference and reference.w) or 1)
  local refH = math.max(1, tonumber(reference and reference.h) or 1)
  return math.max(0.01, (tonumber(width) or refW) / refW), math.max(0.01, (tonumber(height) or refH) / refH)
end

return M

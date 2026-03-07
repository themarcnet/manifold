local M = {}

function M.init(ctx)
  ctx._tabs = ctx.widgets and ctx.widgets.tabs or nil
  _G.__looperTabsWidget = ctx._tabs
end

function M.resized(ctx, w, h)
  local tabs = ctx.widgets and ctx.widgets.tabs or nil
  if tabs and tabs.setBounds then
    tabs:setBounds(0, 0, w, h)
  end
end

function M.cleanup(ctx)
  if _G.__looperTabsWidget == ctx._tabs then
    _G.__looperTabsWidget = nil
  end
end

return M

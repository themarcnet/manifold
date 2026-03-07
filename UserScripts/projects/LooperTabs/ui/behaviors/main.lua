local Shared = require("behaviors.donut_shared_state")
local SuperSlot = require("behaviors.donut_super_slot")

local M = {}

local function ensureSuperSlot(ctx, force)
  local ok, err = SuperSlot.ensureLoaded(ctx and ctx.project or nil, Shared.getSelections(), force)
  _G.__looperTabsSuperSlotState = {
    ok = ok == true,
    error = err or "",
  }
  return ok == true
end

function M.init(ctx)
  ctx._tabs = ctx.widgets and ctx.widgets.tabs or nil
  _G.__looperTabsWidget = ctx._tabs
  _G.__looperTabsEnsureSuperSlot = function(force)
    return ensureSuperSlot(ctx, force == true)
  end
  ensureSuperSlot(ctx, false)
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
  _G.__looperTabsEnsureSuperSlot = nil
  _G.__looperTabsSuperSlotState = nil
end

return M

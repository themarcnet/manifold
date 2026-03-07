local Shared = require("behaviors.looper_shared_state")

local M = {}

function M.resized(ctx, w, h)
  local widgets = ctx.widgets or {}
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local componentIds = {
    "transport",
    "capture_plane",
    "layer0",
    "layer1",
    "layer2",
    "layer3",
  }

  for _, id in ipairs(componentIds) do
    local widget = widgets[id]
    local spec = Shared.getComponentSpec(ctx, id)
    Shared.applySpecRect(widget, spec, w, h, designW, designH)
  end
end

return M

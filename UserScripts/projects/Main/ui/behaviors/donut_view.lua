local Shared = require("behaviors.donut_shared_state")

local M = {}

local function getGlobalPrefix(ctx)
  local root = ctx and ctx.root or nil
  local node = root and root.node or nil
  local src = node and node.getUserData and node:getUserData("_structuredSource") or nil
  return type(src) == "table" and type(src.globalId) == "string" and src.globalId or ""
end

function M.resized(ctx, w, h)
  local widgets = ctx.allWidgets or {}
  local prefix = getGlobalPrefix(ctx)
  local designW, designH = Shared.getDesignSize(ctx, w, h)
  local componentIds = {
    "transport",
    "capture_plane",
    "vocal_fx",
    "layer0",
    "layer1",
    "layer2",
    "layer3",
  }

  for _, id in ipairs(componentIds) do
    local key = (prefix ~= "") and (prefix .. "." .. id) or id
    local widget = widgets[key]
    local spec = Shared.getComponentSpec(ctx, id)
    Shared.applySpecRect(widget, spec, w, h, designW, designH)
  end
end

return M

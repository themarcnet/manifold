-- Rack node shell behavior
-- Handles drag-to-reorder interactions

local M = {}

function M.onInit(ctx)
  print("[ShellBehavior] Init " .. tostring(ctx.id))
end

function M.onReady(ctx)
  print("[ShellBehavior] Ready " .. tostring(ctx.id))
  
  local node = ctx.node
  if not node then 
    print("[ShellBehavior] No node for " .. tostring(ctx.id))
    return 
  end
  
  -- Enable mouse interception
  node:setInterceptsMouse(true, false)
  print("[ShellBehavior] Wired " .. tostring(ctx.id))
  
  local isDragging = false
  
  node:setOnMouseDown(function(x, y)
    print("[Shell] MouseDown on " .. tostring(ctx.id) .. " at y=" .. y)
    if y > 20 then return end
    isDragging = true
  end)
  
  node:setOnMouseDrag(function(x, y)
    if not isDragging then return end
  end)
  
  node:setOnMouseUp(function(x, y)
    if not isDragging then return end
    isDragging = false
    print("[Shell] MouseUp on " .. tostring(ctx.id))
  end)
end

return M

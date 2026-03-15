-- Runtime Benchmark - Behavior
-- Dynamic node spawning and performance measurement

local M = {}

-- Benchmark state
M.count = 0
M.frames = 0
M.lastFps = 0
M.lastFpsTime = 0
M.isAnimating = false
M.lastSpawnMs = 0.0
M.lastClearMs = 0.0
M.lastAnimMs = 0.0
M.animPhase = 0.0
M.animNodes = {}

-- Entity layer reference (created dynamically under viewport)
M.entityLayer = nil

-- ============================================================================
-- Helpers
-- ============================================================================

local function nowSeconds()
  local t = getTime and getTime() or 0
  return t
end

-- ============================================================================
-- Core Benchmark Operations
-- ============================================================================

function M.clearNodes(ctx)
  local start = nowSeconds()
  
  if M.entityLayer ~= nil then
    M.entityLayer:clearChildren()
  end
  
  M.animNodes = {}
  M.count = 0
  M.isAnimating = false
  M.lastClearMs = (nowSeconds() - start) * 1000.0
  M.lastAnimMs = 0.0
  
  -- Update UI
  local w = ctx.widgets
  if w.animBtn then
    w.animBtn:setLabel("Anim: OFF")
  end
  M.updateStatsLabel(ctx)
end

function M.spawnNodes(ctx, num)
  -- Clear existing first
  M.clearNodes(ctx)
  
  local start = nowSeconds()
  local w = ctx.widgets
  
  if not w.viewport then return end
  
  -- Create entity layer if needed
  if not M.entityLayer then
    M.entityLayer = w.viewport.node:createChild("entityLayer")
    M.entityLayer:setBounds(0, 0, 0, 0)
  end
  
  local vw = w.viewport.node:getWidth()
  local vh = w.viewport.node:getHeight()
  if vw <= 12 then vw = 800 end
  if vh <= 12 then vh = 500 end
  
  M.entityLayer:setBounds(0, 0, vw, vh)
  
  -- Spawn nodes
  for i = 1, num do
    local node = M.entityLayer:createChild("entity_" .. i)
    local bx = math.random(0, math.max(0, vw - 10))
    local by = math.random(0, math.max(0, vh - 10))
    local size = 8 + (i % 3)
    local colour = 0xff000000
      + ((37 * i) % 255) * 0x10000
      + ((71 * i) % 255) * 0x100
      + ((113 * i) % 255)
    
    node:setBounds(bx, by, size, size)
    node:setDisplayList({
      {
        cmd = "fillRect",
        x = 0,
        y = 0,
        w = size,
        h = size,
        color = colour,
      }
    })
    
    M.animNodes[i] = {
      node = node,
      bx = bx,
      by = by,
      size = size,
      phase = (i % 1024) * 0.013,
      radius = 6 + (i % 23),
    }
  end
  
  M.count = num
  M.lastSpawnMs = (nowSeconds() - start) * 1000.0
  M.updateStatsLabel(ctx)
end

function M.toggleAnimation(ctx)
  M.isAnimating = not M.isAnimating
  
  local w = ctx.widgets
  if w.animBtn then
    w.animBtn:setLabel(M.isAnimating and "Anim: ON" or "Anim: OFF")
  end
  M.updateStatsLabel(ctx)
end

-- ============================================================================
-- UI Updates
-- ============================================================================

function M.updateStatsLabel(ctx)
  local w = ctx.widgets
  if not w.statsLabel then return end
  
  local status = string.format(
    "Nodes: %d  Spawn: %.2f ms  Clear: %.2f ms  Mode: %s",
    M.count,
    M.lastSpawnMs,
    M.lastClearMs,
    M.isAnimating and "animating" or "idle"
  )
  w.statsLabel:setText(status)
  
  if w.animLabel then
    w.animLabel:setText(string.format("Anim: %.2f ms", M.lastAnimMs))
  end
end

function M.updateFpsLabel(ctx)
  local w = ctx.widgets
  if w.fpsLabel then
    w.fpsLabel:setText(string.format("FPS: %d", M.lastFps))
  end
end

-- ============================================================================
-- Animation Loop
-- ============================================================================

function M.animate(ctx)
  if not M.isAnimating or M.count == 0 then
    return
  end
  
  local start = nowSeconds()
  M.animPhase = M.animPhase + 0.055
  
  for i = 1, M.count do
    local item = M.animNodes[i]
    if item and item.node then
      local px = item.bx + math.sin(M.animPhase + item.phase) * item.radius
      local py = item.by + math.cos(M.animPhase * 0.85 + item.phase) * item.radius
      item.node:setBounds(math.floor(px), math.floor(py), item.size, item.size)
    end
  end
  
  M.lastAnimMs = (nowSeconds() - start) * 1000.0
end

function M.updateFps(ctx)
  M.frames = M.frames + 1
  local now = nowSeconds()
  
  if now - M.lastFpsTime >= 1.0 then
    M.lastFps = M.frames
    M.frames = 0
    M.lastFpsTime = now
    M.updateFpsLabel(ctx)
    M.updateStatsLabel(ctx)
  end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function M.init(ctx)
  -- Wire buttons
  local w = ctx.widgets
  
  if w.spawn1k then
    w.spawn1k._onClick = function() M.spawnNodes(ctx, 1000) end
  end
  if w.spawn5k then
    w.spawn5k._onClick = function() M.spawnNodes(ctx, 5000) end
  end
  if w.spawn10k then
    w.spawn10k._onClick = function() M.spawnNodes(ctx, 10000) end
  end
  if w.spawn50k then
    w.spawn50k._onClick = function() M.spawnNodes(ctx, 50000) end
  end
  if w.clearBtn then
    w.clearBtn._onClick = function() M.clearNodes(ctx) end
  end
  if w.animBtn then
    w.animBtn._onClick = function() M.toggleAnimation(ctx) end
  end
  
  -- Init FPS timer
  M.lastFpsTime = nowSeconds()
  M.updateStatsLabel(ctx)
end

function M.resized(ctx, w, h)
  -- Update entity layer size if it exists
  if M.entityLayer then
    local viewport = ctx.widgets.viewport
    if viewport then
      local vw = viewport.node:getWidth()
      local vh = viewport.node:getHeight()
      M.entityLayer:setBounds(0, 0, vw, vh)
    end
  end
  
  -- Keep FPS label right-aligned
  local fpsLabel = ctx.widgets.fpsLabel
  if fpsLabel and fpsLabel.node then
    fpsLabel.node:setBounds(w - 120, 8, 112, 20)
  end
end

function M.update(ctx, state)
  M.animate(ctx)
  M.updateFps(ctx)
end

function M.cleanup(ctx)
  M.clearNodes(ctx)
  M.entityLayer = nil
end

-- ============================================================================
-- Extension Point for Future Benchmarks
-- ============================================================================

-- Future benchmarks can be added as:
-- M.benchmarks["mybench"] = {
--   init = function(ctx) ... end,
--   run = function(ctx, params) ... end,
--   cleanup = function(ctx) ... end,
-- }
-- 
-- Then wired to additional buttons in init()

return M

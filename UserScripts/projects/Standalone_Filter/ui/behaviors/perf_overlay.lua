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

local function setLabelText(widget, text)
  if widget and widget.setText then
    widget:setText(text)
  elseif widget and widget.setLabel then
    widget:setLabel(text)
  end
end

local function formatMB(value)
  local n = tonumber(value) or 0
  return string.format("%.1f MB", n)
end

local function formatInt(value)
  return tostring(math.floor((tonumber(value) or 0) + 0.5))
end

local function formatMicros(value)
  local n = math.floor((tonumber(value) or 0) + 0.5)
  return tostring(n) .. " us"
end

local function formatPercent(value)
  local n = math.floor((tonumber(value) or 0) + 0.5)
  return tostring(n) .. "%"
end

local function syncState(ctx)
  local w = ctx.widgets or {}
  
  -- Memory metrics
  setLabelText(w.val_pss, formatMB(safeGetParam('/plugin/ui/perf/pssMB', 0)))
  setLabelText(w.val_priv, formatMB(safeGetParam('/plugin/ui/perf/privateDirtyMB', 0)))
  setLabelText(w.val_lua, formatMB(safeGetParam('/plugin/ui/perf/luaHeapMB', 0)))
  setLabelText(w.val_heap, formatMB(safeGetParam('/plugin/ui/perf/glibcHeapMB', 0)))
  setLabelText(w.val_arena, formatMB(safeGetParam('/plugin/ui/perf/glibcArenaMB', 0)))
  setLabelText(w.val_mmap, formatMB(safeGetParam('/plugin/ui/perf/glibcMmapMB', 0)))
  setLabelText(w.val_free, formatMB(safeGetParam('/plugin/ui/perf/glibcFreeHeldMB', 0)))
  setLabelText(w.val_rel, formatMB(safeGetParam('/plugin/ui/perf/glibcReleasableMB', 0)))
  setLabelText(w.val_ar, formatInt(safeGetParam('/plugin/ui/perf/glibcArenaCount', 0)))
  
  -- Performance metrics
  setLabelText(w.val_frame, formatMicros(safeGetParam('/plugin/ui/perf/frameCurrentUs', 0)))
  setLabelText(w.val_avg, formatMicros(safeGetParam('/plugin/ui/perf/frameAvgUs', 0)))
  setLabelText(w.val_cpu, formatPercent(safeGetParam('/plugin/ui/perf/cpuPercent', 0)))
end

function M.init(ctx)
  ctx._lastSyncTime = 0
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

local M = {}

local SYNC_INTERVAL = 0.15

local function safeGetParam(path, fallback)
  if type(getParam) == "function" then
    local ok, value = pcall(getParam, path)
    if ok and value ~= nil then return value end
  end
  return fallback
end

local function setText(w, text)
  if w and w.setText then w:setText(text)
  elseif w and w.setLabel then w:setLabel(text) end
end

local function mb(v)
  return string.format("%.1f", tonumber(v) or 0)
end

local function us(v)
  return tostring(math.floor((tonumber(v) or 0) + 0.5))
end

local function pct(v)
  return tostring(math.floor((tonumber(v) or 0) + 0.5)) .. "%"
end

local function pair(prefix, a, b)
  return string.format("%s %s/%s", prefix, mb(a), mb(b))
end

local function syncState(ctx)
  local w = ctx.widgets or {}

  local pss = safeGetParam('/plugin/ui/perf/pssMB', 0)
  local priv = safeGetParam('/plugin/ui/perf/privateDirtyMB', 0)
  local luaMb = safeGetParam('/plugin/ui/perf/luaHeapMB', 0)
  local gpuTotal = safeGetParam('/plugin/ui/perf/gpuTotalMB', 0)
  local gpuFont = safeGetParam('/plugin/ui/perf/gpuFontAtlasMB', 0)
  local gpuSurf = safeGetParam('/plugin/ui/perf/gpuSurfaceColorMB', 0) + safeGetParam('/plugin/ui/perf/gpuSurfaceDepthMB', 0)

  setText(w.val_tot_pss, 'P ' .. mb(pss))
  setText(w.val_tot_priv, 'D ' .. mb(priv))
  setText(w.val_lua, 'L ' .. mb(luaMb))
  setText(w.val_gpu, 'G ' .. mb(gpuTotal))

  setText(w.val_plug_pss, 'P ' .. mb(safeGetParam('/plugin/ui/perf/pluginDeltaPssMB', 0)))
  setText(w.val_plug_priv, 'D ' .. mb(safeGetParam('/plugin/ui/perf/pluginDeltaPrivateDirtyMB', 0)))
  setText(w.val_plug_heap, 'H ' .. mb(safeGetParam('/plugin/ui/perf/pluginDeltaHeapMB', 0)))
  setText(w.val_gpu_detail, 'F ' .. mb(gpuFont) .. ' / S ' .. mb(gpuSurf))

  setText(w.val_ui_pss, 'P ' .. mb(safeGetParam('/plugin/ui/perf/uiDeltaPssMB', 0)))
  setText(w.val_ui_priv, 'D ' .. mb(safeGetParam('/plugin/ui/perf/uiDeltaPrivateDirtyMB', 0)))
  setText(w.val_ui_heap, 'H ' .. mb(safeGetParam('/plugin/ui/perf/uiDeltaHeapMB', 0)))
  setText(w.val_heap_arena, 'Heap ' .. mb(safeGetParam('/plugin/ui/perf/glibcHeapMB', 0)) .. ' / A ' .. mb(safeGetParam('/plugin/ui/perf/glibcArenaMB', 0)))

  setText(w.val_stage_dsp, pair('DSP', safeGetParam('/plugin/ui/perf/afterDspDeltaPssMB', 0), safeGetParam('/plugin/ui/perf/afterDspDeltaPrivateDirtyMB', 0)))
  setText(w.val_stage_ui, pair('Open', safeGetParam('/plugin/ui/perf/afterUiOpenDeltaPssMB', 0), safeGetParam('/plugin/ui/perf/afterUiOpenDeltaPrivateDirtyMB', 0)))
  setText(w.val_stage_idle, pair('Idle', safeGetParam('/plugin/ui/perf/afterUiIdleDeltaPssMB', 0), safeGetParam('/plugin/ui/perf/afterUiIdleDeltaPrivateDirtyMB', 0)))

  setText(w.val_dsp_cur, 'Cur ' .. us(safeGetParam('/plugin/ui/perf/dspCurrentUs', 0)))
  setText(w.val_dsp_avg, 'Avg ' .. us(safeGetParam('/plugin/ui/perf/dspAvgUs', 0)))
  setText(w.val_dsp_peak, 'Peak ' .. us(safeGetParam('/plugin/ui/perf/dspPeakUs', 0)))

  setText(w.val_ui_frame, 'Frm ' .. us(safeGetParam('/plugin/ui/perf/frameCurrentUs', 0)))
  setText(w.val_ui_avg, 'Avg ' .. us(safeGetParam('/plugin/ui/perf/frameAvgUs', 0)))
  setText(w.val_cpu, 'CPU ' .. pct(safeGetParam('/plugin/ui/perf/cpuPercent', 0)))
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

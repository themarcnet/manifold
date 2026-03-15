local W = require("ui_widgets")
local RuntimeHelpers = require("shell.runtime_script_utils")

local M = {}

local LIVE_SLOT = "live_editor"
local PARAM_ROW_H = 30
local PARAM_ROW_GAP = 8
local PARAM_SCROLL_STEP = 32

local parseDspParamDefsFromCode = RuntimeHelpers.parseDspParamDefsFromCode
local parseDspGraphFromCode = RuntimeHelpers.parseDspGraphFromCode
local collectRuntimeParamsForScript = RuntimeHelpers.collectRuntimeParamsForScript

local function clamp(v, lo, hi)
  local n = tonumber(v) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function round(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

local function repaint(widget)
  if widget and widget.node and widget.node.repaint then
    widget.node:repaint()
  end
end

local function setBounds(widget, x, y, w, h)
  if widget and widget.setBounds then
    widget:setBounds(math.floor(x), math.floor(y), math.floor(w), math.floor(h))
  elseif widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(math.floor(x), math.floor(y), math.floor(w), math.floor(h))
  end
end

local function setVisible(widget, visible)
  if widget and widget.setVisible then
    widget:setVisible(visible == true)
  elseif widget and widget.node and widget.node.setVisible then
    widget.node:setVisible(visible == true)
  end
end

local function setText(widget, text)
  if widget and widget.setText then
    widget:setText(text or "")
  end
end

local function pathStem(path)
  local p = tostring(path or "")
  local stem = p:match("([^/]+)$") or p
  return stem:gsub("%.lua$", "")
end

local function readText(path)
  if type(readTextFile) ~= "function" or type(path) ~= "string" or path == "" then
    return ""
  end
  local ok, text = pcall(readTextFile, path)
  if ok and type(text) == "string" then
    return text
  end
  return ""
end

local function getLastDspError()
  if type(getDspScriptLastError) ~= "function" then
    return ""
  end
  local ok, value = pcall(getDspScriptLastError)
  if ok and type(value) == "string" then
    return value
  end
  return ""
end

local function setDspSlotTransient(slot)
  if type(setDspSlotPersistOnUiSwitch) == "function" and type(slot) == "string" and slot ~= "" then
    pcall(setDspSlotPersistOnUiSwitch, slot, false)
  end
end

local function getAbsoluteBounds(node)
  if not (node and node.getBounds) then
    return 0, 0, 0, 0
  end

  local x, y, w, h = node:getBounds()
  local parent = node.getParent and node:getParent() or nil
  while parent do
    if parent.getBounds then
      local px, py = parent:getBounds()
      x = (tonumber(x) or 0) + (tonumber(px) or 0)
      y = (tonumber(y) or 0) + (tonumber(py) or 0)
    end
    parent = parent.getParent and parent:getParent() or nil
  end

  return math.floor(tonumber(x) or 0),
         math.floor(tonumber(y) or 0),
         math.max(0, math.floor(tonumber(w) or 0)),
         math.max(0, math.floor(tonumber(h) or 0))
end

local function inferStep(def)
  local minV = tonumber(def and def.min)
  local maxV = tonumber(def and def.max)
  if minV ~= nil and maxV ~= nil then
    local span = math.abs(maxV - minV)
    if span >= 8 then
      return 0.1
    end
    if span >= 2 then
      return 0.01
    end
    return 0.001
  end
  return 0.01
end

local function graphNodeColour(prim)
  local key = string.lower(tostring(prim or ""))
  if key:find("gain", 1, true) then return 0xff22c55e end
  if key:find("mix", 1, true) then return 0xffeab308 end
  if key:find("delay", 1, true) then return 0xfff59e0b end
  if key:find("filter", 1, true) or key:find("svf", 1, true) then return 0xffa855f7 end
  if key:find("chorus", 1, true) or key:find("phaser", 1, true) then return 0xff06b6d4 end
  if key:find("pitch", 1, true) or key:find("gran", 1, true) then return 0xfff97316 end
  if key:find("pass", 1, true) then return 0xff38bdf8 end
  return 0xff38bdf8
end

local function buildGraphDisplayList(ctx, w, h, zoom)
  zoom = zoom or 1.0
  local display = {
    { cmd = "fillRoundedRect", x = 0, y = 0, w = w, h = h, radius = 8, color = 0xff0b1220 },
    { cmd = "drawRoundedRect", x = 0, y = 0, w = w, h = h, radius = 8, thickness = 1, color = 0xff334155 },
    { cmd = "drawText", x = 10, y = 6, w = math.max(0, w - 20), h = 16, color = 0xff94a3b8, text = "Drag to pan", fontSize = 10.0, align = "left", valign = "middle" },
  }

  local graph = ctx._graphModel or { nodes = {}, edges = {} }
  local nodes = graph.nodes or {}
  local edges = graph.edges or {}

  display[#display + 1] = {
    cmd = "drawText",
    x = 10,
    y = 6,
    w = math.max(0, w - 20),
    h = 16,
    color = 0xff94a3b8,
    text = string.format("parsed nodes=%d edges=%d", #nodes, #edges),
    fontSize = 10.0,
    align = "right",
    valign = "middle",
  }

  if #nodes == 0 then
    display[#display + 1] = {
      cmd = "drawText",
      x = 10,
      y = 34,
      w = math.max(0, w - 20),
      h = 18,
      color = 0xff94a3b8,
      text = "No nodes parsed from script",
      fontSize = 11.0,
      align = "left",
      valign = "middle",
    }
    return display
  end

  local graphLeft = 10
  local graphTop = 30
  local graphW = math.max(1, w - 20)
  local graphH = math.max(1, h - 40)
  local count = #nodes
  local originX = graphLeft + (ctx._graphPanX or 0)
  local originY = graphTop + (ctx._graphPanY or 0)
  local grid = 36

  local gridOffsetX = ((originX % grid) + grid) % grid
  local gridOffsetY = ((originY % grid) + grid) % grid
  for gx = graphLeft - gridOffsetX, graphLeft + graphW, grid do
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = gx,
      y1 = graphTop,
      x2 = gx,
      y2 = graphTop + graphH,
      color = 0x18283a52,
      thickness = 1,
    }
  end
  for gy = graphTop - gridOffsetY, graphTop + graphH, grid do
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = graphLeft,
      y1 = gy,
      x2 = graphLeft + graphW,
      y2 = gy,
      color = 0x18283a52,
      thickness = 1,
    }
  end

  local barW = math.floor(8 * zoom)
  local portW = math.floor(barW * 0.5)  -- Half the ribbon width
  local portH = math.floor(16 * zoom)
  local nodeW = math.floor(math.min(140, math.max(100, math.floor(graphW / count) - 16)) * zoom)
  local nodeH = math.floor(48 * zoom)

  -- Topological sort: compute depth (longest path from any source)
  local depth = {}
  local inDegree = {}
  for i = 1, count do
    inDegree[i] = 0
    depth[i] = 0
  end
  for _, edge in ipairs(edges) do
    inDegree[edge.to] = inDegree[edge.to] + 1
  end
  -- Kahn's algorithm to assign depths
  local queue = {}
  for i = 1, count do
    if inDegree[i] == 0 then
      table.insert(queue, i)
      depth[i] = 0
    end
  end
  local processed = 0
  while #queue > 0 do
    local u = table.remove(queue, 1)
    processed = processed + 1
    for _, edge in ipairs(edges) do
      if edge.from == u then
        local v = edge.to
        depth[v] = math.max(depth[v], depth[u] + 1)
        inDegree[v] = inDegree[v] - 1
        if inDegree[v] == 0 then
          table.insert(queue, v)
        end
      end
    end
  end
  -- Group nodes by depth level
  local levels = {}
  local maxDepth = 0
  for i = 1, count do
    local d = depth[i] or 0
    maxDepth = math.max(maxDepth, d)
    levels[d] = levels[d] or {}
    table.insert(levels[d], i)
  end

  local positions = {}
  local minLevelWidth = nodeW + math.floor(60 * zoom)
  local levelWidth = math.max(minLevelWidth, math.floor(graphW / (maxDepth + 1)))
  local totalWidth = (maxDepth + 1) * levelWidth
  local offsetX = math.max(10, math.floor((graphW - totalWidth) * 0.5))

  -- Position nodes: x by depth level, y distributed within level
  for d = 0, maxDepth do
    local levelNodes = levels[d] or {}
    local levelCount = #levelNodes
    local totalH = levelCount * nodeH + (levelCount - 1) * 16
    local startY = math.floor((graphH - totalH) * 0.5)
    for i, nodeIdx in ipairs(levelNodes) do
      local x = math.floor(originX + offsetX + d * levelWidth + (levelWidth - nodeW) * 0.5)
      local y = math.floor(originY + startY + (i - 1) * (nodeH + 16))
      local accent = graphNodeColour(nodes[nodeIdx].prim)

      positions[nodeIdx] = {
        x = x,
        y = y,
        w = nodeW,
        h = nodeH,
        cx = x + math.floor(nodeW * 0.5),
        cy = y + math.floor(nodeH * 0.5),
        accent = accent,
        outputX = x + nodeW,
        outputY = y + math.floor(nodeH * 0.5) - math.floor(portH * 0.5),
        inputX = x,
        inputY = y + math.floor(nodeH * 0.5) - math.floor(portH * 0.5),
      }
    end
  end

  for i = 1, #edges do
    local edge = edges[i]
    local a = positions[tonumber(edge.from) or 0]
    local b = positions[tonumber(edge.to) or 0]
    if a and b then
      local startX = a.outputX + portW
      local startY = a.outputY + math.floor(portH * 0.5)
      local endX = b.inputX + math.floor(barW * 0.5)  -- Cutout only covers half the ribbon
      local endY = b.inputY + math.floor(portH * 0.5)

      local elbowX = startX + math.max(20, math.floor((endX - startX) * 0.4))

      display[#display + 1] = {
        cmd = "drawLine",
        x1 = startX,
        y1 = startY,
        x2 = elbowX,
        y2 = startY,
        color = 0xff94a3b8,
        thickness = 2,
      }
      display[#display + 1] = {
        cmd = "drawLine",
        x1 = elbowX,
        y1 = startY,
        x2 = elbowX,
        y2 = endY,
        color = 0xff94a3b8,
        thickness = 2,
      }
      display[#display + 1] = {
        cmd = "drawLine",
        x1 = elbowX,
        y1 = endY,
        x2 = endX,
        y2 = endY,
        color = 0xff94a3b8,
        thickness = 2,
      }
    end
  end

  for i = 1, #nodes do
    local node = nodes[i]
    local p = positions[i]
    local accent = p.accent
    local label = tostring(node.var or "") .. " : " .. tostring(node.prim or "")
    local pad = 10
    local textX = p.x + barW + pad
    local textW = p.w - barW - pad * 2

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = p.x + 2,
      y = p.y + 2,
      w = p.w,
      h = p.h,
      radius = 6,
      color = 0x30000000,
    }

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = p.x,
      y = p.y,
      w = p.w,
      h = p.h,
      radius = 6,
      color = 0xff172030,
    }

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = p.x,
      y = p.y,
      w = barW,
      h = p.h,
      radius = 6,
      color = accent,
    }

    -- Selection highlight
    if ctx._graphSelectedNode == i then
      display[#display + 1] = {
        cmd = "drawRoundedRect",
        x = p.x - 2,
        y = p.y - 2,
        w = p.w + 4,
        h = p.h + 4,
        radius = 8,
        thickness = 2,
        color = 0xffffffff,
      }
    end

    display[#display + 1] = {
      cmd = "drawRoundedRect",
      x = p.x,
      y = p.y,
      w = p.w,
      h = p.h,
      radius = 6,
      thickness = 1,
      color = accent,
    }

    display[#display + 1] = {
      cmd = "fillRect",
      x = p.inputX,
      y = p.inputY,
      w = portW,
      h = portH,
      color = 0xff0b1220,
    }

    display[#display + 1] = {
      cmd = "drawRect",
      x = p.inputX,
      y = p.inputY,
      w = portW,
      h = portH,
      thickness = 1,
      color = 0xff334155,
    }

    display[#display + 1] = {
      cmd = "fillRect",
      x = p.outputX,
      y = p.outputY,
      w = portW,
      h = portH,
      color = accent,
    }

    display[#display + 1] = {
      cmd = "drawText",
      x = textX,
      y = p.y + 3,
      w = textW,
      h = p.h - 6,
      color = 0xffe2e8f0,
      text = label,
      fontSize = 10.5 * zoom,
      align = "left",
      valign = "middle",
    }
  end

  return display
end

local function syncGraphDisplay(ctx)
  local graphCanvas = ctx.widgets and ctx.widgets.graphCanvas or nil
  if not (graphCanvas and graphCanvas.node and graphCanvas.node.setDisplayList) then
    return
  end

  local w = math.max(1, round(graphCanvas.node:getWidth()))
  local h = math.max(1, round(graphCanvas.node:getHeight()))
  graphCanvas.node:setClipRect(0, 0, w, h)
  graphCanvas.node:setDisplayList(buildGraphDisplayList(ctx, w, h, ctx._graphZoom or 1.0))
  repaint(graphCanvas)
end

local function syncMetrics(ctx)
  local nodeCount = tonumber(type(getParam) == "function" and getParam("/manifold/debug/graphNodeCount") or 0) or 0
  local routeCount = tonumber(type(getParam) == "function" and getParam("/manifold/debug/graphRouteCount") or 0) or 0
  local inputRms = tonumber(type(getParam) == "function" and getParam("/manifold/debug/graphInputRms") or 0) or 0
  local wetRms = tonumber(type(getParam) == "function" and getParam("/manifold/debug/graphWetRms") or 0) or 0
  local mixRms = tonumber(type(getParam) == "function" and getParam("/manifold/debug/graphMixedRms") or 0) or 0

  setText(ctx.widgets.graphMetrics,
    string.format("runtime nodes=%d routes=%d | RMS in=%.4f wet=%.4f mix=%.4f",
      round(nodeCount), round(routeCount), inputRms, wetRms, mixRms))
end

local function syncEditorClosedUi(ctx)
  local visible = ctx._editorVisible ~= false
  setVisible(ctx.widgets.editorHostFrame, visible)
  setVisible(ctx.widgets.editorClosedLabel, not visible)
  setVisible(ctx.widgets.openEditorButton, not visible)
  if not visible then
    setText(ctx.widgets.editorClosedLabel, "Editor closed. Re-open to continue editing " .. tostring(ctx._currentName or "script") .. ".")
  end
end

local function syncHeaderStatus(ctx)
  local status = tostring(ctx._status or "Ready")
  local path = tostring(ctx._currentPath or "")
  if path ~= "" then
    status = status .. " | " .. path
  end
  setText(ctx.widgets.headerStatus, status)
  setText(ctx.widgets.runtimeStatus, tostring(ctx._runtimeStatus or "Runtime idle"))
  setText(ctx.widgets.lastError, "Error: " .. tostring(ctx._lastError or "none"))
end

local function ensureProjectEditorState(ctx)
  if type(shell) ~= "table" then
    return nil
  end

  shell.projectScriptEditor = shell.projectScriptEditor or {
    kind = "",
    ownership = "",
    name = "",
    path = "",
    text = "",
    cursorPos = 1,
    selectionAnchor = nil,
    dragAnchorPos = nil,
    scrollRow = 1,
    focused = false,
    status = "",
    lastClickTime = 0,
    lastClickLine = -1,
    clickStreak = 0,
    dirty = false,
    syncToken = 0,
    bodyRect = nil,
  }

  return shell.projectScriptEditor
end

local function syncEditorHost(ctx)
  local editorState = ensureProjectEditorState(ctx)
  if not editorState then
    return
  end

  local frame = ctx.widgets and ctx.widgets.editorHostFrame or nil
  local shellMode = type(shell) == "table" and tostring(shell.mode or "") or ""
  local editContentMode = type(shell) == "table" and tostring(shell.editContentMode or "") or ""
  local visible = ctx._editorVisible ~= false
    and frame ~= nil
    and frame.node ~= nil
    and ctx._currentPath ~= ""
    and not (shellMode == "edit" and editContentMode == "script")
  local bounds = { x = 0, y = 0, w = 0, h = 0 }

  if visible then
    local x, y, w, h = getAbsoluteBounds(frame.node)
    visible = w > 0 and h > 0
    bounds = { x = x, y = y, w = w, h = h }
  end

  editorState.kind = "dsp"
  editorState.ownership = ""
  editorState.name = ctx._currentName or pathStem(ctx._currentPath)
  editorState.path = ctx._currentPath or ""
  editorState.text = ctx._currentText or ""
  editorState.status = ctx._status or ""
  editorState.bodyRect = nil

  if type(shell.defineSurface) == "function" then
    shell:defineSurface("projectScriptEditor", {
      id = "projectScriptEditor",
      kind = "tool",
      backend = "imgui",
      visible = visible,
      bounds = bounds,
      z = 60,
      mode = "global",
      docking = "fill",
      interactive = true,
      modal = false,
      payloadKey = "projectScriptEditor",
      title = "DSP Live Script",
    })
  end
end

local function setDropdownPopupVisual(dropdown, open)
  if not dropdown then
    return
  end
  if dropdown._open == (open == true) then
    return
  end
  dropdown._open = open == true
  if dropdown._syncRetained then
    dropdown:_syncRetained()
  end
  repaint(dropdown)
end

local function syncScriptDropdownWidget(ctx)
  local dropdown = ctx.widgets and ctx.widgets.scriptDropdown or nil
  local rows = ctx._scriptRows or {}
  if not dropdown then
    return
  end

  local options = {}
  for i = 1, #rows do
    options[i] = rows[i].name
  end
  if #options == 0 then
    options[1] = "No DSP scripts found"
  end

  dropdown:setOptions(options)
  dropdown:setSelected(clamp(ctx._selectedIndex or 1, 1, #options))
end

local function getScriptPopupBounds(ctx)
  local dropdown = ctx.widgets and ctx.widgets.scriptDropdown or nil
  local root = ctx.root and ctx.root.node or nil
  if not (dropdown and dropdown.node and root) then
    return { x = 0, y = 0, w = 0, h = 0 }
  end

  local x, y, w, h = getAbsoluteBounds(dropdown.node)
  local optionCount = math.max(1, #(ctx._scriptRows or {}))
  local visibleRows = math.max(1, math.min(optionCount, 10))
  local popupW = math.max(220, w)
  local popupH = visibleRows * 28 + 8
  local rootW = math.max(1, round(root:getWidth()))
  local rootH = math.max(1, round(root:getHeight()))
  local popupX = x
  local popupY = y + h

  if popupY + popupH > rootH then
    popupY = y - popupH
  end
  popupY = clamp(popupY, 0, math.max(0, rootH - popupH))
  if popupX + popupW > rootW then
    popupX = math.max(0, rootW - popupW)
  end

  return {
    x = round(popupX),
    y = round(popupY),
    w = round(popupW),
    h = round(popupH),
  }
end

local function closeScriptPopup(ctx)
  ctx._scriptPopupOpen = false
  setDropdownPopupVisual(ctx.widgets and ctx.widgets.scriptDropdown or nil, false)
  if type(shell) == "table" and type(shell.defineSurface) == "function" then
    shell:defineSurface("scriptList", {
      id = "scriptList",
      kind = "tool",
      backend = "imgui",
      visible = false,
      bounds = { x = 0, y = 0, w = 0, h = 0 },
      z = 65,
      mode = "global",
      docking = "floating",
      interactive = true,
      modal = false,
      payloadKey = "scriptRows",
      title = "Scripts",
    })
    shell.scriptListActions = nil
  end
end

local function syncScriptPopupSurface(ctx)
  if type(shell) ~= "table" or type(shell.defineSurface) ~= "function" then
    return false
  end

  local rows = {}
  local sourceRows = ctx._scriptRows or {}
  for i = 1, #sourceRows do
    rows[i] = {
      section = false,
      nonInteractive = false,
      active = false,
      dirty = false,
      kind = "dsp",
      ownership = "",
      path = sourceRows[i].path,
      name = sourceRows[i].name,
      label = sourceRows[i].name,
      selected = (i == (ctx._selectedIndex or 1)),
    }
  end
  shell.scriptRows = rows
  shell.scriptListActions = {
    select = function(_shellRef, row, index)
      ctx._selectedIndex = clamp(tonumber(index) or 1, 1, math.max(1, #sourceRows))
      ctx._selectedPath = row and row.path or ""
      ctx._status = row and ("Selected " .. tostring(row.name or pathStem(row.path))) or "Ready"
      syncScriptDropdownWidget(ctx)
      closeScriptPopup(ctx)
      syncHeaderStatus(ctx)
    end,
    open = function(_shellRef, row, index)
      ctx._selectedIndex = clamp(tonumber(index) or 1, 1, math.max(1, #sourceRows))
      ctx._selectedPath = row and row.path or ""
      syncScriptDropdownWidget(ctx)
      closeScriptPopup(ctx)
      loadSelectedScript(ctx, ctx._selectedIndex, true)
      refreshRuntimeParams(ctx)
      rebuildParamControls(ctx)
      refreshParamWidgets(ctx)
      syncHeaderStatus(ctx)
    end,
  }

  local bounds = getScriptPopupBounds(ctx)
  shell:defineSurface("scriptList", {
    id = "scriptList",
    kind = "tool",
    backend = "imgui",
    visible = ctx._scriptPopupOpen == true,
    bounds = bounds,
    z = 65,
    mode = "global",
    docking = "floating",
    interactive = true,
    modal = false,
    payloadKey = "scriptRows",
    title = "Scripts",
  })
  return true
end

local function toggleScriptPopup(ctx)
  local dropdown = ctx.widgets and ctx.widgets.scriptDropdown or nil
  if not dropdown then
    return
  end

  if ctx._scriptPopupOpen == true then
    closeScriptPopup(ctx)
    return
  end

  if syncScriptPopupSurface(ctx) then
    ctx._scriptPopupOpen = true
    setDropdownPopupVisual(dropdown, true)
    syncScriptPopupSurface(ctx)
    return
  end

  dropdown:open()
end

local loadSelectedScript
local refreshRuntimeParams
local rebuildParamControls
local refreshParamWidgets

local function onEditorTextChanged(ctx, nextText)
  local text = tostring(nextText or "")
  if text == tostring(ctx._currentText or "") then
    return
  end

  ctx._currentText = text
  ctx._graphModel = parseDspGraphFromCode(text)
  ctx._paramDefs = parseDspParamDefsFromCode(text)
  refreshRuntimeParams(ctx)
  rebuildParamControls(ctx)
  refreshParamWidgets(ctx)
  syncGraphDisplay(ctx)
end

local function syncEditorTextFromHost(ctx)
  if type(shell) ~= "table" or type(shell.projectScriptEditor) ~= "table" then
    return
  end
  local editorState = shell.projectScriptEditor
  if tostring(editorState.path or "") ~= tostring(ctx._currentPath or "") then
    return
  end
  onEditorTextChanged(ctx, editorState.text or "")
end

local function refreshScriptDropdown(ctx)
  local rows = {}
  if type(listDspScripts) == "function" then
    local ok, scripts = pcall(listDspScripts)
    if ok and type(scripts) == "table" then
      for i = 1, #scripts do
        local script = scripts[i]
        if type(script) == "table" then
          local path = tostring(script.path or "")
          rows[#rows + 1] = {
            name = tostring(script.name or pathStem(path) or ("Script " .. tostring(i))),
            path = path,
          }
        end
      end
    end
  end

  local defaultPath = tostring((ctx.project and ctx.project.root or "") .. "/dsp/default_dsp.lua")
  local hasDefault = false
  for i = 1, #rows do
    if rows[i].path == defaultPath then
      hasDefault = true
      break
    end
  end
  if not hasDefault and defaultPath ~= "/dsp/default_dsp.lua" then
    rows[#rows + 1] = {
      name = "default_dsp",
      path = defaultPath,
    }
  end

  table.sort(rows, function(a, b)
    local an = string.lower(tostring(a.name or ""))
    local bn = string.lower(tostring(b.name or ""))
    if an == bn then
      return tostring(a.path or "") < tostring(b.path or "")
    end
    return an < bn
  end)

  if #rows == 0 then
    rows[1] = {
      name = "default_dsp",
      path = defaultPath,
    }
  end

  ctx._scriptRows = rows

  local selected = 1
  local wantedPath = tostring(ctx._selectedPath or ctx._currentPath or "")
  local defaultIndex = 1
  for i = 1, #rows do
    local pathLower = string.lower(rows[i].path or "")
    if pathLower:find("default_dsp%.lua", 1, false) or string.lower(rows[i].name or "") == "default_dsp" then
      defaultIndex = i
    end
    if wantedPath ~= "" and rows[i].path == wantedPath then
      selected = i
    end
  end
  if wantedPath == "" then
    selected = defaultIndex
  end

  ctx._selectedIndex = clamp(selected, 1, #rows)
  ctx._selectedPath = rows[ctx._selectedIndex] and rows[ctx._selectedIndex].path or ""
  syncScriptDropdownWidget(ctx)
  if ctx._scriptPopupOpen == true then
    syncScriptPopupSurface(ctx)
  end
end

loadSelectedScript = function(ctx, index, forceOpen)
  local rows = ctx._scriptRows or {}
  local idx = clamp(index or ctx._selectedIndex or 1, 1, math.max(1, #rows))
  local row = rows[idx]
  if not row then
    return
  end

  local text = readText(row.path)
  ctx._selectedIndex = idx
  ctx._selectedPath = row.path
  ctx._currentRow = row
  ctx._currentPath = row.path
  ctx._currentName = row.name or pathStem(row.path)
  ctx._currentText = text
  ctx._graphModel = parseDspGraphFromCode(text)
  ctx._paramDefs = parseDspParamDefsFromCode(text)
  ctx._status = "Loaded " .. tostring(ctx._currentName)
  ctx._lastError = getLastDspError()
  if forceOpen ~= false then
    ctx._editorVisible = true
  end

  local editorState = ensureProjectEditorState(ctx)
  if editorState then
    editorState.kind = "dsp"
    editorState.ownership = ""
    editorState.name = ctx._currentName
    editorState.path = ctx._currentPath
    editorState.text = ctx._currentText
    editorState.cursorPos = 1
    editorState.selectionAnchor = nil
    editorState.dragAnchorPos = nil
    editorState.scrollRow = 1
    editorState.focused = false
    editorState.status = ctx._status
    editorState.lastClickTime = 0
    editorState.lastClickLine = -1
    editorState.clickStreak = 0
    editorState.dirty = false
    editorState.syncToken = (tonumber(editorState.syncToken) or 0) + 1
  end

  syncScriptDropdownWidget(ctx)
  if ctx._scriptPopupOpen == true then
    syncScriptPopupSurface(ctx)
  end
  syncEditorClosedUi(ctx)
  syncEditorHost(ctx)
  syncGraphDisplay(ctx)
end

local function stopLiveSlot(ctx)
  setDspSlotTransient(LIVE_SLOT)
  local ok = false
  if type(unloadDspSlot) == "function" then
    ok = unloadDspSlot(LIVE_SLOT) == true
  end
  if ok then
    ctx._runtimeStatus = "Live editor slot unloaded"
  else
    ctx._runtimeStatus = "No live editor slot to unload"
  end
  ctx._lastError = getLastDspError()
end

local function runCurrentScript(ctx)
  if type(ctx._currentText) ~= "string" or ctx._currentText == "" then
    ctx._runtimeStatus = "Nothing to run"
    return
  end

  setDspSlotTransient(LIVE_SLOT)

  local sourceName = string.format(
    "project:dsp_live:%s:%d",
    tostring(ctx._currentName or "script"),
    #ctx._currentText)

  local ok = false
  if type(loadDspScriptFromStringInSlot) == "function" then
    ok = loadDspScriptFromStringInSlot(ctx._currentText, sourceName, LIVE_SLOT) == true
  elseif type(loadDspScriptFromString) == "function" then
    ok = loadDspScriptFromString(ctx._currentText, sourceName) == true
  end

  if ok then
    ctx._runtimeStatus = "Loaded script into live editor slot"
  else
    local err = getLastDspError()
    ctx._runtimeStatus = "DSP load failed" .. ((err ~= "") and (": " .. err) or "")
  end

  ctx._lastError = getLastDspError()
end

refreshRuntimeParams = function(ctx)
  local defs = ctx._paramDefs or {}
  local row = {
    name = ctx._currentName or pathStem(ctx._currentPath),
    path = ctx._currentPath or "",
  }
  ctx._runtimeParams = collectRuntimeParamsForScript(row, nil, defs, LIVE_SLOT)
end

local function clearParamControls(ctx)
  for i = 1, #(ctx._paramControls or {}) do
    local control = ctx._paramControls[i]
    if control and control.widget and control.widget.node then
      control.widget.node:setVisible(false)
    end
  end
  ctx._paramControls = {}
  local body = ctx.widgets and ctx.widgets.paramsBody or nil
  if body and body.node and body.node.clearChildren then
    body.node:clearChildren()
  end
end

rebuildParamControls = function(ctx)
  clearParamControls(ctx)
  local body = ctx.widgets and ctx.widgets.paramsBody or nil
  if not (body and body.node) then
    return
  end

  local controls = {}
  local runtimeParams = ctx._runtimeParams or {}
  local defs = ctx._paramDefs or {}

  -- Get MIDI device list if available
  local midiDevices = {}
  if type(Midi) == "table" and type(Midi.inputDevices) == "function" then
    local ok, devices = pcall(Midi.inputDevices)
    if ok and type(devices) == "table" then
      midiDevices = devices
    end
  end

  for i = 1, #defs do
    local def = defs[i]
    local runtime = runtimeParams[i] or {
      path = def.path,
      endpointPath = def.path,
      active = false,
      numericValue = def.default,
      min = def.min,
      max = def.max,
      step = def.step,
    }

    local minV = tonumber(runtime.min)
    local maxV = tonumber(runtime.max)
    local defaultV = tonumber(def.default)

    if minV == nil then minV = tonumber(defaultV) or 0 end
    if maxV == nil then maxV = minV + 1 end
    if maxV <= minV then maxV = minV + 1 end

    local control = {
      widget = nil,
      def = def,
      runtime = runtime,
    }

    local path = runtime.path or def.path or ""
    local isMidiDeviceParam = path:match("^/midi/device/input$") or path:match("^/midi/.*/device$")

    if isMidiDeviceParam and #midiDevices > 0 then
      -- Create dropdown for MIDI device selection
      local options = {}
      for idx, name in ipairs(midiDevices) do
        options[idx] = name
      end
      -- Add "None" option at start
      table.insert(options, 1, "None")

      -- Find root node for dropdown overlay positioning
      local rootNode = ctx.root and ctx.root.node or body.node
      while rootNode and rootNode.getParent do
        local parent = rootNode:getParent()
        if not parent then break end
        rootNode = parent
      end
      
      local widget = W.Dropdown.new(body.node, "runtimeParam" .. tostring(i), {
        label = "MIDI Input Device",
        options = options,
        selected = math.min(math.floor((runtime.numericValue or -1) + 2), #options),
        max_visible_rows = 8,
        rootNode = rootNode,
        on_select = function(idx, value)
          if ctx._syncingParams == true then
            return
          end
          local activeRuntime = control.runtime or runtime
          local endpoint = activeRuntime.endpointPath or activeRuntime.path or def.path
          if type(endpoint) ~= "string" or endpoint == "" then
            return
          end
          -- idx is 1-based index, subtract 2 for 0-based device index (-1 = None at index 1)
          local deviceIndex = idx - 2
          if type(setParam) == "function" then
            local ok = setParam(endpoint, deviceIndex)
            if ok == false then
              ctx._runtimeStatus = "setParam failed: " .. endpoint
            else
              ctx._runtimeStatus = string.format("MIDI device selected: %s", value or "None")
              activeRuntime.numericValue = deviceIndex
            end
            ctx._lastError = getLastDspError()
          end
          -- Also open the MIDI device directly
          if deviceIndex >= 0 and type(Midi) == "table" and type(Midi.openInput) == "function" then
            pcall(Midi.openInput, deviceIndex)
          end
        end,
      })
      control.widget = widget
      control.isDropdown = true
    else
      -- Standard slider for other params
      local widget = W.Slider.new(body.node, "runtimeParam" .. tostring(i), {
        label = runtime.path or def.path or ("Param " .. tostring(i)),
        min = minV,
        max = maxV,
        value = tonumber(runtime.numericValue) or tonumber(defaultV) or minV,
        step = tonumber(runtime.step) or inferStep(def),
        colour = runtime.active and 0xff38bdf8 or 0xff475569,
        bg = 0xff1e293b,
        showValue = true,
        on_change = function(value)
          if ctx._syncingParams == true then
            return
          end
          local activeRuntime = control.runtime or runtime
          if activeRuntime.active ~= true then
            return
          end
          local endpoint = activeRuntime.endpointPath or activeRuntime.path or def.path
          if type(endpoint) ~= "string" or endpoint == "" then
            return
          end
          if type(setParam) == "function" then
            local ok = setParam(endpoint, value)
            if ok == false then
              ctx._runtimeStatus = "setParam failed: " .. endpoint
            else
              ctx._runtimeStatus = string.format("set %s = %.4f", endpoint, tonumber(value) or 0)
              activeRuntime.numericValue = tonumber(value)
            end
            ctx._lastError = getLastDspError()
          end
        end,
      })
      control.widget = widget
    end

    controls[#controls + 1] = control
  end

  ctx._paramControls = controls
  ctx._paramScroll = 0
end

local function getParamContentHeight(ctx)
  local count = #(ctx._paramControls or {})
  if count <= 0 then
    return 28
  end
  return 8 + count * PARAM_ROW_H + math.max(0, count - 1) * PARAM_ROW_GAP + 8
end

local function getParamViewportHeight(ctx)
  local body = ctx.widgets and ctx.widgets.paramsBody or nil
  if not (body and body.node and body.node.getHeight) then
    return 0
  end
  return math.max(0, round(body.node:getHeight()))
end

local function getParamMaxScroll(ctx)
  return math.max(0, getParamContentHeight(ctx) - getParamViewportHeight(ctx))
end

local function relayoutParamControls(ctx)
  local controls = ctx._paramControls or {}
  local body = ctx.widgets and ctx.widgets.paramsBody or nil
  if not (body and body.node and body.node.getWidth) then
    return
  end

  local bodyW = math.max(0, round(body.node:getWidth()))
  local y = 8 - round(ctx._paramScroll or 0)
  local controlW = math.max(0, bodyW - 16)

  for i = 1, #controls do
    local control = controls[i]
    setBounds(control.widget, 8, y, controlW, PARAM_ROW_H)
    
    -- For dropdowns, calculate and set absolute position for overlay
    if control.isDropdown and control.widget and control.widget.setAbsolutePos then
      local absX, absY = getAbsoluteBounds(control.widget.node)
      control.widget:setAbsolutePos(absX, absY)
    end
    
    y = y + PARAM_ROW_H + PARAM_ROW_GAP
  end

  local maxScroll = getParamMaxScroll(ctx)
  local slider = ctx.widgets and ctx.widgets.paramScrollSlider or nil
  if slider then
    ctx._syncingParams = true
    if maxScroll > 0 then
      slider:setEnabled(true)
      slider:setValue(1.0 - ((ctx._paramScroll or 0) / maxScroll))
    else
      slider:setEnabled(false)
      slider:setValue(1.0)
    end
    ctx._syncingParams = false
  end

  if #controls == 0 then
    setText(ctx.widgets.paramState, "No ctx.params.register(...) found in current script")
  else
    local activeCount = 0
    for i = 1, #controls do
      if controls[i].runtime and controls[i].runtime.active then
        activeCount = activeCount + 1
      end
    end
    setText(ctx.widgets.paramState,
      string.format("Declared params: %d | Active runtime params: %d", #controls, activeCount))
  end

  if maxScroll > 0 then
    setText(ctx.widgets.paramScrollInfo,
      string.format("Scroll: %d/%d", round(ctx._paramScroll or 0), round(maxScroll)))
  else
    setText(ctx.widgets.paramScrollInfo, "Scroll: none")
  end
end

refreshParamWidgets = function(ctx)
  local controls = ctx._paramControls or {}
  local runtimeParams = ctx._runtimeParams or {}
  local dirtyShape = #controls ~= #runtimeParams

  if not dirtyShape then
    for i = 1, #controls do
      if not controls[i].runtime or controls[i].runtime.path ~= runtimeParams[i].path then
        dirtyShape = true
        break
      end
    end
  end

  if dirtyShape then
    rebuildParamControls(ctx)
    controls = ctx._paramControls or {}
  end

  ctx._syncingParams = true
  for i = 1, #controls do
    local control = controls[i]
    local runtime = runtimeParams[i] or control.runtime or {}
    control.runtime = runtime

    local widget = control.widget
    local label = runtime.active and tostring(runtime.path or "") or (tostring(runtime.path or "") .. " (inactive)")
    widget._label = label
    widget._colour = runtime.active and 0xff38bdf8 or 0xff475569
    widget:setEnabled(runtime.active == true)

    local value = tonumber(runtime.numericValue)
    if widget._dragging ~= true then
      if control.isDropdown then
        -- Dropdown uses setSelected (1-based index)
        -- value=-1 (None) -> idx=1, value=0 (first device) -> idx=2, etc.
        local idx = math.floor((value or -1) + 2)
        if type(widget.setSelected) == "function" then
          widget:setSelected(idx)
        end
      else
        -- Slider uses setValue
        if value ~= nil then
          widget:setValue(value)
        elseif control.def and control.def.default ~= nil then
          widget:setValue(control.def.default)
        end
      end
    end

    if widget.refreshRetained then
      widget:refreshRetained()
    end
    repaint(widget)
  end
  ctx._syncingParams = false

  relayoutParamControls(ctx)
end

local function handleParamScroll(ctx, deltaY)
  local maxScroll = getParamMaxScroll(ctx)
  if maxScroll <= 0 then
    ctx._paramScroll = 0
    relayoutParamControls(ctx)
    return
  end

  local nextScroll = tonumber(ctx._paramScroll) or 0
  if deltaY > 0 then
    nextScroll = nextScroll - PARAM_SCROLL_STEP
  elseif deltaY < 0 then
    nextScroll = nextScroll + PARAM_SCROLL_STEP
  end

  ctx._paramScroll = clamp(nextScroll, 0, maxScroll)
  relayoutParamControls(ctx)
end

local function installMainEditorActionHandlers(ctx)
  if type(shell) ~= "table" then
    return
  end

  shell.mainScriptEditorActions = {
    save = function(shellRef)
      local ed = type(shellRef) == "table" and shellRef.projectScriptEditor or nil
      if type(ed) ~= "table" or tostring(ed.path or "") == "" then
        return
      end
      if type(writeTextFile) ~= "function" then
        ctx._status = "writeTextFile unavailable"
        return
      end
      local ok = writeTextFile(ed.path, ed.text or "")
      if ok == false then
        ctx._status = "Save failed"
      else
        ed.text = readText(ed.path)
        ed.dirty = false
        ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
        ctx._status = "Saved " .. tostring(ctx._currentName or pathStem(ed.path))
        ctx._lastError = getLastDspError()
        onEditorTextChanged(ctx, ed.text or "")
        syncEditorHost(ctx)
      end
      syncHeaderStatus(ctx)
    end,
    reload = function(shellRef)
      local ed = type(shellRef) == "table" and shellRef.projectScriptEditor or nil
      if type(ed) ~= "table" or tostring(ed.path or "") == "" then
        return
      end
      ed.text = readText(ed.path)
      ed.cursorPos = 1
      ed.selectionAnchor = nil
      ed.dragAnchorPos = nil
      ed.scrollRow = 1
      ed.dirty = false
      ed.syncToken = (tonumber(ed.syncToken) or 0) + 1
      ctx._status = "Reloaded from disk"
      ctx._lastError = getLastDspError()
      onEditorTextChanged(ctx, ed.text or "")
      syncEditorHost(ctx)
      syncHeaderStatus(ctx)
    end,
    close = function(_shellRef)
      closeScriptPopup(ctx)
      ctx._editorVisible = false
      ctx._status = "Editor closed"
      syncEditorClosedUi(ctx)
      syncEditorHost(ctx)
      syncHeaderStatus(ctx)
    end,
  }
end

local function resizeLayout(ctx, w, h)
  local widgets = ctx.widgets or {}
  local width = math.max(1, round(w or 0))
  local height = math.max(1, round(h or 0))
  local pad = 16
  local gap = 12
  local headerH = 86
  local bodyY = pad + headerH + 12
  local bodyH = math.max(0, height - bodyY - pad)
  local leftW = math.floor((width - pad * 2 - gap) * 0.58)
  local rightW = math.max(260, width - pad * 2 - gap - leftW)
  local rightX = pad + leftW + gap
  local graphH = math.floor((bodyH - gap) * 0.42)
  local paramsY = bodyY + graphH + gap
  local paramsH = math.max(140, bodyH - graphH - gap)

  setBounds(widgets.header, pad, pad, width - pad * 2, headerH)
  setBounds(widgets.title, pad + 16, pad + 12, 420, 24)
  setBounds(widgets.subtitle, pad + 16, pad + 40, 560, 16)

  local runW = 62
  local refreshW = 92
  local loadW = 80
  local stopW = 60
  local topY = pad + 12
  local x = width - pad - stopW
  setBounds(widgets.stopButton, x, topY, stopW, 28)
  x = x - 8 - runW
  setBounds(widgets.runButton, x, topY, runW, 28)
  x = x - 8 - refreshW
  setBounds(widgets.refreshButton, x, topY, refreshW, 28)
  x = x - 8 - loadW
  setBounds(widgets.loadButton, x, topY, loadW, 28)
  local dropdownX = math.max(pad + 300, x - 308)
  setBounds(widgets.scriptDropdown, dropdownX, topY, math.max(180, x - 8 - dropdownX), 28)
  setBounds(widgets.headerStatus, dropdownX, pad + 44, width - pad - dropdownX, 16)
  if widgets.scriptDropdown and widgets.scriptDropdown.setAbsolutePos then
    widgets.scriptDropdown:setAbsolutePos(dropdownX, topY)
  end

  setBounds(widgets.editorPanel, pad, bodyY, leftW, bodyH)
  setBounds(widgets.editorTitle, pad + 14, bodyY + 10, 220, 18)
  setBounds(widgets.editorSubtext, pad + 14, bodyY + 30, leftW - 28, 16)
  setBounds(widgets.editorHostFrame, pad + 14, bodyY + 58, leftW - 28, math.max(0, bodyH - 72))
  setBounds(widgets.editorClosedLabel, pad + 38, bodyY + math.max(80, math.floor(bodyH * 0.48)), leftW - 80, 22)
  setBounds(widgets.openEditorButton, pad + 38, bodyY + math.max(110, math.floor(bodyH * 0.48) + 30), 120, 28)

  setBounds(widgets.graphPanel, rightX, bodyY, rightW, graphH)
  setBounds(widgets.graphTitle, rightX + 16, bodyY + 10, rightW - 32, 18)
  setBounds(widgets.graphSubtext, rightX + 16, bodyY + 30, rightW - 32, 16)
  setBounds(widgets.graphCanvas, rightX + 16, bodyY + 56, rightW - 32, math.max(0, graphH - 72))

  setBounds(widgets.paramsPanel, rightX, paramsY, rightW, paramsH)
  setBounds(widgets.paramsTitle, rightX + 16, paramsY + 10, rightW - 32, 18)
  setBounds(widgets.paramState, rightX + 16, paramsY + 32, rightW - 32, 16)
  setBounds(widgets.runtimeStatus, rightX + 16, paramsY + 52, rightW - 32, 16)
  setBounds(widgets.graphMetrics, rightX + 16, paramsY + 72, rightW - 32, 16)
  setBounds(widgets.lastError, rightX + 16, paramsY + 92, rightW - 32, 16)
  setBounds(widgets.paramScrollInfo, rightX + 16, paramsY + 112, rightW - 32, 16)

  local paramsBodyY = paramsY + 136
  local paramsBodyH = math.max(0, paramsH - 152)
  local scrollbarVisible = getParamMaxScroll(ctx) > 0
  local scrollW = scrollbarVisible and 14 or 0
  local scrollGap = scrollbarVisible and 8 or 0
  local paramsBodyW = math.max(0, rightW - 32 - scrollW - scrollGap)

  setBounds(widgets.paramsBody, rightX + 16, paramsBodyY, paramsBodyW, paramsBodyH)
  setBounds(widgets.paramScrollSlider, rightX + 16 + paramsBodyW + scrollGap, paramsBodyY, scrollW, paramsBodyH)
  setVisible(widgets.paramScrollSlider, scrollbarVisible)

  syncEditorClosedUi(ctx)
  syncEditorHost(ctx)
  syncGraphDisplay(ctx)
  relayoutParamControls(ctx)
end

function M.init(ctx)
  ctx._scriptRows = {}
  ctx._selectedIndex = 1
  ctx._selectedPath = ""
  ctx._currentRow = nil
  ctx._currentPath = ""
  ctx._currentName = ""
  ctx._currentText = ""
  ctx._graphModel = { nodes = {}, edges = {} }
  ctx._graphPanX = 0
  ctx._graphPanY = 0
  ctx._graphZoom = 1.0
  ctx._graphDragging = false
  ctx._graphAltDragging = false
  ctx._graphDragStartX = 0
  ctx._graphDragStartY = 0
  ctx._graphDragPanX = 0
  ctx._graphDragPanY = 0
  ctx._graphDragZoom = 1.0
  ctx._graphSelectedNode = nil
  ctx._scriptPopupOpen = false
  ctx._paramDefs = {}
  ctx._runtimeParams = {}
  ctx._paramControls = {}
  ctx._paramScroll = 0
  ctx._editorVisible = true
  ctx._status = "Ready"
  ctx._runtimeStatus = "Runtime idle"
  ctx._lastError = "none"
  ctx._syncingParams = false

  installMainEditorActionHandlers(ctx)

  local widgets = ctx.widgets or {}
  if widgets.scriptDropdown then
    widgets.scriptDropdown._onSelect = function(idx)
      ctx._selectedIndex = clamp(idx, 1, math.max(1, #(ctx._scriptRows or {})))
      local row = (ctx._scriptRows or {})[ctx._selectedIndex]
      ctx._selectedPath = row and row.path or ""
      ctx._status = row and ("Selected " .. tostring(row.name or pathStem(row.path))) or "Ready"
      syncScriptDropdownWidget(ctx)
      syncHeaderStatus(ctx)
    end
    widgets.scriptDropdown.onClick = function(_dropdown)
      toggleScriptPopup(ctx)
    end
  end

  if widgets.loadButton then
    widgets.loadButton._onClick = function()
      closeScriptPopup(ctx)
      loadSelectedScript(ctx, ctx._selectedIndex, true)
      refreshRuntimeParams(ctx)
      rebuildParamControls(ctx)
      refreshParamWidgets(ctx)
      syncHeaderStatus(ctx)
    end
  end

  if widgets.refreshButton then
    widgets.refreshButton._onClick = function()
      closeScriptPopup(ctx)
      refreshScriptDropdown(ctx)
      ctx._status = "Refreshed DSP script list"
      syncHeaderStatus(ctx)
    end
  end

  if widgets.runButton then
    widgets.runButton._onClick = function()
      closeScriptPopup(ctx)
      syncEditorTextFromHost(ctx)
      runCurrentScript(ctx)
      refreshRuntimeParams(ctx)
      refreshParamWidgets(ctx)
      syncHeaderStatus(ctx)
    end
  end

  if widgets.stopButton then
    widgets.stopButton._onClick = function()
      closeScriptPopup(ctx)
      stopLiveSlot(ctx)
      refreshRuntimeParams(ctx)
      refreshParamWidgets(ctx)
      syncHeaderStatus(ctx)
    end
  end

  if widgets.openEditorButton then
    widgets.openEditorButton._onClick = function()
      closeScriptPopup(ctx)
      ctx._editorVisible = true
      ctx._status = "Editor opened"
      syncEditorClosedUi(ctx)
      syncEditorHost(ctx)
      syncHeaderStatus(ctx)
    end
  end

  if widgets.paramScrollSlider then
    widgets.paramScrollSlider._onChange = function(value)
      if ctx._syncingParams == true then
        return
      end
      local maxScroll = getParamMaxScroll(ctx)
      if maxScroll <= 0 then
        ctx._paramScroll = 0
      else
        ctx._paramScroll = clamp((1.0 - (tonumber(value) or 0)) * maxScroll, 0, maxScroll)
      end
      relayoutParamControls(ctx)
    end
  end

  if widgets.paramsBody and widgets.paramsBody.node and widgets.paramsBody.node.setOnMouseWheel then
    widgets.paramsBody.node:setOnMouseWheel(function(_mx, _my, deltaY)
      handleParamScroll(ctx, deltaY)
    end)
  end

  if widgets.graphCanvas and widgets.graphCanvas.node then
    widgets.graphCanvas.node:setInterceptsMouse(true, false)
    widgets.graphCanvas.node:setOnMouseDown(function(mx, my, shift, ctrl, alt)
      local _ = shift
      _ = ctrl
      local graph = ctx._graphModel or { nodes = {}, edges = {} }
      local nodes = graph.nodes or {}
      local edges = graph.edges or {}
      local count = #nodes
      
      if count == 0 then
        ctx._graphDragging = true
        ctx._graphDragStartX = round(mx or 0)
        ctx._graphDragStartY = round(my or 0)
        ctx._graphDragPanX = round(ctx._graphPanX or 0)
        ctx._graphDragPanY = round(ctx._graphPanY or 0)
        return
      end
      
      -- Hit test against nodes
      local zoom = ctx._graphZoom or 1.0
      local w = math.max(1, round(widgets.graphCanvas.node:getWidth()))
      local h = math.max(1, round(widgets.graphCanvas.node:getHeight()))
      local graphW = math.max(1, w - 20)
      local graphH = math.max(1, h - 40)
      local originX = 10 + (ctx._graphPanX or 0)
      local originY = 30 + (ctx._graphPanY or 0)
      
      -- Recalculate layout to get exact positions
      local nodeW = math.floor(math.min(140, math.max(100, math.floor(graphW / count) - 16)) * zoom)
      local nodeH = math.floor(48 * zoom)
      
      -- Build positions (simplified from buildGraphDisplayList)
      local depth = {}
      local inDegree = {}
      for i = 1, count do
        inDegree[i] = 0
        depth[i] = 0
      end
      for _, edge in ipairs(edges) do
        inDegree[edge.to] = inDegree[edge.to] + 1
      end
      local queue = {}
      for i = 1, count do
        if inDegree[i] == 0 then
          table.insert(queue, i)
          depth[i] = 0
        end
      end
      while #queue > 0 do
        local u = table.remove(queue, 1)
        for _, edge in ipairs(edges) do
          if edge.from == u then
            local v = edge.to
            depth[v] = math.max(depth[v], depth[u] + 1)
            inDegree[v] = inDegree[v] - 1
            if inDegree[v] == 0 then
              table.insert(queue, v)
            end
          end
        end
      end
      local levels = {}
      local maxDepth = 0
      for i = 1, count do
        local d = depth[i] or 0
        maxDepth = math.max(maxDepth, d)
        levels[d] = levels[d] or {}
        table.insert(levels[d], i)
      end
      local minLevelWidth = nodeW + math.floor(60 * zoom)
      local levelWidth = math.max(minLevelWidth, math.floor(graphW / (maxDepth + 1)))
      local totalWidth = (maxDepth + 1) * levelWidth
      local offsetX = math.max(10, math.floor((graphW - totalWidth) * 0.5))
      
      -- Hit test
      local selected = nil
      for d = 0, maxDepth do
        local levelNodes = levels[d] or {}
        local levelCount = #levelNodes
        local totalLevelH = levelCount * nodeH + (levelCount - 1) * 16
        local startY = math.floor((graphH - totalLevelH) * 0.5)
        for i, nodeIdx in ipairs(levelNodes) do
          local nx = math.floor(originX + offsetX + d * levelWidth + (levelWidth - nodeW) * 0.5)
          local ny = math.floor(originY + startY + (i - 1) * (nodeH + 16))
          if mx >= nx and mx <= nx + nodeW and my >= ny and my <= ny + nodeH then
            selected = nodeIdx
            break
          end
        end
        if selected then break end
      end
      
      ctx._graphSelectedNode = selected
      
      if alt then
        -- Alt+drag will zoom at point (handled on drag start)
        ctx._graphAltDragging = true
        ctx._graphDragStartX = round(mx or 0)
        ctx._graphDragStartY = round(my or 0)
        ctx._graphDragZoom = ctx._graphZoom or 1.0
      else
        ctx._graphDragging = true
        ctx._graphDragStartX = round(mx or 0)
        ctx._graphDragStartY = round(my or 0)
        ctx._graphDragPanX = round(ctx._graphPanX or 0)
        ctx._graphDragPanY = round(ctx._graphPanY or 0)
      end
      
      syncGraphDisplay(ctx)
    end)
    widgets.graphCanvas.node:setOnMouseDrag(function(mx, my, _dx, _dy)
      if ctx._graphAltDragging then
        -- Alt+drag zoom
        local startY = ctx._graphDragStartY or 0
        local deltaY = (my or 0) - startY
        local factor = 1.0 - deltaY * 0.01
        local newZoom = clamp((ctx._graphDragZoom or 1.0) * factor, 0.3, 3.0)
        ctx._graphZoom = newZoom
        syncGraphDisplay(ctx)
        return
      end
      if ctx._graphDragging ~= true then
        return
      end
      ctx._graphPanX = round((ctx._graphDragPanX or 0) + ((mx or 0) - (ctx._graphDragStartX or 0)))
      ctx._graphPanY = round((ctx._graphDragPanY or 0) + ((my or 0) - (ctx._graphDragStartY or 0)))
      syncGraphDisplay(ctx)
    end)
    widgets.graphCanvas.node:setOnMouseUp(function(_mx, _my)
      ctx._graphDragging = false
      ctx._graphAltDragging = false
    end)
    widgets.graphCanvas.node:setOnMouseWheel(function(mx, my, deltaY, shift, ctrl, alt)
      local _ = shift
      _ = ctrl
      if not alt then
        return
      end
      local zoom = ctx._graphZoom or 1.0
      local factor = deltaY > 0 and 1.1 or 0.9
      local newZoom = clamp(zoom * factor, 0.3, 3.0)
      if math.abs(newZoom - zoom) < 0.0001 then
        return
      end
      -- Zoom at point: keep the design point under mouse stable
      local graphW = math.max(1, round(widgets.graphCanvas.node:getWidth()) - 20)
      local graphH = math.max(1, round(widgets.graphCanvas.node:getHeight()) - 40)
      local designX = mx - (ctx._graphPanX or 0) - 10
      local designY = my - (ctx._graphPanY or 0) - 30
      ctx._graphZoom = newZoom
      ctx._graphPanX = mx - 10 - designX * (newZoom / zoom)
      ctx._graphPanY = my - 30 - designY * (newZoom / zoom)
      syncGraphDisplay(ctx)
    end)
  end

  refreshScriptDropdown(ctx)
  loadSelectedScript(ctx, ctx._selectedIndex, true)
  refreshRuntimeParams(ctx)
  rebuildParamControls(ctx)
  refreshParamWidgets(ctx)
  syncMetrics(ctx)
  syncEditorClosedUi(ctx)
  syncHeaderStatus(ctx)

  -- MIDI state for polling
  ctx._midiLastNote = nil

  -- Parameter modulation state
  ctx._modState = {
    active = false,
    lfo1Phase = 0,
    lfo2Phase = 0,
    lfo3Phase = 0,
    lastTime = 0,
    -- Config (read from runtime params)
    lfo1Rate = 0.5,
    lfo1Depth = 0.5,
    lfo2Rate = 0.2,
    lfo2Depth = 0.4,
    lfo3Rate = 4,
    lfo3Depth = 0.1,
    -- Base values (user-set, LFOs modulate around these)
    filterCutoff = 1500,
    chorusRate = 0.5,
    oscFreq = 220,
  }

  -- Arpeggiator state
  ctx._arpState = {
    heldNotes = {},       -- {note=N, velocity=V} sorted by note
    heldNoteSet = {},     -- note → true (for fast lookup)
    sequence = {},        -- built from held notes + pattern + octaves
    seqIndex = 0,         -- current position in sequence
    seqDirection = 1,     -- 1=forward, -1=backward (for updown)
    lastStepTime = 0,     -- getTime() of last step
    gateOffTime = 0,      -- getTime() when current gate should close
    gateOpen = false,     -- is a note currently sounding
    active = false,       -- are we in arp mode (script has /arp/ params)
    -- Config (read from DSP params by UI)
    tempo = 120,
    rate = 2,             -- 0=1/4, 1=1/8, 2=1/16, 3=1/32, 4=1/64
    pattern = 0,          -- 0=up, 1=down, 2=updown, 3=random
    octaves = 1,
    gateLen = 0.8,
    swing = 0,
    stepCount = 0,        -- total steps taken (for swing)
  }
end

-- ============================================================================
-- Parameter Modulation Engine (runs in UI update loop, drives DSP via setParam)
-- ============================================================================

local function modIsActive(ctx)
  -- Mod mode is active if the loaded script declares /mod/lfo1/rate param
  local defs = ctx._paramDefs or {}
  for i = 1, #defs do
    if (defs[i].path or "") == "/mod/lfo1/rate" then
      return true
    end
  end
  return false
end

local function modReadConfigFromParams(ctx)
  local mod = ctx._modState
  if not mod then return end

  local wasActive = mod.active
  mod.active = modIsActive(ctx)
  if not mod.active then return end

  -- On first activation, seed base values from defaults
  local justActivated = mod.active and not wasActive

  local controls = ctx._paramControls or {}
  for i = 1, #controls do
    local c = controls[i]
    local path = c.def and c.def.path or ""
    local val = c.runtime and c.runtime.numericValue
    if not val then goto continue end

    -- LFO config params: always read (these aren't modulation targets)
    if path == "/mod/lfo1/rate" then mod.lfo1Rate = clamp(val, 0.05, 10)
    elseif path == "/mod/lfo1/depth" then mod.lfo1Depth = clamp(val, 0, 1)
    elseif path == "/mod/lfo2/rate" then mod.lfo2Rate = clamp(val, 0.05, 5)
    elseif path == "/mod/lfo2/depth" then mod.lfo2Depth = clamp(val, 0, 1)
    elseif path == "/mod/lfo3/rate" then mod.lfo3Rate = clamp(val, 0.1, 12)
    elseif path == "/mod/lfo3/depth" then mod.lfo3Depth = clamp(val, 0, 1)

    -- Modulation TARGET base values: update on first activation or when user drags
    -- (prevents reading back our own modulated values as the new base)
    elseif justActivated or (c.widget and c.widget._dragging == true) then
      if path == "/mod/filter/cutoff" then mod.filterCutoff = clamp(val, 100, 8000)
      elseif path == "/mod/chorus/rate" then mod.chorusRate = clamp(val, 0.1, 5)
      elseif path == "/mod/osc/freq" then mod.oscFreq = clamp(val, 40, 880)
      end
    end

    ::continue::
  end
end

local function modUpdate(ctx)
  local mod = ctx._modState
  if not mod or not mod.active then return end

  local now = 0
  if type(getTime) == "function" then
    now = getTime()
  elseif os and os.clock then
    now = os.clock()
  end

  local dt = now - (mod.lastTime or now)
  mod.lastTime = now

  -- Clamp dt to avoid huge jumps on first frame or after pause
  if dt <= 0 or dt > 0.2 then
    return
  end

  -- Advance LFO phases
  mod.lfo1Phase = mod.lfo1Phase + dt * mod.lfo1Rate * 2 * math.pi
  mod.lfo2Phase = mod.lfo2Phase + dt * mod.lfo2Rate * 2 * math.pi
  mod.lfo3Phase = mod.lfo3Phase + dt * mod.lfo3Rate * 2 * math.pi

  -- Wrap phases
  local TWO_PI = 2 * math.pi
  while mod.lfo1Phase > TWO_PI do mod.lfo1Phase = mod.lfo1Phase - TWO_PI end
  while mod.lfo2Phase > TWO_PI do mod.lfo2Phase = mod.lfo2Phase - TWO_PI end
  while mod.lfo3Phase > TWO_PI do mod.lfo3Phase = mod.lfo3Phase - TWO_PI end

  -- Compute LFO values (-1 to +1)
  local lfo1 = math.sin(mod.lfo1Phase)
  local lfo2 = math.sin(mod.lfo2Phase)
  local lfo3 = math.sin(mod.lfo3Phase)

  if type(setParam) ~= "function" then return end

  -- LFO1 → filter cutoff (exponential mapping for musical response)
  if mod.lfo1Depth > 0.001 then
    local modAmount = lfo1 * mod.lfo1Depth
    -- Modulate in octaves: depth=1 means ±2 octaves
    local modulated = mod.filterCutoff * math.pow(2, modAmount * 2)
    modulated = clamp(modulated, 100, 12000)
    setParam("/mod/filter/cutoff", modulated)
  end

  -- LFO2 → chorus rate
  if mod.lfo2Depth > 0.001 then
    local modAmount = lfo2 * mod.lfo2Depth
    local modulated = mod.chorusRate * (1 + modAmount)
    modulated = clamp(modulated, 0.1, 5)
    setParam("/mod/chorus/rate", modulated)
  end

  -- LFO3 → oscillator frequency (vibrato)
  if mod.lfo3Depth > 0.001 then
    local modAmount = lfo3 * mod.lfo3Depth
    -- Modulate in semitones: depth=1 means ±2 semitones
    local modulated = mod.oscFreq * math.pow(2, modAmount * 2 / 12)
    modulated = clamp(modulated, 20, 2000)
    setParam("/mod/osc/freq", modulated)
  end
end

-- ============================================================================
-- Arpeggiator Engine (runs in UI update loop, drives DSP via setParam)
-- ============================================================================

local function arpIsActive(ctx)
  -- Arp mode is active if the loaded script declares /arp/note and /arp/gate params
  local defs = ctx._paramDefs or {}
  for i = 1, #defs do
    local p = defs[i].path or ""
    if p == "/arp/note" or p == "/arp/gate" then
      return true
    end
  end
  return false
end

local function arpBuildSequence(arp)
  -- Build the note sequence from held notes + pattern + octaves
  local held = {}
  for i = 1, #arp.heldNotes do
    held[i] = arp.heldNotes[i]
  end

  if #held == 0 then
    arp.sequence = {}
    return
  end

  local octaves = clamp(round(arp.octaves), 1, 4)
  local pattern = clamp(round(arp.pattern), 0, 3)

  -- Expand across octaves
  local expanded = {}
  for oct = 0, octaves - 1 do
    for i = 1, #held do
      expanded[#expanded + 1] = {
        note = held[i].note + (oct * 12),
        velocity = held[i].velocity,
      }
    end
  end

  -- Apply pattern ordering
  if pattern == 0 then
    -- Up: already sorted ascending
    arp.sequence = expanded
  elseif pattern == 1 then
    -- Down: reverse
    local reversed = {}
    for i = #expanded, 1, -1 do
      reversed[#reversed + 1] = expanded[i]
    end
    arp.sequence = reversed
  elseif pattern == 2 then
    -- Up-Down: up then down (skip duplicates at boundaries)
    local seq = {}
    for i = 1, #expanded do
      seq[#seq + 1] = expanded[i]
    end
    for i = #expanded - 1, 2, -1 do
      seq[#seq + 1] = expanded[i]
    end
    arp.sequence = seq
  elseif pattern == 3 then
    -- Random: shuffle a copy
    local shuffled = {}
    for i = 1, #expanded do
      shuffled[i] = expanded[i]
    end
    for i = #shuffled, 2, -1 do
      local j = math.random(1, i)
      shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    arp.sequence = shuffled
  end

  -- Clamp sequence index
  if arp.seqIndex < 1 or arp.seqIndex > #arp.sequence then
    arp.seqIndex = 1
  end
end

local function arpNoteOn(arp, note, velocity)
  -- Add note to held list (sorted by pitch)
  if arp.heldNoteSet[note] then
    -- Already held, update velocity
    for i = 1, #arp.heldNotes do
      if arp.heldNotes[i].note == note then
        arp.heldNotes[i].velocity = velocity
        break
      end
    end
    return
  end

  arp.heldNoteSet[note] = true
  local entry = { note = note, velocity = velocity }

  -- Insert sorted
  local inserted = false
  for i = 1, #arp.heldNotes do
    if note < arp.heldNotes[i].note then
      table.insert(arp.heldNotes, i, entry)
      inserted = true
      break
    end
  end
  if not inserted then
    arp.heldNotes[#arp.heldNotes + 1] = entry
  end

  arpBuildSequence(arp)
end

local function arpNoteOff(arp, note)
  if not arp.heldNoteSet[note] then
    return
  end
  arp.heldNoteSet[note] = nil

  for i = #arp.heldNotes, 1, -1 do
    if arp.heldNotes[i].note == note then
      table.remove(arp.heldNotes, i)
      break
    end
  end

  arpBuildSequence(arp)
end

local ARP_RATE_DIVISORS = { 1, 0.5, 0.25, 0.125, 0.0625 }  -- 1/4, 1/8, 1/16, 1/32, 1/64

local function arpGetStepDuration(arp)
  local beatDuration = 60.0 / clamp(arp.tempo, 40, 300)
  local rateIdx = clamp(round(arp.rate), 0, 4) + 1
  return beatDuration * (ARP_RATE_DIVISORS[rateIdx] or 0.25)
end

local function arpUpdate(ctx)
  local arp = ctx._arpState
  if not arp then return end

  -- Check if arp mode should be active
  arp.active = arpIsActive(ctx)
  if not arp.active then return end
  if #arp.sequence == 0 then
    -- No notes held: close gate if open
    if arp.gateOpen then
      arp.gateOpen = false
      if type(setParam) == "function" then
        setParam("/arp/gate", 0)
      end
    end
    return
  end

  local now = 0
  if type(getTime) == "function" then
    now = getTime()
  elseif os and os.clock then
    now = os.clock()
  end

  -- Close gate if gate duration expired
  if arp.gateOpen and now >= arp.gateOffTime then
    arp.gateOpen = false
    if type(setParam) == "function" then
      setParam("/arp/gate", 0)
    end
  end

  -- Check if it's time for the next step
  local stepDuration = arpGetStepDuration(arp)

  -- Apply swing: odd steps get delayed
  local swingOffset = 0
  if arp.swing > 0 and arp.stepCount % 2 == 1 then
    swingOffset = stepDuration * arp.swing
  end

  local nextStepTime = arp.lastStepTime + stepDuration + swingOffset
  if now < nextStepTime then
    return
  end

  -- Advance step
  arp.lastStepTime = now
  arp.stepCount = arp.stepCount + 1

  -- Get current note from sequence
  local seq = arp.sequence
  if #seq == 0 then return end

  arp.seqIndex = ((arp.seqIndex - 1) % #seq) + 1
  local step = seq[arp.seqIndex]
  if not step then return end

  -- For random pattern, reshuffle when we wrap around
  if round(arp.pattern) == 3 and arp.seqIndex == 1 and arp.stepCount > 0 then
    arpBuildSequence(arp)
    step = arp.sequence[1]
    if not step then return end
  end

  -- Advance index for next step
  arp.seqIndex = arp.seqIndex + 1

  -- Send note to DSP
  if type(setParam) == "function" then
    setParam("/arp/note", step.note)
    setParam("/arp/velocity", step.velocity)
    setParam("/arp/gate", 1)
  end

  arp.gateOpen = true
  arp.gateOffTime = now + stepDuration * clamp(arp.gateLen, 0.1, 1.0)

  ctx._runtimeStatus = string.format("Arp: %s vel:%d [%d/%d]",
    type(Midi) == "table" and type(Midi.noteName) == "function"
      and Midi.noteName(step.note) or tostring(step.note),
    step.velocity,
    arp.seqIndex - 1, #seq)
end

local function arpReadConfigFromParams(ctx)
  -- Read arp config params from the runtime param values
  local arp = ctx._arpState
  if not arp or not arp.active then return end

  local controls = ctx._paramControls or {}
  for i = 1, #controls do
    local c = controls[i]
    local path = c.def and c.def.path or ""
    local val = c.runtime and c.runtime.numericValue

    if path == "/arp/tempo" and val then
      arp.tempo = clamp(val, 40, 300)
    elseif path == "/arp/rate" and val then
      arp.rate = clamp(val, 0, 4)
    elseif path == "/arp/pattern" and val then
      local newPattern = clamp(round(val), 0, 3)
      if newPattern ~= round(arp.pattern) then
        arp.pattern = newPattern
        arpBuildSequence(arp)
      end
    elseif path == "/arp/octaves" and val then
      local newOctaves = clamp(round(val), 1, 4)
      if newOctaves ~= round(arp.octaves) then
        arp.octaves = newOctaves
        arpBuildSequence(arp)
      end
    elseif path == "/arp/gate_len" and val then
      arp.gateLen = clamp(val, 0.1, 1.0)
    elseif path == "/arp/swing" and val then
      arp.swing = clamp(val, 0, 0.9)
    end
  end
end

local function arpProcessMidi(ctx)
  -- Poll MIDI and route to arp or direct synth depending on mode
  if type(Midi) ~= "table" or type(Midi.pollInputEvent) ~= "function" then
    return
  end

  local arp = ctx._arpState
  local isArpMode = arp and arp.active

  while true do
    local event = Midi.pollInputEvent()
    if not event then break end

    if event.type == Midi.NOTE_ON and event.data2 > 0 then
      if isArpMode then
        arpNoteOn(arp, event.data1, event.data2)
        ctx._runtimeStatus = string.format("Arp hold: %s vel:%d (%d notes)",
          type(Midi.noteName) == "function" and Midi.noteName(event.data1) or tostring(event.data1),
          event.data2, #arp.heldNotes)
      else
        -- Direct synth mode (non-arp scripts)
        if type(setParam) == "function" then
          setParam("/midi/synth/note", event.data1)
          setParam("/midi/synth/velocity", event.data2)
          setParam("/midi/synth/gate", 1)
        end
        ctx._runtimeStatus = string.format("MIDI Note: %d vel %d", event.data1, event.data2)
      end
      ctx._midiLastNote = event.data1

    elseif event.type == Midi.NOTE_OFF or (event.type == Midi.NOTE_ON and event.data2 == 0) then
      if isArpMode then
        arpNoteOff(arp, event.data1)
        ctx._runtimeStatus = string.format("Arp release: %s (%d held)",
          type(Midi.noteName) == "function" and Midi.noteName(event.data1) or tostring(event.data1),
          #arp.heldNotes)
      else
        if type(setParam) == "function" then
          setParam("/midi/synth/gate", 0)
        end
        ctx._runtimeStatus = "MIDI Note Off"
      end

    elseif event.type == Midi.CONTROL_CHANGE then
      ctx._runtimeStatus = string.format("MIDI CC %d = %d", event.data1, event.data2)
    end
  end
end

function M.resized(ctx, w, h)
  resizeLayout(ctx, w, h)
  if ctx._scriptPopupOpen == true then
    syncScriptPopupSurface(ctx)
  end
end

function M.update(ctx, rawState)
  local _ = rawState
  syncEditorTextFromHost(ctx)
  refreshRuntimeParams(ctx)
  refreshParamWidgets(ctx)
  syncMetrics(ctx)
  ctx._lastError = getLastDspError() ~= "" and getLastDspError() or (ctx._lastError or "none")
  syncHeaderStatus(ctx)
  syncEditorHost(ctx)
  if ctx._scriptPopupOpen == true then
    syncScriptPopupSurface(ctx)
  end

  -- MIDI + Arpeggiator
  arpReadConfigFromParams(ctx)
  arpProcessMidi(ctx)
  arpUpdate(ctx)

  -- Parameter Modulation
  modReadConfigFromParams(ctx)
  modUpdate(ctx)
end

function M.cleanup(ctx)
  if type(shell) == "table" then
    if type(shell.defineSurface) == "function" then
      closeScriptPopup(ctx)
      shell:defineSurface("projectScriptEditor", {
        id = "projectScriptEditor",
        kind = "tool",
        backend = "imgui",
        visible = false,
        bounds = { x = 0, y = 0, w = 0, h = 0 },
        z = 60,
        mode = "global",
        docking = "fill",
        interactive = true,
        modal = false,
        payloadKey = "projectScriptEditor",
        title = "DSP Live Script",
      })
    end
    shell.mainScriptEditorActions = nil
    shell.projectScriptEditor = nil
    shell.scriptListActions = nil
  end

  stopLiveSlot(ctx)
  clearParamControls(ctx)
end

return M

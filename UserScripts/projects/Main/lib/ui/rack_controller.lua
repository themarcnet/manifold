-- Rack Controller Module
-- Owns dock/rack/view bootstrap and control wiring.

local M = {}

function M.setupDockModeControls(ctx, deps)
  deps = deps or {}
  local widgets = ctx.widgets or {}
  local getScopedWidget = deps.getScopedWidget
  local setUtilityDockMode = deps.setUtilityDockMode
  local syncDockModeDots = deps.syncDockModeDots
  local ensureUtilityDockState = deps.ensureUtilityDockState

  ctx._dockDots = {}
  local dotMap = {
    { suffix = ".dockModeDots.dockModeDotFull", mode = "full" },
    { suffix = ".dockModeDots.dockModeDotCompactSplit", mode = "compact_split" },
    { suffix = ".dockModeDots.dockModeDotCompactCollapsed", mode = "compact_collapsed" },
  }

  for _, entry in ipairs(dotMap) do
    local w = widgets[entry.suffix:match("[^.]+$")] or getScopedWidget(ctx, entry.suffix)
    if w then
      ctx._dockDots[#ctx._dockDots + 1] = { widget = w, mode = entry.mode }
      if w.node and w.node.setOnClick then
        w.node:setInterceptsMouse(true, true)
        local mode = entry.mode
        w.node:setOnClick(function()
          setUtilityDockMode(ctx, mode)
          syncDockModeDots(ctx)
        end)
      end
    end
  end

  local initDock = ensureUtilityDockState(ctx)
  if initDock.heightMode == "collapsed" then
    ctx._dockMode = "compact_collapsed"
  elseif initDock.heightMode == "compact" then
    ctx._dockMode = "compact_split"
  else
    ctx._dockMode = "full"
  end
  syncDockModeDots(ctx)
end

function M.setupPatchViewToggle(ctx, deps)
  deps = deps or {}
  local widgets = ctx.widgets or {}
  local syncPatchViewMode = deps.syncPatchViewMode

  if widgets.patchViewToggle then
    widgets.patchViewToggle._onClick = function()
      local currentMode = ctx._rackState and ctx._rackState.viewMode or "perf"
      local newMode = (currentMode == "perf") and "patch" or "perf"
      if ctx._rackState then
        ctx._rackState.viewMode = newMode
      end
      local isPatch = newMode == "patch"
      widgets.patchViewToggle:setLabel(isPatch and "PERF" or "PATCH")
      syncPatchViewMode(ctx)
      print("[PatchView] Switched to " .. newMode .. " mode")
    end

    local isPatch = (ctx._rackState and ctx._rackState.viewMode) == "patch"
    widgets.patchViewToggle:setLabel(isPatch and "PERF" or "PATCH")
  end
end

function M.setupRackPagination(ctx, deps)
  deps = deps or {}
  local widgets = ctx.widgets or {}
  local getScopedWidget = deps.getScopedWidget
  local onRackDotClick = deps.onRackDotClick
  local ensureRackPaginationState = deps.ensureRackPaginationState
  local updateRackPaginationDots = deps.updateRackPaginationDots

  ctx._rackDots = {}
  for i = 1, 3 do
    local dotId = ".rackContainer.rackPaginationDots.rackDot" .. i
    local w = getScopedWidget(ctx, dotId)
    if not w then
      w = widgets["rackDot" .. i]
    end
    if not w then
      local container = widgets.rackPaginationDots
      if container and container.children then
        w = container.children["rackDot" .. i]
      end
    end
    if w and w.node then
      ctx._rackDots[i] = { widget = w, index = i }
      w.node:setInterceptsMouse(true, true)
      local idx = i
      w.node:setOnClick(function()
        onRackDotClick(ctx, idx)
      end)
    end
  end

  ensureRackPaginationState(ctx)
  updateRackPaginationDots(ctx)
end

function M.bindRailPorts(ctx, deps)
  deps = deps or {}
  local getScopedWidget = deps.getScopedWidget
  local bindWirePortWidget = deps.bindWirePortWidget

  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.leftMidiIn"), {
    key = "midi:left:0",
    moduleId = "__midiInput",
    nodeId = "__midiInput",
    shellId = "rackContainer",
    portId = "voice",
    direction = "output",
    portType = "control",
    label = "MIDI",
    group = "midi",
    side = "left",
    row = 0,
  })

  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend1"), {
    key = "rail:right:0",
    moduleId = "__rackRail",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row1",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 0,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend2"), {
    key = "rail:right:1",
    moduleId = "__rackRail",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row2",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 1,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.rightRailSend3"), {
    key = "rail:right:2",
    moduleId = "__rackRail",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "send_row3",
    direction = "input",
    portType = "audio",
    label = "SEND",
    group = "rail",
    side = "right",
    row = 2,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.leftRailRecv2"), {
    key = "rail:left:1",
    moduleId = "__rackRail",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "recv_row2",
    direction = "output",
    portType = "audio",
    label = "RECV",
    group = "rail",
    side = "left",
    row = 1,
  })
  bindWirePortWidget(ctx, getScopedWidget(ctx, ".rackContainer.leftRailRecv3"), {
    key = "rail:left:2",
    moduleId = "__rackRail",
    nodeId = "__rackRail",
    shellId = "rackContainer",
    portId = "recv_row3",
    direction = "output",
    portType = "audio",
    label = "RECV",
    group = "rail",
    side = "left",
    row = 2,
  })
end

function M.setupShellInteractions(ctx, deps)
  deps = deps or {}
  local setupShellDragHandlers = deps.setupShellDragHandlers
  local setupResizeToggleHandlers = deps.setupResizeToggleHandlers
  local setupDeleteButtonHandlers = deps.setupDeleteButtonHandlers
  local setupPaletteDragHandlers = deps.setupPaletteDragHandlers

  setupShellDragHandlers(ctx)
  setupResizeToggleHandlers(ctx)
  if setupDeleteButtonHandlers then
    setupDeleteButtonHandlers(ctx)
  end
  if setupPaletteDragHandlers then
    setupPaletteDragHandlers(ctx)
  end
  print("[Drag] Shell drag handlers setup complete")
end

function M.finalizeViewState(ctx, deps)
  deps = deps or {}
  local syncKeyboardCollapseButton = deps.syncKeyboardCollapseButton
  local syncPatchViewMode = deps.syncPatchViewMode
  local RackWireLayer = deps.RackWireLayer
  local ensureUtilityDockState = deps.ensureUtilityDockState
  local syncDockModeDots = deps.syncDockModeDots
  local refreshManagedLayoutState = deps.refreshManagedLayoutState

  syncKeyboardCollapseButton(ctx)
  syncPatchViewMode(ctx)

  -- Sync patch view toggle button label to match loaded state
  local widgets = ctx.widgets or {}
  if widgets.patchViewToggle then
    local isPatch = (ctx._rackState and ctx._rackState.viewMode) == "patch"
    widgets.patchViewToggle:setLabel(isPatch and "PERF" or "PATCH")
  end

  if RackWireLayer then
    RackWireLayer.setupWireLayer(ctx)
  end

  local loadedDock = ensureUtilityDockState(ctx)
  if loadedDock.heightMode == "collapsed" then
    ctx._dockMode = "compact_collapsed"
  elseif loadedDock.heightMode == "compact" then
    ctx._dockMode = "compact_split"
  else
    ctx._dockMode = "full"
  end
  syncDockModeDots(ctx)
  refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)

  ctx._patchViewBootstrapFrames = 8
end

return M

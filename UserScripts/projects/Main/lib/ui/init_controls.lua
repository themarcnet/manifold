-- Init Controls Module
-- Owns non-component init wiring and startup state restoration.

local RackController = require("ui.rack_controller")
local ModEndpointRegistry = require("modulation.endpoint_registry")
local ModRouteCompiler = require("modulation.route_compiler")
local ModRuntime = require("modulation.runtime")
local MidiParamRack = require("ui.midi_param_rack")

local function getCombinedModTargetState(ctx, path, readParam)
  local targetPath = tostring(path or "")
  if targetPath == "" then
    return nil
  end

  local runtimes = {
    ctx and ctx._rackModRuntime or nil,
    ctx and ctx._modRuntime or nil,
  }

  for i = 1, #runtimes do
    local runtime = runtimes[i]
    if runtime and runtime.getTargetState then
      local state = runtime:getTargetState(targetPath, readParam)
      if state ~= nil then
        return state
      end
    end
  end

  return nil
end

local M = {}

function M.bindControls(ctx, deps)
  deps = deps or {}

  local widgets = ctx.widgets or {}
  local getScopedWidget = deps.getScopedWidget
  local triggerVoice = deps.triggerVoice
  local releaseVoice = deps.releaseVoice
  local panicVoices = deps.panicVoices
  local refreshMidiDevices = deps.refreshMidiDevices
  local applyMidiSelection = deps.applyMidiSelection
  local syncSelected = deps.syncSelected
  local setKeyboardCollapsed = deps.setKeyboardCollapsed
  local persistDockUiState = deps.persistDockUiState
  local syncText = deps.syncText
  local getOctaveLabel = deps.getOctaveLabel
  local syncKeyboardDisplay = deps.syncKeyboardDisplay
  local handleKeyboardClick = deps.handleKeyboardClick
  local saveCurrentState = deps.saveCurrentState
  local loadSavedState = deps.loadSavedState
  local resetToDefaults = deps.resetToDefaults
  local updateDropdownAnchors = deps.updateDropdownAnchors
  local loadRuntimeState = deps.loadRuntimeState
  local backgroundTick = deps.backgroundTick
  local setPath = deps.setPath
  local readParam = deps.readParam
  local applyRackConnectionState = deps.applyRackConnectionState
  local deleteRackNode = deps.deleteRackNode
  local toggleRackNodeWidth = deps.toggleRackNodeWidth
  local spawnPalettePlaceholderAt = deps.spawnPalettePlaceholderAt
  local spawnPaletteNodeAt = deps.spawnPaletteNodeAt
  local setUtilityDockMode = deps.setUtilityDockMode
  local syncDockModeDots = deps.syncDockModeDots
  local ensureUtilityDockState = deps.ensureUtilityDockState
  local syncPatchViewMode = deps.syncPatchViewMode
  local onRackDotClick = deps.onRackDotClick
  local ensureRackPaginationState = deps.ensureRackPaginationState
  local updateRackPaginationDots = deps.updateRackPaginationDots
  local setRackViewport = deps.setRackViewport
  local bindWirePortWidget = deps.bindWirePortWidget
  local setupShellDragHandlers = deps.setupShellDragHandlers
  local setupResizeToggleHandlers = deps.setupResizeToggleHandlers
  local setupDeleteButtonHandlers = deps.setupDeleteButtonHandlers
  local setupPaletteDragHandlers = deps.setupPaletteDragHandlers
  local syncKeyboardCollapseButton = deps.syncKeyboardCollapseButton
  local RackWireLayer = deps.RackWireLayer
  local refreshManagedLayoutState = deps.refreshManagedLayoutState

  ctx._modEndpointRegistry = ctx._modEndpointRegistry or ModEndpointRegistry.new()
  ctx._modRouteCompiler = ctx._modRouteCompiler or ModRouteCompiler.new()
  ctx._modRuntime = ctx._modRuntime or ModRuntime.new()

  local function rebuildModEndpointRegistry(reason)
    if ctx._modEndpointRegistry and ctx._modEndpointRegistry.rebuild then
      ctx._modEndpointRegistry:rebuild(ctx, { reason = reason })
    end
  end

  local function compileModRoute(route)
    rebuildModEndpointRegistry("compile-route")
    if ctx._modRouteCompiler and ctx._modRouteCompiler.compileRoute then
      return ctx._modRouteCompiler:compileRoute(route, ctx._modEndpointRegistry)
    end
    return {
      ok = false,
      route = route,
      errors = {
        { code = "missing_compiler", message = "mod route compiler is unavailable" },
      },
      warnings = {},
      compiled = nil,
    }
  end

  local function compileDebugRoutes()
    local routes = {
      {
        id = "voice_env_cutoff",
        source = "adsr.env",
        target = "/midi/synth/cutoff",
        amount = 0.45,
      },
      {
        id = "global_pitch_to_cutoff",
        source = "midi.pitch_bend",
        target = "/midi/synth/cutoff",
        amount = 0.8,
      },
      {
        id = "mod_wheel_to_waveform",
        source = "midi.mod_wheel",
        target = "/midi/synth/waveform",
        amount = 1.0,
        mode = "replace",
      },
      {
        id = "invalid_trigger_to_scalar",
        source = "adsr.eoc",
        target = "/midi/synth/eq8/mix",
        amount = 0.5,
      },
    }

    rebuildModEndpointRegistry("compile-debug-routes")
    if ctx._modRouteCompiler and ctx._modRouteCompiler.compileRoutes then
      return ctx._modRouteCompiler:compileRoutes(routes, ctx._modEndpointRegistry)
    end
    return {
      totalCount = #routes,
      okCount = 0,
      errorCount = #routes,
      routes = {},
    }
  end

  local function setGlobalModRoutes(routes)
    rebuildModEndpointRegistry("set-global-mod-routes")
    if ctx._modRuntime and ctx._modRuntime.setRoutes then
      return ctx._modRuntime:setRoutes(routes, ctx._modRouteCompiler, ctx._modEndpointRegistry)
    end
    return {
      requestedCount = type(routes) == "table" and #routes or 0,
      compiledCount = 0,
      activeCount = 0,
      rejectedCount = 0,
    }
  end

  local function evaluateGlobalModRuntime()
    if ctx._modRuntime and ctx._modRuntime.evaluateAndApply then
      return ctx._modRuntime:evaluateAndApply(ctx, readParam, setPath)
    end
    return {
      activeRouteCount = 0,
      appliedTargetCount = 0,
      restoredTargetCount = 0,
      appliedTargets = {},
      restoredTargets = {},
    }
  end

  ctx._onMidiDeviceStateChanged = function(event)
    rebuildModEndpointRegistry(event and event.reason or "midi-device-state-changed")
    MidiParamRack.invalidate(ctx)
  end

  if widgets.testNote then
    widgets.testNote._onPress = function()
      local voiceIndex = triggerVoice(ctx, 60, 100)
      if voiceIndex ~= nil then
        ctx._lastEvent = "Test: C4"
      else
        ctx._lastEvent = string.format("Blocked: %s", tostring(ctx._triggerBlockedReason or "missing trigger path"))
      end
    end
    widgets.testNote._onRelease = function()
      releaseVoice(ctx, 60)
    end
  end

  if widgets.panic then
    widgets.panic._onClick = function()
      panicVoices(ctx)
      ctx._lastEvent = "Panic: all off"
    end
  end

  if widgets.refreshMidi then
    widgets.refreshMidi._onClick = function()
      refreshMidiDevices(ctx, false)
      ctx._lastEvent = "MIDI refreshed"
    end
  end

  if widgets.midiInputDropdown then
    widgets.midiInputDropdown._onSelect = function(idx)
      applyMidiSelection(ctx, idx, true)
      syncSelected(widgets.midiInputDropdown, ctx._selectedMidiInputIdx or idx)
      MidiParamRack.invalidate(ctx)
    end
  end

  RackController.setupDockModeControls(ctx, {
    getScopedWidget = getScopedWidget,
    setUtilityDockMode = setUtilityDockMode,
    syncDockModeDots = syncDockModeDots,
    ensureUtilityDockState = ensureUtilityDockState,
  })

  if widgets.keyboardGrabHandle and widgets.keyboardGrabHandle.node then
    local dragging = false
    local startMode = "compact_split"
    local lastMode = nil
    local modeIndex = {
      compact_collapsed = 1,
      compact_split = 2,
      full = 3,
    }
    local modes = { "compact_collapsed", "compact_split", "full" }

    widgets.keyboardGrabHandle.node:setInterceptsMouse(true, true)
    widgets.keyboardGrabHandle.node:setOnMouseDown(function(x, y)
      local _ = x
      local _y = y
      dragging = true
      startMode = ctx._dockMode or "compact_split"
      lastMode = startMode
    end)
    widgets.keyboardGrabHandle.node:setOnMouseDrag(function(x, y, dx, dy)
      local _ = x
      local _y = y
      local _dx = dx
      if not dragging then
        return
      end
      local baseIndex = modeIndex[startMode] or 2
      local deltaY = tonumber(dy) or 0
      local step = 0
      if deltaY <= -24 then
        step = 1
      elseif deltaY >= 24 then
        step = -1
      end
      local nextIndex = math.max(1, math.min(3, baseIndex + step))
      local nextMode = modes[nextIndex]
      if nextMode ~= nil and nextMode ~= lastMode then
        lastMode = nextMode
        setUtilityDockMode(ctx, nextMode)
        syncDockModeDots(ctx)
      end
    end)
    widgets.keyboardGrabHandle.node:setOnMouseUp(function(x, y)
      local _ = x
      local _y = y
      dragging = false
      persistDockUiState(ctx)
    end)
  end

  RackController.setupPatchViewToggle(ctx, {
    syncPatchViewMode = syncPatchViewMode,
  })

  if widgets.octaveDown then
    widgets.octaveDown._onClick = function()
      ctx._keyboardOctave = math.max(0, ctx._keyboardOctave - 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave, ctx))
      syncKeyboardDisplay(ctx)
    end
  end

  if widgets.octaveUp then
    widgets.octaveUp._onClick = function()
      ctx._keyboardOctave = math.min(6, ctx._keyboardOctave + 1)
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave, ctx))
      syncKeyboardDisplay(ctx)
    end
  end

  if widgets.keyCountButton then
    widgets.keyCountButton._onClick = function()
      local options = {14, 28, 42, 64}
      local current = ctx._keyboardKeyCount or 14
      local nextIdx = 1
      for i, v in ipairs(options) do
        if v == current then
          nextIdx = (i % #options) + 1
          break
        end
      end
      ctx._keyboardKeyCount = options[nextIdx]
      widgets.keyCountButton:setLabel(tostring(ctx._keyboardKeyCount) .. "k")
      syncText(widgets.octaveLabel, getOctaveLabel(ctx._keyboardOctave, ctx))
      syncKeyboardDisplay(ctx)
    end
  end

  if widgets.keyboardCanvas and widgets.keyboardCanvas.node then
    local canvas = widgets.keyboardCanvas
    canvas.node:setInterceptsMouse(true, false)
    canvas.node:setOnMouseDown(function(x, y)
      handleKeyboardClick(ctx, x, y, true)
      syncKeyboardDisplay(ctx)
    end)
    canvas.node:setOnMouseUp(function(x, y)
      handleKeyboardClick(ctx, x, y, false)
      syncKeyboardDisplay(ctx)
    end)
    syncKeyboardDisplay(ctx)
  end

  if widgets.savePreset then
    widgets.savePreset._onClick = function()
      saveCurrentState(ctx)
    end
  end

  if widgets.loadPreset then
    widgets.loadPreset._onClick = function()
      loadSavedState(ctx)
    end
  end

  if widgets.resetPreset then
    widgets.resetPreset._onClick = function()
      resetToDefaults(ctx)
    end
  end

  RackController.setupRackPagination(ctx, {
    getScopedWidget = getScopedWidget,
    onRackDotClick = onRackDotClick,
    ensureRackPaginationState = ensureRackPaginationState,
    updateRackPaginationDots = updateRackPaginationDots,
  })

  RackController.bindRailPorts(ctx, {
    getScopedWidget = getScopedWidget,
    bindWirePortWidget = bindWirePortWidget,
  })

  RackController.setupShellInteractions(ctx, {
    setupShellDragHandlers = setupShellDragHandlers,
    setupResizeToggleHandlers = setupResizeToggleHandlers,
    setupDeleteButtonHandlers = setupDeleteButtonHandlers,
    setupPaletteDragHandlers = setupPaletteDragHandlers,
  })

  updateDropdownAnchors(ctx)
  refreshMidiDevices(ctx, true)
  loadSavedState(ctx)

  -- Initialize key count button label from loaded state
  if widgets.keyCountButton then
    widgets.keyCountButton:setLabel(tostring(ctx._keyboardKeyCount or 14) .. "k")
  end

  local additiveState = loadRuntimeState() or {}
  ctx._pendingAdditiveParamSync = {
    partials = tonumber(additiveState.additivePartials) or 8,
    tilt = tonumber(additiveState.additiveTilt) or 0.0,
    drift = tonumber(additiveState.additiveDrift) or 0.0,
    attempts = 0,
  }

  RackController.finalizeViewState(ctx, {
    syncKeyboardCollapseButton = syncKeyboardCollapseButton,
    syncPatchViewMode = syncPatchViewMode,
    RackWireLayer = RackWireLayer,
    ensureUtilityDockState = ensureUtilityDockState,
    syncDockModeDots = syncDockModeDots,
    refreshManagedLayoutState = refreshManagedLayoutState,
  })

  ctx._backgroundTickHook = function()
    backgroundTick(ctx)
  end
  _G.__midiSynthBackgroundTick = ctx._backgroundTickHook

  local shell = type(_G) == "table" and _G.shell or nil
  if type(shell) == "table" and type(shell.deferRetainedRefresh) == "function" then
    shell:deferRetainedRefresh(function()
      if _G.__midiSynthBackgroundTick == ctx._backgroundTickHook then
        backgroundTick(ctx)
      end
    end)
  end

  ctx._panicHook = function()
    panicVoices(ctx)
  end
  _G.__midiSynthPanic = ctx._panicHook

  ctx._triggerNoteHook = function(note, velocity)
    return triggerVoice(ctx, math.floor(tonumber(note) or 60), math.floor(tonumber(velocity) or 100))
  end
  _G.__midiSynthTriggerNote = ctx._triggerNoteHook

  ctx._releaseNoteHook = function(note)
    releaseVoice(ctx, math.floor(tonumber(note) or 60))
    return true
  end
  _G.__midiSynthReleaseNote = ctx._releaseNoteHook

  ctx._setAuthoredParamHook = function(path, value)
    if type(path) ~= "string" or path == "" then
      return false
    end
    setPath(path, tonumber(value) or 0, { source = "debug-authored" })
    return true
  end
  _G.__midiSynthSetAuthoredParam = ctx._setAuthoredParamHook

  ctx._getModTargetStateHook = function(path)
    return getCombinedModTargetState(ctx, path, readParam)
  end
  _G.__midiSynthGetModTargetState = ctx._getModTargetStateHook

  ctx._getDockPresentationModeHook = function()
    return ctx._dockMode or "compact_collapsed"
  end
  _G.__midiSynthGetDockPresentationMode = ctx._getDockPresentationModeHook

  ctx._setDockPresentationModeHook = function(mode)
    if mode == "full" or mode == "compact_split" or mode == "compact_collapsed" then
      setUtilityDockMode(ctx, mode)
      syncDockModeDots(ctx)
      return true
    end
    return false
  end
  _G.__midiSynthSetDockPresentationMode = ctx._setDockPresentationModeHook

  ctx._setRackViewportHook = function(offset)
    if type(setRackViewport) == "function" then
      setRackViewport(ctx, offset)
      return true
    end
    return false
  end
  _G.__midiSynthSetRackViewport = ctx._setRackViewportHook

  ctx._resyncRackConnectionsHook = function(reason)
    if type(applyRackConnectionState) == "function" then
      applyRackConnectionState(ctx, reason or "debug-resync")
      return true
    end
    return false
  end
  _G.__midiSynthResyncRackConnections = ctx._resyncRackConnectionsHook

  ctx._deleteRackNodeHook = function(nodeId)
    if type(deleteRackNode) == "function" then
      return deleteRackNode(ctx, nodeId) == true
    end
    return false
  end
  _G.__midiSynthDeleteRackNode = ctx._deleteRackNodeHook

  ctx._spawnPalettePlaceholderHook = function(targetRow, targetIndex, insertMode)
    if type(spawnPalettePlaceholderAt) == "function" then
      return spawnPalettePlaceholderAt(ctx, targetRow, targetIndex, insertMode) == true
    end
    return false
  end
  _G.__midiSynthSpawnPalettePlaceholder = ctx._spawnPalettePlaceholderHook

  ctx._spawnPaletteNodeHook = function(entryId, targetRow, targetIndex, insertMode)
    if type(spawnPaletteNodeAt) == "function" then
      return spawnPaletteNodeAt(ctx, entryId, targetRow, targetIndex, insertMode) == true
    end
    return false
  end
  _G.__midiSynthSpawnPaletteNode = ctx._spawnPaletteNodeHook

  ctx._toggleRackNodeWidthHook = function(nodeId)
    if type(toggleRackNodeWidth) == "function" then
      return toggleRackNodeWidth(ctx, nodeId) == true
    end
    return false
  end
  _G.__midiSynthToggleRackNodeWidth = ctx._toggleRackNodeWidthHook

  ctx._getRackRouteDebugHook = function()
    local MidiSynthRackSpecs = require("behaviors.rack_midisynth_specs")
    local RackLayout = require("behaviors.rack_layout")
    local route = MidiSynthRackSpecs.describeAudioRoute(ctx._rackConnections or {}, ctx._rackState and ctx._rackState.modules)
    local uiConnections = {}
    local currentConnections = ctx._rackConnections or {}
    for i = 1, #currentConnections do
      uiConnections[i] = RackLayout.makeRackConnection(currentConnections[i])
    end
    route.uiConnections = uiConnections
    route.uiConnectionCount = #uiConnections
    route.currentEdgeMaskParam = tonumber(getParam and getParam("/midi/synth/rack/audio/edgeMask") or route.edgeMask) or route.edgeMask
    route.lastAppliedEdgeMask = tonumber(ctx._rackAudioEdgeMask or route.edgeMask) or route.edgeMask
    route.viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
    route.controlRoutes = {
      adsrToOscillatorGateConnected = not not (ctx._controlRouteState and ctx._controlRouteState.adsrToOscillatorGateConnected),
      adsrToCanonicalOscillatorGateConnected = not not (ctx._controlRouteState and ctx._controlRouteState.adsrToCanonicalOscillatorGateConnected),
      adsrToLegacyOscillatorGateConnected = not not (ctx._controlRouteState and ctx._controlRouteState.adsrToLegacyOscillatorGateConnected),
      lastReason = ctx._controlRouteState and ctx._controlRouteState.lastReason or nil,
      router = ctx._controlRouteState and ctx._controlRouteState.router or nil,
      runtime = ctx._rackModRuntime and ctx._rackModRuntime.debugSnapshot and ctx._rackModRuntime:debugSnapshot(getParam) or nil,
    }
    return route
  end
  _G.__midiSynthGetRackRouteDebug = ctx._getRackRouteDebugHook

  ctx._getModEndpointRegistryHook = function()
    rebuildModEndpointRegistry("debug-hook")
    if ctx._modEndpointRegistry and ctx._modEndpointRegistry.debugSnapshot then
      return ctx._modEndpointRegistry:debugSnapshot()
    end
    return {
      totalCount = 0,
      sourceCount = 0,
      targetCount = 0,
      providerCounts = {},
      scopeCounts = {},
      duplicateIds = {},
      endpoints = {},
    }
  end
  _G.__midiSynthGetModEndpointRegistry = ctx._getModEndpointRegistryHook

  ctx._compileModRouteHook = function(route)
    return compileModRoute(route)
  end
  _G.__midiSynthCompileModRoute = ctx._compileModRouteHook

  ctx._getModRouteCompilerDebugHook = function()
    local batch = compileDebugRoutes()
    local compilerDebug = ctx._modRouteCompiler and ctx._modRouteCompiler.debugSnapshot and ctx._modRouteCompiler:debugSnapshot() or {}
    return {
      batch = batch,
      compiler = compilerDebug,
    }
  end
  _G.__midiSynthGetModRouteCompilerDebug = ctx._getModRouteCompilerDebugHook

  ctx._setGlobalModRoutesHook = function(routes)
    return setGlobalModRoutes(routes)
  end
  _G.__midiSynthSetGlobalModRoutes = ctx._setGlobalModRoutesHook

  ctx._clearGlobalModRoutesHook = function()
    return setGlobalModRoutes({})
  end
  _G.__midiSynthClearGlobalModRoutes = ctx._clearGlobalModRoutesHook

  ctx._setModSourceValueHook = function(sourceId, value)
    if ctx._modRuntime and ctx._modRuntime.setSourceValue then
      return ctx._modRuntime:setSourceValue(sourceId, value, { source = "debug-hook" })
    end
    return false
  end
  _G.__midiSynthSetModSourceValue = ctx._setModSourceValueHook

  ctx._evaluateModRuntimeHook = function()
    return evaluateGlobalModRuntime()
  end
  _G.__midiSynthEvaluateModRuntime = ctx._evaluateModRuntimeHook

  ctx._getModRuntimeDebugHook = function()
    if ctx._modRuntime and ctx._modRuntime.debugSnapshot then
      return ctx._modRuntime:debugSnapshot(readParam)
    end
    return {
      activeRouteCount = 0,
      sourceValues = {},
      activeRoutes = {},
      rejectedRoutes = {},
      targetStates = {},
    }
  end
  _G.__midiSynthGetModRuntimeDebug = ctx._getModRuntimeDebugHook

  rebuildModEndpointRegistry("bind-controls")
end

return M

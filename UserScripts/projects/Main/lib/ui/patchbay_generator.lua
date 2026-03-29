-- Patchbay Widget Generator
-- Generates interactive widget trees for the patchbay (visual node editor)

local PatchbayPanel = require("components.patchbay_panel")
local ScopedWidget = require("ui.scoped_widget")

local M = {}

-- Re-export needed helpers
local getScopedWidget = ScopedWidget.getScopedWidget
local forcePatchbayRetainedRefresh = ScopedWidget.forcePatchbayRetainedRefresh

local function endsWith(text, suffix)
  if type(text) ~= "string" or type(suffix) ~= "string" then
    return false
  end
  if suffix == "" then
    return true
  end
  return text:sub(-#suffix) == suffix
end

-- Cache of instantiated patchbay widget trees per shell, keyed by shellId.
local patchbayInstances = {}
local patchbayPortRegistry = {}

-- Forward declarations
local onPatchbayPageClick
local bindWirePortWidget

-- Shell ID to module/spec mapping
local SHELL_MAPPINGS = {
  adsrShell = { moduleId = "adsr", specId = "adsr", componentId = "envelopeComponent" },
  oscillatorShell = { moduleId = "oscillator", specId = "oscillator", componentId = "oscillatorComponent" },
  filterShell = { moduleId = "filter", specId = "filter", componentId = "filterComponent" },
  fx1Shell = { moduleId = "fx1", specId = "fx1", componentId = "fx1Component" },
  fx2Shell = { moduleId = "fx2", specId = "fx2", componentId = "fx2Component" },
  eqShell = { moduleId = "eq", specId = "eq", componentId = "eqComponent" },
  placeholder1Shell = { moduleId = "placeholder1", specId = "placeholder1", componentId = "placeholder1Content" },
  placeholder2Shell = { moduleId = "placeholder2", specId = "placeholder2", componentId = "placeholder2Content" },
  placeholder3Shell = { moduleId = "placeholder3", specId = "placeholder3", componentId = "placeholder3Content" },
}

function M.registerShellMapping(shellId, moduleId, specId, componentId)
  if type(shellId) ~= "string" or shellId == "" then
    return
  end
  SHELL_MAPPINGS[shellId] = {
    moduleId = tostring(moduleId or ""),
    specId = tostring(specId or moduleId or ""),
    componentId = tostring(componentId or "contentComponent"),
  }
end

function M.unregisterShellMapping(shellId)
  local mapping = SHELL_MAPPINGS[shellId]
  local moduleId = mapping and tostring(mapping.moduleId or "") or ""
  if mapping and moduleId ~= "" and moduleId:match("^placeholder[%d]+$") == nil
    and moduleId ~= "adsr" and moduleId ~= "oscillator" and moduleId ~= "filter"
    and moduleId ~= "fx1" and moduleId ~= "fx2" and moduleId ~= "eq" then
    SHELL_MAPPINGS[shellId] = nil
  end
end

local function getShellMapping(shellId)
  return SHELL_MAPPINGS[tostring(shellId or "")]
end

local function getShellIds()
  local ids = {}
  for shellId, _ in pairs(SHELL_MAPPINGS) do
    ids[#ids + 1] = shellId
  end
  table.sort(ids)
  return ids
end

-- Clear port registry entries for a specific shell
function M.clearPortRegistryForShell(shellId, ctx)
  for key, entry in pairs(patchbayPortRegistry) do
    if type(entry) == "table" and entry.shellId == shellId then
      patchbayPortRegistry[key] = nil
    end
  end
  if ctx then
    ctx._patchbayPortRegistry = patchbayPortRegistry
  end
  _G.__midiSynthPatchbayPortRegistry = patchbayPortRegistry
end

-- Register a patchbay port entry
function M.registerPort(entry, ctx)
  if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
    return
  end
  patchbayPortRegistry[entry.key] = entry
  if ctx then
    ctx._patchbayPortRegistry = patchbayPortRegistry
  end
  _G.__midiSynthPatchbayPortRegistry = patchbayPortRegistry
end

-- Bind wire port widget with mouse handlers for drag/drop
bindWirePortWidget = function(ctx, portWidget, entry, RackWireLayer, RackModPopover)
  if not (portWidget and portWidget.node and type(entry) == "table") then
    return
  end

  entry.widget = portWidget
  M.registerPort(entry, ctx)
  portWidget.node:setInterceptsMouse(true, true)

  if portWidget.node.setOnMouseDown then
    portWidget.node:setOnMouseDown(function(mx, my, shift, ctrl, alt, right)
      if right and RackModPopover and RackModPopover.openPortForWidget then
        RackModPopover.openPortForWidget(ctx, entry, portWidget, ctx and ctx._rackModPopoverDeps)
        return
      end
      if shift and RackWireLayer and RackWireLayer.spliceNodeForPort then
        if RackWireLayer.spliceNodeForPort(ctx, entry) then
          return
        end
      end
      if ctrl and RackWireLayer and RackWireLayer.deleteConnectionsForPort then
        RackWireLayer.deleteConnectionsForPort(ctx, entry)
        return
      end
      if RackWireLayer and RackWireLayer.beginWireDrag then
        RackWireLayer.beginWireDrag(ctx, entry)
        if RackWireLayer.updateWireDragPointer then
          RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
        end
      end
    end)
  end

  if portWidget.node.setOnMouseDrag then
    portWidget.node:setOnMouseDrag(function(mx, my)
      if RackWireLayer and RackWireLayer.updateWireDragPointer then
        RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
      end
    end)
  end

  if portWidget.node.setOnMouseUp then
    portWidget.node:setOnMouseUp(function(mx, my)
      if RackWireLayer and RackWireLayer.updateWireDragPointer then
        RackWireLayer.updateWireDragPointer(ctx, portWidget, mx, my)
      end
      if RackWireLayer and RackWireLayer.finishWireDrag then
        RackWireLayer.finishWireDrag(ctx)
      end
    end)
  end
end

-- Cleanup patchbay widgets from runtime for a shell
function M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
  M.clearPortRegistryForShell(shellId, ctx)

  local runtime = _G.__manifoldStructuredUiRuntime
  if not runtime then return end

  local shell = (type(_G) == "table") and _G.shell or nil
  if type(shell) == "table" and type(shell.clearDeferredRefreshes) == "function" then
    pcall(function() shell:clearDeferredRefreshes() end)
  end

  if RackWireLayer and RackWireLayer.cancelWireDrag then
    RackWireLayer.cancelWireDrag(ctx)
  end

  if runtime.widgets then
    local toRemove = {}
    for k, _ in pairs(runtime.widgets) do
      if type(k) == "string" and k:find(shellId .. "%.patchbayPanel%.patchbayContent", 1, false) then
        toRemove[#toRemove + 1] = k
      end
    end
    for _, k in ipairs(toRemove) do
      runtime.widgets[k] = nil
    end
  end

  if ctx then
    local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
    if panel and panel._structuredRecord then
      panel._structuredRecord.children = {}
    end
    if panel and panel.node and panel.node.clearChildren then
      pcall(function() panel.node:clearChildren() end)
    end
  end
end

-- Invalidate patchbay cache for a specific node or all nodes
function M.invalidate(nodeId, ctx, RACK_MODULE_SHELL_LAYOUT, RackWireLayer)
  if nodeId == nil then
    for shellId, _ in pairs(patchbayInstances) do
      M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
      if ctx then
        local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
        if panel and panel.node and panel.node.clearChildren then
          pcall(function() panel.node:clearChildren() end)
        end
      end
    end
    patchbayInstances = {}
    return
  end

  if type(RACK_MODULE_SHELL_LAYOUT) == "table" then
    local meta = RACK_MODULE_SHELL_LAYOUT[nodeId]
    if meta then
      local shellId = meta.shellId
      if patchbayInstances[shellId] then
        M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
        if ctx then
          local panel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
          if panel and panel.node and panel.node.clearChildren then
            pcall(function() panel.node:clearChildren() end)
          end
        end
        patchbayInstances[shellId] = nil
      end
    end
  end
end

-- Get patchbay instance for a shell
function M.getInstance(shellId)
  return patchbayInstances[shellId]
end

-- Set patchbay instance for a shell
function M.setInstance(shellId, instance)
  patchbayInstances[shellId] = instance
end

-- Clear all instances
function M.clearInstances()
  patchbayInstances = {}
end

-- Ensure patchbay widgets are instantiated for a shell
function M.ensureWidgets(ctx, shellId, nodeId, specId, currentPage, deps)
  if type(currentPage) == "table" and deps == nil then
    deps = currentPage
    currentPage = specId
    specId = nodeId
    nodeId = specId
  end
  currentPage = currentPage or 0
  deps = deps or {}
  nodeId = tostring(nodeId or specId or "")
  specId = tostring(specId or nodeId or "")
  local RackWireLayer = deps.RackWireLayer
  local RackModPopover = deps.RackModPopover
  local readParam = deps.readParam
  local setPath = deps.setPath
  local setWidgetValueSilently = deps.setWidgetValueSilently
  local PATHS = deps.PATHS
  local setSampleLoopStartLinked = deps.setSampleLoopStartLinked
  local setSampleLoopLenLinked = deps.setSampleLoopLenLinked
  local syncLegacyBlendDirectionFromBlend = deps.syncLegacyBlendDirectionFromBlend

  local runtime = _G.__manifoldStructuredUiRuntime
  local existing = patchbayInstances[shellId]
  if existing then
    local widget = existing.widget
    local record = existing.record
    local widgetRuntime = widget and widget._structuredRuntime or nil
    local recordRuntime = record and record.runtime or nil
    if widgetRuntime ~= runtime and recordRuntime ~= runtime then
      M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
      patchbayInstances[shellId] = nil
      existing = nil
    end
  end

  if patchbayInstances[shellId] and patchbayInstances[shellId].currentPage == currentPage then
    return patchbayInstances[shellId]
  end

  if patchbayInstances[shellId] and patchbayInstances[shellId].currentPage ~= currentPage then
    M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
    patchbayInstances[shellId] = nil
  end

  if patchbayInstances[shellId] then
    return patchbayInstances[shellId]
  end

  local spec = ctx._rackModuleSpecs and ctx._rackModuleSpecs[specId]
  if not spec then return nil end

  local patchbayPanel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
  if not patchbayPanel or not patchbayPanel.node then return nil end

  runtime = _G.__manifoldStructuredUiRuntime
  if not runtime or not runtime.instantiateSpec then return nil end

  local shellWidget = getScopedWidget(ctx, "." .. shellId)
  local shellX, shellY, shellW, shellH = 0, 0, 236, 220
  if shellWidget and shellWidget.node and shellWidget.node.getBounds then
    shellX, shellY, shellW, shellH = shellWidget.node:getBounds()
  end
  local headerH = 12
  local pw = math.max(100, math.floor(tonumber(shellW) or 236))
  local ph = math.max(80, math.floor((tonumber(shellH) or 220) - headerH))

  patchbayPanel.node:setBounds(0, headerH, pw, ph)
  local nodeSize = (pw >= 400) and "1x2" or "1x1"

  local patchbaySpec = PatchbayPanel.generate(spec, pw, ph, nodeSize, currentPage)
  if not patchbaySpec then return nil end

  local globalPrefix = ctx._globalPrefix or "root"
  local patchbayPrefix = (patchbayPanel._structuredRecord and patchbayPanel._structuredRecord.globalId)
    or (globalPrefix .. "." .. shellId .. ".patchbayPanel")

  patchbayPanel.node:setDisplayList({})

  local ok, widget, globalId, record = pcall(function()
    return runtime:instantiateSpec(patchbayPanel.node, patchbaySpec, {
      idPrefix = patchbayPrefix,
      localWidgets = ctx.allWidgets or {},
      extraProps = nil,
      isRoot = false,
      parentRecord = patchbayPanel._structuredRecord,
      sourceDocumentPath = "patchbay_dynamic",
      sourceKind = "node",
    })
  end)

  if not ok then
    print("[Patchbay] Failed to instantiate for " .. shellId .. ": " .. tostring(widget))
    return nil
  end

  if record and patchbayPanel._structuredRecord then
    local parentChildren = patchbayPanel._structuredRecord.children
    if type(parentChildren) ~= "table" then
      parentChildren = {}
      patchbayPanel._structuredRecord.children = parentChildren
    end
    parentChildren[#parentChildren + 1] = record
  end

  if widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(0, 0, math.floor(pw), math.floor(ph))
  end

  if widget and widget._structuredRuntime and widget._structuredRecord then
    pcall(function()
      widget._structuredRuntime:notifyRecordHostedResized(widget._structuredRecord, pw, ph)
    end)
  end
  if patchbayPanel._structuredRuntime and patchbayPanel._structuredRecord then
    pcall(function()
      patchbayPanel._structuredRuntime:notifyRecordHostedResized(patchbayPanel._structuredRecord, pw, ph)
    end)
  end

  forcePatchbayRetainedRefresh(widget, patchbayPanel)

  local runtimeWidgets = runtime.widgets or {}
  local recordWidgets = {}

  local function collectRecordWidgets(recordNode)
    if type(recordNode) ~= "table" then
      return
    end
    if type(recordNode.globalId) == "string" and recordNode.globalId ~= "" and recordNode.widget ~= nil then
      recordWidgets[recordNode.globalId] = recordNode.widget
    end
    local children = type(recordNode.children) == "table" and recordNode.children or {}
    for i = 1, #children do
      collectRecordWidgets(children[i])
    end
  end

  collectRecordWidgets(record)

  local function lookupWidgetInMap(widgetMap, searchPath)
    if type(widgetMap) ~= "table" then
      return nil, nil
    end

    local candidate = widgetMap[searchPath]
    if candidate then
      return candidate, searchPath
    end

    local suffix = tostring(searchPath):match("([^.]+%.patchbayPanel.*)$")
    if suffix and suffix ~= "" then
      local bestKey = nil
      local bestWidget = nil
      for key, widgetCandidate in pairs(widgetMap) do
        if type(key) == "string" and endsWith(key, suffix) then
          if bestKey == nil or #key < #bestKey then
            bestKey = key
            bestWidget = widgetCandidate
          end
        end
      end
      if bestWidget then
        return bestWidget, bestKey
      end
    end

    return nil, nil
  end

  local function findFirstWidget(searchPaths)
    for _, searchPath in ipairs(searchPaths or {}) do
      local candidate, foundKey = lookupWidgetInMap(recordWidgets, searchPath)
      if candidate then
        return candidate, foundKey
      end
      candidate, foundKey = lookupWidgetInMap(runtimeWidgets, searchPath)
      if candidate then
        return candidate, foundKey
      end
    end
    return nil, nil
  end

  local allParams = (spec.ports or {}).params or {}
  local perPage = (nodeSize == "1x2") and (PatchbayPanel.PARAMS_PER_PAGE_1X2 or 16) or (PatchbayPanel.PARAMS_PER_PAGE_1X1 or 6)
  local startIdx = currentPage * perPage + 1
  local endIdx = math.min(#allParams, startIdx + perPage - 1)
  local currentParams = {}
  for idx = startIdx, endIdx do
    currentParams[#currentParams + 1] = allParams[idx]
  end

  local sliderWidgets = {}

  local inputs = (spec.ports or {}).inputs or {}
  for _, port in ipairs(inputs) do
    if port.edge == nil then
      local rowId = "input_" .. tostring(port.id)
      local widget = runtimeWidgets[patchbayPrefix .. ".patchbayContent.inputsColumn." .. rowId .. "." .. rowId .. "_port"]
      bindWirePortWidget(ctx, widget, {
        key = table.concat({ nodeId, shellId, "input", tostring(port.id) }, ":"),
        moduleId = nodeId,
        shellId = shellId,
        portId = tostring(port.id),
        direction = "input",
        portType = tostring(port.type or "control"),
        label = port.label or port.id,
        group = "io",
      }, RackWireLayer, RackModPopover)
    end
  end

  local outputs = (spec.ports or {}).outputs or {}
  for _, port in ipairs(outputs) do
    if port.edge == nil then
      local rowId = "output_" .. tostring(port.id)
      local widget = runtimeWidgets[patchbayPrefix .. ".patchbayContent.outputsColumn." .. rowId .. "." .. rowId .. "_port"]
      bindWirePortWidget(ctx, widget, {
        key = table.concat({ nodeId, shellId, "output", tostring(port.id) }, ":"),
        moduleId = nodeId,
        shellId = shellId,
        portId = tostring(port.id),
        direction = "output",
        portType = tostring(port.type or "audio"),
        label = port.label or port.id,
        group = "io",
      }, RackWireLayer, RackModPopover)
    end
  end

  for i, param in ipairs(currentParams) do
    if param then
      local paramId = tostring(param.id or i)
      local paramKey = "param_" .. paramId .. "_p" .. currentPage

      local sliderSearchPaths = {
        patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_val",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_val",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_slider",
        patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_val",
      }

      local sliderWidget = findFirstWidget(sliderSearchPaths)

      local inputPortWidget = nil
      if param.input ~= false then
        inputPortWidget = findFirstWidget({
          patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_in",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_in",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_in",
        })
      end

      local outputPortWidget = nil
      if param.output ~= false then
        outputPortWidget = findFirstWidget({
          patchbayPrefix .. ".patchbayContent.paramsColumn." .. paramKey .. "." .. paramKey .. "_out",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColLeft." .. paramKey .. "." .. paramKey .. "_out",
          patchbayPrefix .. ".patchbayContent.paramsColumn.paramColumns.paramColRight." .. paramKey .. "." .. paramKey .. "_out",
        })
      end

      bindWirePortWidget(ctx, inputPortWidget, {
        key = table.concat({ nodeId, shellId, "input", paramId }, ":"),
        moduleId = nodeId,
        shellId = shellId,
        portId = paramId,
        direction = "input",
        portType = "control",
        label = param.label or paramId,
        group = "param",
        page = currentPage,
      }, RackWireLayer, RackModPopover)

      bindWirePortWidget(ctx, outputPortWidget, {
        key = table.concat({ nodeId, shellId, "output", paramId }, ":"),
        moduleId = nodeId,
        shellId = shellId,
        portId = paramId,
        direction = "output",
        portType = "control",
        label = param.label or paramId,
        group = "param",
        page = currentPage,
      }, RackWireLayer, RackModPopover)

      if sliderWidget and param.path and setPath and readParam then
        local dspPath = param.path
        local scale = param.scale
        local pmin = param.min or 0
        local pmax = param.max or 1
        local displayRange = pmax - pmin

        sliderWidget._onChange = function(v)
          local dspVal = v
          if scale and displayRange > 0 then
            local dspMin = scale.dspMin or 0
            local dspMax = scale.dspMax or 1
            local dspRange = dspMax - dspMin
            dspVal = ((v - pmin) / displayRange) * dspRange + dspMin
          end

          if dspPath == PATHS.sampleLoopStart and setSampleLoopStartLinked then
            setSampleLoopStartLinked(dspVal)
          elseif dspPath == PATHS.sampleLoopLen and setSampleLoopLenLinked then
            setSampleLoopLenLinked(dspVal)
          elseif dspPath == PATHS.blendAmount and syncLegacyBlendDirectionFromBlend then
            setPath(dspPath, dspVal)
            syncLegacyBlendDirectionFromBlend(dspVal)
          else
            setPath(dspPath, dspVal)
          end
        end

        local dspVal = readParam(dspPath, param.default or 0)
        local displayVal = dspVal
        if scale and displayRange > 0 then
          local dspMin = scale.dspMin or 0
          local dspMax = scale.dspMax or 1
          local dspRange = dspMax - dspMin
          if dspRange > 0 then
            displayVal = ((dspVal - dspMin) / dspRange) * displayRange + pmin
          end
        end

        if sliderWidget.setValue and setWidgetValueSilently then
          setWidgetValueSilently(sliderWidget, tonumber(displayVal) or param.default or 0)
        end
        sliderWidget._modParamPath = dspPath
        sliderWidget._modDisplayScale = scale
        sliderWidgets[param.id] = { widget = sliderWidget, path = dspPath, param = param }
      end
    end
  end

  local numPages = patchbaySpec.props and patchbaySpec.props._numPages or 1
  if numPages > 1 then
    for pageIdx = 0, numPages - 1 do
      local dotPath = patchbayPrefix .. ".patchbayContent.paramsColumn.paramsHeaderRow.pageDots.pageDots_dot" .. (pageIdx + 1)
      local dotWidget = runtimeWidgets[dotPath]
      if dotWidget and dotWidget.node and dotWidget.node.setOnClick then
        dotWidget.node:setInterceptsMouse(true, true)
        local targetPage = pageIdx
        local targetShell = shellId
        dotWidget.node:setOnClick(function()
          onPatchbayPageClick(ctx, targetShell, targetPage)
        end)
      end
    end
  end

  local instance = {
    widget = widget,
    record = record,
    sliders = sliderWidgets,
    nodeId = nodeId,
    specId = specId,
    currentPage = currentPage,
    nodeSize = nodeSize,
    numPages = numPages,
  }
  patchbayInstances[shellId] = instance
  if RackWireLayer and RackWireLayer.refreshWires then
    RackWireLayer.refreshWires(ctx)
  end
  return instance
end

-- Handle pagination dot click in patchbay
onPatchbayPageClick = function(ctx, shellId, pageIndex)
  if not shellId then return end
  local instance = patchbayInstances[shellId]
  if instance and instance.numPages and instance.numPages > 1 then
    ctx._pendingPatchbayPages = ctx._pendingPatchbayPages or {}
    ctx._pendingPatchbayPages[shellId] = pageIndex
  end
end

-- Sync patchbay slider values from live DSP state
function M.syncValues(ctx, readParam, setWidgetValueSilently, getModTargetState)
  local function toDisplayValue(param, dspValue)
    local value = tonumber(dspValue) or tonumber(param.default) or 0
    local scale = param.scale
    if not scale then
      return value
    end

    local pmin = param.min or 0
    local pmax = param.max or 1
    local displayRange = pmax - pmin
    local dspMin = scale.dspMin or 0
    local dspMax = scale.dspMax or 1
    local dspRange = dspMax - dspMin
    if displayRange > 0 and dspRange > 0 then
      return ((value - dspMin) / dspRange) * displayRange + pmin
    end
    return value
  end

  for shellId, instance in pairs(patchbayInstances) do
    if instance and instance.sliders then
      for paramId, entry in pairs(instance.sliders) do
        local widget = entry.widget
        local path = entry.path
        local param = entry.param
        if widget and path and widget.setValue then
          local dspCurrent = readParam(path, param.default or 0)
          local modState = type(getModTargetState) == "function" and getModTargetState(path) or nil
          local dspBaseValue = modState and tonumber(modState.baseValue) or dspCurrent
          local dspEffectiveValue = modState and tonumber(modState.effectiveValue) or dspCurrent
          local displayBaseValue = toDisplayValue(param, dspBaseValue)
          local displayEffectiveValue = toDisplayValue(param, dspEffectiveValue)

          if not widget._dragging then
            local current = widget.getValue and widget:getValue() or nil
            local threshold = 0.0001
            if current == nil or math.abs((tonumber(current) or 0) - (tonumber(displayBaseValue) or 0)) > threshold then
              if setWidgetValueSilently then
                setWidgetValueSilently(widget, displayBaseValue)
              else
                widget:setValue(displayBaseValue)
              end
            end
          end

          if widget.setModulationState then
            widget:setModulationState(displayBaseValue, displayEffectiveValue, {
              enabled = modState ~= nil and math.abs((displayEffectiveValue or 0) - (displayBaseValue or 0)) > 0.0001,
            })
          end
        end
      end
    end
  end
end

-- Find a registered patchbay port by module/port/direction
function M.findRegisteredPort(ctx, moduleId, portId, direction)
  local registry = ctx and ctx._patchbayPortRegistry or nil
  if type(registry) ~= "table" then
    return nil
  end
  for _, entry in pairs(registry) do
    if type(entry) == "table"
      and entry.moduleId == moduleId
      and entry.portId == portId
      and entry.direction == direction
      and entry.widget ~= nil then
      return entry
    end
  end
  return nil
end

-- Sync patch view mode visibility
function M.syncPatchViewMode(ctx, deps)
  deps = deps or {}
  local RackWireLayer = deps.RackWireLayer
  local syncRackEdgeTerminals = deps.syncRackEdgeTerminals

  local rackState = ctx._rackState
  if not rackState then return end

  local isPatch = (rackState.viewMode or "perf") == "patch"
  local activeModuleIds = {}
  local rackModules = type(rackState.modules) == "table" and rackState.modules or {}
  for i = 1, #rackModules do
    local module = rackModules[i]
    local moduleId = module and tostring(module.id or "") or ""
    if moduleId ~= "" then
      activeModuleIds[moduleId] = true
    end
  end

  local shellIds = getShellIds()

  for _, shellId in ipairs(shellIds) do
    local shell = getScopedWidget(ctx, "." .. shellId)
    if shell then
      local mapping = getShellMapping(shellId) or {}
      local moduleId = tostring(mapping.moduleId or mapping.nodeId or "")
      local specId = tostring(mapping.specId or moduleId)
      local componentId = tostring(mapping.componentId or "contentComponent")
      local shellActive = activeModuleIds[moduleId] == true
      local showPatchbay = isPatch and shellActive
      local showContent = (not isPatch) and shellActive

      local content = getScopedWidget(ctx, "." .. shellId .. "Content")
      if content and content.setVisible then
        content:setVisible(showContent)
      end
      local compId = shellId:gsub("Shell", "Component")
      local comp = getScopedWidget(ctx, "." .. shellId .. "." .. compId)
      if comp and comp.setVisible then
        comp:setVisible(showContent)
      end
      local contentPanels = { componentId, "envelopeComponent", "oscillatorComponent", "filterComponent", "fx1Component", "fx2Component", "eqComponent", "placeholder1Content", "placeholder2Content", "placeholder3Content", "placeholderKnobContent", "contentComponent" }
      for _, panelId in ipairs(contentPanels) do
        local panel = getScopedWidget(ctx, "." .. shellId .. "." .. panelId)
        if panel and panel.setVisible then
          panel:setVisible(showContent)
          break
        end
      end

      local patchbayPanel = getScopedWidget(ctx, "." .. shellId .. ".patchbayPanel")
      if patchbayPanel and patchbayPanel.node then
        patchbayPanel.node:setVisible(showPatchbay)
      end

      if showPatchbay and specId ~= "" then
        M.ensureWidgets(ctx, shellId, moduleId, specId, nil, deps)
      elseif not shellActive and patchbayInstances[shellId] then
        M.cleanupFromRuntime(shellId, ctx, RackWireLayer)
        patchbayInstances[shellId] = nil
      end
    end
  end

  if syncRackEdgeTerminals then
    syncRackEdgeTerminals(ctx)
  end

  if RackWireLayer then
    RackWireLayer.refreshWires(ctx)
  end
end

-- Get port registry (for debugging)
function M.getPortRegistry()
  return patchbayPortRegistry
end

-- Get all instances (for debugging)
function M.getInstances()
  return patchbayInstances
end

return M

-- Dynamic Module Binding Module
-- Extracted from midisynth.lua
-- Handles dynamic module registry requests, rack audio staging, topology,
-- and dynamic shell materialization.

local M = {}

local host = nil
local setPath = nil
local PATHS = nil
local MidiSynthRackSpecs = nil
local RackModuleFactory = nil
local RACK_MODULE_SHELL_LAYOUT = nil
local getScopedWidget = nil
local getScopedBehavior = nil
local RackLayoutManager = nil
local PatchbayRuntime = nil
local rackRegistryNonce = 0

function M._rackAudioStagePath(index)
  return string.format("/midi/synth/rack/stage/%d", math.max(1, math.floor(tonumber(index) or 1)))
end

function M._rackAudioSourcePath(index)
  return string.format("/midi/synth/rack/source/%d", math.max(1, math.floor(tonumber(index) or 1)))
end

function M._rackAudioSourceCodeForNodeId(nodeId)
  local id = tostring(nodeId or "")
  if id == "oscillator" then
    return 1
  end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[id] or nil
  if type(entry) == "table" and tostring(entry.specId or "") == "rack_oscillator" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 100 + slotIndex
  end
  if type(entry) == "table" and tostring(entry.specId or "") == "rack_sample" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 200 + slotIndex
  end
  if type(entry) == "table" and tostring(entry.specId or "") == "blend_simple" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 300 + slotIndex
  end
  return 0
end

function M._rackRegistryRequestKindForSpecId(specId)
  local mapping = {
    eq = 0,
    fx = 1,
    filter = 2,
    rack_oscillator = 3,
    rack_sample = 4,
    adsr = 5,
    arp = 6,
    transpose = 7,
    velocity_mapper = 8,
    scale_quantizer = 9,
    note_filter = 10,
    attenuverter_bias = 11,
    range_mapper = 12,
    lfo = 13,
    slew = 14,
    sample_hold = 15,
    compare = 16,
    cv_mix = 17,
    blend_simple = 18,
  }
  return mapping[tostring(specId or "")]
end

function M._requestDynamicModuleSlot(specId, slotIndex)
  local index = math.max(1, math.floor(tonumber(slotIndex) or 0))
  if index <= 0 then
    return false
  end

  local kind = M._rackRegistryRequestKindForSpecId(specId)
  if kind == nil then
    return false
  end
  local writer = nil
  if type(_G.setParam) == "function" then
    writer = _G.setParam
  elseif type(command) == "function" then
    writer = function(path, value)
      command("SET", path, tostring(value))
      return true
    end
  end
  if type(writer) ~= "function" then
    return false
  end
  rackRegistryNonce = math.max(0, math.floor(tonumber(rackRegistryNonce or 0))) + 1
  local okKind = writer(PATHS.rackRegistryRequestKind, kind) ~= false
  local okIndex = writer(PATHS.rackRegistryRequestIndex, index) ~= false
  local okNonce = writer(PATHS.rackRegistryRequestNonce, rackRegistryNonce) ~= false
  return okKind and okIndex and okNonce
end

function M._ensureDynamicShellForNode(ctx, nodeId)
  if not (ctx and type(RACK_MODULE_SHELL_LAYOUT) == "table") then
    return nil
  end
  local existing = RACK_MODULE_SHELL_LAYOUT[tostring(nodeId or "")]
  if existing then
    return existing
  end

  local node = nil
  local sourceNodes = (ctx and ctx._dragPreviewModules) or (ctx and ctx._rackState and ctx._rackState.modules) or {}
  for i = 1, #sourceNodes do
    if sourceNodes[i] and tostring(sourceNodes[i].id or "") == tostring(nodeId or "") then
      node = sourceNodes[i]
      break
    end
  end
  local spec = ctx._rackModuleSpecs and ctx._rackModuleSpecs[tostring(nodeId or "")] or nil
  local rackShellHost = getScopedWidget(ctx, ".rackContainer.rackShellHost") or getScopedWidget(ctx, ".rackShellHost")
  local runtime = _G.__manifoldStructuredUiRuntime
  if not (node and spec and rackShellHost and rackShellHost.node and runtime and runtime.instantiateSpec) then
    return nil
  end

  local RackModuleShell = require("components.rack_module_shell")
  local shellId = tostring(nodeId) .. "Shell"
  local slotW = (RackLayoutManager and RackLayoutManager.RACK_SLOT_W) or 236
  local slotH = (RackLayoutManager and RackLayoutManager.RACK_SLOT_H) or 220
  local componentId = tostring((spec.meta and spec.meta.componentId) or (node.meta and node.meta.componentId) or "contentComponent")
  local shellSpec = RackModuleShell({
    id = shellId,
    layout = false,
    x = 0,
    y = 0,
    w = math.max(1, tonumber(node.w) or 1) * slotW,
    h = math.max(1, tonumber(node.h) or 1) * slotH,
    sizeKey = tostring(node.sizeKey or "1x1"),
    accentColor = tonumber(spec.accentColor) or 0xff64748b,
    nodeName = tostring(spec.name or nodeId),
    componentRef = spec.meta and spec.meta.componentRef or "ui/components/placeholder.ui.lua",
    componentId = componentId,
    componentBehavior = spec.meta and spec.meta.behavior or nil,
    componentProps = {
      instanceNodeId = tostring(nodeId or ""),
      paramBase = spec.meta and spec.meta.paramBase or nil,
      specId = spec.meta and spec.meta.specId or spec.id or nil,
      sizeKey = tostring(node.sizeKey or "1x1"),
    },
    componentOverrides = {
      [componentId] = {
        style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
        props = { interceptsMouse = false },
      },
    },
  })

  local parentRecord = rackShellHost._structuredRecord
  local parentChildren = parentRecord and parentRecord.children or nil
  local _, _, record = runtime:instantiateSpec(rackShellHost.node, shellSpec, {
    idPrefix = parentRecord and parentRecord.globalId or (ctx._globalPrefix or "root") .. ".rackContainer.rackShellHost",
    localWidgets = ctx.allWidgets or {},
    extraProps = nil,
    isRoot = false,
    parentRecord = parentRecord,
    sourceDocumentPath = "rack_dynamic_shell",
    sourceKind = "node",
  })
  if type(parentChildren) == "table" and record ~= nil then
    parentChildren[#parentChildren + 1] = record
  end

  if ctx then
    ctx._scopedWidgetCache = {}
    ctx._scopedBehaviorCache = {}
  end

  local componentBehavior = getScopedBehavior(ctx, "." .. shellId .. "." .. componentId)
  if componentBehavior and componentBehavior.ctx then
    componentBehavior.ctx._instanceNodeId = tostring(nodeId or "")
    local behaviorRoot = componentBehavior.ctx.root
    local behaviorNode = behaviorRoot and behaviorRoot.node or nil
    if behaviorNode and behaviorNode.setUserData then
      behaviorNode:setUserData("_structuredInstanceSource", {
        nodeId = tostring(nodeId or ""),
        shellId = tostring(shellId or ""),
        componentId = tostring(componentId or ""),
        globalId = behaviorRoot and behaviorRoot._structuredRecord and behaviorRoot._structuredRecord.globalId or nil,
      })
    end
  end
  if componentBehavior and componentBehavior.ctx and componentBehavior.module then
    if componentBehavior.ctx._dynamicInitApplied ~= true and type(componentBehavior.module.init) == "function" then
      componentBehavior.module.init(componentBehavior.ctx)
      componentBehavior.ctx._dynamicInitApplied = true
    end
    componentBehavior.ctx.instanceProps = type(componentBehavior.ctx.instanceProps) == "table" and componentBehavior.ctx.instanceProps or {}
    componentBehavior.ctx.instanceProps.sizeKey = tostring(node.sizeKey or "1x1")
    if type(componentBehavior.module.resized) == "function" then
      componentBehavior.module.resized(componentBehavior.ctx)
    end
  end

  local meta = {
    shellId = shellId,
    badgeSuffix = "." .. shellId .. ".sizeBadge",
    row = tonumber(node.row) or 0,
    accentColor = tonumber(spec.accentColor) or 0xff64748b,
    specId = tostring(spec.id or nodeId),
    componentId = componentId,
    dynamic = true,
  }
  RACK_MODULE_SHELL_LAYOUT[tostring(nodeId)] = meta
  PatchbayRuntime.registerShellMapping(shellId, tostring(nodeId), meta.specId, meta.componentId)
  if host and type(host._setupShellDragHandlers) == "function" then
    host._setupShellDragHandlers(ctx)
  end
  if host and type(host._setupResizeToggleHandlers) == "function" then
    host._setupResizeToggleHandlers(ctx)
  end
  if host and type(host._setupDeleteButtonHandlers) == "function" then
    host._setupDeleteButtonHandlers(ctx)
  end
  return meta
end

function M._rackAudioStageCodeForNodeId(nodeId)
  local id = tostring(nodeId or "")
  if id == "filter" then return 1 end
  if id == "fx1" then return 2 end
  if id == "fx2" then return 3 end
  if id == "eq" then return 4 end
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[id] or nil
  if type(entry) == "table" and tostring(entry.specId or "") == "eq" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 100 + slotIndex
  end
  if type(entry) == "table" and tostring(entry.specId or "") == "fx" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 200 + slotIndex
  end
  if type(entry) == "table" and tostring(entry.specId or "") == "filter" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 300 + slotIndex
  end
  if type(entry) == "table" and tostring(entry.specId or "") == "blend_simple" then
    local slotIndex = math.max(1, math.floor(tonumber(entry.slotIndex) or 0))
    return 400 + slotIndex
  end
  return 0
end

function M._syncRackAudioStageParams(ctx)
  local description = MidiSynthRackSpecs.describeAudioStageSequence(ctx and ctx._rackConnections or {}, ctx and ctx._rackState and ctx._rackState.modules)
  local stages = type(description) == "table" and description.stageNodeIds or {}
  local sources = type(description) == "table" and description.sourceNodeIds or { "oscillator" }
  local reachesOutput = type(description) == "table" and description.reachesOutput == true
  for i = 1, #stages do
    setPath(M._rackAudioStagePath(i), M._rackAudioStageCodeForNodeId(stages[i]))
  end
  for i = 1, #sources do
    setPath(M._rackAudioSourcePath(i), M._rackAudioSourceCodeForNodeId(sources[i]))
  end
  setPath(PATHS.rackAudioStageCount, #stages)
  setPath(PATHS.rackAudioOutputEnabled, reachesOutput and 1 or 0)
  setPath(PATHS.rackAudioSourceCount, #sources)
  ctx._rackAudioStageSequence = stages
  ctx._rackAudioSourceSequence = sources
  ctx._rackAudioReachesOutput = reachesOutput
  return stages
end

function M._rackTopologySignature(connections, nodes)
  local normalized = MidiSynthRackSpecs.normalizeConnections(connections, nodes)
  local parts = {}
  for i = 1, #normalized do
    local conn = normalized[i]
    local fromEndpoint = type(conn and conn.from) == "table" and conn.from or {}
    local toEndpoint = type(conn and conn.to) == "table" and conn.to or {}
    parts[#parts + 1] = table.concat({
      tostring(conn and conn.kind or ""),
      tostring(fromEndpoint.nodeId or ""),
      tostring(fromEndpoint.portId or ""),
      tostring(toEndpoint.nodeId or ""),
      tostring(toEndpoint.portId or ""),
    }, "\31")
  end
  return table.concat(parts, "\30")
end

function M._rackTopologyChanged(previousConnections, previousNodes, nextConnections, nextNodes)
  return M._rackTopologySignature(previousConnections, previousNodes) ~= M._rackTopologySignature(nextConnections, nextNodes)
end

function M._inferredDynamicSpecId(node)
  local meta = type(node) == "table" and type(node.meta) == "table" and node.meta or {}
  local metaSpecId = tostring(meta.specId or "")
  if metaSpecId ~= "" and RackModuleFactory and RackModuleFactory.specConfig(metaSpecId) ~= nil then
    return metaSpecId
  end
  local nodeId = tostring(type(node) == "table" and node.id or "")
  local inferred = nodeId:match("^(.-)_inst_%d+$")
  if inferred ~= nil and RackModuleFactory and RackModuleFactory.specConfig(inferred) ~= nil then
    return inferred
  end
  return nil
end

function M._rebuildDynamicRackModuleState(ctx)
  if type(ctx) ~= "table" then
    return 0
  end

  ctx._rackModuleSpecs = MidiSynthRackSpecs.rackModuleSpecById()
  _G.__midiSynthDynamicModuleInfo = {}
  _G.__midiSynthDynamicModuleSpecs = {}

  local slots = RackModuleFactory.ensureDynamicModuleSlots(ctx)
  for _, bucket in pairs(slots or {}) do
    if type(bucket) == "table" then
      for slotIndex in pairs(bucket) do
        bucket[slotIndex] = nil
      end
    end
  end

  local nodes = ctx._rackState and ctx._rackState.modules or {}
  local restored = 0
  local maxSerial = 0

  for i = 1, #nodes do
    local node = nodes[i]
    local nodeId = tostring(node and node.id or "")
    local serial = tonumber(nodeId:match("_inst_(%d+)$"))
    if serial ~= nil and serial > maxSerial then
      maxSerial = serial
    end

    local specId = M._inferredDynamicSpecId(node)
    if specId ~= nil then
      node.meta = type(node.meta) == "table" and node.meta or {}
      local slotIndex = tonumber(node.meta.slotIndex)
      if slotIndex == nil then
        local paramBase = tostring(node.meta.paramBase or "")
        slotIndex = tonumber(paramBase:match("/(%d+)$"))
      end
      if slotIndex == nil then
        slotIndex = RackModuleFactory.nextAvailableSlot(ctx, specId)
      end
      slotIndex = math.max(1, math.floor(tonumber(slotIndex) or 1))

      M._requestDynamicModuleSlot(specId, slotIndex)

      local paramBase = RackModuleFactory.buildParamBase(specId, slotIndex)
      local spec = RackModuleFactory.registerDynamicModuleSpec(ctx, specId, nodeId, {
        slotIndex = slotIndex,
        paramBase = paramBase,
      })
      if type(spec) == "table" then
        RackModuleFactory.markSlotOccupied(ctx, specId, slotIndex, nodeId)
        node.meta.specId = specId
        node.meta.componentId = tostring(node.meta.componentId or (spec.meta and spec.meta.componentId) or "contentComponent")
        node.meta.spawned = true
        node.meta.slotIndex = slotIndex
        node.meta.paramBase = paramBase
        restored = restored + 1
      end
    end
  end

  ctx._dynamicNodeSerial = math.max(tonumber(ctx._dynamicNodeSerial) or 0, maxSerial)
  _G.__midiSynthRackModuleSpecs = ctx._rackModuleSpecs
  return restored
end

function M.attach(midiSynth)
  host = midiSynth
  midiSynth._rackAudioStagePath = M._rackAudioStagePath
  midiSynth._rackAudioSourcePath = M._rackAudioSourcePath
  midiSynth._rackAudioSourceCodeForNodeId = M._rackAudioSourceCodeForNodeId
  midiSynth._rackRegistryRequestKindForSpecId = M._rackRegistryRequestKindForSpecId
  midiSynth._requestDynamicModuleSlot = M._requestDynamicModuleSlot
  midiSynth._ensureDynamicShellForNode = M._ensureDynamicShellForNode
  midiSynth._rackAudioStageCodeForNodeId = M._rackAudioStageCodeForNodeId
  midiSynth._syncRackAudioStageParams = M._syncRackAudioStageParams
  midiSynth._rackTopologySignature = M._rackTopologySignature
  midiSynth._rackTopologyChanged = M._rackTopologyChanged
  midiSynth._inferredDynamicSpecId = M._inferredDynamicSpecId
  midiSynth._rebuildDynamicRackModuleState = M._rebuildDynamicRackModuleState
end

function M.init(deps)
  setPath = deps.setPath
  PATHS = deps.PATHS
  MidiSynthRackSpecs = deps.MidiSynthRackSpecs
  RackModuleFactory = deps.RackModuleFactory or require("ui.rack_module_factory")
  RACK_MODULE_SHELL_LAYOUT = deps.RACK_MODULE_SHELL_LAYOUT
  getScopedWidget = deps.getScopedWidget
  getScopedBehavior = deps.getScopedBehavior
  RackLayoutManager = deps.RackLayoutManager
  PatchbayRuntime = deps.PatchbayRuntime
  rackRegistryNonce = 0
end

return M

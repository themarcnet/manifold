local M = {}

local EDGE_ORDER = {
  { id = "oscillator_to_filter", fromKey = "oscillator", toKey = "filter" },
  { id = "oscillator_to_fx1", fromKey = "oscillator", toKey = "fx1" },
  { id = "oscillator_to_fx2", fromKey = "oscillator", toKey = "fx2" },
  { id = "oscillator_to_eq", fromKey = "oscillator", toKey = "eq" },
  { id = "oscillator_to_output", fromKey = "oscillator", toKey = "output" },
  { id = "filter_to_fx1", fromKey = "filter", toKey = "fx1" },
  { id = "filter_to_fx2", fromKey = "filter", toKey = "fx2" },
  { id = "filter_to_eq", fromKey = "filter", toKey = "eq" },
  { id = "filter_to_output", fromKey = "filter", toKey = "output" },
  { id = "fx1_to_filter", fromKey = "fx1", toKey = "filter" },
  { id = "fx1_to_fx2", fromKey = "fx1", toKey = "fx2" },
  { id = "fx1_to_eq", fromKey = "fx1", toKey = "eq" },
  { id = "fx1_to_output", fromKey = "fx1", toKey = "output" },
  { id = "fx2_to_filter", fromKey = "fx2", toKey = "filter" },
  { id = "fx2_to_fx1", fromKey = "fx2", toKey = "fx1" },
  { id = "fx2_to_eq", fromKey = "fx2", toKey = "eq" },
  { id = "fx2_to_output", fromKey = "fx2", toKey = "output" },
  { id = "eq_to_filter", fromKey = "eq", toKey = "filter" },
  { id = "eq_to_fx1", fromKey = "eq", toKey = "fx1" },
  { id = "eq_to_fx2", fromKey = "eq", toKey = "fx2" },
  { id = "eq_to_output", fromKey = "eq", toKey = "output" },
}

local EDGE_BIT_INDEX = {}
for i = 1, #EDGE_ORDER do
  EDGE_BIT_INDEX[EDGE_ORDER[i].id] = i - 1
end

local function maskFromIds(ids)
  local mask = 0
  for i = 1, #(ids or {}) do
    local bitIndex = EDGE_BIT_INDEX[ids[i]]
    if bitIndex ~= nil then
      mask = mask + (2 ^ bitIndex)
    end
  end
  return mask
end

local DEFAULT_EDGE_MASK = maskFromIds({
  "oscillator_to_filter",
  "filter_to_fx1",
  "fx1_to_fx2",
  "fx2_to_eq",
  "eq_to_output",
})

M.EDGE_ORDER = EDGE_ORDER
M.DEFAULT_EDGE_MASK = DEFAULT_EDGE_MASK
M.MAX_EDGE_MASK = (2 ^ #EDGE_ORDER) - 1
M.STAGE_FILTER = 1
M.STAGE_FX1 = 2
M.STAGE_FX2 = 3
M.STAGE_EQ = 4
M.DYNAMIC_EQ_STAGE_BASE = 100
M.DYNAMIC_FX_STAGE_BASE = 200
M.DYNAMIC_FILTER_STAGE_BASE = 300

local function bitIsSet(mask, bitIndex)
  return math.floor((tonumber(mask) or 0) / (2 ^ bitIndex)) % 2 >= 1
end

local function clampMask(value)
  local mask = math.floor((tonumber(value) or DEFAULT_EDGE_MASK) + 0.5)
  if mask < 0 then
    return 0
  end
  if mask > M.MAX_EDGE_MASK then
    return M.MAX_EDGE_MASK
  end
  return mask
end

local function slotInputNodes(slot)
  local inputs = {}
  if type(slot) ~= "table" then
    return inputs
  end

  -- Lazy FX slots have a single ingress (`slot.input`) that internally fans out
  -- to dry + currently instantiated effect inputs. Routing the rack source to
  -- individual effect inputs only works for whatever instances happened to exist
  -- when the route was compiled, which is why chorus (the default startup effect)
  -- kept working while newly selected effects stayed silent.
  if slot.input then
    inputs[#inputs + 1] = slot.input
    return inputs
  end

  -- Fallback for older eager-style slot implementations.
  if slot.dry then
    inputs[#inputs + 1] = slot.dry
  end

  local effects = type(slot.effects) == "table" and slot.effects or {}
  for i = 1, #effects do
    local effect = effects[i]
    if effect and effect.input then
      inputs[#inputs + 1] = effect.input
    end
  end

  return inputs
end

local function appendConnection(applied, fromNode, toNode)
  if not (fromNode and toNode) then
    return
  end

  for i = 1, #applied do
    local existing = applied[i]
    if existing and existing.from == fromNode and existing.to == toNode then
      return
    end
  end

  applied[#applied + 1] = { from = fromNode, to = toNode }
end

function M.create(ctx, nodes)
  nodes = nodes or {}

  local router = {
    ctx = ctx,
    oscillator = nodes.oscillator,
    sources = type(nodes.sources) == "table" and nodes.sources or nil,
    filter = nodes.filter,
    fx1 = nodes.fx1,
    fx2 = nodes.fx2,
    eq = nodes.eq,
    dynamicEqSlots = type(nodes.dynamicEqSlots) == "table" and nodes.dynamicEqSlots or {},
    dynamicFxSlots = type(nodes.dynamicFxSlots) == "table" and nodes.dynamicFxSlots or {},
    dynamicFilterSlots = type(nodes.dynamicFilterSlots) == "table" and nodes.dynamicFilterSlots or {},
    output = nodes.output,
    edgeMask = DEFAULT_EDGE_MASK,
    activeEdges = {},
    appliedConnections = {},
    stageSequence = { M.STAGE_FILTER, M.STAGE_FX1, M.STAGE_FX2, M.STAGE_EQ },
    stageDescriptors = {},
    stageLabels = { "filter", "fx1", "fx2", "eq" },
  }

  local function hasConnection(connections, fromNode, toNode)
    for i = 1, #(connections or {}) do
      local conn = connections[i]
      if conn and conn.from == fromNode and conn.to == toNode then
        return true
      end
    end
    return false
  end

  local function applyDesiredConnections(desired)
    local current = type(router.appliedConnections) == "table" and router.appliedConnections or {}

    -- Disconnect stale edges first. Structural edits like insert/splice can still
    -- produce a tiny audible discontinuity, but this avoids the much worse full
    -- graph teardown we were doing before for every topology update.
    for i = 1, #current do
      local conn = current[i]
      if conn and conn.from and conn.to and not hasConnection(desired, conn.from, conn.to) then
        ctx.graph.disconnect(conn.from, conn.to)
      end
    end

    for i = 1, #desired do
      local conn = desired[i]
      if conn and conn.from and conn.to and not hasConnection(current, conn.from, conn.to) then
        ctx.graph.connect(conn.from, conn.to)
      end
    end

    router.appliedConnections = desired
    return desired
  end

  local function connectIntoFxSlot(sourceNode, slot, applied)
    local inputNodes = slotInputNodes(slot)
    for i = 1, #inputNodes do
      appendConnection(applied, sourceNode, inputNodes[i])
    end
  end

  local function connectIntoTarget(sourceNode, targetKey, applied)
    if not sourceNode then
      return
    end

    if targetKey == "filter" then
      if router.filter then
        appendConnection(applied, sourceNode, router.filter)
      end
      return
    end

    if targetKey == "fx1" then
      connectIntoFxSlot(sourceNode, router.fx1, applied)
      return
    end

    if targetKey == "fx2" then
      connectIntoFxSlot(sourceNode, router.fx2, applied)
      return
    end

    if targetKey == "eq" then
      if router.eq then
        appendConnection(applied, sourceNode, router.eq)
      end
      return
    end

    if targetKey == "output" then
      if router.output then
        appendConnection(applied, sourceNode, router.output)
      end
      return
    end
  end

  local function resolveSourceNode(key)
    if key == "oscillator" then
      return router.oscillator
    elseif key == "filter" then
      return router.filter
    elseif key == "fx1" then
      return router.fx1 and router.fx1.output or nil
    elseif key == "fx2" then
      return router.fx2 and router.fx2.output or nil
    elseif key == "eq" then
      return router.eq
    end
    return nil
  end

  local function stageDescriptorForCode(code)
    local stageCode = math.max(0, math.floor(tonumber(code) or 0))
    if stageCode == M.STAGE_FILTER then
      return {
        label = "filter",
        kind = "node_target",
        targetNode = router.filter,
        outputNode = router.filter,
      }
    elseif stageCode == M.STAGE_FX1 then
      return {
        label = "fx1",
        kind = "fx_slot",
        targetSlot = router.fx1,
        outputNode = router.fx1 and router.fx1.output or nil,
      }
    elseif stageCode == M.STAGE_FX2 then
      return {
        label = "fx2",
        kind = "fx_slot",
        targetSlot = router.fx2,
        outputNode = router.fx2 and router.fx2.output or nil,
      }
    elseif stageCode == M.STAGE_EQ then
      return {
        label = "eq",
        kind = "node_target",
        targetNode = router.eq,
        outputNode = router.eq,
      }
    elseif stageCode >= M.DYNAMIC_EQ_STAGE_BASE and stageCode < M.DYNAMIC_FX_STAGE_BASE then
      local slotIndex = stageCode - M.DYNAMIC_EQ_STAGE_BASE
      local slot = router.dynamicEqSlots[slotIndex]
      local node = slot and slot.node or nil
      if node then
        return {
          label = "eq_slot_" .. tostring(slotIndex),
          kind = "node_target",
          targetNode = node,
          outputNode = node,
        }
      end
    elseif stageCode >= M.DYNAMIC_FX_STAGE_BASE and stageCode < M.DYNAMIC_FILTER_STAGE_BASE then
      local slotIndex = stageCode - M.DYNAMIC_FX_STAGE_BASE
      local slot = router.dynamicFxSlots[slotIndex]
      local node = slot and slot.output or nil
      if node then
        return {
          label = "fx_slot_" .. tostring(slotIndex),
          kind = "fx_slot",
          targetSlot = slot,
          outputNode = node,
        }
      end
    elseif stageCode >= M.DYNAMIC_FILTER_STAGE_BASE then
      local slotIndex = stageCode - M.DYNAMIC_FILTER_STAGE_BASE
      local slot = router.dynamicFilterSlots[slotIndex]
      local node = slot and slot.node or nil
      if node then
        return {
          label = "filter_slot_" .. tostring(slotIndex),
          kind = "node_target",
          targetNode = node,
          outputNode = node,
        }
      end
    end
    return nil
  end

  local function connectIntoStageDescriptor(sourceNode, descriptor, applied)
    if not (sourceNode and type(descriptor) == "table") then
      return
    end
    local kind = tostring(descriptor.kind or "")
    if kind == "fx_slot" then
      connectIntoFxSlot(sourceNode, descriptor.targetSlot, applied)
      return
    end
    if kind == "node_target" then
      appendConnection(applied, sourceNode, descriptor.targetNode)
      return
    end
    local targetKey = tostring(descriptor.targetKey or "")
    if targetKey ~= "" then
      connectIntoTarget(sourceNode, targetKey, applied)
    end
  end

  local function collectSourceNodes(sources)
    local currentSources = {}
    if type(sources) == "table" and #sources > 0 then
      for i = 1, #sources do
        if sources[i] then
          currentSources[#currentSources + 1] = sources[i]
        end
      end
    elseif router.oscillator then
      currentSources[1] = router.oscillator
    end
    return currentSources
  end

  local function applyStageDescriptors(descriptors, sourceNodes, connectOutput, sequenceSnapshot)
    local applied = {}
    local currentSources = collectSourceNodes(sourceNodes)
    local appliedDescriptors = {}
    local appliedLabels = {}
    local shouldConnectOutput = connectOutput == true

    for i = 1, #(descriptors or {}) do
      local descriptor = descriptors[i]
      if descriptor and descriptor.outputNode then
        for sourceIndex = 1, #currentSources do
          connectIntoStageDescriptor(currentSources[sourceIndex], descriptor, applied)
        end
        currentSources = { descriptor.outputNode }
        appliedDescriptors[#appliedDescriptors + 1] = descriptor
        appliedLabels[#appliedLabels + 1] = tostring(descriptor.label or "stage")
      end
    end

    if shouldConnectOutput and router.output then
      for sourceIndex = 1, #currentSources do
        if currentSources[sourceIndex] then
          appendConnection(applied, currentSources[sourceIndex], router.output)
        end
      end
    end

    applyDesiredConnections(applied)
    router.stageSequence = type(sequenceSnapshot) == "table" and sequenceSnapshot or appliedLabels
    router.stageDescriptors = appliedDescriptors
    router.stageLabels = appliedLabels
    router.connectOutput = shouldConnectOutput
    return router.stageSequence
  end

  function router.applyEdgeMask(value)
    local mask = clampMask(value)

    local applied = {}
    local activeEdges = {}
    for i = 1, #EDGE_ORDER do
      local edge = EDGE_ORDER[i]
      if bitIsSet(mask, i - 1) then
        connectIntoTarget(resolveSourceNode(edge.fromKey), edge.toKey, applied)
        activeEdges[#activeEdges + 1] = edge.id
      end
    end

    applyDesiredConnections(applied)
    router.edgeMask = mask
    router.activeEdges = activeEdges
    return mask
  end

  function router.applyStageSequence(sequence, connectOutput)
    local nextSequence = {}
    local descriptors = {}
    if type(sequence) == "table" then
      for i = 1, #sequence do
        local stageCode = math.max(0, math.floor(tonumber(sequence[i]) or 0))
        nextSequence[#nextSequence + 1] = stageCode
        local descriptor = stageDescriptorForCode(stageCode)
        if descriptor and descriptor.outputNode then
          descriptors[#descriptors + 1] = descriptor
        end
      end
    end
    return applyStageDescriptors(descriptors, router.sources, connectOutput, nextSequence)
  end

  function router.applyResolvedStageSequence(descriptors, sources, connectOutput, labels)
    local sourceNodes = type(sources) == "table" and sources or router.sources
    local sequenceSnapshot = nil
    if type(labels) == "table" then
      sequenceSnapshot = labels
    end
    return applyStageDescriptors(descriptors or {}, sourceNodes, connectOutput, sequenceSnapshot)
  end

  function router.getDebugState()
    return {
      edgeMask = router.edgeMask,
      activeEdges = router.activeEdges,
      edgeCount = #router.activeEdges,
      activePath = table.concat(router.activeEdges, " | "),
      stageSequence = router.stageSequence,
      stageLabels = router.stageLabels,
      connectOutput = router.connectOutput == true,
      appliedConnectionCount = #router.appliedConnections,
    }
  end

  return router
end

return M

-- Palette Browser Module for Midisynth

local MidiSynthRackSpecs = require("behaviors.rack_midisynth_specs")
local RackLayout = require("behaviors.rack_layout")
local RackModuleFactory = require("ui.rack_module_factory")

local M = {}

local _setPath = nil
local _VOICE_COUNT = 8
local _refreshManagedLayoutState = nil
local _getScopedWidget = nil
local _getWidgetBoundsInRoot = nil
local _getWidgetBounds = nil
local _setWidgetBounds = nil
local _syncText = nil
local _syncColour = nil
local _computeRackFlowTargetPlacement = nil
local _previewRackDragReorder = nil
local _finalizeRackDragReorder = nil
local _ensureDragGhost = nil
local _updateDragGhost = nil
local _hideDragGhost = nil
local _resetDragState = nil
local _dragState = nil
local _getRackShellMetaByNodeId = nil
local _collectRackFlowSnapshot = nil
local _pointInsideRackFlowBands = nil
local _requestDynamicModuleSlot = nil

function M.init(deps)
  _setPath = deps.setPath
  _VOICE_COUNT = deps.voiceCount or 8
  _refreshManagedLayoutState = deps.refreshManagedLayoutState
  _getScopedWidget = deps.getScopedWidget
  _getWidgetBoundsInRoot = deps.getWidgetBoundsInRoot
  _getWidgetBounds = deps.getWidgetBounds
  _setWidgetBounds = deps.setWidgetBounds
  _syncText = deps.syncText
  _syncColour = deps.syncColour
  _computeRackFlowTargetPlacement = deps.computeRackFlowTargetPlacement
  _previewRackDragReorder = deps.previewRackDragReorder
  _finalizeRackDragReorder = deps.finalizeRackDragReorder
  _ensureDragGhost = deps.ensureDragGhost
  _updateDragGhost = deps.updateDragGhost
  _hideDragGhost = deps.hideDragGhost
  _resetDragState = deps.resetDragState
  _dragState = deps.dragState
  _getRackShellMetaByNodeId = deps.getRackShellMetaByNodeId
  _collectRackFlowSnapshot = deps.collectRackFlowSnapshot
  _pointInsideRackFlowBands = deps.pointInsideRackFlowBands
  _requestDynamicModuleSlot = deps.requestDynamicModuleSlot
end

function M.attach(host)
  host._getPaletteEntry = M._getPaletteEntry
  host._selectPaletteEntry = M._selectPaletteEntry
  host._ensurePaletteSelection = M._ensurePaletteSelection
  host._requestUtilityBrowserRefresh = M._requestUtilityBrowserRefresh
  host._togglePaletteBrowseSection = M._togglePaletteBrowseSection
  host._isPaletteBrowseSectionCollapsed = M._isPaletteBrowseSectionCollapsed
  host._paletteBrowseEntryButtonMap = M._paletteBrowseEntryButtonMap
  host._paletteEntryIndex = M._paletteEntryIndex
  host._paletteCardMetrics = M._paletteCardMetrics
  host._getFilteredPaletteEntries = M._getFilteredPaletteEntries
  host._paletteViewportWidth = M._paletteViewportWidth
  host._paletteViewportHeight = M._paletteViewportHeight
  host._palettePreferredColumnCount = M._palettePreferredColumnCount
  host._paletteGridColumnCount = M._paletteGridColumnCount
  host._palettePreferredWidth = M._palettePreferredWidth
  host._paletteContentHeight = M._paletteContentHeight
  host._paletteMaxScrollOffset = M._paletteMaxScrollOffset
  host._clampPaletteScrollOffset = M._clampPaletteScrollOffset
  host._ensureSelectedPaletteScrollVisible = M._ensureSelectedPaletteScrollVisible
  host._nextAvailableCanonicalFilterNodeId = M._nextAvailableCanonicalFilterNodeId
  host._nextAvailableCanonicalFxNodeId = M._nextAvailableCanonicalFxNodeId
  host._canSpawnPaletteEntry = M._canSpawnPaletteEntry
  host._buildPaletteNodeFromEntry = M._buildPaletteNodeFromEntry
  host._buildPaletteNode = M._buildPaletteNode
  host._clearPaletteDragPreview = M._clearPaletteDragPreview
  host._setupUtilityPaletteBrowserHandlers = M._setupUtilityPaletteBrowserHandlers
  host._setupPaletteDragHandlers = M._setupPaletteDragHandlers
  host._syncPaletteCardState = M._syncPaletteCardState
end

local PALETTE_SPEC_TEMPLATES = MidiSynthRackSpecs.paletteEntryTemplateById()

local function makePaletteEntry(specId, overrides)
  local base = PALETTE_SPEC_TEMPLATES[tostring(specId or "")] or {}
  local entry = {
    id = tostring(specId or ""),
    specId = tostring(specId or ""),
    category = tostring(base.category or "utility"),
    accentColor = base.accentColor,
    displayName = tostring(base.displayName or specId or "Module"),
    description = tostring(base.description or ""),
    portSummary = tostring(base.portSummary or ""),
  }
  if type(overrides) == "table" then
    for key, value in pairs(overrides) do
      entry[key] = value
    end
  end
  return entry
end

M._PALETTE_ENTRIES = {
  makePaletteEntry("placeholder", {
    id = "placeholder",
    cardId = "palettePlaceholderCard",
    hintId = "palettePlaceholderHint",
    spawnKind = "dynamic",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1" },
  }),
  makePaletteEntry("adsr", {
    id = "adsr",
    cardId = "paletteAdsrCard",
    hintId = "paletteAdsrHint",
    spawnKind = "adsr-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "envelopeComponent" },
  }),
  makePaletteEntry("arp", {
    id = "arp",
    cardId = "paletteArpCard",
    hintId = "paletteArpHint",
    spawnKind = "arp-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "arpComponent" },
  }),
  makePaletteEntry("transpose", {
    id = "transpose",
    cardId = "paletteTransposeCard",
    hintId = "paletteTransposeHint",
    spawnKind = "transpose-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "transposeComponent" },
  }),
  makePaletteEntry("velocity_mapper", {
    id = "velocity_mapper",
    cardId = "paletteVelocityMapperCard",
    hintId = "paletteVelocityMapperHint",
    spawnKind = "velocity-mapper-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "velocityMapperComponent" },
  }),
  makePaletteEntry("scale_quantizer", {
    id = "scale_quantizer",
    cardId = "paletteScaleQuantizerCard",
    hintId = "paletteScaleQuantizerHint",
    spawnKind = "scale-quantizer-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "scaleQuantizerComponent" },
  }),
  makePaletteEntry("note_filter", {
    id = "note_filter",
    cardId = "paletteNoteFilterCard",
    hintId = "paletteNoteFilterHint",
    spawnKind = "note-filter-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "noteFilterComponent" },
  }),
  makePaletteEntry("rack_oscillator", {
    id = "rack_oscillator",
    cardId = "paletteRackOscillatorCard",
    hintId = "paletteRackOscillatorHint",
    spawnKind = "oscillator-module",
    defaultNode = { w = 2, h = 1, sizeKey = "1x2", componentId = "rackOscillatorComponent" },
  }),
  makePaletteEntry("rack_sample", {
    id = "rack_sample",
    cardId = "paletteRackSampleCard",
    hintId = "paletteRackSampleHint",
    spawnKind = "sample-module",
    defaultNode = { w = 2, h = 1, sizeKey = "1x2", componentId = "rackSampleComponent" },
  }),
  makePaletteEntry("blend_simple", {
    id = "blend_simple",
    cardId = "paletteBlendSimpleCard",
    hintId = "paletteBlendSimpleHint",
    spawnKind = "blend-simple-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "rackBlendSimpleComponent" },
  }),
  makePaletteEntry("filter", {
    id = "filter",
    cardId = "paletteFilterCard",
    hintId = "paletteFilterHint",
    nodeId = "filter",
    spawnKind = "filter-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "filterComponent" },
  }),
  makePaletteEntry("eq", {
    id = "eq",
    cardId = "paletteEqCard",
    hintId = "paletteEqHint",
    nodeId = "eq",
    spawnKind = "eq-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "eqComponent" },
  }),
  makePaletteEntry("fx", {
    id = "fx",
    cardId = "paletteFxCard",
    hintId = "paletteFxHint",
    spawnKind = "fx-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "fx1Component" },
  }),
  makePaletteEntry("attenuverter_bias", {
    id = "attenuverter_bias",
    cardId = "paletteAttenuverterBiasCard",
    hintId = "paletteAttenuverterBiasHint",
    spawnKind = "attenuverter-bias-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "attenuverterBiasComponent" },
  }),
  makePaletteEntry("lfo", {
    id = "lfo",
    cardId = "paletteLfoCard",
    hintId = "paletteLfoHint",
    spawnKind = "lfo-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "lfoComponent" },
  }),
  makePaletteEntry("slew", {
    id = "slew",
    cardId = "paletteSlewCard",
    hintId = "paletteSlewHint",
    spawnKind = "slew-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "slewComponent" },
  }),
  makePaletteEntry("sample_hold", {
    id = "sample_hold",
    cardId = "paletteSampleHoldCard",
    hintId = "paletteSampleHoldHint",
    spawnKind = "sample-hold-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "sampleHoldComponent" },
  }),
  makePaletteEntry("compare", {
    id = "compare",
    cardId = "paletteCompareCard",
    hintId = "paletteCompareHint",
    spawnKind = "compare-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "compareComponent" },
  }),
  makePaletteEntry("cv_mix", {
    id = "cv_mix",
    cardId = "paletteCvMixCard",
    hintId = "paletteCvMixHint",
    spawnKind = "cv-mix-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "cvMixComponent" },
  }),
  makePaletteEntry("range_mapper", {
    id = "range_mapper",
    cardId = "paletteRangeMapperCard",
    hintId = "paletteRangeMapperHint",
    spawnKind = "range_mapper-module",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1", componentId = "rangeMapperComponent" },
  }),
}


local function getActiveRackNodes(ctx)
  return (ctx and (ctx._dragPreviewModules or (ctx._rackState and ctx._rackState.modules))) or {}
end

local function getActiveRackNodeById(ctx, nodeId)
  local nodes = getActiveRackNodes(ctx)
  for i = 1, #nodes do
    if nodes[i] and nodes[i].id == nodeId then
      return nodes[i]
    end
  end
  return nil
end

function M._getPaletteEntry(entryId)
  local targetId = tostring(entryId or "")
  for i = 1, #M._PALETTE_ENTRIES do
    local entry = M._PALETTE_ENTRIES[i]
    if entry and tostring(entry.id or "") == targetId then
      return entry
    end
  end
  return nil
end

function M._selectPaletteEntry(ctx, entryId)
  local entry = M._getPaletteEntry(entryId)
  if type(ctx) ~= "table" or type(entry) ~= "table" then
    return nil
  end
  ctx._selectedPaletteEntryId = tostring(entry.id or "")
  ctx._suppressPaletteAutoScroll = false
  M._ensureSelectedPaletteScrollVisible(ctx)
  M._requestUtilityBrowserRefresh(ctx)
  return entry
end

function M._ensurePaletteSelection(ctx)
  if type(ctx) ~= "table" then
    return nil
  end
  local selected = M._getPaletteEntry(ctx._selectedPaletteEntryId)
  if selected then
    return selected
  end
  local fallback = M._PALETTE_ENTRIES[1]
  if fallback then
    ctx._selectedPaletteEntryId = tostring(fallback.id or "")
  end
  return fallback
end

function M._requestUtilityBrowserRefresh(ctx)
  if type(ctx) ~= "table" then
    return
  end
  if ctx._lastW and ctx._lastH then
    _refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
  end
end

function M._togglePaletteBrowseSection(ctx, sectionId)
  if type(ctx) ~= "table" then
    return
  end
  ctx._paletteBrowseCollapsed = ctx._paletteBrowseCollapsed or { voice = false, audio = false, fx = false, mod = false }
  local key = tostring(sectionId or "")
  if key == "voice" or key == "audio" or key == "fx" or key == "mod" then
    ctx._paletteBrowseCollapsed[key] = not not (not ctx._paletteBrowseCollapsed[key])
    M._requestUtilityBrowserRefresh(ctx)
  end
end

function M._isPaletteBrowseSectionCollapsed(ctx, sectionId)
  local collapsed = type(ctx) == "table" and ctx._paletteBrowseCollapsed or nil
  if type(collapsed) ~= "table" then
    return false
  end
  return collapsed[tostring(sectionId or "")] == true
end

function M._paletteBrowseEntryButtonMap()
  return {
    adsr = "utilityNavVoiceAdsr",
    arp = "utilityNavVoiceArp",
    transpose = "utilityNavVoiceTranspose",
    velocity_mapper = "utilityNavVoiceVelocityMapper",
    scale_quantizer = "utilityNavVoiceScaleQuantizer",
    note_filter = "utilityNavVoiceNoteFilter",
    placeholder = "utilityNavAudioPlaceholder",
    rack_oscillator = "utilityNavAudioOsc",
    rack_sample = "utilityNavAudioSample",
    filter = "utilityNavAudioFilter",
    eq = "utilityNavFxEq",
    fx = "utilityNavFxFx",
    attenuverter_bias = "utilityNavModAttenuverterBias",
    lfo = "utilityNavModLfo",
    slew = "utilityNavModSlew",
    sample_hold = "utilityNavModSampleHold",
    compare = "utilityNavModCompare",
    cv_mix = "utilityNavModCvMix",
    range_mapper = "utilityNavFxRange",
  }
end

function M._paletteEntryIndex(entryId)
  local targetId = tostring(entryId or "")
  for i = 1, #M._PALETTE_ENTRIES do
    local entry = M._PALETTE_ENTRIES[i]
    if entry and tostring(entry.id or "") == targetId then
      return i
    end
  end
  return nil
end

function M._paletteCardMetrics()
  return {
    w = 102,
    h = 56,
    gap = 6,
    rowGap = 6,
    pad = 8,
    step = 62,
    trackW = 8,
  }
end

function M._getFilteredPaletteEntries(ctx)
  local entries = M._PALETTE_ENTRIES or {}
  local tags = type(ctx) == "table" and ctx._paletteFilterTags or {}
  local showAll = type(ctx) == "table" and ctx._paletteFilterTagAll ~= false
  local searchText = type(ctx) == "table" and tostring(ctx._paletteSearchText or ""):lower() or ""
  local hasTagFilter = type(tags) == "table" and next(tags) ~= nil
  local hasSearchFilter = searchText ~= ""
  if not hasTagFilter and not hasSearchFilter then
    return entries
  end
  local filtered = {}
  for i = 1, #entries do
    local entry = entries[i]
    local category = tostring(entry.category or "utility")
    local name = tostring(entry.displayName or entry.id or ""):lower()
    local matchesSearch = not hasSearchFilter or (name:find(searchText, 1, true) ~= nil)
    local matchesTag = showAll or (not hasTagFilter) or (tags[category] == true)
    if matchesSearch and matchesTag then
      filtered[#filtered + 1] = entry
    end
  end
  return filtered
end

function M._paletteViewportWidth(ctx)
  local strip = _getScopedWidget(ctx, ".paletteStrip")
  local m = M._paletteCardMetrics()
  if strip and strip.node and strip.node.getBounds then
    local _, _, w, _ = strip.node:getBounds()
    return math.max(1, math.floor(tonumber(w) or 0) - m.trackW - 6)
  end
  return 540
end

function M._paletteViewportHeight(ctx)
  local strip = _getScopedWidget(ctx, ".paletteStrip")
  if strip and strip.node and strip.node.getBounds then
    local _, _, _, h = strip.node:getBounds()
    return math.max(1, math.floor(tonumber(h) or 0))
  end
  return 136
end

function M._palettePreferredColumnCount(ctx)
  local _ = ctx
  return 6
end

function M._paletteGridColumnCount(ctx)
  return math.max(1, math.min(M._palettePreferredColumnCount(ctx), #M._PALETTE_ENTRIES > 0 and #M._PALETTE_ENTRIES or 1))
end

function M._palettePreferredWidth(ctx)
  local m = M._paletteCardMetrics()
  local columns = M._paletteGridColumnCount(ctx)
  return (m.pad * 2) + (columns * m.w) + (math.max(0, columns - 1) * m.gap) + m.trackW + 6
end

function M._paletteContentHeight(ctx)
  local m = M._paletteCardMetrics()
  local columns = M._paletteGridColumnCount(ctx)
  local rows = math.max(1, math.ceil(#M._PALETTE_ENTRIES / columns))
  return (m.pad * 2) + (rows * m.h) + (math.max(0, rows - 1) * m.rowGap)
end

function M._paletteMaxScrollOffset(ctx)
  local viewportH = M._paletteViewportHeight(ctx)
  local contentH = M._paletteContentHeight(ctx)
  return math.max(0, contentH - viewportH)
end

function M._clampPaletteScrollOffset(ctx)
  if type(ctx) ~= "table" then
    return 0
  end
  local maxOffset = M._paletteMaxScrollOffset(ctx)
  local offset = math.max(0, math.floor(tonumber(ctx._paletteScrollOffset) or 0))
  if offset > maxOffset then
    offset = maxOffset
  end
  ctx._paletteScrollOffset = offset
  return offset
end

function M._ensureSelectedPaletteScrollVisible(ctx)
  if type(ctx) ~= "table" then
    return
  end
  local index = M._paletteEntryIndex(ctx._selectedPaletteEntryId)
  if not index then
    return
  end
  local m = M._paletteCardMetrics()
  local columns = M._paletteGridColumnCount(ctx)
  local viewportH = M._paletteViewportHeight(ctx)
  local row = math.floor((index - 1) / columns)
  local itemTop = m.pad + (row * (m.h + m.rowGap))
  local itemBottom = itemTop + m.h
  local offset = M._clampPaletteScrollOffset(ctx)
  local viewTop = offset
  local viewBottom = offset + viewportH
  if itemTop < viewTop then
    ctx._paletteScrollOffset = math.max(0, itemTop - m.pad)
  elseif itemBottom > viewBottom then
    ctx._paletteScrollOffset = math.max(0, itemBottom - viewportH + m.pad)
  end
  M._clampPaletteScrollOffset(ctx)
end

function M._nextAvailableCanonicalFilterNodeId(ctx)
  if getActiveRackNodeById(ctx, "filter") == nil then
    return "filter"
  end
  return nil
end

function M._nextAvailableCanonicalFxNodeId(ctx)
  if getActiveRackNodeById(ctx, "fx1") == nil then
    return "fx1"
  end
  if getActiveRackNodeById(ctx, "fx2") == nil then
    return "fx2"
  end
  return nil
end

function M._canSpawnPaletteEntry(ctx, entry)
  if type(entry) ~= "table" then
    return false
  end
  local spawnKind = tostring(entry.spawnKind or "dynamic")
  if spawnKind == "adsr-module" then
    if getActiveRackNodeById(ctx, "adsr") == nil then
      return true
    end
    return RackModuleFactory.nextAvailableSlot(ctx, "adsr") ~= nil
  elseif spawnKind == "arp-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "arp") ~= nil
  elseif spawnKind == "transpose-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "transpose") ~= nil
  elseif spawnKind == "velocity-mapper-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "velocity_mapper") ~= nil
  elseif spawnKind == "scale-quantizer-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "scale_quantizer") ~= nil
  elseif spawnKind == "note-filter-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "note_filter") ~= nil
  elseif spawnKind == "attenuverter-bias-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "attenuverter_bias") ~= nil
  elseif spawnKind == "lfo-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "lfo") ~= nil
  elseif spawnKind == "slew-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "slew") ~= nil
  elseif spawnKind == "sample-hold-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "sample_hold") ~= nil
  elseif spawnKind == "compare-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "compare") ~= nil
  elseif spawnKind == "cv-mix-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "cv_mix") ~= nil
  elseif spawnKind == "oscillator-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "rack_oscillator") ~= nil
  elseif spawnKind == "sample-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "rack_sample") ~= nil
  elseif spawnKind == "eq-module" then
    if getActiveRackNodeById(ctx, "eq") == nil then
      return true
    end
    return RackModuleFactory.nextAvailableSlot(ctx, "eq") ~= nil
  elseif spawnKind == "filter-module" then
    if M._nextAvailableCanonicalFilterNodeId(ctx) ~= nil then
      return true
    end
    return RackModuleFactory.nextAvailableSlot(ctx, "filter") ~= nil
  elseif spawnKind == "fx-module" then
    if M._nextAvailableCanonicalFxNodeId(ctx) ~= nil then
      return true
    end
    return RackModuleFactory.nextAvailableSlot(ctx, "fx") ~= nil
  elseif spawnKind == "range_mapper-module" then
    return RackModuleFactory.nextAvailableSlot(ctx, "range_mapper") ~= nil
  end
  return true
end

function M._buildPaletteNodeFromEntry(ctx, entry)
  if not M._canSpawnPaletteEntry(ctx, entry) then
    return nil, nil, false
  end

  local specId = tostring(entry and entry.specId or "")
  local defaultNode = type(entry) == "table" and entry.defaultNode or nil
  local width = math.max(1, math.floor(tonumber(defaultNode and defaultNode.w) or 1))
  local height = math.max(1, math.floor(tonumber(defaultNode and defaultNode.h) or 1))
  local sizeKey = type(defaultNode and defaultNode.sizeKey) == "string" and defaultNode.sizeKey or string.format("%dx%d", height, width)
  local spawnKind = tostring(entry and entry.spawnKind or "dynamic")

  if spawnKind == "adsr-module" and getActiveRackNodeById(ctx, "adsr") == nil then
    local spec = ctx and ctx._rackModuleSpecs and ctx._rackModuleSpecs[specId] or nil
    if type(spec) ~= "table" then
      return nil, nil, false
    end
    local componentId = type(defaultNode and defaultNode.componentId) == "string" and defaultNode.componentId
      or type(spec.meta and spec.meta.componentId) == "string" and spec.meta.componentId
      or "envelopeComponent"
    local node = RackLayout.makeRackModuleInstance {
      id = "adsr",
      row = 0,
      col = 0,
      w = width,
      h = height,
      sizeKey = sizeKey,
      meta = {
        specId = specId,
        componentId = componentId,
        spawned = true,
      },
    }
    return "adsr", node, false
  end

  if spawnKind == "eq-module" and getActiveRackNodeById(ctx, "eq") == nil then
    local spec = ctx and ctx._rackModuleSpecs and ctx._rackModuleSpecs[specId] or nil
    if type(spec) ~= "table" then
      return nil, nil, false
    end
    local componentId = type(defaultNode and defaultNode.componentId) == "string" and defaultNode.componentId
      or type(spec.meta and spec.meta.componentId) == "string" and spec.meta.componentId
      or "eqComponent"
    local node = RackLayout.makeRackModuleInstance {
      id = "eq",
      row = 0,
      col = 0,
      w = width,
      h = height,
      sizeKey = sizeKey,
      meta = {
        specId = specId,
        componentId = componentId,
        spawned = true,
      },
    }
    return "eq", node, false
  end

  if spawnKind == "filter-module" then
    local canonicalFilterNodeId = M._nextAvailableCanonicalFilterNodeId(ctx)
    if canonicalFilterNodeId ~= nil then
      local canonicalSpec = ctx and ctx._rackModuleSpecs and ctx._rackModuleSpecs[canonicalFilterNodeId] or nil
      if type(canonicalSpec) ~= "table" then
        return nil, nil, false
      end
      local canonicalComponentId = type(defaultNode and defaultNode.componentId) == "string" and defaultNode.componentId
        or type(canonicalSpec.meta and canonicalSpec.meta.componentId) == "string" and canonicalSpec.meta.componentId
        or "filterComponent"
      local canonicalNode = RackLayout.makeRackModuleInstance {
        id = canonicalFilterNodeId,
        row = 0,
        col = 0,
        w = width,
        h = height,
        sizeKey = sizeKey,
        meta = {
          specId = specId,
          componentId = canonicalComponentId,
          spawned = true,
        },
      }
      return canonicalFilterNodeId, canonicalNode, false
    end
  end

  if spawnKind == "fx-module" then
    local canonicalFxNodeId = M._nextAvailableCanonicalFxNodeId(ctx)
    if canonicalFxNodeId ~= nil then
      local canonicalSpec = ctx and ctx._rackModuleSpecs and ctx._rackModuleSpecs[canonicalFxNodeId] or nil
      if type(canonicalSpec) ~= "table" then
        return nil, nil, false
      end
      local canonicalComponentId = type(defaultNode and defaultNode.componentId) == "string" and defaultNode.componentId
        or type(canonicalSpec.meta and canonicalSpec.meta.componentId) == "string" and canonicalSpec.meta.componentId
        or (canonicalFxNodeId == "fx2" and "fx2Component" or "fx1Component")
      local canonicalNode = RackLayout.makeRackModuleInstance {
        id = canonicalFxNodeId,
        row = 0,
        col = 0,
        w = width,
        h = height,
        sizeKey = sizeKey,
        meta = {
          specId = canonicalFxNodeId,
          componentId = canonicalComponentId,
          spawned = true,
        },
      }
      return canonicalFxNodeId, canonicalNode, false
    end
  end

  local dynamicMeta = nil
  if spawnKind == "adsr-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "adsr", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "arp-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "arp", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "transpose-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "transpose", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "velocity-mapper-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "velocity_mapper", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "scale-quantizer-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "scale_quantizer", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "note-filter-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "note_filter", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "attenuverter-bias-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "attenuverter_bias", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "lfo-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "lfo", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "slew-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "slew", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "sample-hold-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "sample_hold", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "compare-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "compare", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "cv-mix-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "cv_mix", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "eq-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "eq", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "oscillator-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "rack_oscillator", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "sample-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "rack_sample", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "blend-simple-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "blend_simple", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "filter-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "filter", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "fx-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "fx", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  elseif spawnKind == "range_mapper-module" then
    dynamicMeta = RackModuleFactory.createDynamicSpawnMeta(ctx, "range_mapper", {
      _setPath = _setPath,
      voiceCount = _VOICE_COUNT,
    })
  end

  if spawnKind ~= "dynamic" and dynamicMeta == nil then
    return nil, nil, false
  end

  local nodeId = RackModuleFactory.nextDynamicNodeId(ctx, specId)
  local spec = RackModuleFactory.registerDynamicModuleSpec(ctx, specId, nodeId, dynamicMeta)
  if type(spec) ~= "table" then
    RackModuleFactory.releaseDynamicSpawnMeta(ctx, specId, dynamicMeta)
    return nil, nil, false
  end
  if dynamicMeta and dynamicMeta.slotIndex ~= nil then
    RackModuleFactory.markSlotOccupied(ctx, specId, dynamicMeta.slotIndex, nodeId)
    _requestDynamicModuleSlot(specId, dynamicMeta.slotIndex)
  end

  local node = RackLayout.makeRackModuleInstance {
    id = nodeId,
    row = 0,
    col = 0,
    w = width,
    h = height,
    sizeKey = sizeKey,
    meta = {
      specId = specId,
      componentId = tostring(spec.meta and spec.meta.componentId or "contentComponent"),
      spawned = true,
      slotIndex = dynamicMeta and dynamicMeta.slotIndex or nil,
      paramBase = dynamicMeta and dynamicMeta.paramBase or nil,
    },
  }
  return nodeId, node, true
end

function M._buildPaletteNode(ctx, specId)
  return M._buildPaletteNodeFromEntry(ctx, {
    id = tostring(specId or ""),
    specId = tostring(specId or ""),
    spawnKind = "dynamic",
    defaultNode = { w = 1, h = 1, sizeKey = "1x1" },
  })
end

function M._clearPaletteDragPreview(ctx)
  if ctx then
    ctx._dragPreviewModules = nil
  end
  _dragState.previewPlacement = nil
  _dragState.previewIndex = nil
  _dragState.targetIndex = nil
end

function M._setupUtilityPaletteBrowserHandlers(ctx)
  if type(ctx) ~= "table" or ctx._utilityPaletteBrowserHandlersReady == true then
    return
  end

  local function bindButton(suffix, onPress)
    local widget = _getScopedWidget(ctx, suffix)
    if not (widget and widget.node and onPress) then
      return
    end
    widget.node:setInterceptsMouse(true, true)
    widget.node:setOnMouseDown(function()
      onPress()
      M._requestUtilityBrowserRefresh(ctx)
    end)
    if widget.node.setOnMouseWheel then
      widget.node:setOnMouseWheel(function(mx, my, deltaY)
        local _ = mx
        _ = my
        local sign = (tonumber(deltaY) or 0) > 0 and -1 or 1
        local step = 24
        ctx._utilityNavScrollOffset = math.max(0, (tonumber(ctx._utilityNavScrollOffset) or 0) + (sign * step))
        M._requestUtilityBrowserRefresh(ctx)
      end)
    end
  end

  local utilityNavRail = _getScopedWidget(ctx, ".utilityNavRail")
  if utilityNavRail and utilityNavRail.node and utilityNavRail.node.setOnMouseWheel then
    utilityNavRail.node:setInterceptsMouse(true, true)
    utilityNavRail.node:setOnMouseWheel(function(mx, my, deltaY)
      local _ = mx
      _ = my
      local sign = (tonumber(deltaY) or 0) > 0 and -1 or 1
      local step = 24
      local nextOffset = math.max(0, (tonumber(ctx._utilityNavScrollOffset) or 0) + (sign * step))
      ctx._utilityNavScrollOffset = nextOffset
      M._requestUtilityBrowserRefresh(ctx)
    end)
  end

  local utilityBrowserBody = _getScopedWidget(ctx, ".utilityBrowserBody") or ctx.widgets.utilityBrowserBody
  local paletteStrip = _getScopedWidget(ctx, ".paletteStrip") or ctx.widgets.paletteStrip

  local searchPanel = _getScopedWidget(ctx, ".utilitySearchPanel")
  if searchPanel and searchPanel.node then
    searchPanel.node:setInterceptsMouse(true, true)
    searchPanel.node:setWantsKeyboardFocus(true)
    searchPanel.node:setOnMouseDown(function()
      ctx._paletteSearchFocused = true
      searchPanel.node:setWantsKeyboardFocus(true)
      M._requestUtilityBrowserRefresh(ctx)
    end)
    if searchPanel.node.setOnKeyPress then
      searchPanel.node:setOnKeyPress(function(keyCode, charCode, shift, ctrl, alt)
        if not ctx._paletteSearchFocused then
          return false
        end
        local _ = shift
        _ = ctrl
        _ = alt
        if keyCode == 27 then
          ctx._paletteSearchText = ""
          ctx._paletteSearchFocused = false
          M._requestUtilityBrowserRefresh(ctx)
          return true
        end
        if keyCode == 8 then
          local text = tostring(ctx._paletteSearchText or "")
          if #text > 0 then
            ctx._paletteSearchText = string.sub(text, 1, #text - 1)
          end
          M._requestUtilityBrowserRefresh(ctx)
          return true
        end
        if charCode and charCode >= 32 and charCode < 127 then
          local char = string.char(charCode)
          ctx._paletteSearchText = tostring(ctx._paletteSearchText or "") .. char
          M._requestUtilityBrowserRefresh(ctx)
          return true
        end
        return false
      end)
    end
  end
  
  local function handleScroll(mx, my, deltaY)
    local _ = mx
    _ = my
    local sign = (tonumber(deltaY) or 0) > 0 and -1 or 1
    local step = M._paletteCardMetrics().step
    local nextOffset = math.max(0, math.min(M._paletteMaxScrollOffset(ctx), (tonumber(ctx._paletteScrollOffset) or 0) + (sign * step)))
    if nextOffset ~= (tonumber(ctx._paletteScrollOffset) or 0) then
      ctx._paletteScrollOffset = nextOffset
      ctx._suppressPaletteAutoScroll = true
      M._requestUtilityBrowserRefresh(ctx)
    end
  end
  
  if utilityBrowserBody and utilityBrowserBody.node then
    utilityBrowserBody.node:setInterceptsMouse(true, true)
    if utilityBrowserBody.node.setOnMouseWheel then
      utilityBrowserBody.node:setOnMouseWheel(handleScroll)
    end
  end
  
  if paletteStrip and paletteStrip.node then
    paletteStrip.node:setInterceptsMouse(true, true)
    if paletteStrip.node.setOnMouseWheel then
      paletteStrip.node:setOnMouseWheel(handleScroll)
    end
  end

  bindButton(".utilityNavVoiceHeader", function()
    M._togglePaletteBrowseSection(ctx, "voice")
  end)
  bindButton(".utilityNavAudioHeader", function()
    M._togglePaletteBrowseSection(ctx, "audio")
  end)
  bindButton(".utilityNavFxHeader", function()
    M._togglePaletteBrowseSection(ctx, "fx")
  end)
  bindButton(".utilityNavModHeader", function()
    M._togglePaletteBrowseSection(ctx, "mod")
  end)

  bindButton(".palettePagePrev", function()
    local step = math.max(M._paletteCardMetrics().step, math.floor(M._paletteViewportHeight(ctx) * 0.75))
    ctx._paletteScrollOffset = math.max(0, (tonumber(ctx._paletteScrollOffset) or 0) - step)
    M._requestUtilityBrowserRefresh(ctx)
  end)
  bindButton(".palettePageNext", function()
    local step = math.max(M._paletteCardMetrics().step, math.floor(M._paletteViewportHeight(ctx) * 0.75))
    ctx._paletteScrollOffset = math.min(M._paletteMaxScrollOffset(ctx), (tonumber(ctx._paletteScrollOffset) or 0) + step)
    M._requestUtilityBrowserRefresh(ctx)
  end)

  bindButton(".utilityTagAll", function()
    ctx._paletteFilterTagAll = true
    ctx._paletteFilterTags = {}
    ctx._paletteScrollOffset = 0
    M._requestUtilityBrowserRefresh(ctx)
  end)
  bindButton(".utilityTagVoice", function()
    if ctx._paletteFilterTagAll then
      ctx._paletteFilterTagAll = false
      ctx._paletteFilterTags = { voice = true }
    else
      ctx._paletteFilterTags.voice = not ctx._paletteFilterTags.voice
      if next(ctx._paletteFilterTags) == nil then
        ctx._paletteFilterTagAll = true
      end
    end
    ctx._paletteScrollOffset = 0
    M._requestUtilityBrowserRefresh(ctx)
  end)
  bindButton(".utilityTagAudio", function()
    if ctx._paletteFilterTagAll then
      ctx._paletteFilterTagAll = false
      ctx._paletteFilterTags = { audio = true }
    else
      ctx._paletteFilterTags.audio = not ctx._paletteFilterTags.audio
      if next(ctx._paletteFilterTags) == nil then
        ctx._paletteFilterTagAll = true
      end
    end
    ctx._paletteScrollOffset = 0
    M._requestUtilityBrowserRefresh(ctx)
  end)
  bindButton(".utilityTagFx", function()
    if ctx._paletteFilterTagAll then
      ctx._paletteFilterTagAll = false
      ctx._paletteFilterTags = { fx = true }
    else
      ctx._paletteFilterTags.fx = not ctx._paletteFilterTags.fx
      if next(ctx._paletteFilterTags) == nil then
        ctx._paletteFilterTagAll = true
      end
    end
    ctx._paletteScrollOffset = 0
    M._requestUtilityBrowserRefresh(ctx)
  end)
  bindButton(".utilityTagMod", function()
    if ctx._paletteFilterTagAll then
      ctx._paletteFilterTagAll = false
      ctx._paletteFilterTags = { mod = true }
    else
      ctx._paletteFilterTags.mod = not ctx._paletteFilterTags.mod
      if next(ctx._paletteFilterTags) == nil then
        ctx._paletteFilterTagAll = true
      end
    end
    ctx._paletteScrollOffset = 0
    M._requestUtilityBrowserRefresh(ctx)
  end)

  ctx._utilityPaletteBrowserHandlersReady = true
end

function M._setupPaletteDragHandlers(ctx)
  for i = 1, #M._PALETTE_ENTRIES do
    local entry = M._PALETTE_ENTRIES[i]
    local paletteCard = _getScopedWidget(ctx, "." .. tostring(entry.cardId or ""))
    if paletteCard and paletteCard.node then
      paletteCard.node:setInterceptsMouse(true, false)
      local isDragging = false

      paletteCard.node:setOnMouseDown(function(x, y, shift)
        M._selectPaletteEntry(ctx, entry.id)
        local paletteBounds = _getWidgetBoundsInRoot(ctx, paletteCard)
        local nextNodeId, tempNode, unregisterOnCancel = M._buildPaletteNodeFromEntry(ctx, entry)
        if not paletteBounds or not nextNodeId or not tempNode then
          return
        end

        isDragging = true
        _dragState.active = true
        _dragState.sourceKind = "palette"
        _dragState.shellId = nil
        _dragState.moduleId = nextNodeId
        _dragState.row = nil
        _dragState.paletteEntryId = tostring(entry.id or "")
        _dragState.unregisterOnCancel = unregisterOnCancel == true
        _dragState.startX = x
        _dragState.startY = y
        _dragState.grabOffsetX = x
        _dragState.grabOffsetY = y
        _dragState.startIndex = nil
        _dragState.targetIndex = nil
        _dragState.previewIndex = nil
        _dragState.startPlacement = nil
        _dragState.previewPlacement = nil
        _dragState.rowSnapshot = nil
        _dragState.baseModules = RackLayout.cloneRackModules((ctx._rackState and ctx._rackState.modules) or {})
        _dragState.baseModules[#_dragState.baseModules + 1] = tempNode
        _dragState.insertMode = shift == true
        _dragState.ghostStartX = paletteBounds.x or 0
        _dragState.ghostStartY = paletteBounds.y or 0
        _dragState.ghostX = paletteBounds.x or 0
        _dragState.ghostY = paletteBounds.y or 0
        _dragState.ghostW = paletteBounds.w or 1
        _dragState.ghostH = paletteBounds.h or 1

        local _, ghostAccent = _ensureDragGhost(ctx)
        local spec = ctx._rackModuleSpecs and (ctx._rackModuleSpecs[nextNodeId] or ctx._rackModuleSpecs[tostring(entry.specId or "")]) or nil
        local ghostAccentColor = (spec and spec.accentColor) or 0xff64748b
        if ghostAccent then
          ghostAccent:setStyle({ bg = ghostAccentColor, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
        end
        _updateDragGhost(ctx)
      end)

      paletteCard.node:setOnMouseDrag(function(x, y, dx, dy)
        if not isDragging then return end

        _dragState.ghostX = (_dragState.ghostStartX or 0) + (tonumber(dx) or 0)
        _dragState.ghostY = (_dragState.ghostStartY or 0) + (tonumber(dy) or 0)
        _updateDragGhost(ctx)

        local snapshot = _collectRackFlowSnapshot(ctx)
        local ghostCenterX = (_dragState.ghostX or 0) + ((_dragState.ghostW or 0) * 0.5)
        local ghostCenterY = (_dragState.ghostY or 0) + ((_dragState.ghostH or 0) * 0.5)
        local movingNodeId = ctx._dragPreviewModules and _dragState.moduleId or nil

        if _pointInsideRackFlowBands(ctx, snapshot, ghostCenterX, ghostCenterY) then
          local targetPlacement = _computeRackFlowTargetPlacement(ctx, snapshot, movingNodeId, ghostCenterX, ghostCenterY)
          if targetPlacement then
            if _dragState.startPlacement == nil then
              _dragState.startPlacement = {
                mode = tostring(targetPlacement.mode or "flow"),
                row = targetPlacement.row,
                col = targetPlacement.col,
                index = targetPlacement.index,
              }
            end
            _previewRackDragReorder(ctx, targetPlacement)
          end
        else
          if ctx._dragPreviewModules ~= nil or _dragState.previewPlacement ~= nil then
            M._clearPaletteDragPreview(ctx)
            _refreshManagedLayoutState(ctx, ctx._lastW, ctx._lastH)
          end
        end
      end)

      paletteCard.node:setOnMouseUp(function()
        if not isDragging then return end
        isDragging = false
        _finalizeRackDragReorder(ctx)
        _hideDragGhost(ctx)
        _resetDragState(ctx)
      end)
    end
  end
end


function M._syncPaletteCardState(ctx)
  local changed = false
  local function ellipsize(text, maxChars)
    local s = tostring(text or "")
    local n = math.max(1, math.floor(tonumber(maxChars) or 1))
    if #s <= n then
      return s
    end
    if n <= 1 then
      return string.sub(s, 1, n)
    end
    return string.sub(s, 1, n - 1) .. "…"
  end

  local function paletteStatusText(entry, paletteAvailable)
    local id = tostring(entry and entry.id or "")
    if id == "adsr" then
      if paletteAvailable and getActiveRackNodeById(ctx, "adsr") == nil then
        return "Restore ADSR"
      end
      return paletteAvailable and "" or "No free ADSR slots"
    elseif id == "rack_oscillator" then
      return paletteAvailable and "" or "No free Osc slots"
    elseif id == "rack_sample" then
      return paletteAvailable and "" or "No free Sample slots"
    elseif id == "arp" then
      return paletteAvailable and "" or "No free Arp slots"
    elseif id == "transpose" then
      return paletteAvailable and "" or "No free Transpose slots"
    elseif id == "velocity_mapper" then
      return paletteAvailable and "" or "No free Velocity slots"
    elseif id == "scale_quantizer" then
      return paletteAvailable and "" or "No free Quantizer slots"
    elseif id == "note_filter" then
      return paletteAvailable and "" or "No free Note Filter slots"
    elseif id == "attenuverter_bias" then
      return paletteAvailable and "" or "No free ATV / Bias slots"
    elseif id == "lfo" then
      return paletteAvailable and "" or "No free LFO slots"
    elseif id == "slew" then
      return paletteAvailable and "" or "No free Slew slots"
    elseif id == "sample_hold" then
      return paletteAvailable and "" or "No free Sample Hold slots"
    elseif id == "compare" then
      return paletteAvailable and "" or "No free Compare slots"
    elseif id == "cv_mix" then
      return paletteAvailable and "" or "No free CV Mix slots"
    elseif id == "filter" then
      local missingCanonicalFilter = M._nextAvailableCanonicalFilterNodeId(ctx)
      if paletteAvailable and missingCanonicalFilter == "filter" then
        return "Restore Filter"
      end
      return paletteAvailable and "" or "No free Filter slots"
    elseif id == "eq" then
      return paletteAvailable and "" or "No free EQ slots"
    elseif id == "fx" then
      local missingCanonicalFx = M._nextAvailableCanonicalFxNodeId(ctx)
      if paletteAvailable and missingCanonicalFx == "fx1" then
        return "Restore FX1"
      elseif paletteAvailable and missingCanonicalFx == "fx2" then
        return "Restore FX2"
      end
      return paletteAvailable and "" or "No free FX slots"
    elseif id == "range_mapper" then
      return paletteAvailable and "" or "No free Range slots"
    end
    return paletteAvailable and "" or "Unavailable"
  end

  local function syncButtonLabel(widget, text)
    if widget and widget.setLabel then
      widget:setLabel(text)
    elseif widget and widget.setText then
      widget:setText(text)
    end
  end

  local function styleNavButton(widget, selected)
    if widget and widget.setStyle then
      widget:setStyle({
        bg = selected and 0xff16233a or 0x00000000,
        hoverBg = 0xff16233a,
        colour = selected and 0xffffffff or 0xff94a3b8,
        radius = 0,
        fontSize = 9,
      })
    end
  end

  local selectedEntry = M._ensurePaletteSelection(ctx)
  if ctx._suppressPaletteAutoScroll ~= true then
    M._ensureSelectedPaletteScrollVisible(ctx)
  end
  local m = M._paletteCardMetrics()
  local scrollOffset = M._clampPaletteScrollOffset(ctx)
  local viewportW = M._paletteViewportWidth(ctx)
  local viewportH = M._paletteViewportHeight(ctx)
  local columns = M._paletteGridColumnCount(ctx)
  local visibleFirst = 1
  local visibleLast = 0

  local paletteStripRow = _getScopedWidget(ctx, ".paletteStripRow")
  local paletteStripContent = _getScopedWidget(ctx, ".paletteStripContent")
  if paletteStripContent then
    changed = _setWidgetBounds(paletteStripContent, 0, 0, viewportW, viewportH) or changed
    if paletteStripContent.node and paletteStripContent.node.setClipRect then
      paletteStripContent.node:setClipRect(0, 0, viewportW, viewportH)
    end
  end
  if paletteStripRow then
    changed = _setWidgetBounds(paletteStripRow, 0, 0, viewportW, viewportH) or changed
    if paletteStripRow.node and paletteStripRow.node.setClipRect then
      paletteStripRow.node:setClipRect(0, 0, viewportW, viewportH)
    end
  end

  for i = 1, #M._PALETTE_ENTRIES do
    local entry = M._PALETTE_ENTRIES[i]
    local filteredEntries = M._getFilteredPaletteEntries(ctx)
    local filteredIdx = nil
    for fi = 1, #filteredEntries do
      if filteredEntries[fi] == entry then
        filteredIdx = fi
        break
      end
    end
    local paletteCard = _getScopedWidget(ctx, "." .. tostring(entry.cardId or ""))
    local paletteHint = _getScopedWidget(ctx, "." .. tostring(entry.hintId or ""))
    local palettePorts = _getScopedWidget(ctx, "." .. tostring(entry.portsId or ""))
    local paletteAccent = _getScopedWidget(ctx, "." .. tostring(entry.accentId or ""))
    local paletteAvailable = M._canSpawnPaletteEntry(ctx, entry)
    local selected = selectedEntry and tostring(selectedEntry.id or "") == tostring(entry.id or "")
    local statusText = paletteStatusText(entry, paletteAvailable)
    local row = filteredIdx and math.floor((filteredIdx - 1) / columns) or 0
    local col = filteredIdx and ((filteredIdx - 1) % columns) or 0
    local cardX = m.pad + (col * (m.w + m.gap))
    local cardY = m.pad + (row * (m.h + m.rowGap)) - scrollOffset
    local pageVisible = filteredIdx ~= nil and (cardX + m.w) >= 0 and cardX <= viewportW and (cardY + m.h) >= 0 and cardY <= viewportH
    if pageVisible and filteredIdx then
      if visibleLast == 0 then
        visibleFirst = filteredIdx
      end
      visibleLast = filteredIdx
    end
    if paletteCard and paletteCard.setStyle then
      paletteCard:setStyle({
        bg = selected and 0xff16233a or 0xff121a2f,
        border = selected and 0xff38bdf8 or (paletteAvailable and 0xff1f2b4d or 0xff1f2937),
        borderWidth = selected and 2 or 1,
        radius = 0,
        opacity = paletteAvailable and 1.0 or 0.45,
      })
    end
    if paletteAccent and paletteAccent.setStyle then
      local accent = tonumber(entry.accentColor) or 0xff64748b
      paletteAccent:setStyle({ bg = accent, radius = 0, opacity = paletteAvailable and 1.0 or 0.4 })
    end
    if paletteHint then
      _syncText(paletteHint, ellipsize(statusText, 18))
      _syncColour(paletteHint, statusText ~= "" and 0xff64748b or 0x00000000)
      if paletteHint.setVisible then
        paletteHint:setVisible(pageVisible and statusText ~= "")
      end
    end
    if palettePorts then
      _syncText(palettePorts, ellipsize(tostring(entry.portSummary or entry.ports or ""), 18))
      _syncColour(palettePorts, selected and 0xffe2e8f0 or 0xff94a3b8)
    end
    if paletteCard then
      if pageVisible and filteredIdx then
        changed = _setWidgetBounds(paletteCard, math.floor(cardX), math.floor(cardY), m.w, m.h) or changed
        if paletteCard.setVisible then
          paletteCard:setVisible(true)
        end
      else
        if paletteCard.setVisible then
          paletteCard:setVisible(false)
        end
      end
    end
  end

  local function styleTagButton(widget, active)
    if widget then
      if widget.setBg then
        widget:setBg(active and 0xff334155 or 0x00000000)
      end
      if widget.setTextColour then
        widget:setTextColour(active and 0xfff1f5f9 or 0xff94a3b8)
      end
    end
  end

  local showAll = ctx._paletteFilterTagAll ~= false
  local tags = ctx._paletteFilterTags or {}
  ctx._scopedWidgetCache = nil
  local tagAll = _getScopedWidget(ctx, ".utilityTagAll")
  local tagVoice = _getScopedWidget(ctx, ".utilityTagVoice")
  local tagAudio = _getScopedWidget(ctx, ".utilityTagAudio")
  local tagFx = _getScopedWidget(ctx, ".utilityTagFx")
  local tagMod = _getScopedWidget(ctx, ".utilityTagMod")
  styleTagButton(tagAll, showAll)
  styleTagButton(tagVoice, not showAll and tags.voice == true)
  styleTagButton(tagAudio, not showAll and tags.audio == true)
  styleTagButton(tagFx, not showAll and tags.fx == true)
  styleTagButton(tagMod, not showAll and tags.mod == true)

  local searchPanel = _getScopedWidget(ctx, ".utilitySearchPanel")
  local searchText = _getScopedWidget(ctx, ".utilitySearchText")
  local searchFocused = ctx._paletteSearchFocused == true
  local searchValue = tostring(ctx._paletteSearchText or "")
  if searchPanel and searchPanel.setStyle then
    searchPanel:setStyle({ bg = searchFocused and 0xff1e293b or 0xff0f172a })
  end
  if searchText then
    if searchValue ~= "" then
      _syncText(searchText, searchValue)
      _syncColour(searchText, 0xffe2e8f0)
    else
      _syncText(searchText, searchFocused and "Type to filter..." or "Search modules...")
      _syncColour(searchText, 0xff64748b)
    end
  end

  local pageLabel = _getScopedWidget(ctx, ".palettePageLabel")
  local pagePrev = _getScopedWidget(ctx, ".palettePagePrev")
  local pageNext = _getScopedWidget(ctx, ".palettePageNext")
  local topBarSelected = _getScopedWidget(ctx, ".utilityTopBarSelected")
  local paletteScrollTrack = _getScopedWidget(ctx, ".paletteScrollTrack")
  local paletteScrollThumb = _getScopedWidget(ctx, ".paletteScrollThumb")
  local maxOffset = M._paletteMaxScrollOffset(ctx)
  if visibleLast == 0 then
    visibleFirst = 0
  end
  if pageLabel then
    local filteredEntries = M._getFilteredPaletteEntries(ctx)
    _syncText(pageLabel, string.format("%d-%d/%d", visibleFirst, visibleLast, #filteredEntries))
  end
  if pagePrev and pagePrev.setStyle then
    pagePrev:setStyle({
      bg = scrollOffset > 0 and 0xff0d1420 or 0xff111827,
      hoverBg = scrollOffset > 0 and 0xff16233a or 0xff111827,
      colour = scrollOffset > 0 and 0xffcbd5e1 or 0xff475569,
      border = 0xff1f2b4d,
      borderWidth = 1,
      radius = 0,
      fontSize = 9,
    })
  end
  if pageNext and pageNext.setStyle then
    pageNext:setStyle({
      bg = scrollOffset < maxOffset and 0xff0d1420 or 0xff111827,
      hoverBg = scrollOffset < maxOffset and 0xff16233a or 0xff111827,
      colour = scrollOffset < maxOffset and 0xffcbd5e1 or 0xff475569,
      border = 0xff1f2b4d,
      borderWidth = 1,
      radius = 0,
      fontSize = 9,
    })
  end
  if topBarSelected and selectedEntry then
    _syncText(topBarSelected, ellipsize(tostring(selectedEntry.displayName or selectedEntry.id or ""), 20))
  end

  if paletteScrollTrack and paletteScrollThumb then
    local trackBounds = _getWidgetBounds(paletteScrollTrack)
    local trackH = math.max(8, math.floor(tonumber(trackBounds and trackBounds.h) or 0))
    local contentH = M._paletteContentHeight(ctx)
    local viewport = math.max(1, viewportH)
    local thumbH = math.max(18, math.floor((viewport / math.max(viewport, contentH)) * trackH))
    local thumbTravel = math.max(0, trackH - thumbH)
    local scrollT = (maxOffset > 0) and ((tonumber(scrollOffset) or 0) / maxOffset) or 0
    changed = _setWidgetBounds(paletteScrollThumb, 0, math.floor(thumbTravel * scrollT), 4, thumbH) or changed
    if paletteScrollTrack.setVisible then
      paletteScrollTrack:setVisible(maxOffset > 0)
    end
  end

  local detailTitle = _getScopedWidget(ctx, ".utilityDetailTitle")
  local detailSubtitle = _getScopedWidget(ctx, ".utilityDetailSubtitle")
  local detailPorts = _getScopedWidget(ctx, ".utilityDetailPorts")
  local detailStatus = _getScopedWidget(ctx, ".utilityDetailStatus")
  local detailAccent = _getScopedWidget(ctx, ".utilityDetailAccent")

  if selectedEntry then
    local paletteAvailable = M._canSpawnPaletteEntry(ctx, selectedEntry)
    local statusText = paletteStatusText(selectedEntry, paletteAvailable)
    if detailTitle then
      _syncText(detailTitle, ellipsize(tostring(selectedEntry.displayName or selectedEntry.id or "Module"), 16))
    end
    if detailSubtitle then
      _syncText(detailSubtitle, tostring(selectedEntry.description or ""))
    end
    if detailPorts then
      _syncText(detailPorts, ellipsize(tostring(selectedEntry.portSummary or ""), 22))
    end
    if detailStatus then
      _syncText(detailStatus, statusText)
      _syncColour(detailStatus, paletteAvailable and 0xff38bdf8 or 0xfff87171)
      if detailStatus.setVisible then
        detailStatus:setVisible(statusText ~= "")
      end
    end
    if detailAccent and detailAccent.setStyle then
      detailAccent:setStyle({ bg = tonumber(selectedEntry.accentColor) or 0xff38bdf8, radius = 0 })
    end
  end

  return changed
end

return M

local M = {}

M.MAX_LAYERS = 4
M.kSegmentBars = { 0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0 }
M.kSegmentLabels = { "1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16" }
M.kFxEffects = {
  { id = "bypass", label = "Bypass" },
  { id = "chorus", label = "Chorus" },
  { id = "phaser", label = "Phaser" },
  { id = "bitcrusher", label = "Bitcrusher" },
  { id = "waveshaper", label = "Waveshaper" },
  { id = "filter", label = "Filter" },
  { id = "svf", label = "SVF Filter" },
  { id = "reverb", label = "Reverb" },
  { id = "shimmer", label = "Shimmer" },
  { id = "stereodelay", label = "Stereo Delay" },
  { id = "reversedelay", label = "Reverse Delay" },
  { id = "multitap", label = "Multitap" },
  { id = "pitchshift", label = "Pitch Shift" },
  { id = "granulator", label = "Granulator" },
  { id = "ringmod", label = "Ring Mod" },
  { id = "formant", label = "Formant" },
  { id = "eq", label = "EQ" },
  { id = "compressor", label = "Compressor" },
  { id = "limiter", label = "Limiter" },
  { id = "transient", label = "Transient" },
  { id = "widener", label = "Widener" },
}
M.kFxLabels = {}
for i = 1, #M.kFxEffects do
  M.kFxLabels[i] = M.kFxEffects[i].label
end

local selections = {
  vocal = "bypass",
  layers = { "bypass", "bypass", "bypass", "bypass" },
}

function M.clamp(v, lo, hi)
  local n = tonumber(v) or 0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.setParamSafe(path, value)
  if type(path) ~= "string" or path == "" then return false end
  if type(setParam) == "function" then
    local ok, handled = pcall(setParam, path, value)
    return ok and handled == true
  end
  return false
end

function M.getParamSafe(path, fallback)
  if type(path) ~= "string" or path == "" then return fallback end
  if type(getParam) == "function" then
    local ok, value = pcall(getParam, path)
    if ok and value ~= nil then return value end
  end
  return fallback
end

function M.commandSet(path, value)
  if command then
    command("SET", path, tostring(value))
  end
end

function M.commandTrigger(path)
  if command then
    command("TRIGGER", path)
  end
end

function M.layerPath(layerIndex, suffix)
  return string.format("/core/behavior/layer/%d/%s", layerIndex, suffix)
end

function M.sanitizeSpeed(value)
  local speed = math.abs(tonumber(value) or 1.0)
  if speed < 0.1 then speed = 0.1 end
  if speed > 4.0 then speed = 4.0 end
  return speed
end

function M.wrap01(v)
  while v < 0.0 do v = v + 1.0 end
  while v >= 1.0 do v = v - 1.0 end
  return v
end

function M.readParam(params, path, fallback)
  if type(params) ~= "table" then
    return fallback
  end
  local value = params[path]
  if value == nil then
    return fallback
  end
  return value
end

function M.readBoolParam(params, path, fallback)
  local raw = M.readParam(params, path, fallback and 1 or 0)
  if raw == nil then
    return fallback
  end
  return raw == true or raw == 1
end

function M.normalizeState(state)
  if type(state) ~= "table" then
    return {}
  end

  local params = state.params or {}
  local voices = state.voices or {}
  local normalized = {
    params = params,
    voices = voices,
    tempo = M.readParam(params, "/core/behavior/tempo", 120),
    targetBPM = M.readParam(params, "/core/behavior/targetbpm", 120),
    samplesPerBar = M.readParam(params, "/core/behavior/samplesPerBar", 88200),
    sampleRate = M.readParam(params, "/core/behavior/sampleRate", 44100),
    captureSize = M.readParam(params, "/core/behavior/captureSize", 0),
    isRecording = M.readBoolParam(params, "/core/behavior/recording", false),
    overdubEnabled = M.readBoolParam(params, "/core/behavior/overdub", true),
    recordMode = M.readParam(params, "/core/behavior/mode", "firstLoop"),
    activeLayer = M.readParam(params, "/core/behavior/activeLayer", M.readParam(params, "/core/behavior/layer", 0)),
    forwardArmed = M.readBoolParam(params, "/core/behavior/forwardArmed", false),
    forwardBars = M.readParam(params, "/core/behavior/forwardBars", 0),
    layers = {},
  }

  normalized.activeLayer = tonumber(normalized.activeLayer) or 0

  for i, voice in ipairs(voices) do
    if type(voice) == "table" then
      normalized.layers[i] = {
        index = voice.id or (i - 1),
        length = voice.length or 0,
        position = voice.position or 0,
        speed = voice.speed or 1,
        reversed = voice.reversed or false,
        volume = voice.volume or 1,
        state = voice.state or "empty",
        muted = voice.muted or false,
        bars = voice.bars or 0,
        params = voice.params or {},
      }
    end
  end

  if #normalized.layers == 0 then
    for layerIdx = 0, M.MAX_LAYERS - 1 do
      local volume = tonumber(M.readParam(params, M.layerPath(layerIdx, "volume"), 1.0)) or 1.0
      local muted = M.readBoolParam(params, M.layerPath(layerIdx, "mute"), false)
      local bars = tonumber(M.readParam(params, M.layerPath(layerIdx, "bars"), 0)) or 0
      local length = tonumber(M.readParam(params, M.layerPath(layerIdx, "length"), 0)) or 0
      local posNorm = tonumber(M.readParam(params, M.layerPath(layerIdx, "seek"), 0)) or 0
      local stateName = M.readParam(params, M.layerPath(layerIdx, "state"), nil)
      if type(stateName) ~= "string" or stateName == "" then
        if muted then
          stateName = "muted"
        elseif normalized.isRecording and normalized.activeLayer == layerIdx then
          stateName = "recording"
        else
          stateName = "stopped"
        end
      end

      normalized.layers[layerIdx + 1] = {
        index = layerIdx,
        length = length,
        position = math.floor(posNorm * math.max(1, length)),
        speed = tonumber(M.readParam(params, M.layerPath(layerIdx, "speed"), 1.0)) or 1.0,
        reversed = M.readBoolParam(params, M.layerPath(layerIdx, "reverse"), false),
        volume = volume,
        state = stateName,
        muted = muted,
        bars = bars,
        params = { mute = muted and 1 or 0 },
      }
    end
  end

  return normalized
end

function M.layerStateColour(state)
  local colours = {
    empty = 0xff64748b,
    playing = 0xff34d399,
    recording = 0xffef4444,
    overdubbing = 0xfff59e0b,
    muted = 0xff94a3b8,
    stopped = 0xfffde047,
    paused = 0xffa78bfa,
  }
  return colours[state] or 0xffffffff
end

function M.layerStateName(state)
  local names = {
    empty = "Empty",
    playing = "Playing",
    recording = "Recording",
    overdubbing = "Overdub",
    muted = "Muted",
    stopped = "Stopped",
    paused = "Paused",
  }
  return names[state] or ""
end

function M.segmentRangeForBars(bars)
  local prev = 0
  for i, v in ipairs(M.kSegmentBars) do
    if math.abs(v - bars) < 0.0001 then
      prev = (i > 1) and M.kSegmentBars[i - 1] or 0
      return prev, v, M.kSegmentLabels[i] or tostring(v)
    end
  end
  return 0, bars, tostring(bars)
end

function M.formatBars(bars)
  if bars == nil or bars == 0 then
    return ""
  end
  if bars < 1 then
    if math.abs(bars - 0.0625) < 0.001 then return "1/16 bar" end
    if math.abs(bars - 0.125) < 0.001 then return "1/8 bar" end
    if math.abs(bars - 0.25) < 0.001 then return "1/4 bar" end
    if math.abs(bars - 0.5) < 0.001 then return "1/2 bar" end
    return string.format("%.2f bars", bars)
  end
  local rounded = math.floor(bars + 0.5)
  if rounded == 1 then
    return "1 bar"
  end
  return string.format("%d bars", rounded)
end

function M.effectIdFromIndex(idx)
  idx = math.max(1, math.min(#M.kFxEffects, tonumber(idx) or 1))
  return M.kFxEffects[idx].id
end

function M.effectIndexFromId(effectId)
  for i = 1, #M.kFxEffects do
    if M.kFxEffects[i].id == effectId then
      return i
    end
  end
  return 1
end

function M.effectLabelById(effectId)
  return M.kFxEffects[M.effectIndexFromId(effectId)].label
end

function M.vocalFxBasePath()
  return "/core/super/vocal/slot"
end

function M.layerFxBasePath(layerIndex)
  local idx = math.max(0, math.min(M.MAX_LAYERS - 1, tonumber(layerIndex) or 0))
  return string.format("/core/super/layer/%d/fx", idx)
end

function M.createMapping(path, label, rangeMin, rangeMax, typeTag)
  return {
    path = path,
    label = label,
    rangeMin = tonumber(rangeMin) or 0.0,
    rangeMax = tonumber(rangeMax) or 1.0,
    type = typeTag or "f",
  }
end

function M.mappingRange(mapping)
  local lo = tonumber(mapping and mapping.rangeMin) or 0.0
  local hi = tonumber(mapping and mapping.rangeMax) or 1.0
  if hi < lo then lo, hi = hi, lo end
  if hi == lo then hi = lo + 1.0 end
  return lo, hi
end

function M.mappingToNormalized(mapping, actual, fallbackNorm)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then
    return fallbackNorm or 0.5
  end
  local lo, hi = M.mappingRange(mapping)
  local val = tonumber(actual) or fallbackNorm or 0.0
  return M.clamp((val - lo) / (hi - lo), 0.0, 1.0)
end

function M.normalizedToMapping(mapping, norm)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then
    return 0.0
  end
  local lo, hi = M.mappingRange(mapping)
  return lo + M.clamp(norm, 0.0, 1.0) * (hi - lo)
end

function M.knobStepForMapping(mapping)
  if mapping == nil then return 0.01 end
  if type(mapping.type) == "string" and mapping.type:find("i", 1, true) then
    return 1.0
  end
  local lo, hi = M.mappingRange(mapping)
  return math.max(0.001, (hi - lo) / 200.0)
end

function M.applyMappedNormalized(mapping, norm)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then return false end
  return M.setParamSafe(mapping.path, M.normalizedToMapping(mapping, norm))
end

function M.applyMappedActual(mapping, value)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then return false end
  return M.setParamSafe(mapping.path, value)
end

function M.readMappedActual(mapping, fallback)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then return fallback end
  return tonumber(M.getParamSafe(mapping.path, fallback)) or fallback
end

function M.readMappedNormalized(mapping, fallbackNorm)
  if mapping == nil or type(mapping.path) ~= "string" or mapping.path == "" then return fallbackNorm or 0.5 end
  return M.mappingToNormalized(mapping, M.getParamSafe(mapping.path, M.normalizedToMapping(mapping, fallbackNorm or 0.5)), fallbackNorm or 0.5)
end

function M.updateKnobBinding(knob, mapping, fallbackLabel)
  if not knob then return end
  local lo, hi = M.mappingRange(mapping)
  knob._min = lo
  knob._max = hi
  knob._step = M.knobStepForMapping(mapping)
  knob._label = (mapping and mapping.label) or fallbackLabel or knob._label or ""
end

local function shortEndpointLabel(path, prefix)
  if type(path) ~= "string" then return "(unmapped)" end
  local p = path
  if type(prefix) == "string" and prefix ~= "" and p:sub(1, #prefix) == prefix then
    p = p:sub(#prefix + 1)
  end
  p = p:gsub("^/", "")
  p = p:gsub("_", " ")
  return p
end

function M.buildScopedCatalog(basePath, effectId)
  local out = { M.createMapping(nil, "(unmapped)", 0.0, 1.0, "f") }
  local prefix = tostring(basePath or "") .. "/" .. tostring(effectId or "") .. "/"
  if type(listEndpoints) == "function" and effectId and effectId ~= "bypass" then
    local ok, endpoints = pcall(listEndpoints, prefix, true, true)
    if ok and type(endpoints) == "table" and #endpoints > 0 then
      for i = 1, #endpoints do
        local ep = endpoints[i]
        if type(ep) == "table" and type(ep.path) == "string" and ep.path ~= "" then
          out[#out + 1] = M.createMapping(
            ep.path,
            shortEndpointLabel(ep.path, prefix),
            ep.rangeMin,
            ep.rangeMax,
            ep.type
          )
        end
      end
    end
  end
  return out
end

function M.createMappingScope(basePath)
  return {
    basePath = basePath,
    mappings = { x = nil, y = nil, k1 = nil, k2 = nil, mix = nil },
    catalog = { M.createMapping(nil, "(unmapped)", 0.0, 1.0, "f") },
    labels = { "(unmapped)" },
    effectId = nil,
  }
end

function M.scopeCatalogIndex(scope, path)
  local catalog = scope and scope.catalog or {}
  for i = 1, #catalog do
    if catalog[i].path == path then return i end
  end
  return 1
end

function M.assignScopeMappingByIndex(scope, key, idx)
  local catalog = scope and scope.catalog or {}
  local item = catalog[idx] or catalog[1]
  scope.mappings[key] = item and item.path and M.createMapping(item.path, item.label, item.rangeMin, item.rangeMax, item.type) or nil
end

local function preferredIndex(scope, patterns, used)
  local catalog = scope and scope.catalog or {}
  for _, pattern in ipairs(patterns or {}) do
    for i = 2, #catalog do
      if not used[i] then
        local label = string.lower(tostring(catalog[i].label or ""))
        local path = string.lower(tostring(catalog[i].path or ""))
        if label:find(pattern, 1, true) or path:find(pattern, 1, true) then
          used[i] = true
          return i
        end
      end
    end
  end
  for i = 2, #catalog do
    if not used[i] then
      used[i] = true
      return i
    end
  end
  return 1
end

function M.assignDefaultScopeMappings(scope)
  local used = {}
  local xIdx = preferredIndex(scope, { "cutoff", "rate", "time", "timel", "pitch", "size", "freq", "grain", "width", "threshold" }, used)
  local yIdx = preferredIndex(scope, { "resonance", "feedback", "timer", "density", "damping", "depth", "release", "window", "shift", "high" }, used)
  local k1Idx = preferredIndex(scope, { "drive", "attack", "spread", "makeup", "vowel", "tapcount", "voices", "bits", "room", "low" }, used)
  local k2Idx = preferredIndex(scope, { "mix", "wet", "output", "soft", "freeze", "mode", "ratio", "mono", "feedback" }, used)
  local mixIdx = preferredIndex(scope, { "mix", "wet", "output", "dry", "level", "width" }, used)
  M.assignScopeMappingByIndex(scope, "x", xIdx)
  M.assignScopeMappingByIndex(scope, "y", yIdx)
  M.assignScopeMappingByIndex(scope, "k1", k1Idx)
  M.assignScopeMappingByIndex(scope, "k2", k2Idx)
  M.assignScopeMappingByIndex(scope, "mix", mixIdx)
end

function M.ensureScopeCatalog(scope, effectId)
  if not scope then return end
  if scope.effectId == effectId and scope.catalog and #scope.catalog > 1 then
    return
  end
  scope.catalog = M.buildScopedCatalog(scope.basePath, effectId)
  scope.labels = {}
  for i = 1, #scope.catalog do
    scope.labels[i] = scope.catalog[i].label
  end
  local previous = scope.mappings or {}
  scope.effectId = effectId
  scope.mappings = { x = nil, y = nil, k1 = nil, k2 = nil, mix = nil }
  local validCount = 0
  for _, key in ipairs({ "x", "y", "k1", "k2", "mix" }) do
    local old = previous[key]
    if old and M.scopeCatalogIndex(scope, old.path) ~= 1 then
      M.assignScopeMappingByIndex(scope, key, M.scopeCatalogIndex(scope, old.path))
      validCount = validCount + 1
    end
  end
  if validCount == 0 then
    M.assignDefaultScopeMappings(scope)
  end
end

function M.syncScopeDropdown(dropdown, scope, key)
  if not dropdown or not scope then return end
  local labels = scope.labels or { "(unmapped)" }
  if dropdown._lastScopeLabels ~= labels then
    dropdown._lastScopeLabels = labels
    dropdown:setOptions(labels)
  end
  local mapping = scope.mappings[key]
  local idx = M.scopeCatalogIndex(scope, mapping and mapping.path or nil)
  if dropdown._lastScopeSelected ~= idx then
    dropdown._lastScopeSelected = idx
    dropdown:setSelected(idx)
  end
end

function M.syncMappedKnob(knob, mapping, fallbackLabel, fallbackValue)
  if not knob then return end
  M.updateKnobBinding(knob, mapping, fallbackLabel)
  if not knob._dragging then
    knob:setValue(M.readMappedActual(mapping, fallbackValue))
  end
end

function M.syncMappedXY(widget, mappingX, mappingY, fallbackX, fallbackY)
  if not widget then return end
  widget:setValues(
    M.readMappedNormalized(mappingX, fallbackX),
    M.readMappedNormalized(mappingY, fallbackY)
  )
end

function M.getSelections()
  return selections
end

function M.setVocalEffectByIndex(idx)
  selections.vocal = M.effectIdFromIndex(idx)
  if type(_G.__looperTabsEnsureSuperSlot) == "function" then
    _G.__looperTabsEnsureSuperSlot(true)
  end
  return selections.vocal
end

function M.setLayerEffectByIndex(layerIndex, idx)
  local slot = math.max(1, math.min(M.MAX_LAYERS, (tonumber(layerIndex) or 0) + 1))
  selections.layers[slot] = M.effectIdFromIndex(idx)
  if type(_G.__looperTabsEnsureSuperSlot) == "function" then
    _G.__looperTabsEnsureSuperSlot(true)
  end
  return selections.layers[slot]
end

function M.mappingOptionLabels()
  return {
    "Unmapped",
    "Param X",
    "Param Y",
    "Macro 1",
    "Macro 2",
    "Mix",
  }
end

local function findById(items, id)
  if type(items) ~= "table" or type(id) ~= "string" or id == "" then
    return nil
  end
  for _, item in ipairs(items) do
    if type(item) == "table" and item.id == id then
      return item
    end
  end
  return nil
end

function M.getChildSpec(ctx, id)
  local spec = ctx and ctx.spec or nil
  if type(spec) ~= "table" then
    return nil
  end
  return findById(spec.children, id)
end

function M.getComponentSpec(ctx, id)
  local spec = ctx and ctx.spec or nil
  if type(spec) ~= "table" then
    return nil
  end
  return findById(spec.components, id)
end

function M.getDesignSize(ctx, fallbackW, fallbackH)
  local spec = ctx and ctx.spec or nil
  local designW = type(spec) == "table" and tonumber(spec.w) or nil
  local designH = type(spec) == "table" and tonumber(spec.h) or nil
  if not designW or designW <= 0 then designW = tonumber(fallbackW) or 1 end
  if not designH or designH <= 0 then designH = tonumber(fallbackH) or 1 end
  return designW, designH
end

function M.applySpecRect(widget, nodeSpec, parentW, parentH, designW, designH)
  if not widget or not nodeSpec or not widget.setBounds then
    return
  end
  designW = tonumber(designW) or tonumber(parentW) or 1
  designH = tonumber(designH) or tonumber(parentH) or 1
  parentW = tonumber(parentW) or designW
  parentH = tonumber(parentH) or designH

  local sx = parentW / math.max(1, designW)
  local sy = parentH / math.max(1, designH)
  local x = math.floor(((tonumber(nodeSpec.x) or 0) * sx) + 0.5)
  local y = math.floor(((tonumber(nodeSpec.y) or 0) * sy) + 0.5)
  local w = math.floor(((tonumber(nodeSpec.w) or 0) * sx) + 0.5)
  local h = math.floor(((tonumber(nodeSpec.h) or 0) * sy) + 0.5)
  widget:setBounds(x, y, w, h)
end

function M.setDropdownAbsolutePos(rootWidget, widget)
  if not (rootWidget and rootWidget.node and widget and widget.node and widget.setAbsolutePos and rootWidget.node.getBounds and widget.node.getBounds) then
    return
  end
  local rx, ry = rootWidget.node:getBounds()
  local wx, wy = widget.node:getBounds()
  widget:setAbsolutePos(rx + wx, ry + wy)
end

return M

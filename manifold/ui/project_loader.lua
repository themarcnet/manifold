local W = require("ui_widgets")
local LayoutEngine = require("layout_engine")

local M = {}

local SUPPORTED_WIDGETS = {
  Panel = W.Panel,
  Button = W.Button,
  Label = W.Label,
  Slider = W.Slider,
  VSlider = W.VSlider,
  Dropdown = W.Dropdown,
  Toggle = W.Toggle,
  NumberBox = W.NumberBox,
  Knob = W.Knob,
  WaveformView = W.WaveformView,
  Meter = W.Meter,
  SegmentedControl = W.SegmentedControl,
  Radio = W.Radio,
  DonutWidget = W.DonutWidget,
  XYPadWidget = W.XYPadWidget,
  CurveWidget = W.CurveWidget,
  TabHost = W.TabHost,
  TabPage = W.TabPage,
}

local FONT_STYLE_MAP = {
  plain = FontStyle.plain,
  bold = FontStyle.bold,
  italic = FontStyle.italic,
}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[deepCopy(k)] = deepCopy(v)
  end
  return out
end

local function mergeInto(dst, src)
  if type(src) ~= "table" then
    return dst
  end
  for k, v in pairs(src) do
    dst[k] = v
  end
  return dst
end

local function mergeDeepInto(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then
    return dst
  end
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = {}
      end
      mergeDeepInto(dst[k], v)
    else
      dst[k] = deepCopy(v)
    end
  end
  return dst
end

local function normalizeFontStyle(config)
  if type(config.fontStyle) == "string" then
    config.fontStyle = FONT_STYLE_MAP[string.lower(config.fontStyle)] or FontStyle.plain
  end
end

local function flattenSpecConfig(spec, runtime, extraProps)
  local config = {}
  mergeInto(config, spec.style)
  mergeInto(config, spec.props)
  mergeInto(config, extraProps)
  normalizeFontStyle(config)

  if spec.type == "Dropdown" and config.rootNode == nil then
    config.rootNode = runtime.rootNode
  end

  return config
end

local function floorInt(v)
  return math.floor((tonumber(v) or 0) + 0.5)
end

local function numberOrNil(v)
  if v == nil then
    return nil
  end
  return tonumber(v)
end

local function lowerString(v)
  return string.lower(tostring(v or ""))
end

local function clampNumber(v, minV, maxV)
  local n = tonumber(v) or 0
  if minV ~= nil and n < minV then
    n = minV
  end
  if maxV ~= nil and n > maxV then
    n = maxV
  end
  return n
end

local function getBounds(spec, fallback)
  return floorInt(spec.x or (fallback and fallback.x) or 0),
         floorInt(spec.y or (fallback and fallback.y) or 0),
         floorInt(spec.w or (fallback and fallback.w) or 0),
         floorInt(spec.h or (fallback and fallback.h) or 0)
end

local function mergeLayout(baseLayout, overrideLayout)
  local layout = deepCopy(baseLayout or {})
  mergeInto(layout, overrideLayout or {})
  if next(layout) == nil then
    return nil
  end
  return layout
end

local function mergeNodeTable(baseValue, overrideValue)
  local merged = deepCopy(baseValue or {})
  mergeInto(merged, overrideValue or {})
  if next(merged) == nil then
    return nil
  end
  return merged
end

local function resolveAbsoluteBounds(spec, layout, fallback)
  local x = numberOrNil(layout.x) or numberOrNil(layout.left) or spec.x or (fallback and fallback.x) or 0
  local y = numberOrNil(layout.y) or numberOrNil(layout.top) or spec.y or (fallback and fallback.y) or 0
  local w = numberOrNil(layout.w) or numberOrNil(layout.width) or spec.w or (fallback and fallback.w) or 0
  local h = numberOrNil(layout.h) or numberOrNil(layout.height) or spec.h or (fallback and fallback.h) or 0
  return x, y, w, h
end

local function resolveRelativeBounds(spec, layout, parentW, parentH, fallback)
  local x = (numberOrNil(layout.x) or 0.0) * parentW
  local y = (numberOrNil(layout.y) or 0.0) * parentH
  local w = (numberOrNil(layout.w) or numberOrNil(layout.width) or 1.0) * parentW
  local h = (numberOrNil(layout.h) or numberOrNil(layout.height) or 1.0) * parentH

  if layout.left ~= nil and layout.right ~= nil then
    local left = numberOrNil(layout.left) or 0.0
    local right = numberOrNil(layout.right) or 0.0
    x = left * parentW
    w = parentW - (left + right) * parentW
  end
  if layout.top ~= nil and layout.bottom ~= nil then
    local top = numberOrNil(layout.top) or 0.0
    local bottom = numberOrNil(layout.bottom) or 0.0
    y = top * parentH
    h = parentH - (top + bottom) * parentH
  end

  if fallback then
    if layout.x == nil and layout.left == nil then x = fallback.x or x end
    if layout.y == nil and layout.top == nil then y = fallback.y or y end
  end

  return x, y, w, h
end

local function resolveHybridAxis(layout, parentSize, basePos, baseSize, startKey, endKey, sizeKey, altSizeKey)
  local startInset = numberOrNil(layout[startKey])
  local endInset = numberOrNil(layout[endKey])
  local size = numberOrNil(layout[sizeKey]) or numberOrNil(layout[altSizeKey]) or numberOrNil(baseSize) or 0
  local pos = numberOrNil(layout[startKey == "left" and "x" or "y"]) or numberOrNil(basePos) or 0

  if startInset ~= nil then
    pos = startInset
  end

  if startInset ~= nil and endInset ~= nil and layout[sizeKey] == nil and layout[altSizeKey] == nil then
    size = parentSize - startInset - endInset
  elseif startInset == nil and endInset ~= nil then
    pos = parentSize - endInset - size
  end

  return pos, size
end

local function applySizeClamp(layout, w, h)
  w = clampNumber(w,
    numberOrNil(layout.minW) or numberOrNil(layout.minWidth),
    numberOrNil(layout.maxW) or numberOrNil(layout.maxWidth))
  h = clampNumber(h,
    numberOrNil(layout.minH) or numberOrNil(layout.minHeight),
    numberOrNil(layout.maxH) or numberOrNil(layout.maxHeight))
  return w, h
end

local function resolveLayoutBounds(spec, parentW, parentH, fallback)
  local layout = spec.layout
  if type(layout) ~= "table" then
    return getBounds(spec, fallback)
  end

  local mode = lowerString(layout.mode or layout.sizing or layout.kind or "absolute")
  local x, y, w, h

  if mode == "relative" or mode == "fill" or mode == "responsive" then
    x, y, w, h = resolveRelativeBounds(spec, layout, parentW, parentH, fallback)
  elseif mode == "hybrid" or mode == "anchored" or mode == "inset" then
    x, w = resolveHybridAxis(layout, parentW, spec.x or (fallback and fallback.x), spec.w or (fallback and fallback.w), "left", "right", "width", "w")
    y, h = resolveHybridAxis(layout, parentH, spec.y or (fallback and fallback.y), spec.h or (fallback and fallback.h), "top", "bottom", "height", "h")
  elseif LayoutEngine.isManagedContainerLayoutMode(mode) then
    local usesInsets = layout.left ~= nil or layout.right ~= nil or layout.top ~= nil or layout.bottom ~= nil
    if usesInsets then
      x, w = resolveHybridAxis(layout, parentW, spec.x or (fallback and fallback.x), spec.w or (fallback and fallback.w), "left", "right", "width", "w")
      y, h = resolveHybridAxis(layout, parentH, spec.y or (fallback and fallback.y), spec.h or (fallback and fallback.h), "top", "bottom", "height", "h")
    else
      x, y, w, h = resolveAbsoluteBounds(spec, layout, fallback)
    end
  else
    x, y, w, h = resolveAbsoluteBounds(spec, layout, fallback)
  end

  w, h = applySizeClamp(layout, w, h)
  return floorInt(x), floorInt(y), floorInt(math.max(0, w)), floorInt(math.max(0, h))
end

local function validateValue(value, path, visited)
  local t = type(value)
  if t == "function" or t == "userdata" or t == "thread" then
    error("structured UI contains unsupported value at " .. path .. ": " .. t)
  end
  if t ~= "table" then
    return
  end

  if visited[value] then
    error("structured UI contains recursive table at " .. path)
  end
  visited[value] = true

  local mt = getmetatable(value)
  if mt ~= nil then
    error("structured UI table has metatable at " .. path)
  end

  for k, v in pairs(value) do
    if type(k) == "function" or type(k) == "userdata" or type(k) == "thread" then
      error("structured UI contains unsupported key type at " .. path)
    end
    validateValue(v, path .. "." .. tostring(k), visited)
  end
end

local function executeLuaFileReturningTable(absPath, label)
  local chunk, loadErr = loadfile(absPath)
  if not chunk then
    error((label or "lua table") .. " load failed: " .. tostring(loadErr))
  end

  local ok, result = pcall(chunk)
  if not ok then
    error((label or "lua table") .. " execution failed: " .. tostring(result))
  end
  if type(result) ~= "table" then
    error((label or "lua table") .. " must return a table")
  end

  return result
end

local function loadStructuredTable(absPath, label)
  local result = executeLuaFileReturningTable(absPath, label)
  validateValue(result, label or absPath, {})
  return result
end

local function loadBehaviorModule(absPath, label)
  return executeLuaFileReturningTable(absPath, label)
end

local function startsWith(text, prefix)
  return type(text) == "string" and text:sub(1, #prefix) == prefix
end

local function resolveAssetPath(runtime, ref)
  if type(ref) ~= "string" or ref == "" then
    error("missing asset ref")
  end

  if startsWith(ref, "/") then
    return ref
  end

  if startsWith(ref, "user:ui/") then
    return runtime.userScriptsRoot .. "/ui/" .. ref:sub(#"user:ui/" + 1)
  end
  if startsWith(ref, "user:dsp/") then
    return runtime.userScriptsRoot .. "/dsp/" .. ref:sub(#"user:dsp/" + 1)
  end
  if startsWith(ref, "system:ui/") then
    return runtime.systemUiRoot .. "/" .. ref:sub(#"system:ui/" + 1)
  end
  if startsWith(ref, "system:dsp/") then
    return runtime.systemDspRoot .. "/" .. ref:sub(#"system:dsp/" + 1)
  end

  return runtime.projectRoot .. "/" .. ref
end

local function splitPath(path)
  local parts = {}
  if type(path) ~= "string" or path == "" then
    return parts
  end
  for part in string.gmatch(path, "[^%.]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function getValueByPath(root, path)
  if type(root) ~= "table" then
    return nil
  end
  if type(path) ~= "string" or path == "" then
    return root
  end
  local current = root
  for _, part in ipairs(splitPath(path)) do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end
  return current
end

local function setValueByPath(root, path, value)
  if type(root) ~= "table" or type(path) ~= "string" or path == "" then
    return false
  end
  local parts = splitPath(path)
  if #parts == 0 then
    return false
  end
  local current = root
  for i = 1, #parts - 1 do
    local part = parts[i]
    if type(current[part]) ~= "table" then
      current[part] = {}
    end
    current = current[part]
  end
  current[parts[#parts]] = value
  return true
end

local function removeValueByPath(root, path)
  if type(root) ~= "table" or type(path) ~= "string" or path == "" then
    return false
  end
  local parts = splitPath(path)
  if #parts == 0 then
    return false
  end
  local current = root
  for i = 1, #parts - 1 do
    current = current[parts[i]]
    if type(current) ~= "table" then
      return false
    end
  end
  current[parts[#parts]] = nil
  return true
end

local function isArrayTable(value)
  if type(value) ~= "table" then
    return false, 0
  end
  local maxIndex = 0
  local count = 0
  for k, _ in pairs(value) do
    if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
      return false, 0
    end
    if k > maxIndex then
      maxIndex = k
    end
    count = count + 1
  end
  if count == 0 then
    return true, 0
  end
  if maxIndex ~= count then
    return false, 0
  end
  return true, count
end

local function escapeLuaString(text)
  return string.format("%q", tostring(text or ""))
end

local function pathStartsWith(text, prefix)
  return type(text) == "string" and type(prefix) == "string" and text:sub(1, #prefix) == prefix
end

local function pathRelativeToRoot(absPath, root)
  if type(absPath) ~= "string" or absPath == "" then
    return absPath or ""
  end
  if type(root) ~= "string" or root == "" then
    return absPath
  end
  local normalizedRoot = root
  if normalizedRoot:sub(-1) ~= "/" then
    normalizedRoot = normalizedRoot .. "/"
  end
  if pathStartsWith(absPath, normalizedRoot) then
    return absPath:sub(#normalizedRoot + 1)
  end
  return absPath
end

local NODE_KEY_ORDER = {
  "id", "type", "x", "y", "w", "h", "layout", "layoutChild", "shellLayout",
  "props", "style", "bind", "behavior", "children", "components", "ref",
}

local function orderedKeys(value)
  local used = {}
  local keys = {}
  for _, key in ipairs(NODE_KEY_ORDER) do
    if value[key] ~= nil then
      keys[#keys + 1] = key
      used[key] = true
    end
  end

  local rest = {}
  for k, _ in pairs(value) do
    if type(k) == "string" and not used[k] then
      rest[#rest + 1] = k
    end
  end
  table.sort(rest)
  for _, key in ipairs(rest) do
    keys[#keys + 1] = key
  end
  return keys
end

local function serializeLuaValue(value, indent)
  local t = type(value)
  indent = indent or ""

  if t == "nil" then
    return "nil"
  end
  if t == "number" or t == "boolean" then
    return tostring(value)
  end
  if t == "string" then
    return escapeLuaString(value)
  end
  if t ~= "table" then
    error("cannot serialize structured UI value of type: " .. t)
  end

  local isArray, count = isArrayTable(value)
  local nextIndent = indent .. "  "

  if isArray then
    if count == 0 then
      return "{}"
    end
    local out = {"{"}
    for i = 1, count do
      out[#out + 1] = nextIndent .. serializeLuaValue(value[i], nextIndent) .. ","
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out, "\n")
  end

  local keys = orderedKeys(value)
  if #keys == 0 then
    return "{}"
  end

  local out = {"{"}
  for _, key in ipairs(keys) do
    out[#out + 1] = nextIndent .. key .. " = " .. serializeLuaValue(value[key], nextIndent) .. ","
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end

local function serializeStructuredDocument(value)
  validateValue(value, "serializedDocument", {})
  return "return " .. serializeLuaValue(value, "") .. "\n"
end

local function buildBehaviorContext(runtime, opts)
  return {
    project = {
      root = runtime.projectRoot,
      manifest = runtime.manifestPath,
      uiRoot = runtime.uiRoot,
      userScriptsRoot = runtime.userScriptsRoot,
      systemUiRoot = runtime.systemUiRoot,
      systemDspRoot = runtime.systemDspRoot,
      displayName = runtime.displayName,
    },
    root = opts.rootWidget,
    widgets = opts.localWidgets,
    allWidgets = runtime.widgets,
    instanceId = opts.instanceId,
    instanceProps = opts.instanceProps or {},
    spec = opts.spec,
  }
end

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(opts)
  local self = setmetatable({}, Runtime)
  self.requestedPath = opts.requestedPath or ""
  self.projectRoot = opts.projectRoot or ""
  self.manifestPath = opts.manifestPath or ""
  self.uiRoot = opts.uiRoot or ""
  self.displayName = opts.displayName or "Project"
  self.userScriptsRoot = opts.userScriptsRoot or ""
  self.systemUiRoot = opts.systemUiRoot or ""
  self.systemDspRoot = opts.systemDspRoot or ""
  self.rootNode = nil
  self.rootWidget = nil
  self.sceneSpec = nil
  self.widgets = {}
  self.behaviors = {}
  self.layoutTree = nil
  self.documents = {}
  self.documentOrder = {}
  self.recordsBySourceKey = {}
  self.recordsBySourceLists = {}
  self.dependencyFiles = {}
  self.dependencyOrder = {}
  self.projectLocalModules = {}
  self.originalRequire = nil
  self.requireTrackingInstalled = false
  self.lastError = ""
  self.lastOperation = ""
  return self
end

function Runtime:isProjectLocalDependencyPath(absPath)
  if type(absPath) ~= "string" or absPath == "" then
    return false
  end
  if type(self.projectRoot) ~= "string" or self.projectRoot == "" then
    return false
  end
  local root = self.projectRoot
  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end
  return absPath == self.projectRoot or pathStartsWith(absPath, root)
end

function Runtime:recordDependency(absPath, kind, moduleName)
  if not self:isProjectLocalDependencyPath(absPath) then
    return
  end

  local key = tostring(absPath)
  local entry = self.dependencyFiles[key]
  if not entry then
    entry = {
      path = key,
      kind = kind or "file",
    }
    self.dependencyFiles[key] = entry
    self.dependencyOrder[#self.dependencyOrder + 1] = key
  elseif type(kind) == "string" and kind ~= "" then
    entry.kind = kind
  end

  if type(moduleName) == "string" and moduleName ~= "" then
    entry.moduleName = moduleName
    self.projectLocalModules[moduleName] = key
  end
end

function Runtime:listReloadDependencies()
  local out = {}
  local seen = {}

  local function add(path)
    if type(path) ~= "string" or path == "" or seen[path] then
      return
    end
    seen[path] = true
    out[#out + 1] = path
  end

  add(self.manifestPath)
  add(self.uiRoot)

  for _, key in ipairs(self.dependencyOrder or {}) do
    local entry = self.dependencyFiles[key]
    add(entry and entry.path or nil)
  end

  return out
end

function Runtime:invalidateProjectLocalModules()
  if type(package) ~= "table" or type(package.loaded) ~= "table" then
    return 0
  end

  local cleared = 0
  for moduleName in pairs(self.projectLocalModules or {}) do
    if type(moduleName) == "string" and moduleName ~= "" and package.loaded[moduleName] ~= nil then
      package.loaded[moduleName] = nil
      cleared = cleared + 1
    end
  end
  return cleared
end

function Runtime:installRequireTracking()
  if self.requireTrackingInstalled == true or type(require) ~= "function" then
    return
  end

  self.originalRequire = require
  local runtime = self
  _G.require = function(name)
    local resolvedPath = nil
    if type(package) == "table" and type(package.searchpath) == "function" then
      local ok, found = pcall(package.searchpath, tostring(name or ""), package.path or "", ".", "/")
      if ok and type(found) == "string" and found ~= "" then
        resolvedPath = found
      end
    end

    local result = runtime.originalRequire(name)
    if runtime:isProjectLocalDependencyPath(resolvedPath) then
      runtime:recordDependency(resolvedPath, "module", tostring(name or ""))
    end
    return result
  end
  self.requireTrackingInstalled = true
end

function Runtime:restoreRequireTracking()
  if self.requireTrackingInstalled ~= true then
    return
  end
  if self.originalRequire ~= nil then
    _G.require = self.originalRequire
  end
  self.originalRequire = nil
  self.requireTrackingInstalled = false
end

function Runtime:setLastError(message, operation)
  self.lastError = tostring(message or "")
  self.lastOperation = tostring(operation or "")
end

function Runtime:clearLastError(operation)
  self.lastError = ""
  self.lastOperation = tostring(operation or "")
end

function Runtime:registerWidget(globalId, localWidgets, localId, widget)
  if type(globalId) == "string" and globalId ~= "" then
    self.widgets[globalId] = widget
  end
  if type(localWidgets) == "table" and type(localId) == "string" and localId ~= "" then
    localWidgets[localId] = widget
  end
end

function Runtime:registerRecord(record)
  if type(record) ~= "table" then
    return
  end

  local sourcePath = record.sourceDocumentPath
  local nodeId = nil
  if type(record.spec) == "table" then
    nodeId = record.spec.id
  end

  if type(sourcePath) == "string" and sourcePath ~= "" and type(nodeId) == "string" and nodeId ~= "" then
    local key = sourcePath .. "::" .. nodeId
    self.recordsBySourceKey[key] = record
    self.recordsBySourceLists[key] = self.recordsBySourceLists[key] or {}
    table.insert(self.recordsBySourceLists[key], record)
  end
end

function Runtime:registerRecordAlias(documentPath, nodeId, record)
  if type(documentPath) ~= "string" or documentPath == "" then
    return
  end
  if type(nodeId) ~= "string" or nodeId == "" then
    return
  end
  if type(record) ~= "table" then
    return
  end
  local key = documentPath .. "::" .. nodeId
  self.recordsBySourceKey[key] = record
  self.recordsBySourceLists[key] = self.recordsBySourceLists[key] or {}
  table.insert(self.recordsBySourceLists[key], record)
end

function Runtime:getRecordBySource(documentPath, nodeId)
  if type(documentPath) ~= "string" or documentPath == "" then
    return nil
  end
  if type(nodeId) ~= "string" or nodeId == "" then
    return nil
  end
  return self.recordsBySourceKey[documentPath .. "::" .. nodeId]
end

function Runtime:getRecordsBySource(documentPath, nodeId)
  if type(documentPath) ~= "string" or documentPath == "" then
    return {}
  end
  if type(nodeId) ~= "string" or nodeId == "" then
    return {}
  end
  return self.recordsBySourceLists[documentPath .. "::" .. nodeId] or {}
end

function Runtime:loadDocument(absPath, kind)
  local existing = self.documents[absPath]
  if existing then
    return existing
  end

  self:clearLastError("loadDocument")
  self:recordDependency(absPath, kind or "structured")
  local model = loadStructuredTable(absPath, tostring(kind or "structured") .. ":" .. absPath)
  local document = {
    path = absPath,
    kind = kind or "structured",
    model = model,
    dirty = false,
  }
  self.documents[absPath] = document
  self.documentOrder[#self.documentOrder + 1] = absPath
  return document
end

function Runtime:findNodeById(root, nodeId)
  if type(root) ~= "table" or type(nodeId) ~= "string" or nodeId == "" then
    return nil
  end

  if root.id == nodeId then
    return root
  end

  for _, child in ipairs(root.children or {}) do
    local match = self:findNodeById(child, nodeId)
    if match then
      return match
    end
  end

  for _, comp in ipairs(root.components or {}) do
    if type(comp) == "table" then
      if comp.id == nodeId then
        return comp
      end
      local match = self:findNodeById(comp, nodeId)
      if match then
        return match
      end
    end
  end

  return nil
end

function Runtime:getDocument(absPath)
  return self.documents[absPath]
end

function Runtime:listDocuments()
  local out = {}
  for _, path in ipairs(self.documentOrder or {}) do
    local doc = self.documents[path]
    if doc then
      out[#out + 1] = {
        path = doc.path,
        kind = doc.kind,
        dirty = doc.dirty == true,
      }
    end
  end
  return out
end

function Runtime:syncLiveSpecsForNode(absPath, nodeId, path, value, remove)
  if type(absPath) ~= "string" or absPath == "" then
    return
  end
  if type(nodeId) ~= "string" or nodeId == "" then
    return
  end
  if type(path) ~= "string" or path == "" then
    return
  end

  local seenSpecs = {}

  local function syncSpec(spec)
    if type(spec) ~= "table" or seenSpecs[spec] then
      return
    end
    seenSpecs[spec] = true

    local liveNode = self:findNodeById(spec, nodeId)
    if type(liveNode) ~= "table" then
      return
    end

    if remove then
      removeValueByPath(liveNode, path)
    else
      setValueByPath(liveNode, path, deepCopy(value))
    end
  end

  local function visitRecord(record)
    if type(record) ~= "table" then
      return
    end

    if record.sourceDocumentPath == absPath then
      syncSpec(record.spec)
    end

    for _, child in ipairs(record.children or {}) do
      visitRecord(child)
    end
  end

  visitRecord(self.layoutTree)

  local overrideNodeId, overridePath = string.match(path, "^overrides%.([^.]+)%.(.+)$")
  if type(overrideNodeId) == "string" and overrideNodeId ~= "" and type(overridePath) == "string" and overridePath ~= "" then
    local aliasRecords = self:getRecordsBySource(absPath, nodeId)
    for _, aliasRecord in ipairs(aliasRecords or {}) do
      if type(aliasRecord) == "table" and type(aliasRecord.spec) == "table" then
        local liveNode = self:findNodeById(aliasRecord.spec, overrideNodeId)
        if type(liveNode) == "table" then
          if remove then
            removeValueByPath(liveNode, overridePath)
          else
            setValueByPath(liveNode, overridePath, deepCopy(value))
          end
        end
      end
    end
  end
end

function Runtime:applyComponentInstanceOverrides(componentSpec, instanceSpec)
  local overrides = type(instanceSpec) == "table" and instanceSpec.overrides or nil
  if type(componentSpec) ~= "table" or type(overrides) ~= "table" then
    return
  end

  for childNodeId, overrideSpec in pairs(overrides) do
    if type(childNodeId) == "string" and childNodeId ~= "" and type(overrideSpec) == "table" then
      local target = self:findNodeById(componentSpec, childNodeId)
      if type(target) == "table" then
        mergeDeepInto(target, overrideSpec)
      end
    end
  end
end

function Runtime:annotateComponentInstanceRecords(record, ownerDocumentPath, instanceNodeId, sourceDocumentPath)
  if type(record) ~= "table" or type(ownerDocumentPath) ~= "string" or ownerDocumentPath == "" or type(instanceNodeId) ~= "string" or instanceNodeId == "" then
    return
  end

  if type(sourceDocumentPath) == "string" and sourceDocumentPath ~= "" and record.sourceDocumentPath ~= sourceDocumentPath then
    return
  end

  local widget = record.widget
  local node = widget and widget.node or nil
  if node and node.setUserData then
    local sourceMeta = node.getUserData and node:getUserData("_structuredSource") or nil
    local childNodeId = type(sourceMeta) == "table" and type(sourceMeta.nodeId) == "string" and sourceMeta.nodeId or (type(record.spec) == "table" and record.spec.id) or instanceNodeId
    node:setUserData("_structuredInstanceSource", {
      documentPath = ownerDocumentPath,
      nodeId = instanceNodeId,
      childNodeId = childNodeId,
      globalId = record.globalId,
      kind = (childNodeId == instanceNodeId) and "component_instance" or "component_child_instance",
    })
  end

  for _, childRecord in ipairs(record.children or {}) do
    self:annotateComponentInstanceRecords(childRecord, ownerDocumentPath, instanceNodeId, sourceDocumentPath)
  end
end

function Runtime:getProjectStatus()
  local docs = self:listDocuments()
  local dirtyCount = 0
  for i = 1, #docs do
    if docs[i].dirty == true then
      dirtyCount = dirtyCount + 1
    end
  end

  return {
    projectRoot = self.projectRoot or "",
    manifestPath = self.manifestPath or "",
    requestedPath = self.requestedPath or "",
    uiRoot = self.uiRoot or "",
    documentCount = #docs,
    dirtyCount = dirtyCount,
    lastError = self.lastError or "",
    lastOperation = self.lastOperation or "",
    documents = docs,
  }
end

function Runtime:collectBehaviorRefs(spec, out, seen)
  if type(spec) ~= "table" then
    return
  end

  if type(spec.behavior) == "string" and spec.behavior ~= "" then
    local absPath = resolveAssetPath(self, spec.behavior)
    if not seen[absPath] then
      seen[absPath] = true
      out[#out + 1] = absPath
    end
  end

  for _, child in ipairs(spec.children or {}) do
    self:collectBehaviorRefs(child, out, seen)
  end
  for _, component in ipairs(spec.components or {}) do
    self:collectBehaviorRefs(component, out, seen)
  end
end

function Runtime:listProjectFiles()
  local out = {}
  local projectRoot = self.projectRoot or ""
  local seen = {}

  local function addFile(path, kind, group, dirty)
    if type(path) ~= "string" or path == "" or seen[path] then
      return
    end
    seen[path] = true
    out[#out + 1] = {
      kind = kind or "file",
      group = group or "Project Files",
      name = pathRelativeToRoot(path, projectRoot),
      path = path,
      dirty = dirty == true,
    }
  end

  if type(self.manifestPath) == "string" and self.manifestPath ~= "" then
    addFile(self.manifestPath, "manifest", "Project", false)
  end

  for _, path in ipairs(self.documentOrder or {}) do
    local doc = self.documents[path]
    if doc then
      local group = (doc.kind == "component") and "UI Components" or "UI Scene"
      addFile(doc.path, "ui", group, doc.dirty == true)
    end
  end

  if type(listFilesRecursive) == "function" and projectRoot ~= "" then
    local ok, files = pcall(listFilesRecursive, projectRoot)
    if ok and type(files) == "table" then
      for _, path in ipairs(files) do
        local rel = pathRelativeToRoot(path, projectRoot)
        local kind = "file"
        local group = "Project Files"
        if rel == "manifold.project.json5" then
          kind = "manifest"
          group = "Project"
        elseif pathStartsWith(rel, "ui/components/") then
          kind = "ui"
          group = "UI Components"
        elseif pathStartsWith(rel, "ui/behaviors/") then
          kind = "behavior"
          group = "Behaviors"
        elseif pathStartsWith(rel, "ui/") then
          kind = "ui"
          group = "UI Scene"
        elseif pathStartsWith(rel, "dsp/") then
          kind = "dsp"
          group = "DSP"
        elseif pathStartsWith(rel, "themes/") then
          kind = "theme"
          group = "Themes"
        elseif pathStartsWith(rel, "editor/") then
          kind = "editor"
          group = "Editor"
        end

        local doc = self.documents[path]
        addFile(path, kind, group, doc and doc.dirty == true)
      end
    end
  end

  local groupOrder = {
    ["Project"] = 1,
    ["UI Scene"] = 2,
    ["UI Components"] = 3,
    ["Behaviors"] = 4,
    ["DSP"] = 5,
    ["Themes"] = 6,
    ["Editor"] = 7,
    ["Project Files"] = 99,
  }
  table.sort(out, function(a, b)
    local ga = groupOrder[a.group or ""] or 50
    local gb = groupOrder[b.group or ""] or 50
    if ga ~= gb then
      return ga < gb
    end
    if (a.group or "") ~= (b.group or "") then
      return (a.group or "") < (b.group or "")
    end
    return (a.name or "") < (b.name or "")
  end)

  return out
end

function Runtime:getNodeValue(absPath, nodeId, path)
  local doc = self.documents[absPath]
  if not doc then
    local err = "unknown document: " .. tostring(absPath)
    self:setLastError(err, "getNodeValue")
    return nil, err
  end
  local node = self:findNodeById(doc.model, nodeId)
  if not node then
    local err = "unknown node id: " .. tostring(nodeId)
    self:setLastError(err, "getNodeValue")
    return nil, err
  end
  self:clearLastError("getNodeValue")
  return getValueByPath(node, path), nil
end

function Runtime:setNodeValue(absPath, nodeId, path, value)
  local doc = self.documents[absPath]
  if not doc then
    local err = "unknown document: " .. tostring(absPath)
    self:setLastError(err, "setNodeValue")
    return false, err
  end
  local node = self:findNodeById(doc.model, nodeId)
  if not node then
    local err = "unknown node id: " .. tostring(nodeId)
    self:setLastError(err, "setNodeValue")
    return false, err
  end
  if type(path) ~= "string" or path == "" then
    local err = "missing node path"
    self:setLastError(err, "setNodeValue")
    return false, err
  end
  local ok = setValueByPath(node, path, value)
  if not ok then
    local err = "failed to set path: " .. tostring(path)
    self:setLastError(err, "setNodeValue")
    return false, err
  end

  self:syncLiveSpecsForNode(absPath, nodeId, path, value, false)

  doc.dirty = true
  self:clearLastError("setNodeValue")
  return true, nil
end

function Runtime:removeNodeValue(absPath, nodeId, path)
  local doc = self.documents[absPath]
  if not doc then
    local err = "unknown document: " .. tostring(absPath)
    self:setLastError(err, "removeNodeValue")
    return false, err
  end
  local node = self:findNodeById(doc.model, nodeId)
  if not node then
    local err = "unknown node id: " .. tostring(nodeId)
    self:setLastError(err, "removeNodeValue")
    return false, err
  end
  local ok = removeValueByPath(node, path)
  if not ok then
    local err = "failed to remove path: " .. tostring(path)
    self:setLastError(err, "removeNodeValue")
    return false, err
  end

  self:syncLiveSpecsForNode(absPath, nodeId, path, nil, true)

  doc.dirty = true
  self:clearLastError("removeNodeValue")
  return true, nil
end

function Runtime:saveDocument(absPath)
  local doc = self.documents[absPath]
  if not doc then
    local err = "unknown document: " .. tostring(absPath)
    self:setLastError(err, "saveDocument")
    return false, err
  end
  if type(writeTextFile) ~= "function" then
    local err = "writeTextFile unavailable"
    self:setLastError(err, "saveDocument")
    return false, err
  end

  local source = serializeStructuredDocument(doc.model)
  local ok = writeTextFile(absPath, source)
  if ok == false then
    local err = "writeTextFile failed: " .. tostring(absPath)
    self:setLastError(err, "saveDocument")
    return false, err
  end
  doc.dirty = false
  self:clearLastError("saveDocument")
  return true, nil
end

function Runtime:saveAllDocuments()
  for _, path in ipairs(self.documentOrder or {}) do
    local ok, err = self:saveDocument(path)
    if not ok then
      self:setLastError(err, "saveAllDocuments")
      return false, err
    end
  end
  self:clearLastError("saveAllDocuments")
  return true, nil
end

function Runtime:instantiateSpec(parentNode, spec, opts)
  local widgetClass = SUPPORTED_WIDGETS[spec.type]
  if widgetClass == nil then
    error("unsupported structured widget type: " .. tostring(spec.type))
  end

  local localId = spec.id or opts.defaultName or spec.type
  local globalId = localId
  if type(opts.idPrefix) == "string" and opts.idPrefix ~= "" then
    globalId = opts.idPrefix .. "." .. localId
  end

  local config = flattenSpecConfig(spec, self, opts.extraProps)
  local widget = widgetClass.new(parentNode, localId, config)
  local x, y, w, h = getBounds(spec, opts.boundsOverride)
  if widget.setBounds then
    widget:setBounds(x, y, w, h)
  elseif widget.node and widget.node.setBounds then
    widget.node:setBounds(x, y, w, h)
  end

  if widget.node and widget.node.setUserData then
    widget.node:setUserData("_structuredSource", {
      documentPath = opts.sourceDocumentPath,
      nodeId = spec.id,
      globalId = globalId,
      kind = opts.sourceKind or "node",
    })
  end

  local record = {
    widget = widget,
    spec = spec,
    globalId = globalId,
    children = {},
    parent = opts.parentRecord,
    sourceDocumentPath = opts.sourceDocumentPath,
    sourceKind = opts.sourceKind or "node",
  }

  if type(widget.setStructuredRuntime) == "function" then
    widget:setStructuredRuntime(self, record)
  else
    widget._structuredRuntime = self
    widget._structuredRecord = record
  end

  self:registerWidget(globalId, opts.localWidgets, localId, widget)
  self:registerRecord(record)
  if opts.localWidgets and opts.localWidgets.root == nil and opts.isRoot then
    opts.localWidgets.root = widget
  end

  local childPrefix = globalId
  for _, child in ipairs(spec.children or {}) do
    local _, _, childRecord = self:instantiateSpec(widget.node, child, {
      idPrefix = childPrefix,
      localWidgets = opts.localWidgets,
      extraProps = nil,
      isRoot = false,
      parentRecord = record,
      sourceDocumentPath = opts.sourceDocumentPath,
      sourceKind = "node",
    })
    record.children[#record.children + 1] = childRecord
    if type(widget.addStructuredChild) == "function" then
      widget:addStructuredChild(childRecord, "node", child)
    end
  end

  for _, componentInstance in ipairs(spec.components or {}) do
    local _, _, componentRecord = self:instantiateComponent(widget.node, componentInstance, childPrefix, opts.sourceDocumentPath, record)
    record.children[#record.children + 1] = componentRecord
    if type(widget.addStructuredChild) == "function" then
      widget:addStructuredChild(componentRecord, "component", componentInstance)
    end
  end

  if type(widget.finalizeStructuredChildren) == "function" then
    widget:finalizeStructuredChildren()
  end

  return widget, globalId, record
end

function Runtime:instantiateComponent(parentNode, instanceSpec, parentPrefix, ownerDocumentPath, parentRecord)
  local absRef = resolveAssetPath(self, instanceSpec.ref)
  local componentDoc = self:loadDocument(absRef, "component")
  local componentSpec = deepCopy(componentDoc.model)

  componentSpec.id = instanceSpec.id or componentSpec.id or "component"
  componentSpec.props = mergeInto(componentSpec.props or {}, instanceSpec.props or {})
  componentSpec.x = instanceSpec.x or componentSpec.x or 0
  componentSpec.y = instanceSpec.y or componentSpec.y or 0
  componentSpec.w = instanceSpec.w or componentSpec.w or 0
  componentSpec.h = instanceSpec.h or componentSpec.h or 0
  componentSpec.layout = mergeLayout(componentSpec.layout, instanceSpec.layout)
  componentSpec.layoutChild = mergeNodeTable(componentSpec.layoutChild, instanceSpec.layoutChild)
  self:applyComponentInstanceOverrides(componentSpec, instanceSpec)

  local behaviorInsertIndex = #self.behaviors + 1
  local localWidgets = {}
  local rootWidget, componentGlobalId, componentRecord = self:instantiateSpec(parentNode, componentSpec, {
    idPrefix = parentPrefix,
    localWidgets = localWidgets,
    extraProps = nil,
    isRoot = true,
    parentRecord = parentRecord,
    sourceDocumentPath = componentDoc.path,
    sourceKind = "component_node",
  })

  if rootWidget and rootWidget.node and rootWidget.node.setUserData and type(ownerDocumentPath) == "string" and ownerDocumentPath ~= "" then
    local instanceNodeId = instanceSpec.id or componentSpec.id
    self:annotateComponentInstanceRecords(componentRecord, ownerDocumentPath, instanceNodeId, componentDoc.path)
    self:registerRecordAlias(ownerDocumentPath, instanceNodeId, componentRecord)
  end

  local behaviorRef = instanceSpec.behavior
  if type(behaviorRef) ~= "string" or behaviorRef == "" then
    behaviorRef = componentSpec.behavior
  end

  if type(behaviorRef) == "string" and behaviorRef ~= "" then
    local behaviorPath = resolveAssetPath(self, behaviorRef)
    self:recordDependency(behaviorPath, "behavior")
    local behaviorModule = loadBehaviorModule(behaviorPath, "behavior:" .. behaviorPath)
    local ctx = buildBehaviorContext(self, {
      rootWidget = rootWidget,
      localWidgets = localWidgets,
      instanceId = componentSpec.id,
      instanceProps = instanceSpec.props or {},
      spec = componentSpec,
    })
    table.insert(self.behaviors, behaviorInsertIndex, {
      module = behaviorModule,
      ctx = ctx,
      path = behaviorPath,
      id = componentGlobalId,
      record = componentRecord,
    })
  end

  return rootWidget, componentGlobalId, componentRecord
end

function Runtime:getLayoutInfo(fallbackW, fallbackH)
  local scene = self.sceneSpec or {}
  local shellLayout = scene.shellLayout or scene.viewport or {}
  local mode = shellLayout.mode or shellLayout.sizing or "fill"

  return {
    mode = mode,
    designW = shellLayout.designW or scene.w or fallbackW,
    designH = shellLayout.designH or scene.h or fallbackH,
    scaleMode = shellLayout.scaleMode or shellLayout.presentation,
    alignX = shellLayout.alignX,
    alignY = shellLayout.alignY,
  }
end

function Runtime:applyRecordBounds(record, x, y, w, h)
  local widget = record and record.widget or nil
  if widget and widget.setBounds then
    widget:setBounds(x, y, w, h)
  elseif widget and widget.node and widget.node.setBounds then
    widget.node:setBounds(x, y, w, h)
  end
end

local function isRecordDescendantOf(record, ancestor)
  local current = record
  while current do
    if current == ancestor then
      return true
    end
    current = current.parent
  end
  return false
end

local function isTabHostRecord(record)
  local widget = record and record.widget or nil
  return widget ~= nil and type(widget.isTabHost) == "function" and widget:isTabHost() == true
end

local function visitRecords(record, fn)
  if type(record) ~= "table" then
    return
  end
  fn(record)
  for _, child in ipairs(record.children or {}) do
    visitRecords(child, fn)
  end
end

local function isTabPageRecord(record)
  local widget = record and record.widget or nil
  return widget ~= nil and type(widget.isTabPage) == "function" and widget:isTabPage() == true
end

function Runtime:getImmediateTabPageAncestor(record, tabHostRecord)
  local current = record
  local page = nil
  while current and current ~= tabHostRecord do
    if isTabPageRecord(current) then
      page = current
    end
    current = current.parent
  end
  return page
end

function Runtime:isRecordActive(record)
  local current = record
  while current do
    local parent = current.parent
    if isTabHostRecord(parent) then
      local activePage = parent.widget and parent.widget.getActivePageRecord and parent.widget:getActivePageRecord() or nil
      local pageAncestor = self:getImmediateTabPageAncestor(record, parent)
      if activePage ~= nil and pageAncestor ~= activePage then
        return false
      end
    end
    current = parent
  end
  return true
end

function Runtime:applyLayoutSubtree(record, parentW, parentH, skipSelf)
  if type(record) ~= "table" or record.widget == nil then
    return
  end

  local currentW = tonumber(parentW)
  local currentH = tonumber(parentH)

  if not skipSelf then
    local x, y, w, h = resolveLayoutBounds(record.spec or {}, currentW or 0, currentH or 0)
    self:applyRecordBounds(record, x, y, w, h)
    currentW = w
    currentH = h
  else
    if (currentW == nil or currentH == nil) and record.widget.node then
      if currentW == nil and record.widget.node.getWidth then
        currentW = record.widget.node:getWidth()
      end
      if currentH == nil and record.widget.node.getHeight then
        currentH = record.widget.node:getHeight()
      end
    end
  end

  currentW = tonumber(currentW) or 0
  currentH = tonumber(currentH) or 0

  if isTabHostRecord(record) then
    local hostWidget = record.widget
    local contentX, contentY, contentW, contentH = 0, 0, currentW, currentH
    if hostWidget and type(hostWidget.getContentRect) == "function" then
      contentX, contentY, contentW, contentH = hostWidget:getContentRect()
    end

    local activePage = hostWidget and hostWidget.getActivePageRecord and hostWidget:getActivePageRecord() or nil

    for _, childRecord in ipairs(record.children or {}) do
      if isTabPageRecord(childRecord) then
        local isActive = (activePage == nil and childRecord == record.children[1]) or (childRecord == activePage)
        if childRecord.widget and type(childRecord.widget.setVisible) == "function" then
          childRecord.widget:setVisible(isActive)
        end
        if isActive then
          self:applyRecordBounds(childRecord, contentX, contentY, contentW, contentH)
          self:applyLayoutSubtree(childRecord, contentW, contentH, true)
        else
          self:applyRecordBounds(childRecord, contentX, contentY, 0, 0)
        end
      else
        local x, y, w, h = resolveLayoutBounds(childRecord.spec or {}, currentW, currentH)
        self:applyRecordBounds(childRecord, x, y, w, h)
        self:applyLayoutSubtree(childRecord, w, h, true)
      end
    end
    return
  end

  if LayoutEngine.isManagedContainerSpec(record.spec) then
    LayoutEngine.applyContainerLayout(record, currentW, currentH, {
      applyRecordBounds = function(childRecord, x, y, w, h)
        self:applyRecordBounds(childRecord, x, y, w, h)
      end,
      resolveLayoutBounds = function(spec, parentWidth, parentHeight, fallback)
        return resolveLayoutBounds(spec, parentWidth, parentHeight, fallback)
      end,
    })

    for _, childRecord in ipairs(record.children or {}) do
      local childW = 0
      local childH = 0
      if childRecord.widget and childRecord.widget.node then
        if childRecord.widget.node.getWidth then
          childW = tonumber(childRecord.widget.node:getWidth()) or 0
        end
        if childRecord.widget.node.getHeight then
          childH = tonumber(childRecord.widget.node:getHeight()) or 0
        end
        if (childW <= 0 or childH <= 0) and childRecord.widget.node.getBounds then
          local _, _, bw, bh = childRecord.widget.node:getBounds()
          if childW <= 0 then childW = tonumber(bw) or 0 end
          if childH <= 0 then childH = tonumber(bh) or 0 end
        end
      end
      self:applyLayoutSubtree(childRecord, childW, childH, true)
    end
    return
  end

  for _, childRecord in ipairs(record.children or {}) do
    local x, y, w, h = resolveLayoutBounds(childRecord.spec or {}, currentW, currentH)
    self:applyRecordBounds(childRecord, x, y, w, h)
    self:applyLayoutSubtree(childRecord, w, h, true)
  end
end

function Runtime:init(rootNode)
  self.rootNode = rootNode
  self.widgets = {}
  self.behaviors = {}
  self.layoutTree = nil
  self.documents = {}
  self.documentOrder = {}
  self.recordsBySourceKey = {}
  self.recordsBySourceLists = {}
  self.dependencyFiles = {}
  self.dependencyOrder = {}
  self.projectLocalModules = {}
  self:installRequireTracking()

  local sceneDoc = self:loadDocument(self.uiRoot, "scene")
  self.sceneSpec = sceneDoc.model

  local localWidgets = {}
  self.rootWidget, _, self.layoutTree = self:instantiateSpec(rootNode, self.sceneSpec, {
    idPrefix = "",
    localWidgets = localWidgets,
    extraProps = nil,
    isRoot = true,
    sourceDocumentPath = sceneDoc.path,
    sourceKind = "scene_node",
  })

  if type(self.sceneSpec.behavior) == "string" and self.sceneSpec.behavior ~= "" then
    local behaviorPath = resolveAssetPath(self, self.sceneSpec.behavior)
    self:recordDependency(behaviorPath, "behavior")
    local behaviorModule = loadBehaviorModule(behaviorPath, "behavior:" .. behaviorPath)
    table.insert(self.behaviors, 1, {
      module = behaviorModule,
      ctx = buildBehaviorContext(self, {
        rootWidget = self.rootWidget,
        localWidgets = localWidgets,
        instanceId = self.sceneSpec.id or "root",
        instanceProps = self.sceneSpec.props or {},
        spec = self.sceneSpec,
      }),
      path = behaviorPath,
      id = self.sceneSpec.id or "root",
      record = self.layoutTree,
    })
  end

  for _, entry in ipairs(self.behaviors) do
    if type(entry.module.init) == "function" then
      entry.module.init(entry.ctx)
    end
  end
end

function Runtime:resized(w, h)
  if self.suspendLayoutPass == true then
    self.lastRootWidth = w
    self.lastRootHeight = h
    return
  end

  if self.rootWidget and self.rootWidget.setBounds then
    self.rootWidget:setBounds(0, 0, w, h)
  end

  if self.layoutTree then
    self:applyLayoutSubtree(self.layoutTree, w, h, true)
  end

  self.lastRootWidth = w
  self.lastRootHeight = h

  for _, entry in ipairs(self.behaviors) do
    if entry.record == nil or self:isRecordActive(entry.record) then
      local bw = w
      local bh = h
      local rootWidget = entry.ctx and entry.ctx.root or nil
      if rootWidget and rootWidget.node then
        if rootWidget.node.getWidth then
          bw = rootWidget.node:getWidth()
        end
        if rootWidget.node.getHeight then
          bh = rootWidget.node:getHeight()
        end
      end

      if entry.record and entry.record ~= self.layoutTree then
        self:applyLayoutSubtree(entry.record, bw, bh, true)
      end

      if type(entry.module.resized) == "function" then
        entry.module.resized(entry.ctx, bw, bh)
      end
    end
  end

  self:refreshHostedContainers()
end

local function canonicalStatePath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 10) == "/manifold/" then
    return "/core/behavior/" .. path:sub(11)
  end
  if path:sub(1, 14) == "/dsp/manifold/" then
    return "/core/behavior/" .. path:sub(15)
  end
  return path
end

local function buildChangedPathSet(changedPaths)
  if type(changedPaths) ~= "table" then
    return nil
  end

  local set = {}
  for _, path in ipairs(changedPaths) do
    if type(path) == "string" and path ~= "" then
      set[path] = true
      local canonical = canonicalStatePath(path)
      if canonical ~= nil then
        set[canonical] = true
      end
    end
  end
  return set
end

function Runtime:update(changedPaths)
  local state = (type(_G) == "table" and type(_G.state) == "table") and _G.state or nil
  local changedSet = buildChangedPathSet(changedPaths)

  for _, entry in ipairs(self.behaviors) do
    if (entry.record == nil or self:isRecordActive(entry.record)) and type(entry.module.update) == "function" then
      local shouldUpdate = true

      if type(entry.module.shouldUpdate) == "function" then
        shouldUpdate = entry.module.shouldUpdate(entry.ctx, changedPaths, changedSet) == true
      elseif changedSet ~= nil then
        local subscriptions = entry.ctx and entry.ctx._subscriptions or nil
        if type(subscriptions) == "table" and next(subscriptions) ~= nil then
          shouldUpdate = false
          for path in pairs(subscriptions) do
            if changedSet[path] == true then
              shouldUpdate = true
              break
            end
          end
        end
      end

      if shouldUpdate then
        entry.module.update(entry.ctx, state, changedPaths)
      end
    end
  end
end

function Runtime:refreshHostedContainers()
  if not self.layoutTree then
    return
  end

  visitRecords(self.layoutTree, function(record)
    if isTabHostRecord(record) then
      self:notifyHostedContainerChanged(record)
    end
  end)
end

function Runtime:notifyRecordHostedResized(record, w, h)
  if type(record) ~= "table" then
    return false
  end

  if self.suspendLayoutPass == true then
    return true
  end

  local width = tonumber(w)
  local height = tonumber(h)
  if width == nil or height == nil then
    local widget = record.widget
    if widget and widget.node then
      if width == nil and widget.node.getWidth then
        width = widget.node:getWidth()
      end
      if height == nil and widget.node.getHeight then
        height = widget.node:getHeight()
      end
    end
  end

  width = tonumber(width) or 0
  height = tonumber(height) or 0

  self:applyLayoutSubtree(record, width, height, true)

  for _, entry in ipairs(self.behaviors or {}) do
    if entry.record and isRecordDescendantOf(entry.record, record) and self:isRecordActive(entry.record) then
      local bw = width
      local bh = height
      local rootWidget = entry.ctx and entry.ctx.root or nil
      if rootWidget and rootWidget.node then
        if rootWidget.node.getWidth then bw = rootWidget.node:getWidth() end
        if rootWidget.node.getHeight then bh = rootWidget.node:getHeight() end
      end

      if entry.record and entry.record ~= record then
        self:applyLayoutSubtree(entry.record, bw, bh, true)
      end

      if type(entry.module.resized) == "function" then
        entry.module.resized(entry.ctx, bw, bh)
      end
    end
  end

  return true
end

function Runtime:notifyHostedContainerChanged(record)
  if type(record) ~= "table" then
    return false
  end
  local widget = record.widget
  if not (widget and widget.node) then
    return false
  end
  local w = widget.node.getWidth and widget.node:getWidth() or self.lastRootWidth or 0
  local h = widget.node.getHeight and widget.node:getHeight() or self.lastRootHeight or 0
  return self:notifyRecordHostedResized(record, w, h)
end

function Runtime:cleanup()
  for i = #self.behaviors, 1, -1 do
    local entry = self.behaviors[i]
    if type(entry.module.cleanup) == "function" then
      entry.module.cleanup(entry.ctx)
    end
  end
  self:invalidateProjectLocalModules()
  self:restoreRequireTracking()
  self.behaviors = {}
  self.widgets = {}
  self.layoutTree = nil
  self.documents = {}
  self.documentOrder = {}
  self.recordsBySourceKey = {}
  self.recordsBySourceLists = {}
  self.dependencyFiles = {}
  self.dependencyOrder = {}
  self.projectLocalModules = {}
end

function M.install(opts)
  local runtime = Runtime.new(opts or {})
  local usingShellPerformanceView = false

  local function publishRuntimeGlobals(active)
    if active then
      _G.__manifoldStructuredUiRuntime = runtime
      _G.getStructuredUiDocuments = function()
        return runtime:listDocuments()
      end
      _G.getStructuredUiProjectFiles = function()
        return runtime:listProjectFiles()
      end
      _G.getStructuredUiReloadDependencies = function()
        return runtime:listReloadDependencies()
      end
      _G.getStructuredUiProjectStatus = function()
        return runtime:getProjectStatus()
      end
      _G.getStructuredUiNodeValue = function(documentPath, nodeId, path)
        local value, err = runtime:getNodeValue(documentPath, nodeId, path)
        if err then
          runtime:setLastError(err, "getStructuredUiNodeValue")
          error(err)
        end
        runtime:clearLastError("getStructuredUiNodeValue")
        return value
      end
      _G.setStructuredUiNodeValue = function(documentPath, nodeId, path, value)
        local ok, err = runtime:setNodeValue(documentPath, nodeId, path, value)
        if not ok then
          runtime:setLastError(err, "setStructuredUiNodeValue")
          error(err)
        end
        runtime:clearLastError("setStructuredUiNodeValue")
        return true
      end
      _G.removeStructuredUiNodeValue = function(documentPath, nodeId, path)
        local ok, err = runtime:removeNodeValue(documentPath, nodeId, path)
        if not ok then
          runtime:setLastError(err, "removeStructuredUiNodeValue")
          error(err)
        end
        runtime:clearLastError("removeStructuredUiNodeValue")
        return true
      end
      _G.saveStructuredUiDocument = function(documentPath)
        local ok, err = runtime:saveDocument(documentPath)
        if not ok then
          runtime:setLastError(err, "saveStructuredUiDocument")
          error(err)
        end
        runtime:clearLastError("saveStructuredUiDocument")
        return true
      end
      _G.saveStructuredUiAll = function()
        local ok, err = runtime:saveAllDocuments()
        if not ok then
          runtime:setLastError(err, "saveStructuredUiAll")
          error(err)
        end
        runtime:clearLastError("saveStructuredUiAll")
        return true
      end
      _G.reloadStructuredUiProject = function()
        local currentPath = getCurrentScriptPath and getCurrentScriptPath() or runtime.requestedPath or runtime.manifestPath
        if type(currentPath) ~= "string" or currentPath == "" then
          runtime:setLastError("no current structured UI project path", "reloadStructuredUiProject")
          error("no current structured UI project path")
        end
        if type(switchUiScript) ~= "function" then
          runtime:setLastError("switchUiScript unavailable", "reloadStructuredUiProject")
          error("switchUiScript unavailable")
        end
        runtime:clearLastError("reloadStructuredUiProject")
        switchUiScript(currentPath)
        return true
      end
    else
      if _G.__manifoldStructuredUiRuntime == runtime then
        _G.__manifoldStructuredUiRuntime = nil
        _G.getStructuredUiDocuments = nil
        _G.getStructuredUiProjectFiles = nil
        _G.getStructuredUiReloadDependencies = nil
        _G.getStructuredUiProjectStatus = nil
        _G.getStructuredUiNodeValue = nil
        _G.setStructuredUiNodeValue = nil
        _G.removeStructuredUiNodeValue = nil
        _G.saveStructuredUiDocument = nil
        _G.saveStructuredUiAll = nil
        _G.reloadStructuredUiProject = nil
      end
    end
  end

  function ui_init(root)
    publishRuntimeGlobals(true)
    if shell and type(shell.registerPerformanceView) == "function" then
      usingShellPerformanceView = true
      shell:registerPerformanceView({
        init = function(contentRoot)
          local ok, err = pcall(function()
            runtime:init(contentRoot)
            runtime:update(nil)
          end)
          if not ok then
            runtime:setLastError(err, "ui_init")
            error(err)
          end
          runtime:clearLastError("ui_init")
        end,
        getLayoutInfo = function(fallbackW, fallbackH)
          return runtime:getLayoutInfo(fallbackW, fallbackH)
        end,
        resized = function(x, y, w, h)
          local _ = x
          _ = y
          runtime:resized(w, h)
        end,
        update = function(changedPaths)
          runtime:update(changedPaths)
        end,
      })
      return
    end

    local ok, err = pcall(function()
      runtime:init(root)
    end)
    if not ok then
      runtime:setLastError(err, "ui_init")
      error(err)
    end
    runtime:clearLastError("ui_init")
    runtime:update(nil)
  end

  function ui_resized(w, h)
    if usingShellPerformanceView then
      return
    end
    runtime:resized(w, h)
  end

  function ui_update(state)
    if usingShellPerformanceView then
      return
    end
    runtime:update(state)
  end

  function ui_cleanup()
    publishRuntimeGlobals(false)
    runtime:cleanup()
  end

  return runtime
end

M.Runtime = Runtime

return M

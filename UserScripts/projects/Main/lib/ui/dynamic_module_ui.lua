local M = {}

function M.clamp(value, lo, hi)
  local n = tonumber(value) or 0.0
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function M.readParam(path, fallback)
  if type(_G.getParam) == "function" then
    local ok, value = pcall(_G.getParam, path)
    if ok and value ~= nil then
      return value
    end
  end
  return fallback
end

function M.writeParam(path, value)
  local numeric = tonumber(value) or 0
  if type(_G.setParam) == "function" then
    return _G.setParam(path, numeric)
  end
  if type(command) == "function" then
    command("SET", path, tostring(numeric))
    return true
  end
  return false
end

function M.isUsableInstanceModuleId(moduleId)
  local id = tostring(moduleId or "")
  if id == "" then
    return false
  end
  if id:match("Component$") or id:match("Content$") or id:match("Shell$") then
    return false
  end
  return true
end

function M.nodeIdFromGlobalId(globalId)
  local gid = tostring(globalId or "")
  local shellId = gid:match("%.([^.]+Shell)%.[^.]+$") or gid:match("([^.]+Shell)%.[^.]+$")
  if type(shellId) == "string" and shellId ~= "" then
    local moduleId = shellId:gsub("Shell$", "")
    if M.isUsableInstanceModuleId(moduleId) then
      return moduleId
    end
  end
  return nil
end

function M.getInstanceModuleId(ctx, fallbackModuleId)
  local propsNodeId = type(ctx) == "table" and ctx.instanceProps and ctx.instanceProps.instanceNodeId or nil
  if M.isUsableInstanceModuleId(propsNodeId) then
    if type(ctx) == "table" then
      ctx._instanceNodeId = propsNodeId
    end
    return propsNodeId
  end
  if type(ctx) == "table" and M.isUsableInstanceModuleId(ctx._instanceNodeId) then
    return ctx._instanceNodeId
  end

  local record = ctx and ctx.root and ctx.root._structuredRecord or nil
  local globalId = type(record) == "table" and tostring(record.globalId or "") or ""
  local moduleId = M.nodeIdFromGlobalId(globalId)
  if moduleId ~= nil then
    if type(ctx) == "table" then
      ctx._instanceNodeId = moduleId
    end
    return moduleId
  end

  local root = ctx and ctx.root or nil
  local node = root and root.node or nil
  local source = node and node.getUserData and node:getUserData("_structuredInstanceSource") or nil
  local sourceNodeId = type(source) == "table" and type(source.nodeId) == "string" and source.nodeId or nil
  if M.isUsableInstanceModuleId(sourceNodeId) then
    if type(ctx) == "table" then
      ctx._instanceNodeId = sourceNodeId
    end
    return sourceNodeId
  end

  local sourceGlobalId = type(source) == "table" and tostring(source.globalId or "") or ""
  moduleId = M.nodeIdFromGlobalId(sourceGlobalId)
  if moduleId ~= nil then
    if type(ctx) == "table" then
      ctx._instanceNodeId = moduleId
    end
    return moduleId
  end

  return tostring(fallbackModuleId or "module_inst_1")
end

function M.getParamBase(ctx, templateBase, fallbackModuleId)
  local instanceProps = type(ctx) == "table" and ctx.instanceProps or nil
  local propsParamBase = type(instanceProps) == "table" and type(instanceProps.paramBase) == "string" and instanceProps.paramBase or nil
  if type(propsParamBase) == "string" and propsParamBase ~= "" then
    return propsParamBase
  end
  local moduleId = M.getInstanceModuleId(ctx, fallbackModuleId)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[moduleId] or nil
  local paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase
  end
  return tostring(templateBase or "")
end

function M.pathFor(ctx, templateBase, fallbackModuleId, suffix)
  return M.getParamBase(ctx, templateBase, fallbackModuleId) .. "/" .. tostring(suffix or "")
end

function M.syncSelected(widget, selectedIndex)
  local idx = math.max(1, math.floor(tonumber(selectedIndex) or 1))
  if widget and widget.setSelected and not widget._open then
    widget:setSelected(idx)
  end
end

function M.setOptions(widget, options, selectedIndex)
  if not widget then
    return
  end
  if type(options) == "table" and widget.setOptions then
    widget:setOptions(options)
  end
  if selectedIndex ~= nil then
    M.syncSelected(widget, selectedIndex)
  end
end

function M.setText(widget, text)
  if widget and widget.setText then
    widget:setText(tostring(text or ""))
  end
end

function M.setLabel(widget, label)
  if widget and widget.setLabel then
    widget:setLabel(tostring(label or ""))
  elseif widget then
    widget._label = tostring(label or "")
    if widget._syncRetained then
      widget:_syncRetained()
    end
  end
end

function M.refreshDisplay(widget, builder)
  if not (widget and widget.node and type(builder) == "function") then
    return false
  end
  local w = tonumber(widget.node:getWidth()) or 0
  local h = tonumber(widget.node:getHeight()) or 0
  if w <= 0 or h <= 0 then
    return false
  end
  widget.node:setDisplayList(builder(math.max(1, math.floor(w)), math.max(1, math.floor(h))) or {})
  if widget.node.repaint then
    widget.node:repaint()
  end
  return true
end

local function makeNestedScalarProxy(base)
  return setmetatable({}, {
    __index = function(_, key)
      if type(osc) ~= "table" or type(osc.getValue) ~= "function" then
        return nil
      end
      return osc.getValue(base .. "/" .. tostring(key))
    end,
  })
end

local function readVoiceEntries(base)
  if type(osc) ~= "table" or type(osc.getValue) ~= "function" then
    return {}
  end
  local count = math.max(0, math.floor(tonumber(osc.getValue(base .. "/count")) or 0))
  local out = {}
  for i = 1, count do
    local voiceBase = base .. "/" .. tostring(i)
    out[i] = setmetatable({}, {
      __index = function(_, key)
        return osc.getValue(voiceBase .. "/" .. tostring(key))
      end,
    })
  end
  return out
end

function M.getViewState(globalKey, moduleId)
  local id = tostring(moduleId or "")
  local store = type(_G) == "table" and _G[globalKey] or nil
  if type(store) == "table" and type(store[id]) == "table" then
    return store[id]
  end

  if type(osc) == "table" and type(osc.getValue) == "function" and globalKey ~= "" and id ~= "" then
    local base = "/plugin/ui/viewstate/" .. tostring(globalKey) .. "/" .. id
    return setmetatable({}, {
      __index = function(_, key)
        local keyStr = tostring(key)
        if keyStr == "activeVoices" then
          return readVoiceEntries(base .. "/activeVoices")
        end
        if keyStr == "values" or keyStr == "outputs" then
          return makeNestedScalarProxy(base .. "/" .. keyStr)
        end
        local value = osc.getValue(base .. "/" .. keyStr)
        if value == nil then
          return nil
        end
        return value
      end,
    })
  end

  return nil
end

return M

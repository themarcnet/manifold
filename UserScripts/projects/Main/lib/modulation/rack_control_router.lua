local RackSpecs = require("behaviors.rack_midisynth_specs")

local Router = {}
Router.__index = Router

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for key, entry in pairs(value) do
    out[key] = copyTable(entry)
  end
  return out
end

local function copyArray(values)
  local out = {}
  for i = 1, #(values or {}) do
    out[i] = copyTable(values[i])
  end
  return out
end

local function buildPortIndex()
  local specById = RackSpecs.rackModuleSpecById()
  local index = {}

  for moduleId, spec in pairs(specById) do
    local entry = {
      controlInputs = {},
      controlOutputs = {},
      paramInputs = {},
      paramOutputs = {},
    }

    local ports = spec.ports or {}
    for _, key in ipairs({ "inputs", "outputs" }) do
      local list = type(ports[key]) == "table" and ports[key] or {}
      for i = 1, #list do
        local port = list[i]
        if tostring(port.type or "") == "control" then
          if key == "inputs" then
            entry.controlInputs[tostring(port.id or "")] = true
          else
            entry.controlOutputs[tostring(port.id or "")] = true
          end
        end
      end
    end

    local params = ports.params or {}
    for i = 1, #params do
      local param = params[i]
      local paramId = tostring(param.id or "")
      if param.input == true then
        entry.paramInputs[paramId] = tostring(param.path or "")
      end
      if param.output == true then
        entry.paramOutputs[paramId] = tostring(param.path or "")
      end
    end

    index[moduleId] = entry
  end

  return index
end

local function nonAudioConnections(connections)
  local out = {}
  local source = type(connections) == "table" and connections or {}
  for i = 1, #source do
    local conn = source[i]
    if type(conn) == "table" and tostring(conn.kind or "") ~= "audio" then
      out[#out + 1] = conn
    end
  end
  return out
end

local function resolveExplicitRouteMode(connMeta)
  if type(connMeta) ~= "table" then
    return nil
  end
  local mode = connMeta.applyMode or connMeta.mode
  if mode == nil then
    return nil
  end
  local text = tostring(mode)
  if text == "" then
    return nil
  end
  return text
end

function Router.new(options)
  options = options or {}
  local self = setmetatable({}, Router)
  self.portIndex = buildPortIndex()
  self.routes = {}
  self.activeRoutes = {}
  self.rejectedRoutes = {}
  self.byTarget = {}
  self.lastReason = nil
  return self
end

function Router:resolveSourceId(endpoint)
  local from = type(endpoint) == "table" and endpoint or {}
  local moduleId = tostring(from.moduleId or "")
  local portId = tostring(from.portId or "")
  if moduleId == "__midiInput" and portId == "voice" then
    return "midi.voice"
  end
  local spec = self.portIndex[moduleId]
  if spec == nil then
    return nil
  end
  if spec.controlOutputs[portId] == true then
    return string.format("%s.%s", moduleId, portId)
  end
  local paramPath = spec.paramOutputs[portId]
  if type(paramPath) == "string" and paramPath ~= "" then
    return "param_out:" .. paramPath
  end
  return nil
end

function Router:resolveTargetId(endpoint)
  local to = type(endpoint) == "table" and endpoint or {}
  local moduleId = tostring(to.moduleId or "")
  local portId = tostring(to.portId or "")
  local spec = self.portIndex[moduleId]
  if spec == nil then
    return nil
  end
  if spec.controlInputs[portId] == true then
    return string.format("%s.%s", moduleId, portId)
  end
  local paramPath = spec.paramInputs[portId]
  if type(paramPath) == "string" and paramPath ~= "" then
    return paramPath
  end
  return nil
end

function Router:rebuild(connections, routeCompiler, endpointRegistry, reason)
  self.portIndex = buildPortIndex()
  local rawRoutes = {}
  local activeRoutes = {}
  local rejectedRoutes = {}
  local byTarget = {}

  local controlConnections = nonAudioConnections(connections)
  for i = 1, #controlConnections do
    local conn = controlConnections[i]
    local sourceId = self:resolveSourceId(conn.from)
    local targetId = self:resolveTargetId(conn.to)
    local connMeta = type(conn.meta) == "table" and conn.meta or {}
    local routeMode = resolveExplicitRouteMode(connMeta)
    local route = {
      id = tostring(conn.id or string.format("rack_control_%d", i)),
      source = sourceId,
      target = targetId,
      mode = routeMode,
      amount = tonumber(connMeta.modAmount) or 1.0,
      enabled = connMeta.disabled ~= true,
      meta = {
        sourceView = "rack",
        connectionKind = conn.kind,
        from = copyTable(conn.from),
        to = copyTable(conn.to),
        modAmount = tonumber(connMeta.modAmount) or 1.0,
        applyMode = routeMode,
      },
    }
    rawRoutes[#rawRoutes + 1] = route

    local compiled = routeCompiler and routeCompiler.compileRoute and routeCompiler:compileRoute(route, endpointRegistry) or {
      ok = false,
      route = route,
      errors = {
        { code = "missing_compiler", message = "route compiler unavailable" },
      },
      warnings = {},
      compiled = nil,
    }

    if compiled.ok then
      activeRoutes[#activeRoutes + 1] = compiled
      local targetKey = tostring(compiled.compiled and compiled.compiled.targetHandle or compiled.route and compiled.route.target or "")
      byTarget[targetKey] = byTarget[targetKey] or {}
      byTarget[targetKey][#byTarget[targetKey] + 1] = compiled
    else
      rejectedRoutes[#rejectedRoutes + 1] = compiled
    end
  end

  self.routes = rawRoutes
  self.activeRoutes = activeRoutes
  self.rejectedRoutes = rejectedRoutes
  self.byTarget = byTarget
  self.lastReason = reason

  return self:debugSnapshot()
end

function Router:isTargetConnected(targetId)
  local routes = self.byTarget[tostring(targetId or "")]
  return type(routes) == "table" and #routes > 0
end

function Router:getRoutesForTarget(targetId)
  return copyArray(self.byTarget[tostring(targetId or "")] or {})
end

function Router:updateRouteAmount(routeId, amount)
  local key = tostring(routeId or "")
  local nextAmount = tonumber(amount)
  if key == "" or nextAmount == nil then
    return false
  end

  local updated = false

  for i = 1, #self.routes do
    local route = self.routes[i]
    if tostring(route and route.id or "") == key then
      route.amount = nextAmount
      route.meta = type(route.meta) == "table" and route.meta or {}
      route.meta.modAmount = nextAmount
      updated = true
    end
  end

  for i = 1, #self.activeRoutes do
    local entry = self.activeRoutes[i]
    if tostring(entry and entry.route and entry.route.id or "") == key then
      if type(entry.route) == "table" then
        entry.route.amount = nextAmount
        entry.route.meta = type(entry.route.meta) == "table" and entry.route.meta or {}
        entry.route.meta.modAmount = nextAmount
      end
      if type(entry.compiled) == "table" then
        entry.compiled.amount = nextAmount
      end
      updated = true
    end
  end

  for i = 1, #self.rejectedRoutes do
    local entry = self.rejectedRoutes[i]
    if tostring(entry and entry.route and entry.route.id or "") == key then
      if type(entry.route) == "table" then
        entry.route.amount = nextAmount
        entry.route.meta = type(entry.route.meta) == "table" and entry.route.meta or {}
        entry.route.meta.modAmount = nextAmount
      end
      updated = true
    end
  end

  return updated
end

function Router:debugSnapshot()
  local targets = {}
  for targetId, routes in pairs(self.byTarget) do
    targets[#targets + 1] = {
      target = targetId,
      routeCount = #routes,
      routeIds = (function()
        local out = {}
        for i = 1, #routes do
          out[i] = routes[i].route and routes[i].route.id or nil
        end
        return out
      end)(),
    }
  end
  table.sort(targets, function(a, b)
    return tostring(a.target or "") < tostring(b.target or "")
  end)

  return {
    routeCount = #self.routes,
    activeRouteCount = #self.activeRoutes,
    rejectedRouteCount = #self.rejectedRoutes,
    lastReason = self.lastReason,
    targets = targets,
    routes = copyArray(self.activeRoutes),
    rejectedRoutes = copyArray(self.rejectedRoutes),
  }
end

return Router

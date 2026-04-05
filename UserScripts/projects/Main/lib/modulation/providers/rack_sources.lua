local RackSpecs = require("behaviors.rack_midisynth_specs")

local M = {}

local CONTROL_PORT_META = {
  adsr = {
    midi = { direction = "target", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "ADSR MIDI In", min = 0, max = 1, default = 0 },
    gate = { direction = "target", scope = "voice", signalKind = "gate", domain = "event", displayName = "ADSR Gate", min = 0, max = 1, default = 0 },
    retrig = { direction = "target", scope = "voice", signalKind = "trigger", domain = "event", displayName = "ADSR Retrig", min = 0, max = 1, default = 0 },
    voice = { direction = "source", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "ADSR Voice", min = 0, max = 1, default = 0 },
    env = { direction = "source", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "ADSR Env", min = 0, max = 1, default = 0 },
    inv = { direction = "source", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "ADSR Inverted Env", min = 0, max = 1, default = 1 },
    eoc = { direction = "source", scope = "voice", signalKind = "trigger", domain = "event", displayName = "ADSR End Of Cycle", min = 0, max = 1, default = 0 },
  },
  arp = {
    voice_in = { direction = "target", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "Arp Voice In", min = 0, max = 1, default = 0 },
    voice = { direction = "source", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "Arp Voice Out", min = 0, max = 1, default = 0 },
  },
  oscillator = {
    voice = { direction = "target", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "Oscillator Voice", min = 0, max = 1, default = 0 },
    gate = { direction = "target", scope = "voice", signalKind = "gate", domain = "event", displayName = "Oscillator Gate", min = 0, max = 1, default = 0 },
    v_oct = { direction = "target", scope = "voice", signalKind = "scalar", domain = "midi_note", displayName = "Oscillator V/Oct", min = 0, max = 127, default = 60 },
    fm = { direction = "target", scope = "voice", signalKind = "scalar_bipolar", domain = "normalized", displayName = "Oscillator FM", min = -1, max = 1, default = 0 },
    pw_cv = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Oscillator Pulse Width CV", min = 0, max = 1, default = 0.5 },
    blend_cv = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Oscillator Blend CV", min = 0, max = 1, default = 0.5 },
  },
  rack_oscillator = {
    voice = { direction = "target", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "Rack Oscillator Voice", min = 0, max = 1, default = 0 },
    gate = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Rack Oscillator Gate", min = 0, max = 0.4, default = 0 },
    v_oct = { direction = "target", scope = "voice", signalKind = "scalar", domain = "midi_note", displayName = "Rack Oscillator V/Oct", min = 0, max = 127, default = 60 },
    fm = { direction = "target", scope = "voice", signalKind = "scalar_bipolar", domain = "normalized", displayName = "Rack Oscillator FM", min = -1, max = 1, default = 0 },
    pw_cv = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Rack Oscillator Pulse Width CV", min = 0, max = 1, default = 0.5 },
  },
  rack_sample = {
    voice = { direction = "target", scope = "voice", signalKind = "voice_bundle", domain = "voice", displayName = "Rack Sample Voice", min = 0, max = 1, default = 0 },
    gate = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Rack Sample Gate", min = 0, max = 1, default = 0 },
    v_oct = { direction = "target", scope = "voice", signalKind = "scalar", domain = "midi_note", displayName = "Rack Sample V/Oct", min = 0, max = 127, default = 60 },
  },
  filter = {
    env = { direction = "target", scope = "voice", signalKind = "scalar_unipolar", domain = "normalized", displayName = "Filter Env", min = 0, max = 1, default = 0 },
  },
}

local function copyArray(values)
  local out = {}
  for i = 1, #(values or {}) do
    out[i] = values[i]
  end
  return out
end

local function inferScope(nodeId, path)
  local node = tostring(nodeId or "")
  local rawPath = tostring(path or "")
  if rawPath:match("^/midi/synth/voice/") then
    return "voice"
  end
  if node == "adsr" or node == "oscillator" or node == "filter" then
    return "voice"
  end
  return "global"
end

local function inferSignalKind(param)
  if type(param) ~= "table" then
    return "scalar"
  end
  if type(param.options) == "table" and #param.options > 0 then
    return "stepped"
  end
  if tostring(param.format or "") == "enum" then
    return "stepped"
  end
  return "scalar"
end

local function inferDomain(param)
  if type(param) ~= "table" then
    return "normalized"
  end
  local format = tostring(param.format or "")
  local path = tostring(param.path or "")
  if format == "freq" or path:match("/cutoff$") or path:match("/freq$") then
    return "freq"
  end
  if format == "time" then
    return "time"
  end
  if format == "enum" then
    return "enum_index"
  end
  if path:match("/output$") and tonumber(param.min) ~= nil and tonumber(param.min) < 0 then
    return "gain_db"
  end
  return "normalized"
end

local function emitControlEndpoints(spec, out)
  local moduleId = tostring(spec.id or "")
  local specMeta = type(spec.meta) == "table" and spec.meta or {}
  local specKey = tostring(specMeta.specId or moduleId)
  local metaByPort = CONTROL_PORT_META[specKey] or CONTROL_PORT_META[moduleId] or {}
  local dynamicInfo = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local dynamicEntry = type(dynamicInfo) == "table" and dynamicInfo[moduleId] or nil
  local ports = spec.ports or {}

  for _, key in ipairs({ "inputs", "outputs" }) do
    local list = type(ports[key]) == "table" and ports[key] or {}
    for i = 1, #list do
      local port = list[i]
      if tostring(port.type or "") == "control" then
        local portId = tostring(port.id or "")
        local fallbackMeta = metaByPort[portId] or {}
        local direction = tostring(port.direction or fallbackMeta.direction or (key == "inputs" and "target" or "source"))
        local scope = tostring(port.scope or fallbackMeta.scope or "global")
        local signalKind = tostring(port.signalKind or fallbackMeta.signalKind or "scalar")
        local domain = tostring(port.domain or fallbackMeta.domain or "normalized")
        local displayName = tostring(port.displayName or fallbackMeta.displayName or port.label or portId)
        out[#out + 1] = {
          id = string.format("%s.%s", moduleId, portId),
          direction = direction,
          scope = scope,
          signalKind = signalKind,
          domain = domain,
          provider = "rack-spec",
          owner = moduleId,
          displayName = displayName,
          available = true,
          min = port.min ~= nil and port.min or fallbackMeta.min,
          max = port.max ~= nil and port.max or fallbackMeta.max,
          default = port.default ~= nil and port.default or fallbackMeta.default,
          meta = {
            moduleId = moduleId,
            specId = specKey,
            slotIndex = type(dynamicEntry) == "table" and dynamicEntry.slotIndex or nil,
            portId = portId,
            portLabel = port.label,
            portType = port.type,
            kind = direction == "target" and "control-target" or "control-source",
          },
        }
      end
    end
  end
end

local function emitParamEndpoints(spec, out)
  local moduleId = tostring(spec.id or "")
  local params = spec.ports and spec.ports.params or {}
  for i = 1, #params do
    local param = params[i]
    local path = tostring(param.path or "")
    if path ~= "" then
      local signalKind = tostring(param.signalKind or inferSignalKind(param))
      local domain = tostring(param.domain or inferDomain(param))
      local scope = tostring(param.scope or inferScope(moduleId, path))
      local displayName = tostring(param.displayName or param.label or path)

      if param.input == true then
        out[#out + 1] = {
          id = path,
          direction = "target",
          scope = scope,
          signalKind = signalKind,
          domain = domain,
          provider = "rack-spec",
          owner = moduleId,
          displayName = displayName,
          available = true,
          min = param.min,
          max = param.max,
          default = param.default,
          enumOptions = copyArray(param.options),
          meta = {
            moduleId = moduleId,
            paramId = param.id,
            path = path,
            kind = "param-target",
          },
        }
      end

      if param.output == true then
        out[#out + 1] = {
          id = "param_out:" .. path,
          direction = "source",
          scope = scope,
          signalKind = signalKind == "stepped" and "scalar_unipolar" or signalKind,
          domain = domain,
          provider = "rack-spec",
          owner = moduleId,
          displayName = displayName .. " Out",
          available = true,
          min = param.min,
          max = param.max,
          default = param.default,
          enumOptions = copyArray(param.options),
          meta = {
            moduleId = moduleId,
            paramId = param.id,
            path = path,
            kind = "param-source",
          },
        }
      end
    end
  end
end

function M.collect(ctx, options)
  local out = {}
  local specsById = RackSpecs.rackModuleSpecById()
  local orderedIds = {}
  for moduleId in pairs(specsById) do
    orderedIds[#orderedIds + 1] = moduleId
  end
  table.sort(orderedIds, function(a, b)
    return tostring(a or "") < tostring(b or "")
  end)
  for i = 1, #orderedIds do
    local spec = specsById[orderedIds[i]]
    emitControlEndpoints(spec, out)
    emitParamEndpoints(spec, out)
  end
  return out
end

return M

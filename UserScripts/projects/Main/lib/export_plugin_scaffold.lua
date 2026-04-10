local ExportPluginScaffold = {}

local Utils = require("utils")
local ParameterBinder = require("parameter_binder")

local function registerSchema(ctx, schema)
  if type(schema) ~= "table" or not (ctx and ctx.params and ctx.params.register) then
    return
  end

  for i = 1, #schema do
    local entry = schema[i]
    if type(entry) == "table" and entry.path and entry.spec then
      ctx.params.register(entry.path, entry.spec)
    end
  end
end

local function mergeTables(dst, src)
  local out = type(dst) == "table" and dst or {}
  if type(src) ~= "table" then
    return out
  end
  for key, value in pairs(src) do
    out[key] = value
  end
  return out
end

function ExportPluginScaffold.buildSingleRackModulePlugin(ctx, options)
  options = type(options) == "table" and options or {}

  local slotIndex = math.max(1, math.floor(tonumber(options.slotIndex) or 1))
  local schemaSpecId = tostring(options.schemaSpecId or "")
  local moduleRequire = tostring(options.moduleRequire or "")
  local description = tostring(options.description or "Manifold Export")
  local applyDefaults = type(options.applyDefaults) == "function" and options.applyDefaults or function() end
  local schemaOptions = type(options.schemaOptions) == "table" and options.schemaOptions or {}
  local extraDepsFactory = type(options.extraDepsFactory) == "function" and options.extraDepsFactory or nil

  if moduleRequire == "" then
    error("export_plugin_scaffold: moduleRequire is required")
  end
  if schemaSpecId == "" then
    error("export_plugin_scaffold: schemaSpecId is required")
  end

  local rackModule = require(moduleRequire)

  local input = ctx.primitives.PassthroughNode.new(2, 0)
  local output = ctx.primitives.PassthroughNode.new(2)
  if ctx.graph.markInput then
    ctx.graph.markInput(input)
  end
  if ctx.graph.markMonitor then
    ctx.graph.markMonitor(output)
  end

  local slots = {}
  local moduleDeps = {
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    applyDefaults = applyDefaults,
  }
  if extraDepsFactory ~= nil then
    moduleDeps = mergeTables(moduleDeps, extraDepsFactory(ctx, slots) or {})
  end
  local module = rackModule.create(moduleDeps)

  local slot = module.createSlot(slotIndex)

  if slot and slot.input then
    ctx.graph.connect(input, slot.input)
  end
  if slot and slot.node then
    ctx.graph.connect(input, slot.node)
  end
  if slot and slot.output then
    ctx.graph.connect(slot.output, output)
  elseif slot and slot.out then
    ctx.graph.connect(slot.out, output)
  elseif slot and slot.node then
    ctx.graph.connect(slot.node, output)
  else
    error("export_plugin_scaffold: slot has no routable node/output")
  end

  registerSchema(ctx, ParameterBinder.buildDynamicSlotSchema(schemaSpecId, slotIndex, schemaOptions))

  return {
    description = description,
    input = input,
    output = output,
    onParamChange = function(path, value)
      module.applyPath(path, value)
    end,
  }
end

return ExportPluginScaffold

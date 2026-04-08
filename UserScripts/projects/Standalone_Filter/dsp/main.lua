local function dirname(path)
  return (tostring(path or ""):gsub("/+$", ""):match("^(.*)/[^/]+$") or ".")
end

local function join(...)
  local parts = { ... }
  local out = ""
  for i = 1, #parts do
    local part = tostring(parts[i] or "")
    if part ~= "" then
      if out == "" then
        out = part
      else
        out = out:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
      end
    end
  end
  return out
end

local function appendPackageRoot(root)
  if type(root) ~= "string" or root == "" then
    return
  end
  local entry = root .. "/?.lua;" .. root .. "/?/init.lua"
  local current = tostring(package.path or "")
  if not current:find(entry, 1, true) then
    package.path = current == "" and entry or (current .. ";" .. entry)
  end
end

local scriptDir = tostring(__manifoldDspScriptDir or ".")
local projectRoot = dirname(scriptDir)
local mainRoot = join(projectRoot, "../Main")
appendPackageRoot(join(mainRoot, "lib"))
appendPackageRoot(join(mainRoot, "ui"))
appendPackageRoot(join(mainRoot, "dsp"))

local Utils = require("utils")
local ParameterBinder = require("parameter_binder")
local RackFilterModule = require("rack_modules.filter")

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

function buildPlugin(ctx)
  local input = ctx.primitives.PassthroughNode.new(2, 0)
  local output = ctx.primitives.PassthroughNode.new(2)
  if ctx.graph.markInput then
    ctx.graph.markInput(input)
  end
  if ctx.graph.markMonitor then
    ctx.graph.markMonitor(output)
  end

  local slots = {}
  local module = RackFilterModule.create({
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    applyDefaults = function(node)
      node:setMode(0)
      node:setCutoff(3200.0)
      node:setResonance(0.75)
      if node.setDrive then node:setDrive(1.0) end
      if node.setMix then node:setMix(1.0) end
    end,
  })

  local slot = module.createSlot(1)
  ctx.graph.connect(input, slot.node)
  ctx.graph.connect(slot.node, output)

  registerSchema(ctx, ParameterBinder.buildDynamicSlotSchema("filter", 1, {}))

  return {
    description = "Manifold Filter",
    input = input,
    output = output,
    onParamChange = function(path, value)
      module.applyPath(path, value)
    end,
  }
end

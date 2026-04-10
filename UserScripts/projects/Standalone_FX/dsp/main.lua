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

local function makeConnectMixerInput(ctx)
  return function(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    ctx.graph.connect(source, mixer, 0, (inputIndex - 1) * 2)
  end
end

local scriptDir = tostring(__manifoldDspScriptDir or ".")
local projectRoot = dirname(scriptDir)
local mainRoot = join(projectRoot, "../Main")
appendPackageRoot(join(mainRoot, "lib"))
appendPackageRoot(join(mainRoot, "ui"))
appendPackageRoot(join(mainRoot, "dsp"))

local ExportPluginScaffold = require("export_plugin_scaffold")
local ParameterBinder = require("parameter_binder")
local FxDefs = require("fx_definitions")
local FxSlot = require("fx_slot")

function buildPlugin(ctx)
  local maxFxParams = ParameterBinder.MAX_FX_PARAMS or 5
  local defaultFxParamValues = { 0.5, 0.5, 0.2, 0.6, 0.4 }
  return ExportPluginScaffold.buildSingleRackModulePlugin(ctx, {
    description = "Manifold Effect",
    moduleRequire = "rack_modules.fx",
    schemaSpecId = "fx",
    slotIndex = 1,
    schemaOptions = {
      fxOptionCount = #FxDefs.FX_OPTIONS,
      maxFxParams = maxFxParams,
      fxParamDefaults = defaultFxParamValues,
    },
    extraDepsFactory = function(runtimeCtx)
      local fxDefs = FxDefs.buildFxDefs(runtimeCtx.primitives, runtimeCtx.graph)
      return {
        FxSlot = FxSlot,
        fxDefs = fxDefs,
        fxCtx = {
          primitives = runtimeCtx.primitives,
          graph = runtimeCtx.graph,
          connectMixerInput = makeConnectMixerInput(runtimeCtx),
        },
        maxFxParams = maxFxParams,
      }
    end,
  })
end

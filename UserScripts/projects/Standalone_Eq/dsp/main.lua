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

local ExportPluginScaffold = require("export_plugin_scaffold")

function buildPlugin(ctx)
  return ExportPluginScaffold.buildSingleRackModulePlugin(ctx, {
    description = "Manifold EQ8",
    moduleRequire = "rack_modules.eq",
    schemaSpecId = "eq",
    slotIndex = 1,
    applyDefaults = function(node)
      node:setMix(1.0)
      node:setOutput(0.0)
      for i = 1, 8 do
        node:setBandEnabled(i, false)
      end
    end,
  })
end

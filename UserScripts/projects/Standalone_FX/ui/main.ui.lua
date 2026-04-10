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

local projectRoot = tostring(__manifoldProjectRoot or dirname(__manifoldProjectManifest or ""))
local mainRoot = join(projectRoot, "../Main")
appendPackageRoot(join(mainRoot, "ui"))
appendPackageRoot(join(mainRoot, "lib"))

local ExportPluginShell = require("export_plugin_shell")

return ExportPluginShell.build({
  rootId = "standalone_fx_root",
  title = "Effect",
  accent = 0xff4ade80,
  width = 472,
  height = 220,
  headerHeight = 12,
  contentWidth = 472,
  contentHeight = 208,
  moduleId = "fx_component",
  moduleBehavior = "../Main/ui/behaviors/fx_slot.lua",
  moduleRef = "../Main/ui/components/export_fx_slot.ui.lua",
  moduleProps = {
    instanceNodeId = "standalone_fx_1",
    paramBase = "/plugin/params",
  },
})

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

return {
  id = "standalone_filter_root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 472,
  h = 208,
  style = {
    bg = 0xff0b1220,
  },
  components = {
    {
      id = "filter_component",
      x = 0,
      y = 0,
      w = 472,
      h = 208,
      layout = { mode = "hybrid", left = 0, top = 0, right = 0, bottom = 0 },
      behavior = "../Main/ui/behaviors/filter.lua",
      ref = "../Main/ui/components/filter.ui.lua",
      props = {
        instanceNodeId = "standalone_filter_1",
        paramBase = "/midi/synth/rack/filter/1",
        specId = "filter",
      },
    },
  },
}

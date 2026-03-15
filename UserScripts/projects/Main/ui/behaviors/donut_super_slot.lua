local M = {}

local cachedModule = nil
local cachedModulePath = ""

local function loadProjectSuperSlotModule(project)
  local root = project and project.root or ""
  if type(root) ~= "string" or root == "" then
    return nil, "missing project root"
  end

  local modulePath = root .. "/dsp/super_slot.lua"
  if cachedModule ~= nil and cachedModulePath == modulePath then
    return cachedModule
  end

  local chunk, loadErr = loadfile(modulePath)
  if not chunk then
    return nil, "failed to load project super slot module: " .. tostring(loadErr)
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, "failed to execute project super slot module: " .. tostring(result)
  end
  if type(result) ~= "table" or type(result.ensureLoaded) ~= "function" then
    return nil, "project super slot module did not expose ensureLoaded(project, selections, force)"
  end

  cachedModule = result
  cachedModulePath = modulePath
  return cachedModule
end

function M.ensureLoaded(project, selections, force)
  local delegate, err = loadProjectSuperSlotModule(project)
  if not delegate then
    return false, err
  end
  return delegate.ensureLoaded(project, selections, force)
end

return M

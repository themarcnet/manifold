-- State Manager Module
-- Extracted from midisynth.lua
-- Handles state persistence, defaults, runtime state path management

local M = {}

-- Dependencies (provided via init)
local deps = {}

function M.runtimeStatePath()
  local root = deps.projectRoot and deps.projectRoot() or ""
  if root == "" then
    return ""
  end
  return root .. "/editor/runtime_state.lua"
end

M.loadRuntimeState = function()
  local path = M.runtimeStatePath()
  if path == "" or type(deps.readTextFile) ~= "function" then
    return {}
  end
  local text = deps.readTextFile(path)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  local chunk, err = load(text, "midi_runtime_state", "t", {})
  if not chunk then
    return {}
  end
  local ok, state = pcall(chunk)
  if not ok or type(state) ~= "table" then
    return {}
  end
  return state
end

M.saveRuntimeState = function(state)
  local path = M.runtimeStatePath()
  if path == "" or type(deps.writeTextFile) ~= "function" then
    return false
  end

  local rackState = state.rackState or {
    viewMode = state.rackViewMode,
    densityMode = state.rackDensityMode,
    utilityDock = {
      mode = state.utilityDockMode,
      collapsed = state.keyboardCollapsed,
    },
    modules = state.rackModules or {},
  }

  local lines = {}
  table.insert(lines, "-- Auto-generated runtime state")
  table.insert(lines, "return {")
  table.insert(lines, "  rackViewMode = " .. tostring(state.rackViewMode or 0) .. ",")
  table.insert(lines, "  rackDensityMode = " .. tostring(state.rackDensityMode or 0) .. ",")
  table.insert(lines, "  utilityDockMode = " .. tostring(state.utilityDockMode or "arrange") .. ",")
  table.insert(lines, "  keyboardCollapsed = " .. tostring(state.keyboardCollapsed or false) .. ",")
  table.insert(lines, "}")

  local content = table.concat(lines, "\n")
  return deps.writeTextFile(path, content)
end

function M.ensureUtilityDockState(ctx)
  local rackState = ctx and ctx._rackState
  local utilityDock = rackState and rackState.utilityDock or nil
  local defaultDock = { mode = "arrange", collapsed = false }
  
  if type(utilityDock) ~= "table" then
    utilityDock = defaultDock
  end
  
  local mode = utilityDock.mode
  if type(mode) ~= "string" or (mode ~= "arrange" and mode ~= "stack") then
    mode = "arrange"
  end
  
  local collapsed = utilityDock.collapsed
  if type(collapsed) ~= "boolean" then
    collapsed = false
  end
  
  ctx._utilityDockMode = mode
  ctx._utilityDockCollapsed = collapsed
  
  return {
    mode = mode,
    collapsed = collapsed,
  }
end

function M.getUtilityDockState(ctx)
  return {
    mode = ctx._utilityDockMode or "arrange",
    collapsed = ctx._utilityDockCollapsed or false,
  }
end

function M.setUtilityDockMode(ctx, modeKey)
  local validModes = { arrange = true, stack = true }
  local mode = validModes[modeKey] and modeKey or "arrange"
  ctx._utilityDockMode = mode
  
  if ctx._rackState and ctx._rackState.utilityDock then
    ctx._rackState.utilityDock.mode = mode
  end
  
  return mode
end

function M.persistDockUiState(ctx)
  if not deps.setPath then return end
  
  local dockState = M.getUtilityDockState(ctx)
  deps.setPath("/midi/synth/ui/utilityDockMode", dockState.mode)
  deps.setPath("/midi/synth/ui/keyboardCollapsed", dockState.collapsed)
end

function M.loadSavedState(ctx)
  local state = {}
  
  if type(deps.readTextFile) == "function" then
    local root = deps.projectRoot and deps.projectRoot() or ""
    if root ~= "" then
      local path = root .. "/editor/midisynth_state.lua"
      local content = deps.readTextFile(path)
      if type(content) == "string" and content ~= "" then
        local chunk, err = load(content, "midisynth_state", "t", {})
        if chunk then
          local ok, loaded = pcall(chunk)
          if ok and type(loaded) == "table" then
            state = loaded
          end
        end
      end
    end
  end
  
  state.rackState = state.rackState or {}
  state.rackConnections = state.rackConnections or {}
  
  ctx._rackState = state.rackState
  ctx._rackConnections = state.rackConnections
  ctx._utilityDock = state.rackState and state.rackState.utilityDock
  
  M.ensureUtilityDockState(ctx)
  
  _G.__midiSynthRackState = ctx._rackState
  _G.__midiSynthRackConnections = ctx._rackConnections
  
  return state
end

function M.resetToDefaults(ctx)
  local MidiSynthRackSpecs = deps.MidiSynthRackSpecs
  local defaultRackState = MidiSynthRackSpecs and MidiSynthRackSpecs.defaultRackState and MidiSynthRackSpecs.defaultRackState() or nil
  local defaultModules = defaultRackState and defaultRackState.modules or {}
  
  ctx._rackState = {
    viewMode = defaultRackState and defaultRackState.viewMode or 0,
    densityMode = defaultRackState and defaultRackState.densityMode or 0,
    utilityDock = defaultRackState and defaultRackState.utilityDock or { mode = "arrange", collapsed = false },
    modules = defaultModules,
  }
  
  ctx._rackConnections = {}
  ctx._utilityDock = ctx._rackState.utilityDock
  
  M.ensureUtilityDockState(ctx)
  
  _G.__midiSynthRackState = ctx._rackState
  _G.__midiSynthRackConnections = ctx._rackConnections
  
  ctx._lastEvent = "Reset to defaults"
  
  return ctx._rackState
end

function M.attach(midiSynth)
  deps.midiSynth = midiSynth
  -- Expose state functions to host
  midiSynth.runtimeStatePath = M.runtimeStatePath
  midiSynth.loadRuntimeState = M.loadRuntimeState
  midiSynth.saveRuntimeState = M.saveRuntimeState
  midiSynth.ensureUtilityDockState = M.ensureUtilityDockState
  midiSynth.getUtilityDockState = M.getUtilityDockState
  midiSynth.setUtilityDockMode = M.setUtilityDockMode
  midiSynth.persistDockUiState = M.persistDockUiState
  midiSynth.loadSavedState = M.loadSavedState
  midiSynth.resetToDefaults = M.resetToDefaults
end

function M.init(options)
  options = options or {}
  deps.projectRoot = options.projectRoot
  deps.readTextFile = options.readTextFile
  deps.writeTextFile = options.writeTextFile
  deps.setPath = options.setPath
  deps.MidiSynthRackSpecs = options.MidiSynthRackSpecs or require("behaviors.rack_midisynth_specs")
end

return M

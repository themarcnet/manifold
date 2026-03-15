-- Project-owned shared Super slot loader for Main.
--
-- The slot now loads a real project DSP file (`dsp/super_slot_runtime.lua`) and
-- then drives its select params. This kills the previous generated-string hack
-- while keeping one shared slot backing all Main tabs.

local M = {}

local DSP_SLOT = "super"
local EFFECT_IDS = {
  "bypass",
  "chorus",
  "phaser",
  "bitcrusher",
  "waveshaper",
  "filter",
  "svf",
  "reverb",
  "shimmer",
  "stereodelay",
  "reversedelay",
  "multitap",
  "pitchshift",
  "granulator",
  "ringmod",
  "formant",
  "eq",
  "compressor",
  "limiter",
  "transient",
  "widener",
}

local function effectIndex(effectId)
  for i, id in ipairs(EFFECT_IDS) do
    if id == effectId then
      return i - 1
    end
  end
  return 0
end

local function selectionKey(selections)
  local layers = selections and selections.layers or {}
  return table.concat({
    selections and selections.vocal or "bypass",
    layers[1] or "bypass",
    layers[2] or "bypass",
    layers[3] or "bypass",
    layers[4] or "bypass",
  }, "|")
end

local function setPath(path, value)
  if type(setParam) == "function" then
    local ok, handled = pcall(setParam, path, value)
    if ok and handled == true then
      return true
    end
  end
  if type(command) == "function" then
    local ok = pcall(command, "SET", path, tostring(value))
    if ok then
      return true
    end
  end
  return false
end

local function applySelections(selections)
  local vocalId = selections and selections.vocal or "bypass"
  if not setPath("/core/super/vocal/slot/select", effectIndex(vocalId)) then
    return false, "failed to set vocal slot selection"
  end

  local layers = selections and selections.layers or {}
  for i = 0, 3 do
    local effectId = layers[i + 1] or "bypass"
    local path = string.format("/core/super/layer/%d/fx/select", i)
    if not setPath(path, effectIndex(effectId)) then
      return false, "failed to set layer slot selection for layer " .. tostring(i)
    end
  end

  M._loadedKey = selectionKey(selections or {})
  return true
end

function M.ensureLoaded(project, selections, force)
  if type(loadDspScriptInSlot) ~= "function" then
    return false, "loadDspScriptInSlot unavailable"
  end

  local root = project and project.root or ""
  if type(root) ~= "string" or root == "" then
    return false, "missing project root"
  end

  local runtimePath = root .. "/dsp/super_slot_runtime.lua"
  local loaded = false
  if type(isDspSlotLoaded) == "function" then
    local ok, result = pcall(isDspSlotLoaded, DSP_SLOT)
    loaded = ok and result == true
  end

  if type(setDspSlotPersistOnUiSwitch) == "function" then
    pcall(setDspSlotPersistOnUiSwitch, DSP_SLOT, false)
  end

  local mustLoad = (not loaded) or M._loadedPath ~= runtimePath
  if mustLoad then
    local ok, result = pcall(loadDspScriptInSlot, runtimePath, DSP_SLOT)
    if not ok then
      return false, tostring(result)
    end
    if result ~= true then
      return false, "slot load failed"
    end
    M._loadedPath = runtimePath
  elseif force ~= true and M._loadedKey == selectionKey(selections or {}) then
    return true
  end

  return applySelections(selections or {})
end

return M

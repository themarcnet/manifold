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

local function setOverrideStyle(componentId)
  return {
    [componentId] = {
      style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
      props = { interceptsMouse = false },
    },
  }
end

local function renameShellChildren(shell, module)
  if type(shell) ~= "table" or type(shell.children) ~= "table" then
    return shell
  end
  for i = 1, #shell.children do
    local child = shell.children[i]
    local id = tostring(type(child) == "table" and child.id or "")
    if id == "sizeBadge" then
      child.id = module.sizeBadgeId
    elseif id == "nodeNameLabel" then
      child.id = module.nodeNameLabelId
    elseif id == "deleteButton" then
      child.id = module.deleteButtonId
    elseif id == "resizeToggle" then
      child.id = module.resizeButtonId
    elseif id == "accent" then
      child.id = module.accentId
    end
  end
  return shell
end

local projectRoot = tostring(__manifoldProjectRoot or dirname(__manifoldProjectManifest or ""))
local mainRoot = join(projectRoot, "../Main")
appendPackageRoot(join(projectRoot, "lib"))
appendPackageRoot(join(mainRoot, "ui"))
appendPackageRoot(join(mainRoot, "lib"))

local RackModuleShell = require("components.rack_module_shell")
local Registry = require("module_host_registry")
local modules = Registry.modules()

local moduleOptions = {}
for i = 1, #modules do
  moduleOptions[i] = modules[i].label
end

local shells = {
  {
    id = "script_workspace",
    type = "Panel",
    x = 16,
    y = 520,
    w = 1020,
    h = 180,
    style = {
      bg = 0x14000000,
      border = 0x221f2b4d,
      borderWidth = 1,
      radius = 0,
    },
    props = { interceptsMouse = false },
    children = {
      {
        id = "workspace_title",
        type = "Label",
        x = 14,
        y = 10,
        w = 240,
        h = 18,
        props = { text = "Plugin editor" },
        style = { colour = 0xffcbd5e1, fontSize = 11 },
      },
      {
        id = "workspace_status",
        type = "Label",
        x = 260,
        y = 10,
        w = 520,
        h = 18,
        props = { text = "No file selected" },
        style = { colour = 0xff64748b, fontSize = 10 },
      },
      {
        id = "workspace_editor_tab",
        type = "Button",
        x = 810,
        y = 8,
        w = 74,
        h = 22,
        props = { label = "Editor" },
        style = { bg = 0xff1e293b, colour = 0xffe2e8f0, fontSize = 10 },
      },
      {
        id = "workspace_graph_tab",
        type = "Button",
        x = 888,
        y = 8,
        w = 82,
        h = 22,
        props = { label = "DSP Graph" },
        style = { bg = 0xff1e293b, colour = 0xffe2e8f0, fontSize = 10 },
      },
      {
        id = "workspace_save_button",
        type = "Button",
        x = 974,
        y = 8,
        w = 44,
        h = 22,
        props = { label = "Save" },
        style = { bg = 0xff0f766e, colour = 0xffecfeff, fontSize = 10 },
      },
      {
        id = "workspace_reload_button",
        type = "Button",
        x = 1022,
        y = 8,
        w = 60,
        h = 22,
        props = { label = "Reload" },
        style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 10 },
      },
      {
        id = "workspace_path",
        type = "Label",
        x = 14,
        y = 34,
        w = 1000,
        h = 18,
        props = { text = "" },
        style = { colour = 0xff94a3b8, fontSize = 10 },
      },
      {
        id = "workspace_editor_host_frame",
        type = "Panel",
        x = 14,
        y = 58,
        w = 1004,
        h = 108,
        style = { bg = 0xff0b1220, border = 0xff243041, borderWidth = 1, radius = 0 },
      },
      {
        id = "workspace_graph_canvas",
        type = "Panel",
        x = 14,
        y = 58,
        w = 1004,
        h = 108,
        style = { bg = 0xff0b1220, border = 0xff243041, borderWidth = 1, radius = 0 },
      },
      {
        id = "workspace_graph_empty",
        type = "Label",
        x = 40,
        y = 96,
        w = 720,
        h = 22,
        props = { text = "Select a DSP file from the sidebar to inspect its graph." },
        style = { colour = 0xff64748b, fontSize = 11 },
      },
    },
  },
}

for i = 1, #modules do
  local module = modules[i]
  local size = Registry.sizePixels(module.defaultSize)
  local shell = RackModuleShell({
    id = module.shellId,
    layout = false,
    x = 0,
    y = 0,
    w = size.w,
    h = size.h,
    sizeKey = module.defaultSize,
    accentColor = module.accentColor,
    nodeName = module.label,
    componentRef = module.componentPath,
    componentId = module.componentId,
    componentBehavior = module.behaviorPath,
    componentProps = {
      instanceNodeId = module.instanceNodeId,
      paramBase = module.paramBase,
      specId = module.id,
      sizeKey = module.defaultSize,
    },
    componentOverrides = setOverrideStyle(module.componentId),
  })
  shell = renameShellChildren(shell, module)
  shell.props = shell.props or {}
  shell.props.visible = true
  shells[#shells + 1] = {
    id = module.displayId,
    type = "Panel",
    x = 0,
    y = 0,
    w = size.w,
    h = size.h,
    style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
    props = { interceptsMouse = false, visible = false },
    children = { shell },
  }
end

return {
  id = "rack_host_root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1440,
  h = 900,
  style = {
    bg = 0xff07111d,
  },
  behavior = "ui/behaviors/main.lua",
  children = {
    {
      id = "sidebar",
      type = "Panel",
      x = 0,
      y = 0,
      w = 340,
      h = 900,
      layout = { mode = "hybrid", left = 0, top = 0, bottom = 0, width = 340 },
      style = { bg = 0xff0d1726, border = 0xff1f2b3d, borderWidth = 1, radius = 0 },
      children = {
        { id = "title", type = "Label", x = 20, y = 18, w = 250, h = 22, props = { text = "Rack Module Host" }, style = { colour = 0xfff8fafc, fontSize = 18 } },
        { id = "subtitle", type = "Label", x = 20, y = 44, w = 290, h = 42, props = { text = "Loads Main rack modules in a proper standalone sandbox with real aspect-ratio-aware presentation, audio routing, and MIDI-driven auditioning.", wordWrap = true }, style = { colour = 0xff94a3b8, fontSize = 10 } },

        { id = "midi_input_label", type = "Label", x = 20, y = 104, w = 120, h = 14, props = { text = "MIDI input" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
        { id = "midi_input_dropdown", type = "Dropdown", x = 20, y = 124, w = 300, h = 28, props = { options = { "None (Disabled)" }, selected = 1, max_visible_rows = 10 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
        { id = "midi_device_value", type = "Label", x = 20, y = 158, w = 300, h = 18, props = { text = "Input: None (Disabled)" }, style = { colour = 0xff60a5fa, fontSize = 10 } },

        { id = "module_label", type = "Label", x = 20, y = 194, w = 120, h = 14, props = { text = "Module" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
        { id = "module_selector", type = "Dropdown", x = 20, y = 214, w = 300, h = 28, props = { options = moduleOptions, selected = 1, max_visible_rows = 12 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
        { id = "module_status", type = "Label", x = 20, y = 250, w = 300, h = 48, props = { text = "", wordWrap = true }, style = { colour = 0xff60a5fa, fontSize = 10 } },

        { id = "view_label", type = "Label", x = 20, y = 310, w = 120, h = 14, props = { text = "View" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
        { id = "view_selector", type = "Dropdown", x = 20, y = 330, w = 140, h = 28, props = { options = { "Performance", "Patch" }, selected = 1, max_visible_rows = 2 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },

        { id = "size_label", type = "Label", x = 20, y = 372, w = 120, h = 14, props = { text = "Display size" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
        { id = "size_selector", type = "Dropdown", x = 20, y = 392, w = 160, h = 28, props = { options = { "1x1" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
        { id = "size_note", type = "Label", x = 188, y = 394, w = 132, h = 40, props = { text = "Actual rack modes only: 1x1 or 1x2.", wordWrap = true }, style = { colour = 0xff94a3b8, fontSize = 9 } },

        { id = "sidebar_params_tab", type = "Button", x = 20, y = 442, w = 92, h = 24, props = { label = "Params" }, style = { bg = 0xff1d4ed8, colour = 0xffeff6ff, fontSize = 10 } },
        { id = "sidebar_files_tab", type = "Button", x = 118, y = 442, w = 92, h = 24, props = { label = "Files" }, style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 10 } },
        { id = "input_a_title", type = "Label", x = 224, y = 446, w = 96, h = 14, props = { text = "Host params" }, style = { colour = 0xfff8fafc, fontSize = 11 } },
        { id = "input_a_mode", type = "Dropdown", x = 20, y = 468, w = 300, h = 26, props = { options = { "External", "Silence", "Sine", "Saw", "Square", "Pulse", "Noise" }, selected = 3, max_visible_rows = 7 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
        { id = "input_a_pitch", type = "Slider", x = 20, y = 504, w = 300, h = 22, props = { min = 24, max = 84, step = 1, value = 60, label = "Pitch", compact = true, showValue = true }, style = { colour = 0xff38bdf8, bg = 0xff122033, fontSize = 9 } },
        { id = "input_a_level", type = "Slider", x = 20, y = 532, w = 300, h = 22, props = { min = 0, max = 1, step = 0.01, value = 0.65, label = "Level", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff0d1b28, fontSize = 9 } },

        {
          id = "input_b_group",
          type = "Panel",
          x = 20,
          y = 580,
          w = 300,
          h = 112,
          style = { bg = 0x00000000 },
          children = {
            { id = "input_b_title", type = "Label", x = 0, y = 0, w = 160, h = 14, props = { text = "Input B / Aux" }, style = { colour = 0xfff8fafc, fontSize = 11 } },
            { id = "input_b_mode", type = "Dropdown", x = 0, y = 22, w = 300, h = 26, props = { options = { "External", "Silence", "Sine", "Saw", "Square", "Pulse", "Noise" }, selected = 4, max_visible_rows = 7 }, style = { bg = 0xff2a180f, colour = 0xffffd3b0, radius = 0, fontSize = 10 } },
            { id = "input_b_pitch", type = "Slider", x = 0, y = 58, w = 300, h = 22, props = { min = 24, max = 84, step = 1, value = 67, label = "Pitch", compact = true, showValue = true }, style = { colour = 0xfffb923c, bg = 0xff2b160d, fontSize = 9 } },
            { id = "input_b_level", type = "Slider", x = 0, y = 86, w = 300, h = 22, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Level", compact = true, showValue = true }, style = { colour = 0xffff9a62, bg = 0xff2a150d, fontSize = 9 } },
          },
        },

        { id = "routing_hint", type = "Label", x = 20, y = 716, w = 300, h = 84, props = { text = "Audio modules use Input A. Blend uses Input A + Input B. Sample capture records the selected source, including external host audio when Source is Input and Input A is External.", wordWrap = true }, style = { colour = 0xff94a3b8, fontSize = 10 } },
        { id = "module_note", type = "Label", x = 20, y = 804, w = 300, h = 76, props = { text = "", wordWrap = true }, style = { colour = 0xff64748b, fontSize = 10 } },
        {
          id = "sidebar_files_panel",
          type = "Panel",
          x = 20,
          y = 472,
          w = 300,
          h = 408,
          style = { bg = 0xff0b1220, border = 0xff243041, borderWidth = 1, radius = 0 },
          props = { visible = false },
          children = {
            { id = "sidebar_files_title", type = "Label", x = 12, y = 10, w = 276, h = 16, props = { text = "Plugin files" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
            { id = "sidebar_files_hint", type = "Label", x = 12, y = 30, w = 276, h = 36, props = { text = "Select a file to load it into the editor below. DSP files also show a graph tab.", wordWrap = true }, style = { colour = 0xff64748b, fontSize = 10 } },
            { id = "sidebar_files_tree_panel", type = "Panel", x = 12, y = 74, w = 276, h = 322, style = { bg = 0xff0f1726, border = 0xff243041, borderWidth = 1, radius = 0 } },
          },
        },
      },
    },
    {
      id = "viewport",
      type = "Panel",
      x = 352,
      y = 0,
      w = 1088,
      h = 900,
      layout = { mode = "hybrid", left = 352, top = 0, right = 0, bottom = 0 },
      style = { bg = 0xff0a1220 },
      children = {
        { id = "viewport_title", type = "Label", x = 24, y = 18, w = 420, h = 22, props = { text = "Module View" }, style = { colour = 0xfff8fafc, fontSize = 18 } },
        { id = "viewport_subtitle", type = "Label", x = 24, y = 44, w = 860, h = 18, props = { text = "Selected rack module rendered using the real rack shell and the real 1x1 / 1x2 layout logic. Patch view uses the same patchbay surface style as Main." }, style = { colour = 0xff94a3b8, fontSize = 10 } },
        {
          id = "module_surface",
          type = "Panel",
          x = 24,
          y = 78,
          w = 1040,
          h = 798,
          layout = { mode = "hybrid", left = 24, top = 78, right = 24, bottom = 24 },
          style = { bg = 0xff0f1726, border = 0xff1f2937, borderWidth = 1, radius = 0 },
          children = shells,
        },
      },
    },
  },
}

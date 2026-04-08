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
        id = "editor_tabs",
        type = "TabHost",
        x = 14,
        y = 8,
        w = 820,
        h = 24,
        props = {
          activeIndex = 1,
          tabBarHeight = 26,
          tabSizing = "fill",
        },
        style = {
          bg = 0xff111827,
          border = 0xff334155,
          borderWidth = 1,
          radius = 0,
          tabBarBg = 0xff111827,
          tabBg = 0xff334155,
          activeTabBg = 0xff2563eb,
          textColour = 0xffe2e8f0,
          activeTextColour = 0xffffffff,
        },
        children = {
          { id = "editor_page_1", type = "TabPage", props = { title = "Tab 1" }, style = { bg = 0x00000000 } },
          { id = "editor_page_2", type = "TabPage", props = { title = "Tab 2" }, style = { bg = 0x00000000 } },
          { id = "editor_page_3", type = "TabPage", props = { title = "Tab 3" }, style = { bg = 0x00000000 } },
          { id = "editor_page_4", type = "TabPage", props = { title = "Tab 4" }, style = { bg = 0x00000000 } },
          { id = "editor_page_5", type = "TabPage", props = { title = "Tab 5" }, style = { bg = 0x00000000 } },
          { id = "editor_page_6", type = "TabPage", props = { title = "Tab 6" }, style = { bg = 0x00000000 } },
          { id = "editor_page_7", type = "TabPage", props = { title = "Tab 7" }, style = { bg = 0x00000000 } },
          { id = "editor_page_8", type = "TabPage", props = { title = "Tab 8" }, style = { bg = 0x00000000 } },
        },
      },
      {
        id = "workspace_status",
        type = "Label",
        x = 14,
        y = 34,
        w = 860,
        h = 18,
        props = { text = "No file selected" },
        style = { colour = 0xff94a3b8, fontSize = 10 },
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
        id = "workspace_editor_host_frame",
        type = "Panel",
        x = 14,
        y = 58,
        w = 1004,
        h = 108,
        style = { bg = 0xff0b1220, border = 0xff243041, borderWidth = 1, radius = 0 },
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

shells[#shells + 1] = {
  id = "plugin_graph_canvas",
  type = "Panel",
  x = 0,
  y = 0,
  w = 472,
  h = 208,
  style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
  props = { interceptsMouse = true, visible = false },
}

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

        {
          id = "sidebar_tabs",
          type = "TabHost",
          x = 20,
          y = 96,
          w = 300,
          h = 784,
          props = {
            activeIndex = 1,
            tabBarHeight = 26,
            tabSizing = "fill",
          },
          style = {
            bg = 0xff0b1220,
            border = 0xff243041,
            borderWidth = 1,
            radius = 0,
            tabBarBg = 0xff0f1726,
            tabBg = 0xff1e293b,
            activeTabBg = 0xff1d4ed8,
            textColour = 0xffcbd5e1,
            activeTextColour = 0xffeff6ff,
          },
          children = {
            {
              id = "params_page",
              type = "TabPage",
              props = { title = "Params" },
              style = { bg = 0x00000000 },
              children = {
                { id = "midi_input_label", type = "Label", x = 12, y = 12, w = 120, h = 14, props = { text = "MIDI input" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
                { id = "midi_input_dropdown", type = "Dropdown", x = 12, y = 32, w = 276, h = 28, props = { options = { "None (Disabled)" }, selected = 1, max_visible_rows = 10 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
                { id = "midi_device_value", type = "Label", x = 12, y = 66, w = 276, h = 18, props = { text = "Input: None (Disabled)" }, style = { colour = 0xff60a5fa, fontSize = 10 } },

                { id = "module_label", type = "Label", x = 12, y = 98, w = 120, h = 14, props = { text = "Module" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
                { id = "module_selector", type = "Dropdown", x = 12, y = 118, w = 276, h = 28, props = { options = moduleOptions, selected = 1, max_visible_rows = 12 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
                { id = "module_status", type = "Label", x = 12, y = 154, w = 276, h = 48, props = { text = "", wordWrap = true }, style = { colour = 0xff60a5fa, fontSize = 10 } },

                { id = "view_label", type = "Label", x = 12, y = 214, w = 120, h = 14, props = { text = "View" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
                { id = "view_selector", type = "Dropdown", x = 12, y = 234, w = 140, h = 28, props = { options = { "Performance", "Patch" }, selected = 1, max_visible_rows = 2 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },

                { id = "size_label", type = "Label", x = 12, y = 274, w = 120, h = 14, props = { text = "Display size" }, style = { colour = 0xffcbd5e1, fontSize = 10 } },
                { id = "size_selector", type = "Dropdown", x = 12, y = 294, w = 160, h = 28, props = { options = { "1x1" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
                { id = "size_note", type = "Label", x = 180, y = 296, w = 108, h = 40, props = { text = "Actual rack modes only: 1x1 or 1x2.", wordWrap = true }, style = { colour = 0xff94a3b8, fontSize = 9 } },

                { id = "input_a_title", type = "Label", x = 12, y = 350, w = 120, h = 14, props = { text = "Host params" }, style = { colour = 0xfff8fafc, fontSize = 11 } },
                { id = "input_a_mode", type = "Dropdown", x = 12, y = 370, w = 276, h = 26, props = { options = { "External", "Silence", "Sine", "Saw", "Square", "Pulse", "Noise" }, selected = 3, max_visible_rows = 7 }, style = { bg = 0xff162235, colour = 0xffe2e8f0, radius = 0, fontSize = 10 } },
                { id = "input_a_pitch", type = "Slider", x = 12, y = 406, w = 276, h = 22, props = { min = 24, max = 84, step = 1, value = 60, label = "Pitch", compact = true, showValue = true }, style = { colour = 0xff38bdf8, bg = 0xff122033, fontSize = 9 } },
                { id = "input_a_level", type = "Slider", x = 12, y = 434, w = 276, h = 22, props = { min = 0, max = 1, step = 0.01, value = 0.65, label = "Level", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff0d1b28, fontSize = 9 } },

                {
                  id = "input_b_group",
                  type = "Panel",
                  x = 12,
                  y = 474,
                  w = 276,
                  h = 108,
                  style = { bg = 0x00000000 },
                  children = {
                    { id = "input_b_title", type = "Label", x = 0, y = 0, w = 160, h = 14, props = { text = "Input B / Aux" }, style = { colour = 0xfff8fafc, fontSize = 11 } },
                    { id = "input_b_mode", type = "Dropdown", x = 0, y = 22, w = 276, h = 26, props = { options = { "External", "Silence", "Sine", "Saw", "Square", "Pulse", "Noise" }, selected = 4, max_visible_rows = 7 }, style = { bg = 0xff2a180f, colour = 0xffffd3b0, radius = 0, fontSize = 10 } },
                    { id = "input_b_pitch", type = "Slider", x = 0, y = 58, w = 276, h = 22, props = { min = 24, max = 84, step = 1, value = 67, label = "Pitch", compact = true, showValue = true }, style = { colour = 0xfffb923c, bg = 0xff2b160d, fontSize = 9 } },
                    { id = "input_b_level", type = "Slider", x = 0, y = 86, w = 276, h = 22, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Level", compact = true, showValue = true }, style = { colour = 0xffff9a62, bg = 0xff2a150d, fontSize = 9 } },
                  },
                },

                { id = "routing_hint", type = "Label", x = 12, y = 598, w = 276, h = 72, props = { text = "Audio modules use Input A. Blend uses Input A + Input B. Sample capture records the selected source, including external host audio when Source is Input and Input A is External.", wordWrap = true }, style = { colour = 0xff94a3b8, fontSize = 10 } },
                { id = "module_note", type = "Label", x = 12, y = 678, w = 276, h = 76, props = { text = "", wordWrap = true }, style = { colour = 0xff64748b, fontSize = 10 } },
              },
            },
            {
              id = "files_page",
              type = "TabPage",
              props = { title = "Files" },
              style = { bg = 0x00000000 },
              children = {
                { id = "sidebar_files_status", type = "Label", x = 12, y = 12, w = 276, h = 16, props = { text = "Plugin files" }, style = { colour = 0xffcbd5e1, fontSize = 11 } },
                { id = "sidebar_files_path", type = "Label", x = 12, y = 32, w = 276, h = 30, props = { text = "Select a file to load it into the editor below. DSP files also show the graph tab.", wordWrap = true }, style = { colour = 0xff64748b, fontSize = 10 } },
                { id = "sidebar_files_tree_panel", type = "Panel", x = 12, y = 72, w = 276, h = 676, style = { bg = 0xff0f1726, border = 0xff243041, borderWidth = 1, radius = 0 } },
              },
            },
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
        {
          id = "viewport_tabs",
          type = "TabHost",
          x = 24,
          y = 18,
          w = 220,
          h = 26,
          props = {
            activeIndex = 1,
            tabBarHeight = 24,
            tabSizing = "fill",
          },
          style = {
            bg = 0x00000000,
            border = 0x00000000,
            borderWidth = 0,
            radius = 0,
            tabBarBg = 0x00000000,
            tabBg = 0xff1e293b,
            activeTabBg = 0xff2563eb,
            textColour = 0xffcbd5e1,
            activeTextColour = 0xffffffff,
          },
          children = {
            { id = "plugin_page", type = "TabPage", props = { title = "Plugin" }, style = { bg = 0x00000000 } },
            { id = "graph_page", type = "TabPage", props = { title = "Graph" }, style = { bg = 0x00000000 } },
          },
        },
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

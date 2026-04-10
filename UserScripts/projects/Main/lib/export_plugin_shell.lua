local ExportPluginShell = {}

function ExportPluginShell.build(options)
  options = type(options) == "table" and options or {}

  local rootId = tostring(options.rootId or "export_plugin_root")
  local title = tostring(options.title or "Export")
  local accent = tonumber(options.accent) or 0xff22d3ee
  local width = math.max(1, math.floor(tonumber(options.width) or 472))
  local height = math.max(1, math.floor(tonumber(options.height) or 220))
  local headerHeight = math.max(1, math.floor(tonumber(options.headerHeight) or 12))
  local contentWidth = math.max(1, math.floor(tonumber(options.contentWidth) or width))
  local contentHeight = math.max(1, math.floor(tonumber(options.contentHeight) or (height - headerHeight)))
  local moduleId = tostring(options.moduleId or "module_component")
  local moduleBehavior = tostring(options.moduleBehavior or "")
  local moduleRef = tostring(options.moduleRef or "")
  local moduleProps = type(options.moduleProps) == "table" and options.moduleProps or {}

  if moduleBehavior == "" then
    error("export_plugin_shell.build: moduleBehavior is required")
  end
  if moduleRef == "" then
    error("export_plugin_shell.build: moduleRef is required")
  end

  return {
    id = rootId,
    type = "Panel",
    x = 0,
    y = 0,
    w = width,
    h = height,
    behavior = "../Main/ui/behaviors/export_shell.lua",
    props = {
      moduleComponentId = moduleId,
      contentW = contentWidth,
      contentH = contentHeight,
    },
    style = {
      bg = 0xff0b1220,
      border = 0xff1f2b4d,
      borderWidth = 1,
      radius = 0,
    },
    children = {
      {
        id = "header_bg",
        type = "Panel",
        x = 0,
        y = 0,
        w = width,
        h = headerHeight,
        style = { bg = 0xff111827, radius = 0 },
      },
      {
        id = "header_accent",
        type = "Panel",
        x = 0,
        y = 0,
        w = 18,
        h = headerHeight,
        style = { bg = accent, radius = 0 },
      },
      {
        id = "title",
        type = "Label",
        x = 24,
        y = 0,
        w = math.max(80, width - 88),
        h = headerHeight,
        props = { text = title },
        style = { colour = 0xffffffff, fontSize = 9, bg = 0x00000000 },
      },
      {
        id = "dev_button",
        type = "Toggle",
        x = math.max(0, width - 60),
        y = 0,
        w = 60,
        h = headerHeight,
        props = { value = false, onLabel = "SET", offLabel = "SET" },
        style = { onColour = 0xff475569, offColour = 0x20ffffff, textColour = 0xffffffff, fontSize = 8, radius = 0 },
      },
      {
        id = "content_bg",
        type = "Panel",
        x = 0,
        y = headerHeight,
        w = width,
        h = math.max(1, height - headerHeight),
        style = { bg = 0xff0b1220, radius = 0 },
      },
    },
    components = {
      {
        id = moduleId,
        x = 0,
        y = headerHeight,
        w = width,
        h = contentHeight,
        behavior = moduleBehavior,
        ref = moduleRef,
        props = moduleProps,
      },
      {
        id = "settings_overlay",
        x = 0,
        y = headerHeight,
        w = width,
        h = contentHeight,
        behavior = "../Main/ui/behaviors/export_settings_panel.lua",
        ref = "../Main/ui/components/export_settings_panel.ui.lua",
        props = {},
      },
      {
        id = "perf_overlay",
        x = 0,
        y = headerHeight,
        w = width,
        h = contentHeight,
        behavior = "../Main/ui/behaviors/export_perf_overlay.lua",
        ref = "../Main/ui/components/export_perf_overlay.ui.lua",
        props = {},
      },
    },
  }
end

return ExportPluginShell

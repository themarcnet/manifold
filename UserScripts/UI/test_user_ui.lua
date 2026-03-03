-- test_user_ui.lua
-- Simple test UI to verify user scripts directory is working

local W = require("ui_widgets")

local ui = {}

function ui_init(root)
    -- Main panel
    ui.panel = W.Panel.new(root, "testPanel", {
        bg = 0xff1a2332,
        radius = 12,
        border = 0xff38bdf8,
        borderWidth = 2,
    })

    -- Title
    ui.title = W.Label.new(ui.panel.node, "title", {
        text = "USER SCRIPT WORKS!",
        colour = 0xff38bdf8,
        fontSize = 28.0,
        fontStyle = FontStyle.bold,
    })

    -- Subtitle
    ui.subtitle = W.Label.new(ui.panel.node, "subtitle", {
        text = "This UI was loaded from the User Scripts directory",
        colour = 0xff94a3b8,
        fontSize = 14.0,
    })

    -- Info panel
    ui.infoPanel = W.Panel.new(ui.panel.node, "infoPanel", {
        bg = 0xff0f172a,
        radius = 8,
    })

    ui.pathLabel = W.Label.new(ui.infoPanel.node, "pathLabel", {
        text = "Path: UserScripts/UI/test_user_ui.lua",
        colour = 0xff64748b,
        fontSize = 11.0,
    })

    ui_resized(root:getWidth(), root:getHeight())
end

function ui_resized(w, h)
    local margin = 40
    local panelW = w - margin * 2
    local panelH = h - margin * 2

    ui.panel.node:setBounds(margin, margin, panelW, panelH)
    
    ui.title.node:setBounds(0, 40, panelW, 40)
    ui.subtitle.node:setBounds(0, 90, panelW, 30)
    
    ui.infoPanel.node:setBounds(40, 150, panelW - 80, 80)
    ui.pathLabel.node:setBounds(20, 30, panelW - 120, 20)
end

function ui_update(state)
    -- Nothing to update
end

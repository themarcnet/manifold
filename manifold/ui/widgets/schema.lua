-- schema.lua
-- Editor schema definitions for all widgets

local Utils = require("widgets.utils")

local Schema = {}

local kEditorSchemaByWidget = {
    Button = {
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "fontSize", label = "Font Size", type = "number", min = 6, max = 64, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
    },
    Label = {
        { path = "text", label = "Text", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "fontSize", label = "Font Size", type = "number", min = 6, max = 64, step = 1, group = "Style" },
        { path = "fontStyle", label = "Font Style", type = "enum", group = "Style" },
        { path = "justification", label = "Justify", type = "enum", group = "Layout" },
    },
    Panel = {
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "border", label = "Border", type = "color", group = "Style" },
        { path = "borderWidth", label = "Border Width", type = "number", min = 0, max = 12, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
        { path = "opacity", label = "Opacity", type = "number", min = 0, max = 1, step = 0.01, group = "Style" },
        { path = "interceptsMouse", label = "Intercept Mouse", type = "bool", group = "Behavior" },
    },
    Slider = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "showValue", label = "Show Value", type = "bool", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Track", type = "color", group = "Style" },
    },
    VSlider = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Track", type = "color", group = "Style" },
    },
    Knob = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
    Toggle = {
        { path = "value", label = "Value", type = "bool", group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "onColour", label = "On Colour", type = "color", group = "Style" },
        { path = "offColour", label = "Off Colour", type = "color", group = "Style" },
    },
    Dropdown = {
        { path = "selected", label = "Selected", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "colour", label = "Accent", type = "color", group = "Style" },
    },
    CurveWidget = {
        { path = "title", label = "Title", type = "text", group = "Behavior" },
        { path = "editable", label = "Editable", type = "bool", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "gridColour", label = "Grid", type = "color", group = "Style" },
        { path = "axisColour", label = "Axis", type = "color", group = "Style" },
    },
    WaveformView = {
        { path = "mode", label = "Mode", type = "enum", group = "Behavior", options = {
            { label = "layer", value = "layer" },
            { label = "capture", value = "capture" },
        } },
        { path = "layerIndex", label = "Layer", type = "number", min = 0, max = 16, step = 1, group = "Behavior" },
        { path = "colour", label = "Wave Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "playheadColour", label = "Playhead", type = "color", group = "Style" },
    },
    Meter = {
        { path = "orientation", label = "Orientation", type = "enum", group = "Layout", options = {
            { label = "vertical", value = "vertical" },
            { label = "horizontal", value = "horizontal" },
        } },
        { path = "showPeak", label = "Show Peak", type = "bool", group = "Behavior" },
        { path = "decay", label = "Decay", type = "number", min = 0, max = 1, step = 0.01, group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
    SegmentedControl = {
        { path = "selected", label = "Selected", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "selectedBg", label = "Selected Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "selectedTextColour", label = "Selected Text", type = "color", group = "Style" },
    },
    Radio = {
        { path = "selected", label = "Selected", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "selectedBg", label = "Selected Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "selectedTextColour", label = "Selected Text", type = "color", group = "Style" },
    },
    NumberBox = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "format", label = "Format", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
    TabHost = {
        { path = "activeIndex", label = "Active Tab", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "tabSizing", label = "Tab Sizing", type = "text", options = { "fill", "content" }, group = "Layout" },
        { path = "tabBarHeight", label = "Tab Bar Height", type = "number", min = 18, max = 96, step = 1, group = "Layout" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "border", label = "Border", type = "color", group = "Style" },
        { path = "borderWidth", label = "Border Width", type = "number", min = 0, max = 12, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
        { path = "tabBarBg", label = "Tab Bar Background", type = "color", group = "Style" },
        { path = "tabBg", label = "Tab Background", type = "color", group = "Style" },
        { path = "activeTabBg", label = "Active Tab Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "activeTextColour", label = "Active Text Colour", type = "color", group = "Style" },
    },
    TabPage = {
        { path = "title", label = "Title", type = "text", group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "border", label = "Border", type = "color", group = "Style" },
        { path = "borderWidth", label = "Border Width", type = "number", min = 0, max = 12, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
        { path = "opacity", label = "Opacity", type = "number", min = 0, max = 1, step = 0.01, group = "Style" },
    },
}

function Schema.buildEditorSchema(widgetType, config)
    local base = Utils.cloneArrayOfTables(kEditorSchemaByWidget[widgetType] or {})

    for i = 1, #base do
        local item = base[i]
        if item.path == "value" then
            if item.min == nil then item.min = config.min end
            if item.max == nil then item.max = config.max end
            if item.step == nil then item.step = config.step end
        elseif item.path == "selected" and type(config.options) == "table" then
            item.max = #config.options
        elseif item.path == "activeIndex" and type(config.pages) == "table" then
            item.max = #config.pages
        elseif item.path == "fontStyle" then
            item.options = Utils.makeFontStyleOptions()
        elseif item.path == "justification" then
            item.options = Utils.makeJustifyOptions()
        end
    end

    return base
end

return Schema

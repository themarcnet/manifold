-- label.lua
-- Label widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Label = BaseWidget:extend()

function Label.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Label)

    self._text = config.text or ""
    self._colour = Utils.colour(config.colour, 0xff9ca3af)
    self._fontSize = config.fontSize or 13.0
    self._fontName = config.fontName
    self._fontStyle = config.fontStyle or FontStyle.plain
    self._justification = config.justification or Justify.centredLeft

    self.node:setInterceptsMouse(false, false)

    self:_storeEditorMeta("Label", {}, Schema.buildEditorSchema("Label", config))

    return self
end

function Label:onDraw(w, h)
    gfx.setColour(self._colour)
    if self._fontName then
        gfx.setFont(self._fontName, self._fontSize, self._fontStyle)
    else
        gfx.setFont(self._fontSize)
    end
    gfx.drawText(self._text, 0, 0, w, h, self._justification)
end

function Label:setText(text)
    self._text = text
end

function Label:getText()
    return self._text
end

function Label:setColour(colour)
    self._colour = colour
end

return Label

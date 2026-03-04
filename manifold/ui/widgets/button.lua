-- button.lua
-- Button widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Button = BaseWidget:extend()

function Button.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Button)

    self._label = config.label or ""
    self._bg = Utils.colour(config.bg, 0xff374151)
    self._textColour = Utils.colour(config.textColour, 0xffffffff)
    self._fontSize = config.fontSize or 13.0
    self._radius = config.radius or 7.0
    self._onClick = config.on_click or config.onClick
    self._onPress = config.on_press or config.onPress
    self._onRelease = config.on_release or config.onRelease

    self:_storeEditorMeta("Button", {
        on_click = self._onClick,
        on_press = self._onPress,
        on_release = self._onRelease
    }, Schema.buildEditorSchema("Button", config))

    return self
end

function Button:onMouseDown(mx, my)
    if self._onPress then
        self._onPress(mx, my)
    end
end

function Button:onMouseUp(mx, my)
    if self._onRelease then
        self._onRelease(mx, my)
    end
end

function Button:onClick()
    if self._onClick then
        self._onClick()
    end
end

function Button:drawBackground(w, h)
    local bg = self._bg
    if not self:isEnabled() then
        bg = Utils.darken(bg, 40)
    elseif self:isPressed() then
        bg = Utils.darken(bg, 20)
    elseif self:isHovered() then
        bg = Utils.brighten(bg, 25)
    end
    
    gfx.setColour(bg)
    gfx.fillRoundedRect(1, 1, w - 2, h - 2, self._radius)
    gfx.setColour(Utils.brighten(bg, 40))
    gfx.drawRoundedRect(1, 1, w - 2, h - 2, self._radius, 1.0)
end

function Button:drawLabel(w, h)
    gfx.setColour(self._textColour)
    gfx.setFont(self._fontSize)
    gfx.drawText(self._label, 0, 0, w, h, Justify.centred)
end

function Button:onDraw(w, h)
    self:drawBackground(w, h)
    self:drawLabel(w, h)
end

function Button:setLabel(label)
    self._label = label
end

function Button:getLabel()
    return self._label
end

function Button:setBg(colour)
    self._bg = colour
end

function Button:setTextColour(colour)
    self._textColour = colour
end

return Button

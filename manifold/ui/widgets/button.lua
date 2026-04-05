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

    self:_syncRetained()

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
    -- Text shadow
    gfx.setColour(0xb0000000)
    gfx.setFont(self._fontSize)
    gfx.drawText(self._label, 1, 1, w, h, Justify.centred)
    
    -- Main text
    gfx.setColour(self._textColour)
    gfx.drawText(self._label, 0, 0, w, h, Justify.centred)
end

function Button:onDraw(w, h)
    self:drawBackground(w, h)
    self:drawLabel(w, h)
end

function Button:_syncRetained(w, h)
    local _, _, bw, bh = self.node:getBounds()
    w = w or bw or 0
    h = h or bh or 0

    local bg = self._bg
    if not self:isEnabled() then
        bg = Utils.darken(bg, 40)
    elseif self:isPressed() then
        bg = Utils.darken(bg, 20)
    elseif self:isHovered() then
        bg = Utils.brighten(bg, 25)
    end

    self.node:setStyle({
        bg = bg,
        border = Utils.brighten(bg, 40),
        borderWidth = 1.0,
        radius = self._radius,
        opacity = 1.0
    })

    self.node:setDisplayList({
        {
            cmd = "drawText",
            x = 1,
            y = 1,
            w = w,
            h = h,
            color = 0xb0000000,
            text = self._label,
            fontSize = self._fontSize,
            align = "center",
            valign = "middle"
        },
        {
            cmd = "drawText",
            x = 0,
            y = 0,
            w = w,
            h = h,
            color = self._textColour,
            text = self._label,
            fontSize = self._fontSize,
            align = "center",
            valign = "middle"
        }
    })
end

function Button:setLabel(label)
    local nextLabel = label or ""
    if self._label == nextLabel then
        return
    end
    self._label = nextLabel
    self:_syncRetained()
    self.node:repaint()
end

function Button:getLabel()
    return self._label
end

function Button:setBg(colour)
    if self._bg == colour then
        return
    end
    self._bg = colour
    self:_syncRetained()
    self.node:repaint()
end

function Button:setTextColour(colour)
    if self._textColour == colour then
        return
    end
    self._textColour = colour
    self:_syncRetained()
    self.node:repaint()
end

return Button

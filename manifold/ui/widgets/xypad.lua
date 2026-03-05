-- xypad.lua
-- 2D control surface - clean base widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")

local XYPadWidget = BaseWidget:extend()

function XYPadWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), XYPadWidget)

    self._x = config.x or 0.5
    self._y = config.y or 0.5
    self._handleColour = Utils.colour(config.handleColour, 0xffff8800)
    self._bgColour = Utils.colour(config.bgColour, 0x00000000)
    self._gridColour = Utils.colour(config.gridColour, 0x00000000)
    self._onChange = config.on_change or config.onChange

    self:_storeEditorMeta("XYPadWidget", {
        on_change = self._onChange,
    }, {})

    self:exposeParams({
        { path = "handleColour", label = "Handle Colour", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "gridColour", label = "Grid", type = "color", group = "Style" },
    })

    return self
end

function XYPadWidget:onMouseDown(mx, my)
    self:_updateFromMouse(mx, my)
end

function XYPadWidget:onMouseDrag(mx, my, dx, dy)
    self:_updateFromMouse(mx, my)
end

function XYPadWidget:_updateFromMouse(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local margin = 20

    self._x = Utils.clamp((mx - margin) / (w - margin * 2), 0, 1)
    self._y = Utils.clamp((my - margin) / (h - margin * 2), 0, 1)

    if self._onChange then
        self._onChange(self._x, self._y)
    end
end

function XYPadWidget:getValues()
    return self._x, self._y
end

function XYPadWidget:setValues(x, y)
    self._x = Utils.clamp(x or 0.5, 0, 1)
    self._y = Utils.clamp(y or 0.5, 0, 1)
end

function XYPadWidget:onDraw(w, h)
    local margin = 20
    local drawW = w - margin * 2
    local drawH = h - margin * 2

    -- Background
    gfx.setColour(self._bgColour)
    gfx.fillRoundedRect(margin, margin, drawW, drawH, 8)

    -- Grid lines
    gfx.setColour(self._gridColour)
    for i = 1, 4 do
        local x = margin + (drawW / 5) * i
        local y = margin + (drawH / 5) * i
        gfx.drawVerticalLine(math.floor(x), margin, drawH)
        gfx.drawHorizontalLine(math.floor(y), margin, drawW)
    end

    -- Crosshair center
    local cx = margin + drawW / 2
    local cy = margin + drawH / 2
    gfx.setColour(Utils.brighten(self._gridColour, 20))
    gfx.drawVerticalLine(math.floor(cx), margin, drawH)
    gfx.drawHorizontalLine(math.floor(cy), margin, drawW)

    -- Current position
    local px = margin + self._x * drawW
    local py = margin + self._y * drawH

    -- Glow
    for i = 3, 1, -1 do
        local glowSize = 8 + i * 4
        local alpha = 50 - i * 15
        gfx.setColour((alpha << 24) | 0xff4400)
        gfx.fillRoundedRect(math.floor(px - glowSize/2), math.floor(py - glowSize/2),
                           math.floor(glowSize), math.floor(glowSize), glowSize/2)
    end

    -- Handle
    gfx.setColour(self._handleColour)
    gfx.fillRoundedRect(math.floor(px - 6), math.floor(py - 6), 12, 12, 6)
    gfx.setColour(0xffffffff)
    gfx.fillRoundedRect(math.floor(px - 3), math.floor(py - 3), 6, 6, 3)

    -- Coordinates label
    gfx.setColour(0xffffffff)
    gfx.setFont(11.0)
    local label = string.format("X: %.2f  Y: %.2f", self._x, self._y)
    gfx.drawText(label, margin, h - 18, drawW, 16, Justify.centred)
end

return XYPadWidget

-- numberbox.lua
-- Number box widget with +/- buttons and drag

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local NumberBox = BaseWidget:extend()

function NumberBox.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), NumberBox)

    self._min = config.min or 0
    self._max = config.max or 999
    self._step = config.step or 1
    self._value = Utils.clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = Utils.colour(config.colour, 0xff38bdf8)
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._dragging = false
    self._dragStartY = 0
    self._dragStartValue = 0
    self._format = config.format or (self._step >= 1 and "%d" or "%.1f")
    self._clickTarget = nil
    self._buttonHeld = nil
    self._repeatDelay = 15
    self._repeatInterval = 3
    self._repeatCounter = 0

    self:_storeEditorMeta("NumberBox", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("NumberBox", config))

    return self
end

function NumberBox:onMouseDown(mx, my)
    local w = self.node:getWidth()
    local btnW = math.min(24, w * 0.2)
    
    if mx < btnW then
        self._clickTarget = "minus"
        self._buttonHeld = "minus"
        self._repeatCounter = 0
        self:_adjust(-1)
    elseif mx > w - btnW then
        self._clickTarget = "plus"
        self._buttonHeld = "plus"
        self._repeatCounter = 0
        self:_adjust(1)
    else
        self._clickTarget = "value"
        self._dragging = true
        self._dragStartY = my
        self._dragStartValue = self._value
    end
end

function NumberBox:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    local range = self._max - self._min
    local delta = (-dy / 100.0) * range
    local newVal = Utils.clamp(Utils.snapToStep(self._dragStartValue + delta, self._step), self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function NumberBox:onMouseUp(mx, my)
    self._dragging = false
end

function NumberBox:onDoubleClick()
    if self._clickTarget ~= "value" then return end
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function NumberBox:_adjust(direction)
    local newVal = Utils.clamp(self._value + self._step * direction, self._min, self._max)
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function NumberBox:onDraw(w, h)
    local btnW = math.min(24, math.floor(w * 0.2))
    local bg = self._bg
    
    -- Background
    gfx.setColour(bg)
    gfx.fillRoundedRect(0, 0, w, h, 5)
    gfx.setColour(Utils.brighten(bg, 20))
    gfx.drawRoundedRect(0, 0, w, h, 5, 1)
    
    -- Minus button
    local minusBg = self:isHovered() and Utils.brighten(bg, 15) or bg
    gfx.setColour(minusBg)
    gfx.fillRoundedRect(1, 1, btnW, h - 2, 4)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(14.0)
    gfx.drawText("−", 0, 0, btnW, h, Justify.centred)
    
    -- Plus button
    local plusBg = self:isHovered() and Utils.brighten(bg, 15) or bg
    gfx.setColour(plusBg)
    gfx.fillRoundedRect(w - btnW - 1, 1, btnW, h - 2, 4)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(14.0)
    gfx.drawText("+", w - btnW, 0, btnW, h, Justify.centred)
    
    -- Separator lines
    gfx.setColour(Utils.brighten(bg, 30))
    gfx.drawVerticalLine(btnW, 2, h - 2)
    gfx.drawVerticalLine(w - btnW - 1, 2, h - 2)
    
    -- Label
    if self._label ~= "" then
        gfx.setColour(0xff94a3b8)
        gfx.setFont(9.0)
        gfx.drawText(self._label, btnW + 4, 1, w - btnW * 2 - 8, math.floor(h * 0.4), Justify.centred)
    end
    
    local fmtValue = self._value
    if self._format == "%d" then fmtValue = math.floor(fmtValue + 0.5) end
    local valText = string.format(self._format, fmtValue) .. self._suffix
    gfx.setColour(self._dragging and Utils.brighten(self._colour, 30) or self._colour)
    gfx.setFont(13.0)
    local valY = self._label ~= "" and math.floor(h * 0.3) or 0
    local valH = self._label ~= "" and math.floor(h * 0.7) or h
    gfx.drawText(valText, btnW + 4, valY, w - btnW * 2 - 8, valH, Justify.centred)
end

function NumberBox:getValue()
    return self._value
end

function NumberBox:setValue(v)
    self._value = Utils.clamp(v, self._min, self._max)
end

return NumberBox

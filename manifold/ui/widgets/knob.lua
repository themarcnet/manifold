-- knob.lua
-- Rotary knob widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Knob = BaseWidget:extend()

function Knob.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Knob)

    self._min = config.min or 0
    self._max = config.max or 1
    self._step = config.step or 0
    self._value = Utils.clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = Utils.colour(config.colour, 0xff22d3ee)
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._dragging = false
    self._dragStartY = 0
    self._dragStartValue = 0

    -- Arc angles: -135° to +135°
    self._startAngle = -135
    self._endAngle = 135

    self:_storeEditorMeta("Knob", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("Knob", config))

    return self
end

function Knob:onMouseDown(mx, my)
    self._dragging = true
    self._dragStartY = my
    self._dragStartValue = self._value
end

function Knob:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    local range = self._max - self._min
    local delta = (-dy / 150.0) * range  -- Vertical drag
    local newVal = Utils.clamp(Utils.snapToStep(self._dragStartValue + delta, self._step), self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Knob:onMouseUp(mx, my)
    self._dragging = false
end

function Knob:onDoubleClick()
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Knob:onDraw(w, h)
    local cx = w / 2
    local cy = h * 0.42
    local radius = math.min(w, h) * 0.32
    
    -- Draw background
    self:drawBackground(cx, cy, radius)
    
    -- Draw arc
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    local arcEnd = self._startAngle + t * (self._endAngle - self._startAngle)
    self:drawArc(cx, cy, radius, arcEnd)
    
    -- Draw pointer
    self:drawPointer(cx, cy, radius * 0.55, arcEnd)
    
    -- Draw value and label
    self:drawValueText(w, h)
    self:drawLabelText(w, h)
end

function Knob:drawBackground(cx, cy, radius)
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(cx - radius, cy - radius, radius * 2, radius * 2, radius)
end

function Knob:drawArc(cx, cy, radius, endAngle)
    local numTicks = 32
    for i = 0, numTicks do
        local angle = self._startAngle + (i / numTicks) * (self._endAngle - self._startAngle)
        local rad = math.rad(angle - 90)
        local isFilled = angle <= endAngle
        gfx.setColour(isFilled and self._colour or Utils.darken(self._bg, 10))
        local x1 = cx + math.cos(rad) * (radius * 0.7)
        local y1 = cy + math.sin(rad) * (radius * 0.7)
        local x2 = cx + math.cos(rad) * (radius * 0.92)
        local y2 = cy + math.sin(rad) * (radius * 0.92)
        gfx.fillRect(math.min(x1, x2), math.min(y1, y2),
                      math.max(2, math.abs(x2 - x1)),
                      math.max(2, math.abs(y2 - y1)))
    end
end

function Knob:drawPointer(cx, cy, radius, angle)
    local rad = math.rad(angle - 90)
    local px = cx + math.cos(rad) * radius
    local py = cy + math.sin(rad) * radius
    gfx.setColour(0xffe2e8f0)
    gfx.fillRoundedRect(px - 2, py - 2, 4, 4, 2)
end

function Knob:drawValueText(w, h)
    local valText
    local v = tonumber(self._value) or 0
    if self._step >= 1 then
        valText = tostring(math.floor(v + 0.5)) .. self._suffix
    else
        valText = string.format("%.2f", v) .. self._suffix
    end
    gfx.setColour(0xffcbd5e1)
    gfx.setFont(11.0)
    gfx.drawText(valText, 0, math.floor(h * 0.72), w, math.floor(h * 0.14), Justify.centred)
end

function Knob:drawLabelText(w, h)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(10.0)
    gfx.drawText(self._label, 0, math.floor(h * 0.86), w, math.floor(h * 0.14), Justify.centred)
end

function Knob:getValue()
    return self._value
end

function Knob:setValue(v)
    self._value = Utils.clamp(v, self._min, self._max)
end

return Knob

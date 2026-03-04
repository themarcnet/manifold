-- slider.lua
-- Horizontal and vertical slider widgets

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

-- ============================================================================
-- Slider (Horizontal)
-- ============================================================================

local Slider = BaseWidget:extend()

function Slider.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Slider)

    self._min = config.min or 0
    self._max = config.max or 1
    self._step = config.step or 0
    self._value = Utils.clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = Utils.colour(config.colour, 0xff38bdf8)
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._showValue = config.showValue ~= false
    self._dragging = false
    self._dragStartX = 0
    self._dragStartValue = 0

    self.node:setInterceptsMouse(true, false)

    self:_storeEditorMeta("Slider", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("Slider", config))

    return self
end

function Slider:onMouseDown(mx, my)
    self._dragging = true
    self._dragStartX = mx
    self._dragStartValue = self._value
    self:valueFromMouse(mx)
end

function Slider:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    self:valueFromMouse(mx)
end

function Slider:onMouseUp(mx, my)
    self._dragging = false
end

function Slider:onDoubleClick()
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Slider:valueFromMouse(mx)
    local w = self.node:getWidth()
    local trackW = math.max(1, w - 16)
    local t = Utils.clamp((mx - 8) / trackW, 0, 1)
    local newVal = self._min + t * (self._max - self._min)
    newVal = Utils.snapToStep(newVal, self._step)
    newVal = Utils.clamp(newVal, self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Slider:onDraw(w, h)
    local trackY = h * 0.5 - 3
    local trackH = 6
    local trackR = 3
    
    -- Draw track
    self:drawTrack(8, trackY, w - 16, trackH, trackR)
    
    -- Draw thumb
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    local thumbX = 8 + t * (w - 16) - 6
    self:drawThumb(thumbX, (h - 20) / 2, 12, 20)
    
    -- Draw label
    if self._showValue then
        local valText
        local v = tonumber(self._value) or 0
        if self._step >= 1 then
            local iv = math.floor(v + 0.5)
            valText = self._label .. ": " .. tostring(iv) .. self._suffix
        else
            valText = self._label .. ": " .. string.format("%.2f", v) .. self._suffix
        end
        gfx.setColour(0xffe2e8f0)
        gfx.setFont(11.0)
        gfx.drawText(valText, 8, 2, w - 16, 20, Justify.centred)
    end
end

function Slider:drawTrack(x, y, w, h, r)
    -- Background track
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(x, y, w, h, r)
    
    -- Filled portion
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    gfx.setColour(self._colour)
    gfx.fillRoundedRect(x, y, w * t, h, r)
end

function Slider:drawThumb(x, y, w, h)
    local col = self._colour
    if self._dragging then
        col = Utils.brighten(col, 30)
    elseif self:isHovered() then
        col = Utils.brighten(col, 15)
    end
    gfx.setColour(col)
    gfx.fillRoundedRect(x, y, w, h, 4)
end

function Slider:getValue()
    return self._value
end

function Slider:setValue(v)
    self._value = Utils.clamp(v, self._min, self._max)
end

function Slider:reset()
    self:setValue(self._defaultValue)
end

-- ============================================================================
-- VSlider (Vertical) - extends Slider
-- ============================================================================

local VSlider = Slider:extend()

function VSlider.new(parent, name, config)
    local self = setmetatable(Slider.new(parent, name, config), VSlider)
    -- Override the type stored by Slider.new
    self:_storeEditorMeta("VSlider", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("VSlider", config))
    return self
end

function VSlider:onMouseDown(mx, my)
    self._dragging = true
    self:valueFromMouse(mx, my)
end

function VSlider:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    self:valueFromMouse(mx, my)
end

function VSlider:valueFromMouse(mx, my)
    if my == nil then
        return
    end
    local h = self.node:getHeight()
    local trackH = math.max(1, h - 16)
    local t = 1 - Utils.clamp((my - 8) / trackH, 0, 1)  -- Inverted: bottom = min
    local newVal = self._min + t * (self._max - self._min)
    newVal = Utils.snapToStep(newVal, self._step)
    newVal = Utils.clamp(newVal, self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function VSlider:onDraw(w, h)
    local trackX = 2
    local trackW = w - 4
    local trackY = 4
    local trackH = h - 8
    local trackR = trackW / 2
    
    -- Draw track (subtle background)
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(trackX, trackY, trackW, trackH, trackR)
    
    -- Calculate thumb position based on value
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    
    -- Browser-style scroll pill: thumb represents viewport
    local thumbH = math.max(30, trackH * 0.3)  -- Minimum 30px or 30% of track
    local thumbW = trackW
    local maxThumbY = trackY + trackH - thumbH
    local thumbY = trackY + maxThumbY * (1 - t)
    
    -- Draw thumb (scroll pill)
    local col = self._colour
    if self._dragging then
        col = Utils.brighten(col, 30)
    elseif self:isHovered() then
        col = Utils.brighten(col, 15)
    end
    gfx.setColour(col)
    gfx.fillRoundedRect(trackX, thumbY, thumbW, thumbH, trackR)
end

return {
    Slider = Slider,
    VSlider = VSlider
}

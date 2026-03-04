-- meter.lua
-- Level meter widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Meter = BaseWidget:extend()

function Meter.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Meter)

    self._value = 0  -- 0 to 1
    self._peak = 0
    self._colour = Utils.colour(config.colour, 0xff22c55e)
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._orientation = config.orientation or "vertical"  -- "vertical" or "horizontal"
    self._showPeak = config.showPeak ~= false
    self._decay = config.decay or 0.9

    self.node:setInterceptsMouse(false, false)

    self:_storeEditorMeta("Meter", {}, Schema.buildEditorSchema("Meter", config))

    return self
end

function Meter:onDraw(w, h)
    -- Decay peak
    self._peak = self._peak * self._decay
    
    if self._orientation == "vertical" then
        -- Background
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, 3)
        
        -- Level
        local fillH = h * self._value
        gfx.setColour(self._colour)
        gfx.fillRoundedRect(0, h - fillH, w, fillH, 3)
        
        -- Peak marker
        if self._showPeak and self._peak > 0.01 then
            local peakY = h * (1 - self._peak)
            gfx.setColour(0xffff0000)
            gfx.fillRect(0, peakY - 1, w, 2)
        end
    else
        -- Background
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, 3)
        
        -- Level
        local fillW = w * self._value
        gfx.setColour(self._colour)
        gfx.fillRoundedRect(0, 0, fillW, h, 3)
        
        -- Peak marker
        if self._showPeak and self._peak > 0.01 then
            local peakX = w * self._peak
            gfx.setColour(0xffff0000)
            gfx.fillRect(peakX - 1, 0, 2, h)
        end
    end
end

function Meter:setValue(v)
    self._value = Utils.clamp(v, 0, 1)
    if self._value > self._peak then
        self._peak = self._value
    end
end

return Meter

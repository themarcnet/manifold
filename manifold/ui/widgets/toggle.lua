-- toggle.lua
-- Toggle/Switch widget

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Toggle = BaseWidget:extend()

function Toggle.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Toggle)

    self._value = config.value or false
    self._label = config.label or ""
    self._onColour = Utils.colour(config.onColour, 0xff22c55e)
    self._offColour = Utils.colour(config.offColour, 0xff374151)
    self._onChange = config.on_change or config.onChange

    self:_storeEditorMeta("Toggle", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("Toggle", config))

    return self
end

function Toggle:onClick()
    self._value = not self._value
    if self._onChange then
        self._onChange(self._value)
    end
end

function Toggle:onDraw(w, h)
    -- Track
    local trackW = math.floor(math.min(38, w * 0.5))
    local trackH = 18
    local trackX = math.floor(w - trackW - 6)
    local trackY = math.floor((h - trackH) / 2)
    local trackR = math.floor(trackH / 2)
    
    local trackCol = self._value and self._onColour or self._offColour
    if self:isHovered() then
        trackCol = Utils.brighten(trackCol, 15)
    end
    
    gfx.setColour(trackCol)
    gfx.fillRoundedRect(trackX, trackY, trackW, trackH, trackR)
    
    -- Thumb
    local thumbR = trackH - 4
    local thumbX = math.floor(self._value and (trackX + trackW - thumbR - 2) or (trackX + 2))
    local thumbY = math.floor(trackY + 2)
    gfx.setColour(0xffe2e8f0)
    gfx.fillRoundedRect(thumbX, thumbY, thumbR, thumbR, math.floor(thumbR / 2))
    
    -- Label
    gfx.setColour(self._value and 0xffe2e8f0 or 0xff94a3b8)
    gfx.setFont(12.0)
    gfx.drawText(self._label, 6, 0, math.floor(trackX - 10), h, Justify.centredLeft)
end

function Toggle:getValue()
    return self._value
end

function Toggle:setValue(v)
    self._value = v
end

return Toggle

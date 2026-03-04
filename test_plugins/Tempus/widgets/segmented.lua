-- segmented.lua
-- Segmented control (multi-button selector)

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local SegmentedControl = BaseWidget:extend()

function SegmentedControl.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), SegmentedControl)

    self._segments = config.segments or {}
    self._selected = config.selected or 1
    self._onSelect = config.on_select or config.onSelect
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._selectedBg = Utils.colour(config.selectedBg, 0xff38bdf8)
    self._textColour = Utils.colour(config.textColour, 0xffe2e8f0)
    self._selectedTextColour = Utils.colour(config.selectedTextColour, 0xffffffff)

    self:_storeEditorMeta("SegmentedControl", {
        on_select = self._onSelect
    }, Schema.buildEditorSchema("SegmentedControl", config))

    return self
end

function SegmentedControl:onMouseDown(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local segW = w / #self._segments
    local idx = math.floor(mx / segW) + 1
    
    if idx >= 1 and idx <= #self._segments then
        self._selected = idx
        if self._onSelect then
            self._onSelect(idx, self._segments[idx])
        end
    end
end

function SegmentedControl:onDraw(w, h)
    local segW = math.floor(w / #self._segments)
    local segH = h
    local r = 6
    
    for i, seg in ipairs(self._segments) do
        local x = math.floor((i - 1) * segW)
        local isSelected = (i == self._selected)
        local isHovered = self:isHovered()
        
        local bg = isSelected and self._selectedBg or self._bg
        if isHovered and not isSelected then
            bg = Utils.brighten(bg, 10)
        end
        
        -- Draw segment with rounded corners on ends only
        gfx.setColour(bg)
        if i == 1 then
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        elseif i == #self._segments then
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        else
            gfx.fillRect(x, 0, segW, segH)
        end
        
        -- Text
        gfx.setColour(isSelected and self._selectedTextColour or self._textColour)
        gfx.setFont(11.0)
        gfx.drawText(seg, x, 0, segW, segH, Justify.centred)
    end
    
    -- Border around whole control
    gfx.setColour(Utils.brighten(self._bg, 20))
    gfx.drawRoundedRect(0, 0, w, h, r, 1)
end

function SegmentedControl:getSelected()
    return self._selected
end

function SegmentedControl:setSelected(idx)
    self._selected = Utils.clamp(idx, 1, #self._segments)
end

return SegmentedControl

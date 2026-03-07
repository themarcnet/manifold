-- dropdown.lua
-- Dropdown widget with overlay

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Dropdown = BaseWidget:extend()

function Dropdown.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Dropdown)

    self._options = config.options or {}
    self._selected = config.selected or 1
    self._onSelect = config.on_select or config.onSelect
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._colour = Utils.colour(config.colour, 0xff38bdf8)
    self._open = false
    self._overlay = nil
    self._rootNode = config.rootNode  -- root canvas for overlay placement
    self._maxVisibleRows = config.max_visible_rows or 10
    self._scrollRow = 1

    self:_storeEditorMeta("Dropdown", {
        on_select = self._onSelect
    }, Schema.buildEditorSchema("Dropdown", config))

    return self
end

function Dropdown:getSelectedLabel()
    return self._options[self._selected] or "---"
end

function Dropdown:close()
    if self._overlay then
        self._overlay:setOnDraw(nil)
        self._overlay:setOnClick(nil)
        self._overlay:setOnMouseDown(nil)
        self._overlay:setBounds(0, 0, 0, 0)
        self._open = false
    end
end

function Dropdown:open()
    if self._open then
        self:close()
        return
    end

    self._open = true
    local overlayParent = self._rootNode or self.node
    if not self._overlay then
        self._overlay = overlayParent:addChild(self.name .. "_overlay")
    end

    local itemH = 30
    local optionCount = #self._options
    local visibleRows = math.max(1, math.min(optionCount, self._maxVisibleRows))
    local overlayH = visibleRows * itemH + 4
    local overlayW = math.max(220, self.node:getWidth())

    local maxFirst = math.max(1, optionCount - visibleRows + 1)
    self._scrollRow = Utils.clamp(self._scrollRow or 1, 1, maxFirst)
    if optionCount > 0 then
        if self._selected < self._scrollRow then
            self._scrollRow = self._selected
        elseif self._selected > (self._scrollRow + visibleRows - 1) then
            self._scrollRow = self._selected - visibleRows + 1
        end
        self._scrollRow = Utils.clamp(self._scrollRow, 1, maxFirst)
    end

    local overlayX, overlayY = 0, self.node:getHeight()
    if self._rootNode and self._absX and self._absY then
        overlayX = math.floor(self._absX)
        overlayY = math.floor(self._absY + self.node:getHeight())

        local rootH = self._rootNode:getHeight()
        local rootW = self._rootNode:getWidth()

        if overlayY + overlayH > rootH then
            overlayY = math.floor(self._absY - overlayH)
        end
        overlayY = Utils.clamp(overlayY, 0, math.max(0, rootH - overlayH))

        if overlayX + overlayW > rootW then
            overlayX = math.max(0, rootW - overlayW)
        end
    end

    self._overlay:setBounds(
        math.floor(overlayX),
        math.floor(overlayY),
        math.floor(overlayW),
        math.floor(overlayH)
    )

    local dropdown = self
    self._overlay:setInterceptsMouse(true, true)
    self._overlay:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        gfx.setColour(0x40000000)
        gfx.fillRoundedRect(2, 2, w, h, 6)
        gfx.setColour(0xff1e293b)
        gfx.fillRoundedRect(0, 0, w - 2, h - 2, 6)
        gfx.setColour(0xff475569)
        gfx.drawRoundedRect(0, 0, w - 2, h - 2, 6, 1)

        local first = dropdown._scrollRow
        local last = math.min(optionCount, first + visibleRows - 1)
        local hasScroll = optionCount > visibleRows
        local hasMoreAbove = first > 1
        local hasMoreBelow = last < optionCount
        local scrollbarW = hasScroll and 14 or 0
        local textW = w - 24 - scrollbarW
        local row = 0

        for i = first, last do
            row = row + 1
            local opt = dropdown._options[i]
            local y = 2 + (row - 1) * itemH
            local isSel = (i == dropdown._selected)
            if isSel then
                gfx.setColour(0xff334155)
                gfx.fillRoundedRect(2, y, w - 6, itemH, 4)
            end
            gfx.setColour(isSel and dropdown._colour or 0xffe2e8f0)
            gfx.setFont(12.0)
            gfx.drawText(opt, 12, math.floor(y), textW, itemH, Justify.centredLeft)
        end

        if hasScroll then
            local trackX = w - scrollbarW - 6
            local trackY = 4
            local trackH = h - 10
            local thumbTravel = math.max(1, trackH - 28)
            local thumbH = math.max(18, math.floor((visibleRows / math.max(1, optionCount)) * thumbTravel))
            local maxScrollRows = math.max(1, optionCount - visibleRows)
            local scrollT = (dropdown._scrollRow - 1) / maxScrollRows
            local thumbY = trackY + 14 + math.floor((thumbTravel - thumbH) * scrollT)

            gfx.setColour(0xff0f172a)
            gfx.fillRoundedRect(trackX, trackY, scrollbarW, trackH, 4)
            gfx.setColour(0xff334155)
            gfx.drawRoundedRect(trackX, trackY, scrollbarW, trackH, 4, 1)

            gfx.setColour(hasMoreAbove and 0xffcbd5e1 or 0xff475569)
            gfx.setFont(9.0)
            gfx.drawText("▲", trackX, trackY + 1, scrollbarW, 12, Justify.centred)

            gfx.setColour(hasMoreBelow and 0xffcbd5e1 or 0xff475569)
            gfx.drawText("▼", trackX, trackY + trackH - 13, scrollbarW, 12, Justify.centred)

            gfx.setColour(0xff38bdf8)
            gfx.fillRoundedRect(trackX + 2, thumbY, math.max(6, scrollbarW - 4), thumbH, 3)

            if hasMoreAbove then
                gfx.setColour(0x221e40af)
                gfx.fillRoundedRect(2, 2, w - 6, 12, 3)
            end
            if hasMoreBelow then
                gfx.setColour(0x221e40af)
                gfx.fillRoundedRect(2, h - 16, w - 6, 12, 3)
            end
        end
    end)

    self._overlay:setOnMouseWheel(function(mx, my, deltaY)
        if optionCount <= visibleRows then
            return
        end
        local step = (deltaY and deltaY > 0) and -1 or 1
        local maxFirst = math.max(1, optionCount - visibleRows + 1)
        dropdown._scrollRow = Utils.clamp(dropdown._scrollRow + step, 1, maxFirst)
        dropdown._overlay:repaint()
    end)

    self._overlay:setOnMouseDown(function(mx, my)
        local row = math.floor((my - 2) / itemH) + 1
        if row >= 1 and row <= visibleRows then
            local idx = dropdown._scrollRow + row - 1
            if idx >= 1 and idx <= optionCount then
                dropdown._selected = idx
                if dropdown._onSelect then
                    dropdown._onSelect(dropdown._selected, dropdown._options[dropdown._selected])
                end
            end
        end
        dropdown:close()
    end)
end

function Dropdown:onClick()
    self:open()
end

function Dropdown:onDraw(w, h)
    local bg = self:isHovered() and Utils.brighten(self._bg, 15) or self._bg
    
    gfx.setColour(bg)
    gfx.fillRoundedRect(1, 1, math.floor(w - 2), math.floor(h - 2), 6)
    gfx.setColour(Utils.brighten(bg, 30))
    gfx.drawRoundedRect(1, 1, math.floor(w - 2), math.floor(h - 2), 6, 1)
    
    -- Selected text
    gfx.setColour(0xffe2e8f0)
    gfx.setFont(12.0)
    gfx.drawText(self:getSelectedLabel(), 10, 0, math.floor(w - 30), h, Justify.centredLeft)
    
    -- Arrow
    gfx.setColour(0xff94a3b8)
    gfx.setFont(10.0)
    gfx.drawText(self._open and "▲" or "▼", math.floor(w - 22), 0, 16, h, Justify.centred)
end

function Dropdown:getSelected()
    return self._selected
end

function Dropdown:setSelected(idx)
    self._selected = Utils.clamp(idx, 1, #self._options)
end

function Dropdown:setOptions(opts)
    self._options = opts or {}
    self._selected = Utils.clamp(self._selected, 1, math.max(1, #self._options))
    self._scrollRow = 1
    self.node:repaint()
end

function Dropdown:setAbsolutePos(ax, ay)
    self._absX = ax
    self._absY = ay
end

return Dropdown

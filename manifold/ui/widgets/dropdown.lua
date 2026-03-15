-- dropdown.lua
-- Dropdown widget with overlay

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Dropdown = BaseWidget:extend()

local function setTransparentStyle(node)
    node:setStyle({
        bg = 0x00000000,
        border = 0x00000000,
        borderWidth = 0,
        radius = 0,
        opacity = 1.0,
    })
end

local function buildMainDisplayList(self, w, h)
    local bg = self:isHovered() and Utils.brighten(self._bg, 15) or self._bg
    return {
        {
            cmd = "fillRoundedRect",
            x = 1,
            y = 1,
            w = math.floor(w - 2),
            h = math.floor(h - 2),
            radius = 6,
            color = bg,
        },
        {
            cmd = "drawRoundedRect",
            x = 1,
            y = 1,
            w = math.floor(w - 2),
            h = math.floor(h - 2),
            radius = 6,
            thickness = 1,
            color = Utils.brighten(bg, 30),
        },
        {
            cmd = "drawText",
            x = 10,
            y = 0,
            w = math.max(0, math.floor(w - 30)),
            h = h,
            color = 0xffe2e8f0,
            text = self:getSelectedLabel(),
            fontSize = 12.0,
            align = "left",
            valign = "middle",
        },
        {
            cmd = "drawText",
            x = math.floor(w - 22),
            y = 0,
            w = 16,
            h = h,
            color = 0xff94a3b8,
            text = self._open and "▲" or "▼",
            fontSize = 10.0,
            align = "center",
            valign = "middle",
        }
    }
end

local function buildOverlayDisplayList(self, w, h, optionCount, visibleRows, itemH)
    local display = {
        {
            cmd = "fillRoundedRect",
            x = 2,
            y = 2,
            w = w,
            h = h,
            radius = 6,
            color = 0x40000000,
        },
        {
            cmd = "fillRoundedRect",
            x = 0,
            y = 0,
            w = math.max(0, w - 2),
            h = math.max(0, h - 2),
            radius = 6,
            color = 0xff1e293b,
        },
        {
            cmd = "drawRoundedRect",
            x = 0,
            y = 0,
            w = math.max(0, w - 2),
            h = math.max(0, h - 2),
            radius = 6,
            thickness = 1,
            color = 0xff475569,
        }
    }

    local first = self._scrollRow
    local last = math.min(optionCount, first + visibleRows - 1)
    local hasScroll = optionCount > visibleRows
    local hasMoreAbove = first > 1
    local hasMoreBelow = last < optionCount
    local scrollbarW = hasScroll and 14 or 0
    local textW = w - 24 - scrollbarW
    local row = 0

    for i = first, last do
        row = row + 1
        local opt = self._options[i]
        local y = 2 + (row - 1) * itemH
        local isSel = (i == self._selected)
        if isSel then
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = 2,
                y = y,
                w = math.max(0, w - 6),
                h = itemH,
                radius = 4,
                color = 0xff334155,
            }
        end
        display[#display + 1] = {
            cmd = "drawText",
            x = 12,
            y = math.floor(y),
            w = math.max(0, textW),
            h = itemH,
            color = isSel and self._colour or 0xffe2e8f0,
            text = tostring(opt),
            fontSize = 12.0,
            align = "left",
            valign = "middle",
        }
    end

    if hasScroll then
        local trackX = w - scrollbarW - 6
        local trackY = 4
        local trackH = h - 10
        local thumbTravel = math.max(1, trackH - 28)
        local thumbH = math.max(18, math.floor((visibleRows / math.max(1, optionCount)) * thumbTravel))
        local maxScrollRows = math.max(1, optionCount - visibleRows)
        local scrollT = (self._scrollRow - 1) / maxScrollRows
        local thumbY = trackY + 14 + math.floor((thumbTravel - thumbH) * scrollT)

        display[#display + 1] = {
            cmd = "fillRoundedRect",
            x = trackX,
            y = trackY,
            w = scrollbarW,
            h = trackH,
            radius = 4,
            color = 0xff0f172a,
        }
        display[#display + 1] = {
            cmd = "drawRoundedRect",
            x = trackX,
            y = trackY,
            w = scrollbarW,
            h = trackH,
            radius = 4,
            thickness = 1,
            color = 0xff334155,
        }
        display[#display + 1] = {
            cmd = "drawText",
            x = trackX,
            y = trackY + 1,
            w = scrollbarW,
            h = 12,
            color = hasMoreAbove and 0xffcbd5e1 or 0xff475569,
            text = "▲",
            fontSize = 9.0,
            align = "center",
            valign = "middle",
        }
        display[#display + 1] = {
            cmd = "drawText",
            x = trackX,
            y = trackY + trackH - 13,
            w = scrollbarW,
            h = 12,
            color = hasMoreBelow and 0xffcbd5e1 or 0xff475569,
            text = "▼",
            fontSize = 9.0,
            align = "center",
            valign = "middle",
        }
        display[#display + 1] = {
            cmd = "fillRoundedRect",
            x = trackX + 2,
            y = thumbY,
            w = math.max(6, scrollbarW - 4),
            h = thumbH,
            radius = 3,
            color = 0xff38bdf8,
        }

        if hasMoreAbove then
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = 2,
                y = 2,
                w = math.max(0, w - 6),
                h = 12,
                radius = 3,
                color = 0x221e40af,
            }
        end
        if hasMoreBelow then
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = 2,
                y = h - 16,
                w = math.max(0, w - 6),
                h = 12,
                radius = 3,
                color = 0x221e40af,
            }
        end
    end

    return display
end

function Dropdown.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Dropdown)

    self._options = config.options or {}
    self._selected = config.selected or 1
    self._onSelect = config.on_select or config.onSelect
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._colour = Utils.colour(config.colour, 0xff38bdf8)
    self._open = false
    self._overlay = nil
    self._rootNode = config.rootNode
    self._maxVisibleRows = config.max_visible_rows or 10
    self._scrollRow = 1

    self:_storeEditorMeta("Dropdown", {
        on_select = self._onSelect
    }, Schema.buildEditorSchema("Dropdown", config))

    self:_syncRetained()

    return self
end

local function optionsEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if tostring(a[i]) ~= tostring(b[i]) then
            return false
        end
    end
    return true
end

function Dropdown:getSelectedLabel()
    return self._options[self._selected] or "---"
end

function Dropdown:_syncRetained(w, h)
    local _, _, bw, bh = self.node:getBounds()
    w = w or bw or 0
    h = h or bh or 0
    setTransparentStyle(self.node)
    self.node:setDisplayList(buildMainDisplayList(self, w, h))
end

function Dropdown:_syncOverlayRetained()
    if not self._overlay then
        return
    end

    local optionCount = #self._options
    local itemH = 30
    local visibleRows = math.max(1, math.min(optionCount, self._maxVisibleRows))
    local _, _, w, h = self._overlay:getBounds()

    if not self._open or w <= 0 or h <= 0 or optionCount <= 0 then
        self._overlay:clearDisplayList()
        self._overlay:setStyle({ bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
        return
    end

    setTransparentStyle(self._overlay)
    self._overlay:setDisplayList(buildOverlayDisplayList(self, w, h, optionCount, visibleRows, itemH))
end

function Dropdown:close()
    if self._overlay then
        if (not self._runtimeNodeOnly) and self._overlay.setOnDraw then
            self._overlay:setOnDraw(nil)
        end
        self._overlay:setOnClick(nil)
        self._overlay:setOnMouseDown(nil)
        self._overlay:setOnMouseWheel(nil)
        self._overlay:setVisible(false)
        self._overlay:setBounds(0, 0, 0, 0)
        self._overlay:clearDisplayList()
        self._overlay:setStyle({ bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0, opacity = 1.0 })
        self._overlay:repaint()
    end
        self._open = false
    self:_syncRetained()
    self.node:repaint()
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
        self._overlay:setWidgetType("DropdownOverlay")
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

    self._overlay:setVisible(true)
    self._overlay:setZOrder(100)  -- Ensure overlay renders on top
    self._overlay:setBounds(
        math.floor(overlayX),
        math.floor(overlayY),
        math.floor(overlayW),
        math.floor(overlayH)
    )

    local dropdown = self
    self._overlay:setInterceptsMouse(true, true)
    if (not self._runtimeNodeOnly) and self._overlay.setOnDraw then
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
    end

    self._overlay:setOnMouseWheel(function(mx, my, deltaY)
        if optionCount <= visibleRows then
            return
        end
        local step = (deltaY and deltaY > 0) and -1 or 1
        local maxFirst = math.max(1, optionCount - visibleRows + 1)
        dropdown._scrollRow = Utils.clamp(dropdown._scrollRow + step, 1, maxFirst)
        dropdown:_syncOverlayRetained()
        dropdown._overlay:repaint()
    end)

    self._overlay:setOnMouseDown(function(mx, my)
        local row = math.floor((my - 2) / itemH) + 1
        if row >= 1 and row <= visibleRows then
            local idx = dropdown._scrollRow + row - 1
            if idx >= 1 and idx <= optionCount then
                dropdown._selected = idx
                dropdown:_syncRetained()
                if dropdown._onSelect then
                    dropdown._onSelect(dropdown._selected, dropdown._options[dropdown._selected])
                end
            end
        end
        dropdown:close()
    end)

    self:_syncRetained()
    self:_syncOverlayRetained()
    self.node:repaint()
    self._overlay:repaint()
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

    gfx.setColour(0xffe2e8f0)
    gfx.setFont(12.0)
    gfx.drawText(self:getSelectedLabel(), 10, 0, math.floor(w - 30), h, Justify.centredLeft)

    gfx.setColour(0xff94a3b8)
    gfx.setFont(10.0)
    gfx.drawText(self._open and "▲" or "▼", math.floor(w - 22), 0, 16, h, Justify.centred)
end

function Dropdown:getSelected()
    return self._selected
end

function Dropdown:setSelected(idx)
    local nextSelected = Utils.clamp(idx, 1, math.max(1, #self._options))
    if self._selected == nextSelected then
        return
    end
    self._selected = nextSelected
    self:_syncRetained()
    if self._overlay then
        self:_syncOverlayRetained()
    end
    self.node:repaint()
end

function Dropdown:setOptions(opts)
    local nextOptions = opts or {}
    local nextSelected = Utils.clamp(self._selected, 1, math.max(1, #nextOptions))
    if optionsEqual(self._options, nextOptions) and self._selected == nextSelected then
        return
    end
    self._options = nextOptions
    self._selected = nextSelected
    self._scrollRow = 1
    self:_syncRetained()
    if self._overlay then
        self:_syncOverlayRetained()
    end
    self.node:repaint()
end

function Dropdown:setAbsolutePos(ax, ay)
    self._absX = ax
    self._absY = ay
end

return Dropdown

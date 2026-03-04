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
    local overlayH = #self._options * itemH + 4
    local overlayW = math.max(160, self.node:getWidth())
    
    if self._rootNode and self._absX and self._absY then
        -- Position on root canvas using stored absolute coordinates
        self._overlay:setBounds(
            math.floor(self._absX),
            math.floor(self._absY + self.node:getHeight()),
            math.floor(overlayW),
            math.floor(overlayH)
        )
    else
        -- Fallback: child of self (will clip)
        self._overlay:setBounds(0, self.node:getHeight(), self.node:getWidth(), overlayH)
    end
    
    local dropdown = self
    self._overlay:setInterceptsMouse(true, true)
    self._overlay:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        -- Drop shadow
        gfx.setColour(0x40000000)
        gfx.fillRoundedRect(2, 2, w, h, 6)
        -- Background
        gfx.setColour(0xff1e293b)
        gfx.fillRoundedRect(0, 0, w - 2, h - 2, 6)
        gfx.setColour(0xff475569)
        gfx.drawRoundedRect(0, 0, w - 2, h - 2, 6, 1)
        
        for i, opt in ipairs(dropdown._options) do
            local y = 2 + (i - 1) * itemH
            local isSel = (i == dropdown._selected)
            if isSel then
                gfx.setColour(0xff334155)
                gfx.fillRoundedRect(2, y, w - 6, itemH, 4)
            end
            gfx.setColour(isSel and dropdown._colour or 0xffe2e8f0)
            gfx.setFont(12.0)
            gfx.drawText(opt, 12, math.floor(y), w - 24, itemH, Justify.centredLeft)
        end
    end)
    
    self._overlay:setOnMouseDown(function(mx, my)
        local idx = math.floor((my - 2) / itemH) + 1
        if idx >= 1 and idx <= #dropdown._options then
            dropdown._selected = idx
            if dropdown._onSelect then
                dropdown._onSelect(dropdown._selected, dropdown._options[dropdown._selected])
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
    self._options = opts
end

function Dropdown:setAbsolutePos(ax, ay)
    self._absX = ax
    self._absY = ay
end

return Dropdown

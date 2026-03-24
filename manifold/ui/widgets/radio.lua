-- radio.lua
-- Radio widget (multi-button selector)

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local Radio = BaseWidget:extend()

function Radio.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Radio)

    self._options = config.options or {}
    self._selected = config.selected or 1
    self._onChange = config.on_change or config.onChange
    self._bg = Utils.colour(config.bg, 0xff1e293b)
    self._selectedBg = Utils.colour(config.selectedBg, 0xff3b82f6)
    self._textColour = Utils.colour(config.textColour, 0xffe2e8f0)
    self._selectedTextColour = Utils.colour(config.selectedTextColour, 0xffffffff)

    self:_storeEditorMeta("Radio", {
        on_change = self._onChange
    }, Schema.buildEditorSchema("Radio", config))

    self:_syncRetained()

    return self
end

function Radio:onMouseDown(mx, my)
    local count = #self._options
    if count <= 0 then
        return
    end

    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local segW = w / count
    local idx = math.floor(mx / segW) + 1
    
    if idx >= 1 and idx <= count then
        self._selected = idx
        self:_syncRetained(w, h)
        self.node:repaint()
        if self._onChange then
            self._onChange(idx)
        end
    end
end

function Radio:onDraw(w, h)
    local segW = math.floor(w / #self._options)
    local segH = h
    local r = 6
    
    for i, opt in ipairs(self._options) do
        local x = math.floor((i - 1) * segW)
        local isSelected = (i == self._selected)
        local isHovered = self:isHovered()
        
        local bg = isSelected and self._selectedBg or self._bg
        if isHovered and not isSelected then
            bg = Utils.brighten(bg, 10)
        end
        
        gfx.setColour(bg)
        if i == 1 then
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        elseif i == #self._options then
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        else
            gfx.fillRect(x, 0, segW, segH)
        end
        
        gfx.setColour(isSelected and self._selectedTextColour or self._textColour)
        gfx.setFont(11.0)
        gfx.drawText(opt, x, 0, segW, segH, Justify.centred)
    end
    
    gfx.setColour(Utils.brighten(self._bg, 20))
    gfx.drawRoundedRect(0, 0, w, h, r, 1)
end

function Radio:_syncRetained(w, h)
    local _, _, bw, bh = self.node:getBounds()
    w = w or bw or 0
    h = h or bh or 0

    local count = math.max(1, #self._options)
    local segW = math.floor(w / count)
    local display = {}
    local isHovered = self:isHovered()

    for i, opt in ipairs(self._options) do
        local x = math.floor((i - 1) * segW)
        local nextX = (i == count) and w or math.floor(i * segW)
        local cellW = math.max(0, nextX - x)
        local isSelected = (i == self._selected)
        local bg = isSelected and self._selectedBg or self._bg
        if isHovered and not isSelected then
            bg = Utils.brighten(bg, 10)
        end

        display[#display + 1] = {
            cmd = "fillRect",
            x = x,
            y = 0,
            w = cellW,
            h = h,
            color = bg,
        }
        display[#display + 1] = {
            cmd = "drawText",
            x = x,
            y = 0,
            w = cellW,
            h = h,
            color = isSelected and self._selectedTextColour or self._textColour,
            text = tostring(opt),
            fontSize = 11.0,
            align = "center",
            valign = "middle",
        }
    end

    self.node:setStyle({
        bg = 0x00000000,
        border = Utils.brighten(self._bg, 20),
        borderWidth = 1.0,
        radius = 6,
        opacity = 1.0
    })
    self.node:setDisplayList(display)
end

function Radio:getSelected()
    return self._selected
end

function Radio:setSelected(idx)
    self._selected = Utils.clamp(idx, 1, #self._options)
    self:_syncRetained()
    self.node:repaint()
end

return Radio

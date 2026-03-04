-- xypad.lua
-- 2D control surface with trails

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")

local XYPadWidget = BaseWidget:extend()

local function xyHsvToRgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

function XYPadWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), XYPadWidget)

    self._x = config.x or 0.5
    self._y = config.y or 0.5
    self._handleColour = Utils.colour(config.handleColour, 0xffff8800)
    self._trailColour = Utils.colour(config.trailColour, 0xff22d3ee)
    self._bgColour = Utils.colour(config.bgColour, 0x00000000)
    self._gridColour = Utils.colour(config.gridColour, 0x00000000)
    self._showTrails = config.showTrails ~= false
    self._maxTrails = config.maxTrails or 50
    self._trails = {}
    self._onChange = config.on_change or config.onChange

    self:_storeEditorMeta("XYPadWidget", {
        on_change = self._onChange,
    }, {})

    self:exposeParams({
        { path = "handleColour", label = "Handle Colour", type = "color", group = "Style" },
        { path = "trailColour", label = "Trail Colour", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "gridColour", label = "Grid", type = "color", group = "Style" },
        { path = "showTrails", label = "Show Trails", type = "bool", group = "Behavior" },
    })

    return self
end

function XYPadWidget:onMouseDown(mx, my)
    self:_updateFromMouse(mx, my)
end

function XYPadWidget:onMouseDrag(mx, my, dx, dy)
    self:_updateFromMouse(mx, my)
end

function XYPadWidget:_updateFromMouse(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local margin = 20

    self._x = Utils.clamp((mx - margin) / (w - margin * 2), 0, 1)
    self._y = Utils.clamp((my - margin) / (h - margin * 2), 0, 1)

    if self._showTrails then
        table.insert(self._trails, 1, { x = self._x, y = self._y, life = 1.0 })
        if #self._trails > self._maxTrails then
            table.remove(self._trails)
        end
    end

    if self._onChange then
        self._onChange(self._x, self._y)
    end
end

function XYPadWidget:updateTrails(dt)
    for i = #self._trails, 1, -1 do
        local trail = self._trails[i]
        trail.life = trail.life - dt * 2
        if trail.life <= 0 then
            table.remove(self._trails, i)
        end
    end
end

function XYPadWidget:getValues()
    return self._x, self._y
end

function XYPadWidget:setValues(x, y)
    self._x = Utils.clamp(x or 0.5, 0, 1)
    self._y = Utils.clamp(y or 0.5, 0, 1)
end

function XYPadWidget:onDraw(w, h)
    local margin = 20
    local drawW = w - margin * 2
    local drawH = h - margin * 2

    -- Background
    gfx.setColour(self._bgColour)
    gfx.fillRoundedRect(margin, margin, drawW, drawH, 8)

    -- Grid lines
    gfx.setColour(self._gridColour)
    for i = 1, 4 do
        local x = margin + (drawW / 5) * i
        local y = margin + (drawH / 5) * i
        gfx.drawVerticalLine(math.floor(x), margin, drawH)
        gfx.drawHorizontalLine(math.floor(y), margin, drawW)
    end

    -- Crosshair center
    local cx = margin + drawW / 2
    local cy = margin + drawH / 2
    gfx.setColour(Utils.brighten(self._gridColour, 20))
    gfx.drawVerticalLine(math.floor(cx), margin, drawH)
    gfx.drawHorizontalLine(math.floor(cy), margin, drawW)

    -- Trails
    if self._showTrails then
        local tc = self._trailColour or 0xff22d3ee
        local ta = (tc >> 24) & 0xff
        local tr = (tc >> 16) & 0xff
        local tg = (tc >> 8) & 0xff
        local tb = tc & 0xff
        
        for i, trail in ipairs(self._trails) do
            local tx = margin + trail.x * drawW
            local ty = margin + trail.y * drawH
            local size = 4 + (1 - i / #self._trails) * 8
            local lifeAlpha = trail.life * 150 / 255
            
            local hue = i / #self._trails
            local hr, hg, hb = xyHsvToRgb(hue, 0.9, 1.0)
            local blend = 0.5
            local r = math.floor(tr * blend + hr * (1-blend))
            local g = math.floor(tg * blend + hg * (1-blend))
            local b = math.floor(tb * blend + hb * (1-blend))
            local alpha = math.floor(ta * lifeAlpha)
            
            local color = (alpha << 24) | (r << 16) | (g << 8) | b
            gfx.setColour(color)
            gfx.fillRoundedRect(math.floor(tx - size/2), math.floor(ty - size/2),
                               math.floor(size), math.floor(size), size/2)
        end
    end

    -- Current position
    local px = margin + self._x * drawW
    local py = margin + self._y * drawH

    -- Glow
    for i = 3, 1, -1 do
        local glowSize = 8 + i * 4
        local alpha = 50 - i * 15
        gfx.setColour((alpha << 24) | 0xff4400)
        gfx.fillRoundedRect(math.floor(px - glowSize/2), math.floor(py - glowSize/2),
                           math.floor(glowSize), math.floor(glowSize), glowSize/2)
    end

    -- Handle
    gfx.setColour(self._handleColour)
    gfx.fillRoundedRect(math.floor(px - 6), math.floor(py - 6), 12, 12, 6)
    gfx.setColour(0xffffffff)
    gfx.fillRoundedRect(math.floor(px - 3), math.floor(py - 3), 6, 6, 3)

    -- Coordinates label
    gfx.setColour(0xffffffff)
    gfx.setFont(11.0)
    local label = string.format("X: %.2f  Y: %.2f", self._x, self._y)
    gfx.drawText(label, margin, h - 18, drawW, 16, Justify.centred)
end

return XYPadWidget

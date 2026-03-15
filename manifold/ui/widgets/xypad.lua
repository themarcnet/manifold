-- xypad.lua
-- 2D control surface - clean base widget with immediate drag updates and enhanced styling

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")

local XYPadWidget = BaseWidget:extend()

local function boundsSize(node)
    local _, _, w, h = node:getBounds()
    return w or 0, h or 0
end

local function setTransparentStyle(node)
    node:setStyle({
        bg = 0x00000000,
        border = 0x00000000,
        borderWidth = 0,
        radius = 0,
        opacity = 1.0,
    })
end

function XYPadWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), XYPadWidget)

    self._x = config.x or 0.5
    self._y = config.y or 0.5
    -- Enhanced default styling matching MidiSynth's aesthetic
    self._handleColour = Utils.colour(config.handleColour, 0xff22d3ee)  -- Cyan default like MidiSynth
    self._bgColour = Utils.colour(config.bgColour, 0xff0d1420)         -- Dark blue-grey background
    self._gridColour = Utils.colour(config.gridColour, 0xff1a1a3a)     -- Subtle grid
    self._onChange = config.on_change or config.onChange
    self._dragging = false

    self:_storeEditorMeta("XYPadWidget", {
        on_change = self._onChange,
    }, {})

    self:exposeParams({
        { path = "handleColour", label = "Handle Colour", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "gridColour", label = "Grid", type = "color", group = "Style" },
    })

    self:refreshRetained()

    return self
end

function XYPadWidget:onMouseDown(mx, my)
    self._dragging = true
    self:_updateFromMouse(mx, my)
end

function XYPadWidget:onMouseDrag(mx, my, dx, dy)
    if self._dragging then
        self:_updateFromMouse(mx, my)
    end
end

function XYPadWidget:onMouseUp(mx, my)
    self._dragging = false
    -- Refresh retained to update visual state (handle size, etc)
    self:refreshRetained()
    self.node:repaint()
end

function XYPadWidget:_updateFromMouse(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local margin = 20

    self._x = Utils.clamp((mx - margin) / (w - margin * 2), 0, 1)
    self._y = 1.0 - Utils.clamp((my - margin) / (h - margin * 2), 0, 1)

    -- IMMEDIATE update during drag - bypass deferred refresh for responsiveness
    local bw, bh = boundsSize(self.node)
    w = w or bw
    h = h or bh
    self:_syncRetained(w, h)
    self.node:repaint()

    if self._onChange then
        self._onChange(self._x, self._y)
    end
end

function XYPadWidget:getValues()
    return self._x, self._y
end

function XYPadWidget:setValues(x, y)
    self._x = Utils.clamp(x or 0.5, 0, 1)
    self._y = Utils.clamp(y or 0.5, 0, 1)
    self:refreshRetained()
    self.node:repaint()
end

function XYPadWidget:onDraw(w, h)
    -- Delegate to retained sync for consistent rendering
    self:_syncRetained(w, h)
end

function XYPadWidget:_syncRetained(w, h)
    local bw, bh = boundsSize(self.node)
    w = w or bw
    h = h or bh

    local margin = 20
    local drawW = math.max(1, w - margin * 2)
    local drawH = math.max(1, h - margin * 2)
    local cx = margin + drawW * 0.5
    local cy = margin + drawH * 0.5
    local px = margin + self._x * drawW
    local py = margin + (1.0 - self._y) * drawH

    -- Calculate dim/mid colors from handle color (like MidiSynth)
    local col = self._handleColour
    local colDim = (0x18 << 24) | (col & 0x00ffffff)
    local colMid = (0x44 << 24) | (col & 0x00ffffff)
    local colLabel = (0x88 << 24) | (col & 0x00ffffff)

    local display = {
        {
            cmd = "fillRoundedRect",
            x = margin,
            y = margin,
            w = drawW,
            h = drawH,
            radius = 8,
            color = self._bgColour,
        }
    }

    -- Grid lines (subtle)
    for i = 1, 3 do
        local gx = math.floor(margin + (drawW / 4) * i + 0.5)
        local gy = math.floor(margin + (drawH / 4) * i + 0.5)
        display[#display + 1] = {
            cmd = "drawLine",
            x1 = gx,
            y1 = margin,
            x2 = gx,
            y2 = margin + drawH,
            thickness = 1,
            color = self._gridColour,
        }
        display[#display + 1] = {
            cmd = "drawLine",
            x1 = margin,
            y1 = gy,
            x2 = margin + drawW,
            y2 = gy,
            thickness = 1,
            color = self._gridColour,
        }
    end

    -- Crosshair at center
    local crossColour = Utils.brighten(self._gridColour, 20)
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = math.floor(cx + 0.5),
        y1 = margin,
        x2 = math.floor(cx + 0.5),
        y2 = margin + drawH,
        thickness = 1,
        color = crossColour,
    }
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = margin,
        y1 = math.floor(cy + 0.5),
        x2 = margin + drawW,
        y2 = math.floor(cy + 0.5),
        thickness = 1,
        color = crossColour,
    }

    -- Crosshair at current position (like MidiSynth)
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = math.floor(px + 0.5),
        y1 = margin,
        x2 = math.floor(px + 0.5),
        y2 = margin + drawH,
        thickness = 1,
        color = colMid,
    }
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = margin,
        y1 = math.floor(py + 0.5),
        x2 = margin + drawW,
        y2 = math.floor(py + 0.5),
        thickness = 1,
        color = colMid,
    }

    -- Filled quadrant (like MidiSynth - shows the "active" region)
    display[#display + 1] = {
        cmd = "fillRect",
        x = margin,
        y = py,
        w = px - margin,
        h = margin + drawH - py,
        color = colDim,
    }

    -- Glow effect (3-layer, larger when dragging)
    local ptR = self._dragging and 8 or 6
    for i = 3, 1, -1 do
        local glowSize = ptR * 2 + i * 6
        local alpha = 60 - i * 18
        display[#display + 1] = {
            cmd = "fillRoundedRect",
            x = math.floor(px - glowSize / 2 + 0.5),
            y = math.floor(py - glowSize / 2 + 0.5),
            w = math.floor(glowSize + 0.5),
            h = math.floor(glowSize + 0.5),
            radius = glowSize / 2,
            color = (alpha << 24) | (col & 0x00ffffff),
        }
    end

    -- Outer handle ring (white when dragging, handle color otherwise)
    display[#display + 1] = {
        cmd = "fillRoundedRect",
        x = math.floor(px - ptR - 1 + 0.5),
        y = math.floor(py - ptR - 1 + 0.5),
        w = (ptR + 1) * 2,
        h = (ptR + 1) * 2,
        radius = ptR + 1,
        color = self._dragging and 0x33ffffff or (0x22 << 24) | (col & 0x00ffffff),
    }

    -- Main handle
    display[#display + 1] = {
        cmd = "fillRoundedRect",
        x = math.floor(px - 5 + 0.5),
        y = math.floor(py - 5 + 0.5),
        w = 10,
        h = 10,
        radius = 5,
        color = self._dragging and col or 0xffffffff,
    }

    -- Inner dot
    display[#display + 1] = {
        cmd = "fillRoundedRect",
        x = math.floor(px - 2 + 0.5),
        y = math.floor(py - 2 + 0.5),
        w = 4,
        h = 4,
        radius = 2,
        color = self._dragging and 0xffffffff or col,
    }

    -- X/Y value labels at edges (like MidiSynth)
    local xName = "X"
    local yName = "Y"
    display[#display + 1] = {
        cmd = "drawText",
        x = margin + 4,
        y = h - margin - 14,
        w = math.floor(drawW * 0.4),
        h = 12,
        text = string.format("%s: %.0f%%", xName, self._x * 100),
        color = colLabel,
        fontSize = 9,
        align = "left",
        valign = "middle",
    }
    display[#display + 1] = {
        cmd = "drawText",
        x = margin + math.floor(drawW * 0.6) - 4,
        y = margin + 2,
        w = math.floor(drawW * 0.4),
        h = 12,
        text = string.format("%s: %.0f%%", yName, self._y * 100),
        color = colLabel,
        fontSize = 9,
        align = "right",
        valign = "top",
    }

    setTransparentStyle(self.node)
    self.node:setDisplayList(display)
end

return XYPadWidget

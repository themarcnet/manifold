local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local CurveWidget = BaseWidget:extend()

local function boundsSize(node)
    local _, _, w, h = node:getBounds()
    return w or 0, h or 0
end

local function clamp01(v)
    return Utils.clamp(tonumber(v) or 0, 0, 1)
end

local function toCurveY(y)
    return Utils.clamp(tonumber(y) or 0, -1, 1)
end

local function defaultSampler(x)
    return Utils.clamp(tonumber(x) or 0, -1, 1)
end

local function pointDistanceSq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

function CurveWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), CurveWidget)

    self._colour = Utils.colour(config.colour, 0xfff97316)
    self._bg = Utils.colour(config.bg, 0xff0d1420)
    self._gridColour = Utils.colour(config.gridColour, 0xff1a1a3a)
    self._axisColour = Utils.colour(config.axisColour, 0xff334155)
    self._title = tostring(config.title or "")
    self._editable = config.editable == true
    self._readOnly = not self._editable
    self._curveSampler = defaultSampler
    self._controlPoints = {}
    self._dragIndex = nil
    self._onControlChange = config.on_control_change or config.onControlChange

    if self.node and self.node.setInterceptsMouse then
        self.node:setInterceptsMouse(self._editable, false)
    end

    self:_storeEditorMeta("CurveWidget", {
        on_control_change = self._onControlChange,
    }, Schema.buildEditorSchema("CurveWidget", config))

    self:refreshRetained()
    return self
end

function CurveWidget:setCurveSampler(fn)
    self._curveSampler = type(fn) == "function" and fn or defaultSampler
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:setControlPoints(points)
    local nextPoints = {}
    if type(points) == "table" then
        for i = 1, #points do
            local p = points[i]
            if type(p) == "table" then
                nextPoints[#nextPoints + 1] = {
                    x = clamp01(p.x),
                    y = clamp01(p.y),
                    mirrored = p.mirrored == true,
                    label = p.label and tostring(p.label) or nil,
                }
            end
        end
    end
    self._controlPoints = nextPoints
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:setEditable(editable)
    self._editable = editable == true
    self._readOnly = not self._editable
    if self.node and self.node.setInterceptsMouse then
        self.node:setInterceptsMouse(self._editable, false)
    end
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:setTitle(title)
    self._title = tostring(title or "")
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:setColour(value)
    self._colour = Utils.colour(value, self._colour)
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:_contentRect(w, h)
    local topPad = (self._title ~= "") and 14 or 4
    return 4, topPad, math.max(1, w - 8), math.max(1, h - topPad - 4)
end

function CurveWidget:_pointToPixels(px, py, cx, cy, cw, ch)
    local x = cx + px * cw
    local y = cy + py * ch
    return x, y
end

function CurveWidget:_pixelsToPoint(mx, my, cx, cy, cw, ch)
    local px = clamp01((mx - cx) / math.max(1, cw))
    local py = clamp01((my - cy) / math.max(1, ch))
    return px, py
end

function CurveWidget:_hitControlPoint(mx, my)
    if not self._editable then
        return nil
    end

    local w, h = boundsSize(self.node)
    local cx, cy, cw, ch = self:_contentRect(w, h)
    local hitRadius = 7
    local bestIdx = nil
    local bestDist = hitRadius * hitRadius

    for i = 1, #self._controlPoints do
        local p = self._controlPoints[i]
        local px, py = self:_pointToPixels(p.x, p.y, cx, cy, cw, ch)
        local dist = pointDistanceSq(mx, my, px, py)
        if dist <= bestDist then
            bestDist = dist
            bestIdx = i
        end
        if p.mirrored then
            local mxp, myp = self:_pointToPixels(1.0 - p.x, 1.0 - p.y, cx, cy, cw, ch)
            local mdist = pointDistanceSq(mx, my, mxp, myp)
            if mdist <= bestDist then
                bestDist = mdist
                bestIdx = i
            end
        end
    end

    return bestIdx
end

function CurveWidget:onMouseDown(mx, my)
    self._dragIndex = self:_hitControlPoint(mx, my)
end

function CurveWidget:onMouseDrag(mx, my, dx, dy)
    local _ = dx
    local __ = dy
    if not self._editable or not self._dragIndex then
        return
    end

    local w, h = boundsSize(self.node)
    local cx, cy, cw, ch = self:_contentRect(w, h)
    local px, py = self:_pixelsToPoint(mx, my, cx, cy, cw, ch)
    local point = self._controlPoints[self._dragIndex]
    if not point then
        return
    end

    point.x = px
    point.y = py

    if self._onControlChange then
        self._onControlChange(self._dragIndex, px, py)
    end

    self:_syncRetained(w, h)
    self.node:repaint()
end

function CurveWidget:onMouseUp(mx, my)
    local _ = mx
    local __ = my
    self._dragIndex = nil
    self:refreshRetained()
    self.node:repaint()
end

function CurveWidget:onDraw(w, h)
    self:_syncRetained(w, h)
end

function CurveWidget:_syncRetained(w, h)
    local bw, bh = boundsSize(self.node)
    w = w or bw
    h = h or bh

    local cx, cy, cw, ch = self:_contentRect(w, h)
    local color = self._colour
    local curveColor = self:isHovered() and Utils.brighten(color, 10) or color
    local glowColor = (0x24 << 24) | (curveColor & 0x00ffffff)
    local pointGlowColor = (0x40 << 24) | (curveColor & 0x00ffffff)
    local titleColor = 0xffcbd5e1

    local display = {
        {
            cmd = "fillRoundedRect",
            x = 0, y = 0,
            w = w, h = h,
            radius = 6,
            color = self._bg,
        },
        {
            cmd = "fillRoundedRect",
            x = 0, y = 0,
            w = w, h = h,
            radius = 6,
            color = self:isHovered() and 0x18000000 or 0x12000000,
        },
    }

    if self._title ~= "" then
        display[#display + 1] = {
            cmd = "drawText",
            x = 4, y = 1,
            w = math.max(1, w - 8), h = 10,
            color = titleColor,
            text = self._title,
            fontSize = 8,
            align = "left",
            valign = "top",
        }
    end

    for i = 1, 3 do
        local gx = math.floor(cx + (cw / 4) * i + 0.5)
        local gy = math.floor(cy + (ch / 4) * i + 0.5)
        display[#display + 1] = {
            cmd = "drawLine",
            x1 = gx, y1 = cy,
            x2 = gx, y2 = cy + ch,
            thickness = 1,
            color = self._gridColour,
        }
        display[#display + 1] = {
            cmd = "drawLine",
            x1 = cx, y1 = gy,
            x2 = cx + cw, y2 = gy,
            thickness = 1,
            color = self._gridColour,
        }
    end

    local axisX = math.floor(cx + cw * 0.5 + 0.5)
    local axisY = math.floor(cy + ch * 0.5 + 0.5)
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = axisX, y1 = cy,
        x2 = axisX, y2 = cy + ch,
        thickness = 1,
        color = self._axisColour,
    }
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = cx, y1 = axisY,
        x2 = cx + cw, y2 = axisY,
        thickness = 1,
        color = self._axisColour,
    }
    display[#display + 1] = {
        cmd = "drawLine",
        x1 = cx, y1 = cy + ch,
        x2 = cx + cw, y2 = cy,
        thickness = 1,
        color = 0x30ffffff,
    }

    local samples = math.max(16, math.min(48, w))
    local prevX, prevY
    for i = 0, samples do
        local t = i / samples
        local sampleX = t * 2.0 - 1.0
        local sampleY = toCurveY(self._curveSampler(sampleX))
        local px = math.floor(cx + t * cw + 0.5)
        local py = math.floor(cy + (1.0 - (sampleY + 1.0) * 0.5) * ch + 0.5)

        if prevX then
            display[#display + 1] = {
                cmd = "drawLine",
                x1 = prevX, y1 = prevY,
                x2 = px, y2 = py,
                thickness = 4,
                color = glowColor,
            }
            display[#display + 1] = {
                cmd = "drawLine",
                x1 = prevX, y1 = prevY,
                x2 = px, y2 = py,
                thickness = 2,
                color = curveColor,
            }
        end
        prevX, prevY = px, py
    end

    for i = 1, #self._controlPoints do
        local p = self._controlPoints[i]
        local points = {
            { p.x, p.y, self._dragIndex == i },
        }
        if p.mirrored then
            points[#points + 1] = { 1.0 - p.x, 1.0 - p.y, false }
        end

        for pi = 1, #points do
            local pp = points[pi]
            local px, py = self:_pointToPixels(pp[1], pp[2], cx, cy, cw, ch)
            local r = pp[3] and 4 or 3
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = math.floor(px - r - 2 + 0.5), y = math.floor(py - r - 2 + 0.5),
                w = (r + 2) * 2, h = (r + 2) * 2,
                radius = r + 2,
                color = pointGlowColor,
            }
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = math.floor(px - r + 0.5), y = math.floor(py - r + 0.5),
                w = r * 2, h = r * 2,
                radius = r,
                color = 0xffffffff,
            }
            display[#display + 1] = {
                cmd = "fillRoundedRect",
                x = math.floor(px - 1 + 0.5), y = math.floor(py - 1 + 0.5),
                w = 2, h = 2,
                radius = 1,
                color = curveColor,
            }
        end
    end

    self.node:setDisplayList(display)
end

return CurveWidget

-- donut.lua
-- Circular/annular waveform display for loopers

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")

local DonutWidget = BaseWidget:extend()

function DonutWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), DonutWidget)

    self._ringColour = Utils.colour(config.ringColour, 0xff22d3ee)
    self._playheadColour = Utils.colour(config.playheadColour, 0xfff8fafc)
    self._bgColour = Utils.colour(config.bgColour, 0x22475a75)
    self._thickness = config.thickness or 0.4
    self._layerIndex = config.layerIndex or 0
    self._onSeek = config.on_seek or config.onSeek

    self._layerData = {}
    self._peaks = nil
    self._bounce = 0.0

    self.node:setInterceptsMouse(true, false)

    self:_storeEditorMeta("DonutWidget", {
        on_seek = self._onSeek,
    }, {})

    self:exposeParams({
        { path = "ringColour", label = "Ring Colour", type = "color", group = "Style" },
        { path = "playheadColour", label = "Playhead", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "thickness", label = "Thickness", type = "number", min = 0.2, max = 0.8, step = 0.05, group = "Style" },
    })

    return self
end

function DonutWidget:onMouseDown(mx, my)
    self:_handleSeek(mx, my)
end

function DonutWidget:onMouseDrag(mx, my, dx, dy)
    self:_handleSeek(mx, my)
end

function DonutWidget:_handleSeek(mx, my)
    if not self._onSeek then return end
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local cx, cy = w * 0.5, h * 0.5
    local ang = math.atan(my - cy, mx - cx)
    local norm = (ang + math.pi * 0.5) / (math.pi * 2.0)
    if norm < 0.0 then norm = norm + 1.0 end
    if norm >= 1.0 then norm = norm - 1.0 end
    self._onSeek(self._layerIndex, norm)
end

function DonutWidget:setLayerData(data)
    self._layerData = data or {}
end

function DonutWidget:setPeaks(peaks)
    self._peaks = peaks
end

function DonutWidget:setBounce(b)
    self._bounce = b or 0.0
end

local function drawDonutCircle(cx, cy, r, colour, segs)
    segs = segs or 64
    gfx.setColour(colour)
    local px = cx + r
    local py = cy
    for i = 1, segs do
        local t = (i / segs) * math.pi * 2.0
        local x = cx + math.cos(t) * r
        local y = cy + math.sin(t) * r
        gfx.drawLine(px, py, x, y)
        px, py = x, y
    end
end

function DonutWidget:onDraw(w, h)
    local cx, cy = w * 0.5, h * 0.5
    local baseRadius = math.max(20, math.min(w, h) * 0.34)
    local thickness = Utils.clamp(self._thickness, 0.2, 0.8)
    local baseInner = baseRadius * thickness
    local bounce = self._bounce or 0.0

    local layerData = self._layerData or {}
    local posNorm = Utils.clamp(tonumber(layerData.positionNorm) or 0.0, 0.0, 1.0)
    local peaks = self._peaks

    local radius = baseRadius + bounce * 2.4
    local inner = baseInner + bounce * 1.2

    drawDonutCircle(cx, cy, radius, self._bgColour, 72)
    drawDonutCircle(cx, cy, inner, self._bgColour, 72)

    local playheadIdx = 1

    if peaks and #peaks > 0 then
        playheadIdx = math.floor(posNorm * #peaks) + 1
        if playheadIdx < 1 then playheadIdx = 1 end
        if playheadIdx > #peaks then playheadIdx = #peaks end

        gfx.setColour(self._ringColour)

        local window = 10
        local emphasisAmount = 2.6 * bounce

        for i = 1, #peaks do
            local p = Utils.clamp(peaks[i] or 0.0, 0.0, 1.0)

            local d = math.abs(i - playheadIdx)
            d = math.min(d, #peaks - d)

            local influence = 0.0
            if d <= window then
                influence = 1.0 - (d / window)
                influence = influence * influence
            end

            local shaped = Utils.clamp(
                p * (1.0 + emphasisAmount * influence) + (0.14 * bounce * influence),
                0.0, 1.0
            )

            local a = ((i - 1) / #peaks) * math.pi * 2.0 - math.pi * 0.5
            local r1 = inner
            local r2 = inner + shaped * (radius - inner)
            local x1 = cx + math.cos(a) * r1
            local y1 = cy + math.sin(a) * r1
            local x2 = cx + math.cos(a) * r2
            local y2 = cy + math.sin(a) * r2
            gfx.drawLine(x1, y1, x2, y2)
        end
    end

    if (layerData.length or 0) > 0 then
        local a = posNorm * math.pi * 2.0 - math.pi * 0.5
        local x1 = cx + math.cos(a) * (inner - 3)
        local y1 = cy + math.sin(a) * (inner - 3)
        local x2 = cx + math.cos(a) * (radius + 3)
        local y2 = cy + math.sin(a) * (radius + 3)
        gfx.setColour(self._playheadColour)
        gfx.drawLine(x1, y1, x2, y2)
    end
end

return DonutWidget

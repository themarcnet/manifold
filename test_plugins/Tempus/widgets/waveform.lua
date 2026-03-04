-- waveform.lua
-- Waveform view widget with scrubbing support

local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local WaveformView = BaseWidget:extend()

function WaveformView.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), WaveformView)

    self._colour = Utils.colour(config.colour, 0xff22d3ee)
    self._bg = Utils.colour(config.bg, 0xff0b1220)
    self._playheadColour = Utils.colour(config.playheadColour, 0xffff4d4d)
    self._mode = config.mode or "layer"  -- "layer" or "capture"
    self._layerIdx = config.layerIndex or 0
    self._playheadPos = -1  -- -1 = hidden
    self._captureStart = 0
    self._captureEnd = 0
    self._onScrubStart = config.on_scrub_start or config.onScrubStart
    self._onScrubSnap = config.on_scrub_snap or config.onScrubSnap
    self._onScrubSpeed = config.on_scrub_speed or config.onScrubSpeed
    self._onScrubEnd = config.on_scrub_end or config.onScrubEnd
    self._scrubbing = false
    self._lastScrubX = 0

    -- Enable mouse if any scrub callback is set
    if self._onScrubStart or self._onScrubSnap then
        self.node:setInterceptsMouse(true, false)
    else
        self.node:setInterceptsMouse(false, false)
    end

    self:_storeEditorMeta("WaveformView", {
        on_scrub_start = self._onScrubStart,
        on_scrub_snap = self._onScrubSnap,
        on_scrub_speed = self._onScrubSpeed,
        on_scrub_end = self._onScrubEnd
    }, Schema.buildEditorSchema("WaveformView", config))
    
    -- Rebind mouse callbacks directly to bypass BaseWidget metatable chain
    local wfSelf = self
    self.node:setOnMouseDown(function(mx, my)
        if wfSelf._scrubbing then
            local w = wfSelf.node:getWidth()
            if w > 4 then
                local pos = math.max(0, math.min(1, (mx - 2) / (w - 4)))
                wfSelf._lastScrubPos = pos
                if wfSelf._onScrubSnap then
                    wfSelf._onScrubSnap(pos, 0)
                end
            end
            return
        end

        wfSelf._scrubbing = true
        if wfSelf._onScrubStart then
            wfSelf._onScrubStart()
        end
        local w = wfSelf.node:getWidth()
        if w > 4 then
            local pos = math.max(0, math.min(1, (mx - 2) / (w - 4)))
            wfSelf._lastScrubPos = pos
            if wfSelf._onScrubSnap then
                wfSelf._onScrubSnap(pos, 0)
            end
        end
    end)
    
    self.node:setOnMouseDrag(function(mx, my, dx, dy)
        if not wfSelf._scrubbing then return end
        local w = wfSelf.node:getWidth()
        if w <= 4 then return end
        local pos = math.max(0, math.min(1, (mx - 2) / (w - 4)))
        local delta = 0
        if wfSelf._lastScrubPos then
            delta = pos - wfSelf._lastScrubPos
        end
        wfSelf._lastScrubPos = pos
        if wfSelf._onScrubSnap then
            wfSelf._onScrubSnap(pos, delta)
        end
    end)
    
    self.node:setOnMouseUp(function(mx, my)
        if wfSelf._scrubbing then
            wfSelf._scrubbing = false
            wfSelf._lastScrubPos = nil
            if wfSelf._onScrubEnd then
                wfSelf._onScrubEnd()
            end
        end
    end)
    
    return self
end

function WaveformView:onDraw(w, h)
    if w < 4 or h < 4 then return end
    
    -- Background
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(0, 0, w, h, 4)
    gfx.setColour(self._scrubbing and 0x50475569 or 0x30475569)
    gfx.drawRoundedRect(0, 0, w, h, 4, self._scrubbing and 2 or 1)
    
    -- Center line
    gfx.setColour(0x18ffffff)
    gfx.drawHorizontalLine(math.floor(h / 2), 2, w - 2)
    
    -- Waveform
    local numBuckets = math.min(w - 4, 200)
    local peaks = nil
    
    if self._mode == "layer" then
        peaks = getLayerPeaks(self._layerIdx, numBuckets)
    elseif self._mode == "capture" and self._captureEnd > self._captureStart then
        peaks = getCapturePeaks(math.floor(self._captureStart), math.floor(self._captureEnd), numBuckets)
    end
    
    if peaks and #peaks > 0 then
        gfx.setColour(self._colour)
        local centerY = h / 2
        local gain = h * 0.43
        for x = 1, #peaks do
            local peak = peaks[x]
            local ph = peak * gain
            local px = 2 + (x - 1) * ((w - 4) / #peaks)
            gfx.drawVerticalLine(math.floor(px), centerY - ph, centerY + ph)
        end
    end
    
    -- Playhead
    if self._playheadPos >= 0 and self._playheadPos <= 1 then
        local phX = 2 + math.floor(self._playheadPos * (w - 4))
        gfx.setColour(self._scrubbing and 0xffffff00 or self._playheadColour)
        gfx.drawVerticalLine(phX, 1, h - 1)
    end
end

function WaveformView:setLayerIndex(idx)
    self._layerIdx = idx
    self._mode = "layer"
end

function WaveformView:setCaptureRange(startAgo, endAgo)
    self._captureStart = startAgo
    self._captureEnd = endAgo
    self._mode = "capture"
end

function WaveformView:setPlayheadPos(pos)
    self._playheadPos = pos
end

function WaveformView:setColour(colour)
    self._colour = colour
end

return WaveformView

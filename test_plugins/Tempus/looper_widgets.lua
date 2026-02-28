-- looper_widgets_new.lua
-- New widget library with proper OOP inheritance for user extensibility.
-- All widgets are classes that users can require and subclass.
-- 
-- Usage:
--   local W = require("looper_widgets_new")
--   
--   -- Use built-in slider
--   local slider = W.Slider.new(parent, "mySlider", {min=0, max=1, value=0.5})
--   
--   -- Create custom slider with overridden behavior
--   local MySlider = W.Slider:extend()
--   function MySlider:drawTrack(x, y, w, h)
--     -- Custom track drawing
--   end
--   local mySlider = MySlider.new(parent, "custom", {min=0, max=100})

local Widgets = {}

-- ============================================================================
-- Base Widget Class - All widgets inherit from this
-- ============================================================================

local BaseWidget = {}
BaseWidget.__index = BaseWidget

function BaseWidget:extend()
    local cls = {}
    for k, v in pairs(self) do
        if k:find("__") == 1 then
            cls[k] = v
        end
    end
    cls.__index = cls
    cls.super = self
    setmetatable(cls, self)
    return cls
end

function BaseWidget.new(parent, name, config)
    local self = setmetatable({}, BaseWidget)
    config = config or {}
    
    self.node = parent:addChild(name)
    self.name = name
    self.config = config
    self._hovered = false
    self._pressed = false
    self._enabled = config.enabled ~= false
    
    -- Bind callbacks
    self:bindCallbacks()
    
    return self
end

function BaseWidget:bindCallbacks()
    self.node:setOnMouseDown(function(mx, my) 
        if not self._enabled then return end
        self._pressed = true
        self:onMouseDown(mx, my) 
    end)
    
    self.node:setOnMouseDrag(function(mx, my, dx, dy) 
        if not self._enabled then return end
        self:onMouseDrag(mx, my, dx, dy) 
    end)
    
    self.node:setOnMouseUp(function(mx, my) 
        self._pressed = false
        self:onMouseUp(mx, my) 
    end)
    
    self.node:setOnClick(function() 
        if not self._enabled then return end
        self:onClick() 
    end)
    
    self.node:setOnDoubleClick(function()
        if not self._enabled then return end
        self:onDoubleClick()
    end)
    
    self.node:setOnDraw(function(node)
        self._hovered = node:isMouseOver()
        self:onDraw(node:getWidth(), node:getHeight())
    end)
end

function BaseWidget:onMouseDown(mx, my) end
function BaseWidget:onMouseDrag(mx, my, dx, dy) end
function BaseWidget:onMouseUp(mx, my) end
function BaseWidget:onClick() end
function BaseWidget:onDoubleClick() end
function BaseWidget:onDraw(w, h) end

function BaseWidget:setEnabled(enabled)
    self._enabled = enabled
end

function BaseWidget:isEnabled()
    return self._enabled
end

function BaseWidget:isHovered()
    return self._hovered
end

function BaseWidget:isPressed()
    return self._pressed
end

function BaseWidget:setBounds(x, y, w, h)
    -- Ensure all values are integers for sol2
    local ix = math.floor(x + 0.5)
    local iy = math.floor(y + 0.5)
    local iw = math.floor(w + 0.5)
    local ih = math.floor(h + 0.5)
    self.node:setBounds(ix, iy, iw, ih)
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function colour(c, default) 
    return c or default or 0xff333333 
end

local function clamp(v, lo, hi) 
    return math.max(lo, math.min(hi, v)) 
end

local function lerp(a, b, t) 
    return a + (b - a) * t 
end

local function brighten(c, amount)
    local a = (c >> 24) & 0xff
    local r = math.min(255, ((c >> 16) & 0xff) + amount)
    local g = math.min(255, ((c >> 8) & 0xff) + amount)
    local b = math.min(255, (c & 0xff) + amount)
    return (a << 24) | (r << 16) | (g << 8) | b
end

local function darken(c, amount)
    local a = (c >> 24) & 0xff
    local r = math.max(0, ((c >> 16) & 0xff) - amount)
    local g = math.max(0, ((c >> 8) & 0xff) - amount)
    local b = math.max(0, (c & 0xff) - amount)
    return (a << 24) | (r << 16) | (g << 8) | b
end

local function snapToStep(value, step)
    if step and step > 0 then
        return math.floor(value / step + 0.5) * step
    end
    return value
end

-- ============================================================================
-- Button Widget
-- ============================================================================

Widgets.Button = BaseWidget:extend()

function Widgets.Button.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Button)
    
    self._label = config.label or ""
    self._bg = colour(config.bg, 0xff374151)
    self._textColour = colour(config.textColour, 0xffffffff)
    self._fontSize = config.fontSize or 13.0
    self._radius = config.radius or 7.0
    self._onClick = config.on_click or config.onClick
    self._onPress = config.on_press or config.onPress
    self._onRelease = config.on_release or config.onRelease
    
    return self
end

function Widgets.Button:onMouseDown(mx, my)
    if self._onPress then
        self._onPress(mx, my)
    end
end

function Widgets.Button:onMouseUp(mx, my)
    if self._onRelease then
        self._onRelease(mx, my)
    end
end

function Widgets.Button:onClick()
    if self._onClick then
        self._onClick()
    end
end

function Widgets.Button:drawBackground(w, h)
    local bg = self._bg
    if not self:isEnabled() then
        bg = darken(bg, 40)
    elseif self:isPressed() then
        bg = darken(bg, 20)
    elseif self:isHovered() then
        bg = brighten(bg, 25)
    end
    
    gfx.setColour(bg)
    gfx.fillRoundedRect(1, 1, w - 2, h - 2, self._radius)
    gfx.setColour(brighten(bg, 40))
    gfx.drawRoundedRect(1, 1, w - 2, h - 2, self._radius, 1.0)
end

function Widgets.Button:drawLabel(w, h)
    gfx.setColour(self._textColour)
    gfx.setFont(self._fontSize)
    gfx.drawText(self._label, 0, 0, w, h, Justify.centred)
end

function Widgets.Button:onDraw(w, h)
    self:drawBackground(w, h)
    self:drawLabel(w, h)
end

function Widgets.Button:setLabel(label)
    self._label = label
end

function Widgets.Button:getLabel()
    return self._label
end

function Widgets.Button:setBg(colour)
    self._bg = colour
end

function Widgets.Button:setTextColour(colour)
    self._textColour = colour
end

-- ============================================================================
-- Label Widget
-- ============================================================================

Widgets.Label = BaseWidget:extend()

function Widgets.Label.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Label)
    
    self._text = config.text or ""
    self._colour = colour(config.colour, 0xff9ca3af)
    self._fontSize = config.fontSize or 13.0
    self._fontName = config.fontName
    self._fontStyle = config.fontStyle or FontStyle.plain
    self._justification = config.justification or Justify.centredLeft
    
    self.node:setInterceptsMouse(false, false)
    
    return self
end

function Widgets.Label:onDraw(w, h)
    gfx.setColour(self._colour)
    if self._fontName then
        gfx.setFont(self._fontName, self._fontSize, self._fontStyle)
    else
        gfx.setFont(self._fontSize)
    end
    gfx.drawText(self._text, 0, 0, w, h, self._justification)
end

function Widgets.Label:setText(text)
    self._text = text
end

function Widgets.Label:getText()
    return self._text
end

function Widgets.Label:setColour(colour)
    self._colour = colour
end

-- ============================================================================
-- Panel Widget (Container)
-- ============================================================================

Widgets.Panel = BaseWidget:extend()

function Widgets.Panel.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Panel)
    
    self._bg = colour(config.bg, 0x00000000)
    self._border = colour(config.border, 0x00000000)
    self._borderWidth = config.borderWidth or 0
    self._radius = config.radius or 0
    self._opacity = config.opacity or 1.0
    
    if config.interceptsMouse ~= nil then
        self.node:setInterceptsMouse(config.interceptsMouse, true)
    end
    
    if config.on_wheel then
        self.node:setOnMouseWheel(function(x, y, deltaY)
            config.on_wheel(x, y, deltaY)
        end)
    end
    
    return self
end

function Widgets.Panel:onDraw(w, h)
    -- Background
    if (self._bg >> 24) & 0xff > 0 then
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, self._radius)
    end
    
    -- Border
    if self._borderWidth > 0 and (self._border >> 24) & 0xff > 0 then
        gfx.setColour(self._border)
        gfx.drawRoundedRect(0, 0, w, h, self._radius, self._borderWidth)
    end
end

function Widgets.Panel:setStyle(style)
    if style.bg then self._bg = style.bg end
    if style.border then self._border = style.border end
    if style.borderWidth then self._borderWidth = style.borderWidth end
    if style.radius then self._radius = style.radius end
    if style.opacity then self._opacity = style.opacity end
end

-- ============================================================================
-- Slider Widget (Horizontal)
-- ============================================================================

Widgets.Slider = BaseWidget:extend()

function Widgets.Slider.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Slider)
    
    self._min = config.min or 0
    self._max = config.max or 1
    self._step = config.step or 0
    self._value = clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = colour(config.colour, 0xff38bdf8)
    self._bg = colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._showValue = config.showValue ~= false
    self._dragging = false
    self._dragStartX = 0
    self._dragStartValue = 0
    
    self.node:setInterceptsMouse(true, false)
    
    return self
end

function Widgets.Slider:onMouseDown(mx, my)
    self._dragging = true
    self._dragStartX = mx
    self._dragStartValue = self._value
    self:valueFromMouse(mx)
end

function Widgets.Slider:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    self:valueFromMouse(mx)
end

function Widgets.Slider:onMouseUp(mx, my)
    self._dragging = false
end

function Widgets.Slider:onDoubleClick()
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.Slider:valueFromMouse(mx)
    local w = self.node:getWidth()
    local trackW = math.max(1, w - 16)
    local t = clamp((mx - 8) / trackW, 0, 1)
    local newVal = self._min + t * (self._max - self._min)
    newVal = snapToStep(newVal, self._step)
    newVal = clamp(newVal, self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.Slider:onDraw(w, h)
    local trackY = h * 0.5 - 3
    local trackH = 6
    local trackR = 3
    
    -- Draw track
    self:drawTrack(8, trackY, w - 16, trackH, trackR)
    
    -- Draw thumb
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    local thumbX = 8 + t * (w - 16) - 6
    self:drawThumb(thumbX, (h - 20) / 2, 12, 20)
    
    -- Draw label (simplified - just value for now)
    if self._showValue then
        local valText
        if self._step >= 1 then
            valText = self._label .. ": " .. string.format("%d", self._value) .. self._suffix
        else
            valText = self._label .. ": " .. string.format("%.2f", self._value) .. self._suffix
        end
        gfx.setColour(0xffe2e8f0)
        gfx.setFont(11.0)
        gfx.drawText(valText, 8, 2, w - 16, 20, Justify.centred)
    end
end

function Widgets.Slider:drawTrack(x, y, w, h, r)
    -- Background track
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(x, y, w, h, r)
    
    -- Filled portion
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    gfx.setColour(self._colour)
    gfx.fillRoundedRect(x, y, w * t, h, r)
end

function Widgets.Slider:drawThumb(x, y, w, h)
    local col = self._colour
    if self._dragging then
        col = brighten(col, 30)
    elseif self:isHovered() then
        col = brighten(col, 15)
    end
    gfx.setColour(col)
    gfx.fillRoundedRect(x, y, w, h, 4)
end

function Widgets.Slider:drawLabel(x, y, w, h)
    gfx.setColour(0xffe2e8f0)
    gfx.setFont(11.0)
    gfx.drawText(self._label, x, y, w, h, Justify.centredLeft)
end

function Widgets.Slider:drawValue(x, y, w, h)
    local valText
    if self._step >= 1 then
        valText = string.format("%d", self._value) .. self._suffix
    else
        valText = string.format("%.2f", self._value) .. self._suffix
    end
    gfx.setColour(0xffcbd5e1)
    gfx.setFont(11.0)
    gfx.drawText(valText, math.floor(x), math.floor(y), math.floor(w), math.floor(h), Justify.centredRight)
end

function Widgets.Slider:getValue()
    return self._value
end

function Widgets.Slider:setValue(v)
    self._value = clamp(v, self._min, self._max)
end

function Widgets.Slider:reset()
    self:setValue(self._defaultValue)
end

-- ============================================================================
-- Vertical Slider Widget
-- ============================================================================

Widgets.VSlider = Widgets.Slider:extend()

function Widgets.VSlider.new(parent, name, config)
    return setmetatable(Widgets.Slider.new(parent, name, config), Widgets.VSlider)
end

function Widgets.VSlider:onMouseDown(mx, my)
    self._dragging = true
    self:valueFromMouse(mx, my)
end

function Widgets.VSlider:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    self:valueFromMouse(mx, my)
end

function Widgets.VSlider:valueFromMouse(mx, my)
    if my == nil then
        return
    end
    local h = self.node:getHeight()
    local trackH = math.max(1, h - 16)
    local t = 1 - clamp((my - 8) / trackH, 0, 1)  -- Inverted: bottom = min
    local newVal = self._min + t * (self._max - self._min)
    newVal = snapToStep(newVal, self._step)
    newVal = clamp(newVal, self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.VSlider:onDraw(w, h)
    local trackX = 2
    local trackW = w - 4
    local trackY = 4
    local trackH = h - 8
    local trackR = trackW / 2
    
    -- Draw track (subtle background)
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(trackX, trackY, trackW, trackH, trackR)
    
    -- Calculate thumb position based on value
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    
    -- Browser-style scroll pill: thumb represents viewport
    local thumbH = math.max(30, trackH * 0.3)  -- Minimum 30px or 30% of track
    local thumbW = trackW
    local maxThumbY = trackY + trackH - thumbH
    local thumbY = trackY + maxThumbY * (1 - t)
    
    -- Draw thumb (scroll pill)
    local col = self._colour
    if self._dragging then
        col = brighten(col, 30)
    elseif self:isHovered() then
        col = brighten(col, 15)
    end
    gfx.setColour(col)
    gfx.fillRoundedRect(trackX, thumbY, thumbW, thumbH, trackR)
end

-- ============================================================================
-- Knob Widget (Rotary)
-- ============================================================================

Widgets.Knob = BaseWidget:extend()

function Widgets.Knob.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Knob)
    
    self._min = config.min or 0
    self._max = config.max or 1
    self._step = config.step or 0
    self._value = clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = colour(config.colour, 0xff22d3ee)
    self._bg = colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._dragging = false
    self._dragStartY = 0
    self._dragStartValue = 0
    
    -- Arc angles: -135° to +135°
    self._startAngle = -135
    self._endAngle = 135
    
    return self
end

function Widgets.Knob:onMouseDown(mx, my)
    self._dragging = true
    self._dragStartY = my
    self._dragStartValue = self._value
end

function Widgets.Knob:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    local range = self._max - self._min
    local delta = (-dy / 150.0) * range  -- Vertical drag
    local newVal = clamp(snapToStep(self._dragStartValue + delta, self._step), self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.Knob:onMouseUp(mx, my)
    self._dragging = false
end

function Widgets.Knob:onDoubleClick()
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.Knob:onDraw(w, h)
    local cx = w / 2
    local cy = h * 0.42
    local radius = math.min(w, h) * 0.32
    
    -- Draw background
    self:drawBackground(cx, cy, radius)
    
    -- Draw arc
    local t = (self._value - self._min) / math.max(0.001, self._max - self._min)
    local arcEnd = self._startAngle + t * (self._endAngle - self._startAngle)
    self:drawArc(cx, cy, radius, arcEnd)
    
    -- Draw pointer
    self:drawPointer(cx, cy, radius * 0.55, arcEnd)
    
    -- Draw value and label
    self:drawValueText(w, h)
    self:drawLabelText(w, h)
end

function Widgets.Knob:drawBackground(cx, cy, radius)
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(cx - radius, cy - radius, radius * 2, radius * 2, radius)
end

function Widgets.Knob:drawArc(cx, cy, radius, endAngle)
    local numTicks = 32
    for i = 0, numTicks do
        local angle = self._startAngle + (i / numTicks) * (self._endAngle - self._startAngle)
        local rad = math.rad(angle - 90)
        local isFilled = angle <= endAngle
        gfx.setColour(isFilled and self._colour or darken(self._bg, 10))
        local x1 = cx + math.cos(rad) * (radius * 0.7)
        local y1 = cy + math.sin(rad) * (radius * 0.7)
        local x2 = cx + math.cos(rad) * (radius * 0.92)
        local y2 = cy + math.sin(rad) * (radius * 0.92)
        gfx.fillRect(math.min(x1, x2), math.min(y1, y2),
                      math.max(2, math.abs(x2 - x1)),
                      math.max(2, math.abs(y2 - y1)))
    end
end

function Widgets.Knob:drawPointer(cx, cy, radius, angle)
    local rad = math.rad(angle - 90)
    local px = cx + math.cos(rad) * radius
    local py = cy + math.sin(rad) * radius
    gfx.setColour(0xffe2e8f0)
    gfx.fillRoundedRect(px - 2, py - 2, 4, 4, 2)
end

function Widgets.Knob:drawValueText(w, h)
    local valText
    if self._step >= 1 then
        valText = string.format("%d", self._value) .. self._suffix
    else
        valText = string.format("%.2f", self._value) .. self._suffix
    end
    gfx.setColour(0xffcbd5e1)
    gfx.setFont(11.0)
    gfx.drawText(valText, 0, math.floor(h * 0.72), w, math.floor(h * 0.14), Justify.centred)
end

function Widgets.Knob:drawLabelText(w, h)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(10.0)
    gfx.drawText(self._label, 0, math.floor(h * 0.86), w, math.floor(h * 0.14), Justify.centred)
end

function Widgets.Knob:getValue()
    return self._value
end

function Widgets.Knob:setValue(v)
    self._value = clamp(v, self._min, self._max)
end

-- ============================================================================
-- Toggle/Switch Widget
-- ============================================================================

Widgets.Toggle = BaseWidget:extend()

function Widgets.Toggle.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Toggle)
    
    self._value = config.value or false
    self._label = config.label or ""
    self._onColour = colour(config.onColour, 0xff22c55e)
    self._offColour = colour(config.offColour, 0xff374151)
    self._onChange = config.on_change or config.onChange
    
    return self
end

function Widgets.Toggle:onClick()
    self._value = not self._value
    if self._onChange then
        self._onChange(self._value)
    end
end

function Widgets.Toggle:onDraw(w, h)
    -- Track
    local trackW = math.floor(math.min(38, w * 0.5))
    local trackH = 18
    local trackX = math.floor(w - trackW - 6)
    local trackY = math.floor((h - trackH) / 2)
    local trackR = math.floor(trackH / 2)
    
    local trackCol = self._value and self._onColour or self._offColour
    if self:isHovered() then
        trackCol = brighten(trackCol, 15)
    end
    
    gfx.setColour(trackCol)
    gfx.fillRoundedRect(trackX, trackY, trackW, trackH, trackR)
    
    -- Thumb
    local thumbR = trackH - 4
    local thumbX = math.floor(self._value and (trackX + trackW - thumbR - 2) or (trackX + 2))
    local thumbY = math.floor(trackY + 2)
    gfx.setColour(0xffe2e8f0)
    gfx.fillRoundedRect(thumbX, thumbY, thumbR, thumbR, math.floor(thumbR / 2))
    
    -- Label
    gfx.setColour(self._value and 0xffe2e8f0 or 0xff94a3b8)
    gfx.setFont(12.0)
    gfx.drawText(self._label, 6, 0, math.floor(trackX - 10), h, Justify.centredLeft)
end

function Widgets.Toggle:getValue()
    return self._value
end

function Widgets.Toggle:setValue(v)
    self._value = v
end

-- ============================================================================
-- Dropdown Widget
-- Uses the root canvas for the overlay so it is not clipped by parent bounds.
-- Pass config.rootNode = <root canvas> to enable proper overlay positioning.
-- ============================================================================

Widgets.Dropdown = BaseWidget:extend()

function Widgets.Dropdown.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Dropdown)
    
    self._options = config.options or {}
    self._selected = config.selected or 1
    self._onSelect = config.on_select or config.onSelect
    self._bg = colour(config.bg, 0xff1e293b)
    self._colour = colour(config.colour, 0xff38bdf8)
    self._open = false
    self._overlay = nil
    self._rootNode = config.rootNode  -- root canvas for overlay placement
    
    return self
end

function Widgets.Dropdown:getSelectedLabel()
    return self._options[self._selected] or "---"
end

function Widgets.Dropdown:close()
    if self._overlay then
        self._overlay:setOnDraw(nil)
        self._overlay:setOnClick(nil)
        self._overlay:setOnMouseDown(nil)
        self._overlay:setBounds(0, 0, 0, 0)
        self._open = false
    end
end

-- Walk up parent chain to compute absolute position of the dropdown node
function Widgets.Dropdown:_getAbsolutePos()
    local ax, ay = 0, 0
    local n = self.node
    while n do
        local bx, by, bw, bh = n:getBounds()
        ax = ax + bx
        ay = ay + by
        -- Try to get parent; if getBounds returns 0,0 for root, stop
        -- We walk until we hit the root canvas (whose parent we can't access from Lua)
        -- So we use a simple approach: accumulate bounds of self.node only
        break  -- For now, we store the absolute position from the UI layout
    end
    return ax, ay
end

function Widgets.Dropdown:open()
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

function Widgets.Dropdown:onClick()
    self:open()
end

function Widgets.Dropdown:onDraw(w, h)
    local bg = self:isHovered() and brighten(self._bg, 15) or self._bg
    
    gfx.setColour(bg)
    gfx.fillRoundedRect(1, 1, math.floor(w - 2), math.floor(h - 2), 6)
    gfx.setColour(brighten(bg, 30))
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

function Widgets.Dropdown:getSelected()
    return self._selected
end

function Widgets.Dropdown:setSelected(idx)
    self._selected = clamp(idx, 1, #self._options)
end

function Widgets.Dropdown:setOptions(opts)
    self._options = opts
end

-- Store absolute position for overlay placement (call from ui_resized)
function Widgets.Dropdown:setAbsolutePos(ax, ay)
    self._absX = ax
    self._absY = ay
end

-- ============================================================================
-- Waveform View Widget (interactive: click/drag to scrub)
-- ============================================================================

Widgets.WaveformView = BaseWidget:extend()

function Widgets.WaveformView.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.WaveformView)
    
    self._colour = colour(config.colour, 0xff22d3ee)
    self._bg = colour(config.bg, 0xff0b1220)
    self._playheadColour = colour(config.playheadColour, 0xffff4d4d)
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
    
    -- Rebind mouse callbacks directly to bypass BaseWidget metatable chain
    local wfSelf = self
    self.node:setOnMouseDown(function(mx, my)
        -- If already scrubbing, just update position without restart
        -- This prevents speed capture/restore issues on rapid clicks
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
        -- Snap playhead to click position
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

function Widgets.WaveformView:onDraw(w, h)
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

function Widgets.WaveformView:setLayerIndex(idx)
    self._layerIdx = idx
    self._mode = "layer"
end

function Widgets.WaveformView:setCaptureRange(startAgo, endAgo)
    self._captureStart = startAgo
    self._captureEnd = endAgo
    self._mode = "capture"
end

function Widgets.WaveformView:setPlayheadPos(pos)
    self._playheadPos = pos
end

function Widgets.WaveformView:setColour(colour)
    self._colour = colour
end

-- ============================================================================
-- Meter Widget (Level Meter)
-- ============================================================================

Widgets.Meter = BaseWidget:extend()

function Widgets.Meter.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.Meter)
    
    self._value = 0  -- 0 to 1
    self._peak = 0
    self._colour = colour(config.colour, 0xff22c55e)
    self._bg = colour(config.bg, 0xff1e293b)
    self._orientation = config.orientation or "vertical"  -- "vertical" or "horizontal"
    self._showPeak = config.showPeak ~= false
    self._decay = config.decay or 0.9
    
    self.node:setInterceptsMouse(false, false)
    
    return self
end

function Widgets.Meter:onDraw(w, h)
    -- Decay peak
    self._peak = self._peak * self._decay
    
    if self._orientation == "vertical" then
        -- Background
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, 3)
        
        -- Level
        local fillH = h * self._value
        gfx.setColour(self._colour)
        gfx.fillRoundedRect(0, h - fillH, w, fillH, 3)
        
        -- Peak marker
        if self._showPeak and self._peak > 0.01 then
            local peakY = h * (1 - self._peak)
            gfx.setColour(0xffff0000)
            gfx.fillRect(0, peakY - 1, w, 2)
        end
    else
        -- Background
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, 3)
        
        -- Level
        local fillW = w * self._value
        gfx.setColour(self._colour)
        gfx.fillRoundedRect(0, 0, fillW, h, 3)
        
        -- Peak marker
        if self._showPeak and self._peak > 0.01 then
            local peakX = w * self._peak
            gfx.setColour(0xffff0000)
            gfx.fillRect(peakX - 1, 0, 2, h)
        end
    end
end

function Widgets.Meter:setValue(v)
    self._value = clamp(v, 0, 1)
    if self._value > self._peak then
        self._peak = self._value
    end
end

-- ============================================================================
-- Segmented Control (Multi-button selector)
-- ============================================================================

Widgets.SegmentedControl = BaseWidget:extend()

function Widgets.SegmentedControl.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.SegmentedControl)
    
    self._segments = config.segments or {}
    self._selected = config.selected or 1
    self._onSelect = config.on_select or config.onSelect
    self._bg = colour(config.bg, 0xff1e293b)
    self._selectedBg = colour(config.selectedBg, 0xff38bdf8)
    self._textColour = colour(config.textColour, 0xffe2e8f0)
    self._selectedTextColour = colour(config.selectedTextColour, 0xffffffff)
    
    return self
end

function Widgets.SegmentedControl:onMouseDown(mx, my)
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

function Widgets.SegmentedControl:onDraw(w, h)
    local segW = math.floor(w / #self._segments)
    local segH = h
    local r = 6
    
    for i, seg in ipairs(self._segments) do
        local x = math.floor((i - 1) * segW)
        local isSelected = (i == self._selected)
        local isHovered = self:isHovered() and math.floor(self.node:getWidth() * 0) == 0
        -- Simple hover detection
        
        local bg = isSelected and self._selectedBg or self._bg
        if isHovered and not isSelected then
            bg = brighten(bg, 10)
        end
        
        -- Draw segment with rounded corners on ends only
        gfx.setColour(bg)
        if i == 1 then
            -- Left segment: round left corners
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        elseif i == #self._segments then
            -- Right segment: round right corners  
            gfx.fillRoundedRect(x, 0, segW, segH, r)
        else
            -- Middle: no rounding
            gfx.fillRect(x, 0, segW, segH)
        end
        
        -- Text
        gfx.setColour(isSelected and self._selectedTextColour or self._textColour)
        gfx.setFont(11.0)
        gfx.drawText(seg, x, 0, segW, segH, Justify.centred)
    end
    
    -- Border around whole control
    gfx.setColour(brighten(self._bg, 20))
    gfx.drawRoundedRect(0, 0, w, h, r, 1)
end

function Widgets.SegmentedControl:getSelected()
    return self._selected
end

function Widgets.SegmentedControl:setSelected(idx)
    self._selected = clamp(idx, 1, #self._segments)
end

-- ============================================================================
-- NumberBox Widget (compact numeric value with +/- and drag-to-change)
-- ============================================================================

Widgets.NumberBox = BaseWidget:extend()

function Widgets.NumberBox.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.NumberBox)
    
    self._min = config.min or 0
    self._max = config.max or 999
    self._step = config.step or 1
    self._value = clamp(config.value or self._min, self._min, self._max)
    self._defaultValue = config.defaultValue or self._value
    self._label = config.label or ""
    self._suffix = config.suffix or ""
    self._colour = colour(config.colour, 0xff38bdf8)
    self._bg = colour(config.bg, 0xff1e293b)
    self._onChange = config.on_change or config.onChange
    self._dragging = false
    self._dragStartY = 0
    self._dragStartValue = 0
    self._format = config.format or (self._step >= 1 and "%d" or "%.1f")
    self._clickTarget = nil
    -- Auto-repeat state for +/- buttons
    self._buttonHeld = nil  -- "minus" or "plus" when held
    self._repeatDelay = 15  -- frames before auto-repeat starts (~250ms)
    self._repeatInterval = 3  -- frames between repeats (~50ms)
    self._repeatCounter = 0
    
    return self
end

function Widgets.NumberBox:onMouseDown(mx, my)
    local w = self.node:getWidth()
    local btnW = math.min(24, w * 0.2)
    
    if mx < btnW then
        -- Minus button
        self._clickTarget = "minus"
        self._buttonHeld = "minus"
        self._repeatCounter = 0
        self:_adjust(-1)
    elseif mx > w - btnW then
        -- Plus button
        self._clickTarget = "plus"
        self._buttonHeld = "plus"
        self._repeatCounter = 0
        self:_adjust(1)
    else
        -- Start drag on the value area
        self._clickTarget = "value"
        self._dragging = true
        self._dragStartY = my
        self._dragStartValue = self._value
    end
end

function Widgets.NumberBox:onMouseDrag(mx, my, dx, dy)
    if not self._dragging then return end
    local range = self._max - self._min
    local delta = (-dy / 100.0) * range
    local newVal = clamp(snapToStep(self._dragStartValue + delta, self._step), self._min, self._max)
    
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.NumberBox:onMouseUp(mx, my)
    self._dragging = false
end

function Widgets.NumberBox:onDoubleClick()
    -- Only reset to default if double-click was on the value area, not +/- buttons
    if self._clickTarget ~= "value" then return end
    if self._value ~= self._defaultValue then
        self._value = self._defaultValue
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.NumberBox:_adjust(direction)
    local newVal = clamp(self._value + self._step * direction, self._min, self._max)
    if newVal ~= self._value then
        self._value = newVal
        if self._onChange then
            self._onChange(self._value)
        end
    end
end

function Widgets.NumberBox:onDraw(w, h)
    local btnW = math.min(24, math.floor(w * 0.2))
    local bg = self._bg
    
    -- Background
    gfx.setColour(bg)
    gfx.fillRoundedRect(0, 0, w, h, 5)
    gfx.setColour(brighten(bg, 20))
    gfx.drawRoundedRect(0, 0, w, h, 5, 1)
    
    -- Minus button
    local minusBg = self:isHovered() and brighten(bg, 15) or bg
    gfx.setColour(minusBg)
    gfx.fillRoundedRect(1, 1, btnW, h - 2, 4)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(14.0)
    gfx.drawText("−", 0, 0, btnW, h, Justify.centred)
    
    -- Plus button
    local plusBg = self:isHovered() and brighten(bg, 15) or bg
    gfx.setColour(plusBg)
    gfx.fillRoundedRect(w - btnW - 1, 1, btnW, h - 2, 4)
    gfx.setColour(0xff94a3b8)
    gfx.setFont(14.0)
    gfx.drawText("+", w - btnW, 0, btnW, h, Justify.centred)
    
    -- Separator lines
    gfx.setColour(brighten(bg, 30))
    gfx.drawVerticalLine(btnW, 2, h - 2)
    gfx.drawVerticalLine(w - btnW - 1, 2, h - 2)
    
    -- Label (small, above value)
    if self._label ~= "" then
        gfx.setColour(0xff94a3b8)
        gfx.setFont(9.0)
        gfx.drawText(self._label, btnW + 4, 1, w - btnW * 2 - 8, math.floor(h * 0.4), Justify.centred)
    end
    
    local fmtValue = self._value
    if self._format == "%d" then fmtValue = math.floor(fmtValue + 0.5) end
    local valText = string.format(self._format, fmtValue) .. self._suffix
    gfx.setColour(self._dragging and brighten(self._colour, 30) or self._colour)
    gfx.setFont(13.0)
    local valY = self._label ~= "" and math.floor(h * 0.3) or 0
    local valH = self._label ~= "" and math.floor(h * 0.7) or h
    gfx.drawText(valText, btnW + 4, valY, w - btnW * 2 - 8, valH, Justify.centred)
end

function Widgets.NumberBox:getValue()
    return self._value
end

function Widgets.NumberBox:setValue(v)
    self._value = clamp(v, self._min, self._max)
end

-- ============================================================================
-- Export the Widgets module with BaseWidget exposed for extension
-- ============================================================================

Widgets.BaseWidget = BaseWidget

return Widgets

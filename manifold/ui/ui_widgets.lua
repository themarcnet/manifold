-- ui_widgets.lua
-- Widget library with proper OOP inheritance for user extensibility.
-- All widgets are classes that users can require and subclass.
-- 
-- Usage:
--   local W = require("ui_widgets")
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

function BaseWidget:_storeEditorMeta(widgetType, callbacks, schema)
    -- Store editor metadata on the Canvas node for introspection
    self.node:setUserData("_editorMeta", {
        type = widgetType,
        name = self.name,
        widget = self,
        config = self.config,
        schema = schema or {},
        callbacks = callbacks or {}
    })
end

function BaseWidget:bindCallbacks()
    self.node:setOnMouseDown(function(mx, my, shift, ctrl, alt)
        if not self._enabled then return end
        self._pressed = true
        self:onMouseDown(mx, my, shift, ctrl, alt)
    end)

    self.node:setOnMouseDrag(function(mx, my, dx, dy, shift, ctrl, alt)
        if not self._enabled then return end
        self:onMouseDrag(mx, my, dx, dy, shift, ctrl, alt)
    end)

    self.node:setOnMouseUp(function(mx, my, shift, ctrl, alt)
        self._pressed = false
        self:onMouseUp(mx, my, shift, ctrl, alt)
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
-- Parameter Exposure API
-- Allows widgets to declare custom editable params for the inspector.
-- ============================================================================

function BaseWidget:exposeParams(specs)
    -- Declare custom editable parameters for this widget.
    -- specs = {
    --   { path = "ringColour", label = "Ring Colour", type = "color", group = "Style" },
    --   { path = "friction", label = "Friction", type = "number", min = 0, max = 1, group = "Behavior" },
    -- }
    -- APPEND to existing exposed params instead of replacing
    if not self._exposedParams then
        self._exposedParams = {}
    end
    for _, item in ipairs(specs or {}) do
        -- Check if path already exists, skip if so
        local exists = false
        for _, existing in ipairs(self._exposedParams) do
            if existing.path == item.path then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(self._exposedParams, item)
        end
    end
    self:_mergeExposedIntoSchema()
end

function BaseWidget:getExposedParams()
    return self._exposedParams or {}
end

function BaseWidget:_getExposed(path)
    -- Default getter: read from self["_" .. path]
    -- Subclasses can override for computed properties.
    local key = "_" .. path
    return self[key]
end

function BaseWidget:_setExposed(path, value)
    -- Default setter: write to self["_" .. path] and repaint.
    -- Subclasses can override for side effects or computed properties.
    local key = "_" .. path
    self[key] = value
    self.node:repaint()
end

function BaseWidget:_mergeExposedIntoSchema()
    local meta = self.node:getUserData("_editorMeta")
    if type(meta) ~= "table" then
        return
    end

    local baseSchema = meta.schema or {}
    local exposed = self._exposedParams or {}

    -- Merge: base schema + exposed params (avoid duplicates by path)
    local merged = {}
    local seen = {}
    for _, item in ipairs(baseSchema) do
        if type(item) == "table" and type(item.path) == "string" then
            seen[item.path] = true
            merged[#merged + 1] = item
        end
    end
    for _, item in ipairs(exposed) do
        if type(item) == "table" and type(item.path) == "string" then
            if not seen[item.path] then
                merged[#merged + 1] = item
            end
        end
    end

    meta.schema = merged
    self.node:setUserData("_editorMeta", meta)
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

local function cloneArrayOfTables(items)
    local out = {}
    for i = 1, #(items or {}) do
        local src = items[i]
        local dst = {}
        for k, v in pairs(src) do
            if type(v) == "table" then
                local t = {}
                for kk, vv in pairs(v) do
                    t[kk] = vv
                end
                dst[k] = t
            else
                dst[k] = v
            end
        end
        out[#out + 1] = dst
    end
    return out
end

local function makeFontStyleOptions()
    local fs = FontStyle or {}
    return {
        { label = "plain", value = fs.plain or 0 },
        { label = "bold", value = fs.bold or 1 },
        { label = "italic", value = fs.italic or 2 },
        { label = "boldItalic", value = fs.boldItalic or 3 },
    }
end

local function makeJustifyOptions()
    local j = Justify or {}
    return {
        { label = "centred", value = j.centred or 36 },
        { label = "centredLeft", value = j.centredLeft or 33 },
        { label = "centredRight", value = j.centredRight or 34 },
        { label = "topLeft", value = j.topLeft or 9 },
        { label = "topRight", value = j.topRight or 10 },
        { label = "bottomLeft", value = j.bottomLeft or 17 },
        { label = "bottomRight", value = j.bottomRight or 18 },
    }
end

local kEditorSchemaByWidget = {
    Button = {
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "fontSize", label = "Font Size", type = "number", min = 6, max = 64, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
    },
    Label = {
        { path = "text", label = "Text", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "fontSize", label = "Font Size", type = "number", min = 6, max = 64, step = 1, group = "Style" },
        { path = "fontStyle", label = "Font Style", type = "enum", group = "Style" },
        { path = "justification", label = "Justify", type = "enum", group = "Layout" },
    },
    Panel = {
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "border", label = "Border", type = "color", group = "Style" },
        { path = "borderWidth", label = "Border Width", type = "number", min = 0, max = 12, step = 1, group = "Style" },
        { path = "radius", label = "Radius", type = "number", min = 0, max = 24, step = 1, group = "Style" },
        { path = "opacity", label = "Opacity", type = "number", min = 0, max = 1, step = 0.01, group = "Style" },
        { path = "interceptsMouse", label = "Intercept Mouse", type = "bool", group = "Behavior" },
    },
    Slider = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "showValue", label = "Show Value", type = "bool", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Track", type = "color", group = "Style" },
    },
    VSlider = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Track", type = "color", group = "Style" },
    },
    Knob = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
    Toggle = {
        { path = "value", label = "Value", type = "bool", group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "onColour", label = "On Colour", type = "color", group = "Style" },
        { path = "offColour", label = "Off Colour", type = "color", group = "Style" },
    },
    Dropdown = {
        { path = "selected", label = "Selected", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "colour", label = "Accent", type = "color", group = "Style" },
    },
    WaveformView = {
        { path = "mode", label = "Mode", type = "enum", group = "Behavior", options = {
            { label = "layer", value = "layer" },
            { label = "capture", value = "capture" },
        } },
        { path = "layerIndex", label = "Layer", type = "number", min = 0, max = 16, step = 1, group = "Behavior" },
        { path = "colour", label = "Wave Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "playheadColour", label = "Playhead", type = "color", group = "Style" },
    },
    Meter = {
        { path = "orientation", label = "Orientation", type = "enum", group = "Layout", options = {
            { label = "vertical", value = "vertical" },
            { label = "horizontal", value = "horizontal" },
        } },
        { path = "showPeak", label = "Show Peak", type = "bool", group = "Behavior" },
        { path = "decay", label = "Decay", type = "number", min = 0, max = 1, step = 0.01, group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
    SegmentedControl = {
        { path = "selected", label = "Selected", type = "number", min = 1, step = 1, group = "Behavior" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
        { path = "selectedBg", label = "Selected Background", type = "color", group = "Style" },
        { path = "textColour", label = "Text Colour", type = "color", group = "Style" },
        { path = "selectedTextColour", label = "Selected Text", type = "color", group = "Style" },
    },
    NumberBox = {
        { path = "value", label = "Value", type = "number", group = "Behavior" },
        { path = "min", label = "Min", type = "number", group = "Behavior" },
        { path = "max", label = "Max", type = "number", group = "Behavior" },
        { path = "step", label = "Step", type = "number", min = 0, max = 10, step = 0.01, group = "Behavior" },
        { path = "label", label = "Label", type = "text", group = "Behavior" },
        { path = "suffix", label = "Suffix", type = "text", group = "Behavior" },
        { path = "format", label = "Format", type = "text", group = "Behavior" },
        { path = "colour", label = "Colour", type = "color", group = "Style" },
        { path = "bg", label = "Background", type = "color", group = "Style" },
    },
}

local function buildEditorSchema(widgetType, config)
    local base = cloneArrayOfTables(kEditorSchemaByWidget[widgetType] or {})

    for i = 1, #base do
        local item = base[i]
        if item.path == "value" then
            if item.min == nil then item.min = config.min end
            if item.max == nil then item.max = config.max end
            if item.step == nil then item.step = config.step end
        elseif item.path == "selected" and type(config.options) == "table" then
            item.max = #config.options
        elseif item.path == "fontStyle" then
            item.options = makeFontStyleOptions()
        elseif item.path == "justification" then
            item.options = makeJustifyOptions()
        end
    end

    return base
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

    self:_storeEditorMeta("Button", {
        on_click = self._onClick,
        on_press = self._onPress,
        on_release = self._onRelease
    }, buildEditorSchema("Button", config))

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

    self:_storeEditorMeta("Label", {}, buildEditorSchema("Label", config))

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

    self:_storeEditorMeta("Panel", {
        on_wheel = config.on_wheel
    }, buildEditorSchema("Panel", config))

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

    self:_storeEditorMeta("Slider", {
        on_change = self._onChange
    }, buildEditorSchema("Slider", config))

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
        local v = tonumber(self._value) or 0
        if self._step >= 1 then
            local iv = math.floor(v + 0.5)
            valText = self._label .. ": " .. tostring(iv) .. self._suffix
        else
            valText = self._label .. ": " .. string.format("%.2f", v) .. self._suffix
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
    local v = tonumber(self._value) or 0
    if self._step >= 1 then
        valText = tostring(math.floor(v + 0.5)) .. self._suffix
    else
        valText = string.format("%.2f", v) .. self._suffix
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
    local self = setmetatable(Widgets.Slider.new(parent, name, config), Widgets.VSlider)
    -- Override the type stored by Slider.new
    self:_storeEditorMeta("VSlider", {
        on_change = self._onChange
    }, buildEditorSchema("VSlider", config))
    return self
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

    self:_storeEditorMeta("Knob", {
        on_change = self._onChange
    }, buildEditorSchema("Knob", config))

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
    local v = tonumber(self._value) or 0
    if self._step >= 1 then
        valText = tostring(math.floor(v + 0.5)) .. self._suffix
    else
        valText = string.format("%.2f", v) .. self._suffix
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

    self:_storeEditorMeta("Toggle", {
        on_change = self._onChange
    }, buildEditorSchema("Toggle", config))

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

    self:_storeEditorMeta("Dropdown", {
        on_select = self._onSelect
    }, buildEditorSchema("Dropdown", config))

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

    self:_storeEditorMeta("WaveformView", {
        on_scrub_start = self._onScrubStart,
        on_scrub_snap = self._onScrubSnap,
        on_scrub_speed = self._onScrubSpeed,
        on_scrub_end = self._onScrubEnd
    }, buildEditorSchema("WaveformView", config))
    
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

    self:_storeEditorMeta("Meter", {}, buildEditorSchema("Meter", config))

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

    self:_storeEditorMeta("SegmentedControl", {
        on_select = self._onSelect
    }, buildEditorSchema("SegmentedControl", config))

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

    self:_storeEditorMeta("NumberBox", {
        on_change = self._onChange
    }, buildEditorSchema("NumberBox", config))

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
-- DonutWidget - Circular/annular waveform display for loopers
-- ============================================================================

Widgets.DonutWidget = BaseWidget:extend()

function Widgets.DonutWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.DonutWidget)

    self._ringColour = colour(config.ringColour, 0xff22d3ee)
    self._playheadColour = colour(config.playheadColour, 0xfff8fafc)
    self._bgColour = colour(config.bgColour, 0x22475a75)
    self._thickness = config.thickness or 0.4  -- Inner radius as fraction of outer
    self._layerIndex = config.layerIndex or 0
    self._onSeek = config.on_seek or config.onSeek

    -- State for drawing (set externally via setLayerData)
    self._layerData = {}
    self._peaks = nil
    self._bounce = 0.0

    -- Enable mouse for seeking
    self.node:setInterceptsMouse(true, false)

    -- Store editor meta FIRST so exposeParams has something to merge into
    self:_storeEditorMeta("DonutWidget", {
        on_seek = self._onSeek,
    }, {})

    -- NOW expose params - they'll merge into the schema
    self:exposeParams({
        { path = "ringColour", label = "Ring Colour", type = "color", group = "Style" },
        { path = "playheadColour", label = "Playhead", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "thickness", label = "Thickness", type = "number", min = 0.2, max = 0.8, step = 0.05, group = "Style" },
    })

    return self
end

function Widgets.DonutWidget:onMouseDown(mx, my)
    self:_handleSeek(mx, my)
end

function Widgets.DonutWidget:onMouseDrag(mx, my, dx, dy)
    self:_handleSeek(mx, my)
end

function Widgets.DonutWidget:_handleSeek(mx, my)
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

function Widgets.DonutWidget:setLayerData(data)
    self._layerData = data or {}
end

function Widgets.DonutWidget:setPeaks(peaks)
    self._peaks = peaks
end

function Widgets.DonutWidget:setBounce(b)
    self._bounce = b or 0.0
end

local function donutLayerColor(state)
    if state == "recording" then return 0xffef4444 end
    if state == "playing" then return 0xff22c55e end
    if state == "overdubbing" then return 0xfff59e0b end
    if state == "paused" then return 0xffa78bfa end
    if state == "muted" then return 0xff64748b end
    return 0xff38bdf8
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

function Widgets.DonutWidget:onDraw(w, h)
    local cx, cy = w * 0.5, h * 0.5
    local baseRadius = math.max(20, math.min(w, h) * 0.34)
    local thickness = clamp(self._thickness, 0.2, 0.8)
    local baseInner = baseRadius * thickness
    local bounce = self._bounce or 0.0

    local layerData = self._layerData or {}
    local posNorm = clamp(tonumber(layerData.positionNorm) or 0.0, 0.0, 1.0)
    local peaks = self._peaks

    local radius = baseRadius + bounce * 2.4
    local inner = baseInner + bounce * 1.2

    -- Background circles
    drawDonutCircle(cx, cy, radius, self._bgColour, 72)
    drawDonutCircle(cx, cy, inner, self._bgColour, 72)

    local playheadIdx = 1

    if peaks and #peaks > 0 then
        playheadIdx = math.floor(posNorm * #peaks) + 1
        if playheadIdx < 1 then playheadIdx = 1 end
        if playheadIdx > #peaks then playheadIdx = #peaks end

        -- Use exposed ringColour directly
        gfx.setColour(self._ringColour)

        local window = 10
        local emphasisAmount = 2.6 * bounce

        for i = 1, #peaks do
            local p = clamp(peaks[i] or 0.0, 0.0, 1.0)

            local d = math.abs(i - playheadIdx)
            d = math.min(d, #peaks - d)

            local influence = 0.0
            if d <= window then
                influence = 1.0 - (d / window)
                influence = influence * influence
            end

            local shaped = clamp(
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

    -- Playhead
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

-- ============================================================================
-- XYPadWidget - 2D control surface with trails
-- ============================================================================

Widgets.XYPadWidget = BaseWidget:extend()

function Widgets.XYPadWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.XYPadWidget)

    self._x = config.x or 0.5
    self._y = config.y or 0.5
    self._handleColour = colour(config.handleColour, 0xffff8800)
    self._trailColour = colour(config.trailColour, 0xff22d3ee)
    self._bgColour = colour(config.bgColour, 0x00000000)  -- transparent by default
    self._gridColour = colour(config.gridColour, 0x00000000)  -- transparent by default
    self._showTrails = config.showTrails ~= false
    self._maxTrails = config.maxTrails or 50
    self._trails = {}
    self._onChange = config.on_change or config.onChange

    -- Store editor meta FIRST so exposeParams has something to merge into
    self:_storeEditorMeta("XYPadWidget", {
        on_change = self._onChange,
    }, {})

    -- NOW expose params - they'll merge into the schema
    self:exposeParams({
        { path = "handleColour", label = "Handle Colour", type = "color", group = "Style" },
        { path = "trailColour", label = "Trail Colour", type = "color", group = "Style" },
        { path = "bgColour", label = "Background", type = "color", group = "Style" },
        { path = "gridColour", label = "Grid", type = "color", group = "Style" },
        { path = "showTrails", label = "Show Trails", type = "bool", group = "Behavior" },
    })

    return self
end

function Widgets.XYPadWidget:onMouseDown(mx, my)
    self:_updateFromMouse(mx, my)
end

function Widgets.XYPadWidget:onMouseDrag(mx, my, dx, dy)
    self:_updateFromMouse(mx, my)
end

function Widgets.XYPadWidget:_updateFromMouse(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()
    local margin = 20

    self._x = clamp((mx - margin) / (w - margin * 2), 0, 1)
    self._y = clamp((my - margin) / (h - margin * 2), 0, 1)

    -- Add to trails
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

function Widgets.XYPadWidget:updateTrails(dt)
    for i = #self._trails, 1, -1 do
        local trail = self._trails[i]
        trail.life = trail.life - dt * 2
        if trail.life <= 0 then
            table.remove(self._trails, i)
        end
    end
end

function Widgets.XYPadWidget:getValues()
    return self._x, self._y
end

function Widgets.XYPadWidget:setValues(x, y)
    self._x = clamp(x or 0.5, 0, 1)
    self._y = clamp(y or 0.5, 0, 1)
end

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

function Widgets.XYPadWidget:onDraw(w, h)
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
    gfx.setColour(brighten(self._gridColour, 20))
    gfx.drawVerticalLine(math.floor(cx), margin, drawH)
    gfx.drawHorizontalLine(math.floor(cy), margin, drawW)

    -- Trails
    if self._showTrails then
        -- Extract base trail colour
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
            
            -- Blend with rainbow hue based on index
            local hue = i / #self._trails
            local hr, hg, hb = xyHsvToRgb(hue, 0.9, 1.0)
            local blend = 0.5  -- 50% trail colour, 50% rainbow
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

-- ============================================================================
-- GLSLWidget - Base widget for OpenGL shader rendering
-- Subclasses override onDrawGL(w, h) and call compileShaders(vs, fs)
-- ============================================================================

Widgets.GLSLWidget = BaseWidget:extend()

function Widgets.GLSLWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), Widgets.GLSLWidget)

    -- GL resource handles (0 = invalid/not created)
    self._program = 0
    self._vao = 0
    self._vbo = 0
    self._ibo = 0
    self._fbo = 0
    self._colorTex = 0
    self._depthRbo = 0
    self._fbWidth = 0
    self._fbHeight = 0

    -- Shader sources (can be set before GL context exists)
    self._vertexShader = config.vertexShader or nil
    self._fragmentShader = config.fragmentShader or nil

    -- Enable OpenGL for this canvas
    self.node:setOpenGLEnabled(true)

    -- Bind GL lifecycle callbacks
    self.node:setOnGLContextCreated(function()
        self:_onGLContextCreated()
    end)
    self.node:setOnGLContextClosing(function()
        self:_onGLContextClosing()
    end)
    self.node:setOnGLRender(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        self:_onGLRender(w, h)
    end)

    self:_storeEditorMeta("GLSLWidget", {}, {})

    return self
end

function Widgets.GLSLWidget:setShaders(vertexSource, fragmentSource)
    self._vertexShader = vertexSource
    self._fragmentShader = fragmentSource
    -- If GL context exists, recompile immediately
    if self._program and self._program ~= 0 then
        self:_compileIfNeeded()
    end
end

function Widgets.GLSLWidget:_onGLContextCreated()
    self:_createGeometry()
    self:_createFramebuffer(256, 256) -- initial size, resized on first render
    self:_compileIfNeeded()
end

function Widgets.GLSLWidget:_onGLContextClosing()
    self:_releaseGLResources()
end

function Widgets.GLSLWidget:_releaseGLResources()
    if gfx and gfx.releaseGLResources then
        -- Use built-in cleanup if available
    end
    -- Manual cleanup
    local gl = _G.gl
    if not gl then return end

    if self._program ~= 0 then
        pcall(function() gl.deleteProgram(self._program) end)
        self._program = 0
    end
    if self._vbo ~= 0 then
        pcall(function() gl.deleteBuffer(self._vbo) end)
        self._vbo = 0
    end
    if self._ibo ~= 0 then
        pcall(function() gl.deleteBuffer(self._ibo) end)
        self._ibo = 0
    end
    if self._vao ~= 0 then
        pcall(function() gl.deleteVertexArray(self._vao) end)
        self._vao = 0
    end
    if self._colorTex ~= 0 then
        pcall(function() gl.deleteTexture(self._colorTex) end)
        self._colorTex = 0
    end
    if self._depthRbo ~= 0 then
        pcall(function() gl.deleteRenderbuffer(self._depthRbo) end)
        self._depthRbo = 0
    end
    if self._fbo ~= 0 then
        pcall(function() gl.deleteFramebuffer(self._fbo) end)
        self._fbo = 0
    end
    self._fbWidth = 0
    self._fbHeight = 0
end

function Widgets.GLSLWidget:_createGeometry()
    local gl = _G.gl
    if not gl then return false end

    -- Full-screen quad: x, y, u, v
    local vertices = {
        -1.0, -1.0, 0.0, 0.0,
         1.0, -1.0, 1.0, 0.0,
         1.0,  1.0, 1.0, 1.0,
        -1.0,  1.0, 0.0, 1.0,
    }
    local indices = {0, 1, 2, 0, 2, 3}

    self._vbo = gl.createBuffer()
    gl.bindBuffer(GL.ARRAY_BUFFER, self._vbo)
    gl.bufferDataFloat(GL.ARRAY_BUFFER, vertices, GL.STATIC_DRAW)

    self._ibo = gl.createBuffer()
    gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, self._ibo)
    gl.bufferDataUInt16(GL.ELEMENT_ARRAY_BUFFER, indices, GL.STATIC_DRAW)

    self._vao = gl.createVertexArray()
    gl.bindVertexArray(self._vao)
    gl.bindBuffer(GL.ARRAY_BUFFER, self._vbo)
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 2, GL.FLOAT, false, 16, 0)
    gl.enableVertexAttribArray(1)
    gl.vertexAttribPointer(1, 2, GL.FLOAT, false, 16, 8)
    gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, self._ibo)
    gl.bindVertexArray(0)

    return true
end

function Widgets.GLSLWidget:_createFramebuffer(width, height)
    local gl = _G.gl
    if not gl then return false end
    if not GL.TEXTURE_2D then return false end

    -- Release old if exists
    if self._fbo ~= 0 then
        pcall(function() gl.deleteFramebuffer(self._fbo) end)
        self._fbo = 0
    end
    if self._colorTex ~= 0 then
        pcall(function() gl.deleteTexture(self._colorTex) end)
        self._colorTex = 0
    end
    if self._depthRbo ~= 0 then
        pcall(function() gl.deleteRenderbuffer(self._depthRbo) end)
        self._depthRbo = 0
    end

    self._colorTex = gl.createTexture()
    if not self._colorTex or self._colorTex == 0 then
        return false
    end
    gl.bindTexture(GL.TEXTURE_2D, self._colorTex)
    gl.texImage2DRGBA(GL.TEXTURE_2D, 0, width, height)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE)

    self._depthRbo = gl.createRenderbuffer()
    if not self._depthRbo or self._depthRbo == 0 then
        return false
    end
    gl.bindRenderbuffer(GL.RENDERBUFFER, self._depthRbo)
    gl.renderbufferStorage(GL.RENDERBUFFER, GL.DEPTH24_STENCIL8, width, height)

    self._fbo = gl.createFramebuffer()
    if not self._fbo or self._fbo == 0 then
        return false
    end
    gl.bindFramebuffer(GL.FRAMEBUFFER, self._fbo)
    gl.framebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, self._colorTex, 0)
    gl.framebufferRenderbuffer(GL.FRAMEBUFFER, GL.DEPTH_STENCIL_ATTACHMENT, GL.RENDERBUFFER, self._depthRbo)

    local status = gl.checkFramebufferStatus(GL.FRAMEBUFFER)
    gl.bindFramebuffer(GL.FRAMEBUFFER, 0)

    if status ~= GL.FRAMEBUFFER_COMPLETE then
        return false
    end

    self._fbWidth = width
    self._fbHeight = height
    return true
end

function Widgets.GLSLWidget:_compileIfNeeded()
    if not self._vertexShader or not self._fragmentShader then
        return false
    end
    if self._program ~= 0 then
        self:_releaseProgramOnly()
    end
    return self:_compileShaders(self._vertexShader, self._fragmentShader)
end

function Widgets.GLSLWidget:_releaseProgramOnly()
    local gl = _G.gl
    if not gl then return end
    if self._program ~= 0 then
        pcall(function() gl.deleteProgram(self._program) end)
        self._program = 0
    end
end

function Widgets.GLSLWidget:_compileShaders(vertexSource, fragmentSource)
    local gl = _G.gl
    if not gl then return false end

    local function compileShader(shaderType, source, label)
        local shader = gl.createShader(shaderType)
        gl.shaderSource(shader, source)
        gl.compileShader(shader)
        local status = gl.getShaderCompileStatus(shader)
        if status == 0 then
            local log = gl.getShaderInfoLog(shader) or ""
            gl.deleteShader(shader)
            return nil, log
        end
        return shader
    end

    local vs, vsErr = compileShader(GL.VERTEX_SHADER, vertexSource, "vertex")
    if not vs then return false, vsErr end

    local fs, fsErr = compileShader(GL.FRAGMENT_SHADER, fragmentSource, "fragment")
    if not fs then
        gl.deleteShader(vs)
        return false, fsErr
    end

    self._program = gl.createProgram()
    gl.attachShader(self._program, vs)
    gl.attachShader(self._program, fs)
    gl.linkProgram(self._program)

    local linkStatus = gl.getProgramLinkStatus(self._program)
    gl.deleteShader(vs)
    gl.deleteShader(fs)

    if linkStatus == 0 then
        local log = gl.getProgramInfoLog(self._program) or ""
        gl.deleteProgram(self._program)
        self._program = 0
        return false, log
    end

    return true
end

function Widgets.GLSLWidget:_onGLRender(w, h)
    -- Subclasses override onDrawGL(w, h) for custom rendering
    local gl = _G.gl
    if not gl then return end

    -- Debug
    if not self._renderCount then self._renderCount = 0 end
    self._renderCount = self._renderCount + 1
    if self._renderCount % 60 == 0 then
        print(string.format("GLSLWidget._onGLRender called: program=%d animTime=%.2f", self._program or 0, self._animTime or -1))
    end

    -- Call subclass method
    if self.onDrawGL then
        self:onDrawGL(w, h)
    else
        -- Base: clear to black
        gl.clearColor(0, 0, 0, 1)
        gl.clear(GL.COLOR_BUFFER_BIT)
    end
end

function Widgets.GLSLWidget:_ensureFramebufferSize(w, h)
    if w ~= self._fbWidth or h ~= self._fbHeight then
        return self:_createFramebuffer(w, h)
    end
    return true
end

-- Override this in subclasses for custom rendering
function Widgets.GLSLWidget:onDrawGL(w, h)
    -- Subclasses implement their render logic here
    -- Called from _onGLRender after setup
end

-- ============================================================================
-- Export the Widgets module with BaseWidget exposed for extension
-- ============================================================================

Widgets.BaseWidget = BaseWidget

return Widgets

-- base.lua
-- BaseWidget class - all widgets inherit from this

local Utils = require("widgets.utils")

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

-- Parameter Exposure API
function BaseWidget:exposeParams(specs)
    -- Declare custom editable parameters for this widget.
    if not self._exposedParams then
        self._exposedParams = {}
    end
    for _, item in ipairs(specs or {}) do
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
    local key = "_" .. path
    return self[key]
end

function BaseWidget:_setExposed(path, value)
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

return BaseWidget

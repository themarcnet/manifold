-- base.lua
-- BaseWidget class - all widgets inherit from this

local Utils = require("widgets.utils")

local BaseWidget = {}
BaseWidget.__index = BaseWidget

local function parentIsCanvas(parent)
    return parent ~= nil and parent.getRuntimeNode ~= nil
end

local function parentIsRuntimeNode(parent)
    return parent ~= nil and parent.getRuntimeNode == nil and parent.createChild ~= nil
end

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

    if parentIsCanvas(parent) then
        self.node = parent:addChild(name)
        self.runtimeNode = self.node:getRuntimeNode()
        self._runtimeNodeOnly = false
    elseif parentIsRuntimeNode(parent) then
        self.node = parent:createChild(name)
        self.runtimeNode = self.node
        self._runtimeNodeOnly = true
    else
        error("BaseWidget.new expected Canvas or RuntimeNode parent")
    end

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
    -- Store editor metadata on the current authored node for introspection.
    self.node:setWidgetType(widgetType)
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
    if self.node.setOnMouseEnter then
        self.node:setOnMouseEnter(function()
            self._hovered = true
            self:refreshRetained()
            self.node:repaint()
            self:onMouseEnter()
        end)
    end

    if self.node.setOnMouseExit then
        self.node:setOnMouseExit(function()
            self._hovered = false
            self:refreshRetained()
            self.node:repaint()
            self:onMouseExit()
        end)
    end

    if self.node.setOnMouseDown then
        self.node:setOnMouseDown(function(mx, my, shift, ctrl, alt)
            if not self._enabled then return end
            self._pressed = true
            self:refreshRetained()
            self.node:repaint()
            self:onMouseDown(mx, my, shift, ctrl, alt)
        end)
    end

    if self.node.setOnMouseDrag then
        self.node:setOnMouseDrag(function(mx, my, dx, dy, shift, ctrl, alt)
            if not self._enabled then return end
            self:onMouseDrag(mx, my, dx, dy, shift, ctrl, alt)
        end)
    end

    if self.node.setOnMouseUp then
        self.node:setOnMouseUp(function(mx, my, shift, ctrl, alt)
            self._pressed = false
            self:refreshRetained()
            self.node:repaint()
            self:onMouseUp(mx, my, shift, ctrl, alt)
        end)
    end
    
    if self.node.setOnClick then
        self.node:setOnClick(function() 
            if not self._enabled then return end
            self:onClick() 
        end)
    end
    
    if self.node.setOnDoubleClick then
        self.node:setOnDoubleClick(function()
            if not self._enabled then return end
            self:onDoubleClick()
        end)
    end

    if (not self._runtimeNodeOnly) and self.node.setOnDraw then
        self.node:setOnDraw(function(node)
            self._hovered = node:isMouseOver()
            self:onDraw(node:getWidth(), node:getHeight())
        end)
    else
        self:refreshRetained()
    end
end

function BaseWidget:onMouseDown(mx, my) end
function BaseWidget:onMouseDrag(mx, my, dx, dy) end
function BaseWidget:onMouseUp(mx, my) end
function BaseWidget:onClick() end
function BaseWidget:onDoubleClick() end
function BaseWidget:onMouseEnter() end
function BaseWidget:onMouseExit() end
function BaseWidget:onDraw(w, h) end
function BaseWidget:_syncRetained(w, h) end
function BaseWidget:tickRetained(dt) end

function BaseWidget:refreshRetained(w, h)
    if type(self._syncRetained) ~= "function" then
        return
    end

    self._deferredRetainedW = w
    self._deferredRetainedH = h

    local shell = (type(_G) == "table") and _G.shell or nil
    local canDefer = type(shell) == "table"
        and type(shell.deferRetainedRefresh) == "function"
        and type(shell.flushDeferredRefreshes) == "function"

    if canDefer then
        local generation = tonumber(shell._deferredRefreshGeneration) or 0
        if self._retainedRefreshGeneration ~= generation then
            self._retainedRefreshQueued = false
            self._retainedRefreshGeneration = generation
        end

        if self._retainedRefreshQueued then
            return
        end

        self._retainedRefreshQueued = true
        self._retainedRefreshGeneration = generation
        shell:deferRetainedRefresh(function()
            if self._retainedRefreshGeneration ~= generation then
                return
            end
            self._retainedRefreshQueued = false
            local queuedW = self._deferredRetainedW
            local queuedH = self._deferredRetainedH
            self._deferredRetainedW = nil
            self._deferredRetainedH = nil
            self:_syncRetained(queuedW, queuedH)
        end)
        return
    end

    self._retainedRefreshQueued = false
    self._deferredRetainedW = nil
    self._deferredRetainedH = nil
    self:_syncRetained(w, h)
end

function BaseWidget:setEnabled(enabled)
    local nextEnabled = enabled ~= false
    if self._enabled == nextEnabled then
        return
    end
    self._enabled = nextEnabled
    self:refreshRetained()
    if self.node and self.node.repaint then
        self.node:repaint()
    end
end

function BaseWidget:setVisible(visible)
    local nextVisible = visible == true
    if self.node and self.node.isVisible and self.node:isVisible() == nextVisible then
        return
    end
    if self.node and self.node.setVisible then
        self.node:setVisible(nextVisible)
    end

    local rendererMode = "canvas"
    if type(getUIRendererMode) == "function" then
        rendererMode = tostring(getUIRendererMode() or "canvas")
    end

    if nextVisible and rendererMode ~= "canvas" then
        self:refreshRetained()
    end
end

function BaseWidget:getPreferredWidth()
    if self.config and self.config.preferredWidth ~= nil then
        return tonumber(self.config.preferredWidth) or 0
    end
    if self.node and self.node.getWidth then
        return tonumber(self.node:getWidth()) or 0
    end
    return tonumber(self.config and self.config.w) or 0
end

function BaseWidget:getPreferredHeight()
    if self.config and self.config.preferredHeight ~= nil then
        return tonumber(self.config.preferredHeight) or 0
    end
    if self.node and self.node.getHeight then
        return tonumber(self.node:getHeight()) or 0
    end
    return tonumber(self.config and self.config.h) or 0
end

function BaseWidget:getMinWidth()
    return tonumber(self.config and (self.config.minW or self.config.minWidth)) or 0
end

function BaseWidget:getMinHeight()
    return tonumber(self.config and (self.config.minH or self.config.minHeight)) or 0
end

function BaseWidget:requestLayout()
    local runtime = self._structuredRuntime
    local record = self._structuredRecord
    if type(runtime) ~= "table" or type(runtime.notifyRecordHostedResized) ~= "function" or type(record) ~= "table" then
        return false
    end

    local refreshRecord = record.parent or record
    local ok = pcall(function()
        runtime:notifyRecordHostedResized(refreshRecord)
    end)
    return ok == true
end

function BaseWidget:isEnabled()
    return self._enabled
end

function BaseWidget:isVisible()
    if self.node and self.node.isVisible then
        return self.node:isVisible()
    end
    return true
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
    local sizeChanged = self._lastRetainedBoundsW ~= iw or self._lastRetainedBoundsH ~= ih
    self._lastRetainedBoundsW = iw
    self._lastRetainedBoundsH = ih
    self.node:setBounds(ix, iy, iw, ih)
    if self._runtimeNodeOnly then
        if sizeChanged and iw > 0 and ih > 0 then
            self:refreshRetained(iw, ih)
        end
        return
    end

    local rendererMode = "canvas"
    if type(getUIRendererMode) == "function" then
        rendererMode = tostring(getUIRendererMode() or "canvas")
    end

    if rendererMode ~= "canvas" and sizeChanged and iw > 0 and ih > 0 then
        self:refreshRetained(iw, ih)
    end
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
    self:refreshRetained()
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

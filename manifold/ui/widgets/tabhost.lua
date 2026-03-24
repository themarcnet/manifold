local BaseWidget = require("widgets.base")
local Utils = require("widgets.utils")
local Schema = require("widgets.schema")

local TabHost = BaseWidget:extend()

local function clampIndex(idx, count)
    if count <= 0 then
        return 0
    end
    return Utils.clamp(math.floor(tonumber(idx) or 1), 1, count)
end

local function coerceLabel(value, fallback)
    local text = tostring(value or "")
    if text == "" then
        return fallback or "Tab"
    end
    return text
end

local function refreshRecordRetained(record)
    if type(record) ~= "table" then
        return
    end

    local widget = record.widget
    if type(widget) == "table" and type(widget.refreshRetained) == "function" then
        local node = widget.node
        local w = 0
        local h = 0
        if node and node.getWidth and node.getHeight then
            w = tonumber(node:getWidth()) or 0
            h = tonumber(node:getHeight()) or 0
        elseif node and node.getBounds then
            local _, _, bw, bh = node:getBounds()
            w = tonumber(bw) or 0
            h = tonumber(bh) or 0
        end
        widget:refreshRetained(w, h)
    end

    for _, child in ipairs(record.children or {}) do
        refreshRecordRetained(child)
    end
end

local function shouldForceImmediateRefreshFlush()
    if type(getUIRendererMode) ~= "function" then
        return false
    end
    return tostring(getUIRendererMode() or "") == "canvas"
end

local function flushDeferredRefreshesNow()
    if not shouldForceImmediateRefreshFlush() then
        return
    end
    local shell = (type(_G) == "table") and _G.shell or nil
    if shell and type(shell.flushDeferredRefreshes) == "function" then
        shell:flushDeferredRefreshes()
    end
end

local function setStyleAndDisplay(host, w, h)
    host.node:setStyle({
        bg = host._bg,
        border = host._border,
        borderWidth = host._borderWidth,
        radius = host._radius,
        opacity = 1.0,
    })

    local display = {
        {
            cmd = "fillRoundedRect",
            x = 0,
            y = 0,
            w = w,
            h = host._tabBarHeight,
            radius = host._radius,
            color = host._tabBarBg,
        }
    }

    for i = 1, #host._tabRects do
        local r = host._tabRects[i]
        local page = host._pages[i]
        local label = coerceLabel(page and page.title, page and page.id or ("Tab " .. tostring(i)))
        local active = (i == host._activeIndex)
        local bg = active and host._activeTabBg or host._tabBg
        if host:isHovered() and not active then
            bg = Utils.brighten(bg, 10)
        end

        display[#display + 1] = {
            cmd = "fillRoundedRect",
            x = r.x,
            y = r.y,
            w = r.w,
            h = math.max(0, r.h - 2),
            radius = math.max(0, host._radius - 2),
            color = bg,
        }
        display[#display + 1] = {
            cmd = "drawText",
            x = r.x + 6,
            y = r.y,
            w = math.max(0, r.w - 12),
            h = r.h,
            color = active and host._activeTextColour or host._textColour,
            text = label,
            fontSize = 12.0,
            align = "center",
            valign = "middle",
        }
    end

    host.node:setDisplayList(display)
end

function TabHost.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), TabHost)

    self._activeIndex = math.floor(tonumber(config.activeIndex or config.selected or 1) or 1)
    self._tabBarHeight = math.max(18, math.floor(tonumber(config.tabBarHeight or 26) or 26))
    self._tabGap = math.max(0, math.floor(tonumber(config.tabGap or 4) or 4))
    self._tabPadding = math.max(8, math.floor(tonumber(config.tabPadding or 12) or 12))
    self._tabSizing = string.lower(tostring(config.tabSizing or config.tabLayout or config.tabMode or "fill"))
    self._bg = Utils.colour(config.bg, 0xff0f172a)
    self._border = Utils.colour(config.border, 0xff334155)
    self._borderWidth = math.max(0, tonumber(config.borderWidth or 1) or 1)
    self._radius = math.max(0, tonumber(config.radius or 8) or 8)
    self._tabBarBg = Utils.colour(config.tabBarBg, 0xff111827)
    self._tabBg = Utils.colour(config.tabBg, 0xff1e293b)
    self._activeTabBg = Utils.colour(config.activeTabBg, 0xff2563eb)
    self._textColour = Utils.colour(config.textColour, 0xffcbd5e1)
    self._activeTextColour = Utils.colour(config.activeTextColour, 0xffffffff)
    self._pages = {}
    self._tabRects = {}
    self._onSelect = config.on_select or config.onSelect
    self._layoutDirty = true
    self._lastLayoutW = -1
    self._lastLayoutH = -1
    self._lastLayoutActiveIndex = -1
    self._lastLayoutPageCount = -1
    self._structuredRuntime = nil
    self._structuredRecord = nil

    self:_storeEditorMeta("TabHost", {
        on_select = self._onSelect,
    }, Schema.buildEditorSchema("TabHost", config))

    self:_syncRetained()

    return self
end

function TabHost:isTabHost()
    return true
end

function TabHost:setStructuredRuntime(runtime, record)
    self._structuredRuntime = runtime
    self._structuredRecord = record
end

function TabHost:_notifyRuntimeLayoutChanged()
    local runtime = self._structuredRuntime
    local record = self._structuredRecord
    if runtime and type(runtime.notifyHostedContainerChanged) == "function" and record then
        runtime:notifyHostedContainerChanged(record)
    end
end

function TabHost:_computeTabRects(w)
    local rects = {}
    local x = 0
    local h = self._tabBarHeight
    local pageCount = #self._pages

    if pageCount <= 0 then
        return rects
    end

    if self._tabSizing == "fit" or self._tabSizing == "content" then
        for i = 1, pageCount do
            local page = self._pages[i]
            local label = coerceLabel(page.title, page.id or ("Tab " .. tostring(i)))
            local tabW = math.max(72, math.min(220, self._tabPadding * 2 + (#label * 7)))
            rects[i] = {
                x = x,
                y = 0,
                w = math.min(tabW, math.max(0, w - x)),
                h = h,
            }
            x = x + rects[i].w + self._tabGap
        end
        return rects
    end

    local totalGap = self._tabGap * math.max(0, pageCount - 1)
    local availableW = math.max(0, w - totalGap)
    local baseW = math.floor(availableW / pageCount)
    local remainder = availableW - baseW * pageCount

    for i = 1, pageCount do
        local tabW = baseW
        if remainder > 0 then
            tabW = tabW + 1
            remainder = remainder - 1
        end
        rects[i] = {
            x = x,
            y = 0,
            w = math.max(0, tabW),
            h = h,
        }
        x = x + rects[i].w + self._tabGap
    end

    return rects
end

function TabHost:getContentRect()
    local w = math.floor(self.node:getWidth() or 0)
    local h = math.floor(self.node:getHeight() or 0)
    return 0, self._tabBarHeight, w, math.max(0, h - self._tabBarHeight)
end

function TabHost:_layoutPages(force)
    local w = math.floor(self.node:getWidth() or 0)
    local h = math.floor(self.node:getHeight() or 0)
    local pageCount = #self._pages
    local activeIndex = clampIndex(self._activeIndex, pageCount)

    if not force
        and not self._layoutDirty
        and self._lastLayoutW == w
        and self._lastLayoutH == h
        and self._lastLayoutActiveIndex == activeIndex
        and self._lastLayoutPageCount == pageCount then
        return
    end

    self._activeIndex = activeIndex
    self._tabRects = self:_computeTabRects(w)

    local contentX, contentY, contentW, contentH = self:getContentRect()

    for i = 1, pageCount do
        local page = self._pages[i]
        local active = (i == self._activeIndex)
        if page.widget then
            if type(page.widget.setBounds) == "function" then
                page.widget:setBounds(contentX, contentY, contentW, contentH)
            elseif page.widget.node and page.widget.node.setBounds then
                page.widget.node:setBounds(contentX, contentY, contentW, contentH)
            end
            if type(page.widget.setVisible) == "function" then
                page.widget:setVisible(active)
            end
        end
    end

    self._layoutDirty = false
    self._lastLayoutW = w
    self._lastLayoutH = h
    self._lastLayoutActiveIndex = self._activeIndex
    self._lastLayoutPageCount = pageCount
end

function TabHost:addStructuredChild(childRecord)
    if type(childRecord) ~= "table" or type(childRecord.widget) ~= "table" then
        return
    end

    local childWidget = childRecord.widget
    if type(childWidget.isTabPage) ~= "function" or childWidget:isTabPage() ~= true then
        return
    end

    self._pages[#self._pages + 1] = {
        widget = childWidget,
        id = childRecord.spec and childRecord.spec.id or ("page_" .. tostring(#self._pages + 1)),
        title = (type(childWidget.getTabTitle) == "function" and childWidget:getTabTitle()) or (childRecord.spec and childRecord.spec.title) or nil,
        record = childRecord,
    }
    self._layoutDirty = true
    self:_layoutPages(true)
    self:_syncRetained()
end

function TabHost:finalizeStructuredChildren()
    self._layoutDirty = true
    self:_layoutPages(true)
    local activePage = self:getActivePageRecord()
    if activePage ~= nil then
        refreshRecordRetained(activePage)
        flushDeferredRefreshesNow()
    end
    self:_syncRetained()
    self:_notifyRuntimeLayoutChanged()
end

function TabHost:setOnSelect(fn)
    self._onSelect = fn
end

function TabHost:getActiveIndex()
    return self._activeIndex
end

function TabHost:getSelected()
    return self._activeIndex
end

function TabHost:getActiveTabId()
    local page = self._pages[self._activeIndex]
    return page and page.id or nil
end

function TabHost:getActivePageRecord()
    local page = self._pages[self._activeIndex]
    return page and page.record or nil
end

function TabHost:getPageRecords()
    local out = {}
    for i = 1, #self._pages do
        out[i] = self._pages[i].record
    end
    return out
end

function TabHost:setSelected(idx)
    self:setActiveIndex(idx)
end

function TabHost:setActiveTab(idOrIndex)
    if type(idOrIndex) == "number" then
        self:setActiveIndex(idOrIndex)
        return
    end

    for i = 1, #self._pages do
        if self._pages[i].id == idOrIndex then
            self:setActiveIndex(i)
            return
        end
    end
end

function TabHost:setActiveIndex(idx)
    local nextIndex = clampIndex(idx, #self._pages)
    if nextIndex == self._activeIndex then
        return
    end
    self._activeIndex = nextIndex
    self._layoutDirty = true
    self:_layoutPages(true)
    local activePage = self:getActivePageRecord()
    if activePage ~= nil then
        refreshRecordRetained(activePage)
        flushDeferredRefreshesNow()
    end
    self:_syncRetained()
    self:_notifyRuntimeLayoutChanged()
    if self._onSelect and nextIndex > 0 then
        local page = self._pages[nextIndex]
        self._onSelect(nextIndex, page and page.id or nil, page and page.title or nil)
    end
    self.node:repaint()
end

function TabHost:setTabBarHeight(value)
    self._tabBarHeight = math.max(18, math.floor(tonumber(value) or self._tabBarHeight))
    self._layoutDirty = true
    self:_layoutPages(true)
    self:_syncRetained()
    self:_notifyRuntimeLayoutChanged()
    self.node:repaint()
end

function TabHost:setBg(value)
    self._bg = value
    self:_syncRetained()
    self.node:repaint()
end

function TabHost:setTextColour(value)
    self._textColour = value
    self:_syncRetained()
    self.node:repaint()
end

function TabHost:setActiveTextColour(value)
    self._activeTextColour = value
    self:_syncRetained()
    self.node:repaint()
end

function TabHost:setStyle(style)
    if style.bg ~= nil then self._bg = style.bg end
    if style.border ~= nil then self._border = style.border end
    if style.borderWidth ~= nil then self._borderWidth = style.borderWidth end
    if style.radius ~= nil then self._radius = style.radius end
    if style.tabBarBg ~= nil then self._tabBarBg = style.tabBarBg end
    if style.tabBg ~= nil then self._tabBg = style.tabBg end
    if style.activeTabBg ~= nil then self._activeTabBg = style.activeTabBg end
    if style.textColour ~= nil then self._textColour = style.textColour end
    if style.activeTextColour ~= nil then self._activeTextColour = style.activeTextColour end
    if style.tabSizing ~= nil then self._tabSizing = string.lower(tostring(style.tabSizing)) end
    self:_syncRetained()
    self.node:repaint()
end

function TabHost:onMouseDown(mx, my)
    if my < 0 or my > self._tabBarHeight then
        return
    end

    for i = 1, #self._tabRects do
        local r = self._tabRects[i]
        if mx >= r.x and mx <= (r.x + r.w) and my >= r.y and my <= (r.y + r.h) then
            self:setActiveIndex(i)
            return
        end
    end
end

function TabHost:_syncRetained(w, h)
    w = math.floor(w or self.node:getWidth() or 0)
    h = math.floor(h or self.node:getHeight() or 0)
    self:_layoutPages(false)
    setStyleAndDisplay(self, w, h)
end

function TabHost:onDraw(w, h)
    self:_layoutPages(false)

    if (self._bg >> 24) & 0xff > 0 then
        gfx.setColour(self._bg)
        gfx.fillRoundedRect(0, 0, w, h, self._radius)
    end

    gfx.setColour(self._tabBarBg)
    gfx.fillRoundedRect(0, 0, w, self._tabBarHeight, self._radius)

    for i = 1, #self._tabRects do
        local r = self._tabRects[i]
        local page = self._pages[i]
        local label = coerceLabel(page and page.title, page and page.id or ("Tab " .. tostring(i)))
        local active = (i == self._activeIndex)
        local bg = active and self._activeTabBg or self._tabBg

        if self:isHovered() and not active then
            bg = Utils.brighten(bg, 10)
        end

        gfx.setColour(bg)
        gfx.fillRoundedRect(r.x, r.y, r.w, math.max(0, r.h - 2), math.max(0, self._radius - 2))

        gfx.setColour(active and self._activeTextColour or self._textColour)
        gfx.setFont(12.0)
        gfx.drawText(label, r.x + 6, r.y, math.max(0, r.w - 12), r.h, Justify.centred)
    end

    if self._borderWidth > 0 and (self._border >> 24) & 0xff > 0 then
        gfx.setColour(self._border)
        gfx.drawRoundedRect(0, 0, w, h, self._radius, self._borderWidth)
    end
end

return TabHost

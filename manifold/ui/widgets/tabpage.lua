local Panel = require("widgets.panel")
local Schema = require("widgets.schema")

local TabPage = Panel:extend()

function TabPage.new(parent, name, config)
    local self = setmetatable(Panel.new(parent, name, config), TabPage)
    self._title = config.title or config.tabTitle or config.label or name
    self._tabVisible = config.tabVisible ~= false and config.visible ~= false

    self:_storeEditorMeta("TabPage", {}, Schema.buildEditorSchema("TabPage", config))

    return self
end

function TabPage:isTabPage()
    return true
end

function TabPage:getTabTitle()
    return self._title
end

function TabPage:isTabVisible()
    return self._tabVisible ~= false
end

function TabPage:setTabVisible(visible)
    self._tabVisible = visible == true
    if self.node and self.node.repaint then
        self.node:repaint()
    end
end

function TabPage:setTitle(value)
    self._title = tostring(value or "")
    if self.node and self.node.repaint then
        self.node:repaint()
    end
end

function TabPage:setLabel(value)
    self:setTitle(value)
end

return TabPage

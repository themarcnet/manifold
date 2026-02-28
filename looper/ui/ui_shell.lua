-- ui_shell.lua
-- Shared parent shell/header for Lua UI scripts.

local W = require("looper_widgets")

local Shell = {}

local function readParam(params, path, fallback)
    if type(params) ~= "table" then
        return fallback
    end
    local v = params[path]
    if v == nil then
        return fallback
    end
    return v
end

local function readBoolParam(params, path, fallback)
    local raw = readParam(params, path, fallback and 1 or 0)
    if raw == nil then
        return fallback
    end
    return raw == true or raw == 1
end

local function getVisibleUiScripts(currentPath)
    local listed = listUiScripts() or {}
    local visible = {}
    for i = 1, #listed do
        local s = listed[i]
        if type(s) == "table" and type(s.path) == "string" then
            visible[#visible + 1] = s
        end
    end
    return visible
end

function Shell.create(parentNode, options)
    local opts = options or {}
    local shell = {
        parentNode = parentNode,
        pad = opts.pad or 0,
        height = opts.height or 44,
        gapAfter = opts.gapAfter or 6,
        onBeforeSwitch = opts.onBeforeSwitch,
        title = opts.title or "PLUGIN",
    }

    shell.panel = W.Panel.new(parentNode, "sharedShell", {
        bg = 0xff111827,
        border = 0xff1f2937,
        borderWidth = 1,
    })

    shell.titleLabel = W.Label.new(shell.panel.node, "sharedShellTitle", {
        text = shell.title,
        colour = 0xff7dd3fc,
        fontSize = 18.0,
        fontStyle = FontStyle.bold,
    })

    shell.masterKnob = W.Knob.new(shell.panel.node, "sharedMaster", {
        min = 0, max = 1, step = 0.01, value = 0.8,
        label = "Master", suffix = "",
        colour = 0xffa78bfa,
        on_change = function(v)
            command("SET", "/core/behavior/volume", tostring(v))
        end,
    })

    shell.inputKnob = W.Knob.new(shell.panel.node, "sharedInput", {
        min = 0, max = 2, step = 0.01, value = 1.0,
        label = "Input", suffix = "",
        colour = 0xfff59e0b,
        on_change = function(v)
            command("SET", "/core/behavior/inputVolume", tostring(v))
        end,
    })

    shell.passthroughToggle = W.Toggle.new(shell.panel.node, "sharedPassthrough", {
        label = "Input",
        onColour = 0xff34d399,
        offColour = 0xff475569,
        value = true,
        on_change = function(on)
            command("SET", "/core/behavior/passthrough", on and "1" or "0")
        end,
    })

    local settingsOpen = false
    local scriptOverlay = nil

    shell.settingsButton = W.Button.new(shell.panel.node, "sharedSettings", {
        label = "Settings",
        bg = 0xff1e293b,
        fontSize = 13.0,
        on_click = function()
            settingsOpen = not settingsOpen
            if not settingsOpen then
                if scriptOverlay then
                    scriptOverlay:setBounds(0, 0, 0, 0)
                end
                return
            end

            local currentPath = getCurrentScriptPath()
            local scripts = getVisibleUiScripts(currentPath)
            if scriptOverlay == nil then
                scriptOverlay = shell.parentNode:addChild("sharedScriptOverlay")
            end

            local itemH = 28
            local headerH = 26
            local overlayH = math.min(320, headerH + #scripts * itemH + 8)
            local overlayW = 240
            local btnX, btnY = shell.settingsButton.node:getBounds()
            local panelX, panelY = shell.panel.node:getBounds()

            scriptOverlay:setBounds(panelX + btnX - overlayW + 84, panelY + btnY + 32, overlayW, overlayH)

            scriptOverlay:setOnDraw(function(self)
                local w = self:getWidth()
                local h = self:getHeight()
                gfx.setColour(0x50000000)
                gfx.fillRoundedRect(2, 2, w, h, 6)
                gfx.setColour(0xff1e293b)
                gfx.fillRoundedRect(0, 0, w - 2, h - 2, 6)
                gfx.setColour(0xff475569)
                gfx.drawRoundedRect(0, 0, w - 2, h - 2, 6, 1)

                gfx.setColour(0xff94a3b8)
                gfx.setFont(10.0)
                gfx.drawText("UI Scripts", 10, 4, w - 20, headerH - 4, Justify.centredLeft)

                for i = 1, #scripts do
                    local s = scripts[i]
                    local y = headerH + (i - 1) * itemH
                    local isCurrent = (s.path == currentPath)
                    if isCurrent then
                        gfx.setColour(0xff334155)
                        gfx.fillRoundedRect(4, y, w - 10, itemH - 2, 4)
                    end
                    gfx.setColour(isCurrent and 0xff38bdf8 or 0xffe2e8f0)
                    gfx.setFont(11.0)
                    gfx.drawText(s.name, 12, y, w - 24, itemH - 2, Justify.centredLeft)
                end
            end)

            scriptOverlay:setOnMouseDown(function(mx, my)
                if my < headerH then
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)
                    return
                end

                local idx = math.floor((my - headerH) / itemH) + 1
                if idx >= 1 and idx <= #scripts then
                    local target = scripts[idx].path
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)

                    if target ~= currentPath then
                        if type(shell.onBeforeSwitch) == "function" then
                            shell.onBeforeSwitch(target, currentPath)
                        end
                        switchUiScript(target)
                    end
                else
                    settingsOpen = false
                    scriptOverlay:setBounds(0, 0, 0, 0)
                end
            end)
        end,
    })

    function shell:setTitle(text)
        self.titleLabel:setText(text)
    end

    function shell:layout(totalW, totalH)
        self.panel:setBounds(self.pad, self.pad, totalW - self.pad * 2, self.height)
        self.titleLabel:setBounds(10, 0, 130, self.height)

        local right = totalW - self.pad * 2 - 10
        local hGap = 8
        local knobW = self.height - 4

        self.settingsButton:setBounds(right - 80, 6, 78, self.height - 12)
        right = right - 80 - hGap

        self.masterKnob:setBounds(right - knobW, 2, knobW, self.height - 4)
        right = right - knobW - hGap

        self.inputKnob:setBounds(right - knobW, 2, knobW, self.height - 4)
        right = right - knobW - hGap

        self.passthroughToggle:setBounds(right - 80, 6, 80, self.height - 12)
    end

    function shell:getContentBounds(totalW, totalH)
        local x = self.pad
        local y = self.pad + self.height + self.gapAfter
        local w = totalW - self.pad * 2
        local h = totalH - y - self.pad
        return x, y, w, h
    end

    function shell:updateFromState(state)
        local params = state and state.params or state or {}
        self.masterKnob:setValue(readParam(params, "/core/behavior/volume", 0.8))
        self.inputKnob:setValue(readParam(params, "/core/behavior/inputVolume", 1.0))
        self.passthroughToggle:setValue(readBoolParam(params, "/core/behavior/passthrough", true))
    end

    return shell
end

return Shell

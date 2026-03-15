-- editor_core.lua
-- Editor mode layout. Created and managed by Shell, not standalone.

local W = require("ui_widgets")

local EditorCore = {}

function EditorCore.create(parentNode)
    local editor = {
        parentNode = parentNode,
        visible = false,
        treeWidth = 200,
        inspectorWidth = 260,
        gap = 6,
        previewBounds = {x=0, y=0, w=0, h=0},
    }

    -- Container for all editor panels
    editor.container = W.Panel.new(parentNode, "editorContainer", {
        bg = 0xff0a0f1a,
    })

    -- Tree panel (left)
    editor.treePanel = W.Panel.new(editor.container.node, "editorTree", {
        bg = 0xff141a24,
        border = 0xff334155,
        borderWidth = 1,
        radius = 6,
    })

    editor.treeHeader = W.Label.new(editor.treePanel.node, "treeHeader", {
        text = "Hierarchy",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    editor.treeContent = W.Label.new(editor.treePanel.node, "treeContent", {
        text = "No UI loaded",
        colour = 0xff64748b,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    -- Preview panel (center)
    editor.previewPanel = W.Panel.new(editor.container.node, "editorPreview", {
        bg = 0xff0f172a,
        border = 0xff334155,
        borderWidth = 1,
        radius = 6,
    })

    editor.previewHeader = W.Label.new(editor.previewPanel.node, "previewHeader", {
        text = "Canvas Preview",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    -- Preview canvas where User UI renders
    editor.previewCanvas = editor.previewPanel.node:addChild("previewCanvas")
    editor.previewCanvas:setInterceptsMouse(true, true)

    -- Inspector panel (right)
    editor.inspectorPanel = W.Panel.new(editor.container.node, "editorInspector", {
        bg = 0xff141a24,
        border = 0xff334155,
        borderWidth = 1,
        radius = 6,
    })

    editor.inspectorHeader = W.Label.new(editor.inspectorPanel.node, "inspectorHeader", {
        text = "Inspector",
        colour = 0xff94a3b8,
        fontSize = 12.0,
        fontStyle = FontStyle.bold,
    })

    editor.inspectorContent = W.Label.new(editor.inspectorPanel.node, "inspectorContent", {
        text = "Select a widget",
        colour = 0xff64748b,
        fontSize = 11.0,
        justification = Justify.centredLeft,
    })

    function editor:setVisible(visible)
        self.visible = visible
        if not visible then
            self.container:setBounds(0, 0, 0, 0)
            self.treePanel:setBounds(0, 0, 0, 0)
            self.treeHeader:setBounds(0, 0, 0, 0)
            self.treeContent:setBounds(0, 0, 0, 0)
            self.previewPanel:setBounds(0, 0, 0, 0)
            self.previewHeader:setBounds(0, 0, 0, 0)
            self.previewCanvas:setBounds(0, 0, 0, 0)
            self.inspectorPanel:setBounds(0, 0, 0, 0)
            self.inspectorHeader:setBounds(0, 0, 0, 0)
            self.inspectorContent:setBounds(0, 0, 0, 0)
        end
    end

    function editor:layout(x, y, w, h)
        if not self.visible then return end

        local ix, iy, iw, ih = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
        self.container:setBounds(ix, iy, iw, ih)

        local availW = iw - self.gap * 2
        local treeW = math.floor(math.min(self.treeWidth, availW * 0.22))
        local inspectorW = math.floor(math.min(self.inspectorWidth, availW * 0.28))
        local previewW = math.floor(availW - treeW - inspectorW)

        local headerH = 28
        local pad = 8

        -- Tree panel
        self.treePanel:setBounds(0, 0, treeW, ih)
        self.treeHeader:setBounds(pad, 4, treeW - pad*2, headerH)
        self.treeContent:setBounds(pad, headerH + 4, treeW - pad*2, ih - headerH - 8)

        -- Preview panel
        local previewX = treeW + self.gap
        self.previewPanel:setBounds(math.floor(previewX), 0, previewW, ih)
        self.previewHeader:setBounds(pad, 4, previewW - pad*2, headerH)

        -- Preview canvas bounds (for Shell to pass to Performance view)
        local pcX = math.floor(previewX + pad)
        local pcY = headerH + 4
        local pcW = previewW - pad*2
        local pcH = ih - headerH - 8
        self.previewCanvas:setBounds(pad, pcY, pcW, pcH)
        self.previewBounds = {x = pcX, y = pcY, w = pcW, h = pcH}

        -- Inspector panel
        self.inspectorPanel:setBounds(math.floor(treeW + previewW + self.gap*2), 0, inspectorW, ih)
        self.inspectorHeader:setBounds(pad, 4, inspectorW - pad*2, headerH)
        self.inspectorContent:setBounds(pad, headerH + 8, inspectorW - pad*2, ih - headerH - 16)
    end

    function editor:getPreviewBounds()
        return self.previewBounds
    end

    function editor:getPreviewCanvas()
        return self.previewCanvas
    end

    function editor:updateFromState(state)
        -- Update inspector, tree selection, etc.
    end

    -- Start hidden
    editor:setVisible(false)

    return editor
end

return EditorCore

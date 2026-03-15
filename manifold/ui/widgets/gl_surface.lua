-- gl_surface.lua
-- First-party GPU surface widget.
-- Source of truth is a structured surface descriptor on the RuntimeNode.
-- Backends may consume that descriptor directly (imgui-direct) or via adapters.

local BaseWidget = require("widgets.base")
local Schema = require("widgets.schema")

local GLSurfaceWidget = BaseWidget:extend()

local DEFAULT_VERTEX = [[
#version 150
in vec2 aPos;
in vec2 aUv;
out vec2 vUv;
void main() {
    vUv = aUv;
    gl_Position = vec4(aPos, 0.0, 1.0);
}
]]

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[deepCopy(k)] = deepCopy(v)
    end
    return out
end

local function normalizePass(pass)
    local p = deepCopy(pass or {})
    if type(p.vertexShader) ~= "string" or p.vertexShader == "" then
        p.vertexShader = DEFAULT_VERTEX
    end
    p.inputTextureUniform = p.inputTextureUniform or "uInputTex"
    p.uniforms = deepCopy(p.uniforms or {})
    return p
end

local function normalizeDescriptor(config)
    local descriptor = {
        version = 1,
        kind = "shaderQuad",
        shaderLanguage = "glsl",
        passes = {},
    }

    if type(config.surface) == "table" then
        local copy = deepCopy(config.surface)
        if type(copy.version) == "number" then descriptor.version = copy.version end
        if type(copy.kind) == "string" and copy.kind ~= "" then descriptor.kind = copy.kind end
        if type(copy.shaderLanguage) == "string" and copy.shaderLanguage ~= "" then descriptor.shaderLanguage = copy.shaderLanguage end
        if type(copy.passes) == "table" then
            for i = 1, #copy.passes do
                descriptor.passes[i] = normalizePass(copy.passes[i])
            end
        end
    end

    if #descriptor.passes == 0 then
        if type(config.vertexShader) == "string" or type(config.fragmentShader) == "string" then
            descriptor.passes[1] = normalizePass({
                vertexShader = config.vertexShader,
                fragmentShader = config.fragmentShader,
                uniforms = deepCopy(config.uniforms or {}),
                clearColor = deepCopy(config.clearColor),
                inputTextureUniform = config.inputTextureUniform,
            })
        end
    end

    return descriptor
end

function GLSurfaceWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config or {}), GLSurfaceWidget)
    self._descriptor = normalizeDescriptor(config or {})

    self:_storeEditorMeta("GLSurfaceWidget", {}, Schema.buildEditorSchema("GLSurfaceWidget", config or {}))
    self:refreshSurface()
    return self
end

function GLSurfaceWidget:setDescriptor(descriptor)
    self._descriptor = normalizeDescriptor({ surface = descriptor })
    self:refreshSurface()
end

function GLSurfaceWidget:getDescriptor()
    return deepCopy(self._descriptor)
end

function GLSurfaceWidget:setUniform(name, value, passIndex)
    local index = math.max(1, math.floor(tonumber(passIndex) or 1))
    self._descriptor.passes[index] = self._descriptor.passes[index] or normalizePass({})
    self._descriptor.passes[index].uniforms = self._descriptor.passes[index].uniforms or {}
    self._descriptor.passes[index].uniforms[name] = deepCopy(value)
    self:refreshSurface()
end

function GLSurfaceWidget:refreshSurface()
    if self.node and self.node.setCustomSurface then
        self.node:setCustomSurface("gpu_shader", deepCopy(self._descriptor))
    else
        self.node:setCustomSurfaceType("gpu_shader")
        self.node:setCustomRenderPayload(deepCopy(self._descriptor))
    end
    if self.node and self.node.repaint then
        self.node:repaint()
    end
end

function GLSurfaceWidget:onDraw(_w, _h)
end

function GLSurfaceWidget:_syncRetained(_w, _h)
    self:refreshSurface()
end

return GLSurfaceWidget

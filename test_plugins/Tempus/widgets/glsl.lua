-- glsl.lua
-- Base widget for OpenGL shader rendering

local BaseWidget = require("widgets.base")

local GLSLWidget = BaseWidget:extend()

function GLSLWidget.new(parent, name, config)
    local self = setmetatable(BaseWidget.new(parent, name, config), GLSLWidget)

    self._program = 0
    self._vao = 0
    self._vbo = 0
    self._ibo = 0
    self._fbo = 0
    self._colorTex = 0
    self._depthRbo = 0
    self._fbWidth = 0
    self._fbHeight = 0

    self._vertexShader = config.vertexShader or nil
    self._fragmentShader = config.fragmentShader or nil

    self.node:setOpenGLEnabled(true)

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

function GLSLWidget:setShaders(vertexSource, fragmentSource)
    self._vertexShader = vertexSource
    self._fragmentShader = fragmentSource
    if self._program and self._program ~= 0 then
        self:_compileIfNeeded()
    end
end

function GLSLWidget:_onGLContextCreated()
    self:_createGeometry()
    self:_createFramebuffer(256, 256)
    self:_compileIfNeeded()
end

function GLSLWidget:_onGLContextClosing()
    self:_releaseGLResources()
end

function GLSLWidget:_releaseGLResources()
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

function GLSLWidget:_createGeometry()
    local gl = _G.gl
    if not gl then return false end

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

function GLSLWidget:_createFramebuffer(width, height)
    local gl = _G.gl
    if not gl then return false end
    if not GL.TEXTURE_2D then return false end

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

function GLSLWidget:_compileIfNeeded()
    if not self._vertexShader or not self._fragmentShader then
        return false
    end
    if self._program ~= 0 then
        self:_releaseProgramOnly()
    end
    return self:_compileShaders(self._vertexShader, self._fragmentShader)
end

function GLSLWidget:_releaseProgramOnly()
    local gl = _G.gl
    if not gl then return end
    if self._program ~= 0 then
        pcall(function() gl.deleteProgram(self._program) end)
        self._program = 0
    end
end

function GLSLWidget:_compileShaders(vertexSource, fragmentSource)
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

function GLSLWidget:_onGLRender(w, h)
    local gl = _G.gl
    if not gl then return end

    if self.onDrawGL then
        self:onDrawGL(w, h)
    else
        gl.clearColor(0, 0, 0, 1)
        gl.clear(GL.COLOR_BUFFER_BIT)
    end
end

function GLSLWidget:_ensureFramebufferSize(w, h)
    if w ~= self._fbWidth or h ~= self._fbHeight then
        return self:_createFramebuffer(w, h)
    end
    return true
end

-- Override this in subclasses
function GLSLWidget:onDrawGL(w, h)
end

return GLSLWidget

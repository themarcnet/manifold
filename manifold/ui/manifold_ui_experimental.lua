-- manifold_ui_experimental.lua
-- EXPERIMENTAL: Creative UI exploration with particles, effects, and novel interactions
-- This is a playground for testing what's possible with the Canvas system
-- Now with OSC integration: XY Pad sends/receives OSC at /experimental/xy

local W = require("ui_widgets")

-- ============================================================================
-- Global State for Effects
-- ============================================================================
local current_state = {}
local MAX_LAYERS = 4
local ui = {}

-- OSC state
local oscEnabled = false
local oscSentCount = 0
local oscRecvCount = 0
local oscLastSent = "x=0.50 y=0.50"
local oscLastRecv = "x=0.50 y=0.50"
local oscLastTxLogTime = 0
local oscLastRxLogTime = 0

-- Animation state
local animTime = 0
local lastFrameTime = 0
local particles = {}
local trails = {}  -- For XY pad trails
local matrixDrops = {}  -- Matrix rain effect
local eqBars = {}
local spectrumBands = 32
local kaleidoscopeAngle = 0
local noiseOffset = 0

-- OpenGL retained resources (created/destroyed with context)
local glState = {
    sceneProgram = 0,
    postProgram = 0,
    vao = 0,
    vbo = 0,
    ibo = 0,
    fbo = 0,
    colorTex = 0,
    depthRbo = 0,
    fbWidth = 0,
    fbHeight = 0,
    scenePosLoc = -1,
    sceneUvLoc = -1,
    postPosLoc = -1,
    postUvLoc = -1,
    sceneTimeLoc = -1,
    sceneResolutionLoc = -1,
    postTimeLoc = -1,
    postResolutionLoc = -1,
    postInputTexLoc = -1,
    postIntensityLoc = -1,
    ready = false,
    lastError = nil,
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t) return a + (b - a) * t end

local function hsvToRgb(h, s, v)
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
    else r, g, b = v, p, q
    end

    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

local function rgbToInt(r, g, b, a)
    a = a or 255
    return (a << 24) | (r << 16) | (g << 8) | b
end

local function randomRange(min, max)
    return min + math.random() * (max - min)
end

local function readParam(params, path, fallback)
    if type(params) ~= "table" then
        return fallback
    end
    local value = params[path]
    if value == nil then
        return fallback
    end
    return value
end

local function readBoolParam(params, path, fallback)
    local raw = readParam(params, path, fallback and 1 or 0)
    if raw == nil then
        return fallback
    end
    return raw == true or raw == 1
end

local function normalizeState(state)
    if type(state) ~= "table" then
        return {}
    end

    local params = state.params or {}
    local voices = state.voices or {}
    local normalized = {
        params = params,
        voices = voices,
        spectrum = state.spectrum,
        isRecording = readBoolParam(params, "/manifold/recording", false),
        recordMode = readParam(params, "/manifold/mode", "firstLoop"),
        layers = {},
    }

    for i, voice in ipairs(voices) do
        if type(voice) == "table" then
            normalized.layers[i] = {
                index = voice.id or (i - 1),
                state = voice.state or "empty",
                speed = voice.speed or 1,
                volume = voice.volume or 1,
                reversed = voice.reversed or false,
            }
        end
    end

    return normalized
end

local function releaseGLResources()
    if glState.depthRbo and glState.depthRbo ~= 0 then
        gl.deleteRenderbuffer(glState.depthRbo)
    end
    if glState.colorTex and glState.colorTex ~= 0 then
        gl.deleteTexture(glState.colorTex)
    end
    if glState.fbo and glState.fbo ~= 0 then
        gl.deleteFramebuffer(glState.fbo)
    end
    if glState.ibo and glState.ibo ~= 0 then
        gl.deleteBuffer(glState.ibo)
    end
    if glState.vbo and glState.vbo ~= 0 then
        gl.deleteBuffer(glState.vbo)
    end
    if glState.vao and glState.vao ~= 0 then
        gl.deleteVertexArray(glState.vao)
    end
    if glState.sceneProgram and glState.sceneProgram ~= 0 then
        gl.deleteProgram(glState.sceneProgram)
    end
    if glState.postProgram and glState.postProgram ~= 0 then
        gl.deleteProgram(glState.postProgram)
    end

    glState.sceneProgram = 0
    glState.postProgram = 0
    glState.vao = 0
    glState.vbo = 0
    glState.ibo = 0
    glState.fbo = 0
    glState.colorTex = 0
    glState.depthRbo = 0
    glState.fbWidth = 0
    glState.fbHeight = 0
    glState.scenePosLoc = -1
    glState.sceneUvLoc = -1
    glState.postPosLoc = -1
    glState.postUvLoc = -1
    glState.sceneTimeLoc = -1
    glState.sceneResolutionLoc = -1
    glState.postTimeLoc = -1
    glState.postResolutionLoc = -1
    glState.postInputTexLoc = -1
    glState.postIntensityLoc = -1
    glState.ready = false
end

local function compileShader(shaderType, source, label)
    local shader = gl.createShader(shaderType)
    if not shader or shader == 0 then
        return nil, "createShader failed for " .. label
    end

    gl.shaderSource(shader, source)
    gl.compileShader(shader)

    if not gl.getShaderCompileStatus(shader) then
        local log = gl.getShaderInfoLog(shader) or ""
        gl.deleteShader(shader)
        return nil, label .. " compile failed: " .. log
    end

    return shader, nil
end

local function createProgram(vertexSource, fragmentSource)
    local vs, vsErr = compileShader(GL.VERTEX_SHADER, vertexSource, "vertex shader")
    if not vs then
        return nil, vsErr
    end

    local fs, fsErr = compileShader(GL.FRAGMENT_SHADER, fragmentSource, "fragment shader")
    if not fs then
        gl.deleteShader(vs)
        return nil, fsErr
    end

    local program = gl.createProgram()
    if not program or program == 0 then
        gl.deleteShader(vs)
        gl.deleteShader(fs)
        return nil, "createProgram failed"
    end

    gl.attachShader(program, vs)
    gl.attachShader(program, fs)
    gl.linkProgram(program)

    if not gl.getProgramLinkStatus(program) then
        local log = gl.getProgramInfoLog(program) or ""
        gl.deleteShader(vs)
        gl.deleteShader(fs)
        gl.deleteProgram(program)
        return nil, "program link failed: " .. log
    end

    gl.detachShader(program, vs)
    gl.detachShader(program, fs)
    gl.deleteShader(vs)
    gl.deleteShader(fs)

    return program, nil
end

local function createOrResizeFramebuffer(width, height)
    width = math.max(2, math.floor(width))
    height = math.max(2, math.floor(height))

    if glState.fbo ~= 0 and glState.fbWidth == width and glState.fbHeight == height then
        return true
    end

    if glState.depthRbo ~= 0 then
        gl.deleteRenderbuffer(glState.depthRbo)
        glState.depthRbo = 0
    end
    if glState.colorTex ~= 0 then
        gl.deleteTexture(glState.colorTex)
        glState.colorTex = 0
    end
    if glState.fbo ~= 0 then
        gl.deleteFramebuffer(glState.fbo)
        glState.fbo = 0
    end

    local tex = gl.createTexture()
    local fbo = gl.createFramebuffer()
    local rbo = gl.createRenderbuffer()
    if tex == 0 or fbo == 0 or rbo == 0 then
        glState.lastError = "failed to allocate framebuffer resources"
        return false
    end

    gl.bindTexture(GL.TEXTURE_2D, tex)
    gl.texImage2DRGBA(GL.TEXTURE_2D, 0, width, height)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, GL.CLAMP_TO_EDGE)
    gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, GL.CLAMP_TO_EDGE)
    gl.bindTexture(GL.TEXTURE_2D, 0)

    gl.bindRenderbuffer(GL.RENDERBUFFER, rbo)
    gl.renderbufferStorage(GL.RENDERBUFFER, GL.DEPTH24_STENCIL8, width, height)
    gl.bindRenderbuffer(GL.RENDERBUFFER, 0)

    gl.bindFramebuffer(GL.FRAMEBUFFER, fbo)
    gl.framebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, tex, 0)
    gl.framebufferRenderbuffer(GL.FRAMEBUFFER, GL.DEPTH_STENCIL_ATTACHMENT, GL.RENDERBUFFER, rbo)
    gl.drawBuffers({ GL.COLOR_ATTACHMENT0 })

    local status = gl.checkFramebufferStatus(GL.FRAMEBUFFER)
    gl.bindFramebuffer(GL.FRAMEBUFFER, 0)

    if status ~= GL.FRAMEBUFFER_COMPLETE then
        gl.deleteRenderbuffer(rbo)
        gl.deleteTexture(tex)
        gl.deleteFramebuffer(fbo)
        glState.lastError = "framebuffer incomplete: " .. tostring(status)
        return false
    end

    glState.fbo = fbo
    glState.colorTex = tex
    glState.depthRbo = rbo
    glState.fbWidth = width
    glState.fbHeight = height

    return true
end

local function initGLResources()
    releaseGLResources()

    local vertexSource = [[
        attribute vec2 aPos;
        attribute vec2 aUv;
        varying vec2 vUv;

        void main()
        {
            vUv = aUv;
            gl_Position = vec4(aPos, 0.0, 1.0);
        }
    ]]

    local sceneFragmentSource = [[
        varying vec2 vUv;
        uniform float uTime;
        uniform vec2 uResolution;

        void main()
        {
            vec2 uv = vUv;
            vec2 centered = uv - vec2(0.5);
            float r = length(centered);
            float wave = sin((uv.x * 16.0) + (uTime * 1.8)) * 0.5 + 0.5;
            float ring = sin((r * 40.0) - (uTime * 3.2)) * 0.5 + 0.5;
            float flow = sin((uv.y * 12.0) + (uTime * 1.2)) * 0.5 + 0.5;

            vec3 base = vec3(0.05, 0.08, 0.14);
            vec3 hot = vec3(0.10 + 0.40 * wave, 0.20 + 0.60 * ring, 0.80 + 0.20 * flow);
            vec3 color = mix(base, hot, 0.80 * ring + 0.15 * wave);

            float vignette = smoothstep(0.95, 0.2, r);
            color *= vignette;

            gl_FragColor = vec4(color, 1.0);
        }
    ]]

    local postFragmentSource = [[
        varying vec2 vUv;
        uniform sampler2D uInputTex;
        uniform float uTime;
        uniform vec2 uResolution;
        uniform float uIntensity;

        void main()
        {
            vec2 uv = vUv;
            vec2 center = uv - vec2(0.5);
            float dist = length(center);

            float aberration = 0.0025 + 0.0035 * uIntensity;
            vec2 dir = normalize(center + vec2(1e-4));
            vec3 sampleR = texture2D(uInputTex, uv + dir * aberration).rgb;
            vec3 sampleG = texture2D(uInputTex, uv).rgb;
            vec3 sampleB = texture2D(uInputTex, uv - dir * aberration).rgb;
            vec3 color = vec3(sampleR.r, sampleG.g, sampleB.b);

            float scan = sin((uv.y * uResolution.y * 0.25) + (uTime * 8.0)) * 0.03;
            color *= (0.96 + scan);

            float vignette = smoothstep(0.95, 0.25, dist);
            color *= vignette;

            gl_FragColor = vec4(color, 1.0);
        }
    ]]

    local sceneProgram, sceneErr = createProgram(vertexSource, sceneFragmentSource)
    if not sceneProgram then
        glState.lastError = sceneErr
        return false
    end

    local postProgram, postErr = createProgram(vertexSource, postFragmentSource)
    if not postProgram then
        gl.deleteProgram(sceneProgram)
        glState.lastError = postErr
        return false
    end

    local vbo = gl.createBuffer()
    local ibo = gl.createBuffer()
    local vao = gl.createVertexArray()
    if not vbo or vbo == 0 or not ibo or ibo == 0 or not vao or vao == 0 then
        if vbo and vbo ~= 0 then gl.deleteBuffer(vbo) end
        if ibo and ibo ~= 0 then gl.deleteBuffer(ibo) end
        if vao and vao ~= 0 then gl.deleteVertexArray(vao) end
        gl.deleteProgram(sceneProgram)
        gl.deleteProgram(postProgram)
        glState.lastError = "createBuffer failed"
        return false
    end

    -- Full-screen quad: x, y, u, v
    local vertices = {
        -1.0, -1.0, 0.0, 0.0,
         1.0, -1.0, 1.0, 0.0,
         1.0,  1.0, 1.0, 1.0,
        -1.0,  1.0, 0.0, 1.0,
    }
    local indices = { 0, 1, 2, 0, 2, 3 }

    gl.bindVertexArray(vao)
    gl.bindBuffer(GL.ARRAY_BUFFER, vbo)
    gl.bufferDataFloat(GL.ARRAY_BUFFER, vertices, GL.STATIC_DRAW)
    gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, ibo)
    gl.bufferDataUInt16(GL.ELEMENT_ARRAY_BUFFER, indices, GL.STATIC_DRAW)

    local scenePosLoc = gl.getAttribLocation(sceneProgram, "aPos")
    local sceneUvLoc = gl.getAttribLocation(sceneProgram, "aUv")
    local postPosLoc = gl.getAttribLocation(postProgram, "aPos")
    local postUvLoc = gl.getAttribLocation(postProgram, "aUv")

    if scenePosLoc < 0 or sceneUvLoc < 0 or postPosLoc < 0 or postUvLoc < 0 then
        gl.bindVertexArray(0)
        gl.bindBuffer(GL.ARRAY_BUFFER, 0)
        gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, 0)
        gl.deleteBuffer(vbo)
        gl.deleteBuffer(ibo)
        gl.deleteVertexArray(vao)
        gl.deleteProgram(sceneProgram)
        gl.deleteProgram(postProgram)
        glState.lastError = "vertex attributes missing"
        return false
    end

    gl.enableVertexAttribArray(scenePosLoc)
    gl.vertexAttribPointer(scenePosLoc, 2, GL.FLOAT, false, 16, 0)
    gl.enableVertexAttribArray(sceneUvLoc)
    gl.vertexAttribPointer(sceneUvLoc, 2, GL.FLOAT, false, 16, 8)

    gl.enableVertexAttribArray(postPosLoc)
    gl.vertexAttribPointer(postPosLoc, 2, GL.FLOAT, false, 16, 0)
    gl.enableVertexAttribArray(postUvLoc)
    gl.vertexAttribPointer(postUvLoc, 2, GL.FLOAT, false, 16, 8)

    gl.bindVertexArray(0)
    gl.bindBuffer(GL.ARRAY_BUFFER, 0)
    gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, 0)

    glState.sceneProgram = sceneProgram
    glState.postProgram = postProgram
    glState.vao = vao
    glState.vbo = vbo
    glState.ibo = ibo
    glState.scenePosLoc = scenePosLoc
    glState.sceneUvLoc = sceneUvLoc
    glState.postPosLoc = postPosLoc
    glState.postUvLoc = postUvLoc
    glState.sceneTimeLoc = gl.getUniformLocation(sceneProgram, "uTime")
    glState.sceneResolutionLoc = gl.getUniformLocation(sceneProgram, "uResolution")
    glState.postTimeLoc = gl.getUniformLocation(postProgram, "uTime")
    glState.postResolutionLoc = gl.getUniformLocation(postProgram, "uResolution")
    glState.postInputTexLoc = gl.getUniformLocation(postProgram, "uInputTex")
    glState.postIntensityLoc = gl.getUniformLocation(postProgram, "uIntensity")
    glState.ready = true
    glState.lastError = nil

    if not createOrResizeFramebuffer(256, 256) then
        releaseGLResources()
        return false
    end

    return true
end

-- ============================================================================
-- Particle System
-- ============================================================================

local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

function ParticleSystem.new(maxParticles)
    local self = setmetatable({}, ParticleSystem)
    self.particles = {}
    self.maxParticles = maxParticles or 200
    return self
end

function ParticleSystem:emit(x, y, config)
    if #self.particles >= self.maxParticles then
        table.remove(self.particles, 1)
    end

    local angle = randomRange(0, math.pi * 2)
    local speed = randomRange(config.minSpeed or 50, config.maxSpeed or 200)

    table.insert(self.particles, {
        x = x,
        y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        life = 1.0,
        decay = randomRange(config.minDecay or 0.5, config.maxDecay or 2.0),
        size = randomRange(config.minSize or 2, config.maxSize or 8),
        hue = config.hue or randomRange(0, 1),
        hueShift = config.hueShift or 0.1,
        gravity = config.gravity or 0,
        friction = config.friction or 0.98,
    })
end

function ParticleSystem:update(dt)
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]

        -- Physics
        p.vy = p.vy + p.gravity * dt
        p.vx = p.vx * p.friction
        p.vy = p.vy * p.friction

        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- Life
        p.life = p.life - p.decay * dt
        p.hue = (p.hue + p.hueShift * dt) % 1.0

        if p.life <= 0 then
            table.remove(self.particles, i)
        end
    end
end

function ParticleSystem:draw()
    for _, p in ipairs(self.particles) do
        local r, g, b = hsvToRgb(p.hue, 0.8, 1.0)
        local alpha = math.floor(p.life * 200) << 24
        local color = alpha | (r << 16) | (g << 8) | b

        local size = p.size * p.life
        gfx.setColour(color)
        gfx.fillRoundedRect(math.floor(p.x - size/2), math.floor(p.y - size/2),
                           math.floor(size), math.floor(size), size/2)
    end
end

-- ============================================================================
-- Matrix Rain Widget (extends BaseWidget)
-- ============================================================================

local MatrixRainWidget = W.BaseWidget:extend()

function MatrixRainWidget.new(parent, name, config)
    local self = setmetatable(W.BaseWidget.new(parent, name, config), MatrixRainWidget)

    self._cols = config.cols or 40
    self._charSize = config.charSize or 14
    self._speed = config.speed or 1.0
    self._spawnRate = config.spawnRate or 0.05
    self._color = config.color or 0xff00ff00
    self._drops = {}
    self._chars = config.charset or "0123456789ABCDEF"

    -- Store editor meta first, then expose params
    self:_storeEditorMeta("MatrixRainWidget", {}, {})
    self:exposeParams({
        { path = "cols", label = "Columns", type = "number", min = 5, max = 100, step = 1, group = "Layout" },
        { path = "charSize", label = "Char Size", type = "number", min = 6, max = 32, step = 1, group = "Style" },
        { path = "speed", label = "Speed", type = "number", min = 0.1, max = 5.0, step = 0.1, group = "Animation" },
        { path = "spawnRate", label = "Spawn Rate", type = "number", min = 0.01, max = 0.5, step = 0.01, group = "Animation" },
        { path = "color", label = "Color", type = "color", group = "Style" },
    })

    return self
end

function MatrixRainWidget:update(dt)
    local scaledDt = dt * self._speed

    -- Spawn new drops
    for i = 1, self._cols do
        if math.random() < self._spawnRate and not self._drops[i] then
            self._drops[i] = {
                y = -self._charSize,
                speed = randomRange(50, 150),
                length = math.random(5, 15),
                chars = {}
            }
            for j = 1, self._drops[i].length do
                self._drops[i].chars[j] = self._chars:sub(math.random(1, #self._chars), 1)
            end
        end
    end

    -- Update drops
    for i, drop in pairs(self._drops) do
        drop.y = drop.y + drop.speed * scaledDt

        -- Update characters occasionally
        for j = 1, drop.length do
            if math.random() < 0.1 then
                drop.chars[j] = self._chars:sub(math.random(1, #self._chars), 1)
            end
        end

        -- Remove off-screen drops
        local h = self.node:getHeight()
        if drop.y > h + 50 then
            self._drops[i] = nil
        end
    end
end

function MatrixRainWidget:onDraw(w, h)
    local colWidth = w / self._cols

    -- Extract color components
    local baseColor = self._color or 0xff00ff00
    local baseR = (baseColor >> 16) & 0xff
    local baseG = (baseColor >> 8) & 0xff
    local baseB = baseColor & 0xff

    for i, drop in pairs(self._drops) do
        local colX = (i - 1) * colWidth + colWidth / 2

        for j = 1, drop.length do
            local charY = drop.y - (j - 1) * self._charSize
            if charY > -self._charSize and charY < h then
                local brightness = 1 - (j - 1) / drop.length
                local alpha = math.floor(brightness * 255)
                local r = math.floor(baseR * brightness)
                local g = math.floor(baseG * brightness)
                local b = math.floor(baseB * brightness)
                local color = (alpha << 24) | (r << 16) | (g << 8) | b

                gfx.setColour(color)
                gfx.setFont(self._charSize)
                gfx.drawText(drop.chars[j], math.floor(colX - self._charSize/2), math.floor(charY),
                           self._charSize, self._charSize, Justify.centred)
            end
        end
    end
end

-- Keep old MatrixRain class for second layer (or convert it too)
local MatrixRain = {}
MatrixRain.__index = MatrixRain

function MatrixRain.new(cols, charSize)
    local self = setmetatable({}, MatrixRain)
    self.cols = cols or 40
    self.charSize = charSize or 14
    self.drops = {}
    self.chars = "0123456789ABCDEF"
    return self
end

function MatrixRain:update(dt)
    -- Spawn new drops
    for i = 1, self.cols do
        if math.random() < 0.05 and not self.drops[i] then
            self.drops[i] = {
                y = -self.charSize,
                speed = randomRange(50, 150),
                length = math.random(5, 15),
                chars = {}
            }
            for j = 1, self.drops[i].length do
                self.drops[i].chars[j] = self.chars:sub(math.random(1, #self.chars), 1)
            end
        end
    end

    -- Update drops
    for i, drop in pairs(self.drops) do
        drop.y = drop.y + drop.speed * dt

        -- Update characters occasionally
        for j = 1, drop.length do
            if math.random() < 0.1 then
                drop.chars[j] = self.chars:sub(math.random(1, #self.chars), 1)
            end
        end

        -- Remove off-screen drops
        if drop.y > 800 then
            self.drops[i] = nil
        end
    end
end

function MatrixRain:draw(x, y, w, h)
    local colWidth = w / self.cols

    for i, drop in pairs(self.drops) do
        local colX = x + (i - 1) * colWidth + colWidth / 2

        for j = 1, drop.length do
            local charY = drop.y - (j - 1) * self.charSize
            if charY > y and charY < y + h then
                local brightness = 1 - (j - 1) / drop.length
                local alpha = math.floor(brightness * 255)
                local color = (alpha << 24) | (0 << 16) | (math.floor(brightness * 255) << 8) | 0

                gfx.setColour(color)
                gfx.setFont(self.charSize)
                gfx.drawText(drop.chars[j], math.floor(colX - self.charSize/2), math.floor(charY),
                           self.charSize, self.charSize, Justify.centred)
            end
        end
    end
end

-- ============================================================================
-- PostFXWidget - extends GLSLWidget with 2-pass pipeline
-- ============================================================================

local PostFXWidget = W.GLSLWidget:extend()

function PostFXWidget.new(parent, name, config)
    local self = setmetatable(W.GLSLWidget.new(parent, name, config), PostFXWidget)

    -- Exposed parameters with defaults
    self._intensity = config.intensity or 0.5
    self._aberration = config.aberration or 0.003
    self._scanlines = config.scanlines or 0.03
    self._waveSpeed = config.waveSpeed or 1.8
    self._ringSpeed = config.ringSpeed or 3.2

    -- Scene shader (procedural)
    self._sceneVertex = [[
        attribute vec2 aPos;
        attribute vec2 aUv;
        varying vec2 vUv;
        void main() {
            vUv = aUv;
            gl_Position = vec4(aPos, 0.0, 1.0);
        }
    ]]

    self._sceneFragment = [[
        varying vec2 vUv;
        uniform float uTime;
        uniform float uWaveSpeed;
        uniform float uRingSpeed;
        void main() {
            vec2 uv = vUv;
            vec2 centered = uv - vec2(0.5);
            float r = length(centered);
            float wave = sin((uv.x * 16.0) + (uTime * uWaveSpeed)) * 0.5 + 0.5;
            float ring = sin((r * 40.0) - (uTime * uRingSpeed)) * 0.5 + 0.5;
            float flow = sin((uv.y * 12.0) + (uTime * 1.2)) * 0.5 + 0.5;
            vec3 base = vec3(0.05, 0.08, 0.14);
            vec3 hot = vec3(0.10 + 0.40 * wave, 0.20 + 0.60 * ring, 0.80 + 0.20 * flow);
            vec3 color = mix(base, hot, 0.80 * ring + 0.15 * wave);
            float vignette = smoothstep(0.95, 0.2, r);
            color *= vignette;
            gl_FragColor = vec4(color, 1.0);
        }
    ]]

    -- Post shader (effects)
    self._postVertex = self._sceneVertex

    self._postFragment = [[
        varying vec2 vUv;
        uniform sampler2D uInputTex;
        uniform float uTime;
        uniform vec2 uResolution;
        uniform float uIntensity;
        uniform float uAberration;
        uniform float uScanlines;
        void main() {
            vec2 uv = vUv;
            vec2 center = uv - vec2(0.5);
            float dist = length(center);
            float aberration = uAberration + 0.0035 * uIntensity;
            vec2 dir = normalize(center + vec2(1e-4));
            vec3 sampleR = texture2D(uInputTex, uv + dir * aberration).rgb;
            vec3 sampleG = texture2D(uInputTex, uv).rgb;
            vec3 sampleB = texture2D(uInputTex, uv - dir * aberration).rgb;
            vec3 color = vec3(sampleR.r, sampleG.g, sampleB.b);
            float scan = sin((uv.y * uResolution.y * 0.25) + (uTime * 8.0)) * uScanlines;
            color *= (1.0 - uScanlines + scan);
            float vignette = smoothstep(0.95, 0.25, dist);
            color *= vignette;
            gl_FragColor = vec4(color, 1.0);
        }
    ]]

    -- Compile shaders
    local ok, err = self:setShaders(self._sceneVertex, self._sceneFragment)
    if not ok then
        print("PostFXWidget shader compile failed: " .. tostring(err))
    else
        print("PostFXWidget shaders compiled OK")
    end
    
    -- Store meta and expose params
    self:_storeEditorMeta("PostFXWidget", {}, {})
    self:exposeParams({
        { path = "intensity", label = "FX Intensity", type = "number", min = 0, max = 1, step = 0.01, group = "Post FX" },
        { path = "aberration", label = "Chromatic Aberration", type = "number", min = 0, max = 0.02, step = 0.001, group = "Post FX" },
        { path = "scanlines", label = "Scanlines", type = "number", min = 0, max = 0.1, step = 0.001, group = "Post FX" },
        { path = "waveSpeed", label = "Wave Speed", type = "number", min = 0, max = 5, step = 0.1, group = "Animation" },
        { path = "ringSpeed", label = "Ring Speed", type = "number", min = 0, max = 10, step = 0.1, group = "Animation" },
    })

    return self
end

function PostFXWidget:onDrawGL(w, h)
    local gl = _G.gl
    if not gl then return end

    -- Debug
    if not self._drawCount then self._drawCount = 0 end
    self._drawCount = self._drawCount + 1
    if self._drawCount % 60 == 0 then
        print(string.format("PostFXWidget.onDrawGL: program=%d fbo=%d tex=%d animTime=%.2f", self._program or 0, self._fbo or 0, self._colorTex or 0, self._animTime or -1))
    end

    -- Ensure geometry exists
    if self._vao == 0 then
        self:_createGeometry()
    end

    -- Ensure FBO exists and size matches
    if self._fbo == 0 or w ~= self._fbWidth or h ~= self._fbHeight then
        if not self:_createFramebuffer(w, h) then
            gl.clearColor(0.2, 0.05, 0.05, 1.0)
            gl.clear(GL.COLOR_BUFFER_BIT)
            return
        end
    end

    -- Ensure texture exists
    if self._colorTex == 0 or self._colorTex == nil then
        gl.clearColor(0.1, 0.1, 0.05, 1.0)
        gl.clear(GL.COLOR_BUFFER_BIT)
        return
    end

    -- Pass 1: Scene to FBO
    gl.bindFramebuffer(GL.FRAMEBUFFER, self._fbo)
    gl.viewport(0, 0, w, h)
    gl.enable(GL.DEPTH_TEST)
    gl.clearColor(0.02, 0.03, 0.06, 1.0)
    gl.clear(GL.COLOR_BUFFER_BIT + GL.DEPTH_BUFFER_BIT)

    -- Recompile if shaders changed (not implemented, would check dirty flag)
    if self._program == 0 then
        self:_compileShaders(self._sceneVertex, self._sceneFragment)
    end

    gl.useProgram(self._program)
    -- Set uniforms
    local timeLoc = gl.getUniformLocation(self._program, "uTime")
    local waveLoc = gl.getUniformLocation(self._program, "uWaveSpeed")
    local ringLoc = gl.getUniformLocation(self._program, "uRingSpeed")
    -- Debug: print uniform locations once
    if not self._debugPrinted then
        print("GLSLWidget uniforms: timeLoc=" .. tostring(timeLoc) .. " waveLoc=" .. tostring(waveLoc) .. " ringLoc=" .. tostring(ringLoc))
                self._debugPrinted = true
    end
    if timeLoc >= 0 then gl.uniform1f(timeLoc, self._animTime or 0) end
    if waveLoc >= 0 then gl.uniform1f(waveLoc, self._waveSpeed) end
    if ringLoc >= 0 then gl.uniform1f(ringLoc, self._ringSpeed) end

    gl.bindVertexArray(self._vao)
    gl.drawElements(GL.TRIANGLES, 6, GL.UNSIGNED_SHORT, 0)

    -- Pass 2: Post to screen
    gl.bindFramebuffer(GL.FRAMEBUFFER, 0)
    gl.viewport(0, 0, w, h)
    gl.disable(GL.DEPTH_TEST)
    gl.clearColor(0.01, 0.015, 0.03, 1.0)
    gl.clear(GL.COLOR_BUFFER_BIT)

    -- Compile post shader (simplified - reusing same program for now)
    -- In full implementation, store separate _postProgram
    gl.useProgram(self._program)
    gl.activeTexture(GL.TEXTURE0)
    gl.bindTexture(GL.TEXTURE_2D, self._colorTex)

    local texLoc = gl.getUniformLocation(self._program, "uInputTex")
    local resLoc = gl.getUniformLocation(self._program, "uResolution")
    local intLoc = gl.getUniformLocation(self._program, "uIntensity")
    local abeLoc = gl.getUniformLocation(self._program, "uAberration")
    local scanLoc = gl.getUniformLocation(self._program, "uScanlines")

    if texLoc >= 0 then gl.uniform1i(texLoc, 0) end
    if resLoc >= 0 then gl.uniform2f(resLoc, w, h) end
    if intLoc >= 0 then gl.uniform1f(intLoc, self._intensity) end
    if abeLoc >= 0 then gl.uniform1f(abeLoc, self._aberration) end
    if scanLoc >= 0 then gl.uniform1f(scanLoc, self._scanlines) end

    gl.drawElements(GL.TRIANGLES, 6, GL.UNSIGNED_SHORT, 0)
    gl.bindVertexArray(0)
    gl.useProgram(0)
    gl.bindTexture(GL.TEXTURE_2D, 0)
end

function PostFXWidget:setAnimTime(t)
    self._animTime = t
end

-- ============================================================================
-- Kaleidoscope Effect
-- ============================================================================

local function drawKaleidoscopeSegment(cx, cy, radius, angle, segments, time)
    local segmentAngle = (math.pi * 2) / segments

    for i = 0, segments - 1 do
        local a1 = angle + i * segmentAngle
        local a2 = angle + (i + 1) * segmentAngle

        local hue = (time * 0.1 + i / segments) % 1.0
        local r, g, b = hsvToRgb(hue, 0.8, 1.0)
        local color = (255 << 24) | (r << 16) | (g << 8) | b

        gfx.setColour(color)

        -- Draw a curved segment
        local steps = 20
        for j = 0, steps - 1 do
            local t1 = j / steps
            local t2 = (j + 1) / steps

            local wave1 = math.sin(a1 * 3 + time * 2) * 0.3 + 0.7
            local wave2 = math.sin(a2 * 3 + time * 2) * 0.3 + 0.7

            local r1 = radius * wave1 * (0.5 + t1 * 0.5)
            local r2 = radius * wave2 * (0.5 + t2 * 0.5)

            local x1 = cx + math.cos(a1) * r1
            local y1 = cy + math.sin(a1) * r1
            local x2 = cx + math.cos(a2) * r2
            local y2 = cy + math.sin(a2) * r2

            if j == 0 then
                gfx.fillRoundedRect(math.floor(x1 - 2), math.floor(y1 - 2), 4, 4, 2)
            end
        end
    end
end

-- ============================================================================
-- Perlin Noise Field (simplified)
-- ============================================================================

local function noise(x, y, z)
    return math.sin(x * 12.9898 + y * 78.233 + z) * 43758.5453 % 1
end

local function drawNoiseField(x, y, w, h, time, scale)
    local cols = 10
    local rows = 8
    local cellW = w / cols
    local cellH = h / rows

    -- Background
    gfx.setColour(0x051015)
    gfx.fillRect(x, y, w, h)

    for i = 0, cols - 1 do
        for j = 0, rows - 1 do
            local nx = i * scale + time * 0.5
            local ny = j * scale + time * 0.3
            local n = noise(nx, ny, time * 0.1)

            local angle = n * math.pi * 4
            local cx = x + i * cellW + cellW / 2
            local cy = y + j * cellH + cellH / 2

            local len = math.min(cellW, cellH) * 0.35
            local x2 = cx + math.cos(angle) * len
            local y2 = cy + math.sin(angle) * len

            local hue = (n + time * 0.05) % 1
            local r, g, b = hsvToRgb(hue, 0.8, 1.0)
            local color = (240 << 24) | (r << 16) | (g << 8) | b

            gfx.setColour(color)
            gfx.drawLine(math.floor(cx), math.floor(cy), math.floor(x2), math.floor(y2), 2)

            -- Draw dot at center
            gfx.setColour(0xffffffff)
            gfx.fillRoundedRect(math.floor(cx - 1), math.floor(cy - 1), 3, 3, 1.5)
        end
    end
end

-- ============================================================================
-- XY Pad with Trails
-- ============================================================================

local XYPad = {}
XYPad.__index = XYPad

function XYPad.new(parent, name, config)
    local self = setmetatable({}, XYPad)

    self.node = parent:addChild(name)
    self.name = name
    self.config = config or {}

    self._x = config.x or 0.5
    self._y = config.y or 0.5
    self._dragging = false
    self._trails = {}
    self._maxTrails = 50
    self._onChange = config.on_change or config.onChange

    -- Bind callbacks
    self.node:setOnMouseDown(function(mx, my)
        self._dragging = true
        self:updateFromMouse(mx, my)
    end)

    self.node:setOnMouseDrag(function(mx, my, dx, dy)
        if self._dragging then
            self:updateFromMouse(mx, my)
        end
    end)

    self.node:setOnMouseUp(function(mx, my)
        self._dragging = false
    end)

    self.node:setOnDraw(function(node)
        self:onDraw(node:getWidth(), node:getHeight())
    end)

    return self
end

function XYPad:updateFromMouse(mx, my)
    local w = self.node:getWidth()
    local h = self.node:getHeight()

    self._x = clamp((mx - 20) / (w - 40), 0, 1)
    self._y = clamp((my - 20) / (h - 40), 0, 1)

    -- Add to trails
    table.insert(self._trails, 1, {x = self._x, y = self._y, life = 1.0})
    if #self._trails > self._maxTrails then
        table.remove(self._trails)
    end

    if self._onChange then
        self._onChange(self._x, self._y)
    end
end

function XYPad:updateTrails(dt)
    for i = #self._trails, 1, -1 do
        local trail = self._trails[i]
        trail.life = trail.life - dt * 2
        if trail.life <= 0 then
            table.remove(self._trails, i)
        end
    end
end

function XYPad:onDraw(w, h)
    local drawW = w - 40
    local drawH = h - 40

    -- Background grid
    gfx.setColour(0x1a1f2e)
    gfx.fillRoundedRect(20, 20, drawW, drawH, 8)

    -- Grid lines
    gfx.setColour(0x30354a)
    for i = 1, 4 do
        local x = 20 + (drawW / 5) * i
        local y = 20 + (drawH / 5) * i
        gfx.drawVerticalLine(math.floor(x), 20, drawH)
        gfx.drawHorizontalLine(math.floor(y), 20, drawW)
    end

    -- Crosshair center
    local cx = 20 + drawW / 2
    local cy = 20 + drawH / 2
    gfx.setColour(0x50556a)
    gfx.drawVerticalLine(math.floor(cx), 20, drawH)
    gfx.drawHorizontalLine(math.floor(cy), 20, drawW)

    -- Trails
    for i, trail in ipairs(self._trails) do
        local tx = 20 + trail.x * drawW
        local ty = 20 + trail.y * drawH
        local size = 4 + (1 - i / #self._trails) * 8
        local alpha = math.floor(trail.life * 150)

        local hue = i / #self._trails
        local r, g, b = hsvToRgb(hue, 0.9, 1.0)
        local color = (alpha << 24) | (r << 16) | (g << 8) | b

        gfx.setColour(color)
        gfx.fillRoundedRect(math.floor(tx - size/2), math.floor(ty - size/2),
                           math.floor(size), math.floor(size), size/2)
    end

    -- Current position
    local px = 20 + self._x * drawW
    local py = 20 + self._y * drawH

    -- Glow
    for i = 3, 1, -1 do
        local glowSize = 8 + i * 4
        local alpha = 50 - i * 15
        gfx.setColour((alpha << 24) | (0xff << 16) | (0x44 << 8) | 0x00)
        gfx.fillRoundedRect(math.floor(px - glowSize/2), math.floor(py - glowSize/2),
                           math.floor(glowSize), math.floor(glowSize), glowSize/2)
    end

    -- Handle
    gfx.setColour(0xffff8800)
    gfx.fillRoundedRect(math.floor(px - 6), math.floor(py - 6), 12, 12, 6)
    gfx.setColour(0xffffffff)
    gfx.fillRoundedRect(math.floor(px - 3), math.floor(py - 3), 6, 6, 3)

    -- Coordinates label
    gfx.setColour(0xffffffff)
    gfx.setFont(11.0)
    local label = string.format("X: %.2f  Y: %.2f", self._x, self._y)
    gfx.drawText(label, 20, h - 18, drawW, 16, Justify.centred)
end

function XYPad:getValues()
    return self._x, self._y
end

-- ============================================================================
-- Animated Equalizer
-- ============================================================================

local function updateEQBars(dt)
    for i = 1, spectrumBands do
        if not eqBars[i] then
            eqBars[i] = {height = 0.1, target = 0.5, velocity = 0}
        end

        -- Generate fake audio data based on time and layer states
        local baseFreq = i / spectrumBands
        local timeFactor = animTime * 8 + i * 0.3

        -- Multiple sine waves for more interesting movement
        local target = math.abs(math.sin(timeFactor) * 0.5 + math.sin(timeFactor * 2.3) * 0.3 + math.sin(timeFactor * 0.7) * 0.2)

        -- Add some layer influence if available
        if type(current_state.layers) == "table" then
            for _, layer in ipairs(current_state.layers) do
                if layer.state == "playing" then
                    target = target + 0.3
                    break
                end
            end
        end

        target = clamp(target, 0.05, 0.95)

        -- Spring physics - faster response
        local k = 15  -- spring constant
        local d = 0.6  -- damping
        local force = (target - eqBars[i].height) * k
        eqBars[i].velocity = eqBars[i].velocity + force * dt
        eqBars[i].velocity = eqBars[i].velocity * d
        eqBars[i].height = eqBars[i].height + eqBars[i].velocity * dt
        eqBars[i].height = clamp(eqBars[i].height, 0, 1)
    end
end

local function drawEQVisualizer(x, y, w, h)
    local gap = 1
    local barW = math.floor((w - (spectrumBands - 1) * gap) / spectrumBands)
    local maxBarH = h - 5

    -- Background
    gfx.setColour(0x051015)
    gfx.fillRect(x, y, w, h)

    for i = 1, spectrumBands do
        local bar = eqBars[i]
        if not bar then bar = {height = 0} end

        local barH = math.floor(bar.height * maxBarH)

        local bx = x + (i - 1) * (barW + gap)
        local by = y + maxBarH - barH

        -- Always draw something, even if small
        if barH < 2 then
            barH = 2
            by = y + maxBarH - 2
        end

        -- Color based on height: blue (low) -> green -> yellow -> red (high)
        local hue = 0.66 - (bar.height * 0.66)  -- 0.66 (blue) to 0 (red)
        local r, g, b = hsvToRgb(hue, 0.8, 1.0)
        local color = (240 << 24) | (r << 16) | (g << 8) | b

        gfx.setColour(color)
        gfx.fillRect(bx, by, barW, barH)
    end
end

-- ============================================================================
-- Waveform Circular Visualizer
-- ============================================================================

local function drawCircularWaveform(cx, cy, radius, time)
    local points = 60

    -- Background
    gfx.setColour(0x051015)
    gfx.fillRoundedRect(math.floor(cx - radius), math.floor(cy - radius), math.floor(radius * 2), math.floor(radius * 2), radius)

    -- Draw outer ring
    for i = 0, points - 1 do
        local angle1 = (i / points) * math.pi * 2
        local angle2 = ((i + 1) / points) * math.pi * 2

        -- Get audio data
        local audioSample = 0
        if current_state and type(current_state.layers) == "table" then
            for _, layer in ipairs(current_state.layers) do
                if layer.state == "playing" then
                    local phase = time * 5 + angle1 * 3
                    audioSample = audioSample + math.sin(phase) * 0.4
                end
            end
        end

        -- Fallback animation if no audio
        if audioSample == 0 then
            audioSample = math.sin(angle1 * 6 + time * 3) * 0.2
        end

        local r = radius * (0.8 + audioSample * 0.3)

        local x1 = cx + math.cos(angle1) * r
        local y1 = cy + math.sin(angle1) * r
        local x2 = cx + math.cos(angle2) * r
        local y2 = cy + math.sin(angle2) * r

        local hue = (i / points + time * 0.1) % 1
        local rC, gC, bC = hsvToRgb(hue, 0.9, 1.0)
        local color = (220 << 24) | (rC << 16) | (gC << 8) | bC

        gfx.setColour(color)
        gfx.drawLine(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), 3)
    end

    -- Center dot
    gfx.setColour(0xffffffff)
    gfx.fillRoundedRect(math.floor(cx - 4), math.floor(cy - 4), 8, 8, 4)
end

-- ============================================================================
-- UI Initialization
-- ============================================================================

function ui_init(root)
    -- Initialize particle systems
    ui.particles1 = ParticleSystem.new(150)  -- Main particle system
    ui.particles2 = ParticleSystem.new(80)   -- Secondary effect

    -- Root panel
    ui.rootPanel = W.Panel.new(root, "rootPanel", {
        bg = 0xff0a0f1a,
    })

    -- ==========================================================================
    -- Header
    -- ==========================================================================
    ui.headerPanel = W.Panel.new(ui.rootPanel.node, "header", {
        bg = 0x80111827,
        border = 0xff38bdf8,
        borderWidth = 1,
    })

    -- Register OSC endpoint for XY pad (appears in OSCQuery)
    -- This needs to happen early so we can show status in header
    if osc and osc.registerEndpoint then
        osc.registerEndpoint("/experimental/xy", {
            type = "ff",  -- two floats
            range = {0, 1},  -- both values 0-1
            access = 3,  -- read-write
            description = "XY Pad control (x, y)"
        })
        oscEnabled = true
    end

    ui.titleLabel = W.Label.new(ui.headerPanel.node, "title", {
        text = "◢ EXPERIMENTAL ◣",
        colour = 0xff22d3ee,
        fontSize = 20.0,
        fontStyle = FontStyle.bold,
    })

    ui.subtitleLabel = W.Label.new(ui.headerPanel.node, "subtitle", {
        text = "Visual Playground",
        colour = 0xff94a3b8,
        fontSize = 11.0,
    })

    -- OSC status indicator
    local oscStatus = "OSC: disabled"
    if oscEnabled then
        oscStatus = "OSC: /experimental/xy"
    end
    ui.oscLabel = W.Label.new(ui.headerPanel.node, "oscLabel", {
        text = oscStatus,
        colour = oscEnabled and 0xff22c55e or 0xff64748b,
        fontSize = 10.0,
    })

    -- ==========================================================================
    -- Left Panel: Particle System Emitter
    -- ==========================================================================
    ui.particlePanel = W.Panel.new(ui.rootPanel.node, "particlePanel", {
        bg = 0x151a2a,
        border = 0xff334155,
        borderWidth = 1,
        radius = 8,
    })

    -- Particle emitter using XYPadWidget base
    ui.particlePad = W.XYPadWidget.new(ui.particlePanel.node, "particlePad", {
        x = 0.5, y = 0.5,
        showTrails = false,
        handleColour = 0x00000000,  -- invisible handle
    })

    -- Expose particle emission parameters
    ui.particlePad:exposeParams({
        { path = "minSpeed", label = "Min Speed", type = "number", min = 10, max = 500, step = 10, group = "Particles" },
        { path = "maxSpeed", label = "Max Speed", type = "number", min = 10, max = 1000, step = 10, group = "Particles" },
        { path = "minSize", label = "Min Size", type = "number", min = 1, max = 20, step = 1, group = "Particles" },
        { path = "maxSize", label = "Max Size", type = "number", min = 1, max = 50, step = 1, group = "Particles" },
        { path = "hue", label = "Hue", type = "number", min = 0, max = 1, step = 0.01, group = "Particles" },
        { path = "hueShift", label = "Hue Shift", type = "number", min = 0, max = 1, step = 0.01, group = "Particles" },
        { path = "gravity", label = "Gravity", type = "number", min = -200, max = 500, step = 10, group = "Particles" },
    })

    -- Set default values
    ui.particlePad._minSpeed = 80
    ui.particlePad._maxSpeed = 250
    ui.particlePad._minSize = 2
    ui.particlePad._maxSize = 10
    ui.particlePad._hue = 0.0
    ui.particlePad._hueShift = 0.3
    ui.particlePad._gravity = 50

    -- Custom drawing for particle pad (no handle, just particles)
    ui.particlePad.node:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()

        -- Background
        gfx.setColour(0x101520)
        gfx.fillRoundedRect(0, 0, w, h, 6)

        -- Draw particles
        ui.particles1:draw()

        -- Instructions
        gfx.setColour(0x6094a3b8)
        gfx.setFont(10.0)
        gfx.drawText("Click & drag to emit particles", 0, h - 20, w, 16, Justify.centred)

        -- Particle count
        gfx.setColour(0xffffffff)
        gfx.setFont(9.0)
        gfx.drawText("Particles: " .. #ui.particles1.particles, 8, 8, 100, 14, Justify.centredLeft)
    end)

    -- Particle emission on drag (update position AND emit)
    ui.particlePad.node:setOnMouseDrag(function(mx, my, dx, dy)
        local w = ui.particlePad.node:getWidth()
        local h = ui.particlePad.node:getHeight()
        local margin = 20
        -- Update widget position
        ui.particlePad._x = math.max(0, math.min(1, (mx - margin) / (w - margin * 2)))
        ui.particlePad._y = math.max(0, math.min(1, (my - margin) / (h - margin * 2)))
        -- Emit particles using exposed params
        ui.particles1:emit(mx, my, {
            minSpeed = ui.particlePad._minSpeed or 80,
            maxSpeed = ui.particlePad._maxSpeed or 250,
            minSize = ui.particlePad._minSize or 2,
            maxSize = ui.particlePad._maxSize or 10,
            hue = (ui.particlePad._hue or 0) + animTime * 0.1 % 1,
            hueShift = ui.particlePad._hueShift or 0.5,
            gravity = ui.particlePad._gravity or 50
        })
    end)

    ui.particlePad.node:setOnMouseDown(function(mx, my)
        local w = ui.particlePad.node:getWidth()
        local h = ui.particlePad.node:getHeight()
        local margin = 20
        -- Update widget position
        ui.particlePad._x = math.max(0, math.min(1, (mx - margin) / (w - margin * 2)))
        ui.particlePad._y = math.max(0, math.min(1, (my - margin) / (h - margin * 2)))
        -- Emit particles using exposed params
        ui.particles1:emit(mx, my, {
            minSpeed = ui.particlePad._minSpeed or 80,
            maxSpeed = ui.particlePad._maxSpeed or 250,
            minSize = ui.particlePad._minSize or 2,
            maxSize = ui.particlePad._maxSize or 10,
            hue = ui.particlePad._hue or 0.0,
            hueShift = ui.particlePad._hueShift or 0.3,
            gravity = ui.particlePad._gravity or 50
        })
    end)

    -- ==========================================================================
    -- Middle Panel: XY Pad
    -- ==========================================================================
    ui.xyPanel = W.Panel.new(ui.rootPanel.node, "xyPanel", {
        bg = 0x151a2a,
        border = 0xff334155,
        borderWidth = 1,
        radius = 8,
    })

    ui.xyLabel = W.Label.new(ui.xyPanel.node, "xyLabel", {
        text = "XY Pad (Control Space)",
        colour = 0xffa78bfa,
        fontSize = 12.0,
    })

    ui.xySentLabel = W.Label.new(ui.xyPanel.node, "xySentLabel", {
        text = "TX 0 - " .. oscLastSent,
        colour = 0xff22c55e,
        fontSize = 10.0,
    })

    ui.xyRecvLabel = W.Label.new(ui.xyPanel.node, "xyRecvLabel", {
        text = "RX 0 - " .. oscLastRecv,
        colour = 0xfff59e0b,
        fontSize = 10.0,
    })

    ui.xyPad = W.XYPadWithTrails.new(ui.xyPanel.node, "xyPad", {
        x = 0.5, y = 0.5,
        on_change = function(x, y)
            -- Send OSC when XY pad changes
            if osc.send then
                local path = ui.xyPad._oscPath or "/experimental/xy"
                local minV = ui.xyPad._minValue or 0
                local maxV = ui.xyPad._maxValue or 1
                local sx = minV + x * (maxV - minV)
                local sy = minV + y * (maxV - minV)
                osc.send(path, sx, sy)
                oscSentCount = oscSentCount + 1
                oscLastSent = string.format("x=%.2f y=%.2f", sx, sy)
                local now = getTime and getTime() or 0
                if now - oscLastTxLogTime > 0.1 then
                    print("[OSC TX]" .. path, oscLastSent)
                    oscLastTxLogTime = now
                end
            end
        end,
    })

    -- Expose OSC parameters
    ui.xyPad:exposeParams({
        { path = "oscPath", label = "OSC Path", type = "text", group = "OSC" },
        { path = "minValue", label = "Min Value", type = "number", min = -1000, max = 1000, step = 0.1, group = "OSC" },
        { path = "maxValue", label = "Max Value", type = "number", min = -1000, max = 1000, step = 0.1, group = "OSC" },
        { path = "deadZone", label = "Dead Zone", type = "number", min = 0, max = 0.5, step = 0.01, group = "OSC" },
    })

    -- Set defaults
    ui.xyPad._oscPath = "/experimental/xy"
    ui.xyPad._minValue = 0
    ui.xyPad._maxValue = 1
    ui.xyPad._deadZone = 0

    -- Receive OSC to update XY pad position
    local oscPath = ui.xyPad._oscPath or "/experimental/xy"
    if osc and osc.removeHandler then
        osc.removeHandler(oscPath)
    end
    if osc.onMessage then
        osc.onMessage(oscPath, function(args)
            if args and #args >= 2 then
                local x = tonumber(args[1]) or 0.5
                local y = tonumber(args[2]) or 0.5
                -- Update XY pad without triggering on_change (to avoid feedback loop)
                if ui.xyPad then
                    ui.xyPad:setValues(x, y)
                end
                oscRecvCount = oscRecvCount + 1
                oscLastRecv = string.format("x=%.2f y=%.2f", x, y)
                local now = getTime and getTime() or 0
                if now - oscLastRxLogTime > 0.1 then
                    print("[OSC RX] /experimental/xy", oscLastRecv)
                    oscLastRxLogTime = now
                end
            end
        end)  -- non-persistent: avoid duplicate handlers on script switches
    end

    -- Register looper event listeners for testing
    if looper and looper.onTempoChanged then
        looper.onTempoChanged(function(bpm)
            print("[OSC Test] Tempo changed to:", bpm)
        end)
    end

    if looper and looper.onLayerStateChanged then
        looper.onLayerStateChanged(function(layer, state)
            print("[OSC Test] Layer", layer, "state:", state)
        end)
    end

    -- ==========================================================================
    -- Right Panel: Matrix Rain Widget
    -- ==========================================================================
    ui.matrixRain = MatrixRainWidget.new(ui.rootPanel.node, "matrixRain", {
        cols = 30, charSize = 12, speed = 1.0, spawnRate = 0.05, color = 0xff00ff00,
    })

    -- ==========================================================================
    -- Bottom Panel: Audio Visualizers
    -- ==========================================================================

    -- EQ Panel
    ui.eqPanel = W.Panel.new(ui.rootPanel.node, "eqPanel", {
        bg = 0x0a0f1a,
        border = 0xff475569,
        borderWidth = 1,
        radius = 8,
    })

    ui.eqCanvas = ui.eqPanel.node:addChild("eqCanvas")
    ui.eqCanvas:setInterceptsMouse(false, false)
    ui.eqCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        drawEQVisualizer(0, 0, w, h)
    end)

    -- Waveform panel
    ui.wavePanel = W.Panel.new(ui.rootPanel.node, "wavePanel", {
        bg = 0x0a0f1a,
        border = 0xff475569,
        borderWidth = 1,
        radius = 8,
    })

    ui.waveCanvas = ui.wavePanel.node:addChild("waveCanvas")
    ui.waveCanvas:setInterceptsMouse(false, false)
    ui.waveCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        local cx = w / 2
        local cy = h / 2
        local radius = math.min(w, h) * 0.4

        drawCircularWaveform(cx, cy, radius, animTime)
    end)

    -- ==========================================================================
    -- Noise Field Panel
    -- ==========================================================================
    ui.noisePanel = W.Panel.new(ui.rootPanel.node, "noisePanel", {
        bg = 0x101520,
        border = 0xff475569,
        borderWidth = 1,
        radius = 8,
    })

    ui.noiseLabel = W.Label.new(ui.noisePanel.node, "noiseLabel", {
        text = "Vector Field",
        colour = 0xfff59e0b,
        fontSize = 12.0,
    })

    ui.noiseCanvas = ui.noisePanel.node:addChild("noiseCanvas")
    ui.noiseCanvas:setInterceptsMouse(false, false)
    ui.noiseCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        drawNoiseField(5, 5, w - 10, h - 10, animTime, 0.2)
    end)

    -- ==========================================================================
    -- Kaleidoscope Panel
    -- ==========================================================================
    ui.kaleidoPanel = W.Panel.new(ui.rootPanel.node, "kaleidoPanel", {
        bg = 0x0a0a15,
        border = 0xffec4899,
        borderWidth = 1,
        radius = 8,
    })

    ui.kaleidoLabel = W.Label.new(ui.kaleidoPanel.node, "kaleidoLabel", {
        text = "Kaleidoscope",
        colour = 0xffec4899,
        fontSize = 12.0,
    })

    ui.kaleidoCanvas = ui.kaleidoPanel.node:addChild("kaleidoCanvas")
    ui.kaleidoCanvas:setInterceptsMouse(false, false)
    ui.kaleidoCanvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        local cx = w / 2
        local cy = h / 2
        local radius = math.min(w, h) * 0.4

        drawKaleidoscopeSegment(cx, cy, radius, kaleidoscopeAngle + animTime, 8, animTime)
    end)

    -- ==========================================================================
    -- OpenGL PostFX Widget Panel
    -- ==========================================================================
    ui.glPanel = W.Panel.new(ui.rootPanel.node, "glPanel", {
        bg = 0x0a0a15,
        border = 0xff00ffff,
        borderWidth = 2,
        radius = 8,
    })

    ui.glLabel = W.Label.new(ui.glPanel.node, "glLabel", {
        text = "OpenGL Pipeline (PostFXWidget)",
        colour = 0xff00ffff,
        fontSize = 12.0,
    })

    ui.glStatusLabel = W.Label.new(ui.glPanel.node, "glStatusLabel", {
        text = "GLSL Widget",
        colour = 0xff94a3b8,
        fontSize = 10.0,
    })

    -- PostFXWidget extends GLSLWidget
    ui.glWidget = PostFXWidget.new(ui.glPanel.node, "glWidget", {
        intensity = 0.5,
        aberration = 0.003,
        scanlines = 0.03,
        waveSpeed = 1.8,
        ringSpeed = 3.2,
    })

    -- ==========================================================================
    -- Layer Status (Minimal)
    -- ==========================================================================
    ui.statusPanel = W.Panel.new(ui.rootPanel.node, "statusPanel", {
        bg = 0x80111827,
        border = 0xff374151,
        borderWidth = 1,
    })

    ui.layerIndicators = {}
    for i = 1, MAX_LAYERS do
        ui.layerIndicators[i] = W.Panel.new(ui.statusPanel.node, "layer" .. i, {
            bg = 0xff1e293b,
            border = 0xff475569,
            borderWidth = 1,
            radius = 4,
        })

        W.Label.new(ui.layerIndicators[i].node, "label" .. i, {
            text = "L" .. i,
            colour = 0xff94a3b8,
            fontSize = 10.0,
        })
    end

    -- Start animation timer
    lastFrameTime = getTime()
end

-- ============================================================================
-- Layout
-- ============================================================================

function ui_resized(w, h)
    local margin = 12
    local panelH = h - 120
    local bottomH = 140

    -- Header
    ui.rootPanel:setBounds(0, 0, w, h)
    ui.headerPanel:setBounds(margin, margin, math.floor(w - margin * 2), 40)
    ui.titleLabel:setBounds(12, 0, 200, 40)
    ui.subtitleLabel:setBounds(220, 0, 150, 40)
    ui.oscLabel:setBounds(380, 0, math.floor(w - margin * 2 - 392), 40)

    -- Three main panels in a row
    local panelW = math.floor((w - margin * 4) / 3)
    local topY = margin + 40 + margin
    local mainH = math.floor(panelH - bottomH - margin * 2)

    -- Left: Particle emitter
    ui.particlePanel:setBounds(margin, topY, panelW, mainH)
    ui.particlePad.node:setBounds(8, 8, math.floor(panelW - 16), math.floor(mainH - 16))

    -- Middle: XY Pad
    ui.xyPanel:setBounds(math.floor(margin * 2 + panelW), topY, panelW, mainH)
    ui.xyLabel:setBounds(8, 8, math.floor(panelW - 16), 20)
    ui.xySentLabel:setBounds(8, 28, math.floor(panelW - 16), 16)
    ui.xyRecvLabel:setBounds(8, 44, math.floor(panelW - 16), 16)
    ui.xyPad.node:setBounds(8, 64, math.floor(panelW - 16), math.floor(mainH - 72))

    -- Right: Matrix Rain
    ui.matrixRain:setBounds(math.floor(margin * 3 + panelW * 2), topY, panelW, mainH)

    -- Bottom row - 5 equal sections
    local bottomY = topY + mainH + margin
    local sectionW = math.floor((w - margin * 6) / 5)

    -- EQ Visualizer
    ui.eqPanel:setBounds(margin, bottomY, sectionW, bottomH)
    ui.eqCanvas:setBounds(8, 8, sectionW - 16, bottomH - 16)

    -- Waveform
    ui.wavePanel:setBounds(math.floor(margin * 2 + sectionW), bottomY, sectionW, bottomH)
    ui.waveCanvas:setBounds(8, 8, sectionW - 16, bottomH - 16)

    -- Noise field
    ui.noisePanel:setBounds(math.floor(margin * 3 + sectionW * 2), bottomY, sectionW, bottomH)
    ui.noiseLabel:setBounds(8, 4, sectionW - 16, 18)
    ui.noiseCanvas:setBounds(8, 24, sectionW - 16, bottomH - 28)

    -- Kaleidoscope
    ui.kaleidoPanel:setBounds(math.floor(margin * 4 + sectionW * 3), bottomY, sectionW, bottomH)
    ui.kaleidoLabel:setBounds(8, 4, sectionW - 16, 18)
    ui.kaleidoCanvas:setBounds(8, 24, sectionW - 16, bottomH - 28)

    -- OpenGL 3D Cube
    ui.glPanel:setBounds(math.floor(margin * 5 + sectionW * 4), bottomY, sectionW, bottomH)
    ui.glLabel:setBounds(8, 4, sectionW - 16, 18)
    ui.glStatusLabel:setBounds(8, 20, sectionW - 16, 14)
    ui.glWidget:setBounds(8, 36, sectionW - 16, bottomH - 40)

    -- Status bar at bottom
    ui.statusPanel:setBounds(margin, h - 35, math.floor(w - margin * 2), 25)
    local indicatorW = math.floor((w - margin * 2 - 16) / MAX_LAYERS)
    for i = 1, MAX_LAYERS do
        ui.layerIndicators[i]:setBounds(math.floor(8 + (i - 1) * (indicatorW + 4)), 4, indicatorW, 17)
    end
end

-- ============================================================================
-- Animation Update
-- ============================================================================

function ui_update(state)
    current_state = normalizeState(state)
    local viewState = current_state

    local now = getTime()
    local dt = now - lastFrameTime
    lastFrameTime = now

    animTime = animTime + dt

    -- Update particle systems
    ui.particles1:update(dt)
    ui.particles2:update(dt)

    -- Update XY pad trails
    ui.xyPad:updateTrails(dt)

    -- Update matrix rain
    ui.matrixRain:update(dt)

    -- Update EQ with real spectrum data
    if viewState.spectrum then
        for i = 1, spectrumBands do
            if not eqBars[i] then
                eqBars[i] = {height = 0, velocity = 0}
            end
            local target = viewState.spectrum[i] or 0
            -- Fast attack, slow decay
            if target > eqBars[i].height then
                eqBars[i].height = eqBars[i].height + (target - eqBars[i].height) * 0.3
            else
                eqBars[i].height = eqBars[i].height + (target - eqBars[i].height) * 0.1
            end
        end
    end

    -- Update kaleidoscope
    kaleidoscopeAngle = kaleidoscopeAngle + dt * 0.5

    if ui.xySentLabel then
        ui.xySentLabel:setText("TX " .. tostring(oscSentCount) .. " - " .. oscLastSent)
    end
    if ui.xyRecvLabel then
        ui.xyRecvLabel:setText("RX " .. tostring(oscRecvCount) .. " - " .. oscLastRecv)
    end

    -- Update noise offset
    noiseOffset = noiseOffset + dt * 0.1

    -- Emit ambient particles occasionally
    if math.random() < 0.1 then
        local w = ui.particlePad.node:getWidth()
        local h = ui.particlePad.node:getHeight()
        ui.particles2:emit(w/2 + randomRange(-50, 50), h/2 + randomRange(-50, 50), {
            minSpeed = 20, maxSpeed = 60,
            minSize = 1, maxSize = 4,
            hue = animTime * 0.05 % 1,
            hueShift = 0.2,
            gravity = -10  -- Float up
        })
    end

    -- Update layer indicator colors
    if viewState.layers then
        for i = 1, MAX_LAYERS do
            local layer = viewState.layers[i]
            if layer then
                local color = 0xff1e293b
                if layer.state == "playing" then
                    color = 0xff22c55e
                elseif layer.state == "recording" then
                    color = 0xffef4444
                elseif layer.state == "overdubbing" then
                    color = 0xfff59e0b
                end
                ui.layerIndicators[i]._bg = color
            end
        end
    end

    -- Force redraw of animated canvases
    ui.particlePad.node:repaint()
    ui.matrixRain.node:repaint()
    ui.eqCanvas:repaint()
    ui.waveCanvas:repaint()
    ui.noiseCanvas:repaint()
    ui.kaleidoCanvas:repaint()
    -- Debug: check if time is flowing
    if not lastDbg then lastDbg = 0 end
    if animTime - lastDbg > 1 then
        print(string.format("animTime=%.2f glWidget._animTime=%.2f", animTime, ui.glWidget._animTime or -1))
        lastDbg = animTime
    end
    ui.glWidget:setAnimTime(animTime)
    ui.glWidget.node:repaint()
    ui.xyPad.node:repaint()
end

local W = require("ui_widgets")

local ui = {}
local current_state = {}
local MAX_LAYERS = 4
local contentRoot = nil

local FX_PRESETS = {"Chorus", "Phaser", "Reverse", "Crusher"}
local SEG_BARS = {0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0}
local SEG_LABELS = {"1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16"}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function endpointExists(path)
  if type(hasEndpoint) == "function" then
    local ok, exists = pcall(hasEndpoint, path)
    return ok and exists == true
  end
  return true
end

local function setParamSafe(path, value)
  if not endpointExists(path) then
    return false
  end
  if type(setParam) == "function" then
    local ok, handled = pcall(setParam, path, value)
    return ok and handled == true
  end
  return false
end

local function triggerSafe(path)
  command("TRIGGER", path)
end

local function readParam(params, path, fallback)
  if type(params) ~= "table" then return fallback end
  local v = params[path]
  if v == nil then return fallback end
  return v
end

local function liveParam(params, path, fallback)
  if type(getParam) == "function" then
    local ok, value = pcall(getParam, path)
    if ok and value ~= nil then
      return value
    end
  end
  return readParam(params, path, fallback)
end

local function readBoolParam(params, path, fallback)
  local raw = readParam(params, path, fallback and 1 or 0)
  return raw == true or raw == 1
end

local function layerPath(layerIndex, suffix)
  return string.format("/core/behavior/layer/%d/%s", layerIndex, suffix)
end

local function vocalFxPath(suffix)
  local p1 = "/core/super/vocal/slot/" .. suffix
  local p2 = "/core/behavior/super/vocal/slot/" .. suffix
  if endpointExists(p1) then return p1 end
  if endpointExists(p2) then return p2 end
  return p1
end

local function layerFxPath(layerIndex, suffix)
  local p1 = string.format("/core/super/layer/%d/fx/%s", layerIndex, suffix)
  local p2 = string.format("/core/behavior/super/layer/%d/fx/%s", layerIndex, suffix)
  if endpointExists(p1) then return p1 end
  if endpointExists(p2) then return p2 end
  return p1
end

local function buildSuperDspPathCandidates()
  local out = {}
  if settings and settings.getDspScriptsDir then
    local dir = settings.getDspScriptsDir() or ""
    if dir ~= "" then
      if dir:sub(-1) == "/" then
        out[#out + 1] = dir .. "donut_looper_super_dsp.lua"
      else
        out[#out + 1] = dir .. "/donut_looper_super_dsp.lua"
      end
    end
  end
  out[#out + 1] = "manifold/dsp/donut_looper_super_dsp.lua"
  out[#out + 1] = "./donut_looper_super_dsp.lua"
  return out
end

local function ensureSuperDspLoaded()
  if type(setDspSlotPersistOnUiSwitch) == "function" then
    pcall(setDspSlotPersistOnUiSwitch, "super", false)
  end

  if endpointExists("/core/super/vocal/slot/k1") then
    return true
  end

  if type(loadDspScriptInSlot) ~= "function" then
    return false
  end

  local candidates = buildSuperDspPathCandidates()
  for i = 1, #candidates do
    local ok, loaded = pcall(loadDspScriptInSlot, candidates[i], "super")
    if ok and loaded and endpointExists("/core/super/vocal/slot/k1") then
      ui.loadedDspPath = candidates[i]
      return true
    end
  end

  return endpointExists("/core/super/vocal/slot/k1")
end

local function modeIndexFromString(mode)
  if type(mode) == "number" then return clamp(math.floor(mode + 0.5), 0, 2) end
  if mode == "firstLoop" then return 0 end
  if mode == "freeMode" then return 1 end
  if mode == "traditional" then return 2 end
  return 0
end

local function normalizeState(s)
  if type(s) ~= "table" then return {} end

  local params = s.params or {}
  local voices = s.voices or {}

  local out = {
    params = params,
    voices = voices,
    tempo = tonumber(liveParam(params, "/core/behavior/tempo", 120)) or 120,
    targetBPM = tonumber(liveParam(params, "/core/behavior/targetbpm", 120)) or 120,
    samplesPerBar = tonumber(readParam(params, "/core/behavior/samplesPerBar", 88200)) or 88200,
    captureSize = tonumber(readParam(params, "/core/behavior/captureSize", 0)) or 0,
    isRecording = (tonumber(liveParam(params, "/core/behavior/recording", 0)) or 0) > 0.5,
    overdubEnabled = (tonumber(liveParam(params, "/core/behavior/overdub", 0)) or 0) > 0.5,
    activeLayer = tonumber(liveParam(params, "/core/behavior/activeLayer", liveParam(params, "/core/behavior/layer", 0))) or 0,
    recordMode = liveParam(params, "/core/behavior/mode", "firstLoop"),
    forwardArmed = (tonumber(liveParam(params, "/core/behavior/forwardArmed", 0)) or 0) > 0.5,
    forwardBars = tonumber(liveParam(params, "/core/behavior/forwardBars", 0)) or 0,
    layers = {},
    vocalFx = {
      select = tonumber(liveParam(params, vocalFxPath("select"), 0)) or 0,
      x = tonumber(liveParam(params, vocalFxPath("x"), 0.5)) or 0.5,
      y = tonumber(liveParam(params, vocalFxPath("y"), 0.5)) or 0.5,
      k1 = tonumber(liveParam(params, vocalFxPath("k1"), 0.5)) or 0.5,
      k2 = tonumber(liveParam(params, vocalFxPath("k2"), 0.5)) or 0.5,
      mix = tonumber(liveParam(params, vocalFxPath("mix"), 0.45)) or 0.45,
    },
  }

  if type(out.recordMode) == "number" then
    local idx = clamp(math.floor(out.recordMode + 0.5), 0, 2)
    if idx == 0 then out.recordMode = "firstLoop"
    elseif idx == 1 then out.recordMode = "freeMode"
    else out.recordMode = "traditional" end
  end

  if #voices > 0 then
    for i, voice in ipairs(voices) do
      out.layers[i] = {
        index = voice.id or (i - 1),
        length = voice.length or 0,
        position = voice.position or 0,
        speed = voice.speed or 1,
        reversed = voice.reversed or false,
        volume = voice.volume or 1,
        state = voice.state or "empty",
        muted = voice.muted or false,
        fx = {
          select = tonumber(liveParam(params, layerFxPath(i - 1, "select"), 0)) or 0,
          x = tonumber(liveParam(params, layerFxPath(i - 1, "x"), 0.5)) or 0.5,
          y = tonumber(liveParam(params, layerFxPath(i - 1, "y"), 0.5)) or 0.5,
          k1 = tonumber(liveParam(params, layerFxPath(i - 1, "k1"), 0.5)) or 0.5,
          k2 = tonumber(liveParam(params, layerFxPath(i - 1, "k2"), 0.5)) or 0.5,
          mix = tonumber(liveParam(params, layerFxPath(i - 1, "mix"), 0.35)) or 0.35,
        },
      }
    end
  else
    for i = 0, MAX_LAYERS - 1 do
      local length = tonumber(readParam(params, layerPath(i, "length"), 0)) or 0
      local pos = tonumber(readParam(params, layerPath(i, "position"), 0)) or 0
      local stateName = readParam(params, layerPath(i, "state"), nil)
      if type(stateName) ~= "string" then
        if out.isRecording and out.activeLayer == i then stateName = "recording"
        elseif length > 0 then stateName = "stopped"
        else stateName = "empty" end
      end

      out.layers[i + 1] = {
        index = i,
        length = length,
        position = pos,
        speed = tonumber(readParam(params, layerPath(i, "speed"), 1.0)) or 1.0,
        reversed = readBoolParam(params, layerPath(i, "reverse"), false),
        volume = tonumber(readParam(params, layerPath(i, "volume"), 1.0)) or 1.0,
        muted = readBoolParam(params, layerPath(i, "mute"), false),
        state = stateName,
        fx = {
          select = tonumber(liveParam(params, layerFxPath(i, "select"), 0)) or 0,
          x = tonumber(liveParam(params, layerFxPath(i, "x"), 0.5)) or 0.5,
          y = tonumber(liveParam(params, layerFxPath(i, "y"), 0.5)) or 0.5,
          k1 = tonumber(liveParam(params, layerFxPath(i, "k1"), 0.5)) or 0.5,
          k2 = tonumber(liveParam(params, layerFxPath(i, "k2"), 0.5)) or 0.5,
          mix = tonumber(liveParam(params, layerFxPath(i, "mix"), 0.35)) or 0.35,
        },
      }
    end
  end

  return out
end

local function layerStateColour(stateName)
  local colours = {
    empty = 0xff64748b,
    playing = 0xff34d399,
    recording = 0xffef4444,
    overdubbing = 0xfff59e0b,
    muted = 0xff94a3b8,
    stopped = 0xfffde047,
    paused = 0xffa78bfa,
  }
  return colours[stateName] or 0xffffffff
end

local function initTransport(parent)
  ui.transport = W.Panel.new(parent, "transport", { bg = 0xff111827, radius = 8 })

  ui.title = W.Label.new(ui.transport.node, "title", {
    text = "Donut Super Looper",
    colour = 0xff93c5fd,
    fontSize = 13,
    fontStyle = FontStyle.bold,
  })


  ui.recBtn = W.Button.new(ui.transport.node, "rec", {
    label = "● REC",
    bg = 0xff7f1d1d,
    on_click = function()
      if current_state.isRecording then triggerSafe("/core/behavior/stoprec")
      else triggerSafe("/core/behavior/rec") end
    end,
  })

  ui.playBtn = W.Button.new(ui.transport.node, "play", {
    label = "▶", bg = 0xff14532d,
    on_click = function() triggerSafe("/core/behavior/play") end,
  })

  ui.pauseBtn = W.Button.new(ui.transport.node, "pause", {
    label = "⏸", bg = 0xff78350f,
    on_click = function() triggerSafe("/core/behavior/pause") end,
  })

  ui.stopBtn = W.Button.new(ui.transport.node, "stop", {
    label = "⏹", bg = 0xff334155,
    on_click = function() triggerSafe("/core/behavior/stop") end,
  })

  ui.clearBtn = W.Button.new(ui.transport.node, "clear", {
    label = "Clear", bg = 0xff7f1d1d,
    on_click = function() triggerSafe("/core/behavior/clear") end,
  })

  ui.overdubToggle = W.Toggle.new(ui.transport.node, "overdub", {
    label = "Overdub",
    onColour = 0xfff59e0b,
    offColour = 0xff374151,
    on_change = function(on)
      setParamSafe("/core/behavior/overdub", on and 1 or 0)
    end,
  })

  ui.tempoBox = W.NumberBox.new(ui.transport.node, "tempo", {
    min = 20, max = 300, step = 1, value = 120,
    label = "BPM", format = "%d", colour = 0xff38bdf8,
    on_change = function(v) setParamSafe("/core/behavior/tempo", v) end,
  })

  ui.targetBox = W.NumberBox.new(ui.transport.node, "target", {
    min = 20, max = 300, step = 1, value = 120,
    label = "Target", format = "%d", colour = 0xff22d3ee,
    on_change = function(v) setParamSafe("/core/behavior/targetbpm", v) end,
  })
end

local function initCapture(parent)
  ui.capture = W.Panel.new(parent, "capture", { bg = 0xff101723, radius = 8 })

  ui.captureTitle = W.Label.new(ui.capture.node, "captureTitle", {
    text = "",
    colour = 0xff9ca3af,
    fontSize = 12.0,
  })

  ui.captureStrips = {}
  for slot = 1, #SEG_BARS do
    local barsIndex = #SEG_BARS + 1 - slot
    local stripBars = SEG_BARS[barsIndex]
    local stripLabel = SEG_LABELS[barsIndex]

    local strip = W.Panel.new(ui.capture.node, "strip_" .. slot, {
      bg = 0xff0f1b2d,
      interceptsMouse = false,
    })

    local prevBars = (barsIndex > 1) and SEG_BARS[barsIndex - 1] or 0

    strip.node:setOnDraw(function(self)
      local w = self:getWidth()
      local h = self:getHeight()

      gfx.setColour(0xff0f1b2d)
      gfx.fillRect(0, 0, w, h)
      gfx.setColour(0x22ffffff)
      gfx.drawHorizontalLine(math.floor(h / 2), 0, w)

      local spb = current_state.samplesPerBar or 88200
      local rangeStart = math.floor(prevBars * spb)
      local rangeEnd = math.floor(stripBars * spb)
      local captureSize = current_state.captureSize or 0
      local clippedStart = math.max(0, math.min(captureSize, rangeStart))
      local clippedEnd = math.max(0, math.min(captureSize, rangeEnd))

      if clippedEnd > clippedStart and w > 4 then
        local numBuckets = math.min(w - 4, 128)
        local peaks = getCapturePeaks(clippedStart, clippedEnd, numBuckets)
        if peaks and #peaks > 0 then
          local centerY = h / 2
          local gain = h * 0.45
          gfx.setColour(0xff22d3ee)
          for x = 1, #peaks do
            local peak = peaks[x]
            local ph = peak * gain
            local px = 2 + (x - 1) * ((w - 4) / #peaks)
            gfx.drawVerticalLine(math.floor(px), centerY - ph, centerY + ph)
          end
        end
      end

      gfx.setColour(0x40475569)
      gfx.drawRect(0, 0, w, h)
      gfx.setColour(0xffcbd5e1)
      gfx.setFont(10.0)
      gfx.drawText(stripLabel, 4, h - 16, w - 8, 14, Justify.bottomLeft)
    end)

    ui.captureStrips[#ui.captureStrips + 1] = { node = strip.node, barsIndex = barsIndex }
  end

  ui.captureSegments = {}
  for i = #SEG_BARS, 1, -1 do
    local bars = SEG_BARS[i]
    local label = SEG_LABELS[i]

    local seg = W.Panel.new(ui.capture.node, "segment_hit_" .. i, {
      bg = 0x00000000,
      interceptsMouse = true,
    })

    seg.node:setOnClick(function()
      if current_state.recordMode == "traditional" then
        setParamSafe("/core/behavior/forward", bars)
      else
        setParamSafe("/core/behavior/commit", bars)
      end
    end)

    seg.node:setOnDraw(function(self)
      local w = self:getWidth()
      local h = self:getHeight()
      local hovered = self:isMouseOver()
      local armed = current_state.forwardArmed and math.abs((current_state.forwardBars or 0) - bars) < 0.001

      if hovered then
        gfx.setColour(0x2a60a5fa)
        gfx.fillRect(0, 0, w, h)
        gfx.setColour(0xff60a5fa)
        gfx.drawRect(0, 0, w, h, 1)
      end

      if armed then
        gfx.setColour(0x3384cc16)
        gfx.fillRect(0, 0, w, h)
        gfx.setColour(0xff84cc16)
        gfx.drawRect(0, 0, w, h, 2)
      end

      if hovered or armed then
        local tc = armed and 0xffd9f99d or 0xffbfdbfe
        gfx.setColour(tc)
        gfx.setFont(12.0)
        gfx.drawText(label .. " bars", 6, 0, w - 12, 20, Justify.topRight)
      end
    end)

    ui.captureSegments[#ui.captureSegments + 1] = { node = seg.node, bars = bars, index = i }
  end
end

local function initVocalFx(parent)
  ui.vocal = W.Panel.new(parent, "vocal", { bg = 0xff111827, radius = 8, border = 0xff1f2937, borderWidth = 1 })

  ui.vocalTitle = W.Label.new(ui.vocal.node, "vocalTitle", {
    text = "Vocal Input FX",
    colour = 0xff93c5fd,
    fontSize = 12,
    fontStyle = FontStyle.bold,
  })

  ui.vocalPreset = W.Dropdown.new(ui.vocal.node, "vocalPreset", {
    options = FX_PRESETS,
    selected = 1,
    bg = 0xff1e293b,
    colour = 0xff38bdf8,
    rootNode = contentRoot,
    on_select = function(idx)
      setParamSafe(vocalFxPath("select"), idx - 1)
    end,
  })

  ui.vocalXY = W.XYPadWidget.new(ui.vocal.node, "vocalXY", {
    x = 0.5, y = 0.5,
    on_change = function(x, y)
      setParamSafe(vocalFxPath("x"), x)
      setParamSafe(vocalFxPath("y"), y)
    end,
  })

  ui.vocalK1 = W.Knob.new(ui.vocal.node, "vocalK1", {
    min = 0, max = 1, step = 0.01, value = 0.5,
    label = "K1", colour = 0xff22d3ee,
    on_change = function(v) setParamSafe(vocalFxPath("k1"), v) end,
  })

  ui.vocalK2 = W.Knob.new(ui.vocal.node, "vocalK2", {
    min = 0, max = 1, step = 0.01, value = 0.5,
    label = "K2", colour = 0xff22d3ee,
    on_change = function(v) setParamSafe(vocalFxPath("k2"), v) end,
  })

  ui.vocalMix = W.Knob.new(ui.vocal.node, "vocalMix", {
    min = 0, max = 1, step = 0.01, value = 0.45,
    label = "Mix", colour = 0xffa78bfa,
    on_change = function(v) setParamSafe(vocalFxPath("mix"), v) end,
  })
end

local function initLayerCards(parent)
  ui.layers = {}

  for i = 0, MAX_LAYERS - 1 do
    local card = {}

    card.panel = W.Panel.new(parent, "layerCard" .. i, {
      bg = 0xff0b1220,
      border = 0xff1f2937,
      borderWidth = 1,
      radius = 8,
    })

    card.title = W.Label.new(card.panel.node, "title" .. i, {
      text = "Layer " .. tostring(i),
      colour = 0xffcbd5e1,
      fontSize = 12,
    })

    card.donut = W.DonutWidget.new(card.panel.node, "donut" .. i, {
      layerIndex = i,
      on_seek = function(layerIdx, norm)
        setParamSafe("/core/behavior/activeLayer", layerIdx)
        setParamSafe(layerPath(layerIdx, "seek"), norm)
      end,
    })

    card.play = W.Button.new(card.panel.node, "play" .. i, {
      label = "Play",
      bg = 0xff14532d,
      on_click = function()
        setParamSafe("/core/behavior/activeLayer", i)
        triggerSafe(layerPath(i, "play"))
      end,
    })

    card.clear = W.Button.new(card.panel.node, "clear" .. i, {
      label = "Clear",
      bg = 0xff7f1d1d,
      on_click = function()
        setParamSafe("/core/behavior/activeLayer", i)
        triggerSafe(layerPath(i, "clear"))
      end,
    })

    card.mute = W.Button.new(card.panel.node, "mute" .. i, {
      label = "Mute",
      bg = 0xff475569,
      on_click = function()
        local layer = current_state.layers and current_state.layers[i + 1] or {}
        setParamSafe(layerPath(i, "mute"), layer.muted and 0 or 1)
      end,
    })

    card.preset = W.Dropdown.new(card.panel.node, "preset" .. i, {
      options = FX_PRESETS,
      selected = 1,
      bg = 0xff1e293b,
      colour = 0xff38bdf8,
      rootNode = contentRoot,
      on_select = function(idx)
        setParamSafe(layerFxPath(i, "select"), idx - 1)
      end,
    })

    card.xy = W.XYPadWidget.new(card.panel.node, "xy" .. i, {
      x = 0.5, y = 0.5,
      on_change = function(x, y)
        setParamSafe(layerFxPath(i, "x"), x)
        setParamSafe(layerFxPath(i, "y"), y)
      end,
    })

    card.k1 = W.Knob.new(card.panel.node, "k1" .. i, {
      min = 0, max = 1, step = 0.01, value = 0.5,
      label = "K1", colour = 0xff22d3ee,
      on_change = function(v) setParamSafe(layerFxPath(i, "k1"), v) end,
    })

    card.k2 = W.Knob.new(card.panel.node, "k2" .. i, {
      min = 0, max = 1, step = 0.01, value = 0.5,
      label = "K2", colour = 0xff22d3ee,
      on_change = function(v) setParamSafe(layerFxPath(i, "k2"), v) end,
    })

    card.mix = W.Knob.new(card.panel.node, "mix" .. i, {
      min = 0, max = 1, step = 0.01, value = 0.35,
      label = "Mix", colour = 0xffa78bfa,
      on_change = function(v) setParamSafe(layerFxPath(i, "mix"), v) end,
    })

    ui.layers[i + 1] = card
  end
end

function ui_init(root)
  contentRoot = root
  ui.root = W.Panel.new(root, "root", { bg = 0xff060b16 })

  initTransport(ui.root.node)
  initCapture(ui.root.node)
  initVocalFx(ui.root.node)
  initLayerCards(ui.root.node)

  ensureSuperDspLoaded()
end

function ui_resized(w, h)
  if not ui.root then return end
  ui.root:setBounds(0, 0, w, h)

  local pad = 8
  local transportH = 50
  local captureH = 96
  local vocalH = 146

  ui.transport:setBounds(pad, pad, w - pad * 2, transportH)
  ui.title:setBounds(8, 4, 180, 14)
  ui.recBtn:setBounds(8, 20, 78, 24)
  ui.playBtn:setBounds(90, 20, 38, 24)
  ui.pauseBtn:setBounds(132, 20, 38, 24)
  ui.stopBtn:setBounds(174, 20, 38, 24)
  ui.clearBtn:setBounds(216, 20, 56, 24)
  ui.overdubToggle:setBounds(276, 20, 100, 24)
  ui.targetBox:setBounds(w - 180, 8, 84, 34)
  ui.tempoBox:setBounds(w - 92, 8, 84, 34)

  local captureY = pad + transportH + pad
  local captureW = w - pad * 2
  ui.capture:setBounds(pad, captureY, captureW, captureH)

  ui.captureTitle:setText("")
  ui.captureTitle:setBounds(0, 0, 0, 0)

  local captureArea = { x = 0, y = 4, w = captureW, h = captureH - 8 }
  local slotCount = #SEG_BARS
  local slotWidth = math.max(1, math.floor(captureArea.w / slotCount))
  local totalStripW = slotWidth * slotCount
  local x0 = captureArea.x + captureArea.w - totalStripW

  for slot, strip in ipairs(ui.captureStrips) do
    strip.node:setBounds(x0 + (slot - 1) * slotWidth, captureArea.y, slotWidth, captureArea.h)
  end

  for _, seg in ipairs(ui.captureSegments) do
    local i = seg.index
    local sx = x0 + (slotCount - i) * slotWidth
    local sw = i * slotWidth
    seg.node:setBounds(sx, captureArea.y, sw, captureArea.h)
  end

  local vocalY = captureY + captureH + pad
  ui.vocal:setBounds(pad, vocalY, w - pad * 2, vocalH)
  ui.vocalTitle:setBounds(8, 6, 180, 16)
  ui.vocalPreset:setBounds(8, 24, 132, 26)
  ui.vocalPreset:setAbsolutePos(pad + 8, vocalY + 24)
  ui.vocalXY:setBounds(8, 54, 190, vocalH - 62)
  ui.vocalK1:setBounds(204, 24, 72, vocalH - 32)
  ui.vocalK2:setBounds(280, 24, 72, vocalH - 32)
  ui.vocalMix:setBounds(356, 24, 72, vocalH - 32)

  local layerY = vocalY + vocalH + pad
  local availH = h - layerY - pad
  local gap = 8
  local cardW = math.floor((w - pad * 2 - gap) / 2)
  local cardH = math.floor((availH - gap) / 2)

  for idx, card in ipairs(ui.layers) do
    local i = idx - 1
    local col = i % 2
    local row = math.floor(i / 2)
    local x = pad + col * (cardW + gap)
    local y = layerY + row * (cardH + gap)

    card.panel:setBounds(x, y, cardW, cardH)
    card.title:setBounds(8, 6, 200, 16)

    local donutSize = math.max(72, math.min(cardH - 54, math.floor(cardW * 0.36)))
    card.donut:setBounds(8, 24, donutSize, donutSize)

    card.play:setBounds(8, cardH - 24, 54, 20)
    card.clear:setBounds(66, cardH - 24, 54, 20)
    card.mute:setBounds(124, cardH - 24, 54, 20)

    local fxX = donutSize + 16
    local fxW = cardW - fxX - 8
    card.preset:setBounds(fxX, 24, math.min(132, fxW), 24)
    card.preset:setAbsolutePos(x + fxX, y + 24)

    card.xy:setBounds(fxX, 52, math.floor(fxW * 0.52), cardH - 60)

    local knobX = fxX + math.floor(fxW * 0.52) + 6
    local knobW = math.max(50, fxW - (knobX - fxX))
    local rowH = math.floor((cardH - 66) / 3)
    card.k1:setBounds(knobX, 52, knobW, rowH)
    card.k2:setBounds(knobX, 56 + rowH, knobW, rowH)
    card.mix:setBounds(knobX, 60 + rowH * 2, knobW, rowH)
  end
end

function ui_update(s)
  current_state = normalizeState(s)

  for _, strip in ipairs(ui.captureStrips or {}) do
    if strip.node and strip.node.repaint then
      strip.node:repaint()
    end
  end

  ui.tempoBox:setValue(current_state.tempo or 120)
  ui.targetBox:setValue(current_state.targetBPM or 120)
  ui.overdubToggle:setValue(current_state.overdubEnabled or false)

  if current_state.isRecording then
    ui.recBtn:setLabel("● REC*")
    ui.recBtn:setBg(0xffdc2626)
  else
    ui.recBtn:setLabel("● REC")
    ui.recBtn:setBg(0xff7f1d1d)
  end

  local vf = current_state.vocalFx or {}
  ui.vocalPreset:setSelected(clamp(math.floor((vf.select or 0) + 1.5), 1, #FX_PRESETS))
  ui.vocalXY:setValues(vf.x or 0.5, vf.y or 0.5)
  if not ui.vocalK1._dragging then ui.vocalK1:setValue(vf.k1 or 0.5) end
  if not ui.vocalK2._dragging then ui.vocalK2:setValue(vf.k2 or 0.5) end
  if not ui.vocalMix._dragging then ui.vocalMix:setValue(vf.mix or 0.45) end

  for idx, card in ipairs(ui.layers) do
    local layer = current_state.layers and current_state.layers[idx] or {}
    local active = (current_state.activeLayer or 0) == (idx - 1)
    local stateName = tostring(layer.state or "empty")

    card.panel:setStyle({
      bg = active and 0xff10243f or 0xff0b1220,
      border = active and 0xff38bdf8 or 0xff1f2937,
      borderWidth = active and 2 or 1,
    })

    card.title:setText(string.format("Layer %d  •  %s", idx - 1, stateName))
    card.title:setColour(active and 0xffdbeafe or 0xffcbd5e1)

    if stateName == "playing" then
      card.play:setLabel("Pause")
      card.play:setBg(0xffb45309)
      card.play._onClick = function()
        setParamSafe("/core/behavior/activeLayer", idx - 1)
        triggerSafe(layerPath(idx - 1, "pause"))
      end
    else
      card.play:setLabel("Play")
      card.play:setBg(0xff14532d)
      card.play._onClick = function()
        setParamSafe("/core/behavior/activeLayer", idx - 1)
        triggerSafe(layerPath(idx - 1, "play"))
      end
    end

    if layer.muted then
      card.mute:setLabel("Muted")
      card.mute:setBg(0xffef4444)
    else
      card.mute:setLabel("Mute")
      card.mute:setBg(0xff475569)
    end

    local peaks = nil
    if type(getLayerPeaks) == "function" then
      peaks = getLayerPeaks(idx - 1, 96)
    end

    card.donut:setLayerData({
      length = layer.length or 0,
      positionNorm = layer.length and layer.length > 0 and clamp((layer.position or 0) / layer.length, 0.0, 1.0) or 0.0,
      volume = layer.volume or 1.0,
      muted = layer.muted,
      state = stateName,
    })
    card.donut:setPeaks(peaks)

    local fx = layer.fx or {}
    card.preset:setSelected(clamp(math.floor((fx.select or 0) + 1.5), 1, #FX_PRESETS))
    card.xy:setValues(fx.x or 0.5, fx.y or 0.5)
    if not card.k1._dragging then card.k1:setValue(fx.k1 or 0.5) end
    if not card.k2._dragging then card.k2:setValue(fx.k2 or 0.5) end
    if not card.mix._dragging then card.mix:setValue(fx.mix or 0.35) end
  end
end

function ui_cleanup()
  setParamSafe(vocalFxPath("mix"), 0.0)
  for i = 0, MAX_LAYERS - 1 do
    setParamSafe(layerFxPath(i, "mix"), 0.0)
  end

  if type(setDspSlotPersistOnUiSwitch) == "function" then
    pcall(setDspSlotPersistOnUiSwitch, "super", false)
  end
  if type(unloadDspSlot) == "function" then
    pcall(unloadDspSlot, "super")
  end
end

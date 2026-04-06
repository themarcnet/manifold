-- Envelope (ADSR) Behavior with interactive graph
local ModWidgetSync = require("ui.modulation_widget_sync")

local EnvelopeBehavior = {}

local COLORS = {
  grid = 0xFF1A1A3A,
  envelope = 0xfffda4af,
  envelopeDim = 0x88fda4af,
  fill = 0x18fda4af,
  controlPoint = 0xFFFFFFFF,
  controlPointActive = 0xfffda4af,
  controlPointHover = 0xffffe4e6,
}

local VOICE_COLORS = {
  0xff4ade80,  -- green
  0xff38bdf8,  -- blue
  0xfffbbf24,  -- amber
  0xfff87171,  -- red
  0xffa78bfa,  -- purple
  0xff2dd4bf,  -- teal
  0xfffb923c,  -- orange
  0xfff472b6,  -- pink
}

local POINT_RADIUS = 5
local HIT_RADIUS = 12
local SYNC_INTERVAL = 0.08

local GLOBAL_PATHS = {
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
}

-- Calculate the pixel positions of ADSR control points
local function calcAdsrPoints(ctx, w, h)
  local pad = 6
  local headerH = 16  -- Space for title at top
  local graphW = w - pad * 2
  local graphH = h - pad * 2 - headerH  -- Reduced height for graph content
  local displayValues = ctx.displayValues or ctx.values
  local totalTime = displayValues.attack + displayValues.decay + 0.5 + displayValues.release

  local attackX = pad + math.floor((displayValues.attack / totalTime) * graphW)
  local decayX = attackX + math.floor((displayValues.decay / totalTime) * graphW)
  local sustainY = pad + headerH + math.floor(graphH - (displayValues.sustain * graphH))
  local releaseX = decayX + math.floor((0.5 / totalTime) * graphW)
  local bottomY = pad + headerH + graphH
  local topY = pad + headerH

  return {
    pad = pad,
    graphW = graphW,
    graphH = graphH,
    bottomY = bottomY,
    topY = topY,
    attack  = { x = attackX,  y = topY },
    decay   = { x = decayX,   y = sustainY },
    sustain = { x = releaseX, y = sustainY },
    release = { x = w - pad,  y = bottomY },
  }
end

local function buildEnvelopeDisplay(ctx, w, h)
  local display = {}
  local pts = calcAdsrPoints(ctx, w, h)
  local activePoint = ctx.dragPoint

  -- Title inside graph (top-left, following Sample/Blend pattern)
  display[#display + 1] = {
    cmd = "drawText", x = 4, y = 2, w = w - 8, h = 16,
    text = "ADSR", color = COLORS.envelope, fontSize = 11, align = "left", valign = "top",
  }

  -- Subtle grid lines
  for i = 1, 3 do
    local x = math.floor((w / 4) * i)
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = x, y1 = 0, x2 = x, y2 = h,
      thickness = 1, color = COLORS.grid,
    }
  end
  for i = 1, 3 do
    local y = math.floor((h / 4) * i)
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = 0, y1 = y, x2 = w, y2 = y,
      thickness = 1, color = COLORS.grid,
    }
  end

  -- Envelope fill (semi-transparent polygon approximation via filled rects - skip for now, just lines)

  -- Envelope path segments
  local segments = {
    { pts.pad, pts.bottomY, pts.attack.x, pts.attack.y },
    { pts.attack.x, pts.attack.y, pts.decay.x, pts.decay.y },
    { pts.decay.x, pts.decay.y, pts.sustain.x, pts.sustain.y },
    { pts.sustain.x, pts.sustain.y, pts.release.x, pts.release.y },
  }

  for _, seg in ipairs(segments) do
    -- Glow line (wider, translucent)
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = seg[1], y1 = seg[2], x2 = seg[3], y2 = seg[4],
      thickness = 4, color = COLORS.fill,
    }
    -- Main line
    display[#display + 1] = {
      cmd = "drawLine",
      x1 = seg[1], y1 = seg[2], x2 = seg[3], y2 = seg[4],
      thickness = 2, color = COLORS.envelope,
    }
  end

  -- Control points
  local pointDefs = {
    { name = "attack",  pt = pts.attack },
    { name = "decay",   pt = pts.decay },
    { name = "sustain", pt = pts.sustain },
  }

  for _, def in ipairs(pointDefs) do
    local isActive = (activePoint == def.name)
    local col = isActive and COLORS.controlPointActive or COLORS.controlPoint
    local r = isActive and (POINT_RADIUS + 2) or POINT_RADIUS

    -- Outer glow when active
    if isActive then
      display[#display + 1] = {
        cmd = "fillRoundedRect",
        x = def.pt.x - r - 2, y = def.pt.y - r - 2,
        w = (r + 2) * 2, h = (r + 2) * 2,
        radius = r + 2,
        color = 0x44fda4af,
      }
    end

    display[#display + 1] = {
      cmd = "fillRoundedRect",
      x = def.pt.x - r, y = def.pt.y - r,
      w = r * 2, h = r * 2,
      radius = r,
      color = col,
    }
  end

  -- Voice position indicators
  local voices = ctx.voicePositions
  if type(voices) == "table" then
    local vals = ctx.displayValues or ctx.values
    local attackTime = math.max(0.001, vals.attack)
    local decayTime = math.max(0.001, vals.decay)
    local sustainLevel = vals.sustain
    local releaseTime = math.max(0.001, vals.release)

    for vi, voice in ipairs(voices) do
      local col = VOICE_COLORS[((vi - 1) % #VOICE_COLORS) + 1]
      local colDim = (0xaa << 24) | (col & 0x00ffffff)
      local vx, vy
      local t = voice.time or 0
      local level = voice.level or 0

      if voice.stage == "attack" then
        local progress = math.min(1, t / attackTime)
        -- Lerp along the attack segment
        vx = pts.pad + (pts.attack.x - pts.pad) * progress
        vy = pts.bottomY + (pts.attack.y - pts.bottomY) * progress

      elseif voice.stage == "decay" then
        local progress = math.min(1, t / decayTime)
        vx = pts.attack.x + (pts.decay.x - pts.attack.x) * progress
        vy = pts.attack.y + (pts.decay.y - pts.attack.y) * progress

      elseif voice.stage == "sustain" then
        -- Sit in the sustain hold region
        vx = (pts.decay.x + pts.sustain.x) * 0.5
        vy = pts.decay.y

      elseif voice.stage == "release" then
        local progress = math.min(1, t / releaseTime)
        vx = pts.sustain.x + (pts.release.x - pts.sustain.x) * progress
        vy = pts.sustain.y + (pts.release.y - pts.sustain.y) * progress
      end

      if vx and vy then
        -- Vertical line from bottom to the voice position
        display[#display + 1] = {
          cmd = "drawLine",
          x1 = vx, y1 = pts.bottomY,
          x2 = vx, y2 = vy,
          thickness = 1, color = colDim,
        }
        -- Dot at the voice position
        display[#display + 1] = {
          cmd = "fillRoundedRect",
          x = vx - 3, y = vy - 3,
          w = 6, h = 6,
          radius = 3,
          color = col,
        }
      end
    end
  end

  return display
end

local function updateValueDisplay(ctx)
  -- no-op: graph and knobs are the display
end



local function syncKnobs(ctx)
  local ak = ctx.widgets.attack_knob
  local dk = ctx.widgets.decay_knob
  local sk = ctx.widgets.sustain_knob
  local rk = ctx.widgets.release_knob
  if ak then ak._onChange = nil; ak:setValue(ctx.values.attack * 1000) end
  if dk then dk._onChange = nil; dk:setValue(ctx.values.decay * 1000) end
  if sk then sk._onChange = nil; sk:setValue(ctx.values.sustain * 100) end
  if rk then rk._onChange = nil; rk:setValue(ctx.values.release * 1000) end
end

local function refreshGraph(ctx)
  local graph = ctx.widgets.adsr_graph
  if not graph then return end

  local w = 0
  local h = 0
  if graph.node and graph.node.getWidth then
    w = graph.node:getWidth()
    h = graph.node:getHeight()
  end
  if w <= 0 or h <= 0 then return end

  ctx.graphW = w
  ctx.graphH = h

  if graph.node and graph.node.setDisplayList then
    graph.node:setDisplayList(buildEnvelopeDisplay(ctx, w, h))
  end
  if graph.node and graph.node.repaint then
    graph.node:repaint()
  end
end

-- Find which control point (if any) is near the mouse position
local function hitTestPoint(ctx, mx, my)
  local w = ctx.graphW or 0
  local h = ctx.graphH or 0
  if w <= 0 or h <= 0 then return nil end

  local pts = calcAdsrPoints(ctx, w, h)
  local candidates = {
    { name = "attack",  pt = pts.attack },
    { name = "decay",   pt = pts.decay },
    { name = "sustain", pt = pts.sustain },
  }

  for _, c in ipairs(candidates) do
    local dx = mx - c.pt.x
    local dy = my - c.pt.y
    if (dx * dx + dy * dy) <= HIT_RADIUS * HIT_RADIUS then
      return c.name
    end
  end
  return nil
end

-- Clamp helper
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function readParam(path, fallback)
  if type(_G.getParam) == "function" then
    local ok, value = pcall(_G.getParam, path)
    if ok and value ~= nil then
      return value
    end
  end
  return fallback
end

local function writeParam(path, value)
  local numeric = tonumber(value) or 0
  local authoredWriter = type(_G) == "table" and _G.__midiSynthSetAuthoredParam or nil
  if type(authoredWriter) == "function" then
    return authoredWriter(path, numeric)
  end
  if type(_G.setParam) == "function" then
    return _G.setParam(path, numeric)
  end
  if type(command) == "function" then
    command("SET", path, tostring(numeric))
    return true
  end
  return false
end

local function getInstanceModuleId(ctx)
  local record = ctx and ctx.root and ctx.root._structuredRecord or nil
  local globalId = type(record) == "table" and tostring(record.globalId or "") or ""
  local shellId = globalId:match("%.([^.]+Shell)%.[^.]+$") or globalId:match("([^.]+Shell)%.[^.]+$")
  if type(shellId) == "string" and shellId ~= "" then
    return shellId:gsub("Shell$", "")
  end
  return "adsr"
end

local function getParamBase(ctx)
  local moduleId = getInstanceModuleId(ctx)
  local info = type(_G) == "table" and _G.__midiSynthDynamicModuleInfo or nil
  local entry = type(info) == "table" and info[moduleId] or nil
  local paramBase = type(entry) == "table" and type(entry.paramBase) == "string" and entry.paramBase or nil
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase
  end
  return nil
end

local function pathFor(ctx, key)
  local paramBase = getParamBase(ctx)
  if type(paramBase) == "string" and paramBase ~= "" then
    return paramBase .. "/" .. tostring(key)
  end
  return GLOBAL_PATHS[key]
end

local function syncFromParams(ctx)
  local changed = false
  ctx.displayValues = ctx.displayValues or {
    attack = ctx.values.attack or 0.05,
    decay = ctx.values.decay or 0.2,
    sustain = ctx.values.sustain or 0.7,
    release = ctx.values.release or 0.4,
  }

  local attackPath = pathFor(ctx, "attack")
  local decayPath = pathFor(ctx, "decay")
  local sustainPath = pathFor(ctx, "sustain")
  local releasePath = pathFor(ctx, "release")

  local attack, attackEffective, attackState = ModWidgetSync.resolveValues(attackPath, ctx.values.attack or 0.05, readParam)
  local decay, decayEffective, decayState = ModWidgetSync.resolveValues(decayPath, ctx.values.decay or 0.2, readParam)
  local sustain, sustainEffective, sustainState = ModWidgetSync.resolveValues(sustainPath, ctx.values.sustain or 0.7, readParam)
  local release, releaseEffective, releaseState = ModWidgetSync.resolveValues(releasePath, ctx.values.release or 0.4, readParam)

  attack = tonumber(attack) or 0.05
  decay = tonumber(decay) or 0.2
  sustain = tonumber(sustain) or 0.7
  release = tonumber(release) or 0.4
  attackEffective = tonumber(attackEffective) or attack
  decayEffective = tonumber(decayEffective) or decay
  sustainEffective = tonumber(sustainEffective) or sustain
  releaseEffective = tonumber(releaseEffective) or release

  if math.abs((ctx.values.attack or 0.05) - attack) > 0.0001 then ctx.values.attack = attack changed = true end
  if math.abs((ctx.values.decay or 0.2) - decay) > 0.0001 then ctx.values.decay = decay changed = true end
  if math.abs((ctx.values.sustain or 0.7) - sustain) > 0.0001 then ctx.values.sustain = sustain changed = true end
  if math.abs((ctx.values.release or 0.4) - release) > 0.0001 then ctx.values.release = release changed = true end
  if math.abs((ctx.displayValues.attack or 0.05) - attackEffective) > 0.0001 then ctx.displayValues.attack = attackEffective changed = true end
  if math.abs((ctx.displayValues.decay or 0.2) - decayEffective) > 0.0001 then ctx.displayValues.decay = decayEffective changed = true end
  if math.abs((ctx.displayValues.sustain or 0.7) - sustainEffective) > 0.0001 then ctx.displayValues.sustain = sustainEffective changed = true end
  if math.abs((ctx.displayValues.release or 0.4) - releaseEffective) > 0.0001 then ctx.displayValues.release = releaseEffective changed = true end

  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.attack_knob or nil, attack, attackEffective, attackState, function(v)
    return (tonumber(v) or 0.0) * 1000.0
  end)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.decay_knob or nil, decay, decayEffective, decayState, function(v)
    return (tonumber(v) or 0.0) * 1000.0
  end)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.sustain_knob or nil, sustain, sustainEffective, sustainState, function(v)
    return (tonumber(v) or 0.0) * 100.0
  end)
  ModWidgetSync.syncWidget(ctx.widgets and ctx.widgets.release_knob or nil, release, releaseEffective, releaseState, function(v)
    return (tonumber(v) or 0.0) * 1000.0
  end)

  local moduleId = getInstanceModuleId(ctx)
  local state = type(_G) == "table" and type(_G.__midiSynthAdsrViewState) == "table" and _G.__midiSynthAdsrViewState[moduleId] or nil
  local voices = type(state) == "table" and state.voices or nil
  local nextPositions = {}
  if type(voices) == "table" then
    for i = 1, #voices do
      local voice = voices[i]
      if type(voice) == "table" and (((tonumber(voice.gate) or 0.0) > 0.5) or tostring(voice.envelopeStage or "idle") ~= "idle") then
        nextPositions[#nextPositions + 1] = {
          stage = tostring(voice.envelopeStage or "idle"),
          time = tonumber(voice.envelopeTime) or 0.0,
          level = tonumber(voice.envelopeLevel) or 0.0,
        }
      end
    end
  end
  ctx.voicePositions = nextPositions
  return changed
end

local function bindControls(ctx)
  local bindings = {
    attack_knob = { key = "attack", scale = 0.001, min = 0.001, max = 5.0 },
    decay_knob = { key = "decay", scale = 0.001, min = 0.001, max = 5.0 },
    sustain_knob = { key = "sustain", scale = 0.01, min = 0.0, max = 1.0 },
    release_knob = { key = "release", scale = 0.001, min = 0.001, max = 10.0 },
  }
  for widgetId, spec in pairs(bindings) do
    local widget = ctx.widgets and ctx.widgets[widgetId] or nil
    if widget then
      widget._onChange = function(v)
        local scaled = clamp((tonumber(v) or 0.0) * spec.scale, spec.min, spec.max)
        ctx.values[spec.key] = scaled
        writeParam(pathFor(ctx, spec.key), scaled)
        syncFromParams(ctx)
        refreshGraph(ctx)
      end
    end
  end
end

-- Solve for parameter values such that the control point lands exactly at mx,my.
-- Graph positions are proportional: pos = time / totalTime, so we invert that.
local function applyDrag(ctx, pointName, mx, my)
  local w = ctx.graphW or 0
  local h = ctx.graphH or 0
  if w <= 0 or h <= 0 then return end

  local pad = 6
  local graphW = w - pad * 2
  local graphH = h - pad * 2
  local normX = clamp((mx - pad) / graphW, 0.01, 0.99)

  if pointName == "attack" then
    -- attackX/graphW = attack/totalTime, solve for attack:
    -- attack = normX * restTime / (1 - normX)
    local restTime = ctx.values.decay + 0.5 + ctx.values.release
    ctx.values.attack = clamp(normX * restTime / (1.0 - normX), 0.001, 5.0)

  elseif pointName == "decay" then
    -- (attack+decay)/totalTime = normX, solve for decay:
    -- decay = normX*(0.5+release)/(1-normX) - attack
    local holdAndRelease = 0.5 + ctx.values.release
    local decay = normX * holdAndRelease / (1.0 - normX) - ctx.values.attack
    ctx.values.decay = clamp(decay, 0.001, 5.0)
    -- Y → sustain level
    local normY = clamp(1.0 - ((my - pad) / graphH), 0.0, 1.0)
    ctx.values.sustain = normY

  elseif pointName == "sustain" then
    -- (attack+decay+0.5)/totalTime = normX, solve for release:
    -- release = fixed*(1-normX)/normX
    local fixed = ctx.values.attack + ctx.values.decay + 0.5
    local release = fixed * (1.0 - normX) / normX
    ctx.values.release = clamp(release, 0.001, 10.0)
    -- Y → sustain level
    local normY = clamp(1.0 - ((my - pad) / graphH), 0.0, 1.0)
    ctx.values.sustain = normY
  end

  writeParam(pathFor(ctx, "attack"), ctx.values.attack)
  writeParam(pathFor(ctx, "decay"), ctx.values.decay)
  writeParam(pathFor(ctx, "sustain"), ctx.values.sustain)
  writeParam(pathFor(ctx, "release"), ctx.values.release)
  syncFromParams(ctx)
  updateValueDisplay(ctx)
  refreshGraph(ctx)
end

local function setupGraphInteraction(ctx)
  local graph = ctx.widgets.adsr_graph
  if not graph or not graph.node then return end

  -- Ensure the panel intercepts mouse events
  if graph.node.setInterceptsMouse then
    graph.node:setInterceptsMouse(true, true)
  end

  if graph.node.setOnMouseDown then
    graph.node:setOnMouseDown(function(mx, my)
      local hit = hitTestPoint(ctx, mx, my)
      if hit then
        ctx.dragPoint = hit
        refreshGraph(ctx)
      end
    end)
  end

  if graph.node.setOnMouseDrag then
    graph.node:setOnMouseDrag(function(mx, my)
      if ctx.dragPoint then
        applyDrag(ctx, ctx.dragPoint, mx, my)
      end
    end)
  end

  if graph.node.setOnMouseUp then
    graph.node:setOnMouseUp(function(mx, my)
      ctx.dragPoint = nil
      refreshGraph(ctx)
    end)
  end
end

function EnvelopeBehavior.init(ctx)
  ctx.values = {
    attack = 0.05,
    decay = 0.2,
    sustain = 0.7,
    release = 0.4,
  }
  ctx.displayValues = {
    attack = 0.05,
    decay = 0.2,
    sustain = 0.7,
    release = 0.4,
  }
  ctx.voicePositions = {}
  ctx.dragPoint = nil
  ctx.graphW = 0
  ctx.graphH = 0

  bindControls(ctx)
  setupGraphInteraction(ctx)
  syncFromParams(ctx)
  updateValueDisplay(ctx)
  refreshGraph(ctx)
end

local function resizeEnvelopeLayout(ctx, w, h)
  local widgets = ctx.widgets
  local pad = 16
  local gap = 6
  local sliderH = 20

  -- Graph fills top, sliders live in a compact 2x2 grid below it.
  local sliderAreaH = sliderH * 2 + gap
  local graphH = math.max(40, h - pad * 2 - sliderAreaH - 8)
  local graphY = pad
  local graph = widgets.adsr_graph
  if graph then
    if graph.setBounds then graph:setBounds(pad, graphY, w - pad * 2, graphH)
    elseif graph.node then graph.node:setBounds(pad, graphY, w - pad * 2, graphH) end
  end

  local sliderY = graphY + graphH + 8
  local sliderW = math.floor((w - pad * 2 - gap) / 2)
  local positions = {
    attack_knob = { pad, sliderY },
    decay_knob = { pad + sliderW + gap, sliderY },
    sustain_knob = { pad, sliderY + sliderH + gap },
    release_knob = { pad + sliderW + gap, sliderY + sliderH + gap },
  }

  for id, pos in pairs(positions) do
    local knob = widgets[id]
    if knob then
      if knob.setBounds then knob:setBounds(pos[1], pos[2], sliderW, sliderH)
      elseif knob.node then knob.node:setBounds(pos[1], pos[2], sliderW, sliderH) end
    end
  end
end

function EnvelopeBehavior.resized(ctx, w, h)
  -- w, h may come from the project loader or we read from root
  if (not w or w <= 0) and ctx.root and ctx.root.node and ctx.root.node.getWidth then
    w = ctx.root.node:getWidth()
    h = ctx.root.node:getHeight()
  end
  if w and w > 0 and h and h > 0 then
    resizeEnvelopeLayout(ctx, w, h)
  end
  refreshGraph(ctx)
end

function EnvelopeBehavior.onParamChange(ctx, name, value)
  if name == "attack" then
    ctx.values.attack = value
    local knob = ctx.widgets.attack_knob
    if knob then knob:setValue(value * 1000) end
  elseif name == "decay" then
    ctx.values.decay = value
    local knob = ctx.widgets.decay_knob
    if knob then knob:setValue(value * 1000) end
  elseif name == "sustain" then
    ctx.values.sustain = value
    local knob = ctx.widgets.sustain_knob
    if knob then knob:setValue(value * 100) end
  elseif name == "release" then
    ctx.values.release = value
    local knob = ctx.widgets.release_knob
    if knob then knob:setValue(value * 1000) end
  end
  updateValueDisplay(ctx)
  refreshGraph(ctx)
end

function EnvelopeBehavior.update(ctx)
  local now = type(getTime) == "function" and getTime() or 0
  if now == 0 or now - (ctx._lastSyncTime or 0) >= SYNC_INTERVAL then
    ctx._lastSyncTime = now
    local changed = syncFromParams(ctx)
    if changed then
      updateValueDisplay(ctx)
    end
    refreshGraph(ctx)
  end
end

function EnvelopeBehavior.repaint(ctx)
  refreshGraph(ctx)
end

return EnvelopeBehavior

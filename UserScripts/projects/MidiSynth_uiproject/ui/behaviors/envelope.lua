-- Envelope (ADSR) Behavior
-- Handles ADSR controls and visualization

local EnvelopeBehavior = {}

function EnvelopeBehavior.onInit(ctx)
  ctx.widgets = {
    attackKnob = ctx:getWidget("attack_knob"),
    attackValue = ctx:getWidget("attack_value"),
    decayKnob = ctx:getWidget("decay_knob"),
    decayValue = ctx:getWidget("decay_value"),
    sustainKnob = ctx:getWidget("sustain_knob"),
    sustainValue = ctx:getWidget("sustain_value"),
    releaseKnob = ctx:getWidget("release_knob"),
    releaseValue = ctx:getWidget("release_value"),
    graph = ctx:getWidget("adsr_graph"),
  }
  
  ctx.values = {
    attack = 0.01,
    decay = 0.1,
    sustain = 0.7,
    release = 0.3,
  }
  
  -- Format time display
  local function formatTime(ms)
    if ms < 1000 then
      return string.format("%.0f ms", ms)
    else
      return string.format("%.1f s", ms / 1000)
    end
  end
  
  -- Attack knob
  if ctx.widgets.attackKnob then
    ctx.widgets.attackKnob.onChange = function(value)
      ctx.values.attack = value / 1000.0
      if ctx.widgets.attackValue then
        ctx.widgets.attackValue:setText(formatTime(value))
      end
      ctx:notifyParent("attack", ctx.values.attack)
      ctx:drawGraph()
    end
  end
  
  -- Decay knob
  if ctx.widgets.decayKnob then
    ctx.widgets.decayKnob.onChange = function(value)
      ctx.values.decay = value / 1000.0
      if ctx.widgets.decayValue then
        ctx.widgets.decayValue:setText(formatTime(value))
      end
      ctx:notifyParent("decay", ctx.values.decay)
      ctx:drawGraph()
    end
  end
  
  -- Sustain knob
  if ctx.widgets.sustainKnob then
    ctx.widgets.sustainKnob.onChange = function(value)
      ctx.values.sustain = value / 100.0
      if ctx.widgets.sustainValue then
        ctx.widgets.sustainValue:setText(string.format("%.0f%%", value))
      end
      ctx:notifyParent("sustain", ctx.values.sustain)
      ctx:drawGraph()
    end
  end
  
  -- Release knob
  if ctx.widgets.releaseKnob then
    ctx.widgets.releaseKnob.onChange = function(value)
      ctx.values.release = value / 1000.0
      if ctx.widgets.releaseValue then
        ctx.widgets.releaseValue:setText(formatTime(value))
      end
      ctx:notifyParent("release", ctx.values.release)
      ctx:drawGraph()
    end
  end
  
  -- Initial graph draw
  ctx:drawGraph()
end

function EnvelopeBehavior.drawGraph(ctx)
  if not ctx.widgets.graph then return end
  
  local g = ctx.widgets.graph
  local w = g:getWidth()
  local h = g:getHeight()
  
  g:clear()
  
  -- Background
  g:setColor(0xFF0A0A1A)
  g:fillRect(0, 0, w, h)
  
  -- Grid lines
  g:setColor(0xFF1A1A3A)
  for i = 0, 4 do
    local x = (w / 4) * i
    g:drawLine(x, 0, x, h)
  end
  for i = 0, 4 do
    local y = (h / 4) * i
    g:drawLine(0, y, w, y)
  end
  
  -- Draw ADSR envelope
  local totalTime = ctx.values.attack + ctx.values.decay + 0.5 + ctx.values.release
  local attackX = (ctx.values.attack / totalTime) * w
  local decayX = attackX + (ctx.values.decay / totalTime) * w
  local sustainY = h - (ctx.values.sustain * (h - 20)) - 10
  local releaseX = decayX + (0.5 / totalTime) * w
  
  g:setColor(0xFFE94560)
  g:setLineWidth(2)
  
  -- Attack line
  g:drawLine(0, h - 10, attackX, 10)
  
  -- Decay line
  g:drawLine(attackX, 10, decayX, sustainY)
  
  -- Sustain line
  g:drawLine(decayX, sustainY, releaseX, sustainY)
  
  -- Release line
  g:drawLine(releaseX, sustainY, w, h - 10)
  
  -- Control points
  g:setColor(0xFFFFFFFF)
  g:fillCircle(attackX, 10, 4)
  g:fillCircle(decayX, sustainY, 4)
  g:fillCircle(releaseX, sustainY, 4)
  
  g:repaint()
end

function EnvelopeBehavior.onParamChange(ctx, name, value)
  if name == "attack" then
    ctx.values.attack = value
    if ctx.widgets.attackKnob then
      ctx.widgets.attackKnob:setValue(value * 1000)
    end
    if ctx.widgets.attackValue then
      ctx.widgets.attackValue:setText(string.format("%.0f ms", value * 1000))
    end
    ctx:drawGraph()
  elseif name == "decay" then
    ctx.values.decay = value
    if ctx.widgets.decayKnob then
      ctx.widgets.decayKnob:setValue(value * 1000)
    end
    if ctx.widgets.decayValue then
      ctx.widgets.decayValue:setText(string.format("%.0f ms", value * 1000))
    end
    ctx:drawGraph()
  elseif name == "sustain" then
    ctx.values.sustain = value
    if ctx.widgets.sustainKnob then
      ctx.widgets.sustainKnob:setValue(value * 100)
    end
    if ctx.widgets.sustainValue then
      ctx.widgets.sustainValue:setText(string.format("%.0f%%", value * 100))
    end
    ctx:drawGraph()
  elseif name == "release" then
    ctx.values.release = value
    if ctx.widgets.releaseKnob then
      ctx.widgets.releaseKnob:setValue(value * 1000)
    end
    if ctx.widgets.releaseValue then
      ctx.widgets.releaseValue:setText(string.format("%.0f ms", value * 1000))
    end
    ctx:drawGraph()
  end
end

function EnvelopeBehavior.notifyParent(ctx, paramName, value)
  local parent = ctx:getParent()
  if parent and parent.setParam then
    parent:setParam(paramName, value)
  end
end

return EnvelopeBehavior

-- Oscillator Behavior
-- Handles waveform selection and oscillator parameters

local OscillatorBehavior = {}

function OscillatorBehavior.onInit(ctx)
  -- Get widget references
  ctx.widgets = {
    waveformDropdown = ctx:getWidget("waveform_dropdown"),
    polyphonySlider = ctx:getWidget("polyphony_slider"),
    polyphonyValue = ctx:getWidget("polyphony_value"),
    unisonSlider = ctx:getWidget("unison_slider"),
    unisonValue = ctx:getWidget("unison_value"),
    detuneKnob = ctx:getWidget("detune_knob"),
    detuneValue = ctx:getWidget("detune_value"),
    glideKnob = ctx:getWidget("glide_knob"),
    glideValue = ctx:getWidget("glide_value"),
  }
  
  -- Current values
  ctx.values = {
    waveform = 0,
    polyphony = 8,
    unison = 1,
    detune = 0.0,
    glide = 0.0,
  }
  
  -- Set up callbacks
  if ctx.widgets.waveformDropdown then
    ctx.widgets.waveformDropdown.onChange = function(index)
      ctx.values.waveform = index
      ctx:notifyParent("waveform", index)
    end
  end
  
  if ctx.widgets.polyphonySlider then
    ctx.widgets.polyphonySlider.onChange = function(value)
      local intValue = math.floor(value + 0.5)
      ctx.values.polyphony = intValue
      if ctx.widgets.polyphonyValue then
        ctx.widgets.polyphonyValue:setText(tostring(intValue))
      end
      ctx:notifyParent("polyphony", intValue)
    end
  end
  
  if ctx.widgets.unisonSlider then
    ctx.widgets.unisonSlider.onChange = function(value)
      local intValue = math.floor(value + 0.5)
      ctx.values.unison = intValue
      if ctx.widgets.unisonValue then
        ctx.widgets.unisonValue:setText(tostring(intValue))
      end
      ctx:notifyParent("unison", intValue)
    end
  end
  
  if ctx.widgets.detuneKnob then
    ctx.widgets.detuneKnob.onChange = function(value)
      ctx.values.detune = value
      if ctx.widgets.detuneValue then
        ctx.widgets.detuneValue:setText(string.format("%.0f ct", value))
      end
      ctx:notifyParent("detune", value)
    end
  end
  
  if ctx.widgets.glideKnob then
    ctx.widgets.glideKnob.onChange = function(value)
      ctx.values.glide = value / 1000.0  -- Convert ms to seconds
      if ctx.widgets.glideValue then
        if value < 1000 then
          ctx.widgets.glideValue:setText(string.format("%.0f ms", value))
        else
          ctx.widgets.glideValue:setText(string.format("%.1f s", value / 1000))
        end
      end
      ctx:notifyParent("glide", ctx.values.glide)
    end
  end
end

function OscillatorBehavior.onParamChange(ctx, name, value)
  if name == "waveform" then
    ctx.values.waveform = value
    if ctx.widgets.waveformDropdown then
      ctx.widgets.waveformDropdown:setSelected(math.floor(value))
    end
  elseif name == "polyphony" then
    ctx.values.polyphony = value
    if ctx.widgets.polyphonySlider then
      ctx.widgets.polyphonySlider:setValue(value)
    end
    if ctx.widgets.polyphonyValue then
      ctx.widgets.polyphonyValue:setText(tostring(math.floor(value)))
    end
  elseif name == "unison" then
    ctx.values.unison = value
    if ctx.widgets.unisonSlider then
      ctx.widgets.unisonSlider:setValue(value)
    end
    if ctx.widgets.unisonValue then
      ctx.widgets.unisonValue:setText(tostring(math.floor(value)))
    end
  elseif name == "detune" then
    ctx.values.detune = value
    if ctx.widgets.detuneKnob then
      ctx.widgets.detuneKnob:setValue(value)
    end
    if ctx.widgets.detuneValue then
      ctx.widgets.detuneValue:setText(string.format("%.0f ct", value))
    end
  elseif name == "glide" then
    ctx.values.glide = value
    if ctx.widgets.glideKnob then
      ctx.widgets.glideKnob:setValue(value * 1000)  -- Convert seconds to ms
    end
  end
end

function OscillatorBehavior.notifyParent(ctx, paramName, value)
  local parent = ctx:getParent()
  if parent and parent.setParam then
    parent:setParam(paramName, value)
  end
end

return OscillatorBehavior

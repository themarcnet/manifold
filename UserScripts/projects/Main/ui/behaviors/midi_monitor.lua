-- MIDI Monitor Behavior
-- Displays incoming MIDI activity

local MidiMonitorBehavior = {}

function MidiMonitorBehavior.onInit(ctx)
  ctx.widgets = {
    eventList = ctx:getWidget("event_list"),
    activityLed = ctx:getWidget("activity_led"),
  }
  
  ctx.state = {
    events = {},
    maxEvents = 7,
    activityTimer = 0,
    noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"},
  }
  
  -- Initial empty state
  ctx:updateDisplay()
end

function MidiMonitorBehavior.onUpdate(ctx)
  -- Handle activity LED
  if ctx.state.activityTimer > 0 then
    ctx.state.activityTimer = ctx.state.activityTimer - 1
    if ctx.state.activityTimer <= 0 then
      ctx:setActivityLed(false)
    end
  end
end

function MidiMonitorBehavior.onMidiEvent(ctx, eventType, channel, data1, data2)
  -- Flash activity LED
  ctx:setActivityLed(true)
  ctx.state.activityTimer = 10  -- Frames
  
  -- Format event text
  local text = ctx:formatEvent(eventType, channel, data1, data2)
  
  -- Add to event list
  table.insert(ctx.state.events, 1, {
    text = text,
    time = os.time(),
  })
  
  -- Trim to max size
  while #ctx.state.events > ctx.state.maxEvents do
    table.remove(ctx.state.events)
  end
  
  ctx:updateDisplay()
end

function MidiMonitorBehavior.formatEvent(ctx, eventType, channel, data1, data2)
  local ch = string.format("Ch%02d", channel)
  
  if eventType == "NOTE_ON" then
    local note = ctx:formatNote(data1)
    local vel = string.format("V%03d", data2)
    return string.format("%-4s %-8s %s %s", ch, "NOTE ON", note, vel)
  elseif eventType == "NOTE_OFF" then
    local note = ctx:formatNote(data1)
    return string.format("%-4s %-8s %s", ch, "NOTE OFF", note)
  elseif eventType == "CC" then
    local ccName = ctx:getCCName(data1)
    return string.format("%-4s CC %03d %s = %03d", ch, data1, ccName, data2)
  elseif eventType == "PITCH_BEND" then
    return string.format("%-4s PITCH %d", ch, data1 - 8192)
  elseif eventType == "PROGRAM_CHANGE" then
    return string.format("%-4s PROGRAM %03d", ch, data1)
  else
    return string.format("%-4s %s", ch, eventType)
  end
end

function MidiMonitorBehavior.formatNote(ctx, note)
  local octave = math.floor(note / 12) - 1
  local noteName = ctx.state.noteNames[(note % 12) + 1]
  return string.format("%s%d", noteName, octave)
end

function MidiMonitorBehavior.getCCName(ctx, cc)
  local ccNames = {
    [1] = "Mod",
    [7] = "Vol",
    [10] = "Pan",
    [11] = "Expr",
    [64] = "Sustain",
    [71] = "Res",
    [72] = "Rel",
    [73] = "Atk",
    [74] = "Cutoff",
  }
  return ccNames[cc] or ""
end

function MidiMonitorBehavior.updateDisplay(ctx)
  if not ctx.widgets.eventList then return end
  
  local items = {}
  for _, event in ipairs(ctx.state.events) do
    table.insert(items, event.text)
  end
  
  -- Fill with empty lines if needed
  while #items < ctx.state.maxEvents do
    table.insert(items, "")
  end
  
  ctx.widgets.eventList:setItems(items)
end

function MidiMonitorBehavior.setActivityLed(ctx, active)
  if not ctx.widgets.activityLed then return end
  
  if active then
    ctx.widgets.activityLed:setStyle({
      bg = 0xFF00FF00,
      radius = 6,
    })
  else
    ctx.widgets.activityLed:setStyle({
      bg = 0xFF333333,
      radius = 6,
    })
  end
end

return MidiMonitorBehavior

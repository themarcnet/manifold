-- Keyboard Behavior
-- Virtual piano keyboard with mouse/touch input

local KeyboardBehavior = {}

function KeyboardBehavior.onInit(ctx)
  ctx.widgets = {
    canvas = ctx:getWidget("keyboard_canvas"),
    octaveLabel = ctx:getWidget("octave_label"),
    octaveDown = ctx:getWidget("octave_down"),
    octaveUp = ctx:getWidget("octave_up"),
    velocitySlider = ctx:getWidget("velocity_slider"),
  }
  
  ctx.state = {
    baseOctave = 3,  -- C3
    velocity = 100,
    pressedKeys = {},  -- Track which keys are currently pressed
    whiteKeyWidth = 0,
    blackKeyWidth = 0,
    keyHeight = 0,
  }
  
  -- Note layout (7 white keys per octave)
  ctx.whiteNotes = {0, 2, 4, 5, 7, 9, 11}  -- C, D, E, F, G, A, B
  ctx.blackNotes = {1, 3, 6, 8, 10}         -- C#, D#, F#, G#, A#
  ctx.blackKeyPositions = {0, 1, 3, 4, 5}   -- Which white key gaps have black keys
  
  -- Calculate key dimensions
  ctx:calculateDimensions()
  
  -- Set up canvas input
  if ctx.widgets.canvas then
    ctx.widgets.canvas:setInterceptsMouse(true, false)
    
    ctx.widgets.canvas.onMouseDown = function(x, y)
      ctx:handleMouseDown(x, y)
    end
    
    ctx.widgets.canvas.onMouseUp = function(x, y)
      ctx:handleMouseUp(x, y)
    end
    
    ctx.widgets.canvas.onMouseDrag = function(x, y)
      ctx:handleMouseDrag(x, y)
    end
    
    ctx.widgets.canvas.onPaint = function()
      ctx:drawKeyboard()
    end
  end
  
  -- Octave controls
  if ctx.widgets.octaveDown then
    ctx.widgets.octaveDown.onClick = function()
      ctx.state.baseOctave = math.max(0, ctx.state.baseOctave - 1)
      ctx:updateOctaveLabel()
      ctx:drawKeyboard()
    end
  end
  
  if ctx.widgets.octaveUp then
    ctx.widgets.octaveUp.onClick = function()
      ctx.state.baseOctave = math.min(7, ctx.state.baseOctave + 1)
      ctx:updateOctaveLabel()
      ctx:drawKeyboard()
    end
  end
  
  -- Velocity slider
  if ctx.widgets.velocitySlider then
    ctx.widgets.velocitySlider.onChange = function(value)
      ctx.state.velocity = math.floor(value + 0.5)
    end
  end
  
  -- Initial draw
  ctx:updateOctaveLabel()
  ctx:drawKeyboard()
end

function KeyboardBehavior.calculateDimensions(ctx)
  if not ctx.widgets.canvas then return end
  
  local w = ctx.widgets.canvas:getWidth()
  local h = ctx.widgets.canvas:getHeight()
  
  -- 5 octaves * 7 white keys = 35 white keys
  ctx.state.whiteKeyWidth = w / 35
  ctx.state.blackKeyWidth = ctx.state.whiteKeyWidth * 0.6
  ctx.state.keyHeight = h
end

function KeyboardBehavior.updateOctaveLabel(ctx)
  if ctx.widgets.octaveLabel then
    local noteNames = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    ctx.widgets.octaveLabel:setText("Octave: " .. noteNames[1] .. ctx.state.baseOctave)
  end
end

function KeyboardBehavior.drawKeyboard(ctx)
  if not ctx.widgets.canvas then return end
  
  local g = ctx.widgets.canvas
  local w = g:getWidth()
  local h = g:getHeight()
  
  g:clear()
  
  local numOctaves = 5
  local totalWhiteKeys = numOctaves * 7
  local whiteKeyW = w / totalWhiteKeys
  local blackKeyW = whiteKeyW * 0.6
  
  -- Draw white keys
  for octave = 0, numOctaves - 1 do
    for i = 1, 7 do
      local keyIndex = octave * 7 + i - 1
      local x = keyIndex * whiteKeyW
      local note = (ctx.state.baseOctave + octave) * 12 + ctx.whiteNotes[i]
      local isPressed = ctx.state.pressedKeys[note]
      
      -- Key color
      if isPressed then
        g:setColor(0xFFE94560)  -- Pressed color
      else
        g:setColor(0xFFFFFFFF)  -- White key
      end
      
      g:fillRect(x, 0, whiteKeyW - 1, h)
      
      -- Border
      g:setColor(0xFFAAAAAA)
      g:drawRect(x, 0, whiteKeyW - 1, h)
    end
  end
  
  -- Draw black keys
  for octave = 0, numOctaves - 1 do
    for i = 1, 5 do
      local whiteKeyIndex = octave * 7 + ctx.blackKeyPositions[i]
      local x = (whiteKeyIndex + 0.7) * whiteKeyW
      local note = (ctx.state.baseOctave + octave) * 12 + ctx.blackNotes[i]
      local isPressed = ctx.state.pressedKeys[note]
      
      -- Key color
      if isPressed then
        g:setColor(0xFFFF6B8A)  -- Pressed color (lighter)
      else
        g:setColor(0xFF1A1A2E)  -- Black key
      end
      
      g:fillRect(x, 0, blackKeyW, h * 0.6)
      
      -- Border
      g:setColor(0xFF000000)
      g:drawRect(x, 0, blackKeyW, h * 0.6)
    end
  end
  
  g:repaint()
end

function KeyboardBehavior.getNoteAtPosition(ctx, x, y)
  if not ctx.widgets.canvas then return nil end
  
  local w = ctx.widgets.canvas:getWidth()
  local h = ctx.widgets.canvas:getHeight()
  local numOctaves = 5
  local totalWhiteKeys = numOctaves * 7
  local whiteKeyW = w / totalWhiteKeys
  local blackKeyW = whiteKeyW * 0.6
  
  -- Check black keys first (they're on top)
  for octave = 0, numOctaves - 1 do
    for i = 1, 5 do
      local whiteKeyIndex = octave * 7 + ctx.blackKeyPositions[i]
      local keyX = (whiteKeyIndex + 0.7) * whiteKeyW
      
      if x >= keyX and x < keyX + blackKeyW and y < h * 0.6 then
        return (ctx.state.baseOctave + octave) * 12 + ctx.blackNotes[i]
      end
    end
  end
  
  -- Check white keys
  local whiteKeyIndex = math.floor(x / whiteKeyW)
  local octave = math.floor(whiteKeyIndex / 7)
  local noteInOctave = (whiteKeyIndex % 7) + 1
  
  if octave < numOctaves then
    return (ctx.state.baseOctave + octave) * 12 + ctx.whiteNotes[noteInOctave]
  end
  
  return nil
end

function KeyboardBehavior.handleMouseDown(ctx, x, y)
  local note = ctx:getNoteAtPosition(x, y)
  if note then
    ctx:triggerNoteOn(note)
  end
end

function KeyboardBehavior.handleMouseUp(ctx, x, y)
  -- Release all held keys
  for note, _ in pairs(ctx.state.pressedKeys) do
    ctx:triggerNoteOff(note)
  end
end

function KeyboardBehavior.handleMouseDrag(ctx, x, y)
  local note = ctx:getNoteAtPosition(x, y)
  
  -- Check if we moved to a different key
  local currentNote = nil
  for n, _ in pairs(ctx.state.pressedKeys) do
    currentNote = n
    break
  end
  
  if note and note ~= currentNote then
    -- Release old note, press new
    if currentNote then
      ctx:triggerNoteOff(currentNote)
    end
    ctx:triggerNoteOn(note)
  end
end

function KeyboardBehavior.triggerNoteOn(ctx, note)
  if ctx.state.pressedKeys[note] then return end  -- Already pressed
  
  ctx.state.pressedKeys[note] = true
  ctx:drawKeyboard()
  
  -- Send MIDI note on
  if Midi then
    -- Send on channel 1
    Midi.sendNoteOn(1, note, ctx.state.velocity)
  end
end

function KeyboardBehavior.triggerNoteOff(ctx, note)
  if not ctx.state.pressedKeys[note] then return end  -- Not pressed
  
  ctx.state.pressedKeys[note] = nil
  ctx:drawKeyboard()
  
  -- Send MIDI note off
  if Midi then
    Midi.sendNoteOff(1, note)
  end
end

function KeyboardBehavior.onMidiNoteOn(ctx, note, velocity)
  ctx.state.pressedKeys[note] = true
  ctx:drawKeyboard()
end

function KeyboardBehavior.onMidiNoteOff(ctx, note)
  ctx.state.pressedKeys[note] = nil
  ctx:drawKeyboard()
end

return KeyboardBehavior

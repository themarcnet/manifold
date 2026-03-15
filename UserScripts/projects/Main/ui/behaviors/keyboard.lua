-- Keyboard Behavior
-- Virtual piano keyboard with mouse/touch input
-- Migrated to RuntimeNode display list pattern

local KeyboardBehavior = {}

-- Color constants (ARGB format)
local COLORS = {
  whiteKey = 0xFFFFFFFF,
  whiteKeyPressed = 0xFFE94560,
  blackKey = 0xFF1A1A2E,
  blackKeyPressed = 0xFFFF6B8A,
  whiteKeyBorder = 0xFFAAAAAA,
  blackKeyBorder = 0xFF000000,
}

-- Build display list for the keyboard
local function buildKeyboardDisplay(ctx, w, h)
  local display = {}
  local numOctaves = 5
  local totalWhiteKeys = numOctaves * 7
  local whiteKeyW = w / totalWhiteKeys
  local blackKeyW = whiteKeyW * 0.6
  
  -- Draw white keys first (bottom layer)
  for octave = 0, numOctaves - 1 do
    for i = 1, 7 do
      local keyIndex = octave * 7 + i - 1
      local x = math.floor(keyIndex * whiteKeyW)
      local note = (ctx.state.baseOctave + octave) * 12 + ctx.whiteNotes[i]
      local isPressed = ctx.state.pressedKeys[note]
      
      -- Key fill
      local color = isPressed and COLORS.whiteKeyPressed or COLORS.whiteKey
      display[#display + 1] = {
        cmd = "fillRect",
        x = x,
        y = 0,
        w = math.floor(whiteKeyW - 1),
        h = h,
        color = color,
      }
      
      -- Key border
      display[#display + 1] = {
        cmd = "drawRect",
        x = x,
        y = 0,
        w = math.floor(whiteKeyW - 1),
        h = h,
        thickness = 1,
        color = COLORS.whiteKeyBorder,
      }
    end
  end
  
  -- Draw black keys on top
  for octave = 0, numOctaves - 1 do
    for i = 1, 5 do
      local whiteKeyIndex = octave * 7 + ctx.blackKeyPositions[i]
      local x = math.floor((whiteKeyIndex + 0.7) * whiteKeyW)
      local note = (ctx.state.baseOctave + octave) * 12 + ctx.blackNotes[i]
      local isPressed = ctx.state.pressedKeys[note]
      local keyH = math.floor(h * 0.6)
      
      -- Key fill
      local color = isPressed and COLORS.blackKeyPressed or COLORS.blackKey
      display[#display + 1] = {
        cmd = "fillRect",
        x = x,
        y = 0,
        w = math.floor(blackKeyW),
        h = keyH,
        color = color,
      }
      
      -- Key border
      display[#display + 1] = {
        cmd = "drawRect",
        x = x,
        y = 0,
        w = math.floor(blackKeyW),
        h = keyH,
        thickness = 1,
        color = COLORS.blackKeyBorder,
      }
    end
  end
  
  return display
end

-- Draw keyboard using Canvas immediate mode (for Canvas renderer)
local function drawKeyboardCanvas(ctx, w, h)
  local numOctaves = 5
  local totalWhiteKeys = numOctaves * 7
  local whiteKeyW = w / totalWhiteKeys
  local blackKeyW = whiteKeyW * 0.6
  
  gfx.setColour(COLORS.whiteKey)
  
  -- Draw white keys
  for octave = 0, numOctaves - 1 do
    for i = 1, 7 do
      local keyIndex = octave * 7 + i - 1
      local x = keyIndex * whiteKeyW
      local note = (ctx.state.baseOctave + octave) * 12 + ctx.whiteNotes[i]
      local isPressed = ctx.state.pressedKeys[note]
      
      -- Key color
      if isPressed then
        gfx.setColour(COLORS.whiteKeyPressed)
      else
        gfx.setColour(COLORS.whiteKey)
      end
      
      gfx.fillRect(x, 0, whiteKeyW - 1, h)
      
      -- Border
      gfx.setColour(COLORS.whiteKeyBorder)
      gfx.drawRect(x, 0, whiteKeyW - 1, h)
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
        gfx.setColour(COLORS.blackKeyPressed)
      else
        gfx.setColour(COLORS.blackKey)
      end
      
      gfx.fillRect(x, 0, blackKeyW, h * 0.6)
      
      -- Border
      gfx.setColour(COLORS.blackKeyBorder)
      gfx.drawRect(x, 0, blackKeyW, h * 0.6)
    end
  end
end

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
    pressedKeys = {},
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
  
  -- Set up canvas input using RuntimeNode methods
  if ctx.widgets.canvas then
    local canvas = ctx.widgets.canvas
    
    -- Set input capabilities
    if canvas.setInterceptsMouse then
      canvas:setInterceptsMouse(true, false)
    end
    if canvas.setInputCapabilities then
      canvas:setInputCapabilities({
        pointer = true,
        wheel = false,
        keyboard = false,
        focusable = false,
      })
    end
    
    -- Mouse callbacks using RuntimeNode methods (not property assignment)
    if canvas.setOnMouseDown then
      canvas:setOnMouseDown(function(mx, my)
        ctx:handleMouseDown(mx, my)
      end)
    end
    
    if canvas.setOnMouseUp then
      canvas:setOnMouseUp(function(mx, my)
        ctx:handleMouseUp(mx, my)
      end)
    end
    
    if canvas.setOnMouseDrag then
      canvas:setOnMouseDrag(function(mx, my, dx, dy)
        ctx:handleMouseDrag(mx, my)
      end)
    end
    
    -- Set up rendering
    if canvas.setOnDraw then
      -- Canvas mode: immediate rendering
      canvas:setOnDraw(function(node)
        local w = node:getWidth()
        local h = node:getHeight()
        drawKeyboardCanvas(ctx, w, h)
      end)
    end
    
    -- RuntimeNode mode: retained display list
    ctx:refreshKeyboardDisplay()
  end
  
  -- Octave controls
  if ctx.widgets.octaveDown then
    ctx.widgets.octaveDown.onClick = function()
      ctx.state.baseOctave = math.max(0, ctx.state.baseOctave - 1)
      ctx:updateOctaveLabel()
      ctx:refreshKeyboardDisplay()
    end
  end
  
  if ctx.widgets.octaveUp then
    ctx.widgets.octaveUp.onClick = function()
      ctx.state.baseOctave = math.min(7, ctx.state.baseOctave + 1)
      ctx:updateOctaveLabel()
      ctx:refreshKeyboardDisplay()
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
  ctx:refreshKeyboardDisplay()
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

function KeyboardBehavior.refreshKeyboardDisplay(ctx)
  if not ctx.widgets.canvas then return end
  
  local canvas = ctx.widgets.canvas
  local w = canvas:getWidth()
  local h = canvas:getHeight()
  
  -- Set transparent style for RuntimeNode
  if canvas.setStyle then
    canvas:setStyle({
      bg = 0x00000000,
      border = 0x00000000,
      borderWidth = 0,
      radius = 0,
      opacity = 1.0,
    })
  end
  
  -- Set display list for RuntimeNode mode
  if canvas.setDisplayList then
    canvas:setDisplayList(buildKeyboardDisplay(ctx, w, h))
  end
  
  -- Trigger repaint for Canvas mode
  if canvas.repaint then
    canvas:repaint()
  end
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
  ctx:refreshKeyboardDisplay()
  
  -- Send MIDI note on
  if Midi then
    Midi.sendNoteOn(1, note, ctx.state.velocity)
  end
end

function KeyboardBehavior.triggerNoteOff(ctx, note)
  if not ctx.state.pressedKeys[note] then return end  -- Not pressed
  
  ctx.state.pressedKeys[note] = nil
  ctx:refreshKeyboardDisplay()
  
  -- Send MIDI note off
  if Midi then
    Midi.sendNoteOff(1, note)
  end
end

function KeyboardBehavior.onMidiNoteOn(ctx, note, velocity)
  ctx.state.pressedKeys[note] = true
  ctx:refreshKeyboardDisplay()
end

function KeyboardBehavior.onMidiNoteOff(ctx, note)
  ctx.state.pressedKeys[note] = nil
  ctx:refreshKeyboardDisplay()
end

return KeyboardBehavior

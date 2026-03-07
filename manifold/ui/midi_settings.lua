-- MIDI Settings UI
-- Configuration panel for MIDI input/output and monitoring

local midiSettings = {
  id = "midi_settings",
  type = "Panel",
  x = 0, y = 0,
  w = 600, h = 400,
  style = {
    bg = 0xFF1A1A2E,
    border = 0xFF0F3460,
    borderWidth = 2,
    radius = 8,
  },
  children = {
    -- Title
    {
      id = "title",
      type = "Label",
      x = 20, y = 20,
      w = 560, h = 30,
      text = "MIDI Settings",
      style = {
        fontSize = 20,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    
    -- Input Devices Section
    {
      id = "input_label",
      type = "Label",
      x = 20, y = 60,
      w = 200, h = 20,
      text = "MIDI Input",
      style = {
        fontSize = 14,
        textColor = 0xFFFFFFFF,
        fontFlags = 1,
      }
    },
    {
      id = "input_dropdown",
      type = "Dropdown",
      x = 20, y = 85,
      w = 300, h = 30,
      items = {},
      style = {
        bg = 0xFF16213E,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "input_refresh",
      type = "Button",
      x = 330, y = 85,
      w = 80, h = 30,
      text = "Refresh",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    
    -- Output Devices Section
    {
      id = "output_label",
      type = "Label",
      x = 20, y = 130,
      w = 200, h = 20,
      text = "MIDI Output",
      style = {
        fontSize = 14,
        textColor = 0xFFFFFFFF,
        fontFlags = 1,
      }
    },
    {
      id = "output_dropdown",
      type = "Dropdown",
      x = 20, y = 155,
      w = 300, h = 30,
      items = {},
      style = {
        bg = 0xFF16213E,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "output_refresh",
      type = "Button",
      x = 330, y = 155,
      w = 80, h = 30,
      text = "Refresh",
      style = {
        bg = 0xFF0F3460,
        textColor = 0xFFFFFFFF,
      }
    },
    
    -- Channel Filter
    {
      id = "channel_label",
      type = "Label",
      x = 20, y = 200,
      w = 200, h = 20,
      text = "Channel Filter",
      style = {
        fontSize = 14,
        textColor = 0xFFFFFFFF,
        fontFlags = 1,
      }
    },
    {
      id = "omni_toggle",
      type = "Toggle",
      x = 20, y = 225,
      w = 120, h = 24,
      text = "Omni Mode",
      value = true,
    },
    {
      id = "channel_slider",
      type = "Slider",
      x = 150, y = 225,
      w = 200, h = 24,
      min = 1, max = 16,
      value = 1,
      style = {
        trackColor = 0xFF0F3460,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "channel_value",
      type = "Label",
      x = 360, y = 227,
      w = 50, h = 20,
      text = "Ch 1",
      style = {
        textColor = 0xFFAAAAAA,
        fontSize = 12,
      }
    },
    
    -- MIDI Thru
    {
      id = "thru_toggle",
      type = "Toggle",
      x = 20, y = 265,
      w = 150, h = 24,
      text = "MIDI Thru",
      value = false,
    },
    
    -- Activity Monitor
    {
      id = "activity_label",
      type = "Label",
      x = 20, y = 310,
      w = 200, h = 20,
      text = "MIDI Activity",
      style = {
        fontSize = 14,
        textColor = 0xFFFFFFFF,
        fontFlags = 1,
      }
    },
    {
      id = "activity_led",
      type = "Panel",
      x = 150, y = 312,
      w = 16, h = 16,
      style = {
        bg = 0xFF333333,
        radius = 8,
      }
    },
    {
      id = "last_event",
      type = "Label",
      x = 180, y = 310,
      w = 400, h = 20,
      text = "No activity",
      style = {
        fontSize = 12,
        textColor = 0xFFAAAAAA,
      }
    },
    
    -- Test Button
    {
      id = "test_btn",
      type = "Button",
      x = 20, y = 350,
      w = 120, h = 36,
      text = "Send Test Note",
      style = {
        bg = 0xFFE94560,
        textColor = 0xFFFFFFFF,
      }
    },
    {
      id = "panic_btn",
      type = "Button",
      x = 150, y = 350,
      w = 100, h = 36,
      text = "All Notes Off",
      style = {
        bg = 0xFF662222,
        textColor = 0xFFFFFFFF,
      }
    },
  }
}

-- Behavior
function midiSettings.onInit(ctx)
  ctx.widgets = {
    inputDropdown = ctx:getWidget("input_dropdown"),
    outputDropdown = ctx:getWidget("output_dropdown"),
    omniToggle = ctx:getWidget("omni_toggle"),
    channelSlider = ctx:getWidget("channel_slider"),
    channelValue = ctx:getWidget("channel_value"),
    thruToggle = ctx:getWidget("thru_toggle"),
    activityLed = ctx:getWidget("activity_led"),
    lastEvent = ctx:getWidget("last_event"),
    testBtn = ctx:getWidget("test_btn"),
    panicBtn = ctx:getWidget("panic_btn"),
  }
  
  -- Refresh device lists
  ctx:refreshDevices()
  
  -- Set up callbacks
  if ctx.widgets.omniToggle then
    ctx.widgets.omniToggle.onChange = function(value)
      if Midi then
        Midi.setOmniMode(value)
      end
      if ctx.widgets.channelSlider then
        ctx.widgets.channelSlider:setEnabled(not value)
      end
    end
  end
  
  if ctx.widgets.channelSlider then
    ctx.widgets.channelSlider.onChange = function(value)
      local ch = math.floor(value)
      if ctx.widgets.channelValue then
        ctx.widgets.channelValue:setText("Ch " .. ch)
      end
      if Midi then
        Midi.setChannelFilter(ch)
      end
    end
  end
  
  if ctx.widgets.thruToggle then
    ctx.widgets.thruToggle.onChange = function(value)
      if Midi then
        Midi.thruEnabled(value)
      end
    end
  end
  
  if ctx.widgets.testBtn then
    ctx.widgets.testBtn.onClick = function()
      if Midi then
        -- Send C4 note
        Midi.sendNoteOn(1, 60, 100)
        ctx:showActivity("Sent Note On: C4")
        -- Schedule note off
        ctx:schedule(function()
          Midi.sendNoteOff(1, 60)
          ctx:showActivity("Sent Note Off: C4")
        end, 0.5)
      end
    end
  end
  
  if ctx.widgets.panicBtn then
    ctx.widgets.panicBtn.onClick = function()
      if Midi then
        for ch = 1, 16 do
          Midi.sendAllNotesOff(ch)
        end
        ctx:showActivity("All Notes Off sent")
      end
    end
  end
  
  -- Set up MIDI monitoring
  if Midi then
    Midi.onNoteOn(function(channel, note, velocity, timestamp)
      local noteName = Midi.noteName(note)
      local octave = math.floor(note / 12) - 1
      ctx:showActivity(string.format("Note On: %s%d (vel %d) ch%d", noteName, octave, velocity, channel))
    end)
    
    Midi.onNoteOff(function(channel, note, timestamp)
      local noteName = Midi.noteName(note)
      local octave = math.floor(note / 12) - 1
      ctx:showActivity(string.format("Note Off: %s%d ch%d", noteName, octave, channel))
    end)
    
    Midi.onControlChange(function(channel, cc, value, timestamp)
      ctx:showActivity(string.format("CC %d = %d ch%d", cc, value, channel))
    end)
  end
end

function midiSettings.refreshDevices(ctx)
  if not Midi then return end
  
  local inputs = Midi.inputDevices()
  if ctx.widgets.inputDropdown then
    ctx.widgets.inputDropdown:clear()
    for i, device in ipairs(inputs) do
      ctx.widgets.inputDropdown:addItem(device)
    end
  end
  
  local outputs = Midi.outputDevices()
  if ctx.widgets.outputDropdown then
    ctx.widgets.outputDropdown:clear()
    for i, device in ipairs(outputs) do
      ctx.widgets.outputDropdown:addItem(device)
    end
  end
end

function midiSettings.showActivity(ctx, text)
  if ctx.widgets.lastEvent then
    ctx.widgets.lastEvent:setText(text)
  end
  if ctx.widgets.activityLed then
    ctx.widgets.activityLed:setStyle({bg = 0xFF00FF00, radius = 8})
    ctx:schedule(function()
      if ctx.widgets.activityLed then
        ctx.widgets.activityLed:setStyle({bg = 0xFF333333, radius = 8})
      end
    end, 0.1)
  end
end

return midiSettings

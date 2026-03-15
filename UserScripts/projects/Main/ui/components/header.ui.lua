-- Header Panel UI
-- Title, master controls, and transport

return {
  type = "Panel",
  style = {
    bg = 0xFF0F3460,
  },
  children = {
    {
      id = "title",
      type = "Label",
      x = 20, y = 15,
      w = 300, h = 30,
      text = "MIDI SYNTH",
      style = {
        fontSize = 24,
        textColor = 0xFFFFFFFF,
        fontFlags = 1,
      }
    },
    {
      id = "subtitle",
      type = "Label",
      x = 20, y = 40,
      w = 300, h = 16,
      text = "Polyphonic Synthesizer",
      style = {
        fontSize = 12,
        textColor = 0xFFAAAAAA,
      }
    },
    -- Voice counter
    {
      id = "voices_label",
      type = "Label",
      x = 350, y = 20,
      w = 100, h = 20,
      text = "Voices:",
      style = {
        fontSize = 12,
        textColor = 0xFFAAAAAA,
      }
    },
    {
      id = "voices_value",
      type = "Label",
      x = 410, y = 20,
      w = 40, h = 20,
      text = "0",
      style = {
        fontSize = 16,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    -- MIDI Input indicator
    {
      id = "midi_label",
      type = "Label",
      x = 500, y = 20,
      w = 80, h = 20,
      text = "MIDI IN:",
      style = {
        fontSize = 12,
        textColor = 0xFFAAAAAA,
      }
    },
    {
      id = "midi_indicator",
      type = "Panel",
      x = 570, y = 22,
      w = 16, h = 16,
      style = {
        bg = 0xFF333333,
        radius = 8,
      }
    },
    -- Master volume
    {
      id = "volume_label",
      type = "Label",
      x = 650, y = 20,
      w = 60, h = 20,
      text = "Master",
      style = {
        fontSize = 12,
        textColor = 0xFFAAAAAA,
      }
    },
    {
      id = "volume_slider",
      type = "Slider",
      x = 710, y = 18,
      w = 150, h = 24,
      min = 0, max = 100,
      value = 70,
      style = {
        trackColor = 0xFF1A1A2E,
        fillColor = 0xFFE94560,
      }
    },
    {
      id = "volume_value",
      type = "Label",
      x = 870, y = 20,
      w = 50, h = 20,
      text = "70%",
      style = {
        fontSize = 12,
        textColor = 0xFFFFFFFF,
      }
    },
    -- All Notes Off button
    {
      id = "panic_btn",
      type = "Button",
      x = 1000, y = 12,
      w = 80, h = 36,
      text = "PANIC",
      style = {
        bg = 0xFFE94560,
        textColor = 0xFFFFFFFF,
        fontSize = 12,
        radius = 4,
      }
    },
    -- Settings button
    {
      id = "settings_btn",
      type = "Button",
      x = 1100, y = 12,
      w = 80, h = 36,
      text = "Settings",
      style = {
        bg = 0xFF16213E,
        textColor = 0xFFFFFFFF,
        fontSize = 12,
        radius = 4,
      }
    },
  }
}

-- MIDI Monitor UI
-- Displays incoming MIDI events in real-time

return {
  type = "Panel",
  style = {
    bg = 0xFF16213E,
    border = 0xFF0F3460,
    borderWidth = 1,
    radius = 8,
  },
  children = {
    {
      id = "title",
      type = "Label",
      x = 10, y = 8,
      w = 200, h = 20,
      text = "MIDI MONITOR",
      style = {
        fontSize = 14,
        textColor = 0xFFE94560,
        fontFlags = 1,
      }
    },
    {
      id = "activity_led",
      type = "Panel",
      x = 240, y = 10,
      w = 12, h = 12,
      style = {
        bg = 0xFF333333,
        radius = 6,
      }
    },
    -- Event list
    {
      id = "event_list",
      type = "List",
      x = 10, y = 35,
      w = 260, h = 145,
      style = {
        bg = 0xFF0A0A1A,
        itemHeight = 20,
        textColor = 0xFFFFFFFF,
        fontSize = 11,
      }
    },
  }
}

return {
  id = "perf_overlay_root",
  type = "Panel",
  x = 0, y = 0, w = 472, h = 208,
  style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
  children = {
    -- Background
    { id = "perf_bg", type = "Panel", x = 120, y = 100, w = 340, h = 100,
      style = { bg = 0xdd0f172a, radius = 4 } },
    
    -- Title
    { id = "perf_title", type = "Label", x = 128, y = 106, w = 120, h = 14,
      props = { text = "Memory Profile" },
      style = { colour = 0xffa78bfa, fontSize = 10, bg = 0x00000000 } },
    
    -- Row 1: PSS | Priv | Lua
    { id = "lbl_pss", type = "Label", x = 128, y = 126, w = 30, h = 12, props = { text = "PSS" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_pss", type = "Label", x = 162, y = 126, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_priv", type = "Label", x = 230, y = 126, w = 30, h = 12, props = { text = "Priv" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_priv", type = "Label", x = 264, y = 126, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_lua", type = "Label", x = 332, y = 126, w = 30, h = 12, props = { text = "Lua" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_lua", type = "Label", x = 366, y = 126, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    -- Row 2: Heap | Arena | Mmap
    { id = "lbl_heap", type = "Label", x = 128, y = 142, w = 30, h = 12, props = { text = "Heap" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_heap", type = "Label", x = 162, y = 142, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_arena", type = "Label", x = 230, y = 142, w = 30, h = 12, props = { text = "Arena" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_arena", type = "Label", x = 264, y = 142, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_mmap", type = "Label", x = 332, y = 142, w = 30, h = 12, props = { text = "Mmap" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_mmap", type = "Label", x = 366, y = 142, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    -- Row 3: Free | Rel | Ar#
    { id = "lbl_free", type = "Label", x = 128, y = 158, w = 30, h = 12, props = { text = "Free" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_free", type = "Label", x = 162, y = 158, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_rel", type = "Label", x = 230, y = 158, w = 30, h = 12, props = { text = "Rel" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_rel", type = "Label", x = 264, y = 158, w = 60, h = 12, props = { text = "0.0 MB" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_ar", type = "Label", x = 332, y = 158, w = 30, h = 12, props = { text = "Ar#" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ar", type = "Label", x = 366, y = 158, w = 60, h = 12, props = { text = "0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    
    -- Row 4: Frame | Avg | CPU
    { id = "lbl_frame", type = "Label", x = 128, y = 176, w = 30, h = 12, props = { text = "Frm" }, style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
    { id = "val_frame", type = "Label", x = 162, y = 176, w = 60, h = 12, props = { text = "0 us" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_avg", type = "Label", x = 230, y = 176, w = 30, h = 12, props = { text = "Avg" }, style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
    { id = "val_avg", type = "Label", x = 264, y = 176, w = 60, h = 12, props = { text = "0 us" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    
    { id = "lbl_cpu", type = "Label", x = 332, y = 176, w = 30, h = 12, props = { text = "CPU" }, style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
    { id = "val_cpu", type = "Label", x = 366, y = 176, w = 60, h = 12, props = { text = "0%" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    
    -- Hint
    { id = "perf_hint", type = "Label", x = 380, y = 190, w = 70, h = 10,
      props = { text = "` to hide" },
      style = { colour = 0xff64748b, fontSize = 7, bg = 0x00000000 } },
  },
}

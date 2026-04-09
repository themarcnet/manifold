return {
  id = "perf_overlay_root",
  type = "Panel",
  x = 0, y = 0, w = 472, h = 208,
  style = { bg = 0x00000000, border = 0x00000000, borderWidth = 0, radius = 0 },
  children = {
    { id = "perf_bg", type = "Panel", x = 108, y = 88, w = 352, h = 112,
      style = { bg = 0xdd0f172a, radius = 4 } },
    { id = "perf_title", type = "Label", x = 116, y = 94, w = 160, h = 14,
      props = { text = "Plugin Cost" },
      style = { colour = 0xffa78bfa, fontSize = 10, bg = 0x00000000 } },

    { id = "lbl_tot", type = "Label", x = 116, y = 112, w = 28, h = 12, props = { text = "Tot" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_tot_pss", type = "Label", x = 146, y = 112, w = 62, h = 12, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_tot_priv", type = "Label", x = 210, y = 112, w = 62, h = 12, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_lua", type = "Label", x = 274, y = 112, w = 62, h = 12, props = { text = "L 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_gpu", type = "Label", x = 338, y = 112, w = 110, h = 12, props = { text = "G 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },

    { id = "lbl_plug", type = "Label", x = 116, y = 126, w = 28, h = 12, props = { text = "Plug" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_plug_pss", type = "Label", x = 146, y = 126, w = 62, h = 12, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_plug_priv", type = "Label", x = 210, y = 126, w = 62, h = 12, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_plug_heap", type = "Label", x = 274, y = 126, w = 62, h = 12, props = { text = "H 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_gpu_detail", type = "Label", x = 338, y = 126, w = 110, h = 12, props = { text = "F 0.0 / S 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },

    { id = "lbl_ui", type = "Label", x = 116, y = 140, w = 28, h = 12, props = { text = "UI" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ui_pss", type = "Label", x = 146, y = 140, w = 62, h = 12, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ui_priv", type = "Label", x = 210, y = 140, w = 62, h = 12, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ui_heap", type = "Label", x = 274, y = 140, w = 62, h = 12, props = { text = "H 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_heap_arena", type = "Label", x = 338, y = 140, w = 110, h = 12, props = { text = "Heap 0.0 / A 0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },

    { id = "lbl_stage", type = "Label", x = 116, y = 154, w = 36, h = 12, props = { text = "Stage" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_stage_dsp", type = "Label", x = 154, y = 154, w = 90, h = 12, props = { text = "DSP 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_stage_ui", type = "Label", x = 246, y = 154, w = 96, h = 12, props = { text = "Open 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },
    { id = "val_stage_idle", type = "Label", x = 344, y = 154, w = 104, h = 12, props = { text = "Idle 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 8, bg = 0x00000000 } },

    { id = "lbl_dsp", type = "Label", x = 116, y = 168, w = 36, h = 12, props = { text = "DSP" }, style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
    { id = "val_dsp_cur", type = "Label", x = 154, y = 168, w = 90, h = 12, props = { text = "Cur 0" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_dsp_avg", type = "Label", x = 246, y = 168, w = 96, h = 12, props = { text = "Avg 0" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_dsp_peak", type = "Label", x = 344, y = 168, w = 104, h = 12, props = { text = "Peak 0" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },

    { id = "lbl_ui_perf", type = "Label", x = 116, y = 182, w = 36, h = 12, props = { text = "UI" }, style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ui_frame", type = "Label", x = 154, y = 182, w = 90, h = 12, props = { text = "Frm 0" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_ui_avg", type = "Label", x = 246, y = 182, w = 96, h = 12, props = { text = "Avg 0" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "val_cpu", type = "Label", x = 344, y = 182, w = 70, h = 12, props = { text = "CPU 0%" }, style = { colour = 0xff94a3b8, fontSize = 8, bg = 0x00000000 } },
    { id = "perf_hint", type = "Label", x = 414, y = 182, w = 36, h = 12,
      props = { text = "`" },
      style = { colour = 0xff64748b, fontSize = 8, bg = 0x00000000 } },
  },
}

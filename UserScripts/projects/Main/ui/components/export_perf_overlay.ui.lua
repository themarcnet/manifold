return {
  id = "perf_overlay_root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 472,
  h = 208,
  style = {
    bg = 0xee0f172a,
    border = 0xff334155,
    borderWidth = 1,
    radius = 0,
  },
  children = {
    { id = "title", type = "Label", x = 12, y = 10, w = 200, h = 18, props = { text = "Perf" }, style = { colour = 0xffffffff, fontSize = 12 } },

    { id = "tot_label", type = "Label", x = 12, y = 34, w = 80, h = 14, props = { text = "Total" }, style = { colour = 0xff94a3b8, fontSize = 9 } },
    { id = "val_tot_pss", type = "Label", x = 90, y = 34, w = 70, h = 14, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_tot_priv", type = "Label", x = 158, y = 34, w = 70, h = 14, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_lua", type = "Label", x = 226, y = 34, w = 70, h = 14, props = { text = "L 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_gpu", type = "Label", x = 294, y = 34, w = 70, h = 14, props = { text = "G 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },

    { id = "plug_label", type = "Label", x = 12, y = 54, w = 80, h = 14, props = { text = "Plugin" }, style = { colour = 0xff94a3b8, fontSize = 9 } },
    { id = "val_plug_pss", type = "Label", x = 90, y = 54, w = 70, h = 14, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_plug_priv", type = "Label", x = 158, y = 54, w = 70, h = 14, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_plug_heap", type = "Label", x = 226, y = 54, w = 70, h = 14, props = { text = "H 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_gpu_detail", type = "Label", x = 294, y = 54, w = 160, h = 14, props = { text = "F 0.0 / S 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },

    { id = "ui_label", type = "Label", x = 12, y = 74, w = 80, h = 14, props = { text = "UI" }, style = { colour = 0xff94a3b8, fontSize = 9 } },
    { id = "val_ui_pss", type = "Label", x = 90, y = 74, w = 70, h = 14, props = { text = "P 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_ui_priv", type = "Label", x = 158, y = 74, w = 70, h = 14, props = { text = "D 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_ui_heap", type = "Label", x = 226, y = 74, w = 70, h = 14, props = { text = "H 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_heap_arena", type = "Label", x = 294, y = 74, w = 160, h = 14, props = { text = "Heap 0.0 / A 0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },

    { id = "stage_label", type = "Label", x = 12, y = 98, w = 80, h = 14, props = { text = "Stages" }, style = { colour = 0xff94a3b8, fontSize = 9 } },
    { id = "val_stage_dsp", type = "Label", x = 90, y = 98, w = 120, h = 14, props = { text = "DSP 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_stage_ui", type = "Label", x = 212, y = 98, w = 120, h = 14, props = { text = "Open 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_stage_idle", type = "Label", x = 334, y = 98, w = 120, h = 14, props = { text = "Idle 0.0/0.0" }, style = { colour = 0xffffffff, fontSize = 9 } },

    { id = "time_label", type = "Label", x = 12, y = 122, w = 80, h = 14, props = { text = "Timing" }, style = { colour = 0xff94a3b8, fontSize = 9 } },
    { id = "val_dsp_cur", type = "Label", x = 90, y = 122, w = 84, h = 14, props = { text = "Cur 0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_dsp_avg", type = "Label", x = 176, y = 122, w = 84, h = 14, props = { text = "Avg 0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_dsp_peak", type = "Label", x = 262, y = 122, w = 84, h = 14, props = { text = "Peak 0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_ui_frame", type = "Label", x = 90, y = 142, w = 84, h = 14, props = { text = "Frm 0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_ui_avg", type = "Label", x = 176, y = 142, w = 84, h = 14, props = { text = "Avg 0" }, style = { colour = 0xffffffff, fontSize = 9 } },
    { id = "val_cpu", type = "Label", x = 262, y = 142, w = 84, h = 14, props = { text = "CPU 0%" }, style = { colour = 0xffffffff, fontSize = 9 } },
  },
}

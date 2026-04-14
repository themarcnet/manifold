return {
  id = "oscRoot",
  type = "Panel",
  x = 0, y = 0, w = 560, h = 200,
  style = { bg = 0xff121a2f, border = 0xff1f2b4d, borderWidth = 1, radius = 10 },
  -- Port definitions for signal routing visualization
  ports = {
    inputs = {
      { id = "cv_in", type = "cv", y = 0.35, label = "CV" }
    },
    outputs = {
      { id = "audio_out", type = "audio", y = 0.65, label = "OUT" }
    }
  },
  children = {
    { id = "title", type = "Label", x = 16, y = 8, w = 200, h = 14, props = { text = "OSCILLATOR" }, style = { colour = 0xff7dd3fc, fontSize = 12 } },

    -- Graph on left (filled by behavior)
    { id = "osc_graph", type = "Panel", x = 10, y = 28, w = 270, h = 164, style = { bg = 0xff0d1420, border = 0xff1a1a3a, borderWidth = 1, radius = 6 } },
    -- Sample length display (top right of graph, same row as SAMPLE MODE)
    { id = "sample_length_label", type = "Label", x = 210, y = 10, w = 80, h = 16, props = { text = "0ms" }, style = { colour = 0xff94a3b8, fontSize = 10 } },

    -- TabHost on right for Wave/Sample/Blend switching
    {
      id = "mode_tabs",
      type = "TabHost",
      x = 290, y = 28, w = 260, h = 130,
      props = {
        activeIndex = 1,
        tabBarHeight = 24,
        tabSizing = "fill",
      },
      style = {
        bg = 0xff0b1220,
        border = 0xff1f2937,
        borderWidth = 1,
        radius = 6,
        tabBarBg = 0xff0d1420,
        tabBg = 0xff1e293b,
        activeTabBg = 0xff2563eb,
        textColour = 0xff94a3b8,
        activeTextColour = 0xffffffff,
      },
      children = {
        {
          id = "wave_tab",
          type = "TabPage",
          x = 0, y = 24, w = 260, h = 106,
          props = { title = "Wave" },
          style = { bg = 0x00000000 },
          children = {
            { id = "waveform_dropdown", type = "Dropdown", x = 4, y = 4, w = 84, h = 20, props = { options = { "Sine", "Saw", "Square", "Triangle", "Blend", "Noise", "Pulse", "SuperSaw" }, selected = 2, max_visible_rows = 8 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8, radius = 0 } },
            { id = "render_mode_tabs", type = "SegmentedControl", x = 94, y = 4, w = 84, h = 20, props = { segments = { "Std", "Add" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xff2563eb, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },
            { id = "pulse_width_knob", type = "Slider", x = 10, y = 30, w = 200, h = 20, props = { min = 0.01, max = 0.99, step = 0.01, value = 0.5, label = "Width", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
            { id = "add_partials_knob", type = "Slider", x = 10, y = 30, w = 120, h = 20, props = { min = 1, max = 12, step = 1, value = 8, label = "Parts", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
            { id = "add_tilt_knob", type = "Slider", x = 10, y = 56, w = 120, h = 20, props = { min = -1, max = 1, step = 0.01, value = 0.0, label = "Tilt", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
            { id = "add_drift_knob", type = "Slider", x = 10, y = 82, w = 120, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Drift", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff10231d, fontSize = 9 } },
            { id = "drive_curve", type = "CurveWidget", x = 10, y = 94, w = 56, h = 56, props = { title = "DRV", editable = false }, style = { colour = 0xfff97316, bg = 0xff120d0a, gridColour = 0xff2a1a12, axisColour = 0xff4b2d1d } },
            { id = "drive_mode_dropdown", type = "Dropdown", x = 78, y = 100, w = 62, h = 20, props = { options = { "Soft", "Hard", "Clip", "Fold" }, selected = 1, max_visible_rows = 4 }, style = { bg = 0xff1e293b, colour = 0xfff97316, fontSize = 9, radius = 0 } },
            { id = "drive_bias_knob", type = "Slider", x = 78, y = 152, w = 62, h = 20, props = { min = -1, max = 1, step = 0.01, value = 0.0, label = "Bias", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xfffb7185, bg = 0xff2a1117, fontSize = 9 } },
            { id = "drive_knob", type = "Slider", x = 78, y = 126, w = 62, h = 20, props = { min = 0, max = 20, step = 0.1, value = 0.0, label = "Drive", compact = true, showValue = true }, style = { colour = 0xfff97316, bg = 0xff2a1208, fontSize = 9 } },
          },
        },
        {
          id = "sample_tab",
          type = "TabPage",
          x = 0, y = 24, w = 260, h = 130,
          props = { title = "Sample" },
          style = { bg = 0x00000000 },
          children = {
            { id = "sample_source_dropdown", type = "Dropdown", x = 4, y = 4, w = 56, h = 20, props = { options = { "Live", "L1", "L2", "L3", "L4" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 10, radius = 0 } },
            { id = "sample_pitch_map_toggle", type = "Toggle", x = 4, y = 4, w = 70, h = 20, props = { offLabel = "P-Map Off", onLabel = "P-Map On", value = false }, style = { onColour = 0xffd97706, offColour = 0xff475569, fontSize = 10 } },
            { id = "sample_capture_mode_toggle", type = "Toggle", x = 78, y = 4, w = 56, h = 20, props = { offLabel = "Retro", onLabel = "Free", value = false }, style = { onColour = 0xff0ea5e9, offColour = 0xff475569, fontSize = 10 } },
            { id = "sample_capture_button", type = "Button", x = 138, y = 4, w = 48, h = 20, props = { label = "Cap" }, style = { bg = 0xff334155, colour = 0xffe2e8f0, fontSize = 10 } },

            -- Pitch mode selector: Classic (speed-based) vs Phase Vocoder (duration-preserving)
            { id = "sample_pitch_mode", type = "SegmentedControl", x = 4, y = 28, w = 170, h = 20, props = { segments = { "Classic", "PVoc", "HQ" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xff8b5cf6, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },

            { id = "sample_bars_box", type = "Slider", x = 10, y = 54, w = 200, h = 20, props = { min = 0.0625, max = 16.0, step = 0.0625, value = 1.0, label = "Bars", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
            { id = "sample_root_box", type = "Slider", x = 10, y = 80, w = 200, h = 20, props = { min = 12, max = 96, step = 1, value = 60, label = "Root", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },
            { id = "sample_xfade_box", type = "Slider", x = 10, y = 106, w = 200, h = 20, props = { min = 0, max = 50, step = 1, value = 10, label = "X-Fade", compact = true, showValue = true }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },
            -- Phase vocoder parameters (only visible in PVoc/HQ modes via behavior)
            { id = "sample_pvoc_fft", type = "Slider", x = 10, y = 130, w = 100, h = 20, props = { min = 9, max = 12, step = 1, value = 11, label = "FFT", compact = true, showValue = true }, style = { colour = 0xffa78bfa, bg = 0xff1e1b33, fontSize = 9 } },
            { id = "sample_pvoc_stretch", type = "Slider", x = 110, y = 130, w = 100, h = 20, props = { min = 0.25, max = 4.0, step = 0.25, value = 1.0, label = "Stretch", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
          },
        },
        {
          id = "blend_tab",
          type = "TabPage",
          x = 0, y = 24, w = 260, h = 160,
          props = { title = "Blend" },
          style = { bg = 0x00000000 },
          children = {
            { id = "blend_mode_dropdown", type = "Dropdown", x = 4, y = 4, w = 68, h = 20, props = { options = { "Mix", "Ring", "FM", "Sync", "Add", "Morph" }, selected = 1, max_visible_rows = 6 }, style = { bg = 0xff1e293b, colour = 0xff22d3ee, fontSize = 10, radius = 0 } },
            { id = "blend_key_track_radio", type = "Radio", x = 78, y = 4, w = 132, h = 20, props = { options = { "Wave", "Sample", "Both" }, selected = 3 }, style = { bg = 0xff1e293b, selectedBg = 0xff3b82f6, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },
            { id = "blend_sample_pitch_knob", type = "Slider", x = 10, y = 34, w = 200, h = 20, props = { min = -24, max = 24, step = 1, value = 0, label = "Pitch", compact = true, showValue = true }, style = { colour = 0xfff472b6, bg = 0xff2b1020, fontSize = 9 } },
            { id = "blend_mod_amount_knob", type = "Slider", x = 10, y = 60, w = 200, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Depth", compact = true, showValue = true }, style = { colour = 0xfffb923c, bg = 0xff2a1708, fontSize = 9 } },
            { id = "add_flavor_toggle", type = "SegmentedControl", x = 10, y = 86, w = 140, h = 20, props = { segments = { "Self", "Driven" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xff7c3aed, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },
            { id = "morph_curve", type = "SegmentedControl", x = 10, y = 86, w = 74, h = 20, props = { segments = { "Lin", "SCrv", "EqP" }, selected = 3 }, style = { bg = 0xff1e293b, selectedBg = 0xfff97316, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },
            { id = "morph_phase", type = "SegmentedControl", x = 92, y = 86, w = 118, h = 20, props = { segments = { "Ntrl", "Brt", "Dark" }, selected = 1 }, style = { bg = 0xff1e293b, selectedBg = 0xfff97316, textColour = 0xff94a3b8, selectedTextColour = 0xffffffff } },
            { id = "morph_speed", type = "Slider", x = 10, y = 112, w = 96, h = 20, props = { min = 0.1, max = 4.0, step = 0.1, value = 1.0, label = "Speed", compact = true, showValue = false }, style = { colour = 0xfff97316, bg = 0xff2a1708, fontSize = 9 } },
            { id = "morph_contrast", type = "Slider", x = 114, y = 112, w = 96, h = 20, props = { min = 0, max = 2, step = 0.01, value = 0.5, label = "Contrast", compact = true, showValue = false }, style = { colour = 0xfff97316, bg = 0xff2a1708, fontSize = 9 } },
            { id = "morph_smooth", type = "Slider", x = 10, y = 138, w = 96, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Smooth", compact = true, showValue = false }, style = { colour = 0xfffb923c, bg = 0xff2a1708, fontSize = 9 } },
            { id = "morph_convergence", type = "Slider", x = 114, y = 138, w = 96, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0.0, label = "Stretch", compact = true, showValue = false }, style = { colour = 0xfffb923c, bg = 0xff2a1708, fontSize = 9 } },
          },
        },
      },
    },

    { id = "unison_knob", type = "Slider", x = 10, y = 118, w = 270, h = 20, props = { min = 1, max = 8, step = 1, value = 1, label = "Unison", compact = true, showValue = true }, style = { colour = 0xff22d3ee, bg = 0xff08212a, fontSize = 9 } },
    { id = "detune_knob", type = "Slider", x = 10, y = 144, w = 270, h = 20, props = { min = 0, max = 100, step = 1, value = 0, label = "Detune", compact = true, showValue = true }, style = { colour = 0xff4ade80, bg = 0xff102317, fontSize = 9 } },
    { id = "spread_knob", type = "Slider", x = 10, y = 170, w = 270, h = 20, props = { min = 0, max = 1, step = 0.01, value = 0, label = "Spread", compact = true, showValue = true }, style = { colour = 0xfffbbf24, bg = 0xff2b2008, fontSize = 9 } },

    -- Blend and Output footer controls (repositioned by behavior)
    { id = "blend_amount_knob", type = "Slider", x = 305, y = 164, w = 76, h = 24, props = { min = 0, max = 1, step = 0.01, value = 0.5, label = "Blend", compact = true, bidirectional = true, showValue = true }, style = { colour = 0xfff59e0b, bg = 0xff2a1b08, fontSize = 9 } },
    { id = "output_knob", type = "Slider", x = 389, y = 164, w = 76, h = 24, props = { min = 0, max = 2, step = 0.01, value = 0.8, label = "Output", compact = true, showValue = true }, style = { colour = 0xff34d399, bg = 0xff10231d, fontSize = 9 } },
  },
}

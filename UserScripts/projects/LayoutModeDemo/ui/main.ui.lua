return {
  id = "root",
  type = "Panel",
  x = 0,
  y = 0,
  w = 1280,
  h = 720,
  shellLayout = {
    mode = "fill",
    designW = 1280,
    designH = 720,
  },
  style = {
    bg = 0xff08111f,
  },
  children = {
    {
      id = "header",
      type = "Panel",
      layout = { mode = "hybrid", left = 12, right = 12, top = 12, h = 56 },
      style = {
        bg = 0xff0f172a,
        border = 0xff1e293b,
        borderWidth = 1,
        radius = 10,
      },
      children = {
        {
          id = "title",
          type = "Label",
          x = 16,
          y = 10,
          w = 340,
          h = 20,
          props = { text = "LAYOUT MODE DEMO" },
          style = {
            colour = 0xffe2e8f0,
            fontSize = 20,
            fontStyle = FontStyle.bold,
          },
        },
        {
          id = "subtitle",
          type = "Label",
          x = 16,
          y = 30,
          w = 780,
          h = 16,
          props = { text = "Tabs below demonstrate stack-x, stack-y, grid, overlay, and mixed nesting without breaking legacy absolute layout." },
          style = {
            colour = 0xff94a3b8,
            fontSize = 11,
          },
        },
      },
    },
    {
      id = "mainTabs",
      type = "TabHost",
      layout = { mode = "hybrid", left = 12, right = 12, top = 80, bottom = 12 },
      props = {
        activeIndex = 1,
        tabBarHeight = 28,
        tabSizing = "fill",
      },
      style = {
        bg = 0xff0b1220,
        border = 0xff1f2937,
        borderWidth = 1,
        radius = 10,
        tabBarBg = 0xff020617,
        tabBg = 0xff111827,
        activeTabBg = 0xff2563eb,
        textColour = 0xffcbd5e1,
        activeTextColour = 0xffffffff,
      },
      children = {
        {
          id = "stacks_page",
          type = "TabPage",
          props = { title = "Stacks" },
          style = { bg = 0xff0b1220 },
          children = {
            {
              id = "stacks_intro",
              type = "Label",
              layout = { mode = "hybrid", left = 16, right = 16, top = 12, h = 18 },
              props = { text = "Top demo is stack-x. Lower-left is stack-y. Lower-right is stack-x with an absolute child riding on top." },
              style = { colour = 0xff94a3b8, fontSize = 11 },
            },
            {
              id = "stack_row_demo",
              type = "Panel",
              layout = { mode = "stack-x", left = 16, right = 16, top = 42, h = 88, padding = 12, gap = 12, align = "center" },
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 8 },
              children = {
                {
                  id = "stack_row_button",
                  type = "Button",
                  layoutChild = { basis = 120, crossSize = 32 },
                  props = { label = "Fixed 120" },
                  style = { bg = 0xff1d4ed8, fontSize = 12 },
                },
                {
                  id = "stack_row_dropdown",
                  type = "Dropdown",
                  layoutChild = { basis = 220, crossSize = 32 },
                  props = { options = { "Alpha", "Beta", "Gamma", "Delta" }, selected = 2, max_visible_rows = 4 },
                  style = { bg = 0xff1e293b, colour = 0xff22d3ee },
                },
                {
                  id = "stack_row_status",
                  type = "Label",
                  layoutChild = { grow = 1, crossSize = 22 },
                  props = { text = "grow = 1 → this label eats the spare width" },
                  style = { colour = 0xffcbd5e1, fontSize = 12 },
                },
                {
                  id = "stack_row_action",
                  type = "Button",
                  layoutChild = { basis = 132, crossSize = 32 },
                  props = { label = "Fixed 132" },
                  style = { bg = 0xff7c3aed, fontSize = 12 },
                },
              },
            },
            {
              id = "stack_column_demo",
              type = "Panel",
              layout = { mode = "stack-y", left = 16, top = 150, w = 380, bottom = 16, padding = 12, gap = 10, align = "stretch" },
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 8 },
              children = {
                {
                  id = "column_title",
                  type = "Label",
                  layoutChild = { basis = 20 },
                  props = { text = "stack-y with fixed and grow children" },
                  style = { colour = 0xff7dd3fc, fontSize = 12, fontStyle = FontStyle.bold },
                },
                {
                  id = "column_card_a",
                  type = "Panel",
                  layoutChild = { basis = 72 },
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 6 },
                  children = {
                    { id = "column_card_a_label", type = "Label", x = 12, y = 12, w = 320, h = 18, props = { text = "basis = 72" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                  },
                },
                {
                  id = "column_card_b",
                  type = "Panel",
                  layoutChild = { grow = 1, minH = 120 },
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 6 },
                  children = {
                    { id = "column_card_b_label", type = "Label", x = 12, y = 12, w = 320, h = 18, props = { text = "grow = 1, minH = 120" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                    { id = "column_card_b_body", type = "Label", x = 12, y = 36, w = 332, h = 54, props = { text = "This panel stretches to consume remaining vertical space in the stack." }, style = { colour = 0xff94a3b8, fontSize = 11 } },
                  },
                },
                {
                  id = "column_card_c",
                  type = "Panel",
                  layoutChild = { basis = 78 },
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 6 },
                  children = {
                    { id = "column_card_c_label", type = "Label", x = 12, y = 12, w = 320, h = 18, props = { text = "basis = 78" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                  },
                },
              },
            },
            {
              id = "stack_absolute_demo",
              type = "Panel",
              layout = { mode = "stack-x", left = 414, right = 16, top = 150, bottom = 16, padding = 12, gap = 12, align = "stretch" },
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 8 },
              children = {
                {
                  id = "absolute_demo_left",
                  type = "Panel",
                  layoutChild = { grow = 1 },
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 6 },
                  children = {
                    { id = "absolute_demo_left_label", type = "Label", x = 12, y = 12, w = 260, h = 18, props = { text = "Flow child A" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                  },
                },
                {
                  id = "absolute_demo_right",
                  type = "Panel",
                  layoutChild = { grow = 1 },
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 6 },
                  children = {
                    { id = "absolute_demo_right_label", type = "Label", x = 12, y = 12, w = 260, h = 18, props = { text = "Flow child B" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                  },
                },
                {
                  id = "stack_absolute_badge",
                  type = "Label",
                  layoutChild = { position = "absolute", x = 16, y = 12, w = 208, h = 20 },
                  props = { text = "absolute child inside stack-x" },
                  style = { colour = 0xffffffff, fontSize = 11 },
                },
              },
            },
          },
        },
        {
          id = "grid_page",
          type = "TabPage",
          props = { title = "Grid" },
          style = { bg = 0xff0b1220 },
          children = {
            {
              id = "grid_intro",
              type = "Label",
              layout = { mode = "hybrid", left = 16, right = 16, top = 12, h = 18 },
              props = { text = "The hero card spans two columns. The magenta note is an absolute child positioned over the managed grid." },
              style = { colour = 0xff94a3b8, fontSize = 11 },
            },
            {
              id = "grid_demo",
              type = "Panel",
              layout = { mode = "grid", left = 16, right = 16, top = 42, bottom = 16, columns = 4, gap = 12, padding = 12, minRowHeight = 120 },
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 8 },
              children = {
                {
                  id = "hero_card",
                  type = "Panel",
                  layoutChild = { colSpan = 2 },
                  style = { bg = 0xff132238, border = 0xff2563eb, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "hero_title", type = "Label", x = 14, y = 12, w = 340, h = 18, props = { text = "Hero card · colSpan = 2" }, style = { colour = 0xffe2e8f0, fontSize = 13, fontStyle = FontStyle.bold } },
                    { id = "hero_body", type = "Label", x = 14, y = 38, w = 420, h = 42, props = { text = "This wider card demonstrates sibling-aware placement instead of manual card math in a behavior." }, style = { colour = 0xff93c5fd, fontSize = 11 } },
                  },
                },
                {
                  id = "filter_card",
                  type = "Panel",
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "filter_title", type = "Label", x = 14, y = 12, w = 180, h = 18, props = { text = "Filter" }, style = { colour = 0xffe2e8f0, fontSize = 13 } },
                    { id = "filter_cutoff", type = "Knob", x = 12, y = 42, w = 60, h = 70, props = { min = 20, max = 20000, step = 1, value = 4200, label = "Cutoff" }, style = { colour = 0xfff59e0b } },
                  },
                },
                {
                  id = "env_card",
                  type = "Panel",
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "env_title", type = "Label", x = 14, y = 12, w = 180, h = 18, props = { text = "Envelope" }, style = { colour = 0xffe2e8f0, fontSize = 13 } },
                    { id = "env_attack", type = "Knob", x = 12, y = 42, w = 60, h = 70, props = { min = 0, max = 1, step = 0.01, value = 0.08, label = "Attack" }, style = { colour = 0xff4ade80 } },
                  },
                },
                {
                  id = "fx_bus",
                  type = "Panel",
                  layoutChild = { colSpan = 2 },
                  style = { bg = 0xff1a1433, border = 0xff7c3aed, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "fx_title", type = "Label", x = 14, y = 12, w = 280, h = 18, props = { text = "FX bus · second wide card" }, style = { colour = 0xffede9fe, fontSize = 13 } },
                    { id = "fx_dropdown", type = "Dropdown", x = 14, y = 40, w = 180, h = 24, props = { options = { "Chorus", "Phaser", "Delay", "Reverb" }, selected = 3, max_visible_rows = 4 }, style = { bg = 0xff2e1065, colour = 0xffc4b5fd } },
                  },
                },
                {
                  id = "meter_card",
                  type = "Panel",
                  style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "meter_title", type = "Label", x = 14, y = 12, w = 180, h = 18, props = { text = "Meter / Note" }, style = { colour = 0xffe2e8f0, fontSize = 13 } },
                    { id = "meter_note", type = "Label", x = 14, y = 44, w = 180, h = 20, props = { text = "C#4 · vel 97" }, style = { colour = 0xff22d3ee, fontSize = 12 } },
                  },
                },
                {
                  id = "grid_absolute_note",
                  type = "Label",
                  layoutChild = { position = "absolute", x = 18, y = 18, w = 220, h = 18 },
                  props = { text = "absolute overlay note on managed grid" },
                  style = { colour = 0xffff7adf, fontSize = 11 },
                },
              },
            },
          },
        },
        {
          id = "overlay_page",
          type = "TabPage",
          props = { title = "Overlay" },
          style = { bg = 0xff0b1220 },
          children = {
            {
              id = "overlay_intro",
              type = "Label",
              layout = { mode = "hybrid", left = 16, right = 16, top = 12, h = 18 },
              props = { text = "Overlay mode anchors children to the container content rect. This is useful for badges, floating chrome, and composited panels." },
              style = { colour = 0xff94a3b8, fontSize = 11 },
            },
            {
              id = "overlay_stage",
              type = "Panel",
              layout = { mode = "overlay", left = 16, right = 16, top = 42, bottom = 16, padding = 12 },
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 8 },
              children = {
                {
                  id = "overlay_background",
                  type = "Panel",
                  layoutChild = { anchor = "fill" },
                  style = { bg = 0xff0f172a, border = 0xff1e293b, borderWidth = 1, radius = 8 },
                },
                {
                  id = "overlay_badge",
                  type = "Label",
                  layoutChild = { anchor = "top-right", margin = 12, w = 120, h = 20 },
                  props = { text = "TOP-RIGHT BADGE" },
                  style = { colour = 0xfffef3c7, fontSize = 11 },
                },
                {
                  id = "overlay_center_panel",
                  type = "Panel",
                  layoutChild = { anchor = "center", w = 420, h = 220 },
                  style = { bg = 0xff132238, border = 0xff2563eb, borderWidth = 1, radius = 10 },
                  children = {
                    { id = "overlay_center_title", type = "Label", x = 18, y = 18, w = 300, h = 20, props = { text = "Centered overlay panel" }, style = { colour = 0xffe2e8f0, fontSize = 14, fontStyle = FontStyle.bold } },
                    { id = "overlay_center_body", type = "Label", x = 18, y = 52, w = 380, h = 40, props = { text = "This panel is anchored by the system while its internals remain manual/absolute." }, style = { colour = 0xff93c5fd, fontSize = 12 } },
                    { id = "overlay_center_dropdown", type = "Dropdown", x = 18, y = 122, w = 180, h = 24, props = { options = { "One", "Two", "Three" }, selected = 1, max_visible_rows = 3 }, style = { bg = 0xff1e293b, colour = 0xff38bdf8 } },
                  },
                },
                {
                  id = "overlay_bottom_strip",
                  type = "Panel",
                  layoutChild = { anchor = "bottom-center", margin = { 0, 0, 16, 0 }, w = 520, h = 46 },
                  style = { bg = 0xff1a1433, border = 0xff7c3aed, borderWidth = 1, radius = 8 },
                  children = {
                    { id = "overlay_bottom_label", type = "Label", x = 14, y = 14, w = 420, h = 18, props = { text = "bottom-center anchored control strip" }, style = { colour = 0xffddd6fe, fontSize = 12 } },
                  },
                },
                {
                  id = "overlay_debug_label",
                  type = "Label",
                  layoutChild = { position = "absolute", x = 24, y = 24, w = 180, h = 18 },
                  props = { text = "absolute debug text" },
                  style = { colour = 0xfff472b6, fontSize = 11 },
                },
              },
            },
          },
        },
        {
          id = "mixed_page",
          type = "TabPage",
          props = { title = "Mixed" },
          style = { bg = 0xff0b1220 },
          children = {
            {
              id = "mixed_intro",
              type = "Label",
              layout = { mode = "hybrid", left = 16, right = 16, top = 12, h = 18 },
              props = { text = "Outer card is legacy manual placement. Inside it, a nested TabHost uses grid, stack-y, and overlay layouts." },
              style = { colour = 0xff94a3b8, fontSize = 11 },
            },
            {
              id = "manual_outer_card",
              type = "Panel",
              x = 48,
              y = 56,
              w = 1160,
              h = 560,
              style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 10 },
              children = {
                {
                  id = "manual_outer_label",
                  type = "Label",
                  x = 16,
                  y = 12,
                  w = 420,
                  h = 18,
                  props = { text = "Legacy absolute shell containing managed layout subtrees" },
                  style = { colour = 0xffe2e8f0, fontSize = 12, fontStyle = FontStyle.bold },
                },
                {
                  id = "inner_tabs",
                  type = "TabHost",
                  layout = { mode = "hybrid", left = 12, right = 12, top = 42, bottom = 12 },
                  props = { activeIndex = 1, tabBarHeight = 24, tabSizing = "fill" },
                  style = {
                    bg = 0xff0b1220,
                    border = 0xff1f2937,
                    borderWidth = 1,
                    radius = 8,
                    tabBarBg = 0xff0f172a,
                    tabBg = 0xff1e293b,
                    activeTabBg = 0xff0ea5e9,
                    textColour = 0xffcbd5e1,
                    activeTextColour = 0xffffffff,
                  },
                  children = {
                    {
                      id = "inner_grid_page",
                      type = "TabPage",
                      props = { title = "Nested Grid" },
                      children = {
                        {
                          id = "inner_grid",
                          type = "Panel",
                          layout = { mode = "grid", left = 16, right = 16, top = 16, bottom = 16, columns = 3, gap = 12, padding = 12, minRowHeight = 100 },
                          style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                          children = {
                            { id = "inner_grid_a", type = "Panel", layoutChild = { colSpan = 2 }, style = { bg = 0xff132238, border = 0xff2563eb, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_grid_a_label", type = "Label", x = 12, y = 12, w = 260, h = 18, props = { text = "nested grid wide card" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                            { id = "inner_grid_b", type = "Panel", style = { bg = 0xff0b1220, border = 0xff334155, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_grid_b_label", type = "Label", x = 12, y = 12, w = 200, h = 18, props = { text = "card B" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                            { id = "inner_grid_c", type = "Panel", style = { bg = 0xff0b1220, border = 0xff334155, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_grid_c_label", type = "Label", x = 12, y = 12, w = 200, h = 18, props = { text = "card C" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                            { id = "inner_grid_d", type = "Panel", style = { bg = 0xff0b1220, border = 0xff334155, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_grid_d_label", type = "Label", x = 12, y = 12, w = 200, h = 18, props = { text = "card D" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                          },
                        },
                      },
                    },
                    {
                      id = "inner_stack_page",
                      type = "TabPage",
                      props = { title = "Nested Stack" },
                      children = {
                        {
                          id = "inner_stack",
                          type = "Panel",
                          layout = { mode = "stack-y", left = 16, right = 16, top = 16, bottom = 16, padding = 12, gap = 10, align = "stretch" },
                          style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                          children = {
                            { id = "inner_stack_title", type = "Label", layoutChild = { basis = 20 }, props = { text = "nested stack-y" }, style = { colour = 0xff7dd3fc, fontSize = 12, fontStyle = FontStyle.bold } },
                            { id = "inner_stack_row_1", type = "Panel", layoutChild = { basis = 70 }, style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_stack_row_1_label", type = "Label", x = 12, y = 12, w = 320, h = 18, props = { text = "row 1" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                            { id = "inner_stack_row_2", type = "Panel", layoutChild = { grow = 1, minH = 120 }, style = { bg = 0xff111827, border = 0xff334155, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_stack_row_2_label", type = "Label", x = 12, y = 12, w = 320, h = 18, props = { text = "grow = 1 nested row" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                          },
                        },
                      },
                    },
                    {
                      id = "inner_overlay_page",
                      type = "TabPage",
                      props = { title = "Nested Overlay" },
                      children = {
                        {
                          id = "inner_overlay",
                          type = "Panel",
                          layout = { mode = "overlay", left = 16, right = 16, top = 16, bottom = 16, padding = 12 },
                          style = { bg = 0xff0f172a, border = 0xff334155, borderWidth = 1, radius = 8 },
                          children = {
                            { id = "inner_overlay_bg", type = "Panel", layoutChild = { anchor = "fill" }, style = { bg = 0xff111827, border = 0xff1f2937, borderWidth = 1, radius = 6 } },
                            { id = "inner_overlay_badge", type = "Label", layoutChild = { anchor = "top-right", margin = 12, w = 150, h = 18 }, props = { text = "nested overlay badge" }, style = { colour = 0xfffef3c7, fontSize = 11 } },
                            { id = "inner_overlay_center", type = "Panel", layoutChild = { anchor = "center", w = 260, h = 140 }, style = { bg = 0xff132238, border = 0xff2563eb, borderWidth = 1, radius = 6 }, children = {
                              { id = "inner_overlay_center_label", type = "Label", x = 12, y = 12, w = 220, h = 18, props = { text = "nested center panel" }, style = { colour = 0xffe2e8f0, fontSize = 12 } },
                            } },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  },
}

# UI System Design

## Overview

A Lua-based UI system for audio plugins featuring declarative styling via CSS and a flexible layout engine. The system allows users to build custom UIs through a widget library, apply consistent styling through stylesheets, and arrange elements using automatic layout algorithms.

## Motivation

Building on the concepts from the Audio Plugin UI Development talk (Roth Michaels, iZotope/Native Instruments), this system addresses similar challenges:

- **Declarative syntax** — Define UIs as data, not imperative code
- **Type safety** — Reduce runtime errors through clear interfaces
- **Separation of concerns** — Structure, styling, and behavior are distinct
- **Hot-reload** — Edit styles without recompiling

However, implementing in Lua provides significant advantages over the C++ approach:
- Runtime parsing and application (no compile-time concepts required)
- Instant style reload during development
- Simpler metaprogramming through Lua tables and metamethods

## Goals

1. **User-extensible widgets** — Users can subclass any widget and override behavior
2. **CSS-based styling** — Consistent theming across the entire UI
3. **Multiple layout modes** — Flexbox, stack, or manual pixel positioning
4. **Visual editor ready** — System designed to be driven by a future GUI builder
5. **Backward compatible** — Manual layout in `ui_resized()` still works

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      UI Script (.lua)                       │
│  Widget instantiation + configuration + event handlers      │
└──────────────────────────┬──────────────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
   ┌──────────────┐ ┌────────────┐ ┌─────────────────────┐
   │ ui_widgets   │ │ ui_styles  │ │ ui_layout           │
   │              │ │            │ │                     │
   │ BaseWidget   │ │ CSS.parse  │ │ Layout.applyFlex    │
   │ Button       │ │ CSS.resolve│ │ Layout.applyStack   │
   │ Knob         │ │ Pseudo-    │ │ Layout.applyManual  │
   │ Panel        │ │   classes  │ │                     │
   └──────┬───────┘ └─────┬──────┘ └──────────┬──────────┘
          │               │                    │
          └───────────────┼────────────────────┘
                          ▼
          ┌───────────────────────────────┐
          │         Canvas (C++)           │
          │   Scene graph + rendering      │
          └───────────────────────────────┘
```

---

## File Organization

```
manifold/ui/
├── ui_widgets.lua       -- Widget library (BaseWidget + all widgets)
├── ui_styles.lua        -- CSS parser + style resolution
├── ui_layout.lua        -- Layout engine (flex/stack/manual)
├── ui_themes.lua        -- Built-in theme definitions
├── looper_ui.lua        -- Default UI script (user-facing)
└── *.lua               -- Other UI scripts
```

---

## CSS System (`ui_styles.lua`)

### Purpose

Parse CSS-like stylesheets and apply them to widgets based on selectors.

### API

```lua
local CSS = require("ui_styles")

-- Load a theme (table or string)
CSS.load(theme)
-- theme = { 
--   [".classname"] = { bg = 0xff374151, radius = 6 },
--   ["Button:hover"] = { bg = 0xff4b5563 },
--   ["#myButton"] = { bg = 0xff22c55e },
-- }

-- Apply styles to a widget instance
CSS.apply(widget)
-- Resolves all matching rules and applies via widget setters

-- Query current style (for debugging)
CSS.getComputed(widget)
-- Returns merged style table after all rules applied

-- Hot-reload: re-apply styles to all registered widgets
CSS.reload()
```

### Supported Selectors

| Selector | Example | Matches |
|----------|---------|---------|
| Type | `Button` | All Button widgets |
| Class | `.btn` | Widgets with `config.class = "btn"` |
| ID | `#recButton` | Widget with `config.id = "recButton"` |
| Pseudo-class | `Button:hover` | Widget when hovered (auto-tracked) |
| Pseudo-class | `Button:pressed` | Widget when pressed |

### Pseudo-classes

Automatically track widget state and apply matching styles:

```lua
-- In theme:
[".btn:hover"] = { bg = 0xff4b5563 }
[".btn:pressed"] = { bg = 0xff1f2937 }
[".btn:disabled"] = { opacity = 0.5 }
```

The style system automatically:
- Tracks hover state via widget:isHovered()
- Tracks pressed state via widget:isPressed()
- Tracks enabled state via widget:isEnabled()
- Re-applies styles when state changes

### Style Properties

Map directly to widget setter methods:

```lua
-- Theme entry
[".myButton"] = {
    bg = 0xff374151,           -- calls widget:setBg(0xff374151)
    textColour = 0xffffffff,   -- calls widget:setTextColour(0xffffffff)
    radius = 6,                -- calls widget:setRadius(6)
    visible = true,            -- calls widget:setVisible(true)
}
```

### Theme Example

```lua
-- ui_themes.lua
return {
    -- Global defaults for all widgets
    ["*"] = {
        bg = 0xff1e293b,
        textColour = 0xffffffff,
        fontSize = 12,
    },

    -- Button styles
    [".btn"] = {
        radius = 6,
        padding = {8, 16},
    },
    [".btn:hover"] = {
        bg = 0xff4b5563,
    },
    [".btn:pressed"] = {
        bg = 0xff1f2937,
    },
    [".btn-primary"] = {
        bg = 0xff38bdf8,
    },
    [".btn-danger"] = {
        bg = 0xffef4444,
    },

    -- Panel styles
    ["Panel"] = {
        radius = 8,
        border = 0xff334155,
        borderWidth = 1,
    },
    [".panel-dark"] = {
        bg = 0xff0f172a,
    },

    -- Knob styles
    ["Knob"] = {
        trackColour = 0xff1e293b,
        thumbColour = 0xff22d3ee,
    },

    -- Layout helpers (used by ui_layout)
    [".row"] = {
        -- These trigger layout behavior
        _layout = "hstack",
        _spacing = 8,
    },
    [".col"] = {
        _layout = "vstack",
        _spacing = 8,
    },
    [".center"] = {
        _justifyContent = "center",
        _alignItems = "center",
    },
}
```

---

## Layout System (`ui_layout.lua`)

### Purpose

Automatically position and size widgets within containers.

### API

```lua
local Layout = require("ui_layout")

-- Apply layout to a container widget
Layout.apply(container)
-- Reads container's layout config and lays out children

-- Manual override: disable auto-layout
widget:setLayoutMode("manual")
```

### Layout Modes

#### 1. Flexbox (Yoga-style)

Full CSS Flexbox implementation via Yoga library:

```lua
local panel = W.Panel.new(parent, "container", {
    display = "flex",
    flexDirection = "row",
    justifyContent = "center",
    alignItems = "center",
    gap = 8,
    padding = 16,
})
```

**Supported properties:**
- `display`: `"flex"` | `"none"`
- `flexDirection`: `"row"` | `"column"`
- `justifyContent`: `"flex-start"` | `"center"` | `"flex-end"` | `"space-between"` | `"space-around"`
- `alignItems`: `"flex-start"` | `"center"` | `"flex-end"` | `"stretch"`
- `gap`: number (pixels between items)
- `padding`: number or {top, right, bottom, left}
- `margin`: number or {top, right, bottom, left}
- `width`, `height`: number or "wrap_content" or "fill_parent"
- `minWidth`, `maxWidth`, `minHeight`, `maxHeight`

#### 2. Stack Layout (Simplified)

Linear stacking without Yoga overhead:

```lua
local panel = W.Panel.new(parent, "container", {
    layout = "vstack",  -- or "hstack"
    spacing = 8,
    padding = 16,
    align = "start",    -- "start" | "center" | "end" | "stretch"
})
```

#### 3. Manual Layout (Current)

Pixel-precise positioning via `ui_resized()`:

```lua
-- Still works exactly as before
function ui_resized(w, h)
    ui.panel:setBounds(10, 10, 200, 100)
    ui.button:setBounds(10, 120, 80, 30)
end
```

### Layout Triggers

Layout is recalculated when:
1. Container is resized
2. Child is added or removed
3. Child's "preferred size" changes (optional)
4. Explicit call to `container:requestLayout()`

---

## Widget System (`ui_widgets.lua`)

### BaseWidget

All widgets inherit from BaseWidget, providing:

```lua
-- Construction
Widget.new(parent, name, config)

-- State queries
widget:isHovered()
widget:isPressed()
widget:isEnabled()

-- Style integration
widget:applyStyles()      -- Called automatically on construction
widget:onStateChanged()   -- Called when hover/press changes

-- Layout integration
widget:setLayoutMode("flex" | "stack" | "manual")
widget:requestLayout()

-- Standard methods
widget:setBounds(x, y, w, h)
widget:getWidth()
widget:getHeight()
widget:setVisible(visible)
widget:setEnabled(enabled)
```

### Widget Setters

Every config property has a corresponding setter:

| Config | Setter |
|--------|--------|
| `bg` | `widget:setBg(color)` |
| `textColour` | `widget:setTextColour(color)` |
| `radius` | `widget:setRadius(number)` |
| `border` | `widget:setBorder(color)` |
| `borderWidth` | `widget:setBorderWidth(number)` |
| etc. |

The CSS system uses these setters to apply styles.

### Built-in Widgets

| Widget | Description |
|--------|-------------|
| `Button` | Clickable button with label |
| `Label` | Text display |
| `Panel` | Container (supports layout) |
| `Slider` | Horizontal slider |
| `VSlider` | Vertical slider |
| `Knob` | Rotary knob control |
| `Toggle` | On/off switch |
| `Dropdown` | Selection dropdown |
| `WaveformView` | Audio waveform display |
| `Meter` | Level meter |
| `SegmentedControl` | Multi-option selector |
| `NumberBox` | Numeric input with +/- buttons |

### Extending Widgets

Users can subclass any widget:

```lua
local W = require("ui_widgets")

-- Create custom button
local CustomButton = W.Button:extend()

function CustomButton:drawBackground(w, h)
    -- Override drawing
    gfx.setColour(self._bg)
    gfx.fillRoundedRect(0, 0, w, h, self._radius)
    -- Custom glow effect
    if self:isHovered() then
        gfx.setColour(0x40ffffff)
        gfx.fillRoundedRect(-2, -2, w + 4, h + 4, self._radius + 2)
    end
end

-- Use it
local btn = CustomButton.new(parent, "myBtn", {label = "Click"})
```

---

## User Workflow

### Without Visual Editor

```lua
-- my_ui.lua
local W = require("ui_widgets")
local CSS = require("ui_styles")
local Layout = require("ui_layout")

-- Load theme
CSS.load(require("ui_themes.dark"))

-- Create UI
local mainPanel = W.Panel.new(root, "main", {class = "panel-dark"})
local buttonRow = W.Panel.new(mainPanel, "buttons", {class = "row"})

local recBtn = W.Button.new(buttonRow, "rec", {
    class = "btn btn-danger",
    label = "REC",
    on_click = function() command("TRIGGER", "/manifold/rec") end,
})

local playBtn = W.Button.new(buttonRow, "play", {
    class = "btn btn-primary", 
    label = "PLAY",
    on_click = function() command("TRIGGER", "/manifold/play") end,
})

-- Layout is automatic via CSS classes
-- Or override with explicit layout:
mainPanel:setLayoutMode("flex")
mainPanel:setFlexDirection("column")
```

### With Visual Editor (Future)

1. User drags widgets onto canvas
2. User configures properties in inspector
3. Editor exports:
   - `.lua` script with widget instantiation
   - `.css` file with theme/styling

---

## Implementation Plan

### Phase 1: CSS System (Priority: High)

- [ ] Create `ui_styles.lua`
- [ ] Parse CSS from table (skip string parsing initially)
- [ ] Implement selector matching (type, class, id)
- [ ] Integrate with BaseWidget:applyStyles()
- [ ] Add pseudo-class support (:hover, :pressed, :disabled)
- [ ] Create `ui_themes.lua` with default theme

### Phase 2: Layout System (Priority: Medium)

- [ ] Create `ui_layout.lua`
- [ ] Implement stack layout (vstack/hstack)
- [ ] Add flexbox support (wrap Yoga or custom implementation)
- [ ] Integrate with Panel widget
- [ ] Support layout switching at runtime

### Phase 3: Widget Enhancements (Priority: Medium)

- [ ] Rename `looper_widgets.lua` → `ui_widgets.lua`
- [ ] Add style-aware setters to BaseWidget
- [ ] Add layout request system
- [ ] Document extension patterns

### Phase 4: Editor Integration (Priority: Future)

- [ ] Export CSS from visual editor
- [ ] Live preview with hot-reload
- [ ] Generate optimized Lua code

---

## Backward Compatibility

The system is additive — existing UIs continue to work:

```lua
-- This still works exactly as before
function ui_resized(w, h)
    ui.panel:setBounds(10, 10, 200, 100)
    ui.button:setBounds(10, 120, 80, 30)
end
```

Users can adopt CSS/layout incrementally:
1. Start with manual layout
2. Add CSS classes for consistent styling
3. Switch to auto-layout for new panels

---

## Color Format

All colors in the system use 32-bit ARGB:

```lua
0xff374151  -- Alpha=255, R=55, G=65, B=81
0x00374151  -- Alpha=0 (transparent), R=55, G=65, B=81
```

Helpers provided:

```lua
local function colour(c, default)
    return c or default or 0xff333333
end
```

---

## Naming Conventions

### Files
- `ui_*.lua` — System modules
- `*_ui.lua` — UI scripts
- `*_theme.lua` — Theme files

### Functions
- `CSS.parse(str)` — Parse CSS string
- `CSS.apply(widget)` — Apply styles to widget
- `Layout.apply(container)` — Layout children
- `widget:setBg(color)` — Set property
- `widget:isHovered()` — Query state

### No Obfuscation
- No single-letter variables (except loop indices)
- No cryptic abbreviations (use `textColour`, not `tc`)
- Comments explain *why*, not just *what*

---

## References

- Roth Michaels, "Building a UI Library for Audio Plugins" — CPPCon talk inspiration
- CSS Spec (MDN) — Selector and property reference
- Yoga Layout — Flexbox implementation for reference
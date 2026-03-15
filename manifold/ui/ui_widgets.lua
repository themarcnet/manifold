-- ui_widgets.lua
-- Widget library with proper OOP inheritance for user extensibility.
-- All widgets are classes that users can require and subclass.
-- 
-- This is now a wrapper module - individual widgets are in the widgets/ folder.
-- Usage remains the same:
--   local W = require("ui_widgets")
--   local slider = W.Slider.new(parent, "mySlider", {min=0, max=1, value=0.5})

local Widgets = {}

-- Import all widget modules
local BaseWidget = require("widgets.base")
local Button = require("widgets.button")
local Label = require("widgets.label")
local Panel = require("widgets.panel")
local Sliders = require("widgets.slider")
local Knob = require("widgets.knob")
local Toggle = require("widgets.toggle")
local Dropdown = require("widgets.dropdown")
local WaveformView = require("widgets.waveform")
local Meter = require("widgets.meter")
local SegmentedControl = require("widgets.segmented")
local NumberBox = require("widgets.numberbox")
local DonutWidget = require("widgets.donut")
local XYPadWidget = require("widgets.xypad")
local XYPadWithTrails = require("widgets.xypad_trails")
local GLSLWidget = require("widgets.glsl")
local GLSurfaceWidget = require("widgets.gl_surface")
local TabHost = require("widgets.tabhost")
local TabPage = require("widgets.tabpage")

-- Export all widgets
Widgets.BaseWidget = BaseWidget
Widgets.Button = Button
Widgets.Label = Label
Widgets.Panel = Panel
Widgets.Slider = Sliders.Slider
Widgets.VSlider = Sliders.VSlider
Widgets.Knob = Knob
Widgets.Toggle = Toggle
Widgets.Dropdown = Dropdown
Widgets.WaveformView = WaveformView
Widgets.Meter = Meter
Widgets.SegmentedControl = SegmentedControl
Widgets.NumberBox = NumberBox
Widgets.DonutWidget = DonutWidget
Widgets.XYPadWidget = XYPadWidget
Widgets.XYPadWithTrails = XYPadWithTrails
Widgets.GLSLWidget = GLSLWidget
Widgets.GLSurfaceWidget = GLSurfaceWidget
Widgets.TabHost = TabHost
Widgets.TabPage = TabPage

return Widgets

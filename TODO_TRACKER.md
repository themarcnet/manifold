# TODO Tracker

Flat list of observations, bugs, ideas, and stray thoughts. Append to the bottom.

---

## Exemplars (Reference Format)

- [2026-03-30] UI lag on grain delay panel. Profiler points to `grainDelayProcess()` 
  but source looks fine. @investigate @perf

- [2026-03-30] Modulate grain position with LFO? Would need new parameter. @idea @feature

- [2026-03-29] SIGFPE crash in `Resampler.cpp:88`. Division by zero suspected. 
  Happened once, can't reproduce. @bug @crash

- [2026-03-28] `Oscillator.cpp` has three different interpolation routines. 
  Consolidate to one template when there's time. @refactor @cleanup

---

## Entries

- [2026-03-30] Address discrepancies between current project formats and older 
  project formats and how they work in the editor. @bug @editor

- [2026-03-30] Address regressions in editors — highlight issues, resizing 
  components, etc. @bug @editor @ui

- [2026-03-30] Improve Manifold base UI, including project loading and project 
  loading tools. @ui @feature

- [2026-03-30] Improve build times for application. Address warnings and errors 
  present in build — dedicate time to parse through and improve. @build @cleanup

- [2026-03-30] Investigate crash on IPC commands or project switch via IPC. @bug 
  @crash @ipc

- [2026-03-30] Finish the gRPC implementation. @feature @grpc @network

- [2026-03-30] Find a more graceful way to handle exiting the application without 
  a SIGSEGV. @bug @crash @stability

- [2026-03-30] Improve bug and crash handling so the app bubbles crashes/errors 
  up to the user for easy discoverability and better stability. @feature @ux 
  @stability

- [2026-03-30] Standalone project for loading individual rack modules as 
  standalone modules. @feature @rack @standalone

- [2026-03-30] Build wrapper project for exporting standalone modules as VSTs. 
  @feature @vst @export @build

- [2026-03-30] ~~Investigate what widgets and behaviors there are in projects that 
  could be hoisted up into becoming system level Manifold packages and libraries.~~ 
  **COMPLETED BY KIMI (Agent)** - See report at 
  `agent-docs/reports/260331_package_extraction_investigation_report.md`
  @agent @investigate @packages @architecture @completed

- [2026-03-30] Port remaining DSP live scripting effects to the MIDI synth 
  projects effects slot. @feature @dsp @midi @effects

- [2026-03-30] ~~Investigate and report on what effects and modulation sources are 
  still in DSP live scripting and/or looper/donut super effects slots that have 
  not made their way into the MIDI synth effects slot.~~ 
  **COMPLETED BY KIMI (Agent)** - See report at 
  `agent-docs/reports/260331_effects_audit_dsp_live_vs_midisynth.md`
  @agent @investigate @dsp @effects @audit @completed

- [2026-03-30] Right-click menu handling and specific feature handling needs to 
  be added to the project, specifically in the MIDI synth project. @feature @ui 
  @midi @contextmenu

- [2026-03-30] Hybrid number box entry in compact slider faders — ability to 
  manually enter/type a number in a fader or slider. @feature @ui @widgets @input

- [2026-03-30] Investigate infrastructure for sandboxed agents — approaches for 
  creating isolated copies of repo in cloud/Docker where agents can work safely 
  and generate PRs/reviewable artifacts without impacting local codebase. 
  @agent @investigate @infrastructure @sandbox @docker @cloud @automation


- [2026-03-30] **Code Quality** — Replace empty-script unload + markUnloaded() 
  split. Currently in `BehaviorCoreProcessor.cpp:603`. Original TODO added 
  2026-03-15. @refactor @scripting @cleanup
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:603`

- [2026-03-30] **Infrastructure** — Implement JSON serialization matching Lua 
  structure. Original TODO added 2026-03-04. @feature @serialization @json
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2341`

- [2026-03-30] **Infrastructure** — Implement schema describing all manifold 
  state paths. Original TODO added 2026-03-04. @feature @schema @state
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2347`

- [2026-03-30] **Feature** — Implement subscription management. Original TODO 
  added 2026-03-04. @feature @subscriptions @state
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2399`

- [2026-03-30] **Feature** — Implement unsubscription mechanism. Original TODO 
  added 2026-03-04. @feature @subscriptions @state
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2405`

- [2026-03-30] **Feature** — Implement subscription clearing. Original TODO 
  added 2026-03-04. @feature @subscriptions @state
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2410`

- [2026-03-30] **Feature** — Implement pending change processing. Original TODO 
  added 2026-03-04. @feature @state @async
  **Source:** `manifold/core/BehaviorCoreProcessor.cpp:2414`

- [2026-03-30] **Audio** — Proper resampling if file rate != plugin rate. 
  Original TODO added 2026-03-04. @bug @audio @resampling
  **Source:** `manifold/primitives/control/ControlServer.cpp:1002`

- [2026-03-30] **MIDI** — Expose channelMask getter (currently returns 0xFFFF). 
  Original TODO added 2026-03-07. @feature @midi @api
  **Source:** `manifold/primitives/scripting/bindings/LuaMidiBindings.cpp:261`

- [2026-03-30] **MIDI** — Implement MIDI learn functionality. Original TODO 
  added 2026-03-06. @feature @midi @learn
  **Source:** `manifold/primitives/scripting/bindings/LuaMidiBindings.cpp:283`

- [2026-03-30] **MIDI** — Implement MIDI mapping removal. Original TODO added 
  2026-03-06. @feature @midi @learn
  **Source:** `manifold/primitives/scripting/bindings/LuaMidiBindings.cpp:290`

- [2026-03-30] **MIDI** — Populate stored MIDI mappings from persistence. 
  Original TODO added 2026-03-06. @feature @midi @persistence
  **Source:** `manifold/primitives/scripting/bindings/LuaMidiBindings.cpp:296`

- [2026-03-30] **BUG** — Graph disables on every UI switch, killing all audio. 
  This is a real bug affecting audio continuity. Original comment added 
  2026-03-04. @bug @audio @ui @critical
  **Source:** `manifold/primitives/scripting/LuaEngine.cpp:1416`

- [2026-03-30] **UI Polish** — Popup bounds handling needs refinement. Popup 
  placement is visually correct but bounds need work. Original TODO added 
  2026-03-24. @ui @polish @widgets
  **Source:** `manifold/ui/widgets/dropdown.lua:396`

- [2026-03-30] **Test Plugin** — Implement change tracking in Tempus plugin. 
  Original TODO added 2026-02-28. @test @plugin @low-priority
  **Source:** `test_plugins/Tempus/TempusPlugin.cpp:276`

- [2026-03-30] ~~Investigate main Manifold project (not UserScripts) for god 
  objects, bloated functions/methods, and files that would benefit from 
  decomposition.~~ 
  **COMPLETED BY KIMI (Agent)** - See report at 
  `agent-docs/reports/260331_god_object_investigation.md`
  @agent @investigate @refactor @architecture @code-quality @completed

- [2026-03-30] MIDI synth keyboard panel enhancements: (1) Add grab handle above 
  keyboard canvas for dynamic resize (drag up/down), (2) Add scrollable section 
  displaying all MIDI parameters advertised by connected hardware device as 
  sliders/labels/controls for quick access to onboard MIDI params. @feature @ui 
  @midi @keyboard @hardware

- [2026-03-30] **BUG** — MIDI synth sample synth object: distortion parameters 
  in the wave tab do not seem to work. 
  **INVESTIGATED BY KIMI (Agent)** - See report at
  `agent-docs/reports/260331_midi_synth_distortion_bug_investigation.md`
  @bug @midi @wave @distortion @investigated

- [2026-03-30] **BUG** — MIDI synth sample synth object: in the blend tab, pitch 
  is currently only working for sample and is no longer working for wave. 
  **INVESTIGATED BY KIMI (Agent)** - Regression. `blendSamplePitch` pitch knob 
  previously affected both wave and sample, now only affects sample. See report at
  `agent-docs/reports/260331_midi_synth_blend_pitch_bug_investigation.md`
  @bug @midi @blend @pitch @regression @investigated

- [x] [2026-03-30] **BUG** — Effects parameter dropdown in patch view does not update 
  to reflect the current selection, even though the parameter itself correctly 
  updates to the new effect. UI display out of sync with actual value. @bug 
  @ui @patch @effects @dropdown (Fixed: widget_sync.lua used wrong method names 
  getSelectedItemIndex/setSelectedItemIndex instead of getSelected/setSelected)

- [x] [2026-03-30] **REGRESSION** — MIDI synth default view on startup is currently 
  patch view but should be performance/play view instead. @agent @regression 
  @midi @ui @view (Fixed: runtime_state.lua had rackViewMode="patch", changed to "perf")

- [2026-03-30] MIDI keyboard should allow changing the number of keys displayed 
  in the keyboard area (octave range / key count control). @feature @midi 
  @keyboard @ui

- [2026-03-30] MIDI synth project should have a drag-out inspector/editor area 
  from the right side (three dots handle) — can reuse the editor component from 
  edit view. @feature @midi @ui @inspector @editor

- [2026-03-30] **REGRESSION** — After performance optimizations, Main tab host 
  sometimes only loads as labels (not full UI). Issue with rendering/partial 
  initialization. @bug @regression @ui @tabs @performance

- [2026-03-30] **BUG** — Pushing items off the third row via insert or expand 
  causes them to disappear (overflows to 4th row, but 4th row navigation is not 
  yet implemented). Unexpected behavior / data loss risk. @bug @ui @grid 
  @navigation @overflow



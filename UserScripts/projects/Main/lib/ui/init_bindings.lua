-- Init Bindings Module
-- Owns component bootstrap and DSP/UI callback wiring during init.

local M = {}

function M.bindComponents(ctx, deps)
  deps = deps or {}

  local widgets = ctx.widgets or {}
  local PATHS = deps.PATHS or {}
  local SAMPLE_SOURCE_OPTIONS = deps.SAMPLE_SOURCE_OPTIONS or {}
  local DRIVE_SHAPE_OPTIONS = deps.DRIVE_SHAPE_OPTIONS or {}
  local BLEND_MODE_OPTIONS = deps.BLEND_MODE_OPTIONS or {}

  local getScopedWidget = deps.getScopedWidget
  local getScopedBehavior = deps.getScopedBehavior
  local setPath = deps.setPath
  local readParam = deps.readParam
  local clamp = deps.clamp
  local round = deps.round
  local sanitizeBlendMode = deps.sanitizeBlendMode
  local setWidgetInteractiveState = deps.setWidgetInteractiveState
  local formatMidiNoteValue = deps.formatMidiNoteValue
  local getTime = deps.getTime

  ctx._portSpecs = {
    envelopeComponent = { outputs = {{ id = "cv_out", type = "cv", y = 0.5 }} },
    oscillatorComponent = {
      inputs = {{ id = "cv_in", type = "cv", y = 0.35 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.65 }}
    },
    filterComponent = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    fx1Component = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    fx2Component = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }},
      outputs = {{ id = "audio_out", type = "audio", y = 0.5 }}
    },
    eqComponent = {
      inputs = {{ id = "audio_in", type = "audio", y = 0.5 }}
    },
  }

  local function scopedBehavior(suffix)
    return getScopedBehavior(ctx, suffix)
  end

  local function scopedWidget(suffix)
    return getScopedWidget(ctx, suffix)
  end

  -- Oscillator component → DSP
  local oscBehavior = scopedBehavior(".oscillatorComponent")
  local oscCtx = oscBehavior and oscBehavior.ctx or nil
  local oscModule = oscBehavior and oscBehavior.module or nil
  ctx._oscCtx = oscCtx
  ctx._oscModule = oscModule

  local oscWfDrop = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.waveform_dropdown")
  local oscRenderModeTabs = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.render_mode_tabs")
  local oscSampleSourceDrop = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_source_dropdown")
  local oscSamplePitchMapToggle = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_map_toggle")
  local oscSamplePitchMode = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_mode")
  local oscSampleCaptureModeToggle = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_capture_mode_toggle")
  local oscSampleCaptureBtn = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_capture_button")
  local oscSampleRootBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_root_box")
  local oscSampleBarsBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_bars_box")
  local oscSampleXfadeBox = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_xfade_box")
  local oscSamplePvocFFT = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pvoc_fft")
  local oscSamplePvocStretch = scopedWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pvoc_stretch")
  local oscDriveModeDrop = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_mode_dropdown")
  local oscDrive = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_knob")
  local oscDriveBias = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_bias_knob")
  local oscAddPartials = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_partials_knob")
  local oscAddTilt = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_tilt_knob")
  local oscAddDrift = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.add_drift_knob")
  local oscOutput = scopedWidget(".oscillatorComponent.output_knob")
  local oscPulseWidth = scopedWidget(".oscillatorComponent.mode_tabs.wave_tab.pulse_width_knob")
  local oscUnison = scopedWidget(".oscillatorComponent.unison_knob")
  local oscDetune = scopedWidget(".oscillatorComponent.detune_knob")
  local oscSpread = scopedWidget(".oscillatorComponent.spread_knob")
  local oscBlendModeDrop = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mode_dropdown")
  local oscBlendKeyTrackRadio = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_key_track_radio")
  local oscBlendAmount = scopedWidget(".oscillatorComponent.blend_amount_knob")
  local oscBlendSamplePitch = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob")
  local oscBlendModAmount = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob")
  local oscAddFlavorToggle = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle")
  local oscMorphCurve = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve")
  local oscMorphConvergence = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence")
  local oscMorphPhase = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase")
  local oscMorphSpeed = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed")
  local oscMorphContrast = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast")
  local oscMorphSmooth = scopedWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth")

  local function setSampleCaptureButtonRecording(recording)
    local isRecording = recording == true
    if oscCtx then
      oscCtx.sampleCaptureRecording = isRecording
    end
    if oscSampleCaptureBtn then
      oscSampleCaptureBtn:setLabel(isRecording and "STOP" or "Cap")
      oscSampleCaptureBtn:setBg(isRecording and 0xffdc2626 or 0xff334155)
    end
  end

  local function pulseSampleCaptureTrigger()
    setPath(PATHS.sampleCaptureTrigger, 1)
    setPath(PATHS.sampleCaptureTrigger, 0)
  end

  if oscCtx then
    oscCtx.sampleCaptureRecording = false

    oscCtx._onRangeChange = function(which, value)
      if which == "start" then
        setPath(PATHS.sampleLoopStart, clamp(value, 0.0, 0.95))
      elseif which == "len" then
        setPath(PATHS.sampleLoopLen, clamp(value, 0.05, 1.0))
      end
    end

    oscCtx._onPlayStartChange = function(value)
      setPath(PATHS.samplePlayStart, clamp(value, 0.0, 0.99))
    end
  end

  local function refreshOscGraph()
    if not oscCtx or not oscModule then
      return
    end
    if oscModule.repaint then
      oscModule.repaint(oscCtx)
    else
      oscModule.resized(oscCtx)
    end
  end

  if oscSampleSourceDrop and oscSampleSourceDrop.setOptions then
    oscSampleSourceDrop:setOptions(SAMPLE_SOURCE_OPTIONS)
  end
  if oscSampleRootBox and oscSampleRootBox.setValueFormatter then
    oscSampleRootBox:setValueFormatter(function(v)
      return formatMidiNoteValue(v)
    end)
  end
  if oscDriveModeDrop and oscDriveModeDrop.setOptions then
    oscDriveModeDrop:setOptions(DRIVE_SHAPE_OPTIONS)
  end
  if oscBlendModeDrop and oscBlendModeDrop.setOptions then
    oscBlendModeDrop:setOptions(BLEND_MODE_OPTIONS)
  end

  if oscWfDrop then
    oscWfDrop._onSelect = function(idx)
      setPath(PATHS.waveform, idx - 1)
      if oscCtx then
        oscCtx.waveformType = idx - 1
        refreshOscGraph()
        if oscModule and oscModule.updateKnobLayout then
          oscModule.updateKnobLayout(oscCtx)
        end
      end
    end
  end

  if oscRenderModeTabs then
    oscRenderModeTabs._onSelect = function(idx)
      local mode = math.max(0, math.min(1, idx - 1))
      setPath(PATHS.oscRenderMode, mode)
      if oscCtx then
        oscCtx.renderMode = mode
        refreshOscGraph()
        if oscModule and oscModule.updateKnobLayout then
          oscModule.updateKnobLayout(oscCtx)
        end
      end
    end
  end

  if oscSampleSourceDrop then
    oscSampleSourceDrop._onSelect = function(idx)
      setPath(PATHS.sampleSource, idx - 1)
    end
  end

  if oscSamplePitchMapToggle then
    oscSamplePitchMapToggle._onChange = function(v)
      setPath(PATHS.samplePitchMapEnabled, v and 1 or 0)
    end
  end

  if oscSamplePitchMode then
    oscSamplePitchMode._onSelect = function(idx)
      local mode = math.max(0, math.min(2, idx - 1))
      setPath(PATHS.samplePitchMode, mode)
      if oscCtx then
        oscCtx.samplePitchMode = mode
        refreshOscGraph()
      end
      if oscSamplePvocStretch and oscSamplePvocStretch.node and oscSamplePvocStretch.node.setVisible then
        oscSamplePvocStretch.node:setVisible(mode == 2)
      end
    end
  end

  if oscSampleCaptureModeToggle then
    oscSampleCaptureModeToggle._onChange = function(v)
      local modeStr = v and "free" or "retro"
      print("Capture mode changed to: " .. modeStr)
      setPath(PATHS.sampleCaptureMode, v and 1 or 0)
      if not v then
        setSampleCaptureButtonRecording(false)
      end
    end
  end

  if oscSampleCaptureBtn then
    oscSampleCaptureBtn._onClick = nil
    oscSampleCaptureBtn._onPress = function()
      local freeMode = (round(readParam(PATHS.sampleCaptureMode, 0)) == 1)
      if freeMode then
        local recording = (readParam(PATHS.sampleCaptureRecording, (oscCtx and oscCtx.sampleCaptureRecording) and 1 or 0) or 0) > 0.5
        local nextRecording = not recording
        setSampleCaptureButtonRecording(nextRecording)
        ctx._lastEvent = nextRecording and "Recording..." or "Sample captured (free)"
      else
        ctx._lastEvent = "Sample captured"
      end
      pulseSampleCaptureTrigger()
      if oscCtx then
        oscCtx._cachedPeaks = nil
      end
    end
  end

  if oscSampleBarsBox then
    oscSampleBarsBox._onChange = function(v)
      setPath(PATHS.sampleCaptureBars, v)
    end
  end

  if oscSampleRootBox then
    oscSampleRootBox._onChange = function(v)
      setPath(PATHS.sampleRootNote, round(v))
    end
  end

  if oscSampleXfadeBox then
    oscSampleXfadeBox._onChange = function(v)
      setPath(PATHS.sampleCrossfade, clamp(v / 100.0, 0.0, 0.5))
      if oscCtx then
        oscCtx.sampleCrossfade = clamp(v / 100.0, 0.0, 0.5)
        refreshOscGraph()
      end
    end
  end

  if oscSamplePvocFFT then
    oscSamplePvocFFT._onChange = function(v)
      setPath(PATHS.samplePvocFFTOrder, math.max(9, math.min(12, round(v))))
    end
  end

  if oscSamplePvocStretch then
    oscSamplePvocStretch._onChange = function(v)
      setPath(PATHS.samplePvocTimeStretch, clamp(v, 0.25, 4.0))
    end
  end

  if oscDriveModeDrop then
    oscDriveModeDrop._onSelect = function(idx)
      local shape = math.max(0, math.min(#DRIVE_SHAPE_OPTIONS - 1, idx - 1))
      setPath(PATHS.driveShape, shape)
      if oscCtx then
        oscCtx.driveShape = shape
        refreshOscGraph()
      end
    end
  end

  if oscDrive then
    oscDrive._onChange = function(v)
      setPath(PATHS.drive, v)
      if oscCtx then
        oscCtx.driveAmount = v
        refreshOscGraph()
      end
    end
  end

  if oscDriveBias then
    oscDriveBias._onChange = function(v)
      setPath(PATHS.driveBias, v)
      if oscCtx then
        oscCtx.driveBias = v
        refreshOscGraph()
      end
    end
  end

  if oscAddPartials then
    oscAddPartials._onChange = function(v)
      local partials = round(v)
      setPath(PATHS.additivePartials, partials)
      if oscCtx then
        oscCtx.additivePartials = partials
        refreshOscGraph()
      end
    end
  end

  if oscAddTilt then
    oscAddTilt._onChange = function(v)
      setPath(PATHS.additiveTilt, v)
      if oscCtx then
        oscCtx.additiveTilt = v
        refreshOscGraph()
      end
    end
  end

  if oscAddDrift then
    oscAddDrift._onChange = function(v)
      setPath(PATHS.additiveDrift, v)
      if oscCtx then
        oscCtx.additiveDrift = v
        refreshOscGraph()
      end
    end
  end

  if oscOutput then
    oscOutput._onChange = function(v)
      setPath(PATHS.output, v)
      if oscCtx then
        oscCtx.outputLevel = v
        refreshOscGraph()
      end
    end
  end

  if oscPulseWidth then
    oscPulseWidth._onChange = function(v)
      setPath(PATHS.pulseWidth, v)
      if oscCtx then
        oscCtx.pulseWidth = v
        refreshOscGraph()
      end
    end
  end

  if oscUnison then
    oscUnison._onChange = function(v)
      setPath(PATHS.unison, v)
      if oscCtx then
        oscCtx.unison = v
        refreshOscGraph()
      end
    end
  end

  if oscDetune then
    oscDetune._onChange = function(v)
      setPath(PATHS.detune, v)
      if oscCtx then
        oscCtx.detune = v
        refreshOscGraph()
      end
    end
  end

  if oscSpread then
    oscSpread._onChange = function(v)
      setPath(PATHS.spread, v)
      if oscCtx then
        oscCtx.spread = v
        refreshOscGraph()
      end
    end
  end

  if oscBlendModeDrop then
    oscBlendModeDrop._onSelect = function(idx)
      local mode = sanitizeBlendMode(idx - 1)
      setPath(PATHS.blendMode, mode)
      setWidgetInteractiveState(oscUnison, true)
      setWidgetInteractiveState(oscDetune, true)
      setWidgetInteractiveState(oscSpread, true)
      if oscCtx then
        oscCtx.blendMode = mode
        refreshOscGraph()
      end
    end
  end

  if oscBlendKeyTrackRadio then
    oscBlendKeyTrackRadio._onChange = function(idx)
      local val = (idx == 1) and 0 or (idx == 2) and 1 or 2
      setPath(PATHS.blendKeyTrack, val)
      if oscCtx then
        oscCtx.blendKeyTrackMode = val
        refreshOscGraph()
      end
    end
  end

  if oscBlendAmount then
    oscBlendAmount._onChange = function(v)
      setPath(PATHS.blendAmount, v)
      if oscCtx then
        oscCtx.blendAmount = v
        refreshOscGraph()
      end
    end
  end

  if oscBlendSamplePitch then
    oscBlendSamplePitch._onChange = function(v)
      setPath(PATHS.blendSamplePitch, v)
      if oscCtx then
        oscCtx.blendSamplePitch = v
        refreshOscGraph()
      end
    end
  end

  if oscBlendModAmount then
    oscBlendModAmount._onChange = function(v)
      setPath(PATHS.blendModAmount, v)
      if oscCtx then
        oscCtx.blendModAmount = v
        refreshOscGraph()
      end
    end
  end

  if oscAddFlavorToggle then
    oscAddFlavorToggle._onSelect = function(idx)
      local flavor = (idx == 2) and 1 or 0
      setPath(PATHS.addFlavor, flavor)
      if oscCtx then
        oscCtx.addFlavor = flavor
        refreshOscGraph()
      end
    end
  end

  if oscMorphCurve then
    oscMorphCurve._onSelect = function(idx)
      local curve = math.max(0, math.min(2, idx - 1))
      setPath(PATHS.morphCurve, curve)
      if oscCtx then
        oscCtx.morphCurve = curve
        refreshOscGraph()
      end
    end
  end

  if oscMorphConvergence then
    oscMorphConvergence._onChange = function(v)
      local convergence = math.max(0, math.min(1, tonumber(v) or 0))
      setPath(PATHS.morphConvergence, convergence)
      if oscCtx then
        oscCtx.morphStretch = convergence
        refreshOscGraph()
      end
    end
  end

  if oscMorphPhase then
    oscMorphPhase._onSelect = function(idx)
      local phase = math.max(0, math.min(2, idx - 1))
      setPath(PATHS.morphPhase, phase)
      if oscCtx then
        oscCtx.morphPhase = phase
        refreshOscGraph()
      end
    end
  end

  if oscMorphSpeed then
    oscMorphSpeed._onChange = function(v)
      local speed = math.max(0.1, math.min(4.0, tonumber(v) or 1.0))
      if PATHS.morphSpeed then
        setPath(PATHS.morphSpeed, speed)
      end
      if oscCtx then
        oscCtx.morphSpeed = speed
        refreshOscGraph()
      end
    end
  end

  if oscMorphContrast then
    oscMorphContrast._onChange = function(v)
      local contrast = math.max(0.0, math.min(2.0, tonumber(v) or 0.5))
      if PATHS.morphContrast then
        setPath(PATHS.morphContrast, contrast)
      end
      if oscCtx then
        oscCtx.morphContrast = contrast
        refreshOscGraph()
      end
    end
  end

  if oscMorphSmooth then
    oscMorphSmooth._onChange = function(v)
      local smooth = math.max(0.0, math.min(1.0, tonumber(v) or 0.0))
      if PATHS.morphSmooth then
        setPath(PATHS.morphSmooth, smooth)
      end
      if oscCtx then
        oscCtx.morphSmooth = smooth
        refreshOscGraph()
      end
    end
  end

  -- Envelope ADSR component → DSP + graph refresh
  local envBehavior = scopedBehavior(".envelopeComponent")
  local envCtx = envBehavior and envBehavior.ctx or nil
  local envModule = envBehavior and envBehavior.module or nil
  ctx._envCtx = envCtx
  ctx._envModule = envModule

  local envAttack = scopedWidget(".envelopeComponent.attack_knob")
  local envDecay = scopedWidget(".envelopeComponent.decay_knob")
  local envSustain = scopedWidget(".envelopeComponent.sustain_knob")
  local envRelease = scopedWidget(".envelopeComponent.release_knob")

  if envAttack then
    envAttack._onChange = function(v)
      local s = v / 1000.0
      setPath(PATHS.attack, s)
      if envCtx then
        envCtx.values.attack = s
        envModule.resized(envCtx)
      end
    end
  end

  if envDecay then
    envDecay._onChange = function(v)
      local s = v / 1000.0
      setPath(PATHS.decay, s)
      if envCtx then
        envCtx.values.decay = s
        envModule.resized(envCtx)
      end
    end
  end

  if envSustain then
    envSustain._onChange = function(v)
      local s = v / 100.0
      setPath(PATHS.sustain, s)
      if envCtx then
        envCtx.values.sustain = s
        envModule.resized(envCtx)
      end
    end
  end

  if envRelease then
    envRelease._onChange = function(v)
      local s = v / 1000.0
      setPath(PATHS.release, s)
      if envCtx then
        envCtx.values.release = s
        envModule.resized(envCtx)
      end
    end
  end

  if widgets.filterTypeDropdown then
    widgets.filterTypeDropdown._onSelect = function(idx)
      setPath(PATHS.filterType, idx - 1)
    end
  end

end

return M

-- Update Sync Module
-- Syncs DSP state to UI widgets in the update loop

local WidgetSync = require("ui.widget_sync")
local ScopedWidget = require("ui.scoped_widget")

local M = {}

-- Re-export helpers
local round = WidgetSync.round
local syncValue = WidgetSync.syncValue
local syncSelected = WidgetSync.syncSelected
local syncText = WidgetSync.syncText
local syncColour = WidgetSync.syncColour
local syncKnobLabel = WidgetSync.syncKnobLabel
local getScopedWidget = ScopedWidget.getScopedWidget

-- Main update function
function M.update(ctx, deps)
  deps = deps or {}
  local BG_TICK_INTERVAL = deps.BG_TICK_INTERVAL or 0.1
  local OSC_REPAINT_INTERVAL = deps.OSC_REPAINT_INTERVAL or 0.033
  local OSC_REPAINT_INTERVAL_WHILE_INTERACTING = deps.OSC_REPAINT_INTERVAL_WHILE_INTERACTING or 0.016
  local OSC_REPAINT_INTERVAL_MULTI_VOICE = deps.OSC_REPAINT_INTERVAL_MULTI_VOICE or 0.05
  local ENV_REPAINT_INTERVAL = deps.ENV_REPAINT_INTERVAL or 0.033
  local ENV_REPAINT_INTERVAL_WHILE_INTERACTING = deps.ENV_REPAINT_INTERVAL_WHILE_INTERACTING or 0.016
  local VOICE_COUNT = deps.VOICE_COUNT or 8
  local FILTER_OPTIONS = deps.FILTER_OPTIONS
  local FxDefs = deps.FxDefs
  local PATHS = deps.PATHS
  
  -- Callbacks
  local getTime = deps.getTime
  local backgroundTick = deps.backgroundTick
  local isUiInteracting = deps.isUiInteracting
  local maybeRefreshMidiDevices = deps.maybeRefreshMidiDevices
  local syncPatchViewMode = deps.syncPatchViewMode
  local RackWireLayer = deps.RackWireLayer
  local readParam = deps.readParam
  local setPath = deps.setPath
  local sanitizeBlendMode = deps.sanitizeBlendMode
  local getVoiceStackingLabels = deps.getVoiceStackingLabels
  local setWidgetInteractiveState = deps.setWidgetInteractiveState
  local setWidgetBounds = deps.setWidgetBounds
  local isPluginMode = deps.isPluginMode
  local activeVoiceCount = deps.activeVoiceCount
  local voiceSummary = deps.voiceSummary
  local noteName = deps.noteName
  local formatTime = deps.formatTime
  local syncKeyboardDisplay = deps.syncKeyboardDisplay
  local syncMidiParamRack = deps.syncMidiParamRack
  local cleanupPatchbayFromRuntime = deps.cleanupPatchbayFromRuntime
  local patchbayInstances = deps.patchbayInstances
  local ensurePatchbayWidgets = deps.ensurePatchbayWidgets
  local syncPatchbayValues = deps.syncPatchbayValues
  local clamp = deps.clamp
  local setWidgetValueSilently = deps.setWidgetValueSilently
  local getModTargetState = deps.getModTargetState

  local now = getTime and getTime() or 0
  if now - (ctx._lastUpdateTime or 0) > BG_TICK_INTERVAL then
    backgroundTick(ctx)
  end

  local widgets = ctx.widgets or {}
  local uiInteracting = isUiInteracting(ctx)

  local dt = now - (ctx._lastUiUpdateTime or now)
  ctx._lastUiUpdateTime = now

  maybeRefreshMidiDevices(ctx, now)

  if (ctx._patchViewBootstrapFrames or 0) > 0 then
    local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
    if viewMode == "patch" then
      syncPatchViewMode(ctx)
      if RackWireLayer and RackWireLayer.refreshWires then
        RackWireLayer.refreshWires(ctx)
      end
      local registry = ctx._patchbayPortRegistry or {}
      local registryCount = 0
      for _ in pairs(registry) do
        registryCount = registryCount + 1
      end
      if registryCount > 0 then
        ctx._patchViewBootstrapFrames = ctx._patchViewBootstrapFrames - 1
      end
    else
      ctx._patchViewBootstrapFrames = 0
    end
  end

  if ctx._pendingAdditiveParamSync then
    local pending = ctx._pendingAdditiveParamSync
    pending.attempts = (pending.attempts or 0) + 1
    local currentPartials = readParam(PATHS.additivePartials, pending.partials)
    local currentTilt = readParam(PATHS.additiveTilt, pending.tilt)
    local currentDrift = readParam(PATHS.additiveDrift, pending.drift)
    if math.abs((tonumber(currentPartials) or 0) - (tonumber(pending.partials) or 8)) > 0.0001 then
      setPath(PATHS.additivePartials, pending.partials)
    end
    if math.abs((tonumber(currentTilt) or 0) - (tonumber(pending.tilt) or 0.0)) > 0.0001 then
      setPath(PATHS.additiveTilt, pending.tilt)
    end
    if math.abs((tonumber(currentDrift) or 0) - (tonumber(pending.drift) or 0.0)) > 0.0001 then
      setPath(PATHS.additiveDrift, pending.drift)
    end
    if pending.attempts >= 4 then
      ctx._pendingAdditiveParamSync = nil
    end
  end

  local waveform = round(readParam(PATHS.waveform, 1))
  local filterType = round(readParam(PATHS.filterType, 0))
  local cutoff = readParam(PATHS.cutoff, 3200)
  local resonance = readParam(PATHS.resonance, 0.75)
  local drive = readParam(PATHS.drive, 0.0)
  local driveShape = round(readParam(PATHS.driveShape, 0))
  local driveBias = readParam(PATHS.driveBias, 0.0)
  local oscRenderMode = round(readParam(PATHS.oscRenderMode, 0))
  local fx1Type = round(readParam(PATHS.fx1Type, 0))
  local fx1Mix = readParam(PATHS.fx1Mix, 0.0)
  local fx2Type = round(readParam(PATHS.fx2Type, 0))
  local fx2Mix = readParam(PATHS.fx2Mix, 0.0)
  local delayTime = readParam(PATHS.delayTimeL, 220)
  local delayFeedback = readParam(PATHS.delayFeedback, 0.24)
  local delayMix = readParam(PATHS.delayMix, 0.0)
  local reverbWet = readParam(PATHS.reverbWet, 0.0)
  local output = readParam(PATHS.output, 0.8)
  local attack = readParam(PATHS.attack, 0.05)
  local decay = readParam(PATHS.decay, 0.2)
  local sustain = readParam(PATHS.sustain, 0.7)
  local release = readParam(PATHS.release, 0.4)

  local sampleSource = round(readParam(PATHS.sampleSource, 0))
  local sampleCaptureBars = readParam(PATHS.sampleCaptureBars, 1.0)
  local sampleCaptureMode = round(readParam(PATHS.sampleCaptureMode, 0))
  local samplePitchMapEnabled = (readParam(PATHS.samplePitchMapEnabled, 0.0) or 0.0) > 0.5
  local samplePitchMode = round(readParam(PATHS.samplePitchMode, 0))
  local sampleRootNote = readParam(PATHS.sampleRootNote, 60.0)
  local sampleLoopStartPct = readParam(PATHS.sampleLoopStart, 0.0) * 100.0
  local sampleLoopLenPct = readParam(PATHS.sampleLoopLen, 1.0) * 100.0
  local sampleRetrigger = readParam(PATHS.sampleRetrigger, 1.0) > 0.5
  local rawBlendMode = round(readParam(PATHS.blendMode, 0))
  local blendMode = sanitizeBlendMode(rawBlendMode)
  if blendMode ~= rawBlendMode then
    setPath(PATHS.blendMode, blendMode)
  end
  local blendAmount = readParam(PATHS.blendAmount, 0.5)
  local blendKeyTrackMode = round(readParam(PATHS.blendKeyTrack, 2))
  local blendSamplePitch = readParam(PATHS.blendSamplePitch, 0.0)
  local blendModAmount = readParam(PATHS.blendModAmount, 0.5)
  local addFlavor = round(readParam(PATHS.addFlavor, 0))

  ctx._adsr.attack = attack
  ctx._adsr.decay = decay
  ctx._adsr.sustain = sustain
  ctx._adsr.release = release

  local maxAmp = 0
  local dominantFreq = 220
  for i = 1, VOICE_COUNT do
    local voice = ctx._voices[i]
    if voice.currentAmp > maxAmp then
      maxAmp = voice.currentAmp
      dominantFreq = voice.freq or dominantFreq
    end
  end

  local function liveWidget(suffix)
    return getScopedWidget(ctx, suffix)
  end

  local function setWidgetBaseValue(widget, value)
    if not widget or not widget.setValue then
      return
    end
    local current = widget.getValue and widget:getValue() or nil
    if current ~= nil and math.abs((tonumber(current) or 0) - (tonumber(value) or 0)) <= 0.0001 then
      return
    end
    if setWidgetValueSilently then
      setWidgetValueSilently(widget, value)
    else
      widget:setValue(value)
    end
  end

  local function syncModulatedWidget(widget, path, fallbackValue, mapDisplayValue)
    if not widget or not path then
      return fallbackValue, fallbackValue, nil
    end

    local rawValue = fallbackValue
    if rawValue == nil then
      rawValue = readParam(path, 0)
    end

    local modState = type(getModTargetState) == "function" and getModTargetState(path) or nil
    local baseValue = modState and tonumber(modState.baseValue) or rawValue
    local effectiveValue = modState and tonumber(modState.effectiveValue) or rawValue
    if type(mapDisplayValue) == "function" then
      rawValue = mapDisplayValue(rawValue)
      baseValue = mapDisplayValue(baseValue)
      effectiveValue = mapDisplayValue(effectiveValue)
    end
    local overlayEnabled = modState ~= nil and math.abs((effectiveValue or 0) - (baseValue or 0)) > 0.0001

    if widget.setValue and not widget._dragging then
      setWidgetBaseValue(widget, baseValue)
    end

    if widget.setModulationState then
      widget:setModulationState(baseValue, effectiveValue, {
        enabled = overlayEnabled,
      })
    end

    return baseValue, effectiveValue, modState
  end

  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.waveform_dropdown"), waveform + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.render_mode_tabs"), oscRenderMode + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_mode_dropdown"), driveShape + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mode_dropdown"), blendMode + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_source_dropdown"), sampleSource + 1)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_mode"), samplePitchMode + 1)

  local pvocStretchWidget = liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pvoc_stretch")
  if pvocStretchWidget and pvocStretchWidget.node and pvocStretchWidget.node.setVisible then
    pvocStretchWidget.node:setVisible(samplePitchMode == 2)
  end

  local samplePitchMapToggle = liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pitch_map_toggle")
  if samplePitchMapToggle and samplePitchMapToggle.getValue and samplePitchMapToggle.setValue then
    if samplePitchMapToggle:getValue() ~= samplePitchMapEnabled then
      samplePitchMapToggle:setValue(samplePitchMapEnabled)
    end
  end

  local tabHost = liveWidget(".oscillatorComponent.mode_tabs")
  local currentTab = tabHost and tabHost.getActiveIndex and tabHost:getActiveIndex() or 1

  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_bars_box"), PATHS.sampleCaptureBars, sampleCaptureBars)

  local sampleCaptureRecording = (readParam(PATHS.sampleCaptureRecording, 0.0) or 0.0) > 0.5
  local sampleCaptureBtn = liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_capture_button")
  if sampleCaptureBtn then
    sampleCaptureBtn:setLabel((sampleCaptureMode == 1 and sampleCaptureRecording) and "STOP" or "Cap")
    sampleCaptureBtn:setBg((sampleCaptureMode == 1 and sampleCaptureRecording) and 0xffdc2626 or 0xff334155)
  end
  if ctx._oscCtx then
    ctx._oscCtx.sampleCaptureRecording = sampleCaptureRecording
  end

  local sampleLengthLabel = liveWidget(".oscillatorComponent.sample_length_label")
  if sampleLengthLabel then
    if currentTab == 2 then
      if sampleLengthLabel.setText then
        local lengthMs = math.max(0, math.floor(tonumber(readParam(PATHS.sampleCapturedLengthMs, 0)) or 0))
        sampleLengthLabel:setText(tostring(lengthMs) .. "ms")
      end
      if sampleLengthLabel.node and sampleLengthLabel.node.setVisible then
        sampleLengthLabel.node:setVisible(true)
      end
    else
      if sampleLengthLabel.node and sampleLengthLabel.node.setVisible then
        sampleLengthLabel.node:setVisible(false)
      end
    end
  end

  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_root_box"), PATHS.sampleRootNote, sampleRootNote)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_xfade_box"), PATHS.sampleCrossfade, readParam(PATHS.sampleCrossfade, 0.1), function(v)
    return math.floor((tonumber(v) or 0.1) * 100)
  end)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pvoc_fft"), PATHS.samplePvocFFTOrder, readParam(PATHS.samplePvocFFTOrder, 11))
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.sample_tab.sample_pvoc_stretch"), PATHS.samplePvocTimeStretch, readParam(PATHS.samplePvocTimeStretch, 1.0))

  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_knob"), PATHS.drive, drive)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.drive_bias_knob"), PATHS.driveBias, driveBias)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_partials_knob"), PATHS.additivePartials, round(readParam(PATHS.additivePartials, 8)))
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_tilt_knob"), PATHS.additiveTilt, readParam(PATHS.additiveTilt, 0.0))
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.add_drift_knob"), PATHS.additiveDrift, readParam(PATHS.additiveDrift, 0.0))
  syncModulatedWidget(liveWidget(".oscillatorComponent.output_knob"), PATHS.output, output)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.wave_tab.pulse_width_knob"), PATHS.pulseWidth, readParam(PATHS.pulseWidth, 0.5))

  local unisonWidget = liveWidget(".oscillatorComponent.unison_knob")
  local detuneWidget = liveWidget(".oscillatorComponent.detune_knob")
  local spreadWidget = liveWidget(".oscillatorComponent.spread_knob")
  syncModulatedWidget(unisonWidget, PATHS.unison, readParam(PATHS.unison, 1))
  syncModulatedWidget(detuneWidget, PATHS.detune, readParam(PATHS.detune, 0))
  syncModulatedWidget(spreadWidget, PATHS.spread, readParam(PATHS.spread, 0))

  local unisonLabel, detuneLabel, spreadLabel = getVoiceStackingLabels(currentTab, oscRenderMode, blendMode)
  syncKnobLabel(unisonWidget, unisonLabel)
  syncKnobLabel(detuneWidget, detuneLabel)
  syncKnobLabel(spreadWidget, spreadLabel)

  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_key_track_radio"), blendKeyTrackMode + 1)
  syncModulatedWidget(liveWidget(".oscillatorComponent.blend_amount_knob"), PATHS.blendAmount, blendAmount)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob"), PATHS.blendSamplePitch, blendSamplePitch)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob"), PATHS.blendModAmount, blendModAmount)
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle"), addFlavor + 1)

  local addFlavorToggle = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.add_flavor_toggle")
  if addFlavorToggle then
    local visible = blendMode == 4
    if addFlavorToggle.setVisible then
      addFlavorToggle:setVisible(visible)
    elseif addFlavorToggle.node and addFlavorToggle.node.setVisible then
      addFlavorToggle.node:setVisible(visible)
    end
  end

  local blendSamplePitchWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_sample_pitch_knob")
  if blendSamplePitchWidget then
    if blendSamplePitchWidget.setVisible then
      blendSamplePitchWidget:setVisible(true)
    elseif blendSamplePitchWidget.node and blendSamplePitchWidget.node.setVisible then
      blendSamplePitchWidget.node:setVisible(true)
    end
  end

  local blendModAmountWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.blend_mod_amount_knob")
  if blendModAmountWidget then
    if blendModAmountWidget.setVisible then
      blendModAmountWidget:setVisible(true)
    elseif blendModAmountWidget.node and blendModAmountWidget.node.setVisible then
      blendModAmountWidget.node:setVisible(true)
    end
  end

  local addActive = blendMode == 4
  local morphActive = blendMode == 5
  local temporalActive = addActive or morphActive

  local phaseWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase")
  local speedWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed")
  local contrastWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast")
  local smoothWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth")
  local stretchWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence")
  local curveWidget = liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve")

  for _, w in ipairs({ phaseWidget, speedWidget, contrastWidget, smoothWidget, stretchWidget }) do
    if w then
      if w.setVisible then w:setVisible(temporalActive)
      elseif w.node and w.node.setVisible then w.node:setVisible(temporalActive) end
    end
  end

  if curveWidget then
    if curveWidget.setVisible then curveWidget:setVisible(morphActive)
    elseif curveWidget.node and curveWidget.node.setVisible then curveWidget.node:setVisible(morphActive) end
  end

  local rowX = 10
  local rowW = 200
  local rowH = 20
  local gap = 8
  local halfW = 96
  if blendSamplePitchWidget then setWidgetBounds(blendSamplePitchWidget, rowX, 34, rowW, rowH) end
  if blendModAmountWidget then setWidgetBounds(blendModAmountWidget, rowX, 60, rowW, rowH) end

  if morphActive then
    if curveWidget then setWidgetBounds(curveWidget, rowX, 86, 74, rowH) end
    if phaseWidget then setWidgetBounds(phaseWidget, 92, 86, 118, rowH) end
    if speedWidget then setWidgetBounds(speedWidget, rowX, 112, halfW, rowH) end
    if contrastWidget then setWidgetBounds(contrastWidget, 114, 112, halfW, rowH) end
    if smoothWidget then setWidgetBounds(smoothWidget, rowX, 138, halfW, rowH) end
    if stretchWidget then setWidgetBounds(stretchWidget, 114, 138, halfW, rowH) end
  elseif addActive then
    if addFlavorToggle then setWidgetBounds(addFlavorToggle, rowX, 86, 86, rowH) end
    if phaseWidget then setWidgetBounds(phaseWidget, 104, 86, 106, rowH) end
    if speedWidget then setWidgetBounds(speedWidget, rowX, 112, halfW, rowH) end
    if contrastWidget then setWidgetBounds(contrastWidget, 114, 112, halfW, rowH) end
    if smoothWidget then setWidgetBounds(smoothWidget, rowX, 138, halfW, rowH) end
    if stretchWidget then setWidgetBounds(stretchWidget, 114, 138, halfW, rowH) end
  end

  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_curve"), round(readParam(PATHS.morphCurve, 2)) + 1)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_convergence"), PATHS.morphConvergence, readParam(PATHS.morphConvergence, 0))
  syncSelected(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_phase"), round(readParam(PATHS.morphPhase, 0)) + 1)
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_speed"), PATHS.morphSpeed, readParam(PATHS.morphSpeed, 1.0))
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_contrast"), PATHS.morphContrast, readParam(PATHS.morphContrast, 0.5))
  syncModulatedWidget(liveWidget(".oscillatorComponent.mode_tabs.blend_tab.morph_smooth"), PATHS.morphSmooth, readParam(PATHS.morphSmooth, 0.0))

  setWidgetInteractiveState(liveWidget(".oscillatorComponent.unison_knob"), true)
  setWidgetInteractiveState(liveWidget(".oscillatorComponent.detune_knob"), true)
  setWidgetInteractiveState(liveWidget(".oscillatorComponent.spread_knob"), true)

  local oscCtx = ctx._oscCtx
  if oscCtx then
    oscCtx.waveformType = waveform
    oscCtx.renderMode = oscRenderMode
    oscCtx.pulseWidth = readParam(PATHS.pulseWidth, 0.5)
    oscCtx.unison = readParam(PATHS.unison, 1)
    oscCtx.detune = readParam(PATHS.detune, 0)
    oscCtx.spread = readParam(PATHS.spread, 0)
    oscCtx.additivePartials = round(readParam(PATHS.additivePartials, 8))
    oscCtx.additiveTilt = readParam(PATHS.additiveTilt, 0.0)
    oscCtx.additiveDrift = readParam(PATHS.additiveDrift, 0.0)
    oscCtx.driveAmount = drive
    oscCtx.driveShape = driveShape
    oscCtx.driveBias = driveBias
    oscCtx.driveMix = 1.0
    oscCtx.outputLevel = output

    local oscModule = ctx._oscModule
    if oscModule and oscModule.updateKnobLayout then
      oscModule.updateKnobLayout(oscCtx)
    end

    oscCtx.oscMode = (currentTab == 2) and 1 or ((currentTab == 3) and 2 or 0)
    oscCtx.sampleLoopStart = sampleLoopStartPct / 100.0
    oscCtx.sampleLoopLen = sampleLoopLenPct / 100.0
    oscCtx.samplePlayStart = (readParam(PATHS.samplePlayStart, 0.0) or 0.0)
    oscCtx.sampleCrossfade = (readParam(PATHS.sampleCrossfade, 0.1) or 0.1)
    oscCtx.sampleCaptureRecording = sampleCaptureRecording
    oscCtx.samplePitchMode = samplePitchMode
    oscCtx.blendMode = blendMode
    oscCtx.blendAmount = blendAmount
    oscCtx.blendKeyTrackMode = blendKeyTrackMode
    oscCtx.blendSamplePitch = blendSamplePitch
    oscCtx.blendModAmount = blendModAmount
    oscCtx.addFlavor = addFlavor
    oscCtx.morphCurve = round(readParam(PATHS.morphCurve, 2))
    oscCtx.morphStretch = readParam(PATHS.morphConvergence, 0)
    oscCtx.morphTilt = round(readParam(PATHS.morphPhase, 0))
    oscCtx.morphSpeed = readParam(PATHS.morphSpeed, 1.0)
    oscCtx.morphContrast = readParam(PATHS.morphContrast, 0.5)
    oscCtx.morphSmooth = readParam(PATHS.morphSmooth, 0.0)

    local activeVoices = oscCtx.activeVoices or {}
    local activeCount = 0
    local dominantSamplePos = 0
    local dominantAmpForPos = 0
    local controlRouteState = ctx and ctx._controlRouteState or nil
    -- Direct ADSR -> oscillator wiring disappears once a voice rack chain sits in front
    -- of the legacy oscillator, but the canonical oscillator still receives transformed
    -- voice bundles and should keep its playhead / morph visuals alive.
    local canonicalOscRouteConnected = not not (
      controlRouteState
      and (
        controlRouteState.adsrToCanonicalOscillatorGateConnected
        or controlRouteState.adsrToLegacyOscillatorGateConnected
      )
    )
    local samplePositions = (type(getVoiceSamplePositions) == "function") and (getVoiceSamplePositions() or {}) or {}
    for i = 1, VOICE_COUNT do
      local voiceAmp = tonumber(readParam(string.format("/midi/synth/voice/%d/amp", i), 0.0)) or 0.0
      local voiceFreq = tonumber(readParam(string.format("/midi/synth/voice/%d/freq", i), 220.0)) or 220.0
      local samplePos = tonumber(samplePositions[i]) or 0.0
      if canonicalOscRouteConnected and voiceAmp > 0.001 then
        activeCount = activeCount + 1
        local item = activeVoices[activeCount] or {}
        item.voiceIndex = i
        item.freq = voiceFreq
        item.amp = voiceAmp
        item.samplePos = samplePos
        activeVoices[activeCount] = item
        if voiceAmp > dominantAmpForPos then
          dominantAmpForPos = voiceAmp
          dominantSamplePos = samplePos
        end
      end
    end
    for i = activeCount + 1, #activeVoices do
      activeVoices[i] = nil
    end
    oscCtx.activeVoices = activeVoices
    oscCtx.morphSamplePos = dominantSamplePos

    if uiInteracting then
      oscCtx.maxPoints = 72
    elseif activeCount >= 3 then
      oscCtx.maxPoints = 96
    elseif activeCount >= 2 then
      oscCtx.maxPoints = 120
    else
      oscCtx.maxPoints = 180
    end

    oscCtx.animTime = (oscCtx.animTime or 0) + dt

    local oscRepaintInterval = OSC_REPAINT_INTERVAL
    if uiInteracting then
      oscRepaintInterval = OSC_REPAINT_INTERVAL_WHILE_INTERACTING
    elseif activeCount >= 2 then
      oscRepaintInterval = OSC_REPAINT_INTERVAL_MULTI_VOICE
    end

    if ctx._oscModule and ctx._oscModule.repaint and now - (ctx._lastOscRepaintTime or 0) >= oscRepaintInterval then
      ctx._lastOscRepaintTime = now
      ctx._oscModule.repaint(oscCtx)
    end
  end

  syncModulatedWidget(liveWidget(".envelopeComponent.attack_knob"), PATHS.attack, attack, function(v)
    return (tonumber(v) or 0) * 1000.0
  end)
  syncModulatedWidget(liveWidget(".envelopeComponent.decay_knob"), PATHS.decay, decay, function(v)
    return (tonumber(v) or 0) * 1000.0
  end)
  syncModulatedWidget(liveWidget(".envelopeComponent.sustain_knob"), PATHS.sustain, sustain, function(v)
    return (tonumber(v) or 0) * 100.0
  end)
  syncModulatedWidget(liveWidget(".envelopeComponent.release_knob"), PATHS.release, release, function(v)
    return (tonumber(v) or 0) * 1000.0
  end)

  local envCtx = ctx._envCtx
  if envCtx then
    envCtx.values.attack = attack
    envCtx.values.decay = decay
    envCtx.values.sustain = sustain
    envCtx.values.release = release

    local voicePositions = envCtx.voicePositions or {}
    local vpCount = 0
    for i = 1, VOICE_COUNT do
      local voice = ctx._voices[i]
      if voice and voice.envelopeStage and voice.envelopeStage ~= "idle" then
        vpCount = vpCount + 1
        local item = voicePositions[vpCount] or {}
        item.stage = voice.envelopeStage
        item.level = voice.envelopeLevel or 0
        item.time = voice.envelopeTime or 0
        voicePositions[vpCount] = item
      end
    end
    for i = vpCount + 1, #voicePositions do
      voicePositions[i] = nil
    end
    envCtx.voicePositions = voicePositions

    local envRepaintInterval = uiInteracting and ENV_REPAINT_INTERVAL_WHILE_INTERACTING or ENV_REPAINT_INTERVAL
    if ctx._envModule and ctx._envModule.repaint and now - (ctx._lastEnvRepaintTime or 0) >= envRepaintInterval then
      ctx._lastEnvRepaintTime = now
      ctx._envModule.repaint(envCtx)
    end
  end

  syncText(widgets.adsrValue, string.format("ADSR: A %s / D %s / S %.0f%% / R %s",
    formatTime(attack), formatTime(decay), sustain * 100, formatTime(release)))

  local activeCount = activeVoiceCount(ctx)
  local midiStatusText = isPluginMode() and "host" or "waiting"
  local midiStatusColour = 0xfff59e0b
  if activeCount > 0 then
    midiStatusText = "active"
    midiStatusColour = 0xff4ade80
  elseif ctx._selectedMidiInputIdx and ctx._selectedMidiInputIdx > 1 then
    midiStatusText = "armed"
    midiStatusColour = 0xff38bdf8
  end

  if widgets.midiState then
    syncText(widgets.midiState, midiStatusText)
    syncColour(widgets.midiState, midiStatusColour)
  end

  syncText(widgets.voicesValue, "8 voice poly")
  syncText(widgets.currentNote, "Note: " .. (ctx._currentNote and noteName(ctx._currentNote) or "--"))
  syncText(widgets.voiceStatus, voiceSummary(ctx))
  syncText(widgets.midiEvent, ctx._lastEvent)
  syncText(widgets.freqValue, string.format("Freq: %.2f Hz", dominantFreq))
  syncText(widgets.ampValue, string.format("Amp: %.3f", maxAmp))
  local filterName = FILTER_OPTIONS[filterType + 1] or "SVF"
  syncText(widgets.filterValue, string.format("Filter: %s / %d Hz / Res %.2f", filterName, round(cutoff), resonance))
  syncText(widgets.adsrValue, string.format("ADSR: A %s / D %s / S %.0f%% / R %s",
    formatTime(attack), formatTime(decay), sustain * 100, formatTime(release)))
  local fx1Name = FxDefs.FX_OPTIONS[fx1Type + 1] or "None"
  local fx2Name = FxDefs.FX_OPTIONS[fx2Type + 1] or "None"
  syncText(widgets.fxValue, string.format("FX1: %s / FX2: %s / Dly %.0f%% / Verb %.0f%%",
    fx1Name, fx2Name, delayMix * 100, reverbWet * 100))
  syncText(widgets.deviceValue, "Input: " .. (ctx._selectedMidiInputLabel or "None"))

  for i = 1, 8 do
    local voiceLabel = widgets["voiceNote" .. i]
    if voiceLabel then
      local voice = ctx._voices[i]
      if voice and voice.active and voice.note and voice.envelopeStage ~= "idle" then
        syncText(voiceLabel, noteName(voice.note))
      else
        syncText(voiceLabel, "--")
      end
    end
  end

  if ctx._keyboardDirty then
    syncKeyboardDisplay(ctx)
    ctx._keyboardDirty = false
  end

  if syncMidiParamRack then
    syncMidiParamRack(ctx)
  end

  if ctx._pendingPatchbayPages and next(ctx._pendingPatchbayPages) ~= nil then
    for shellId, pageIndex in pairs(ctx._pendingPatchbayPages) do
      local instance = patchbayInstances[shellId]
      local specId = instance and instance.specId or nil
      local nodeId = instance and instance.nodeId or specId
      if specId then
        cleanupPatchbayFromRuntime(shellId, ctx)
        patchbayInstances[shellId] = nil
        ensurePatchbayWidgets(ctx, shellId, nodeId, specId, pageIndex)
      end
      ctx._pendingPatchbayPages[shellId] = nil
    end
    if RackWireLayer and RackWireLayer.refreshWires then
      RackWireLayer.refreshWires(ctx)
    end
  end

  local viewMode = ctx._rackState and ctx._rackState.viewMode or "perf"
  if viewMode == "patch" then
    syncPatchbayValues(ctx)
  end
end

return M

-- MidiSynth Integration Module for Main
-- Extracted from MidiSynth_uiproject/dsp/main.lua with routing support.
-- Builds an 8-voice polysynth with two serial FX slots, ADSR, filter, EQ.
-- Optionally connects output to a looper layer input for recording.

local M = {}

local FxDefs = require("fx_definitions")
local VoicePool = require("voice_pool")
local Utils = require("utils")
local FxSlot = require("fx_slot")
local SampleSynth = require("sample_synth")
local SampleCaptureSources = require("sample_capture_sources")
local ParameterBinder = require("parameter_binder")
local RackAudioRouter = require("rack_audio_router")
local RackEqModule = require("rack_modules.eq")
local RackFxModule = require("rack_modules.fx")
local RackFilterModule = require("rack_modules.filter")
local RackOscillatorModule = require("rack_modules.oscillator")
local RackSampleModule = require("rack_modules.sample")
local RackBlendSimpleModule = require("rack_modules.blend_simple")

local VOICE_COUNT = 8

local PATHS = ParameterBinder.PATHS

local function noteToFrequency(note)
  return 440.0 * (2.0 ^ ((tonumber(note) - 69.0) / 12.0))
end

local MAX_FX_PARAMS = ParameterBinder.MAX_FX_PARAMS
local LEGACY_OSC_MAX_LEVEL = 0.40
local DYNAMIC_OSC_OUTPUT_TRIM = 0.25
local DYNAMIC_OSC_DEFAULT_OUTPUT = 0.8
local OSC_MODE_CLASSIC = 0
local OSC_MODE_SAMPLE_LOOP = 1
local OSC_MODE_BLEND = 2
local OSC_RENDER_STANDARD = 0
local OSC_RENDER_ADD = 1
local ADD_FLAVOR_SELF = 0
local ADD_FLAVOR_DRIVEN = 1
local SAMPLE_PITCH_MODE_CLASSIC = 0
local SAMPLE_PITCH_MODE_PHASE_VOCODER = 1
local SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ = 2
local SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ = 2
local DYNAMIC_OSC_SOURCE_BASE = 100
local DYNAMIC_SAMPLE_SOURCE_BASE = 200
local DYNAMIC_BLEND_SIMPLE_SOURCE_BASE = 300
local DYNAMIC_SAMPLE_OUTPUT_TRIM = 0.25
local DYNAMIC_BLEND_SIMPLE_STAGE_BASE = 400
local AUX_AUDIO_SOURCE_CODES = ParameterBinder.AUX_AUDIO_SOURCE_CODES or {}

function M.buildSynth(ctx, options)
  options = options or {}
  local layerInputNodes = options.layerInputNodes or {}
  local layerSourceNodes = options.layerSourceNodes or {}

  local mix = ctx.primitives.MixerNode.new()

  local function applyFilterDefaults(node)
    node:setMode(0)
    node:setCutoff(3200)
    node:setResonance(0.75)
    node:setDrive(1.0)
    node:setMix(1.0)
  end

  local filt = ctx.primitives.SVFNode.new()
  applyFilterDefaults(filt)

  local dist = ctx.primitives.DistortionNode.new()
  local eq8 = ctx.primitives.EQ8Node.new()
  local spec = ctx.primitives.SpectrumAnalyzerNode.new()
  local out = ctx.primitives.GainNode.new(2)

  local function connectMixerInput(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    -- inputIndex is 1-based bus number; target input = (bus-1) * 2 for stereo buses
    ctx.graph.connect(source, mixer, 0, (inputIndex - 1) * 2)
  end

  local fxDefs = FxDefs.buildFxDefs(ctx.primitives, ctx.graph)

  -- Create FX context with helper for fx_slot module
  local fxCtx = {
    primitives = ctx.primitives,
    graph = ctx.graph,
    connectMixerInput = connectMixerInput,
  }

  local fx1Slot = FxSlot.create(fxCtx, fxDefs, {defaultMix = 0.0, maxFxParams = MAX_FX_PARAMS})
  local fx2Slot = FxSlot.create(fxCtx, fxDefs, {defaultMix = 0.0, maxFxParams = MAX_FX_PARAMS})
  local dynamicFxSlots = {}
  -- Lazy-loaded rack FX module slots.

  local dynamicFilterSlots = {}
  -- Lazy-loaded rack filter module slots.

  local dynamicOscillatorSlots = {}
  -- Lazy-loaded rack oscillator module slots.

  local dynamicSampleSlots = {}
  -- Lazy-loaded rack sample module slots.

  local dynamicBlendSimpleSlots = {}
  -- Lazy-loaded rack blend-simple module slots.

  -- Noise generator
  local noiseGen = ctx.primitives.NoiseGeneratorNode.new()
  noiseGen:setLevel(1.0)
  noiseGen:setColor(0.1)
  local currentNoiseLevel = 0.0

  -- Sample synth mode state
  -- DSP is always on the canonical blend path; UI tabs are view-only.
  local sampleMode = OSC_MODE_BLEND
  local renderMode = OSC_RENDER_STANDARD
  local additivePartials = 8
  local additiveTilt = 0.0
  local additiveDrift = 0.0
  -- SampleSynth will manage capture state
  local samplePitchMapEnabled = false
  local samplePitchMode = SAMPLE_PITCH_MODE_CLASSIC
  local samplePvocFFTOrder = 11
  local samplePvocTimeStretch = 1.0
  local sampleRootNote = 60.0
  local samplePlayStart = 0.0    -- Yellow flag: where playback starts
  local sampleLoopStart = 0.0    -- Green flag: where playback jumps to after loopEnd
  local sampleLoopLen = 1.0      -- Determines red flag (loop end)
  local sampleCrossfade = 0.1    -- Boundary crossfade window (normalized of clipped domain)
  local sampleRetrigger = true

  -- Blend mode state
  local blendMode = 0           -- 0=Mix, 1=Ring, 2=FM, 3=Sync, 4=Add, 5=Morph
  local blendAmount = 0.5       -- Mix: crossfade. Other modes: bipolar direction/amount.
  local waveToSample = 0.5      -- Legacy hidden param (deprecated)
  local sampleToWave = 0.0      -- Legacy hidden param (deprecated)
  local blendKeyTrack = 2       -- 0=wave (no sample keytrack), 1=sample, 2=both
  local blendSamplePitch = 0.0  -- Sample transpose in semitones
  local blendModAmount = 0.5    -- Modulation depth budget
  local addFlavor = ADD_FLAVOR_SELF
  local unisonVoices = 1
  local detuneCents = 0.0
  local stereoSpread = 0.0
  local xorBehavior = 0         -- Legacy hidden param (deprecated)

  -- Morph mode parameters
  local morphCurve = 2          -- 0=linear, 1=S-curve, 2=equal-power (default)
  local morphConvergence = 0.0  -- Repurposed: harmonic stretch (0=normal, 1=stretched/metallic)
  local morphPhaseParam = 0     -- Repurposed: spectral tilt (0=neutral, 1=bright, 2=dark)
  local morphSpeed = 1.0        -- Temporal scan speed multiplier
  local morphContrast = 0.5     -- Spectral contrast boost
  local morphSmooth = 0.0       -- Temporal frame smoothing
  local envFollowAmount = 1.0   -- How much sample phrase contour shapes additive output (0=flat, 1=full)

  -- Morph mode cache to avoid rebuilding partials every frame
  local cachedMorphWavePartials = nil
  local cachedMorphWaveKey = nil -- string: waveform_freq_partialCount_tilt_drift

  local cachedSamplePeaks = {}
  local cachedSamplePeakBuckets = 0
  local latestSampleAnalysis = nil
  local latestSamplePartials = nil
  local latestTemporalPartials = nil  -- TemporalTemporalData: { frameCount, frames[], frameTimes[], ... }
  local temporalExtractPending = false
  local sampleAdditiveEnabled = false
  local sampleAdditiveMix = 0.25
  local sampleAnalysisPending = false   -- analysis requested but not yet queued
  local sampleAnalysisInFlight = false  -- async worker is running
  local extractCapturedSamplePartials

  -- Forward declarations for helpers defined later in the function body
  local ensureSampleAnalysis = nil
  local pollAsyncSampleAnalysis = nil
  local applyAllSampleDerivedAdditiveStates = nil
  local applySpectralVoiceParams = nil
  local applyAllSpectralVoiceParams = nil
  local sampleDerivedAdditiveRefreshPending = true

  local function requestSampleDerivedAdditiveRefresh()
    sampleDerivedAdditiveRefreshPending = true
  end

  -- Live source for input-dsp capture path (mode 0 = MonitorControlled).
  local liveSampleInput = ctx.primitives.PassthroughNode.new(2, 0)
  if ctx.graph and ctx.graph.markInput then
    ctx.graph.markInput(liveSampleInput)
  end
  local captureSourceConfig = SampleCaptureSources.buildConfig({
    liveInput = liveSampleInput,
    layerSourceNodes = layerSourceNodes,
  })

  mix:setInputCount(VOICE_COUNT)

  -- Create VoicePool for voice management
  local voicePool = VoicePool.new(ctx, {
    count = VOICE_COUNT,
    basePath = "/midi/synth"
  })

  -- Create SampleSynth
  local sampleSynth = SampleSynth.create(ctx, {
    sourceSpecs = captureSourceConfig.sourceSpecs,
    defaultSourceId = captureSourceConfig.defaultSourceId,
  })

  -- Create voices and populate voicePool
  for i = 1, VOICE_COUNT do
    voicePool.voices[i] = sampleSynth.createVoiceGraph(i, {
      mixBus = mix,
      noiseSource = noiseGen,
      oscRenderStandard = OSC_RENDER_STANDARD,
      oscRenderAdd = OSC_RENDER_ADD,
      addFlavorSelf = ADD_FLAVOR_SELF,
    })
  end

  -- Signal chain defaults
  -- Keep the downstream distortion node around for the future dedicated drive
  -- stage, but it is no longer part of the synth voice path.
  dist:setDrive(1.8); dist:setMix(0.14); dist:setOutput(0.9)

  local function applyEqDefaults(node)
    node:setMix(1.0); node:setOutput(0.0)
    node:setBandType(1, ctx.primitives.EQ8Node.BandType.LowShelf)
    node:setBandFreq(1, 60.0); node:setBandGain(1, 0.0); node:setBandQ(1, 0.8)
    node:setBandType(2, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(2, 120.0); node:setBandGain(2, 0.0); node:setBandQ(2, 1.0)
    node:setBandType(3, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(3, 250.0); node:setBandGain(3, 0.0); node:setBandQ(3, 1.0)
    node:setBandType(4, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(4, 500.0); node:setBandGain(4, 0.0); node:setBandQ(4, 1.0)
    node:setBandType(5, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(5, 1000.0); node:setBandGain(5, 0.0); node:setBandQ(5, 1.0)
    node:setBandType(6, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(6, 2500.0); node:setBandGain(6, 0.0); node:setBandQ(6, 1.0)
    node:setBandType(7, ctx.primitives.EQ8Node.BandType.Peak)
    node:setBandFreq(7, 6000.0); node:setBandGain(7, 0.0); node:setBandQ(7, 1.0)
    node:setBandType(8, ctx.primitives.EQ8Node.BandType.HighShelf)
    node:setBandFreq(8, 12000.0); node:setBandGain(8, 0.0); node:setBandQ(8, 0.8)
  end

  applyEqDefaults(eq8)
  local dynamicEqSlots = {}
  -- Lazy-loaded rack EQ module slots.

  spec:setSensitivity(1.2); spec:setSmoothing(0.86); spec:setFloor(-72)
  out:setGain(0.8)

  -- Apply initial phase vocoder settings to all voices
  sampleSynth.applyInitialPhaseVocoderSettings(voicePool.voices, {
    samplePitchMode = samplePitchMode,
    samplePitchModePhaseVocoderHQ = SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ,
    fftOrder = samplePvocFFTOrder,
    timeStretch = samplePvocTimeStretch,
  })

  local rackAudioRouter = RackAudioRouter.create(ctx, {
    oscillator = mix,
    sources = { mix },
    filter = filt,
    fx1 = fx1Slot,
    fx2 = fx2Slot,
    eq = eq8,
    dynamicEqSlots = dynamicEqSlots,
    dynamicFxSlots = dynamicFxSlots,
    dynamicFilterSlots = dynamicFilterSlots,
    dynamicBlendSimpleSlots = dynamicBlendSimpleSlots,
    output = spec,
  })

  local rackStageState = {
    count = 4,
    connectOutput = true,
    stages = { RackAudioRouter.STAGE_FILTER, RackAudioRouter.STAGE_FX1, RackAudioRouter.STAGE_FX2, RackAudioRouter.STAGE_EQ },
  }

  local rackSourceState = {
    count = 1,
    sources = { 1 },
    applied = {},
  }

  local function sourceDescriptorForCode(code)
    local sourceCode = math.max(0, math.floor(tonumber(code) or 0))
    if sourceCode == 1 then
      return {
        key = "mono_oscillator",
        node = mix,
        inputIndex = 1,
      }
    elseif sourceCode >= DYNAMIC_SAMPLE_SOURCE_BASE then
      local slotIndex = sourceCode - DYNAMIC_SAMPLE_SOURCE_BASE
      local slot = dynamicSampleSlots[slotIndex]
      local node = slot and slot.output or nil
      if node then
        return {
          key = "dyn_sample_" .. tostring(slotIndex),
          node = node,
          inputIndex = VOICE_COUNT + slotIndex + 1,
        }
      end
    elseif sourceCode >= DYNAMIC_BLEND_SIMPLE_SOURCE_BASE then
      local slotIndex = sourceCode - DYNAMIC_BLEND_SIMPLE_SOURCE_BASE
      local slot = dynamicBlendSimpleSlots[slotIndex]
      local node = slot and slot.output or nil
      if node then
        return {
          key = "dyn_blend_simple_" .. tostring(slotIndex),
          node = node,
          inputIndex = VOICE_COUNT + 33 + slotIndex,
        }
      end
    elseif sourceCode >= DYNAMIC_OSC_SOURCE_BASE then
      local slotIndex = sourceCode - DYNAMIC_OSC_SOURCE_BASE
      local slot = dynamicOscillatorSlots[slotIndex]
      local node = slot and slot.output or nil
      if node then
        return {
          key = "dyn_osc_" .. tostring(slotIndex),
          node = node,
          inputIndex = slotIndex + 1,
        }
      end
    end
    return nil
  end

  local function applyRackSourceSequence()
    local desired = {}
    local count = math.max(0, math.floor(tonumber(rackSourceState.count) or 0))

    for i = 1, count do
      local descriptor = sourceDescriptorForCode(rackSourceState.sources[i])
      if descriptor and descriptor.node then
        desired[#desired + 1] = descriptor
      end
    end

    local resolvedSources = {}
    for i = 1, #desired do
      resolvedSources[#resolvedSources + 1] = desired[i].node
    end
    if #resolvedSources == 0 then
      resolvedSources[1] = mix
    end

    rackAudioRouter.sources = resolvedSources
    rackSourceState.applied = desired
    return desired
  end

  local function currentRackStageSequence()
    local out = {}
    local count = math.max(0, math.floor(tonumber(rackStageState.count) or 0))
    for i = 1, count do
      out[#out + 1] = math.max(0, math.floor(tonumber(rackStageState.stages[i]) or 0))
    end
    return out
  end

  local function applyRackStageSequence()
    return rackAudioRouter.applyStageSequence(currentRackStageSequence(), rackStageState.connectOutput == true)
  end

  -- Signal chain is now driven by the rack stage sequence, with the old edge
  -- mask retained as the explicit "apply now" trigger for UI compatibility.
  applyRackSourceSequence()
  applyRackStageSequence()
  ctx.graph.connect(spec, out)
  ctx.graph.markOutput(out)

  -- Route synth output to every looper layer input for recording.
  -- This mirrors the microphone path so all layers see the same live capture feed.
  local synthSend = nil

  if #layerInputNodes > 0 then
    synthSend = ctx.primitives.GainNode.new(2)
    synthSend:setGain(1.0)
    ctx.graph.connect(spec, synthSend)
    for i = 1, #layerInputNodes do
      local layerInput = layerInputNodes[i]
      if layerInput then
        ctx.graph.connect(synthSend, layerInput)
      end
    end
  end

  -- Parameter registration
  local paramRegistration = ParameterBinder.registerAll(ctx, {
    voicePool = voicePool,
    targets = {
      filt = filt,
      eq8 = eq8,
      out = out,
      noiseGen = noiseGen,
    },
    fxOptionCount = #FxDefs.FX_OPTIONS,
    maxFxParams = MAX_FX_PARAMS,
    oscRenderStandard = OSC_RENDER_STANDARD,
    oscModeClassic = OSC_MODE_CLASSIC,
    sampleSourceLive = captureSourceConfig.paramMin,
    sampleSourceLayerMax = captureSourceConfig.paramMax,
    samplePitchModeClassic = SAMPLE_PITCH_MODE_CLASSIC,
    samplePitchModeMax = SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ,
  })
  local params = paramRegistration.params
  local adsr = paramRegistration.adsr
  local dynamicRegisteredParamPaths = {}
  for i = 1, #(params or {}) do
    local path = tostring(params[i] or "")
    if path ~= "" then
      dynamicRegisteredParamPaths[path] = true
    end
  end
  local dynamicRegisteredSlots = {}

  local function registerDynamicSchemaEntries(schema)
    local entries = schema
    if type(schema) == "table" and type(schema.path) == "string" then
      entries = { schema }
    end
    for i = 1, #(entries or {}) do
      local entry = entries[i]
      local path = tostring(entry and entry.path or "")
      if path ~= "" and dynamicRegisteredParamPaths[path] ~= true then
        ctx.params.register(path, entry.spec)
        dynamicRegisteredParamPaths[path] = true
        params[#params + 1] = path
      end
    end
  end

  local rackEqModule = RackEqModule.create({
    ctx = ctx,
    slots = dynamicEqSlots,
    applyDefaults = applyEqDefaults,
    ParameterBinder = ParameterBinder,
  })

  local rackFxModule = RackFxModule.create({
    slots = dynamicFxSlots,
    FxSlot = FxSlot,
    ParameterBinder = ParameterBinder,
    fxCtx = fxCtx,
    fxDefs = fxDefs,
    maxFxParams = MAX_FX_PARAMS,
  })

  local rackFilterModule = RackFilterModule.create({
    ctx = ctx,
    slots = dynamicFilterSlots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    applyDefaults = applyFilterDefaults,
  })

  local rackOscillatorModule = RackOscillatorModule.create({
    ctx = ctx,
    slots = dynamicOscillatorSlots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    noteToFrequency = noteToFrequency,
    connectMixerInput = connectMixerInput,
    voiceCount = VOICE_COUNT,
    outputTrim = DYNAMIC_OSC_OUTPUT_TRIM,
    defaultOutput = DYNAMIC_OSC_DEFAULT_OUTPUT,
    maxLevel = LEGACY_OSC_MAX_LEVEL,
    oscRenderStandard = OSC_RENDER_STANDARD,
  })

  local function buildDynamicSampleSourceSpecs(slotInput)
    local sourceSpecs = {}
    if slotInput then
      sourceSpecs[#sourceSpecs + 1] = {
        id = 0,
        name = "input",
        node = slotInput,
        kind = "input",
      }
    end

    local sharedSpecs = type(captureSourceConfig and captureSourceConfig.sourceSpecs) == "table" and captureSourceConfig.sourceSpecs or {}
    for i = 1, #sharedSpecs do
      local spec = sharedSpecs[i]
      if type(spec) == "table" and spec.node then
        local cloned = {}
        for key, value in pairs(spec) do
          cloned[key] = value
        end
        cloned.id = math.max(1, math.floor(tonumber(spec.id) or 0) + 1)
        sourceSpecs[#sourceSpecs + 1] = cloned
      end
    end

    table.sort(sourceSpecs, function(a, b)
      return (tonumber(a and a.id) or 0) < (tonumber(b and b.id) or 0)
    end)
    return sourceSpecs
  end

  local rackSampleModule = RackSampleModule.create({
    ctx = ctx,
    slots = dynamicSampleSlots,
    Utils = Utils,
    SampleSynth = SampleSynth,
    ParameterBinder = ParameterBinder,
    noteToFrequency = noteToFrequency,
    connectMixerInput = connectMixerInput,
    voiceCount = VOICE_COUNT,
    outputTrim = DYNAMIC_SAMPLE_OUTPUT_TRIM,
    samplePitchModeClassic = SAMPLE_PITCH_MODE_CLASSIC,
    samplePitchModePhaseVocoder = SAMPLE_PITCH_MODE_PHASE_VOCODER,
    samplePitchModePhaseVocoderHQ = SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ,
    buildSourceSpecs = buildDynamicSampleSourceSpecs,
  })

  local rackBlendSimpleModule = RackBlendSimpleModule.create({
    ctx = ctx,
    slots = dynamicBlendSimpleSlots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    connectMixerInput = connectMixerInput,
  })

  local function ensureDynamicModuleSlot(specId, slotIndex)
    local id = tostring(specId or "")
    local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
    dynamicRegisteredSlots[id] = dynamicRegisteredSlots[id] or {}

    if dynamicRegisteredSlots[id][index] == true then
      return true
    end

    if id == "eq" then
      rackEqModule.createSlot(index)
    elseif id == "fx" then
      rackFxModule.createSlot(index)
    elseif id == "filter" then
      rackFilterModule.createSlot(index)
    elseif id == "rack_oscillator" then
      rackOscillatorModule.createSlot(index)
    elseif id == "rack_sample" then
      rackSampleModule.createSlot(index)
    elseif id == "blend_simple" then
      rackBlendSimpleModule.createSlot(index)
    end

    registerDynamicSchemaEntries(ParameterBinder.buildDynamicSlotSchema(id, index, {
      voiceCount = VOICE_COUNT,
      fxOptionCount = #FxDefs.FX_OPTIONS,
      maxFxParams = MAX_FX_PARAMS,
      oscRenderStandard = OSC_RENDER_STANDARD,
    }))

    dynamicRegisteredSlots[id][index] = true
    return true
  end

  local function ensureDynamicModulePath(path)
    local specId, slotIndex = ParameterBinder.matchDynamicModulePath(path)
    if specId == nil or slotIndex == nil then
      return false
    end
    return ensureDynamicModuleSlot(specId, slotIndex)
  end

  local function ensureRackAudioStagePath(index)
    registerDynamicSchemaEntries(ParameterBinder.buildRackAudioStageSchema(index))
    return true
  end

  local function ensureRackAudioSourcePath(index)
    registerDynamicSchemaEntries(ParameterBinder.buildRackAudioSourceSchema(index))
    return true
  end

  local registryRequestState = {
    kind = 0,
    index = 0,
  }

  _G.__midiSynthEnsureDynamicModuleSlot = ensureDynamicModuleSlot
  _G.__midiSynthEnsureDynamicPath = ensureDynamicModulePath
  _G.__midiSynthGetDynamicSampleSlotPeaks = function(slotIndex, numBuckets)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    if not slot then
      return {}
    end
    local bucketCount = math.max(32, math.floor(tonumber(numBuckets) or 128))
    if type(slot.cachedSamplePeaks) == "table" and #slot.cachedSamplePeaks > 0 then
      return sampleSynth.resamplePeaks(slot.cachedSamplePeaks, bucketCount)
    end
    local voice = slot.voices and slot.voices[1] or nil
    local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
    if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
      local ok, peaks = pcall(function()
        return getSampleRegionPlaybackPeaks(playbackNode, bucketCount)
      end)
      if ok and type(peaks) == "table" and #peaks > 0 then
        slot.cachedSamplePeaks = peaks
        slot.cachedSamplePeakBuckets = #peaks
        return sampleSynth.resamplePeaks(peaks, bucketCount)
      end
    end
    return {}
  end
  _G.__midiSynthGetDynamicSampleSlotAnalysis = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    return (slot and type(slot.latestAnalysis) == "table") and slot.latestAnalysis or {}
  end
  _G.__midiSynthGetDynamicOscillatorSlotAnalysis = function(slotIndex)
    local registry = type(_G) == "table" and _G.__midiSynthDynamicOscillatorAnalysis or nil
    local entry = type(registry) == "table" and registry[math.max(1, math.floor(tonumber(slotIndex) or 1))] or nil
    return type(entry) == "table" and entry or {}
  end
  _G.__midiSynthGetDynamicSampleSlotPartials = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    return (slot and type(slot.latestPartials) == "table") and slot.latestPartials or {}
  end
  _G.__midiSynthGetDynamicSampleSlotTemporal = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    return (slot and type(slot.latestTemporal) == "table") and slot.latestTemporal or {}
  end
  _G.__midiSynthGetDynamicSampleSlotVoicePositions = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    local out = {}
    local voices = slot and slot.voices or {}
    for i = 1, #voices do
      local voice = voices[i]
      out[i] = (voice and voice.samplePlayback and voice.samplePlayback.getNormalizedPosition and voice.samplePlayback:getNormalizedPosition()) or 0.0
    end
    return out
  end
  _G.__midiSynthGetDynamicSampleSlotWriteOffset = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    if not (slot and slot.sampleSynth and slot.sampleSynth.getSelectedSourceWriteOffset) then
      return 0
    end
    return slot.sampleSynth.getSelectedSourceWriteOffset()
  end
  _G.__midiSynthGetDynamicSampleSlotSelectedSourceName = function(slotIndex)
    local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
    if not (slot and slot.sampleSynth and slot.sampleSynth.getSelectedSourceEntry) then
      return ""
    end
    local entry = slot.sampleSynth.getSelectedSourceEntry()
    return tostring(entry and entry.name or "")
  end
  _G.__midiSynthGetAuxAudioConnectionCount = function()
    return #(auxAudioConnectionsApplied or {})
  end

  local function hostSamplesPerBar()
    if ctx.host and ctx.host.getParam then
      local spb = tonumber(ctx.host.getParam("/core/behavior/samplesPerBar")) or 0
      if spb > 0 then
        return spb
      end
    end

    local sr = (ctx.host and ctx.host.getSampleRate and tonumber(ctx.host.getSampleRate())) or 44100.0
    local tempo = (ctx.host and ctx.host.getParam and tonumber(ctx.host.getParam("/core/behavior/tempo"))) or 120.0
    if sr <= 0 then sr = 44100.0 end
    if tempo <= 0 then tempo = 120.0 end
    return (sr * 240.0) / tempo
  end

  -- Source selection now handled by SampleSynth module
  local function selectedSampleSourceEntry()
    return sampleSynth.getSelectedSourceEntry()
  end

  local function selectedSampleSourceCapture()
    return sampleSynth.getSelectedSourceCapture()
  end

  -- Expose write offset for UI (free mode capture)
  local function getSelectedSourceWriteOffset()
    return sampleSynth.getSelectedSourceWriteOffset()
  end

  local function reverseTable(tbl)
    local out = {}
    for i = #tbl, 1, -1 do
      out[#out + 1] = tbl[i]
    end
    return out
  end

  local function resamplePeaks(peaks, numBuckets)
    if type(peaks) ~= "table" or #peaks == 0 or numBuckets <= 0 then
      return {}
    end
    if #peaks == numBuckets then
      return peaks
    end
    local out = {}
    local srcCount = #peaks
    for i = 1, numBuckets do
      local t = (i - 1) / math.max(1, numBuckets - 1)
      local srcIndex = math.floor(t * math.max(0, srcCount - 1)) + 1
      out[i] = peaks[srcIndex] or 0.0
    end
    return out
  end

  local function hasUsableSampleAdditivePartials(partials)
    return type(partials) == "table"
      and (tonumber(partials.activeCount) or 0) > 0
      and (tonumber(partials.fundamental) or 0.0) > 0.0
  end

  local function buildDrivenWaveWeight(waveform, harmonicNumber, width)
    local wf = Utils.roundIndex(waveform, 7)
    local h = math.max(1, math.floor(tonumber(harmonicNumber) or 1))
    local pulse = Utils.clamp(width or 0.5, 0.01, 0.99)

    if wf == 0 then
      return (h == 1) and 1.0 or 0.0
    elseif wf == 1 then
      return 1.0 / h
    elseif wf == 2 then
      return (h % 2 == 1) and (1.0 / h) or 0.0
    elseif wf == 3 then
      return (h % 2 == 1) and (1.0 / (h * h)) or 0.0
    elseif wf == 4 then
      return ((h == 1) and 0.45 or 0.0) + (0.55 / h)
    elseif wf == 5 then
      return 1.0 / math.sqrt(h)
    elseif wf == 6 then
      return math.abs(math.sin(math.pi * h * pulse)) / h
    elseif wf == 7 then
      return (1.0 / h) * (1.0 + 0.22 * math.cos(h * 0.73) + 0.15 * math.sin(h * 1.11))
    end

    return 1.0 / h
  end

  local function buildDrivenSampleAdditivePartials(sourcePartials, voice)
    if not hasUsableSampleAdditivePartials(sourcePartials) then
      return sourcePartials
    end

    local width = (voice and voice.pulseWidth) or pulseWidth or 0.5
    local waveform = (voice and voice.waveform) or 1
    local out = {
      activeCount = 0,
      fundamental = tonumber(sourcePartials.fundamental) or 0.0,
      inharmonicity = tonumber(sourcePartials.inharmonicity) or 0.0,
      brightness = tonumber(sourcePartials.brightness) or 0.0,
      rmsLevel = tonumber(sourcePartials.rmsLevel) or 0.0,
      peakLevel = tonumber(sourcePartials.peakLevel) or 0.0,
      attackTimeMs = tonumber(sourcePartials.attackTimeMs) or 0.0,
      spectralCentroidHz = tonumber(sourcePartials.spectralCentroidHz) or 0.0,
      analysisStartSample = tonumber(sourcePartials.analysisStartSample) or 0,
      analysisEndSample = tonumber(sourcePartials.analysisEndSample) or 0,
      numSamples = tonumber(sourcePartials.numSamples) or 0,
      numChannels = tonumber(sourcePartials.numChannels) or 1,
      sampleRate = tonumber(sourcePartials.sampleRate) or 44100.0,
      isPercussive = sourcePartials.isPercussive,
      reliable = sourcePartials.reliable,
      algorithm = "wave-driven-additive",
      partials = {}
    }

    local maxAmp = 0.0
    local sourceEntries = sourcePartials.partials or {}
    for i = 1, math.min(8, tonumber(sourcePartials.activeCount) or 0) do
      local src = sourceEntries[i]
      if type(src) == "table" then
        local srcAmp = math.max(0.0, tonumber(src.amplitude) or 0.0)
        local weight = math.max(0.0, buildDrivenWaveWeight(waveform, i, width))
        local amp = srcAmp * weight
        out.partials[#out.partials + 1] = {
          frequency = tonumber(src.frequency) or 0.0,
          amplitude = amp,
          phase = tonumber(src.phase) or 0.0,
          decayRate = tonumber(src.decayRate) or 0.0,
        }
        maxAmp = math.max(maxAmp, amp)
      end
    end

    if maxAmp <= 1.0e-6 then
      out.partials = {}
      out.activeCount = 0
      out.fundamental = 0.0
      return out
    end

    local kept = {}
    for i = 1, #out.partials do
      local part = out.partials[i]
      if part.amplitude > (maxAmp * 0.02) then
        kept[#kept + 1] = {
          frequency = part.frequency,
          amplitude = part.amplitude / maxAmp,
          phase = part.phase,
          decayRate = part.decayRate,
        }
      end
    end
    out.partials = kept
    out.activeCount = #kept
    if out.activeCount <= 0 then
      out.fundamental = 0.0
    end
    return out
  end

  --- Normalize partials to ratio space (fundamental = 1.0).
  --- Returns nil if input is unusable.
  local function normalizePartials(partials)
    if type(partials) ~= "table" then return nil end
    local count = tonumber(partials.activeCount) or 0
    if count <= 0 then return nil end
    local fund = tonumber(partials.fundamental) or 0.0
    if fund <= 1.0e-6 then
      local p1 = partials.partials and partials.partials[1]
      fund = p1 and (tonumber(p1.frequency) or 0.0) or 0.0
    end
    if fund <= 1.0e-6 then return nil end

    local out = { activeCount = count, fundamental = fund, partials = {} }
    for i = 1, count do
      local p = partials.partials and partials.partials[i]
      if p then
        out.partials[i] = {
          ratio = math.max(0.01, (tonumber(p.frequency) or 0.0) / fund),
          amplitude = tonumber(p.amplitude) or 0.0,
          phase = tonumber(p.phase) or 0.0,
          decayRate = tonumber(p.decayRate) or 0.0,
        }
      else
        out.partials[i] = { ratio = 0.0, amplitude = 0.0, phase = 0.0, decayRate = 0.0 }
      end
    end
    return out
  end

  --- Core spectral morph between two normalized partial sets.
  --- position: 0 = source A (wave), 1 = source B (sample)
  --- curve: 0=linear, 1=S-curve, 2=equal-power
  --- depth: 0=only amplitudes morph (freqs snap to dominant), 1=full freq+amp morph
  --- Returns a PartialData-compatible table with absolute frequencies.
  local function morphPartials(partialsA, partialsB, position, curve, depth)
    local a = normalizePartials(partialsA)
    local b = normalizePartials(partialsB)
    if not a and not b then return nil end
    if not a then return partialsB end
    if not b then return partialsA end

    local pos = Utils.clamp01(position or 0.0)
    local dep = Utils.clamp01(depth or 1.0)
    local aCount = a.activeCount or 0
    local bCount = b.activeCount or 0
    local maxCount = math.max(aCount, bCount)
    if maxCount <= 0 then return nil end

    -- Amplitude crossfade coefficients (affected by curve)
    local aCoeff, bCoeff
    local curveType = curve or 2
    if curveType == 0 then
      -- Linear
      aCoeff = 1.0 - pos
      bCoeff = pos
    elseif curveType == 1 then
      -- S-curve (smooth cosine interpolation)
      local t = 0.5 - 0.5 * math.cos(pos * math.pi)
      aCoeff = 1.0 - t
      bCoeff = t
    else
      -- Equal-power (default)
      aCoeff = math.cos(pos * math.pi * 0.5)
      bCoeff = math.sin(pos * math.pi * 0.5)
    end

    -- Frequency morph amount: depth scales how much frequencies slide
    -- At depth=0: freqs stay with the dominant source (snap crossfade)
    -- At depth=1: full log-frequency interpolation
    local freqMorphT = pos * dep

    local out = {
      activeCount = maxCount,
      fundamental = 1.0,
      partials = {},
    }

    for i = 1, maxCount do
      local ap = (i <= aCount) and a.partials[i] or nil
      local bp = (i <= bCount) and b.partials[i] or nil
      local aRatio = ap and (tonumber(ap.ratio) or 0.0) or 0.0
      local aAmp   = ap and (tonumber(ap.amplitude) or 0.0) or 0.0
      local aPhase  = ap and (tonumber(ap.phase) or 0.0) or 0.0
      local aDecay  = ap and (tonumber(ap.decayRate) or 0.0) or 0.0
      local bRatio = bp and (tonumber(bp.ratio) or 0.0) or 0.0
      local bAmp   = bp and (tonumber(bp.amplitude) or 0.0) or 0.0
      local bPhase  = bp and (tonumber(bp.phase) or 0.0) or 0.0
      local bDecay  = bp and (tonumber(bp.decayRate) or 0.0) or 0.0

      -- Frequency: log-space interpolation (musical pitch morph)
      local morphRatio
      if aRatio <= 0.01 and bRatio <= 0.01 then
        morphRatio = 0.0
      elseif aRatio <= 0.01 then
        morphRatio = bRatio
      elseif bRatio <= 0.01 then
        morphRatio = aRatio
      else
        -- Log-lerp: exp( (1-t)*log(a) + t*log(b) )
        local logA = math.log(aRatio)
        local logB = math.log(bRatio)
        morphRatio = math.exp(logA + (logB - logA) * freqMorphT)
      end

      -- Amplitude: crossfade with curve
      local morphAmp = aAmp * aCoeff + bAmp * bCoeff

      -- Phase: crossfade linearly
      local morphPhase = aPhase + (bPhase - aPhase) * pos

      -- Decay: crossfade
      local morphDecay = aDecay + (bDecay - aDecay) * pos

      out.partials[i] = {
        frequency = morphRatio,  -- ratio space (fundamental = 1.0)
        amplitude = morphAmp,
        phase = morphPhase,
        decayRate = morphDecay,
      }
    end

    return out
  end

  local function applySampleDerivedPartialsToVoices(partials)
    local usable = hasUsableSampleAdditivePartials(partials)
    for i = 1, VOICE_COUNT do
      local voice = voicePool.voices[i]
      if voice and voice.sampleAdditive then
        if usable then
          local voicePartials = (addFlavor == ADD_FLAVOR_DRIVEN)
            and buildDrivenSampleAdditivePartials(partials, voice)
            or partials
          voice.sampleAdditive:setPartials(voicePartials)
        else
          voice.sampleAdditive:clearPartials()
        end
      end
    end
    return usable
  end

  local function refreshSampleDerivedPartialsFromPlayback(reason)
    -- Ensure analysis has run if capture just happened
    ensureSampleAnalysis()
    local partials = extractCapturedSamplePartials(false, true)
    local usable = applySampleDerivedPartialsToVoices(partials)
    return usable
  end

  -- Temporal (multi-frame) partial extraction for evolving morph.
  -- This is heavier than single-frame, so we only call it when Morph mode is active
  -- and the sample has changed.
  local function extractTemporalPartials(reason)
    local voice = voicePool.voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastTemporalPartials then
      latestTemporalPartials = nil
      return nil
    end

    local ok, temporal = pcall(function()
      return playback:getLastTemporalPartials()
    end)
    if not ok or type(temporal) ~= "table" then
      return latestTemporalPartials
    end

    local fc = tonumber(temporal.frameCount) or 0
    if fc > 0 then
      latestTemporalPartials = temporal
      for i = 1, VOICE_COUNT do
        voicePool.voices[i].morphTemporalPos = 0.0
      end
      return temporal
    end

    ensureSampleAnalysis()
    return latestTemporalPartials
  end

  local function mapTemporalPositionForVoice(voice, samplePos)
    local pos = math.max(0.0, math.min(1.0, tonumber(samplePos) or 0.0))
    local speed = Utils.clamp(tonumber(morphSpeed) or 1.0, 0.0, 4.0)

    local outPos
    if speed <= 0.001 then
      outPos = (voice and voice.morphTemporalPos) or 0.0
    else
      -- Make Speed obvious and deterministic: scale the actual sample position.
      -- This matches the UI preview and avoids the previous barely-audible delta drift.
      outPos = (pos * speed) % 1.0
      if outPos < 0.0 then outPos = outPos + 1.0 end
    end

    if voice then
      voice.lastTemporalSamplePos = pos
      voice.morphTemporalPos = outPos
    end
    return outPos
  end

  -- Get the interpolated partial frame at a normalized position (0..1) in temporal data.
  -- Uses morphSmooth to go from stepped frames -> smooth interpolation,
  -- and morphContrast to exaggerate spectral differences.
  local function getTemporalFrameAtPosition(temporal, pos)
    if not temporal or not temporal.frames or not temporal.frameTimes then return nil end
    local fc = tonumber(temporal.frameCount) or 0
    if fc <= 0 then return nil end
    if fc == 1 then return temporal.frames[1] end

    local t = math.max(0.0, math.min(1.0, pos))
    local smoothAmt = Utils.clamp01(tonumber(morphSmooth) or 0.0)
    local contrastAmt = Utils.clamp(tonumber(morphContrast) or 0.5, 0.0, 2.0)

    -- Find bracketing frames
    local lo, hi = 1, fc
    for i = 1, fc - 1 do
      local ft = tonumber(temporal.frameTimes[i + 1]) or 1.0
      if ft > t then
        lo = i
        hi = i + 1
        break
      end
      lo = i
      hi = i
    end

    if lo == hi then return temporal.frames[lo] end

    local loTime = tonumber(temporal.frameTimes[lo]) or 0.0
    local hiTime = tonumber(temporal.frameTimes[hi]) or 1.0
    local span = hiTime - loTime
    local rawFrac = (span > 1e-6) and math.max(0.0, math.min(1.0, (t - loTime) / span)) or 0.0

    -- Smooth is intentionally strong:
    --   0.0 = nearest-frame stepping
    --   1.0 = full glide across the frame span
    local frac
    if smoothAmt <= 0.001 then
      frac = (rawFrac >= 0.5) and 1.0 or 0.0
    else
      local edge0 = 0.5 - 0.5 * smoothAmt
      local edge1 = 0.5 + 0.5 * smoothAmt
      if rawFrac <= edge0 then
        frac = 0.0
      elseif rawFrac >= edge1 then
        frac = 1.0
      else
        frac = (rawFrac - edge0) / math.max(1.0e-6, edge1 - edge0)
        frac = frac * frac * (3.0 - 2.0 * frac) -- smoothstep
      end
    end

    local frameA = temporal.frames[lo]
    local frameB = temporal.frames[hi]
    if not frameA or not frameB then return frameA or frameB end

    -- Interpolate partials
    local countA = tonumber(frameA.activeCount) or 0
    local countB = tonumber(frameB.activeCount) or 0
    local maxCount = math.max(countA, countB)
    if maxCount <= 0 then return frameA end

    local result = {
      activeCount = maxCount,
      fundamental = (tonumber(frameA.fundamental) or 0) + ((tonumber(frameB.fundamental) or 0) - (tonumber(frameA.fundamental) or 0)) * frac,
      brightness = (tonumber(frameA.brightness) or 0) + ((tonumber(frameB.brightness) or 0) - (tonumber(frameA.brightness) or 0)) * frac,
      rmsLevel = (tonumber(frameA.rmsLevel) or 0) + ((tonumber(frameB.rmsLevel) or 0) - (tonumber(frameA.rmsLevel) or 0)) * frac,
      partials = {},
      frequencies = {},
      amplitudes = {},
      phases = {},
    }

    local freqsA = frameA.frequencies or {}
    local freqsB = frameB.frequencies or {}
    local ampsA = frameA.amplitudes or {}
    local ampsB = frameB.amplitudes or {}
    local phsA = frameA.phases or {}
    local phsB = frameB.phases or {}

    for i = 1, maxCount do
      local af = tonumber(freqsA[i]) or 0.0
      local bf = tonumber(freqsB[i]) or 0.0
      local aa = tonumber(ampsA[i]) or 0.0
      local ba = tonumber(ampsB[i]) or 0.0
      local ap = tonumber(phsA[i]) or 0.0
      local bp = tonumber(phsB[i]) or 0.0

      -- Log-frequency interpolation
      local freq
      if af <= 0.01 and bf <= 0.01 then freq = 0.0
      elseif af <= 0.01 then freq = bf * frac
      elseif bf <= 0.01 then freq = af * (1.0 - frac)
      else freq = math.exp(math.log(af) + (math.log(bf) - math.log(af)) * frac) end

      local rawAmp = aa + (ba - aa) * frac

      -- Contrast control: 0 = flatter / gentler, 2 = more dramatic spectral peaks
      local contrastExponent = 1.15 - contrastAmt * 0.45
      local contrastGain = 1.0 + contrastAmt * 0.85
      local contrastAmp = rawAmp > 0.001 and (math.pow(rawAmp, contrastExponent) * contrastGain) or 0.0

      -- Kill truly silent partials (noise floor)
      local noiseFloor = 0.006 - contrastAmt * 0.002
      if contrastAmp < noiseFloor then contrastAmp = 0.0 end

      result.frequencies[i] = freq
      result.amplitudes[i] = contrastAmp
      result.phases[i] = ap + (bp - ap) * frac
      result.partials[i] = {
        frequency = freq,
        amplitude = contrastAmp,
        phase = ap + (bp - ap) * frac,
      }
    end

    -- Phrase contour now lives after the sine-bank normaliser in C++.
    -- Keep the interpolated partial frame itself amplitude-normalized here.

    -- Strong temporal smoothing: smear across neighbouring frames, not just the local crossfade.
    if smoothAmt > 0.001 then
      local prevFrame = temporal.frames[math.max(1, lo - 1)]
      local nextFrame = temporal.frames[math.min(fc, hi + 1)]
      local prevAmps = prevFrame and prevFrame.amplitudes or nil
      local nextAmps = nextFrame and nextFrame.amplitudes or nil
      local prevFreqs = prevFrame and prevFrame.frequencies or nil
      local nextFreqs = nextFrame and nextFrame.frequencies or nil

      for i = 1, maxCount do
        local p = result.partials[i]
        if p then
          local baseAmp = tonumber(p.amplitude) or 0.0
          local baseFreq = tonumber(p.frequency) or 0.0

          local pa = prevAmps and (tonumber(prevAmps[i]) or 0.0) or 0.0
          local na = nextAmps and (tonumber(nextAmps[i]) or 0.0) or 0.0
          local pf = prevFreqs and (tonumber(prevFreqs[i]) or 0.0) or 0.0
          local nf = nextFreqs and (tonumber(nextFreqs[i]) or 0.0) or 0.0

          local avgAmp = (pa + baseAmp + na) / 3.0
          local avgFreq = baseFreq
          if baseFreq > 0.01 or pf > 0.01 or nf > 0.01 then
            local accum = 0.0
            local weight = 0.0
            if pf > 0.01 then accum = accum + math.log(pf) * 0.75; weight = weight + 0.75 end
            if baseFreq > 0.01 then accum = accum + math.log(baseFreq) * 1.5; weight = weight + 1.5 end
            if nf > 0.01 then accum = accum + math.log(nf) * 0.75; weight = weight + 0.75 end
            if weight > 0.0 then avgFreq = math.exp(accum / weight) end
          end

          -- Make Smooth obvious: at 1.0 it strongly favours the averaged temporal smear.
          local smearMix = 0.15 + smoothAmt * 0.85
          p.amplitude = baseAmp + (avgAmp - baseAmp) * smearMix
          p.frequency = avgFreq > 0.01 and (baseFreq + (avgFreq - baseFreq) * smearMix) or baseFreq
          result.amplitudes[i] = p.amplitude
          result.frequencies[i] = p.frequency
        end
      end
    end

    return result
  end

  local function getReferenceTemporalPlayback()
    local refVoice = voices and voicePool.voices[1] or nil
    return refVoice and refVoice.samplePlayback or nil
  end

  local function queryTemporalFrameForVoice(voice, samplePos)
    local tPos = mapTemporalPositionForVoice(voice, samplePos)
    local refPlayback = getReferenceTemporalPlayback()
    if refPlayback and refPlayback.hasTemporalPartials and refPlayback.getTemporalFrameAtPosition then
      local okHas, hasTemporal = pcall(function()
        return refPlayback:hasTemporalPartials()
      end)
      if okHas and hasTemporal then
        local okFrame, frame = pcall(function()
          return refPlayback:getTemporalFrameAtPosition(tPos, morphSmooth or 0.0, morphContrast or 0.5)
        end)
        if okFrame and type(frame) == "table" and (tonumber(frame.activeCount) or 0) > 0 then
          return frame
        end
      end
    end

    -- Fallback to the cached Lua temporal table if the C++ fast path is unavailable.
    return getTemporalFrameAtPosition(latestTemporalPartials, tPos)
  end

  local function applySampleWindowToVoice(voice)
    if not voice or not voice.samplePlayback then
      return
    end

    local capturedLength = tonumber(voice.sampleCapturedLength) or 0
    local fullLength = capturedLength > 0 and capturedLength or (voice.samplePlayback:getLoopLength() or 0)
    if fullLength <= 0 then
      return
    end

    local playStartAbs = Utils.clamp(samplePlayStart, 0.0, 0.95)
    local loopStartAbs = Utils.clamp(sampleLoopStart, 0.0, 0.95)
    local loopEndAbs = Utils.clamp(sampleLoopStart + sampleLoopLen, 0.05, 1.0)
    if loopEndAbs <= loopStartAbs then
      loopEndAbs = math.min(1.0, loopStartAbs + 0.01)
    end
    if playStartAbs > loopEndAbs then
      playStartAbs = loopStartAbs
    end

    voice.playStartNorm = playStartAbs
    voice.loopStartNorm = loopStartAbs
    voice.loopEndNorm = loopEndAbs
    voice.crossfadeNorm = Utils.clamp(sampleCrossfade, 0.0, 0.5)

    voice.samplePlayback:setLoopLength(fullLength)
    voice.samplePlayback:setPlayStart(playStartAbs)
    voice.samplePlayback:setLoopStart(loopStartAbs)
    voice.samplePlayback:setLoopEnd(loopEndAbs)
    voice.samplePlayback:setCrossfade(voice.crossfadeNorm)
  end

  local function analyzeCapturedSample()
    local voice = voicePool.voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastAnalysis then
      latestSampleAnalysis = nil
      return nil
    end

    local ok, analysis = pcall(function()
      return playback:getLastAnalysis()
    end)
    if not ok or type(analysis) ~= "table" then
      ensureSampleAnalysis()
      return latestSampleAnalysis
    end

    local midiNote = tonumber(analysis.midiNote)
    if midiNote ~= nil then
      analysis.midiNote = Utils.clamp(math.floor(midiNote + 0.5), 12, 96)
    end

    latestSampleAnalysis = analysis
    return analysis
  end

  extractCapturedSamplePartials = function(forceExtract, preserveLastGood)
    local voice = voicePool.voices[1]
    local playback = voice and voice.samplePlayback or nil
    if not playback or not playback.getLastPartials then
      latestSamplePartials = nil
      applySampleDerivedPartialsToVoices(nil)
      return nil
    end

    local ok, partials = pcall(function()
      return playback:getLastPartials()
    end)
    if ok and type(partials) == "table" and hasUsableSampleAdditivePartials(partials) then
      latestSamplePartials = partials
      applySampleDerivedPartialsToVoices(partials)
      return partials
    end

    if forceExtract then
      ensureSampleAnalysis()
    end

    if preserveLastGood and hasUsableSampleAdditivePartials(latestSamplePartials) then
      applySampleDerivedPartialsToVoices(latestSamplePartials)
      return latestSamplePartials
    end

    if ok and type(partials) == "table" then
      latestSamplePartials = partials
      applySampleDerivedPartialsToVoices(partials)
      return partials
    end

    latestSamplePartials = nil
    applySampleDerivedPartialsToVoices(nil)
    return nil
  end

  local applyVoiceFrequency

  local function maybeApplyDetectedSampleRoot(analysis)
    if type(analysis) ~= "table" then
      print("PitchMap: no analysis result to apply")
      return false
    end
    if not samplePitchMapEnabled then
      print("PitchMap: toggle off, leaving root at " .. tostring(sampleRootNote))
      return false
    end
    if analysis.reliable ~= true then
      print("PitchMap: analysis not reliable, not applying")
      return false
    end

    local midiNote = tonumber(analysis.midiNote)
    if midiNote == nil then
      print("PitchMap: analysis missing midiNote")
      return false
    end

    local applied = Utils.clamp(math.floor(midiNote + 0.5), 12, 96)
    print("PitchMap: applying root " .. tostring(applied))

    local wrote = false
    if ctx and ctx.host and ctx.host.setParam then
      wrote = ctx.host.setParam(PATHS.sampleRootNote, applied) == true
    end

    if wrote then
      sampleRootNote = applied
      for i = 1, VOICE_COUNT do
        applyVoiceFrequency(i, voicePool.voices[i].freq or 220.0)
      end
    else
      print("PitchMap: host param write failed")
    end

    return wrote
  end

  -- Queue async sample analysis if needed. Never do heavy FFT / partial extraction inline.
  ensureSampleAnalysis = function()
    if sampleAnalysisPending == false or sampleAnalysisInFlight == true then
      return
    end

    local voice = voicePool.voices[1]
    local playback = voice and voice.samplePlayback or nil
    local playbackNode = playback and playback.__node or nil
    if not playbackNode or type(requestSampleRegionPlaybackAsyncAnalysis) ~= "function" then
      return
    end
    local loopLen = (playback and playback.getLoopLength and playback:getLoopLength()) or 0
    if loopLen <= 0 then
      return
    end

    -- Analysis resolution is independent from the front-panel additive density.
    -- Always capture the full partial budget so noisy / speech material does not collapse
    -- into a stupidly sparse fallback just because the render control is low.
    local partialCount = 32
    local ok, err = pcall(function()
      requestSampleRegionPlaybackAsyncAnalysis(playbackNode, partialCount, 1024, 256, 256)
    end)
    if ok then
      sampleAnalysisPending = false
      sampleAnalysisInFlight = true
      print(string.format("AsyncAnalysis: queued loopLen=%d partialCount=%d", loopLen, partialCount))
    else
      print("ensureSampleAnalysis failed to queue async analysis: " .. tostring(err))
    end
  end

  pollAsyncSampleAnalysis = function()
    if sampleAnalysisInFlight ~= true then
      return false
    end

    local voice = voicePool.voices[1]
    local playback = voice and voice.samplePlayback or nil
    local playbackNode = playback and playback.__node or nil
    if not playbackNode or type(isSampleRegionPlaybackAnalysisPending) ~= "function" then
      sampleAnalysisInFlight = false
      return false
    end

    local okPending, pending = pcall(function()
      return isSampleRegionPlaybackAnalysisPending(playbackNode)
    end)
    if not okPending then
      sampleAnalysisInFlight = false
      return false
    end
    if pending == true then
      return false
    end

    sampleAnalysisInFlight = false
    print("AsyncAnalysis: worker finished, harvesting results")

    local okAnalysis, analysis = pcall(function() return getSampleRegionPlaybackLastAnalysis(playbackNode) end)
    local okPartials, partials = pcall(function() return getSampleRegionPlaybackPartials(playbackNode) end)
    local okTemporal, temporal = pcall(function() return getSampleRegionPlaybackTemporalPartials(playbackNode) end)

    if okAnalysis and type(analysis) == "table" then
      latestSampleAnalysis = analysis
      print(string.format("AsyncAnalysis: analysis freq=%.2f reliable=%s midi=%s", tonumber(analysis.frequency) or 0.0, tostring(analysis.reliable), tostring(analysis.midiNote)))
      maybeApplyDetectedSampleRoot(analysis)
    end
    if okPartials and type(partials) == "table" then
      latestSamplePartials = partials
      print(string.format("AsyncAnalysis: partials active=%s fundamental=%.2f", tostring(partials.activeCount), tonumber(partials.fundamental) or 0.0))
      applySampleDerivedPartialsToVoices(partials)
    end
    if okTemporal and type(temporal) == "table" then
      latestTemporalPartials = temporal
      print(string.format("AsyncAnalysis: temporal frames=%s fundamental=%.2f", tostring(temporal.frameCount), tonumber(temporal.globalFundamental) or 0.0))
    end

    local playbackNode = playback and playback.__node or nil
    if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
      local okPeaks, peaks = pcall(function()
        return getSampleRegionPlaybackPeaks(playbackNode, 512)
      end)
      if okPeaks and type(peaks) == "table" and #peaks > 0 then
        cachedSamplePeaks = peaks
        cachedSamplePeakBuckets = #peaks
      end
    end

    applyAllSpectralVoiceParams()
    requestSampleDerivedAdditiveRefresh()
    return true
  end

  local function buildBlendRuntimeOptions(extra)
    local options = {
      blendMode = blendMode,
      blendAmount = blendAmount,
      blendModAmount = blendModAmount,
      blendSamplePitch = blendSamplePitch,
      blendKeyTrack = blendKeyTrack,
      samplePitchMode = samplePitchMode,
      samplePitchModePhaseVocoder = SAMPLE_PITCH_MODE_PHASE_VOCODER,
      samplePitchModePhaseVocoderHQ = SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ,
      additivePartials = additivePartials,
      additiveTilt = additiveTilt,
      additiveDrift = additiveDrift,
      morphCurve = morphCurve,
      morphConvergence = morphConvergence,
      morphPhaseParam = morphPhaseParam,
      morphSpeed = morphSpeed,
      morphContrast = morphContrast,
      morphSmooth = morphSmooth,
      envFollowAmount = envFollowAmount,
      addFlavor = addFlavor,
      addFlavorSelf = ADD_FLAVOR_SELF,
      sampleRootNote = sampleRootNote,
      unisonVoices = unisonVoices,
      detuneCents = detuneCents,
      stereoSpread = stereoSpread,
      sampleToWave = sampleToWave,
      waveToSample = waveToSample,
      sampleRetrigger = sampleRetrigger,
      sampleReferencePlayback = (voicePool.voices[1] and voicePool.voices[1].samplePlayback) or nil,
      latestSampleAnalysis = latestSampleAnalysis,
      latestSamplePartials = latestSamplePartials,
      noteToFrequency = noteToFrequency,
      ensureSampleAnalysis = ensureSampleAnalysis,
      mapTemporalPositionForVoice = mapTemporalPositionForVoice,
    }
    if extra then
      for k, v in pairs(extra) do
        options[k] = v
      end
    end
    return options
  end

  local function isAdditiveBlendMode()
    return sampleSynth.isAdditiveBlendMode(blendMode)
  end

  local function applyVoiceStackingParams(voice)
    sampleSynth.applyVoiceStackingParams(voice, buildBlendRuntimeOptions())
  end

  local function applyAllVoiceStackingParams()
    for i = 1, VOICE_COUNT do
      applyVoiceStackingParams(voicePool.voices[i])
    end
  end

  local function getBlendSamplePlaybackSpeed(voice)
    return sampleSynth.getBlendSamplePlaybackSpeed(voice, buildBlendRuntimeOptions())
  end

  local function applyPitchModeToVoice(voice)
    sampleSynth.applyPitchModeToVoice(voice, buildBlendRuntimeOptions())
  end

  applySpectralVoiceParams = function(voice)
    sampleSynth.applySpectralVoiceParams(voice, buildBlendRuntimeOptions())
  end

  applyAllSpectralVoiceParams = function()
    for i = 1, VOICE_COUNT do
      applySpectralVoiceParams(voicePool.voices[i])
    end
  end

  local function applySampleDerivedAdditiveToVoice(voice, amp)
    sampleSynth.applySampleDerivedAdditiveToVoice(voice, amp, buildBlendRuntimeOptions())
  end

  applyAllSampleDerivedAdditiveStates = function()
    for i = 1, VOICE_COUNT do
      local voice = voicePool.voices[i]
      applySampleDerivedAdditiveToVoice(voice, (voice and (voice.amp or voicePool.lastAmp[i])) or 0.0)
    end
  end

  local function applyBlendParamsToVoice(voice)
    sampleSynth.applyBlendParamsToVoice(voice, buildBlendRuntimeOptions())
  end

  local function applyAllBlendParams()
    for i = 1, VOICE_COUNT do
      applyBlendParamsToVoice(voicePool.voices[i])
    end
  end

  local function applyVoiceModeForAmp(voice, amp)
    if not voice then
      return
    end

    -- Canonical Blend branch for all tabs/modes.
    if voice.voiceMix then
      voice.voiceMix:setGain(1, 0.0) -- osc direct off
      voice.voiceMix:setGain(2, 0.0) -- noise direct off
      voice.voiceMix:setGain(3, 0.0) -- sample direct off
      voice.voiceMix:setGain(4, 1.0) -- canonical path on
    end
    voice.osc:setEnabled(true)
    voice.osc:setAmplitude(amp)
    voice.noiseGain:setGain(0.0)
    voice.sampleGain:setGain(0.0)
    if voice.sampleBlendGain then voice.sampleBlendGain:setGain(amp * 2.0) end
    if isAdditiveBlendMode() and amp > 0.0005 then
      requestSampleDerivedAdditiveRefresh()
    else
      applySampleDerivedAdditiveToVoice(voice, amp)
    end
    applyBlendParamsToVoice(voice)
    if amp <= 0.0005 and voice.gate <= 0.5 then
      voice.samplePlayback:stop()
    end
  end

  local function applyAllVoiceModes()
    for i = 1, VOICE_COUNT do
      local amp = voicePool.lastAmp[i] or 0.0
      applyVoiceModeForAmp(voicePool.voices[i], amp)
    end
  end

  applyVoiceFrequency = function(voiceIndex, frequency)
    local voice = voicePool.voices[voiceIndex]
    if not voice then
      return
    end

    local f = Utils.clamp(tonumber(frequency) or 220.0, 20.0, 8000.0)
    voice.freq = f
    
    -- blendKeyTrack: 0=wave (wave keytracks, sample doesn't), 1=sample (sample keytracks, wave doesn't), 2=both keytrack
    local waveFreq = f
    if blendKeyTrack ~= 1 then
      -- Wave keytracks in modes 0 and 2
      waveFreq = f
      -- In mode 2 (both keytrack), apply pitch knob to wave as well
      if blendKeyTrack == 2 then
        waveFreq = f * (2.0 ^ (Utils.clamp(blendSamplePitch, -24.0, 24.0) / 12.0))
      end
    else
      -- Mode 1: Wave stays at root note frequency (no keytracking)
      local rootFreq = noteToFrequency(sampleRootNote)
      if rootFreq > 0 then
        waveFreq = rootFreq
      else
        waveFreq = 220.0
      end
    end

    voice.osc:setFrequency(waveFreq)
    if voice.blendAddOsc then
      voice.blendAddOsc:setFrequency(waveFreq)
    end

    -- Always set sample playback speed/pitch routing (blend is always active)
    voice.samplePlayback:setSpeed(getBlendSamplePlaybackSpeed(voice))
    applyPitchModeToVoice(voice)
    if isAdditiveBlendMode() and ((voice.amp or voicePool.lastAmp[voiceIndex] or 0.0) > 0.0005) then
      requestSampleDerivedAdditiveRefresh()
    else
      applySampleDerivedAdditiveToVoice(voice, voice.amp or voicePool.lastAmp[voiceIndex] or 0.0)
    end
    applyBlendParamsToVoice(voice)
  end

  local function applyVoiceGate(voiceIndex, gateValue)
    local voice = voicePool.voices[voiceIndex]
    if not voice then
      return
    end

    local g = (tonumber(gateValue) or 0.0) > 0.5 and 1.0 or 0.0
    voice.gate = g
    if g <= 0.5 then
      voice.syncPhase = 0.0

      -- Add/Morph can otherwise get stuck sustaining if we wait for other state to
      -- eventually notice the note-off. Force the additive family to ramp down now.
      if voice.blendAddOsc then
        voice.blendAddOsc:setAmplitude(0.0)
      end
      if voice.sampleAdditive then
        voice.sampleAdditive:setAmplitude(0.0)
      end
      if voice.morphWaveAdditive then
        voice.morphWaveAdditive:setAmplitude(0.0)
      end
      if voice.samplePlayback and (blendMode == 4 or blendMode == 5) then
        voice.samplePlayback:stop()
      end
      voice.lastSampleAdditiveMix = 0.0
      voice.lastSampleAdditiveFreq = 0.0
    end

    -- Trigger ADSR envelope
    if voice.adsr then
      voice.adsr:setGate(g > 0.5)
    end

    -- Always start sample playback (blend is always active)
    if g > 0.5 then
      if sampleRetrigger or not voice.samplePlayback:isPlaying() then
        voice.samplePlayback:trigger()
      else
        voice.samplePlayback:play()
      end
      if voice.sampleAdditive then
        voice.sampleAdditive:reset()
      end
      if voice.samplePhaseVocoder then
        voice.samplePhaseVocoder:reset()
        -- Restore FFT order and time stretch after reset
        voice.samplePhaseVocoder:setFFTOrder(math.floor(samplePvocFFTOrder))
        voice.samplePhaseVocoder:setTimeStretch(samplePvocTimeStretch)
      end
      -- Reset temporal morph cursor on note-on
      voice.morphTemporalPos = 0.0
      voice.lastTemporalSamplePos = nil
      -- Ensure gains and blend params are set for this voice
      applyVoiceModeForAmp(voice, voice.amp or voicePool.lastAmp[voiceIndex] or 0.5)
      applyBlendParamsToVoice(voice)
    end
    -- Note: Don't stop immediately on gate off - let ADSR release fade it out
    -- Sample will be stopped by applyVoiceModeForAmp when amp <= 0.0005
  end

  local function captureSampleFromCurrentSource()
    local sourceEntry = sampleSynth.getSelectedSourceEntry()
    local captureNode = sourceEntry and sourceEntry.capture and sourceEntry.capture.__node or nil
    if not captureNode then
      print("CaptureSample: no capture node")
      return false
    end

    local samplesBack
    local captureMode = sampleSynth.getCaptureMode()
    local captureStartOffset = sampleSynth.getCaptureStartOffset()
    local captureBars = sampleSynth.getCaptureBars()
    
    if captureMode == 1 then
      -- Free mode: calculate from start offset to current position
      local currentOffset = captureNode:getWriteOffset()
      print(string.format("CaptureSample (free): mode=%d startOffset=%d current=%d",
        captureMode, captureStartOffset, currentOffset))

      -- Handle time-based duration (negative startOffset signals time-based)
      if captureStartOffset < 0 then
        samplesBack = math.abs(captureStartOffset)
        print(string.format("CaptureSample (free): time-based duration=%d samples", samplesBack))
      elseif captureStartOffset == 0 then
        print("CaptureSample (free): ERROR - startOffset is 0, using retro mode fallback")
        samplesBack = math.max(1, math.floor(captureBars * hostSamplesPerBar() + 0.5))
      else
        local duration = currentOffset - captureStartOffset
        if duration <= 0 then
          duration = duration + captureNode:getCaptureSize()
        end
        samplesBack = math.max(1, math.floor(duration))
        print(string.format("CaptureSample (free): offset-based duration=%d samplesBack=%d",
          duration, samplesBack))
      end
    else
      -- Retro mode: fixed bar count
      samplesBack = math.max(1, math.floor(captureBars * hostSamplesPerBar() + 0.5))
    end
    
    local copiedAny = false
    print(string.format("CaptureSample: source=%s samplesBack=%d", tostring(sourceEntry and sourceEntry.name), samplesBack))

    for i = 1, VOICE_COUNT do
      local voice = voicePool.voices[i]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node
      local xfadeNode = voice and voice.samplePlaybackX and voice.samplePlaybackX.__node
      if playbackNode then
        local ok, copied = pcall(function()
          return captureNode:copyRecentToLoop(playbackNode, samplesBack, false)
        end)
        print(string.format("CaptureSample: voice=%d ok=%s copied=%s", i, tostring(ok), tostring(copied)))
        if ok and copied then
          copiedAny = true
          voice.sampleCapturedLength = voice.samplePlayback:getLoopLength() or 0
          print(string.format("CaptureSample: voice=%d loopLen=%d", i, tonumber(voice.sampleCapturedLength) or 0))
          -- Copy to crossfade voice too
          if xfadeNode then
            local okX, copiedX = pcall(function()
              return captureNode:copyRecentToLoop(xfadeNode, samplesBack, false)
            end)
            print(string.format("CaptureSample: voice=%d crossfade copied=%s", i, tostring(okX and copiedX)))
          end
          -- Set both voices to full captured length
          if voice.samplePlayback then
            voice.samplePlayback:setLoopLength(voice.sampleCapturedLength)
          end
          if voice.samplePlaybackX then
            voice.samplePlaybackX:setLoopLength(voice.sampleCapturedLength)
          end
          -- Reset to start
          voice.samplePlayback:seek(0)
          if voice.samplePhaseVocoder then
            voice.samplePhaseVocoder:reset()
            -- Restore FFT order and time stretch after reset
            voice.samplePhaseVocoder:setFFTOrder(math.floor(samplePvocFFTOrder))
            voice.samplePhaseVocoder:setTimeStretch(samplePvocTimeStretch)
          end
          if voice.samplePlaybackX then
            voice.samplePlaybackX:seek(0)
          end
          if voice.gate > 0.5 then
            voice.samplePlayback:play()
          end
          voice.isFirstTrigger = true
          applySampleWindowToVoice(voice)
          applyVoiceFrequency(i, voice.freq or 220.0)
        end
      else
        print(string.format("CaptureSample: voice=%d no playback node", i))
      end
    end

    if copiedAny and type(getSampleRegionPlaybackPeaks) == "function" then
      local voice = voicePool.voices[1]
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
      local ok, peaks = pcall(function()
        return getSampleRegionPlaybackPeaks(playbackNode, 512)
      end)
      if ok and type(peaks) == "table" and #peaks > 0 then
        cachedSamplePeaks = peaks
        cachedSamplePeakBuckets = #cachedSamplePeaks
      end
    end

    print("CaptureSample: copiedAny=" .. tostring(copiedAny))
    
    -- Calculate captured length in milliseconds
    local capturedLengthMs = 0
    if copiedAny then
      local sampleRate = hostSampleRate and hostSampleRate() or 48000
      capturedLengthMs = math.floor((samplesBack / sampleRate) * 1000 + 0.5)
      print(string.format("CaptureSample: length=%d ms", capturedLengthMs))
    end
    
    if copiedAny then
      for i = 1, VOICE_COUNT do
        local voice = voicePool.voices[i]
        if voice and voice.sampleAdditive then
          if voice.sampleAdditive.setSpectralSamplePlayback then
            voice.sampleAdditive:setSpectralSamplePlayback((voicePool.voices[1] and voicePool.voices[1].samplePlayback) or voice.samplePlayback)
          end
          if voice.sampleAdditive.setSpectralTemporalPosition then
            voice.sampleAdditive:setSpectralTemporalPosition(0.0)
          end
          voice.morphTemporalPos = 0.0
          voice.lastTemporalSamplePos = nil
        end
      end
      applyAllSpectralVoiceParams()
      -- Keep current published analysis/partials alive until the async replacement finishes.
      -- That avoids the dead-zone where Morph/Add lose both audio and visuals.
      sampleAnalysisPending = true
      sampleAnalysisInFlight = false
      ensureSampleAnalysis()
      requestSampleDerivedAdditiveRefresh()
    end

    return copiedAny, capturedLengthMs
  end

  local function applyWaveform(value)
    local wf = Utils.roundIndex(value, 7)
    for i = 1, VOICE_COUNT do
      voicePool.voices[i].waveform = wf
      voicePool.voices[i].osc:setWaveform(wf)
      voicePool.voices[i].blendAddOsc:setWaveform(wf)
      if voicePool.voices[i].sampleAdditive and voicePool.voices[i].sampleAdditive.setSpectralWaveform then
        voicePool.voices[i].sampleAdditive:setSpectralWaveform(wf)
      end
    end
  end

  local function applyFilterType(value)
    filt:setMode(Utils.roundIndex(value, 3))
  end

  applyWaveform(1)
  -- Initialize canonical blend path for all voices up front so Wave/Sample
  -- tabs behave like Blend DSP immediately, without requiring a tab switch.
  sampleSynth.initializeVoiceGraphDefaults(voicePool.voices, {
    adsr = adsr,
    oscRenderStandard = OSC_RENDER_STANDARD,
    oscRenderAdd = OSC_RENDER_ADD,
    addFlavorSelf = ADD_FLAVOR_SELF,
  })
  for i = 1, VOICE_COUNT do
    applySampleWindowToVoice(voicePool.voices[i])
    applyVoiceFrequency(i, voicePool.voices[i].freq or 220.0)
    applyVoiceModeForAmp(voicePool.voices[i], voicePool.lastAmp[i] or 0.0)
    applyBlendParamsToVoice(voicePool.voices[i])
  end

  local function forEachVoice(fn)
    for i = 1, VOICE_COUNT do
      fn(voicePool.voices[i], i)
    end
  end

  local function applyRackSourcePath(path, value)
    if tostring(path or "") == PATHS.rackAudioSourceCount then
      rackSourceState.count = math.max(0, math.floor(tonumber(value) or 0))
      applyRackSourceSequence()
      applyRackStageSequence()
      return true
    end
    local sourceIndex = tostring(path or ""):match("^/midi/synth/rack/source/(%d+)$")
    if sourceIndex == nil then
      return false
    end
    local idx = math.max(1, math.floor(tonumber(sourceIndex) or 1))
    rackSourceState.sources[idx] = math.max(0, math.floor(tonumber(value) or 0))
    applyRackSourceSequence()
    applyRackStageSequence()
    return true
  end

  local auxAudioConnectionsApplied = {}

  local function appendAuxAudioConnection(desired, fromNode, toNode)
    if not (fromNode and toNode) then
      return
    end
    for i = 1, #desired do
      local existing = desired[i]
      if existing and existing.from == fromNode and existing.to == toNode then
        return
      end
    end
    desired[#desired + 1] = { from = fromNode, to = toNode }
  end

  local function applyDesiredAuxAudioConnections(desired)
    local current = auxAudioConnectionsApplied or {}
    local mutated = false
    for i = 1, #current do
      local conn = current[i]
      local keep = false
      for j = 1, #(desired or {}) do
        local target = desired[j]
        if target and target.from == conn.from and target.to == conn.to then
          keep = true
          break
        end
      end
      if not keep and conn and conn.from and conn.to then
        ctx.graph.disconnect(conn.from, conn.to)
        mutated = true
      end
    end

    for i = 1, #(desired or {}) do
      local conn = desired[i]
      local present = false
      for j = 1, #current do
        local existing = current[j]
        if existing and existing.from == conn.from and existing.to == conn.to then
          present = true
          break
        end
      end
      if not present and conn and conn.from and conn.to then
        ctx.graph.connect(conn.from, conn.to)
        mutated = true
      end
    end

    auxAudioConnectionsApplied = desired
  end

  local function resolveAuxAudioSourceNodeByCode(code)
    local sourceCode = math.max(0, math.floor(tonumber(code) or 0))
    if sourceCode == (AUX_AUDIO_SOURCE_CODES.OSCILLATOR or 1) then
      return mix
    elseif sourceCode == (AUX_AUDIO_SOURCE_CODES.FILTER or 2) then
      return filt
    elseif sourceCode == (AUX_AUDIO_SOURCE_CODES.FX1 or 3) then
      return fx1Slot and fx1Slot.output or nil
    elseif sourceCode == (AUX_AUDIO_SOURCE_CODES.FX2 or 4) then
      return fx2Slot and fx2Slot.output or nil
    elseif sourceCode == (AUX_AUDIO_SOURCE_CODES.EQ or 5) then
      return eq8
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_OSC_BASE or 100) and sourceCode < (AUX_AUDIO_SOURCE_CODES.DYNAMIC_SAMPLE_BASE or 200) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_OSC_BASE or 100)
      local slot = dynamicOscillatorSlots[slotIndex]
      return slot and slot.output or nil
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_SAMPLE_BASE or 200) and sourceCode < (AUX_AUDIO_SOURCE_CODES.DYNAMIC_BLEND_SIMPLE_BASE or 300) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_SAMPLE_BASE or 200)
      local slot = dynamicSampleSlots[slotIndex]
      return slot and slot.output or nil
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_BLEND_SIMPLE_BASE or 300) and sourceCode < (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FILTER_BASE or 400) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_BLEND_SIMPLE_BASE or 300)
      local slot = dynamicBlendSimpleSlots[slotIndex]
      return slot and slot.output or nil
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FILTER_BASE or 400) and sourceCode < (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FX_BASE or 500) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FILTER_BASE or 400)
      local slot = dynamicFilterSlots[slotIndex]
      return slot and slot.node or nil
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FX_BASE or 500) and sourceCode < (AUX_AUDIO_SOURCE_CODES.DYNAMIC_EQ_BASE or 600) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_FX_BASE or 500)
      local slot = dynamicFxSlots[slotIndex]
      return slot and slot.output or nil
    elseif sourceCode >= (AUX_AUDIO_SOURCE_CODES.DYNAMIC_EQ_BASE or 600) then
      local slotIndex = sourceCode - (AUX_AUDIO_SOURCE_CODES.DYNAMIC_EQ_BASE or 600)
      local slot = dynamicEqSlots[slotIndex]
      return slot and slot.node or nil
    end
    return nil
  end

  local function safeGetParam(path)
    if ctx.host and ctx.host.getParam then
      return ctx.host.getParam(path)
    end
    return nil
  end

  local function refreshAuxAudioConnectionsFromParams()
    local desired = {}
    local unresolved = {}

    for slotIndex, slot in pairs(dynamicBlendSimpleSlots) do
      local sourceCode = tonumber(safeGetParam(ParameterBinder.dynamicBlendSimpleBSourcePath(slotIndex)) or 0) or 0
      local sourceNode = resolveAuxAudioSourceNodeByCode(sourceCode)
      if sourceNode and slot and slot.inputB then
        appendAuxAudioConnection(desired, sourceNode, slot.inputB)
      elseif sourceCode ~= 0 then
        unresolved[#unresolved + 1] = string.format("blend_simple:%d:b:%d", slotIndex, sourceCode)
      end
    end

    for slotIndex, slot in pairs(dynamicSampleSlots) do
      local sourceCode = tonumber(safeGetParam(ParameterBinder.dynamicSampleInputSourcePath(slotIndex)) or 0) or 0
      local sourceNode = resolveAuxAudioSourceNodeByCode(sourceCode)
      if sourceNode and slot and slot.captureInput then
        appendAuxAudioConnection(desired, sourceNode, slot.captureInput)
      elseif sourceCode ~= 0 then
        unresolved[#unresolved + 1] = string.format("rack_sample:%d:in:%d", slotIndex, sourceCode)
      end
    end

    if type(_G) == "table" then
      _G.__midiSynthRackAuxAudioState = {
        desiredCount = #desired,
        unresolved = unresolved,
      }
    end

    applyDesiredAuxAudioConnections(desired)
    return #unresolved == 0
  end

  rackOscillatorModule.refreshAll()

  local function reapplyVoiceFrequencies()
    forEachVoice(function(voice, i)
      applyVoiceFrequency(i, voice.freq or 220.0)
    end)
  end

  local function reapplySampleWindows()
    forEachVoice(function(voice)
      applySampleWindowToVoice(voice)
    end)
  end

  local function invalidateMorphCache()
    cachedMorphWaveKey = nil
    cachedMorphWavePartials = nil
  end

  local function maybeRequestSampleDerivedRefresh()
    if blendMode == 4 or blendMode == 5 then
      requestSampleDerivedAdditiveRefresh()
    end
  end

  local function updateAdsr(field, value, normalize, setterName)
    local normalized = normalize(value)
    adsr[field] = normalized
    forEachVoice(function(voice)
      if voice.adsr then
        voice.adsr[setterName](voice.adsr, normalized)
      end
    end)
  end

  local function applyRackStagePath(path, value)
    local stageIndex = tostring(path or ""):match("^/midi/synth/rack/stage/(%d+)$")
    if stageIndex == nil then
      return false
    end
    local idx = math.max(1, math.floor(tonumber(stageIndex) or 1))
    rackStageState.stages[idx] = math.max(0, math.floor(tonumber(value) or 0))
    applyRackStageSequence()
    return true
  end

  local onParamChange = ParameterBinder.createDispatcher({
    resolveVoicePath = voicePool.resolvePath,
    onVoiceFreq = function(voiceIdx, value)
      voicePool.setFrequency(voiceIdx, value, {
        blendKeyTrack = blendKeyTrack,
        sampleRootNote = sampleRootNote,
      })
      applyVoiceFrequency(voiceIdx, value)
    end,
    onVoiceGate = function(voiceIdx, value)
      voicePool.setGate(voiceIdx, value, {
        stopOnGateOff = (blendMode == 4 or blendMode == 5),
        sampleRetrigger = sampleRetrigger,
      })
      applyVoiceGate(voiceIdx, value)
    end,
    onVoiceAmp = function(voiceIdx, value)
      voicePool.setAmplitude(voiceIdx, value)
      applyVoiceModeForAmp(voicePool.voices[voiceIdx], tonumber(value) or 0)
    end,
    exactHandlers = {
      [PATHS.noiseLevel] = function(value)
        currentNoiseLevel = Utils.clamp01(tonumber(value) or 0.0)
        applyAllVoiceModes()
      end,
      [PATHS.oscRenderMode] = function(value)
        renderMode = Utils.roundIndex(value, 1)
        forEachVoice(function(voice)
          voice.osc:setRenderMode(renderMode)
        end)
      end,
      [PATHS.additivePartials] = function(value)
        additivePartials = math.floor(Utils.clamp(tonumber(value) or 8, 1, 32) + 0.5)
        forEachVoice(function(voice)
          voice.additivePartials = additivePartials
          voice.osc:setAdditivePartials(additivePartials)
          voice.blendAddOsc:setAdditivePartials(additivePartials)
        end)
        applyAllSpectralVoiceParams()
        invalidateMorphCache()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.additiveTilt] = function(value)
        additiveTilt = Utils.clamp(tonumber(value) or 0.0, -1.0, 1.0)
        forEachVoice(function(voice)
          voice.additiveTilt = additiveTilt
          voice.osc:setAdditiveTilt(additiveTilt)
          voice.blendAddOsc:setAdditiveTilt(additiveTilt)
        end)
        applyAllSpectralVoiceParams()
        invalidateMorphCache()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.additiveDrift] = function(value)
        additiveDrift = Utils.clamp(tonumber(value) or 0.0, 0.0, 1.0)
        forEachVoice(function(voice)
          voice.additiveDrift = additiveDrift
          voice.osc:setAdditiveDrift(additiveDrift)
          voice.blendAddOsc:setAdditiveDrift(additiveDrift)
        end)
        applyAllSpectralVoiceParams()
        invalidateMorphCache()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.oscMode] = function()
        sampleMode = OSC_MODE_BLEND
        forEachVoice(function(voice, i)
          applySampleWindowToVoice(voice)
          applyVoiceFrequency(i, voice.freq or 220.0)
          if voice.gate > 0.5 then
            if sampleRetrigger then
              voice.samplePlayback:trigger()
            else
              voice.samplePlayback:play()
            end
          end
        end)
        applyAllBlendParams()
        applyAllVoiceModes()
      end,
      [PATHS.sampleSource] = function(value)
        sampleSynth.setSource(Utils.roundIndex(value, captureSourceConfig.paramMax))
      end,
      [PATHS.sampleCaptureBars] = function(value)
        sampleSynth.setCaptureBars(Utils.clamp(tonumber(value) or 1.0, 0.0625, 16.0))
      end,
      [PATHS.sampleCaptureMode] = function(value)
        sampleSynth.setCaptureMode(value)
        print(string.format("DSP: capture mode = %s", sampleSynth.getCaptureMode() == 1 and "free" or "retro"))
      end,
      [PATHS.sampleCaptureStartOffset] = function(value)
        sampleSynth.setCaptureStartOffset(math.floor(tonumber(value) or 0))
        print(string.format("DSP: capture start offset = %d", sampleSynth.getCaptureStartOffset()))
      end,
      [PATHS.samplePitchMapEnabled] = function(value)
        samplePitchMapEnabled = (tonumber(value) or 0.0) > 0.5
        if samplePitchMapEnabled then
          maybeApplyDetectedSampleRoot(analyzeCapturedSample())
        end
      end,
      [PATHS.samplePitchMode] = function(value)
        samplePitchMode = Utils.roundIndex(value, SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ)
        local pvocMode = 0
        if samplePitchMode == SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ then
          pvocMode = 1
        end
        forEachVoice(function(voice)
          if voice and voice.samplePhaseVocoder then
            voice.samplePhaseVocoder:setMode(pvocMode)
            voice.samplePhaseVocoder:setFFTOrder(math.floor(samplePvocFFTOrder))
            voice.samplePhaseVocoder:setTimeStretch(samplePvocTimeStretch)
          end
        end)
        reapplyVoiceFrequencies()
      end,
      [PATHS.samplePvocFFTOrder] = function(value)
        samplePvocFFTOrder = Utils.clamp(tonumber(value) or 11, 9, 12)
        forEachVoice(function(voice)
          if voice and voice.samplePhaseVocoder then
            voice.samplePhaseVocoder:setFFTOrder(math.floor(samplePvocFFTOrder))
            local sr = (ctx.host and ctx.host.getSampleRate and tonumber(ctx.host.getSampleRate())) or 44100.0
            voice.samplePhaseVocoder:prepare(sr, 512)
          end
        end)
      end,
      [PATHS.samplePvocTimeStretch] = function(value)
        samplePvocTimeStretch = Utils.clamp(tonumber(value) or 1.0, 0.25, 4.0)
        forEachVoice(function(voice)
          if voice and voice.samplePhaseVocoder then
            voice.samplePhaseVocoder:setTimeStretch(samplePvocTimeStretch)
          end
        end)
      end,
      [PATHS.sampleRootNote] = function(value)
        sampleRootNote = Utils.clamp(tonumber(value) or 60.0, 12.0, 96.0)
        reapplyVoiceFrequencies()
      end,
      [PATHS.samplePlayStart] = function(value)
        samplePlayStart = Utils.clamp01(tonumber(value) or 0.0)
        reapplySampleWindows()
      end,
      [PATHS.sampleLoopStart] = function(value)
        sampleLoopStart = Utils.clamp01(tonumber(value) or 0.0)
        reapplySampleWindows()
      end,
      [PATHS.sampleLoopLen] = function(value)
        sampleLoopLen = Utils.clamp(tonumber(value) or 1.0, 0.05, 1.0)
        reapplySampleWindows()
      end,
      [PATHS.sampleCrossfade] = function(value)
        sampleCrossfade = Utils.clamp(tonumber(value) or 0.1, 0.0, 0.5)
        reapplySampleWindows()
      end,
      [PATHS.sampleRetrigger] = function(value)
        sampleRetrigger = (tonumber(value) or 0.0) > 0.5
      end,
      [PATHS.sampleAdditiveEnabled] = function(value)
        sampleAdditiveEnabled = (tonumber(value) or 0.0) > 0.5
        local ready = refreshSampleDerivedPartialsFromPlayback("param-sampleAdditiveEnabled")
        applyAllSampleDerivedAdditiveStates()
        print(string.format(
          "SampleAdditiveDebug: enabled=%s ready=%s count=%s fundamental=%.2f blendMode=%d blendAmount=%.3f",
          tostring(sampleAdditiveEnabled),
          tostring(ready),
          tostring(latestSamplePartials and latestSamplePartials.activeCount),
          tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
          blendMode,
          blendAmount
        ))
      end,
      [PATHS.sampleAdditiveMix] = function(value)
        sampleAdditiveMix = Utils.clamp01(tonumber(value) or 0.25)
        requestSampleDerivedAdditiveRefresh()
      end,
      [PATHS.sampleCaptureTrigger] = function(value)
        if (tonumber(value) or 0.0) > 0.5 then
          local ok, lengthMs = captureSampleFromCurrentSource()
          if ok and lengthMs and lengthMs > 0 then
            sampleSynth.setLastCapturedLengthMs(lengthMs)
            print(string.format("DSP: stored captured length = %d ms", lengthMs))
          end
        end
      end,
      [PATHS.blendMode] = function(value)
        blendMode = Utils.roundIndex(value, 5)
        sampleAdditiveEnabled = (blendMode == 4 or blendMode == 5)
        applyAllVoiceStackingParams()
        if sampleAdditiveEnabled then
          refreshSampleDerivedPartialsFromPlayback("param-blendMode")
        end
        applyAllSpectralVoiceParams()
        applyAllBlendParams()
        applyAllSampleDerivedAdditiveStates()
      end,
      [PATHS.blendAmount] = function(value)
        blendAmount = Utils.clamp01(tonumber(value) or 0.5)
        applyAllSpectralVoiceParams()
        applyAllBlendParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.waveToSample] = function(value)
        waveToSample = Utils.clamp01(tonumber(value) or 0.5)
      end,
      [PATHS.sampleToWave] = function(value)
        sampleToWave = Utils.clamp01(tonumber(value) or 0.0)
      end,
      [PATHS.blendKeyTrack] = function(value)
        blendKeyTrack = Utils.roundIndex(value, 2)
        reapplyVoiceFrequencies()
        requestSampleDerivedAdditiveRefresh()
      end,
      [PATHS.blendSamplePitch] = function(value)
        blendSamplePitch = Utils.clamp(tonumber(value) or 0.0, -24.0, 24.0)
        reapplyVoiceFrequencies()
        requestSampleDerivedAdditiveRefresh()
      end,
      [PATHS.blendModAmount] = function(value)
        blendModAmount = Utils.clamp01(tonumber(value) or 0.5)
        applyAllSpectralVoiceParams()
        applyAllBlendParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.addFlavor] = function(value)
        addFlavor = Utils.roundIndex(value, 1)
        applyAllSpectralVoiceParams()
        requestSampleDerivedAdditiveRefresh()
      end,
      [PATHS.xorBehavior] = function()
      end,
      [PATHS.morphCurve] = function(value)
        morphCurve = Utils.roundIndex(value, 2)
        applyAllSpectralVoiceParams()
        requestSampleDerivedAdditiveRefresh()
      end,
      [PATHS.morphConvergence] = function(value)
        morphConvergence = Utils.clamp01(tonumber(value) or 0.0)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.morphPhase] = function(value)
        morphPhaseParam = Utils.roundIndex(value, 2)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.morphSpeed] = function(value)
        morphSpeed = Utils.clamp(tonumber(value) or 1.0, 0.0, 4.0)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.morphContrast] = function(value)
        morphContrast = Utils.clamp(tonumber(value) or 0.5, 0.0, 2.0)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.morphSmooth] = function(value)
        morphSmooth = Utils.clamp01(tonumber(value) or 0.0)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.envFollowAmount] = function(value)
        envFollowAmount = Utils.clamp01(tonumber(value) or 1.0)
        applyAllSpectralVoiceParams()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.waveform] = function(value)
        applyWaveform(value)
        applyAllSpectralVoiceParams()
        invalidateMorphCache()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.pulseWidth] = function(value)
        local pw = Utils.clamp(tonumber(value) or 0.5, 0.01, 0.99)
        forEachVoice(function(voice)
          voice.pulseWidth = pw
          voice.osc:setPulseWidth(pw)
          voice.blendAddOsc:setPulseWidth(pw)
          if voice.sampleAdditive and voice.sampleAdditive.setSpectralPulseWidth then
            voice.sampleAdditive:setSpectralPulseWidth(pw)
          end
        end)
        invalidateMorphCache()
        maybeRequestSampleDerivedRefresh()
      end,
      [PATHS.unison] = function(value)
        unisonVoices = math.floor(Utils.clamp(tonumber(value) or 1, 1, 8) + 0.5)
        applyAllVoiceStackingParams()
      end,
      [PATHS.detune] = function(value)
        detuneCents = Utils.clamp(tonumber(value) or 0, 0, 100)
        applyAllVoiceStackingParams()
      end,
      [PATHS.spread] = function(value)
        stereoSpread = Utils.clamp(tonumber(value) or 0, 0, 1)
        applyAllVoiceStackingParams()
      end,
      [PATHS.driveShape] = function(value)
        local shape = Utils.roundIndex(value, 3)
        forEachVoice(function(voice)
          voice.osc:setDriveShape(shape)
          voice.blendAddOsc:setDriveShape(shape)
        end)
      end,
      [PATHS.driveBias] = function(value)
        local bias = Utils.clamp(tonumber(value) or 0, -1, 1)
        forEachVoice(function(voice)
          voice.osc:setDriveBias(bias)
          voice.blendAddOsc:setDriveBias(bias)
        end)
      end,
      [PATHS.drive] = function(value)
        local drv = Utils.clamp(tonumber(value) or 0, 0, 20)
        forEachVoice(function(voice)
          voice.osc:setDrive(drv)
          voice.blendAddOsc:setDrive(drv)
        end)
      end,
      [PATHS.filterType] = function(value)
        applyFilterType(value)
      end,
      [PATHS.attack] = function(value)
        updateAdsr("attack", value, function(v) return math.max(0.001, tonumber(v) or 0.05) end, "setAttack")
      end,
      [PATHS.decay] = function(value)
        updateAdsr("decay", value, function(v) return math.max(0.001, tonumber(v) or 0.2) end, "setDecay")
      end,
      [PATHS.sustain] = function(value)
        updateAdsr("sustain", value, function(v) return math.max(0.0, math.min(1.0, tonumber(v) or 0.7)) end, "setSustain")
      end,
      [PATHS.release] = function(value)
        updateAdsr("release", value, function(v) return math.max(0.001, tonumber(v) or 0.4) end, "setRelease")
      end,
      [PATHS.fx1Type] = function(value)
        fx1Slot.applySelection(value)
      end,
      [PATHS.fx1Mix] = function(value)
        fx1Slot.applyMix(value)
      end,
      [PATHS.fx2Type] = function(value)
        fx2Slot.applySelection(value)
      end,
      [PATHS.fx2Mix] = function(value)
        fx2Slot.applyMix(value)
      end,
      [PATHS.rackAudioStageCount] = function(value)
        rackStageState.count = math.max(0, math.floor(tonumber(value) or 0))
        applyRackStageSequence()
      end,
      [PATHS.rackAudioOutputEnabled] = function(value)
        rackStageState.connectOutput = (tonumber(value) or 0) > 0.5
        applyRackStageSequence()
      end,
      [PATHS.rackAudioEdgeMask] = function(value)
        rackAudioRouter.edgeMask = tonumber(value) or RackAudioRouter.DEFAULT_EDGE_MASK
        rackAudioRouter.activeEdges = {}
        applyRackStageSequence()
      end,
      [PATHS.rackRegistryRequestKind] = function(value)
        registryRequestState.kind = math.max(0, math.floor(tonumber(value) or 0))
        print(string.format("RackRegistry: kind=%d", registryRequestState.kind))
      end,
      [PATHS.rackRegistryRequestIndex] = function(value)
        registryRequestState.index = math.max(0, math.floor(tonumber(value) or 0))
        print(string.format("RackRegistry: index=%d", registryRequestState.index))
      end,
      [PATHS.rackRegistryRequestNonce] = function()
        local kind = math.max(0, math.floor(tonumber(registryRequestState.kind) or 0))
        local index = math.max(0, math.floor(tonumber(registryRequestState.index) or 0))
        local specId = ParameterBinder.specIdForRegistryRequestKind(kind)
        print(string.format("RackRegistry: nonce spec=%s index=%d", tostring(specId), index))
        if specId == "rack_audio_stage" then
          return ensureRackAudioStagePath(index)
        elseif specId == "rack_audio_source" then
          return ensureRackAudioSourcePath(index)
        elseif specId ~= nil then
          return ensureDynamicModuleSlot(specId, index)
        end
      end,
    },
    ignorePredicates = {
      function(path)
        return ParameterBinder.isEq8Path(path)
      end,
    },
    patternHandlers = {
      ParameterBinder.fxSlotPatternHandler("fx1", fx1Slot),
      ParameterBinder.fxSlotPatternHandler("fx2", fx2Slot),
      rackEqModule.applyPath,
      rackFxModule.applyPath,
      rackFilterModule.applyPath,
      rackBlendSimpleModule.applyPath,
      rackSampleModule.applyPath,
      rackOscillatorModule.applyPath,
      applyRackStagePath,
      applyRackSourcePath,
    },
  })

  return {
    params = params,
    onParamChange = onParamChange,

    process = function(blockSize, sampleRate)
      local sr = tonumber(sampleRate) or 44100.0
      local n = tonumber(blockSize) or 0
      if sr <= 1.0 or n <= 0 then
        return
      end

      -- Keep async sample analysis results flowing back into Lua/DSP state.
      pollAsyncSampleAnalysis()
      refreshAuxAudioConnectionsFromParams()
      for slotIndex, _ in pairs(dynamicSampleSlots) do
        rackSampleModule.pollAnalysis(slotIndex)
        rackSampleModule.updateReadbacks(slotIndex)
      end

      local additiveRefreshPending = sampleDerivedAdditiveRefreshPending == true
      sampleDerivedAdditiveRefreshPending = false

      for i = 1, VOICE_COUNT do
        local voice = voicePool.voices[i]
        if voice and voice.gate > 0.5 then
          sampleSynth.updateBlendVoiceFrame(voice, buildBlendRuntimeOptions({
            sr = sr,
            blockSamples = n,
            additiveRefreshPending = additiveRefreshPending,
            amp = voice.amp or voicePool.lastAmp[i] or 0.0,
          }))
        elseif voice then
          sampleSynth.resetBlendVoiceFrameState(voice)
        end
      end
    end,

    getSamplePeaks = function(numBuckets)
      numBuckets = numBuckets or 100
      pollAsyncSampleAnalysis()
      if type(cachedSamplePeaks) ~= "table" or #cachedSamplePeaks == 0 then
        local voice = voicePool.voices[1]
        local playback = voice and voice.samplePlayback or nil
        local playbackNode = playback and playback.__node or nil
        if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
          local ok, peaks = pcall(function()
            return getSampleRegionPlaybackPeaks(playbackNode, math.max(32, numBuckets))
          end)
          if ok and type(peaks) == "table" and #peaks > 0 then
            cachedSamplePeaks = peaks
            cachedSamplePeakBuckets = #peaks
          end
        end
      end
      if type(cachedSamplePeaks) ~= "table" or #cachedSamplePeaks == 0 then
        return {}
      end
      return resamplePeaks(cachedSamplePeaks, numBuckets)
    end,

    getSampleLoopLength = function()
      local voice = voicePool.voices[1]
      if voice and voice.samplePlayback then
        return voice.samplePlayback:getLoopLength()
      end
      return 0
    end,

    getLatestSampleAnalysis = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voicePool.voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackLastAnalysis) == "function" then
        local ok, analyzed = pcall(function() return getSampleRegionPlaybackLastAnalysis(playbackNode) end)
        if ok and type(analyzed) == "table" and next(analyzed) ~= nil then
          latestSampleAnalysis = analyzed
          return analyzed
        end
      end

      if type(latestSampleAnalysis) == "table" then
        return latestSampleAnalysis
      end
      return {}
    end,

    getLatestSamplePartials = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voicePool.voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackPartials) == "function" then
        local ok, extracted = pcall(function() return getSampleRegionPlaybackPartials(playbackNode) end)
        if ok and type(extracted) == "table" and ((tonumber(extracted.activeCount) or 0) > 0) then
          latestSamplePartials = extracted
          applySampleDerivedPartialsToVoices(extracted)
          return extracted
        end
      end

      if type(latestSamplePartials) == "table" then
        return latestSamplePartials
      end
      applySampleDerivedPartialsToVoices(nil)
      return {}
    end,

    getLatestTemporalPartials = function()
      ensureSampleAnalysis()
      pollAsyncSampleAnalysis()

      local voice = voicePool.voices[1]
      local playback = voice and voice.samplePlayback or nil
      local playbackNode = playback and playback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackTemporalPartials) == "function" then
        local ok, temporal = pcall(function() return getSampleRegionPlaybackTemporalPartials(playbackNode) end)
        if ok and type(temporal) == "table" and ((tonumber(temporal.frameCount) or 0) > 0) then
          latestTemporalPartials = temporal
          return temporal
        end
      end

      if type(latestTemporalPartials) == "table" then
        return latestTemporalPartials
      end
      return {}
    end,

    refreshSampleDerivedAdditive = function()
      local ready = refreshSampleDerivedPartialsFromPlayback()
      -- Also refresh temporal partials if in Morph mode
      if blendMode == 5 then
        extractTemporalPartials("refresh-additive-morph")
      end
      applyAllSampleDerivedAdditiveStates()
      return {
        enabled = blendMode == 4 or blendMode == 5,
        ready = ready,
        mix = blendAmount,
        activeCount = tonumber(latestSamplePartials and latestSamplePartials.activeCount) or 0,
        fundamental = tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
        temporalFrames = latestTemporalPartials and tonumber(latestTemporalPartials.frameCount) or 0,
      }
    end,

    getVoiceSamplePositions = function()
      local positions = {}
      for i = 1, VOICE_COUNT do
        local voice = voicePool.voices[i]
        if voice and voice.amp > 0.0001 then
          positions[i] = (voice.samplePlayback and voice.samplePlayback:getNormalizedPosition()) or 0
        else
          positions[i] = 0
        end
      end
      return positions
    end,

    getDynamicSampleSlotPeaks = function(slotIndex, numBuckets)
      local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
      if not slot then
        return {}
      end
      local bucketCount = math.max(32, math.floor(tonumber(numBuckets) or 128))
      if type(slot.cachedSamplePeaks) == "table" and #slot.cachedSamplePeaks > 0 then
        return sampleSynth.resamplePeaks(slot.cachedSamplePeaks, bucketCount)
      end
      local voice = slot.voices and slot.voices[1] or nil
      local playbackNode = voice and voice.samplePlayback and voice.samplePlayback.__node or nil
      if playbackNode and type(getSampleRegionPlaybackPeaks) == "function" then
        local ok, peaks = pcall(function()
          return getSampleRegionPlaybackPeaks(playbackNode, bucketCount)
        end)
        if ok and type(peaks) == "table" and #peaks > 0 then
          slot.cachedSamplePeaks = peaks
          slot.cachedSamplePeakBuckets = #peaks
          return sampleSynth.resamplePeaks(peaks, bucketCount)
        end
      end
      return {}
    end,

    getDynamicSampleSlotVoicePositions = function(slotIndex)
      local slot = dynamicSampleSlots[math.max(1, math.floor(tonumber(slotIndex) or 1))]
      local out = {}
      local voices = slot and slot.voices or {}
      for i = 1, #voices do
        local voice = voices[i]
        out[i] = (voice and voice.samplePlayback and voice.samplePlayback.getNormalizedPosition and voice.samplePlayback:getNormalizedPosition()) or 0.0
      end
      return out
    end,

    getSampleDerivedAddDebug = function(voiceIndex)
      local idx = math.max(1, math.min(VOICE_COUNT, tonumber(voiceIndex) or 1))
      local voice = voicePool.voices[idx]
      if not voice then
        return {}
      end
      local sampleNode = voice.sampleAdditive and voice.sampleAdditive.__node or nil
      local blendOscNode = voice.blendAddOsc and voice.blendAddOsc.__node or nil
      return {
        enabled = blendMode == 4 or blendMode == 5,
        ready = hasUsableSampleAdditivePartials(latestSamplePartials),
        mix = blendAmount,
        voiceAmp = voice.amp or 0.0,
        gate = voice.gate or 0.0,
        targetFrequency = voice.lastSampleAdditiveFreq or 0.0,
        busMix = voice.lastSampleAdditiveMix or 0.0,
        activeCount = tonumber(latestSamplePartials and latestSamplePartials.activeCount) or 0,
        fundamental = tonumber(latestSamplePartials and latestSamplePartials.fundamental) or 0.0,
        referenceNote = sampleRootNote,
        blendSampleSpeed = voice.lastBlendSampleSpeed or 0.0,
        addCrossfadePosition = voice.addCrossfade and voice.addCrossfade:getPosition() or -9,
        addBranchGain = voice.addBranchGain and voice.addBranchGain:getGain() or 0.0,
        sampleAdditiveGain = voice.sampleAdditiveGain and voice.sampleAdditiveGain:getGain() or 0.0,
        addPhraseGain = voice.addPhraseGain and voice.addPhraseGain:getGain() or 0.0,
        branchGain1 = voice.branchMixer and voice.branchMixer:getGain(1) or -1,
        branchGain2 = voice.branchMixer and voice.branchMixer:getGain(2) or -1,
        branchGain3 = voice.branchMixer and voice.branchMixer:getGain(3) or -1,
        waveform = voice.waveform or -1,
        waveFrequency = voice.freq or 0.0,
        sampleNodeEnabled = sampleNode and sampleNode.isEnabled and sampleNode:isEnabled() or false,
        sampleNodeAmplitude = sampleNode and sampleNode.getAmplitude and sampleNode:getAmplitude() or 0.0,
        sampleNodeFrequency = sampleNode and sampleNode.getFrequency and sampleNode:getFrequency() or 0.0,
        sampleNodeActivePartials = sampleNode and sampleNode.getActivePartialCount and sampleNode:getActivePartialCount() or 0,
        sampleNodeReferenceFundamental = sampleNode and sampleNode.getReferenceFundamental and sampleNode:getReferenceFundamental() or 0.0,
        sampleNodeSpectralMode = sampleNode and sampleNode.getSpectralMode and sampleNode:getSpectralMode() or -1,
        blendOscEnabled = blendOscNode and blendOscNode.isEnabled and blendOscNode:isEnabled() or false,
        blendOscAmplitude = blendOscNode and blendOscNode.getAmplitude and blendOscNode:getAmplitude() or 0.0,
        blendOscFrequency = blendOscNode and blendOscNode.getFrequency and blendOscNode:getFrequency() or 0.0,
        blendOscRenderMode = blendOscNode and blendOscNode.getRenderMode and blendOscNode:getRenderMode() or -1,
        envFollowAmount = envFollowAmount,
        envFollowValue = voice.sampleEnvFollower and voice.sampleEnvFollower:getEnvelope() or 0.0,
      }
    end,

    -- Expose write offset for free mode capture
    getCaptureWriteOffset = function()
      local entry = selectedSampleSourceEntry()
      local capture = entry and entry.capture and entry.capture.__node
      if capture then
        local offset = capture:getWriteOffset()
        return offset
      end
      return 0
    end,

    -- Get last captured sample length in milliseconds
    getLastCapturedLengthMs = function()
      return lastCapturedLengthMs
    end,

    getRackAudioRouteDebug = function()
      return rackAudioRouter.getDebugState()
    end,

    ensureDynamicModuleSlot = ensureDynamicModuleSlot,

    getBlendDebug = function(voiceIndex)
      local idx = math.max(1, math.min(VOICE_COUNT, tonumber(voiceIndex) or 1))
      local voice = voicePool.voices[idx]
      if not voice then return "no voice" end
      local branchG1 = voice.branchMixer and voice.branchMixer:getGain(1) or -1
      local branchG2 = voice.branchMixer and voice.branchMixer:getGain(2) or -1
      local branchG3 = voice.branchMixer and voice.branchMixer:getGain(3) or -1
      local mixPos = voice.mixCrossfade and voice.mixCrossfade:getPosition() or -9
      local dirPos = voice.directionCrossfade and voice.directionCrossfade:getPosition() or -9
      local ringPos = voice.ringCrossfade and voice.ringCrossfade:getPosition() or -9
      local addPos = voice.addCrossfade and voice.addCrossfade:getPosition() or -9
      local addGain = voice.addBranchGain and voice.addBranchGain:getGain() or 0
      local baseSel = voice.basePathSelect and voice.basePathSelect:getPosition() or -9
      local samplePos = voice.samplePlayback and voice.samplePlayback:getNormalizedPosition() or 0
      local oscNode = voice.osc and voice.osc.__node or nil
      local oscAmp = oscNode and oscNode.getAmplitude and oscNode:getAmplitude() or 0.0
      local oscRender = oscNode and oscNode.getRenderMode and oscNode:getRenderMode() or renderMode
      return string.format(
        "render=%d mode=%d blend=%.3f depth=%.3f wg=%.3f sg=%.3f addActive=%s branch=[%.1f %.1f %.1f] xfade=[mix %.2f dir %.2f ring %.2f add %.2f base %.2f] addGain=%.2f oscFreq=%.2f oscAmp=%.3f sampleSpeed=%.3f samplePos=%.3f",
        oscRender, blendMode, blendAmount, blendModAmount, waveToSample, sampleToWave,
        tostring(blendMode == 4 or blendMode == 5),
        branchG1, branchG2, branchG3,
        mixPos, dirPos, ringPos, addPos, baseSel,
        addGain,
        voice.lastBlendOscFreq or 0.0,
        oscAmp,
        voice.lastBlendSampleSpeed or 0.0,
        samplePos)
    end,
  }
end

return M

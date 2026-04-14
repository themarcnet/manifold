-- Parameter binder/schema helpers for MidiSynth-style DSP modules.
-- Extracted from midisynth_integration.lua to make parameter metadata reusable
-- across registration, automation, presets, palette/export, and future modules.

local ParameterBinder = {}
local RackAudioRouter = require("rack_audio_router")

local DYNAMIC_SLOT_CAPS = {
  adsr = 128,
  arp = 128,
  transpose = 128,
  velocity_mapper = 128,
  scale_quantizer = 128,
  note_filter = 128,
  attenuverter_bias = 128,
  range_mapper = 128,
  lfo = 128,
  slew = 128,
  sample_hold = 128,
  compare = 128,
  cv_mix = 128,
  eq = 32,
  fx = 32,
  filter = 32,
  rack_oscillator = 32,
  rack_sample = 32,
  blend_simple = 32,
}

local MAX_RACK_AUDIO_STAGES = 128
local MAX_RACK_AUDIO_SOURCES = 33
local AUX_AUDIO_SOURCE_CODES = {
  NONE = 0,
  OSCILLATOR = 1,
  FILTER = 2,
  FX1 = 3,
  FX2 = 4,
  EQ = 5,
  DYNAMIC_OSC_BASE = 100,
  DYNAMIC_SAMPLE_BASE = 200,
  DYNAMIC_BLEND_SIMPLE_BASE = 300,
  DYNAMIC_FILTER_BASE = 400,
  DYNAMIC_FX_BASE = 500,
  DYNAMIC_EQ_BASE = 600,
}

local PATHS = {
  waveform = "/midi/synth/waveform",
  cutoff = "/midi/synth/cutoff",
  resonance = "/midi/synth/resonance",
  drive = "/midi/synth/drive",
  driveShape = "/midi/synth/driveShape",
  driveBias = "/midi/synth/driveBias",
  filterType = "/midi/synth/filterType",
  fx1Type = "/midi/synth/fx1/type",
  fx1Mix = "/midi/synth/fx1/mix",
  fx2Type = "/midi/synth/fx2/type",
  fx2Mix = "/midi/synth/fx2/mix",
  eqOutput = "/midi/synth/eq8/output",
  eqMix = "/midi/synth/eq8/mix",
  output = "/midi/synth/output",
  attack = "/midi/synth/adsr/attack",
  decay = "/midi/synth/adsr/decay",
  sustain = "/midi/synth/adsr/sustain",
  release = "/midi/synth/adsr/release",
  noiseLevel = "/midi/synth/noise/level",
  noiseColor = "/midi/synth/noise/color",
  pulseWidth = "/midi/synth/pulseWidth",
  unison = "/midi/synth/unison",
  detune = "/midi/synth/detune",
  spread = "/midi/synth/spread",
  oscRenderMode = "/midi/synth/osc/renderMode",
  additivePartials = "/midi/synth/osc/add/partials",
  additiveTilt = "/midi/synth/osc/add/tilt",
  additiveDrift = "/midi/synth/osc/add/drift",
  oscMode = "/midi/synth/osc/mode",
  sampleSource = "/midi/synth/sample/source",
  sampleCaptureTrigger = "/midi/synth/sample/captureTrigger",
  sampleCaptureBars = "/midi/synth/sample/captureBars",
  sampleCaptureMode = "/midi/synth/sample/captureMode",
  sampleCaptureWriteOffset = "/midi/synth/sample/captureWriteOffset",
  sampleCaptureStartOffset = "/midi/synth/sample/captureStartOffset",
  sampleCapturedLengthMs = "/midi/synth/sample/capturedLengthMs",
  sampleCaptureRecording = "/midi/synth/sample/captureRecording",
  samplePitchMapEnabled = "/midi/synth/sample/pitchMapEnabled",
  samplePitchMode = "/midi/synth/sample/pitchMode",
  samplePvocFFTOrder = "/midi/synth/sample/pvoc/fftOrder",
  samplePvocTimeStretch = "/midi/synth/sample/pvoc/timeStretch",
  sampleRootNote = "/midi/synth/sample/rootNote",
  samplePlayStart = "/midi/synth/sample/playStart",
  sampleLoopStart = "/midi/synth/sample/loopStart",
  sampleLoopLen = "/midi/synth/sample/loopLen",
  sampleCrossfade = "/midi/synth/sample/crossfade",
  sampleRetrigger = "/midi/synth/sample/retrigger",
  sampleAdditiveEnabled = "/midi/synth/debug/sampleAdditive/enabled",
  sampleAdditiveMix = "/midi/synth/debug/sampleAdditive/mix",
  blendMode = "/midi/synth/blend/mode",
  blendAmount = "/midi/synth/blend/amount",
  waveToSample = "/midi/synth/blend/waveToSample",
  sampleToWave = "/midi/synth/blend/sampleToWave",
  blendKeyTrack = "/midi/synth/blend/keyTrack",
  blendSamplePitch = "/midi/synth/blend/samplePitch",
  blendModAmount = "/midi/synth/blend/modAmount",
  addFlavor = "/midi/synth/blend/addFlavor",
  xorBehavior = "/midi/synth/blend/xorBehavior",
  morphCurve = "/midi/synth/blend/morphCurve",
  morphConvergence = "/midi/synth/blend/morphConvergence",
  morphPhase = "/midi/synth/blend/morphPhase",
  morphSpeed = "/midi/synth/blend/morphSpeed",
  morphContrast = "/midi/synth/blend/morphContrast",
  morphSmooth = "/midi/synth/blend/morphSmooth",
  envFollowAmount = "/midi/synth/blend/envFollow",
  rackAudioEdgeMask = "/midi/synth/rack/audio/edgeMask",
  rackAudioStageCount = "/midi/synth/rack/stageCount",
  rackAudioOutputEnabled = "/midi/synth/rack/outputEnabled",
  rackAudioSourceCount = "/midi/synth/rack/sourceCount",
  rackRegistryRequestKind = "/midi/synth/rack/registry/requestKind",
  rackRegistryRequestIndex = "/midi/synth/rack/registry/requestIndex",
  rackRegistryRequestNonce = "/midi/synth/rack/registry/requestNonce",
}

ParameterBinder.PATHS = PATHS
ParameterBinder.MAX_FX_PARAMS = 5
ParameterBinder.MAX_RACK_AUDIO_STAGES = MAX_RACK_AUDIO_STAGES
ParameterBinder.MAX_RACK_AUDIO_SOURCES = MAX_RACK_AUDIO_SOURCES
ParameterBinder.DYNAMIC_SLOT_CAPS = DYNAMIC_SLOT_CAPS
ParameterBinder.AUX_AUDIO_SOURCE_CODES = AUX_AUDIO_SOURCE_CODES

function ParameterBinder.dynamicSlotCapacity(specId)
  return math.max(0, math.floor(tonumber(DYNAMIC_SLOT_CAPS[tostring(specId or "")]) or 0))
end

ParameterBinder.ADSR_DEFAULTS = {
  attack = 0.05,
  decay = 0.2,
  sustain = 0.7,
  release = 0.4,
}

local EQ8_DEFAULT_FREQS = { 60, 120, 250, 500, 1000, 2500, 6000, 12000 }

local function copyTable(src)
  local out = {}
  for key, value in pairs(src or {}) do
    out[key] = value
  end
  return out
end

local function appendSchema(schema, path, spec, bind)
  schema[#schema + 1] = {
    path = path,
    spec = copyTable(spec),
    bind = bind,
  }
end

local function cloneArray(values)
  local out = {}
  for i = 1, #(values or {}) do
    out[i] = values[i]
  end
  return out
end

local function schemaByPath(schema)
  local out = {}
  for i = 1, #(schema or {}) do
    local entry = schema[i]
    out[entry.path] = entry
  end
  return out
end

function ParameterBinder.voiceFreqPath(index)
  return string.format("/midi/synth/voice/%d/freq", index)
end

function ParameterBinder.voiceAmpPath(index)
  return string.format("/midi/synth/voice/%d/amp", index)
end

function ParameterBinder.voiceGatePath(index)
  return string.format("/midi/synth/voice/%d/gate", index)
end

function ParameterBinder.eq8BandEnabledPath(index)
  return string.format("/midi/synth/eq8/band/%d/enabled", index)
end

function ParameterBinder.eq8BandTypePath(index)
  return string.format("/midi/synth/eq8/band/%d/type", index)
end

function ParameterBinder.eq8BandFreqPath(index)
  return string.format("/midi/synth/eq8/band/%d/freq", index)
end

function ParameterBinder.eq8BandGainPath(index)
  return string.format("/midi/synth/eq8/band/%d/gain", index)
end

function ParameterBinder.eq8BandQPath(index)
  return string.format("/midi/synth/eq8/band/%d/q", index)
end

function ParameterBinder.rackAudioStagePath(index)
  return string.format("/midi/synth/rack/stage/%d", math.max(1, math.floor(tonumber(index) or 1)))
end

function ParameterBinder.rackAudioSourcePath(index)
  return string.format("/midi/synth/rack/source/%d", math.max(1, math.floor(tonumber(index) or 1)))
end

function ParameterBinder.dynamicEqBasePath(slotIndex)
  return string.format("/midi/synth/rack/eq/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicEqMixPath(slotIndex)
  return ParameterBinder.dynamicEqBasePath(slotIndex) .. "/mix"
end

function ParameterBinder.dynamicEqOutputPath(slotIndex)
  return ParameterBinder.dynamicEqBasePath(slotIndex) .. "/output"
end

function ParameterBinder.dynamicEqBandEnabledPath(slotIndex, bandIndex)
  return string.format("%s/band/%d/enabled", ParameterBinder.dynamicEqBasePath(slotIndex), math.max(1, math.floor(tonumber(bandIndex) or 1)))
end

function ParameterBinder.dynamicEqBandTypePath(slotIndex, bandIndex)
  return string.format("%s/band/%d/type", ParameterBinder.dynamicEqBasePath(slotIndex), math.max(1, math.floor(tonumber(bandIndex) or 1)))
end

function ParameterBinder.dynamicEqBandFreqPath(slotIndex, bandIndex)
  return string.format("%s/band/%d/freq", ParameterBinder.dynamicEqBasePath(slotIndex), math.max(1, math.floor(tonumber(bandIndex) or 1)))
end

function ParameterBinder.dynamicEqBandGainPath(slotIndex, bandIndex)
  return string.format("%s/band/%d/gain", ParameterBinder.dynamicEqBasePath(slotIndex), math.max(1, math.floor(tonumber(bandIndex) or 1)))
end

function ParameterBinder.dynamicEqBandQPath(slotIndex, bandIndex)
  return string.format("%s/band/%d/q", ParameterBinder.dynamicEqBasePath(slotIndex), math.max(1, math.floor(tonumber(bandIndex) or 1)))
end

function ParameterBinder.dynamicFxBasePath(slotIndex)
  return string.format("/midi/synth/rack/fx/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicAdsrBasePath(slotIndex)
  return string.format("/midi/synth/rack/adsr/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicAdsrAttackPath(slotIndex)
  return ParameterBinder.dynamicAdsrBasePath(slotIndex) .. "/attack"
end

function ParameterBinder.dynamicAdsrDecayPath(slotIndex)
  return ParameterBinder.dynamicAdsrBasePath(slotIndex) .. "/decay"
end

function ParameterBinder.dynamicAdsrSustainPath(slotIndex)
  return ParameterBinder.dynamicAdsrBasePath(slotIndex) .. "/sustain"
end

function ParameterBinder.dynamicAdsrReleasePath(slotIndex)
  return ParameterBinder.dynamicAdsrBasePath(slotIndex) .. "/release"
end

function ParameterBinder.dynamicArpBasePath(slotIndex)
  return string.format("/midi/synth/rack/arp/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicArpRatePath(slotIndex)
  return ParameterBinder.dynamicArpBasePath(slotIndex) .. "/rate"
end

function ParameterBinder.dynamicArpModePath(slotIndex)
  return ParameterBinder.dynamicArpBasePath(slotIndex) .. "/mode"
end

function ParameterBinder.dynamicArpOctavesPath(slotIndex)
  return ParameterBinder.dynamicArpBasePath(slotIndex) .. "/octaves"
end

function ParameterBinder.dynamicArpGateLengthPath(slotIndex)
  return ParameterBinder.dynamicArpBasePath(slotIndex) .. "/gate"
end

function ParameterBinder.dynamicArpHoldPath(slotIndex)
  return ParameterBinder.dynamicArpBasePath(slotIndex) .. "/hold"
end

function ParameterBinder.dynamicTransposeBasePath(slotIndex)
  return string.format("/midi/synth/rack/transpose/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicTransposeSemitonesPath(slotIndex)
  return ParameterBinder.dynamicTransposeBasePath(slotIndex) .. "/semitones"
end

function ParameterBinder.dynamicVelocityMapperBasePath(slotIndex)
  return string.format("/midi/synth/rack/velocity_mapper/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicVelocityMapperAmountPath(slotIndex)
  return ParameterBinder.dynamicVelocityMapperBasePath(slotIndex) .. "/amount"
end

function ParameterBinder.dynamicVelocityMapperCurvePath(slotIndex)
  return ParameterBinder.dynamicVelocityMapperBasePath(slotIndex) .. "/curve"
end

function ParameterBinder.dynamicVelocityMapperOffsetPath(slotIndex)
  return ParameterBinder.dynamicVelocityMapperBasePath(slotIndex) .. "/offset"
end

function ParameterBinder.dynamicScaleQuantizerBasePath(slotIndex)
  return string.format("/midi/synth/rack/scale_quantizer/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicScaleQuantizerRootPath(slotIndex)
  return ParameterBinder.dynamicScaleQuantizerBasePath(slotIndex) .. "/root"
end

function ParameterBinder.dynamicScaleQuantizerScalePath(slotIndex)
  return ParameterBinder.dynamicScaleQuantizerBasePath(slotIndex) .. "/scale"
end

function ParameterBinder.dynamicScaleQuantizerDirectionPath(slotIndex)
  return ParameterBinder.dynamicScaleQuantizerBasePath(slotIndex) .. "/direction"
end

function ParameterBinder.dynamicNoteFilterBasePath(slotIndex)
  return string.format("/midi/synth/rack/note_filter/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicNoteFilterLowPath(slotIndex)
  return ParameterBinder.dynamicNoteFilterBasePath(slotIndex) .. "/low"
end

function ParameterBinder.dynamicNoteFilterHighPath(slotIndex)
  return ParameterBinder.dynamicNoteFilterBasePath(slotIndex) .. "/high"
end

function ParameterBinder.dynamicNoteFilterModePath(slotIndex)
  return ParameterBinder.dynamicNoteFilterBasePath(slotIndex) .. "/mode"
end

function ParameterBinder.dynamicAttenuverterBiasBasePath(slotIndex)
  return string.format("/midi/synth/rack/attenuverter_bias/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicAttenuverterBiasAmountPath(slotIndex)
  return ParameterBinder.dynamicAttenuverterBiasBasePath(slotIndex) .. "/amount"
end

function ParameterBinder.dynamicAttenuverterBiasBiasPath(slotIndex)
  return ParameterBinder.dynamicAttenuverterBiasBasePath(slotIndex) .. "/bias"
end

function ParameterBinder.dynamicRangeMapperBasePath(slotIndex)
  return string.format("/midi/synth/rack/range_mapper/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicRangeMapperMinPath(slotIndex)
  return ParameterBinder.dynamicRangeMapperBasePath(slotIndex) .. "/min"
end

function ParameterBinder.dynamicRangeMapperMaxPath(slotIndex)
  return ParameterBinder.dynamicRangeMapperBasePath(slotIndex) .. "/max"
end

function ParameterBinder.dynamicRangeMapperModePath(slotIndex)
  return ParameterBinder.dynamicRangeMapperBasePath(slotIndex) .. "/mode"
end

function ParameterBinder.dynamicLfoBasePath(slotIndex)
  return string.format("/midi/synth/rack/lfo/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicLfoRatePath(slotIndex)
  return ParameterBinder.dynamicLfoBasePath(slotIndex) .. "/rate"
end

function ParameterBinder.dynamicLfoShapePath(slotIndex)
  return ParameterBinder.dynamicLfoBasePath(slotIndex) .. "/shape"
end

function ParameterBinder.dynamicLfoDepthPath(slotIndex)
  return ParameterBinder.dynamicLfoBasePath(slotIndex) .. "/depth"
end

function ParameterBinder.dynamicLfoPhasePath(slotIndex)
  return ParameterBinder.dynamicLfoBasePath(slotIndex) .. "/phase"
end

function ParameterBinder.dynamicLfoRetrigPath(slotIndex)
  return ParameterBinder.dynamicLfoBasePath(slotIndex) .. "/retrig"
end

function ParameterBinder.dynamicSlewBasePath(slotIndex)
  return string.format("/midi/synth/rack/slew/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicSlewRisePath(slotIndex)
  return ParameterBinder.dynamicSlewBasePath(slotIndex) .. "/rise"
end

function ParameterBinder.dynamicSlewFallPath(slotIndex)
  return ParameterBinder.dynamicSlewBasePath(slotIndex) .. "/fall"
end

function ParameterBinder.dynamicSlewShapePath(slotIndex)
  return ParameterBinder.dynamicSlewBasePath(slotIndex) .. "/shape"
end

function ParameterBinder.dynamicSampleHoldBasePath(slotIndex)
  return string.format("/midi/synth/rack/sample_hold/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicSampleHoldModePath(slotIndex)
  return ParameterBinder.dynamicSampleHoldBasePath(slotIndex) .. "/mode"
end

function ParameterBinder.dynamicCompareBasePath(slotIndex)
  return string.format("/midi/synth/rack/compare/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicCompareThresholdPath(slotIndex)
  return ParameterBinder.dynamicCompareBasePath(slotIndex) .. "/threshold"
end

function ParameterBinder.dynamicCompareHysteresisPath(slotIndex)
  return ParameterBinder.dynamicCompareBasePath(slotIndex) .. "/hysteresis"
end

function ParameterBinder.dynamicCompareDirectionPath(slotIndex)
  return ParameterBinder.dynamicCompareBasePath(slotIndex) .. "/direction"
end

function ParameterBinder.dynamicCvMixBasePath(slotIndex)
  return string.format("/midi/synth/rack/cv_mix/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicCvMixLevelPath(slotIndex, inputIndex)
  return string.format("%s/level_%d", ParameterBinder.dynamicCvMixBasePath(slotIndex), math.max(1, math.floor(tonumber(inputIndex) or 1)))
end

function ParameterBinder.dynamicCvMixOffsetPath(slotIndex)
  return ParameterBinder.dynamicCvMixBasePath(slotIndex) .. "/offset"
end

function ParameterBinder.dynamicOscillatorBasePath(slotIndex)
  return string.format("/midi/synth/rack/osc/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicOscillatorWaveformPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/waveform"
end

function ParameterBinder.dynamicOscillatorRenderModePath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/renderMode"
end

function ParameterBinder.dynamicOscillatorAdditivePartialsPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/additivePartials"
end

function ParameterBinder.dynamicOscillatorAdditiveTiltPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/additiveTilt"
end

function ParameterBinder.dynamicOscillatorAdditiveDriftPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/additiveDrift"
end

function ParameterBinder.dynamicOscillatorDrivePath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/drive"
end

function ParameterBinder.dynamicOscillatorDriveShapePath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/driveShape"
end

function ParameterBinder.dynamicOscillatorDriveBiasPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/driveBias"
end

function ParameterBinder.dynamicOscillatorPulseWidthPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/pulseWidth"
end

function ParameterBinder.dynamicOscillatorUnisonPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/unison"
end

function ParameterBinder.dynamicOscillatorDetunePath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/detune"
end

function ParameterBinder.dynamicOscillatorSpreadPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/spread"
end

function ParameterBinder.dynamicOscillatorOutputPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/output"
end

function ParameterBinder.dynamicOscillatorManualPitchPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/manualPitch"
end

function ParameterBinder.dynamicOscillatorManualLevelPath(slotIndex)
  return ParameterBinder.dynamicOscillatorBasePath(slotIndex) .. "/manualLevel"
end

function ParameterBinder.dynamicOscillatorVoiceGatePath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/gate", ParameterBinder.dynamicOscillatorBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicOscillatorVoiceVOctPath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/vOct", ParameterBinder.dynamicOscillatorBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicOscillatorVoiceFmPath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/fm", ParameterBinder.dynamicOscillatorBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicOscillatorVoicePwCvPath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/pwCv", ParameterBinder.dynamicOscillatorBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicSampleBasePath(slotIndex)
  return string.format("/midi/synth/rack/sample/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicSampleSourcePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/source"
end

function ParameterBinder.dynamicSampleCaptureTriggerPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureTrigger"
end

function ParameterBinder.dynamicSampleCaptureBarsPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureBars"
end

function ParameterBinder.dynamicSampleCaptureModePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureMode"
end

function ParameterBinder.dynamicSampleCaptureStartOffsetPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureStartOffset"
end

function ParameterBinder.dynamicSampleCapturedLengthMsPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/capturedLengthMs"
end

function ParameterBinder.dynamicSampleCaptureRecordingPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureRecording"
end

function ParameterBinder.dynamicSampleCaptureWriteOffsetPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/captureWriteOffset"
end

function ParameterBinder.dynamicSamplePitchMapEnabledPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/pitchMapEnabled"
end

function ParameterBinder.dynamicSamplePitchModePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/pitchMode"
end

function ParameterBinder.dynamicSamplePvocFFTOrderPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/pvoc/fftOrder"
end

function ParameterBinder.dynamicSamplePvocTimeStretchPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/pvoc/timeStretch"
end

function ParameterBinder.dynamicSampleRootNotePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/rootNote"
end

function ParameterBinder.dynamicSampleUnisonPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/unison"
end

function ParameterBinder.dynamicSampleDetunePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/detune"
end

function ParameterBinder.dynamicSampleSpreadPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/spread"
end

function ParameterBinder.dynamicSamplePlayStartPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/playStart"
end

function ParameterBinder.dynamicSampleLoopStartPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/loopStart"
end

function ParameterBinder.dynamicSampleLoopLenPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/loopLen"
end

function ParameterBinder.dynamicSampleCrossfadePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/crossfade"
end

function ParameterBinder.dynamicSampleRetriggerPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/retrigger"
end

function ParameterBinder.dynamicSampleOutputPath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/output"
end

function ParameterBinder.dynamicSampleInputSourcePath(slotIndex)
  return ParameterBinder.dynamicSampleBasePath(slotIndex) .. "/inputSource"
end

function ParameterBinder.dynamicSampleVoiceGatePath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/gate", ParameterBinder.dynamicSampleBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicSampleVoiceVOctPath(slotIndex, voiceIndex)
  return string.format("%s/voice/%d/vOct", ParameterBinder.dynamicSampleBasePath(slotIndex), math.max(1, math.floor(tonumber(voiceIndex) or 1)))
end

function ParameterBinder.dynamicBlendSimpleBasePath(slotIndex)
  return string.format("/midi/synth/rack/blend_simple/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicBlendSimpleModePath(slotIndex)
  return ParameterBinder.dynamicBlendSimpleBasePath(slotIndex) .. "/mode"
end

function ParameterBinder.dynamicBlendSimpleBlendAmountPath(slotIndex)
  return ParameterBinder.dynamicBlendSimpleBasePath(slotIndex) .. "/blendAmount"
end

function ParameterBinder.dynamicBlendSimpleBlendModAmountPath(slotIndex)
  return ParameterBinder.dynamicBlendSimpleBasePath(slotIndex) .. "/blendModAmount"
end

function ParameterBinder.dynamicBlendSimpleOutputPath(slotIndex)
  return ParameterBinder.dynamicBlendSimpleBasePath(slotIndex) .. "/output"
end

function ParameterBinder.dynamicBlendSimpleBSourcePath(slotIndex)
  return ParameterBinder.dynamicBlendSimpleBasePath(slotIndex) .. "/bSource"
end

function ParameterBinder.dynamicFilterBasePath(slotIndex)
  return string.format("/midi/synth/rack/filter/%d", math.max(1, math.floor(tonumber(slotIndex) or 1)))
end

function ParameterBinder.dynamicFilterTypePath(slotIndex)
  return ParameterBinder.dynamicFilterBasePath(slotIndex) .. "/type"
end

function ParameterBinder.dynamicFilterCutoffPath(slotIndex)
  return ParameterBinder.dynamicFilterBasePath(slotIndex) .. "/cutoff"
end

function ParameterBinder.dynamicFilterResonancePath(slotIndex)
  return ParameterBinder.dynamicFilterBasePath(slotIndex) .. "/resonance"
end

function ParameterBinder.dynamicFxTypePath(slotIndex)
  return ParameterBinder.dynamicFxBasePath(slotIndex) .. "/type"
end

function ParameterBinder.dynamicFxMixPath(slotIndex)
  return ParameterBinder.dynamicFxBasePath(slotIndex) .. "/mix"
end

function ParameterBinder.dynamicFxParamPath(slotIndex, index)
  return string.format("%s/p/%d", ParameterBinder.dynamicFxBasePath(slotIndex), math.max(0, math.floor(tonumber(index) or 0)))
end

function ParameterBinder.fxParamPath(slotName, index)
  return string.format("/midi/synth/%s/p/%d", tostring(slotName), tonumber(index) or 0)
end

function ParameterBinder.matchFxParamPath(path)
  local slotName, index = tostring(path or ""):match("^/midi/synth/(fx[12])/p/(%d+)$")
  if slotName == nil then
    return nil
  end
  return slotName, tonumber(index)
end

function ParameterBinder.isEq8Path(path)
  if path == PATHS.eqOutput or path == PATHS.eqMix then
    return true
  end
  return tostring(path or ""):match("^/midi/synth/eq8/") ~= nil
end

function ParameterBinder.matchDynamicEqPath(path)
  local normalized = tostring(path or "")
  local slotIndex, bandIndex, suffix = normalized:match("^/midi/synth/rack/eq/(%d+)/band/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), tonumber(bandIndex), suffix
  end
  slotIndex, suffix = normalized:match("^/midi/synth/rack/eq/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), nil, suffix
  end
  return nil
end

function ParameterBinder.matchDynamicFxPath(path)
  local normalized = tostring(path or "")
  local slotIndex, paramIndex = normalized:match("^/midi/synth/rack/fx/(%d+)/p/(%d+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "param", tonumber(paramIndex)
  end
  slotIndex = normalized:match("^/midi/synth/rack/fx/(%d+)/type$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "type", nil
  end
  slotIndex = normalized:match("^/midi/synth/rack/fx/(%d+)/mix$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "mix", nil
  end
  return nil
end

function ParameterBinder.matchDynamicAdsrPath(path)
  local normalized = tostring(path or "")
  local slotIndex, suffix = normalized:match("^/midi/synth/rack/adsr/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), suffix
  end
  return nil
end

function ParameterBinder.matchDynamicArpPath(path)
  local normalized = tostring(path or "")
  local slotIndex, suffix = normalized:match("^/midi/synth/rack/arp/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), suffix
  end
  return nil
end

function ParameterBinder.matchDynamicFilterPath(path)
  local normalized = tostring(path or "")
  local slotIndex = normalized:match("^/midi/synth/rack/filter/(%d+)/type$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "type"
  end
  slotIndex = normalized:match("^/midi/synth/rack/filter/(%d+)/cutoff$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "cutoff"
  end
  slotIndex = normalized:match("^/midi/synth/rack/filter/(%d+)/resonance$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "resonance"
  end
  return nil
end

function ParameterBinder.matchDynamicOscillatorPath(path)
  local normalized = tostring(path or "")
  local slotIndex, suffix = normalized:match("^/midi/synth/rack/osc/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), suffix
  end
  return nil
end

function ParameterBinder.matchDynamicOscillatorVoicePath(path)
  local normalized = tostring(path or "")
  local slotIndex, voiceIndex, suffix = normalized:match("^/midi/synth/rack/osc/(%d+)/voice/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), tonumber(voiceIndex), suffix
  end
  return nil
end

function ParameterBinder.matchDynamicSamplePath(path)
  local normalized = tostring(path or "")
  local slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/source$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "source"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureTrigger$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureTrigger"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureBars$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureBars"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureMode$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureMode"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureStartOffset$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureStartOffset"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/capturedLengthMs$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "capturedLengthMs"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureRecording$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureRecording"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/captureWriteOffset$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "captureWriteOffset"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/pitchMapEnabled$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "pitchMapEnabled"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/pitchMode$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "pitchMode"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/pvoc/fftOrder$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "pvocFFTOrder"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/pvoc/timeStretch$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "pvocTimeStretch"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/rootNote$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "rootNote"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/unison$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "unison"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/detune$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "detune"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/spread$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "spread"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/playStart$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "playStart"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/loopStart$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "loopStart"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/loopLen$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "loopLen"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/crossfade$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "crossfade"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/retrigger$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "retrigger"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/output$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "output"
  end
  slotIndex = normalized:match("^/midi/synth/rack/sample/(%d+)/inputSource$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "inputSource"
  end
  return nil
end

function ParameterBinder.matchDynamicSampleVoicePath(path)
  local normalized = tostring(path or "")
  local slotIndex, voiceIndex, suffix = normalized:match("^/midi/synth/rack/sample/(%d+)/voice/(%d+)/([%a_]+)$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), tonumber(voiceIndex), suffix
  end
  return nil
end

function ParameterBinder.matchDynamicBlendSimplePath(path)
  local normalized = tostring(path or "")
  local slotIndex = normalized:match("^/midi/synth/rack/blend_simple/(%d+)/mode$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "mode"
  end
  slotIndex = normalized:match("^/midi/synth/rack/blend_simple/(%d+)/blendAmount$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "blendAmount"
  end
  slotIndex = normalized:match("^/midi/synth/rack/blend_simple/(%d+)/blendModAmount$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "blendModAmount"
  end
  slotIndex = normalized:match("^/midi/synth/rack/blend_simple/(%d+)/output$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "output"
  end
  slotIndex = normalized:match("^/midi/synth/rack/blend_simple/(%d+)/bSource$")
  if slotIndex ~= nil then
    return tonumber(slotIndex), "bSource"
  end
  return nil
end

function ParameterBinder.specIdForRegistryRequestKind(kind)
  local k = math.max(0, math.floor(tonumber(kind) or 0))
  local mapping = {
    [0] = "eq",
    [1] = "fx",
    [2] = "filter",
    [3] = "rack_oscillator",
    [4] = "rack_sample",
    [5] = "adsr",
    [6] = "arp",
    [7] = "transpose",
    [8] = "velocity_mapper",
    [9] = "scale_quantizer",
    [10] = "note_filter",
    [11] = "attenuverter_bias",
    [12] = "range_mapper",
    [13] = "lfo",
    [14] = "slew",
    [15] = "sample_hold",
    [16] = "compare",
    [17] = "cv_mix",
    [18] = "blend_simple",
    [19] = "rack_audio_stage",
    [20] = "rack_audio_source",
  }
  return mapping[k]
end

function ParameterBinder.matchDynamicModulePath(path)
  local normalized = tostring(path or "")
  local patterns = {
    { specId = "adsr", pattern = "^/midi/synth/rack/adsr/(%d+)/" },
    { specId = "arp", pattern = "^/midi/synth/rack/arp/(%d+)/" },
    { specId = "transpose", pattern = "^/midi/synth/rack/transpose/(%d+)/" },
    { specId = "velocity_mapper", pattern = "^/midi/synth/rack/velocity_mapper/(%d+)/" },
    { specId = "scale_quantizer", pattern = "^/midi/synth/rack/scale_quantizer/(%d+)/" },
    { specId = "note_filter", pattern = "^/midi/synth/rack/note_filter/(%d+)/" },
    { specId = "attenuverter_bias", pattern = "^/midi/synth/rack/attenuverter_bias/(%d+)/" },
    { specId = "range_mapper", pattern = "^/midi/synth/rack/range_mapper/(%d+)/" },
    { specId = "lfo", pattern = "^/midi/synth/rack/lfo/(%d+)/" },
    { specId = "slew", pattern = "^/midi/synth/rack/slew/(%d+)/" },
    { specId = "sample_hold", pattern = "^/midi/synth/rack/sample_hold/(%d+)/" },
    { specId = "compare", pattern = "^/midi/synth/rack/compare/(%d+)/" },
    { specId = "cv_mix", pattern = "^/midi/synth/rack/cv_mix/(%d+)/" },
    { specId = "eq", pattern = "^/midi/synth/rack/eq/(%d+)/" },
    { specId = "fx", pattern = "^/midi/synth/rack/fx/(%d+)/" },
    { specId = "filter", pattern = "^/midi/synth/rack/filter/(%d+)/" },
    { specId = "rack_oscillator", pattern = "^/midi/synth/rack/osc/(%d+)/" },
    { specId = "rack_sample", pattern = "^/midi/synth/rack/sample/(%d+)/" },
    { specId = "blend_simple", pattern = "^/midi/synth/rack/blend_simple/(%d+)/" },
  }

  for i = 1, #patterns do
    local entry = patterns[i]
    local slotIndex = normalized:match(entry.pattern)
    if slotIndex ~= nil then
      return entry.specId, math.max(1, math.floor(tonumber(slotIndex) or 1))
    end
  end

  return nil
end

function ParameterBinder.matchRackAudioStagePath(path)
  local index = tostring(path or ""):match("^/midi/synth/rack/stage/(%d+)$")
  if index ~= nil then
    return math.max(1, math.floor(tonumber(index) or 1))
  end
  return nil
end

function ParameterBinder.matchRackAudioSourcePath(path)
  local index = tostring(path or ""):match("^/midi/synth/rack/source/(%d+)$")
  if index ~= nil then
    return math.max(1, math.floor(tonumber(index) or 1))
  end
  return nil
end

local function dynamicSlotCount(options, specId)
  local counts = type(options) == "table" and type(options.dynamicSlotCounts) == "table" and options.dynamicSlotCounts or nil
  if type(counts) == "table" and counts[tostring(specId or "")] ~= nil then
    return math.max(0, math.floor(tonumber(counts[tostring(specId or "")]) or 0))
  end
  return ParameterBinder.dynamicSlotCapacity(specId)
end

local function appendDynamicSlotSchema(schema, specId, slotIndex, options)
  local id = tostring(specId or "")
  local index = math.max(1, math.floor(tonumber(slotIndex) or 1))
  local voiceCount = math.max(1, math.floor(tonumber(options and options.voiceCount) or 8))
  local fxOptionCount = math.max(1, math.floor(tonumber(options and options.fxOptionCount) or 1))
  local maxFxParams = math.max(1, math.floor(tonumber(options and options.maxFxParams) or ParameterBinder.MAX_FX_PARAMS))
  local fxParamDefaults = type(options) == "table" and type(options.fxParamDefaults) == "table" and options.fxParamDefaults or nil
  local oscRenderStandard = tonumber(options and options.oscRenderStandard) or 0

  if id == "adsr" then
    appendSchema(schema, ParameterBinder.dynamicAdsrAttackPath(index), { type = "f", min = 0.001, max = 5, default = 0.05, description = "Dynamic ADSR " .. index .. " attack" })
    appendSchema(schema, ParameterBinder.dynamicAdsrDecayPath(index), { type = "f", min = 0.001, max = 5, default = 0.2, description = "Dynamic ADSR " .. index .. " decay" })
    appendSchema(schema, ParameterBinder.dynamicAdsrSustainPath(index), { type = "f", min = 0, max = 1, default = 0.7, description = "Dynamic ADSR " .. index .. " sustain" })
    appendSchema(schema, ParameterBinder.dynamicAdsrReleasePath(index), { type = "f", min = 0.001, max = 10, default = 0.4, description = "Dynamic ADSR " .. index .. " release" })
    return schema
  end

  if id == "arp" then
    appendSchema(schema, ParameterBinder.dynamicArpRatePath(index), { type = "f", min = 0.25, max = 20, default = 8.0, description = "Dynamic Arp " .. index .. " rate (Hz)" })
    appendSchema(schema, ParameterBinder.dynamicArpModePath(index), { type = "f", min = 0, max = 3, default = 0, description = "Dynamic Arp " .. index .. " mode" })
    appendSchema(schema, ParameterBinder.dynamicArpOctavesPath(index), { type = "f", min = 1, max = 4, default = 1, description = "Dynamic Arp " .. index .. " octave range" })
    appendSchema(schema, ParameterBinder.dynamicArpGateLengthPath(index), { type = "f", min = 0.05, max = 1, default = 0.6, description = "Dynamic Arp " .. index .. " gate length" })
    appendSchema(schema, ParameterBinder.dynamicArpHoldPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Arp " .. index .. " hold" })
    return schema
  end

  if id == "transpose" then
    appendSchema(schema, ParameterBinder.dynamicTransposeSemitonesPath(index), { type = "f", min = -24, max = 24, default = 0, description = "Dynamic Transpose " .. index .. " semitone offset" })
    return schema
  end

  if id == "velocity_mapper" then
    appendSchema(schema, ParameterBinder.dynamicVelocityMapperAmountPath(index), { type = "f", min = 0, max = 1, default = 1.0, description = "Dynamic Velocity Mapper " .. index .. " amount" })
    appendSchema(schema, ParameterBinder.dynamicVelocityMapperCurvePath(index), { type = "f", min = 0, max = 2, default = 0, description = "Dynamic Velocity Mapper " .. index .. " curve" })
    appendSchema(schema, ParameterBinder.dynamicVelocityMapperOffsetPath(index), { type = "f", min = -1, max = 1, default = 0.0, description = "Dynamic Velocity Mapper " .. index .. " offset" })
    return schema
  end

  if id == "scale_quantizer" then
    appendSchema(schema, ParameterBinder.dynamicScaleQuantizerRootPath(index), { type = "f", min = 0, max = 11, default = 0, description = "Dynamic Scale Quantizer " .. index .. " root" })
    appendSchema(schema, ParameterBinder.dynamicScaleQuantizerScalePath(index), { type = "f", min = 1, max = 6, default = 1, description = "Dynamic Scale Quantizer " .. index .. " scale" })
    appendSchema(schema, ParameterBinder.dynamicScaleQuantizerDirectionPath(index), { type = "f", min = 1, max = 3, default = 1, description = "Dynamic Scale Quantizer " .. index .. " direction" })
    return schema
  end

  if id == "note_filter" then
    appendSchema(schema, ParameterBinder.dynamicNoteFilterLowPath(index), { type = "f", min = 0, max = 127, default = 36, description = "Dynamic Note Filter " .. index .. " low" })
    appendSchema(schema, ParameterBinder.dynamicNoteFilterHighPath(index), { type = "f", min = 0, max = 127, default = 96, description = "Dynamic Note Filter " .. index .. " high" })
    appendSchema(schema, ParameterBinder.dynamicNoteFilterModePath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Note Filter " .. index .. " mode" })
    return schema
  end

  if id == "attenuverter_bias" then
    appendSchema(schema, ParameterBinder.dynamicAttenuverterBiasAmountPath(index), { type = "f", min = -1, max = 1, default = 1.0, description = "Dynamic ATV / Bias " .. index .. " amount" })
    appendSchema(schema, ParameterBinder.dynamicAttenuverterBiasBiasPath(index), { type = "f", min = -1, max = 1, default = 0.0, description = "Dynamic ATV / Bias " .. index .. " bias" })
    return schema
  end

  if id == "range_mapper" then
    appendSchema(schema, ParameterBinder.dynamicRangeMapperMinPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Range Mapper " .. index .. " minimum" })
    appendSchema(schema, ParameterBinder.dynamicRangeMapperMaxPath(index), { type = "f", min = 0, max = 1, default = 1, description = "Dynamic Range Mapper " .. index .. " maximum" })
    appendSchema(schema, ParameterBinder.dynamicRangeMapperModePath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Range Mapper " .. index .. " mode" })
    return schema
  end

  if id == "lfo" then
    appendSchema(schema, ParameterBinder.dynamicLfoRatePath(index), { type = "f", min = 0.01, max = 20, default = 1.0, description = "Dynamic LFO " .. index .. " rate" })
    appendSchema(schema, ParameterBinder.dynamicLfoShapePath(index), { type = "f", min = 0, max = 5, default = 0, description = "Dynamic LFO " .. index .. " shape" })
    appendSchema(schema, ParameterBinder.dynamicLfoDepthPath(index), { type = "f", min = 0, max = 1, default = 1.0, description = "Dynamic LFO " .. index .. " depth" })
    appendSchema(schema, ParameterBinder.dynamicLfoPhasePath(index), { type = "f", min = 0, max = 360, default = 0, description = "Dynamic LFO " .. index .. " phase" })
    appendSchema(schema, ParameterBinder.dynamicLfoRetrigPath(index), { type = "f", min = 0, max = 1, default = 1, description = "Dynamic LFO " .. index .. " retrig" })
    return schema
  end

  if id == "slew" then
    appendSchema(schema, ParameterBinder.dynamicSlewRisePath(index), { type = "f", min = 0, max = 2000, default = 0, description = "Dynamic Slew " .. index .. " rise" })
    appendSchema(schema, ParameterBinder.dynamicSlewFallPath(index), { type = "f", min = 0, max = 2000, default = 0, description = "Dynamic Slew " .. index .. " fall" })
    appendSchema(schema, ParameterBinder.dynamicSlewShapePath(index), { type = "f", min = 0, max = 2, default = 1, description = "Dynamic Slew " .. index .. " shape" })
    return schema
  end

  if id == "sample_hold" then
    appendSchema(schema, ParameterBinder.dynamicSampleHoldModePath(index), { type = "f", min = 0, max = 2, default = 0, description = "Dynamic Sample Hold " .. index .. " mode" })
    return schema
  end

  if id == "compare" then
    appendSchema(schema, ParameterBinder.dynamicCompareThresholdPath(index), { type = "f", min = -1, max = 1, default = 0, description = "Dynamic Compare " .. index .. " threshold" })
    appendSchema(schema, ParameterBinder.dynamicCompareHysteresisPath(index), { type = "f", min = 0, max = 0.5, default = 0.05, description = "Dynamic Compare " .. index .. " hysteresis" })
    appendSchema(schema, ParameterBinder.dynamicCompareDirectionPath(index), { type = "f", min = 0, max = 2, default = 0, description = "Dynamic Compare " .. index .. " direction" })
    return schema
  end

  if id == "cv_mix" then
    for inputIndex = 1, 4 do
      appendSchema(schema, ParameterBinder.dynamicCvMixLevelPath(index, inputIndex), { type = "f", min = 0, max = 1, default = inputIndex == 1 and 1.0 or 0.0, description = "Dynamic CV Mix " .. index .. " input " .. inputIndex .. " level" })
    end
    appendSchema(schema, ParameterBinder.dynamicCvMixOffsetPath(index), { type = "f", min = -1, max = 1, default = 0, description = "Dynamic CV Mix " .. index .. " offset" })
    return schema
  end

  if id == "eq" then
    appendSchema(schema, ParameterBinder.dynamicEqOutputPath(index), { type = "f", min = -24, max = 24, default = 0, description = "Dynamic EQ " .. index .. " output trim" })
    appendSchema(schema, ParameterBinder.dynamicEqMixPath(index), { type = "f", min = 0, max = 1, default = 1, description = "Dynamic EQ " .. index .. " mix" })
    for bandIndex = 1, 8 do
      appendSchema(schema, ParameterBinder.dynamicEqBandEnabledPath(index, bandIndex), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic EQ " .. index .. " band " .. bandIndex .. " enabled" })
      appendSchema(schema, ParameterBinder.dynamicEqBandTypePath(index, bandIndex), { type = "f", min = 0, max = 6, default = bandIndex == 1 and 1 or (bandIndex == 8 and 2 or 0), description = "Dynamic EQ " .. index .. " band " .. bandIndex .. " type" })
      appendSchema(schema, ParameterBinder.dynamicEqBandFreqPath(index, bandIndex), { type = "f", min = 20, max = 20000, default = EQ8_DEFAULT_FREQS[bandIndex], description = "Dynamic EQ " .. index .. " band " .. bandIndex .. " frequency" })
      appendSchema(schema, ParameterBinder.dynamicEqBandGainPath(index, bandIndex), { type = "f", min = -24, max = 24, default = 0, description = "Dynamic EQ " .. index .. " band " .. bandIndex .. " gain" })
      appendSchema(schema, ParameterBinder.dynamicEqBandQPath(index, bandIndex), { type = "f", min = 0.1, max = 24, default = (bandIndex == 1 or bandIndex == 8) and 0.8 or 1.0, description = "Dynamic EQ " .. index .. " band " .. bandIndex .. " Q" })
    end
    return schema
  end

  if id == "fx" then
    appendSchema(schema, ParameterBinder.dynamicFxTypePath(index), { type = "f", min = 0, max = fxOptionCount - 1, default = 0, description = "Dynamic FX " .. index .. " type", deferGraphMutation = true })
    appendSchema(schema, ParameterBinder.dynamicFxMixPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic FX " .. index .. " wet/dry" })
    for paramIndex = 0, maxFxParams - 1 do
      local defaultValue = tonumber(fxParamDefaults and fxParamDefaults[paramIndex + 1]) or 0.5
      appendSchema(schema, ParameterBinder.dynamicFxParamPath(index, paramIndex), { type = "f", min = 0, max = 1, default = defaultValue, description = "Dynamic FX " .. index .. " param " .. paramIndex })
    end
    return schema
  end

  if id == "filter" then
    appendSchema(schema, ParameterBinder.dynamicFilterTypePath(index), { type = "f", min = 0, max = 3, default = 0, description = "Dynamic Filter " .. index .. " type" })
    appendSchema(schema, ParameterBinder.dynamicFilterCutoffPath(index), { type = "f", min = 80, max = 16000, default = 3200, description = "Dynamic Filter " .. index .. " cutoff" })
    appendSchema(schema, ParameterBinder.dynamicFilterResonancePath(index), { type = "f", min = 0.1, max = 2, default = 0.75, description = "Dynamic Filter " .. index .. " resonance" })
    return schema
  end

  if id == "rack_oscillator" then
    appendSchema(schema, ParameterBinder.dynamicOscillatorWaveformPath(index), { type = "f", min = 0, max = 7, default = 1, description = "Dynamic Oscillator " .. index .. " waveform" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorRenderModePath(index), { type = "f", min = 0, max = 1, default = oscRenderStandard, description = "Dynamic Oscillator " .. index .. " render mode" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorAdditivePartialsPath(index), { type = "f", min = 1, max = 32, default = 8, description = "Dynamic Oscillator " .. index .. " additive partial count" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorAdditiveTiltPath(index), { type = "f", min = -1, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " additive tilt" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorAdditiveDriftPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " additive drift" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorDrivePath(index), { type = "f", min = 0, max = 20, default = 0.0, description = "Dynamic Oscillator " .. index .. " drive" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorDriveShapePath(index), { type = "f", min = 0, max = 3, default = 0, description = "Dynamic Oscillator " .. index .. " drive shape" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorDriveBiasPath(index), { type = "f", min = -1, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " drive bias" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorPulseWidthPath(index), { type = "f", min = 0.01, max = 0.99, default = 0.5, description = "Dynamic Oscillator " .. index .. " pulse width" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorUnisonPath(index), { type = "f", min = 1, max = 8, default = 1, description = "Dynamic Oscillator " .. index .. " unison" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorDetunePath(index), { type = "f", min = 0, max = 100, default = 0, description = "Dynamic Oscillator " .. index .. " detune" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorSpreadPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " spread" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorOutputPath(index), { type = "f", min = 0, max = 2, default = 0.8, description = "Dynamic Oscillator " .. index .. " output" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorManualPitchPath(index), { type = "f", min = 0, max = 127, default = 60, description = "Dynamic Oscillator " .. index .. " manual pitch" })
    appendSchema(schema, ParameterBinder.dynamicOscillatorManualLevelPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " manual level" })
    for voiceIndex = 1, voiceCount do
      appendSchema(schema, ParameterBinder.dynamicOscillatorVoiceGatePath(index, voiceIndex), { type = "f", min = 0, max = 0.4, default = 0, description = "Dynamic Oscillator " .. index .. " voice " .. voiceIndex .. " gate" })
      appendSchema(schema, ParameterBinder.dynamicOscillatorVoiceVOctPath(index, voiceIndex), { type = "f", min = 0, max = 127, default = 60, description = "Dynamic Oscillator " .. index .. " voice " .. voiceIndex .. " V/Oct note" })
      appendSchema(schema, ParameterBinder.dynamicOscillatorVoiceFmPath(index, voiceIndex), { type = "f", min = -1, max = 1, default = 0, description = "Dynamic Oscillator " .. index .. " voice " .. voiceIndex .. " FM" })
      appendSchema(schema, ParameterBinder.dynamicOscillatorVoicePwCvPath(index, voiceIndex), { type = "f", min = 0, max = 1, default = 0.5, description = "Dynamic Oscillator " .. index .. " voice " .. voiceIndex .. " pulse width CV" })
    end
    return schema
  end

  if id == "rack_sample" then
    appendSchema(schema, ParameterBinder.dynamicSampleSourcePath(index), { type = "f", min = 0, max = 5, default = 1, description = "Dynamic Sample " .. index .. " source (0=input, 1=live, 2..5=layers)" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureTriggerPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " capture trigger" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureBarsPath(index), { type = "f", min = 0.0625, max = 16, default = 1.0, description = "Dynamic Sample " .. index .. " capture bars" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureModePath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " capture mode (0=retro, 1=free)" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureStartOffsetPath(index), { type = "f", min = -9999999, max = 9999999, default = 0, description = "Dynamic Sample " .. index .. " capture start offset" })
    appendSchema(schema, ParameterBinder.dynamicSampleCapturedLengthMsPath(index), { type = "f", min = 0, max = 30000, default = 0, description = "Dynamic Sample " .. index .. " last captured length (ms)" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureRecordingPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " free capture recording state" })
    appendSchema(schema, ParameterBinder.dynamicSampleCaptureWriteOffsetPath(index), { type = "f", min = 0, max = 9999999, default = 0, description = "Dynamic Sample " .. index .. " capture write offset" })
    appendSchema(schema, ParameterBinder.dynamicSamplePitchMapEnabledPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " pitch map enabled" })
    appendSchema(schema, ParameterBinder.dynamicSamplePitchModePath(index), { type = "f", min = 0, max = 2, default = 0, description = "Dynamic Sample " .. index .. " pitch mode (0=classic, 1=pvoc, 2=pvoc hq)" })
    appendSchema(schema, ParameterBinder.dynamicSamplePvocFFTOrderPath(index), { type = "f", min = 9, max = 12, default = 11, description = "Dynamic Sample " .. index .. " phase vocoder FFT order" })
    appendSchema(schema, ParameterBinder.dynamicSamplePvocTimeStretchPath(index), { type = "f", min = 0.25, max = 4.0, default = 1.0, description = "Dynamic Sample " .. index .. " phase vocoder stretch" })
    appendSchema(schema, ParameterBinder.dynamicSampleRootNotePath(index), { type = "f", min = 12, max = 96, default = 60, description = "Dynamic Sample " .. index .. " root MIDI note" })
    appendSchema(schema, ParameterBinder.dynamicSampleUnisonPath(index), { type = "f", min = 1, max = 8, default = 1, description = "Dynamic Sample " .. index .. " unison" })
    appendSchema(schema, ParameterBinder.dynamicSampleDetunePath(index), { type = "f", min = 0, max = 100, default = 0, description = "Dynamic Sample " .. index .. " detune" })
    appendSchema(schema, ParameterBinder.dynamicSampleSpreadPath(index), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " spread" })
    appendSchema(schema, ParameterBinder.dynamicSamplePlayStartPath(index), { type = "f", min = 0, max = 0.95, default = 0, description = "Dynamic Sample " .. index .. " play start" })
    appendSchema(schema, ParameterBinder.dynamicSampleLoopStartPath(index), { type = "f", min = 0, max = 0.95, default = 0, description = "Dynamic Sample " .. index .. " loop start" })
    appendSchema(schema, ParameterBinder.dynamicSampleLoopLenPath(index), { type = "f", min = 0.05, max = 1.0, default = 1.0, description = "Dynamic Sample " .. index .. " loop length" })
    appendSchema(schema, ParameterBinder.dynamicSampleCrossfadePath(index), { type = "f", min = 0.0, max = 0.5, default = 0.1, description = "Dynamic Sample " .. index .. " loop crossfade" })
    appendSchema(schema, ParameterBinder.dynamicSampleRetriggerPath(index), { type = "f", min = 0, max = 1, default = 1, description = "Dynamic Sample " .. index .. " retrigger" })
    appendSchema(schema, ParameterBinder.dynamicSampleOutputPath(index), { type = "f", min = 0, max = 2, default = 0.8, description = "Dynamic Sample " .. index .. " output" })
    appendSchema(schema, ParameterBinder.dynamicSampleInputSourcePath(index), { type = "f", min = 0, max = 65535, default = 0, description = "Dynamic Sample " .. index .. " auxiliary audio input source code" })
    for voiceIndex = 1, voiceCount do
      appendSchema(schema, ParameterBinder.dynamicSampleVoiceGatePath(index, voiceIndex), { type = "f", min = 0, max = 1, default = 0, description = "Dynamic Sample " .. index .. " voice " .. voiceIndex .. " gate" })
      appendSchema(schema, ParameterBinder.dynamicSampleVoiceVOctPath(index, voiceIndex), { type = "f", min = 0, max = 127, default = 60, description = "Dynamic Sample " .. index .. " voice " .. voiceIndex .. " V/Oct note" })
    end
    return schema
  end

  if id == "blend_simple" then
    appendSchema(schema, ParameterBinder.dynamicBlendSimpleModePath(index), { type = "f", min = 0, max = 3, default = 0, description = "Dynamic Blend Simple " .. index .. " mode (0=mix, 1=ring, 2=fm, 3=sync)" })
    appendSchema(schema, ParameterBinder.dynamicBlendSimpleBlendAmountPath(index), { type = "f", min = 0, max = 1, default = 0.5, description = "Dynamic Blend Simple " .. index .. " blend amount" })
    appendSchema(schema, ParameterBinder.dynamicBlendSimpleBlendModAmountPath(index), { type = "f", min = 0, max = 1, default = 0.5, description = "Dynamic Blend Simple " .. index .. " blend modulation amount" })
    appendSchema(schema, ParameterBinder.dynamicBlendSimpleOutputPath(index), { type = "f", min = 0, max = 1, default = 1.0, description = "Dynamic Blend Simple " .. index .. " output" })
    appendSchema(schema, ParameterBinder.dynamicBlendSimpleBSourcePath(index), { type = "f", min = 0, max = 65535, default = 0, description = "Dynamic Blend Simple " .. index .. " auxiliary B source code" })
    return schema
  end

  return schema
end

local DYNAMIC_SLOT_SCHEMA_IDS = {
  "adsr",
  "arp",
  "transpose",
  "velocity_mapper",
  "scale_quantizer",
  "note_filter",
  "attenuverter_bias",
  "range_mapper",
  "lfo",
  "slew",
  "sample_hold",
  "compare",
  "cv_mix",
  "eq",
  "fx",
  "filter",
  "rack_oscillator",
  "rack_sample",
  "blend_simple",
}

local function appendDynamicSlotsFromCounts(schema, options)
  for i = 1, #DYNAMIC_SLOT_SCHEMA_IDS do
    local specId = DYNAMIC_SLOT_SCHEMA_IDS[i]
    local count = dynamicSlotCount(options, specId)
    for slotIndex = 1, count do
      appendDynamicSlotSchema(schema, specId, slotIndex, options)
    end
  end
  return schema
end

function ParameterBinder.buildDynamicSlotSchema(specId, slotIndex, options)
  local schema = {}
  return appendDynamicSlotSchema(schema, specId, slotIndex, options or {})
end

function ParameterBinder.buildRackAudioStageSchema(index)
  local stageIndex = math.max(1, math.floor(tonumber(index) or 1))
  return {
    path = ParameterBinder.rackAudioStagePath(stageIndex),
    spec = {
      type = "f",
      min = 0,
      max = 65535,
      default = stageIndex == 1 and 1 or (stageIndex == 2 and 2 or (stageIndex == 3 and 3 or (stageIndex == 4 and 4 or 0))),
      description = "Rack audio stage code " .. stageIndex,
    },
  }
end

function ParameterBinder.buildRackAudioSourceSchema(index)
  local sourceIndex = math.max(1, math.floor(tonumber(index) or 1))
  return {
    path = ParameterBinder.rackAudioSourcePath(sourceIndex),
    spec = {
      type = "f",
      min = 0,
      max = 65535,
      default = sourceIndex == 1 and 1 or 0,
      description = "Rack audio source code " .. sourceIndex,
    },
  }
end

function ParameterBinder.buildSchema(options)
  options = options or {}

  local fxOptionCount = math.max(1, math.floor(tonumber(options.fxOptionCount) or 1))
  local maxFxParams = math.max(1, math.floor(tonumber(options.maxFxParams) or ParameterBinder.MAX_FX_PARAMS))
  local oscRenderStandard = tonumber(options.oscRenderStandard) or 0
  local oscModeClassic = tonumber(options.oscModeClassic) or 0
  local sampleSourceLive = tonumber(options.sampleSourceLive) or 0
  local sampleSourceLayerMax = tonumber(options.sampleSourceLayerMax) or sampleSourceLive
  local samplePitchModeClassic = tonumber(options.samplePitchModeClassic) or 0
  local samplePitchModeMax = tonumber(options.samplePitchModeMax) or 2

  local schema = {}

  appendSchema(schema, PATHS.waveform, { type = "f", min = 0, max = 7, default = 1, description = "Oscillator waveform" })
  appendSchema(schema, PATHS.oscRenderMode, { type = "f", min = 0, max = 1, default = oscRenderStandard, description = "Oscillator render mode (0=standard, 1=additive)" })
  appendSchema(schema, PATHS.additivePartials, { type = "f", min = 1, max = 32, default = 8, description = "Additive partial count" })
  appendSchema(schema, PATHS.additiveTilt, { type = "f", min = -1, max = 1, default = 0, description = "Additive spectral tilt" })
  appendSchema(schema, PATHS.additiveDrift, { type = "f", min = 0, max = 1, default = 0, description = "Additive drift amount" })
  appendSchema(schema, PATHS.pulseWidth, { type = "f", min = 0.01, max = 0.99, default = 0.5, description = "Pulse width" })
  appendSchema(schema, PATHS.unison, { type = "f", min = 1, max = 8, default = 1, description = "Unison voices" })
  appendSchema(schema, PATHS.detune, { type = "f", min = 0, max = 100, default = 0, description = "Unison detune (cents)" })
  appendSchema(schema, PATHS.spread, { type = "f", min = 0, max = 1, default = 0, description = "Stereo spread" })
  appendSchema(schema, PATHS.driveShape, { type = "f", min = 0, max = 3, default = 0, description = "Oscillator drive shape" })
  appendSchema(schema, PATHS.driveBias, { type = "f", min = -1, max = 1, default = 0, description = "Oscillator drive bias" })
  appendSchema(schema, PATHS.filterType, { type = "f", min = 0, max = 3, default = 0, description = "Filter type" })
  appendSchema(schema, PATHS.cutoff, { type = "f", min = 80, max = 16000, default = 3200, description = "Filter cutoff" }, {
    targetKey = "filt",
    method = "setCutoff",
  })
  appendSchema(schema, PATHS.resonance, { type = "f", min = 0.1, max = 2, default = 0.75, description = "Filter resonance" }, {
    targetKey = "filt",
    method = "setResonance",
  })
  appendSchema(schema, PATHS.drive, { type = "f", min = 0, max = 20, default = 0.0, description = "Oscillator drive amount" })

  appendSchema(schema, PATHS.fx1Type, { type = "f", min = 0, max = fxOptionCount - 1, default = 0, description = "FX1 type", deferGraphMutation = true })
  appendSchema(schema, PATHS.fx1Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX1 wet/dry" })
  appendSchema(schema, PATHS.fx2Type, { type = "f", min = 0, max = fxOptionCount - 1, default = 0, description = "FX2 type", deferGraphMutation = true })
  appendSchema(schema, PATHS.fx2Mix, { type = "f", min = 0, max = 1, default = 0, description = "FX2 wet/dry" })

  for i = 0, maxFxParams - 1 do
    appendSchema(schema, ParameterBinder.fxParamPath("fx1", i), { type = "f", min = 0, max = 1, default = 0.5, description = "FX1 param " .. i })
    appendSchema(schema, ParameterBinder.fxParamPath("fx2", i), { type = "f", min = 0, max = 1, default = 0.5, description = "FX2 param " .. i })
  end

  appendSchema(schema, PATHS.eqOutput, { type = "f", min = -24, max = 24, default = 0, description = "EQ output trim" }, {
    targetKey = "eq8",
    method = "setOutput",
    assertMessage = "EQ8 bind failed: setOutput",
  })
  appendSchema(schema, PATHS.eqMix, { type = "f", min = 0, max = 1, default = 1, description = "EQ mix" }, {
    targetKey = "eq8",
    method = "setMix",
    assertMessage = "EQ8 bind failed: setMix",
  })

  for i = 1, 8 do
    appendSchema(schema, ParameterBinder.eq8BandEnabledPath(i), { type = "f", min = 0, max = 1, default = 0, description = "EQ8 band " .. i .. " enabled" }, {
      targetKey = "eq8",
      method = "setBandEnabled:" .. i,
      assertMessage = "EQ8 bind failed: setBandEnabled:" .. i,
    })
    appendSchema(schema, ParameterBinder.eq8BandTypePath(i), { type = "f", min = 0, max = 6, default = i == 1 and 1 or (i == 8 and 2 or 0), description = "EQ8 band " .. i .. " type" }, {
      targetKey = "eq8",
      method = "setBandType:" .. i,
      assertMessage = "EQ8 bind failed: setBandType:" .. i,
    })
    appendSchema(schema, ParameterBinder.eq8BandFreqPath(i), { type = "f", min = 20, max = 20000, default = EQ8_DEFAULT_FREQS[i], description = "EQ8 band " .. i .. " frequency" }, {
      targetKey = "eq8",
      method = "setBandFreq:" .. i,
      assertMessage = "EQ8 bind failed: setBandFreq:" .. i,
    })
    appendSchema(schema, ParameterBinder.eq8BandGainPath(i), { type = "f", min = -24, max = 24, default = 0, description = "EQ8 band " .. i .. " gain" }, {
      targetKey = "eq8",
      method = "setBandGain:" .. i,
      assertMessage = "EQ8 bind failed: setBandGain:" .. i,
    })
    appendSchema(schema, ParameterBinder.eq8BandQPath(i), { type = "f", min = 0.1, max = 24, default = (i == 1 or i == 8) and 0.8 or 1.0, description = "EQ8 band " .. i .. " Q" }, {
      targetKey = "eq8",
      method = "setBandQ:" .. i,
      assertMessage = "EQ8 bind failed: setBandQ:" .. i,
    })
  end

  appendSchema(schema, PATHS.output, { type = "f", min = 0, max = 2, default = 0.8, description = "Output gain" }, {
    targetKey = "out",
    method = "setGain",
  })
  appendSchema(schema, PATHS.rackAudioEdgeMask, {
    type = "f",
    min = 0,
    max = RackAudioRouter.MAX_EDGE_MASK,
    default = RackAudioRouter.DEFAULT_EDGE_MASK,
    description = "Rack fixed-chain audio edge mask"
  })
  appendSchema(schema, PATHS.rackAudioStageCount, {
    type = "f",
    min = 0,
    max = MAX_RACK_AUDIO_STAGES,
    default = 4,
    description = "Rack audio stage count"
  })
  appendSchema(schema, PATHS.rackAudioOutputEnabled, {
    type = "f",
    min = 0,
    max = 1,
    default = 1,
    description = "Rack audio output enabled"
  })
  appendSchema(schema, PATHS.rackAudioSourceCount, {
    type = "f",
    min = 0,
    max = MAX_RACK_AUDIO_SOURCES,
    default = 1,
    description = "Rack audio source count"
  })
  appendSchema(schema, PATHS.rackRegistryRequestKind, {
    type = "f",
    min = 0,
    max = 32,
    default = 0,
    description = "Rack registry request kind"
  })
  appendSchema(schema, PATHS.rackRegistryRequestIndex, {
    type = "f",
    min = 0,
    max = 128,
    default = 0,
    description = "Rack registry request index"
  })
  appendSchema(schema, PATHS.rackRegistryRequestNonce, {
    type = "f",
    min = 0,
    max = 1000000000,
    default = 0,
    description = "Rack registry request nonce",
    deferGraphMutation = true,
  })
  for i = 1, MAX_RACK_AUDIO_STAGES do
    local entry = ParameterBinder.buildRackAudioStageSchema(i)
    appendSchema(schema, entry.path, entry.spec)
  end
  for i = 1, MAX_RACK_AUDIO_SOURCES do
    local entry = ParameterBinder.buildRackAudioSourceSchema(i)
    appendSchema(schema, entry.path, entry.spec)
  end

  appendSchema(schema, PATHS.attack, { type = "f", min = 0.001, max = 5, default = 0.05, description = "ADSR attack" })
  appendSchema(schema, PATHS.decay, { type = "f", min = 0.001, max = 5, default = 0.2, description = "ADSR decay" })
  appendSchema(schema, PATHS.sustain, { type = "f", min = 0, max = 1, default = 0.7, description = "ADSR sustain" })
  appendSchema(schema, PATHS.release, { type = "f", min = 0.001, max = 10, default = 0.4, description = "ADSR release" })

  appendDynamicSlotsFromCounts(schema, options)

  appendSchema(schema, PATHS.noiseLevel, { type = "f", min = 0, max = 1, default = 0, description = "Noise level" })
  appendSchema(schema, PATHS.noiseColor, { type = "f", min = 0, max = 1, default = 0.1, description = "Noise color" }, {
    targetKey = "noiseGen",
    method = "setColor",
  })

  appendSchema(schema, PATHS.oscMode, { type = "f", min = 0, max = 2, default = oscModeClassic, description = "Osc mode (0=classic, 1=sample loop, 2=blend)" })
  appendSchema(schema, PATHS.sampleSource, { type = "f", min = sampleSourceLive, max = sampleSourceLayerMax, default = sampleSourceLive, description = "Sample source (0=live, 1..4=layers)" })
  appendSchema(schema, PATHS.sampleCaptureTrigger, { type = "f", min = 0, max = 1, default = 0, description = "Trigger sample capture from current source" })
  appendSchema(schema, PATHS.sampleCaptureBars, { type = "f", min = 0.0625, max = 16, default = 1.0, description = "Capture length in bars" })
  appendSchema(schema, PATHS.sampleCaptureMode, { type = "f", min = 0, max = 1, default = 0, description = "Capture mode (0=retro, 1=free)" })
  appendSchema(schema, PATHS.sampleCaptureWriteOffset, { type = "f", min = 0, max = 9999999, default = 0, description = "Current sample capture write offset" })
  appendSchema(schema, PATHS.sampleCaptureStartOffset, { type = "f", min = 0, max = 9999999, default = 0, description = "Start offset for free mode capture (samples)" })
  appendSchema(schema, PATHS.sampleCapturedLengthMs, { type = "f", min = 0, max = 30000, default = 0, description = "Last captured length in milliseconds" })
  appendSchema(schema, PATHS.sampleCaptureRecording, { type = "f", min = 0, max = 1, default = 0, description = "Sample free capture recording state (0/1)" })
  appendSchema(schema, PATHS.samplePitchMapEnabled, { type = "f", min = 0, max = 1, default = 0, description = "Auto-apply detected sample pitch to root note" })
  appendSchema(schema, PATHS.samplePitchMode, { type = "f", min = samplePitchModeClassic, max = samplePitchModeMax, default = samplePitchModeClassic, description = "Sample pitch mode (0=classic, 1=pvoc, 2=pvoc hq)" })
  appendSchema(schema, PATHS.samplePvocFFTOrder, { type = "f", min = 9, max = 12, default = 11, description = "Phase vocoder FFT order (9=512, 10=1024, 11=2048, 12=4096)" })
  appendSchema(schema, PATHS.samplePvocTimeStretch, { type = "f", min = 0.25, max = 4.0, default = 1.0, description = "Phase vocoder time stretch ratio (0.25-4.0)" })
  appendSchema(schema, PATHS.sampleRootNote, { type = "f", min = 12, max = 96, default = 60, description = "Sample root MIDI note" })
  appendSchema(schema, PATHS.samplePlayStart, { type = "f", min = 0, max = 0.95, default = 0, description = "Sample play start - yellow flag (normalized)" })
  appendSchema(schema, PATHS.sampleLoopStart, { type = "f", min = 0, max = 0.95, default = 0, description = "Sample loop start - green flag (normalized)" })
  appendSchema(schema, PATHS.sampleLoopLen, { type = "f", min = 0.05, max = 1.0, default = 1.0, description = "Sample loop length (normalized)" })
  appendSchema(schema, PATHS.sampleCrossfade, { type = "f", min = 0.0, max = 0.5, default = 0.1, description = "Boundary crossfade window" })
  appendSchema(schema, PATHS.sampleRetrigger, { type = "f", min = 0, max = 1, default = 1, description = "Retrigger sample from loop start on note-on" })
  appendSchema(schema, PATHS.sampleAdditiveEnabled, { type = "f", min = 0, max = 1, default = 0, description = "Debug gate for hidden sample-derived additive layer" })
  appendSchema(schema, PATHS.sampleAdditiveMix, { type = "f", min = 0, max = 1, default = 0.25, description = "Debug mix for hidden sample-derived additive layer" })

  appendSchema(schema, PATHS.blendMode, { type = "f", min = 0, max = 5, default = 0, description = "Blend mode (0=Mix, 1=Ring, 2=FM, 3=Sync, 4=Add, 5=Morph)" })
  appendSchema(schema, PATHS.blendAmount, { type = "f", min = 0, max = 1, default = 0.5, description = "Blend amount / wetness" })
  appendSchema(schema, PATHS.waveToSample, { type = "f", min = 0, max = 1, default = 0.5, description = "Wave influence on sample path" })
  appendSchema(schema, PATHS.sampleToWave, { type = "f", min = 0, max = 1, default = 0.0, description = "Sample influence on wave path" })
  appendSchema(schema, PATHS.blendKeyTrack, { type = "f", min = 0, max = 2, default = 2, description = "Keytrack: 0=wave, 1=sample, 2=both" })
  appendSchema(schema, PATHS.blendSamplePitch, { type = "f", min = -24, max = 24, default = 0, description = "Blend sample transpose (semitones)" })
  appendSchema(schema, PATHS.blendModAmount, { type = "f", min = 0, max = 1, default = 0.5, description = "Blend mode modulation depth" })
  appendSchema(schema, PATHS.addFlavor, { type = "f", min = 0, max = 1, default = 0, description = "Add mode flavor (0=Self, 1=Driven)" })
  appendSchema(schema, PATHS.xorBehavior, { type = "f", min = 0, max = 1, default = 0, description = "XOR behavior: 0=crush/xor, 1=gate/compare" })

  appendSchema(schema, PATHS.morphCurve, { type = "f", min = 0, max = 2, default = 2, description = "Morph crossfade curve: 0=linear, 1=S-curve, 2=equal-power" })
  appendSchema(schema, PATHS.morphConvergence, { type = "f", min = 0, max = 1, default = 0, description = "Harmonic stretch: 0=normal, 1=metallic/bell character" })
  appendSchema(schema, PATHS.morphPhase, { type = "f", min = 0, max = 2, default = 0, description = "Spectral tilt: 0=neutral, 1=bright, 2=dark" })
  appendSchema(schema, PATHS.morphSpeed, { type = "f", min = 0.1, max = 4.0, default = 1.0, description = "Temporal scan speed: 0.1=slow, 4.0=fast" })
  appendSchema(schema, PATHS.morphContrast, { type = "f", min = 0, max = 2, default = 0.5, description = "Spectral contrast: 0=subtle, 2=aggressive" })
  appendSchema(schema, PATHS.morphSmooth, { type = "f", min = 0, max = 1, default = 0.0, description = "Frame smoothing: 0=hard cuts, 1=buttery" })
  appendSchema(schema, PATHS.envFollowAmount, { type = "f", min = 0, max = 1, default = 1.0, description = "Envelope follow: how much sample phrase contour shapes additive output" })

  return schema
end

function ParameterBinder.buildModulationTargetDescriptors(options)
  local schema = ParameterBinder.buildSchema(options)
  local byPath = schemaByPath(schema)
  local seeded = {
    {
      path = PATHS.cutoff,
      scope = "global",
      signalKind = "scalar",
      domain = "freq",
      owner = "filter",
      displayName = "Filter Cutoff",
    },
    {
      path = PATHS.resonance,
      scope = "global",
      signalKind = "scalar",
      domain = "q",
      owner = "filter",
      displayName = "Filter Resonance",
    },
    {
      path = PATHS.pulseWidth,
      scope = "global",
      signalKind = "scalar",
      domain = "normalized",
      owner = "oscillator",
      displayName = "Pulse Width",
    },
    {
      path = PATHS.eqMix,
      scope = "global",
      signalKind = "scalar",
      domain = "normalized",
      owner = "eq8",
      displayName = "EQ Mix",
    },
    {
      path = PATHS.eqOutput,
      scope = "global",
      signalKind = "scalar",
      domain = "gain_db",
      owner = "eq8",
      displayName = "EQ Output",
    },
    {
      path = PATHS.output,
      scope = "global",
      signalKind = "scalar",
      domain = "normalized",
      owner = "output",
      displayName = "Output Gain",
    },
    {
      path = PATHS.waveform,
      scope = "global",
      signalKind = "stepped",
      domain = "enum_index",
      owner = "oscillator",
      displayName = "Oscillator Waveform",
      enumOptions = { "Sine", "Saw", "Sqr", "Tri", "Blend", "Noise", "Pulse", "SSaw" },
    },
    {
      path = PATHS.filterType,
      scope = "global",
      signalKind = "stepped",
      domain = "enum_index",
      owner = "filter",
      displayName = "Filter Type",
      enumOptions = { "SVF LP", "SVF BP", "SVF HP", "SVF Notch" },
    },
  }

  local out = {}
  for i = 1, #seeded do
    local spec = seeded[i]
    local schemaEntry = byPath[spec.path]
    local paramSpec = schemaEntry and schemaEntry.spec or {}
    out[#out + 1] = {
      id = spec.path,
      direction = "target",
      scope = spec.scope,
      signalKind = spec.signalKind,
      domain = spec.domain,
      provider = "parameter-schema",
      owner = spec.owner,
      displayName = spec.displayName,
      available = true,
      min = paramSpec.min,
      max = paramSpec.max,
      default = paramSpec.default,
      enumOptions = cloneArray(spec.enumOptions),
      meta = {
        description = paramSpec.description,
        paramType = paramSpec.type,
        sourcePath = spec.path,
      },
    }
  end

  return out
end

function ParameterBinder.registerSchema(ctx, schema, options)
  options = options or {}
  local params = {}
  local targets = options.targets or {}

  local function addParam(path, specDef)
    ctx.params.register(path, specDef)
    params[#params + 1] = path
  end

  if options.voicePool and options.voicePool.registerVoicePaths then
    options.voicePool.registerVoicePaths(addParam)
  end

  for i = 1, #schema do
    local entry = schema[i]
    addParam(entry.path, entry.spec)

    if entry.bind ~= nil then
      local target = targets[entry.bind.targetKey]
      if target == nil then
        error(string.format("ParameterBinder missing bind target '%s' for %s", tostring(entry.bind.targetKey), tostring(entry.path)))
      end
      local ok = ctx.params.bind(entry.path, target, entry.bind.method)
      if entry.bind.assertMessage ~= nil then
        assert(ok, entry.bind.assertMessage)
      elseif ok == false then
        error(string.format("Failed to bind %s -> %s", tostring(entry.path), tostring(entry.bind.method)))
      end
    end
  end

  return params
end

function ParameterBinder.registerAll(ctx, options)
  local schema = ParameterBinder.buildSchema(options)
  local params = ParameterBinder.registerSchema(ctx, schema, options)
  return {
    schema = schema,
    params = params,
    adsr = copyTable(ParameterBinder.ADSR_DEFAULTS),
  }
end

function ParameterBinder.createDispatcher(options)
  options = options or {}
  local exactHandlers = options.exactHandlers or {}
  local ignorePredicates = options.ignorePredicates or {}
  local patternHandlers = options.patternHandlers or {}

  return function(path, value)
    if options.resolveVoicePath ~= nil then
      local action, voiceIndex = options.resolveVoicePath(path)
      if action == "freq" and options.onVoiceFreq then
        return options.onVoiceFreq(voiceIndex, value, path)
      elseif action == "gate" and options.onVoiceGate then
        return options.onVoiceGate(voiceIndex, value, path)
      elseif action == "amp" and options.onVoiceAmp then
        return options.onVoiceAmp(voiceIndex, value, path)
      end
    end

    local exactHandler = exactHandlers[path]
    if exactHandler ~= nil then
      return exactHandler(value, path)
    end

    for i = 1, #ignorePredicates do
      if ignorePredicates[i](path, value) == true then
        return nil
      end
    end

    for i = 1, #patternHandlers do
      if patternHandlers[i](path, value) == true then
        return nil
      end
    end

    if options.onUnhandled ~= nil then
      return options.onUnhandled(path, value)
    end

    return nil
  end
end

function ParameterBinder.fxSlotPatternHandler(slotName, fxSlot)
  return function(path, value)
    local matchedSlot, index = ParameterBinder.matchFxParamPath(path)
    if matchedSlot ~= slotName or index == nil then
      return false
    end
    fxSlot.applyParam(index + 1, value)
    return true
  end
end

return ParameterBinder

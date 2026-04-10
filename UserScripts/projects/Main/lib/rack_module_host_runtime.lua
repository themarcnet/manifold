-- Standalone Rack Module Host Runtime
-- Provides deps, instantiates individual rack modules, wires I/O.
-- This is the same runtime that exported VST3 plugins will use.

local FxDefs = require("fx_definitions")
local Utils = require("utils")
local FxSlot = require("fx_slot")
local SampleSynth = require("sample_synth")
local ParameterBinder = require("parameter_binder")

local RackFilterModule = require("rack_modules.filter")
local RackFxModule = require("rack_modules.fx")
local RackEqModule = require("rack_modules.eq")
local RackOscillatorModule = require("rack_modules.oscillator")
local RackSampleModule = require("rack_modules.sample")
local RackBlendSimpleModule = require("rack_modules.blend_simple")

local M = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local VOICE_COUNT = 8
local MAX_FX_PARAMS = ParameterBinder.MAX_FX_PARAMS or 64
local LEGACY_OSC_MAX_LEVEL = 0.40
local DYNAMIC_OSC_OUTPUT_TRIM = 0.25
local DYNAMIC_OSC_DEFAULT_OUTPUT = 0.8
local OSC_RENDER_STANDARD = 0
local SAMPLE_PITCH_MODE_CLASSIC = 0
local SAMPLE_PITCH_MODE_PHASE_VOCODER = 1
local SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ = 2

local function noteToFrequency(note)
  return 440.0 * (2.0 ^ ((tonumber(note) - 69.0) / 12.0))
end

-- ---------------------------------------------------------------------------
-- Module registry — maps specId to { module, depsFn }
-- depsFn(ctx, slots) builds the deps table for that module type
-- ---------------------------------------------------------------------------

local function makeConnectMixerInput(ctx)
  return function(mixer, inputIndex, source)
    mixer:setInputCount(inputIndex)
    mixer:setGain(inputIndex, 1.0)
    mixer:setPan(inputIndex, 0.0)
    ctx.graph.connect(source, mixer, 0, (inputIndex - 1) * 2)
  end
end

local function makeFilterDeps(ctx, slots)
  local function applyDefaults(node)
    node:setMode(0)
    node:setCutoff(3200)
    node:setResonance(0.75)
    node:setDrive(1.0)
    node:setMix(1.0)
  end
  return {
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    applyDefaults = applyDefaults,
  }
end

local function makeEqDeps(ctx, slots)
  local function applyDefaults(node)
    for i = 1, 8 do
      node:setBandGain(i, 0.0)
      node:setBandFreq(i, 1000.0)
      node:setBandQ(i, 0.707)
      node:setBandType(i, 0)
    end
    node:setMix(1.0)
  end
  return {
    ctx = ctx,
    slots = slots,
    applyDefaults = applyDefaults,
    ParameterBinder = ParameterBinder,
  }
end

local function makeFxDeps(ctx, slots)
  local connectMixerInput = makeConnectMixerInput(ctx)
  local fxDefs = FxDefs.buildFxDefs(ctx.primitives, ctx.graph)
  local fxCtx = {
    primitives = ctx.primitives,
    graph = ctx.graph,
    connectMixerInput = connectMixerInput,
  }
  return {
    ctx = ctx,
    slots = slots,
    FxSlot = FxSlot,
    ParameterBinder = ParameterBinder,
    fxCtx = fxCtx,
    fxDefs = fxDefs,
    maxFxParams = MAX_FX_PARAMS,
  }
end

local function makeOscillatorDeps(ctx, slots)
  local connectMixerInput = makeConnectMixerInput(ctx)
  return {
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    noteToFrequency = noteToFrequency,
    connectMixerInput = connectMixerInput,
    voiceCount = VOICE_COUNT,
    outputTrim = DYNAMIC_OSC_OUTPUT_TRIM,
    defaultOutput = DYNAMIC_OSC_DEFAULT_OUTPUT,
    maxLevel = LEGACY_OSC_MAX_LEVEL,
    oscRenderStandard = OSC_RENDER_STANDARD,
  }
end

local function makeSampleDeps(ctx, slots, sampleSynth)
  local connectMixerInput = makeConnectMixerInput(ctx)
  return {
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    SampleSynth = SampleSynth,
    ParameterBinder = ParameterBinder,
    noteToFrequency = noteToFrequency,
    connectMixerInput = connectMixerInput,
    voiceCount = VOICE_COUNT,
    outputTrim = DYNAMIC_OSC_OUTPUT_TRIM,
    samplePitchModeClassic = SAMPLE_PITCH_MODE_CLASSIC,
    samplePitchModePhaseVocoder = SAMPLE_PITCH_MODE_PHASE_VOCODER,
    samplePitchModePhaseVocoderHQ = SAMPLE_PITCH_MODE_PHASE_VOCODER_HQ,
    buildSourceSpecs = sampleSynth and sampleSynth.buildSourceSpecs or nil,
  }
end

local function makeBlendSimpleDeps(ctx, slots)
  local connectMixerInput = makeConnectMixerInput(ctx)
  return {
    ctx = ctx,
    slots = slots,
    Utils = Utils,
    ParameterBinder = ParameterBinder,
    connectMixerInput = connectMixerInput,
  }
end

-- ---------------------------------------------------------------------------
-- Module entry: describes one module type for the host
-- ---------------------------------------------------------------------------

local MODULE_DEFS = {
  filter        = { module = RackFilterModule,     depsFn = makeFilterDeps,     kind = "processor" },
  fx            = { module = RackFxModule,         depsFn = makeFxDeps,         kind = "processor" },
  eq            = { module = RackEqModule,         depsFn = makeEqDeps,         kind = "processor" },
  oscillator    = { module = RackOscillatorModule, depsFn = makeOscillatorDeps, kind = "source" },
  sample        = { module = RackSampleModule,     depsFn = makeSampleDeps,     kind = "source" },
  blend_simple  = { module = RackBlendSimpleModule, depsFn = makeBlendSimpleDeps, kind = "processor_dual" },
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Instantiate a single rack module and wire it into the audio graph.
--- @param ctx table  DSP context from buildPlugin(ctx)
--- @param specId string  Module spec ID (e.g. "filter", "oscillator")
--- @return table moduleInstance  The created module (has createSlot, applyPath)
--- @return table slot  The first slot created by the module
--- @return table deps  The deps table used (for advanced usage)
function M.instantiateModule(ctx, specId)
  local def = MODULE_DEFS[specId]
  if not def then
    error("Unknown rack module specId: " .. tostring(specId))
  end

  local slots = {}

  -- Sample module needs a SampleSynth instance first
  local sampleSynth = nil
  if specId == "sample" then
    sampleSynth = SampleSynth.create(ctx, {
      layerInputNodes = {},
      layerSourceNodes = {},
    })
  end

  -- Build the deps
  local deps
  if specId == "sample" then
    deps = def.depsFn(ctx, slots, sampleSynth)
  else
    deps = def.depsFn(ctx, slots)
  end

  -- Create the module
  local moduleInstance = def.module.create(deps)

  -- Create one slot
  moduleInstance.createSlot(1)

  return moduleInstance, slots[1], deps, def.kind, sampleSynth
end

--- Wire a module's output to the plugin output.
--- For processor modules, also wires plugin input → module input.
--- @param ctx table  DSP context
--- @param slot table  The module's first slot
--- @param kind string  "source", "processor", or "processor_dual"
function M.wireModule(ctx, slot, kind)
  if kind == "source" then
    -- Source modules produce their own audio
    if slot.output then
      ctx.graph.connect(slot.output, ctx.output)
    elseif slot.out then
      ctx.graph.connect(slot.out, ctx.output)
    end

  elseif kind == "processor" then
    -- Single-input processor: input → module → output
    local passthrough = ctx.primitives.GainNode.new(2)
    passthrough:setGain(1.0)
    ctx.graph.connect(ctx.input, passthrough)

    if slot.input then
      ctx.graph.connect(passthrough, slot.input)
    end
    if slot.node then
      ctx.graph.connect(passthrough, slot.node)
    end
    if slot.output then
      ctx.graph.connect(slot.output, ctx.output)
    elseif slot.out then
      ctx.graph.connect(slot.out, ctx.output)
    end

  elseif kind == "processor_dual" then
    -- Dual-input processor (blend): input → A, secondary → B
    local passthroughA = ctx.primitives.GainNode.new(2)
    passthroughA:setGain(1.0)
    local passthroughB = ctx.primitives.GainNode.new(2)
    passthroughB:setGain(1.0)
    ctx.graph.connect(ctx.input, passthroughA)
    ctx.graph.connect(ctx.input, passthroughB)

    if slot.inputA then
      ctx.graph.connect(passthroughA, slot.inputA)
    end
    if slot.inputB then
      ctx.graph.connect(passthroughB, slot.inputB)
    end
    if slot.output then
      ctx.graph.connect(slot.output, ctx.output)
    end
  end
end

--- Register a module's parameters with the DSP host.
--- Reads parameter definitions from the module's spec.
--- @param ctx table  DSP context
--- @param specId string  Module spec ID
--- @param slotIndex number  Slot index (default 1)
function M.registerModuleParams(ctx, specId, slotIndex)
  slotIndex = slotIndex or 1
  -- Parameters are registered via applyPath as they come in from the UI.
  -- The host params (module selection, input controls) are registered separately.
end

--- Get the module definition table for a specId.
function M.getModuleDef(specId)
  return MODULE_DEFS[specId]
end

--- Get all registered module spec IDs.
function M.getRegisteredModules()
  local ids = {}
  for id, _ in pairs(MODULE_DEFS) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

--- Get the kind (source/processor/processor_dual) for a specId.
function M.getModuleKind(specId)
  local def = MODULE_DEFS[specId]
  return def and def.kind or nil
end

return M

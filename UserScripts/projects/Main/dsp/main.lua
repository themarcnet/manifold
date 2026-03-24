-- Main DSP - Integrated Looper + MidiSynth
-- MidiSynth output routes to both host output and looper layer 0 input for recording.

local looperBaseline = loadDspModule("./looper_baseline.lua")
local midisynthModule = loadDspModule("./midisynth_integration.lua")

function buildPlugin(ctx)
  -- Step 1: Build looper baseline (creates 4 layers with capture/playback)
  local looper = looperBaseline.attach(ctx)

  -- Step 2: Resolve looper layer nodes for synth integration.
  -- - layer0InputNode: synth monitor/send into looper layer 0 capture chain.
  -- - layerSourceNodes: sources that can be grabbed into MidiSynth sample mode.
  local layer0InputNode = nil
  local layerSourceNodes = {}
  if looper.layers then
    for i = 1, #looper.layers do
      local layer = looper.layers[i]
      local parts = layer and layer["parts"] or nil

      if i == 1 and parts and parts["input"] then
        layer0InputNode = parts["input"]["__node"]
      end

      -- Tap from gate (pre-gain) so gain remains a sink for audible layer output.
      local sourceNode = nil
      if parts and parts["gate"] then
        sourceNode = parts["gate"]["__node"]
      elseif parts and parts["playback"] then
        sourceNode = parts["playback"]["__node"]
      end
      layerSourceNodes[i] = sourceNode
    end
  end

  -- Step 3: Build MidiSynth with routing to looper layer 0 + sample sources
  local synth = midisynthModule.buildSynth(ctx, {
    targetLayerInput = layer0InputNode,
    layerSourceNodes = layerSourceNodes,
  })

  -- Step 4: Return combined plugin descriptor
  return {
    description = "Main - 4-layer looper with 8-voice polysynth",
    params = synth.params,   -- looper params are registered via ctx.params.register in baseline
    onParamChange = function(path, value)
      -- Route synth params to synth
      if path:match("^/midi/synth/") then
        if synth.onParamChange then
          synth.onParamChange(path, value)
        end
        return
      end

      -- Route everything else to looper
      if looper.applyParam then
        looper.applyParam(path, value)
      end
    end,

    getSamplePeaks = function(numBuckets)
      if synth.getSamplePeaks then
        return synth.getSamplePeaks(numBuckets)
      end
      return nil
    end,

    getSampleLoopLength = function()
      if synth.getSampleLoopLength then
        return synth.getSampleLoopLength()
      end
      return 0
    end,

    getVoiceSamplePositions = function()
      if synth.getVoiceSamplePositions then
        return synth.getVoiceSamplePositions()
      end
      return {}
    end,

    refreshSampleDerivedAdditive = function()
      if synth.refreshSampleDerivedAdditive then
        return synth.refreshSampleDerivedAdditive()
      end
      return {}
    end,

    getSampleDerivedAddDebug = function(voiceIndex)
      if synth.getSampleDerivedAddDebug then
        return synth.getSampleDerivedAddDebug(voiceIndex)
      end
      return {}
    end,

    process = function(blockSize, sampleRate)
      if synth.process then
        synth.process(blockSize, sampleRate)
      end
    end,
  }
end

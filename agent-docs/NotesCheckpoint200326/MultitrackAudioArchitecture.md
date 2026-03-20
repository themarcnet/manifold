# Multitrack Audio Architecture Proposal

**Date:** 2026-03-20  
**Context:** Manifold Audio Looper - Multi-view, multi-DSP project architecture  
**Status:** Design document for implementation

---

## Problem Statement

The current audio track infrastructure is limiting when wiring up inputs and outputs within a multi-view, multi-DSP project (Main). While dynamic patching inside a single project is possible (as demonstrated by DspLiveScripting), the current approach is bespoke to Lua and doesn't scale to complex multitrack scenarios.

Specific pain points:

1. **Cross-slot node access is fragile**: `host.getGraphNodeByPath()` reaches into other slots' internals
2. **Manual plumbing**: Passing `targetLayerInput` between modules doesn't scale to 3+ components
3. **No stable API contract**: Reaching into `layers[i].parts.input` breaks encapsulation
4. **Single graph limitation**: Can't have synth in slot A, looper in slot B, FX in slot C with audio flowing between them

---

## Solution: Slot Port Declarations + Graph Merging

Instead of separate `GraphRuntime` per slot, merge them into one runtime with declared ports.

### Core Concept

**Slots become namespaces within one shared graph.** This enables:

1. **Cross-slot routing**: `ctx.ports.getOutput("synth", "main")` → node in another slot
2. **Dynamic rewiring**: Change connections, recompile merged graph
3. **Hot reload per slot**: Reload synth slot without touching looper slot
4. **No audio thread changes**: Still one `GraphRuntime`, one `process()` call

---

## Runtime Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SINGLE GraphRuntime                                  │
│                    (all slots compiled together)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SLOT: "inputs"                    SLOT: "looper"           SLOT: "master"   │
│  ┌─────────────────┐              ┌─────────────────┐      ┌─────────────┐  │
│  │ InputPassthrough├──→ "mic" ───→│ layer0:parts.in │      │ masterGain  │  │
│  │ InputPassthrough├──→ "line" ──→│ layer1:parts.in │      │    ↓        │  │
│  └─────────────────┘              │ layer2:parts.in │      │  limiter    │  │
│        ↑                          │ layer3:parts.in │      │    ↓        │  │
│   host audio                      │    ↓    ↓       │      │  output     │  │
│                                   │  [playback nodes]│      └─────────────┘  │
│                                   │    ↓            │            ↑           │
│                                   │ "out0"-"out3"   │────────────┘           │
│                                   └─────────────────┘                        │
│                                          ↑                                   │
│                                          │         SLOT: "synth"             │
│                                          │         ┌─────────────────┐       │
│                                          └─────────│ midiVoiceNode     │       │
│                                                    │    ↓            │       │
│                                                    │ "synth_main" ───┼──┐    │
│                                                    │ "synth_send" ───┼──┼──┐ │
│                                                    └─────────────────┘  │  │ │
│                                                                         │  │ │
│  SLOT: "fx_bus"                              SLOT: "donut_fx"           │  │ │
│  ┌─────────────────┐                        ┌─────────────────┐        │  │ │
│  │ reverbIn ←──────┼────────────────────────┼──← "vocal"      │←───────┘  │ │
│  │    ↓            │                        │    ↓            │           │ │
│  │ reverbNode      │                        │ [fx chain]      │           │ │
│  │    ↓            │                        │    ↓            │           │ │
│  │ "reverb_out" ───┼────────────────────────→──┼──┼──→ layer0 │←──────────┘ │
│  └─────────────────┘                        └─────────────────┘              │
│                                                                              │
│  CROSS-SLOT CONNECTIONS (declared in Lua, compiled to native):               │
│  - inputs:mic → looper:layer0_in                                             │
│  - synth:synth_main → looper:layer0_in (for recording synth)                 │
│  - synth:synth_send → fx_bus:reverbIn                                        │
│  - fx_bus:reverb_out → donut_fx:vocal                                        │
│  - looper:out0 → donut_fx:layer0                                             │
│  - donut_fx:layer0 → master:masterGain                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Lua API

### Port Declaration

```lua
-- Slot A (Looper) declares what it exposes
function buildPlugin(ctx)
  local layers = {}
  for i = 1, 4 do
    layers[i] = ctx.bundles.LoopLayer.new({channels = 2})
  end
  
  -- Declare output ports other slots can connect to
  ctx.ports.declareOutput("layer1_out", layers[1].parts.gain)
  ctx.ports.declareOutput("layer2_out", layers[2].parts.gain)
  ctx.ports.declareOutput("layer3_out", layers[3].parts.gain)
  ctx.ports.declareOutput("layer4_out", layers[4].parts.gain)
  
  -- Declare input ports other slots can feed into
  ctx.ports.declareInput("layer1_rec", layers[1].parts.input)
  
  return {
    ports = {
      inputs = {"layer1_rec"},
      outputs = {"layer1_out", "layer2_out", "layer3_out", "layer4_out"}
    }
  }
end
```

### Cross-Slot Connection

```lua
-- Slot B (Synth) connects to Slot A's ports
function buildPlugin(ctx)
  local synth = buildSynth(ctx)
  
  -- Get port reference (works across slots)
  local layerInput = ctx.ports.getInput("default", "layer1_rec")
  local layerOutput = ctx.ports.getOutput("default", "layer1_out")
  
  -- Route synth to looper input
  ctx.graph.connect(synth.output, layerInput)
  
  -- Route looper output through synth FX
  ctx.graph.connect(layerOutput, synth.filter)
  
  return {
    ports = {
      inputs = {"midi_in"},
      outputs = {"main_out"}
    }
  }
end
```

---

## C++ Implementation

### SlotPortRegistry

```cpp
class SlotPortRegistry {
public:
    // Key: "slotName/portName" -> node weak_ptr
    std::unordered_map<std::string, std::weak_ptr<IPrimitiveNode>> outputPorts;
    std::unordered_map<std::string, std::weak_ptr<IPrimitiveNode>> inputPorts;
    
    // Called during buildPlugin across all slots
    void registerOutput(const std::string& slot, const std::string& name, 
                        std::shared_ptr<IPrimitiveNode> node);
    void registerInput(const std::string& slot, const std::string& name,
                       std::shared_ptr<IPrimitiveNode> node);
    
    // Resolved by other slots during their buildPlugin
    std::shared_ptr<IPrimitiveNode> getOutput(const std::string& slot, 
                                               const std::string& name);
    std::shared_ptr<IPrimitiveNode> getInput(const std::string& slot,
                                              const std::string& name);
};
```

### Graph Merging in BehaviorCoreProcessor

```cpp
void BehaviorCoreProcessor::rebuildMergedGraph() {
    auto mergedGraph = std::make_shared<PrimitiveGraph>();
    
    // Collect all nodes from all slots
    for (auto& [slotName, slot] : dspSlots) {
        slot->addNodesToGraph(mergedGraph);
    }
    dspScriptHost->addNodesToGraph(mergedGraph);
    
    // Collect all connections (including cross-slot port connections)
    for (auto& [slotName, slot] : dspSlots) {
        slot->addConnectionsToGraph(mergedGraph);
    }
    dspScriptHost->addConnectionsToGraph(mergedGraph);
    
    // Single compile for all slots
    auto newRuntime = compileGraphRuntime(*mergedGraph, sampleRate, blockSize, 2);
    requestGraphRuntimeSwap(std::move(newRuntime));
}
```

### Lua Bindings

```cpp
// In DSPPluginScriptHost::bindLua()
sol::table ports = lua.create_table();
ports["declareOutput"] = [this](const std::string& name, 
                                 std::shared_ptr<IPrimitiveNode> node) {
    portRegistry_->registerOutput(slotName_, name, node);
};
ports["declareInput"] = [this](const std::string& name,
                                std::shared_ptr<IPrimitiveNode> node) {
    portRegistry_->registerInput(slotName_, name, node);
};
ports["getOutput"] = [this](const std::string& slot, const std::string& name) {
    return portRegistry_->getOutput(slot, name);  // weak_ptr promoted
};
ports["getInput"] = [this](const std::string& slot, const std::string& name) {
    return portRegistry_->getInput(slot, name);
};
ctx["ports"] = ports;
```

---

## Multitrack Routing Patterns

### 1. Traditional DAW Tracks

```lua
-- SLOT: "track_n" (template for N tracks)
function buildPlugin(ctx)
  local input = ctx.ports.getInput("inputs", "host_in")
  local recArm = ctx.params.create("/track/1/rec_arm", {type="bool"})
  
  local layer = ctx.bundles.LoopLayer.new({channels=2})
  
  -- Record from input when armed
  if recArm.value then
    ctx.graph.connect(input, layer.parts.input)
  end
  
  -- FX chain
  local eq = ctx.primitives.EQNode.new()
  local comp = ctx.primitives.CompressorNode.new()
  
  ctx.graph.connect(layer.parts.gain, eq)
  ctx.graph.connect(eq, comp)
  
  -- Output to master bus
  ctx.ports.declareOutput("main", comp)
  
  return {ports={outputs={"main"}}}
end
```

### 2. Send/Return Buses

```lua
-- SLOT: "reverb_bus"
function buildPlugin(ctx)
  -- Multiple inputs summed
  local mixer = ctx.primitives.MixerNode.new()
  
  -- Declare input that any track can send to
  ctx.ports.declareInput("send", mixer)
  
  local reverb = ctx.primitives.ReverbNode.new()
  ctx.graph.connect(mixer, reverb)
  
  -- Return to tracks
  ctx.ports.declareOutput("return", reverb)
  
  return {ports={inputs={"send"}, outputs={"return"}}}
end

-- In track slot:
local reverbSend = ctx.primitives.GainNode.new(2)
reverbSend:setGain(0.3)  -- send level
ctx.graph.connect(trackOutput, reverbSend)
ctx.graph.connect(reverbSend, ctx.ports.getInput("reverb_bus", "send"))

local reverbReturn = ctx.ports.getOutput("reverb_bus", "return")
local returnMixer = ctx.primitives.MixerNode.new()
ctx.graph.connect(trackOutput, returnMixer, 0, 0)  -- dry
ctx.graph.connect(reverbReturn, returnMixer, 0, 1)  -- wet
```

### 3. Sidechain Routing

```lua
-- Kick drum track sends to compressor sidechain
local kickDetector = ctx.primitives.EnvelopeFollowerNode.new()
ctx.graph.connect(kickOutput, kickDetector)

-- Declare as sidechain output
ctx.ports.declareOutput("sidechain", kickDetector)

-- Bass track uses it
local bassComp = ctx.primitives.CompressorNode.new()
local sidechainIn = ctx.ports.getOutput("kick_track", "sidechain")
bassComp:setSidechainInput(sidechainIn)
```

### 4. Feedback Loops (with single-sample delay)

```lua
-- Karplus-Strong style physical modeling
local delay = ctx.primitives.StereoDelayNode.new()
local filter = ctx.primitives.SVFNode.new()
local mixer = ctx.primitives.MixerNode.new()

-- Exciter input
ctx.ports.declareInput("exciter", mixer)

-- Feedback loop: delay → filter → back to delay
ctx.graph.connect(mixer, delay)
ctx.graph.connect(delay, filter)
-- Feedback connection (handled specially in GraphRuntime for 1-sample delay)
ctx.graph.connectFeedback(filter, mixer, {delay=1})

ctx.ports.declareOutput("out", delay)
```

---

## Native Performance Characteristics

| Aspect | Current (Single Slot) | With Port System (Multi-Slot) |
|--------|----------------------|-------------------------------|
| **Process call** | One `GraphRuntime::process()` | Same - still one runtime |
| **Node count** | 50 nodes | 200+ nodes (all slots merged) |
| **Cache efficiency** | Good | Same - linear traversal |
| **Lock-free** | Yes | Yes - no locks added |
| **Cross-slot latency** | N/A (can't do it) | 0 samples (same graph) |
| **Reconfiguration** | Reload whole script | Reload single slot, recompile merged |
| **Memory** | Pre-allocated per node | Same - just more nodes |

---

## Dynamic Reconfiguration Flow

When you change routing dynamically:

```
Message Thread (non-RT):
1. Lua: ctx.graph.connect(A, B)  -- adds connection to slot's graph builder
2. Lua: requestGraphRebuild()    -- signals host
3. C++: Collect nodes from all slots
4. C++: Compile new GraphRuntime (topological sort, allocate buffers)
5. C++: atomic swap to new runtime

Audio Thread:
- Seamlessly switches to new graph at block boundary
- Old runtime queued for deletion
```

**Cost:** ~1-5ms for 100-node graph on modern CPU. **Glitchless** due to atomic swap.

---

## What This Unlocks

| Feature | Implementation |
|---------|---------------|
| **Track freezing/bouncing** | Route track output to offline capture node |
| **Track folders/groups** | Slot with mixer that submixes child tracks |
| **VST hosting** | New node type that wraps VST, lives in slot |
| **Parallel processing** | Split/merge nodes for multiband/M/S |
| **Modular synthesis** | Each slot is a "module", ports are patch points |
| **Non-linear routing** | Feedback, recursion, generative patches |

---

## Implementation Phases

| Phase | Work | Est |
|-------|------|-----|
| 1 | `ctx.ports.declareInput/Output()` Lua API | 1 day |
| 2 | `SlotPortRegistry` C++ implementation | 2 days |
| 3 | Graph merging in `BehaviorCoreProcessor` | 2 days |
| 4 | `ctx.ports.getInput/Output()` cross-slot resolution | 1 day |
| 5 | Refactor Main project to use ports | 1 day |

**Total: ~1 week for proper multi-slot routing.**

---

## Bottom Line

This architecture provides **native DAW-level routing** with:

- **Zero overhead** cross-slot connections (same graph)
- **Dynamic reconfiguration** (recompile on change)
- **Modular architecture** (slots as track/bus/plugin units)
- **Lock-free real-time** (unchanged from current)

The Lua becomes **declarative routing configuration**. The compiled `GraphRuntime` is the **native execution engine**.

---

## Related Documents

- `MIDI_IMPLEMENTATION.md` - MIDI system that integrates with this architecture
- `README.md` - Core architecture overview
- `UserScripts/projects/Main/dsp/` - Current DSP scripts that would be refactored

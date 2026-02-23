# Grain Freeze - Development Notes

## Build Commands
```bash
cd build && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j$(nproc)
```

## Test
```bash
./build/GrainFreeze_artefacts/Release/Standalone/Grain\ Freeze
```

## JUCE Pitfalls

### resized() called before constructor completes
JUCE's `AudioProcessorEditor` base class calls `resized()` during construction, BEFORE derived class members are initialized. 

**Fix:** Call `resized()` manually at the end of your constructor, or add null checks:
```cpp
void resized() {
    if (sliders.isEmpty()) return;  // Not constructed yet
    // ... layout code
}
```

### Component visibility
Always call `addAndMakeVisible()` after creating components, or they won't render.

## Debug Logging
Debug logs are written to `/tmp/grainfreeze_debug.log` when DEBUG is defined.

## Architecture
- `GranularEngine.h` - Circular buffer, grain voices, playback engine
- `EffectsProcessor.h` - Reverb and shimmer effects
- `PluginProcessor.cpp` - Audio/MIDI processing, parameter management
- `PluginEditor.cpp` - UI components and layout

cmake_minimum_required(VERSION 3.22)

project(GRAIN_FREEZE VERSION 1.0.0)

add_subdirectory(/home/shamanic/dev/JUCE JUCE)

juce_add_plugin(GrainFreeze
    VERSION 1.0.0
    PLUGIN_MANUFACTURER_CODE Shmc
    PLUGIN_CODE GrFr
    FORMATS VST3 Standalone
    PRODUCT_NAME "Grain Freeze"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT TRUE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD FALSE)

target_sources(GrainFreeze
    PRIVATE
        PluginEditor.cpp
        PluginProcessor.cpp
        GranularEngine.h
        EffectsProcessor.h)

target_compile_definitions(GrainFreeze
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries(GrainFreeze
    PRIVATE
        juce::juce_audio_utils
        juce::juce_dsp
        juce::juce_gui_extra
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

juce_add_plugin(Looper
    VERSION 1.0.0
    PLUGIN_MANUFACTURER_CODE Shmc
    PLUGIN_CODE Lopr
    FORMATS VST3 Standalone
    PRODUCT_NAME "Looper"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE)

target_sources(Looper
    PRIVATE
        LooperProcessor.cpp
        LooperProcessor.h
        LooperEditor.cpp
        LooperEditor.h
        LooperLayer.h
        primitives/dsp/CaptureBuffer.h
        primitives/dsp/LoopBuffer.h
        primitives/dsp/Playhead.h
        primitives/dsp/TempoInference.h
        primitives/dsp/Quantizer.h
        primitives/ui/Canvas.h
        primitives/ui/CanvasStyle.h)

target_compile_definitions(Looper
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries(Looper
    PRIVATE
        juce::juce_audio_utils
        juce::juce_gui_extra
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

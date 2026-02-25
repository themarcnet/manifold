cmake_minimum_required(VERSION 3.22)

project(GRAIN_FREEZE VERSION 1.0.0)

include(FetchContent)

add_subdirectory(/home/shamanic/dev/JUCE JUCE)

# --- Lua 5.4 (system) ---
find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA REQUIRED IMPORTED_TARGET lua)

# --- sol2 (header-only Lua bindings) ---
FetchContent_Declare(
    sol2
    GIT_REPOSITORY https://github.com/ThePhD/sol2.git
    GIT_TAG        develop
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(sol2)

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
        GrainFreeze_Prototype/PluginEditor.cpp
        GrainFreeze_Prototype/PluginProcessor.cpp
        GrainFreeze_Prototype/GranularEngine.h
        GrainFreeze_Prototype/EffectsProcessor.h)

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
        looper/engine/LooperProcessor.cpp
        looper/engine/LooperProcessor.h
        looper/ui/LooperEditor.cpp
        looper/ui/LooperEditor.h
        looper/engine/LooperLayer.h
        looper/primitives/dsp/CaptureBuffer.h
        looper/primitives/dsp/LoopBuffer.h
        looper/primitives/dsp/Playhead.h
        looper/primitives/dsp/TempoInference.h
        looper/primitives/dsp/Quantizer.h
        looper/primitives/control/ControlServer.h
        looper/primitives/control/ControlServer.cpp
        looper/primitives/control/OSCServer.h
        looper/primitives/control/OSCServer.cpp
        looper/primitives/control/OSCEndpointRegistry.h
        looper/primitives/control/OSCEndpointRegistry.cpp
        looper/primitives/control/EndpointResolver.h
        looper/primitives/control/EndpointResolver.cpp
        looper/primitives/control/OSCQuery.h
        looper/primitives/control/OSCQuery.cpp
        looper/primitives/ui/Canvas.h
        looper/primitives/ui/Canvas.cpp
        looper/primitives/ui/CanvasStyle.h
        looper/primitives/scripting/LuaEngine.h
        looper/primitives/scripting/LuaEngine.cpp
        looper/primitives/control/OSCSettingsPersistence.h
        looper/primitives/control/OSCSettingsPersistence.cpp)

target_include_directories(Looper PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_compile_definitions(Looper
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries(Looper
    PRIVATE
        juce::juce_audio_utils
        juce::juce_audio_formats
        juce::juce_dsp
        juce::juce_gui_extra
        juce::juce_opengl
        PkgConfig::LUA
        sol2::sol2
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

# Headless test harness - no GUI, no audio device, just the processor + ControlServer
add_executable(LooperHeadless looper/headless/LooperHeadless.cpp)

add_executable(LuaEngineMockHarness looper/headless/LuaEngineMockHarness.cpp)

add_executable(EndpointResolverHarness looper/headless/EndpointResolverHarness.cpp)

add_executable(ControlCommandQueueHarness looper/headless/ControlCommandQueueHarness.cpp)

add_executable(CanonicalCommandHarness looper/headless/CanonicalCommandHarness.cpp)

target_include_directories(LooperHeadless
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(LooperHeadless
    PRIVATE
        Looper
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(LuaEngineMockHarness
    PRIVATE
        Looper
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(EndpointResolverHarness
    PRIVATE
        Looper
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(ControlCommandQueueHarness
    PRIVATE
        Looper
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(CanonicalCommandHarness
    PRIVATE
        Looper
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_compile_definitions(LooperHeadless
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_compile_definitions(LuaEngineMockHarness
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_compile_definitions(EndpointResolverHarness
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_compile_definitions(ControlCommandQueueHarness
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

target_compile_definitions(CanonicalCommandHarness
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

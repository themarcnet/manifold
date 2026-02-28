cmake_minimum_required(VERSION 3.22)

project(MANIFOLD VERSION 1.0.0)

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

# --- Ableton Link ---
FetchContent_Declare(
    ableton_link
    GIT_REPOSITORY https://github.com/Ableton/link.git
    GIT_TAG        Link-3.1.2
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(ableton_link)
set(LINK_BUILD_ASIO ON CACHE BOOL "" FORCE)
set(LINK_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LINK_BUILD_TESTS OFF CACHE BOOL "" FORCE)

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

# --- Manifold (formerly LooperPrimitives) ---
# BehaviorCore-based looper runtime

set(MANIFOLD_DSP_SOURCES
    looper/primitives/dsp/CaptureBuffer.h
    looper/primitives/dsp/LoopBuffer.h
    looper/primitives/dsp/Playhead.h
    looper/primitives/dsp/TempoInference.h
    looper/primitives/dsp/Quantizer.h
    looper/primitives/scripting/PrimitiveGraph.h
    looper/primitives/scripting/PrimitiveGraph.cpp
    looper/primitives/scripting/GraphRuntime.h
    looper/primitives/scripting/GraphRuntime.cpp
    dsp/core/graph/PrimitiveNode.h
    dsp/core/nodes/PrimitiveNodes.h
    dsp/core/nodes/PlayheadNode.h
    dsp/core/nodes/PlayheadNode.cpp
    dsp/core/nodes/PassthroughNode.h
    dsp/core/nodes/PassthroughNode.cpp
    dsp/core/nodes/GainNode.h
    dsp/core/nodes/GainNode.cpp
    dsp/core/nodes/LoopPlaybackNode.h
    dsp/core/nodes/LoopPlaybackNode.cpp
    dsp/core/nodes/PlaybackStateGateNode.h
    dsp/core/nodes/PlaybackStateGateNode.cpp
    dsp/core/nodes/RetrospectiveCaptureNode.h
    dsp/core/nodes/RetrospectiveCaptureNode.cpp
    dsp/core/nodes/RecordStateNode.h
    dsp/core/nodes/RecordStateNode.cpp
    dsp/core/nodes/QuantizerNode.h
    dsp/core/nodes/QuantizerNode.cpp
    dsp/core/nodes/RecordModePolicyNode.h
    dsp/core/nodes/RecordModePolicyNode.cpp
    dsp/core/nodes/ForwardCommitSchedulerNode.h
    dsp/core/nodes/ForwardCommitSchedulerNode.cpp
    dsp/core/nodes/TransportStateNode.h
    dsp/core/nodes/TransportStateNode.cpp
    dsp/core/nodes/OscillatorNode.h
    dsp/core/nodes/OscillatorNode.cpp
    dsp/core/nodes/ReverbNode.h
    dsp/core/nodes/ReverbNode.cpp
    dsp/core/nodes/FilterNode.h
    dsp/core/nodes/FilterNode.cpp
    dsp/core/nodes/DistortionNode.h
    dsp/core/nodes/DistortionNode.cpp)

set(MANIFOLD_RUNTIME_SOURCES
    looper/engine/LooperLayer.h
    looper/primitives/sync/LinkSync.h
    looper/primitives/sync/LinkSync.cpp
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
    looper/primitives/control/OSCSettingsPersistence.h
    looper/primitives/control/OSCSettingsPersistence.cpp
    looper/primitives/ui/Canvas.h
    looper/primitives/ui/Canvas.cpp
    looper/primitives/ui/CanvasStyle.h
    looper/primitives/scripting/LuaEngine.h
    looper/primitives/scripting/LuaEngine.cpp
    looper/primitives/scripting/core/LuaCoreEngine.h
    looper/primitives/scripting/core/LuaCoreEngine.cpp
    looper/primitives/scripting/bindings/LuaUIBindings.h
    looper/primitives/scripting/bindings/LuaUIBindings.cpp
    looper/primitives/scripting/bindings/LuaControlBindings.h
    looper/primitives/scripting/bindings/LuaControlBindings.cpp
    looper/primitives/scripting/DSPPluginScriptHost.h
    looper/primitives/scripting/DSPPluginScriptHost.cpp)

set(MANIFOLD_CORE_SOURCES
    looper_primitives/BehaviorCoreProcessor.h
    looper_primitives/BehaviorCoreProcessor.cpp
    looper_primitives/BehaviorCoreEditor.h
    looper_primitives/BehaviorCoreEditor.cpp)

juce_add_plugin(Manifold
    VERSION 1.0.0
    PLUGIN_MANUFACTURER_CODE Shmc
    PLUGIN_CODE Mnfd
    FORMATS Standalone
    PRODUCT_NAME "Manifold"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE)

target_sources(Manifold
    PRIVATE
        ${MANIFOLD_DSP_SOURCES}
        ${MANIFOLD_RUNTIME_SOURCES}
        ${MANIFOLD_CORE_SOURCES})

target_include_directories(Manifold 
    PRIVATE 
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_compile_definitions(Manifold
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0
        ASIO_STANDALONE=1
        LINK_PLATFORM_LINUX=1)

target_link_libraries(Manifold
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

# Headless test harnesses
add_executable(ManifoldHeadless looper/headless/ManifoldHeadless.cpp)

add_executable(LuaEngineMockHarness looper/headless/LuaEngineMockHarness.cpp)

add_executable(EndpointResolverHarness looper/headless/EndpointResolverHarness.cpp)

add_executable(ControlCommandQueueHarness looper/headless/ControlCommandQueueHarness.cpp)

add_executable(CanonicalCommandHarness looper/headless/CanonicalCommandHarness.cpp)

add_executable(StateProjectionHarness looper/headless/StateProjectionHarness.cpp)

target_include_directories(ManifoldHeadless
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(ManifoldHeadless
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(LuaEngineMockHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(EndpointResolverHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(ControlCommandQueueHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(CanonicalCommandHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_link_libraries(StateProjectionHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra)

target_compile_definitions(ManifoldHeadless
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

target_compile_definitions(StateProjectionHarness
    PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0)

cmake_minimum_required(VERSION 3.22)

project(MANIFOLD VERSION 1.0.0)

include(FetchContent)

# --- JUCE (git submodule by default) ---
set(JUCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/JUCE" CACHE PATH
    "Path to JUCE checkout (default: git submodule at external/JUCE)")

if(NOT EXISTS "${JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "JUCE not found at '${JUCE_DIR}'.\n"
        "Run: git submodule update --init --recursive\n"
        "Or configure with: -DJUCE_DIR=/path/to/JUCE")
endif()

add_subdirectory("${JUCE_DIR}" JUCE)

# --- Lua 5.4 ---
option(MANIFOLD_BUILD_LUA "Build Lua 5.4 from source instead of using system install" OFF)
set(MANIFOLD_LUA_TARGET "")

if(MANIFOLD_BUILD_LUA)
    # Build Lua from source (for Windows or when no system Lua is available)
    FetchContent_Declare(
        lua_src
        URL https://www.lua.org/ftp/lua-5.4.7.tar.gz
        URL_HASH SHA256=9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30
    )
    FetchContent_MakeAvailable(lua_src)

    # Build Lua as a static library
    set(LUA_SRC_DIR "${lua_src_SOURCE_DIR}/src")
    file(GLOB LUA_CORE_SOURCES "${LUA_SRC_DIR}/*.c")
    # Remove lua.c and luac.c (standalone interpreters)
    list(FILTER LUA_CORE_SOURCES EXCLUDE REGEX "(lua|luac)\\.c$")

    add_library(lua_static STATIC ${LUA_CORE_SOURCES})
    target_include_directories(lua_static PUBLIC "${LUA_SRC_DIR}")
    if(UNIX)
        target_compile_definitions(lua_static PRIVATE LUA_USE_POSIX)
        target_link_libraries(lua_static PRIVATE m dl)
    endif()
    set(MANIFOLD_LUA_TARGET lua_static)
    message(STATUS "Building Lua from source")
else()
    # Preferred path on macOS/vcpkg and modern Linux installs
    find_package(Lua 5.4 QUIET)
    if(Lua_FOUND)
        if(TARGET Lua::Lua)
            set(MANIFOLD_LUA_TARGET Lua::Lua)
        elseif(LUA_LIBRARIES)
            add_library(manifold_lua_fallback INTERFACE)
            if(DEFINED LUA_INCLUDE_DIRS)
                target_include_directories(manifold_lua_fallback INTERFACE ${LUA_INCLUDE_DIRS})
            elseif(DEFINED LUA_INCLUDE_DIR)
                target_include_directories(manifold_lua_fallback INTERFACE ${LUA_INCLUDE_DIR})
            endif()
            target_link_libraries(manifold_lua_fallback INTERFACE ${LUA_LIBRARIES})
            set(MANIFOLD_LUA_TARGET manifold_lua_fallback)
        endif()
    endif()

    # Fallback for Linux environments that rely on pkg-config
    if(NOT MANIFOLD_LUA_TARGET)
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(LUA54 QUIET IMPORTED_TARGET lua5.4)
            if(TARGET PkgConfig::LUA54)
                set(MANIFOLD_LUA_TARGET PkgConfig::LUA54)
            else()
                pkg_check_modules(LUA QUIET IMPORTED_TARGET lua)
                if(TARGET PkgConfig::LUA)
                    set(MANIFOLD_LUA_TARGET PkgConfig::LUA)
                endif()
            endif()
        endif()
    endif()

    if(NOT MANIFOLD_LUA_TARGET)
        message(FATAL_ERROR
            "Could not find Lua 5.4.\n"
            "Linux: install lua5.4 dev package (or pkg-config + lua5.4).\n"
            "Windows: configure with -DMANIFOLD_BUILD_LUA=ON to build from source.")
    endif()
endif()

message(STATUS "Using Lua target: ${MANIFOLD_LUA_TARGET}")

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

set(MANIFOLD_LINK_PLATFORM_DEFINE "")
if(WIN32)
    set(MANIFOLD_LINK_PLATFORM_DEFINE LINK_PLATFORM_WINDOWS=1)
elseif(APPLE)
    set(MANIFOLD_LINK_PLATFORM_DEFINE LINK_PLATFORM_MACOSX=1)
elseif(UNIX)
    set(MANIFOLD_LINK_PLATFORM_DEFINE LINK_PLATFORM_LINUX=1)
else()
    message(FATAL_ERROR "Unsupported platform for Ableton Link platform defines")
endif()

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
    manifold/primitives/dsp/CaptureBuffer.h
    manifold/primitives/dsp/LoopBuffer.h
    manifold/primitives/dsp/Playhead.h
    manifold/primitives/dsp/TempoInference.h
    manifold/primitives/dsp/Quantizer.h
    manifold/primitives/scripting/PrimitiveGraph.h
    manifold/primitives/scripting/PrimitiveGraph.cpp
    manifold/primitives/scripting/GraphRuntime.h
    manifold/primitives/scripting/GraphRuntime.cpp
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
    dsp/core/nodes/DistortionNode.cpp
    dsp/core/nodes/SVFNode.h
    dsp/core/nodes/SVFNode.cpp
    dsp/core/nodes/StereoDelayNode.h
    dsp/core/nodes/StereoDelayNode.cpp
    dsp/core/nodes/CompressorNode.h
    dsp/core/nodes/CompressorNode.cpp
    dsp/core/nodes/WaveShaperNode.h
    dsp/core/nodes/WaveShaperNode.cpp
    dsp/core/nodes/ChorusNode.h
    dsp/core/nodes/ChorusNode.cpp
    dsp/core/nodes/StereoWidenerNode.h
    dsp/core/nodes/StereoWidenerNode.cpp
    dsp/core/nodes/PhaserNode.h
    dsp/core/nodes/PhaserNode.cpp
    dsp/core/nodes/GranulatorNode.h
    dsp/core/nodes/GranulatorNode.cpp
    dsp/core/nodes/StutterNode.h
    dsp/core/nodes/StutterNode.cpp
    dsp/core/nodes/ShimmerNode.h
    dsp/core/nodes/ShimmerNode.cpp
    dsp/core/nodes/MultitapDelayNode.h
    dsp/core/nodes/MultitapDelayNode.cpp
    dsp/core/nodes/PitchShifterNode.h
    dsp/core/nodes/PitchShifterNode.cpp
    dsp/core/nodes/TransientShaperNode.h
    dsp/core/nodes/TransientShaperNode.cpp
    dsp/core/nodes/RingModulatorNode.h
    dsp/core/nodes/RingModulatorNode.cpp
    dsp/core/nodes/BitCrusherNode.h
    dsp/core/nodes/BitCrusherNode.cpp
    dsp/core/nodes/FormantFilterNode.h
    dsp/core/nodes/FormantFilterNode.cpp
    dsp/core/nodes/ReverseDelayNode.h
    dsp/core/nodes/ReverseDelayNode.cpp
    dsp/core/nodes/EnvelopeFollowerNode.h
    dsp/core/nodes/EnvelopeFollowerNode.cpp
    dsp/core/nodes/PitchDetectorNode.h
    dsp/core/nodes/PitchDetectorNode.cpp
    dsp/core/nodes/CrossfaderNode.h
    dsp/core/nodes/CrossfaderNode.cpp
    dsp/core/nodes/MixerNode.h
    dsp/core/nodes/MixerNode.cpp
    dsp/core/nodes/NoiseGeneratorNode.h
    dsp/core/nodes/NoiseGeneratorNode.cpp
    dsp/core/nodes/MSEncoderNode.h
    dsp/core/nodes/MSEncoderNode.cpp
    dsp/core/nodes/EQNode.h
    dsp/core/nodes/EQNode.cpp
    dsp/core/nodes/LimiterNode.h
    dsp/core/nodes/LimiterNode.cpp
    dsp/core/nodes/SpectrumAnalyzerNode.h
    dsp/core/nodes/SpectrumAnalyzerNode.cpp
    dsp/core/nodes/MidiVoiceNode.h
    dsp/core/nodes/MidiVoiceNode.cpp
    dsp/core/nodes/MidiInputNode.h
    dsp/core/nodes/MidiInputNode.cpp)

set(MANIFOLD_RUNTIME_SOURCES
    manifold/engine/ManifoldLayer.h
    manifold/primitives/sync/LinkSync.h
    manifold/primitives/sync/LinkSync.cpp
    manifold/primitives/control/ControlServer.h
    manifold/primitives/control/ControlServer.cpp
    manifold/primitives/control/OSCServer.h
    manifold/primitives/control/OSCServer.cpp
    manifold/primitives/control/OSCEndpointRegistry.h
    manifold/primitives/control/OSCEndpointRegistry.cpp
    manifold/primitives/control/EndpointResolver.h
    manifold/primitives/control/EndpointResolver.cpp
    manifold/primitives/control/OSCQuery.h
    manifold/primitives/control/OSCQuery.cpp
    manifold/primitives/control/OSCSettingsPersistence.h
    manifold/primitives/control/OSCSettingsPersistence.cpp
    manifold/primitives/ui/Canvas.h
    manifold/primitives/ui/Canvas.cpp
    manifold/primitives/ui/CanvasStyle.h
    manifold/primitives/scripting/LuaEngine.h
    manifold/primitives/scripting/LuaEngine.cpp
    manifold/primitives/scripting/ScriptableProcessor.h
    manifold/primitives/scripting/ScriptableProcessor.cpp
    manifold/primitives/scripting/core/LuaCoreEngine.h
    manifold/primitives/scripting/core/LuaCoreEngine.cpp
    manifold/primitives/scripting/bindings/LuaUIBindings.h
    manifold/primitives/scripting/bindings/LuaUIBindings.cpp
    manifold/primitives/scripting/bindings/LuaControlBindings.h
    manifold/primitives/scripting/bindings/LuaControlBindings.cpp
    manifold/primitives/scripting/bindings/LuaMidiBindings.cpp
    manifold/primitives/scripting/DSPPluginScriptHost.h
    manifold/primitives/scripting/DSPPluginScriptHost.cpp
    manifold/primitives/midi/MidiEvent.h
    manifold/primitives/midi/MidiEvent.cpp
    manifold/primitives/midi/MidiManager.h
    manifold/primitives/midi/MidiManager.cpp
    manifold/primitives/core/Settings.h
    manifold/primitives/core/Settings.cpp)

set(MANIFOLD_CORE_SOURCES
    manifold/core/BehaviorCoreProcessor.h
    manifold/core/BehaviorCoreProcessor.cpp
    manifold/core/BehaviorCoreEditor.h
    manifold/core/BehaviorCoreEditor.cpp)

juce_add_plugin(Manifold
    VERSION 1.0.0
    PLUGIN_MANUFACTURER_CODE Shmc
    PLUGIN_CODE Mnfd
    FORMATS Standalone VST3
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
        ${MANIFOLD_LINK_PLATFORM_DEFINE})

target_link_libraries(Manifold
    PRIVATE
        juce::juce_audio_utils
        juce::juce_audio_formats
        juce::juce_dsp
        juce::juce_gui_extra
        juce::juce_opengl
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

# Copy ALL Lua UI files to Manifold Standalone output directory
add_custom_command(TARGET Manifold POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/manifold/ui
        $<TARGET_FILE_DIR:Manifold>
    COMMAND ${CMAKE_COMMAND} -E rm -f
        $<TARGET_FILE_DIR:Manifold>/looper_widgets.lua
        $<TARGET_FILE_DIR:Manifold>/looper_ui_experimental.lua
        $<TARGET_FILE_DIR:Manifold>/looper_settings_ui.lua
    COMMENT "Copying Lua UI files for Manifold Standalone"
)

# Copy ALL Lua UI files to Manifold VST3 bundle (inside .vst3 next to .so)
add_custom_command(TARGET Manifold_VST3 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/manifold/ui
        $<TARGET_FILE_DIR:Manifold_VST3>
    COMMAND ${CMAKE_COMMAND} -E rm -f
        $<TARGET_FILE_DIR:Manifold_VST3>/looper_widgets.lua
        $<TARGET_FILE_DIR:Manifold_VST3>/looper_ui_experimental.lua
        $<TARGET_FILE_DIR:Manifold_VST3>/looper_settings_ui.lua
    COMMENT "Copying Lua UI files for Manifold VST3"
)

# Headless test harnesses
add_executable(ManifoldHeadless manifold/headless/ManifoldHeadless.cpp)

add_executable(LuaEngineMockHarness manifold/headless/LuaEngineMockHarness.cpp)

add_executable(EndpointResolverHarness manifold/headless/EndpointResolverHarness.cpp)

add_executable(ControlCommandQueueHarness manifold/headless/ControlCommandQueueHarness.cpp)

add_executable(CanonicalCommandHarness manifold/headless/CanonicalCommandHarness.cpp)

add_executable(StateProjectionHarness manifold/headless/StateProjectionHarness.cpp)

target_include_directories(ManifoldHeadless
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(ManifoldHeadless
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

target_include_directories(LuaEngineMockHarness
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(LuaEngineMockHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

target_include_directories(EndpointResolverHarness
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(EndpointResolverHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

target_include_directories(ControlCommandQueueHarness
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(ControlCommandQueueHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

target_include_directories(CanonicalCommandHarness
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(CanonicalCommandHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

target_include_directories(StateProjectionHarness
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_link_libraries(StateProjectionHarness
    PRIVATE
        Manifold
        juce::juce_audio_processors
        juce::juce_audio_formats
        juce::juce_audio_utils
        juce::juce_gui_extra
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2)

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

# --- Test Plugin: Tempus ---
# Minimal plugin demonstrating:
# - ScriptableProcessor inheritance
# - Lua UI framework
# - Ableton Link integration
# - VST parameter exposure
# - First loop tempo detection (no DSP)

juce_add_plugin(Tempus
    VERSION 1.0.0
    PLUGIN_MANUFACTURER_CODE Fltp
    PLUGIN_CODE FLTP
    FORMATS VST3 Standalone
    PRODUCT_NAME "Tempus"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE)

target_sources(Tempus
    PRIVATE
        ${MANIFOLD_DSP_SOURCES}
        ${MANIFOLD_RUNTIME_SOURCES}
        test_plugins/Tempus/TempusPlugin.cpp
        test_plugins/Tempus/TempusEditor.cpp)

target_include_directories(Tempus
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${ableton_link_SOURCE_DIR}/include
        ${ableton_link_SOURCE_DIR}/modules/asio-standalone/asio/include)

target_compile_definitions(Tempus
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0
        JUCE_DISPLAY_SPLASH_SCREEN=0
        ASIO_STANDALONE=1
        ${MANIFOLD_LINK_PLATFORM_DEFINE})

target_link_libraries(Tempus
    PRIVATE
        juce::juce_audio_utils
        juce::juce_audio_formats
        juce::juce_dsp
        juce::juce_gui_extra
        juce::juce_opengl
        ${MANIFOLD_LUA_TARGET}
        sol2::sol2
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags)

# Copy Lua UI files to Tempus Standalone output directory
add_custom_command(TARGET Tempus POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/test_plugins/Tempus/firstloop_ui.lua
        $<TARGET_FILE_DIR:Tempus>/firstloop_ui.lua
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/test_plugins/Tempus/ui_widgets.lua
        $<TARGET_FILE_DIR:Tempus>/ui_widgets.lua
    COMMAND ${CMAKE_COMMAND} -E rm -f
        $<TARGET_FILE_DIR:Tempus>/looper_widgets.lua
    COMMENT "Copying Lua UI files for Tempus Standalone"
)

# Copy Lua UI files to Tempus VST3 bundle (inside .vst3 next to .so)
add_custom_command(TARGET Tempus_VST3 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/test_plugins/Tempus/firstloop_ui.lua
        $<TARGET_FILE_DIR:Tempus_VST3>/firstloop_ui.lua
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/test_plugins/Tempus/ui_widgets.lua
        $<TARGET_FILE_DIR:Tempus_VST3>/ui_widgets.lua
    COMMAND ${CMAKE_COMMAND} -E rm -f
        $<TARGET_FILE_DIR:Tempus_VST3>/looper_widgets.lua
    COMMENT "Copying Lua UI files for Tempus VST3"
)

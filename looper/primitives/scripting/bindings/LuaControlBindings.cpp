#include "LuaControlBindings.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "../ScriptableProcessor.h"
#include "../../control/CommandParser.h"
#include "../../control/ControlServer.h"
#include "../../control/OSCEndpointRegistry.h"
#include "../../control/OSCServer.h"

#include <juce_core/juce_core.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include <cstdio>
#include <map>
#include <mutex>
#include <vector>

// ============================================================================
// Binding Registration
// ============================================================================

void LuaControlBindings::registerBindings(LuaCoreEngine& engine,
                                          ScriptableProcessor* processor) {
    auto& lua = engine.getLuaState();

    registerCommandBindings(lua, processor);
    registerOSCBindings(lua, processor);
    registerEventBindings(lua, processor);
    registerWaveformBindings(lua, processor);
    registerUtilityBindings(lua, processor);
}

void LuaControlBindings::registerCommandBindings(sol::state& lua,
                                                 ScriptableProcessor* processor) {
    // command() function - routes through CommandParser
    lua["command"] = [processor](sol::variadic_args va) {
        if (!processor || va.size() == 0) return;

        // Build command string from variadic args
        std::string cmdStr;
        for (size_t i = 0; i < va.size(); ++i) {
            if (i > 0) cmdStr += " ";
            auto arg = va[i];
            if (arg.get_type() == sol::type::number) {
                cmdStr += std::to_string(arg.get<float>());
            } else {
                cmdStr += arg.get<std::string>();
            }
        }

        // Parse using CommandParser
        auto result = CommandParser::parse(
            cmdStr,
            processor ? &processor->getEndpointRegistry() : nullptr);

        if (result.usedLegacySyntax) {
            static std::atomic<int> legacySyntaxWarnings{0};
            const int count =
                legacySyntaxWarnings.fetch_add(1, std::memory_order_relaxed) + 1;
            if (count <= 5 || (count % 100) == 0) {
                fprintf(stderr,
                        "[LuaControl] deprecated legacy command syntax '%s' used "
                        "(count=%d). Prefer canonical SET/GET/TRIGGER paths.\n",
                        result.legacyVerb.c_str(), count);
            }
        }

        switch (result.kind) {
        case ParseResult::Kind::Enqueue:
            processor->postControlCommandPayload(result.command);
            break;
        case ParseResult::Kind::NoOpWarning:
            break;
        case ParseResult::Kind::Error:
            fprintf(stderr, "[LuaControl] command error: %s (input: %s)\n",
                    result.errorMessage.c_str(), cmdStr.c_str());
            break;
        default:
            // Queries and other types not meaningful from Lua
            break;
        }
    };

    // Direct parameter access
    lua["setParam"] = [processor](const std::string& path, float value) -> bool {
        if (!processor) return false;
        return processor->setParamByPath(path, value);
    };

    lua["getParam"] = [processor](const std::string& path) -> float {
        if (!processor) return 0.0f;
        return processor->getParamByPath(path);
    };

    lua["hasEndpoint"] = [processor](const std::string& path) -> bool {
        if (!processor) return false;
        return processor->hasEndpoint(path);
    };

    // Direct seek (bypasses CommandParser for reliability)
    lua["seekLayer"] = [processor](int layerIdx, float normalizedPos) {
        if (!processor) return;
        if (layerIdx < 0 || layerIdx >= processor->getNumLayers()) return;
        ControlCommand cmd;
        cmd.operation = ControlOperation::Legacy;
        cmd.type = ControlCommand::Type::LayerSeek;
        cmd.intParam = layerIdx;
        cmd.floatParam = normalizedPos;
        processor->postControlCommandPayload(cmd);
    };
}

void LuaControlBindings::registerOSCBindings(sol::state& lua,
                                             ScriptableProcessor* processor) {
    auto oscTable = lua.create_table();

    // Get current settings
    oscTable["getSettings"] = [processor](sol::this_state s) -> sol::table {
        sol::state_view lua(s);
        auto result = lua.create_table();
        if (!processor) return result;

        auto& oscServer = processor->getOSCServer();
        auto settings = oscServer.getSettings();

        result["inputPort"] = settings.inputPort;
        result["queryPort"] = settings.queryPort;
        result["oscEnabled"] = settings.oscEnabled;
        result["oscQueryEnabled"] = settings.oscQueryEnabled;

        auto targets = lua.create_table();
        for (int i = 0; i < settings.outTargets.size(); ++i) {
            targets[i + 1] = settings.outTargets[i].toStdString();
        }
        result["outTargets"] = targets;

        return result;
    };

    // Send OSC message
    oscTable["send"] = [processor](const std::string& address,
                                    sol::variadic_args args) -> bool {
        if (!processor) return false;

        std::vector<juce::var> vars;
        for (auto arg : args) {
            if (arg.is<int>()) {
                vars.push_back(arg.as<int>());
            } else if (arg.is<float>()) {
                vars.push_back(arg.as<float>());
            } else if (arg.is<double>()) {
                vars.push_back(static_cast<float>(arg.as<double>()));
            } else if (arg.is<std::string>()) {
                vars.push_back(juce::String(arg.as<std::string>()));
            } else if (arg.is<bool>()) {
                vars.push_back(arg.as<bool>() ? 1 : 0);
            }
        }

        juce::String path(address.c_str());
        processor->getOSCServer().broadcast(path, vars);
        return true;
    };

    // Register callback for incoming OSC
    oscTable["onMessage"] = [processor](const std::string& address,
                                         sol::function callback) -> bool {
        if (!processor || !callback.valid()) return false;
        // Implementation would store callback and invoke when OSC received
        // For now, stub
        return true;
    };

    lua["osc"] = oscTable;
}

void LuaControlBindings::registerEventBindings(sol::state& lua,
                                               ScriptableProcessor* processor) {
    auto looperTable = lua.create_table();

    // Event registration stubs - full implementation would need callback storage
    looperTable["onTempoChanged"] = [](sol::function callback) -> bool {
        if (!callback.valid()) return false;
        // Store callback, invoke when tempo changes
        return true;
    };

    looperTable["onCommit"] = [](sol::function callback) -> bool {
        if (!callback.valid()) return false;
        return true;
    };

    looperTable["onRecordingChanged"] = [](sol::function callback) -> bool {
        if (!callback.valid()) return false;
        return true;
    };

    looperTable["onLayerStateChanged"] = [](sol::function callback) -> bool {
        if (!callback.valid()) return false;
        return true;
    };

    lua["looper"] = looperTable;

    // Ableton Link integration
    auto linkTable = lua.create_table();

    linkTable["isEnabled"] = [processor]() -> bool {
        if (!processor) return false;
        return processor->isLinkEnabled();
    };

    linkTable["setEnabled"] = [processor](bool enabled) {
        if (!processor) return;
        processor->setLinkEnabled(enabled);
    };

    linkTable["isTempoSyncEnabled"] = [processor]() -> bool {
        if (!processor) return false;
        return processor->isLinkTempoSyncEnabled();
    };

    linkTable["setTempoSyncEnabled"] = [processor](bool enabled) {
        if (!processor) return;
        processor->setLinkTempoSyncEnabled(enabled);
    };

    linkTable["getNumPeers"] = [processor]() -> int {
        if (!processor) return 0;
        return processor->getLinkNumPeers();
    };

    linkTable["isPlaying"] = [processor]() -> bool {
        if (!processor) return false;
        return processor->isLinkPlaying();
    };

    linkTable["getBeat"] = [processor]() -> double {
        if (!processor) return 0.0;
        return processor->getLinkBeat();
    };

    linkTable["getPhase"] = [processor]() -> double {
        if (!processor) return 0.0;
        return processor->getLinkPhase();
    };

    linkTable["requestTempo"] = [processor](double bpm) {
        if (!processor) return;
        processor->requestLinkTempo(bpm);
    };

    linkTable["requestStart"] = [processor]() {
        if (!processor) return;
        processor->requestLinkStart();
    };

    linkTable["requestStop"] = [processor]() {
        if (!processor) return;
        processor->requestLinkStop();
    };

    lua["link"] = linkTable;
}

void LuaControlBindings::registerWaveformBindings(sol::state& lua,
                                                  ScriptableProcessor* processor) {
    // Waveform peak data
    lua["getLayerPeaks"] = [&lua, processor](int layerIdx, int numBuckets) -> sol::table {
        auto result = lua.create_table();
        if (!processor || numBuckets <= 0) return result;

        std::vector<float> peaks;
        if (!processor->computeLayerPeaks(layerIdx, numBuckets, peaks)) {
            return result;
        }
        for (size_t i = 0; i < peaks.size(); ++i) {
            result[i + 1] = peaks[i];
        }
        return result;
    };

    lua["getCapturePeaks"] = [&lua, processor](int startAgo, int endAgo,
                                         int numBuckets) -> sol::table {
        auto result = lua.create_table();
        if (!processor || numBuckets <= 0) return result;

        std::vector<float> peaks;
        if (!processor->computeCapturePeaks(startAgo, endAgo, numBuckets, peaks)) {
            return result;
        }
        for (size_t i = 0; i < peaks.size(); ++i) {
            result[i + 1] = peaks[i];
        }
        return result;
    };

    lua["getLayerPeaksForPath"] = [&lua, processor](const std::string& pathBase,
                                               int layerIdx,
                                               int numBuckets) -> sol::table {
        auto result = lua.create_table();
        if (!processor || numBuckets <= 0) return result;

        std::vector<float> peaks;
        if (!processor->computeLayerPeaksForPath(pathBase, layerIdx, numBuckets, peaks)) {
            return result;
        }
        for (size_t i = 0; i < peaks.size(); ++i) {
            result[i + 1] = peaks[i];
        }
        return result;
    };
}

void LuaControlBindings::registerUtilityBindings(sol::state& lua,
                                                 ScriptableProcessor* processor) {
    (void)processor;  // May be used for host callbacks

    // Time for animations
    lua["getTime"] = []() -> double {
        static const auto startTime = juce::Time::getHighResolutionTicks();
        return juce::Time::highResolutionTicksToSeconds(
            juce::Time::getHighResolutionTicks() - startTime);
    };

    // List available UI scripts in directory
    lua["listUiScripts"] = [](sol::this_state s) -> sol::table {
        sol::state_view lua(s);
        return lua.create_table();  // Stub - needs implementation
    };

    // Switch UI script
    lua["switchUiScript"] = [](const std::string& path) {
        (void)path;  // Stub - needs implementation
    };

    // Clipboard access
    lua["setClipboardText"] = [](const std::string& text) -> bool {
        juce::SystemClipboard::copyTextToClipboard(juce::String(text));
        return true;
    };

    lua["getClipboardText"] = []() -> std::string {
        return juce::SystemClipboard::getTextFromClipboard().toStdString();
    };

    // File utilities
    lua["writeTextFile"] = [](const std::string& path,
                               const std::string& text) -> bool {
        juce::File outFile(path);
        return outFile.replaceWithText(juce::String(text), false, false, "\n");
    };
}

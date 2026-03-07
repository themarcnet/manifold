#include "LuaControlBindings.h"

// sol2 requires Lua headers before inclusion
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include "../DSPPrimitiveWrappers.h"
#include "../ScriptableProcessor.h"
#include "../PrimitiveGraph.h"
#include "dsp/core/nodes/PrimitiveNodes.h"
#include "../../control/CommandParser.h"
#include "../../control/ControlServer.h"
#include "../../control/OSCEndpointRegistry.h"
#include "../../control/OSCServer.h"
#include "../../control/OSCPacketBuilder.h"
#include "../../control/OSCSettingsPersistence.h"
#include "../../control/OSCQuery.h"
#include "../../core/Settings.h"

#include <juce_core/juce_core.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include <cstdio>
#include <map>
#include <mutex>
#include <vector>
#include <atomic>
#include <unordered_set>
#include <set>

namespace {

bool isUiScriptFile(const juce::File& script) {
    if (!script.existsAsFile()) return false;
    auto content = script.loadFileAsString();
    return content.contains("function ui_init");
}

bool isProjectManifestFile(const juce::File& file) {
    return file.existsAsFile() &&
           file.getFileName().equalsIgnoreCase("manifold.project.json5");
}

juce::String readProjectDisplayName(const juce::File& manifestFile) {
    auto json = juce::JSON::parse(manifestFile);
    if (!json.isObject()) {
        return manifestFile.getParentDirectory().getFileName();
    }

    auto* obj = json.getDynamicObject();
    if (obj == nullptr) {
        return manifestFile.getParentDirectory().getFileName();
    }

    if (obj->hasProperty("name")) {
        auto name = obj->getProperty("name").toString();
        if (name.isNotEmpty()) {
            return name;
        }
    }

    return manifestFile.getParentDirectory().getFileName();
}

} // namespace

// ============================================================================
// Binding Registration
// ============================================================================

void LuaControlBindings::registerBindings(LuaCoreEngine& engine,
                                          ILuaControlState& state) {
    auto& lua = engine.getLuaState();

    registerCommandBindings(lua, state);
    registerWaveformBindings(lua, state);
    registerDspBindings(lua, state);
    registerGraphBindings(lua, state);
    registerOSCBindings(lua, state);
    registerEventBindings(lua, state);
    registerLinkBindings(lua, state);
    registerUtilityBindings(lua, state);
    registerMidiBindings(lua, state);
}

void LuaControlBindings::registerCommandBindings(sol::state& lua,
                                                 ILuaControlState& state) {
    // ---- command() ----
    lua["command"] = [&state](sol::variadic_args va) {
        auto* processor = state.getProcessor();
        if (!processor || va.size() == 0) return;

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

        if (!result.warningCode.empty()) {
            static std::atomic<int> parserWarnings{0};
            const int count = parserWarnings.fetch_add(1, std::memory_order_relaxed) + 1;
            if (count <= 5 || (count % 100) == 0) {
                fprintf(stderr, "[LuaControl] %s: %s (count=%d)\n",
                        result.warningCode.c_str(), result.warningMessage.c_str(), count);
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
            break;
        }
    };

    lua["setParam"] = [&state](const std::string& path, float value) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->setParamByPath(path, value);
    };

    lua["getParam"] = [&state](const std::string& path) -> float {
        auto* processor = state.getProcessor();
        if (!processor) return 0.0f;
        return processor->getParamByPath(path);
    };

    lua["hasEndpoint"] = [&state](const std::string& path) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->hasEndpoint(path);
    };

    lua["listEndpoints"] = [&state, &lua](sol::optional<std::string> prefixOpt,
                                            sol::optional<bool> writableOnlyOpt,
                                            sol::optional<bool> numericOnlyOpt) -> sol::table {
        auto result = sol::table(lua, sol::create);
        auto* processor = state.getProcessor();
        if (!processor) return result;

        const std::string prefix = prefixOpt.value_or(std::string());
        const bool writableOnly = writableOnlyOpt.value_or(false);
        const bool numericOnly = numericOnlyOpt.value_or(false);

        const auto endpoints = processor->getEndpointRegistry().getAllEndpoints();
        int outIndex = 1;
        for (const auto& endpoint : endpoints) {
            const std::string path = endpoint.path.toStdString();
            if (!prefix.empty() && path.rfind(prefix, 0) != 0) {
                continue;
            }
            if (writableOnly && endpoint.access < 2) {
                continue;
            }
            if (numericOnly) {
                const std::string type = endpoint.type.toStdString();
                const bool numeric = type.find('f') != std::string::npos ||
                                     type.find('i') != std::string::npos ||
                                     type.find('d') != std::string::npos;
                if (!numeric) {
                    continue;
                }
            }

            auto item = sol::table(lua, sol::create);
            item["path"] = path;
            item["type"] = endpoint.type.toStdString();
            item["rangeMin"] = endpoint.rangeMin;
            item["rangeMax"] = endpoint.rangeMax;
            item["access"] = endpoint.access;
            item["description"] = endpoint.description.toStdString();
            item["category"] = endpoint.category.toStdString();
            result[outIndex++] = item;
        }
        return result;
    };

    lua["seekLayer"] = [&state](int layerIdx, float normalizedPos) {
        auto* processor = state.getProcessor();
        if (!processor) return;
        if (layerIdx < 0 || layerIdx >= 4) return;
        ControlCommand cmd;
        cmd.operation = ControlOperation::Legacy;
        cmd.type = ControlCommand::Type::LayerSeek;
        cmd.intParam = layerIdx;
        cmd.floatParam = normalizedPos;
        processor->postControlCommandPayload(cmd);
    };
}

void LuaControlBindings::registerWaveformBindings(sol::state& lua,
                                                  ILuaControlState& state) {
    lua["getLayerPeaks"] = [&state, &lua](int layerIdx, int numBuckets) -> sol::table {
        auto result = sol::table(lua, sol::create);
        auto* processor = state.getProcessor();
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

    lua["getLayerPeaksForPath"] = [&state, &lua](const std::string& pathBase,
                                           int layerIdx,
                                           int numBuckets) -> sol::table {
        auto result = sol::table(lua, sol::create);
        auto* processor = state.getProcessor();
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

    lua["getCapturePeaks"] = [&state, &lua](int startAgo, int endAgo,
                                      int numBuckets) -> sol::table {
        auto result = sol::table(lua, sol::create);
        auto* processor = state.getProcessor();
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
}

void LuaControlBindings::registerDspBindings(sol::state& lua,
                                             ILuaControlState& state) {
    lua["reloadDspScript"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->reloadDspScript();
    };

    lua["loadDspScript"] = [&state](const std::string& path) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->loadDspScript(juce::File(path));
    };

    lua["loadDspScriptInSlot"] = [&state](const std::string& path,
                                          const std::string& slot) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        const std::string slotName = slot.empty() ? "default" : slot;
        const bool ok = processor->loadDspScript(juce::File(path), slotName);
        if (ok && slotName != "default") {
            state.getManagedDspSlots().insert(slotName);
        }
        return ok;
    };

    lua["loadDspScriptFromString"] = [&state](const std::string& code,
                                               const std::string& sourceName) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->loadDspScriptFromString(code, sourceName);
    };

    lua["loadDspScriptFromStringInSlot"] = [&state](const std::string& code,
                                                     const std::string& sourceName,
                                                     const std::string& slot) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        const std::string slotName = slot.empty() ? "default" : slot;
        const bool ok = processor->loadDspScriptFromString(code, sourceName, slotName);
        if (ok && slotName != "default") {
            state.getManagedDspSlots().insert(slotName);
        }
        return ok;
    };

    lua["setDspSlotPersistOnUiSwitch"] = [&state](const std::string& slot,
                                                   bool persist) -> bool {
        const std::string slotName = slot.empty() ? "default" : slot;
        if (slotName == "default") return false;

        state.getManagedDspSlots().insert(slotName);
        if (persist) {
            state.getPersistentDspSlots().insert(slotName);
        } else {
            state.getPersistentDspSlots().erase(slotName);
        }
        return true;
    };

    lua["isDspSlotPersistOnUiSwitch"] = [&state](const std::string& slot) -> bool {
        const std::string slotName = slot.empty() ? "default" : slot;
        return state.getPersistentDspSlots().find(slotName) !=
               state.getPersistentDspSlots().end();
    };

    lua["unloadDspSlot"] = [&state](const std::string& slot) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        const std::string slotName = slot.empty() ? "default" : slot;
        const bool ok = processor->unloadDspSlot(slotName);
        if (slotName != "default") {
            state.getManagedDspSlots().erase(slotName);
            state.getPersistentDspSlots().erase(slotName);
        }
        return ok;
    };

    lua["isDspScriptLoaded"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isDspScriptLoaded();
    };

    lua["isDspSlotLoaded"] = [&state](const std::string& slot) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isDspSlotLoaded(slot);
    };

    lua["getDspScriptLastError"] = [&state]() -> std::string {
        auto* processor = state.getProcessor();
        if (!processor) return "";
        return processor->getDspScriptLastError();
    };
}

void LuaControlBindings::registerGraphBindings(sol::state& lua,
                                               ILuaControlState& state) {
    // ---- DSP Primitives factory ----
    lua["Primitives"] = lua.create_table();

    lua["Primitives"]["LoopBuffer"] = lua.create_table();
    lua["Primitives"]["LoopBuffer"]["new"] = [](int sizeSamples, int channels = 2) {
        auto buf = std::make_shared<dsp_primitives::LoopBufferWrapper>();
        buf->setSize(sizeSamples, channels);
        return buf;
    };

    lua["Primitives"]["Playhead"] = lua.create_table();
    lua["Primitives"]["Playhead"]["new"] = [](int length = 0) {
        auto ph = std::make_shared<dsp_primitives::PlayheadWrapper>();
        ph->setLoopLength(length);
        return ph;
    };

    lua["Primitives"]["CaptureBuffer"] = lua.create_table();
    lua["Primitives"]["CaptureBuffer"]["new"] = [](int sizeSamples, int channels = 2) {
        auto cap = std::make_shared<dsp_primitives::CaptureBufferWrapper>();
        cap->setSize(sizeSamples, channels);
        return cap;
    };

    lua["Primitives"]["Quantizer"] = lua.create_table();
    lua["Primitives"]["Quantizer"]["new"] = [](double sampleRate) {
        auto q = std::make_shared<dsp_primitives::QuantizerWrapper>();
        q->setSampleRate(sampleRate);
        return q;
    };

    // Get graph from processor
    auto* processor = state.getProcessor();
    std::shared_ptr<dsp_primitives::PrimitiveGraph> graph;
    if (processor) {
        graph = processor->getPrimitiveGraph();
    }
    if (!graph) {
        graph = std::make_shared<dsp_primitives::PrimitiveGraph>();
    }

    // Register node usertypes
    lua.new_usertype<dsp_primitives::PlayheadNode>("PlayheadNode",
        sol::constructors<std::shared_ptr<dsp_primitives::PlayheadNode>()>(),
        "setLoopLength", &dsp_primitives::PlayheadNode::setLoopLength,
        "setSpeed", &dsp_primitives::PlayheadNode::setSpeed,
        "setReversed", &dsp_primitives::PlayheadNode::setReversed,
        "play", &dsp_primitives::PlayheadNode::play,
        "pause", &dsp_primitives::PlayheadNode::pause,
        "stop", &dsp_primitives::PlayheadNode::stop,
        "getLoopLength", &dsp_primitives::PlayheadNode::getLoopLength,
        "getSpeed", &dsp_primitives::PlayheadNode::getSpeed,
        "isReversed", &dsp_primitives::PlayheadNode::isReversed,
        "isPlaying", &dsp_primitives::PlayheadNode::isPlaying,
        "getNormalizedPosition", &dsp_primitives::PlayheadNode::getNormalizedPosition
    );

    lua.new_usertype<dsp_primitives::PassthroughNode>("PassthroughNode",
        sol::constructors<std::shared_ptr<dsp_primitives::PassthroughNode>(int)>()
    );

    lua.new_usertype<dsp_primitives::OscillatorNode>("OscillatorNode",
        sol::constructors<std::shared_ptr<dsp_primitives::OscillatorNode>()>(),
        "setFrequency", &dsp_primitives::OscillatorNode::setFrequency,
        "setAmplitude", &dsp_primitives::OscillatorNode::setAmplitude,
        "setEnabled", &dsp_primitives::OscillatorNode::setEnabled,
        "setWaveform", &dsp_primitives::OscillatorNode::setWaveform,
        "getFrequency", &dsp_primitives::OscillatorNode::getFrequency,
        "getAmplitude", &dsp_primitives::OscillatorNode::getAmplitude,
        "isEnabled", &dsp_primitives::OscillatorNode::isEnabled,
        "getWaveform", &dsp_primitives::OscillatorNode::getWaveform
    );

    lua.new_usertype<dsp_primitives::ReverbNode>("ReverbNode",
        sol::constructors<std::shared_ptr<dsp_primitives::ReverbNode>()>(),
        "setRoomSize", &dsp_primitives::ReverbNode::setRoomSize,
        "setDamping", &dsp_primitives::ReverbNode::setDamping,
        "setWetLevel", &dsp_primitives::ReverbNode::setWetLevel,
        "setDryLevel", &dsp_primitives::ReverbNode::setDryLevel,
        "setWidth", &dsp_primitives::ReverbNode::setWidth,
        "getRoomSize", &dsp_primitives::ReverbNode::getRoomSize,
        "getDamping", &dsp_primitives::ReverbNode::getDamping,
        "getWetLevel", &dsp_primitives::ReverbNode::getWetLevel,
        "getDryLevel", &dsp_primitives::ReverbNode::getDryLevel,
        "getWidth", &dsp_primitives::ReverbNode::getWidth
    );

    lua.new_usertype<dsp_primitives::FilterNode>("FilterNode",
        sol::constructors<std::shared_ptr<dsp_primitives::FilterNode>()>(),
        "setCutoff", &dsp_primitives::FilterNode::setCutoff,
        "setResonance", &dsp_primitives::FilterNode::setResonance,
        "setMix", &dsp_primitives::FilterNode::setMix,
        "getCutoff", &dsp_primitives::FilterNode::getCutoff,
        "getResonance", &dsp_primitives::FilterNode::getResonance,
        "getMix", &dsp_primitives::FilterNode::getMix
    );

    lua.new_usertype<dsp_primitives::DistortionNode>("DistortionNode",
        sol::constructors<std::shared_ptr<dsp_primitives::DistortionNode>()>(),
        "setDrive", &dsp_primitives::DistortionNode::setDrive,
        "setMix", &dsp_primitives::DistortionNode::setMix,
        "setOutput", &dsp_primitives::DistortionNode::setOutput,
        "getDrive", &dsp_primitives::DistortionNode::getDrive,
        "getMix", &dsp_primitives::DistortionNode::getMix,
        "getOutput", &dsp_primitives::DistortionNode::getOutput
    );

    lua.new_usertype<dsp_primitives::SVFNode>("SVFNode",
        sol::constructors<std::shared_ptr<dsp_primitives::SVFNode>()>(),
        "setCutoff", &dsp_primitives::SVFNode::setCutoff,
        "setResonance", &dsp_primitives::SVFNode::setResonance,
        "setMode", &dsp_primitives::SVFNode::setMode,
        "setDrive", &dsp_primitives::SVFNode::setDrive,
        "setMix", &dsp_primitives::SVFNode::setMix,
        "getCutoff", &dsp_primitives::SVFNode::getCutoff,
        "getResonance", &dsp_primitives::SVFNode::getResonance,
        "getMode", &dsp_primitives::SVFNode::getMode,
        "getDrive", &dsp_primitives::SVFNode::getDrive,
        "getMix", &dsp_primitives::SVFNode::getMix,
        "reset", &dsp_primitives::SVFNode::reset
    );

    lua.new_usertype<dsp_primitives::StereoDelayNode>("StereoDelayNode",
        sol::constructors<std::shared_ptr<dsp_primitives::StereoDelayNode>()>(),
        "setTimeMode", &dsp_primitives::StereoDelayNode::setTimeMode,
        "setTimeL", &dsp_primitives::StereoDelayNode::setTimeL,
        "setTimeR", &dsp_primitives::StereoDelayNode::setTimeR,
        "setDivisionL", &dsp_primitives::StereoDelayNode::setDivisionL,
        "setDivisionR", &dsp_primitives::StereoDelayNode::setDivisionR,
        "setFeedback", &dsp_primitives::StereoDelayNode::setFeedback,
        "setFeedbackCrossfeed", &dsp_primitives::StereoDelayNode::setFeedbackCrossfeed,
        "setFilterEnabled", &dsp_primitives::StereoDelayNode::setFilterEnabled,
        "setFilterCutoff", &dsp_primitives::StereoDelayNode::setFilterCutoff,
        "setFilterResonance", &dsp_primitives::StereoDelayNode::setFilterResonance,
        "setMix", &dsp_primitives::StereoDelayNode::setMix,
        "setPingPong", &dsp_primitives::StereoDelayNode::setPingPong,
        "setWidth", &dsp_primitives::StereoDelayNode::setWidth,
        "setFreeze", &dsp_primitives::StereoDelayNode::setFreeze,
        "setDucking", &dsp_primitives::StereoDelayNode::setDucking,
        "setTempo", &dsp_primitives::StereoDelayNode::setTempo,
        "getTimeMode", &dsp_primitives::StereoDelayNode::getTimeMode,
        "getTimeL", &dsp_primitives::StereoDelayNode::getTimeL,
        "getTimeR", &dsp_primitives::StereoDelayNode::getTimeR,
        "getMix", &dsp_primitives::StereoDelayNode::getMix,
        "getFeedback", &dsp_primitives::StereoDelayNode::getFeedback,
        "getPingPong", &dsp_primitives::StereoDelayNode::getPingPong,
        "getFreeze", &dsp_primitives::StereoDelayNode::getFreeze,
        "reset", &dsp_primitives::StereoDelayNode::reset
    );

    // MIDI Nodes
    lua.new_usertype<dsp_primitives::MidiVoiceNode>("MidiVoiceNode",
        sol::constructors<std::shared_ptr<dsp_primitives::MidiVoiceNode>()>(),
        "setWaveform", &dsp_primitives::MidiVoiceNode::setWaveform,
        "setAttack", &dsp_primitives::MidiVoiceNode::setAttack,
        "setDecay", &dsp_primitives::MidiVoiceNode::setDecay,
        "setSustain", &dsp_primitives::MidiVoiceNode::setSustain,
        "setRelease", &dsp_primitives::MidiVoiceNode::setRelease,
        "setFilterCutoff", &dsp_primitives::MidiVoiceNode::setFilterCutoff,
        "setFilterResonance", &dsp_primitives::MidiVoiceNode::setFilterResonance,
        "setFilterEnvAmount", &dsp_primitives::MidiVoiceNode::setFilterEnvAmount,
        "setEnabled", &dsp_primitives::MidiVoiceNode::setEnabled,
        "setPolyphony", &dsp_primitives::MidiVoiceNode::setPolyphony,
        "setGlide", &dsp_primitives::MidiVoiceNode::setGlide,
        "setDetune", &dsp_primitives::MidiVoiceNode::setDetune,
        "setSpread", &dsp_primitives::MidiVoiceNode::setSpread,
        "setUnison", &dsp_primitives::MidiVoiceNode::setUnison,
        "getWaveform", &dsp_primitives::MidiVoiceNode::getWaveform,
        "getAttack", &dsp_primitives::MidiVoiceNode::getAttack,
        "getDecay", &dsp_primitives::MidiVoiceNode::getDecay,
        "getSustain", &dsp_primitives::MidiVoiceNode::getSustain,
        "getRelease", &dsp_primitives::MidiVoiceNode::getRelease,
        "getFilterCutoff", &dsp_primitives::MidiVoiceNode::getFilterCutoff,
        "getFilterResonance", &dsp_primitives::MidiVoiceNode::getFilterResonance,
        "getFilterEnvAmount", &dsp_primitives::MidiVoiceNode::getFilterEnvAmount,
        "isEnabled", &dsp_primitives::MidiVoiceNode::isEnabled,
        "getPolyphony", &dsp_primitives::MidiVoiceNode::getPolyphony,
        "getNumActiveVoices", &dsp_primitives::MidiVoiceNode::getNumActiveVoices,
        "noteOn", &dsp_primitives::MidiVoiceNode::noteOn,
        "noteOff", &dsp_primitives::MidiVoiceNode::noteOff,
        "allNotesOff", &dsp_primitives::MidiVoiceNode::allNotesOff,
        "allSoundOff", &dsp_primitives::MidiVoiceNode::allSoundOff,
        "pitchBend", &dsp_primitives::MidiVoiceNode::pitchBend,
        "controlChange", &dsp_primitives::MidiVoiceNode::controlChange
    );

    lua.new_usertype<dsp_primitives::MidiInputNode>("MidiInputNode",
        sol::constructors<std::shared_ptr<dsp_primitives::MidiInputNode>()>(),
        "setChannelFilter", &dsp_primitives::MidiInputNode::setChannelFilter,
        "setChannelMask", &dsp_primitives::MidiInputNode::setChannelMask,
        "setOmniMode", &dsp_primitives::MidiInputNode::setOmniMode,
        "setMonophonic", &dsp_primitives::MidiInputNode::setMonophonic,
        "setPortamento", &dsp_primitives::MidiInputNode::setPortamento,
        "setPitchBendRange", &dsp_primitives::MidiInputNode::setPitchBendRange,
        "setEnabled", &dsp_primitives::MidiInputNode::setEnabled,
        "setEchoOutput", &dsp_primitives::MidiInputNode::setEchoOutput,
        "getChannelFilter", &dsp_primitives::MidiInputNode::getChannelFilter,
        "isOmniMode", &dsp_primitives::MidiInputNode::isOmniMode,
        "isMonophonic", &dsp_primitives::MidiInputNode::isMonophonic,
        "getPortamento", &dsp_primitives::MidiInputNode::getPortamento,
        "getPitchBendRange", &dsp_primitives::MidiInputNode::getPitchBendRange,
        "isEnabled", &dsp_primitives::MidiInputNode::isEnabled,
        "isEchoingOutput", &dsp_primitives::MidiInputNode::isEchoingOutput,
        "getLastNote", &dsp_primitives::MidiInputNode::getLastNote,
        "getLastVelocity", &dsp_primitives::MidiInputNode::getLastVelocity,
        "getCurrentPitchBend", &dsp_primitives::MidiInputNode::getCurrentPitchBend,
        "connectToVoiceNode", &dsp_primitives::MidiInputNode::connectToVoiceNode,
        "triggerNoteOn", &dsp_primitives::MidiInputNode::triggerNoteOn,
        "triggerNoteOff", &dsp_primitives::MidiInputNode::triggerNoteOff,
        "triggerPitchBend", &dsp_primitives::MidiInputNode::triggerPitchBend
    );

    // Node factories
    lua["Primitives"]["PlayheadNode"] = lua.create_table();
    lua["Primitives"]["PlayheadNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::PlayheadNode>();
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["PassthroughNode"] = lua.create_table();
    lua["Primitives"]["PassthroughNode"]["new"] = [graph](int numChannels) {
        auto node = std::make_shared<dsp_primitives::PassthroughNode>(numChannels);
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["OscillatorNode"] = lua.create_table();
    lua["Primitives"]["OscillatorNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::OscillatorNode>();
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["ReverbNode"] = lua.create_table();
    lua["Primitives"]["ReverbNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::ReverbNode>();
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["FilterNode"] = lua.create_table();
    lua["Primitives"]["FilterNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::FilterNode>();
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["DistortionNode"] = lua.create_table();
    lua["Primitives"]["DistortionNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::DistortionNode>();
        graph->registerNode(node);
        return node;
    };

    lua["Primitives"]["SVFNode"] = lua.create_table();
    lua["Primitives"]["SVFNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::SVFNode>();
        graph->registerNode(node);
        return node;
    };
    lua["Primitives"]["SVFNode"]["Mode"] = lua.create_table_with(
        "Lowpass", 0,
        "Bandpass", 1,
        "Highpass", 2,
        "Notch", 3,
        "Peak", 4
    );

    lua["Primitives"]["StereoDelayNode"] = lua.create_table();
    lua["Primitives"]["StereoDelayNode"]["new"] = [graph]() {
        auto node = std::make_shared<dsp_primitives::StereoDelayNode>();
        graph->registerNode(node);
        return node;
    };
    lua["Primitives"]["StereoDelayNode"]["TimeMode"] = lua.create_table_with(
        "Free", 0,
        "Synced", 1
    );
    lua["Primitives"]["StereoDelayNode"]["Division"] = lua.create_table_with(
        "ThirtySecond", 0,
        "Sixteenth", 1,
        "Eighth", 2,
        "Quarter", 3,
        "Half", 4,
        "Whole", 5,
        "DottedEighth", 6,
        "DottedQuarter", 7,
        "TripletSixteenth", 8,
        "TripletEighth", 9,
        "TripletQuarter", 10
    );

    // Connection helpers
    auto toPrimitiveNode = [](const sol::object& obj) -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
        if (obj.is<std::shared_ptr<dsp_primitives::PlayheadNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::PlayheadNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::PassthroughNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::PassthroughNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::OscillatorNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::OscillatorNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::ReverbNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::ReverbNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::FilterNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::FilterNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::DistortionNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::DistortionNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::SVFNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::SVFNode>>();
        }
        if (obj.is<std::shared_ptr<dsp_primitives::StereoDelayNode>>()) {
            return obj.as<std::shared_ptr<dsp_primitives::StereoDelayNode>>();
        }
        return nullptr;
    };

    lua["connectNodes"] = [graph, toPrimitiveNode](const sol::object& fromObj,
                                                    const sol::object& toObj) -> bool {
        auto from = toPrimitiveNode(fromObj);
        auto to = toPrimitiveNode(toObj);
        if (!from || !to) return false;
        return graph->connect(from, 0, to, 0);
    };

    lua["hasGraphCycle"] = [graph]() -> bool {
        return graph->hasCycle();
    };

    lua["getGraphNodeCount"] = [graph]() -> int {
        return static_cast<int>(graph->getNodeCount());
    };

    lua["getGraphConnectionCount"] = [graph]() -> int {
        return static_cast<int>(graph->getConnectionCount());
    };

    lua["clearGraph"] = [graph]() {
        graph->clear();
    };

    lua["setGraphProcessingEnabled"] = [&state](bool enabled) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        processor->setGraphProcessingEnabled(enabled);
        return processor->isGraphProcessingEnabled() == enabled;
    };

    lua["isGraphProcessingEnabled"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isGraphProcessingEnabled();
    };
}

void LuaControlBindings::registerOSCBindings(sol::state& lua,
                                             ILuaControlState& state) {
    auto oscTable = lua.create_table();

    oscTable["getSettings"] = [&state, &lua]() -> sol::table {
        auto result = sol::table(lua, sol::create);
        auto* processor = state.getProcessor();
        if (!processor) return result;

        auto& oscServer = processor->getOSCServer();
        auto settings = oscServer.getSettings();

        result["inputPort"] = settings.inputPort;
        result["queryPort"] = settings.queryPort;
        result["oscEnabled"] = settings.oscEnabled;
        result["oscQueryEnabled"] = settings.oscQueryEnabled;

        auto targetsTbl = sol::table(lua, sol::create);
        for (int i = 0; i < settings.outTargets.size(); ++i) {
            targetsTbl[i + 1] = settings.outTargets[i].toStdString();
        }
        result["outTargets"] = targetsTbl;

        return result;
    };

    oscTable["setSettings"] = [&state](sol::table settingsTable) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        OSCSettings settings;

        if (settingsTable["inputPort"].valid()) {
            settings.inputPort = settingsTable["inputPort"].get<int>();
        }
        if (settingsTable["queryPort"].valid()) {
            settings.queryPort = settingsTable["queryPort"].get<int>();
        }
        if (settingsTable["oscEnabled"].valid()) {
            settings.oscEnabled = settingsTable["oscEnabled"].get<bool>();
        }
        if (settingsTable["oscQueryEnabled"].valid()) {
            settings.oscQueryEnabled = settingsTable["oscQueryEnabled"].get<bool>();
        }
        if (settingsTable["outTargets"].valid()) {
            sol::table targetsTable = settingsTable["outTargets"];
            for (int i = 1; ; ++i) {
                auto val = targetsTable.get<sol::optional<std::string>>(i);
                if (!val.has_value()) break;
                settings.outTargets.add(juce::String(val.value()));
            }
        }

        if (!OSCSettingsPersistence::save(settings)) return false;
        processor->getOSCServer().setSettings(settings);
        return true;
    };

    oscTable["getStatus"] = [&state]() -> std::string {
        auto* processor = state.getProcessor();
        if (!processor) return "no processor";
        auto& oscServer = processor->getOSCServer();
        if (!oscServer.isRunning()) return "stopped";
        return "running";
    };

    oscTable["addTarget"] = [&state](const std::string& ipPort) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        processor->getOSCServer().addOutTarget(juce::String(ipPort));
        auto settings = processor->getOSCServer().getSettings();
        OSCSettingsPersistence::save(settings);
        return true;
    };

    oscTable["removeTarget"] = [&state](const std::string& ipPort) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        processor->getOSCServer().removeOutTarget(juce::String(ipPort));
        auto settings = processor->getOSCServer().getSettings();
        OSCSettingsPersistence::save(settings);
        return true;
    };

    oscTable["send"] = [&state](const std::string& address,
                                sol::variadic_args args) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        std::vector<juce::var> vars;
        for (auto arg : args) {
            if (arg.is<int>()) vars.push_back(arg.as<int>());
            else if (arg.is<float>()) vars.push_back(arg.as<float>());
            else if (arg.is<double>()) vars.push_back(static_cast<float>(arg.as<double>()));
            else if (arg.is<std::string>()) vars.push_back(juce::String(arg.as<std::string>()));
            else if (arg.is<bool>()) vars.push_back(arg.as<bool>() ? 1 : 0);
        }

        juce::String path(address.c_str());
        processor->getOSCServer().broadcast(path, vars);

        if (!path.startsWith("/core/behavior/") && path.startsWithChar('/')) {
            processor->getOSCServer().setCustomValue(path, vars);
            state.getUiRegisteredOscValues().insert(path.toStdString());
        }
        return true;
    };

    oscTable["sendTo"] = [&state](const std::string& ip, int port,
                                  const std::string& address,
                                  sol::variadic_args args) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        std::vector<juce::var> vars;
        for (auto arg : args) {
            if (arg.is<int>()) vars.push_back(arg.as<int>());
            else if (arg.is<float>()) vars.push_back(arg.as<float>());
            else if (arg.is<double>()) vars.push_back(static_cast<float>(arg.as<double>()));
            else if (arg.is<std::string>()) vars.push_back(juce::String(arg.as<std::string>()));
            else if (arg.is<bool>()) vars.push_back(arg.as<bool>() ? 1 : 0);
        }

        juce::String path(address.c_str());
        auto packet = OSCPacketBuilder::build(path, vars);
        juce::DatagramSocket socket;
        socket.bindToPort(0);
        socket.write(juce::String(ip.c_str()), port, packet.data(),
                     static_cast<int>(packet.size()));

        if (!path.startsWith("/core/behavior/") && path.startsWithChar('/')) {
            processor->getOSCServer().setCustomValue(path, vars);
            state.getUiRegisteredOscValues().insert(path.toStdString());
        }
        return true;
    };

    oscTable["onMessage"] = [&state](const std::string& address,
                                     sol::function callback,
                                     sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> cbLock(state.getOscCallbacksMutex());
        ILuaControlState::OSCCallback cb;
        cb.func = callback;
        cb.persistent = persistent.value_or(false);
        cb.address = juce::String(address.c_str());
        state.getOscCallbacks()[juce::String(address.c_str())].push_back(std::move(cb));
        return true;
    };

    oscTable["removeHandler"] = [&state](const std::string& address) -> bool {
        std::lock_guard<std::mutex> lock(state.getOscCallbacksMutex());
        auto it = state.getOscCallbacks().find(juce::String(address.c_str()));
        if (it != state.getOscCallbacks().end()) {
            state.getOscCallbacks().erase(it);
            return true;
        }
        return false;
    };

    oscTable["registerEndpoint"] = [&state](const std::string& path,
                                             sol::table options) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        OSCEndpoint endpoint;
        endpoint.path = juce::String(path.c_str());
        endpoint.category = "custom";

        if (options["type"].valid()) {
            endpoint.type = juce::String(options["type"].get<std::string>().c_str());
        } else {
            endpoint.type = "f";
        }

        if (options["range"].valid()) {
            sol::table range = options["range"];
            auto minVal = range[1];
            auto maxVal = range[2];
            endpoint.rangeMin = minVal.valid() ? minVal.get<float>() : 0.0f;
            endpoint.rangeMax = maxVal.valid() ? maxVal.get<float>() : 1.0f;
        }

        if (options["access"].valid()) {
            endpoint.access = options["access"].get<int>();
        } else {
            endpoint.access = 3;
        }

        if (options["description"].valid()) {
            endpoint.description = juce::String(options["description"].get<std::string>().c_str());
        }

        processor->getEndpointRegistry().registerCustomEndpoint(endpoint);
        state.getUiRegisteredOscEndpoints().insert(endpoint.path.toStdString());
        processor->getOSCQueryServer().rebuildTree();
        return true;
    };

    oscTable["removeEndpoint"] = [&state](const std::string& path) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        const juce::String endpointPath(path.c_str());
        processor->getEndpointRegistry().unregisterCustomEndpoint(endpointPath);
        processor->getOSCServer().removeCustomValue(endpointPath);
        state.getUiRegisteredOscEndpoints().erase(endpointPath.toStdString());
        state.getUiRegisteredOscValues().erase(endpointPath.toStdString());
        processor->getOSCQueryServer().rebuildTree();
        return true;
    };

    oscTable["setValue"] = [&state](const std::string& path,
                                    sol::object value) -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;

        std::vector<juce::var> args;
        if (value.is<float>()) args.emplace_back(value.as<float>());
        else if (value.is<int>()) args.emplace_back(value.as<int>());
        else if (value.is<double>()) args.emplace_back((float)value.as<double>());
        else if (value.is<std::string>()) args.emplace_back(juce::String(value.as<std::string>().c_str()));
        else if (value.is<bool>()) args.emplace_back(value.as<bool>() ? 1 : 0);
        else if (value.get_type() == sol::type::table) {
            sol::table tbl = value;
            for (int i = 1;; ++i) {
                sol::object item = tbl[i];
                if (!item.valid() || item.get_type() == sol::type::nil) break;
                if (item.is<int>()) args.emplace_back(item.as<int>());
                else if (item.is<float>()) args.emplace_back(item.as<float>());
                else if (item.is<double>()) args.emplace_back((float)item.as<double>());
                else if (item.is<std::string>()) args.emplace_back(juce::String(item.as<std::string>().c_str()));
                else if (item.is<bool>()) args.emplace_back(item.as<bool>() ? 1 : 0);
            }
        } else {
            return false;
        }

        const juce::String valuePath(path.c_str());
        processor->getOSCServer().setCustomValue(valuePath, args);
        state.getUiRegisteredOscValues().insert(valuePath.toStdString());
        return true;
    };

    oscTable["getValue"] = [&state, &lua](const std::string& path) -> sol::object {
        auto* processor = state.getProcessor();
        if (!processor) return sol::nil;

        std::vector<juce::var> vals;
        if (!processor->getOSCServer().getCustomValue(juce::String(path.c_str()), vals) || vals.empty()) {
            return sol::nil;
        }

        if (vals.size() == 1) {
            const auto& val = vals[0];
            if (val.isInt()) return sol::make_object(lua, (int)val);
            else if (val.isDouble()) return sol::make_object(lua, (double)val);
            else if (val.isString()) return sol::make_object(lua, val.toString().toStdString());
            else if (val.isBool()) return sol::make_object(lua, (bool)val);
            return sol::nil;
        }

        auto t = sol::table(lua, sol::create);
        for (size_t i = 0; i < vals.size(); ++i) {
            const auto& val = vals[i];
            if (val.isInt()) t[i + 1] = (int)val;
            else if (val.isDouble()) t[i + 1] = (double)val;
            else if (val.isString()) t[i + 1] = val.toString().toStdString();
            else if (val.isBool()) t[i + 1] = (bool)val;
            else t[i + 1] = sol::nil;
        }
        return sol::make_object(lua, t);
    };

    oscTable["onQuery"] = [&state](const std::string& path,
                                   sol::function callback,
                                   sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getOscQueryHandlersMutex());
        ILuaControlState::OSCQueryHandler handler;
        handler.func = callback;
        handler.persistent = persistent.value_or(false);
        state.getOscQueryHandlers()[juce::String(path.c_str())] = std::move(handler);
        return true;
    };

    lua["osc"] = oscTable;
}

void LuaControlBindings::registerEventBindings(sol::state& lua,
                                               ILuaControlState& state) {
    auto looperTable = lua.create_table();

    looperTable["onTempoChanged"] = [&state](sol::function callback,
                                             sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getEventListenersMutex());
        ILuaControlState::EventListener listener;
        listener.func = callback;
        listener.persistent = persistent.value_or(false);
        state.getTempoChangedListeners().push_back(std::move(listener));
        return true;
    };

    looperTable["onCommit"] = [&state](sol::function callback,
                                       sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getEventListenersMutex());
        ILuaControlState::EventListener listener;
        listener.func = callback;
        listener.persistent = persistent.value_or(false);
        state.getCommitListeners().push_back(std::move(listener));
        return true;
    };

    looperTable["onRecordingChanged"] = [&state](sol::function callback,
                                                 sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getEventListenersMutex());
        ILuaControlState::EventListener listener;
        listener.func = callback;
        listener.persistent = persistent.value_or(false);
        state.getRecordingChangedListeners().push_back(std::move(listener));
        return true;
    };

    looperTable["onLayerStateChanged"] = [&state](sol::function callback,
                                                  sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getEventListenersMutex());
        ILuaControlState::EventListener listener;
        listener.func = callback;
        listener.persistent = persistent.value_or(false);
        state.getLayerStateChangedListeners().push_back(std::move(listener));
        return true;
    };

    looperTable["onStateChanged"] = [&state](sol::function callback,
                                             sol::optional<bool> persistent) -> bool {
        if (!callback.valid()) return false;

        std::lock_guard<std::mutex> lock(state.getEventListenersMutex());
        ILuaControlState::EventListener listener;
        listener.func = callback;
        listener.persistent = persistent.value_or(false);
        state.getStateChangedListeners().push_back(std::move(listener));
        return true;
    };

    lua["looper"] = looperTable;
}

void LuaControlBindings::registerLinkBindings(sol::state& lua,
                                              ILuaControlState& state) {
    auto linkTable = lua.create_table();

    linkTable["isEnabled"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isLinkEnabled();
    };

    linkTable["setEnabled"] = [&state](bool enabled) {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->setLinkEnabled(enabled);
    };

    linkTable["isTempoSyncEnabled"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isLinkTempoSyncEnabled();
    };

    linkTable["setTempoSyncEnabled"] = [&state](bool enabled) {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->setLinkTempoSyncEnabled(enabled);
    };

    linkTable["isStartStopSyncEnabled"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isLinkStartStopSyncEnabled();
    };

    linkTable["setStartStopSyncEnabled"] = [&state](bool enabled) {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->setLinkStartStopSyncEnabled(enabled);
    };

    linkTable["getNumPeers"] = [&state]() -> int {
        auto* processor = state.getProcessor();
        if (!processor) return 0;
        return processor->getLinkNumPeers();
    };

    linkTable["isPlaying"] = [&state]() -> bool {
        auto* processor = state.getProcessor();
        if (!processor) return false;
        return processor->isLinkPlaying();
    };

    linkTable["getBeat"] = [&state]() -> double {
        auto* processor = state.getProcessor();
        if (!processor) return 0.0;
        return processor->getLinkBeat();
    };

    linkTable["getPhase"] = [&state]() -> double {
        auto* processor = state.getProcessor();
        if (!processor) return 0.0;
        return processor->getLinkPhase();
    };

    linkTable["requestTempo"] = [&state](double bpm) {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->requestLinkTempo(bpm);
    };

    linkTable["requestStart"] = [&state]() {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->requestLinkStart();
    };

    linkTable["requestStop"] = [&state]() {
        auto* processor = state.getProcessor();
        if (!processor) return;
        processor->requestLinkStop();
    };

    lua["link"] = linkTable;
}

void LuaControlBindings::registerUtilityBindings(sol::state& lua,
                                                 ILuaControlState& state) {
    std::fprintf(stderr, "[LuaControlBindings] registerUtilityBindings called\n");
    
    lua["getTime"] = []() -> double {
        static const auto startTime = juce::Time::getHighResolutionTicks();
        return juce::Time::highResolutionTicksToSeconds(
            juce::Time::getHighResolutionTicks() - startTime);
    };

    lua["listUiScripts"] = [&lua]() -> sol::table {
        auto result = sol::table(lua, sol::create);
        std::set<std::string> seenPaths;
        int index = 1;

        auto addUiScriptEntry = [&](const juce::File& script,
                                    const juce::String& displayName,
                                    const juce::String& kind,
                                    const juce::String& scope) {
            if (!script.exists()) return;
            const auto fullPath = script.getFullPathName().toStdString();
            if (seenPaths.count(fullPath) > 0) return;
            seenPaths.insert(fullPath);

            auto entry = sol::table(lua, sol::create);
            entry["name"] = displayName.toStdString();
            entry["path"] = fullPath;
            entry["kind"] = kind.toStdString();
            entry["scope"] = scope.toStdString();
            result[index++] = entry;
        };

        auto addLooseUiScriptsFromDir = [&](const juce::File& dir,
                                            const juce::String& scope) {
            if (!dir.isDirectory()) return;
            auto scripts = dir.findChildFiles(juce::File::findFiles, false, "*.lua");
            for (const auto& script : scripts) {
                auto name = script.getFileNameWithoutExtension();

                if (name == "ui_widgets" || name == "ui_shell" ||
                    name == "project_loader") {
                    continue;
                }
                if (!isUiScriptFile(script)) {
                    continue;
                }

                addUiScriptEntry(script, name, "script", scope);
            }
        };

        auto addProjectsFromDir = [&](const juce::File& dir) {
            if (!dir.isDirectory()) return;
            auto entries = dir.findChildFiles(juce::File::findDirectories, false);
            for (const auto& child : entries) {
                const auto manifest = child.getChildFile("manifold.project.json5");
                if (!isProjectManifestFile(manifest)) {
                    continue;
                }

                auto name = readProjectDisplayName(manifest);
                addUiScriptEntry(manifest, name, "project", "project");
            }
        };

        auto& settings = Settings::getInstance();

        auto devDir = settings.getDevScriptsDir();
        if (devDir.isNotEmpty()) {
            addLooseUiScriptsFromDir(juce::File(devDir), "system");
        } else {
            std::fprintf(stderr,
                         "[LuaControlBindings] listUiScripts: devScriptsDir is empty\n");
        }

        auto userRoot = settings.getUserScriptsDir();
        if (userRoot.isNotEmpty()) {
            juce::File root(userRoot);
            addProjectsFromDir(root.getChildFile("projects"));
            addLooseUiScriptsFromDir(root.getChildFile("ui"), "user");

            // Transitional compatibility for older directory naming.
            addLooseUiScriptsFromDir(root.getChildFile("UI"), "user-legacy");
            addProjectsFromDir(root);
        }

        return result;
    };

    lua["switchUiScript"] = [&state](const std::string& path) {
        state.setPendingSwitchPath(path);
    };

    lua["getCurrentScriptPath"] = [&state]() -> std::string {
        return state.getCurrentScriptFile().getFullPathName().toStdString();
    };

    lua["setClipboardText"] = [](const std::string& text) -> bool {
        juce::SystemClipboard::copyTextToClipboard(juce::String(text));
        return true;
    };

    lua["getClipboardText"] = []() -> std::string {
        return juce::SystemClipboard::getTextFromClipboard().toStdString();
    };

    lua["writeTextFile"] = [](const std::string& path,
                               const std::string& text) -> bool {
        juce::File outFile(path);
        return outFile.replaceWithText(juce::String(text), false, false, "\n");
    };

    lua["readTextFile"] = [](const std::string& path) -> std::string {
        juce::File inFile(path);
        if (!inFile.existsAsFile()) {
            return "";
        }
        return inFile.loadFileAsString().toStdString();
    };

    lua["listFilesRecursive"] = [&lua](const std::string& rootPath) -> sol::table {
        auto result = sol::table(lua, sol::create);
        juce::File root(rootPath);
        if (!root.isDirectory()) {
            return result;
        }

        auto files = root.findChildFiles(juce::File::findFiles, true);
        files.sort();

        int index = 1;
        for (const auto& file : files) {
            const auto ext = file.getFileExtension();
            if (ext != ".lua" && ext != ".json5") {
                continue;
            }
            result[index++] = file.getFullPathName().toStdString();
        }
        return result;
    };

    lua["listDspScripts"] = [&lua]() -> sol::table {
        auto result = sol::table(lua, sol::create);
        std::set<std::string> seenNames;
        int index = 1;

        auto addScriptsFromDir = [&](const juce::File& dir) {
            if (!dir.isDirectory()) return;
            auto scripts = dir.findChildFiles(juce::File::findFiles, false, "*.lua");
            for (const auto& script : scripts) {
                auto name = script.getFileNameWithoutExtension().toStdString();

                // Skip duplicates
                if (seenNames.count(name) > 0) continue;

                // Only include files that look like DSP scripts (contain buildPlugin function)
                auto content = script.loadFileAsString();
                if (!content.contains("function buildPlugin")) {
                    continue;
                }

                seenNames.insert(name);
                auto entry = sol::table(lua, sol::create);
                entry["name"] = name;
                entry["path"] = script.getFullPathName().toStdString();
                entry["code"] = content.toStdString();
                result[index++] = entry;
            }
        };

        // Strict source: configured DSP scripts directory only (no fallbacks)
        auto& settings = Settings::getInstance();
        auto dspDir = settings.getDspScriptsDir();
        if (dspDir.isNotEmpty()) {
            const juce::File baseDir(dspDir);
            addScriptsFromDir(baseDir);
            addScriptsFromDir(baseDir.getChildFile("scripts"));
        } else {
            std::fprintf(stderr,
                         "[LuaControlBindings] listDspScripts: dspScriptsDir is empty\n");
        }

        return result;
    };

    // Settings table - persistent configuration
    auto settingsTable = lua.create_table();
    
    settingsTable["getUserScriptsDir"] = []() -> std::string {
        return Settings::getInstance().getUserScriptsDir().toStdString();
    };
    
    settingsTable["setUserScriptsDir"] = [](const std::string& path) {
        Settings::getInstance().setUserScriptsDir(juce::String(path));
        Settings::getInstance().save();
    };
    
    settingsTable["getDevScriptsDir"] = []() -> std::string {
        return Settings::getInstance().getDevScriptsDir().toStdString();
    };
    
    settingsTable["setDevScriptsDir"] = [](const std::string& path) {
        Settings::getInstance().setDevScriptsDir(juce::String(path));
        Settings::getInstance().save();
    };
    
    settingsTable["getOscPort"] = []() -> int {
        return Settings::getInstance().getOscPort();
    };
    
    settingsTable["setOscPort"] = [](int port) {
        Settings::getInstance().setOscPort(port);
        Settings::getInstance().save();
    };
    
    settingsTable["getOscQueryPort"] = []() -> int {
        return Settings::getInstance().getOscQueryPort();
    };
    
    settingsTable["setOscQueryPort"] = [](int port) {
        Settings::getInstance().setOscQueryPort(port);
        Settings::getInstance().save();
    };
    
    settingsTable["save"] = []() {
        Settings::getInstance().save();
    };
    
    settingsTable["getConfigPath"] = []() -> std::string {
        return Settings::getInstance().getConfigPath().toStdString();
    };
    
    // Async directory chooser - calls callback(path) when user selects
    settingsTable["browseForUserScriptsDir"] = [&state](sol::function callback) {
        std::fprintf(stderr, "[LuaSettings] browseForUserScriptsDir called\n");
        auto currentDir = Settings::getInstance().getUserScriptsDir();
        std::fprintf(stderr, "[LuaSettings] currentDir='%s'\n", currentDir.toRawUTF8());
        if (currentDir.isEmpty()) {
            currentDir = juce::File::getSpecialLocation(juce::File::userHomeDirectory).getFullPathName();
            std::fprintf(stderr, "[LuaSettings] using home dir: '%s'\n", currentDir.toRawUTF8());
        }
        std::fprintf(stderr, "[LuaSettings] calling showDirectoryChooser...\n");
        state.showDirectoryChooser("Select User Scripts Directory", 
                                    currentDir.toStdString(), 
                                    callback);
        std::fprintf(stderr, "[LuaSettings] showDirectoryChooser returned\n");
    };
    
    // DSP scripts directory
    settingsTable["getDspScriptsDir"] = []() -> std::string {
        return Settings::getInstance().getDspScriptsDir().toStdString();
    };
    
    settingsTable["setDspScriptsDir"] = [](const std::string& path) {
        Settings::getInstance().setDspScriptsDir(juce::String(path));
        Settings::getInstance().save();
    };
    
    settingsTable["browseForDspScriptsDir"] = [&state](sol::function callback) {
        auto currentDir = Settings::getInstance().getDspScriptsDir();
        if (currentDir.isEmpty()) {
            currentDir = juce::File::getSpecialLocation(juce::File::userHomeDirectory).getFullPathName();
        }
        state.showDirectoryChooser("Select DSP Scripts Directory", 
                                    currentDir.toStdString(), 
                                    callback);
    };
    
    std::fprintf(stderr, "[LuaControlBindings] About to set lua['settings']...\n");
    lua["settings"] = settingsTable;
    
    // Debug: verify settings table was created properly
    std::fprintf(stderr, "[LuaSettings] Registered settings table with %zu entries\n", 
                 settingsTable.size());
    std::fprintf(stderr, "[LuaSettings] browseForUserScriptsDir valid: %d\n", 
                 settingsTable["browseForUserScriptsDir"].valid() ? 1 : 0);
    
    // Verify it was actually set
    auto verifyTable = lua["settings"];
    std::fprintf(stderr, "[LuaSettings] Verification - lua['settings'] type: %s\n", 
                 verifyTable.get_type() == sol::type::table ? "table" : "not table");
}

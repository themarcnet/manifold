#include "DSPHostInternal.h"

#include "../../../core/BehaviorCoreProcessor.h"
#include "../../core/Settings.h"
#include "../../midi/MidiManager.h"
#include "../PrimitiveGraph.h"
#include "dsp/core/nodes/PrimitiveNodes.h"

namespace dsp_host {

void initialiseLoadSession(LoadSession &session) {
  session.lua.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                             sol::lib::table, sol::lib::package);
  session.luaState = session.lua.lua_state();
}

bool configureModuleLoading(LoadSession &session,
                            const juce::File *scriptFile,
                            sol::table &ctx,
                            std::string &error) {
  const auto scriptDir = scriptFile != nullptr ? scriptFile->getParentDirectory()
                                               : juce::File();
  auto &settings = Settings::getInstance();
  juce::File userDspRoot(settings.getUserScriptsDir());
  if (userDspRoot.isDirectory()) {
    userDspRoot = userDspRoot.getChildFile("dsp");
  }
  juce::File systemDspRoot(settings.getDspScriptsDir());

  std::string packagePath;
  auto appendPackageRoot = [&packagePath](const juce::File &root) {
    if (!root.isDirectory()) {
      return;
    }
    const auto base = root.getFullPathName().toStdString();
    if (!packagePath.empty()) {
      packagePath += ";";
    }
    packagePath += base + "/?.lua;" + base + "/?/init.lua";
  };

  appendPackageRoot(scriptDir);
  appendPackageRoot(userDspRoot);
  appendPackageRoot(systemDspRoot);
  if (scriptFile != nullptr) {
    juce::File projectLibDir =
        scriptFile->getParentDirectory().getParentDirectory().getChildFile("lib");
    if (projectLibDir.isDirectory()) {
      appendPackageRoot(projectLibDir);
    }
  }
  session.lua["package"]["path"] = packagePath;

  session.lua["__manifoldDspScriptDir"] = scriptDir.getFullPathName().toStdString();
  session.lua["__manifoldUserDspRoot"] =
      userDspRoot.getFullPathName().toStdString();
  session.lua["__manifoldSystemDspRoot"] =
      systemDspRoot.getFullPathName().toStdString();

  sol::protected_function_result helperInit = session.lua.script(R"lua(
__manifoldDspModuleCache = __manifoldDspModuleCache or {}

local function __dirname(path)
  return (tostring(path or ""):gsub("/+$", ""):match("^(.*)/[^/]+$") or ".")
end

local function __join(...)
  local parts = { ... }
  local out = ""
  for i = 1, #parts do
    local part = tostring(parts[i] or "")
    if part ~= "" then
      if out == "" then
        out = part
      else
        out = out:gsub("/+$", "") .. "/" .. part:gsub("^/+", "")
      end
    end
  end
  return out
end

local function __isAbsolutePath(path)
  path = tostring(path or "")
  return path:match("^/") ~= nil or path:match("^[A-Za-z]:[/\\]") ~= nil
end

local function __resolveDspPath(ref, baseDir)
  if type(ref) ~= "string" or ref == "" then
    error("DSP module ref must be a non-empty string")
  end

  if __isAbsolutePath(ref) then
    return ref
  end

  if ref:sub(1, 7) == "system:" then
    return __join(__manifoldSystemDspRoot or "", ref:sub(8))
  end
  if ref:sub(1, 5) == "user:" then
    return __join(__manifoldUserDspRoot or "", ref:sub(6))
  end
  if ref:sub(1, 8) == "project:" then
    return __join(baseDir or __manifoldDspScriptDir or "", ref:sub(9))
  end
  return __join(baseDir or __manifoldDspScriptDir or "", ref)
end

function resolveDspPath(ref)
  return __resolveDspPath(ref, __manifoldDspScriptDir)
end

function __manifoldLoadDspModule(ref, baseDir)
  local path = __resolveDspPath(ref, baseDir or __manifoldDspScriptDir)
  local cached = __manifoldDspModuleCache[path]
  if cached ~= nil then
    return cached
  end

  local env = {
    __dspModulePath = path,
    __dspModuleDir = __dirname(path),
  }
  env.resolveDspPath = function(childRef)
    return __resolveDspPath(childRef, env.__dspModuleDir)
  end
  env.loadDspModule = function(childRef)
    return __manifoldLoadDspModule(childRef, env.__dspModuleDir)
  end
  setmetatable(env, { __index = _G })

  local chunk, err = loadfile(path, "t", env)
  if not chunk then
    error("failed to load DSP module '" .. tostring(ref) .. "' (" .. tostring(path) .. "): " .. tostring(err))
  end

  local result = chunk()
  local module = result
  if module == nil then
    module = rawget(env, "M")
    if module == nil then
      module = env
    end
  end

  __manifoldDspModuleCache[path] = module
  return module
end

function loadDspModule(ref)
  return __manifoldLoadDspModule(ref, __manifoldDspScriptDir)
end
)lua");
  if (!helperInit.valid()) {
    sol::error err = helperInit;
    error = err.what();
    return false;
  }

  auto pathsTable = sol::state_view(session.luaState).create_table();
  pathsTable["scriptDir"] = scriptDir.getFullPathName().toStdString();
  pathsTable["userDspRoot"] = userDspRoot.getFullPathName().toStdString();
  pathsTable["systemDspRoot"] = systemDspRoot.getFullPathName().toStdString();
  ctx["paths"] = pathsTable;
  return true;
}

bool executeBuildPlugin(LoadSession &session,
                        const juce::File *scriptFile,
                        const std::string *scriptCode,
                        sol::table &ctx,
                        std::string &error) {
  if (scriptFile == nullptr && scriptCode == nullptr) {
    error = "no DSP script source provided";
    return false;
  }

  sol::protected_function_result loadResult =
      (scriptFile != nullptr)
          ? session.lua.script_file(scriptFile->getFullPathName().toStdString())
          : session.lua.script(*scriptCode);
  if (!loadResult.valid()) {
    sol::error err = loadResult;
    error = err.what();
    return false;
  }

  sol::object buildFnObj = session.lua["buildPlugin"];
  if (!buildFnObj.valid() || buildFnObj.get_type() != sol::type::function) {
    error = "DSP script must define buildPlugin(ctx)";
    return false;
  }

  sol::protected_function buildFn = buildFnObj;
  sol::protected_function_result buildResult = buildFn(ctx);
  if (!buildResult.valid()) {
    sol::error err = buildResult;
    error = err.what();
    return false;
  }

  if (!buildResult.get<sol::object>().is<sol::table>()) {
    error = "buildPlugin(ctx) must return a table";
    return false;
  }

  session.pluginTable = buildResult.get<sol::table>();
  if (session.pluginTable["onParamChange"].valid() &&
      session.pluginTable["onParamChange"].get_type() == sol::type::function) {
    session.onParamChange = session.pluginTable["onParamChange"];
  }
  if (session.pluginTable["process"].valid() &&
      session.pluginTable["process"].get_type() == sol::type::function) {
    session.process = session.pluginTable["process"];
  }

  for (const auto &entry : session.paramValues) {
    const auto bindingIt = session.paramBindings.find(entry.first);
    if (bindingIt != session.paramBindings.end()) {
      bindingIt->second(entry.second);
    }

    if (session.onParamChange.valid()) {
      std::string internalPath = entry.first;
      const auto mapIt = session.externalToInternalPath.find(entry.first);
      if (mapIt != session.externalToInternalPath.end()) {
        internalPath = mapIt->second;
      }

      sol::protected_function_result applyResult =
          session.onParamChange(internalPath, entry.second);
      if (!applyResult.valid()) {
        sol::error err = applyResult;
        error = "onParamChange default apply failed: " + std::string(err.what());
        return false;
      }
    }
  }

  return true;
}

void registerMidiApi(LoadSession &session,
                     ScriptableProcessor *processor,
                     sol::table &ctx,
                     bool publishHostApi) {
  auto* bcp = static_cast<BehaviorCoreProcessor*>(processor);
  auto* midiMgr = bcp != nullptr ? bcp->getMidiManager() : nullptr;
  auto lua = sol::state_view(session.luaState);

  if (publishHostApi) {
    auto hostApi = lua.create_table();
    hostApi["getSampleRate"] = [processor]() {
      return processor ? processor->getSampleRate() : 44100.0;
    };
    hostApi["getPlayTimeSamples"] = [processor]() {
      return processor ? processor->getPlayTimeSamples() : 0.0;
    };
    hostApi["setParam"] = [processor](const std::string &path, float value) {
      return processor ? processor->setParamByPath(path, value) : false;
    };
    hostApi["getParam"] = [processor](const std::string &path) {
      return processor ? processor->getParamByPath(path) : 0.0f;
    };
    hostApi["hasEndpoint"] = [processor](const std::string &path) {
      return processor ? processor->hasEndpoint(path) : false;
    };
    hostApi["setCustomValue"] = [processor](const std::string &path, const sol::object &value) {
      if (processor == nullptr) {
        return false;
      }

      std::vector<juce::var> args;
      if (value.is<bool>()) args.emplace_back(value.as<bool>());
      else if (value.is<int>()) args.emplace_back(value.as<int>());
      else if (value.is<double>()) args.emplace_back(value.as<double>());
      else if (value.is<float>()) args.emplace_back(static_cast<double>(value.as<float>()));
      else if (value.is<std::string>()) args.emplace_back(juce::String(value.as<std::string>()));
      else if (value.is<const char*>()) args.emplace_back(juce::String(value.as<const char*>()));
      else return false;

      processor->getOSCServer().setCustomValue(juce::String(path.c_str()), args);
      return true;
    };

    session.lua["host"] = hostApi;
    ctx["host"] = hostApi;
    session.lua["getSampleRate"] = hostApi["getSampleRate"];
    session.lua["getPlayTimeSamples"] = hostApi["getPlayTimeSamples"];
    session.lua["setParam"] = hostApi["setParam"];
    session.lua["getParam"] = hostApi["getParam"];
    session.lua["hasEndpoint"] = hostApi["hasEndpoint"];
    session.lua["setCustomValue"] = hostApi["setCustomValue"];
  }

  auto midiApi = lua.create_table();
  midiApi["sendNoteOn"] = [bcp](int channel, int note, int velocity) {
    if (bcp != nullptr) {
      bcp->sendMidiNoteOn(channel, note, velocity);
    }
  };
  midiApi["sendNoteOff"] = [bcp](int channel, int note) {
    if (bcp != nullptr) {
      bcp->sendMidiNoteOff(channel, note);
    }
  };
  midiApi["sendCC"] = [bcp](int channel, int cc, int value) {
    if (bcp != nullptr) {
      bcp->sendMidiCC(channel, cc, value);
    }
  };
  midiApi["sendPitchBend"] = [bcp](int channel, int value) {
    if (bcp != nullptr) {
      bcp->sendMidiPitchBend(channel, value);
    }
  };
  midiApi["sendProgramChange"] = [bcp](int channel, int program) {
    if (bcp != nullptr) {
      bcp->sendMidiProgramChange(channel, program);
    }
  };
  midiApi["sendAllNotesOff"] = [bcp](int channel) {
    if (bcp != nullptr) {
      bcp->sendMidiCC(channel, 123, 0);
    }
  };
  midiApi["sendAllSoundOff"] = [bcp](int channel) {
    if (bcp != nullptr) {
      bcp->sendMidiCC(channel, 120, 0);
    }
  };
  lua_State* midiLuaState = session.luaState;
  midiApi["pollInputEvent"] = [midiLuaState, midiMgr]() -> sol::object {
    auto midiLua = sol::state_view(midiLuaState);
    if (midiMgr == nullptr) {
      return sol::make_object(midiLua, sol::nil);
    }

    uint8_t status = 0, data1 = 0, data2 = 0;
    int32_t timestamp = 0;
    if (!midiMgr->getInputRing().read(status, data1, data2, timestamp)) {
      return sol::make_object(midiLua, sol::nil);
    }

    sol::table event = midiLua.create_table();
    event["status"] = status;
    event["type"] = MidiStatus::type(status);
    event["channel"] = MidiStatus::channel(status) + 1;
    event["data1"] = data1;
    event["data2"] = data2;
    event["timestamp"] = timestamp;
    return sol::make_object(midiLua, event);
  };
  midiApi["NOTE_OFF"] = 0x80;
  midiApi["NOTE_ON"] = 0x90;
  midiApi["AFTERTOUCH"] = 0xA0;
  midiApi["CONTROL_CHANGE"] = 0xB0;
  midiApi["PROGRAM_CHANGE"] = 0xC0;
  midiApi["CHANNEL_PRESSURE"] = 0xD0;
  midiApi["PITCH_BEND"] = 0xE0;
  midiApi["CLOCK"] = 0xF8;
  midiApi["START"] = 0xFA;
  midiApi["STOP"] = 0xFC;
  midiApi["CONTINUE"] = 0xFB;
  session.lua["Midi"] = midiApi;
  ctx["Midi"] = midiApi;
}

void registerHostApiAndGlobals(
    LoadSession &session,
    ScriptableProcessor *processor,
    std::shared_ptr<dsp_primitives::PrimitiveGraph> graph,
    sol::table &ctx,
    const PathMapperFn &mapInternalToExternal,
    const std::function<std::shared_ptr<dsp_primitives::IPrimitiveNode>(
        const sol::object &)> &toPrimitiveNode) {
  auto hostApi = sol::state_view(session.luaState).create_table();
  hostApi["getSampleRate"] = [processor]() {
    return processor ? processor->getSampleRate() : 44100.0;
  };
  hostApi["getPlayTimeSamples"] = [processor]() {
    return processor ? processor->getPlayTimeSamples() : 0.0;
  };
  hostApi["setParam"] = [processor, mapInternalToExternal](const std::string &path,
                                     float value) {
    if (!processor) {
      return false;
    }
    const std::string externalPath = mapInternalToExternal(path);
    return processor->setParamByPath(externalPath, value);
  };
  hostApi["getParam"] = [processor, mapInternalToExternal](const std::string &path) {
    if (!processor) {
      return 0.0f;
    }
    const std::string externalPath = mapInternalToExternal(path);
    return processor->getParamByPath(externalPath);
  };
  hostApi["getGraphNodeByPath"] = [processor](const std::string &path)
      -> std::shared_ptr<dsp_primitives::IPrimitiveNode> {
    if (!processor) {
      return {};
    }
    return processor->getGraphNodeByPath(path);
  };
  ctx["host"] = hostApi;
  registerMidiApi(session, processor, ctx, false);

  session.lua["getLoopPlaybackPeaks"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::LoopPlaybackNode> node,
      int numBuckets) -> sol::table {
    sol::state_view lua(ts);
    sol::table result(lua, sol::create);
    if (!node || numBuckets <= 0) {
      return result;
    }
    std::vector<float> peaks;
    if (node->computePeaks(numBuckets, peaks)) {
      for (size_t i = 0; i < peaks.size(); ++i) {
        result[i + 1] = peaks[i];
      }
    }
    return result;
  };

  session.lua["getSampleRegionPlaybackPeaks"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node,
      int numBuckets) -> sol::table {
    sol::state_view lua(ts);
    sol::table result(lua, sol::create);
    if (!node || numBuckets <= 0) {
      return result;
    }
    std::vector<float> peaks;
    if (node->computePeaks(numBuckets, peaks)) {
      for (size_t i = 0; i < peaks.size(); ++i) {
        result[i + 1] = peaks[i];
      }
    }
    return result;
  };

  session.lua["analyzeSampleRegionPlaybackRootKey"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return sampleAnalysisToLua(ts, node->analyzeSample());
  };

  session.lua["analyzeSampleRegionPlayback"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return sampleAnalysisToLua(ts, node->analyzeSample());
  };

  session.lua["getSampleRegionPlaybackLastAnalysis"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return sampleAnalysisToLua(ts, node->getLastAnalysis());
  };

  session.lua["extractSampleRegionPlaybackPartials"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return partialDataToLua(ts, node->extractPartials());
  };

  session.lua["getSampleRegionPlaybackPartials"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return partialDataToLua(ts, node->getLastPartials());
  };

  session.lua["buildWavePartials"] = [](
      sol::this_state ts,
      int waveform,
      float fundamental,
      int partialCount,
      float tilt,
      float drift,
      sol::optional<float> pulseWidth) -> sol::table {
    return partialDataToLua(
        ts,
        dsp_primitives::buildWavePartials(waveform, fundamental, partialCount,
                                          tilt, drift,
                                          pulseWidth.value_or(0.5f)));
  };

  session.lua["extractSampleRegionPlaybackTemporalPartials"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node,
      sol::optional<int> maxPartials,
      sol::optional<int> windowSize,
      sol::optional<int> hopSize,
      sol::optional<int> maxFrames) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return temporalPartialDataToLua(ts, node->extractTemporalPartials(
        maxPartials.value_or(dsp_primitives::PartialData::kMaxPartials),
        windowSize.value_or(2048),
        hopSize.value_or(1024),
        maxFrames.value_or(128)));
  };

  session.lua["getSampleRegionPlaybackTemporalPartials"] = [](
      sol::this_state ts,
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) -> sol::table {
    if (!node) {
      sol::state_view lua(ts);
      return sol::table(lua, sol::create);
    }
    return temporalPartialDataToLua(ts, node->getLastTemporalPartials());
  };

  session.lua["requestSampleRegionPlaybackAsyncAnalysis"] = [](
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node,
      sol::optional<int> maxPartials,
      sol::optional<int> windowSize,
      sol::optional<int> hopSize,
      sol::optional<int> maxFrames) {
    if (!node) {
      return;
    }
    node->requestAsyncAnalysis(
        maxPartials.value_or(dsp_primitives::PartialData::kMaxPartials),
        windowSize.value_or(2048),
        hopSize.value_or(1024),
        maxFrames.value_or(128));
  };

  session.lua["isSampleRegionPlaybackAnalysisPending"] = [](
      std::shared_ptr<dsp_primitives::SampleRegionPlaybackNode> node) {
    return node ? node->isAsyncAnalysisPending() : false;
  };

  session.lua["connectNodes"] = [graph, toPrimitiveNode](const sol::object &fromObj,
                                                          const sol::object &toObj) {
    auto from = toPrimitiveNode(fromObj);
    auto to = toPrimitiveNode(toObj);
    if (!from || !to) {
      return false;
    }
    return graph && graph->connect(from, 0, to, 0);
  };
}

} // namespace dsp_host

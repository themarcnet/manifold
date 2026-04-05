#include "DSPHostInternal.h"

#include "../../core/Settings.h"

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

} // namespace dsp_host

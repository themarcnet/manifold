#include "LuaCoreEngine.h"

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include <juce_core/juce_core.h>

#include <cstdio>
#include <utility>

// ============================================================================
// pImpl
// ============================================================================

struct LuaCoreEngine::Impl {
    std::unique_ptr<sol::state> lua;
    mutable std::recursive_mutex luaMutex;
    bool scriptLoaded = false;
    std::string lastError;
    juce::File currentScriptFile;
    std::string packagePath;

    // Hot reload tracking
    juce::Time lastModTime;
    int hotReloadCounter = 0;
    static constexpr int HOT_RELOAD_CHECK_INTERVAL = 30; // frames between checks
    bool hotReloadEnabled = true;
};

// ============================================================================
// Construction / Destruction
// ============================================================================

LuaCoreEngine::LuaCoreEngine() : pImpl(std::make_unique<Impl>()) {}

LuaCoreEngine::~LuaCoreEngine() = default;

// ============================================================================
// Initialization
// ============================================================================

bool LuaCoreEngine::initialize() {
    std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    
    try {
        pImpl->lua = std::make_unique<sol::state>();
        pImpl->lua->open_libraries(
            sol::lib::base,
            sol::lib::math,
            sol::lib::string,
            sol::lib::table,
            sol::lib::package
        );
        return true;
    } catch (const std::exception& e) {
        pImpl->lastError = e.what();
        return false;
    }
}

// ============================================================================
// Script Loading
// ============================================================================

bool LuaCoreEngine::loadScript(const juce::File& scriptFile) {
    if (!scriptFile.existsAsFile()) {
        pImpl->lastError = "Script file not found: " + 
                          scriptFile.getFullPathName().toStdString();
        return false;
    }

    pImpl->currentScriptFile = scriptFile;

    // Set up package.path from script directory
    auto dir = scriptFile.getParentDirectory().getFullPathName().toStdString();
    setPackagePath(dir);

    std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    
    try {
        auto result = pImpl->lua->script_file(scriptFile.getFullPathName().toStdString());
        if (!result.valid()) {
            sol::error err = result;
            pImpl->lastError = err.what();
            pImpl->scriptLoaded = false;
            return false;
        }
    } catch (const std::exception& e) {
        pImpl->lastError = e.what();
        pImpl->scriptLoaded = false;
        return false;
    }

    pImpl->scriptLoaded = true;
    pImpl->lastError.clear();
    pImpl->lastModTime = scriptFile.getLastModificationTime();

    return true;
}

bool LuaCoreEngine::loadScriptFromString(const std::string& code, 
                                         const std::string& sourceName) {
    std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
    
    try {
        auto result = pImpl->lua->script(code, sourceName);
        if (!result.valid()) {
            sol::error err = result;
            pImpl->lastError = err.what();
            pImpl->scriptLoaded = false;
            return false;
        }
    } catch (const std::exception& e) {
        pImpl->lastError = e.what();
        pImpl->scriptLoaded = false;
        return false;
    }

    pImpl->scriptLoaded = true;
    pImpl->lastError.clear();

    return true;
}

// ============================================================================
// Hot Reload
// ============================================================================

bool LuaCoreEngine::reloadCurrentScript() {
    if (!pImpl->currentScriptFile.existsAsFile()) {
        return false;
    }

    auto currentModTime = pImpl->currentScriptFile.getLastModificationTime();
    if (currentModTime == pImpl->lastModTime) {
        return true; // No change, considered success
    }

    return loadScript(pImpl->currentScriptFile);
}

bool LuaCoreEngine::forceReload() {
    if (!pImpl->currentScriptFile.existsAsFile()) {
        return false;
    }
    return loadScript(pImpl->currentScriptFile);
}

void LuaCoreEngine::setHotReloadEnabled(bool enabled) {
    pImpl->hotReloadEnabled = enabled;
}

bool LuaCoreEngine::isHotReloadEnabled() const {
    return pImpl->hotReloadEnabled;
}

void LuaCoreEngine::checkHotReload() {
    if (!pImpl->hotReloadEnabled || !pImpl->scriptLoaded) {
        return;
    }

    // Check at ~1Hz (every 30 frames at 30Hz)
    pImpl->hotReloadCounter++;
    if (pImpl->hotReloadCounter < Impl::HOT_RELOAD_CHECK_INTERVAL) {
        return;
    }
    pImpl->hotReloadCounter = 0;

    if (!pImpl->currentScriptFile.existsAsFile()) {
        return;
    }

    auto currentModTime = pImpl->currentScriptFile.getLastModificationTime();
    if (currentModTime != pImpl->lastModTime) {
        reloadCurrentScript();
    }
}

// ============================================================================
// State Queries
// ============================================================================

bool LuaCoreEngine::isScriptLoaded() const {
    return pImpl->scriptLoaded;
}

const std::string& LuaCoreEngine::getLastError() const {
    return pImpl->lastError;
}

juce::File LuaCoreEngine::getCurrentScriptFile() const {
    return pImpl->currentScriptFile;
}

// ============================================================================
// Lua State Access
// ============================================================================

sol::state& LuaCoreEngine::getLuaState() {
    return *pImpl->lua;
}

const sol::state& LuaCoreEngine::getLuaState() const {
    return *pImpl->lua;
}

std::recursive_mutex& LuaCoreEngine::getMutex() const {
    return pImpl->luaMutex;
}

// ============================================================================
// Package Path
// ============================================================================

void LuaCoreEngine::setPackagePath(const std::string& path) {
    pImpl->packagePath = path;
    if (pImpl->lua) {
        std::lock_guard<std::recursive_mutex> lock(pImpl->luaMutex);
        auto packagePath = path + "/?.lua;" + path + "/?/init.lua";
        (*pImpl->lua)["package"]["path"] = packagePath;
    }
}

std::string LuaCoreEngine::getPackagePath() const {
    return pImpl->packagePath;
}

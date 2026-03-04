#pragma once

#include <functional>
#include <memory>
#include <string>
#include <mutex>

// Forward declarations - no heavy includes in header
namespace sol {
class state;
}

namespace juce {
class File;
class Time;
}

/**
 * LuaCoreEngine: Minimal Lua VM lifecycle management.
 * 
 * Responsibilities:
 *   - Initialize/shutdown Lua VM
 *   - Load and execute scripts
 *   - Hot reload detection
 *   - Error handling
 *   - Thread-safe access to Lua state
 * 
 * Does NOT:
 *   - Register any bindings (UI, DSP, or Control)
 *   - Call script lifecycle hooks (ui_init, ui_update, etc.)
 *   - Know about ScriptableProcessor, Canvas, or any domain types
 * 
 * Threading: Lua state is protected by mutex. All methods are thread-safe.
 */
class LuaCoreEngine {
public:
    LuaCoreEngine();
    ~LuaCoreEngine();

    // Non-copyable, non-movable (mutex member)
    LuaCoreEngine(const LuaCoreEngine&) = delete;
    LuaCoreEngine& operator=(const LuaCoreEngine&) = delete;
    LuaCoreEngine(LuaCoreEngine&&) = delete;
    LuaCoreEngine& operator=(LuaCoreEngine&&) = delete;

    /**
     * Initialize the Lua VM and open standard libraries.
     * Must be called before any other methods.
     * @return true on success, false on error (see getLastError())
     */
    bool initialize();

    /**
     * Load and execute a script file.
     * @param scriptFile Path to .lua file
     * @return true on success, false on error
     */
    bool loadScript(const juce::File& scriptFile);

    /**
     * Load and execute script from string.
     * @param code Lua source code
     * @param sourceName Name for error reporting (e.g., "<inline>")
     * @return true on success, false on error
     */
    bool loadScriptFromString(const std::string& code, const std::string& sourceName);

    /**
     * Reload the current script (hot reload).
     * Only reloads if file modification time has changed.
     * @return true if reloaded or no change, false on error
     */
    bool reloadCurrentScript();

    /**
     * Force reload regardless of modification time.
     * @return true on success, false on error
     */
    bool forceReload();

    /**
     * Check if hot reload is needed. Call periodically (~1Hz).
     * If enabled and file changed, will call reloadCurrentScript().
     */
    void checkHotReload();

    // State queries
    bool isScriptLoaded() const;
    const std::string& getLastError() const;
    juce::File getCurrentScriptFile() const;

    /**
     * Access the underlying Lua state for binding registration.
     * Bindings must lock the mutex via lock() / unlock() around access.
     * @return Reference to sol::state (valid after initialize())
     */
    sol::state& getLuaState();
    const sol::state& getLuaState() const;

    /**
     * Lock/unlock the Lua state mutex for thread-safe access.
     * Use std::lock_guard<std::recursive_mutex> with lock().
     */
    std::recursive_mutex& getMutex() const;

    /**
     * Set the directory for require() paths.
     * Automatically set from script file parent directory on loadScript().
     */
    void setPackagePath(const std::string& path);
    std::string getPackagePath() const;

    /**
     * Configure hot reload behavior.
     */
    void setHotReloadEnabled(bool enabled);
    bool isHotReloadEnabled() const;

private:
    struct Impl;
    std::unique_ptr<Impl> pImpl;
};

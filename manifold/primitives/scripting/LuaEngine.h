#pragma once

#include "core/LuaCoreEngine.h"
#include "DSPPrimitiveWrappers.h"
#include "ILuaControlState.h"
#include "../ui/Canvas.h"
#include <juce_gui_basics/juce_gui_basics.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

// Forward-declare sol types to avoid pulling sol.hpp into every TU
namespace sol {
class state;
}

class ScriptableProcessor;

/**
 * LuaEngine: hosts a Lua VM on the JUCE message thread.
 *
 * Responsibilities:
 *  - Load and execute Lua scripts
 *  - Bind Canvas, CanvasStyle, Graphics to Lua
 *  - Bind `command()` so Lua can post ControlServer commands
 *  - Push processor state snapshot to Lua each tick
 *  - Support hot-reload on script file change
 *
 * Threading: ALL methods must be called on the message thread only.
 */
class LuaEngine : public ILuaControlState {
public:
  LuaEngine();
  ~LuaEngine() override;

  /** Initialise the Lua VM and register all bindings.
   *  @param processor  Scriptable processor seam (for command posting and
   * state reads).
   *  @param rootCanvas The root Canvas node that Lua will populate with
   * children.
   */
  void initialise(ScriptableProcessor *processor, Canvas *rootCanvas);

  /** Load and execute a script file.  Calls ui_init(root) in the script. */
  bool loadScript(const juce::File &scriptFile);

  /** Switch to a different script file (tears down current UI, loads new one).
   */
  bool switchScript(const juce::File &scriptFile);

  /** Reload the currently loaded script (hot-reload). */
  bool reloadCurrentScript();

  /** Get list of available UI scripts in a directory.
   *  Returns vector of {name, absolutePath} pairs. */
  std::vector<std::pair<std::string, std::string>>
  getAvailableScripts(const juce::File &directory) const;

  /** Called on editor resize.  Calls ui_resized(w, h) in the script. */
  void notifyResized(int width, int height);

  /** Called at timer rate (~30Hz).  Pushes state and calls ui_update(state).
   *  Also checks for hot-reload if enough time has elapsed. */
  void notifyUpdate();

  /** Returns true if a script is loaded and running. */
  bool isScriptLoaded() const;

  /** Get last error message (empty if no error). */
  const std::string &getLastError() const;

  /** Get the directory where the current script lives. */
  juce::File getScriptDirectory() const;

  /** Check if there's a Lua callback registered for an OSC address.
   *  Called by OSCServer before dispatching to built-in handlers.
   *  Returns true if Lua handled the message.
   */
  bool invokeOSCCallback(const juce::String& address,
                         const std::vector<juce::var>& args);

  /** Resolve a dynamic OSCQuery VALUE request via Lua callback.
   *  Returns true and fills outArgs when handled.
   */
  bool invokeOSCQueryCallback(const juce::String& path,
                              std::vector<juce::var>& outArgs);

  /** Clear all non-persistent callbacks (called on script switch). */
  void clearNonPersistentCallbacks();

  // ============================================================================
  // ILuaControlState implementation
  // ============================================================================
  ScriptableProcessor* getProcessor() override;
  const ScriptableProcessor* getProcessor() const override;

  juce::File getCurrentScriptFile() const override;
  void setPendingSwitchPath(const std::string& path) override;

  std::unordered_set<std::string>& getManagedDspSlots() override;
  const std::unordered_set<std::string>& getManagedDspSlots() const override;
  std::unordered_set<std::string>& getPersistentDspSlots() override;
  const std::unordered_set<std::string>& getPersistentDspSlots() const override;

  std::unordered_set<std::string>& getUiRegisteredOscEndpoints() override;
  const std::unordered_set<std::string>& getUiRegisteredOscEndpoints() const override;
  std::unordered_set<std::string>& getUiRegisteredOscValues() override;
  const std::unordered_set<std::string>& getUiRegisteredOscValues() const override;

  std::map<juce::String, std::vector<OSCCallback>>& getOscCallbacks() override;
  std::mutex& getOscCallbacksMutex() override;

  std::map<juce::String, OSCQueryHandler>& getOscQueryHandlers() override;
  std::mutex& getOscQueryHandlersMutex() override;

  std::vector<EventListener>& getTempoChangedListeners() override;
  std::vector<EventListener>& getCommitListeners() override;
  std::vector<EventListener>& getRecordingChangedListeners() override;
  std::vector<EventListener>& getLayerStateChangedListeners() override;
  std::vector<EventListener>& getStateChangedListeners() override;
  std::mutex& getEventListenersMutex() override;

  void withLuaState(std::function<void(sol::state&)> callback) override;
  void withLuaState(std::function<void(const sol::state&)> callback) const override;

  void showDirectoryChooser(const std::string& title, 
                            const std::string& initialPath,
                            sol::function callback) override;

private:
  void invokeEventListeners();
  void processPendingOSCCallbacks();
  void registerBindings();
  void pushStateToLua();
  void checkHotReload();

  LuaCoreEngine coreEngine_;  // Core VM lifecycle (no UI/Control deps)
  struct Impl;
  std::unique_ptr<Impl> pImpl;

  JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LuaEngine)
};

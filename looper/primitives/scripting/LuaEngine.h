#pragma once

#include "core/LuaCoreEngine.h"
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

namespace dsp_primitives {

class LoopBufferWrapper {
public:
  void setSize(int sizeSamples, int channels = 2);
  int getLength() const;
  int getChannels() const;
  void setCrossfade(float ms);
  float getCrossfade() const;
  
private:
  int length_ = 0;
  int channels_ = 2;
  float crossfadeMs_ = 0.0f;
};

class PlayheadWrapper {
public:
  void setLoopLength(int length);
  int getLoopLength() const;
  void setPosition(float normalized);
  float getPosition() const;
  void setSpeed(float speed);
  float getSpeed() const;
  void setReversed(bool reversed);
  bool isReversed() const;
  void play();
  void pause();
  void stop();
  
private:
  int loopLength_ = 0;
  int position_ = 0;
  float speed_ = 1.0f;
  bool reversed_ = false;
  bool playing_ = false;
};

class CaptureBufferWrapper {
public:
  void setSize(int sizeSamples, int channels = 2);
  int getSize() const;
  int getChannels() const;
  void setRecordEnabled(bool enabled);
  bool isRecordEnabled() const;
  void clear();
  
private:
  int size_ = 0;
  int channels_ = 2;
  bool recordEnabled_ = false;
};

class QuantizerWrapper {
public:
  void setSampleRate(double sampleRate);
  void setTempo(float bpm);
  float getTempo() const;
  int getQuantizedLength(int samples) const;
  float getQuantizedBars(int samples) const;
  
private:
  double sampleRate_ = 44100.0;
  float tempo_ = 120.0f;
};

} // namespace dsp_primitives

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
class LuaEngine {
public:
  LuaEngine();
  ~LuaEngine();

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

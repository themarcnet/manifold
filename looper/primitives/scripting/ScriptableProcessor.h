#pragma once

#include "../control/ControlServer.h"
#include "ScriptingConfig.h"
#include <array>
#include <memory>
#include <string>
#include <vector>

class OSCServer;
class OSCEndpointRegistry;
class OSCQueryServer;

namespace dsp_primitives {
class PrimitiveGraph;
class GraphRuntime;
}

enum class ScriptableLayerState {
  Empty = 0,
  Playing = 1,
  Recording = 2,
  Overdubbing = 3,
  Muted = 4,
  Stopped = 5,
  Paused = 6,
  Unknown = 255,
};

struct ScriptableLayerSnapshot {
  int index = 0;
  int length = 0;
  int position = 0;
  float speed = 1.0f;
  bool reversed = false;
  float volume = 1.0f;
  ScriptableLayerState state = ScriptableLayerState::Unknown;
  bool muted = false;
};

class ScriptableProcessor {
public:
  virtual ~ScriptableProcessor() = default;

  // Message/control thread: enqueue full command payload.
  virtual bool postControlCommandPayload(const ControlCommand &command) = 0;

  // Message/control thread: enqueue command for audio-thread consumption.
  virtual bool postControlCommand(ControlCommand::Type type, int intParam = 0,
                                   float floatParam = 0.0f) = 0;

  // Message/control thread: networking/control service access.
  virtual ControlServer &getControlServer() = 0;
  virtual OSCServer &getOSCServer() = 0;
  virtual OSCEndpointRegistry &getEndpointRegistry() = 0;
  virtual OSCQueryServer &getOSCQueryServer() = 0;

  // Optional graph/script host hooks. Defaults are safe no-ops so non-looper
  // processors can participate in the shared runtime services.
  virtual std::shared_ptr<dsp_primitives::PrimitiveGraph> getPrimitiveGraph() {
    return {};
  }
  virtual void setGraphProcessingEnabled(bool) {}
  virtual bool isGraphProcessingEnabled() const { return false; }
  virtual int getGraphBlockSize() const { return scripting::BufferConfig::MAX_DSP_BLOCK_SIZE; }
  virtual int getGraphOutputChannels() const { return 2; }
  virtual void requestGraphRuntimeSwap(
      std::unique_ptr<dsp_primitives::GraphRuntime>) {}
  virtual bool loadDspScript(const juce::File &) { return false; }
  virtual bool loadDspScript(const juce::File &, const std::string &/*slot*/) { return false; }
  virtual bool loadDspScriptFromString(const std::string &, const std::string &) {
    return false;
  }
  virtual bool loadDspScriptFromString(const std::string &, const std::string &,
                                       const std::string &/*slot*/) {
    return false;
  }
  virtual bool reloadDspScript() { return false; }
  virtual bool reloadDspScript(const std::string &/*slot*/) { return false; }
  virtual bool unloadDspSlot(const std::string &/*slot*/) { return false; }
  virtual bool isDspScriptLoaded() const { return false; }
  virtual bool isDspSlotLoaded(const std::string &/*slot*/) const { return false; }
  virtual const std::string &getDspScriptLastError() const {
    static const std::string empty;
    return empty;
  }
  virtual void drainRetiredGraphRuntimes() {}

  // =========================================================================
  // Generic path-based parameter access (Phase 1 of DSP scripting)
  // These enable Lua/primitives to configure any registered endpoint uniformly.
  // =========================================================================

  // Set a parameter by path. Returns true if command was enqueued.
  // Path must be a writable endpoint registered in OSCEndpointRegistry.
  // Thread-safe: enqueues command for audio thread, does not mutate directly.
  virtual bool setParamByPath(const std::string &path, float value) = 0;

  // Get a parameter value by path. Returns 0.0f for unknown paths.
  // Path must be a readable endpoint. Reads from projected state snapshot.
  // Thread-safe: reads from atomic snapshot, safe from any thread.
  virtual float getParamByPath(const std::string &path) const = 0;

  // Check if a path is a known endpoint.
  virtual bool hasEndpoint(const std::string &path) const = 0;

  // Snapshot accessors for UI/control-thread reads.
  virtual int getNumLayers() const = 0;
  virtual bool getLayerSnapshot(int index,
                                ScriptableLayerSnapshot &out) const = 0;
  virtual int getCaptureSize() const = 0;
  virtual bool computeLayerPeaks(int layerIndex, int numBuckets,
                                 std::vector<float> &outPeaks) const = 0;

  // Optional slot/path-aware waveform query.
  // Default keeps legacy behavior and forwards to computeLayerPeaks().
  virtual bool computeLayerPeaksForPath(const std::string &pathBase,
                                        int layerIndex, int numBuckets,
                                        std::vector<float> &outPeaks) const {
    (void)pathBase;
    return computeLayerPeaks(layerIndex, numBuckets, outPeaks);
  }

  virtual bool computeCapturePeaks(int startAgo, int endAgo, int numBuckets,
                                   std::vector<float> &outPeaks) const = 0;

  virtual float getTempo() const = 0;
  virtual float getTargetBPM() const = 0;
  virtual float getSamplesPerBar() const = 0;
  virtual double getSampleRate() const = 0;
  virtual double getPlayTimeSamples() const = 0;
  virtual float getMasterVolume() const = 0;
  virtual float getInputVolume() const = 0;
  virtual bool isPassthroughEnabled() const = 0;
  virtual bool isRecording() const = 0;
  virtual bool isOverdubEnabled() const = 0;
  virtual int getActiveLayerIndex() const = 0;
  virtual bool isForwardCommitArmed() const = 0;
  virtual float getForwardCommitBars() const = 0;
  virtual int getRecordModeIndex() const = 0;
  virtual int getCommitCount() const = 0;
  virtual std::array<float, 32> getSpectrumData() const = 0;

  // Ableton Link integration (default no-ops for processors without Link)
  virtual bool isLinkEnabled() const { return false; }
  virtual void setLinkEnabled(bool /*enabled*/) {}
  virtual bool isLinkTempoSyncEnabled() const { return false; }
  virtual void setLinkTempoSyncEnabled(bool /*enabled*/) {}
  virtual bool isLinkStartStopSyncEnabled() const { return false; }
  virtual void setLinkStartStopSyncEnabled(bool /*enabled*/) {}
  virtual int getLinkNumPeers() const { return 0; }
  virtual bool isLinkPlaying() const { return false; }
  virtual double getLinkBeat() const { return 0.0; }
  virtual double getLinkPhase() const { return 0.0; }
  virtual void requestLinkTempo(double /*bpm*/) {}
  virtual void requestLinkStart() {}
  virtual void requestLinkStop() {}
  virtual void processLinkPendingRequests() {}
};

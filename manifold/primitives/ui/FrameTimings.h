#pragma once

#include <atomic>
#include <cstdint>

struct FrameTimingStage {
  std::atomic<int64_t> currentUs{0};
  std::atomic<int64_t> peakUs{0};
  std::atomic<int64_t> avgUsX100{0};

  int64_t getCurrentUs() const noexcept {
    return currentUs.load(std::memory_order_relaxed);
  }

  int64_t getPeakUs() const noexcept {
    return peakUs.load(std::memory_order_relaxed);
  }

  int64_t getAvgUsX100() const noexcept {
    return avgUsX100.load(std::memory_order_relaxed);
  }

  int64_t getAvgUs() const noexcept {
    return getAvgUsX100() / 100;
  }
};

struct FrameTimings {
  FrameTimingStage total;
  FrameTimingStage dsp;
  FrameTimingStage pushState;
  FrameTimingStage eventListeners;
  FrameTimingStage uiUpdate;
  FrameTimingStage paint;
  FrameTimingStage anim;
  FrameTimingStage renderDispatch;
  FrameTimingStage syncHosts;
  FrameTimingStage present;
  FrameTimingStage overBudget;
  FrameTimingStage canvasRepaintLead;
  std::atomic<int64_t> frameCount{0};
  std::atomic<int64_t> overBudgetCount{0};
  std::atomic<int64_t> editorWidth{0};
  std::atomic<int64_t> editorHeight{0};

  // Total paint time accumulated across ALL canvases (not just root)
  std::atomic<int64_t> totalPaintAccumulatedUs{0};

  // ImGui smoke-test / host instrumentation
  std::atomic<bool> imguiContextReady{false};
  std::atomic<bool> imguiTestWindowVisible{false};
  std::atomic<bool> imguiWantCaptureMouse{false};
  std::atomic<bool> imguiWantCaptureKeyboard{false};
  std::atomic<int64_t> imguiFrameCount{0};
  std::atomic<int64_t> imguiRenderUs{0};
  std::atomic<int64_t> imguiVertexCount{0};
  std::atomic<int64_t> imguiIndexCount{0};
  std::atomic<int64_t> imguiButtonClicks{0};
  std::atomic<bool> imguiDocumentLoaded{false};
  std::atomic<bool> imguiDocumentDirty{false};
  std::atomic<int64_t> imguiDocumentLineCount{0};

  // CPU and memory utilization (updated by editor)
  std::atomic<float> cpuPercent{0.0f};         // 0-100%
  std::atomic<int64_t> processPssBytes{0};     // proportional set size
  std::atomic<int64_t> privateDirtyBytes{0};   // private dirty memory
  std::atomic<int64_t> luaHeapBytes{0};        // Lua VM heap
  std::atomic<int64_t> glibcHeapUsedBytes{0};  // glibc allocated heap in use (uordblks)
  std::atomic<int64_t> glibcArenaBytes{0};     // arena bytes from sbrk/heap
  std::atomic<int64_t> glibcMmapBytes{0};      // bytes in mmap'd blocks
  std::atomic<int64_t> glibcFreeHeldBytes{0};  // free bytes held by allocator
  std::atomic<int64_t> glibcReleasableBytes{0}; // top-most releasable bytes
  std::atomic<int64_t> glibcArenaCount{0};     // allocator heap/arena count

  // Plugin-attributable deltas relative to processor construction baseline.
  std::atomic<int64_t> pluginDeltaPssBytes{0};
  std::atomic<int64_t> pluginDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> pluginDeltaHeapBytes{0};
  std::atomic<int64_t> pluginDeltaArenaBytes{0};

  // UI-attributable deltas relative to editor open baseline.
  std::atomic<int64_t> uiDeltaPssBytes{0};
  std::atomic<int64_t> uiDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> uiDeltaHeapBytes{0};

  // Stage snapshots relative to processor construction baseline.
  std::atomic<int64_t> afterLuaInitDeltaPssBytes{0};
  std::atomic<int64_t> afterLuaInitDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> afterBindingsDeltaPssBytes{0};
  std::atomic<int64_t> afterBindingsDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> afterScriptLoadDeltaPssBytes{0};
  std::atomic<int64_t> afterScriptLoadDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> afterDspDeltaPssBytes{0};
  std::atomic<int64_t> afterDspDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> afterUiOpenDeltaPssBytes{0};
  std::atomic<int64_t> afterUiOpenDeltaPrivateDirtyBytes{0};
  std::atomic<int64_t> afterUiIdleDeltaPssBytes{0};
  std::atomic<int64_t> afterUiIdleDeltaPrivateDirtyBytes{0};

  // Plugin-owned GPU resources (not host/driver VRAM mappings).
  std::atomic<int64_t> gpuFontAtlasBytes{0};
  std::atomic<int64_t> gpuSurfaceColorBytes{0};
  std::atomic<int64_t> gpuSurfaceDepthBytes{0};
  std::atomic<int64_t> gpuTotalBytes{0};

  // ImGui CPU-side internal state.
  std::atomic<int64_t> imguiWindowCount{0};
  std::atomic<int64_t> imguiTableCount{0};
  std::atomic<int64_t> imguiTabBarCount{0};
  std::atomic<int64_t> imguiViewportCount{0};
  std::atomic<int64_t> imguiFontCount{0};
  std::atomic<int64_t> imguiWindowStateBytes{0};
  std::atomic<int64_t> imguiDrawBufferBytes{0};
  std::atomic<int64_t> imguiInternalStateBytes{0};

  // Deeper UI/runtime category breakdown.
  std::atomic<int64_t> runtimeNodeCount{0};
  std::atomic<int64_t> runtimeNodeBytes{0};
  std::atomic<int64_t> runtimeCallbackCount{0};
  std::atomic<int64_t> runtimeUserDataEntries{0};
  std::atomic<int64_t> runtimeUserDataBytes{0};
  std::atomic<int64_t> runtimeCustomPayloadBytes{0};
  std::atomic<int64_t> displayListCount{0};
  std::atomic<int64_t> displayListCommandCount{0};
  std::atomic<int64_t> displayListBytes{0};
  std::atomic<int64_t> renderSnapshotNodeCount{0};
  std::atomic<int64_t> renderSnapshotBytes{0};
  std::atomic<int64_t> customSurfaceStateBytes{0};
  std::atomic<int64_t> scriptSourceBytes{0};

  // Lua bridge / registry / callback state.
  std::atomic<int64_t> luaGlobalCount{0};
  std::atomic<int64_t> luaRegistryEntryCount{0};
  std::atomic<int64_t> luaPackageLoadedCount{0};
  std::atomic<int64_t> luaOscPathCount{0};
  std::atomic<int64_t> luaOscCallbackCount{0};
  std::atomic<int64_t> luaOscQueryHandlerCount{0};
  std::atomic<int64_t> luaEventListenerCount{0};
  std::atomic<int64_t> luaManagedDspSlotCount{0};
  std::atomic<int64_t> luaOverlayCacheCount{0};

  // Endpoint / registry footprint proxies.
  std::atomic<int64_t> endpointTotalCount{0};
  std::atomic<int64_t> endpointCustomCount{0};
  std::atomic<int64_t> endpointPathBytes{0};
  std::atomic<int64_t> endpointDescriptionBytes{0};

  // DSP/script host bookkeeping.
  std::atomic<int64_t> dspHostCount{0};
  std::atomic<int64_t> dspScriptSourceBytes{0};

  // Editor/shell retained host-side config state.
  std::atomic<int64_t> shellScriptListRowCount{0};
  std::atomic<int64_t> shellScriptListBytes{0};
  std::atomic<int64_t> shellHierarchyRowCount{0};
  std::atomic<int64_t> shellHierarchyBytes{0};
  std::atomic<int64_t> shellInspectorRowCount{0};
  std::atomic<int64_t> shellInspectorBytes{0};
  std::atomic<int64_t> shellScriptInspectorBytes{0};
  std::atomic<int64_t> shellMainEditorTextBytes{0};

  void update(int64_t totalUs, int64_t pushStateUs, int64_t eventListenersUs,
              int64_t uiUpdateUs, int64_t paintUs,
              int64_t animUs = 0, int64_t renderDispatchUs = 0,
              int64_t syncHostsUs = 0, int64_t presentUs = 0,
              int64_t overBudgetUs = 0, int64_t canvasRepaintLeadUs = 0) noexcept {
    updateStage(total, totalUs);
    updateStage(pushState, pushStateUs);
    updateStage(eventListeners, eventListenersUs);
    updateStage(uiUpdate, uiUpdateUs);
    updateStage(paint, paintUs);
    updateStage(anim, animUs);
    updateStage(renderDispatch, renderDispatchUs);
    updateStage(syncHosts, syncHostsUs);
    updateStage(present, presentUs);
    updateStage(overBudget, overBudgetUs);
    updateStage(canvasRepaintLead, canvasRepaintLeadUs);
    if (overBudgetUs > 0) {
      overBudgetCount.fetch_add(1, std::memory_order_relaxed);
    }
    frameCount.fetch_add(1, std::memory_order_relaxed);
  }

  void resetPeaks() noexcept {
    total.peakUs.store(0, std::memory_order_relaxed);
    dsp.peakUs.store(0, std::memory_order_relaxed);
    pushState.peakUs.store(0, std::memory_order_relaxed);
    eventListeners.peakUs.store(0, std::memory_order_relaxed);
    uiUpdate.peakUs.store(0, std::memory_order_relaxed);
    paint.peakUs.store(0, std::memory_order_relaxed);
    anim.peakUs.store(0, std::memory_order_relaxed);
    renderDispatch.peakUs.store(0, std::memory_order_relaxed);
    syncHosts.peakUs.store(0, std::memory_order_relaxed);
    present.peakUs.store(0, std::memory_order_relaxed);
    overBudget.peakUs.store(0, std::memory_order_relaxed);
    canvasRepaintLead.peakUs.store(0, std::memory_order_relaxed);
    overBudgetCount.store(0, std::memory_order_relaxed);
  }

private:
  static constexpr int64_t kEmaAlphaNumerator = 5;
  static constexpr int64_t kEmaAlphaDenominator = 100;

  static void updateStage(FrameTimingStage &stage, int64_t durationUs) noexcept {
    stage.currentUs.store(durationUs, std::memory_order_relaxed);

    const int64_t previousPeak = stage.peakUs.load(std::memory_order_relaxed);
    if (durationUs > previousPeak) {
      stage.peakUs.store(durationUs, std::memory_order_relaxed);
    }

    const int64_t previousAvgX100 = stage.avgUsX100.load(std::memory_order_relaxed);
    const int64_t durationX100 = durationUs * 100;
    const int64_t nextAvgX100 =
        (previousAvgX100 == 0)
            ? durationX100
            : ((previousAvgX100 * (kEmaAlphaDenominator - kEmaAlphaNumerator)) +
               (durationX100 * kEmaAlphaNumerator)) /
                  kEmaAlphaDenominator;
    stage.avgUsX100.store(nextAvgX100, std::memory_order_relaxed);
  }
};

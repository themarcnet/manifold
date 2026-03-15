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
  FrameTimingStage pushState;
  FrameTimingStage eventListeners;
  FrameTimingStage uiUpdate;
  FrameTimingStage paint;
  std::atomic<int64_t> frameCount{0};

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

  void update(int64_t totalUs, int64_t pushStateUs, int64_t eventListenersUs,
              int64_t uiUpdateUs, int64_t paintUs) noexcept {
    updateStage(total, totalUs);
    updateStage(pushState, pushStateUs);
    updateStage(eventListeners, eventListenersUs);
    updateStage(uiUpdate, uiUpdateUs);
    updateStage(paint, paintUs);
    frameCount.fetch_add(1, std::memory_order_relaxed);
  }

  void resetPeaks() noexcept {
    total.peakUs.store(0, std::memory_order_relaxed);
    pushState.peakUs.store(0, std::memory_order_relaxed);
    eventListeners.peakUs.store(0, std::memory_order_relaxed);
    uiUpdate.peakUs.store(0, std::memory_order_relaxed);
    paint.peakUs.store(0, std::memory_order_relaxed);
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

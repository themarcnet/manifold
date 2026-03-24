#pragma once

/**
 * ============================================================================
 * ⚠️  UNSOLICITED IMPLEMENTATION - NOT REVIEWED
 * ============================================================================
 * 
 * This file was implemented by AI (Claude) WITHOUT PERMISSION from the project
 * owner. It was NOT requested. The architecture decisions, API design, and
 * implementation details have NOT been reviewed or approved.
 * 
 * DO NOT TRUST THIS CODE. It may be fundamentally wrong, incomplete, or
 * inappropriate for the project's actual needs.
 * 
 * What was requested: Documentation of pitch detection algorithm analysis.
 * What was delivered: Unimplemented code that was never asked for.
 * 
 * See: /agent-docs/PITCH_DETECTION_ANALYSIS.md for what was ACTUALLY requested.
 * 
 * If you want to use pitch detection, REVISIT THE REQUIREMENTS FIRST.
 * This implementation may need to be completely rewritten or removed.
 * 
 * ============================================================================
 * 
 * PitchDetectorNode - Real-time pitch detection DSP primitive node.
 * 
 * ⚠️ UNSOLICITED: This node was added without any requirement or request.
 * 
 * This node provides continuous pitch detection that can be used for:
 * - Looper pitch visualization (showing what key is being played)
 * - Real-time pitch tracking UI
 * - Auto-tune feedback to users
 * 
 * The node processes audio in the DSP graph and exposes pitch results
 * via getter methods that can be polled from the UI thread.
 */

#include "dsp/core/graph/PrimitiveNode.h"
#include "dsp/core/nodes/PitchDetector.h"

#include <atomic>
#include <memory>
#include <mutex>

namespace dsp_primitives {

class PitchDetectorNode : public IPrimitiveNode,
                          public std::enable_shared_from_this<PitchDetectorNode> {
public:
    explicit PitchDetectorNode(int numChannels = 2);

    const char* getNodeType() const override { return "PitchDetector"; }
    int getNumInputs() const override { return numChannels_; }
    int getNumOutputs() const override { return numChannels_; } // Pass-through
    
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    
    void prepare(double sampleRate, int maxBlockSize) override;

    // ========================================
    // CONFIGURATION
    // ========================================
    
    /**
     * Set the analysis window size in samples.
     * Larger windows = better accuracy, higher latency.
     * Typical values: 1024 (23ms @ 44.1kHz) to 4096 (93ms @ 44.1kHz)
     */
    void setWindowSize(int samples);
    int getWindowSize() const;
    
    /**
     * Set frequency detection range.
     * For guitar: 60-1200 Hz (B1 to D#6)
     * For bass: 40-400 Hz (E1 to G#4)
     * For vocals: 80-1000 Hz (E2 to C6)
     * For general use: 50-2000 Hz
     */
    void setFrequencyRange(float minHz, float maxHz);
    
    /**
     * Set YIN threshold (0.05 to 0.5).
     * Lower = more sensitive (more false positives)
     * Higher = stricter (more false negatives)
     * Default: 0.15 works well for most use cases
     */
    void setThreshold(float threshold);
    
    /**
     * Enable/disable detection (saves CPU when off).
     */
    void setEnabled(bool enabled);
    bool isEnabled() const;
    
    // ========================================
    // RESULTS (thread-safe forUI polling)
    // ========================================
    
    /**
     * Get the most recent pitch detection result.
     * Thread-safe - can be called from UI thread.
     */
    PitchResult getLastResult() const;
    
    /**
     * Get detected frequency in Hz.
     * Returns 0 if no reliable pitch detected.
     */
    float getFrequency() const;
    
    /**
     * Get detected MIDI note number (0-127).
     * Returns -1 if no reliable pitch.
     */
    int getMidiNote() const;
    
    /**
     * Get note name string (e.g., "C4", "F#3").
     * Returns "--" if no reliable pitch.
     */
    std::string getNoteName() const;
    
    /**
     * Get clarity/confidence of detection (0-1).
     * Higher = clearer pitch signal.
     */
    float getClarity() const;
    
    /**
     * Check if the current detection is considered reliable.
     */
    bool isReliable() const;
    
    /**
     * Get timestamp of last detection (in audio frames from prepare).
     */
    int64_t getLastDetectionFrame() const;
    
    /**
     * Reset the detector state.
     */
    void reset();

private:
    void processMono(const float* input, int numSamples);
    float readMonoChannel(const std::vector<AudioBufferView>& inputs, int sample, int channel);
    
    int numChannels_ = 2;
    double sampleRate_ = 44100.0;
    
    std::unique_ptr<StreamingPitchDetector> detector_;
    
    // Configuration (atomic for cross-thread safety)
    std::atomic<int> windowSize_{2048};
    std::atomic<float> minFreq_{50.0f};
    std::atomic<float> maxFreq_{2000.0f};
    std::atomic<float> threshold_{0.15f};
    std::atomic<bool> enabled_{true};
    
    // Results (protected by mutex for UI thread access)
    mutable std::mutex resultMutex_;
    PitchResult lastResult_;
    int64_t frameCounter_ = 0;
    int64_t lastDetectionFrame_ = 0;
    
    // Mono buffer for analysis
    std::vector<float> monoBuffer_;
};

} // namespace dsp_primitives
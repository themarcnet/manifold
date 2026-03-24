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
 * PitchDetector - YIN-based pitch detection for audio applications
 * 
 * This provides both offline (sample analysis) and real-time (streaming) pitch detection.
 * The YIN algorithm is chosen for its balance of accuracy and computational efficiency,
 * making it suitable for:
 * 
 * - Sample root key detection (offline analysis on capture)
 * - Real-time pitch tracking for looper visualization
 * - Pitch-correlated time-stretching/tuning operations
 * 
 * Algorithm reference: de Cheveigné & Kawahara (2002) - "YIN, a fundamental frequency
 * estimator for speech and music"
 */

#include <cmath>
#include <vector>
#include <algorithm>
#include <numeric>
#include <limits>

namespace dsp_primitives {

struct PitchResult {
    float frequency = 0.0f;      // Detected frequency in Hz (0 = no pitch detected)
    float clarity = 0.0f;        // Clarity/confidence metric (0-1, higher = clearer pitch)
    int midiNote = -1;           // Nearest MIDI note number (0-127, -1 = none)
    float centsDeviation = 0.0f; // Deviation from nearest semitone in cents (-50 to 50)
    bool isReliable = false;     // Whether the detection is considered reliable
};

struct SampleAnalysisResult {
    int midiNote = 60;                // Detected root key (default C4)
    float frequency = 261.63f;        // Detected frequency
    float confidence = 0.0f;          // Overall confidence (0-1)
    float pitchStability = 0.0f;      // How stable the pitch is across analysis windows
    bool isPercussive = false;        // True if sample appears unpitched/percussive
    int attackEndSample = 0;          // Where the attack phase ends
    int analysisStartSample = 0;      // Start of analyzed region
    int analysisEndSample = 0;        // End of analyzed region
    const char* algorithm = "none";  // Algorithm used
};

class PitchDetector {
public:
    explicit PitchDetector(int maxBufferSize = 8192)
        : maxBufferSize_(maxBufferSize)
        , yinBuffer_(maxBufferSize)
        , windowBuffer_(maxBufferSize)
    {
    }

    // ========================================
    // CONFIGURATION
    // ========================================
    
    void setSampleRate(float sampleRate) {
        sampleRate_ = sampleRate;
    }
    
    void setMinFrequency(float minHz) {
        minFrequency_ = std::max(20.0f, std::min(minHz, 2000.0f));
    }
    
    void setMaxFrequency(float maxHz) {
        maxFrequency_ = std::max(100.0f, std::min(maxHz, 8000.0f));
    }
    
    // YIN threshold (0.05-0.5, lower = more sensitive, higher = stricter)
    void setThreshold(float threshold) {
        threshold_ = std::clamp(threshold, 0.05f, 0.5f);
    }
    
    // ========================================
    // YIN PITCH DETECTION
    // ========================================
    
    /**
     * Detect pitch using the YIN algorithm.
     * 
     * @param samples Interleaved or mono audio samples
     * @param numSamples Number of samples in the buffer
     * @param channel Which channel to analyze (for multi-channel buffers)
     * @param stride Sample stride (1 for mono, numChannels for interleaved)
     * @return PitchResult with detected frequency and metadata
     */
    PitchResult detectPitchYIN(const float* samples, int numSamples, 
                                int channel, int stride) {
        if (numSamples < minSamplesForAnalysis()) {
            return {};
        }
        
        // Apply Hann window
        applyHannWindow(samples, numSamples, channel, stride);
        
        const int maxLag = std::min(static_cast<int>(sampleRate_ / minFrequency_), numSamples / 2);
        const int minLag = std::max(static_cast<int>(sampleRate_ / maxFrequency_), 2);
        
        if (maxLag <= minLag || maxLag >= numSamples) {
            return {};
        }
        
        // Step 1: Compute difference function
        computeDifferenceFunction(numSamples, maxLag);
        
        // Step 2: Cumulative mean normalized difference
        computeCMNDF(maxLag);
        
        // Step 3: Find the pitch (absolute threshold)
        int bestLag = findPitchLag(minLag, maxLag);
        
        if (bestLag < 0) {
            return {};
        }
        
        // Step 4: Parabolic interpolation for sub-sample accuracy
        float refinedLag = parabolicInterpolation(bestLag, maxLag);
        
        // Calculate frequency
        float frequency = sampleRate_ / refinedLag;
        
        if (frequency < minFrequency_ || frequency > maxFrequency_) {
            return {};
        }
        
        // Calculate clarity (1 - yinValue at best lag)
        float clarity = (bestLag > 0 && bestLag < static_cast<int>(yinBuffer_.size())) 
            ? 1.0f - yinBuffer_[bestLag] 
            : 0.0f;
        clarity = std::clamp(clarity, 0.0f, 1.0f);
        
        PitchResult result;
        result.frequency = frequency;
        result.clarity = clarity;
        result.isReliable = clarity > 0.5f;
        
        // Convert to MIDI
        result.midiNote = frequencyToMidi(frequency);
        result.centsDeviation = calculateCentsDeviation(frequency, result.midiNote);
        
        return result;
    }
    
    /**
     * Convenience overload for mono buffers.
     */
    PitchResult detectPitchYIN(const float* samples, int numSamples) {
        return detectPitchYIN(samples, numSamples, 0, 1);
    }
    
    /**
     * Detect pitch from a juce::AudioBuffer.
     */
    PitchResult detectPitchYIN(const float* const* channelData, int numSamples, int channel = 0) {
        return detectPitchYIN(channelData[channel], numSamples, 0, 1);
    }

    // ========================================
    // OFFLINE SAMPLE ANALYSIS
    // ========================================
    
    /**
     * Analyze a sample buffer to detect its root key.
     * This is designed for offline sample analysis (e.g., when capturing for a sampler).
     * 
     * @param samples Mono sample data
     * @param numSamples Number of samples
     * @param skipAttackMs Milliseconds to skip at start (default: auto-detect)
     * @param analysisDurationMs Duration to analyze after attack (default: use available)
     * @return SampleAnalysisResult with detected root key and metadata
     */
    SampleAnalysisResult analyzeSampleRootKey(const float* samples, int numSamples,
                                               float skipAttackMs = -1.0f,
                                               float analysisDurationMs = -1.0f) {
        SampleAnalysisResult result;

        if (!samples || numSamples <= 0) {
            result.isPercussive = true;
            result.confidence = 0.0f;
            return result;
        }

        const float minFreq = 50.0f;
        const float maxFreq = 4000.0f;
        const float yinThreshold = 0.15f;
        const int manualSkipSamples = static_cast<int>(((skipAttackMs > 0.0f) ? skipAttackMs : 50.0f) * sampleRate_ / 1000.0f);
        const int analysisWindowSamples = static_cast<int>(((analysisDurationMs > 0.0f) ? analysisDurationMs : 300.0f) * sampleRate_ / 1000.0f);

        result.isPercussive = detectPercussive(samples, numSamples);

        const int autoAttackEnd = findAttackEnd(samples, numSamples);
        const int attackEndSamples = std::max(autoAttackEnd, manualSkipSamples);
        result.attackEndSample = attackEndSamples;

        const int endSample = std::min(attackEndSamples + analysisWindowSamples, numSamples);
        result.analysisStartSample = attackEndSamples;
        result.analysisEndSample = endSample;

        const int analysisSamples = std::max(0, endSample - attackEndSamples);
        const int minRequiredSamples = static_cast<int>(sampleRate_ / maxFreq * 3.0f);
        if (analysisSamples < minRequiredSamples) {
            result.isPercussive = true;
            result.confidence = 0.0f;
            result.pitchStability = 0.0f;
            result.algorithm = "none";
            return result;
        }

        const float* analysisStart = samples + attackEndSamples;
        std::vector<float> analysisBuffer(static_cast<size_t>(analysisSamples));
        for (int i = 0; i < analysisSamples; ++i) {
            analysisBuffer[static_cast<size_t>(i)] = analysisStart[i];
        }

        const PitchResult yinResult = detectPitchYIN(analysisBuffer.data(), analysisSamples);
        const PitchResult nsdfResult = detectPitchNSDF(analysisBuffer.data(), analysisSamples, 0.6f, minFreq, maxFreq);

        const StabilityResult stability = analyzePitchStability(analysisBuffer.data(), analysisSamples,
                                                                static_cast<int>(sampleRate_ * 0.05f),
                                                                yinThreshold, minFreq, maxFreq);
        result.pitchStability = stability.stability;

        float bestPitch = 0.0f;
        float bestConfidence = 0.0f;
        const char* algorithm = "none";

        if (yinResult.frequency > 0.0f && yinResult.clarity > 0.5f) {
            bestPitch = yinResult.frequency;
            bestConfidence = yinResult.clarity;
            algorithm = "YIN";
        } else if (nsdfResult.frequency > 0.0f && nsdfResult.clarity > 0.5f) {
            bestPitch = nsdfResult.frequency;
            bestConfidence = nsdfResult.clarity;
            algorithm = "NSDF";
        }

        if (stability.averagePitch > 0.0f && stability.stability > 0.7f) {
            bestPitch = stability.averagePitch;
            bestConfidence = std::max(bestConfidence, stability.stability);
            algorithm = "YIN+Stability";
        }

        if (bestPitch > 0.0f) {
            result.frequency = bestPitch;
            result.midiNote = frequencyToMidi(bestPitch);
            result.confidence = std::clamp(bestConfidence * (result.isPercussive ? 0.5f : 1.0f) * result.pitchStability,
                                           0.0f, 1.0f);
            result.algorithm = algorithm;
            return result;
        }

        result.confidence = 0.0f;
        result.pitchStability = stability.stability;
        result.algorithm = "none";
        return result;
    }

    // ========================================
    // UTILITY FUNCTIONS
    // ========================================
    
    /**
     * Convert frequency to MIDI note number.
     */
    static int frequencyToMidi(float frequency) {
        if (frequency <= 0.0f) return -1;
        return static_cast<int>(std::round(69.0f + 12.0f * std::log2(frequency / 440.0f)));
    }
    
    /**
     * Convert MIDI note number to frequency.
     */
    static float midiToFrequency(int midiNote) {
        return 440.0f * std::pow(2.0f, (midiNote - 69) / 12.0f);
    }
    
    /**
     * Calculate cents deviation from nearest semitone.
     */
    static float calculateCentsDeviation(float frequency, int midiNote) {
        float nearestFreq = midiToFrequency(midiNote);
        return 1200.0f * std::log2(frequency / nearestFreq);
    }
    
    /**
     * Convert frequency to note name string (e.g., "C4", "F#3").
     */
    static std::string frequencyToNoteName(float frequency) {
        static const char* noteNames[] = {
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
        };
        int midi = frequencyToMidi(frequency);
        if (midi < 0 || midi > 127) return "--";
        int octave = (midi / 12) - 1;
        int note = midi % 12;
        return std::string(noteNames[note]) + std::to_string(octave);
    }
    
    /**
     * Calculate RMS level of a buffer.
     */
    static float calculateRMS(const float* samples, int numSamples, int stride = 1) {
        if (numSamples <= 0) return 0.0f;
        float sum = 0.0f;
        for (int i = 0; i < numSamples; ++i) {
            float s = samples[i * stride];
            sum += s * s;
        }
        return std::sqrt(sum / numSamples);
    }
    
    /**
     * Apply Hann window in-place to the window buffer.
     */
    void applyHannWindow(const float* samples, int numSamples, int channel = 0, int stride = 1) {
        if (static_cast<int>(windowBuffer_.size()) < numSamples) {
            windowBuffer_.resize(numSamples);
        }
        
        for (int i = 0; i < numSamples; ++i) {
            float multiplier = 0.5f * (1.0f - std::cos(2.0f * M_PI * i / (numSamples - 1)));
            int idx = channel + i * stride;
            windowBuffer_[i] = samples[idx] * multiplier;
        }
    }

private:
    struct StabilityResult {
        float stability = 0.0f;
        std::vector<float> pitches;
        float averagePitch = 0.0f;
    };

    int minSamplesForAnalysis() const {
        // Need at least 2 periods of the lowest frequency
        return static_cast<int>(sampleRate_ / minFrequency_ * 2.5f);
    }
    
    void computeDifferenceFunction(int numSamples, int maxLag) {
        // Step 1: Compute difference function d_t(tau)
        // d_t(tau) = sum_{j=1}^{W} (x_j - x_{j+tau})^2
        
        if (static_cast<int>(yinBuffer_.size()) < maxLag) {
            yinBuffer_.resize(maxLag + 1);
        }
        
        yinBuffer_[0] = 1.0f; // d(0) is always 0, but we set to 1 to avoid division issues
        
        for (int lag = 1; lag <= maxLag; ++lag) {
            float sum = 0.0f;
            for (int i = 0; i < maxLag; ++i) {
                float delta = windowBuffer_[i] - windowBuffer_[i + lag];
                sum += delta * delta;
            }
            yinBuffer_[lag] = sum;
        }
    }
    
    void computeCMNDF(int maxLag) {
        // Step 2: Cumulative Mean Normalized Difference Function
        // yinBuffer_[tau] = d_[tau] / (1/tau * sum_{j=1}^{tau} d_j)
        
        float runningSum = 0.0f;
        for (int lag = 1; lag <= maxLag; ++lag) {
            runningSum += yinBuffer_[lag];
            yinBuffer_[lag] = (yinBuffer_[lag] * lag) / runningSum;
        }
    }
    
    int findPitchLag(int minLag, int maxLag) {
        // Step 3: Find the first lag below threshold after minLag
        int bestLag = -1;
        float minValue = std::numeric_limits<float>::max();
        
        for (int lag = minLag; lag <= maxLag && lag < static_cast<int>(yinBuffer_.size()); ++lag) {
            float val = yinBuffer_[lag];
            
            if (val < threshold_) {
                // Found a lag below threshold
                // Find local minimum in this region
                int searchLag = lag;
                while (searchLag + 1 <= maxLag && 
                       searchLag + 1 < static_cast<int>(yinBuffer_.size()) &&
                       yinBuffer_[searchLag + 1] < yinBuffer_[searchLag]) {
                    ++searchLag;
                }
                return searchLag;
            }
            
            if (val < minValue) {
                minValue = val;
                bestLag = lag;
            }
        }
        
        // No value below threshold, return the minimum if it's close enough
        if (minValue < threshold_ * 2.0f) {
            return bestLag;
        }
        
        return -1;
    }
    
    float parabolicInterpolation(int lag, int maxLag) {
        if (lag <= 1 || lag >= maxLag - 1 || lag >= static_cast<int>(yinBuffer_.size()) - 1) {
            return static_cast<float>(lag);
        }
        
        float y1 = yinBuffer_[lag - 1];
        float y2 = yinBuffer_[lag];
        float y3 = yinBuffer_[lag + 1];
        
        float denom = y1 - 2.0f * y2 + y3;
        if (std::abs(denom) < 1e-10f) {
            return static_cast<float>(lag);
        }
        
        // Parabolic interpolation: x_peak = lag + (y1 - y3) / (2 * denom)
        return static_cast<float>(lag) + (y1 - y3) / (2.0f * denom);
    }

    PitchResult detectPitchNSDF(const float* samples, int numSamples,
                                float threshold, float minFreq, float maxFreq) const {
        const int bufferSize = numSamples;
        const int minLag = static_cast<int>(sampleRate_ / maxFreq);
        const int maxLag = std::min(static_cast<int>(sampleRate_ / minFreq), bufferSize / 2);

        if (!samples || maxLag <= minLag || bufferSize < maxLag + 2) {
            return {};
        }

        std::vector<float> nsdf(static_cast<size_t>(maxLag), 0.0f);
        for (int lag = 0; lag < maxLag; ++lag) {
            float autocorr = 0.0f;
            float energy = 0.0f;
            for (int i = 0; i < bufferSize - lag; ++i) {
                const float a = samples[i];
                const float b = samples[i + lag];
                autocorr += a * b;
                energy += a * a + b * b;
            }
            nsdf[static_cast<size_t>(lag)] = energy > 0.0f ? (2.0f * autocorr) / energy : 0.0f;
        }

        float maxValue = 0.0f;
        int bestLag = 0;
        for (int lag = std::max(minLag, 1); lag < maxLag - 1; ++lag) {
            const float value = nsdf[static_cast<size_t>(lag)];
            if (value > threshold &&
                value > nsdf[static_cast<size_t>(lag - 1)] &&
                value > nsdf[static_cast<size_t>(lag + 1)] &&
                value > maxValue) {
                maxValue = value;
                bestLag = lag;
            }
        }

        if (bestLag <= 0 || maxValue < threshold) {
            return {};
        }

        float refinedLag = static_cast<float>(bestLag);
        if (bestLag > 0 && bestLag < maxLag - 1) {
            const float y1 = nsdf[static_cast<size_t>(bestLag - 1)];
            const float y2 = nsdf[static_cast<size_t>(bestLag)];
            const float y3 = nsdf[static_cast<size_t>(bestLag + 1)];
            const float denom = y1 - 2.0f * y2 + y3;
            if (std::abs(denom) > 1e-10f) {
                refinedLag = static_cast<float>(bestLag) + (y1 - y3) / (2.0f * denom);
            }
        }

        const float frequency = sampleRate_ / refinedLag;
        if (frequency < minFreq || frequency > maxFreq || !std::isfinite(frequency)) {
            return {};
        }

        PitchResult result;
        result.frequency = frequency;
        result.clarity = maxValue;
        result.midiNote = frequencyToMidi(frequency);
        result.centsDeviation = calculateCentsDeviation(frequency, result.midiNote);
        result.isReliable = maxValue > threshold;
        return result;
    }

    StabilityResult analyzePitchStability(const float* samples, int numSamples,
                                          int windowSize, float threshold,
                                          float minFreq, float maxFreq) {
        StabilityResult result;
        if (!samples || numSamples <= 0 || windowSize <= 0 || numSamples < windowSize) {
            return result;
        }

        const int hopSize = std::max(1, windowSize / 2);
        const int numWindows = std::max(0, (numSamples - windowSize) / hopSize);
        if (numWindows < 2) {
            return result;
        }

        const float prevMin = minFrequency_;
        const float prevMax = maxFrequency_;
        const float prevThreshold = threshold_;
        setMinFrequency(minFreq);
        setMaxFrequency(maxFreq);
        setThreshold(threshold);

        for (int i = 0; i < numWindows; ++i) {
            const int start = i * hopSize;
            PitchResult pitch = detectPitchYIN(samples + start, windowSize);
            if (pitch.frequency > 0.0f && pitch.clarity > 0.5f) {
                result.pitches.push_back(pitch.frequency);
            }
        }

        setMinFrequency(prevMin);
        setMaxFrequency(prevMax);
        setThreshold(prevThreshold);

        if (result.pitches.size() < 2) {
            return result;
        }

        float sumPitch = 0.0f;
        for (float pitch : result.pitches) {
            sumPitch += pitch;
        }
        result.averagePitch = sumPitch / static_cast<float>(result.pitches.size());

        float variance = 0.0f;
        for (float pitch : result.pitches) {
            const float cents = 1200.0f * std::log2(pitch / result.averagePitch);
            variance += cents * cents;
        }
        variance /= static_cast<float>(result.pitches.size());
        result.stability = std::max(0.0f, 1.0f - variance / 2500.0f);
        return result;
    }
    
    bool detectPercussive(const float* samples, int numSamples) const {
        // Check for rapid amplitude decay characteristic of percussive sounds
        if (numSamples < static_cast<int>(sampleRate_ * 0.05f)) {
            return true; // Very short samples are likely percussive
        }
        
        const int numSegments = 10;
        const int segmentSize = numSamples / numSegments;
        
        std::vector<float> amplitudes;
        for (int seg = 0; seg < numSegments; ++seg) {
            int start = seg * segmentSize;
            amplitudes.push_back(calculateRMS(samples + start, segmentSize));
        }
        
        // Check for rapid initial decay
        float initialAmp = amplitudes[0];
        float laterAmp = amplitudes[amplitudes.size() - 1];
        
        // If amplitude decays very quickly after attack, likely percussive
        if (initialAmp > 0.3f && laterAmp < 0.02f && amplitudes[2] < initialAmp * 0.3f) {
            return true;
        }
        
        return false;
    }
    
    int findAttackEnd(const float* samples, int numSamples) const {
        // Find where the amplitude stabilizes after the attack
        const int windowSize = std::max(1, static_cast<int>(sampleRate_ * 0.05f)); // 50ms windows
        const int numWindows = numSamples / windowSize;
        
        if (numWindows < 3) return 0;
        
        std::vector<float> rmsValues;
        for (int w = 0; w < numWindows; ++w) {
            int start = w * windowSize;
            rmsValues.push_back(calculateRMS(samples + start, windowSize));
        }
        
        // Find where amplitude changes become small
        for (size_t i = 2; i < rmsValues.size(); ++i) {
            float prevChange = std::abs(rmsValues[i - 1] - rmsValues[i - 2]);
            float currChange = std::abs(rmsValues[i] - rmsValues[i - 1]);
            
            if (prevChange < 0.02f && currChange < 0.02f && rmsValues[i] > 0.03f) {
                return static_cast<int>(i * windowSize);
            }
        }
        
        return 0;
    }

    // Configuration
    float sampleRate_ = 44100.0f;
    float minFrequency_ = 50.0f;
    float maxFrequency_ = 2000.0f;
    float threshold_ = 0.15f; // YIN threshold
    
    // Buffers
    int maxBufferSize_;
    std::vector<float> yinBuffer_;
    std::vector<float> windowBuffer_;
};

/**
 * StreamingPitchDetector - Real-time pitch detection for continuous audio streams.
 * 
 * Designed for low-latency pitch tracking in the audio callback.
 * Uses overlapping windows for smoother tracking.
 */
class StreamingPitchDetector {
public:
    explicit StreamingPitchDetector(float sampleRate = 44100.0f, int windowSize = 2048)
        : sampleRate_(sampleRate)
        , windowSize_(windowSize)
        , hopSize_(windowSize / 4) // 75% overlap
        , detector_(windowSize)
        , ringBuffer_(windowSize * 2)
    {
        detector_.setSampleRate(sampleRate);
    }
    
    void setSampleRate(float sampleRate) {
        sampleRate_ = sampleRate;
        detector_.setSampleRate(sampleRate);
    }
    
    void setWindowSize(int windowSize) {
        windowSize_ = windowSize;
        hopSize_ = windowSize / 4;
        ringBuffer_.resize(windowSize * 2);
        writePos_ = 0;
        samplesAvailable_ = 0;
        detector_ = PitchDetector(windowSize);
        detector_.setSampleRate(sampleRate_);
    }
    
    void setFrequencyRange(float minHz, float maxHz) {
        detector_.setMinFrequency(minHz);
        detector_.setMaxFrequency(maxHz);
    }
    
    void setThreshold(float threshold) {
        detector_.setThreshold(threshold);
    }
    
    /**
     * Process a block of samples and update pitch detection.
     * Call this from your audio callback.
     * 
     * @param samples Mono input samples
     * @param numSamples Number of samples
     * @return True if a new pitch result is available
     */
    bool process(const float* samples, int numSamples) {
        // Add samples to ring buffer
        for (int i = 0; i < numSamples; ++i) {
            ringBuffer_[writePos_] = samples[i];
            writePos_ = (writePos_ + 1) % static_cast<int>(ringBuffer_.size());
        }
        samplesAvailable_ += numSamples;
        
        // Check if we have enough samples for analysis
        if (samplesAvailable_ < windowSize_) {
            return false;
        }
        
        // Extract window for analysis
        std::vector<float> analysisWindow(windowSize_);
        for (int i = 0; i < windowSize_; ++i) {
            int readPos = (writePos_ - windowSize_ + i + static_cast<int>(ringBuffer_.size())) 
                          % static_cast<int>(ringBuffer_.size());
            analysisWindow[i] = ringBuffer_[readPos];
        }
        
        // Run pitch detection
        currentResult_ = detector_.detectPitchYIN(analysisWindow.data(), windowSize_);
        samplesAvailable_ -= hopSize_; // Advance by hop size
        
        return currentResult_.frequency > 0;
    }
    
    /**
     * Process interleaved stereo samples (uses first channel).
     */
    bool processStereo(const float* samples, int numFrames) {
        return process(samples, numFrames); // Will use stride if needed
    }
    
    /**
     * Get the most recent pitch result.
     */
    const PitchResult& getResult() const {
        return currentResult_;
    }
    
    /**
     * Check if the current result is considered reliable.
     */
    bool hasReliablePitch() const {
        return currentResult_.frequency > 0 && currentResult_.isReliable;
    }

private:
    float sampleRate_;
    int windowSize_;
    int hopSize_;
    
    PitchDetector detector_;
    PitchResult currentResult_;
    
    std::vector<float> ringBuffer_;
    int writePos_ = 0;
    int samplesAvailable_ = 0;
};

} // namespace dsp_primitives
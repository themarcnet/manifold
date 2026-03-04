#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <algorithm>
#include <cmath>
#include "../primitives/dsp/CaptureBuffer.h"
#include "../primitives/dsp/LoopBuffer.h"
#include "../primitives/dsp/Playhead.h"

class ManifoldLayer {
public:
    ManifoldLayer() = default;
    
    enum class State {
        Empty,
        Playing,
        Recording,
        Overdubbing,
        Muted,
        Stopped,
        Paused
    };
    
    void setLength(int samples) {
        buffer.setSize(samples, 2);
        playhead.setLength(samples);
    }
    
    void process(float* outputL, float* outputR, int numSamples) {
        if (state == State::Empty || state == State::Muted || state == State::Stopped || state == State::Paused) {
            std::fill(outputL, outputL + numSamples, 0.0f);
            std::fill(outputR, outputR + numSamples, 0.0f);
            return;
        }

        const int length = buffer.getLength();
        if (length == 0) {
            std::fill(outputL, outputL + numSamples, 0.0f);
            std::fill(outputR, outputR + numSamples, 0.0f);
            return;
        }

        // Crossfade zone: configured length, but never more than 1/4 of the loop
        const int xfade = std::min(crossfadeLength, std::max(0, length / 4));
        constexpr float halfPi = 1.5707963267948966f;

        for (int i = 0; i < numSamples; ++i) {
            const int pos = playhead.getPosition();

            float left  = buffer.getSample(pos, 0);
            float right = buffer.getSample(pos, 1);

            if (xfade > 1) {
                float t = -1.0f;   // normalised crossfade position 0..1 (-1 = not in zone)
                int wrapPos = 0;   // mirror position on the other side of the boundary

                if (!playhead.isReversed()) {
                    // Forward: crossfade zone is the last `xfade` samples [L-xfade .. L-1]
                    // As playhead approaches L, blend from current (end) into wrapped (beginning)
                    const int fadeStart = length - xfade;
                    if (pos >= fadeStart) {
                        const int k = pos - fadeStart;
                        t = static_cast<float>(k) / static_cast<float>(xfade);
                        wrapPos = k;  // corresponding sample near start of buffer
                    }
                } else {
                    // Reverse: crossfade zone is the first `xfade` samples [0 .. xfade-1]
                    // As playhead approaches 0, blend from current (start) into wrapped (end)
                    if (pos < xfade) {
                        t = 1.0f - static_cast<float>(pos) / static_cast<float>(xfade);
                        wrapPos = (length - xfade) + pos;  // corresponding sample near end of buffer
                    }
                }

                if (t >= 0.0f) {
                    // Equal-power crossfade: cos/sin maintains constant energy
                    // (linear blending causes a ~3dB dip at the midpoint)
                    const float angle = t * halfPi;
                    const float fadeOut = std::cos(angle);
                    const float fadeIn  = std::sin(angle);

                    left  = left * fadeOut + buffer.getSample(wrapPos, 0) * fadeIn;
                    right = right * fadeOut + buffer.getSample(wrapPos, 1) * fadeIn;
                }
            }

            outputL[i] = left * volume;
            outputR[i] = right * volume;
            playhead.advance(1);
        }
    }
    
    void recordInput(const float* inputL, const float* inputR, int numSamples, bool overdub = false) {
        for (int i = 0; i < numSamples; ++i) {
            int pos = playhead.getPosition();
            if (overdub) {
                buffer.addSample(pos, inputL[i], 0);
                buffer.addSample(pos, inputR[i], 1);
            } else {
                buffer.setSample(pos, inputL[i], 0);
                buffer.setSample(pos, inputR[i], 1);
            }
            playhead.advance(1);
        }
    }
    
    void copyFromCapture(const CaptureBuffer& capture, int captureStartOffset, int numSamples, bool overdub = false) {
        if (overdub) {
            overdubFromCapture(capture, captureStartOffset, numSamples);
        } else {
            buffer.setSize(numSamples, 2);
            playhead.setLength(numSamples);
            buffer.copyFrom(capture, captureStartOffset, numSamples);
            state = State::Playing;
        }
    }

    void overdubFromCapture(const CaptureBuffer& capture, int captureStartOffset, int numSamples) {
        if (buffer.getLength() <= 0) return;
        buffer.overdubFrom(capture, captureStartOffset, numSamples);
        playhead.setLength(buffer.getLength());
        state = State::Playing;
    }
    
    void play() { 
        if (state == State::Paused || (state != State::Empty && state != State::Recording))
            state = State::Playing; 
    }
    void pause() {
        if (state == State::Playing)
            state = State::Paused;
    }
    void stop() {
        if (state == State::Empty) return;
        state = State::Stopped;
        playhead.reset();
    }
    void mute() { state = State::Muted; }
    void unmute() { if (state == State::Muted) state = State::Playing; }
    void beginOverdub() { if (state != State::Empty) state = State::Overdubbing; }
    void clear() { 
        buffer.clear(); 
        state = State::Empty;
        playhead.reset();
    }
    
    void setVolume(float v) { volume = juce::jlimit(0.0f, 2.0f, v); }
    void setSpeed(float s) { playhead.setSpeed(s); }
    void setReversed(bool r) { playhead.setReversed(r); }
    void setCrossfadeLength(int samples) { crossfadeLength = std::max(0, samples); }
    int getCrossfadeLength() const { return crossfadeLength; }
    
    State getState() const { return state; }
    int getLength() const { return buffer.getLength(); }
    float getVolume() const { return volume; }
    int getPosition() const { return playhead.getPosition(); }
    bool isReversed() const { return playhead.isReversed(); }
    float getSpeed() const { return playhead.getSpeed(); }
    LoopBuffer& getBuffer() { return buffer; }
    const LoopBuffer& getBuffer() const { return buffer; }
    Playhead& getPlayhead() { return playhead; }
    
private:
    LoopBuffer buffer;
    Playhead playhead;
    State state = State::Empty;
    float volume = 1.0f;
    int crossfadeLength = 256;  // ~5.8ms at 44.1kHz, good default for click-free loops
};

#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <algorithm>
#include "../primitives/dsp/CaptureBuffer.h"
#include "../primitives/dsp/LoopBuffer.h"
#include "../primitives/dsp/Playhead.h"

class LooperLayer {
public:
    LooperLayer() = default;
    
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
        const int crossfadeSamples = std::min(128, std::max(0, length / 8));

        for (int i = 0; i < numSamples; ++i) {
            int pos = playhead.getPosition();

            float left = buffer.getSample(pos, 0);
            float right = buffer.getSample(pos, 1);

            if (crossfadeSamples > 1) {
                if (!playhead.isReversed()) {
                    const int fadeStart = length - crossfadeSamples;
                    if (pos >= fadeStart) {
                        const int k = pos - fadeStart;
                        const float blend = static_cast<float>(k) / static_cast<float>(crossfadeSamples);
                        const int wrapPos = k;

                        left = left * (1.0f - blend) + buffer.getSample(wrapPos, 0) * blend;
                        right = right * (1.0f - blend) + buffer.getSample(wrapPos, 1) * blend;
                    }
                } else {
                    if (pos < crossfadeSamples) {
                        const int k = crossfadeSamples - 1 - pos;
                        const float blend = static_cast<float>(k) / static_cast<float>(crossfadeSamples);
                        const int wrapPos = (length - crossfadeSamples) + pos;

                        left = left * (1.0f - blend) + buffer.getSample(wrapPos, 0) * blend;
                        right = right * (1.0f - blend) + buffer.getSample(wrapPos, 1) * blend;
                    }
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
};

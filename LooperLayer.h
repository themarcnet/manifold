#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include "primitives/dsp/CaptureBuffer.h"
#include "primitives/dsp/LoopBuffer.h"
#include "primitives/dsp/Playhead.h"

class LooperLayer {
public:
    LooperLayer() = default;
    
    enum class State {
        Empty,
        Playing,
        Recording,
        Overdubbing,
        Muted
    };
    
    void setLength(int samples) {
        buffer.setSize(samples, 2);
        playhead.setLength(samples);
    }
    
    void process(float* outputL, float* outputR, int numSamples) {
        if (state == State::Empty || state == State::Muted) {
            std::fill(outputL, outputL + numSamples, 0.0f);
            std::fill(outputR, outputR + numSamples, 0.0f);
            return;
        }
        
        for (int i = 0; i < numSamples; ++i) {
            int pos = playhead.getPosition();
            outputL[i] = buffer.getSample(pos, 0) * volume;
            outputR[i] = buffer.getSample(pos, 1) * volume;
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
        buffer.setSize(numSamples, 2);
        playhead.setLength(numSamples);
        
        if (overdub) {
            buffer.overdubFrom(capture, captureStartOffset, numSamples);
        } else {
            buffer.copyFrom(capture, captureStartOffset, numSamples);
        }
        
        state = State::Playing;
    }
    
    void play() { 
        if (state != State::Empty) state = State::Playing; 
    }
    void stop() { state = State::Playing; playhead.reset(); }
    void mute() { state = State::Muted; }
    void unmute() { if (state == State::Muted) state = State::Playing; }
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
    Playhead& getPlayhead() { return playhead; }
    
private:
    LoopBuffer buffer;
    Playhead playhead;
    State state = State::Empty;
    float volume = 1.0f;
};

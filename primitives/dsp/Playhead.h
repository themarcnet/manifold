#pragma once

#include <juce_audio_basics/juce_audio_basics.h>

class Playhead {
public:
    Playhead() = default;
    
    void setLength(int samples) { 
        length = samples; 
        if (position >= length) position = 0;
    }
    
    void setPosition(float pos) { 
        position = pos;
        while (position >= length) position -= length;
        while (position < 0) position += length;
    }
    
    void setSpeed(float s) { speed = s; }
    void setReversed(bool r) { reversed = r; }
    void setLooping(bool l) { looping = l; }
    
    float advance(int numSamples) {
        if (length == 0) return 0.0f;
        
        float delta = numSamples * speed * (reversed ? -1.0f : 1.0f);
        position += delta;
        
        float loopCount = 0.0f;
        if (looping) {
            while (position >= length) { position -= length; ++loopCount; }
            while (position < 0) { position += length; --loopCount; }
        }
        
        return loopCount;
    }
    
    int getPosition() const { 
        int pos = static_cast<int>(position) % length;
        while (pos < 0) pos += length;
        return pos;
    }
    
    float getPositionFloat() const { return position; }
    float getSpeed() const { return speed; }
    bool isReversed() const { return reversed; }
    bool isLooping() const { return looping; }
    int getLength() const { return length; }
    
    void reset() {
        position = 0;
    }
    
private:
    float position = 0.0f;
    int length = 0;
    float speed = 1.0f;
    bool reversed = false;
    bool looping = true;
};

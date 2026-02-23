#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include "CaptureBuffer.h"

class LoopBuffer {
public:
    LoopBuffer() = default;
    
    void setSize(int sizeSamples, int channels = 2) {
        buffer.setSize(channels, sizeSamples, true, true, true);
        length = sizeSamples;
    }
    
    void copyFrom(const CaptureBuffer& capture, int captureStartOffset, int numSamples) {
        int capSize = capture.getSize();
        auto* capBuf = capture.getRawBuffer();
        
        for (int ch = 0; ch < buffer.getNumChannels() && ch < capBuf->getNumChannels(); ++ch) {
            for (int i = 0; i < numSamples && i < length; ++i) {
                int srcIdx = (captureStartOffset + i) % capSize;
                float sample = capBuf->getSample(ch, srcIdx);
                
                int dstIdx = i % length;
                buffer.setSample(ch, dstIdx, sample);
            }
        }
    }
    
    void overdubFrom(const CaptureBuffer& capture, int captureStartOffset, 
                     int numSamples, float fadeIn = 0.005f) {
        int capSize = capture.getSize();
        auto* capBuf = capture.getRawBuffer();
        int fadeSamples = static_cast<int>(fadeIn * 44100);
        
        for (int ch = 0; ch < buffer.getNumChannels() && ch < capBuf->getNumChannels(); ++ch) {
            for (int i = 0; i < numSamples && i < length; ++i) {
                int srcIdx = (captureStartOffset + i) % capSize;
                float sample = capBuf->getSample(ch, srcIdx);
                
                int dstIdx = i % length;
                float existing = buffer.getSample(ch, dstIdx);
                
                float fade = 1.0f;
                if (i < fadeSamples) fade = static_cast<float>(i) / fadeSamples;
                else if (i > numSamples - fadeSamples) 
                    fade = static_cast<float>(numSamples - i) / fadeSamples;
                
                buffer.setSample(ch, dstIdx, existing + sample * fade);
            }
        }
    }
    
    float getSample(int position, int channel = 0) const {
        if (length == 0) return 0.0f;
        int pos = position % length;
        while (pos < 0) pos += length;
        return buffer.getSample(channel, pos);
    }
    
    void setSample(int position, float value, int channel = 0) {
        if (length == 0) return;
        int pos = position % length;
        while (pos < 0) pos += length;
        buffer.setSample(channel, pos, value);
    }
    
    void addSample(int position, float value, int channel = 0) {
        if (length == 0) return;
        int pos = position % length;
        while (pos < 0) pos += length;
        float existing = buffer.getSample(channel, pos);
        buffer.setSample(channel, pos, existing + value);
    }
    
    void clear() {
        buffer.clear();
    }
    
    int getLength() const { return length; }
    int getNumChannels() const { return buffer.getNumChannels(); }
    juce::AudioBuffer<float>* getRawBuffer() { return &buffer; }
    const juce::AudioBuffer<float>* getRawBuffer() const { return &buffer; }
    
private:
    juce::AudioBuffer<float> buffer;
    int length = 0;
};

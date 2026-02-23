#pragma once

#include <juce_audio_basics/juce_audio_basics.h>
#include <array>
#include <cmath>

class CaptureBuffer {
public:
    CaptureBuffer(int sizeSamples = 0)
        : bufferSize(sizeSamples)
    {
        if (sizeSamples > 0)
            buffer.setSize(2, sizeSamples);
    }
    
    void setSize(int sizeSamples) {
        bufferSize = sizeSamples;
        buffer.setSize(2, sizeSamples, true, true, true);
        offsetToNow.fill(0);
    }
    
    void setNumChannels(int channels) {
        buffer.setSize(channels, bufferSize, true, true, true);
    }
    
    int getNumChannels() const { return buffer.getNumChannels(); }
    int getSize() const { return bufferSize; }
    
    void write(float sample, int channel = 0) {
        if (bufferSize == 0) return;
        buffer.setSample(channel, offsetToNow[channel], sample);
        offsetToNow[channel] = (offsetToNow[channel] + 1) % bufferSize;
    }
    
    void writeBlock(const float* samples, int numSamples, int channel = 0) {
        if (bufferSize == 0) return;
        for (int i = 0; i < numSamples; ++i) {
            buffer.setSample(channel, offsetToNow[channel], samples[i]);
            offsetToNow[channel] = (offsetToNow[channel] + 1) % bufferSize;
        }
    }
    
    float getSample(int samplesAgo, int channel = 0) const {
        if (bufferSize == 0) return 0.0f;
        int idx = offsetToNow[channel] - 1 - samplesAgo;
        while (idx < 0) idx += bufferSize;
        return buffer.getSample(channel, idx);
    }
    
    void readBlock(float* dest, int numSamples, int samplesAgo, int channel = 0) const {
        if (bufferSize == 0) {
            std::fill(dest, dest + numSamples, 0.0f);
            return;
        }
        for (int i = 0; i < numSamples; ++i) {
            dest[i] = getSample(samplesAgo + i, channel);
        }
    }
    
    int getOffsetToNow(int channel = 0) const { return offsetToNow[channel]; }
    
    void clear() {
        buffer.clear();
        offsetToNow.fill(0);
    }
    
    juce::AudioBuffer<float>* getRawBuffer() { return &buffer; }
    const juce::AudioBuffer<float>* getRawBuffer() const { return &buffer; }
    
private:
    juce::AudioBuffer<float> buffer;
    int bufferSize = 0;
    std::array<int, 2> offsetToNow{0, 0};
};

#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>
#include <array>

namespace GrainConsts
{
    constexpr int maxVoices = 16;
    constexpr int maxGrainsPerVoice = 8;
    constexpr float minGrainSize = 0.01f;
    constexpr float maxGrainSize = 2.0f;
    constexpr float bufferLengthSec = 8.0f;
}

class CircularBuffer
{
public:
    CircularBuffer() = default;
    
    void prepare(double sampleRate, int maxChannels)
    {
        sr = sampleRate;
        bufferSize = static_cast<int>(GrainConsts::bufferLengthSec * sampleRate);
        buffer.setSize(maxChannels, bufferSize);
        buffer.clear();
        writePos = 0;
        numChannels = maxChannels;
    }
    
    void write(const juce::AudioBuffer<float>& input)
    {
        if (bufferSize == 0) return;
        
        auto numSamples = input.getNumSamples();
        auto channels = juce::jmin(input.getNumChannels(), numChannels);
        
        for (int ch = 0; ch < channels; ++ch)
        {
            const float* src = input.getReadPointer(ch);
            float* dst = buffer.getWritePointer(ch);
            
            for (int i = 0; i < numSamples; ++i)
            {
                int pos = (writePos + i) % bufferSize;
                dst[pos] = src[i];
            }
        }
        
        writePos = (writePos + numSamples) % bufferSize;
    }
    
    float read(int channel, float position, float sampleRate) const
    {
        if (bufferSize == 0) return 0.0f;
        
        int channels = juce::jmin(channel + 1, numChannels);
        if (channels <= channel) return 0.0f;
        
        int posInt = static_cast<int>(position);
        float frac = position - posInt;
        
        posInt = posInt % bufferSize;
        if (posInt < 0) posInt += bufferSize;
        
        int posNext = (posInt + 1) % bufferSize;
        
        const float* data = buffer.getReadPointer(channel);
        return data[posInt] * (1.0f - frac) + data[posNext] * frac;
    }
    
    int getWritePosition() const { return writePos; }
    int getSize() const { return bufferSize; }
    int getNumChannels() const { return numChannels; }
    double getSampleRate() const { return sr; }
    
    float getSampleRange(int channel, int startSample, int numSamples) const
    {
        float maxVal = 0.0f;
        for (int i = 0; i < numSamples; ++i)
        {
            int pos = (startSample + i) % bufferSize;
            float val = std::abs(buffer.getSample(channel, pos));
            if (val > maxVal) maxVal = val;
        }
        return maxVal;
    }
    
private:
    juce::AudioBuffer<float> buffer;
    int bufferSize = 0;
    int writePos = 0;
    int numChannels = 2;
    double sr = 44100.0;
};

struct Grain
{
    bool active = false;
    float startPosition = 0.0f;
    float position = 0.0f;
    float speed = 1.0f;
    float size = 0.1f;
    float envelopePos = 0.0f;
    float pan = 0.5f;
    float amplitude = 1.0f;
    
    void reset()
    {
        active = false;
        position = 0.0f;
        envelopePos = 0.0f;
    }
    
    float getEnvelope() const
    {
        float x = envelopePos * 2.0f - 1.0f;
        return std::exp(-2.0f * x * x);
    }
};

struct GrainInfo
{
    bool active = false;
    float normalizedPosition = 0.0f;
    float envelope = 0.0f;
};

class GrainVoice
{
public:
    GrainVoice() = default;
    
    void prepare(double sampleRate)
    {
        sr = sampleRate;
        grains.resize(GrainConsts::maxGrainsPerVoice);
        activeGrains = 0;
    }
    
    void noteOn(int note, float velocity, const CircularBuffer& buffer,
                float grainSize, float density, float randomize, float spread,
                float scrubPos, bool reverse)
    {
        currentNote = note;
        this->velocity = velocity;
        active = true;
        envelope = 0.0f;
        envelopeTarget = velocity;
        released = false;
        
        baseSpeed = std::pow(2.0f, (note - 60) / 12.0f);
        if (reverse) baseSpeed = -baseSpeed;
        
        float bufferPos = buffer.getWritePosition() - buffer.getSize() * scrubPos;
        if (bufferPos < 0) bufferPos += buffer.getSize();
        bufferPos = fmod(bufferPos, buffer.getSize());
        
        basePosition = bufferPos;
        this->spread = spread;
        this->randomize = randomize;
        this->grainSize = grainSize;
        this->reverse = reverse;
        grainCounter = 0;
        samplesPerGrain = static_cast<int>(sr / juce::jmax(density, 1.0f));
    }
    
    void noteOff()
    {
        released = true;
    }
    
    bool isActive() const { return active; }
    int getCurrentNote() const { return currentNote; }
    const std::vector<Grain>& getGrains() const { return grains; }
    
    void process(float* leftOut, float* rightOut, int numSamples,
                 const CircularBuffer& buffer, float grainSize, float density,
                 float randomize, float spread, float scrubPos = 0.1f, bool reverseMode = false)
    {
        if (!active) return;
        
        if (reverse != reverseMode)
        {
            reverse = reverseMode;
            baseSpeed = std::abs(baseSpeed) * (reverse ? -1.0f : 1.0f);
        }
        
        int bufSize = buffer.getSize();
        float targetPos = buffer.getWritePosition() - bufSize * scrubPos;
        if (targetPos < 0) targetPos += bufSize;
        targetPos = fmod(targetPos, bufSize);
        
        float posDiff = targetPos - basePosition;
        while (posDiff > bufSize / 2) posDiff -= bufSize;
        while (posDiff < -bufSize / 2) posDiff += bufSize;
        basePosition += posDiff * 0.01f;
        
        samplesPerGrain = static_cast<int>(sr / juce::jmax(density, 1.0f));
        
        for (int i = 0; i < numSamples; ++i)
        {
            if (released)
            {
                envelope -= 0.001f;
                if (envelope <= 0.0f)
                {
                    active = false;
                    for (auto& g : grains) g.reset();
                    return;
                }
            }
            else
            {
                envelope += (envelopeTarget - envelope) * 0.01f;
            }
            
            grainCounter++;
            if (grainCounter >= samplesPerGrain && activeGrains < GrainConsts::maxGrainsPerVoice)
            {
                grainCounter = 0;
                startNewGrain(buffer, grainSize, randomize, spread);
            }
            
            float left = 0.0f, right = 0.0f;
            activeGrains = 0;
            
            for (auto& grain : grains)
            {
                if (!grain.active) continue;
                
                activeGrains++;
                float env = grain.getEnvelope();
                float samplePos = grain.position;
                
                float sampleL = buffer.read(0, samplePos, sr);
                float sampleR = buffer.read(juce::jmin(1, buffer.getNumChannels() - 1), samplePos, sr);
                
                float gain = env * grain.amplitude * envelope * velocity;
                float panLeft = std::cos(grain.pan * juce::MathConstants<float>::halfPi);
                float panRight = std::sin(grain.pan * juce::MathConstants<float>::halfPi);
                
                left += sampleL * gain * panLeft;
                right += sampleR * gain * panRight;
                
                float speed = grain.speed * baseSpeed;
                grain.position += speed;
                grain.envelopePos += 1.0f / (grain.size * sr);
                
                if (grain.envelopePos >= 1.0f)
                {
                    grain.active = false;
                }
            }
            
            leftOut[i] += left;
            rightOut[i] += right;
        }
    }
    
private:
    void startNewGrain(const CircularBuffer& circBuffer, float grainSize, float randomize, float spread)
    {
        for (auto& grain : grains)
        {
            if (!grain.active)
            {
                grain.active = true;
                
                float r1 = rng.nextFloat();
                float r2 = rng.nextFloat();
                float r3 = rng.nextFloat();
                float r4 = rng.nextFloat();
                float r5 = rng.nextFloat();
                
                float randOffset = (r1 - 0.5f) * spread * circBuffer.getSize();
                grain.startPosition = basePosition + randOffset;
                if (grain.startPosition < 0) grain.startPosition += circBuffer.getSize();
                grain.startPosition = fmod(grain.startPosition, circBuffer.getSize());
                
                grain.position = grain.startPosition;
                grain.envelopePos = 0.0f;
                
                float sizeRand = 1.0f + (r2 - 0.5f) * randomize;
                grain.size = grainSize * sizeRand;
                grain.size = juce::jlimit(GrainConsts::minGrainSize, GrainConsts::maxGrainSize, grain.size);
                
                float speedRand = 1.0f + (r3 - 0.5f) * randomize * 0.5f;
                grain.speed = speedRand;
                
                grain.pan = 0.5f + (r4 - 0.5f) * randomize;
                grain.pan = juce::jlimit(0.0f, 1.0f, grain.pan);
                
                grain.amplitude = 0.5f + r5 * 0.5f;
                
                break;
            }
        }
    }
    
    std::vector<Grain> grains;
    int activeGrains = 0;
    int currentNote = -1;
    float velocity = 0.0f;
    float envelope = 0.0f;
    float envelopeTarget = 0.0f;
    bool active = false;
    bool released = false;
    
    double sr = 44100.0;
    float baseSpeed = 1.0f;
    float basePosition = 0.0f;
    float grainSize = 0.1f;
    float randomize = 0.5f;
    float spread = 0.1f;
    bool reverse = false;
    
    int grainCounter = 0;
    int samplesPerGrain = 1000;
    juce::Random rng;
};

class GranularEngine
{
public:
    GranularEngine()
    {
        voices.resize(GrainConsts::maxVoices);
    }
    
    void prepare(double sampleRate, int maxChannels)
    {
        sr = sampleRate;
        circularBuffer.prepare(sampleRate, maxChannels);
        for (auto& voice : voices)
        {
            voice.prepare(sampleRate);
        }
        prepared = true;
    }
    
    void process(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages,
                 float grainSize, float density, float randomize, float spread,
                 float scrubPos, bool reverse, float dryWet)
    {
        if (!prepared) return;
        
        int numSamples = buffer.getNumSamples();
        
        juce::AudioBuffer<float> dryBuffer;
        dryBuffer.makeCopyOf(buffer);
        
        if (!frozen)
        {
            circularBuffer.write(buffer);
        }
        
        bool hasMidi = midiMessages.getNumEvents() > 0;
        
        for (const auto metadata : midiMessages)
        {
            auto msg = metadata.getMessage();
            if (msg.isNoteOn())
            {
                int note = msg.getNoteNumber();
                float vel = msg.getVelocity() / 127.0f;
                
                GrainVoice* freeVoice = nullptr;
                for (auto& voice : voices)
                {
                    if (!voice.isActive())
                    {
                        freeVoice = &voice;
                        break;
                    }
                }
                
                if (freeVoice)
                {
                    freeVoice->noteOn(note, vel, circularBuffer, grainSize, density, randomize, spread, scrubPos, reverse);
                }
                else
                {
                    voices[0].noteOn(note, vel, circularBuffer, grainSize, density, randomize, spread, scrubPos, reverse);
                }
            }
            else if (msg.isNoteOff())
            {
                int note = msg.getNoteNumber();
                for (auto& voice : voices)
                {
                    if (voice.isActive() && voice.getCurrentNote() == note)
                    {
                        voice.noteOff();
                    }
                }
            }
        }
        
        if (frozen && !hasMidi)
        {
            if (!voices[0].isActive())
            {
                voices[0].noteOn(60, 0.7f, circularBuffer, grainSize, density, randomize, spread, scrubPos, reverse);
            }
        }
        
        float* leftOut = buffer.getWritePointer(0);
        float* rightOut = buffer.getWritePointer(juce::jmin(1, buffer.getNumChannels() - 1));
        
        for (auto& voice : voices)
        {
            voice.process(leftOut, rightOut, numSamples, circularBuffer, grainSize, density, randomize, spread, scrubPos, reverse);
        }
        
        for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
        {
            const float* dry = dryBuffer.getReadPointer(juce::jmin(ch, dryBuffer.getNumChannels() - 1));
            float* wet = buffer.getWritePointer(ch);
            for (int i = 0; i < numSamples; ++i)
            {
                wet[i] = dry[i] * (1.0f - dryWet) + wet[i] * dryWet;
            }
        }
    }
    
    void setFrozen(bool shouldFreeze) { frozen = shouldFreeze; }
    bool isFrozen() const { return frozen; }
    
    const CircularBuffer& getCircularBuffer() const { return circularBuffer; }
    
    float getWaveformSample(int channel, int sampleIndex) const
    {
        if (!prepared) return 0.0f;
        return circularBuffer.read(channel, sampleIndex, sr);
    }
    
    int getBufferWritePos() const { return circularBuffer.getWritePosition(); }
    int getBufferSize() const { return circularBuffer.getSize(); }
    
    std::vector<GrainInfo> getActiveGrains() const
    {
        std::vector<GrainInfo> grains;
        int bufSize = circularBuffer.getSize();
        if (bufSize == 0) return grains;
        
        for (const auto& voice : voices)
        {
            if (!voice.isActive()) continue;
            for (const auto& grain : voice.getGrains())
            {
                if (grain.active)
                {
                    GrainInfo info;
                    info.active = true;
                    info.normalizedPosition = grain.position / bufSize;
                    info.envelope = grain.getEnvelope();
                    grains.push_back(info);
                }
            }
        }
        return grains;
    }
    
private:
    CircularBuffer circularBuffer;
    std::vector<GrainVoice> voices;
    double sr = 44100.0;
    bool frozen = false;
    bool prepared = false;
};

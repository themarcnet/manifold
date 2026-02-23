#pragma once

#include <juce_dsp/juce_dsp.h>
#include <array>

class ShimmerEffect
{
public:
    ShimmerEffect() = default;
    
    void prepare(double sampleRate, int maxBlockSize)
    {
        sr = sampleRate;
        
        for (int i = 0; i < numShifters; ++i)
        {
            pitchShifters[i].setSampleRate(sampleRate);
            pitchShifters[i].setSemitonesUp(shiftSemitones[i]);
        }
        
        delayBuffer.setSize(2, static_cast<int>(sampleRate * 2.0));
        delayBuffer.clear();
        
        delayLines[0].prepare({ sampleRate, static_cast<juce::uint32>(maxBlockSize), 2 });
        delayLines[1].prepare({ sampleRate, static_cast<juce::uint32>(maxBlockSize), 2 });
    }
    
    void reset()
    {
        for (auto& shifter : pitchShifters)
            shifter.reset();
        
        delayBuffer.clear();
        delayWritePos = 0;
        delayLines[0].reset();
        delayLines[1].reset();
    }
    
    void process(float* left, float* right, int numSamples, float amount, float feedback, float size)
    {
        if (amount < 0.001f) return;
        
        for (int i = 0; i < numSamples; ++i)
        {
            float inL = left[i];
            float inR = right[i];
            
            float delayTime = size * 0.5f;
            int delaySamples = static_cast<int>(delayTime * sr);
            delaySamples = juce::jlimit(1, static_cast<int>(sr), delaySamples);
            
            float feedbackL = 0.0f, feedbackR = 0.0f;
            
            int readPos = delayWritePos - delaySamples;
            if (readPos < 0) readPos += delayBuffer.getNumSamples();
            
            feedbackL = delayBuffer.getSample(0, readPos);
            feedbackR = delayBuffer.getSample(1, readPos);
            
            float shiftedL = 0.0f, shiftedR = 0.0f;
            float tempL[1] = { feedbackL };
            float tempR[1] = { feedbackR };
            
            for (int s = 0; s < numShifters; ++s)
            {
                float shiftL = pitchShifters[s].processSample(0, feedbackL);
                float shiftR = pitchShifters[s].processSample(1, feedbackR);
                shiftedL += shiftL * 0.5f;
                shiftedR += shiftR * 0.5f;
            }
            
            float wetL = shiftedL * amount;
            float wetR = shiftedR * amount;
            
            delayBuffer.setSample(0, delayWritePos, inL + wetL * feedback);
            delayBuffer.setSample(1, delayWritePos, inR + wetR * feedback);
            
            delayWritePos = (delayWritePos + 1) % delayBuffer.getNumSamples();
            
            left[i] = inL + wetL * amount;
            right[i] = inR + wetR * amount;
        }
    }
    
private:
    class PitchShifter
    {
    public:
        void setSampleRate(double rate)
        {
            sampleRate = rate;
            grainSize = static_cast<int>(0.03f * rate);
            grainBuffer.resize(grainSize * 2);
            std::fill(grainBuffer.begin(), grainBuffer.end(), 0.0f);
        }
        
        void setSemitonesUp(int semitones)
        {
            shiftRatio = std::pow(2.0f, semitones / 12.0f);
        }
        
        void reset()
        {
            writePos = 0;
            readPos1 = 0;
            readPos2 = grainSize / 2;
            grainCounter = 0;
            std::fill(grainBuffer.begin(), grainBuffer.end(), 0.0f);
        }
        
        float processSample(int channel, float input)
        {
            grainBuffer[writePos] = input;
            
            float readPos1Float = writePos - grainSize;
            while (readPos1Float < 0) readPos1Float += grainSize;
            
            float readPos2Float = readPos1Float + grainSize * 0.5f;
            while (readPos2Float >= grainSize) readPos2Float -= grainSize;
            
            int idx1a = static_cast<int>(readPos1Float);
            int idx1b = (idx1a + 1) % grainSize;
            float frac1 = readPos1Float - idx1a;
            float grain1 = grainBuffer[idx1a] * (1.0f - frac1) + grainBuffer[idx1b] * frac1;
            
            int idx2a = static_cast<int>(readPos2Float);
            int idx2b = (idx2a + 1) % grainSize;
            float frac2 = readPos2Float - idx2a;
            float grain2 = grainBuffer[idx2a] * (1.0f - frac2) + grainBuffer[idx2b] * frac2;
            
            float envPos = (writePos % grainSize) / static_cast<float>(grainSize);
            float env1 = 0.5f * (1.0f - std::cos(2.0f * juce::MathConstants<float>::pi * envPos));
            float env2 = 0.5f * (1.0f - std::cos(2.0f * juce::MathConstants<float>::pi * fmod(envPos + 0.5f, 1.0f)));
            
            writePos = (writePos + 1) % (grainSize * 2);
            
            return grain1 * env1 + grain2 * env2;
        }
        
    private:
        std::vector<float> grainBuffer;
        int grainSize = 1024;
        int writePos = 0;
        int readPos1 = 0;
        int readPos2 = 512;
        int grainCounter = 0;
        float shiftRatio = 2.0f;
        double sampleRate = 44100.0;
    };
    
    static constexpr int numShifters = 2;
    PitchShifter pitchShifters[numShifters];
    int shiftSemitones[2] = { 12, 19 };
    
    juce::AudioBuffer<float> delayBuffer;
    int delayWritePos = 0;
    
    std::array<juce::dsp::DelayLine<float>, 2> delayLines;
    double sr = 44100.0;
};

class ReverbEffect
{
public:
    ReverbEffect() = default;
    
    void prepare(double sampleRate, int maxBlockSize)
    {
        reverb.prepare({ sampleRate, static_cast<juce::uint32>(maxBlockSize), 2 });
        reset();
    }
    
    void reset()
    {
        reverb.reset();
    }
    
    void process(float* left, float* right, int numSamples, float mix, float size, float damping)
    {
        if (mix < 0.001f) return;
        
        params.roomSize = size;
        params.damping = damping;
        params.wetLevel = mix;
        params.dryLevel = 1.0f - mix * 0.5f;
        params.width = 1.0f;
        params.freezeMode = 0.0f;
        
        reverb.setParameters(params);
        
        juce::dsp::AudioBlock<float> block(&left, 1, numSamples);
        juce::dsp::AudioBlock<float> blockR(&right, 1, numSamples);
        
        float* channels[2] = { left, right };
        juce::dsp::AudioBlock<float> stereoBlock(channels, 2, numSamples);
        juce::dsp::ProcessContextReplacing<float> context(stereoBlock);
        
        reverb.process(context);
    }
    
private:
    juce::dsp::Reverb reverb;
    juce::Reverb::Parameters params;
};

class EffectsProcessor
{
public:
    EffectsProcessor() = default;
    
    void prepare(double sampleRate, int maxBlockSize, int numChannels)
    {
        reverb.prepare(sampleRate, maxBlockSize);
        shimmer.prepare(sampleRate, maxBlockSize);
        
        tempBuffer.setSize(numChannels, maxBlockSize);
    }
    
    void reset()
    {
        reverb.reset();
        shimmer.reset();
    }
    
    void process(juce::AudioBuffer<float>& buffer,
                 float reverbMix, float reverbSize, float reverbDamping,
                 float shimmerAmount, float shimmerFeedback, float shimmerSize)
    {
        int numSamples = buffer.getNumSamples();
        
        tempBuffer.makeCopyOf(buffer);
        
        float* left = buffer.getWritePointer(0);
        float* right = buffer.getWritePointer(juce::jmin(1, buffer.getNumChannels() - 1));
        
        shimmer.process(left, right, numSamples, shimmerAmount, shimmerFeedback, shimmerSize);
        reverb.process(left, right, numSamples, reverbMix, reverbSize, reverbDamping);
    }
    
private:
    ReverbEffect reverb;
    ShimmerEffect shimmer;
    juce::AudioBuffer<float> tempBuffer;
};

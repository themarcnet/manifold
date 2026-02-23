#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_extra/juce_gui_extra.h>
#include "GranularEngine.h"
#include "EffectsProcessor.h"

enum ParameterID
{
    Freeze = 0,
    GrainSize,
    Density,
    Randomize,
    Spread,
    ReverbMix,
    ReverbSize,
    ReverbDamping,
    ShimmerAmount,
    ShimmerFeedback,
    ShimmerSize,
    MasterVolume,
    NumParameters
};

class AudioPluginAudioProcessor final : public juce::AudioProcessor
{
public:
    AudioPluginAudioProcessor();
    ~AudioPluginAudioProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;

    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;

    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    using AudioProcessor::processBlock;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override;

    const juce::String getName() const override;

    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    double getTailLengthSeconds() const override;

    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram(int index) override;
    const juce::String getProgramName(int index) override;
    void changeProgramName(int index, const juce::String& newName) override;

    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    juce::AudioProcessorValueTreeState apvts;
    GranularEngine granularEngine;
    EffectsProcessor effectsProcessor;
    
    float getWaveformData(int channel, int sampleIndex) const;
    int getBufferSize() const;
    int getBufferWritePos() const;
    bool isFrozen() const;
    std::vector<GrainInfo> getActiveGrains() const;
    void processBlockMidi(const juce::MidiMessage& msg);

private:
    juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();
    juce::MidiBuffer pendingMidiBuffer;
    
    std::atomic<float>* freezeParam = nullptr;
    std::atomic<float>* grainSizeParam = nullptr;
    std::atomic<float>* densityParam = nullptr;
    std::atomic<float>* randomizeParam = nullptr;
    std::atomic<float>* spreadParam = nullptr;
    std::atomic<float>* reverbMixParam = nullptr;
    std::atomic<float>* reverbSizeParam = nullptr;
    std::atomic<float>* reverbDampingParam = nullptr;
    std::atomic<float>* shimmerAmountParam = nullptr;
    std::atomic<float>* shimmerFeedbackParam = nullptr;
    std::atomic<float>* shimmerSizeParam = nullptr;
    std::atomic<float>* masterVolumeParam = nullptr;
    std::atomic<float>* dryWetParam = nullptr;
    std::atomic<float>* scrubParam = nullptr;
    std::atomic<float>* reverseParam = nullptr;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AudioPluginAudioProcessor)
};

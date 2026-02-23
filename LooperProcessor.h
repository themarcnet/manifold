#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include "primitives/dsp/CaptureBuffer.h"
#include "primitives/dsp/TempoInference.h"
#include "primitives/dsp/Quantizer.h"
#include "LooperLayer.h"

enum class RecordMode {
    FirstLoop,
    FreeMode,
    Traditional,
    Retrospective
};

class LooperProcessor : public juce::AudioProcessor {
public:
    static const int MAX_LAYERS = 4;
    static const int CAPTURE_SECONDS = 32;
    
    LooperProcessor();
    ~LooperProcessor() override;
    
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages) override;
    
    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }
    
    const juce::String getName() const override { return "Looper"; }
    bool acceptsMidi() const override { return true; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}
    
    void getStateInformation(juce::MemoryBlock&) override {}
    void setStateInformation(const void*, int) override {}
    
    CaptureBuffer& getCaptureBuffer() { return captureBuffer; }
    LooperLayer& getLayer(int index) { return layers[index]; }
    int getActiveLayerIndex() const { return activeLayerIndex; }
    void setActiveLayer(int index);
    
    void startRecording();
    void stopRecording();
    void commitRetrospective(float numBars);
    
    RecordMode getRecordMode() const { return recordMode; }
    void setRecordMode(RecordMode mode) { recordMode = mode; }
    
    bool isRecording() const { return isCurrentlyRecording; }
    bool isPlaying() const;
    
    float getTempo() const { return tempo; }
    void setTempo(float bpm);
    
    float getTargetBPM() const { return targetBPM; }
    void setTargetBPM(float bpm) { targetBPM = bpm; }
    
    bool getInferTempo() const { return inferTempo; }
    void setInferTempo(bool infer) { inferTempo = infer; }
    
    float getMasterVolume() const { return masterVolume; }
    void setMasterVolume(float vol) { masterVolume = vol; }
    
    float getSamplesPerBar() const;
    double getSampleRate() const { return currentSampleRate; }
    
private:
    CaptureBuffer captureBuffer;
    LooperLayer layers[MAX_LAYERS];
    int activeLayerIndex = 0;
    
    TempoInference tempoInference;
    Quantizer quantizer;
    
    RecordMode recordMode = RecordMode::FirstLoop;
    bool isCurrentlyRecording = false;
    double recordStartTime = 0.0;
    double playTime = 0.0;
    
    float tempo = 120.0f;
    float targetBPM = 120.0f;
    bool inferTempo = true;
    float masterVolume = 1.0f;
    double currentSampleRate = 44100.0;
    
    void processFirstLoopStop();
    void processFreeModeStop();
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LooperProcessor)
};

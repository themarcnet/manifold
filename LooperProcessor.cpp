#include "LooperProcessor.h"
#include "LooperEditor.h"

LooperProcessor::LooperProcessor()
    : juce::AudioProcessor(juce::AudioProcessor::BusesProperties()
        .withInput("Input", juce::AudioChannelSet::stereo(), true)
        .withOutput("Output", juce::AudioChannelSet::stereo(), true))
{
}

LooperProcessor::~LooperProcessor() {}

void LooperProcessor::prepareToPlay(double sampleRate, int) {
    currentSampleRate = sampleRate;
    int captureSamples = static_cast<int>(CAPTURE_SECONDS * sampleRate);
    captureBuffer.setSize(captureSamples);
    captureBuffer.setNumChannels(2);
    quantizer.setSampleRate(sampleRate);
    quantizer.setTempo(tempo);
    playTime = 0.0;
}

void LooperProcessor::releaseResources() {}

void LooperProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) {
    auto* inputL = buffer.getWritePointer(0);
    auto* inputR = buffer.getNumChannels() > 1 ? buffer.getWritePointer(1) : inputL;
    int numSamples = buffer.getNumSamples();
    
    // Always write to capture buffer
    for (int i = 0; i < numSamples; ++i) {
        captureBuffer.write(inputL[i], 0);
        captureBuffer.write(inputR[i], 1);
    }
    
    // Mix all layers together
    float layerMixL[4096];
    float layerMixR[4096];
    
    for (int i = 0; i < numSamples; ++i) {
        layerMixL[i] = 0.0f;
        layerMixR[i] = 0.0f;
    }
    
    for (auto& layer : layers) {
        float layerL[4096];
        float layerR[4096];
        layer.process(layerL, layerR, numSamples);
        
        for (int i = 0; i < numSamples; ++i) {
            layerMixL[i] += layerL[i];
            layerMixR[i] += layerR[i];
        }
    }
    
    // Output: dry input + wet layers
    for (int i = 0; i < numSamples; ++i) {
        inputL[i] = inputL[i] * 0.7f + layerMixL[i] * masterVolume;
        inputR[i] = inputR[i] * 0.7f + layerMixR[i] * masterVolume;
    }
    
    playTime += numSamples;
}

juce::AudioProcessorEditor* LooperProcessor::createEditor() { 
    return new LooperEditor(*this); 
}

void LooperProcessor::setActiveLayer(int index) {
    if (index >= 0 && index < MAX_LAYERS) activeLayerIndex = index;
}

void LooperProcessor::startRecording() {
    if (isCurrentlyRecording) return;
    isCurrentlyRecording = true;
    recordStartTime = playTime;
}

void LooperProcessor::stopRecording() {
    if (!isCurrentlyRecording) return;
    isCurrentlyRecording = false;
    
    switch (recordMode) {
        case RecordMode::FirstLoop: processFirstLoopStop(); break;
        case RecordMode::FreeMode: processFreeModeStop(); break;
        default: break;
    }
}

void LooperProcessor::commitRetrospective(float numBars) {
    int samplesBack = static_cast<int>(numBars * getSamplesPerBar());
    int startOffset = captureBuffer.getOffsetToNow() - samplesBack;
    while (startOffset < 0) startOffset += captureBuffer.getSize();
    
    layers[activeLayerIndex].copyFromCapture(captureBuffer, startOffset, samplesBack);
}

void LooperProcessor::processFirstLoopStop() {
    double duration = playTime - recordStartTime;
    double durationSeconds = duration / currentSampleRate;
    
    auto result = tempoInference.findBestMatch(durationSeconds, targetBPM, 4);
    
    if (result.valid) {
        tempo = result.tempo;
        quantizer.setTempo(tempo);
        
        int samples = static_cast<int>(result.numBars * getSamplesPerBar());
        int startOffset = captureBuffer.getOffsetToNow() - static_cast<int>(duration);
        while (startOffset < 0) startOffset += captureBuffer.getSize();
        
        layers[activeLayerIndex].copyFromCapture(captureBuffer, startOffset, samples);
    }
}

void LooperProcessor::processFreeModeStop() {
    double duration = playTime - recordStartTime;
    int quantizedLength = quantizer.quantizeToNearestLegal(duration);
    
    int startOffset = captureBuffer.getOffsetToNow() - static_cast<int>(duration);
    while (startOffset < 0) startOffset += captureBuffer.getSize();
    
    layers[activeLayerIndex].copyFromCapture(captureBuffer, startOffset, quantizedLength);
}

void LooperProcessor::setTempo(float bpm) {
    tempo = bpm;
    quantizer.setTempo(bpm);
}

bool LooperProcessor::isPlaying() const {
    for (const auto& layer : layers) {
        if (layer.getState() == LooperLayer::State::Playing) return true;
    }
    return false;
}

float LooperProcessor::getSamplesPerBar() const {
    float beatsPerSecond = tempo / 60.0f;
    float samplesPerBeat = static_cast<float>(currentSampleRate / beatsPerSecond);
    return samplesPerBeat * 4.0f;
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new LooperProcessor();
}

#include "LooperEditor.h"

LooperEditor::LooperEditor(LooperProcessor& p)
    : juce::AudioProcessorEditor(p), processor(p)
{
    setSize(600, 450);
    startTimerHz(30);
}

void LooperEditor::timerCallback() {
    repaint();
}

void LooperEditor::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff1a1a2e));
    
    auto bounds = getLocalBounds().reduced(10);
    
    // Title
    g.setColour(juce::Colours::cyan);
    g.setFont(24.0f);
    g.drawText("LOOPER", bounds.removeFromTop(35), juce::Justification::centred);
    
    bounds.removeFromTop(10);
    
    // Button row
    auto btnRow = bounds.removeFromTop(40);
    
    // REC button
    auto recBounds = btnRow.removeFromLeft(80);
    g.setColour(processor.isRecording() ? juce::Colours::red : juce::Colour(0xff663333));
    g.fillRoundedRectangle(recBounds.toFloat(), 6);
    g.setColour(juce::Colours::white);
    g.setFont(16.0f);
    g.drawText("REC", recBounds, juce::Justification::centred);
    
    btnRow.removeFromLeft(10);
    
    // STOP button
    auto stopBounds = btnRow.removeFromLeft(80);
    g.setColour(juce::Colour(0xff555555));
    g.fillRoundedRectangle(stopBounds.toFloat(), 6);
    g.setColour(juce::Colours::white);
    g.drawText("STOP", stopBounds, juce::Justification::centred);
    
    btnRow.removeFromLeft(10);
    
    // Mode button
    auto modeBounds = btnRow.removeFromLeft(120);
    juce::String modeText;
    switch (processor.getRecordMode()) {
        case RecordMode::FirstLoop: modeText = "First Loop"; break;
        case RecordMode::FreeMode: modeText = "Free Mode"; break;
        case RecordMode::Traditional: modeText = "Traditional"; break;
        case RecordMode::Retrospective: modeText = "Retrospective"; break;
    }
    g.setColour(juce::Colour(0xff335566));
    g.fillRoundedRectangle(modeBounds.toFloat(), 6);
    g.setColour(juce::Colours::white);
    g.drawText(modeText, modeBounds, juce::Justification::centred);
    
    btnRow.removeFromLeft(10);
    
    // Target BPM
    g.setColour(juce::Colours::grey);
    g.setFont(14.0f);
    g.drawText("Target: " + juce::String(processor.getTargetBPM(), 0) + " BPM", btnRow, juce::Justification::centredLeft);
    
    bounds.removeFromTop(10);
    
    // Waveform display
    auto waveBounds = bounds.removeFromTop(80);
    g.setColour(juce::Colour(0xff16213e));
    g.fillRect(waveBounds);
    g.setColour(juce::Colour(0xff0f3460));
    g.drawRect(waveBounds, 2);
    
    // Draw capture buffer waveform
    auto& capture = processor.getCaptureBuffer();
    int numSamples = capture.getSize();
    float maxLevel = 0.0f;
    
    if (numSamples > 0) {
        g.setColour(juce::Colour(0xff00ff88));
        float width = waveBounds.getWidth();
        int samplesPerPixel = juce::jmax(1, numSamples / static_cast<int>(width));
        float centerY = waveBounds.getCentreY();
        
        for (int x = 0; x < static_cast<int>(width); ++x) {
            int sampleIdx = numSamples - (x * samplesPerPixel);
            float maxSample = 0.0f;
            for (int i = 0; i < samplesPerPixel && sampleIdx - i >= 0; ++i) {
                float s = std::abs(capture.getSample(sampleIdx - i, 0));
                if (s > maxSample) maxSample = s;
            }
            if (maxSample > maxLevel) maxLevel = maxSample;
            float height = maxSample * waveBounds.getHeight() * 0.8f;
            g.drawVerticalLine(waveBounds.getX() + x, centerY - height, centerY + height);
        }
    }
    
    // Input level indicator
    g.setColour(maxLevel > 0.001f ? juce::Colours::green : juce::Colours::red);
    g.setFont(10.0f);
    g.drawText(maxLevel > 0.001f ? "INPUT OK" : "NO INPUT", 
               waveBounds.withSize(80, 15), juce::Justification::centredLeft);
    
    bounds.removeFromTop(10);
    
    // Segment buttons (retrospective commit)
    g.setColour(juce::Colours::white);
    g.setFont(12.0f);
    g.drawText("Retrospective (click to capture):", bounds.removeFromTop(20), juce::Justification::centredLeft);
    
    auto segRow = bounds.removeFromTop(35);
    const char* labels[] = {"1/16", "1/8", "1/4", "1/2", "1", "2", "4", "8", "16"};
    float barValues[] = {0.0625f, 0.125f, 0.25f, 0.5f, 1.0f, 2.0f, 4.0f, 8.0f, 16.0f};
    
    for (int i = 0; i < 9; ++i) {
        auto seg = segRow.removeFromLeft(40);
        segRow.removeFromLeft(5);
        
        // Highlight if this duration would fit in capture
        int samplesNeeded = static_cast<int>(barValues[i] * processor.getSamplesPerBar());
        bool canCapture = samplesNeeded <= numSamples;
        
        g.setColour(canCapture ? juce::Colour(0xff2d4059) : juce::Colour(0xff1a1a1a));
        g.fillRoundedRectangle(seg.toFloat(), 4);
        g.setColour(canCapture ? juce::Colours::white : juce::Colours::grey);
        g.setFont(11.0f);
        g.drawText(labels[i], seg, juce::Justification::centred);
    }
    
    bounds.removeFromTop(10);
    
    // Layers
    g.setColour(juce::Colours::white);
    g.setFont(12.0f);
    g.drawText("Layers (click to select):", bounds.removeFromTop(20), juce::Justification::centredLeft);
    
    for (int i = 0; i < LooperProcessor::MAX_LAYERS; ++i) {
        auto layerBounds = bounds.removeFromTop(30);
        bounds.removeFromTop(5);
        
        auto& layer = processor.getLayer(i);
        
        // Layer background
        bool isActive = (processor.getActiveLayerIndex() == i);
        g.setColour(isActive ? juce::Colour(0xff3d5a80) : juce::Colour(0xff293241));
        g.fillRoundedRectangle(layerBounds.toFloat(), 4);
        
        // Layer state text
        juce::String stateText;
        juce::Colour stateColor = juce::Colours::white;
        switch (layer.getState()) {
            case LooperLayer::State::Empty: 
                stateText = "Empty"; 
                stateColor = juce::Colours::grey;
                break;
            case LooperLayer::State::Playing: 
                stateText = "Playing (" + juce::String(layer.getLength() / 44100.0, 2) + "s)"; 
                stateColor = juce::Colour(0xff00ff88);
                break;
            case LooperLayer::State::Recording: 
                stateText = "Recording"; 
                stateColor = juce::Colours::red;
                break;
            case LooperLayer::State::Overdubbing: 
                stateText = "Overdubbing"; 
                stateColor = juce::Colours::orange;
                break;
            case LooperLayer::State::Muted: 
                stateText = "Muted"; 
                stateColor = juce::Colours::grey;
                break;
        }
        
        g.setColour(juce::Colours::white);
        g.setFont(13.0f);
        g.drawText("L" + juce::String(i) + ":", layerBounds.reduced(8, 0), juce::Justification::centredLeft);
        
        g.setColour(stateColor);
        g.drawText(stateText, layerBounds.reduced(35, 0), juce::Justification::centredLeft);
        
        // Playhead
        if (layer.getState() == LooperLayer::State::Playing && layer.getLength() > 0) {
            float pos = static_cast<float>(layer.getPosition()) / layer.getLength();
            int playheadX = layerBounds.getX() + static_cast<int>(pos * layerBounds.getWidth());
            g.setColour(juce::Colour(0xffff0000));
            g.drawVerticalLine(playheadX, layerBounds.getY() + 2, layerBounds.getBottom() - 2);
        }
    }
    
    // Status bar
    auto statusBounds = getLocalBounds().removeFromBottom(25);
    g.setColour(juce::Colours::grey);
    g.setFont(12.0f);
    
    float samplesPerBar = processor.getSamplesPerBar();
    float barDuration = samplesPerBar / processor.getSampleRate();
    
    g.drawText("Tempo: " + juce::String(processor.getTempo(), 1) + " BPM | " +
               "1 bar = " + juce::String(barDuration, 2) + "s", 
               statusBounds.reduced(10, 0), juce::Justification::centredLeft);
    
    g.setColour(processor.isRecording() ? juce::Colours::red : juce::Colours::grey);
    g.drawText(processor.isRecording() ? "RECORDING" : "Ready", 
               statusBounds.reduced(10, 0), juce::Justification::centredRight);
}

void LooperEditor::resized() {}

void LooperEditor::mouseDown(const juce::MouseEvent& e) {
    auto pos = e.getPosition();
    auto bounds = getLocalBounds().reduced(10);
    
    // Skip title
    bounds.removeFromTop(35 + 10);
    
    // Button row
    auto btnRow = bounds.removeFromTop(40);
    
    // REC button
    if (pos.x >= btnRow.getX() && pos.x < btnRow.getX() + 80 &&
        pos.y >= btnRow.getY() && pos.y < btnRow.getY() + 40) {
        if (processor.isRecording()) processor.stopRecording();
        else processor.startRecording();
        return;
    }
    btnRow.removeFromLeft(80 + 10);
    
    // STOP button  
    if (pos.x >= btnRow.getX() && pos.x < btnRow.getX() + 80 &&
        pos.y >= btnRow.getY() && pos.y < btnRow.getY() + 40) {
        processor.stopRecording();
        return;
    }
    btnRow.removeFromLeft(80 + 10);
    
    // Mode button
    if (pos.x >= btnRow.getX() && pos.x < btnRow.getX() + 120 &&
        pos.y >= btnRow.getY() && pos.y < btnRow.getY() + 40) {
        int next = (static_cast<int>(processor.getRecordMode()) + 1) % 4;
        processor.setRecordMode(static_cast<RecordMode>(next));
        return;
    }
    
    // Skip to segment buttons
    bounds.removeFromTop(40 + 10 + 80 + 10 + 20);
    auto segRow = bounds.removeFromTop(35);
    
    // Segment buttons
    float barValues[] = {0.0625f, 0.125f, 0.25f, 0.5f, 1.0f, 2.0f, 4.0f, 8.0f, 16.0f};
    for (int i = 0; i < 9; ++i) {
        auto seg = segRow.removeFromLeft(40);
        segRow.removeFromLeft(5);
        
        if (pos.x >= seg.getX() && pos.x < seg.getRight() &&
            pos.y >= seg.getY() && pos.y < seg.getBottom()) {
            processor.commitRetrospective(barValues[i]);
            return;
        }
    }
    
    // Skip to layers
    bounds.removeFromTop(10 + 20);
    
    for (int i = 0; i < LooperProcessor::MAX_LAYERS; ++i) {
        auto layerBounds = bounds.removeFromTop(30);
        bounds.removeFromTop(5);
        
        if (pos.x >= layerBounds.getX() && pos.x < layerBounds.getRight() &&
            pos.y >= layerBounds.getY() && pos.y < layerBounds.getBottom()) {
            processor.setActiveLayer(i);
            return;
        }
    }
}
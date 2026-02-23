#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <fstream>
#include <chrono>

static void debugLog(const std::string& msg)
{
    std::ofstream f("/tmp/grainfreeze_debug.log", std::ios::app);
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    f << std::ctime(&time) << ": " << msg << std::endl;
}

AudioPluginAudioProcessorEditor::AudioPluginAudioProcessorEditor(AudioPluginAudioProcessor& p)
    : AudioProcessorEditor(&p), processorRef(p)
{
    debugLog("Editor constructor started");
    
    setSize(750, 680);
    debugLog("setSize done");
    
    titleLabel.setText("GRAIN FREEZE", juce::dontSendNotification);
    titleLabel.setJustificationType(juce::Justification::centred);
    titleLabel.setColour(juce::Label::textColourId, juce::Colour(220, 230, 250));
    titleLabel.setFont(juce::FontOptions(22.0f, juce::Font::bold));
    addAndMakeVisible(titleLabel);
    debugLog("titleLabel done");
    
    subtitleLabel.setText("Live Sampling Granular Synthesizer", juce::dontSendNotification);
    subtitleLabel.setJustificationType(juce::Justification::centred);
    subtitleLabel.setColour(juce::Label::textColourId, juce::Colour(100, 115, 140));
    subtitleLabel.setFont(juce::FontOptions(10.0f));
    addAndMakeVisible(subtitleLabel);
    debugLog("subtitleLabel done");
    
    waveformDisplay = std::make_unique<WaveformDisplay>(p);
    addAndMakeVisible(*waveformDisplay);
    debugLog("waveformDisplay done");
    
    freezeButton = std::make_unique<FreezeButton>(p.apvts);
    addAndMakeVisible(*freezeButton);
    debugLog("freezeButton done");
    
    reverseButton = std::make_unique<ReverseButton>(p.apvts);
    addAndMakeVisible(*reverseButton);
    debugLog("reverseButton done");
    
    keyboard = std::make_unique<juce::MidiKeyboardComponent>(keyboardState, juce::MidiKeyboardComponent::horizontalKeyboard);
    keyboard->setOctaveForMiddleC(4);
    keyboard->setLowestVisibleKey(36);
    keyboard->setColour(juce::MidiKeyboardComponent::whiteNoteColourId, juce::Colour(45, 50, 62));
    keyboard->setColour(juce::MidiKeyboardComponent::blackNoteColourId, juce::Colour(25, 28, 36));
    keyboard->setColour(juce::MidiKeyboardComponent::keySeparatorLineColourId, juce::Colour(60, 70, 90));
    keyboard->setColour(juce::MidiKeyboardComponent::keyDownOverlayColourId, juce::Colour(0, 200, 160));
    keyboard->setColour(juce::MidiKeyboardComponent::mouseOverKeyOverlayColourId, juce::Colour(0, 180, 140).withAlpha(0.3f));
    keyboard->setKeyWidth(20.0f);
    addAndMakeVisible(*keyboard);
    keyboardState.addListener(this);
    debugLog("keyboard done");
    
    auto addSlider = [&](const juce::String& name, const juce::String& paramID) {
        if (p.apvts.getParameter(paramID) != nullptr)
        {
            auto* slider = new SimpleSlider(name, p.apvts, paramID);
            sliders.add(slider);
            addAndMakeVisible(slider);
            debugLog("added slider: " + name.toStdString());
        }
        else
        {
            debugLog("MISSING PARAM: " + paramID.toStdString());
        }
    };
    
    addSlider("Grain Size", "grainSize");
    addSlider("Density", "density");
    addSlider("Randomize", "randomize");
    addSlider("Spread", "spread");
    addSlider("Dry/Wet", "dryWet");
    addSlider("Scrub", "scrub");
    addSlider("Reverb Mix", "reverbMix");
    addSlider("Reverb Size", "reverbSize");
    addSlider("Shimmer", "shimmerAmount");
    addSlider("Volume", "masterVolume");
    
    debugLog("Editor constructor complete, sliders count: " + std::to_string(sliders.size()));
    
    resized();
}

AudioPluginAudioProcessorEditor::~AudioPluginAudioProcessorEditor()
{
    keyboardState.removeListener(this);
}

void AudioPluginAudioProcessorEditor::handleNoteOn(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float velocity)
{
    auto msg = juce::MidiMessage::noteOn(midiChannel, midiNoteNumber, velocity);
    processorRef.processBlockMidi(msg);
}

void AudioPluginAudioProcessorEditor::handleNoteOff(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float)
{
    auto msg = juce::MidiMessage::noteOff(midiChannel, midiNoteNumber);
    processorRef.processBlockMidi(msg);
}

void AudioPluginAudioProcessorEditor::paint(juce::Graphics& g)
{
    debugLog("paint() called");
    auto bounds = getLocalBounds().toFloat();
    
    debugLog("paint bounds: " + std::to_string(bounds.getWidth()) + "x" + std::to_string(bounds.getHeight()));
    
    g.setColour(juce::Colour(18, 20, 26));
    g.fillRect(bounds);
    
    g.setColour(juce::Colour(28, 32, 42));
    g.fillRect(bounds.removeFromTop(50));
    
    g.setColour(juce::Colour(40, 46, 60));
    g.fillRect(bounds.removeFromTop(2));
    
    g.setColour(juce::Colour(0, 255, 200).withAlpha(0.15f));
    g.fillRect(0.0f, 0.0f, 3.0f, static_cast<float>(getHeight()));
}

void AudioPluginAudioProcessorEditor::resized()
{
    debugLog("resized() called");
    auto bounds = getLocalBounds();
    debugLog("resized bounds: " + std::to_string(bounds.getWidth()) + "x" + std::to_string(bounds.getHeight()));
    
    auto headerBounds = bounds.removeFromTop(50);
    titleLabel.setBounds(headerBounds.removeFromTop(26));
    subtitleLabel.setBounds(headerBounds);
    
    auto contentBounds = bounds.reduced(15, 10);
    
    if (waveformDisplay)
    {
        auto wb = contentBounds.removeFromTop(80);
        waveformDisplay->setBounds(wb);
        debugLog("waveformDisplay bounds: " + std::to_string(wb.getX()) + "," + std::to_string(wb.getY()) + " " + std::to_string(wb.getWidth()) + "x" + std::to_string(wb.getHeight()));
    }
    contentBounds.removeFromTop(8);
    
    auto buttonRow = contentBounds.removeFromTop(36);
    if (freezeButton)
    {
        freezeButton->setBounds(buttonRow.removeFromLeft(120));
    }
    if (reverseButton)
    {
        reverseButton->setBounds(buttonRow.removeFromLeft(60).reduced(2));
    }
    contentBounds.removeFromTop(8);
    
    if (keyboard)
    {
        auto kb = contentBounds.removeFromTop(50);
        keyboard->setBounds(kb);
        debugLog("keyboard bounds: " + std::to_string(kb.getWidth()) + "x" + std::to_string(kb.getHeight()));
    }
    contentBounds.removeFromTop(8);
    
    auto row1 = contentBounds.removeFromTop(95);
    int sliderWidth = row1.getWidth() / 6;
    for (int i = 0; i < 6 && i < sliders.size(); ++i)
        sliders[i]->setBounds(row1.removeFromLeft(sliderWidth).reduced(4, 0));
    
    debugLog("row1 sliders done");
    
    contentBounds.removeFromTop(8);
    
    auto row2 = contentBounds.removeFromTop(95);
    for (int i = 6; i < 10 && i < sliders.size(); ++i)
        sliders[i]->setBounds(row2.removeFromLeft(sliderWidth).reduced(4, 0));
    
    debugLog("resized() complete");
}

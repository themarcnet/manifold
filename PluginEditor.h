#pragma once

#include "PluginProcessor.h"
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_utils/juce_audio_utils.h>

class WaveformDisplay : public juce::Component, public juce::Timer
{
public:
    WaveformDisplay(AudioPluginAudioProcessor& proc) : processor(proc)
    {
        startTimerHz(30);
    }
    
    ~WaveformDisplay() override { stopTimer(); }
    
    void paint(juce::Graphics& g) override
    {
        auto bounds = getLocalBounds().toFloat();
        auto frozen = processor.isFrozen();
        
        g.setColour(juce::Colour(20, 22, 28));
        g.fillRoundedRectangle(bounds, 6.0f);
        
        g.setColour(juce::Colour(40, 44, 56));
        g.drawRoundedRectangle(bounds.reduced(0.5f), 6.0f, 1.0f);
        
        auto waveformBounds = bounds.reduced(8.0f);
        
        if (frozen)
        {
            g.setColour(juce::Colour(0, 255, 180).withAlpha(0.08f));
            g.fillRoundedRectangle(waveformBounds, 4.0f);
        }
        
        int bufferSize = processor.getBufferSize();
        int writePos = processor.getBufferWritePos();
        
        if (bufferSize > 0)
        {
            auto path = juce::Path();
            float width = waveformBounds.getWidth();
            float height = waveformBounds.getHeight();
            float centerY = waveformBounds.getCentreY();
            
            int samplesPerPixel = juce::jmax(1, bufferSize / static_cast<int>(width));
            
            g.setColour(frozen ? juce::Colour(0, 255, 180) : juce::Colour(100, 120, 255));
            
            for (int x = 0; x < static_cast<int>(width); ++x)
            {
                int sampleIndex = writePos - bufferSize + (x * samplesPerPixel);
                if (sampleIndex < 0) sampleIndex += bufferSize;
                
                float sample = processor.getWaveformData(0, sampleIndex);
                float y = centerY - sample * height * 0.4f;
                
                if (x == 0)
                    path.startNewSubPath(waveformBounds.getX() + x, y);
                else
                    path.lineTo(waveformBounds.getX() + x, y);
            }
            
            g.strokePath(path, juce::PathStrokeType(1.5f));
            
            auto grains = processor.getActiveGrains();
            for (const auto& grain : grains)
            {
                if (grain.active)
                {
                    float x = waveformBounds.getX() + grain.normalizedPosition * width;
                    float alpha = grain.envelope * 0.8f;
                    
                    g.setColour(juce::Colour(255, 100, 100).withAlpha(alpha));
                    g.drawLine(x, waveformBounds.getY(), x, waveformBounds.getBottom(), 2.0f);
                    
                    g.setColour(juce::Colour(255, 150, 150).withAlpha(alpha * 0.5f));
                    g.fillEllipse(x - 3.0f, waveformBounds.getCentreY() - 3.0f, 6.0f, 6.0f);
                }
            }
        }
        
        g.setColour(juce::Colours::white.withAlpha(0.6f));
        g.setFont(juce::FontOptions(11.0f));
        auto label = frozen ? "FROZEN" : "LIVE";
        g.drawText(label, bounds.reduced(10), juce::Justification::topRight);
    }
    
    void timerCallback() override { repaint(); }
    
private:
    AudioPluginAudioProcessor& processor;
};

class SimpleSlider : public juce::Component
{
public:
    SimpleSlider(const juce::String& name, juce::AudioProcessorValueTreeState& vts, const juce::String& paramID)
        : attachment(vts, paramID, slider)
    {
        label.setText(name, juce::dontSendNotification);
        label.setJustificationType(juce::Justification::centred);
        label.setColour(juce::Label::textColourId, juce::Colour(160, 170, 190));
        label.setFont(juce::FontOptions(11.0f));
        addAndMakeVisible(label);
        
        slider.setSliderStyle(juce::Slider::RotaryVerticalDrag);
        slider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 50, 18);
        slider.setColour(juce::Slider::rotarySliderFillColourId, juce::Colour(0, 200, 160));
        slider.setColour(juce::Slider::rotarySliderOutlineColourId, juce::Colour(50, 56, 72));
        slider.setColour(juce::Slider::thumbColourId, juce::Colour(0, 255, 200));
        slider.setColour(juce::Slider::trackColourId, juce::Colour(0, 180, 140));
        slider.setColour(juce::Slider::textBoxTextColourId, juce::Colour(200, 210, 230));
        slider.setColour(juce::Slider::textBoxBackgroundColourId, juce::Colour(25, 28, 36));
        slider.setColour(juce::Slider::textBoxOutlineColourId, juce::Colour(50, 56, 72));
        addAndMakeVisible(slider);
    }
    
    void resized() override
    {
        auto bounds = getLocalBounds();
        label.setBounds(bounds.removeFromTop(18));
        slider.setBounds(bounds);
    }
    
private:
    juce::Label label;
    juce::Slider slider;
    juce::AudioProcessorValueTreeState::SliderAttachment attachment;
};

class FreezeButton : public juce::Component, public juce::Timer
{
public:
    FreezeButton(juce::AudioProcessorValueTreeState& vts)
        : apvts(vts)
    {
        startTimerHz(15);
        setMouseCursor(juce::MouseCursor::PointingHandCursor);
    }
    
    ~FreezeButton() override { stopTimer(); }
    
    void paint(juce::Graphics& g) override
    {
        auto bounds = getLocalBounds().toFloat().reduced(2.0f);
        
        if (isFrozen)
        {
            g.setColour(juce::Colour(0, 200, 160));
            g.fillRoundedRectangle(bounds, 8.0f);
            g.setColour(juce::Colour(0, 255, 200));
            g.drawRoundedRectangle(bounds, 8.0f, 2.0f);
            g.setColour(juce::Colour(20, 30, 40));
        }
        else
        {
            g.setColour(juce::Colour(35, 40, 52));
            g.fillRoundedRectangle(bounds, 8.0f);
            g.setColour(juce::Colour(60, 70, 90));
            g.drawRoundedRectangle(bounds, 8.0f, 1.5f);
            g.setColour(juce::Colour(140, 150, 170));
        }
        
        g.setFont(juce::FontOptions(14.0f, juce::Font::bold));
        g.drawText(isFrozen ? "FROZEN" : "FREEZE", bounds, juce::Justification::centred);
    }
    
    void mouseDown(const juce::MouseEvent&) override
    {
        if (auto* param = apvts.getParameter("freeze"))
            param->setValueNotifyingHost(param->getValue() > 0.5f ? 0.0f : 1.0f);
    }
    
    void timerCallback() override
    {
        if (auto* param = apvts.getParameter("freeze"))
            isFrozen = param->getValue() > 0.5f;
        repaint();
    }
    
private:
    juce::AudioProcessorValueTreeState& apvts;
    bool isFrozen = false;
};

class ReverseButton : public juce::Component, public juce::Timer
{
public:
    ReverseButton(juce::AudioProcessorValueTreeState& vts)
        : apvts(vts)
    {
        startTimerHz(15);
        setMouseCursor(juce::MouseCursor::PointingHandCursor);
    }
    
    ~ReverseButton() override { stopTimer(); }
    
    void paint(juce::Graphics& g) override
    {
        auto bounds = getLocalBounds().toFloat().reduced(2.0f);
        
        if (isReverse)
        {
            g.setColour(juce::Colour(200, 100, 50));
            g.fillRoundedRectangle(bounds, 6.0f);
            g.setColour(juce::Colour(255, 150, 80));
            g.drawRoundedRectangle(bounds, 6.0f, 2.0f);
            g.setColour(juce::Colour(20, 30, 40));
        }
        else
        {
            g.setColour(juce::Colour(35, 40, 52));
            g.fillRoundedRectangle(bounds, 6.0f);
            g.setColour(juce::Colour(60, 70, 90));
            g.drawRoundedRectangle(bounds, 6.0f, 1.5f);
            g.setColour(juce::Colour(140, 150, 170));
        }
        
        g.setFont(juce::FontOptions(12.0f, juce::Font::bold));
        g.drawText("REV", bounds, juce::Justification::centred);
    }
    
    void mouseDown(const juce::MouseEvent&) override
    {
        if (auto* param = apvts.getParameter("reverse"))
            param->setValueNotifyingHost(param->getValue() > 0.5f ? 0.0f : 1.0f);
    }
    
    void timerCallback() override
    {
        if (auto* param = apvts.getParameter("reverse"))
            isReverse = param->getValue() > 0.5f;
        repaint();
    }
    
private:
    juce::AudioProcessorValueTreeState& apvts;
    bool isReverse = false;
};

class AudioPluginAudioProcessorEditor final : public juce::AudioProcessorEditor,
                                               public juce::MidiKeyboardStateListener
{
public:
    explicit AudioPluginAudioProcessorEditor(AudioPluginAudioProcessor& p);
    ~AudioPluginAudioProcessorEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;
    
    void handleNoteOn(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float velocity) override;
    void handleNoteOff(juce::MidiKeyboardState*, int midiChannel, int midiNoteNumber, float velocity) override;

private:
    AudioPluginAudioProcessor& processorRef;
    
    std::unique_ptr<WaveformDisplay> waveformDisplay;
    std::unique_ptr<FreezeButton> freezeButton;
    std::unique_ptr<ReverseButton> reverseButton;
    
    juce::MidiKeyboardState keyboardState;
    std::unique_ptr<juce::MidiKeyboardComponent> keyboard;
    
    juce::OwnedArray<SimpleSlider> sliders;
    
    juce::Label titleLabel;
    juce::Label subtitleLabel;
    
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AudioPluginAudioProcessorEditor)
};

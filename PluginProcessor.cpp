#include "PluginProcessor.h"
#include "PluginEditor.h"

AudioPluginAudioProcessor::AudioPluginAudioProcessor()
    : AudioProcessor(BusesProperties()
        .withInput("Input", juce::AudioChannelSet::stereo(), true)
        .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      apvts(*this, nullptr, "Parameters", createParameterLayout())
{
    freezeParam = apvts.getRawParameterValue("freeze");
    grainSizeParam = apvts.getRawParameterValue("grainSize");
    densityParam = apvts.getRawParameterValue("density");
    randomizeParam = apvts.getRawParameterValue("randomize");
    spreadParam = apvts.getRawParameterValue("spread");
    reverbMixParam = apvts.getRawParameterValue("reverbMix");
    reverbSizeParam = apvts.getRawParameterValue("reverbSize");
    reverbDampingParam = apvts.getRawParameterValue("reverbDamping");
    shimmerAmountParam = apvts.getRawParameterValue("shimmerAmount");
    shimmerFeedbackParam = apvts.getRawParameterValue("shimmerFeedback");
    shimmerSizeParam = apvts.getRawParameterValue("shimmerSize");
    masterVolumeParam = apvts.getRawParameterValue("masterVolume");
    dryWetParam = apvts.getRawParameterValue("dryWet");
    scrubParam = apvts.getRawParameterValue("scrub");
    reverseParam = apvts.getRawParameterValue("reverse");
}

AudioPluginAudioProcessor::~AudioPluginAudioProcessor()
{
}

juce::AudioProcessorValueTreeState::ParameterLayout AudioPluginAudioProcessor::createParameterLayout()
{
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> params;
    
    params.push_back(std::make_unique<juce::AudioParameterBool>(
        juce::ParameterID("freeze", 1), "Freeze", false));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("grainSize", 1), "Grain Size",
        juce::NormalisableRange<float>(0.01f, 2.0f, 0.001f, 0.5f), 0.15f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("density", 1), "Density",
        juce::NormalisableRange<float>(1.0f, 50.0f, 0.1f, 0.5f), 15.0f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("randomize", 1), "Randomize",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.3f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("spread", 1), "Spread",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.2f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("reverbMix", 1), "Reverb Mix",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.3f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("reverbSize", 1), "Reverb Size",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.7f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("reverbDamping", 1), "Reverb Damping",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("shimmerAmount", 1), "Shimmer Amount",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.0f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("shimmerFeedback", 1), "Shimmer Feedback",
        juce::NormalisableRange<float>(0.0f, 0.95f, 0.01f), 0.6f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("shimmerSize", 1), "Shimmer Size",
        juce::NormalisableRange<float>(0.1f, 1.0f, 0.01f), 0.5f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("masterVolume", 1), "Master Volume",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.7f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("dryWet", 1), "Dry/Wet",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f), 0.5f));
    
    params.push_back(std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID("scrub", 1), "Scrub",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.001f), 0.1f));
    
    params.push_back(std::make_unique<juce::AudioParameterBool>(
        juce::ParameterID("reverse", 1), "Reverse", false));
    
    return { params.begin(), params.end() };
}

const juce::String AudioPluginAudioProcessor::getName() const
{
    return JucePlugin_Name;
}

bool AudioPluginAudioProcessor::acceptsMidi() const { return true; }
bool AudioPluginAudioProcessor::producesMidi() const { return false; }
bool AudioPluginAudioProcessor::isMidiEffect() const { return false; }
double AudioPluginAudioProcessor::getTailLengthSeconds() const { return 2.0; }

int AudioPluginAudioProcessor::getNumPrograms() { return 1; }
int AudioPluginAudioProcessor::getCurrentProgram() { return 0; }
void AudioPluginAudioProcessor::setCurrentProgram(int) {}
const juce::String AudioPluginAudioProcessor::getProgramName(int) { return {}; }
void AudioPluginAudioProcessor::changeProgramName(int, const juce::String&) {}

void AudioPluginAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    granularEngine.prepare(sampleRate, juce::jmax(2, getTotalNumInputChannels()));
    effectsProcessor.prepare(sampleRate, samplesPerBlock, juce::jmax(2, getTotalNumOutputChannels()));
}

void AudioPluginAudioProcessor::releaseResources()
{
}

bool AudioPluginAudioProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const
{
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono()
     && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;

    return true;
}

void AudioPluginAudioProcessor::processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ScopedNoDenormals noDenormals;
    
    midiMessages.addEvents(pendingMidiBuffer, 0, -1, 0);
    pendingMidiBuffer.clear();
    
    auto totalNumInputChannels = getTotalNumInputChannels();
    auto totalNumOutputChannels = getTotalNumOutputChannels();

    for (auto i = totalNumInputChannels; i < totalNumOutputChannels; ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    bool freeze = freezeParam->load() > 0.5f;
    granularEngine.setFrozen(freeze);
    
    float grainSize = grainSizeParam->load();
    float density = densityParam->load();
    float randomize = randomizeParam->load();
    float spread = spreadParam->load();
    float dryWet = dryWetParam->load();
    float scrub = scrubParam->load();
    bool reverse = reverseParam->load() > 0.5f;
    
    granularEngine.process(buffer, midiMessages, grainSize, density, randomize, spread, scrub, reverse, dryWet);
    
    float reverbMix = reverbMixParam->load();
    float reverbSize = reverbSizeParam->load();
    float reverbDamping = reverbDampingParam->load();
    float shimmerAmount = shimmerAmountParam->load();
    float shimmerFeedback = shimmerFeedbackParam->load();
    float shimmerSize = shimmerSizeParam->load();
    
    effectsProcessor.process(buffer, reverbMix, reverbSize, reverbDamping,
                             shimmerAmount, shimmerFeedback, shimmerSize);
    
    float volume = masterVolumeParam->load();
    buffer.applyGain(volume);
}

bool AudioPluginAudioProcessor::hasEditor() const { return true; }

juce::AudioProcessorEditor* AudioPluginAudioProcessor::createEditor()
{
    return new AudioPluginAudioProcessorEditor(*this);
}

void AudioPluginAudioProcessor::getStateInformation(juce::MemoryBlock& destData)
{
    auto state = apvts.copyState();
    std::unique_ptr<juce::XmlElement> xml(state.createXml());
    copyXmlToBinary(*xml, destData);
}

void AudioPluginAudioProcessor::setStateInformation(const void* data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xmlState(getXmlFromBinary(data, sizeInBytes));
    if (xmlState.get() != nullptr)
        if (xmlState->hasTagName(apvts.state.getType()))
            apvts.replaceState(juce::ValueTree::fromXml(*xmlState));
}

float AudioPluginAudioProcessor::getWaveformData(int channel, int sampleIndex) const
{
    return granularEngine.getWaveformSample(channel, sampleIndex);
}

int AudioPluginAudioProcessor::getBufferSize() const
{
    return granularEngine.getBufferSize();
}

int AudioPluginAudioProcessor::getBufferWritePos() const
{
    return granularEngine.getBufferWritePos();
}

bool AudioPluginAudioProcessor::isFrozen() const
{
    return granularEngine.isFrozen();
}

std::vector<GrainInfo> AudioPluginAudioProcessor::getActiveGrains() const
{
    return granularEngine.getActiveGrains();
}

void AudioPluginAudioProcessor::processBlockMidi(const juce::MidiMessage& msg)
{
    pendingMidiBuffer.addEvent(msg, 0);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new AudioPluginAudioProcessor();
}

#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include "manifold/primitives/midi/MidiManager.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

// ============================================================================
// Voice Structure for Polyphonic MIDI Synthesis
// ============================================================================
struct SynthesizerVoice {
    // Voice state
    std::atomic<bool> active{false};
    std::atomic<bool> gate{false};
    std::atomic<uint8_t> note{0};
    std::atomic<uint8_t> velocity{0};
    std::atomic<float> frequency{440.0f};
    std::atomic<float> amplitude{0.0f};
    std::atomic<float> pitchBend{0.0f};  // -1.0 to +1.0
    
    // Oscillator state
    double phase = 0.0;
    double phaseIncrement = 0.0;
    
    // Filter state
    float filterCutoff = 20000.0f;
    float filterResonance = 0.707f;
    float filterState[2] = {0.0f, 0.0f};
    
    // Envelope state (for ADSR)
    float envelopeLevel = 0.0f;
    enum class EnvStage { Off, Attack, Decay, Sustain, Release };
    EnvStage envStage = EnvStage::Off;
    int samplesInStage = 0;
    
    void reset() {
        active.store(false, std::memory_order_relaxed);
        gate.store(false, std::memory_order_relaxed);
        note.store(0, std::memory_order_relaxed);
        velocity.store(0, std::memory_order_relaxed);
        frequency.store(440.0f, std::memory_order_relaxed);
        amplitude.store(0.0f, std::memory_order_relaxed);
        pitchBend.store(0.0f, std::memory_order_relaxed);
        phase = 0.0;
        phaseIncrement = 0.0;
        filterState[0] = filterState[1] = 0.0f;
        envelopeLevel = 0.0f;
        envStage = EnvStage::Off;
        samplesInStage = 0;
    }
    
    void trigger(uint8_t noteNum, uint8_t vel, float freq) {
        note.store(noteNum, std::memory_order_relaxed);
        velocity.store(vel, std::memory_order_relaxed);
        frequency.store(freq, std::memory_order_relaxed);
        gate.store(true, std::memory_order_relaxed);
        active.store(true, std::memory_order_release);
        phaseIncrement = 2.0 * M_PI * freq / 44100.0;  // Will be updated in prepare
    }
    
    void release() {
        gate.store(false, std::memory_order_release);
    }
};

// ============================================================================
// MidiVoiceNode - Polyphonic MIDI synthesizer voice processor
// ============================================================================
class MidiVoiceNode : public IPrimitiveNode, public std::enable_shared_from_this<MidiVoiceNode> {
public:
    static constexpr int MAX_VOICES = 16;
    
    MidiVoiceNode();
    
    const char* getNodeType() const override { return "MidiVoice"; }
    int getNumInputs() const override { return 0; }
    int getNumOutputs() const override { return 1; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    
    // MIDI event handling
    void noteOn(uint8_t channel, uint8_t note, uint8_t velocity);
    void noteOff(uint8_t channel, uint8_t note);
    void allNotesOff();
    void allSoundOff();
    void pitchBend(uint8_t channel, int16_t value);
    void controlChange(uint8_t channel, uint8_t cc, uint8_t value);
    
    // Parameter setters
    void setWaveform(int shape) { waveform_.store(juce::jlimit(0, 6, shape), std::memory_order_release); }
    void setAttack(float seconds) { attackTime_.store(juce::jlimit(0.001f, 10.0f, seconds), std::memory_order_release); }
    void setDecay(float seconds) { decayTime_.store(juce::jlimit(0.001f, 10.0f, seconds), std::memory_order_release); }
    void setSustain(float level) { sustainLevel_.store(juce::jlimit(0.0f, 1.0f, level), std::memory_order_release); }
    void setRelease(float seconds) { releaseTime_.store(juce::jlimit(0.001f, 10.0f, seconds), std::memory_order_release); }
    void setFilterCutoff(float freq) { filterCutoff_.store(juce::jlimit(20.0f, 20000.0f, freq), std::memory_order_release); }
    void setFilterResonance(float q) { filterResonance_.store(juce::jlimit(0.1f, 10.0f, q), std::memory_order_release); }
    void setFilterEnvAmount(float amount) { filterEnvAmount_.store(juce::jlimit(-1.0f, 1.0f, amount), std::memory_order_release); }
    void setEnabled(bool en) { enabled_.store(en, std::memory_order_release); }
    void setPolyphony(int voices) { polyphony_.store(juce::jlimit(1, MAX_VOICES, voices), std::memory_order_release); }
    void setGlide(float seconds) { glideTime_.store(juce::jlimit(0.0f, 5.0f, seconds), std::memory_order_release); }
    void setDetune(float cents) { detune_.store(juce::jlimit(0.0f, 100.0f, cents), std::memory_order_release); }
    void setSpread(float spread) { stereoSpread_.store(juce::jlimit(0.0f, 1.0f, spread), std::memory_order_release); }
    void setUnison(int voices) { unisonVoices_.store(juce::jlimit(1, 8, voices), std::memory_order_release); }
    
    // Parameter getters
    int getWaveform() const { return waveform_.load(std::memory_order_acquire); }
    float getAttack() const { return attackTime_.load(std::memory_order_acquire); }
    float getDecay() const { return decayTime_.load(std::memory_order_acquire); }
    float getSustain() const { return sustainLevel_.load(std::memory_order_acquire); }
    float getRelease() const { return releaseTime_.load(std::memory_order_acquire); }
    float getFilterCutoff() const { return filterCutoff_.load(std::memory_order_acquire); }
    float getFilterResonance() const { return filterResonance_.load(std::memory_order_acquire); }
    float getFilterEnvAmount() const { return filterEnvAmount_.load(std::memory_order_acquire); }
    bool isEnabled() const { return enabled_.load(std::memory_order_acquire); }
    int getPolyphony() const { return polyphony_.load(std::memory_order_acquire); }
    int getNumActiveVoices() const;
    
    // Access to internal voices for advanced control
    SynthesizerVoice& getVoice(int index) { return voices_[index % MAX_VOICES]; }
    
private:
    int findFreeVoice();
    int findVoicePlayingNote(uint8_t note, uint8_t channel);
    void updateVoiceFrequency(SynthesizerVoice& voice);
    float processEnvelope(SynthesizerVoice& voice);
    float generateSample(SynthesizerVoice& voice, float* stereoPan = nullptr);
    float applyFilter(SynthesizerVoice& voice, float input);
    
    // Waveform generators
    float sineWave(double phase);
    float sawWave(double phase);
    float squareWave(double phase);
    float triangleWave(double phase);
    float noise();
    
    // Parameters
    std::atomic<int> waveform_{0};        // 0=sine, 1=saw, 2=square, 3=triangle, 4=noise, 5=pulse, 6=supersaw
    std::atomic<float> attackTime_{0.01f};
    std::atomic<float> decayTime_{0.1f};
    std::atomic<float> sustainLevel_{0.7f};
    std::atomic<float> releaseTime_{0.3f};
    std::atomic<float> filterCutoff_{20000.0f};
    std::atomic<float> filterResonance_{0.707f};
    std::atomic<float> filterEnvAmount_{0.0f};
    std::atomic<bool> enabled_{true};
    std::atomic<int> polyphony_{8};
    std::atomic<float> glideTime_{0.0f};
    std::atomic<float> detune_{0.0f};
    std::atomic<float> stereoSpread_{0.5f};
    std::atomic<int> unisonVoices_{1};
    
    // Voice state
    std::array<SynthesizerVoice, MAX_VOICES> voices_;
    int nextVoice_ = 0;  // Round-robin counter
    
    // Sample rate
    double sampleRate_ = 44100.0;
    
    // Pre-calculated coefficients
    float attackCoeff_ = 1.0f;
    float decayCoeff_ = 0.99f;
    float releaseCoeff_ = 0.95f;
};

} // namespace dsp_primitives

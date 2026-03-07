#include "MidiVoiceNode.h"
#include <cmath>
#include <cstdlib>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace dsp_primitives {

MidiVoiceNode::MidiVoiceNode() {
    for (auto& voice : voices_) {
        voice.reset();
    }
}

void MidiVoiceNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;
    
    // Pre-calculate envelope coefficients
    attackCoeff_ = 1.0f - std::exp(-1.0f / (attackTime_.load() * sampleRate_));
    decayCoeff_ = 1.0f - std::exp(-1.0f / (decayTime_.load() * sampleRate_));
    releaseCoeff_ = 1.0f - std::exp(-1.0f / (releaseTime_.load() * sampleRate_));
}

void MidiVoiceNode::process(const std::vector<AudioBufferView>& inputs,
                            std::vector<WritableAudioBufferView>& outputs,
                            int numSamples) {
    (void)inputs;
    
    if (outputs.empty() || !enabled_.load(std::memory_order_acquire)) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }
    
    auto& out = outputs[0];
    const int numChannels = out.numChannels;
    const int poly = polyphony_.load(std::memory_order_acquire);
    
    // Get current parameter values
    const int waveform = waveform_.load(std::memory_order_acquire);
    const float filterCutoff = filterCutoff_.load(std::memory_order_acquire);
    const float filterResonance = filterResonance_.load(std::memory_order_acquire);
    const float filterEnvAmt = filterEnvAmount_.load(std::memory_order_acquire);
    const float sustain = sustainLevel_.load(std::memory_order_acquire);
    const float glide = glideTime_.load(std::memory_order_acquire);
    const float detuneCents = detune_.load(std::memory_order_acquire);
    const float spread = stereoSpread_.load(std::memory_order_acquire);
    const int unison = unisonVoices_.load(std::memory_order_acquire);
    
    // Update envelope coefficients
    attackCoeff_ = 1.0f - std::exp(-1.0f / (attackTime_.load() * sampleRate_ * 0.001f + 1.0f));
    decayCoeff_ = 1.0f - std::exp(-1.0f / (decayTime_.load() * sampleRate_ * 0.001f + 1.0f));
    releaseCoeff_ = 1.0f - std::exp(-1.0f / (releaseTime_.load() * sampleRate_ * 0.001f + 1.0f));
    
    for (int i = 0; i < numSamples; ++i) {
        float leftSample = 0.0f;
        float rightSample = 0.0f;
        int activeVoiceCount = 0;
        
        for (int v = 0; v < poly; ++v) {
            auto& voice = voices_[v];
            
            if (!voice.active.load(std::memory_order_acquire)) {
                continue;
            }
            
            // Process envelope
            float envLevel = processEnvelope(voice);
            if (envLevel <= 0.0f && voice.envStage == SynthesizerVoice::EnvStage::Off) {
                voice.active.store(false, std::memory_order_release);
                continue;
            }
            
            // Update frequency with glide
            float targetFreq = voice.frequency.load(std::memory_order_acquire);
            float pitchBend = voice.pitchBend.load(std::memory_order_acquire);
            targetFreq *= std::pow(2.0f, pitchBend);  // Apply pitch bend
            
            if (glide > 0.0f) {
                float currentFreq = static_cast<float>(voice.phaseIncrement * sampleRate_ / (2.0 * M_PI));
                float glideCoeff = 1.0f - std::exp(-1.0f / (glide * sampleRate_));
                currentFreq += (targetFreq - currentFreq) * glideCoeff;
                voice.phaseIncrement = 2.0 * M_PI * currentFreq / sampleRate_;
            } else {
                voice.phaseIncrement = 2.0 * M_PI * targetFreq / sampleRate_;
            }
            
            // Generate audio for this voice
            float stereoPan[2] = {0.5f, 0.5f};
            float voiceSample = generateSample(voice, stereoPan);
            
            // Apply velocity scaling
            float vel = voice.velocity.load(std::memory_order_acquire) / 127.0f;
            voiceSample *= vel * envLevel;
            
            // Apply filter
            voice.filterCutoff = filterCutoff * std::pow(2.0f, filterEnvAmt * (envLevel - 0.5f) * 4.0f);
            voiceSample = applyFilter(voice, voiceSample);
            
            leftSample += voiceSample * stereoPan[0];
            rightSample += voiceSample * stereoPan[1];
            activeVoiceCount++;
        }
        
        // Mix down
        float outputGain = activeVoiceCount > 0 ? 1.0f / std::sqrt(static_cast<float>(activeVoiceCount)) : 0.0f;
        leftSample *= outputGain;
        rightSample *= outputGain;
        
        // Output
        if (numChannels >= 2) {
            out.setSample(0, i, leftSample);
            out.setSample(1, i, rightSample);
        } else {
            out.setSample(0, i, (leftSample + rightSample) * 0.5f);
        }
    }
}

float MidiVoiceNode::processEnvelope(SynthesizerVoice& voice) {
    const float attack = attackTime_.load(std::memory_order_acquire);
    const float decay = decayTime_.load(std::memory_order_acquire);
    const float sustain = sustainLevel_.load(std::memory_order_acquire);
    const float release = releaseTime_.load(std::memory_order_acquire);
    
    switch (voice.envStage) {
        case SynthesizerVoice::EnvStage::Off:
            return 0.0f;
            
        case SynthesizerVoice::EnvStage::Attack:
            voice.envelopeLevel += (1.0f - voice.envelopeLevel) * attackCoeff_;
            if (voice.envelopeLevel >= 0.99f) {
                voice.envelopeLevel = 1.0f;
                voice.envStage = SynthesizerVoice::EnvStage::Decay;
            }
            break;
            
        case SynthesizerVoice::EnvStage::Decay:
            voice.envelopeLevel += (sustain - voice.envelopeLevel) * decayCoeff_;
            if (!voice.gate.load(std::memory_order_acquire)) {
                voice.envStage = SynthesizerVoice::EnvStage::Release;
            }
            break;
            
        case SynthesizerVoice::EnvStage::Sustain:
            voice.envelopeLevel = sustain;
            if (!voice.gate.load(std::memory_order_acquire)) {
                voice.envStage = SynthesizerVoice::EnvStage::Release;
            }
            break;
            
        case SynthesizerVoice::EnvStage::Release:
            voice.envelopeLevel *= (1.0f - releaseCoeff_);
            if (voice.envelopeLevel < 0.001f) {
                voice.envelopeLevel = 0.0f;
                voice.envStage = SynthesizerVoice::EnvStage::Off;
                voice.active.store(false, std::memory_order_release);
            }
            break;
    }
    
    return voice.envelopeLevel;
}

float MidiVoiceNode::generateSample(SynthesizerVoice& voice, float* stereoPan) {
    const int waveform = waveform_.load(std::memory_order_acquire);
    const int unison = unisonVoices_.load(std::memory_order_acquire);
    const float detuneCents = detune_.load(std::memory_order_acquire);
    const float spread = stereoSpread_.load(std::memory_order_acquire);
    
    float sample = 0.0f;
    
    for (int u = 0; u < unison; ++u) {
        // Calculate detuned frequency for this unison voice
        float detuneAmount = (u - unison * 0.5f) * detuneCents / 100.0f;
        double freqMult = std::pow(2.0, detuneAmount / 12.0);
        double phaseInc = voice.phaseIncrement * freqMult;
        
        // Generate waveform
        float voiceSample = 0.0f;
        switch (waveform) {
            case 0: voiceSample = sineWave(voice.phase); break;
            case 1: voiceSample = sawWave(voice.phase); break;
            case 2: voiceSample = squareWave(voice.phase); break;
            case 3: voiceSample = triangleWave(voice.phase); break;
            case 4: voiceSample = noise(); break;
            case 5: voiceSample = (voice.phase < M_PI) ? 0.8f : -0.2f; break;  // Pulse
            case 6: {  // Supersaw (multiple detuned saws)
                voiceSample = sawWave(voice.phase);
                voiceSample += sawWave(voice.phase * 1.01) * 0.5f;
                voiceSample += sawWave(voice.phase * 0.99) * 0.5f;
                voiceSample *= 0.5f;
                break;
            }
            default: voiceSample = sineWave(voice.phase); break;
        }
        
        // Stereo spread
        float pan = 0.5f + (u - unison * 0.5f) * spread / unison;
        stereoPan[0] = std::sqrt(1.0f - pan);
        stereoPan[1] = std::sqrt(pan);
        
        // Advance phase
        voice.phase += phaseInc;
        while (voice.phase >= 2.0 * M_PI) voice.phase -= 2.0 * M_PI;
        
        sample += voiceSample;
    }
    
    return sample / static_cast<float>(unison);
}

float MidiVoiceNode::applyFilter(SynthesizerVoice& voice, float input) {
    // Simple state-variable filter
    float cutoff = voice.filterCutoff;
    float resonance = filterResonance_.load(std::memory_order_acquire);
    
    float f = 2.0f * std::sin(M_PI * cutoff / sampleRate_);
    float q = 1.0f / resonance;
    
    float low = voice.filterState[0] + f * voice.filterState[1];
    float high = input - low - q * voice.filterState[1];
    float band = f * high + voice.filterState[1];
    
    voice.filterState[0] = low;
    voice.filterState[1] = band;
    
    return low;
}

float MidiVoiceNode::sineWave(double phase) {
    return std::sin(phase);
}

float MidiVoiceNode::sawWave(double phase) {
    return static_cast<float>(2.0 * phase / (2.0 * M_PI) - 1.0);
}

float MidiVoiceNode::squareWave(double phase) {
    return (phase < M_PI) ? 1.0f : -1.0f;
}

float MidiVoiceNode::triangleWave(double phase) {
    float normalized = static_cast<float>(phase / (2.0 * M_PI));
    return 4.0f * std::abs(normalized - 0.5f) - 1.0f;
}

float MidiVoiceNode::noise() {
    return (static_cast<float>(std::rand()) / RAND_MAX) * 2.0f - 1.0f;
}

void MidiVoiceNode::noteOn(uint8_t channel, uint8_t note, uint8_t velocity) {
    (void)channel;
    
    // Check if note is already playing (retrigger)
    int existingVoice = findVoicePlayingNote(note, channel);
    if (existingVoice >= 0) {
        voices_[existingVoice].trigger(note, velocity, midi::noteToFrequency(note));
        return;
    }
    
    // Find free voice
    int voiceIdx = findFreeVoice();
    if (voiceIdx >= 0) {
        voices_[voiceIdx].trigger(note, velocity, midi::noteToFrequency(note));
        nextVoice_ = (voiceIdx + 1) % polyphony_.load();
    }
}

void MidiVoiceNode::noteOff(uint8_t channel, uint8_t note) {
    int voiceIdx = findVoicePlayingNote(note, channel);
    if (voiceIdx >= 0) {
        voices_[voiceIdx].release();
    }
}

void MidiVoiceNode::allNotesOff() {
    for (auto& voice : voices_) {
        voice.release();
    }
}

void MidiVoiceNode::allSoundOff() {
    for (auto& voice : voices_) {
        voice.reset();
    }
}

void MidiVoiceNode::pitchBend(uint8_t channel, int16_t value) {
    (void)channel;
    float bend = static_cast<float>(value) / 8192.0f;  // -1.0 to +1.0
    for (auto& voice : voices_) {
        if (voice.active.load(std::memory_order_acquire)) {
            voice.pitchBend.store(bend, std::memory_order_relaxed);
        }
    }
}

void MidiVoiceNode::controlChange(uint8_t channel, uint8_t cc, uint8_t value) {
    (void)channel;
    
    switch (cc) {
        case midi::Constants::CUTOFF:
            setFilterCutoff(20.0f + (value / 127.0f) * 19980.0f);
            break;
        case midi::Constants::RESONANCE:
            setFilterResonance(0.1f + (value / 127.0f) * 9.9f);
            break;
        case midi::Constants::ATTACK_TIME:
            setAttack(0.001f + (value / 127.0f) * 9.999f);
            break;
        case midi::Constants::RELEASE_TIME:
            setRelease(0.001f + (value / 127.0f) * 9.999f);
            break;
        case midi::Constants::DAMPER_PEDAL:
            if (value < 64) {
                // Release all sustained voices
                for (auto& voice : voices_) {
                    if (voice.active.load(std::memory_order_acquire)) {
                        voice.release();
                    }
                }
            }
            break;
    }
}

int MidiVoiceNode::findFreeVoice() {
    const int poly = polyphony_.load(std::memory_order_acquire);
    
    // First try to find an inactive voice
    for (int i = 0; i < poly; ++i) {
        int idx = (nextVoice_ + i) % poly;
        if (!voices_[idx].active.load(std::memory_order_acquire)) {
            return idx;
        }
    }
    
    // Voice stealing: find voice in release stage with lowest envelope
    int stealIdx = -1;
    float lowestLevel = 2.0f;
    for (int i = 0; i < poly; ++i) {
        if (voices_[i].envelopeLevel < lowestLevel) {
            lowestLevel = voices_[i].envelopeLevel;
            stealIdx = i;
        }
    }
    
    return stealIdx;
}

int MidiVoiceNode::findVoicePlayingNote(uint8_t note, uint8_t channel) {
    (void)channel;
    const int poly = polyphony_.load(std::memory_order_acquire);
    
    for (int i = 0; i < poly; ++i) {
        if (voices_[i].active.load(std::memory_order_acquire) &&
            voices_[i].note.load(std::memory_order_acquire) == note) {
            return i;
        }
    }
    return -1;
}

int MidiVoiceNode::getNumActiveVoices() const {
    int count = 0;
    const int poly = polyphony_.load(std::memory_order_acquire);
    for (int i = 0; i < poly; ++i) {
        if (voices_[i].active.load(std::memory_order_acquire)) {
            count++;
        }
    }
    return count;
}

} // namespace dsp_primitives
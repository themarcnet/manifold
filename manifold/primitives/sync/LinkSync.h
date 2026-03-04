#pragma once

#include <atomic>
#include <memory>
#include <mutex>

#include <juce_audio_basics/juce_audio_basics.h>

// Ableton Link includes - Link is header-only, must include before use
#include <ableton/Link.hpp>

struct LinkState {
    std::atomic<double> tempo{120.0};
    std::atomic<double> beat{0.0};
    std::atomic<double> phase{0.0};
    std::atomic<bool> isPlaying{false};
    std::atomic<int> numPeers{0};
    std::atomic<bool> isEnabled{false};
    std::atomic<bool> isTempoSyncEnabled{true};
    std::atomic<bool> isStartStopSyncEnabled{true};
    std::atomic<double> quantum{4.0};
};

class LinkSync {
public:
    LinkSync();
    ~LinkSync();

    void initialise(double sampleRate);
    void shutdown();

    bool processAudio(int numSamples);

    LinkState& getState() { return state; }
    const LinkState& getState() const { return state; }

    void setEnabled(bool enabled);
    void setTempoSyncEnabled(bool enabled);
    void setStartStopSyncEnabled(bool enabled);
    void setQuantum(double quantum);
    void requestTempo(double bpm);
    void processPendingRequests();
    void requestPlay();
    void requestStop();

    double getTempo() const { return state.tempo.load(std::memory_order_relaxed); }
    double getBeat() const { return state.beat.load(std::memory_order_relaxed); }
    double getPhase() const { return state.phase.load(std::memory_order_relaxed); }
    bool getIsPlaying() const { return state.isPlaying.load(std::memory_order_relaxed); }
    int getNumPeers() const { return state.numPeers.load(std::memory_order_relaxed); }
    bool isEnabled() const { return state.isEnabled.load(std::memory_order_relaxed); }
    double getQuantum() const { return state.quantum.load(std::memory_order_relaxed); }

    double samplesToBeats(double samples) const;
    double beatsToSamples(double beats) const;
    double getSamplesToNextBeat() const;
    double getSamplesToNextBar() const;

private:
    std::unique_ptr<ableton::Link> link;
    LinkState state;
    std::atomic<double> sampleRate_{44100.0};
    std::atomic<double> samplesSinceLastCallback_{0.0};
    std::mutex linkMutex;
    std::atomic<int> tempoChangeCooldown_{0};
    static constexpr int TEMPO_CHANGE_COOLDOWN_FRAMES = 20;
    std::atomic<double> pendingTempoRequest_{0.0};
    std::atomic<bool> hasPendingTempoRequest_{false};
    bool initialised_{false};
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LinkSync)
};

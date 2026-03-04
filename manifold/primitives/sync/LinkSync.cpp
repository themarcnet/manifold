#include "LinkSync.h"
#include <ableton/Link.hpp>
#include <ableton/platforms/Config.hpp>

static auto getHostTime() {
    return ableton::link::platform::Clock{}.micros();
}

LinkSync::LinkSync() = default;
LinkSync::~LinkSync() { shutdown(); }

void LinkSync::initialise(double sampleRate) {
    if (initialised_) return;
    sampleRate_.store(sampleRate > 0.0 ? sampleRate : 44100.0, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(linkMutex);
        link = std::make_unique<ableton::Link>(120.0);
        link->enableStartStopSync(true);
        link->enable(true);
    }
    state.tempo.store(120.0, std::memory_order_relaxed);
    state.beat.store(0.0, std::memory_order_relaxed);
    state.phase.store(0.0, std::memory_order_relaxed);
    state.isPlaying.store(false, std::memory_order_relaxed);
    state.numPeers.store(0, std::memory_order_relaxed);
    state.isEnabled.store(true, std::memory_order_relaxed);
    state.isTempoSyncEnabled.store(true, std::memory_order_relaxed);
    state.isStartStopSyncEnabled.store(true, std::memory_order_relaxed);
    state.quantum.store(4.0, std::memory_order_relaxed);
    initialised_ = true;
}

void LinkSync::shutdown() {
    if (!initialised_) return;
    {
        std::lock_guard<std::mutex> lock(linkMutex);
        if (link) link->enable(false);
        link.reset();
    }
    initialised_ = false;
}

bool LinkSync::processAudio(int numSamples) {
    if (!initialised_ || !link || !state.isEnabled.load(std::memory_order_relaxed)) {
        samplesSinceLastCallback_.store(0.0, std::memory_order_relaxed);
        return false;
    }
    const double sr = sampleRate_.load(std::memory_order_relaxed);
    if (sr <= 0.0) return false;
    const auto hostTime = getHostTime();
    bool tempoChanged = false;
    {
        std::lock_guard<std::mutex> lock(linkMutex);
        if (!link) return false;
        auto sessionState = link->captureAudioSessionState();
        const auto newPeers = static_cast<int>(link->numPeers());
        state.numPeers.store(newPeers, std::memory_order_relaxed);
        const double linkTempo = sessionState.tempo();
        const double currentTempo = state.tempo.load(std::memory_order_relaxed);
        int cooldown = tempoChangeCooldown_.load(std::memory_order_relaxed);
        if (cooldown > 0) {
            tempoChangeCooldown_.store(cooldown - 1, std::memory_order_relaxed);
        } else {
            if (std::abs(linkTempo - currentTempo) > 0.01) {
                if (state.isTempoSyncEnabled.load(std::memory_order_relaxed)) {
                    state.tempo.store(linkTempo, std::memory_order_relaxed);
                    tempoChanged = true;
                }
            }
        }
        const double quantum = state.quantum.load(std::memory_order_relaxed);
        const double beat = sessionState.beatAtTime(hostTime, quantum);
        const double phase = sessionState.phaseAtTime(hostTime, quantum);
        state.beat.store(beat, std::memory_order_relaxed);
        state.phase.store(phase, std::memory_order_relaxed);
        const bool isPlaying = sessionState.isPlaying();
        state.isPlaying.store(isPlaying, std::memory_order_relaxed);
    }
    samplesSinceLastCallback_.store(static_cast<double>(numSamples), std::memory_order_relaxed);
    return tempoChanged;
}

void LinkSync::setEnabled(bool enabled) {
    state.isEnabled.store(enabled, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(linkMutex);
    if (link) link->enable(enabled);
}

void LinkSync::setTempoSyncEnabled(bool enabled) {
    state.isTempoSyncEnabled.store(enabled, std::memory_order_relaxed);
}

void LinkSync::setStartStopSyncEnabled(bool enabled) {
    state.isStartStopSyncEnabled.store(enabled, std::memory_order_relaxed);
    std::lock_guard<std::mutex> lock(linkMutex);
    if (link) link->enableStartStopSync(enabled);
}

void LinkSync::setQuantum(double quantum) {
    state.quantum.store(std::max(1.0, quantum), std::memory_order_relaxed);
}

void LinkSync::requestTempo(double bpm) {
    if (!initialised_) return;
    const double clampedBpm = std::clamp(bpm, 20.0, 999.0);
    pendingTempoRequest_.store(clampedBpm, std::memory_order_relaxed);
    hasPendingTempoRequest_.store(true, std::memory_order_relaxed);
    tempoChangeCooldown_.store(TEMPO_CHANGE_COOLDOWN_FRAMES, std::memory_order_relaxed);
    state.tempo.store(clampedBpm, std::memory_order_relaxed);
}

void LinkSync::processPendingRequests() {
    if (!initialised_ || !link) return;
    if (hasPendingTempoRequest_.load(std::memory_order_relaxed)) {
        double bpm = pendingTempoRequest_.load(std::memory_order_relaxed);
        hasPendingTempoRequest_.store(false, std::memory_order_relaxed);
        std::lock_guard<std::mutex> lock(linkMutex);
        if (!link) return;
        auto sessionState = link->captureAppSessionState();
        sessionState.setTempo(bpm, getHostTime());
        link->commitAppSessionState(sessionState);
    }
}

void LinkSync::requestPlay() {
    if (!initialised_ || !link) return;
    if (!state.isStartStopSyncEnabled.load(std::memory_order_relaxed)) return;
    std::lock_guard<std::mutex> lock(linkMutex);
    if (!link) return;
    auto sessionState = link->captureAppSessionState();
    const double quantum = state.quantum.load(std::memory_order_relaxed);
    sessionState.requestBeatAtStartPlayingTime(0.0, quantum);
    link->commitAppSessionState(sessionState);
}

void LinkSync::requestStop() {
    if (!initialised_ || !link) return;
    if (!state.isStartStopSyncEnabled.load(std::memory_order_relaxed)) return;
    std::lock_guard<std::mutex> lock(linkMutex);
    if (!link) return;
    auto sessionState = link->captureAppSessionState();
    sessionState.setIsPlaying(false, getHostTime());
    link->commitAppSessionState(sessionState);
}

double LinkSync::samplesToBeats(double samples) const {
    const double sr = sampleRate_.load(std::memory_order_relaxed);
    const double tempo = state.tempo.load(std::memory_order_relaxed);
    if (sr <= 0.0 || tempo <= 0.0) return 0.0;
    return (samples / sr) * tempo / 60.0;
}

double LinkSync::beatsToSamples(double beats) const {
    const double sr = sampleRate_.load(std::memory_order_relaxed);
    const double tempo = state.tempo.load(std::memory_order_relaxed);
    if (sr <= 0.0 || tempo <= 0.0) return 0.0;
    return beats * 60.0 / tempo * sr;
}

double LinkSync::getSamplesToNextBeat() const {
    const double phase = state.phase.load(std::memory_order_relaxed);
    return beatsToSamples(1.0 - phase);
}

double LinkSync::getSamplesToNextBar() const {
    const double beat = state.beat.load(std::memory_order_relaxed);
    const double quantum = state.quantum.load(std::memory_order_relaxed);
    const double beatsInBar = std::fmod(beat, quantum);
    return beatsToSamples(quantum - beatsInBar);
}

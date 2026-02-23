#pragma once

#include <cmath>
#include <vector>
#include <limits>

struct TempoInferenceResult {
    float tempo;
    float numBars;
    float distance;
    bool valid;
};

class TempoInference {
public:
    TempoInference() {
        allowedBars = { 0.0625f, 0.125f, 0.25f, 0.5f, 1.0f, 2.0f, 3.0f, 4.0f, 6.0f, 8.0f, 12.0f, 16.0f };
    }
    
    void setAllowedBars(const std::vector<float>& bars) {
        allowedBars = bars;
    }
    
    void setAllow3612(bool allow) {
        allow3612 = allow;
    }
    
    TempoInferenceResult findBestMatch(double durationSeconds, float targetBPM, int timeSigTop = 4) {
        if (durationSeconds <= 0) {
            return { 0, 0, 0, false };
        }
        
        double minutes = durationSeconds / 60.0;
        float bestTempo = 0;
        float bestNumBars = 1;
        float bestDistance = std::numeric_limits<float>::max();
        bool found = false;
        
        for (float bars : allowedBars) {
            if (!allow3612) {
                if (std::abs(bars - 3.0f) < 0.001f ||
                    std::abs(bars - 6.0f) < 0.001f ||
                    std::abs(bars - 12.0f) < 0.001f) {
                    continue;
                }
            }
            
            float beats = bars * timeSigTop;
            float tempo = static_cast<float>(beats / minutes);
            float distance = std::abs(tempo - targetBPM);
            
            if (!found || distance < bestDistance - 0.0001f ||
                (std::abs(distance - bestDistance) <= 0.0001f && bars > bestNumBars)) {
                found = true;
                bestDistance = distance;
                bestNumBars = bars;
                bestTempo = tempo;
            }
        }
        
        return { bestTempo, bestNumBars, bestDistance, found };
    }
    
    float getSamplesPerBar(float bpm, int timeSigTop, double sampleRate) const {
        float beatsPerSecond = bpm / 60.0f;
        float samplesPerBeat = static_cast<float>(sampleRate / beatsPerSecond);
        return samplesPerBeat * timeSigTop;
    }
    
    float getSamplesForBars(float bars, float bpm, int timeSigTop, double sampleRate) const {
        return bars * getSamplesPerBar(bpm, timeSigTop, sampleRate);
    }
    
private:
    std::vector<float> allowedBars;
    bool allow3612 = true;
};

#pragma once

#include <cmath>
#include <vector>
#include <limits>

class Quantizer {
public:
    Quantizer() = default;
    
    void setTempo(float bpm) { this->bpm = bpm; }
    void setTimeSignature(int top, int bottom = 4) { 
        timeSigTop = top; 
        timeSigBottom = bottom;
    }
    void setSampleRate(double rate) { sampleRate = rate; }
    
    enum class Division {
        OneBar,
        Half,
        Quarter,
        Eighth,
        Sixteenth,
        Triplet,
        Dotted
    };
    
    void setAllowedDivisions(const std::vector<Division>& divs) {
        allowedDivisions = divs;
    }
    
    int quantizeToNearest(double positionSamples, Division division) const {
        int quantSize = getDivisionSamples(division);
        return static_cast<int>(std::round(positionSamples / quantSize)) * quantSize;
    }
    
    int quantizeUp(double positionSamples, Division division) const {
        int quantSize = getDivisionSamples(division);
        return static_cast<int>(std::ceil(positionSamples / quantSize)) * quantSize;
    }
    
    int quantizeDown(double positionSamples, Division division) const {
        int quantSize = getDivisionSamples(division);
        return static_cast<int>(std::floor(positionSamples / quantSize)) * quantSize;
    }
    
    Division findNearestDivision(double durationSamples) const {
        Division nearest = Division::OneBar;
        double minDistance = std::numeric_limits<double>::max();
        
        for (Division div : allowedDivisions) {
            double divSamples = getDivisionSamples(div);
            double remainder = std::fmod(durationSamples, divSamples);
            double distance = std::min(remainder, divSamples - remainder);
            
            if (distance < minDistance) {
                minDistance = distance;
                nearest = div;
            }
        }
        
        return nearest;
    }
    
    int quantizeToNearestLegal(double durationSamples) const {
        Division nearest = findNearestDivision(durationSamples);
        return quantizeToNearest(durationSamples, nearest);
    }
    
    int getDivisionSamples(Division division) const {
        double samplesPerBeat = sampleRate * 60.0 / bpm;
        double beatsPerBar = timeSigTop;
        
        switch (division) {
            case Division::OneBar: return static_cast<int>(samplesPerBeat * beatsPerBar);
            case Division::Half: return static_cast<int>(samplesPerBeat * beatsPerBar / 2);
            case Division::Quarter: return static_cast<int>(samplesPerBeat * beatsPerBar / 4);
            case Division::Eighth: return static_cast<int>(samplesPerBeat * beatsPerBar / 8);
            case Division::Sixteenth: return static_cast<int>(samplesPerBeat * beatsPerBar / 16);
            case Division::Triplet: return static_cast<int>(samplesPerBeat * beatsPerBar / 3);
            case Division::Dotted: return static_cast<int>(samplesPerBeat * beatsPerBar * 1.5);
        }
        return static_cast<int>(samplesPerBeat * beatsPerBar);
    }
    
    float getBPM() const { return bpm; }
    
private:
    float bpm = 120.0f;
    int timeSigTop = 4;
    int timeSigBottom = 4;
    double sampleRate = 44100.0;
    std::vector<Division> allowedDivisions = {
        Division::OneBar,
        Division::Half,
        Division::Quarter,
        Division::Eighth,
        Division::Sixteenth
    };
};

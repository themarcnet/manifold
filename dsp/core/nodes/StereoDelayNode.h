#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <atomic>
#include <memory>
#include <array>

namespace dsp_primitives {

class StereoDelayNode : public IPrimitiveNode,
                        public std::enable_shared_from_this<StereoDelayNode> {
public:
    enum class TimeMode {
        Free = 0,     // Time in milliseconds
        Synced        // Time in beat divisions
    };

    enum class Division {
        ThirtySecond = 0,
        Sixteenth,
        Eighth,
        Quarter,
        Half,
        Whole,
        DottedEighth,
        DottedQuarter,
        TripletSixteenth,
        TripletEighth,
        TripletQuarter,
        NumDivisions
    };

    StereoDelayNode();

    const char* getNodeType() const override { return "StereoDelay"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }
    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;

    // Time settings
    void setTimeMode(TimeMode mode);
    void setTimeL(float milliseconds);
    void setTimeR(float milliseconds);
    void setDivisionL(Division div);
    void setDivisionR(Division div);
    
    // Feedback and tone
    void setFeedback(float feedback);
    void setFeedbackCrossfeed(float crossfeed);
    void setFilterEnabled(bool enabled);
    void setFilterCutoff(float cutoff);
    void setFilterResonance(float resonance);
    
    // Mix and width
    void setMix(float wet);
    void setPingPong(bool enabled);
    void setWidth(float width);
    
    // Freeze/Ducking
    void setFreeze(bool enabled);
    void setDucking(float amount);
    
    // Getters
    TimeMode getTimeMode() const;
    float getTimeL() const;
    float getTimeR() const;
    Division getDivisionL() const;
    Division getDivisionR() const;
    float getFeedback() const;
    float getFeedbackCrossfeed() const;
    bool getFilterEnabled() const;
    float getFilterCutoff() const;
    float getFilterResonance() const;
    float getMix() const;
    bool getPingPong() const;
    float getWidth() const;
    bool getFreeze() const;
    float getDucking() const;

    void reset();
    void setTempo(float bpm);

private:
    void updateBufferSize();
    float divisionToSamples(Division div) const;
    void processFilter(float& sampleL, float& sampleR);
    
    struct ChannelState {
        float filterZ1 = 0.0f;
        float filterZ2 = 0.0f;
        float lastFeedback = 0.0f;
    };

    // Target parameters (atomic for thread-safe updates)
    std::atomic<TimeMode> timeMode_{TimeMode::Free};
    std::atomic<float> targetTimeL_{250.0f};
    std::atomic<float> targetTimeR_{375.0f};
    std::atomic<Division> divisionL_{Division::Quarter};
    std::atomic<Division> divisionR_{Division::DottedEighth};
    std::atomic<float> targetFeedback_{0.3f};
    std::atomic<float> targetFeedbackCrossfeed_{0.0f};
    std::atomic<bool> filterEnabled_{false};
    std::atomic<float> targetFilterCutoff_{4000.0f};
    std::atomic<float> targetFilterResonance_{0.5f};
    std::atomic<float> targetMix_{0.5f};
    std::atomic<bool> pingPong_{false};
    std::atomic<float> targetWidth_{1.0f};
    std::atomic<bool> freeze_{false};
    std::atomic<float> targetDucking_{0.0f};
    std::atomic<float> tempo_{120.0f};

    // Current smoothed parameters
    float currentTimeL_ = 250.0f;
    float currentTimeR_ = 375.0f;
    float currentFeedback_ = 0.3f;
    float currentFeedbackCrossfeed_ = 0.0f;
    float currentFilterCutoff_ = 4000.0f;
    float currentFilterResonance_ = 0.5f;
    float currentMix_ = 0.5f;
    float currentWidth_ = 1.0f;
    float currentDucking_ = 0.0f;

    // Smoothing coefficients
    float timeSmoothingCoeff_ = 1.0f;
    float feedbackSmoothingCoeff_ = 1.0f;
    float filterSmoothingCoeff_ = 1.0f;
    float mixSmoothingCoeff_ = 1.0f;
    float widthSmoothingCoeff_ = 1.0f;
    float duckingSmoothingCoeff_ = 1.0f;

    // Audio buffer
    juce::AudioBuffer<float> delayBuffer_;
    int writeIndex_ = 0;
    int bufferSize_ = 0;
    
    float readIndexL_ = 0.0f;
    float readIndexR_ = 0.0f;
    
    float filterG_ = 0.0f;
    float filterK_ = 0.0f;
    
    ChannelState stateL_;
    ChannelState stateR_;
    
    float duckEnvelope_ = 1.0f;
    static constexpr float kDuckAttack = 0.1f;
    static constexpr float kDuckRelease = 0.995f;
    
    double sampleRate_ = 44100.0;
    bool prepared_ = false;
    
    static constexpr float kMaxDelaySeconds = 5.0f;
    static constexpr int kMaxSamplesPerBlock = 8192;
};

} // namespace dsp_primitives

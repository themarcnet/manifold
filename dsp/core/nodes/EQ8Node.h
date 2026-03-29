#pragma once

#include "dsp/core/graph/PrimitiveNode.h"
#include <array>
#include <atomic>
#include <memory>

namespace dsp_primitives {

class EQ8Node : public IPrimitiveNode,
                public std::enable_shared_from_this<EQ8Node> {
public:
    static constexpr int kNumBands = 8;

    enum class BandType {
        Peak = 0,
        LowShelf = 1,
        HighShelf = 2,
        LowPass = 3,
        HighPass = 4,
        Notch = 5,
        BandPass = 6,
    };

    EQ8Node();

    const char* getNodeType() const override { return "EQ8"; }
    int getNumInputs() const override { return 2; }
    int getNumOutputs() const override { return 2; }

    void process(const std::vector<AudioBufferView>& inputs,
                 std::vector<WritableAudioBufferView>& outputs,
                 int numSamples) override;
    void prepare(double sampleRate, int maxBlockSize) override;
    void reset();

    void setBandEnabled(int band, bool enabled);
    void setBandType(int band, int type);
    void setBandFreq(int band, float hz);
    void setBandGain(int band, float db);
    void setBandQ(int band, float q);

    bool getBandEnabled(int band) const;
    int getBandType(int band) const;
    float getBandFreq(int band) const;
    float getBandGain(int band) const;
    float getBandQ(int band) const;

    void setOutput(float db) { targetOutputDb_.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release); }
    void setMix(float mix) { targetMix_.store(juce::jlimit(0.0f, 1.0f, mix), std::memory_order_release); }

    float getOutput() const { return targetOutputDb_.load(std::memory_order_acquire); }
    float getMix() const { return targetMix_.load(std::memory_order_acquire); }

private:
    struct Coeffs {
        float b0 = 1.0f;
        float b1 = 0.0f;
        float b2 = 0.0f;
        float a1 = 0.0f;
        float a2 = 0.0f;
    };

    struct State {
        float x1 = 0.0f;
        float x2 = 0.0f;
        float y1 = 0.0f;
        float y2 = 0.0f;
    };

    struct BandTarget {
        std::atomic<bool> enabled{false};
        std::atomic<int> type{static_cast<int>(BandType::Peak)};
        std::atomic<float> freqHz{1000.0f};
        std::atomic<float> gainDb{0.0f};
        std::atomic<float> q{1.0f};
    };

    struct BandRuntime {
        bool enabled = false;
        int type = static_cast<int>(BandType::Peak);
        float freqHz = 1000.0f;
        float gainDb = 0.0f;
        float q = 1.0f;
    };

    static int toIndex(int band);
    static Coeffs makePeak(float sr, float freq, float q, float gainDb);
    static Coeffs makeLowShelf(float sr, float freq, float gainDb);
    static Coeffs makeHighShelf(float sr, float freq, float gainDb);
    static Coeffs makeLowPass(float sr, float freq, float q);
    static Coeffs makeHighPass(float sr, float freq, float q);
    static Coeffs makeNotch(float sr, float freq, float q);
    static Coeffs makeBandPass(float sr, float freq, float q);
    static Coeffs makeBandCoeffs(float sr, const BandRuntime& band);
    static float processBiquad(float x, State& s, const Coeffs& c);
    void updateCoeffsForCurrentParams(bool force = false);

    std::array<BandTarget, kNumBands> targetBands_{};
    std::array<BandRuntime, kNumBands> bands_{};
    std::atomic<float> targetOutputDb_{0.0f};
    std::atomic<float> targetMix_{1.0f};

    float outputDb_ = 0.0f;
    float mix_ = 1.0f;
    float smooth_ = 1.0f;

    std::array<std::array<State, kNumBands>, 2> state_{};
    std::array<Coeffs, kNumBands> coeffs_{};
    std::array<BandRuntime, kNumBands> coeffBands_{};
    bool coeffsValid_ = false;

    double sampleRate_ = 44100.0;
    bool prepared_ = false;
};

} // namespace dsp_primitives

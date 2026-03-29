#include "dsp/core/nodes/EQ8Node.h"

#include <algorithm>
#include <cmath>

namespace dsp_primitives {

namespace {
constexpr std::array<float, EQ8Node::kNumBands> kDefaultFreqs = {
    60.0f, 120.0f, 250.0f, 500.0f, 1000.0f, 2500.0f, 6000.0f, 12000.0f
};
constexpr std::array<EQ8Node::BandType, EQ8Node::kNumBands> kDefaultTypes = {
    EQ8Node::BandType::LowShelf,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::Peak,
    EQ8Node::BandType::HighShelf,
};

inline void copyDryToOutput(const AudioBufferView& input,
                            WritableAudioBufferView& output,
                            int numSamples) {
    for (int i = 0; i < numSamples; ++i) {
        const float inL = input.getSample(0, i);
        const float inR = input.numChannels > 1 ? input.getSample(1, i) : inL;
        output.setSample(0, i, inL);
        if (output.numChannels > 1) {
            output.setSample(1, i, inR);
        }
    }
}

inline float clampFreq(float sr, float freq) {
    const float nyquistSafe = std::max(40.0f, std::min(20000.0f, sr * 0.45f));
    return juce::jlimit(20.0f, nyquistSafe, freq);
}

inline float safeQ(float q) {
    return juce::jlimit(0.1f, 24.0f, q);
}
} // namespace

EQ8Node::EQ8Node() {
    for (int i = 0; i < kNumBands; ++i) {
        targetBands_[static_cast<size_t>(i)].enabled.store(false, std::memory_order_release);
        targetBands_[static_cast<size_t>(i)].type.store(static_cast<int>(kDefaultTypes[static_cast<size_t>(i)]), std::memory_order_release);
        targetBands_[static_cast<size_t>(i)].freqHz.store(kDefaultFreqs[static_cast<size_t>(i)], std::memory_order_release);
        targetBands_[static_cast<size_t>(i)].gainDb.store(0.0f, std::memory_order_release);
        targetBands_[static_cast<size_t>(i)].q.store(1.0f, std::memory_order_release);

        bands_[static_cast<size_t>(i)].enabled = false;
        bands_[static_cast<size_t>(i)].type = static_cast<int>(kDefaultTypes[static_cast<size_t>(i)]);
        bands_[static_cast<size_t>(i)].freqHz = kDefaultFreqs[static_cast<size_t>(i)];
        bands_[static_cast<size_t>(i)].gainDb = 0.0f;
        bands_[static_cast<size_t>(i)].q = 1.0f;
    }
}

int EQ8Node::toIndex(int band) {
    if (band < 1 || band > kNumBands) {
        return -1;
    }
    return band - 1;
}

void EQ8Node::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;
    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    const double smoothTime = 0.01;
    smooth_ = static_cast<float>(1.0 - std::exp(-1.0 / (smoothTime * sampleRate_)));
    smooth_ = juce::jlimit(0.0001f, 1.0f, smooth_);

    for (int i = 0; i < kNumBands; ++i) {
        auto& band = bands_[static_cast<size_t>(i)];
        const auto& target = targetBands_[static_cast<size_t>(i)];
        band.enabled = target.enabled.load(std::memory_order_acquire);
        band.type = target.type.load(std::memory_order_acquire);
        band.freqHz = target.freqHz.load(std::memory_order_acquire);
        band.gainDb = target.gainDb.load(std::memory_order_acquire);
        band.q = target.q.load(std::memory_order_acquire);
    }
    outputDb_ = targetOutputDb_.load(std::memory_order_acquire);
    mix_ = targetMix_.load(std::memory_order_acquire);

    reset();
    updateCoeffsForCurrentParams(true);
    prepared_ = true;
}

void EQ8Node::reset() {
    for (auto& ch : state_) {
        for (auto& s : ch) {
            s = State{};
        }
    }
    coeffsValid_ = false;
}

void EQ8Node::updateCoeffsForCurrentParams(bool force) {
    constexpr float kFreqEpsilon = 0.5f;
    constexpr float kGainEpsilon = 0.02f;
    constexpr float kQEpsilon = 0.01f;

    for (int bandIdx = 0; bandIdx < kNumBands; ++bandIdx) {
        const auto& band = bands_[static_cast<size_t>(bandIdx)];
        const auto& cached = coeffBands_[static_cast<size_t>(bandIdx)];
        const bool closeEnough = band.enabled == cached.enabled
            && band.type == cached.type
            && std::abs(band.freqHz - cached.freqHz) <= kFreqEpsilon
            && std::abs(band.gainDb - cached.gainDb) <= kGainEpsilon
            && std::abs(band.q - cached.q) <= kQEpsilon;
        if (!force && coeffsValid_ && closeEnough) {
            continue;
        }
        coeffs_[static_cast<size_t>(bandIdx)] = makeBandCoeffs(static_cast<float>(sampleRate_), band);
        coeffBands_[static_cast<size_t>(bandIdx)] = band;
    }
    coeffsValid_ = true;
}

void EQ8Node::setBandEnabled(int band, bool enabled) {
    const int idx = toIndex(band);
    if (idx < 0) return;
    targetBands_[static_cast<size_t>(idx)].enabled.store(enabled, std::memory_order_release);
}

void EQ8Node::setBandType(int band, int type) {
    const int idx = toIndex(band);
    if (idx < 0) return;
    const int clampedType = juce::jlimit(0, static_cast<int>(BandType::BandPass), type);
    targetBands_[static_cast<size_t>(idx)].type.store(clampedType, std::memory_order_release);
}

void EQ8Node::setBandFreq(int band, float hz) {
    const int idx = toIndex(band);
    if (idx < 0) return;
    targetBands_[static_cast<size_t>(idx)].freqHz.store(juce::jlimit(20.0f, 20000.0f, hz), std::memory_order_release);
}

void EQ8Node::setBandGain(int band, float db) {
    const int idx = toIndex(band);
    if (idx < 0) return;
    targetBands_[static_cast<size_t>(idx)].gainDb.store(juce::jlimit(-24.0f, 24.0f, db), std::memory_order_release);
}

void EQ8Node::setBandQ(int band, float q) {
    const int idx = toIndex(band);
    if (idx < 0) return;
    targetBands_[static_cast<size_t>(idx)].q.store(safeQ(q), std::memory_order_release);
}

bool EQ8Node::getBandEnabled(int band) const {
    const int idx = toIndex(band);
    if (idx < 0) return false;
    return targetBands_[static_cast<size_t>(idx)].enabled.load(std::memory_order_acquire);
}

int EQ8Node::getBandType(int band) const {
    const int idx = toIndex(band);
    if (idx < 0) return static_cast<int>(BandType::Peak);
    return targetBands_[static_cast<size_t>(idx)].type.load(std::memory_order_acquire);
}

float EQ8Node::getBandFreq(int band) const {
    const int idx = toIndex(band);
    if (idx < 0) return 1000.0f;
    return targetBands_[static_cast<size_t>(idx)].freqHz.load(std::memory_order_acquire);
}

float EQ8Node::getBandGain(int band) const {
    const int idx = toIndex(band);
    if (idx < 0) return 0.0f;
    return targetBands_[static_cast<size_t>(idx)].gainDb.load(std::memory_order_acquire);
}

float EQ8Node::getBandQ(int band) const {
    const int idx = toIndex(band);
    if (idx < 0) return 1.0f;
    return targetBands_[static_cast<size_t>(idx)].q.load(std::memory_order_acquire);
}

EQ8Node::Coeffs EQ8Node::makePeak(float sr, float freq, float q, float gainDb) {
    const float f = clampFreq(sr, freq);
    const float Q = safeQ(q);
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);

    const float b0 = 1.0f + alpha * A;
    const float b1 = -2.0f * cosw0;
    const float b2 = 1.0f - alpha * A;
    const float a0 = 1.0f + alpha / A;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha / A;

    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeLowShelf(float sr, float freq, float gainDb) {
    const float f = clampFreq(sr, freq);
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float sinw0 = std::sin(w0);
    const float alpha = sinw0 / 2.0f * std::sqrt(A);

    const float b0 = A * ((A + 1.0f) - (A - 1.0f) * cosw0 + 2.0f * alpha);
    const float b1 = 2.0f * A * ((A - 1.0f) - (A + 1.0f) * cosw0);
    const float b2 = A * ((A + 1.0f) - (A - 1.0f) * cosw0 - 2.0f * alpha);
    const float a0 = (A + 1.0f) + (A - 1.0f) * cosw0 + 2.0f * alpha;
    const float a1 = -2.0f * ((A - 1.0f) + (A + 1.0f) * cosw0);
    const float a2 = (A + 1.0f) + (A - 1.0f) * cosw0 - 2.0f * alpha;

    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeHighShelf(float sr, float freq, float gainDb) {
    const float f = clampFreq(sr, freq);
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float sinw0 = std::sin(w0);
    const float alpha = sinw0 / 2.0f * std::sqrt(A);

    const float b0 = A * ((A + 1.0f) + (A - 1.0f) * cosw0 + 2.0f * alpha);
    const float b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cosw0);
    const float b2 = A * ((A + 1.0f) + (A - 1.0f) * cosw0 - 2.0f * alpha);
    const float a0 = (A + 1.0f) - (A - 1.0f) * cosw0 + 2.0f * alpha;
    const float a1 = 2.0f * ((A - 1.0f) - (A + 1.0f) * cosw0);
    const float a2 = (A + 1.0f) - (A - 1.0f) * cosw0 - 2.0f * alpha;

    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeLowPass(float sr, float freq, float q) {
    const float f = clampFreq(sr, freq);
    const float Q = safeQ(q);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);
    const float b0 = (1.0f - cosw0) * 0.5f;
    const float b1 = 1.0f - cosw0;
    const float b2 = (1.0f - cosw0) * 0.5f;
    const float a0 = 1.0f + alpha;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha;
    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeHighPass(float sr, float freq, float q) {
    const float f = clampFreq(sr, freq);
    const float Q = safeQ(q);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);
    const float b0 = (1.0f + cosw0) * 0.5f;
    const float b1 = -(1.0f + cosw0);
    const float b2 = (1.0f + cosw0) * 0.5f;
    const float a0 = 1.0f + alpha;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha;
    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeNotch(float sr, float freq, float q) {
    const float f = clampFreq(sr, freq);
    const float Q = safeQ(q);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);
    const float b0 = 1.0f;
    const float b1 = -2.0f * cosw0;
    const float b2 = 1.0f;
    const float a0 = 1.0f + alpha;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha;
    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeBandPass(float sr, float freq, float q) {
    const float f = clampFreq(sr, freq);
    const float Q = safeQ(q);
    const float w0 = 2.0f * juce::MathConstants<float>::pi * f / sr;
    const float cosw0 = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * Q);
    const float b0 = alpha;
    const float b1 = 0.0f;
    const float b2 = -alpha;
    const float a0 = 1.0f + alpha;
    const float a1 = -2.0f * cosw0;
    const float a2 = 1.0f - alpha;
    return { b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0 };
}

EQ8Node::Coeffs EQ8Node::makeBandCoeffs(float sr, const BandRuntime& band) {
    const auto type = static_cast<BandType>(juce::jlimit(0, static_cast<int>(BandType::BandPass), band.type));
    switch (type) {
        case BandType::LowShelf:  return makeLowShelf(sr, band.freqHz, band.gainDb);
        case BandType::HighShelf: return makeHighShelf(sr, band.freqHz, band.gainDb);
        case BandType::LowPass:   return makeLowPass(sr, band.freqHz, band.q);
        case BandType::HighPass:  return makeHighPass(sr, band.freqHz, band.q);
        case BandType::Notch:     return makeNotch(sr, band.freqHz, band.q);
        case BandType::BandPass:  return makeBandPass(sr, band.freqHz, band.q);
        case BandType::Peak:
        default:                  return makePeak(sr, band.freqHz, band.q, band.gainDb);
    }
}

float EQ8Node::processBiquad(float x, State& s, const Coeffs& c) {
    const float y = c.b0 * x + c.b1 * s.x1 + c.b2 * s.x2 - c.a1 * s.y1 - c.a2 * s.y2;
    s.x2 = s.x1;
    s.x1 = x;
    s.y2 = s.y1;
    s.y1 = y;
    return y;
}

void EQ8Node::process(const std::vector<AudioBufferView>& inputs,
                      std::vector<WritableAudioBufferView>& outputs,
                      int numSamples) {
    if (!prepared_ || inputs.empty() || outputs.empty() || numSamples <= 0) {
        if (!outputs.empty()) {
            outputs[0].clear();
        }
        return;
    }

    std::array<bool, kNumBands> targetEnabled{};
    std::array<int, kNumBands> targetType{};
    std::array<float, kNumBands> targetFreq{};
    std::array<float, kNumBands> targetGain{};
    std::array<float, kNumBands> targetQ{};
    for (int i = 0; i < kNumBands; ++i) {
        const auto& target = targetBands_[static_cast<size_t>(i)];
        targetEnabled[static_cast<size_t>(i)] = target.enabled.load(std::memory_order_acquire);
        targetType[static_cast<size_t>(i)] = target.type.load(std::memory_order_acquire);
        targetFreq[static_cast<size_t>(i)] = target.freqHz.load(std::memory_order_acquire);
        targetGain[static_cast<size_t>(i)] = target.gainDb.load(std::memory_order_acquire);
        targetQ[static_cast<size_t>(i)] = target.q.load(std::memory_order_acquire);
    }
    const float tOut = targetOutputDb_.load(std::memory_order_acquire);
    const float tMix = targetMix_.load(std::memory_order_acquire);

    if (tMix <= 1.0e-4f && mix_ <= 1.0e-4f) {
        copyDryToOutput(inputs[0], outputs[0], numSamples);
        return;
    }

    for (int i = 0; i < numSamples; ++i) {
        for (int bandIdx = 0; bandIdx < kNumBands; ++bandIdx) {
            auto& band = bands_[static_cast<size_t>(bandIdx)];
            band.enabled = targetEnabled[static_cast<size_t>(bandIdx)];
            band.type = targetType[static_cast<size_t>(bandIdx)];
            band.freqHz += (targetFreq[static_cast<size_t>(bandIdx)] - band.freqHz) * smooth_;
            band.gainDb += (targetGain[static_cast<size_t>(bandIdx)] - band.gainDb) * smooth_;
            band.q += (targetQ[static_cast<size_t>(bandIdx)] - band.q) * smooth_;
        }
        outputDb_ += (tOut - outputDb_) * smooth_;
        mix_ += (tMix - mix_) * smooth_;

        updateCoeffsForCurrentParams();
        const float outGain = std::pow(10.0f, outputDb_ / 20.0f);

        const float inL = inputs[0].getSample(0, i);
        const float inR = inputs[0].numChannels > 1 ? inputs[0].getSample(1, i) : inL;

        float outL = inL;
        float outR = inR;

        for (int ch = 0; ch < 2; ++ch) {
            const float dry = ch == 0 ? inL : inR;
            float x = dry;
            for (int bandIdx = 0; bandIdx < kNumBands; ++bandIdx) {
                if (!bands_[static_cast<size_t>(bandIdx)].enabled) {
                    continue;
                }
                x = processBiquad(x, state_[static_cast<size_t>(ch)][static_cast<size_t>(bandIdx)], coeffs_[static_cast<size_t>(bandIdx)]);
            }
            x *= outGain;
            const float out = dry * (1.0f - mix_) + x * mix_;
            if (ch == 0) outL = out;
            else outR = out;
        }

        outputs[0].setSample(0, i, outL);
        if (outputs[0].numChannels > 1) {
            outputs[0].setSample(1, i, outR);
        }
    }
}

} // namespace dsp_primitives

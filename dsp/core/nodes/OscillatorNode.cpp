
#define _USE_MATH_DEFINES
#include "dsp/core/nodes/OscillatorNode.h"

#include "dsp/core/nodes/OscillatorNode_Highway.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <mutex>
#include <unordered_map>



#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace dsp_primitives {

namespace {
constexpr int kMaxAdditiveHarmonics = 12;
constexpr double kTwoPi = 2.0 * M_PI;   

constexpr std::size_t toIndex(int value) noexcept {
    return static_cast<std::size_t>(value);
}
constexpr int kWaveAddTableSize = 2048;
constexpr int kWaveAddBandCount = 20;
constexpr int kWaveAddQuantizeScale = 100;

struct WaveAddRecipeKey {
    int sampleRate = 44100;
    int waveform = 0;
    int partialCount = 8;
    int tiltQ = 0;
    int driftQ = 0;
    int pulseWidthQ = 50;

    bool operator==(const WaveAddRecipeKey& other) const {
        return sampleRate == other.sampleRate
            && waveform == other.waveform
            && partialCount == other.partialCount
            && tiltQ == other.tiltQ
            && driftQ == other.driftQ
            && pulseWidthQ == other.pulseWidthQ;
    }
};

struct WaveAddRecipeKeyHasher {
    std::size_t operator()(const WaveAddRecipeKey& key) const noexcept {
        std::size_t hash = 1469598103934665603ull;
        auto mix = [&hash](std::uint64_t value) {
            hash ^= static_cast<std::size_t>(value);
            hash *= 1099511628211ull;
        };
        mix(static_cast<std::uint64_t>(key.sampleRate));
        mix(static_cast<std::uint64_t>(key.waveform));
        mix(static_cast<std::uint64_t>(key.partialCount));
        mix(static_cast<std::uint64_t>(key.tiltQ));
        mix(static_cast<std::uint64_t>(key.driftQ));
        mix(static_cast<std::uint64_t>(key.pulseWidthQ));
        return hash;
    }
};

std::mutex gWaveAddTableCacheMutex;
std::unordered_map<WaveAddRecipeKey, std::weak_ptr<const WaveAddTableSet>, WaveAddRecipeKeyHasher> gWaveAddTableCache;

inline int quantizeWaveAddValue(float value, float minimum, float maximum) {
    const float clamped = juce::jlimit(minimum, maximum, value);
    return static_cast<int>(std::lround(clamped * static_cast<float>(kWaveAddQuantizeScale)));
}

inline float dequantizeWaveAddValue(int value) {
    return static_cast<float>(value) / static_cast<float>(kWaveAddQuantizeScale);
}

inline WaveAddRecipeKey makeWaveAddRecipeKey(int waveform,
                                             int partialCount,
                                             float tilt,
                                             float drift,
                                             float pulseWidth,
                                             double sampleRate) {
    WaveAddRecipeKey key;
    key.sampleRate = static_cast<int>(std::lround(sampleRate > 1.0 ? sampleRate : 44100.0));
    key.waveform = juce::jlimit(0, 7, waveform);
    key.partialCount = juce::jlimit(1, kMaxAdditiveHarmonics, partialCount);
    key.tiltQ = quantizeWaveAddValue(tilt, -1.0f, 1.0f);
    key.driftQ = quantizeWaveAddValue(drift, 0.0f, 1.0f);
    key.pulseWidthQ = quantizeWaveAddValue(pulseWidth, 0.01f, 0.99f);
    return key;
}

inline int waveAddBandIndexForFrequency(float frequency, double sampleRate) {
    const float safeFrequency = std::max(1.0f, std::abs(frequency));
    const float maxRatio = std::max(1.0f, static_cast<float>((sampleRate * 0.475) / safeFrequency));
    const int ratioBucket = static_cast<int>(std::floor(std::min(maxRatio, static_cast<float>(kWaveAddBandCount))));
    return juce::jlimit(0, kWaveAddBandCount - 1, ratioBucket - 1);
}

float lookupWaveAddSampleInternal(const WaveAddTableSet& tableSet, float phaseNorm, int bandIndex) {
    const float wrappedPhase = [] (float phase) {
        const float wrapped = std::fmod(phase, 1.0f);
        return wrapped < 0.0f ? wrapped + 1.0f : wrapped;
    }(phaseNorm);
    const float position = wrappedPhase * static_cast<float>(kWaveAddTableSize);
    const int index = juce::jlimit(0, kWaveAddTableSize - 1, static_cast<int>(position));
    const float frac = position - static_cast<float>(index);
    const auto& band = tableSet.bands[static_cast<std::size_t>(juce::jlimit(0, kWaveAddBandCount - 1, bandIndex))];
    const float a = band[static_cast<std::size_t>(index)];
    const float b = band[static_cast<std::size_t>(index + 1)];
    return a + (b - a) * frac;
}

inline float foldToUnit(float x) {
    x = juce::jlimit(-32.0f, 32.0f, x);
    while (x > 1.0f || x < -1.0f) {
        if (x > 1.0f) {
            x = 2.0f - x;
        } else {
            x = -2.0f - x;
        }
    }
    return x;
}

inline float applyDriveTransfer(float sample, float drive, int shape) {
    const float drv = juce::jlimit(0.0f, 20.0f, drive);
    if (drv <= 0.0001f) {
        return juce::jlimit(-1.0f, 1.0f, sample);
    }

    switch (juce::jlimit(0, 3, shape)) {
        case 1: {
            const float gain = 1.0f + drv * 1.35f;
            const float normaliser = std::atan(gain);
            
            if (normaliser <= 1.0e-6f) {
                return juce::jlimit(-1.0f, 1.0f, sample);
            }

            float ret = std::atan(sample * gain) / normaliser; 
            return  ret;
        }
        case 2: {
            const float gain = 1.0f + drv * 1.2f;
            return juce::jlimit(-1.0f, 1.0f, sample * gain);
        }
        case 3: {
            const float gain = 1.0f + drv * 1.1f;
            return foldToUnit(sample * gain);
        }
        case 0:
        default: {
            const float gain = 1.0f + drv * 0.85f;
            const float normaliser = std::tanh(gain);
            if (normaliser <= 1.0e-6f) {
                return juce::jlimit(-1.0f, 1.0f, sample);
            }
            return std::tanh(sample * gain) / normaliser;
        }
    }
}

inline float applyDriveShape(float sample, float drive, int shape, float bias, float mix) {
    const float drv = juce::jlimit(0.0f, 20.0f, drive);
    const float wetMix = juce::jlimit(0.0f, 1.0f, mix);
    if (drv <= 0.0001f || wetMix <= 0.0001f) {
        return juce::jlimit(-1.0f, 1.0f, sample);
    }

    const float biasOffset = juce::jlimit(-1.0f, 1.0f, bias) * 0.75f;
    const float center = applyDriveTransfer(biasOffset, drv, shape);
    const float pos = std::abs(applyDriveTransfer(1.0f + biasOffset, drv, shape) - center);
    const float neg = std::abs(applyDriveTransfer(-1.0f + biasOffset, drv, shape) - center);
    const float normaliser = std::max(1.0e-6f, std::max(pos, neg));
    const float shaped = (applyDriveTransfer(sample + biasOffset, drv, shape) - center) / normaliser;
    const float wet = juce::jlimit(-1.0f, 1.0f, shaped);

    return juce::jlimit(-1.0f, 1.0f, sample + (wet - sample) * wetMix);
}

inline float wrapPhase01(float phase) {
    const float wrapped = std::fmod(phase, 1.0f);
    return wrapped < 0.0f ? wrapped + 1.0f : wrapped;
}

inline int additiveHarmonicLimit(float frequency, double sampleRate) {
    const double safeFreq = std::max(1.0, std::abs(static_cast<double>(frequency)));
    const int nyquistLimited = static_cast<int>(std::floor((sampleRate * 0.475) / safeFreq));
    return juce::jlimit(1, kMaxAdditiveHarmonics, nyquistLimited);
}

inline float additiveOutputTrim(int waveform) {
    switch (waveform) {
        case 1: return 0.96f; // saw
        case 2: return 0.98f; // square
        case 3: return 1.06f; // triangle
        case 4: return 0.94f; // blend
        case 5: return 0.78f; // noise cloud
        case 6: return 1.00f; // pulse
        case 7: return 0.84f; // supersaw
        case 0:
        default:
            return 1.0f;
    }
}

struct AdditiveShapeControls {
    int partialCount = 8;
    float tilt = 0.0f;
    float drift = 0.0f;
    int waveform = 0;
};

inline void addShapedPartialSample(float phaseNorm,
                                   double ratio,
                                   float amplitude,
                                   double phaseOffset,
                                   const AdditiveShapeControls& controls,
                                   float& sum,
                                   float& amplitudeSum) {
    if (amplitude <= 1.0e-6f) {
        return;
    }

    const double safeRatio = std::max(0.1, ratio);
    const float tilt = juce::jlimit(-1.0f, 1.0f, controls.tilt);
    const float drift = juce::jlimit(0.0f, 1.0f, controls.drift);
    const float tiltScale = std::max(0.12f, std::pow(static_cast<float>(safeRatio), tilt * 0.85f));
    const double ratioJitter = std::sin(safeRatio * 2.173 + static_cast<double>(controls.waveform) * 0.53);
    const double phaseJitter = std::sin(safeRatio * 1.618 + static_cast<double>(controls.waveform) * 0.37);
    const double driftRatio = 1.0 + ratioJitter * static_cast<double>(drift) * 0.035 * (1.0 + safeRatio * 0.05);
    const double shapedRatio = std::max(0.1, safeRatio * driftRatio);
    const double shapedPhase = phaseOffset + phaseJitter * static_cast<double>(drift) * 0.85;
    const float shapedAmplitude = amplitude * tiltScale;

    sum += static_cast<float>(std::sin(kTwoPi * static_cast<double>(phaseNorm) * shapedRatio + shapedPhase)) * shapedAmplitude;
    amplitudeSum += shapedAmplitude;
}

inline float standardWaveformSample(int waveform, float voicePhase, float pulseWidthPhase, 
                                    size_t smpnum, Debug::Logger & log) {
    const float phaseNorm = voicePhase / static_cast<float>(kTwoPi);
    const float sine = static_cast<float>(std::sin(voicePhase));
    const float saw = 2.0f * phaseNorm - 1.0f;
    const float square = (voicePhase < juce::MathConstants<double>::pi) ? 1.0f : -1.0f;
    const float triangle = 1.0f - 4.0f * std::abs(phaseNorm - 0.5f);

    switch (waveform) {
        case 1: 
            DEBUG_LOG_VALUE(log, smpnum, "Saw", saw);
            return saw;
        case 2: return square;
        case 3: 
            DEBUG_LOG_VALUE(log, smpnum, "Triangle", triangle);
            return triangle;
        case 4: 
            DEBUG_LOG_VALUE(log, smpnum, "Saw", saw);
            DEBUG_LOG_VALUE(log, smpnum, "Sine", sine);
            DEBUG_LOG_VALUE(log, smpnum, "Sine+Saw", 0.45f * sine + 0.55f * saw);
            return 0.45f * sine + 0.55f * saw;
        case 5: return (static_cast<float>(std::rand()) / RAND_MAX) * 2.0f - 1.0f;
        case 6: return (voicePhase < pulseWidthPhase) ? 1.0f : -1.0f;
        case 7: {
            const float s1 = saw;
            const float s2 = 2.0f * std::fmod(phaseNorm * 1.01f, 1.0f) - 1.0f;
            const float s3 = 2.0f * std::fmod(phaseNorm * 0.99f, 1.0f) - 1.0f;
            return (s1 + s2 * 0.5f + s3 * 0.5f) * 0.5f;
        }
        case 0:
        default:
            return sine;
    }
}

inline float additiveSawSample(float phaseNorm, int harmonicLimit, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
    for (int harmonic = 1; harmonic <= partialCount; ++harmonic) {
        const bool negative = (harmonic % 2) == 0;
        addShapedPartialSample(phaseNorm,
                               static_cast<double>(harmonic),
                               1.0f / static_cast<float>(harmonic),
                               negative ? M_PI : 0.0,
                               controls,    
                               sum,
                               amplitudeSum);
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additiveSquareSample(float phaseNorm, int harmonicLimit, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    const int partialCount = juce::jlimit(1, kMaxAdditiveHarmonics, controls.partialCount);
    int added = 0;
    for (int harmonic = 1; harmonic <= harmonicLimit && added < partialCount; harmonic += 2, ++added) {
        addShapedPartialSample(phaseNorm,
                               static_cast<double>(harmonic),
                               1.0f / static_cast<float>(harmonic),
                               0.0,
                               controls,
                               sum,
                               amplitudeSum);
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additiveTriangleSample(float phaseNorm, int harmonicLimit, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    const int partialCount = juce::jlimit(1, kMaxAdditiveHarmonics, controls.partialCount);
    int added = 0;
    for (int harmonic = 1; harmonic <= harmonicLimit && added < partialCount; harmonic += 2, ++added) {
        const bool positiveCosine = ((harmonic / 2) % 2) == 1;
        addShapedPartialSample(phaseNorm,
                               static_cast<double>(harmonic),
                               1.0f / static_cast<float>(harmonic * harmonic),
                               positiveCosine ? (M_PI * 0.5) : (-M_PI * 0.5),
                               controls,
                               sum,
                               amplitudeSum);
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additiveBlendSample(float phaseNorm, int harmonicLimit, const AdditiveShapeControls& controls) {
    const float sine = std::sin(kTwoPi * static_cast<double>(phaseNorm));
    const float saw = additiveSawSample(phaseNorm, harmonicLimit, controls);
    return juce::jlimit(-1.0f, 1.0f, sine * 0.45f + saw * 0.55f);
}

inline float additiveNoiseSample(float phaseNorm, float maxRatio, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    int added = 0;
    for (const auto& partial : constants::kNoiseCloud) {
        if (partial.ratio > static_cast<double>(maxRatio) || added >= controls.partialCount) {
            continue;
        }
        addShapedPartialSample(phaseNorm,
                               partial.ratio,
                               partial.amplitude,
                               partial.phaseOffset,
                               controls,
                               sum,
                               amplitudeSum);
        ++added;
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additivePulseSample(float phaseNorm, int harmonicLimit, float pulseWidth, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    const float width = juce::jlimit(0.01f, 0.99f, pulseWidth);
    const int partialCount = juce::jlimit(1, harmonicLimit, controls.partialCount);
    for (int harmonic = 1; harmonic <= partialCount; ++harmonic) {
        const float coeff = std::sin(static_cast<float>(M_PI) * static_cast<float>(harmonic) * width);
        addShapedPartialSample(phaseNorm,
                               static_cast<double>(harmonic),
                               std::abs(coeff) / static_cast<float>(harmonic),
                               coeff < 0.0f ? M_PI : 0.0,
                               controls,
                               sum,
                               amplitudeSum);
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additiveSuperSawSampleFromRatioLimit(float phaseNorm, float maxRatio, const AdditiveShapeControls& controls) {
    float sum = 0.0f;
    float amplitudeSum = 0.0f;
    const int layerLimit = juce::jlimit(1, static_cast<int>(constants::kSuperSawLayers.size()), controls.partialCount);
    for (int layerIndex = 0; layerIndex < layerLimit; ++layerIndex) {
        const auto& layer = constants::kSuperSawLayers[static_cast<std::size_t>(layerIndex)];
        const double detuneRatio = std::pow(2.0, static_cast<double>(layer.detuneCents) / 1200.0);
        const float layerRatioLimit = std::max(1.0f, maxRatio / static_cast<float>(detuneRatio));
        const int harmonicLimit = juce::jlimit(1, kMaxAdditiveHarmonics, static_cast<int>(std::floor(layerRatioLimit)));
        const float layerPhase = wrapPhase01(phaseNorm * static_cast<float>(detuneRatio)
                                             + static_cast<float>(layer.phaseOffset / kTwoPi));
        const float sample = additiveSawSample(layerPhase, harmonicLimit, controls);
        sum += sample * layer.gain;
        amplitudeSum += layer.gain;
    }
    return amplitudeSum > 1.0e-6f ? sum / amplitudeSum : 0.0f;
}

inline float additiveRecipeSampleFromRatioLimit(int waveform,
                                                float phaseNorm,
                                                float maxRatio,
                                                float pulseWidth,
                                                const AdditiveShapeControls& controls) {
    const int harmonicLimit = juce::jlimit(1, kMaxAdditiveHarmonics, static_cast<int>(std::floor(std::max(1.0f, maxRatio))));

    float sample = 0.0f;
    switch (waveform) {
        case 0:
            sample = static_cast<float>(std::sin(kTwoPi * static_cast<double>(phaseNorm)));
            break;
        case 1:
            sample = additiveSawSample(phaseNorm, harmonicLimit, controls);
            break;
        case 2:
            sample = additiveSquareSample(phaseNorm, harmonicLimit, controls);
            break;
        case 3:
            sample = additiveTriangleSample(phaseNorm, harmonicLimit, controls);
            break;
        case 4:
            sample = additiveBlendSample(phaseNorm, harmonicLimit, controls);
            break;
        case 5:
            sample = additiveNoiseSample(phaseNorm, maxRatio, controls);
            break;
        case 6:
            sample = additivePulseSample(phaseNorm, harmonicLimit, pulseWidth, controls);
            break;
        case 7:
            sample = additiveSuperSawSampleFromRatioLimit(phaseNorm, maxRatio, controls);
            break;
        default:
            sample = static_cast<float>(std::sin(kTwoPi * static_cast<double>(phaseNorm)));
            break;
    }

    const float tiltComp = 1.0f + juce::jlimit(-0.12f, 0.10f, controls.tilt * -0.10f);
    const float driftComp = 1.0f - controls.drift * 0.08f;
    return juce::jlimit(-1.0f, 1.0f, sample * additiveOutputTrim(waveform) * tiltComp * driftComp);
}

inline float additiveRecipeSample(int waveform,
                                  float phaseNorm,
                                  float baseFrequency,
                                  double sampleRate,
                                  float pulseWidth,
                                  int partialCount,
                                  float tilt,
                                  float drift) {
    const float maxRatio = std::max(1.0f, static_cast<float>((sampleRate * 0.475) / std::max(1.0f, std::abs(baseFrequency))));
    const AdditiveShapeControls controls {
        juce::jlimit(1, kMaxAdditiveHarmonics, partialCount),
        juce::jlimit(-1.0f, 1.0f, tilt),
        juce::jlimit(0.0f, 1.0f, drift),
        waveform,
    };
    return additiveRecipeSampleFromRatioLimit(waveform, phaseNorm, maxRatio, pulseWidth, controls);
}

std::shared_ptr<const WaveAddTableSet> buildWaveAddTableSet(const WaveAddRecipeKey& key) {
    auto tableSet = std::make_shared<WaveAddTableSet>();

    const AdditiveShapeControls controls {
        juce::jlimit(1, kMaxAdditiveHarmonics, key.partialCount),
        juce::jlimit(-1.0f, 1.0f, dequantizeWaveAddValue(key.tiltQ)),
        juce::jlimit(0.0f, 1.0f, dequantizeWaveAddValue(key.driftQ)),
        key.waveform,
    };
    const float pulseWidth = juce::jlimit(0.01f, 0.99f, dequantizeWaveAddValue(key.pulseWidthQ));

    for (int bandIndex = 0; bandIndex < kWaveAddBandCount; ++bandIndex) {
        const float maxRatio = static_cast<float>(bandIndex + 1);
        auto& band = tableSet->bands[static_cast<std::size_t>(bandIndex)];
        for (int sampleIndex = 0; sampleIndex < kWaveAddTableSize; ++sampleIndex) {
            const float phaseNorm = static_cast<float>(sampleIndex) / static_cast<float>(kWaveAddTableSize);
            band[static_cast<std::size_t>(sampleIndex)] = additiveRecipeSampleFromRatioLimit(key.waveform,
                                                                                            phaseNorm,
                                                                                            maxRatio,
                                                                                            pulseWidth,
                                                                                            controls);
        }
        band[static_cast<std::size_t>(kWaveAddTableSize)] = band[0];
    }

    return tableSet;
}

std::shared_ptr<const WaveAddTableSet> getOrCreateWaveAddTableSet(const WaveAddRecipeKey& key) {
    {
        const std::lock_guard<std::mutex> lock(gWaveAddTableCacheMutex);
        const auto found = gWaveAddTableCache.find(key);
        if (found != gWaveAddTableCache.end()) {
            if (auto cached = found->second.lock()) {
                return cached;
            }
        }
    }

    auto fresh = buildWaveAddTableSet(key);

    const std::lock_guard<std::mutex> lock(gWaveAddTableCacheMutex);
    const auto found = gWaveAddTableCache.find(key);
    if (found != gWaveAddTableCache.end()) {
        if (auto cached = found->second.lock()) {
            return cached;
        }
        found->second = fresh;
        return fresh;
    }

    for (auto it = gWaveAddTableCache.begin(); it != gWaveAddTableCache.end(); ) {
        if (it->second.expired()) {
            it = gWaveAddTableCache.erase(it);
        } else {
            ++it;
        }
    }
    gWaveAddTableCache.emplace(key, fresh);
    return fresh;
}
} // namespace

float lookupWaveAddSample(const WaveAddTableSet& tableSet, float phaseNorm, int bandIndex) {
    return lookupWaveAddSampleInternal(tableSet, phaseNorm, bandIndex);
}

OscillatorNode::OscillatorNode(int simdTgt) : simdTarget_(simdTgt)
{
    refreshWaveAddTableSet();  
}

void OscillatorNode::setFrequency(float freq) {
    targetFrequency_.store(juce::jlimit(1.0f, 20000.0f, freq), std::memory_order_release);
    notifyConfigChangeSimdImplementation(false);
}

void OscillatorNode::refreshWaveAddTableSet() {
    const auto key = makeWaveAddRecipeKey(waveform_.load(std::memory_order_acquire),
                                          additivePartials_.load(std::memory_order_acquire),
                                          additiveTilt_.load(std::memory_order_acquire),
                                          additiveDrift_.load(std::memory_order_acquire),
                                          pulseWidth_.load(std::memory_order_acquire),
                                          sampleRate_);
    auto tableSet = getOrCreateWaveAddTableSet(key);
    std::atomic_store_explicit(&waveAddTableSet_, std::move(tableSet), std::memory_order_release);
}

void OscillatorNode::setWaveform(int shape) {
    waveform_.store(juce::jlimit(0, 7, shape), std::memory_order_release);
    refreshWaveAddTableSet();
    notifyConfigChangeSimdImplementation(true);
}

void OscillatorNode::setAdditivePartials(int count) {
    additivePartials_.store(juce::jlimit(1, 12, count), std::memory_order_release);
    refreshWaveAddTableSet();
}

void OscillatorNode::setAdditiveTilt(float tilt) {
    additiveTilt_.store(juce::jlimit(-1.0f, 1.0f, tilt), std::memory_order_release);
    refreshWaveAddTableSet();
    notifyConfigChangeSimdImplementation(true);
}

void OscillatorNode::setAdditiveDrift(float drift) {
    additiveDrift_.store(juce::jlimit(0.0f, 1.0f, drift), std::memory_order_release);
    refreshWaveAddTableSet();
    notifyConfigChangeSimdImplementation(true);
}

void OscillatorNode::setPulseWidth(float width) {
    pulseWidth_.store(juce::jlimit(0.01f, 0.99f, width), std::memory_order_release);
    refreshWaveAddTableSet();
    notifyConfigChangeSimdImplementation(true);
}

void OscillatorNode::setUnison(int voices) {
    unisonVoices_.store(juce::jlimit(1, 8, voices), std::memory_order_release);
    notifyConfigChangeSimdImplementation(true);
}

void OscillatorNode::resetPhase() {
    phase_ = 0.0;
    for (auto& p : unisonPhases_) p = 0.0;
    unisonVoiceGains_[0] = 1.0f;
    for (int i = 1; i < 8; ++i) {
        unisonVoiceGains_[toIndex(i)] = 0.0f;
    }
    lastRequestedUnison_ = 1;
    if (simd_implementation_) {
        simd_implementation_->resetPhase();
    }
}

const char * OscillatorNode::getHighwayImplementationTargetName() const
{
    if(simd_implementation_.get() == NULL)
        return NULL;

    return simd_implementation_->targetName();
}


void OscillatorNode::notifyConfigChangeSimdImplementation(bool refreshWaveAddTableSet)
{
    if(simd_implementation_ != NULL)
    {
        simd_implementation_->configChanged();

        if(refreshWaveAddTableSet)
            simd_implementation_->refreshWaveAddTableSet();
    }
}

void OscillatorNode::prepare(double sampleRate, int maxBlockSize)
{
    (void)maxBlockSize;

    sampleRate_ = sampleRate > 1.0 ? sampleRate : 44100.0;

    
    const double freqTimeSeconds = 0.02;
    const double ampTimeSeconds = 0.01;
    const double renderTimeSeconds = 0.008;
    const double detuneTimeSeconds = 0.012;
    const double spreadTimeSeconds = 0.012;
    const double unisonVoiceTimeSeconds = 0.008;
    freqSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (freqTimeSeconds * sampleRate_)));
    ampSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (ampTimeSeconds * sampleRate_)));
    renderMixSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (renderTimeSeconds * sampleRate_)));
    detuneSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (detuneTimeSeconds * sampleRate_)));
    spreadSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (spreadTimeSeconds * sampleRate_)));
    unisonVoiceSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (unisonVoiceTimeSeconds * sampleRate_)));
    freqSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, freqSmoothingCoeff_);
    ampSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, ampSmoothingCoeff_);
    renderMixSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, renderMixSmoothingCoeff_);
    detuneSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, detuneSmoothingCoeff_);
    spreadSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, spreadSmoothingCoeff_);
    unisonVoiceSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, unisonVoiceSmoothingCoeff_);

    currentFrequency_ = targetFrequency_.load(std::memory_order_acquire);
    currentAmplitude_ = targetAmplitude_.load(std::memory_order_acquire);
    currentRenderMix_ = renderMode_.load(std::memory_order_acquire) == 1 ? 1.0f : 0.0f;
    currentDetuneCents_ = detuneCents_.load(std::memory_order_acquire);
    currentSpread_ = stereoSpread_.load(std::memory_order_acquire);
    refreshWaveAddTableSet();
    resetPhase();

    //Set up SIMD implementation according to simdTarget_
    //  0 = automatic
    //  -1 = disabled
    if((simd_implementation_ == NULL) && (simdTarget_ >= 0))
    {
        hwy::RunHighwayErrorCode errCode = hwy::RunHighwayErrorCode_Error;

        simd_implementation_.reset(OscillatorNode_Highway::__CreateInstance(simdTarget_,
                                                                            static_cast<float>(sampleRate),
                                                                            &targetFrequency_,
                                                                            &targetAmplitude_,
                                                                            &waveform_,
                                                                            &pulseWidth_,
                                                                            &drive_,
                                                                            &driveShape_,
                                                                            &driveBias_,
                                                                            &driveMix_,
                                                                            &renderMode_,
                                                                            &additivePartials_,
                                                                            &additiveTilt_,
                                                                            &additiveDrift_,
                                                                            &waveAddTableSet_,
                                                                            &unisonVoices_,
                                                                            &detuneCents_,
                                                                            &stereoSpread_,
                                                                            &syncEnabled_,
                                                                            &errCode));

        highwayErrCode_ = static_cast<int>(errCode);
    }

    if(simd_implementation_ != NULL)
    {
        simd_implementation_->prepare(static_cast<float>(sampleRate));
        simd_implementation_->configChanged();
        simd_implementation_->refreshWaveAddTableSet();
        simd_implementation_->resetPhase();
    }
}

Debug::Logger &  OscillatorNode::GetLog()
{
    if(simd_implementation_.get() != NULL)
        return simd_implementation_->GetLogger();

    return logger_;
}

void OscillatorNode::process(const std::vector<AudioBufferView>& inputs,
                             std::vector<WritableAudioBufferView>& outputs,
                             int numSamples) {
    const bool enabled = enabled_.load(std::memory_order_acquire);
    if (outputs.empty() || !enabled) {
        if (!outputs.empty()) outputs[0].clear();
        return;
    }

    if(simd_implementation_ != NULL)
    {
        simd_implementation_->run(inputs, outputs, numSamples);
        return;
    }

    const bool syncOn = syncEnabled_.load(std::memory_order_acquire);
    const bool hasSyncInput = syncOn && !inputs.empty() && inputs[0].numChannels > 0;

    auto& out = outputs[0];
    const int wf = waveform_.load(std::memory_order_acquire);
    const int renderMode = renderMode_.load(std::memory_order_acquire);
    const float targetRenderMix = renderMode == 1 ? 1.0f : 0.0f;
    const float targetFreq = targetFrequency_.load(std::memory_order_acquire);
    const float targetAmp = enabled ? targetAmplitude_.load(std::memory_order_acquire) : 0.0f;
    const float drive = drive_.load(std::memory_order_acquire);
    const int driveShape = driveShape_.load(std::memory_order_acquire);
    const int additivePartials = additivePartials_.load(std::memory_order_acquire);
    const float additiveTilt = additiveTilt_.load(std::memory_order_acquire);
    const float additiveDrift = additiveDrift_.load(std::memory_order_acquire);
    const float driveBias = driveBias_.load(std::memory_order_acquire);
    const float driveMix = driveMix_.load(std::memory_order_acquire);
    const float pulseWidthNorm = pulseWidth_.load(std::memory_order_acquire);
    const float pulseWidthPhase = pulseWidthNorm * static_cast<float>(kTwoPi);
    const int requestedUnison = unisonVoices_.load(std::memory_order_acquire);
    const float requestedDetuneCents = detuneCents_.load(std::memory_order_acquire);
    const float requestedSpread = stereoSpread_.load(std::memory_order_acquire);
    const auto waveAddTables = std::atomic_load_explicit(&waveAddTableSet_, std::memory_order_acquire);
    const float twopi = static_cast<float>(kTwoPi);

    // Wave-tab Add is the expensive additive recipe path. Raw 8-voice unison on top of
    // additive harmonic synthesis is just a CPU bomb, so remap it to a cheaper but still
    // musically sensible behaviour here instead of letting the whole project crackle.
    const bool additiveWaveMode = (targetRenderMix >= 0.5f) || (currentRenderMix_ >= 0.5f);
    int targetUnison = requestedUnison;
    float targetDetuneCents = requestedDetuneCents;
    float targetSpread = requestedSpread;
    const int effectiveAdditivePartials = additivePartials;
    if (additiveWaveMode) {
        constexpr int kAdditiveUnisonCap = 3;
        targetUnison = juce::jlimit(1, kAdditiveUnisonCap, requestedUnison);
        if (requestedUnison > targetUnison) {
            const float extra = static_cast<float>(requestedUnison - targetUnison)
                / static_cast<float>(juce::jmax(1, 8 - targetUnison));
            targetDetuneCents = juce::jlimit(0.0f, 100.0f, requestedDetuneCents * (1.0f + extra * 1.15f));
            targetSpread = juce::jlimit(0.0f, 1.0f, requestedSpread + extra * 0.35f);
        }
    }

    int layoutUnison = lastRequestedUnison_;
    if (targetUnison > lastRequestedUnison_) {
        for (int v = lastRequestedUnison_; v < targetUnison; ++v) {
            unisonPhases_[toIndex(v)] = phase_;
            unisonVoiceGains_[toIndex(v)] = 0.0f;
        }
        lastRequestedUnison_ = targetUnison;
        layoutUnison = targetUnison;
    } else {
        layoutUnison = juce::jmax(targetUnison, lastRequestedUnison_);
    }

    const int voiceLimit = juce::jlimit(1, 8, layoutUnison);
    const int placementCount = juce::jmax(1, layoutUnison);
    const float placementCenter = (static_cast<float>(placementCount) - 1.0f) * 0.5f;

    for (int i = 0; i < numSamples; ++i) {
        if (hasSyncInput) {
            const float syncSample = inputs[0].getSample(0, i);
            if (prevSyncSample_ <= 0.0f && syncSample > 0.0f) {
                phase_ = 0.0;
                for (auto& p : unisonPhases_) p = 0.0;
            }

            DEBUG_LOG_VALUE(logger_, totalSamples_, "prevSyncSample", prevSyncSample_);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "syncSample", syncSample);

            prevSyncSample_ = syncSample;
        }

        currentFrequency_ += (targetFreq - currentFrequency_) * freqSmoothingCoeff_;
        currentAmplitude_ += (targetAmp - currentAmplitude_) * ampSmoothingCoeff_;
        currentRenderMix_ += (targetRenderMix - currentRenderMix_) * renderMixSmoothingCoeff_;
        currentDetuneCents_ += (targetDetuneCents - currentDetuneCents_) * detuneSmoothingCoeff_;
        currentSpread_ += (targetSpread - currentSpread_) * spreadSmoothingCoeff_;

        const float phaseIncrement = twopi * currentFrequency_ / sampleRate_;
        const float renderMix = juce::jlimit(0.0f, 1.0f, currentRenderMix_);

        float leftSample = 0.0f;
        float rightSample = 0.0f;
        int contributingVoices = 0;

        bool higherVoicesStillActive = false;
        for (int v = 0; v < voiceLimit; ++v) {
            const auto voiceSlot = toIndex(v);
            const float targetVoiceGain = (v < targetUnison) ? 1.0f : 0.0f;
            unisonVoiceGains_[voiceSlot] += (targetVoiceGain - unisonVoiceGains_[voiceSlot]) * unisonVoiceSmoothingCoeff_;
            const float voiceGain = unisonVoiceGains_[voiceSlot];
            if (v >= targetUnison && voiceGain > 1.0e-4f) {
                higherVoicesStillActive = true;
            }

            if (voiceGain <= 1.0e-4f) {
                continue;
            }
            ++contributingVoices;

            const float voiceOffset = static_cast<float>(v) - placementCenter;
            const float detuneAmount = voiceOffset * currentDetuneCents_ / 100.0f;
            const float freqMult = std::powf(2.0, detuneAmount / 12.0);
            const float voicePhaseInc = phaseIncrement * freqMult;
            const float voiceFrequency = currentFrequency_ * freqMult;

            float& voicePhase = (v == 0) ? phase_ : unisonPhases_[voiceSlot];
            const float phaseNorm = voicePhase / twopi;

            
            DEBUG_LOG_VALUE(logger_, totalSamples_, "currentFreq", currentFrequency_);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "voiceOffset", voiceOffset);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "currentDetuneCents", currentDetuneCents_);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "detuneAmount", detuneAmount);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "voicePhase", voicePhase);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "phaseIncrement", phaseIncrement);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "freqMult", freqMult);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "voicePhaseInc", voicePhaseInc);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "phaseNorm", phaseNorm);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "currentAmplitude", currentAmplitude_);
       
            const auto renderAdditiveSample = [&]() {
                if (waveAddTables) {
                    const int bandIndex = waveAddBandIndexForFrequency(voiceFrequency, sampleRate_);
                    return lookupWaveAddSampleInternal(*waveAddTables, phaseNorm, bandIndex);
                }
                return additiveRecipeSample(wf, phaseNorm, voiceFrequency, sampleRate_, pulseWidthNorm,
                                            effectiveAdditivePartials, additiveTilt, additiveDrift);
            };

            float waveformSample = 0.0f;
            if (renderMix <= 0.0001f) {
                waveformSample = standardWaveformSample(wf, voicePhase, pulseWidthPhase, totalSamples_, logger_);
            } else if (renderMix >= 0.9999f) {
                waveformSample = renderAdditiveSample();
            } else {
                const float standardSample = standardWaveformSample(wf, voicePhase, pulseWidthPhase, totalSamples_, logger_);

                const float additiveSample = renderAdditiveSample();

                waveformSample = standardSample + (additiveSample - standardSample) * renderMix;
            }

            waveformSample = applyDriveShape(waveformSample, drive, driveShape, driveBias, driveMix);
            if (!std::isfinite(waveformSample)) {
                waveformSample = 0.0f;
            }

            waveformSample *= voiceGain;

            const float pan = juce::jlimit(0.0f,
                                           1.0f,
                                           0.5f + voiceOffset * currentSpread_ / static_cast<float>(juce::jmax(1, placementCount)));
            const float leftPan = std::sqrt(1.0f - pan);
            const float rightPan = std::sqrt(pan);

            leftSample += waveformSample * leftPan;
            rightSample += waveformSample * rightPan;

            DEBUG_LOG_VALUE(logger_, totalSamples_, "pan_left", leftPan);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "pan_right", rightPan);

            voicePhase += voicePhaseInc;
            while (voicePhase >= twopi) {
                voicePhase -= twopi;
                DEBUG_LOG_VALUE(logger_, totalSamples_, "Subtract 2pi from voicePhase", voicePhase);
            }
            
            while (voicePhase < 0.0) {
                voicePhase += twopi;
                DEBUG_LOG_VALUE(logger_, totalSamples_, "Add 2pi to voicePhase", voicePhase);
            }
        }

        if (!higherVoicesStillActive) {
            lastRequestedUnison_ = targetUnison;
        }

        const float normGain = (contributingVoices > 0) ? (1.0f / std::sqrt(static_cast<float>(contributingVoices))) : 0.0f;
        leftSample *= normGain * currentAmplitude_;
        rightSample *= normGain * currentAmplitude_;

        DEBUG_LOG_VALUE(logger_, totalSamples_, "normGain", normGain);
        DEBUG_LOG_VALUE(logger_, totalSamples_, "contribVoices", contributingVoices);

        if (!std::isfinite(leftSample)) {
            leftSample = 0.0f;
        }
        if (!std::isfinite(rightSample)) {
            rightSample = 0.0f;
        }

        if (out.numChannels >= 2) {
            out.setSample(0, i, leftSample);
            out.setSample(1, i, rightSample);

            DEBUG_LOG_VALUE(logger_, totalSamples_, "out_left", leftSample);
            DEBUG_LOG_VALUE(logger_, totalSamples_, "out_right", rightSample);

        } else {

            DEBUG_LOG_VALUE(logger_, totalSamples_, "out_mono", (leftSample + rightSample) * 0.5f);
            
            out.setSample(0, i, (leftSample + rightSample) * 0.5f);
        }

        ++totalSamples_;
    }
}

// Build partials from waveform recipe for morph mode
PartialData buildWavePartials(int waveform, float fundamental, int partialCount, float tilt, float drift, float pulseWidth) {
    PartialData result;
    result.fundamental = std::max(1.0f, fundamental);
    result.activeCount = 0;
    result.algorithm = "wave-recipe";

    const int maxPartials = std::min(partialCount, PartialData::kMaxPartials);
    if (maxPartials <= 0 || fundamental <= 0.0f) {
        return result;
    }

    // Tilt scaling: negative tilt emphasizes low harmonics, positive emphasizes high
    auto tiltScale = [tilt](int harmonic) -> float {
        const float ratio = static_cast<float>(harmonic);
        return std::max(0.12f, std::pow(ratio, tilt * 0.85f));
    };

    // Drift adds slight frequency jitter and phase offset
    auto driftOffset = [drift, waveform](int harmonic) -> std::pair<float, float> {
        if (drift <= 0.0f) {
            return {1.0f, 0.0f};
        }
        const double h = static_cast<double>(harmonic);
        const double w = static_cast<double>(waveform);
        const float freqJitter = 1.0f + static_cast<float>(std::sin(h * 2.173 + w * 0.53)) * drift * 0.035f * (1.0f + static_cast<float>(h) * 0.05f);
        const float phaseJitter = static_cast<float>(std::sin(h * 1.618 + w * 0.37)) * drift * 0.85f;
        return {freqJitter, phaseJitter};
    };

    int added = 0;
    float amplitudeSum = 0.0f;

    const auto storePartial = [&result](int index, float frequency, float amplitude, float phase, float decayRate) {
        const auto slot = toIndex(index);
        result.frequencies[slot] = frequency;
        result.amplitudes[slot] = amplitude;
        result.phases[slot] = phase;
        result.decayRates[slot] = decayRate;
    };

    switch (waveform) {
        case 0: { // Sine
            storePartial(0, fundamental, 1.0f, 0.0f, 0.0f);
            result.activeCount = 1;
            result.brightness = 0.0f;
            result.inharmonicity = 0.0f;
            return result;
        }

        case 1: { // Saw
            for (int h = 1; h <= maxPartials && added < PartialData::kMaxPartials; ++h) {
                const float baseAmp = 1.0f / static_cast<float>(h);
                const bool negative = (h % 2) == 0;
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             (negative ? static_cast<float>(M_PI) : 0.0f) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            break;
        }

        case 2: { // Square (odd harmonics)
            for (int h = 1; h <= maxPartials * 2 && added < PartialData::kMaxPartials; h += 2) {
                const float baseAmp = 1.0f / static_cast<float>(h);
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            break;
        }

        case 3: { // Triangle (odd harmonics, 1/n^2 amplitude)
            for (int h = 1; h <= maxPartials * 2 && added < PartialData::kMaxPartials; h += 2) {
                const float baseAmp = 1.0f / static_cast<float>(h * h);
                const bool positiveCosine = ((h / 2) % 2) == 1;
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             (positiveCosine ? static_cast<float>(M_PI * 0.5f) : static_cast<float>(-M_PI * 0.5f)) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            break;
        }

        case 4: { // Blend (mix of sine and saw)
            storePartial(0, fundamental, 0.45f, 0.0f, 0.0f);
            amplitudeSum += 0.45f;
            added = 1;

            for (int h = 2; h <= maxPartials + 1 && added < PartialData::kMaxPartials; ++h) {
                const float baseAmp = 0.55f / static_cast<float>(h);
                const bool negative = (h % 2) == 0;
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             (negative ? static_cast<float>(M_PI) : 0.0f) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            break;
        }

        case 5: { // Noise cloud (inharmonic)
            for (std::size_t i = 0; i < constants::kNoiseCloud.size() && added < PartialData::kMaxPartials; ++i) {
                const auto& partial = constants::kNoiseCloud[i];
                const auto [freqJitter, phaseJitter] = driftOffset(static_cast<int>(i + 1));
                const float ts = partial.amplitude * tiltScale(static_cast<int>(i + 1));

                storePartial(added,
                             fundamental * static_cast<float>(partial.ratio) * freqJitter,
                             ts,
                             static_cast<float>(partial.phaseOffset) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            result.inharmonicity = 0.5f;
            break;
        }

        case 6: { // Pulse (harmonics with sinc-shaped amplitudes)
            const float pw = std::clamp(pulseWidth, 0.01f, 0.99f);
            for (int h = 1; h <= maxPartials && added < PartialData::kMaxPartials; ++h) {
                const float coeff = std::sin(static_cast<float>(M_PI) * static_cast<float>(h) * pw);
                const float baseAmp = std::abs(coeff) / static_cast<float>(h);
                const bool negative = coeff < 0.0f;
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             (negative ? static_cast<float>(M_PI) : 0.0f) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            break;
        }

        case 7: { // SuperSaw
            for (int h = 1; h <= maxPartials && added < PartialData::kMaxPartials; ++h) {
                const float baseAmp = 1.0f / static_cast<float>(h);
                const bool negative = (h % 2) == 0;
                const auto [freqJitter, phaseJitter] = driftOffset(h);
                const float ts = tiltScale(h) * baseAmp * 0.84f;

                storePartial(added,
                             fundamental * static_cast<float>(h) * freqJitter,
                             ts,
                             (negative ? static_cast<float>(M_PI) : 0.0f) + phaseJitter,
                             0.0f);
                amplitudeSum += ts;
                ++added;
            }
            result.inharmonicity = 0.15f;
            break;
        }

        default:
            storePartial(0, fundamental, 1.0f, 0.0f, 0.0f);
            result.activeCount = 1;
            return result;
    }

    result.activeCount = added;

    if (amplitudeSum > 1.0e-6f) {
        for (int i = 0; i < result.activeCount; ++i) {
            result.amplitudes[toIndex(i)] /= amplitudeSum;
        }
    }

    if (result.activeCount > 0) {
        float weightedFreq = 0.0f;
        float totalAmp = 0.0f;
        for (int i = 0; i < result.activeCount; ++i) {
            weightedFreq += result.frequencies[toIndex(i)] * result.amplitudes[toIndex(i)];
            totalAmp += result.amplitudes[toIndex(i)];
        }
        if (totalAmp > 1.0e-6f) {
            const float centroid = weightedFreq / totalAmp;
            result.brightness = std::clamp((centroid - 100.0f) / 4900.0f, 0.0f, 1.0f);
        }
    }

    result.isReliable = true;
    return result;
}

} // namespace dsp_primitives

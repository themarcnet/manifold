#include "dsp/core/nodes/SampleRegionPlaybackNode.h"
#include "dsp/core/nodes/PartialsExtractor.h"
#include "dsp/core/nodes/SampleAnalyzer.h"

#include <cmath>
#include <vector>
#include <utility>

namespace dsp_primitives {

namespace {

float clamp01f(float v) {
    return juce::jlimit(0.0f, 1.0f, v);
}

const char* internAlgorithmName(const std::string& algorithm) {
    if (algorithm == "YIN") {
        return "YIN";
    }
    if (algorithm == "NSDF") {
        return "NSDF";
    }
    if (algorithm == "YIN+Stability") {
        return "YIN+Stability";
    }
    return "none";
}

struct AsyncAnalysisSnapshot {
    std::weak_ptr<SampleRegionPlaybackNode> node;
    juce::AudioBuffer<float> buffer;
    int sampleLength = 0;
    int numChannels = 1;
    float sampleRate = 44100.0f;
    int maxPartials = PartialData::kMaxPartials;
    int windowSize = 2048;
    int hopSize = 1024;
    int maxFrames = 128;
    std::uint64_t generation = 0;
};

juce::ThreadPool& sampleAnalysisPool() {
    static juce::ThreadPool pool { 1 };
    return pool;
}

class SamplePlaybackAnalysisJob final : public juce::ThreadPoolJob {
public:
    explicit SamplePlaybackAnalysisJob(AsyncAnalysisSnapshot snapshot)
        : juce::ThreadPoolJob("SamplePlaybackAnalysisJob"), snapshot_(std::move(snapshot)) {}

    JobStatus runJob() override {
        auto node = snapshot_.node.lock();
        if (!node || snapshot_.sampleLength <= 0 || snapshot_.sampleRate <= 0.0f) {
            return jobHasFinished;
        }

        const auto mono = SampleAnalyzer::foldToMono(snapshot_.buffer, snapshot_.numChannels, snapshot_.sampleLength);
        const auto analysis = SampleAnalyzer::analyzeMonoBuffer(
            mono.samples.data(),
            static_cast<int>(mono.samples.size()),
            snapshot_.sampleRate,
            mono.numChannels);
        const auto partials = PartialsExtractor::extractMonoBuffer(
            mono.samples.data(),
            static_cast<int>(mono.samples.size()),
            snapshot_.sampleRate,
            analysis,
            mono.numChannels,
            snapshot_.maxPartials);
        const auto temporal = PartialsExtractor::extractTemporalFrames(
            mono.samples.data(),
            static_cast<int>(mono.samples.size()),
            snapshot_.sampleRate,
            analysis,
            mono.numChannels,
            snapshot_.maxPartials,
            snapshot_.windowSize,
            snapshot_.hopSize,
            snapshot_.maxFrames);

        node->publishAsyncAnalysisResult(snapshot_.generation, analysis, partials, temporal);
        return jobHasFinished;
    }

private:
    AsyncAnalysisSnapshot snapshot_;
};

} // namespace

float SampleRegionPlaybackNode::normalizedUnisonOffset(int voiceIndex, int voiceCount) {
    if (voiceCount <= 1) {
        return 0.0f;
    }

    const float center = 0.5f * static_cast<float>(voiceCount - 1);
    const float maxOffset = juce::jmax(1.0f, center);
    return (static_cast<float>(voiceIndex) - center) / maxOffset;
}

SampleRegionPlaybackNode::SampleRegionPlaybackNode(int numChannels) : numChannels_(numChannels) {}

SampleRegionPlaybackNode::~SampleRegionPlaybackNode() = default;

void SampleRegionPlaybackNode::prepare(double sampleRate, int maxBlockSize) {
    (void)maxBlockSize;

    const double newSampleRate = sampleRate > 0.0 ? sampleRate : 44100.0;
    const int newMaxLoopSamples = juce::jmax(1, static_cast<int>(newSampleRate * 30.0));

    const bool needsReallocate =
        loopBufferA_.getNumChannels() != numChannels_ ||
        loopBufferA_.getNumSamples() != newMaxLoopSamples ||
        loopBufferB_.getNumChannels() != numChannels_ ||
        loopBufferB_.getNumSamples() != newMaxLoopSamples;

    sampleRate_ = newSampleRate;
    maxLoopSamples_ = newMaxLoopSamples;

    const double speedTimeSeconds = 0.012;
    const double detuneTimeSeconds = 0.012;
    const double spreadTimeSeconds = 0.012;
    const double unisonVoiceTimeSeconds = 0.008;
    speedSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (speedTimeSeconds * sampleRate_)));
    detuneSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (detuneTimeSeconds * sampleRate_)));
    spreadSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (spreadTimeSeconds * sampleRate_)));
    unisonVoiceSmoothingCoeff_ = static_cast<float>(1.0 - std::exp(-1.0 / (unisonVoiceTimeSeconds * sampleRate_)));
    speedSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, speedSmoothingCoeff_);
    detuneSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, detuneSmoothingCoeff_);
    spreadSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, spreadSmoothingCoeff_);
    unisonVoiceSmoothingCoeff_ = juce::jlimit(0.0001f, 1.0f, unisonVoiceSmoothingCoeff_);

    if (needsReallocate) {
        loopBufferA_.setSize(numChannels_, maxLoopSamples_, false, true, true);
        loopBufferB_.setSize(numChannels_, maxLoopSamples_, false, true, true);
        loopBufferA_.clear();
        loopBufferB_.clear();
        activeLoopBufferIndex_.store(0, std::memory_order_release);
        for (int v = 0; v < kMaxUnisonVoices; ++v) {
            readPositions_[v] = 0.0;
            firstPassStates_[v] = true;
        }
        lastPosition_.store(0, std::memory_order_release);
    } else {
        const int sampleLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
        for (int v = 0; v < kMaxUnisonVoices; ++v) {
            readPositions_[v] = clampPosition(readPositions_[v], sampleLength);
        }
        lastPosition_.store(static_cast<int>(readPositions_[0]), std::memory_order_release);
    }

    const int currentLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    loopLength_.store(currentLength, std::memory_order_release);
    currentSpeed_ = speed_.load(std::memory_order_acquire);
    currentDetuneCents_ = detuneCents_.load(std::memory_order_acquire);
    currentSpread_ = stereoSpread_.load(std::memory_order_acquire);
    unisonVoiceGains_[0] = 1.0f;
    for (int v = 1; v < kMaxUnisonVoices; ++v) {
        unisonVoiceGains_[v] = 0.0f;
    }
    lastRequestedUnison_ = 1;
}

void SampleRegionPlaybackNode::setLoopLength(int samples) {
    const int clamped = juce::jlimit(0, maxLoopSamples_, samples);
    loopLength_.store(clamped, std::memory_order_release);
}

int SampleRegionPlaybackNode::getLoopLength() const {
    return loopLength_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setSpeed(float speed) {
    speed_.store(juce::jlimit(0.0f, 8.0f, speed), std::memory_order_release);
}

float SampleRegionPlaybackNode::getSpeed() const {
    return speed_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::play() {
    playing_.store(true, std::memory_order_release);
}

void SampleRegionPlaybackNode::pause() {
    playing_.store(false, std::memory_order_release);
}

void SampleRegionPlaybackNode::stop() {
    playing_.store(false, std::memory_order_release);
    triggerRequest_.store(false, std::memory_order_release);
    seekRequest_.store(-1, std::memory_order_release);
    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        readPositions_[v] = 0.0;
        firstPassStates_[v] = true;
        unisonVoiceGains_[v] = (v == 0) ? 1.0f : 0.0f;
    }
    lastRequestedUnison_ = 1;
    lastPosition_.store(0, std::memory_order_release);
}

void SampleRegionPlaybackNode::trigger() {
    triggerRequest_.store(true, std::memory_order_release);
    playing_.store(true, std::memory_order_release);
}

bool SampleRegionPlaybackNode::isPlaying() const {
    return playing_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::seekNormalized(float normalized) {
    const int sampleLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
    const float clamped = clamp01f(normalized);
    const int position = juce::jlimit(0, sampleLength - 1,
                                      static_cast<int>(clamped * static_cast<float>(sampleLength - 1)));
    seekRequest_.store(position, std::memory_order_release);
}

float SampleRegionPlaybackNode::getNormalizedPosition() const {
    const int sampleLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
    const int position = juce::jlimit(0, sampleLength - 1, lastPosition_.load(std::memory_order_acquire));
    return static_cast<float>(position) / static_cast<float>(sampleLength);
}

void SampleRegionPlaybackNode::setPlayStart(float normalized) {
    playStartNorm_.store(clamp01f(normalized), std::memory_order_release);
}

float SampleRegionPlaybackNode::getPlayStart() const {
    return playStartNorm_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setLoopStart(float normalized) {
    loopStartNorm_.store(clamp01f(normalized), std::memory_order_release);
}

float SampleRegionPlaybackNode::getLoopStart() const {
    return loopStartNorm_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setLoopEnd(float normalized) {
    loopEndNorm_.store(clamp01f(normalized), std::memory_order_release);
}

float SampleRegionPlaybackNode::getLoopEnd() const {
    return loopEndNorm_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setCrossfade(float normalized) {
    crossfadeNorm_.store(juce::jlimit(0.0f, 0.5f, normalized), std::memory_order_release);
}

float SampleRegionPlaybackNode::getCrossfade() const {
    return crossfadeNorm_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setUnison(int voices) {
    unisonVoices_.store(juce::jlimit(1, kMaxUnisonVoices, voices), std::memory_order_release);
}

int SampleRegionPlaybackNode::getUnison() const {
    return unisonVoices_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setDetune(float cents) {
    detuneCents_.store(juce::jlimit(0.0f, 100.0f, cents), std::memory_order_release);
}

float SampleRegionPlaybackNode::getDetune() const {
    return detuneCents_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::setSpread(float amount) {
    stereoSpread_.store(juce::jlimit(0.0f, 1.0f, amount), std::memory_order_release);
}

float SampleRegionPlaybackNode::getSpread() const {
    return stereoSpread_.load(std::memory_order_acquire);
}

double SampleRegionPlaybackNode::clampPosition(double position, int sampleLength) {
    if (sampleLength <= 0) {
        return 0.0;
    }
    if (position < 0.0) {
        return 0.0;
    }
    const double maxPos = static_cast<double>(juce::jmax(0, sampleLength - 1));
    if (position > maxPos) {
        return maxPos;
    }
    return position;
}

SampleRegionPlaybackNode::RegionState SampleRegionPlaybackNode::computeRegionState() const {
    RegionState s;
    s.sampleLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));

    const float playStartNorm = clamp01f(playStartNorm_.load(std::memory_order_acquire));
    const float loopStartNorm = clamp01f(loopStartNorm_.load(std::memory_order_acquire));
    const float loopEndNorm = clamp01f(loopEndNorm_.load(std::memory_order_acquire));
    const float crossfadeNorm = juce::jlimit(0.0f, 0.5f, crossfadeNorm_.load(std::memory_order_acquire));

    s.playStart = juce::jlimit(0, s.sampleLength - 1,
                               static_cast<int>(playStartNorm * static_cast<float>(s.sampleLength - 1)));
    s.loopStart = juce::jlimit(0, s.sampleLength - 1,
                               static_cast<int>(loopStartNorm * static_cast<float>(s.sampleLength - 1)));
    s.loopEnd = juce::jlimit(1, s.sampleLength,
                             static_cast<int>(std::round(loopEndNorm * static_cast<float>(s.sampleLength))));

    if (s.loopEnd <= s.loopStart) {
        s.loopEnd = juce::jmin(s.sampleLength, s.loopStart + 1);
    }
    if (s.playStart >= s.loopEnd) {
        s.playStart = s.loopStart;
    }

    s.loopWindow = juce::jmax(1, s.loopEnd - s.loopStart);
    s.crossfadeSamples = juce::jlimit(0, juce::jmax(0, s.loopWindow - 1),
                                      static_cast<int>(std::round(crossfadeNorm * static_cast<float>(s.loopWindow))));
    return s;
}

float SampleRegionPlaybackNode::readSample(const juce::AudioBuffer<float>& buffer,
                                           int channel,
                                           double position) const {
    const int sampleLength = juce::jmax(1, loopLength_.load(std::memory_order_acquire));
    const double clampedPos = clampPosition(position, sampleLength);
    const int indexA = juce::jlimit(0, sampleLength - 1, static_cast<int>(clampedPos));
    const int indexB = juce::jlimit(0, sampleLength - 1, indexA + 1);
    const float frac = static_cast<float>(clampedPos - static_cast<double>(indexA));
    const float a = buffer.getSample(channel, indexA);
    const float b = buffer.getSample(channel, indexB);
    return a + (b - a) * frac;
}

void SampleRegionPlaybackNode::applyPendingControlChanges(const RegionState& region, int activeUnison) {
    const int unison = juce::jlimit(1, kMaxUnisonVoices, activeUnison);
    if (unison > lastRequestedUnison_) {
        const int anchorVoice = juce::jlimit(0, kMaxUnisonVoices - 1, (lastRequestedUnison_ - 1) / 2);
        const double anchorPosition = readPositions_[anchorVoice];
        const bool anchorFirstPass = firstPassStates_[anchorVoice];
        for (int v = lastRequestedUnison_; v < unison; ++v) {
            readPositions_[v] = anchorPosition;
            firstPassStates_[v] = anchorFirstPass;
            unisonVoiceGains_[v] = 0.0f;
        }
    }
    lastRequestedUnison_ = unison;

    if (triggerRequest_.exchange(false, std::memory_order_acq_rel)) {
        for (int v = 0; v < unison; ++v) {
            readPositions_[v] = static_cast<double>(region.playStart);
            firstPassStates_[v] = true;
            unisonVoiceGains_[v] = (v == 0) ? 1.0f : 0.0f;
        }
        for (int v = unison; v < kMaxUnisonVoices; ++v) {
            readPositions_[v] = static_cast<double>(region.playStart);
            firstPassStates_[v] = true;
            unisonVoiceGains_[v] = 0.0f;
        }
        lastPosition_.store(region.playStart, std::memory_order_release);
        playing_.store(true, std::memory_order_release);
    }

    const int seek = seekRequest_.exchange(-1, std::memory_order_acq_rel);
    if (seek >= 0) {
        const double seekPos = static_cast<double>(juce::jlimit(0, region.sampleLength - 1, seek));
        const bool firstPass = (seekPos < static_cast<double>(region.loopStart));
        for (int v = 0; v < kMaxUnisonVoices; ++v) {
            readPositions_[v] = seekPos;
            firstPassStates_[v] = firstPass;
            unisonVoiceGains_[v] = (v == 0) ? 1.0f : 0.0f;
        }
        lastPosition_.store(static_cast<int>(seekPos), std::memory_order_release);
    }
}

void SampleRegionPlaybackNode::process(const std::vector<AudioBufferView>& inputs,
                                       std::vector<WritableAudioBufferView>& outputs,
                                       int numSamples) {
    (void)inputs;
    const int channels = juce::jmin(numChannels_, static_cast<int>(outputs.size()));
    if (channels <= 0 || numSamples <= 0) {
        return;
    }

    const RegionState region = computeRegionState();
    const int targetUnison = juce::jlimit(1, kMaxUnisonVoices, unisonVoices_.load(std::memory_order_acquire));
    applyPendingControlChanges(region, targetUnison);

    if (region.sampleLength <= 0 || !playing_.load(std::memory_order_acquire)) {
        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            for (int i = 0; i < numSamples; ++i) {
                outputs[idx].setSample(ch, i, 0.0f);
            }
        }
        return;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    juce::AudioBuffer<float>& activeLoop = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;

    const float targetSpeed = juce::jlimit(0.0f, 8.0f, speed_.load(std::memory_order_acquire));
    const float targetDetuneCents = detuneCents_.load(std::memory_order_acquire);
    const float targetSpread = stereoSpread_.load(std::memory_order_acquire);
    if (targetSpeed <= 0.0f && currentSpeed_ <= 1.0e-4f) {
        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            for (int i = 0; i < numSamples; ++i) {
                outputs[idx].setSample(ch, i, 0.0f);
            }
        }
        return;
    }

    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        if (firstPassStates_[v]) {
            readPositions_[v] = juce::jlimit(static_cast<double>(region.playStart),
                                             static_cast<double>(region.loopEnd - 1),
                                             readPositions_[v]);
        } else {
            while (readPositions_[v] >= static_cast<double>(region.loopEnd)) {
                readPositions_[v] -= static_cast<double>(region.loopWindow);
            }
            while (readPositions_[v] < static_cast<double>(region.loopStart)) {
                readPositions_[v] += static_cast<double>(region.loopWindow);
            }
        }
    }

    const double crossfadeStart = static_cast<double>(region.loopEnd - region.crossfadeSamples);

    for (int i = 0; i < numSamples; ++i) {
        currentSpeed_ += (targetSpeed - currentSpeed_) * speedSmoothingCoeff_;
        currentDetuneCents_ += (targetDetuneCents - currentDetuneCents_) * detuneSmoothingCoeff_;
        currentSpread_ += (targetSpread - currentSpread_) * spreadSmoothingCoeff_;

        float mixedSamples[2] = {0.0f, 0.0f};
        int contributingVoices = 0;

        for (int v = 0; v < kMaxUnisonVoices; ++v) {
            const float targetVoiceGain = (v < targetUnison) ? 1.0f : 0.0f;
            unisonVoiceGains_[v] += (targetVoiceGain - unisonVoiceGains_[v]) * unisonVoiceSmoothingCoeff_;
            const float voiceGain = unisonVoiceGains_[v];
            if (voiceGain <= 1.0e-4f) {
                continue;
            }
            ++contributingVoices;

            const float offset = normalizedUnisonOffset(v, targetUnison);
            const double speedMult = std::pow(2.0, static_cast<double>(offset * currentDetuneCents_) / 1200.0);
            const double voiceSpeed = static_cast<double>(currentSpeed_) * speedMult;
            const float pan = juce::jlimit(0.0f, 1.0f, 0.5f + offset * currentSpread_ * 0.5f);
            const float leftPan = std::sqrt(1.0f - pan);
            const float rightPan = std::sqrt(pan);
            const double position = readPositions_[v];

            const bool inBoundaryCrossfade = region.crossfadeSamples > 0 &&
                                             position >= crossfadeStart &&
                                             position < static_cast<double>(region.loopEnd);

            for (int ch = 0; ch < channels; ++ch) {
                float out = 0.0f;
                if (inBoundaryCrossfade) {
                    const double seamOffset = position - crossfadeStart;
                    const double headPosition = static_cast<double>(region.loopStart) + seamOffset;
                    const float mix = static_cast<float>(seamOffset / static_cast<double>(region.crossfadeSamples));
                    const float tailGain = std::cos(mix * juce::MathConstants<float>::halfPi);
                    const float headGain = std::sin(mix * juce::MathConstants<float>::halfPi);
                    const float tailSample = readSample(activeLoop, ch, position);
                    const float headSample = readSample(activeLoop, ch, headPosition);
                    out = tailSample * tailGain + headSample * headGain;
                } else {
                    out = readSample(activeLoop, ch, position);
                }

                out *= voiceGain;
                if (channels >= 2) {
                    mixedSamples[ch] += out * (ch == 0 ? leftPan : rightPan);
                } else {
                    mixedSamples[ch] += out;
                }
            }

            readPositions_[v] += voiceSpeed;
            if (firstPassStates_[v]) {
                if (readPositions_[v] >= static_cast<double>(region.loopEnd)) {
                    const double overshoot = readPositions_[v] - static_cast<double>(region.loopEnd);
                    const double resumeOffset = static_cast<double>(region.crossfadeSamples);
                    readPositions_[v] = static_cast<double>(region.loopStart) + resumeOffset + overshoot;
                    while (readPositions_[v] >= static_cast<double>(region.loopEnd)) {
                        readPositions_[v] -= static_cast<double>(region.loopWindow);
                    }
                    firstPassStates_[v] = false;
                }
            } else {
                while (readPositions_[v] >= static_cast<double>(region.loopEnd)) {
                    const double overshoot = readPositions_[v] - static_cast<double>(region.loopEnd);
                    const double resumeOffset = static_cast<double>(region.crossfadeSamples);
                    readPositions_[v] = static_cast<double>(region.loopStart) + resumeOffset + overshoot;
                }
            }
        }

        const float normGain = (contributingVoices > 0)
            ? (1.0f / std::sqrt(static_cast<float>(contributingVoices)))
            : 0.0f;
        for (int ch = 0; ch < channels; ++ch) {
            const size_t idx = static_cast<size_t>(ch);
            outputs[idx].setSample(ch, i, mixedSamples[ch] * normGain);
        }
    }

    const int trackedVoice = juce::jlimit(0, targetUnison - 1, (targetUnison - 1) / 2);
    lastPosition_.store(juce::jlimit(0, region.sampleLength - 1, static_cast<int>(readPositions_[trackedVoice])),
                        std::memory_order_release);
}

bool SampleRegionPlaybackNode::computePeaks(int numBuckets, std::vector<float>& outPeaks) const {
    outPeaks.clear();
    if (numBuckets <= 0) {
        return false;
    }

    const int sampleLength = juce::jmax(0, loopLength_.load(std::memory_order_acquire));
    if (sampleLength <= 0) {
        return false;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const juce::AudioBuffer<float>& activeLoop = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;
    if (activeLoop.getNumSamples() <= 0 || activeLoop.getNumChannels() <= 0) {
        return false;
    }

    outPeaks.resize(static_cast<size_t>(numBuckets), 0.0f);
    const int bucketSize = juce::jmax(1, sampleLength / numBuckets);
    const int channels = juce::jmin(numChannels_, activeLoop.getNumChannels());

    float highest = 0.0f;
    for (int x = 0; x < numBuckets; ++x) {
        const int start = juce::jmin(sampleLength - 1, x * bucketSize);
        const int count = juce::jmin(bucketSize, sampleLength - start);
        float peak = 0.0f;

        for (int i = 0; i < count; ++i) {
            const int idx = start + i;
            for (int ch = 0; ch < channels; ++ch) {
                peak = juce::jmax(peak, std::abs(activeLoop.getSample(ch, idx)));
            }
        }

        outPeaks[static_cast<size_t>(x)] = peak;
        highest = juce::jmax(highest, peak);
    }

    const float rescale = highest > 0.0f
                              ? juce::jmin(8.0f, juce::jmax(1.0f, 1.0f / highest))
                              : 1.0f;
    for (auto& peak : outPeaks) {
        peak = juce::jmin(1.0f, peak * rescale);
    }

    return true;
}

std::vector<float> SampleRegionPlaybackNode::getPeaks(int numBuckets) const {
    std::vector<float> peaks;
    computePeaks(numBuckets, peaks);
    return peaks;
}

SampleAnalysis SampleRegionPlaybackNode::analyzeSample() const {
    SampleAnalysis analysis;
    PartialData partials;

    const int sampleLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    if (sampleLength <= 0) {
        analysis.isPercussive = true;
        analysis.isReliable = false;
        partials.isPercussive = true;
        partials.isReliable = false;
        std::lock_guard<std::mutex> lock(analysisMutex_);
        lastAnalysis_ = analysis;
        lastPartials_ = partials;
        return analysis;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const juce::AudioBuffer<float>& activeBuffer = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;
    const int channels = juce::jmax(1, juce::jmin(numChannels_, activeBuffer.getNumChannels()));
    const float sampleRate = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);

    const auto mono = SampleAnalyzer::foldToMono(activeBuffer, channels, sampleLength);
    analysis = SampleAnalyzer::analyzeMonoBuffer(mono.samples.data(),
                                                 static_cast<int>(mono.samples.size()),
                                                 sampleRate,
                                                 mono.numChannels);
    partials = PartialsExtractor::extractMonoBuffer(mono.samples.data(),
                                                    static_cast<int>(mono.samples.size()),
                                                    sampleRate,
                                                    analysis,
                                                    mono.numChannels);

    std::lock_guard<std::mutex> lock(analysisMutex_);
    lastAnalysis_ = analysis;
    lastPartials_ = partials;
    return analysis;
}

SampleAnalysis SampleRegionPlaybackNode::getLastAnalysis() const {
    std::lock_guard<std::mutex> lock(analysisMutex_);
    return lastAnalysis_;
}

PartialData SampleRegionPlaybackNode::extractPartials() const {
    const SampleAnalysis analysis = analyzeSample();
    (void)analysis;
    std::lock_guard<std::mutex> lock(analysisMutex_);
    return lastPartials_;
}

PartialData SampleRegionPlaybackNode::getLastPartials() const {
    std::lock_guard<std::mutex> lock(analysisMutex_);
    return lastPartials_;
}

TemporalPartialData SampleRegionPlaybackNode::extractTemporalPartials(
    int maxPartials, int windowSize, int hopSize, int maxFrames) const
{
    const int sampleLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    if (sampleLength <= 0) {
        TemporalPartialData empty;
        std::lock_guard<std::mutex> lock(analysisMutex_);
        lastTemporalPartials_ = empty;
        return empty;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const juce::AudioBuffer<float>& activeBuffer = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;
    const int channels = juce::jmax(1, juce::jmin(numChannels_, activeBuffer.getNumChannels()));
    const float sampleRate = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);

    const auto mono = SampleAnalyzer::foldToMono(activeBuffer, channels, sampleLength);
    const auto analysis = SampleAnalyzer::analyzeMonoBuffer(
        mono.samples.data(), static_cast<int>(mono.samples.size()), sampleRate, mono.numChannels);

    auto temporal = PartialsExtractor::extractTemporalFrames(
        mono.samples.data(),
        static_cast<int>(mono.samples.size()),
        sampleRate,
        analysis,
        mono.numChannels,
        maxPartials,
        windowSize,
        hopSize,
        maxFrames);

    std::lock_guard<std::mutex> lock(analysisMutex_);
    lastTemporalPartials_ = temporal;
    return temporal;
}

TemporalPartialData SampleRegionPlaybackNode::getLastTemporalPartials() const {
    std::lock_guard<std::mutex> lock(analysisMutex_);
    return lastTemporalPartials_;
}

void SampleRegionPlaybackNode::requestAsyncAnalysis(int maxPartials,
                                                    int windowSize,
                                                    int hopSize,
                                                    int maxFrames) {
    const int sampleLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    if (sampleLength <= 0) {
        asyncAnalysisPending_.store(false, std::memory_order_release);
        return;
    }

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const juce::AudioBuffer<float>& activeBuffer = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;
    const int channels = juce::jmax(1, juce::jmin(numChannels_, activeBuffer.getNumChannels()));
    const float sampleRate = static_cast<float>(sampleRate_ > 0.0 ? sampleRate_ : 44100.0);

    AsyncAnalysisSnapshot snapshot;
    snapshot.node = shared_from_this();
    snapshot.sampleLength = sampleLength;
    snapshot.numChannels = channels;
    snapshot.sampleRate = sampleRate;
    snapshot.maxPartials = juce::jlimit(1, PartialData::kMaxPartials, maxPartials);
    snapshot.windowSize = juce::jmax(256, windowSize);
    snapshot.hopSize = juce::jmax(64, hopSize);
    snapshot.maxFrames = juce::jlimit(1, TemporalPartialData::kMaxFrames, maxFrames);
    snapshot.generation = analysisRequestedGeneration_.fetch_add(1, std::memory_order_acq_rel) + 1;
    snapshot.buffer.setSize(channels, sampleLength, false, true, true);
    for (int ch = 0; ch < channels; ++ch) {
        snapshot.buffer.copyFrom(ch, 0, activeBuffer, ch, 0, sampleLength);
    }

    asyncAnalysisPending_.store(true, std::memory_order_release);
    juce::Logger::writeToLog("SampleRegionPlaybackNode::requestAsyncAnalysis generation=" + juce::String(static_cast<long long>(snapshot.generation)) +
                             " sampleLength=" + juce::String(sampleLength));
    sampleAnalysisPool().addJob(new SamplePlaybackAnalysisJob(std::move(snapshot)), true);
}

bool SampleRegionPlaybackNode::isAsyncAnalysisPending() const {
    return asyncAnalysisPending_.load(std::memory_order_acquire);
}

void SampleRegionPlaybackNode::publishAsyncAnalysisResult(std::uint64_t generation,
                                                          const SampleAnalysis& analysis,
                                                          const PartialData& partials,
                                                          const TemporalPartialData& temporal) {
    const auto requestedGeneration = analysisRequestedGeneration_.load(std::memory_order_acquire);
    if (generation < requestedGeneration) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(analysisMutex_);
        lastAnalysis_ = analysis;
        lastPartials_ = partials;
        lastTemporalPartials_ = temporal;
    }

    analysisCompletedGeneration_.store(generation, std::memory_order_release);
    asyncAnalysisPending_.store(false, std::memory_order_release);
    juce::Logger::writeToLog("SampleRegionPlaybackNode::publishAsyncAnalysisResult generation=" + juce::String(static_cast<long long>(generation)) +
                             " freq=" + juce::String(analysis.frequency) +
                             " partials=" + juce::String(partials.activeCount) +
                             " frames=" + juce::String(temporal.frameCount));
}

SampleAnalysisResult SampleRegionPlaybackNode::analyzeRootKey() const {
    const SampleAnalysis analysis = analyzeSample();

    SampleAnalysisResult result;
    result.midiNote = analysis.midiNote;
    result.frequency = analysis.frequency;
    result.confidence = analysis.confidence;
    result.pitchStability = analysis.pitchStability;
    result.isPercussive = analysis.isPercussive;
    result.attackEndSample = analysis.attackEndSample;
    result.analysisStartSample = analysis.analysisStartSample;
    result.analysisEndSample = analysis.analysisEndSample;
    result.algorithm = internAlgorithmName(analysis.algorithm);
    return result;
}

void SampleRegionPlaybackNode::clearLoop() {
    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const int writeIndex = (activeIndex == 0) ? 1 : 0;
    juce::AudioBuffer<float>& writeBuffer = (writeIndex == 0) ? loopBufferA_ : loopBufferB_;
    writeBuffer.clear();
    activeLoopBufferIndex_.store(writeIndex, std::memory_order_release);
    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        readPositions_[v] = 0.0;
        firstPassStates_[v] = true;
    }
    lastPosition_.store(0, std::memory_order_release);
    loopLength_.store(0, std::memory_order_release);
    analysisRequestedGeneration_.store(0, std::memory_order_release);
    analysisCompletedGeneration_.store(0, std::memory_order_release);
    asyncAnalysisPending_.store(false, std::memory_order_release);

    std::lock_guard<std::mutex> lock(analysisMutex_);
    lastAnalysis_ = SampleAnalysis{};
    lastPartials_ = PartialData{};
    lastTemporalPartials_ = TemporalPartialData{};
}

void SampleRegionPlaybackNode::copyFromCaptureBuffer(const juce::AudioBuffer<float>& captureBuffer,
                                                     int captureSize,
                                                     int captureStartOffset,
                                                     int numSamples,
                                                     bool overdub) {
    if (captureSize <= 0 || numSamples <= 0 || captureBuffer.getNumChannels() <= 0) {
        return;
    }

    const int requestedLength = juce::jlimit(1, maxLoopSamples_, numSamples);

    const int activeIndex = activeLoopBufferIndex_.load(std::memory_order_acquire);
    const int writeIndex = (activeIndex == 0) ? 1 : 0;
    juce::AudioBuffer<float>& writeBuffer = (writeIndex == 0) ? loopBufferA_ : loopBufferB_;
    const juce::AudioBuffer<float>& activeBuffer = (activeIndex == 0) ? loopBufferA_ : loopBufferB_;

    const int previousLength = juce::jlimit(0, maxLoopSamples_, loopLength_.load(std::memory_order_acquire));
    const int targetLength = requestedLength;
    const int channels = juce::jmin(numChannels_, captureBuffer.getNumChannels(), writeBuffer.getNumChannels());

    int start = captureStartOffset;
    while (start < 0) {
        start += captureSize;
    }
    start %= captureSize;

    writeBuffer.clear();

    if (!overdub || previousLength <= 0) {
        for (int ch = 0; ch < channels; ++ch) {
            for (int i = 0; i < targetLength; ++i) {
                const int src = (start + i) % captureSize;
                writeBuffer.setSample(ch, i, captureBuffer.getSample(ch, src));
            }
        }
    } else {
        for (int ch = 0; ch < channels; ++ch) {
            for (int i = 0; i < targetLength; ++i) {
                const float existing = activeBuffer.getSample(ch, i % previousLength);
                const int src = (start + i) % captureSize;
                writeBuffer.setSample(ch, i, existing + captureBuffer.getSample(ch, src));
            }
        }
    }

    loopLength_.store(targetLength, std::memory_order_release);
    activeLoopBufferIndex_.store(writeIndex, std::memory_order_release);
    for (int v = 0; v < kMaxUnisonVoices; ++v) {
        readPositions_[v] = 0.0;
        firstPassStates_[v] = true;
    }
    lastPosition_.store(0, std::memory_order_release);
    asyncAnalysisPending_.store(false, std::memory_order_release);

    std::lock_guard<std::mutex> lock(analysisMutex_);
    lastAnalysis_ = SampleAnalysis{};
    lastPartials_ = PartialData{};
    lastTemporalPartials_ = TemporalPartialData{};
}

} // namespace dsp_primitives

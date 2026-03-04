#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_events/juce_events.h>

#include "../../manifold/core/BehaviorCoreProcessor.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <thread>

static std::atomic<bool> shouldQuit{false};

static void signalHandler(int) {
    shouldQuit.store(true);
}

static void printUsage(const char* name) {
    std::fprintf(stderr,
                 "Usage: %s [--samplerate SR] [--blocksize BS] [--duration SECS]\n"
                 "  --samplerate  Sample rate (default: 44100)\n"
                 "  --blocksize   Block size (default: 512)\n"
                 "  --duration    Run duration in seconds, 0=forever (default: 0)\n",
                 name);
}

int main(int argc, char* argv[]) {
    double sampleRate = 44100.0;
    int blockSize = 512;
    double duration = 0.0;

    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--samplerate") == 0 && i + 1 < argc) {
            sampleRate = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--blocksize") == 0 && i + 1 < argc) {
            blockSize = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            printUsage(argv[0]);
            return 0;
        } else {
            std::fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            printUsage(argv[0]);
            return 1;
        }
    }

    juce::ScopedJuceInitialiser_GUI juceInit;

    std::fprintf(stderr,
                 "LooperPrimitivesHeadless: sampleRate=%.0f blockSize=%d duration=%.1fs\n",
                 sampleRate, blockSize, duration);

    BehaviorCoreProcessor processor;
    processor.prepareToPlay(sampleRate, blockSize);

    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);

    juce::AudioBuffer<float> buffer(2, blockSize);
    juce::MidiBuffer midi;

    const auto blockDuration = std::chrono::microseconds(
        static_cast<long long>(blockSize / sampleRate * 1'000'000.0));

    const auto startTime = std::chrono::steady_clock::now();
    long long blocksProcessed = 0;

    while (!shouldQuit.load()) {
        const auto blockStart = std::chrono::steady_clock::now();

        buffer.clear();
        processor.processBlock(buffer, midi);
        ++blocksProcessed;

        if (duration > 0.0) {
            const auto elapsed = std::chrono::steady_clock::now() - startTime;
            const double elapsedSecs = std::chrono::duration<double>(elapsed).count();
            if (elapsedSecs >= duration)
                break;
        }

        const auto elapsed = std::chrono::steady_clock::now() - blockStart;
        const auto remaining = blockDuration - elapsed;
        if (remaining.count() > 0)
            std::this_thread::sleep_for(remaining);
    }

    const auto totalTime = std::chrono::steady_clock::now() - startTime;
    const double totalSecs = std::chrono::duration<double>(totalTime).count();

    std::fprintf(stderr,
                 "\nLooperPrimitivesHeadless: Stopped. %lld blocks processed in %.1fs "
                 "(%.1f blocks/sec)\n",
                 blocksProcessed,
                 totalSecs,
                 blocksProcessed / (totalSecs > 0 ? totalSecs : 1.0));

    processor.releaseResources();
    return 0;
}

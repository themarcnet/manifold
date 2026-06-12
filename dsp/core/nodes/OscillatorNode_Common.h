#pragma once

#include <array>

namespace dsp_primitives
{

    struct WaveAddTableSet
    {
        std::array<std::array<float, 2048 + 1>, 20> bands{};
    };

    struct InharmonicPartial
    {
        double ratio;
        float amplitude;
        double phaseOffset;
    };

    
    struct SuperSawLayer
    {
        float detuneCents;
        float gain;
        double phaseOffset;
    };

    namespace constants
    {
        constexpr std::array<InharmonicPartial, 12> kNoiseCloud = {{
            { 1.00, 1.00f, 0.00 },
            { 1.37, 0.91f, 0.63 },
            { 1.93, 0.82f, 1.42 },
            { 2.58, 0.74f, 2.17 },
            { 3.11, 0.67f, 0.88 },
            { 3.93, 0.60f, 2.74 },
            { 5.17, 0.52f, 1.11 },
            { 6.44, 0.45f, 2.49 },
            { 8.13, 0.38f, 0.37 },
            { 10.37, 0.31f, 1.96 },
            { 13.11, 0.25f, 2.81 },
            { 16.51, 0.20f, 0.94 },
        }};

        constexpr std::array<SuperSawLayer, 5> kSuperSawLayers = {{
            { -18.0f, 0.55f, 0.17 },
            { -7.0f, 0.82f, 0.51 },
            { 0.0f, 1.00f, 0.00 },
            { 8.0f, 0.79f, 0.33 },
            { 19.0f, 0.50f, 0.74 },
        }};
    }

    //Interface specific to Highway version of OscillatorNode
    namespace OscillatorNode_Highway
    {
        class IOscillatorNodeSIMDAInterface : public IPrimitiveNodeSIMDImplementation
        {
        public:
            virtual ~IOscillatorNodeSIMDAInterface()
            {}

            virtual void refreshWaveAddTableSet() = 0;
            virtual void resetPhase() = 0;
            virtual const Debug::Logger & GetLogger() const = 0;
        };
    }

}

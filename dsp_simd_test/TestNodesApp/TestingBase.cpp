
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#include "TestingBase.h"


TestingBase::TestingBase()
{}

TestingBase::TestData * TestingBase::CreateTest(const char * name, float samplerate,StereoMode mode, int numBusses)
{
    TestData & retData = data_.emplace_back();

    retData.index = static_cast<int>(data_.size() - 1);
    retData.name = name;
    retData.mode = StereoMode_Stereo;
    retData.busses.resize(numBusses); //1 bus
    retData.sampleRate = samplerate;

    return &retData;
}

TestingBase::TestWaveSpec * TestingBase::AppendTestWaveSpec(TestData * test, int bus, int numSamples, float leftScale, float rightScale)
{
    TestWaveSpec & ret = test->busses[bus].waves.emplace_back();
    ret.numSamples = numSamples;
    ret.left.scale = leftScale;
    ret.right.scale = rightScale;
    return &ret;
}

TestingBase::TestWaveSpec * TestingBase::AppendSilenceTestWaveSpec(TestData * test, int bus, int numSamples)
{
    TestWaveSpec & ret = test->busses[bus].waves.emplace_back();
    ret.numSamples = numSamples;
    ret.left.scale = 0.0f;
    ret.right.scale = 0.0f;

    TestWave & silenceleft = ret.left.waveParameters.emplace_back();
    
    silenceleft.amplitude = 0.0f;
    silenceleft.frequency = 0.0f;
    silenceleft.phase = 0.0f;

    if(test->mode != StereoMode_Mono)
    {
        TestWave & silenceright = ret.right.waveParameters.emplace_back();
        silenceright.amplitude = 0.0f;
        silenceright.frequency = 0.0f;
        silenceright.phase = 0.0f;
    }

    return &ret;
}

TestingBase::TestWave * TestingBase::AddWaveToMix(TestWaveSpec * testch, Channel channel, float frequency, float amplitude, float phase)
{
    TestWave * ret = NULL;
    if(channel == 0)
    {
        ret = &(testch->left.waveParameters.emplace_back());
    }
    else
    {
        ret = &(testch->right.waveParameters.emplace_back());
    }

    ret->amplitude = amplitude;
    ret->frequency = frequency;
    ret->phase = phase;
    return ret;
}

void TestingBase::GenerateTestSamples(std::vector<TestData> & testdata)
{
    for( TestData & td : testdata)
    {
        //Generate buffers - one for each bus
        int busnum = 0;
        for(const auto & bus : td.busses)
        {
            //Iterate over wave parameters to calculate the number of samples
            int totalNiumSamples = 0;
            for(const auto & w : bus.waves)
            {
                totalNiumSamples += w.numSamples;
            }

            //Allocate audio buffer
            const int numchannels = (td.mode == StereoMode_Mono) ? 1 : 2;
            std::shared_ptr<juce::AudioBuffer<float>> currentBusBuffer(new juce::AudioBuffer<float>(numchannels, totalNiumSamples));

            //Zero the channels
            float * const * bufferPtrs =  currentBusBuffer->getArrayOfWritePointers();
            for(int c=0; c < numchannels; ++c)
            {
                memset(bufferPtrs[c], 0, totalNiumSamples * sizeof(float));
            }

            //Generate waves, as per the wave parameters
            int offset = 0;
            const float pi = static_cast<float>(M_PI);
            const float deltatime = 1.0f / td.sampleRate;
            for(const auto & w : bus.waves)
            {   
                for(int c = 0; c < numchannels; ++c)
                {
                    float * destPtr = bufferPtrs[c] + offset;
                    const TestMix & srcMix = ((c == 1) && (td.mode == StereoMode_Stereo)) ? w.right : w.left;
                    for(const auto & wav : srcMix.waveParameters)
                    {
                        for(int t=0; t < w.numSamples; ++t)
                        {
                            float s = static_cast<float>(t) * 2 * pi * wav.frequency * deltatime;
                            s += wav.phase;
                            s = sin(s) * wav.amplitude;
                            s *= srcMix.scale;
                            destPtr[t] += s;
                        }
                    }
                }

                offset += w.numSamples;
            }

            //Store audio buffer for the bus
            td.wavedata.push_back(currentBusBuffer);
            ++busnum;
        }
    }
}
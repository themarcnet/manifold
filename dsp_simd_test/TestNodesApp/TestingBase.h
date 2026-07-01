#pragma once

#include <vector>
#include <memory>
#include <string>
#include <map>
#include <chrono>

#include <juce_audio_basics/juce_audio_basics.h>

#include <manifold/debugging/Logging.h>

namespace dsp_primitives
{
    class IPrimitiveNode;
}

class TestingBase
{
public:

    //Details of a single waveform
    struct TestWave
    {
        float frequency = 400;
        float phase = 0;
        float amplitude = 1.0f;
    };

    //Details of multiple waveforms to add together
    struct TestMix
    {
        float scale = 1.0f;
        std::vector<TestWave> waveParameters;
    };

    //Details of left and right channel definitions
    struct TestWaveSpec
    {
        int numSamples = 1024;
        TestMix left;
        TestMix right; //Ignored in mono or duplicate modes
    };

    //Details of multiple waves appended together
    struct TestBus
    {   
        std::vector<TestWaveSpec> waves;
    };

    
    enum StereoMode
    {
        StereoMode_Mono,
        StereoMode_Stereo,
        StereoMode_Duplicate,
    };

    
    struct NodeParameterValue
    {
        NodeParameterValue(const char * v) : strval(v)
        {
            data.strval = strval.c_str();
        }

        NodeParameterValue(const float v)
        {
            data.floatval = v;
        }

        NodeParameterValue(double v)
        {
            data.dblval = v;
        }

        NodeParameterValue(int32_t v)
        {
            data.i32val = v;
        }

        NodeParameterValue(int64_t v)
        {
            data.i64val = v;
        }

        NodeParameterValue(bool v)
        {
            data.bval = v;
        }

        union
        {
            float floatval;
            double dblval;
            const char * strval;
            int32_t i32val;
            int64_t i64val;
            bool bval;
        } data;
        const std::string strval;
    };

    typedef std::vector<std::shared_ptr<juce::AudioBuffer<float>>> AudioBufferPtrVector;

    struct TestData
    {
        int index;
        std::string name;
        
        //Wave generation 
        StereoMode mode;
        size_t blockSize = 256;
        float sampleRate = 44100;
        float tolerance = 0.008f;
        bool resetInstances = false;
        std::vector<TestBus> busses; //Allows multiple busses for a single test

        //Node paramters for this test
        std::map<std::string, NodeParameterValue> nodeParameters;
        
        //Generated audio data, modified by GenerateTestSamples
        TestingBase::AudioBufferPtrVector wavedata;

        //Test results
        std::map<std::string, std::chrono::nanoseconds> simdDurations;  //Time per target
        std::map<std::string,  std::chrono::nanoseconds> baseTestDuration; //Base time per target
        std::map < std::string, std::shared_ptr<std::vector<std::vector<float>>>> baseResult;
        std::map < std::string, std::shared_ptr<std::vector<std::vector<float>>>> simdResult;
        std::map<std::string, float> maxResultDifference;
    };
   
    TestingBase();

    virtual dsp_primitives::IPrimitiveNode * CreateNode(int target) const = 0;

    virtual const char * GetName() const = 0;

    //Implement by test to specify a suite of tests with waveforms, channels, busses, length all configurable.
    virtual std::vector<TestData> * GetTestData() = 0;
    
    //Generate the wave data for all tests
    void GenerateTestSamples(std::vector<TestData> & testdata);

    //Configure the specified node. Test specific because of the different parameters that each node has.
    virtual bool ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters) = 0;

    virtual void AfterPrepare(dsp_primitives::IPrimitiveNode * /*node*/) 
    {}

    virtual void ResetNode(dsp_primitives::IPrimitiveNode * node) = 0;

    virtual Debug::Logger * GetLog(dsp_primitives::IPrimitiveNode * node) 
    {
        return NULL;
    }

protected:
    enum Channel
    {
        Channel_Left = 0,
        Channel_Right = 1
    };

     TestData * CreateTest(const char * name, float samplerate, StereoMode mode, int numBusses);

     TestWaveSpec * AppendTestWaveSpec(TestData * test, int bus, int numSamples, float leftScale = 1.0f, float rightScale = 1.0f);

     TestWaveSpec * AppendSilenceTestWaveSpec(TestData * test, int bus, int numSamples);

     TestWave * AddWaveToMix(TestWaveSpec * testch, Channel channel, float frequency, float amplitude, float phase);

     std::vector<TestData> * GetTestDataPtr()
     {
         return &data_;
     };

private:
    std::vector<TestData> data_;
};

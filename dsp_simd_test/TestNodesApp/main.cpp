#define _USE_MATH_DEFINES

#include <stdio.h>
#include <math.h>

namespace juce
{
    const char * juce_compilationDate = "1/1/1";
    const char * juce_compilationTime = "2/2/2";
}

#include "dsp/core//nodes/ADSREnvelopeNode.h"
#include "dsp/core//nodes/BitCrusherNode.h"

struct NodeParameterValue
{
    NodeParameterValue(const char * v) : floatval(-1),dblval(-1),strval(v), i32val(-1), i64val(-1), bval(false)
    {}

    NodeParameterValue(const float v) :  floatval(v),dblval(-1),i32val(-1), i64val(-1), bval(false)
    {}

    NodeParameterValue(double v) :  floatval(-1), dblval(v),i32val(-1), i64val(-1), bval(false)
    {}

    NodeParameterValue(int32_t v) :  floatval(-1), dblval(-1),i32val(v), i64val(-1), bval(false)
    {}

    NodeParameterValue(int64_t v) : floatval(-1), dblval(-1),i32val(-1),i64val(v), bval(false)
    {}

    NodeParameterValue(bool v) :floatval(-1), dblval(-1),i32val(-1),i64val(-1),  bval(v)
    {}

    float floatval;
    double dblval;
    std::string strval;
    int32_t i32val;
    int64_t i64val;
    bool bval;
};

static const int c_max_waves = 128;

struct TestWaveData
{   
    int numSamples;
    float channelAmps[2];

    int numWaves;
    float frequences[c_max_waves];
    float phases[c_max_waves];
    float amps[c_max_waves];    
};

struct NodeTestEntry
{
    bool stereo;
    std::string name;
    std::map<std::string, NodeParameterValue> parameters;
    std::vector<std::vector<TestWaveData>> testdata;
    std::vector<std::vector<float>> result;
    std::chrono::nanoseconds testDuration;
    std::chrono::nanoseconds baseTestDuration;
};

#define FLOAT_TOLLERANCE_SSE            0.008f

static float pow_wrapper(float a, float b)
{
    return powf(a,b);
}

static double pow_wrapper(double a, double b)
{
    return pow(a,b);
}


template<typename F>
static bool compareFloats(F a, F b, const F tolerance)
{   
    if(a == b)
        return true;

    if(_finite(a) && !_finite(b))
        return false;

    if(!_finite(a) && _finite(b))
        return false;

    if(!_finite(a) && !_finite(b))
        return true;

    if(!_isnan(a) && _isnan(b))
        return false;

    if(_isnan(a) && !_isnan(b))
        return false;

    if(_isnan(a) && _isnan(b))
        return true;
        
    F absa = abs(a);
    F absb = abs(b);
    F logab = 0;
    F flogab = 0;
    F maxab = (absa > absb) ? absa : absb;
    F minab = (absa < absb) ? absa : absb;

    int abfactor = 0;
    if(maxab != 0)
    {
        logab = log10(maxab);
        flogab = floor(logab);
        abfactor = (int)flogab; 
    }

        
    //Zero fix / approx zero fix
    F maxdiff = tolerance;
    if((absa == 0) || (absb == 0))
    {
        //Allow greater error if one value is zero
        maxdiff = tolerance * pow_wrapper(10.0f,  static_cast<F>(abfactor) / 2);
    }
    else
    {
        bool signa = (a >= 0);
        bool signb = (b >= 0);
        if(signa != signb)
            return false;

        if(abfactor > 0)
            maxdiff = tolerance * pow_wrapper(10.0f, static_cast<F>(abfactor) - 1);
        else
            maxdiff = tolerance * pow_wrapper(10.0f, static_cast<F>(abfactor) + 1);
    }

    F diff = maxab - minab;
    if(diff > maxdiff)
        return false;

    return true;
}


//================================================================


static std::unique_ptr<juce::AudioBuffer<float>> GenerateSamples(const double samplerate, bool stereo, int numSamples,
                                                                 const float * channelAmp, 
                                                                 const float * frequencies, const float * phase, const float * amplitude, int numwaves)
{
    const int numChannels = stereo ? 2 : 1;
    const float pi = static_cast<float>(M_PI);
    std::unique_ptr<juce::AudioBuffer<float>> buffer(new juce::AudioBuffer<float>(numChannels, numSamples));
    
    float * const * destptr = buffer->getArrayOfWritePointers();
    float time = 0;
    const float deltatime = 1.0f / static_cast<float>(samplerate);
    for(int c =0; c < numChannels; ++c)
    {   
        for(int t = 0; t < numSamples; ++t)
        {
            float sampval = 0.0f;
            for(int f = 0; f < numwaves; ++f)
            {
                float s = static_cast<float>(t) * 2 * pi * frequencies[f] * deltatime;
                s += phase[f];
                s = sin(s) * amplitude[f];
                s *= channelAmp[c];

                sampval += s;
            };

            destptr[c][t] = sampval;
        }

    }

    return buffer;
}


//================================================================

static bool ConfigureNode(dsp_primitives::ADSREnvelopeNode & node, const std::map<std::string,NodeParameterValue> & parameters)
{
    for(const auto & itr : parameters)
    {
        if(itr.first == "Attack_Seconds")
            node.setAttack(itr.second.floatval);
        else if(itr.first == "Decay_Seconds")
            node.setDecay(itr.second.floatval);
        else if(itr.first == "Sustain_Level")
            node.setSustain(itr.second.floatval);
        else if(itr.first == "Release_Seconds")
            node.setRelease(itr.second.floatval);
        else if(itr.first == "Gate")
            node.setGate(itr.second.bval);
    }

    return true;
}

static bool ConfigureNode(dsp_primitives::BitCrusherNode & node, const std::map<std::string,NodeParameterValue> & parameters)
{
    for(const auto & itr : parameters)
    {
        if(itr.first == "Bits")
            node.setBits(itr.second.floatval);
        else if(itr.first == "LogicMode")
            node.setLogicMode(itr.second.i32val);
        else if(itr.first == "Mix")
            node.setMix(itr.second.floatval);
        else if(itr.first == "Output")
            node.setOutput(itr.second.floatval);
        else if(itr.first == "RateReduction")
            node.setRateReduction(itr.second.floatval);
    }

    return true;
}


//================================================================

static void GenerateWave1Parameters(TestWaveData & entry, int sampleCount)
{
    entry.channelAmps[0] = 1.0f;
    entry.channelAmps[1] = 0.8f;
    entry.numSamples = sampleCount;
    entry.numWaves = 1;
    entry.amps[0] = 1.0f;
    entry.frequences[0] = 440;
    entry.phases[0] = 0;    
}

static void GenerateWave2Parameters(TestWaveData & entry, int sampleCount)
{
    entry.channelAmps[0] = 1.0f;
    entry.channelAmps[1] = 0.8f;
    entry.numSamples = sampleCount;
    entry.numWaves = 2;
    entry.amps[0] = 0.2f;
    entry.amps[1] = 0.8f;
    entry.frequences[0] = 440;
    entry.frequences[1] = 740;
    entry.phases[0] = 0;
    entry.phases[1] = 45;
}

static void GenerateWave3Parameters(TestWaveData & entry, int sampleCount)
{
    entry.channelAmps[0] = 1.0f;
    entry.channelAmps[1] = 0.5f;
    entry.numSamples = sampleCount;
    entry.numWaves = 3;
    entry.amps[0] = 0.2f;
    entry.amps[1] = 2.8f;
    entry.amps[2] = 0.7f;
    entry.frequences[0] = 880;
    entry.frequences[1] = 1480;
    entry.frequences[2] = 3276;
    entry.phases[0] = 0;
    entry.phases[1] = 45;
    entry.phases[2] = 32;
}

static void GenerateWave4Parameters(TestWaveData & entry, int sampleCount)
{
    entry.channelAmps[0] = 0.8f;
    entry.channelAmps[1] = 1.0f;
    entry.numSamples = sampleCount;
    entry.numWaves = 5;
    entry.amps[0] = 0.2f;
    entry.amps[1] = 0.3f;
    entry.amps[2] = 0.3f;
    entry.amps[3] = 0.1f;
    entry.amps[4] = 0.2f;
    entry.frequences[0] = 770;
    entry.frequences[1] = 1320;
    entry.frequences[2] = 2206;
    entry.frequences[3] = 440;
    entry.frequences[4] = 3282;
    entry.phases[0] = 0;
    entry.phases[1] = 45;
    entry.phases[2] = 32;
    entry.phases[3] = 69;
    entry.phases[4] = 12;
}


static void GenerateWave5Parameters(TestWaveData & entry, int sampleCount)
{
    entry.channelAmps[0] = 1.0f;
    entry.channelAmps[1] = 0.8f;
    entry.numSamples = sampleCount;
    entry.numWaves = 3;
    entry.amps[0] = 0.2f;
    entry.amps[1] = 0.8f;
    entry.amps[2] = 0.7f;
    entry.frequences[0] = 660;
    entry.frequences[1] = 1220;
    entry.frequences[2] = 1206;
    entry.phases[0] = 0;
    entry.phases[1] = 32;
    entry.phases[2] = 56;
}

template<class T>
static bool GetTestData(std::vector<NodeTestEntry> & out)
{
    return false;
}


template<>
static bool GetTestData<dsp_primitives::ADSREnvelopeNode>(std::vector<NodeTestEntry> & out)
{
    out.resize(6);

    out[0].stereo = false;
    out[0].name = "Off";
    out[0].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(1);
        GenerateWave1Parameters(t[0].emplace_back(), 9999);
        return t;
    }();
    out[0].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Attack_Seconds", NodeParameterValue(static_cast<float>(0.25f))));
        m.insert(std::make_pair("Decay_Seconds", NodeParameterValue(static_cast<float>(1.23f))));
        m.insert(std::make_pair("Sustain_Level", NodeParameterValue(static_cast<float>(0.69f))));
        m.insert(std::make_pair("Release_Seconds", NodeParameterValue(static_cast<float>(2.3f))));
        m.insert(std::make_pair("Gate", NodeParameterValue(false)));
        return m;
    }();

    //Turn 'gate' on to start processing with various waves
    out[1].stereo = false;
    out[1].name = "Gate=On (Attack)";
    out[1].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Gate", NodeParameterValue(true)));
        return m;
    }();
    out[1].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave1Parameters(t[0].emplace_back(), 10000);
        GenerateWave2Parameters(t[1].emplace_back(), 28023);
        GenerateWave3Parameters(t[2].emplace_back(), 12034);
        GenerateWave4Parameters(t[3].emplace_back(), 13095);
        GenerateWave5Parameters(t[4].emplace_back(), 10702);
        return t;
    }();

    
    //Turn 'gate' off to release
    out[2].stereo = false;
    out[2].name = "Gate=Off (Release)";
    out[2].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Gate", NodeParameterValue(false)));
        return m;
    }();
    out[2].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(4);
        GenerateWave3Parameters(t[0].emplace_back(), 19999);
        GenerateWave2Parameters(t[1].emplace_back(), 36723);
        GenerateWave1Parameters(t[2].emplace_back(), 12000);
        GenerateWave4Parameters(t[3].emplace_back(), 15700);
        return t;
    }();


    out[3].stereo = true;
    out[3].name = "Off - Stereo";
    out[3].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(1);
        GenerateWave1Parameters(t[0].emplace_back(), 9999);
        return t;
    }();
    out[3].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Attack_Seconds", NodeParameterValue(static_cast<float>(0.8f))));
        m.insert(std::make_pair("Decay_Seconds", NodeParameterValue(static_cast<float>(0.5f))));
        m.insert(std::make_pair("Sustain_Level", NodeParameterValue(static_cast<float>(0.9f))));
        m.insert(std::make_pair("Release_Seconds", NodeParameterValue(static_cast<float>(1.3f))));
        m.insert(std::make_pair("Gate", NodeParameterValue(false)));
        return m;
    }();

    //Turn 'gate' on to start processing with various waves
    out[4].stereo = true;
    out[4].name = "Gate=On (Attack) - Stereo";
    out[4].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Gate", NodeParameterValue(true)));
        return m;
    }();
    out[4].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave3Parameters(t[0].emplace_back(), 10000);
        GenerateWave2Parameters(t[1].emplace_back(), 8023);
        GenerateWave2Parameters(t[2].emplace_back(), 12034);
        GenerateWave4Parameters(t[3].emplace_back(), 13095);
        GenerateWave5Parameters(t[4].emplace_back(), 10702);
        return t;
    }();

    //Turn 'gate' off to release
    out[5].stereo = true;
    out[5].name = "Gate=Off (Release) - Stereo";
    out[5].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Gate", NodeParameterValue(false)));
        return m;
    }();
    out[5].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(4);
        GenerateWave5Parameters(t[0].emplace_back(), 19999);
        GenerateWave2Parameters(t[1].emplace_back(), 16723);
        GenerateWave3Parameters(t[2].emplace_back(), 12000);
        GenerateWave1Parameters(t[3].emplace_back(), 15700);
        return t;
    }();

    return true;
}


template<>
static bool GetTestData<dsp_primitives::BitCrusherNode>(std::vector<NodeTestEntry> & out)
{
    out.resize(9);

    out[0].stereo = true;
    out[0].name = "15 Bits - Logic Mode 1 - one input";
    out[0].testdata = []
    {
        //Provide 3 inputs (input 1 not used)
        std::vector<std::vector<TestWaveData>> t(4);
        GenerateWave3Parameters(t[0].emplace_back(), 2012);
        GenerateWave1Parameters(t[1].emplace_back(), 2164);
        GenerateWave5Parameters(t[2].emplace_back(), 2111);
        GenerateWave5Parameters(t[3].emplace_back(), 1117);
        return t;
    }();    
    out[0].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(15.0f))));
        m.insert(std::make_pair("RateReduction", NodeParameterValue(static_cast<float>(1.2f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.8f))));
        m.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.2f))));
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        return m;
    }();

    out[1].stereo = true;
    out[1].name = "14 Bits - Logic Mode 2 - one input";
    out[1].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave1Parameters(t[0].emplace_back(), 2312);
        GenerateWave2Parameters(t[1].emplace_back(), 2637);
        GenerateWave3Parameters(t[2].emplace_back(), 2164);
        GenerateWave4Parameters(t[3].emplace_back(), 2111);
        GenerateWave5Parameters(t[4].emplace_back(), 2187);
        return t;
    }();    
    out[1].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(14.0f))));
        return m;
    }();

    out[2].stereo = true;
    out[2].name = "13 Bits - Logic Mode 3 - one input";
    out[2].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave1Parameters(t[0].emplace_back(), 312);
        GenerateWave2Parameters(t[1].emplace_back(), 637);
        GenerateWave3Parameters(t[2].emplace_back(), 164);
        GenerateWave4Parameters(t[3].emplace_back(), 111);
        GenerateWave5Parameters(t[4].emplace_back(), 1187);
        return t;
    }();    
    out[2].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(3))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(13.0f))));
        return m;
    }();

    out[3].stereo = true;
    out[3].name = "15 Bits - Logic Mode 1 - two inputs";
    out[3].testdata = []
    {
        //Provide 3 inputs (input 1 not used)
        std::vector<std::vector<TestWaveData>> t(4);
        GenerateWave3Parameters(t[0].emplace_back(), 2312);
        GenerateWave1Parameters(t[0].emplace_back(), 2312);
        GenerateWave2Parameters(t[0].emplace_back(), 2312);
        
        GenerateWave1Parameters(t[1].emplace_back(), 2164);
        GenerateWave1Parameters(t[1].emplace_back(), 2164);
        GenerateWave3Parameters(t[1].emplace_back(), 2164);

        GenerateWave5Parameters(t[2].emplace_back(), 2111);
        GenerateWave1Parameters(t[2].emplace_back(), 2111);
        GenerateWave3Parameters(t[2].emplace_back(), 2111);

        GenerateWave2Parameters(t[3].emplace_back(), 1117);
        GenerateWave1Parameters(t[3].emplace_back(), 1117);
        GenerateWave5Parameters(t[3].emplace_back(), 1117);
        return t;
    }();    
    out[3].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(15.0f))));
        m.insert(std::make_pair("RateReduction", NodeParameterValue(static_cast<float>(1.2f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.8f))));
        m.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.2f))));
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        return m;
    }();


    
    out[4].stereo = true;
    out[4].name = "12 Bits - Logic Mode 2 - two input";
    out[4].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(4);
        GenerateWave2Parameters(t[0].emplace_back(), 3312);
        GenerateWave1Parameters(t[0].emplace_back(), 3312);
        GenerateWave5Parameters(t[0].emplace_back(), 3312);
        
        GenerateWave1Parameters(t[1].emplace_back(), 2637);
        GenerateWave1Parameters(t[1].emplace_back(), 2637);
        GenerateWave4Parameters(t[1].emplace_back(), 2637);

        GenerateWave3Parameters(t[2].emplace_back(), 3164);
        GenerateWave1Parameters(t[2].emplace_back(), 3164);
        GenerateWave3Parameters(t[2].emplace_back(), 3164);

        GenerateWave4Parameters(t[3].emplace_back(), 21187);
        GenerateWave1Parameters(t[3].emplace_back(), 21187);
        GenerateWave5Parameters(t[3].emplace_back(), 21187);
        return t;
    }();    
    out[4].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(12.0f))));
        return m;
    }();


    out[5].stereo = true;
    out[5].name = "7 Bits - Logic Mode 1 - one input";
    out[5].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave1Parameters(t[0].emplace_back(), 1312);
        GenerateWave2Parameters(t[1].emplace_back(), 2637);
        GenerateWave3Parameters(t[2].emplace_back(), 1164);
        GenerateWave4Parameters(t[3].emplace_back(), 2111);
        GenerateWave5Parameters(t[4].emplace_back(), 3187);
        return t;
    }();    
    out[5].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(7.0f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.5f))));
        m.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.0f))));
        return m;
    }();

    out[6].stereo = true;
    out[6].name = "4 Bits - Logic Mode 2 - two inputs";
    out[6].testdata = []
    {
        std::vector<std::vector<TestWaveData>> t(5);
        GenerateWave1Parameters(t[0].emplace_back(), 1312);
        GenerateWave1Parameters(t[0].emplace_back(), 1312);
        GenerateWave5Parameters(t[0].emplace_back(), 1312);
        
        GenerateWave2Parameters(t[1].emplace_back(), 2637);
        GenerateWave1Parameters(t[1].emplace_back(), 2637);
        GenerateWave4Parameters(t[1].emplace_back(), 2637);

        GenerateWave3Parameters(t[2].emplace_back(), 1164);
        GenerateWave1Parameters(t[2].emplace_back(), 1164);
        GenerateWave3Parameters(t[2].emplace_back(), 1164);

        GenerateWave4Parameters(t[3].emplace_back(), 2111);
        GenerateWave1Parameters(t[3].emplace_back(), 2111);
        GenerateWave2Parameters(t[3].emplace_back(), 2111);
        
        GenerateWave5Parameters(t[4].emplace_back(), 3187);
        GenerateWave1Parameters(t[4].emplace_back(), 3187);
        GenerateWave1Parameters(t[4].emplace_back(), 3187);
        return t;
    }();    
    out[6].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(4.0f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.9f))));
        return m;
    }();

    out[7].stereo = true;
    out[7].name = "2 Bits - Logic Mode 1 - two inputs";
    out[7].testdata = out[6].testdata;
    out[7].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(2.0f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.9f))));
        return m;
    }();

    out[8].stereo = true;
    out[8].name = "15 Bits - Logic Mode 1 - two inputs";
    out[8].testdata = out[6].testdata;
    out[8].parameters = []
    {
        std::map<std::string, NodeParameterValue> m;
        m.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        m.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(15.0f))));
        m.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.5f))));
        return m;
    }();

    return true;
}


//================================================================
template<typename T>
static bool TestNode(const double samplerate, const int blksize)
{
    T node;
    T basenode;

    printf("===================================\n%s\n===================================\n", node.getNodeType());

    //Get test data
    std::vector<NodeTestEntry> tests;
    if(!GetTestData<T>(tests) || tests.empty())
    {
        printf("TEST DATA GENERATION FAILED! ");
        return false;
    }

    //Get generic interface
    dsp_primitives::IPrimitiveNode * primitiveIFace = &node;
    dsp_primitives::IPrimitiveNode * basePrimitiveIFace = &basenode;

    //Set sample rate and block size
    primitiveIFace->prepare(samplerate, blksize);
    basePrimitiveIFace->prepare(samplerate, blksize);


    //On the base version, turn off SIMD.
    //This gives us something to compare against
    basenode.disableSIMD();
    
    //Run tests
    long long baseTotal = 0;
    long long simdTotal = 0;
    for(auto & curtest : tests)
    {
        printf("   Test %s : ", curtest.name.c_str());

        //Configure the node
        if(!ConfigureNode(node, curtest.parameters))
        {
            printf("CONFIGURE FAILED! ");
            return false;
        }

        if(!ConfigureNode(basenode, curtest.parameters))
        {
            printf("BASE CONFIGURE FAILED! ");
            return false;
        }
            
        const int numChannels = curtest.stereo ? 2 : 1;
        curtest.testDuration = std::chrono::nanoseconds::zero();
        curtest.baseTestDuration = std::chrono::nanoseconds::zero();
        for(const auto & curtestdata : curtest.testdata)
        {
            //Generate test data
            std::vector<std::unique_ptr<juce::AudioBuffer<float>>> testdatabuffers;
            int numSamples = -1;
            for(const auto & bufdata : curtestdata)
            {
                if((numSamples == -1) || (bufdata.numSamples < numSamples))
                    numSamples = bufdata.numSamples;

                testdatabuffers.push_back(GenerateSamples(samplerate, curtest.stereo, bufdata.numSamples, bufdata.channelAmps,
                                                          bufdata.frequences, bufdata.phases, bufdata.amps, bufdata.numWaves));
            }

            //Allocate buffer for output
            std::unique_ptr<juce::AudioBuffer<float>> outputbuffer(new juce::AudioBuffer<float>(numChannels, numSamples));

            //Allocate buffer for base output
            std::unique_ptr<juce::AudioBuffer<float>> baseOutputbuffer(new juce::AudioBuffer<float>(numChannels, numSamples));
            

            //Process in blocks
            int remain = numSamples;
            if(remain == 0)
            {
                printf("FAILED - Test Buffer Zero");
                return false;
            }
            
            size_t offset = 0;
            while(remain > 0)
            {
                const int blockSampleCount = (remain > blksize) ? blksize : remain;

                //Generate input view
                std::vector<dsp_primitives::AudioBufferView> inputViews(testdatabuffers.size());
                std::vector<const float *> inputPtrs(numChannels * testdatabuffers.size());
                int idx = 0;
                int ptridx = 0;
                for(const auto & buf : testdatabuffers)
                {
                    inputViews[idx].numChannels = numChannels;
                    inputViews[idx].numSamples = blockSampleCount;
                    const float * const * origInPtrs = buf->getArrayOfReadPointers();
                    for(int c=0; c < numChannels; ++c)
                    {
                        inputPtrs[ptridx] = &origInPtrs[c][offset];
                        ++ptridx;
                    }

                    inputViews[idx].channelData = &inputPtrs[ptridx - numChannels];
                    ++idx;
                }

                //Generate output view
                std::vector<dsp_primitives::WritableAudioBufferView> outputViews(1);
                std::vector<dsp_primitives::WritableAudioBufferView> baseOutputViews(1);
                std::vector<float *> outputPtrs(numChannels);
                std::vector<float *> baseOutputPtrs(numChannels);
                outputViews[0].numChannels = numChannels;
                outputViews[0].numSamples = blockSampleCount;
                baseOutputViews[0].numChannels = numChannels;
                baseOutputViews[0].numSamples = blockSampleCount;
                float * const * origOutPtrs = outputbuffer->getArrayOfWritePointers();
                float * const * origBaseOutPtrs = baseOutputbuffer->getArrayOfWritePointers();
                for(int c=0; c < numChannels; ++c)
                {
                    outputPtrs[c] = &origOutPtrs[c][offset];
                    baseOutputPtrs[c] = &origBaseOutPtrs[c][offset];
                }
                outputViews[0].channelData = outputPtrs.data();
                baseOutputViews[0].channelData = baseOutputPtrs.data();

                //Process base implementation
                auto start = std::chrono::high_resolution_clock::now();;
                basePrimitiveIFace->process(inputViews, baseOutputViews, blockSampleCount);
                auto end = std::chrono::high_resolution_clock::now();
                curtest.baseTestDuration += (end - start);

                //Process simd implementation
                start = std::chrono::high_resolution_clock::now();
                primitiveIFace->process(inputViews, outputViews, blockSampleCount);
                end = std::chrono::high_resolution_clock::now();
                curtest.testDuration += (end - start);
                
                //collect results for current block
                curtest.result.resize(numChannels);
                for(int c = 0; c < numChannels; ++c)
                {
                    const size_t cursz = curtest.result[c].size();

                    //Compare with base
                    for(int x=0; x < blockSampleCount; ++x)
                    {
                        if(!compareFloats(outputPtrs[c][x], baseOutputPtrs[c][x], FLOAT_TOLLERANCE_SSE))
                        {
                            printf(" - Fail : Sample %zu Channel %u : Expected %g, got %g", x + cursz, c, baseOutputPtrs[c][x], outputPtrs[c][x]);
                            return false;
                        }
                    }

                    curtest.result[c].resize(cursz + blockSampleCount);
                    memcpy(&curtest.result[c][cursz], outputPtrs[c], sizeof(float) * blockSampleCount);
                }

                //Next block
                remain -= blockSampleCount;
                offset += blockSampleCount;
            }
        }

        printf(" - Pass - Base: %lld nanoseconds SIMD:%lld nanoseconds Speed:%f\n",
               std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.baseTestDuration).count(),
               std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.testDuration).count(),
               static_cast<float>(std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.baseTestDuration).count()) / static_cast<float>(std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.testDuration).count()));

        baseTotal += std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.baseTestDuration).count();
        simdTotal += std::chrono::duration_cast<std::chrono::nanoseconds>(curtest.testDuration).count();
    }

    printf("SUCCESS - Base Total:%lld \t SIMD Total: %lld Speed:%f \n", baseTotal, simdTotal, static_cast<float>(baseTotal) / static_cast<float>(simdTotal));

    //return success
    return true;
}




int main(int argc, const char ** argv)
{
    static const double c_samplerate = 44100;
    static const int c_blockSize = 256;

    if(!TestNode<dsp_primitives::ADSREnvelopeNode>(c_samplerate, c_blockSize))
    {
        printf(" - FAILED!");
        return -1;
    }

    if(!TestNode<dsp_primitives::BitCrusherNode>(c_samplerate, c_blockSize))
    {
        printf(" - FAILED!");
        return -1;
    }
    
    printf(" - Success\n");

    return 0;
}
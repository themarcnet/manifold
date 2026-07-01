

#include "TestGainNode.h"

dsp_primitives::IPrimitiveNode * TestGainNode::CreateNode(int target) const
{
     dsp_primitives::GainNode * gainnode = new dsp_primitives::GainNode();

     //Call separate method to set the SIMD target platform. 
     gainnode->overrideHighwayImplementationTarget(target);
     
     return gainnode;
}

void TestGainNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::GainNode * gainnode = dynamic_cast<dsp_primitives::GainNode *>(node);
    gainnode->reset();
}

bool TestGainNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
     dsp_primitives::GainNode * gainnode = dynamic_cast<dsp_primitives::GainNode*>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "Gain")
            gainnode->setGain(itr.second.data.floatval);
        else if(itr.first == "Muted")
            gainnode->setMuted(itr.second.data.bval);
        else
            throw new std::runtime_error((std::string("Unknown GainNode parameter ") + itr.first).c_str());
    }

    return true;
}

std::vector<TestingBase::TestData> * TestGainNode::GetTestData()
{
    {
        //Test 1: Mono - gain 1.0

        TestData * test = CreateTest("Mono Gain 1.0", 44100, StereoMode_Mono, 1);
        test->nodeParameters.insert(std::make_pair("Gain", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Muted", NodeParameterValue(false)));

        //Waveform 1 
        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 20001);
        AddWaveToMix(testdata, Channel_Left, 440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Left, 980, 0.6f, 32);
    }

    {
        //Test 2: Stereo gain 0.5

        TestData * test = CreateTest("Stereo Gain 0.5", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Gain", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Muted", NodeParameterValue(false)));

        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 20001);
        AddWaveToMix(testdata, Channel_Left, 1440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 1980, 0.6f, 32);
    }

     {
        //Test 2: Stereo gain 2.0 muted

        TestData * test = CreateTest("Stereo Gain 2.0 + Muted", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Gain", NodeParameterValue(static_cast<float>(2.0f))));
        test->nodeParameters.insert(std::make_pair("Muted", NodeParameterValue(true)));

        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 20001);
        AddWaveToMix(testdata, Channel_Left, 1440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Left, 1980, 0.6f, 32);
        AddWaveToMix(testdata, Channel_Right, 1440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 1980, 1.6f, 32);
    }


     {
        //Test 3: Stereo gain 1.0 again

        TestData * test = CreateTest("Stereo Unmuted  Back to Gain 1.0", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Gain", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Muted", NodeParameterValue(false)));

        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 20001);
        AddWaveToMix(testdata, Channel_Left, 2440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 2980, 0.6f, 32);
     }

     return GetTestDataPtr();
}

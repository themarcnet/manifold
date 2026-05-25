#include "TestADSRNode.h"

dsp_primitives::IPrimitiveNode * TestADSRNode::CreateNode(int target) const
{
    return new dsp_primitives::ADSREnvelopeNode(target);
}

void TestADSRNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::ADSREnvelopeNode * adsrnode = dynamic_cast<dsp_primitives::ADSREnvelopeNode *>(node);
    adsrnode->reset();
}

bool TestADSRNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
     dsp_primitives::ADSREnvelopeNode * adsrnode = dynamic_cast<dsp_primitives::ADSREnvelopeNode *>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "Attack_Seconds")
            adsrnode->setAttack(itr.second.data.floatval);
        else if(itr.first == "Decay_Seconds")
            adsrnode->setDecay(itr.second.data.floatval);
        else if(itr.first == "Sustain_Level")
            adsrnode->setSustain(itr.second.data.floatval);
        else if(itr.first == "Release_Seconds")
            adsrnode->setRelease(itr.second.data.floatval);
        else if(itr.first == "Gate")
            adsrnode->setGate(itr.second.data.bval);
        else
             throw new std::exception((std::string("Unknown ADSR Envelope parameter ") + itr.first).c_str());
    }

    return true;
}


std::vector<TestingBase::TestData> * TestADSRNode::GetTestData()
{
     //Test 1 : Off
    {
        TestData * offTest = CreateTest("Off - Mono", 44100, StereoMode_Mono, 1);
        offTest->nodeParameters.insert(std::make_pair("Attack_Seconds", NodeParameterValue(static_cast<float>(0.25f))));
        offTest->nodeParameters.insert(std::make_pair("Decay_Seconds", NodeParameterValue(static_cast<float>(1.23f))));
        offTest->nodeParameters.insert(std::make_pair("Sustain_Level", NodeParameterValue(static_cast<float>(0.69f))));
        offTest->nodeParameters.insert(std::make_pair("Release_Seconds", NodeParameterValue(static_cast<float>(2.3f))));
        offTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(false)));

        //Single mono wave
        TestWaveSpec * offTestData = AppendTestWaveSpec(offTest, 0, 9999);
        AddWaveToMix(offTestData, Channel_Left, 440, 1.0f, 0);
    }

    //Test 2 : Gate-on attack - mono
    {
        TestData * gateOnTest = CreateTest("Gate=On (Attack) - Mono", 44100, StereoMode_Mono, 1);
        gateOnTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(true)));

        TestWaveSpec * gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 10000);
        AddWaveToMix(gateOnTestData, Channel_Left, 640, 1.0f, 0);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 28023);
        AddWaveToMix(gateOnTestData, Channel_Left, 440, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 740, 0.8f, 45);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 12034);
        AddWaveToMix(gateOnTestData, Channel_Left, 880, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1480, 2.8f, 45);
        AddWaveToMix(gateOnTestData, Channel_Left, 3276, 0.7f, 32);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 13095);
        AddWaveToMix(gateOnTestData, Channel_Left, 770, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1320, 0.3f, 45);
        AddWaveToMix(gateOnTestData, Channel_Left, 2206, 0.3f, 32);
        AddWaveToMix(gateOnTestData, Channel_Left, 440, 0.1f, 69);
        AddWaveToMix(gateOnTestData, Channel_Left, 3282, 0.2f, 12);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 10702);
        AddWaveToMix(gateOnTestData, Channel_Left, 660, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1320, 0.8f, 32);
        AddWaveToMix(gateOnTestData, Channel_Left, 1206, 0.7f, 56);
    }

    //Test 3 - Gate off - release
    {
        TestData * gateOffTest = CreateTest("Gate=Off (Release) - Mono", 44100, StereoMode_Mono, 1);
        gateOffTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(false)));

        TestWaveSpec * gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 19999);
        AddWaveToMix(gateOffTestData, Channel_Left, 1880, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 1480, 2.8f, 45);
        AddWaveToMix(gateOffTestData, Channel_Left, 3276, 0.7f, 32);
        
        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 36723);
        AddWaveToMix(gateOffTestData, Channel_Left, 1440, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 740, 0.8f, 45);

        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 12000);
        AddWaveToMix(gateOffTestData, Channel_Left, 1640, 1.0f, 0);

        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 15700);
        AddWaveToMix(gateOffTestData, Channel_Left, 1770, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 1320, 0.6f, 45);
        AddWaveToMix(gateOffTestData, Channel_Left, 206, 0.8f, 32);
        AddWaveToMix(gateOffTestData, Channel_Left, 1440, 0.1f, 69);
    }

    //Test 4 : Off - Stereo
    {
        TestData * offStereoTest = CreateTest("Off - Stereo", 44100, StereoMode_Stereo, 1);
        offStereoTest->nodeParameters.insert(std::make_pair("Attack_Seconds", NodeParameterValue(static_cast<float>(0.8f))));
        offStereoTest->nodeParameters.insert(std::make_pair("Decay_Seconds", NodeParameterValue(static_cast<float>(0.5f))));
        offStereoTest->nodeParameters.insert(std::make_pair("Sustain_Level", NodeParameterValue(static_cast<float>(0.9f))));
        offStereoTest->nodeParameters.insert(std::make_pair("Release_Seconds", NodeParameterValue(static_cast<float>(1.3f))));
        offStereoTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(false)));

        TestWaveSpec * offStereoTestTest = AppendTestWaveSpec(offStereoTest, 0, 9999, 1.0f, 0.8f);
        AddWaveToMix(offStereoTestTest, Channel_Left, 440, 1.0f, 0);
        AddWaveToMix(offStereoTestTest, Channel_Right, 440, 1.0f, 0);
    }


    //Test 5 : Gate-on attack - Stereo
    {
        TestData * gateOnTest = CreateTest("Gate=On (Attack) - Stereo", 44100, StereoMode_Stereo, 1);
        gateOnTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(true)));

        TestWaveSpec * gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 10000, 0.8f, 1.0f);
        AddWaveToMix(gateOnTestData, Channel_Left, 640, 1.0f, 0);
        AddWaveToMix(gateOnTestData, Channel_Right, 630, 1.0f, 0);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 28023);
        AddWaveToMix(gateOnTestData, Channel_Left, 440, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 740, 0.8f, 45);
        AddWaveToMix(gateOnTestData, Channel_Right, 480, 0.2f, 19);
        AddWaveToMix(gateOnTestData, Channel_Right, 780, 0.8f, 12);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 12034);
        AddWaveToMix(gateOnTestData, Channel_Left, 880, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1480, 2.8f, 45);
        AddWaveToMix(gateOnTestData, Channel_Left, 3276, 0.7f, 32);
        AddWaveToMix(gateOnTestData, Channel_Right, 1880, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Right, 2480, 1.8f, 45);
        AddWaveToMix(gateOnTestData, Channel_Right, 2276, 0.7f, 32);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 13095);
        AddWaveToMix(gateOnTestData, Channel_Left, 770, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1320, 0.3f, 45);
        AddWaveToMix(gateOnTestData, Channel_Left, 2206, 0.3f, 32);
        AddWaveToMix(gateOnTestData, Channel_Left, 440, 0.1f, 69);
        AddWaveToMix(gateOnTestData, Channel_Left, 3282, 0.2f, 12);
        AddWaveToMix(gateOnTestData, Channel_Right, 1440, 0.5f, 69);
        AddWaveToMix(gateOnTestData, Channel_Right, 2282, 0.5f, 12);

        gateOnTestData = AppendTestWaveSpec(gateOnTest, 0, 10702);
        AddWaveToMix(gateOnTestData, Channel_Left, 660, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Left, 1320, 0.8f, 32);
        AddWaveToMix(gateOnTestData, Channel_Left, 1206, 0.7f, 56);
        AddWaveToMix(gateOnTestData, Channel_Right, 760, 0.2f, 0);
        AddWaveToMix(gateOnTestData, Channel_Right, 1520, 0.7f, 32);
        AddWaveToMix(gateOnTestData, Channel_Right, 1306, 0.4f, 56);
    }

    //Test 6 - Gate off to release
    {
        TestData * gateOffTest = CreateTest("Gate=Off (Release) - Stereo", 44100, StereoMode_Stereo, 1);
        gateOffTest->nodeParameters.insert(std::make_pair("Gate", NodeParameterValue(false)));

        TestWaveSpec * gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 19999, 0.5f, 0.6f);
        AddWaveToMix(gateOffTestData, Channel_Left, 1880, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 1480, 2.8f, 45);
        AddWaveToMix(gateOffTestData, Channel_Left, 3276, 0.7f, 32);
        AddWaveToMix(gateOffTestData, Channel_Right, 1980, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Right, 1380, 1.0f, 45);
        AddWaveToMix(gateOffTestData, Channel_Right, 2276, 0.7f, 32);
        
        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 16723);
        AddWaveToMix(gateOffTestData, Channel_Left, 1440, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 740, 0.8f, 45);
        AddWaveToMix(gateOffTestData, Channel_Right, 1440, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Right, 740, 0.8f, 45);

        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 12000);
        AddWaveToMix(gateOffTestData, Channel_Left, 1640, 1.0f, 0);
        AddWaveToMix(gateOffTestData, Channel_Right, 1640, 1.0f, 0);

        gateOffTestData = AppendTestWaveSpec(gateOffTest, 0, 15700);
        AddWaveToMix(gateOffTestData, Channel_Left, 1770, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Left, 1320, 0.6f, 45);
        AddWaveToMix(gateOffTestData, Channel_Left, 1206, 0.8f, 32);
        AddWaveToMix(gateOffTestData, Channel_Right, 1440, 0.1f, 69);
        AddWaveToMix(gateOffTestData, Channel_Right, 1770, 0.2f, 0);
        AddWaveToMix(gateOffTestData, Channel_Right, 1320, 0.6f, 45);
    }


    return GetTestDataPtr();
}
#include "TestMixerNode.h"

dsp_primitives::IPrimitiveNode * TestMixerNode::CreateNode(int target) const
{
    return new dsp_primitives::MixerNode(target);
}

void TestMixerNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::MixerNode * mixnode = dynamic_cast<dsp_primitives::MixerNode *>(node);
    mixnode->reset();
}

bool TestMixerNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
     dsp_primitives::MixerNode * mixernode = dynamic_cast<dsp_primitives::MixerNode *>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "InputCount")
            mixernode->setInputCount(itr.second.data.i32val);
        else if(itr.first == "Gain1")
            mixernode->setGain(1, itr.second.data.floatval);
        else if(itr.first == "Gain2")
            mixernode->setGain(2, itr.second.data.floatval);
        else if(itr.first == "Gain3")
            mixernode->setGain(3, itr.second.data.floatval);
        else if(itr.first == "Gain4")
            mixernode->setGain(4, itr.second.data.floatval);
        else if(itr.first == "Gain5")
            mixernode->setGain(5, itr.second.data.floatval);
        else if(itr.first == "Gain6")
            mixernode->setGain(6, itr.second.data.floatval);
        else if(itr.first == "Gain7")
            mixernode->setGain(7, itr.second.data.floatval);
        else if(itr.first == "Gain8")
            mixernode->setGain(8, itr.second.data.floatval);
        else if(itr.first == "Pan1")
            mixernode->setPan(1, itr.second.data.floatval);
        else if(itr.first == "Pan2")
            mixernode->setPan(2, itr.second.data.floatval);
        else if(itr.first == "Pan3")
            mixernode->setPan(3, itr.second.data.floatval);
        else if(itr.first == "Pan4")
            mixernode->setPan(4, itr.second.data.floatval);
        else if(itr.first == "Pan5")
            mixernode->setPan(5, itr.second.data.floatval);
        else if(itr.first == "Pan6")
            mixernode->setPan(6, itr.second.data.floatval);
        else if(itr.first == "Pan7")
            mixernode->setPan(7, itr.second.data.floatval);
        else if(itr.first == "Pan8")
            mixernode->setPan(8, itr.second.data.floatval);
        else if(itr.first == "Master")
            mixernode->setMaster(itr.second.data.floatval);
        else
             throw new std::exception((std::string("Unknown Mixer parameter ") + itr.first).c_str());
    }

    return true;
}

std::vector<TestingBase::TestData> * TestMixerNode::GetTestData()
{
     //Test 1 : One stereo bus
    {
        TestData * test = CreateTest("1 Bus Stereo", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Gain1", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(1.0f))));

        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
        AddWaveToMix(testdata, Channel_Left, 440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 840, 1.0f, 0);
    }

    //Test 2 : two stereo busses
    {
        TestData * test = CreateTest("2 Busses Stereo", 44100, StereoMode_Stereo, 2);
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Gain1", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Gain2", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(1.0f))));

        TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
        AddWaveToMix(testdata, Channel_Left, 1440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 1840, 1.0f, 0);

        testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.8f);
        AddWaveToMix(testdata, Channel_Left, 440, 1.0f, 0);
        AddWaveToMix(testdata, Channel_Right, 840, 1.0f, 0);

        testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
        AddWaveToMix(testdata, Channel_Left, 2440, 0.5f, 0);
        AddWaveToMix(testdata, Channel_Left, 1440, 0.5f, 0);
        AddWaveToMix(testdata, Channel_Right, 2140, 0.6f, 45);
        AddWaveToMix(testdata, Channel_Right, 1140, 0.4f, 45);

        testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.8f);
        AddWaveToMix(testdata, Channel_Left, 740, 0.5f, 30);
        AddWaveToMix(testdata, Channel_Right, 640, 0.4f, 35);
    }

    //Test 3 : four stereo busses with panning
    {
        TestData * test = CreateTest("4 Busses with panning", 44100, StereoMode_Stereo, 4);
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(4))));
        test->nodeParameters.insert(std::make_pair("Gain1", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Gain2", NodeParameterValue(static_cast<float>(0.4f))));
        test->nodeParameters.insert(std::make_pair("Gain3", NodeParameterValue(static_cast<float>(0.6f))));
        test->nodeParameters.insert(std::make_pair("Gain4", NodeParameterValue(static_cast<float>(1.3f))));
        test->nodeParameters.insert(std::make_pair("Pan1", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Pan2", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Pan3", NodeParameterValue(static_cast<float>(-0.5f))));
        test->nodeParameters.insert(std::make_pair("Pan4", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(1.0f))));
        
        //Wave 1 on 4 busses
        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 1440, 1.0f, 0);
            AddWaveToMix(testdata, Channel_Right, 1840, 1.0f, 0);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 640, 1.0f, 0);
            AddWaveToMix(testdata, Channel_Right, 840, 1.0f, 0);

            testdata = AppendTestWaveSpec(test, 2, 9999, 1.0f, 1.0f);
            AddWaveToMix(testdata, Channel_Left, 2440, 1.0f, 20);
            AddWaveToMix(testdata, Channel_Right, 2840, 1.0f, 0);

            testdata = AppendTestWaveSpec(test, 3, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 3140, 1.0f, 0);
            AddWaveToMix(testdata, Channel_Right, 3240, 1.0f, 40);
        }

        //Wave 2 on 4 busses
        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 2440, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 1440, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Right, 2140, 0.6f, 45);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.4f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.6f);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Right, 2140, 1.6f, 45);

            testdata = AppendTestWaveSpec(test, 2, 9999, 0.8f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Right, 2140, 1.6f, 45);
            AddWaveToMix(testdata, Channel_Right, 1140, 1.6f, 45);

            testdata = AppendTestWaveSpec(test, 3, 9999, 1.0f, 1.0f);
            AddWaveToMix(testdata, Channel_Left, 1940, 1.0f, 20);
            AddWaveToMix(testdata, Channel_Left, 2840, 1.0f, 10);
            AddWaveToMix(testdata, Channel_Right, 2140, 0.6f, 45);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.6f, 40);
        }

        //Wave 3 on 4 busses
        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.8f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 440, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.8f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Right, 1240, 1.0f, 45);
            AddWaveToMix(testdata, Channel_Right, 1240, 1.0f, 40);

            testdata = AppendTestWaveSpec(test, 2, 9999, 0.8f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Left, 1040, 0.8f, 15);
            AddWaveToMix(testdata, Channel_Right, 2140, 1.2f, 45);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.6f, 40);
            AddWaveToMix(testdata, Channel_Right, 1540, 1.0f, 30);

            testdata = AppendTestWaveSpec(test, 3, 9999, 1.0f, 1.0f);
            AddWaveToMix(testdata, Channel_Left, 940, 1.0f, 20);
            AddWaveToMix(testdata, Channel_Left, 840, 1.0f, 10);
            AddWaveToMix(testdata, Channel_Left, 1040, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Right, 1840, 0.6f, 45);
            AddWaveToMix(testdata, Channel_Right, 940, 0.6f, 40);
            AddWaveToMix(testdata, Channel_Right, 1240, 0.6f, 40);
        }

        //Wave 4 on 4 busses
        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 440, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 540, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 640, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 740, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.5f);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Right, 1040, 1.0f, 45);
            AddWaveToMix(testdata, Channel_Right, 1140, 1.0f, 40);
            AddWaveToMix(testdata, Channel_Right, 1240, 1.0f, 40);
            AddWaveToMix(testdata, Channel_Right, 1340, 1.0f, 40);

            testdata = AppendTestWaveSpec(test, 2, 9999, 0.8f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 480, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 580, 0.5f, 10);
            AddWaveToMix(testdata, Channel_Left, 680, 0.8f, 15);
            AddWaveToMix(testdata, Channel_Left, 780, 0.8f, 15);
            AddWaveToMix(testdata, Channel_Right, 1080, 1.2f, 45);
            AddWaveToMix(testdata, Channel_Right, 1180, 0.6f, 40);
            AddWaveToMix(testdata, Channel_Right, 1380, 1.0f, 30);

            testdata = AppendTestWaveSpec(test, 3, 9999, 1.0f, 1.0f);
            AddWaveToMix(testdata, Channel_Left, 1480, 1.0f, 20);
            AddWaveToMix(testdata, Channel_Left, 1580, 1.0f, 10);
            AddWaveToMix(testdata, Channel_Left, 1680, 1.0f, 15);
            AddWaveToMix(testdata, Channel_Left, 1780, 1.0f, 15);
            AddWaveToMix(testdata, Channel_Right, 2080, 1.2f, 45);
            AddWaveToMix(testdata, Channel_Right, 2180, 0.6f, 40);
            AddWaveToMix(testdata, Channel_Right, 2380, 1.0f, 30);
            AddWaveToMix(testdata, Channel_Right, 1380, 1.0f, 65);
        }
    }

    //Test 4 : Eight stereo busses with panning - high load
    {
        TestData * test = CreateTest("8 Busses High Load", 44100, StereoMode_Stereo, 8);
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(8))));
        for (int i = 1; i <= 8; ++i) 
        {
            test->nodeParameters.insert(std::make_pair("Gain" + std::to_string(i), NodeParameterValue(static_cast<float>(0.75f + (static_cast<float>(i) / 10.0f) ))));
        }
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(1.0f))));

        for(int i=0; i < 8; ++i)
        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, i, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 1480 + (i * 100), 1.0f, 20);
            AddWaveToMix(testdata, Channel_Right, 2280 + (i * 80), 1.0f, 20);
        }
    }

    //Test 5 : Stereo panning
    {
        TestData * test = CreateTest("Stereo Panning Only - 2 busses", 44100, StereoMode_Stereo, 2 );
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Gain1", NodeParameterValue(static_cast<float>(0.6f))));
        test->nodeParameters.insert(std::make_pair("Gain2", NodeParameterValue(static_cast<float>(0.9f))));
        test->nodeParameters.insert(std::make_pair("Pan1", NodeParameterValue(static_cast<float>(-1.0f))));
        test->nodeParameters.insert(std::make_pair("Pan2", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(1.0f))));

        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 640, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 60);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.5f);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Right, 1040, 1.0f, 45);
        }

        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 640, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 1940, 0.5f, 60);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);
            AddWaveToMix(testdata, Channel_Right, 1640, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.5f);
            AddWaveToMix(testdata, Channel_Left, 1840, 1.2f, 20);
            AddWaveToMix(testdata, Channel_Right, 1440, 1.0f, 45);
        }
    }

    //Test 6 : Master gain
    {
        TestData * test = CreateTest("Master Gain Variation - 2 Busses", 44100, StereoMode_Stereo, 2 );
        test->nodeParameters.insert(std::make_pair("InputCount", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Gain1", NodeParameterValue(static_cast<float>(0.6f))));
        test->nodeParameters.insert(std::make_pair("Gain2", NodeParameterValue(static_cast<float>(0.9f))));
        test->nodeParameters.insert(std::make_pair("Master", NodeParameterValue(static_cast<float>(0.5f))));

        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 640, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 940, 0.5f, 60);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.5f);
            AddWaveToMix(testdata, Channel_Left, 840, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Right, 1040, 1.0f, 45);
        }

        {
            TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 9999, 0.5f, 0.8f);
            AddWaveToMix(testdata, Channel_Left, 640, 0.5f, 20);
            AddWaveToMix(testdata, Channel_Left, 1940, 0.5f, 60);
            AddWaveToMix(testdata, Channel_Right, 1140, 0.8f, 45);
            AddWaveToMix(testdata, Channel_Right, 1640, 0.8f, 45);

            testdata = AppendTestWaveSpec(test, 1, 9999, 0.5f, 0.5f);
            AddWaveToMix(testdata, Channel_Left, 1840, 1.2f, 20);
            AddWaveToMix(testdata, Channel_Right, 1440, 1.0f, 45);
        }
    }

    return GetTestDataPtr();
}
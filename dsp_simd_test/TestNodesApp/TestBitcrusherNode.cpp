#include "TestBitcrusherNode.h"

dsp_primitives::IPrimitiveNode * TestBitcrusherNode::CreateNode(int target) const
{
    return new dsp_primitives::BitCrusherNode(target);
}

void TestBitcrusherNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::BitCrusherNode * bitcrushernode = dynamic_cast<dsp_primitives::BitCrusherNode *>(node);
    bitcrushernode->reset();
}

bool TestBitcrusherNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
     dsp_primitives::BitCrusherNode * bitcrushernode = dynamic_cast<dsp_primitives::BitCrusherNode *>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "Bits")
            bitcrushernode->setBits(itr.second.data.floatval);
        else if(itr.first == "LogicMode")
            bitcrushernode->setLogicMode(itr.second.data.i32val);
        else if(itr.first == "Mix")
            bitcrushernode->setMix(itr.second.data.floatval);
        else if(itr.first == "Output")
            bitcrushernode->setOutput(itr.second.data.floatval);
        else if(itr.first == "RateReduction")
            bitcrushernode->setRateReduction(itr.second.data.floatval);
        else
             throw new std::runtime_error((std::string("Unknown Bitcrusher parameter ") + itr.first).c_str());
    }

    return true;
}

void TestBitcrusherNode::GenerateWaves_SingleBus(TestingBase::TestData * test)
{
    TestWaveSpec * testdata = AppendTestWaveSpec(test, 0, 20012, 1.0f, 0.7f);
    AddWaveToMix(testdata, Channel_Left, 1880, 0.2f, 0);
    AddWaveToMix(testdata, Channel_Left, 1480, 0.8f, 45);
    AddWaveToMix(testdata, Channel_Left, 3276, 0.7f, 32);
    AddWaveToMix(testdata, Channel_Right, 2880, 0.2f, 0);
    AddWaveToMix(testdata, Channel_Right, 1780, 0.8f, 45);
    AddWaveToMix(testdata, Channel_Right, 2276, 0.7f, 32);

    testdata = AppendTestWaveSpec(test, 0, 21064, 0.9f, 0.8f);
    AddWaveToMix(testdata, Channel_Left, 640, 1.0f, 0);
    AddWaveToMix(testdata, Channel_Right, 1240, 1.0f, 0);

    testdata = AppendTestWaveSpec(test, 0, 21011, 0.5f, 0.3f);
    AddWaveToMix(testdata, Channel_Left, 770, 0.2f, 0);
    AddWaveToMix(testdata, Channel_Left, 1320, 0.3f, 45);
    AddWaveToMix(testdata, Channel_Left, 2206, 0.3f, 32);
    AddWaveToMix(testdata, Channel_Left, 440, 0.5f, 69);
    AddWaveToMix(testdata, Channel_Left, 3282, 0.2f, 12);
    AddWaveToMix(testdata, Channel_Right, 2770, 0.2f, 0);
    AddWaveToMix(testdata, Channel_Right, 2320, 0.3f, 45);
    AddWaveToMix(testdata, Channel_Right, 1206, 0.5f, 32);
    AddWaveToMix(testdata, Channel_Right, 1440, 0.1f, 69);
    AddWaveToMix(testdata, Channel_Right, 1282, 0.2f, 12);

    testdata = AppendTestWaveSpec(test, 0, 11017, 0.8f, 0.4f);
    AddWaveToMix(testdata, Channel_Left, 1770, 0.5f, 0);
    AddWaveToMix(testdata, Channel_Left, 320, 0.7f, 45);
    AddWaveToMix(testdata, Channel_Left, 1206, 0.3f, 32);
    AddWaveToMix(testdata, Channel_Left, 1440, 0.5f, 22);
    AddWaveToMix(testdata, Channel_Left, 2282, 0.2f, 72);
    AddWaveToMix(testdata, Channel_Right, 770, 0.6f, 10);
    AddWaveToMix(testdata, Channel_Right, 1320, 0.39f, 45);
    AddWaveToMix(testdata, Channel_Right, 2206, 0.5f, 32);
    AddWaveToMix(testdata, Channel_Right, 1840, 0.1f, 69);
    AddWaveToMix(testdata, Channel_Right, 1252, 0.2f, 15);
    AddWaveToMix(testdata, Channel_Right, 4000, 0.2f, 15);
}

void TestBitcrusherNode::GenerateWaves_DoubleBus(TestingBase::TestData * test)
{
    TestWaveSpec * testdata_bus0 = AppendTestWaveSpec(test, 0, 23012, 1.0f, 0.7f);
    TestWaveSpec * testdata_bus1 = AppendTestWaveSpec(test, 1, 23012, 1.0f, 0.7f);
    AddWaveToMix(testdata_bus0, Channel_Left, 1880, 1.2f, 0);
    AddWaveToMix(testdata_bus0, Channel_Left, 1480, 0.8f, 45);
    AddWaveToMix(testdata_bus0, Channel_Left, 3276, 0.7f, 32);
    AddWaveToMix(testdata_bus0, Channel_Right, 2880, 1.2f, 0);
    AddWaveToMix(testdata_bus0, Channel_Right, 1780, 0.8f, 45);
    AddWaveToMix(testdata_bus0, Channel_Right, 2276, 0.7f, 32);
    AddWaveToMix(testdata_bus1, Channel_Left, 2880, 0.6f, 0);
    AddWaveToMix(testdata_bus1, Channel_Left, 480, 0.8f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 1276, 0.9f, 0);
    AddWaveToMix(testdata_bus1, Channel_Right, 3276, 0.5f, 0);

    testdata_bus0 = AppendTestWaveSpec(test, 0, 21064, 0.8f, 0.4f);
    testdata_bus1 = AppendTestWaveSpec(test, 1, 21064, 0.5f, 0.5f);
    AddWaveToMix(testdata_bus0, Channel_Left, 1880, 0.4f, 32);
    AddWaveToMix(testdata_bus0, Channel_Left, 1480, 0.8f, 45);
    AddWaveToMix(testdata_bus0, Channel_Right, 1780, 0.8f, 45);
    AddWaveToMix(testdata_bus0, Channel_Right, 2276, 0.7f, 32);
    AddWaveToMix(testdata_bus1, Channel_Left, 1880, 0.4f, 32);
    AddWaveToMix(testdata_bus1, Channel_Left, 3480, 0.5f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 1780, 0.8f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 2276, 0.7f, 32);

    testdata_bus0 = AppendTestWaveSpec(test, 0, 21011, 0.8f, 0.4f);
    testdata_bus1 = AppendTestWaveSpec(test, 1, 21011, 0.5f, 0.5f);
    AddWaveToMix(testdata_bus0, Channel_Left, 2880, 0.4f, 32);
    AddWaveToMix(testdata_bus0, Channel_Left, 780, 0.8f, 45);
    AddWaveToMix(testdata_bus0, Channel_Right, 780, 0.5f, 45);
    AddWaveToMix(testdata_bus0, Channel_Right, 2276, 0.7f, 32);
    AddWaveToMix(testdata_bus1, Channel_Left, 3880, 0.8f, 32);
    AddWaveToMix(testdata_bus1, Channel_Left, 1980, 0.54f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 1680, 0.67f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 3276, 0.4f, 32);

    testdata_bus0 = AppendTestWaveSpec(test, 0, 11017, 0.8f, 0.47f);
    testdata_bus1 = AppendTestWaveSpec(test, 1, 11017, 0.5f, 0.23f);
    AddWaveToMix(testdata_bus0, Channel_Left, 1880, 0.5f, 32);
    AddWaveToMix(testdata_bus0, Channel_Right, 2780, 0.5f, 45);
    AddWaveToMix(testdata_bus1, Channel_Left, 3880, 0.8f, 32);
    AddWaveToMix(testdata_bus1, Channel_Right, 1680, 0.67f, 45);
    AddWaveToMix(testdata_bus1, Channel_Right, 2276, 0.4f, 32);
}

std::vector<TestingBase::TestData> * TestBitcrusherNode::GetTestData()
{
    //Test 1 - 15 bits, logic mode 1, one input
    /*{
        TestData * test = CreateTest("15 Bits - Logic Mode 1 - one input", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(15.0f))));
        test->nodeParameters.insert(std::make_pair("RateReduction", NodeParameterValue(static_cast<float>(1.2f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.2f))));
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));

        GenerateWaves_SingleBus(test);
    }

    //Test 2 - 14 Bits - Logic Mode 2 - one input
    {
        TestData * test = CreateTest("14 Bits - Logic Mode 2 - one input", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(14.0f))));

        GenerateWaves_SingleBus(test);
    }

    //Test 3 - 13 Bits - Logic Mode 3 - one input
    {
        TestData * test = CreateTest("13 Bits - Logic Mode 3 - one input", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(3))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(13.0f))));

        GenerateWaves_SingleBus(test);
    }
    */
    //Test 4 - 15 bits - logic mode 1 - two inputs
    {
        TestData * test = CreateTest("15 Bits - Logic Mode 1 - two inputs", 44100, StereoMode_Stereo, 2); //Note: 2 busses are created
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(15.0f))));
        test->nodeParameters.insert(std::make_pair("RateReduction", NodeParameterValue(static_cast<float>(1.2f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.2f))));
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));

        GenerateWaves_DoubleBus(test);
    }

    //Test 5 - 12 bits - logic mode 2 - two inputs
    {
        TestData * test = CreateTest("12 Bits - Logic Mode 2 - two inputs", 44100, StereoMode_Stereo, 2); //Note: 2 busses are created
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<float>(12.0f))));

        GenerateWaves_DoubleBus(test);
    }


     //Test 6 - 7 bits, logic mode 1, one input
    {
        TestData * test = CreateTest("7 Bits - Logic Mode 1 - one input", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(7.0f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Output", NodeParameterValue(static_cast<float>(1.0f))));

        GenerateWaves_SingleBus(test);
    }

    //Test 7 - 4 bits - logic mode 2 - two inputs
    {
        TestData * test = CreateTest("4 Bits - Logic Mode 2 - two inputs", 44100, StereoMode_Stereo, 2); //Note: 2 busses are created
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(4.0f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.9f))));

        GenerateWaves_DoubleBus(test);
    }

    //Test 8 - 2 bits - logic mode 1 - two inputs
    {
        TestData * test = CreateTest("2 Bits - Logic Mode 1 - two inputs", 44100, StereoMode_Stereo, 2); //Note: 2 busses are created
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(2.0f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.9f))));

        GenerateWaves_DoubleBus(test);
    }

    //Test 9 - 15 bits - logic mode 1 - two inputs
    {
        TestData * test = CreateTest("15 Bits - Logic Mode 2 - two inputs", 44100, StereoMode_Stereo, 2); //Note: 2 busses are created
        test->nodeParameters.insert(std::make_pair("LogicMode", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Bits", NodeParameterValue(static_cast<int>(15.0f))));
        test->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.5f))));

        GenerateWaves_DoubleBus(test);
    }


    return GetTestDataPtr();
}


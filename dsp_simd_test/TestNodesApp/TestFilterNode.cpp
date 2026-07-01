#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#include "TestFilterNode.h"

dsp_primitives::IPrimitiveNode * TestFilterNode::CreateNode(int target) const
{
    return new dsp_primitives::FilterNode(target);
}

void TestFilterNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::FilterNode * filtnode = dynamic_cast<dsp_primitives::FilterNode *>(node);
    filtnode->reset();
}

Debug::Logger * TestFilterNode::GetLog(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::FilterNode * filternode = dynamic_cast<dsp_primitives::FilterNode *>(node);
    auto & log = filternode->GetLog();
    return &log;
}



bool TestFilterNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
     dsp_primitives::FilterNode * filternode = dynamic_cast<dsp_primitives::FilterNode *>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "Cutoff")
            filternode->setCutoff(itr.second.data.floatval);
        else if(itr.first == "Resonance")
            filternode->setResonance(itr.second.data.floatval);
        else if(itr.first == "Mix")
            filternode->setMix(itr.second.data.floatval);
        else
            throw new std::runtime_error((std::string("Unknown FilterNode parameter ") + itr.first).c_str());
    }

    return true;
}

std::vector<TestingBase::TestData> * TestFilterNode::GetTestData()
{
    //---------------------------------------------------------------
    {
        //Test 1: Default Low Cutoff
        
        TestData * lowCutoffTest = CreateTest("Default Low Cutoff", 44100, StereoMode_Stereo, 1);
        lowCutoffTest->nodeParameters.insert(std::make_pair("Cutoff", NodeParameterValue(static_cast<float>(1400.0f))));
        lowCutoffTest->nodeParameters.insert(std::make_pair("Resonance", NodeParameterValue(static_cast<float>(0.1f))));
        lowCutoffTest->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(1.0f))));

        //Waveform 1 - single wave
        TestWaveSpec * lowCutoffTestData = AppendTestWaveSpec(lowCutoffTest, 0, 10000);
        AddWaveToMix(lowCutoffTestData, Channel_Left, 440, 1.0f, 0);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 980, 0.6f, 32);

        //Waveform 2 - 2 waves mixed together
        lowCutoffTestData = AppendTestWaveSpec(lowCutoffTest, 0, 12003);
        AddWaveToMix(lowCutoffTestData, Channel_Left, 1440, 0.5f, 10);
        AddWaveToMix(lowCutoffTestData, Channel_Left, 1200, 1.5f, 0);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 970, 0.5f, 72);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 1500, 0.5f, 32);

        //Waveform 3- 3 waves mixed together
        lowCutoffTestData = AppendTestWaveSpec(lowCutoffTest, 0, 10007);
        AddWaveToMix(lowCutoffTestData, Channel_Left,  1400, 0.33f, 10);
        AddWaveToMix(lowCutoffTestData, Channel_Left,  1423, 0.30f, 10);
        AddWaveToMix(lowCutoffTestData, Channel_Left,  1481, 0.25f, 10);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 1560, 0.5f, 10);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 1900, 0.4f, 30);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 2200, 0.2f, 40);
        AddWaveToMix(lowCutoffTestData, Channel_Right, 2800, 0.5f, 40);
    }

    //---------------------------------------------------------------
    //Test 2: Default Low Cutoff
    {
        TestData * highCutoffResonanceTest = CreateTest("High Cutoff High Resonance", 44100,StereoMode_Stereo, 1);
        highCutoffResonanceTest->nodeParameters.insert(std::make_pair("Cutoff", NodeParameterValue(static_cast<float>(5000.0f))));
        highCutoffResonanceTest->nodeParameters.insert(std::make_pair("Resonance", NodeParameterValue(static_cast<float>(0.8f))));
        highCutoffResonanceTest->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(1.0f))));

        //Waveform 1 - single wave
        TestWaveSpec * highCutoffResonanceTestData = AppendTestWaveSpec(highCutoffResonanceTest, 0, 10000);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 1000, 0.5f, 0);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 980, 0.6f, 32);

        //Waveform 2 - 2 waves mixed together
        highCutoffResonanceTestData = AppendTestWaveSpec(highCutoffResonanceTest, 0, 10001);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left,  1900, 0.5f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left,  1300, 0.5f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 1970, 0.5f, 22);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 1500, 0.5f, 32);

        //Waveform 3- 3 waves mixed together
        highCutoffResonanceTestData = AppendTestWaveSpec(highCutoffResonanceTest, 0, 9999);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 200, 0.33f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 423, 1.30f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 2581, 0.25f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 560, 0.5f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 900, 0.4f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 1200, 0.2f, 20);

        //Waveform 4- 4 waves mixed together
        highCutoffResonanceTestData = AppendTestWaveSpec(highCutoffResonanceTest, 0, 23001);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 1200, 0.33f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 423, 0.30f, 20);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 2581, 0.25f, 30);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Left, 3581, 0.25f, 40);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 1560, 0.5f, 10);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 900, 1.4f, 32);
        AddWaveToMix(highCutoffResonanceTestData, Channel_Right, 3200, 0.2f, 66);
    }

    //--------------------------------------------------------------------------------
    //Test 3 : Dry / Wet mix
    {
        TestData * dryWetMixTest = CreateTest("Dry/Wet Mix", 44100, StereoMode_Stereo, 1);
        dryWetMixTest->nodeParameters.insert(std::make_pair("Cutoff", NodeParameterValue(static_cast<float>(2000.0f))));
        dryWetMixTest->nodeParameters.insert(std::make_pair("Resonance", NodeParameterValue(static_cast<float>(0.5f))));
        dryWetMixTest->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.7f))));

        
        //Waveform 1 - single wave
        TestWaveSpec * dryWetMixTestData = AppendTestWaveSpec(dryWetMixTest, 0, 10000);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 1700, 0.5f, 0);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 1300, 0.6f, 32);

        //Waveform 2 - 2 waves mixed together
        dryWetMixTestData = AppendTestWaveSpec(dryWetMixTest, 0, 10002);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 1900, 0.5f, 10);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 1300, 0.5f, 10);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 2970, 1.5f, 55);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 1500, 0.5f, 43);

        //Waveform 3- 3 waves mixed together
        dryWetMixTestData = AppendTestWaveSpec(dryWetMixTest, 0, 9999);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 1200, 1.33f, 17);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 1423, 1.30f, 80);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 581, 0.65f, 20);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 1520, 0.5f, 30);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 1900, 0.4f, 80);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 1100, 0.8f, 20);

        //Waveform 4- 4 waves mixed together
        dryWetMixTestData = AppendTestWaveSpec(dryWetMixTest, 0, 23001);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 2200, 0.53f, 90);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 2423, 0.80f, 50);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 2581, 0.545f, 130);
        AddWaveToMix(dryWetMixTestData, Channel_Left, 3581, 0.95f, 45);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 560, 0.5f, 10);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 900, 0.7f, 32);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 400, 1.8f, 120);
        AddWaveToMix(dryWetMixTestData, Channel_Right, 200, 0.8f, 66);
    }

    //--------------------------------------------------------------------------------
    //Test 4 : Mono processing
    {
        TestData * monoTest = CreateTest("Mono Processing",44100, StereoMode_Mono, 1);
        monoTest->nodeParameters.insert(std::make_pair("Cutoff", NodeParameterValue(static_cast<float>(3000.0f))));
        monoTest->nodeParameters.insert(std::make_pair("Resonance", NodeParameterValue(static_cast<float>(0.3f))));
        monoTest->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(1.0f))));

        //Waveform 1- 4 waves mixed together
        TestWaveSpec * monoTestData = AppendTestWaveSpec(monoTest, 0, 13000);
        AddWaveToMix(monoTestData, Channel_Left, 2200, 0.53f, 90);
        AddWaveToMix(monoTestData, Channel_Left, 2423, 0.80f, 50);
        AddWaveToMix(monoTestData, Channel_Left, 2581, 0.545f, 130);
        AddWaveToMix(monoTestData, Channel_Left, 3581, 0.95f, 45);

        monoTestData = AppendTestWaveSpec(monoTest, 0, 10075);
        AddWaveToMix(monoTestData, Channel_Left, 1200, 0.53f, 0);
        AddWaveToMix(monoTestData, Channel_Left, 1423, 1.80f, 50);
        AddWaveToMix(monoTestData, Channel_Left, 1581, 0.545f, 30);
        AddWaveToMix(monoTestData, Channel_Left, 2581, 0.95f, 45);

        monoTestData = AppendTestWaveSpec(monoTest, 0, 10001);
        AddWaveToMix(monoTestData, Channel_Left, 200, 0.53f, 0);
        AddWaveToMix(monoTestData, Channel_Left, 423, 1.20f, 50);
        AddWaveToMix(monoTestData, Channel_Left, 581, 1.545f, 30);
        AddWaveToMix(monoTestData, Channel_Left, 581, 0.35f, 45);

        monoTestData = AppendTestWaveSpec(monoTest, 0, 9999);
        AddWaveToMix(monoTestData, Channel_Left, 1200, 0.53f, 0);
        AddWaveToMix(monoTestData, Channel_Left, 423, 0.20f, 50);
        AddWaveToMix(monoTestData, Channel_Left, 2581, 0.45f, 30);
        AddWaveToMix(monoTestData, Channel_Left, 581, 1.35f, 45);

        monoTestData = AppendTestWaveSpec(monoTest, 0, 23001);
        AddWaveToMix(monoTestData, Channel_Left, 200, 0.53f, 0);
        AddWaveToMix(monoTestData, Channel_Left, 2423, 0.30f, 55);
        AddWaveToMix(monoTestData, Channel_Left, 1581, 0.75f, 25);
        AddWaveToMix(monoTestData, Channel_Left, 2581, 1.35f, 40);
    }

    //--------------------------------------------------------------------------------
    //Test 5 : Back to Stereo processing
    {
        TestData * stereoTest = CreateTest("Stereo Processing", 44100, StereoMode_Stereo, 1);
        
        //Waveform 1 - single wave
        TestWaveSpec * stereoTestData = AppendTestWaveSpec(stereoTest, 0, 10000);
        AddWaveToMix(stereoTestData, Channel_Left, 200, 0.53f, 20);
        AddWaveToMix(stereoTestData, Channel_Left, 3423, 0.30f, 55);
        AddWaveToMix(stereoTestData, Channel_Left, 1581, 0.245f, 130);
        AddWaveToMix(stereoTestData, Channel_Left, 4581, 0.25f, 145);
        AddWaveToMix(stereoTestData, Channel_Right, 1560, 0.8f, 10);
        AddWaveToMix(stereoTestData, Channel_Right, 2900, 1.7f, 32);
        AddWaveToMix(stereoTestData, Channel_Right, 3400, 1.2f, 120);
        AddWaveToMix(stereoTestData, Channel_Right, 2200, 0.4f, 66);

        stereoTestData = AppendTestWaveSpec(stereoTest, 0, 10075);
        AddWaveToMix(stereoTestData, Channel_Left, 4200, 0.53f, 90);
        AddWaveToMix(stereoTestData, Channel_Left, 3423, 0.80f, 50);
        AddWaveToMix(stereoTestData, Channel_Left, 2581, 0.545f, 30);
        AddWaveToMix(stereoTestData, Channel_Left, 1581, 0.85f, 45);
        AddWaveToMix(stereoTestData, Channel_Right, 3360, 0.5f, 10);
        AddWaveToMix(stereoTestData, Channel_Right, 2000, 0.8f, 32);
        AddWaveToMix(stereoTestData, Channel_Right, 3400, 0.3f, 90);
        AddWaveToMix(stereoTestData, Channel_Right, 1200, 1.8f, 66);

        stereoTestData = AppendTestWaveSpec(stereoTest, 0, 10001);
        AddWaveToMix(stereoTestData, Channel_Left, 1200, 0.53f, 95);
        AddWaveToMix(stereoTestData, Channel_Left, 2423, 0.80f, 51);
        AddWaveToMix(stereoTestData, Channel_Left, 1581, 0.545f, 11);
        AddWaveToMix(stereoTestData, Channel_Left, 2581, 0.85f, 145);
        AddWaveToMix(stereoTestData, Channel_Right, 1560, 0.5f, 60);
        AddWaveToMix(stereoTestData, Channel_Right, 2900, 0.7f, 132);
        AddWaveToMix(stereoTestData, Channel_Right, 1400, 0.8f, 100);
        AddWaveToMix(stereoTestData, Channel_Right, 400, 0.2f, 100);
        AddWaveToMix(stereoTestData, Channel_Right, 2200, 0.8f, 66);

        stereoTestData = AppendTestWaveSpec(stereoTest, 0, 9999);
        AddWaveToMix(stereoTestData, Channel_Left, 2200, 0.53f, 90);
        AddWaveToMix(stereoTestData, Channel_Left, 2223, 1.80f, 150);
        AddWaveToMix(stereoTestData, Channel_Left, 2281, 0.545f, 130);
        AddWaveToMix(stereoTestData, Channel_Left, 3281, 0.95f, 45);
        AddWaveToMix(stereoTestData, Channel_Right, 520, 0.5f, 10);
        AddWaveToMix(stereoTestData, Channel_Right, 920, 0.7f, 32);
        AddWaveToMix(stereoTestData, Channel_Right, 420, 1.8f, 120);
        AddWaveToMix(stereoTestData, Channel_Right, 220, 0.8f, 66);

        stereoTestData = AppendTestWaveSpec(stereoTest, 0, 23001);
        AddWaveToMix(stereoTestData, Channel_Left, 2200, 0.13f, 90);
        AddWaveToMix(stereoTestData, Channel_Left, 3423, 0.20f, 50);
        AddWaveToMix(stereoTestData, Channel_Left, 2581, 0.345f, 130);
        AddWaveToMix(stereoTestData, Channel_Left, 3581, 0.45f, 145);
        AddWaveToMix(stereoTestData, Channel_Right, 2560, 0.1f, 10);
        AddWaveToMix(stereoTestData, Channel_Right, 3900, 0.2f, 32);
        AddWaveToMix(stereoTestData, Channel_Right, 4400, 1.3f, 120);
        AddWaveToMix(stereoTestData, Channel_Right, 3200, 0.4f, 166);
    }

    //---------------------------------------------------------------------------------
    //Test 6 : Extreme
    {
        TestData * extemeTest = CreateTest("Extreme Values", 44100, StereoMode_Stereo, 1);
        extemeTest->nodeParameters.insert(std::make_pair("Cutoff", NodeParameterValue(static_cast<float>(100.0f))));
        extemeTest->nodeParameters.insert(std::make_pair("Resonance", NodeParameterValue(static_cast<float>(1.0f))));
        extemeTest->nodeParameters.insert(std::make_pair("Mix", NodeParameterValue(static_cast<float>(0.5f))));

        TestWaveSpec * extemeTestData = AppendTestWaveSpec(extemeTest, 0, 10000);
        AddWaveToMix(extemeTestData, Channel_Left, 200, 0.53f, 20);
        AddWaveToMix(extemeTestData, Channel_Left, 423, 0.30f, 55);
        AddWaveToMix(extemeTestData, Channel_Left, 581, 0.245f, 130);
        AddWaveToMix(extemeTestData, Channel_Left, 581, 0.25f, 145);
        AddWaveToMix(extemeTestData, Channel_Right, 4560, 0.8f, 10);
        AddWaveToMix(extemeTestData, Channel_Right, 2900, 1.7f, 32);
        AddWaveToMix(extemeTestData, Channel_Right, 4400, 1.2f, 120);
        AddWaveToMix(extemeTestData, Channel_Right, 2200, 0.4f, 66);

        extemeTestData = AppendTestWaveSpec(extemeTest, 0, 10000);
        AddWaveToMix(extemeTestData, Channel_Left, 4200, 0.53f, 90);
        AddWaveToMix(extemeTestData, Channel_Left, 3423, 0.80f, 50);
        AddWaveToMix(extemeTestData, Channel_Left, 2581, 0.545f, 30);
        AddWaveToMix(extemeTestData, Channel_Left, 1581, 0.85f, 45);
        AddWaveToMix(extemeTestData, Channel_Right, 3360, 0.5f, 10);
        AddWaveToMix(extemeTestData, Channel_Right, 2000, 0.8f, 32);
        AddWaveToMix(extemeTestData, Channel_Right, 3400, 0.3f, 90);
        AddWaveToMix(extemeTestData, Channel_Right, 1200, 1.8f, 66);

        extemeTestData = AppendTestWaveSpec(extemeTest, 0, 10006);
        AddWaveToMix(extemeTestData, Channel_Left, 200, 0.53f, 95);
        AddWaveToMix(extemeTestData, Channel_Left, 423, 0.80f, 51);
        AddWaveToMix(extemeTestData, Channel_Left, 581, 0.545f, 11);
        AddWaveToMix(extemeTestData, Channel_Left, 581, 0.85f, 145);
        AddWaveToMix(extemeTestData, Channel_Right, 560, 0.5f, 60);
        AddWaveToMix(extemeTestData, Channel_Right, 900, 0.7f, 132);
        AddWaveToMix(extemeTestData, Channel_Right, 400, 0.8f, 100);
        AddWaveToMix(extemeTestData, Channel_Right, 200, 0.8f, 66);

        extemeTestData = AppendTestWaveSpec(extemeTest, 0, 9999);
        AddWaveToMix(extemeTestData, Channel_Left, 2200, 0.53f, 90);
        AddWaveToMix(extemeTestData, Channel_Left, 2223, 1.80f, 150);
        AddWaveToMix(extemeTestData, Channel_Left, 2281, 0.545f, 130);
        AddWaveToMix(extemeTestData, Channel_Left, 3281, 0.95f, 45);
        AddWaveToMix(extemeTestData, Channel_Right, 520, 0.5f, 10);
        AddWaveToMix(extemeTestData, Channel_Right, 920, 0.7f, 32);
        AddWaveToMix(extemeTestData, Channel_Right, 420, 1.8f, 120);
        AddWaveToMix(extemeTestData, Channel_Right, 220, 0.8f, 66);

        extemeTestData = AppendTestWaveSpec(extemeTest, 0, 23001);
        AddWaveToMix(extemeTestData, Channel_Left, 2200, 0.13f, 90);
        AddWaveToMix(extemeTestData, Channel_Left, 3423, 0.20f, 50);
        AddWaveToMix(extemeTestData, Channel_Left, 2581, 0.345f, 130);
        AddWaveToMix(extemeTestData, Channel_Left, 3581, 0.45f, 145);
        AddWaveToMix(extemeTestData, Channel_Right, 2560, 0.1f, 10);
        AddWaveToMix(extemeTestData, Channel_Right, 3900, 0.2f, 32);
        AddWaveToMix(extemeTestData, Channel_Right, 4400, 1.3f, 120);
        AddWaveToMix(extemeTestData, Channel_Right, 3200, 0.4f, 166);
    }

    return GetTestDataPtr();
}


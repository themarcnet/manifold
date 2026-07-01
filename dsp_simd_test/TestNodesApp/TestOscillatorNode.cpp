#include <fstream>
#include <manifold/debugging/Logging.h>

#include "TestOscillatorNode.h"

dsp_primitives::IPrimitiveNode * TestOscillatorNode::CreateNode(int target) const
{
    return new dsp_primitives::OscillatorNode(target);
}

void TestOscillatorNode::ResetNode(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::OscillatorNode * oscnode = dynamic_cast<dsp_primitives::OscillatorNode *>(node);
    oscnode->resetPhase();
}

void TestOscillatorNode::AfterPrepare(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::OscillatorNode * oscnode = dynamic_cast<dsp_primitives::OscillatorNode *>(node);
    oscnode->resetPhase();
}

Debug::Logger * TestOscillatorNode::GetLog(dsp_primitives::IPrimitiveNode * node)
{
    dsp_primitives::OscillatorNode * oscnode = dynamic_cast<dsp_primitives::OscillatorNode *>(node);
    Debug::Logger & log = oscnode->GetLog();
    return &log;
}

bool TestOscillatorNode::ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters)
{
    dsp_primitives::OscillatorNode * oscnode = dynamic_cast<dsp_primitives::OscillatorNode *>(node);

    for(const auto & itr : parameters.nodeParameters)
    {
        if(itr.first == "Frequency")
            oscnode->setFrequency(itr.second.data.floatval);
        else if(itr.first == "Amplitude")
            oscnode->setAmplitude(itr.second.data.floatval);
        else if(itr.first == "Enabled")
            oscnode->setEnabled(itr.second.data.bval);
        else if(itr.first == "Waveform")
            oscnode->setWaveform(itr.second.data.i32val);
        else if(itr.first == "Drive")
            oscnode->setDrive(itr.second.data.floatval);
        else if(itr.first == "DriveShape")
            oscnode->setDriveShape(itr.second.data.i32val);
        else if(itr.first == "DriveBias")
            oscnode->setDriveBias(itr.second.data.floatval);
        else if(itr.first == "DriveMix")
            oscnode->setDriveMix(itr.second.data.floatval);
        else if(itr.first == "RenderMode")
            oscnode->setRenderMode(itr.second.data.i32val);
        else if(itr.first == "AdditivePartials")
            oscnode->setAdditivePartials(itr.second.data.i32val);
        else if(itr.first == "AdditiveTilt")
            oscnode->setAdditiveTilt(itr.second.data.floatval);
        else if(itr.first == "AdditiveDrift")
            oscnode->setAdditiveDrift(itr.second.data.floatval);
        else if(itr.first == "PulseWidth")
            oscnode->setPulseWidth(itr.second.data.floatval);
        else if(itr.first == "Unison")
            oscnode->setUnison(itr.second.data.i32val);
        else if(itr.first == "Detune")
            oscnode->setDetune(itr.second.data.floatval);
        else if(itr.first == "Spread")
            oscnode->setSpread(itr.second.data.floatval);
        else if(itr.first == "SyncEnabled")
            oscnode->setSyncEnabled(itr.second.data.bval);
        else
             throw new std::runtime_error((std::string("Unknown Oscillator parameter ") + itr.first).c_str());
    }

    return true;
}

std::vector<TestingBase::TestData> * TestOscillatorNode::GetTestData()
{
    
    {
        //Test 1 : Sine - sync enabled
        TestData * test = CreateTest("Sine - Constant - Sync Enabled", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(440.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.7f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(true)));

        AppendSilenceTestWaveSpec(test, 0, 10121);
        TestWaveSpec * syncwave = AppendTestWaveSpec(test, 0, 2);
        AddWaveToMix(syncwave, Channel_Left, 440, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 440, 1.0f, 0.0f);
        AppendSilenceTestWaveSpec(test, 0, 2);
        syncwave = AppendTestWaveSpec(test, 0, 30000);
        AddWaveToMix(syncwave, Channel_Left, 440, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 440, 1.0f, 0.0f);
    }
    
    {
        //Test 2 : Sine
        TestData * test = CreateTest("Sine - Constant - Sync disabled", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 3 : Sine
        TestData * test = CreateTest("Sine - Smoothing to new values", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(3200.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(5.0f))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }
    

    {
        //Test 4 : Saw Constant - sync enabled
        TestData * test = CreateTest("Saw - Constant - sync enabled", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(3400.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(5.0f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        
        AppendSilenceTestWaveSpec(test, 0, 2047);
        TestWaveSpec * syncwave = AppendTestWaveSpec(test, 0, 2);
        AddWaveToMix(syncwave, Channel_Left, 667, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 890, 1.0f, 0.0f);
        AppendSilenceTestWaveSpec(test, 0, 2);
        syncwave = AppendTestWaveSpec(test, 0, 15000);
        AddWaveToMix(syncwave, Channel_Left, 1200, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 1200, 1.0f, 0.0f);
    }
    
    {
        //Test 5 : Saw Constant - sync disabled
        TestData * test = CreateTest("Saw - Constant - Sync disabled", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }
    
    {
        //Test 6 : Saw Drive
        TestData * test = CreateTest("Saw Drive shape 1 - Smoothing", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(220.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.9f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(8.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.15f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 7 : Saw Drive 2
        TestData * test = CreateTest("Saw Drive shape 2 - constant", 44100, StereoMode_Stereo, 1);
        test->resetInstances = true; //Reset instances to prevent phase floating point error from getting too big
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(2))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

     {
        //Test 8 : Saw Drive 3
        TestData * test = CreateTest("Saw Drive shape 3 - constant", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(3))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 9 : Saw Drive with sync
        TestData * test = CreateTest("Saw Drive shape 1 sync", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(1))));

        AppendSilenceTestWaveSpec(test, 0, 121);
        TestWaveSpec * syncwave = AppendTestWaveSpec(test, 0, 2);
        AddWaveToMix(syncwave, Channel_Left, 440, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 440, 1.0f, 0.0f);
        AppendSilenceTestWaveSpec(test, 0, 2);
        syncwave = AppendTestWaveSpec(test, 0, 30000);
        AddWaveToMix(syncwave, Channel_Left, 440, 1.0f, 0.0f);
        AddWaveToMix(syncwave, Channel_Right, 440, 1.0f, 0.0f);
    }
    
     {
        //Test 10 : Square Constant - no drive
        TestData * test = CreateTest("Square constant", 44100, StereoMode_Stereo, 1);
        test->resetInstances = true;
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(3240.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.7f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(true)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

     {
        //Test 11 : Square Drive shape 1
        TestData * test = CreateTest("Sqr Drive shape 1: Smoothing", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(220.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.7f))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(8.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.15f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.6f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 12 : Square Drive 2
        TestData * test = CreateTest("Sqr Drive shape 2 - constant", 44100, StereoMode_Stereo, 1);
        test->resetInstances = true; //Reset instances to prevent phase floating point error from getting too big
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(2))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

     {
        //Test 13 : Square Drive 3
        TestData * test = CreateTest("Sqr Drive shape 3 - constant", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(3))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
     }

     {
        //Test 14 : Triagle Constant - no drive
        TestData * test = CreateTest("Triangle constant", 44100, StereoMode_Stereo, 1);
        test->resetInstances = true;
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(2200.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.2f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(3))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(true)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
     }

     {
        //Test 15 : Triangle Drive shape 1
        TestData * test = CreateTest("Tri Drive shape 1: Smoothing", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(220.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.7f))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(8.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.15f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.6f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

     {
        //Test 16 : Triangle Drive 2
        TestData * test = CreateTest("Tri Drive shape 2 - constant", 44100, StereoMode_Stereo, 1);
        test->resetInstances = true; //Reset instances to prevent phase floating point error from getting too big
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(2))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

     {
        //Test 17 : Triangle Drive 3
        TestData * test = CreateTest("Tri Drive shape 3 - constant", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(3))));
        
        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    /*
    //=====
    {
        //Test 9 : Square Drive
        TestData * test = CreateTest("Sqr Drv 2: Smooth to new vals", 44100, StereoMode_Stereo, 1);
        test->tolerance = 1.5f; //Allow more tollerance, due to rounding issues from some double (the base implementation uses) vs float (simd version uses)
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(220.f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(2.5f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(10.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(2))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.45f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    
    {
        //Test 7 : Triangle Drive
        TestData * test = CreateTest("Triangle Drv 3: Smooth to new vals", 44100, StereoMode_Stereo, 1);
        test->tolerance = 1.5f; //Allow more tollerance, due to rounding issues from some double (the base implementation uses) vs float (simd version uses)
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(440.f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(3))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(5.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(3))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.25f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.3f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }


    {
        //Test 6 : Blend
        TestData * test = CreateTest("Blend", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(440.f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(1.5f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(4))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(3.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(-0.1f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.65f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }
    
    {
        //Test 4 : Pulse
        TestData * test = CreateTest("Pulse", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(550.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.75f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(6))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(4.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(3))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.7f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.23f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 5 : Additive Render
        TestData * test = CreateTest("Additive Render", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(440.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(2.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("AdditivePartials", NodeParameterValue(static_cast<int>(8))));
        test->nodeParameters.insert(std::make_pair("AdditiveTilt", NodeParameterValue(static_cast<float>(0.35f))));
        test->nodeParameters.insert(std::make_pair("AdditiveDrift", NodeParameterValue(static_cast<float>(0.25f))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 6 : Saw Unison
        TestData * test = CreateTest("Saw Unison", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(330.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.85f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(1.0f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(4))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(18.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.8f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }

    {
        //Test 6 : SuperSaw
        TestData * test = CreateTest("SawSuperSaw", 44100, StereoMode_Stereo, 1);
        test->nodeParameters.insert(std::make_pair("Enabled", NodeParameterValue(true)));
        test->nodeParameters.insert(std::make_pair("Frequency", NodeParameterValue(static_cast<float>(220.0f))));
        test->nodeParameters.insert(std::make_pair("Amplitude", NodeParameterValue(static_cast<float>(0.7f))));
        test->nodeParameters.insert(std::make_pair("Waveform", NodeParameterValue(static_cast<int>(7))));
        test->nodeParameters.insert(std::make_pair("Drive", NodeParameterValue(static_cast<float>(2.5f))));
        test->nodeParameters.insert(std::make_pair("DriveShape", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("DriveBias", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("DriveMix", NodeParameterValue(static_cast<float>(0.75f))));
        test->nodeParameters.insert(std::make_pair("RenderMode", NodeParameterValue(static_cast<int>(0))));
        test->nodeParameters.insert(std::make_pair("PulseWidth", NodeParameterValue(static_cast<float>(0.5f))));
        test->nodeParameters.insert(std::make_pair("Unison", NodeParameterValue(static_cast<int>(1))));
        test->nodeParameters.insert(std::make_pair("Detune", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("Spread", NodeParameterValue(static_cast<float>(0.0f))));
        test->nodeParameters.insert(std::make_pair("SyncEnabled", NodeParameterValue(false)));

        AppendSilenceTestWaveSpec(test, 0, 262149);
    }
    */
    return GetTestDataPtr();
}

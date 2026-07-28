
#include <stdio.h>
#include <fstream>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#include <manifold/debugging/Logging.h>
#include <manifold/highway/HighwayDebug.h>

#include <dsp/core/nodes/PrimitiveNodes.h>
#include <dsp/core/nodes/OscillatorNode_Common.h>

#include "TestADSRNode.h"
#include "TestBitcrusherNode.h"
#include "TestFilterNode.h"
#include "TestGainNode.h"
#include "TestMixerNode.h"
#include "TestOscillatorNode.h"

// default implementation
template <typename T>
struct TypeName
{
    static const char* Get()
    {
        return typeid(T).name();
    }
};



template<typename F>
static F pow_wrapper(F a, F b)
{
    return static_cast<F>(std::pow(a, b));
}



template<typename F>
static bool compareFloats(F a, F b, const F tolerance)
{   
    if(std::memcmp(&a, &b, sizeof(F)) == 0)
        return true;

    if(std::isfinite(a) && !std::isfinite(b))
        return false;

    if(!std::isfinite(a) && std::isfinite(b))
        return false;

    if(!std::isfinite(a) && !std::isfinite(b))
        return true;

    if(!std::isnan(a) && std::isnan(b))
        return false;

    if(std::isnan(a) && !std::isnan(b))
        return false;

    if(std::isnan(a) && std::isnan(b))
        return true;
        
    F absa = std::abs(a);
    F absb = std::abs(b);
    F logab = 0;
    F flogab = 0;
    F maxab = (absa > absb) ? absa : absb;
    F minab = (absa < absb) ? absa : absb;

    int abfactor = 0;
    if(maxab > static_cast<F>(0))
    {
        logab = static_cast<F>(std::log10(maxab));
        flogab = static_cast<F>(std::floor(logab));
        abfactor = static_cast<int>(flogab); 
    }

        
    //Zero fix / approx zero fix
    F maxdiff = tolerance;
    if((absa <= std::numeric_limits<F>::epsilon()) || (absb <= std::numeric_limits<F>::epsilon()))
    {
        //Allow greater error if one value is zero
        maxdiff = tolerance * pow_wrapper(10.0f,  static_cast<F>(abfactor) / 2);
    }
    else
    {

        if(abfactor > 0)
            maxdiff = tolerance * pow_wrapper(10.0f, static_cast<F>(abfactor) - 1);
        else
            maxdiff = tolerance * pow_wrapper(10.0f, static_cast<F>(abfactor) + 1);

        
        bool signa = (a >= 0);
        bool signb = (b >= 0);
        if(signa != signb)
            maxdiff /= 2;
    }

    F diff = maxab - minab;
    if(diff > maxdiff)
        return false;

    return true;
}

static std::string GetDebugLogPath(const char * testname,  const char * tgtName, dsp_primitives::IPrimitiveNode * node)
{
    const char * nodetype = node->getNodeType();
    if(nodetype == NULL)
        nodetype = node->getNodeType();


    std::stringstream path;
    path << nodetype  << "_" << testname << "_" << tgtName << ".log";
    
    return path.str();
}

template<class TESTCLASS>
static void EraseLog(TESTCLASS & testclass, dsp_primitives::IPrimitiveNode * nodea, dsp_primitives::IPrimitiveNode * nodeb)
{
#ifdef ENABLE_LOGGING
    Debug::Logger * baselog = testclass.GetLog(nodea);
    Debug::Logger * simdlog = testclass.GetLog(nodeb);

    if(baselog != NULL)
        baselog->Clear();

    if(simdlog != NULL)
        simdlog->Clear();
#endif
}

template<class TESTCLASS>
static void SetLogStart(TESTCLASS & testclass, dsp_primitives::IPrimitiveNode * nodea, dsp_primitives::IPrimitiveNode * nodeb, size_t val)
{
#ifdef ENABLE_LOGGING
    Debug::Logger * baselog = testclass.GetLog(nodea);
    Debug::Logger * simdlog = testclass.GetLog(nodeb);

    if(baselog != NULL)
        baselog->SetLogStartValues(val);

    if(simdlog != NULL)
        simdlog->SetLogStartValues(val);
#endif
}

template<class TESTCLASS>
static void WriteDebugLog( const char * testname,  const char * tgtName,
                          TESTCLASS & testclass, 
                          dsp_primitives::IPrimitiveNode * nodea, dsp_primitives::IPrimitiveNode * nodeb)
{
#ifdef ENABLE_LOGGING
    Debug::Logger * baselog = testclass.GetLog(nodea);
    Debug::Logger * simdlog = testclass.GetLog(nodeb);

    if((baselog == NULL) || (simdlog == NULL))
        return;

    if(tgtName == NULL)
        tgtName = "0";
        
    
    std::string path = GetDebugLogPath(testname, tgtName, nodea);
    std::fstream strm(path.c_str(), std::ios::out | std::ios::app);
    
    Debug::Logger::CompareLogsToStream(strm, "BASE" ,*baselog,  "SIMD" , *simdlog);

    //Clear out logs
    baselog->Clear();
    simdlog->Clear();
#endif

}


template<typename TESTCLASS, typename NODETYPE>
static bool TestNode()
{
    //Create instance of test class
    std::unique_ptr<TESTCLASS> testclass(new TESTCLASS());

    //Get test data
    std::vector<TestingBase::TestData> *    testData = testclass->GetTestData();
    if((testData == NULL) || testData->empty())
    {
        printf(" No Test Data Available for %s !! ", testclass->GetName());
        return false;
    }

    //Generate samples for all tests
    testclass->GenerateTestSamples(*testData);

    //TODO: Test changes in sample rate and/or block size
    //For now we just use the values from the first test
    const float samplerate = (*testData)[0].sampleRate;
    const size_t blockSize = (*testData)[0].blockSize;

    printf("\n==========================================\n%s : %s\n==========================================\n", TypeName<NODETYPE>::Get(),  testclass->GetName());

    try
    {
        //Run the tests one after the other on the same instances of the node
        //Repeat for each supported SIMD target
        //Run the same test against all SIMD targets
        bool previousTargetRanTests = false;
        for(int target = 0; target < 64; ++target)
        {
            //Create the SIMD version of the dsp node by passing the current target
            std::unique_ptr<NODETYPE> node(dynamic_cast<NODETYPE *>(testclass->CreateNode(target)));
            if(node == NULL)
            {
                printf(" Failed to create node for target %d ", target);
                return false;
            }

            //On the base version, turn off SIMD. We do this by passing -1 as the target.
            //This gives us something to compare against.
            std::unique_ptr<NODETYPE> basenode(dynamic_cast<NODETYPE *>(testclass->CreateNode(-1)));
            if(node == NULL)
            {
                printf(" Failed to create base node for ");
                return false;
            }

            //Get generic interface
            dsp_primitives::IPrimitiveNode * primitiveIFace = node.get();
            dsp_primitives::IPrimitiveNode * basePrimitiveIFace = basenode.get();


            //Set sample rate and block size.  
            //By calling 'prepare' on the node, it will initialise the SIMD mechanism if enabled (target != -1)
            primitiveIFace->prepare(samplerate, static_cast<int>(blockSize));
            basePrimitiveIFace->prepare(samplerate, static_cast<int>(blockSize));

            //Call the test 'after prepare' method, to perform any action after prepare() has been called,
            //but before any tests are performed
            testclass->AfterPrepare(primitiveIFace);
            testclass->AfterPrepare(basePrimitiveIFace);

            //Check for Highway error code to see if there were problems with the SIMD initialisation
            //Under normal use, it will silently default to the base implementation, but we want to check 
            //that we are comparing an SIMD version against the base.
            int errcode = node->getHighwayErrorCode();
            bool nextTest = false;
            if(errcode != 0)
            {
                switch(errcode)
                {
                    case 1:
                        //Out of targets to test - move to the next test
                        nextTest = true;
                        break;

                    case 2:
                        printf("Target %d : not compiled in\n", target);
                        previousTargetRanTests = false;
                        continue; //use continue to try the next target

                    case 3:
                        printf("Target %d : not supported by CPU\n", target);
                        previousTargetRanTests = false;
                        continue; //use continue to try the next target

                    case 4:
                        printf("Target %d : Disabled in build\n", target);
                        previousTargetRanTests = false;
                        continue; //use continue to try the next target

                    default:
                        printf("Target %d : Unknown highway error code %d\n", target, errcode);
                        return false;
                }

                if(nextTest)
                    break; //break the target loop to resume the outter test data loop
            }

            const char * tgtname = node->getHighwayImplementationTargetName();
            if(tgtname == NULL)
            {
                printf("TARGET %d NOT AVAILABLE\n", target);
                return false;
            }

            if(!previousTargetRanTests)
                printf("------------------------------------------------------------------------\n");

            printf("Target %d : %s \n", target, tgtname);

            std::chrono::nanoseconds baseTotalTime = std::chrono::nanoseconds::zero();
            std::chrono::nanoseconds simdTotalTime = std::chrono::nanoseconds::zero();
            float maxDiff = 0.0f;
            size_t totalTestSamples = 0;
            for(auto & test : *testData)
            {
                printf("   Test %s ", test.name.c_str());

                //Delete old log
                std::string logpath = GetDebugLogPath(test.name.c_str(), tgtname, basePrimitiveIFace);
                std::remove(logpath.c_str());

                //Don't log until this total number of samples processed (Debugging)
                //SetLogStart(*testclass, basePrimitiveIFace, primitiveIFace, 1193200);

                if(test.resetInstances)
                {
                    printf(" (reset instance) ");
                    
                    //Call the test 'reset' method on the node (using the test class to do so)
                    testclass->ResetNode(primitiveIFace);
                    testclass->ResetNode(basePrimitiveIFace);
                }

                //Init results
                test.baseResult[tgtname].reset();
                test.simdResult[tgtname].reset();
                test.simdDurations[tgtname] = std::chrono::nanoseconds::zero();
                test.baseTestDuration[tgtname] = std::chrono::nanoseconds::zero();

                //Configure both the base and SIMD nodes
                if(!testclass->ConfigureNode(primitiveIFace, test))
                {
                    printf("CONFIGURE FAILED! ");
                    return false;
                }

                if(!testclass->ConfigureNode(basePrimitiveIFace, test))
                {
                    printf("BASE CONFIGURE FAILED! ");
                    return false;
                }

                //work out how many samples to process
                size_t totalNumSamples = 0;
                for(const auto & bus : test.busses)
                {
                    size_t ts = 0;
                    for(const auto & w : bus.waves)
                    {
                        ts += w.numSamples;
                    }

                    if((totalNumSamples == 0) || (ts < totalNumSamples))
                        totalNumSamples = ts;
                }

                if(totalNumSamples == 0)
                {
                    printf("ERROR: Test Data resulted in zero samples! ");
                    return false;
                }

                const int numChannels = (test.mode == TestingBase::StereoMode_Mono) ? 1 : 2;

                //Allocate buffer for output
                std::unique_ptr<juce::AudioBuffer<float>> outputbuffer(new juce::AudioBuffer<float>(numChannels, static_cast<int>(totalNumSamples)));

                //Allocate buffer for base output
                std::unique_ptr<juce::AudioBuffer<float>> baseOutputbuffer(new juce::AudioBuffer<float>(numChannels, static_cast<int>(totalNumSamples)));

                //Process samples in blocks
                const size_t numBusses = test.wavedata.size();
                size_t remain = totalNumSamples;
                size_t offset = 0;
                while(remain > 0)
                {
                    const size_t blockSampleCount = (remain > blockSize) ? blockSize : remain;

                    //Clear logs
                    EraseLog(*testclass, basePrimitiveIFace, primitiveIFace);

                    //Generate input view
                    std::vector<dsp_primitives::AudioBufferView> inputViews(test.wavedata.size());
                    std::vector<const float *> inputPtrs(test.wavedata.size() * numChannels);
                    size_t inputIdx = 0;
                    size_t ptridx = 0;
                    for(const auto & buf : test.wavedata)
                    {
                        inputViews[inputIdx].numChannels = numChannels;
                        inputViews[inputIdx].numSamples = static_cast<int>(blockSampleCount);
                        const float * const * origInPtrs = buf->getArrayOfReadPointers();
                        for(int c = 0; c < numChannels; ++c)
                        {
                            inputPtrs[ptridx] = &origInPtrs[c][offset];
                            ++ptridx;
                        }

                        inputViews[inputIdx].channelData = &inputPtrs[ptridx - numChannels];
                        ++inputIdx;
                    }

                    //Generate output view
                    std::vector<dsp_primitives::WritableAudioBufferView> outputViews(1);
                    std::vector<dsp_primitives::WritableAudioBufferView> baseOutputViews(1);
                    std::vector<float *> outputPtrs(numChannels);
                    std::vector<float *> baseOutputPtrs(numChannels);
                    outputViews[0].numChannels = numChannels;
                    outputViews[0].numSamples = static_cast<int>(blockSampleCount);
                    baseOutputViews[0].numChannels = numChannels;
                    baseOutputViews[0].numSamples = static_cast<int>(blockSampleCount);
                    float * const * origOutPtrs = outputbuffer->getArrayOfWritePointers();
                    float * const * origBaseOutPtrs = baseOutputbuffer->getArrayOfWritePointers();
                    for(int c = 0; c < numChannels; ++c)
                    {
                        outputPtrs[c] = &origOutPtrs[c][offset];
                        baseOutputPtrs[c] = &origBaseOutPtrs[c][offset];
                    }

                    outputViews[0].channelData = outputPtrs.data();
                    baseOutputViews[0].channelData = baseOutputPtrs.data();

                    //Process base implementation
                    auto start = std::chrono::high_resolution_clock::now();;
                    basePrimitiveIFace->process(inputViews, baseOutputViews, static_cast<int>(blockSampleCount));
                    auto end = std::chrono::high_resolution_clock::now();
                    test.baseTestDuration[tgtname] += (end - start);
                    baseTotalTime += (end - start);

                    //Process simd implementation
                    start = std::chrono::high_resolution_clock::now();
                    primitiveIFace->process(inputViews, outputViews, static_cast<int>(blockSampleCount));
                    end = std::chrono::high_resolution_clock::now();
                    test.simdDurations[tgtname] += (end - start);
                    simdTotalTime += (end - start);

                    //collect results for current block
                    if(test.baseResult[tgtname].get() == NULL)
                        test.baseResult[tgtname].reset(new std::vector<std::vector<float>>(numChannels));

                    if(test.simdResult[tgtname].get() == NULL)
                        test.simdResult[tgtname].reset(new std::vector<std::vector<float>>(numChannels));

                    //Write log
                    WriteDebugLog(test.name.c_str(), tgtname, *testclass, basePrimitiveIFace, primitiveIFace);

                    //Check data
                    for(int c = 0; c < numChannels; ++c)
                    {
                        std::vector<float> & result = (*test.baseResult[tgtname])[c];
                        const size_t cursz = result.size();
                        
                        //Compare with base
                        for(size_t x = 0; x < blockSampleCount; ++x)
                        {
                            if(!compareFloats(outputPtrs[c][x], baseOutputPtrs[c][x], test.tolerance))
                            {
                                printf(" - Fail : Sample %zu (%zu) Channel %u : Expected %g, got %g", x + cursz, x + totalTestSamples, c, baseOutputPtrs[c][x], outputPtrs[c][x]);
                                return false;
                            }

                            const float diff = fabsf(outputPtrs[c][x] - baseOutputPtrs[c][x]);
                            if(diff > maxDiff)
                                maxDiff = diff;
                        }

                        result.resize(cursz + blockSampleCount);
                        memcpy(&result[cursz], outputPtrs[c], sizeof(float) * blockSampleCount);
                    }

                    offset += blockSampleCount;
                    remain -= blockSampleCount;
                    totalTestSamples += blockSampleCount;
                }

                test.maxResultDifference[tgtname] = maxDiff;

                const long long baseNs = static_cast<long long>(std::chrono::duration_cast<std::chrono::nanoseconds>(test.baseTestDuration[tgtname]).count());
                const long long simdNs = static_cast<long long>(std::chrono::duration_cast<std::chrono::nanoseconds>(test.simdDurations[tgtname]).count());
                printf("- Pass - Base: %lld ns   SIMD: %lld ns   Speed:%f   MaxDiff:%f\n", baseNs, simdNs, static_cast<float>(baseNs) / static_cast<float>(simdNs), maxDiff);
            }

            previousTargetRanTests = true; //Prevents double line being printed

            const long long totalBaseNs = static_cast<long long>(std::chrono::duration_cast<std::chrono::nanoseconds>(baseTotalTime).count());
            const long long totalSimdNs = static_cast<long long>(std::chrono::duration_cast<std::chrono::nanoseconds>(simdTotalTime).count());
            printf("\nAverage Time: Base: %lld ns   SIMD: %lld ns   Speed:%f\n", totalBaseNs, totalSimdNs, static_cast<float>(totalBaseNs) / static_cast<float>(totalSimdNs));

            printf("------------------------------------------------------------------------\n");
        }
    }
    catch(const std::exception & ex)
    {
        printf(" - EXCEPTION WAS RAISED: %s", ex.what());
    }
  

    return true;
}


int main(int argc, const char ** argv)
{   
    
    if(!TestNode<TestADSRNode, dsp_primitives::ADSREnvelopeNode>())
    {
        printf(" - FAILED!");
        return -1;
    }
    
    if(!TestNode<TestBitcrusherNode, dsp_primitives::BitCrusherNode>())
    {
        printf(" - FAILED!");
        return -1;
    }

    if(!TestNode<TestFilterNode, dsp_primitives::FilterNode>())
    {
        printf(" - FAILED!");
        return -1;
    }
   
    if(!TestNode<TestGainNode, dsp_primitives::GainNode>())
    {
        printf(" - FAILED!");
        return -1;
    }

    
    if(!TestNode<TestMixerNode, dsp_primitives::MixerNode>())
    {
        printf(" - FAILED!");
        return -1;
    }
    

    if(!TestNode<TestOscillatorNode, dsp_primitives::OscillatorNode>())
    {
        printf(" - FAILED!");
        return -1;
    }

    return 0;
}

#pragma once
#include "TestingBase.h"

#include <dsp/core/nodes/ADSREnvelopeNode.h>
#include <manifold/debugging/Logging.h>

class TestADSRNode : public TestingBase
{
public:
    virtual const char * GetName() const override
    {
        return "ADSREnvelopeNode";
    }

    virtual dsp_primitives::IPrimitiveNode * CreateNode(int target) const override;

    virtual void ResetNode(dsp_primitives::IPrimitiveNode * node) override;

    virtual Debug::Logger * GetLog(dsp_primitives::IPrimitiveNode * node)  override;

    virtual std::vector<TestData> * GetTestData() override;

    //Configure the specified node. Test specific because of the different parameters that each node has.
    virtual bool ConfigureNode(dsp_primitives::IPrimitiveNode * node, const TestData & parameters) override;
};
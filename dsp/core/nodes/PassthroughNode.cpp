#include "dsp/core/nodes/PassthroughNode.h"

namespace dsp_primitives {

PassthroughNode::PassthroughNode(int numChannels,
                                 HostInputMode hostInputMode)
    : numChannels_(numChannels), hostInputMode_(hostInputMode) {}

void PassthroughNode::prepare(double sampleRate, int maxBlockSize) {
    (void)sampleRate;
    (void)maxBlockSize;
}

void PassthroughNode::process(const std::vector<AudioBufferView>& inputs,
                              std::vector<WritableAudioBufferView>& outputs,
                              int numSamples) {
    for (int ch = 0; ch < numChannels_ && ch < static_cast<int>(inputs.size()) && ch < static_cast<int>(outputs.size()); ++ch) {
        for (int i = 0; i < numSamples; ++i) {
            outputs[ch].setSample(ch, i, inputs[ch].getSample(ch, i));
        }
    }
}

} // namespace dsp_primitives
